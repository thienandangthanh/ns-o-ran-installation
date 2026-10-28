#!/usr/bin/env python3
"""pacer.py: the lock-step pacer that ns-3 connects to when run with
--e2Pacing=lockstep. ns-3 is the only time base and the only party that
blocks; the pacer grants every step.

ns-3 -> pacer: ready{seq, simTimeNs, buffered}, steps{seq} (every agent has sent
step seq, so has read sample seq), controlRx{seq, viaNodeId, ctlId, buffered},
applied{seq, controls, late}, controlAck{...} (for pacer-injected controls),
stopping{seq}, end{seq}, abort{seq}.
pacer -> ns-3: go{seq}, abort{reason}, control{nodeId, ctlId, imsi,
targetCellId, afterSeq}, endAck.

Per `ready` k the pacer looks k up in the schedule:
  - no entry: `go` k at once (every step that cannot produce a control);
  - "inject": send those control lines (scripted lock-step, Fallback-1), then go;
  - "trigger" (with "goBeforeTrigger": true the pacer sends `go` k first, so the control misses
    barrier k and is refused late at k + 1): wait for `steps` k (before it an agent may not have read sample
    k and would stamp a control afterSeq k-1), run the command (an rc gRPC
    call, a TS xApp trigger), then wait until ns-3 has reported "expect"
    controlRx lines for k, at most T_ctl from the trigger (else abort); with
    "absence": true it waits W after the trigger and requires exactly "expect"
    controls (statistical negatives). A command still running at T_ctl aborts.
  - "triggers": [{"cmd", "expect"}, ...] (several controls in one step, sent in this order): wait for
    `steps` k, then run each command in turn and wait until ns-3 has reported that command's controlRx
    lines before the next one starts (rc sends every control in its own goroutine, so two quick calls
    could reach the agent in either order and swap its ctlIds); each control's L is measured from its
    own command's start, each within T_ctl.
  - "prepare": {"cmd", "timeoutS" (default 30), "mayFail"} (optional, with or without a trigger): after any
    "inject", wait for `steps` k, then run the command before the trigger's t0, so its wall time never counts
    toward L or W (the R3′ Influx certification, predictor and stub load). A non-zero exit or a timeout aborts
    the run naming "prepare"; with "mayFail" it is recorded (prepareRc, prepareWallS) and the step goes on.
    An entry with only "prepare" is followed by `go` k.
At `stopping` it sends the schedule's "late" controls (forced-late case: ns-3
answers them refused/late), runs the schedule's "stopTrigger" if any, and then
endAck. "stopTrigger": {"cmd", "confirm", "timeoutS"} sends a control after the
final barrier and holds endAck until "confirm" exits 0 (it waits for the agent to
have forwarded the control), all within timeoutS (keep it under ns-3's gate
timeout); the result goes to pacer-summary.json "stopTrigger".

--replay LEDGER builds the schedule from a control ledger: every line is
injected at its rxSeq with its viaNodeId, ctlId, imsi, targetCell and
afterSeq, so a replay reproduces the run without the RIC (a line refused late
mid-run, afterSeq < rxSeq, is injected at its rxSeq and refused again; one
refused late at the stop is sent at the stop handshake).

Outputs in --out: pacer-log.jsonl (every message with wall time) and
pacer-summary.json (per trigger step: L of each control = trigger start ->
controlRx; the slack against T_ctl or W; acks of injected controls; abort).
Exit 0 when ns-3 ended without an abort, 3 on an abort, 2 on a usage error.

usage: pacer.py --port P --out DIR [--schedule FILE | --replay LEDGER]
                [--t-ctl S] [--w S] [--accept-timeout S]
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time


def load_schedule(args):
    if args.replay:
        steps, late = {}, []
        with open(args.replay) as f:
            for line in f:
                m = json.loads(line)
                if m.get("type") == "ledgerHeader":
                    continue
                c = {"nodeId": m["viaNodeId"], "ctlId": m["ctlId"], "imsi": m["imsi"],
                     "targetCellId": m["targetCell"], "afterSeq": m["afterSeq"]}
                if m["cause"] == "late" and m["afterSeq"] >= m["rxSeq"]:
                    late.append(c)  # arrived after the last barrier: replayed at the stop handshake
                else:
                    steps.setdefault(str(m["rxSeq"]), {"inject": []})["inject"].append(c)
        return {"steps": steps, "late": late}
    if args.schedule:
        with open(args.schedule) as f:
            s = json.load(f)
        s.setdefault("steps", {})
        s.setdefault("late", [])
        return s
    return {"steps": {}, "late": []}


class Pacer:
    def __init__(self, conn, out_dir, schedule, t_ctl, w):
        self.conn = conn
        self.buf = b""
        self.log = open(os.path.join(out_dir, "pacer-log.jsonl"), "w")
        self.out_dir = out_dir
        self.schedule = schedule
        self.t_ctl = t_ctl
        self.w = w
        self.rx = {}         # seq -> [(wall, msg)] controlRx
        self.steps_in = set()  # seqs whose `steps` arrived
        self.ready_q = []      # `ready` seen while a trigger waited (goBeforeTrigger steps)
        self.summary = {"tCtlS": t_ctl, "wS": w, "steps": {}, "acks": [], "applied": {},
                        "readyCount": 0, "aborted": False, "abortStep": None, "ended": False}

    def note(self, direction, msg):
        self.log.write(json.dumps({"t": time.time(), "dir": direction, "msg": msg}) + "\n")
        self.log.flush()

    def send(self, msg):
        self.note("tx", msg)
        self.conn.sendall((json.dumps(msg, separators=(",", ":")) + "\n").encode())

    def recv(self, timeout):
        """One message, or None after timeout seconds."""
        deadline = time.time() + timeout
        while b"\n" not in self.buf:
            left = deadline - time.time()
            if left <= 0:
                return None
            self.conn.settimeout(left)
            try:
                chunk = self.conn.recv(65536)
            except socket.timeout:
                return None
            if not chunk:
                raise EOFError
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        msg = json.loads(line)
        self.note("rx", msg)
        return msg

    def handle_async(self, msg):
        """Messages that can arrive at any time; True when the run is over."""
        t = msg.get("type")
        if t == "ready":
            self.ready_q.append(msg)
        elif t == "steps":
            self.steps_in.add(msg["seq"])
        elif t == "controlRx":
            self.rx.setdefault(msg["seq"], []).append((time.time(), msg))
        elif t == "controlAck":
            self.summary["acks"].append(msg)
        elif t == "applied":
            self.summary["applied"][str(msg["seq"])] = msg["controls"]
        elif t == "stopping":
            for c in self.schedule.get("late", []):
                self.send(dict({"type": "control", "afterSeq": msg["seq"]}, **c))
            self.summary["lateSent"] = len(self.schedule.get("late", []))
            if self.schedule.get("stopTrigger"):
                self.summary["stopTrigger"] = self.stop_trigger(self.schedule["stopTrigger"], msg["seq"])
            self.send({"type": "endAck"})
        elif t == "end":
            self.summary["ended"] = True
            return True
        elif t == "abort":
            self.summary["aborted"] = True
            self.summary["abortStep"] = msg.get("seq")
            return True
        return False

    def wait_steps(self, seq, deadline):
        """Waits for `steps` seq; True when the run is over."""
        while seq not in self.steps_in and time.time() < deadline:
            msg = self.recv(deadline - time.time())
            if msg is not None and self.handle_async(msg):
                return True
        return False

    def stop_trigger(self, st, seq):
        """Runs the stop trigger's command, then its confirm command, within timeoutS in all."""
        deadline = time.time() + float(st.get("timeoutS", 6))
        rec = {"seq": seq, "cmdRc": None, "confirmRc": None}
        self.note("pacer", {"type": "stopTrigger", "seq": seq, "cmd": st["cmd"]})
        for key, cmd in (("cmd", st["cmd"]), ("confirm", st.get("confirm"))):
            if not cmd:
                continue
            try:
                p = subprocess.run(cmd, capture_output=True, text=True, timeout=max(0.1, deadline - time.time()))
                rec[key + "Rc"] = p.returncode
                rec[key + "Out"] = (p.stdout + p.stderr)[-400:]
            except subprocess.TimeoutExpired:
                rec[key + "Out"] = "still running at the stop trigger's timeout"
                break
            if p.returncode != 0:
                break
        rec["wallS"] = round(time.time() - (deadline - float(st.get("timeoutS", 6))), 6)
        rec["ok"] = rec["cmdRc"] == 0 and (not st.get("confirm") or rec["confirmRc"] == 0)
        return rec

    def step_triggers(self, seq, rec, trigs):
        """Several triggers in one step, one at a time; True when the run is over."""
        if self.wait_steps(seq, time.time() + self.t_ctl):
            return True
        if seq not in self.steps_in:
            self.summary["steps"][str(seq)] = rec
            self.abort("step %d: no `steps` from ns-3 within %s s" % (seq, self.t_ctl))
            return False
        want, rec["L"], rec["triggerRcs"], rec["window"] = 0, [], [], "T_ctl"
        for i, trig in enumerate(trigs):
            self.note("pacer", {"type": "trigger", "seq": seq, "index": i, "cmd": trig["cmd"]})
            t0 = time.time()
            try:
                p = subprocess.run(trig["cmd"], capture_output=True, text=True, timeout=self.t_ctl)
            except subprocess.TimeoutExpired as ex:
                rec["triggerRcs"].append(None)
                rec["triggerOut"] = "still running at T_ctl: %r" % (ex.cmd,)
                self.summary["steps"][str(seq)] = rec
                self.abort("step %d: trigger %d still running at T_ctl %s s" % (seq, i, self.t_ctl))
                return False
            rec["triggerRcs"].append(p.returncode)
            rec["triggerOut"] = (p.stdout + p.stderr)[-400:]
            want += trig.get("expect", 1)
            if self.wait_controls(seq, want, t0 + self.t_ctl):
                return True
            got = self.rx_from(seq)
            if len(got) != want or p.returncode != 0:
                rec["controls"] = len(got)
                self.summary["steps"][str(seq)] = rec
                self.abort("step %d: trigger %d: %d control(s) within T_ctl (want %d), trigger rc %d" % (
                    seq, i, len(got), want, p.returncode))
                return False
            rec["L"] += [round(t - t0, 6) for t, _ in got[want - trig.get("expect", 1):want]]
        got = self.rx_from(seq)
        rec["controls"] = len(got)
        rec["rxOrder"] = [[m.get("viaNodeId"), m.get("ctlId")] for _, m in got]
        rec["triggerRc"] = 0
        rec["slackS"] = round(self.t_ctl - max(rec["L"]), 6) if rec["L"] else None
        self.summary["steps"][str(seq)] = rec
        self.send({"type": "go", "seq": seq})
        return False

    def run_prepare(self, seq, rec, prep):
        """Waits for `steps` seq, then runs the prepare command before any trigger's t0, so its wall time
        never counts toward L or W. Returns (run over, may continue); a failed or timed-out prepare
        aborts the run unless "mayFail" (then it is recorded and the step goes on)."""
        if self.wait_steps(seq, time.time() + self.t_ctl):
            return True, False
        if seq not in self.steps_in:
            self.summary["steps"][str(seq)] = rec
            self.abort("step %d: no `steps` from ns-3 within %s s" % (seq, self.t_ctl))
            return False, False
        self.note("pacer", {"type": "prepare", "seq": seq, "cmd": prep["cmd"]})
        t0 = time.time()
        try:
            p = subprocess.run(prep["cmd"], capture_output=True, text=True, timeout=float(prep.get("timeoutS", 30)))
            rec["prepareRc"], rec["prepareOut"] = p.returncode, (p.stdout + p.stderr)[-400:]
        except subprocess.TimeoutExpired:
            rec["prepareRc"], rec["prepareOut"] = None, "still running at its timeout %s s" % prep.get("timeoutS", 30)
        rec["prepareWallS"] = round(time.time() - t0, 6)
        if rec["prepareRc"] == 0 or prep.get("mayFail"):
            return False, True
        self.summary["steps"][str(seq)] = rec
        self.abort("step %d: prepare failed (rc %s): %s" % (seq, rec["prepareRc"], rec["prepareOut"][-200:]))
        return False, False

    def abort(self, reason):
        self.send({"type": "abort", "reason": reason})
        self.summary["pacerAbortReason"] = reason

    def rx_from(self, seq):
        """controlRx lines tagged seq or later (a goBeforeTrigger control arrives tagged seq + 1)."""
        return [x for k, v in sorted(self.rx.items()) if k >= seq for x in v]

    def wait_controls(self, seq, expect, deadline):
        while len(self.rx_from(seq)) < expect and time.time() < deadline:
            msg = self.recv(deadline - time.time())
            if msg is not None and self.handle_async(msg):
                return True
        return False

    def step(self, seq):
        entry = self.schedule["steps"].get(str(seq))
        if entry is None:
            self.send({"type": "go", "seq": seq})
            return False
        rec = {"seq": seq}
        for c in entry.get("inject", []):
            self.send(dict({"type": "control"}, **c))
        rec["injected"] = len(entry.get("inject", []))
        if entry.get("prepare"):
            over, ok = self.run_prepare(seq, rec, entry["prepare"])
            if over:
                return True
            if not ok:
                return False
        if entry.get("triggers"):
            return self.step_triggers(seq, rec, entry["triggers"])
        trig = entry.get("trigger")
        if trig:
            expect = entry.get("expect", 0)
            if self.wait_steps(seq, time.time() + self.t_ctl):
                return True
            if seq not in self.steps_in:
                self.summary["steps"][str(seq)] = rec
                self.abort("step %d: no `steps` from ns-3 within %s s" % (seq, self.t_ctl))
                return False
            went = bool(entry.get("goBeforeTrigger"))
            if went:
                # the control must miss barrier `seq`: it is sent after `go`, so the agent stamps
                # afterSeq = seq and ns-3 refuses it late at the next barrier (never the final one)
                self.send({"type": "go", "seq": seq})
            self.note("pacer", {"type": "trigger", "seq": seq, "cmd": trig["cmd"]})
            t0 = time.time()
            try:
                p = subprocess.run(trig["cmd"], capture_output=True, text=True, timeout=self.t_ctl)
                rec["triggerRc"] = p.returncode
                rec["triggerOut"] = (p.stdout + p.stderr)[-400:]
            except subprocess.TimeoutExpired as ex:
                rec["triggerRc"] = None
                rec["triggerOut"] = "still running at T_ctl: %r" % (ex.cmd,)
                self.summary["steps"][str(seq)] = rec
                self.abort("step %d: trigger still running at T_ctl %s s" % (seq, self.t_ctl))
                return False
            if entry.get("absence"):
                over = self.wait_controls(seq, expect + 1, t0 + self.w)
                rec["window"] = "W"
            else:
                over = self.wait_controls(seq, expect, t0 + self.t_ctl)
                rec["window"] = "T_ctl"
            if over:
                return True
            got = self.rx_from(seq)
            rec["controls"] = len(got)
            rec["L"] = [round(t - t0, 6) for t, _ in got]
            budget = self.w if entry.get("absence") else self.t_ctl
            complete = len(got) == expect and p.returncode == 0
            # slack only for a complete step: an aborted or empty one has no measured latency
            rec["slackS"] = round(budget - max(rec["L"] or [0]), 6) if complete and rec["L"] else None
            self.summary["steps"][str(seq)] = rec
            if not complete:
                self.abort("step %d: %d control(s) within %s (want %d), trigger rc %d" % (
                    seq, len(got), rec["window"], expect, p.returncode))
                return False
            if went:
                return False
        self.summary["steps"].setdefault(str(seq), rec)
        self.send({"type": "go", "seq": seq})
        return False

    def run(self):
        try:
            while True:
                msg = self.ready_q.pop(0) if self.ready_q else self.recv(3600)
                if msg is None:
                    self.summary["error"] = "ns-3 silent for an hour"
                    break
                if msg.get("type") == "ready":
                    self.summary["readyCount"] += 1
                    if self.step(msg["seq"]):
                        break
                elif self.handle_async(msg):
                    break
        except EOFError:
            self.summary["eof"] = True
        self.log.close()
        slack = {"T_ctl": None, "W": None}
        for rec in self.summary["steps"].values():
            if rec.get("slackS") is not None:
                key = "W" if rec.get("window") == "W" else "T_ctl"
                slack[key] = rec["slackS"] if slack[key] is None else min(slack[key], rec["slackS"])
        self.summary["minSlackS"] = slack  # over complete trigger steps only
        with open(os.path.join(self.out_dir, "pacer-summary.json"), "w") as f:
            json.dump(self.summary, f, indent=2)
        return 3 if self.summary["aborted"] or not self.summary["ended"] else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--schedule")
    ap.add_argument("--replay")
    ap.add_argument("--t-ctl", type=float, default=30.0)
    ap.add_argument("--w", type=float, default=1.0)
    ap.add_argument("--accept-timeout", type=float, default=600.0)
    args = ap.parse_args()
    if args.schedule and args.replay:
        ap.error("--schedule and --replay are exclusive")
    os.makedirs(args.out, exist_ok=True)
    schedule = load_schedule(args)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(1)
    srv.settimeout(args.accept_timeout)
    print("READY", flush=True)
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        print("pacer: ns-3 never connected", file=sys.stderr)
        return 3
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    return Pacer(conn, args.out, schedule, args.t_ctl, args.w).run()


if __name__ == "__main__":
    sys.exit(main())

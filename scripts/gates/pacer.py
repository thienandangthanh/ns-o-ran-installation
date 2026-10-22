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
  - "trigger": wait for `steps` k (before it an agent may not have read sample
    k and would stamp a control afterSeq k-1), run the command (an rc gRPC
    call, a TS xApp trigger), then wait until ns-3 has reported "expect"
    controlRx lines for k, at most T_ctl from the trigger (else abort); with
    "absence": true it waits W after the trigger and requires exactly "expect"
    controls (statistical negatives). A command still running at T_ctl aborts.
At `stopping` it sends the schedule's "late" controls (forced-late case: ns-3
answers them refused/late) and then endAck.

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
        if t == "steps":
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

    def abort(self, reason):
        self.send({"type": "abort", "reason": reason})
        self.summary["pacerAbortReason"] = reason

    def wait_controls(self, seq, expect, deadline):
        while len(self.rx.get(seq, [])) < expect and time.time() < deadline:
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
        trig = entry.get("trigger")
        if trig:
            expect = entry.get("expect", 0)
            if self.wait_steps(seq, time.time() + self.t_ctl):
                return True
            if seq not in self.steps_in:
                self.summary["steps"][str(seq)] = rec
                self.abort("step %d: no `steps` from ns-3 within %s s" % (seq, self.t_ctl))
                return False
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
            got = self.rx.get(seq, [])
            rec["controls"] = len(got)
            rec["L"] = [round(t - t0, 6) for t, _ in got]
            budget = self.w if entry.get("absence") else self.t_ctl
            rec["slackS"] = round(budget - max(rec["L"] or [0]), 6)
            self.summary["steps"][str(seq)] = rec
            if len(got) != expect or p.returncode != 0:
                self.abort("step %d: %d control(s) within %s (want %d), trigger rc %d" % (
                    seq, len(got), rec["window"], expect, p.returncode))
                return False
        self.summary["steps"].setdefault(str(seq), rec)
        self.send({"type": "go", "seq": seq})
        return False

    def run(self):
        try:
            while True:
                msg = self.recv(3600)
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

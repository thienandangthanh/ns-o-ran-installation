#!/usr/bin/env python3
"""pacer-selftest.py: the pacer against a stub ns-3, no RIC. Exit 0 when every case passes.

Cases: (1) a single "trigger" step (the old path, same summary fields); (2) "triggers" in one step run one at a
time, the second command starting only after the first command's controlRx; (3) a "stopTrigger" holds endAck
until its confirm command exits 0; (4) a confirm that outlives timeoutS is recorded as not ok and endAck still
goes out; (5) a "prepare" runs after `steps` and before the trigger, and its wall time is not in L; (6) a prepare
that exits non-zero aborts the run naming "prepare" and the trigger never runs; (7) a prepare past its timeoutS
aborts; (8) with "mayFail" a failed prepare is recorded and the step goes on; (9) a prepare-only entry is
followed by `go`; (10) --replay puts a line refused late after the last barrier at the stop handshake, and a
line pending at the stop under δ > 0 (and a mid-run late one) at its rxSeq, each with the ueId of its
e2-pacing-log.jsonl record and no imsi (an unknownUe line, imsi 0, too); a ledger line without a record, two
records for one (viaNodeId, ctlId), a record whose targetCellId differs and a record without a ledger line each
make load_schedule fail; (11) an inject with "ueIdFrom" is sent after the step's prepare with the file's ipcUeId,
and a missing file aborts naming "ueIdFrom". A trigger command creates a marker file; the stub answers each new marker with one controlRx.
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time

PACER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pacer.py")


def touch(path):
    return [sys.executable, "-c", "open(%r, 'w').close()" % path]


def stub(port, tmp, seqs, markers):
    """Plays ns-3: ready/steps per seq, one controlRx per marker that appears, stopping, end. Returns a trace."""
    for _ in range(100):
        try:
            c = socket.create_connection(("127.0.0.1", port))
            break
        except OSError:
            time.sleep(0.05)
    buf, trace, ctl = b"", [], {}

    def send(m):
        c.sendall((json.dumps(m) + "\n").encode())
        trace.append((time.time(), "tx", m))

    def poll(timeout):
        nonlocal buf
        c.settimeout(timeout)
        try:
            chunk = c.recv(65536)
        except socket.timeout:
            return []
        buf += chunk
        out = []
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            m = json.loads(line)
            trace.append((time.time(), "rx", m))
            out.append(m)
        return out

    seen = set()
    aborted = False
    for seq in seqs:
        if aborted:
            break
        send({"type": "ready", "seq": seq, "simTimeNs": seq * 100000000, "buffered": 0})
        send({"type": "steps", "seq": seq})
        done = False
        while not done:
            for name, node in markers.get(seq, []):
                if name not in seen and os.path.exists(os.path.join(tmp, name)):
                    seen.add(name)
                    ctl[node] = ctl.get(node, 0) + 1
                    send({"type": "controlRx", "seq": seq, "viaNodeId": node, "ctlId": ctl[node], "buffered": 1})
            for m in poll(0.02):
                if m.get("type") == "go" and m["seq"] == seq:
                    done = True
                elif m.get("type") == "abort":  # ns-3 answers a pacer abort with its own abort and stops
                    send({"type": "abort", "seq": seq})
                    done = aborted = True
    if aborted:
        c.close()
        return trace, time.time()
    send({"type": "stopping", "seq": seqs[-1]})
    t_stop = time.time()
    while not any(m.get("type") == "endAck" for _, d, m in trace if d == "rx"):
        poll(0.1)
        if time.time() - t_stop > 20:
            break
    send({"type": "end", "seq": seqs[-1]})
    c.close()
    return trace, t_stop


def run_case(name, schedule, seqs, markers, port):
    tmp = tempfile.mkdtemp(prefix="pacer-selftest-")
    sched = json.loads(json.dumps(schedule).replace("@TMP@", tmp))
    sp = os.path.join(tmp, "schedule.json")
    json.dump(sched, open(sp, "w"))
    out = os.path.join(tmp, "out")
    p = subprocess.Popen([sys.executable, "-I", PACER, "--port", str(port), "--out", out, "--schedule", sp,
                          "--t-ctl", "5"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    p.stdout.readline()  # READY
    trace, t_stop = stub(port, tmp, seqs, markers)
    rc = p.wait(timeout=30)
    summary = json.load(open(os.path.join(out, "pacer-summary.json")))
    return rc, summary, trace, t_stop, tmp


def main():
    problems = []
    # (1) the old single-trigger path
    rc, s, _, _, _ = run_case("single", {"steps": {"2": {"trigger": {"cmd": touch("@TMP@/a")}, "expect": 1}}},
                              [0, 1, 2, 3], {2: [("a", 1)]}, 38591)
    r = s["steps"].get("2", {})
    if rc != 0 or r.get("controls") != 1 or r.get("triggerRc") != 0 or len(r.get("L", [])) != 1 or r.get("slackS") is None \
            or r.get("window") != "T_ctl" or "triggers" in r:
        problems.append("single trigger: rc %s step %r" % (rc, r))
    # (2) two triggers in one step, strictly one after the other
    sched = {"steps": {"2": {"triggers": [{"cmd": touch("@TMP@/b1"), "expect": 1}, {"cmd": touch("@TMP@/b2"), "expect": 1}]}}}
    rc, s, trace, _, tmp = run_case("multi", sched, [0, 1, 2, 3], {2: [("b1", 2), ("b2", 2)]}, 38592)
    r = s["steps"].get("2", {})
    rx1 = min(t for t, d, m in trace if d == "tx" and m.get("type") == "controlRx")
    b2 = os.path.getmtime(os.path.join(tmp, "b2"))
    if rc != 0 or r.get("controls") != 2 or r.get("rxOrder") != [[2, 1], [2, 2]] or r.get("triggerRcs") != [0, 0] \
            or len(r.get("L", [])) != 2 or r.get("slackS") is None:
        problems.append("multi trigger: rc %s step %r" % (rc, r))
    if b2 < rx1:
        problems.append("multi trigger: the second command ran before the first control's controlRx")
    # (3) the stop trigger holds endAck until confirm exits 0
    sched = {"steps": {}, "stopTrigger": {"cmd": touch("@TMP@/s"), "confirm": [sys.executable, "-c", "import time; time.sleep(1)"],
                                          "timeoutS": 4}}
    rc, s, trace, t_stop, tmp = run_case("stop", sched, [0, 1], {}, 38593)
    st = s.get("stopTrigger", {})
    t_ack = min(t for t, d, m in trace if d == "rx" and m.get("type") == "endAck")
    if rc != 0 or not st.get("ok") or not os.path.exists(os.path.join(tmp, "s")) or t_ack - t_stop < 0.9:
        problems.append("stop trigger: rc %s %r, endAck %.2f s after stopping" % (rc, st, t_ack - t_stop))
    # (4) a confirm that outlives timeoutS: not ok, endAck still sent
    sched = {"steps": {}, "stopTrigger": {"cmd": touch("@TMP@/s"), "confirm": [sys.executable, "-c", "import time; time.sleep(5)"],
                                          "timeoutS": 1}}
    rc, s, trace, t_stop, _ = run_case("stop-timeout", sched, [0, 1], {}, 38594)
    st = s.get("stopTrigger", {})
    acks = [t for t, d, m in trace if d == "rx" and m.get("type") == "endAck"]
    if rc != 0 or st.get("ok") is not False or not acks or acks[0] - t_stop > 3:
        problems.append("stop trigger timeout: rc %s %r" % (rc, st))
    # (5) prepare after `steps`, before the trigger; L excludes its 0.5 s
    sleep_touch = [sys.executable, "-c", "import time; time.sleep(0.5); open(%r, 'w').close()" % "@TMP@/p"]
    sched = {"steps": {"2": {"prepare": {"cmd": sleep_touch, "timeoutS": 3}, "trigger": {"cmd": touch("@TMP@/a")}, "expect": 1}}}
    rc, s, _, _, tmp = run_case("prepare", sched, [0, 1, 2, 3], {2: [("a", 1)]}, 38595)
    r = s["steps"].get("2", {})
    log = [json.loads(l) for l in open(os.path.join(tmp, "out", "pacer-log.jsonl"))]
    i_steps = next((i for i, x in enumerate(log) if x["dir"] == "rx" and x["msg"] == {"type": "steps", "seq": 2}), None)
    i_prep = next((i for i, x in enumerate(log) if x["msg"].get("type") == "prepare"), None)
    i_trig = next((i for i, x in enumerate(log) if x["msg"].get("type") == "trigger"), None)
    order_ok = None not in (i_steps, i_prep, i_trig) and i_steps < i_prep < i_trig and \
        os.path.getmtime(os.path.join(tmp, "p")) <= os.path.getmtime(os.path.join(tmp, "a"))
    if rc != 0 or r.get("prepareRc") != 0 or (r.get("prepareWallS") or 0) < 0.5 or r.get("controls") != 1 \
            or not r.get("L") or max(r["L"]) >= 0.4 or not order_ok:
        problems.append("prepare: rc %s order %s step %r" % (rc, order_ok, r))
    # (6) a failing prepare aborts, naming it, and the trigger never runs
    sched = {"steps": {"2": {"prepare": {"cmd": [sys.executable, "-c", "raise SystemExit(4)"]},
                             "trigger": {"cmd": touch("@TMP@/a")}, "expect": 1}}}
    rc, s, _, _, tmp = run_case("prepare-fail", sched, [0, 1, 2, 3], {2: [("a", 1)]}, 38596)
    if rc != 3 or "prepare" not in (s.get("pacerAbortReason") or "") or os.path.exists(os.path.join(tmp, "a")) \
            or s["steps"].get("2", {}).get("prepareRc") != 4:
        problems.append("prepare failure: rc %s %r" % (rc, s.get("pacerAbortReason")))
    # (7) a prepare past its timeout aborts
    sched = {"steps": {"2": {"prepare": {"cmd": [sys.executable, "-c", "import time; time.sleep(3)"], "timeoutS": 0.5},
                             "trigger": {"cmd": touch("@TMP@/a")}, "expect": 1}}}
    rc, s, _, _, tmp = run_case("prepare-timeout", sched, [0, 1, 2, 3], {2: [("a", 1)]}, 38597)
    if rc != 3 or "prepare" not in (s.get("pacerAbortReason") or "") or os.path.exists(os.path.join(tmp, "a")):
        problems.append("prepare timeout: rc %s %r" % (rc, s.get("pacerAbortReason")))
    # (8) mayFail: recorded, the trigger still runs, no abort
    sched = {"steps": {"2": {"prepare": {"cmd": [sys.executable, "-c", "raise SystemExit(1)"], "mayFail": True},
                             "trigger": {"cmd": touch("@TMP@/a")}, "expect": 1}}}
    rc, s, _, _, _ = run_case("prepare-mayfail", sched, [0, 1, 2, 3], {2: [("a", 1)]}, 38598)
    r = s["steps"].get("2", {})
    if rc != 0 or r.get("prepareRc") != 1 or r.get("controls") != 1 or s.get("aborted"):
        problems.append("prepare mayFail: rc %s step %r" % (rc, r))
    # (9) a prepare-only entry: prepare runs, then go
    rc, s, _, _, tmp = run_case("prepare-only", {"steps": {"1": {"prepare": {"cmd": touch("@TMP@/p")}}}}, [0, 1, 2], {}, 38599)
    r = s["steps"].get("1", {})
    if rc != 0 or r.get("prepareRc") != 0 or not os.path.exists(os.path.join(tmp, "p")) or s.get("aborted"):
        problems.append("prepare-only: rc %s step %r" % (rc, r))
    # (10) the replay schedule: stop-handshake late vs pending at stop under δ > 0 vs late mid-run
    import argparse, importlib.util
    spec = importlib.util.spec_from_file_location("pacer_mod", PACER)
    pm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pm)
    rdir = tempfile.mkdtemp()
    led, plog = os.path.join(rdir, "e2-control-ledger.jsonl"), os.path.join(rdir, "e2-pacing-log.jsonl")

    def ln(ctl, rx, after, rx_ns, ap_ns, cause, imsi=1):
        return {"viaNodeId": 2, "ctlId": ctl, "imsi": imsi, "targetCell": 2, "rxSeq": rx, "afterSeq": after,
                "rxSimTimeNs": rx_ns, "applySimTimeNs": ap_ns, "outcome": "refused", "cause": cause}

    def rec(ctl, after, x2, target=2, node=2):
        return {"type": "control", "v": 1, "viaNodeId": node, "ctlId": ctl, "ueId": {"mEnbUeX2apId": x2, "mnCellId": 1},
                "targetCellId": target, "afterSeq": after}

    lines = [ln(1, 100, 100, 10_000_000_000, 10_000_000_000, "late"),     # after the last barrier
             ln(2, 99, 99, 9_900_000_000, 10_000_000_000, "late"),        # pending at the stop (δ = 150)
             ln(3, 30, 29, 3_000_000_000, 3_000_000_000, "late"),         # missed its barrier mid-run
             ln(4, 40, 40, 4_000_000_000, 4_000_000_000, "unknownUe", 0)]  # an unresolved UE, replayed as sent
    recs = [rec(1, 100, 3), rec(2, 99, 3), rec(3, 29, 3), rec(4, 40, 4095)]
    barrier = {"type": "barrier", "seq": 30}

    def write(ls, rs):
        with open(led, "w") as f:
            f.write(json.dumps({"type": "ledgerHeader", "v": 1, "delta-model": "fixed 150"}) + "\n")
            for x in ls:
                f.write(json.dumps(x) + "\n")
        with open(plog, "w") as f:
            for x in [barrier] + rs:
                f.write(json.dumps(x) + "\n")

    write(lines, recs)
    sc = pm.load_schedule(argparse.Namespace(replay=led, schedule=None))
    got = ([c["ctlId"] for c in sc["late"]], sorted((k, [c["ctlId"] for c in v["inject"]]) for k, v in sc["steps"].items()))
    if got != ([1], [("30", [3]), ("40", [4]), ("99", [2])]):
        problems.append("replay schedule: %r" % (got,))
    sent = sc["late"] + [c for v in sc["steps"].values() for c in v["inject"]]
    want_ue = {r["ctlId"]: r["ueId"] for r in recs}
    if any("imsi" in c or c["ueId"] != want_ue[c["ctlId"]] for c in sent) or len(sent) != 4:
        problems.append("replay controls carry the pacing records' ueId and no imsi: %r" % (sent,))
    for name, ls, rs in (("a ledger line without a pacing record", lines, recs[:3]),
                         ("two pacing records for one (viaNodeId, ctlId)", lines, recs + [rec(4, 40, 4095)]),
                         ("a pacing record whose targetCellId differs", lines, recs[:3] + [rec(4, 40, 4095, target=3)]),
                         ("a pacing record without a ledger line", lines, recs + [rec(1, 20, 5, node=3)])):
        write(ls, rs)
        try:
            pm.load_schedule(argparse.Namespace(replay=led, schedule=None))
            problems.append("replay: %s did not fail load_schedule" % name)
        except pm.ReplayError:
            pass
    write(lines, recs[:3])
    r = subprocess.run([sys.executable, PACER, "--port", "38598", "--out", os.path.join(rdir, "out"), "--replay", led],
                       capture_output=True, text=True, timeout=30)
    if r.returncode != 2 or "READY" in r.stdout:
        problems.append("replay with an unpaired line: exit %s, stdout %r (want 2 before READY)" % (r.returncode, r.stdout))
    # (11) a deferred inject: the prepare writes the UE ID file, the control follows it with that ueId
    ue = {"mEnbUeX2apId": 3, "mnCellId": 1}
    write_ue = [sys.executable, "-c", "import json; json.dump({'ipcUeId': %r}, open(%r, 'w'))" % (ue, "@TMP@/ue.json")]
    ctl = {"nodeId": 3, "ctlId": 1, "ueIdFrom": "@TMP@/ue.json", "targetCellId": 2, "afterSeq": 2}
    rc, s, _, _, tmp = run_case("ue-id-from", {"steps": {"2": {"prepare": {"cmd": write_ue}, "inject": [ctl]}}},
                                [0, 1, 2, 3], {}, 38600)
    log = [json.loads(l) for l in open(os.path.join(tmp, "out", "pacer-log.jsonl"))]
    i_prep = next((i for i, x in enumerate(log) if x["msg"].get("type") == "prepare"), None)
    sent = [(i, x["msg"]) for i, x in enumerate(log) if x["dir"] == "tx" and x["msg"].get("type") == "control"]
    if rc != 0 or len(sent) != 1 or i_prep is None or sent[0][0] < i_prep or sent[0][1].get("ueId") != ue \
            or "ueIdFrom" in sent[0][1]:
        problems.append("ueIdFrom: rc %s sent %r" % (rc, sent))
    rc, s, _, _, _ = run_case("ue-id-from-missing", {"steps": {"2": {"inject": [dict(ctl, ueIdFrom="@TMP@/none.json")]}}},
                              [0, 1, 2, 3], {}, 38601)
    if rc != 3 or "ueIdFrom" not in (s.get("pacerAbortReason") or ""):
        problems.append("ueIdFrom missing file: rc %s %r" % (rc, s.get("pacerAbortReason")))
    for q in problems:
        print("FAIL " + q)
    print("pacer self-test: %s" % ("ok" if not problems else "%d failure(s)" % len(problems)))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

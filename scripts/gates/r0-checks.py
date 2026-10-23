#!/usr/bin/env python3
"""r0-checks.py: schedule building and ledger checks for gate r0.

  r0-checks.py schedule SCENARIO ENDPOINT [--forced-late | --calibrate | --fault-stop] [--rc-send PATH]
                        [--confirm CMD...]
        the pacer schedule for the scenario: one rc-send trigger per control, each expecting one control
        at ns-3 (several controls in one step become a "triggers" list, sent in scenario order); with
        --forced-late only the forced-late control, sent after `go` (goBeforeTrigger); with --calibrate the
        ten calibration controls; with --fault-stop the scenario's faultStop controls plus its stopTrigger,
        confirmed by CMD (the rest of the arguments)
  r0-checks.py tctl PACER_SUMMARY [--steps N]
        T_ctl from a calibration run: needs a run that ended without an abort and exactly N (10) complete
        trigger steps (one control, trigger rc 0, slack recorded); L = the largest per-control latency
        (pacer wall time at controlRx minus the time just before the trigger started: an upper bound on
        trigger-to-read); T_ctl = max(30, ceil(20 x L)), rounded up
  r0-checks.py expect SCENARIO LEDGER [--forced-late | --fault-stop]
        every control's ledger line has the expected outcome/cause, found by (via, imsi, target) in order
  r0-checks.py d7 LEDGER
        D7 counters from the applied lines: viaEnb, viaServingGnb, viaTargetGnb, distinctImsis, targetGnbs
"""
import json
import sys


def load(p):
    return json.load(open(p))


def ledger_lines(p):
    return [json.loads(l) for l in open(p) if l.strip()][1:]


def cmd_schedule(a):
    sc, ep = load(a[0]), a[1]
    send = a[a.index("--rc-send") + 1] if "--rc-send" in a else "rc-send.sh"
    steps = {}
    todo = sc["calibration"] if "--calibrate" in a else (
        [dict(sc["forcedLate"], goBeforeTrigger=True)] if "--forced-late" in a else (
            sc["faultStop"]["controls"] if "--fault-stop" in a else sc["controls"]))
    by_step = {}
    for c in todo:
        by_step.setdefault(str(c["step"]), []).append(c)
    for k, cs in by_step.items():
        cmds = [["bash", send, ep, str(c["via"]), str(c["imsi"]), c["key"]] for c in cs]
        if len(cs) == 1:
            e = {"trigger": {"cmd": cmds[0]}, "expect": 1}
            if cs[0].get("goBeforeTrigger"):
                e["goBeforeTrigger"] = True
        else:  # several controls in one step: sent one at a time, in list order
            if any(c.get("goBeforeTrigger") for c in cs):
                sys.exit("step %s: goBeforeTrigger needs a single control" % k)
            e = {"triggers": [{"cmd": cmd, "expect": 1} for cmd in cmds]}
        steps[k] = e
    out = {"steps": steps, "late": []}
    st = sc["faultStop"].get("stopTrigger") if "--fault-stop" in a else None
    if st:  # a control sent after the final barrier; endAck waits until the agent has forwarded it
        confirm = a[a.index("--confirm") + 1:] if "--confirm" in a else []
        out["stopTrigger"] = {"cmd": ["bash", send, ep, str(st["via"]), str(st["imsi"]), st["key"]],
                              "confirm": confirm, "timeoutS": st.get("timeoutS", 6)}
    print(json.dumps(out, indent=1))
    return 0


def cmd_expect(a):
    sc = load(a[0])
    lines = ledger_lines(a[1])
    todo = [sc["forcedLate"]] if "--forced-late" in a else (
        sc["faultStop"]["controls"] if "--fault-stop" in a else sc["controls"])
    problems = []
    for c in todo:
        hit = [x for x in lines if x["viaNodeId"] == c["via"] and x["imsi"] == c["imsi"] and x["targetCell"] == c["targetCell"]]
        if len(hit) != 1:
            problems.append("control %r: %d ledger lines" % (c, len(hit)))
            continue
        x = hit[0]
        got = "applied" if x["outcome"] == "applied" else x["cause"]
        if got != c["expect"]:
            problems.append("control via %d imsi %d -> %d: %s, expected %s" % (c["via"], c["imsi"], c["targetCell"], got, c["expect"]))
        if "--forced-late" in a and not (x["afterSeq"] == c["step"] and x["rxSeq"] > c["step"]):
            problems.append("forced late control: afterSeq %d rxSeq %d, expected afterSeq %d and a later barrier" % (x["afterSeq"], x["rxSeq"], c["step"]))
        if "--forced-late" not in a and x["afterSeq"] != c["step"]:
            problems.append("control via %d imsi %d: afterSeq %d != step %d" % (c["via"], c["imsi"], x["afterSeq"], c["step"]))
    if len(lines) != len(todo):
        problems.append("%d ledger lines for %d controls" % (len(lines), len(todo)))
    print(json.dumps({"problems": problems, "pass": not problems}, indent=1))
    return 0 if not problems else 1


def cmd_d7(a):
    ap = [x for x in ledger_lines(a[0]) if x["outcome"] == "applied"]
    # nodeId n (n >= 2) is the gNB serving cell n; node 1 is the eNB (MN)
    d = {"viaEnb": sum(1 for x in ap if x["viaNodeId"] == 1),
         "viaServingGnb": sum(1 for x in ap if x["viaNodeId"] == x["sourceCell"]),
         "viaTargetGnb": sum(1 for x in ap if x["viaNodeId"] == x["targetCell"]),
         "distinctImsis": len({x["imsi"] for x in ap}),
         "targetGnbs": sorted({x["targetCell"] for x in ap}), "applied": len(ap)}
    print(json.dumps(d))
    ok = d["viaEnb"] >= 1 and d["viaServingGnb"] >= 1 and d["viaTargetGnb"] >= 1 and d["distinctImsis"] >= 2 and {2, 3} <= set(d["targetGnbs"])
    return 0 if ok else 1


def cmd_tctl(a):
    import math
    summary = load(a[0])
    want = int(a[a.index("--steps") + 1]) if "--steps" in a else 10
    problems, ls = [], []
    if not summary.get("ended") or summary.get("aborted"):
        problems.append("the calibration run did not end cleanly (ended %r, aborted %r)" % (summary.get("ended"), summary.get("aborted")))
    steps = summary.get("steps", {})
    for k, rec in sorted(steps.items(), key=lambda kv: int(kv[0])):
        if "L" not in rec:
            continue  # an inject-only or untriggered step
        if rec.get("controls") != 1 or rec.get("triggerRc") != 0 or rec.get("slackS") is None or len(rec["L"]) != 1:
            problems.append("step %s is not a complete trigger step: %r" % (k, rec))
            continue
        ls.append(rec["L"][0])
    if len(ls) != want:
        problems.append("%d complete trigger steps, expected %d" % (len(ls), want))
    l_max = max(ls) if ls else None
    t_ctl = max(30, math.ceil(20 * l_max)) if l_max is not None else None
    print(json.dumps({"lMaxS": l_max, "lS": sorted(ls), "tCtlSeconds": t_ctl, "problems": problems, "pass": not problems}, indent=1))
    return 0 if not problems else 1


if __name__ == "__main__":
    cmds = {"schedule": cmd_schedule, "expect": cmd_expect, "d7": cmd_d7, "tctl": cmd_tctl}
    if len(sys.argv) < 3 or sys.argv[1] not in cmds:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

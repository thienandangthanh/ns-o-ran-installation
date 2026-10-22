#!/usr/bin/env python3
"""r0-checks.py: schedule building and ledger checks for gate r0.

  r0-checks.py schedule SCENARIO ENDPOINT [--forced-late] [--rc-send PATH]
        the pacer schedule for the scenario: one rc-send trigger per control, each expecting one control
        at ns-3; with --forced-late only the forced-late control, sent after `go` (goBeforeTrigger)
  r0-checks.py expect SCENARIO LEDGER [--forced-late]
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
    todo = [dict(sc["forcedLate"], goBeforeTrigger=True)] if "--forced-late" in a else sc["controls"]
    for c in todo:
        e = {"trigger": {"cmd": ["bash", send, ep, str(c["via"]), str(c["imsi"]), c["key"]]}, "expect": 1}
        if c.get("goBeforeTrigger"):
            e["goBeforeTrigger"] = True
        steps[str(c["step"])] = e
    print(json.dumps({"steps": steps, "late": []}, indent=1))
    return 0


def cmd_expect(a):
    sc = load(a[0])
    lines = ledger_lines(a[1])
    todo = [sc["forcedLate"]] if "--forced-late" in a else sc["controls"]
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


if __name__ == "__main__":
    cmds = {"schedule": cmd_schedule, "expect": cmd_expect, "d7": cmd_d7}
    if len(sys.argv) < 3 or sys.argv[1] not in cmds:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

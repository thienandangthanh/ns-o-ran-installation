#!/usr/bin/env python3
"""r2-checks.py: schedule, stub table and judges for gate r2 (TS xApp + stub QP).

  r2-checks.py triggers SCENARIO [--calibrate]
        the trigger list (step, imsi, kind, predictions, via, key, targetCell, expect); --calibrate expands the
        calibration block (round robin, each UE sent to the cell it is not on)
  r2-checks.py schedule SCENARIO SEND CTL_PORT [--calibrate]
        the pacer schedule: one `send-rmr.sh CTL_PORT anomaly <imsi>` trigger per step; a positive waits for one
        control within T_ctl, a negative requires none within W ("absence")
  r2-checks.py table SCENARIO [--calibrate]
        the stub QP's prediction table: per UE, its predictions in step order
  r2-checks.py expect SCENARIO LEDGER [--calibrate]
        positives: exactly one ledger line by (via, imsi, targetCell), afterSeq = step, the expected outcome
        (calibration: any outcome); negatives: no ledger line for the IMSI; ledger lines = positives; late = 0
  r2-checks.py wire SCENARIO RC_MULTISET [--calibrate]
        the decoded wire: RICcontrolRequests = positives, each attributed to its trigger by (imsi, step) with
        viaNode = the target's agent, targetKey = the stub's chosen key and exactly one terminal answer; none for
        a negative's IMSI
  r2-checks.py stub SCENARIO STUB_LOG INJECTOR_TX [--calibrate]
        the injector sent every trigger (RMR state 0) and the stub got one 30000 naming exactly that UE per trigger,
        in step order, and answered each with a 30002 sent in state 0; other message types the stub got (e.g.
        12041/12042 while it holds a -1 route) are recorded, not judged
  r2-checks.py d7 LEDGER
        every applied line came through the target gNB's agent (recorded deviation P1); both gNBs are targets
  r2-checks.py w PACER_SUMMARY T_CTL [--count N]
        W from a calibration run: N complete one-control trigger steps; L_max = their largest L;
        W = max(1 s, 3 x L_max) rounded up to 0.1 s; also reports whether 20 x L_max <= T_ctl
"""
import json
import math
import sys


def load(p):
    return json.load(open(p))


def ledger_lines(p):
    return [json.loads(l) for l in open(p) if l.strip()][1:]


def triggers(sc, calibrate):
    if not calibrate:
        return sorted(sc["controls"], key=lambda c: c["step"])
    cal = sc["calibration"]
    cell = {int(k): v for k, v in cal["startCells"].items()}
    ues = sorted(cell)
    out = []
    for i in range(cal["count"]):
        imsi = ues[i % len(ues)]
        src = cell[imsi]
        tgt = 2 if src == 3 else 3
        key = lambda c: "%08X%02X" % (c, c)
        out.append({"step": cal["firstStep"] + i * cal["everySteps"], "imsi": imsi, "kind": "positive",
                    "predictions": [[key(src), [100, 0]], [key(tgt), [300, 0]]],
                    "via": tgt, "key": key(tgt), "targetCell": tgt, "expect": "any"})
        cell[imsi] = tgt
    return out


def cmd_triggers(a):
    print(json.dumps(triggers(load(a[0]), "--calibrate" in a), indent=1))
    return 0


def cmd_schedule(a):
    sc, send, port = load(a[0]), a[1], a[2]
    steps = {}
    for t in triggers(sc, "--calibrate" in a):
        e = {"trigger": {"cmd": ["bash", send, port, "anomaly", str(t["imsi"])]}}
        if t["kind"] == "positive":
            e["expect"] = 1
        else:
            e["expect"], e["absence"] = 0, True
        if str(t["step"]) in steps:
            sys.exit("step %d has two triggers" % t["step"])
        steps[str(t["step"])] = e
    print(json.dumps({"steps": steps, "late": []}, indent=1))
    return 0


def cmd_table(a):
    tab = {}
    for t in triggers(load(a[0]), "--calibrate" in a):
        tab.setdefault(str(t["imsi"]), []).append(t["predictions"])
    print(json.dumps({"predictions": tab}, indent=1))
    return 0


def cmd_expect(a):
    cal = "--calibrate" in a
    ts, lines = triggers(load(a[0]), cal), ledger_lines(a[1])
    problems = []
    pos = [t for t in ts if t["kind"] == "positive"]
    for t in pos:
        hit = [x for x in lines if x["viaNodeId"] == t["via"] and x["imsi"] == t["imsi"] and x["targetCell"] == t["targetCell"]
               and (not cal or x["afterSeq"] == t["step"])]
        if len(hit) != 1:
            problems.append("positive %r: %d ledger lines" % ({k: t[k] for k in ("step", "imsi", "via")}, len(hit)))
            continue
        x = hit[0]
        got = "applied" if x["outcome"] == "applied" else x["cause"]
        if t["expect"] != "any" and got != t["expect"]:
            problems.append("step %d imsi %d: %s, expected %s" % (t["step"], t["imsi"], got, t["expect"]))
        if x["afterSeq"] != t["step"]:
            problems.append("step %d imsi %d: afterSeq %d" % (t["step"], t["imsi"], x["afterSeq"]))
    for t in ts:
        if t["kind"] == "negative" and any(x["imsi"] == t["imsi"] for x in lines):
            problems.append("negative %s (step %d, imsi %d) has a ledger line" % (t.get("case"), t["step"], t["imsi"]))
    late = sum(1 for x in lines if x.get("cause") == "late")
    if late:
        problems.append("%d late ledger lines" % late)
    if len(lines) != len(pos):
        problems.append("%d ledger lines for %d positives" % (len(lines), len(pos)))
    outcomes = {}
    for x in lines:
        k = "applied" if x["outcome"] == "applied" else x["cause"]
        outcomes[k] = outcomes.get(k, 0) + 1
    print(json.dumps({"positives": len(pos), "negatives": len(ts) - len(pos), "ledgerLines": len(lines), "late": late,
                      "outcomes": outcomes, "problems": problems, "pass": not problems}, indent=1))
    return 0 if not problems else 1


def cmd_wire(a):
    cal = "--calibrate" in a
    ts, ms = triggers(load(a[0]), cal), load(a[1])
    problems = []
    pos = [t for t in ts if t["kind"] == "positive"]
    for t in pos:
        hit = [m for m in ms if m["imsi"] == t["imsi"] and m["step"] == t["step"]]
        if len(hit) != 1:
            problems.append("positive step %d imsi %d: %d RICcontrolRequests" % (t["step"], t["imsi"], len(hit)))
            continue
        m = hit[0]
        if m["viaNode"] != t["via"] or m["targetKey"].upper() != t["key"] or m["targetKey"] != m["targetKey"].upper():
            problems.append("step %d imsi %d: via %r key %r, expected via %d key %s" % (t["step"], t["imsi"], m["viaNode"], m["targetKey"], t["via"], t["key"]))
        if m["answer"] not in ("ack", "failure"):
            problems.append("step %d imsi %d: no terminal answer (%r)" % (t["step"], t["imsi"], m["answer"]))
    for t in ts:
        if t["kind"] == "negative" and any(m["imsi"] == t["imsi"] for m in ms):
            problems.append("negative %s imsi %d: a RICcontrolRequest on the wire" % (t.get("case"), t["imsi"]))
    if len(ms) != len(pos):
        problems.append("%d RICcontrolRequests on the wire for %d positives" % (len(ms), len(pos)))
    keys = sorted({m["targetKey"] for m in ms})
    print(json.dumps({"requests": len(ms), "positives": len(pos), "targetKeys": keys, "problems": problems,
                      "pass": not problems}, indent=1))
    return 0 if not problems else 1


def cmd_stub(a):
    ts, log = triggers(load(a[0]), "--calibrate" in a), load(a[1])
    tx = [json.loads(l) for l in open(a[2]) if l.strip()]
    problems = []
    anomalies = [r for r in tx if r["mtype"] == 30003]
    if len(anomalies) != len(ts) or any(r["state"] != 0 for r in anomalies):
        problems.append("injector: %d 30003 sends (want %d), states %r" % (len(anomalies), len(ts), sorted({r["state"] for r in anomalies})))
    sent_ues = [json.loads(bytes.fromhex(r["payloadHex"]))[0]["ue-id"] for r in anomalies]
    if sent_ues != [str(t["imsi"]) for t in ts]:
        problems.append("injector sent ues %r, expected %r" % (sent_ues, [str(t["imsi"]) for t in ts]))
    reqs = [r for r in log if r["rx"]["mtype"] == 30000]
    other = [r for r in log if r["rx"]["mtype"] != 30000]
    got = []
    for r in reqs:
        try:
            got.append(json.loads(r["rx"]["payload"])["UEPredictionSet"])
        except (ValueError, KeyError):
            got.append(None)
    if got != [[str(t["imsi"])] for t in ts]:
        problems.append("stub got UEPredictionSets %r, expected one per trigger %r" % (got, [[str(t["imsi"])] for t in ts]))
    bad_tx = [r for r in reqs if (r.get("tx") or {}).get("state") != 0]
    if bad_tx:
        problems.append("%d 30000 requests without a 30002 sent in state 0: %r" % (len(bad_tx), [r.get("note") for r in bad_tx]))
    print(json.dumps({"injected": len(anomalies), "stubRequests": len(reqs), "stubOtherMessages": len(other),
                      "stubOtherTypes": sorted({r["rx"]["mtype"] for r in other}),
                      "problems": problems, "pass": not problems}, indent=1))
    return 0 if not problems else 1


def cmd_d7(a):
    ap = [x for x in ledger_lines(a[0]) if x["outcome"] == "applied"]
    d = {"viaTargetGnb": sum(1 for x in ap if x["viaNodeId"] == x["targetCell"]), "applied": len(ap),
         "distinctImsis": len({x["imsi"] for x in ap}), "targetGnbs": sorted({x["targetCell"] for x in ap}),
         "form": "R2/R3: target-addressed (recorded deviation P1)"}
    print(json.dumps(d))
    return 0 if ap and d["viaTargetGnb"] == len(ap) and {2, 3} <= set(d["targetGnbs"]) else 1


def cmd_w(a):
    summ, t_ctl = load(a[0]), float(a[1])
    want = int(a[a.index("--count") + 1]) if "--count" in a else None
    problems, ls = [], []
    if not summ.get("ended") or summ.get("aborted"):
        problems.append("the calibration run did not end cleanly")
    for k, rec in sorted(summ.get("steps", {}).items(), key=lambda kv: int(kv[0])):
        if "L" not in rec:
            continue
        if rec.get("controls") != 1 or rec.get("triggerRc") != 0 or len(rec["L"]) != 1 or rec.get("window") != "T_ctl":
            problems.append("step %s is not a complete one-control trigger step: %r" % (k, rec))
            continue
        ls.append(rec["L"][0])
    if want is not None and len(ls) != want:
        problems.append("%d complete trigger steps, expected %d" % (len(ls), want))
    l_max = max(ls) if ls else None
    w = max(1.0, math.ceil(30 * l_max) / 10) if l_max is not None else None
    out = {"n": len(ls), "lMaxS": l_max, "lS": sorted(ls), "wSeconds": w,
           "tCtlCoversTwentyLMax": (20 * l_max <= t_ctl) if l_max is not None else None,
           "problems": problems, "pass": not problems}
    print(json.dumps(out, indent=1))
    return 0 if not problems else 1


if __name__ == "__main__":
    cmds = {"triggers": cmd_triggers, "schedule": cmd_schedule, "table": cmd_table, "expect": cmd_expect,
            "wire": cmd_wire, "stub": cmd_stub, "d7": cmd_d7, "w": cmd_w}
    if len(sys.argv) < 3 or sys.argv[1] not in cmds:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

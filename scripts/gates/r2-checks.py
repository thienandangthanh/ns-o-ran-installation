#!/usr/bin/env python3
"""r2-checks.py: schedule, stub table and judges for gate r2 (TS xApp + stub QP).

Every trigger names its UE by the UE's KPM UE ID key (en-gNB-UEID, enGnbUeId:<lteRnti>@00F110-<MN cell %05X>):
U(imsi) is the gNB tag of the IMSI's identity in the run's e2-ue-context-*.jsonl (ue-context-map.py), so the
judges take the run's trace dir; a trigger with a "ueId" instead of an "imsi" names that key as given (n3: a key no
UE holds).

  r2-checks.py triggers SCENARIO [--calibrate]
        the trigger list (step, imsi or ueId, kind, predictions, via, key, targetCell, expect); --calibrate expands
        the calibration block (round robin, each UE sent to the cell it is not on, via the cell it is on)
  r2-checks.py schedule SCENARIO SEND CTL_PORT RUN_DIR STUB_URL [--calibrate]
        the run's pacer schedule: per step one `send-rmr.sh CTL_PORT anomaly-from RUN_DIR/ue-id/s<step>-i<imsi>.txt`
        trigger after a prepare (`r2-checks.py prepare`) that resolves and Influx-confirms that key (a "ueId"
        trigger sends `anomaly <ueId>`); the first step's prepare also loads the stub table. A positive waits for
        one control within T_ctl, a negative requires none within W ("absence")
  r2-checks.py prepare SCENARIO RUN_DIR STEP STUB_URL [--load-table] [--calibrate]
        the pacer prepare of one step: with --load-table, once the run's context files (lines with seq <= STEP)
        hold every scenario IMSI, the table keyed by U(imsi) PUT to the stub, which must report exactly those
        UEs and entries (written to RUN_DIR/r2/stub-table.json); then ue-id-prepare.py for the step's IMSI
  r2-checks.py table SCENARIO TRACE_DIR [--calibrate] [--max-seq S]
        the stub QP's prediction table: per UE key, its predictions in step order
  r2-checks.py expect SCENARIO LEDGER [--calibrate]
        positives: exactly one ledger line by (via, imsi, targetCell), afterSeq = step, the expected outcome
        (calibration: any outcome); negatives: no ledger line for the IMSI (a "ueId" negative: no line at its step,
        and no IMSI of the run, by the ledger's trace dir, holds that ID); ledger lines = positives; late = 0
  r2-checks.py wire SCENARIO RC_MULTISET TRACE_DIR [--calibrate]
        the decoded wire: RICcontrolRequests = positives, each attributed to its trigger by (I(ueId), step) with
        viaNode = the UE's source en-gNB, targetKey = the stub's chosen key and exactly one terminal answer; none
        for a negative's UE (a "ueId" negative: none at its step and none naming its X2AP ID)
  r2-checks.py stub SCENARIO STUB_LOG INJECTOR_TX TRACE_DIR [--calibrate]
        the injector sent every trigger (RMR state 0) naming U(imsi) and the stub got one 30000 naming exactly
        [U(imsi)] per trigger, in step order, and answered each with a 30002 sent in state 0; other message types
        the stub got (e.g. 12041/12042 while it holds a -1 route) are recorded, not judged
  r2-checks.py d7 LEDGER
        every applied line came through the UE's source en-gNB (viaNodeId = sourceCell), via both gNBs, and both
        gNBs are targets
  r2-checks.py w PACER_SUMMARY T_CTL [--count N]
        W from a calibration run: N complete one-control trigger steps; L_max = their largest L;
        W = max(1 s, 3 x L_max) rounded up to 0.1 s; also reports whether 20 x L_max <= T_ctl
"""
import importlib.util
import os
import urllib.request
import json
import math
import sys


HERE = os.path.dirname(os.path.abspath(__file__))


def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def uecm():
    return _mod("ue_context_map", os.path.join(HERE, "..", "..", "tools", "e2-evidence", "ue-context-map.py"))


def load(p):
    return json.load(open(p))


def ue_keys(trace_dir, max_seq=None):
    """({imsi: U(imsi)}, problems) from the run's context files (conjunct (c): one identity per IMSI)."""
    m = uecm()
    cm = m.UeContextMap(trace_dir, max_seq=max_seq)
    ids, p = cm.identities()
    return {i: m.gnb_tag(rnti, mn) for i, (rnti, mn, _) in ids.items()}, cm.problems + p


def ue_of(t, keys):
    """The key a trigger names: its literal ueId, or U(imsi) (None when the IMSI has no identity)."""
    return t["ueId"] if "ueId" in t else keys.get(t["imsi"])


def ue_file(rd, t):
    return os.path.join(rd, "ue-id", "s%d-i%d" % (t["step"], t["imsi"]))


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
        key = lambda c: "%08X10" % c   # the TS xApp cell key: NCI (gNB ID, cell part 1) + APER pad digit 0
        out.append({"step": cal["firstStep"] + i * cal["everySteps"], "imsi": imsi, "kind": "positive",
                    "predictions": [[key(src), [100, 0]], [key(tgt), [300, 0]]],
                    "via": src, "key": key(tgt), "targetCell": tgt, "expect": "any"})
        cell[imsi] = tgt
    return out


def cmd_triggers(a):
    print(json.dumps(triggers(load(a[0]), "--calibrate" in a), indent=1))
    return 0


def cmd_schedule(a):
    sc, send, port, rd, url = load(a[0]), a[1], a[2], a[3], a[4]
    cal = ["--calibrate"] if "--calibrate" in a else []
    steps = {}
    ts = triggers(sc, cal)
    for n, t in enumerate(ts):
        if "ueId" in t:
            e = {"trigger": {"cmd": ["bash", send, port, "anomaly", t["ueId"]]}}
        else:
            e = {"trigger": {"cmd": ["bash", send, port, "anomaly-from", ue_file(rd, t) + ".txt"]}}
        if "imsi" in t or n == 0:
            e["prepare"] = {"cmd": ["python3", "-I", os.path.join(HERE, "r2-checks.py"), "prepare", a[0], rd, str(t["step"]), url]
                            + (["--load-table"] if n == 0 else []) + cal, "timeoutS": 30}
        if t["kind"] == "positive":
            e["expect"] = 1
        else:
            e["expect"], e["absence"] = 0, True
        if str(t["step"]) in steps:
            sys.exit("step %d has two triggers" % t["step"])
        steps[str(t["step"])] = e
    print(json.dumps({"steps": steps, "late": []}, indent=1))
    return 0


def table(ts, keys):
    """({key: [predictions in step order]}, problems)."""
    tab, problems = {}, []
    for t in ts:
        k = ue_of(t, keys)
        if k is None:
            problems.append("IMSI %d has no identity in the context files" % t["imsi"])
            continue
        tab.setdefault(k, []).append(t["predictions"])
    return tab, problems


def cmd_table(a):
    ms = int(a[a.index("--max-seq") + 1]) if "--max-seq" in a else None
    keys, p = ue_keys(a[1], ms)
    tab, p2 = table(triggers(load(a[0]), "--calibrate" in a), keys)
    for q in p + p2:
        print(q, file=sys.stderr)
    print(json.dumps({"predictions": tab}, indent=1))
    return 0 if not p + p2 else 1


def cmd_prepare(a):
    scen, rd, step, url = a[0], a[1], int(a[2]), a[3]
    ts = triggers(load(scen), "--calibrate" in a)
    trace = os.path.join(rd, "trace")
    if "--load-table" in a:
        keys, p = ue_keys(trace, step)
        miss = sorted({t["imsi"] for t in ts if "imsi" in t} - set(keys))
        if p or miss:
            print("stub table not loaded at %d: %s" % (step, "; ".join(p[:3] + ["IMSIs %s not yet in the context files" % miss] * bool(miss))))
            return 1
        tab, p = table(ts, keys)
        body = {"predictions": tab}
        req = urllib.request.Request(url + "/table", data=json.dumps(body).encode(), method="PUT")
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                got = json.loads(r.read())
        except (OSError, ValueError) as ex:
            print("stub table PUT at %d: %s" % (step, ex))
            return 1
        want = {"ues": sorted(tab), "entries": sum(len(v) for v in tab.values())}
        os.makedirs(os.path.join(rd, "r2"), exist_ok=True)
        json.dump({"step": step, "table": body, "answer": got}, open(os.path.join(rd, "r2", "stub-table.json"), "w"), indent=1)
        if p or got != want:
            print("stub table at %d answered %r, want %r %s" % (step, got, want, p))
            return 1
        print("stub table loaded at %d: %d UEs, %d entries" % (step, len(tab), want["entries"]))
    here = [t for t in ts if t["step"] == step and "imsi" in t]
    if not here:
        return 0
    uep = _mod("ue_id_prepare", os.path.join(HERE, "ue-id-prepare.py"))
    rc = 0
    for t in here:
        rec, p = uep.prepare(trace, step, t["imsi"], ue_file(rd, t))
        print("ue-id seq %d imsi %d: %s" % (step, t["imsi"], rec["ueId"] if rec else "FAIL " + "; ".join(p[:3])))
        rc |= 0 if rec else 1
    return rc


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
        if t["kind"] != "negative":
            continue
        if "ueId" in t:
            at = [x for x in lines if x["rxSeq"] == t["step"] or x["afterSeq"] == t["step"]]
            x2 = uecm().x2_of(t["ueId"])
            held = uecm().UeContextMap(os.path.dirname(os.path.abspath(a[1]))).holds(*x2) if x2 else None
            if at or held != []:
                problems.append("negative %s (step %d, ueId %s): %d ledger lines at that step, held by IMSIs %r (want none)"
                                % (t.get("case"), t["step"], t["ueId"], len(at), held))
        elif any(x["imsi"] == t["imsi"] for x in lines):
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
    ucm = uecm()
    cm = ucm.UeContextMap(a[2])
    problems = ["UE context: " + q for q in cm.problems]

    def imsi(m):
        x = ucm.x2_of(m.get("ueId"))
        return cm.imsi_of(*x) if x else None
    pos = [t for t in ts if t["kind"] == "positive"]
    for t in pos:
        hit = [m for m in ms if imsi(m) == t["imsi"] and m["step"] == t["step"]]
        if len(hit) != 1:
            problems.append("positive step %d imsi %d: %d RICcontrolRequests" % (t["step"], t["imsi"], len(hit)))
            continue
        m = hit[0]
        if m["viaNode"] != t["via"] or m["targetKey"].upper() != t["key"] or m["targetKey"] != m["targetKey"].upper():
            problems.append("step %d imsi %d: via %r key %r, expected via %d key %s" % (t["step"], t["imsi"], m["viaNode"], m["targetKey"], t["via"], t["key"]))
        if m["answer"] not in ("ack", "failure"):
            problems.append("step %d imsi %d: no terminal answer (%r)" % (t["step"], t["imsi"], m["answer"]))
    for t in ts:
        if t["kind"] != "negative":
            continue
        if "ueId" in t:
            x2 = ucm.x2_of(t["ueId"])
            bad = [m for m in ms if m["step"] == t["step"] or (x2 and (ucm.x2_of(m.get("ueId")) or (None,))[0] == x2[0])]
            if bad or not x2:
                problems.append("negative %s (ueId %s): %d RICcontrolRequests at step %d or naming its X2AP ID" % (
                    t.get("case"), t["ueId"], len(bad), t["step"]))
        elif any(imsi(m) == t["imsi"] for m in ms):
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
    keys, problems = ue_keys(a[3])
    problems = ["UE context: " + q for q in problems]
    want_ues = [ue_of(t, keys) for t in ts]
    anomalies = [r for r in tx if r["mtype"] == 30003]
    if len(anomalies) != len(ts) or any(r["state"] != 0 for r in anomalies):
        problems.append("injector: %d 30003 sends (want %d), states %r" % (len(anomalies), len(ts), sorted({r["state"] for r in anomalies})))
    sent_ues = [json.loads(bytes.fromhex(r["payloadHex"]))[0]["ue-id"] for r in anomalies]
    if None in want_ues or sent_ues != want_ues:
        problems.append("injector sent ues %r, expected %r" % (sent_ues, want_ues))
    reqs = [r for r in log if r["rx"]["mtype"] == 30000]
    other = [r for r in log if r["rx"]["mtype"] != 30000]
    got = []
    for r in reqs:
        try:
            got.append(json.loads(r["rx"]["payload"])["UEPredictionSet"])
        except (ValueError, KeyError):
            got.append(None)
    if None in want_ues or got != [[u] for u in want_ues]:
        problems.append("stub got UEPredictionSets %r, expected one per trigger %r" % (got, [[u] for u in want_ues]))
    bad_tx = [r for r in reqs if (r.get("tx") or {}).get("state") != 0]
    if bad_tx:
        problems.append("%d 30000 requests without a 30002 sent in state 0: %r" % (len(bad_tx), [r.get("note") for r in bad_tx]))
    print(json.dumps({"injected": len(anomalies), "stubRequests": len(reqs), "stubOtherMessages": len(other),
                      "stubOtherTypes": sorted({r["rx"]["mtype"] for r in other}),
                      "problems": problems, "pass": not problems}, indent=1))
    return 0 if not problems else 1


def cmd_d7(a):
    ap = [x for x in ledger_lines(a[0]) if x["outcome"] == "applied"]
    d = {"viaSourceGnb": sum(1 for x in ap if x["viaNodeId"] == x["sourceCell"]), "applied": len(ap),
         "distinctImsis": len({x["imsi"] for x in ap}), "targetGnbs": sorted({x["targetCell"] for x in ap}),
         "viaGnbs": sorted({x["viaNodeId"] for x in ap}),
         "form": "via the source en-gNB (SN-initiated, E2SM-RC Style 5 action 3)"}
    print(json.dumps(d))
    return 0 if (ap and d["viaSourceGnb"] == len(ap) and {2, 3} <= set(d["targetGnbs"])
                 and {2, 3} <= set(d["viaGnbs"])) else 1


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
    cmds = {"triggers": cmd_triggers, "schedule": cmd_schedule, "table": cmd_table, "prepare": cmd_prepare, "expect": cmd_expect,
            "wire": cmd_wire, "stub": cmd_stub, "d7": cmd_d7, "w": cmd_w}
    if len(sys.argv) < 3 or sys.argv[1] not in cmds:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

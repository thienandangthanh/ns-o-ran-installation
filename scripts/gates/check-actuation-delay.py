#!/usr/bin/env python3
"""check-actuation-delay.py: the δ seam on one lock-step run (AC7, AC9; plan R-5, I-2, I-3).

  check-actuation-delay.py LEDGER NS3RUN --delta-ms D [--c-ms 3.0] [--min-applied N]
  check-actuation-delay.py --self-test

LEDGER is trace/e2-control-ledger.jsonl, NS3RUN the run's ns-3 output directory (EnbHandoverStartStats.txt, rows
"time-s imsi cellId rnti targetCellId", 0.1 ms resolution). Checks:
  1. the ledger header records delta-model "fixed D";
  2. on every applied line, applySimTimeNs - rxSimTimeNs = D ms (decisionSimTimeNs := rxSimTimeNs, I-3);
  3. on every applied line, the eNB's HandoverStart for that IMSI and target is at applySimTimeNs + c, with
     c = --c-ms (3.0 ms, registered from the M9 reference: ledger apply 3.0008 s, HandoverStart 3.0038 s), compared
     at the trace's 0.1 ms resolution; each HandoverStart row matches at most one applied line;
  4. at least --min-applied applied lines (default 1: AC9 needs one applied handover per δ).
Prints one JSON report; exit 0 on pass.
"""
import argparse
import json
import os
import sys
import tempfile

TICK_NS = 100_000  # the trace prints seconds with 4 decimals: 0.1 ms


def handover_starts(ns3run):
    rows = []
    with open(os.path.join(ns3run, "EnbHandoverStartStats.txt")) as f:
        for line in f:
            p = line.split()
            if len(p) >= 5:
                rows.append({"tick": round(float(p[0]) * 1e4), "imsi": int(p[1]), "target": int(p[4]), "used": False})
    return rows


def check(ledger_path, ns3run, delta_ms, c_ms, min_applied):
    rows = [json.loads(l) for l in open(ledger_path) if l.strip()] if os.path.exists(ledger_path) else []
    problems = []
    header, lines = (rows[0], rows[1:]) if rows else ({}, [])
    if rows and header.get("delta-model") != "fixed %d" % delta_ms:
        problems.append("header %r, want delta-model 'fixed %d'" % (header, delta_ms))
    starts = handover_starts(ns3run)
    applied = [l for l in lines if l["outcome"] == "applied"]
    offsets = []
    for l in applied:
        k = (l["viaNodeId"], l["ctlId"])
        if l["applySimTimeNs"] - l["rxSimTimeNs"] != delta_ms * 1_000_000:
            problems.append("apply - rx = %d ns for %r, want %d ms" % (l["applySimTimeNs"] - l["rxSimTimeNs"], k, delta_ms))
        want = round((l["applySimTimeNs"] + round(c_ms * 1_000_000)) / TICK_NS)
        hit = next((s for s in starts if not s["used"] and s["imsi"] == l["imsi"] and s["target"] == l["targetCell"]
                    and s["tick"] == want), None)
        if hit is None:
            problems.append("no HandoverStart at apply + %.1f ms for imsi %d -> cell %d (%r)" % (c_ms, l["imsi"], l["targetCell"], k))
        else:
            hit["used"] = True
            offsets.append((hit["tick"] * TICK_NS - l["applySimTimeNs"]) / 1e6)
    if len(applied) < min_applied:
        problems.append("%d applied lines, need at least %d" % (len(applied), min_applied))
    return {"deltaMs": delta_ms, "cMs": c_ms, "applied": len(applied), "lines": len(lines),
            "applyToHandoverStartMs": offsets, "problems": problems, "pass": not problems}


def self_test():
    d = tempfile.mkdtemp()
    def run(ledger, starts, delta, n=1):
        open(d + "/l.jsonl", "w").write("\n".join(json.dumps(x) for x in ledger) + "\n")
        open(d + "/EnbHandoverStartStats.txt", "w").write("".join(s + "\n" for s in starts))
        return check(d + "/l.jsonl", d, delta, 3.0, n)["pass"]
    hdr = lambda ms: {"type": "ledgerHeader", "v": 1, "delta-model": "fixed %d" % ms}
    line = lambda rx, ap, out="applied": {"rxSeq": 30, "rxSimTimeNs": rx, "applySimTimeNs": ap, "viaNodeId": 2, "ctlId": 1,
                                          "afterSeq": 30, "imsi": 1, "sourceCell": 3, "targetCell": 2, "outcome": out, "cause": ""}
    m9 = [hdr(0), line(3000800000, 3000800000)]
    assert run(m9, ["3.0038 1 1 3 2"], 0), "the M9 reference line passes at d = 0"
    assert run([hdr(150), line(3000800000, 3150800000)], ["3.1538 1 1 3 2"], 150), "d = 150 passes"
    assert not run([hdr(150), line(3000800000, 3100800000)], ["3.1038 1 1 3 2"], 150), "apply - rx != d fails"
    assert not run([hdr(0), line(3000800000, 3000800000)], ["3.0048 1 1 3 2"], 0), "an offset other than c fails"
    assert not run([hdr(0), line(3000800000, 3000800000)], ["3.0038 2 1 3 2"], 0), "another IMSI's start fails"
    assert not run([hdr(100), line(3000800000, 3100800000)], ["3.1038 1 1 3 2"], 150), "a wrong header fails"
    assert not run([hdr(150), line(3000800000, 3150800000, "refused")], [], 150), "no applied line fails min 1"
    print("check-actuation-delay self-test: ok")
    return 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ledger")
    ap.add_argument("ns3run")
    ap.add_argument("--delta-ms", type=int, required=True)
    ap.add_argument("--c-ms", type=float, default=3.0)
    ap.add_argument("--min-applied", type=int, default=1)
    a = ap.parse_args()
    r = check(a.ledger, a.ns3run, a.delta_ms, a.c_ms, a.min_applied)
    print(json.dumps(r, indent=1))
    return 0 if r["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())

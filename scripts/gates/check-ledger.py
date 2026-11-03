#!/usr/bin/env python3
"""check-ledger.py: contract C2 on a lock-step run's control ledger.

Inputs: the ledger (trace/e2-control-ledger.jsonl; missing = no control) and
the pacer log (pacer/pacer-log.jsonl), whose ns-3 `ready` lines give every
barrier's seq and sim time. With --delta-ms D (the run's ActuationDelay, default
0) the checks follow the δ seam; at D = 0 they are exactly the d = 0 checks.
Checks, per line:
  1. applySimTimeNs - rxSimTimeNs = 0 (d = 0); with D > 0, = D on every line that
     is not `late`, and >= 0 on a `late` line;
  2. rxSeq == afterSeq, except cause `late`;
  3. rxSimTimeNs is the sim time of the barrier of rxSeq, except cause `late`;
  4. lines sorted by (rxSeq, imsi, viaNodeId, targetCell, ctlId), written once; with
     D > 0 a line is written when it is answered, so the key is (applySimTimeNs,
     rxSeq, imsi, viaNodeId, targetCell, ctlId);
and for the run: the header records delta-model "fixed <D>"; per barrier, the
lines other than `late` equal ns-3's `applied` controls minus its `late`
(a control refused late at a barrier missed its own one, afterSeq < rxSeq; with
D > 0 a control decided at a barrier and still pending when the run stopped is
answered `late` at the stop and counts for its barrier: rxSimTimeNs is that
barrier's time and applySimTimeNs is later);
the `late` lines are at least the barriers' `late` total (the rest were
refused at the stop); with --expect N the total equals N (controls sent or
injected).
Prints one JSON report; exit 0 on pass.

usage: check-ledger.py LEDGER PACER_LOG [--expect N] [--delta-ms D]
"""
import argparse
import json
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ledger")
    ap.add_argument("pacer_log")
    ap.add_argument("--expect", type=int)
    ap.add_argument("--delta-ms", type=int, default=0)
    a = ap.parse_args()
    delta_ns = a.delta_ms * 1_000_000
    rows = []
    if os.path.exists(a.ledger):
        with open(a.ledger) as f:
            rows = [json.loads(l) for l in f if l.strip()]
    barrier_ns, applied, applied_late = {}, {}, {}
    with open(a.pacer_log) as f:
        for l in f:
            e = json.loads(l)
            m = e["msg"]
            if e["dir"] == "rx" and m.get("type") == "ready":
                barrier_ns[m["seq"]] = m["simTimeNs"]
            if e["dir"] == "rx" and m.get("type") == "applied":
                applied[m["seq"]] = m["controls"] - m.get("late", 0)
                applied_late[m["seq"]] = m.get("late", 0)
    problems = []
    lines = rows
    if rows:
        header, lines = rows[0], rows[1:]
        if header.get("type") != "ledgerHeader" or header.get("delta-model") != "fixed %d" % a.delta_ms:
            problems.append("missing or wrong header %r" % header)
    seen = set()
    per_seq = {}
    for l in lines:
        k = (l["viaNodeId"], l["ctlId"])
        if k in seen:
            problems.append("two lines for %r" % (k,))
        seen.add(k)
        if delta_ns == 0:
            if l["applySimTimeNs"] != l["rxSimTimeNs"]:
                problems.append("apply - rx != 0 for %r" % (k,))
        elif l["cause"] != "late" and l["applySimTimeNs"] - l["rxSimTimeNs"] != delta_ns:
            problems.append("apply - rx = %d != %d for %r" % (l["applySimTimeNs"] - l["rxSimTimeNs"], delta_ns, k))
        elif l["cause"] == "late" and l["applySimTimeNs"] < l["rxSimTimeNs"]:
            problems.append("late line answered before it was received for %r" % (k,))
        pending_at_stop = (delta_ns > 0 and l["cause"] == "late" and l["afterSeq"] >= l["rxSeq"]
                           and barrier_ns.get(l["rxSeq"]) == l["rxSimTimeNs"] and l["applySimTimeNs"] > l["rxSimTimeNs"])
        if l["cause"] == "late" and not pending_at_stop:
            continue
        per_seq[l["rxSeq"]] = per_seq.get(l["rxSeq"], 0) + 1
        if l["rxSeq"] != l["afterSeq"]:
            problems.append("rxSeq %d != afterSeq %d for %r" % (l["rxSeq"], l["afterSeq"], k))
        if barrier_ns.get(l["rxSeq"]) != l["rxSimTimeNs"]:
            problems.append("rxSimTimeNs %d is not the barrier time %r of seq %d for %r" % (
                l["rxSimTimeNs"], barrier_ns.get(l["rxSeq"]), l["rxSeq"], k))
    if delta_ns == 0:
        order = [(l["rxSeq"], l["imsi"], l["viaNodeId"], l["targetCell"], l["ctlId"]) for l in lines]
    else:
        order = [(l["applySimTimeNs"], l["rxSeq"], l["imsi"], l["viaNodeId"], l["targetCell"], l["ctlId"]) for l in lines]
    if order != sorted(order):
        problems.append("lines not in (%srxSeq, C4) order" % ("" if delta_ns == 0 else "answer time, "))
    for seq, n in sorted(per_seq.items()):
        if applied.get(seq) != n:
            problems.append("seq %d: %d ledger lines, ns-3 applied %r" % (seq, n, applied.get(seq)))
    for seq, n in sorted(applied.items()):
        if n and per_seq.get(seq, 0) != n:
            problems.append("seq %d: ns-3 applied %d, ledger has %d" % (seq, n, per_seq.get(seq, 0)))
    late_lines = [l for l in lines if l["cause"] == "late"]
    if len(late_lines) < sum(applied_late.values()):
        problems.append("%d late lines, ns-3 refused %d late at barriers" % (len(late_lines), sum(applied_late.values())))
    for seq, n in sorted(applied_late.items()):
        if n and sum(1 for l in late_lines if l["rxSeq"] == seq and l["afterSeq"] < seq) != n:
            problems.append("seq %d: ns-3 refused %d late, ledger has %d with afterSeq < %d" % (
                seq, n, sum(1 for l in late_lines if l["rxSeq"] == seq and l["afterSeq"] < seq), seq))
    if a.expect is not None and len(lines) != a.expect:
        problems.append("%d ledger lines, expected %d" % (len(lines), a.expect))
    report = {"deltaMs": a.delta_ms, "lines": len(lines), "late": sum(1 for l in lines if l["cause"] == "late"),
              "barriers": len(barrier_ns), "outcomes": sorted({(l["outcome"], l["cause"]) for l in lines}),
              "problems": problems, "pass": not problems}
    json.dump(report, sys.stdout, indent=2)
    print()
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

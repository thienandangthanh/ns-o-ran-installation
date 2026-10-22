#!/usr/bin/env python3
"""check-ledger.py: contract C2 on a lock-step run's control ledger.

Inputs: the ledger (trace/e2-control-ledger.jsonl; missing = no control) and
the pacer log (pacer/pacer-log.jsonl), whose ns-3 `ready` lines give every
barrier's seq and sim time. Checks, per line:
  1. applySimTimeNs - rxSimTimeNs = 0 (d = 0);
  2. rxSeq == afterSeq, except cause `late` (it arrived after its barrier);
  3. rxSimTimeNs is the sim time of the barrier of rxSeq (late lines: the
     stop time, not a barrier);
  4. lines sorted by (rxSeq, imsi, viaNodeId, targetCell, ctlId), written once;
and for the run: the header records delta-model "fixed 0", the number of
lines per seq equals ns-3's `applied` count for that barrier, and with
--expect N the total equals N (controls sent or injected).
Prints one JSON report; exit 0 on pass.

usage: check-ledger.py LEDGER PACER_LOG [--expect N]
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
    a = ap.parse_args()
    rows = []
    if os.path.exists(a.ledger):
        with open(a.ledger) as f:
            rows = [json.loads(l) for l in f if l.strip()]
    barrier_ns, applied = {}, {}
    with open(a.pacer_log) as f:
        for l in f:
            e = json.loads(l)
            m = e["msg"]
            if e["dir"] == "rx" and m.get("type") == "ready":
                barrier_ns[m["seq"]] = m["simTimeNs"]
            if e["dir"] == "rx" and m.get("type") == "applied":
                applied[m["seq"]] = m["controls"]
    problems = []
    lines = rows
    if rows:
        header, lines = rows[0], rows[1:]
        if header.get("type") != "ledgerHeader" or header.get("delta-model") != "fixed 0":
            problems.append("missing or wrong header %r" % header)
    seen = set()
    per_seq = {}
    for l in lines:
        k = (l["viaNodeId"], l["ctlId"])
        if k in seen:
            problems.append("two lines for %r" % (k,))
        seen.add(k)
        if l["applySimTimeNs"] != l["rxSimTimeNs"]:
            problems.append("apply - rx != 0 for %r" % (k,))
        if l["cause"] == "late":
            continue
        per_seq[l["rxSeq"]] = per_seq.get(l["rxSeq"], 0) + 1
        if l["rxSeq"] != l["afterSeq"]:
            problems.append("rxSeq %d != afterSeq %d for %r" % (l["rxSeq"], l["afterSeq"], k))
        if barrier_ns.get(l["rxSeq"]) != l["rxSimTimeNs"]:
            problems.append("rxSimTimeNs %d is not the barrier time %r of seq %d for %r" % (
                l["rxSimTimeNs"], barrier_ns.get(l["rxSeq"]), l["rxSeq"], k))
    order = [(l["rxSeq"], l["imsi"], l["viaNodeId"], l["targetCell"], l["ctlId"]) for l in lines]
    if order != sorted(order):
        problems.append("lines not in (rxSeq, C4) order")
    for seq, n in sorted(per_seq.items()):
        if applied.get(seq) != n:
            problems.append("seq %d: %d ledger lines, ns-3 applied %r" % (seq, n, applied.get(seq)))
    for seq, n in sorted(applied.items()):
        if n and per_seq.get(seq, 0) != n:
            problems.append("seq %d: ns-3 applied %d, ledger has %d" % (seq, n, per_seq.get(seq, 0)))
    if a.expect is not None and len(lines) != a.expect:
        problems.append("%d ledger lines, expected %d" % (len(lines), a.expect))
    report = {"lines": len(lines), "late": sum(1 for l in lines if l["cause"] == "late"),
              "barriers": len(barrier_ns), "outcomes": sorted({(l["outcome"], l["cause"]) for l in lines}),
              "problems": problems, "pass": not problems}
    json.dump(report, sys.stdout, indent=2)
    print()
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""check-c9-handover-trace.py: contract C9, the ns-3 handover rows against the control ledger.

  check-c9-handover-trace.py RUN_DIR [--allow-extra]

RUN_DIR holds trace/e2-control-ledger.jsonl and ns3run/{EnbHandoverStartStats,EnbHandoverEndStats}.txt
(`time imsi rnti sourceCell targetCell` and `time imsi rnti cell`). Checks:
  - every ledger line `applied` has exactly one HandoverStart row for its imsi, from its sourceCell to
    its targetCell, at or after its apply time, and a later HandoverEnd row for that imsi at the target;
  - no HandoverStart or HandoverEnd row is left over (an orphan) unless --allow-extra;
  - so a `refused` line (including late) leaves no row: the row counts equal the applied count.
A missing trace file counts as no rows. Prints one JSON report; exit 0 when there is no problem.
"""
import json
import os
import sys


def rows(path):
    if not os.path.exists(path):
        return []
    return [l.split() for l in open(path) if l.strip()]


def main(argv):
    allow_extra = "--allow-extra" in argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    rd = args[0]
    ledger = os.path.join(rd, "trace", "e2-control-ledger.jsonl")
    lines = [json.loads(l) for l in open(ledger) if l.strip()][1:] if os.path.exists(ledger) else []
    starts = [(float(r[0]), int(r[1]), int(r[3]), int(r[4])) for r in rows(os.path.join(rd, "ns3run", "EnbHandoverStartStats.txt"))]
    ends = [(float(r[0]), int(r[1]), int(r[3])) for r in rows(os.path.join(rd, "ns3run", "EnbHandoverEndStats.txt"))]
    problems = []
    used_s, used_e = set(), set()
    applied = [x for x in lines if x["outcome"] == "applied"]
    for x in applied:
        t_apply = x["applySimTimeNs"] / 1e9
        hs = [i for i, s in enumerate(starts) if i not in used_s and s[1] == x["imsi"] and s[2] == x["sourceCell"]
              and s[3] == x["targetCell"] and s[0] >= t_apply - 1e-9]
        if len(hs) != 1:
            problems.append("applied %r: %d matching HandoverStart rows" % ((x["viaNodeId"], x["ctlId"], x["imsi"]), len(hs)))
            continue
        used_s.add(hs[0])
        he = [i for i, e in enumerate(ends) if i not in used_e and e[1] == x["imsi"] and e[2] == x["targetCell"]
              and e[0] >= starts[hs[0]][0]]
        if not he:
            problems.append("applied %r: no HandoverEnd at cell %d after the start" % ((x["viaNodeId"], x["ctlId"], x["imsi"]), x["targetCell"]))
            continue
        used_e.add(min(he, key=lambda i: ends[i][0]))
    orphans_s = [starts[i] for i in range(len(starts)) if i not in used_s]
    orphans_e = [ends[i] for i in range(len(ends)) if i not in used_e]
    if (orphans_s or orphans_e) and not allow_extra:
        problems.append("orphan rows: %d HandoverStart, %d HandoverEnd" % (len(orphans_s), len(orphans_e)))
    report = {"ledgerLines": len(lines), "applied": len(applied), "refused": len(lines) - len(applied),
              "handoverStartRows": len(starts), "handoverEndRows": len(ends),
              "orphanStarts": orphans_s, "orphanEnds": orphans_e, "problems": problems, "pass": not problems}
    print(json.dumps(report, indent=1))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

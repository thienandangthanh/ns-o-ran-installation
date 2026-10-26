#!/usr/bin/env python3
"""check-c9-handover-trace.py: contract C9, the ns-3 handover rows against the control ledger.

  check-c9-handover-trace.py RUN_DIR [--allow-extra]
  check-c9-handover-trace.py --self-test

RUN_DIR holds trace/e2-control-ledger.jsonl and ns3run/{EnbHandoverStartStats,EnbHandoverEndStats}.txt
(`time imsi rnti sourceCell targetCell` and `time imsi rnti cell`). Each `applied` line owns its IMSI's
window [its apply time, the IMSI's next applied line's apply time). Checks:
  - the ledger's source differs from its target, and no two applied lines of one IMSI share an apply time;
  - exactly one HandoverStart row of that IMSI (any cells) lies in the window, and it goes from the line's
    sourceCell to its targetCell;
  - exactly one HandoverEnd row of that IMSI lies between that start and the window's end, at the target;
  - no HandoverStart or HandoverEnd row is left over (an orphan) unless --allow-extra;
  - so a `refused` line (including late) leaves no row: the row counts equal the applied count.
The window matters when an IMSI repeats the same source and target (the R2 calibration block): without it a
row could be attributed to an earlier control whose own row is missing. Only applied lines bound a window, so
a refused line in the same step does not split one. A missing trace file counts as no rows. Prints one JSON
report; exit 0 when there is no problem. --self-test judges fixtures/c9-r2-calib and mutated copies of it.
"""
import json
import os
import shutil
import sys
import tempfile
from collections import defaultdict

EPS = 1e-9


def rows(path):
    if not os.path.exists(path):
        return []
    return [l.split() for l in open(path) if l.strip()]


def judge(rd, allow_extra=False):
    ledger = os.path.join(rd, "trace", "e2-control-ledger.jsonl")
    lines = [json.loads(l) for l in open(ledger) if l.strip()][1:] if os.path.exists(ledger) else []
    starts = [(float(r[0]), int(r[1]), int(r[3]), int(r[4])) for r in rows(os.path.join(rd, "ns3run", "EnbHandoverStartStats.txt"))]
    ends = [(float(r[0]), int(r[1]), int(r[3])) for r in rows(os.path.join(rd, "ns3run", "EnbHandoverEndStats.txt"))]
    problems = []
    used_s, used_e = set(), set()
    applied = [x for x in lines if x["outcome"] == "applied"]
    by_imsi = defaultdict(list)
    for x in applied:
        by_imsi[x["imsi"]].append(x)
    for imsi in sorted(by_imsi):
        xs = sorted(by_imsi[imsi], key=lambda x: x["applySimTimeNs"])
        for k, x in enumerate(xs):
            tag = (x["viaNodeId"], x["ctlId"], imsi)
            lo = x["applySimTimeNs"] / 1e9
            hi = xs[k + 1]["applySimTimeNs"] / 1e9 if k + 1 < len(xs) else float("inf")
            if x["sourceCell"] == x["targetCell"]:
                problems.append("applied %r: ledger source == target %d" % (tag, x["targetCell"]))
                continue
            if hi - lo < EPS:
                problems.append("applied %r: another applied line of imsi %d at the same apply time" % (tag, imsi))
                continue
            hs = [i for i, s in enumerate(starts) if s[1] == imsi and lo - EPS <= s[0] < hi - EPS]
            if len(hs) != 1:
                problems.append("applied %r: %d HandoverStart rows for imsi %d in [%.6f, %s)" % (tag, len(hs), imsi, lo, hi))
                continue
            s = starts[hs[0]]
            used_s.add(hs[0])
            if (s[2], s[3]) != (x["sourceCell"], x["targetCell"]):
                problems.append("applied %r: HandoverStart %r is not %d->%d" % (tag, s, x["sourceCell"], x["targetCell"]))
                continue
            he = [i for i, e in enumerate(ends) if e[1] == imsi and s[0] - EPS <= e[0] < hi - EPS]
            if len(he) != 1:
                problems.append("applied %r: %d HandoverEnd rows for imsi %d after its start in the window" % (tag, len(he), imsi))
                continue
            used_e.add(he[0])
            if ends[he[0]][2] != x["targetCell"]:
                problems.append("applied %r: HandoverEnd %r not at target %d" % (tag, ends[he[0]], x["targetCell"]))
    orphans_s = [starts[i] for i in range(len(starts)) if i not in used_s]
    orphans_e = [ends[i] for i in range(len(ends)) if i not in used_e]
    if (orphans_s or orphans_e) and not allow_extra:
        problems.append("orphan rows: %d HandoverStart, %d HandoverEnd" % (len(orphans_s), len(orphans_e)))
    return {"ledgerLines": len(lines), "applied": len(applied), "refused": len(lines) - len(applied),
            "handoverStartRows": len(starts), "handoverEndRows": len(ends),
            "orphanStarts": orphans_s, "orphanEnds": orphans_e, "problems": problems, "pass": not problems}


def self_test():
    """The R2 calibration run (25 applied lines; IMSIs repeat the same source and target) must pass, and
    every mutation of it must fail, including a mis-attribution a windowless matcher would accept."""
    fx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "c9-r2-calib")
    L0 = [l for l in open(os.path.join(fx, "trace", "e2-control-ledger.jsonl")) if l.strip()]
    S0 = rows(os.path.join(fx, "ns3run", "EnbHandoverStartStats.txt"))
    E0 = rows(os.path.join(fx, "ns3run", "EnbHandoverEndStats.txt"))

    def at(rs, t):
        return [i for i, r in enumerate(rs) if r[0] == t][0]

    def m(fn):
        def run(L, S, E):
            fn(L, S, E)
            return L, S, E
        return run

    cases = [
        ("identity", True, m(lambda L, S, E: None)),
        ("ledger and rows reordered", True, m(lambda L, S, E: (L.__setitem__(slice(1, None), L[:0:-1]), S.reverse(), E.reverse()))),
        ("dropped Start", False, m(lambda L, S, E: S.pop(at(S, "4.6038")))),
        ("Start to the wrong target", False, m(lambda L, S, E: S[at(S, "4.6038")].__setitem__(4, "1"))),
        ("Start with source == target", False, m(lambda L, S, E: S[at(S, "4.6038")].__setitem__(4, "3"))),
        ("orphan Start before the first apply", False, m(lambda L, S, E: S.append(["0.5", "1", "1", "3", "2"]))),
        ("End before its Start", False, m(lambda L, S, E: E[at(E, "4.60552")].__setitem__(0, "4.6020"))),
        ("Start before its apply", False, m(lambda L, S, E: S[at(S, "4.6038")].__setitem__(0, "4.6000"))),
        ("mis-attribution: early Start dropped, same triple added late", False,
         m(lambda L, S, E: (E.pop(at(E, "4.60552")), S.pop(at(S, "4.6038")),
                            S.append(["8.3038", "1", "13", "3", "2"]), E.append(["8.30552", "1", "17", "2"])))),
        ("Start after the IMSI's next apply", False, m(lambda L, S, E: S[at(S, "1.0038")].__setitem__(0, "2.9"))),
        ("End at the wrong cell", False, m(lambda L, S, E: E[at(E, "4.60552")].__setitem__(3, "3"))),
        ("applied turned refused, rows kept", False, m(lambda L, S, E: L.__setitem__(13, L[13].replace('"applied"', '"refused"')))),
        ("duplicate End", False, m(lambda L, S, E: E.append(["4.7", "1", "11", "2"]))),
        ("dropped End", False, m(lambda L, S, E: E.pop(at(E, "4.60552")))),
        ("End after the IMSI's next apply", False, m(lambda L, S, E: E[at(E, "4.60552")].__setitem__(0, "6.5"))),
    ]
    bad = 0
    for name, want, fn in cases:
        L, S, E = fn(list(L0), [list(r) for r in S0], [list(r) for r in E0])
        d = tempfile.mkdtemp()
        try:
            os.makedirs(os.path.join(d, "trace"))
            os.makedirs(os.path.join(d, "ns3run"))
            open(os.path.join(d, "trace", "e2-control-ledger.jsonl"), "w").write("".join(L))
            open(os.path.join(d, "ns3run", "EnbHandoverStartStats.txt"), "w").write("".join(" ".join(r) + "\n" for r in S))
            open(os.path.join(d, "ns3run", "EnbHandoverEndStats.txt"), "w").write("".join(" ".join(r) + "\n" for r in E))
            got = judge(d)["pass"]
        finally:
            shutil.rmtree(d)
        ok = got == want
        bad += not ok
        print("%s c9 self-test: %s (pass=%s, want %s)" % ("ok" if ok else "FAIL", name, got, want))
    return 0 if bad == 0 else 1


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    allow_extra = "--allow-extra" in argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    report = judge(args[0], allow_extra)
    print(json.dumps(report, indent=1))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

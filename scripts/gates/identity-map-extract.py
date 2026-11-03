#!/usr/bin/env python3
"""identity-map-extract.py: freeze the checkpoint-1 UE identity map (plan R-8) from ns-3's own trace.

  identity-map-extract.py PDCP_LTE_TRACE --source-label LABEL [--mn-cell 1] [--plmn 00F110] [--macro-enb 00001]
  identity-map-extract.py --self-test

PDCP_LTE_TRACE is a run's ns3run/DlE2PdcpStatsLte.txt (header "% start end CellId IMSI RNTI LCID ..."): the master
node's PDCP rows per UE. The map gives, per IMSI, the MN's LTE RNTI, which is the m-eNB-UE-X2AP-ID an en-gNB holds for
that UE (plan R-4). The script refuses to write a map unless every row is on the MN cell and every IMSI has exactly
one RNTI for the whole run. Output (stdout, JSON):
  {"source": LABEL, "sourceSha256": ..., "mnCellId": 1, "globalEnbId": {"plmn": ..., "macroEnbId": ...},
   "ues": {"<imsi>": {"mEnbUeX2apId": <rnti>}}}
The map is frozen at checkpoint 1 and never regenerated from later output; P08's transform reads it.
"""
import argparse
import hashlib
import json
import sys
import tempfile


def extract(path, mn_cell):
    ues, problems = {}, []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            p = line.split()
            if not p or p[0].startswith("%"):
                continue
            cell, imsi, rnti = int(p[2]), int(p[3]), int(p[4])
            if cell != mn_cell:
                problems.append("line %d: cell %d is not the MN cell %d" % (n, cell, mn_cell))
                continue
            ues.setdefault(imsi, set()).add(rnti)
    for imsi, rntis in sorted(ues.items()):
        if len(rntis) != 1:
            problems.append("IMSI %d has %d RNTIs on the MN cell: %s" % (imsi, len(rntis), sorted(rntis)))
    if not ues:
        problems.append("no UE rows")
    return {str(i): {"mEnbUeX2apId": next(iter(r))} for i, r in sorted(ues.items()) if len(r) == 1}, problems


def self_test():
    hdr = "% start\tend\tCellId\tIMSI\tRNTI\tLCID\n"
    def run(rows):
        f = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False)
        f.write(hdr + "".join("0.1\t0.2\t%d\t%d\t%d\t3\n" % r for r in rows)); f.close()
        return extract(f.name, 1)
    ues, pr = run([(1, 1, 3), (1, 2, 4), (1, 1, 3)])
    assert not pr and ues == {"1": {"mEnbUeX2apId": 3}, "2": {"mEnbUeX2apId": 4}}, (ues, pr)
    assert run([(1, 1, 3), (1, 1, 5)])[1], "two RNTIs for one IMSI must fail"
    assert run([(1, 1, 3), (2, 2, 4)])[1], "a row on a non-MN cell must fail"
    print("identity-map-extract self-test: ok")
    return 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("trace")
    ap.add_argument("--source-label", required=True, help="<path>@<cp1 sha>")
    ap.add_argument("--mn-cell", type=int, default=1)
    ap.add_argument("--plmn", default="00F110")
    ap.add_argument("--macro-enb", default="00001")
    a = ap.parse_args()
    ues, problems = extract(a.trace, a.mn_cell)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    sha = hashlib.sha256(open(a.trace, "rb").read()).hexdigest()
    print(json.dumps({"source": a.source_label, "sourceSha256": sha, "mnCellId": a.mn_cell,
                      "globalEnbId": {"plmn": a.plmn, "macroEnbId": a.macro_enb}, "ues": ues}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

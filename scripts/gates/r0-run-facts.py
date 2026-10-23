#!/usr/bin/env python3
"""r0-run-facts.py EVIDENCE_DIR: per-run facts of an R-rung gate, gathered into one verdict record.

For every RIC-bearing run under EVIDENCE_DIR/runs/ (live1..3, k9, calib; any that exist):
  c2             the answer identity from the wire extractor: answers = ledger lines + agent-local answers
  c5             pairsByReqId and answerViaNodeId from the wire extractor
  resetEvidence  the per-run reset record (bucket id, pods before and after, fresh)
and over the live runs:
  kpmUeListMoved per applied IMSI, true when its move shows in the decoded KPM UE lists of every live run
Prints the record; exit 1 when any of them is missing or false, or when no live run applied a control.
"""
import glob
import json
import os
import sys


def load(p):
    try:
        return json.load(open(p))
    except (OSError, ValueError):
        return None


def main(e):
    runs = sorted(os.path.basename(d) for d in glob.glob(os.path.join(e, "runs", "*"))
                  if os.path.exists(os.path.join(d, "extra", "c1-extract-summary.json")) or
                  os.path.exists(os.path.join(e, os.path.basename(d) + "-reset.json")))
    out = {"runs": runs, "c2": {}, "c5": {}, "resetEvidence": {}, "kpmUeListMoved": {}, "problems": []}
    pr = out["problems"]
    for r in runs:
        summ = load(os.path.join(e, "runs", r, "extra", "c1-extract-summary.json"))
        if summ is None or summ.get("c2") is None or summ.get("c5") is None:
            pr.append("%s: no wire extractor summary with c2 and c5" % r)
        else:
            out["c2"][r] = summ["c2"]
            out["c5"][r] = summ["c5"]
            if not summ["c2"]["holds"]:
                pr.append("%s: answers != ledger lines + agent-local %r" % (r, summ["c2"]))
            if not (summ["c5"]["pairsByReqId"] and summ["c5"]["answerViaNodeId"]):
                pr.append("%s: c5 %r" % (r, summ["c5"]))
        rec = load(os.path.join(e, r + "-reset.json"))
        if rec is None:
            pr.append("%s: no reset record" % r)
        else:
            out["resetEvidence"][r] = {k: rec[k] for k in ("resetStartUtc", "bucketBefore", "bucketAfter", "fresh")}
            out["resetEvidence"][r]["podsAfter"] = rec["podsAfter"]
            if not rec["fresh"]:
                pr.append("%s: reset not fresh %r" % (r, rec["problems"]))
    live = [r for r in runs if r.startswith("live")]
    if not live:
        pr.append("no live run")
    for r in live:
        m = load(os.path.join(e, "runs", r, "kpm-ue-moves.json"))
        if m is None or not m.get("pass"):
            pr.append("%s: KPM UE-list check missing or failed" % r)
            continue
        if not m["kpmUeListMoved"]:
            pr.append("%s: no applied control to judge" % r)
        for imsi, ok in m["kpmUeListMoved"].items():
            out["kpmUeListMoved"][imsi] = out["kpmUeListMoved"].get(imsi, True) and ok
    if live and set(out["kpmUeListMoved"]) and not all(out["kpmUeListMoved"].values()):
        pr.append("kpmUeListMoved %r" % out["kpmUeListMoved"])
    out["pass"] = not pr
    c5 = out["c5"].values()
    out["c5"] = {"pairsByReqId": bool(c5) and all(v["pairsByReqId"] for v in c5),
                 "answerViaNodeId": bool(c5) and all(v["answerViaNodeId"] for v in c5), "perRun": out["c5"]}
    print(json.dumps(out, sort_keys=True))
    return 0 if not pr else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))

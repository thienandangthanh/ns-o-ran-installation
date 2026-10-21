#!/usr/bin/env python3
"""recovery-eval.py <polls.tsv> --after EPOCH --expected-names FILE [--out summary.json]

Reads the post-delete poll log of gate M7. One line per poll, tab separated:
  <epoch> <comma list of e2mgr CONNECTED names> <node:restart:running:state:subs:indTx> ...
Per node (id = the gNB-ID in the e2mgr name, gnb_001_001_0000000N), at poll resolution:
  restarted_s       first poll with RestartCount >= 1
  connected_s       first poll after that with the node in the e2mgr CONNECTED set and agent state READY
  first_ind_s       first poll after that with indTx > 0 (counters restart with the process)
All times are seconds after --after (the delete). Exit 1 unless every node has all three
(i.e. the node restarted, reconnected and indications resumed). Wire-exact times come from
e2-facts-query.py post-delete; this log bounds the wait and gives the restart evidence.
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("polls")
    ap.add_argument("--after", type=float, required=True)
    ap.add_argument("--expected-names", required=True)
    ap.add_argument("--out")
    a = ap.parse_args()
    names = {int(n[-8:], 16): n for n in open(a.expected_names).read().split() if n}
    res = {str(i): {"name": n, "restarted_s": None, "connected_s": None, "first_ind_s": None, "max_restart": 0}
           for i, n in names.items()}
    polls = 0
    for line in open(a.polls):
        c = line.rstrip("\n").split("\t")
        if len(c) < 3:
            continue
        t = float(c[0])
        if t < a.after:
            continue
        polls += 1
        conn = set(x for x in c[1].split(",") if x)
        for tok in c[2].split():
            nid, rc, run, state, subs, ind = (tok.split(":") + ["0"] * 6)[:6]
            r = res.get(nid)
            if r is None:
                continue
            rel = round(t - a.after, 1)
            r["max_restart"] = max(r["max_restart"], int(rc))
            if int(rc) >= 1 and r["restarted_s"] is None:
                r["restarted_s"] = rel
            if r["restarted_s"] is not None and r["connected_s"] is None and r["name"] in conn and state == "READY":
                r["connected_s"] = rel
            if r["connected_s"] is not None and r["first_ind_s"] is None and int(ind) > 0:
                r["first_ind_s"] = rel
    bad = []
    for nid, r in sorted(res.items(), key=lambda kv: int(kv[0])):
        print("node %s (%s): %s" % (nid, r["name"], json.dumps({k: v for k, v in r.items() if k != "name"})))
        for k in ("restarted_s", "connected_s", "first_ind_s"):
            if r[k] is None:
                bad.append("node %s never reached %s" % (nid, k))
    print("%d polls after the delete" % polls)
    if a.out:
        json.dump(res, open(a.out, "w"), indent=1, sort_keys=True)
    for b in bad:
        print("PROBLEM: " + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

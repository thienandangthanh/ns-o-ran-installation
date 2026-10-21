#!/usr/bin/env python3
"""influx-node-rows.py <flux-csv> [--after EPOCH] [--nodes 1,2,3] [--out summary.json]

Counts Influx points per `ns3.nodeId` value (kpimon writes no tags, so the
nodeId field is the only per-node key). Input: Flux --raw CSV of the
`ns3.nodeId` field series (columns _time and _value). With --after, rows are
split into before/after that wall-clock epoch and the first row time after it
is reported (seconds since --after). Exit 1 when --nodes is given and a node has
no row after --after (or no row at all without --after).
"""
import argparse
import csv
import datetime
import io
import json
import sys


def parse_time(s):
    s = s.rstrip("Z")
    head, _, frac = s.partition(".")
    dt = datetime.datetime.strptime(head, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc)
    return dt.timestamp() + (float("0." + frac) if frac else 0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--after", type=float)
    ap.add_argument("--nodes")
    ap.add_argument("--out")
    a = ap.parse_args()
    per, hdr = {}, None
    for line in open(a.csv):
        line = line.rstrip("\r\n")
        if not line or line.startswith("#"):
            continue
        rec = next(csv.reader(io.StringIO(line)))
        if "_value" in rec and "_time" in rec:
            hdr = {n: i for i, n in enumerate(rec)}
            continue
        if hdr is None or len(rec) <= max(hdr.values()):
            continue
        try:
            nid, t = str(int(float(rec[hdr["_value"]]))), parse_time(rec[hdr["_time"]])
        except ValueError:
            continue
        d = per.setdefault(nid, {"total": 0, "before": 0, "after": 0, "first_after_s": None})
        d["total"] += 1
        if a.after is not None:
            if t >= a.after:
                d["after"] += 1
                s = round(t - a.after, 2)
                d["first_after_s"] = s if d["first_after_s"] is None else min(d["first_after_s"], s)
            else:
                d["before"] += 1
    bad = []
    for nid in (a.nodes.split(",") if a.nodes else []):
        d = per.get(nid)
        if not d or (d["after"] if a.after is not None else d["total"]) == 0:
            bad.append("node %s: no rows%s" % (nid, " after the delete" if a.after is not None else ""))
    for nid, d in sorted(per.items()):
        print("nodeId %s: %s" % (nid, json.dumps(d)))
    for b in bad:
        print("PROBLEM: " + b)
    if a.out:
        json.dump(per, open(a.out, "w"), indent=1, sort_keys=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

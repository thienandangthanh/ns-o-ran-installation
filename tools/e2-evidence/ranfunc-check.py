#!/usr/bin/env python3
"""ranfunc-check.py <harness-ranfunc.jsonl> --map metric-map.v1.json --kind gnb|enb
        --map-sha256 <full sha256 of the map file> --oid OID --short-name NAME

Checks the output of `kpimon-decode-harness --ranfunc` (the agent's RAN function
definition decoded by kpimon's own libe2smwrapper.so, buildRanCellUeKpi, plus a
strict asn_decode) against metric-map.v1.json:
  - strict decode RC_OK with every octet consumed;
  - short name, OID, and the map sha8 in the description ("ns-O-RAN KPM map v1 <sha8>");
  - kpimon's cell and UE name lists have the map's length AND equal the map's
    names in order (kpimon divides by these lengths and walks records by them);
  - the two report styles carry the same name lists.
Exit 0 on pass; prints the figures either way.
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jsonl")
    ap.add_argument("--map", required=True)
    ap.add_argument("--kind", required=True)
    ap.add_argument("--map-sha256", required=True)
    ap.add_argument("--oid", required=True)
    ap.add_argument("--short-name", required=True)
    a = ap.parse_args()
    rows = [r for r in json.load(open(a.map))["rows"] if r["kind"] == a.kind]
    want = {l: [r["kpm"] for r in sorted((x for x in rows if x["list"] == l), key=lambda x: x["order"])]
            for l in ("cell", "ue")}
    lines = [json.loads(x) for x in open(a.jsonl) if x.strip()]
    bad = []
    if len(lines) != 1:
        sys.exit("expected exactly one ranfunc record, got %d" % len(lines))
    d = lines[0]
    s, k = d["strict"], d.get("kpimon", {"cell": [], "ue": []})
    print("octets %s, strict %s consumed %s" % (d["len"], s["code"], s.get("consumed")))
    print("short=%s oid=%s description=%r" % (s.get("shortName"), s.get("oid"), s.get("description")))
    print("kpimon cell=%d ue=%d; map(%s) cell=%d ue=%d" % (len(k["cell"]), len(k["ue"]), a.kind, len(want["cell"]), len(want["ue"])))
    if s["code"] != "RC_OK" or s.get("consumed") != d["len"]:
        bad.append("strict decode not clean")
    if s.get("shortName") != a.short_name:
        bad.append("short name %r" % s.get("shortName"))
    if s.get("oid") != a.oid:
        bad.append("oid %r" % s.get("oid"))
    sha8 = a.map_sha256[:8]
    if not (s.get("description") or "").endswith(" " + sha8):
        bad.append("description does not end with the map sha8 %s" % sha8)
    for l in ("cell", "ue"):
        if len(k[l]) != len(want[l]):
            bad.append("kpimon %s list length %d != map %d" % (l, len(k[l]), len(want[l])))
        elif k[l] != want[l]:
            bad.append("kpimon %s names differ from the map" % l)
    styles = {st["type"]: st["names"] for st in s.get("styles", [])}
    if styles.get(1) != want["cell"] or styles.get(3) != want["ue"]:
        bad.append("report-style name lists (types 1/3) differ from the map")
    for b in bad:
        print("PROBLEM: " + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

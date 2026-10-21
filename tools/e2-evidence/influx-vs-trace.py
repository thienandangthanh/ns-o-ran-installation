#!/usr/bin/env python3
"""influx-vs-trace.py --map metric-map.v1.json --trace e2-ipc-trace-N.jsonl
        --influx-cell cell.csv --influx-ue ue.csv --out result.json [--node N]

Compares the InfluxDB rows kpimon wrote against the ns-3 IPC trace (ground
truth, one JSON line per hello/sample/bye, written before every send).

Join keys (kpimon writes no tags and stamps wall-clock time, so _time is never
used): cellMetrics row = (ns3.nodeId, ns3.seq); UeMetrics row = (ns3.nodeId,
ns3.seq, ns3.imsi). Expected value of every mapped field = the trace value
converted by the metric-map rules (the agent's own rules, re-implemented here):
  INTEGER  exact int in 0..2^31-1, else noValue (field absent in Influx)
  REAL     float64, compared bit-exact (struct pack of the parsed CSV value)
  noValue  field absent (empty pivot cell)
Rows of the node's kind (gnb or enb, from the trace hello) are used.

Inputs are the pivoted Flux CSV exports (one row per point, one column per field).
Picks (hard result): the first sample with UEs, the middle sample and the last
sample. If a pick has no complete rows in Influx the nearest complete sample is
used and the substitution is recorded (`fallback_from`); a pick with no
candidate at all fails. All samples are also compared (informational numbers).
Exit 0 when all picks are found and equal.
"""
import argparse
import csv
import io
import json
import math
import struct
import sys


def bits(x):
    return "%016x" % struct.unpack("<Q", struct.pack("<d", float(x)))[0]


def resolve(root, pointer):
    cur = root
    for t in pointer[1:].split("/"):
        if isinstance(cur, dict) and t in cur:
            cur = cur[t]
        elif isinstance(cur, list) and t.isdigit() and int(t) < len(cur):
            cur = cur[int(t)]
        else:
            return None
    return cur


def expect(row, v):
    """Expected Influx value for one map row: ('none',) | ('int', n) | ('real', bits)."""
    if v is None or isinstance(v, bool):
        return ("none",)
    if row["type"] == "REAL":
        x = float(v)
        if row["xform"] == "ns_to_ms_floor":
            x = math.floor(x / 1e6)
        return ("real", bits(x))
    if isinstance(v, float):
        if v != math.floor(v):
            return ("none",)
        v = int(v)
    if row["xform"] == "ns_to_ms_floor":
        v = v // 1000000
    return ("int", v) if 0 <= v <= 2147483647 else ("none",)


def same(exp, got):
    if exp[0] == "none":
        return got is None
    if got is None:
        return False
    return int(got) == exp[1] if exp[0] == "int" else bits(float(got)) == exp[1]


def read_rows(path):
    """Yield dict(column -> str|None) for every data row of a Flux --raw CSV (tables may repeat headers)."""
    hdr = None
    for line in open(path):
        line = line.rstrip("\r\n")
        if not line or line.startswith("#"):
            continue
        rec = next(csv.reader(io.StringIO(line)))
        if "_measurement" in rec:
            hdr = rec
            continue
        if hdr is not None and len(rec) == len(hdr):
            yield {n: (v if v != "" else None) for n, v in zip(hdr, rec)}


def index_rows(path, node, with_imsi):
    idx, dup = {}, 0
    for r in read_rows(path):
        try:
            if r.get("ns3.nodeId") is None or int(r["ns3.nodeId"]) != node:
                continue
            key = (int(r["ns3.seq"]), int(r["ns3.imsi"])) if with_imsi else int(r["ns3.seq"])
        except (KeyError, TypeError, ValueError):
            continue
        if key in idx:
            dup += 1
        idx[key] = r
    return idx, dup


def compare_row(rows, root, ue_obj, got):
    n = bad = 0
    diffs = []
    for row in rows:
        src = ue_obj if row["scope"] == "ue" else root
        e = expect(row, resolve(src, row["src"]))
        g = got.get(row["kpm"])
        n += 1
        if not same(e, g):
            bad += 1
            if len(diffs) < 3:
                diffs.append({"field": row["kpm"], "influx": g, "expected": e})
    return n, bad, diffs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", required=True)
    ap.add_argument("--trace", required=True)
    ap.add_argument("--influx-cell", required=True)
    ap.add_argument("--influx-ue", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--node", type=int)
    a = ap.parse_args()

    samples, hello = {}, None
    for line in open(a.trace):
        m = json.loads(line)
        if m["type"] == "hello":
            hello = m
        elif m["type"] == "sample":
            samples[m["seq"]] = m
    if not hello or not samples:
        sys.exit("trace has no hello/sample lines")
    node = a.node if a.node is not None else hello["nodeId"]
    kind = hello["kind"]
    rows = [r for r in json.load(open(a.map))["rows"] if r["kind"] == kind]
    cell = sorted((r for r in rows if r["list"] == "cell"), key=lambda r: r["order"])
    ue = sorted((r for r in rows if r["list"] == "ue"), key=lambda r: r["order"])
    cell_idx, cell_dup = index_rows(a.influx_cell, node, False)
    ue_idx, ue_dup = index_rows(a.influx_ue, node, True)

    def check_sample(seq):
        s = samples[seq]
        res = {"seq": seq, "ues": [u["imsi"] for u in s["ues"]], "cell_row": seq in cell_idx,
               "ue_rows": sum((seq, u["imsi"]) in ue_idx for u in s["ues"]), "fields": 0, "differ": 0, "diffs": []}
        res["complete"] = res["cell_row"] and res["ue_rows"] == len(s["ues"])
        if res["cell_row"]:
            n, b, d = compare_row(cell, s, None, cell_idx[seq])
            res["fields"] += n; res["differ"] += b; res["diffs"] += d
        for u in s["ues"]:
            if (seq, u["imsi"]) in ue_idx:
                n, b, d = compare_row(ue, s, u, ue_idx[(seq, u["imsi"])])
                res["fields"] += n; res["differ"] += b; res["diffs"] += [dict(x, imsi=u["imsi"]) for x in d]
        return res

    seqs = sorted(samples)
    first_ue = next((q for q in seqs if samples[q]["ues"]), None)
    targets = [("first_with_ues", first_ue), ("middle", seqs[len(seqs) // 2]), ("last", seqs[-1])]
    complete = {q for q in seqs if q in cell_idx and all((q, u["imsi"]) in ue_idx for u in samples[q]["ues"])}
    picks, ok = [], first_ue is not None
    for label, seq in targets:
        if seq is None:
            picks.append({"label": label, "error": "no sample with UEs in the trace"})
            ok = False
            continue
        use = seq
        if seq not in complete:
            order = sorted(complete, key=lambda q: abs(q - seq))
            if label == "first_with_ues":
                order = [q for q in order if samples[q]["ues"]]
            use = order[0] if order else None
        if use is None:
            picks.append({"label": label, "seq": seq, "error": "no complete sample in Influx"})
            ok = False
            continue
        r = check_sample(use)
        r.update(label=label, fallback_from=None if use == seq else seq)
        picks.append(r)
        ok = ok and r["complete"] and r["differ"] == 0 and r["fields"] > 0
    allres = [check_sample(q) for q in seqs]
    summary = {
        "node": node, "kind": kind, "trace_samples": len(seqs), "trace_ue_rows": sum(len(samples[q]["ues"]) for q in seqs),
        "influx_cell_rows": len(cell_idx), "influx_ue_rows": len(ue_idx), "duplicate_keys": cell_dup + ue_dup,
        "all_samples_complete": sum(r["complete"] for r in allres), "all_fields_compared": sum(r["fields"] for r in allres),
        "all_fields_differ": sum(r["differ"] for r in allres), "all_first_diffs": [d for r in allres for d in r["diffs"]][:5],
    }
    json.dump({"picks": picks, "all": summary, "ok": ok}, open(a.out, "w"), indent=1, sort_keys=True)
    for p in picks:
        print("pick %-15s seq=%s fallback_from=%s ues=%s cell_row=%s ue_rows=%s fields=%s differ=%s %s" % (
            p["label"], p.get("seq"), p.get("fallback_from"), len(p.get("ues", [])), p.get("cell_row"),
            p.get("ue_rows"), p.get("fields"), p.get("differ"), p.get("error", "")))
    print("all samples: %s" % json.dumps(summary, sort_keys=True))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""check-n4-v5-windows.py: the pre-registered V5 rule n4-v5-r1 over every 16-seq window of each gNB cell.

Rows: one per gNB cell report, keyed by (ns3.nodeId, ns3.seq), never by time; the gNB node ids
come from the run's IPC hello lines (kind gnb). Windows: every run of 16 consecutive seq values all
present for one cell, sliding by 1, start-up and tail included. A window passes iff
  (a) DRB.PdcpSduVolumeUL and DRB.PdcpSduVolumeDL are present in all 16 rows as integers
      (Influx datatype long; in IPC mode, JSON ints),
  (b) QP's PROCESS.constant() (ric-app-qp@47a35ca src/qptrain.py:81-92, reproduced below) is
      False on the window's [UL, DL] frame, i.e. at least 10 distinct (UL, DL) rows survive, and
  (c) neither column is all zero in the window.
V5 passes iff every window of every gNB cell passes and every gNB cell has at least one window.
Per-series distinct counts are reported as diagnostics only.

  check-n4-v5-windows.py --trace RUN/trace --influx DUMP.csv   the K18 dump (the V5 verdict)
  check-n4-v5-windows.py --trace RUN/trace --ipc               the same rule on the IPC samples (calibration)
  check-n4-v5-windows.py --self-test
"""
import argparse
import collections
import csv
import io
import json
import pathlib
import sys

import pandas as pd

UL, DL = "DRB.PdcpSduVolumeUL", "DRB.PdcpSduVolumeDL"
THPTPARAM = [UL, DL]  # QP's db.thptparam under the G1 mapping (QP inputs = the two PDCP SDU rows)
WIN = 16


def qp_constant(data):
    """ric-app-qp@47a35ca src/qptrain.py:81-92 PROCESS.constant(), with self.data = data."""
    val = True
    df = data.copy()
    df = df[THPTPARAM]
    df = df.drop_duplicates()
    df = df.loc[:, df.apply(pd.Series.nunique) != 1]
    if df is not None:
        df = df.dropna()
        df = df.loc[:, (df != 0).any(axis=0)]
        if len(df) >= 10:
            val = False
    return val


def gnb_nodes(trace_dir):
    nodes = set()
    for p in sorted(pathlib.Path(trace_dir).glob("e2-ipc-trace-*.jsonl")):
        with open(p) as f:
            for line in f:
                m = json.loads(line)
                if m.get("type") == "hello" and m.get("kind") == "gnb":
                    nodes.add(m["nodeId"])
                    break
    return nodes


def rows_from_ipc(trace_dir, gnbs):
    rows = {}
    for p in sorted(pathlib.Path(trace_dir).glob("e2-ipc-trace-*.jsonl")):
        for line in p.read_text().splitlines():
            m = json.loads(line) if line.strip() else {}
            if m.get("type") == "sample" and m["nodeId"] in gnbs:
                cu = (m.get("cell") or {}).get("cuUp") or {}
                rows[(m["nodeId"], m["seq"])] = {k: (cu[k], type(cu[k]) is int) for k in THPTPARAM if k in cu}
    return rows


def rows_from_influx(path, gnbs):
    """Annotated CSV (influx query --raw) -> {(nodeId, seq): {field: (value, isLong)}} for cellMetrics."""
    points = collections.defaultdict(dict)
    dtypes = None
    header = None
    for block in pathlib.Path(path).read_text().split("\n\n"):
        lines = [l for l in block.splitlines() if l.strip()]
        for rec in csv.reader(io.StringIO("\n".join(lines))):
            if not rec:
                continue
            if rec[0] == "#datatype":
                dtypes, header = rec, None
                continue
            if rec[0].startswith("#"):
                continue
            if header is None:
                header = rec
                continue
            r = dict(zip(header, rec))
            if r.get("_measurement") != "cellMetrics":
                continue
            dt = dtypes[header.index("_value")] if dtypes else ""
            skip = {"", "result", "table", "_start", "_stop", "_value", "_field", "_measurement"}
            key = (r["_time"],) + tuple(sorted((k, v) for k, v in r.items() if k not in skip and k != "_time"))
            raw = r["_value"]
            val = int(raw) if dt == "long" else float(raw) if dt == "double" else raw
            points[key][r["_field"]] = (val, dt == "long")
    rows = {}
    for f in points.values():
        if "ns3.nodeId" not in f or "ns3.seq" not in f:
            continue
        node, seq = int(f["ns3.nodeId"][0]), int(f["ns3.seq"][0])
        if node in gnbs:
            rows[(node, seq)] = {k: f[k] for k in THPTPARAM if k in f}
    return rows


def judge(rows, gnbs):
    out = {"gnbNodes": sorted(gnbs), "cells": {}, "windowsTotal": 0, "windowsFailed": 0}
    ok = bool(gnbs)
    for node in sorted(gnbs):
        seqs = sorted(s for n, s in rows if n == node)
        present = set(seqs)
        cell = {"rows": len(seqs), "windows": 0, "failed": [], "distinctUL": [], "distinctDL": []}
        for s in seqs:
            win = list(range(s, s + WIN))
            if not all(x in present for x in win):
                continue
            cell["windows"] += 1
            rs = [rows[(node, x)] for x in win]
            why = []
            if not all(k in r and r[k][1] for r in rs for k in THPTPARAM):
                why.append("a")
            else:
                df = pd.DataFrame({k: [r[k][0] for r in rs] for k in THPTPARAM})
                cell["distinctUL"].append(int(df[UL].nunique()))
                cell["distinctDL"].append(int(df[DL].nunique()))
                if qp_constant(df):
                    why.append("b")
                if any((df[k] == 0).all() for k in THPTPARAM):
                    why.append("c")
            if why:
                cell["failed"].append({"firstSeq": s, "clauses": why})
        for k in ("distinctUL", "distinctDL"):
            v = cell[k]
            cell[k] = {"min": min(v), "max": max(v)} if v else None
        out["windowsTotal"] += cell["windows"]
        out["windowsFailed"] += len(cell["failed"])
        cell["failed"] = cell["failed"][:20]
        ok &= cell["windows"] > 0 and not cell["failed"]
        out["cells"][str(node)] = cell
    out["rule"] = "n4-v5-r1"
    out["pass"] = ok
    return out


def self_test():
    gnbs = {2}
    vary = {(2, s): {UL: (100 + s % 12, True), DL: (8371, True)} for s in range(1, 41)}
    flat = {(2, s): {UL: (100 + s % 5, True), DL: (8371, True)} for s in range(1, 41)}
    zero = {(2, s): {UL: (0, True), DL: (8371 + s, True)} for s in range(1, 41)}
    dbl: dict = dict(vary)
    dbl[(2, 20)] = {UL: (111.0, False), DL: (8371, True)}
    gap = {k: v for k, v in vary.items() if k[1] != 20}
    cases = [("pass: 12 distinct UL, constant DL", vary, True),
             ("fail: only 5 distinct rows (QP constant)", flat, False),
             ("fail: UL all zero", zero, False),
             ("fail: a double in one row", dbl, False),
             ("pass: a gap leaves fewer windows, all good", gap, True),
             ("fail: no window at all", {(2, s): vary[(2, s)] for s in range(1, 10)}, False)]
    bad = 0
    for name, rows, want in cases:
        got = judge(rows, gnbs)["pass"]
        bad += got != want
        print(("ok   " if got == want else "FAIL ") + name)
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--trace")
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--influx")
    src.add_argument("--ipc", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.trace or not (a.influx or a.ipc):
        ap.error("--trace and one of --influx/--ipc are required")
    gnbs = gnb_nodes(a.trace)
    rows = rows_from_influx(a.influx, gnbs) if a.influx else rows_from_ipc(a.trace, gnbs)
    v = judge(rows, gnbs)
    v["source"] = "influx" if a.influx else "ipc"
    json.dump(v, sys.stdout, indent=2)
    print()
    return 0 if v["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())

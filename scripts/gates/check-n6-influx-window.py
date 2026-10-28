#!/usr/bin/env python3
"""check-n6-influx-window.py: N6, certify the Influx rows of one R3′ trigger window at barrier T.

ns-3 is blocked at barrier T, so no row past T can exist (K2) and kpimon may still be writing rows <= T: the
check polls Influx (in the InfluxDB pod, the pod's own token expanded inside the pod; nothing secret reaches
argv, a file or a log) until every condition holds, at most the scenario's n6.deadlineS. Pass iff:
  c1 for every expected gNB cell n and every seq s of [T-15, T] (clipped at 0 with --clip): exactly one
     cellMetrics row (n, s), the counter column typed long, its value equal to the IPC sample's;
  c2 no cellMetrics or UeMetrics row of any node has seq > T;
  u1 each checked IMSI is listed by exactly one gNB node in the IPC samples at T;
  u2 the gNB UeMetrics rows (n, T, imsi) of each checked IMSI are exactly that node, once;
  h  the IMSI's last applied ledger line (if any) targets that node and has rxSeq <= T-1.
Checked IMSIs: --imsi I (a trigger), or --all (dry-run observe: every scenario IMSI). eNB rows are never read
for values. Outputs integers only: OUT_WINDOW {"T", "imsi", "clipped", "cells", "membership", "pass"} (the
predictor's sole input), OUT_VERDICT {"pass", "problems", "polls", "wallS"}.

  check-n6-influx-window.py SCENARIO T (--imsi I | --all) TRACE_DIR LEDGER OUT_WINDOW OUT_VERDICT [--clip]
        [--cell-csv F --ue-csv F]   (fixtures: read the Flux CSVs instead of querying Influx, one poll)
  check-n6-influx-window.py --self-test
"""
import csv
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

INFLUX_POD = "r4-influxdb-influxdb2-0"
IN_POD = 'export INFLUX_TOKEN="${INFLUX_TOKEN:-$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}"; exec influx query --org influxdata --raw "$1"'


def flux(measurement, fields):
    sel = " or ".join('r._field == "%s"' % f for f in fields)
    return ('from(bucket: "kpimon") |> range(start: 0) |> filter(fn: (r) => r._measurement == "%s" and (%s)) '
            '|> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value") '
            '|> drop(columns: ["_start", "_stop"])' % (measurement, sel))


def query(text):
    env = dict(os.environ)
    env.setdefault("KUBECONFIG", os.path.expanduser("~/.kube/config"))
    p = subprocess.run(["kubectl", "exec", "-n", "ricplt", INFLUX_POD, "--", "sh", "-c", IN_POD, "_", text],
                       capture_output=True, text=True, timeout=15, env=env, stdin=subprocess.DEVNULL)
    if p.returncode != 0 or p.stdout.startswith("error"):
        raise RuntimeError("influx query rc %d (stderr %d bytes, not kept)" % (p.returncode, len(p.stderr)))
    return p.stdout


def parse(text):
    """[(row dict col -> str|None, types dict col -> datatype)] from Flux --raw CSV (tables repeat annotations)."""
    out, types, hdr = [], [], None
    for line in text.splitlines():
        if not line.strip():
            continue
        rec = next(csv.reader(io.StringIO(line)))
        if rec[0] == "#datatype":
            types, hdr = rec, None
        elif rec[0].startswith("#"):
            continue
        elif hdr is None:
            hdr = rec
        elif len(rec) == len(hdr):
            out.append(({n: (v if v != "" else None) for n, v in zip(hdr, rec)}, dict(zip(hdr, types))))
    return out


def ipc(trace_dir, t, gnbs):
    """{node: {seq: sample}} for gNB samples with seq <= T (a torn last line is ignored)."""
    out = {}
    for n in gnbs:
        p = pathlib.Path(trace_dir) / ("e2-ipc-trace-%d.jsonl" % n)
        out[n] = {}
        if not p.exists():
            continue
        for line in p.read_text().splitlines():
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if m.get("type") == "sample" and m["seq"] <= t:
                out[n][m["seq"]] = m
    return out


def certify(sc, t, imsis, clip, trace_dir, ledger, cell_text, ue_text):
    gnbs = [int(n) for n in sc["n6"]["expectedCells"]]
    field = sc["counter"]["field"]
    first = t - sc["window"]["length"] + 1
    seqs = list(range(max(0, first) if clip else first, t + 1))
    problems, cells, member = [], {}, {}
    if seqs[0] < 0:
        problems.append("window starts at seq %d < 0 (use --clip only where pre-registered)" % seqs[0])
    samples = ipc(trace_dir, t, gnbs)
    rows = {}
    for r, ty in parse(cell_text):
        try:
            n, s = int(r["ns3.nodeId"]), int(r["ns3.seq"])
        except (KeyError, TypeError, ValueError):
            problems.append("a cellMetrics row without ns3.nodeId/ns3.seq")
            continue
        if s > t:
            problems.append("c2: cellMetrics row (%d, %d) past T" % (n, s))
        rows.setdefault((n, s), []).append((r.get(field), ty.get(field)))
    for n in gnbs:
        cells[str(n)] = {}
        for s in seqs:
            got = rows.get((n, s), [])
            smp = samples[n].get(s)
            want = ((smp or {}).get("cell") or {}).get("cuUp", {}).get(field)
            if len(got) != 1 or got[0][0] is None or got[0][1] != "long" or type(want) is not int or int(got[0][0]) != want:
                problems.append("c1: cell (%d, %d): influx %r, ipc %r" % (n, s, got, want))
                continue
            cells[str(n)][str(s)] = want
    ue_rows = {}
    for r, _ in parse(ue_text):
        try:
            n, s, i = int(r["ns3.nodeId"]), int(r["ns3.seq"]), int(r["ns3.imsi"])
        except (KeyError, TypeError, ValueError):
            problems.append("a UeMetrics row without ns3.nodeId/ns3.seq/ns3.imsi")
            continue
        if s > t:
            problems.append("c2: UeMetrics row (%d, %d, %d) past T" % (n, s, i))
        elif s == t and n in gnbs:
            ue_rows.setdefault(i, []).append(n)
    lines = [json.loads(l) for l in open(ledger) if l.strip()][1:] if os.path.exists(ledger) else []
    for i in imsis:
        ipc_nodes = [n for n in gnbs if any(u.get("imsi") == i for u in (samples[n].get(t) or {}).get("ues") or [])]
        if len(ipc_nodes) != 1:
            problems.append("u1: imsi %d listed by gNB nodes %r in IPC at %d" % (i, ipc_nodes, t))
            continue
        if sorted(ue_rows.get(i, [])) != ipc_nodes:
            problems.append("u2: imsi %d UeMetrics rows at %d on nodes %r, IPC %r" % (i, t, sorted(ue_rows.get(i, [])), ipc_nodes))
            continue
        ap = [x for x in lines if x.get("imsi") == i and x.get("outcome") == "applied"]
        if ap and (ap[-1]["targetCell"] != ipc_nodes[0] or ap[-1]["rxSeq"] > t - 1):
            problems.append("h: imsi %d last applied line %r, serving %d at %d" % (i, ap[-1], ipc_nodes[0], t))
            continue
        member[str(i)] = ipc_nodes[0]
    return {"T": t, "imsi": imsis[0] if len(imsis) == 1 else None, "clipped": clip, "cells": cells,
            "membership": member, "pass": not problems}, problems


def main(av):
    sc = json.load(open(av[0]))
    t = int(av[1])
    imsis = list(sc["imsis"]) if av[2] == "--all" else [int(av[3])]
    rest = av[3:] if av[2] == "--all" else av[4:]
    trace_dir, ledger, out_win, out_ver = rest[:4]
    clip = "--clip" in rest
    fixture = "--cell-csv" in rest
    t0, polls, deadline = time.time(), 0, time.time() + float(sc["n6"]["deadlineS"])
    while True:
        polls += 1
        try:
            if fixture:
                cell = open(rest[rest.index("--cell-csv") + 1]).read()
                ue = open(rest[rest.index("--ue-csv") + 1]).read()
            else:
                cell = query(flux("cellMetrics", ["ns3.nodeId", "ns3.seq", sc["counter"]["field"]]))
                ue = query(flux(sc["counter"]["ueMeasurement"], ["ns3.nodeId", "ns3.seq", "ns3.imsi"]))
            win, problems = certify(sc, t, imsis, clip, trace_dir, ledger, cell, ue)
        except (RuntimeError, subprocess.TimeoutExpired) as ex:
            win, problems = None, ["query: %s" % ex]
        if not problems or fixture or time.time() + float(sc["n6"]["pollS"]) > deadline:
            break
        time.sleep(float(sc["n6"]["pollS"]))
    if win is not None:
        json.dump(win, open(out_win, "w"), sort_keys=True)
    json.dump({"T": t, "pass": not problems, "problems": problems[:20], "nProblems": len(problems), "polls": polls,
               "wallS": round(time.time() - t0, 3)}, open(out_ver, "w"), sort_keys=True)
    print("N6 seq %d: %s after %d poll(s)%s" % (t, "PASS" if not problems else "FAIL", polls,
                                               "" if not problems else ": " + "; ".join(problems[:3])))
    return 0 if not problems else 1


def _csv(cols, types, rows):
    lines = ["#datatype,string,long," + ",".join(types), "#group,false,false" + ",false" * len(cols),
             "#default,_result,," + "," * (len(cols) - 1), ",result,table," + ",".join(cols)]
    lines += [",,0," + ",".join("" if v is None else str(v) for v in r) for r in rows]
    return "\n".join(lines) + "\n"


def self_test():
    import importlib.util
    here = pathlib.Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("n6fx", here / "n6-fixtures.py")
    fx = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fx)
    sc = json.load(open(here / "r3p-scenario.json"))
    bad = 0
    for name, want, kw in fx.CASES:
        with tempfile.TemporaryDirectory() as d:
            args = fx.build(pathlib.Path(d), _csv, **kw)
            win, problems = certify(sc, args["T"], args["imsis"], False, args["trace"], args["ledger"],
                                    args["cell"], args["ue"])
        got = not problems
        bad += got != want
        print(("ok   " if got == want else "FAIL ") + name + ("" if got == want else ": %r" % problems[:2]))
    print("n6 self-test: %s" % ("ok" if not bad else "%d failure(s)" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    if len(sys.argv) < 8:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

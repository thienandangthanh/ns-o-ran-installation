#!/usr/bin/env python3
"""influx-ue-ueid-every-node.py: every Influx UeMetrics row's ueId resolves to its ns3.imsi, on every node of a run.

  influx-ue-ueid-every-node.py --influx-ue UE.csv --node-ips node-ips.json --ue-context-dir TRACE_DIR --out FILE
  influx-ue-ueid-every-node.py --self-test

UE.csv is the pivoted UeMetrics Flux export of the run window (agents-ns3-run.sh influx_export: one row per point,
one column per field, the group-key tag columns kept). The node set is the keys of node-ips.json; a node's kind
(gnb or enb) comes from its e2-ipc-trace-<n>.jsonl hello in TRACE_DIR. Passes iff:
  - the CSV has a ueId column and the run's UE context loads without problems (ue-context-map.py UeContextMap);
  - every UeMetrics row of node n carries a ueId of n's kind's form (enGnbUeId:<x2>@00F110-<%05X> on a gNB node,
    enbUeId:<mmeUeS1apId>@<x2> on the eNB) that resolves through ctx(n, ns3.seq) to that row's ns3.imsi value
    (R(n, {ns3.seq}, ueId), the very resolver of influx-vs-trace.py `ueid_mismatches`); a row without ueId,
    ns3.seq or ns3.imsi, or whose ueId is malformed, unresolved or names another IMSI, fails;
  - every row's ns3.nodeId is a node of node-ips.json (a row of no listed node, or without a nodeId, fails);
  - every node of node-ips.json has at least one UeMetrics row.
"""
import argparse
import importlib.util
import json
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    assert spec is not None and spec.loader is not None, filename
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


IVT = _load("influx_vs_trace", "influx-vs-trace.py")
UCM = IVT._ue_context_map()


def _num(v):
    try:
        return int(v) if v is not None else None
    except ValueError:
        return None


def check(ue_csv, node_ips, trace_dir):
    nodes = sorted(int(k) for k in json.load(open(node_ips)))
    cm = UCM.UeContextMap(trace_dir)
    problems = ["UE context: " + p for p in cm.problems]
    has_col, foreign, foreign_ex = False, 0, []
    for r in IVT.read_rows(ue_csv):
        has_col = has_col or "ueId" in r
        if _num(r.get("ns3.nodeId")) not in nodes:
            foreign += 1
            if len(foreign_ex) < 5:
                foreign_ex.append({"nodeId": r.get("ns3.nodeId"), "seq": r.get("ns3.seq"), "ueId": r.get("ueId")})
    if not has_col:
        problems.append("the UE CSV has no ueId column")
    if foreign:
        problems.append("%d UeMetrics row(s) of no node in %s: %s" % (foreign, nodes, foreign_ex))
    per = {}
    for n in nodes:
        rows, bad, _, examples = IVT.ueid_mismatches(ue_csv, n, cm)
        per[str(n)] = {"kind": cm.kinds.get(n), "ueRows": rows, "ueidMismatch": bad, "mismatchExamples": examples}
        if rows == 0:
            problems.append("node %d has no UeMetrics row" % n)
        if bad:
            problems.append("node %d: %d of %d UeMetrics row(s) whose ueId is missing, malformed, unresolved or names "
                            "another IMSI than ns3.imsi, e.g. %s" % (n, bad, rows, examples[:2]))
    return {"nodes": per, "ueCsvHasUeIdColumn": has_col, "rowsOfNoListedNode": foreign,
            "problems": problems[:40], "problemCount": len(problems), "pass": not problems}


def _csv(path, rows):
    """A pivoted Flux --raw CSV of UeMetrics rows (dicts of ueId, ns3.imsi, ns3.nodeId, ns3.seq; None = empty)."""
    cols = ["ueId", "ns3.imsi", "ns3.nodeId", "ns3.seq"]
    if rows and "ueId" not in rows[0]:
        cols = cols[1:]
    lines = ["#datatype,string,long,dateTime:RFC3339,string," + ",".join("string" if c == "ueId" else "long" for c in cols[1:]),
             ",result,table,_time,_measurement," + ",".join(cols)]
    for i, r in enumerate(rows):
        lines.append(",,0,2026-01-01T00:00:%02d.000Z,UeMetrics,%s" % (i % 60, ",".join(
            "" if r.get(c) is None else str(r[c]) for c in cols)))
    pathlib.Path(path).write_text("\n".join(lines) + "\n")


def self_test():
    fails = []
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        # eNB node 1 and gNB node 2; IMSIs 1, 2 with MN RNTIs 3, 4; IMSI 2 joins gNB 2 at seq 2 (seqs 0..3).
        d = UCM._fixture(t / "run")
        (t / "node-ips.json").write_text(json.dumps({"1": ["172.17.0.2"], "2": ["172.17.0.3"]}))
        row = lambda n, s, i, u: {"ueId": u, "ns3.imsi": i, "ns3.nodeId": n, "ns3.seq": s}
        enb = {1: "enbUeId:1@3", 2: "enbUeId:2@4"}
        gnb = {1: "enGnbUeId:3@00F110-00001", 2: "enGnbUeId:4@00F110-00001"}
        good = ([row(1, s, i, enb[i]) for s in range(4) for i in (1, 2)] +
                [row(2, s, 1, gnb[1]) for s in range(4)] + [row(2, s, 2, gnb[2]) for s in (2, 3)])

        def case(name, want, rows, node_ips=None):
            _csv(t / "ue.csv", rows)
            r = check(t / "ue.csv", node_ips or t / "node-ips.json", d)
            if r["pass"] != want:
                fails.append("%s: pass %s, want %s %r" % (name, r["pass"], want, r["problems"][:2]))

        def edit(i, **kw):
            rows = [dict(r) for r in good]
            rows[i].update({k.replace("_", "."): v for k, v in kw.items()})
            return rows
        case("every row resolves to its IMSI on both nodes", True, good)
        case("a row without ueId", False, edit(9, ueId=None))
        case("a gNB-form ueId on the eNB node", False, edit(0, ueId=gnb[1]))
        case("an eNB-form ueId on a gNB node", False, edit(8, ueId="enbUeId:1@3"))
        case("a ueId naming another IMSI than ns3.imsi", False, edit(0, ueId=enb[2]))
        case("a ueId absent from ctx(n, s) at its seq", False, good + [row(2, 1, 2, gnb[2])])
        case("a malformed ueId", False, edit(8, ueId="enGnbUeId:3@00f110-00001"))
        case("a row without ns3.imsi", False, edit(1, ns3_imsi=None))
        case("a row without ns3.seq", False, edit(1, ns3_seq=None))
        case("a node of node-ips.json without a UE row", False, [r for r in good if r["ns3.nodeId"] != 2])
        case("a row of a node not in node-ips.json", False, good + [row(3, 0, 1, gnb[1])])
        case("a row without ns3.nodeId", False, good + [row(None, 0, 1, gnb[1])])
        case("a UE CSV without the ueId column", False, [{k: v for k, v in r.items() if k != "ueId"} for r in good])
    for f in fails:
        print("FAIL " + f)
    print("influx-ue-ueid-every-node self-test: " + ("ok" if not fails else "%d failure(s)" % len(fails)))
    return 1 if fails else 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("--influx-ue", required=True, help="pivoted UeMetrics Flux CSV of the run window")
    ap.add_argument("--node-ips", required=True, help="the run's node-ips.json (its keys are the node set)")
    ap.add_argument("--ue-context-dir", required=True, help="the run's trace dir (e2-ue-context-*.jsonl, e2-ipc-trace-*.jsonl)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    r = check(a.influx_ue, a.node_ips, a.ue_context_dir)
    with open(a.out, "w") as f:
        json.dump(r, f, indent=1, sort_keys=True)
        f.write("\n")
    print(json.dumps({"nodes": {n: {k: v[k] for k in ("kind", "ueRows", "ueidMismatch")} for n, v in r["nodes"].items()},
                      "rowsOfNoListedNode": r["rowsOfNoListedNode"], "pass": r["pass"]}, sort_keys=True))
    for p in r["problems"][:20]:
        print("problem: " + p)
    return 0 if r["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())

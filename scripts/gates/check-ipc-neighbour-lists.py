#!/usr/bin/env python3
"""Every UE tick of a 2-gNB rung reports exactly min(8, eligible) L3 neighbours (ledger row 159).

ns-3's gNB builds each UE's L3 report from its per-UE SINR map. Before the neighbour-loop fix
(contract Amendment 4), a reverse loop that stopped at `--begin()` (undefined behaviour) dropped
the only neighbour of a 2-entry map whose serving cell was the higher cellId and the strongest
(r2 live1 at cp2: node 3 reported 0 neighbours in 82 of 178 UE ticks).

Input: a rung evidence dir; every `runs/*/trace/e2-ipc-trace-<node>.jsonl` is read. Node 1 is the
LTE eNB (it reports no neighbour list) and every other trace is one gNB, whose cell id is its node
id. In the 2-gNB rungs (r2, r3p) each gNB's SINR map holds both NR cells at every tick (594 of 594
UE blocks in r2 live1), so eligible = G - 1 with G the run's gNB count. Pass iff, in every run,
every UE record at a gNB lists exactly min(8, G - 1) neighbours, distinct, none the serving cell,
each one of the run's gNB cells, and every gNB contributes at least one UE record.

Usage: check-ipc-neighbour-lists.py <evidence-dir> | --self-test
"""
import glob
import json
import os
import re
import sys
import tempfile

MAX_NEIGH = 8
ENB_NODE = 1


def check_run(trace_files):
    """Return (problems, ticks) for one run's IPC traces."""
    problems, ticks = [], {}
    nodes = {}
    for f in trace_files:
        m = re.search(r"e2-ipc-trace-(\d+)\.jsonl$", f)
        if m:
            nodes[int(m.group(1))] = f
    gnbs = sorted(n for n in nodes if n != ENB_NODE)
    if not gnbs:
        return ["no gNB trace"], ticks
    want = min(MAX_NEIGH, len(gnbs) - 1)
    for node in gnbs:
        ticks[node] = 0
        for line in open(nodes[node]):
            rec = json.loads(line)
            if rec.get("type") != "sample":
                continue
            for ue in rec.get("ues", []):
                l3 = ue.get("cuCp", {}).get("l3")
                if l3 is None:
                    continue
                ticks[node] += 1
                neigh = [n.get("cellId") for n in l3.get("neigh", [])]
                serving = l3.get("servCellId")
                where = "node %d seq %s imsi %s" % (node, rec.get("seq"), ue.get("imsi"))
                if len(neigh) != want:
                    problems.append("%s: %d neighbours, want %d" % (where, len(neigh), want))
                if len(set(neigh)) != len(neigh):
                    problems.append("%s: repeated neighbour %s" % (where, neigh))
                if serving in neigh:
                    problems.append("%s: serving cell %s listed as a neighbour" % (where, serving))
                foreign = [c for c in neigh if c not in gnbs]
                if foreign:
                    problems.append("%s: neighbours %s are not gNB cells of the run" % (where, foreign))
        if ticks[node] == 0:
            problems.append("node %d: no UE record" % node)
    return problems, ticks


def check_dir(evidence_dir):
    runs = {}
    for f in glob.glob(os.path.join(evidence_dir, "runs", "*", "trace", "e2-ipc-trace-*.jsonl")):
        runs.setdefault(f.split(os.sep)[-3], []).append(f)
    if not runs:
        return ["no IPC trace under runs/*/trace"], {}
    problems, summary = [], {}
    for run in sorted(runs):
        p, ticks = check_run(runs[run])
        summary[run] = {str(k): v for k, v in ticks.items()}
        problems += ["%s: %s" % (run, x) for x in p]
    return problems, summary


def _write_run(root, run, node_ues):
    d = os.path.join(root, "runs", run, "trace")
    os.makedirs(d)
    for node, ues in node_ues.items():
        with open(os.path.join(d, "e2-ipc-trace-%d.jsonl" % node), "w") as f:
            f.write(json.dumps({"type": "hello", "nodeId": node}) + "\n")
            f.write(json.dumps({"type": "sample", "nodeId": node, "seq": 1, "ues": ues}) + "\n")


def _ue(imsi, serving, neigh):
    return {"imsi": imsi, "cuCp": {"l3": {"servCellId": serving, "neigh": [{"cellId": c} for c in neigh]}}}


def self_test():
    cases = [
        ("good 2-gNB run", {1: [{"imsi": 1, "cuCp": {"l3": {"servCellId": 1}}}],
                            2: [_ue(1, 2, [3])], 3: [_ue(2, 3, [2])]}, True),
        ("0-neighbour tick (the UB)", {2: [_ue(1, 2, [3])], 3: [_ue(2, 3, [])]}, False),
        ("serving cell as neighbour", {2: [_ue(1, 2, [2])], 3: [_ue(2, 3, [2])]}, False),
        ("foreign neighbour", {2: [_ue(1, 2, [7])], 3: [_ue(2, 3, [2])]}, False),
        ("two neighbours with two gNBs", {2: [_ue(1, 2, [3, 3])], 3: [_ue(2, 3, [2])]}, False),
        ("a gNB with no UE record", {2: [_ue(1, 2, [3])], 3: []}, False),
    ]
    bad = 0
    for name, node_ues, want_pass in cases:
        with tempfile.TemporaryDirectory() as root:
            _write_run(root, "live1", node_ues)
            problems, _ = check_dir(root)
            if (not problems) != want_pass:
                bad += 1
                print("self-test FAIL: %s: problems %s" % (name, problems))
    print("self-test %s (%d cases)" % ("FAIL" if bad else "ok", len(cases)))
    return 1 if bad else 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    if len(sys.argv) != 2:
        print("usage: check-ipc-neighbour-lists.py <evidence-dir> | --self-test")
        return 2
    problems, summary = check_dir(sys.argv[1])
    print(json.dumps({"uePerGnbTicks": summary, "problems": problems[:20], "problemCount": len(problems)}))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

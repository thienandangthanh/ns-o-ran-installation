#!/usr/bin/env python3
"""compare-free-run.py: the P1 V1 free-run equality rule
(plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/p1-free-run-reference/v1-rule.md).

Each run directory holds trace/e2-ipc-trace-<node>.jsonl and ns3run/*.txt.
Every candidate is compared with the reference run:
  1. IPC samples per node equal (scripts/probes/compare-ns3-ipc-sample-digests.py),
     plus an explicit check of the node set and of samples_per_run;
  2. the set of ns3run/*.txt names equal and every sha256 equal, except
     DlE2RlcStatsLte.txt compared without its columns 5-6 (contract C1);
     stdout.txt and stderr.txt are process logs and are not compared;
  3. no e2-control-ledger.jsonl in any run.
Prints one JSON report; exit 0 only if every candidate passes.

usage: compare-free-run.py REFLABEL=DIR LABEL=DIR [LABEL=DIR ...]
"""
import hashlib
import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
LOGS = {"stdout.txt", "stderr.txt"}
COLUMN_EXCLUSIONS = {"DlE2RlcStatsLte.txt": {5, 6}}  # 1-based, contract C1


def load_ipc_module():
    path = HERE.parent / "probes" / "compare-ns3-ipc-sample-digests.py"
    spec = importlib.util.spec_from_file_location("ipc_digests", path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def trace_digests(run_dir):
    out = {}
    for p in sorted((pathlib.Path(run_dir) / "ns3run").glob("*.txt")):
        if p.name in LOGS:
            continue
        drop = COLUMN_EXCLUSIONS.get(p.name)
        if drop:
            h = hashlib.sha256()
            for line in p.read_text().splitlines():
                cols = [c for i, c in enumerate(line.split(), 1) if i not in drop]
                h.update((" ".join(cols) + "\n").encode())
            out[p.name] = h.hexdigest()
        else:
            out[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def main(args):
    if len(args) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    ipc = load_ipc_module()
    runs = [a.partition("=") for a in args]
    ref_label, _, ref_dir = runs[0]
    ref_samples = ipc.load_samples(ref_dir)
    ref_traces = trace_digests(ref_dir)
    report = {"reference": ref_label, "rule": "p1-free-run-reference/v1-rule.md", "candidates": {}}
    ok_all = True
    for label, _, d in runs[1:]:
        samples = ipc.load_samples(d)
        traces = trace_digests(d)
        nodes_equal = set(samples) == set(ref_samples)
        counts = {str(n): [len(ref_samples.get(n, {})), len(samples.get(n, {}))]
                  for n in sorted(set(samples) | set(ref_samples))}
        counts_equal = all(a == b for a, b in counts.values())
        mismatched = {str(n): [s for s in sorted(set(ref_samples[n]) & set(samples[n]))
                               if ref_samples[n][s] != samples[n][s]][:5]
                      for n in sorted(set(samples) & set(ref_samples))}
        samples_equal = all(not m for m in mismatched.values())
        names_equal = set(traces) == set(ref_traces)
        differing = sorted(n for n in set(traces) & set(ref_traces) if traces[n] != ref_traces[n])
        ledgers = [str(p) for p in pathlib.Path(d).rglob("e2-control-ledger.jsonl")]
        ok = nodes_equal and counts_equal and samples_equal and names_equal and not differing and not ledgers
        ok_all &= ok
        report["candidates"][label] = {
            "pass": ok, "nodes_equal": nodes_equal, "samples_per_run_ref_vs_run": counts,
            "samples_equal": samples_equal, "first_mismatched_seqs": mismatched,
            "trace_names_equal": names_equal,
            "trace_names_only_in_ref": sorted(set(ref_traces) - set(traces)),
            "trace_names_only_in_run": sorted(set(traces) - set(ref_traces)),
            "traces_compared": len(set(traces) & set(ref_traces)), "traces_differing": differing,
            "ledger_files": ledgers}
    report["reference_ledger_files"] = [str(p) for p in pathlib.Path(ref_dir).rglob("e2-control-ledger.jsonl")]
    ok_all &= not report["reference_ledger_files"]
    report["all_pass"] = ok_all
    json.dump(report, sys.stdout, indent=2)
    print()
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

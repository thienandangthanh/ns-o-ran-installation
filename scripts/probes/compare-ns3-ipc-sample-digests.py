#!/usr/bin/env python3
"""Offline probe: are ns-3 IPC sample lines identical across runs?

For each run directory given, finds e2-ipc-trace-<node>.jsonl files (recursively),
keeps only `sample` lines, drops the wall-clock / delivery fields that are not
simulation output (`ipcDropped`), and compares per node the samples common to all
runs by `seq`. Prints one JSON report on stdout.

Usage: compare-ns3-ipc-sample-digests.py LABEL=DIR [LABEL=DIR ...]
"""
import hashlib
import json
import pathlib
import sys

DROP_KEYS = {"ipcDropped"}


def load_samples(run_dir, transform=None):
    """Return {nodeId: {seq: canonical_line}} for every trace under run_dir.

    transform(msg, kind), if given, may check and edit each sample before it is
    canonicalized; kind is the node kind from the file's hello line (None if absent).
    """
    nodes = {}
    for path in sorted(pathlib.Path(run_dir).rglob("e2-ipc-trace-*.jsonl")):
        kind = None
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            msg = json.loads(line)
            if msg.get("type") == "hello":
                kind = msg.get("kind")
            if msg.get("type") != "sample":
                continue
            for k in DROP_KEYS:
                msg.pop(k, None)
            if transform is not None:
                transform(msg, kind)
            canon = json.dumps(msg, sort_keys=True, separators=(",", ":"))
            nodes.setdefault(msg["nodeId"], {})[msg["seq"]] = canon
    return nodes


def main(args):
    runs = {}
    for arg in args:
        label, _, d = arg.partition("=")
        runs[label] = load_samples(d)
    labels = list(runs)
    report = {"runs": labels, "dropped_keys": sorted(DROP_KEYS), "nodes": {}}
    all_nodes = sorted(set().union(*(r.keys() for r in runs.values())))
    for node in all_nodes:
        per_run = [runs[l].get(node, {}) for l in labels]
        common = sorted(set.intersection(*(set(p) for p in per_run)))
        mismatched = [s for s in common if len({p[s] for p in per_run}) != 1]
        digest = hashlib.sha256("\n".join(per_run[0][s] for s in common).encode()).hexdigest()
        report["nodes"][str(node)] = {
            "samples_per_run": {l: len(p) for l, p in zip(labels, per_run)},
            "common_seqs": len(common),
            "mismatched_seqs": len(mismatched),
            "first_mismatches": mismatched[:5],
            "common_sha256": digest,
        }
    report["all_equal"] = all(n["mismatched_seqs"] == 0 for n in report["nodes"].values())
    json.dump(report, sys.stdout, indent=2)
    print()
    return 0 if report["all_equal"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

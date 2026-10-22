#!/usr/bin/env python3
"""digest-run.py: the C1 digest set of one run, and the comparison of runs.

A run directory holds trace/ (e2-ipc-trace-<node>.jsonl, e2-control-ledger.jsonl)
and ns3run/ (ns-3 trace text files). Components:
  ledger  the control ledger lines (no wall clock is ever written there; a
          missing ledger is an empty one);
  ipc     per node, the IPC `sample` lines without `hello` and with
          `ipcDropped` dropped (it must be 0 and is asserted separately);
  traces  every ns3run/*.txt except the stdout/stderr logs, with
          DlE2RlcStatsLte.txt columns 5-6 removed (contract C1);
  extra   live-only components from the decoded wire, written by the rung gates
          as extra/rc-multiset.json (per-step RC multiset), extra/kpm-headers.json
          and extra/collet-start-time.json; when `extra` is a compared component,
          a run without all three fails the comparison (two empty sets never
          compare equal).

  digest-run.py RUN                         -> JSON digests of RUN
  digest-run.py --compare [--components ledger,ipc,traces[,extra]] A=RUN B=RUN ...
                                            -> per-run equality with the first; exit 0 if all equal
"""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FREE = _module("compare_free_run", HERE / "compare-free-run.py")
EXTRA_EXPECTED = ("rc-multiset", "kpm-headers", "collet-start-time")
IPC = _module("ipc_digests", HERE.parent / "probes" / "compare-ns3-ipc-sample-digests.py")


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def digests(run):
    run = pathlib.Path(run)
    ledger = run / "trace" / "e2-control-ledger.jsonl"
    samples = IPC.load_samples(run / "trace")
    ipc_dropped = 0
    for p in sorted((run / "trace").glob("e2-ipc-trace-*.jsonl")):
        for line in p.read_text().splitlines():
            if '"type":"sample"' in line:
                ipc_dropped = max(ipc_dropped, json.loads(line).get("ipcDropped", 0))
    out = {
        "ledger": sha(ledger.read_text()) if ledger.exists() else sha(""),
        "ledgerLines": max(0, len(ledger.read_text().splitlines()) - 1) if ledger.exists() else 0,
        "ipc": {str(n): sha("\n".join(s[k] for k in sorted(s))) for n, s in sorted(samples.items())},
        "ipcSamples": {str(n): len(s) for n, s in sorted(samples.items())},
        "ipcDroppedMax": ipc_dropped,
        "traces": FREE.trace_digests(run),
        "extra": {p.stem: sha(p.read_text()) for p in sorted((run / "extra").glob("*.json"))},
    }
    out["overall"] = sha(json.dumps({k: out[k] for k in ("ledger", "ipc", "traces")}, sort_keys=True))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--compare", action="store_true")
    ap.add_argument("--components", default="ledger,ipc,traces")
    ap.add_argument("runs", nargs="+")
    a = ap.parse_args()
    if not a.compare:
        json.dump(digests(a.runs[0]), sys.stdout, indent=2)
        print()
        return 0
    comps = a.components.split(",")
    labelled = [r.partition("=") for r in a.runs]
    d = {label: digests(path) for label, _, path in labelled}
    ref = labelled[0][0]
    report = {"reference": ref, "components": comps, "runs": {}}
    ok = True
    if "extra" in comps:
        missing = {label: [n for n in EXTRA_EXPECTED if n not in d[label]["extra"]] for label in d}
        missing = {k: v for k, v in missing.items() if v}
        if missing:
            report["extraMissing"] = missing
            ok = False
    for label, _, _ in labelled[1:]:
        diff = [c for c in comps if d[label][c] != d[ref][c]]
        detail = {}
        for c in diff:
            if isinstance(d[ref][c], dict):
                keys = set(d[ref][c]) | set(d[label][c])
                detail[c] = sorted(k for k in keys if d[ref][c].get(k) != d[label][c].get(k))
        report["runs"][label] = {"equal": not diff, "differing": diff, "detail": detail,
                                 "ipcDroppedMax": d[label]["ipcDroppedMax"]}
        ok &= not diff
    report["ipcDroppedMaxAll"] = max(v["ipcDroppedMax"] for v in d.values())
    report["overall"] = {label: d[label]["overall"] for label in d}
    report["all_equal"] = ok
    json.dump(report, sys.stdout, indent=2)
    print()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

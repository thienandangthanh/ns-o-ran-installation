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

  --n4-ul-off-drop LABEL=absent|present[,...] (default off): the UL-off regression of the two
  gNB CU-UP PDCP SDU volume keys. A `present` run must carry both keys as JSON ints in every
  gNB sample's cell.cuUp, with UL == 0 everywhere and DL > 0 in at least one sample of every
  gNB node that ever lists a UE, and no eNB sample, other cell section or UE section may carry
  either key; then exactly those two keys are deleted before digesting. An `absent` run must
  carry neither key anywhere. Any failed precondition exits non-zero whatever the digests say.
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


N4_KEYS = ("DRB.PdcpSduVolumeUL", "DRB.PdcpSduVolumeDL")


class N4Drop:
    """Checks and strips the two N4 keys of one run's samples (see --n4-ul-off-drop)."""

    def __init__(self, mode):
        assert mode in ("absent", "present"), mode
        self.mode = mode
        self.r = {"mode": mode, "samplesChecked": 0, "missing": 0, "ulNonZero": 0, "nonInt": 0,
                  "dlPositiveByNode": {}, "unexpectedCarriers": 0}

    def __call__(self, msg, kind):
        self.r["samplesChecked"] += 1
        cell = msg.get("cell") or {}
        for name, sec in cell.items():
            if name != "cuUp" and isinstance(sec, dict) and any(k in sec for k in N4_KEYS):
                self.r["unexpectedCarriers"] += 1
        for ue in msg.get("ues") or []:
            for sec in ue.values():
                if isinstance(sec, dict) and any(k in sec for k in N4_KEYS):
                    self.r["unexpectedCarriers"] += 1
        cu = cell.get("cuUp")
        carried = isinstance(cu, dict) and any(k in cu for k in N4_KEYS)
        if self.mode == "absent" or kind != "gnb":
            self.r["unexpectedCarriers"] += carried
            return
        node = str(msg["nodeId"])
        if msg.get("ues"):
            self.r["dlPositiveByNode"].setdefault(node, False)
        if not isinstance(cu, dict) or any(k not in cu for k in N4_KEYS):
            self.r["missing"] += 1
            return
        ul, dl = (cu[k] for k in N4_KEYS)
        if any(type(v) is not int for v in (ul, dl)):
            self.r["nonInt"] += 1
            return
        self.r["ulNonZero"] += ul != 0
        if dl > 0 and node in self.r["dlPositiveByNode"]:
            self.r["dlPositiveByNode"][node] = True
        for k in N4_KEYS:
            del cu[k]

    def ok(self):
        r = self.r
        return (r["samplesChecked"] > 0 and r["missing"] == 0 and r["ulNonZero"] == 0 and r["nonInt"] == 0
                and r["unexpectedCarriers"] == 0
                and (self.mode == "absent" or (r["dlPositiveByNode"] and all(r["dlPositiveByNode"].values()))))


def digests(run, n4=None):
    run = pathlib.Path(run)
    ledger = run / "trace" / "e2-control-ledger.jsonl"
    samples = IPC.load_samples(run / "trace", n4)
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
        # only the named live components: the extractor's diagnostics (rc-requests, rc-answers: RIC request IDs
        # and wall times) sit in the same directory and must never be digested
        "extra": {n: sha((run / "extra" / (n + ".json")).read_text()) for n in EXTRA_EXPECTED
                  if (run / "extra" / (n + ".json")).exists()},
    }
    out["overall"] = sha(json.dumps({k: out[k] for k in ("ledger", "ipc", "traces")}, sort_keys=True))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--compare", action="store_true")
    ap.add_argument("--components", default="ledger,ipc,traces")
    ap.add_argument("--n4-ul-off-drop", default="", metavar="LABEL=absent|present[,...]")
    ap.add_argument("runs", nargs="+")
    a = ap.parse_args()
    if not a.compare:
        json.dump(digests(a.runs[0]), sys.stdout, indent=2)
        print()
        return 0
    comps = a.components.split(",")
    labelled = [r.partition("=") for r in a.runs]
    n4 = {label: N4Drop(mode) for label, _, mode in
          (x.partition("=") for x in a.n4_ul_off_drop.split(",") if x)}
    unknown = set(n4) - {label for label, _, _ in labelled}
    if unknown:
        ap.error("--n4-ul-off-drop names unknown runs: " + ",".join(sorted(unknown)))
    d = {label: digests(path, n4.get(label)) for label, _, path in labelled}
    ref = labelled[0][0]
    report = {"reference": ref, "components": comps, "runs": {}}
    ok = True
    if n4:
        report["n4Drop"] = {label: dict(c.r, ok=c.ok()) for label, c in n4.items()}
        ok = all(c.ok() for c in n4.values())
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

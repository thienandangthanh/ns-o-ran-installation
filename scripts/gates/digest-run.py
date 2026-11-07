#!/usr/bin/env python3
"""digest-run.py: the C1 digest set of one run, and the comparison of runs.

A run directory holds trace/ (e2-ipc-trace-<node>.jsonl, e2-control-ledger.jsonl)
and ns3run/ (ns-3 trace text files). Components:
  ledger  the control ledger lines (no wall clock is ever written there; a
          missing ledger is an empty one);
  ipc     per node, the IPC `sample` lines without `hello` and with
          `ipcDropped` dropped (it must be 0 and is asserted separately);
          ns-3 writes its `ueContext` lines to e2-ue-context-<node>.jsonl only,
          so ipcTraceUeContextLines (the `ueContext` lines found in the run's
          e2-ipc-trace-*.jsonl, which the sample digest would not see) must be
          0: any other count makes every mode exit 3;
  traces  every ns3run/*.txt except the stdout/stderr logs, with
          DlE2RlcStatsLte.txt columns 5-6 removed (contract C1);
  extra   live-only components from the decoded wire, written by the rung gates
          as extra/rc-multiset.json (per-step RC multiset), extra/kpm-headers.json
          and extra/collet-start-time.json; when `extra` is a compared component,
          a run without all three fails the comparison (two empty sets never
          compare equal).

  digest-run.py RUN                         -> JSON digests of RUN
  digest-run.py --compare [--components ledger,ipc,traces[,extra]] A=RUN B=RUN ...
                                            -> per-run equality with the first; exit 0 if all equal,
                                               1 if a component differs, 3 if a run's ipc trace holds a
                                               ueContext line (never 1, so a "must differ" caller cannot pass)

  digest-run.py --self-test                 -> the ueContext rule on two synthetic runs

  --n4-ul-off-drop LABEL=absent|present[,...] (default off): the UL-off regression of the four
  gNB CU-UP PDCP SDU volume keys (DRB.PdcpSduVolumeUL, DL, X2UL, X2DL). A `present` run must
  carry all four keys as JSON ints in every gNB sample's cell.cuUp, with UL, DL and X2UL == 0
  everywhere and X2DL > 0 in at least one sample of every gNB node that ever lists a UE, and no
  eNB sample, other cell section or UE section may carry any of them; then exactly those four
  keys are deleted before digesting. An `absent` run must carry none of them anywhere. Any
  failed precondition exits non-zero whatever the digests say.
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


N4_ZERO_KEYS = ("DRB.PdcpSduVolumeUL", "DRB.PdcpSduVolumeDL", "DRB.PdcpSduVolumeX2UL")  # 0 with UL traffic off
N4_X2DL = "DRB.PdcpSduVolumeX2DL"
N4_KEYS = N4_ZERO_KEYS + (N4_X2DL,)


class N4Drop:
    """Checks and strips the four N4 keys of one run's samples (see --n4-ul-off-drop)."""

    def __init__(self, mode):
        assert mode in ("absent", "present"), mode
        self.mode = mode
        self.r = {"mode": mode, "samplesChecked": 0, "missing": 0, "nonZero": {k: 0 for k in N4_ZERO_KEYS},
                  "nonInt": 0, "x2dlPositiveByNode": {}, "unexpectedCarriers": 0}

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
            self.r["x2dlPositiveByNode"].setdefault(node, False)
        if not isinstance(cu, dict) or any(k not in cu for k in N4_KEYS):
            self.r["missing"] += 1
            return
        if any(type(cu[k]) is not int for k in N4_KEYS):
            self.r["nonInt"] += 1
            return
        for k in N4_ZERO_KEYS:
            self.r["nonZero"][k] += cu[k] != 0
        if cu[N4_X2DL] > 0 and node in self.r["x2dlPositiveByNode"]:
            self.r["x2dlPositiveByNode"][node] = True
        for k in N4_KEYS:
            del cu[k]

    def ok(self):
        r = self.r
        return (r["samplesChecked"] > 0 and r["missing"] == 0 and not any(r["nonZero"].values()) and r["nonInt"] == 0
                and r["unexpectedCarriers"] == 0
                and (self.mode == "absent" or (r["x2dlPositiveByNode"] and all(r["x2dlPositiveByNode"].values()))))


UE_CONTEXT_IN_IPC_TRACE_EXIT = 3


def is_ue_context_line(line):
    """A `ueContext` line (also one that does not parse but names the type)."""
    try:
        return json.loads(line).get("type") == "ueContext"
    except (ValueError, AttributeError):
        return '"ueContext"' in line


def digests(run, n4=None):
    run = pathlib.Path(run)
    ledger = run / "trace" / "e2-control-ledger.jsonl"
    samples = IPC.load_samples(run / "trace", n4)
    ipc_dropped = ue_context_lines = 0
    for p in sorted((run / "trace").glob("e2-ipc-trace-*.jsonl")):
        for line in p.read_text().splitlines():
            if '"type":"sample"' in line:
                ipc_dropped = max(ipc_dropped, json.loads(line).get("ipcDropped", 0))
            ue_context_lines += is_ue_context_line(line)
    out = {
        "ledger": sha(ledger.read_text()) if ledger.exists() else sha(""),
        "ledgerLines": max(0, len(ledger.read_text().splitlines()) - 1) if ledger.exists() else 0,
        "ipc": {str(n): sha("\n".join(s[k] for k in sorted(s))) for n, s in sorted(samples.items())},
        "ipcSamples": {str(n): len(s) for n, s in sorted(samples.items())},
        "ipcDroppedMax": ipc_dropped,
        "ipcTraceUeContextLines": ue_context_lines,
        "traces": FREE.trace_digests(run),
        # only the named live components: the extractor's diagnostics (rc-requests, rc-answers: RIC request IDs
        # and wall times) sit in the same directory and must never be digested
        "extra": {n: sha((run / "extra" / (n + ".json")).read_text()) for n in EXTRA_EXPECTED
                  if (run / "extra" / (n + ".json")).exists()},
    }
    out["overall"] = sha(json.dumps({k: out[k] for k in ("ledger", "ipc", "traces")}, sort_keys=True))
    return out


def self_test():
    """Two equal runs compare equal (exit 0); a ueContext line in one run's ipc trace makes --compare and the
    single-run mode exit 3, also when the other components differ (a "must differ" caller sees 3, not 1)."""
    import subprocess
    import tempfile
    bad = []
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        for name in ("a", "b"):
            (t / name / "trace").mkdir(parents=True)
            (t / name / "ns3run").mkdir()
            (t / name / "trace" / "e2-ipc-trace-2.jsonl").write_text(
                '{"type":"hello","nodeId":2,"kind":"gnb"}\n{"type":"sample","nodeId":2,"seq":0,"ipcDropped":0,"ues":[]}\n')
            (t / name / "ns3run" / "CellIdStats.txt").write_text("1 2 3\n")
        run = lambda *av: subprocess.run([sys.executable, "-I", __file__, *av], capture_output=True, text=True).returncode
        if run("--compare", "A=%s" % (t / "a"), "B=%s" % (t / "b")) != 0:
            bad.append("two equal runs did not compare equal")
        with open(t / "b" / "trace" / "e2-ipc-trace-2.jsonl", "a") as f:
            f.write('{"type":"ueContext","v":1,"nodeId":2,"seq":1,"ues":[]}\n')
        if run("--compare", "A=%s" % (t / "a"), "B=%s" % (t / "b")) != UE_CONTEXT_IN_IPC_TRACE_EXIT:
            bad.append("a ueContext line in the ipc trace did not exit 3 under --compare")
        if run(str(t / "b")) != UE_CONTEXT_IN_IPC_TRACE_EXIT:
            bad.append("a ueContext line in the ipc trace did not exit 3 in the single-run mode")
        (t / "b" / "ns3run" / "CellIdStats.txt").write_text("1 2 4\n")
        if run("--compare", "A=%s" % (t / "a"), "B=%s" % (t / "b")) != UE_CONTEXT_IN_IPC_TRACE_EXIT:
            bad.append("differing runs with a ueContext line did not exit 3")
    for b in bad:
        print("FAIL " + b)
    print("digest-run self-test: " + ("ok" if not bad else "%d failure(s)" % len(bad)))
    return 1 if bad else 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("--compare", action="store_true")
    ap.add_argument("--components", default="ledger,ipc,traces")
    ap.add_argument("--n4-ul-off-drop", default="", metavar="LABEL=absent|present[,...]")
    ap.add_argument("runs", nargs="+")
    a = ap.parse_args()
    if not a.compare:
        d = digests(a.runs[0])
        json.dump(d, sys.stdout, indent=2)
        print()
        return UE_CONTEXT_IN_IPC_TRACE_EXIT if d["ipcTraceUeContextLines"] else 0
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
    report["ipcTraceUeContextLines"] = {label: d[label]["ipcTraceUeContextLines"] for label in d}
    leaked = any(report["ipcTraceUeContextLines"].values())
    report["all_equal"] = ok and not leaked
    json.dump(report, sys.stdout, indent=2)
    print()
    if leaked:
        return UE_CONTEXT_IN_IPC_TRACE_EXIT
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

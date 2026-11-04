#!/usr/bin/env python3
"""reference-compare.py: the committed dev reference of the top rung and the M9 comparison against it.

  reference-compare.py make RUN REFDIR [--file NAME=PATH ...] [--recorded NAME=PATH ...]
        REFDIR/equal/digests.json   digest-run.py's ledger, ipc, traces and extra digests of RUN (live1 of a green C1)
        REFDIR/equal/files.json     sha256 of each --file (R3′: the predictor records, the schedule, the scenario)
        REFDIR/recorded/NAME        a copy of each --recorded file (image IDs: reported, never judged)
        REFDIR/SHA256SUMS           sha256 of every file above, relative to REFDIR
  reference-compare.py compare RUN REFDIR [--file NAME=PATH ...] [--recorded NAME=PATH ...]
        SHA256SUMS verifies; RUN's ipc trace holds no ueContext line (make refuses such a RUN too); RUN's digests
        equal equal/digests.json on every component; each --file's sha256
        equals equal/files.json (same names); --recorded files are diffed and reported only.
        Prints {"equalsReference": bool, ...}; exit 0 iff equal.
  --components C,C,...   (make and compare; default ledger,ipc,traces,extra) the digest components the reference
        holds. A δ > 0 reference is sim-side only (ledger,ipc,traces). compare fails unless the reference holds
        exactly the requested set, so a sim-side reference never passes a full comparison.
  reference-compare.py --self-test
"""
import hashlib
import importlib.util
import json
import pathlib
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
COMPONENTS = ("ledger", "ipc", "traces", "extra")


def digest_run():
    spec = importlib.util.spec_from_file_location("digest_run", HERE / "digest-run.py")
    assert spec is not None and spec.loader is not None
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


def pairs(av, flag):
    return dict(av[i + 1].split("=", 1) for i, x in enumerate(av) if x == flag)


def make(run, ref, files, recorded, components=COMPONENTS):
    ref = pathlib.Path(ref)
    (ref / "equal").mkdir(parents=True, exist_ok=True)
    (ref / "recorded").mkdir(exist_ok=True)
    d = digest_run().digests(run)
    if d["ipcTraceUeContextLines"]:
        raise SystemExit("reference-compare make: %d ueContext line(s) in %s's ipc trace" % (d["ipcTraceUeContextLines"], run))
    json.dump({c: d[c] for c in components}, open(ref / "equal" / "digests.json", "w"), indent=1, sort_keys=True)
    json.dump({n: sha(p) for n, p in files.items()}, open(ref / "equal" / "files.json", "w"), indent=1, sort_keys=True)
    for n, p in recorded.items():
        shutil.copyfile(p, ref / "recorded" / n)
    sums = sorted(str(p.relative_to(ref)) for p in ref.rglob("*") if p.is_file() and p.name != "SHA256SUMS")
    (ref / "SHA256SUMS").write_text("".join("%s  %s\n" % (sha(ref / p), p) for p in sums))


def compare(run, ref, files, recorded, components=COMPONENTS):
    ref, probs, out = pathlib.Path(ref), [], {}
    sums = ref / "SHA256SUMS"
    if not sums.exists():
        probs.append("no SHA256SUMS")
    else:
        listed = set()
        for line in sums.read_text().splitlines():
            h, _, p = line.partition("  ")
            listed.add(p)
            if not (ref / p).exists() or sha(ref / p) != h:
                probs.append("SHA256SUMS: %s does not verify" % p)
        extra = {str(p.relative_to(ref)) for p in ref.rglob("*") if p.is_file() and p.name != "SHA256SUMS"} - listed
        probs += ["SHA256SUMS: %s is not listed" % p for p in sorted(extra)]
    if not probs:
        want, d = json.load(open(ref / "equal" / "digests.json")), digest_run().digests(run)
        if d["ipcTraceUeContextLines"]:
            probs.append("%d ueContext line(s) in the run's ipc trace" % d["ipcTraceUeContextLines"])
        if set(want) != set(components):
            probs.append("reference components %r, requested %r" % (sorted(want), sorted(components)))
        out["differingComponents"] = [c for c in components if d.get(c) != want.get(c)]
        probs += ["component %s differs from the reference" % c for c in out["differingComponents"]]
        wf = json.load(open(ref / "equal" / "files.json"))
        if set(wf) != set(files):
            probs.append("files %r, reference %r" % (sorted(files), sorted(wf)))
        probs += ["file %s differs from the reference" % n for n in sorted(set(wf) & set(files)) if sha(files[n]) != wf[n]]
        out["recordedDiffers"] = sorted(n for n, p in recorded.items()
                                        if not (ref / "recorded" / n).exists() or sha(p) != sha(ref / "recorded" / n))
    out.update(equalsReference=not probs, problems=probs[:20])
    return out


def self_test():
    bad = []
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        run = t / "run"
        (run / "trace").mkdir(parents=True)
        (run / "ns3run").mkdir()
        (run / "extra").mkdir()
        (run / "trace" / "e2-ipc-trace-2.jsonl").write_text('{"type":"hello","nodeId":2}\n{"type":"sample","nodeId":2,"seq":0,"ipcDropped":0}\n')
        (run / "trace" / "e2-control-ledger.jsonl").write_text('{"type":"ledgerHeader"}\n')
        (run / "ns3run" / "CellIdStats.txt").write_text("1 2 3\n")
        for n in ("rc-multiset", "kpm-headers", "collet-start-time"):
            (run / "extra" / (n + ".json")).write_text("[]")
        (t / "rec.jsonl").write_text('{"T": 30}\n')
        (t / "img.json").write_text('{"ts": "sha256:1"}')
        files, recd = {"predictor-records": str(t / "rec.jsonl")}, {"images.json": str(t / "img.json")}
        make(run, t / "ref", files, recd)
        if not compare(run, t / "ref", files, recd)["equalsReference"]:
            bad.append("a run equal to its own reference")
        (t / "img.json").write_text('{"ts": "sha256:2"}')
        r = compare(run, t / "ref", files, recd)
        if not r["equalsReference"] or r["recordedDiffers"] != ["images.json"]:
            bad.append("a recorded difference is reported, never judged: %r" % r)
        (run / "ns3run" / "CellIdStats.txt").write_text("1 2 4\n")
        if compare(run, t / "ref", files, recd)["equalsReference"]:
            bad.append("a changed trace equals the reference")
        (run / "ns3run" / "CellIdStats.txt").write_text("1 2 3\n")
        (t / "rec.jsonl").write_text('{"T": 31}\n')
        if compare(run, t / "ref", files, recd)["equalsReference"]:
            bad.append("changed predictor records equal the reference")
        (t / "rec.jsonl").write_text('{"T": 30}\n')
        (t / "ref" / "equal" / "files.json").write_text("{}")
        if compare(run, t / "ref", files, recd)["equalsReference"]:
            bad.append("a tampered reference passes SHA256SUMS")
        make(run, t / "sim", files, recd, ("ledger", "ipc", "traces"))
        if not compare(run, t / "sim", files, recd, ("ledger", "ipc", "traces"))["equalsReference"]:
            bad.append("a run equal to its own sim-side reference")
        if compare(run, t / "sim", files, recd)["equalsReference"]:
            bad.append("a sim-side reference passes a full comparison")
        ipc = run / "trace" / "e2-ipc-trace-2.jsonl"
        ipc.write_text(ipc.read_text() + '{"type":"ueContext","v":1,"nodeId":2,"seq":1,"ues":[]}\n')
        if compare(run, t / "ref", files, recd)["equalsReference"]:
            bad.append("a run whose ipc trace holds a ueContext line equals the reference")
        try:
            make(run, t / "ref2", files, recd)
            bad.append("make accepted a run whose ipc trace holds a ueContext line")
        except SystemExit:
            pass
    for b in bad:
        print("FAIL " + b)
    print("reference-compare self-test: %s" % ("ok" if not bad else "%d failure(s)" % len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    av = sys.argv[1:]
    if av == ["--self-test"]:
        sys.exit(self_test())
    if len(av) < 3 or av[0] not in ("make", "compare"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    f, r = pairs(av[3:], "--file"), pairs(av[3:], "--recorded")
    comp = COMPONENTS
    if "--components" in av:
        comp = tuple(av[av.index("--components") + 1].split(","))
        if not comp or set(comp) - set(COMPONENTS):
            print("unknown components %r" % (comp,), file=sys.stderr)
            sys.exit(2)
    if av[0] == "make":
        make(av[1], av[2], f, r, comp)
        sys.exit(0)
    res = compare(av[1], av[2], f, r, comp)
    print(json.dumps(res, indent=1, sort_keys=True))
    sys.exit(0 if res["equalsReference"] else 1)

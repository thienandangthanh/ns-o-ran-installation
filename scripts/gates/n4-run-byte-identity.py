#!/usr/bin/env python3
"""n4-run-byte-identity.py: byte identity of two N4 free runs on a fixed compared set.

Compared set of one run directory (uloff or ulon); every item is the sha256 of its normalised bytes:
  ns3run/<name>                         every ns3run/*.txt except stdout.txt and stderr.txt, same name set;
                                        DlE2RlcStatsLte.txt without its columns 5-6 (contract C1: the digest
                                        comes from compare-free-run.py's trace_digests, the one source of that rule)
  trace/e2-ue-context-<n>.jsonl         the whole file
  trace/e2-ipc-trace-<n>.jsonl:samples  the `sample` lines, raw, in file order; `hello` (pid run id, written per
                                        connection) and `bye` (delivery counters) are not compared
  ns3run/stdout.txt:body                stdout without its first `N4AUDIT v2 hdr=` line
  ns3run/stdout.txt:audit-header        that line alone (null when absent): its own item, so a caller can judge it apart
  ns3-argv.txt                          the ns-3 arguments, one per line, the run directory written as <run>
                                        (the gate writes it; the binary path is not an argument)
Preconditions (any failure exits 2: an inconclusive run, not a byte-identity result), checked on each run alone so
that two runs missing the same output never compare equal:
  - ns3-exit, when recorded, is 0; ns3-argv.txt holds --simTime and --nMmWaveEnbNodes=n; stdout.txt exists;
    no e2-control-ledger.jsonl anywhere;
  - every file of REQUIRED_TRACES is present and non-empty, and each of REQUIRED_ROWS holds a row that is not a
    `%` header;
  - the IPC trace and UE context node sets are both exactly {1, ..., n+1}: the LTE eNB is cell 1 and the gNBs are
    cells 2..n+1, the emitter's nodeId being the cell id (lte-enb-net-device.cc, mmwave-enb-net-device.cc); every
    emitter writes its UE context file's seq-0 line with its first sample, so none is empty;
  - each IPC trace holds a non-empty sample stream with exactly the seqs 0..N-1 (N = simTime / the hello's periodNs),
    "ipcDropped":0 in every sample and no line other than hello, sample and bye;
  - a ulon run (--enableUlTraffic=true in its argv) has >= 1 ulrx, >= 1 dltx and one end line.

  n4-run-byte-identity.py manifest RUN   write RUN/n4-run-bytes.manifest.json and print it; exit 2 on a precondition
  n4-run-byte-identity.py compare A B    A, B: run dirs or manifests; exit 0 equal, 1 differ (the differing items
                                         listed, with the first differing line when both are run dirs), 2 precondition
  n4-run-byte-identity.py compare --except-audit-header A B
                                         the same, without the ns3run/stdout.txt:audit-header item (a build that
                                         changes that line on purpose, judged apart); every other item is compared
  n4-run-byte-identity.py verify-reference DIR NAME...
                                         DIR/SHA256SUMS strictly: every line is `<64 lowercase hex>  <name>`, each NAME
                                         has exactly one entry and DIR/NAME has that digest; prints the verified digests
                                         as JSON; exit 0 verified, 1 not
  n4-run-byte-identity.py --self-test    the must-fail and must-pass fixtures
"""
import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import re
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = "n4-run-bytes.manifest.json"
SCHEMA = "n4-run-bytes/v1"
HDR = b"N4AUDIT v2 hdr="
ABSENT = "<absent>"
AUDIT_HEADER_ITEM = "ns3run/stdout.txt:audit-header"
# Every ns3run trace scenario-zero writes in the N4 config (NoAuto, so no handover files): the same 28 names in the
# archived N4 uloff and ulon runs and in an M7 run, each non-empty there.
REQUIRED_TRACES = (
    "CellIdStats.txt", "DlE2PdcpStats.txt", "DlE2PdcpStatsLte.txt", "DlE2RlcStats.txt", "DlE2RlcStatsLte.txt",
    "DlMacStats.txt", "DlPdcpStats.txt", "DlPhyTransmissionTrace.txt", "DlRlcStats.txt", "DlRxPhyStats.txt",
    "DlTxPhyStats.txt", "EnbSchedAllocTraces.txt", "LteDlRsrpSinrStats.txt", "LteUlSinrStats.txt", "MmWaveSinrTime.txt",
    "MmWaveSwitchStats.txt", "RlcAmBufferSize.txt", "RxPacketTrace.txt", "UeFailures.txt", "UlE2PdcpStats.txt",
    "UlE2PdcpStatsLte.txt", "UlE2RlcStats.txt", "UlE2RlcStatsLte.txt", "UlPdcpStats.txt", "UlRlcStats.txt",
    "X2Stats.txt", "enbs.txt", "ues.txt")
# The traces the scenario always fills with rows in this config (positions, attach, switches, X2, DL RLC periods).
REQUIRED_ROWS = ("ues.txt", "enbs.txt", "CellIdStats.txt", "MmWaveSwitchStats.txt", "X2Stats.txt", "DlE2RlcStatsLte.txt")


def _load_free_run():
    spec = importlib.util.spec_from_file_location("compare_free_run", HERE / "compare-free-run.py")
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FREE = _load_free_run()


def sha(b):
    return hashlib.sha256(b).hexdigest()


def raw_lines(p):
    return p.read_bytes().splitlines(keepends=True)


def line_type(raw):
    """The JSON `type` of an IPC trace line; None when the line does not parse as an object."""
    try:
        msg = json.loads(raw)
    except ValueError:
        return None, None
    return (msg.get("type"), msg) if isinstance(msg, dict) else (None, None)


def has_row(p):
    """True when the file holds a non-blank line that is not a `%` header (streamed: some traces are large)."""
    with p.open("rb") as f:
        return any(line.strip() and not line.startswith(b"%") for line in f)


def node_ids(trace_dir, prefix):
    """The node ids of trace_dir's <prefix><n>.jsonl files, as written in their names."""
    return {p.name[len(prefix):-len(".jsonl")] for p in trace_dir.glob(prefix + "*.jsonl")}


def split_stdout(lines):
    """(stdout without its first audit header line, that line or None)."""
    for i, line in enumerate(lines):
        if line.startswith(HDR):
            return lines[:i] + lines[i + 1:], line
    return lines, None


def build(run):
    run = pathlib.Path(run)
    fail, items, counts = [], {}, {}
    ex = run / "ns3-exit"
    if ex.exists() and ex.read_text().strip() != "0":
        fail.append("ns-3 exit %s" % ex.read_text().strip())
    ap = run / "ns3-argv.txt"
    argv = ap.read_text().splitlines() if ap.exists() else []
    if ap.exists():
        items["ns3-argv.txt"] = sha(ap.read_bytes())
    else:
        fail.append("no ns3-argv.txt")
    config = "ulon" if "--enableUlTraffic=true" in argv else "uloff"
    sim = [a.split("=", 1)[1] for a in argv if a.startswith("--simTime=")]
    try:
        sim_s = float(sim[-1])
    except (IndexError, ValueError):
        sim_s = None
        fail.append("no numeric --simTime in ns3-argv.txt")
    nmm = [a.split("=", 1)[1] for a in argv if a.startswith("--nMmWaveEnbNodes=")]
    want_nodes = {str(i) for i in range(1, int(nmm[-1]) + 2)} if nmm and nmm[-1].isdigit() else None
    if want_nodes is None:
        fail.append("no integer --nMmWaveEnbNodes in ns3-argv.txt")
    ledgers = sorted(str(p.relative_to(run)) for p in run.rglob("e2-control-ledger.jsonl"))
    if ledgers:
        fail.append("ledger file(s) %s" % ledgers)
    nd = run / "ns3run"
    absent = [n for n in REQUIRED_TRACES if not (nd / n).is_file() or (nd / n).stat().st_size == 0]
    if absent:
        fail.append("required ns3run trace(s) missing or empty: %s" % absent)
    rowless = [n for n in REQUIRED_ROWS if (nd / n).is_file() and not has_row(nd / n)]
    if rowless:
        fail.append("ns3run trace(s) without a row: %s" % rowless)
    for prefix in ("e2-ipc-trace-", "e2-ue-context-"):
        got = node_ids(run / "trace", prefix)
        if want_nodes is not None and got != want_nodes:
            fail.append("%s<n>.jsonl node set %s, want %s" % (prefix, sorted(got), sorted(want_nodes, key=int)))
    empty_ctx = sorted(p.name for p in (run / "trace").glob("e2-ue-context-*.jsonl") if p.stat().st_size == 0)
    if empty_ctx:
        fail.append("empty UE context file(s) %s" % empty_ctx)
    for name, digest in FREE.trace_digests(run).items():
        items["ns3run/" + name] = digest
    for p in sorted((run / "trace").glob("e2-ue-context-*.jsonl")):
        items["trace/" + p.name] = sha(p.read_bytes())
        counts["trace/" + p.name] = len(raw_lines(p))
    ipc = sorted((run / "trace").glob("e2-ipc-trace-*.jsonl"))
    if not ipc:
        fail.append("no trace/e2-ipc-trace-*.jsonl")
    pins = set()
    for p in ipc:
        kept, seqs, period, dropped, odd = [], [], None, 0, 0
        for raw in raw_lines(p):
            t, msg = line_type(raw)
            if t == "hello":
                period = period or msg.get("periodNs")
                em = msg.get("emitter") or {}
                pins.add((em.get("ns3Sha"), em.get("oranInterfaceSha")))
            elif t == "sample":
                kept.append(raw)
                seqs.append(msg.get("seq"))
                d = msg.get("ipcDropped")
                dropped += type(d) is not int or d != 0
            elif t != "bye":
                odd += 1
        item = "trace/%s:samples" % p.name
        items[item], counts[item] = sha(b"".join(kept)), len(kept)
        if not kept:
            fail.append("%s: no sample line" % p.name)
        if dropped:
            fail.append("%s: %d sample(s) without \"ipcDropped\":0" % (p.name, dropped))
        if odd:
            fail.append("%s: %d line(s) neither hello, sample nor bye" % (p.name, odd))
        n = round(sim_s * 1e9 / period) if sim_s and isinstance(period, int) and period > 0 else None
        if n is None or not all(type(s) is int for s in seqs) or sorted(seqs) != list(range(n)):
            fail.append("%s: seqs are not exactly 0..N-1 (N %s, %d samples)" % (p.name, n, len(seqs)))
    so = run / "ns3run" / "stdout.txt"
    header, events = None, {}
    if so.exists():
        body, header = split_stdout(raw_lines(so))
        items["ns3run/stdout.txt:body"], counts["ns3run/stdout.txt:body"] = sha(b"".join(body)), len(body)
        items["ns3run/stdout.txt:audit-header"] = None if header is None else sha(header)
        events = {k: sum(line.startswith(b"N4AUDIT %s" % k.encode()) for line in body) for k in ("ulrx", "dltx", "end")}
        if config == "ulon" and not (events["ulrx"] >= 1 and events["dltx"] >= 1 and events["end"] == 1):
            fail.append("ulon audit lines %s (want ulrx >= 1, dltx >= 1, end 1)" % events)
    else:
        fail.append("no ns3run/stdout.txt")
    return {"schema": SCHEMA, "config": config, "items": items, "lines": counts,
            "info": {"auditHeader": None if header is None else header.decode(errors="replace").rstrip("\n"),
                     "auditEvents": events, "emitterPins": sorted(map(list, pins), key=str), "simTime_s": sim_s},
            "excluded": {"ipcTraceLines": ["hello", "bye"], "ns3runFiles": sorted(FREE.LOGS),
                         "dlE2RlcStatsLteColumns": sorted(FREE.COLUMN_EXCLUSIONS["DlE2RlcStatsLte.txt"])},
            "preconditions": {"ok": not fail, "failures": fail}}


def item_lines(run, item):
    """The normalised lines behind one item, for the first-differing-line diagnostic only (the verdict is the digest)."""
    name, _, part = item.partition(":")
    p = run / name
    lines = raw_lines(p) if p.is_file() else []
    if part == "samples":
        return [line for line in lines if line_type(line)[0] == "sample"]
    if part:
        body, header = split_stdout(lines)
        return body if part == "body" else [header or b""]
    drop = FREE.COLUMN_EXCLUSIONS.get(p.name, set())
    return [b" ".join(c for i, c in enumerate(line.split(), 1) if i not in drop) for line in lines] if drop else lines


def first_diff(da, db, item):
    la, lb = item_lines(da, item), item_lines(db, item)
    for i in range(max(len(la), len(lb))):
        a, b = (la[i] if i < len(la) else b"<eof>"), (lb[i] if i < len(lb) else b"<eof>")
        if a != b:
            return {"line": i + 1, "a": a[:240].decode(errors="replace"), "b": b[:240].decode(errors="replace")}
    return None


def load(arg):
    p = pathlib.Path(arg)
    if p.is_dir():
        return build(p), p
    m = json.loads(p.read_text())
    if m.get("schema") != SCHEMA:
        raise ValueError("%s is not an %s manifest" % (arg, SCHEMA))
    return m, None


def compare(a, b, skip=()):
    """Exit code of comparing A and B on every item except the ones named in skip (only AUDIT_HEADER_ITEM is allowed)."""
    assert set(skip) <= {AUDIT_HEADER_ITEM}, skip
    try:
        (ma, da), (mb, db) = load(a), load(b)
    except (OSError, ValueError) as exc:
        print(json.dumps({"equal": None, "error": str(exc)}))
        return 2
    report = {"a": str(a), "b": str(b), "configs": [ma["config"], mb["config"]], "skipped": sorted(skip),
              "preconditions": {"a": ma["preconditions"], "b": mb["preconditions"]}}
    if not (ma["preconditions"]["ok"] and mb["preconditions"]["ok"]):
        report["equal"] = None
        print(json.dumps(report, indent=2))
        return 2
    ia = {k: v for k, v in ma["items"].items() if k not in skip}
    ib = {k: v for k, v in mb["items"].items() if k not in skip}
    differing = sorted(k for k in set(ia) | set(ib) if ia.get(k, ABSENT) != ib.get(k, ABSENT))
    report.update(equal=not differing, itemsCompared=len(set(ia) | set(ib)), differing=differing,
                  onlyInA=sorted(set(ia) - set(ib)), onlyInB=sorted(set(ib) - set(ia)))
    if da and db and differing:
        report["firstDifferingLines"] = {k: first_diff(da, db, k) for k in differing[:12]}
    print(json.dumps(report, indent=2))
    return 0 if not differing else 1


SUMS_LINE = re.compile(r"([0-9a-f]{64})  (\S(?:.*\S)?)")


def verify_reference(ref_dir, names):
    """(problems, {name: verified sha256}) of ref_dir/SHA256SUMS for the files NAMES (see the module doc)."""
    ref_dir, bad, entries = pathlib.Path(ref_dir), [], {}
    try:
        lines = (ref_dir / "SHA256SUMS").read_text().split("\n")
    except (OSError, UnicodeDecodeError) as exc:
        return ["cannot read %s/SHA256SUMS: %s" % (ref_dir, exc)], {}
    if lines and lines[-1] == "":
        lines.pop()   # the final newline
    for n, line in enumerate(lines, 1):
        m = SUMS_LINE.fullmatch(line)
        if not m:
            bad.append("SHA256SUMS:%d: not `<64 hex>  <name>`: %r" % (n, line[:120]))
            continue
        entries.setdefault(m.group(2), []).append(m.group(1))
    digests = {}
    for name in names:
        got = entries.get(name, [])
        if len(got) != 1:
            bad.append("SHA256SUMS has %d entries for %s, want exactly 1" % (len(got), name))
            continue
        try:
            actual = sha((ref_dir / name).read_bytes())
        except OSError as exc:
            bad.append("cannot read %s: %s" % (name, exc))
            continue
        if actual != got[0]:
            bad.append("%s: sha256 %s, SHA256SUMS says %s" % (name, actual, got[0]))
        else:
            digests[name] = actual
    if not names:
        bad.append("no file to verify")
    return bad, digests


def verify_self_test():
    """Failures of the strict SHA256SUMS fixtures."""
    names = ["m-uloff.json", "m-ulon.json"]
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        for nm in names + ["m-uloffXjson", "other.txt"]:
            (t / nm).write_text("content of %s\n" % nm)
        good = ["%s  %s" % (sha((t / nm).read_bytes()), nm) for nm in names + ["other.txt"]]
        cases = [  # (name, SHA256SUMS lines, wanted ok)
            ("good", good, True),
            ("a missing entry", good[1:], False),
            ("a bare name line instead of an entry", ["m-uloff.json"] + good[1:], False),
            ("a bare name line besides the entries", good + ["m-ulon.json"], False),
            ("a malformed line", good + ["not a checksum line"], False),
            ("a binary-mode line", ["%s *m-uloff.json" % good[0][:64]] + good[1:], False),
            ("an uppercase digest", [good[0][:64].upper() + good[0][64:]] + good[1:], False),
            ("a wrong digest", ["0" * 64 + "  m-uloff.json"] + good[1:], False),
            ("a look-alike file name only", ["%s  m-uloffXjson" % sha((t / "m-uloffXjson").read_bytes())] + good[1:],
             False),
            ("a duplicate entry", good + [good[0]], False),
            ("a blank line", good[:1] + [""] + good[1:], False),
        ]
        fails = []
        for name, lines, want in cases:
            (t / "SHA256SUMS").write_text("".join(x + "\n" for x in lines))
            bad, digests = verify_reference(t, names)
            if (not bad) != want or (want and sorted(digests) != names):
                fails.append("verify-reference %s: problems %s" % (name, bad))
        return fails


def self_test():
    def write_base(d):
        (d / "ns3run").mkdir(parents=True)
        (d / "trace").mkdir()
        (d / "ns3-exit").write_text("0\n")
        (d / "ns3-argv.txt").write_text(
            "--nMmWaveEnbNodes=2\n--simTime=0.3\n--enableUlTraffic=true\n--e2TraceDir=<run>/trace\n")
        for n in REQUIRED_TRACES:
            (d / "ns3run" / n).write_text("0.1 1 2\n")
        (d / "ns3run" / "CellIdStats.txt").write_text("0.1 1 2\n0.2 1 3\n")
        (d / "ns3run" / "DlE2RlcStatsLte.txt").write_text("% start end CellId IMSI\n0.1 0.2 1 2 33 44 5 6\n")
        (d / "ns3run" / "stderr.txt").write_text("connected at 12:00:01\n")
        (d / "ns3run" / "stdout.txt").write_text(
            "N4AUDIT v2 hdr=2\nN4AUDIT ulrx 150000000 0 1 3 3 1310 2000000 2\nN4AUDIT dltx 170000000 0 1 3 3 1310 0\n"
            "N4AUDIT end connected=2 present=2 missing=0\n")
        for n in (1, 2, 3):
            (d / "trace" / ("e2-ue-context-%d.jsonl" % n)).write_text(
                '{"type":"ueContext","v":1,"nodeId":%d,"seq":0,"ues":[1]}\n' % n)
            hello = ('{"type":"hello","nodeId":%d,"periodNs":100000000,"runId":"1-111",'
                     '"emitter":{"ns3Sha":"a","oranInterfaceSha":"b"}}\n' % n)
            samples = "".join('{"type":"sample","nodeId":%d,"seq":%d,"ipcDropped":0,"v":%d}\n' % (n, s, 10 + s)
                              for s in range(3))
            (d / "trace" / ("e2-ipc-trace-%d.jsonl" % n)).write_text(
                hello + samples + '{"type":"bye","nodeId":%d,"sent":3}\n' % n)

    def edit(rel, old, new):
        def f(d):
            p = d / rel
            text = p.read_text()
            assert old in text, "fixture edit is a no-op: %s not in %s" % (old, rel)
            p.write_text(text.replace(old, new, 1))
        return f

    def rm(rel):
        return lambda d: (d / rel).unlink()

    def keep_no_samples(d):
        p = d / "trace" / "e2-ipc-trace-3.jsonl"
        p.write_text("".join(x for x in p.read_text().splitlines(keepends=True) if '"sample"' not in x))

    def move_hello(d):
        p = d / "trace" / "e2-ipc-trace-2.jsonl"
        ls = p.read_text().splitlines(keepends=True)
        p.write_text("".join(ls[1:2] + ls[:1] + ls[2:]))

    ipc, so, rlc = "trace/e2-ipc-trace-2.jsonl", "ns3run/stdout.txt", "ns3run/DlE2RlcStatsLte.txt"
    skip_hdr = (AUDIT_HEADER_ITEM,)
    fixtures = [  # (name, mutation of B (and of A too when the name starts with "both"), wanted compare exit[, skip])
        ("identical runs", lambda d: None, 0),
        ("columns 5-6 of DlE2RlcStatsLte.txt changed", edit(rlc, "1 2 33 44", "1 2 77 88"), 0),
        ("hello changed (pid run id)", edit(ipc, '"1-111"', '"1-222"'), 0),
        ("hello moved after the first sample", move_hello, 0),
        ("bye changed", edit(ipc, '"sent":3', '"sent":2'), 0),
        ("stderr.txt changed", edit("ns3run/stderr.txt", "12:00:01", "12:09:59"), 0),
        ("a changed ns3run trace byte", edit("ns3run/CellIdStats.txt", "0.2 1 3", "0.2 1 4"), 1),
        ("a changed IPC sample byte", edit(ipc, '"v":11', '"v":12'), 1),
        ("column 4 of DlE2RlcStatsLte.txt changed", edit(rlc, "1 2 33 44", "1 9 33 44"), 1),
        ("a missing ns3run trace file", rm("ns3run/CellIdStats.txt"), 2),
        ("an extra ns3run trace file", lambda d: (d / "ns3run" / "Extra.txt").write_text("x\n"), 1),
        ("an extra UE context node", lambda d: (d / "trace" / "e2-ue-context-4.jsonl").write_text("{}\n"), 2),
        ("a missing IPC trace node", rm("trace/e2-ipc-trace-3.jsonl"), 2),
        ("both lack the same ns3run trace file", rm("ns3run/X2Stats.txt"), 2),
        ("both lack the same IPC trace node", rm("trace/e2-ipc-trace-3.jsonl"), 2),
        ("both lack the same UE context node", rm("trace/e2-ue-context-1.jsonl"), 2),
        ("both have an empty sample stream at one node", keep_no_samples, 2),
        ("both have an empty UE context file", lambda d: (d / "trace" / "e2-ue-context-2.jsonl").write_text(""), 2),
        ("both have a required trace with its header only", edit(rlc, "0.1 0.2 1 2 33 44 5 6\n", ""), 2),
        ("both lack --nMmWaveEnbNodes", edit("ns3-argv.txt", "--nMmWaveEnbNodes=2\n", ""), 2),
        ("a changed audit event", edit(so, "ulrx 150000000 0 1 3 3 1310", "ulrx 150000000 0 1 3 3 1311"), 1),
        ("a changed audit header", edit(so, "hdr=2", "hdr=3"), 1),
        ("a changed UE context line", edit("trace/e2-ue-context-2.jsonl", '"ues":[1]', '"ues":[2]'), 1),
        ("a changed argv", edit("ns3-argv.txt", "--simTime=0.3\n", "--simTime=0.3\n--RngRun=2\n"), 1),
        ("ipcDropped 1", edit(ipc, '"seq":1,"ipcDropped":0', '"seq":1,"ipcDropped":1'), 2),
        ("ns-3 exit 1", lambda d: (d / "ns3-exit").write_text("1\n"), 2),
        ("a ledger file", lambda d: (d / "trace" / "e2-control-ledger.jsonl").write_text("{}\n"), 2),
        ("an incomplete seq range", edit(ipc, '"seq":2', '"seq":3'), 2),
        ("ulon without a dltx line", edit(so, "N4AUDIT dltx", "N4AUDIT dlxx"), 2),
        ("an unknown IPC line type", edit(ipc, '{"type":"bye"', '{"type":"other"'), 2),
        ("no ns3-argv.txt", rm("ns3-argv.txt"), 2),
        # --except-audit-header leaves out that one item and nothing else
        ("audit header changed, skipped", edit(so, "hdr=2", "hdr=2 class=ns3::NrPdcpHeader"), 0, skip_hdr),
        ("audit header removed, skipped", edit(so, "N4AUDIT v2 hdr=2\n", ""), 0, skip_hdr),
        ("audit event changed, header skipped", edit(so, "dltx 170000000 0 1 3 3 1310", "dltx 170000000 0 1 3 3 1311"), 1,
         skip_hdr),
        ("trace byte changed, header skipped", edit("ns3run/CellIdStats.txt", "0.2 1 3", "0.2 1 4"), 1, skip_hdr),
        ("IPC sample changed, header skipped", edit(ipc, '"v":11', '"v":12'), 1, skip_hdr),
        ("argv changed, header skipped", edit("ns3-argv.txt", "--simTime=0.3\n", "--simTime=0.3\n--RngRun=2\n"), 1,
         skip_hdr),
    ]
    bad = []
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        write_base(t / "a")
        for i, (name, mutate, want, *skip) in enumerate(fixtures):
            a, b = t / "a", t / ("b%d" % i)
            shutil.copytree(t / "a", b)
            mutate(b)
            if name.startswith("both"):
                a = t / ("a%d" % i)
                shutil.copytree(t / "a", a)
                mutate(a)
            with contextlib.redirect_stdout(io.StringIO()):
                got = compare(a, b, *skip)
            if got != want:
                bad.append("%s: compare exit %d, want %d" % (name, got, want))
        with contextlib.redirect_stdout(io.StringIO()):
            rc = main(["manifest", str(t / "a")])
            got = compare(t / "a" / MANIFEST, t / "a")
        if rc != 0 or got != 0:
            bad.append("a written manifest against its own run: manifest exit %d, compare exit %d (want 0, 0)" % (rc, got))
    bad += verify_self_test()
    for b in bad:
        print("FAIL " + b)
    print("n4-run-byte-identity self-test: " + ("ok (%d fixtures)" % len(fixtures) if not bad else "%d failure(s)" % len(bad)))
    return 1 if bad else 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) == 2 and argv[0] == "manifest":
        run = pathlib.Path(argv[1])
        if not run.is_dir():
            print("no run directory %s" % run, file=sys.stderr)
            return 2
        m = build(run)
        text = json.dumps(m, indent=2) + "\n"
        (run / MANIFEST).write_text(text)
        sys.stdout.write(text)
        for f in m["preconditions"]["failures"]:
            print("precondition: " + f, file=sys.stderr)
        return 0 if m["preconditions"]["ok"] else 2
    if len(argv) == 3 and argv[0] == "compare":
        return compare(argv[1], argv[2])
    if len(argv) >= 2 and argv[0] == "verify-reference":
        bad, digests = verify_reference(argv[1], argv[2:])
        print(json.dumps({"dir": argv[1], "verified": digests, "problems": bad}, indent=2))
        return 1 if bad else 0
    if len(argv) == 4 and argv[:2] == ["compare", "--except-audit-header"]:
        return compare(argv[2], argv[3], (AUDIT_HEADER_ITEM,))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

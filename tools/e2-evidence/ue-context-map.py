#!/usr/bin/env python3
"""ue-context-map.py: a run's UE context map (ns-3's X2AP UE contexts) and the resolution of KPM UE IDs to IMSIs.

  ue-context-map.py check --trace-dir DIR --pdcp DlE2PdcpStatsLte.txt [--expect-map identity-map.json] [--out FILE]
  ue-context-map.py --self-test

ns-3 writes e2-ue-context-<n>.jsonl next to e2-ipc-trace-<n>.jsonl (--e2TraceDir): one ns3-e2-ipc v1 `ueContext`
line per emission, {"type": "ueContext", "v": 1, "nodeId": n, "seq": s, "ues": [{"imsi", "lteRnti", "mnCellId",
"mmeUeS1apId"}, ...]}, written before the sample of seq s whenever the node's contexts changed (or the agent
reconnected). `check` passes iff:
  (a) every node n with a hello in e2-ipc-trace-<n>.jsonl has e2-ue-context-<n>.jsonl; every line has the shape of
      the schema's `ueContext` (keys, types, ranges), nodeId n, seq strictly increasing in the file, `ues` sorted by
      imsi, each imsi once;
  (b) ctx(n, s) := the `ues` of node n's last line with seq <= s (none before the first line); every IMSI of node n's
      IPC sample s is in ctx(n, s);
  (c) over all files each IMSI has one (lteRnti, mnCellId, mmeUeS1apId), lteRnti in 0..4095, mnCellId = 1 (the
      eNB), mmeUeS1apId = imsi (ns-3's construction, disclosed), and no two IMSIs share (lteRnti, mnCellId);
  (d) that lteRnti equals the IMSI's single RNTI on cell 1 of the run's DlE2PdcpStatsLte.txt (identity-map-extract.py
      `extract`, which also requires every row on the MN cell and one RNTI per IMSI), so the map is anchored on
      ns-3's own MN PDCP trace, not on the IPC channel it is checked for.
--expect-map adds the live cross-check against a frozen identity map (identity-map-extract.py output): the run's
IMSI set equals the map's, per IMSI lteRnti = ues[imsi].mEnbUeX2apId and mnCellId = the map's mnCellId, the map's
globalEnbId is {00F110, 00001}, and the map's sha256 is the one listed for it in the SHA256SUMS of its directory.

KPM UE IDs (the representation the kpimon decode harness prints and the RC UE ID transform uses):
  gNB node: {"type": "en-gNB-UEID", "mEnbUeX2apId": lteRnti, "globalEnbId": {"plmn": "00F110", "macroEnbId": "%05X"}},
            Influx tag enGnbUeId:<lteRnti>@00F110-<mnCellId %05X>;
  eNB node: {"type": "eNB-UEID", "mmeUeS1apId": m, "gummei": {"plmn": "00F110", "mmeGroupId": "0001", "mmeCode": "01"},
            "mEnbUeX2apId": lteRnti} (globalENB-ID absent), Influx tag enbUeId:<mmeUeS1apId>@<lteRnti>.
R(n, S, id) := the unique IMSI i in ctx(n, s) for some s in S whose ID of node n's kind equals id, else unresolved.
Other tools load this file with importlib (UeContextMap, wire_id_problems, wire_id_tag).
"""
import argparse
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import sys
import tempfile

PLMN = "00F110"
MN_CELL = 1
MME_GROUP_ID = "0001"
MME_CODE = "01"
GNB_TAG_RE = re.compile(r"^enGnbUeId:(0|[1-9][0-9]*)@([0-9A-F]{6})-([0-9A-F]{5})$")
ENB_TAG_RE = re.compile(r"^enbUeId:(0|[1-9][0-9]*)@(0|[1-9][0-9]*)$")
CTX_RE = re.compile(r"^e2-ue-context-([0-9]+)\.jsonl$")
TRACE_RE = re.compile(r"^e2-ipc-trace-([0-9]+)\.jsonl$")
HERE = pathlib.Path(__file__).resolve().parent


def _int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def gnb_tag(rnti, mn_cell):
    return "enGnbUeId:%d@%s-%05X" % (rnti, PLMN, mn_cell)


def enb_tag(mme, rnti):
    return "enbUeId:%d@%d" % (mme, rnti)


def tag_of(kind, ue):
    """The Influx tag of one context entry on a node of this kind."""
    return gnb_tag(ue["lteRnti"], ue["mnCellId"]) if kind == "gnb" else enb_tag(ue["mmeUeS1apId"], ue["lteRnti"])


def tag_form_ok(kind, tag):
    return isinstance(tag, str) and bool((GNB_TAG_RE if kind == "gnb" else ENB_TAG_RE).match(tag))


def wire_id_problems(kind, uid):
    """Problems of one decoded KPM UE ID against the form a node of this kind must send (empty when it conforms).
    gNB: en-gNB-UEID with globalENB-ID {00F110, macro eNB ID 1 (20 bits)} and no optional member; eNB: eNB-UEID with
    gUMMEI {00F110, 1, 1}, m-eNB-UE-X2AP-ID present and globalENB-ID absent. A gNB-UEID never conforms."""
    if not isinstance(uid, dict):
        return ["UE ID %r is not an object" % (uid,)]
    t = uid.get("type")
    if t == "gNB-UEID":
        return ["gNB-UEID %r" % (uid,)]
    if kind == "gnb":
        want = {"type", "mEnbUeX2apId", "globalEnbId"}
        if t != "en-gNB-UEID":
            return ["a gNB node's UE ID is %s, not en-gNB-UEID" % t]
        p = []
        if set(uid) != want:
            p.append("en-gNB-UEID members %s, want exactly %s (no optional member)" % (sorted(uid), sorted(want)))
        if uid.get("globalEnbId") != {"plmn": PLMN, "macroEnbId": "%05X" % MN_CELL}:
            p.append("en-gNB-UEID globalENB-ID %r, want {%s, macro eNB ID %05X}" % (uid.get("globalEnbId"), PLMN, MN_CELL))
        if not _int(uid.get("mEnbUeX2apId")) or not 0 <= uid["mEnbUeX2apId"] <= 4095:
            p.append("en-gNB-UEID m-eNB-UE-X2AP-ID %r" % (uid.get("mEnbUeX2apId"),))
        return p
    want = {"type", "mmeUeS1apId", "gummei", "mEnbUeX2apId"}
    if t != "eNB-UEID":
        return ["the eNB node's UE ID is %s, not eNB-UEID" % t]
    p = []
    if set(uid) != want:
        p.append("eNB-UEID members %s, want exactly %s (m-eNB-UE-X2AP-ID present, globalENB-ID absent)" % (
            sorted(uid), sorted(want)))
    if uid.get("gummei") != {"plmn": PLMN, "mmeGroupId": MME_GROUP_ID, "mmeCode": MME_CODE}:
        p.append("eNB-UEID gUMMEI %r, want {%s, %s, %s}" % (uid.get("gummei"), PLMN, MME_GROUP_ID, MME_CODE))
    if not _int(uid.get("mmeUeS1apId")) or not _int(uid.get("mEnbUeX2apId")) or not 0 <= uid["mEnbUeX2apId"] <= 4095:
        p.append("eNB-UEID IDs %r / %r" % (uid.get("mmeUeS1apId"), uid.get("mEnbUeX2apId")))
    return p


def wire_id_tag(kind, uid):
    """The Influx-tag form of a conforming decoded UE ID (None when it does not conform)."""
    if wire_id_problems(kind, uid):
        return None
    if kind == "gnb":
        g = uid["globalEnbId"]
        return "enGnbUeId:%d@%s-%s" % (uid["mEnbUeX2apId"], g["plmn"], g["macroEnbId"])
    return enb_tag(uid["mmeUeS1apId"], uid["mEnbUeX2apId"])


def line_problems(m, node):
    """Shape of one ueContext line (schema ns3-e2-ipc.v1 `ueContext`) of node `node`."""
    if not isinstance(m, dict):
        return ["not an object"]
    p = []
    if m.get("type") != "ueContext":
        p.append("type %r" % (m.get("type"),))
    if m.get("v") != 1 or not _int(m.get("v")):
        p.append("v %r" % (m.get("v"),))
    if m.get("nodeId") != node or not _int(m.get("nodeId")):
        p.append("nodeId %r in the file of node %d" % (m.get("nodeId"), node))
    if not _int(m.get("seq")) or m["seq"] < 0:
        p.append("seq %r" % (m.get("seq"),))
    ues = m.get("ues")
    if not isinstance(ues, list):
        return p + ["ues is not an array"]
    rng = (("imsi", 999999999999999), ("lteRnti", 4095), ("mnCellId", 1048575), ("mmeUeS1apId", 4294967295))
    prev = None
    for u in ues:
        if not isinstance(u, dict) or any(not _int(u.get(k)) or not 0 <= u[k] <= hi for k, hi in rng):
            p.append("ue entry %r outside the schema" % (u,))
            continue
        if prev is not None and u["imsi"] <= prev:
            p.append("ues not sorted by imsi or an imsi twice (%d after %d)" % (u["imsi"], prev))
        prev = u["imsi"]
    return p


def _node_of(regex, name):
    m = regex.match(name)
    assert m is not None, name  # the glob patterns match only these names
    return int(m.group(1))


def load_module(name, path):
    """Load a harness script (hyphenated file name) as a module."""
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, path
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def read_jsonl(path, problems, what):
    out = []
    for n, line in enumerate(open(path), 1):
        if not line.strip():
            continue
        try:
            out.append(json.loads(line))
        except ValueError:
            problems.append("%s line %d is not JSON" % (what, n))
    return out


class UeContextMap:
    """The context lines of one run directory (node kinds from the IPC trace hellos). max_seq keeps only the lines
    with seq <= max_seq (a run blocked at a barrier)."""

    def __init__(self, trace_dir, max_seq=None):
        self.dir = pathlib.Path(trace_dir)
        self.problems, self.kinds, self.lines, self.samples = [], {}, {}, {}
        for p in sorted(self.dir.glob("e2-ipc-trace-*.jsonl")):
            n = _node_of(TRACE_RE, p.name)
            for x in read_jsonl(p, self.problems, p.name):
                if x.get("type") == "hello":
                    self.kinds[n] = x.get("kind")
                elif x.get("type") == "sample" and _int(x.get("seq")):
                    self.samples.setdefault(n, {})[x["seq"]] = [u.get("imsi") for u in x.get("ues") or []]
        ctx_nodes = {_node_of(CTX_RE, p.name): p for p in self.dir.glob("e2-ue-context-*.jsonl")}
        if not self.kinds:
            self.problems.append("no hello in any e2-ipc-trace-*.jsonl of %s" % self.dir)
        for n in sorted(self.kinds):
            if self.kinds[n] not in ("gnb", "enb"):
                self.problems.append("node %d hello kind %r" % (n, self.kinds[n]))
            if n not in ctx_nodes:
                self.problems.append("node %d has a hello but no e2-ue-context-%d.jsonl" % (n, n))
        for n, p in sorted(ctx_nodes.items()):
            if n not in self.kinds:
                self.problems.append("e2-ue-context-%d.jsonl has no IPC trace hello" % n)
            seqs, rows = [], []
            for i, x in enumerate(read_jsonl(p, self.problems, p.name), 1):
                lp = line_problems(x, n)
                if lp:
                    self.problems.append("%s line %d: %s" % (p.name, i, "; ".join(lp)))
                    continue
                if seqs and x["seq"] <= seqs[-1]:
                    self.problems.append("%s line %d: seq %d not above %d" % (p.name, i, x["seq"], seqs[-1]))
                    continue
                if max_seq is not None and x["seq"] > max_seq:
                    continue
                seqs.append(x["seq"])
                rows.append({u["imsi"]: u for u in x["ues"]})
            self.lines[n] = (seqs, rows)

    def ctx(self, node, seq):
        """{imsi: entry} of node's last line with seq <= seq ({} before the first line or for an unknown node)."""
        seqs, rows = self.lines.get(node, ([], []))
        lo, hi = 0, len(seqs)
        while lo < hi:
            mid = (lo + hi) // 2
            if seqs[mid] <= seq:
                lo = mid + 1
            else:
                hi = mid
        return rows[lo - 1] if lo else {}

    def resolve(self, node, seqs, tag):
        """R(node, seqs, tag): the unique IMSI whose ID (in the Influx-tag form of the node's kind) equals tag, else
        None."""
        kind = self.kinds.get(node)
        if kind not in ("gnb", "enb") or not tag_form_ok(kind, tag):
            return None
        hits = {i for s in seqs for i, u in self.ctx(node, s).items() if tag_of(kind, u) == tag}
        return next(iter(hits)) if len(hits) == 1 else None

    def resolve_wire(self, node, seqs, uid):
        """R(node, seqs, decoded wire UE ID); (imsi or None, problems of the ID's form)."""
        kind = self.kinds.get(node)
        if kind not in ("gnb", "enb"):
            return None, ["node %r has no IPC hello kind" % (node,)]
        p = wire_id_problems(kind, uid)
        return (None if p else self.resolve(node, seqs, wire_id_tag(kind, uid))), p

    def identities(self):
        """Conjunct (c): {imsi: (lteRnti, mnCellId, mmeUeS1apId)} over every line of every file, and its problems."""
        seen, p = {}, []
        for n, (_, rows) in sorted(self.lines.items()):
            for row in rows:
                for i, u in row.items():
                    seen.setdefault(i, set()).add((u["lteRnti"], u["mnCellId"], u["mmeUeS1apId"]))
        ids = {}
        for i, s in sorted(seen.items()):
            if len(s) != 1:
                p.append("IMSI %d has %d identities %s" % (i, len(s), sorted(s)))
                continue
            rnti, mn, mme = next(iter(s))
            if mn != MN_CELL:
                p.append("IMSI %d mnCellId %d, want %d (the eNB)" % (i, mn, MN_CELL))
            if mme != i:
                p.append("IMSI %d mmeUeS1apId %d, want the IMSI" % (i, mme))
            ids[i] = (rnti, mn, mme)
        by_key = {}
        for i, (rnti, mn, _) in ids.items():
            by_key.setdefault((rnti, mn), []).append(i)
        p += ["IMSIs %s share (lteRnti, mnCellId) %s" % (v, k) for k, v in sorted(by_key.items()) if len(v) > 1]
        return ids, p

    def sample_coverage(self):
        """Conjunct (b): every IMSI of node n's sample s is in ctx(n, s)."""
        p = []
        for n, smp in sorted(self.samples.items()):
            for s, imsis in sorted(smp.items()):
                miss = [i for i in imsis if i not in self.ctx(n, s)]
                if miss:
                    p.append("node %d sample %d: IMSIs %s not in ctx(n, s)" % (n, s, miss))
        return p


def _extract():
    return load_module("identity_map_extract", HERE.parent.parent / "scripts" / "gates" / "identity-map-extract.py").extract


def expect_map_problems(ids, map_path):
    """The live cross-check against a frozen identity map."""
    p = []
    mp = pathlib.Path(map_path)
    fm = json.load(open(mp))
    want = {int(i): v["mEnbUeX2apId"] for i, v in fm.get("ues", {}).items()}
    if sorted(ids) != sorted(want):
        p.append("IMSI set %s, the frozen map's %s" % (sorted(ids), sorted(want)))
    for i in sorted(set(ids) & set(want)):
        if ids[i][0] != want[i] or ids[i][1] != fm.get("mnCellId"):
            p.append("IMSI %d (lteRnti, mnCellId) %s, the frozen map's (%s, %s)" % (i, ids[i][:2], want[i], fm.get("mnCellId")))
    if fm.get("globalEnbId") != {"plmn": PLMN, "macroEnbId": "%05X" % MN_CELL}:
        p.append("frozen map globalEnbId %r" % (fm.get("globalEnbId"),))
    sums = mp.parent / "SHA256SUMS"
    listed = {}
    if sums.exists():
        for line in sums.read_text().splitlines():
            h, _, name = line.partition("  ")
            listed[os.path.normpath(name)] = h
    got = hashlib.sha256(mp.read_bytes()).hexdigest()
    if listed.get(mp.name) != got:
        p.append("frozen map sha256 %s, %s lists %s" % (got, sums, listed.get(mp.name)))
    return p


def check(trace_dir, pdcp, expect_map=None):
    cm = UeContextMap(trace_dir)
    problems = list(cm.problems)
    problems += cm.sample_coverage()
    ids, p = cm.identities()
    problems += p
    pd, pp = _extract()(pdcp, MN_CELL)
    problems += ["PDCP trace: " + x for x in pp]
    for i, (rnti, _, _) in sorted(ids.items()):
        want = pd.get(str(i), {}).get("mEnbUeX2apId")
        if want != rnti:
            problems.append("IMSI %d lteRnti %d, ns-3's MN PDCP trace RNTI %s" % (i, rnti, want))
    if not ids:
        problems.append("no UE in any context line")
    if expect_map:
        problems += expect_map_problems(ids, expect_map)
    out = {"nodes": {str(n): {"kind": cm.kinds.get(n), "lines": len(cm.lines.get(n, ([], []))[0])}
                     for n in sorted(set(cm.kinds) | set(cm.lines))},
           "identities": {str(i): {"lteRnti": r, "mnCellId": m, "mmeUeS1apId": s} for i, (r, m, s) in sorted(ids.items())},
           "expectMap": expect_map, "problems": problems[:40], "problemCount": len(problems), "pass": not problems}
    return out


def _write(d, name, lines):
    (d / name).write_text("".join(json.dumps(x, separators=(",", ":")) + "\n" for x in lines))


def _fixture(d, ctx_override=None, pdcp_rows=None, sample_ues=None):
    """A healthy run: eNB node 1 and gNB node 2; IMSIs 1, 2 with MN RNTIs 3, 4; IMSI 2 joins gNB 2 at seq 2."""
    d.mkdir(parents=True, exist_ok=True)
    ue = lambda i, r: {"imsi": i, "lteRnti": r, "mnCellId": 1, "mmeUeS1apId": i}
    ctx = {1: [{"type": "ueContext", "v": 1, "nodeId": 1, "seq": 0, "ues": [ue(1, 3), ue(2, 4)]}],
           2: [{"type": "ueContext", "v": 1, "nodeId": 2, "seq": 0, "ues": [ue(1, 3)]},
               {"type": "ueContext", "v": 1, "nodeId": 2, "seq": 2, "ues": [ue(1, 3), ue(2, 4)]}]}
    ctx.update(ctx_override or {})
    ues = sample_ues or {1: lambda s: [1, 2], 2: lambda s: [1] if s < 2 else [1, 2]}
    for n, kind in ((1, "enb"), (2, "gnb")):
        _write(d, "e2-ipc-trace-%d.jsonl" % n, [{"type": "hello", "nodeId": n, "kind": kind}] +
               [{"type": "sample", "nodeId": n, "seq": s, "ues": [{"imsi": i} for i in ues[n](s)]} for s in range(4)])
        if ctx.get(n) is not None:
            _write(d, "e2-ue-context-%d.jsonl" % n, ctx[n])
    rows = pdcp_rows or [(1, 1, 3), (1, 2, 4), (1, 1, 3)]
    (d / "pdcp.txt").write_text("% start\tend\tCellId\tIMSI\tRNTI\tLCID\n" +
                                "".join("0.1\t0.2\t%d\t%d\t%d\t3\n" % r for r in rows))
    return d


def self_test():
    fails = []
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        ue = lambda i, r, mn=1, mme=None: {"imsi": i, "lteRnti": r, "mnCellId": mn, "mmeUeS1apId": i if mme is None else mme}
        line = lambda n, s, ues: {"type": "ueContext", "v": 1, "nodeId": n, "seq": s, "ues": ues}

        def case(name, want, **kw):
            d = _fixture(t / name.replace(" ", "-"), **kw)
            r = check(d, d / "pdcp.txt")
            if r["pass"] != want:
                fails.append("%s: pass %s, want %s %r" % (name, r["pass"], want, r["problems"][:2]))
        case("healthy", True)
        case("a node file missing", False, ctx_override={2: None})
        case("seq not increasing", False, ctx_override={2: [line(2, 2, [ue(1, 3)]), line(2, 2, [ue(1, 3), ue(2, 4)])]})
        case("a sample IMSI absent from ctx", False, sample_ues={1: lambda s: [1, 2], 2: lambda s: [1, 2]})
        case("two RNTIs for one IMSI", False, ctx_override={1: [line(1, 0, [ue(1, 5), ue(2, 4)])]})
        case("two IMSIs on one RNTI", False, ctx_override={1: [line(1, 0, [ue(1, 3), ue(2, 3)])],
                                                           2: [line(2, 0, [ue(1, 3), ue(2, 3)])]},
             pdcp_rows=[(1, 1, 3), (1, 2, 3)])
        case("mmeUeS1apId not the IMSI", False, ctx_override={1: [line(1, 0, [ue(1, 3), ue(2, 4, mme=7)])]})
        case("an RNTI that differs from the PDCP trace", False, pdcp_rows=[(1, 1, 3), (1, 2, 6)])
        case("ues not sorted by imsi", False, ctx_override={1: [line(1, 0, [ue(2, 4), ue(1, 3)])]})
        case("mnCellId not the eNB", False, ctx_override={1: [line(1, 0, [ue(1, 3), ue(2, 4, mn=2)])]})
        # resolution
        cm = UeContextMap(_fixture(t / "resolve"))
        g = lambda r: {"type": "en-gNB-UEID", "mEnbUeX2apId": r, "globalEnbId": {"plmn": PLMN, "macroEnbId": "00001"}}
        e = lambda m, r: {"type": "eNB-UEID", "mmeUeS1apId": m, "gummei": {"plmn": PLMN, "mmeGroupId": "0001", "mmeCode": "01"},
                          "mEnbUeX2apId": r}
        checks = [
            ("an en-gNB-UEID resolves", cm.resolve_wire(2, {2}, g(4)) == (2, [])),
            ("an X2AP ID absent from ctx(n, s) does not resolve", cm.resolve_wire(2, {1}, g(4))[0] is None),
            ("an eNB-UEID resolves", cm.resolve_wire(1, {0}, e(1, 3)) == (1, [])),
            ("a gNB-UEID carrying the IMSI fails", cm.resolve_wire(2, {2}, {"type": "gNB-UEID", "amfUeNgapId": 2})[1] != []),
            ("a wrong globalENB-ID fails", cm.resolve_wire(2, {2}, dict(g(4), globalEnbId={"plmn": PLMN, "macroEnbId": "00002"}))[1] != []),
            ("an optional member fails", cm.resolve_wire(2, {2}, dict(g(4), optional=True))[1] != []),
            ("an eNB-UEID with globalENB-ID fails", cm.resolve_wire(1, {0}, dict(e(1, 3), globalEnbPresent=True))[1] != []),
            ("an eNB-UEID on a gNB node fails", cm.resolve_wire(2, {2}, e(2, 4))[1] != []),
            ("the gNB tag resolves", cm.resolve(2, {3}, "enGnbUeId:4@00F110-00001") == 2),
            ("the eNB tag resolves", cm.resolve(1, {3}, "enbUeId:2@4") == 2),
            ("a tag of the other kind does not resolve", cm.resolve(1, {3}, "enGnbUeId:4@00F110-00001") is None),
            ("a lowercase macro eNB ID tag does not resolve", cm.resolve(2, {3}, "enGnbUeId:4@00f110-00001") is None),
            ("a resolution over several seqs", cm.resolve(2, {0, 1, 2}, "enGnbUeId:4@00F110-00001") == 2),
            ("a barrier hides later lines", UeContextMap(t / "resolve", max_seq=1).resolve(2, {3}, "enGnbUeId:4@00F110-00001") is None),
        ]
        fails += [n for n, ok in checks if not ok]
        # the frozen map cross-check
        d = _fixture(t / "expect")
        fm = {"mnCellId": 1, "globalEnbId": {"plmn": PLMN, "macroEnbId": "00001"}, "ues": {"1": {"mEnbUeX2apId": 3}, "2": {"mEnbUeX2apId": 4}}}
        (d / "map.json").write_text(json.dumps(fm))
        (d / "SHA256SUMS").write_text("%s  ./map.json\n" % hashlib.sha256((d / "map.json").read_bytes()).hexdigest())
        if not check(d, d / "pdcp.txt", d / "map.json")["pass"]:
            fails.append("a run equal to the frozen map")
        (d / "map.json").write_text(json.dumps(dict(fm, ues={"1": {"mEnbUeX2apId": 4}, "2": {"mEnbUeX2apId": 3}})))
        (d / "SHA256SUMS").write_text("%s  ./map.json\n" % hashlib.sha256((d / "map.json").read_bytes()).hexdigest())
        if check(d, d / "pdcp.txt", d / "map.json")["pass"]:
            fails.append("a run whose RNTIs differ from the frozen map")
        (d / "map.json").write_text(json.dumps(fm))
        if check(d, d / "pdcp.txt", d / "map.json")["pass"]:
            fails.append("a frozen map whose sha256 differs from SHA256SUMS")
    for f in fails:
        print("FAIL " + f)
    print("ue-context-map self-test: " + ("ok" if not fails else "%d failure(s)" % len(fails)))
    return 1 if fails else 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--trace-dir", required=True)
    c.add_argument("--pdcp", required=True, help="the run's ns3run/DlE2PdcpStatsLte.txt")
    c.add_argument("--expect-map")
    c.add_argument("--out")
    a = ap.parse_args()
    r = check(a.trace_dir, a.pdcp, a.expect_map)
    if a.out:
        with open(a.out, "w") as f:
            json.dump(r, f, indent=1, sort_keys=True)
            f.write("\n")
    print(json.dumps({"nodes": r["nodes"], "identities": len(r["identities"]), "pass": r["pass"]}, sort_keys=True))
    for p in r["problems"][:20]:
        print("problem: " + p)
    return 0 if r["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())

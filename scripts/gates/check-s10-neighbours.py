#!/usr/bin/env python3
"""check-s10-neighbours.py: the 8-neighbour cap of the KPM UE report against ns-3's full measurement map (AC15).

  check-s10-neighbours.py RECORDS_JSONL --map metric-map.v1.json --trace-dir TRACE_DIR --sinr MmWaveSinrTime.txt
                          --out FILE [--max-neigh 8] [--guard-ms 1] [--expect-cells 10,11]
  check-s10-neighbours.py --self-test

RECORDS_JSONL is `kpimon-decode-harness --records` over the capture's indication lines (decoded wire bytes; the same
decoder and record layout as p12-records-check.py). A Format 2 UE block is UE j's records of one measData item
(metric-major: metric r of UE j at r * nUe + j); a block that is all noValue is skipped. Its node, seq and IMSI are its
own ns3.nodeId, ns3.seq and ns3.imsi records; the node kind comes from the node's IPC trace hello, the record names
from the metric map's ue list of that kind (by order). The neighbour slots are the rows named ns3.l3.nbr<k>.cellId.

  decoded(g, s, i)  = the number of neighbour slots of the block that carry a value. Its values must be distinct and
                      none may be g (ns-3 lists each measured cell once and skips the serving cell,
                      mmwave-enb-net-device.cc:990-1023).
  measured(g, s, i) = the distinct cellIds other than g in ns-3's MmWaveSinrTime.txt rows of IMSI i (`time imsi
                      cellId sinrDb`, one row per LteEnbRrc NotifyMmWaveSinr, mmwave-bearer-stats-connector.cc:515-531;
                      the same trace source feeds the gNB's m_l3sinrMap, mmwave-enb-net-device.cc:300-303,349-372)
                      with time in [t_s - T + guard, t_s - guard], t_s = the sample's simTimeNs and T = the hello's
                      periodNs. Counted only when i is in node g's IPC sample at s - 1 and at s (so the UE was in g's
                      UE map over the window); otherwise the tick is not judged. The gNB's map is never cleared, so
                      this is a lower bound of what ns-3 held when it built sample s: measured > 8 implies at least 9
                      measured neighbours, which ns-3 caps at E2SM_REPORT_MAX_NEIGH = 8 (mmwave-enb-net-device.h:71).

Pass (exit 0) iff the map's gNB ue list carries exactly --max-neigh neighbour slots; at least one judged (g, s, i)
has measured > --max-neigh; every such tick decodes exactly --max-neigh; no block decodes more than --max-neigh; every
decoded list is well formed; every indication decodes RC_OK; the SINR trace parses. --expect-cells adds the
informational cellIdsGe10Pass: the decoded cell IDs >= 10 (Format 1 and 2 ns3.nodeId, ns3.l3.servCellId and the
neighbour cellIds) include every listed cell; it is written to FILE and judged by the gate, not by this exit code.
"""
import argparse
import bisect
import json
import pathlib
import re
import sys
import tempfile

NBR_RE = re.compile(r"^ns3\.l3\.nbr([0-9]+)\.cellId$")
SINR_HEADER = "Time IMSI CellId SINR[dB]"


def value(rec):
    """An INTEGER record's value, else None (REAL, noValue)."""
    return rec.get("v") if isinstance(rec, dict) and rec.get("t") == "int" else None


def layout(map_path):
    """{(kind, list): [kpm names by order]} of the metric map."""
    rows = json.load(open(map_path))["rows"]
    out = {}
    for kind in ("gnb", "enb"):
        for lst in ("cell", "ue"):
            out[(kind, lst)] = [r["kpm"] for r in sorted((r for r in rows if r["kind"] == kind and r["list"] == lst),
                                                         key=lambda r: r["order"])]
    return out


def nbr_slots(names):
    """[(k, index)] of the ns3.l3.nbr<k>.cellId names, by k."""
    return sorted((int(m.group(1)), i) for i, n in enumerate(names) for m in [NBR_RE.match(n)] if m)


def load_traces(trace_dir, problems):
    """{node: {"kind", "periodNs", "samples": {seq: (simTimeNs, {imsi})}}} from the IPC traces."""
    nodes = {}
    for p in sorted(pathlib.Path(trace_dir).glob("e2-ipc-trace-*.jsonl")):
        hello, samples = None, {}
        for n, line in enumerate(open(p), 1):
            if not line.strip():
                continue
            try:
                m = json.loads(line)
            except ValueError:
                problems.append("%s line %d is not JSON" % (p.name, n))
                continue
            if m.get("type") == "hello":
                hello = m
            elif m.get("type") == "sample":
                samples[m["seq"]] = (m["simTimeNs"], {u["imsi"] for u in m.get("ues") or []})
        if hello is None:
            problems.append("%s has no hello" % p.name)
            continue
        nodes[hello["nodeId"]] = {"kind": hello.get("kind"), "periodNs": hello.get("periodNs"), "samples": samples}
    if not nodes:
        problems.append("no IPC trace in %s" % trace_dir)
    return nodes


def load_sinr(path, problems):
    """{imsi: [(time s, cellId)] sorted}; the trace's header line is the only non-numeric line allowed."""
    by, n = {}, 0
    try:
        f = open(path)
    except OSError as ex:
        problems.append("SINR trace: %s" % ex)
        return by, 0
    with f:
        for k, line in enumerate(f, 1):
            s = line.strip()
            if not s or s == SINR_HEADER:
                continue
            c = s.split()
            try:
                if len(c) != 4:
                    raise ValueError(s)
                t, i, cell = float(c[0]), int(c[1]), int(c[2])
                float(c[3])
            except ValueError:
                problems.append("SINR trace line %d is not `time imsi cellId sinrDb`: %r" % (k, s[:80]))
                continue
            by.setdefault(i, []).append((t, cell))
            n += 1
    for v in by.values():
        v.sort()
    if not n:
        problems.append("SINR trace %s has no row" % path)
    return by, n


def measured(sinr, imsi, node, lo, hi):
    """The distinct cellIds other than node in IMSI's rows with lo <= time <= hi."""
    rows = sinr.get(imsi, [])
    a, b = bisect.bisect_left(rows, (lo, -1)), bisect.bisect_right(rows, (hi, 1 << 62))
    return {c for _, c in rows[a:b] if c != node}


def blocks(records_path, lay, nodes, problems):
    """(Format 2 UE blocks [(node, seq, imsi, [slot values], servCellId)], Format 1 nodeIds, indications)."""
    out, f1, n = [], set(), 0
    for line in open(records_path):
        if not line.strip():
            continue
        x = json.loads(line)
        n += 1
        tag = x.get("id")
        if x.get("hdr_code") != "RC_OK" or x.get("msg_code") != "RC_OK":
            problems.append("%s: decode %s/%s" % (tag, x.get("hdr_code"), x.get("msg_code")))
            continue
        if x.get("msg_format") == 1:
            v = value((x.get("records") or [None])[0])
            if v is None:
                problems.append("%s: Format 1 without a nodeId record" % tag)
            else:
                f1.add(v)
            continue
        if x.get("msg_format") != 2:
            problems.append("%s: message format %r" % (tag, x.get("msg_format")))
            continue
        items, u = x.get("itemRecords"), x.get("ueIdsPerItem") or 0
        widths = {len(r) for r in items or []}
        if u <= 0 or not items or len(widths) != 1 or next(iter(widths)) % u:
            problems.append("%s: Format 2 item widths %s for %d UEs" % (tag, sorted(widths), u))
            continue
        m = next(iter(widths)) // u
        if x.get("condItems") is not None and x["condItems"] != m:
            problems.append("%s: %s measCondUEidList items for %d records per UE" % (tag, x["condItems"], m))
            continue
        for item in items:
            for j in range(u):
                b = [item[r * u + j] for r in range(m)]
                if all(r.get("t") == "none" for r in b):
                    continue
                node = value(b[0])
                kind = (nodes.get(node) or {}).get("kind")
                names = lay.get((kind, "ue"), [])
                if len(names) != m or names[:1] != ["ns3.nodeId"]:
                    problems.append("%s: UE block of node %r (kind %r): %d records, the map's ue list %d" % (
                        tag, node, kind, m, len(names)))
                    continue
                seq, imsi = value(b[names.index("ns3.seq")]), value(b[names.index("ns3.imsi")])
                slots = [value(b[i]) for _, i in nbr_slots(names)]
                serv = value(b[names.index("ns3.l3.servCellId")]) if "ns3.l3.servCellId" in names else None
                out.append((node, seq, imsi, slots, serv, kind))
    if not n:
        problems.append("no indication in %s" % records_path)
    return out, f1, n


def judge(records_path, map_path, trace_dir, sinr_path, max_neigh=8, guard_ms=1.0, expect_cells=()):
    problems = []
    lay = layout(map_path)
    nslots = len(nbr_slots(lay[("gnb", "ue")]))
    if nslots != max_neigh:
        problems.append("the map's gNB ue list carries %d neighbour slots, not %d" % (nslots, max_neigh))
    nodes = load_traces(trace_dir, problems)
    sinr, sinr_rows = load_sinr(sinr_path, problems)
    bl, f1, n_ind = blocks(records_path, lay, nodes, problems)
    guard = guard_ms / 1e3
    judged = ticks = 0
    decoded_at_ticks, hist_dec, hist_meas, over, short, malformed, examples = set(), {}, {}, 0, 0, 0, []
    cells = {"nodeId": {c for c in f1 if c >= 10}, "servCellId": set(), "nbrCellId": set()}
    for node, seq, imsi, slots, serv, kind in bl:
        cells["nodeId"] |= {node} if node is not None and node >= 10 else set()
        cells["servCellId"] |= {serv} if serv is not None and serv >= 10 else set()
        vals = [v for v in slots if v is not None]
        cells["nbrCellId"] |= {v for v in vals if v >= 10}
        if kind != "gnb":
            continue
        dec = len(vals)
        hist_dec[dec] = hist_dec.get(dec, 0) + 1
        if dec > max_neigh:
            over += 1
            problems.append("node %s seq %s IMSI %s decodes %d neighbours (> %d)" % (node, seq, imsi, dec, max_neigh))
        if len(set(vals)) != dec or node in vals:
            malformed += 1
            problems.append("node %s seq %s IMSI %s: decoded neighbour cells %r repeat a cell or name the serving node" % (
                node, seq, imsi, vals))
        smp = nodes[node]["samples"]
        if seq not in smp or seq - 1 not in smp or imsi not in smp[seq][1] or imsi not in smp[seq - 1][1]:
            continue
        period = nodes[node]["periodNs"] / 1e9
        t = smp[seq][0] / 1e9
        meas = measured(sinr, imsi, node, t - period + guard, t - guard)
        judged += 1
        hist_meas[len(meas)] = hist_meas.get(len(meas), 0) + 1
        if len(meas) > max_neigh:
            ticks += 1
            decoded_at_ticks.add(dec)
            if dec != max_neigh:
                short += 1
                if len(examples) < 5:
                    examples.append({"node": node, "seq": seq, "imsi": imsi, "measured": sorted(meas), "decoded": vals})
    if short:
        problems.append("%d tick(s) with more than %d measured cells decode fewer than %d neighbours, e.g. %s" % (
            short, max_neigh, max_neigh, json.dumps(examples[:2])))
    if not ticks:
        problems.append("non-vacuity: no judged (UE, period) has more than %d measured cells (judged %d)" % (max_neigh, judged))
    union = set().union(*cells.values())
    res = {"indications": n_ind, "ueBlocks": len(bl), "sinrRows": sinr_rows, "mapNeighbourSlots": nslots,
           "ueTicksJudged": judged, "ueTicksWithMoreThan8Measured": ticks,
           "decodedNeighbours": sorted(decoded_at_ticks), "maxDecodedNeighbours": max(hist_dec) if hist_dec else None,
           "decodedHistogram": {str(k): v for k, v in sorted(hist_dec.items())},
           "measuredHistogram": {str(k): v for k, v in sorted(hist_meas.items())},
           "ticksDecodingShort": short, "blocksDecodingOverCap": over, "malformedLists": malformed,
           "cellIdsGe10InKpm": sorted(union), "cellIdsGe10BySource": {k: sorted(v) for k, v in cells.items()},
           "expectCells": sorted(expect_cells), "cellIdsGe10Pass": set(expect_cells) <= union,
           "rule": "measured = distinct cellIds != serving in MmWaveSinrTime.txt rows of the IMSI in "
                   "[t_s - T + %g ms, t_s - %g ms], UE in the node's IPC samples s - 1 and s" % (guard_ms, guard_ms),
           "problems": problems[:20], "nProblems": len(problems), "pass": not problems}
    return res


################################################################################
# self-test
################################################################################
def _map(nslots=8):
    rows = []
    for kind, lst, names in (("gnb", "cell", ["ns3.nodeId", "x", "ns3.seq"]), ("enb", "cell", ["ns3.nodeId", "x", "ns3.seq"]),
                             ("enb", "ue", ["ns3.nodeId", "x", "ns3.seq", "ns3.imsi", "ns3.l3.servCellId"])):
        rows += [{"kind": kind, "list": lst, "order": k + 1, "kpm": n} for k, n in enumerate(names)]
    gue = ["ns3.nodeId", "x", "ns3.seq", "ns3.imsi", "ns3.l3.servCellId"]
    for k in range(1, nslots + 1):
        gue += ["ns3.l3.nbr%d.cellId" % k, "ns3.l3.nbr%d.sinrDb" % k]
    rows += [{"kind": "gnb", "list": "ue", "order": k + 1, "kpm": n} for k, n in enumerate(gue)]
    return {"rows": rows}, gue


def _fixture(d, sinr_cells, decoded, nslots=8, ue_seqs=(0, 1, 2, 3), extra_rows=(), node=2, f1_nodes=(2, 10, 11)):
    """One gNB node `node` (and the eNB 1) with IMSI 1 in samples ue_seqs; SINR rows of IMSI 1 every 10 ms over 0..0.4 s
    from sinr_cells; Format 2 blocks of IMSI 1 at node for seqs 1..3 with the decoded neighbour list; Format 1 from
    f1_nodes."""
    d.mkdir(parents=True, exist_ok=True)
    mp, gue = _map(nslots)
    (d / "map.json").write_text(json.dumps(mp))
    tr = d / "trace"
    tr.mkdir(exist_ok=True)
    for n, kind in ((1, "enb"), (node, "gnb")):
        lines = [{"type": "hello", "nodeId": n, "kind": kind, "periodNs": 100_000_000}]
        lines += [{"type": "sample", "nodeId": n, "seq": s, "simTimeNs": s * 100_000_000,
                   "ues": [{"imsi": 1}] if (kind == "enb" or s in ue_seqs) else []} for s in range(4)]
        (tr / ("e2-ipc-trace-%d.jsonl" % n)).write_text("".join(json.dumps(x) + "\n" for x in lines))
    rows = ["%g 1 %d %.3f" % (k / 100, c, 1.5) for k in range(0, 40) for c in sinr_cells]
    rows += list(extra_rows)
    (d / "sinr.txt").write_text("\n".join(rows) + "\n")
    recs = []
    for f in f1_nodes:
        recs.append({"id": "c%d" % f, "hdr_code": "RC_OK", "msg_code": "RC_OK", "msg_format": 1,
                     "records": [{"t": "int", "v": f}, {"t": "none"}, {"t": "int", "v": 1}]})
    for s in (1, 2, 3):
        b = []
        for name in gue:
            k = NBR_RE.match(name)
            if name == "ns3.nodeId":
                b.append({"t": "int", "v": node})
            elif name == "ns3.seq":
                b.append({"t": "int", "v": s})
            elif name == "ns3.imsi":
                b.append({"t": "int", "v": 1})
            elif name == "ns3.l3.servCellId":
                b.append({"t": "int", "v": node})
            elif k and int(k.group(1)) <= len(decoded):
                b.append({"t": "int", "v": decoded[int(k.group(1)) - 1]})
            else:
                b.append({"t": "none"})
        recs.append({"id": "u%d" % s, "hdr_code": "RC_OK", "msg_code": "RC_OK", "msg_format": 2, "measDataItems": 1,
                     "ueIdsPerItem": 1, "condItems": len(gue), "records": b, "itemRecords": [b]})
    (d / "records.jsonl").write_text("".join(json.dumps(r) + "\n" for r in recs))
    return d


def self_test():
    fails = []
    ten = list(range(2, 12))              # 10 en-gNB cells: 9 neighbours of cell 2
    best8 = [3, 4, 5, 6, 7, 8, 9, 10]

    def case(name, want, expect_cells=(10, 11), max_neigh=8, cells_pass=None, **kw):
        with tempfile.TemporaryDirectory() as t:
            d = _fixture(pathlib.Path(t), **kw)
            r = judge(d / "records.jsonl", d / "map.json", d / "trace", d / "sinr.txt", max_neigh, 1.0, expect_cells)
        if r["pass"] != want:
            fails.append("%s: pass %s, want %s %r" % (name, r["pass"], want, r["problems"][:2]))
        if cells_pass is not None and r["cellIdsGe10Pass"] != cells_pass:
            fails.append("%s: cellIdsGe10Pass %s, want %s" % (name, r["cellIdsGe10Pass"], cells_pass))
        return r

    r = case("10 cells measured, 8 decoded", True, cells_pass=True, sinr_cells=ten, decoded=best8)
    if r["ueTicksWithMoreThan8Measured"] != 3 or r["decodedNeighbours"] != [8] or r["cellIdsGe10InKpm"] != [10, 11]:
        fails.append("healthy facts %r" % {k: r[k] for k in ("ueTicksWithMoreThan8Measured", "decodedNeighbours", "cellIdsGe10InKpm")})
    case("non-vacuity: 8 cells measured (7 neighbours) is never more than 8", False,
         sinr_cells=list(range(2, 10)), decoded=best8[:7])
    case("more than 8 measured but 7 decoded", False, sinr_cells=ten, decoded=best8[:7])
    case("a 9-slot map decoding 9 neighbours", False, nslots=9, max_neigh=8, sinr_cells=ten, decoded=best8 + [11])
    case("a decoded list naming the serving cell", False, sinr_cells=ten, decoded=[2] + best8[1:])
    case("a decoded list repeating a cell", False, sinr_cells=ten, decoded=best8[:7] + [3])
    case("the UE never in the node's samples s - 1 and s: no tick judged", False, ue_seqs=(1, 3), sinr_cells=ten, decoded=best8)
    r = case("UE present at s - 1 and s only from seq 2", True, ue_seqs=(1, 2, 3), sinr_cells=ten, decoded=best8)
    if r["ueTicksJudged"] != 2:
        fails.append("membership rule judged %d ticks, want 2 (seqs 2, 3)" % r["ueTicksJudged"])
    # the 9th neighbour only exactly at t_s or inside the guard is not counted
    edge = ["%g 1 11 1.0" % t for t in (0.1, 0.2, 0.3, 0.0995)]
    case("a cell seen only at the window edges does not count", False, sinr_cells=list(range(2, 11)), decoded=best8, extra_rows=edge)
    case("a malformed SINR row", False, sinr_cells=ten, decoded=best8, extra_rows=["0.1 1 x 2"])
    # best8 names cell 10 as a neighbour, but no decoded cell ID is 11
    case("cell 11 missing from the decoded KPM", True, cells_pass=False, sinr_cells=ten, decoded=best8, f1_nodes=(2,))
    for f in fails:
        print("FAIL " + f)
    print("check-s10-neighbours self-test: " + ("ok" if not fails else "%d failure(s)" % len(fails)))
    return 1 if fails else 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("records")
    ap.add_argument("--map", required=True)
    ap.add_argument("--trace-dir", required=True)
    ap.add_argument("--sinr", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-neigh", type=int, default=8)
    ap.add_argument("--guard-ms", type=float, default=1.0)
    ap.add_argument("--expect-cells", default="")
    a = ap.parse_args()
    exp = [int(x) for x in a.expect_cells.split(",") if x.strip()]
    r = judge(a.records, a.map, a.trace_dir, a.sinr, a.max_neigh, a.guard_ms, exp)
    with open(a.out, "w") as f:
        json.dump(r, f, indent=1, sort_keys=True)
    print(json.dumps({k: r[k] for k in ("ueTicksJudged", "ueTicksWithMoreThan8Measured", "decodedNeighbours",
                                        "maxDecodedNeighbours", "cellIdsGe10InKpm", "pass")}, sort_keys=True))
    for p in r["problems"][:10]:
        print("problem: " + p)
    return 0 if r["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())

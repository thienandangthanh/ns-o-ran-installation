#!/usr/bin/env python3
"""check-pdcp-volume-totals.py: judge the en-gNB cells' PDCP SDU volume counters against the PDCP audit.

A UL-on ns-3 run (scenario-zero, enableUlTraffic) prints the audit v2 on stdout. Every `N4AUDIT` line is one of
six forms, tokens separated by single spaces, every number a base-10 non-negative integer without leading zeros:
  N4AUDIT v2 hdr=<H> class=<C>                                            the MC DRB's PDCP header size and class
  N4AUDIT dltx <tNs> <nodeId> <cellId> <imsi> <lcid> <pduBytes> <leg>     a DL PDCP PDU the MN submits
  N4AUDIT ulrx <tNs> <nodeId> <cellId> <imsi> <lcid> <pduBytes> <delayNs> <leg>   a UL PDCP PDU the MN receives
  N4AUDIT x2dl <tNs> <nodeId> <cellId> <srcCellId> <teid> <pduBytes>      a DL PDCP PDU an en-gNB cell receives on X2-U
  N4AUDIT x2ul <tNs> <nodeId> <cellId> <dstCellId> <teid> <pduBytes>      a UL PDCP PDU an en-gNB cell sends on X2-U
  N4AUDIT end connected=<n> present=<m> missing=<k>
`leg` is 0 for the LTE leg and the en-gNB cell for the X2 leg; pduBytes is the PDCP PDU (header included, GTP-U
excluded); the audit cellId equals the IPC sample nodeId. The MN cells M are the cellIds of the dltx and ulrx lines,
the gNB cells G the expected gNB nodes; an x2dl whose source is in G is forwarded en-gNB to en-gNB.

The gNB IPC samples (cell.cuUp, integer kbit per period) carry DRB.PdcpSduVolumeX2DL/X2UL (3GPP TS 28.552
§5.1.2.1.1.2, §5.1.2.1.2.2), counted at the en-gNB's own X2-U boundary, and DRB.PdcpSduVolumeDL/UL, which are 0
because the en-gNB hosts no DRB PDCP entity. Pass iff:
  A0 sample completeness: the gNB traces are exactly the expected gNB nodes (2 .. 1 + nMmWaveEnbNodes of the
     rung-config scenario; node 1 is the eNB) and each holds every seq 0 .. N-1 once, N = simTime / the hello
     periodNs (a missing cell or a truncated tail fails instead of becoming residual bits), read on its trace's
     cadence: simTimeNs(seq k) == simTimeNs(seq 0) + k * that trace's hello periodNs, with 0 < simTimeNs(seq 0) <
     periodNs (collapsed or shifted read instants fail instead of moving events into residual; offCadence); every
     gNB hello's periodNs is a positive JSON int, judged per hello line before any deduplication (invalidHelloPeriods);
  A1 audit form: every N4AUDIT line matches exactly one of the six forms (malformedAuditLines == 0); exactly one
     header line, `v2` with hdr equal to the NR data PDU header with a 12-bit SN (2 octets, 3GPP TS 38.323
     §6.2.2.2) and class ns3::NrPdcpHeader (any other version fails); exactly one end line, with connected ==
     present and missing == 0; every dltx, ulrx, x2dl and x2ul event lies in the run, 0 < tNs <= T with T the run's
     stop time (outOfRunEvents == 0; such an event is no audit of this run, and A4 does not count it);
  A2 one RRC per IMSI: every dltx/ulrx event of an IMSI is on one node;
  A3 no UL PDU at two RRCs: no UL identity (imsi, tNs - delayNs) on two nodes (delayNs == 0 has no identity:
     reported, not judged);
  A4 accounting, per cell with no pooling: for each gNB sample (g, s) read at t(g, s), truth = the sum of
     8 * (pduBytes - H) over the x2dl (for X2DL) or x2ul (for X2UL) lines of cellId g with t(g, s-1) < tNs <
     t(g, s), t(g, -1) = -inf, every line whatever its LCID; |1000 * counter - truth| <= 500 bits per sample and
     key, and per read instant the sum over gNB cells is within 1 kbit per cell; both counters are JSON ints; an x2
     event at a read instant of its cell is a tie and fails; x2 events in (their cell's last read, T] are residual,
     allowed only when that read is the run's final read instant; every cell reference is known (badCellRefs == 0):
     dltx/ulrx at a cell outside G with leg in {0} | G, x2dl at a cell of G from a source in M | G other than
     itself, x2ul from a cell of G to a cell of M;
  A5 every event has pduBytes >= H + 1 and every UL lcid-3 SDU is larger than 40 bytes;
  A6 non-vacuity: >= 1 lcid-3 dltx on the LTE leg, >= 1 lcid-3 dltx on an X2 leg, and >= 1 x2ul;
  A7 every gNB sample carries DRB.PdcpSduVolumeDL and DRB.PdcpSduVolumeUL as the int 0;
  A8 X2 conservation, inclusion form, per (MN cell m, gNB cell g) over multisets of pduBytes, T = the run's stop:
     x2dl(g, src m) is included in dltx(m, leg g), and dltx(m, leg g, tNs <= T - 2 ms) in x2dl(g, src m);
     ulrx(m, leg g) is included in x2ul(g, dst m), and x2ul(g, dst m, tNs <= T - 2 ms) in ulrx(m, leg g); the
     sender events after T - 2 ms (in flight at the stop or not) are reported as lateSenderEvents.
Never compensates a double count (no dedupe, factor or wider tolerance).

  check-pdcp-volume-totals.py RUN_DIR --sim-time-s S
        (RUN_DIR/ns3run/stdout.txt, RUN_DIR/trace/*.jsonl; nMmWaveEnbNodes from rung-config.json or $RUNG_CONFIG)
  check-pdcp-volume-totals.py --self-test      (the fixtures in check-pdcp-volume-totals-fixtures.py)
"""
import bisect
import collections
import importlib.util
import json
import os
import pathlib
import re
import sys

HDR = 2  # octets: the MC DRB's NR PDCP data PDU header, 12-bit SN (D/C, 3 R, SN), 3GPP TS 38.323 §6.2.2.2
HDR_CLASS = "ns3::NrPdcpHeader"  # the header class the MC DRB's PDCP entity writes, named by the audit header line
X2_KEYS = {"ul": "DRB.PdcpSduVolumeX2UL", "dl": "DRB.PdcpSduVolumeX2DL"}
OWN_KEYS = {"ul": "DRB.PdcpSduVolumeUL", "dl": "DRB.PdcpSduVolumeDL"}
LCID = 3
LATE_NS = 2_000_000  # sender events after T - 2 ms may still be in flight at the stop (X2-U delay 1 ms)

_N = r"(0|[1-9][0-9]*)"
FORMS = {  # line form -> (full-line pattern, field names of its numbers)
    "hdr": (re.compile(rf"N4AUDIT (v2) hdr={_N} class=(\S+)"), None),
    "dltx": (re.compile(rf"N4AUDIT dltx {_N} {_N} {_N} {_N} {_N} {_N} {_N}"),
             ("t", "node", "cell", "imsi", "lcid", "bytes", "leg")),
    "ulrx": (re.compile(rf"N4AUDIT ulrx {_N} {_N} {_N} {_N} {_N} {_N} {_N} {_N}"),
             ("t", "node", "cell", "imsi", "lcid", "bytes", "delay", "leg")),
    "x2dl": (re.compile(rf"N4AUDIT x2dl {_N} {_N} {_N} {_N} {_N} {_N}"), ("t", "node", "cell", "peer", "teid", "bytes")),
    "x2ul": (re.compile(rf"N4AUDIT x2ul {_N} {_N} {_N} {_N} {_N} {_N}"), ("t", "node", "cell", "peer", "teid", "bytes")),
    "end": (re.compile(rf"N4AUDIT end connected={_N} present={_N} missing={_N}"), ("connected", "present", "missing")),
}
VERSION = re.compile(r"N4AUDIT (v[0-9]+) ")


def bits(e):
    return 8 * (e["bytes"] - HDR)


def load_audit(path):
    """The run's N4AUDIT lines parsed strictly: {"headers": [(version, size, class)], "ends": [dict],
    "ev": {form: [event]}, "malformed": n, "version": the first version token seen}."""
    a = {"headers": [], "ends": [], "ev": {k: [] for k in ("dltx", "ulrx", "x2dl", "x2ul")}, "malformed": 0,
         "version": None}
    for line in pathlib.Path(path).read_text(errors="replace").splitlines():
        if not line.startswith("N4AUDIT"):
            continue
        if a["version"] is None and VERSION.match(line):
            a["version"] = VERSION.match(line).group(1)
        hits = [(k, m) for k, (rx, _) in FORMS.items() for m in [rx.fullmatch(line)] if m]
        if len(hits) != 1:
            a["malformed"] += 1
            continue
        (form, m), = hits
        if form == "hdr":
            a["headers"].append((m.group(1), int(m.group(2)), m.group(3)))
        elif form == "end":
            a["ends"].append(dict(zip(FORMS["end"][1], map(int, m.groups()))))
        else:
            a["ev"][form].append(dict(zip(FORMS[form][1], map(int, m.groups()))))
    return a


def valid_period(p):
    """A hello periodNs: a positive JSON int (not a bool, not a float of the same value)."""
    return type(p) is int and p > 0


def load_gnb_samples(trace_dir, hellos=None):
    """The gNB samples of every IPC trace; each gNB hello line, unmerged, is appended to `hellos` when given."""
    out = []
    for p in sorted(pathlib.Path(trace_dir).glob("e2-ipc-trace-*.jsonl")):
        kind = None
        for line in p.read_text().splitlines():
            if not line.strip():
                continue
            m = json.loads(line)
            if m.get("type") == "hello":
                kind, period = m.get("kind"), m.get("periodNs")
                if hellos is not None and kind == "gnb":
                    hellos.append({"trace": p.name, "periodNs": period})
            elif m.get("type") == "sample" and kind == "gnb":
                cu = (m.get("cell") or {}).get("cuUp") or {}
                out.append({"node": m["nodeId"], "seq": m["seq"], "t": m["simTimeNs"], "period": period,
                            "x2": {d: cu.get(k) for d, k in X2_KEYS.items()},
                            "own": {d: cu.get(k) for d, k in OWN_KEYS.items()}})
    return out


def off_cadence(samples):
    """Per gNB node whose reads are off its trace's cadence: its periodNs, its seq-0 instant and the number of samples
    not at seq-0 instant + seq * periodNs (every sample, when the period or the seq-0 instant is not valid)."""
    by_node = collections.defaultdict(list)
    for s in samples:
        by_node[s["node"]].append(s)
    out = {}
    for n, ss in sorted(by_node.items()):
        periods = {s["period"] for s in ss}
        period = next(iter(periods)) if len(periods) == 1 else None
        t0s = {s["t"] for s in ss if s["seq"] == 0}
        t0 = next(iter(t0s)) if len(t0s) == 1 else None
        ok = type(period) is int and period > 0 and type(t0) is int and 0 < t0 < period
        off = sum(not ok or type(s["seq"]) is not int or type(s["t"]) is not int or s["t"] != t0 + s["seq"] * period
                  for s in ss)
        if off:
            out[str(n)] = {"periodNs": period, "seq0Ns": t0, "offCadenceSamples": off}
    return out


def multiset_excess(a, b):
    """The number of elements of multiset a not covered by multiset b."""
    return sum((a - b).values())


def judge(run, gnb_nodes, n_seq, stop_ns):
    run = pathlib.Path(run)
    a = load_audit(run / "ns3run" / "stdout.txt")
    dltx, ulrx, x2dl, x2ul = (a["ev"][k] for k in ("dltx", "ulrx", "x2dl", "x2ul"))
    mn, x2 = dltx + ulrx, x2dl + x2ul
    hellos = []
    samples = load_gnb_samples(run / "trace", hellos)
    hdr = a["headers"][0] if len(a["headers"]) == 1 else (None, None, None)
    end = a["ends"][0] if len(a["ends"]) == 1 else None
    v = {"auditVersion": a["version"], "hdr": hdr[1], "hdrClass": hdr[2], "headerLines": len(a["headers"]),
         "end": end, "endLines": len(a["ends"]), "malformedAuditLines": a["malformed"], "mnEvents": len(mn),
         "x2Events": len(x2), "x2ulEvents": len(x2ul), "gnbSamples": len(samples), "stopNs": stop_ns}

    # A0
    seqs = collections.defaultdict(list)
    for s in samples:
        seqs[s["node"]].append(s["seq"])
    want = list(range(n_seq))
    v["expectedGnbNodes"], v["expectedSeqsPerNode"], v["gnbNodes"] = sorted(gnb_nodes), n_seq, sorted(seqs)
    v["incompleteNodes"] = {str(n): {"missing": len(set(want) - set(seqs.get(n, []))),
                                     "extraOrDuplicate": len(seqs.get(n, [])) - len(set(seqs.get(n, [])) & set(want))}
                            for n in sorted(set(gnb_nodes) | set(seqs)) if sorted(seqs.get(n, [])) != want}
    v["offCadence"] = off_cadence(samples)
    v["invalidHelloPeriods"] = [h for h in hellos if not valid_period(h["periodNs"])]
    v["a0"] = n_seq > 0 and set(seqs) == set(gnb_nodes) and not v["incompleteNodes"] and not v["offCadence"] \
        and not v["invalidHelloPeriods"]

    # A1
    in_run = [e for e in mn + x2 if 0 < e["t"] <= stop_ns]
    v["outOfRunEvents"] = len(mn) + len(x2) - len(in_run)
    v["a1"] = a["malformed"] == 0 and hdr == ("v2", HDR, HDR_CLASS) and end is not None and \
        end["missing"] == 0 and end["connected"] == end["present"] and v["outOfRunEvents"] == 0

    # A2, A3 over the MN's events
    nodes = collections.defaultdict(set)
    ul_id = collections.defaultdict(set)
    no_id = 0
    for e in mn:
        nodes[e["imsi"]].add(e["node"])
    for e in ulrx:
        if e["delay"] == 0:
            no_id += 1
        else:
            ul_id[(e["imsi"], e["t"] - e["delay"])].add(e["node"])
    v["rrcNodesPerImsi"] = {str(i): sorted(n) for i, n in sorted(nodes.items())}
    v["a2"] = bool(mn) and all(len(n) == 1 for n in nodes.values())
    v["twoRrcIdentities"] = sum(len(n) > 1 for n in ul_id.values())
    v["noIdentityEvents"] = no_id
    v["a3"] = v["twoRrcIdentities"] == 0
    same = collections.Counter((e["node"], e["imsi"], e["t"] - e["delay"]) for e in ulrx if e["delay"])
    v["sameRrcDuplicates"] = sum(c - 1 for c in same.values() if c > 1)

    # A5
    v["a5"] = bool(mn) and all(e["bytes"] >= HDR + 1 for e in mn + x2) and \
        all(e["bytes"] - HDR > 40 for e in ulrx if e["lcid"] == LCID)

    # cell classification
    G = set(gnb_nodes)
    M = {e["cell"] for e in mn}
    bad = sum(e["cell"] in G or not (e["leg"] == 0 or e["leg"] in G) for e in mn)
    bad += sum(e["cell"] not in G or e["peer"] == e["cell"] or e["peer"] not in M | G for e in x2dl)
    bad += sum(e["cell"] not in G or e["peer"] not in M for e in x2ul)
    v["badCellRefs"] = bad
    fwd = [e for e in x2dl if e["peer"] in G and e["peer"] != e["cell"] and e["cell"] in G]
    v["forwardedEvents"], v["forwardedBits"] = len(fwd), sum(bits(e) for e in fwd)

    # A4: per cell, its own read instants
    reads = collections.defaultdict(list)
    for i, s in enumerate(samples):
        reads[s["node"]].append((s["t"], i))
    for rl in reads.values():
        rl.sort()
    final_t = max((s["t"] for s in samples), default=None)
    truth = [{"ul": 0, "dl": 0} for _ in samples]
    ties = residual = residual_early = 0
    for d, es in (("dl", x2dl), ("ul", x2ul)):
        for e in es:
            if not 0 < e["t"] <= stop_ns:
                continue   # outside the run: judged by A1, never residual
            rl = reads.get(e["cell"], [])
            times = [t for t, _ in rl]
            k = bisect.bisect_left(times, e["t"])
            if k < len(times) and times[k] == e["t"]:
                ties += 1
            elif k < len(times):
                truth[rl[k][1]][d] += bits(e)
            elif times and times[-1] == final_t:
                residual += bits(e)
            else:
                residual_early += bits(e)
    cell_err, sum_err, bad_ctr = 0, 0.0, 0
    a4 = bool(samples)
    for i, s in enumerate(samples):
        for d in ("ul", "dl"):
            if type(s["x2"][d]) is not int:
                bad_ctr += 1
                a4 = False
                continue
            err = abs(1000 * s["x2"][d] - truth[i][d])
            cell_err = max(cell_err, err)
            a4 &= err <= 500
    at = collections.defaultdict(list)
    for i, s in enumerate(samples):
        at[s["t"]].append(i)
    for idx in at.values():
        for d in ("ul", "dl"):
            if any(type(samples[i]["x2"][d]) is not int for i in idx):
                continue
            perr = abs(1000 * sum(samples[i]["x2"][d] for i in idx) - sum(truth[i][d] for i in idx)) / 1000
            sum_err = max(sum_err, perr)
            a4 &= perr <= len(idx)
    v.update({"perCellMaxErrBits": cell_err, "periodSumMaxErrKbit": sum_err, "ties": ties, "residualBits": residual,
              "residualBeforeFinalReadBits": residual_early, "nonIntCounters": bad_ctr})
    v["a4"] = a4 and ties == 0 and residual_early == 0 and bad == 0

    # A6
    v["legCounts"] = {"lte": sum(e["lcid"] == LCID and e["leg"] == 0 for e in dltx),
                      "x2": sum(e["lcid"] == LCID and e["leg"] != 0 for e in dltx)}
    v["a6"] = v["legCounts"]["lte"] > 0 and v["legCounts"]["x2"] > 0 and v["x2ulEvents"] > 0

    # A7
    v["ownPdcpNonZeroSamples"] = sum(any(type(s["own"][d]) is not int or s["own"][d] != 0 for d in ("ul", "dl"))
                                     for s in samples)
    v["a7"] = bool(samples) and v["ownPdcpNonZeroSamples"] == 0

    # A8: per (MN cell, gNB cell) pair, the sender's multiset against the receiver's
    late = stop_ns - LATE_NS
    ms = collections.defaultdict(collections.Counter)

    def put(name, pair, e):
        if pair[0] in M and pair[1] in G:
            ms[(name, pair)][e["bytes"]] += 1
            if e["t"] <= late:
                ms[(name + "Early", pair)][e["bytes"]] += 1
    for e in dltx:
        put("dlSend", (e["cell"], e["leg"]), e)
    for e in x2dl:
        put("dlRecv", (e["peer"], e["cell"]), e)
    for e in x2ul:
        put("ulSend", (e["peer"], e["cell"]), e)
    for e in ulrx:
        put("ulRecv", (e["cell"], e["leg"]), e)
    pairs = {p for _, p in ms}
    c = {"dlMnOnly": 0, "dlGnbOnly": 0, "ulGnbOnly": 0, "ulMnOnly": 0}
    for p in pairs:
        c["dlGnbOnly"] += multiset_excess(ms[("dlRecv", p)], ms[("dlSend", p)])
        c["dlMnOnly"] += multiset_excess(ms[("dlSendEarly", p)], ms[("dlRecv", p)])
        c["ulMnOnly"] += multiset_excess(ms[("ulRecv", p)], ms[("ulSend", p)])
        c["ulGnbOnly"] += multiset_excess(ms[("ulSendEarly", p)], ms[("ulRecv", p)])
    v["conservation"] = c
    v["lateSenderEvents"] = {"dl": sum(e["t"] > late for e in dltx if e["leg"] != 0),
                             "ul": sum(e["t"] > late for e in x2ul)}
    v["a8"] = not any(c.values())

    v["pass"] = all(v["a%d" % k] for k in range(9))
    return v


def expected_from_config(run, sim_time_s):
    """gNB node ids from the rung-config scenario, and the seq count from simTime and the gNB hello periodNs."""
    cfg = os.environ.get("RUNG_CONFIG", str(pathlib.Path(__file__).resolve().parent / "rung-config.json"))
    nodes = list(range(2, 2 + json.load(open(cfg))["scenario"]["nMmWaveEnbNodes"]["value"]))
    hellos = []
    load_gnb_samples(pathlib.Path(run) / "trace", hellos)
    periods = {h["periodNs"] for h in hellos}   # merged only after every hello's period is a positive int
    if not hellos or not all(valid_period(h["periodNs"]) for h in hellos) or len(periods) != 1:
        return nodes, 0   # no gNB hello, an invalid period or disagreeing periods: A0 fails closed
    n_seq, rem = divmod(round(sim_time_s * 1e9), next(iter(periods)))
    return nodes, (n_seq if rem == 0 else 0)


def _fixtures():
    spec = importlib.util.spec_from_file_location(
        "check_pdcp_volume_totals_fixtures", pathlib.Path(__file__).resolve().parent / "check-pdcp-volume-totals-fixtures.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main(argv):
    if argv[1:] == ["--self-test"]:
        return _fixtures().self_test(sys.modules[__name__])
    if len(argv) != 4 or argv[2] != "--sim-time-s":
        print(__doc__, file=sys.stderr)
        return 2
    sim_time_s = float(argv[3])
    v = judge(argv[1], *expected_from_config(argv[1], sim_time_s), round(sim_time_s * 1e9))
    json.dump(v, sys.stdout, indent=2)
    print()
    return 0 if v["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

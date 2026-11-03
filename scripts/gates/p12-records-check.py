#!/usr/bin/env python3
"""p12-records-check.py: multi-record KPM indications against the ns-3 IPC trace (AC10, KPM reporting period P = K x T).

  p12-records-check.py RECORDS_JSONL --map metric-map.v1.json --trace e2-ipc-trace-N.jsonl [--trace ...]
                       --per-indication K --granularity-ms G --out FILE
  p12-records-check.py --self-test

RECORDS_JSONL is `kpimon-decode-harness --records` over the capture's indication lines: per indication the decode
codes, msg_format, measDataItems (one per granularity interval, E2SM-KPM v03.00 8.2.1.4.1/8.2.1.4.2), the flat
record list (Format 1: every item's records in order; Format 2: item 0's records metric-major over the UEs), for
Format 2 every item's records (itemRecords) and the UE IDs (amfUeNgapIds, the IMSIs in the agent's encoding), the
granulPeriod and the header's colletStartTime. The trace gives each node's samples: seq, simTimeNs (simTimeMs is
simTimeNs // 10^6, the agent's own truncation, ns3_e2_agent src/sample-forwarder.cpp) and the IMSIs of its UE list.

Checks (exit 0 when all hold):
  1. every indication decodes RC_OK (header and message), carries exactly K measData items and granulPeriod G;
  2. Format 1, per node (the ns3.nodeId record): each indication's K items carry K consecutive seqs; the indications
     are disjoint, and together cover the node's trace seqs from the first one, in whole periods: the n mod K samples
     of the period still open at bye are not reported (no partial indication). So one indication per K seqs;
  3. every Format 1 and Format 2 header's collection start time is the first record's sample window start:
     epoch + max(0, simTimeMs - T) of that seq, with the epoch (simStartEpochMs) and T from the node's trace hello;
  4. every Format 2 indication's first seq starts a period that a Format 1 indication of the same node reports.
     Per item and listed UE: all noValue exactly when that IMSI is absent from the trace sample of the item's seq
     (E2SM-KPM v03.00 7.4.4.4: NULL for the granularity periods where a listed UE does not appear), otherwise its
     nodeId, seq and imsi records are the node's, the item's (first seq + item index) and the listed IMSI. The node
     and first seq come from the first UE block that has values;
  5. per node, every period that a Format 1 indication reports has Format 2 UE lists whose union is the period's
     trace UEs (the union over its K samples), no IMSI listed twice for the same period.
The record positions come from the metric map (gnb/enb cell and ue lists, by order).
"""
import argparse
import json
import sys
import tempfile

NTP_UNIX_OFFSET_S = 2208988800


def ntp_ms(ts_hex):
    v = int(ts_hex, 16)
    return (v >> 32) * 1000 + round((v & 0xFFFFFFFF) * 1000 / 2 ** 32) - NTP_UNIX_OFFSET_S * 1000


def layout(map_path):
    rows = json.load(open(map_path))["rows"]
    out = {}
    for kind in ("gnb", "enb"):
        for lst in ("cell", "ue"):
            names = [r["kpm"] for r in sorted((r for r in rows if r["kind"] == kind and r["list"] == lst),
                                              key=lambda r: r["order"])]
            out[(kind, lst)] = names
    return out


def load_traces(paths):
    nodes = {}
    for p in paths:
        hello, samples = None, {}
        for line in open(p):
            m = json.loads(line)
            if m["type"] == "hello":
                hello = m
            elif m["type"] == "sample":
                samples[m["seq"]] = {"simTimeMs": m["simTimeNs"] // 1_000_000,
                                     "imsis": {ue["imsi"] for ue in m.get("ues", [])}}
        if hello is None:
            sys.exit("trace %s has no hello" % p)
        nodes[hello["nodeId"]] = {"kind": hello["kind"], "periodMs": hello["periodNs"] // 1_000_000,
                                  "epochMs": hello["simStartEpochMs"], "samples": samples}
    return nodes


def value(rec):
    return rec.get("v") if rec.get("t") == "int" else None


def format2_judge(tag, x, n, lay, nodes, problems):
    """(node, first seq, IMSIs) of a Format 2 indication, judged UE block by UE block against the trace, or None."""
    items, u, imsis = x.get("itemRecords"), x.get("ueIdsPerItem") or 0, x.get("amfUeNgapIds") or []
    if u <= 0 or not x.get("ueIdsUniform", False) or len(imsis) != u or len(set(imsis)) != u or None in imsis:
        problems.append("%s: Format 2 UE ids %r per item %r uniform %r" % (tag, imsis, u, x.get("ueIdsUniform")))
        return None
    if not isinstance(items, list) or len(items) != n:
        problems.append("%s: Format 2 itemRecords %s for %s items" % (tag, None if items is None else len(items), n))
        return None
    width = {len(rs) for rs in items}
    if len(width) != 1 or next(iter(width)) % u:
        problems.append("%s: Format 2 item record counts %s for %d UEs" % (tag, sorted(width), u))
        return None
    m = next(iter(width)) // u
    # block(i, j): UE j's records in item i (metric-major: metric r of UE j at r * u + j).
    block = lambda i, j: [items[i][r * u + j] for r in range(m)]
    present = [(i, j) for i in range(n) for j in range(u) if any(rec.get("t") != "none" for rec in block(i, j))]
    if not present:
        problems.append("%s: Format 2 carries no value in any item" % tag)
        return None
    node = value(block(*present[0])[0])
    if node not in nodes:
        problems.append("%s: Format 2 nodeId %r not in the traces" % (tag, node))
        return None
    names = lay[(nodes[node]["kind"], "ue")]
    if len(names) != m:
        problems.append("%s: Format 2 has %d metrics per UE, the map %d" % (tag, m, len(names)))
        return None
    ni, si, ii = names.index("ns3.nodeId"), names.index("ns3.seq"), names.index("ns3.imsi")
    i0, j0 = present[0]
    seq0 = (value(block(i0, j0)[si]) or 0) - i0
    trace = nodes[node]["samples"]
    for i in range(n):
        s = trace.get(seq0 + i)
        if s is None:
            problems.append("%s: Format 2 item %d seq %d not in node %d's trace" % (tag, i, seq0 + i, node))
            continue
        for j, imsi in enumerate(imsis):
            b = block(i, j)
            if (i, j) not in present:
                if imsi in s["imsis"]:
                    problems.append("%s: Format 2 item %d IMSI %d is noValue, but the UE is in the trace at seq %d" % (tag, i, imsi, seq0 + i))
            elif imsi not in s["imsis"]:
                problems.append("%s: Format 2 item %d IMSI %d has values, but the UE is not in the trace at seq %d" % (tag, i, imsi, seq0 + i))
            elif (value(b[ni]), value(b[si]), value(b[ii])) != (node, seq0 + i, imsi):
                problems.append("%s: Format 2 item %d UE %d nodeId/seq/imsi %s, want %s" % (
                    tag, i, j, (value(b[ni]), value(b[si]), value(b[ii])), (node, seq0 + i, imsi)))
    return node, seq0, imsis


def check(records_path, lay, nodes, k, g):
    problems, f1_by_node, f2 = [], {}, []
    items_hist = {}
    lines = [json.loads(l) for l in open(records_path) if l.strip()]
    for x in lines:
        tag = x.get("id")
        if x.get("hdr_code") != "RC_OK" or x.get("msg_code") != "RC_OK":
            problems.append("%s: decode %s/%s" % (tag, x.get("hdr_code"), x.get("msg_code")))
            continue
        n = x.get("measDataItems")
        items_hist[n] = items_hist.get(n, 0) + 1
        if n != k:
            problems.append("%s: %s measData items, want %d" % (tag, n, k))
        if x.get("granulPeriod") != g:
            problems.append("%s: granulPeriod %r, want %d" % (tag, x.get("granulPeriod"), g))
        recs = x.get("records", [])
        if x.get("msg_format") == 1:
            node = value(recs[0]) if recs else None
            if node not in nodes:
                problems.append("%s: Format 1 nodeId %r not in the traces" % (tag, node))
                continue
            names = lay[(nodes[node]["kind"], "cell")]
            w = len(names)
            if len(recs) != w * (n or 0):
                problems.append("%s: %d records for %s items of %d metrics" % (tag, len(recs), n, w))
                continue
            seqs = [value(recs[i * w + names.index("ns3.seq")]) for i in range(n)]
            f1_by_node.setdefault(node, []).append((tag, seqs, x.get("header", {}).get("ts_hex")))
        elif x.get("msg_format") == 2:
            r = format2_judge(tag, x, n, lay, nodes, problems)
            if r is not None:
                f2.append((tag, r[0], r[1], r[2], x.get("header", {}).get("ts_hex")))
        else:
            problems.append("%s: message format %r" % (tag, x.get("msg_format")))

    def header_ok(tag, node, seq0, ts_hex):
        s = nodes[node]["samples"].get(seq0)
        if s is None:
            problems.append("%s: seq %r not in node %d's trace" % (tag, seq0, node))
            return
        want = nodes[node]["epochMs"] + max(0, s["simTimeMs"] - nodes[node]["periodMs"])
        if ts_hex is None or ntp_ms(ts_hex) != want:
            problems.append("%s: header time %s, want %d (seq %d)" % (tag, ts_hex and ntp_ms(ts_hex), want, seq0))

    per_node, starts = {}, {}
    for node, info in sorted(nodes.items()):
        trace = sorted(info["samples"])
        full = len(trace) - len(trace) % k
        got = f1_by_node.get(node, [])
        covered = []
        for tag, seqs, ts in got:
            if any(s is None for s in seqs) or seqs != list(range(seqs[0], seqs[0] + len(seqs))):
                problems.append("%s: seqs %s are not consecutive" % (tag, seqs))
                continue
            covered += seqs
            starts.setdefault(node, set()).add(seqs[0])
            header_ok(tag, node, seqs[0], ts)
        if sorted(covered) != trace[:full] or len(set(covered)) != len(covered):
            problems.append("node %d: Format 1 covers seqs %s..%s (%d, %d distinct), want trace[:%d] = %s..%s" % (
                node, min(covered, default=None), max(covered, default=None), len(covered), len(set(covered)),
                full, trace[0] if trace else None, trace[full - 1] if full else None))
        per_node[node] = {"traceSamples": len(trace), "format1Indications": len(got), "seqsCovered": len(covered),
                          "unreportedAtBye": len(trace) - full,
                          "indicationsPerKSeqs": (len(got) * k / full) if full else None}
    listed = {}
    for tag, node, seq0, imsis, ts in f2:
        if seq0 not in starts.get(node, set()):
            problems.append("%s: Format 2 first seq %r starts no Format 1 period of node %d" % (tag, seq0, node))
        else:
            header_ok(tag, node, seq0, ts)
            listed.setdefault((node, seq0), []).extend(imsis)
    for node, ss in sorted(starts.items()):
        tr = nodes[node]["samples"]
        for s0 in sorted(ss):
            want = sorted(set().union(*(tr[q]["imsis"] for q in range(s0, s0 + k) if q in tr)))
            got = sorted(listed.get((node, s0), []))
            if got != want:
                problems.append("node %d period %d: Format 2 lists IMSIs %s, the trace has %s" % (node, s0, got, want))
    return {"perIndication": k, "indications": len(lines), "measDataItemsHistogram": {str(a): b for a, b in sorted(items_hist.items(), key=str)},
            "recordsPerIndication": next(iter(items_hist)) if len(items_hist) == 1 else sorted(items_hist, key=str),
            "indicationsPerTenSeqs": (sorted({v["indicationsPerKSeqs"] for v in per_node.values()}, key=str)[0]
                                      if len({v["indicationsPerKSeqs"] for v in per_node.values()}) == 1 else None),
            "format2Indications": len(f2), "nodes": {str(n): v for n, v in per_node.items()},
            "problems": problems[:40], "problemCount": len(problems), "pass": not problems and bool(lines)}


def self_test():
    d = tempfile.mkdtemp()
    cell = ["ns3.nodeId", "ns3.simTimeMs", "ns3.seq", "m1"]
    ue = ["ns3.nodeId", "ns3.simTimeMs", "ns3.seq", "ns3.imsi", "u1"]
    rows = [{"kind": "gnb", "list": "cell", "order": i, "kpm": n} for i, n in enumerate(cell)]
    rows += [{"kind": "gnb", "list": "ue", "order": i, "kpm": n} for i, n in enumerate(ue)]
    json.dump({"rows": rows}, open(d + "/map.json", "w"))
    epoch, T, k = 1767225600000, 100, 10
    # UE IMSI 1 from seq 1, IMSI 2 from seq 4 (appears in the middle of the first period).
    in_trace = lambda seq: [i for i, first in ((1, 1), (2, 4)) if seq >= first]
    with open(d + "/trace.jsonl", "w") as f:
        f.write(json.dumps({"type": "hello", "nodeId": 2, "kind": "gnb", "periodNs": T * 1_000_000, "simStartEpochMs": epoch}) + "\n")
        for s in range(1, 26):  # 25 samples: 2 whole periods, 5 unreported at bye; the emitter's 0.8 ms offset
            f.write(json.dumps({"type": "sample", "seq": s, "simTimeNs": 800000 + s * T * 1_000_000,
                                "ues": [{"imsi": i} for i in in_trace(s)]}) + "\n")

    def ts(seq):
        ms = epoch + max(0, seq * T - T)  # (800000 + seq * T * 10^6) // 10^6 = seq * T
        sec, frac = divmod(ms, 1000)
        return "%016x" % (((sec + NTP_UNIX_OFFSET_S) << 32) | round(frac * 2 ** 32 / 1000))

    def f1(tag, seqs, items=None, g=T):
        recs = [r for s in seqs for r in ({"t": "int", "v": 2}, {"t": "int", "v": s * T}, {"t": "int", "v": s}, {"t": "real", "bits": "0"})]
        return {"id": tag, "hdr_code": "RC_OK", "msg_code": "RC_OK", "msg_format": 1, "measDataItems": items or len(seqs),
                "records": recs, "granulPeriod": g, "header": {"ts_hex": ts(seqs[0])}}

    def f2(tag, seq0, imsis=(1, 2), blank=(), fill=(), seq_of=None, g=T):
        """The agent's encoding (values where the UE is in the trace, noValue elsewhere), with blank/fill overrides."""
        u, none = len(imsis), {"t": "none"}

        def item(i):
            sq = seq_of(i) if seq_of else seq0 + i
            per_ue = []
            for j, imsi in enumerate(imsis):
                has = (imsi in in_trace(seq0 + i) or (i, j) in fill) and (i, j) not in blank
                per_ue.append([2, sq * T, sq, imsi, None] if has else [None] * len(ue))
            return [none if per_ue[j][r] is None else {"t": "int", "v": per_ue[j][r]} for r in range(len(ue)) for j in range(u)]
        items = [item(i) for i in range(k)]
        return {"id": tag, "hdr_code": "RC_OK", "msg_code": "RC_OK", "msg_format": 2, "measDataItems": k,
                "records": items[0], "itemRecords": items, "ueIdsPerItem": u, "ueIdsUniform": True,
                "amfUeNgapIds": list(imsis), "granulPeriod": g, "header": {"ts_hex": ts(seq0)}}

    def run(lines):
        open(d + "/r.jsonl", "w").write("".join(json.dumps(x) + "\n" for x in lines))
        return check(d + "/r.jsonl", layout(d + "/map.json"), load_traces([d + "/trace.jsonl"]), k, T)

    f1s = [f1("a", list(range(1, 11))), f1("b", list(range(11, 21)))]
    good = f1s + [f2("c", 1), f2("d", 11)]
    r = run(good)
    assert r["pass"] and r["recordsPerIndication"] == 10 and r["indicationsPerTenSeqs"] == 1.0, r
    assert r["nodes"]["2"]["unreportedAtBye"] == 5, r
    assert run(f1s + [f2("c", 1), f2("d1", 11, imsis=(1,)), f2("d2", 11, imsis=(2,))])["pass"], "UE chunks split over two messages must pass"
    assert not run(good + [f1("e", list(range(21, 26)))])["pass"], "a partial period at bye must fail"
    assert not run(good[:1] + good[2:3])["pass"], "a missing period must fail"
    assert not run([f1("a", list(range(1, 11))), f1("b", [11, 12, 13, 14, 15, 17, 16, 18, 19, 20])] + good[2:])["pass"], "out of order"
    bad_ts = json.loads(json.dumps(good)); bad_ts[1]["header"]["ts_hex"] = ts(12)
    assert not run(bad_ts)["pass"], "a header stamped at another seq must fail"
    assert not run(f1s + [f2("c", 5), f2("d", 11)])["pass"], "a Format 2 period start that Format 1 does not report must fail"
    assert not run(f1s + [f2("c", 1, blank={(5, 1)}), f2("d", 11)])["pass"], "a present UE blanked in the middle must fail"
    assert not run(f1s + [f2("c", 1, blank={(0, 0)}), f2("d", 11)])["pass"], "a present UE blanked at the period start must fail"
    assert not run(f1s + [f2("c", 1, fill={(1, 1)}), f2("d", 11)])["pass"], "values for a UE absent from the trace must fail"
    assert not run(f1s + [f2("c", 1, blank={(i, 0) for i in range(k)} | {(i, 1) for i in range(k)}), f2("d", 11)])["pass"], "an all-noValue Format 2 must fail"
    assert not run(f1s + [f2("c", 1, seq_of=lambda i: 1 + i + (i == 5)), f2("d", 11)])["pass"], "a Format 2 item at another seq must fail"
    assert not run(f1s + [f2("c", 1)])["pass"], "a period with trace UEs but no Format 2 must fail"
    assert not run(good + [f2("d2", 11, imsis=(2,))])["pass"], "an IMSI listed twice for one period must fail"
    assert not run(f1s + [f2("c", 1), f2("d", 11, imsis=(1,))])["pass"], "a trace UE missing from the period's lists must fail"
    assert not run([f1("a", list(range(1, 11)), g=1000)] + good[1:])["pass"], "a Format 1 granulPeriod other than G must fail"
    assert not run(f1s + [f2("c", 1, g=1000), f2("d", 11)])["pass"], "a Format 2 granulPeriod other than G must fail"
    one_rec = [f1("x%d" % s, [s]) for s in range(1, 26)]
    assert not run(one_rec)["pass"], "one record per indication at K = 10 must fail"
    print("p12-records-check self-test: ok")
    return 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("records")
    ap.add_argument("--map", required=True)
    ap.add_argument("--trace", action="append", required=True)
    ap.add_argument("--per-indication", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--granularity-ms", type=int, required=True)
    a = ap.parse_args()
    r = check(a.records, layout(a.map), load_traces(a.trace), a.per_indication, a.granularity_ms)
    json.dump(r, open(a.out, "w"), indent=1, sort_keys=True)
    print(json.dumps({k: v for k, v in r.items() if k != "problems"}, sort_keys=True))
    for p in r["problems"]:
        print("problem:", p)
    return 0 if r["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())

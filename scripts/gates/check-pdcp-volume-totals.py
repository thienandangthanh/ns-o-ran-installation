#!/usr/bin/env python3
"""check-pdcp-volume-totals.py: judge the gNB cells' DRB.PdcpSduVolumeUL/DL against the PDCP audit.

A UL-on ns-3 run prints one `N4AUDIT` line per DRB PDCP PDU event on every eNB/gNB RRC
(scenario-zero, enableUlTraffic). That audit is the ground truth for the two per-cell counters
in the gNB IPC samples (cell.cuUp, kbit, rounded once per cell per period). Pass iff:
  A0 sample completeness: the gNB traces are exactly the expected gNB nodes (2 .. 1 + nMmWaveEnbNodes of
     the rung-config scenario; node 1 is the eNB) and each holds every seq 0 .. N-1 once, N = simTime /
     the hello periodNs (a missing cell or a truncated tail fails instead of becoming residual bits);
  A1 completeness: an `end` line with connected == present and missing == 0; the audit header's
     PDCP header size equals the 12-bit-SN DRB data PDU header (2 octets, 3GPP TS 36.323 §6.2.3,
     3GPP TS 38.323 §6.2.2.2);
  A2 one RRC per IMSI: every ulrx/dltx event of an IMSI is on one node;
  A3 no UL PDU at two RRCs: no UL identity (imsi, tNs - delayNs) on two nodes (delayNs == 0 has
     no identity: reported, not judged);
  A4 accounting: per gNB sample, |1000 * counter - truthBits| <= 500 for UL and DL, where truthBits
     = sum of 8 * (pduBytes - h) over the lcid-3 events of the sample's UEs in (that UE's previous
     gNB read, this read]; per read instant, the sum over gNB cells is within 1 kbit per cell; an
     event exactly at a read instant of its UE is a tie and fails; a UE listed by two gNB cells at
     one read is judged on the sum over those cells and counted as an overlap; events after a UE's
     last read are residual and allowed only when that read is the run's final read instant (a UE
     that vanishes from every gNB map before the end leaves unverified bits, which fail);
  A5 every event has pduBytes >= h + 1 and every UL lcid-3 SDU is larger than 40 bytes.
Never compensates a double count (no dedupe, factor or wider tolerance).

  check-pdcp-volume-totals.py RUN_DIR --sim-time-s S
        (RUN_DIR/ns3run/stdout.txt, RUN_DIR/trace/*.jsonl; nMmWaveEnbNodes from rung-config.json or $RUNG_CONFIG)
  check-pdcp-volume-totals.py --self-test
"""
import collections
import json
import os
import pathlib
import sys
import tempfile

HDR = 2  # octets: 12-bit-SN DRB data PDU header (D/C, 3 R, SN), 3GPP TS 36.323 §6.2.3
KEYS = {"ul": "DRB.PdcpSduVolumeUL", "dl": "DRB.PdcpSduVolumeDL"}
LCID = 3


def load_audit(path):
    hdr, end, ev = None, None, []
    for line in pathlib.Path(path).read_text(errors="replace").splitlines():
        if not line.startswith("N4AUDIT "):
            continue
        f = line.split()
        if f[1] == "v1":
            hdr = int(f[2].split("=")[1])
        elif f[1] == "end":
            end = {k: int(v) for k, v in (x.split("=") for x in f[2:])}
        elif f[1] in ("ulrx", "dltx"):
            e = {"d": f[1][:2], "t": int(f[2]), "node": int(f[3]), "cell": int(f[4]), "imsi": int(f[5]),
                 "lcid": int(f[6]), "bytes": int(f[7])}
            if e["d"] == "ul":
                e["delay"] = int(f[8])
            ev.append(e)
    return hdr, end, ev


def load_gnb_samples(trace_dir, periods=None):
    out = []
    for p in sorted(pathlib.Path(trace_dir).glob("e2-ipc-trace-*.jsonl")):
        kind = None
        for line in p.read_text().splitlines():
            if not line.strip():
                continue
            m = json.loads(line)
            if m.get("type") == "hello":
                kind = m.get("kind")
                if periods is not None and kind == "gnb":
                    periods.add(m.get("periodNs"))
            elif m.get("type") == "sample" and kind == "gnb":
                cu = (m.get("cell") or {}).get("cuUp") or {}
                out.append({"node": m["nodeId"], "seq": m["seq"], "t": m["simTimeNs"],
                            "ues": sorted(u["imsi"] for u in m.get("ues") or [] if "cuUp" in u),
                            "ctr": {d: cu.get(k) for d, k in KEYS.items()}})
    return out


def judge(run, gnb_nodes, n_seq):
    run = pathlib.Path(run)
    hdr, end, ev = load_audit(run / "ns3run" / "stdout.txt")
    samples = load_gnb_samples(run / "trace")
    v = {"hdr": hdr, "end": end, "events": len(ev), "gnbSamples": len(samples)}

    # A0
    seqs = collections.defaultdict(list)
    for s in samples:
        seqs[s["node"]].append(s["seq"])
    want = list(range(n_seq))
    v["expectedGnbNodes"], v["expectedSeqsPerNode"], v["gnbNodes"] = sorted(gnb_nodes), n_seq, sorted(seqs)
    v["incompleteNodes"] = {str(n): {"missing": len(set(want) - set(seqs.get(n, []))),
                                     "extraOrDuplicate": len(seqs.get(n, [])) - len(set(seqs.get(n, [])) & set(want))}
                            for n in sorted(set(gnb_nodes) | set(seqs)) if sorted(seqs.get(n, [])) != want}
    v["a0"] = n_seq > 0 and set(seqs) == set(gnb_nodes) and not v["incompleteNodes"]

    # A1
    v["a1"] = hdr == HDR and end is not None and end.get("missing") == 0 and end.get("connected") == end.get("present")

    # A2, A3
    nodes = collections.defaultdict(set)
    ul_id = collections.defaultdict(set)
    no_id = 0
    for e in ev:
        nodes[e["imsi"]].add(e["node"])
        if e["d"] == "ul":
            if e["delay"] == 0:
                no_id += 1
            else:
                ul_id[(e["imsi"], e["t"] - e["delay"])].add(e["node"])
    v["rrcNodesPerImsi"] = {str(i): sorted(n) for i, n in sorted(nodes.items())}
    v["a2"] = bool(ev) and all(len(n) == 1 for n in nodes.values())
    v["twoRrcIdentities"] = sum(len(n) > 1 for n in ul_id.values())
    v["noIdentityEvents"] = no_id
    v["a3"] = v["twoRrcIdentities"] == 0
    same = collections.Counter((e["node"], e["imsi"], e["t"] - e["delay"]) for e in ev if e["d"] == "ul" and e["delay"])
    v["sameRrcDuplicates"] = sum(c - 1 for c in same.values() if c > 1)

    # A5
    v["a5"] = bool(ev) and all(e["bytes"] >= HDR + 1 for e in ev) and \
        all(e["bytes"] - HDR > 40 for e in ev if e["d"] == "ul" and e["lcid"] == LCID)

    # A4: per UE, the gNB reads that list it, in time order
    reads = collections.defaultdict(list)
    for i, s in enumerate(samples):
        for imsi in s["ues"]:
            reads[imsi].append((s["t"], i))
    truth = [{"ul": 0, "dl": 0} for _ in samples]
    final_t = max((s["t"] for s in samples), default=None)
    ties, residual, unverified = 0, 0, 0
    by_ue = collections.defaultdict(list)
    for e in ev:
        if e["lcid"] == LCID:
            by_ue[e["imsi"]].append(e)
    per_ue_ul_pdus = []
    for imsi, es in by_ue.items():
        rl = sorted(reads.get(imsi, []))
        times = sorted({t for t, _ in rl})
        tset = set(times)
        for e in es:
            if e["t"] in tset:
                ties += 1
                continue
            nxt = next((t for t in times if t > e["t"]), None)
            if nxt is None:
                if times and times[-1] == final_t:
                    residual += 8 * (e["bytes"] - HDR)
                else:
                    unverified += 8 * (e["bytes"] - HDR)
                continue
            owners = [i for t, i in rl if t == nxt]
            truth[owners[0]][e["d"]] += 8 * (e["bytes"] - HDR)
        prev = -1
        for t in times:
            per_ue_ul_pdus.append(sum(1 for e in es if e["d"] == "ul" and prev < e["t"] < t))
            prev = t
    v["ties"], v["residualBits"], v["unverifiedResidualBits"] = ties, residual, unverified

    # groups of gNB samples at one read instant joined by a shared UE (HO overlap)
    at = collections.defaultdict(list)
    for i, s in enumerate(samples):
        at[s["t"]].append(i)
    overlaps, cell_err, sum_err, bad_ctr = 0, 0, 0.0, 0
    a4 = bool(samples)
    for t, idx in at.items():
        parent = {i: i for i in idx}

        def find(i):
            while parent[i] != i:
                i = parent[i]
            return i
        owner = {}
        for i in idx:
            for imsi in samples[i]["ues"]:
                if imsi in owner:
                    overlaps += 1
                    parent[find(i)] = find(owner[imsi])
                else:
                    owner[imsi] = i
        groups = collections.defaultdict(list)
        for i in idx:
            groups[find(i)].append(i)
        for d in ("ul", "dl"):
            if any(type(samples[i]["ctr"][d]) is not int for i in idx):
                bad_ctr += 1
                a4 = False
                continue
            for g in groups.values():
                err = abs(1000 * sum(samples[i]["ctr"][d] for i in g) - sum(truth[i][d] for i in g))
                cell_err = max(cell_err, err)
                a4 &= err <= 500 * len(g)
            perr = abs(1000 * sum(samples[i]["ctr"][d] for i in idx) - sum(truth[i][d] for i in idx)) / 1000
            sum_err = max(sum_err, perr)
            a4 &= perr <= len(idx)
    v.update({"perCellMaxErrBits": cell_err, "periodSumMaxErrKbit": sum_err, "overlaps": overlaps,
              "nonIntCounters": bad_ctr})
    v["a4"] = a4 and ties == 0 and unverified == 0
    v["perUeUlPdusPerPeriod"] = dict(sorted(collections.Counter(per_ue_ul_pdus).items()))
    v["pass"] = all(v[k] for k in ("a0", "a1", "a2", "a3", "a4", "a5"))
    return v


def _fixture(root, audit, samples):
    (root / "ns3run").mkdir(parents=True)
    (root / "trace").mkdir()
    (root / "ns3run" / "stdout.txt").write_text("noise\n" + "\n".join(audit) + "\n")
    lines = [json.dumps({"type": "hello", "nodeId": 2, "kind": "gnb", "periodNs": 100000000})]
    for seq, t, ues, ul, dl in samples:
        lines.append(json.dumps({"type": "sample", "nodeId": 2, "seq": seq, "simTimeNs": t,
                                 "cell": {"cuUp": {KEYS["ul"]: ul, KEYS["dl"]: dl}},
                                 "ues": [{"imsi": i, "cuUp": {}} for i in ues]}))
    (root / "trace" / "e2-ipc-trace-2.jsonl").write_text("\n".join(lines) + "\n")
    return root


def self_test():
    good = ["N4AUDIT v1 hdr=2",
            "N4AUDIT ulrx 150000000 0 1 3 3 1310 2000000", "N4AUDIT ulrx 160000000 0 1 3 3 1310 2000000",
            "N4AUDIT dltx 170000000 0 1 3 3 1310", "N4AUDIT end connected=2 present=2 missing=0"]
    # 2 UL PDUs of 1308 B SDU = 20928 bits -> 21 kbit; 1 DL -> 10464 bits -> 10 kbit
    ok_samples = [(0, 100800000, [3], 0, 0), (1, 200800000, [3], 21, 10)]
    tail = good[:-1] + ["N4AUDIT ulrx 250000000 0 1 3 3 1310 2000000", good[-1]]
    # (name, audit, samples, want[, expected gNB nodes[, expected seqs per node]]); default [2], 2
    cases = [
        ("pass", good, ok_samples, True),
        ("pass, residual after the final read", tail, ok_samples, True),
        ("counter off by 1 kbit", good, [(0, 100800000, [3], 0, 0), (1, 200800000, [3], 22, 10)], False),
        ("PDU counted at two RRCs", good + ["N4AUDIT ulrx 150000000 7 9 3 3 1310 2000000"], ok_samples, False),
        ("header size 3", [good[0].replace("hdr=2", "hdr=3")] + good[1:], ok_samples, False),
        ("an unconnected PDCP", good[:-1] + ["N4AUDIT end connected=2 present=3 missing=1"], ok_samples, False),
        ("no end line", good[:-1], ok_samples, False),
        ("tie at a read", good + ["N4AUDIT dltx 200800000 0 1 3 3 1310"], ok_samples, False),
        ("UL SDU of 40 B", good + ["N4AUDIT ulrx 180000000 0 1 3 3 42 1000"], ok_samples, False),
        ("a float counter", good, [(0, 100800000, [3], 0, 0), (1, 200800000, [3], 21.0, 10)], False),
        ("a missing gNB cell", good, ok_samples, False, [2, 3]),
        ("a truncated tail", good, ok_samples, False, [2], 3),
        ("a duplicate seq", good, ok_samples + [(1, 200800000, [], 0, 0)], False),
        ("an unexpected gNB node", good, ok_samples, False, [3]),
        ("residual after a UE leaves every gNB map", tail,
         [(0, 100800000, [3], 0, 0), (1, 200800000, [3], 21, 10), (2, 300800000, [], 0, 0)], False, [2], 3),
    ]
    bad = 0
    for name, audit, smp, want, *exp in cases:
        nodes, n_seq = (exp + [[2], 2][len(exp):])[:2]
        with tempfile.TemporaryDirectory() as t:
            got = judge(_fixture(pathlib.Path(t), audit, smp), nodes, n_seq)["pass"]
        bad += got != want
        print(("ok   " if got == want else "FAIL ") + name)
    return 1 if bad else 0


def expected_from_config(run, sim_time_s):
    """gNB node ids from the rung-config scenario, and the seq count from simTime and the gNB hello periodNs."""
    cfg = os.environ.get("RUNG_CONFIG", str(pathlib.Path(__file__).resolve().parent / "rung-config.json"))
    nodes = list(range(2, 2 + json.load(open(cfg))["scenario"]["nMmWaveEnbNodes"]["value"]))
    periods = set()
    load_gnb_samples(pathlib.Path(run) / "trace", periods)
    if len(periods) != 1 or type(next(iter(periods))) is not int or next(iter(periods)) <= 0:
        return nodes, 0   # no gNB hello, or disagreeing periods: A0 fails closed
    n_seq, rem = divmod(round(sim_time_s * 1e9), next(iter(periods)))
    return nodes, (n_seq if rem == 0 else 0)


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    if len(argv) != 4 or argv[2] != "--sim-time-s":
        print(__doc__, file=sys.stderr)
        return 2
    v = judge(argv[1], *expected_from_config(argv[1], float(argv[3])))
    json.dump(v, sys.stdout, indent=2)
    print()
    return 0 if v["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

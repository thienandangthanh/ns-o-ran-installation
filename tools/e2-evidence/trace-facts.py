#!/usr/bin/env python3
"""trace-facts.py <trace.jsonl>... [--require-clean | --reconnects-ok] [--expect-nodes 1,2] [--out f.json]
trace-facts.py --pdcp-stats <ns3run dir> [--out f.json]

Summarises ns-3 IPC trace files (e2-ipc-trace-<cellId>.jsonl: hello, sample and
bye lines, written before every send so dropped samples are included).
Per node: kind, hello count, samples, lastSeq, seq gaps, bye counters
(built, sent, droppedDisconnected, droppedBackpressure) and the largest
per-sample ipcDropped. --require-clean fails unless every node has exactly one
hello and one bye, sent == built, zero drops and no seq gaps. --reconnects-ok is for runs where the
agents restart (the emitter reconnects and says hello again) and drops are expected: it needs exactly one bye,
hello >= 1, no seq gaps, built == sent + droppedDisconnected + droppedBackpressure and last_seq == built - 1,
and only reports the drop counts. --expect-nodes
fails unless the node set matches exactly.

--pdcp-stats judges the DL PDU size of the EN-DC data bearer in one run's ns3run directory. DlE2PdcpStats.txt
(MmWaveBearerStatsCalculator: per epoch and IMSI/LCID, nTxPDUs and TxBytes counted at the MC PDCP entity's TxPDU
trace, after its header is added; columns found by header name) is judged on its LCID-3 rows with nTxPDUs > 0,
against W = 1308 + 2, the scenario's 1308-byte DL SDU plus the 2-octet NR PDCP data PDU header with a 12-bit SN
(3GPP TS 38.323 §6.2.2.2):
  - a switch row, one with a SwitchToLte or SwitchToMmWave of its IMSI in [start - d, end + d), d = end - start
    (events from LteSwitchStats.txt and MmWaveSwitchStats.txt of the same directory: time field 2, IMSI field 3),
    has TxBytes <= nTxPDUs * W: at a switch the eNB re-submits RLC buffer entries, some of them short;
  - every other row has TxBytes == nTxPDUs * W;
  - at least one row is not a switch row.
A missing switch file means no event of that kind (the simulator creates it on its first event); a malformed switch
line fails. The fact (printed, and written to --out) holds the switch-row and equality-row counts, overall and per IMSI.
"""
import argparse
import json
import os
import sys

DRB_LCID = 3          # the scenario's one data radio bearer
DL_SDU_BYTES = 1308   # DL UDP payload 1280 + UDP 8 + IPv4 20: the PDCP SDU
NR_PDCP_HDR = 2       # NR PDCP data PDU header, 12-bit SN: octet 1 D/C, R, R, R, SN[11:8]; octet 2 SN[7:0] (38.323 §6.2.2.2)


def summarize(path):
    d = {"file": path, "hello": 0, "bye": 0, "samples": 0, "last_seq": None, "seq_gaps": 0, "ipc_dropped_max": 0,
         "ues_max": 0, "bye_msg": None, "node": None, "kind": None, "period_ns": None}
    prev = None
    for line in open(path):
        if not line.strip():
            continue
        m = json.loads(line)
        if m["type"] == "hello":
            d["hello"] += 1
            d["node"], d["kind"], d["period_ns"] = m["nodeId"], m["kind"], m.get("periodNs")
        elif m["type"] == "sample":
            d["samples"] += 1
            if prev is not None and m["seq"] != prev + 1:
                d["seq_gaps"] += 1
            prev = d["last_seq"] = m["seq"]
            d["ipc_dropped_max"] = max(d["ipc_dropped_max"], m.get("ipcDropped", 0))
            d["ues_max"] = max(d["ues_max"], len(m.get("ues", [])))
        elif m["type"] == "bye":
            d["bye"] += 1
            d["bye_msg"] = {k: m.get(k) for k in ("built", "sent", "droppedDisconnected", "droppedBackpressure", "lastSeq")}
    return d


SWITCH_FILES = (("LteSwitchStats.txt", "SwitchToLte"), ("MmWaveSwitchStats.txt", "SwitchToMmWave"))


def switch_events(run_dir):
    """({imsi: [times]} of both switch files, problems); a missing file holds no event. A line is exactly
    `<kind> <time s> <imsi> <cellId> <rnti>` as McStatsCalculator writes it."""
    events, bad = {}, []
    for name, kind in SWITCH_FILES:
        path = os.path.join(run_dir, name)
        if not os.path.exists(path):
            continue
        for n, line in enumerate(open(path), 1):
            f = line.split()
            if not f:
                continue
            try:
                if len(f) != 5 or f[0] != kind or any(int(x) < 0 for x in f[2:]):
                    raise ValueError
                t, imsi = float(f[1]), int(f[2])
            except ValueError:
                bad.append("%s:%d: not a %s line: %r" % (path, n, kind, line[:120]))
                continue
            events.setdefault(imsi, []).append(t)
    return events, bad


def pdcp_dl_pdu_bytes(run_dir):
    """(problems, fact) of a run's DlE2PdcpStats.txt against its switch files (see the module doc)."""
    want = DL_SDU_BYTES + NR_PDCP_HDR
    path = os.path.join(run_dir, "DlE2PdcpStats.txt")
    events, bad = switch_events(run_dir)
    cols, per = None, {}
    for n, line in enumerate(open(path), 1):
        if line.startswith("%"):
            cols = line[1:].split()
            continue
        if not line.strip():
            continue
        names = ("start", "end", "IMSI", "LCID", "nTxPDUs", "TxBytes")
        if cols is None or not set(names) <= set(cols):
            return bad + ["%s:%d: a data row before a header naming %s" % (path, n, ", ".join(names))], None
        f = line.split()
        try:
            start, end = float(f[cols.index("start")]), float(f[cols.index("end")])
            imsi, lcid, npdu, nbytes = (int(f[cols.index(k)]) for k in names[2:])
        except (IndexError, ValueError):
            return bad + ["%s:%d: not a stats row: %r" % (path, n, line[:120])], None
        if lcid != DRB_LCID or npdu <= 0:
            continue
        d = end - start
        switch = any(start - d <= t < end + d for t in events.get(imsi, ()))
        c = per.setdefault(str(imsi), {"switchRows": 0, "equalityRows": 0})
        c["switchRows" if switch else "equalityRows"] += 1
        if switch and nbytes > npdu * want:
            bad.append("%s:%d: switch row, IMSI %d nTxPDUs %d TxBytes %d > %d * %d" % (path, n, imsi, npdu, nbytes, npdu, want))
        elif not switch and nbytes != npdu * want:
            bad.append("%s:%d: IMSI %d nTxPDUs %d TxBytes %d != %d * %d (no switch of the IMSI within one epoch)" % (
                path, n, imsi, npdu, nbytes, npdu, want))
    fact = {"file": path, "pduBytes": want, "lcid": DRB_LCID,
            "switchRows": sum(c["switchRows"] for c in per.values()),
            "equalityRows": sum(c["equalityRows"] for c in per.values()),
            "switchEvents": sum(len(v) for v in events.values()),
            "perImsi": dict(sorted(per.items(), key=lambda kv: int(kv[0]))), "problems": len(bad)}
    if not fact["equalityRows"]:
        bad.append("%s: no LCID-%d row with nTxPDUs > 0 outside a switch window" % (path, DRB_LCID))
    return bad, fact


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("traces", nargs="*")
    ap.add_argument("--pdcp-stats", metavar="NS3RUN_DIR")
    ap.add_argument("--require-clean", action="store_true")
    ap.add_argument("--reconnects-ok", action="store_true")
    ap.add_argument("--expect-nodes")
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.pdcp_stats is not None:
        if a.traces or a.require_clean or a.reconnects_ok or a.expect_nodes is not None:
            ap.error("--pdcp-stats takes only --out")
        try:
            bad, fact = pdcp_dl_pdu_bytes(a.pdcp_stats)
        except OSError as exc:
            bad, fact = ["cannot read %s: %s" % (a.pdcp_stats, exc)], None
        print(json.dumps(fact, sort_keys=True))
        if a.out:
            json.dump(fact, open(a.out, "w"), indent=1, sort_keys=True)
        for b in bad[:20]:
            print("PROBLEM: " + b)
        sys.exit(1 if bad else 0)
    if not a.traces:
        ap.error("no trace file")
    nodes = [summarize(p) for p in a.traces]
    bad = []
    if a.expect_nodes is not None:
        got = sorted(str(n["node"]) for n in nodes)
        if got != sorted(x for x in a.expect_nodes.split(",") if x):
            bad.append("trace nodes %s != expected %s" % (got, a.expect_nodes))
    for n in nodes:
        print("node %s (%s): samples=%d last_seq=%s gaps=%d ipcDropped_max=%d ues_max=%d hello=%d bye=%d %s" % (
            n["node"], n["kind"], n["samples"], n["last_seq"], n["seq_gaps"], n["ipc_dropped_max"], n["ues_max"],
            n["hello"], n["bye"], json.dumps(n["bye_msg"])))
        if a.require_clean:
            b = n["bye_msg"] or {}
            if n["hello"] != 1 or n["bye"] != 1:
                bad.append("node %s hello=%d bye=%d (want 1/1)" % (n["node"], n["hello"], n["bye"]))
            elif b["sent"] != b["built"] or b["droppedDisconnected"] or b["droppedBackpressure"] or n["ipc_dropped_max"]:
                bad.append("node %s sent %s != built %s or drops %s/%s" % (
                    n["node"], b["sent"], b["built"], b["droppedDisconnected"], b["droppedBackpressure"]))
            if n["seq_gaps"]:
                bad.append("node %s has %d seq gaps" % (n["node"], n["seq_gaps"]))
        if a.reconnects_ok:
            b = n["bye_msg"] or {}
            dd, db = b.get("droppedDisconnected") or 0, b.get("droppedBackpressure") or 0
            print("node %s: hello=%d (reconnects %d) droppedDisconnected=%d droppedBackpressure=%d" % (
                n["node"], n["hello"], max(n["hello"] - 1, 0), dd, db))
            if n["bye"] != 1 or n["hello"] < 1:
                bad.append("node %s hello=%d bye=%d (want hello >= 1, bye == 1)" % (n["node"], n["hello"], n["bye"]))
            elif b.get("built") != (b.get("sent") or 0) + dd + db:
                bad.append("node %s built %s != sent %s + droppedDisconnected %d + droppedBackpressure %d" % (
                    n["node"], b.get("built"), b.get("sent"), dd, db))
            elif n["last_seq"] != b["built"] - 1:
                bad.append("node %s last_seq %s != built-1 (%d)" % (n["node"], n["last_seq"], b["built"] - 1))
            if n["seq_gaps"]:
                bad.append("node %s has %d seq gaps" % (n["node"], n["seq_gaps"]))
    if a.out:
        json.dump(nodes, open(a.out, "w"), indent=1, sort_keys=True)
    for b in bad:
        print("PROBLEM: " + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

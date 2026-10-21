#!/usr/bin/env python3
"""trace-facts.py <trace.jsonl>... [--require-clean | --reconnects-ok] [--expect-nodes 1,2] [--out f.json]

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
"""
import argparse
import json
import sys


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("traces", nargs="+")
    ap.add_argument("--require-clean", action="store_true")
    ap.add_argument("--reconnects-ok", action="store_true")
    ap.add_argument("--expect-nodes")
    ap.add_argument("--out")
    a = ap.parse_args()
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

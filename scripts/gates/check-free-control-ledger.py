#!/usr/bin/env python3
"""check-free-control-ledger.py: P1 V3, a scripted free-run control run.

Inputs: the ns-3 control ledger (e2-control-ledger.jsonl), the controls the
stand-in agent sent (controls-sent.jsonl) and the controlAck lines it got
(control-acks.jsonl), all from ipc-null-sink --controls.

Pass when:
  - the first line is the header with delta-model "fixed 0";
  - there is exactly one ledger line per sent control, matched by
    (viaNodeId, ctlId), and the imsi/targetCell/afterSeq agree;
  - every line has applySimTimeNs - rxSimTimeNs = 0;
  - lines are sorted by rxSeq, then by the C4 key (imsi, viaNodeId,
    targetCell, ctlId) within a step;
  - exactly one controlAck per sent control, whose outcome, cause, seq and
    applySimTimeNs equal its ledger line;
  - the outcomes are applied or refused, and a refusal has a ledger cause.
Prints one JSON report; exit 0 on pass.

usage: check-free-control-ledger.py LEDGER SENT ACKS
"""
import json
import sys

CAUSES = {"alreadyOnTarget", "inHandover", "unknownImsi", "unknownTarget", "lteFallback", "late"}


def jsonl(path):
    with open(path) as f:
        return [json.loads(l) for l in f if l.strip()]


def main(ledger_path, sent_path, acks_path):
    rows = jsonl(ledger_path)
    sent = jsonl(sent_path)
    acks = jsonl(acks_path)
    problems = []
    header, lines = (rows[0], rows[1:]) if rows else ({}, [])
    if header.get("type") != "ledgerHeader" or header.get("delta-model") != "fixed 0":
        problems.append("missing or wrong ledger header: %r" % header)
    by_key = {}
    for l in lines:
        k = (l["viaNodeId"], l["ctlId"])
        if k in by_key:
            problems.append("two ledger lines for %r" % (k,))
        by_key[k] = l
        if l["applySimTimeNs"] - l["rxSimTimeNs"] != 0:
            problems.append("apply - rx != 0 for %r" % (k,))
        if l["outcome"] not in ("applied", "refused"):
            problems.append("bad outcome for %r" % (k,))
        if l["outcome"] == "refused" and l["cause"] not in CAUSES:
            problems.append("refusal without a ledger cause for %r" % (k,))
        if l["outcome"] == "applied" and l["cause"] != "":
            problems.append("applied with a cause for %r" % (k,))
    order = [(l["rxSeq"], l["imsi"], l["viaNodeId"], l["targetCell"], l["ctlId"]) for l in lines]
    if order != sorted(order):
        problems.append("ledger not sorted by (rxSeq, imsi, viaNodeId, targetCell, ctlId)")
    if len(lines) != len(sent):
        problems.append("ledger lines %d != controls sent %d" % (len(lines), len(sent)))
    for c in sent:
        l = by_key.get((c["nodeId"], c["ctlId"]))
        if l is None:
            problems.append("no ledger line for sent control %r" % c)
        elif (l["imsi"], l["targetCell"], l["afterSeq"]) != (c["imsi"], c["targetCellId"], c["afterSeq"]):
            problems.append("ledger line disagrees with sent control %r" % c)
    ack_keys = {}
    for a in acks:
        k = (a["nodeId"], a["ctlId"])
        ack_keys[k] = ack_keys.get(k, 0) + 1
        l = by_key.get(k)
        if l is None:
            problems.append("ack without ledger line %r" % (k,))
        elif (a["outcome"], a["cause"], a["seq"], a["applySimTimeNs"]) != (
                l["outcome"], l["cause"], l["rxSeq"], l["applySimTimeNs"]):
            problems.append("ack disagrees with ledger for %r" % (k,))
    for c in sent:
        n = ack_keys.get((c["nodeId"], c["ctlId"]), 0)
        if n != 1:
            problems.append("%d acks for control %r" % (n, (c["nodeId"], c["ctlId"])))
    report = {"ledger_lines": len(lines), "controls_sent": len(sent), "acks": len(acks),
              "outcomes": sorted({(l["outcome"], l["cause"]) for l in lines}),
              "problems": problems, "pass": not problems}
    json.dump(report, sys.stdout, indent=2)
    print()
    return 0 if not problems else 1


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(*sys.argv[1:]))

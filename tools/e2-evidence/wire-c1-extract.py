#!/usr/bin/env python3
"""wire-c1-extract.py: the live-only C1 components, read from the decoded E2AP wire.

  wire-c1-extract.py PCAP --node-ips node-ips.json --out-dir DIR
                     [--ledger e2-control-ledger.jsonl] [--decode-cmd "docker run --rm -i rc-decode:TAG"]
                     [--t0 EPOCH] [--t1 EPOCH]

Writes into DIR (a run's `extra/` directory):
  rc-multiset.json        one record per RICcontrolRequest, without the RIC request IDs and wall times:
                          step (ledger rxSeq), viaNode, style, action, imsi (AMF-UE-NGAP-ID), target key,
                          answer (ack|failure|none), cause, outcome octets; sorted. Steps come from joining
                          the k-th request to a node with the ledger line (viaNodeId, ctlId = k) the agent
                          numbered it with; the join is asserted one to one and consistent (imsi, target).
  kpm-headers.json        per node, the E2SM-KPM RICindicationHeader octets of its indications in order
                          (retransmissions dropped by association and TSN)
  collet-start-time.json  per node, octets 1-8 of every header (the NTP-format colletStartTime of the
                          agent's header encoding) as hex
  c1-extract-summary.json counts, the RIC-ID pairing (request <-> answer by requestorId, instanceId) and
                          every problem found; exit 1 when there is a problem.
RIC request IDs and frame times stay in rc-requests.json / rc-answers.json (diagnostics, not digested).
The RC decoder (tools/rc-decode) turns the control header/message octets into XER; a decode that is not
RC_OK with every octet consumed is a problem. KPM headers are compared as octets, so the decode of the
timestamp is not needed for equality.
--t0/--t1 keep only frames in [t0, t1) (a capture can span a whole gate).
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys

DISSECT = ["-d", "sctp.port==36422,e2ap"]
CAUSES = {  # CauseRICrequest, E2AP v03.00 9.2.1 (index order of the ASN.1 enumeration)
    "ran-function-id-invalid": 0, "action-not-supported": 1, "excessive-actions": 2, "duplicate-action": 3,
    "duplicate-event-trigger": 4, "function-resource-limit": 5, "request-id-unknown": 6,
    "inconsistent-action-subsequent-action-sequence": 7, "control-message-invalid": 8,
    "ric-call-process-id-invalid": 9, "control-timer-expired": 10, "control-failed-to-execute": 11,
    "system-not-ready": 12, "unspecified": 13}


def tshark(pcap, display_filter, fields):
    cmd = ["tshark", "-r", pcap] + DISSECT + ["-Y", display_filter, "-T", "fields", "-E", "separator=\t",
                                              "-E", "occurrence=a", "-E", "aggregator=,"]
    for f in fields:
        cmd += ["-e", f]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 and "cut short" not in res.stderr:
        sys.exit("tshark failed: " + res.stderr.strip()[-400:])
    return [r.split("\t") for r in res.stdout.splitlines()]


def split(col):
    return col.split(",") if col else []


def clean(h):
    return h.replace(":", "").upper()


def node_of(ip, ip2node):
    return ip2node.get(ip)


def in_window(t, t0, t1):
    return (t0 is None or t >= t0) and (t1 is None or t < t1)


def decode_rc(items, decode_cmd):
    """items: [(id, 'header'|'message', hex)] -> {id: xer text without whitespace}, problems."""
    if not items:
        return {}, []
    stdin = "".join("%s %s %s\n" % (i, kind, hexs) for i, kind, hexs in items)
    res = subprocess.run(shlex.split(decode_cmd), input=stdin, capture_output=True, text=True)
    out, problems = {}, []
    for line in res.stdout.splitlines():
        d = json.loads(line)
        if not d.get("ok"):
            problems.append("RC decode failed for %s: %s" % (d.get("id"), str(d)[:200]))
        out[d["id"]] = re.sub(r"\s+", "", d.get("xer", ""))
    for i, _, _ in items:
        if i not in out:
            problems.append("no decoder answer for %s (rc %s: %s)" % (i, res.returncode, res.stderr[-200:]))
    return out, problems


def rc_requests(pcap, ip2node, t0, t1):
    rows = tshark(pcap, "e2ap.procedureCode == 4 && e2ap.initiatingMessage_element",
                  ["frame.number", "frame.time_epoch", "ip.dst", "sctp.data_tsn_raw", "sctp.assoc_index",
                   "e2ap.ricRequestorID", "e2ap.ricInstanceID", "e2ap.RANfunctionID",
                   "e2ap.RICcontrolAckRequest", "e2ap.RICcontrolHeader", "e2ap.RICcontrolMessage"])
    out, seen, problems = [], set(), []
    for c in rows:
        c += [""] * (11 - len(c))
        frame, t, dst, tsn, assoc = c[0], float(c[1]), c[2], c[3], c[4]
        req, inst, func, ackreq, hdr, msg = map(split, c[5:11])
        if not in_window(t, t0, t1):
            continue
        n = len(hdr)
        if not (len(msg) == n and len(req) == n and len(inst) == n and len(func) == n):
            problems.append("frame %s: %d control PDUs but field counts differ" % (frame, n))
            continue
        tsns = split(tsn) if len(split(tsn)) == n else [""] * n
        for k in range(n):
            key = (assoc, tsns[k]) if tsns[k] else ("frame", frame, k)
            if key in seen:
                continue  # SCTP retransmission
            seen.add(key)
            out.append({"id": "f%s.%d" % (frame, k), "frame": int(frame), "t": t, "viaNode": node_of(dst, ip2node),
                        "dst": dst, "requestorId": int(req[k]), "instanceId": int(inst[k]),
                        "ranFunctionId": int(func[k]), "hdr": clean(hdr[k]), "msg": clean(msg[k]),
                        "ackRequestPresent": bool(split(ackreq))})
    return out, problems


def rc_answers(pcap, ip2node, t0, t1):
    rows = tshark(pcap, "e2ap.procedureCode == 4 && (e2ap.successfulOutcome_element || e2ap.unsuccessfulOutcome_element)",
                  ["frame.number", "frame.time_epoch", "ip.src", "sctp.data_tsn_raw", "sctp.assoc_index",
                   "e2ap.successfulOutcome_element", "e2ap.ricRequestorID", "e2ap.ricInstanceID",
                   "e2ap.ricRequest", "e2ap.RICcontrolOutcome"])
    out, seen, problems = [], set(), []
    for c in rows:
        c += [""] * (10 - len(c))
        frame, t, src, tsn, assoc = c[0], float(c[1]), c[2], c[3], c[4]
        okcol, req, inst, cause, outc = split(c[5]), split(c[6]), split(c[7]), split(c[8]), split(c[9])
        if not in_window(t, t0, t1):
            continue
        n = len(req)
        if len(inst) != n or n == 0:
            problems.append("frame %s: answer field counts differ" % frame)
            continue
        tsns = split(tsn) if len(split(tsn)) == n else [""] * n
        for k in range(n):
            key = (assoc, tsns[k]) if tsns[k] else ("frame", frame, k)
            if key in seen:
                continue
            seen.add(key)
            kind = "ack" if okcol else "failure"
            cs = cause[k] if k < len(cause) else ""
            out.append({"id": "f%s.%d" % (frame, k), "frame": int(frame), "t": t, "viaNode": node_of(src, ip2node),
                        "kind": kind, "requestorId": int(req[k]), "instanceId": int(inst[k]),
                        "cause": cs, "outcome": clean(outc[k]) if k < len(outc) else ""})
    return out, problems


def kpm_headers(pcap, ip2node, t0, t1):
    rows = tshark(pcap, "e2ap.procedureCode == 5 && e2ap.initiatingMessage_element",
                  ["frame.number", "frame.time_epoch", "ip.src", "sctp.data_tsn_raw", "sctp.assoc_index",
                   "e2ap.RICindicationHeader"])
    per, seen, problems = {}, set(), []
    for c in rows:
        c += [""] * (6 - len(c))
        frame, t, src, tsn, assoc, hdr = c[0], float(c[1]), c[2], c[3], c[4], split(c[5])
        if not in_window(t, t0, t1):
            continue
        tsns = split(tsn) if len(split(tsn)) == len(hdr) else [""] * len(hdr)
        for k, h in enumerate(hdr):
            key = (assoc, tsns[k]) if tsns[k] else ("frame", frame, k)
            if key in seen:
                continue
            seen.add(key)
            node = node_of(src, ip2node)
            if node is None:
                problems.append("indication frame %s from unknown source %s" % (frame, src))
                continue
            per.setdefault(str(node), []).append(clean(h))
    return per, problems


def parse_rc(hdr_x, msg_x):
    style = re.search(r"<ric-Style-Type>(\d+)<", hdr_x)
    action = re.search(r"<ric-ControlAction-ID>(\d+)<", hdr_x)
    amf = re.search(r"<amf-UE-NGAP-ID>(\d+)<", hdr_x)
    octs = re.search(r"<ranParameter-ID>4</ranParameter-ID><ranParameter-valueType><ranP-Choice-ElementFalse>"
                     r"<ranParameter-value><valueOctS>([0-9A-F]+)</valueOctS>", msg_x)
    target = octs.group(1) if octs else None
    return {"style": int(style.group(1)) if style else None, "action": int(action.group(1)) if action else None,
            "imsi": int(amf.group(1)) if amf else None, "targetOctets": target,
            "targetKey": target[-10:] if target and len(target) == 18 else None,
            "targetCell": int(target[-2:], 16) if target and len(target) == 18 else None}


def cause_name(raw):
    raw = (raw or "").strip()
    if raw in CAUSES:
        return raw
    if raw.isdigit():
        for k, v in CAUSES.items():
            if v == int(raw):
                return k
    return raw


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("pcap")
    ap.add_argument("--node-ips", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--ledger")
    ap.add_argument("--decode-cmd", default="docker run --rm -i rc-decode")
    ap.add_argument("--t0", type=float)
    ap.add_argument("--t1", type=float)
    a = ap.parse_args()
    ip2node = {ip: int(n) for n, ips in json.load(open(a.node_ips)).items() for ip in ips}
    os.makedirs(a.out_dir, exist_ok=True)
    problems = []

    reqs, p = rc_requests(a.pcap, ip2node, a.t0, a.t1)
    problems += p
    ans, p = rc_answers(a.pcap, ip2node, a.t0, a.t1)
    problems += p
    items = []
    for r in reqs:
        items += [(r["id"] + ".h", "header", r["hdr"]), (r["id"] + ".m", "message", r["msg"])]
    xers, p = decode_rc(items, a.decode_cmd)
    problems += p
    for r in reqs:
        r.update(parse_rc(xers.get(r["id"] + ".h", ""), xers.get(r["id"] + ".m", "")))
        if r["style"] != 3 or r["action"] != 1 or r["targetKey"] is None or r["imsi"] is None:
            problems.append("request %s does not decode to style 3 / action 1 / a 9-octet target" % r["id"])
        if r["viaNode"] is None:
            problems.append("request %s goes to unknown address %s" % (r["id"], r["dst"]))

    # exactly one terminal answer per request, paired by the RIC request ID (requestorId, instanceId)
    by_id = {}
    for r in reqs:
        by_id.setdefault((r["requestorId"], r["instanceId"]), []).append(r)
    ans_by_id = {}
    for x in ans:
        ans_by_id.setdefault((x["requestorId"], x["instanceId"]), []).append(x)
    for k, rs in by_id.items():
        if len(rs) != 1:
            problems.append("RIC request ID %r used by %d requests" % (k, len(rs)))
    for k, xs in ans_by_id.items():
        if k not in by_id:
            problems.append("answer for unknown RIC request ID %r" % (k,))
        elif len(xs) != 1:
            problems.append("RIC request ID %r has %d terminal answers" % (k, len(xs)))
    for r in reqs:
        xs = ans_by_id.get((r["requestorId"], r["instanceId"]), [])
        r["answer"] = xs[0]["kind"] if len(xs) == 1 else ("none" if not xs else "multiple")
        r["cause"] = cause_name(xs[0]["cause"]) if len(xs) == 1 and xs[0]["kind"] == "failure" else ""
        r["outcome"] = xs[0]["outcome"] if len(xs) == 1 and xs[0]["kind"] == "ack" else ""
        if r["answer"] == "ack" and r["outcome"] != "0000":
            problems.append("ACK of %r does not carry ControlOutcome Format 1 (0000): %r" % (
                (r["requestorId"], r["instanceId"]), r["outcome"]))

    # join with the ledger: the k-th request to a node is the agent's ctlId k
    multiset = []
    if a.ledger:
        rows = []
        if os.path.exists(a.ledger):
            rows = [json.loads(l) for l in open(a.ledger) if l.strip()][1:]
        led = {(x["viaNodeId"], x["ctlId"]): x for x in rows}
        counters = {}
        for r in sorted(reqs, key=lambda q: (q["t"], q["frame"])):
            counters[r["viaNode"]] = counters.get(r["viaNode"], 0) + 1
            r["ctlId"] = counters[r["viaNode"]]
        agent_failed = 0
        for r in reqs:
            x = led.pop((r["viaNode"], r["ctlId"]), None)
            if x is None:
                agent_failed += 1  # answered by the agent itself (static reject): no ledger line, no step
                r["step"] = None
                continue
            r["step"] = x["rxSeq"]
            if x["imsi"] != r["imsi"] or x["targetCell"] != r["targetCell"]:
                problems.append("request %s (node %s ctl %d) imsi/target %s/%s differ from ledger %s/%s" % (
                    r["id"], r["viaNode"], r["ctlId"], r["imsi"], r["targetCell"], x["imsi"], x["targetCell"]))
            want = "ack" if x["outcome"] == "applied" else "failure"
            if r["answer"] != want:
                problems.append("request %s: ledger %s but wire answer %s" % (r["id"], x["outcome"], r["answer"]))
        for k in sorted(led):
            problems.append("ledger line %r has no request on the wire" % (k,))
    for r in sorted(reqs, key=lambda q: (q.get("step") if q.get("step") is not None else -1, q["viaNode"] or 0,
                                         q["imsi"] or 0, q["targetCell"] or 0, q["t"])):
        multiset.append({"step": r.get("step"), "viaNode": r["viaNode"], "style": r["style"], "action": r["action"],
                         "imsi": r["imsi"], "targetKey": r["targetKey"], "answer": r["answer"],
                         "cause": r["cause"], "outcome": r["outcome"]})

    per, p = kpm_headers(a.pcap, ip2node, a.t0, a.t1)
    problems += p
    collet = {n: [h[2:18] for h in hs] for n, hs in per.items()}
    for n, hs in per.items():
        for h in hs:
            if len(h) < 18:
                problems.append("node %s: KPM header shorter than 9 octets: %s" % (n, h))

    def dump(name, obj):
        with open(os.path.join(a.out_dir, name), "w") as f:
            json.dump(obj, f, indent=1, sort_keys=True)
            f.write("\n")
    dump("rc-multiset.json", multiset)
    dump("kpm-headers.json", per)
    dump("collet-start-time.json", collet)
    dump("rc-requests.json", reqs)
    dump("rc-answers.json", ans)
    summary = {"rcRequests": len(reqs), "rcAnswers": len(ans),
               "acks": sum(1 for x in ans if x["kind"] == "ack"), "failures": sum(1 for x in ans if x["kind"] == "failure"),
               "kpmHeadersByNode": {n: len(h) for n, h in sorted(per.items())}, "problems": problems,
               "pass": not problems}
    dump("c1-extract-summary.json", summary)
    print(json.dumps({k: v for k, v in summary.items() if k != "problems"}), file=sys.stderr)
    for q in problems[:20]:
        print("problem: " + q, file=sys.stderr)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

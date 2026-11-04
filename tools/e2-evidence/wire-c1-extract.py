#!/usr/bin/env python3
"""wire-c1-extract.py: the live-only C1 components, read from the decoded E2AP wire.

  wire-c1-extract.py PCAP --node-ips node-ips.json --facts FACTS --out-dir DIR
                     [--ledger e2-control-ledger.jsonl --ue-context-dir TRACE_DIR]
                     [--decode-cmd "docker run --rm -i rc-decode:TAG"]
                     [--t0 EPOCH] [--t1 EPOCH] [--expect-requests N] [--expect-agent-local N]

Writes into DIR (a run's `extra/` directory):
  rc-multiset.json        one record per RICcontrolRequest, without the RIC request IDs and wall times:
                          step (ledger rxSeq), viaNode, style, action, ueId (the header's en-gNB-UEID as
                          {"type": "en-gNB-UEID", "mEnbUeX2apId": N, "globalEnbId": {"plmn": "00F110",
                          "macroEnbId": "%05X"}}; it must carry no optional member), target key (the
                          last 10 hex of RAN parameter 4, which must be the APER NR-CGI 0000F110 + gNB ID (8 hex)
                          + 10: PLMN 001/01, cell part 1, pad 0; the TS xApp cell key), answer (ack|failure|none),
                          cause, outcome octets; sorted (step, viaNode, mEnbUeX2apId, targetCell, t). Steps come
                          from joining the k-th request to a node with the ledger line (viaNodeId, ctlId = k) the
                          agent numbered it with; the join is asserted one to one and consistent: a line with
                          imsi != 0 needs I(wire ueId) = its imsi, where I(X, M) is the IMSI whose (lteRnti,
                          mnCellId) in the run's e2-ue-context files (--ue-context-dir) equals (mEnbUeX2apId, macro
                          eNB ID); a line with imsi 0 must be refused unknownUe; the e2-pacing-log.jsonl record of
                          the line's (viaNodeId, ctlId) carries the wire ueId's {mEnbUeX2apId, mnCellId}; target
                          and answer as before. Every request must be Style 5 / action 3 with an en-gNB-UEID.
  kpm-headers.json        per node, the E2SM-KPM RICindicationHeader octets of its indications in order
                          (retransmissions dropped by association and TSN)
  collet-start-time.json  per node, octets 1-8 of every header (the NTP-format colletStartTime of the
                          agent's header encoding) as hex
  c1-extract-summary.json counts, the RIC-ID pairing (request <-> answer by requestorId, instanceId), the
                          answer count identity (answers = ledger lines + agent-local answers), the C5
                          summary (pairsByReqId; answerViaNodeId: each answer comes from the node the request
                          went to) and every problem found; exit 1 when there is a problem.
RIC request IDs and frame times stay in rc-requests.json / rc-answers.json (diagnostics, not digested). There each
request also carries viaMeid: the meid (e2term's rendering, as lib.sh meid_of) of the Global E2 Node ID in the E2
Setup Request of the SCTP association (agent IP, port; the latest INIT_ACK at or before the request, FACTS = the
e2ap-pcap-facts.py sheet of PCAP) that carried it; viaMeid != meid_of(viaNode) is a problem and the summary
records viaMeidEqualsNode. A request's viaNode comes from its destination IP and an answer's from its source IP;
an IP that node-ips.json lists for more than one node is a problem for every request or answer to or from it.
The RC decoder (tools/rc-decode) turns the control header/message octets into XER; a decode that is not
RC_OK with every octet consumed is a problem. Every ACK's RIC Control Outcome goes through the same decoder
and must decode to E2SM-RC Control Outcome Format 1. Every request needs exactly one terminal answer.
--expect-requests: the number of requests the run must carry; --expect-agent-local (default 0 when a ledger
is given): requests the agent answered itself, without a ledger line. KPM headers are compared as octets, so the decode of the
timestamp is not needed for equality.
--t0/--t1 keep only frames in [t0, t1) (a capture can span a whole gate).
--self-test checks the UE ID parse, the meid rendering and the shared-IP map on synthetic input.
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys

# E2AP is selected by its SCTP PPID 70 (O-RAN E2GAP v08.00 section 6.1); no port decode-as is forced.
DISSECT = []
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


def ip_map(node_ips):
    """node-ips.json {node: [ip, ...]} -> {ip: node}, an IP listed for several nodes mapped to the tuple of them."""
    multi = {}
    for n, ips in node_ips.items():
        for ip in ips:
            multi.setdefault(ip, set()).add(int(n))
    return {ip: (next(iter(ns)) if len(ns) == 1 else tuple(sorted(ns))) for ip, ns in multi.items()}


def node_of(ip, ip2node):
    """The node of an IP; None for an unknown or a shared IP (shared_ip reports the latter)."""
    v = ip2node.get(ip)
    return v if isinstance(v, int) else None


def shared_ip(ip, ip2node):
    v = ip2node.get(ip)
    return v if isinstance(v, tuple) else None


def meid_of(node):
    """lib.sh meid_of: the eNB (node 1) and the en-gNBs (node n >= 2) of the testbed."""
    return "enB_macro_001_001_000001" if node == 1 else "en_gnb_001_001_%08x" % node


def plmn_digits(plmn):
    """(MCC, MNC) of a PLMN Identity in hex (3GPP TS 24.008 BCD order), each zero-padded to 3 digits as e2term's
    run name does; None for a malformed PLMN."""
    if not isinstance(plmn, str) or not re.fullmatch(r"[0-9a-fA-F]{6}", plmn):
        return None
    o = bytes.fromhex(plmn)
    d = [o[0] & 15, o[0] >> 4, o[1] & 15, o[1] >> 4, o[2] & 15, o[2] >> 4]
    mcc, mnc = d[0:3], [d[4], d[5]] + ([d[3]] if d[3] != 15 else [])
    if any(x > 9 for x in mcc + mnc):
        return None
    return "".join(map(str, mcc)), "".join(map(str, mnc)).zfill(3)


def render_meid(setup):
    """e2term's RAN name of an E2 Setup Request's Global E2 Node ID (fact-sheet fields e2node_type, plmn, node_id,
    node_id_bits), for the node kinds of this testbed; None for any other kind."""
    pd = plmn_digits(setup.get("plmn"))
    nid, bits, kind = setup.get("node_id"), setup.get("node_id_bits"), setup.get("e2node_type")
    if pd is None or not isinstance(nid, int):
        return None
    if kind == "en-gNB" and bits == 32:
        return "en_gnb_%s_%s_%08x" % (pd[0], pd[1], nid)
    if kind == "eNB" and bits == 20:
        return "enB_macro_%s_%s_%06x" % (pd[0], pd[1], nid)
    return None


def _module(name, filename):
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), filename)
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, path
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def assoc_meid(facts):
    """meid_at(ip, port, t): (the rendered meid of the E2 Setup Request on the SCTP association (ip, port) with the
    latest INIT_ACK at or before t, or None; problem text or None)."""
    assocs, _ = _module("e2_facts_query", "e2-facts-query.py").build_assocs(facts)
    by = {}
    for x in assocs:  # sorted by INIT_ACK time
        by.setdefault((x["ip"], x["sport"]), []).append(x)

    def meid_at(ip, port, t):
        best = None
        for x in by.get((ip, port), []):
            if x["t_init_ack"] <= t:
                best = x
        if best is None:
            return None, "no SCTP association of %s:%s at t %.3f in the fact sheet" % (ip, port, t)
        if best["setup_request"] is None:
            return None, "association %s:%s has no E2 Setup Request" % (ip, port)
        m = render_meid(best["setup_request"])
        return m, (None if m else "association %s:%s: E2 Setup Global E2 Node ID %r has no meid rendering" % (
            ip, port, {k: best["setup_request"].get(k) for k in ("e2node_type", "plmn", "node_id", "node_id_bits")}))
    return meid_at


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
                   "e2ap.RICcontrolAckRequest", "e2ap.RICcontrolHeader", "e2ap.RICcontrolMessage", "sctp.dstport"])
    out, seen, problems = [], set(), []
    for c in rows:
        c += [""] * (12 - len(c))
        frame, t, dst, tsn, assoc = c[0], float(c[1]), c[2], c[3], c[4]
        req, inst, func, ackreq, hdr, msg = map(split, c[5:11])
        dport = int(split(c[11])[0]) if split(c[11]) else None
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
            if shared_ip(dst, ip2node):
                problems.append("request f%s.%d goes to %s, which node-ips.json lists for nodes %s" % (
                    frame, k, dst, list(shared_ip(dst, ip2node))))
            out.append({"id": "f%s.%d" % (frame, k), "frame": int(frame), "t": t, "viaNode": node_of(dst, ip2node),
                        "dst": dst, "dport": dport, "requestorId": int(req[k]), "instanceId": int(inst[k]),
                        "ranFunctionId": int(func[k]), "hdr": clean(hdr[k]), "msg": clean(msg[k]),
                        "ackRequestPresent": bool(split(ackreq))})
    return out, problems


def rc_answers(pcap, ip2node, t0, t1):
    rows = tshark(pcap, "e2ap.procedureCode == 4 && (e2ap.successfulOutcome_element || e2ap.unsuccessfulOutcome_element)",
                  ["frame.number", "frame.time_epoch", "ip.src", "sctp.data_tsn_raw", "sctp.assoc_index",
                   "e2ap.successfulOutcome_element", "e2ap.ricRequestorID", "e2ap.ricInstanceID",
                   "e2ap.ricRequest", "e2ap.RICcontrolOutcome", "sctp.srcport"])
    out, seen, problems = [], set(), []
    for c in rows:
        c += [""] * (11 - len(c))
        sport = int(split(c[10])[0]) if split(c[10]) else None
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
            if shared_ip(src, ip2node):
                problems.append("answer f%s.%d comes from %s, which node-ips.json lists for nodes %s" % (
                    frame, k, src, list(shared_ip(src, ip2node))))
            kind = "ack" if okcol else "failure"
            cs = cause[k] if k < len(cause) else ""
            out.append({"id": "f%s.%d" % (frame, k), "frame": int(frame), "t": t, "viaNode": node_of(src, ip2node),
                        "src": src, "sport": sport, "kind": kind, "requestorId": int(req[k]), "instanceId": int(inst[k]),
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


# RAN parameter 4 (NR CGI) of the control message, and the only form its value may take: the APER NR-CGI, 9 octets
# = 00 | PLMN 00F110 | NR Cell Identity (gNB ID, 32 bits, then cell part 1, 4 bits) | 4 zero pad bits.
P4_RE = re.compile(r"<ranParameter-ID>4</ranParameter-ID><ranParameter-valueType><ranP-Choice-ElementFalse>"
                   r"<ranParameter-value><valueOctS>([0-9A-F]+)</valueOctS>")
NRCGI_RE = re.compile(r"0000F110([0-9A-F]{8})10")


# the header's UE ID when it is an en-gNB-UEID with exactly m-eNB-UE-X2AP-ID and globalENB-ID {pLMN, macro eNB ID}
# (whitespace-free XER): any optional member, another eNB-ID kind or another UEID CHOICE fails the full match
UEID_EN_GNB_RE = re.compile(r"<ueID><en-gNB-UEID><m-eNB-UE-X2AP-ID>(\d+)</m-eNB-UE-X2AP-ID><globalENB-ID>"
                            r"<pLMNIdentity>([0-9A-F]{6})</pLMNIdentity><eNB-ID><macro-eNB-ID>([01]{20})</macro-eNB-ID>"
                            r"</eNB-ID></globalENB-ID></en-gNB-UEID></ueID>")
UE_PLMN = "00F110"


def parse_ue_id(hdr_x):
    """The en-gNB-UEID of a control header XER in the R-2 representation, or None."""
    blocks = re.findall(r"<ueID>.*?</ueID>", hdr_x)
    m = UEID_EN_GNB_RE.fullmatch(blocks[0]) if len(blocks) == 1 else None
    if not m or m.group(2) != UE_PLMN or int(m.group(1)) > 4095:
        return None
    return {"type": "en-gNB-UEID", "mEnbUeX2apId": int(m.group(1)),
            "globalEnbId": {"plmn": m.group(2), "macroEnbId": "%05X" % int(m.group(3), 2)}}


def parse_rc(hdr_x, msg_x):
    """Style, action, UE ID and target of one control. The target counts only when the message holds exactly one
    RAN parameter 4, RAN parameters 1, 2 and 3 appear before it, and its value is the APER NR-CGI; targetKey is
    then its last 10 hex digits and targetCell the gNB ID. Otherwise both are None (a problem in main)."""
    style = re.search(r"<ric-Style-Type>(\d+)<", hdr_x)
    action = re.search(r"<ric-ControlAction-ID>(\d+)<", hdr_x)
    p4 = list(P4_RE.finditer(msg_x))
    target = p4[0].group(1) if len(p4) == 1 else None
    before = msg_x[:p4[0].start()] if len(p4) == 1 else ""
    path = all("<ranParameter-ID>%d</ranParameter-ID>" % i in before for i in (1, 2, 3))
    cgi = NRCGI_RE.fullmatch(target) if target and path else None
    return {"style": int(style.group(1)) if style else None, "action": int(action.group(1)) if action else None,
            "ueId": parse_ue_id(hdr_x), "targetOctets": target,
            "targetKey": target[-10:] if cgi else None,
            "targetCell": int(cgi.group(1), 16) if cgi else None}


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
    ap.add_argument("--facts", help="the e2ap-pcap-facts.py sheet of PCAP (the association of each request)")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--ledger")
    ap.add_argument("--ue-context-dir", help="the run's trace/ (e2-ue-context-*.jsonl and e2-pacing-log.jsonl)")
    ap.add_argument("--decode-cmd", default="docker run --rm -i rc-decode")
    ap.add_argument("--t0", type=float)
    ap.add_argument("--t1", type=float)
    ap.add_argument("--expect-requests", type=int)
    ap.add_argument("--expect-agent-local", type=int, default=0)
    a = ap.parse_args()
    node_ips = json.load(open(a.node_ips))
    ip2node = ip_map(node_ips)
    # the KPM headers keep the plain map (an IP listed twice goes to the last node listed)
    kpm_ip2node = {ip: int(n) for n, ips in node_ips.items() for ip in ips}
    os.makedirs(a.out_dir, exist_ok=True)
    problems = []
    meid_at = assoc_meid(json.load(open(a.facts))) if a.facts else None
    ucm = _module("ue_context_map", "ue-context-map.py") if a.ue_context_dir else None
    cmap = ucm.UeContextMap(a.ue_context_dir) if ucm else None
    pacing = ucm.pacing_controls(a.ue_context_dir) if ucm else {}
    if cmap is not None and cmap.problems:
        problems += ["UE context: " + q for q in cmap.problems[:10]]

    reqs, p = rc_requests(a.pcap, ip2node, a.t0, a.t1)
    problems += p
    ans, p = rc_answers(a.pcap, ip2node, a.t0, a.t1)
    problems += p
    items = []
    for r in reqs:
        items += [(r["id"] + ".h", "header", r["hdr"]), (r["id"] + ".m", "message", r["msg"])]
    for x in ans:
        if x["kind"] == "ack":
            items.append((x["id"] + ".o", "outcome", x["outcome"]))
    xers, p = decode_rc(items, a.decode_cmd)
    problems += p
    for r in reqs:
        r.update(parse_rc(xers.get(r["id"] + ".h", ""), xers.get(r["id"] + ".m", "")))
        if r["style"] != 5 or r["action"] != 3 or r["targetKey"] is None or r["ueId"] is None:
            problems.append("request %s does not decode to style 5 / action 3 / an en-gNB-UEID / an APER NR-CGI target"
                            % r["id"])
        if r["viaNode"] is None and not shared_ip(r["dst"], ip2node):
            problems.append("request %s goes to unknown address %s" % (r["id"], r["dst"]))
        if meid_at is None:
            r["viaMeid"] = None
            problems.append("request %s: no --facts, so its association meid cannot be checked" % r["id"])
        else:
            r["viaMeid"], why = meid_at(r["dst"], r["dport"], r["t"])
            if why:
                problems.append("request %s: %s" % (r["id"], why))
            elif r["viaNode"] is not None and r["viaMeid"] != meid_of(r["viaNode"]):
                problems.append("request %s: association meid %s, meid_of(viaNode %d) %s" % (
                    r["id"], r["viaMeid"], r["viaNode"], meid_of(r["viaNode"])))

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
        if r["answer"] not in ("ack", "failure"):
            problems.append("request %s %r has %s terminal answer" % (r["id"], (r["requestorId"], r["instanceId"]), r["answer"]))
        if r["answer"] == "ack" and r["outcome"] != "0000":
            problems.append("ACK of %r does not carry ControlOutcome Format 1 (0000): %r" % (
                (r["requestorId"], r["instanceId"]), r["outcome"]))
        if r["answer"] == "ack":
            x = xs[0]
            x["outcomeXer"] = xers.get(x["id"] + ".o", "")
            if "<controlOutcome-Format1>" not in x["outcomeXer"]:
                problems.append("ACK of %r: the RIC Control Outcome does not decode to Format 1" % (
                    (r["requestorId"], r["instanceId"]),))
        if len(xs) == 1 and xs[0]["viaNode"] != r["viaNode"]:
            r["answerFromOtherNode"] = xs[0]["viaNode"]
            problems.append("request %s went to node %s but its answer came from node %s" % (
                r["id"], r["viaNode"], xs[0]["viaNode"]))
    if a.expect_requests is not None and len(reqs) != a.expect_requests:
        problems.append("%d RICcontrolRequests on the wire, expected %d" % (len(reqs), a.expect_requests))
    pairs_by_req_id = (all(len(rs) == 1 for rs in by_id.values()) and all(k in by_id for k in ans_by_id)
                       and all(r["answer"] in ("ack", "failure") for r in reqs))
    answer_via_node = all("answerFromOtherNode" not in r for r in reqs) and all(
        r["answer"] in ("ack", "failure") for r in reqs)

    # join with the ledger: the k-th request to a node is the agent's ctlId k
    multiset, c2 = [], None
    if a.ledger and cmap is None:
        problems.append("--ledger without --ue-context-dir: the wire UE IDs cannot be joined to the ledger's IMSIs")
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
            ue = ucm.x2_of(r["ueId"]) if ucm and r["ueId"] else None
            r["ueImsi"] = cmap.imsi_of(*ue) if cmap is not None and ue else None
            if x["imsi"] != 0 and r["ueImsi"] != x["imsi"]:
                problems.append("request %s (node %s ctl %d): I(ueId %s) = %s, ledger imsi %s" % (
                    r["id"], r["viaNode"], r["ctlId"], ue, r["ueImsi"], x["imsi"]))
            if x["imsi"] == 0 and (x["outcome"], x["cause"]) != ("refused", "unknownUe"):
                problems.append("request %s (node %s ctl %d): ledger imsi 0 but %s/%s, not refused unknownUe" % (
                    r["id"], r["viaNode"], r["ctlId"], x["outcome"], x["cause"]))
            recs = pacing.get((r["viaNode"], r["ctlId"]), [])
            rue = ucm.x2_of(recs[0].get("ueId")) if ucm and len(recs) == 1 else None
            if len(recs) != 1 or rue is None or rue != ue:
                problems.append("request %s (node %s ctl %d): wire ueId %s, e2-pacing-log records %s" % (
                    r["id"], r["viaNode"], r["ctlId"], ue, [q.get("ueId") for q in recs]))
            if x["targetCell"] != r["targetCell"]:
                problems.append("request %s (node %s ctl %d) target %s differs from ledger %s" % (
                    r["id"], r["viaNode"], r["ctlId"], r["targetCell"], x["targetCell"]))
            want = "ack" if x["outcome"] == "applied" else "failure"
            if r["answer"] != want:
                problems.append("request %s: ledger %s but wire answer %s" % (r["id"], x["outcome"], r["answer"]))
        for k in sorted(led):
            problems.append("ledger line %r has no request on the wire" % (k,))
        if agent_failed != a.expect_agent_local:
            problems.append("%d requests answered by the agent itself (no ledger line), expected %d" % (
                agent_failed, a.expect_agent_local))
        c2 = {"answers": len(ans), "ledgerLines": len(rows), "agentLocal": agent_failed,
              "holds": len(ans) == len(rows) + agent_failed}
        if not c2["holds"]:
            problems.append("answers %d != ledger lines %d + agent-local %d" % (len(ans), len(rows), agent_failed))
    for r in sorted(reqs, key=lambda q: (q.get("step") if q.get("step") is not None else -1, q["viaNode"] or 0,
                                         (q["ueId"] or {}).get("mEnbUeX2apId", -1), q["targetCell"] or 0, q["t"])):
        multiset.append({"step": r.get("step"), "viaNode": r["viaNode"], "style": r["style"], "action": r["action"],
                         "ueId": r["ueId"], "targetKey": r["targetKey"], "answer": r["answer"],
                         "cause": r["cause"], "outcome": r["outcome"]})

    per, p = kpm_headers(a.pcap, kpm_ip2node, a.t0, a.t1)
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
               "kpmHeadersByNode": {n: len(h) for n, h in sorted(per.items())}, "c2": c2,
               "c5": {"pairsByReqId": pairs_by_req_id, "answerViaNodeId": answer_via_node},
               "viaMeidEqualsNode": bool(reqs) and all(r.get("viaMeid") is not None and r["viaNode"] is not None
                                                       and r["viaMeid"] == meid_of(r["viaNode"]) for r in reqs),
               "problems": problems,
               "pass": not problems}
    dump("c1-extract-summary.json", summary)
    print(json.dumps({k: v for k, v in summary.items() if k != "problems"}), file=sys.stderr)
    for q in problems[:20]:
        print("problem: " + q, file=sys.stderr)
    return 0 if not problems else 1


def self_test():
    ue = ("<ueID><en-gNB-UEID><m-eNB-UE-X2AP-ID>%s</m-eNB-UE-X2AP-ID><globalENB-ID><pLMNIdentity>%s</pLMNIdentity>"
          "<eNB-ID><macro-eNB-ID>%s</macro-eNB-ID></eNB-ID></globalENB-ID>%s</en-gNB-UEID></ueID>")
    hdr = lambda x2="3", plmn="00F110", macro="0" * 19 + "1", extra="": (
        "<E2SM-RC-ControlHeader><ric-controlHeader-formats><controlHeader-Format1>" + ue % (x2, plmn, macro, extra) +
        "<ric-Style-Type>5</ric-Style-Type><ric-ControlAction-ID>3</ric-ControlAction-ID></controlHeader-Format1>"
        "</ric-controlHeader-formats></E2SM-RC-ControlHeader>")
    want = {"type": "en-gNB-UEID", "mEnbUeX2apId": 3, "globalEnbId": {"plmn": "00F110", "macroEnbId": "00001"}}
    gnb = "<ueID><gNB-UEID><amf-UE-NGAP-ID>3</amf-UE-NGAP-ID></gNB-UEID></ueID>"
    cases = [
        ("an en-gNB-UEID header parses", parse_ue_id(hdr()) == want and parse_rc(hdr(), "")["style"] == 5),
        ("an optional member fails", parse_ue_id(hdr(extra="<gNB-CU-UE-F1AP-ID>1</gNB-CU-UE-F1AP-ID>")) is None),
        ("another PLMN fails", parse_ue_id(hdr(plmn="00F120")) is None),
        ("an X2AP ID above 4095 fails", parse_ue_id(hdr(x2="4096")) is None),
        ("a gNB-UEID (the IMSI form) fails", parse_ue_id(gnb) is None),
        ("the macro eNB ID is rendered %05X", parse_ue_id(hdr(macro="0" * 15 + "11111"))["globalEnbId"]["macroEnbId"] == "0001F"),
        ("en-gNB meid", render_meid({"e2node_type": "en-gNB", "plmn": "00f110", "node_id": 2, "node_id_bits": 32})
         == meid_of(2) == "en_gnb_001_001_00000002"),
        ("eNB meid", render_meid({"e2node_type": "eNB", "plmn": "00f110", "node_id": 1, "node_id_bits": 20})
         == meid_of(1) == "enB_macro_001_001_000001"),
        ("a gNB (NR standalone) has no rendering here", render_meid({"e2node_type": "gNB", "plmn": "00f110",
                                                                     "node_id": 2, "node_id_bits": 32}) is None),
        ("a shared IP maps to no node", node_of("10.0.0.2", ip_map({"2": ["10.0.0.2"], "3": ["10.0.0.2"]})) is None
         and shared_ip("10.0.0.2", ip_map({"2": ["10.0.0.2"], "3": ["10.0.0.2"]})) == (2, 3)),
        ("an unshared IP maps to its node", node_of("10.0.0.3", ip_map({"2": ["10.0.0.2"], "3": ["10.0.0.3"]})) == 3),
    ]
    for name, ok in cases:
        print("%s %s" % ("ok  " if ok else "FAIL", name))
    ok = all(c[1] for c in cases)
    print("wire-c1-extract self-test: %s" % ("ok" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    sys.exit(main())

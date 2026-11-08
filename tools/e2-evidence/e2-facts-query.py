#!/usr/bin/env python3
"""e2-facts-query.py <facts.json> <query> [options]

Gate assertions over the fact sheet from e2ap-pcap-facts.py. Each query prints
its evidence and exits 0 (pass) or 1 (fail).

  setup-request   --func-id N --oid OID --short-name S --node-type T --node-id N --node-id-bits B --plmn HEX
                  [--not-node-id-hex HEX]   every E2SetupRequest's Global E2 Node ID (read inside its
                                                    id-GlobalE2node-ID IE) has that CHOICE (en-gNB, eNB, ...),
                                                    PLMN, ID and bit length; the ID is not the reference node's
  setup-response  --func-id N
  subscription    --func-id N [--after EPOCH]      request (RIC->agent) answered by a response
  sub-period      --period-ms P [--granul-ms G] [--after EPOCH]   every request has KPM reportingPeriod P (and every
                                                    action granulPeriod G) and is answered by a response
                                                    (granulPeriod only decodes where tshark's KPM v3 dissector gets
                                                    through the action definition; it stops on some Format 3 lists,
                                                    so gates evidence the granularity by records per indication)
  sub-actions     (--nodes L | --node-ips F) --decoded D [--after EPOCH]   every RIC SUBSCRIPTION REQUEST of the fact
                                                    sheet in the window is on an association whose E2 Setup node is an
                                                    expected node (one on no association, on an association without an
                                                    E2SetupRequest inside the capture or of another node is a problem)
                                                    and, with C = the served cells of that association's E2 Setup X2
                                                    request parts (identity and agreement rule; never 0), has exactly
                                                    C+1 RICaction-ToBeSetup items: IDs 1..C report actions in E2SM-KPM
                                                    Format 1 whose cellGlobalID names a served cell of the node's kind
                                                    (NR on an en-gNB, E-UTRA on the eNB), each cell once, ID C+1 a
                                                    report action in Format 3; the RIC SUBSCRIPTION RESPONSE admits all
                                                    C+1; every expected node received >= 1 request. D is the capture's
                                                    asn1-indep decode (e2-sub-setup-decode.py), which decides every
                                                    value (kpm-action-subscription-judges.py)
  ind-actions     (--nodes L | --node-ips F) --decoded D --ind-actions A --records R --lines L --extract-summary S
                  --map M [--after EPOCH]   every RIC INDICATION in the window (A: pcap-to-lines.py --actions rows, L
                                                    its lines, S its stderr summary, R kpimon-decode-harness --records
                                                    over L) lies on an expected node's association and joins its
                                                    subscription (the latest successful RIC SUBSCRIPTION RESPONSE there
                                                    with its requestor, instance and RAN function ID); its RICactionID
                                                    is admitted; under a Format 1 action the message is Format 1 and
                                                    every measData item's ns3.nodeId (position from M's cell list) is
                                                    the node, under the Format 3 action it is Format 2; every admitted
                                                    action received >= 1 indication; no extractor row skipped, every
                                                    line has one row and one record, every record decodes RC_OK
                                                    (kpm-indication-action-judges.py)
  sub-failure     --cause GROUP:INDEX [--after EPOCH]   a request answered by a RIC SUBSCRIPTION FAILURE with that
                                                    cause, and no request in the window answered by a response
  assoc-start     --service-ip IP --before EPOCH [--sctp-port 36422]   one ESTABLISHED association per node before EPOCH
  no-abort        --from EPOCH --to EPOCH           ABORT chunks inside the window (also lists the rest)
  post-delete     --service-ip IP --after EPOCH --func-id N [--timeline-out F]
  indications                                       every node's associations carried RICindications
  service-ip      --service-ip IP                   every agent INIT in the capture went to the Service IP
  associations    [--after EPOCH]                   list associations (informational)
  --self-test                                       the sub-actions and ind-actions queries on synthetic fact sheets
                                                    and decodes
  ppid            [--nodes L | --node-ips F] [--source-ip IP]   (facts from e2ap-pcap-facts.py --ppid) every DATA chunk
                                                    sent to the SCTP port carries PPID 70 (E2AP, O-RAN E2GAP v08.00
                                                    section 6.1); every expected node's associations, or the
                                                    --source-ip's, sent PPID 70 chunks; and E2AP decoded by PPID
                                                    counts as many frames as E2AP forced on the port

Attribution is by ASSOCIATION, never by container IP (Docker reassigns IPs when agents restart). An association
is (agent ip, agent source port) <-> Service, born at the INIT_ACK that answers an INIT; its node is the node ID
of the Global E2 Node ID in the E2SetupRequest sent on it (an en-gNB's 32-bit gNB ID = the ns-3 cellId = nodeId, the
eNB's 20-bit macro eNB ID = nodeId 1; any other ID, such as the reference kpm_sim's, is "not an expected node" and
ignored). INITs that never got an INIT_ACK belong to no association and
are only reported per agent IP. The expected node set is --nodes (comma list) or the keys of --node-ips.
--node-ips F (JSON {"<nodeId>": ["<container ip>", ...]}) is a cross-check only: mismatches are printed as
informational lines and never decide a verdict.
"""
import argparse
import contextlib
import importlib.util
import io
import json
import os
import sys


def load(path):
    return json.load(open(path))


def _sibling(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(os.path.dirname(os.path.abspath(__file__)), filename))
    assert spec is not None and spec.loader is not None, filename
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


KAJ = _sibling("kpm_action_subscription_judges", "kpm-action-subscription-judges.py")
KIJ = _sibling("kpm_indication_action_judges", "kpm-indication-action-judges.py")


def node_of(ips):
    return {ip: nid for nid, lst in ips.items() for ip in lst}


def q_setup_request(f, a):
    reqs = f["setup_requests"]
    print("E2SetupRequests on the wire: %d" % len(reqs))
    bad = []
    if not reqs:
        bad.append("no E2SetupRequest decoded")
    for r in reqs:
        print("frame %d from %s: funcs=%s oids=%s short=%s node=%s/%s/%s bits plmn=%s descr=%s" % (
            r["frame"], r["src"], r["ran_function_ids"], sorted(set(r["oids"])), r["short_names"], r["e2node_type"],
            r["node_id"], r["node_id_bits"], r["plmn"], r["descriptions"]))
        if a.func_id not in r["ran_function_ids"]:
            bad.append("RANfunctionID %d missing" % a.func_id)
        if a.oid not in r["oids"]:
            bad.append("ranFunctionOID %s missing" % a.oid)
        if a.short_name not in r["short_names"]:
            bad.append("short name %s missing" % a.short_name)
        if r["e2node_type"] != a.node_type:
            bad.append("Global E2 Node ID type %s != %s" % (r["e2node_type"], a.node_type))
        if r["node_id"] != a.node_id:
            bad.append("node ID %s != %d" % (r["node_id"], a.node_id))
        if r["node_id_bits"] != a.node_id_bits:
            bad.append("node ID bit length %s != %d" % (r["node_id_bits"], a.node_id_bits))
        if (r["plmn"] or "") != a.plmn.lower():
            bad.append("plmn %s != %s" % (r["plmn"], a.plmn))
        if a.not_node_id_hex:
            v = int(a.not_node_id_hex, 16)
            if r["node_id"] in (v, v >> 3):
                bad.append("node ID equals the reference node's %s" % a.not_node_id_hex)
    return bad


def q_setup_response(f, a):
    rs = f["setup_responses"]
    print("E2SetupResponses: %s" % [(r["frame"], r["dst"], r["accepted"]) for r in rs])
    if not rs:
        return ["no E2SetupResponse decoded"]
    return [] if all(a.func_id in r["accepted"] for r in rs) else ["RANfunctionsAccepted lacks %d" % a.func_id]


def q_subscription(f, a):
    after = a.after or 0
    reqs = [r for r in f["sub_requests"] if r["t"] >= after]
    resps = [r for r in f["sub_responses"] if r["t"] >= after]
    print("RICsubscriptionRequests: %s" % [(r["frame"], r["dst"], r["requestor"], r["instance"], r["ran_function_id"]) for r in reqs])
    print("RICsubscriptionResponses: %s" % [(r["frame"], r["src"], r["requestor"], r["instance"], r["ran_function_id"]) for r in resps])
    if not reqs or not resps:
        return ["need >= 1 request and >= 1 response"]
    bad = []
    if any(r["ran_function_id"] != a.func_id for r in reqs + resps):
        bad.append("RAN function id differs from %d" % a.func_id)
    answered = {(r["requestor"], r["instance"]) for r in resps}
    if not any((r["requestor"], r["instance"]) in answered for r in reqs):
        bad.append("no response matches a request (requestor, instance)")
    return bad


def _window(f, key, a):
    return [r for r in f.get(key, []) if r["t"] >= (a.after or 0)]


def q_sub_period(f, a):
    reqs, resps = _window(f, "sub_requests", a), _window(f, "sub_responses", a)
    print("RICsubscriptionRequests (frame, reportingPeriod, granulPeriods): %s" % [
        (r["frame"], r.get("reporting_period_ms"), r.get("granul_periods_ms")) for r in reqs])
    if not reqs:
        return ["no RICsubscriptionRequest in the window"]
    bad = []
    for r in reqs:
        if r.get("reporting_period_ms") != a.period_ms:
            bad.append("frame %d: reportingPeriod %s != %d" % (r["frame"], r.get("reporting_period_ms"), a.period_ms))
        g = r.get("granul_periods_ms") or []
        if a.granul_ms is not None and (not g or any(x != a.granul_ms for x in g)):
            bad.append("frame %d: granulPeriods %s != %d" % (r["frame"], g, a.granul_ms))
    answered = {(r["requestor"], r["instance"]) for r in resps}
    if not any((r["requestor"], r["instance"]) in answered for r in reqs):
        bad.append("no request answered by a RIC SUBSCRIPTION RESPONSE")
    return bad


def q_sub_failure(f, a):
    reqs, resps, fails = _window(f, "sub_requests", a), _window(f, "sub_responses", a), _window(f, "sub_failures", a)
    print("RICsubscriptionRequests: %s" % [(r["frame"], r["requestor"], r["instance"], r.get("reporting_period_ms")) for r in reqs])
    print("RICsubscriptionFailures: %s" % [(r["frame"], r["requestor"], r["instance"], r.get("cause"), r.get("cause_label")) for r in fails])
    print("RICsubscriptionResponses: %s" % [(r["frame"], r["requestor"], r["instance"]) for r in resps])
    bad = []
    asked = {(r["requestor"], r["instance"]) for r in reqs}
    hit = [r for r in fails if (r["requestor"], r["instance"]) in asked]
    if not hit:
        bad.append("no RIC SUBSCRIPTION FAILURE answers a request in the window")
    if any(r.get("cause") != a.cause for r in hit):
        bad.append("failure cause %s != %s" % (sorted({r.get("cause") for r in hit}, key=str), a.cause))
    if resps:
        bad.append("%d RIC SUBSCRIPTION RESPONSE(s) in the window" % len(resps))
    return bad


def expected_nodes(a):
    if a.nodes:
        return sorted(int(x) for x in a.nodes.split(",") if x)
    if a.node_ips:
        return sorted(int(k) for k in load(a.node_ips))
    sys.exit("need --nodes or --node-ips")


def build_assocs(f):
    """Associations from the fact sheet: list of dicts, sorted by INIT_ACK time. Every later event carries its
    association via assoc_of(); `others` collects nothing, unattributed events are simply not in any association."""
    if "init_acks" not in f or "cookie_acks" not in f:
        sys.exit("fact sheet predates association attribution (no init_acks/cookie_acks): re-run e2ap-pcap-facts.py")
    key = lambda ip, port: (ip, port)
    by_key = {}
    cookie = {}
    for c in sorted(f["cookie_acks"], key=lambda x: x["t"]):
        cookie.setdefault(key(c["dst"], c["dport"]), []).append(c["t"])
    for ack in sorted(f["init_acks"], key=lambda x: x["t"]):
        k = key(ack["dst"], ack["dport"])
        lst = by_key.setdefault(k, [])
        # a repeated INIT_ACK on a 4-tuple that has no COOKIE_ACK yet is the same handshake
        if lst and lst[-1]["t_cookie_ack"] is None:
            continue
        lst.append({"ip": k[0], "sport": k[1], "service": ack["src"], "service_port": ack["sport"],
                    "t_init_ack": ack["t"], "t_init": None, "t_cookie_ack": None, "node": None, "node_id": None,
                    "setup_request": None, "setup_response": None, "sub_requests": [], "sub_responses": [],
                    "indications": [], "frame": ack["frame"]})
        # COOKIE_ACK of this handshake: first one at/after this INIT_ACK
        lst[-1]["t_cookie_ack"] = next((t for t in cookie.get(k, []) if t >= ack["t"]), None)
    assocs = sorted((x for lst in by_key.values() for x in lst), key=lambda x: x["t_init_ack"])

    def assoc_of(ip, port, t):
        best = None
        for x in by_key.get(key(ip, port), []):
            if x["t_init_ack"] <= t:
                best = x
        return best

    # An INIT is answered when an association on its tuple was born at or after it; the first such INIT after the
    # previous association on that tuple is the association's INIT. The rest never got an INIT_ACK.
    inits = sorted(f["inits"], key=lambda x: x["t"])
    unanswered = []
    for i in inits:
        nxt = next((x for x in by_key.get(key(i["src"], i["sport"]), []) if x["t_init_ack"] >= i["t"]), None)
        if nxt is None:
            unanswered.append(i)
        elif nxt["t_init"] is None:
            nxt["t_init"] = i["t"]
    for r in sorted(f["setup_requests"], key=lambda x: x["t"]):
        x = assoc_of(r["src"], r["sport"], r["t"])
        if x and x["setup_request"] is None:
            x["setup_request"], x["node_id"], x["node"] = r, r["node_id"], r["node_id"]
    for r in f["setup_responses"]:
        x = assoc_of(r["dst"], r["dport"], r["t"])
        if x and x["setup_response"] is None and r["t"] >= x["t_init_ack"]:
            x["setup_response"] = r
    for r in f["sub_requests"]:
        x = assoc_of(r["dst"], r["dport"], r["t"])
        if x:
            x["sub_requests"].append(r)
    for r in f["sub_responses"]:
        x = assoc_of(r["src"], r["sport"], r["t"])
        if x:
            x["sub_responses"].append(r)
    for r in f.get("ind_events", []):
        x = assoc_of(r["src"], r["sport"], r["t"])
        if x:
            x["indications"].append(r["t"])
    return assocs, unanswered


def assoc_established(x):
    return x["t_cookie_ack"] is not None


def fmt_assoc(x):
    return "%s:%d node=%s nodeId=%s init_ack=%.2f cookie_ack=%s setup_resp=%s subReq=%d subResp=%d ind=%d" % (
        x["ip"], x["sport"], x["node"], x["node_id"], x["t_init_ack"], x["t_cookie_ack"] is not None,
        x["setup_response"] is not None, len(x["sub_requests"]), len(x["sub_responses"]), len(x["indications"]))


def print_unanswered(unanswered):
    per = {}
    for i in unanswered:
        per.setdefault(i["src"], []).append(i)
    for ip, lst in sorted(per.items()):
        print("informational: %d INIT(s) from %s never answered by an INIT_ACK (no association): sports %s, t %.1f..%.1f" % (
            len(lst), ip, sorted({x["sport"] for x in lst}), lst[0]["t"], lst[-1]["t"]))


def cross_check(a, assocs, nodes):
    """Compare association attribution with node-ips.json (informational only)."""
    if not a.node_ips:
        return
    ips = load(a.node_ips)
    for nid in nodes:
        seen = sorted({x["ip"] for x in assocs if x["node"] == nid})
        extra = sorted(set(seen) - set(ips.get(str(nid), [])))
        if extra:
            print("informational: node %s associations came from %s, node-ips.json lists %s (IP reassignment after restarts)" % (
                nid, extra, ips.get(str(nid), [])))


def q_associations(f, a):
    assocs, unanswered = build_assocs(f)
    for x in assocs:
        if a.after is None or x["t_init_ack"] >= a.after:
            print(fmt_assoc(x))
    print_unanswered(unanswered)
    return []


def q_assoc_start(f, a):
    nodes = expected_nodes(a)
    assocs, unanswered = build_assocs(f)
    pre = [x for x in assocs if x["t_init_ack"] < a.before]
    for x in pre:
        print("association %s%s" % (fmt_assoc(x), "" if x["node"] in nodes else "  (not an expected node: ignored)"))
    print_unanswered([i for i in unanswered if i["t"] < a.before])
    cross_check(a, pre, nodes)
    bad = []
    mine = [x for x in pre if x["node"] in nodes]
    for nid in nodes:
        est = [x for x in mine if x["node"] == nid and assoc_established(x)]
        if len(est) != 1:
            bad.append("node %s has %d established associations with an E2SetupRequest before the window end (want exactly 1)" % (nid, len(est)))
    unfinished = [x for x in mine if not assoc_established(x)]
    for x in unfinished:
        bad.append("node %s association %s:%d has an INIT_ACK but no COOKIE_ACK" % (x["node"], x["ip"], x["sport"]))
    est = [x for x in mine if assoc_established(x)]
    ips = [x["ip"] for x in est]
    if len(set(ips)) != len(ips):
        bad.append("agent source IPs are not distinct per node: %s" % sorted(ips))
    tuples = [(x["ip"], x["sport"]) for x in est]
    if len(set(tuples)) != len(tuples):
        bad.append("(ip, src-port) collision among the initial associations: %s" % sorted(tuples))
    for x in est:
        if x["service"] != a.service_ip or x["service_port"] != a.sctp_port:
            bad.append("node %s association goes to %s:%d, not the Service %s:%d" % (
                x["node"], x["service"], x["service_port"], a.service_ip, a.sctp_port))
    return bad


def agent_ips(a, assocs):
    nodes = expected_nodes(a)
    ips = {x["ip"] for x in assocs if x["node"] in nodes}
    if a.node_ips:
        ips |= {ip for lst in load(a.node_ips).values() for ip in lst}
    return ips


def q_service_ip(f, a):
    assocs, _ = build_assocs(f)
    owner = agent_ips(a, assocs)
    mine = [i for i in f["inits"] if i["src"] in owner]
    print("agent INITs: %d from %d agent IPs, destinations: %s" % (len(mine), len({i["src"] for i in mine}),
                                                                   sorted({(i["dst"], i["dport"]) for i in mine})))
    bad = ["INIT %d from %s to %s:%d" % (i["frame"], i["src"], i["dst"], i["dport"]) for i in mine
           if (i["dst"], i["dport"]) != (a.service_ip, a.sctp_port)]
    return bad or ([] if mine else ["no agent INIT in the capture"])


def q_no_abort(f, a):
    inside = [x for x in f["aborts"] if a.from_ <= x["t"] < a.to]
    print("ABORT chunks in [%.3f, %.3f): %d %s" % (a.from_, a.to, len(inside), [(x["frame"], x["src"], x["dst"]) for x in inside][:10]))
    print("all ABORTs: %s" % [(x["frame"], round(x["t"], 3), x["src"], x["dst"]) for x in f["aborts"]][:40])
    print("all SHUTDOWN-family chunks: %s" % [(x["frame"], round(x["t"], 3), x["src"], x["dst"], x["chunks"]) for x in f["shutdowns"]][:40])
    return [] if not inside else ["%d ABORT(s) during the endurance window" % len(inside)]


def q_post_delete(f, a):
    nodes = expected_nodes(a)
    assocs, unanswered = build_assocs(f)
    t0 = a.after
    bad, timeline = [], {}
    for i in f["inits"]:
        if i["t"] >= t0 and i["dst"] != a.service_ip and i["src"] in agent_ips(a, assocs):
            bad.append("post-delete INIT from %s to %s, not the Service IP %s" % (i["src"], i["dst"], a.service_ip))
    print_unanswered([i for i in unanswered if i["t"] >= t0])
    cross_check(a, assocs, nodes)
    rel = lambda x: None if x is None else round((x["t"] if isinstance(x, dict) else x) - t0, 2)
    for nid in nodes:
        old = [x for x in assocs if x["node"] == nid and x["t_init_ack"] < t0]
        new = [x for x in assocs if x["node"] == nid and x["t_init_ack"] >= t0 and assoc_established(x)]
        old_ports = sorted({x["sport"] for x in old})
        first = new[0] if new else None
        setup = min((x["setup_request"] for x in new if x["setup_request"]), key=lambda r: r["t"], default=None)
        resp = min((x["setup_response"] for x in new if x["setup_response"] and a.func_id in x["setup_response"]["accepted"]),
                   key=lambda r: r["t"], default=None)
        sreq = min((r for x in new for r in x["sub_requests"]), key=lambda r: r["t"], default=None)
        sresp = min((r for x in new for r in x["sub_responses"]), key=lambda r: r["t"], default=None)
        inds = sorted(t for x in new for t in x["indications"] if sresp and t >= sresp["t"])
        ind = inds[0] if inds else None
        timeline[nid] = {
            "init_s": rel(first["t_init"] if first and first["t_init"] is not None else first["t_init_ack"] if first else None),
            "setup_request_s": rel(setup), "setup_response_s": rel(resp),
            "sub_request_s": rel(sreq), "sub_response_s": rel(sresp), "first_indication_s": rel(ind),
            "new_sport": first["sport"] if first else None, "old_sports": old_ports,
            "old_associations": ["%s:%d" % (x["ip"], x["sport"]) for x in old],
            "new_associations": ["%s:%d" % (x["ip"], x["sport"]) for x in new],
            "new_sports": [x["sport"] for x in new],
            "indications_post_delete": sum(len(x["indications"]) for x in new)}
        print("node %s: %s" % (nid, json.dumps(timeline[nid])))
        for name, v in (("new established association", first), ("new E2SetupRequest", setup),
                        ("E2SetupResponse accepting %d" % a.func_id, resp), ("new RICsubscriptionRequest", sreq),
                        ("subscription response", sresp), ("first indication", ind)):
            if v is None:
                bad.append("node %s: no %s after the delete" % (nid, name))
        reused = sorted({x["sport"] for x in new} & set(old_ports))
        if reused:
            bad.append("node %s reconnected from the OLD source port(s) %s" % (nid, reused))
    if a.timeline_out:
        json.dump(timeline, open(a.timeline_out, "w"), indent=1, sort_keys=True)
    return bad


def q_indications(f, a):
    nodes = expected_nodes(a)
    assocs, _ = build_assocs(f)
    cross_check(a, assocs, nodes)
    bad = []
    for nid in nodes:
        mine = [x for x in assocs if x["node"] == nid]
        n = sum(len(x["indications"]) for x in mine)
        print("node %s: %d RICindication frames over %d association(s): %s" % (
            nid, n, len(mine), [("%s:%d" % (x["ip"], x["sport"]), len(x["indications"])) for x in mine]))
        if n == 0:
            bad.append("node %s sent no RICindication" % nid)
    return bad


def q_sub_actions(f, a):
    if not a.decoded:
        sys.exit("sub-actions needs --decoded (the capture's asn1-indep decode, e2-sub-setup-decode.py)")
    assocs, _ = build_assocs(f)
    return KAJ.judge_sub_actions(f, load(a.decoded), expected_nodes(a), assocs, a.after or 0)


def q_ind_actions(f, a):
    need = [k for k in ("decoded", "ind_actions", "records", "lines", "extract_summary", "map") if not getattr(a, k)]
    if need:
        sys.exit("ind-actions needs --%s" % ", --".join(k.replace("_", "-") for k in need))
    assocs, _ = build_assocs(f)
    jsonl = lambda p: [json.loads(x) for x in open(p) if x.strip()]
    nlines = sum(1 for x in open(a.lines) if x.strip())
    try:
        summary = json.loads(open(a.extract_summary).read().strip().splitlines()[-1])
    except (IndexError, ValueError):
        summary = None
    return KIJ.judge_ind_actions(f, load(a.decoded), expected_nodes(a), assocs, a.after or 0, jsonl(a.ind_actions),
                                 jsonl(a.records), nlines, summary, KIJ.cell_layout(a.map))


def self_test():
    """The judges of kpm-action-subscription-judges.py on synthetic fact sheets and decodes: each case's verdict and,
    for a failing case, its reason."""
    def run_query(query, f, decoded, after, **extra):
        A = argparse.Namespace(nodes="1,2", node_ips=None, after=after, decoded=None, **extra)
        assocs, _ = build_assocs(f)
        with contextlib.redirect_stdout(io.StringIO()):
            return KAJ.judge_sub_actions(f, decoded, expected_nodes(A), assocs, after or 0)
    def run_ind(sheet):
        assocs, _ = build_assocs(sheet.f)
        with contextlib.redirect_stdout(io.StringIO()):
            return KIJ.judge_ind_actions(sheet.f, sheet.dec, [1, 2], assocs, 0, sheet.rows, sheet.records,
                                         len(sheet.records), sheet.summary, KIJ.LAYOUT)
    fails = KAJ.self_test(run_query) + KIJ.self_test(run_ind)
    print("e2-facts-query self-test: " + ("ok" if not fails else "FAIL " + "; ".join(fails)))
    return 1 if fails else 0


E2AP_PPID = 70


def q_ppid(f, a):
    if "ppid" not in f:
        sys.exit("fact sheet has no ppid facts: re-run e2ap-pcap-facts.py --ppid")
    pf, bad = f["ppid"], []
    per = pf["to_port_by_assoc"]
    for k, v in sorted(per.items()):
        other = {p: n for p, n in v["counts"].items() if int(p) != E2AP_PPID}
        print("%s -> :%d PPID counts %s" % (k, pf["sctp_port"], json.dumps(v["counts"], sort_keys=True)))
        if other:
            bad.append("%s sent %d DATA chunk(s) with PPID %s" % (k, sum(other.values()), sorted(other, key=int)))
    n70 = lambda v: v["counts"].get(str(E2AP_PPID), 0)
    if a.nodes or a.node_ips:
        assocs, _ = build_assocs(f)
        for nid in expected_nodes(a):
            keys = {"%s:%d" % (x["ip"], x["sport"]) for x in assocs if x["node"] == nid}
            n = sum(n70(per[k]) for k in keys if k in per)
            print("node %s: %d PPID-70 chunk(s) over %s" % (nid, n, sorted(keys)))
            if n == 0:
                bad.append("node %s: no PPID-70 DATA chunk (associations %s)" % (nid, sorted(keys)))
    if a.source_ip:
        n = sum(n70(v) for v in per.values() if v["src"] == a.source_ip)
        print("source %s: %d PPID-70 chunk(s)" % (a.source_ip, n))
        if n == 0:
            bad.append("source %s sent no PPID-70 DATA chunk" % a.source_ip)
    if not per:
        bad.append("no DATA chunk was sent to port %d" % pf["sctp_port"])
    fr = pf["e2ap_frames"]
    print("E2AP frames decoded by PPID %d, forced on the port %d" % (fr["by_ppid"], fr["forced_port"]))
    if fr["by_ppid"] != fr["forced_port"]:
        bad.append("E2AP decoded by PPID (%d frames) != forced on the port (%d)" % (fr["by_ppid"], fr["forced_port"]))
    return bad


QUERIES = {"setup-request": q_setup_request, "setup-response": q_setup_response, "subscription": q_subscription,
           "sub-period": q_sub_period, "sub-failure": q_sub_failure, "sub-actions": q_sub_actions,
           "ind-actions": q_ind_actions,
           "assoc-start": q_assoc_start, "no-abort": q_no_abort, "post-delete": q_post_delete,
           "indications": q_indications, "service-ip": q_service_ip, "associations": q_associations,
           "ppid": q_ppid}


def main():
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    ap = argparse.ArgumentParser()
    ap.add_argument("facts")
    ap.add_argument("query", choices=sorted(QUERIES))
    ap.add_argument("--func-id", type=int, default=2)
    ap.add_argument("--oid")
    ap.add_argument("--short-name")
    ap.add_argument("--node-type")
    ap.add_argument("--node-id", type=int)
    ap.add_argument("--node-id-bits", type=int)
    ap.add_argument("--plmn")
    ap.add_argument("--not-node-id-hex")
    ap.add_argument("--after", type=float)
    ap.add_argument("--period-ms", type=int)
    ap.add_argument("--granul-ms", type=int)
    ap.add_argument("--cause")
    ap.add_argument("--before", type=float)
    ap.add_argument("--from", dest="from_", type=float)
    ap.add_argument("--to", type=float)
    ap.add_argument("--node-ips")
    ap.add_argument("--nodes", help="comma list of expected node ids (default: keys of --node-ips)")
    ap.add_argument("--service-ip")
    ap.add_argument("--source-ip")
    ap.add_argument("--sctp-port", type=int, default=36422)
    ap.add_argument("--timeline-out")
    ap.add_argument("--decoded", help="sub-actions, ind-actions: the capture's asn1-indep decode (e2-sub-setup-decode.py)")
    ap.add_argument("--ind-actions", help="ind-actions: pcap-to-lines.py --actions rows (JSON lines)")
    ap.add_argument("--records", help="ind-actions: kpimon-decode-harness --records over --lines")
    ap.add_argument("--lines", help="ind-actions: the pcap-to-lines.py lines")
    ap.add_argument("--extract-summary", help="ind-actions: pcap-to-lines.py --actions stderr (its summary line)")
    ap.add_argument("--map", help="ind-actions: metric-map.v1.json (cell-list position of ns3.nodeId)")
    a = ap.parse_args()
    bad = QUERIES[a.query](load(a.facts), a)
    for b in bad:
        print("PROBLEM: " + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

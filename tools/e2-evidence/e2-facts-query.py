#!/usr/bin/env python3
"""e2-facts-query.py <facts.json> <query> [options]

Gate assertions over the fact sheet from e2ap-pcap-facts.py. Each query prints
its evidence and exits 0 (pass) or 1 (fail).

  setup-request   --func-id N --oid OID --short-name S --gnb-id N --plmn HEX [--not-gnb-id-hex HEX]
  setup-response  --func-id N
  subscription    --func-id N [--after EPOCH]      request (RIC->agent) answered by a response
  assoc-start     --service-ip IP --before EPOCH [--sctp-port 36422]   one ESTABLISHED association per node before EPOCH
  no-abort        --from EPOCH --to EPOCH           ABORT chunks inside the window (also lists the rest)
  post-delete     --service-ip IP --after EPOCH --func-id N [--timeline-out F]
  indications                                       every node's associations carried RICindications
  service-ip      --service-ip IP                   every agent INIT in the capture went to the Service IP
  associations    [--after EPOCH]                   list associations (informational)

Attribution is by ASSOCIATION, never by container IP (Docker reassigns IPs when agents restart). An association
is (agent ip, agent source port) <-> Service, born at the INIT_ACK that answers an INIT; its node is the global
gNB-ID of the E2SetupRequest sent on it (decimal gNB-ID == nodeId; any other gNB-ID, such as the reference
kpm_sim's, is "not an expected node" and ignored). INITs that never got an INIT_ACK belong to no association and
are only reported per agent IP. The expected node set is --nodes (comma list) or the keys of --node-ips.
--node-ips F (JSON {"<nodeId>": ["<container ip>", ...]}) is a cross-check only: mismatches are printed as
informational lines and never decide a verdict.
"""
import argparse
import json
import sys


def load(path):
    return json.load(open(path))


def node_of(ips):
    return {ip: nid for nid, lst in ips.items() for ip in lst}


def q_setup_request(f, a):
    reqs = f["setup_requests"]
    print("E2SetupRequests on the wire: %d" % len(reqs))
    bad = []
    if not reqs:
        bad.append("no E2SetupRequest decoded")
    for r in reqs:
        print("frame %d from %s: funcs=%s oids=%s short=%s gnbId=%s plmn=%s descr=%s" % (
            r["frame"], r["src"], r["ran_function_ids"], sorted(set(r["oids"])), r["short_names"], r["gnb_id"],
            r["plmn"], r["descriptions"]))
        if a.func_id not in r["ran_function_ids"]:
            bad.append("RANfunctionID %d missing" % a.func_id)
        if a.oid not in r["oids"]:
            bad.append("ranFunctionOID %s missing" % a.oid)
        if a.short_name not in r["short_names"]:
            bad.append("short name %s missing" % a.short_name)
        if r["gnb_id"] != a.gnb_id:
            bad.append("global gNB-ID %s != %d" % (r["gnb_id"], a.gnb_id))
        if (r["plmn"] or "") != a.plmn.lower():
            bad.append("plmn %s != %s" % (r["plmn"], a.plmn))
        if a.not_gnb_id_hex:
            v = int(a.not_gnb_id_hex, 16)
            if r["gnb_id"] in (v, v >> 3):
                bad.append("gNB-ID equals the reference node's %s" % a.not_gnb_id_hex)
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
                    "t_init_ack": ack["t"], "t_init": None, "t_cookie_ack": None, "node": None, "gnb_id": None,
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
            x["setup_request"], x["gnb_id"], x["node"] = r, r["gnb_id"], r["gnb_id"]
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
    return "%s:%d node=%s gNB-ID=%s init_ack=%.2f cookie_ack=%s setup_resp=%s subReq=%d subResp=%d ind=%d" % (
        x["ip"], x["sport"], x["node"], x["gnb_id"], x["t_init_ack"], x["t_cookie_ack"] is not None,
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


QUERIES = {"setup-request": q_setup_request, "setup-response": q_setup_response, "subscription": q_subscription,
           "assoc-start": q_assoc_start, "no-abort": q_no_abort, "post-delete": q_post_delete,
           "indications": q_indications, "service-ip": q_service_ip, "associations": q_associations}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("facts")
    ap.add_argument("query", choices=sorted(QUERIES))
    ap.add_argument("--func-id", type=int, default=2)
    ap.add_argument("--oid")
    ap.add_argument("--short-name")
    ap.add_argument("--gnb-id", type=int)
    ap.add_argument("--plmn")
    ap.add_argument("--not-gnb-id-hex")
    ap.add_argument("--after", type=float)
    ap.add_argument("--before", type=float)
    ap.add_argument("--from", dest="from_", type=float)
    ap.add_argument("--to", type=float)
    ap.add_argument("--node-ips")
    ap.add_argument("--nodes", help="comma list of expected node ids (default: keys of --node-ips)")
    ap.add_argument("--service-ip")
    ap.add_argument("--sctp-port", type=int, default=36422)
    ap.add_argument("--timeline-out")
    a = ap.parse_args()
    bad = QUERIES[a.query](load(a.facts), a)
    for b in bad:
        print("PROBLEM: " + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

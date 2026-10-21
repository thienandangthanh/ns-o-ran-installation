#!/usr/bin/env python3
"""e2-facts-query.py <facts.json> <query> [options]

Gate assertions over the fact sheet from e2ap-pcap-facts.py. Each query prints
its evidence and exits 0 (pass) or 1 (fail).

  setup-request   --func-id N --oid OID --short-name S --gnb-id N --plmn HEX [--not-gnb-id-hex HEX]
  setup-response  --func-id N
  subscription    --func-id N [--after EPOCH]      request (RIC->agent) answered by a response
  assoc-start     --node-ips F --service-ip IP --before EPOCH [--sctp-port 36422]
  no-abort        --from EPOCH --to EPOCH           ABORT chunks inside the window (also lists the rest)
  post-delete     --node-ips F --service-ip IP --after EPOCH --func-id N [--timeline-out F]
  indications     --node-ips F                      every node IP sent RICindications
  service-ip      --node-ips F --service-ip IP      every agent INIT in the capture went to the Service IP

--node-ips F: JSON {"<nodeId>": ["<container ip>", ...]}.
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


def q_assoc_start(f, a):
    ips = load(a.node_ips)
    owner = node_of(ips)
    pre = [i for i in f["inits"] if i["t"] < a.before]
    per = {}
    for i in pre:
        per.setdefault(i["src"], []).append(i)
    for ip, lst in sorted(per.items()):
        print("INIT from %s (node %s): %s" % (ip, owner.get(ip, "?"), [(x["sport"], x["dst"], x["dport"]) for x in lst]))
    bad = []
    for nid, lst in sorted(ips.items()):
        n = sum(len(per.get(ip, [])) for ip in lst)
        if n != 1:
            bad.append("node %s has %d INITs before the window end (want exactly 1)" % (nid, n))
    # INITs from other sources (the reference node, restarted by the platform) are listed above but are not agents.
    mine = [i for i in pre if i["src"] in owner]
    if len({i["src"] for i in mine}) != len(ips):
        bad.append("%d distinct agent INIT sources for %d agents" % (len({i["src"] for i in mine}), len(ips)))
    sports = [i["sport"] for i in mine]
    if len(set(sports)) != len(sports):
        bad.append("src-port collision among the initial associations: %s" % sorted(sports))
    for i in mine:
        if i["dst"] != a.service_ip or i["dport"] != a.sctp_port:
            bad.append("INIT to %s:%d, not the Service %s:%d" % (i["dst"], i["dport"], a.service_ip, a.sctp_port))
    return bad


def q_service_ip(f, a):
    ips = load(a.node_ips)
    owner = node_of(ips)
    mine = [i for i in f["inits"] if i["src"] in owner]
    print("agent INITs: %d, destinations: %s" % (len(mine), sorted({(i["dst"], i["dport"]) for i in mine})))
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
    ips = load(a.node_ips)
    owner = node_of(ips)
    t0 = a.after
    old_ports = {}
    for i in f["inits"]:
        if i["t"] < t0:
            old_ports.setdefault(owner.get(i["src"]), set()).add(i["sport"])
    bad, timeline = [], {}
    for i in f["inits"]:
        if i["t"] >= t0 and i["dst"] != a.service_ip:
            bad.append("post-delete INIT from %s to %s, not the Service IP %s" % (i["src"], i["dst"], a.service_ip))
    rel = lambda x: None if x is None else round((x["t"] if isinstance(x, dict) else x) - t0, 2)
    for nid, lst in sorted(ips.items()):
        mine = set(lst)
        init = next((i for i in f["inits"] if i["t"] >= t0 and i["src"] in mine), None)
        setup = next((r for r in f["setup_requests"] if r["t"] >= t0 and r["src"] in mine), None)
        resp = next((r for r in f["setup_responses"] if r["t"] >= t0 and r["dst"] in mine and a.func_id in r["accepted"]), None)
        sreq = next((r for r in f["sub_requests"] if r["t"] >= t0 and r["dst"] in mine), None)
        sresp = next((r for r in f["sub_responses"] if r["t"] >= t0 and r["src"] in mine), None)
        inds = sorted(t for ip in lst for t in f["ind_times_by_src"].get(ip, []) if sresp and t >= sresp["t"])
        ind = inds[0] if inds else None
        timeline[nid] = {"init_s": rel(init), "setup_request_s": rel(setup), "setup_response_s": rel(resp),
                         "sub_request_s": rel(sreq), "sub_response_s": rel(sresp), "first_indication_s": rel(ind),
                         "new_sport": init["sport"] if init else None, "old_sports": sorted(old_ports.get(nid, []))}
        print("node %s: %s" % (nid, json.dumps(timeline[nid])))
        for name, v in (("new INIT", init), ("new E2SetupRequest", setup),
                        ("E2SetupResponse accepting %d" % a.func_id, resp), ("new RICsubscriptionRequest", sreq),
                        ("subscription response", sresp), ("first indication", ind)):
            if v is None:
                bad.append("node %s: no %s after the delete" % (nid, name))
        if init and init["sport"] in old_ports.get(nid, set()):
            bad.append("node %s reconnected from the OLD source port %d" % (nid, init["sport"]))
    if a.timeline_out:
        json.dump(timeline, open(a.timeline_out, "w"), indent=1, sort_keys=True)
    return bad


def q_indications(f, a):
    ips = load(a.node_ips)
    bad = []
    for nid, lst in sorted(ips.items()):
        n = sum(len(f["ind_times_by_src"].get(ip, [])) for ip in lst)
        print("node %s: %d RICindication frames from %s" % (nid, n, lst))
        if n == 0:
            bad.append("node %s sent no RICindication" % nid)
    return bad


QUERIES = {"setup-request": q_setup_request, "setup-response": q_setup_response, "subscription": q_subscription,
           "assoc-start": q_assoc_start, "no-abort": q_no_abort, "post-delete": q_post_delete,
           "indications": q_indications, "service-ip": q_service_ip}


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

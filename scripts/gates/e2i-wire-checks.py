#!/usr/bin/env python3
"""e2i-wire-checks.py: the E2 interop gate's wire checks, judged on the capture and on an independent decoder.

  setup FACTS PCAP --node-ips F --decode-cmd CMD --out OUT [--injected F]   E2 Setup Requests of every node (FACTS =
        the e2ap-pcap-facts.py output of PCAP; F = {"<nodeId>": [ip, ...]}): Global E2 Node ID, RAN functions, the X2
        component's request part and the RAN function 3 definition, from the whole setup PDU decoded by CMD (this
        script's `decode` mode in the asn1-indep image; identity and RAN functions must agree with tshark's), and the
        KPM subscriptions; OUT = {"checks": {name: {pass, detail}}, "nodes": ...}. With --injected, the RAN
        parameter IDs of every Style 5 action 3 control expected to be acknowledged (decoded in the image) must be
        announced too
  controls PCAP --node-ips F --facts FACTS --injected F --out OUT   every injected control (F: JSON lines {tag,
        node, headerHex, messageHex, expect: "ack" | "failure:<cause>"}) is on the wire once, to its node, with the
        injected header and message octets, and is answered once by that node as expected

Every frame is attributed to its node by its SCTP association, as kpm-ue-list-moves.py assoc_node_of does: the
association is (agent IP, agent SCTP port), the source of setup requests, subscription responses and control
answers and the destination of subscription requests and control requests, with the latest INIT_ACK at or before
the frame; its node is that association's E2 Setup Global E2 Node ID, and node-ips.json must list the agent IP for
that node. A frame on an association without an E2 Setup Request, or failing the IP cross-check, is a problem; every
node of node-ips.json must still have its setup request.
  x2-parts SETUP_OUT RECORD.json [RECORD.json ...]   beside each e2mgr nodeb record write RECORD.json.x2-parts.hex,
        one line per X2 component "<peer Global ID> <request part hex>" (peer as type/plmn/id/bits; the hex is the
        record's e2nodeComponentRequestPart base64-decoded: the hex text e2mgr stores, or the octets in hex); pass iff
        every X2 component of every record has a line, each line's hex equals its record field decoded again, and
        each request part equals the request part of the same X2 component (by peer) in that node's latest E2 Setup
        Request on the wire (SETUP_OUT, the setup mode's output). Plain hex outlives the evidence scrubber, which
        rewrites the base64 fields
  verdict OUT NAME      exit 0 iff check NAME of OUT passed (prints its detail)
  decode                (inside the image) stdin JSON {frame id: [E2AP PDU hex, ...]} -> stdout JSON {frame id:
                        [decode_setup of each PDU]}
  --decode-self-test    (inside the image) decode the AC6a probe nodes' X2 request parts
  --self-test           the judge on synthetic decodes, positive and negative

Expected identity (plan R-3): node 1 is the LTE eNB (Global ENB ID, macro eNB ID 1 in 20 bits; X2 init-eNB with one
served E-UTRA cell, ECI = 1 << 8 | 1, PCI 1, TAC 0001, EARFCN 100/18100) announcing KPM only; node n >= 2 is an
en-gNB (Global en-gNB ID, gNB ID n in 32 bits; X2 init-en-gNB with one served NR cell, NCI = n << 4 | 1, PCI n,
TAC 0001, NRARFCN 632758 (Point A, 3GPP TS 36.423 §9.2.106), band n78, nR-TxBW scs60/nrb24, and an MTC that decodes
to exactly one MeasTiming, the SSB at NR-ARFCN 633312 (GSCN 7846) with SCS kHz30) announcing KPM (2) and RC (3),
whose definition under the E2SM-RC OID announces exactly one control (style, action), Style 5 action 3 (PSCell
change), with RAN parameters (collected through every nested RANParameter-Definition) covering 1 to 4 and P_I4, the
action 3 parameters of E2SM-RC v03.00 §8.4.6.3: 1 Target PSCell ID > 2 CHOICE Target Cell > 3 NR Cell > 4 NR CGI.
PLMN 001/01 (00F110) everywhere.
"""
import base64
import binascii
import importlib.util
import json
import os
import shlex
import subprocess
import sys

PLMN = "00f110"
RC_OID = "1.3.6.1.4.1.53148.1.1.2.3"
P_I4 = {1, 2, 3, 4}  # E2SM-RC v03.00 §8.4.6.3, action 3: Target PSCell ID > CHOICE Target Cell > NR Cell > NR CGI
# The en-gNB's served NR cell (the agent's e2-node-identity.hpp): X2 NRARFCN = Point A (3GPP TS 36.423 §9.2.106) of a
# 20 MHz, 60 kHz carrier whose reference 633334 is on n78's 30 kHz raster (38.104 Table 5.4.2.2-1, §5.4.2.3); the MTC
# SSB on GSCN 7846, inside that carrier (38.104 Table 5.4.3.1-1, 38.101-1 Table 5.4.3.3-1)
NR_POINT_A, NR_TXBW, NR_SSB_ARFCN, NR_SSB_SCS = 632758, {"nRSCS": "scs60", "nRNRB": "nrb24"}, 633312, "kHz30"
# AC6a probe nodes' X2 request parts as they were on the wire (frames 6 and 17 of its capture). Historic: recorded
# before the served NR cell's frequency fix, so the en-gNB part carries NRARFCN and MTC carrierFreq 633333 with
# nR-TxBW scs30/nrb106; --decode-self-test judges only that both decode
AC6A_EN_GNB_7F000001 = ("0024004100000100f4003a40000200fc00090000f110507f00000100fd002600000400010000f1107f00000110"
                        "001000f110410009a9f500004d002700071011353ea50000")
AC6A_ENB_FFFFE = "0024003100000100f4002a000002001500080000f11000ffffe000fa0017000000010000f110ffffe010001000f1100046b4006455"


def plain(o):
    if isinstance(o, bytes):
        return o.hex()
    if isinstance(o, (list, tuple)):
        return [plain(x) for x in o]
    if isinstance(o, dict):
        return {k: plain(v) for k, v in o.items()}
    return o


def meas_timing(mtc):
    """The MeasTiming list of a decoded MeasurementTimingConfiguration (criticalExtensions c1 measTimingConf), or
    None for any other shape."""
    ext = (mtc or {}).get("criticalExtensions")
    if not ext or ext[0] != "c1" or ext[1][0] != "measTimingConf":
        return None
    return ext[1][1].get("measTiming")


def decode_x2(hexpart):
    """{node, ies} of an X2 request part (each served NR cell gains mtcDecodes and mtcMeasTiming, the decoded MTC's
    MeasTiming list) or {error}, inside the image."""
    from e2indep import x2ap
    try:
        d = x2ap.decode_endc_x2_setup_request(bytes.fromhex(hexpart))
        for c in d["ies"].get("id-ServedNRcellsENDCX2ManagementList", []):
            mtc = c["servedNRCellInfo"].get("measurementTimingConfiguration")
            dec = x2ap.decode_measurement_timing_configuration(mtc) if mtc else None
            c["servedNRCellInfo"]["mtcDecodes"] = bool(mtc) and bool(dec)
            c["servedNRCellInfo"]["mtcMeasTiming"] = meas_timing(dec)
        return plain(d)
    except Exception as ex:  # noqa: BLE001 - every decode failure is a finding
        return {"error": "%s: %s" % (type(ex).__name__, ex)}


def global_id(body):
    """[type, plmn hex, id, bits] of a decoded {global-en-gNB-ID | global-eNB-ID: {...}} (E2AP)."""
    kind = "en-gNB" if "global-en-gNB-ID" in body else "eNB" if "global-eNB-ID" in body else None
    gid = body.get("global-en-gNB-ID") or body.get("global-eNB-ID") or {}
    _, (val, bits) = gid.get("gNB-ID") or gid.get("eNB-ID") or (None, (None, None))
    return [kind, plain(gid.get("pLMN-Identity")), val, bits]


def x2_peers(nid, nodes):
    """The X2 neighbours an agent is configured with, as global_id values: the eNB has X2 to every en-gNB of the run,
    an en-gNB to the eNB."""
    if nid == 1:
        return sorted(["en-gNB", PLMN, n, 32] for n in nodes if n != 1)
    return [["eNB", PLMN, 1, 20]]


def decode_setup(hexpdu):
    """One E2AP PDU, inside the image: for an E2setupRequest {message, globalId: [type, plmn, id, bits],
    ranFunctionIds, x2: [decoded X2 request part per x2 component], x2peers: [the peer named by each x2 component's
    E2nodeComponentID-InterfaceX2, as [type, plmn, id, bits]], components, rcdef (RAN function 3's definition, decoded,
    when announced)}; otherwise {message} or {error}."""
    from e2indep import e2ap, e2sm_rc
    try:
        d = e2ap.decode_e2ap(bytes.fromhex(hexpdu))
    except Exception as ex:  # noqa: BLE001
        return {"error": "%s: %s" % (type(ex).__name__, ex)}
    if d["message"] != "E2setupRequest":
        return {"message": d["message"]}
    ies = d["ies"]
    kind, body = ies["id-GlobalE2node-ID"]
    funcs = e2ap.items(ies.get("id-RANfunctionsAdded", []))
    comps = e2ap.items(ies.get("id-E2nodeComponentConfigAddition", []))
    x2 = [c for c in comps if c["e2nodeComponentInterfaceType"] == "x2"]
    out = {"message": d["message"], "globalId": [kind] + global_id(body)[1:],
           "ranFunctionIds": sorted(f["ranFunctionID"] for f in funcs), "components": len(comps),
           "x2": [decode_x2(c["e2nodeComponentConfiguration"]["e2nodeComponentRequestPart"].hex()) for c in x2],
           "x2hex": [c["e2nodeComponentConfiguration"]["e2nodeComponentRequestPart"].hex() for c in x2],
           "x2peers": [global_id(c["e2nodeComponentID"][1]) for c in x2]}
    rc = [f["ranFunctionDefinition"] for f in funcs if f["ranFunctionID"] == 3]
    if rc:
        try:
            out["rcdef"] = plain(e2sm_rc.decode_ran_function_definition(rc[0]))
        except Exception as ex:  # noqa: BLE001
            out["rcdef"] = {"error": "%s: %s" % (type(ex).__name__, ex)}
    return out


def decode_control_ids(hexmsg):
    """Inside the image: {ids: every RAN parameter ID of an E2SM-RC control message, at any depth} or {error}."""
    from e2indep import e2sm_rc
    try:
        d = e2sm_rc.decode_control_message(bytes.fromhex(hexmsg))
    except Exception as ex:  # noqa: BLE001 - every decode failure is a finding
        return {"error": "%s: %s" % (type(ex).__name__, ex)}
    if d["params"] is None:
        return {"error": "control message %s, not Format 1" % d["format"]}
    return {"ids": sorted(param_ids(d["params"], "id"))}


def tshark_setup_pdus(pcap):
    """frame -> the octets (hex) of every E2AP PDU in each frame holding an E2 Setup Request, reassembled. The raw
    layer bytes are used, not tshark's fields: its E2SM-RC dissector stops at the gNB's RAN function 3 definition
    (a RANParameter-ID above its integer limit) and leaves every IE after it undissected."""
    cmd = ["tshark", "-r", pcap, "-Y", "e2ap.procedureCode == 1 && e2ap.initiatingMessage_element", "-T", "json",
           "-x", "-j", "frame e2ap"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 and "cut short" not in res.stderr:
        sys.exit("tshark failed: " + res.stderr.strip()[-400:])
    out = {}
    for pkt in json.loads(res.stdout or "[]"):
        lay = pkt["_source"]["layers"]
        raw = lay.get("e2ap_raw", [])
        raws = raw if raw and isinstance(raw[0], list) else [raw]
        out[int(lay["frame"]["frame.number"])] = [r[0] for r in raws if r]
    return out


def judge_node(nid, reqs, decoded, subs, peers, sent_ids=()):
    """Problems per check name for one node: reqs = its setup-request facts (tshark), decoded = frame id -> the
    independent decodes of that frame's PDUs, peers = its X2 neighbours (x2_peers). Identity and RAN functions must
    agree in both; there is one X2 component per neighbour, named by it, and no other component."""
    enb = nid == 1
    p = {k: [] for k in ("globalIds", "ranFunctions", "x2apRequestPartDecodes", "style5Action3Announced",
                         "kpimonSubscribedAll")}
    if not reqs:
        for k in p:
            p[k].append("node %d sent no E2 Setup Request" % nid)
        return p
    want_id, want_funcs = (("eNB", 1, 20) if enb else ("en-gNB", nid, 32)), ([2] if enb else [2, 3])
    for r in reqs:
        f = "node %d frame %d" % (nid, r["frame"])
        setups = [d for d in decoded.get("f%d" % r["frame"], []) if d.get("message") == "E2setupRequest"]
        if len(setups) != 1:
            for k in ("globalIds", "ranFunctions", "x2apRequestPartDecodes", "style5Action3Announced"):
                p[k].append("%s: %d independently decoded E2 Setup Requests, want 1 (%s)" % (
                    f, len(setups), decoded.get("f%d" % r["frame"])))
            continue
        d = setups[0]
        got = (r.get("e2node_type"), r.get("node_id"), r.get("node_id_bits"))
        if got != want_id or r.get("plmn") != PLMN:
            p["globalIds"].append("%s: tshark Global E2 Node ID %s PLMN %s, want %s PLMN %s" % (
                f, got, r.get("plmn"), want_id, PLMN))
        if d["globalId"] != [want_id[0], PLMN, want_id[1], want_id[2]]:
            p["globalIds"].append("%s: decoded Global E2 Node ID %s, want %s" % (f, d["globalId"], list(want_id)))
        if sorted(r.get("ran_function_ids") or []) != want_funcs or d["ranFunctionIds"] != want_funcs:
            p["ranFunctions"].append("%s: RAN functions tshark %s, decoded %s, want %s" % (
                f, sorted(r.get("ran_function_ids") or []), d["ranFunctionIds"], want_funcs))
        if sorted(d["x2peers"]) != peers or d["components"] != len(peers):
            p["x2apRequestPartDecodes"].append("%s: %d components, X2 peers %s, want one X2 component per peer %s" % (
                f, d["components"], sorted(d["x2peers"]), peers))
        for x in d["x2"]:
            p["x2apRequestPartDecodes"] += ["%s: %s" % (f, b) for b in x2_problems(nid, x)]
        if not enb:
            bad = rcdef_problems(d["rcdef"], sent_ids) if d.get("rcdef") else ["no RAN function 3 definition"]
            p["style5Action3Announced"] += ["%s: %s" % (f, b) for b in bad]
    if not (subs["requests"] >= 1 and subs["responses"] >= 1):
        p["kpimonSubscribedAll"].append("node %d: %d KPM subscription requests, %d responses" % (
            nid, subs["requests"], subs["responses"]))
    return p


def x2_problems(nid, d):
    if "error" in d:
        return ["X2 request part does not decode: " + d["error"]]
    ies, bad = d["ies"], []
    if nid == 1:
        if d["node"] != "init-eNB":
            return ["X2 initiating node %s, want init-eNB" % d["node"]]
        g = ies.get("id-GlobalENB-ID", {})
        if g.get("pLMN-Identity") != PLMN or g.get("eNB-ID") != ["macro-eNB-ID", [1, 20]]:
            bad.append("X2 Global ENB ID %s" % g)
        cells = [c["servedEUTRACellInfo"] for c in ies.get("id-ServedEUTRAcellsENDCX2ManagementList", [])]
        want = {"cellId": {"pLMN-Identity": PLMN, "eUTRANcellIdentifier": [(1 << 8) | 1, 28]}, "pCI": 1, "tAC": "0001"}
        if len(cells) != 1 or any(cells[0].get(k) != v for k, v in want.items()):
            bad.append("served E-UTRA cells %s, want one with %s" % (cells, want))
        elif cells[0].get("eUTRA-Mode-Info", [None, {}])[1].get("dL-EARFCN") != 100:
            bad.append("served E-UTRA cell DL EARFCN is not 100")
        return bad
    if d["node"] != "init-en-gNB":
        return ["X2 initiating node %s, want init-en-gNB" % d["node"]]
    g = ies.get("id-Globalen-gNB-ID", {})
    if g.get("pLMN-Identity") != PLMN or g.get("gNB-ID") != ["gNB-ID", [nid, 32]]:
        bad.append("X2 Global en-gNB ID %s" % g)
    cells = [c["servedNRCellInfo"] for c in ies.get("id-ServedNRcellsENDCX2ManagementList", [])]
    want = {"nrCellID": {"pLMN-Identity": PLMN, "nRcellIdentifier": [(nid << 4) | 1, 36]}, "nrpCI": nid,
            "configured-TAC": "0001"}
    if len(cells) != 1 or any(cells[0].get(k) != v for k, v in want.items()):
        return bad + ["served NR cells %s, want one with %s" % (cells, want)]
    mode = (cells[0].get("nrModeInfo") or [None, {}])[1]
    freq = mode.get("nRFreqInfo", {})
    if freq.get("nRARFCN") != NR_POINT_A or [b.get("freqBandIndicatorNr") for b in freq.get("freqBandListNr", [])] != [78]:
        bad.append("served NR cell frequency %s, want NRARFCN %d (Point A) band n78" % (freq, NR_POINT_A))
    txbw = mode.get("nR-TxBW") or {}
    if {k: txbw.get(k) for k in NR_TXBW} != NR_TXBW:
        bad.append("served NR cell nR-TxBW %s, want %s" % (txbw, NR_TXBW))
    if cells[0].get("mtcDecodes") is not True:
        bad.append("served NR cell MeasurementTimingConfiguration does not decode")
    else:
        timing = cells[0].get("mtcMeasTiming") or []
        ft = [t.get("frequencyAndTiming") or {} for t in timing]
        if len(ft) != 1 or ft[0].get("carrierFreq") != NR_SSB_ARFCN or ft[0].get("ssbSubcarrierSpacing") != NR_SSB_SCS:
            bad.append("served NR cell MTC MeasTiming %s, want exactly one with carrierFreq %d and SSB SCS %s" % (
                timing, NR_SSB_ARFCN, NR_SSB_SCS))
    return bad


def param_ids(o, key="ranParameter-ID"):
    """Every RAN parameter ID in a decoded value, at any depth (a RANParameter-Definition's structure and list children,
    or a control message's nested parameters)."""
    out = set()
    if isinstance(o, dict):
        if isinstance(o.get(key), int):
            out.add(o[key])
        for v in o.values():
            out |= param_ids(v, key)
    elif isinstance(o, (list, tuple)):
        for v in o:
            out |= param_ids(v, key)
    return out


def rcdef_problems(d, sent_ids=()):
    """The RC definition announces exactly {(5, 3)}, under the E2SM-RC OID, its parameters (recursively) covering
    1 to 4, P_I4 and every parameter ID of the run's acknowledged Style 5 action 3 control messages (sent_ids)."""
    if "error" in d:
        return ["RAN function 3 definition does not decode: " + d["error"]]
    oid = d.get("ranFunction-Name", {}).get("ranFunction-E2SM-OID")
    styles = d.get("ranFunctionDefinition-Control", {}).get("ric-ControlStyle-List", [])
    pairs = sorted((s.get("ric-ControlStyle-Type"), a.get("ric-ControlAction-ID"))
                   for s in styles for a in s.get("ric-ControlAction-List", []))
    acts = [a for s in styles if s.get("ric-ControlStyle-Type") == 5 for a in s.get("ric-ControlAction-List", [])
            if a.get("ric-ControlAction-ID") == 3]
    params = param_ids([a.get("ran-ControlActionParameters-List", []) for a in acts])
    bad = [] if oid == RC_OID else ["OID %s, want %s" % (oid, RC_OID)]
    if len(acts) != 1 or not {1, 2, 3, 4} | P_I4 | set(sent_ids) <= params:
        bad.append("Style 5 action 3 entries %d, its RAN parameters %s (want one, covering %s)" % (
            len(acts), sorted(params), sorted({1, 2, 3, 4} | P_I4 | set(sent_ids))))
    if pairs != [(5, 3)]:
        bad.append("announced control (style, action) %s, want exactly [(5, 3)]" % pairs)
    return bad


def _wire_module(name, filename):
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, "..", "..", "tools", "e2-evidence", filename))
    assert spec and spec.loader
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def assoc_attribution(facts, node_ips):
    """(node_of(ip, port, t) -> (node, problem), {ip: {nodes}}) by the frame's SCTP association (module docstring)."""
    km = _wire_module("kpm_ue_list_moves", "kpm-ue-list-moves.py")
    multi = km.ip_nodes(node_ips)
    return km.assoc_node_of(facts, multi), multi


def setup(a):
    facts, node_ips = json.load(open(a.facts)), json.load(open(a.node_ips))
    node_of, _ = assoc_attribution(facts, node_ips)
    pdus, items, problems = tshark_setup_pdus(a.pcap), {}, []
    by_node = {int(n): [] for n in node_ips}
    for r in facts["setup_requests"]:
        n, why = node_of(r["src"], r["sport"], r["t"])
        if why:
            problems.append("setup request frame %d: %s" % (r["frame"], why))
            continue
        if n not in by_node:
            problems.append("setup request frame %d: node %d is not in node-ips.json" % (r["frame"], n))
            continue
        items["f%d" % r["frame"]] = pdus.get(r["frame"], [])
        by_node[n].append(r)
    acked = [i for i in (json.loads(x) for x in open(a.injected) if x.strip()) if i["expect"] == "ack"] if a.injected else []
    for i in acked:
        items["ctl:%s" % i["tag"]] = [i["messageHex"]]
    res = subprocess.run(shlex.split(a.decode_cmd), input=json.dumps(items), capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("decoder failed: " + res.stderr.strip()[-400:])
    decoded = json.loads(res.stdout)
    sent_ids = set()
    for i in acked:
        got = (decoded.get("ctl:%s" % i["tag"]) or [{}])[0]
        if "error" in got or "ids" not in got:
            problems.append("acknowledged control %s: message does not decode: %s" % (i["tag"], got))
        else:
            sent_ids |= set(got["ids"])
    subs = {n: {"requests": 0, "responses": 0} for n in by_node}
    for key, ip_k, port_k in (("requests", "dst", "dport"), ("responses", "src", "sport")):
        for r in facts["sub_requests" if key == "requests" else "sub_responses"]:
            if key == "requests" and r.get("ran_function_id") != 2:
                continue
            n, why = node_of(r[ip_k], r[port_k], r["t"])
            if why or n not in subs:
                problems.append("subscription %s frame %s: %s" % (key[:-1], r.get("frame"), why or "node %s not in node-ips.json" % n))
                continue
            subs[n][key] += 1
    checks, nodes = {}, {}
    for n, reqs in by_node.items():
        nodes[n] = {"setupFrames": [r["frame"] for r in reqs], "subscriptions": subs[n],
                    "decoded": {"f%d" % r["frame"]: decoded.get("f%d" % r["frame"]) for r in reqs}}
        for k, bad in judge_node(n, reqs, decoded, subs[n], x2_peers(n, by_node), sent_ids).items():
            checks.setdefault(k, []).extend(bad)
    # an unattributed frame is a problem of every check it could have fed
    for k in checks:
        checks[k].extend(problems)
    out = {"checks": {k: {"pass": not v, "detail": v or ["every node as expected"]} for k, v in checks.items()},
           "nodes": nodes, "acknowledgedControlParameterIds": sorted(sent_ids)}
    json.dump(out, open(a.out, "w"), indent=1, sort_keys=True)
    for k, v in sorted(out["checks"].items()):
        print("%-24s %s %s" % (k, "PASS" if v["pass"] else "FAIL", "; ".join(v["detail"])[:400]))
    return 0 if all(v["pass"] for v in out["checks"].values()) else 1


def controls(a):
    wc1 = _wire_module("wc1", "wire-c1-extract.py")
    node_ips = json.load(open(a.node_ips))
    node_of, _ = assoc_attribution(json.load(open(a.facts)), node_ips)
    ip2node = wc1.ip_map(node_ips)
    reqs, p1 = wc1.rc_requests(a.pcap, ip2node, None, None)
    answers, p2 = wc1.rc_answers(a.pcap, ip2node, None, None)
    # the shared-IP notes of the IP map are superseded by the association rule below
    problems, rows = [p for p in p1 + p2 if "which node-ips.json lists for nodes" not in p], []
    for r in reqs:
        r["viaNode"], why = node_of(r["dst"], r["dport"], r["t"])
        if why:
            problems.append("request %s: %s" % (r["id"], why))
    for x in answers:
        x["viaNode"], why = node_of(x["src"], x["sport"], x["t"])
        if why:
            problems.append("answer %s: %s" % (x["id"], why))
    for inj in (json.loads(x) for x in open(a.injected) if x.strip()):
        on = [r for r in reqs if r["hdr"] == inj["headerHex"].upper() and r["msg"] == inj["messageHex"].upper()]
        row = {"tag": inj["tag"], "requests": [(r["frame"], r["viaNode"]) for r in on]}
        if len(on) != 1 or on[0]["viaNode"] != inj["node"]:
            problems.append("%s: on the wire %s, want once to node %d" % (inj["tag"], row["requests"], inj["node"]))
        else:
            r = on[0]
            ans = [x for x in answers if x["viaNode"] == r["viaNode"] and (x["requestorId"], x["instanceId"]) == (
                r["requestorId"], r["instanceId"])]
            got = [x["kind"] if x["kind"] == "ack" else "failure:" + wc1.cause_name(x["cause"]) for x in ans]
            row["answers"] = got
            if got != [inj["expect"]]:
                problems.append("%s: answers %s, want [%s]" % (inj["tag"], got, inj["expect"]))
        rows.append(row)
    json.dump({"controls": rows, "problems": problems}, open(a.out, "w"), indent=1)
    print(json.dumps(rows))
    print("problems:", problems or "none")
    return 1 if problems else 0


def record_parts(rec):
    """(node, [(peer Global ID, request part hex or None, problem)]) of one e2mgr nodeb record."""
    nb = rec.get("globalNbId", {})
    bits = nb.get("nbId", "")
    node = int(bits, 2) if bits and set(bits) <= {"0", "1"} else None
    body = rec.get("enb") if rec.get("nodeType") == "ENB" else rec.get("gnb")
    out = []
    for c in (body or {}).get("nodeConfigs", []):
        if c.get("e2nodeComponentInterfaceType") != "x2":
            continue
        x = c.get("e2nodeComponentInterfaceTypeX2", {})
        g, kind = (x.get("globalEngnbId"), "en-gNB") if x.get("globalEngnbId") else (x.get("globalEnbId"), "eNB")
        g = g or {}
        pid = g.get("gnbId") or g.get("eNBId") or g.get("enbId") or ""
        peer = "%s/%s/%s/%d" % (kind, (g.get("plmnIdentity") or "").lower(),
                                int(pid, 2) if pid and set(pid) <= {"0", "1"} else pid, len(pid))
        try:
            raw = base64.b64decode(c.get("e2nodeComponentRequestPart") or "", validate=True)
        except (binascii.Error, ValueError) as ex:
            out.append((peer, None, "request part is not base64: %s" % ex))
            continue
        text = raw.decode("ascii", "replace")
        hx = text.lower() if raw and all(ch in "0123456789abcdefABCDEF" for ch in text) else raw.hex()
        out.append((peer, hx, None if hx else "empty request part"))
    return node, out


def x2_parts(setup_out, records):
    wire = {}
    for n, d in json.load(open(setup_out))["nodes"].items():
        frames = sorted(d.get("decoded", {}), key=lambda f: int(f[1:]))
        setups = [x for f in frames[-1:] for x in (d["decoded"][f] or []) if x.get("message") == "E2setupRequest"]
        if setups:
            wire[int(n)] = {"%s/%s/%s/%s" % tuple(p): h for p, h in zip(setups[0]["x2peers"], setups[0].get("x2hex", []))}
    problems, rows = [], 0
    for path in records:
        node, parts = record_parts(json.load(open(path)))
        if not parts:
            problems.append("%s: no X2 component" % path)
        with open(path + ".x2-parts.hex", "w") as f:
            for peer, hx, why in parts:
                if why:
                    problems.append("%s %s: %s" % (path, peer, why))
                    continue
                f.write("%s %s\n" % (peer, hx))
        lines = [l.split() for l in open(path + ".x2-parts.hex") if l.strip()]
        again = {peer: hx for peer, hx, why in record_parts(json.load(open(path)))[1] if not why}
        if len(lines) != len(parts) or any(len(l) != 2 or again.get(l[0]) != l[1] for l in lines):
            problems.append("%s: sidecar lines %d for %d X2 components, or a line differs from its record field" % (
                path, len(lines), len(parts)))
        for peer, hx in (l for l in lines if len(l) == 2):
            w = wire.get(node, {}).get(peer)
            rows += 1
            if w is None or w.lower() != hx:
                problems.append("%s node %s %s: stored request part != the node's E2 Setup Request on the wire (%s)" % (
                    path, node, peer, "no such component on the wire" if w is None else "octets differ"))
    print(json.dumps({"records": len(records), "x2Components": rows, "problems": problems, "pass": not problems}))
    return 0 if not problems and rows else 1


def verdict(path, name):
    c = json.load(open(path))["checks"].get(name)
    print(json.dumps(c) if c else "no check %s" % name)
    return 0 if c and c["pass"] else 1


NODES = [1, 2, 3]


def self_test():
    """The judge on decodes shaped as the image returns them (pycrate values made plain)."""
    def gnb(n, nci=None, bits=32, pci=None, arfcn=NR_POINT_A, scs="scs60", nrb="nrb24", ssb=NR_SSB_ARFCN,
            ssb_scs="kHz30", timings=1):
        timing = {"frequencyAndTiming": {"carrierFreq": ssb, "ssbSubcarrierSpacing": ssb_scs,
                                         "ssb-MeasurementTimingConfiguration": {"periodicityAndOffset": ["sf20", 0],
                                                                                "duration": "sf1"}}}
        cell = {"nrpCI": n if pci is None else pci, "configured-TAC": "0001", "mtcDecodes": True,
                "mtcMeasTiming": [timing] * timings,
                "nrCellID": {"pLMN-Identity": PLMN, "nRcellIdentifier": [(n << 4) | 1 if nci is None else nci, 36]},
                "nrModeInfo": ["tdd", {"nRFreqInfo": {"nRARFCN": arfcn, "freqBandListNr": [{"freqBandIndicatorNr": 78}]},
                                       "nR-TxBW": {"nRSCS": scs, "nRNRB": nrb}}]}
        return {"node": "init-en-gNB", "ies": {"id-Globalen-gNB-ID": {"pLMN-Identity": PLMN, "gNB-ID": ["gNB-ID", [n, bits]]},
                                               "id-ServedNRcellsENDCX2ManagementList": [{"servedNRCellInfo": cell}]}}
    enb = {"node": "init-eNB", "ies": {"id-GlobalENB-ID": {"pLMN-Identity": PLMN, "eNB-ID": ["macro-eNB-ID", [1, 20]]},
                                       "id-ServedEUTRAcellsENDCX2ManagementList": [{"servedEUTRACellInfo": {
                                           "pCI": 1, "tAC": "0001", "cellId": {"pLMN-Identity": PLMN,
                                                                                "eUTRANcellIdentifier": [257, 28]},
                                           "eUTRA-Mode-Info": ["fDD", {"dL-EARFCN": 100}]}}]}}

    def rcdef(style=5, action=3, params=(1, 2, 3, 4), oid=RC_OID):
        return {"ranFunction-Name": {"ranFunction-E2SM-OID": oid}, "ranFunctionDefinition-Control": {
            "ric-ControlStyle-List": [{"ric-ControlStyle-Type": style, "ric-ControlAction-List": [
                {"ric-ControlAction-ID": action, "ran-ControlActionParameters-List": [{"ranParameter-ID": i} for i in params]}]}]}}

    def nested(leaf=4):
        """Parameter 1 > 2 (a structure) > 3 (a list) > 4, as RANParameter-Definition children."""
        item = lambda i, kids, alt: {"ranParameter-ID": i, "ranParameter-name": "p%d" % i, **({"ranParameter-Definition": {
            "ranParameter-Definition-Choice": [alt, {("ranParameter-List" if alt == "choiceLIST" else "ranParameter-STRUCTURE"): kids}]}}
            if kids else {})}
        three = item(3, [item(leaf, [], None)] if leaf else [], "choiceLIST")
        d = rcdef(params=())
        d["ranFunctionDefinition-Control"]["ric-ControlStyle-List"][0]["ric-ControlAction-List"][0][
            "ran-ControlActionParameters-List"] = [item(1, [item(2, [three], "choiceSTRUCTURE")], "choiceSTRUCTURE")]
        return d

    def two_styles():
        d = rcdef()
        d["ranFunctionDefinition-Control"]["ric-ControlStyle-List"].append(
            {"ric-ControlStyle-Type": 3, "ric-ControlAction-List": [{"ric-ControlAction-ID": 1}]})
        return d

    def run(nid, x2, rc=None, req=None, subs=(1, 1), dec=None):
        """req overrides the tshark facts, dec the independent decode of the setup PDU."""
        enb = nid == 1
        d = {"message": "E2setupRequest", "globalId": ["eNB", PLMN, 1, 20] if enb else ["en-gNB", PLMN, nid, 32],
             "ranFunctionIds": [2] if enb else [2, 3], "components": 2 if enb else 1, "x2": [x2] * (2 if enb else 1),
             "x2peers": x2_peers(nid, NODES)}
        if rc is not None:
            d["rcdef"] = rc
        d.update(dec or {})
        r = {"frame": 7, "e2node_type": "eNB" if enb else "en-gNB", "node_id": nid, "node_id_bits": 20 if enb else 32,
             "plmn": PLMN, "ran_function_ids": [2] if enb else [2, 3]}
        r.update(req or {})
        got = judge_node(nid, [r], {"f7": [{"message": "RICserviceUpdate"}, d]}, {"requests": subs[0], "responses": subs[1]},
                         x2_peers(nid, NODES))
        return {k: v for k, v in got.items() if v}

    cases = [
        ("en-gNB 2 as expected", run(2, gnb(2), rcdef()) == {}),
        ("eNB 1 as expected", run(1, enb) == {}),
        ("en-gNB with a 22-bit gNB ID on the wire", "globalIds" in run(2, gnb(2), rcdef(), {"node_id_bits": 22})),
        ("en-gNB announced as a gNB", "globalIds" in run(2, gnb(2), rcdef(), {"e2node_type": "gNB"})),
        ("eNB announcing RC", "ranFunctions" in run(1, enb, req={"ran_function_ids": [2, 3]})),
        ("en-gNB without RC", "ranFunctions" in run(2, gnb(2), rcdef(), {"ran_function_ids": [2]})),
        ("served NR cell of another gNB", "x2apRequestPartDecodes" in run(2, gnb(2, nci=(3 << 4) | 1), rcdef())),
        ("served NR cell in the N5 form", "x2apRequestPartDecodes" in run(2, gnb(2, nci=0x203), rcdef())),
        ("X2 Global en-gNB ID of 22 bits", "x2apRequestPartDecodes" in run(2, gnb(2, bits=22), rcdef())),
        ("NR PCI not the cellId", "x2apRequestPartDecodes" in run(2, gnb(2, pci=1), rcdef())),
        ("NRARFCN 633333, off n78's 30 kHz raster as Point A", "x2apRequestPartDecodes" in run(
            2, gnb(2, arfcn=633333), rcdef())),
        ("MTC carrierFreq equal to the NRARFCN", "x2apRequestPartDecodes" in run(2, gnb(2, ssb=NR_POINT_A), rcdef())),
        ("nR-TxBW scs30/nrb106", "x2apRequestPartDecodes" in run(2, gnb(2, scs="scs30", nrb="nrb106"), rcdef())),
        ("MTC SSB SCS kHz15", "x2apRequestPartDecodes" in run(2, gnb(2, ssb_scs="kHz15"), rcdef())),
        ("MTC with two MeasTimings", "x2apRequestPartDecodes" in run(2, gnb(2, timings=2), rcdef())),
        ("X2 part that does not decode", "x2apRequestPartDecodes" in run(2, {"error": "x"}, rcdef())),
        ("eNB with an init-en-gNB part", "x2apRequestPartDecodes" in run(1, gnb(1))),
        ("RC without Style 5 action 3", "style5Action3Announced" in run(2, gnb(2), rcdef(style=3, action=1))),
        ("RC Style 5 action 3 without parameter 4", "style5Action3Announced" in run(2, gnb(2), rcdef(params=(1, 2, 3)))),
        ("RC under another OID", "style5Action3Announced" in run(2, gnb(2), rcdef(oid="1.3.6.1.4.1.53148.1.1.2.2"))),
        ("RC parameters 1 to 4 nested (structure and list children)", run(2, gnb(2), nested()) == {}),
        ("RC definition still listing Style 3 action 1", "style5Action3Announced" in run(2, gnb(2), two_styles())),
        ("RC definition lacking the nested NR CGI parameter", "style5Action3Announced" in run(2, gnb(2), nested(leaf=None))),
        ("RC definition lacking a parameter the run's acknowledged control sent", bool(
            rcdef_problems(rcdef(), sent_ids=(1, 2, 3, 4, 9)))),
        ("node never subscribed", "kpimonSubscribedAll" in run(1, enb, subs=(0, 0))),
        ("subscription never answered", "kpimonSubscribedAll" in run(2, gnb(2), rcdef(), subs=(1, 0))),
        ("tshark and the decode disagree on the gNB ID", "globalIds" in run(2, gnb(2), rcdef(),
                                                                         dec={"globalId": ["en-gNB", PLMN, 3, 32]})),
        ("decoded RAN functions differ from tshark's", "ranFunctions" in run(2, gnb(2), rcdef(), dec={"ranFunctionIds": [2]})),
        ("an NG component beside the X2 one", "x2apRequestPartDecodes" in run(2, gnb(2), rcdef(), dec={"components": 2})),
        ("eNB with one X2 component for two en-gNB neighbours", "x2apRequestPartDecodes" in run(
            1, enb, dec={"components": 1, "x2": [enb], "x2peers": [["en-gNB", PLMN, 2, 32]]})),
        ("eNB X2 component naming a node that is not its neighbour", "x2apRequestPartDecodes" in run(
            1, enb, dec={"x2peers": [["en-gNB", PLMN, 2, 32], ["en-gNB", PLMN, 4, 32]]})),
        ("en-gNB X2 component naming another en-gNB", "x2apRequestPartDecodes" in run(
            2, gnb(2), rcdef(), dec={"x2peers": [["en-gNB", PLMN, 3, 32]]})),
        ("the second eNB X2 request part fails", "x2apRequestPartDecodes" in run(1, enb, dec={"x2": [enb, {"error": "x"}]})),
        ("no independently decoded setup request in the frame", set(judge_node(
            2, [{"frame": 7}], {"f7": [{"error": "x"}]}, {"requests": 1, "responses": 1}, [])) >= {"globalIds"} and all(
            judge_node(2, [{"frame": 7}], {"f7": [{"error": "x"}]}, {"requests": 1, "responses": 1}, [])[k]
            for k in ("globalIds", "ranFunctions", "x2apRequestPartDecodes", "style5Action3Announced"))),
        ("node without a setup request fails every check", len([v for v in judge_node(3, [], {}, {}, []).values() if v]) == 5),
    ]
    for name, ok in cases:
        print("%s %s" % ("ok  " if ok else "FAIL", name))
    ok = all(c[1] for c in cases)
    print("e2i wire checks self-test: %s" % ("ok" if ok else "FAIL"))
    return 0 if ok else 1


def decode_self_test():
    sys.path.insert(0, "/opt/asn1-indep")
    g, e = decode_x2(AC6A_EN_GNB_7F000001), decode_x2(AC6A_ENB_FFFFE)
    cells = g["ies"]["id-ServedNRcellsENDCX2ManagementList"]
    ok = (g["node"] == "init-en-gNB" and g["ies"]["id-Globalen-gNB-ID"]["gNB-ID"] == ["gNB-ID", [0x7F000001, 32]]
          and cells[0]["servedNRCellInfo"]["nrCellID"]["nRcellIdentifier"] == [(0x7F000001 << 4) | 1, 36]
          and cells[0]["servedNRCellInfo"]["mtcDecodes"] is True
          and e["node"] == "init-eNB" and e["ies"]["id-GlobalENB-ID"]["eNB-ID"] == ["macro-eNB-ID", [0xFFFFE, 20]]
          and "error" in decode_x2("00") and "error" in decode_setup("00"))
    print("e2i decode self-test: %s" % ("ok" if ok else "FAIL %s %s" % (g, e)))
    return 0 if ok else 1


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    if sys.argv[1:] == ["--decode-self-test"]:
        return decode_self_test()
    if sys.argv[1:] == ["decode"]:
        sys.path.insert(0, "/opt/asn1-indep")
        print(json.dumps({k: [decode_control_ids(h) if k.startswith("ctl:") else decode_setup(h) for h in v]
                          for k, v in json.load(sys.stdin).items()}))
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "verdict":
        return verdict(sys.argv[2], sys.argv[3])
    if len(sys.argv) >= 4 and sys.argv[1] == "x2-parts":
        return x2_parts(sys.argv[2], sys.argv[3:])
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("setup")
    s.add_argument("facts")
    s.add_argument("pcap")
    s.add_argument("--node-ips", required=True)
    s.add_argument("--decode-cmd", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--injected")
    c = sub.add_parser("controls")
    c.add_argument("--facts", required=True)
    c.add_argument("pcap")
    c.add_argument("--node-ips", required=True)
    c.add_argument("--injected", required=True)
    c.add_argument("--out", required=True)
    a = ap.parse_args()
    return setup(a) if a.cmd == "setup" else controls(a)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""e2i-wire-checks.py: the E2 interop gate's wire checks, judged on the capture and on an independent decoder.

  setup FACTS PCAP --node-ips F --decode-cmd CMD --out OUT   E2 Setup Requests of every node (FACTS = the
        e2ap-pcap-facts.py output of PCAP; F = {"<nodeId>": [ip, ...]}): Global E2 Node ID, RAN functions, the X2
        component's request part and the RAN function 3 definition, from the whole setup PDU decoded by CMD (this
        script's `decode` mode in the asn1-indep image; identity and RAN functions must agree with tshark's), and the
        KPM subscriptions; OUT = {"checks": {name: {pass, detail}}, "nodes": ...}
  controls PCAP --node-ips F --injected F --out OUT   every injected control (F: JSON lines {tag, node, headerHex,
        messageHex, expect: "ack" | "failure:<cause>"}) is on the wire once, to its node, with the injected header
        and message octets, and is answered once by that node as expected
  verdict OUT NAME      exit 0 iff check NAME of OUT passed (prints its detail)
  decode                (inside the image) stdin JSON {frame id: [E2AP PDU hex, ...]} -> stdout JSON {frame id:
                        [decode_setup of each PDU]}
  --decode-self-test    (inside the image) decode the AC6a probe nodes' X2 request parts
  --self-test           the judge on synthetic decodes, positive and negative

Expected identity (plan R-3): node 1 is the LTE eNB (Global ENB ID, macro eNB ID 1 in 20 bits; X2 init-eNB with one
served E-UTRA cell, ECI = 1 << 8 | 1, PCI 1, TAC 0001, EARFCN 100/18100) announcing KPM only; node n >= 2 is an
en-gNB (Global en-gNB ID, gNB ID n in 32 bits; X2 init-en-gNB with one served NR cell, NCI = n << 4 | 1, PCI n,
TAC 0001, NR-ARFCN 633333, band n78, a decodable MTC) announcing KPM (2) and RC (3), whose definition holds Style 5
action 3 with RAN parameters 1 to 4 under the E2SM-RC OID. PLMN 001/01 (00F110) everywhere.
"""
import importlib.util
import json
import os
import shlex
import subprocess
import sys

PLMN = "00f110"
RC_OID = "1.3.6.1.4.1.53148.1.1.2.3"
# AC6a probe nodes' X2 request parts as they were on the wire (frames 6 and 17 of its capture)
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


def decode_x2(hexpart):
    """{node, ies} of an X2 request part (each served NR cell gains mtcDecodes) or {error}, inside the image."""
    from e2indep import x2ap
    try:
        d = x2ap.decode_endc_x2_setup_request(bytes.fromhex(hexpart))
        for c in d["ies"].get("id-ServedNRcellsENDCX2ManagementList", []):
            mtc = c["servedNRCellInfo"].get("measurementTimingConfiguration")
            c["servedNRCellInfo"]["mtcDecodes"] = bool(mtc) and bool(x2ap.decode_measurement_timing_configuration(mtc))
        return plain(d)
    except Exception as ex:  # noqa: BLE001 - every decode failure is a finding
        return {"error": "%s: %s" % (type(ex).__name__, ex)}


def decode_setup(hexpdu):
    """One E2AP PDU, inside the image: for an E2setupRequest {message, globalId: [type, plmn, id, bits],
    ranFunctionIds, x2: [decoded X2 request part per x2 component], components, rcdef (RAN function 3's definition,
    decoded, when announced)}; otherwise {message} or {error}."""
    from e2indep import e2ap, e2sm_rc
    try:
        d = e2ap.decode_e2ap(bytes.fromhex(hexpdu))
    except Exception as ex:  # noqa: BLE001
        return {"error": "%s: %s" % (type(ex).__name__, ex)}
    if d["message"] != "E2setupRequest":
        return {"message": d["message"]}
    ies = d["ies"]
    kind, body = ies["id-GlobalE2node-ID"]
    gid = body.get("global-en-gNB-ID") or body.get("global-eNB-ID") or {}
    _, (val, bits) = gid.get("gNB-ID") or gid.get("eNB-ID") or (None, (None, None))
    funcs = e2ap.items(ies.get("id-RANfunctionsAdded", []))
    comps = e2ap.items(ies.get("id-E2nodeComponentConfigAddition", []))
    out = {"message": d["message"], "globalId": [kind, plain(gid.get("pLMN-Identity")), val, bits],
           "ranFunctionIds": sorted(f["ranFunctionID"] for f in funcs), "components": len(comps),
           "x2": [decode_x2(c["e2nodeComponentConfiguration"]["e2nodeComponentRequestPart"].hex())
                  for c in comps if c["e2nodeComponentInterfaceType"] == "x2"]}
    rc = [f["ranFunctionDefinition"] for f in funcs if f["ranFunctionID"] == 3]
    if rc:
        try:
            out["rcdef"] = plain(e2sm_rc.decode_ran_function_definition(rc[0]))
        except Exception as ex:  # noqa: BLE001
            out["rcdef"] = {"error": "%s: %s" % (type(ex).__name__, ex)}
    return out


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


def judge_node(nid, reqs, decoded, subs):
    """Problems per check name for one node: reqs = its setup-request facts (tshark), decoded = frame id -> the
    independent decodes of that frame's PDUs. Identity and RAN functions must agree in both."""
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
        if len(d["x2"]) != 1 or d["components"] != 1:
            p["x2apRequestPartDecodes"].append("%s: %d components, %d X2, want one X2" % (f, d["components"], len(d["x2"])))
        for x in d["x2"]:
            p["x2apRequestPartDecodes"] += ["%s: %s" % (f, b) for b in x2_problems(nid, x)]
        if not enb:
            bad = rcdef_problems(d["rcdef"]) if d.get("rcdef") else ["no RAN function 3 definition"]
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
    freq = (cells[0].get("nrModeInfo") or [None, {}])[1].get("nRFreqInfo", {})
    if freq.get("nRARFCN") != 633333 or [b.get("freqBandIndicatorNr") for b in freq.get("freqBandListNr", [])] != [78]:
        bad.append("served NR cell frequency %s, want NR-ARFCN 633333 band n78" % freq)
    if cells[0].get("mtcDecodes") is not True:
        bad.append("served NR cell MeasurementTimingConfiguration does not decode")
    return bad


def rcdef_problems(d):
    if "error" in d:
        return ["RAN function 3 definition does not decode: " + d["error"]]
    oid = d.get("ranFunction-Name", {}).get("ranFunction-E2SM-OID")
    styles = d.get("ranFunctionDefinition-Control", {}).get("ric-ControlStyle-List", [])
    acts = [a for s in styles if s.get("ric-ControlStyle-Type") == 5 for a in s.get("ric-ControlAction-List", [])
            if a.get("ric-ControlAction-ID") == 3]
    params = {q.get("ranParameter-ID") for a in acts for q in a.get("ran-ControlActionParameters-List", [])}
    bad = [] if oid == RC_OID else ["OID %s, want %s" % (oid, RC_OID)]
    if len(acts) != 1 or not {1, 2, 3, 4} <= params:
        bad.append("Style 5 action 3 entries %d, its RAN parameters %s (want one, with 1 to 4)" % (len(acts), sorted(params)))
    return bad


def setup(a):
    facts = json.load(open(a.facts))
    ip2node = {ip: int(n) for n, ips in json.load(open(a.node_ips)).items() for ip in ips}
    pdus, items = tshark_setup_pdus(a.pcap), {}
    by_node = {n: [] for n in sorted(set(ip2node.values()))}
    for r in facts["setup_requests"]:
        n = ip2node.get(r["src"])
        if n is not None:
            items["f%d" % r["frame"]] = pdus.get(r["frame"], [])
            by_node[n].append(r)
    res = subprocess.run(shlex.split(a.decode_cmd), input=json.dumps(items), capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("decoder failed: " + res.stderr.strip()[-400:])
    decoded = json.loads(res.stdout)
    checks, nodes = {}, {}
    for n, reqs in by_node.items():
        ips = [ip for ip, m in ip2node.items() if m == n]
        subs = {"requests": sum(1 for s in facts["sub_requests"] if s["dst"] in ips and s.get("ran_function_id") == 2),
                "responses": sum(1 for s in facts["sub_responses"] if s["src"] in ips)}
        nodes[n] = {"setupFrames": [r["frame"] for r in reqs], "subscriptions": subs,
                    "decoded": {"f%d" % r["frame"]: decoded.get("f%d" % r["frame"]) for r in reqs}}
        for k, bad in judge_node(n, reqs, decoded, subs).items():
            checks.setdefault(k, []).extend(bad)
    out = {"checks": {k: {"pass": not v, "detail": v or ["every node as expected"]} for k, v in checks.items()},
           "nodes": nodes}
    json.dump(out, open(a.out, "w"), indent=1, sort_keys=True)
    for k, v in sorted(out["checks"].items()):
        print("%-24s %s %s" % (k, "PASS" if v["pass"] else "FAIL", "; ".join(v["detail"])[:400]))
    return 0 if all(v["pass"] for v in out["checks"].values()) else 1


def controls(a):
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("wc1", os.path.join(here, "../../tools/e2-evidence/wire-c1-extract.py"))
    assert spec and spec.loader
    wc1 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wc1)
    ip2node = {ip: int(n) for n, ips in json.load(open(a.node_ips)).items() for ip in ips}
    reqs, p1 = wc1.rc_requests(a.pcap, ip2node, None, None)
    answers, p2 = wc1.rc_answers(a.pcap, ip2node, None, None)
    problems, rows = p1 + p2, []
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


def verdict(path, name):
    c = json.load(open(path))["checks"].get(name)
    print(json.dumps(c) if c else "no check %s" % name)
    return 0 if c and c["pass"] else 1


def self_test():
    """The judge on decodes shaped as the image returns them (pycrate values made plain)."""
    def gnb(n, nci=None, bits=32, pci=None):
        cell = {"nrpCI": n if pci is None else pci, "configured-TAC": "0001", "mtcDecodes": True,
                "nrCellID": {"pLMN-Identity": PLMN, "nRcellIdentifier": [(n << 4) | 1 if nci is None else nci, 36]},
                "nrModeInfo": ["tdd", {"nRFreqInfo": {"nRARFCN": 633333, "freqBandListNr": [{"freqBandIndicatorNr": 78}]}}]}
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

    def run(nid, x2, rc=None, req=None, subs=(1, 1), dec=None):
        """req overrides the tshark facts, dec the independent decode of the setup PDU."""
        enb = nid == 1
        d = {"message": "E2setupRequest", "globalId": ["eNB", PLMN, 1, 20] if enb else ["en-gNB", PLMN, nid, 32],
             "ranFunctionIds": [2] if enb else [2, 3], "components": 1, "x2": [x2]}
        if rc is not None:
            d["rcdef"] = rc
        d.update(dec or {})
        r = {"frame": 7, "e2node_type": "eNB" if enb else "en-gNB", "node_id": nid, "node_id_bits": 20 if enb else 32,
             "plmn": PLMN, "ran_function_ids": [2] if enb else [2, 3]}
        r.update(req or {})
        got = judge_node(nid, [r], {"f7": [{"message": "RICserviceUpdate"}, d]}, {"requests": subs[0], "responses": subs[1]})
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
        ("X2 part that does not decode", "x2apRequestPartDecodes" in run(2, {"error": "x"}, rcdef())),
        ("eNB with an init-en-gNB part", "x2apRequestPartDecodes" in run(1, gnb(1))),
        ("RC without Style 5 action 3", "style5Action3Announced" in run(2, gnb(2), rcdef(style=3, action=1))),
        ("RC Style 5 action 3 without parameter 4", "style5Action3Announced" in run(2, gnb(2), rcdef(params=(1, 2, 3)))),
        ("RC under another OID", "style5Action3Announced" in run(2, gnb(2), rcdef(oid="1.3.6.1.4.1.53148.1.1.2.2"))),
        ("node never subscribed", "kpimonSubscribedAll" in run(1, enb, subs=(0, 0))),
        ("subscription never answered", "kpimonSubscribedAll" in run(2, gnb(2), rcdef(), subs=(1, 0))),
        ("tshark and the decode disagree on the gNB ID", "globalIds" in run(2, gnb(2), rcdef(),
                                                                         dec={"globalId": ["en-gNB", PLMN, 3, 32]})),
        ("decoded RAN functions differ from tshark's", "ranFunctions" in run(2, gnb(2), rcdef(), dec={"ranFunctionIds": [2]})),
        ("an NG component beside the X2 one", "x2apRequestPartDecodes" in run(2, gnb(2), rcdef(), dec={"components": 2})),
        ("no independently decoded setup request in the frame", set(judge_node(
            2, [{"frame": 7}], {"f7": [{"error": "x"}]}, {"requests": 1, "responses": 1})) >= {"globalIds"} and all(
            judge_node(2, [{"frame": 7}], {"f7": [{"error": "x"}]}, {"requests": 1, "responses": 1})[k]
            for k in ("globalIds", "ranFunctions", "x2apRequestPartDecodes", "style5Action3Announced"))),
        ("node without a setup request fails every check", len([v for v in judge_node(3, [], {}, {}).values() if v]) == 5),
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
        print(json.dumps({k: [decode_setup(h) for h in v] for k, v in json.load(sys.stdin).items()}))
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "verdict":
        return verdict(sys.argv[2], sys.argv[3])
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("setup")
    s.add_argument("facts")
    s.add_argument("pcap")
    s.add_argument("--node-ips", required=True)
    s.add_argument("--decode-cmd", required=True)
    s.add_argument("--out", required=True)
    c = sub.add_parser("controls")
    c.add_argument("pcap")
    c.add_argument("--node-ips", required=True)
    c.add_argument("--injected", required=True)
    c.add_argument("--out", required=True)
    a = ap.parse_args()
    return setup(a) if a.cmd == "setup" else controls(a)


if __name__ == "__main__":
    sys.exit(main())

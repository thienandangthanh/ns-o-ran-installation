#!/usr/bin/env python3
"""e2-sub-setup-decode.py: the E2 Setup Requests and RIC subscription procedures of a capture, decoded by the
independent asn1-indep codec (pycrate), never by tshark's E2SM dissectors.

  collect PCAP           (host or VM, tshark) stdout JSON {"f<frame>": [E2AP PDU hex, ...]} of every frame holding
                         an E2 Setup Request or a RIC subscription procedure PDU, from the raw reassembled e2ap layer
                         bytes. tshark's field dissection is not used: it stops in the gNB's RC RAN function
                         definition and in some E2SM-KPM Format 3 lists.
  decode                 (inside the asn1-indep image) stdin: collect's JSON; stdout JSON {"f<frame>": [one decode
                         per PDU, in order]}. Each decode is one of
           {"message": "E2setupRequest", "globalId": GID, "components": N, "x2": [PART, ...]}
                 PART = {"node": "init-en-gNB" | "init-eNB", "globalId": GID, "cells": [CELL, ...]} | {"error": ...},
                 the X2 request part (e2nodeComponentRequestPart) of every x2 component; response parts are never
                 read. The cells are the part's own served cells: ServedNRcellsENDCX2ManagementList of an
                 init-en-gNB, ServedEUTRAcellsENDCX2ManagementList of an init-eNB.
           {"message": "RICsubscriptionRequest", "requestor", "instance", "ranFunctionId", "actions": [ACTION, ...]}
                 ACTION = {"id", "type" (report | insert | policy), "definition": null | DEF | {"error": ...}},
                 DEF = {"format" (1..5), "style", "granulPeriod", "cgi": CELL | null}, the E2SM-KPM v03.00
                 action definition
           {"message": "RICsubscriptionResponse", "requestor", "instance", "ranFunctionId", "admitted": [id, ...],
                 "notAdmitted": [[id, "group:cause"], ...]}
           {"message": "RICsubscriptionFailure", "requestor", "instance", "ranFunctionId", "cause": "group:cause"}
           {"message": <any other E2AP message>} | {"error": "<why the PDU does not decode>"}
                 GID  = [node kind (en-gNB | eNB | ...), ID CHOICE name, PLMN hex, ID value, ID bit length]
                 CELL = ["nr", PLMN hex, NR cell identity, 36] | ["eutra", PLMN hex, E-UTRA cell identity, 28]
  --decode-self-test     (inside the image) round trips through asn1-indep's own encoders: a two-cell en-gNB setup,
                         an eNB setup, a subscription with Format 1 actions naming NR and E-UTRA CGIs, a Format 1
                         action without a CGI, a Format 3 action and an undecodable definition, a response with a
                         not-admitted action and a failure; exits 0 when every decode is as built.
"""
import json
import subprocess
import sys

FILTER = "(e2ap.procedureCode == 1 && e2ap.initiatingMessage_element) || e2ap.procedureCode == 8"


def collect(pcap):
    cmd = ["tshark", "-r", pcap, "-Y", FILTER, "-T", "json", "-x", "-j", "frame e2ap"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    # a capture that is still being written can end in a partial packet: keep what was decoded
    if res.returncode != 0 and "cut short" not in res.stderr:
        sys.exit("tshark failed: " + res.stderr.strip()[-400:])
    out = {}
    for pkt in json.loads(res.stdout or "[]"):
        lay = pkt["_source"]["layers"]
        raw = lay.get("e2ap_raw", [])
        raws = raw if raw and isinstance(raw[0], list) else [raw]
        out["f%d" % int(lay["frame"]["frame.number"])] = [r[0] for r in raws if r]
    return out


def _hex(b):
    return bytes(b).hex()


def global_id(kind, gid):
    """GID of a decoded GlobalenGNB-ID or GlobalENB-ID (E2AP and X2AP use the same member names)."""
    choice, (val, bits) = gid.get("gNB-ID") or gid.get("eNB-ID") or (None, (None, None))
    return [kind, choice, _hex(gid["pLMN-Identity"]), val, bits]


def e2_global_id(e2node):
    kind, body = e2node
    gid = body.get("global-en-gNB-ID") or body.get("global-eNB-ID")
    return global_id(kind, gid) if gid else [kind, None, None, None, None]


def x2_part(octets):
    from e2indep import x2ap
    try:
        d = x2ap.decode_endc_x2_setup_request(bytes(octets))
    except Exception as ex:  # noqa: BLE001 - every decode failure is a finding
        return {"error": "%s: %s" % (type(ex).__name__, ex)}
    ies = d["ies"]
    if d["node"] == "init-en-gNB":
        gid = global_id("en-gNB", ies["id-Globalen-gNB-ID"])
        cells = [["nr", _hex(c["servedNRCellInfo"]["nrCellID"]["pLMN-Identity"])]
                 + list(c["servedNRCellInfo"]["nrCellID"]["nRcellIdentifier"])
                 for c in ies.get("id-ServedNRcellsENDCX2ManagementList", [])]
    elif d["node"] == "init-eNB":
        gid = global_id("eNB", ies["id-GlobalENB-ID"])
        cells = [["eutra", _hex(c["servedEUTRACellInfo"]["cellId"]["pLMN-Identity"])]
                 + list(c["servedEUTRACellInfo"]["cellId"]["eUTRANcellIdentifier"])
                 for c in ies.get("id-ServedEUTRAcellsENDCX2ManagementList", [])]
    else:
        return {"node": d["node"], "globalId": None, "cells": []}
    return {"node": d["node"], "globalId": gid, "cells": cells}


def kpm_cgi(cgi):
    if cgi is None:
        return None
    kind, v = cgi
    if kind == "nR-CGI":
        return ["nr", _hex(v["pLMNIdentity"])] + list(v["nRCellIdentity"])
    if kind == "eUTRA-CGI":
        return ["eutra", _hex(v["pLMNIdentity"])] + list(v["eUTRACellIdentity"])
    return [kind, None, None, None]


def action_definition(octets):
    from e2indep.codec import decode
    from e2indep_gen import E2SM_KPM_v0300 as kpm
    try:
        d = decode(kpm.E2SM_KPM_IEs.E2SM_KPM_ActionDefinition, bytes(octets))
    except Exception as ex:  # noqa: BLE001 - every decode failure is a finding
        return {"error": "%s: %s" % (type(ex).__name__, ex)}
    name, body = d["actionDefinition-formats"]
    return {"format": int(name.rsplit("Format", 1)[1]), "style": d["ric-Style-Type"],
            "granulPeriod": body.get("granulPeriod"), "cgi": kpm_cgi(body.get("cellGlobalID"))}


def _cause(c):
    return "%s:%s" % c


def decode_pdu(hexpdu):
    from e2indep import e2ap
    from e2indep.ap_protocol import items
    try:
        d = e2ap.decode_e2ap(bytes.fromhex(hexpdu))
        m, ies = d["message"], d["ies"]
        if m == "E2setupRequest":
            comps = items(ies.get("id-E2nodeComponentConfigAddition", []))
            return {"message": m, "globalId": e2_global_id(ies["id-GlobalE2node-ID"]), "components": len(comps),
                    "x2": [x2_part(c["e2nodeComponentConfiguration"]["e2nodeComponentRequestPart"])
                           for c in comps if c["e2nodeComponentInterfaceType"] == "x2"]}
        if not m.startswith("RICsubscription") or m.startswith("RICsubscriptionDelete") or "Modification" in m:
            return {"message": m}
        rid = ies["id-RICrequestID"]
        out = {"message": m, "requestor": rid["ricRequestorID"], "instance": rid["ricInstanceID"],
               "ranFunctionId": ies["id-RANfunctionID"]}
        if m == "RICsubscriptionRequest":
            acts = items(ies["id-RICsubscriptionDetails"]["ricAction-ToBeSetup-List"])
            out["actions"] = [{"id": a["ricActionID"], "type": a["ricActionType"],
                               "definition": action_definition(a["ricActionDefinition"])
                               if "ricActionDefinition" in a else None} for a in acts]
        elif m == "RICsubscriptionResponse":
            out["admitted"] = [a["ricActionID"] for a in items(ies["id-RICactions-Admitted"])]
            out["notAdmitted"] = [[a["ricActionID"], _cause(a["cause"])]
                                  for a in items(ies.get("id-RICactions-NotAdmitted", []))]
        elif m == "RICsubscriptionFailure":
            out["cause"] = _cause(ies["id-Cause"])
        return out
    except Exception as ex:  # noqa: BLE001 - every decode failure is a finding
        return {"error": "%s: %s" % (type(ex).__name__, ex)}


def decode_all(frames):
    return {k: [decode_pdu(h) for h in v] for k, v in frames.items()}


def decode_self_test():
    from e2indep import e2ap, x2ap
    from e2indep.codec import encode
    from e2indep_gen import E2SM_KPM_v0300 as kpm
    plmn = bytes.fromhex("00F110")
    mtc = x2ap.measurement_timing_configuration(633312)
    nr = lambda nci: x2ap.served_nr_cell(nci & 0xF, plmn, nci, 632758, 78, mtc, configured_tac=b"\x00\x01")
    gnb_part = x2ap.endc_x2_setup_request_en_gnb(plmn, 7, [nr(0x71), nr(0x72)])
    enb_part = x2ap.endc_x2_setup_request_enb(plmn, 1, [x2ap.served_eutra_cell(1, plmn, 0x101, b"\x00\x01", 100, 18100)])
    fn = e2ap.RanFunction(2, 2, "1.3.6.1.4.1.53148.1.2.2.2", b"\x00")
    comp = lambda peer, part: e2ap.Component("x2", e2ap.x2_component_id(**peer), part, b"")
    gnb = e2ap.e2_setup_request(1, e2ap.e2node_en_gnb(plmn, 7), [fn],
                                [comp({"global_enb": e2ap.global_enb_id(plmn, 1)}, gnb_part)])
    enb = e2ap.e2_setup_request(2, e2ap.e2node_enb(plmn, 1), [fn],
                                [comp({"global_en_gnb": e2ap.global_en_gnb_id(plmn, 7)}, enb_part)])
    label = [{"measLabel": {"noLabel": "true"}}]
    info = [{"measType": ("measName", "ns3.nodeId"), "labelInfoList": label}]
    nr_cgi = lambda nci: ("nR-CGI", {"pLMNIdentity": plmn, "nRCellIdentity": (nci, 36)})

    def f1(cgi):
        body = {"measInfoList": info, "granulPeriod": 100}
        if cgi is not None:
            body["cellGlobalID"] = cgi
        return encode(kpm.E2SM_KPM_IEs.E2SM_KPM_ActionDefinition,
                      {"ric-Style-Type": 1, "actionDefinition-formats": ("actionDefinition-Format1", body)})
    f3 = encode(kpm.E2SM_KPM_IEs.E2SM_KPM_ActionDefinition, {"ric-Style-Type": 3, "actionDefinition-formats": (
        "actionDefinition-Format3", {"measCondList": [{"measType": ("measName", "ns3.imsi"), "matchingCond": [
            {"matchingCondChoice": ("measLabel", {"noLabel": "true"})}]}], "granulPeriod": 100})})
    defs = [f1(nr_cgi(0x71)), f1(("eUTRA-CGI", {"pLMNIdentity": plmn, "eUTRACellIdentity": (0x101, 28)})), f1(None),
            f3, b"\xff\xff"]
    item = lambda i, d: e2ap.E2AP.single("RICaction-ToBeSetup-ItemIEs", "id-RICaction-ToBeSetup-Item",
                                         {"ricActionID": i, "ricActionType": "report", "ricActionDefinition": d})
    req = e2ap.build("RICsubscriptionRequest", [
        ("id-RICrequestID", {"ricRequestorID": 123, "ricInstanceID": 6}), ("id-RANfunctionID", 2),
        ("id-RICsubscriptionDetails", {"ricEventTriggerDefinition": b"\x00",
                                       "ricAction-ToBeSetup-List": [item(i + 1, d) for i, d in enumerate(defs)]})])
    resp = e2ap.ric_subscription_response((123, 6), 2, [1, 2], [(3, ("ricRequest", "action-not-supported"))])
    fail = e2ap.ric_subscription_failure((123, 7), 2, ("ricRequest", "action-not-supported"))
    got = decode_all({"f1": [gnb.hex(), enb.hex()], "f2": [req.hex(), resp.hex(), fail.hex(), "00"]})
    p = "00f110"
    want = {"f1": [
        {"message": "E2setupRequest", "globalId": ["en-gNB", "gNB-ID", p, 7, 32], "components": 1,
         "x2": [{"node": "init-en-gNB", "globalId": ["en-gNB", "gNB-ID", p, 7, 32],
                 "cells": [["nr", p, 0x71, 36], ["nr", p, 0x72, 36]]}]},
        {"message": "E2setupRequest", "globalId": ["eNB", "macro-eNB-ID", p, 1, 20], "components": 1,
         "x2": [{"node": "init-eNB", "globalId": ["eNB", "macro-eNB-ID", p, 1, 20], "cells": [["eutra", p, 0x101, 28]]}]}],
        "f2": [
        {"message": "RICsubscriptionRequest", "requestor": 123, "instance": 6, "ranFunctionId": 2, "actions": [
            {"id": 1, "type": "report", "definition": {"format": 1, "style": 1, "granulPeriod": 100, "cgi": ["nr", p, 0x71, 36]}},
            {"id": 2, "type": "report", "definition": {"format": 1, "style": 1, "granulPeriod": 100, "cgi": ["eutra", p, 0x101, 28]}},
            {"id": 3, "type": "report", "definition": {"format": 1, "style": 1, "granulPeriod": 100, "cgi": None}},
            {"id": 4, "type": "report", "definition": {"format": 3, "style": 3, "granulPeriod": 100, "cgi": None}}]},
        {"message": "RICsubscriptionResponse", "requestor": 123, "instance": 6, "ranFunctionId": 2, "admitted": [1, 2],
         "notAdmitted": [[3, "ricRequest:action-not-supported"]]},
        {"message": "RICsubscriptionFailure", "requestor": 123, "instance": 7, "ranFunctionId": 2,
         "cause": "ricRequest:action-not-supported"}]}
    bad = []
    undecodable = got["f2"][0]["actions"].pop() if got["f2"][0].get("actions") else None
    if not (undecodable and undecodable["id"] == 5 and "error" in (undecodable["definition"] or {})):
        bad.append("an undecodable action definition did not give an error: %s" % undecodable)
    if "error" not in got["f2"].pop():
        bad.append("an undecodable PDU did not give an error")
    for k in want:
        for i, (g, w) in enumerate(zip(got[k], want[k])):
            if g != w:
                bad.append("%s[%d]: decoded %s, built %s" % (k, i, json.dumps(g), json.dumps(w)))
    print("e2-sub-setup-decode self-test: " + ("ok" if not bad else "FAIL\n" + "\n".join(bad)))
    return 1 if bad else 0


def main():
    args = sys.argv[1:]
    if args == ["--decode-self-test"]:
        return decode_self_test()
    if args == ["decode"]:
        json.dump(decode_all(json.load(sys.stdin)), sys.stdout, sort_keys=True)
        return 0
    if len(args) == 2 and args[0] == "collect":
        json.dump(collect(args[1]), sys.stdout, sort_keys=True)
        return 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())

"""E2SM-RC v2.0 (rc@a2282ee e2sm-rc-2.0.asn + e2sm-common.asn) in APER.

RAN parameters are plain dicts, nested:
  element    {'id': 4, 'value': ('valueOctS', b'...'), 'key': False}
             key True -> ranP-Choice-ElementTrue, False -> ranP-Choice-ElementFalse
             (value may be None only for ElementFalse)
  structure  {'id': 1, 'structure': [param, ...]}      ([] = no sequence-of-ranParameters)
  list       {'id': 5, 'list': [[param, ...], ...]}   (one inner list per RANParameter-STRUCTURE)
RANParameter-Value alternatives: valueBoolean, valueInt, valueReal, valueBitS
((int, nbits)), valueOctS (bytes), valuePrintableString (str).

Wire note: RANParameter-ID is INTEGER (1..2^32, ...). This codec encodes it per
X.691 (extension bit, 2-bit length, value - 1). The asn1c code generated from
the same file treats it as unconstrained (no extension bit, length octet, two's
complement value), so the two are not wire-compatible for any PDU that carries a
RANParameter-ID; see selftest.py and asn/SOURCES.txt.
"""
from e2indep_gen import E2SM_RC_v0200 as _M

from .codec import CodecError, bitstr, decode, encode, plmn

_I = _M.E2SM_RC_IEs
HEADER, MESSAGE, OUTCOME = _I.E2SM_RC_ControlHeader, _I.E2SM_RC_ControlMessage, _I.E2SM_RC_ControlOutcome
RAN_FUNCTION_DEFINITION = _I.E2SM_RC_RANFunctionDefinition
OID = "1.3.6.1.4.1.53148.1.1.2.3"  # the E2SM-RC-IEs module OID of e2sm-rc-2.0.asn


def ue_id_en_gnb(m_enb_ue_x2ap_id, plmn_id, macro_enb_id, m_enb_ue_x2ap_id_ext=None):
    """UEID en-gNB-UEID: MeNB UE X2AP ID (0..4095) and the MeNB GlobalENB-ID (20-bit macro)."""
    val = {"m-eNB-UE-X2AP-ID": m_enb_ue_x2ap_id,
           "globalENB-ID": {"pLMNIdentity": plmn(plmn_id), "eNB-ID": ("macro-eNB-ID", bitstr(macro_enb_id, 20))}}
    if m_enb_ue_x2ap_id_ext is not None:
        val["m-eNB-UE-X2AP-ID-Extension"] = m_enb_ue_x2ap_id_ext
    return ("en-gNB-UEID", val)


def ue_id_gnb(amf_ue_ngap_id, plmn_id, amf_region_id, amf_set_id, amf_pointer, cu_f1ap_ids=(), cu_cp_e1ap_ids=()):
    """UEID gNB-UEID: AMF UE NGAP ID, GUAMI (8/10/6-bit AMF region/set/pointer), optional ID lists."""
    val = {"amf-UE-NGAP-ID": amf_ue_ngap_id,
           "guami": {"pLMNIdentity": plmn(plmn_id), "aMFRegionID": bitstr(amf_region_id, 8),
                     "aMFSetID": bitstr(amf_set_id, 10), "aMFPointer": bitstr(amf_pointer, 6)}}
    if cu_f1ap_ids:
        val["gNB-CU-UE-F1AP-ID-List"] = [{"gNB-CU-UE-F1AP-ID": i} for i in cu_f1ap_ids]
    if cu_cp_e1ap_ids:
        val["gNB-CU-CP-UE-E1AP-ID-List"] = [{"gNB-CU-CP-UE-E1AP-ID": i} for i in cu_cp_e1ap_ids]
    return ("gNB-UEID", val)


def control_header(ue_id, style_type, action_id, decision=None):
    """E2SM-RC ControlHeader Format 1; decision None (omitted), 'accept' or 'reject'."""
    f1 = {"ueID": ue_id, "ric-Style-Type": style_type, "ric-ControlAction-ID": action_id}
    if decision is not None:
        f1["ric-ControlDecision"] = decision
    return encode(HEADER, {"ric-controlHeader-formats": ("controlHeader-Format1", f1)})


def decode_control_header(buf):
    """{'format', 'ue_id', 'style_type', 'action_id', 'decision', 'raw'} (fields None unless Format 1)."""
    fmt, val = decode(HEADER, buf)["ric-controlHeader-formats"]
    f1 = val if fmt == "controlHeader-Format1" else {}
    return {"format": fmt, "ue_id": f1.get("ueID"), "style_type": f1.get("ric-Style-Type"),
            "action_id": f1.get("ric-ControlAction-ID"), "decision": f1.get("ric-ControlDecision"), "raw": val}


def _value_type(p):
    if "structure" in p:
        return ("ranP-Choice-Structure", {"ranParameter-Structure": _structure(p["structure"])})
    if "list" in p:
        if not p["list"]:
            raise CodecError(f"RAN parameter {p.get('id')}: a list needs at least one structure")
        return ("ranP-Choice-List", {"ranParameter-List": {"list-of-ranParameter": [_structure(s) for s in p["list"]]}})
    if "value" not in p:
        raise CodecError(f"RAN parameter {p.get('id')}: needs 'structure', 'list' or 'value'")
    if p.get("key"):
        if p["value"] is None:
            raise CodecError(f"RAN parameter {p.get('id')}: a key element needs a value")
        return ("ranP-Choice-ElementTrue", {"ranParameter-value": p["value"]})
    return ("ranP-Choice-ElementFalse", {} if p["value"] is None else {"ranParameter-value": p["value"]})


def _structure(params):
    return {"sequence-of-ranParameters": [_item(p) for p in params]} if params else {}


def _item(p):
    return {"ranParameter-ID": p["id"], "ranParameter-valueType": _value_type(p)}


def _param(item):
    """Inverse of _item: a decoded RANParameter item -> parameter dict."""
    alt, v = item["ranParameter-valueType"]
    pid = item["ranParameter-ID"]
    if alt == "ranP-Choice-Structure":
        return {"id": pid, "structure": _params(v["ranParameter-Structure"])}
    if alt == "ranP-Choice-List":
        return {"id": pid, "list": [_params(s) for s in v["ranParameter-List"]["list-of-ranParameter"]]}
    return {"id": pid, "value": v.get("ranParameter-value"), "key": alt == "ranP-Choice-ElementTrue"}


def _params(structure):
    return [_param(i) for i in structure.get("sequence-of-ranParameters", [])]


def control_message(params):
    """E2SM-RC ControlMessage Format 1 from a list of RAN parameter dicts."""
    f1 = {"ranP-List": [_item(p) for p in params]}
    return encode(MESSAGE, {"ric-controlMessage-formats": ("controlMessage-Format1", f1)})


def decode_control_message(buf):
    """{'format', 'params' (Format 1 only, else None), 'raw'}."""
    fmt, val = decode(MESSAGE, buf)["ric-controlMessage-formats"]
    params = [_param(i) for i in val["ranP-List"]] if fmt == "controlMessage-Format1" else None
    return {"format": fmt, "params": params, "raw": val}


def control_outcome(items=()):
    """E2SM-RC ControlOutcome Format 1 from [(RAN parameter id, RANParameter-Value), ...] (may be empty)."""
    f1 = {"ranP-List": [{"ranParameter-ID": i, "ranParameter-value": v} for i, v in items]}
    return encode(OUTCOME, {"ric-controlOutcome-formats": ("controlOutcome-Format1", f1)})


def decode_control_outcome(buf):
    """{'format', 'items' (Format 1 only: [(id, value)]), 'raw'}."""
    fmt, val = decode(OUTCOME, buf)["ric-controlOutcome-formats"]
    its = ([(i["ranParameter-ID"], i["ranParameter-value"]) for i in val["ranP-List"]]
           if fmt == "controlOutcome-Format1" else None)
    return {"format": fmt, "items": its, "raw": val}


def ran_function_definition(short_name, description, control_styles, oid=OID, instance=None):
    """E2SM-RC RANFunctionDefinition with only a Control part.

    control_styles: [{'style_type', 'style_name', 'header_format', 'message_format',
    'outcome_format', 'actions': [{'id', 'name', 'params': [(id, name), ...],
    'ue_group': False}]}]."""
    if not control_styles:
        raise CodecError("need at least one control style")
    name = {"ranFunction-ShortName": short_name, "ranFunction-E2SM-OID": oid, "ranFunction-Description": description}
    if instance is not None:
        name["ranFunction-Instance"] = instance
    styles = []
    for s in control_styles:
        item = {"ric-ControlStyle-Type": s["style_type"], "ric-ControlStyle-Name": s["style_name"],
                "ric-ControlHeaderFormat-Type": s["header_format"], "ric-ControlMessageFormat-Type": s["message_format"],
                "ric-ControlOutcomeFormat-Type": s["outcome_format"]}
        actions = []
        for a in s.get("actions", []):
            act = {"ric-ControlAction-ID": a["id"], "ric-ControlAction-Name": a["name"],
                   "ueGroup-ControlAction-Supported": "true" if a.get("ue_group") else "false"}
            if a.get("params"):
                act["ran-ControlActionParameters-List"] = [{"ranParameter-ID": i, "ranParameter-name": n}
                                                           for i, n in a["params"]]
            actions.append(act)
        if actions:
            item["ric-ControlAction-List"] = actions
        styles.append(item)
    return encode(RAN_FUNCTION_DEFINITION, {"ranFunction-Name": name,
                                            "ranFunctionDefinition-Control": {"ric-ControlStyle-List": styles}})


def decode_ran_function_definition(buf):
    """Decoded E2SM-RC RANFunctionDefinition (raw pycrate value)."""
    return decode(RAN_FUNCTION_DEFINITION, buf)

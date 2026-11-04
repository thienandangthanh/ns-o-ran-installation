"""E2AP v03.01 (O-RAN.WG3.E2AP) PDUs in APER.

Builders return encoded bytes; decode_e2ap() returns
{kind, procedure_code, criticality, message, ies: {IE id name: value}, raw}.
IE ids, criticalities and procedure codes come from the compiled ASN.1.

Value conventions: PLMN = 3 TBCD octets (bytes.fromhex('00F110') = MCC 001
MNC 01); request_id = (ricRequestorID, ricInstanceID); cause = CHOICE tuple,
e.g. ('ricRequest', 'action-not-supported'); component_id = E2nodeComponentID
CHOICE tuple (see x2_component_id()).
"""
from typing import NamedTuple

from e2indep_gen import E2AP_v0301 as _M

from .ap_protocol import ApProtocol, items
from .codec import CodecError, bitstr, plmn

E2AP = ApProtocol(_M.E2AP_PDU_Descriptions.E2AP_PDU, _M.E2AP_PDU_Descriptions.E2AP_ELEMENTARY_PROCEDURES,
                  _M.E2AP_PDU_Contents, _M.E2AP_Constants, ("E2AP-CommonDataTypes", "ProtocolIE-ID"))
build = E2AP.build


class RanFunction(NamedTuple):
    id: int            # RANfunctionID 0..4095
    revision: int      # RANfunctionRevision 0..4095
    oid: str           # RANfunctionOID, e.g. '1.3.6.1.4.1.53148.1.1.2.3' (E2SM-RC)
    definition: bytes  # the E2SM RAN function definition octets


class Component(NamedTuple):
    interface_type: str    # E2nodeComponentInterfaceType: 'ng', 'xn', 'e1', 'f1', 'w1', 's1', 'x2'
    component_id: tuple    # E2nodeComponentID CHOICE tuple
    request_part: bytes    # e2nodeComponentRequestPart (e.g. an X2 Setup Request)
    response_part: bytes   # e2nodeComponentResponsePart


def global_enb_id(plmn_id, macro_enb_id):
    """GlobalENB-ID with a 20-bit macro eNB ID."""
    return {"pLMN-Identity": plmn(plmn_id), "eNB-ID": ("macro-eNB-ID", bitstr(macro_enb_id, 20))}


def global_en_gnb_id(plmn_id, gnb_id, gnb_id_bits=32):
    """GlobalenGNB-ID; gNB ID BIT STRING of 22..32 bits (default 32)."""
    if not 22 <= gnb_id_bits <= 32:
        raise CodecError(f"gNB ID length {gnb_id_bits} not in 22..32")
    return {"pLMN-Identity": plmn(plmn_id), "gNB-ID": ("gNB-ID", bitstr(gnb_id, gnb_id_bits))}


def e2node_enb(plmn_id, macro_enb_id):
    """GlobalE2node-ID of an eNB."""
    return ("eNB", {"global-eNB-ID": global_enb_id(plmn_id, macro_enb_id)})


def e2node_en_gnb(plmn_id, gnb_id, gnb_id_bits=32):
    """GlobalE2node-ID of an en-gNB."""
    return ("en-gNB", {"global-en-gNB-ID": global_en_gnb_id(plmn_id, gnb_id, gnb_id_bits)})


def x2_component_id(global_enb=None, global_en_gnb=None):
    """E2nodeComponentID of an X2 interface (peer GlobalENB-ID and/or GlobalenGNB-ID dicts)."""
    val = {}
    if global_enb is not None:
        val["global-eNB-ID"] = global_enb
    if global_en_gnb is not None:
        val["global-en-gNB-ID"] = global_en_gnb
    return ("e2nodeComponentInterfaceTypeX2", val)


def e2_setup_request(transaction_id, e2node, ran_functions, components):
    """E2setupRequest: e2node from e2node_enb()/e2node_en_gnb(), lists of RanFunction and Component."""
    if not ran_functions or not components:
        raise CodecError("E2setupRequest needs at least one RAN function and one component")
    funcs = [E2AP.single("RANfunction-ItemIEs", "id-RANfunction-Item",
                         {"ranFunctionID": f.id, "ranFunctionDefinition": f.definition,
                          "ranFunctionRevision": f.revision, "ranFunctionOID": f.oid}) for f in ran_functions]
    comps = [E2AP.single("E2nodeComponentConfigAddition-ItemIEs", "id-E2nodeComponentConfigAddition-Item",
                         {"e2nodeComponentInterfaceType": c.interface_type, "e2nodeComponentID": c.component_id,
                          "e2nodeComponentConfiguration": {"e2nodeComponentRequestPart": c.request_part,
                                                           "e2nodeComponentResponsePart": c.response_part}})
             for c in components]
    return build("E2setupRequest", [("id-TransactionID", transaction_id), ("id-GlobalE2node-ID", e2node),
                                    ("id-RANfunctionsAdded", funcs), ("id-E2nodeComponentConfigAddition", comps)])


def _request_id(request_id):
    requestor, instance = request_id
    return {"ricRequestorID": requestor, "ricInstanceID": instance}


def ric_subscription_response(request_id, ran_function_id, admitted, not_admitted=()):
    """RICsubscriptionResponse: admitted = [action id, ...] (non-empty);
    not_admitted = [(action id, cause), ...] (IE omitted when empty)."""
    if not admitted:
        raise CodecError("RICaction-Admitted-List needs at least one action")
    ies = [("id-RICrequestID", _request_id(request_id)), ("id-RANfunctionID", ran_function_id),
           ("id-RICactions-Admitted", [E2AP.single("RICaction-Admitted-ItemIEs", "id-RICaction-Admitted-Item",
                                                   {"ricActionID": a}) for a in admitted])]
    if not_admitted:
        ies.append(("id-RICactions-NotAdmitted",
                    [E2AP.single("RICaction-NotAdmitted-ItemIEs", "id-RICaction-NotAdmitted-Item",
                                 {"ricActionID": a, "cause": c}) for a, c in not_admitted]))
    return build("RICsubscriptionResponse", ies)


def ric_subscription_failure(request_id, ran_function_id, cause):
    """RICsubscriptionFailure with a Cause."""
    return build("RICsubscriptionFailure", [("id-RICrequestID", _request_id(request_id)),
                                            ("id-RANfunctionID", ran_function_id), ("id-Cause", cause)])


def _control_ies(request_id, ran_function_id, call_process_id):
    ies = [("id-RICrequestID", _request_id(request_id)), ("id-RANfunctionID", ran_function_id)]
    if call_process_id is not None:
        ies.append(("id-RICcallProcessID", call_process_id))
    return ies


def ric_control_request(request_id, ran_function_id, header, message, call_process_id=None, ack_request=None):
    """RICcontrolRequest (E2AP v03.01 §9.1.1.7, IEs in the ASN.1 order); header and message = E2SM control header
    and message octets; ack_request = RICcontrolAckRequest name ('noAck', 'ack') or None to omit the optional IE."""
    ies = _control_ies(request_id, ran_function_id, call_process_id)
    ies += [("id-RICcontrolHeader", header), ("id-RICcontrolMessage", message)]
    if ack_request is not None:
        ies.append(("id-RICcontrolAckRequest", ack_request))
    return build("RICcontrolRequest", ies)


def ric_control_ack(request_id, ran_function_id, outcome=None, call_process_id=None):
    """RICcontrolAcknowledge; outcome = E2SM control outcome octets, or None to omit the optional IE."""
    ies = _control_ies(request_id, ran_function_id, call_process_id)
    if outcome is not None:
        ies.append(("id-RICcontrolOutcome", outcome))
    return build("RICcontrolAcknowledge", ies)


def ric_control_failure(request_id, ran_function_id, cause, outcome=None, call_process_id=None):
    """RICcontrolFailure with a Cause and an optional control outcome."""
    ies = _control_ies(request_id, ran_function_id, call_process_id) + [("id-Cause", cause)]
    if outcome is not None:
        ies.append(("id-RICcontrolOutcome", outcome))
    return build("RICcontrolFailure", ies)


def decode_e2ap(buf):
    """Decode any E2AP PDU (see module docstring for the returned dict)."""
    return E2AP.decode(buf)


def procedure_name(buf):
    """Message type name of an E2AP PDU, e.g. 'RICcontrolRequest'."""
    return decode_e2ap(buf)["message"]


def decode_e2_setup_outcome(buf):
    """Summarise an E2setupResponse or E2setupFailure."""
    d = decode_e2ap(buf)
    ies = d["ies"]
    if d["message"] == "E2setupFailure":
        return {"outcome": "failure", "transaction_id": ies["id-TransactionID"], "cause": ies["id-Cause"],
                "time_to_wait": ies.get("id-TimeToWait")}
    if d["message"] != "E2setupResponse":
        raise CodecError(f"expected an E2 Setup outcome, got {d['message']}")
    ric = ies["id-GlobalRIC-ID"]
    acks = items(ies["id-E2nodeComponentConfigAdditionAck"])
    return {"outcome": "response", "transaction_id": ies["id-TransactionID"],
            "ric_plmn": ric["pLMN-Identity"], "ric_id": ric["ric-ID"][0],
            "accepted": [(i["ranFunctionID"], i["ranFunctionRevision"])
                         for i in items(ies.get("id-RANfunctionsAccepted", []))],
            "rejected": [(i["ranFunctionID"], i["cause"]) for i in items(ies.get("id-RANfunctionsRejected", []))],
            "component_acks": [{"interface_type": a["e2nodeComponentInterfaceType"],
                                "component_id": a["e2nodeComponentID"],
                                "outcome": a["e2nodeComponentConfigurationAck"]["updateOutcome"],
                                "cause": a["e2nodeComponentConfigurationAck"].get("failureCause")} for a in acks]}

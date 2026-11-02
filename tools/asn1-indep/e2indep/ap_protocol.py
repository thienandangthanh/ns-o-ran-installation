"""Generic build/decode for 3GPP-style application protocols (E2AP, X2AP).

Both protocols wrap every message in an <X>-PDU CHOICE {initiatingMessage,
successfulOutcome, unsuccessfulOutcome} of {procedureCode, criticality, value}
and carry IEs as ProtocolIE-Field {id, criticality, value}. Procedure codes,
criticalities, IE ids and IE types are all read from the compiled ASN.1 (the
elementary-procedure set and the per-message IE sets), never hard-coded.
"""
from .codec import CodecError, decode, encode

_KINDS = {"InitiatingMessage": "initiatingMessage", "SuccessfulOutcome": "successfulOutcome",
          "UnsuccessfulOutcome": "unsuccessfulOutcome"}


def _setval(obj):
    v = obj._val
    return list(v.root) + list(v.ext or [])


def _open_name(t):
    """Name pycrate's OPEN type expects for a value of type t (see OPEN._get_const_tr)."""
    return t._typeref.called[1] if t._typeref is not None else t.TYPE


class ApProtocol:
    """pdu: the <X>-PDU type; procedures: the <X>-ELEMENTARY-PROCEDURES set;
    contents: the compiled <X>-PDU-Contents module (holds the IE sets);
    constants: the compiled <X>-Constants module; ie_id_type: the
    (module, type) reference of ProtocolIE-ID constants."""

    def __init__(self, pdu, procedures, contents, constants, ie_id_type):
        self.pdu, self.contents = pdu, contents
        self.procs = {}  # message type name -> (pdu alternative, procedure code, criticality)
        for ep in _setval(procedures):
            for key, kind in _KINDS.items():
                if key in ep:
                    self.procs[_open_name(ep[key])] = (kind, ep["procedureCode"], ep["criticality"])
        self.ie_ids, self.ie_names = {}, {}
        for name in constants._obj_:
            const = getattr(constants, name.replace("-", "_"))
            if const._typeref is not None and const._typeref.called == ie_id_type:
                self.ie_ids[name] = const._val
                self.ie_names.setdefault(const._val, name)

    def ie_set(self, set_name):
        """{ie id: (criticality, type name)} of a compiled IE set, e.g. 'E2setupRequestIEs'."""
        obj = getattr(self.contents, set_name.replace("-", "_"), None)
        if obj is None:
            raise CodecError(f"no IE set {set_name}")
        return {e["id"]: (e["criticality"], _open_name(e["Value"])) for e in _setval(obj)}

    def fields(self, set_name, ies):
        """ProtocolIE-Container value from [(IE id name, value), ...] checked against set_name."""
        allowed = self.ie_set(set_name)
        out = []
        for id_name, value in ies:
            ie_id = self.ie_ids.get(id_name)
            if ie_id not in allowed:
                raise CodecError(f"{id_name} is not an IE of {set_name}")
            crit, tname = allowed[ie_id]
            out.append({"id": ie_id, "criticality": crit, "value": (tname, value)})
        return out

    def single(self, set_name, id_name, value):
        """ProtocolIE-SingleContainer value (one list element of an *-ItemIEs list)."""
        return self.fields(set_name, [(id_name, value)])[0]

    def _message_ie_set(self, message):
        for cand in (message + "-IEs", message + "IEs"):
            if hasattr(self.contents, cand.replace("-", "_")):
                return cand
        raise CodecError(f"no IE set for {message}")

    def build(self, message, ies):
        """Encode a PDU: message type name (e.g. 'RICcontrolAcknowledge') and
        [(IE id name, value), ...] in wire order."""
        if message not in self.procs:
            raise CodecError(f"unknown message {message}")
        kind, code, crit = self.procs[message]
        body = {"protocolIEs": self.fields(self._message_ie_set(message), ies)}
        return encode(self.pdu, (kind, {"procedureCode": code, "criticality": crit, "value": (message, body)}))

    def named(self, container):
        """{IE id name: value} of a decoded ProtocolIE-Container (unknown ids keep the number)."""
        return {self.ie_names.get(f["id"], f["id"]): f["value"][1] for f in container}

    def decode(self, buf):
        """Decode a PDU into {kind, procedure_code, criticality, message, ies, raw}."""
        kind, msg = decode(self.pdu, buf)
        mtype, body = msg["value"]
        return {"kind": kind, "procedure_code": msg["procedureCode"], "criticality": msg["criticality"],
                "message": mtype, "ies": self.named(body["protocolIEs"]), "raw": (kind, msg)}


def items(single_container_list):
    """Values of a decoded list of ProtocolIE-SingleContainer (e.g. RANfunctions-List)."""
    return [f["value"][1] for f in single_container_list]

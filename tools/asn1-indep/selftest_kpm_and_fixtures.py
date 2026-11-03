"""selftest.py helpers: E2SM-KPM decode checks and the cross-checks against
committed asn1c-encoded captures (tools/rmr-peer/fixtures, tools/rc-decode/fixtures).

check(name, cond, detail) records one result; see selftest.py.
"""
import os

from e2indep import e2ap, e2sm_rc as rc
from e2indep.codec import CodecError, decode, encode
from e2indep_gen import E2SM_RC_v0200

# The rc-decode fixture message as asn1c (rc@a2282ee) encoded it, and the same value
# (rc-decode's XER: 1 > 2 > 3 > 4 = valueOctS 0000F1100000000003) encoded per X.691 here.
# They differ only in every RANParameter-ID: asn1c '00 01 <id>' (SEQUENCE ext bit, then
# unconstrained INTEGER: length octet + value) vs X.691 '00 <id-1>' (SEQUENCE ext bit,
# constraint ext bit, 2-bit length, then id - lb).
ASN1C_MSG = "0000010001014400000001024400000001034400000001042a00090000f1100000000003"
X691_MSG = "00000100004400000001440000000244000000032a00090000f1100000000003"
FIXTURE_NR_CGI = bytes.fromhex("0000f1100000000003")
# rc with the Testbed patch set (RANParameter-ID bounded 1..4294967295, ...; RAN parameter 4 = APER NR-CGI) encoding
# TS key 0000000310 at PLMN 00F110, captured from its libe2smwrapper (e2sm_encode_nrcgi then
# e2sm_encode_ric_control_message, the calls its gRPC path makes).
ASN1C_P14_MSG_GNB3 = "00000100004400000001440000000244000000032a00090000f1100000000310"


def kpm_checks(check, kpm):
    hdr = {"indicationHeader-formats": ("indicationHeader-Format1", {
        "colletStartTime": bytes.fromhex("0000019a2b3c4d5e"), "senderName": "probe", "vendorName": "e2indep"})}
    buf = encode(kpm.HEADER, hdr)
    h = kpm.decode_indication_header(buf)
    check("KPM IndicationHeader decode", h["collect_start_time"] == bytes.fromhex("0000019a2b3c4d5e")
          and h["sender_name"] == "probe" and encode(kpm.HEADER, {"indicationHeader-formats": (h["format"], h["raw"])}) == buf,
          buf.hex())
    f1 = {"measData": [{"measRecord": [("integer", 7), ("noValue", 0)]}, {"measRecord": [("integer", 4294967295)]}],
          "measInfoList": [{"measType": ("measName", "DRB.UEThpDl"), "labelInfoList": [{"measLabel": {"noLabel": "true"}}]},
                           {"measType": ("measID", 5), "labelInfoList": [{"measLabel": {"noLabel": "true"}}]}],
          "granulPeriod": 100}
    buf = encode(kpm.MESSAGE, {"indicationMessage-formats": ("indicationMessage-Format1", f1)})
    m = kpm.decode_indication_message(buf)
    check("KPM IndicationMessage Format1 decode", m["records"] == [[("integer", 7), ("noValue", 0)], [("integer", 4294967295)]]
          and m["meas_names"] == ["DRB.UEThpDl", "id:5"] and m["granularity_period"] == 100, buf.hex())
    ue = rc.ue_id_gnb(9, bytes.fromhex("00F110"), 1, 0, 0)
    buf = encode(kpm.MESSAGE, {"indicationMessage-formats": ("indicationMessage-Format3", {
        "ueMeasReportList": [{"ueID": ue, "measReport": f1}]})})
    m = kpm.decode_indication_message(buf)
    rep = m["ue_reports"][0] if m["ue_reports"] else {}
    check("KPM IndicationMessage Format3 UE IDs", rep.get("ue_id") == ue and rep.get("meas_names") == ["DRB.UEThpDl", "id:5"],
          buf.hex())


def _rmr_peer_checks(check, root):
    bufs = {}
    for name in ("ric-control-ack.hex", "ric-control-failure.hex"):
        with open(os.path.join(root, "rmr-peer", name)) as f:
            buf = bufs[name] = bytes.fromhex(f.read().strip())
        d = e2ap.decode_e2ap(buf)
        check(f"asn1c capture {name}: decode + re-encode byte-equal", encode(e2ap.E2AP.pdu, d["raw"]) == buf,
              f"{d['message']} {d['ies']}")
    ack = e2ap.decode_e2ap(bufs["ric-control-ack.hex"])["ies"]
    rid = (ack["id-RICrequestID"]["ricRequestorID"], ack["id-RICrequestID"]["ricInstanceID"])
    o = rc.decode_control_outcome(ack["id-RICcontrolOutcome"])
    check("asn1c ack outcome is RC ControlOutcome Format1, empty", o["format"] == "controlOutcome-Format1" and o["items"] == [])
    check("independent RICcontrolAcknowledge == asn1c capture",
          e2ap.ric_control_ack(rid, ack["id-RANfunctionID"], rc.control_outcome()) == bufs["ric-control-ack.hex"])
    fail = e2ap.decode_e2ap(bufs["ric-control-failure.hex"])["ies"]
    rid = (fail["id-RICrequestID"]["ricRequestorID"], fail["id-RICrequestID"]["ricInstanceID"])
    check("independent RICcontrolFailure == asn1c capture",
          e2ap.ric_control_failure(rid, fail["id-RANfunctionID"], fail["id-Cause"]) == bufs["ric-control-failure.hex"])


def _rc_decode_checks(check, root, handover_params):
    with open(os.path.join(root, "rc-decode", "rc-control-requests.hex")) as f:
        rows = [line.split() for line in f if line.strip()]
    bad = []
    for frame, hdr, _msg in rows:
        h = bytes.fromhex(hdr)
        d = rc.decode_control_header(h)
        if not (rc.control_header(d["ue_id"], d["style_type"], d["action_id"], d["decision"]) == h
                and d["style_type"] == 3 and d["action_id"] == 1 and d["ue_id"][0] == "gNB-UEID"):
            bad.append(frame)
    check(f"asn1c RC headers ({len(rows)}): decode + re-encode byte-equal, style 3, action 1, gNB-UEID", not bad, repr(bad))
    msgs = {m for _f, _h, m in rows}
    undecodable = 0
    for m in msgs:
        try:
            rc.decode_control_message(bytes.fromhex(m))
        except CodecError:
            undecodable += 1
    ours = rc.control_message(handover_params(FIXTURE_NR_CGI)).hex()
    pinned = msgs == {ASN1C_MSG} and undecodable == 1 and ours == X691_MSG
    check("FINDING RANParameter-ID: asn1c RC messages are not X.691 (pinned)", pinned,
          f"{len(msgs)} distinct message(s), {undecodable} undecodable here; asn1c {sorted(msgs)[0]} vs X.691 {ours}")
    try:
        nr = repr(decode(E2SM_RC_v0200.E2SM_COMMON_IEs.NR_CGI, FIXTURE_NR_CGI))
    except CodecError as exc:
        nr = f"undecodable ({exc})"
    print(f"INFO fixture valueOctS {FIXTURE_NR_CGI.hex()} read as an APER NR-CGI: {nr}")


def _rc_nrcgi_checks(check, root, handover_params):
    """rc-control-nrcgi.hex (make-nrcgi-fixture.py): X.691 header and message of a Style 3/1 control per line id
    '...-gnb<n>'; each re-encodes byte-equal, the target is the NR-CGI of gNB n, and rc's P14-fixed asn1c output for
    gNB 3 equals the fixture's X.691 message."""
    with open(os.path.join(root, "rc-decode", "rc-control-nrcgi.hex")) as f:
        rows = [line.split() for line in f if line.strip()]
    bad = []
    msg_of = {}
    for name, hdr, msg in rows:
        gnb = int(name.rsplit("gnb", 1)[1])
        cgi = encode(E2SM_RC_v0200.E2SM_COMMON_IEs.NR_CGI, {"pLMNIdentity": bytes.fromhex("00f110"),
                                                            "nRCellIdentity": ((gnb << 4) | 1, 36)})
        d = rc.decode_control_header(bytes.fromhex(hdr))
        ok = (rc.control_header(d["ue_id"], d["style_type"], d["action_id"], d["decision"]).hex() == hdr
              and d["style_type"] == 3 and d["action_id"] == 1
              and rc.control_message(handover_params(cgi)).hex() == msg)
        msg_of[gnb] = msg
        if not ok:
            bad.append(name)
    check(f"X.691 RC fixture ({len(rows)}): header round-trip style 3/1, message = 1>2>3>4 with the gNB's NR-CGI",
          rows and not bad, repr(bad))
    check("asn1c (rc, P14-fixed) RC message == X.691 for the gNB 3 target", msg_of.get(3) == ASN1C_P14_MSG_GNB3,
          f"fixture {msg_of.get(3)} vs asn1c {ASN1C_P14_MSG_GNB3}")


def fixture_checks(check, root, handover_params):
    _rmr_peer_checks(check, root)
    _rc_decode_checks(check, root, handover_params)
    _rc_nrcgi_checks(check, root, handover_params)

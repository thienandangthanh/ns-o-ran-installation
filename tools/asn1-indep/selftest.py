#!/usr/bin/env python3
"""selftest.py [fixtures-dir]: round-trip and cross-check the e2indep codec.

Round trip = encode -> decode -> re-encode from the decoded value, byte-equal,
plus field checks on the decoded value. With fixtures-dir (holding rc-decode/
and rmr-peer/ from tools/), real asn1c-encoded captures are decoded too:
  - rmr-peer: RICcontrolAcknowledge / RICcontrolFailure PDUs of the R1 capture;
  - rc-decode: RICcontrolHeader / RICcontrolMessage octets of the probe pcap.
The rc-decode control messages do NOT decode here; that is a known finding
(asn1c encodes RANParameter-ID unconstrained), checked as such: the test pins
the exact difference so that any change in either codec is noticed.
Prints one line per check and exits 1 if any check fails.
"""
import sys

from e2indep import e2ap, e2sm_rc as rc, kpm, x2ap
from e2indep.codec import CodecError, encode
from selftest_kpm_and_fixtures import fixture_checks, kpm_checks

PLMN = bytes.fromhex("00F110")
RESULTS = []


def check(name, cond, detail=""):
    RESULTS.append(bool(cond))
    print(f"{'PASS' if cond else 'FAIL'} {name}{': ' + detail if detail else ''}")


def roundtrip(name, buf, decoder, reencode):
    """decoder(buf) -> value; reencode(value) -> bytes; must equal buf."""
    val = decoder(buf)
    again = reencode(val)
    check(f"{name} round trip", again == buf, buf.hex() if again == buf else f"{buf.hex()} != {again.hex()}")
    return val


def e2ap_rt(name, buf):
    return roundtrip(name, buf, e2ap.decode_e2ap, lambda d: encode(e2ap.E2AP.pdu, d["raw"]))


def e2_setup_checks():
    rf = e2ap.RanFunction(3, 1, rc.OID, rc.ran_function_definition("ORAN-E2SM-RC", "RAN Control", [
        {"style_type": 3, "style_name": "Connected Mode Mobility Control", "header_format": 1,
         "message_format": 1, "outcome_format": 1,
         "actions": [{"id": 1, "name": "Handover Control", "params": [(1, "Target Primary Cell ID"), (4, "NR CGI")]}]}]))
    comp = e2ap.Component("x2", e2ap.x2_component_id(global_en_gnb=e2ap.global_en_gnb_id(PLMN, 2)), b"\x01", b"\x02")
    d = e2ap_rt("E2setupRequest eNB", e2ap.e2_setup_request(1, e2ap.e2node_enb(PLMN, 0x00001), [rf], [comp]))
    enb = d["ies"]["id-GlobalE2node-ID"]
    check("E2setupRequest eNB macro ID", enb == ("eNB", {"global-eNB-ID": {
        "pLMN-Identity": PLMN, "eNB-ID": ("macro-eNB-ID", (1, 20))}}), repr(enb))
    d = e2ap_rt("E2setupRequest en-gNB", e2ap.e2_setup_request(7, e2ap.e2node_en_gnb(PLMN, 0x7F000001), [rf], [comp]))
    gid = d["ies"]["id-GlobalE2node-ID"][1]["global-en-gNB-ID"]["gNB-ID"]
    check("E2setupRequest en-gNB gNB ID is 32-bit 0x7F000001", gid == ("gNB-ID", (0x7F000001, 32)), repr(gid))
    funcs = e2ap.items(d["ies"]["id-RANfunctionsAdded"])
    check("E2setupRequest RAN function item", funcs[0]["ranFunctionID"] == 3 and funcs[0]["ranFunctionOID"] == rc.OID)
    defn = rc.decode_ran_function_definition(funcs[0]["ranFunctionDefinition"])
    check("RC RAN function definition round trip", encode(rc.RAN_FUNCTION_DEFINITION, defn) == rf.definition)
    resp = e2ap.build("E2setupResponse", [
        ("id-TransactionID", 7), ("id-GlobalRIC-ID", {"pLMN-Identity": PLMN, "ric-ID": (0x000F1, 20)}),
        ("id-RANfunctionsAccepted", [e2ap.E2AP.single("RANfunctionID-ItemIEs", "id-RANfunctionID-Item",
                                                      {"ranFunctionID": 3, "ranFunctionRevision": 1})]),
        ("id-E2nodeComponentConfigAdditionAck", [e2ap.E2AP.single(
            "E2nodeComponentConfigAdditionAck-ItemIEs", "id-E2nodeComponentConfigAdditionAck-Item",
            {"e2nodeComponentInterfaceType": "x2", "e2nodeComponentID": comp.component_id,
             "e2nodeComponentConfigurationAck": {"updateOutcome": "success"}})])])
    o = e2ap.decode_e2_setup_outcome(resp)
    check("E2setupResponse decode", o["outcome"] == "response" and o["accepted"] == [(3, 1)]
          and o["ric_id"] == 0xF1 and o["component_acks"][0]["outcome"] == "success", repr(o))
    fail = e2ap.build("E2setupFailure", [("id-TransactionID", 7), ("id-Cause", ("misc", "unspecified")),
                                         ("id-TimeToWait", "v5s")])
    o = e2ap.decode_e2_setup_outcome(fail)
    check("E2setupFailure decode", o == {"outcome": "failure", "transaction_id": 7,
                                         "cause": ("misc", "unspecified"), "time_to_wait": "v5s"}, repr(o))


def ric_response_checks():
    e2ap_rt("RICsubscriptionResponse", e2ap.ric_subscription_response(
        (1024, 5), 3, [1], [(2, ("ricRequest", "action-not-supported"))]))
    e2ap_rt("RICsubscriptionFailure", e2ap.ric_subscription_failure((1024, 5), 3, ("ricRequest", "ran-function-id-invalid")))
    outcome = rc.control_outcome()
    d = rc.decode_control_outcome(outcome)
    check("RC ControlOutcome Format1 empty", d["format"] == "controlOutcome-Format1" and d["items"] == []
          and rc.control_outcome(d["items"]) == outcome, outcome.hex())
    d = e2ap_rt("RICcontrolAcknowledge with outcome", e2ap.ric_control_ack((1, 2), 3, outcome))
    check("RICcontrolAcknowledge carries the outcome", d["ies"].get("id-RICcontrolOutcome") == outcome)
    d = e2ap_rt("RICcontrolAcknowledge without outcome", e2ap.ric_control_ack((1, 2), 3))
    check("RICcontrolAcknowledge omits the outcome", "id-RICcontrolOutcome" not in d["ies"], repr(d["ies"]))
    e2ap_rt("RICcontrolFailure", e2ap.ric_control_failure((1, 2), 3, ("ricRequest", "control-failed-to-execute")))
    check("procedure_name", e2ap.procedure_name(e2ap.ric_control_ack((1, 2), 3)) == "RICcontrolAcknowledge")


def handover_params(nr_cgi):
    """Target Primary Cell ID (1) > Target Cell (2) > NR Cell (3) > NR CGI (4), as the TS xApp sends it."""
    leaf = {"id": 4, "value": ("valueOctS", nr_cgi), "key": False}
    return [{"id": 1, "structure": [{"id": 2, "structure": [{"id": 3, "structure": [leaf]}]}]}]


def rc_checks():
    ue = rc.ue_id_en_gnb(3, PLMN, 0x00001)
    d = roundtrip("RC ControlHeader en-gNB-UEID", rc.control_header(ue, 3, 1), rc.decode_control_header,
                  lambda v: rc.control_header(v["ue_id"], v["style_type"], v["action_id"], v["decision"]))
    check("RC header UE ID", d["ue_id"] == ("en-gNB-UEID", {"m-eNB-UE-X2AP-ID": 3, "globalENB-ID": {
        "pLMNIdentity": PLMN, "eNB-ID": ("macro-eNB-ID", (1, 20))}}), repr(d["ue_id"]))
    roundtrip("RC ControlHeader gNB-UEID", rc.control_header(rc.ue_id_gnb(1, PLMN, 1, 0, 0, [1], [1]), 3, 1, "accept"),
              rc.decode_control_header,
              lambda v: rc.control_header(v["ue_id"], v["style_type"], v["action_id"], v["decision"]))
    params = handover_params(PLMN + bytes.fromhex("0000000210")) + [
        {"id": 10, "list": [[{"id": 11, "value": ("valueInt", 7), "key": True}],
                            [{"id": 11, "value": ("valuePrintableString", "x"), "key": True}]]},
        {"id": 12, "value": None, "key": False}, {"id": 13, "structure": []},
        {"id": 4294967296, "value": ("valueBitS", (5, 3)), "key": False}]
    d = roundtrip("RC ControlMessage Format1", rc.control_message(params), rc.decode_control_message,
                  lambda v: rc.control_message(v["params"]))
    check("RC ControlMessage params", d["params"] == params, repr(d["params"]))


def negative_checks():
    for name, fn in [("bit string overflow", lambda: e2ap.global_enb_id(PLMN, 1 << 20)),
                     ("non-TBCD PLMN", lambda: e2ap.global_enb_id(b"\xaa\xf1\x10", 1)),
                     ("IE not in set", lambda: e2ap.build("RICcontrolAcknowledge", [("id-Cause", ("misc", "unspecified"))])),
                     ("out-of-range integer", lambda: e2ap.ric_control_ack((70000, 1), 3)),
                     ("trailing octets", lambda: e2ap.decode_e2ap(e2ap.ric_control_ack((1, 2), 3) + b"\x00")),
                     ("garbage", lambda: e2ap.decode_e2ap(b"\xff\xff"))]:
        try:
            fn()
            check(f"rejects {name}", False, "no error")
        except CodecError as exc:
            check(f"rejects {name}", True, str(exc)[:90])


def x2ap_checks():
    mtc = x2ap.measurement_timing_configuration(632628)
    m = x2ap.decode_measurement_timing_configuration(mtc)
    ft = m["criticalExtensions"][1][1]["measTiming"][0]["frequencyAndTiming"]
    check("MeasurementTimingConfiguration", ft["carrierFreq"] == 632628
          and ft["ssb-MeasurementTimingConfiguration"]["periodicityAndOffset"] == ("sf20", 0), mtc.hex())
    cell_id = x2ap.nr_cell_identity(0x00000002, 1)
    cell = x2ap.served_nr_cell(1, PLMN, cell_id, 632628, 78, mtc, configured_tac=b"\x00\x01")
    buf = x2ap.endc_x2_setup_request_en_gnb(PLMN, 0x00000002, [cell])
    d = roundtrip("X2AP ENDCX2SetupRequest en-gNB", buf, x2ap.decode_x2ap, lambda v: encode(x2ap.X2.pdu, v["raw"]))
    s = x2ap.decode_endc_x2_setup_request(buf)
    nr = s["ies"]["id-ServedNRcellsENDCX2ManagementList"][0]["servedNRCellInfo"]
    check("X2AP NR CGI = gNB 0x00000002 + cell 1 (36 bits)",
          s["node"] == "init-en-gNB" and nr["nrCellID"]["nRcellIdentifier"] == (0x21, 36), repr(nr["nrCellID"]))
    check("X2AP gNB ID 32 bits", s["ies"]["id-Globalen-gNB-ID"]["gNB-ID"] == ("gNB-ID", (2, 32)))
    check("X2AP served cell MTC octets", nr["measurementTimingConfiguration"] == mtc)
    enb = x2ap.endc_x2_setup_request_enb(PLMN, 0x00001, [x2ap.served_eutra_cell(1, PLMN, 0x0000101, b"\x00\x01", 100, 18100)])
    roundtrip("X2AP ENDCX2SetupRequest eNB", enb, x2ap.decode_x2ap, lambda v: encode(x2ap.X2.pdu, v["raw"]))
    check("X2AP eNB node type", x2ap.decode_endc_x2_setup_request(enb)["node"] == "init-eNB")
    gr = x2ap.endc_x2_setup_response_en_gnb(PLMN, 0x00000002, [cell])
    roundtrip("X2AP ENDCX2SetupResponse en-gNB", gr, x2ap.decode_x2ap, lambda v: encode(x2ap.X2.pdu, v["raw"]))
    check("X2AP en-gNB response node type", x2ap.decode_endc_x2_setup_response(gr)["node"] == "respond-en-gNB")
    er = x2ap.endc_x2_setup_response_enb(PLMN, 0x00001, [x2ap.served_eutra_cell(1, PLMN, 0x0000101, b"\x00\x01", 100, 18100)])
    roundtrip("X2AP ENDCX2SetupResponse eNB", er, x2ap.decode_x2ap, lambda v: encode(x2ap.X2.pdu, v["raw"]))
    check("X2AP eNB response node type", x2ap.decode_endc_x2_setup_response(er)["node"] == "respond-eNB")


def main():
    fixtures = sys.argv[1] if len(sys.argv) > 1 else None
    for group in (e2_setup_checks, ric_response_checks, rc_checks, negative_checks, x2ap_checks):
        group()
    kpm_checks(check, kpm)
    if fixtures:
        fixture_checks(check, fixtures, handover_params)
    else:
        print("SKIP fixture cross-checks: no fixtures dir given")
    print(f"selftest: {sum(RESULTS)}/{len(RESULTS)} checks passed")
    sys.exit(0 if all(RESULTS) else 1)


if __name__ == "__main__":
    main()

"""3GPP TS 36.423 X2AP EN-DC X2 Setup (APER) and the TS 38.331
MeasurementTimingConfiguration (UPER), from pycrate's bundled X2AP and RRCNR
modules (release and provenance in asn/SOURCES.txt).

NR cell identity: 36 bits = gNB ID (gnb_id_bits, 22..32) followed by the local
cell part; nr_cell_identity() builds it.
"""
from pycrate_asn1dir import X2AP as _X

from .ap_protocol import ApProtocol
from .codec import CodecError, bitstr, decode, encode, plmn

X2 = ApProtocol(_X.X2AP_PDU_Descriptions.X2AP_PDU, _X.X2AP_PDU_Descriptions.X2AP_ELEMENTARY_PROCEDURES,
                _X.X2AP_PDU_Contents, _X.X2AP_Constants, ("X2AP-CommonDataTypes", "ProtocolIE-ID"))


def nr_cell_identity(gnb_id, cell_local_id, gnb_id_bits=32):
    """36-bit NR cell identity: gNB ID in the leftmost gnb_id_bits, then the local cell ID."""
    if not 22 <= gnb_id_bits <= 32:
        raise CodecError(f"gNB ID length {gnb_id_bits} not in 22..32")
    bitstr(gnb_id, gnb_id_bits)
    bitstr(cell_local_id, 36 - gnb_id_bits)
    return (gnb_id << (36 - gnb_id_bits)) | cell_local_id


def served_nr_cell(pci, plmn_id, nr_cell_id, arfcn, band, measurement_timing_configuration,
                   scs="scs30", nrb="nrb106", configured_tac=None, five_gs_tac=None, broadcast_plmns=None):
    """ServedNRCell-Information of a TDD cell (nrModeInfo tdd: NR-ARFCN, one band, SCS/NRB).

    configured_tac: 2 octets; five_gs_tac: 3 octets; at least one is required here.
    measurement_timing_configuration: UPER octets, e.g. from measurement_timing_configuration()."""
    if configured_tac is None and five_gs_tac is None:
        raise CodecError("served NR cell needs configured_tac and/or five_gs_tac")
    cell = {"nrpCI": pci, "nrCellID": {"pLMN-Identity": plmn(plmn_id), "nRcellIdentifier": bitstr(nr_cell_id, 36)},
            "broadcastPLMNs": [plmn(p) for p in (broadcast_plmns or [plmn_id])],
            "nrModeInfo": ("tdd", {"nRFreqInfo": {"nRARFCN": arfcn,
                                                  "freqBandListNr": [{"freqBandIndicatorNr": band,
                                                                      "supportedSULBandList": []}]},
                                   "nR-TxBW": {"nRSCS": scs, "nRNRB": nrb}}),
            "measurementTimingConfiguration": measurement_timing_configuration}
    if five_gs_tac is not None:
        cell["fiveGS-TAC"] = five_gs_tac
    if configured_tac is not None:
        cell["configured-TAC"] = configured_tac
    return cell


def served_eutra_cell(pci, plmn_id, eutran_cell_id, tac, dl_earfcn, ul_earfcn, bandwidth="bw100"):
    """ServedCell-Information of an FDD E-UTRA cell (28-bit cell identity, 2-octet TAC)."""
    return {"pCI": pci, "cellId": {"pLMN-Identity": plmn(plmn_id), "eUTRANcellIdentifier": bitstr(eutran_cell_id, 28)},
            "tAC": tac, "broadcastPLMNs": [plmn(plmn_id)],
            "eUTRA-Mode-Info": ("fDD", {"uL-EARFCN": ul_earfcn, "dL-EARFCN": dl_earfcn,
                                        "uL-Transmission-Bandwidth": bandwidth,
                                        "dL-Transmission-Bandwidth": bandwidth})}


def endc_x2_setup_request_en_gnb(plmn_id, gnb_id, cells, gnb_id_bits=32):
    """ENDCX2SetupRequest from an en-gNB (init-en-gNB) with served NR cells (served_nr_cell())."""
    if not cells:
        raise CodecError("need at least one served NR cell")
    gid = {"pLMN-Identity": plmn(plmn_id), "gNB-ID": ("gNB-ID", bitstr(gnb_id, gnb_id_bits))}
    node = X2.fields("En-gNB-ENDCX2SetupReqIEs", [
        ("id-Globalen-gNB-ID", gid),
        ("id-ServedNRcellsENDCX2ManagementList", [{"servedNRCellInfo": c} for c in cells])])
    return X2.build("ENDCX2SetupRequest", [("id-InitiatingNodeType-EndcX2Setup", ("init-en-gNB", node))])


def endc_x2_setup_request_enb(plmn_id, macro_enb_id, cells):
    """ENDCX2SetupRequest from an eNB (init-eNB) with served E-UTRA cells (served_eutra_cell())."""
    if not cells:
        raise CodecError("need at least one served E-UTRA cell")
    gid = {"pLMN-Identity": plmn(plmn_id), "eNB-ID": ("macro-eNB-ID", bitstr(macro_enb_id, 20))}
    node = X2.fields("ENB-ENDCX2SetupReqIEs", [
        ("id-GlobalENB-ID", gid),
        ("id-ServedEUTRAcellsENDCX2ManagementList", [{"servedEUTRACellInfo": c} for c in cells])])
    return X2.build("ENDCX2SetupRequest", [("id-InitiatingNodeType-EndcX2Setup", ("init-eNB", node))])


def endc_x2_setup_response_en_gnb(plmn_id, gnb_id, cells, gnb_id_bits=32):
    """ENDCX2SetupResponse from an en-gNB (respond-en-gNB) with served NR cells (served_nr_cell())."""
    if not cells:
        raise CodecError("need at least one served NR cell")
    gid = {"pLMN-Identity": plmn(plmn_id), "gNB-ID": ("gNB-ID", bitstr(gnb_id, gnb_id_bits))}
    node = X2.fields("En-gNB-ENDCX2SetupReqAckIEs", [
        ("id-Globalen-gNB-ID", gid),
        ("id-ServedNRcellsENDCX2ManagementList", [{"servedNRCellInfo": c} for c in cells])])
    return X2.build("ENDCX2SetupResponse", [("id-RespondingNodeType-EndcX2Setup", ("respond-en-gNB", node))])


def endc_x2_setup_response_enb(plmn_id, macro_enb_id, cells):
    """ENDCX2SetupResponse from an eNB (respond-eNB) with served E-UTRA cells (served_eutra_cell())."""
    if not cells:
        raise CodecError("need at least one served E-UTRA cell")
    gid = {"pLMN-Identity": plmn(plmn_id), "eNB-ID": ("macro-eNB-ID", bitstr(macro_enb_id, 20))}
    node = X2.fields("ENB-ENDCX2SetupReqAckIEs", [
        ("id-GlobalENB-ID", gid),
        ("id-ServedEUTRAcellsENDCX2ManagementList", [{"servedEUTRACellInfo": c} for c in cells])])
    return X2.build("ENDCX2SetupResponse", [("id-RespondingNodeType-EndcX2Setup", ("respond-eNB", node))])


def decode_x2ap(buf):
    """Decode any X2AP PDU: {kind, procedure_code, criticality, message, ies, raw}."""
    return X2.decode(buf)


def decode_endc_x2_setup_request(buf):
    """{'node': 'init-en-gNB' | 'init-eNB', 'ies': {IE id name: value}} of an ENDCX2SetupRequest."""
    d = decode_x2ap(buf)
    if d["message"] != "ENDCX2SetupRequest":
        raise CodecError(f"expected ENDCX2SetupRequest, got {d['message']}")
    node, container = d["ies"]["id-InitiatingNodeType-EndcX2Setup"]
    return {"node": node, "ies": X2.named(container)}


def decode_endc_x2_setup_response(buf):
    """{'node': 'respond-en-gNB' | 'respond-eNB', 'ies': {IE id name: value}} of an ENDCX2SetupResponse."""
    d = decode_x2ap(buf)
    if d["message"] != "ENDCX2SetupResponse":
        raise CodecError(f"expected ENDCX2SetupResponse, got {d['message']}")
    node, container = d["ies"]["id-RespondingNodeType-EndcX2Setup"]
    return {"node": node, "ies": X2.named(container)}


_SSB_PERIODS = (5, 10, 20, 40, 80, 160)


def _mtc_type():
    from pycrate_asn1dir import RRCNR  # large module: imported only when needed
    return RRCNR.NR_InterNodeDefinitions.MeasurementTimingConfiguration


def measurement_timing_configuration(arfcn, scs="kHz30", period_ms=20, offset=0, duration="sf1"):
    """UPER MeasurementTimingConfiguration (TS 38.331 NR-InterNodeDefinitions) with one
    MeasTiming: SSB at NR-ARFCN arfcn, SSB subcarrier spacing scs, SMTC periodicity
    period_ms (default 20 ms) with the given offset (subframes) and duration."""
    if period_ms not in _SSB_PERIODS:
        raise CodecError(f"SSB-MTC periodicity {period_ms} ms not in {_SSB_PERIODS}")
    if not 0 <= offset < period_ms:
        raise CodecError(f"SSB-MTC offset {offset} not in 0..{period_ms - 1}")
    timing = {"frequencyAndTiming": {"carrierFreq": arfcn, "ssbSubcarrierSpacing": scs,
                                     "ssb-MeasurementTimingConfiguration": {
                                         "periodicityAndOffset": (f"sf{period_ms}", offset), "duration": duration}}}
    val = {"criticalExtensions": ("c1", ("measTimingConf", {"measTiming": [timing]}))}
    return encode(_mtc_type(), val, aligned=False)


def decode_measurement_timing_configuration(buf):
    """Decoded MeasurementTimingConfiguration (raw pycrate value)."""
    return decode(_mtc_type(), buf, aligned=False)

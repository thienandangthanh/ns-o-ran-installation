"""make-nrcgi-fixture.py: write fixtures/rc-control-nrcgi.hex, RIC CONTROL header and message octets encoded per
X.691 by the independent codec (tools/asn1-indep, pycrate), one line "<id> <header hex> <message hex>".

Run inside the asn1-indep image (it has e2indep on the path):
    podman run --rm localhost/asn1-indep:<tag> python3 - < tools/rc-decode/make-nrcgi-fixture.py \
        > tools/rc-decode/fixtures/rc-control-nrcgi.hex

Content (plan R-3): Control Header Format 1, Style 3 "Connected Mode Mobility Control" action 1 "Handover Control"
(E2SM-RC 7.6.4.1), UE ID gNB-UEID as rc sends it (AMF UE NGAP ID = IMSI, GUAMI 00F110 / 1 / 0 / 0, one F1AP and
one E1AP ID 1); Control Message Format 1 with RAN parameters 1 > 2 > 3 > 4 (8.4.4.1), parameter 4 = APER NR-CGI
(E2SM common) of PLMN 00F110 and NR Cell Identity = gNB ID (32 bits) || cell part 1.
"""
from e2indep import e2sm_rc
from e2indep.codec import encode
from e2indep_gen import E2SM_RC_v0200

PLMN = bytes.fromhex("00f110")


def nr_cgi(gnb_id):
    return encode(E2SM_RC_v0200.E2SM_COMMON_IEs.NR_CGI,
                  {"pLMNIdentity": PLMN, "nRCellIdentity": ((gnb_id << 4) | 1, 36)})


def header(imsi):
    ue = e2sm_rc.ue_id_gnb(imsi, PLMN, 1, 0, 0, cu_f1ap_ids=[1], cu_cp_e1ap_ids=[1])
    return e2sm_rc.control_header(ue, 3, 1)


def message(gnb_id):
    target = {"id": 4, "value": ("valueOctS", nr_cgi(gnb_id)), "key": False}
    return e2sm_rc.control_message([{"id": 1, "structure": [{"id": 2, "structure": [{"id": 3, "structure": [target]}]}]}])


for imsi, gnb in ((1, 3), (2, 2)):
    print("s3a1-imsi%d-gnb%d %s %s" % (imsi, gnb, header(imsi).hex(), message(gnb).hex()))

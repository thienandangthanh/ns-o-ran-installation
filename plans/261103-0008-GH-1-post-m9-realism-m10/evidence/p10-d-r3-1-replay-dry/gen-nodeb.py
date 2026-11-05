"""Synthetic e2mgr nodeb records for en-gNB IDs 2..12 and the eNB at the corrected served NR cell: each request part
is the uppercase hex text of the node's APER EN-DC X2 SETUP REQUEST (as e2mgr stores it), built with the independent
encoder. The en-gNB cell is the agent's (ns3_e2_agent e2-node-identity.hpp): PCI = gNB ID, NRARFCN 632758 (Point A),
n78, nR-TxBW scs60/nrb24, MTC SSB at NR-ARFCN 633312 (GSCN 7846), Configured TAC 0001."""
import base64, json, sys
sys.path.insert(0, "/opt/asn1-indep")
from e2indep import x2ap
PLMN = bytes.fromhex("00F110")
out = sys.argv[1]
mtc = x2ap.measurement_timing_configuration(633312)
def doc(meid, msg, key):
    hexpart = bytes(msg).hex().upper()
    return {"ranName": meid, "connectionStatus": "CONNECTED",
            key: {"nodeConfigs": [{"e2nodeComponentInterfaceType": "x2",
                                   "e2nodeComponentRequestPart": base64.b64encode(hexpart.encode()).decode()}]}}
for nid in range(2, 13):
    cell = x2ap.served_nr_cell(nid, PLMN, x2ap.nr_cell_identity(nid, 1), 632758, 78, mtc, scs="scs60", nrb="nrb24",
                               configured_tac=b"\x00\x01")
    msg = x2ap.endc_x2_setup_request_en_gnb(PLMN, nid, [cell])
    json.dump(doc("en_gnb_001_001_%08x" % nid, msg, "gnb"), open("%s/nodeb-%02d.json" % (out, nid), "w"))
cell = x2ap.served_eutra_cell(1, PLMN, (1 << 8) | 1, b"\x00\x01", 100, 18100)
json.dump(doc("enB_macro_001_001_000001", x2ap.endc_x2_setup_request_enb(PLMN, 1, [cell]), "enb"), open(out + "/nodeb-enb.json", "w"))

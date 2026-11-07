# Candidate fix (scratch tree only): a PDCP Control PDU received by an MC entity is discarded per
# 3GPP TS 38.323 clause 5.10 instead of aborting the run.
import sys
root = sys.argv[1]
UE_OLD = '''        NS_ABORT_MSG_IF(pdcpHeader.GetDcBit() != DataPduHeader::DATA_PDU,
                        "McUePdcp received a PDCP Control PDU; this model sends Data PDUs only");
'''
UE_NEW = '''        if (pdcpHeader.GetDcBit() != DataPduHeader::DATA_PDU)
        {
            // A PDCP Control PDU (D/C 0, 3GPP TS 38.323 clause 6.3.7). This entity is configured
            // with none of the Control PDUs of clause 6.2.3 (no status report on its UM DRB, no
            // ROHC, EHC or UDC, no SN gap report), so the PDU carries reserved or invalid values
            // for it and is discarded (clause 5.10): RX state unchanged, nothing delivered.
            NS_LOG_WARN("McUePdcp rnti " << m_rnti << " lcid " << +m_lcid
                                         << " discards a PDCP Control PDU of "
                                         << p->GetSize() + pdcpHeader.GetSerializedSize()
                                         << " bytes");
            return;
        }
'''
ENB_OLD = '''    NS_ABORT_MSG_IF(pdcpHeader.GetDcBit() != DataPduHeader::DATA_PDU,
                    "McEnbPdcp received a PDCP Control PDU; this model sends Data PDUs only");
'''
ENB_NEW = '''    if (pdcpHeader.GetDcBit() != DataPduHeader::DATA_PDU)
    {
        // A PDCP Control PDU (D/C 0, 3GPP TS 38.323 clause 6.3.7). This entity is configured with
        // none of the Control PDUs of clause 6.2.3 (no status report on its UM DRB, no ROHC, EHC
        // or UDC, no SN gap report), so the PDU carries reserved or invalid values for it and is
        // discarded (clause 5.10): RX state unchanged, nothing delivered.
        NS_LOG_WARN("McEnbPdcp rnti " << m_rnti << " lcid " << +m_lcid
                                      << " discards a PDCP Control PDU of "
                                      << p->GetSize() + pdcpHeader.GetSerializedSize() << " bytes");
        return;
    }
'''
for rel, old, new in (("src/lte/model/mc-ue-pdcp.cc", UE_OLD, UE_NEW), ("src/lte/model/mc-enb-pdcp.cc", ENB_OLD, ENB_NEW)):
    path = f"{root}/{rel}"
    s = open(path).read()
    assert s.count(old) == 1, rel
    open(path, "w").write(s.replace(old, new))
print("ok")

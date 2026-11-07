# Final recommended fix text (scratch tree only): discard per TS 38.323 clause 5.10 and drop the
# abort.h include that only the removed aborts used.
import sys
root = sys.argv[1]
def block(entity, ind):
    i = " " * ind
    return (f"{i}if (pdcpHeader.GetDcBit() != DataPduHeader::DATA_PDU)\n"
            f"{i}{{\n"
            f"{i}    // A PDCP Control PDU (D/C 0, 3GPP TS 38.323 clause 6.3.7). The model configures none\n"
            f"{i}    // of the functions that use one (clause 6.2.3: status report, ROHC, EHC or UDC\n"
            f"{i}    // feedback, SN gap report), so for this entity it carries reserved or invalid values\n"
            f"{i}    // and is discarded (clause 5.10): RX state unchanged, nothing delivered.\n"
            f"{i}    NS_LOG_WARN(\"{entity} rnti \" << m_rnti << \" lcid \" << +m_lcid\n"
            f"{i}                << \" discards a PDCP Control PDU of \"\n"
            f"{i}                << p->GetSize() + pdcpHeader.GetSerializedSize() << \" bytes\");\n"
            f"{i}    return;\n"
            f"{i}}}\n")
for rel, entity, ind in (("src/lte/model/mc-ue-pdcp.cc", "McUePdcp", 8), ("src/lte/model/mc-enb-pdcp.cc", "McEnbPdcp", 4)):
    path = f"{root}/{rel}"
    s = open(path).read()
    i = " " * ind
    old = (f"{i}NS_ABORT_MSG_IF(pdcpHeader.GetDcBit() != DataPduHeader::DATA_PDU,\n"
           f"{i}                \"{entity} received a PDCP Control PDU; this model sends Data PDUs only\");\n")
    assert s.count(old) == 1, rel
    s = s.replace(old, block(entity, ind))
    assert s.count('#include "ns3/abort.h"\n') == 1, rel
    s = s.replace('#include "ns3/abort.h"\n', "")
    assert "NS_ABORT" not in s, rel
    open(path, "w").write(s)
print("ok")

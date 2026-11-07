# Adds packet-uid trace probes (stderr) to a scratch ns-3 tree at 34b7f3cc, on top of probe.py.
import sys
root = sys.argv[1]
def patch(rel, anchor, insert, after=True, occurrence_after=None):
    path = f"{root}/{rel}"
    s = open(path).read()
    start = s.index(occurrence_after) if occurrence_after else 0
    i = s.index(anchor, start)
    j = i + len(anchor) if after else i
    s = s[:j] + insert + s[j:]
    if "#include <iostream>" not in s:
        s = s.replace("#include", "#include <iostream>\n#include", 1)
    open(path, "w").write(s)
# McUePdcp probe: add uid to the PROBE line
p = f"{root}/src/lte/model/mc-ue-pdcp.cc"
s = open(p).read()
s = s.replace('<< " mmw=" << m_useMmWaveConnection << std::endl;', '<< " mmw=" << m_useMmWaveConnection << " uid=" << p->GetUid() << std::endl;', 1)
open(p, "w").write(s)
# X2 MC DL send
patch("src/lte/model/epc-x2.cc", "Ptr<Packet> packet = params.ueData;\n    packet->AddHeader(gtpu);",
      '\n    std::cerr << "X2MC t=" << Simulator::Now().GetNanoSeconds() << " uid=" << packet->GetUid() << " size=" << packet->GetSize() << " src=" << params.sourceCellId << " tgt=" << params.targetCellId << " teid=" << params.gtpTeid << std::endl;',
      occurrence_after="EpcX2::DoSendMcPdcpPdu")
# eNB PDCP LTE leg TX
patch("src/lte/model/mc-enb-pdcp.cc", "m_txPdu(m_rnti, m_lcid, p->GetSize());\n    params.pdcpPdu = p;",
      '\n    std::cerr << "LTETX t=" << Simulator::Now().GetNanoSeconds() << " rnti=" << m_rnti << " uid=" << p->GetUid() << " size=" << p->GetSize() << std::endl;',
      occurrence_after="McEnbPdcp::DoTransmitPdcpSduLTE")
# eNB/gNB RRC forwarding: entry and each delivered packet
patch("src/lte/model/lte-enb-rrc.cc", "    // Prepare the variables for the LTE to MmWave DC forward",
      '\n    std::cerr << "FWD t=" << Simulator::Now().GetNanoSeconds() << " cell=" << m_rrc->m_cellId << " rnti=" << m_rnti << " imsi=" << m_imsi << " lte2mmw=" << mcLteToMmWaveForwarding << " mmw2mmw=" << mcMmToMmWaveForwarding << " rlc=" << rlc->GetInstanceTypeId().GetName() << std::endl;',
      after=False, occurrence_after="UeManager::ForwardRlcBuffers(Ptr<LteRlc> rlc,\n                             Ptr<LtePdcp> pdcp")
patch("src/lte/model/lte-enb-rrc.cc", "params.ueData = rlcSdu;",
      '\n            std::cerr << "FWDPKT t=" << Simulator::Now().GetNanoSeconds() << " rnti=" << m_rnti << " uid=" << rlcSdu->GetUid() << " size=" << rlcSdu->GetSize() << std::endl;')
print("ok")

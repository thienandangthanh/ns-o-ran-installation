# Inserts a D/C probe into McUePdcp/McEnbPdcp::DoReceivePdu of an ns-3 tree (scratch copy only).
# With --drop-abort it also removes the P7 NS_ABORT_MSG_IF on the D/C bit so processing continues
# exactly as at 4a0871d6 (parse as data).
import re, sys
root = sys.argv[1]
drop = "--drop-abort" in sys.argv
PROBE = r'''
    {
        uint8_t probeB[6] = {0, 0, 0, 0, 0, 0};
        uint32_t probeN = p->CopyData(probeB, 6);
        bool probeDc = probeN > 0 && (probeB[0] & 0x80);
        if (!probeDc || p->GetSize() > 1310)
        {
            char probeHex[32];
            snprintf(probeHex, sizeof probeHex, "%02x%02x%02x%02x%02x%02x", probeB[0], probeB[1],
                     probeB[2], probeB[3], probeB[4], probeB[5]);
            std::cerr << "PROBE %s t=" << Simulator::Now().GetNanoSeconds()
                      << " ctx=" << Simulator::GetContext() << " rnti=" << m_rnti
                      << " lcid=" << +m_lcid << " size=" << p->GetSize() << " dc=" << probeDc
                      << " bytes=" << probeHex << " delayNs=" << delay.GetNanoSeconds()
                      << " mmw=" << m_useMmWaveConnection << std::endl;
        }
    }
'''
for fname, tag in (("mc-ue-pdcp.cc", "UE"), ("mc-enb-pdcp.cc", "ENB")):
    path = f"{root}/src/lte/model/{fname}"
    s = open(path).read()
    anchor = 'NS_LOG_LOGIC("ALL BYTE TAGS REMOVED. NetAmin and FlowMonitor won\'t work");'
    i = s.index(anchor, s.index("::DoReceivePdu(Ptr<Packet> p)"))
    s = s[: i + len(anchor)] + PROBE.replace("%s", tag) + s[i + len(anchor):]
    if drop:
        s, n = re.subn(r'\n\s*NS_ABORT_MSG_IF\(pdcpHeader\.GetDcBit\(\) != DataPduHeader::DATA_PDU,\n\s*"Mc(Ue|Enb)Pdcp received a PDCP Control PDU; this model sends Data PDUs only"\);', "", s)
        assert n == 1, (fname, n)
    if "#include <cstdio>" not in s:
        s = s.replace('#include "ns3/log.h"', '#include "ns3/log.h"\n#include <cstdio>\n#include <iostream>', 1)
    open(path, "w").write(s)
    print("patched", path)

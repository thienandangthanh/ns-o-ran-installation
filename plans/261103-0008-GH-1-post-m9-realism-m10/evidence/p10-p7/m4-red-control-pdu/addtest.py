# Adds the Control PDU receive cases to the mc-pdcp-nr-header suite (scratch tree only).
import sys
path = sys.argv[1] + "/src/lte/test/lte-test-mc-pdcp-nr-header.cc"
s = open(path).read()
CASE = r'''/**
 * \ingroup lte-test
 * \brief An MC PDCP entity discards a received PDCP Control PDU (D/C 0, 3GPP TS 38.323 V19.1.0
 *        clauses 6.3.7 and 6.3.8): the entity is configured with no Control PDU, so the PDU
 *        carries reserved or invalid values for it (clause 5.10). After a Data PDU at SN 2047,
 *        a Control PDU larger than the delivery minimum delivers nothing and leaves RX SN 2048.
 */
template <class Pdcp>
class McPdcpControlPduRxTestCase : public TestCase
{
  public:
    McPdcpControlPduRxTestCase(const std::string& direction, uint8_t pduType)
        : TestCase(direction + " PDCP Control PDU of PDU type " + std::to_string(pduType) +
                   " discarded"),
          m_pduType(pduType)
    {
    }

  private:
    void DoRun() override
    {
        EnableHeaderMetadata();
        m_pdcp = CreateObject<Pdcp>();
        Wire(m_pdcp, DRB_LCID, &m_rlc, &m_user);
        uint32_t rxPdus = 0;
        m_pdcp->TraceConnectWithoutContext(
            "RxPDU",
            MakeBoundCallback(
                +[](uint32_t* n, uint16_t, uint8_t, uint32_t, uint64_t) { ++*n; },
                &rxPdus));

        const uint16_t sn = 2047;
        const Bytes sdu = Payload(sn + 7, 120);
        m_pdcp->GetLteRlcSapUser()->ReceivePdcpPdu(HandBuiltDataPdu(sn, sdu));

        // Octet 1 = D/C 0, PDU type, R R R R (Figure 6.2.3.1-1), then 100 octets: large enough
        // that a parse as a Data PDU would deliver an SDU and move RX SN.
        Bytes control(1, static_cast<uint8_t>(m_pduType << 4));
        const Bytes body = Payload(m_pduType + 3, 100);
        control.insert(control.end(), body.begin(), body.end());
        m_pdcp->GetLteRlcSapUser()->ReceivePdcpPdu(PacketOf(control));

        NS_TEST_EXPECT_MSG_EQ(rxPdus, 2u, "both PDUs counted as received from the RLC");
        NS_TEST_EXPECT_MSG_EQ(m_user.m_sdus.size(), 1u, "only the Data PDU's SDU delivered");
        NS_TEST_EXPECT_MSG_EQ(m_pdcp->GetStatus().rxSn,
                              static_cast<uint16_t>(sn + 1),
                              "RX SN unchanged by the Control PDU");
    }

    void DoTeardown() override
    {
        DisposeAll(m_pdcp);
        m_pdcp = nullptr;
    }

    uint8_t m_pduType;
    Ptr<Pdcp> m_pdcp;
    CapturingRlcSapProvider m_rlc;
    CapturingPdcpSapUser m_user;
};

'''
anchor = "/**\n * \\ingroup lte-test\n * \\brief The E-UTRA PDCP entity of SRB1 is unchanged"
assert s.count(anchor) == 1
s = s.replace(anchor, CASE + anchor)
REG_ANCHOR = "        using EnbForwarding = McPdcpForwardingTestCase<McEnbPdcp, McUePdcp>;"
REG = '''        // Status report, interspersed ROHC feedback (neither configured) and a reserved type.
        for (uint8_t pduType : {0, 1, 5})
        {
            AddTestCase(new McPdcpControlPduRxTestCase<McUePdcp>("DL McUePdcp", pduType),
                        TestCase::QUICK);
            AddTestCase(new McPdcpControlPduRxTestCase<McEnbPdcp>("UL McEnbPdcp", pduType),
                        TestCase::QUICK);
        }

'''
assert s.count(REG_ANCHOR) == 1
s = s.replace(REG_ANCHOR, REG + REG_ANCHOR)
open(path, "w").write(s)
print("ok")

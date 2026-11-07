# P9 X2 counters: consensus rulings (2026-11-07 13:15 KST)

These rulings came from a unanimous brainstorm consensus under the user's standing rule of 2026-11-07 02:21. They are **not user rulings**. They are shown at the next user session, where the user can reopen any of them. One question, the remedy for Q-2, is the user's to decide and is open.

Source: `brainstorm-261107-1244-GH-1-p9-x2-counter-ultra-debate.md`. The design counsel is `kongming-261107-1215-GH-1-p9-x2-counter-design.md`; its §3 interface contract is adopted as corrected below.

| Q | Ruling |
|---|---|
| Q-1 | **Count at the en-gNB's own X2-U boundary (R).** DL is counted for every GTP-U `McForwardDownlinkData` PDU the en-gNB receives, after the GTP-U header is removed and before the forward-map test (`epc-x2.cc:626`, `:642` @4318e43b). UL is counted for every `McForwardUplinkData` PDU it sends, in `DoReceiveMcPdcpSdu` before `:1291`. **This revises the counting sentence of user ruling Q2 in node and instant only.** The counted PDUs, their cell (`targetCellId`), the SDU-bit formula and the re-entered SDUs are all unchanged. Reason: an MN-instant count is 1 ms early (X2LinkDelay, `mmwave-point-to-point-epc-helper.cc:222-226`), which is 4 slots at numerology 2 (`mmwave-phy-mac-common.cc:48-52`). That fails R1 (1 slot), which row 151's Q5 amendment binds to this counter, and it fails (3) "its node owns the counted event". |
| Q-1b | A PDU that the S-SN redirects is counted at the S-SN and again at the T-SN: two X2 transfers into two NRCellCUs (Q2 + Q5). The S-SN's RLC-buffer forward counts at the T-SN only. Disclosed: Σ_g X2DL exceeds the MN's X2 output during an SN change. Interpretations: no en-gNB counter carries the SwitchToLte return (`lte-enb-rrc.cc:2031-2037`, untyped `SendUeData`); an arrival counts whatever its RLC user does with it. |
| Q-2 | **The forwarded RLC UM tail is an R1 gap, not an interpretation.** On the S-SN forward, a D/C = 1 tail of N payload octets is counted as 8 × (N − 2), so 16 bits are lost: an error in value, not timing. **The remedy is the user's (open; see below).** Until it is ruled, the X2 registry entries cannot record `holds: true`. |
| Q-3 | **(b): a new ns-3 suite `epc-x2-mc-pdcp-volume`, gated at M4 (row 163).** |
| Q-4 (i) | A6 also requires ≥ 1 x2ul event. |
| Q-4 (ii) | A8 is required, in inclusion form (row 151 amendment below). It replaces the counsel's one-sided 2 ms exclusion. |
| Q-4 (iii) | The lint's pending machinery is removed (row 147 note, stricter). |
| Q-4 (iv) | Row 152 additions (a)–(d). |
| Q-4 (v) | Row 164: the regenerated KPM T/T golden. |
| Q-4 (vi) | Audit v2 grammar per the counsel's §3.3. N4 identity is not a P9 gate (row 150 note). Fix the v3 key list at `gate-n4-ul-metric.sh:420`. |

## Open for the user: the Q-2 remedy
Every remedy changes M10's scope or a user ruling, so the brainstorm does not pick one.
- **(a) Fix the tail framing in its own ns-3 commit right before P9** (precedent: the SN-wrap commit before P7).
  - The tail is detectable. It still carries `LteRlcSduStatusTag` LAST_SEGMENT or MIDDLE_SEGMENT (`lte-rlc-um-lowlat.cc:258-282`), and `DeliverRlcForwardingBuffer` strips tags only after its D/C test (`lte-rlc-forwarding-buffer.cc:190-194`). A FULL_SDU test before the D/C test forwards only whole PDCP PDUs.
  - **(a-narrow)** Apply it only to the S-SN secondary-cell forward (`forwardPdcpPdus`, `lte-enb-rrc.cc:939`). Row 149's P7 counts stay as they are.
  - **(a-wide)** Apply it to every caller, including the LTE↔mmWave switch forwards (`:1483`, `:1903`). This also absorbs the "RLC UM tail re-submission" follow-up into M10 and changes row 149's short rows, which then need a row 149 amendment.
- **(b) A user-owned exception.** At most 16 bits per forwarded D/C = 1 tail, at most one tail per RLC entity per SN change, recorded in the registry. Row 151's Q5 amendment names this as the fallback.
- **(c) `ns3.*` names for the X2 rows.** This undoes Option A. Not recommended.

## Ledger text applied in the docs commit before P9 code
The following were applied: new rows 163 and 164; additive blocks for row 151, row 152, row 147 (note), row 150 (note) and row 161 (detail). See the ledger.

## Unresolved questions
- The Q-2 remedy: (a-narrow), (a-wide), (b) or (c).
- Implementation cost of the row 163 suite: whether `EpcX2::AddX2Interface` can be driven without a full EPC stack.

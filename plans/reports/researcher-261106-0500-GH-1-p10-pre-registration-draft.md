# P10 pre-registration draft: P6, P7, P9, P15, UseIdealRrc, row 139 amendment

Date: 2026-11-06 ~05:00 KST. Author: researcher subagent (read-only; no plan, ledger, code or VM change).
Pins read: harness `f911f7e5`, ns-3 `ea6e46f6`, oran-interface `53253fe2`, Testbed `163ef252`. The Testbed working tree also holds uncommitted D-R3-1 edits (`e2-node-identity.{hpp,cpp}`, `codec-probe-e2ap.cpp`), which I did not read or touch.
Legend: [V] verified here, with file:line or clause and PDF page. [I] inference. [U] not read.

## 0. Outcome (lead)

1. **P6 cannot be fixed as Design words it.** QosFlow.PdcpPduVolumeDL is a split-gNB measurement (CU→DU over F1-U) that excludes Dual-Connectivity volume. The ns-3 en-gNB is non-split, and every one of its bearers is DC. The honest fix renames the MAC value in place to a vendor `ns3.*` name, and puts no 3GPP PDCP PDU volume on the en-gNB. 28.552 defines no MAC-layer volume measurement to move it to. This needs a user ruling (Q1).
2. **Units are already right for the volume counters.** E2SM-KPM v03.00 §7.9.1 replaces 28.552's Mbit with **kbit INTEGER** for DRB.PdcpSduVolumeDL/UL, QosFlow.PdcpPduVolumeDL and the X2 variants. Map rows `:56-57` (INTEGER, kbit) conform, so no unit change reaches R3′'s scenario.
3. **P7 SN width: pre-register 18 bits.** 38.323 allows 12 or 18 bits for DRBs, and RRC picks one. At 12 bits the NR header is byte-identical to the E-UTRA DL header, so check (a) and AC16's trace check would be vacuous. At 18 bits the reordering window is 2^17 = 131072. The width change touches 9 consumer sites the Design list omits. The rollover check (c) fails on today's code, at 12 bits already.
4. **P9: strict 28.552 gives 0 for the en-gNB.** For an MN-terminated split bearer, no SDU enters the en-gNB's PDCP. Two honest options exist. Option A reports the via-SN volume as DRB.PdcpSduVolumeX2DL/UL and needs a T3 ruling. Option B keeps the name with a recorded interpretation and needs no T3. This needs a user ruling (Q2). Either way, `check-pdcp-volume-totals.py` attributes volume by leg.
5. **P15 is backed by the spec.** Table 7.8-1 maps Style 1 to Action Format 1 and Indication Format 1, and Style 3 to Action Format 3 and Indication Format 2. All 8 row-100 sites are verified at their current lines.
6. **c (I-2) is 3 × X2LinkDelay [I], which no Uu message enters.** UseIdealRrc=false can still move it, through the PrepareHandover queue in CONNECTION_RECONFIGURATION. Pre-register: the predicate is unchanged, the probe records every offset, and any offset ≠ 3.0 ms is a Stop.
7. **Two budget hazards the 7.2 table misses.** Any metric-map or lint change (P6) forces an agent rebuild and a kpimon reinstall: the agent image holds the map, and the kpimon installer runs the lint. P6, P7 and P9 also need M5 under `plan.md:72`.

## 1. P6: QosFlow.PdcpPduVolumeDL and the metric-map lint

### Spec [V]
| Claim | Source |
|---|---|
| QosFlow.PdcpPduVolumeDL counts the PDCP PDU bits **from gNB-CU to gNB-DU**. "The measurements of DL Cell PDCP PDU Data Volume in Dual-Connectivity scenarios is not included." It is an integer in Mbit, object GNBCUUPFunction / NRCellCU, and "NRCellCU measurement applies only for 2-split deployment". | 28.552 V20.2.0 §5.1.3.6.1.1, PDF pp.196–197 |
| §5.1.3 is "Performance measurements valid for split gNB deployment scenario". §5.1.2 is "valid only for non-split". | 28.552 PDF p.188, p.183 |
| E2SM-KPM replaces Mbit with **Kbit, INTEGER** for QosFlow.PdcpPduVolumeDL, DRB.PdcpSduVolumeDL/UL, X2DL/UL, XnDL/UL, and the 32.425 DRB.PdcpSduVolumeDl/Ul. KPM cites the DL/UL cell clauses as 5.1.2.1.2.1/.2.2, an older 28.552 numbering; V20.2.0 has DL at 5.1.2.1.1.1. | KPM v03.00 §7.9.1, PDF p.14 |
| No MAC-layer data-volume measurement exists in 28.552. Searches for "MacPduVolume", "MacSduVolume" and "MAC PDU bits" find nothing, and the TOC lists none. The closest is O-RAN's DRB.RlcSduTransmittedVolumeDL (RLC SDU level, UE-acknowledged, NRCellDU, kbit), which is a kpm_sim name the lint forbids (`lint-metric-map.py:31-35`). | 28.552 full-text search; KPM §7.10.1, p.15 |
| The ns-3 en-gNB is non-split. Its only node config is the `x2` component (no F1) [V `evidence/s10/20261105T184211Z/runs/live1/s10/e2mgr-node-10.json` nodeConfigs], and it has one NG component plus X2 per phase-05's exit record. | evidence |

### Code [V]
- The cell value is MAC: `oran-interface/helper/mmwave-indication-message-helper.cc:132` sends `QosFlow.PdcpPduVolumeDL_Filter` = `macVolumeCellSpecific`. That is the sum of `m_tbSize` per (RNTI, cell) at `ns-3-mmwave-oran/src/mmwave/helper/mmwave-phy-trace.cc:262`, retransmissions included, in bytes, summed at `mmwave-enb-net-device.cc:1167-1169`.
- Affected map rows (`ns3_e2_agent/schema/metric-map.v1.json`; line numbers unchanged from the plan):

| Line | kind/list/order | kpm | Source and true unit | Finding |
|---|---|---|---|---|
| :33 | gnb/cell/11 | QosFlow.PdcpPduVolumeDL, REAL, "bytes/period" | MAC TB bytes (`helper:132`) | wrong layer; split-only, DC-excluded name; KPM type INTEGER |
| :68 | gnb/ue/11 | ns3.du.QosFlow.PdcpPduVolumeDL | MAC TB bytes per UE (`helper:88`) | vendor name, but it embeds a 3GPP name |
| :85 | gnb/ue/28 | QosFlow.PdcpPduVolumeDL, "bytes/period" | NR RLC tx bytes **in kbit** (`mmwave-enb-net-device.cc:720,725`; `helper:44`; the plan cites `:43`, which is the comment) | wrong layer; unit label wrong |
| :134 | enb/ue/11 | QosFlow.PdcpPduVolumeDL, "bytes/period" | MN PDCP kbit − LTE RLC kbit (`lte-enb-net-device.cc:1110-1111,1134,1158`) | E-UTRA node; DC; unit label wrong |
| :86, :135 | gnb/ue, enb/ue | DRB.PdcpPduNbrDl.Qos | — | no clause in 28.552 or KPM v03 [V search] |
| :47, :83 | gnb cell/ue | DRB.BufferSize.Qos | — | no clause in 28.552 or KPM v03 [V search] |
| :128 | enb/ue/5 | DRB.PdcpSduVolumeDl, REAL, "bytes/period" | MN PDCP **PDU** kbit (`lte-enb-net-device.cc:1110-1111`) | PDU, not SDU; KPM type INTEGER; label wrong (32.425 [U]) |
| :56-57 | gnb/cell/34-35 | DRB.PdcpSduVolumeUL/DL, INTEGER, kbit | `mmwave-enb-net-device.cc:707-708,834-836` | conforms on unit and type; P9 changes the value |

### Pre-registered change (recommended, pending Q1)
- Rename row `:33` in place to `ns3.du.macVolumeDl`: same order 11, same measId 11 (the doc's "stable; append-only", `:11`), REAL, bytes/period, layer MAC. Do the same for `:68` (one REAL name across both lists; lint `:76-77`).
- Put no QosFlow.PdcpPduVolumeDL on any node. No conforming source exists, because the en-gNB is non-split and every bearer is DC.
- Rename `:85`, `:86`, `:134`, `:135`, `:47` and `:83` in place to `ns3.*` vendor names, and correct their unit labels to what the code computes (kbit where the code applies `*8/1e3`).
- Row `:128`: make the value SDU bits as an INTEGER in kbit, or rename it to `ns3.*`. Its clause is 32.425 §4.4.7.1 [U], see Q3.
- Classify the remaining 3GPP-style names at the phase. The map holds 38 distinct non-`ns3` names. I confirmed only presence for DRB.UEThpDl (28.552 p.57), RRC.ConnMean (p.68), DRB.MeanActiveUeDl (p.143) and TB.TotNbrDlInitial* (p.112).
- KISS: P6 needs only the map and kpimon's `enb-kpm-measurements.json`. The ns-3 `AddItem` keys are src pointers and can stay (they appear in the IPC traces).
- **Hazard [V]:** the agent image copies the map (`ns3_e2_agent/Dockerfile:92`). The kpimon installer runs the lint with `--kpimon-enb` (`additional_scripts/install_xapp_kpi_monitor.sh:193`), and kpimon's stale-image key includes the map and the lint (`scripts/gates/kpimon.sh:34-37`). So P6 means an agent rebuild, a kpimon reinstall (~3 GiB [I]), and M5, M6 and M7 (`plan.md:72`).

## 2. P7: NR PDCP header on the EN-DC bearer

### Spec [V]
- 37.340 V19.3.0 §4.2.2 (PDF p.14; `PZYCKMNI` is newer than `E6VYJPXJ` V18.7.0): for a UE that supports EN-DC, the network "can configure either E-UTRA PDCP or NR PDCP for MN terminated MCG bearers while NR PDCP is always used for all other bearers". SRB1/SRB2 may use either (p.13).
- The ns-3 MC bearer is an MN-terminated split bearer: the PDCP is at the MN, with an LTE RLC leg and an X2→SN RLC leg (`mc-enb-pdcp.cc:275-292`). NR PDCP is therefore mandatory for it. Using NR from bearer creation is allowed (the MCG case), so no mid-life header switch is needed.
- 38.323 V19.1.0 §6.3.2 (PDF p.45): the SN length is "12 or 18 bits ... configured by upper layers (pdcp-SN-SizeUL, pdcp-SN-SizeDL)". 38.331 V19.4.0 (`WF2FTADX`, p.1044, p.1048) makes it `ENUMERATED {len12bits, len18bits}`, and "for SRBs only len12bits". No clause forces either width for a DRB.
- Headers (38.323 §6.2.2.2/§6.2.2.3, figures on PDF p.40, printed p.39):
  - 12-bit: octet 1 = D/C, R, R, R, SN[11:8]; octet 2 = SN[7:0].
  - 18-bit: octet 1 = D/C, R×5, SN[17:16]; octets 2–3 = SN[15:0].
  - MAC-I appears on a DRB only with integrity protection (§6.3.4, p.46), so none here. D/C = 1 is a Data PDU (§6.3.7, p.46).
- 36.323 V19.0.0 §6.2.3 (PDF p.40): the E-UTRA 12-bit DL header is D/C, R, R, R, SN, which is **byte-identical** to the NR 12-bit header. UL differs only by the AILC bit.
- Window_Size = 2^(pdcp-SN-Size − 1) (38.323 §7.2, p.49): 2048 at 12 bits and 131072 at 18 bits.

### Pre-registered SN width (recommended, Q4 to confirm): 18 bits, DL and UL, every Mc*Pdcp DRB
- [V] Only 18 bits makes the NR header distinguishable on the bytes. At 12 bits, (a) and AC16's "traces show an NR header" cannot fail.
- [I] Fit: DL is 1308-byte SDUs every 500 µs per UE (`scenario-zero.cc:691-693`), about 2000 PDU/s. At 12 bits the SN wraps about every 2 s, and the 2048 window is about 1 s of traffic. At 18 bits the SN wraps every ~131 s, so live runs never wrap and only test (c) exercises rollover.
- Header: 3 octets, `oct1 = 0x80 | (SN >> 16 & 0x03)`, `oct2 = SN >> 8 & 0xFF`, `oct3 = SN & 0xFF`. A DL data PDU is 1308 + 3 = 1311 bytes (today 1310).
- SRB1 keeps `LtePdcp` with the E-UTRA header (`lte-enb-rrc.cc:251`, `lte-ue-rrc.cc:2208`). Every DRB is Mc*Pdcp (`lte-enb-rrc.cc:499-500`, `lte-ue-rrc.cc:2312`), so "bearer type" = PDCP class.

### Consumers, verified at current lines
| Site | Current line | In Design? |
|---|---|---|
| McEnbPdcp writer/parser | `mc-enb-pdcp.cc:247-259`, `:313-321` (wraps at `:251`, `:318`) | yes (`:247,256,313`) |
| McUePdcp writer/parser | `mc-ue-pdcp.cc:197-209`, `:256-267` (size guard `:256 > 3`) | yes, guard no |
| UE forwarding | `lte-ue-rrc.cc:1700` (guard `:1706 > 3`), `:1759` (SN window `:1774-1775`), `:1829` (guard `:1835 >= 3`) | lines yes, guards and arithmetic no |
| eNB forwarding/HO buffers | `lte-enb-rrc.cc:1034` (guard `:1040`), `:1091` (`:1105-1106` `SN >= SN_1 − 2`), `:1176` (guard `:1182`) | lines yes, guards and arithmetic no |
| RLC AM recovery | `lte-rlc-am.cc:1801-1808`, keyed into `std::map<uint32_t,…>` (`lte-rlc-am.h:208`): it orders by raw SN, so the order is wrong across a wrap | line yes, ordering no |
| LtePdcp (SRB only) | `lte-pdcp.cc:180,189,221` | yes (assert) |
| SN types and limits | `mc-enb-pdcp.h:123,226-227,235`; `mc-ue-pdcp.h:108,195-196,201` (`uint16_t`, 4095); `lte-pdcp-header.h:74` (`uint16_t GetSequenceNumber`), `lte-pdcp-header.cc:53` (`& 0x0FFF`) | **no**: 2^18 does not fit `uint16_t` |
| P9 subtraction | `mmwave-enb-net-device.cc:677` (the plan says `:658`, which is the function start) | yes, line drifted |
| N4 audit header print | `scratch/scenario-zero.cc:727` (`LtePdcpHeader().GetSerializedSize()`) | **no** |
| Harness audit judge | `scripts/gates/check-pdcp-volume-totals.py:37` (HDR = 2), `:99` (A1), `:121` (A5), doc `:11-12` | **no** (it is listed under P9 only) |
| UseIdealRrc | `scenario-zero.cc:492` (the plan says `:483`) | line drifted |

"Fails loudly" mechanism [I]: McEnbPdcp and McUePdcp tag every PDU with a header-type packet tag. Each consumer above reads the tag, and `NS_FATAL_ERROR` fires when it is absent. The RLC therefore never guesses the header.

### Checks (a)–(c), pre-registered
New suite `mc-pdcp-nr-header`, made gate-visible by row 148. Cases (a) and (c) go in `src/lte/test/test-mc-pdcp-nr-header.cc`. Case (b) needs the mmWave EN-DC topology, so it goes in `src/mmwave/test/` [I: the lte module cannot link mmwave; check CMake].
- **(a) `nr-header-bytes`.**
  - Setup: McEnbPdcp (DL) and McUePdcp (UL) send 1308-byte SDUs into a stub RLC SAP, at SN ∈ {0, 1, 4096, 2^17, 2^18−1}.
  - Pass iff the PDU is SDU + 3 bytes, the three octets match the formula above with the 5 R bits = 0 and D/C = 1, and the payload equals the SDU byte for byte.
  - The McUePdcp RX of a hand-built 18-bit PDU delivers the SDU and sets RX SN + 1.
  - SRB LtePdcp still emits 2 octets.
  - Non-vacuity: the same assertions on an LtePdcpHeader-built PDU fail on size and at SN ≥ 4096.
- **(b) `payload-preserved-through-forwarding`.**
  - Setup: 1 eNB, 2 en-gNBs, 1 UE, RLC AM, DL and UL UDP whose payloads carry an id and a pattern.
  - Two scenarios: (b1) an MN-initiated secondary-cell change with non-empty RLC buffers (eNB path `lte-enb-rrc.cc` `:1034-1182`); (b2) the same at the UE (UL path `lte-ue-rrc.cc` `:1700-1835`).
  - Pass iff every SDU delivered at the receiving PDCP is byte-equal to a sent SDU (no header byte leaks), and every sent id is delivered.
  - Run the case once at the `m10-cp2` pins first, as a baseline. If ns-3 already loses SDUs there, record that and judge byte equality only (Q5).
- **(c) `sn-rollover-recovery`.**
  - McEnbPdcp TX at 2^18−2 yields SNs 262142, 262143, 0, and RX wraps the same way.
  - `CreateRlcSduBuffer` over SDUs {262142, 262143, 0, 1} then iterates in COUNT order.
  - The `lte-enb-rrc.cc:1105` and `lte-ue-rrc.cc:1774` "previous two SDUs" selection picks SN_1−2 and SN_1−1 modulo 2^18.
  - [V] Today's `std::map` keyed by raw SN orders 0 and 1 first, and the `uint16_t − 2` comparison breaks at SN_1 ∈ {0, 1}. So (c) fails now, which makes it non-vacuous, and it needs a fix in P7.
- **(d)** M4, M5, M6, M7, plus row 149's trace check.

## 3. P9: DRB.PdcpSduVolumeDL/UL on the en-gNB

### Spec [V]
- DRB.PdcpSduVolumeDL (28.552 §5.1.2.1.1.1, PDF p.183): "obtained by counting the number of bits **entering the NG-RAN PDCP layers** ... at the PDCP SDU level", object NRCellCU, non-split. UL is §5.1.2.1.2.1 (p.185): bits "delivered from PDCP layer to higher layers". The KPM unit is kbit INTEGER (§7.9.1, p.14).
- DRB.PdcpSduVolumeX2DL/UL (§5.1.2.1.1.2, pp.183–184; §5.1.2.1.2.2, pp.185–186): "PDCP SDU bits ... delivered on X2 interface in DC-scenarios", NRCellCU, QCI in EN-DC. The KPM unit is kbit INTEGER.
- 37.340 §4.2.2 (p.14): for an MN-terminated split bearer, the PDCP entity is in the MN.
- [I] Read strictly, **no SDU of an MN-terminated bearer enters the en-gNB's PDCP**, so DRB.PdcpSduVolumeDL/UL = 0 at every en-gNB in this scenario. The via-SN portion is the X2 measurement's subject. Whether "delivered on X2" covers MN→SN PDU traffic counted at SDU level is itself [I].

### Current computation [V]
- `mmwave-enb-net-device.cc:658` (`BuildRicIndicationMessageCuUp`) loops over the gNB's UE map (`:686`) and sums the **MN** McEnbPdcp's LCID-3 bytes:
  - DL TxPDU and UL RxPDU (`:700-708`), taken from the shared E2 PDCP calculator. Both legs feed it (`mmwave-bearer-stats-connector.cc:310-318`; `mmwave-helper.cc:3195-3201`).
  - It subtracts one LtePdcpHeader size per PDU (`:677`), and rounds to kbit once per cell (`:834-836`).
- So the gNB is credited with the LTE-leg volume too. McEnbPdcp sends to LTE with probability `perPckToLTE` (default 0.5, `mc-enb-pdcp.cc:109-113,277`). The legs are separable at `DoTransmitPdcpSduLTE` (`:214-229`) vs `DoTransmitPdcpSduMmWave` (`:232-240`, target = `m_ueDataParams.targetCellId`), and at `DoReceivePdu` vs `DoReceiveMcPdcpPdu` (`:296`, `:333-337`).

### Options (ranked; Q2)
1. **A, recommended:** DRB.PdcpSduVolumeDL/UL at the en-gNB = bits entering its own PDCP, which is 0 here. The via-SN SDU bits are reported as DRB.PdcpSduVolumeX2DL/UL, appended to the map as new orders, kbit INTEGER. The predictor reads X2DL with the same formula.
   - Needs: a T3 ruling on `r3p-scenario.json:8-9,13,29` (counter field) and a contract-Decision check on "reads the corrected counter" (contract `:116`, `:190`).
   - `r3p-scenario.json` is a row-21 (#9) file, so it carries a flag like row 141's.
2. **B:** keep the name DRB.PdcpSduVolumeDL with the via-SN SDU bits, as Design's [I]. This is a recorded interpretation, since those bits do not enter this node's PDCP. No T3 follows; the values move, and P11 attributes the change.
3. Rejected: the name kept with value 0, because the predictor would go dead and R3′ would be red.

For both A and B, ns-3 adds per-leg cell counters, from new McEnbPdcp traces at `:238` and `:336` that carry the SN cell id. The counters reset at each read of the cell, not per UE. The header size comes from the NR header (3).

**Predictor** (`scripts/gates/r3p-predictor.py:44-75`): the formula and the decision mirror are unchanged under both options. Under B there is no row. Under A there is a key change (row 152), with readers at `n6-fixtures.py:10`, `r3p-checks-fixtures.py:15`, `digest-run.py:64`, `check-n4-v5-windows.py:29`, `n4-drop-selftest.py:17` and `r3p-scenario.json:8-13,29`.

## 4. P15: per-action indication format

### Spec [V] (KPM v03.00, `F82PYZVK`)
- §7.4.2.2 (p.9): Style 1 uses Action Definition Format 1. "the Cell Global ID IE **shall be included**" when the measurement types belong to a single-cell object class (NRCellDU, NRCellCU; 32.425 EUtranCell…).
- §7.4.2.4 (p.10): Style 1 uses Indication Message Format 1.
- §7.4.4.2 (p.10): Style 3 uses Action Definition Format 3.
- §7.4.4.4 (p.11): Style 3 uses Indication Message Format 2.
- Table 7.8-1 (p.13): Style 1 → Action 1 / Header 1 / Message 1; Style 3 → Action 3 / Header 1 / Message 2.

### Today [V]
- The agent sends every report on the lowest admitted action (`ns3_e2_agent/src/e2-session.cpp:179-180`, `:214`): one cell Format 1 and the UE Format 2 messages (`:231-232`; encoders at `sample-forwarder.cpp:211`, `:253`).
- The agent decodes each action's format (`kpm-subscription-admission.cpp:42-80`) but does not keep it (`subscription-table.hpp:21-22`).

### Row 100's 8 sites (all verified)
`gate-m6-kpm.sh:100`; `gate-m7-multignb.sh:204`; `gate-r0-rc-scripted.sh:206` (the ledger says `:201`); `gate-r1-rc-multi-control.sh:174` (the ledger says `:184`); `gate-p12-kpm-period.sh:138` (a) and `:212` (c); `gate-e2i-interop.sh:278`; `ts-rung-lib.sh:85` (r2, r3p, s10; the s10 evidence shows `s10_live1_kpimon_subscription_one_action_id1_format3`).

Shared code: `agents-ns3-run.sh:223-224` (`kpm_sub_actions_check`, doc `:15`), `e2-facts-query.py:393-440` (`q_sub_actions`, doc `:18-24`, self-test `:443-499`), `e2ap-pcap-facts.py:187-211` (`parse_sub_actions`).

### p12 re-baseline
- `p12-records-check.py` judges `msg_format` only (`:190-207`). Its records carry no action ID, because `tools/kpimon-decode-harness/pcap-to-lines.py:28-29` extracts no `ricActionID`.
- New: `pcap-to-lines.py` adds the E2AP ricActionID field [I: the tshark field name, `e2ap.ricActionID`, is to be checked with `tshark -G fields`]. The harness passes it through. Check 2 requires the Format 1 action, and check 4 requires the Format 3 action.
- With one cell per node, the IDs are 1 (F1) and 2 (F3) [I, P05 item 4], and the counts per node stay the same.

## 5. UseIdealRrc (AC17) and c

### What c is today [V]
- c = 3.0 ms (`check-actuation-delay.py:12,91`): every applied line needs a HandoverStart for the same IMSI and target at `applySimTimeNs` + 3.0 ms, at 0.1 ms ticks (`:46-56`).
- It runs in r3p as `r3p_<label>_actuation_delay_applied_at_rx_plus_delta_handover_start_at_apply_plus_c` (`gate-r3p-ts-predictor.sh:257-258`), and in M10's d100, d200 and d500 (`plan.md:160-163`, I-2 `:283`).

### Where it comes from [I]
- HandoverStart fires in `UeManager::RecvHandoverRequestAck` (`lte-enb-rrc.cc:869`, trace `:909`), after three X2 legs: MN `SendMcHandoverRequest` → source SN, `SendHandoverRequest` → target SN (`:774`), and Ack back.
- X2LinkDelay defaults to 1 ms (`mmwave-point-to-point-epc-helper.cc:224`), and no Uu message lies on that path. Ideal RRC has a 0 ms message delay (`lte-rrc-protocol-ideal.cc:50`).
- Real RRC can still move c: when the source UeManager is in CONNECTION_RECONFIGURATION or HANDOVER_JOINING, PrepareHandover is queued (`lte-enb-rrc.cc:779-781`) and replayed after the Uu round trip (`:1817-1819`, `:1880-1882`).

### Pre-registered judgement (row 156)
- The I-2 predicate is unchanged under UseIdealRrc=false: c = 3.0 ms exactly.
- The probe run records `applyToHandoverStartMs` for every applied line (already output, `:59-60`).
- If any probe offset ≠ 3.0 ms, P10 stops before the UseIdealRrc commit for a user ruling, and no re-baseline is pre-approved.
- Note: S-R covers only a probe that does not complete with ≥ 1 applied PSCell change. An offset change is a predicate change (AC18), not an S-R case.
- After adoption, measure the 10-gNB wall rate (review 7.3 item 5).

## 6. Row 139 amendment, from s10's node 10 [V]
- The source file exists on disk but is **not git-tracked** (verdict-layer allowlist): `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/s10/20261105T184211Z/runs/live1/s10/e2mgr-node-10.json`, sha256 `f851b83b74be1044f82347466c114611bce5095cfd891ec348a1ddb367ac4148`.
- Its content: ranName `en_gnb_001_001_0000000a`, nodeType GNB/EN_GNB, one `x2` node config.
- The request part, base64 → hex text, is 138 characters. The suffix `0000000A` occurs at offset 46 (key `0000000A00`, Global en-gNB ID + next IE id) and offset 80 (key `0000000A10`, NR CGI).
- The bytes are from the cp2 era, before D-R3-1.
- The C++ hex-letter path is the `toupper` loop after `nr_meid` (`ts_xapp.cpp.nr_cell_map.patch`), which no current test reaches with a letter.

## 7. Draft ledger rows (147–158)

| # | Phase | Check (file:line) | Old | New | Why not weaker | #9? |
|---|---|---|---|---|---|---|
| 147 | P10 (P6, AC16) | `ns3_e2_agent/tests/lint-metric-map.py` `lint()` `:54-98`, FIELDS `:37`; run by `install_xapp_kpi_monitor.sh:193` and by phase-10 Validation; new `--self-test` added to `scripts/gates/lint.sh` | Fields present; kind, list, type, scope and xform enums; one type per name; PrintableString; order 1..n; measId = base + order; lead names; no kpm_sim overlap. `unit` and `origin` informational; no clause or layer | Every old conjunct, plus: each row carries `clause` and `layer`. A non-`ns3.` name must name an entry of a new registry `schema/kpm-measurement-clauses.v1.json`. Each entry holds name, document §/page, object class, layer, unit (KPM §7.9.1 where listed, else 3GPP), type, `splitOnly`, `dcExcluded`, each read from Zotero. The row's unit, type and layer must equal the entry's. The src section must fit the layer (`/cell/du`,`/du` → PHY/MAC/RLC; `*/cuUp` → PDCP; `*/cuCp` → RRC). A `gnb` row (non-split en-gNB) may not use a `splitOnly` entry. `ns3.*` rows are exempt from the clause check but need `layer`. Self-test fixtures that must fail: a MAC src under QosFlow.PdcpPduVolumeDL; a REAL DRB.PdcpSduVolumeDL; a Mbit unit; a split-only name on gnb; a 3GPP name with no clause. The shipped map must pass | Strict conjunction; the old checks are kept. Today's map fails it at `:33`, `:85`, `:128`, `:134` | No |
| 148 | P10 (P7) | New `m4_ns3_pdcp_mc_nr_header_suites_pass` in `gate-m4-ns3-build.sh` (after `:181`), running `./test.py -s mc-pdcp-nr-header` (and the mmwave (b) suite) | None; P07's suite was run by hand (`phase-07:217`) | All cases (a), (b) and (c) of §2 pass. (c) fails at `m10-cp2`, which proves it non-vacuous | New check | No |
| 149 | P10 (P7, AC16 "traces show NR header") | New `<step>_pdcp_dl_pdu_bytes_eq_sdu_plus_nr_header` (`tools/e2-evidence/trace-facts.py --pdcp-stats`) at M6 and M7 [I: exact stats file and columns, `DlE2PdcpStats.txt`] | None | Every LCID-3 epoch row with nTxPDUs > 0 has TxBytes = nTxPDUs × (1308 + 3). A fixture at 1310 (E-UTRA 12-bit) fails | New check | No |
| 150 | P10 (P7; lands in P7's harness commit with the ns-3 pin) | `check-pdcp-volume-totals.py:37` HDR, A1 `:99`, A5 `:121`, doc `:11-12`; self-test `:230` | hdr == 2 (36.323 §6.2.3); A5 pduBytes ≥ 3 | hdr == 3 (38.323 §6.2.2.3; `scenario-zero.cc:727` prints the DRB NrPdcpHeader size); A5 pduBytes ≥ 4. The self-test case "header size 2" fails | Same equality on the spec'd value; the old value becomes a failing fixture | No |
| 151 | P10 (P9) | `check-pdcp-volume-totals.py` A4 `:124-198`, `load_audit` `:42-58`; audit v2 in `scenario-zero.cc:45-109` | Truth for a gNB sample = the SDU bits of **all** LCID-3 MN PDCP events of the UEs the sample lists, in (that UE's previous gNB read, this read]; overlap groups summed | Audit v2 lines add `leg` (the SN cell id for X2-routed DL/UL PDUs; 0 for the LTE leg). Truth for (g, t) = Σ SDU bits with leg == g in (g's previous read, t]. Same 500-bit and 1-kbit-per-cell tolerances, ties, residual and unverified rules. New A6: the run has ≥ 1 LTE-leg and ≥ 1 NR-leg LCID-3 DL event. Option A also requires KEYS → X2 names and A7: DRB.PdcpSduVolumeUL/DL == 0 on every gNB sample. Self-test: "counter = all MN volume" (today's ns-3) fails | Same tolerance on a narrower, correct truth. A6 guarantees today's behaviour fails | No |
| 152 | P10 (P9, Option A only) | R3′ counter key: `r3p-scenario.json:8-9,13,29`, `r3p-predictor.py:6`, `n6-fixtures.py:10`, `r3p-checks-fixtures.py:15`, `digest-run.py:64`, `check-n4-v5-windows.py:29`, `n4-drop-selftest.py:17` | field DRB.PdcpSduVolumeDL | field DRB.PdcpSduVolumeX2DL; formula, window, threshold and decision unchanged | Same predicate on the counter that measures the routed volume | No, but flag: `r3p-scenario.json` is a row-21 #9 file; T3 |
| 153 | P10 (P15; register in a docs commit before code) | `q_sub_actions` `e2-facts-query.py:393-440` (doc `:18-24`), `parse_sub_actions` `e2ap-pcap-facts.py:187-211`, via `kpm_sub_actions_check` `agents-ns3-run.sh:223-224`, at m6 `:100`, m7 `:204`, r0 `:206`, r1 `:174`, p12 `:138`/`:212`, e2i `:278`, `ts-rung-lib.sh:85`; checks renamed `…_kpimon_subscription_format1_per_cell_and_format3` | Exactly 1 item: ID 1, report, Format 3; each node ≥ 1 request | Every request after the capture start on an expected node's association has exactly C+1 items, where C = the served cells in that node's E2 Setup X2 request part in the same capture (1 per ns-3 node). IDs 1..C are report actions in Format 1 whose cellGlobalID equals a served cell's CGI, each cell once (NR CGI on an en-gNB, E-UTRA CGI on the eNB). ID C+1 is report, Format 3. The RIC SUBSCRIPTION RESPONSE admits all C+1 (no NotAdmitted). Each node ≥ 1 request. Self-test: the old single-F3 form fails; F1 without CGI fails; a foreign CGI fails; two F3 fail; a not-admitted action fails | The F3 conjuncts are kept except the ID (1 → C+1, P05 item 4). C F1 conjuncts and an admission conjunct are added. The CGI is taken from the capture, not a meid literal, so no P5 | No |
| 154 | P10 (P15) | New `<site>_kpm_indication_format_equals_its_action_format` at m6, m7, p12 a, e2i, r0, r1 and `ts-rung-lib.sh`, through `pcap-to-lines.py` + ricActionID and a new `e2-facts-query.py ind-actions` | None (today every report rides action 1) | Every RICindication after the capture start carries an action ID admitted in its subscription. Under an F1 action the message is Format 1 and its `ns3.nodeId` is the node; under the F3 action it is Format 2. Each admitted action receives ≥ 1 indication. Self-test: F1 under the F3 action (today) fails; F2 under F1 fails; an unknown ID fails; a silent action fails | New check | No |
| 155 | P10 (P15) | `p12-records-check.py` checks 2 and 4 (`:24-34`, `:190-207`); the gate check `p12_a_one_indication_per_10_seqs_with_10_records` (`gate-p12-kpm-period.sh:141-148`) | Format judged by `msg_format` only | Every old conjunct, plus each record's `actionId`: check 2 requires the subscription's F1 action of that node's cell, check 4 its F3 action | Strict conjunction | No |
| 156 | P10 (UseIdealRrc; register before the probe) | `check-actuation-delay.py:36-60`, `--c-ms` default `:91`; `gate-r3p-ts-predictor.sh:257-258`; M10 d100/d200/d500 | c = 3.0 ms, HandoverStart = apply + c at 0.1 ms | Unchanged under UseIdealRrc=false. The probe records every `applyToHandoverStartMs`. Any value ≠ 3.0 is a Stop for a ruling before the commit | Identical | No |
| 157 | P10 (AC17) | New probe verdict `probe_ideal_rrc_false_completes_with_applied_pscell_change` | None | ns-3 run at `UseIdealRrc=false` (echoed in the run's config record) exits 0; ≥ 1 applied ledger line matched by `check-c9-handover-trace.py` (HandoverStart and End rows, no orphan) | New | No |
| 158 | P10 (R-4, row 139 additive) | `ts_serving_cell_from_influx_test` (`install_patch_files/xApps/ts/src/ts_xapp/`) | Cases for gNBs 2 and 3 only (no hex letter) | Every row-139 case, plus a fixture copying `ranName` and the request part of s10 `e2mgr-node-10.json` (sha256 above, cp2-era bytes, labelled) and a D-R3-1 regenerated twin. (i) The xApp's own NodebHandler gives exactly {`0000000A10`, `0000000A00`} → `en_gnb_001_001_0000000a`. (ii) Latest point `e2NodeId` = that node with a prediction that names `0000000A10` gives serving `0000000A10`, and the order-free decision holds. (iii) A prediction that names only `0000000A00` gives none. (iv) `e2NodeId` `en_gnb_001_001_0000000A` (uppercase) gives none | Additive | No (uses the approved `%08X10` key form; rewrites no N5 predicate) |

Map renames (§1) are data, not check predicates, and have no rows. Their effect is judged by row 147 and by the unchanged map-driven M6/M7/p12 Influx = IPC checks.

## 8. Ordering and budget hazards (new against review §7)
1. P6 = agent rebuild + kpimon reinstall + M5–M7 (§1). Add these to the P6 gates and the cycle-1 budget.
2. Row 150 belongs to P7's harness commit, not P9's: the P7 ns-3 pin prints `hdr=3` while the judge expects 2.
3. P7 and P9 change ns-3, so `plan.md:72` adds M5 to the 7.2 table rows of both.
4. If the user picks Option A for P9, its T3 must be ruled before P9 code. The cp3 R3′ reference then moves on a new key.
5. P15's CGI expectation must come from the capture's E2 Setup X2 part. A meid literal there would make the row touch P5 (#9).

## Limitations
- 32.425 (the E-UTRA eNB rows) is not in Zotero, so eNB clauses are [U].
- 37.340's network-side termination figure (Fig 4.2.2-3) was not read as an image.
- The exact stats file and columns for row 149, the tshark ricActionID field name, and the CMake placement of suite (b) are [I].
- I did not classify all 38 measNames for row 147, only the P6/P9-relevant ones.

## Unresolved questions (for the user)
1. **Q1 (P6, spec).** QosFlow.PdcpPduVolumeDL is split-only and excludes DC (28.552 §5.1.3.6.1.1, pp.196–197). Accept "no QosFlow.PdcpPduVolumeDL on the en-gNB; the MAC value renamed in place to `ns3.du.macVolumeDl`" in place of Design's "report it from the PDCP calculator"?
2. **Q2 (P9, spec plus T3).** Option A (DRB.PdcpSduVolumeDL = 0 and the predictor reads DRB.PdcpSduVolumeX2DL; T3 and a contract check on "corrected counter") or Option B (same name with the via-SN value, a recorded interpretation)?
3. **Q3 (AC16 wording).** AC16 says "28.552 clause", but eNB rows are E-UTRA (32.425, per KPM §7.4.2.2 p.9). Should the lint accept 32.425 for `enb` rows, and can you add TS 32.425 to Zotero before P6?
4. **Q4 (P7).** Confirm 18-bit PDCP SN for every MC DRB, DL and UL. 12 bits would make the NR header indistinguishable from E-UTRA.
5. **Q5 (P7 (b)).** If the cp2 baseline shows ns-3 already loses SDUs at an SN change, is (b) judged on byte equality of the delivered SDUs only, with the loss recorded?
6. **Q6.** The fix for the pre-existing SN-wrap ordering bug (`lte-rlc-am.h:208`, `lte-enb-rrc.cc:1105`) goes inside P7's commit, because (c) requires it. Is that in scope under R8, or does it need its own commit and bisection slot?

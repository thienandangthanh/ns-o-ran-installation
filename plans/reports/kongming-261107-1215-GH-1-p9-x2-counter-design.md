# Kongming counsel: P9 design, the en-gNB X2 PDCP SDU volume counters (2026-11-07 12:15 KST)

Advisory only. Model: Opus 5.5 (the caller's override of the Fable routing). Pins read: harness 7ac51b00, ns-3 4318e43b, oran-interface 53253fe2, Testbed 254027ca. Every `file:line` below was read at those pins. The 3GPP and O-RAN texts were read from the Zotero PDFs with pdftotext: 28.552 V20.2.0 (`5SZUBP6M`, attachment RMU9VRW7), 28.552 V17.17.0 (`XU985K2J`, attachment WJPE6SBD) and E2SM-KPM v03.00 (`F82PYZVK`, attachment TH66CKUZ). The MCP Zotero tools were not loaded, so `zotero-cli path` located the files.

## TL;DR

- Count both X2 counters at the en-gNB's own X2-U boundary, not at the MN.
  - DL: every GTP-U `McForwardDownlinkData` PDU the en-gNB receives, counted for its local cell before the forward-map test.
  - UL: every GTP-U `McForwardUplinkData` PDU (a UL PDCP PDU) the en-gNB sends to the MN, counted in `EpcX2::DoReceiveMcPdcpSdu`.
  - Why: this single hook covers every DL path in one place: the MN split leg, the SDUs re-sent after an LTE→NR switch, the PDUs the S-SN redirects to the T-SN, and the S-SN's RLC-buffer forward. It counts at the instant the clause's owner sees the event.
  - What it fixes: counting at the MN's submission is 1 ms early. That is 4 slots at numerology 2, so it fails the R1 rule's 1-slot allowance and row 147's "its node owns the counted event".
  - This changes the counting sentence of user ruling Q2, so it is question Q-1 for the brainstorm.
- The interface contract below holds whichever way Q-1 is decided:
  - the audit v2 grammar;
  - the four IPC `cell.cuUp` keys;
  - map rows 36 and 37, appended (DRB.PdcpSduVolumeX2UL, then X2DL), INTEGER, Kbit;
  - rows 34 and 35 stay and report 0.

  Only one ns-3 function and the judge's truth set depend on Q-1, so the two implementers can start now.
- Two gaps that no registered row covers yet:
  - **R3′ single would go red at its first check.** Row 152 edits `r3p-scenario.json`, so its sha256 no longer matches the `scenarioSha256` that the committed `r3p-schedule.json` and `r3p-stage-a.json` carry, and `gate-r3p-ts-predictor.sh:128-129` requires a match. Row 152 must add both files: recompute the sha only, as rows 22–23 did.
  - **The live V3 runs reach no SN change.** They run NoAuto with no RIC, so they cannot exercise the S-SN→T-SN accounting that user ruling Q5 added.

## Reframed problem

What is being decided:
- the counting point and instant for two 3GPP counters at the en-gNB;
- the audit grammar that proves them;
- the judge that compares them;
- the gate route that runs that judge.

All of it must satisfy, at the same time:
- user ruling Q2: Option A, the X2 names, and 0 for the en-gNB's own PDCP volume;
- user ruling Q5: S-SN→T-SN forwarding is counted at the receiving cell;
- the R1 rule: exactly once on every path the runs reach, with only timing allowed to differ, by at most 1 slot;
- the registry rule of row 147: owning node, unit, type, value check.

Constraints: one fix per commit for P11's bisection, no switches, and every predicate change registered before code. Non-goals: per-UE X2 rows, eNB-side counters, the UM tail defect and the GTP aliasing defect (both are recorded follow-ups).

## 1. What 28.552 says (question 1)

The quotes come from V20.2.0, §5.1.2 "Performance measurements valid only for non-split gNB deployment scenario" (p.183). ns-3's en-gNB is non-split, as row 147 already records.

- **§5.1.2.1.1.2, DL Cell PDCP SDU Data Volume on X2 Interface (pp.183–184).**
  - a) "the Data Volume (amount of PDCP SDU bits) in the downlink delivered on X2 interface in DC-scenarios"; the unit is Mbit.
  - b) CC.
  - c) "obtained by counting the number of bits transferred in the downlink through X2 interface. The measurement is performed at the PDCP SDU level."
  - d) An integer in Mbit.
  - e) "DRB.PdcpSduVolumeX2DL, or DRB.PdcpSduVolumeX2DL_Filter", where the filter is PLMN, SNSSAI and QoS.
  - f) **NRCellCU.**
- **§5.1.2.1.2.2, UL Cell PDCP SDU Data Volume on X2 Interface (pp.185–186).** The same structure: "in the uplink delivered on X2 interface in NSA scenarios", "counting the number of bits transferred in the uplink through X2 interface ... at the PDCP SDU level", CC, integer Mbit, NRCellCU.
- **Annex A.25 (p.403).** "for split bearers, PDCP data is transferred between the MN and the SN via the MN-SN user plane interface ... the data volume transferred between MN and SN should be counted."
- **KPM v03.00 §7.9.1 (p.14)** lists both names, so the registry rule makes the unit Kbit: "DRB.PdcpSduVolumeX2DL_Filter ... clause 5.1.2.1.1.2 ... INTEGER Mbit → Kbit"; "DRB.PdcpSduVolumeX2UL_Filter ... clause 5.1.2.1.2.2 ... INTEGER Mbit → Kbit". Row 147's "Mbit unit" negative fixture therefore applies to the X2 rows too.
- **V17.17.0 (ETSI pp.121–122) is not identical,** so `v17Identical: false` for both. It gives only the `_Filter` form, its filter is PLMN and QoS without S-NSSAI, and it has no item i).

Answers:
- **Which node counts.** The object is NRCellCU, so the counter is the en-gNB cell's. For an MN-terminated split bearer, the en-gNB observes DL X2 bits when it receives them and UL X2 bits when it sends them.
- **DL truth for cell g:** the PDCP SDU bits of every DL PDCP PDU that cell g receives over X2-U.
- **UL truth for cell g:** the PDCP SDU bits of every UL PDCP PDU that cell g sends over X2-U to the MN. This is the UL data that g's RLC received from the UE and delivers to the MN-hosted PDCP.
- **SDU bits** = 8 × (PDU bytes − 2), the NR 12-bit data PDU header from row 150.

**The timing fact that forces Q-1.**
- `X2LinkDelay` defaults to 1 ms (`src/mmwave/helper/mmwave-point-to-point-epc-helper.cc:222-226`), and scenario-zero does not override it.
- The default numerology is 2 (`src/mmwave/model/mmwave-phy-mac-common.cc:48-52`), which gives 4 slots per millisecond (`:120-133`). The slot is 0.25 ms.
- So the MN's submission precedes the en-gNB's reception by 4 slots. The registry text allows "by at most 1 slot for a count".
- An MN-side counter therefore cannot get `holds: true` honestly. It would also fail row 147 (3), "its node owns the counted event", because the counting code would run on the eNB node.

## 2. Counting design (question 1)

### The paths, verified

- **MN split, X2 leg.** `McEnbPdcp::DoTransmitPdcpSduMmWave`: `m_txPdu` at `mc-enb-pdcp.cc:243`, then `SendMcPdcpPdu` at `:244`, then `EpcX2::DoSendMcPdcpPdu` with GTP type `McForwardDownlinkData` (`epc-x2.cc:1229-1262`).
- **MN split, LTE leg.** `DoTransmitPdcpSduLTE`, with `m_txPdu` at `:226`. The split is `perPckToLTE` = 0.5 by default (`:78`, `:282`).
- **LTE→NR re-entry.** At MC setup and at a switch, the LTE RLC buffer re-enters McEnbPdcp as SDUs (`lte-enb-rrc.cc:1483`, `:1903`, then `:971-980`). Each one gets a new SN, and a new X2-leg send if the split picks NR.
- **S-SN redirect.** At an SN change the S-SN calls `AddTeidToBeForwarded` (`lte-enb-rrc.cc:864-875`). Its EpcX2 then redirects every later X2-U arrival with that TEID to the T-SN (`epc-x2.cc:642`, `:671-677`). The redirect happens after the GTP header is removed (`:626`) and does not check the message type.
- **S-SN RLC-buffer forward.** `ForwardRlcBuffers(rlc, 0, teid, 0, 1, 0)` at `:905` calls `ForwardRlcPdu` (`:961`), which is mapped to `DoSendMcPdcpPdu` (`epc-x2-sap.h:859-861`).
  - These are whole PDCP PDUs with the header kept: `removePdcpHeader` is false (`lte-rlc-forwarding-buffer.h` doc at `:68-77`).
- **UL.** The SN's RLC (`lte-rlc-um-lowlat.cc:1311-1324`; the AM and UM RLCs do the same) calls `EpcX2::DoReceiveMcPdcpSdu` (`epc-x2.cc:1265-1298`), which sends GTP type `McForwardUplinkData`.
  - At the MN this arrives at `McEnbPdcp::DoReceiveMcPdcpPdu` (`mc-enb-pdcp.cc:349-352`), then `DoReceivePdu`, whose `m_rxPdu` fires at `:313`, before the D/C test.
- **SwitchToLte return.** The gNB's RLC buffer is sent back to the MN with `SendUeData` (`lte-enb-rrc.cc:2032`, `:956`).
  - This is DL data that the MN receives, so no en-gNB counts it. That follows Q5's rule that the receiving cell counts.
  - It is not UL either: it does not use the `McForwardUplinkData` type.

Every DL MC PDU that enters an en-gNB passes through `EpcX2::RecvFromX2uSocket` (`epc-x2.cc:597`), and every UL MC PDU that leaves one passes through `DoReceiveMcPdcpSdu`. No other entry or exit exists. That is why one hook per direction meets R1 by construction.

### Recommended (Option R; Q-1 asks the brainstorm to confirm it)

- **New EpcX2 trace `McDlPdcpPduRx`** with fields (localCellId, remoteCellId, gtpTeid, pduBytes).
  - It fires in `RecvFromX2uSocket` after `RemoveHeader(gtpu)` (`:626`) when the message type is `McForwardDownlinkData`, **before** the forward-map test at `:642`.
  - So a PDU that the S-SN redirects counts at the S-SN, where it arrived, and again at the T-SN when the redirected copy arrives there with remote = S-SN.
  - This is the "data the source SN forwards to target cell g ... counted at the receiving cell" of Q5. The S-SN count is Q2's "volume the MN sends over X2 to that cell".
- **New EpcX2 trace `McUlPdcpPduTx`** with fields (localCellId = `params.sourceCellId`, remoteCellId = `params.targetCellId`, gtpTeid, pduBytes). It fires in `DoReceiveMcPdcpSdu` after the socket-lookup assert and before `AddHeader(gtpu)` (`:1291`).
- **The counter.**
  - `MmWaveEnbNetDevice` subscribes to its own node's EpcX2 (`GetNode()->GetObject<EpcX2>()`; EpcX2 is aggregated at `mmwave-point-to-point-epc-helper.cc:363-365`). It subscribes where the CU-UP report is enabled and aborts if EpcX2 is absent.
  - It keeps (pdus, bytes) per direction for `localCellId == m_cellId`.
  - At every CU-UP report it computes `X2DL = (8 × (bytes − 2 × pdus) + 500) / 1000` kbit, does the same for UL, and resets the counts. The reset runs at every read in every mode, including the CSV branch.
  - The header size comes from `McEnbPdcp::DataPduHeader().GetSerializedSize()`, as at `:679` today. The NS_ASSERT `bytes >= 2 × pdus` is kept.
- **DRB.PdcpSduVolumeUL/DL = 0.**
  - The MN-hosted sums at `mmwave-enb-net-device.cc:673-711` are removed, together with their comment and assert.
  - Add a loud failure if any UE context of this en-gNB holds a DRB PDCP entity, so that a future SN-terminated bearer cannot silently report 0.
  - Leave the per-UE loop exactly as it is, including the `m_e2PdcpStatsCalculator` reads and the reset at `:817`. `DlE2PdcpStats.txt` and row 149's trace facts then stay identical to P7's.
- **Constraints:** no RandomVariable, no scheduled event and no file are added. N4's no-RV check guards this.

### If the brainstorm keeps the MN instant (Option M)

- ns-3 counts X2DL(g) from the McEnbPdcp X2-leg sends to g plus the forwarded `McDlPdcpPduRx` events at g whose remote is a gNB, and X2UL(g) from the MN's X2-leg receptions from g.
- This needs a cross-node accumulator, because McEnbPdcp lives on the eNB, plus three counting points.
- The registry entry must then list a 1 ms (4-slot) shift, which R1 does not allow. Without an explicit user-owned exception, the X2 rows would have to become `ns3.*`, which undoes Option A.
- The audit grammar below supports Option M unchanged; only the judge's truth set changes (section 4).

## 3. Interface contract between implementer A (simulator) and implementer B (harness)

### 3.1 IPC `sample.cell.cuUp` keys (en-gNB samples only)

| key | type | meaning |
|---|---|---|
| `DRB.PdcpSduVolumeUL` | JSON int | 0, always |
| `DRB.PdcpSduVolumeDL` | JSON int | 0, always |
| `DRB.PdcpSduVolumeX2UL` | JSON int | kbit of X2UL in (previous read, this read] |
| `DRB.PdcpSduVolumeX2DL` | JSON int | kbit of X2DL in (previous read, this read] |

- oran-interface: `FillCuUpValues(plmId, ul, dl, x2Ul, x2Dl)` adds the two X2 names with `AddCellValue<long>` (`helper/mmwave-indication-message-helper.cc:51-57`, and its header). Add no overload.
- The read instant is the sample's `simTimeNs`. The IPC `nodeId` is the ns-3 cellId, so audit `cellId` equals sample `nodeId`.

### 3.2 Metric map (Testbed `schema/metric-map.v1.json`)

- **Row 34** (`DRB.PdcpSduVolumeUL`, measId 34) and **row 35** (`DRB.PdcpSduVolumeDL`, measId 35): keep the name, order, measId, type and unit. Remove `pendingFix`. Rewrite `origin` to name the zero and its source.
- **Append** after file line 60:
  - order 36, measId 36: `DRB.PdcpSduVolumeX2UL`, INTEGER, scope sample, src `/cell/cuUp/DRB.PdcpSduVolumeX2UL`, xform none, unit `Kbit`, clause `3GPP TS 28.552 V20.2.0 §5.1.2.1.2.2`, layer PDCP, legacyName null.
  - order 37, measId 37: `DRB.PdcpSduVolumeX2DL`, with the same fields and clause `§5.1.2.1.1.2`.
  - Both `origin` fields name ns-3@<P9 sha> `src/lte/model/epc-x2.cc:<line>` and `src/mmwave/model/mmwave-enb-net-device.cc:<line>`, and oran-interface@<P9 sha> at its line.
- UL comes before DL to mirror rows 34 and 35. Cell measId = order, append-only, as the map doc requires. The UE list and the eNB lists are unchanged.
- Remove the doc line about `pendingFix`.

### 3.3 Audit v2 (scenario-zero stdout, only with `enableUlTraffic`; uloff prints no `N4AUDIT` line)

```
N4AUDIT v2 hdr=<H> class=<C>
N4AUDIT dltx <tNs> <nodeId> <cellId> <imsi> <lcid> <pduBytes> <leg>
N4AUDIT ulrx <tNs> <nodeId> <cellId> <imsi> <lcid> <pduBytes> <delayNs> <leg>
N4AUDIT x2dl <tNs> <nodeId> <cellId> <srcCellId> <teid> <pduBytes>
N4AUDIT x2ul <tNs> <nodeId> <cellId> <dstCellId> <teid> <pduBytes>
N4AUDIT end connected=<n> present=<m> missing=<k>
```

**Token counts, split on single spaces:** header 4, dltx 9, ulrx 10, x2dl 8, x2ul 8, end 5. Every number is a base-10 non-negative integer. `tNs` is `Simulator::Now()` in ns, and `nodeId` is the `/NodeList` index.

**Header.**
- The meaning is v1's, with the version token `v2`. It is printed once, at the first DRB PDCP connection, from that entity's own header object.
- It reads `hdr=2 class=ns3::NrPdcpHeader`, so row 150's predicate is unchanged.

**dltx and ulrx** come from the MN's McEnbPdcp, connected per UE as today (`scenario-zero.cc:104-124`). `cellId` is the RRC's cell, the MN.
- **dltx** comes from a new McEnbPdcp trace `TxPduLeg` with fields (rnti, lcid, pduBytes, legCellId), fired next to `m_txPdu`:
  - in `DoTransmitPdcpSduLTE`, leg = 0;
  - in `DoTransmitPdcpSduMmWave`, leg = `m_ueDataParams.targetCellId`.
- **ulrx** comes from a new trace `RxPduLeg` with fields (rnti, lcid, pduBytes, delayNs, legCellId), fired next to `m_rxPdu`:
  - leg = 0 when the PDU came through the LTE RLC SAP;
  - leg = `params.sourceCellId` when it came through `DoReceiveMcPdcpPdu`. That is the SN cell, set at `epc-x2.cc:636-640`.
  - Use one shared receive body, `ReceivePdu(p, leg)`, and keep `DoReceivePdu(p)`'s behaviour.
- The audit connects `TxPduLeg` and `RxPduLeg` instead of `TxPDU` and `RxPDU`, and aborts if either connection fails. Every DRB PDCP must be an McEnbPdcp.
- Do not change the signatures of the existing `TxPDU` and `RxPDU`: `Config::ConnectFailSafe` in the bearer-stats connector would silently drop a mismatched callback.

**x2dl and x2ul** come from the two EpcX2 traces of section 2.
- Connect them once at setup with `Config::ConnectFailSafe("/NodeList/*/$ns3::EpcX2/McDlPdcpPduRx")` and `.../McUlPdcpPduTx`, take nodeId from the context, and abort on false.
- In x2dl, `cellId` is the receiving en-gNB cell and `srcCellId` the X2 remote cell: the MN's cell means the MN leg, and a gNB cell means S-SN→T-SN forwarded.
- In x2ul, `cellId` is the sending en-gNB cell and `dstCellId` the MN's cell.
- `pduBytes` is the PDCP PDU, header included, GTP-U excluded.

**The forwarded mark is `srcCellId`.** The judge classifies it. The MN cells M are the cellIds of all dltx and ulrx lines; the gNB cells G are the expected gNB nodes. An x2dl is forwarded iff its src ∈ G.

**The end line** is unchanged.

**Parsers that must change** (B):
- `check-pdcp-volume-totals.py` `load_audit` (`:42-58`);
- `gate-n4-ul-metric.sh:129`, `cal_ok`, `^N4AUDIT v1` → `^N4AUDIT v2`;
- `n4-run-byte-identity.py:54`, HDR `b"N4AUDIT v1 hdr="` → `v2`, and its self-test strings (`:351`, `:419`).

`tools/e2-evidence/trace-facts.py` does not parse the audit: no `N4AUDIT` string appears under `tools/`.

**Is "bytes − header" right for forwarded data?**
- Yes for every whole PDU. The MN's sends, the S-SN redirect (the MN's PDU untouched) and the RLC-buffer forward (PDCP PDUs with the header kept) all carry the 2-octet header.
- The exception is pre-existing. When the head of an `LteRlcUmLowLat` TX buffer is the tail of a partly sent SDU, `DeliverRlcForwardingBuffer` either drops it (D/C = 0) or forwards it as a PDU (D/C = 1). In the second case 2 payload octets are subtracted as if they were a header, so the count is 16 bits low per forwarded tail.
- This belongs to the "RLC UM tail re-submission" follow-up in phase-10. Whether it counts as an R1 gap is Q-2.

## 4. Judge redesign for row 151 (question 4)

The judge keeps A0, A2 and A3 as they are. A2 and A3 apply over the dltx and ulrx lines only.

| conjunct | rule |
|---|---|
| A0 | Unchanged: gNB traces = nodes 2..1+n, every seq 0..N−1 once |
| A1 | Header `v2 hdr=2 class=ns3::NrPdcpHeader`; end line with connected == present and missing == 0; **every `N4AUDIT` line matches exactly one of the six forms** (count `malformedAuditLines`; a v1 header fails) |
| A4 | **Per cell, no pooling.** For each gNB sample (g, s) with read instant t(g,s): truthDL = Σ 8 × (pduBytes − H) over x2dl with cellId g and t(g,s−1) < tNs < t(g,s), with t(g,−1) = −∞; truthUL the same over x2ul. Pass iff \|1000 × ctr − truth\| ≤ 500 bits per sample and key, and per read instant \|Σ_g 1000 × ctr − Σ_g truth\| ≤ 1 kbit × (number of cells). Both counters must be ints |
| Ties | An x2 event at cell g with tNs equal to any read instant of g fails (`ties`) |
| Residual | x2 events at g after g's last read are residual, allowed only when that read is the run's last read instant (A0 makes it so) |
| Unknown | x2dl/x2ul at a cell ∉ G, an x2dl src ∉ M ∪ G or equal to its own cell, an x2ul dst ∉ M, or a dltx/ulrx leg ∉ {0} ∪ G fails (`badCellRefs`) |
| A5 | Every dltx, ulrx, x2dl and x2ul has pduBytes ≥ H + 1; every ulrx with lcid 3 has an SDU > 40 B |
| A6 | ≥ 1 dltx with lcid 3 and leg 0, and ≥ 1 with lcid 3 and leg ≠ 0 (row 151). **Recommended addition:** ≥ 1 x2ul, so X2UL is not vacuous |
| A7 | Every gNB sample has `DRB.PdcpSduVolumeUL` and `DRB.PdcpSduVolumeDL` as ints equal to 0 |
| A8 (recommended, new) | **X2 conservation.** For every g ∈ G: the multiset of dltx pduBytes with leg g equals the multiset of x2dl pduBytes at g with src ∈ M, and the multiset of x2ul pduBytes from g equals the multiset of ulrx pduBytes with leg g. MN-side events with tNs > simTimeNs − 2 ms are excluded (in flight at the stop); gNB-side events are never excluded |

**Removed:** the UE-list ownership, the `owners[0]` truth (`:152-153`), the union-find pooling (`:160-192`), the `overlaps` field and the "UE vanishes from every gNB map" rule. The counter no longer depends on UE maps, so none of these has an object left.

**Why A8.** It is the only conjunct that ties the en-gNB's events to independent MN PDCP events. It catches an X2 hook placed after the redirect, or on the wrong message type, for the MN leg. In the V3 runs it cannot see the redirect and forward paths, because those runs make no SN change (Q-3).

**Truth under Option M** (only if Q-1 is decided that way): truthDL(g) = dltx with leg g at the MN's instant plus x2dl at g with src ∈ G; truthUL(g) = ulrx with leg g at the MN's instant. Everything else is the same.

**Verdict fields.**
- Keep: `a0`–`a5`, `pass`, `hdr`, `hdrClass`, `end`, `gnbSamples`, `perCellMaxErrBits`, `periodSumMaxErrKbit`, `ties`, `residualBits`, `nonIntCounters`.
- Add: `a6`, `a7`, `a8`, `auditVersion`, `mnEvents`, `x2Events`, `legCounts` ({`lte`, `x2`}), `x2ulEvents`, `forwardedEvents`, `forwardedBits`, `badCellRefs`, `malformedAuditLines`, `ownPdcpNonZeroSamples`, and `conservation` ({`dlMnOnly`, `dlGnbOnly`, `ulGnbOnly`, `ulMnOnly`}).
- Drop: `overlaps` and `unverifiedResidualBits`.

**Self-test fixtures.** The `_fixture` helper must write two gNB traces (nodes 2 and 3) with all four keys.
- Pass:
  - two cells, both DL legs, x2ul, zeros;
  - plus a forwarded x2dl (src 2 at cell 3) inside cell 3's X2DL;
  - residual after the final read.
- Fail, as row 151 requires:
  - the X2DL counter equals all MN dltx volume of both legs;
  - X2DL swapped between cells 2 and 3 with the same sum;
  - `DRB.PdcpSduVolumeDL` = 1 on one gNB sample.
- Fail, recommended:
  - only leg-0 dltx;
  - only X2-leg dltx;
  - no x2ul (if A6's addition is registered);
  - a v1 header;
  - a forwarded event left out of the T-SN's counter;
  - a forwarded event credited to the source cell;
  - x2dl at the eNB cell;
  - a dltx with leg 3 and no x2dl at 3 (A8);
  - an x2dl from the MN with no dltx (A8);
  - an x2ul with no matching ulrx (A8);
  - a tie on an x2dl;
  - a dltx with an extra token;
  - `DRB.PdcpSduVolumeUL` ≠ 0;
  - a float X2 counter;
  - X2UL off by 1 kbit.
- Kept from today: missing gNB cell, truncated tail, duplicate seq, unexpected gNB node, unconnected PDCP, no end line, header size 3, class LtePdcpHeader, header line without a class, header with a trailing field, a UL SDU of 40 B, a PDU at two RRCs.

## 5. Row 152 edits and the row 161 route (question 5)

**The row 152 list as registered:**
- `r3p-scenario.json` `:2` (the citation becomes §5.1.2.1.1.2), `:8-10` (`field` and `ipc` → X2DL), `:13` (`formula.dl`), `:29` (the transform);
- `r3p-predictor.py:6`;
- `n6-fixtures.py:10`;
- `r3p-checks-fixtures.py:15`;
- `digest-run.py:64`;
- `check-n4-v5-windows.py:29-30`, plus its doc line `:7`;
- `n4-drop-selftest.py:17`.

**Missing from row 152; register them before code:**
- **(a) Recompute the sha in `r3p-schedule.json:2` and `r3p-stage-a.json:58`.**
  - `scenarioSha256` is today `392feefc…`, which equals `sha256(r3p-scenario.json)`. Recompute it from the amended scenario. This is a pure T, like rows 22–23; every other byte stays literal.
  - The `expectedAnswer` kbit values (for example 133936 and 66976) are the formation dry run's numbers under the old counter. They are not compared live: only the decisions are (`r3p-prepare.py:10`, `r3p-checks.py:178`).
  - If a scheduled decision flips, the run is red and that is a PAUSE T3. It is never a re-formation.
- **(b) Extend `digest-run.py --n4-ul-off-drop` to the four gNB CU-UP keys** instead of re-pointing it.
  - A plain re-point would leave `DRB.PdcpSduVolumeUL/DL` undropped and unchecked.
  - The new rule: a present run carries all four keys as ints, with UL == 0, DL == 0, X2UL == 0, and X2DL > 0 in at least one sample of every gNB that ever lists a UE. All four are then dropped.
  - New `n4-drop-selftest` cases: DL ≠ 0 fails, and a missing X2 key fails.
- **(c) The comment at `gate-r3p-ts-predictor.sh:3`.** No predicate changes.
- **(d) A P11 consequence to record now.** `m9-transform.py`'s T (`:15-27`) maps the M9 files onto the pre-P9 scenario, so `--reference-transform` at cp3 needs T extended or that comparison retired.

**The R3′ risk.**
- In the committed schedule, h1 (IMSI 1, step 30) sees gNB2 : gNB3 = 133936 : 66976, which is 4 UEs against 2 at 33488 kbit per UE per 1.6 s. The decision rule needs 10 × other > 11 × serving.
- P9 halves both cells through the 0.5 split. P9 draws no new random number, so the split is the same realization. The binomial noise per window is about 1 %, and the ratio stays about 2.0.
- n1 (ratio 0.5) and m1 (5 UEs against 1) keep their "none".
- The Q5 burst at h1 lands at the T-SN around seq 30–31, outside m1's window [35, 50].
- I expect the scheduled decisions to reproduce. This is a belief, computed from the schedule's numbers, not a run.

**The row 161 route, `gate-n4-ul-metric.sh --part v3`.**
- Add `v3` to the part list. Like determinism and identity, it takes the UL pattern and RngRun from `rung-config.json` and refuses `--ul-pattern` and `--ref`.
- Checks, reusing the full mode's names:
  - `n4_build_tools_present`, `n4_ns3_binary_located_at_pins`;
  - `n4_uloff_free_run`, `n4_uloff_emitter_at_pins`, `n4_v2_uloff_prints_no_audit`;
  - `n4_ulon_free_run`, `n4_ulon_emitter_at_pins`;
  - `n4_v3_counters_equal_the_pdcp_audit`, `n4_ul_flag_moves_no_random_draw`, `n4_no_stray_process`.
- Plus an informational record `n4_v3_reference_equality_not_evaluated` (pass true) and the fact `notEvaluated` = [`n4_reference_is_a_pre_n4_free_run`, `n4_v2_uloff_equals_reference_after_the_strict_drop`, `n4_v2_same_trace_file_names`].
- Fix the key list that `v3()` prints (`:417-420`): `overlaps` would raise a KeyError.
- The chain driver gets step 14, `n4|gate-n4-ul-metric.sh|3600|--part v3` (`evidence/p10-chain/p10-gate-chain.sh:80-96`). The driver's step id stays `n4`.

## 6. Gate impacts and unregistered checks (question 6)

- **N4 identity (step 13).**
  - Do not run it after P9. Against `reference/n4-sn-wrap`, the stdout body (audit v2, x2 lines, leg tokens) and every gNB IPC sample (the zeros and two new keys) differ by design.
  - Record in the P9 phase record that identity is not a P9 gate and that the determinism reference is re-banked at cp3 (P11, row 161).
  - Update `n4-run-byte-identity.py`'s HDR to v2 in P9's harness commit, so that the cp3 re-bank splits the right line.
- **Full N4 mode.** Its V2 is red against K19 from the UB fix onward, and P9 does not change that. It is not in the M10 step set.
- **M5.** `ranfunc-check.py` and the install lint are map-driven. They need the map at 37 cell names and a lint with no pending rows.
- **M6 and M7.** The map-driven Influx = IPC checks pick up rows 36 and 37 automatically, because kpimon takes gNB names from the RAN function. kpimon reinstalls because the map and the registry are on its stale list (`kpimon.sh:36-39`). Row 149's facts stay identical if the per-UE loop is untouched. No M6 or M7 check names `DRB.PdcpSduVolumeDL`.
- **Influx.** `cellMetrics` gains two long fields. `DRB.PdcpSduVolumeUL/DL` stay, at 0.
- **R3′.** Single mode compares no reference. The references (`reference/r3p*`, `m9-r3p-raw`) are re-banked at cp3. The schedule sha is item (a) above.
- **KPM T/T golden.**
  - Regenerate `fixtures/kpm-tt-golden-gnb2-seq26-35.txt` in the Testbed commit. Keep the input `ipc-samples-gnb2-seq26-35.jsonl` unchanged, so rows 36 and 37 encode noValue.
  - Expected result: the header and UE pieces are byte-identical, and each cell piece changes only by two appended measInfo items and records. APER lengths shift, so prove this by decoding (for example with `tools/asn1-indep`), not by a byte-suffix argument.
  - Also check that the k20 worst-case message still fits `E2_MAX_E2SM_BYTES`.
  - The test is not gated, so run it once in the agent image and quote its output in the commit message.
- **p12 at cp3.** The cell list length changes. P15 re-baselines p12 after P9 anyway.
- **docs.** `docs/system-architecture-l-release.md:181` and the R3′ paragraph at `:185` name the old counter and the "recorded deviation P9". Update them in a docs follow-up commit.

**Checks that need a ledger entry before code** (one docs commit):

1. **Row 151, amended:**
   - the outcome of Q-1 (truth instants at the en-gNB's X2-U boundary);
   - the exact v2 grammar and A1's strict line parse;
   - A4 over the x2 lines, with pooling and UE-list ownership removed;
   - the classification rules (M, G, forwarded = src ∈ G, `badCellRefs`);
   - A6's x2ul addition and A8, if adopted;
   - the fixture list;
   - the redirect counted at the S-SN and at the T-SN, stated as an interpretation;
   - a disclosure that the V3 route makes no SN change.
2. **Row 152, amended:** items (a)–(d) of section 5.
3. **Row 147 note.** P9's commit removes the (8) exception together with the last pending rows: any `pendingFix` field becomes a finding, `--require-no-pending` and `PENDING_ALLOWED` (`lint-metric-map.py:49-53`, `:104`, `:252-275`) are removed, and the self-test's pending fixtures are replaced by "a row carrying pendingFix fails". This is strictly stronger, but the fixture set changes.
4. **Row 150 note.** The audit version token is v2 in the three parsers. A v1-header fixture now fails. The class and size conjuncts are unchanged.
5. **Row 161 detail:** the pattern and RngRun come from rung-config; the check names; the not-evaluated record; chain step 14.
6. **New fixture row** for the KPM golden regeneration, like row 144: no predicate change, only the fixture, with the decode-level diff as evidence.
7. **Only if Q-3 = (b):** a new row for the ns-3 suite `epc-x2-mc-pdcp-volume` and the check `m4_ns3_epc_x2_mc_pdcp_volume_suite_passes`.

## 7. Commit plan (question 7)

1. **Harness docs commit:** the ledger items 1–7, the Q-1–Q-3 rulings, and the phase-10 P9 gate line with chain step 14.
2. **ns-3 fork commit:** EpcX2 traces, McEnbPdcp leg traces with `ReceivePdu(p, leg)`, the gNB counter and the zeros, audit v2, and the Q-3 (b) suite if chosen. Example message: `fix(mmwave): count the en-gNB cell's PDCP SDU volume on X2 and report zero for its own PDCP`.
3. **oran-interface fork commit:** `FillCuUpValues` with the two X2 values. It does not build against the old ns-3, and that is fine because only the harness pin moves the pair. Example: `fix(e2): carry the en-gNB X2 PDCP SDU volumes in the CU-UP cell report`.
4. **Testbed fork commit**, which cites the SHAs from 2 and 3: the map, the registry, the lint and its self-test, and the golden. Example: `fix(ns3-e2-agent): map the en-gNB X2 PDCP SDU volumes and hold its own PDCP volumes at zero`.
5. **Harness commit, the bisection point:**
   - `pins.conf` with all three SHAs;
   - the judge;
   - `--part v3` and `cal_ok`;
   - the HDR in `n4-run-byte-identity`;
   - every row-152 file, including the schedule and stage-A sha;
   - chain step 14.

   Example: `fix(gates): judge the en-gNB X2 PDCP SDU volumes per cell and pin the X2 counter change`.
6. After the green chain: the phase record, the raw archive, and the docs follow-up commit.

Commits 2–4 are reachable only through the pin in 5. That makes P9 one bisection step, like the D-R3-1 pair. The new judge fails on the old pins and the old judge fails on the new ones, so neither can land apart from the pin.

**Chain:** `p10-gate-chain.sh <sha5> 2 7` (M4–M7, i0, i2), then `14 14` (n4 v3), then `10 10` (r3p single), each with a fresh log dir. N4 v3 runs before R3′ so that a counter red does not waste an R3′ run. Re-read `df` first: 41 GiB were free after P7; the kpimon build guard is 34 GiB.

## 8. Briefs for the two implementers

**A (simulator, Testbed):**
- Owns: `epc-x2.{h,cc}`, `mc-enb-pdcp.{h,cc}`, `mmwave-enb-net-device.{h,cc}`, `scratch/scenario-zero.cc` (the grammar doc block at `:46-58` too), the optional `src/lte/test/` suite with its CMake entry, the oran-interface helper, the map, the registry, the lint and its self-test, and the golden.
- Must:
  - count at the en-gNB's X2-U boundary (pending Q-1);
  - fire `McDlPdcpPduRx` before `:642`;
  - leave the per-UE loop and the stats calculators untouched;
  - name no `LtePdcpHeader` on an MC path (row 148's source lint);
  - add no RNG draw and no event.
- Registry entries for X2DL and X2UL:
  - pages [183, 184] and [185, 186]; check them with `zotero-cli read`;
  - NRCellCU, NR, PDCP, Kbit with KPM p.14 as the unit source, INTEGER;
  - owningNode [gnb]; countingEvent quoted from item c);
  - splitOnly false, dcExcluded false, perUeAllowed true (KPM §7.9 p.13);
  - nameForms total; v17Identical false;
  - valueChecks: holds true, gaps [], residuals [];
  - interpretations: the X2-U boundary, header subtraction, the redirect counted twice per Q5, the UM tail per Q-2's outcome, the bare name;
  - reAudit: an SN-terminated bearer, AM DRBs, Xn;
  - int32 bound: (X2 links into the cell) × 100 Gb/s × period / 1000 kbit.
- Rows 34 and 35 in the registry: holds true, value 0, reason "no DRB PDCP entity at the en-gNB (37.340 §4.2.2)".
- Host checks: the shipped lint has 0 findings, the self-test passes, and `kpm-report-period-test: ok` in the agent image.

**B (harness):**
- Owns: `check-pdcp-volume-totals.py`, `gate-n4-ul-metric.sh`, `n4-run-byte-identity.py`, the row-152 files with the sha recompute, `digest-run.py` with `n4-drop-selftest.py`, the comment in `gate-r3p-ts-predictor.sh`, and the chain driver.
- Works from section 3.3 alone, with fixtures and no simulator.
- Must: drop pooling entirely; key truth on audit `cellId` = sample `nodeId`; never filter x2 lines by LCID; leave `pins.conf` to the controller.
- Done when: `lint.sh` passes, including the new judge's self-test with all section 4 fixtures, `n4-drop-selftest`, the byte-identity self-test, the V5 self-test and the r3p self-tests.

## What to avoid

- Do not count at the MN "because the ruling says so" without settling Q-1. The 4-slot shift fails R1, and the brainstorm, not the implementer, should decide it.
- Do not reuse EpcX2's `RxPDU` trace for counting. It fires for every X2-U packet, including GTP-U bytes, before the message type is known. It also feeds `X2Stats.txt`, which the no-RV check compares.
- Do not change the existing `TxPDU`/`RxPDU` signatures. Do not hook the RLC's `SendMcPdcpSdu`: it misses the S-SN arrivals of redirected PDUs.
- Do not "re-point" `digest-run`'s two keys, and do not re-form the R3′ schedule from new dry runs. Recompute the sha and let the live decisions judge the X2 counter.
- Do not keep the pending machinery with an empty set. That is a dormant legacy mode.
- Do not run `--part identity` at the P9 pins, and do not read its red as a P9 failure.

## Alternatives and trade-offs

- **Option M (the MN instant, as Q2's text says).** Faithful to the letter of the ruling. But it needs a cross-node accumulator and three counting points, and it fails R1 and row 147 (3) unless the user owns an exception. Weaker on every axis but the letter of the ruling.
- **Counters inside EpcX2 with a getter**, instead of traces plus device-side counting. Equivalent behaviour, but it puts reporting state into the X2 model. The trace approach keeps one event source for both the counter and the audit, as the PDCP stats already do.
- **A scripted SN change in the V3 runs**, through `controlFileName=ts_actions_for_ns3.csv` (`lte-enb-net-device.cc:147-190`). That would give live forwarded events. But the file is re-applied at every eNB read, has no time gate ("TODO adapt to the scheduling"), and changes the V3 scenario. Riskier than an EpcX2 unit suite.

## Success metrics

- The lint has 0 findings and no `pendingFix` anywhere. Rows 36 and 37 pass through a value check that holds.
- M4–M7 are green. M6 Influx = IPC holds on 37 cell rows. Row 149's counts equal P7's (M6 201/93, M7 3557/1819).
- n4 `--part v3` is green:
  - a0–a8 true;
  - `perCellMaxErrBits` ≤ 500 and `ties` 0;
  - `legCounts.lte` > 0, `legCounts.x2` > 0 and `x2ulEvents` > 0;
  - every conservation count is 0;
  - `forwardedEvents` = 0, reported as the disclosed limit;
  - `notEvaluated` recorded.
- R3′ single is green with the scheduled decisions reproduced: n1 none, h1 handover applied, m1 none.
- The golden's header and UE pieces are identical, and the decode diff shows only two appended cell items.

## Assumptions

- **High.** The X2-U delay is 1 ms and numerology 2 gives a 0.25 ms slot. Verified at the cited lines; scenario-zero overrides neither.
- **High.** One cell per gNB node. The filter on `localCellId == m_cellId` covers the other case anyway.
- **High.** The V3 route makes no SN change: NoAuto and no RIC (`gate-n4-ul-metric.sh:71`; rung-config `handoverMode`). This comes from the configuration, not from a run.
- **High.** The clients stop at simTime − 0.1 s (`scenario-zero.cc:737`, `:744`), so nothing is in flight at the stop. A8's 2 ms exclusion is a safety margin.
- **Medium-high.** The R3′ decisions survive. Computed from the schedule's numbers; a red here is the hazard line's PAUSE T3.
- **Medium.** The KPM golden test is not gated. Taken from memory and the phase text; not checked against the M5 script.

## Unresolved questions for the brainstorm

- **Q-1 (before code). Counting point.** The en-gNB's X2-U boundary, with truth at the en-gNB's reception (DL) and send (UL), against Q2's sentence "at the MN, each PDCP PDU submitted".
  - Recommended: the en-gNB boundary.
  - What would flip it: a reading that the DL clause event is the MN's X2 submission and that its 1 ms shift is not a "counting instant" in R1's sense. That reading would also have to pass row 147 (3).
- **Q-2. The forwarded RLC UM tail.** Its 2 payload octets are subtracted as a header, 16 bits low per forwarded tail on a path the R3′ runs reach. Is that an R1 "gap" or an interpretation?
  - Recommended: an interpretation that sits with the UM-tail follow-up. The counter counts exactly what the model transfers as PDCP PDUs, once per receiving cell.
  - If it is ruled a gap: either the tail forwarding is fixed first, as its own commit before P9, or the X2 rows cannot keep their 3GPP names.
- **Q-3. Evidence for the redirect and forward paths,** which the V3 runs never reach and A8 cannot see.
  - (a) Disclose it, and rely on the single hook plus the judge fixtures.
  - (b) Add a small ns-3 suite `epc-x2-mc-pdcp-volume`. It would cover A→B normal, A→B redirected to C (counted at B and at C), B→C direct, and the UL send at B, with an RLC user stub at C. It would be gate-visible at M4, with its own row, as rows 148, 159 and 160 did.
  - Recommended: (b), because R3′ reaches these paths and only a test or code reading can see them.

Status: DONE_WITH_CONCERNS
Summary: Design and contract are complete. Count both X2 counters at the en-gNB's X2-U boundary. Audit v2 adds leg tokens and x2dl/x2ul lines, the judge works per cell with A6–A8, rows 36 and 37 are appended, and P9 lands as one pin commit.
Concerns: Q-1 revises a user-ruled counting sentence, because the MN instant breaks R1 by 4 slots. Row 152 misses the r3p schedule and stage-A sha recompute, without which R3′ single goes red at its first check. The V3 route never exercises the Q5 forwarding paths.

# kongming counsel: P6 step 1, the SDU-header rule and the double-count design

2026-10-27, about 02:45 KST. This is the P6 step 1 consult ("kongming before code"). It is advice only and **not user approval**. Model: Opus 5.5 (the user's routing for kongming).

**Inputs**
- Plan files: `goal-packet.md` (In scope 4, Out of scope, "never weaken a test"), `plan.md` (invariants), `phase-06` including K4, K13, K17–K20 and K25, and my `kongming-261027-0145` report (D1, D2, the V2 drop option).
- The user's decision record `plans/reports/decisions-261022-2013-…` §4 and §5.
- Sources at the pins: ns-3 `962fabc7` and oran-interface `63155c49`, read from fresh shallow clones in my scratchpad. The clones in this worktree are at the older `ace32168` and `438a839`, so the phase file's line numbers are stale. I also read `ric-app-qp@47a35ca` through `gh api`, and the harness at `a87cde7`.
- Evidence: `evidence/r2/20261026T143406Z/runs/{c8free,live1,live2}` (`ns3run/`, `trace/`).
- I did not touch the VM.

## TL;DR
1. **SDU rule.** Per gNB cell and per period, take the cell's UE map and the shared E2PDCP calculator at lcid 3:
   - SDU bits = Σ 8·(B − h·N), where B is the PDU bytes and N the PDU count (UL from RxPDU, DL from TxPDU).
   - kbit = (bits + 500) / 1000, rounded once per cell, for both UL and DL.
   - h = `LtePdcpHeader::GetSerializedSize()`, which is a constant 2 in this ns-3. There is only one SN length (12 bits) for every direction and bearer, so the SN length cannot differ between UL and DL or between bearers.
2. **There is no gNB PDCP.** For every EN-DC UE, the DRB PDCP is the MN's `McEnbPdcp` on the LTE eNB. The gNB holds only RLC and forwards UL to the MN over X2.
   - Both counters are therefore "the MN-PDCP volume of the UEs in this gNB's UE map". That is "where the DL counter is taken", as the user's record directed (`decisions-261022-2013` §4).
   - It contradicts the phase Context, and it reports MN-hosted volume under the en-gNB NRCellCU. That is a standards classification the user has not made (widen P7, or a new P9).
   - **Don't push or pin the counter until the user rules.** Put the question in the next PAUSE. If no other pause comes first, print PAUSE T4 before the first push of the counter.
3. **V3 cannot run literally.** There is no gNB PDCP, and there is no PDCP trace file aligned with the read window.
   - The E2 rows are snapshots taken 0.8 ms before the gNB reads.
   - `DlPdcpStats.txt` and `UlPdcpStats.txt` hold only the last epoch.
   - Use a per-PDU audit, gated by the flag, on the PDCP objects themselves. It prints to stdout, so there is no new trace file. Judge each cell within ±0.5 kbit, and also check the literal "Σ over cells within ±1 kbit per cell".
4. **V5.** Do **not** pre-register "≥ 2 distinct values of each series".
   - The gNB-cell DL series is constant in almost every window: exactly 200 PDUs per UE per 100 ms, and the UE set never changes in a NoAuto, −1000 dB, null-control run. That clause would fail by construction.
   - K17 replaced V5. Pre-register QP's own `constant()` == False, plus no all-zero column, plus int types, over every complete 16-seq window of each gNB cell.
5. **UL traffic.**
   - Primary: constant-rate UL with the DL parameters (1280 B every 500 µs per UE), which saturates the uplink.
   - Fallback, pre-registered now: a deterministic, below-capacity size pattern.
   - Neither creates a RandomVariable. Validate on the V3 free-run in the R3 config before the dump.

## Reframed problem
The question behind step 1 is: what number must ns-3 emit, from which quantities, and how can V2, V3 and V5 prove it without weakening a test or moving the flag-off path?
- **Requirements:**
  - INTEGER kbit, PDCP SDU level, per gNB cell, appended to the gNB cuUp section;
  - the flag-off path unchanged except the two IPC keys;
  - no RandomVariable created by the UL flag;
  - V3 measures double counting;
  - V5 is pre-registered before the dump.
- **Non-goals:** changing the DL traffic, QP prediction quality, the LTE cell's legacy fields, and any ns-3 PDCP realism fix (P7, post-M9).

## Verified facts behind the answers
| # | Fact | Where |
|---|---|---|
| F1 | **The PDCP is at the MN.** The gNB's `RecvRlcSetupRequest` creates RLC only. Its target is "the LTE cell", and its upper side is the X2 RLC provider. UL arrives at the MN as `McForwardUplinkData` through `m_x2PdcpUserMap[teid]`, then goes `DoReceiveMcPdcpPdu` → `DoReceivePdu`. The secondary-HO `HandoverEndOk` fires at the target gNB, where the UE has no `DataRadioBearerMap`. Evidence: `DlE2PdcpStats.txt` has CellId 1 (the LTE cell) in all 588 rows of c8free, live1 and live2 | `lte-enb-rrc.cc:1453-1515`, `:1479`, `:1874`; `epc-x2.cc:660-665`; `mc-enb-pdcp.cc:296-337` |
| F2 | **One calculator serves all gNBs, and the LTE eNB has its own.** Both calculators receive the same MN events. Each is read and reset by one device class, so there is no cross-reset. The cellId stored per IMSI is the last writer, which is always 1 here | `mmwave-helper.cc:2222`, `:2525`, `:3193-3208`; connector `:1187-1201`; calculator `:250` |
| F3 | **Header.** `GetSerializedSize` returns 2. The SN is masked to 12 bits, and the header is serialized as D/C, three zero bits, then a 12-bit SN. The UE (UL) and the MN use the same class; the max SN is 4095. In the traces the PDU is 1310 B: a 1308 B SDU plus 2 | `lte-pdcp-header.cc:57`, `:95-108`; `mc-ue-pdcp.cc:197-209`; `mc-enb-pdcp.cc:247-259`, `:313-314`; `mc-enb-pdcp.h:235` |
| F4 | **Count points.** DL TxPDU fires after `AddHeader` (`:259`): at `:221` on the LTE leg, at `:238` on the NR leg. UL RxPDU fires at `:308`, before `RemoveHeader`. An SDU reaches the upper layer only if it is larger than 40 B | `mc-enb-pdcp.cc:221-238`, `:308-329` |
| F5 | **Trace files.** E2-calculator rows are written at EndEpoch, every 0.1 s, without a reset. The gNB reads at 0.8 ms + k·0.1 s. So each row covers 99.2 ms (198 PDUs per UE), not the 100 ms read window (200). For non-E2 calculators, EndEpoch resets **before** it writes, so `DlPdcpStats.txt` and `UlPdcpStats.txt` keep only the final partial epoch (6 rows, 9.75–10 s) | calculator `:583-595`, `:586-591`; `mmwave-enb-net-device.cc:492`, `:1510` |
| F6 | **DL is constant per UE.** `nTxPDUs` is 198 in 582 of 588 rows in c8free, live1 and live2, including after live1's 4 applied handovers (`EnbHandoverEndStats` at 2.0, 3.0, 6.0 and 7.0 s). So (i) no handover double-connects the MN PDCP traces. UL RxPDU is connected in the same call as DL TxPDU (connector `:1196-1199`), so this covers UL too (inference). And (ii) a gNB cell's DL = round(n × 2092.8) kbit for n UEs | evidence above |
| F7 | **The getters insert entries.** They use `operator[]`, so a UL read adds zero entries to `m_ulRxPackets` and `m_ulRxData`. `ResetResultsForImsiLcid` erases them in the same call, and `WriteUlResults` keys on `m_ulTxPackets` only | calculator `:597-627`, `:508-522`, `:398-404` |
| F8 | **IPC.** A gNB cell's `cuUp` is `{}` today. gNB samples carry `simTimeNs` = 0.8 ms + k·100 ms; the LTE eNB's carry 0.5 ms + k·100 ms. Each gNB sample's `ues` entries that hold a `cuUp` object are exactly that report's UE map. Precedent: the LTE helper already has `FillCuUpValues(plmId, long ul, long dl)`, which carries per-UE-rounded, PDU-level DL and UL hard-coded to 0 | `lte-indication-message-helper.h:39`; `lte-enb-net-device.cc:1112-1114`, `:1236` |
| F9 | **QP's `constant()`.** It drops duplicate [UL, DL] rows, drops columns with only one value, applies `dropna`, drops all-zero columns, and returns "not constant" iff at least 10 rows remain. A constant DL column alone does not make it True; the distinct rows then equal the distinct UL values. `adfuller` runs only in training | `ric-app-qp@47a35ca src/qptrain.py:55-64`, `:81-92`, `:121-140`; `prediction.py:32` |
| F10 | Influx rows join on (`ns3.nodeId`, `ns3.seq`), never on `_time` | `scripts/gates/gate-m6-kpm.sh:12` |

## Q1. The SDU-header rule
**Computation** (`MmWaveEnbNetDevice::BuildRicIndicationMessageCuUp`, loop at `mmwave-enb-net-device.cc:657`; all arithmetic in `uint64_t`):
```
h  = LtePdcpHeader().GetSerializedSize()          // 2; lte-pdcp-header.cc:95-99 (call the class, no literal)
for each UE u in m_rrc->GetUeMap():                // the gNB's UE map at report time
  Bul = GetUlRxData(imsi,3);  Nul = GetUlRxPackets(imsi,3)   // calculator :621-627, :605-611; filled at :251-252
  Bdl = GetDlTxData(imsi,3);  Ndl = GetDlTxPackets(imsi,3)   // calculator :703-709, :687-693; filled at :217-218
  NS_ASSERT(Bul >= h*Nul && Bdl >= h*Ndl)          // invariant, no side effect
  ulBits += 8*(Bul - h*Nul);  dlBits += 8*(Bdl - h*Ndl)
ulKbit = (ulBits + 500) / 1000;  dlKbit = (dlBits + 500) / 1000   // round half up, once per cell per period
```
- **Rounding.** The integer form equals `std::round` for non-negative values, and the checker can replicate it exactly.
- **Which paths already round per UE.** Two existing DL paths sum per-UE rounded, PDU-level kbit:
  - the gNB's `cellDlTxVolume` (`:666-670`), which only feeds `NS_LOG_DEBUG` (`:800-801`); the CSV row writes empty fields (`:829-830`);
  - the LTE eNB's `pDCPBytesDL` (`lte-enb-net-device.cc:1112-1114`, `:1236`), which is on the wire.
- Reuse and change neither: changing the LTE field would move V2.
- Both new counters round once per cell, so UL and DL are consistent.
- **Worked example** (the CBR DL, 4 UEs): 4 × 200 × (1310 − 2) × 8 = 8,371,200 bits → **8371** kbit. The old per-UE PDU-level rounding gives 4 × 2096 = 8384.
- **SN length.**
  - Only `LtePdcpHeader` exists for DRBs. Its SN is fixed at 12 bits and its header at 2 B, on the UE (UL Tx) and on the MN (DL Tx, UL Rx). So no UL/DL or per-bearer difference can occur at these pins.
  - If a later change introduced another size (for example an NR 18-bit SN = 3 B, or a 4-B MAC-I trailer with DRB integrity), the rule becomes per (direction, lcid): Σ 8·(B − h_dir,lcid·N).
  - That works only while the size is constant for an (imsi, lcid) within a period. A mid-period reconfiguration would need per-PDU stripping at the trace sink.
  - Put this in a code comment and call the class, not a literal.
- **Delivery caveat.** UL SDUs of 40 B or less are counted by RxPDU but never delivered (`mc-enb-pdcp.cc:322`).
  - Make "UL SDU > 40 B" a recorded constraint of the UL config. `UdpClient` payload = PacketSize (`udp-client.cc:208`), so SDU = PacketSize + 28 and PacketSize must be ≥ 13.
  - Have the V3 checker assert it.
- **Standards rows** (read through zotero-mcp; I could not, so the clause numbers below are from memory and must be verified):
  - 3GPP TS 36.323 V19.0.0 (`DZFZCTGR`): data PDU for DRBs with a 12-bit SN, 2-octet header (I believe §6.2.3).
  - 3GPP TS 38.323 V19.1.0 (`MSNDDXJH`): the 12-bit-SN DRB data PDU is also 2 octets, plus an optional 4-octet MAC-I (I believe §6.2.2.2).
  - If confirmed, record that **P7 changes none of the N4 numbers** at a 12-bit SN without integrity.

## Q2. The double-count check for V3
**What can double count** (from the code):

| # | Mechanism | Status |
|---|---|---|
| H1 | One PDCP trace connected twice to E2PDCP. `ConnectDrbTracesEnb` runs on the first reconfiguration and on every eNB `HandoverEndOk` (connector `:483-492`, `:907-912`), and `DisconnectTracesEnb` is empty (`:1284-1290`) | Not seen: F6 shows 198 PDUs per epoch across 4 handovers |
| H2 | RxPDU at two RRCs for one PDU | Structurally impossible: one TEID maps to one MN PDCP (F1), and there is one LTE eNB |
| H3 | A UE in two gNB UE maps at one read (HO overlap) | No double count, because reading resets; the first reader takes the bytes. Attribution splits |
| H4 | The same SDU delivered or sent twice at one RRC. UL: ns-3 PDCP has no duplicate discard (`mc-enb-pdcp.cc:313-329`). DL: RLC buffers are re-inserted into the MN PDCP at a leg switch (`lte-enb-rrc.cc:1227-1239`, `:2297-2306` → `:5689-5718`) | No switches at −1000 dB. Possible in principle |

**What to count per RRC.** Add a small audit to `scenario-zero.cc`, behind `--enableUlTraffic` only.
- **Hooks.**
  - At setup, connect `/NodeList/*/DeviceList/*/LteEnbRrc/ConnectionReconfiguration` and `…/HandoverEndOk`; both exist on every eNB and gNB RRC.
  - In each callback, run `Config::LookupMatches("<rrc>/UeMap/<rnti>/DataRadioBearerMap/*/LtePdcp")`. Connect each matched object's `RxPDU` and `TxPDU` **once**, guarded by a set of object pointers. Bind nodeId, cellId and IMSI into the callback.
- **Output.**
  - Per event, one stdout line:
    - `N4AUDIT ulrx <tNs> <nodeId> <cellId> <imsi> <lcid> <pduBytes> <delayNs>`
    - `N4AUDIT dltx <tNs> <nodeId> <cellId> <imsi> <lcid> <pduBytes>`
  - A header line `N4AUDIT v1 hdr=<h>`.
  - After `Simulator::Run()` and before `Destroy`, a completeness line: `N4AUDIT end connected=<n> present=<m>`, where m is the number of matches of `/NodeList/*/DeviceList/*/LteEnbRrc/UeMap/*/DataRadioBearerMap/*/LtePdcp` at that point.
  - Use `std::cout` with `'\n'`, not `endl`. That is about 220k lines, about 10 MB, for a 10-s run.
- **Constraints.**
  - No RandomVariable, no `Simulator::Schedule`, no new file. `stdout.txt` is already excluded from every digest (`compare-free-run.py` LOGS).
  - Keep it in `scenario-zero.cc`. `agents-ns3-run.sh:40` finds the binary with `find build/scratch -maxdepth 1`, so a scratch subdirectory would move the binary and break the harness.

**Checker** (`check-pdcp-volume-totals.py <run>`). Inputs:
- `ns3run/stdout.txt` (the audit lines);
- `trace/e2-ipc-trace-<gNB>.jsonl` (`simTimeNs`, the two cuUp fields, and the cuUp UE list per sample);
- the hello lines (node kind).

It passes only if all of these hold:
- **A1 completeness:** `connected == present`, no object is connected twice, and the audit header's h equals the rule's h.
- **A2 one RRC per UE:** every `ulrx` and `dltx` event of an IMSI is on one node, the same node for UL and DL.
- **A3 no PDU at two RRCs:** no UL identity (imsi, tNs − delayNs) appears on two nodes. An event with `delayNs == 0` has no identity; report it as "no identity" and do not fail on it.
- **A4 accounting.**
  - For each UE, the reads are the gNB samples whose cuUp UE list holds it.
  - Events in (previous read, this read] belong to that sample's cell; truthBits = Σ 8·(pduBytes − h).
  - Per gNB sample, |1000·counter − truthBits| ≤ 500, for UL and for DL.
  - Per period, Σ over gNB cells is within ±1 kbit per cell (the plan's literal V3).
  - An event exactly at a read instant (`tNs` equals that UE's read time) is a tie and must not occur (fail closed).
  - When a UE is in two UE maps at the same read, judge only the Σ over those cells and count the overlap. Expect 0 overlaps in V3.
- **A5 header and delivery:** every event has pduBytes ≥ h + 1, and every UL event has an SDU > 40 B.

Report, but do not gate on:
- duplicate UL identities on one node;
- residual bits after each UE's last read;
- per-UE PDUs per period (the saturation evidence for Q4);
- the CBR DL expectation of 200 PDUs per UE per read window.

**The run.** One free-run with UL on, in the pre-registered R3 config. No RIC is needed, and the same run serves as the Q4 calibration.
- It contains no handovers. HO-time attribution is covered by F6.
- Because the audit sits behind the UL flag, P8 can run the same checker on every R3 live run, which do contain QP-driven handovers. That would add a check, not remove one.

**Pass/fail output.** One JSON verdict:
- `a1..a5` booleans;
- `perCellMaxErrBits`, `periodSumMaxErrKbit`, `ties`, `overlaps`, `rrcNodesPerImsi`, `twoRrcIdentities`, `sameRrcDuplicates`, `noIdentityEvents`, `residualBits`;
- exit 0 only if every A item holds.

**If a PDU is counted twice:** stop and follow the Failure Protocol. Never compensate in the checker: no dedupe, no factor, no wider tolerance, no excluded period. Classify by mechanism:
- **Counter about 2× the audit for a UE** (H1): the calculator gets the event twice.
  - The fix belongs in the connector, which the flag-off path shares.
  - Re-run V2. If the fix moves any flag-off byte (for example the LTE per-UE DL fields), it changes the locked outcome: PAUSE T6, or T3.
- **Events at two RRCs** (H2): this contradicts F1 and means the model differs from what I read. Do not patch around it: PAUSE T3.
- **Duplicates at one RRC** (H4): the counter is correct, because ns-3 delivered the SDU twice.
  - Record it as a simulator artifact and a candidate realism deviation, for the user (T4 class) at the next pause.
  - It is not a V3 failure by the plan's wording ("at two RRCs").

## Q3. Placement, and the flag-off path
- **Accumulators.** Declare `ulSduBits` and `dlSduBits` (`uint64_t`) next to `cellDlTxVolume` (`:647-650`).
- **Reads.** Read and accumulate right after `:670`, beside the existing DL reads (`:664-669`). That is above the RLC loop (`:677-687`) and well above `ResetResultsForImsiLcid` (`:778`). Between them, only `GetDlDelay` (`:741`) touches E2PDCP, and it only finds.
- **Emit.** After the loop, inside the `if (!IsOffline())` block (`:795-798`), call `FillCuUpValues(plmId, ulKbit, dlKbit)`.
  - Mirror the LTE signature in `mmwave-indication-message-helper.{h,cc}` (`.h:39`, `.cc:50-54`).
  - Use `AddCellValue<long>("DRB.PdcpSduVolumeUL", …)`, then `…DL`.
  - Include `ns3/lte-pdcp-header.h`.
- **Do not call** `GetUlTxData`, `GetUlTxPackets`, `GetUlCellId` or `GetDlCellId`. The cell-id maps are never erased (K25), and every cell id is 1 here, so any cell filter would zero the counters.

**Flag off: nothing changes except the two IPC keys.**
- **No RandomVariable.** The new code creates or draws none. The GlobalValue registers statically.
- **No event.** No `Schedule` call is added, and the audit and the UL client sit inside the flag branch.
- **No file.** No CSV column, no trace, and no stdout line (V2 checks this, see Q5).
- **Map state.** The UL reads insert zero entries that `:778` erases in the same call (F7). `WriteUlResults` iterates `m_ulTxPackets`, which the new code never touches.

**Flag on.**
- **No new RandomVariable.** `UdpClient` and `PacketSink` hold none. Install the UL client inside the UE loop after the DL client (`scenario-zero.cc:582-586`): `UdpClientHelper(remoteHostAddr, 60000)` per UE, added to `clientApp`, so it starts at 0.1 s and stops at simTime − 0.1 (`:594-595`). The sink already exists in every run (`:566-572`). All of this is after the `speed` RV (`:528`).
- **No reordering of existing events.** New start events only add uids; they keep the relative order of the existing events.
- **Validate it:** in the calibration run, against the UL-off V2 run at the same pins, `ues.txt`, `enbs.txt`, `CellIdStats.txt` and `MmWaveSwitchStats.txt` must be fully equal, and the `X2Stats.txt` lines before 0.1 s must be equal. With NoAuto and −1000 dB, attach and switch happen only at 0.054 s.

## Q4. UL traffic
- **Primary: constant-rate UL equal to DL.** `PacketSize=1280`, `Interval=500 µs`, `MaxPackets=UINT32_MAX`, per UE to `remoteHost:60000`.
  - That is 20.48 Mbit/s of payload per UE, or 42–84 Mbit/s offered per cell. This is very likely above the uplink capacity of this 20 MHz carrier (inference).
  - The delivered UL then follows the channel and the scheduler. Under saturation, per-UE DL deliveries in the reference vary by ±10–25 % per period (`nRxPDUs` 93–249).
  - Benefits: the plan's literal "constant rate"; K17's first option; no RV; the SDU is a fixed 1308 B (an extra checker assertion); a full-buffer-like load.
  - Risk: PDU quantization. A stable cell could repeat its per-period PDU count, leaving fewer than 10 distinct values in a window.
- **Fallback, pre-registered now: a deterministic pattern below capacity.**
  - `Interval=5 ms` and `PacketSize_k = 200 + 50·(k mod 16)` B for UL period k from 0.1 s.
  - It is set by one `Simulator::Schedule`d `SetAttribute("PacketSize")` per step, inside the flag branch (no RV). `UdpClient` reads `m_size` at every send.
  - That gives 16 distinct offered volumes per window by construction, small buffers, and SDUs > 40 B.
- **Selection.** Run the primary first. Use the fallback only if the primary fails the pre-registered V5 predicate on the calibration run. If both fail, PAUSE T3: do not tune any further.
- **Validate before the dump**, in this order:
  1. V3 calibration free-run in the R3 config with UL on.
  2. On its IPC trace, apply the exact V5 predicate (Q6) to every complete 16-seq window of each gNB cell, plus int types.
  3. The no-RV prefix equality (Q3).
  4. Saturation evidence for the primary: audit per-UE UL PDUs per period below 200.
  5. V3 green.
  6. Record the chosen UL parameters and the calibration evidence directory in `rung-config.json` and commit them.
  7. Take the dump once.
  8. Then `digest-run.py --compare --components ipc CAL=<calib> DUMP=<dump run>` must be equal. That is null-control equivalence with UL on, and it ties the dump to the validated values.

## Q5. The V2 strict drop option in `digest-run.py`
- **Option.** `--n4-ul-off-drop REF=absent,CAND=present`. Default off, so every other caller is unchanged.
- **Mechanism.** Add an optional per-message `transform` hook to `load_samples` in `scripts/probes/compare-ns3-ipc-sample-digests.py`. Default `None` gives identical behaviour.
- **Per run, on `sample` lines only:**
  - The node kind comes from the hello line.
  - `present` run:
    - every gNB sample's `cell.cuUp` holds both `DRB.PdcpSduVolumeUL` and `DRB.PdcpSduVolumeDL`, each a JSON int (int and not bool);
    - UL == 0 in every gNB sample;
    - DL > 0 in at least one sample **of every gNB node** that ever lists a UE (stricter than "once", and certain in c8free);
    - no eNB sample and no UE-level section carries either key;
    - then delete exactly those two keys and nothing else. A `cuUp` left as `{}` stays `{}`, which matches the reference.
  - `absent` run: no sample carries either key.
- **Report and exit.**
  - Write the result to the report under `n4Drop` (`samplesChecked`, `missing`, `ulNonZero`, `nonInt`, `dlPositiveByNode`, `unexpectedCarriers`).
  - Any precondition failure exits non-zero, whatever the digests say. A stray extra key is not dropped, so the digest differs and V2 is red.
- **The V2 gate also asserts:**
  - **trace name set:** traces stay at `ipc,traces` with their names (no new file);
  - **no audit output:** zero `N4AUDIT` lines in the candidate's `stdout.txt`;
  - **provenance:** `ns3-binary-provenance.txt` names the new ns-3 and oran-interface SHAs (D1).
- **Self-test** (a strengthening):
  - one fixture that passes;
  - failing fixtures: a missing key, UL = 1, DL all zero, `0.0` as a float, an extra key, a reference that carries the keys, and an eNB sample that carries one.

## Q6. V5 pre-registration and the `rung-config.json` fields
**Text to commit before the calibration run.** Rule id `n4-v5-r1`.
- **Input:** the scrubbed Influx dump of the K18 run: null-control, lock-step, the R3 config, UL on, with the parameters from `rung-config.json`.
- **Rows:** measurement `cellMetrics`, restricted to gNB cells (`ns3.nodeId` of a node with kind gnb), keyed by (`ns3.nodeId`, `ns3.seq`), never by `_time`.
- **Windows:** every window of 16 consecutive `ns3.seq` values that are all present for one cell, sliding by 1 from the first seq to the last. None is excluded, start-up and tail included.
- **A window passes iff:**
  - (a) both fields `DRB.PdcpSduVolumeUL` and `DRB.PdcpSduVolumeDL` are present in all 16 rows, with Influx datatype `long` (int);
  - (b) QP's `PROCESS.constant()` (`ric-app-qp@47a35ca src/qptrain.py:81-92`, reimplemented verbatim) is False on the window's [UL, DL] frame, which means at least 10 distinct (UL, DL) rows;
  - (c) neither column is all zero in the window (K17).
- **V5 passes iff** every window of every gNB cell passes, and V6 holds.
- **Fixed after the dump:** the rule, the window set and the UL parameters do not change after the dump. A red window is a failed Verify.
- **Diagnostic only:** per-window distinct counts of each series, reported. DL is expected to be constant within almost every window. That is by design, and it is the input P7 needs to test QP training.

**Why not "≥ 2 distinct values of each series".**
- It is the original V5 text, which K17 explicitly replaced ("V5 replaced").
- With the CBR DL (F6) and a constant UE set (NoAuto, −1000 dB, null-control), it fails by construction.
- Reading K17 as additive would make V5 unsatisfiable without changing the DL traffic, a product choice. That would be T3, not a quiet DL change.

**Fields to record** (one object with a provenance per item):
- **pins:** the ns-3, oran-interface and Testbed SHAs of the dump;
- **topology and run:** `nMmWaveEnbNodes` 2; `handoverMode` NoAuto; `simTime_s`; `RngRun` 1; `outageThreshold_dB` −1000 (substitution 1); `simStartEpochMs` 1767225600000; `indicationPeriodicity_s` 0.1; `bufferSize_MB` 10;
- **reporting flags:** `e2du`, `e2cuUp`, `e2cuCp` and `reducedPmValues` as gated;
- **pacing:** lock-step, null control;
- **DL (unchanged):** 1280 B / 500 µs / 0.1 s to simTime − 0.1;
- **UL:**
  - `enableUlTraffic` true, app `UdpClient`, PacketSize, Interval, MaxPackets, destination port 60000, start and stop;
  - pattern null, or the fallback's formula;
  - the constraint "UL SDU > 40 B";
  - the calibration evidence directory;
- **header:** `pdcpHeaderBytes` 2, with its source line and SHA;
- **V5:** `v5Rule` id, window 16, slide 1, the predicate, the commit SHA and the KST time.

Fill the existing `ul_rate` key; it is currently null. The R3 schedule's `simTime` must equal the dump's. Any later change re-takes the dump and re-judges V5 (D2).

## Q7. Plan text that cannot run literally or would weaken a test
1. **Context, "UL Rx … gNB's DRB PDCP (`lte-enb-rrc.cc:499`)":** false for EN-DC UEs (F1). The counters are MN-PDCP volume attributed by gNB UE map; that standards classification is the user's call (TL;DR 2).
2. **Hazard (a), "McForwardUplinkData can fire RxPDU on more than one RRC":** structurally false (one TEID maps to one MN PDCP). V3 still measures it.
3. **V3, "at the gNB PDCP from the ns-3 PDCP trace file over the same window":** no such file exists (F5). Using the E2 rows with a tolerance widened to absorb the 0.8 ms sliver would **weaken** V3, and deriving the truth from the same calculator would be vacuous. The audit is the truth, and it is stricter (±0.5 kbit per cell).
4. **V5 original text versus K17:** see Q6. The phase acceptance "both series non-constant" holds for DL over the whole dump only through its start-up and tail values. Raise this with P7: QP trains on a nearly constant DL column. It is not a P6 red under K17.
5. **Step 2 "for the DRB SN length in use":** trivially executable, because the size is one constant (Q1). Replace the standards row "3GPP TS 38.323 … check presence; missing → T4" with K4's two rows (Q1). Don't leave the stale text.
6. **Step 3 "constant rate":** it needs the calibration and the pre-registered fallback (Q4). Without them, it is a single shot at a T6.
7. **Step 5 and the Files list:** add the audit in `scenario-zero.cc`, the oran-interface `.h`, the `lte-pdcp-header.h` include, the `digest-run.py` option and its fixtures, and the `load_samples` hook. Also say that V3 is a free-run with UL on in the R3 config.
8. **Stale line numbers** (at `ace32168`): use `scenario-zero.cc:528`, `:566-572`, `:576-587`, and `e2-ipc-message-encoder.cc:201`.
9. **Forward risk for P7 and P8 (inference).** The gNB-cell DL is the UE count × 2092.8 kbit. A DL-driven TS xApp decision may therefore pull UEs into the bigger cell until the smaller one empties. Its rows then become all-zero, and QP's `constant()` becomes True for it. Check this when P7 chooses the R3 schedule (T3 territory). It is not a P6 item.

## What to avoid
- Filtering on any calculator cell id: every one is 1.
- Reading after `:778`.
- Re-using or "fixing" `cellDlTxVolume` or the LTE `pDCPBytesDL`.
- Using doubles for the bit sums.
- An `OnOffApplication`, or any helper with RandomVariables, for UL.
- Moving `scenario-zero` into a scratch subdirectory.
- The NS_LOG debug stream as V3's judge.
- Compensating a double count in the checker.
- Choosing the V5 rule or window after seeing data.
- `git add -f` for the dump fixture.

## Alternatives and trade-offs
- **A. Per-period buckets inside ns-3** instead of per-PDU lines. Smaller output, but it copies the 800 µs read offset into scenario-zero and cannot resolve HO overlap. Weaker.
- **B. A trace file only when UL is on** (`ns3run/N4PdcpAudit.txt`) instead of stdout.
  - It fits the rule "judge on ns-3 traces" better, it is digested in R3 C1, and the flag-off path is unchanged.
  - Your brief rules it out. If that constraint was meant only for the flag-off path, I would prefer B.
- **C. A separate `--pdcpAudit` flag.** R3 stdout stays lean, but P8 loses free checks on HO-bearing runs. Acceptable; I prefer the single flag.
- **D. NS_LOG with no code** (`McEnbPdcp=level_function|prefix_time|prefix_node`). Zero code, but the judge would be a debug log in a version-dependent format. Reject it for gating.

## Work checklist
1. Do the Zotero reads (3GPP TS 36.323, 3GPP TS 38.323, 3GPP TS 37.340 §4.2.2, and the 3GPP TS 28.552 measured object). Fill the ledger. Write the user ruling request (P7 widening or a new P9) into the notes.
2. Commit the V5 text, the UL primary and fallback parameters, and the checker rules, before any UL-on run.
3. Write the code (Q1, Q3), the audit, the UL flag, and the oran-interface signature. Run V1. Add the `digest-run.py` option, its fixtures and the `load_samples` hook.
4. Wait for the user's ruling, or include it in the next PAUSE, before pushing the counter. Then push the forks and bump `pins.conf` before any gate (D1).
5. Build, then run V2 (provenance, drop option, zero audit lines).
6. Run the calibration and V3 free-run in the R3 config with UL on: V3 checker, the no-RV prefix equality, the V5 predicate on IPC. Use the fallback only if needed; if both fail, T3.
7. Do K13, then M5–M7, then r0/r1/r2 single (V4).
8. Take the K18 dump once, judge V5 and V6 once, run the IPC equality against the calibration run, and commit the fixture under a non-ignored name.

## Success metrics
- V2 equal, with both keys in every gNB sample, UL = 0, and DL > 0 per gNB node.
- V3: `perCellMaxErrBits` ≤ 500, ties 0, one RRC per IMSI, `connected == present`.
- UL-off DL body samples equal round(n × 2092.8).
- Every V5 window passes on the first and only dump.
- The calibration and dump IPC are equal.
- No change to any flag-off trace byte.

## Assumptions
- **High.** The EN-DC bearer's PDCP is MN-hosted for every UE (F1, plus the evidence). It would flip only if a gNB node owned a `DataRadioBearerMap` PDCP, which A1 and A2 would show.
- **High.** No UL lcid-3 traffic exists with UL off. Only the remote host has a `UdpClient`, and the UL E2 trace has a header only.
- **Medium.** The UL with the DL parameters saturates the uplink. The calibration run decides this, with a pre-registered fallback.
- **Medium.** The MN-hosted attribution needs a user classification, but no code change. If the user's §4 note ("measured where the DL counter is taken") counts as having classified it, no ruling is needed. I did not treat it so, because §4 also called the N4 metric faithful "with no deviation" while the location was still unverified.
- **Medium.** The clause numbers of 3GPP TS 36.323 and 3GPP TS 38.323 come from memory; Zotero is the authority.
- **Low.** No PDCP event ever coincides with a read instant. The checker fails closed if one does.

## Unresolved questions
1. Does the user widen P7 to cover the MN-hosted PDCP attribution, or record a new P9? Either way the code is the same.
2. Was "no new trace file" meant for the flag-off path only? If so, alternative B is cleaner.
3. Does P8 adopt the V3 checker as a per-run check on the R3 live runs?
4. P7: does QP train cleanly on a DL column that is constant except at start-up?

Status: DONE_WITH_CONCERNS
Summary: The SDU rule is Σ 8·(B − 2N) per gNB cell from the shared MN-PDCP calculator, rounded once per cell, and the SN length is fixed, so UL, DL and bearers cannot differ. V3 needs a flag-gated per-PDU audit on stdout, because no aligned PDCP trace exists. V5 must be K17's QP predicate, because the gNB-cell DL series is constant within windows.
Concerns/Blockers: The counters attribute MN-hosted PDCP volume to the en-gNB cell (the phase Context is wrong). The user must classify that as a widening of P7 or a new P9 before the counter is pushed. Pre-registering "≥ 2 distinct values of each series" would fail V5 by construction.

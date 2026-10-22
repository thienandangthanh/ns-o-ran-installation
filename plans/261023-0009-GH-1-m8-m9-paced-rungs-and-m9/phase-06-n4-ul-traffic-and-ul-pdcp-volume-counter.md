# P6: N4, opt-in UL traffic and the UL/DL PDCP SDU volume rows

**Start state:** `r2-green`. **Snapshot at exit:** none.

## Context (resolved read-only during warmup planning, ns-3 @ace32168, oran-interface @438a839)
- **UL PDCP Rx point.** `RxPDU` fires in `McEnbPdcp::DoReceivePdu` (`src/lte/model/mc-enb-pdcp.cc` ~300-308) on the RRC that receives the PDU. For mmWave-carried UL that is the gNB's DRB PDCP (`lte-enb-rrc.cc:499`). `ConnectDrbTracesEnb` (`src/mmwave/helper/mmwave-bearer-stats-connector.cc:1141-1203`) wires every `UeMap/*/DataRadioBearerMap/*/LtePdcp/RxPDU` to `UlRxPduCallback` for every calculator in `m_e2PdcpStatsVector` (gNB `E2PDCP` and LTE `E2PDCPLTE`, `mmwave-helper.cc:3187-3200`). `UlRxPdu` accumulates by (imsi, lcid) with no cell filter (`mmwave-bearer-stats-calculator.cc:236-260`).
- **DL mirror.** The gNB DL cell volume sums `GetDlTxData(imsi,3)` over its UE map, converted per UE to kbit as `round(bytes*8/1e3)` (`mmwave-enb-net-device.cc:640-671`). It is PDU-level (fired after `AddHeader`, `mc-enb-pdcp.cc:262`), and it is written only to the CSV (`:503`), never to IPC. `ResetResultsForImsiLcid` (`:778`) clears both DL and UL maps, so the UL read must sit above it.
- **Hazards.** (a) Both calculators receive every RRC's events, and X2 `McForwardUplinkData` (`epc-x2.cc:660-664, 1285`) can fire `RxPDU` on more than one RRC, so double counting is possible (inference, not run). (b) `GetUlCellId` returns the DL cell map (calculator `:732`); do not filter on it. (c) The values are PDU bytes including the PDCP header; 3GPP TS 28.552 counts SDU bits.
- **Opt-in UL traffic.** scenario-zero already has a sink on the remote host at port 60000 (`scratch/scenario-zero.cc:524-530`) and a DL `UdpClient` per UE (`:532-545`). `UdpClient` and `PacketSink` create no `RandomVariable`, so with the flag off nothing shifts the automatic stream indices. In the flag-on branch, create no RV ahead of the existing ones (the `speed` RV at `:486`).
- **IPC.** `EncodeE2IpcSample` (`oran-interface/model/e2-ipc-message-encoder.cc:192`) writes `cell.{du,cuUp,cuCp}`. The gNB `FillCuUpValues` (`oran-interface/helper/mmwave-indication-message-helper.cc:51`) carries no volume today.
- **kpimon.** A new cell measName becomes a `cellMetrics` field of the same name with no code change (no whitelist). INTEGER → int32, REAL → float64. The field has no tags; the cell identity is the field `ns3.nodeId`. The count and order of cell values must match the RAN-function advertisement (`control.go.previous:773-786`), and the name list is read once per node at initialization. If kpimon nonetheless needs a code change, that is PAUSE T3 (it would widen the locked SIZE(8)-only patch scope).

## Requirements (contract)
In scope 4 (amended 2026-10-23 00:14):
- opt-in UL traffic in scenario-zero (`--enableUlTraffic`, default false);
- per-gNB-cell PDCP SDU volume counters, UL and DL, sent as `DRB.PdcpSduVolumeUL` and `DRB.PdcpSduVolumeDL` (INTEGER, kbit; legacyNames `DRB.PdcpSduVolumeUL_Filter`, `DRB.PdcpSduVolumeDL_Filter`), appended to the metric map;
- the agent mapping; the existing MAC-sourced `QosFlow.PdcpPduVolumeDL` row is unchanged (recorded deviation P6).
Acceptance (regression): free-run with UL off is unchanged (ns-3 traces byte-equal; IPC `sample` lines equal after removing exactly the two new cuUp fields); M5–M7 green; one live run each of R0, R1, R2 on the new image passes; a UL-on Influx dump exists for QP with both series non-constant.

## Files
- ns-3 fork: `scratch/scenario-zero.cc` (flag + UL `UdpClient`), `src/mmwave/model/mmwave-enb-net-device.{h,cc}` (UL and DL SDU accumulation in the UE loop above the reset).
- oran-interface fork: `helper/mmwave-indication-message-helper.cc` (two `AddCellValue<long>` cuUp items).
- Testbed agent: `schema/metric-map.v1.json` (append rows order 34, 35; measIds 34, 35; `src` `/cell/cuUp/<name>`), `tests/lint-metric-map.py` (no change expected).
- Harness: `scripts/gates/check-pdcp-volume-totals.py`, `scripts/gates/gate-n4-ul-metric.sh`.

## Steps
1. **kongming before code** (opus): pass this Context and ask for the SDU-header rule and the double-count check design.
2. Read the PDCP header size from `LtePdcpHeader::GetSerializedSize` for the DRB SN length in use; compute SDU bits = (PDU bytes − header bytes × PDU count) × 8 per UE (use the calculator's packet counts), sum per cell, then `round(bits / 1000)` once per cell per period.
3. Add the flag and the UL `UdpClient` (constant rate chosen so the UL kbit series varies across 16-step windows; record the rate).
4. Add the IPC fields and the metric-map rows; run the lint.
5. Double-count check: a flag-on run with per-RRC event counting.
6. Regression: free-run UL off; M5–M7 gates; one live run each of R0, R1, R2.
7. UL-on dump: one live run in the R2 config with UL on; archive the scrubbed Influx dump for P7/P8.
8. Pin bump; phase-exit checklist.

## Verify (comparison only)
- V1: `tests/lint-metric-map.py schema/metric-map.v1.json` exits 0.
- V2: UL off vs the P5 reference: `digest-run.py` ns-3 trace digests equal; IPC sample digests equal after dropping `cell.cuUp.DRB.PdcpSduVolumeUL` and `cell.cuUp.DRB.PdcpSduVolumeDL`.
- V3: flag-on run: `check-pdcp-volume-totals.py` exits 0, meaning for each period Σ over gNB cells of the UL counter equals, within ±1 kbit per cell, the UL PDCP SDU bits delivered at the gNB PDCP from the ns-3 PDCP trace file over the same window; likewise for DL. A per-RRC event count shows no PDU counted at two RRCs.
- V4: M5, M6, M7 gates exit 0; R0, R1, R2 single live runs each pass C2–C9.
- V5: in the UL-on dump, every 16-step window per gNB cell has ≥ 2 distinct values of each of `DRB.PdcpSduVolumeUL` and `DRB.PdcpSduVolumeDL` in `cellMetrics`; the field types are int.
- V6: token-pattern grep over the dump = 0.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| UL name, definition (SDU bits delivered to higher layers), NRCellCU | 3GPP TS 28.552 V20.2.0 §5.1.2.1.2.1 | `5SZUBP6M` | 2026-10-22 |
| DL name and definition | 3GPP TS 28.552 V20.2.0 §5.1.2.1.1.1 | `5SZUBP6M` | 2026-10-23 (amendment) |
| Wire name without `_Filter`, PrintableString; filters as labels | E2SM-KPM v03.00 §8.3.9, §8.3.11 | `F82PYZVK` | 2026-10-22 |
| INTEGER, kbit (gap: KPM cites old clause 5.1.2.1.2.2) | E2SM-KPM v03.00 §7.9.1 | `F82PYZVK` | 2026-10-22 |
| Existing DL MAC-sourced row — **recorded deviation P6 (widened)** | E2SM-KPM v03.00 §7.9.1; 3GPP TS 28.552 §5.1.3.6.1.1 | `F82PYZVK`, `5SZUBP6M` | 2026-10-23 |
| PDCP header size for SDU accounting | 3GPP TS 38.323 (NR PDCP) data PDU format — **check presence in Zotero; missing → T4** | — | read in this phase |

## Failure Protocol
If any Verify step does not meet its stated pass condition, STOP this phase.
Do not improvise a fix, retry blindly, or reason around the failure.
Spawn the `kongming` subagent (`model: opus`) for next-step counsel and pass:
- the phase and task id,
- what you attempted (the steps you ran),
- the exact command and its full output (scrubbed),
- the pass condition it failed to meet.
Apply kongming's guidance, then re-run the Verify step. If it fails again, or the guidance would change the locked outcome, print `PAUSE T6 evidence=<path> journal=<path>` and call no further tool.
If `kongming` cannot be spawned, STOP and print the same PAUSE line with the failure evidence. Never continue by self-reasoning. kongming's counsel is never user approval.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P7.

## Risk and rollback
Risk: double counting through X2 or the shared calculators (V3 catches it); integer kbit flattening at low UL rates (V5). Rollback: the flag defaults off; revert commits; revert VM to `r2-green`.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K25 (fact fix).** `GetUlCellId` (`mmwave-bearer-stats-calculator.cc:720-725`) returns `m_ulCellId`, which `UlRxPdu` sets to the reporting RRC's cell (last writer, `:250`); `:732` is `GetDlCellId`. Still do not filter on it. AddHeader is at `mc-enb-pdcp.cc:259`. `FillCuUpValues(plmId)` has no volume parameter, so the `.h` file and the ns-3 caller change too; add them to Files.
- **K4 / P7.** The SDU accounting strips the header ns-3 actually adds (E-UTRA PDCP, 3GPP TS 36.323 data PDU format) and records it. Recorded deviation P7: 3GPP TS 37.340 V18.7.0 §4.2.2 (`E6VYJPXJ`) requires NR PDCP (3GPP TS 38.323) on EN-DC bearers other than MN-terminated MCG bearers. Ledger rows cite 3GPP TS 36.323 V19.0.0 (Zotero `DZFZCTGR`, data PDU format) and 3GPP TS 38.323 V19.1.0 (`MSNDDXJH`), both added 2026-10-23.
- **K17 (V5 replaced).** For every R3 trigger window, QP's own `constant()` predicate is false: ≥ 10 distinct non-duplicate (UL, DL) rows and no all-zero column. Use a UL rate above uplink capacity, or a deterministic pattern that creates no RV, and record it in `rung-config.json`.
- **K18 (step 7).** Take the UL-on dump from a **null-control lock-step run in the R3 config with UL on**.
- **K13.** Restart kpimon after the agent advertisement changes, and gate its re-subscription (the name list is read once per node).
- **K19.** V2 compares against the last free-run at the pre-P6 pins.
- **K20 (start state).** This phase descends from `r2-green` and is not reverted to it. Rollback: revert to `r2-green`, then re-run M4, M5 and the P6 builds.

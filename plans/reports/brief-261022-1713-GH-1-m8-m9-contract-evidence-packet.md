# Evidence packet: the M8–M9 delivery contract (brainstorm --ultra)

Date: 2026-10-22 17:13 KST. Branch `migrate-l-release-NIST-1-8-0`. This packet is the same for all five candidates. Do not reopen anything marked **locked**.

## 1. The request

The user approved the pre-M8 pacing plan (`docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md`) with the changes below and asked for a bounded delivery contract for **M8 (= R0), R1, R2, R3 and M9**, which will then feed `ak:plan`. The original contract text: M8 means an rc xApp control causes a handover visible in the ns-3 trace, for at least 2 gNBs. M9 means: revert `fresh-install`, run one script unattended, and reach the highest green rung (`plans/reports/brainstorm-261017-0308-GH-1-ns-oran-l-release-nist-1-8-0-contract.md` lines 91–92, 232–238). The user also asked that every open question in the journal be answered; they are, in §4.

## 2. Locked decisions (user, 2026-10-22)

| # | Final decision |
|---|---|
| D1 | A harness **pacer** (a fourth IPC peer) releases each step. Lock-step, one step = one 0.1 s KPM period. ns-3 is the only time base and the only component that blocks. |
| D2 | Gate runs: **freeze, then fail** on deadline run-out. Late or refused controls get RICcontrolFailure with cause **`control-failed-to-execute`**; the journal's `control-timer-expired` was wrong (§4 Q7). Continue-and-flag is kept for demo mode only. |
| D3 | `--handoverMode=NoAuto` for M8–R3, without `TakeUeHoControl`. |
| D4 | One additive public `LteEnbRrc` method that runs the prechecks, cancels any pending TTT, performs the handover and returns an outcome. |
| D5 | **d = 0, and no delay attribute in M8–M9.** "Transmission time" = the E2 link only, which is invisible under a 0.1 s period, so do not add it. **But** M8 adopts the apply-time contract (user answer 3 = yes): prechecks run only inside D4 at apply time; the ACK is D4's result at apply time; ledger lines are written at apply; the ledger carries receive-side fields (`rxSeq`, `rxSimTimeNs`) beside `applySimTimeNs`; replay is keyed on the receive step. "Overlap" (d = 1 for wall-time overlap) is **struck**. No plan to shorten the period or leave NoAuto. **Post-M9 realism pass, out of scope here:** a realistic whole-loop delay plus `UseIdealRrc=false`, together, for publication. R3 in this scope is a functional demo, but the work feeds published research. |
| D6 | **Patch QP on our fork so R3 repeats exactly** (scope added). The fork `github.com/thienandangthanh/ric-app-qp` is now **public**; `master` = 47a35ca = NIST's L pin. Two unrelated old branches exist; do not build on them. |
| D7 | "≥ 2 gNBs" means ≥ 2 IMSIs handed over to ≥ 2 distinct target gNBs, with ≥ 1 control delivered through a non-target agent, the eNB agent included. |
| D8 | 3 live runs + 1 replay per paced rung. |
| D9 | M8 config `--nMmWaveEnbNodes=2` (eNB 1 + gNB 2–3), 6.36 wall s per sim s. |
| D10 | Pin `simStartEpochMs` in gated runs. |
| Earlier | Any E2 node's agent may receive a control; ns-3 routes it by IMSI to the LTE master RRC. Every agent advertises RC RAN function 3. E2SM-RC v2.0 from rc @a2282ee with a pinned generator. Ladder target R3. Pacing is an opt-in ns-3 attribute; the default free-run keeps M5–M7 unchanged. Agents may push WIP to fork branches; gates clone forks anonymously at pinned SHAs (`scripts/pins.conf`). Never delete `fresh-install`. |

## 3. The pacing design being contracted

Journal §5–§8: the thread path, IPC messages (`control`, `controlAck`, `step`, the pacer `ready`/`go`/`abort`, the `hello.pacing` field), deadlines (T_start 120 s, T_gate 10 s, T_ctl 30 s, W 1 s), rollback and fallbacks, and the acceptance-criteria additions. Read §5–§8 and apply the D2 and D5 amendments above.

## 4. Answers to the journal's open questions, and new findings

| Q | Answer | Source |
|---|---|---|
| 1 kpimon → QP mapping | kpimon writes untagged `UeMetrics`/`cellMetrics` rows with wall-clock `_time` and writes them out of order. QP reads `UEReports`/`CellReports` keyed by string `ue-id`/`nrCellIdentity`, with `[pdcpBytesUl, pdcpBytesDl]` and a ≥ 10-row gate. Everything except gNB uplink is derivable from the agent's `ns3.*` fields. Recommended: the QP fork does the mapping in its reader, uses a sim-time window keyed on `ns3.simTimeMs`, sends DL first, clamps values, sends no reply without a valid serving-cell pair (closes G7), catches exceptions, and pins packages. kpimon and TS are not forked. **Stock NIST QP crashes on its training path** with today's unpinned pandas. The eNB's UE rows must be filtered out. UL = 0 crashes QP's `adfuller`, so it needs a second varying metric (e.g. `RRU.PrbUsedDl`). | `plans/reports/research-261022-1544-GH-1-kpimon-qp-mapping-and-qp-fork-patch.md` (verified: `qptrain.py:40,60`) |
| G4 (confirmed) | The agents send `e2nodeComponentRequestPart` = `"reqpart"`, so **TS's `cell_map` is empty and TS skips every control**. One 10-char cell-key format must be shared by the agent, TS `cell_map` and QP. | same report |
| 3 RLC columns | Uninitialised `LteFlowId_t` read via `m_flowId[p]` / `m_dlTxPackets[p]` `operator[]` (`mmwave-bearer-stats-calculator.cc:461-462,692`; `lte-common.cc:32`). Gate: keep excluding cols 5–6 of `DlE2RlcStatsLte.txt`. An optional fork fix is out of scope. | Explore agent, verified |
| 4 HO trace columns | `UeHandoverStartStats.txt` = `time imsi rnti sourceCellId targetCellId`; `UeHandoverEndStats.txt` = `time imsi rnti targetCellId`. No header; about 6 significant digits. A NoAuto `PerformHandoverToTargetCell` writes the same rows. A refused/no-op HO writes no start row. Gate: a start row with time ≥ apply, imsi, target, source ≠ target, then a later end row. | Explore agent (`mmwave-bearer-stats-connector.cc:646-705`), verified |
| 5 rc ack routing (live) | e2term routes 12041/12042 by (mtype, subid = ricInstanceID), falling back to subid −1. kpimon owns subids 1–5 exactly; every xApp has a −1 route and RMR keeps the last one, which rtmgr reorders on each rebuild. **0 of 10 rc acks would reach rc.** Gate on the wire only. Fix options: make rc the sole −1 owner, or put rc's instance IDs above submgr's range. | `plans/reports/probe-261022-1544-GH-1-rtmgr-route-table-live-dump.md`, verified on `p2-e2term-stash.txt` |
| 6 NIST AD | Still a wall-clock 1.6 s window on a 0.5 s schedule; it reads `UEReports` (fed by a VIAVI replay), not kpimon; a static read says it crashes at `ad_model.py:104`. Stock AD cannot drive any rung, so R2/R3 use a harness 30003 trigger. | `plans/reports/research-261022-1544-GH-1-ad-window-and-e2ap-control-ack-semantics.md` |
| 7 E2AP prose | Checked in v02.00, v03.00, v03.01, v08.00 and v09.00 (user's Zotero): the ACK = "successfully processed the requested RIC Control procedure action", identical in rules across versions; ControlOutcome optional; Cause mandatory in FAILURE; `control-timer-expired` = Call-Process Time-to-Wait only. | same report, addendum |

**D5 counsel findings adopted into scope (apply at d = 0):**
- Sort tie-break race: two same-IMSI controls through the same agent in one step are ordered by arrival. Fix: put `targetCellId` before `ctlId` in the sort key, or route such pairs through different agents.
- The agent holds N pending controls keyed by `ctlId`, has no wall-clock ack timeout, and sends FAILURE for all pending controls on `bye`/EOF.
- Acks are routed back through `viaNodeId`.
- The gate pairs request and answer by RIC request id, never by "same step".
- NoAuto still runs the outage fallback (`TriggerUeAssociationUpdate`, around `lte-enb-rrc.cc:4700`, before the NoAuto branch at `:4805`).
- A handover to the serving cell hits the X2 assert (`epc-x2.cc:693`).

Reports: `plans/reports/counsel-261022-1544-GH-1-d5-delay-{skeptic,realism,extension-point}.md`.

## 5. Decisions still open (the candidate must recommend; the user decides)

| # | Open decision | Options known |
|---|---|---|
| N1 | rc ack delivery | (a) a deployment fix so acks reach rc (rc as sole −1 owner, or an rc instance-ID offset); (b) accept rc's 2 s timeout path and gate on the wire only |
| N2 | QP packages | pin pandas 1.5.3 + numpy < 2, or port the 2 lines and pin current versions |
| N3 | QP model state | restart the QP pod each run, or train statelessly per request |
| N4 | Second VAR variable for QP (no gNB uplink) | e.g. `RRU.PrbUsedDl`; or add a real UL metric to the agent |
| N5 | Cell-key format (G4) shared by agent, TS and QP | not designed |
| N6 | Who owns "all rows for step T are in Influx" before a trigger | the pacer, or QP |
| N7 | How the Testbed fork picks up the QP fork | carry NIST's 4 QP patches in the fork, or add a 5th patch; plus the URL and `commit_hashes*.json` |

## 6. Constraints

- Every gate is scripted and clones at pinned SHAs. M9 runs unattended from `fresh-install`.
- The host keeps a 20 GB disk reserve (`/home` has 77 G free). Only `fresh-install` and `f7-rerun-green` exist.
- Never trust rc's ack log; judge on decoded wire bytes.
- The repeat gate (journal §8) applies, with the `DlE2RlcStatsLte` cols 5–6 exclusion.
- Code lives on fork branches `dev/l-release-nist180`: ns-3, oran-interface, the Testbed (agent) and now QP. The harness lives on the parent repo branch.

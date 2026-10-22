# P8: R3, TS xApp with the QP fork, UL on

**Start state:** `r2-green` with the P7 pins. **Snapshot at exit:** `r3-green`, only after the free-space check.

## Context
ns-3 is frozen at barrier T, so Influx holds no T+1 rows (K2), and kpimon writes out of order (`kp:666`). The pacer therefore certifies Influx rows for **every** seq in QP's 1600 sim-ms window before it triggers the TS xApp (N6, verifier-1723 #4). QP's first request trains inline (`main.py:104`), so W comes from a calibration run that includes that training (verifier-1723 #5). Real QP may never pick a better cell (R3 vacuity), so the trigger schedule comes from P7's offline dry run on UL-on rows.

## Requirements (contract)
R3: real TS xApp plus the QP fork, UL traffic on, fixed trigger schedule (`r3-schedule.json`).
- ≥ 1 handover applied from a QP-driven decision; every trigger's outcome (control or none) identical across C1's runs.
- N6: the pacer counts `cellMetrics` rows for every seq in the 16-step window against the IPC samples before each trigger.
- W = max(1 s, 3 × p99.9) from a calibration run including QP's first inline training.
- QP pod restarted per run; forecast hash equal across the 3 live runs; QP image digest and `pip freeze` in `verdict.json`.
- G7; eNB rows excluded; uint32 clamp.
- HandoverStart row count = applied count; zero handover rows in a null-control run.
- R2/R3: `ue-id` is the decimal IMSI; target-addressed controls recorded as deviation P1.
- C1–C9; RestartCount = 0 for rc, TS xApp, QP, kpimon, hw-go and every agent; route dumps; −1 owner recorded.
- Measure the overlay growth for the M9 budget.

## Files
- Create: `scripts/gates/gate-r3-ts-qp-fork.sh`, `scripts/gates/qp-install.sh` (Testbed installer path at `QP_SHA`), `scripts/gates/check-n6-influx-window.py`.
- Modify: `scripts/gates/pacer.py` (N6 window predicate), `scripts/run-to-m9.sh` (add gate r3).

## Steps
1. Install QP from the fork; verify Ready and RestartCount 0.
2. Calibration run with UL on; measure L including the first inline training; set W; record it.
3. Null-control run in the R3 config: 0 HandoverStart rows.
4. Run `repeat-gate.sh r3` with the fixed schedule.
5. Record the image chain sizes; compute the measured M9 overlay estimate.
6. Free-space check, then `vm-snapshot.sh create r3-green --need-gb <n>`.
7. Phase-exit checklist.

## Verify (comparison only)
- V1: `gate-r3-ts-qp-fork.sh` exits 0; `verdict.json` C1 fields all true.
- V2: `verdict.json` `qpDrivenApplied ≥ 1`; per trigger, the outcome list is identical across the 3 live runs.
- V3: `verdict.json` `forecastHashes` has 3 equal values; `qpImageDigest` and `pipFreeze` present.
- V4: `check-n6-influx-window.py` exits 0 for every trigger (16 seqs present per gNB cell before release).
- V5: HandoverStart rows = ledger `applied` lines; the null-control run has 0 HandoverStart rows.
- V6: `verdict.json` `restartCounts` all 0, `wSeconds`, `routeOwner12041`, `routeOwner12042`.
- V7: `vm-snapshot.sh list` shows `r3-green`; `evidence/p8-disk/<ts>/chain-sizes.txt` exists.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| QP inputs (as P7) | 3GPP TS 28.552 V20.2.0 §5.1.2.1.1.1, §5.1.2.1.2.1 | `5SZUBP6M` | 2026-10-22/23 |
| Target-addressed control — **recorded deviation P1** | 3GPP TS 38.300 §9.2.3; 3GPP TS 37.340 §10.5.1 | per decision record §2 | 2026-10-22 |
| UE ID — **recorded deviation P4** | E2SM common v07.00 §6.2.2.6 | `QW6VJ83M` | 2026-10-22 |

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
A red C1 is re-run only after its root cause is recorded and a change committed, then as a full fresh set. If D2 freeze-fail trips on TS xApp/QP wall jitter so often that C1 cannot pass with W as measured, that is T3, not a reason to raise W blindly.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P9.

## Risk and rollback
Risk: QP training latency exceeds W under VM load. Rollback: revert VM to `r2-green`; revert pins.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K6 (N6).** Before each trigger, the pacer certifies the `UeMetrics` rows for every triggered IMSI at seq T from each gNB agent, plus the 16 `cellMetrics` seqs. `check-n6-influx-window.py` has a UE-row case.
- **K12.** The stub QP is down before step 1, and an rtmgr dump shows exactly one 30000 receiver (QP).
- **K20 (start state).** This phase descends from `r2-green` through P6 and P7 and is not reverted. Rollback: revert to `r2-green`, then re-run M4, M5, the P6 builds and `qp-install`.

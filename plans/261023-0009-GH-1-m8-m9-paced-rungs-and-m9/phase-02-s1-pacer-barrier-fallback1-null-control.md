# P2: S1, pacer and barrier, Fallback-1, null-control equivalence, fault run (i)

**Start state:** `f7-rerun-green` with the P1 pins. **Snapshot at exit:** none.

## Context
Design D1–D10 (journal `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md` §5–§7): one pacer object in oran-interface; every emitter registers in `Start`; when the last emitter has emitted seq k the barrier is scheduled with `Simulator::ScheduleNow`; the barrier flushes samples, polls agents and the pacer socket, buffers every `control`, and waits for every node's `step{k}` and the pacer's `go`. Agents never block. ns-3 is the only time base. Deadlines start only once ns-3 is blocked. A paused ns-3 causes no E2 teardown for 900 s (journal §6). Staging: control path under `free` first (done in P1), then the barrier.

## Requirements (contract)
In scope 2: pacer + barrier (D1); deadlines T_start 120 s, T_gate 10 s, T_ctl 30 s (re-set at R0), W ≥ 1 s (re-set at R2/R3); D2 freeze-then-fail (a late control gets `control-failed-to-execute`); IPC schema v1 minor bump (`step`, `hello.pacing`); the replay sink; Fallback-1 scripted lock-step; null-control equivalence; `simStartEpochMs` pinned (D10). Demo mode (D2 continue-and-flag) is out of scope.
Acceptance: C2 (ledger checks), C7 (deadline run-out names the step; margins), C8 (null control = free-run digest; pacing opt-in; M5–M7 re-pass), forced fault run (i): an agent withholds `step{k}`; the run aborts within T_gate + 5 s; the verdict names k; no ledger line after k.

## Files
- oran-interface fork: pacer object, `step` messages, `hello.pacing` and deadlines.
- ns-3 fork: barrier hook on the sim thread, replay sink, `simStartEpochMs` attribute.
- Testbed agent: `step{k, forwarded, droppedNoSub, controls}`, ready (`seq −1`), test-only `--withhold-step k` flag for fault run (i).
- Harness: `scripts/gates/pacer.py` (host- or VM-side pacer), `scripts/gates/gate-s1-pacer-lockstep.sh`, `scripts/gates/check-ledger.py` (C2 checks), `scripts/gates/digest-run.py` (C1 digest set: ledger without `diag`, IPC `sample` lines without `hello`, traces except `DlE2RlcStatsLte.txt` cols 5–6, KPM headers and `colletStartTime`).

## Steps
1. Pacer and barrier in oran-interface and ns-3, default `free`.
2. Agent `step` messages; pacer script with T_start, T_gate, T_ctl, W.
3. Fallback-1: the pacer injects `control` directly (no RIC); replay sink feeds a ledger back.
4. Null-control equivalence: lock-step with no controls vs free-run, same `--RngRun` and `simStartEpochMs`.
5. Fault run (i) with `--withhold-step k`.
6. `gate-s1-pacer-lockstep.sh` runs 3–5 and writes `verdict.json`; re-run M5–M7 at the new pins.
7. Phase-exit checklist.

## Verify (comparison only)
- V1: `gate-s1-pacer-lockstep.sh` exits 0; `verdict.json` has `nullControlDigestEqualsFreeRun: true`.
- V2: Fallback-1 scripted run: `check-ledger.py` exits 0 (every line `applySimTimeNs − rxSimTimeNs = 0`, `rxSeq == afterSeq`, `rxSimTimeNs` = barrier time of `rxSeq`, counts match); the replay of that ledger without the RIC gives the same `digest-run.py` output.
- V3: fault run (i) aborts with wall time from barrier block to abort ≤ T_gate + 5 s; `verdict.json` field `abortStep` = k; no ledger line has `rxSeq > k`.
- V4: a control injected after the final barrier gets exactly one RICcontrolFailure `control-failed-to-execute` on the wire (decoded with the P0 decoder/tshark), not applied.
- V5: M5, M6, M7 gates exit 0 at the new pins (pacing default `free`).

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| Late control → RICcontrolFailure `control-failed-to-execute` | E2AP v03.00 §9.2.1 | `WEE5IEXF` | 2026-10-22 |
| Exactly one terminal answer per RICcontrolRequest | E2AP v03.00 RIC Control procedure (successful / unsuccessful outcome) | `WEE5IEXF` | read in this phase |
| d = 0 actuation — **recorded deviation P3** | decided in D5 | — | — |

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
If the lock-step barrier cannot be made to work and only Fallback-2 (free-run, non-repeatable M8) remains, that is an outcome change: PAUSE T3.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P3.

## Risk and rollback
Risk: a deadlock between the barrier poll and agent sockets. Rollback: `hello.pacing=free` restores M5–M7 behaviour; revert commits; VM back to `f7-rerun-green`.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K9 (V4 replaced).** P2 has no RMR sender. V4 becomes: a forced late control at the IPC level gives a ledger line `cause=late` and a `controlAck` with outcome late, and an agent unit test encodes the RICcontrolFailure `control-failed-to-execute`. The wire check moves to P3.
- **K11 (C1 reading, user 01:03 KST).** The 3 live runs are byte-equal on all components. The replay is compared with them on the ledger, IPC samples and traces. `digest-run.py` includes the per-step RC multiset, KPM headers and colletStartTime for live runs.
- **K10.** Verdicts carry `ipcDropped` (= 0), `droppedNoSub` (= 0) and `minSlack{T_start,T_gate,T_ctl,W}`.
- **K19.** V6: the free-run digest at the P2 pins equals P1's.

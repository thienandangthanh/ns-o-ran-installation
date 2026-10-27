# Codex plan gate, amendment A1 (M8–M9)

Rule: Codex challenge and audit, plan gate, adopted for this goal as CX-1 to CX-4 (`goal-packet.md`, A1, approved by the user 2026-10-27 23:24 KST). Codex ran read-only (`task --fresh --effort high`), with no edits and no SSH, VM or network access. Briefs are in the session scratchpad and contain no secrets. Runs counted against the A1 cap of 4: round 1 = 1, round 2 = 2.

Classification uses the warmup taxonomy: `mitigation-within-contract` (applied), `preflight-required`, `blocker`, `outcome-change-request` (would be T9 / Decision required). I verified every finding at its cited lines before triage.

## Round 1 (2026-10-27 23:35 KST; verdict: needs-attention, 7 findings)
| # | Finding (Codex) | Verified at | Class | Decision and change |
|---|---|---|---|---|
| 1 | N6 asks for the triggered UE's row "from each gNB agent", but UE membership is disjoint across gNBs, so healthy triggers would never certify | phase-08b Requirements (from K6 of old P8) | mitigation-within-contract | Accept. N6 is now membership-aware: every expected cell row, plus exactly the UE rows the agents' IPC samples at T list; serving-cell consistency and no in-progress handover at T; fixtures for healthy disjoint membership and a missing expected row (V9) |
| 2 | `gate_id` maps `gate-r3p-…` to `r3`, and the protection helper knows `r3-green`, not `r3p-green` | `scripts/vm/vm-common.sh:63` (`^gate-([a-z]+[0-9]+)`) | mitigation-within-contract | Accept. Files now include the `gate_id` regex `^gate-([a-z]+[0-9]+[a-z]?)-` with the K24 self-test extended to `r3p`, and protection of `r3p-green` (plus `r2-green` under substitution 4); V9 |
| 3 | Substitution 4 can be reached from missing data or a schedule-construction failure, so it could turn a defect into an authorized scope cut | phase-08b step 4 | mitigation-within-contract | Accept. The candidate domain is pre-registered; the dry run is classified as invalid (Failure Protocol), valid with a schedule, valid with no handover (substitution 4, with a committed `r3p-substitution4.json` of evidence and config hashes), or valid with a candidate but no formable schedule (T3) |
| 4 | Re-setting W for R3′ would break R2's gate, whose `cfg_ok` requires W provenance under `evidence/r2/` | `scripts/gates/gate-r2-ts-stub-qp.sh:88` | mitigation-within-contract | Accept. R3′ gets its own `r3pConfig.W_s` and provenance; R2's `deadlines.W_s` stays; V9 re-checks R2 `cfg_ok` against the final config |
| 5 | A watchdog that trips at 25 GB cannot prove "≥ 25 GB throughout": a detected crossing is already a violation, and a dip between polls is missed | `scripts/vm/host-disk-watchdog.sh:60`; phase-09 A1 runner | mitigation-within-contract (stricter, contract unchanged) | Accept. Preventive trip point 25 + h GB, h measured from growth rate × (poll + detection + shutdown), recorded in `m9-budget.md`; fixtures for each fail case |
| 6 | The A1 budget subtracts dev overlays already counted in host free space, contradicting P0's corrected K2 formula | phase-00 K2; phase-09 A1; plan.md checklist item 5 | mitigation-within-contract | Accept. Both now use K2's accounting with the floor 25 + h |
| 7 | The pre-ship audit can pass without covering committed changes or the fork source diffs (pin ranges are only gitlinks in the parent) | phase-09 A1 Codex audit | mitigation-within-contract | Accept. The controller writes an audit inventory (parent changes, plus local fork diffs for any changed pin, fetched by the controller beforehand); Codex reports coverage per item; unreviewed items are ledger gaps |

Escalated: none. Rejected: none.

## Round 2 (2026-10-27 23:41 KST; verdict: needs-attention, 3 findings; round-1 fixes 1, 2, 4 and 6 confirmed sufficient)
| # | Finding (Codex) | Verified at | Class | Decision and change |
|---|---|---|---|---|
| R2-1 | The candidate domain excluded windows with missing or duplicate rows, so bad data could be censored before classification and a defect could still reach substitution 4 | phase-08b step 2 (round-1 text) | mitigation-within-contract | Accept. The domain is derived only from configuration and must be non-empty; any missing, duplicate, Influx ≠ IPC or N6 failure anywhere in it makes the dry run invalid; fixtures in V9a; M9 validates the committed `r3p-substitution4.json` against the frozen config hashes before it accepts R2 as the top rung (phase-09 A1) |
| R2-2 | Headroom h covered one poll, but the stale-heartbeat allowance is two periods, and nothing stopped the VM gate when the watchdog died | phase-09 A1 runner (round-1 text) | mitigation-within-contract | Accept. Two bounded stop paths (low-space trip; runner-side stale-heartbeat cancellation and shutdown); h from the longer path; a fixture that kills the watchdog during a dummy gate unit |
| R2-3 | Coverage gaps could still be recorded while the ledger says `Status: complete` | phase-09 A1 Codex audit and V5 (round-1 text) | mitigation-within-contract | Accept. Completion requires every material inventory item to be marked reviewed, by Codex (main or spare run) or, after `Codex skipped`, by a `code-reviewer` subagent with the same inventory; V5 checks this |

Escalated: none. Rejected: none. No finding touched a user ruling or an acceptance signal, so there was no T9 / Decision required.

Codex runs used for A1: 2 of 4 (plan gate). Remaining: pre-ship 1 (P9) and spare 1.

Status: complete

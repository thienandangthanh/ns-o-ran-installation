# Decisions: M8–M9 open questions before re-issuing the goal (2026-10-27 21:55 KST)

Source of the questions: `plans/handoffs/m8-m9-open-questions-before-goal-reissue-20261027-2120.md`. The rulings below are the user's own words, given in chat at 21:55 KST. Kongming's counsel is not part of them.

| # | Question | User ruling | Effect on the plan |
|---|---|---|---|
| 1 | How QP trains under the constant gNB-cell DL | **Superseded by S1** (below): after looking back at the original scenario, the user chose R2 + R3′ and deferred QP. | Brainstorm: `plans/reports/brainstorm-261027-2155-GH-1-qp-training-scenario-fit.md`. P7 step 6 stays blocked until the user rules. |
| 2 | Disk at Stop B (watchdog trips at 25 GB) | "I'll try to free up but not now." Update at 22:28 KST: the user cleaned the disk, and host `/home` free is **63 G** (verified with `df -h /home`; it was 38 G). | Amend P9 to budget for 25 GB plus measured growth (Codex F02). Shifting the last estimate (−23 to −25 GB at 38 G) by +25 GB gives about +2 to 0 GB against the 20 GB floor, which is **about −3 to −5 GB against the 25 GB watchdog**. That is an estimate, to be re-measured at P8/P9. Stop B still reports the exact GB to free, and P10 starts only once the projection is ≥ 0. |
| 3 | The r2 single red: fresh one-fix budget after the release? | Confirmed. | On release: phase-06 Failure Protocol with kongming, one guided fix, then a fresh green r2 single (Codex F06). |
| 4 | History of commit `f2138f0` (239 force-added evidence files) | Keep it public. | No history rewrite. Codex F09 (export must fail closed) still applies to future exports. |
| 5 | Add `ric-app-qp` to `.gitmodules` | Not now; `pins.conf` is enough. Defer until after the goal is met. | P7 adds only `QP_URL`/`QP_SHA` to `scripts/pins.conf`. `ric-app-qp/` stays a plain clone excluded through `.git/info/exclude`. |
| 6 | T8 release | Release T8 when the goal is re-issued. | On resume, update the records that cite `901f8c5` to `381a824` (same tree `aece41f6`). |

## Unresolved
- Ruling 1 is superseded by S1 below.

## Rulings on the closed-loop simplification (2026-10-27 23:04–23:09 KST)
Source: `plans/reports/brainstorm-261027-2241-GH-1-simplify-closed-loop-migration-proof.md` (best-of-5 brainstorm, debated with two Codex perspectives).

| # | Question | User ruling | Effect |
|---|---|---|---|
| S1 | Scope of the closed-loop proof | "As recommended": R2 + R3′ (a harness predictor reads per-cell DL from Influx by sim time and drives the TS xApp), with stop-at-R2 pre-authorized as the fallback if the R3′ dry run yields no handover | Supersedes ruling 1 (QP training option): the QP fork (P7) and the real-QP R3 (P8) are deferred to a later goal, not deleted. M9 = M0–M7 + R0–R2 + R3′ (or R2 on fallback), top rung at full C1 and equal to the committed reference. The locked goal-packet needs an amendment that the user approves. |
| S2 | N4 | Keep the N4 counters (`DRB.PdcpSduVolumeUL/DL`) and the UL flag as an opt-in feature; drop the QP-only checks (K18 one-shot Influx dump, V5 window predicate, V6) as a user-ruled scope change | Kept: V1 lint, V2 flag-off digest unchanged, V3 counter totals (judge hardened per F04), V4 regression chain, and Influx = IPC equality for the counters R3′ reads (the non-QP part of F05). |
| S3 | A more complex scenario (portability smoke, e.g. scenario-one) | Defer to the next goal | Not in this goal; docs name the scenario-zero coupling (`agents-ns3-run.sh:40`; pacing/ledger globals only in `scenario-zero.cc`). |
| S4 | M9 free-disk acceptance | Agree: ≥ 25 GB, matching the watchdog trip point (F02) | Replaces the contract's ≥ 20 GB floor for M9 acceptance; P9 budgets 25 GB plus measured growth. |

## Contract amendment A1 (2026-10-27 23:24 KST, through ak:goal-warmup)
| # | Question | User ruling | Effect |
|---|---|---|---|
| S5 | Adopt the Codex challenge-and-audit rule into this goal, and lock the amended contract | "Approve" (ask_user approve/edit/abort) on contract A1: S1–S4 plus CX-1 (Codex failure or refusal is not T8; print `Codex skipped: <reason>`), CX-2 (new trigger T9 for a Codex finding that needs a user ruling), CX-3 (cap 4 runs: plan gate 2 before re-issue, pre-ship 1 at P9, spare 1; the three earlier runs of 2026-10-27 not counted), CX-4 (Codex read-only, no SSH/VM, no secrets, controller only) | `goal-packet.md` rewritten as A1 (old text at `0230254`); `plan.md` amended (P7/P8 deferred, P8′ = `phase-08b-r3prime-ts-xapp-harness-predictor.md`, T9, Codex cross-cutting rule, disk 25 GB for M9); Amendment A1 blocks in phase-06, -09, -10; deferral banners in phase-07, -08. Ready still needs the Codex plan gate (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reports/codex-plan-gate.md`, `Status: complete`) and the user's final-summary confirmation. |

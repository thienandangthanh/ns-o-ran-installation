# Decisions: user rulings on the P6 single-mode restart-judge pause (2026-10-27 09:55 KST)

Pause: PAUSE T6, journal `docs/journals/2026-10-27-m8-m9-p6-pause-t6-single-mode-restart-judge.md` (section 6), counsel `plans/reports/kongming-261027-0245-GH-1-p6-pause-t6-single-mode-aggregate-restart-check.md` (judge fix, U1–U3) and `kongming-261027-0215-GH-1-p6-n4-sdu-header-rule-and-double-count-design.md` (N4). The user ruled "decide as advised" on the explanation of the pause; the rulings below are the user's, and kongming's counsel is not user approval.

## Rulings
1. **U1: the edit to the r0 and r1 judges is approved** (the fourth change to code r0/r1 execute since their C1). The aggregate restart check judges exactly the runs each mode makes. The regression is r0 single, then r1 single, at the new harness SHA. Running the regression as `--mode c1` instead was rejected: it only moves the edit to P6 V4 and M9, which use single mode, and costs about four times the VM time.
2. **U2: the T6 budget is fresh after the release** (the literal reading of the 2026-10-26 22:30 ruling 1). The approved fix is part of the release, not the guided fix, so the first failed Verify after the release (r0 single, r1 single, and so on) gets one kongming-guided fix.
3. **U3: the TS xApp and stub are not added to the r0/r1 `restartCounts` fact map now.** The edit stays minimal; the judge already covers every ricxapp pod row. It goes on the Stop B list.
4. **N4: the MN-hosted PDCP volume credited to the en-gNB cell is a new recorded deviation, P9,** not a widening of P7. P7 is about the PDCP header format (ns-3 uses the E-UTRA PDCP header on the EN-DC bearer; 3GPP TS 37.340 §4.2.2 requires NR PDCP). P9 is about the measured object: ns-3 has no gNB PDCP for EN-DC UEs (the PDCP is the LTE master node's `McEnbPdcp`), so `DRB.PdcpSduVolumeUL` and `DRB.PdcpSduVolumeDL` report the master node's PDCP SDU volume under the en-gNB cell, which 3GPP TS 28.552 measures at the NRCellCU. Recorded, not fixed (post-M9 realism pass). The N4 code is the same either way; the counter may be pushed once the plan text for P6 V3 and V5 carries kongming 0215's corrections (V3 as a flag-gated per-PDU audit, V5 as the K17 QP predicate).
5. **Carried over, unchanged, for Stop B:** T6 budget per Verify step or per release for P6's later steps; the rule "RestartCount = 0 is judged literally; a gate reaches it by recreating pods, never by filtering; only a boot-explained restart may be cleared as a precondition"; option D (r0/r1 reset the TS xApp and stub per run). The history of commit `f2138f0` stays open (no advice was given on it).

## Changes made (harness, this commit)
| File | Change |
|---|---|
| `scripts/gates/rc-lib.sh` | New `rc_restarts_zero_all <run>...`: each named run's after-snapshot exists, is non-empty and passes `rc_restarts_zero`; an empty run list is red. Header index line added. |
| `scripts/gates/gate-r0-rc-scripted.sh` | `restart_all_zero` (a `cat` of the c1-only `k9-after-pods.tsv` under pipefail) replaced by `rc_restarts_zero_all` over `live1..NLIVE`, plus `k9` in c1. Check name `r0_restart_counts_all_zero` and fact `restartCountsAllZero` kept; the fact line sends the helper's output to `/dev/null`. |
| `scripts/gates/gate-r1-rc-multi-control.sh` | The same, with `f2` and `r1_restart_counts_all_zero`. |
| `scripts/gates/lint.sh` | Self-test of the new judge (single list passes; a missing or empty snapshot, an empty list and a restart count of 1 fail; the fact form is one word) and a static rule against a silenced `cat` of a named evidence file into a pipe. |

`gate-r2-ts-stub-qp.sh` is unchanged (it uses a glob and is correct).

## Verification so far
- `scripts/gates/lint.sh`: ok.
- Mutation check: with the old r0 line restored, the new static rule flags `gate-r0-rc-scripted.sh:357` and lint fails.
- Back-test on committed evidence: R0 C1 `073520Z` [live1–3, k9] → 0; R1 C1 `084654Z` [live1–3, f2] → 0; r0 `171731Z` [live1] → 0; r0 `165654Z` [live1] → 1 (stub `rrkd6` and TS xApp `f57mf` at restart count 1); r0 `171731Z` [live1, k9] → 1 ("k9: no after-snapshot"). Every committed verdict is reproduced. This supports the fix; it does not replace the fresh runs.
- Not run yet on the VM: r0 single and r1 single at the new SHA. They run when the user re-issues the goal.

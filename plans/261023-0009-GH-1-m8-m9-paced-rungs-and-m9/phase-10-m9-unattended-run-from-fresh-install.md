# P10: M9, one unattended run from fresh-install

**Start state:** `r3-green` exists (check first); then revert to `fresh-install`. **Snapshot at exit:** none, unless the budget allows a final one under a new name.

## Requirements (contract)
M9: revert `fresh-install`, one invocation, no prompts, exit 0. `verdict.json` lists M0–M7 and R0–R3 with pass/fail and pins. R0–R2 each pass one live run (C2–C9); R3 is the highest green rung, passes its full C1, and its ledger and digests equal the committed dev reference. Host free ≥ 20 GB throughout (watchdog). Then: handoff report, journal, README and `docs/` updated with the run commands and verified against the run log, and a run report listing deviations P1–P6, the Q2 result and any substitution applied.

## Files
- `scripts/run-to-m9.sh` (final), evidence under `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/`.
- `README.md`, `docs/deployment-guide-l-release.md`, `docs/system-architecture-l-release.md` (RC path, pacing, UL/DL rows, QP fork, deviations).
- `plans/reports/handoff-<ts>-GH-1-m8-m9-done.md`, `plans/reports/run-report-<ts>-GH-1-m8-m9-deviations.md`, `docs/journals/<date>-m8-m9-m9-green.md`.

## Steps
1. kongming (opus) go/no-go before starting (the Stop B advice counts if the pins are unchanged since).
2. Check: `vm-snapshot.sh list` shows `r3-green`; `m9-budget.md` projection ≥ 0; host free ≥ 20 GB.
3. Update the resume card ("P10 running, started <ts>, VM reverting to fresh-install").
4. `scripts/vm/vm-snapshot.sh revert fresh-install`.
5. Run `scripts/run-to-m9.sh --harness-sha <frozen> --run-prefix n --no-snapshots` through the harness's background facility, with the global wall deadline and the disk watchdog. Update the resume card when it starts and at each gate boundary seen in the log.
6. Compare R3 with `reference/r3/`.
7. Write the run report, the handoff report and the journal; update README and docs; verify every command in them against the run log; push.
8. Phase-exit checklist; then print the M9 verdict summary and the line `GOAL DONE M9`.

## Verify (comparison only)
- V1: `run-to-m9.sh` exit code 0.
- V2: `verdict.json` lists `m0`…`m7`, `r0`…`r3` each with `pass`, and `pins`; `highestGreenRung = r3`.
- V3: `verdict.json` `r3.c1` all true; `r3.equalsReference = true` (byte-equal digests vs `reference/r3/`).
- V4: `watchdog.json` `minHostFreeGb ≥ 20`; no `watchdog-tripped.json`.
- V5: the run report lists P1, P2, P3, P4, P5, P6 and N5, plus the Q2 count and substitution states.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| Run report deviations P1–P6, N5 | as recorded in the decision record §6 and the 00:05/00:14 amendments | — | — |

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
A watchdog trip is T2. An M9 re-run needs a fresh `fresh-install` revert and must use a prefix whose names do not exist.

## Phase exit
Run the plan's phase-exit checklist, then print `GOAL DONE M9`.

## Risk and rollback
Risk: the disk budget is short mid-run (watchdog stops it, T2). Rollback: revert to `r3-green` for diagnosis; `fresh-install` is never touched.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K8.** V3 compares `reference/r3/equal/` byte for byte; `recorded/` is diffed and reported, not gated.
- **K14.** Before launch, `git diff --quiet <frozen> HEAD -- scripts tools` exits 0.
- **K15.** The watchdog trips at 25 GB, so V4 (`minHostFreeGb ≥ 20`) is meaningful.
- **K1.** The M0 probe pair inside M9 (`m0-probe-n`, `m0-branch-n`) is allowed by the 01:03 KST rule.
- **K21.** The final output line is `GOAL DONE M9 verdict=<path to verdict.json>`, printed as Claude's own message, not tool output.
- **P7.** V5 lists P1–P7 and N5.

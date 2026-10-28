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

## Amendment A1 (binding, 2026-10-27; contract approved 23:24 KST; overrides any conflicting text above)
- **Start state:** the top rung's green snapshot exists (`r3p-green`, or `r2-green` under substitution 4).
- **V2:** `verdict.json` holds exactly the pre-registered step set (`m0`…`m7`, `i0`, `r0`, `r1`, `i2`, `r2`, then the R3′ steps unless substitution 4), each `pass`, with `pins`; `highestGreenRung = r3p` (or `r2` under substitution 4); no `notM9` flag.
- **V3:** the top rung's `c1` all true and `equalsReference = true` against `reference/r3p/equal/` (or `reference/r2/equal/`).
- **V4:** `watchdog.json` `minHostFreeGb ≥ 25`, heartbeat never stale; no `watchdog-tripped.json`. Step 2 checks host free ≥ 25 GB plus the measured M9 growth.
- **V5 / run report:** lists P1–P9 and N5, the Q2 count, every substitution state (1–4), and the descoping (S1: QP fork and real-QP R3 deferred; S2: K18/V5/V6 dropped; S3: portability smoke in the next goal).
- **Docs:** README, `docs/deployment-guide-l-release.md` (run-to-m9, the manual rc gRPC and TS xApp loop, the scope statement) and `docs/system-architecture-l-release.md` (fix the stale §8 "not implemented" line; RC path, pacing, UL/DL rows, R3′ predictor; QP fork deferred) plus a "run your own experiment" section: `agents-ns3-run.sh:40` hard-codes the `*-scenario-zero-*` binary; pacing and ledger globals live only in `scenario-zero.cc`; the N5 key is digits only up to cellId ≤ 9; pacing is opt-in; QP/AD need a live-data adapter. Every command verified against the M9 log.
- **Final line:** `GOAL DONE M9 verdict=<path to verdict.json>` (K21).

## Stop B mapping to the A1 runner (records only; the same signals, none weakened; listed for the user's ratification at Stop B)
Source: `plans/reports/kongming-261028-1540-GH-1-stop-b-go-no-go-p10.md`. The runner writes no `watchdog.json`; every signal is read from `evidence/m9/<ts>/verdict.json`, which `scripts/m9-verdict.py` writes fail-closed.
- **Step 2:** `vm-snapshot.sh list` shows `r3p-green`; `df -BG /home` ≥ T = 84 GiB (`m9-budget.md`), else PAUSE T2 without reverting.
- **Step 6:** read the r3p gate's own `equalsReference` (its `--reference` compare against `reference/r3p/`), which the verdict carries.
- **V2:** "no `notM9` flag" means `notM9: false`; `exactStepSet: true`.
- **V4:** `minHostFreeGb` ≥ 25; `watchdogAlive.maxAgeS` ≤ 2 × `intervalS` with `lastCheckEpoch` within 2 polling periods of the end; none of `watchdog-tripped.json`, `watchdog-lost.json`, `wall-deadline.json`, `monitor-lost.json` present. K15's trip at 25 is superseded by the A1 trip at 29 GiB (25 + h).
- **Pre-flight (before step 4), in order:**
  1. resume checks: the chain is fresh-install > f7-rerun-green > r0-green > r2-green > r3p-green, with no `n[0-9]-*` or `m0-*-n*` names;
  2. the worktree equals F for `scripts`, `tools` and the reference, and F is on origin;
  3. the pins are re-checked with `ls-remote`;
  4. `lint.sh`, the runner self-test and the verdict self-test all pass;
  5. record Debian trixie's tshark version (4.4.19-0+deb13u1 at Stop B);
  6. no runner, watchdog, monitor or vm-exec process runs on the host, and no `gate-*` unit is active on the VM;
  7. `df -BG /home` ≥ 84 (88 with the margin), else PAUSE T2;
  8. update the resume card, commit and push;
  9. revert `fresh-install` (the runner never reverts, and `gate-m0-host.sh` would otherwise pin the active overlay as its probe's backing file), re-measure df (about +2.6 GiB), confirm `r3p-green` is still listed, and commit a "P10 start" projection row ≥ 0;
  10. run `scripts/run-to-m9.sh --harness-sha e0a6ac5ee0b4824038c22e39d467fc1f714d0d13 --run-prefix n --no-snapshots` in the background and record the start epoch and deadline (wall 20,199 s);
  11. when it exits, apply V1–V5 as mapped above.

## Launch-route amendment (binding; user rulings 2026-10-28 22:10–22:35 KST, `plans/reports/decisions-261028-2219-GH-1-p10-attempt-3-memory-gate-and-release-order.md`; overrides step 5 and Stop B items 7 and 10 above)
- **Host:** rebooted; only Orca and one Claude Code session started with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` (recorded with `printenv`). No browser or second Claude/Codex session during the run.
- **Release order:** resume checks; pre-flight 2–6 at F′ (plus: no `m9-*` user unit loaded; no `<prefix>[0-9]-*` or `m0-*-<prefix>*` names); resume card; route smoke (a) `systemd-run` of `scripts/vm/m9-runner-selftest.sh` as `m9-<prefix>-smoke` exits 0, (b) client-kill check (`systemd-run --user --wait --unit=m9-<prefix>-clientkill sleep 120`, kill the client, unit still `active`, then stop it); revert `fresh-install`; leaked-overlay checks 1–5 and deletion of the former active overlay only; `df -BG /home` ≥ 84 else PAUSE T2; `r3p-green` listed; access smoke through the same route (`virsh domstate`, `ssh -o BatchMode=yes oran-kvm-2404 true`, `git ls-remote origin HEAD`) exits 0; memory gate MemAvailable + qemu RSS ≥ 23 GiB else PAUSE T3; projection row; launch. A red smoke means launching per step 5 as written (bare background shell, env var on), not a PAUSE.
- **Launch (step 5):** the runner runs as the transient user unit `m9-<prefix>.service`, started from the worktree root through the Claude Code background facility with `systemd-run --user --wait --unit=m9-<prefix> --same-dir -E PATH -E SSH_AUTH_SOCK -E GIT_TERMINAL_PROMPT -p KillMode=mixed -p TimeoutStopSec=180 -p OOMPolicy=continue -p StandardOutput=append:<plan>/evidence/m9/runner-<prefix>.log -p StandardError=inherit <worktree>/scripts/run-to-m9.sh --harness-sha <F′> --run-prefix <prefix> --no-snapshots` (never `--collect`, `--pipe`, `--pty`, `--scope` or `-q`). That command's exit status is V1, cross-checked against the unit's journal result.
- **A lost client is not a stop:** never relaunch; re-attach with a journal/`systemctl --user show` waiter; V1 is then the unit's main-process status. Operator stop is `systemctl --user stop m9-<prefix>.service`. The post-reap cleanup (`vm_stop_gates`, `vm_shutdown`) runs only when the unit is inactive.
- **Records:** `free -g` and `/proc/pressure/memory` at each boundary (facts, never gates); after exit, move the log to `evidence/m9/<run_ts>/runner.log` and `reset-failed` a failed unit.

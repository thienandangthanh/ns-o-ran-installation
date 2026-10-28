# Handoff: M8–M9 done (amendment A1)

**M9 is green.** One unattended run from `fresh-install` exited 0 with all 14 pre-registered steps passing. R3′, the TS xApp driven by a harness predictor that reads per-cell DL from InfluxDB, is the top rung: its full C1 passed and it equals the committed reference. Minimum host free was 59 GB, and the watchdog stayed alive.

- Verdict: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/verdict.json`
- Run report (deviations P1–P9 and N5, Q2, substitutions, descoping, bring-up remedy): `plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md`
- Journal: `docs/journals/2026-10-29-m8-m9-m9-green.md`
- Frozen harness F″ `39b3ba21d46d9e347d14d2841a8abe1ace1ccb05`, pins in `scripts/pins.conf` (Testbed `c6d1434a`, ns-3 `ba954440`, oran-interface `96efc40e`, e2sim `2209995a`), all pushed.

## How to reproduce
README "Reproduce M9" and `docs/deployment-guide-l-release.md` §3 "M9". Before reverting, have at least 84 GiB free on `/home` (`m9-budget.md`). On a host where Claude Code runs the job, start it with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` and launch the runner as a `systemd-run --user --wait` unit (phase-10 Launch-route amendment).

## State left behind
- VM `ubuntu24.04` is running on the post-M9 overlay. Snapshots: `fresh-install` > `f7-rerun-green` > `r0-green` > `r2-green` > `r3p-green`, plus the M0 probes `m0-probe-n10280921`, `m0-probe-o10281122`, `m0-probe-p10281349` and `m0-probe-q10281658`. Host `/home` free: 59 GB.
- No `gate-*` unit, agent container or ns-3 process runs on the VM, and no runner, watchdog or `m9-*` unit runs on the host.
- The next revert will leak the active overlay again (see the follow-ups); delete it only after the checks of `decisions-261028-2014`.

## Follow-ups after M9 (recorded; not done in this goal)
1. **`finish()` orphan gap** (user ruling 6, 2026-10-28): drop the `kill -0` guard before `vm_stop_gates` in `scripts/run-to-m9.sh`, and correct the TERM trap message.
2. **revertDisks leak**: `gate-m0-host.sh`'s probe branch create and delete untrack the active overlay, so every revert after an M9 run leaks it (16, 36.5 and 41.5 GB so far). Fix the probe, or make the release order delete the leak.
3. **`rtmgr_push_acked` can report a false OK**: rtmgr logs "successful … OK" for endpoints that never read the table. Judge on receiver evidence (`rt_reader_ok`) instead.
4. **Root cause of the stuck RMR route readers** in e2mgr and submgr after a cold boot or a fresh install (L-release images). F″ remedies it; it fired once in M9 (m1). Worth an upstream bug report once the trigger is isolated.
5. **Watchdog headroom h**: the measured growth rate implies h ≈ 9 (trip ≈ 34) against the frozen h = 4 (trip 29); adopt it in the next budget.
6. **Deferred by A1**: the QP fork (`381a824`) and R3 with real QP; K18/V5/V6; the scenario-one portability smoke and a scenario-agnostic harness (S3); the realism pass for P1–P9; the stale parent submodule gitlinks.
7. Commits `f2138f0` (675 evidence files force-added earlier): a history rewrite is pending the user's approval.

## Unresolved questions
1. The A1 interpretations listed at Stop B have no explicit ratification on record. Should they be ratified?
2. Should the "follow-ups" go into the next goal's contract?

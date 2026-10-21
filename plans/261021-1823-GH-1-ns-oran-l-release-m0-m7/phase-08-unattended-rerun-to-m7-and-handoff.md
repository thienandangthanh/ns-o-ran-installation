# P8 — Unattended re-run from fresh-install to M7; docs; pre-M8 gate

## Requirements
1. **Freeze the pins:** `scripts/pins.env` holds the final pushed SHA of every fork branch and of the harness repo.
2. **Disk budget.** Compute the host free space needed (bytes used per gate, recorded since P0) plus 20 GB.
   - If `/home` lacks it, STOP and apply the user's decision on deleting gate snapshots `l1…l7`.
   - `fresh-install` is never deleted. `m0-probe` and `l0-preflight` are also deleted only if allowed.
3. **Run unattended from the host:**
   1. `vm-snapshot.sh revert fresh-install`
   2. `scripts/run-to-m7.sh --pins scripts/pins.env`
   3. This clones from GitHub at the pinned SHAs and runs gates M0→M7 back to back, with no human input. Each gate's `verdict.json` is collected.

   P2's kpimon patch step and P3-dependent images are all built by script inside this run.
4. Run gate snapshots only where the budget allows; `f7-rerun-green` at the end is required.
5. **Docs.**
   - Update `README.md` with an L/NIST section: how to run `run-to-m7.sh`.
   - Update `docs/` (deployment guide and architecture note for Approach A).
   - Verify every command in them against the re-run log.
6. **Pre-M8 planning-gate handoff** in `plans/reports/`:
   - M4 timing numbers
   - M7 load observations
   - open questions for pacing (lock-step T, IPC→ns-3 thread control path, keep-alive vs lock-step, option B)
   - a pointer to the deferred M8/R0–R3/M9 work

   **Do not start M8.**

## Gate (finale)
- All 8 `verdict.json` files (M0…M7) are `pass`, from one unattended invocation, with SHAs matching `pins.env`.

## Risks
- **Flaky gates** (pod readiness, nexus3 pulls): bounded retries inside gates only, each retry logged. A flaky pass is reported as such, not hidden.

## Review amendments (contract-preserving review, 2026-10-21)
- **K12: harness SHA.** Pass it as an argument to `run-to-m7.sh`; a file cannot pin its own commit. `pins.env` holds only the 4 fork SHAs. The clone path is the one M0 proved from `fresh-install`.
- **K4: naming and fallback.** Re-run snapshots use the `f*` prefix. If space must be freed, apply the user's fallback decision.
- **K15: version drift.** Diff the resolved package and image versions against `evidence/m1/versions.txt` from the dev run. Report any drift as part of the verdict, not as a hidden pass.
- **K6: reboot cadence.** Reboots happen at the same gate boundaries as the dev run, even where a snapshot is skipped.

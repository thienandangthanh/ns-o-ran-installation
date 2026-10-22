# P9: Freeze pins, commit the dev reference, compute the M9 budget; then Stop B

**Start state:** `r3-green`. **Snapshot at exit:** none.

## Context
M9's R3 must equal the committed dev reference, which is valid only at frozen pins. An M9 revert to `fresh-install` removes only the active overlay; the dev chain stays on disk (P5 housekeeping README, Lesson), and deleting a non-leaf snapshot frees almost nothing. Inferred M9 overlay ≈ 40 GB (measured at P8). Host headroom at warmup: 75 G free, 20 GB floor.

## Requirements (contract)
M9 groundwork: every fork SHA and the harness SHA frozen; the R3 dev reference regenerated at the frozen pins if anything changed since P8; reference digests committed; M9 disk and wall budget from measured data. No snapshot is deleted; any deletion the budget needs is a T1 user ruling at Stop B.

## Files
- `scripts/pins.conf` (frozen), `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3/` (ledger digest, trace digests, IPC digests, KPM header digests, decoded-RC multiset digest, forecast hash, QP image digest, `pip freeze`), `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md`.
- `scripts/run-to-m9.sh` (final gate table with timeouts from measured durations; global wall deadline = 1.5 × Σ measured dev gate durations).

## Steps
1. Freeze: record every fork branch head and the harness SHA; confirm all pushed; set `pins.conf`.
2. If any SHA differs from the P8 run, re-run `repeat-gate.sh r3` at the frozen pins and use its output as the reference.
3. Commit the reference digests.
4. M9 budget: host free now − (dev overlays that remain) − M9 overlay (P8 measurement) ≥ 20 GB; wall budget per gate and global.
5. **Stop B:**
   - journal `docs/journals/<date>-m8-m9-stop-b.md` with the budget table and go/no-go evidence;
   - kongming (opus) go/no-go on P10 and the frozen pins, as an advice report next to the journal;
   - if the budget is negative, list the options (free space outside VM images; a specific snapshot deletion, each as its own T1 approval with the space it frees, measured);
   - update the resume card to "next: P10" and push;
   - print `PAUSE B evidence=<path> journal=<path>` and call no further tool.

## Verify (comparison only)
- V1: every SHA in `pins.conf` equals `git ls-remote` of its fork branch; the harness SHA is on `origin`.
- V2: `reference/r3/` files exist and `sha256sum -c reference/r3/SHA256SUMS` exits 0.
- V3: `m9-budget.md` contains a projection row with a numeric value and the sign.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| none new (freeze and budget only) | — | — | — |

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

## Phase exit
Run the plan's phase-exit checklist, then Stop B as in step 5.

## Risk and rollback
Risk: the regenerated reference differs from P8's (non-determinism at frozen pins); that is a red C1, with root cause before any re-run. Rollback: unfreeze pins (revert the commit).

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K8 (reference split).**
  - `reference/r3/equal/` holds what M9 must match: ledger, IPC, traces, KPM headers and colletStartTime, the RC multiset, forecast hashes and `pip freeze`.
  - `reference/r3/recorded/` holds what M9 only reports: the QP image ID, every deployed image ID and the base-image digest.
- **K14 (order).**
  1. Finalize `run-to-m9.sh` and `rung-config.json`, then commit.
  2. Freeze the pins.
  3. Regenerate and commit the reference.
  - "Differs" means the fork pins plus the gate inputs that R3 reads: pacer, scenario, schedule and rung-config.
- **K2 (step 4).** Use the corrected projection formula from P0.
- **Snapshot rule (01:03 KST).** If the budget needs space, the run may delete `r0-green` and/or `r2-green` (only after their evidence is archived; each deletion logged with the space it freed), never `fresh-install`, `f7-rerun-green` or `r3-green`. A shortfall that this cannot cover is ruled at Stop B.

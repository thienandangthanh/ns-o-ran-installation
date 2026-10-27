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
- **Snapshot rule (01:03 KST).** If the budget needs space, the run may delete `r0-green` and/or `r2-green` (only after their evidence is archived; each deletion logged with the space it freed), never `fresh-install`, `f7-rerun-green` or `r3-green`. A shortfall that this cannot cover is ruled at Stop B: the Stop B report states the exact number of GB the user must free before P10 (user, 01:30 KST), and P10 starts only once the projection is ≥ 0.

## Amendment A1 (binding, 2026-10-27; contract approved 23:24 KST; overrides any conflicting text above)
Source: `goal-packet.md` (A1), Codex findings F02, F07, F08, F10 (accepted), verifier caveat 7 (`--reference` mode).
- **Start state:** `r3p-green` (or `r2-green` under substitution 4). **Top rung** = R3′, or R2 under substitution 4; every `r3`/`reference/r3/` above reads as the top rung's (`reference/r3p/` or `reference/r2/`). The QP image, forecast hash and `pip freeze` items are dropped from the reference (deferred with P7/P8).
- **Runner (F07, F08), finalized before the freeze (K14 step 1):** `run-to-m9.sh` ORDER becomes `m0…m7 i0 r0 r1 i2 r2` plus the R3′ steps (or none under substitution 4); i3/r3 removed. The verdict passes only on the exact pre-registered step set with every step pass, the top rung's C1 pass and `equalsReference = true`, and `minHostFreeGb` present and ≥ 25; a `--from/--to` subset is marked `notM9`. Per-gate timeouts from measured durations and a global wall deadline (1.5 × Σ measured). The watchdog writes a heartbeat; a missing or stale heartbeat (older than 2 polling periods) fails the run. **Preventive trip point:** the watchdog trips at `25 + h` GB, where h = the measured maximum host-disk growth rate during dev gates × (polling period + detection + VM shutdown delay), rounded up, recorded with its evidence in `m9-budget.md`; so a trip stops the run before free space can fall below 25 GB, and `minHostFreeGb ≥ 25` is what M9 must show. **Both stop paths are bounded:** (a) low space: the watchdog's K15 trip (stop the VM-side `gate-*` unit over ssh, shut the VM down gracefully); (b) watchdog loss: the runner itself checks the heartbeat between polls and, when it is older than 2 polling periods, runs the same cancellation and shutdown and fails the verdict. h is computed from the longer path (2 polling periods + runner check interval + cancellation + shutdown). Self-test fixtures for each fail case (no heartbeat, stale heartbeat, missing min-free, min-free < 25, subset run, missing step, extra step), plus a fixture that kills the watchdog while a dummy gate unit runs and shows the unit stopped within the bound.
- **Substitution 4 in M9:** when the runner selects R2 as the top rung, it validates the committed `r3p-substitution4.json` (its evidence dir exists and its config and scenario sha256s match the frozen files); otherwise the verdict fails.
- **`--reference` mode:** the top rung's gate compares its C1 output with the committed reference and writes `equalsReference`.
- **Budget (F02, keeping P0's K2 accounting):** projection = host free now − expected further dev growth − M9 need (measured, counted once) − (25 + h) GB. Overlays already on disk are inside "host free now" and are not subtracted again. Stop B states the exact GB to free; P10 starts only once the projection is ≥ 0.
- **Records (F10), before the freeze:** every rung and M9 verdict carries `substitution3Applied`; the P10 run report template lists P1–P9, N5, the descoping S1/S2 and every substitution.
- **Codex pre-ship audit (CX-3), after the runner and reference are final but before the freeze commit:** one `adversarial-review` run per the packet (`--base <pre-build sha>` from the resume card; `--scope working-tree` with `<pre-build sha>..HEAD` named in the focus if uncommitted work exists). Before the run, the controller writes an **audit inventory** (scratchpad, no secrets): every parent file changed in `<pre-build sha>..HEAD` and in the working tree, and, for each fork whose pin changed since the pre-build sha, the local checkout fetched (by the controller, not Codex) so that `git -C <fork dir> diff <old pin>..<new pin>` works offline, with the list of changed fork files. The focus names the inventory and asks Codex to state, per inventory item, reviewed or not. Triage checks coverage against the inventory; zero files in `.context.summary` is a false pass. **The ledger may end `Status: complete` only when every inventory item that holds a material change (code, gate, config, schema; not plan or report text) is marked reviewed**, by the main run, by the spare run (CX-3), or, if Codex is skipped or the cap is spent, by the normal reviewer (a `code-reviewer` subagent given the same inventory), recorded per item in the ledger. Listing an item as unreviewed never counts as coverage. Triage every finding in `reports/codex-pre-ship-audit.md`: accept (fix, re-run the affected Verify; a fix that changes a gate input re-runs the reference per K14), reject (verification source), or escalate → PAUSE T9. Codex failure → `Codex skipped: <reason>` (CX-1), continue.
- **Verify add:** V4 runner self-test fixtures exit 0 (including the watchdog-loss and substitution-4 record fixtures); V5 `reports/codex-pre-ship-audit.md` ends `Status: complete` with every material inventory item marked reviewed (by Codex or, after `Codex skipped: <reason>`, by the normal reviewer).
- **Snapshot rule:** the top rung's green snapshot is never deleted before M9 is green; `r0-green` and (unless top rung) `r2-green` may be deleted only under the packet's rule.

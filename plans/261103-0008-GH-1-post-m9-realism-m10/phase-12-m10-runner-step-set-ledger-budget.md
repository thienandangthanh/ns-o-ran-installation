# P12: M10 runner, check-diff ledger close-out, budget; then Stop B

**Start state:** checkpoint-3 pins (tag `m10-cp3`). **Snapshot at exit:** none.

## Context
The M9 runner has:
- a fixed step table [V `scripts/run-to-m9.sh:70-90`];
- the `PLAN_REL` evidence root and reference [V `:27-31`, `:88`];
- budget-driven timeouts and watchdog [V `scripts/m9-budget.json`: trip 29 today];
- a fail-closed verdict [V `scripts/m9-verdict.py:39-86`].

FU1 (P00) already fixed `finish()`. The rehearsals, cold re-measures and the Codex pre-ship audit ran in P11, before the cp3 tag (kongming #8). **This phase is runner-only.** After `m10-cp3` it may change no gate, check or tool: `git diff m10-cp3..F₁₀ -- scripts/gates tools` must be empty, and only the runner, verdict, budget and gitignore files may change.

## Requirements (contract)
- **AC19 (groundwork):**
  - the step set is exactly R-1, pre-registered in plan.md before this code (p12 last); `exactStepSet: true`;
  - r3p at δ = 0 equals the cp3 reference; d150 equals its cp3 reference; d100/d200/d500 are checked against their cp3 sim-side references;
  - the M9 `reference/r3p/` stays reachable through the `m10-cp1` and `m10-cp2` tags;
  - health: exit 0, every step green, `minHostFreeGb ≥ 25`, the watchdog (trip 37) never trips, rc RestartCount 0.
- **AC18:** the check-diff ledger is complete: every changed m0–r3p check old → new, why it is not weaker, no deletion, and the P1/P5/N5 rows marked registered with their Stop A record.
- **Stop B:** the disk check against T′ and the /mnt/data line.

## Design
- **One runner core (DRY).** The shared body of `run-to-m9.sh` (argument parsing, harness-SHA guard, monitors, `finish()`, step loop) moves into `scripts/vm/run-chain-core.sh`.
  - `run-to-m9.sh` keeps its M9 table (reproducible history).
  - `run-to-m10.sh` supplies R-1, the M10 evidence root (`plans/261103-0008-GH-1-post-m9-realism-m10/evidence`), `scripts/m10-budget.json` and the cp3 reference paths.
  - `m9-verdict.py` gains `--goal m10`: step names, the d150 C1 reference check, the δ fields of d100/d200/d500, rc RestartCount, and the per-rung assertion that the subscription period is 100 ms.
- **`scripts/m10-budget.json`**, built by `scripts/m9-budget.py` from the P11 rehearsal durations (cold i0/i2/m3 included), with `watchdog.hGb = 12`, `tripGb = 37` and `globalWallS = ceil(1.5 × Σ longest green)`.
- **Disk:** T′ = max(T′_method, T′_measured) from plan.md's budget, with N_new measured in P11.
- **`plans/.gitignore`:** keep the `m10/*/*` top-level files, like `m9/*/*`.

## Files
- Create: `scripts/run-to-m10.sh`, `scripts/vm/run-chain-core.sh`, `scripts/m10-budget.json`, `scripts/gates/gate-d-delta-identity.sh` (d100/d200/d500 single runs with the δ and c checks), and the d150 wrapper (`gate-r3p-ts-predictor.sh --mode c1 --delta-ms 150 --reference …/reference/r3p-d150-cp3`).
- Note: `gate-d-delta-identity.sh` and the d150 wrapper are gate files, so they are written and rehearsed **in P11 before the tag**. They are listed here only as runner inputs.
- Modify: `scripts/run-to-m9.sh` (source the core; same behaviour), `scripts/m9-verdict.py`, `scripts/m9-budget.py`, `scripts/vm/m9-runner-selftest.sh` (M10 cases: wrong step set, missing d150 reference, trip 37, p12 not last), `plans/.gitignore`, `plans/261103-0008-GH-1-post-m9-realism-m10/check-diff-ledger.md`.
- Create (Markdown): `plans/261103-0008-GH-1-post-m9-realism-m10/m10-budget.md`, `docs/journals/<date>-m10-stop-b.md`.

## Steps
1. Refactor the runner core. The M9 self-test cases must pass unchanged first; then add the M10 cases.
2. `run-to-m10.sh` and the verdict changes; verdict self-test.
3. Budget from the P11 measurements: timeouts, W′, and T′ under both bases. Write `m10-budget.md`.
4. Close the AC18 ledger: cross-check against `git diff 39b3ba2..m10-cp3 -- scripts/gates tools` (`39b3ba2` is the M9 harness F″) so that every changed check has a row.
5. Freeze: harness SHA F₁₀ pushed; pins verified with `git ls-remote`; `git diff m10-cp3..F₁₀ -- scripts/gates tools` empty. Stop B packet → `PAUSE B`.

## Validation
- `bash scripts/vm/m9-runner-selftest.sh` passes all M9 and M10 cases; the verdict self-test passes.
- `run-to-m10.sh --harness-sha F₁₀ --dry-plan` lists exactly R-1.
- The ledger cross-check prints no changed check without a row.
- `git diff --stat m10-cp3..F₁₀ -- scripts/gates tools` is empty.
- Stop B: `df -BG /home /mnt/data` measured, T′ computed, the user frees any shortfall before P13.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| None: runner and budget. | — | — | — |

## Risks
- The runner refactor regresses M9 behaviour (Medium/Low). The M9 self-test cases pass unchanged first.
- T′ exceeds what can be freed (High/Medium). The user decides the base and frees space at Stop B; nothing is deleted autonomously.
- A gate needs a fix after the cp3 tag (Medium/Low). That is not allowed in P12: go back to P11 and produce a new tag (`m10-cp3` is never moved; the new tag is `m10-cp3b`), with the reason journaled.

## Rollback
Revert the runner commits; `run-to-m9.sh` at `39b3ba2` remains the M9 record.

# kongming counsel: P8′ step 4 stage A red (missing ledger), guided fix

Date: 2026-10-28 13:05 KST. Advisory only, not user approval. Verified at HEAD 2e100e4. The run itself was at harness 5c2b049; 5c2b049..2e100e4 touches only the M9 runner and lint, not the r3p path. Red evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r3p/20261028T035439Z`. Model: opus (per user CLAUDE.md), not fable.

## TL;DR
**GO, with three changes.**
- Replace the `grep -c` count with a fail-closed, self-tested judge in `r3p-checks.py`:
  - stage A: zero ledger lines past the header, and an absent file counts as zero;
  - stage B: the file exists and holds exactly one line, which is h1's control, applied and not late.
- Fix a fail-open defect I found while scouting. This one is more serious than the bug that went red. `check … bash -c "python3 … | tee …"` returns tee's exit status, so the gate's pipefail does not reach the judge. Today this affects 14 checks: the r3p live judges, the r3p calibration judges, and R2's expect/wire/stub judges.
- Harden `classify` so that only exit codes 0, 3 and 4 count as valid.

Then commit, push, and do one fresh full stage A run. Do not reuse anything from the red classification. The red run may be cited only as root-cause and cross-check evidence. No T3. This counsel is the one T6-budget fix: a second red stage A means PAUSE T6.

## Root cause (verified)
- ns-3 opens the ledger lazily. `WriteLedger` creates the file and its header on the first line only (`oran-interface/model/e2-control-hub.cc:348-357`), so a run with no control has no ledger file. The JSON is compact (`e2-ipc-json-writer.cc:65-71`), so the grep pattern itself was right.
- `applied_n` (`scripts/gates/gate-r3p-ts-predictor.sh:160`) runs grep on the absent file. n comes back empty, so the check fails. The stage record (`:164-168`) then marks the stage not clean, and the classifier returns invalid (`r3p-dry-run-classifier.py:43,87-88`).
- An independent judge in the same red run already shows a null stage: `checks/r3p_drya_handover_rows_match_ledger.out` reports ledgerLines 0, applied 0, refused 0, HandoverStart 0.
- The other readers already treat an absent ledger as empty:
  - `check-c9-handover-trace.py:38-39`
  - `check-n6-influx-window.py:128`
  - `digest-run.py:108-115`
  - `check-ledger.py:34`

## 1. Go/no-go on the proposed fix: GO, with these refinements
1. **Put the count in `r3p-checks.py`, not inline shell.** Add a subcommand, e.g. `dry-ledger LEDGER [--h1 STAGE_A_CLASS]`.
   - Without `--h1` (stage A), it passes iff the ledger is absent, or has 0 lines past the header, of **any** outcome. A null-control stage means no control at all. A refused line would mean something sent an untriggered control, and that should be red. C8's null control is judged the same way (digest ledger = empty).
   - With `--h1` (stage B), the file must exist and hold exactly one line. That line must have `(viaNodeId, imsi, targetCell, afterSeq) == (h1.via, h1.imsi, h1.targetCell, h1.step)`, outcome `applied`, and cause not `late`. Read h1 from the stage A class file, not from the run's schedule.json, so a schedule-builder bug cannot weaken the expectation.
   - Print one JSON line with `lines`, `applied`, `refused` and `pass`, as the other judges do.
   - Call it directly from `check`, with no `| tee`. You can keep the check name `r3p_${label}_applied_controls_${want}` for a like-for-like comparison with the red run.
2. **Fixtures** in `r3p-checks-fixtures.py`, run by the existing self-test, which the stage A run executes at `r3p_predictor_n6_classifier_checks_reference_self_tests`:
   - Stage A cases:
     - absent → pass;
     - header-only → pass;
     - one refused line → fail.
   - Stage B cases:
     - absent → fail;
     - the matching applied line → pass;
     - wrong target → fail;
     - two lines → fail;
     - refused → fail;
     - late → fail.
3. **Make `ledger()` (`r3p-checks.py:52-53`) return `[]` for an absent file.** This matches the readers above. No verdict changes, because every live schedule contains h1. `c_expect`, `c_d7` and `c_driven` then fail with "0 ledger lines" instead of a traceback.
4. **Same commit, same block: harden `classify` (`gate-r3p-ts-predictor.sh:173`).** `[ "$rc" != 1 ]` passes a usage error (2) or a signal kill (137) as "valid". Use `case $rc in 0|3|4) return 0;; *) return 1;; esac`, and also require the class file to exist. A legitimate classification cannot turn red because of this.

## 2. Fresh stage A run: required. Citing the red run: limited
- **Required.** The Failure Protocol says to re-run the Verify step. The classification of record must come from the gate at a committed harness with exit 0 / verdict PASS.
  - The forced-clean host re-classification is exactly the "reasoning around the failure" that the protocol forbids. It must never become `scripts/gates/r3p-stage-a.json`, a stage B `--stage-a-class`, or a `stageDir`.
  - Do not commit it into the evidence dir under any `r3p-stage-*-class.json` name. Quote its numbers in the notes or journal, labelled diagnostic.
- **Allowed uses of the red run:**
  - as root-cause evidence: the `.out` file, the stage record, the c9 output above;
  - as an observation that every other check passed at 5c2b049 (N6 70/70, max 0.818 s);
  - as a **determinism cross-check**. Lock-step at RngRun 1 with a pinned epoch should reproduce `n1=(20, imsi 3, none)`, `h1=(30, imsi 1, →0000000202 via 2)`, 420 candidates, 140/280/0.
    - If the fresh class differs, the fresh run is still the record.
    - But do not start stage B. Record the divergence and consult kongming first, because C1 would likely be red too.
- **Not allowed uses of the red run:**
  - as a pass;
  - as a pre-registration input;
  - as a substitute for any fresh-run fact.
- Commit the red evidence dir unchanged. Its `r3p-stage-a-class.json` (invalid) is the honest record.
- **Pre-registration hygiene.** You looked at a diagnostic classification, so prove nothing pre-registered moved. `git diff 5c2b049 <fix> -- scripts/gates/{r3p-scenario.json,rung-config.json,r3p-predictor.py,r3p-dry-run-classifier.py,r3p-schedules.py,r3p-prepare.py,check-n6-influx-window.py}` must be empty. The fresh class file's `scenarioSha256` must equal `7824c744…64f6`.

## 3. Same-class defects (verified)
- **Fail-open `| tee` inside `bash -c` (MUST FIX before step 5).**
  - `set -uo pipefail` (`lib.sh:14`) is not inherited by a child `bash -c`, because SHELLOPTS is not exported. Reproduced locally: `bash -c "false | tee"` returns rc 0, while `bash -o pipefail -c` returns 1.
  - Affected checks:
    - `gate-r3p-ts-predictor.sh:221,223` (calibration);
    - `gate-r3p-ts-predictor.sh:228-236` (all nine live judges: expect, wire, stub, predictor, influx-ipc, d7, observation, membership, driven);
    - `gate-r2-ts-stub-qp.sh:120-122`.
  - Combined with a missing ledger, a live run with no applied control would pass expect, d7 and driven. That is a false green.
  - **Fix:** `bash -o pipefail -c "…"` on exactly those 14 lines.
    - Do **not** export SHELLOPTS globally. Every child bash would inherit pipefail, which revives the `logs | grep -q` SIGPIPE-141 trap.
    - Add a lint rule: `bash -c "[^"]*\| *tee` without `-o pipefail` fails.
  - **Retro audit (done here, read-only):** every tee'd `runs/*/r2-*.json` in all 7 `evidence/r2/*` dirs has `"pass": true`. No recorded R2 verdict changes, so no R2 re-run is needed now; M9 re-runs R2 anyway. Record this audit in the notes.
  - It does not touch the dry-run block, which exits at `:181` before `rung_judges`. It may ship in the same push as a separate commit, and must land before calibration.
- **No other wrong-verdict missing-ledger readers:**
  - The dryrun block reads the ledger only via `applied_n`, c9 and N6 (via prepare).
  - The C1 replay (`ts-rung-lib.sh:169,179`) and `r2-checks.py:38` need a ledger, but only on runs where h1 must have applied, so they fail closed (once the tee fix lands).
  - `c_membership` and `c_observation` read windows, not the ledger.
  - "m1-only" has no ledger dependence beyond h1.
- **Process rule:** commit `r3p-stage-a.json` only from a run whose `verdict.json` passes. The class is written before `rung_final_facts`' checks (IPC drops, restart counts, stray process), which are outside the stage record.

## 4. Acceptance signals (T3/T6)
- **No T3.**
  - Not changed: the counter, the window, the formula, the domain, the template, the observation-change control, the classifier logic, the class categories, and the pass condition ("every check green and a valid classification").
  - The judge now reads ns-3's own semantics (no line = no file). The stricter stage A/B predicates and the tee and classify hardening only add verification. Each can turn a false green red, never a red green.
- **T6:** this counsel is the one guided fix since the 11:44 re-issue. If the fresh stage A fails **any** check, including an unrelated one, print PAUSE T6.
- **Routing:** a green gate with class T3 still means PAUSE T3, and substitution4 means report-not-pause. Route on `dryRunClass`, not on exit 0 alone.

## Work checklist
1. Commit 1: the `dry-ledger` judge, its fixtures, the `ledger()` tolerance, and the `applied_n` → judge and `classify` rc changes in the dryrun block.
2. Commit 2: the `bash -o pipefail -c` change on the 14 lines, plus the lint rule.
3. On the host, run `lint.sh` and `r3p-checks.py --self-test`.
4. Run the pre-registration diff (must be empty).
5. Commit the red evidence dir as-is. Scan it for secrets first (repo is PUBLIC; the r3p check covered only `runs/drya/r3p`).
6. Commit message: no plan IDs or finding codes. Push.
7. Run a fresh `vm-exec.sh gate-r3p-ts-predictor.sh -- --mode dryrun --stage a`.
8. Confirm exit 0, the class, `scenarioSha256`, and that it matches the diagnostic.
9. Commit the class as `scripts/gates/r3p-stage-a.json`, then run stage B.

## Unresolved questions
- None blocking. Optional: whether the user wants the tee fail-open audit surfaced in the next journal, as well as in implementation notes (recommended: yes, one paragraph).

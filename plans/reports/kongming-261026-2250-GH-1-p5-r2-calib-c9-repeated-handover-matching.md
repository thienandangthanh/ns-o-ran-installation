# kongming counsel: P5 step 4 (R2 calibration), C9 checker red on repeated same-direction handovers

2026-10-26 ~23:05 KST. Failure Protocol counsel; advisory only, **not user approval**. Model: Opus 5.5 (user routing for kongming).
Inputs: evidence/r2/20261026T133922Z (harness 00485d6), `scripts/gates/check-c9-handover-trace.py`, goal-packet.md, plan.md T3/T6, phase-05 Failure Protocol, contract C9.

## TL;DR
Your root cause is right in substance but wrong on one point. The checker's "exactly one candidate" rule has no upper time bound: it counts every later Start row with the same (imsi, source, target) until the end of the run. So any UE handed over twice in the same direction fails, whatever the order the lines are processed in. The ledger is already time-major, so processing order is not the cause. Fix the checker with per-IMSI attribution windows, as you proposed. The window is the part that matters, because time ordering alone gives a false green (shown below). Also add an explicit source ≠ target check, prove the change with a self-test, then re-run calibrate fresh. This counts as the one kongming-guided fix; it is not T3 or T6. The R0 and R1 greens stand.

## 1. Root cause (Q1), verified
- Ledger: 25 `applied` lines in **time order** (rxSeq 10, 13, …, 82). C4 order applies only within a step. R1 live1 step 30 shows it: ctlId 2 comes before ctlId 1 because it has the lower targetCell. The claim "file order is C4, not time" is wrong for this ledger.
- Traces: 25 Start rows, each at apply + 3.0 ms with the ledger's imsi, source and target. 25 End rows, each at Start + 1.72 ms at the target. They pair 1:1 in time. I checked every line.
- Defect: `check-c9-handover-trace.py:41-45` collects the unused Start rows with the line's triple at time ≥ apply, with no upper bound, and flags `len != 1`. On a flag, `continue` skips End matching, so both rows become orphans (`:53-56`). That gives 13 problems: every line whose triple recurs later (IMSI 1 3→2 at 1.0, 4.6 and 8.2 s gives 3 candidates; the others give 2). It also gives 13 orphan Starts and 13 orphan Ends.
- Why it never fired before: none of R0, R1, S0, S1 or the R2 C1 scenario repeats an (imsi, src, tgt) among applied lines (`r2-scenario.json` controls use IMSIs 1, 3, 2, 6 once each). The calibration block has to repeat: 6 IMSIs × 2 directions = 12 distinct triples, fewer than 25 triggers.
- C9 is the only failure: `gate.log` ends `verdict r2: FAIL failed=['r2_calib_c9_handover_rows_match_applied_lines']`. The run took 8 min (13:39–13:47 UTC). W = 1.0 s (L_max 25.1 ms).

## 2. Is the new matcher a weakening? (Q2)
**No, as long as the per-IMSI windows are kept.** Argument:
- **Where the old result meant something, the new checker is at least as strict.** Take inputs where no IMSI has two applied lines with the same (src, tgt). If the new checker passes, every Start row is matched 1:1 to an applied line with the same triple. Each triple occurs once, so the old candidate set has exactly one member. The old End pick (earliest unused End at the target after the Start) is that window's End, because earlier Ends of the IMSI precede the window. There are no orphans. So the old checker passes too.
- **Outside that set the old checker is red on every input, correct or broken.** With both rows present it sees ≥ 2 candidates. With one row missing, the later line sees 0. Its verdict there carries no information, so nothing is lost.
- **The new checker is stricter than the old one in five ways:**
  - it checks source ≠ target explicitly (C9 text; the old checker only compared with the ledger);
  - each Start is bounded above by the IMSI's next applied line;
  - it requires exactly one Start of the IMSI (any triple) per window;
  - it requires exactly one End per handover;
  - two applied lines for one IMSI at one apply time are a problem (`kpm-ue-list-moves.py:89-100` already treats a same-step pair that way).
- **Empirical checks:**
  - A scratch prototype passes **all 49 archived runs that have traces**: R0 ×4 sets, R0 calib ×2, R1 ×2 sets, S0, S1 ×2, and this calib run. On the 48 that predate this run, the old checker also passes.
  - A fuzz of 1,600 random mutations of R0 073520Z live1, R1 084654Z live1 and rng2, and S1 191853Z fb1: the old and new checkers agree on every case (1,436 red/red, 164 green/green, **0 old-red/new-green**).
  - 13 named mutations of this calib run all fail under the new checker.
- **The window is what makes this safe. Ordering alone is not enough.** I built a mis-attribution fixture from this calib run: drop IMSI 1's 4.6038 Start and its 4.60552 End, then add a 3→2 Start at 8.3038 and an End at 8.30552. Per-triple counts stay the same. Results:

  | Matcher | Result | Note |
  |---|---|---|
  | Old checker | red | no meaning here (it is red on every repeated triple) |
  | Windowless time-ordered greedy (your option without the bound) | **green** | false green |
  | Windowed matcher | red | "0 Start rows for imsi 1 in [4.6008, 6.4008)" |

  A matcher without the per-IMSI upper bound would really weaken the test.

**What the matcher should do (spec, not code):**
1. Group applied lines by IMSI and sort them by `applySimTimeNs`. Two applied lines of one IMSI with the same apply time are a problem.
2. window_k = [apply_k, apply_{k+1}), with ∞ for the last line. Only **applied** lines set the bounds. A refused sibling in the same step (R1 steps 30 and 40) comes before the applied line's Start at +3 ms, so letting it set a bound would give a false red.
3. In window_k there must be exactly one Start row of that IMSI (any triple). Its (source, target) must equal the ledger's, with source ≠ target.
4. In [start_k, the IMSI's next Start row) there must be exactly one End row of that IMSI (any cell), and its cell must equal the ledger target.
5. Keep the orphan rule unchanged. `--allow-extra` relaxes only orphans; no gate passes it (the only callers are r0:209, r1:194 and r2:246, none with the flag).
6. Keep the 1e-9 tolerance.
7. Keep the current report keys (nothing parses them) and add one pair record per line.

I prefer "exactly one in the window, then check" to your "earliest unused". With the orphan rule they give the same pass/fail, but the per-line message names the real defect. A stricter variant bounds End by the next applied line; it also passes all 49 runs. I advise against it because it would assert C3's in-handover coverage inside C9.

## 3. R0 and R1 verdicts (Q3)
There is nothing to revisit. Their inputs never repeat a triple, so their old greens were meaningful, and the new matcher passes every archived R0, R1, S0 and S1 run.
- Record a host re-judge with the fixed checker as a **fact**: R0 073520Z and R1 084654Z, all runs. Do not edit their `verdict.json`.
- The r0 and r1 live regressions already planned in P6 will exercise the new checker live, and M9 will too.

## 4. Order after the fix (Q4)
1. One commit:
   - the checker;
   - a `--self-test` that reads committed fixtures in `scripts/gates/fixtures/` (copies of this calib run's three files and R1 live1's three files);
   - a lint.sh line in the same pattern as `pod-log-window.py --self-test` at `lint.sh:31`.

   The commit message should state the invariant. Do not use plan, phase or audit IDs in code, test names or the message.
2. Run lint and the self-test; both green.
3. Host re-judge (supporting evidence, **not** the Verify): 133922Z calib passes, and R0 and R1 pass. Store it next to the run, for example `runs/calib/c9-host-rejudge-<sha>.json`. 133922Z keeps its red verdict.
4. Push. Then re-run the Verify as a **fresh** `gate-r2-ts-stub-qp.sh --mode calibrate` at the fix SHA (about 8 min). i2 does not need to run first, because r2's per-run reset creates its own rc, TS xApp and stub pods.
5. Take W only from the fresh green calibration. The provenance check at `gate-r2:88` must name that directory, not 133922Z.
6. Then `--dev`, then a fresh full C1 set. The `--dev` rehearsal is cheap insurance: a red C1 costs a recorded root cause, a commit and a full fresh set.

**Any red at step 4 is T6**, because the fix budget is spent, and that includes a red on a different check.

## 5. T3, T6 or one fix? (Q5)
This is **one kongming-guided fix**.
- **Not T3:** C9 as written is met by this run (verified 1:1), and neither the contract nor the scenario changes.
- **Not T6 yet:** this is the first failed Verify since the 22:34 re-issue (standing ruling, plan.md T6).
- **Not an outcome change:** only a harness checker changes, and it becomes stricter.

Disclose it at P5 exit and at Stop B: a judging script was changed after a red, here is the argument, here are the fixtures. The user can overrule. My counsel does not count as that approval.

## Fixtures for the self-test

| Expected | Mutations |
|---|---|
| **PASS** | this calib run as is; the same with the ledger body and trace rows shuffled; R1 live1 as is (same-step applied+refused pair, unknown IMSI) |
| **FAIL** | dropped Start; Start with the wrong target; source = target (ledger line and row both mutated); orphan Start before the IMSI's first apply; duplicate Start inside a window; Start before apply; Start at or after the IMSI's next apply; the **mis-attribution** case above (it must keep its added End, so that only the window can catch it); End before its Start; End at the wrong cell; dropped End; duplicate End; applied flipped to refused with the rows kept; two applied lines of one IMSI at one apply time |

## What to avoid
- **Sorting by time without windows:** a windowless greedy gives a false green (shown above).
- **`--allow-extra` in calibrate mode.**
- **Skipping C9 in calibrate mode.** The `calibration._comment` in `r2-scenario.json` says "only L and the one-control-per-trigger count are judged", but the gate runs every per-run check. Fix the comment to match the gate, never the reverse.
- **Reshaping the calibration so no triple repeats.** That caps it at 12 triggers, narrows the test, and R3 and M9 can repeat triples anyway.
- **Relabelling 133922Z green, or taking W from it.**
- **Letting refused lines bound the windows.** This gives a false red on R1's same-step pairs.

## Assumptions
- **High:** the trace files the checker reads are the ones C9 names, and that stays unchanged. ns-3 cannot apply two controls to one UE in one step (R1 shows the `inHandover` refusal).
- **Medium:** "re-run the Verify step" means a fresh gate run, not a re-judge of archived evidence. A later red on another Verify step (for example the C1 run) goes through its own Failure Protocol. If the user reads the budget as one fix per release, a later red is T6 directly.
- **Medium:** the trace prints about 6 significant digits. Both checkers can only false-red (Start rounded below apply) once t is about 1000 s or more, given the 3 ms margin. That never makes a test weaker, so leave it alone.

## Scratch references (session scratchpad; prototypes only, not for copying as-is)
`/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/a6e4da8c-3ced-4105-a752-bbee28453b14/scratchpad/c9new.py` (windowed prototype), `.../scratchpad/named.py` (named mutations), `.../scratchpad/fuzz.py` (old-vs-new fuzz), `.../scratchpad/greedy_nowindow.py` (the false-green variant).

## Unresolved questions
- Does the T6 budget count per Verify step (the phase Failure Protocol's wording) or once per goal release (the 22:30 ruling's wording)? It matters only if a later Verify goes red.

Status: DONE
Summary: The root cause is the checker's unbounded rule (exactly one same-triple Start among all later rows), not ledger order. The per-IMSI windowed matcher is not a weakening: it is proven on all 49 archived runs and 1,600 fuzz cases, and without the window it gives a false green. Make it one fix, then run calibrate fresh, then --dev, then C1.
Concerns/Blockers: Any red on the fresh calibrate is T6. Disclose the checker change to the user at P5 exit.

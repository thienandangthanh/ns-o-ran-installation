# kongming: P2 (S1) first failed Verify V1, pacer exit capture

Date 2026-10-23 ~04:30 KST. Model: Opus 5.5 (as routed by the caller). Advisory only, not user approval.
Inputs: harness 0e821fb, evidence `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/s1/20261022T185101Z/`, `scripts/gates/gate-s1-pacer-lockstep.sh`, `scripts/gates/lib.sh`, `scripts/gates/agents-ns3-run.sh`, `scripts/gates/pacer.py`, `scripts/gates/digest-run.py`, plan.md, phase-02.

## TL;DR
This is a harness defect, not a product defect. Your conclusion is right, but you have the mechanism backwards, and I reproduced it on bash 5.2.21. Don't use the file wrapper you proposed: `kill "$pp"` would hit the wrapper and leave python orphaned. The smaller and correct fix is to call `_pacer_finish` without `$(...)`, in the shell that started the pacer, and have it set a variable. Then run all of S1 again, fresh, and after that M5–M7. This does not trigger PAUSE T6. If any check is red on the fresh S1, it does.

## 1. Diagnosis (Q1): conclusion right, mechanism reversed (verified)
- A `$(...)` subshell is not the pacer's parent. It does get a copy of the parent's job table.
  - **Pacer reaped by the parent before the fork:** this happens when the pacer exits while the parent is blocked in `ns3_wait`'s `wait $NS3_PID`. Bash's `waitpid(-1)` loop collects the pacer too. The copied table already holds the status, so `wait` in the subshell returns the true code. This is why null, fb1, replay and midlate read 0, and faultsink and faultagent read 3.
  - **Pacer still unreaped at the fork:** this happens when the pacer exits after ns-3 has been reaped. The subshell cannot get the status. Bash 5.2.21 returns **-1**. Bash 5.3 prints "pid N is not a child of this shell" and returns 127.
- So the failure needs the opposite of what you described. It happens when the parent had **not** yet reaped the pacer. tctl fits this. The pacer sends the abort, ns-3 echoes it 0.8 ms later and exits 5 at once. The pacer then still has to write `pacer-summary.json` and shut down the interpreter. So it lost the race.
- **Reproduction:** an `ubuntu:24.04` container with bash 5.2.21, the same build as the VM. The script copies the gate's shape: a background pacer stand-in, ns-3 as `( exec setsid timeout … ) &`, `wait $NS3_PID`, then `prc=$(_pacer_finish $pp)`. The stand-in pacer always exits 3.

  | Pacer exits | ns-3 exits | Value read (3 tries each) |
  |---|---|---|
  | 0.5 s | 1.0 s | 3, 3, 3 |
  | 1.0 s | 1.001 s | 3, 3, 3 |
  | 1.0 s | 1.0 s | 3, 3, 3 |
  | 1.001 s | 1.0 s | 3, -1, 3 |
  | 1.05 s | 1.0 s | -1, -1, -1 |
  | 1.5 s | 1.0 s | -1, -1, -1 |

  The exact "-1" is reproduced.
- **The pacer really did exit 3 in tctl (high confidence):** `pacer-summary.json` was written with `aborted: true`, and run() returns 3 straight after writing it (pacer.py:225-228; the 196 in your note is a different line). `pacer.log` holds only `READY`, so there was no traceback. ns-3 stderr: "E2 pacing abort at step 15: pacer: step 15 …". The abort json shows abortStep 15 and blockedToAbortWallS 30.05.
- **No false pass from the old helper (verified):** in 60 near-simultaneous exit orders with a true pacer exit of 7, it read 7 27 times and -1 33 times, and never 0 or 3. A broken read never matched an expected value, so the 0 and 3 recorded for the passing paced runs are genuine.

## 2. Fix (Q2): sound only with the parent-shell wait, not the file wrapper
**Recommended (minimal).** Change one function and its two call sites in `scripts/gates/gate-s1-pacer-lockstep.sh` (lines 104-108, 132 and 441):
```bash
# _pacer_finish <pid>: waits (bounded) for the pacer, which exits once ns-3 ends, and sets
# PACER_RC to its exit status. Call it in the shell that started the pacer, never inside
# $(...): that subshell is not the pacer's parent, and when the pacer is still running at
# the fork, `wait` there cannot see its status (bash 5.2: -1, bash 5.3: 127).
_pacer_finish() {
    for _ in $(seq 150); do kill -0 "$1" 2>/dev/null || break; sleep 0.2; done
    kill "$1" 2>/dev/null; wait "$1"; PACER_RC=$?
}
...
    [ -z "$pp" ] || { _pacer_finish "$pp"; prc=$PACER_RC; }      # s1_run
...
    _pacer_finish "$pp"; prc=$PACER_RC                            # s1_agent_fault_run
```
- **Verified on bash 5.2.21 in the same container:**
  - All 18 orders above read 3, called through a `check`-style function with redirection, the same shape as `lib.sh:53-62`, which runs the function in the current shell.
  - A pacer that never exits is killed at the bound and reads 143, so the check still fails closed.
- **Nothing gets weaker:** every pass condition stays the same (`prc == 0` after a clean run, `== 3` after an abort). The value is now the real kernel exit status in every exit order.
- **Why not the file wrapper.** With `( python3 … ; echo $? >"$rd/pacer-exit" ) &`, `pp` becomes the wrapper bash.
  - Every `kill "$pp"` would then signal the wrapper, not python. That covers the bounded kill in `_pacer_finish`, `_wait_ready` failing, and `kill "$sp" $pp`. The wrapper dies, python stays orphaned holding port 38499, and the exit file is never written.
  - Verified: the wrapper read 143, the file was missing, and the stand-in kept running.
  - You would need traps or file-presence handling to make it work. That is more code and leaves new ways to fail, for no gain.
- Only these two call sites read a status through `$(...)`. The other `wait` calls in `scripts/` (bringup.sh:99, agents-ns3-run.sh:90/99, gate-m4:39, gate-m2:228, gate-s0:82) run in the parent shell.
- **Should-do (optional, about 1 s):** a fresh green S1 does not by itself prove the fix, because tctl may win the race next time. A deterministic self-test on the VM's own bash closes that gap:
  ```bash
  pacer_exit_read_after_ns3_reaped() {
      local fake ns rc
      sh -c 'sleep 1; exit 3' & fake=$!
      sh -c 'sleep 0.2; exit 5' & ns=$!
      wait "$ns"; rc=$?; _pacer_finish "$fake"
      echo "stand-in ns-3 $rc; stand-in pacer exiting after ns-3 is reaped read as $PACER_RC (want 3); bash $BASH_VERSION"
      [ "$rc" = 5 ] && [ "$PACER_RC" = 3 ]
  }
  check s1_pacer_exit_read_when_pacer_outlives_ns3 pacer_exit_read_after_ns3_reaped
  ```
  The old helper reads -1 in this order. If you skip the self-test, at minimum write the container reproduction (command and the table above) into implementation-notes as the proof.

## 3. Re-run scope (Q3): all of S1, fresh
- V1 is literally "the gate exits 0" with one `verdict.json` at one harness SHA. The gate has no partial mode, and adding one would be new, unverified harness.
- The change touches `s1_run` and `s1_agent_fault_run`, which every paced run uses: null, fb1, replay, midlate, tctl, faultsink and faultagent. All of them must run through the new code.
- The plan's discipline points the same way (plan.md:80): record the root cause, commit, then a full fresh set. The resume card (plan.md:33) already says "re-run S1 fresh".
- Cost: about 16 min last time (955 s). `~/s1-build-p1` was deleted at the end of that run and `~/m4-build` is now at the new pins, so the P1 pins are rebuilt (about 4 min last time) and the new pins are reused. The VM has 53 G free.
- Then M5–M7 (V5) at the new pins, under the fix's harness SHA.

## 4. Other things in the evidence (Q4)
None of these blocks the re-run.
- **Digests are not vacuous (verified locally on the evidence copy).**
  - free and null: 0 ledger lines, 100 IPC samples per node, 29 trace files. fb1 and replay: 8 ledger lines, 100 per node, 34 traces. midlate: 2 ledger lines.
  - The overall digests match the VM's: free/null `08190b78…`, fb1/replay `c615e7c1…`. fb1 differs from null, so the digest does respond to controls.
  - V6 compared 29 traces and 100 samples per node.
- The faultagent V3 check runs with `min_lines 0`, so its "no ledger line at or after K" part holds trivially when there are no controls. faultsink covers the ledger side (3 lines before K). This is acceptable as designed; just know it.
- `pacer.py:200`: a run-out step reports `slackS = budget` (30.0) even though nothing arrived. K10 reads ns-3's barrier log, not this field, so it is harmless today. Make sure R0 does not take T_ctl slack from `slackS` without excluding aborted steps.
- `minSlack.T_ctl` and `minSlack.W` are null, with a note that says why. That is consistent with the user's CPU hold (plan.md:34). T_ctl is re-set at R0 anyway.
- **Housekeeping (verified):** an empty `.claude/agent-memory/kongming/` now sits inside `evidence/s1/20261022T185101Z/`. The agent runtime created it because the session's working directory was the evidence dir. Delete it before committing that evidence, and run commands from the worktree root. I wrote no memory there for this reason.
- Keep the failed run's evidence dir as the first-failure record and commit it. The `evidence/.gitignore` already drops `ns3run/*.txt`. Never overwrite it.

## 5. T6? (Q5)
No. T6 applies when a Verify still fails after one kongming-guided fix, or when the fix changes the locked outcome. This is the first failure. The fix is in the harness only: no product code, pins, pass conditions or locked outcome change. It falls under "apply the guidance, then re-run".

If the fresh S1 gate does not exit 0 for **any** check, that is V1 failing again: print PAUSE T6 with no second self-fix. Also print T6 if a later reading shows the fix must change a pass condition.

## What to avoid
- Don't re-run S1 without the committed fix to "see if it passes". That would be re-running to get green.
- Don't relax the check, for example by accepting the pacer summary's `aborted` instead of the exit code, or by skipping `prc` for abort runs. Either one narrows a Verify.
- Don't put the status read back into `$(...)` in any later gate (R0–R3 will reuse this pattern). The function comment states that invariant.
- Don't add a `--only tctl` mode to the gate.

## Alternatives
- **File wrapper with a TERM trap that forwards the kill to python:** it works, but it is more code and more ways to fail. Rejected.
- **`wait -n -p` (bash 5.1+) in the parent:** also correct, but less readable than a plain `wait $pid` in the parent. No benefit here.

## Assumptions
- The VM's bash is the Ubuntu 24.04 `5.2.21` build I tested in the container. High confidence: the same distro and version, and the reproduction gives the same `-1`. A different bash could print 127 instead, but the fix holds on both, since I tested it on 5.2.21 and the mechanism is the same on 5.3.
- The tctl pacer exited 3. High confidence, from the summary, the empty stderr and pacer.py:225-228. The fresh run shows it directly.
- The plan's "same Verify fails again → T6" covers any red check in the fresh S1, not only this one. Medium-high confidence; it is the literal reading of V1 plus the Failure Protocol.

## Status
DONE. The diagnosis holds with a corrected mechanism, reproduced on bash 5.2.21. The fix is the parent-shell `wait`, not the file wrapper. Re-run all of S1 fresh. This is not T6.

## Next steps
1. Before any VM work, `cd` to the worktree root, delete `evidence/s1/20261022T185101Z/.claude/`, and update the resume card. The re-run is over 10 min.
2. Apply the `_pacer_finish` change and its two call sites from §2. Optionally add the self-test check from §2.
3. Run `scripts/gates/lint.sh`.
4. Record the root cause in `implementation-notes.html` (P2) as a finding:
   - the capture was racy (a status read in a `$(...)` subshell, not the pacer's parent);
   - the exit order in tctl, and the container reproduction table;
   - the fix, and the fact that no pass condition changed.
5. Commit and push in two commits, with no plan IDs in the messages:
   - the failed run's evidence as a record, e.g. `test(gates): record the first gate S1 run, red on reading the pacer exit`;
   - the fix, e.g. `fix(gates): read the pacer exit status in the shell that started it`.
6. Run `scripts/vm/vm-exec.sh gate-s1-pacer-lockstep.sh --timeout 7200 -- --p1-ns3 d3bc4d96… --p1-oi 2817f7e4…` fresh, which gives a new evidence timestamp.
7. If verdict.json passes, check:
   - `s1_run_tctl_runout_aborts_exit5` shows "pacer exit 3 (want 3)";
   - `nullControlDigestEqualsFreeRun` is true and `abortStep` is 30;
   - all checks PASS, plus the self-test if you added it.
8. Then run M5, M6 and M7 (V5) at the new pins, under the fix's harness SHA, and commit their evidence.
9. If any check in step 6 or 8 is red, print PAUSE T6, with a journal, a kongming note, the resume card and a push first. Do not attempt a second fix.
10. Then the P2 phase-exit checklist and a kongming go/no-go for P3. Before R0, check that T_ctl slack is not taken from `slackS` of aborted steps (§4).

## Unresolved questions
- None blocking. The self-test check in §2 is your call: I recommend it, but the container reproduction is enough as the minimum proof.

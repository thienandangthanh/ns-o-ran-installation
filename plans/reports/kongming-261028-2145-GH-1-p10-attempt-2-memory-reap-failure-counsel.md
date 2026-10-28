# kongming: P10 attempt 2 reaped by the memory-pressure reaper (Failure Protocol counsel)

Date: 2026-10-28 ~21:55 KST. Runtime: Claude Code, model opus (Opus 5.5), per the user's CLAUDE.md override. Advisory only. Host checks were read-only (ps, free, /proc, virsh read verbs, ls); no SSH, no virsh writes, no git writes.

## TL;DR
- Attempt 2 failed V1 and V2 for an environmental reason, not because of a harness defect. A Firefox launched from the user's hotkey daemon at 21:41:01 KST caused memory stalls. Ten seconds later, Claude Code's background-shell reaper killed the runner's process group.
- Formally it is a failed Verify, and this consult discharges the Failure Protocol. No fix is applied, so the one-fix budget is not spent. The question is moot anyway, because the re-issue resets the budget.
- Print **`PAUSE T8`**, worded as a harness (runtime) refusal, not a classifier refusal. The reaper forbids an agent restart, and the user releases T8 by re-issuing the goal.
- Record the `finish()` orphan gap; do not fix it before attempt 3. It is off the pass path, and fixing it would cost F″, which nothing requires.
- Ask the user four things:
  - close Firefox and Zotero for the whole run;
  - preferably restart Claude Code with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`;
  - ratify a memory pre-flight item: MemAvailable + qemu RSS ≥ 23 GiB with the VM running;
  - ratify revert → leaked-overlay deletion → df ≥ 84 as the re-run order.
- **Correction:** the leaked overlay is `ubuntu24.1793186558` (34 GiB), not `…1793186494`. The file `1793186494` is the frozen data of `m0-probe-o10281122` and must never be deleted. The resume card's line 26 is wrong and must be fixed before the PAUSE.

## Reframed problem
- **The decision.** Does this interruption (a) count against the fix budget, (b) require a harness change, and (c) which terminal PAUSE fits?
- **What attempt 3 needs** before it starts: memory and route conditions from the user, then the release sequence.
- **Constraints:**
  - K14 freezes `scripts` and `tools` at F′.
  - The reaper notice forbids an agent restart.
  - No test may be weakened, and the budget is frozen.
  - The 20:14 leaked-overlay ruling allows only its checks 1–5.

## Verified evidence
- **Kill mechanism.** `runner.log` shows `Terminated sleep 5`, which means the `sleep` inside `supervised()` got the TERM directly, so the signal went to the whole group. vm-exec has no TERM trap (`scripts/vm/vm-exec.sh`), so it died at once, and bash reaped it. `finish()` only stops the gate unit `if [ -n "$step_pid" ] && kill -0 "$step_pid"` (`scripts/run-to-m9.sh:122-125`). The check failed, so `vm_stop_gates` never ran: no failure line was logged, and the unit survived. The VM unit has no RuntimeMaxSec (`vm-exec.sh:55`); its only bound is the host-side poll loop that was killed.
- **Trigger.**
  - Firefox PID 220006 started at 21:41:01 KST (`ps lstart`). Its parent is `lefthk-worker`, the hotkey daemon, so the user launched it; no agent did.
  - At 12:41:28Z the host had 3 GiB available of 31, with qemu at 16.5 GiB RSS (the guest has 16 GiB configured).
  - `/proc/pressure/memory` still showed `full avg300=0.76` afterwards.
  - Right now the VM is off and Firefox and Zotero are still open: MemAvailable is 19.2 GiB. Starting the VM would bring the host back to about 3 GiB.
  - systemd-oomd is inactive. Claude Code is 2.1.312.
- **m3 was healthy.** It had run 2130 s against a measured 2492 s (`m9-budget.json` measuredS.m3). Host free was still falling (85 → 67 G, matching m3's known −24 GiB growth). There is no sign of a hang.
- **The F′ fix held.** The watchdog ran 157 checks with maxAgeS 32 ≤ 60. Attempt 1 broke at check 75.
- **Overlays** (domblklist, snapshot-dumpxml, ls):
  - `vda` is `ubuntu24.1793186558`: 36.5 GB, root:root, mtime 21:43:21. `m0/20261028T112207Z-host/disk-chain-after-branch-delete.txt` names it. No snapshot XML references it.
  - `fresh-install` has no `revertDisks`. Its `disks` source is `1792618108`, which is already gone. So the next revert leaks `1793186558`, as at 19:45.
  - `ubuntu24.1793186494` (30 MB) is the `<domain>` source of `m0-probe-o10281122`, i.e. that probe's frozen data. Likewise `1793179273` belongs to `m0-probe-n10280921`.
- **Freeze.** K14 holds: `git diff fb3554a HEAD -- scripts tools reference` is empty. `reference/r3p` contains no harness SHA.

## What to do
### Q1: budget and the orphan gap
- **Classification.** It is a failed Verify by the letter. V1 failed (exit 3 from the TERM trap, not 0) and V2 failed (m0–m2 only). This consult is the Failure Protocol's counsel step. Its guidance is environmental and needs the user, so there is no code fix to "apply".
- **Budget: not consumed.**
  - Record "Failure Protocol counsel given, no fix applied; cause environmental".
  - The re-issue resets the budget anyway (standing ruling of 2026-10-26), so attempt 3 starts with a fresh one-fix budget.
- **The orphan gap is a real defect, but only in the cleanup path of a failed run.** It never affects a pass, and the verdict stayed fail-closed (FAIL, correct problems list). Pre-flight check 6 (no active `gate-*` unit) already catches the residue before any re-run.
  - **Record it; do not fix it before attempt 3.** Put it in `implementation-notes.html`, as a known gap in the run report, and as a post-M9 fix.
  - Fixing it now means:
    - F″ and a new freeze;
    - a self-test case;
    - a review, with the Codex cap already spent;
    - re-proving K14.
  - All of that is for a non-causal change. Labelling it the "guided fix" would also be an improvised fix under the Failure Protocol's own wording.
  - Post-M9 shape: in `finish()`, treat a non-empty `step_pid` as "a step was in flight" (drop the `kill -0` test) and always call `vm_stop_gates`. Also change the fixed trap message at `:131` to "stopped by TERM (watchdog, monitor or an external signal)".
- **Pre-registered operator step (records only).** If the runner ends on TERM with no `watchdog-tripped`, `monitor-lost` or `wall-deadline` marker, the controller runs `vm_gate_units`, then `vm_stop_gates`, then `vm_shutdown`, and logs them under `reap/`. This is exactly what was done at 12:42Z.

### Q2: PAUSE id and the journal asks
- **Id: T8.** No id fits literally. T8's mechanism matches best: a Claude Code runtime control blocked a scripted command, and the instruction is "never work around it". Its release semantics also match: re-issuing releases T8 and resets the budget.
  - T6 is wrong: no fix failed.
  - T3 is wrong: the M9 signal can still be met as written.
  - The journal should state: "T8 (runtime refusal: the memory-pressure reaper killed run-to-m9.sh and forbids an agent restart; not a classifier refusal)".
- **The journal asks the user (one decision record after they answer, then re-issue):**
  1. **Required.** Close Firefox and Zotero (and any other heavy GUI app) before re-issuing. Launch no browser on this host until the run ends (expected about 4 h, wall cap 5 h 37 min). Closing Zotero is safe: P10 makes no new standards decision.
  2. **Recommended.** Start the attempt-3 Claude Code session with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`, either on the command line or in your own `settings.json` `env`. The variable is read when the session starts. Third-party reports describe reaps on hosts with 26–41 GB available, so false triggers are plausible over a 4 h idle wait. Only the user may set this; the agent never edits settings.
  3. **Route.** Keep phase-10 step 5's route, the Claude Code background shell. That keeps the exit notification and the user's process rule.
     - Launching through `systemd-run --user` or `nohup` *on the agent's own initiative* is a workaround: it escapes a runtime safety control the notice told us not to bypass, and it contradicts step 5.
     - It is legitimate only as an explicit user ruling. Even then it needs a step-5 amendment and an untested polling route.
     - The "Background VM jobs" rule covers VM-side gates through vm-exec, not the host runner, so it neither allows nor forbids this route.
  4. **Ratify the memory pre-flight item** (Q3).
  5. **Ratify the re-run order** (Q4): revert → checks 1–5 and deletion → df ≥ 84. A literal pre-flight 7 now reads df 67 < 84 and would PAUSE T2 before the revert that frees the space.
  6. **State that re-issuing means "start the M9 run again" (attempt 3, prefix p).** That satisfies the notice's "start it again only when asked".
  7. **Optional.** Fix the orphan gap now as F″ (not recommended), or after M9 (recommended).

### Q3: memory precondition (additive; no test or budget changes)
- **Gate.** After the revert, with the VM running and before launch: `MemAvailable + RSS(qemu-system-x86_64) ≥ 23 GiB`.
  - Rationale: qemu peaked at 16.5 GiB, rounded up to 17, plus at least 6 GiB of headroom at the peak.
  - Today, with the two apps closed, it would read about 26.5 and pass. At the reap it would have read 19.5 and failed. Now it reads 19.2 and fails, which is correct.
  - If it is red: do not launch, and PAUSE T3 naming the shortfall (or another id the user picks).
- **Records only, never gating.** Also record `printenv CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP`, `pgrep -a firefox` and `pgrep -af zotero`. At each step boundary, log `free -g` and `/proc/pressure/memory`.
- The 23 GiB value is a judgment, not a measurement. It is labelled so in the decision record.

### Q4: release steps for attempt 3 (corrected)
- **Before the PAUSE:**
  - Fix the resume card: vda is `ubuntu24.1793186558`, and `1793186494` is protected probe data.
  - The snapshot list now includes `m0-probe-o10281122`.
  - Then write the journal, update the notes, push, and print `PAUSE T8 …`.
- **On re-issue:**
  1. **Resume checks.** The VM is shut off, the current snapshot is `fresh-install`, and the chain is the 5 snapshots plus `m0-probe-n10280921` and `m0-probe-o10281122`. Write the user's rulings to `plans/reports/decisions-<ts>-…md`.
  2. **Pre-flight 2–5 at F′, unchanged.** Prefix p: no `p[0-9]-*` and no `m0-*-p*` names. n and o are spent, and m is invalid.
  3. **Revert `fresh-install`.** Expect the failed unlink of `1792618108` in the virtqemud journal, a new `ubuntu24.<epoch>` as vda, and `1793186558` left behind.
  4. **Leaked-overlay checks 1–5 on `1793186558` only**, logged under `evidence/p10-disk/<ts>/`. Then `rm` and `pool-refresh VMs`, and log the space freed (about 34 GiB, df about 101 G).
     - Check 5: the killed m3 unit's VM-side partial evidence (`/home/uc/evidence/m3/20261028T120541Z`) was never archived. Attempt 1's cancelled m2 partial was in the same state, and the user ruled on "similar files … after the same checks".
     - Do not boot the old overlay to fetch it: Influx and its token exist from m3 on.
     - Never touch `1793186494` or `1793179273`.
  5. **Checks.** `df -BG /home` ≥ 84 (88 with the margin), else PAUSE T2. `r3p-green` is listed. Pre-flight 6 finds no `gate-*` unit. The memory gate (Q3) passes.
  6. **Records.** Write the P10-start projection row, update the resume card, commit and push.
  7. **Launch** `scripts/run-to-m9.sh --harness-sha fb3554af67010dfedb6ae500e533acb7cdac9530 --run-prefix p --no-snapshots` with `run_in_background`. Record the start epoch and the deadline (wall 20199 s).
  8. **On exit, apply V1–V5 per the Stop B mapping.** A red Verify goes to the Failure Protocol with a fresh budget. Another reap: run the cleanup in the operator step (Q1), then PAUSE T8 again.

## What to avoid
- Do not delete `ubuntu24.1793186494`: checks 2 and 3 fail on it, and it would corrupt `m0-probe-o10281122`.
- Do not restart the runner, or detach it to dodge the reaper, without the user's ruling.
- Do not game the reaper's gates: no keep-alive subagent and no fake interactions.
- Do not add a memory watchdog, lower the guest RAM, or change `m9-budget.json`. Each is a frozen-script, environment or budget change.
- Do not call this T6: that misstates the budget. Do not ship the orphan fix as the "guided fix".
- The controller must not open browsers or GUI previews during the run.

## Alternatives and trade-offs
- **Apps closed only, reaper left on.** No session restart is needed. The cost is a residual false-trigger reap during a 4 h idle wait; each one costs a full revert and a re-run. It is acceptable as the minimum.
- **`systemd-run --user` route (user ruling only).** The run survives the Claude session ending. The costs: a step-5 amendment, no exit notification (the controller must poll), and a route that has never been run.
- **Fix the orphan gap now (F″).** Cleaner failure hygiene, at the cost of a new freeze, a self-test, a review and K14, with no effect on a pass. Not worth it before M9.

## Success metrics
- Attempt 3 exits 0 with all 14 steps.
- `minHostFreeGb` ≥ 25 and the watchdog is alive.
- No reap, no PSI `full` spikes in the boundary records, and the memory gate is green at launch.
- The space freed for `1793186558` is logged, and df ≥ 84 before launch.

## Assumptions
- **High confidence.** The reap was caused by memory pressure from Firefox. Evidence: ps, the notice, PSI.
- **High confidence.** Re-issue resets the budget and releases T8. Source: the goal packet's constraints.
- **Medium confidence.** Reaper internals (a PSI trigger, a 30-minute idle gate, the variable read at session start) come from third-party issue analyses of 2.1.251, not from official docs, and the host runs 2.1.312. Official docs contradicting this would change only ask 2, not the PAUSE.
- **Medium confidence.** The 23 GiB threshold. If qemu's peak RSS in attempt 3 exceeds 17 GiB, re-derive it.
- **Medium confidence.** Check 5 is satisfied under the attempt-1 precedent. If the user reads check 5 strictly, the cost is a VM boot and a scrubbed copy of the m3 partial, or PAUSE T1.

## Unresolved questions (for the user)
1. Which reaper option: the variable set or not?
2. Is T3 the right id for a red memory pre-flight?
3. Is check 5 met without archiving the killed m3 partial?
4. Fix the orphan gap after M9 (default), or now?

## Sources
- [Background tasks mass-killed by memory-pressure reaper on Linux (#78674)](https://claudeissues.com/issue/78674-background-tasks-mass-killed-by-memory-pressure-reaper-on-linux-hosts-with-low-m)
- [Memory-pressure reap kills only the tracked shell (#79727)](https://claudeissues.com/issue/79727-bug-memory-pressure-reap-kills-only-the-tracked-shell-child-process-tree-survive)
- [Docs omit memory-pressure reaping (#71459)](https://claudeissues.com/issue/71459-docs-background-shell-docs-omit-memory-pressure-reaping-and-claude-code-disable)

Status: DONE_WITH_CONCERNS
Summary: The cause is environmental. Print PAUSE T8, record the orphan gap without fixing it, and pre-register a memory gate. The leaked overlay ID in the resume card is wrong and must be corrected.
Concerns: the deletion target was misidentified as `1793186494`; the reaper's internals are not officially documented.

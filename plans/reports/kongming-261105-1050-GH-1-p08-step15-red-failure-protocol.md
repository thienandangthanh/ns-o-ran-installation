# kongming counsel: P08 cp2 chain step 15 red (runner re-read its edited script), Failure Protocol

Date: 2026-11-05 11:05 KST. Advisory only. Runtime: Claude Code subagent on Opus 5.5 (the user's CLAUDE.md overrides the `fable` routing).
Inputs: the driver `p08-gate-chain.sh`, `p08-gate-chain.tsv` and `p08-step-15.log` (session scratchpad), `scripts/vm/vm-exec.sh` at 668d1ef and HEAD, `scripts/vm/vm-common.sh` and the self-test at 293957f (`git diff b4109d2..293957f`, per the coordinator's update), the phase-08 work record, the plan's cross-cutting rules, the M8–M9 Failure Protocol and T6 text, the row 130 amendments, `plans/.gitignore`, the step-15 run dir and its watchdog dir.

## TL;DR

- The cause analysis is right; I reproduced it to the byte. Count this as **red #1 of P08**, so the next red is PAUSE T6. The failure is in the chain procedure: a long-lived runner was reading from a mutable tree, and the HEAD check ran only once, at chain start. That procedure can also produce a false green and wrong provenance, so this was not just bad luck.
- The frozen detached checkout is the right fix. Put it on **/home, not /tmp**: the tracked tree is 2.2 GB, /tmp is RAM-backed tmpfs, and the host has 7 GiB available while the VM runs. Freeze the driver itself too. Add a per-step check of the run dir, so that a runner-level exit 0 is never trusted on its own.
- I found no verdict-affecting defect in 293957f. Rerun the whole chain from step 0 after a revert, at the SHA left after the Codex 6 triage. Do the pre-revert checks first: confirm the step-15 copy is complete and run a short runner smoke into a scratch evidence root.

## Reframed problem

There are three decisions here:
1. How to classify the stopped chain under a Failure Protocol that P08 applies literally.
2. How to make the next 20-step, roughly 5.5-hour chain immune to the operator's parallel harness work. The parent keeps reviewing and fixing while chains run: Codex run 3 ran beside a chain, and runs 4 to 6 ran during or right after one.
3. How to rerun with the T6 tripwire armed without spending it on tooling.

The goal is one uniform cp2 chain at one harness SHA, with `m10-cp2` tagged at that SHA. Non-goals: changing any gate predicate, and re-arguing row 130.

## Q1. Cause, and whether it is a red

**Cause (verified).**
- At 668d1ef, the poll loop of `vm-exec.sh` ends at byte 5177 (line 112). Bash had parsed the whole `while … done` and was going to resume reading the file at that offset.
- In the edited file, which equals 33b4992, byte 5177 falls mid-comment. Bash's line counter reads it as line 113, `ns-3 trace text files get sha256`, which gives `ns-3: command not found`.
- Lines 114–122 of the new file are textually the old scrub, manifests, `mkdir` and `tar` commands, so the scrub and the copy did run.
- The `disk_end=` assignment sat before the offset and was skipped. Line 123's `printf … "$disk_end"` then failed under `set -u`, and a script file exits with 1 on that (checked on bash 5.3.20; `bash -c` would give 127).
- The EXIT trap was the old in-memory `wd_on_exit`. With no WD_DONE set and no latch, it stopped the watchdog session and wrote nothing.
- So the run dir has everything except `host-disk.tsv`, `host-disk-watchdog.json` and the `.last-r3p` update. `.last-r3p` still points at step 14 (`20261105T005919Z`).
- The watchdog dir `evidence/watchdog/r3p-20261105T012217Z/` shows a minimum of 54 GiB and no `watchdog-tripped.json`. Its last sample is at 01:45:39Z, 4 s before the exit. The floor held.

**Classification: count it as red #1.** Reasons:
1. `vm-exec.sh:7-8` defines its exit status as the gate's verdict, and the driver treats any non-zero status as red. The Verify did not meet its stated condition (a clean step exit plus row 130's records). The green VM-side verdict does not undo that: by the runner's own contract, the step is red.
2. The run dir lacks row 130's `host-disk-watchdog.json` and `host-disk.tsv`. The step could not count toward cp2 even at 668d1ef.
3. The root cause is a defect in the procedure, not an environmental accident:
   - Host-side code ran from a mutable tree.
   - The `HEAD == sha` guard ran once, at chain start, while 1bd18bd and 33b4992 landed mid-chain. Had step 15 not crashed, steps 16–19 would have run 33b4992's host-side code under `--harness-sha 668d1ef`.
   - The same class can **false-green**. If the stale offset lands past `exit "$code"`, bash reaches EOF with the loop's `break` status, 0. Nothing is copied and the driver moves on.
4. The P10 attempt-2 precedent (the memory reaper, "environmental, no fix, budget not spent") does not fit. That cause was external and nothing was changed. Here the agent's own edit caused the red, and a guided fix (the driver change) is being made, and that is what the one-fix budget is.
5. "Do not reason around the failure" (Failure Protocol) argues against the agent reclassifying its own incident.

The cost is small, because the chain must rerun anyway (33b4992 and 293957f changed the SHA) and the user is engaged. Disclose the classification at Stop A′. The user, as decision owner, may rule it a non-red, and that would only restore the budget.

Codex findings and their fixes (rows 130 amendments, 293957f) are not reds and do not spend the budget. Only the driver change is this red's guided fix.

## Q2. The fix

**Recommended: a frozen checkout plus a hardened driver, with no harness change.**
1. **Put the frozen checkout on /home**, outside the main worktree and outside Orca's workspace root (for example `$HOME/.cache/ns-o-ran-frozen-harness/<sha>`). Do not use the scratchpad.
   - `git archive HEAD | wc -c` is 2,238,914,560 bytes, most of it the M0–M7 plan (1.47 GB) and the M8–M9 plan (0.6 GB).
   - /tmp is tmpfs (16 G). `free -g` shows 7 GiB available with the VM up. P10's memory gate was MemAvailable + qemu RSS ≥ 23 GiB, and the reaper fired at 3 GiB available. A 2.2 GB tmpfs checkout would eat that margin.
   - On /home it costs about 2.2 GiB against a floor margin of roughly 25 GiB.
2. Create the checkout and protect it:
   - `git -C "$repo" worktree add --detach "$frozen" "$sha"`, then `git worktree lock --reason "cp2 chain $sha" "$frozen"`, so nothing prunes it mid-chain.
   - Optionally `chmod -R a-w "$frozen/scripts"`, so that a stray Edit fails loudly.
   - Remove it after the chain (`chmod -R u+w`, `git worktree unlock`, `git worktree remove`).
3. **This works with how `vm-exec.sh` finds things** (verified):
   - `REPO_ROOT` comes from `BASH_SOURCE` (`vm-common.sh:17`), so it becomes the frozen dir.
   - A linked worktree shares `refs/remotes/origin/*`, so `fetch` and `branch -r --contains` (`vm-exec.sh:34-36`) still test the real GitHub push.
   - Keep exporting `EVIDENCE_HOST_ROOT`. The default (`vm-common.sh:20`) would point into the frozen tree's M0–M7 plan.
   - Everything `vm-exec.sh` and `host-disk-watchdog.sh` read is tracked, under `scripts/`.
4. **Per-step guard in the driver:**
   - `git -C "$frozen" rev-parse HEAD` equals the sha, and `git -C "$frozen" status --porcelain --untracked-files=no` is empty.
   - Run `bash "$frozen/scripts/vm/vm-exec.sh" …`.
   - Log the frozen HEAD and the driver's sha256 into the tsv.
5. **Run-dir cross-check after every step.** Never trust exit 0 alone.
   - Require `.last-<gate>` to have been rewritten after the step started (mtime), and take `dest` from it.
   - `dest/exit_code` = 0.
   - `host-disk.tsv` is present.
   - `host-disk-watchdog.json` has `tripped: false`.
   - If `verdict.json` exists, `pass` is true.
   - Before the chain, validate this check offline: the 15 green 668d1ef dirs must pass it, and step 15 must fail on the two missing files. A cross-check that misfires in the rerun would be a red at T6.
6. **Freeze the driver itself.** Wrap its body in `main() { …; }; main "$@"; exit` (or `{ …; exit; }`), so bash parses the whole file before running it. Never edit it while it runs. The `for` loop is already parsed whole, but the lines after it are read late, so an edit to the driver can still misfire.
7. Add a short ledger note before the driver change, since it adds red conditions to the chain procedure (additive, ops). Commit a copy of the driver with the chain evidence. Today it lives only in volatile /tmp.

**Alternatives weighed:**
- **A `{ …; exit; }` wrapper inside `vm-exec.sh`.** It is good defence in depth, but it is weaker than the frozen checkout:
  - it does not fix provenance across mid-chain commits;
  - it needs a new harness SHA, plus a review round;
  - it covers one file only.
  - (`host-disk-watchdog.sh` happens to be safe already, because it only leaves its `while :` loop by `exit`.)
  - Make it a hand-off for the M10 runner. `run-to-m9.sh:56` checks `git diff --quiet` only at start and runs from the worktree, so the M10 unattended run has the same hazard. Launch that run from a frozen checkout too.
- **Refusing a dirty tree.** It is wrong on two counts:
  - It checks at start only, and this edit came mid-run.
  - The worktree always has untracked evidence. A guard scoped to `scripts/` would have made the step after an uncommitted Codex fix red, spending T6 on the guard.

## Q3. Review of 293957f

`git diff b4109d2..293957f -- scripts/vm/vm-common.sh` is byte-identical to the working-tree diff I reviewed at 01:57Z.

**Findings:**
- **No verdict-affecting defect found.** A red cannot become green, because the final `exit "$code"` is untouched, and an EXIT trap that returns keeps the shell's status (checked: `trap f EXIT; exit 3` gives 3). On the normal path, a clean gate can turn red only through a real trip, a failed finish, or an outside TERM.
- **The traces hold:**
  - A held TERM in `wd_start` gives 143 through `wd_on_exit`, which writes the stop request, waits, sweeps once and records nothing.
  - A trip during `wd_end` (its sleep child killed, the runner's TERM held) completes, records 1 and exits 125.
  - A `wd_start` failure leads to a die, which waits for the TERMed child, sweeps a session nobody has, and exits 1.
  - The single `pkill -KILL -s` after the reap is safe. Linux keeps a struct pid referenced while any member holds that sid, and a fresh reuse within about 1 s would also have to be a session leader.
- **Cosmetic windows (both red, record correct):**
  - In `wd_end`, `trap wd_term_exit TERM` comes before `[ "$rc" -eq 0 ] || exit 125`. A TERM in that gap exits 143 instead of 125. Swap the two lines if another commit happens anyway.
  - A held TERM during `wait "$pid"` in `wd_finish` makes `wait` return above 128. Because the job is already reaped by then, the window is microseconds.
- **What the self-test structurally cannot see:**
  1. Its runners are `bash -c` strings, so they are fully in memory and blind to the step-15 class. That is why the driver cross-check matters.
  2. It never runs `vm-exec.sh` itself, so the real `wd_record` Python, `$dest`, and the real ssh and virsh are first exercised by the chain's M2.
  3. Nothing asserts that a red gate's code passes through a clean `wd_end`. Bash semantics make it safe today; it would be a one-line case if wanted.
- **Operational consequence:** an outside TERM is now a clean 143, which is a red, which is T6. The launch route matters more than before:
  - `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` was unset in the environment this counsel ran in.
  - The reaper fires after 30 min without terminal interaction, under memory pressure.
  - So prefer the P10-ratified hybrid `systemd-run --user` route: `KillMode=mixed`, `OOMPolicy=continue`, `StandardOutput=append:`, never `--pipe`. Otherwise, hold the memory gate and keep the session interactive.

## Q4. Evidence

- **Step 15 (`r3p/20261105T012217Z`):**
  - Keep it in place and commit its verdict layer, as P07's red runs were (`r1/20261104T175831Z` is in git), with its `evidence-sha256.txt`.
  - Label it in the work record: "runner incident, red #1, not counted".
  - Do not create `host-disk.tsv` or `host-disk-watchdog.json` for it after the fact. Cite the step log's start line (54 GiB, overlay 28 GiB) and the watchdog dir's values instead.
  - Commit the incident trio, which today exists only in volatile /tmp: the driver, `p08-gate-chain.tsv` and `p08-step-15.log`. Put them in a dedicated evidence dir with a commented `plans/.gitignore` negation, as `p03-unit` has.
- **The 15 green dirs at 668d1ef:**
  - Keep them and commit their verdict layer, labelled "superseded: chain at 668d1ef stopped at step 15; not cp2 evidence".
  - They cannot all be proven to have run 668d1ef host-side code (the edit times are unknown), which is one more reason they are superseded.
- **Raw archive:**
  - Make one archive for the 668d1ef chain. Include the 16 run dirs, their `evidence/watchdog/<gate>-<ts>/` dirs (gitignored; the step-15 one is the only proof the floor held) and all `p08-step-*.log` files.
  - Past phase archives were 30–171 MB. /mnt/data at 6.5 GiB stays above the 5 GiB floor for this archive and the rerun's.
  - Podman storage also lives on /mnt/data, so check `df` after any host container work.
- **Optional:** add `!/*/evidence/*/*/**/host-disk-watchdog.json` to the allowlist. It is the row-130 record, it is small, and today it never reaches git.

## Q5. Rerun plan (ordered)

1. **Settle the SHA.**
   - Codex 5 is already triaged and fixed (87c3757, b4109d2, 293957f).
   - Pre-decide the Codex 6 triage rule now. A finding blocks the chain only if it can turn a clean run red, or a red run green, on a realistic path; those get fixed and the SHA changes. Hardening-only findings, such as narrow TERM or trip timing windows, get a ledger note and a fix after the chain.
   - Do not commit harness fixes while the chain runs. Each one forces another full rerun.
   - Then lint, the self-test and the mutation checks, and push.
2. **Record before acting.**
   - The work record entry (red #1; the cause with the byte-5177 proof; the guided fix).
   - The ledger note for the driver's added red conditions.
   - The resume card, and the Stop A′ disclosure line.
   - Commit.
3. **Before the revert (VM-side evidence dies with it):**
   - Compare step 15's copy against `/home/uc/evidence/r3p/20261105T012217Z` (file count and `du -sb`; the host has 852 files).
   - Confirm no `gate-*` unit is active and no host `vm-exec` or watchdog process remains.
4. **Build the frozen checkout and the driver** (Q2), and validate the cross-check offline on the 668d1ef dirs.
5. **Optional runner smoke**, still before the revert, on the current VM:
   - Command: `EVIDENCE_HOST_ROOT=<scratch> bash "$frozen/scripts/vm/vm-exec.sh" gate-m6-kpm.sh --harness-sha <sha> --timeout 900`. M6 took 2 min in the chain.
   - Judge only the runner, not the verdict:
     - the runner's exit equals the VM's `exit_code`;
     - `host-disk.tsv` and `host-disk-watchdog.json` (`tripped: false`) are present;
     - the watchdog session is empty.
   - It is a pre-flight, not a Verify. Disclose it.
   - Never run it after the revert, because it would dirty f7-rerun-green before M2.
6. **Revert.**
   - Shut the VM off, revert to f7-rerun-green (`--pending` checked, no orphan overlays), and confirm `ubuntu24.1793829629` (28 GiB) is unlinked.
   - Require `df -BG /home` ≥ 80 GiB. This chain started at 83 and was at 54 by step 15.
   - At about 54, the overlay leaked. Run leaked-overlay checks 1–5 under the 2026-10-28 ruling and do not start: the chain would end around 24 GiB against the 22 GiB trip, so a watchdog red would become T6.
   - Re-copy asn1-indep and run `sha256sum -c`.
7. **Launch.**
   - Check the memory gate and the launch route (Q3).
   - Run all 20 steps from step 0, in the same order, at the one SHA.
   - Any red, including 125 and 143, is PAUSE T6. Do not reclassify.
8. **After the chain:**
   - Run the cp2 checks.
   - Tag `m10-cp2` at the verdict SHA (not at HEAD) and push.
   - Commit the verdict layer, make the raw archive, and remove the frozen worktree.

## What to avoid

- A frozen checkout under /tmp (tmpfs, 2.2 GB of RAM), or a sparse worktree trick that writes `extensions.worktreeConfig` into shared config.
- Trusting `vm-exec.sh` exit 0 without the run-dir cross-check.
- Reading `.last-<gate>` without checking it was rewritten during this step.
- Editing or re-launching the driver mid-chain.
- Creating missing records for step 15 after the fact.
- Reclassifying the next red as tooling.
- Starting the chain with /home near 54 GiB.

## Success metrics

- The chain finishes 20/20 at one SHA, with every run dir carrying `host-disk.tsv` and `host-disk-watchdog.json` (`tripped: false`).
- The driver's tsv logs the frozen HEAD equal to the sha at every step.
- `m10-cp2` equals the verdict SHA.
- No orphan worktree, watchdog or VM unit is left.
- The work record and Stop A′ disclose red #1 and its fix.

## Assumptions

- **High:** steps 0–14's VM-side verdicts are unaffected. The gate code ran from the VM clone at 668d1ef; only the host runner was hit.
- **High:** the in-progress edit at resume time matched 33b4992 through line 123. The line numbers fit exactly, and the commit landed 4.5 min after the failure.
- **Medium:** the parent shares this counsel's environment, so the reaper env var is unset there too. If the session was started with it set, the launch-route point weakens to "keep the memory gate".
- **Medium:** "red" in P08 means any non-zero Verify step exit, as in M8–M9 practice ("a red now = PAUSE T6"). If the user rules that runner-only failures with a green VM verdict are not reds, the budget is restored and nothing else changes.
- **Low:** I have not checked whether a `post-checkout` hook exists; the scout block denied `.git` reads. If one exists, it runs once at `worktree add`.

## Unresolved questions

1. Should the user ratify the red-#1 classification at Stop A′, or now, given that they are engaged?
2. Will the user accept the Codex 6 triage rule (only verdict-affecting findings block the chain), or do they want every finding fixed before the chain, at the cost of a rerun each time?
3. Launch route for a T6-armed 5.5 h chain: the P10 hybrid `systemd-run --user` route, or the background shell that ran steps 0–14 without incident?
4. Should `host-disk-watchdog.json` join the verdict-layer allowlist?

# Code review: F′ heartbeat fix (watchdog atomic heartbeat + self-test case 8)

Date 2026-10-28 ~19:35 KST. Read-only review. No VM, ssh, virsh or Codex calls were made.

## Scope
- Diff `239d09f..fb3554a -- scripts`: `scripts/vm/host-disk-watchdog.sh` (+3/-1), `scripts/vm/m9-runner-selftest.sh` (+19/-1, case 8).
- Read-only sweep: `scripts/run-to-m9.sh`, `scripts/vm/m9-heartbeat-monitor.sh`, `scripts/m9-verdict.py`, `scripts/vm/vm-common.sh`, `scripts/m9-budget.json`, attempt-1 evidence `evidence/m9/20261028T092148Z/`, kongming counsel §2.
- Checks I ran:
  - `bash -n` on all 5 shell files: ok. `shellcheck -S warning` on watchdog, monitor and selftest: clean.
  - Self-test in the worktree, 2 runs: 10/10 ok both times, exit 0, 29-30 s each. That fits inside `lint.sh:55`'s `timeout 120`. `pgrep` afterwards showed no leftover watchdog, monitor, `sleep 300/301` or dummy runner, and no leftover `/tmp/tmp.*`.
  - Independent red/green check in the scratchpad:
    - The new self-test against `git archive e0a6ac5 scripts` FAILS case 8 ("no watchdog heartbeat").
    - A variant watchdog using `echo "$(date +%s)" >"$out/heartbeat"` PASSES case 8 (see N2).
  - Freeze scope: `git diff --name-only e0a6ac5 HEAD -- scripts tools <reference>` lists only the 2 files. The frozen set (gates, tools, pins.conf, m9-budget.json, run-to-m9.sh, m9-verdict.py, monitor, vm-common.sh, reference) has no diff. fb3554a is on origin.
- Line numbers below are at HEAD. The fix is at watchdog `:62`. The min-file write is `:65` (it was `:63` at e0a6ac5).

## Overall assessment
The fix is correct and enough for the observed defect:
- A rename inside the same directory is atomic for the monitor's single `cat`.
- `&&` skips the rename if the temp write fails, so a failed write shows up as a stale heartbeat and the run fails closed.
- The monitor is unchanged and still strict.
- Case 8 runs the shipped watchdog, is isolated from the VM, fails at e0a6ac5 and passes at fb3554a.
- No must-fix. Two should-fix items exist, but both are in K14-frozen files and are not triggered at the projected disk margin. They need the user's decision, not a quiet fix.

## Must-fix (blocks the M9 re-run)
None.

## Should-fix (not blocking; frozen files, so the user decides)

### S1. `df -BG` rounds UP: the effective trip is ≤ 28 GiB, and the verdict floor passes at a real 24.x
- **Where:** `scripts/vm/vm-common.sh:81` `host_free_gb() { df -BG --output=avail /home | tail -1 | tr -dc '0-9'; }`
- **Evidence (measured here):** statvfs reports 84.43 GiB free, while `df -BG` prints `85G`. GNU df rounds sizes up.
- **Failure scenario:**
  - At a real 28.5 GiB, the watchdog sees 29. `[ 29 -ge 29 ]` holds, so there is no trip. It trips only when the real free space is ≤ 28.00 GiB.
  - At a real 24.3 GiB minimum, `min-host-free-gb.txt` records 25, and `m9-verdict.py:70` (`mf < floor`) passes. That is a false green of the floor by less than 1 GiB.
  - This adds to the attempt-1 finding (peak growth 0.022 GiB/s, so h ≈ 9 against the frozen 4).
- **Fix:** round down, e.g. `b=$(df -B1 --output=avail /home | tail -1 | tr -dc 0-9); echo $((b / 1073741824))`.
  - This changes `vm-common.sh`, which `vm-snapshot.sh --need-gb` also uses, and it changes trip semantics.
- **Re-run impact:** it matters only within 1 GiB of 29 or 25. The projected minimum is far above both, so it is not blocking.

### S2. A cancel during a `--no-snapshots` boundary reboot can leave the VM running
- **Where:** `run-to-m9.sh:177` (`vm_shutdown && vm_start`, not supervised), `finish` at `run-to-m9.sh:120-130` (no `vm_shutdown`), monitor `cancel` at `:36-41`, watchdog `trip` at `:48-54`.
- **Failure scenario** (P10 runs with `--no-snapshots`, so 8 boundary reboots):
  1. The monitor or watchdog cancels while the runner is in the boundary's `wait_state "shut off"`.
  2. The canceller's `vm_shutdown` and the runner's `vm_shutdown` both poll every 3 s. The runner sees "shut off" first and calls `virsh start`.
  3. The canceller's `wait_state` then never sees "shut off" again, times out after 240 s, and TERMs the runner, which is now in `wait_ssh`.
  4. `finish` has `step_pid` empty, so it only kills the monitors and writes the verdict. The VM is left booted with nothing watching it, and after a trip the watchdog is gone too.
- **Effect:** the verdict still fails closed, so this is neither a false red nor a false green. It leaves partial state: a running VM after a stop.
- **Probability:** the windows are about 12-26 s per boundary, roughly 1-2 % of the run.
- **Fix:** in `finish`, when rc ≠ 0, call `vm_shutdown` (bounded) after stopping the step. Optionally, re-check `vm_state` after the canceller's TERM.

## Notes

### N1. The fix's failure modes are fail-closed, and a leftover tmp file is harmless
- **Temp write failure** (ENOSPC, EACCES): `date` exits non-zero (it checks for write errors at exit), so `mv` is skipped. The heartbeat then goes stale and the monitor cancels within about 60-90 s. That is fail-closed and correct: a watchdog that cannot write is equivalent to a dead one. A full `/home` cannot occur before the trip anyway.
- **`mv` failure:** the same stale heartbeat follows. The error goes to the runner's stderr, so it is visible.
- **Leftover `heartbeat.tmp`** (TERM between the write and `mv`): nothing reads it, and the next run's first poll overwrites it. It cannot block a run, because `run-to-m9.sh:58`'s untracked-file check covers only scripts, tools and the reference, not evidence. The only risk is git hygiene: an untracked file may sit in `evidence/watchdog/`, so do not `git add` that directory wholesale.

### N2. Case 8 catches the shipped regression, but not the whole bug class
- It is red on the exact old form (`date +%s >heartbeat`, now verified independently).
- `echo "$(date +%s)" >"$out/heartbeat"` is still truncate-then-write, with a microsecond window, yet it passes case 8 (verified), because the slowed `date` runs before the redirect opens.
- This is acceptable: the fix's mechanism is the rename, and attempt 1 proved that a window of a few ms is hittable in production.
- Optional hardening: a lint grep asserting that the watchdog never redirects directly into `"$out/heartbeat"`. It would be brittle, so this stays a note.

### N3. Case 8 is isolated from the real VM (verified)
- `VM_SSH`/`VM_DOMAIN` are honoured (`vm-common.sh:7-8`).
- `--min-gb 0` cannot trip at a real free of ≥ 0. If `df` ever returned empty, the trip would run, but it would call `ssh selftest.invalid` and `virsh … selftest-absent`, both fail, and with no `--runner-pid` it kills nothing.
- The monitor gets `--stop-cmd`, so it never calls `vm_*`.
- `--out "$d"` writes only under `mktemp -d`.
- No leftovers remain after the explicit kill plus the EXIT trap. Orphaned `sleep 0.3`, `date` and `sleep 1` children exit within about 1 s.

### N4. Case 8 can flake only toward FAIL, never toward a false pass
- The first heartbeat lands about 0.35 s after the watchdog starts, and the monitor's first read is at ≥ 1 s.
- `checks >= 5` needs about 5 of the 8 s.
- Under heavy load it could fail falsely. It cannot pass the old writer, except with probability about 0.5^7 per run.

### N5. `min-host-free-gb.txt` (watchdog `:65`) is read after a kill without a wait: assessed concretely
- **Sequence:** `finish` runs `kill "$wd_pid"` (`run-to-m9.sh:127`), then `write_verdict`. Python startup takes about 30 ms, after which the verdict reads the file.
- **How it can tear:** the write is a bash builtin: `open(O_TRUNC)`, then `write`. TERM has its default disposition and is delivered at a syscall return, so the watchdog can die between the two and leave the file empty.
- **When:** only on polls that lower the minimum (16 of 76 in attempt 1), and only if the TERM lands in that window of a few µs. That gives about 1e-7 per run.
- **Outcome:** `m9-verdict.py:66-69` reports "no minHostFreeGb recorded", so the verdict FAILs. Fail-closed only, never a false green.
- I agree with the counsel: leave it. If it is ever touched, the fix is the same one-line temp-and-rename.

### N6. Wall deadline: the verdict has no deadline input (false green of up to one interval)
- `m9-verdict.py` checks only that `wall-deadline.json` exists.
- The monitor checks about every 30 s (`m9-heartbeat-monitor.sh:57`). A run whose last step ends in (D, D+≈30 s] gets `finish` → kill monitor → PASS.
- A backward NTP step also extends D.
- **Fix** (in frozen files): pass `--deadline-epoch` to the verdict and require `end <= D`.
- The probability is negligible: about 13.7 ks expected against a 20.2 ks deadline.

### N7. A hung but alive watchdog near the end is a false green of up to about 2 intervals
- `supervised` checks only liveness (`run-to-m9.sh:150`).
- The verdict sees `maxAgeS` only as sampled by the monitor.
- If the watchdog hangs (alive, not writing) within about 60-90 s of the end, the verdict passes.
- **Fix:** the verdict also reads `heartbeat` and requires `end - hb <= 2*interval`.
- No realistic hang source exists (statfs on a local filesystem, `date`).

### N8. Wall-clock dependence: host suspend or a forward clock step falsely reds a healthy run
- The heartbeat age and the deadline both use `date +%s` (monitor `:48`, watchdog `:62`).
- `sleep` (nanosleep, monotonic) does not count suspend time. After a resume the monitor can wake before the watchdog's next write and see an age of about 30 s plus the suspend time, which exceeds 60 and cancels.
- The host has no battery and `systemd-timesyncd` is enabled.
- **Mitigation (operational):** launch the runner under `systemd-inhibit --what=sleep:idle --why=M9 …` and confirm the desktop environment does not auto-suspend.

### N9. A `df` failure or empty output trips and loses the trip record
- With `free=""`, `[ "" -ge 29 ]` returns 2, so `trip ""` runs (watchdog `:66`). It stops the units, shuts the VM down and TERMs the runner.
- `int("")` raises before `open()` (`:39-47`), so `watchdog-tripped.json` is never written.
- The verdict FAILs with no trip marker, and only `runner.log` explains why.
- This is fail-closed, and the cause (statfs failing on `/home`) is very unlikely.
- **Fix:** validate `^[0-9]+$` and record the reason.

### N10. A trip lasting more than 60 s triggers a concurrent monitor cancel
- A trip can take up to about 290 s with no heartbeat, so the monitor also cancels. The result is `watchdog-lost.json` next to `watchdog-tripped.json`, a double shutdown, and the monitor's child sweep killing the watchdog mid-trip.
- `watchdog-tripped.json` is written after at most about 56 s of bounded ssh calls, so it is almost always present.
- Either way the verdict FAILs. The only cost is diagnostic noise.

### N11. No lock and no runner-liveness check
- If the runner is SIGKILLed or OOM-killed, the watchdog loops forever.
- The monitor runs until D, then shuts the VM down and TERMs whatever process then owns `runner_pid`.
- A second run on the same `$wd` would interleave writes.
- This is mitigated by the P10 pre-flight check "no host runner/watchdog/monitor/vm-exec process". Keep that check.

### N12. `supervised` uses `kill -0` on reaped PIDs
- Bash reaps its async children, so a dead watchdog's PID can be reused (`pid_max` is 4194304). That could produce a false "alive".
- The monitor's staleness check makes this redundant, so there is no false green.
- The self-test comment at `:85` ("a reaped child, so it cannot belong to a live process") is inaccurate in principle, but harmless.

## Same-class sweep: files one host M9 process writes while another reads

| File | Writer | Concurrent reader | Status |
|---|---|---|---|
| `heartbeat` | watchdog | monitor | fixed (rename) |
| `watchdog-alive.json` | monitor | verdict | already atomic (`:54-55`) |
| `min-host-free-gb.txt` | watchdog `>` | verdict, `cp` | torn → FAIL only, ~1e-7 (N5) |
| `free-series.tsv` | watchdog `>>` | `cp` only | evidence only; a partial last line at worst |
| `watchdog-lost.json`, `wall-deadline.json`, `monitor-lost.json`, `watchdog-tripped.json` | `>` | verdict uses `os.path.exists` | a torn write is irrelevant; existence fails closed |
| `steps.tsv`, `.last-<step>` | runner / vm-exec, sequential | runner, verdict | not concurrent |
| `verdict.json` | python `open("w")` | humans | a TERM during write is re-run by the re-entered trap |

## Requirement check
"Stop only on a real dead watchdog, a real low disk (< 29 GiB) or the wall deadline; the verdict fails closed otherwise":
- **Met for the torn read.**
- **Residual deviations:**
  - S1: the trip fires at ≤ 28 GiB real, not < 29.
  - N6 and N7: false-green windows of one interval each.
  - N8: a suspend or clock step can red a healthy run.
- None is a regression from F′, and none is likely in the re-run.

## Plan follow-ups
- Counsel §2 Change 1 and Change 2 are done. The red/green proof is recorded and I reproduced it independently.
- Next steps per the counsel: CX-3 Codex review, then the K14 statement, revert, df re-measure, and run with prefix `o`.
- Consider wrapping the launch in `systemd-inhibit` (N8): it is operational and not a code change.

## Unresolved questions
- S1: should host free be rounded down (a `vm-common.sh` change, frozen set)? Or should the 1 GiB rounding be accepted as part of the h = 4 margin? This is the user's call, and it is coupled with the deferred h ≈ 9 finding.
- S2: fix `finish` to shut the VM down on a cancel before the re-run, or after M9? It touches the frozen `run-to-m9.sh`.

Status: DONE_WITH_CONCERNS
Summary: The F′ fix is correct, fail-closed and properly regression-tested (case 8 is red at e0a6ac5 and green at fb3554a, VM-isolated, no leftovers), and nothing blocks the M9 re-run. Two should-fix items in frozen files (df -BG rounds up the trip and floor; a cancel during a no-snapshot reboot can leave the VM running) plus notes on wall-deadline and clock edge cases.
Concerns/Blockers: S1 and S2 need a user decision because they touch K14-frozen files. Case 8 does not catch a builtin-echo truncate-then-write regression (N2).

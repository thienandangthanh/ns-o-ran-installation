# M8–M9, P10 attempt 2: PAUSE T8, the runner was reaped for host memory (2026-10-28 21:58 KST)

## What happened
- The goal was re-issued at 20:17 KST, after PAUSE T1. The pre-flight passed, the revert to `fresh-install` was clean (101 G free), and the projection was +17.
- Attempt 2 ran as `scripts/run-to-m9.sh --harness-sha fb3554af67010dfedb6ae500e533acb7cdac9530 --run-prefix o --no-snapshots`, in a Claude Code background shell, as phase-10 step 5 prescribes. Its evidence is in `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T112207Z/`.
- m0, m1 and m2 went green at 11:24:59Z, 11:49:06Z and 12:05:39Z. The F′ heartbeat fix held through m2, where attempt 1 had failed: 157 watchdog checks, maxAgeS 32.
- At 12:41:11Z, while m3 (`gate-m3-xapps.sh`) was running healthily, Claude Code's memory-pressure reaper killed the background shell. Its notice said the kill was "not a failure of the command" and told me not to start the shell again unless the user asks.
- Host memory at 12:41:28Z: 3 GiB available out of 31, and 13 GiB of swap in use.
  - qemu (the 16 GiB guest) held 16.5 GiB.
  - Firefox, launched about 10 s before the reap, held about 6 GiB.
  - Zotero held 1.3 GiB.
  - The guest itself had 13 GiB available.
- The runner's TERM trap wrote verdict FAIL: steps m0–m2 only, `minHostFreeGb` 67, watchdog alive. Disk space was never the cause.
- Verify failed on V1 (exit 3) and V2 (step set incomplete).
- The evidence is in `evidence/m9/20261028T112207Z/reap/`: `host-state.txt`, `runner.log`, `free-after.txt` and `snapshots-after.txt`.

## Harness gap found
`run-to-m9.sh` `finish()` stops the VM gate units only while `step_pid` is alive. The reaper killed the whole process group, vm-exec included, so `gate-m3-20261028T120541Z` kept running on the VM. The TERM trap's fixed message, "stopped by the disk watchdog or the heartbeat monitor", also names the wrong sender.

I ran `vm_stop_gates` (rc 0, no gate unit and no ns-3 process left) and then `vm_shutdown` (shut off). These are the same actions as the runner's own cancel path. Host available memory went back to 19 GiB.

Per the kongming counsel, the gap is recorded and is fixed after M9. Fixing it now would need F″ and a re-freeze, for a change that does not touch the cause. Pre-flight check 6 already catches a leftover unit.

## Failure Protocol
Counsel: `plans/reports/kongming-261028-2145-GH-1-p10-attempt-2-memory-reap-failure-counsel.md`.
- The cause is environmental, and no harness fix is due.
- The one-fix budget is not spent.
- The Claude Code notice forbids a restart without the user, so this is PAUSE T8: the runtime refused to continue a scripted command. I did not work around it.
  - T6 does not apply, because no guided fix failed.
  - T3 does not apply, because M9 can still be met as written.

## VM and disk state now
- The VM is shut off, and snapshot-current is `fresh-install`.
- The snapshots are: `fresh-install` > `f7-rerun-green` > `r0-green` > `r2-green` > `r3p-green`, plus `m0-probe-n10280921` and `m0-probe-o10281122`.
- The active overlay is `ubuntu24.1793186558` (36.5 GB). gate-m0-host left it untracked, so the next revert will leak it. It is deletable under the 20:14 ruling (`plans/reports/decisions-261028-2014-GH-1-leaked-overlay-deletion-ruling.md`) once checks 1–5 pass.
- `ubuntu24.1793186494` is the frozen data of `m0-probe-o10281122`. It must never be deleted.
- `df -BG /home` reads 67 G now and about 101 G expected after the revert plus the leak deletion.

## Asks for the user (the release)
1. **Required:** close Firefox and Zotero before re-issuing, and launch no browser until the run ends. The run takes about 4 h; the wall cap is 5 h 37 min.
2. **Recommended:** start the next Claude Code session with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` in its environment. Only you can set this, and only at session start.
3. **Keep or change the launch route.** Phase-10 step 5 keeps the runner in a Claude Code background shell. Moving it to `systemd-run --user` or `nohup` would need your ruling and a step-5 amendment; I will not do it on my own.
4. **Ratify a pre-launch memory gate.** After the revert, with the VM running: MemAvailable + qemu RSS ≥ 23 GiB, else no launch and PAUSE T3. The gate only adds a check; it changes no test and no budget. The 23 GiB figure is a judgment (about 17 GiB peak plus 6 GiB headroom), not a measurement.
5. **Ratify the release order:**
   1. Run the resume checks.
   2. Run pre-flight items 2–5 at F′ and confirm there are no `p[0-9]-*` or `m0-*-p*` names.
   3. Revert `fresh-install`.
   4. Run leaked-overlay checks 1–5 on `ubuntu24.1793186558` only, then `rm` it and `pool-refresh VMs`, logging the space freed.
   5. Check `df` ≥ 84, else PAUSE T2.
   6. Confirm `r3p-green` is listed, then run pre-flight item 6 and the memory gate.
   7. Commit the projection row.
   8. Run `run-to-m9.sh --harness-sha fb3554a… --run-prefix p --no-snapshots`.

   Read literally, pre-flight item 7 (df ≥ 84) comes before the revert. Today it would read 67 and stop before the step that frees the space.
6. **Confirm** that re-issuing the goal means "M9 attempt 3, prefix p".
7. **Optional:** a ruling on fixing the `finish()` orphan gap now, as F″, instead of after M9.

## Unresolved questions
- Is check 5 of the leaked-overlay rule met when m3's partial in-VM evidence was never archived? kongming: yes. Attempt 1's cancelled m2 was in the same state, and booting the old overlay to fetch it would expose a live Influx token.
- The reaper's details (trigger, idle gate, environment variable) come from third-party issue reports, not official Claude Code docs.

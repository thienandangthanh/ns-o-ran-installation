# M8–M9, P10: PAUSE T1, a leaked VM overlay blocks the second M9 attempt (2026-10-28 19:45 KST)

## What happened

The goal was re-issued at 18:16 KST after Stop B. The pre-flight passed, the VM was reverted to `fresh-install` (host free 98 → 101 GiB), and M9 attempt 1 started at 18:21:48 KST with prefix n at the frozen harness F `e0a6ac5`.

- **Attempt 1 failed on a harness defect** (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T092148Z/`). m0 and m1 were green. During m2, at 09:59:23Z, the heartbeat monitor cancelled the run with "no watchdog heartbeat". The watchdog was alive and host free was 85 GiB.
- **Root cause:** `host-disk-watchdog.sh` wrote its heartbeat by truncate-then-write. The monitor ran on the same 30 s period in the same second, so one read landed in that window and saw an empty file. The file times are 3 ms apart, and kongming reproduced the race off the VM.
- **The one guided fix** (`plans/reports/kongming-261028-1900-GH-1-p10-m9-heartbeat-race-failure-counsel.md`) is F′ = `fb3554a`: the heartbeat is written atomically, and the new self-test case 8 is red at F and green at F′ in 3 of 3 runs (`fix-proof/`). F′ was reviewed (`plans/reports/code-reviewer-261028-1930-GH-1-f-prime-heartbeat-fix-review.md`: no must-fix, S1 and S2 deferred), and its ledger section in `reports/codex-pre-ship-audit.md` ends `Status: complete`.
- **Codex skipped: run cap reached.** I spent the spare 4th run by mistake: I ran `adversarial-review --help`, the companion started a real review of the working tree, and I cancelled it after about 60 s with no result.
- K14 at F′ holds: only the two host files differ from F, so `reference/r3p/` stands.
- The pre-flight for attempt 2 passed. The revert to `fresh-install` at 10:34Z exited 0.

## Why it pauses

After that revert, `df -BG /home` stayed at **85 GiB**. Attempt 1's working overlay, `/home/andang/VMs/ubuntu24.1793179340` (16 GiB, root:root 0600, frozen at 18:59:44), was not unlinked.

- **Orphan proof** (`evidence/p10-disk/20261028T104307Z/`, with kongming's checks 1–5):
  - it is not the active vda (now `ubuntu24.1793183688` on `ubuntu24.04`);
  - no live or inactive domain disk XML references it, and no snapshot does either;
  - it was attempt 1's active vda (`evidence/m0/20261028T092148Z-host/disk-chain-after-branch-delete.txt`);
  - no image created later can depend on it;
  - nothing has had it open since the cancel's shutoff.
- **Mechanism** (kongming, libvirt 12.8.0 source, `qemu_snapshot.c`): a revert unlinks only the overlay that the current snapshot tracks in `revertDisks`. `gate-m0-host.sh`'s branch create and delete clear that record, so the overlay that becomes active after the M0 probe is untracked and leaks on the next revert. The virtqemud journal for the revert window gave no readable lines, so this is not confirmed from logs. **Every later M9 attempt will leak its whole overlay** (about 55 GiB for a full run) on the next revert. `gate-m0-host.sh` is frozen (K14), so this goes in the handoff as a harness defect, not a fix now.
- **Budget:** the projection is X′ − T = 85 − 84 = +1, inside the R term's ±3. The expected minimum is about 30 GiB against the 29 GiB trip, so kongming estimates a 25–40 % chance of a T2 trip around 5 hours in. With the overlay removed, free space would be about 101 GiB and the expected minimum about 46.
- **Why I did not delete it:** the snapshot rule covers snapshots only, and the Stop B counsel says never delete files in `/home/andang/VMs` by hand. The deletions the rule allows can free about 0.03 GiB. T1 is "a deletion outside the snapshot rule would be needed (… space the allowed deletions cannot free)". kongming's counsel is not user approval, so I am not widening my deletion authority on it (`plans/reports/kongming-261028-1945-GH-1-p10-attempt-2-disk-go-no-go.md`: NO-GO at 85, option C).

## State at the pause

- **VM:** running and idle on the `fresh-install` revert; the active disk is `ubuntu24.1793183688`, tracked in `revertDisks`.
- **Snapshots:** fresh-install > f7-rerun-green > r0-green > r2-green > r3p-green, plus `m0-probe-n10280921`, which is the attempt-1 leftover and is kept.
- **Host:** /home has 85 GiB free. No runner, watchdog or monitor process is running.
- **Harness:** F′ `fb3554af67010dfedb6ae500e533acb7cdac9530` is pushed, and the pins equal the fork heads.
- **Docs:** README and docs/ hold uncommitted P10 drafts with placeholders. They wait for the M9 log and are left in the worktree.

## Asks for the user

1. **Delete the leaked overlay** after these read-only checks, each of which returned 0 or clean on 2026-10-28:
   - (a) `virsh -c qemu:///system dumpxml ubuntu24.04 | grep 1793179340` and the same command with `--inactive` both print nothing;
   - (b) optionally, `journalctl -u virtqemud --since "2026-10-28 19:34"` shows libvirt failing to remove a stale image;
   - (c) the `VMs` pool is active, so run `rm /home/andang/VMs/ubuntu24.1793179340` and then `virsh -c qemu:///system pool-refresh VMs`.
2. **Recommended:** give a standing ruling that the agent may unlink an untracked former-active overlay in `/home/andang/VMs`, only after checks 1–5 pass, logging each deletion with the space it freed. Without this ruling, any red M9 attempt needs the same round trip, because its roughly 55 GiB overlay leaks on the next revert.

## Release steps (on re-issue)

1. Resume checks. Expect the VM running on the fresh-install child overlay and the snapshots as above, with `m0-probe-n10280921` as the expected leftover.
2. Pre-flight per phase-10 "Stop B mapping", with F′ and prefix `o`.
3. `scripts/vm/vm-snapshot.sh revert fresh-install` again: idle time and apt timers may have changed the VM, and this revert is clean. Then confirm `ubuntu24.1793183688` is gone and `df -BG /home` reads ≥ 84 (about 100 expected).
4. Add a "P10 restart" projection row, then start `scripts/run-to-m9.sh --harness-sha fb3554af67010dfedb6ae500e533acb7cdac9530 --run-prefix o --no-snapshots` in the background.
5. The one-fix budget resets on re-issue (standing ruling 2026-10-26). Any red Verify then gets one kongming-guided fix; a second red is PAUSE T6.

## Open questions

- Will the user give the standing ruling on leaked overlays, or delete each one personally?
- Should the post-M9 handoff list the `gate-m0-host.sh` revertDisks leak and the deferred S1 (`df -BG` rounds up) and S2 (a cancel during a no-snapshot reboot can leave the VM up) as harness fixes?

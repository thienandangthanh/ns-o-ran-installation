# kongming: P10 attempt 2, disk go/no-go (2026-10-28 19:45 KST)

Runtime: Opus 5.5 (caller's routing), host read-only. Advisory only; never user approval.

## TL;DR
NO-GO at 85 GiB. Choose option C: print `PAUSE T1` now. The user deletes `/home/andang/VMs/ubuntu24.1793179340` and, ideally, gives a standing ruling for future leaked overlays. On release, revert `fresh-install` again (that revert is clean) and run with prefix `o`. Do not delete the file yourself (option B). The file is a provable orphan, but the deletion falls outside the snapshot rule, and the leak will recur after every M9 attempt.

## Q1. Is 1793179340 a provable orphan?
Yes. Verified evidence:
1. **Not the active disk.** `domblklist` shows vda = `ubuntu24.1793183688`.
2. **No snapshot references it.** Across all 6 `snapshot-dumpxml` outputs (disks, revertDisks and domain sections), the only source files are 1792618108 (missing), 1793183688, ubuntu24.04, the m0-probe qcow2 (missing), 1793179273, r0-green, 1792653312, 1792618143, r3p-green qcow2 (missing) and r2-green.
3. **Nothing can use it as a backing file.** Only files created after its birth (09:22:20Z) could, and those are 1793183688 (made by a revert onto the fresh-install domain disk, i.e. `ubuntu24.04`) and the m0-branch overlay, which libvirt committed and deleted. `m0-probe-n10280921` backs onto 1793179273 (09:21:13Z), which is older than 1793179340.
4. **Identity is proven.** `evidence/m0/20261028T092148Z-host/disk-chain-after-branch-delete.txt` shows 1793179340 as attempt 1's active vda, sitting directly on `ubuntu24.04`.
5. **Nothing has it open.** Its mtime has been frozen at 18:59:44, when the monitor shut the VM off. The root:root owner is libvirt's DAC owner restore at stop; an open image stays libvirt-qemu.
6. **No evidence value.** Attempt 1 failed for a host-side reason, and its evidence is archived on the host.

Checks still worth running (read-only) before anyone deletes:
- (a) `virsh -c qemu:///system dumpxml ubuntu24.04` and `dumpxml --inactive` contain no `1793179340`, and vda's backingStore is `ubuntu24.04`.
- (b) `journalctl -u virtqemud --since "2026-10-28 19:34"` shows `Failed to remove snapshot image '/home/andang/VMs/ubuntu24.1792618108'`. This confirms the mechanism in Q3.
- (c) `virsh pool-list --all`. If `/home/andang/VMs` is a pool, `pool-refresh` it after the delete.

## Q2. Which option
**Contract fit.**
- The snapshot rule (`plan.md:71`, goal-packet constraints) covers only *snapshots*. This is a raw file, and my Stop B counsel said "never delete files in /home/andang/VMs by hand".
- The allowed deletions can free about 0.03 GiB at most. `m0-probe-n10280921` pins only 1793179273 at 31 MB, and its own overlay file is already missing, so libvirt may refuse the delete. `r0-green` and `r2-green` are non-leaf snapshots.
- This is exactly T1 (`plan.md:105`): "space the allowed deletions cannot free".
- T2 does not apply, because no snapshot create or watchdog trip has occurred.
- B would expand the user's deletion authority on kongming's word, which is not allowed.

**Expected value.**
- **Option A.** At 85, the expected minimum is 85 − 43 − 12 = 30 GiB against a trip below 29. The R term carries ±3 of estimate error. The 5 GiB of `--no-snapshots` slack is unproven: attempt 1's m0–m2 used 16 GiB, against about 15 in the Oct-21 chain (78→64 plus m0). That leaves roughly a 25–40% chance of a T2 trip in r2/r3p, about 5 h in. A trip, or any other red, then needs a revert, which leaks attempt 2's ~55 GiB overlay (Q3). The user must act on orphans anyway.
- **Option C.** Costs one user round-trip. At about 101 GiB the expected minimum is about 46, so the trip risk is near 0, and the ruling covers attempt 3 and post-M9 cleanup.
- C dominates unless the user is unreachable for longer than one run (about 5 h).

**Disagreement note.** A is rule-compliant: the pre-registered gate passes, 85 ≥ 84. If the caller picks A, record "+1 GiB margin inside the ±3 R error, known leak recurs" as an accepted trade-off. It is not a violation.

## Q3. Why the revert did not delete it, and whether attempt 2 will leak
Cause (verified in libvirt 12.8.0 `src/qemu/qemu_snapshot.c` against the host's libvirt 12.8.0): the cause is libvirt metadata, not "VM shut off vs running".
1. **Normal revert.** `qemuSnapshotRevertExternalFinish` (~l.2617–2672) unlinks the *current* snapshot's `revertDisks`. If there are none, it unlinks that snapshot's `disks`.
   - At 18:21 the current snapshot was `r3p-green`, so its `disks` entry (`ubuntu24.04-r3p-green.qcow2`) was deleted. That deletion was correct.
2. **What gate-m0-host does to the tracking** (`scripts/gates/gate-m0-host.sh:40-52`):
   - The probe revert recorded 1793179340 as fresh-install's `revertDisks`.
   - `branch_create` then ran `qemuSnapshotClearRevertdisks(current)` (~l.2194) and erased that record.
   - `branch_delete` committed the branch back into 1793179340. `qemuSnapshotDeleteUpdateParent` (~l.3886) restores nothing when the parent has no revertDisks.
   - Result: the active overlay is untracked.
3. **The 19:34 revert** found fresh-install with no revertDisks and unlinked its stale `disks` entry, 1792618108, which was already gone. It warned, and 1793179340 leaked.

Consequences:
- **Attempt 2's own run:** unaffected.
- **Re-revert on release:** clean. Fresh-install now tracks 1793183688 in revertDisks, so that file is unlinked properly. Verify with `ls` afterwards.
- **Recurrence:** every M9 attempt (gate-m0-host, then a later revert) leaks its whole working overlay on the next revert. That is about 55 GiB after a full or late-failing run.
- **Pinned overlay:** the probe `m0-probe-o…` will pin whatever overlay is active at that moment, which is tiny right after the re-revert.
- **Fix:** gate-m0-host is frozen (F/F′, K14), so do not change the harness now. Record the defect for the handoff and the realism pass.

## What to do (ordered)
1. **Don't run the M9 runner.** Don't delete any file or snapshot, and leave the VM running idle on fresh-install. No shutdown is needed: the re-revert on release discards any idle drift, such as apt timers.
2. **Write the evidence directory** `evidence/p10-disk/<ts>/` with:
   - `ls -la --time-style=full-iso /home/andang/VMs`, `df -BG /home`, `domblklist`;
   - the `dumpxml` disk section with its backingStore chain;
   - `snapshot-list --parent` and a grep of every snapshot's source files;
   - the libvirt version, plus check (b) if it is readable;
   - pointers to `m0/20261028T092148Z-host/disk-chain-after-branch-delete.txt` and to this report.
3. **Record a `m9-budget.md` row:** "P10 attempt-2 start: X′ = 85, projection +1, NO-GO: 16 GiB leaked overlay, T1".
4. **Write the journal** `docs/journals/2026-10-28-m8-m9-p10-pause-t1-leaked-overlay.md` covering:
   - the facts: df 85 vs about 101 projected; the file's size, owner and mtime;
   - the orphan proof (Q1, items 1–6);
   - the libvirt mechanism (Q3, with line refs);
   - why there is no self-delete: the snapshot rule, Stop B counsel, and T1 text;
   - the A-vs-C risk numbers;
   - the VM state: running, current fresh-install, active 1793183688 tracked, snapshots unchanged, m0-probe-n10280921 kept;
   - the user asks:
     - (i) `rm /home/andang/VMs/ubuntu24.1793179340`, after checks (a)–(c), plus `pool-refresh` if it is a pool;
     - (ii) recommended: a standing ruling that the agent may unlink an *untracked former-active overlay* in `/home/andang/VMs` only after checks 1–5 pass, logging each delete with the space freed;
   - the release steps.
5. **Before printing PAUSE:** update the resume card and `implementation-notes.html`, then push. The repo is public, so keep only paths and sizes; there are no secrets here. Then print `PAUSE T1 evidence=<dir> journal=<path>`.
6. **On release:**
   - pre-flight (unchanged);
   - `vm-snapshot.sh revert fresh-install`, then confirm 1793183688 is gone and `df -BG /home` ≥ 84 (about 100 expected);
   - commit a projection row;
   - `run-to-m9.sh --harness-sha <F′> --run-prefix o --no-snapshots`.

## What to avoid
- **Raw `rm` by the agent.** Nor `virsh vol-delete`, which is the same act through libvirt.
- **Snapshot surgery:** `snapshot-create --redefine` to re-attach revertDisks, or a throwaway create/revert/delete dance to make libvirt delete the file.
- **Deleting `m0-probe-n10280921` "to free space":** it frees nothing, and libvirt may refuse because its overlay file is missing, which would be a second T1.
- **Retuning h or the trip point now:** the budget is frozen. Proceeding at 85 while calling it ample.

## Assumptions
- High confidence: the host's libvirt behaves as the v12.8.0 source. Check (b) confirms or refutes this.
- Medium confidence: the user can respond within a few hours. If not, A's success chance is about 60–75% and is rule-compliant.
- Medium confidence: the R-term ±3 and the measured m0–m2 consumption carry over to the rest of the run.

## Unresolved questions
- Does the user grant the standing leaked-overlay ruling, or delete each one personally?
- Should the handoff list the gate-m0-host revertDisks leak as a post-M9 harness fix, for example by reverting from the branch before deleting it, or by deleting the probe overlay chain at the end?

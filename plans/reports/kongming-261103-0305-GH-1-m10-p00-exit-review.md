# kongming: M10 P00 phase-exit review (ops prelude, AC1–AC5)

Date: 2026-11-03 03:05 KST. Mode: `--advice` phase-exit counsel, read-only. Runtime: Opus 5.5 (`model: opus`, per the user's CLAUDE.md override of the `fable` routing). Counsel is not user approval.

## TL;DR

**Verdict: GO-WITH-CHANGES.** All five ACs hold as written for P00's share, and I independently verified the load-bearing parts. Both new self-tests fail against the pre-P00 code (mutation-checked), the libvirt mechanism matches libvirt's source and the live snapshot XML, and the 42.4 GiB deletion was within the 2026-10-28 ruling. One real gap remains. The new m0 check `no_untracked_overlays` cannot see the FU2 failure mode until after the next revert. If the leak comes back (a libvirt upgrade on this rolling Arch host, or a create-then-delete snapshot pattern in a dev phase), the first signal is the P13 post-run AC2 check, which runs after the 6-hour M10 run. Add a cheap "pending leak" predicate (required change 1). The other changes are records fixes and P01 discipline. None blocks P01's VM work, which has already started (`da17fd7`).

## Reframed problem

P00 hardens the harness that every later phase and the M10 end run use. The question is not "did the five items land" (they did) but "can any of them make the M10 end run fail or lie": a false green, a false red, or a disk failure discovered only after the run. Non-goals: the FU4 root cause, and changing the F″ remedy.

## Q1. Does each AC hold as written?

**AC1 (FU1): holds.**
- `finish()` (`scripts/run-to-m9.sh:121-131`) now calls `vm_stop_gates` whenever `step_ran=1` (set at `:146` inside `supervised`), with no `kill -0` guard. The trap text (`:132`) now names the disk watchdog trip, the heartbeat monitor cancel and the operator, which covers the reaper and systemd stop senders.
- Self-test case 7b (`scripts/vm/m9-runner-selftest.sh:114-126`) passes on HEAD. I ran the new self-test against the `8017436` runner in a scratch copy, and 7b fails there ("gate unit alive yes"). So the test discriminates.
- Minor: 7b sets `step_ran=1; step_pid=<reaped pid>` directly. The more common real path is "supervised returned non-zero, so `step_pid=""`, then `finish 1`". The new code covers that path through `step_ran`, but no test exercises it. Optional case 7c: `step_pid=""`, `step_ran=1`, and a stand-in unit that must be stopped.
- Behaviour change worth knowing: `finish 0` (success) now also calls `vm_stop_gates`, bounded at `CANCEL_TIMEOUT_S`=30 s + 2 s (`scripts/vm/vm-common.sh:31-33`). It is harmless. The monitors stay alive during it, so the verdict's `end - lastCheckEpoch ≤ 2×interval` rule (`scripts/m9-verdict.py:79`) is unaffected. A TERM that arrives inside that ≤ 32 s window re-enters `finish 3` and exits 3 with a verdict. That outcome is correct if a monitor really fired.

**AC2 (FU2): holds for P00's share. "After the end run" is P13's job and is planned (`phase-13-…:11,26,33`).**
- Dev evidence is complete:
  - M0 probe `d11021754` with the new order: every check passes, including `no_untracked_overlays` (`evidence/m0/20261102T175435Z-host/gate.log`).
  - A second revert then unlinked the post-probe overlay `…1793642118` ("previous active still present: no", `evidence/fu2/20261102T174920Z/checks/second-revert-after.out`).
  - The orphan check after that revert listed 0 files (02:55:48).
- I verified the mechanism against libvirt's `src/qemu/qemu_snapshot.c`:
  - `qemuSnapshotCreate` calls `qemuSnapshotClearRevertdisks(current)`, which frees the record without an unlink.
  - `qemuSnapshotRevertExternalFinish` unlinks the current snapshot's `revertdisks`, or its `disks` when it has none, and records the new overlay in the target's `revertdisks` when the target has children.
  - Deleting a current leaf snapshot commits it into its backing file. `qemuSnapshotDeleteUpdateParent` restores no record.
- Live check: `virsh snapshot-dumpxml ubuntu24.04 fresh-install` shows `<revertDisks>` naming the active `/home/andang/VMs/ubuntu24.1793642139`.
- So the ordering fix is sound. Revert-last (`scripts/gates/gate-m0-host.sh:44-58`) leaves the run's overlay recorded on `fresh-install`.
- **Weaker than it looks:** the new check runs `scripts/vm/vm-orphan-overlays.sh`, which counts any file named by the domain XML as tracked (`:21-25`). The active overlay is always named there, so an active but *unrecorded* overlay (the exact FU2 state) passes. Under the old order the gate would also have passed this check. The check only finds leaks that have already happened.

**AC3 (FU3): holds literally.**
- `rtmgr_push_acked` has no caller left except inside `rc_rmr_ready_after_rtmgr` (`scripts/gates/rc-lib.sh:126-128`), where it is ANDed with `rt_reader_ok rc … ricxapp`.
- Both enumerated callers source `bringup.sh` before `rc-lib.sh` (`gate-i2-ts-xapp-install.sh:14,17`; `gate-r2-…:23,27`; `gate-r3p-…:23,27`), so `rt_reader_ok` resolves.
- The fixture self-test passes on HEAD. With the `8017436` `rc-lib.sh` it fails ("stuck reader: exit 0"), so it discriminates.
- The e2mgr/submgr path is behaviour-identical: `ric_pod` now delegates to `ns_pod ricplt` with the same `ricplt-<comp>-` match (`bringup.sh:204-205`). The F″ remedy is therefore unchanged, as AC5 requires.
- Spirit gap, outside the literal text: TS xApp, stub and a1mediator readiness still rests on `rtmgr_sessions` (`ts-lib.sh:264`; `gate-i2-…:67-68`). That is a sender-side ESTABLISHED check, the same blind spot class that the M9 m6 incident showed. Today those failures surface as a red rung, not a false green, so this is not a P00 blocker.
- Not yet proven in a live gate flow: P00 proved the rc predicate on fixtures plus one cold-boot sample (`evidence/fu3-fu4/…/rt-readers-coldboot-live.txt`). It has never run inside i2 or `rung_live` after an rtmgr restart.

**AC4 (FU5): holds for the M9 share. Rehearsals are planned in P11 (`phase-11-…:18,40,47`).**
- `scripts/disk-burst-h.py` gives worst 12.0 GiB, with per-attempt values 8/9/11/12, matching the earlier kongming figures. It exits 2 above `--limit 12` (`:82`).
- Window semantics: the script takes sample pairs at most 370 s apart (`:33-42`). The 370 s stop path runs from the last above-trip sample to VM stop, so a continuous reading would also count up to one polling interval of tail growth. I re-ran the script with `--window 400` and `430`, and the worst is still 12.0. The 370 s semantics are not hiding a bigger burst in the M9 data.
- Residual: `free-series.tsv` holds integer GiB from `df -BG`, so a recorded drop of 12 is a true drop of about 11–13 GiB. R11 ruled h = 12 on this same data, so there is no new decision, but record the caveat with the AC4 evidence.

**AC5 (FU4): holds.**
- `plans/reports/findings-261103-0247-GH-1-fu4-stuck-rmr-route-readers.md` has the symptom, three hypotheses marked unverified, and one cold-boot reproduction attempt with evidence (not reproduced). It also notes the unrouted TS xApp and stubqp after a cold boot.

## Q2. Regression risk for the M10 runner and the m0–r3p gates

- **`rt_reader_ok rc` cost.** One exec for the wait loop, plus 5 sample execs with 4 × 2 s sleeps, comes to about 10–12 s per call. It runs once in i2 and once per `rung_live` label. Against r2 (timeout 1518 s, measured 612) and r3p (2529 / 1286) this is negligible. P12's budget comes from the P11 rehearsals, so it will include the cost automatically.
- **No digest effect.** AC8 compares `ledger/ipc/traces/extra` digests (`scripts/gates/reference-compare.py:3-12`; `digest-run.py:48`), not check output. The paced run starts after readiness, so the extra wall time does not touch sim-time content.
- **New false-red path.** If rc's reader is stuck, i2 or the rung now goes red early with a precise message, and no bounded remedy exists for rc (F″ refreshes only e2mgr and submgr). Before P00, a stuck rc reader would most likely have reddened later anyway, because a fresh rc pod with no table cannot route 12040. Probability is low, and a live smoke in P01 retires most of it.
- **m0 `no_untracked_overlays` on a pre-existing orphan.** It fails closed and stops M10 at m0. That is cheap and arguably right, but the P13 release order must run the orphan check explicitly before launch, not only as "leaked-overlay handling".
- **Foreign images.** Domains `ubuntu20.04` and `ubuntu20.04-nist` (shut off) point their `vda` into `/home/andang/VMs` (`ubuntu20.1780671766`, `ubuntu20.1792170827`). Those files are absent today. If the user ever restores them, `vm-orphan-overlays.sh` only reads `VM_DOMAIN`'s XML, flags them as untracked, and m0 goes red. Worse, the printed list looks like a deletion list. The ruling's name scope (`ubuntu24.*`) prevents deletion, but the false red stays.
- **libvirt assumption.** Verified for libvirt master and live on 12.8.0 (recorded in `host-facts.txt`). The host is a rolling Arch install, so a `pacman -Syu` mid-goal could change revert semantics. Only the post-run AC2 check would notice today. Required change 1 moves detection to every m0.
- **Probe snapshots accumulate.** Each M0 run leaves one `m0-probe-*` snapshot whose frozen data is the pre-probe overlay (about 27–32 MB). This is negligible on disk, but do not delete these snapshots during M10: their own overlay files are already unlinked, and libvirt's non-current external delete path unlinks parent overlays.

## Q3. Was the leaked-overlay deletion within the ruling?

**Yes, in substance.**
- The file `ubuntu24.1793206761` was the M9 attempt-4 active overlay (epoch 2026-10-28 16:59Z). It falls in the ruling's file class (`decisions-261028-2014…:9`).
- Checks 1–5, ls/df before and after, the command and the space freed (42.4 GiB) are all logged (`evidence/fu2/20261102T174920Z/leak-deletion/checks/`). It was deleted before the fix, as phase step 4 requires.
- Check 5 says "not written since the run that used it stopped". Two writes came after M9:
  - the Oct 31 shutdown flush;
  - the Nov 3 02:42–02:50 FU3/FU4 cold boot on that overlay, ending in the 02:50:51 revert (mtime 02:50:50).
- Both writers are named and stopped, and qemu held a different file, so the check passes in substance.
- Record deviations to fix:
  - (a) The ruling asks for the log under `plans/261023-0009-…/evidence/p10-disk/<ts>/` and a line in `m9-budget.md` (as at `m9-budget.md:131`). Neither was done. The M10 location is reasonable, but say so.
  - (b) The resume card cites `evidence/fu2/20261102T174921Z/leak-deletion/`; the directory is `…174920Z`.
  - (c) `plan.md:118` still describes the 42 GiB as reachable; it is now realised (96 GiB).

## Q4. What P01 must do differently

1. **Snapshot discipline.** Only the M0 probe was fixed; the FU2 trigger itself is general. Creating any snapshot while a revert overlay is current, and then deleting that snapshot while it is current, leaves the overlay active but unrecorded, and the next revert leaks it.
   - Use existing snapshots (`f7-rerun-green`) as P01 start and return points.
   - Create no temporary snapshots.
   - Run dev chains through `run-to-m9.sh … --no-snapshots`.
   - After every revert (the AC6a mandatory revert and phase exit), run `vm-orphan-overlays.sh` and record it.
   - Today's state is clean: `fresh-install` is current with `revertDisks` = `…1793642139`, so the revert to `f7-rerun-green` unlinks it, and `f7-rerun-green` has children, so its new overlay is recorded.
2. **Live-smoke the new rc readiness** before P02's AC8 run 1 depends on it.
   - In P01's live RIC, run `rc_restart_rtmgr`, then `rc_rmr_ready_after_rtmgr`, and keep `rt-readers-rc-*.txt`.
3. **AC6 panic fixture.** The ACK without ControlOutcome is meant to crash rc. After the container restart, check readiness with the new predicate (restart rtmgr if needed) before the 2 s timer fixture. Otherwise the second fixture may run against an rc with no routes, and RestartCount and timer evidence get mixed.
4. **AC18 ledger.** Add a row if P01 touches any m0–r3p predicate. The probes are additive and need no row.

## Required changes (numbered)

1. **Pending-leak predicate** (required; land before the next `gate-m0-host.sh` run, and no later than the P11 rehearsals).
   - Add a mode to `scripts/vm/vm-orphan-overlays.sh` (for example `--pending`) that passes only when the active `vda` source is in the current snapshot's top-level `<revertDisks>`, or, when that element is absent, in its top-level `<disks>`. This mirrors `qemuSnapshotRevertExternalFinish`.
   - Parse with an XML parser so the nested `<domain>` disks are not matched.
   - Add it as an m0-host check right after `no_untracked_overlays`. Run it again in the P13 release order before launch and before the post-run revert.
   - Add AC18 ledger row 3 (an added check, not weaker).
2. **Foreign-domain safety** (required before Stop B). In `vm-orphan-overlays.sh`, read the XML and snapshots of every defined domain (`virsh list --all --name`), or report files outside the `ubuntu24.*` scope separately as "foreign, never a deletion candidate".
3. **Records** (now).
   - Fix the resume-card path typo (`174921Z` → `174920Z`).
   - Add the ruling's budget line for the 42.4 GiB deletion (in `m9-budget.md`, or with an explicit note in the M10 budget sketch), and state the log-location deviation.
   - Update `plan.md:118`.
   - In ledger row 2, say that `no_untracked_overlays` detects completed leaks only.
   - Add the AC4 caveats (sensitivity at 400 s is still 12; integer-GiB quantization) next to `evidence/fu5/…/disk-burst-h.out`.
4. **P01 live smoke** of `rc_rmr_ready_after_rtmgr`, plus the post-panic readiness re-check (Q4 items 2–3).
5. **P01 onward snapshot discipline and an orphan check after every revert and at every phase exit** (Q4 item 1). The P13 release order should name `vm-orphan-overlays.sh` (and change 1) explicitly.

Optional:
- Self-test case 7c (empty `step_pid`).
- P11 rehearsals must run under `host-disk-watchdog.sh`, or AC4 has no `free-series.tsv` to read.
- In P06/P07 (owners of `ts-lib.sh`), extend receiver-side readiness to `trafficxapp` and the stub. Note that the wait loop's `|| true` (`bringup.sh:236`) cannot tell "exec failed" from "no session".
- Hold the libvirt version on the host for the M10 window (pacman `IgnorePkg`), or compare `virsh --version` with 12.8.0 in m0.

## What to avoid

- Do not read `vm-orphan-overlays.sh` output as a deletion list. Only the ruling's five checks and its `ubuntu24.*` scope authorise deletion.
- Do not delete `m0-probe-*` snapshots, and do not delete a snapshot while it is current, in any M10 phase without a dry analysis and both orphan checks afterwards.
- Do not treat fixture-green as live-green for the rc predicate.
- Do not raise h, or reinterpret 12.0 as "below" 12, if a P11 rehearsal shows 13. That is PAUSE T3.

## Assumptions

- libvirt on the host stays at 12.8.0 semantics for the goal's lifetime (medium; Arch is rolling). Required change 1 would detect a change.
- The M10 end run uses `--no-snapshots` (high; `phase-13-…:6`). With snapshots, boundary snapshots pin the overlays instead, which is not a leak but changes the disk accounting.
- rc's image keeps a `cat` binary and its rtmgr session on :4561 stays persistent (high; measured 2026-11-03).
- The contract's "runs in dev" is satisfied by the m0-embedded check plus the standalone script (medium). A stricter reading would want the check after every dev revert, which Q4 item 1 provides.

## Verification I ran

- `rt-reader-selftest.sh`, `disk-burst-h.py --self-test`, `m9-runner-selftest.sh` (all ok) and `lint.sh` (ok, 46 s) on HEAD.
- Mutation runs against `8017436` in a scratch copy: 7b fails, and the stuck fixture fails.
- `disk-burst-h.py --window 400/430`: still 12.0.
- Read-only `virsh` showing `fresh-install`'s `<revertDisks>`, the pool paths, and the foreign domains' `vda` paths.

## Unresolved questions

1. Should the m0 orphan check fail M10 on a pre-existing orphan (fail-closed, current behaviour), or should the P13 release order guarantee zero before launch so the m0 check is only a backstop? I recommend both. That is the user's call if it changes the step set.
2. Are restored `ubuntu20.*` images ever expected back in `/home/andang/VMs`? If not, required change 2 can become a scope filter.

## Sources

- [libvirt `src/qemu/qemu_snapshot.c` (master)](https://gitlab.com/libvirt/libvirt/-/raw/master/src/qemu/qemu_snapshot.c)
- [qemu_snapshot: introduce external snapshot revert support (patch)](https://patchew.org/Libvirt/cover.1678718987.git.phrdina@redhat.com/d71c22c561b75d29dd0852392d6115f2bfa528ed.1678718987.git.phrdina@redhat.com)

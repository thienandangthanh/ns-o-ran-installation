# Kongming note: P9 chain red #1 at M2 (2026-11-07 23:10 KST)

This note ran on Opus 5.5, per the user's routing. It is advice only. I had no access to the VM, and on the host I ran read-only commands.

## TL;DR

The diagnosis holds, and the cause does not depend on P9. The gate's own evidence proves it more directly than the VM reads taken after the gate. The one guided fix is: wait until the host is measurably quiet, revert to `f7-rerun-green`, and re-run the P9 chain from step 0 with a fresh log directory. No harness change and no ledger row are needed. After that, any red step means PAUSE T6. The workload from the other workspace had already ended by 14:10Z, so the user does not need to decide anything now.

## 1. Diagnosis check

### Verified evidence

**The red does not depend on P9 (high confidence).**
- The last green M2 ran at a7943bfb (`evidence/m2/20261106T130927Z`). Between a7943bfb and e86f1d08, `git diff -- scripts/gates/gate-m2-refnode.sh scripts/gates/bringup.sh scripts/vm/` is empty.
- Both runs expect the same e2mgr image, `6.0.6-nist180-85dfecb925f9` built from source 09036c6f (see each run's `e2mgr-image.txt`).
- Both runs show the same kpm_sim patch digest, 235b579b.
- ns-3 and oran-interface are not on M2's path.

**The slowdown started before any Kubernetes symptom.**

| Step | 2026-11-06 (green) | 2026-11-07 (red) |
|---|---|---|
| kpm_sim rebuild | 2m02s | 9m04s (13:15:50–13:24:54) |
| e2mgr | 6m11s for the whole step: build, helm, rollout, refresh, judge | 12m41s for build and import alone, up to the helm upgrade (13:24:54–13:37:35) |

Both steps are plain compute and disk IO inside the VM. A slowdown of this size points to contention on the host.

**The control plane was already failing during the rollout wait.** The gate's own snapshot `bringup-pods-wide-134302.txt` (13:43:02Z) shows:
- kube-controller-manager and kube-scheduler in CrashLoopBackOff, 22 restarts each, the last one 76 s earlier;
- kube-apiserver at 9 restarts, the last one around 13:29Z.

The baseline on 2026-11-06 at 13:18:32 was 15 / 15 / 7, all of them from the boot.

The message `Waiting for deployment spec update to be observed` means the Deployment's observedGeneration stayed below its generation. In other words, the deployment controller inside kube-controller-manager never processed the helm change within 300 s. It was not an image problem or a readiness problem.

**The NOT-CONNECTED sample at 13:48:35 was a failed read, not a dropped E2 link.**
- `e2_node_connected` reads e2mgr through the API-server service proxy (`scripts/gates/bringup.sh:140-155`). An empty or failed read counts as NOT-CONNECTED. kube-apiserver was killed 19 s later.
- The golden pcap shows a single association: 1 INIT and one vtag pair, 0 ABORT, one E2SetupRequest and one E2SetupResponse. HEARTBEAT and HEARTBEAT-ACK arrive every ~31 s, including 13:48:12/18 and 13:48:43/49.
- kpm_sim never resends its E2SetupRequest. A real disconnect therefore could not have shown CONNECTED again at 13:49:05.
- The samples came 30–66 s apart, and only 8 were taken. Green runs take 10 samples exactly 30 s apart, so the sampler itself was slowed.

**Host state at 14:10Z (read-only):**
- IO pressure (`/proc/pressure/io`, full): avg10 0.02, avg60 8.6, avg300 43, falling.
- Load average 5.9.
- No `dfm_firmware`, `cargo` or `rustc` process is running, so the other workspace's workload has ended.
- Leftover risk: 1.59 GB of the VM's memory is in host swap (qemu `VmSwap`). zram swap is 3.9 of 4 GiB full. The disk swap partition (nvme0n1p2) is on the same NVMe drive as /home (nvme0n1p4), which holds the VM overlay. Memory pressure on the host therefore became IO on the VM's own disk.
- The qcow2 disk has no `cache=` setting, so it uses the host's writeback cache. etcd's fsync calls become host cache flushes.

### Corrections, none of which contradict the diagnosis

- **`e2mgr-image.txt` was written before the deploy.** In `e2mgr_image_patched`, `rollout status ... || return 1` returned before the second judge ran. "Stock 6.0.6 at check time" and "docker image: ID none" describe the state before the build. The build succeeded: `install-e2mgr.log:8299` has the `E2MGR_IMAGE` line, and the helm step only runs when that line is present.
- **The VM was left in a route-hazard state.** The same early return skipped `ric_refresh_routes`. The late rollout around 13:55Z replaced e2mgr with no RMR route refresh and no e2term restart. Both are known route hazards in this project.
- **Some readings are yours, not mine.** I could not verify the in-VM etcd, apiserver and controller-manager log readings. The gate's pod snapshot shows the control-plane failure without them.

**Refined cause:** the other workspace's build caused IO and memory contention on the host, made worse by swap and the VM overlay sharing one NVMe drive. etcd slowed down, the control plane restarted, the rollout was late, and one sample read failed.

## 2. The guided fix: option (b)

**Why not (a), re-running on the current VM.** The M2 predicate itself would not be weaker: the judge accepts an e2mgr that is already patched, by design (precedent `20261104T133408Z`). The problem is that the VM is no longer in the step's start state:
- e2mgr was replaced without a route refresh. A re-run of M2 passes the judge, skips the deploy branch, and so never runs the refresh.
- The control plane restarted more than seven times.
- 1.6 GB of the VM's memory is in host swap.

Spending the last guided fix on this state invites a second red from a known L-release route hazard, which would be PAUSE T6.

**Why not (c), a manual route refresh or restart on the current VM.** That is an improvised VM action. The Failure Protocol does not allow it.

**Steps:**

1. Record the red (§3) and archive the raw red evidence.
2. Check the host entry condition. All checks are read-only. Write the values to `entry-condition.txt` in the new chain log directory.
   - H1: in `/proc/pressure/io`, full avg60 ≤ 5 and avg300 ≤ 10, in two readings at least 5 min apart.
   - H2: in `/proc/pressure/memory`, full avg60 ≤ 1, and MemAvailable ≥ 12 GiB.
   - H3: `pgrep -fa 'dfm_firmware|cargo|rustc'` returns nothing. Observe only; never stop or renice those processes.
   - H4: /home has at least 34 GiB free. About 45 GiB is expected after the revert.
3. Revert to `f7-rerun-green`. Run the orphan-overlay checks, because of the revertDisks leak trap. Delete a leaked former-active overlay only under the 2026-10-28 ruling, with its five checks logged.
4. Check the VM entry condition (read-only):
   - V1: the etcd log for the last 5 min has no "took too long" line at 500 ms or more, and at most 2 such lines in total.
   - V2: over the same 5 min, the restart counts of kube-apiserver, kube-controller-manager, kube-scheduler and etcd do not change, and none of them is in CrashLoopBackOff.
5. Cap: if H1–H3 are not met within 60 min, or V1–V2 within 30 min of the revert, stop with PAUSE-host-contention. The user then decides about the other workload or where the VM runs.
6. Start a host logger as a `systemd-run --user` transient unit, writing into the chain log directory every 60 s. It records `/proc/pressure/{io,memory}`, the load average and qemu `VmSwap`. Stop it when the chain ends. It is evidence only, not a gate.
7. Run `p10-gate-chain.sh e86f1d08… 0 7` with a fresh `P10_CHAIN_LOG_DIR`, for example `e86f1d08-p9-r2/steps-0-7`. Then run step 14, then step 10, each with its own fresh directory. Use the same frozen checkout and the same pins.
8. The outcome rule is set before the run:
   - Green: the P9 gates are done.
   - Any red: a kongming note, then PAUSE T6, whatever the PSI log shows. The PSI log only helps explain the cause.
   - The user's M7 exemption for the no-route signature (`decisions-261107-0045`, item 2) still applies.

## 3. Ledger, harness and records

- **No ledger row.** No predicate, check or threshold changes. The precedent is the guided step of D-R3-1 attempt 2.
- **No harness change now.** Both checks were right to fail: the patched image was not deployed within its bound, and CONNECTED could not be confirmed. Changing the frozen e86f1d08 in the middle of the chain would also need a pin bump and a review.
- **Phase file.** Add a block "P9 chain red #1: M2 (host contention)" under the P9 gates, holding the evidence paths, the timeline, the independence proof, this fix, the entry-condition values and the outcome rule. Update the resume card.
- **Follow-ups for Stop B.** None of these blocks this fix; record them only.
  1. The hold sampler counts a failed read through the API-server proxy as NOT-CONNECTED (`bringup.sh:140-155`). It should record read failures separately, or read e2mgr through its Service instead. If adopted, this needs its own ledger row.
  2. Add a host-pressure entry guard to the chain driver, next to the 34 GiB guard.
  3. On a rollout timeout, `e2mgr_image_patched` returns before `ric_refresh_routes` and leaves the VM in a route-hazard state. Make "revert after an M2 red" the rule.
  4. `_bringup_ric` checks only the ricplt pods. At 13:43:13 it reported all pods Ready while kube-controller-manager and kube-scheduler were in CrashLoopBackOff.
  5. Host placement is the user's call: swap and the VM overlay share one NVMe drive, and a 16 GiB VM runs on a 31 GiB host shared with other workspaces.

## Assumptions

- **A1 (medium-high):** the P9 chain has its own Failure Protocol fix, and P7's red #1 did not use it up. The resume card calls this "P9 chain red #1". If the user reads the budget as one per P10 phase, this red is already PAUSE T6.
- **A2 (medium):** the H1, H2 and V1 thresholds are not calibrated against green runs, because no PSI record exists for them. They sit far below the red run (io full 63–66%) and above idle noise. If H1 cannot be met with the VM idle, the VM itself is the load, and that means PAUSE.
- **A3 (high):** the revert behaves as it did at 13:07Z, with /home at about 45 GiB at the start.
- **A4 (medium):** the other workspace's workload stays off for the 3–4 h of the chain. If it restarts during the chain, a second red is likely, and that is PAUSE T6. Only the user can prevent it.

Verdict: GO-revert-f7-rerun-green-and-rerun-P9-chain-from-step-0-under-host-entry-condition

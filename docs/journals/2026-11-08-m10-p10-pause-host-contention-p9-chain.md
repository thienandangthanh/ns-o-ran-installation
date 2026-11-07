# M10 P10: PAUSE for host contention before the P9 chain re-run

- **Date:** 2026-11-08 00:50 KST (2026-11-07 15:50Z)
- **Phase:** P10, the P9 commits (counter Option A, with the forwarded RLC UM tail fix of ruling a-narrow)
- **Trigger:** the cap that kongming-261107-2310 set before the guided re-run: VM entry conditions not met within 30 min of the revert, which means a PAUSE (host contention). This is not PAUSE T6: no chain step ran after red #1, and the guided fix is not spent.

## Where things stand

- **Committed and pushed:** ledger row 165 (6e7df49f); ns-3 `1f1fa3d3` (tail fix; Codex approve, no findings) and `e32a0e05` (P9); oran-interface `0d6bdea`; Testbed `03180a5` (X2DL registry entry holds, lint 0 findings); harness `32232b8d` (P9 + pins), docs `e86f1d08` up to `eec165e0`.
- **P9 chain red #1 (M2, 2026-11-07 13:59Z):** host IO starvation during a concurrent Rust build in another workspace. etcd stalled, the control plane restarted, and the patched e2mgr rolled out only after the gate. Not P9. Recorded in phase-10 "P9 chain red #1".
- **Guided fix in progress:** the host entry condition held 15:08:59–15:13:59Z (io avg60 0, avg300 3.2, no build processes). Revert to `f7-rerun-green` at 15:14:48Z; orphan-overlay check clean; /home 45 GiB.
- **VM entry check failed** (`evidence/p10-chain/e86f1d08-p9/vm-entry-check.txt`). The first 5-min window passed on restart stability but had 7 slow etcd lines (limit 2), 1 of them ≥ 500 ms. In every later window, 140–666 etcd "took too long" lines appeared, with up to 430 ≥ 500 ms. Controller-manager and scheduler restarted 15 → 22 times and kube-apiserver 7 → 9. The cap was reached at 15:47:20Z.
- **Host at the cap:** `/proc/pressure/io` full avg300 ≈ 46 %, **with no build process running**; swap 9 GiB used; load 11 (15 min). The remaining IO load appears to be the freshly reverted VM's own Kubernetes start-up on a new qcow2 overlay. The overlay sits on the same NVMe as the host swap. The same snapshot passed M2 on 2026-11-06, when the host was not swapping.

## Decision needed (user)

How to get a host on which the VM's etcd stays responsive:
1. **Free host memory and swap before the re-run** (recommended): close heavy apps and idle sessions, then `sudo swapoff -a && sudo swapon -a` once RAM allows. I then re-check the entry conditions and run the guided re-run unchanged.
2. **Run in a quiet window** (for example overnight, with no other workspace builds), with the same entry conditions and caps.
3. **Relax the VM entry condition** (for example, allow a settling period after the revert before the 5-min etcd window). This changes a rule set before the run, so it is yours to decide.

The VM is up on the fresh `f7-rerun-green` overlay and idle. The frozen checkout `~/.cache/ns-o-ran-frozen-harness/e86f1d08…` stays locked. Nothing else is in flight.

## User ruling (2026-11-08 02:01 KST)

Option 2, a quiet window. Wait until the Rust session in `dfm-devices-firmware` (docs-update-docs-extract-architecture) has finished its Phase 4 (characterization tests). The signal is its `executor-*-phase-04-*.md` report. Then resume the guided re-run with the entry conditions and caps unchanged. At 02:01 the host showed io full avg300 61 % with that session's `cargo test` running, swap 9 GiB, and MemAvailable 19 GiB.

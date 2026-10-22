# P5 snapshot housekeeping (2026-10-22T03:06–03:12Z)

**Outcome.**
- `m0-probe-f10212128` was deleted.
- **`f0`–`f6` were not deleted. The orchestrator stopped before the first delete** for the user's decision; libvirt did not refuse.
- `fresh-install` and `f7-rerun-green` both still revert and boot.

Files in this directory:
- `image-dir-before.txt` and `image-dir-after.txt`: `ls`, `du`, `df /home`, the snapshot tree and the active chain.
- `delete.log`.
- `revert-fresh-install-check.log`, `revert-f7-check.log` and `revert-f7-ready-after-settle.log`.

Before the first delete, the evidence of the f-run was checked. `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/` holds m0 `20261021T212837Z-host` and `20261021T212930Z`, m1 `213103Z`, m2 `215558Z`, m3 `221128Z`, m4 `225423Z`, m5 `231733Z`, m6 `232516Z` and m7 `233129Z`, each with a `verdict.json`, plus `p8-attempt2-run-to-m7.log`. All of it is tracked in git.

## What happened

1. The VM was shut off gracefully.
2. `vm-snapshot.sh delete m0-probe-f10212128` returned rc 0. libvirt also removed `ubuntu24.1792618108` (18 MB). That was the state image of the m0 probe, and also the overlay path recorded in `fresh-install`'s snapshot metadata.
3. To make sure the stale path does not break M9, `vm-snapshot.sh revert fresh-install` was run. It returned rc 0, the VM booted Ubuntu 24.04.5 with an empty home, and libvirt created a new overlay `ubuntu24.1792638522`. The raw base `ubuntu24.04` was unchanged (3.49 GB allocated before and after).
4. `vm-snapshot.sh revert f7-rerun-green` returned rc 0 and the VM booted. After about 3 min, `kubectl get nodes` showed Ready and all 14 `ricplt` pods were Running and Ready; kpimon and hw-go were Running.

## Why f0–f6 were not deleted

The active chain is: raw base → `ubuntu24.1792618143` → `-f0-preflight` → `-f1-ric-up` → `-f2-refnode` → `-f3-xapps` → `-f4-ns3-build` → `-f5-agent-setup` → `-f6-kpm` → the active overlay. `f7-rerun-green`'s state is everything up to `ubuntu24.04-f6-kpm.qcow2`.

Deleting a non-leaf external snapshot merges its overlay into the backing image. The merged data is still needed by `f7-rerun-green`, so very little space comes back. During each merge, though, the backing image grows by about the overlay's size before the overlay is removed:

| Snapshot | Overlay committed on delete | Allocated |
|---|---|---|
| f0-preflight | `ubuntu24.04-f0-preflight.qcow2` | 14.19 GB |
| f1-ric-up | `ubuntu24.04-f1-ric-up.qcow2` | 0.73 GB |
| f2-refnode | `ubuntu24.04-f2-refnode.qcow2` | 25.47 GB |
| f3-xapps | `ubuntu24.04-f3-xapps.qcow2` | 2.53 GB |
| f4-ns3-build | `ubuntu24.04-f4-ns3-build.qcow2` | 0.91 GB |
| f5-agent-setup | `ubuntu24.04-f5-agent-setup.qcow2` | 0.17 GB |
| f6-kpm | `ubuntu24.04-f6-kpm.qcow2` | 0.70 GB |

`/home` had 31.9 GB free (35 G after the revert). The f2 merge alone would take it to about 6 GB at peak, well under the contract's 20 GB floor. Running out of space during that merge would damage the chain `f7-rerun-green` depends on.

## Space that can actually be reclaimed (not touched; outside the contract's deletion list)

`ubuntu24.1792610322`, 39.55 GB allocated, created 2026-10-21T19:18:42Z, is not in the active chain and is not the recorded disk of any snapshot. It appears to be a leftover from P8 attempt 1. Deleting it needs the user's go-ahead.

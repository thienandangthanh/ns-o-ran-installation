# P5 snapshot housekeeping (2026-10-22T03:06–04:31Z)

**Outcome.**
- `m0-probe-f10212128` and `f0`–`f6` were deleted with `vm-snapshot.sh delete`, one at a time, with the VM shut off. Every delete returned rc 0, and libvirt never refused.
- The user approved deleting the unreferenced 39.55 GB image `ubuntu24.1792610322` before `f2-refnode`.
- Kept: `fresh-install` and `f7-rerun-green`.
- Both still revert and boot. `f7-rerun-green` comes up with the node Ready and all 14 `ricplt` pods Ready.
- `/home` free space went from 31.9 GB to 77 G.

Files in this directory:

| File | What it records |
|---|---|
| `image-dir-before.txt`, `image-dir-after.txt`, `image-dir-final.txt` | `ls`, `du`, `df /home` and the snapshot tree |
| `delete.log` | every delete and its rc, with the peak-space estimate |
| `delete-sizes.log` | `du` before and after each delete |
| `revert-*.log` | the revert checks |

Before the first delete, the f-run evidence was checked. `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/` holds m0 `20261021T212837Z-host` and `20261021T212930Z`, m1 `213103Z`, m2 `215558Z`, m3 `221128Z`, m4 `225423Z`, m5 `231733Z`, m6 `232516Z` and m7 `233129Z`, each with a `verdict.json`, plus `p8-attempt2-run-to-m7.log`. All of it is tracked in git.

## Sequence

1. **m0-probe-f10212128** returned rc 0. libvirt also removed `ubuntu24.1792618108` (18 MB), which was the overlay path recorded in `fresh-install`'s metadata. `revert fresh-install` was then checked: rc 0, and it booted Ubuntu 24.04.5 with an empty home (`revert-fresh-install-check.log`). The raw base `ubuntu24.04` is unchanged: 3,488,784,384 bytes allocated before and after, mtime 2026-10-21 16:04.
2. **f7 check.** `revert f7-rerun-green` returned rc 0, and all 14 `ricplt` pods became Ready (`revert-f7-check.log`, `revert-f7-ready-after-settle.log`).
3. **f5, f4, f6, f3, f1, f0.** Each returned rc 0. Deleting a non-leaf external snapshot commits its overlay into the backing image; for example, after the f5 delete, `-f4-ns3-build.qcow2` grew by 117 MB and `-f5-agent-setup.qcow2` was removed. The free space needed at the peak is therefore about the overlay's size. Before each delete, a guard required free space minus the overlay size to be at least 20 GiB. The lowest estimate was 23 GiB, for f0. Then `f7-rerun-green` was reverted and checked: all 14 pods Ready (`revert-f7-after-deletes.log`).
4. **f2-refnode** (25.2 GiB overlay) would have peaked at about 12 GiB free, below the contract's 20 GB floor, so the orchestrator asked the user. The user chose to delete the orphan first, then f2.
   - `ubuntu24.1792610322` (39,554,871,296 bytes allocated, created 2026-10-21T19:18:42Z, a leftover from P8 attempt 1) was referenced by no snapshot and by neither the live nor the inactive domain XML, and no process held it open. It was removed with `rm` (the directory belongs to the host user; no sudo).
   - f2-refnode was then deleted: rc 0, with a peak estimate of 49 GiB free.
5. **Final f7 check.** `revert f7-rerun-green` returned rc 0. The chain is now `ubuntu24.04` (raw base, `fresh-install`'s state) → `ubuntu24.1792618143` (holds the merged f0–f6 data, 39.7 GB) → the active overlay. After boot the node is Ready, all 14 `ricplt` pods are Ready, and kpimon and hw-go are Running (`revert-f7-final.log`).

Lesson for later runs: libvirt 12.8 removes the old active overlay on revert, so reverts no longer leave orphans. Deleting intermediate external snapshots frees almost nothing, because the merged data stays in the chain of the kept leaf, and it needs temporary space equal to each overlay.

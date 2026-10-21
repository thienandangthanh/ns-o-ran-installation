# P0 — Preflight, fork branches, gate harness (M0)

## Context
- VM `ubuntu24.04` / `ssh oran-kvm-2404` (uc@192.168.122.137) was probed read-only on 2026-10-21: Ubuntu 24.04.5, kernel 6.8, cgroup2, 8 vCPU, 15 GiB, LV 98 GB with `/` 85 GB free, swap 4 GB on, `sudo -n` OK, no git/docker/k8s yet. `sctp.ko` is present but not loaded. Egress to github, docker hub, pkgs.k8s.io, gerrit and nexus3 is OK.
- Host: `/home` 118 GB free, libvirt 12.8, `fresh-install` is external and was taken shut off. The disk chain is a raw base plus a qcow2 overlay in `/home/andang/VMs`.

## Requirements
1. Create branch `dev/l-release-nist180` on each fork, from its upstream pin, and push to `origin`:
   - O-RAN-Testbed-Automation `6088882`
   - ns-3-mmwave-oran `8c42089d`
   - oran-interface `5f547ae`
   - oran-e2sim `2209995`
2. On the Testbed fork branch, copy `RAN_Intelligent_Controllers/Near-Real-Time-RIC/commit_hashes_l_release.json` to `.../Near-Real-Time-RIC/commit_hashes.json` and commit it.
3. Gate harness, in the location settled at handoff:
   - `scripts/pins.env`: the 4 fork SHAs.
   - `scripts/vm/vm-snapshot.sh`: create, revert and list. Create is offline and disk-only (see plan.md).
   - `scripts/vm/vm-exec.sh`: an ssh wrapper that runs a gate on the VM and pulls `evidence/` back.
   - `scripts/gates/lib.sh`: shared helpers (verdict.json, evidence dir, retries).
   - `scripts/gates/gate-m0-preflight.sh`.
   - `scripts/run-to-m7.sh`: chains the gates; a stub at this stage.
4. Create `implementation-notes.html` in this plan dir.

## Gate M0 checks (`gate-m0-preflight.sh` + host part)
- Record the VM name, IP, `lsb_release -r` (must be 24.04), `df -h /`, `free -g`, `nproc`, cgroup fs and kernel.
- Host `df /home` ≥ 20 GB, with the value recorded. `virsh snapshot-list ubuntu24.04` includes `fresh-install`.
- **Snapshot probe.**
  1. Create `m0-probe`.
  2. Start the VM and write a marker file.
  3. `snapshot-revert m0-probe`.
  4. Start the VM again and assert the marker is absent.
  5. Record the disk chain (`domblklist`, `qemu-img info --backing-chain` is read-only) before and after.
- `modprobe sctp` works, and `lsmod | grep sctp` shows it.
- **Package availability on noble**, checked with `apt-cache madison` after adding the repos *in a throwaway step*, or with docs plus `curl` of the repo index:
  - kubeadm/kubelet/kubectl 1.33.x
  - containerd.io
  - docker-ce 29.5.x
  - helm 3.20.x
- **`git apply --check`.**
  - Clone ric-dep at `ee47a347` to `/tmp`, and dry-run every `git apply` in `apply_patches.sh` against it.
  - Clone kpimon-go at `8bbbbbb9`, and dry-run `install_xapp_kpi_monitor.sh`'s patches against it.
  - Record the output.
- Swap: NIST's installer turns it off; record that this is expected, not an error.
- Pass when every check passes. Then snapshot `l0-preflight`.

## Steps
1. Branches and the L drop-in (host worktree), then push.
2. Write the harness scripts and push them.
3. On the VM: `apt-get install -y git`, clone the harness at its pinned SHA, run gate M0.
4. Snapshot probe (host), then snapshot `l0-preflight`.

## Risks
- **External-snapshot revert semantics on libvirt 12.8 are unproven.**
  - The probe catches this. If the probe fails, STOP and ask; do not repair the host.
  - Do not delete `m0-probe` if libvirt refuses deletion with children.
- **Overlay chain growth eats host disk.** Record the bytes used per gate in implementation-notes so the P8 budget is known.

## Rollback
Revert to `fresh-install` (allowed; it is a revert, not a delete).

## Review amendments (contract-preserving review, 2026-10-21)
- **K4: the snapshot probe must exercise what P1 and P8 rely on.** It replaces the leaf-only probe above.
  1. Create `m0-probe-<run>`, start the VM, write a marker.
  2. Shut down and revert to **`fresh-install`** (a non-leaf with children).
  3. Start the VM. Assert the marker is absent and `m0-probe-<run>` is still listed.
  4. Create `m0-branch-<run>`, then delete it. Assert with `du` that its overlay is gone.
  5. Only then create `l0-preflight`.

  If libvirt refuses the delete, record it; the user's decision on the P8 fallback applies. Use `dumpxml` and `du` instead of `qemu-img`.
- **K12 (D1): harness home.** It lives on the parent repo branch `migrate-l-release-NIST-1-8-0` (made public by the user). Push that branch in P0, and assert `visibility == PUBLIC`. Prove that a clone of every pinned repo works from the `fresh-install` state with no credentials stored on the VM. Pass the harness SHA as an argument to `run-to-m7.sh`, never inside `pins.env`.
- **K15: extra egress checks (HEAD only).** packagecloud.io, dl.google.com, proxy.golang.org, `nexus3.o-ran-sc.org:10002`, and `ppa.launchpadcontent.net` (wireshark PPA).
- **K9: optional, during idle time.** Start identifying the asn1c generator commit for kpimon's `e2sm/lib`. Candidates are vlm/asn1c master and mouse07410 `vlm_master` around 2022-12 and 2023-11, matching kpimon commits f50ac28 and efa16fe.

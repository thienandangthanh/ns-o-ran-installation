# P1 — Near-RT RIC on the L pins (M1)

## Context
- `full_install.sh` order:
  1. needrestart conf, chrony, ric-dep clone
  2. `apply_patches.sh`
  3. `install_k8s_and_helm.sh` (k8s 1.33, helm 3.20, flannel, kube-proxy ipvs with iptables fallback)
  4. docker
  5. RIC `./install -f` retry loop
  6. e2-interface clone and build, `oransim:0.0.999` image
  7. chartmuseum, then `run_e2sim_and_connect_to_ric.sh`
  8. appmgr / onboarder, hw-go
- kpimon is **not** installed here.
- No `read` prompts on this path. `wait_for_ricplt_pods.sh:139` uses `read -t 5`, which times out on its own.
- The installer writes into its own tree with sudo (`rm -rf logs/`, `find … sed -i`, chown), so it must run from a VM-local clone.

## Requirements
- `gate-m1-ric-up.sh`:
  1. Clone the Testbed fork at the pinned SHA to `~/nist`.
  2. Run `full_install.sh`, logging to `evidence/m1/`, with stdin from `/dev/null`.
  3. Check that `git -C …/ric-dep rev-parse HEAD` = `ee47a347…` and appmgr = `4c05932d…`.
  4. Check that all `ricplt` pods are Running/Ready, sampled every 60 s for 10 min with zero restarts added.
  5. Record the image tags for e2term, e2mgr, rtmgr, submgr and appmgr. Expected from the L recipe: e2mgr/e2term 6.0.6, appmgr 0.5.8, rtmgr 0.9.6, submgr 0.10.2.
  6. Record the k8s, containerd and kernel versions.
- If `full_install.sh` ends with kpm_sim already connected, record that as a bonus. M2 still re-proves it with a pcap.

## Failure handling (L only)
- Any install failure means STOP retrying blindly:
  1. Classify the failure: apt/version on noble, image pull from nexus3, patch apply, helm, or a pod crash loop.
  2. After 2 failed attempts, consult kongming.
  3. Port fixes as `.patch` files under `install_patch_files/` on the fork, never as hand edits on the VM.
  4. If there is no workaround inside L, write a journal and report to the user. **No N.**
- Revert to `l0-preflight` between attempts if the cluster is half-installed.

## Done
M1 gate green, then snapshot `l1-ric-up`. Push any `.patch` added.

## Risks
- **Older L images (6.0.6 etc.) on k8s 1.33 / containerd 2.x.** Watch for rc pod churn and liveness flaps. The 10-minute stability window exists to catch these.
- **Pins the patched installer copies over whole** (`install_k8s_and_helm.sh`) could hit noble packages that are missing. P0 checks this first.

## Review amendments (contract-preserving review, 2026-10-21)
- **K3: unattended NIST calls.**
  - Run `full_install.sh` detached as `sleep infinity | timeout <budget> ./full_install.sh`.
  - `wait_for_ricplt_pods.sh` busy-loops when stdin is EOF (`:139` `read -t 5` returns instantly, `:162` skips the sleep), and it can wait forever on an unready e2term. The gate watchdog in plan.md handles this.
  - `run_e2sim_and_connect_to_ric.sh:104-160` loops forever and restarts kubelet, so it also needs `timeout`.
- **K15: record the resolved versions** (`dpkg -l` for kube*, containerd, docker, helm, plus every ricplt image digest) to `evidence/m1/versions.txt`. P8 diffs them. The installer falls back to the newest available package (`install_k8s_and_helm.sh:293-303`).
- **K6: re-sample after the reboot.** Snapshot `l1-ric-up` reboots the guest. Re-sample M1 pod stability once afterwards, through `gate_bringup ric`.

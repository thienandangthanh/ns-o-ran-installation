#!/usr/bin/env bash
# gate-m0-host.sh <run-prefix> <harness-sha>: host half of gate M0.
#
# Host facts, harness visibility, credential-free VM, and the snapshot probe
# that proves what P1 and P8 rely on: revert to the non-leaf fresh-install
# keeps sibling snapshots, and a snapshot can be created and deleted with its
# overlay removed. Leaves the VM running at fresh-install state.
# Writes $EVIDENCE_HOST_ROOT/m0/<ts>-host/verdict.json.

RUN_PREFIX="${1:?run prefix (l = dev run, f = re-run)}"
HARNESS_SHA="${2:?harness sha}"
source "$(dirname "$0")/../vm/vm-common.sh"
export GATE_SKIP_DISK_GUARD=1 HARNESS_SHA
GATE_TS=$(date -u +%Y%m%dT%H%M%SZ)
EVIDENCE_DIR="$EVIDENCE_HOST_ROOT/m0/$GATE_TS-host"
export GATE_TS EVIDENCE_DIR
source "$(dirname "$0")/lib.sh"
gate_init m0-host

SNAP="$REPO_ROOT/scripts/vm/vm-snapshot.sh"
run_id="$RUN_PREFIX$(date -u +%m%d%H%M)"
probe="m0-probe-$run_id"
branch="m0-branch-$run_id"
marker="/home/uc/m0-marker-$run_id"

{
    echo "domain $VM_DOMAIN ssh $VM_SSH"
    "${VIRSH[@]}" domifaddr "$VM_DOMAIN" 2>/dev/null || true
    echo "host /home free: $(host_free_gb)G"
    virsh --version
} >"$EVIDENCE_DIR/host-facts.txt"

check host_free_ge_20g test "$(host_free_gb)" -ge "$HOST_MIN_FREE_GB"
check fresh_install_present bash -c "${VIRSH[*]} snapshot-list $VM_DOMAIN --name | grep -x $VM_PROTECTED_SNAPSHOT >/dev/null"
check harness_repo_public bash -c 'gh repo view thienandangthanh/ns-o-ran-installation --json visibility -q .visibility | grep -qx PUBLIC'
check harness_anonymous_clone bash -c "d=\$(mktemp -d) && GIT_TERMINAL_PROMPT=0 git -c credential.helper= clone -q https://github.com/thienandangthanh/ns-o-ran-installation.git \$d/h && git -C \$d/h cat-file -e $HARNESS_SHA^{commit}; rc=\$?; rm -rf \$d; exit \$rc"

# --- snapshot probe -----------------------------------------------------------
disk_chain >"$EVIDENCE_DIR/disk-chain-before.txt"
check probe_create "$SNAP" create "$probe" --evidence "$EVIDENCE_DIR"
check probe_marker_written vm_ssh "touch $marker && test -e $marker"
check revert_fresh_install "$SNAP" revert "$VM_PROTECTED_SNAPSHOT"
disk_chain >"$EVIDENCE_DIR/disk-chain-after-revert.txt"
check marker_absent_after_revert bash -c "! ssh ${SSH_OPTS[*]} $VM_SSH test -e $marker"
check probe_still_listed bash -c "${VIRSH[*]} snapshot-list $VM_DOMAIN --name | grep -x $probe >/dev/null"
check branch_create "$SNAP" create "$branch" --evidence "$EVIDENCE_DIR"
branch_file="$VM_IMAGE_DIR/ubuntu24.04-$branch.qcow2"
check branch_overlay_exists test -e "$branch_file"
check branch_delete "$SNAP" delete "$branch"
disk_chain >"$EVIDENCE_DIR/disk-chain-after-branch-delete.txt"
check branch_unlisted bash -c "! ${VIRSH[*]} snapshot-list $VM_DOMAIN --name | grep -x $branch >/dev/null"
check branch_overlay_gone bash -c "! test -e '$branch_file'"
check vm_up_after_probe wait_ssh 300
"${VIRSH[@]}" snapshot-list "$VM_DOMAIN" --tree >"$EVIDENCE_DIR/snapshot-tree.txt"

# --- the VM holds no credentials ---------------------------------------------
check vm_no_git_credentials vm_ssh '! test -e ~/.git-credentials && ! git config --global --get credential.helper 2>/dev/null && ! ls ~/.ssh/id_* 2>/dev/null'

gate_finish

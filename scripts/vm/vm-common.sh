#!/usr/bin/env bash
# Host-side helpers shared by the VM wrappers (sourced). No host sudo anywhere:
# the host user manages qemu:///system through the libvirt group.

set -uo pipefail

VM_DOMAIN="${VM_DOMAIN:-ubuntu24.04}"
VM_SSH="${VM_SSH:-oran-kvm-2404}"
VM_IMAGE_DIR="${VM_IMAGE_DIR:-/home/andang/VMs}"
# shellcheck disable=SC2034  # used by the scripts that source this file
VM_PROTECTED_SNAPSHOT=fresh-install
# Never deleted by any script (user snapshot rule, 2026-10-23 01:03 KST; amendment A1: the top rung's green
# snapshot is r3p-green, or r2-green once substitution 4 is recorded in R3P_SUBST4_FILE).
VM_NEVER_DELETE=(fresh-install f7-rerun-green r3p-green)
R3P_SUBST4_FILE="${R3P_SUBST4_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/gates/r3p-substitution4.json}"
HOST_MIN_FREE_GB="${HOST_MIN_FREE_GB:-20}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Default is the M0-M7 plan; run-to-m9.sh and the R-rung gates export the M8-M9
# plan's evidence/ dir instead.
EVIDENCE_HOST_ROOT="${EVIDENCE_HOST_ROOT:-$REPO_ROOT/plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence}"

VIRSH=(virsh -q -c qemu:///system)
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

hlog() { echo "[host $(date -u +%H:%M:%S)] $*" >&2; }
die() { hlog "ERROR: $*"; exit 1; }

vm_ssh() { ssh "${SSH_OPTS[@]}" "$VM_SSH" "$@"; }

vm_state() { "${VIRSH[@]}" domstate "$VM_DOMAIN" 2>/dev/null | head -1; }

# wait_state <state> <timeout-s>
wait_state() {
    local want="$1" t="$2" i
    for ((i = 0; i < t; i += 3)); do
        [ "$(vm_state)" = "$want" ] && return 0
        sleep 3
    done
    return 1
}

wait_ssh() {
    local t="${1:-300}" i
    for ((i = 0; i < t; i += 5)); do
        vm_ssh true 2>/dev/null && return 0
        sleep 5
    done
    return 1
}

# vm_shutdown: graceful ACPI shutdown; never forces.
vm_shutdown() {
    [ "$(vm_state)" = "shut off" ] && return 0
    hlog "graceful shutdown of $VM_DOMAIN"
    "${VIRSH[@]}" shutdown "$VM_DOMAIN" >/dev/null || return 1
    wait_state "shut off" 240
}

vm_start() {
    [ "$(vm_state)" = "running" ] || "${VIRSH[@]}" start "$VM_DOMAIN" >/dev/null || return 1
    wait_ssh 300
}

# gate_id <gate-script>: gate-m5-agent-setup.sh -> m5, gate-r0-rc-scripted.sh -> r0, gate-r3p-ts-predictor.sh -> r3p.
gate_id() { sed -E 's/^gate-([a-z]+[0-9]+[a-z]?)-.*/\1/' <<<"$1"; }

# is_protected <snapshot>: true for the snapshots no script may delete.
is_protected() {
    local s
    for s in "${VM_NEVER_DELETE[@]}"; do [ "$1" = "$s" ] && return 0; done
    # substitution 4: R2 is the top rung, so its green snapshot is kept until M9 is green
    [ "$1" = r2-green ] && [ -e "$R3P_SUBST4_FILE" ] && return 0
    return 1
}

host_free_gb() { df -BG --output=avail /home | tail -1 | tr -dc '0-9'; }

# Disk chain as libvirt sees it, plus allocated bytes of every image file.
disk_chain() {
    "${VIRSH[@]}" domblklist "$VM_DOMAIN" --details
    "${VIRSH[@]}" dumpxml "$VM_DOMAIN" | sed -n '/<disk type=.file. device=.disk./,/<\/disk>/p'
    du -b --apparent-size "$VM_IMAGE_DIR"/* 2>/dev/null | sed 's/^/apparent /'
    du -B1 "$VM_IMAGE_DIR"/* 2>/dev/null | sed 's/^/allocated /'
}

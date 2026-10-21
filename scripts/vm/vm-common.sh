#!/usr/bin/env bash
# Host-side helpers shared by the VM wrappers (sourced). No host sudo anywhere:
# the host user manages qemu:///system through the libvirt group.

set -uo pipefail

VM_DOMAIN="${VM_DOMAIN:-ubuntu24.04}"
VM_SSH="${VM_SSH:-oran-kvm-2404}"
VM_IMAGE_DIR="${VM_IMAGE_DIR:-/home/andang/VMs}"
VM_PROTECTED_SNAPSHOT=fresh-install
HOST_MIN_FREE_GB="${HOST_MIN_FREE_GB:-20}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

host_free_gb() { df -BG --output=avail /home | tail -1 | tr -dc '0-9'; }

# Disk chain as libvirt sees it, plus allocated bytes of every image file.
disk_chain() {
    "${VIRSH[@]}" domblklist "$VM_DOMAIN" --details
    "${VIRSH[@]}" dumpxml "$VM_DOMAIN" | sed -n '/<disk type=.file. device=.disk./,/<\/disk>/p'
    du -b --apparent-size "$VM_IMAGE_DIR"/* 2>/dev/null | sed 's/^/apparent /'
    du -B1 "$VM_IMAGE_DIR"/* 2>/dev/null | sed 's/^/allocated /'
}

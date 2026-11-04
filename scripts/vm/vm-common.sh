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
# A cancelling stop path must stay inside its budget (m9-budget.py): every remote call it makes is bounded, so a
# responsive sshd whose systemctl never returns cannot hold the shutdown back. CANCEL_TIMEOUT_S bounds the stop.
CANCEL_TIMEOUT_S="${CANCEL_TIMEOUT_S:-30}"
vm_gate_units() { timeout --kill-after=2 10 ssh -n "${SSH_OPTS[@]}" "$VM_SSH" "systemctl list-units --plain --no-legend --state=active 'gate-*' | awk '{print \$1}'" 2>/dev/null | paste -sd, -; }
vm_stop_gates() { timeout --kill-after=2 "$CANCEL_TIMEOUT_S" ssh -n "${SSH_OPTS[@]}" "$VM_SSH" "sudo systemctl stop 'gate-*'" 2>/dev/null; }

# bounded: a stalled libvirt never holds a stop path back
vm_state() { timeout --kill-after=2 10 "${VIRSH[@]}" domstate "$VM_DOMAIN" 2>/dev/null | head -1; }

# wait_state <state> <timeout-s>
wait_state() {
    local want="$1" end=$(($(date +%s) + $2))
    while [ "$(date +%s)" -lt "$end" ]; do
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
    timeout 10 "${VIRSH[@]}" shutdown "$VM_DOMAIN" >/dev/null || return 1
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

# wd_finish <watchdog dir> <watchdog pid>: ends the host disk watchdog of a finished gate. It asks the watchdog for
# one last check (DIR/stop-request) and waits for it, without killing it: a trip under way completes, stops the gate
# units, shuts the VM down and TERMs the runner. The wait is bounded (WD_FINISH_TIMEOUT_S, default 600 s plus the
# cancel budget); past it, or when the stop request cannot be written, the watchdog is stopped and the finish fails.
# Returns 0 only when the watchdog stopped by itself without a trip.
wd_finish() {
    local dir="$1" pid="$2" bound=$((${WD_FINISH_TIMEOUT_S:-600} + CANCEL_TIMEOUT_S)) end rc
    end=$(($(date +%s) + bound))
    if ! : 2>/dev/null >"$dir/stop-request"; then
        hlog "watchdog: cannot write $dir/stop-request: stopping the watchdog, the gate's end is unchecked"
        [ -e "$dir/watchdog-tripping" ] || { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 1; }
    fi
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$(date +%s)" -ge "$end" ]; then
            hlog "watchdog: still running ${bound} s after the gate ended: stopping it"
            kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
            return 1
        fi
        sleep 1
    done
    wait "$pid"; rc=$?
    [ "$rc" -eq 0 ] && [ ! -e "$dir/watchdog-tripping" ]
}

# wd_on_exit <watchdog dir> <watchdog pid> <record function>: the runner's EXIT trap once the watchdog runs. A
# runner that ended normally sets WD_DONE first. Otherwise, with the trip latch present (a trip under way, also when
# a die path brought the runner here), it waits for the trip (wd_finish), calls the record function with 1 and exits
# 125; without the latch it stops the watchdog and keeps the runner's status.
wd_on_exit() {
    [ -z "${WD_DONE:-}" ] || return 0
    WD_DONE=1
    if [ -e "$1/watchdog-tripping" ]; then
        hlog "the host disk watchdog tripped: failing the gate with 125"
        # inside an EXIT trap the watchdog's closing TERM would kill this shell (143) before the record: the trip is
        # already being handled here, so TERM is ignored while it completes
        trap '' TERM
        wd_finish "$1" "$2" || true
        "$3" 1
        exit 125
    fi
    kill "$2" 2>/dev/null
}

host_free_gb() { df -BG --output=avail /home | tail -1 | tr -dc '0-9'; }

# host_disk_line <label>: "<label> <utc> <free /home GiB> <active vda overlay> <its allocated GiB>" (allocated
# blocks, du -BG, not the apparent size): the per-gate-boundary host disk measurement.
host_disk_line() {
    local vda
    vda=$("${VIRSH[@]}" domblklist "$VM_DOMAIN" --details 2>/dev/null | awk '$3 == "vda" { print $4 }')
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(date -u +%Y%m%dT%H%M%SZ)" "$(host_free_gb)" "${vda:-?}" \
        "$( [ -n "$vda" ] && du -BG "$vda" 2>/dev/null | cut -f1 | tr -dc '0-9' || echo '?')"
}

# Disk chain as libvirt sees it, plus allocated bytes of every image file.
disk_chain() {
    "${VIRSH[@]}" domblklist "$VM_DOMAIN" --details
    "${VIRSH[@]}" dumpxml "$VM_DOMAIN" | sed -n '/<disk type=.file. device=.disk./,/<\/disk>/p'
    du -b --apparent-size "$VM_IMAGE_DIR"/* 2>/dev/null | sed 's/^/apparent /'
    du -B1 "$VM_IMAGE_DIR"/* 2>/dev/null | sed 's/^/allocated /'
}

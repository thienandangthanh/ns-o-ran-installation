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
    timeout --kill-after=2 10 "${VIRSH[@]}" shutdown "$VM_DOMAIN" >/dev/null || return 1
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

# wd_start <dir> <min GiB> <interval s> <runner pid> <log>: starts host-disk-watchdog.sh as the leader of its own
# session (setsid) and sets WD_PID. Every ssh, virsh and timeout it runs stays in that session (timeout makes its
# own process group, never its own session), so wd_stop_session reaches all of them.
# A background job of a non-interactive shell is never a process group leader, so setsid(1) does not fork and $! is
# the session leader itself; the start waits (bounded) until setsid() has run and fails if it never does. The
# runner arms its traps (wd_arm) before calling this, so a trip during the wait is handled like any other. A TERM
# between the launch and WD_PID=$! is held until the pid is saved: acted on earlier, the finaliser would not know
# which session to stop.
wd_start() {
    local i
    WD_TERM_HELD=""
    trap 'WD_TERM_HELD=1' TERM
    setsid bash "$(dirname "${BASH_SOURCE[0]}")/host-disk-watchdog.sh" --min-gb "$2" --interval "$3" --out "$1" \
        --runner-pid "$4" >>"$5" 2>&1 &
    WD_PID=$!
    trap wd_term_exit TERM
    [ -z "$WD_TERM_HELD" ] || wd_term_exit
    for ((i = 0; i < 100; i++)); do
        [ "$(ps -o sid= -p "$WD_PID" 2>/dev/null | tr -d ' ')" = "$WD_PID" ] && return 0
        kill -0 "$WD_PID" 2>/dev/null || break
        sleep 0.1
    done
    # still this shell's unreaped child, so its pid cannot have been reused
    kill -TERM "$WD_PID" 2>/dev/null
    hlog "watchdog: not a session leader"
    return 1
}

# wd_term_exit: the runner's TERM action (a trip's closing signal or one from outside). TERM is ignored from here on,
# so the finaliser (wd_on_exit, the EXIT trap) cannot be cut short by a second one.
wd_term_exit() {
    trap '' TERM
    hlog "runner: TERM"
    exit 143
}

# wd_arm <watchdog dir> <record function>: the runner's traps, installed before wd_start. TERM only exits; EXIT runs
# wd_on_exit, the single finaliser of every path that wd_end did not finish.
wd_arm() {
    WD_PID=""
    WD_DONE=""
    # shellcheck disable=SC2064  # the dir and function name are fixed at arm time
    trap "wd_on_exit $(printf '%q %q' "$1" "$2")" EXIT
    trap wd_term_exit TERM
}

# wd_end <watchdog dir> <record function>: the normal end of a gate. TERM is held while it finishes the watchdog,
# decides the status and writes the record; the run is marked finalised only once the record is written. A clean
# finish records 0 and returns (or exits 143 for a TERM held meanwhile); a trip, or a finish that failed, records
# the latch and exits 125.
wd_end() {
    local rc=0
    WD_TERM_HELD=""
    trap 'WD_TERM_HELD=1' TERM
    if wd_finish "$1"; then
        "$2" 0
    else
        hlog "the host disk watchdog tripped or did not finish while the gate ended: failing the gate"
        "$2" "$([ -e "$1/watchdog-tripping" ] && echo 1 || echo 0)"
        rc=125
    fi
    WD_DONE=1
    trap wd_term_exit TERM
    [ "$rc" -eq 0 ] || exit 125
    [ -z "$WD_TERM_HELD" ] || wd_term_exit
    return 0
}

# wd_stop_session <watchdog pid>: TERM to every process of the watchdog's session, KILL to what is left after 5 s,
# then reap the watchdog. Called only while the runner still owns the session (the watchdog not yet seen to exit).
wd_stop_session() {
    local i
    [ -n "$1" ] || return 0
    pkill -TERM -s "$1" 2>/dev/null
    for ((i = 0; i < 5; i++)); do pgrep -s "$1" >/dev/null || break; sleep 1; done
    pkill -KILL -s "$1" 2>/dev/null
    wait "$1" 2>/dev/null
    return 0
}

# wd_finish <watchdog dir>: ends the host disk watchdog (WD_PID) of a finished gate. It asks the watchdog for one
# last check (DIR/stop-request) and waits for it, without killing it: a trip under way completes, stops the gate
# units, shuts the VM down and TERMs the runner. The wait is bounded (WD_FINISH_TIMEOUT_S, default 600 s plus the
# cancel budget); past it, or when the stop request cannot be written, the watchdog's whole session is stopped and
# the finish fails. Every return ends the runner's ownership of the session: once the watchdog is seen gone, the
# session is swept once and WD_PID is cleared, so no later path signals a session id that may since be reused.
# Returns 0 only when the watchdog stopped by itself without a trip.
wd_finish() {
    local dir="$1" pid="${WD_PID:-}" bound=$((${WD_FINISH_TIMEOUT_S:-600} + CANCEL_TIMEOUT_S)) end rc
    [ -n "$pid" ] || return 1
    end=$(($(date +%s) + bound))
    if ! : 2>/dev/null >"$dir/stop-request"; then
        hlog "watchdog: cannot write $dir/stop-request: stopping the watchdog, the gate's end is unchecked"
        [ -e "$dir/watchdog-tripping" ] || { wd_stop_session "$pid"; WD_PID=""; return 1; }
    fi
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$(date +%s)" -ge "$end" ]; then
            hlog "watchdog: still running ${bound} s after the gate ended: stopping its session"
            wd_stop_session "$pid"
            WD_PID=""
            return 1
        fi
        sleep 1
    done
    wait "$pid"; rc=$?
    # the watchdog runs its commands in the foreground, so its session is empty once it exits by itself; any member
    # left keeps the session id allocated (Linux never reuses an id still in use as a session id), so this sweep
    # cannot reach another session
    pkill -KILL -s "$pid" 2>/dev/null
    WD_PID=""
    [ "$rc" -eq 0 ] && [ ! -e "$dir/watchdog-tripping" ]
}

# wd_on_exit <watchdog dir> <record function>: the EXIT trap wd_arm installs, the one finaliser of every exit that
# wd_end did not finish (a trip's TERM, an outside TERM, a die). It asks the watchdog to stop and lets a trip under
# way complete (wd_finish, bounded, which also stops and forgets the session), and only then decides: with the trip
# latch it records 1 and exits 125; without it the runner's status stands and nothing is recorded as a trip.
wd_on_exit() {
    # inside an EXIT trap a TERM (the watchdog's closing one) takes the default action and would kill this shell
    # before the record: every path is already finishing here, so TERM is ignored
    trap '' TERM
    [ -z "${WD_DONE:-}" ] || return 0
    WD_DONE=1
    [ -n "${WD_PID:-}" ] || return 0
    wd_finish "$1" || true
    if [ -e "$1/watchdog-tripping" ]; then
        hlog "host /home under the watchdog floor: it stopped the gate units and shut the VM down; evidence stays on the VM disk; failing the gate with 125"
        "$2" 1
        exit 125
    fi
    return 0
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

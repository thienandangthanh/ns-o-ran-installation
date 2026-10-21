#!/usr/bin/env bash
# run-to-m7.sh --harness-sha SHA --run-prefix l|f [--from N] [--to N] [--no-snapshots]
#
# Host-side chain of gates M0..M7. Each gate runs on the VM through vm-exec.sh
# (detached, evidence copied back). After a green gate the VM is snapshotted
# (offline, so it reboots); with --no-snapshots it still reboots at the same
# boundary so every run sees the same cadence. Stops at the first red gate.
#
# The dev run uses prefix l (l0-preflight ...); the P8 re-run uses f and always
# ends with f7-rerun-green.

set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/vm/vm-common.sh"

harness_sha=""; prefix=""; from=0; to=7; snapshots=1
while [ $# -gt 0 ]; do
    case "$1" in
        --harness-sha) harness_sha="$2"; shift 2 ;;
        --run-prefix) prefix="$2"; shift 2 ;;
        --from) from="$2"; shift 2 ;;
        --to) to="$2"; shift 2 ;;
        --no-snapshots) snapshots=0; shift ;;
        *) die "unknown arg $1" ;;
    esac
done
[ -n "$harness_sha" ] && [ -n "$prefix" ] || die "need --harness-sha and --run-prefix"

# gate number -> "script|snapshot-suffix|timeout-s|expected growth GB"
declare -A GATES=(
    [0]="gate-m0-preflight.sh|preflight|1800|1"
    [1]="gate-m1-ric-up.sh|ric-up|9600|25"
    [2]="gate-m2-refnode.sh|refnode|3600|3"
    [3]="gate-m3-xapps.sh|xapps|5400|8"
    [4]="gate-m4-ns3-build.sh|ns3-build|7200|10"
    [5]="gate-m5-agent-setup.sh|agent-setup|5400|3"
    [6]="gate-m6-kpm.sh|kpm|3600|2"
    [7]="gate-m7-multignb.sh|multignb|6000|2"
)

boundary() {
    local n="$1" suffix="$2" grow="$3" ev="$4"
    local name="$prefix$n-$suffix"
    [ "$n" = 7 ] && [ "$prefix" = f ] && name="f7-rerun-green"
    if [ "$snapshots" = 1 ] || [ "$name" = "f7-rerun-green" ]; then
        "$here/vm/vm-snapshot.sh" create "$name" --need-gb "$grow" --evidence "$ev" || return 1
    else
        hlog "no-snapshot mode: rebooting at the $name boundary"
        vm_shutdown && vm_start || return 1
    fi
}

for ((n = from; n <= to; n++)); do
    IFS='|' read -r script suffix tmo grow <<<"${GATES[$n]}"
    [ -f "$here/gates/$script" ] || die "gate script $script not written yet"
    if [ "$n" = 0 ]; then
        "$here/gates/gate-m0-host.sh" "$prefix" "$harness_sha" || die "M0 host half failed"
    fi
    "$here/vm/vm-exec.sh" "$script" --harness-sha "$harness_sha" --timeout "$tmo" ||
        die "gate m$n failed; evidence: $(cat "$EVIDENCE_HOST_ROOT/.last-m$n" 2>/dev/null)"
    boundary "$n" "$suffix" "$grow" "$(cat "$EVIDENCE_HOST_ROOT/.last-m$n")" || die "boundary after m$n failed"
    hlog "m$n green"
done
hlog "gates m$from..m$to green"

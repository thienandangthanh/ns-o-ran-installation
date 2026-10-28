#!/usr/bin/env bash
# run-to-m9.sh --harness-sha SHA [--run-prefix P] [--from STEP] [--to STEP] [--no-snapshots]
#
# Host-side chain for M9 (amendment A1): gates M0..M7 (as run-to-m7.sh), then the installs and rungs
#   i0 (RC decoder build + rc install) -> r0 -> r1 -> i2 (TS xApp + stub QP install) -> r2 -> r3p
# Rungs below the top run one live run (--mode single, C2-C9); the top rung runs its full repeat gate (--mode c1)
# against its committed dev reference (--reference). The top rung is R3′ (gate-r3p-ts-predictor.sh), or R2 when
# scripts/gates/r3p-substitution4.json records substitution 4 (validated: its dry-run evidence dir exists and its
# rung-config and scenario sha256s equal the frozen files); then r3p is not a step and r2 runs c1.
#
# Budget (scripts/m9-budget.json, measured at P9; the run refuses to start without it): per-step timeouts, the
# global wall deadline, the watchdog's polling interval and trip point (25 + h GB). Two bounded stop paths:
#   (a) host-disk-watchdog.sh trips below the trip point (stops the VM gate unit, shuts the VM down, stops this
#       runner); (b) m9-heartbeat-monitor.sh cancels the same way when the watchdog's heartbeat is older than two
#       polling periods or the global wall deadline passes.
# The verdict (evidence/m9/<ts>/verdict.json, m9-verdict.py) is written in every case and fails closed: exactly
# the pre-registered step set, every step green, the top rung's C1 green and equal to its reference, minHostFreeGb
# >= 25, the watchdog alive throughout; a --from/--to subset is marked notM9.
#
# --run-prefix defaults to n; f and l are reserved (M0-M7 runs) and a prefix whose snapshots already exist is
# refused. With --no-snapshots no snapshot is created, M7 included; gate-m0-host.sh still creates the
# m0-probe/m0-branch pair (allowed by the snapshot rule). STEP is one of m0..m7, i0, r0, r1, i2, r2, r3p.

set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export EVIDENCE_HOST_ROOT="${EVIDENCE_HOST_ROOT:-$here/../plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence}"
source "$here/vm/vm-common.sh"
EVIDENCE_HOST_ROOT="$(cd "$EVIDENCE_HOST_ROOT" && pwd)"
PLAN_REL=plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9
BUDGET="$here/m9-budget.json"
SUB4="$here/gates/r3p-substitution4.json"

harness_sha=""; prefix="n"; from="m0"; to=""; snapshots=1
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
[ -n "$harness_sha" ] || die "need --harness-sha"
case "$prefix" in
    f | l) die "prefix $prefix is reserved" ;;
    [a-z]) ;;
    *) die "prefix must be one lower-case letter" ;;
esac
"${VIRSH[@]}" snapshot-list "$VM_DOMAIN" --name | grep -E "^${prefix}[0-9]-" >/dev/null &&
    die "snapshots with prefix $prefix already exist"
# the VM clones --harness-sha while this runner and its host scripts run from the worktree: refuse unless they agree
git -C "$here/.." rev-parse -q --verify "$harness_sha^{commit}" >/dev/null || die "harness sha $harness_sha is not a commit here"
git -C "$here/.." diff --quiet "$harness_sha" -- scripts tools "$PLAN_REL/reference" ||
    die "scripts, tools or the reference differ from $harness_sha in this worktree"
[ -z "$(git -C "$here/.." ls-files --others --exclude-standard -- scripts tools "$PLAN_REL/reference")" ] ||
    die "untracked files under scripts, tools or the reference"
[ -s "$BUDGET" ] || die "no $BUDGET: the M9 budget (timeouts, wall deadline, trip point) is measured at P9"
budget() { python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])); [v := v[k] for k in sys.argv[2].split(".")]; print(v)' "$BUDGET" "$1"; }

# the top rung: R3′, or R2 under a validated substitution 4 record
top=r3p; sub4=none
if [ -e "$SUB4" ]; then
    top=r2
    if python3 -I "$here/gates/r3p-substitution4-validate.py" "$SUB4" "$here/.."; then sub4=pass; else sub4=fail; fi
fi
hlog "top rung $top (substitution 4 record: $sub4)"

# step -> "script|snapshot-suffix|expected growth GB|gate args"; timeouts come from the budget
ORDER=(m0 m1 m2 m3 m4 m5 m6 m7 i0 r0 r1 i2 r2)
[ "$top" = r3p ] && ORDER+=(r3p)
declare -A STEPS=(
    [m0]="gate-m0-preflight.sh|preflight|1|"
    [m1]="gate-m1-ric-up.sh|ric-up|25|"
    [m2]="gate-m2-refnode.sh|refnode|3|"
    [m3]="gate-m3-xapps.sh|xapps|8|"
    [m4]="gate-m4-ns3-build.sh|ns3-build|10|"
    [m5]="gate-m5-agent-setup.sh|agent-setup|3|"
    [m6]="gate-m6-kpm.sh|kpm|2|"
    [m7]="gate-m7-multignb.sh|multignb|2|"
    [i0]="gate-i0-rc-install.sh|-|3|"
    [r0]="gate-r0-rc-scripted.sh|-|1|--mode single"
    [r1]="gate-r1-rc-multi-control.sh|-|1|--mode single"
    [i2]="gate-i2-ts-xapp-install.sh|-|3|"
    [r2]="gate-r2-ts-stub-qp.sh|-|1|--mode single"
    [r3p]="gate-r3p-ts-predictor.sh|-|2|--mode c1 --reference $PLAN_REL/reference/r3p"
)
[ "$top" = r2 ] && STEPS[r2]="gate-r2-ts-stub-qp.sh|-|2|--mode c1 --reference $PLAN_REL/reference/r2"
[ -n "$to" ] || to="${ORDER[-1]}"

idx() { local i; for i in "${!ORDER[@]}"; do [ "${ORDER[$i]}" = "$1" ] && echo "$i" && return; done; die "unknown step $1"; }
from_i=$(idx "$from"); to_i=$(idx "$to")
full=0; [ "$from_i" = 0 ] && [ "$to_i" = $((${#ORDER[@]} - 1)) ] && full=1

run_ts=$(date -u +%Y%m%dT%H%M%SZ)
run_dir="$EVIDENCE_HOST_ROOT/m9/$run_ts"
wd="$EVIDENCE_HOST_ROOT/watchdog"
mkdir -p "$run_dir" "$wd"
steps_file="$run_dir/steps.tsv"
: >"$steps_file"
interval=$(budget watchdog.intervalS); trip_gb=$(budget watchdog.tripGb); wall_s=$(budget globalWallS)

write_verdict() {
    python3 -I "$here/m9-verdict.py" "$steps_file" "$run_dir/verdict.json" --expected "$(IFS=,; echo "${ORDER[*]}")" \
        --top "$top" --full "$full" --watchdog-dir "$wd" --pins "$here/pins.conf" --harness "$harness_sha" \
        --prefix "$prefix" --snapshots "$snapshots" --sub4 "$sub4" --min-free-floor 25
    cp "$wd"/{min-host-free-gb.txt,free-series.tsv,watchdog-alive.json,watchdog-tripped.json,watchdog-lost.json,wall-deadline.json} "$run_dir/" 2>/dev/null
}

finish() {
    local rc="$1"
    [ -n "${mon_pid:-}" ] && kill "$mon_pid" 2>/dev/null
    [ -n "${wd_pid:-}" ] && kill "$wd_pid" 2>/dev/null
    write_verdict || rc=1
    exit "$rc"
}
trap 'hlog "stopped by the disk watchdog or the heartbeat monitor"; finish 3' TERM

rm -f "$wd"/{watchdog-tripped.json,min-host-free-gb.txt,free-series.tsv,heartbeat,watchdog-alive.json,watchdog-lost.json,wall-deadline.json}
"$here/vm/host-disk-watchdog.sh" --runner-pid $$ --min-gb "$trip_gb" --interval "$interval" --out "$wd" &
wd_pid=$!
"$here/vm/m9-heartbeat-monitor.sh" --runner-pid $$ --dir "$wd" --interval "$interval" \
    --deadline-epoch $(($(date +%s) + wall_s)) &
mon_pid=$!
hlog "M9 run $run_ts: steps ${ORDER[*]} (full $full), watchdog trip ${trip_gb} GB every ${interval} s, wall ${wall_s} s"

boundary() {
    local step="$1" suffix="$2" grow="$3" ev="$4"
    local name="$prefix${step#m}-$suffix"
    if [ "$snapshots" = 1 ]; then
        "$here/vm/vm-snapshot.sh" create "$name" --need-gb "$grow" --evidence "$ev" || return 1
    else
        hlog "no-snapshot mode: rebooting at the $name boundary"
        vm_shutdown && vm_start || return 1
    fi
}

for ((i = from_i; i <= to_i; i++)); do
    step="${ORDER[$i]}"
    IFS='|' read -r script suffix grow args <<<"${STEPS[$step]}"
    tmo=$(budget "timeoutsS.$step") || { hlog "no timeout for $step in the budget"; printf '%s\tfail\t\n' "$step" >>"$steps_file"; finish 1; }
    [ -f "$here/gates/$script" ] || { printf '%s\tfail\t\n' "$step" >>"$steps_file"; hlog "gate script $script not written yet"; finish 1; }
    if [ "$step" = m0 ]; then
        "$here/gates/gate-m0-host.sh" "$prefix" "$harness_sha" || { printf 'm0-host\tfail\t\n' >>"$steps_file"; finish 1; }
    fi
    read -ra gargs <<<"$args"
    if "$here/vm/vm-exec.sh" "$script" --harness-sha "$harness_sha" --timeout "$tmo" -- "${gargs[@]}"; then
        status=pass
    else
        status=fail
    fi
    ev=$(cat "$EVIDENCE_HOST_ROOT/.last-$step" 2>/dev/null)
    printf '%s\t%s\t%s\n' "$step" "$status" "$ev" >>"$steps_file"
    [ "$status" = pass ] || { hlog "step $step failed; evidence: $ev"; finish 1; }
    if [ "$suffix" != - ]; then
        boundary "$step" "$suffix" "$grow" "$ev" || { hlog "boundary after $step failed"; finish 1; }
    fi
    hlog "$step green"
done
hlog "steps $from..$to green"
finish 0

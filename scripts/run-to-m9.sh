#!/usr/bin/env bash
# run-to-m9.sh --harness-sha SHA [--run-prefix P] [--from STEP] [--to STEP] [--no-snapshots]
#
# Host-side chain for M9: gates M0..M7 (as run-to-m7.sh), then the installs and
# rungs R0..R3 in this order:
#   i0 (RC decoder build + rc install) -> r0 -> r1
#   -> i2 (TS xApp + stub QP install) -> r2
#   -> i3 (stub QP down + QP fork install) -> r3
# Rungs below the top run one live run (--mode single, C2-C9); r3 runs its
# full repeat gate (--mode c1) against the committed dev reference.
#
# Evidence goes to the M8-M9 plan's evidence/ dir. A host disk watchdog runs
# for the whole chain: below 25 GB free it stops the VM unit, shuts the VM down
# and stops this runner. The chain stops at the first red step; the run
# verdict (evidence/m9/<ts>/verdict.json) is written in every case.
#
# --run-prefix defaults to n; f and l are reserved (M0-M7 runs) and a prefix
# whose snapshots already exist is refused. With --no-snapshots no snapshot is
# created, M7 included; gate-m0-host.sh still creates the m0-probe/m0-branch
# pair (allowed by the snapshot rule). STEP is one of m0..m7, i0, r0, r1, i2,
# r2, i3, r3.

set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export EVIDENCE_HOST_ROOT="${EVIDENCE_HOST_ROOT:-$here/../plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence}"
source "$here/vm/vm-common.sh"
EVIDENCE_HOST_ROOT="$(cd "$EVIDENCE_HOST_ROOT" && pwd)"

harness_sha=""; prefix="n"; from="m0"; to="r3"; snapshots=1
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

# step -> "script|snapshot-suffix|timeout-s|expected growth GB|gate args"
ORDER=(m0 m1 m2 m3 m4 m5 m6 m7 i0 r0 r1 i2 r2 i3 r3)
declare -A STEPS=(
    [m0]="gate-m0-preflight.sh|preflight|1800|1|"
    [m1]="gate-m1-ric-up.sh|ric-up|9600|25|"
    [m2]="gate-m2-refnode.sh|refnode|3600|3|"
    [m3]="gate-m3-xapps.sh|xapps|5400|8|"
    [m4]="gate-m4-ns3-build.sh|ns3-build|7200|10|"
    [m5]="gate-m5-agent-setup.sh|agent-setup|5400|3|"
    [m6]="gate-m6-kpm.sh|kpm|3600|2|"
    [m7]="gate-m7-multignb.sh|multignb|6000|2|"
    [i0]="gate-i0-rc-install.sh|-|3600|3|"
    [r0]="gate-r0-rc-scripted.sh|-|5400|1|--mode single"
    [r1]="gate-r1-rc-multi-control.sh|-|5400|1|--mode single"
    [i2]="gate-i2-ts-xapp-install.sh|-|3600|3|"
    [r2]="gate-r2-ts-stub-qp.sh|-|5400|1|--mode single"
    [i3]="gate-i3-qp-install.sh|-|5400|5|"
    [r3]="gate-r3-ts-qp-fork.sh|-|14400|2|--mode c1 --reference"
)

idx() { local i; for i in "${!ORDER[@]}"; do [ "${ORDER[$i]}" = "$1" ] && echo "$i" && return; done; die "unknown step $1"; }
from_i=$(idx "$from"); to_i=$(idx "$to")

run_ts=$(date -u +%Y%m%dT%H%M%SZ)
run_dir="$EVIDENCE_HOST_ROOT/m9/$run_ts"
mkdir -p "$run_dir"
steps_file="$run_dir/steps.tsv"
: >"$steps_file"

write_verdict() {
    python3 - "$steps_file" "$run_dir/verdict.json" "$harness_sha" "$here/pins.conf" \
        "$EVIDENCE_HOST_ROOT/watchdog" "$prefix" "$snapshots" <<'PY'
import json, os, sys
steps_file, out, harness, pins, wd, prefix, snaps = sys.argv[1:]
steps = []
for line in open(steps_file):
    step, status, ev = line.rstrip("\n").split("\t")
    entry = {"step": step, "pass": status == "pass", "evidence": ev}
    vp = os.path.join(ev, "verdict.json") if ev else ""
    if vp and os.path.exists(vp):
        v = json.load(open(vp))
        entry["failed"] = v.get("failed", [])
        entry["pins"] = v.get("pins", {})
    steps.append(entry)
pin_map = dict(l.strip().split("=", 1) for l in open(pins) if "=" in l and not l.startswith("#"))
rungs = [s["step"] for s in steps if s["step"].startswith("r") and s["pass"]]
minfree = None
mf = os.path.join(wd, "min-host-free-gb.txt")
if os.path.exists(mf):
    minfree = int(open(mf).read().strip())
tripped = os.path.exists(os.path.join(wd, "watchdog-tripped.json"))
verdict = {"harness_sha": harness, "pins": pin_map, "run_prefix": prefix,
           "snapshots": snaps == "1", "steps": steps,
           "highestGreenRung": rungs[-1] if rungs else None,
           "minHostFreeGb": minfree, "watchdogTripped": tripped,
           "pass": bool(steps) and all(s["pass"] for s in steps) and not tripped}
json.dump(verdict, open(out, "w"), indent=2)
print(f"M9 verdict: {'PASS' if verdict['pass'] else 'FAIL'} highest green rung "
      f"{verdict['highestGreenRung']} min host free {minfree} GB -> {out}")
PY
}

finish() {
    local rc="$1"
    [ -n "${wd_pid:-}" ] && kill "$wd_pid" 2>/dev/null
    write_verdict
    exit "$rc"
}
trap 'hlog "stopped by the disk watchdog"; finish 3' TERM

rm -f "$EVIDENCE_HOST_ROOT/watchdog/watchdog-tripped.json" "$EVIDENCE_HOST_ROOT/watchdog/min-host-free-gb.txt"
"$here/vm/host-disk-watchdog.sh" --runner-pid $$ &
wd_pid=$!

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
    IFS='|' read -r script suffix tmo grow args <<<"${STEPS[$step]}"
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

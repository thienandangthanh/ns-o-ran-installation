#!/usr/bin/env bash
# P10 VM gate chain driver (the P09 driver with a per-commit step list). D-R3-1: M2-M7 (M5 builds the agent image
# with its codec byte-equality probe; M5-M7 after every agent change), then I0, I2 and the live e2i interop gate.
#   p10-gate-chain.sh HARNESS_SHA [FIRST_STEP_INDEX] [LAST_STEP_INDEX]   run the chain at one harness SHA, stop at the
#                                                                       first red step
#   p10-gate-chain.sh --check-dir RUN_DIR              the per-step run-dir cross-check alone (offline validation)
#
# Every step's host side (vm-exec.sh, the watchdog) runs from a frozen checkout of the SHA: a detached, locked
# worktree on /home with read-only scripts/, checked (HEAD = SHA, tracked files clean) before every step, so an
# edit of the main worktree never reaches a running runner. A step that exits 0 is still red unless the run dir
# that .last-<gate> names, rewritten during the step, has exit_code 0, host-disk.tsv, host-disk-watchdog.json with
# tripped false, and a passing verdict.json when it has one.
# Each line of $log: <utc> <index> <gate id> <script> <args> <exit code> <frozen HEAD> <run dir>.
# The whole body is one function, parsed before it runs: editing this file cannot reach a running chain.

main() {
set -u
repo=/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0
here=/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/fdfe16a0-64f3-4277-9ef6-e00f0ee9ba0c/scratchpad
log=$here/p10-gate-chain.tsv
export EVIDENCE_HOST_ROOT=$repo/plans/261103-0008-GH-1-post-m9-realism-m10/evidence
ref=plans/261103-0008-GH-1-post-m9-realism-m10/reference
m9ref=plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p/equal

# check_dir <run dir>: the cross-check of one step's run dir; prints the first missing condition
check_dir() {
    local d="$1"
    [ -d "$d" ] || { echo "no run dir $d"; return 1; }
    [ "$(cat "$d/exit_code" 2>/dev/null)" = 0 ] || { echo "exit_code is not 0"; return 1; }
    [ -s "$d/host-disk.tsv" ] || { echo "no host-disk.tsv"; return 1; }
    python3 -I - "$d" <<'PY'
import json, os, sys
d = sys.argv[1]
try:
    w = json.load(open(os.path.join(d, "host-disk-watchdog.json")))
except (OSError, ValueError) as e:
    sys.exit(f"no readable host-disk-watchdog.json ({e.__class__.__name__})")
if w.get("tripped") is not False:
    sys.exit(f"host-disk-watchdog.json tripped is {w.get('tripped')!r}")
v = os.path.join(d, "verdict.json")
if os.path.exists(v) and json.load(open(v)).get("pass") is not True:
    sys.exit("verdict.json does not pass")
PY
}

if [ "${1:-}" = --check-dir ]; then
    check_dir "$2" && echo "run dir ok: $2"
    return
fi

sha=$1; first=${2:-0}; last=${3:-999}
frozen=$HOME/.cache/ns-o-ran-frozen-harness/$sha
[ -d "$frozen/scripts/vm" ] || { echo "no frozen checkout at $frozen"; return 2; }
steps=(
  "m2|gate-m2-refnode.sh|3600|"
  "m3|gate-m3-xapps.sh|3600|"
  "m4|gate-m4-ns3-build.sh|7200|"
  "m5|gate-m5-agent-setup.sh|3600|"
  "m6|gate-m6-kpm.sh|3600|"
  "m7|gate-m7-multignb.sh|3600|"
  "i0|gate-i0-rc-install.sh|3600|"
  "i2|gate-i2-ts-xapp-install.sh|3600|"
  "e2i|gate-e2i-interop.sh|5400|--image-tag 09aeabb8b0f99b0c"
)
cd "$frozen" || return 2
for i in "${!steps[@]}"; do
    [ "$i" -lt "$first" ] && continue
    [ "$i" -gt "$last" ] && break
    IFS='|' read -r id g t a <<<"${steps[$i]}"
    head=$(git -C "$frozen" rev-parse HEAD)
    if [ "$head" != "$sha" ] || [ -n "$(git -C "$frozen" status --porcelain --untracked-files=no)" ]; then
        echo "step $i: the frozen checkout is not clean at $sha (HEAD $head)"
        return 2
    fi
    start=$(date +%s)
    # shellcheck disable=SC2086
    bash "$frozen/scripts/vm/vm-exec.sh" "$g" --harness-sha "$sha" --timeout "$t" -- $a >"$here/p10-step-$i.log" 2>&1
    rc=$?
    dest=""
    lastf="$EVIDENCE_HOST_ROOT/.last-$id"
    if [ "$rc" -eq 0 ]; then
        if [ -f "$lastf" ] && [ "$(stat -c %Y "$lastf")" -ge "$start" ]; then
            dest=$(cat "$lastf")
            why=$(check_dir "$dest") || { echo "step $i cross-check: $why" >>"$here/p10-step-$i.log"; rc=97; }
        else
            echo "step $i cross-check: .last-$id was not rewritten during the step" >>"$here/p10-step-$i.log"
            rc=97
        fi
    fi
    printf '%s\t%s\t%s\t%s %s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$i" "$id" "$g" "$a" "$rc" "$head" "$dest" >>"$log"
    [ "$rc" -eq 0 ] || { echo "step $i ($g $a) exit $rc"; return "$rc"; }
done
echo "chain green"
}
main "$@"; exit

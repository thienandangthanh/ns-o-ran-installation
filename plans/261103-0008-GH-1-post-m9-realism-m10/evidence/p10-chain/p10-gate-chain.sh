#!/usr/bin/env bash
# P10 VM gate chain driver (the P09 driver with a per-commit step list). D-R3-1: M2-M7 (M5 builds the agent image
# with its codec byte-equality probe; M5-M7 after every agent change), then I0, I2 and the live e2i interop gate.
#   p10-gate-chain.sh HARNESS_SHA [FIRST_STEP_INDEX] [LAST_STEP_INDEX]   run the chain at one harness SHA, stop at the
#                                                                       first red step
#   P10_SKIP_STEPS=8,... p10-gate-chain.sh ...           skip the listed step indices inside the range (e.g. the UB
#                                                       fix's chain: 0-11 without e2i)
#   step 12 (n4, --part determinism) is the N4 two-build determinism check, run alone after a green chain
#   step 14 (n4, --part v3) judges the en-gNB PDCP SDU volume counters on a uloff and a ulon free run, no reference
#   step 15 (p12) the KPM reporting period gate, run last; the driver stops before it unless /home has >= 34 GiB free
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
# The tsv and the step logs go to a fresh directory per attempt (P10_CHAIN_LOG_DIR): the tsv is appended and the
# step logs are overwritten, so a reused directory would mix attempts.
here=${P10_CHAIN_LOG_DIR:-}
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

# preflight_asn1_indep <tag>: the host tarball checks, then the VM's copy checks (copied first when needed)
preflight_asn1_indep() {
    local tag="$1" src="${ASN1_INDEP_DIR:-$repo/tools/asn1-indep/dist}" vmcheck
    # shellcheck source=/dev/null
    source "$frozen/scripts/vm/vm-common.sh" || return 1
    vmcheck="cd ~/asn1-indep && grep -q '  asn1-indep-$tag.tar\$' SHA256SUMS && sha256sum -c SHA256SUMS"
    echo "host: $src"
    grep -q "  asn1-indep-$tag.tar\$" "$src/SHA256SUMS" || { echo "host SHA256SUMS does not name asn1-indep-$tag.tar"; return 1; }
    (cd "$src" && sha256sum -c SHA256SUMS) || return 1
    if ssh -n "${SSH_OPTS[@]}" "$VM_SSH" "$vmcheck"; then
        echo "VM copy already present and checked"
        return 0
    fi
    echo "copying to $VM_SSH:asn1-indep/"
    ssh -n "${SSH_OPTS[@]}" "$VM_SSH" "mkdir -p ~/asn1-indep && rm -f ~/asn1-indep/asn1-indep-*.tar ~/asn1-indep/SHA256SUMS" || return 1
    scp -q "${SSH_OPTS[@]}" "$src/SHA256SUMS" "$src/asn1-indep-$tag.tar" "$VM_SSH:asn1-indep/" || return 1
    ssh -n "${SSH_OPTS[@]}" "$VM_SSH" "$vmcheck"
}

if [ "${1:-}" = --check-dir ]; then
    check_dir "$2" && echo "run dir ok: $2"
    return
fi

[ -n "$here" ] || { echo "set P10_CHAIN_LOG_DIR to a fresh directory"; return 2; }
mkdir -p "$here" || return 2
[ -e "$log" ] && { echo "$log exists: use a fresh P10_CHAIN_LOG_DIR per attempt"; return 2; }
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
  "r2|gate-r2-ts-stub-qp.sh|7200|--mode single"
  "r3p|gate-r3p-ts-predictor.sh|7200|--mode single"
  "s10|gate-s10-scale.sh|5400|"
  "n4|gate-n4-ul-metric.sh|3600|--part determinism"
  "n4|gate-n4-ul-metric.sh|3600|--part identity"
  "n4|gate-n4-ul-metric.sh|3600|--part v3"
  "p12|gate-p12-kpm-period.sh|3600|"
)
cd "$frozen" || return 2
# asn1-indep pre-flight. The gates whose KPM subscription and indication checks decode the wire with the asn1-indep
# image (m6, m7, p12, e2i, r0, r1, r2, r3p, s10) need ~/asn1-indep/asn1-indep-<tag>.tar and SHA256SUMS in the VM
# (copied by the host), and a VM revert loses them. The tag is the frozen checkout's tools/asn1-indep/image-tag.sh;
# a step's --image-tag (e2i) must equal it, else exit 2. Before the first step: check the host tarball, copy it when
# the VM's copy is missing or does not check, and check it in the VM; exit 2 before any step (and before any tsv
# line) when that fails. Uses vm-exec's SSH route (vm-common.sh).
skip=",${P10_SKIP_STEPS:-},"
tag=""
src_tag=$(bash "$frozen/tools/asn1-indep/image-tag.sh") || { echo "image-tag.sh failed in $frozen"; return 2; }
for i in "${!steps[@]}"; do
    [ "$i" -lt "$first" ] || [ "$i" -gt "$last" ] && continue
    [[ $skip == *",$i,"* ]] && continue
    IFS='|' read -r id _ _ a <<<"${steps[$i]}"
    case "$id" in m6|m7|p12|e2i|r0|r1|r2|r3p|s10) tag=$src_tag ;; esac
    if [[ $a =~ --image-tag[[:space:]]+([0-9a-f]+) ]] && [ "${BASH_REMATCH[1]}" != "$src_tag" ]; then
        echo "step $i passes --image-tag ${BASH_REMATCH[1]}, the frozen checkout's asn1-indep tag is $src_tag"
        return 2
    fi
done
if [ -n "$tag" ]; then
    preflight_asn1_indep "$tag" >"$here/preflight-asn1-indep.txt" 2>&1 ||
        { echo "asn1-indep pre-flight failed for tag $tag: see $here/preflight-asn1-indep.txt"; return 2; }
    echo "asn1-indep pre-flight ok (tag $tag)"
fi
[ "${P10_PREFLIGHT_ONLY:-0}" = 1 ] && { echo "pre-flight only: no step run"; return 0; }
for i in "${!steps[@]}"; do
    [ "$i" -lt "$first" ] && continue
    [ "$i" -gt "$last" ] && break
    [[ $skip == *",$i,"* ]] && { echo "step $i skipped (P10_SKIP_STEPS)"; continue; }
    IFS='|' read -r id g t a <<<"${steps[$i]}"
    if [ "$id" = p12 ]; then
        # the p12 gate reinstalls kpimon three times: it starts only with >= 34 GiB free on the host's /home
        free=$(df -BG --output=avail /home | tail -1 | tr -dc '0-9')
        [ "${free:-0}" -ge 34 ] || { echo "step $i (p12): /home has ${free:-?} GiB free, want >= 34"; return 2; }
        echo "step $i (p12): /home has $free GiB free (>= 34)"
    fi
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

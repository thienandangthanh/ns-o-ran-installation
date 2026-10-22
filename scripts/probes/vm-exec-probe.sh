#!/usr/bin/env bash
# vm-exec-probe.sh <probe-script> [--harness-sha SHA] [--timeout S] [-- probe args...]
#
# Pre-M8 pacing probes: same mechanics as scripts/vm/vm-exec.sh (detached systemd unit on the VM, harness
# cloned at a pushed SHA, scrub, tar back), but for scripts/probes/<probe-script>. Evidence lands in
# plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/<probe>/<ts>/, where <probe> is the script name
# without "probe-" and ".sh". Probes start from a reverted f7-rerun-green; this script does not revert.

source "$(dirname "$0")/../vm/vm-common.sh"

HARNESS_URL="${HARNESS_URL:-https://github.com/thienandangthanh/ns-o-ran-installation.git}"
PROBE_EVIDENCE_ROOT="$REPO_ROOT/plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence"
script="${1:-}"; shift $(($# > 0))
[ -n "$script" ] || die "usage: vm-exec-probe.sh <probe-script> [--harness-sha SHA] [--timeout S] [-- args]"
harness_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
timeout_s=5400
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --harness-sha) harness_sha="$2"; shift 2 ;;
        --timeout) timeout_s="$2"; shift 2 ;;
        --) shift; args=("$@"); break ;;
        *) die "unknown arg $1" ;;
    esac
done
[ -f "$REPO_ROOT/scripts/probes/$script" ] || die "no probe script $script"
probe=$(basename "$script" .sh); probe="${probe#probe-}"
git -C "$REPO_ROOT" fetch -q origin 2>/dev/null || true
git -C "$REPO_ROOT" branch -r --contains "$harness_sha" 2>/dev/null | grep . >/dev/null ||
    die "harness $harness_sha is not on any origin branch; push it first"

ts=$(date -u +%Y%m%dT%H%M%SZ)
ev="/home/uc/evidence/probes/$probe/$ts"
unit="probe-$probe-$ts"
hlog "probe $probe harness ${harness_sha:0:10} -> unit $unit"

vm_ssh bash -s -- "$HARNESS_URL" "$harness_sha" <<'BOOT' || die "VM bootstrap failed"
set -euo pipefail
url="$1"; sha="$2"
[ -d ~/harness/.git ] || GIT_TERMINAL_PROMPT=0 git clone -q "$url" ~/harness
GIT_TERMINAL_PROMPT=0 git -C ~/harness fetch -q origin
git -C ~/harness checkout -q --detach "$sha"
test "$(git -C ~/harness rev-parse HEAD)" = "$sha"
BOOT

qargs=""; [ ${#args[@]} -eq 0 ] || printf -v qargs '%q ' "${args[@]}"
vm_ssh "mkdir -p $ev && sudo systemd-run --quiet --unit=$unit --uid=uc --gid=uc \
    --working-directory=/home/uc --setenv=HOME=/home/uc \
    --setenv=HARNESS_DIR=/home/uc/harness --setenv=HARNESS_SHA=$harness_sha \
    --setenv=GATE_TS=$ts --setenv=EVIDENCE_DIR=$ev \
    bash -c 'bash /home/uc/harness/scripts/probes/$script $qargs >$ev/launch.log 2>&1 </dev/null; echo \$? >$ev/exit_code'" ||
    die "could not start unit $unit"

deadline=$(($(date +%s) + timeout_s)); misses=0
while :; do
    if code=$(vm_ssh "cat $ev/exit_code 2>/dev/null" 2>/dev/null) && [ -n "$code" ]; then break; fi
    vm_ssh true 2>/dev/null && misses=0 || misses=$((misses + 1))
    [ "$misses" -lt 40 ] || die "VM unreachable for ~20 min during $unit"
    if [ "$(date +%s)" -ge "$deadline" ]; then
        hlog "timeout ${timeout_s}s: stopping $unit"
        vm_ssh "sudo systemctl stop $unit; echo 124 >$ev/exit_code" || true
        code=124; break
    fi
    sleep 30
done
hlog "probe $probe exit $code"

vm_ssh "bash /home/uc/harness/scripts/gates/scrub-evidence.sh $ev; \
    cd $ev && find . -name '*.pcap*' -type f -exec sha256sum {} + >pcap-sha256.txt 2>/dev/null; true"
dest="$PROBE_EVIDENCE_ROOT/$probe/$ts"
mkdir -p "$dest"
vm_ssh "tar -C $ev -cf - ." | tar -C "$dest" -xf - || die "evidence copy failed"
hlog "evidence -> $dest"
[ -f "$dest/verdict.json" ] && python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); print("verdict", v["gate"], "PASS" if v["pass"] else "FAIL", v["failed"])' "$dest/verdict.json"
echo "$dest" >"$PROBE_EVIDENCE_ROOT/.last-$probe"
exit "$code"

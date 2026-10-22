#!/usr/bin/env bash
# vm-exec.sh <gate-script> [--harness-sha SHA] [--timeout S] [-- gate args...]
#
# Runs scripts/gates/<gate-script> on the VM as a detached systemd unit, so an
# ssh drop never kills a gate. Polls for its exit code, scrubs the evidence on
# the VM, and copies it to $EVIDENCE_HOST_ROOT/<gate>/<ts>/. Exit status is the
# gate's verdict (0 = pass).
#
# The VM clones the harness anonymously from GitHub at HARNESS_SHA, which must
# already be pushed (default: HEAD of this worktree).

source "$(dirname "$0")/vm-common.sh"

HARNESS_URL="${HARNESS_URL:-https://github.com/thienandangthanh/ns-o-ran-installation.git}"
script="${1:-}"; shift $(($# > 0))
[ -n "$script" ] || die "usage: vm-exec.sh <gate-script> [--harness-sha SHA] [--timeout S] [-- args]"
harness_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
timeout_s=3600
gate_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --harness-sha) harness_sha="$2"; shift 2 ;;
        --timeout) timeout_s="$2"; shift 2 ;;
        --) shift; gate_args=("$@"); break ;;
        *) die "unknown arg $1" ;;
    esac
done
[ -f "$REPO_ROOT/scripts/gates/$script" ] || die "no gate script $script"
gate=$(gate_id "$script")
git -C "$REPO_ROOT" fetch -q origin 2>/dev/null || true
git -C "$REPO_ROOT" branch -r --contains "$harness_sha" 2>/dev/null | grep . >/dev/null ||
    die "harness $harness_sha is not on any origin branch; push it first"

ts=$(date -u +%Y%m%dT%H%M%SZ)
ev="/home/uc/evidence/$gate/$ts"
unit="gate-$gate-$ts"
hlog "gate $gate ($script) harness ${harness_sha:0:10} -> unit $unit"

# Bootstrap: git, then the harness clone at the exact SHA (no credentials).
vm_ssh bash -s -- "$HARNESS_URL" "$harness_sha" <<'BOOT' || die "VM bootstrap failed"
set -euo pipefail
url="$1"; sha="$2"
if ! command -v git >/dev/null; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git >/dev/null
fi
[ -d ~/harness/.git ] || GIT_TERMINAL_PROMPT=0 git clone -q "$url" ~/harness
GIT_TERMINAL_PROMPT=0 git -C ~/harness fetch -q origin
git -C ~/harness checkout -q --detach "$sha"
test "$(git -C ~/harness rev-parse HEAD)" = "$sha"
BOOT

# Launch detached. The wrapper writes exit_code last; it is the completion flag.
qargs=""; [ ${#gate_args[@]} -eq 0 ] || printf -v qargs '%q ' "${gate_args[@]}"
vm_ssh "mkdir -p $ev && sudo systemd-run --quiet --unit=$unit --uid=uc --gid=uc \
    --working-directory=/home/uc --setenv=HOME=/home/uc \
    --setenv=HARNESS_DIR=/home/uc/harness --setenv=HARNESS_SHA=$harness_sha \
    --setenv=GATE_TS=$ts --setenv=EVIDENCE_DIR=$ev \
    bash -c 'bash /home/uc/harness/scripts/gates/$script $qargs >$ev/launch.log 2>&1 </dev/null; echo \$? >$ev/exit_code'" ||
    die "could not start unit $unit"

# Poll; tolerate ssh drops.
deadline=$(($(date +%s) + timeout_s)); misses=0
while :; do
    if code=$(vm_ssh "cat $ev/exit_code 2>/dev/null" 2>/dev/null) && [ -n "$code" ]; then
        break
    fi
    vm_ssh true 2>/dev/null && misses=0 || misses=$((misses + 1))
    [ "$misses" -lt 40 ] || die "VM unreachable for ~20 min during $unit"
    if [ "$(date +%s)" -ge "$deadline" ]; then
        hlog "timeout ${timeout_s}s: stopping $unit"
        vm_ssh "sudo systemctl stop $unit; echo 124 >$ev/exit_code" || true
        code=124; break
    fi
    sleep 30
done
hlog "gate $gate exit $code"

# Scrub on the VM, then copy back; pcaps get a sha256 manifest (they stay out of git).
vm_ssh "bash /home/uc/harness/scripts/gates/scrub-evidence.sh $ev; \
    cd $ev && find . -name '*.pcap*' -type f -exec sha256sum {} + >pcap-sha256.txt 2>/dev/null; true"
dest="$EVIDENCE_HOST_ROOT/$gate/$ts"
mkdir -p "$dest"
# fresh-install has no rsync; tar over ssh needs nothing extra.
vm_ssh "tar -C $ev -cf - ." | tar -C "$dest" -xf - || die "evidence copy failed"
hlog "evidence -> $dest"
[ -f "$dest/verdict.json" ] && python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); print("verdict", v["gate"], "PASS" if v["pass"] else "FAIL", v["failed"])' "$dest/verdict.json"
echo "$dest" >"$EVIDENCE_HOST_ROOT/.last-$gate"
exit "$code"

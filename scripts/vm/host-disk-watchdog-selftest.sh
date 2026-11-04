#!/usr/bin/env bash
# host-disk-watchdog-selftest.sh: host self-test of the /home floor watchdog that vm-exec.sh runs around every gate
# (run by lint.sh). `ssh` and `virsh` are fake binaries first on PATH and the domain and host names are fake, so the
# real VM is never reached.
#   (1) --once with a threshold above the current free space trips: watchdog-tripped.json is written, the gate units
#       are stopped and the VM shut down (through the fakes), the runner gets TERM, and the watchdog exits 1;
#   (2) --once with a threshold of 1 GiB does not trip: exit 0, no trip record, the minimum free space is recorded.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ssh" <<EOF
#!/bin/sh
echo "ssh \$*" >>"$tmp/calls"
exit 0
EOF
cat >"$tmp/bin/virsh" <<EOF
#!/bin/sh
echo "virsh \$*" >>"$tmp/calls"
case "\$*" in
    *domstate*) if [ -e "$tmp/down" ]; then echo "shut off"; else echo running; fi ;;
    *shutdown*) touch "$tmp/down" ;;
esac
exit 0
EOF
chmod +x "$tmp/bin/ssh" "$tmp/bin/virsh"
export PATH="$tmp/bin:$PATH" VM_DOMAIN=selftest-no-such-domain VM_SSH=selftest.invalid CANCEL_TIMEOUT_S=2
fail=0
bad() { echo "FAIL: $*"; fail=1; }
free=$(df -BG --output=avail /home | tail -1 | tr -dc '0-9')

# (1) trip
bash -c 'trap "echo termed >\"$1\"; exit 125" TERM; sleep 60 & wait' _ "$tmp/runner-termed" & runner=$!
bash "$here/host-disk-watchdog.sh" --once --min-gb $((free + 1)) --out "$tmp/wd1" --runner-pid "$runner" >/dev/null 2>&1
rc=$?
wait "$runner"; rrc=$?
[ "$rc" -eq 1 ] || bad "a trip exited $rc, want 1"
[ -s "$tmp/wd1/watchdog-tripped.json" ] || bad "no watchdog-tripped.json"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["thresholdGb"] == int(sys.argv[2]) else 1)' \
    "$tmp/wd1/watchdog-tripped.json" $((free + 1)) || bad "the trip record names the wrong threshold"
grep -q "systemctl stop 'gate-\*'" "$tmp/calls" || bad "the gate units were not stopped"
grep -q 'virsh .*shutdown selftest-no-such-domain' "$tmp/calls" || bad "the VM was not shut down"
grep -q 'destroy' "$tmp/calls" && bad "the VM was forced off"
[ "$(cat "$tmp/runner-termed" 2>/dev/null)" = termed ] && [ "$rrc" -eq 125 ] || bad "the runner got no TERM (exit $rrc)"

# (2) no trip
bash "$here/host-disk-watchdog.sh" --once --min-gb 1 --out "$tmp/wd2" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || bad "no trip exited $rc, want 0"
[ -e "$tmp/wd2/watchdog-tripped.json" ] && bad "a trip record without a trip"
[ -s "$tmp/wd2/min-host-free-gb.txt" ] || bad "no minimum free space recorded"

[ "$fail" -eq 0 ] && echo "host-disk-watchdog self-test: ok"
exit "$fail"

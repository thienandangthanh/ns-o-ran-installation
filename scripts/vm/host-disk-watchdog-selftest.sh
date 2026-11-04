#!/usr/bin/env bash
# host-disk-watchdog-selftest.sh: host self-test of the /home floor watchdog that vm-exec.sh runs around every gate
# (run by lint.sh). `ssh` and `virsh` are fake binaries first on PATH and the domain and host names are fake, so the
# real VM is never reached.
#   (1) --once with a threshold above the current free space trips: watchdog-tripped.json is written, the gate units
#       are stopped and the VM shut down (through the fakes), the runner gets TERM, and the watchdog exits 1;
#   (2) --once with a threshold of 1 GiB does not trip: exit 0, no trip record, the minimum free space is recorded;
#   (3) a runner that finishes (vm-common.sh wd_finish) while a trip is under way (slow fake ssh) fails with 125, and
#       the trip completes: its record is written and the watchdog is gone;
#   (4) a runner that finishes without a trip: wd_finish returns 0 within a few seconds and the watchdog is gone;
#   (5) a runner that dies (vm-common.sh die) during a latched trip still exits 125 through wd_on_exit, and the
#       trip completes and is recorded with 1;
#   (6) a hung virsh during a trip: wd_finish's bound fires, the finish fails (125) and the watchdog is gone;
#   (7) an unwritable stop request: the finish fails (125) promptly and the watchdog is gone.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ssh" <<EOF
#!/bin/sh
echo "ssh \$*" >>"$tmp/calls"
[ -z "\${SELFTEST_SSH_DELAY:-}" ] || sleep "\$SELFTEST_SSH_DELAY"
exit 0
EOF
cat >"$tmp/bin/virsh" <<EOF
#!/bin/sh
echo "virsh \$*" >>"$tmp/calls"
case "\$*" in
    *domstate*) [ -z "\${SELFTEST_VIRSH_HANG:-}" ] || sleep 1000
                if [ -e "$tmp/down" ]; then echo "shut off"; else echo running; fi ;;
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

# finish <threshold GiB> <dir>: a runner like vm-exec.sh: watchdog in the background, wd_finish 1.5 s later
finish() {
    bash -c '
        source "$1/vm-common.sh"
        trap "exit 125" TERM
        bash "$1/host-disk-watchdog.sh" --min-gb "$2" --interval 1 --out "$3" --runner-pid $$ >/dev/null 2>&1 &
        wd=$!
        echo "$wd" >"$3.pid"
        sleep 1.5
        [ "${4:-}" != ro ] || chmod 555 "$3"
        if wd_finish "$3" "$wd"; then exit 0; else exit 125; fi' _ "$here" "$1" "$2" "${3:-}"
}
# (3) a trip under way when the runner finishes
rm -f "$tmp/down"
SELFTEST_SSH_DELAY=2 finish $((free + 1)) "$tmp/wd3"
rc=$?
[ "$rc" -eq 125 ] || bad "a runner finishing during a trip exited $rc, want 125"
[ -s "$tmp/wd3/watchdog-tripped.json" ] || bad "the trip under way did not complete (no watchdog-tripped.json)"
kill -0 "$(cat "$tmp/wd3.pid")" 2>/dev/null && bad "the tripped watchdog is still running"
# (4) a clean finish
start=$(date +%s)
finish 1 "$tmp/wd4"
rc=$?
[ "$rc" -eq 0 ] || bad "a clean finish exited $rc, want 0"
[ $(($(date +%s) - start)) -lt 10 ] || bad "a clean finish took $(($(date +%s) - start)) s"
[ -e "$tmp/wd4/watchdog-tripping" ] && bad "a clean finish left a trip latch"
kill -0 "$(cat "$tmp/wd4.pid")" 2>/dev/null && bad "the watchdog outlived a clean finish"

# (5) a die during a latched trip
rm -f "$tmp/down"
SELFTEST_SSH_DELAY=2 bash -c '
    source "$1/vm-common.sh"
    out="$3"; rec() { echo "$1" >"$out.rec"; }
    bash "$1/host-disk-watchdog.sh" --min-gb "$2" --interval 1 --out "$3" --runner-pid $$ >/dev/null 2>&1 &
    wd=$!
    echo "$wd" >"$3.pid"
    trap "wd_on_exit \"$3\" $wd rec" EXIT
    trap "WD_DONE=1; rec 1; exit 125" TERM
    sleep 1.5
    die "evidence copy failed"' _ "$here" $((free + 1)) "$tmp/wd5" 2>/dev/null
rc=$?
[ "$rc" -eq 125 ] || bad "a die during a latched trip exited $rc, want 125"
[ "$(cat "$tmp/wd5.rec" 2>/dev/null)" = 1 ] || bad "a die during a latched trip recorded no trip"
[ -s "$tmp/wd5/watchdog-tripped.json" ] || bad "the trip under a die path did not complete"
kill -0 "$(cat "$tmp/wd5.pid")" 2>/dev/null && bad "the watchdog outlived a die during a trip"
# (6) a hung virsh during a trip
rm -f "$tmp/down"
start=$(date +%s)
SELFTEST_VIRSH_HANG=1 WD_FINISH_TIMEOUT_S=3 finish $((free + 1)) "$tmp/wd6" 2>/dev/null
rc=$?
[ "$rc" -eq 125 ] || bad "a finish during a hung trip exited $rc, want 125"
[ $(($(date +%s) - start)) -lt 20 ] || bad "a hung trip held the finish $(($(date +%s) - start)) s"
kill -0 "$(cat "$tmp/wd6.pid")" 2>/dev/null && bad "the hung watchdog was not stopped"
# (7) an unwritable stop request
start=$(date +%s)
finish 1 "$tmp/wd7" ro 2>/dev/null
rc=$?
chmod 755 "$tmp/wd7"
[ "$rc" -eq 125 ] || bad "a finish without a stop request exited $rc, want 125"
[ $(($(date +%s) - start)) -lt 10 ] || bad "an unwritable stop request held the finish $(($(date +%s) - start)) s"
kill -0 "$(cat "$tmp/wd7.pid")" 2>/dev/null && bad "the watchdog outlived an unwritable stop request"

[ "$fail" -eq 0 ] && echo "host-disk-watchdog self-test: ok"
exit "$fail"

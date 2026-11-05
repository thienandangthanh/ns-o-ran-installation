#!/usr/bin/env bash
# host-disk-watchdog-selftest.sh: host self-test of the /home floor watchdog that vm-exec.sh runs around every gate
# (run by lint.sh). `ssh` and `virsh` are fake binaries first on PATH and the domain and host names are fake, so the
# real VM is never reached.
#   (1) --once with a threshold above the current free space trips: watchdog-tripped.json is written, the gate units
#       are stopped and the VM shut down (through the fakes), the runner gets TERM, and the watchdog exits 1;
#   (2) --once with a threshold of 1 GiB does not trip: exit 0, no trip record, the minimum free space is recorded;
#   (3) a runner that finishes (vm-common.sh wd_end) while a trip is under way (slow fake ssh) fails with 125 and
#       records 1, and the trip completes: its record is written and the watchdog is gone;
#   (4) a runner that finishes without a trip: wd_end records 0 within a few seconds and the watchdog is gone;
#   (5) a runner that dies (vm-common.sh die) during a latched trip still exits 125 through wd_on_exit, and the
#       trip completes and is recorded with 1;
#   (6) a hung virsh during a trip: wd_finish's bound fires, the finish fails (125, records 1) and the watchdog is
#       gone;
#   (7) an unwritable stop request: the finish fails (125, records 0) promptly and the watchdog is gone;
#   (8) an outside TERM while the watchdog monitors: exit 143, nothing recorded as a trip, the watchdog is gone;
#   (9) an outside TERM during a trip: exit 125 and 1 recorded only after the trip record is complete;
#  (10) a trip whose TERM arrives before wd_start returns (a slow session check): exit 125 with 1 recorded.
#  (11) a TERM between the watchdog's launch and WD_PID=$! (injected by a DEBUG trap) is held: exit 143 and the
#       watchdog's session is empty;
#  (12) a TERM during the normal end's record (a slow record function): the record (0) is complete, then exit 143;
#  (13) the same during the record of a trip the end found (hung virsh, the finish bound fires): exit 125, 1 recorded;
#  (14) after the normal end, no pkill -s is issued (the one sweep happens when the watchdog is seen gone) and
#       WD_PID is cleared.
# Every runner arms its traps with vm-common.sh wd_arm before wd_start, as vm-exec.sh does. In (3)-(10) the watchdog
# runs as a session leader (wd_start), and no process of its session survives the runner.
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

# gone <case>: no process of that case's watchdog session (its ssh, virsh, timeout and sleep children) is left
gone() { local p; p=$(pgrep -s "$(cat "$tmp/wd$1.pid")" | tr '\n' ' '); [ -z "$p" ] || bad "case $1 left processes of the watchdog session: $p"; }
# RUNNER: the head of a runner like vm-exec.sh ($1 here, $2 threshold, $3 watchdog dir): the record function writes
# DIR.rec, the traps are armed, then the watchdog starts and its pid goes to DIR.pid
RUNNER='source "$1/vm-common.sh"
out="$3"; rec() { echo "$1" >"$out.rec"; }
wd_arm "$3" rec
wd_start "$3" "$2" 1 $$ /dev/null || exit 3
echo "$WD_PID" >"$3.pid"
'
# finish <threshold GiB> <dir> [ro]: a runner that ends normally (wd_end) 1.5 s after the watchdog started
finish() {
    bash -c "$RUNNER"'
        sleep 1.5
        [ "${4:-}" != ro ] || chmod 555 "$3"
        wd_end "$3" rec
        exit 0' _ "$here" "$1" "$2" "${3:-}" 2>/dev/null
}
rec_is() { [ "$(cat "$tmp/wd$1.rec" 2>/dev/null)" = "$2" ] || bad "case $1 recorded '$(cat "$tmp/wd$1.rec" 2>/dev/null)', want '$2'"; }
# (3) a trip under way when the runner finishes
rm -f "$tmp/down"
SELFTEST_SSH_DELAY=2 finish $((free + 1)) "$tmp/wd3"
rc=$?
[ "$rc" -eq 125 ] || bad "a runner finishing during a trip exited $rc, want 125"
[ -s "$tmp/wd3/watchdog-tripped.json" ] || bad "the trip under way did not complete (no watchdog-tripped.json)"
kill -0 "$(cat "$tmp/wd3.pid")" 2>/dev/null && bad "the tripped watchdog is still running"
rec_is 3 1
gone 3
# (4) a clean finish
start=$(date +%s)
finish 1 "$tmp/wd4"
rc=$?
[ "$rc" -eq 0 ] || bad "a clean finish exited $rc, want 0"
[ $(($(date +%s) - start)) -lt 10 ] || bad "a clean finish took $(($(date +%s) - start)) s"
[ -e "$tmp/wd4/watchdog-tripping" ] && bad "a clean finish left a trip latch"
kill -0 "$(cat "$tmp/wd4.pid")" 2>/dev/null && bad "the watchdog outlived a clean finish"
rec_is 4 0
gone 4

# (5) a die during a latched trip
rm -f "$tmp/down"
SELFTEST_SSH_DELAY=2 bash -c "$RUNNER"'
    sleep 1.5
    die "evidence copy failed"' _ "$here" $((free + 1)) "$tmp/wd5" 2>/dev/null
rc=$?
[ "$rc" -eq 125 ] || bad "a die during a latched trip exited $rc, want 125"
rec_is 5 1
[ -s "$tmp/wd5/watchdog-tripped.json" ] || bad "the trip under a die path did not complete"
kill -0 "$(cat "$tmp/wd5.pid")" 2>/dev/null && bad "the watchdog outlived a die during a trip"
gone 5
# (6) a hung virsh during a trip
rm -f "$tmp/down"
start=$(date +%s)
SELFTEST_VIRSH_HANG=1 WD_FINISH_TIMEOUT_S=3 finish $((free + 1)) "$tmp/wd6" 2>/dev/null
rc=$?
[ "$rc" -eq 125 ] || bad "a finish during a hung trip exited $rc, want 125"
[ $(($(date +%s) - start)) -lt 20 ] || bad "a hung trip held the finish $(($(date +%s) - start)) s"
kill -0 "$(cat "$tmp/wd6.pid")" 2>/dev/null && bad "the hung watchdog was not stopped"
rec_is 6 1
gone 6
# (7) an unwritable stop request
start=$(date +%s)
finish 1 "$tmp/wd7" ro 2>/dev/null
rc=$?
chmod 755 "$tmp/wd7"
[ "$rc" -eq 125 ] || bad "a finish without a stop request exited $rc, want 125"
[ $(($(date +%s) - start)) -lt 10 ] || bad "an unwritable stop request held the finish $(($(date +%s) - start)) s"
kill -0 "$(cat "$tmp/wd7.pid")" 2>/dev/null && bad "the watchdog outlived an unwritable stop request"
rec_is 7 0
gone 7

# term <case>: TERM from outside to the runner of that case once its watchdog has started
term() { local i; for ((i = 0; i < 50; i++)); do [ -s "$tmp/wd$1.pid" ] && break; sleep 0.1; done; sleep 1; kill -TERM "$2"; }
# (8) an outside TERM while the watchdog monitors (the runner's foreground sleep, like vm-exec.sh's poll, delays it)
bash -c "$RUNNER"'
    sleep 4
    exit 0' _ "$here" 1 "$tmp/wd8" 2>/dev/null & runner=$!
term 8 "$runner"
wait "$runner"; rc=$?
[ "$rc" -eq 143 ] || bad "an outside TERM while monitoring exited $rc, want 143"
[ -e "$tmp/wd8.rec" ] && bad "an outside TERM without a trip was recorded ($(cat "$tmp/wd8.rec"))"
kill -0 "$(cat "$tmp/wd8.pid")" 2>/dev/null && bad "the watchdog outlived an outside TERM"
gone 8
# (9) an outside TERM during a trip (slow fake ssh): the trip record is complete when the runner has exited
rm -f "$tmp/down"
SELFTEST_SSH_DELAY=2 bash -c "$RUNNER"'
    sleep 4
    exit 0' _ "$here" $((free + 1)) "$tmp/wd9" 2>/dev/null & runner=$!
term 9 "$runner"
wait "$runner"; rc=$?
[ "$rc" -eq 125 ] || bad "an outside TERM during a trip exited $rc, want 125"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "unitsActiveAfterStop" in d else 1)' \
    "$tmp/wd9/watchdog-tripped.json" 2>/dev/null || bad "the runner exited before the trip record was complete"
rec_is 9 1
kill -0 "$(cat "$tmp/wd9.pid")" 2>/dev/null && bad "the watchdog outlived an outside TERM during a trip"
gone 9
# (10) a trip that TERMs the runner while wd_start still checks the session: the check is made slow (a ps function
# that sleeps), the trip is immediate (fast fakes), and the runner never reaches the line after wd_start
rm -f "$tmp/down"
bash -c '
    source "$1/vm-common.sh"
    out="$3"; rec() { echo "$1" >"$out.rec"; }
    ps() { echo "$WD_PID" >"$out.pid"; sleep 3; command ps "$@"; }
    wd_arm "$3" rec
    wd_start "$3" "$2" 1 $$ /dev/null || exit 3
    : >"$out.started"
    sleep 4
    exit 0' _ "$here" $((free + 1)) "$tmp/wd10" 2>/dev/null
rc=$?
[ -e "$tmp/wd10.started" ] && bad "case 10's trip came after wd_start returned: the case did not test the start window"
[ "$rc" -eq 125 ] || bad "a trip before wd_start returned exited $rc, want 125"
rec_is 10 1
[ -s "$tmp/wd10/watchdog-tripped.json" ] || bad "the trip before wd_start returned did not complete"
gone 10

# (11) a TERM held across the launch
bash -c '
    source "$1/vm-common.sh"
    out="$3"; rec() { echo "$1" >"$out.rec"; }
    wd_arm "$3" rec
    set -T
    trap '\''[[ $BASH_COMMAND == "WD_PID=\$!" ]] && { echo $! >"$out.pid"; kill -TERM $$; }'\'' DEBUG
    wd_start "$3" "$2" 1 $$ /dev/null || exit 3
    trap - DEBUG
    : >"$out.started"
    exit 0' _ "$here" 1 "$tmp/wd11" 2>/dev/null
rc=$?
[ "$rc" -eq 143 ] || bad "a TERM held across the launch exited $rc, want 143"
[ -e "$tmp/wd11.started" ] && bad "a TERM held across the launch was never acted on"
[ -e "$tmp/wd11.rec" ] && bad "a TERM held across the launch was recorded ($(cat "$tmp/wd11.rec"))"
[ -s "$tmp/wd11.pid" ] || bad "case 11's DEBUG injection did not fire"
gone 11
# slow_end <case> [env...]: a runner whose record function marks DIR.recording, sleeps 2 s, then writes DIR.rec; the
# test TERMs it while it records
slow_end() {
    local c="$1" thr="$2"; shift 2
    env "$@" bash -c '
        source "$1/vm-common.sh"
        out="$3"; rec() { : >"$out.recording"; sleep 2; echo "$1" >"$out.rec"; }
        wd_arm "$3" rec
        wd_start "$3" "$2" 1 $$ /dev/null || exit 3
        echo "$WD_PID" >"$3.pid"
        sleep 1.5
        wd_end "$3" rec
        exit 0' _ "$here" "$thr" "$tmp/wd$c" 2>/dev/null & runner=$!
    for ((i = 0; i < 300; i++)); do [ -e "$tmp/wd$c.recording" ] && break; sleep 0.1; done
    kill -TERM "$runner"
    wait "$runner"
}
# (12) a TERM during a clean end's record
slow_end 12 1
rc=$?
[ "$rc" -eq 143 ] || bad "a TERM during the end record exited $rc, want 143"
rec_is 12 0
gone 12
# (13) a TERM during the record of a trip the end found
rm -f "$tmp/down"
slow_end 13 $((free + 1)) SELFTEST_VIRSH_HANG=1 WD_FINISH_TIMEOUT_S=3
rc=$?
[ "$rc" -eq 125 ] || bad "a TERM during a trip's end record exited $rc, want 125"
rec_is 13 1
gone 13
# (14) no session signal after the normal end has forgotten the pid
bash -c '
    source "$1/vm-common.sh"
    out="$3"; rec() { echo "$1" >"$out.rec"; }
    pkill() { echo "pkill $*" >>"$out.signals"; command pkill "$@"; }
    wd_arm "$3" rec
    wd_start "$3" "$2" 1 $$ /dev/null || exit 3
    echo "$WD_PID" >"$3.pid"
    sleep 1.5
    wd_end "$3" rec
    echo "end WD_PID=${WD_PID:-}" >>"$out.signals"
    exit 0' _ "$here" 1 "$tmp/wd14" 2>/dev/null
rc=$?
[ "$rc" -eq 0 ] || bad "case 14 exited $rc, want 0"
[ "$(tail -1 "$tmp/wd14.signals" 2>/dev/null)" = "end WD_PID=" ] ||
    bad "a session signal after the normal end, or WD_PID kept: $(tr '\n' ';' <"$tmp/wd14.signals" 2>/dev/null)"
[ "$(grep -c '^pkill .*-s' "$tmp/wd14.signals" 2>/dev/null)" = 1 ] || bad "case 14 swept the session $(grep -c '^pkill .*-s' "$tmp/wd14.signals" 2>/dev/null) times, want 1"
rec_is 14 0
gone 14

[ "$fail" -eq 0 ] && echo "host-disk-watchdog self-test: ok"
exit "$fail"

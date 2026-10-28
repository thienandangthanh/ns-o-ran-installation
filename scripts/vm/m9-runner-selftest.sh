#!/usr/bin/env bash
# m9-runner-selftest.sh: the M9 runner's second stop path without a VM. A dummy process stands for the VM-side
# gate unit and another for the runner; the heartbeat monitor runs at a 1 s interval with --stop-cmd killing the
# dummy unit. Cases: (1) the watchdog dies (one heartbeat, then none): watchdog-lost.json, the unit and the runner
# stopped within 2 polling periods + one check + slack (5 s); (2) the global wall deadline passes while the
# heartbeat is fresh: wall-deadline.json and both stopped; (3) a healthy watchdog: the monitor keeps running and
# records maxAgeS <= 2 periods; (4) a hung stop command is bounded; (5) write_verdict returns the judge's
# status; (6) supervised cancels and shuts the VM down once either
# monitor has exited; (7) a TERM to the runner alone stops the running step; (8) the shipped watchdog's heartbeat is
# never read torn by the monitor. Then the substitution 4 record validator and m9-verdict.py self-tests. Exit 0 when every case holds.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
tmp=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$tmp"' EXIT

dummy_runner() { bash -c 'trap "exit 0" TERM; while :; do sleep 0.2; done' >/dev/null 2>&1 & echo $!; }
alive() { kill -0 "$1" 2>/dev/null; }
wait_dead() { local t0=$SECONDS; while alive "$1" || alive "$2"; do [ $((SECONDS - t0)) -lt "$3" ] || return 1; sleep 0.2; done; }

# (1) the watchdog dies after one heartbeat
d="$tmp/lost"; mkdir -p "$d"; date +%s >"$d/heartbeat"
sleep 300 & unit=$!
runner=$(dummy_runner)
"$here/m9-heartbeat-monitor.sh" --runner-pid "$runner" --dir "$d" --interval 1 --deadline-epoch $(($(date +%s) + 600)) \
    --stop-cmd "kill $unit" >/dev/null 2>&1 &
if wait_dead "$unit" "$runner" 6 && [ -s "$d/watchdog-lost.json" ]; then echo "ok   watchdog loss stops the unit and the runner within the bound"
else echo "FAIL watchdog loss: unit alive $(alive $unit && echo yes || echo no), runner alive $(alive "$runner" && echo yes || echo no)"; rc=1; fi

# (2) the global wall deadline with a fresh heartbeat
d="$tmp/deadline"; mkdir -p "$d"
(while :; do date +%s >"$d/heartbeat"; sleep 0.5; done) & beat=$!
sleep 300 & unit=$!
runner=$(dummy_runner)
"$here/m9-heartbeat-monitor.sh" --runner-pid "$runner" --dir "$d" --interval 1 --deadline-epoch $(($(date +%s) + 2)) \
    --stop-cmd "kill $unit" >/dev/null 2>&1 &
if wait_dead "$unit" "$runner" 6 && [ -s "$d/wall-deadline.json" ] && [ ! -e "$d/watchdog-lost.json" ]; then
    echo "ok   the global wall deadline stops the unit and the runner"
else echo "FAIL wall deadline"; rc=1; fi
kill "$beat" 2>/dev/null

# (3) a healthy watchdog: nothing stops, the record shows the heartbeat fresh
d="$tmp/healthy"; mkdir -p "$d"
(while :; do date +%s >"$d/heartbeat"; sleep 0.5; done) & beat=$!
sleep 300 & unit=$!
runner=$(dummy_runner)
"$here/m9-heartbeat-monitor.sh" --runner-pid "$runner" --dir "$d" --interval 1 --deadline-epoch $(($(date +%s) + 600)) \
    --stop-cmd "kill $unit" >/dev/null 2>&1 & mon=$!
sleep 4
if alive "$unit" && alive "$runner" && alive "$mon" && python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1])); sys.exit(0 if a["checks"] >= 2 and a["maxAgeS"] <= 2 * a["intervalS"] else 1)' "$d/watchdog-alive.json"; then
    echo "ok   a healthy watchdog: no stop, heartbeat recorded fresh"
else echo "FAIL healthy watchdog"; rc=1; fi
kill "$mon" "$beat" "$unit" "$runner" 2>/dev/null

# (4) a stop command that never returns (a responsive sshd whose systemctl hangs) is bounded by CANCEL_TIMEOUT_S
d="$tmp/hung"; mkdir -p "$d"; date +%s >"$d/heartbeat"
sleep 300 & unit=$!
runner=$(dummy_runner)
CANCEL_TIMEOUT_S=2 "$here/m9-heartbeat-monitor.sh" --runner-pid "$runner" --dir "$d" --interval 1 \
    --deadline-epoch $(($(date +%s) + 600)) --stop-cmd "kill $unit; sleep 1000" >/dev/null 2>&1 &
if wait_dead "$unit" "$runner" 9; then echo "ok   a hung stop command is bounded and the runner still stops"
else echo "FAIL hung stop command: runner alive $(alive "$runner" && echo yes || echo no)"; rc=1; fi

# the runner's own functions, extracted from run-to-m9.sh so the fixtures test the shipped text
fn() { sed -n "/^$1() {/,/^}/p" "$here/../run-to-m9.sh"; }
# (5) write_verdict returns the judge's status: 0 on a healthy run with no failure markers, 1 with one
for want in 0 1; do
    d="$tmp/verdict$want"; wd="$d/wd"; run_dir="$d/run"; mkdir -p "$wd" "$run_dir"
    steps_file="$d/steps.tsv"; : >"$steps_file"
    for s in m0 r3p; do
        mkdir -p "$d/$s"
        printf '{"pass": true, "failed": [], "mode": "c1", "equalsReference": true, "substitution3Applied": true}' >"$d/$s/verdict.json"
        printf '%s\tpass\t%s\n' "$s" "$d/$s" >>"$steps_file"
    done
    echo 31 >"$wd/min-host-free-gb.txt"
    printf '{"intervalS": 30, "maxAgeS": 31, "checks": 9, "lastCheckEpoch": %s}' "$(date +%s)" >"$wd/watchdog-alive.json"
    [ "$want" = 1 ] && echo '{}' >"$wd/watchdog-lost.json"
    got=$(here="$here/.." top=r3p full=1 harness_sha=x prefix=n snapshots=1 sub4=none steps_file="$steps_file" \
        run_dir="$run_dir" wd="$wd" bash -c "ORDER=(m0 r3p); $(fn write_verdict); write_verdict >/dev/null 2>&1; echo \$?")
    if [ "$got" = "$want" ] && [ -s "$run_dir/verdict.json" ] && [ -e "$run_dir/min-host-free-gb.txt" ]; then
        echo "ok   write_verdict exits $want ($([ "$want" = 0 ] && echo healthy run || echo watchdog lost))"
    else echo "FAIL write_verdict: want $want, got $got"; rc=1; fi
done
# (6) supervised cancels as the monitor would (stop the step and the gate units, shut the VM down) when either
# monitor has exited; the dead PID is a reaped child, so it cannot belong to a live process
sleep 0 & dead=$!; wait "$dead"
for lost in watchdog monitor; do
    d="$tmp/supervised-$lost"; mkdir -p "$d"
    sleep 300 & live=$!
    if [ "$lost" = watchdog ]; then w=$dead; m=$live; else w=$live; m=$dead; fi
    got=$(wd="$d" wd_pid=$w mon_pid=$m bash -c "hlog() { :; }; vm_stop_gates() { touch $d/stopped; }; vm_shutdown() { touch $d/shutdown; }
        $(fn supervised); supervised sleep 300; echo \$?")
    if [ "$got" = 1 ] && [ -s "$d/monitor-lost.json" ] && [ -e "$d/stopped" ] && [ -e "$d/shutdown" ]; then
        echo "ok   supervised cancels and shuts the VM down when the $lost has exited"
    else echo "FAIL supervised ($lost exited): got $got, stopped $([ -e "$d/stopped" ] && echo yes || echo no), shutdown $([ -e "$d/shutdown" ] && echo yes || echo no)"; rc=1; fi
    kill "$live" 2>/dev/null
done
# (7) a TERM to the runner alone stops the running step (finish never orphans it)
d="$tmp/finish"; mkdir -p "$d"
sleep 300 & mons=$!   # stands for both live monitors (finish stops them)
bash -c "hlog() { :; }; vm_stop_gates() { touch $d/stopped; }; write_verdict() { :; }
    $(fn supervised); $(fn finish); trap 'finish 3' TERM; wd_pid=$mons; mon_pid=$mons
    supervised sleep 301; echo unreachable" >/dev/null 2>&1 &
r=$!
sleep 1.5
step=$(pgrep -f "^sleep 301$" -P "$r")
kill -TERM "$r"
t0=$SECONDS; while alive "$r" && [ $((SECONDS - t0)) -lt 8 ]; do sleep 0.2; done
if [ -n "$step" ] && ! alive "$r" && ! alive "$step" && [ -e "$d/stopped" ]; then
    echo "ok   a TERM to the runner stops the running step and the gate units"
else echo "FAIL finish on TERM: runner alive $(alive "$r" && echo yes || echo no), step ${step:-none} alive $([ -n "$step" ] && alive "$step" && echo yes || echo no)"; rc=1
    [ -n "$step" ] && kill "$step" 2>/dev/null; fi
kill "$mons" 2>/dev/null

# (8) a live watchdog's heartbeat is never read torn: the shipped watchdog in a tight loop, its date slowed so a
# truncate-then-write heartbeat would sit empty for 0.3 s of every ~0.6 s loop, against the monitor at 1 s
d="$tmp/torn"; mkdir -p "$d/bin"
printf '#!/bin/sh\nsleep 0.3\nexec %s "$@"\n' "$(command -v date)" >"$d/bin/date"; chmod +x "$d/bin/date"
VM_SSH=selftest.invalid VM_DOMAIN=selftest-absent PATH="$d/bin:$PATH" \
    "$here/host-disk-watchdog.sh" --interval 0 --min-gb 0 --out "$d" >/dev/null 2>&1 & wdog=$!
sleep 300 & unit=$!
runner=$(dummy_runner)
"$here/m9-heartbeat-monitor.sh" --runner-pid "$runner" --dir "$d" --interval 1 --deadline-epoch $(($(date +%s) + 600)) \
    --stop-cmd "kill $unit" >/dev/null 2>&1 & mon=$!
sleep 8
if alive "$unit" && alive "$runner" && alive "$mon" && [ ! -e "$d/watchdog-lost.json" ] &&
    python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1])); sys.exit(0 if a["checks"] >= 5 and a["maxAgeS"] <= 2 * a["intervalS"] else 1)' "$d/watchdog-alive.json"; then
    echo "ok   a live watchdog's heartbeat is never read torn"
else echo "FAIL torn heartbeat read: $(cat "$d/watchdog-lost.json" 2>/dev/null)"; rc=1; fi
kill "$wdog" "$mon" "$unit" "$runner" 2>/dev/null

python3 -I "$here/../gates/r3p-substitution4-validate.py" --self-test >/dev/null || { echo "FAIL substitution 4 record validator self-test"; rc=1; }
python3 -I "$here/../m9-verdict.py" --self-test >/dev/null || { echo "FAIL m9-verdict.py self-test"; rc=1; }
echo "m9 runner self-test: $([ "$rc" = 0 ] && echo ok || echo failed)"
exit "$rc"

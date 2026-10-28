#!/usr/bin/env bash
# m9-runner-selftest.sh: the M9 runner's second stop path without a VM. A dummy process stands for the VM-side
# gate unit and another for the runner; the heartbeat monitor runs at a 1 s interval with --stop-cmd killing the
# dummy unit. Cases: (1) the watchdog dies (one heartbeat, then none): watchdog-lost.json, the unit and the runner
# stopped within 2 polling periods + one check + slack (5 s); (2) the global wall deadline passes while the
# heartbeat is fresh: wall-deadline.json and both stopped; (3) a healthy watchdog: the monitor keeps running and
# records maxAgeS <= 2 periods. Then m9-verdict.py --self-test. Exit 0 when every case holds.
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

python3 -I "$here/../m9-verdict.py" --self-test >/dev/null || { echo "FAIL m9-verdict.py self-test"; rc=1; }
echo "m9 runner self-test: $([ "$rc" = 0 ] && echo ok || echo failed)"
exit "$rc"

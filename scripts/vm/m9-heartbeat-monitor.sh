#!/usr/bin/env bash
# m9-heartbeat-monitor.sh --runner-pid PID --dir DIR --interval S --deadline-epoch E [--stop-cmd CMD]
#
# The M9 runner's second stop path (amendment A1, Codex F08): every S seconds it reads the disk watchdog's
# heartbeat (DIR/heartbeat, epoch seconds) and keeps DIR/watchdog-alive.json {intervalS, maxAgeS, checks,
# lastCheckEpoch} current, so the verdict can require a check near the run's end.
# When the heartbeat is missing or older than 2 x S (the watchdog died), or the wall clock passes E (the global
# deadline), it writes DIR/watchdog-lost.json or DIR/wall-deadline.json and cancels the run as the watchdog's trip
# does: stops every VM-side gate unit over ssh (bounded by CANCEL_TIMEOUT_S), shuts the VM down gracefully, then
# TERMs the runner's children and the runner (its verdict then fails). --stop-cmd replaces the VM stop and shutdown
# (fixtures) under the same bound. Exit 1 after a
# cancel; it never exits on its own otherwise.

source "$(dirname "$0")/vm-common.sh"

runner_pid=""; dir=""; interval=60; deadline=""; stop_cmd=""
while [ $# -gt 0 ]; do
    case "$1" in
        --runner-pid) runner_pid="$2"; shift 2 ;;
        --dir) dir="$2"; shift 2 ;;
        --interval) interval="$2"; shift 2 ;;
        --deadline-epoch) deadline="$2"; shift 2 ;;
        --stop-cmd) stop_cmd="$2"; shift 2 ;;
        *) die "unknown arg $1" ;;
    esac
done
[ -n "$runner_pid" ] && [ -n "$dir" ] && [ -n "$deadline" ] || die "need --runner-pid, --dir and --deadline-epoch"

cancel() {
    local why="$1" file="$2"
    hlog "heartbeat monitor: $why: cancelling the M9 run"
    printf '{"utc": "%s", "reason": "%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$why" >"$dir/$file"
    if [ -n "$stop_cmd" ]; then
        timeout --kill-after=2 "$CANCEL_TIMEOUT_S" bash -c "$stop_cmd" || hlog "heartbeat monitor: the stop command failed or timed out"
    else
        vm_stop_gates || hlog "heartbeat monitor: stopping the VM gate units failed or exceeded ${CANCEL_TIMEOUT_S} s; shutting down anyway"
        vm_shutdown || hlog "heartbeat monitor: guest did not shut down within 240 s"
    fi
    local c
    for c in $(pgrep -P "$runner_pid"); do [ "$c" = $$ ] || kill -TERM "$c" 2>/dev/null; done
    kill -TERM "$runner_pid" 2>/dev/null
    exit 1
}

max_age=0; checks=0
while :; do
    sleep "$interval"
    now=$(date +%s)
    hb=$(cat "$dir/heartbeat" 2>/dev/null)
    [[ "$hb" =~ ^[0-9]+$ ]] || cancel "no watchdog heartbeat" watchdog-lost.json
    age=$((now - hb)); checks=$((checks + 1))
    [ "$age" -gt "$max_age" ] && max_age=$age
    printf '{"intervalS": %s, "maxAgeS": %s, "checks": %s, "lastCheckEpoch": %s}\n' "$interval" "$max_age" "$checks" "$now" \
        >"$dir/watchdog-alive.json"
    [ "$age" -le $((2 * interval)) ] || cancel "watchdog heartbeat ${age}s old (> 2 x ${interval}s)" watchdog-lost.json
    [ "$now" -le "$deadline" ] || cancel "global wall deadline passed" wall-deadline.json
done

#!/usr/bin/env bash
# host-disk-watchdog.sh [--once] [--min-gb N] [--interval S] [--out DIR] [--runner-pid PID]
#
# Polls host /home free space (df --output=avail -BG) every S seconds (default
# 60) and keeps the minimum seen in DIR/min-host-free-gb.txt. Below N GB
# (default 25 = the 20 GB floor plus a 5 GB margin) it trips:
#   1. writes DIR/watchdog-tripped.json (free, threshold, units stopped);
#   2. stops every VM-side gate unit (systemctl stop 'gate-*' over ssh);
#   3. shuts the VM down gracefully (never forced);
#   4. sends SIGTERM to the runner PID, which stops the chain;
# and exits 1. --once checks a single time: exit 0 above the threshold. Every
# poll writes DIR/heartbeat (epoch seconds) for the runner's heartbeat monitor.
# DIR defaults to $EVIDENCE_HOST_ROOT/watchdog.

source "$(dirname "$0")/vm-common.sh"

once=0; min_gb=25; interval=60; out=""; runner_pid=""
while [ $# -gt 0 ]; do
    case "$1" in
        --once) once=1; shift ;;
        --min-gb) min_gb="$2"; shift 2 ;;
        --interval) interval="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --runner-pid) runner_pid="$2"; shift 2 ;;
        *) die "unknown arg $1" ;;
    esac
done
out="${out:-$EVIDENCE_HOST_ROOT/watchdog}"
mkdir -p "$out"
min_file="$out/min-host-free-gb.txt"

trip() {
    local free="$1" before after
    hlog "watchdog: host /home free ${free}G < ${min_gb}G: stopping the chain"
    before=$(vm_ssh "systemctl list-units --plain --no-legend --state=active 'gate-*' | awk '{print \$1}'" 2>/dev/null | paste -sd, -)
    vm_ssh "sudo systemctl stop 'gate-*'" 2>/dev/null || true
    after=$(vm_ssh "systemctl list-units --plain --no-legend --state=active 'gate-*' | awk '{print \$1}'" 2>/dev/null | paste -sd, -)
    python3 - "$out/watchdog-tripped.json" "$free" "$min_gb" "$(cat "$min_file")" "$before" "$after" <<'PY'
import json, sys, time
path, free, thr, minfree, before, after = sys.argv[1:]
json.dump({"tripped_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "hostFreeGb": int(free), "thresholdGb": int(thr), "minHostFreeGb": int(minfree),
           "unitsActiveBefore": [u for u in before.split(",") if u],
           "unitsActiveAfterStop": [u for u in after.split(",") if u]},
          open(path, "w"), indent=2)
PY
    vm_shutdown || hlog "watchdog: guest did not shut down within 240 s"
    if [ -n "$runner_pid" ]; then
        # The runner's TERM trap runs only after its foreground child exits, so
        # stop that child (vm-exec.sh) first; this watchdog is a child too.
        local c
        for c in $(pgrep -P "$runner_pid"); do [ "$c" = $$ ] || kill -TERM "$c" 2>/dev/null; done
        kill -TERM "$runner_pid" 2>/dev/null
    fi
    exit 1
}

while :; do
    date +%s >"$out/heartbeat"   # read by m9-heartbeat-monitor.sh: a stale heartbeat means this watchdog died
    free=$(host_free_gb)
    if [ ! -s "$min_file" ] || [ "$free" -lt "$(cat "$min_file")" ]; then echo "$free" >"$min_file"; fi
    [ "$free" -ge "$min_gb" ] || trip "$free"
    [ "$once" = 1 ] && exit 0
    sleep "$interval"
done

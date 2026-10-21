#!/usr/bin/env bash
# measure-ns3-timing.sh <scenario-binary> <out-dir> [--repeats N] [--simtime S]
#
# Wall-clock cost of scenario-zero per simulated second, with the IPC emitter
# live against the null sink (emit cost included). Two configs at
# --indicationPeriodicity=0.1 and the default UE/traffic load:
#   single   --nMmWaveEnbNodes=1 --e2lteEnabled=false   (gNB 2, port 38472)
#   default  no node args                                (eNB 1 + gNB 2..5, ports 38471-38475)
# Per repeat: fresh null sink -> assert no stray scenario process / listener ->
# run the compiled binary DIRECTLY in its own process group (python
# time.monotonic() around the call, never `./ns3 run`) -> stop sink -> kill our
# PGID -> verify nothing is left. Repeats default 3; if stdev/mean > 10 % repeats
# are added one at a time up to 6.
# Output: <out-dir>/ns3-timing.json and ns3-timing.txt.
set -uo pipefail
export TZ=Asia/Seoul

# Scenario-zero option names (assumed; confirm against scratch/scenario-zero.cc).
E2_TRACE_OPT="--e2TraceDir"
E2_HOST_OPT="--e2AgentHost"
PERIOD=0.1
MAX_REPEATS=6
CV_LIMIT=0.10
RUN_TIMEOUT_S="${RUN_TIMEOUT_S:-900}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINK_PY="$HERE/../tools/ipc-null-sink/ipc-null-sink.py"

usage() { echo "usage: $0 <scenario-binary> <out-dir> [--repeats N] [--simtime S]" >&2; exit 2; }
[ $# -ge 2 ] || usage
BIN="$(readlink -f "$1")"; OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2
REPEATS=3; SIMTIME=10
while [ $# -gt 0 ]; do
    case "$1" in
        --repeats) REPEATS="${2:?}"; shift 2 ;;
        --simtime) SIMTIME="${2:?}"; shift 2 ;;
        *) usage ;;
    esac
done
[ -x "$BIN" ] || { echo "not executable: $BIN" >&2; exit 2; }
[ "$REPEATS" -ge 1 ] 2>/dev/null || usage

# Library dir of the ns-3 build that owns the binary (RPATH is not guaranteed).
BUILD_DIR="$(dirname "$BIN")"
while [ "$BUILD_DIR" != / ] && [ "$(basename "$BUILD_DIR")" != build ]; do BUILD_DIR="$(dirname "$BUILD_DIR")"; done
if [ -d "$BUILD_DIR/lib" ]; then
    export LD_LIBRARY_PATH="$BUILD_DIR/lib:${LD_LIBRARY_PATH:-}"
    SRC_DIR="$(dirname "$BUILD_DIR")"
else
    SRC_DIR=""
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Full-path anchored pattern: matches the scenario process only, not this script.
BIN_RE="^$(printf '%s' "$BIN" | sed 's/[][\.*^$+?(){}|/]/\\&/g')( |\$)"
stray_scenario() { pgrep -f "$BIN_RE" | tr '\n' ' '; }
listeners() { ss -tlnp 2>/dev/null | grep -E ':3847[0-9][[:space:]]' || true; }

SINK_PID=""
OUR_PGIDS=""
stop_sink() {
    [ -n "$SINK_PID" ] || return 0
    kill -TERM "$SINK_PID" 2>/dev/null
    for _ in $(seq 50); do kill -0 "$SINK_PID" 2>/dev/null || break; sleep 0.2; done
    kill -KILL "$SINK_PID" 2>/dev/null
    wait "$SINK_PID" 2>/dev/null
    SINK_PID=""
}
cleanup() {
    stop_sink
    local g
    for g in $OUR_PGIDS; do kill -KILL -- "-$g" 2>/dev/null; done
}
trap cleanup EXIT

# Timed direct run in its own process group; prints one JSON line.
cat >"$OUT/timed-run.py" <<'PY'
import json, os, signal, subprocess, sys, time
rundir, tmo = sys.argv[1], float(sys.argv[2])
cmd = sys.argv[3:]
os.makedirs(rundir, exist_ok=True)
out = open(os.path.join(rundir, "stdout.txt"), "wb")
t0 = time.monotonic()
p = subprocess.Popen(cmd, cwd=rundir, stdout=out, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)
pgid = p.pid
timed_out = False
try:
    rc = p.wait(timeout=tmo)
except subprocess.TimeoutExpired:
    timed_out = True
    os.killpg(pgid, signal.SIGKILL)
    p.wait()
    rc = -9
wall = time.monotonic() - t0
try:
    os.killpg(pgid, signal.SIGKILL)  # anything left in our group
    leftover = True
except ProcessLookupError:
    leftover = False
print(json.dumps({"wall_s": wall, "rc": rc, "timed_out": timed_out, "pgid": pgid,
                  "leftover_killed": leftover}))
PY

# run_repeat <cfg> <ports> <idx> <scenario args...>
run_repeat() {
    local cfg="$1" ports="$2" idx="$3"; shift 3
    local rd="$OUT/$cfg/r$idx" waited=0
    rm -rf "$rd"; mkdir -p "$rd"
    python3 -I "$SINK_PY" --ports "$ports" --out "$rd/sink" >"$rd/sink.log" 2>&1 &
    SINK_PID=$!
    until grep -q '^READY$' "$rd/sink.log" 2>/dev/null; do
        sleep 0.2; waited=$((waited + 1))
        if [ $waited -gt 75 ] || ! kill -0 "$SINK_PID" 2>/dev/null; then
            log "sink failed to start: $(cat "$rd/sink.log")"; return 1
        fi
    done
    local stray; stray="$(stray_scenario)"
    if [ -n "$stray" ]; then log "stray scenario process before run: $stray"; return 1; fi
    local res
    res="$(python3 -I "$OUT/timed-run.py" "$rd" "$RUN_TIMEOUT_S" "$BIN" "--simTime=$SIMTIME" \
        "--indicationPeriodicity=$PERIOD" "$E2_HOST_OPT=127.0.0.1" "$E2_TRACE_OPT=$rd" "$@")" || return 1
    OUR_PGIDS="$OUR_PGIDS $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["pgid"])' "$res")"
    stop_sink
    stray="$(stray_scenario)"
    if [ -n "$stray" ]; then log "stray scenario process after run: $stray"; return 1; fi
    echo "$res" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["dir"]=sys.argv[1]; d["idx"]=int(sys.argv[2]); print(json.dumps(d))' \
        "$rd" "$idx" >>"$OUT/$cfg/runs.jsonl"
    log "$cfg r$idx: $res"
}

# cv_of <cfg>: stdev/mean of wall time over the runs so far (0 with < 2 runs).
cv_of() {
    python3 -I - "$OUT/$1/runs.jsonl" <<'PY'
import json, statistics, sys
w = [json.loads(l)["wall_s"] for l in open(sys.argv[1]) if l.strip()]
print(statistics.stdev(w) / statistics.mean(w) if len(w) >= 2 else 0)
PY
}

measure_cfg() {
    local cfg="$1" ports="$2"; shift 2
    local n=0 cv
    mkdir -p "$OUT/$cfg"; : >"$OUT/$cfg/runs.jsonl"
    while :; do
        n=$((n + 1))
        run_repeat "$cfg" "$ports" "$n" "$@" || return 1
        [ "$n" -ge "$REPEATS" ] || continue
        cv="$(cv_of "$cfg")"
        if [ "$n" -lt "$MAX_REPEATS" ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)' "$cv" "$CV_LIMIT"; then
            log "$cfg: stdev/mean $cv > $CV_LIMIT, adding a repeat"
            continue
        fi
        break
    done
}

LOAD_BEFORE="$(cut -d' ' -f1-3 /proc/loadavg)"
START_ISO="$(date -Is)"
rc=0
if [ -n "$(stray_scenario)" ] || [ -n "$(listeners)" ]; then
    log "stray scenario process or listener on 3847x before start"; exit 1
fi
measure_cfg single 38472 --nMmWaveEnbNodes=1 --e2lteEnabled=false || rc=1
if [ $rc -eq 0 ]; then measure_cfg default 38471-38475 || rc=1; fi
cleanup
LOAD_AFTER="$(cut -d' ' -f1-3 /proc/loadavg)"

LEFT_PROC="$(stray_scenario)"; LEFT_LISTEN="$(listeners)"
[ -z "$LEFT_PROC$LEFT_LISTEN" ] || { log "left over: proc[$LEFT_PROC] listeners[$LEFT_LISTEN]"; rc=1; }

# Source SHAs: the commit of each source dir behind the binary.
sha_of() { [ -n "$1" ] && [ -e "$1" ] && git -C "$1" rev-parse HEAD 2>/dev/null || echo unknown; }
NS3_HEAD="$(sha_of "$SRC_DIR")"
IFACE_HEAD="$(sha_of "${SRC_DIR:+$SRC_DIR/contrib/oran-interface}")"
HARNESS_HEAD="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"

python3 -I - "$OUT" "$SIMTIME" "$PERIOD" "$BIN" "$NS3_HEAD" "$IFACE_HEAD" "$HARNESS_HEAD" \
    "$(nproc)" "$LOAD_BEFORE" "$LOAD_AFTER" "$START_ISO" "$(date -Is)" "$rc" <<'PY'
import json, os, statistics, sys
(out, simtime, period, binary, ns3, iface, harness, nproc, lb, la, t0, t1, rc) = sys.argv[1:]
simtime = float(simtime)
expected = round(simtime / float(period))
rep = {"binary": binary, "simTime_s": simtime, "indicationPeriodicity_s": float(period),
       "expected_samples_per_node": expected,
       "commits": {"ns3_mmwave": ns3, "oran_interface": iface, "harness": harness},
       "nproc": int(nproc), "load_avg_before": lb, "load_avg_after": la,
       "started": t0, "finished": t1, "timezone": "Asia/Seoul",
       "method": "wall time via python time.monotonic() around the direct binary call, "
                 "own process group, emitter active against ipc-null-sink; includes process "
                 "startup and scenario setup",
       "configs": {}, "ok": rc == "0"}
for cfg in ("single", "default"):
    path = os.path.join(out, cfg, "runs.jsonl")
    if not os.path.exists(path):
        continue
    runs = [json.loads(l) for l in open(path) if l.strip()]
    for r in runs:
        r["real_s_per_sim_s"] = r["wall_s"] / simtime
        try:
            s = json.load(open(os.path.join(r["dir"], "sink", "summary.json")))
            r["samples_per_node"] = {k: v["sample"] for k, v in s["nodes"].items()}
            r["invalid_lines"] = s["totals"]["invalid"]
        except (OSError, ValueError):
            r["samples_per_node"] = {}
            r["invalid_lines"] = None
    v = [r["real_s_per_sim_s"] for r in runs]
    mean = statistics.mean(v) if v else None
    sd = statistics.stdev(v) if len(v) >= 2 else 0.0
    rep["configs"][cfg] = {
        "repeats": len(v), "mean": mean, "min": min(v, default=None), "max": max(v, default=None),
        "stdev": sd, "cv": (sd / mean) if mean else None, "runs": runs}
    if any(r["rc"] != 0 or not r["samples_per_node"] for r in runs):
        rep["ok"] = False
json.dump(rep, open(os.path.join(out, "ns3-timing.json"), "w"), indent=2)

L = ["ns-3 scenario-zero timing (real seconds per simulated second)",
     "date %s .. %s (Asia/Seoul)" % (t0, t1),
     "simTime %gs, indicationPeriodicity %gs, expected samples/node %d" % (simtime, float(period), expected),
     "commits: ns3-mmwave %s, oran-interface %s, harness %s" % (ns3, iface, harness),
     "nproc %s, load avg before [%s] after [%s]" % (nproc, lb, la),
     "binary %s" % binary, ""]
for cfg, c in rep["configs"].items():
    if not c["runs"]:
        continue
    L.append("%-8s repeats=%d mean=%.3f min=%.3f max=%.3f stdev=%.3f cv=%.1f%%" % (
        cfg, c["repeats"], c["mean"], c["min"], c["max"], c["stdev"], 100 * (c["cv"] or 0)))
    for r in c["runs"]:
        L.append("  r%d wall=%.2fs rc=%s samples/node=%s invalid=%s" % (
            r["idx"], r["wall_s"], r["rc"], r["samples_per_node"], r["invalid_lines"]))
L.append("")
L.append("result: %s" % ("ok" if rep["ok"] else "PROBLEM (nonzero rc, missing sink data, or hygiene failure)"))
open(os.path.join(out, "ns3-timing.txt"), "w").write("\n".join(L) + "\n")
print("\n".join(L))
PY
[ "$rc" -eq 0 ] && grep -q '^result: ok' "$OUT/ns3-timing.txt"

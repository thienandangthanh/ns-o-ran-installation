#!/usr/bin/env bash
# Gate M4 (VM side): ns-3 builds from a clean pinned clone with no e2sim/asn1c,
# and the IPC emitter behaves (null sink, agent down, default-run regression),
# plus the timing report. Never needs the RIC.
#
# Scripts used: scripts/build-ns3.sh <workdir> (last stdout line = scenario-zero
# binary), scripts/measure-ns3-timing.sh, tools/ipc-null-sink/ipc-null-sink.py.
#
# Knobs: M4_WORKDIR (default $HOME/m4-build); RUN_TIMEOUT_S (default 600 per
# scenario run); BUILD_TIMEOUT_S (default 5400); TIMING_TIMEOUT_S (default 3600).
source "$(dirname "$0")/lib.sh"
gate_init m4

# Scenario-zero option names (assumed; confirm against scratch/scenario-zero.cc).
E2_TRACE_OPT="--e2TraceDir"
E2_HOST_OPT="--e2AgentHost"
PERIOD=0.1
SIMTIME=2

M4_WORKDIR="${M4_WORKDIR:-$HOME/m4-build}"
RUN_TIMEOUT_S="${RUN_TIMEOUT_S:-600}"
BUILD_TIMEOUT_S="${BUILD_TIMEOUT_S:-5400}"
TIMING_TIMEOUT_S="${TIMING_TIMEOUT_S:-3600}"
SINK_PY="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
RUNS="$EVIDENCE_DIR/runs"
mkdir -p "$RUNS"

BIN=""; BUILD_DIR=""; BIN_RE=""
SINK_PID=""

stray_scenario() { [ -n "$BIN_RE" ] && pgrep -f "$BIN_RE" | tr '\n' ' '; }
listeners() { ss -tlnp 2>/dev/null | grep -E ':3847[0-9][[:space:]]' || true; }

stop_sink() {
    [ -n "$SINK_PID" ] || return 0
    kill -TERM "$SINK_PID" 2>/dev/null
    for _ in $(seq 50); do kill -0 "$SINK_PID" 2>/dev/null || break; sleep 0.2; done
    kill -KILL "$SINK_PID" 2>/dev/null
    wait "$SINK_PID" 2>/dev/null
    SINK_PID=""
}
trap stop_sink EXIT

# sink_start <name> <ports>: sink with --save-lines in runs/<name>/sink; waits for READY.
sink_start() {
    local rd="$RUNS/$1" waited=0
    mkdir -p "$rd"
    python3 -I "$SINK_PY" --ports "$2" --out "$rd/sink" --save-lines >"$rd/sink.log" 2>&1 &
    SINK_PID=$!
    until grep -q '^READY$' "$rd/sink.log" 2>/dev/null; do
        sleep 0.2; waited=$((waited + 1))
        if [ $waited -gt 75 ] || ! kill -0 "$SINK_PID" 2>/dev/null; then
            echo "sink failed to start: $(cat "$rd/sink.log")"; return 1
        fi
    done
}

# run_scn <name> <args...>: compiled binary directly, own session, bounded, cwd runs/<name>.
run_scn() {
    local name="$1"; shift
    local rd="$RUNS/$name" t0 t1
    mkdir -p "$rd"
    if [ -n "$(stray_scenario)" ]; then echo "stray scenario process: $(stray_scenario)"; return 1; fi
    t0=$(date +%s.%N)
    (cd "$rd" && setsid -w timeout --kill-after=15 "$RUN_TIMEOUT_S" "$BIN" "$@" >stdout.txt 2>&1 </dev/null)
    local rc=$?
    t1=$(date +%s.%N)
    echo "$rc" >"$rd/exit-code"
    echo "scenario $name exit $rc in $(python3 -c 'import sys; print("%.1f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$t0" "$t1")s: $*"
    return "$rc"
}

# summary_assert <name> <expected nodes csv> <expected total imsis>: sink summary checks (c/d/f).
summary_assert() {
    python3 -I - "$RUNS/$1/sink/summary.json" "$2" "$3" "$SIMTIME" "$PERIOD" <<'PY'
import json, sys
path, nodes_csv, n_imsi, simtime, period = sys.argv[1:]
s = json.load(open(path))
want = [x for x in nodes_csv.split(",") if x]
exp = round(float(simtime) / float(period))
bad = []
if sorted(s["nodes"]) != sorted(want):
    bad.append("nodes %s != %s" % (sorted(s["nodes"]), sorted(want)))
for nid in want:
    n = s["nodes"].get(nid)
    if not n:
        continue
    if n["hello"] != 1 or n["bye"] != 1:
        bad.append("node %s hello=%d bye=%d (want 1/1)" % (nid, n["hello"], n["bye"]))
    if abs(n["sample"] - exp) > 2:
        bad.append("node %s samples %d not within 2 of %d" % (nid, n["sample"], exp))
    if n["seq_gaps"] or n["ipc_dropped_max"]:
        bad.append("node %s seq_gaps=%d ipcDropped=%d" % (nid, n["seq_gaps"], n["ipc_dropped_max"]))
    if (n["kind"] == "enb") != (nid == "1"):
        bad.append("node %s kind %s (cellId 1 must be the only enb)" % (nid, n["kind"]))
    # UEs attach by proximity: per-gNB counts vary (0..6 in scenario-zero),
    # the LTE eNB (master RRC) carries every UE once attached (seq 0 has none).
    counts = {int(k) for k in n["ue_counts"]}
    if n["kind"] == "enb" and not (counts <= {0, int(n_imsi)} and int(n_imsi) in counts):
        bad.append("eNB %s ue counts per sample %s (want %s after attach)" % (nid, sorted(counts), n_imsi))
    if n["kind"] == "gnb" and max(counts, default=0) > int(n_imsi):
        bad.append("gNB %s ue counts per sample %s exceed %s" % (nid, sorted(counts), n_imsi))
    if n["bye_msg"] and n["bye_msg"]["droppedDisconnected"] + n["bye_msg"]["droppedBackpressure"]:
        bad.append("node %s bye reports drops %s" % (nid, n["bye_msg"]))
if s["totals"]["invalid"]:
    bad.append("%d invalid lines: %s" % (s["totals"]["invalid"], s["invalid_examples"][:3]))
if s["totals"]["n_distinct_imsis"] != int(n_imsi):
    bad.append("distinct IMSIs %d != %s" % (s["totals"]["n_distinct_imsis"], n_imsi))
print("sink validation=%s nodes=%s samples=%s ues=%s imsis=%d invalid=%d" % (
    s["validation"], sorted(s["nodes"]), {k: v["sample"] for k, v in s["nodes"].items()},
    {k: v["ue_counts"] for k, v in s["nodes"].items()}, s["totals"]["n_distinct_imsis"],
    s["totals"]["invalid"]))
if bad:
    print("PROBLEMS: " + " | ".join(bad)); sys.exit(1)
PY
}

# trace_vs_wire <name> <nodes csv>: runs/<name> trace files vs lines the sink received.
# Compared on sample lines (byte-exact); the trace may carry extra lines only up to
# the node's final ipcDropped.
trace_vs_wire() {
    python3 -I - "$RUNS/$1" "$2" <<'PY'
import json, os, sys
rd, nodes = sys.argv[1], [x for x in sys.argv[2].split(",") if x]
bad = []
def samples(path):
    out = []
    for raw in open(path, "rb").read().split(b"\n"):
        if raw and json.loads(raw).get("type") == "sample":
            out.append(raw)
    return out
for nid in nodes:
    tp = os.path.join(rd, "e2-ipc-trace-%s.jsonl" % nid)
    wp = os.path.join(rd, "sink", "lines-%s.jsonl" % nid)
    if not os.path.exists(tp) or not os.path.exists(wp):
        bad.append("node %s: missing %s" % (nid, tp if not os.path.exists(tp) else wp)); continue
    t, w = samples(tp), samples(wp)
    dropped = json.loads(w[-1]).get("ipcDropped", 0) if w else 0
    if t == w:
        print("node %s: %d sample lines identical" % (nid, len(t))); continue
    it = iter(t)
    subseq = all(any(x == y for y in it) for x in w)
    if subseq and 0 < len(t) - len(w) <= max(dropped, 0):
        print("node %s: trace has %d extra lines, explained by ipcDropped=%d" % (nid, len(t) - len(w), dropped))
    else:
        bad.append("node %s: trace %d lines vs wire %d (ipcDropped %d, subsequence %s)" % (nid, len(t), len(w), dropped, subseq))
if bad:
    print("PROBLEMS: " + " | ".join(bad)); sys.exit(1)
PY
}

################################################################################
# a. clean clone builds by script
################################################################################
build_ns3() {
    local t0 t1
    t0=$(date +%s)
    timeout --kill-after=60 "$BUILD_TIMEOUT_S" bash "$HARNESS_DIR/scripts/build-ns3.sh" "$M4_WORKDIR" \
        >"$EVIDENCE_DIR/build-ns3.stdout" 2>"$EVIDENCE_DIR/build-ns3.stderr" </dev/null
    local rc=$?
    t1=$(date +%s)
    echo "$((t1 - t0))" >"$EVIDENCE_DIR/build-duration-s"
    tail -n 5 "$EVIDENCE_DIR/build-ns3.stderr"
    echo "build-ns3.sh exit $rc after $((t1 - t0))s"
    [ $rc -eq 0 ] || return 1
    BIN="$(tail -n 1 "$EVIDENCE_DIR/build-ns3.stdout")"
    [ -x "$BIN" ] || { echo "last stdout line is not an executable: $BIN"; return 1; }
    echo "binary $BIN"
}
check m4_build_ns3_exit0 build_ns3

# Everything below needs the binary; derive build/source dirs from its path.
if [ -x "$BIN" ]; then
    BUILD_DIR="$(dirname "$BIN")"
    while [ "$BUILD_DIR" != / ] && [ "$(basename "$BUILD_DIR")" != build ]; do BUILD_DIR="$(dirname "$BUILD_DIR")"; done
    SRC_DIR="$(dirname "$BUILD_DIR")"
    export LD_LIBRARY_PATH="$BUILD_DIR/lib:${LD_LIBRARY_PATH:-}"
    BIN_RE="^$(printf '%s' "$BIN" | sed 's/[][\.*^$+?(){}|/]/\\&/g')( |\$)"
    {
        echo "binary: $BIN"
        echo "ns3 head: $(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null)"
        echo "oran-interface head: $(git -C "$SRC_DIR/contrib/oran-interface" rev-parse HEAD 2>/dev/null)"
    } >"$EVIDENCE_DIR/build-info.txt"
fi

configure_flags_recorded() {
    local f; f="$(find "$M4_WORKDIR" -maxdepth 2 -type f -iname '*configure*' -not -path '*/.git/*' 2>/dev/null | head -n 5)"
    [ -n "$f" ] || { echo "no configure-flags file under $M4_WORKDIR"; return 1; }
    local x
    for x in $f; do cp "$x" "$EVIDENCE_DIR/configure-flags-$(basename "$x")"; echo "recorded $x"; head -n 5 "$x"; done
}
check m4_configure_flags_recorded configure_flags_recorded
record m4_build_duration_informational true "build-ns3.sh took $(cat "$EVIDENCE_DIR/build-duration-s" 2>/dev/null || echo '?')s"

################################################################################
# b. no asn1c / e2sim linkage
################################################################################
no_linkage() {
    [ -x "$BIN" ] && [ -d "$BUILD_DIR/lib" ] || { echo "no binary or $BUILD_DIR/lib"; return 1; }
    local f n=0 bad=0
    for f in "$BIN" "$BUILD_DIR"/lib/*.so; do
        [ -e "$f" ] || continue
        n=$((n + 1))
        if ldd "$f" 2>&1 | grep -Ei 'e2sim|asn1c'; then echo "ldd links e2sim/asn1c: $f"; bad=1; fi
        if nm -D "$f" 2>/dev/null | grep 'asn_DEF_'; then echo "asn_DEF_ symbol in: $f"; bad=1; fi
    done
    echo "checked $n files (binary + build/lib/*.so)"
    [ "$n" -ge 2 ] || { echo "suspiciously few files"; return 1; }
    [ $bad -eq 0 ]
}
check m4_no_e2sim_asn1c_linkage no_linkage

# ns-3.38 keeps CMakeCache.txt and generated build files in <src>/cmake-cache.
CMAKE_DIR="$(dirname "$BUILD_DIR")/cmake-cache"
cache_has_no_e2sim() {
    [ -f "$CMAKE_DIR/CMakeCache.txt" ] || { echo "no $CMAKE_DIR/CMakeCache.txt"; return 1; }
    ! grep -ri e2sim "$CMAKE_DIR/CMakeCache.txt"
}
check m4_cmakecache_has_no_e2sim cache_has_no_e2sim

# Nothing under /usr/local/include/e2sim was used: no build file mentions e2sim.
ls -la /usr/local/include/e2sim >"$EVIDENCE_DIR/usr-local-include-e2sim.txt" 2>&1
record m4_usr_local_include_e2sim_informational true "ls /usr/local/include/e2sim: $(head -n 2 "$EVIDENCE_DIR/usr-local-include-e2sim.txt" | tr '\n' ' ')"
no_e2sim_in_build_files() {
    [ -d "$CMAKE_DIR" ] || return 1
    ! grep -rIl e2sim --include=flags.make --include=link.txt --include=build.make \
        --include=compile_commands.json --include='*.cmake' "$CMAKE_DIR" "$BUILD_DIR"
}
check m4_no_e2sim_in_build_files no_e2sim_in_build_files

################################################################################
# c. smoke: default config, null sink on 38471-38475, trace == wire
################################################################################
smoke_default() {
    sink_start smoke 38471-38475 || return 1
    run_scn smoke "--simTime=$SIMTIME" "--indicationPeriodicity=$PERIOD" "$E2_HOST_OPT=127.0.0.1" "$E2_TRACE_OPT=$RUNS/smoke"
    local rc=$?
    stop_sink
    return $rc
}
check m4_smoke_default_exits0 smoke_default
check m4_smoke_sink_hello_bye_samples_ues_imsis summary_assert smoke 1,2,3,4,5 12
check m4_smoke_trace_equals_wire trace_vs_wire smoke 1,2,3,4,5

################################################################################
# d. single-node config: only node 2 says hello
################################################################################
single_node() {
    sink_start single 38471-38475 || return 1
    run_scn single "--simTime=$SIMTIME" "--indicationPeriodicity=$PERIOD" "$E2_HOST_OPT=127.0.0.1" \
        "$E2_TRACE_OPT=$RUNS/single" --nMmWaveEnbNodes=1 --e2lteEnabled=false
    local rc=$?
    stop_sink
    return $rc
}
check m4_single_node_exits0 single_node
# Single-node: only 2 of the 3 UEs reach gNB 2 (the third stays LTE-only; LTE is not an E2 node here).
check m4_single_node_only_node2_hello summary_assert single 2 2

################################################################################
# e. agent down: no sink at all; the run completes and the traces are complete
################################################################################
agent_down() {
    if [ -n "$(listeners)" ]; then echo "unexpected listener on 3847x:"; listeners; return 1; fi
    run_scn agentdown "--simTime=$SIMTIME" "--indicationPeriodicity=$PERIOD" "$E2_HOST_OPT=127.0.0.1" "$E2_TRACE_OPT=$RUNS/agentdown" || return 1
    grep -iE 'drop' "$RUNS/agentdown/stdout.txt" | tail -n 10 >"$EVIDENCE_DIR/agentdown-drop-counters.txt"
    echo "drop counter lines in stdout: $(grep -ciE 'drop' "$RUNS/agentdown/stdout.txt")"
    python3 -I - "$RUNS/agentdown" "$SIMTIME" "$PERIOD" <<'PY'
import json, os, sys
rd, simtime, period = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
exp = round(simtime / period)
bad = []
for nid in range(1, 6):
    p = os.path.join(rd, "e2-ipc-trace-%d.jsonl" % nid)
    if not os.path.exists(p):
        bad.append("missing trace for node %d" % nid); continue
    s = [json.loads(l) for l in open(p) if l.strip()]
    s = [m for m in s if m.get("type") == "sample"]
    seqs = [m["seq"] for m in s]
    print("node %d: %d samples, last ipcDropped=%s" % (nid, len(s), s[-1]["ipcDropped"] if s else None))
    if abs(len(s) - exp) > 2 or seqs != list(range(len(s))):
        bad.append("node %d: %d samples (want %d +-2, contiguous seq)" % (nid, len(s), exp))
if bad:
    print("PROBLEMS: " + " | ".join(bad)); sys.exit(1)
PY
}
check m4_agent_down_completes_traces_complete agent_down

################################################################################
# f. default-run regression (K11): no new args, same node/UE counts as (c)
################################################################################
default_regression() {
    sink_start regress 38471-38475 || return 1
    run_scn regress "--simTime=$SIMTIME"
    local rc=$?
    stop_sink
    return $rc
}
check m4_default_run_no_new_args_exits0 default_regression
check m4_default_run_same_nodes_and_ues_as_smoke summary_assert regress 1,2,3,4,5 12

################################################################################
# g. timing report
################################################################################
run_timing() {
    local d="$EVIDENCE_DIR/timing"
    timeout --kill-after=60 "$TIMING_TIMEOUT_S" bash "$HARNESS_DIR/scripts/measure-ns3-timing.sh" \
        "$BIN" "$d" --repeats 3 --simtime 10 </dev/null || return 1
    cp "$d/ns3-timing.json" "$d/ns3-timing.txt" "$EVIDENCE_DIR/" || return 1
}
check m4_timing_script_runs run_timing
timing_report_ok() {
    python3 -I - "$EVIDENCE_DIR/ns3-timing.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
bad = []
for cfg in ("single", "default"):
    c = r["configs"].get(cfg)
    if not c or c["repeats"] < 3:
        bad.append("%s: repeats %s (want >= 3)" % (cfg, c and c["repeats"]))
    else:
        print("%s: %d repeats, mean %.3f real s per sim s, cv %.1f%%" % (cfg, c["repeats"], c["mean"], 100 * c["cv"]))
for k in ("ns3_mmwave", "oran_interface"):
    v = r["commits"].get(k, "")
    if len(v) != 40:
        bad.append("commit %s missing: %r" % (k, v))
print("commits %s nproc %s load %s -> %s" % (r["commits"], r["nproc"], r["load_avg_before"], r["load_avg_after"]))
if bad:
    print("PROBLEMS: " + " | ".join(bad)); sys.exit(1)
PY
}
check m4_timing_report_repeats_and_shas timing_report_ok

################################################################################
# h. process hygiene
################################################################################
hygiene() {
    local bad=0
    stop_sink
    if [ -n "$(stray_scenario)" ]; then echo "stray scenario process: $(stray_scenario)"; bad=1; fi
    if [ -n "$(listeners)" ]; then echo "listener on 3847x:"; listeners; bad=1; fi
    [ $bad -eq 0 ] && echo "no scenario process, no listener on 3847x"
    return $bad
}
check m4_no_stray_process_or_listener hygiene

gate_finish

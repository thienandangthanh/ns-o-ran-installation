#!/usr/bin/env bash
# Probe (VM side, M10 AC6b): one lock-step scenario-zero run with --nMmWaveEnbNodes=10 (eNB 1 + gNB 2..11, 30 UEs)
# against 11 live agents and the live RIC. It measures the wall seconds per simulated second and the disk growth, so
# the scale step's simTime (step <= 45 min) and the end-run disk budget come from a measurement, not an inference.
#
#   probe-ns3-scale-ten-gnbs.sh [--simtime S]
#
# UseIdealRrc stays as built: scenario-zero sets ns3::MmWaveHelper::UseIdealRrc to true after cmd.Parse
# (scenario-zero.cc:483), so no CLI value reaches it; making it settable is T-C code (after checkpoint 2).
#
# Completeness (every check must pass, else the rate is not trusted): all 11 agents CONNECTED with distinct names and
# READY+subscribed before ns-3; ns-3 and the pacer (empty schedule: every step granted at once) exit 0; every node's
# IPC trace is clean (one hello, one bye, sent == built, zero drops, no seq gaps); every agent forwarded exactly its
# trace's samples with zero drop counters. Facts: wallPerSimS, simTimeS, wallS, vmRootUsedDeltaGiB, evidenceBytes
# (traces + capture), pcapBytes. Host-side overlay growth is measured by the caller around the run.
# Starts from a snapshot with the RIC, kpimon and the M4 ns-3 build (f7-rerun-green or later); leaves no agent running.
# ns-3's wall timeout scales with simTime: the first run (2026-11-03) measured ~17.5 wall s per 100 ms step and was
# cut by the default 900 s; parsed here, before agents-ns3-run.sh reads NS3_TIMEOUT_S
SIMTIME=10
for ((i = 1; i <= $#; i++)); do [ "${!i}" = --simtime ] && { j=$((i + 1)); SIMTIME="${!j}"; }; done
export NS3_TIMEOUT_S="${NS3_TIMEOUT_S:-$((SIMTIME * 300 + 600))}"
source "$(dirname "$0")/../gates/lib.sh"
gate_init scale10
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"
source "$HARNESS_DIR/scripts/gates/paced-lib.sh"

while [ $# -gt 0 ]; do
    case "$1" in
        --simtime) SIMTIME="$2"; shift 2 ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
NODES="enb:1$(for i in $(seq 2 11); do printf ',gnb:%d' "$i"; done)"
NNODES=11
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
T_GATE_S=$(python3 -I "$CFG" get deadlines.T_gate_s)
T_CTL_S=5
PACER_PORT=38499
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
CLI=(--nMmWaveEnbNodes=10 --handoverMode=NoAuto "--simTime=$SIMTIME" --indicationPeriodicity=0.1)
e="$EVIDENCE_DIR"; rd="$e/run"
mkdir -p "$rd/ns3run" "$rd/trace"
ric_watchdog_bg
fact simTimeS "$SIMTIME"
fact useIdealRrc true
fact nodes "$(json_str "$NODES")"
vm_used() { df -B1 --output=used / | tail -1 | tr -dc '0-9'; }
USED0=$(vm_used)

check scale10_ns3_binary_located agents_ns3_locate
check scale10_e2_ports_reserved agents_reserve_ports
check scale10_capture_started_before_agents capture_start scale10 docker0 'ip proto 132'
check scale10_agents_connected_set_exact gate_bringup agents "$NODES"
distinct() {
    local got; got=$(e2mgr_connected_names)
    echo "CONNECTED ($(echo "$got" | grep -c .)): $(echo "$got" | tr '\n' ' ')"
    [ "$(echo "$got" | grep -c .)" -eq "$NNODES" ] && [ "$(echo "$got" | sort -u | wc -l)" -eq "$NNODES" ]
}
check scale10_e2mgr_all_eleven_connected_distinct distinct
all_subscribed() {
    local deadline=$(($(date +%s) + 240)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk -v n="$NNODES" '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == n) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check scale10_every_agent_ready_and_subscribed all_subscribed

run_it() {
    local pp rc t0 t1
    python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" >"$rd/pacer.log" 2>&1 &
    pp=$!
    paced_wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    t0=$(date +%s.%N)
    ns3_start "$rd/ns3run" "${CLI[@]}" --RngRun=1 "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 \
        --e2TraceDir="$rd/trace" --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" || { kill "$pp"; return 1; }
    ns3_wait; rc=$NS3_RC; t1=$(date +%s.%N)
    paced_pacer_finish "$pp"
    python3 -I -c 'import sys; w = float(sys.argv[2]) - float(sys.argv[1]); print("%.3f %.3f" % (w, w / float(sys.argv[3])))' \
        "$t0" "$t1" "$SIMTIME" >"$rd/wall.txt"
    echo "ns-3 exit $rc, pacer exit $PACER_RC (want 0 and 0); wall s, wall per sim s: $(cat "$rd/wall.txt")"
    [ "$rc" = 0 ] && [ "$PACER_RC" = 0 ]
}
check scale10_lockstep_run_exits_clean run_it
read -r WALL WPS <"$rd/wall.txt" 2>/dev/null || { WALL=null; WPS=null; }
fact wallS "$WALL"
fact wallPerSimS "$WPS"
fact ns3TimeoutS "$NS3_TIMEOUT_S"
# steady-state rate: wall seconds per simulated second over the ready lines after the first simulated second
steady() {
    python3 -I - "$rd/pacer/pacer-log.jsonl" <<'PY'
import json, sys
rd = [(r["t"], r["msg"]["simTimeNs"]) for r in map(json.loads, filter(str.strip, open(sys.argv[1])))
      if r["msg"].get("type") == "ready" and r["msg"]["simTimeNs"] >= 1_000_000_000]
(t0, s0), (t1, s1) = rd[0], rd[-1]
print("%.3f" % ((t1 - t0) / ((s1 - s0) / 1e9)))
PY
}
fact wallPerSimSSteady "$(steady 2>/dev/null || echo null)"

logs_after_bye() {
    local c n deadline=$(($(date +%s) + 20))
    for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
        n=$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c")
        while :; do
            dk logs "$c" >"$rd/agent-$n.log" 2>&1
            grep '^{"event":"stats"' "$rd/agent-$n.log" | tail -n 1 >"$rd/agent-$n-stats.json"
            python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); sys.exit(0 if s["ipc"]["bye"] >= 1 else 1)' \
                "$rd/agent-$n-stats.json" 2>/dev/null && break
            [ "$(date +%s)" -lt "$deadline" ] || { echo "agent $n: no stats line after bye within 20 s"; return 1; }
            sleep 1
        done
    done
}
check scale10_agent_stats_after_bye logs_after_bye
check scale10_agents_stopped agents_stop
check scale10_capture_stopped capture_stop scale10
check scale10_ipc_traces_clean_every_node python3 -I "$HARNESS_DIR/tools/e2-evidence/trace-facts.py" "$rd"/trace/e2-ipc-trace-*.jsonl \
    --require-clean --expect-nodes "$(seq -s, 1 11)" --out "$e/scale10-trace-facts.json"
counters() {
    local n f exp bad=0
    for n in $(seq 1 11); do
        f="$rd/trace/e2-ipc-trace-$n.jsonl"
        exp=$(python3 -I -c 'import json,sys; print(sum(1 for l in open(sys.argv[1]) if l.strip() and json.loads(l).get("type") == "sample"))' "$f" 2>/dev/null || echo 0)
        printf 'node %s: ' "$n"; agent_counters_assert "$rd/agent-$n-stats.json" "$exp" || bad=1
    done
    return "$bad"
}
check scale10_agent_counters_clean_forwarded_equals_trace counters

USED1=$(vm_used)
python3 -I - "$USED0" "$USED1" "$rd" "$e" >"$e/scale10-disk.json" <<'PY'
import json, os, sys
u0, u1, rd, e = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
def tree(p):
    return sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs if not os.path.islink(os.path.join(r, f)))
pcap = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(e) for f in fs if ".pcap" in f)
print(json.dumps({"vmRootUsedDeltaGiB": round((u1 - u0) / 2**30, 3), "evidenceBytes": tree(e), "traceBytes": tree(rd + "/trace"),
                  "pcapBytes": pcap}))
PY
fact disk "$(cat "$e/scale10-disk.json")"
check scale10_hygiene agents_hygiene
ric_watchdog_stop
gate_finish

#!/usr/bin/env bash
# Probe (VM side, pre-M8 pacing gate): does any RIC/E2 component react while ns-3 is paused?
#
# From f7-rerun-green: capture docker0 (ip proto 132), bring up the 5 default agents, wait until every agent is
# READY and subscribed, start ns-3 default config free-run, wait for indications from every node, then
# SIGSTOP the ns-3 process group for each of PAUSES_S (default 60 300 900 s) and SIGCONT it, with ACTIVE_GAP_S of
# running time between pauses. During each pause: sample e2mgr states, agent stats/RestartCount and ricplt pod
# restarts every SAMPLE_S. After each SIGCONT: every agent's indTx must grow within RESUME_TIMEOUT_S.
# Wire facts per pause window come from tshark fields + analyze-pause-window-wire.py. RIC component logs since the
# capture start are kept for reading. No snapshot, no fork push; the caller reverts the VM afterwards.
#
# Knobs: PAUSES_S, ACTIVE_GAP_S (60), SAMPLE_S (30), RESUME_TIMEOUT_S (120), PAUSE_SIMTIME (20).
NS3_TIMEOUT_S="${NS3_TIMEOUT_S:-7200}"
source "$(dirname "$0")/../gates/lib.sh"
gate_init pause-ric-reaction
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"

NODES="enb:1,gnb:2,gnb:3,gnb:4,gnb:5"
NNODES=5
PAUSES_S="${PAUSES_S:-60 300 900}"
ACTIVE_GAP_S="${ACTIVE_GAP_S:-60}"
SAMPLE_S="${SAMPLE_S:-30}"
RESUME_TIMEOUT_S="${RESUME_TIMEOUT_S:-120}"
PAUSE_SIMTIME="${PAUSE_SIMTIME:-20}"
e="$EVIDENCE_DIR"
RUN="$e/ns3run"
mkdir -p "$RUN"

check pause_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check pause_build_tools_present agents_ensure_build_tools
check pause_sctp_module_loaded agents_sctp_module
check pause_ns3_binary_located agents_ns3_locate
check pause_capture_started_before_agents capture_start pause docker0 'ip proto 132'
CAP_T0=$(date +%s)
check pause_bringup_agents_connected_set_exact gate_bringup agents "$NODES"

all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk -v n="$NNODES" '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == n) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check pause_every_agent_ready_and_subscribed_before_ns3 all_subscribed
check pause_ns3_started_default_config ns3_start "$RUN" "--simTime=$PAUSE_SIMTIME" --indicationPeriodicity=0.1 \
    --e2AgentHost=127.0.0.1 "--e2TraceDir=$RUN"

# indtx_all: "<nodeId> <indTx>" per agent.
indtx_all() { agents_stats_all | awk '{ print $1, $6 }'; }
# wait_indtx_above <file-with-baseline> <timeout>: every node's indTx > its baseline.
wait_indtx_above() {
    local base="$1" deadline=$(($(date +%s) + $2)) now
    while [ "$(date +%s)" -lt "$deadline" ]; do
        now=$(indtx_all)
        if python3 -I - "$base" "$now" "$NNODES" <<'PY'
import sys
base = dict(l.split() for l in open(sys.argv[1]) if l.strip())
now = dict(l.split() for l in sys.argv[2].splitlines() if l.strip())
n = int(sys.argv[3])
sys.exit(0 if len(now) == n and all(int(now[k]) > int(base.get(k, -1)) for k in now) else 1)
PY
        then echo "indTx now: $(echo "$now" | tr '\n' ' ')"; return 0; fi
        sleep 2
    done
    echo "indTx did not grow on every node: base $(tr '\n' ' ' <"$base") now $(echo "$now" | tr '\n' ' ')"; return 1
}
printf '%s\n' 1 2 3 4 5 | awk '{ print $1, 0 }' >"$e/indtx-zero.txt"
check pause_first_indications_from_every_node wait_indtx_above "$e/indtx-zero.txt" 300

pause_sample() {
    local d="$1"
    mkdir -p "$d"
    date +%s.%N >"$d/t"
    e2mgr_states >"$d/e2mgr-states.json" 2>/dev/null
    agents_stats_all >"$d/agents.txt"
    kc -n ricplt get pods -o json 2>/dev/null | python3 -I -c '
import json, sys
for p in sorted(json.load(sys.stdin)["items"], key=lambda p: p["metadata"]["name"]):
    print(p["metadata"]["name"], sum(c.get("restartCount", 0) for c in p.get("status", {}).get("containerStatuses", [])))' >"$d/pods.txt"
    pod_info ricxapp kpimon-go >"$d/kpimon.txt" 2>/dev/null
    ps -o stat= -p "$NS3_PID" >"$d/ns3-stat.txt" 2>/dev/null
}
# sample_consistent <window-dir>: every sample shows all 5 CONNECTED, agents RestartCount 0, subs >= 1,
# ricplt restart counts and kpimon unchanged from the first sample.
sample_consistent() {
    python3 -I - "$1" "$NNODES" <<'PY'
import glob, json, os, sys
d, n = sys.argv[1], int(sys.argv[2])
samples = sorted(glob.glob(os.path.join(d, "sample-*")))
bad, first_pods, first_kp = [], None, None
for s in samples:
    st = json.load(open(os.path.join(s, "e2mgr-states.json")))
    conn = [x for x in st if x.get("connectionStatus") == "CONNECTED"]
    if len(conn) != n: bad.append("%s: %d CONNECTED" % (os.path.basename(s), len(conn)))
    for line in open(os.path.join(s, "agents.txt")):
        f = line.split()
        if f[1] != "0" or f[3] != "READY" or int(f[4]) < 1: bad.append("%s: agent %s" % (os.path.basename(s), line.strip()))
    pods = open(os.path.join(s, "pods.txt")).read()
    kp = open(os.path.join(s, "kpimon.txt")).read().split()
    first_pods = first_pods or pods
    first_kp = first_kp or kp
    if pods != first_pods: bad.append("%s: ricplt pods changed" % os.path.basename(s))
    if kp[:1] != first_kp[:1] or kp[-1:] != first_kp[-1:]: bad.append("%s: kpimon pod changed %s" % (os.path.basename(s), kp))
    if "T" not in open(os.path.join(s, "ns3-stat.txt")).read(): bad.append("%s: ns-3 not stopped" % os.path.basename(s))
print("%d samples; problems: %s" % (len(samples), bad or "none"))
sys.exit(1 if bad or not samples else 0)
PY
}

echo '[]' >"$e/pause-windows.json"
for P in $PAUSES_S; do
    w="$e/pause-$P"
    mkdir -p "$w"
    indtx_all >"$w/indtx-before.txt"
    T_STOP=$(date +%s.%N)
    kill -STOP -- "-$NS3_PID"
    log "pause $P s: SIGSTOP pgid $NS3_PID at $T_STOP"
    n=0
    while :; do
        pause_sample "$w/sample-$(printf %03d $n)"
        n=$((n + 1))
        python3 -c 'import sys,time; sys.exit(0 if time.time() + float(sys.argv[3]) < float(sys.argv[1]) + float(sys.argv[2]) else 1)' \
            "$T_STOP" "$P" "$SAMPLE_S" || break
        sleep "$SAMPLE_S"
    done
    python3 -c 'import sys,time; time.sleep(max(0, float(sys.argv[1]) + float(sys.argv[2]) - time.time()))' "$T_STOP" "$P"
    pause_sample "$w/sample-$(printf %03d $n)"
    indtx_all >"$w/indtx-at-cont.txt"
    T_CONT=$(date +%s.%N)
    kill -CONT -- "-$NS3_PID"
    log "pause $P s: SIGCONT at $T_CONT"
    python3 -I -c '
import json, sys
p, ws, ts, tc = sys.argv[1:5]
w = json.load(open(p)); w.append({"pause_s": int(ws), "t_stop": float(ts), "t_cont": float(tc)})
json.dump(w, open(p, "w"), indent=1)' "$e/pause-windows.json" "$P" "$T_STOP" "$T_CONT"
    no_ind_during() {
        diff "$w/indtx-before.txt" "$w/indtx-at-cont.txt" && echo "indTx unchanged during the pause: $(tr '\n' ' ' <"$w/indtx-before.txt")"
    }
    check "pause_${P}s_no_indication_sent_while_stopped" no_ind_during
    check "pause_${P}s_ric_state_unchanged_every_sample" sample_consistent "$w"
    check "pause_${P}s_indications_resume_on_every_node" wait_indtx_above "$w/indtx-at-cont.txt" "$RESUME_TIMEOUT_S"
    ns3_alive || { record "pause_${P}s_ns3_alive_after_cont" false "ns-3 exited"; break; }
    sleep "$ACTIVE_GAP_S"
done

final_state() { agents_stats_all | tee "$e/final-agents.txt"; e2mgr_states >"$e/final-e2mgr-states.json"; }
check pause_final_agent_state_recorded final_state
ns3_stop
for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
    id=$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c")
    dk logs "$c" >"$e/agent-$id.log" 2>&1
done
ric_logs() {
    local comp pod
    for comp in e2term e2mgr submgr rtmgr; do
        read -r pod _ < <(pod_info ricplt "$comp") || continue
        kc -n ricplt logs "$pod" --all-containers --since-time="$(iso_utc "$CAP_T0")" >"$e/ric-$comp.log" 2>&1
    done
    kpimon_logs_since "$CAP_T0" "$e/kpimon.log"
    ls -la "$e"/ric-*.log "$e/kpimon.log"
}
check pause_ric_component_logs_collected ric_logs
check pause_agents_stopped agents_stop
check pause_capture_stopped capture_stop pause
wire() {
    tshark -r "$e/pause.pcap" -d sctp.port==36422,e2ap -T fields -E separator=/t -E occurrence=a -E aggregator=, \
        -e frame.time_epoch -e ip.src -e ip.dst -e sctp.srcport -e sctp.dstport -e sctp.chunk_type \
        -e e2ap.procedureCode -e e2ap.initiatingMessage_element -e e2ap.successfulOutcome_element \
        -e e2ap.unsuccessfulOutcome_element >"$e/pause-wire-fields.tsv" 2>"$e/pause-wire-fields.stderr"
    python3 -I "$HARNESS_DIR/scripts/probes/analyze-pause-window-wire.py" "$e/pause-wire-fields.tsv" "$e/pause-windows.json" \
        | tee "$e/pause-wire-facts.json"
}
check pause_wire_no_abort_shutdown_resubscribe_delete_or_error_and_heartbeats_continue wire
check pause_hygiene agents_hygiene
gate_finish

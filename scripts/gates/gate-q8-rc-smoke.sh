#!/usr/bin/env bash
# Smoke q8 (VM side): the first real rc traffic through the P2 stack, labelled and outside any rung gate.
# Not a repeat gate and not evidence for C1; it shows that the pieces R0 needs work together:
#   rc installed at its pin, grpcurl, the Influx bucket reset, route dumps, a lock-step run with
#   enb:1, gnb:2, gnb:3 agents, two scripted rc controls (one applied, one refused), the capture,
#   and the wire extractor joined to the ledger.
#
#   gate-q8-rc-smoke.sh
#
# Schedule (trigger steps wait for the pacer's `steps` notice, so each control is stamped afterSeq = step):
#   step 20: rc -> node 2, imsi 6 -> gNB 3 cell 3   (ledger: applied; wire: ACK with Outcome Format 1)
#   step 40: rc -> node 3, imsi 6 -> gNB 3 cell 3   (already on the target: refused; wire: FAILURE)
# Outage threshold -1000: the R0 null-control run (Q2) decides it for the gated runs; here the radio state
# only has to let imsi 6 move.
source "$(dirname "$0")/lib.sh"
gate_init q8
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"

e="$EVIDENCE_DIR"
NODES="enb:1,gnb:2,gnb:3"
EPOCH_MS=$(python3 -I "$HARNESS_DIR/scripts/gates/rung-config.py" get scenario.simStartEpochMs)
T_GATE_S=10; T_CTL_S=30; PACER_PORT=38499
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1 --outageThreshold=-1000)
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
RUN="$e/run"
fact vmLoadStart "$(json_str "$(uptime)")"
record q8_args true "nodes $NODES; epoch $EPOCH_MS; cli ${CLI[*]}; rc pin $RC_SHA"
ric_watchdog_bg

_wait_ready() { for _ in $(seq 50); do grep -q READY "$1" && return 0; sleep 0.2; done; echo "$2 did not start: $(cat "$1")"; return 1; }
_pacer_finish() { for _ in $(seq 150); do kill -0 "$1" 2>/dev/null || break; sleep 0.2; done; kill "$1" 2>/dev/null; wait "$1"; PACER_RC=$?; }

check q8_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check q8_build_tools_present agents_ensure_build_tools
check q8_sctp_module_loaded agents_sctp_module
check q8_ns3_binary_located_at_pins agents_ns3_locate
check q8_pod_log_reader_self_test python3 -I "$HARNESS_DIR/scripts/gates/pod-log-window.py" --self-test
check q8_grpcurl_fetched_and_checksum_verified rc_grpcurl_fetch
check q8_rc_installed_at_pin_and_ready rc_install
check q8_influx_bucket_reset rc_influx_bucket_reset
check q8_rc_ready_describe_and_12040_route rc_ready
check q8_route_dump_start rc_route_dump start
fact routeOwner12041Start "$(json_str "${ROUTE_OWNER_12041:-}")"

check q8_capture_started_before_agents capture_start q8 docker0 'ip proto 132'
CAP_T0=$(date +%s)
check q8_bringup_agents_connected_set_exact gate_bringup agents "$NODES"
echo '{}' >"$e/node-ips.json"
check q8_agent_container_ips_recorded agents_record_ips "$e/node-ips.json"
all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == 3) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check q8_every_agent_ready_and_subscribed all_subscribed
check q8_pod_snapshot_before rc_pod_snapshot before
check q8_route_dump_agents_subscribed rc_route_dump subscribed

RC_EP=$(rc_endpoint)
cat >"$e/q8-schedule.json" <<JSON
{"steps": {
  "20": {"trigger": {"cmd": ["bash", "$HARNESS_DIR/scripts/gates/rc-send.sh", "$RC_EP", "2", "6", "0000000303"]}, "expect": 1},
  "40": {"trigger": {"cmd": ["bash", "$HARNESS_DIR/scripts/gates/rc-send.sh", "$RC_EP", "3", "6", "0000000303"]}, "expect": 1}
 }, "late": []}
JSON
q8_run() {
    local rd="$RUN" pp rc
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" --schedule "$e/q8-schedule.json" >"$rd/pacer.log" 2>&1 &
    pp=$!
    _wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    ns3_start "$rd/ns3run" "${CLI[@]}" "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 --e2TraceDir="$rd/trace" \
        --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" || { kill "$pp"; return 1; }
    ns3_wait; rc=$NS3_RC
    _pacer_finish "$pp"
    echo "q8 run: ns-3 exit $rc, pacer exit $PACER_RC (want 0 and 0)"
    [ "$rc" = 0 ] && [ "$PACER_RC" = 0 ]
}
check q8_lockstep_run_with_two_rc_controls q8_run
check q8_pod_snapshot_after rc_pod_snapshot after
check q8_route_dump_end rc_route_dump end
fact routeOwner12041 "$(json_str "${ROUTE_OWNER_12041:-}")"
fact routeOwner12042 "$(json_str "${ROUTE_OWNER_12042:-}")"
check q8_restart_counts_zero rc_restarts_zero after
for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
    dk logs "$c" >"$e/agent-$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c").log" 2>&1
done
check q8_agents_stopped agents_stop
check q8_capture_stopped capture_stop q8

q8_extract() {
    local tag
    tag=$(bash "$HARNESS_DIR/tools/rc-decode/build.sh") || return 1
    python3 -I "$HARNESS_DIR/tools/e2-evidence/wire-c1-extract.py" "$e/q8.pcap" --node-ips "$e/node-ips.json" \
        --ledger "$RUN/trace/e2-control-ledger.jsonl" --out-dir "$RUN/extra" --t0 "$CAP_T0" \
        --decode-cmd "$(dk_cmd) run --rm -i $tag"
}
check q8_wire_extractor_joins_requests_answers_and_ledger q8_extract
q8_facts() {
    python3 -I - "$RUN" <<'PY'
import json, sys
rd = sys.argv[1]
ms = json.load(open(rd + "/extra/rc-multiset.json"))
led = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
print("multiset:", ms)
print("ledger:", [(x["viaNodeId"], x["imsi"], x["sourceCell"], x["targetCell"], x["outcome"], x["cause"]) for x in led])
ok = (len(ms) == 2 and len(led) == 2
      and ms[0]["answer"] == "ack" and ms[0]["outcome"] == "0000" and ms[0]["step"] == 20 and ms[0]["viaNode"] == 2
      and ms[1]["step"] == 40 and ms[1]["answer"] == "failure" and ms[1]["cause"] == "control-failed-to-execute" and ms[1]["viaNode"] == 3
      and led[0]["outcome"] == "applied" and led[1]["outcome"] == "refused")
sys.exit(0 if ok else 1)
PY
}
check q8_two_controls_one_ack_format1_one_failure_matching_ledger q8_facts
influx_has_rows() { influx_rows "-30m" | tee "$e/influx-rows.txt"; grep -q '^total=[1-9]' "$e/influx-rows.txt"; }
check q8_kpimon_wrote_to_the_fresh_bucket influx_has_rows
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

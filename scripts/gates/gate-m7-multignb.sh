#!/usr/bin/env bash
# Gate M7 (VM side): multi-gNB robustness. Default node set = scenario-zero's E2 nodes (eNB 1 + gNB 2..5, 5 agents),
# ns-3 default config, 15 min endurance, then `kubectl delete pod <e2term>` and recovery, all under one ns-3 run.
#
# Timeline (wall clock, T0 = ns-3 start): bring-up (capture on docker0 `ip proto 132` first) -> endurance window
# T0..T0+ENDURANCE_S with a sample every SAMPLE_S (ricplt pod restarts, agent RestartCount, agent RSS, e2mgr CONNECTED set,
# ns-3 alive, load, kpimon) -> pre-delete counts -> e2term pod delete (T_del) -> replacement pod Ready -> bounded recovery
# poll -> ns-3 completes -> snapshots -> capture stop -> analysis -> teardown.
#
# simTime = ceil((ENDURANCE_S + DELETE_PHASE_S + 120) / mean real-s-per-sim-s of the default config) from the latest M4
# timing report (fallback 45, recorded). Time-to-CONNECTED and time-to-first-indication come from the wire (tshark facts,
# T_del = wall clock taken just before the delete command); the poll log bounds the wait and carries the restart evidence.
# Agents exit on association loss and Docker restarts them (P3 design): RestartCount must become >= 1 per agent.
# SCTP ABORT/SHUTDOWN around the delete is expected and only recorded; ABORT inside [T0, T_del) fails.
#
# Knobs: M7_NODES, ENDURANCE_S (900), DELETE_PHASE_S (300), SAMPLE_S (60), POD_READY_TIMEOUT_S (300),
# RECOVER_TIMEOUT_S (300, counted from the replacement pod Ready), NS3_TIMEOUT_S (2700), M7_SIMTIME_OVERRIDE, M4_WORKDIR.
NS3_TIMEOUT_S="${NS3_TIMEOUT_S:-2700}"
source "$(dirname "$0")/lib.sh"
gate_init m7
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"

NODES="${M7_NODES:-enb:1,gnb:2,gnb:3,gnb:4,gnb:5}"
ENDURANCE_S="${ENDURANCE_S:-900}"
DELETE_PHASE_S="${DELETE_PHASE_S:-300}"
SAMPLE_S="${SAMPLE_S:-60}"
POD_READY_TIMEOUT_S="${POD_READY_TIMEOUT_S:-300}"
RECOVER_TIMEOUT_S="${RECOVER_TIMEOUT_S:-300}"
IDS=$(echo "$NODES" | tr ',' '\n' | sed 's/.*://' | sort -n | paste -sd,)
NNODES=$(echo "$IDS" | tr ',' '\n' | grep -c .)
SODIR="$HOME/m7-work/so"
RUN="$EVIDENCE_DIR/ns3run"
EDIR="$EVIDENCE_DIR/endurance"
e="$EVIDENCE_DIR"
mkdir -p "$SODIR" "$RUN" "$EDIR"
ric_watchdog_bg

################################################################################
# prerequisites
################################################################################
check m7_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check m7_build_tools_present agents_ensure_build_tools
check m7_sctp_module_loaded_and_persisted agents_sctp_module
check m7_kpimon_so_extracted_from_image kpimon_extract_so "$SODIR"
so_size8() { echo "TimeStamp SIZE in the extracted .so: $(harness_so_size "$SODIR")"; [ "$(harness_so_size "$SODIR")" = 8 ]; }
check m7_kpimon_so_is_the_size8_patched_build so_size8
check m7_ns3_binary_located agents_ns3_locate
agents_pick_simtime >/dev/null
record m7_simtime_from_m4_timing_informational true "$M7_TIMING_NOTE; endurance ${ENDURANCE_S}s, delete phase ${DELETE_PHASE_S}s"

################################################################################
# capture, bring-up, start state
################################################################################
check m7_capture_started_before_agents capture_start m7 docker0 'ip proto 132'
CAP_T0=$(date +%s)
check m7_bringup_agents_kpm_sim_stopped_connected_set_exact gate_bringup agents "$NODES"
agents_expected_names >"$e/expected-names.txt"
five_distinct() {
    local got; got=$(e2mgr_connected_names)
    echo "CONNECTED: $(echo "$got" | tr '\n' ' ')"
    [ "$(echo "$got" | grep -c .)" -eq "$NNODES" ] && [ "$(echo "$got" | sort -u | wc -l)" -eq "$NNODES" ] && [ "$got" = "$(cat "$e/expected-names.txt")" ]
}
check m7_e2mgr_all_nodes_connected_with_distinct_names five_distinct
echo '{}' >"$e/node-ips.json"
check m7_agent_container_ips_recorded agents_record_ips "$e/node-ips.json"
ips_distinct() {
    python3 -I - "$e/node-ips.json" "$NNODES" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); n = int(sys.argv[2])
allips = [ip for v in d.values() for ip in v]
print("node -> container IPs: %s" % json.dumps(d, sort_keys=True))
sys.exit(0 if len(d) == n and all(len(v) == 1 for v in d.values()) and len(set(allips)) == n else 1)
PY
}
check m7_each_agent_has_its_own_container_ip ips_distinct

all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk -v n="$NNODES" '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == n) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check m7_every_agent_ready_and_subscribed_before_ns3 all_subscribed

################################################################################
# ns-3 + endurance
################################################################################
check m7_ns3_started_default_config ns3_start "$RUN" "--simTime=$M7_SIMTIME" --indicationPeriodicity=0.1 \
    --e2AgentHost=127.0.0.1 "--e2TraceDir=$RUN"
T0=$(printf '%.0f' "$NS3_START_EPOCH")
endurance() {
    local n=0 next
    while :; do
        endurance_sample "$EDIR" "$n"
        n=$((n + 1)); next=$((T0 + n * SAMPLE_S))
        [ "$next" -le $((T0 + ENDURANCE_S)) ] || return 0
        ns3_alive || { echo "ns-3 exited during the endurance window"; return 1; }
        while [ "$(date +%s)" -lt "$next" ]; do sleep 1; done
    done
}
check m7_endurance_window_sampled endurance
check m7_endurance_ricplt_pods_no_new_restarts python3 -I "$E2EV/endurance-eval.py" "$EDIR" --check pods
check m7_endurance_agents_restartcount_stays_zero python3 -I "$E2EV/endurance-eval.py" "$EDIR" --check agents
check m7_endurance_e2mgr_all_connected_every_sample python3 -I "$E2EV/endurance-eval.py" "$EDIR" --check e2mgr --expected-names "$e/expected-names.txt"
check m7_endurance_ns3_alive_every_sample python3 -I "$E2EV/endurance-eval.py" "$EDIR" --check ns3
check m7_endurance_kpimon_pod_no_restart python3 -I "$E2EV/endurance-eval.py" "$EDIR" --check kpimon
record m7_endurance_agent_rss_informational true "$(python3 -I "$E2EV/endurance-eval.py" "$EDIR" --check rss 2>&1 | tr '\n' ';')"
record m7_cpu_load_averages_informational true "nproc $(nproc); $(python3 -I "$E2EV/endurance-eval.py" "$EDIR" --check load 2>&1 | tail -n 1); samples in $EDIR/sample-*/load.txt"

################################################################################
# pre-delete counts, e2term pod delete, recovery
################################################################################
pre_counts() {
    agents_stats_all >"$e/pre-delete-agents.txt"
    e2mgr_states >"$e/pre-delete-e2mgr-states.json"
    kpimon_logs_since "$CAP_T0" "$e/m7-pre-delete-kpimon.log" && kpimon_log_counts "$e/m7-pre-delete-kpimon.log" | tr '\n' ' '
    echo
    influx_node_csv m7-pre "$NS3_START_EPOCH" && python3 -I "$E2EV/influx-node-rows.py" "$e/m7-pre-influx-nodes-cell.csv" --nodes "$IDS" --out "$e/m7-pre-influx-node-rows.json"
    cat "$e/pre-delete-agents.txt"
}
check m7_pre_delete_counts_recorded pre_counts

E2T_POD=""
read -r E2T_POD _ < <(pod_info ricplt e2term) || true
T_DEL=""
delete_e2term() {
    [ -n "$E2T_POD" ] || { echo "no e2term pod found"; return 1; }
    T_DEL=$(date +%s.%N)
    echo "T_del $T_DEL: kubectl -n ricplt delete pod $E2T_POD"
    kc -n ricplt delete pod "$E2T_POD"
}
check m7_e2term_pod_deleted_without_manual_ip_change delete_e2term
T_DEL_INT="${T_DEL:-0}"; T_DEL_INT="${T_DEL_INT%.*}"   # floor: pod creationTimestamp has 1 s resolution
pod_ready() {
    local deadline=$(($(date +%s) + POD_READY_TIMEOUT_S)) name ready created
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if read -r name ready created _ < <(pod_info ricplt e2term) && [ "$ready" = true ] && [ "$created" -ge "$T_DEL_INT" ] && [ "$name" != "$E2T_POD" ]; then
            POD_READY_EPOCH=$(date +%s.%N)
            echo "replacement pod $name Ready $(python3 -c 'import sys; print("%.1f" % (float(sys.argv[1]) - float(sys.argv[2])))' "$POD_READY_EPOCH" "$T_DEL") s after the delete"
            return 0
        fi
        sleep 2
    done
    return 1
}
check m7_replacement_e2term_pod_ready_bounded pod_ready

POLLS="$e/recovery-polls.tsv"; : >"$POLLS"
recovery_poll() {
    printf '%s\t%s\t%s\n' "$(date +%s.%N)" "$(e2mgr_connected_names | paste -sd,)" \
        "$(agents_stats_all | awk '{printf "%s:%s:%s:%s:%s:%s ", $1, $2, $3, $4, $5, $6}')" >>"$POLLS"
}
recover() {
    local deadline=$(($(date +%s) + RECOVER_TIMEOUT_S))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        recovery_poll
        python3 -I "$E2EV/recovery-eval.py" "$POLLS" --after "$T_DEL" --expected-names "$e/expected-names.txt" >/dev/null 2>&1 && break
        ns3_alive || { echo "ns-3 is no longer running"; break; }
        sleep 3
    done
    python3 -I "$E2EV/recovery-eval.py" "$POLLS" --after "$T_DEL" --expected-names "$e/expected-names.txt" --out "$e/m7-recovery-poll-summary.json"
}
check m7_recovery_every_node_restarted_reconnected_and_indicating recover
check m7_ns3_still_running_after_recovery ns3_alive
agents_stats_all >"$e/post-recovery-agents.txt"
agents_record_ips "$e/node-ips.json" >/dev/null
restart_ge1() { cat "$e/post-recovery-agents.txt"; awk '$2 >= 1 { ok++ } END { exit !(ok == '"$NNODES"') }' "$e/post-recovery-agents.txt"; }
check m7_agents_restartcount_ge1_after_delete restart_ge1
check m7_ns3_completes_exit0_through_the_delete ns3_wait
log "draining 10s"; sleep 10

################################################################################
# snapshots, stop capture
################################################################################
agents_stats_all >"$e/final-agents.txt"
for c in $(dk ps -aq --filter label=ns3e2.agent=1); do dk logs "$c" >"$e/agent-$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c").log" 2>&1; done
dk inspect $(dk ps -aq --filter label=ns3e2.agent=1) >"$e/agents-inspect.json" 2>&1
e2mgr_states >"$e/final-e2mgr-states.json"
kpimon_logs_since "$CAP_T0" "$e/m7-kpimon.log"
counts=$(kpimon_log_counts "$e/m7-kpimon.log")
check m7_influx_node_series_exported influx_node_csv m7 "$NS3_START_EPOCH"
check m7_capture_stopped capture_stop m7

################################################################################
# analysis
################################################################################
check m7_pcap_facts_extracted pcap_facts "$e/m7.pcap" m7
F="$e/m7-facts.json"; Q="$E2EV/e2-facts-query.py"
SERVICE_IP=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["agents"][0]["e2Term"].split(":")[0])' "$e/agents.json")
check m7_pcap_one_association_per_agent_distinct_ips_no_sport_collision python3 -I "$Q" "$F" assoc-start \
    --node-ips "$e/node-ips.json" --service-ip "$SERVICE_IP" --before "$T_DEL"
check m7_no_sctp_abort_during_endurance_window python3 -I "$Q" "$F" no-abort --from "$NS3_START_EPOCH" --to "$T_DEL"
record m7_sctp_abort_shutdown_around_delete_informational true "$(python3 -I "$Q" "$F" no-abort --from "$(python3 -c "print($T_DEL - 5)")" --to "$(python3 -c "print($T_DEL + 600)")" 2>&1 | head -c 1500 | tr '\n' ';')"
check m7_wire_every_agent_init_goes_to_the_same_service_ip python3 -I "$Q" "$F" service-ip --node-ips "$e/node-ips.json" --service-ip "$SERVICE_IP"
python3 -I "$Q" "$F" post-delete --node-ips "$e/node-ips.json" --service-ip "$SERVICE_IP" --after "$T_DEL" --func-id 2 \
    --timeline-out "$e/m7-post-delete-timeline.json" >"$e/m7-post-delete-query.txt" 2>&1
timeline_has() {
    python3 -I - "$e/m7-post-delete-timeline.json" "$@" <<'PY'
import json, sys
t = json.load(open(sys.argv[1])); fields = sys.argv[2:]
bad = [n for n, v in t.items() if any(v.get(f) is None for f in fields)]
print("%s: %s" % (",".join(fields), {n: [v.get(f) for f in fields] for n, v in sorted(t.items())}))
sys.exit(1 if bad or not t else 0)
PY
}
new_ports() {
    python3 -I - "$e/m7-post-delete-timeline.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
print({n: (v["new_sport"], v["old_sports"]) for n, v in sorted(t.items())})
sys.exit(0 if t and all(v["new_sport"] is not None and v["new_sport"] not in v["old_sports"] for v in t.values()) else 1)
PY
}
check m7_wire_new_association_per_node_new_source_port new_ports
check m7_wire_new_e2setup_request_and_response_per_node timeline_has setup_request_s setup_response_s
check m7_wire_new_ricsubscription_request_and_response_per_node timeline_has sub_request_s sub_response_s
check m7_wire_first_indication_after_delete_per_node timeline_has first_indication_s
record m7_per_node_time_to_connected_and_first_indication_informational true "wire (s after T_del): $(tr -d ' \n' <"$e/m7-post-delete-timeline.json"); poll bound: $(tr -d ' \n' <"$e/m7-recovery-poll-summary.json" 2>/dev/null)"
check m7_per_node_ricindications_on_the_wire python3 -I "$Q" "$F" indications --node-ips "$e/node-ips.json"

check m7_harness_ran_on_pcap harness_analyze m7 "$e/m7.pcap" "$SODIR" 8
if [ -s "$e/m7-decode.json" ]; then
    wire=$(jget "$e/m7-extract-summary.json" unique); skipped=$(jget "$e/m7-extract-summary.json" rows_skipped)
    total=$(jget "$e/m7-decode.json" total); hclean=$(jget "$e/m7-decode.json" hdr_clean); mclean=$(jget "$e/m7-decode.json" msg_clean)
    bad_sum=$(( $(jget "$e/m7-decode.json" hdr_wmore) + $(jget "$e/m7-decode.json" msg_wmore) + $(jget "$e/m7-decode.json" hdr_fail) + \
        $(jget "$e/m7-decode.json" msg_fail) + $(jget "$e/m7-decode.json" hdr_other) + $(jget "$e/m7-decode.json" msg_other) ))
    whole_pcap() {
        echo "wire (TSN-deduped, whole pcap) $wire; harness total $total; headers clean $hclean; messages clean $mclean; WMORE/FAIL/other $bad_sum; extractor rows skipped $skipped"
        [ "$wire" -gt 0 ] && [ "$total" -eq "$wire" ] && [ "$hclean" -eq "$total" ] && [ "$mclean" -eq "$total" ] && [ "$bad_sum" -eq 0 ] && [ "$skipped" -eq 0 ]
    }
    check m7_harness_every_header_and_message_clean_rc_ok_whole_pcap whole_pcap
    record m7_kpimon_log_counts_informational true "wire $wire; kpimon log: $(echo "$counts" | tr '\n' ' ')"
else
    record m7_harness_outputs_missing false "no m7-decode.json"
fi
fresh_influx() { python3 -I "$E2EV/influx-node-rows.py" "$e/m7-influx-nodes-cell.csv" --after "$T_DEL" --nodes "$IDS" --out "$e/m7-influx-node-rows-cell.json"; }
check m7_influx_fresh_cellmetrics_rows_per_nodeid_after_delete fresh_influx
record m7_influx_ue_rows_per_nodeid_informational true "$(python3 -I "$E2EV/influx-node-rows.py" "$e/m7-influx-nodes-ue.csv" --after "$T_DEL" 2>&1 | tr '\n' ';')"
trace_bye() {
    python3 -I "$E2EV/trace-facts.py" $(for i in ${IDS//,/ }; do echo "$RUN/e2-ipc-trace-$i.jsonl"; done) --expect-nodes "$IDS" --out "$e/m7-trace-facts.json" || true
    python3 -I - "$e/m7-trace-facts.json" <<'PY'
import json, sys
n = json.load(open(sys.argv[1]))
drops = {x["node"]: ((x["bye_msg"] or {}).get("droppedDisconnected"), (x["bye_msg"] or {}).get("droppedBackpressure"), x["ipc_dropped_max"]) for x in n}
print("ipcDropped (disconnected, backpressure, max per-sample): %s; total droppedDisconnected %s (expected > 0 around the delete)" % (
    drops, sum((d[0] or 0) for d in drops.values())))
sys.exit(0 if all(x["hello"] == 1 and x["bye"] == 1 for x in n) else 1)
PY
}
check m7_ns3_bye_ipc_dropped_recorded_per_node trace_bye

################################################################################
# teardown and hygiene
################################################################################
check m7_agents_stopped_no_container_left agents_stop
check m7_no_stray_ns3_agent_process_or_3847x_listener agents_hygiene
check m7_no_capture_left_running bash -c '! pgrep -x tcpdump >/dev/null'
record m7_pcap_in_evidence true "$(stat -c '%s %n' "$e"/m7*.pcap 2>/dev/null | tr '\n' ';')"
ric_watchdog_stop
gate_finish

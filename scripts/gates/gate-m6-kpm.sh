#!/usr/bin/env bash
# Gate M6 (VM side): single-gNB KPM end to end. gnb:2 agent + ns-3 `--nMmWaveEnbNodes=1 --e2lteEnabled=false`
# (P3 sign-off S3: one E2 node, gNB 2), 10 simulated seconds at --indicationPeriodicity=0.1.
#
# Flow: prerequisites -> capture (docker0, `ip proto 132`, before the agent) -> gate_bringup agents gnb:2 ->
# wait for kpimon's RICsubscriptionRequest and the agent's response on the wire -> ns-3 (direct binary, own process
# group, bounded, --e2TraceDir in the evidence) -> drain -> snapshots (agent stats, kpimon log, Influx) -> stop capture
# -> analysis -> teardown and process hygiene.
#
# "Clean RC_OK" (implementation-notes): asn1c code RC_OK AND consumed == length AND, for headers, an 8-octet TimeStamp.
# Wire indication count = harness lines (pcap-to-lines.py: TSN-deduped, assoc+TSN key).
# Influx vs trace: join on (ns3.nodeId, ns3.seq[, ns3.imsi]), never on _time; INTEGER exact, REAL bit-exact, noValue ->
# field absent (tools/e2-evidence/influx-vs-trace.py).
#
# Knobs: NS3_TIMEOUT_S (900), SUB_WAIT_S (180), DRAIN_S (8), M4_WORKDIR.
source "$(dirname "$0")/lib.sh"
gate_init m6
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"

SUB_WAIT_S="${SUB_WAIT_S:-180}"
DRAIN_S="${DRAIN_S:-8}"
SIMTIME=10
PERIOD=0.1
NODES="gnb:2"
SODIR="$HOME/m6-work/so"
RUN="$EVIDENCE_DIR/ns3run"
e="$EVIDENCE_DIR"
mkdir -p "$SODIR" "$RUN"
ric_watchdog_bg

################################################################################
# prerequisites
################################################################################
check m6_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check m6_build_tools_present agents_ensure_build_tools
check m6_sctp_module_loaded_and_persisted agents_sctp_module
check m6_kpimon_so_extracted_from_image kpimon_extract_so "$SODIR"
so_size8() { echo "TimeStamp SIZE in the extracted .so: $(harness_so_size "$SODIR")"; [ "$(harness_so_size "$SODIR")" = 8 ]; }
check m6_kpimon_so_is_the_size8_patched_build so_size8
check m6_ns3_binary_located agents_ns3_locate

################################################################################
# capture, agent, subscription
################################################################################
check m6_capture_started_before_agents capture_start m6 docker0 'ip proto 132'
CAP_T0=$(date +%s)
check m6_bringup_agents_kpm_sim_stopped_connected_set_exact gate_bringup agents "$NODES"
echo "{\"2\":[]}" >"$e/node-ips.json"
check m6_agent_container_ip_recorded agents_record_ips "$e/node-ips.json"

wait_sub() {
    local deadline=$(($(date +%s) + SUB_WAIT_S)) c
    while [ "$(date +%s)" -lt "$deadline" ]; do
        c=$(wire_sub_counts "$e/m6.pcap")
        echo "wire RICsubscription (requests responses): $c"
        [ "${c% *}" -ge 1 ] && [ "${c#* }" -ge 1 ] && return 0
        sleep 3
    done
    return 1
}
check m6_wire_shows_kpimon_subscription_request_and_agent_response wait_sub
# kpimon restart baseline: taken once kpimon has subscribed, i.e. after the
# post-boot settling (the snapshot boundary reboots the VM and k8s restarts the
# kpimon container then, before any of this gate's traffic).
KPIMON_POD0=""; KPIMON_RESTARTS0=""
read -r KPIMON_POD0 _ _ KPIMON_RESTARTS0 < <(pod_info ricxapp kpimon-go) || true
check m6_pcap_subscription_facts pcap_facts "$e/m6.pcap" m6-sub
check m6_tshark_decodes_subscription_request_response_func2 \
    python3 -I "$E2EV/e2-facts-query.py" "$e/m6-sub-facts.json" subscription --func-id 2

################################################################################
# ns-3 run
################################################################################
INFLUX_FROM=$(date +%s)
check m6_ns3_started_single_gnb ns3_start "$RUN" --nMmWaveEnbNodes=1 --e2lteEnabled=false "--simTime=$SIMTIME" \
    "--indicationPeriodicity=$PERIOD" --e2AgentHost=127.0.0.1 "--e2TraceDir=$RUN"
check m6_ns3_completes_exit0 ns3_wait
log "draining ${DRAIN_S}s"; sleep "$DRAIN_S"

agents_stats_last ns3-e2-agent-2 >"$e/agent-stats-final.json"
KPIMON_RESTARTS1=""
read -r _ _ _ KPIMON_RESTARTS1 < <(pod_info ricxapp kpimon-go) || true
kpimon_window() { kpimon_logs_since "$CAP_T0" "$e/m6-kpimon.log" && kpimon_log_window_summary "$e/m6-kpimon.log"; }
check m6_pod_log_reader_self_test python3 -I "$HARNESS_DIR/scripts/gates/pod-log-window.py" --self-test
check m6_kpimon_log_window_complete_across_rotations kpimon_window
counts=$(kpimon_log_counts "$e/m6-kpimon.log")
check m6_influx_exported influx_export m6 "$INFLUX_FROM"
dk inspect ns3-e2-agent-2 >"$e/agent-inspect.json" 2>&1
check m6_capture_stopped capture_stop m6

################################################################################
# analysis
################################################################################
check m6_pcap_facts_extracted pcap_facts "$e/m6.pcap" m6
ind_decoded() {
    e2ap_sample_decode "$e/m6.pcap" 5 3 "$e/m6-indication-sample-decode.txt"
    grep -c 'id-RICindication' "$e/m6-indication-sample-decode.txt"
    grep -q 'RICindicationHeader' "$e/m6-indication-sample-decode.txt" && grep -q 'RICindicationMessage' "$e/m6-indication-sample-decode.txt" || return 1
    grep -q 'E2SM-KPM-IndicationHeader' "$e/m6-indication-sample-decode.txt" && grep -q 'indicationMessage-formats' "$e/m6-indication-sample-decode.txt" || return 1
    # Every indication must dissect without a malformed-packet exception.
    local bad
    bad=$(tshark -r "$e/m6.pcap" -d sctp.port==36422,e2ap -Y 'e2ap.procedureCode == 5 && _ws.malformed' -T fields -e frame.number 2>/dev/null | wc -l)
    echo "tshark $(tshark --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1): malformed indication frames $bad"
    [ "$bad" -eq 0 ] && python3 -I "$E2EV/e2-facts-query.py" "$e/m6-facts.json" indications --node-ips "$e/node-ips.json"
}
check m6_tshark_decodes_ricindications_header_and_message ind_decoded

check m6_harness_ran_on_pcap harness_analyze m6 "$e/m6.pcap" "$SODIR" 8
if [ -s "$e/m6-decode.json" ]; then
    wire=$(jget "$e/m6-extract-summary.json" unique); skipped=$(jget "$e/m6-extract-summary.json" rows_skipped)
    total=$(jget "$e/m6-decode.json" total); hclean=$(jget "$e/m6-decode.json" hdr_clean); mclean=$(jget "$e/m6-decode.json" msg_clean)
    hw=$(jget "$e/m6-decode.json" hdr_wmore); mw=$(jget "$e/m6-decode.json" msg_wmore)
    hf=$(jget "$e/m6-decode.json" hdr_fail); mf=$(jget "$e/m6-decode.json" msg_fail)
    ho=$(jget "$e/m6-decode.json" hdr_other); mo=$(jget "$e/m6-decode.json" msg_other)
    wire_gt0() { echo "wire indications (TSN-deduped): $wire, extractor rows skipped: $skipped"; [ "$wire" -gt 0 ] && [ "$skipped" -eq 0 ]; }
    hdr_all() { echo "headers clean (RC_OK, consumed==len, ts_len 8): $hclean = harness total $total = wire $wire"; [ "$wire" -gt 0 ] && [ "$hclean" -eq "$total" ] && [ "$total" -eq "$wire" ]; }
    msg_all() { echo "messages clean (RC_OK, consumed==len): $mclean = harness total $total = wire $wire"; [ "$wire" -gt 0 ] && [ "$mclean" -eq "$total" ] && [ "$total" -eq "$wire" ]; }
    zero_bad() { echo "harness WMORE hdr/msg $hw/$mw, FAIL $hf/$mf, other $ho/$mo"; [ "$((hw + mw + hf + mf + ho + mo))" -eq 0 ]; }
    ts8() { echo "ts_len histogram: $(jget "$e/m6-harness-summary.json" ts_len_hist)"; [ "$(jget "$e/m6-harness-summary.json" ts_len_hist)" = "{\"8\": $wire}" ]; }
    check m6_wire_indications_gt0_no_rows_skipped wire_gt0
    check m6_harness_every_header_clean_rc_ok_equals_wire hdr_all
    check m6_harness_every_message_clean_rc_ok_equals_wire msg_all
    check m6_harness_zero_wmore_fail_other zero_bad
    check m6_harness_ts_len_8_everywhere ts8
    k_ind=$(echo "$counts" | kv indications); k_hw=$(echo "$counts" | kv hdr_wmore); k_mw=$(echo "$counts" | kv msg_wmore)
    kpimon_eq() { echo "kpimon log (since capture start): indications $k_ind, wire $wire, header RC_WMORE $k_hw, MSG RC_WMORE $k_mw"; [ "$k_ind" = "$wire" ] && [ "$k_hw" -eq 0 ] && [ "$k_mw" -eq 0 ]; }
    check m6_kpimon_log_indications_equal_wire_zero_wmore kpimon_eq
    indtx() { python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); print("agent indTx %d, wire %s" % (s["indTx"], sys.argv[2])); sys.exit(0 if s["indTx"] == int(sys.argv[2]) else 1)' "$e/agent-stats-final.json" "$wire"; }
    check m6_agent_indtx_equals_wire indtx
else
    record m6_harness_outputs_missing false "no m6-decode.json"
fi
kpimon_restarts() { echo "kpimon pod $KPIMON_POD0 restarts $KPIMON_RESTARTS0 -> $KPIMON_RESTARTS1"; [ -n "$KPIMON_RESTARTS0" ] && [ "$KPIMON_RESTARTS0" = "$KPIMON_RESTARTS1" ]; }
check m6_kpimon_pod_no_restart kpimon_restarts

TRACE="$RUN/e2-ipc-trace-2.jsonl"
check m6_emitter_bye_sent_equals_built_zero_drops python3 -I "$E2EV/trace-facts.py" "$TRACE" --require-clean --expect-nodes 2 --out "$e/m6-trace-facts.json"
nsamples=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["samples"])' "$e/m6-trace-facts.json" 2>/dev/null || echo 0)
check m6_agent_counters_clean_samples_in_equal_forwarded_equal_trace agent_counters_assert "$e/agent-stats-final.json" "$nsamples"

check m6_influx_three_samples_equal_trace_bit_exact python3 -I "$E2EV/influx-vs-trace.py" \
    --map "$AGENT_DIR/schema/metric-map.v1.json" --trace "$TRACE" --influx-cell "$e/m6-influx-cell.csv" \
    --influx-ue "$e/m6-influx-ue.csv" --out "$e/m6-influx-vs-trace.json"
all_info() { python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1]))["all"]; print(json.dumps(a, sort_keys=True))' "$e/m6-influx-vs-trace.json"; }
record m6_influx_all_samples_comparison_informational true "$(all_info 2>&1)"

################################################################################
# teardown and hygiene
################################################################################
check m6_agents_stopped_no_container_left agents_stop
check m6_no_stray_ns3_agent_process_or_3847x_listener agents_hygiene
check m6_no_capture_left_running bash -c '! pgrep -x tcpdump >/dev/null'
record m6_pcap_in_evidence true "$(stat -c '%s %n' "$e"/m6*.pcap 2>/dev/null | tr '\n' ';')"
ric_watchdog_stop
gate_finish

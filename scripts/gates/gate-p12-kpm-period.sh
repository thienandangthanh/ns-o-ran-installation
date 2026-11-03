#!/usr/bin/env bash
# Gate p12 (VM side; M10 runner step p12, run last): the KPM reporting period P and granularity G are model
# parameters that kpimon takes from its config and the agent honours (contract AC10, plan R-6). Topology as gate M6:
# the gnb:2 agent and ns-3 `--nMmWaveEnbNodes=1 --e2lteEnabled=false`, 10 simulated seconds at T = 100 ms.
#
#   a  kpimon at P = 1000, G = 100 (P = 10 T): the decoded wire carries one indication per 10 seqs with 10 measData
#      items (Format 1 and Format 2), whole periods only (p12-records-check.py), and Influx equals the IPC trace for
#      every seq (influx-vs-trace.py --every-seq); kpimon decodes every indication.
#   b  kpimon at P = 150: a period that is not a multiple of T sits in the event trigger, which covers the whole
#      subscription, so the agent answers RIC SUBSCRIPTION FAILURE with the cause pre-registered in plan R-6:
#      ricRequest / eventTriggerNotSupported (CauseRICrequest extension index 17 in E2AP v03.01).
#   c  kpimon restored to rung-config.json kpm.* (100/100); the restored subscription's period is decoded.
#
# Facts: recordsPerIndication, indicationsPerTenSeqs, influxEqualsIpcEverySeq, nonMultipleSubscriptionFailure,
# subscriptionFailureCause, restoredPeriodMs. Knobs: SUB_WAIT_S (240), DRAIN_S (8), M4_WORKDIR.
source "$(dirname "$0")/lib.sh"
gate_init p12
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"

SUB_WAIT_S="${SUB_WAIT_S:-240}"
DRAIN_S="${DRAIN_S:-8}"
SIMTIME=10
PERIOD=0.1
T_MS=100
P_MULTI_MS=1000
P_BAD_MS=150
CAUSE_EVENT_TRIGGER_NOT_SUPPORTED="ricRequest:17"
NODES="gnb:2"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
G_MS=$(python3 -I "$CFG" get kpm.granularityPeriodMs)
WORK="$HOME/p12-work"
e="$EVIDENCE_DIR"
mkdir -p "$WORK"
ric_watchdog_bg

################################################################################
# prerequisites
################################################################################
check p12_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check p12_build_tools_present agents_ensure_build_tools
check p12_sctp_module_loaded_and_persisted agents_sctp_module
check p12_ns3_binary_located agents_ns3_locate
check p12_kubectl_exec_it_works_without_tty kubectl_exec_it_probe
fact granularityPeriodMs "$G_MS"

# kpimon_config_periods <P> <G>: the deployed kpimon config carries the period and granularity it was installed with.
kpimon_config_periods() {
    kc -n "$KPIMON_NS" get configmaps -o json >"$WORK/cm.json" 2>&1 || return 1
    python3 -I - "$WORK/cm.json" "$1" "$2" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))["items"]
want = (int(sys.argv[2]), int(sys.argv[3]))
seen = []
for cm in items:
    if "kpimon" not in cm["metadata"]["name"]:
        continue
    for k, v in (cm.get("data") or {}).items():
        try:
            c = json.loads(v)
        except ValueError:
            continue
        ctl = c.get("controls", {}) if isinstance(c, dict) else {}
        if "reportingPeriodMs" in ctl or "granularityPeriodMs" in ctl:
            seen.append((cm["metadata"]["name"], k, ctl.get("reportingPeriodMs"), ctl.get("granularityPeriodMs")))
print("kpimon config periods (configmap, key, P, G): %s, want P %d G %d" % (seen, *want))
sys.exit(0 if seen and all((p, g) == want for _, _, p, g in seen) else 1)
PY
}

# kpimon_at <tag> <P|""> <G|"">: reinstall kpimon with the period and granularity (empty: rung-config.json kpm.*).
kpimon_at() {
    local tag="$1" p="$2" g="$3" install_start wp wg
    wp="${p:-$(python3 -I "$CFG" get kpm.reportingPeriodMs)}"; wg="${g:-$G_MS}"
    check "p12_${tag}_kpimon_uninstalled" kpimon_uninstall
    install_start=$(date +%s)
    if [ -n "$p" ]; then export KPIMON_REPORTING_PERIOD_MS="$p" KPIMON_GRANULARITY_PERIOD_MS="$g"
    else unset KPIMON_REPORTING_PERIOD_MS KPIMON_GRANULARITY_PERIOD_MS; fi
    check "p12_${tag}_kpimon_installed_p${wp}_g${wg}" kpimon_install_retry true "$e/install-$tag.log"
    unset KPIMON_REPORTING_PERIOD_MS KPIMON_GRANULARITY_PERIOD_MS
    check "p12_${tag}_kpimon_pod_ready_after_install" kpimon_wait_ready 300 "$install_start"
    check "p12_${tag}_kpimon_config_carries_p${wp}_g${wg}" kpimon_config_periods "$wp" "$wg"
}

# wait_wire <pcap> <successful|unsuccessful>: a RIC subscription request and an answer of that kind on the wire.
wait_wire() {
    local pcap="$1" kind="$2" deadline=$(($(date +%s) + SUB_WAIT_S)) c
    while [ "$(date +%s)" -lt "$deadline" ]; do
        c=$(tshark -r "$pcap" -d sctp.port==36422,e2ap -Y 'e2ap.procedureCode == 8' -T fields \
            -e e2ap.initiatingMessage_element -e "e2ap.${kind}Outcome_element" 2>/dev/null |
            awk -F'\t' '{ if ($1 != "") i++; if ($2 != "") o++ } END { print i + 0, o + 0 }')
        echo "wire RICsubscription (requests ${kind}Outcomes): $c"
        [ "${c% *}" -ge 1 ] && [ "${c#* }" -ge 1 ] && return 0
        sleep 3
    done
    return 1
}

# agents_up <tag> <pcap-label>: capture first, then the agent; sets CAP_T0.
agents_up() {
    check "p12_${1}_capture_started_before_agents" capture_start "$2" docker0 'ip proto 132'
    CAP_T0=$(date +%s)
    check "p12_${1}_bringup_agents_connected_set_exact" gate_bringup agents "$NODES"
    echo '{"2":[]}' >"$e/$2-node-ips.json"
    check "p12_${1}_agent_container_ip_recorded" agents_record_ips "$e/$2-node-ips.json"
}

################################################################################
# a: P = 10 T, G = T
################################################################################
kpimon_at a "$P_MULTI_MS" "$G_MS"
SODIR="$WORK/so-a"
check p12_a_kpimon_so_extracted_from_image kpimon_extract_so "$SODIR"
agents_up a p12-a
check p12_a_wire_subscription_request_and_response wait_wire "$e/p12-a.pcap" successful
RUN="$e/ns3run-a"; mkdir -p "$RUN"
INFLUX_FROM=$(date +%s)
check p12_a_ns3_started_single_gnb ns3_start "$RUN" --nMmWaveEnbNodes=1 --e2lteEnabled=false "--simTime=$SIMTIME" \
    "--indicationPeriodicity=$PERIOD" "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 "--e2TraceDir=$RUN"
check p12_a_ns3_completes_exit0 ns3_wait
log "draining ${DRAIN_S}s"; sleep "$DRAIN_S"
agents_stats_last ns3-e2-agent-2 >"$e/p12-a-agent-stats-final.json"
kpimon_window() { kpimon_logs_since "$CAP_T0" "$e/p12-a-kpimon.log" && kpimon_log_window_summary "$e/p12-a-kpimon.log"; }
check p12_a_kpimon_log_window_complete kpimon_window
check p12_a_influx_exported influx_export p12-a "$INFLUX_FROM"
check p12_a_agents_stopped agents_stop
check p12_a_capture_stopped capture_stop p12-a

sub_a() { pcap_facts "$e/p12-a.pcap" p12-a-sub && python3 -I "$E2EV/e2-facts-query.py" "$e/p12-a-sub-facts.json" sub-period --period-ms "$P_MULTI_MS" --after "$CAP_T0"; }
check p12_a_decoded_subscription_period_1000_answered sub_a
records_a() {
    local pl="$HARNESS_TOOLS/pcap-to-lines.py" h="$SODIR/kpimon-decode-harness"
    python3 -I "$pl" "$e/p12-a.pcap" >"$e/p12-a-lines.txt" || return 1
    LD_LIBRARY_PATH="$SODIR" "$h" --records <"$e/p12-a-lines.txt" >"$e/p12-a-records.jsonl" 2>"$e/p12-a-records.stderr" || return 1
    python3 -I "$HARNESS_DIR/scripts/gates/p12-records-check.py" "$e/p12-a-records.jsonl" --map "$AGENT_DIR/schema/metric-map.v1.json" \
        --trace "$RUN/e2-ipc-trace-2.jsonl" --per-indication $((P_MULTI_MS / T_MS)) --out "$e/p12-a-records-check.json"
}
check p12_a_one_indication_per_10_seqs_with_10_records records_a
kpimon_decoded_all() {
    local k w hw mw
    k=$(kpimon_log_counts "$e/p12-a-kpimon.log" | kv indications); hw=$(kpimon_log_counts "$e/p12-a-kpimon.log" | kv hdr_wmore)
    mw=$(kpimon_log_counts "$e/p12-a-kpimon.log" | kv msg_wmore); w=$(grep -c . "$e/p12-a-lines.txt")
    echo "kpimon indications $k, wire indications $w, header/message RC_WMORE $hw/$mw"
    [ "$w" -gt 0 ] && [ "$k" = "$w" ] && [ "$hw" -eq 0 ] && [ "$mw" -eq 0 ]
}
check p12_a_kpimon_logged_every_wire_indication_zero_wmore kpimon_decoded_all
check p12_a_influx_equals_ipc_trace_every_seq python3 -I "$E2EV/influx-vs-trace.py" --every-seq \
    --map "$AGENT_DIR/schema/metric-map.v1.json" --trace "$RUN/e2-ipc-trace-2.jsonl" --influx-cell "$e/p12-a-influx-cell.csv" \
    --influx-ue "$e/p12-a-influx-ue.csv" --out "$e/p12-a-influx-vs-trace.json"
check p12_a_emitter_bye_sent_equals_built_zero_drops python3 -I "$E2EV/trace-facts.py" "$RUN/e2-ipc-trace-2.jsonl" --require-clean \
    --expect-nodes 2 --out "$e/p12-a-trace-facts.json"
NSAMPLES=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["samples"])' "$e/p12-a-trace-facts.json" 2>/dev/null || echo 0)
# the samples of the period still open at bye are not reported: n mod (P / T)
check p12_a_agent_counters_forwarded_plus_unreported_equal_trace agent_counters_assert "$e/p12-a-agent-stats-final.json" \
    "$NSAMPLES" "$((NSAMPLES % (P_MULTI_MS / T_MS)))"
jf() {   # jf <json-file> <dotted.key>: the value as JSON, null when absent
    python3 -I - "$1" "$2" 2>/dev/null <<'PY' || echo null
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    v = v[k]
print(json.dumps(v))
PY
}
fact recordsPerIndication "$(jf "$e/p12-a-records-check.json" recordsPerIndication)"
fact indicationsPerTenSeqs "$(jf "$e/p12-a-records-check.json" indicationsPerTenSeqs)"
fact unreportedAtBye "$(jf "$e/p12-a-records-check.json" nodes.2.unreportedAtBye)"
fact influxEqualsIpcEverySeq "$(jf "$e/p12-a-influx-vs-trace.json" all.every_seq_equal)"

################################################################################
# b: P = 150 (not a multiple of T) -> RIC SUBSCRIPTION FAILURE
################################################################################
kpimon_at b "$P_BAD_MS" "$G_MS"
agents_up b p12-b
check p12_b_wire_subscription_request_and_failure wait_wire "$e/p12-b.pcap" unsuccessful
sleep 6   # the agent prints a stats line every 5 s
agents_stats_last ns3-e2-agent-2 >"$e/p12-b-agent-stats-final.json"
refused() { python3 -I -c 'import json,sys; s=json.loads(open(sys.argv[1]).read()); print("subs %s, subsRefused %s" % (s["subs"], s["e2"]["subsRefused"])); sys.exit(0 if s["subs"] == 0 and s["e2"]["subsRefused"] >= 1 else 1)' "$e/p12-b-agent-stats-final.json"; }
check p12_b_agent_counts_the_refused_subscription_and_holds_none refused
check p12_b_agents_stopped agents_stop
check p12_b_capture_stopped capture_stop p12-b
sub_b() {
    pcap_facts "$e/p12-b.pcap" p12-b-sub &&
        python3 -I "$E2EV/e2-facts-query.py" "$e/p12-b-sub-facts.json" sub-period --period-ms "$P_BAD_MS" --after "$CAP_T0" | head -n 1
    python3 -I "$E2EV/e2-facts-query.py" "$e/p12-b-sub-facts.json" sub-failure --cause "$CAUSE_EVENT_TRIGGER_NOT_SUPPORTED" --after "$CAP_T0" &&
        SUB_B_FAILURE=true
}
SUB_B_FAILURE=false
check p12_b_decoded_subscription_failure_cause_event_trigger_not_supported sub_b
fact nonMultipleSubscriptionFailure "$SUB_B_FAILURE"
fact subscriptionFailureCause "$(python3 -I -c 'import json,sys; print(json.dumps(sorted({f["cause_label"] for f in json.load(open(sys.argv[1]))["sub_failures"]}, key=str)))' "$e/p12-b-sub-facts.json" 2>/dev/null || echo null)"

################################################################################
# c: restore rung-config.json kpm.* and decode the restored subscription
################################################################################
kpimon_at c "" ""
agents_up c p12-c
check p12_c_wire_subscription_request_and_response wait_wire "$e/p12-c.pcap" successful
check p12_c_agents_stopped agents_stop
check p12_c_capture_stopped capture_stop p12-c
check p12_c_restored_subscription_period_decoded kpm_sub_period_check "$e/p12-c.pcap" p12-c-sub "$CAP_T0"
fact restoredPeriodMs "$(python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1]))["sub_requests"]; print(json.dumps(sorted({x["reporting_period_ms"] for x in r}, key=str)[-1] if r else None))' "$e/p12-c-sub-facts.json" 2>/dev/null || echo null)"

################################################################################
# hygiene
################################################################################
check p12_no_stray_ns3_agent_process_or_3847x_listener agents_hygiene
check p12_no_capture_left_running bash -c '! pgrep -x tcpdump >/dev/null'
record p12_pcaps_in_evidence true "$(stat -c '%s %n' "$e"/p12-*.pcap 2>/dev/null | tr '\n' ';')"
ric_watchdog_stop
gate_finish

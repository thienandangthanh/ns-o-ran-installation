#!/usr/bin/env bash
# Gate M5 (VM side): one E2 agent (gnb:2) sets up against the L-release RIC.
#
# Flow (every step is a named check; every wait is bounded; re-runnable):
#   1. ~/nist at $TESTBED_SHA with ns3_e2_agent/; tools; sctp module; kpimon's patched .so extracted from the image
#   2. capture on docker0 (`ip proto 132`) BEFORE the agents start: Wireshark learns the E2SM mapping only from E2Setup
#   3. gate_bringup agents gnb:2 (RIC ready + e2term registered, kpm_sim stopped, image, agent, CONNECTED set exact)
#   4. e2mgr node check, agent stats, RAN function definition through kpimon's own library (--ranfunc)
#   5. stop agents, e2mgr must show DISCONNECTED or ABSENT, stop capture, tshark decode of the wire
#
# Wire facts are tshark's (E2AP dissector, -d sctp.port==36422,e2ap); the RAN function definition is decoded by
# kpimon's libe2smwrapper.so (the .so extracted from the patched kpimon image, see M3), never by log lines.
#
# Knobs: AGENTS_CONNECT_TIMEOUT_S (300), DISCONNECT_WAIT_S (120), STATS_WAIT_S (60).
source "$(dirname "$0")/lib.sh"
gate_init m5
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"

DISCONNECT_WAIT_S="${DISCONNECT_WAIT_S:-120}"
STATS_WAIT_S="${STATS_WAIT_S:-60}"
NODES="gnb:2"
NODE_NAME=gnb_001_001_00000002
SODIR="$HOME/m5-work/so"
e="$EVIDENCE_DIR"
mkdir -p "$SODIR"
ric_watchdog_bg

################################################################################
# 1. prerequisites
################################################################################
check m5_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check m5_build_tools_present agents_ensure_build_tools
check m5_sctp_module_loaded_and_persisted agents_sctp_module
check m5_kpimon_so_extracted_from_image kpimon_extract_so "$SODIR"
so_size8() { echo "TimeStamp SIZE in the extracted .so: $(harness_so_size "$SODIR")"; [ "$(harness_so_size "$SODIR")" = 8 ]; }
check m5_kpimon_so_is_the_size8_patched_build so_size8
cp "$SODIR/provenance.txt" "$e/kpimon-so-provenance.txt" 2>/dev/null

################################################################################
# 2-3. capture first, then the agent
################################################################################
check m5_capture_started_before_agents capture_start m5 docker0 'ip proto 132'
check m5_bringup_agents_kpm_sim_stopped_connected_set_exact gate_bringup agents "$NODES"

################################################################################
# 4. e2mgr, agent stats, RAN function definition
################################################################################
check m5_e2mgr_node_connected_name_plmn_gnbid e2mgr_node_check "$NODE_NAME" 00F110 2
record m5_agent_image_informational true "$(tr '\n' ' ' <"$e/agent-image.env" 2>/dev/null)"

agent_ready() {
    local deadline=$(($(date +%s) + STATS_WAIT_S)) line
    while [ "$(date +%s)" -lt "$deadline" ]; do
        line=$(agents_stats_last ns3-e2-agent-2)
        if echo "$line" | python3 -I -c '
import json, sys
s = json.loads(sys.stdin.read())
sys.exit(0 if s["state"] == "READY" and s["setupFuncAccepted"] and s["e2"]["setups"] >= 1 and s["e2"]["rxPduUndecodable"] == 0 else 1)' 2>/dev/null; then
            echo "$line" >"$e/agent-stats-ready.json"; echo "$line"; return 0
        fi
        sleep 3
    done
    echo "no READY stats line within ${STATS_WAIT_S}s; last: ${line:-none}"; return 1
}
check m5_agent_stats_line_connected_ready_setup_accepted agent_ready

ranfunc_ok() {
    ranfunc_decode "$e/e2mgr-node-$NODE_NAME.json" "$SODIR" "$e/m5-ranfunc-harness.jsonl" || return 1
    python3 -I "$E2EV/ranfunc-check.py" "$e/m5-ranfunc-harness.jsonl" \
        --map "$AGENT_DIR/schema/metric-map.v1.json" --kind gnb --oid "$E2AP_OID_KPM" --short-name "$E2AP_SHORT_NAME" \
        --map-sha256 "$(sha256sum "$AGENT_DIR/schema/metric-map.v1.json" | cut -d' ' -f1)"
}
check m5_ranfunc_definition_decodes_clean_via_kpimon_lists_equal_map_sha8 ranfunc_ok

################################################################################
# 5. teardown, then the wire
################################################################################
node_disconnected() {
    local deadline=$(($(date +%s) + DISCONNECT_WAIT_S)) st
    while [ "$(date +%s)" -lt "$deadline" ]; do
        st=$(e2mgr_node_status "$NODE_NAME")
        case "$st" in DISCONNECTED|ABSENT) echo "e2mgr shows $NODE_NAME: $st"; return 0 ;; esac
        sleep 3
    done
    echo "e2mgr still shows $NODE_NAME: $st after ${DISCONNECT_WAIT_S}s"; return 1
}
check m5_agents_stopped_no_container_left agents_stop
check m5_e2mgr_node_disconnected_or_removed_after_stop node_disconnected
sleep 3
check m5_capture_stopped capture_stop m5
check m5_pcap_facts_extracted pcap_facts "$e/m5.pcap" m5

setup_req() {
    python3 -I "$E2EV/e2-facts-query.py" "$e/m5-facts.json" setup-request --func-id 2 --oid "$E2AP_OID_KPM" \
        --short-name "$E2AP_SHORT_NAME" --gnb-id 2 --plmn 00f110 --not-gnb-id-hex B5C67788
}
check m5_tshark_setup_request_func2_oid_shortname_gnbid2_not_kpm_sim setup_req
check m5_tshark_setup_response_accepts_func2 python3 -I "$E2EV/e2-facts-query.py" "$e/m5-facts.json" setup-response --func-id 2
distinct_from_ref() {
    python3 -I - "$e/m5-facts.json" <<'PY'
import json, sys
f = json.load(open(sys.argv[1]))
ids = [r["gnb_id"] for r in f["setup_requests"]]
ref = 0xB5C67788
print("gNB-IDs on the wire: %s (reference node: %d / %d)" % (ids, ref, ref >> 3))
sys.exit(0 if ids and all(i not in (ref, ref >> 3) for i in ids) else 1)
PY
}
check m5_gnb_id_differs_from_reference_node_b5c67788 distinct_from_ref

################################################################################
# hygiene
################################################################################
check m5_no_capture_left_running bash -c '! pgrep -x tcpdump >/dev/null'
no_agent_container() { [ -z "$(dk ps -aq --filter label=ns3e2.agent=1)" ]; }
check m5_no_agent_container_left no_agent_container
record m5_pcap_in_evidence true "$(stat -c '%s %n' "$e"/m5.pcap 2>/dev/null)"
ric_watchdog_stop
gate_finish

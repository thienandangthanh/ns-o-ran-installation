#!/usr/bin/env bash
# Gate e2i (VM side): E2 interoperability of the agents' identity cluster, judged on the wire by an independent codec.
# Needs the asn1-indep image tarball in ~/asn1-indep/ (asn1-indep-<tag>.tar + SHA256SUMS, copied by the host).
#
#   gate-e2i-interop.sh --image-tag TAG
#
# Agents enb:1, gnb:2, gnb:3 set up against the RIC while the docker0 capture runs; the TS xApp is scaled to 0 for
# the injector part (its xapp-frame-cpp 2.3.6 frees a stray RIC control ack twice). Judged:
#   globalIds, ranFunctions, x2apRequestPartDecodes, style5Action3Announced, kpimonSubscribedAll
#        every node's E2 Setup Request and subscriptions on the wire (e2i-wire-checks.py setup: identity from the
#        tshark facts, the X2 request part and the RC RAN function definition decoded by tools/asn1-indep)
#   meids and nbIdBits   the CONNECTED set is meid_of each node (bring-up), e2mgr's records: en-gNBs GNB/EN_GNB with a
#        32-digit nbId and RAN functions 2 and 3, the eNB ENB/MACRO_ENB with a 20-digit nbId
#   independentTargetApplied   a RIC control encoded by tools/asn1-indep (target = the APER NR-CGI of gNB 3) sent by
#        the RIC control injector via en-gNB 2 in a lock-step run: on the wire once with those octets and acknowledged;
#        the ledger's only line applies it (imsi 6 -> cell 3) and ns-3 starts that handover (EnbHandoverStartStats)
#   n5FormRefused        the same control with the old 9-octet target 0000F1100000000303 via en-gNB 3: answered by a
#        FAILURE with cause control-message-invalid, never forwarded to ns-3
#   agentRcControlUnitTest   rc-control-test in the agent image: every case passes, the listed ones included
#   ppidPerNode70        every node's E2AP DATA chunks carry PPID 70
#   tsXappDownDuringInjector   no TS pod from before the injector's install to after the run
#   tsCellMap            the TS xApp, recreated after every agent is CONNECTED, lists every node; e2mgr's records
#        replayed through its parser give each en-gNB its key %08X10, the eNB none, and no key names another node
# The forks' image guards (ts_patches_check, rc_at_pin, the kpimon label) must pass first.
source "$(dirname "$0")/lib.sh"
gate_init e2i
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/ts-lib.sh"
source "$(dirname "$0")/rc-injector-lib.sh"

TAG=""
while [ $# -gt 0 ]; do
    case "$1" in --image-tag) TAG="$2"; shift 2 ;; *) log "unknown arg $1"; exit 2 ;; esac
done
[ -n "$TAG" ] || { log "--image-tag required"; exit 2; }
e="$EVIDENCE_DIR"; RUN="$e/run"
IMG="localhost/asn1-indep:$TAG"
NODES="enb:1,gnb:2,gnb:3"
EPOCH_MS=$(python3 -I "$HARNESS_DIR/scripts/gates/rung-config.py" get scenario.simStartEpochMs)
T_GATE_S=10; T_CTL_S=30; W_S=5; PACER_PORT=38499
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1 --outageThreshold=-1000)
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
WIRE="$HARNESS_DIR/scripts/gates/e2i-wire-checks.py"
UNIT_CASES=(nrcgi-applied-path n5-target-refused m8-capture-refused ran-function-id-invalid control-failed-to-execute
    format1-on-ack bye-fails-all-pending)
fact imageTag "$(json_str "$TAG")"
fact vmLoadStart "$(json_str "$(uptime)")"
record e2i_args true "nodes $NODES; asn1-indep $IMG; cli ${CLI[*]}; rc pin $RC_SHA; TS pin $TS_SHA"
ric_watchdog_bg
# passed <check>: the named check is recorded as passed in this run (check itself always returns 0)
passed() { python3 -I -c 'import json,sys; sys.exit(0 if any(r["name"] == sys.argv[2] and r["pass"] for r in map(json.loads, open(sys.argv[1]))) else 1)' "$CHECKS_FILE" "$1"; }

image_loaded() {
    local d="$HOME/asn1-indep"
    (cd "$d" && sha256sum -c SHA256SUMS) || return 1
    dk load -i "$d/asn1-indep-$TAG.tar" && dk image inspect "$IMG" --format '{{.Id}}'
}
check e2i_asn1_indep_image_checksum_verified_and_loaded image_loaded
check e2i_independent_decoder_self_test dk run --rm --network=none -v "$HARNESS_DIR/scripts/gates:/gates:ro" "$IMG" \
    python3 /gates/e2i-wire-checks.py --decode-self-test
check e2i_wire_judge_self_test python3 -I "$WIRE" --self-test
check e2i_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check e2i_build_tools_present agents_ensure_build_tools
check e2i_sctp_module_loaded agents_sctp_module
check e2i_ns3_binary_located_at_pins agents_ns3_locate
check e2i_ts_tree_and_image_are_pin_plus_patch_set ts_patches_check
check e2i_rc_installed_at_pin_and_ready rc_at_pin
check e2i_kpimon_image_carries_its_patch_set_label kpimon_image_labelled true
check e2i_ric_reset_fresh_rc_kpimon_hw_go_and_bucket rc_ric_reset

################################################################################
# the injector part: TS xApp down, injector registered and routed
################################################################################
check e2i_ts_xapp_scaled_to_zero_and_deregistered ts_scale_down
check e2i_rmr_peer_image_built_and_self_tested rmr_peer_build
check e2i_injector_installed injector_install
check e2i_injector_registered xapp_ensure_registered "$INJECTOR_NAME"
check e2i_rtmgr_restarted_after_registration rc_restart_rtmgr
check e2i_injector_has_a_route_table injector_rmr_ready 180

check e2i_capture_started_before_agents capture_start e2i docker0 'ip proto 132'
check e2i_bringup_agents_connected_set_equals_meids gate_bringup agents "$NODES"
echo '{}' >"$e/node-ips.json"
check e2i_agent_container_ips_recorded agents_record_ips "$e/node-ips.json"
all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == 3) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check e2i_every_agent_ready_and_subscribed_by_kpimon all_subscribed
check e2i_e2mgr_en_gnb_2_record e2mgr_node_check "$(meid_of 2)" 00F110 2
check e2i_e2mgr_en_gnb_3_record e2mgr_node_check "$(meid_of 3)" 00F110 3
check e2i_e2mgr_enb_1_record_x2_to_en_gnbs_2_3 e2mgr_enb_check "$(meid_of 1)" 00F110 1 2 3
check e2i_route_dump_agents_subscribed rc_route_dump subscribed
check e2i_injector_routes_to_e2term_for_both_en_gnbs injector_routes_check subscribed "$(meid_of 2)" "$(meid_of 3)"

agent_unit_test() {
    local img n rc=0
    img=$(sed -n 's/^NS3_E2_AGENT_IMAGE=//p' "$e/agent-image.env")
    [ -n "$img" ] || { echo "no agent image recorded"; return 1; }
    dk run --rm --entrypoint /usr/local/bin/rc-control-test "$img" /usr/local/share/ns3-e2-agent/rc-control-requests.hex \
        /usr/local/share/ns3-e2-agent/rc-control-nrcgi.hex >"$e/rc-control-test.out" 2>"$e/rc-control-test.log" || rc=1
    grep -v '_HEX ' "$e/rc-control-test.out"
    # a case line is "PASS <name>" or "PASS <name>: <detail>"
    for n in "${UNIT_CASES[@]}"; do grep -qE "^PASS $n(:|$)" "$e/rc-control-test.out" || { echo "missing PASS $n"; rc=1; }; done
    grep -qx "rc-control-test: ok" "$e/rc-control-test.out" || rc=1
    return $rc
}
check e2i_agent_rc_control_unit_test_cause_paths agent_unit_test

# the controls, encoded by the independent codec (requestor 1001 tells them from rc's): one applied, one refused
encode_controls() {
    local j1 j2
    j1=$(dk run --rm --network=none -v "$HARNESS_DIR/scripts/probes:/probes:ro" "$IMG" python3 /probes/e2-probe-node.py \
        control --requestor 1001 --instance 1 --func 3 --imsi 6 --target-gnb 3) || return 1
    j2=$(dk run --rm --network=none -v "$HARNESS_DIR/scripts/probes:/probes:ro" "$IMG" python3 /probes/e2-probe-node.py \
        control --requestor 1001 --instance 2 --func 3 --imsi 6 --target-octets 0000F1100000000303) || return 1
    python3 -I - "$j1" "$j2" >"$e/injected.jsonl" <<'PY' || return 1
import json, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert a["targetHex"].upper() == "0000F1100000000310" and b["targetHex"].upper() == "0000F1100000000303", (a, b)
for tag, node, d, want in (("independent-target", 2, a, "ack"), ("n5-form", 3, b, "failure:control-message-invalid")):
    print(json.dumps({"tag": tag, "node": node, "hex": d["hex"], "headerHex": d["headerHex"],
                      "messageHex": d["messageHex"], "targetHex": d["targetHex"], "expect": want}))
PY
    cat "$e/injected.jsonl"
}
check e2i_controls_encoded_by_the_independent_codec encode_controls
schedule() {
    local h1 h2 a1 a2
    h1=$(sed -n 1p "$e/injected.jsonl" | jq -r .hex) && h2=$(sed -n 2p "$e/injected.jsonl" | jq -r .hex) || return 1
    a1=$(injector_send_argv "$(meid_of 2)" "$h1" | jq -R . | jq -sc .) || return 1
    a2=$(injector_send_argv "$(meid_of 3)" "$h2" | jq -R . | jq -sc .) || return 1
    jq -n --argjson a1 "$a1" --argjson a2 "$a2" '{steps: {"20": {trigger: {cmd: $a1}, expect: 1},
        "40": {trigger: {cmd: $a2}, expect: 0, absence: true}}, late: []}' >"$e/e2i-schedule.json" && cat "$e/e2i-schedule.json"
}
check e2i_schedule_written schedule
check e2i_ts_xapp_absent_before_the_run ts_absent
check e2i_pod_snapshot_before rc_pod_snapshot before

_wait_ready() { for _ in $(seq 50); do grep -q READY "$1" && return 0; sleep 0.2; done; echo "$2 did not start: $(cat "$1")"; return 1; }
_pacer_finish() { for _ in $(seq 150); do kill -0 "$1" 2>/dev/null || break; sleep 0.2; done; kill "$1" 2>/dev/null; wait "$1"; PACER_RC=$?; }
e2i_run() {
    local rd="$RUN" pp rc
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" --w "$W_S" \
        --schedule "$e/e2i-schedule.json" >"$rd/pacer.log" 2>&1 &
    pp=$!
    _wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    ns3_start "$rd/ns3run" "${CLI[@]}" "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 --e2TraceDir="$rd/trace" \
        --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" || { kill "$pp"; return 1; }
    ns3_wait; rc=$NS3_RC
    _pacer_finish "$pp"
    echo "e2i run: ns-3 exit $rc, pacer exit $PACER_RC (want 0 and 0)"
    [ "$rc" = 0 ] && [ "$PACER_RC" = 0 ]
}
check e2i_lockstep_run_with_two_injected_controls e2i_run
check e2i_ts_xapp_absent_after_the_run ts_absent
check e2i_pod_snapshot_after rc_pod_snapshot after
# the TS xApp was scaled to zero and deregistered before the injector part, and absent before and after the run
ts_down_during_injector() {
    local c rc=0
    for c in e2i_ts_xapp_scaled_to_zero_and_deregistered e2i_ts_xapp_absent_before_the_run e2i_ts_xapp_absent_after_the_run; do
        if passed "$c"; then echo "$c passed"; else echo "$c did not pass"; rc=1; fi
    done
    return $rc
}
check e2i_ts_xapp_down_during_injector ts_down_during_injector
fact tsXappDownDuringInjector "$(passed e2i_ts_xapp_down_during_injector && echo true || echo false)"
ledger_and_handover() {
    python3 -I - "$RUN/trace/e2-control-ledger.jsonl" "$RUN/ns3run/EnbHandoverStartStats.txt" <<'PY'
import json, sys
led = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][1:]
starts = [l.split() for l in open(sys.argv[2]) if len(l.split()) >= 5]
print("ledger:", [(x["viaNodeId"], x["imsi"], x["sourceCell"], x["targetCell"], x["outcome"]) for x in led])
print("handover starts (imsi, target):", [(int(p[1]), int(p[4])) for p in starts])
ok = (len(led) == 1 and (led[0]["viaNodeId"], led[0]["imsi"], led[0]["targetCell"], led[0]["outcome"]) == (2, 6, 3, "applied")
      and [(int(p[1]), int(p[4])) for p in starts] == [(6, 3)])
sys.exit(0 if ok else 1)
PY
}
check e2i_independent_target_applied_ledger_and_handover_start ledger_and_handover
check e2i_injector_logs_saved injector_logs_save e2i
check e2i_injector_uninstalled injector_uninstall

################################################################################
# the TS xApp again, recreated while every agent is CONNECTED
################################################################################
check e2i_ts_xapp_recreated_ready_and_registered ts_scale_up
check e2i_rtmgr_restarted_after_ts_registration rc_restart_rtmgr
check e2i_ts_xapp_nodeb_list_names_every_connected_node ts_nodeb_list_check
ts_cell_map() {
    local n
    for n in 1 2 3; do e2mgr_get "nodeb/$(meid_of "$n")" >"$e/e2mgr-node-$n.json" || return 1; done
    python3 -I "$HARNESS_DIR/scripts/gates/replay-ts-cell-map.py" "$e"/e2mgr-node-{1,2,3}.json \
        --expect 0000000210="$(meid_of 2)" --expect 0000000310="$(meid_of 3)" --no-key "$(meid_of 1)" --no-wrong-node
}
check e2i_ts_cell_map_en_gnb_keys_no_enb_key_no_wrong_node ts_cell_map

check e2i_restart_counts_zero rc_restarts_zero after
for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
    dk logs "$c" >"$e/agent-$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c").log" 2>&1
done
check e2i_agents_stopped agents_stop
check e2i_capture_stopped capture_stop e2i

################################################################################
# the wire, judged
################################################################################
check e2i_pcap_facts pcap_facts "$e/e2i.pcap" e2i
setup_wire() {
    python3 -I "$WIRE" setup "$e/e2i-facts.json" "$e/e2i.pcap" --node-ips "$e/node-ips.json" --out "$e/e2i-setup.json" \
        --decode-cmd "$(dk_cmd) run --rm -i --network=none -v $HARNESS_DIR/scripts/gates:/gates:ro $IMG python3 /gates/e2i-wire-checks.py decode"
}
check e2i_setup_requests_decoded_and_judged setup_wire
for name in globalIds ranFunctions x2apRequestPartDecodes style5Action3Announced kpimonSubscribedAll; do
    check "e2i_$name" python3 -I "$WIRE" verdict "$e/e2i-setup.json" "$name"
done
check e2i_injected_controls_on_the_wire_and_answered python3 -I "$WIRE" controls "$e/e2i.pcap" \
    --node-ips "$e/node-ips.json" --injected "$e/injected.jsonl" --out "$e/e2i-controls.json"
check e2i_ppid_per_node_70 python3 -I "$E2EV/e2-facts-query.py" "$e/e2i-facts.json" ppid --node-ips "$e/node-ips.json"
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

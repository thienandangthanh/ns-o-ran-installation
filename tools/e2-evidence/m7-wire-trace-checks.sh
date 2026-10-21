#!/usr/bin/env bash
# m7-wire-trace-checks.sh: the post-capture wire and ns-3 trace checks of gate M7, shared by
# scripts/gates/gate-m7-multignb.sh and tools/e2-evidence/replay-m7-analysis.sh (sourced, never executed).
#
# Caller provides: functions check <name> <cmd...> and record <name> <pass> <detail>; E2EV (this directory);
# F (fact sheet from e2ap-pcap-facts.py); Q ($E2EV/e2-facts-query.py); e (evidence dir, read: node-ips.json,
# recovery summary); W (writable dir for the timeline and trace-facts output); RUN (ns-3 e2TraceDir);
# SERVICE_IP; IDS (comma node ids); T_DEL; NS3_START_EPOCH.
#
# Attribution is by association (agent ip, source port), never by container IP: agent containers restart after the
# e2term delete and Docker hands their IPs out again in a different order. node-ips.json is only a cross-check.

m7_timeline_has() {
    python3 -I - "$W/m7-post-delete-timeline.json" "$@" <<'PY'
import json, sys
t = json.load(open(sys.argv[1])); fields = sys.argv[2:]
bad = [n for n, v in t.items() if any(v.get(f) is None for f in fields)]
print("%s: %s" % (",".join(fields), {n: [v.get(f) for f in fields] for n, v in sorted(t.items())}))
sys.exit(1 if bad or not t else 0)
PY
}

m7_new_ports() {
    python3 -I - "$W/m7-post-delete-timeline.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
print({n: (v["new_associations"], "old sports", v["old_sports"]) for n, v in sorted(t.items())})
sys.exit(0 if t and all(v["new_sports"] and not set(v["new_sports"]) & set(v["old_sports"]) for v in t.values()) else 1)
PY
}

# ns-3 emitter reconnects after the restarts (hello >= 1 per node), drops are expected and only recorded.
m7_trace_bye() {
    python3 -I "$E2EV/trace-facts.py" $(for i in ${IDS//,/ }; do echo "$RUN/e2-ipc-trace-$i.jsonl"; done) \
        --expect-nodes "$IDS" --reconnects-ok --out "$W/m7-trace-facts.json" || return 1
    python3 -I - "$W/m7-trace-facts.json" <<'PY'
import json, sys
n = json.load(open(sys.argv[1]))
d = {x["node"]: {"hello": x["hello"], "droppedDisconnected": (x["bye_msg"] or {}).get("droppedDisconnected"),
                 "droppedBackpressure": (x["bye_msg"] or {}).get("droppedBackpressure")} for x in n}
print("per-node hello and drops: %s; total droppedDisconnected %d (expected > 0 around the delete)" % (
    d, sum(v["droppedDisconnected"] or 0 for v in d.values())))
PY
}

m7_wire_trace_checks() {
    local nodeips="$e/node-ips.json"
    check m7_pcap_one_association_per_agent_distinct_ips_no_sport_collision python3 -I "$Q" "$F" assoc-start \
        --nodes "$IDS" --node-ips "$nodeips" --service-ip "$SERVICE_IP" --before "$T_DEL"
    check m7_no_sctp_abort_during_endurance_window python3 -I "$Q" "$F" no-abort --from "$NS3_START_EPOCH" --to "$T_DEL"
    record m7_sctp_abort_shutdown_around_delete_informational true "$(python3 -I "$Q" "$F" no-abort --from "$(python3 -c "print($T_DEL - 5)")" --to "$(python3 -c "print($T_DEL + 600)")" 2>&1 | head -c 1500 | tr '\n' ';')"
    check m7_wire_every_agent_init_goes_to_the_same_service_ip python3 -I "$Q" "$F" service-ip --nodes "$IDS" --node-ips "$nodeips" --service-ip "$SERVICE_IP"
    python3 -I "$Q" "$F" post-delete --nodes "$IDS" --node-ips "$nodeips" --service-ip "$SERVICE_IP" --after "$T_DEL" --func-id 2 \
        --timeline-out "$W/m7-post-delete-timeline.json" >"$W/m7-post-delete-query.txt" 2>&1
    check m7_wire_new_association_per_node_new_source_port m7_new_ports
    check m7_wire_new_e2setup_request_and_response_per_node m7_timeline_has setup_request_s setup_response_s
    check m7_wire_new_ricsubscription_request_and_response_per_node m7_timeline_has sub_request_s sub_response_s
    check m7_wire_first_indication_after_delete_per_node m7_timeline_has first_indication_s
    record m7_per_node_time_to_connected_and_first_indication_informational true "wire (s after T_del): $(tr -d ' \n' <"$W/m7-post-delete-timeline.json"); poll bound: $(tr -d ' \n' <"$e/m7-recovery-poll-summary.json" 2>/dev/null)"
    check m7_per_node_ricindications_on_the_wire python3 -I "$Q" "$F" indications --nodes "$IDS" --node-ips "$nodeips"
    check m7_ns3_bye_ipc_dropped_recorded_per_node m7_trace_bye
}

#!/usr/bin/env bash
# ts-rung-lib.sh: the per-run body shared by the TS xApp rungs (gate r2 with the stub QP's fixed table, gate r3p
# with the harness predictor). Source after lib.sh, bringup.sh, capture.sh, kpimon.sh, agents.sh, rc-lib.sh,
# ts-lib.sh, paced-lib.sh and influx-dump.sh; the gate sets RUNG (the check-name prefix), e, RUNS, NODES, PACER,
# PACER_PORT, T_CTL_S, W_S, CLI, EPOCH_MS, T_GATE_S, RC_DEC_TAG, N_POS and defines the hooks named at rung_live.
# shellcheck disable=SC2154  # e, RUNS, RUNG and the rest are set by the sourcing gate
all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == 3) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}

# agent logs after ns-3 said bye: the agent prints its stats every 5 s, so wait for a stats line with ipc.bye >= 1
agent_logs_after_bye() {
    local rd="$1" c n deadline=$(($(date +%s) + 15))
    for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
        n=$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c")
        while :; do
            dk logs "$c" >"$rd/agent-$n.log" 2>&1
            python3 -I - "$rd/agent-$n.log" <<'PY' && break
import json, sys
last = None
for l in open(sys.argv[1], errors="replace"):
    if l.startswith('{"event":"stats"'):
        last = json.loads(l)
sys.exit(0 if last and last["ipc"]["bye"] >= 1 else 1)
PY
            [ "$(date +%s)" -lt "$deadline" ] || { echo "agent $n: no stats line after bye within 15 s"; return 1; }
            sleep 1
        done
    done
    echo "every agent logged its stats after bye"
}

route_owner_row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${ROUTE_OWNER_12041:-}" "${ROUTE_OWNER_12042:-}" \
        "${ROUTE_OWNER_E2TERM_12041:-}" "${ROUTE_OWNER_E2TERM_12042:-}" >>"$e/route-owners.tsv"
}

# rung_live <label> [--dump]: one run from a fresh RIC state; the per-run checks. The gate defines the hooks
#   rung_stub_setup <label> <rd>   loads or resets the stub and sets RUN_SCHEDULE (the pacer schedule of this run)
#   rung_judges <label> <rd>       the rung's own judges of the run (outcomes, wire requests, stub exchanges)
rung_live() {
    local label="$1" dump="${2:-}" rd="$RUNS/$1" pp rc cap_t0
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace" "$rd/extra"
    check "${RUNG}_${label}_ric_reset_fresh_pods_and_bucket" rc_ric_reset "$label"
    check "${RUNG}_${label}_capture_started_before_agents" capture_start "$label" docker0 'ip proto 132'
    cap_t0=$(date +%s)
    check "${RUNG}_${label}_agents_connected_set_exact" gate_bringup agents "$NODES"
    echo '{}' >"$rd/node-ips.json"
    check "${RUNG}_${label}_agent_ips_recorded" agents_record_ips "$rd/node-ips.json"
    check "${RUNG}_${label}_every_agent_ready_and_subscribed" all_subscribed
    check "${RUNG}_${label}_ts_and_stub_pods_fresh_after_agents_rtmgr_sessions" ts_stub_pods_reset "$label"
    check "${RUNG}_${label}_rc_rmr_ready_after_rtmgr_restart" rc_rmr_ready_after_rtmgr
    check "${RUNG}_${label}_ts_xapp_nodeb_list_has_every_connected_agent" ts_nodeb_list_check
    check "${RUNG}_${label}_route_dump_start" rc_route_dump "$label-start"
    route_owner_row "$label" start
    check "${RUNG}_${label}_routes_30002_20010_to_ts_30000_only_to_stub" ts_routes_check "$label-start"
    check "${RUNG}_${label}_a1_threshold_set_and_logged_by_the_ts_xapp" ts_policy_set "$A1_TH" "r2-$label-$GATE_TS"
    fact "a1ThresholdAttempt_$label" "$(cat "$e/r2-$label-$GATE_TS-a1-attempt.txt" 2>/dev/null || echo null)"
    fact "a1DeliveredAttempt_$label" "$(cat "$e/r2-$label-$GATE_TS-a1-delivered-attempt.txt" 2>/dev/null || echo null)"
    check "${RUNG}_${label}_a1mediator_connection_to_ts_xapp_clean" a1_ts_connection_check "$label"
    fact "a1mediatorRestart_$label" "$(jq -c '{fresh, problems}' "$e/$label-a1mediator-restart.json" 2>/dev/null || echo null)"
    rung_stub_setup "$label" "$rd"
    check "${RUNG}_${label}_injector_started" injector_start "$rd/injector"
    check "${RUNG}_${label}_pods_snapshot_before" rc_pod_snapshot "$label-before"
    run_it() {
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" --w "$W_S" --schedule "$RUN_SCHEDULE" >"$rd/pacer.log" 2>&1 &
        pp=$!
        paced_wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
        ns3_start "$rd/ns3run" "${CLI[@]}" --RngRun=1 "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 \
            --e2TraceDir="$rd/trace" --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" || { kill "$pp"; return 1; }
        ns3_wait; rc=$NS3_RC
        paced_pacer_finish "$pp"
        echo "$rc" >"$rd/ns3-exit"
        echo "$label: ns-3 exit $rc, pacer exit $PACER_RC (want 0 and 0)"
        [ "$rc" = 0 ] && [ "$PACER_RC" = 0 ]
    }
    check "${RUNG}_${label}_lockstep_run_exits_clean" run_it
    check "${RUNG}_${label}_pods_snapshot_after" rc_pod_snapshot "$label-after"
    check "${RUNG}_${label}_route_dump_end" rc_route_dump "$label-end"
    route_owner_row "$label" end
    check "${RUNG}_${label}_restart_counts_zero_rc_ts_stub_kpimon_hw_go_agents" rc_restarts_zero "$label-after"
    check "${RUNG}_${label}_stub_log_saved" stub_log_save "$rd/stub-log.json"
    check "${RUNG}_${label}_injector_stopped" injector_stop "$rd/injector"
    check "${RUNG}_${label}_agent_logs_with_stats_after_bye" agent_logs_after_bye "$rd"
    if [ "$dump" = --dump ]; then
        dump_it() { influx_dump "$rd/influx-kpimon.csv"; }
        check "${RUNG}_${label}_influx_dump_written_without_the_token" dump_it
    fi
    check "${RUNG}_${label}_agents_stopped" agents_stop
    check "${RUNG}_${label}_capture_stopped" capture_stop "$label"
    kpimon_window() { kpimon_logs_since "$cap_t0" "$rd/kpimon.log" && kpimon_log_window_summary "$rd/kpimon.log"; }
    check "${RUNG}_${label}_kpimon_log_window_complete" kpimon_window
    wmore0() { local c; c=$(kpimon_log_counts "$rd/kpimon.log"); echo "$c" | tr '\n' ' '; echo "$c" | awk -F= '($1=="hdr_wmore"||$1=="msg_wmore") && $2!=0 {bad=1} END{exit bad}'; }
    check "${RUNG}_${label}_kpimon_zero_rc_wmore" wmore0
    extract() {
        python3 -I "$HARNESS_DIR/tools/e2-evidence/wire-c1-extract.py" "$e/$label.pcap" --node-ips "$rd/node-ips.json" \
            --ledger "$rd/trace/e2-control-ledger.jsonl" --out-dir "$rd/extra" --t0 "$cap_t0" \
            --decode-cmd "$(dk_cmd) run --rm -i $RC_DEC_TAG" --expect-requests "$N_POS" --expect-agent-local 0
    }
    check "${RUNG}_${label}_wire_one_terminal_answer_per_request_joined_to_ledger" extract
    # KPM continuity after the second rtmgr restart: kpimon decoded every indication on the wire
    kpm_cont() {
        local k w
        k=$(kpimon_log_counts "$rd/kpimon.log" | sed -n 's/^indications=//p')
        w=$(python3 -I -c 'import json,sys; print(sum(json.load(open(sys.argv[1]))["kpmHeadersByNode"].values()))' "$rd/extra/c1-extract-summary.json")
        echo "kpimon indications $k, wire indications $w"
        [ -n "$k" ] && [ "$k" = "$w" ] && [ "$k" -gt 0 ]
    }
    check "${RUNG}_${label}_kpm_continuity_kpimon_equals_wire_indications" kpm_cont
    c2() { python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$rd/trace/e2-control-ledger.jsonl" "$rd/pacer/pacer-log.jsonl" --expect "$N_POS"; }
    check "${RUNG}_${label}_c2_ledger" c2
    check "${RUNG}_${label}_c9_handover_rows_match_applied_lines" python3 -I "$HARNESS_DIR/scripts/gates/check-c9-handover-trace.py" "$rd"
    kpm_moves() {
        python3 -I "$HARNESS_DIR/tools/e2-evidence/kpm-ue-list-moves.py" "$e/$label.pcap" --node-ips "$rd/node-ips.json" \
            --ledger "$rd/trace/e2-control-ledger.jsonl" --epoch-ms "$EPOCH_MS" --t0 "$cap_t0" --out "$rd/kpm-ue-moves.json"
    }
    check "${RUNG}_${label}_kpm_ue_lists_move_applied_and_keep_refused" kpm_moves
    one_connection() {
        python3 -I - "$rd" <<'PY'
import glob, json, re, sys
rd = sys.argv[1]
em = re.findall(r"E2IPC node (\d+) \(\w+\) .*droppedDisconnected=(\d+) .*connects=(\d+)", open(rd + "/ns3run/stderr.txt").read())
bad = [m for m in em if m[1] != "0" or m[2] != "1"]
acc = {}
for f in sorted(glob.glob(rd + "/agent-*.log")):
    last = None
    for l in open(f, errors="replace"):
        if l.startswith('{"event":"stats"'):
            last = json.loads(l)
    acc[f.rsplit("-", 1)[1][:-4]] = last["ipc"]["accepted"] if last else None
print("emitters", em, "agents ipc.accepted", acc)
sys.exit(0 if len(em) == 3 and not bad and len(acc) == 3 and all(v == 1 for v in acc.values()) else 1)
PY
    }
    check "${RUNG}_${label}_one_connection_per_emitter_and_agent" one_connection
    agent_c2() {
        python3 -I - "$rd" <<'PY' | tee "$rd/agent-c2.json"
import glob, json, sys
rd = sys.argv[1]
per = {}
for f in sorted(glob.glob(rd + "/agent-*.log")):
    last = None
    for l in open(f, errors="replace"):
        if l.startswith('{"event":"stats"'):
            last = json.loads(l)
    r = last["rc"]
    per[f.rsplit("-", 1)[1][:-4]] = {k: r[k] for k in ("rx", "forwarded", "rejFunc", "rejDecode", "rejAction", "rejIpcDown",
                                                       "failedOnBye", "ackTx", "failTx", "pending")}
static = sum(v["rejFunc"] + v["rejDecode"] + v["rejAction"] + v["rejIpcDown"] for v in per.values())
post_bye = sum(v["failedOnBye"] for v in per.values())
pending = sum(v["pending"] for v in per.values())
print(json.dumps({"staticRejects": static, "postBye": post_bye, "pending": pending, "perAgent": per}))
sys.exit(0 if static == 0 and post_bye == 0 and pending == 0 else 1)
PY
    }
    check "${RUNG}_${label}_agent_static_rejects_zero_post_bye_zero" agent_c2
    rung_judges "$label" "$rd"
}

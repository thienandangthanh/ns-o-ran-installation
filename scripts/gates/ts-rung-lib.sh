#!/usr/bin/env bash
# ts-rung-lib.sh: the per-run body shared by the TS xApp rungs (gate r2 with the stub QP's fixed table, gate r3p
# with the harness predictor). Source after lib.sh, bringup.sh, capture.sh, kpimon.sh, agents.sh, rc-lib.sh,
# ts-lib.sh, paced-lib.sh and influx-dump.sh; the gate sets RUNG (the check-name prefix), e, RUNS, NODES, PACER,
# PACER_PORT, T_CTL_S, W_S, CLI, EPOCH_MS, T_GATE_S, RC_DEC_TAG, N_POS and defines the hooks named at rung_live.
# shellcheck disable=SC2154,SC2034  # e, RUNS, RUNG and the rest are set by the sourcing gate; PACERX is read by paced-lib.sh
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

# rung_c1: C1 after the three live runs: the replay without the RIC, the --RngRun=2 replay, C2/C7 on it, the
# three live runs equal on every component, the replay equal to live1 and RngRun 2 different from it.
rung_c1() {
    PACERX=(--replay "$RUNS/live1/trace/e2-control-ledger.jsonl")
    check ${RUNG}_replay_run_without_the_ric paced_null_run replay lockstep 0 --RngRun=1
    check ${RUNG}_rng2_run_without_the_ric paced_null_run rng2 lockstep 0 --RngRun=2
    PACERX=()
    rng2_c2() { python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$RUNS/rng2/trace/e2-control-ledger.jsonl" "$RUNS/rng2/pacer/pacer-log.jsonl"; }
    check ${RUNG}_rng2_c2_holds rng2_c2
    rng2_c7() {
        python3 -I - "$RUNS/rng2" <<'PY' | tee "$e/rng2-c7.json"
import json, sys
rd = sys.argv[1]
late = sum(1 for l in list(open(rd + "/trace/e2-control-ledger.jsonl"))[1:] if l.strip() and json.loads(l).get("cause") == "late")
no_sub, slack = 0, None
for l in open(rd + "/trace/e2-pacing-log.jsonl"):
    m = json.loads(l)
    if m.get("type") == "step":
        no_sub = max(no_sub, m.get("droppedNoSub", 0))
    if m.get("type") == "barrier" and m["seq"] != -1 and m["stepsWaitS"] >= 0:
        s = round(m["timeoutS"] - m["stepsWaitS"], 6)
        slack = s if slack is None else min(slack, s)
ns3 = open(rd + "/ns3-exit").read().strip()
out = {"ns3Exit": int(ns3), "late": late, "droppedNoSub": no_sub, "minSlackTGate": slack}
print(json.dumps(out))
sys.exit(0 if out["ns3Exit"] == 0 and late == 0 and no_sub == 0 and slack is not None else 1)
PY
    }
    check ${RUNG}_rng2_c7_holds rng2_c7
    fact rng2 "$(cat "$e/rng2-c7.json" 2>/dev/null || echo null)"
    cmp_runs() { python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare --components "$1" "${@:3}" >"$e/$2.json"; }
    c1_live() { cmp_runs ledger,ipc,traces,extra c1-live live1="$RUNS/live1" live2="$RUNS/live2" live3="$RUNS/live3"; }
    c1_replay() { cmp_runs ledger,ipc,traces c1-replay live1="$RUNS/live1" replay="$RUNS/replay"; }
    c1_rng2() { cmp_runs ledger,ipc,traces c1-rng2 live1="$RUNS/live1" rng2="$RUNS/rng2"; [ $? -eq 1 ]; }   # must differ
    check ${RUNG}_c1_three_live_runs_equal_on_all_components c1_live
    check ${RUNG}_c1_replay_equals_live_on_ledger_ipc_traces c1_replay
    check ${RUNG}_c1_rng2_differs_from_live c1_rng2
    jbool() { python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$1" "$2" 2>/dev/null || echo null; }
    fact c1 "{\"liveRunsEqual\": $(jbool "$e/c1-live.json" all_equal), \"replayEqual\": $(jbool "$e/c1-replay.json" all_equal), \"rngRun2Differs\": $(python3 -I -c 'import json; print(json.dumps(not json.load(open("'"$e"'/c1-rng2.json"))["all_equal"]))' 2>/dev/null || echo null)}"
}

# rung_reference <ref dir> [reference-compare.py args]: --reference mode (C1 only, after rung_c1): live1 equals the
# committed dev reference (SHA256SUMS, ledger/ipc/traces/extra digests, the named files); recorded items are
# reported, never judged. A relative ref dir is taken inside the harness clone, where the reference is committed.
rung_reference() {
    local ref="$1"; shift
    case "$ref" in /*) ;; *) ref="$HARNESS_DIR/$ref" ;; esac
    ref_cmp() {
        python3 -I "$HARNESS_DIR/scripts/gates/reference-compare.py" compare "$RUNS/live1" "$ref" "$@" >"$e/reference-compare.json"
        local rc=$?
        cat "$e/reference-compare.json"
        return $rc
    }
    check "${RUNG}_c1_live1_equals_the_committed_reference" ref_cmp "$@"
    fact equalsReference "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["equalsReference"]))' "$e/reference-compare.json" 2>/dev/null || echo false)"
    fact referenceDir "$(json_str "${ref#"$HARNESS_DIR"/}")"
}

# rung_final_facts: the gate-level facts and checks after the runs: slack, L, IPC drops, restart counts (all runs and
# per pod), the 12041/12042 -1 route owners, whether the TS xApp or the stub held an ack route, and no leftovers.
rung_final_facts() {
    facts_final() {
        python3 -I - "$e" "$e/${RUNG}-facts.json" <<'PY'
import glob, json, sys
e = sys.argv[1]
slack = {"T_start": None, "T_gate": None, "T_ctl": None, "W": None}
for log in sorted(glob.glob(e + "/runs/live*/trace/e2-pacing-log.jsonl")) + sorted(glob.glob(e + "/runs/calib/trace/e2-pacing-log.jsonl")):
    for l in open(log):
        m = json.loads(l)
        if m.get("type") == "barrier" and m["stepsWaitS"] >= 0:
            k = "T_start" if m["seq"] == -1 else "T_gate"
            s = round(m["timeoutS"] - m["stepsWaitS"], 6)
            slack[k] = s if slack[k] is None else min(slack[k], s)
summaries = sorted(glob.glob(e + "/runs/live*/pacer/pacer-summary.json")) + sorted(glob.glob(e + "/runs/calib/pacer/pacer-summary.json"))
for p in summaries:
    for k, v in (json.load(open(p)).get("minSlackS") or {}).items():
        if v is not None:
            slack[k] = v if slack[k] is None else min(slack[k], v)
L = []
for p in summaries:
    for rec in json.load(open(p))["steps"].values():
        if rec.get("window") == "T_ctl":
            L += rec.get("L", [])
dropped = no_sub = 0
for tr in glob.glob(e + "/runs/*/trace/e2-ipc-trace-*.jsonl"):
    for l in open(tr):
        if '"type":"sample"' in l:
            dropped = max(dropped, json.loads(l).get("ipcDropped", 0))
for log in glob.glob(e + "/runs/*/trace/e2-pacing-log.jsonl"):
    for l in open(log):
        m = json.loads(l)
        if m.get("type") == "step":
            no_sub = max(no_sub, m.get("droppedNoSub", 0))
out = {"minSlack": slack, "lControlLatencyS": sorted(L), "ipcDropped": dropped, "droppedNoSub": no_sub}
json.dump(out, open(sys.argv[2], "w"), indent=1)
print(json.dumps(out))
sys.exit(0 if dropped == 0 and no_sub == 0 else 1)
PY
    }
    check ${RUNG}_ipc_dropped_zero_no_sub_dropped_zero_and_slack_recorded facts_final
    for k in minSlack lControlLatencyS ipcDropped droppedNoSub; do
        fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/${RUNG}-facts.json" "$k" 2>/dev/null || echo null)"
    done
    restart_all_zero() { cat "$e"/*-after-pods.tsv 2>/dev/null | awk -F'\t' '$4 != 0 { bad = 1 } END { exit bad }'; }
    check ${RUNG}_restart_counts_all_zero restart_all_zero
    fact restartCountsAllZero "$(restart_all_zero && echo true || echo false)"
    restart_map() {   # "<run>/<rc|ts-xapp|qp-stub|kpimon|hw-go|agent-N>": restart count, from each run's after-snapshot
        python3 -I - "$e" <<'PY'
import glob, json, os, sys
names = (("ricxapp-trafficxapp-", "ts-xapp"), ("ricxapp-stubqp-", "qp-stub"), ("ricxapp-kpimon-go-", "kpimon"),
         ("ricxapp-hw-go-", "hw-go"), ("ricxapp-rc-", "rc"))
out = {}
for f in sorted(glob.glob(sys.argv[1] + "/*-after-pods.tsv")):
    run = os.path.basename(f)[:-len("-after-pods.tsv")]
    for l in open(f):
        c = l.rstrip("\n").split("\t")
        if c[0] == "agent":
            out["%s/agent-%s" % (run, c[1])] = int(c[3])
        else:
            for pre, k in names:
                if c[1].startswith(pre):
                    out["%s/%s" % (run, k)] = int(c[3])
print(json.dumps(out))
PY
    }
    fact restartCounts "$(restart_map 2>/dev/null || echo null)"
    route_owners() {   # per run, at the start and the end, the rtmgr and e2term views of the 12041/12042 -1 owner
        python3 -I - "$e/route-owners.tsv" "$1" <<'PY'
import json, sys
mt, out = sys.argv[2], {}
for l in open(sys.argv[1]):
    run, when, r41, r42, e41, e42 = (l.rstrip("\n").split("\t") + [""] * 6)[:6]
    out.setdefault(run, {})[when] = {"rtmgr": r41 if mt == "12041" else r42, "e2term": e41 if mt == "12041" else e42}
print(json.dumps(out))
PY
    }
    fact routeOwner12041 "$(route_owners 12041 2>/dev/null || echo null)"
    fact routeOwner12042 "$(route_owners 12042 2>/dev/null || echo null)"
    # whether the TS xApp or the stub held a -1 ack route in either view, per run (attributes any later restart)
    fact tsOrStubHeldAckRoute "$(python3 -I - "$e/route-owners.tsv" <<'PY' 2>/dev/null || echo null
import json, sys
out = {}
for l in open(sys.argv[1]):
    c = (l.rstrip("\n").split("\t") + [""] * 6)[:6]
    held = any(("trafficxapp" in v or "stubqp" in v) for v in c[2:])
    out[c[0]] = out.get(c[0], False) or held
print(json.dumps(out))
PY
    )"
    no_stray() {
        local bad=0
        pgrep -f "scenario-zero" && bad=1
        pgrep -f ipc-null-sink && bad=1
        pgrep -f "gates/pacer.py" && bad=1
        [ -z "$(dk ps -aq --filter label=ns3e2.agent=1)" ] || { echo "agent container left"; bad=1; }
        [ -z "$(dk ps -aq --filter "name=$INJ_NAME")" ] || { echo "injector container left"; bad=1; }
        ss -Sanp 2>/dev/null | grep -E ':3847[0-9]|:38499' && bad=1
        [ "$bad" = 0 ] && echo "no leftovers"
        return $bad
    }
    check ${RUNG}_no_stray_process no_stray
}

# rung_preconditions: the TS xApp rung's preconditions, in this order: the RIC watchdog, the NIST tree and TS patches,
# build tools, SCTP, the ns-3 binary, the self-tests, grpcurl, a fresh rc/kpimon/hw-go and bucket, rc at its pin, A1
# policy type 20008 ensured (SDL is in-memory: a VM boot empties it) BEFORE the first a1mediator restart, the TS
# xApp and stub pods recreated with rtmgr sessions, the TS xApp at its pin in gRPC mode, the RMR peer image, the
# stub, image IDs and the RC decoder (RC_DEC_TAG).
rung_preconditions() {
    ric_watchdog_bg

    check ${RUNG}_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
    check ${RUNG}_ts_source_is_pin_plus_exactly_the_testbed_patches ts_patches_check
    check ${RUNG}_build_tools_present agents_ensure_build_tools
    check ${RUNG}_sctp_module_loaded agents_sctp_module
    check ${RUNG}_ns3_binary_located_at_pins agents_ns3_locate
    check ${RUNG}_pod_log_reader_self_test python3 -I "$HARNESS_DIR/scripts/gates/pod-log-window.py" --self-test
    check ${RUNG}_pacer_self_test python3 -I "$HARNESS_DIR/scripts/gates/pacer-selftest.py"
    check ${RUNG}_kpm_ue_list_judge_self_test python3 -I "$HARNESS_DIR/tools/e2-evidence/kpm-ue-list-moves.py" --self-test
    check ${RUNG}_grpcurl_fetched_and_checksum_verified rc_grpcurl_fetch
    # start from pods this gate created: a kept pod's start-up line rotates out of its log
    check ${RUNG}_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket rc_ric_reset pre
    check ${RUNG}_rc_installed_at_pin_and_ready rc_at_pin
    # SDL is in-memory: a VM boot (dbaas restart) empties it, so the type is ensured before any a1mediator restart,
    # whose check then proves the type survives that restart
    check ${RUNG}_a1_policy_type_20008_present ts_policy_type_ensure
    fact a1PolicyTypeCreated "$([ -e "$e/a1-type-create.txt" ] && echo true || echo false)"
    check ${RUNG}_pre_ts_and_stub_pods_fresh_rtmgr_sessions ts_stub_pods_reset pre
    ts_at_pin() { [ "$(git -C "$TS_DIR" rev-parse HEAD)" = "$TS_SHA" ] && ts_ready && jq -e '.ts_control_api == "grpc"' \
        <(kc -n ricxapp get cm configmap-ricxapp-trafficxapp-appconfig -o jsonpath='{.data.config-file\.json}' | jq .controls); }
    check ${RUNG}_ts_xapp_at_pin_ready_in_grpc_mode ts_at_pin
    check ${RUNG}_rmr_peer_image_built_self_tested rmr_peer_build
    stub_present() { read -r n r _ < <(pod_info ricxapp "ricxapp-$STUB_NAME-") && [ "$r" = true ] && echo "stub $n ready"; }
    check ${RUNG}_stub_qp_deployed stub_present
    check ${RUNG}_xapp_image_ids ts_image_ids
    fact xappImageIds "$(cat "$e/xapp-image-ids.json" 2>/dev/null || echo null)"
    RC_DEC_TAG=$(bash "$HARNESS_DIR/tools/rc-decode/build.sh" 2>/dev/null | tail -n 1)
    check ${RUNG}_rc_decoder_built test -n "$RC_DEC_TAG"
}

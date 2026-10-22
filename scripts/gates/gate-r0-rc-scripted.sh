#!/usr/bin/env bash
# Gate R0 = M8 (VM side): the real rc driven by scripted gRPC, lock-step pacing, agents enb:1, gnb:2, gnb:3.
#
#   gate-r0-rc-scripted.sh [--mode c1|single] [--dev] [--tctl SECONDS --tctl-provenance TEXT]
#
# --mode single (the M9 chain): Q2, C8 and one live run with its per-run checks. --mode c1 (default): all of it.
#
# Order (plan phase 03):
#   Q2   null-control free run in the R0 config at the default -5 dB; the LTE outage switches
#        (LteSwitchStats.txt `SwitchToLte` rows) are counted; >= 1 applies substitution 1
#        (--outageThreshold=-1000 for every later run), reported either way.
#   C8   null-control lock-step == free-run at the threshold the gated runs use.
#   live1..live3   the same scripted rc controls, each from a fresh RIC state (rc, kpimon, hw-go recreated, new
#        Influx bucket, agents restarted so ctlId starts at 1), with route dumps, pod snapshots, capture,
#        the wire extractor and the per-run checks (C2 ledger, expected outcomes, C9 handover rows, D7,
#        restart counts 0, one terminal answer per request, kpimon log window).
#   k9   a control sent after `go`, so it misses its barrier: refused late, one FAILURE on the wire, no
#        handover row (outside the C1 digest set).
#   replay   the RIC-free pacer replay of live1's ledger; rng2   the same replay at --RngRun=2.
#   C1   live1 = live2 = live3 on ledger, IPC samples, traces and the wire components; replay equals live1 on
#        ledger, IPC samples and traces; rng2 differs.
#
# T_ctl: a gated run needs the calibrated value (--tctl with its provenance, set from the measured L). --dev
# runs with the contract's start value 30 s and marks verdict.json `dev: true`; it is a rehearsal, not the gate.
# shellcheck disable=SC2034  # SINKX and PACERX are read by paced-lib.sh
source "$(dirname "$0")/lib.sh"
gate_init r0
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/paced-lib.sh"

DEV=0; TCTL_S=""; TCTL_PROV=""; MODE=c1
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --dev) DEV=1; shift ;;
        --tctl) TCTL_S="$2"; shift 2 ;;
        --tctl-provenance) TCTL_PROV="$2"; shift 2 ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
T_GATE_S=$(python3 -I "$CFG" get deadlines.T_gate_s)
if [ -z "$TCTL_S" ]; then TCTL_S=$(python3 -I "$CFG" get deadlines.T_ctl_s); TCTL_PROV="contract start value (not calibrated)"; fi
T_CTL_S="$TCTL_S"
PACER_PORT=38499
NODES="enb:1,gnb:2,gnb:3"
SCEN="$HARNESS_DIR/scripts/gates/r0-scenario.json"
CHK="$HARNESS_DIR/scripts/gates/r0-checks.py"
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10)
SINKX=(); PACERX=()
N_CTL=$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["controls"]))' "$SCEN")
case "$MODE" in c1|single) ;; *) log "bad --mode $MODE"; exit 2 ;; esac
fact mode "$(json_str "$MODE")"
fact dev "$([ "$DEV" = 1 ] && echo true || echo false)"
fact tCtlSeconds "$T_CTL_S"
fact tCtlProvenance "$(json_str "$TCTL_PROV")"
fact vmLoadStart "$(json_str "$(uptime)")"
record r0_args true "dev $DEV; T_ctl $T_CTL_S s ($TCTL_PROV); T_gate $T_GATE_S s; epoch $EPOCH_MS; rc pin $RC_SHA"
tctl_ok() { [ "$DEV" = 1 ] || { [ -n "$TCTL_S" ] && [ "$TCTL_PROV" != "contract start value (not calibrated)" ]; }; }
check r0_t_ctl_is_calibrated_or_run_is_dev tctl_ok
ric_watchdog_bg

check r0_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check r0_build_tools_present agents_ensure_build_tools
check r0_sctp_module_loaded agents_sctp_module
check r0_ns3_binary_located_at_pins agents_ns3_locate
check r0_pod_log_reader_self_test python3 -I "$HARNESS_DIR/scripts/gates/pod-log-window.py" --self-test
check r0_grpcurl_fetched_and_checksum_verified rc_grpcurl_fetch
rc_at_pin() { [ "$(git -C "$RIC_DIR/xApps/rc" rev-parse HEAD)" = "$RC_SHA" ] && rc_ready; }
check r0_rc_installed_at_pin_and_ready rc_at_pin
RC_DEC_TAG=$(bash "$HARNESS_DIR/tools/rc-decode/build.sh" 2>/dev/null | tail -n 1)
check r0_rc_decoder_built test -n "$RC_DEC_TAG"

################################################################################
# Q2 and C8: the radio config, no RIC
################################################################################
check r0_q2_null_control_free_run_default_threshold paced_null_run q2 free 0 --RngRun=1
q2_count() {
    local n
    n=$(grep -c '^SwitchToLte' "$RUNS/q2/ns3run/LteSwitchStats.txt" 2>/dev/null)
    echo "LTE outage switches at the default -5 dB: ${n:-0}"
    echo "${n:-0}" >"$e/q2-outage-switches.txt"
}
check r0_q2_count_lte_outage_switches q2_count
Q2_N=$(cat "$e/q2-outage-switches.txt" 2>/dev/null || echo 0)
if [ "$Q2_N" -ge 1 ]; then THRESH=-1000; SUBST=true; else THRESH=-5; SUBST=false; fi
fact q2OutageSwitches "$Q2_N"
fact substitution1Applied "$SUBST"
fact outageThresholdDb "$THRESH"
CLI+=("--outageThreshold=$THRESH")
check r0_c8_free_run_at_gated_threshold paced_null_run c8free free 0 --RngRun=1
check r0_c8_lockstep_null_control paced_null_run c8null lockstep 0 --RngRun=1
c8() { python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare c8free="$RUNS/c8free" c8null="$RUNS/c8null" >"$e/c8-digests.json"; local rc=$?; python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"])' "$e/c8-digests.json"; return $rc; }
check r0_c8_null_control_equals_free_run c8
fact c8NullEqualsFree "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["all_equal"]))' "$e/c8-digests.json" 2>/dev/null || echo null)"

################################################################################
# live runs
################################################################################
RC_EP=$(rc_endpoint)
python3 -I "$CHK" schedule "$SCEN" "$RC_EP" --rc-send "$HARNESS_DIR/scripts/gates/rc-send.sh" >"$e/r0-schedule.json"
python3 -I "$CHK" schedule "$SCEN" "$RC_EP" --rc-send "$HARNESS_DIR/scripts/gates/rc-send.sh" --forced-late >"$e/k9-schedule.json"

all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == 3) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}

g4() {   # G4: every gNB agent's e2mgr nodeb JSON decodes to its N5 key; the TS xApp's cell_map, replayed offline
    local n
    for n in 1 2 3; do e2mgr_get "nodeb/$(printf 'gnb_001_001_%08x' "$n")" >"$e/e2mgr-node-$n.json" || return 1; done
    python3 -I "$HARNESS_DIR/scripts/gates/replay-ts-cell-map.py" "$e"/e2mgr-node-{1,2,3}.json \
        --expect 0000000202=gnb_001_001_00000002 --expect 0000000303=gnb_001_001_00000003 --no-key gnb_001_001_00000001
}

# r0_live <label> <schedule.json> <n-controls> [--first]: one run from a fresh RIC state; the per-run checks.
r0_live() {
    local label="$1" sched="$2" nctl="$3" first="${4:-}" rd="$RUNS/$1" pp rc cap_t0
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace" "$rd/extra"
    check "r0_${label}_ric_reset_fresh_pods_and_bucket" rc_ric_reset
    check "r0_${label}_route_dump_start" rc_route_dump "$label-start"
    check "r0_${label}_capture_started_before_agents" capture_start "$label" docker0 'ip proto 132'
    cap_t0=$(date +%s)
    check "r0_${label}_agents_connected_set_exact" gate_bringup agents "$NODES"
    echo '{}' >"$rd/node-ips.json"
    check "r0_${label}_agent_ips_recorded" agents_record_ips "$rd/node-ips.json"
    check "r0_${label}_every_agent_ready_and_subscribed" all_subscribed
    [ "$first" = --first ] && check "r0_g4_nodeb_keys_and_ts_cell_map_replay" g4
    check "r0_${label}_pods_snapshot_before" rc_pod_snapshot "$label-before"
    run_it() {
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" --schedule "$sched" >"$rd/pacer.log" 2>&1 &
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
    check "r0_${label}_lockstep_run_exits_clean" run_it
    check "r0_${label}_pods_snapshot_after" rc_pod_snapshot "$label-after"
    check "r0_${label}_route_dump_end" rc_route_dump "$label-end"
    fact "routeOwner12041_$label" "$(json_str "${ROUTE_OWNER_12041:-}")"
    fact "routeOwner12042_$label" "$(json_str "${ROUTE_OWNER_12042:-}")"
    check "r0_${label}_restart_counts_zero_rc_kpimon_hw_go_agents" rc_restarts_zero "$label-after"
    local c
    for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
        dk logs "$c" >"$rd/agent-$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c").log" 2>&1
    done
    check "r0_${label}_agents_stopped" agents_stop
    check "r0_${label}_capture_stopped" capture_stop "$label"
    kpimon_window() { kpimon_logs_since "$cap_t0" "$rd/kpimon.log" && kpimon_log_window_summary "$rd/kpimon.log"; }
    check "r0_${label}_kpimon_log_window_complete" kpimon_window
    wmore0() { local c; c=$(kpimon_log_counts "$rd/kpimon.log"); echo "$c" | tr '\n' ' '; echo "$c" | awk -F= '($1=="hdr_wmore"||$1=="msg_wmore") && $2!=0 {bad=1} END{exit bad}'; }
    check "r0_${label}_kpimon_zero_rc_wmore" wmore0
    extract() {
        python3 -I "$HARNESS_DIR/tools/e2-evidence/wire-c1-extract.py" "$e/$label.pcap" --node-ips "$rd/node-ips.json" \
            --ledger "$rd/trace/e2-control-ledger.jsonl" --out-dir "$rd/extra" --t0 "$cap_t0" \
            --decode-cmd "$(dk_cmd) run --rm -i $RC_DEC_TAG"
    }
    check "r0_${label}_wire_one_terminal_answer_per_request_joined_to_ledger" extract
    c2() { python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$rd/trace/e2-control-ledger.jsonl" "$rd/pacer/pacer-log.jsonl" --expect "$nctl"; }
    check "r0_${label}_c2_ledger" c2
    check "r0_${label}_c9_handover_rows_match_applied_lines" python3 -I "$HARNESS_DIR/scripts/gates/check-c9-handover-trace.py" "$rd"
}

NLIVE=3; [ "$MODE" = single ] && NLIVE=1
for i in $(seq "$NLIVE"); do
    if [ "$i" = 1 ]; then r0_live "live$i" "$e/r0-schedule.json" "$N_CTL" --first; else r0_live "live$i" "$e/r0-schedule.json" "$N_CTL"; fi
    check "r0_live${i}_expected_outcomes_and_afterseq" python3 -I "$CHK" expect "$SCEN" "$RUNS/live$i/trace/e2-control-ledger.jsonl"
done
d7() { python3 -I "$CHK" d7 "$RUNS/live1/trace/e2-control-ledger.jsonl" | tee "$e/d7.json"; }
check r0_d7_three_paths_two_imsis_both_gnbs d7
fact d7 "$(cat "$e/d7.json" 2>/dev/null || echo null)"
refusal() {
    python3 -I - "$RUNS/live1" <<'PY'
import json, sys
rd = sys.argv[1]
led = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
ref = [x for x in led if x["cause"] == "alreadyOnTarget"]
ms = json.load(open(rd + "/extra/rc-multiset.json"))
wire = [m for m in ms if m["cause"] == "control-failed-to-execute"]
print("refused alreadyOnTarget:", ref, "wire failures:", len(wire))
sys.exit(0 if len(ref) == 1 and len(wire) == 1 and ref[0]["viaNodeId"] == wire[0]["viaNode"] else 1)
PY
}
check r0_v4_already_on_target_refusal_ledger_and_wire_failure refusal

if [ "$MODE" = c1 ]; then
# k9: the forced-late control
r0_live k9 "$e/k9-schedule.json" 1
k9_check() {
    python3 -I "$CHK" expect "$SCEN" "$RUNS/k9/trace/e2-control-ledger.jsonl" --forced-late &&
        python3 -I - "$RUNS/k9" <<'PY'
import json, sys
rd = sys.argv[1]
ms = json.load(open(rd + "/extra/rc-multiset.json"))
ok = len(ms) == 1 and ms[0]["answer"] == "failure" and ms[0]["cause"] == "control-failed-to-execute"
print("k9 wire:", ms)
sys.exit(0 if ok else 1)
PY
}
check r0_k9_forced_late_one_failure_ledger_late_no_handover_row k9_check

################################################################################
# C1: the replay without the RIC, RngRun 2, and the digest comparisons
################################################################################
PACERX=(--replay "$RUNS/live1/trace/e2-control-ledger.jsonl")
check r0_replay_run_without_the_ric paced_null_run replay lockstep 0 --RngRun=1
check r0_rng2_run_without_the_ric paced_null_run rng2 lockstep 0 --RngRun=2
PACERX=()
rng2_c2() { python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$RUNS/rng2/trace/e2-control-ledger.jsonl" "$RUNS/rng2/pacer/pacer-log.jsonl"; }
check r0_rng2_c2_holds rng2_c2
cmp_runs() { python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare --components "$1" "${@:3}" >"$e/$2.json"; }
c1_live() { cmp_runs ledger,ipc,traces,extra c1-live live1="$RUNS/live1" live2="$RUNS/live2" live3="$RUNS/live3"; }
c1_replay() { cmp_runs ledger,ipc,traces c1-replay live1="$RUNS/live1" replay="$RUNS/replay"; }
c1_rng2() { cmp_runs ledger,ipc,traces c1-rng2 live1="$RUNS/live1" rng2="$RUNS/rng2"; [ $? -eq 1 ]; }   # must differ
check r0_c1_three_live_runs_equal_on_all_components c1_live
check r0_c1_replay_equals_live_on_ledger_ipc_traces c1_replay
check r0_c1_rng2_differs_from_live c1_rng2
jbool() { python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$1" "$2" 2>/dev/null || echo null; }
fact c1 "{\"liveRunsEqual\": $(jbool "$e/c1-live.json" all_equal), \"replayEqual\": $(jbool "$e/c1-replay.json" all_equal), \"rngRun2Differs\": $(python3 -I -c 'import json; print(json.dumps(not json.load(open("'"$e"'/c1-rng2.json"))["all_equal"]))' 2>/dev/null || echo null)}"
fi

################################################################################
# facts: restart counts, slack, hygiene
################################################################################
facts_final() {
    python3 -I - "$e" <<'PY'
import glob, json, sys
e = sys.argv[1]
slack = {"T_start": None, "T_gate": None, "T_ctl": None, "W": None}
for log in sorted(glob.glob(e + "/runs/live*/trace/e2-pacing-log.jsonl")) + sorted(glob.glob(e + "/runs/k9/trace/e2-pacing-log.jsonl")):
    for l in open(log):
        m = json.loads(l)
        if m.get("type") == "barrier" and m["stepsWaitS"] >= 0:
            k = "T_start" if m["seq"] == -1 else "T_gate"
            s = round(m["timeoutS"] - m["stepsWaitS"], 6)
            slack[k] = s if slack[k] is None else min(slack[k], s)
for p in sorted(glob.glob(e + "/runs/live*/pacer/pacer-summary.json")):
    for k, v in (json.load(open(p)).get("minSlackS") or {}).items():
        if v is not None:
            slack[k] = v if slack[k] is None else min(slack[k], v)
L = []
for p in sorted(glob.glob(e + "/runs/live*/pacer/pacer-summary.json")):
    for rec in json.load(open(p))["steps"].values():
        L += rec.get("L", [])
dropped = 0
for tr in glob.glob(e + "/runs/*/trace/e2-ipc-trace-*.jsonl"):
    for l in open(tr):
        if '"type":"sample"' in l:
            dropped = max(dropped, json.loads(l).get("ipcDropped", 0))
out = {"minSlack": slack, "lLabelledUnusedUnderHold": sorted(L), "ipcDropped": dropped}
json.dump(out, open(e + "/r0-facts.json", "w"), indent=1)
print(json.dumps(out))
sys.exit(0 if dropped == 0 else 1)
PY
}
check r0_ipc_dropped_zero_and_slack_recorded facts_final
for k in minSlack lLabelledUnusedUnderHold ipcDropped; do
    fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/r0-facts.json" "$k" 2>/dev/null || echo null)"
done
restart_all_zero() { cat "$e"/live*-after-pods.tsv "$e"/k9-after-pods.tsv 2>/dev/null | awk -F'\t' '$4 != 0 { bad = 1 } END { exit bad }'; }
check r0_restart_counts_all_zero restart_all_zero
fact restartCountsAllZero "$(restart_all_zero && echo true || echo false)"
no_stray() {
    local bad=0
    pgrep -f "scenario-zero" && bad=1
    pgrep -f ipc-null-sink && bad=1
    pgrep -f "gates/pacer.py" && bad=1
    [ -z "$(dk ps -aq --filter label=ns3e2.agent=1)" ] || { echo "agent container left"; bad=1; }
    ss -Sanp 2>/dev/null | grep -E ':3847[0-9]|:38499' && bad=1
    [ "$bad" = 0 ] && echo "no leftovers"
    return $bad
}
check r0_no_stray_process no_stray
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

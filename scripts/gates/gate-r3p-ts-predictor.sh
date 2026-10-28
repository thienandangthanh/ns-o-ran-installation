#!/usr/bin/env bash
# Gate R3′ (VM side): the TS xApp decides from the harness predictor's answer (persistence of the per-cell
# DRB.PdcpSduVolumeDL read from Influx by sim time, r3p-scenario.json) and controls ns-3 through rc's gRPC; lock-step
# pacing, agents enb:1, gnb:2, gnb:3, R2's radio config. Per trigger step T the pacer's prepare hook (before the
# trigger's t0) runs r3p-prepare.py: N6 certifies the Influx window [T-15, T] and the UE's membership, the predictor
# answers from that certified window only, the stub QP's log is saved and its one-entry table loaded; then the
# 30003 trigger; a handover needs one control within T_ctl, a none none within W.
#
#   gate-r3p-ts-predictor.sh [--mode c1|single|calibrate] [--dev] [--reference <committed reference dir>]
#   gate-r3p-ts-predictor.sh --mode dryrun --stage a
#   gate-r3p-ts-predictor.sh --mode dryrun --stage b --stage-a-class <committed stage A classification>
#
# --mode c1 (default): C8 (with 0 handover rows in the null control), live1..live3, the RIC-free replay, the
# --RngRun=2 replay, C1; --reference adds live1 = the committed reference. --mode single (the M9 chain without the
# reference): C8 and one live run. --mode calibrate: R2's calibration block through the R3′ prepare path (N6 + the
# fixed answer); W = max(1 s, 3 x L_max) for rung-config r3pConfig.W_s. --mode dryrun: one null-control lock-step
# run with the RIC up, a prepare-only N6 observation at every T of the domain (stage b: h1's control injected at h1's
# step), the full Influx = IPC, the handover rows, then r3p-dry-run-classifier.py (invalid fails the gate; formed,
# substitution4, T3 and a schedule are recorded as dryRunClass).
# shellcheck disable=SC2034  # SINKX, PACERX, NODES and the rest are read by paced-lib.sh and ts-rung-lib.sh
source "$(dirname "$0")/lib.sh"
gate_init r3p
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/ts-lib.sh"
source "$(dirname "$0")/paced-lib.sh"
source "$(dirname "$0")/influx-dump.sh"
source "$(dirname "$0")/ts-rung-lib.sh"
RUNG=r3p

DEV=0; MODE=c1; REF=""; STAGE=""; STAGE_A=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --stage) STAGE="$2"; shift 2 ;;
        --stage-a-class) STAGE_A="$2"; shift 2 ;;
        --reference) REF="$2"; shift 2 ;;
        --dev) DEV=1; shift ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
case "$MODE" in c1|single|calibrate|dryrun) ;; *) log "bad --mode $MODE"; exit 2 ;; esac
[ -z "$REF" ] || [ "$MODE" = c1 ] || { log "--reference needs --mode c1"; exit 2; }
if [ "$MODE" = dryrun ]; then
    case "$STAGE" in a) ;; b) [ -n "$STAGE_A" ] || { log "--stage b needs --stage-a-class"; exit 2; } ;;
        *) log "dryrun needs --stage a|b"; exit 2 ;; esac
    case "$STAGE_A" in ""|/*) ;; *) STAGE_A="$HARNESS_DIR/$STAGE_A" ;; esac
fi
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
G="$HARNESS_DIR/scripts/gates"
CFG="$G/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
T_GATE_S=$(python3 -I "$CFG" get deadlines.T_gate_s)
T_CTL_S=$(python3 -I "$CFG" get deadlines.T_ctl_s)
TCTL_PROV=$(python3 -I "$CFG" get deadlines.T_ctl_s.provenance)
W_S=$(python3 -I "$CFG" get r3pConfig.W_s)
W_PROV=$(python3 -I "$CFG" get r3pConfig.W_s.provenance)
THRESH=$(python3 -I "$CFG" get scenario.outageThreshold_dB)
THRESH_PROV=$(python3 -I "$CFG" get scenario.outageThreshold_dB.provenance)
A1_TH=$(python3 -I "$CFG" get a1_threshold)
A1_PROV=$(python3 -I "$CFG" get a1_threshold.provenance)
SUB2=$(python3 -I "$CFG" get substitutions.ts_xapp_default_rmr_handler.applied)
SUB3=$(python3 -I "$CFG" get substitutions.ts_xapp_a1_payload_string.applied)
PACER_PORT=38499
NODES="enb:1,gnb:2,gnb:3"
SCEN="$G/r3p-scenario.json"
SCHED="$G/r3p-schedule.json"
R2SCEN="$G/r2-scenario.json"
CHK="$G/r3p-checks.py"
SEND="$G/send-rmr.sh"
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$G/pacer.py"
TOKEN_FILE="${NIST_RIC_DIR:-$HOME/nist/RAN_Intelligent_Controllers/Near-Real-Time-RIC}/influxdb_auth_token.json"
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 "--outageThreshold=$THRESH")
SINKX=(); PACERX=()
SCEN_TH=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["threshold"])' "$SCEN")
SCEN_SHA=$(sha256sum "$SCEN" | cut -d' ' -f1)
# W is measured by the calibration and unused by a dry run (no trigger); until then the pacer gets R2's value
[ "$W_S" = null ] && { [ "$MODE" = calibrate ] || [ "$MODE" = dryrun ]; } && W_S=$(python3 -I "$CFG" get deadlines.W_s)
case "$MODE" in
    calibrate) N_POS=$(python3 -I "$G/r2-checks.py" triggers "$R2SCEN" --calibrate | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)))') ;;
    dryrun) N_POS=0 ;;
    *) N_POS=$(python3 -I -c 'import json,sys; print(sum(1 for t in json.load(open(sys.argv[1]))["triggers"] if t["decision"] == "handover"))' "$SCHED" 2>/dev/null || echo 0) ;;
esac
fact mode "$(json_str "$MODE")"
fact stage "$(json_str "$STAGE")"
fact dev "$([ "$DEV" = 1 ] && echo true || echo false)"
fact tCtlSeconds "$T_CTL_S"
fact tCtlProvenance "$(json_str "$TCTL_PROV")"
fact wSeconds "$W_S"
fact wProvenance "$(json_str "$W_PROV")"
fact a1Threshold "$A1_TH"
fact a1ThresholdProvenance "$(json_str "$A1_PROV")"
fact substitution2Applied "$SUB2"
fact substitution3Applied "$SUB3"
fact outageThresholdDb "$THRESH"
fact outageThresholdProvenance "$(json_str "$THRESH_PROV")"
fact scenarioSha256 "$(json_str "$SCEN_SHA")"
fact handoverTriggers "$N_POS"
fact vmLoadStart "$(json_str "$(uptime)")"
record r3p_args true "dev $DEV; mode $MODE; stage $STAGE; T_ctl $T_CTL_S s; W $W_S s ($W_PROV); A1 threshold $A1_TH; substitution 2 $SUB2; substitution 3 $SUB3; outage threshold $THRESH dB; scenario $SCEN_SHA"
# the gated values name the evidence that measured them; a gated run follows a committed schedule of this scenario
cfg_ok() {
    case "$TCTL_PROV" in *evidence/r0/*) ;; *) echo "T_ctl provenance does not name evidence/r0/"; return 1 ;; esac
    case "$THRESH_PROV" in *evidence/r0/*) ;; *) echo "outage threshold provenance does not name evidence/r0/"; return 1 ;; esac
    [ "$A1_TH" = "$SCEN_TH" ] || { echo "A1 threshold $A1_TH (rung-config) != r3p scenario $SCEN_TH"; return 1; }
    python3 -I "$G/r3p-predictor.py" lint "$SCEN" || return 1
    case "$MODE" in
        dryrun) [ "$STAGE" = a ] || [ -s "$STAGE_A" ] || { echo "no stage A classification $STAGE_A"; return 1; }
                echo "dry run: no W, no schedule"; return 0 ;;
        calibrate) echo "calibration: W is measured here"; return 0 ;;
    esac
    case "$W_PROV" in *evidence/r3p/*) ;; *) echo "W provenance does not name an R3′ calibration (evidence/r3p/)"; return 1 ;; esac
    python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); sys.exit(0 if s["scenarioSha256"] == sys.argv[2] and s["triggers"] else 1)' \
        "$SCHED" "$SCEN_SHA" || { echo "no committed r3p-schedule.json formed from this scenario"; return 1; }
    echo "T_ctl and the outage threshold from R0, W $W_S s from evidence/r3p/, A1 threshold $A1_TH, schedule of scenario $SCEN_SHA"
}
check r3p_config_values_from_their_evidence cfg_ok
check r3p_predictor_n6_classifier_checks_reference_self_tests bash -c "python3 -I '$G/r3p-predictor.py' --self-test && python3 -I '$G/check-n6-influx-window.py' --self-test && python3 -I '$G/r3p-dry-run-classifier.py' --self-test && python3 -I '$CHK' --self-test && python3 -I '$G/reference-compare.py' --self-test"
rung_preconditions

################################################################################
# dry run: one null-control run with the RIC up, observed at every T of the domain; then the classification
################################################################################
if [ "$MODE" = dryrun ]; then
    label="dry$STAGE"; rd="$RUNS/$label"
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace" "$rd/r3p"
    check "r3p_${label}_ric_reset_fresh_pods_and_bucket" rc_ric_reset "$label"
    check "r3p_${label}_agents_connected_set_exact" gate_bringup agents "$NODES"
    check "r3p_${label}_every_agent_ready_and_subscribed" all_subscribed
    sched_obs() {
        if [ "$STAGE" = b ]; then python3 -I "$G/r3p-schedules.py" observe "$SCEN" "$rd" --after-h1 "$STAGE_A" >"$rd/schedule.json"
        else python3 -I "$G/r3p-schedules.py" observe "$SCEN" "$rd" >"$rd/schedule.json"; fi
    }
    check "r3p_${label}_observe_schedule_written" sched_obs
    check "r3p_${label}_pods_snapshot_before" rc_pod_snapshot "$label-before"
    run_obs() {
        local pp rc
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" --w "$W_S" --schedule "$rd/schedule.json" >"$rd/pacer.log" 2>&1 &
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
    check "r3p_${label}_lockstep_null_control_run_exits_clean" run_obs
    check "r3p_${label}_pods_snapshot_after" rc_pod_snapshot "$label-after"
    check "r3p_${label}_restart_counts_zero_rc_ts_stub_kpimon_hw_go_agents" rc_restarts_zero "$label-after"
    check "r3p_${label}_influx_equals_ipc_full" python3 -I "$CHK" influx-ipc "$SCEN" "$rd"
    check "r3p_${label}_agents_stopped" agents_stop
    check "r3p_${label}_handover_rows_match_ledger" python3 -I "$G/check-c9-handover-trace.py" "$rd"
    # stage A: no ledger line at all (ns-3 writes no ledger without a control); stage B: exactly h1's applied line
    if [ "$STAGE" = b ]; then
        check "r3p_${label}_ledger_exactly_h1_applied" python3 -I "$CHK" dry-ledger "$rd/trace/e2-control-ledger.jsonl" --h1 "$STAGE_A"
    else
        check "r3p_${label}_ledger_no_control" python3 -I "$CHK" dry-ledger "$rd/trace/e2-control-ledger.jsonl"
    fi
    check "r3p_${label}_no_token_in_the_predictor_dir" python3 -I "$CHK" secrets "$rd" "$TOKEN_FILE"
    # the stage is clean iff every check of this run passed; the classifier never drops a candidate
    python3 -I - "$CHECKS_FILE" "r3p_${label}_" "$rd/r3p-stage.json" <<'PY'
import json, sys
bad = [c["name"] for c in map(json.loads, open(sys.argv[1])) if c["name"].startswith(sys.argv[2]) and not c["pass"]]
json.dump({"clean": not bad, "why": bad}, open(sys.argv[3], "w"))
PY
    classify() {
        local rc
        if [ "$STAGE" = a ]; then python3 -I "$G/r3p-dry-run-classifier.py" stage-a "$SCEN" "$rd" "$e/r3p-stage-a-class.json"; rc=$?
        else python3 -I "$G/r3p-dry-run-classifier.py" stage-b "$SCEN" "$STAGE_A" "$rd" "$e/r3p-schedule.json" "$e/r3p-stage-b-class.json"; rc=$?; fi
        # formed or a schedule (0), substitution 4 (4) and T3 (3) are classifications; invalid (1), a usage error or a
        # killed classifier fail the gate, and so does a missing class file
        case "$rc" in 0|3|4) [ -s "$e/r3p-stage-$STAGE-class.json" ] ;; *) return 1 ;; esac
    }
    check "r3p_${label}_classified_valid" classify
    fact dryRunClass "$(cat "$e/r3p-stage-$STAGE-class.json" 2>/dev/null || echo null)"
    fact n6Timing "$(python3 -I -c 'import glob,json,sys; w=[json.load(open(p))["wallS"] for p in glob.glob(sys.argv[1]+"/r3p/n6-*.json")]; print(json.dumps({"n": len(w), "maxS": max(w) if w else None}))' "$rd" 2>/dev/null || echo null)"
    rung_final_facts
    fact vmLoadEnd "$(json_str "$(uptime)")"
    gate_finish
    exit $?
fi

################################################################################
# C8: the radio config, no RIC; the null control has no handover row
################################################################################
if [ "$MODE" != calibrate ]; then
    check r3p_c8_free_run_at_gated_threshold paced_null_run c8free free 0 --RngRun=1
    check r3p_c8_lockstep_null_control paced_null_run c8null lockstep 0 --RngRun=1
    c8() { python3 -I "$G/digest-run.py" --compare c8free="$RUNS/c8free" c8null="$RUNS/c8null" >"$e/c8-digests.json"; local rc=$?; python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"])' "$e/c8-digests.json"; return $rc; }
    check r3p_c8_null_control_equals_free_run c8
    check r3p_c8_null_control_zero_handover_rows python3 -I "$G/check-c9-handover-trace.py" "$RUNS/c8null"
fi

################################################################################
# live runs
################################################################################
rung_stub_setup() {
    local label="$1" rd="$2"
    RUN_SCHEDULE="$rd/schedule.json"
    stub_reset_and_schedule() {
        local u
        u=$(_stub_url) || return 1
        mkdir -p "$rd/r3p"
        if [ "$MODE" = calibrate ]; then
            python3 -I "$G/r3p-schedules.py" calibrate "$SCEN" "$R2SCEN" "$rd" "$u" "$SEND" "$INJ_CTL_PORT" >"$RUN_SCHEDULE" || return 1
        else
            python3 -I "$G/r3p-schedules.py" live "$SCEN" "$SCHED" "$rd" "$u" "$SEND" "$INJ_CTL_PORT" >"$RUN_SCHEDULE" || return 1
        fi
        echo '{"predictions": {}}' >"$rd/r3p/empty-table.json"
        stub_table_load "$rd/r3p/empty-table.json"
    }
    check "r3p_${label}_stub_emptied_and_run_schedule_written" stub_reset_and_schedule
}
rung_judges() {
    local label="$1" rd="$2" L="$2/trace/e2-control-ledger.jsonl" j
    if [ "$MODE" = calibrate ]; then
        join_log() { python3 -I -c 'import importlib.util,json,sys; s=importlib.util.spec_from_file_location("c", sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); json.dump(m.stub_log(sys.argv[2]), open(sys.argv[3], "w"))' "$CHK" "$rd" "$rd/stub-log-joined.json"; }
        check "r3p_${label}_stub_log_parts_joined" join_log
        for j in expect wire; do
            check "r3p_${label}_calibration_${j}" bash -c "python3 -I '$G/r2-checks.py' $j '$R2SCEN' '$rd/$([ $j = expect ] && echo trace/e2-control-ledger.jsonl || echo extra/rc-multiset.json)' --calibrate | tee '$rd/r3p-$j.json'"
        done
        check "r3p_${label}_calibration_stub" bash -c "python3 -I '$G/r2-checks.py' stub '$R2SCEN' '$rd/stub-log-joined.json' '$rd/injector/tx.jsonl' --calibrate | tee '$rd/r3p-stub.json'"
        n6_all() { python3 -I -c 'import glob,json,sys; v=[json.load(open(p))["pass"] for p in glob.glob(sys.argv[1]+"/r3p/n6-*.json")]; print(len(v), "N6 verdicts, all pass:", all(v)); sys.exit(0 if v and all(v) and len(v) == int(sys.argv[2]) else 1)' "$rd" "$N_POS"; }
        check "r3p_${label}_n6_passed_at_every_trigger" n6_all
        return
    fi
    check "r3p_${label}_expected_outcomes_step_scoped_late_zero" bash -c "python3 -I '$CHK' expect '$SCHED' '$L' | tee '$rd/r3p-expect.json'"
    check "r3p_${label}_wire_requests_equal_handovers_via_target_with_predictor_key" bash -c "python3 -I '$CHK' wire '$SCHED' '$rd/extra/rc-multiset.json' | tee '$rd/r3p-wire.json'"
    check "r3p_${label}_injector_and_stub_sent_exactly_the_predictor_answer" bash -c "python3 -I '$CHK' stub '$SCHED' '$rd' '$rd/injector/tx.jsonl' | tee '$rd/r3p-stub.json'"
    check "r3p_${label}_predictor_answer_equals_formula_on_n6_certified_window" bash -c "python3 -I '$CHK' predictor '$SCEN' '$SCHED' '$rd' | tee '$rd/r3p-predictor.json'"
    check "r3p_${label}_influx_equals_ipc_full_for_the_read_counter" bash -c "python3 -I '$CHK' influx-ipc '$SCEN' '$rd' | tee '$rd/r3p-influx-ipc.json'"
    check "r3p_${label}_d7_target_addressed" bash -c "python3 -I '$CHK' d7 '$L' | tee '$rd/r3p-d7.json'"
    check "r3p_${label}_observation_change_gives_the_preregistered_decisions" bash -c "python3 -I '$CHK' observation '$SCEN' '$SCHED' '$rd' | tee '$rd/r3p-observation.json'"
    check "r3p_${label}_post_handover_membership_observed" bash -c "python3 -I '$CHK' membership '$SCHED' '$rd' | tee '$rd/r3p-membership.json'"
    check "r3p_${label}_predictor_driven_applied_at_least_one" bash -c "python3 -I '$CHK' driven '$SCHED' '$L' '$rd' | tee '$rd/r3p-driven.json'"
    check "r3p_${label}_no_token_in_the_predictor_dir" python3 -I "$CHK" secrets "$rd" "$TOKEN_FILE"
}

if [ "$MODE" = calibrate ]; then
    rung_live calib
    wcal() { python3 -I "$G/r2-checks.py" w "$RUNS/calib/pacer/pacer-summary.json" "$T_CTL_S" --count "$N_POS" | tee "$e/r3p-w-calibration.json"; }
    check r3p_calib_w_from_complete_trigger_steps wcal
    fact calibration "$(cat "$e/r3p-w-calibration.json" 2>/dev/null || echo null)"
else
    NLIVE=3; [ "$MODE" = single ] && NLIVE=1
    for i in $(seq "$NLIVE"); do
        if [ "$i" = 1 ]; then rung_live "live$i" --dump; else rung_live "live$i"; fi
    done
fi

if [ "$MODE" = c1 ]; then
    rung_c1
    # every trigger's outcome identical across the three live runs (also inside C1's ledger equality)
    same_outcomes() {
        python3 -I - "$RUNS" <<'PY'
import json, sys
o = {r: [json.loads(l)["decision"] for l in open("%s/%s/r3p/predictor-records.jsonl" % (sys.argv[1], r))] for r in ("live1", "live2", "live3")}
print(json.dumps(o))
sys.exit(0 if o["live1"] and o["live1"] == o["live2"] == o["live3"] else 1)
PY
    }
    check r3p_c1_every_trigger_outcome_identical_across_live_runs same_outcomes
    [ -z "$REF" ] || rung_reference "$REF" --file "predictor-records=$RUNS/live1/r3p/predictor-records.jsonl" \
        --file "schedule=$SCHED" --file "scenario=$SCEN" --recorded "xapp-image-ids.json=$e/xapp-image-ids.json"
fi

if [ "$MODE" != calibrate ]; then
    run_facts() { python3 -I "$G/r0-run-facts.py" "$e" | tee "$e/r3p-run-facts.json"; }
    check r3p_runs_kpm_moved_c2_c5_reset_fresh run_facts
    for k in kpmUeListMoved c2 c5 resetEvidence; do
        fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/r3p-run-facts.json" "$k" 2>/dev/null || echo null)"
    done
    fact predictorDrivenApplied "$(python3 -I -c 'import glob,json,sys; print(json.dumps({p.split("/")[-2]: json.load(open(p))["predictorDrivenApplied"] for p in sorted(glob.glob(sys.argv[1]+"/*/r3p-driven.json"))}))' "$RUNS" 2>/dev/null || echo null)"
    fact observationChange "$(python3 -I -c 'import glob,json,sys; print(json.dumps({p.split("/")[-2]: json.load(open(p))["decisions"] for p in sorted(glob.glob(sys.argv[1]+"/*/r3p-observation.json"))}))' "$RUNS" 2>/dev/null || echo null)"
fi
rung_final_facts
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

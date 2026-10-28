#!/usr/bin/env bash
# Gate R2 (VM side): the TS xApp decides from the stub QP's fixed predictions and controls ns-3 through rc's gRPC
# (G3), lock-step pacing, agents enb:1, gnb:2, gnb:3, the R0 radio config. A trigger is one 30003 from the RMR
# injector naming one UE (the decimal IMSI); the TS xApp asks the stub (30000), gets its prediction (30002) and
# hands over when the best cell beats the serving cell by more than the A1 threshold.
#
#   gate-r2-ts-stub-qp.sh [--mode c1|single|calibrate] [--dev]
#
# --mode c1 (default): C8, live1..live3, the RIC-free replay, the --RngRun=2 replay, C1. --mode single (the M9
# chain): C8 and one live run with its per-run checks. --mode calibrate: one live run of the calibration block
# (scripts/gates/r2-scenario.json), the per-run checks, and W = max(1 s, 3 x L_max) for rung-config.json.
# --dev labels the run a rehearsal (verdict.json `dev: true`); it is not the gate.
#
# Per run, from a fresh RIC state: rc_ric_reset (bucket, rc, kpimon, hw-go, rtmgr), capture, agents CONNECTED and
# subscribed, then the TS xApp and stub pods recreated (the TS xApp reads e2mgr's nodeb list only at start-up),
# their appmgr registrations ensured (neither registers itself), rtmgr restarted again with a session to every
# xApp and a1mediator, the A1 threshold set again (the TS xApp starts at 0), the
# stub's table loaded and the injector started. Positives need one control within T_ctl, negatives none within W.
# shellcheck disable=SC2034  # SINKX and PACERX are read by paced-lib.sh
source "$(dirname "$0")/lib.sh"
gate_init r2
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/ts-lib.sh"
source "$(dirname "$0")/paced-lib.sh"
source "$(dirname "$0")/influx-dump.sh"
source "$(dirname "$0")/ts-rung-lib.sh"
RUNG=r2

DEV=0; MODE=c1
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --dev) DEV=1; shift ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
case "$MODE" in c1|single|calibrate) ;; *) log "bad --mode $MODE"; exit 2 ;; esac
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
T_GATE_S=$(python3 -I "$CFG" get deadlines.T_gate_s)
T_CTL_S=$(python3 -I "$CFG" get deadlines.T_ctl_s)
TCTL_PROV=$(python3 -I "$CFG" get deadlines.T_ctl_s.provenance)
W_S=$(python3 -I "$CFG" get deadlines.W_s)
W_PROV=$(python3 -I "$CFG" get deadlines.W_s.provenance)
THRESH=$(python3 -I "$CFG" get scenario.outageThreshold_dB)
THRESH_PROV=$(python3 -I "$CFG" get scenario.outageThreshold_dB.provenance)
A1_TH=$(python3 -I "$CFG" get a1_threshold)
A1_PROV=$(python3 -I "$CFG" get a1_threshold.provenance)
SUB2=$(python3 -I "$CFG" get substitutions.ts_xapp_default_rmr_handler.applied)
SUB3=$(python3 -I "$CFG" get substitutions.ts_xapp_a1_payload_string.applied)
PACER_PORT=38499
NODES="enb:1,gnb:2,gnb:3"
SCEN="$HARNESS_DIR/scripts/gates/r2-scenario.json"
CHK="$HARNESS_DIR/scripts/gates/r2-checks.py"
SEND="$HARNESS_DIR/scripts/gates/send-rmr.sh"
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 "--outageThreshold=$THRESH")
SINKX=(); PACERX=()
CALX=(); [ "$MODE" = calibrate ] && CALX=(--calibrate)
# the scenario's threshold is the one the calibration sets; gated runs read it from rung-config.json
SCEN_TH=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["threshold"])' "$SCEN")
[ "$MODE" = calibrate ] && A1_TH="$SCEN_TH" && A1_PROV="scenario threshold (calibration run)"
N_POS=$(python3 -I "$CHK" triggers "$SCEN" "${CALX[@]}" | python3 -I -c 'import json,sys; print(sum(1 for t in json.load(sys.stdin) if t["kind"] == "positive"))')
fact mode "$(json_str "$MODE")"
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
fact positives "$N_POS"
fact vmLoadStart "$(json_str "$(uptime)")"
record r2_args true "dev $DEV; mode $MODE; T_ctl $T_CTL_S s; W $W_S s ($W_PROV); A1 threshold $A1_TH ($A1_PROV); substitution 2 $SUB2; substitution 3 $SUB3; outage threshold $THRESH dB; rc pin $RC_SHA; TS pin $TS_SHA"
# the gated values name the evidence that measured them
cfg_ok() {
    case "$TCTL_PROV" in *evidence/r0/*) ;; *) echo "T_ctl provenance does not name evidence/r0/"; return 1 ;; esac
    case "$THRESH_PROV" in *evidence/r0/*) ;; *) echo "outage threshold provenance does not name evidence/r0/"; return 1 ;; esac
    [ "$MODE" = calibrate ] && { echo "calibration: W and the A1 threshold are measured here"; return 0; }
    case "$W_PROV" in *evidence/r2/*) ;; *) echo "W provenance does not name an R2 calibration (evidence/r2/)"; return 1 ;; esac
    [[ "$A1_TH" =~ ^[1-9][0-9]*$ ]] && [ "$A1_TH" = "$SCEN_TH" ] || { echo "A1 threshold $A1_TH (rung-config) != scenario $SCEN_TH, or not a positive integer"; return 1; }
    echo "T_ctl $T_CTL_S s and the outage threshold from R0, W $W_S s from R2 calibration, A1 threshold $A1_TH"
}
check r2_config_values_from_their_evidence cfg_ok
ric_watchdog_bg

check r2_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check r2_ts_source_is_pin_plus_exactly_the_testbed_patches ts_patches_check
check r2_build_tools_present agents_ensure_build_tools
check r2_sctp_module_loaded agents_sctp_module
check r2_ns3_binary_located_at_pins agents_ns3_locate
check r2_pod_log_reader_self_test python3 -I "$HARNESS_DIR/scripts/gates/pod-log-window.py" --self-test
check r2_pacer_self_test python3 -I "$HARNESS_DIR/scripts/gates/pacer-selftest.py"
check r2_kpm_ue_list_judge_self_test python3 -I "$HARNESS_DIR/tools/e2-evidence/kpm-ue-list-moves.py" --self-test
check r2_grpcurl_fetched_and_checksum_verified rc_grpcurl_fetch
# start from pods this gate created: a kept pod's start-up line rotates out of its log
check r2_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket rc_ric_reset pre
check r2_rc_installed_at_pin_and_ready rc_at_pin
# SDL is in-memory: a VM boot (dbaas restart) empties it, so the type is ensured before any a1mediator restart,
# whose check then proves the type survives that restart
check r2_a1_policy_type_20008_present ts_policy_type_ensure
fact a1PolicyTypeCreated "$([ -e "$e/a1-type-create.txt" ] && echo true || echo false)"
check r2_pre_ts_and_stub_pods_fresh_rtmgr_sessions ts_stub_pods_reset pre
ts_at_pin() { [ "$(git -C "$TS_DIR" rev-parse HEAD)" = "$TS_SHA" ] && ts_ready && jq -e '.ts_control_api == "grpc"' \
    <(kc -n ricxapp get cm configmap-ricxapp-trafficxapp-appconfig -o jsonpath='{.data.config-file\.json}' | jq .controls); }
check r2_ts_xapp_at_pin_ready_in_grpc_mode ts_at_pin
check r2_rmr_peer_image_built_self_tested rmr_peer_build
stub_present() { read -r n r _ < <(pod_info ricxapp "ricxapp-$STUB_NAME-") && [ "$r" = true ] && echo "stub $n ready"; }
check r2_stub_qp_deployed stub_present
check r2_xapp_image_ids ts_image_ids
fact xappImageIds "$(cat "$e/xapp-image-ids.json" 2>/dev/null || echo null)"
RC_DEC_TAG=$(bash "$HARNESS_DIR/tools/rc-decode/build.sh" 2>/dev/null | tail -n 1)
check r2_rc_decoder_built test -n "$RC_DEC_TAG"

################################################################################
# C8: the radio config, no RIC
################################################################################
if [ "$MODE" != calibrate ]; then
    check r2_c8_free_run_at_gated_threshold paced_null_run c8free free 0 --RngRun=1
    check r2_c8_lockstep_null_control paced_null_run c8null lockstep 0 --RngRun=1
    c8() { python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare c8free="$RUNS/c8free" c8null="$RUNS/c8null" >"$e/c8-digests.json"; local rc=$?; python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"])' "$e/c8-digests.json"; return $rc; }
    check r2_c8_null_control_equals_free_run c8
    fact c8NullEqualsFree "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["all_equal"]))' "$e/c8-digests.json" 2>/dev/null || echo null)"
fi

################################################################################
# live runs
################################################################################
python3 -I "$CHK" schedule "$SCEN" "$SEND" "$INJ_CTL_PORT" "${CALX[@]}" >"$e/r2-schedule.json"
python3 -I "$CHK" table "$SCEN" "${CALX[@]}" >"$e/r2-stub-table.json"

rung_stub_setup() { RUN_SCHEDULE="$e/r2-schedule.json"; check "r2_${1}_stub_table_loaded" stub_table_load "$e/r2-stub-table.json"; }
rung_judges() {
    local label="$1" rd="$2"
    check "r2_${label}_expected_outcomes_negatives_no_line_late_zero" bash -c "python3 -I '$CHK' expect '$SCEN' '$rd/trace/e2-control-ledger.jsonl' ${CALX[*]} | tee '$rd/r2-expect.json'"
    check "r2_${label}_wire_requests_equal_positives_via_target_with_stub_key" bash -c "python3 -I '$CHK' wire '$SCEN' '$rd/extra/rc-multiset.json' ${CALX[*]} | tee '$rd/r2-wire.json'"
    check "r2_${label}_injector_and_stub_one_request_and_answer_per_trigger" bash -c "python3 -I '$CHK' stub '$SCEN' '$rd/stub-log.json' '$rd/injector/tx.jsonl' ${CALX[*]} | tee '$rd/r2-stub.json'"
}

if [ "$MODE" = calibrate ]; then
    rung_live calib
    wcal() { python3 -I "$CHK" w "$RUNS/calib/pacer/pacer-summary.json" "$T_CTL_S" --count "$N_POS" | tee "$e/r2-w-calibration.json"; }
    check r2_calib_w_from_complete_trigger_steps wcal
    fact calibration "$(cat "$e/r2-w-calibration.json" 2>/dev/null || echo null)"
else
    NLIVE=3; [ "$MODE" = single ] && NLIVE=1
    for i in $(seq "$NLIVE"); do
        if [ "$i" = 1 ]; then rung_live "live$i" --dump; else rung_live "live$i"; fi
    done
    d7() { python3 -I "$CHK" d7 "$RUNS/live1/trace/e2-control-ledger.jsonl" | tee "$e/d7.json"; }
    check r2_d7_every_control_via_the_target_gnb_both_gnbs d7
    fact d7 "$(cat "$e/d7.json" 2>/dev/null || echo null)"
fi

if [ "$MODE" = c1 ]; then
################################################################################
# C1: the replay without the RIC, RngRun 2, and the digest comparisons
################################################################################
rung_c1
fi

################################################################################
# facts: per-run C2, C5, KPM moves, reset evidence, late, restart counts, route owners, slack, hygiene
################################################################################
# (r0-run-facts.py judges the live runs; a calibration has none, its run is judged by the per-run checks above)
if [ "$MODE" != calibrate ]; then
    run_facts() { python3 -I "$HARNESS_DIR/scripts/gates/r0-run-facts.py" "$e" | tee "$e/r2-run-facts.json"; }
    check r2_runs_kpm_moved_c2_c5_reset_fresh run_facts
    for k in kpmUeListMoved c2 c5 resetEvidence; do
        fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/r2-run-facts.json" "$k" 2>/dev/null || echo null)"
    done
fi
per_run_fact() {   # <file in each run dir> <key[,key...]>: {run: value, or {key: value} for several keys}
    python3 -I - "$RUNS" "$1" "$2" <<'PY'
import glob, json, os, sys
keys = sys.argv[3].split(",")
out = {}
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*", sys.argv[2]))):
    d = json.load(open(f))
    out[os.path.basename(os.path.dirname(f))] = d[keys[0]] if len(keys) == 1 else {k: d[k] for k in keys}
print(json.dumps(out))
PY
}
fact c2AgentSplit "$(per_run_fact agent-c2.json staticRejects,postBye 2>/dev/null || echo null)"
fact late "$(per_run_fact r2-expect.json late 2>/dev/null || echo null)"
fact outcomes "$(per_run_fact r2-expect.json outcomes 2>/dev/null || echo null)"
fact wireRequests "$(per_run_fact r2-wire.json requests,positives,targetKeys 2>/dev/null || echo null)"
fact tsResetEvidence "$(python3 -I - "$e" <<'PY' 2>/dev/null || echo null
import glob, json, os, sys
out = {}
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*-ts-reset.json"))):
    d = json.load(open(f))
    out[os.path.basename(f)[:-len("-ts-reset.json")]] = {"fresh": d["fresh"], "after": {k: v["name"] for k, v in d["after"].items()}}
print(json.dumps(out))
PY
)"
fact xappRegistration "$(python3 -I - "$e" <<'PY' 2>/dev/null || echo null
import glob, json, os, sys
out = {}
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*-appmgr-xapps.json"))):
    out[os.path.basename(f)[:-len("-appmgr-xapps.json")]] = sorted(
        "%s@%s:%s" % (i["name"], i["ip"], i["port"]) for a in json.load(open(f)) for i in a.get("instances") or [])
print(json.dumps(out))
PY
)"
fact stubOtherTypes "$(per_run_fact r2-stub.json stubOtherTypes 2>/dev/null || echo null)"
fact influxDump "$(python3 -I -c 'import json,os,sys; p=sys.argv[1]; print(json.dumps({"path": "runs/live1/influx-kpimon.csv", "bytes": os.path.getsize(p)} if os.path.exists(p) else None))' "$RUNS/live1/influx-kpimon.csv" 2>/dev/null || echo null)"
facts_final() {
    python3 -I - "$e" <<'PY'
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
json.dump(out, open(e + "/r2-facts.json", "w"), indent=1)
print(json.dumps(out))
sys.exit(0 if dropped == 0 and no_sub == 0 else 1)
PY
}
check r2_ipc_dropped_zero_no_sub_dropped_zero_and_slack_recorded facts_final
for k in minSlack lControlLatencyS ipcDropped droppedNoSub; do
    fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/r2-facts.json" "$k" 2>/dev/null || echo null)"
done
restart_all_zero() { cat "$e"/*-after-pods.tsv 2>/dev/null | awk -F'\t' '$4 != 0 { bad = 1 } END { exit bad }'; }
check r2_restart_counts_all_zero restart_all_zero
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
check r2_no_stray_process no_stray
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

#!/usr/bin/env bash
# Gate S10 (VM side, AC15): the scale gate. scenario-zero with 10 en-gNBs (eNB cell 1, en-gNB cells 2-11, 30 UEs),
# NoAuto, lock-step, 11 agents on ports 38470 + cellId, simTime 8 s (80 steps at T = 100 ms), kpimon at the rung
# defaults; the TS xApp decides from the stub QP and hands over through rc's gRPC. Everything is pre-registered in
# scripts/gates/s10-scenario.json (its _comment holds the trigger rule).
#
#   gate-s10-scale.sh [--dev]
#
# One live run through ts-rung-lib.sh's rung_live (from a fresh RIC state: capture, the 11 agents CONNECTED and
# subscribed, then the TS xApp and the stub recreated, the A1 threshold set, the stub emptied, the injector
# started; the per-run checks of every TS rung), with this gate's hooks:
#   rung_stub_setup  the pacer schedule (per trigger a prepare, s10-checks.py prepare, then one 30003), the stub
#                    emptied, and e2mgr's state and nodeb records of nodes 1..11 saved right after the TS xApp's
#                    restart (the records its cell map was built from)
#   rung_judges      per trigger: one applied ledger line via its serving en-gNB (expect), one acked Style 5
#                    action 3 RICcontrolRequest to that en-gNB naming the target's key (wire), the injector's
#                    30003 and the stub's 30000/30002 exchange (stub)
# then the verdict facts, each judged on wire bytes, the ledger, ns-3 traces or e2mgr records (never an xApp log):
#   agentsConnected                 e2mgr CONNECTED = meid(1) .. meid(11)
#   influxEqualsIpc                 influx-vs-trace.py --every-seq, every node
#   ueTicksWithMoreThan8Measured,   check-s10-neighbours.py on kpimon's own decode of the capture (kpimon-decode-
#   decodedNeighbours               harness --records) against ns-3's MmWaveSinrTime.txt
#   cellIdsGe10InKpm                the decoded KPM names cells 10 and 11
#   tsCellMapKeysGe10               replay-ts-cell-map.py on the saved nodeb records, --expect for every en-gNB,
#                                   --no-key for the eNB, --no-wrong-node
#   appliedPscellChangesToGe10      applied ledger lines to a cell >= 10 with their acked request on the wire
#   influxWindowHolds               each trigger UE's row is inside the TS xApp's 60 s Influx window
#   s10_e2ap_ppid70_every_node      every node's E2AP chunks carry PPID 70 (e2-facts-query.py ppid --node-ips)
#   stepWallS                       the gate's wall time, at most stepWallMaxS
# --dev labels the run a rehearsal (verdict.json `dev: true`); it is not the gate.
# shellcheck disable=SC2034  # SINKX/PACERX are read by paced-lib.sh; RUNG_NNODES/RUNG_SUBSCRIBE_WAIT_S/N_POS/W_S/
#                            # T_GATE_S/EPOCH_MS/PACER/PACER_PORT/T_CTL_S/CLI by ts-rung-lib.sh
SCEN0="$(dirname "$0")/s10-scenario.json"
SIMTIME=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["simTimeS"])' "$SCEN0") || { echo "s10-scenario.json unreadable"; exit 2; }
# ns-3's wall timeout scales with simTime (AC6b: ~171 wall s per sim s); agents-ns3-run.sh reads it when sourced
export NS3_TIMEOUT_S="${NS3_TIMEOUT_S:-$((SIMTIME * 300 + 600))}"
source "$(dirname "$0")/lib.sh"
gate_init s10
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/ts-lib.sh"
source "$(dirname "$0")/paced-lib.sh"
source "$(dirname "$0")/influx-dump.sh"
source "$(dirname "$0")/ts-rung-lib.sh"
RUNG=s10

DEV=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dev) DEV=1; shift ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
SCEN="$HARNESS_DIR/scripts/gates/s10-scenario.json"
CHK="$HARNESS_DIR/scripts/gates/s10-checks.py"
NBR="$HARNESS_DIR/scripts/gates/check-s10-neighbours.py"
SEND="$HARNESS_DIR/scripts/gates/send-rmr.sh"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
MAP="$AGENT_DIR/schema/metric-map.v1.json"
WORK="$HOME/s10-work"; SODIR="$WORK/so"
# sj <dotted key>: a scenario value (lists and objects as JSON)
sj() {
    python3 -I -c 'import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    v = v[k]
print(json.dumps(v) if isinstance(v, (list, dict)) else v)' "$SCEN" "$1"
}
# jf <json file> <key>: one value as JSON, null when absent
jf() { python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get(sys.argv[2])))' "$1" "$2" 2>/dev/null || echo null; }
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
PACER_PORT=38499
NG=$(sj nMmWaveEnbNodes); NN=$((NG + 1))
NODES="enb:1$(for i in $(seq 2 "$NN"); do printf ',gnb:%d' "$i"; done)"
RUNG_NNODES=$NN
RUNG_SUBSCRIBE_WAIT_S=$(sj subscribeWaitS)
N_POS=$(sj triggers | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)))')
STEP_WALL_MAX_S=$(sj stepWallMaxS)
CLI=("--nMmWaveEnbNodes=$NG" "--handoverMode=$(sj handoverMode)" "--simTime=$SIMTIME"
     "--indicationPeriodicity=$(sj indicationPeriodicityS)" "--outageThreshold=$THRESH")
SINKX=(); PACERX=()
fact dev "$([ "$DEV" = 1 ] && echo true || echo false)"
fact scenarioSha256 "$(json_str "$(sha256sum "$SCEN" | cut -d' ' -f1)")"
fact nodes "$(json_str "$NODES")"
fact simTimeS "$SIMTIME"
fact ns3TimeoutS "$NS3_TIMEOUT_S"
fact cli "$(json_str "${CLI[*]}")"
fact tCtlSeconds "$T_CTL_S"
fact a1Threshold "$A1_TH"
fact a1ThresholdProvenance "$(json_str "$A1_PROV")"
fact outageThresholdDb "$THRESH"
fact outageThresholdProvenance "$(json_str "$THRESH_PROV")"
fact positives "$N_POS"
fact vmLoadStart "$(json_str "$(uptime)")"
record s10_args true "dev $DEV; nodes $NODES; CLI ${CLI[*]}; T_ctl $T_CTL_S s; A1 threshold $A1_TH ($A1_PROV); outage threshold $THRESH dB; ns-3 timeout $NS3_TIMEOUT_S s; rc pin $RC_SHA; TS pin $TS_SHA"
# the gated values name the evidence that measured them; the pre-registration is self-consistent
cfg_ok() {
    case "$TCTL_PROV" in *evidence/r0/*) ;; *) echo "T_ctl provenance does not name evidence/r0/"; return 1 ;; esac
    case "$THRESH_PROV" in *evidence/r0/*) ;; *) echo "outage threshold provenance does not name evidence/r0/"; return 1 ;; esac
    case "$W_PROV" in *evidence/r2/*) ;; *) echo "W provenance does not name an R2 calibration (evidence/r2/)"; return 1 ;; esac
    [[ "$A1_TH" =~ ^[1-9][0-9]*$ ]] || { echo "A1 threshold $A1_TH is not a positive integer"; return 1; }
    python3 -I "$CHK" scenario "$SCEN" || return 1
    echo "T_ctl $T_CTL_S s and the outage threshold from R0, W $W_S s from R2 calibration, A1 threshold $A1_TH; scenario consistent"
}
check s10_config_values_from_their_evidence_scenario_consistent cfg_ok
check s10_checks_self_test python3 -I "$CHK" --self-test
check s10_neighbour_judge_self_test python3 -I "$NBR" --self-test
check s10_ts_cell_map_replay_self_test python3 -I "$HARNESS_DIR/scripts/gates/replay-ts-cell-map.py" --self-test
rung_preconditions
# kpimon's own decoder (libe2smwrapper.so from the kpimon image) and the decode harness built against it
so_fresh() { rm -rf "${WORK:?}/so" && mkdir -p "$WORK" && kpimon_extract_so "$SODIR" && test -x "$SODIR/kpimon-decode-harness"; }
check s10_kpimon_so_extracted_from_image so_fresh

################################################################################
# the live run
################################################################################
# jrun <out file> <cmd...>: the command's stdout to the file and to the check log, its exit status kept
jrun() { local o="$1" rc; shift; "$@" >"$o"; rc=$?; cat "$o"; return "$rc"; }
rung_stub_setup() {
    local label="$1" rd="$2"
    RUN_SCHEDULE="$rd/schedule.json"
    stub_empty_and_schedule() {
        local u
        u=$(_stub_url) || return 1
        mkdir -p "$rd/s10"
        python3 -I "$CHK" schedule "$SCEN" "$SEND" "$INJ_CTL_PORT" "$rd" "$u" >"$RUN_SCHEDULE" || return 1
        echo '{"predictions": {}}' >"$rd/s10/empty-table.json"
        stub_table_load "$rd/s10/empty-table.json"
    }
    check "s10_${label}_stub_emptied_and_run_schedule_written" stub_empty_and_schedule
    # after the TS xApp's restart (it reads e2mgr's nodeb list once, at start-up): the records its cell map came from
    nodeb_save() {
        local n m
        mkdir -p "$rd/s10"
        e2mgr_states >"$rd/s10/e2mgr-states.json" || { echo "e2mgr nodeb/states unreadable"; return 1; }
        for n in $(seq 1 "$NN"); do
            m=$(meid_of "$n") || return 1
            e2mgr_get "nodeb/$m" >"$rd/s10/e2mgr-node-$n.json" || { echo "e2mgr nodeb/$m unreadable"; return 1; }
        done
        jrun "$rd/s10/agents.json" python3 -I "$CHK" agents "$rd/s10/e2mgr-states.json" "$NN"
    }
    check "s10_${label}_e2mgr_nodeb_records_saved_after_ts_restart_all_nodes_connected" nodeb_save
}
rung_judges() {
    local label="$1" rd="$2"
    check "s10_${label}_ledger_one_applied_line_per_trigger_via_its_serving_en_gnb" \
        jrun "$rd/s10/expect.json" python3 -I "$CHK" expect "$SCEN" "$rd"
    check "s10_${label}_wire_one_acked_style5_action3_request_per_trigger_to_its_serving_en_gnb" \
        jrun "$rd/s10/wire.json" python3 -I "$CHK" wire "$SCEN" "$rd" "$rd/extra/rc-multiset.json"
    check "s10_${label}_injector_and_stub_one_request_and_answer_per_trigger" \
        jrun "$rd/s10/stub.json" python3 -I "$CHK" stub "$SCEN" "$rd" "$rd/injector/tx.jsonl"
}

vm_used() { df -B1 --output=used / | tail -1 | tr -dc '0-9'; }
USED0=$(vm_used)
INFLUX_FROM=$(date +%s)
rung_live live1 --dump
rd="$RUNS/live1"
mkdir -p "$rd/s10"
fact triggers "$(python3 -I - "$rd/s10" <<'PY' 2>/dev/null || echo null
import glob, json, os, sys
out = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "trigger-*.json")), key=lambda p: int(p.rsplit("-", 1)[1][:-5])):
    r = json.load(open(f))
    out.append({k: r[k] for k in ("step", "imsi", "ueId", "serving", "servingKey", "target", "targetKey")})
print(json.dumps(out))
PY
)"
fact agentsConnected "$(jf "$rd/s10/agents.json" agentsConnected)"
fact pacerAbortReason "$(jf "$rd/pacer/pacer-summary.json" pacerAbortReason)"

################################################################################
# verdict facts
################################################################################
check s10_influx_exported influx_export s10-live1 "$INFLUX_FROM"
influx_every() {
    local n bad=0
    for n in $(seq 1 "$NN"); do
        python3 -I "$E2EV/influx-vs-trace.py" --every-seq --map "$MAP" --trace "$rd/trace/e2-ipc-trace-$n.jsonl" \
            --influx-cell "$e/s10-live1-influx-cell.csv" --influx-ue "$e/s10-live1-influx-ue.csv" --ue-context-dir "$rd/trace" \
            --node "$n" --out "$rd/s10/influx-vs-trace-$n.json" >/dev/null 2>"$rd/s10/influx-vs-trace-$n.stderr" ||
            { echo "node $n: Influx differs from its IPC trace ($(tail -c 300 "$rd/s10/influx-vs-trace-$n.stderr"))"; bad=1; }
    done
    python3 -I - "$rd/s10" "$NN" <<'PY' | tee "$rd/s10/influx-equals-ipc.json"
import json, os, sys
d, n = sys.argv[1], int(sys.argv[2])
per = {}
for k in range(1, n + 1):
    try:
        a = json.load(open(os.path.join(d, "influx-vs-trace-%d.json" % k)))["all"]
        per[k] = {x: a.get(x) for x in ("every_seq_equal", "trace_samples", "trace_ue_rows", "influx_ue_rows", "ue_rows_ueid_mismatch")}
    except (OSError, ValueError, KeyError):
        per[k] = None
print(json.dumps({"influxEqualsIpc": all(v and v["every_seq_equal"] is True for v in per.values()), "perNode": per}))
PY
    return "$bad"
}
check s10_influx_equals_ipc_trace_every_seq_every_node influx_every
fact influxEqualsIpc "$(jf "$rd/s10/influx-equals-ipc.json" influxEqualsIpc)"
# kpimon's own decode of every KPM indication on the wire
kpm_decode() {
    python3 -I "$HARNESS_TOOLS/pcap-to-lines.py" "$e/live1.pcap" >"$rd/s10/kpm-lines.txt" || return 1
    LD_LIBRARY_PATH="$SODIR" "$SODIR/kpimon-decode-harness" --records <"$rd/s10/kpm-lines.txt" >"$rd/s10/kpm-records.jsonl" \
        2>"$rd/s10/kpm-records.stderr" || { tail -c 300 "$rd/s10/kpm-records.stderr"; return 1; }
    python3 -I - "$rd/s10/kpm-lines.txt" "$rd/s10/kpm-records.jsonl" <<'PY'
import json, sys
lines = sum(1 for l in open(sys.argv[1]) if l.strip())
recs = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
bad = sum(1 for r in recs if r.get("hdr_code") != "RC_OK" or r.get("msg_code") != "RC_OK")
print("wire indications %d, decoded %d, not RC_OK %d" % (lines, len(recs), bad))
sys.exit(0 if lines and lines == len(recs) and not bad else 1)
PY
}
check s10_kpm_every_indication_decoded_by_kpimons_library kpm_decode
nbr() {
    python3 -I "$NBR" "$rd/s10/kpm-records.jsonl" --map "$MAP" --trace-dir "$rd/trace" --sinr "$rd/ns3run/$(sj neighbours.sinrTrace)" \
        --out "$rd/s10/neighbours.json" --max-neigh "$(sj neighbours.maxNeigh)" --guard-ms "$(sj neighbours.guardMs)" \
        --expect-cells "$(sj expectCellIdsGe10 | tr -d '[] ')"
}
check s10_kpm_neighbour_list_exactly_8_when_more_than_8_cells_measured nbr
cells_ge10() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["cellIdsGe10InKpm"], d["cellIdsGe10BySource"]); sys.exit(0 if d["cellIdsGe10Pass"] else 1)' "$rd/s10/neighbours.json"; }
check s10_kpm_names_cell_ids_10_and_11 cells_ge10
for k in ueTicksWithMoreThan8Measured decodedNeighbours maxDecodedNeighbours ueTicksJudged cellIdsGe10InKpm; do
    fact "$k" "$(jf "$rd/s10/neighbours.json" "$k")"
done
# the TS xApp's cell map, replayed from the e2mgr records saved right after its restart
cellmap() {
    local args=() files=() n
    mapfile -t args < <(python3 -I "$CHK" cellmap-args "$SCEN")
    for n in $(seq 1 "$NN"); do files+=("$rd/s10/e2mgr-node-$n.json"); done
    python3 -I "$HARNESS_DIR/scripts/gates/replay-ts-cell-map.py" "${files[@]}" "${args[@]}" >"$rd/s10/cellmap-replay.json" || return 1
    jrun "$rd/s10/cellmap-facts.json" python3 -I "$CHK" cellmap-facts "$SCEN" "$rd/s10/cellmap-replay.json"
}
check s10_ts_cell_map_replay_every_en_gnb_key_no_enb_key_no_wrong_node cellmap
fact tsCellMapKeysGe10 "$(jf "$rd/s10/cellmap-facts.json" tsCellMapKeysGe10)"
check s10_applied_pscell_change_to_a_cell_ge_10_ledger_and_wire \
    jrun "$rd/s10/applied-ge10.json" python3 -I "$CHK" applied-ge10 "$SCEN" "$rd" "$rd/extra/rc-multiset.json"
fact appliedPscellChangesToGe10 "$(jf "$rd/s10/applied-ge10.json" appliedPscellChangesToGe10)"
check s10_trigger_ue_rows_inside_the_ts_xapp_influx_window \
    jrun "$rd/s10/influx-window.json" python3 -I "$CHK" influx-window "$SCEN" "$rd" "$rd/influx-kpimon.csv"
fact influxWindowHolds "$(jf "$rd/s10/influx-window.json" influxWindowHolds)"
# the facts file rung_live judged per run (s10_live1_e2ap_ppid70_every_node), under the pre-registered name
check s10_e2ap_ppid70_every_node python3 -I "$E2EV/e2-facts-query.py" "$e/live1-sub-facts.json" ppid --node-ips "$rd/node-ips.json"
rate() { jrun "$rd/s10/rate.json" python3 -I "$CHK" rate "$rd/pacer/pacer-log.jsonl" "$SIMTIME"; }
check s10_wall_rate_measured rate
fact wallRate "$(cat "$rd/s10/rate.json" 2>/dev/null || echo null)"

################################################################################
# disk, hygiene, the step's wall time
################################################################################
USED1=$(vm_used)
python3 -I - "$USED0" "$USED1" "$rd" "$e" >"$e/s10-disk.json" <<'PY'
import json, os, sys
u0, u1, rd, e = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
def tree(p):
    return sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs if not os.path.islink(os.path.join(r, f)))
pcap = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(e) for f in fs if ".pcap" in f)
print(json.dumps({"vmRootUsedDeltaGiB": round((u1 - u0) / 2**30, 3), "evidenceBytes": tree(e), "traceBytes": tree(rd + "/trace"),
                  "ns3runBytes": tree(rd + "/ns3run"), "pcapBytes": pcap}))
PY
fact disk "$(cat "$e/s10-disk.json" 2>/dev/null || echo null)"
rm -rf "${WORK:?}/so"
rung_final_facts
check s10_hygiene agents_hygiene
# every agent IPC port of this topology (38471-38481) and the pacer's: no TCP listener, no SCTP socket
ports_clear() {
    local bad=0 re=':(3847[0-9]|3848[01]|38499)([^0-9]|$)'
    ss -tlnp 2>/dev/null | grep -E "$re" && bad=1
    ss -Sanp 2>/dev/null | grep -E "$re" && bad=1
    [ "$bad" = 0 ] && echo "no socket on 38470-38481 or 38499"
    return "$bad"
}
check s10_no_socket_on_agent_or_pacer_ports ports_clear
fact vmLoadEnd "$(json_str "$(uptime)")"
STEP_WALL_S=$(($(date +%s) - GATE_START_EPOCH))
fact stepWallS "$STEP_WALL_S"
wall_ok() { echo "step wall $STEP_WALL_S s, budget $STEP_WALL_MAX_S s"; [ "$STEP_WALL_S" -le "$STEP_WALL_MAX_S" ]; }
check s10_step_wall_within_budget wall_ok
gate_finish

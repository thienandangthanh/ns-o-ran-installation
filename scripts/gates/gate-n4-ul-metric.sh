#!/usr/bin/env bash
# Gate N4 (VM side): the gNB cells' DRB.PdcpSduVolumeUL/DL, no RIC. Two free runs in the rung radio config
# (agents' IPC goes to the null sink) at the pins.conf ns-3 and oran-interface SHAs:
#   uloff  UL traffic off: equal to the UL-off reference REF (the last free-run at the pre-N4 pins, K19) on the
#          ns-3 traces and on the IPC samples after the strict drop of exactly the two new cuUp keys
#          (digest-run.py --n4-ul-off-drop); same trace file names; no N4AUDIT line; provenance at the pins.
#   ulon   UL traffic on (--enableUlTraffic, pattern from --ul-pattern): the per-PDU audit judges both counters
#          (check-pdcp-volume-totals.py, V3), and the UL flag creates no RandomVariable: ues.txt, enbs.txt,
#          CellIdStats.txt and MmWaveSwitchStats.txt equal uloff's, and X2Stats.txt lines before 0.1 s too.
# The V5 window rule needs pandas and runs on the host on the archived ulon IPC trace.
#
# --part dump (K18, step 7): one null-control lock-step run in the same config with UL on, through the agents
# enb:1, gnb:2, gnb:3 and kpimon from a fresh RIC state (kpimon restarted, so the run first gates every agent's
# re-subscription, K13); restart counts 0 before and after; then the whole kpimon bucket as annotated CSV
# (n4-ul-on-dump.csv, token-checked on the VM, V6) and its IPC samples equal to the calibration run CAL's
# (null-control equivalence with UL on). The V5 rule runs on the host on that dump.
#
#   gate-n4-ul-metric.sh --ref <VM dir of the reference run> [--ul-pattern constant|steps] [--dev]
#   gate-n4-ul-metric.sh --part dump --cal <VM dir of the ulon calibration run> [--ul-pattern constant|steps] [--dev]
# shellcheck disable=SC2034  # EPOCH_MS, SINK, PACER, CLI, SINKX, PACERX, PACER_PORT, T_GATE_S and T_CTL_S are read by paced-lib.sh
source "$(dirname "$0")/lib.sh"
gate_init n4
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/paced-lib.sh"

DEV=0; REF=""; CAL=""; PART=v23; PATTERN=constant
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) REF="$2"; shift 2 ;;
        --cal) CAL="$2"; shift 2 ;;
        --part) PART="$2"; shift 2 ;;
        --ul-pattern) PATTERN="$2"; shift 2 ;;
        --dev) DEV=1; shift ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
case "$PATTERN" in constant|steps) ;; *) log "bad --ul-pattern $PATTERN"; exit 2 ;; esac
case "$PART" in v23) ;; dump) source "$(dirname "$0")/rc-lib.sh"; source "$(dirname "$0")/influx-dump.sh" ;;
    *) log "bad --part $PART"; exit 2 ;; esac
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
THRESH=$(python3 -I "$CFG" get scenario.outageThreshold_dB)
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 "--outageThreshold=$THRESH")
SINKX=(); PACERX=(); PACER_PORT=38499; T_GATE_S=10; T_CTL_S=30
G="$HARNESS_DIR/scripts/gates"
fact dev "$([ "$DEV" = 1 ] && echo true || echo false)"
fact part "$(json_str "$PART")"
fact reference "$(json_str "$REF")"
fact calibration "$(json_str "$CAL")"
fact ulPattern "$(json_str "$PATTERN")"
fact outageThresholdDb "$THRESH"
fact vmLoadStart "$(json_str "$(uptime)")"
record n4_args true "part $PART; dev $DEV; ref $REF; cal $CAL; UL pattern $PATTERN; ns-3 $NS3_SHA; oran-interface $ORAN_INTERFACE_SHA"

# the reference is a UL-off free run whose emitter is not the gated pins (it predates the counters)
ref_ok() {
    [ -d "$REF/trace" ] && [ -d "$REF/ns3run" ] || { echo "no run under $REF"; return 1; }
    python3 -I - "$REF/trace" "$NS3_SHA" <<'PY'
import json, pathlib, sys
shas = set()
for p in pathlib.Path(sys.argv[1]).glob("e2-ipc-trace-*.jsonl"):
    h = json.loads(p.open().readline())
    shas.add(h["emitter"]["ns3Sha"])
print("reference emitter ns-3", sorted(shas))
sys.exit(0 if shas and sys.argv[2] not in shas else 1)
PY
}
[ "$PART" = v23 ] && check n4_reference_is_a_pre_n4_free_run ref_ok
check n4_build_tools_present agents_ensure_build_tools
check n4_ns3_binary_located_at_pins agents_ns3_locate

emitter_at_pins() {
    python3 -I - "$RUNS/$1/trace" "$NS3_SHA" "$ORAN_INTERFACE_SHA" <<'PY'
import json, pathlib, sys
got = set()
for p in pathlib.Path(sys.argv[1]).glob("e2-ipc-trace-*.jsonl"):
    em = json.loads(p.open().readline())["emitter"]
    got.add((em["ns3Sha"], em["oranInterfaceSha"]))
print("emitter", sorted(got))
sys.exit(0 if got == {(sys.argv[2], sys.argv[3])} else 1)
PY
}

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

################################################################################
# dump: the K18 UL-on Influx dump for QP
################################################################################
if [ "$PART" = dump ]; then
    NODES="enb:1,gnb:2,gnb:3"; rd="$RUNS/dump"
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    cal_ok() { [ -d "$CAL/trace" ] && grep -q '^N4AUDIT v1' "$CAL/ns3run/stdout.txt" && echo "calibration run $CAL is UL on"; }
    check n4_dump_calibration_run_present cal_ok
    check n4_dump_nist_tree_at_testbed_sha agents_tree_at_testbed_sha
    check n4_dump_sctp_module_loaded agents_sctp_module
    check n4_dump_ric_reset_fresh_pods_and_bucket rc_ric_reset dump
    check n4_dump_rc_at_pin_and_ready rc_at_pin
    check n4_dump_agents_connected_set_exact gate_bringup agents "$NODES"
    all_subscribed() {
        local deadline=$(($(date +%s) + 180)) rows
        while [ "$(date +%s)" -lt "$deadline" ]; do
            rows=$(agents_stats_all)
            echo "$rows" | awk '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == 3) }' && { echo "$rows"; return 0; }
            sleep 3
        done
        echo "$rows"; return 1
    }
    check n4_dump_kpimon_resubscribed_every_agent all_subscribed
    check n4_dump_pods_snapshot_before rc_pod_snapshot dump-before
    check n4_dump_restart_counts_zero_before rc_restarts_zero dump-before
    run_it() {
        local pp rc
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" >"$rd/pacer.log" 2>&1 &
        pp=$!
        paced_wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
        ns3_start "$rd/ns3run" "${CLI[@]}" --RngRun=1 "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 \
            --e2TraceDir="$rd/trace" --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" \
            --enableUlTraffic=true "--ulTrafficPattern=$PATTERN" || { kill "$pp"; return 1; }
        ns3_wait; rc=$NS3_RC
        paced_pacer_finish "$pp"
        echo "$rc" >"$rd/ns3-exit"
        echo "dump: ns-3 exit $rc, pacer exit $PACER_RC (want 0 and 0)"
        [ "$rc" = 0 ] && [ "$PACER_RC" = 0 ]
    }
    check n4_dump_null_control_lockstep_ul_on_run run_it
    check n4_dump_emitter_at_pins emitter_at_pins dump
    check n4_dump_pods_snapshot_after rc_pod_snapshot dump-after
    check n4_dump_restart_counts_zero_after rc_restarts_zero dump-after
    sleep 5   # kpimon writes each indication as it decodes it; let the last period land
    check n4_dump_agents_stopped agents_stop
    check n4_dump_influx_bucket_dumped_without_token influx_dump "$e/n4-ul-on-dump.csv"
    cal_eq() {
        python3 -I "$G/digest-run.py" --compare --components ipc CAL="$CAL" DUMP="$rd" >"$e/dump-vs-cal.json"
        local rc=$?
        python3 -I -c 'import json,sys; print("all_equal", json.load(open(sys.argv[1]))["all_equal"])' "$e/dump-vs-cal.json"
        return $rc
    }
    check n4_dump_ipc_equals_the_calibration_run cal_eq
    check n4_no_stray_process no_stray
    fact vmLoadEnd "$(json_str "$(uptime)")"
    gate_finish
    exit $?
fi

################################################################################
# uloff: V2
################################################################################
check n4_uloff_free_run paced_null_run uloff free 0 --RngRun=1
check n4_uloff_emitter_at_pins emitter_at_pins uloff
v2() {
    python3 -I "$G/digest-run.py" --compare --components ipc,traces --n4-ul-off-drop REF=absent,CAND=present \
        REF="$REF" CAND="$RUNS/uloff" >"$e/v2-digests.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"], json.dumps(d.get("n4Drop")))' "$e/v2-digests.json"
    return $rc
}
check n4_v2_uloff_equals_reference_after_the_strict_drop v2
fact v2Digests "$(cat "$e/v2-digests.json" 2>/dev/null || echo null)"
same_trace_names() {
    names() { find "$1" -maxdepth 1 -type f ! -name stdout.txt ! -name stderr.txt -printf '%f\n' | sort; }
    diff <(names "$REF/ns3run") <(names "$RUNS/uloff/ns3run") &&
        diff <(cd "$REF/trace" && ls) <(cd "$RUNS/uloff/trace" && ls) && echo "same trace file names"
}
check n4_v2_same_trace_file_names same_trace_names
no_audit() { local n; n=$(grep -c '^N4AUDIT' "$RUNS/uloff/ns3run/stdout.txt"); echo "N4AUDIT lines: $n"; [ "$n" = 0 ]; }
check n4_v2_uloff_prints_no_audit no_audit

################################################################################
# ulon: V3 and the no-RandomVariable check
################################################################################
check n4_ulon_free_run paced_null_run ulon free 0 --RngRun=1 --enableUlTraffic=true "--ulTrafficPattern=$PATTERN"
check n4_ulon_emitter_at_pins emitter_at_pins ulon
v3() {
    python3 -I "$G/check-pdcp-volume-totals.py" "$RUNS/ulon" >"$e/v3.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print({k: d[k] for k in ("a1","a2","a3","a4","a5","perCellMaxErrBits","periodSumMaxErrKbit","ties","overlaps","events","gnbSamples")})' "$e/v3.json"
    return $rc
}
check n4_v3_counters_equal_the_pdcp_audit v3
fact v3 "$(cat "$e/v3.json" 2>/dev/null || echo null)"
no_rv() {
    local f bad=0
    for f in ues.txt enbs.txt CellIdStats.txt MmWaveSwitchStats.txt; do
        cmp -s "$RUNS/uloff/ns3run/$f" "$RUNS/ulon/ns3run/$f" || { echo "$f differs"; bad=1; }
    done
    cmp -s <(awk '$1 < 0.1' "$RUNS/uloff/ns3run/X2Stats.txt") <(awk '$1 < 0.1' "$RUNS/ulon/ns3run/X2Stats.txt") ||
        { echo "X2Stats.txt lines before 0.1 s differ"; bad=1; }
    [ "$bad" = 0 ] && echo "attach, positions, cell ids, switches and X2 before 0.1 s equal"
    return $bad
}
check n4_ul_flag_moves_no_random_draw no_rv
check n4_no_stray_process no_stray
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

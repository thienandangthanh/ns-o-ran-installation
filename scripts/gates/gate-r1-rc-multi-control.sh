#!/usr/bin/env bash
# Gate R1 (VM side): scripted multi-control through the real rc, lock-step pacing, agents enb:1, gnb:2, gnb:3,
# the R0 radio config.
#
#   gate-r1-rc-multi-control.sh [--mode c1|single] [--dev]
#
# --mode single (the M9 chain): C8 and one live run with its per-run checks. --mode c1 (default): all of it.
# --dev labels the run a rehearsal (verdict.json `dev: true`); it is not the gate.
#
# Cases (scripts/gates/r1-scenario.json; within a step the controls are sent one at a time, in list order):
#   (a) step 20   a same-step pair for two IMSIs through different agents: both applied
#   (b) step 30   one IMSI, the same agent, targets 3 (its own cell, sent first) and 2: target 2 applied,
#                 target 3 refused inHandover (C4 order; arrival order would give alreadyOnTarget)
#   (c) step 40   one IMSI, one non-serving target, through agents 3 (sent first) and 2: node 2 applied,
#                 node 3 refused inHandover (the lower nodeId wins)
#   (d) step 50   an unknown IMSI: refused unknownImsi
#   f2  fault run (ii): one control at step 20, then a control sent after the final barrier through the eNB
#       agent while the pacer holds endAck: exactly one RICcontrolFailure, no ledger line, and agent 1 counts
#       it as failed on bye (rejIpcDown 0), outside the C1 digest set
#
# Order: C8 (null-control lock-step == free-run at the gated threshold), live1..live3 (fresh RIC state each,
# Influx dump after live1), f2, the RIC-free replay of live1, the --RngRun=2 replay, C1. The outage threshold
# comes from rung-config.json (substitution 1, measured by gate r0's Q2), and T_ctl from its calibration.
# shellcheck disable=SC2034  # SINKX and PACERX are read by paced-lib.sh
source "$(dirname "$0")/lib.sh"
gate_init r1
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/paced-lib.sh"
source "$(dirname "$0")/influx-dump.sh"

DEV=0; MODE=c1
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --dev) DEV=1; shift ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
T_GATE_S=$(python3 -I "$CFG" get deadlines.T_gate_s)
T_CTL_S=$(python3 -I "$CFG" get deadlines.T_ctl_s)
TCTL_PROV=$(python3 -I "$CFG" get deadlines.T_ctl_s.provenance)
THRESH=$(python3 -I "$CFG" get scenario.outageThreshold_dB)
THRESH_PROV=$(python3 -I "$CFG" get scenario.outageThreshold_dB.provenance)
PACER_PORT=38499
NODES="enb:1,gnb:2,gnb:3"
SCEN="$HARNESS_DIR/scripts/gates/r1-scenario.json"
CHK="$HARNESS_DIR/scripts/gates/r0-checks.py"
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 "--outageThreshold=$THRESH")
SINKX=(); PACERX=()
N_CTL=$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["controls"]))' "$SCEN")
case "$MODE" in c1|single) ;; *) log "bad --mode $MODE"; exit 2 ;; esac
fact mode "$(json_str "$MODE")"
fact dev "$([ "$DEV" = 1 ] && echo true || echo false)"
fact tCtlSeconds "$T_CTL_S"
fact tCtlProvenance "$(json_str "$TCTL_PROV")"
fact outageThresholdDb "$THRESH"
fact outageThresholdProvenance "$(json_str "$THRESH_PROV")"
fact vmLoadStart "$(json_str "$(uptime)")"
record r1_args true "dev $DEV; mode $MODE; T_ctl $T_CTL_S s ($TCTL_PROV); T_gate $T_GATE_S s; threshold $THRESH dB; epoch $EPOCH_MS; rc pin $RC_SHA"
# the gated values name the R0 evidence that measured them
cfg_ok() {
    case "$TCTL_PROV" in *evidence/r0/*) ;; *) echo "T_ctl provenance does not name evidence/r0/"; return 1 ;; esac
    case "$THRESH_PROV" in *evidence/r0/*) ;; *) echo "threshold provenance does not name evidence/r0/"; return 1 ;; esac
    echo "T_ctl $T_CTL_S s, threshold $THRESH dB, both from R0 evidence"
}
check r1_t_ctl_and_threshold_from_r0_evidence cfg_ok
ric_watchdog_bg

check r1_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check r1_build_tools_present agents_ensure_build_tools
check r1_sctp_module_loaded agents_sctp_module
check r1_ns3_binary_located_at_pins agents_ns3_locate
check r1_pod_log_reader_self_test python3 -I "$HARNESS_DIR/scripts/gates/pod-log-window.py" --self-test
check r1_pacer_self_test python3 -I "$HARNESS_DIR/scripts/gates/pacer-selftest.py"
check r1_kpm_ue_list_judge_self_test python3 -I "$HARNESS_DIR/tools/e2-evidence/kpm-ue-list-moves.py" --self-test
check r1_grpcurl_fetched_and_checksum_verified rc_grpcurl_fetch
# start from rc, kpimon and hw-go pods this gate created: a kept pod's start-up line rotates out of its log
check r1_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket rc_ric_reset pre
check r1_rc_installed_at_pin_and_ready rc_at_pin
RC_DEC_TAG=$(bash "$HARNESS_DIR/tools/rc-decode/build.sh" 2>/dev/null | tail -n 1)
check r1_rc_decoder_built test -n "$RC_DEC_TAG"

################################################################################
# C8: the radio config, no RIC
################################################################################
check r1_c8_free_run_at_gated_threshold paced_null_run c8free free 0 --RngRun=1
check r1_c8_lockstep_null_control paced_null_run c8null lockstep 0 --RngRun=1
c8() { python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare c8free="$RUNS/c8free" c8null="$RUNS/c8null" >"$e/c8-digests.json"; local rc=$?; python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"])' "$e/c8-digests.json"; return $rc; }
check r1_c8_null_control_equals_free_run c8
fact c8NullEqualsFree "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["all_equal"]))' "$e/c8-digests.json" 2>/dev/null || echo null)"

################################################################################
# live runs
################################################################################
RC_EP=$(rc_endpoint)
python3 -I "$CHK" schedule "$SCEN" "$RC_EP" --rc-send "$HARNESS_DIR/scripts/gates/rc-send.sh" >"$e/r1-schedule.json"
python3 -I "$CHK" schedule "$SCEN" "$RC_EP" --rc-send "$HARNESS_DIR/scripts/gates/rc-send.sh" --fault-stop \
    --confirm bash "$HARNESS_DIR/scripts/gates/agent-forward-wait.sh" 1 2 5 >"$e/f2-schedule.json"

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

# r1_live <label> <schedule.json> <n-requests> <n-ledger-lines> <n-agent-local> [--dump]: one run from a fresh RIC
# state; the per-run checks.
r1_live() {
    local label="$1" sched="$2" nreq="$3" nled="$4" nlocal="$5" dump="${6:-}" rd="$RUNS/$1" pp rc cap_t0
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace" "$rd/extra"
    check "r1_${label}_ric_reset_fresh_pods_and_bucket" rc_ric_reset "$label"
    check "r1_${label}_route_dump_start" rc_route_dump "$label-start"
    printf '%s\tstart\t%s\t%s\t%s\t%s\n' "$label" "${ROUTE_OWNER_12041:-}" "${ROUTE_OWNER_12042:-}" \
        "${ROUTE_OWNER_E2TERM_12041:-}" "${ROUTE_OWNER_E2TERM_12042:-}" >>"$e/route-owners.tsv"
    check "r1_${label}_capture_started_before_agents" capture_start "$label" docker0 'ip proto 132'
    cap_t0=$(date +%s)
    check "r1_${label}_agents_connected_set_exact" gate_bringup agents "$NODES"
    echo '{}' >"$rd/node-ips.json"
    check "r1_${label}_agent_ips_recorded" agents_record_ips "$rd/node-ips.json"
    check "r1_${label}_every_agent_ready_and_subscribed" all_subscribed
    check "r1_${label}_pods_snapshot_before" rc_pod_snapshot "$label-before"
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
    check "r1_${label}_lockstep_run_exits_clean" run_it
    check "r1_${label}_pods_snapshot_after" rc_pod_snapshot "$label-after"
    check "r1_${label}_route_dump_end" rc_route_dump "$label-end"
    printf '%s\tend\t%s\t%s\t%s\t%s\n' "$label" "${ROUTE_OWNER_12041:-}" "${ROUTE_OWNER_12042:-}" \
        "${ROUTE_OWNER_E2TERM_12041:-}" "${ROUTE_OWNER_E2TERM_12042:-}" >>"$e/route-owners.tsv"
    check "r1_${label}_restart_counts_zero_rc_kpimon_hw_go_agents" rc_restarts_zero "$label-after"
    check "r1_${label}_agent_logs_with_stats_after_bye" agent_logs_after_bye "$rd"
    if [ "$dump" = --dump ]; then
        dump_it() { influx_dump "$rd/influx-kpimon.csv"; }
        check "r1_${label}_influx_dump_written_without_the_token" dump_it
    fi
    check "r1_${label}_agents_stopped" agents_stop
    check "r1_${label}_capture_stopped" capture_stop "$label"
    kpimon_window() { kpimon_logs_since "$cap_t0" "$rd/kpimon.log" && kpimon_log_window_summary "$rd/kpimon.log"; }
    check "r1_${label}_kpimon_log_window_complete" kpimon_window
    wmore0() { local c; c=$(kpimon_log_counts "$rd/kpimon.log"); echo "$c" | tr '\n' ' '; echo "$c" | awk -F= '($1=="hdr_wmore"||$1=="msg_wmore") && $2!=0 {bad=1} END{exit bad}'; }
    check "r1_${label}_kpimon_zero_rc_wmore" wmore0
    extract() {
        python3 -I "$HARNESS_DIR/tools/e2-evidence/wire-c1-extract.py" "$e/$label.pcap" --node-ips "$rd/node-ips.json" \
            --ledger "$rd/trace/e2-control-ledger.jsonl" --out-dir "$rd/extra" --t0 "$cap_t0" \
            --decode-cmd "$(dk_cmd) run --rm -i $RC_DEC_TAG" --expect-requests "$nreq" --expect-agent-local "$nlocal"
    }
    check "r1_${label}_wire_one_terminal_answer_per_request_joined_to_ledger" extract
    c2() { python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$rd/trace/e2-control-ledger.jsonl" "$rd/pacer/pacer-log.jsonl" --expect "$nled"; }
    check "r1_${label}_c2_ledger" c2
    check "r1_${label}_c9_handover_rows_match_applied_lines" python3 -I "$HARNESS_DIR/scripts/gates/check-c9-handover-trace.py" "$rd"
    kpm_moves() {
        python3 -I "$HARNESS_DIR/tools/e2-evidence/kpm-ue-list-moves.py" "$e/$label.pcap" --node-ips "$rd/node-ips.json" \
            --ledger "$rd/trace/e2-control-ledger.jsonl" --epoch-ms "$EPOCH_MS" --t0 "$cap_t0" --out "$rd/kpm-ue-moves.json"
    }
    check "r1_${label}_kpm_ue_lists_move_applied_and_keep_refused" kpm_moves
    # no emitter left and came back, no agent accepted a second ns-3 connection
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
    check "r1_${label}_one_connection_per_emitter_and_agent" one_connection
    # C2 split from the agents' own counters: static rejects (answered without ns-3) and failures on bye
    agent_c2() {
        python3 -I - "$rd" "$nlocal" <<'PY' | tee "$rd/agent-c2.json"
import glob, json, sys
rd, nlocal = sys.argv[1], int(sys.argv[2])
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
sys.exit(0 if static == 0 and post_bye == nlocal and pending == 0 else 1)
PY
    }
    check "r1_${label}_agent_static_rejects_zero_post_bye_as_expected" agent_c2
}

NLIVE=3; [ "$MODE" = single ] && NLIVE=1
for i in $(seq "$NLIVE"); do
    if [ "$i" = 1 ]; then r1_live "live$i" "$e/r1-schedule.json" "$N_CTL" "$N_CTL" 0 --dump; else r1_live "live$i" "$e/r1-schedule.json" "$N_CTL" "$N_CTL" 0; fi
    check "r1_live${i}_expected_outcomes_and_afterseq" python3 -I "$CHK" expect "$SCEN" "$RUNS/live$i/trace/e2-control-ledger.jsonl"
    # the C4 sort was exercised: in (b) the refused line carries the lower ctlId of node 2 (it was sent first);
    # in (c) ns-3 received node 3's control before node 2's
    c4_used() {
        python3 -I - "$RUNS/live$i" <<'PY'
import json, sys
rd = sys.argv[1]
led = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
b = {x["outcome"] + "/" + x["cause"]: x for x in led if x["rxSeq"] == 30 and x["imsi"] == 2}
summ = json.load(open(rd + "/pacer/pacer-summary.json"))
order40 = [v for v, _ in summ["steps"]["40"]["rxOrder"]]
ok_b = b.get("refused/inHandover", {}).get("ctlId", 0) < b.get("applied/", {}).get("ctlId", 0) and \
    b["refused/inHandover"]["viaNodeId"] == b["applied/"]["viaNodeId"] == 2
ok_c = order40 == [3, 2]
print("step 30:", {k: (v["viaNodeId"], v["ctlId"], v["targetCell"]) for k, v in b.items()}, "step 40 rx order:", order40)
sys.exit(0 if ok_b and ok_c else 1)
PY
    }
    check "r1_live${i}_c4_sort_exercised_not_arrival_order" c4_used
done
d7() { python3 -I "$CHK" d7 "$RUNS/live1/trace/e2-control-ledger.jsonl" | tee "$e/d7.json"; }
check r1_d7_three_paths_two_imsis_both_gnbs d7
fact d7 "$(cat "$e/d7.json" 2>/dev/null || echo null)"

if [ "$MODE" = c1 ]; then
# f2: fault run (ii), the control after the final barrier
r1_live f2 "$e/f2-schedule.json" 2 1 1
f2_check() {
    python3 -I "$CHK" expect "$SCEN" "$RUNS/f2/trace/e2-control-ledger.jsonl" --fault-stop &&
        python3 -I - "$RUNS/f2" <<'PY'
import json, sys
rd = sys.argv[1]
st = json.load(open(rd + "/pacer/pacer-summary.json")).get("stopTrigger") or {}
reqs = json.load(open(rd + "/extra/rc-requests.json"))
ms = json.load(open(rd + "/extra/rc-multiset.json"))
led = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
a1 = json.load(open(rd + "/agent-c2.json"))["perAgent"]["1"]
stop = [m for m in ms if m["imsi"] == 4]
ok = (st.get("ok") is True and len(reqs) == 2 and all(r["viaNode"] == 1 for r in reqs)
      and len(stop) == 1 and stop[0]["answer"] == "failure" and stop[0]["cause"] == "control-failed-to-execute"
      and stop[0]["step"] is None and len(led) == 1 and led[0]["imsi"] == 6
      and a1["forwarded"] == 2 and a1["failedOnBye"] == 1 and a1["rejIpcDown"] == 0 and a1["pending"] == 0)
print("stop trigger", st, "stop control on the wire", stop, "ledger", [(x["imsi"], x["outcome"]) for x in led], "agent 1", a1)
sys.exit(0 if ok else 1)
PY
}
check r1_f2_control_after_final_barrier_one_failure_no_ledger_line_failed_on_bye f2_check

################################################################################
# C1: the replay without the RIC, RngRun 2, and the digest comparisons
################################################################################
PACERX=(--replay "$RUNS/live1/trace/e2-control-ledger.jsonl")
check r1_replay_run_without_the_ric paced_null_run replay lockstep 0 --RngRun=1
check r1_rng2_run_without_the_ric paced_null_run rng2 lockstep 0 --RngRun=2
PACERX=()
rng2_c2() { python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$RUNS/rng2/trace/e2-control-ledger.jsonl" "$RUNS/rng2/pacer/pacer-log.jsonl"; }
check r1_rng2_c2_holds rng2_c2
rng2_c7() {   # the RngRun 2 replay: clean exit (checked above), no late control, no sample dropped, slack recorded
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
check r1_rng2_c7_holds rng2_c7
fact rng2 "$(cat "$e/rng2-c7.json" 2>/dev/null || echo null)"
cmp_runs() { python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare --components "$1" "${@:3}" >"$e/$2.json"; }
c1_live() { cmp_runs ledger,ipc,traces,extra c1-live live1="$RUNS/live1" live2="$RUNS/live2" live3="$RUNS/live3"; }
c1_replay() { cmp_runs ledger,ipc,traces c1-replay live1="$RUNS/live1" replay="$RUNS/replay"; }
c1_rng2() { cmp_runs ledger,ipc,traces c1-rng2 live1="$RUNS/live1" rng2="$RUNS/rng2"; [ $? -eq 1 ]; }   # must differ
check r1_c1_three_live_runs_equal_on_all_components c1_live
check r1_c1_replay_equals_live_on_ledger_ipc_traces c1_replay
check r1_c1_rng2_differs_from_live c1_rng2
jbool() { python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$1" "$2" 2>/dev/null || echo null; }
fact c1 "{\"liveRunsEqual\": $(jbool "$e/c1-live.json" all_equal), \"replayEqual\": $(jbool "$e/c1-replay.json" all_equal), \"rngRun2Differs\": $(python3 -I -c 'import json; print(json.dumps(not json.load(open("'"$e"'/c1-rng2.json"))["all_equal"]))' 2>/dev/null || echo null)}"
fi

################################################################################
# facts: per-run C2, C5, KPM moves, reset evidence, restart counts, route owners, slack, hygiene
################################################################################
run_facts() { python3 -I "$HARNESS_DIR/scripts/gates/r0-run-facts.py" "$e" | tee "$e/r1-run-facts.json"; }
check r1_runs_kpm_moved_c2_c5_reset_fresh run_facts
for k in kpmUeListMoved c2 c5 resetEvidence; do
    fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/r1-run-facts.json" "$k" 2>/dev/null || echo null)"
done
agent_c2_fact() {
    python3 -I - "$RUNS" <<'PY'
import glob, json, os, sys
out = {}
for f in sorted(glob.glob(sys.argv[1] + "/*/agent-c2.json")):
    d = json.load(open(f))
    out[os.path.basename(os.path.dirname(f))] = {"staticRejects": d["staticRejects"], "postBye": d["postBye"]}
print(json.dumps(out))
PY
}
fact c2AgentSplit "$(agent_c2_fact 2>/dev/null || echo null)"
fact influxDump "$(python3 -I -c 'import json,os,sys; p=sys.argv[1]; print(json.dumps({"path": "runs/live1/influx-kpimon.csv", "bytes": os.path.getsize(p)} if os.path.exists(p) else None))' "$RUNS/live1/influx-kpimon.csv" 2>/dev/null || echo null)"
facts_final() {
    python3 -I - "$e" <<'PY'
import glob, json, sys
e = sys.argv[1]
slack = {"T_start": None, "T_gate": None, "T_ctl": None, "W": None}
for log in sorted(glob.glob(e + "/runs/live*/trace/e2-pacing-log.jsonl")) + sorted(glob.glob(e + "/runs/f2/trace/e2-pacing-log.jsonl")):
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
json.dump(out, open(e + "/r1-facts.json", "w"), indent=1)
print(json.dumps(out))
sys.exit(0 if dropped == 0 and no_sub == 0 else 1)
PY
}
check r1_ipc_dropped_zero_no_sub_dropped_zero_and_slack_recorded facts_final
for k in minSlack lControlLatencyS ipcDropped droppedNoSub; do
    fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/r1-facts.json" "$k" 2>/dev/null || echo null)"
done
restart_all_zero() { cat "$e"/live*-after-pods.tsv "$e"/f2-after-pods.tsv 2>/dev/null | awk -F'\t' '$4 != 0 { bad = 1 } END { exit bad }'; }
check r1_restart_counts_all_zero restart_all_zero
fact restartCountsAllZero "$(restart_all_zero && echo true || echo false)"
restart_map() {   # "<run>/<rc|kpimon|hw-go|agent-N>": restart count, from each run's after-snapshot
    python3 -I - "$e" <<'PY'
import glob, json, os, sys
out = {}
for f in sorted(glob.glob(sys.argv[1] + "/*-after-pods.tsv")):
    run = os.path.basename(f)[:-len("-after-pods.tsv")]
    for l in open(f):
        c = l.rstrip("\n").split("\t")
        if c[0] == "agent":
            out["%s/agent-%s" % (run, c[1])] = int(c[3])
        else:
            for k in ("rc", "kpimon", "hw-go"):
                if c[1].startswith("ricxapp-%s-" % k) or (k == "rc" and "xapp-rc-" in c[1]):
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
check r1_no_stray_process no_stray
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

#!/usr/bin/env bash
# Gate S1 (VM side): lock-step pacing (pacer + barrier) without the RIC, then one
# fault run with real agents. R0 config, null sink as the agent stand-in.
#
#   gate-s1-pacer-lockstep.sh --p1-ns3 SHA --p1-oi SHA [--withhold K]
#
# V6 free-run unchanged by the pacing code: p1 (P1 pins, --p1-ns3/--p1-oi) vs free0
#    (pins.conf pair), both free and without --simStartEpochMs; compare-free-run.py.
# V1 null-control equivalence: free vs null (lock-step, pacer with an empty schedule),
#    both with the pinned --simStartEpochMs; digest-run.py on ledger, IPC samples, traces.
# V2 Fallback-1: fb1 = lock-step, the pacer injects scripted controls (and one control
#    after the final barrier); check-ledger.py --expect N; then replay = the pacer
#    replays fb1's ledger; digest-run.py fb1 vs replay on ledger, IPC samples, traces.
# V4 (K9) the forced late control: one ledger line cause=late and one controlAck
#    refused/late; the agent unit test answers a late refusal with
#    RICcontrolFailure control-failed-to-execute (inside the image at TESTBED_SHA).
# V3 fault run (i), twice: the null sink withholds step K (faultsink), and real agents
#    enb:1,gnb:2,gnb:3 with E2_TEST_WITHHOLD_STEP=K against the RIC (faultagent).
#    ns-3 exits 5; e2-pacing-abort.json and the pacer both name step K; the pacer's
#    wall time from `ready` K to `abort` <= T_gate + 5 s; no ledger line after K.
# K10 verdict facts: ipcDropped and droppedNoSub maxima (= 0) and the minimum slack
#    of T_start and T_gate over every paced run (T_ctl and W: no trigger step in S1).
#
# Builds: the P1 pins in ~/s1-build-p1 (taken over from ~/m4-build when that is at
# them; removed at the end), the pins.conf pair in ~/m4-build so M5-M7 reuse it.
source "$(dirname "$0")/lib.sh"
gate_init s1
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"

P1_NS3=""; P1_OI=""; K=30
while [ $# -gt 0 ]; do
    case "$1" in
        --p1-ns3) P1_NS3="$2"; shift 2 ;;
        --p1-oi) P1_OI="$2"; shift 2 ;;
        --withhold) K="$2"; shift 2 ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
e="$EVIDENCE_DIR"
EPOCH_MS=1767225600000   # 2026-01-01T00:00:00Z: sim time 0 for every pinned run (D10)
T_GATE_S=10
PACER_PORT=38499
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1)
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
record s1_args true "p1 ns-3 $P1_NS3 oi $P1_OI; new ns-3 $NS3_SHA oi $ORAN_INTERFACE_SHA testbed $TESTBED_SHA; withhold $K; epoch $EPOCH_MS; cli ${CLI[*]}"
[ -n "$P1_NS3" ] && [ -n "$P1_OI" ] || { record s1_args_complete false "need --p1-ns3 --p1-oi"; gate_finish; exit $?; }

at_shas() { [ "$(git -C "$1/ns-3" rev-parse HEAD 2>/dev/null)" = "$2" ] && [ "$(git -C "$1/ns-3/contrib/oran-interface" rev-parse HEAD 2>/dev/null)" = "$3" ]; }

# s1_build <workdir> <ns3> <oi>: reuse when at those SHAs (the P1 workdir may take over
# ~/m4-build), else build-ns3.sh; prints the provenance.
s1_build() {
    local wd="$1" ns3="$2" oi="$3" bin
    if ! at_shas "$wd" "$ns3" "$oi"; then
        if [ "$wd" = "$HOME/s1-build-p1" ] && at_shas "$HOME/m4-build" "$ns3" "$oi"; then
            rm -rf "$wd" && mv "$HOME/m4-build" "$wd" || return 1
            echo "took over ~/m4-build (at the P1 pins) as $wd"
        else
            timeout --kill-after=60 5400 bash "$HARNESS_DIR/scripts/build-ns3.sh" "$wd" --ns3-sha "$ns3" --oi-sha "$oi" \
                >"$e/build-$(basename "$wd").stdout" 2>"$e/build-$(basename "$wd").stderr" </dev/null || return 1
        fi
    fi
    at_shas "$wd" "$ns3" "$oi" || return 1
    bin=$(find "$wd/ns-3/build/scratch" -maxdepth 1 -type f -perm -u+x -name '*-scenario-zero-*' | head -n 1)
    [ -x "$bin" ] || return 1
    { echo "binary $bin"; echo "ns3 $ns3"; echo "oran-interface $oi"; sha256sum "$bin"; } | tee "$e/provenance-$(basename "$wd").txt"
}

# shellcheck disable=SC2034  # NS3_BIN and NS3_BIN_RE are read by ns3_start/ns3_stray (agents-ns3-run.sh)
s1_use() {
    NS3_BIN=$(find "$1/ns-3/build/scratch" -maxdepth 1 -type f -perm -u+x -name '*-scenario-zero-*' | head -n 1)
    NS3_BIN_RE="^$(printf '%s' "$NS3_BIN" | sed 's/[][\.*^$+?(){}|/]/\\&/g')( |\$)"
    export LD_LIBRARY_PATH="$1/ns-3/build/lib"
}

# _wait_ready <log> <what>: a helper prints READY once it listens.
_wait_ready() {
    for _ in $(seq 50); do grep -q READY "$1" && return 0; sleep 0.2; done
    echo "$2 did not start: $(cat "$1")"; return 1
}

# s1_run <label> <free|lockstep> <want-ns3-exit> [ns-3 args...]: one run with the null sink
# (and, lock-step, the pacer); outputs in $e/runs/<label>. SINKX and PACERX hold extra
# sink and pacer arguments.
SINKX=(); PACERX=()
s1_run() {
    local label="$1" pacing="$2" want="$3" rd="$e/runs/$1" sp pp="" rc prc=""
    shift 3
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    local sargs=(--ports 38471-38473 --out "$rd/sink" --save-lines "${SINKX[@]}")
    local nargs=("${CLI[@]}" "$@" --e2TraceDir="$rd/trace")
    if [ "$pacing" = lockstep ]; then
        sargs+=(--lockstep)
        nargs+=(--e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S")
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" "${PACERX[@]}" >"$rd/pacer.log" 2>&1 &
        pp=$!
        _wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    fi
    python3 -I "$SINK" "${sargs[@]}" >"$rd/sink.log" 2>&1 &
    sp=$!
    _wait_ready "$rd/sink.log" "null sink" || { kill "$sp" $pp; return 1; }
    ns3_start "$rd/ns3run" "${nargs[@]}" || { kill "$sp" $pp; return 1; }
    ns3_wait; rc=$NS3_RC
    if [ -n "$pp" ]; then
        for _ in $(seq 150); do kill -0 "$pp" 2>/dev/null || break; sleep 0.2; done
        kill "$pp" 2>/dev/null; wait "$pp"; prc=$?
    fi
    sleep 1; kill -TERM "$sp"; wait "$sp"
    echo "$rc" >"$rd/ns3-exit"
    echo "$label ($pacing): ns-3 exit $rc (want $want)${pp:+; pacer exit $prc}; sink $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["totals"])' "$rd/sink/summary.json" 2>/dev/null)"
    [ "$rc" = "$want" ]
}

################################################################################
# V6: the pacing code leaves free-run unchanged
################################################################################
check s1_build_p1_pins s1_build "$HOME/s1-build-p1" "$P1_NS3" "$P1_OI"
s1_use "$HOME/s1-build-p1"
check s1_run_p1_free s1_run p1 free 0
check s1_build_new_at_pins s1_build "$HOME/m4-build" "$NS3_SHA" "$ORAN_INTERFACE_SHA"
s1_use "$HOME/m4-build"
check s1_run_free0_free s1_run free0 free 0
v6() {
    python3 -I "$HARNESS_DIR/scripts/gates/compare-free-run.py" p1="$e/runs/p1" free0="$e/runs/free0" >"$e/v6-compare.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print({k: v["pass"] for k, v in d["candidates"].items()}, "all_pass", d["all_pass"])' "$e/v6-compare.json"
    return $rc
}
check s1_v6_free_run_at_new_pins_equals_p1 v6
rm -rf "$HOME/s1-build-p1"

################################################################################
# V1: null-control lock-step equals free-run (same RngRun and simStartEpochMs)
################################################################################
check s1_run_free_pinned_epoch s1_run free free 0 "--simStartEpochMs=$EPOCH_MS"
check s1_run_null_lockstep_empty_schedule s1_run null lockstep 0 "--simStartEpochMs=$EPOCH_MS"
v1() {
    python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare free="$e/runs/free" null="$e/runs/null" >"$e/v1-digests.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"], d["runs"], "ipcDroppedMaxAll", d["ipcDroppedMaxAll"])' "$e/v1-digests.json"
    return $rc
}
check s1_v1_null_control_digest_equals_free_run v1
null_paced_every_step() {
    python3 -I - "$e/runs/null" <<'PY'
import json, sys
s = json.load(open(sys.argv[1] + "/pacer/pacer-summary.json"))
samples = json.load(open(sys.argv[1] + "/sink/summary.json"))["totals"]
print("ready %d ended %s aborted %s applied-nonzero %s" % (s["readyCount"], s["ended"], s["aborted"],
      {k: v for k, v in s["applied"].items() if v}))
sys.exit(0 if s["ended"] and not s["aborted"] and s["readyCount"] > 90 and not any(s["applied"].values()) else 1)
PY
}
check s1_null_run_paced_every_step_and_ended null_paced_every_step

################################################################################
# V2 + V4: Fallback-1 scripted lock-step, forced late control, ledger replay
################################################################################
cat >"$e/fb1-schedule.json" <<'JSON'
{"steps": {
  "20": {"inject": [{"nodeId": 1, "ctlId": 1, "imsi": 6, "targetCellId": 3, "afterSeq": 20},
                    {"nodeId": 2, "ctlId": 1, "imsi": 6, "targetCellId": 3, "afterSeq": 20},
                    {"nodeId": 3, "ctlId": 1, "imsi": 1, "targetCellId": 2, "afterSeq": 20}]},
  "30": {"inject": [{"nodeId": 2, "ctlId": 2, "imsi": 6, "targetCellId": 3, "afterSeq": 30},
                    {"nodeId": 3, "ctlId": 2, "imsi": 99, "targetCellId": 2, "afterSeq": 30}]},
  "40": {"inject": [{"nodeId": 2, "ctlId": 3, "imsi": 3, "targetCellId": 1, "afterSeq": 40},
                    {"nodeId": 2, "ctlId": 4, "imsi": 3, "targetCellId": 7, "afterSeq": 40}]}
 },
 "late": [{"nodeId": 2, "ctlId": 9, "imsi": 4, "targetCellId": 3}]}
JSON
FB1_N=8   # 7 injected at barriers + 1 after the final barrier
PACERX=(--schedule "$e/fb1-schedule.json")
check s1_run_fb1_scripted_lockstep s1_run fb1 lockstep 0 "--simStartEpochMs=$EPOCH_MS"
v2_ledger() {
    python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$e/runs/fb1/trace/e2-control-ledger.jsonl" \
        "$e/runs/fb1/pacer/pacer-log.jsonl" --expect "$FB1_N" | tee "$e/v2-ledger-check.json"
    return "${PIPESTATUS[0]}"
}
check s1_v2_fb1_ledger_c2_checks v2_ledger
v4_late() {
    python3 -I - "$e/runs/fb1" <<'PY'
import json, sys
rd = sys.argv[1]
rows = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
late = [r for r in rows if r["cause"] == "late"]
acks = json.load(open(rd + "/pacer/pacer-summary.json"))["acks"]
late_acks = [a for a in acks if a["cause"] == "late"]
print("late ledger lines %r; late acks %r" % (late, late_acks))
ok = (len(late) == 1 and late[0]["outcome"] == "refused" and late[0]["ctlId"] == 9 and
      len(late_acks) == 1 and late_acks[0]["outcome"] == "refused" and late_acks[0]["ctlId"] == 9)
sys.exit(0 if ok else 1)
PY
}
check s1_v4_forced_late_control_ledger_late_and_ack_refused_late v4_late
PACERX=(--replay "$e/runs/fb1/trace/e2-control-ledger.jsonl")
check s1_run_replay_of_fb1_ledger s1_run replay lockstep 0 "--simStartEpochMs=$EPOCH_MS"
PACERX=()
v2_replay() {
    python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare fb1="$e/runs/fb1" replay="$e/runs/replay" >"$e/v2-replay-digests.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"], d["runs"])' "$e/v2-replay-digests.json"
    return $rc
}
check s1_v2_replay_digest_equals_fb1 v2_replay

################################################################################
# V3: fault run (i), null sink withholds step K
################################################################################
# v3_fault <rundir> <label>: abort named K by ns-3 and by the pacer, within T_gate + 5 s of
# `ready` K, and no ledger line after K.
v3_fault() {
    python3 -I - "$1" "$K" "$T_GATE_S" <<'PY' | tee "$1/v3-fault-check.json"
import json, os, sys
rd, k, tgate = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
problems = []
ab = json.load(open(rd + "/trace/e2-pacing-abort.json"))
if ab["abortStep"] != k:
    problems.append("e2-pacing-abort.json abortStep %r != %d" % (ab["abortStep"], k))
s = json.load(open(rd + "/pacer/pacer-summary.json"))
if not s["aborted"] or s["abortStep"] != k:
    problems.append("pacer aborted %r abortStep %r" % (s["aborted"], s["abortStep"]))
t_ready = t_abort = None
for l in open(rd + "/pacer/pacer-log.jsonl"):
    m = json.loads(l)
    if m["dir"] == "rx" and m["msg"].get("type") == "ready" and m["msg"].get("seq") == k:
        t_ready = m["t"]
    if m["dir"] == "rx" and m["msg"].get("type") == "abort":
        t_abort = m["t"]
wall = None if t_ready is None or t_abort is None else round(t_abort - t_ready, 3)
if wall is None or wall > tgate + 5:
    problems.append("ready %d -> abort wall %r s, bound %s s" % (k, wall, tgate + 5))
led = rd + "/trace/e2-control-ledger.jsonl"
rows = [json.loads(l) for l in open(led) if l.strip()][1:] if os.path.exists(led) else []
after = [r for r in rows if r["rxSeq"] > k]
if after:
    problems.append("ledger lines after %d: %r" % (k, after))
ns3 = open(rd + "/ns3-exit").read().strip()
print(json.dumps({"abortStep": ab["abortStep"], "reason": ab["reason"], "readyToAbortWallS": wall,
                  "boundS": tgate + 5, "ledgerLines": len(rows), "ledgerLinesAfterK": len(after),
                  "ns3Exit": ns3, "problems": problems, "pass": not problems}, indent=2))
sys.exit(0 if not problems else 1)
PY
    return "${PIPESTATUS[0]}"
}
SINKX=(--withhold-step "$K")
PACERX=(--schedule "$e/fb1-schedule.json")   # controls at 20 and 30 land; the ones at 40 never may
check s1_run_faultsink_withheld_step_aborts_exit5 s1_run faultsink lockstep 5 "--simStartEpochMs=$EPOCH_MS"
SINKX=(); PACERX=()
check s1_v3_faultsink_abort_names_k_in_bound_no_ledger_after_k v3_fault "$e/runs/faultsink"

################################################################################
# V3 with real agents + V4 agent unit test
################################################################################
check s1_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check s1_build_tools_present agents_ensure_build_tools
check s1_sctp_module_loaded agents_sctp_module
check s1_bringup_agents_withholding_step_k gate_bringup agents "enb:1,gnb:2,gnb:3" --env "E2_TEST_WITHHOLD_STEP=$K"
all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == 3) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check s1_every_agent_ready_and_subscribed_before_ns3 all_subscribed
s1_agent_fault_run() {
    local rd="$e/runs/faultagent" pp rc
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" >"$rd/pacer.log" 2>&1 &
    pp=$!
    _wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    ns3_start "$rd/ns3run" "${CLI[@]}" "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 --e2TraceDir="$rd/trace" \
        --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" || { kill "$pp"; return 1; }
    ns3_wait; rc=$NS3_RC
    for _ in $(seq 150); do kill -0 "$pp" 2>/dev/null || break; sleep 0.2; done
    kill "$pp" 2>/dev/null; wait "$pp"
    echo "$rc" >"$rd/ns3-exit"
    echo "faultagent: ns-3 exit $rc (want 5)"
    [ "$rc" = 5 ]
}
check s1_run_faultagent_withheld_step_aborts_exit5 s1_agent_fault_run
check s1_v3_faultagent_abort_names_k_in_bound_no_ledger_after_k v3_fault "$e/runs/faultagent"
agents_stats_all >"$e/faultagent-agent-stats.txt"
v4_unit() {
    local img
    img=$(sed -n 's/^NS3_E2_AGENT_IMAGE=//p' "$e/agent-image.env")
    dk run --rm --entrypoint /usr/local/bin/rc-control-test "$img" /usr/local/share/ns3-e2-agent/rc-control-requests.hex \
        >"$e/rc-control-test.out" 2>"$e/rc-control-test.log"
    local rc=$?
    grep -v '_HEX ' "$e/rc-control-test.out"
    grep -qx "PASS late-refusal-control-failed-to-execute" "$e/rc-control-test.out" || { echo "missing PASS late-refusal-control-failed-to-execute"; rc=1; }
    return $rc
}
check s1_v4_agent_unit_test_late_refusal_fails_control v4_unit
check s1_agents_stopped agents_stop

################################################################################
# K10 verdict facts: drops and minimum slack over the paced runs
################################################################################
k10() {
    python3 -I - "$e" <<'PY' | tee "$e/k10-facts.json"
import glob, json, os, sys
e = sys.argv[1]
ipc_dropped = no_sub = 0
slack = {"T_start": None, "T_gate": None, "T_ctl": None, "W": None}
for log in sorted(glob.glob(e + "/runs/*/trace/e2-pacing-log.jsonl")):
    for l in open(log):
        m = json.loads(l)
        if m.get("type") == "step":
            no_sub = max(no_sub, m.get("droppedNoSub", 0))
        if m.get("type") == "barrier" and m["stepsWaitS"] >= 0:
            key = "T_start" if m["seq"] == -1 else "T_gate"
            s = round(m["timeoutS"] - m["stepsWaitS"], 6)
            slack[key] = s if slack[key] is None else min(slack[key], s)
for tr in glob.glob(e + "/runs/*/trace/e2-ipc-trace-*.jsonl"):
    for l in open(tr):
        if '"type":"sample"' in l:
            ipc_dropped = max(ipc_dropped, json.loads(l).get("ipcDropped", 0))
facts = {"ipcDropped": ipc_dropped, "droppedNoSub": no_sub, "minSlack": slack,
         "note": "T_ctl and W: no trigger step in S1"}
print(json.dumps(facts, indent=2))
sys.exit(0 if ipc_dropped == 0 and no_sub == 0 and slack["T_start"] is not None and slack["T_gate"] is not None else 1)
PY
    return "${PIPESTATUS[0]}"
}
check s1_k10_no_ipc_drop_no_nosub_drop_slack_recorded k10

################################################################################
# hygiene (V6 of P1, kept here as the process check)
################################################################################
no_stray() {
    local bad=0
    pgrep -f "scenario-zero" && bad=1
    pgrep -f ipc-null-sink && bad=1
    pgrep -f "gates/pacer.py" && bad=1
    [ -z "$(dk ps -aq --filter label=ns3e2.agent=1)" ] || { echo "agent container left"; bad=1; }
    ss -Sanp 2>/dev/null | grep -E ':3847[0-9]|:38499' && bad=1
    [ "$bad" = 0 ] && echo "no ns-3, sink, pacer, agent or SCTP/3847x/38499 leftovers"
    return $bad
}
check s1_no_stray_process no_stray
gate_finish

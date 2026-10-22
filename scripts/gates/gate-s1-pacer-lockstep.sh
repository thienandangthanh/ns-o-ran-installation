#!/usr/bin/env bash
# Gate S1 (VM side): lock-step pacing (pacer + barrier) without the RIC, then one
# fault run with real agents. R0 config, null sink as the agent stand-in.
#
#   gate-s1-pacer-lockstep.sh --p1-ns3 SHA --p1-oi SHA [--withhold K] [--withhold-node N]
#
# V6 free-run unchanged by the pacing code: p1 (P1 pins, --p1-ns3/--p1-oi) vs free0
#    (pins.conf pair), both free and without --simStartEpochMs; compare-free-run.py.
# V1 null-control equivalence: free vs null (lock-step, pacer with an empty schedule),
#    both with the pinned --simStartEpochMs; digest-run.py on ledger, IPC samples,
#    traces; the null run passed exactly the barriers -1, 0 .. N-1 (N samples per node).
# V2 Fallback-1: fb1 = lock-step, the pacer injects scripted controls (and one control
#    after the final barrier); check-ledger.py --expect N; every pacer-injected control
#    has exactly one ack equal to its ledger line; the outcomes fixed by construction
#    are asserted, among them the precheck order (a UE mid-handover, targeted at its
#    current cell, is inHandover, not alreadyOnTarget); then replay = the pacer replays
#    fb1's ledger; digest-run.py fb1 vs replay on ledger, IPC samples, traces.
# V4 the forced late controls: after the final barrier (fb1) and mid-run (midlate: a
#    control injected one barrier after its afterSeq) each give one ledger line
#    cause=late and one ack refused/late, and the mid-run one changes nothing (the
#    next control for that UE still sees the old cell); the agent unit test answers a
#    late refusal with RICcontrolFailure control-failed-to-execute.
#    midlate also holds a no-op trigger step: the pacer starts it only after `steps`.
# T_ctl run-out (tctl): a trigger expecting one control that never comes; the pacer
#    aborts at T_ctl (30 s) and ns-3 exits 5 naming the step.
# V3 fault run (i), twice, node N only withholding step K: the null sink (faultsink,
#    with fb1's controls, so the ledger has lines before K) and real agents
#    enb:1,gnb:2,gnb:3 against the RIC (faultagent). ns-3 exits 5; e2-pacing-abort.json
#    and the pacer name step K; the reason names node N only; the other nodes sent
#    step K; barrier entry -> abort and the pacer's `ready` K -> abort both
#    <= T_gate + 5 s; no ledger line at or after K.
# verdict.json facts: nullControlDigestEqualsFreeRun, freeRunEqualsP1, abortStep (real
#    agents) and abortStepNullSink, ipcDropped, droppedNoSub, minSlack{T_start,T_gate,
#    T_ctl,W}, VM load at start and end.
#
# Wall times here are bounds and records, never calibrations: the slack recorded
# under a loaded host is not reused for T_ctl or W.
#
# Builds: the P1 pins in ~/s1-build-p1 (taken over from ~/m4-build when that is at
# them; removed at the end), the pins.conf pair in ~/m4-build so M5-M7 reuse it.
source "$(dirname "$0")/lib.sh"
gate_init s1
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"

P1_NS3=""; P1_OI=""; K=30; WNODE=3
while [ $# -gt 0 ]; do
    case "$1" in
        --p1-ns3) P1_NS3="$2"; shift 2 ;;
        --p1-oi) P1_OI="$2"; shift 2 ;;
        --withhold) K="$2"; shift 2 ;;
        --withhold-node) WNODE="$2"; shift 2 ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
e="$EVIDENCE_DIR"
EPOCH_MS=1767225600000   # 2026-01-01T00:00:00Z: sim time 0 for every pinned run
T_GATE_S=10
T_CTL_S=30
PACER_PORT=38499
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1)
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
record s1_args true "p1 ns-3 $P1_NS3 oi $P1_OI; new ns-3 $NS3_SHA oi $ORAN_INTERFACE_SHA testbed $TESTBED_SHA; withhold step $K on node $WNODE; epoch $EPOCH_MS; cli ${CLI[*]}"
fact vmLoadStart "$(json_str "$(uptime)")"
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

# _pacer_finish <pid>: waits (bounded) for the pacer, which exits once ns-3 ends, and sets
# PACER_RC to its exit status. Call it in the shell that started the pacer, never inside
# $(...): that subshell is not the pacer's parent, and when the pacer is still running at
# the fork, `wait` there cannot see its status (bash 5.2: -1, bash 5.3: 127).
_pacer_finish() {
    for _ in $(seq 150); do kill -0 "$1" 2>/dev/null || break; sleep 0.2; done
    kill "$1" 2>/dev/null; wait "$1"; PACER_RC=$?
}

# The exit-status read must hold when the pacer outlives ns-3 (an abort the pacer sent
# itself): stand-ins in that order, on this VM's bash.
pacer_exit_read_after_ns3_reaped() {
    local fake ns rc
    sh -c 'sleep 1; exit 3' & fake=$!
    sh -c 'sleep 0.2; exit 5' & ns=$!
    wait "$ns"; rc=$?; _pacer_finish "$fake"
    echo "stand-in ns-3 $rc; stand-in pacer exiting after ns-3 is reaped read as $PACER_RC (want 3); bash $BASH_VERSION"
    [ "$rc" = 5 ] && [ "$PACER_RC" = 3 ]
}
check s1_pacer_exit_read_when_pacer_outlives_ns3 pacer_exit_read_after_ns3_reaped

# s1_run <label> <free|lockstep> <want-ns3-exit> [ns-3 args...]: one run with the null sink
# (and, lock-step, the pacer, which must exit 0 after a clean run and 3 after an abort);
# outputs in $e/runs/<label>. SINKX and PACERX hold extra sink and pacer arguments.
SINKX=(); PACERX=()
s1_run() {
    local label="$1" pacing="$2" want="$3" rd="$e/runs/$1" sp pp="" rc prc="" wantp
    shift 3
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    local sargs=(--ports 38471-38473 --out "$rd/sink" --save-lines "${SINKX[@]}")
    local nargs=("${CLI[@]}" "$@" --e2TraceDir="$rd/trace")
    if [ "$pacing" = lockstep ]; then
        sargs+=(--lockstep)
        nargs+=(--e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S")
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" "${PACERX[@]}" >"$rd/pacer.log" 2>&1 &
        pp=$!
        _wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    fi
    python3 -I "$SINK" "${sargs[@]}" >"$rd/sink.log" 2>&1 &
    sp=$!
    _wait_ready "$rd/sink.log" "null sink" || { kill "$sp" $pp; return 1; }
    ns3_start "$rd/ns3run" "${nargs[@]}" || { kill "$sp" $pp; return 1; }
    ns3_wait; rc=$NS3_RC
    [ -z "$pp" ] || { _pacer_finish "$pp"; prc=$PACER_RC; }
    sleep 1; kill -TERM "$sp"; wait "$sp"
    echo "$rc" >"$rd/ns3-exit"
    if [ "$want" = 0 ]; then wantp=0; else wantp=3; fi
    echo "$label ($pacing): ns-3 exit $rc (want $want)${pp:+; pacer exit $prc (want $wantp)}; sink $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["totals"])' "$rd/sink/summary.json" 2>/dev/null)"
    [ "$rc" = "$want" ] && { [ -z "$pp" ] || [ "$prc" = "$wantp" ]; }
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
fact freeRunEqualsP1 "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["all_pass"]))' "$e/v6-compare.json" 2>/dev/null || echo null)"
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
fact nullControlDigestEqualsFreeRun "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["all_equal"]))' "$e/v1-digests.json" 2>/dev/null || echo null)"
null_paced_every_step() {
    python3 -I - "$e/runs/null" <<'PY'
import json, sys
rd = sys.argv[1]
nodes = json.load(open(rd + "/sink/summary.json"))["nodes"]
counts = {n["sample"] for n in nodes.values()}
ready = []
for l in open(rd + "/pacer/pacer-log.jsonl"):
    m = json.loads(l)
    if m["dir"] == "rx" and m["msg"].get("type") == "ready":
        ready.append(m["msg"]["seq"])
s = json.load(open(rd + "/pacer/pacer-summary.json"))
n = counts.pop() if len(counts) == 1 else None
want = [-1] + list(range(n)) if n else None
print("samples per node %r; %d ready seqs, first %r last %r; ended %s aborted %s; applied-nonzero %r" % (
    sorted({x["sample"] for x in nodes.values()}), len(ready), ready[:2], ready[-1:], s["ended"], s["aborted"],
    {k: v for k, v in s["applied"].items() if v}))
sys.exit(0 if ready == want and s["ended"] and not s["aborted"] and not any(s["applied"].values()) else 1)
PY
}
check s1_null_run_passed_barriers_exactly_minus1_to_last_seq null_paced_every_step

################################################################################
# V2 + V4: Fallback-1 scripted lock-step, forced late control, ledger replay
################################################################################
# Step 20: imsi 6 is handed over by node 1's control (applied first: same imsi, lower
# nodeId), so node 2's control for imsi 6 -> its current cell 2 finds it mid-handover:
# the precheck order gives inHandover (already-on-target first would give alreadyOnTarget).
cat >"$e/fb1-schedule.json" <<'JSON'
{"steps": {
  "20": {"inject": [{"nodeId": 1, "ctlId": 1, "imsi": 6, "targetCellId": 3, "afterSeq": 20},
                    {"nodeId": 2, "ctlId": 1, "imsi": 6, "targetCellId": 2, "afterSeq": 20},
                    {"nodeId": 3, "ctlId": 1, "imsi": 1, "targetCellId": 2, "afterSeq": 20}]},
  "30": {"inject": [{"nodeId": 2, "ctlId": 2, "imsi": 6, "targetCellId": 3, "afterSeq": 30},
                    {"nodeId": 3, "ctlId": 2, "imsi": 99, "targetCellId": 2, "afterSeq": 30}]},
  "40": {"inject": [{"nodeId": 2, "ctlId": 3, "imsi": 3, "targetCellId": 1, "afterSeq": 40},
                    {"nodeId": 2, "ctlId": 4, "imsi": 3, "targetCellId": 7, "afterSeq": 40}]}
 },
 "late": [{"nodeId": 2, "ctlId": 9, "imsi": 4, "targetCellId": 3}]}
JSON
# (nodeId, ctlId) -> (outcome, cause) for the controls whose answer follows from the
# schedule alone; the others depend on the radio state and are only counted.
cat >"$e/fb1-expected.json" <<'JSON'
{"1,1": ["applied", ""], "2,1": ["refused", "inHandover"], "3,2": ["refused", "unknownImsi"],
 "2,3": ["refused", "unknownTarget"], "2,4": ["refused", "unknownTarget"], "2,9": ["refused", "late"]}
JSON
FB1_N=8   # 7 injected at barriers + 1 after the final barrier
# ledger_vs_acks <rundir> <expected.json|-> [after]: one ack per ledger line (pacer-injected
# controls), equal outcome and cause; the expected table holds; with `after`, prints it.
ledger_vs_acks() {
    python3 -I - "$1" "$2" <<'PY'
import json, sys
rd, exp = sys.argv[1], sys.argv[2]
rows = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
acks = json.load(open(rd + "/pacer/pacer-summary.json"))["acks"]
problems = []
led = {(r["viaNodeId"], r["ctlId"]): r for r in rows}
seen = {}
for a in acks:
    k = (a["nodeId"], a["ctlId"])
    seen[k] = seen.get(k, 0) + 1
    r = led.get(k)
    if r is None or (a["outcome"], a["cause"]) != (r["outcome"], r["cause"]):
        problems.append("ack %r does not match ledger %r" % (a, r))
for k in led:
    if seen.get(k) != 1:
        problems.append("ledger line %r has %r acks" % (k, seen.get(k)))
if exp != "-":
    for k, (o, c) in json.load(open(exp)).items():
        r = led.get(tuple(int(x) for x in k.split(",")))
        got = None if r is None else (r["outcome"], r["cause"])
        if got != (o, c):
            problems.append("control %s: %r, expected %r" % (k, got, (o, c)))
for r in rows:
    print("seq %d node %d ctl %d imsi %d %d->%d %s %s" % (r["rxSeq"], r["viaNodeId"], r["ctlId"], r["imsi"],
          r["sourceCell"], r["targetCell"], r["outcome"], r["cause"]))
print("problems: %r" % problems)
sys.exit(0 if not problems else 1)
PY
}
PACERX=(--schedule "$e/fb1-schedule.json")
check s1_run_fb1_scripted_lockstep s1_run fb1 lockstep 0 "--simStartEpochMs=$EPOCH_MS"
v2_ledger() {
    python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$e/runs/fb1/trace/e2-control-ledger.jsonl" \
        "$e/runs/fb1/pacer/pacer-log.jsonl" --expect "$FB1_N" | tee "$e/v2-ledger-check.json"
    return "${PIPESTATUS[0]}"
}
check s1_v2_fb1_ledger_c2_checks v2_ledger
check s1_v2_fb1_one_ack_per_line_and_expected_outcomes_incl_precheck_order ledger_vs_acks "$e/runs/fb1" "$e/fb1-expected.json"
PACERX=(--replay "$e/runs/fb1/trace/e2-control-ledger.jsonl")
check s1_run_replay_of_fb1_ledger s1_run replay lockstep 0 "--simStartEpochMs=$EPOCH_MS"
v2_replay() {
    python3 -I "$HARNESS_DIR/scripts/gates/digest-run.py" --compare fb1="$e/runs/fb1" replay="$e/runs/replay" >"$e/v2-replay-digests.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"], d["runs"])' "$e/v2-replay-digests.json"
    return $rc
}
check s1_v2_replay_digest_equals_fb1 v2_replay

# midlate: node 1's control for imsi 6 -> 3 reaches barrier 20 stamped afterSeq 19, so it
# missed its barrier: refused late and not applied, hence the same control at 21 (on time)
# finds imsi 6 still on cell 2 and is applied (had the late one been applied at 20, the UE
# would be mid-handover at 21). Step 15 is a no-op trigger (`true`, no control expected).
cat >"$e/midlate-schedule.json" <<'JSON'
{"steps": {
  "15": {"trigger": {"cmd": ["true"]}, "expect": 0},
  "20": {"inject": [{"nodeId": 1, "ctlId": 1, "imsi": 6, "targetCellId": 3, "afterSeq": 19}]},
  "21": {"inject": [{"nodeId": 1, "ctlId": 2, "imsi": 6, "targetCellId": 3, "afterSeq": 21}]}
 },
 "late": []}
JSON
cat >"$e/midlate-expected.json" <<'JSON'
{"1,1": ["refused", "late"], "1,2": ["applied", ""]}
JSON
PACERX=(--schedule "$e/midlate-schedule.json")
check s1_run_midlate_lockstep s1_run midlate lockstep 0 "--simStartEpochMs=$EPOCH_MS"
PACERX=()
v4_midlate() {
    python3 -I "$HARNESS_DIR/scripts/gates/check-ledger.py" "$e/runs/midlate/trace/e2-control-ledger.jsonl" \
        "$e/runs/midlate/pacer/pacer-log.jsonl" --expect 2 || return 1
    ledger_vs_acks "$e/runs/midlate" "$e/midlate-expected.json" || return 1
    python3 -I - "$e/runs/midlate" <<'PY'
import json, sys
rd = sys.argv[1]
rows = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
late = next(r for r in rows if r["ctlId"] == 1)
ontime = next(r for r in rows if r["ctlId"] == 2)
# the late line is at barrier 20 (not the stop) and the next control still sees cell 2
ok = late["rxSeq"] == 20 and late["afterSeq"] == 19 and ontime["rxSeq"] == 21 and ontime["sourceCell"] == 2
print("late %r; on time %r" % (late, ontime))
sys.exit(0 if ok else 1)
PY
}
check s1_v4_midrun_late_control_refused_late_and_not_applied v4_midlate
v4_late_final() {
    ledger_vs_acks "$e/runs/fb1" - | grep -E " late$|problems"
    python3 -I -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][1:]
late = [r for r in rows if r["cause"] == "late"]
sys.exit(0 if len(late) == 1 and late[0]["ctlId"] == 9 and late[0]["outcome"] == "refused" else 1)' "$e/runs/fb1/trace/e2-control-ledger.jsonl"
}
check s1_v4_control_after_final_barrier_ledger_late_and_ack_refused_late v4_late_final
trigger_after_steps() {
    python3 -I - "$e/runs/midlate" <<'PY'
import json, sys
order = []
for l in open(sys.argv[1] + "/pacer/pacer-log.jsonl"):
    m = json.loads(l)
    if m["msg"].get("seq") == 15 and m["msg"].get("type") in ("ready", "steps", "trigger", "go"):
        order.append(m["dir"] + ":" + m["msg"]["type"])
print("step 15 order: %r" % order)
sys.exit(0 if order == ["rx:ready", "rx:steps", "pacer:trigger", "tx:go"] else 1)
PY
}
check s1_noop_trigger_starts_only_after_steps trigger_after_steps

# tctl: a trigger that should bring one control, none comes: the pacer aborts at T_ctl.
cat >"$e/tctl-schedule.json" <<'JSON'
{"steps": {"15": {"trigger": {"cmd": ["true"]}, "expect": 1}}, "late": []}
JSON
PACERX=(--schedule "$e/tctl-schedule.json")
check s1_run_tctl_runout_aborts_exit5 s1_run tctl lockstep 5 "--simStartEpochMs=$EPOCH_MS"
PACERX=()
tctl_named() {
    python3 -I - "$e/runs/tctl" "$T_CTL_S" <<'PY'
import json, sys
rd, tctl = sys.argv[1], float(sys.argv[2])
ab = json.load(open(rd + "/trace/e2-pacing-abort.json"))
s = json.load(open(rd + "/pacer/pacer-summary.json"))
rec = s["steps"].get("15", {})
print("abort %r; pacer reason %r; L %r" % (ab, s.get("pacerAbortReason"), rec.get("L")))
ok = (ab["abortStep"] == 15 and "pacer:" in ab["reason"] and "step 15" in s.get("pacerAbortReason", "")
      and rec.get("controls") == 0 and ab["blockedToAbortWallS"] >= tctl)
sys.exit(0 if ok else 1)
PY
}
check s1_tctl_runout_abort_names_step_15 tctl_named

################################################################################
# V3: fault run (i), node WNODE alone withholds step K
################################################################################
# v3_fault <rundir> <min ledger lines before K>: abort named K by ns-3 and by the pacer,
# reason naming only WNODE, step K from the other nodes, within T_gate + 5 s of the
# barrier entry and of the pacer's `ready` K; no ledger line at or after K.
v3_fault() {
    python3 -I - "$1" "$K" "$T_GATE_S" "$WNODE" "$2" <<'PY' | tee "$1/v3-fault-check.json"
import json, os, sys
rd, k, tgate, wnode, min_lines = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
problems = []
ab = json.load(open(rd + "/trace/e2-pacing-abort.json"))
if ab["abortStep"] != k:
    problems.append("e2-pacing-abort.json abortStep %r != %d" % (ab["abortStep"], k))
if not ab["reason"].startswith("no step %d from node(s) %d within" % (k, wnode)):
    problems.append("abort reason %r does not name node %d alone" % (ab["reason"], wnode))
if not 0 <= ab["blockedToAbortWallS"] <= tgate + 5:
    problems.append("barrier entry -> abort %r s, bound %s s" % (ab["blockedToAbortWallS"], tgate + 5))
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
stepped = set()
nodes = set()
for l in open(rd + "/trace/e2-pacing-log.jsonl"):
    m = json.loads(l)
    if m.get("type") == "step":
        nodes.add(m["nodeId"])
        if m["seq"] == k:
            stepped.add(m["nodeId"])
if stepped != nodes - {wnode} or wnode not in nodes:
    problems.append("step %d came from %r of nodes %r (want all but %d)" % (k, sorted(stepped), sorted(nodes), wnode))
led = rd + "/trace/e2-control-ledger.jsonl"
rows = [json.loads(l) for l in open(led) if l.strip()][1:] if os.path.exists(led) else []
after = [r for r in rows if r["rxSeq"] >= k]
if after:
    problems.append("ledger lines at or after %d: %r" % (k, after))
if len(rows) - len(after) < min_lines:
    problems.append("%d ledger lines before %d, want >= %d" % (len(rows) - len(after), k, min_lines))
print(json.dumps({"abortStep": ab["abortStep"], "reason": ab["reason"], "blockedToAbortWallS": ab["blockedToAbortWallS"],
                  "readyToAbortWallS": wall, "boundS": tgate + 5, "stepKFrom": sorted(stepped), "nodes": sorted(nodes),
                  "ledgerLines": len(rows), "ledgerLinesAtOrAfterK": len(after),
                  "ns3Exit": open(rd + "/ns3-exit").read().strip(), "problems": problems, "pass": not problems}, indent=2))
sys.exit(0 if not problems else 1)
PY
    return "${PIPESTATUS[0]}"
}
SINKX=(--withhold-step "$K" --withhold-node "$WNODE")
PACERX=(--schedule "$e/fb1-schedule.json")   # controls at 20 land before K; those at 40 never may
check s1_run_faultsink_withheld_step_aborts_exit5 s1_run faultsink lockstep 5 "--simStartEpochMs=$EPOCH_MS"
SINKX=(); PACERX=()
check s1_v3_faultsink_abort_names_k_and_node_in_bound_no_ledger_from_k v3_fault "$e/runs/faultsink" 3
fact abortStepNullSink "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["abortStep"])' "$e/runs/faultsink/trace/e2-pacing-abort.json" 2>/dev/null || echo null)"

################################################################################
# V3 with real agents + V4 agent unit test
################################################################################
check s1_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check s1_build_tools_present agents_ensure_build_tools
check s1_sctp_module_loaded agents_sctp_module
check s1_bringup_agents_node_withholding_step_k gate_bringup agents "enb:1,gnb:2,gnb:3" \
    --env "E2_TEST_WITHHOLD_STEP=$K" --env "E2_TEST_WITHHOLD_NODE=$WNODE"
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
    local rd="$e/runs/faultagent" pp rc prc
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" >"$rd/pacer.log" 2>&1 &
    pp=$!
    _wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    ns3_start "$rd/ns3run" "${CLI[@]}" "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 --e2TraceDir="$rd/trace" \
        --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" || { kill "$pp"; return 1; }
    ns3_wait; rc=$NS3_RC
    _pacer_finish "$pp"; prc=$PACER_RC
    echo "$rc" >"$rd/ns3-exit"
    echo "faultagent: ns-3 exit $rc (want 5); pacer exit $prc (want 3)"
    [ "$rc" = 5 ] && [ "$prc" = 3 ]
}
check s1_run_faultagent_withheld_step_aborts_exit5 s1_agent_fault_run
check s1_v3_faultagent_abort_names_k_and_node_in_bound_no_ledger_from_k v3_fault "$e/runs/faultagent" 0
fact abortStep "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["abortStep"])' "$e/runs/faultagent/trace/e2-pacing-abort.json" 2>/dev/null || echo null)"
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
# verdict facts: drops and minimum slack over the paced runs
################################################################################
k10() {
    python3 -I - "$e" <<'PY'
import glob, json, sys
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
         "minSlackNote": "T_ctl and W: no control-bearing trigger step in S1; wall times recorded under the user's CPU hold, not reused for T_ctl or W"}
json.dump(facts, open(e + "/k10-facts.json", "w"), indent=2)
print(json.dumps(facts, indent=2))
sys.exit(0 if ipc_dropped == 0 and no_sub == 0 and slack["T_start"] is not None and slack["T_gate"] is not None else 1)
PY
}
check s1_no_ipc_drop_no_nosub_drop_slack_recorded k10
for k in ipcDropped droppedNoSub minSlack minSlackNote; do
    fact "$k" "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$e/k10-facts.json" "$k" 2>/dev/null || echo null)"
done

################################################################################
# hygiene
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
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

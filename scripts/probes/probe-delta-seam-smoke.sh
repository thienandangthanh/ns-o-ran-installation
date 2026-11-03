#!/usr/bin/env bash
# Probe (VM side, M10 P02 seam smoke): the δ actuation seam (ns3::E2ControlHub::ActuationDelay, scenario-zero
# --actuationDelayMs) on the M4 build in ~/m4-build at the pinned forks (clean trees, emitter SHAs = pins.conf). No RIC: the null sink stands in for
# the agents and the pacer injects S1's Fallback-1 controls (gate-s1-pacer-lockstep.sh V2), so the outcomes are fixed
# by construction. Runs, all lock-step with the R0 configuration:
#   d0       δ = 0      check-ledger.py (the d = 0 checks), one controlAck per ledger line
#   d150     δ = 150    check-ledger.py --delta-ms 150 (one apply event per batch, δ not a multiple of T)
#   d500     δ = 500    check-ledger.py --delta-ms 500 (batches queued to barrier k + 5)
#   d500stop δ = 500, one control injected at step 97 of 100: still pending at the stop, so it gets exactly one
#            refused/late answer whose rxSimTimeNs is barrier 97's time
#   d100tie  δ = 100 (= T, queued path), the tie rule at one barrier: a batch received at barrier 20 is due at 21;
#            barrier 21 also receives a forced-late control (afterSeq 20) and a new batch (due at 22). In the ledger
#            the due batch is answered at t21 before the late refusal, and the new batch at t22
#   d150stop δ = 150 (event path), one control injected at step 99 of 100: its event (t99 + 150 ms) is past the
#            stop, so it is cancelled and answered refused/late once, at a time before t99 + 150 ms
# plus the outcome table per δ, recorded and not asserted: δ moves the apply time into a different radio state
# (the 2026-11-03 smoke: at δ = 500 the step-30 control finds IMSI 6 in LTE fallback instead of already on target).
# The build's provenance (the uncommitted diff of the seam) is recorded.
source "$(dirname "$0")/../gates/lib.sh"
gate_init dseam
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"
source "$HARNESS_DIR/scripts/gates/paced-lib.sh"

e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
T_GATE_S=$(python3 -I "$CFG" get deadlines.T_gate_s)
T_CTL_S=5
PACER_PORT=38499
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1)
SINKX=()
LEDGER_CHECK="$HARNESS_DIR/scripts/gates/check-ledger.py"

check dseam_ns3_binary_located agents_ns3_locate
provenance() {   # the pinned forks, clean, and the hub source carries the seam
    local src="$M4_WORKDIR/ns-3" oi="$M4_WORKDIR/ns-3/contrib/oran-interface"
    { echo "ns-3 $(git -C "$src" rev-parse HEAD) (pin $NS3_SHA)"; echo "oran-interface $(git -C "$oi" rev-parse HEAD) (pin $ORAN_INTERFACE_SHA)"
      git -C "$src" status --porcelain --untracked-files=no; git -C "$oi" status --porcelain --untracked-files=no; } >"$e/build-diff.txt"
    cat "$e/build-diff.txt"
    [ "$(wc -l <"$e/build-diff.txt")" = 2 ] && ns3_build_at_pins && grep -q "ActuationDelay" "$oi/model/e2-control-hub.cc"
}
check dseam_build_at_pins_clean_and_carries_the_seam provenance

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
cat >"$e/stop-schedule.json" <<'JSON'
{"steps": {"97": {"inject": [{"nodeId": 2, "ctlId": 1, "imsi": 2, "targetCellId": 3, "afterSeq": 97}]}}}
JSON
cat >"$e/stop99-schedule.json" <<'JSON'
{"steps": {"99": {"inject": [{"nodeId": 2, "ctlId": 1, "imsi": 2, "targetCellId": 3, "afterSeq": 99}]}}}
JSON
cat >"$e/tie-schedule.json" <<'JSON'
{"steps": {
  "20": {"inject": [{"nodeId": 2, "ctlId": 1, "imsi": 6, "targetCellId": 2, "afterSeq": 20}]},
  "21": {"inject": [{"nodeId": 2, "ctlId": 2, "imsi": 4, "targetCellId": 3, "afterSeq": 20},
                    {"nodeId": 3, "ctlId": 1, "imsi": 1, "targetCellId": 2, "afterSeq": 21}]}
 }}
JSON

acks_match() {   # every ledger line has exactly one controlAck at the pacer with the same outcome and cause
    python3 -I - "$RUNS/$1" <<'PY'
import json, sys
rd = sys.argv[1]
led = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
acks = [json.loads(l)["msg"] for l in open(rd + "/pacer/pacer-log.jsonl")]
acks = [m for m in acks if m.get("type") == "controlAck"]
lk = sorted((l["viaNodeId"], l["ctlId"], l["outcome"], l["cause"], l["applySimTimeNs"]) for l in led)
ak = sorted((a["nodeId"], a["ctlId"], a["outcome"], a["cause"], a["applySimTimeNs"]) for a in acks)
print("ledger %d lines, %d acks, outcomes %s" % (len(lk), len(ak), sorted({(x[2], x[3]) for x in lk})))
sys.exit(0 if lk == ak and lk else 1)
PY
}
for d in 0 150 500; do
    PACERX=(--schedule "$e/fb1-schedule.json")
    check "dseam_run_d$d" paced_null_run "d$d" lockstep 0 "--simStartEpochMs=$EPOCH_MS" "--actuationDelayMs=$d"
    check "dseam_d${d}_ledger_checks" bash -o pipefail -c "python3 -I '$LEDGER_CHECK' '$RUNS/d$d/trace/e2-control-ledger.jsonl' \
        '$RUNS/d$d/pacer/pacer-log.jsonl' --expect 8 --delta-ms $d | tee '$e/d$d-ledger-check.json'"
    check "dseam_d${d}_one_ack_per_ledger_line" acks_match "d$d"
done
same_outcomes() {
    python3 -I - "$RUNS" <<'PY'
import json, sys
def oc(d):
    led = [json.loads(l) for l in open("%s/%s/trace/e2-control-ledger.jsonl" % (sys.argv[1], d)) if l.strip()][1:]
    return sorted((l["viaNodeId"], l["ctlId"], l["imsi"], l["outcome"], l["cause"], l["sourceCell"]) for l in led)
o = {d: oc(d) for d in ("d0", "d150", "d500")}
for d, v in o.items():
    print(d, v)
print("same at every delta:", o["d0"] == o["d150"] == o["d500"])
PY
}
record dseam_outcomes_per_delta_informational true "$(same_outcomes 2>&1 | tail -n 1)"
PACERX=(--schedule "$e/stop-schedule.json")
check dseam_run_d500stop paced_null_run d500stop lockstep 0 "--simStartEpochMs=$EPOCH_MS" --actuationDelayMs=500
check dseam_d500stop_ledger_checks bash -o pipefail -c "python3 -I '$LEDGER_CHECK' '$RUNS/d500stop/trace/e2-control-ledger.jsonl' \
    '$RUNS/d500stop/pacer/pacer-log.jsonl' --expect 1 --delta-ms 500 | tee '$e/d500stop-ledger-check.json'"
check dseam_d0_emitters_at_pins ns3_emitters_at_pins "$RUNS/d0/trace"
pending_at_stop() {   # run, rxSeq, δ ms: exactly one line, refused late, rx at barrier rxSeq, answered before rx + δ
    python3 -I - "$RUNS/$1" "$2" "$3" <<'PY'
import json, sys
rd, k, d = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
led = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
ready = {m["seq"]: m["simTimeNs"] for m in (json.loads(l)["msg"] for l in open(rd + "/pacer/pacer-log.jsonl")) if m.get("type") == "ready"}
acks = [m for m in (json.loads(l)["msg"] for l in open(rd + "/pacer/pacer-log.jsonl")) if m.get("type") == "controlAck"]
print("ledger", led, "acks", acks)
ok = (len(led) == 1 and led[0]["outcome"] == "refused" and led[0]["cause"] == "late" and led[0]["rxSeq"] == k
      and led[0]["rxSimTimeNs"] == ready.get(k) and led[0]["rxSimTimeNs"] < led[0]["applySimTimeNs"] < led[0]["rxSimTimeNs"] + d * 1_000_000
      and len(acks) == 1)
sys.exit(0 if ok else 1)
PY
}
check dseam_d500stop_pending_control_gets_one_late_failure pending_at_stop d500stop 97 500
check dseam_d500stop_one_ack acks_match d500stop

PACERX=(--schedule "$e/stop99-schedule.json")
check dseam_run_d150stop paced_null_run d150stop lockstep 0 "--simStartEpochMs=$EPOCH_MS" --actuationDelayMs=150
check dseam_d150stop_ledger_checks bash -o pipefail -c "python3 -I '$LEDGER_CHECK' '$RUNS/d150stop/trace/e2-control-ledger.jsonl' \
    '$RUNS/d150stop/pacer/pacer-log.jsonl' --expect 1 --delta-ms 150 | tee '$e/d150stop-ledger-check.json'"
check dseam_d150stop_scheduled_event_cancelled_one_late_failure pending_at_stop d150stop 99 150
check dseam_d150stop_one_ack acks_match d150stop

PACERX=(--schedule "$e/tie-schedule.json")
check dseam_run_d100tie paced_null_run d100tie lockstep 0 "--simStartEpochMs=$EPOCH_MS" --actuationDelayMs=100
check dseam_d100tie_ledger_checks bash -o pipefail -c "python3 -I '$LEDGER_CHECK' '$RUNS/d100tie/trace/e2-control-ledger.jsonl' \
    '$RUNS/d100tie/pacer/pacer-log.jsonl' --expect 3 --delta-ms 100 | tee '$e/d100tie-ledger-check.json'"
tie_order() {   # ledger order and times at barrier 21: the due batch, then the late refusal; the new batch at 22
    python3 -I - "$RUNS/d100tie" <<'PY'
import json, sys
rd = sys.argv[1]
led = [json.loads(l) for l in open(rd + "/trace/e2-control-ledger.jsonl") if l.strip()][1:]
ready = {m["seq"]: m["simTimeNs"] for m in (json.loads(l)["msg"] for l in open(rd + "/pacer/pacer-log.jsonl")) if m.get("type") == "ready"}
got = [((l["viaNodeId"], l["ctlId"]), l["rxSeq"], l["cause"] == "late", l["applySimTimeNs"]) for l in led]
want = [((2, 1), 20, False, ready.get(21)), ((2, 2), 21, True, ready.get(21)), ((3, 1), 21, False, ready.get(22))]
print("got ", got)
print("want", want)
sys.exit(0 if got == want and None not in (ready.get(21), ready.get(22)) else 1)
PY
}
check dseam_d100tie_due_batch_before_late_refusal_new_batch_next_barrier tie_order
check dseam_d100tie_one_ack_per_ledger_line acks_match d100tie
gate_finish

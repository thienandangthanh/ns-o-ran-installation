#!/usr/bin/env bash
# Probe (VM side, M10 P04 step 2b): cross-check the frozen checkpoint-1 UE identity map (plan R-8) against ns-3's own
# RRC log, an independent source from the PDCP trace the map was extracted from.
#
#   vm-exec.sh probes/probe-identity-map-nslog.sh -- <identity map, path relative to the harness>
#
# One RIC-free lock-step run (null sink, no controls) with the R3' radio configuration of gate-r3p-ts-predictor.sh
# (enb:1 + 2 gNBs, NoAuto, simTime 10, the gated outage threshold, RngRun 1) at the pinned forks, with
# NS_LOG=LteEnbRrc=level_info. UeManager::SwitchToState logs "ENB Switch to state IMSI i RNTI r" per eNB node. The
# LTE eNB (master node) is the one node whose UE contexts cover every IMSI of the map; on it every IMSI must have
# exactly one RNTI, equal to the map's mEnbUeX2apId, IMSI for IMSI. The same run's PDCP trace must also give the same
# map through identity-map-extract.py (same extractor, fresh run at the pins).
source "$(dirname "$0")/../gates/lib.sh"
gate_init idmap
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"
source "$HARNESS_DIR/scripts/gates/paced-lib.sh"

MAP="$HARNESS_DIR/${1:?usage: probe-identity-map-nslog.sh <identity map json, relative to the harness>}"
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
T_GATE_S=$(python3 -I "$CFG" get deadlines.T_gate_s)
THRESH=$(python3 -I "$CFG" get scenario.outageThreshold_dB)
T_CTL_S=5
PACER_PORT=38499
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
# shellcheck disable=SC2034  # CLI, SINKX and PACERX are read by paced-lib.sh
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 "--outageThreshold=$THRESH" --RngRun=1)
SINKX=(); PACERX=()

check idmap_map_present test -s "$MAP"
check idmap_ns3_binary_located agents_ns3_locate
check idmap_e2_ports_reserved agents_reserve_ports
check idmap_build_at_pins ns3_build_at_pins
export NS_LOG="LteEnbRrc=level_info|prefix_node|prefix_time"
check idmap_run_nslog paced_null_run nslog lockstep 0
unset NS_LOG
check idmap_emitters_at_pins ns3_emitters_at_pins "$RUNS/nslog/trace"

nslog_agrees() {
    python3 -I - "$RUNS/nslog/ns3run/stderr.txt" "$MAP" "$e/identity-map-nslog.json" <<'PY'
import json, re, sys
log, mp, out = sys.argv[1:4]
want = {int(i): v["mEnbUeX2apId"] for i, v in json.load(open(mp))["ues"].items()}
pat = re.compile(r"^\+?\S+s (\d+) .*ENB Switch to state IMSI (\d+) RNTI (\d+) ")
per_node = {}
for line in open(log, errors="replace"):
    m = pat.match(line)
    if m and int(m.group(2)) > 0:
        per_node.setdefault(int(m.group(1)), {}).setdefault(int(m.group(2)), set()).add(int(m.group(3)))
mn = [n for n, u in per_node.items() if set(want) <= set(u)]
res = {"nodes": {str(n): {str(i): sorted(r) for i, r in sorted(u.items())} for n, u in sorted(per_node.items())},
       "masterNode": mn, "map": {str(i): r for i, r in sorted(want.items())}}
problems = []
if len(mn) != 1:
    problems.append("want exactly one node covering every IMSI of the map, got %r" % mn)
else:
    got = per_node[mn[0]]
    for i, r in sorted(want.items()):
        if got.get(i) != {r}:
            problems.append("IMSI %d: RRC log RNTIs %s, map %d" % (i, sorted(got.get(i, ())), r))
res["problems"], res["pass"] = problems, not problems
json.dump(res, open(out, "w"), indent=1, sort_keys=True)
print(json.dumps({"masterNode": mn, "imsis": len(want), "pass": not problems}))
for q in problems:
    print("problem: " + q)
sys.exit(0 if not problems else 1)
PY
}
check idmap_rrc_log_agrees_with_the_map_imsi_for_imsi nslog_agrees

pdcp_agrees() {
    python3 -I "$HARNESS_DIR/scripts/gates/identity-map-extract.py" "$RUNS/nslog/ns3run/DlE2PdcpStatsLte.txt" \
        --source-label "probe-nslog@$HARNESS_SHA" >"$e/identity-map-pdcp-rerun.json" || return 1
    python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1]))["ues"]; b=json.load(open(sys.argv[2]))["ues"]; print("pdcp re-run map equal:", a == b); sys.exit(0 if a == b else 1)' \
        "$e/identity-map-pdcp-rerun.json" "$MAP"
}
check idmap_pdcp_rerun_at_pins_equals_the_map pdcp_agrees
gate_finish

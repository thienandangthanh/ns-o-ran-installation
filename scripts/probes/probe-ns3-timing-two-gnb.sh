#!/usr/bin/env bash
# Probe (VM side, pre-M8 pacing gate): wall seconds per simulated second of scenario-zero with
# --nMmWaveEnbNodes=2 (eNB 1 + gNB 2..3), the smallest config with >= 2 gNBs, measured exactly like M4
# (scripts/measure-ns3-timing.sh: null sink, simTime 10, period 0.1, >= 3 repeats, monotonic clock).
# Uses the M4 build on f7-rerun-green; no rebuild, no snapshot, no fork push.
source "$(dirname "$0")/../gates/lib.sh"
gate_init ns3-timing-two-gnb
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"

check timing2_ns3_binary_located agents_ns3_locate
idle() { cat /proc/loadavg; [ -z "$(dk ps -q --filter label=ns3e2.agent=1)" ] && echo "no agent container running"; }
check timing2_no_agents_running idle
check timing2_measured env TIMING_CONFIGS=two bash "$HARNESS_DIR/scripts/measure-ns3-timing.sh" "$NS3_BIN" \
    "$EVIDENCE_DIR/timing" --repeats 3 --simtime 10
check timing2_hygiene agents_hygiene
gate_finish

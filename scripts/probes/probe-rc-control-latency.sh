#!/usr/bin/env bash
# Probe (VM side, pre-M8 pacing gate): wall latency from a gRPC call to the rc xApp (:7777) until the
# RICcontrolRequest reaches the target agent's container on docker0, with the default 5-node agent set and
# ns-3 default config running free (realistic CPU load).
#
# From f7-rerun-green: install rc with NIST's install_xapp_ric_control.sh (pinned by NIST's commit_hashes),
# fetch grpcurl (pinned release, sha256-checked), capture docker0, bring up the agents, start ns-3, then send
# RC_CALLS controls round-robin over the 5 nodes, RC_GAP_S apart. The agents of today only log an inbound
# RICcontrolRequest and never answer it, so rc only logs its 2 s ack timeout. Latency = first RICcontrol
# initiatingMessage frame to that node's container IP after the call's start (VM clock for both). rc's pod
# RestartCount is recorded before and after. No snapshot, no fork push; the caller reverts the VM.
#
# Knobs: RC_CALLS (30), RC_GAP_S (2), RC_SIMTIME (12).
NS3_TIMEOUT_S="${NS3_TIMEOUT_S:-3600}"
source "$(dirname "$0")/../gates/lib.sh"
gate_init rc-control-latency
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"

NODES="enb:1,gnb:2,gnb:3,gnb:4,gnb:5"
NNODES=5
RC_CALLS="${RC_CALLS:-30}"
RC_GAP_S="${RC_GAP_S:-2}"
RC_SIMTIME="${RC_SIMTIME:-12}"
GRPCURL_VER=1.9.1
e="$EVIDENCE_DIR"
RUN="$e/ns3run"
mkdir -p "$RUN" "$e/calls"

check rc_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check rc_build_tools_present agents_ensure_build_tools
check rc_sctp_module_loaded agents_sctp_module
check rc_ns3_binary_located agents_ns3_locate

install_rc() {
    _agents_prepare_env
    nist_run 3600 "$RIC_DIR/additional_scripts/install_xapp_ric_control.sh" >"$e/install-rc.log" 2>&1 || { tail -n 30 "$e/install-rc.log"; return 1; }
    git -C "$RIC_DIR/xApps/rc" rev-parse HEAD | tee "$e/rc-sha.txt"
    local deadline=$(($(date +%s) + 300)) name ready
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if read -r name ready _ < <(pod_info ricxapp xapp-rc-) && [ "$ready" = true ]; then pod_info ricxapp xapp-rc- | tee "$e/rc-pod-before.txt"; return 0; fi
        sleep 5
    done
    kc -n ricxapp get pods -o wide; return 1
}
check rc_xapp_installed_and_ready install_rc

grpcurl_fetch() {
    local d="$HOME/grpcurl-$GRPCURL_VER" base="https://github.com/fullstorydev/grpcurl/releases/download/v$GRPCURL_VER"
    local tgz="grpcurl_${GRPCURL_VER}_linux_x86_64.tar.gz"
    mkdir -p "$d" && cd "$d" || return 1
    curl -fsSLO "$base/$tgz" && curl -fsSLO "$base/grpcurl_${GRPCURL_VER}_checksums.txt" &&
        grep " $tgz\$" "grpcurl_${GRPCURL_VER}_checksums.txt" | sha256sum -c - && tar -xzf "$tgz" grpcurl &&
        GRPCURL="$d/grpcurl" && "$GRPCURL" -version
    local rc=$?; cd - >/dev/null; return $rc
}
check rc_grpcurl_fetched_and_checksum_verified grpcurl_fetch
GRPCURL="$HOME/grpcurl-$GRPCURL_VER/grpcurl"
RC_IP=$(kc -n ricxapp get pod -l app=ricxapp-rc -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
describe() { echo "rc pod IP $RC_IP"; "$GRPCURL" -plaintext "$RC_IP:7777" describe rc.MsgComm; "$GRPCURL" -plaintext "$RC_IP:7777" describe rc.RicControlGrpcReq; }
check rc_grpc_reflection_describe describe

check rc_capture_started_before_agents capture_start rclat docker0 'ip proto 132'
CAP_T0=$(date +%s)
check rc_bringup_agents_connected_set_exact gate_bringup agents "$NODES"
echo '{}' >"$e/node-ips.json"
check rc_agent_container_ips_recorded agents_record_ips "$e/node-ips.json"
all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk -v n="$NNODES" '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == n) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check rc_every_agent_ready_and_subscribed_before_ns3 all_subscribed
check rc_ns3_started_default_config ns3_start "$RUN" "--simTime=$RC_SIMTIME" --indicationPeriodicity=0.1 \
    --e2AgentHost=127.0.0.1 "--e2TraceDir=$RUN"
sleep 20

# One control: PLMN 001/01 BCD 00F110, UE 1, target cell id hex; ranName = node's e2mgr name.
send_calls() {
    local i id name t0 t1 rc
    : >"$e/calls.tsv"
    for ((i = 0; i < RC_CALLS; i++)); do
        id=$((i % NNODES + 1)); name=$(printf 'gnb_001_001_%08x' "$id")
        t0=$(date +%s.%N)
        "$GRPCURL" -plaintext -d "{
  \"e2NodeID\": \"$name\", \"plmnID\": \"00F110\", \"ranName\": \"$name\",
  \"RICE2APHeaderData\": { \"RanFuncId\": 3, \"RICRequestorID\": 1 },
  \"RICControlHeaderData\": { \"ControlStyle\": 3, \"ControlActionId\": 1,
     \"UEID\": { \"GnbUEID\": { \"amfUENGAPID\": $((i + 1)), \"gNBCUUEF1APID\": [1], \"gNBCUCPUEE1APID\": [1],
        \"guami\": { \"pLMNIdentity\": \"00F110\", \"aMFRegionID\": \"128\", \"aMFSetID\": \"1\", \"aMFPointer\": \"0\" } } } },
  \"RICControlMessageData\": { \"RICControlCellTypeVal\": 1, \"TargetCellID\": \"0000000003\" },
  \"RICControlAckReqVal\": 2
}" "$RC_IP:7777" rc.MsgComm/SendRICControlReqServiceGrpc >"$e/calls/call-$i.out" 2>&1
        rc=$?
        t1=$(date +%s.%N)
        printf '%d\t%d\t%s\t%s\t%s\t%d\n' "$i" "$id" "$name" "$t0" "$t1" "$rc" >>"$e/calls.tsv"
        sleep "$RC_GAP_S"
    done
    awk -F'\t' '$6 != 0 { bad++ } END { print NR " calls, " bad + 0 " grpcurl failures"; exit bad > 0 }' "$e/calls.tsv"
}
check rc_grpc_calls_sent send_calls
sleep 5
rc_pod_after() { pod_info ricxapp xapp-rc- | tee "$e/rc-pod-after.txt"; }
check rc_pod_after_calls_recorded rc_pod_after
ns3_stop
for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
    id=$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c")
    dk logs "$c" >"$e/agent-$id.log" 2>&1
done
rc_logs() { local pod; read -r pod _ < <(pod_info ricxapp xapp-rc-) && kc -n ricxapp logs "$pod" --all-containers --since-time="$(iso_utc "$CAP_T0")" >"$e/rc.log" 2>&1; wc -l "$e/rc.log"; }
check rc_xapp_log_collected rc_logs
check rc_agents_stopped agents_stop
check rc_capture_stopped capture_stop rclat

latency() {
    tshark -r "$e/rclat.pcap" -d sctp.port==36422,e2ap -Y 'e2ap.procedureCode == 4 && e2ap.initiatingMessage_element' \
        -T fields -E separator=/t -e frame.time_epoch -e ip.dst -e sctp.dstport >"$e/rc-control-frames.tsv" 2>"$e/rc-control-frames.stderr"
    python3 -I - "$e/calls.tsv" "$e/rc-control-frames.tsv" "$e/node-ips.json" "$e/rc-latency.json" <<'PY'
import json, statistics, sys
calls_p, frames_p, ips_p, out_p = sys.argv[1:]
ip2node = {ip: int(n) for n, ips in json.load(open(ips_p)).items() for ip in ips}
frames = []
for l in open(frames_p):
    f = l.rstrip("\n").split("\t")
    if len(f) >= 2 and f[0]:
        frames.append((float(f[0]), ip2node.get(f[1])))
frames.sort()
used, rows = set(), []
for l in open(calls_p):
    i, node, name, t0, t1, rc = l.rstrip("\n").split("\t")
    t0, t1, node = float(t0), float(t1), int(node)
    hit = next((k for k, (t, n) in enumerate(frames) if k not in used and n == node and t >= t0), None)
    if hit is not None:
        used.add(hit)
    rows.append({"i": int(i), "node": node, "grpc_s": round(t1 - t0, 4),
                 "wire_s": round(frames[hit][0] - t0, 4) if hit is not None else None})
lat = [r["wire_s"] for r in rows if r["wire_s"] is not None]
g = [r["grpc_s"] for r in rows]
def q(v, p):
    v = sorted(v); return v[min(len(v) - 1, int(round(p * (len(v) - 1))))] if v else None
res = {"calls": len(rows), "matched": len(lat), "control_frames_on_wire": len(frames),
       "wire_latency_s": {"min": min(lat, default=None), "p50": q(lat, .5), "p90": q(lat, .9), "p99": q(lat, .99),
                          "max": max(lat, default=None), "mean": statistics.mean(lat) if lat else None},
       "grpcurl_call_s": {"p50": q(g, .5), "max": max(g, default=None)},
       "note": "wire = first RICcontrol initiatingMessage to the node's container IP after the grpcurl start; "
               "includes grpcurl process start", "rows": rows}
json.dump(res, open(out_p, "w"), indent=1)
print(json.dumps({k: v for k, v in res.items() if k != "rows"}))
sys.exit(0 if len(lat) == len(rows) else 1)
PY
}
check rc_every_call_reached_its_agent_on_the_wire latency
check rc_hygiene agents_hygiene
gate_finish

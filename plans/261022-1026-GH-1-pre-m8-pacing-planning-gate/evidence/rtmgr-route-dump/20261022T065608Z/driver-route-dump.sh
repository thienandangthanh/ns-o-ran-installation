#!/usr/bin/env bash
# VM-side driver for the live route-table dump (open question 5 / gap G9). Not a committed probe: it reuses the
# harness helpers at HARNESS_DIR and the rc install + grpcurl method of scripts/probes/probe-rc-control-latency.sh.
# Phases: p1 rc installed (no agents) -> p2 five agents CONNECTED and kpimon subscribed -> controls -> p3 after.
# Each phase dumps rtmgr's getdebuginfo, the RMR route table stashed by e2term, rc and kpimon, and submgr's
# subscription list. RMR TCP on cni0 and SCTP on docker0 are captured around the controls. No ns-3.
source "$HARNESS_DIR/scripts/gates/lib.sh"
gate_init rtmgr-route-dump
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"

NODES="enb:1,gnb:2,gnb:3,gnb:4,gnb:5"; NNODES=5
RC_CALLS="${RC_CALLS:-10}"; RC_GAP_S="${RC_GAP_S:-3}"
GRPCURL="$HOME/grpcurl-1.9.1/grpcurl"
e="$EVIDENCE_DIR"; mkdir -p "$e/calls"

dump_phase() {
    local p="$1" ip pod
    ip=$(kc -n ricplt get svc service-ricplt-rtmgr-http -o jsonpath='{.spec.clusterIP}')
    curl -s -m 10 "http://$ip:3800/ric/v1/getdebuginfo" >"$e/$p-rtmgr-getdebuginfo.json"
    python3 -I -c 'import json,sys; [print(r.rstrip()) for r in json.load(open(sys.argv[1]))["RouteTable"]]' \
        "$e/$p-rtmgr-getdebuginfo.json" >"$e/$p-rtmgr-routetable.txt"
    read -r pod _ < <(pod_info ricplt e2term-alpha) &&
        kc -n ricplt exec "$pod" -- sh -c 'ls -la /opt/e2/router.txt*; cat /opt/e2/router.txt.stash' >"$e/$p-e2term-stash.txt" 2>&1
    for x in kpimon-go rc hw-go; do
        read -r pod _ < <(pod_info ricxapp "ricxapp-$x-") || read -r pod _ < <(pod_info ricxapp "xapp-$x-") || continue
        kc -n ricxapp exec "$pod" -- sh -c 'env | grep -E "^RMR_" ; for f in $(find / -xdev -name "*.stash" 2>/dev/null); do echo "### $f"; cat "$f"; done' \
            >"$e/$p-$x-stash.txt" 2>&1
    done
    ip=$(kc -n ricplt get pod -l app=ricplt-submgr -o jsonpath='{.items[0].status.podIP}')
    curl -s -m 10 "http://$ip:8088/ric/v1/subscriptions" >"$e/$p-submgr-subscriptions.json"
    curl -s -m 10 "http://$ip:3800/ric/v1/subscriptions" >"$e/$p-submgr-subscriptions-3800.json"
    kc get pods -A -o wide >"$e/$p-pods-wide.txt"
    kc get svc -A >"$e/$p-svc.txt"
    grep -E '\|1204[012]\||\|1201[01]\||\|12050\|' "$e/$p-e2term-stash.txt" | sed "s/^/$p e2term-stash: /"
}

check route_tree agents_tree_at_testbed_sha
check route_tools agents_ensure_build_tools
check route_sctp agents_sctp_module

install_rc() {
    _agents_prepare_env
    nist_run 3600 "$RIC_DIR/additional_scripts/install_xapp_ric_control.sh" >"$e/install-rc.log" 2>&1 || { tail -n 30 "$e/install-rc.log"; return 1; }
    git -C "$RIC_DIR/xApps/rc" rev-parse HEAD | tee "$e/rc-sha.txt"
    local deadline=$(($(date +%s) + 300)) name ready
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if read -r name ready _ < <(pod_info ricxapp xapp-rc-) && [ "$ready" = true ]; then pod_info ricxapp xapp-rc- | tee "$e/rc-pod-before.txt"; return 0; fi
        sleep 5
    done
    return 1
}
check route_rc_installed install_rc
grpcurl_fetch() {
    local d="$HOME/grpcurl-1.9.1" base="https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1" tgz=grpcurl_1.9.1_linux_x86_64.tar.gz
    mkdir -p "$d" && cd "$d" || return 1
    curl -fsSLO "$base/$tgz" && curl -fsSLO "$base/grpcurl_1.9.1_checksums.txt" &&
        grep " $tgz\$" grpcurl_1.9.1_checksums.txt | sha256sum -c - && tar -xzf "$tgz" grpcurl && ./grpcurl -version
    local rc=$?; cd - >/dev/null; return $rc
}
check route_grpcurl grpcurl_fetch
sleep 20
check route_dump_p1_rc_installed dump_phase p1

check route_capture_rmr capture_start rmr cni0 'tcp port 4560 or tcp port 38000'
check route_capture_e2ap capture_start e2ap docker0 'ip proto 132'
check route_agents_connected gate_bringup agents "$NODES"
echo '{}' >"$e/node-ips.json"; check route_agent_ips agents_record_ips "$e/node-ips.json"
all_subscribed() {
    local deadline=$(($(date +%s) + 180)) rows
    while [ "$(date +%s)" -lt "$deadline" ]; do
        rows=$(agents_stats_all)
        echo "$rows" | awk -v n="$NNODES" '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == n) }' && { echo "$rows"; return 0; }
        sleep 3
    done
    echo "$rows"; return 1
}
check route_all_subscribed all_subscribed
sleep 15
check route_dump_p2_subscribed dump_phase p2

RC_IP=$(kc -n ricxapp get pod -l app=ricxapp-rc -o jsonpath='{.items[0].status.podIP}')
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
        rc=$?; t1=$(date +%s.%N)
        printf '%d\t%d\t%s\t%s\t%s\t%d\n' "$i" "$id" "$name" "$t0" "$t1" "$rc" >>"$e/calls.tsv"
        sleep "$RC_GAP_S"
    done
    cat "$e/calls.tsv"
}
CT0=$(date +%s)
check route_controls_sent send_calls
sleep 10
check route_dump_p3_after_controls dump_phase p3
collect_logs() {
    local pod x
    for x in "ricplt e2term-alpha" "ricplt rtmgr" "ricplt submgr" "ricxapp xapp-rc-" "ricxapp kpimon-go" "ricxapp hw-go"; do
        read -r pod _ < <(pod_info $x) || continue
        kc -n "${x%% *}" logs "$pod" --all-containers --since-time="$(iso_utc "$CT0")" >"$e/log-${x##* }.log" 2>&1
    done
    read -r pod _ < <(pod_info ricxapp xapp-rc-) && kc -n ricxapp logs "$pod" --all-containers >"$e/log-rc-full.log" 2>&1
    pod_info ricxapp xapp-rc- | tee "$e/rc-pod-after.txt"
    for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
        dk logs "$c" >"$e/agent-$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c").log" 2>&1
    done
    wc -l "$e"/log-*.log
}
check route_logs collect_logs
check route_agents_stopped agents_stop
check route_capture_e2ap_stopped capture_stop e2ap
check route_capture_rmr_stopped capture_stop rmr
GATE_SKIP_DISK_GUARD=1 gate_finish

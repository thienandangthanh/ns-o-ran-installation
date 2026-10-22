#!/usr/bin/env bash
# rc-lib.sh: helpers shared by the R-rung gates (VM side). Source after lib.sh, bringup.sh, kpimon.sh
# and agents.sh. Judge on the wire, the ledger and the digests, never on rc's log: rc answers its gRPC
# callers at once and sends the control asynchronously (F1).
#
#   rc_install                    rc at the pinned commit through NIST's installer; fail if HEAD differs
#   rc_grpcurl_fetch              pinned grpcurl release, sha256-checked -> $GRPCURL
#   rc_ready                      pod Ready + gRPC describe through the Service + the 12040 route
#   rc_route_dump <label>         rtmgr getdebuginfo and e2term's stash -> $e/<label>-*.txt; sets
#                                 ROUTE_OWNER_12041 / ROUTE_OWNER_12042 (the last `-1` line wins in RMR)
#   rc_pod_snapshot <label>       "<pod> <uid> <restarts>" of rc, kpimon, hw-go and the agents -> $e/<label>-pods.tsv
#   rc_restarts_zero <label>      every restart count in that file is 0
#   rc_influx_bucket_reset        delete and re-create the kpimon bucket; its id -> $e/influx-bucket-id.txt
#   rc_ric_reset                  restart rc (fresh pod), fresh Influx bucket, wait for readiness
#   rc_send_control <args...>     one control through rc's gRPC (see below)
#
# Pins: RC_SHA is the commit rc is built from (the P0 decoder and the agent's codec use the same one).
RC_SHA=a2282eedc9e32f60298bf530456ad367bef0824b
GRPCURL_VER=1.9.1
GRPCURL="$HOME/grpcurl-$GRPCURL_VER/grpcurl"
RC_GRPC_MAX_TIME_S="${RC_GRPC_MAX_TIME_S:-10}"

rc_install() {
    local e="$EVIDENCE_DIR" deadline name ready sha
    _agents_prepare_env
    nist_run 3600 "$RIC_DIR/additional_scripts/install_xapp_ric_control.sh" >"$e/install-rc.log" 2>&1 || {
        tail -n 30 "$e/install-rc.log"; return 1; }
    sha=$(git -C "$RIC_DIR/xApps/rc" rev-parse HEAD) || return 1
    echo "$sha" | tee "$e/rc-sha.txt"
    [ "$sha" = "$RC_SHA" ] || { echo "rc is at $sha, pinned $RC_SHA"; return 1; }
    deadline=$(($(date +%s) + 300))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if read -r name ready _ < <(pod_info ricxapp xapp-rc-) && [ "$ready" = true ]; then
            pod_info ricxapp xapp-rc- | tee "$e/rc-pod-after-install.txt"; return 0
        fi
        sleep 5
    done
    kc -n ricxapp get pods -o wide; return 1
}

rc_grpcurl_fetch() {
    local d="$HOME/grpcurl-$GRPCURL_VER" base="https://github.com/fullstorydev/grpcurl/releases/download/v$GRPCURL_VER"
    local tgz="grpcurl_${GRPCURL_VER}_linux_x86_64.tar.gz" rc
    mkdir -p "$d" && cd "$d" || return 1
    if [ -x grpcurl ] && ./grpcurl -version >/dev/null 2>&1; then rc=0
    else
        curl -fsSLO "$base/$tgz" && curl -fsSLO "$base/grpcurl_${GRPCURL_VER}_checksums.txt" &&
            grep " $tgz\$" "grpcurl_${GRPCURL_VER}_checksums.txt" | sha256sum -c - && tar -xzf "$tgz" grpcurl
        rc=$?
    fi
    [ "$rc" = 0 ] && ./grpcurl -version
    rc=$?; cd - >/dev/null || true; return $rc
}

# rc is reached through its Service (the pod IP changes with every reset).
rc_endpoint() {
    local ip
    ip=$(kc -n ricxapp get svc service-ricxapp-rc-grpc-server -o jsonpath='{.spec.clusterIP}') || return 1
    [ -n "$ip" ] || return 1
    echo "$ip:7777"
}

rc_ready() {
    local name ready ep
    read -r name ready _ < <(pod_info ricxapp xapp-rc-) && [ "$ready" = true ] || { echo "rc pod not ready"; return 1; }
    ep=$(rc_endpoint) || { echo "no rc Service on 7777"; return 1; }
    echo "rc $name ready, gRPC endpoint $ep"
    "$GRPCURL" -plaintext -max-time "$RC_GRPC_MAX_TIME_S" "$ep" describe rc.MsgComm >/dev/null || { echo "gRPC describe failed"; return 1; }
    rc_route_dump ready-probe >/dev/null || return 1
    grep -q '^mse|12040,service-ricxapp-rc-rmr' "$EVIDENCE_DIR/ready-probe-routetable.txt" || { echo "no 12040 route to rc"; return 1; }
    echo "gRPC describe ok, 12040 route to rc present"
}

rc_route_dump() {
    local p="$1" e="$EVIDENCE_DIR" ip pod
    ip=$(kc -n ricplt get svc service-ricplt-rtmgr-http -o jsonpath='{.spec.clusterIP}') || return 1
    curl -s -m 10 "http://$ip:3800/ric/v1/getdebuginfo" >"$e/$p-rtmgr-getdebuginfo.json" || return 1
    python3 -I -c 'import json,sys; [print(r.rstrip()) for r in json.load(open(sys.argv[1]))["RouteTable"]]' \
        "$e/$p-rtmgr-getdebuginfo.json" >"$e/$p-routetable.txt" || return 1
    read -r pod _ < <(pod_info ricplt e2term-alpha) &&
        kc -n ricplt exec "$pod" -- sh -c 'cat /opt/e2/router.txt.stash' >"$e/$p-e2term-stash.txt" 2>&1
    # RMR keeps the last `-1` line of a message type: that service gets the acks that match no exact key
    ROUTE_OWNER_12041=$(grep -E '^mse\|12041\|-1\|' "$e/$p-routetable.txt" | tail -n 1 | cut -d'|' -f4)
    ROUTE_OWNER_12042=$(grep -E '^mse\|12042\|-1\|' "$e/$p-routetable.txt" | tail -n 1 | cut -d'|' -f4)
    echo "route owner 12041|-1 = $ROUTE_OWNER_12041; 12042|-1 = $ROUTE_OWNER_12042"
}

# rc_pod_snapshot <label>: pod name, uid, restart count of rc, kpimon, hw-go; agent containers by node id.
rc_pod_snapshot() {
    local f="$EVIDENCE_DIR/$1-pods.tsv" c
    kc -n ricxapp get pods -o json | python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    n = p["metadata"]["name"]
    cs = p["status"].get("containerStatuses", [])
    print("\t".join(["pod", n, p["metadata"]["uid"], str(sum(c.get("restartCount", 0) for c in cs))]))' >"$f" || return 1
    for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
        printf 'agent\t%s\t%s\t%s\n' "$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c")" \
            "$(dk inspect --format '{{.Id}}' "$c" | cut -c1-12)" "$(dk inspect --format '{{.RestartCount}}' "$c")" >>"$f"
    done
    cat "$f"
}

rc_restarts_zero() {
    local f="$EVIDENCE_DIR/$1-pods.tsv"
    awk -F'\t' '$4 != 0 { print "restart count " $4 " for " $1 " " $2; bad = 1 } END { exit bad }' "$f"
}

# The in-pod influx CLI uses the pod's own admin token, expanded inside the pod; it never reaches this shell.
_influx() {
    # shellcheck disable=SC2016
    kc exec -n ricplt "$INFLUX_POD" -- sh -c \
        'export INFLUX_TOKEN="${INFLUX_TOKEN:-$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}"; exec influx "$@"' _ "$@" </dev/null
}

rc_influx_bucket_reset() {
    _influx bucket delete --name kpimon --org influxdata >/dev/null 2>&1 || true
    _influx bucket create --name kpimon --org influxdata --retention 0 >/dev/null || return 1
    _influx bucket list --name kpimon --org influxdata --hide-headers | awk '{print $1}' | tee "$EVIDENCE_DIR/influx-bucket-id.txt"
    [ -s "$EVIDENCE_DIR/influx-bucket-id.txt" ]
}

# rc_ric_reset: a fresh Influx bucket, then fresh rc, kpimon and hw-go pods (new pod names, restart
# count 0), each waited for. The contract's "RestartCount = 0" then holds literally: the pods that stay
# deployed carry restarts from earlier VM boots, so they are recreated per run. Agents are restarted by
# their own bring-up (ctlId starts at 1 in every run). kpimon is back before the agents subscribe.
rc_ric_reset() {
    local x pod name ready deadline old
    rc_influx_bucket_reset || return 1
    for x in xapp-rc- ricxapp-kpimon-go- ricxapp-hw-go-; do
        read -r old _ < <(pod_info ricxapp "$x") || { echo "no pod $x"; return 1; }
        kc -n ricxapp delete pod "$old" --wait=true >/dev/null || return 1
        deadline=$(($(date +%s) + 300))
        while :; do
            if read -r name ready _ < <(pod_info ricxapp "$x") && [ "$ready" = true ] && [ "$name" != "$old" ]; then break; fi
            [ "$(date +%s)" -lt "$deadline" ] || { echo "$x did not come back"; return 1; }
            sleep 5
        done
        echo "$x: $old -> $name"
    done
    sleep 15
    rc_ready
}

# rc_send_control <viaNodeId> <imsi> <targetKey10hex> [ackReq]: one control through rc (see rc-send.sh).
rc_send_control() {
    local ep
    ep=$(rc_endpoint) || return 1
    bash "$HARNESS_DIR/scripts/gates/rc-send.sh" "$ep" "$@"
}

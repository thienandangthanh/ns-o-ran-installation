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
#   rc_pod_snapshot <label>       "<kind> <pod|node> <uid|id> <restarts> <start> <container start>" of the ricxapp
#                                 pods and the agents -> $e/<label>-pods.tsv
#   rc_restarts_zero <label>      every restart count in that file is 0
#   rc_restarts_zero_all <run>... each named run's after-snapshot exists, is non-empty and has restart counts 0
#   rc_influx_bucket_reset        delete and re-create the kpimon bucket; its id -> $e/influx-bucket-id.txt
#   rc_ric_reset [label]          fresh Influx bucket, fresh rc/kpimon/hw-go pods, rtmgr restarted, rc RMR ready;
#                                 with a label, $e/<label>-reset.json records the bucket id and the pods (name,
#                                 uid, start times) before and after, and the reset fails unless all are new
#   rc_restart_rtmgr              delete rtmgr's pod and wait for the new one (it only opens a connection to an xApp
#                                 the first time it sees the endpoint, and never reconnects to a replaced pod)
#   rc_rmr_ready                  rc's own `RMR is ready after` log line in its current container (bounded wait)
#   rtmgr_push_acked <svc> [ns]   the running rtmgr pod logged a successful route push to <svc>'s RMR port 4560
#                                 (written only when that endpoint's RMR answered the route-table call; bounded wait)
#   rc_rmr_ready_after_rtmgr      rc_rmr_ready, then rtmgr_push_acked for rc's RMR Service
#   rc_at_pin                     rc's source tree at RC_SHA and rc ready; install nothing
# rc_install is NOT part of any per-run path: NIST's script always runs `dms_cli uninstall` first, which deletes
# rc's Services and leaves rtmgr holding a dead connection to the old pod. Use it once (gate i0), then rc_restart_rtmgr.
#   rc_send_control <args...>     one control through rc's gRPC (see below)
#
# Kept pods: a gate reads a pod's one-time start-up line only from a pod the gate itself created (rc_ric_reset,
# ts_stub_pods_reset). rc logs a line for every kubelet probe (about 150 KB/h), kubelet rotates a container log
# at 10 MiB (about 70 h for rc) and `kubectl logs` reads only the newest file, so an older pod's start-up line is
# gone. For a kept pod, liveness comes from fresh evidence: an rtmgr push acknowledgement, a session, wire bytes.
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
            pod_info ricxapp xapp-rc- | tee "$e/rc-pod-after-install.txt"
            rc_restart_rtmgr && rc_rmr_ready; return $?
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
    rc_rmr_ready
}

# A Ready pod, the gRPC server and the 12040 row of rtmgr's table are not enough: rc's gRPC server starts before
# its RMR does, and a control that arrives first panics it (gControlData is set only when RMR is ready).
rc_rmr_ready() {
    local pod deadline logs line
    read -r pod _ < <(pod_info ricxapp xapp-rc-) || return 1
    deadline=$(($(date +%s) + ${RC_RMR_READY_TIMEOUT_S:-90}))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        # the log goes into a variable first: `kubectl logs | grep -q` dies of SIGPIPE under pipefail on a long log
        logs=$(kc -n ricxapp logs "$pod" 2>/dev/null)
        line=$(printf '%s\n' "$logs" | grep -o 'rmrClient: RMR is ready after[^"]*' | head -n 1)
        if [ -n "$line" ]; then echo "$line"; return 0; fi
        sleep 3
    done
    echo "rc $pod: no 'RMR is ready' line within ${RC_RMR_READY_TIMEOUT_S:-90} s"; return 1
}

# rtmgr_push_acked <svc> [ns]: read only from an rtmgr pod this gate restarted (rtmgr logs at DEBUG and rotates
# within hours); the line recurs with every push, so the first match is enough.
rtmgr_push_acked() {
    local pod line ep="$1.${2:-ricxapp}:4560" deadline=$(($(date +%s) + ${RTMGR_PUSH_ACK_TIMEOUT_S:-90}))
    read -r pod _ < <(kc -n ricplt get pods --no-headers | awk '/rtmgr/ && $3 == "Running" { print $1 }')
    [ -n "$pod" ] || { echo "no running rtmgr pod"; return 1; }
    while [ "$(date +%s)" -lt "$deadline" ]; do
        line=$(grep -F -m 1 "Update Routes to Endpoint: $ep successful" < <(kc -n ricplt logs "$pod" -c container-ricplt-rtmgr 2>/dev/null))
        if [ -n "$line" ]; then echo "rtmgr $pod: $(grep -o '"msg":"[^"]*' <<<"$line" | cut -c8-)"; return 0; fi
        sleep 3
    done
    echo "rtmgr $pod: no successful route push to $ep within ${RTMGR_PUSH_ACK_TIMEOUT_S:-90} s"; return 1
}

rc_rmr_ready_after_rtmgr() { rc_rmr_ready && rtmgr_push_acked service-ricxapp-rc-rmr; }

rc_at_pin() {
    [ "$(git -C "$RIC_DIR/xApps/rc" rev-parse HEAD)" = "$RC_SHA" ] && rc_ready
}

rc_restart_rtmgr() {
    local old name deadline
    old=$(kc -n ricplt get pods --no-headers | awk '/rtmgr/ { print $1 }' | head -n 1)
    [ -n "$old" ] || { echo "no rtmgr pod"; return 1; }
    kc -n ricplt delete pod "$old" --wait=true >/dev/null || return 1
    deadline=$(($(date +%s) + 180))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        name=$(kc -n ricplt get pods --no-headers | awk '/rtmgr/ && $2 == "1/1" && $3 == "Running" { print $1 }' | head -n 1)
        [ -n "$name" ] && [ "$name" != "$old" ] && { echo "rtmgr $old -> $name"; sleep 5; return 0; }
        sleep 3
    done
    echo "rtmgr did not come back"; return 1
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
    # e2term's stash is what routes the acks; delta updates overwrite it, so it may hold no `-1` line at all
    ROUTE_OWNER_E2TERM_12041=$(grep -E '^mse\|12041\|-1\|' "$e/$p-e2term-stash.txt" 2>/dev/null | tail -n 1 | cut -d'|' -f4)
    ROUTE_OWNER_E2TERM_12042=$(grep -E '^mse\|12042\|-1\|' "$e/$p-e2term-stash.txt" 2>/dev/null | tail -n 1 | cut -d'|' -f4)
    : "${ROUTE_OWNER_E2TERM_12041:=unknown}" "${ROUTE_OWNER_E2TERM_12042:=unknown}"
    echo "route owner 12041|-1 = $ROUTE_OWNER_12041 (rtmgr) / $ROUTE_OWNER_E2TERM_12041 (e2term stash); 12042|-1 = $ROUTE_OWNER_12042 / $ROUTE_OWNER_E2TERM_12042"
}

# rc_pod_snapshot <label>: pod name, uid, restart count of rc, kpimon, hw-go; agent containers by node id.
rc_pod_snapshot() {
    local f="$EVIDENCE_DIR/$1-pods.tsv" c
    kc -n ricxapp get pods -o json | python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    n = p["metadata"]["name"]
    cs = p["status"].get("containerStatuses", [])
    started = ",".join(sorted(c.get("state", {}).get("running", {}).get("startedAt", "-") for c in cs)) or "-"
    print("\t".join(["pod", n, p["metadata"]["uid"], str(sum(c.get("restartCount", 0) for c in cs)),
                    p["status"].get("startTime", "-"), started]))' >"$f" || return 1
    for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
        printf 'agent\t%s\t%s\t%s\t%s\t%s\n' "$(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}}' "$c")" \
            "$(dk inspect --format '{{.Id}}' "$c" | cut -c1-12)" "$(dk inspect --format '{{.RestartCount}}' "$c")" \
            "$(dk inspect --format '{{.Created}}' "$c")" "$(dk inspect --format '{{.State.StartedAt}}' "$c")" >>"$f"
    done
    cat "$f"
}

rc_restarts_zero() {
    local f="$EVIDENCE_DIR/$1-pods.tsv"
    awk -F'\t' '$4 != 0 { print "restart count " $4 " for " $1 " " $2; bad = 1 } END { exit bad }' "$f"
}

# rc_restarts_zero_all <run>...: each named run's after-snapshot exists, is non-empty and shows restart count 0
rc_restarts_zero_all() {
    local l bad=0
    [ $# -ge 1 ] || { echo "no run named"; return 1; }
    for l in "$@"; do
        if [ ! -s "$EVIDENCE_DIR/$l-after-pods.tsv" ]; then
            echo "$l: no after-snapshot"; bad=1
        elif ! rc_restarts_zero "$l-after"; then
            echo "$l: restart count not 0"; bad=1
        fi
    done
    [ "$bad" = 0 ] && echo "restart counts 0 in: $*"
    return "$bad"
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

# rc_ric_reset: a fresh Influx bucket, then fresh rc, kpimon and hw-go pods (new names, restart count 0)
# deleted together, then rtmgr restarted so it opens new connections to them (it never reconnects to a replaced
# pod), then rc's own RMR-ready line. The contract's "RestartCount = 0" holds literally: the pods that stay
# deployed carry restarts from earlier VM boots, so they are recreated per run. rc never gets SIGTERM (PID 7 under
# sh), so a short grace period costs nothing. Agents are restarted by their own bring-up (ctlId starts at 1).
rc_ric_reset() {
    local x old name deadline label="${1:-}" r="$EVIDENCE_DIR/${1:-}-reset"
    declare -A OLD
    if [ -n "$label" ]; then
        date -u +%Y-%m-%dT%H:%M:%SZ >"$r-start.txt"
        _influx bucket list --name kpimon --org influxdata --hide-headers 2>/dev/null | awk '{print $1}' >"$r-bucket-before.txt"
        kc -n ricxapp get pods -o json >"$r-pods-before.json" || return 1
    fi
    rc_influx_bucket_reset || return 1
    for x in xapp-rc- ricxapp-kpimon-go- ricxapp-hw-go-; do
        read -r old _ < <(pod_info ricxapp "$x") || { echo "no pod $x"; return 1; }
        OLD[$x]=$old
        kc -n ricxapp delete pod "$old" --grace-period=5 --wait=false >/dev/null || return 1
    done
    for x in xapp-rc- ricxapp-kpimon-go- ricxapp-hw-go-; do
        deadline=$(($(date +%s) + 300))
        while :; do
            if read -r name ready _ < <(pod_info ricxapp "$x") && [ "$ready" = true ] && [ "$name" != "${OLD[$x]}" ]; then break; fi
            [ "$(date +%s)" -lt "$deadline" ] || { echo "$x did not come back"; return 1; }
            sleep 3
        done
        echo "$x: ${OLD[$x]} -> $name"
    done
    rc_restart_rtmgr || return 1
    rc_ready || return 1
    [ -n "$label" ] || return 0
    cp "$EVIDENCE_DIR/influx-bucket-id.txt" "$r-bucket-after.txt"
    kc -n ricxapp get pods -o json >"$r-pods-after.json" || return 1
    python3 -I "$HARNESS_DIR/scripts/gates/check-ric-reset.py" "$r"
}

# rc_send_control <viaNodeId> <imsi> <targetKey10hex> [ackReq]: one control through rc (see rc-send.sh).
rc_send_control() {
    local ep
    ep=$(rc_endpoint) || return 1
    bash "$HARNESS_DIR/scripts/gates/rc-send.sh" "$ep" "$@"
}

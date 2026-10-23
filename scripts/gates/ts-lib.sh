#!/usr/bin/env bash
# ts-lib.sh: helpers for the TS xApp, the stub QP and the RMR injector (VM side). Source after lib.sh,
# bringup.sh, kpimon.sh, agents.sh and rc-lib.sh.
#
#   ts_install                    the TS xApp at TS_SHA through NIST's installer, then switched to gRPC towards rc
#                                 (the descriptor default is REST): re-onboarded and reinstalled; rtmgr restarted
#   ts_ready                      TS pod Ready, its log says it listens, and no control-API error
#   rmr_peer_build                the rmr-peer image (stub QP + injector) from tools/rmr-peer, self-tested, imported
#                                 into containerd; RMR_PEER_IMAGE names it (tag = git tree id of tools/rmr-peer)
#   stub_install                  the stub QP as xApp `stubqp` (its own descriptor), Ready; rtmgr restarted
#   ts_routes_check <label>       rtmgr's table: 30002 and 20010|20008 to the TS xApp, 30000 to exactly one
#                                 receiver, the stub (needs rc_route_dump <label> first)
#   rtmgr_sessions <svc...>       rtmgr holds an ESTABLISHED TCP session to each Service's ClusterIP:4561
#   ts_stub_pods_reset <label>    delete the TS xApp and stub pods (their Services stay), wait for new Ready pods,
#                                 restart rtmgr, check its sessions; $e/<label>-ts-reset.json proves freshness
#   ts_nodeb_list_check           the TS log's nodeb list (read once at start-up, gRPC mode only) names every
#                                 CONNECTED E2 node e2mgr knows, and cell mapping did not fail
#   ts_policy_type_ensure         A1 policy type 20008 exists at a1mediator
#   ts_policy_set <threshold> <id>  a new policy instance; wait for the TS log's threshold line (bounded)
#   stub_table_load <json>        PUT the prediction table to the stub (resets its counters and log)
#   stub_log_save <file>          the stub's log of 30000 requests and 30002 answers
#   injector_start <dir>          the RMR injector on the host network, static seed route to the TS xApp's
#                                 Service for 30003, 12041 and 12042; logs in <dir>
#   injector_stop <dir>           stop it, keep its container log
#   ts_image_ids                  image ids of the TS xApp and the stub -> $e/xapp-image-ids.json
# The TS xApp never answers A1 and starts with threshold 0, so the policy is set again after every TS restart.
TS_SHA=19e169b2e81a0dbaf3d9dc526de0415cc995ee8b
TS_DIR="$RIC_DIR/xApps/ts"
TS_RC_EP="service-ricxapp-rc-grpc-server.ricxapp:7777"
TS_POLICY_TYPE=20008
STUB_NAME=stubqp
STUB_VERSION=0.1.0
INJ_NAME=r2-rmr-injector
INJ_RMR_PORT=4590
INJ_CTL_PORT=38510
RMR_PEER_DIR="$HARNESS_DIR/tools/rmr-peer"
export CHART_REPO_URL="${CHART_REPO_URL:-http://0.0.0.0:8090}"

rmr_peer_image() { echo "127.0.0.1:80/stubqp:$(git -C "$HARNESS_DIR" rev-parse --short=12 HEAD:tools/rmr-peer)"; }
RMR_PEER_IMAGE="$(rmr_peer_image 2>/dev/null)"

svc_ip() { kc -n "$1" get svc "$2" -o jsonpath='{.spec.clusterIP}'; }

# _dms_reinstall <name> <version> <descriptor> <schema> <log>: onboard, uninstall if present, install.
_dms_reinstall() {
    local name="$1" ver="$2" desc="$3" schema="$4" lg="$5" out
    out=$(sudo -n dms_cli onboard "$desc" "$schema" 2>&1); echo "onboard: $out" >>"$lg"
    echo "$out" | grep -q '"status": "Created"' || { echo "onboard of $name failed: $out"; return 1; }
    dms_cli uninstall "$name" ricxapp >>"$lg" 2>&1 || true
    for _ in $(seq 60); do kc -n ricxapp get pods --no-headers 2>/dev/null | grep -q "ricxapp-$name-" || break; sleep 2; done
    out=$(dms_cli install "$name" "$ver" ricxapp 2>&1); echo "install: $out" >>"$lg"
    echo "$out" | grep -qE '"?status"?:\s*"?\bOK\b"?' || { echo "install of $name failed: $out"; return 1; }
}

# _wait_new_ready <prefix> <old-name|-> <timeout-s>: a Ready pod named <prefix>* other than old.
_wait_new_ready() {
    local name ready deadline=$(($(date +%s) + $3))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if read -r name ready _ < <(pod_info ricxapp "$1") && [ "$ready" = true ] && [ "$name" != "$2" ]; then
            echo "$1 -> $name"; return 0
        fi
        sleep 3
    done
    kc -n ricxapp get pods -o wide; return 1
}

ts_install() {
    local e="$EVIDENCE_DIR" sha f="$TS_DIR/xapp-descriptor/config-file_updated.json" ver
    _agents_prepare_env
    # never pipe NIST output: nist_run's idle-stdin sleep and the chartmuseum daemon inherit stdout and would
    # hold a pipe open; redact the file afterwards (as kpimon_install does)
    nist_run 3600 "$RIC_DIR/additional_scripts/install_xapp_traffic_steering.sh" >"$e/install-ts.log.raw" 2>&1
    local rc=$?
    redact_stream <"$e/install-ts.log.raw" >"$e/install-ts.log"; rm -f "$e/install-ts.log.raw"
    [ "$rc" = 0 ] || { tail -n 30 "$e/install-ts.log"; return 1; }
    sha=$(git -C "$TS_DIR" rev-parse HEAD) || return 1
    echo "$sha" | tee "$e/ts-sha.txt"
    [ "$sha" = "$TS_SHA" ] || { echo "the TS xApp is at $sha, pinned $TS_SHA"; return 1; }
    # NIST's installer edits only the seed routes (AD Service FQDN); anything else in the tree is a change
    git -C "$TS_DIR" status --short | tee "$e/ts-tree-status.txt"
    git -C "$TS_DIR" diff --stat | tee "$e/ts-tree-diffstat.txt"
    git -C "$TS_DIR" diff --name-only | grep -vxE 'assets/bootstrap.rt|routes.txt' && { echo "unexpected tracked change in the TS tree"; return 1; }
    jq --arg ep "$TS_RC_EP" '.controls.ts_control_api = "grpc" | .controls.ts_control_ep = $ep' "$f" >"$e/ts-config-file.json" || return 1
    cp "$e/ts-config-file.json" "$f"
    ver=$(jq -r .version "$f")
    (cd "$TS_DIR" && _dms_reinstall trafficxapp "$ver" ./xapp-descriptor/config-file_updated.json ./xapp-descriptor/schema.json "$e/install-ts-grpc.log") || return 1
    _wait_new_ready ricxapp-trafficxapp- - 300 || return 1
    kc -n ricxapp get cm configmap-ricxapp-trafficxapp-appconfig -o jsonpath='{.data.config-file\.json}' |
        jq '.controls' | tee "$e/ts-deployed-controls.json"
    [ "$(jq -r .ts_control_api "$e/ts-deployed-controls.json")" = grpc ] || { echo "deployed TS config is not gRPC"; return 1; }
    rc_restart_rtmgr
}

ts_ready() {
    local pod ready logs
    read -r pod ready _ < <(pod_info ricxapp ricxapp-trafficxapp-) && [ "$ready" = true ] || { echo "TS pod not ready"; return 1; }
    for _ in $(seq 30); do
        logs=$(kc -n ricxapp logs "$pod" 2>&1)
        printf '%s\n' "$logs" | grep -q 'listening on port 4560' && break
        sleep 2
    done
    printf '%s\n' "$logs" | grep -q 'listening on port 4560' || { echo "$pod: no 'listening on port 4560'"; return 1; }
    printf '%s\n' "$logs" | grep -E '\[ERROR\] a control api|unable to map cells' && { echo "$pod: control API or cell mapping error"; return 1; }
    echo "TS $pod ready and listening"
}

rmr_peer_build() {
    local e="$EVIDENCE_DIR" tar
    [ -n "$RMR_PEER_IMAGE" ] || { echo "no rmr-peer tag (harness clone not a git tree?)"; return 1; }
    timeout 1200 $(dk_cmd) build --network host -t "$RMR_PEER_IMAGE" "$RMR_PEER_DIR" >"$e/rmr-peer-build.log" 2>&1 ||
        { tail -n 20 "$e/rmr-peer-build.log"; return 1; }
    timeout 120 $(dk_cmd) run --rm --network none "$RMR_PEER_IMAGE" python3 -I /app/rmr-peer-selftest.py | tee "$e/rmr-peer-selftest.txt"
    [ "${PIPESTATUS[0]}" = 0 ] || return 1
    tar="$e/.rmr-peer.tar"
    dk save -o "$tar" "$RMR_PEER_IMAGE" && sudo -n ctr -n=k8s.io image import "$tar" >/dev/null; local rc=$?
    rm -f "$tar"
    [ $rc = 0 ] && echo "built and imported $RMR_PEER_IMAGE"
}

stub_install() {
    local e="$EVIDENCE_DIR" old
    read -r old _ < <(pod_info ricxapp "ricxapp-$STUB_NAME-") || old=-
    jq --arg t "${RMR_PEER_IMAGE##*:}" '.containers[0].image.tag = $t' "$RMR_PEER_DIR/xapp-descriptor/config-file.json" >"$e/stubqp-config-file.json" || return 1
    _dms_reinstall "$STUB_NAME" "$STUB_VERSION" "$e/stubqp-config-file.json" "$RMR_PEER_DIR/xapp-descriptor/schema.json" "$e/install-stubqp.log" || return 1
    _wait_new_ready "ricxapp-$STUB_NAME-" "$old" 300 || return 1
    rc_restart_rtmgr
}

ts_routes_check() {
    local t="$EVIDENCE_DIR/$1-routetable.txt" r30000
    grep -E '^mse\|30002\|-1\|.*trafficxapp' "$t" || { echo "no 30002 route to the TS xApp"; return 1; }
    grep -E '^mse\|20010\|20008\|.*trafficxapp' "$t" || { echo "no 20010|20008 route to the TS xApp"; return 1; }
    r30000=$(grep -E '^mse\|30000\|' "$t")
    echo "$r30000"
    [ "$(echo "$r30000" | grep -c .)" = 1 ] && echo "$r30000" | grep -q "service-ricxapp-$STUB_NAME-rmr" &&
        [ "$(echo "$r30000" | cut -d'|' -f4 | tr ',;' '\n\n' | grep -c .)" = 1 ] ||
        { echo "30000 must have exactly one receiver, the stub"; return 1; }
}

# rtmgr_sessions <svc...>: ESTABLISHED (state 01) entries to <ClusterIP>:4561 (11D1) in rtmgr's /proc/net/tcp.
rtmgr_sessions() {
    local pod s ip hex tcp bad=0
    pod=$(kc -n ricplt get pods --no-headers | awk '/rtmgr/ && $3 == "Running" { print $1 }' | head -n 1)
    tcp=$(kc -n ricplt exec "$pod" -- cat /proc/net/tcp) || return 1
    for s in "$@"; do
        ip=$(svc_ip ricxapp "$s") || { echo "no Service $s"; bad=1; continue; }
        hex=$(echo "$ip" | awk -F. '{ printf "%02X%02X%02X%02X:11D1", $4, $3, $2, $1 }')
        if echo "$tcp" | awk -v d="$hex" '$3 == d && $4 == "01" { f = 1 } END { exit !f }'; then
            echo "rtmgr $pod -> $s $ip:4561 ESTABLISHED"
        else
            echo "rtmgr $pod: no ESTABLISHED session to $s $ip:4561"; bad=1
        fi
    done
    return $bad
}

ts_stub_pods_reset() {
    local r="$EVIDENCE_DIR/$1-ts-reset" x old
    declare -A OLD
    date -u +%Y-%m-%dT%H:%M:%SZ >"$r-start.txt"
    kc -n ricxapp get pods -o json >"$r-pods-before.json" || return 1
    for x in ricxapp-trafficxapp- "ricxapp-$STUB_NAME-"; do
        read -r old _ < <(pod_info ricxapp "$x") || { echo "no pod $x"; return 1; }
        OLD[$x]=$old
        kc -n ricxapp delete pod "$old" --grace-period=5 --wait=false >/dev/null || return 1
    done
    for x in ricxapp-trafficxapp- "ricxapp-$STUB_NAME-"; do _wait_new_ready "$x" "${OLD[$x]}" 300 || return 1; done
    rc_restart_rtmgr || return 1
    kc -n ricxapp get pods -o json >"$r-pods-after.json" || return 1
    python3 -I "$HARNESS_DIR/scripts/gates/check-ts-stub-reset.py" "$r" || return 1
    # rtmgr pushes routes within seconds of its start; give it a bounded wait for every session
    for _ in $(seq 20); do
        rtmgr_sessions service-ricxapp-trafficxapp-rmr "service-ricxapp-$STUB_NAME-rmr" service-ricxapp-rc-rmr service-ricxapp-kpimon-go-rmr >/dev/null && break
        sleep 3
    done
    rtmgr_sessions service-ricxapp-trafficxapp-rmr "service-ricxapp-$STUB_NAME-rmr" service-ricxapp-rc-rmr service-ricxapp-kpimon-go-rmr
}

ts_nodeb_list_check() {
    local pod ip line connected n
    read -r pod _ < <(pod_info ricxapp ricxapp-trafficxapp-) || return 1
    for _ in $(seq 30); do
        line=$(kc -n ricxapp logs "$pod" 2>&1 | grep -m 1 'nodeb list is') && break
        sleep 2
    done
    [ -n "$line" ] || { echo "$pod: no 'nodeb list is' line (not in gRPC mode?)"; return 1; }
    echo "$line"
    kc -n ricxapp logs "$pod" 2>&1 | grep -E 'unable to map cells|Unexpected HTTP code' && { echo "$pod: cell mapping failed"; return 1; }
    ip=$(svc_ip ricplt service-ricplt-e2mgr-http) || return 1
    connected=$(curl -s -m 10 "http://$ip:3800/v1/nodeb/states" | jq -r '.[] | select(.connectionStatus == "CONNECTED") | .inventoryName')
    n=0
    for x in $connected; do
        n=$((n + 1))
        echo "$line" | grep -q "\"$x\"" || { echo "CONNECTED node $x is not in the TS xApp's nodeb list"; return 1; }
    done
    [ "$n" -ge 3 ] || { echo "only $n CONNECTED nodes at e2mgr"; return 1; }
    echo "all $n CONNECTED nodes are in the TS xApp's nodeb list"
}

_a1() { local ip; ip=$(svc_ip ricplt service-ricplt-a1mediator-http) || return 1; echo "http://$ip:10000/A1-P/v2"; }

ts_policy_type_ensure() {
    local base code
    base=$(_a1) || return 1
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$base/policytypes/$TS_POLICY_TYPE")
    if [ "$code" != 200 ]; then
        code=$(curl -s -m 10 -o "$EVIDENCE_DIR/a1-type-create.txt" -w '%{http_code}' -X PUT -H 'Content-Type: application/json' \
            --data-binary @"$HARNESS_DIR/scripts/gates/a1-ts-policy-type-20008.json" "$base/policytypes/$TS_POLICY_TYPE")
        echo "policy type $TS_POLICY_TYPE created: HTTP $code"
        [ "$code" = 201 ] || return 1
    fi
    curl -s -m 10 "$base/policytypes/$TS_POLICY_TYPE" | tee "$EVIDENCE_DIR/a1-type-$TS_POLICY_TYPE.json"
    echo; curl -s -m 10 "$base/policytypes"
}

# ts_policy_set <threshold> <instance-id>: a fresh instance id each time (the TS xApp never answers A1, so a
# delete would never complete); then the TS xApp's own log line, at most 3 instances, each logged.
ts_policy_set() {
    local th="$1" id="$2" base pod code i
    [[ "$th" =~ ^[1-9][0-9]*$ ]] || { echo "threshold must be a positive integer: $th"; return 1; }
    base=$(_a1) || return 1
    read -r pod _ < <(pod_info ricxapp ricxapp-trafficxapp-) || return 1
    for i in 1 2 3; do
        code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' \
            -d "{\"threshold\": $th}" "$base/policytypes/$TS_POLICY_TYPE/policies/$id-$i")
        echo "policy instance $id-$i threshold $th: HTTP $code"
        [ "$code" = 202 ] || [ "$code" = 201 ] || [ "$code" = 200 ] || return 1
        for _ in $(seq 20); do
            kc -n ricxapp logs "$pod" 2>&1 | grep -q "Setting Threshold for A1-P value: $th%" &&
                { kc -n ricxapp logs "$pod" 2>&1 | grep 'Setting Threshold'; return 0; }
            sleep 1
        done
        log "ts_policy_set: no threshold line in $pod 20 s after instance $id-$i (attempt $i/3)"
    done
    echo "the TS xApp never logged the threshold"; return 1
}

_stub_url() { local ip; ip=$(kc -n ricxapp get pod "$(pod_info ricxapp "ricxapp-$STUB_NAME-" | cut -d' ' -f1)" -o jsonpath='{.status.podIP}') && echo "http://$ip:8080"; }

stub_table_load() {
    local u
    u=$(_stub_url) || return 1
    for _ in $(seq 30); do [ "$(curl -s -m 5 "$u/health")" = ok ] && break; sleep 1; done
    [ "$(curl -s -m 5 "$u/health")" = ok ] || { echo "stub RMR not ready"; return 1; }
    curl -sf -m 10 -X PUT --data-binary @"$1" "$u/table" && echo
}

stub_log_save() { local u; u=$(_stub_url) && curl -sf -m 10 "$u/log" >"$1"; }

injector_start() {
    local d="$1" ip nip
    mkdir -p "$d"
    ip=$(svc_ip ricxapp service-ricxapp-trafficxapp-rmr) || return 1
    nip=$(kc get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}') || return 1
    printf 'newrt|start\nmse|30003|-1|%s:4560\nmse|12041|-1|%s:4560\nmse|12042|-1|%s:4560\nnewrt|end\n' "$ip" "$ip" "$ip" >"$d/seed.rt"
    dk rm -f "$INJ_NAME" >/dev/null 2>&1
    dk run -d --name "$INJ_NAME" --network host --user "$(id -u):$(id -g)" -v "$d:/out" \
        -e RMR_SEED_RT=/out/seed.rt -e RMR_RTG_SVC=-1 -e "RMR_SRC_ID=$nip" "$RMR_PEER_IMAGE" \
        python3 -I /app/rmr-injector.py --rmr-port "$INJ_RMR_PORT" --ctl-port "$INJ_CTL_PORT" --out /out >/dev/null || return 1
    for _ in $(seq 50); do dk logs "$INJ_NAME" 2>&1 | grep -q '^READY' && { echo "injector up, seed: $(tr '\n' ' ' <"$d/seed.rt")"; return 0; }; sleep 0.2; done
    dk logs "$INJ_NAME"; return 1
}

injector_stop() {
    dk logs "$INJ_NAME" >"$1/injector.log" 2>&1
    dk rm -f "$INJ_NAME" >/dev/null 2>&1
    true
}

ts_image_ids() {
    python3 -I -c 'import json,sys; print(json.dumps({"trafficxapp": sys.argv[1], "stubqp": sys.argv[2], "stubqpImage": sys.argv[3]}))' \
        "$(dk image inspect --format '{{.Id}}' 127.0.0.1:80/trafficxapp:latest 2>/dev/null)" \
        "$(dk image inspect --format '{{.Id}}' "$RMR_PEER_IMAGE" 2>/dev/null)" "$RMR_PEER_IMAGE" | tee "$EVIDENCE_DIR/xapp-image-ids.json"
}

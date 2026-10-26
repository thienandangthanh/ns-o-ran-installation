#!/usr/bin/env bash
# ts-lib.sh: helpers for the TS xApp, the stub QP and the RMR injector (VM side). Source after lib.sh,
# bringup.sh, kpimon.sh, agents.sh and rc-lib.sh.
#
#   ts_install                    the TS xApp at TS_SHA through NIST's installer, then switched to gRPC towards rc
#                                 (the descriptor default is REST): re-onboarded and reinstalled (no rtmgr restart:
#                                 the caller registers, then restarts rtmgr)
#   ts_patches_check              the TS xApp source is the pinned file plus exactly the Testbed fork's patches, in the
#                                 installer's order: the A1 payload patch (the Go a1mediator sends the policy body as a
#                                 JSON string; the pinned TS xApp reads an object) and the default RMR handler (a stray
#                                 12041/12042 otherwise makes xapp-frame-cpp 2.3.6 free its buffer twice)
#   ts_ready                      TS pod Ready, its log says it listens, and no control-API error
#   rmr_peer_build                the rmr-peer image (stub QP + injector) from tools/rmr-peer, self-tested, imported
#                                 into containerd; RMR_PEER_IMAGE names it (tag = git tree id of tools/rmr-peer)
#   stub_install                  the stub QP as xApp `stubqp` (its own descriptor), Ready (no rtmgr restart)
#   xapp_register <name>          register a deployed xApp with appmgr (POST /ric/v1/register) from its deployed
#                                 descriptor; neither the TS xApp (xapp-frame-cpp 2.3.6) nor the stub registers
#                                 itself, and appmgr 0.5.8 lists, so rtmgr routes, only registered xApps
#   xapp_ensure_registered <name> register only when appmgr's entry is absent or differs (a blind re-register
#                                 forces a full route redistribution)
#   xapp_deregister <name>        deregister, only when appmgr lists exactly that app/instance pair
#   xapp_list_save <file>         appmgr's xApp list
#   ts_routes_check <label> [ts]  rtmgr's table: 20010|20008 to the TS xApp; unless `ts`, also 30002 from the stub
#                                 to the TS xApp and exactly one 30000 row, from the TS xApp to the stub only (rows
#                                 of registered senders are sender-qualified: mse|<type>,<sender>|...)
#   rtmgr_sessions <[ns/]svc...>  rtmgr holds an ESTABLISHED TCP session to each Service's ClusterIP:4561
#                                 (namespace ricxapp unless given)
#   ts_stub_pods_reset <label>    delete the TS xApp and stub pods (their Services stay), wait for new Ready pods,
#                                 ensure both are registered, restart rtmgr, check its sessions (a1mediator too);
#                                 $e/<label>-ts-reset.json proves freshness, $e/<label>-appmgr-xapps.json the list
#   a1mediator_restart <label>    replace the a1mediator pod (deleted, not rolled), wait for a new Ready pod, prove it
#                                 fresh and policy type 20008 still present ($e/<label>-a1mediator-restart.json). Its
#                                 RMR keeps one TCP connection per endpoint and notices a dead peer only on a read
#                                 error; behind kube-proxy IPVS (idle entries expire after 900 s) a replaced TS pod
#                                 or Service leaves that connection black-holed, so 20010 is "sent" and lost
#   a1mediator_restart_count      restart count of the running a1mediator pod (recorded, never judged)
#   a1_ts_connection_check <label>  after the threshold line: a1mediator holds an ESTABLISHED connection to the TS
#                                 xApp's rmr ClusterIP:4560 with an empty send queue, and no :4560 connection with a
#                                 non-empty one ($e/<label>-a1mediator-proc-net-tcp.txt)
#   ts_nodeb_list_check           the TS log's nodeb list (read once at start-up, gRPC mode only) names every
#                                 CONNECTED E2 node e2mgr knows, and cell mapping did not fail
#   ts_policy_type_ensure         A1 policy type 20008 exists at a1mediator
#   ts_threshold_logged <f> <id> <th>  the log file has a threshold line after this call's first A1 payload line
#   ts_policy_set <threshold> <id>  a new policy instance; wait for the TS log's threshold line after this
#                                 call's payload line (bounded)
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
TS_PATCH_DIR="$RIC_DIR/install_patch_files/xApps/ts/src/ts_xapp"
TS_PATCHES=("$TS_PATCH_DIR/ts_xapp.cpp.patch" "$TS_PATCH_DIR/ts_xapp.cpp.default_handler.patch")
TS_PATCHED_FILE=src/ts_xapp/ts_xapp.cpp
STUB_NAME=stubqp
STUB_VERSION=0.1.0
INJ_NAME=r2-rmr-injector
INJ_RMR_PORT=4590
INJ_CTL_PORT=38510
RMR_PEER_DIR="$HARNESS_DIR/tools/rmr-peer"
RTMGR_PEERS=(service-ricxapp-trafficxapp-rmr "service-ricxapp-$STUB_NAME-rmr" service-ricxapp-rc-rmr service-ricxapp-kpimon-go-rmr
    ricplt/service-ricplt-a1mediator-rmr)
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

ts_patches_check() {
    local t p rc
    git -C "$TS_DIR" diff -- "$TS_PATCHED_FILE" >"$EVIDENCE_DIR/ts-patches-applied.diff" || return 1
    t=$(mktemp -d) || return 1
    mkdir -p "$t/$(dirname "$TS_PATCHED_FILE")"
    git -C "$TS_DIR" show "$TS_SHA:$TS_PATCHED_FILE" >"$t/$TS_PATCHED_FILE" || { rm -rf "$t"; return 1; }
    for p in "${TS_PATCHES[@]}"; do
        [ -f "$p" ] && (cd "$t" && git apply "$p") || { echo "$p missing or not applicable to the pinned file"; rm -rf "$t"; return 1; }
    done
    cmp -s "$t/$TS_PATCHED_FILE" "$TS_DIR/$TS_PATCHED_FILE"; rc=$?
    rm -rf "$t"
    [ "$rc" = 0 ] || { echo "$TS_PATCHED_FILE is not the pinned file plus exactly the Testbed fork's patches"; return 1; }
    echo "$TS_PATCHED_FILE = pin + A1 payload patch + default RMR handler patch ($(cat "${TS_PATCHES[@]}" | grep -c '^+[^+]') added lines)"
}

ts_install() {
    local e="$EVIDENCE_DIR" sha f="$TS_DIR/xapp-descriptor/config-file_updated.json" ver img_before img_after patched_before=0
    _agents_prepare_env
    # an image built before the patch existed must not survive the install (the installer skips a build when no
    # source is newer than its tar)
    img_before=$(dk image inspect --format '{{.Id}}' 127.0.0.1:80/trafficxapp:latest 2>/dev/null)
    git -C "$TS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ts_patches_check >/dev/null 2>&1 && patched_before=1
    echo "image before: ${img_before:-none}; tree patched before: $patched_before" | tee "$e/ts-image-before.txt"
    # never pipe NIST output: nist_run's idle-stdin sleep and the chartmuseum daemon inherit stdout and would
    # hold a pipe open; redact the file afterwards (as kpimon_install does)
    nist_run 3600 "$RIC_DIR/additional_scripts/install_xapp_traffic_steering.sh" >"$e/install-ts.log.raw" 2>&1
    local rc=$?
    redact_stream <"$e/install-ts.log.raw" >"$e/install-ts.log"; rm -f "$e/install-ts.log.raw"
    [ "$rc" = 0 ] || { tail -n 30 "$e/install-ts.log"; return 1; }
    sha=$(git -C "$TS_DIR" rev-parse HEAD) || return 1
    echo "$sha" | tee "$e/ts-sha.txt"
    [ "$sha" = "$TS_SHA" ] || { echo "the TS xApp is at $sha, pinned $TS_SHA"; return 1; }
    # the installer edits the seed routes (AD Service FQDN) and applies the Testbed fork's patches; anything else
    # in the tree is a change
    git -C "$TS_DIR" status --short | tee "$e/ts-tree-status.txt"
    git -C "$TS_DIR" diff --stat | tee "$e/ts-tree-diffstat.txt"
    git -C "$TS_DIR" diff --name-only | grep -vxE "assets/bootstrap.rt|routes.txt|$TS_PATCHED_FILE" && { echo "unexpected tracked change in the TS tree"; return 1; }
    ts_patches_check || return 1
    img_after=$(dk image inspect --format '{{.Id}}' 127.0.0.1:80/trafficxapp:latest 2>/dev/null)
    echo "image after: ${img_after:-none}" | tee -a "$e/ts-image-before.txt"
    [ -n "$img_after" ] || { echo "no trafficxapp image after the install"; return 1; }
    if [ "$patched_before" = 0 ] && [ -n "$img_before" ] && [ "$img_after" = "$img_before" ]; then
        echo "the image predates the patches and was not rebuilt"; return 1
    fi
    jq --arg ep "$TS_RC_EP" '.controls.ts_control_api = "grpc" | .controls.ts_control_ep = $ep' "$f" >"$e/ts-config-file.json" || return 1
    cp "$e/ts-config-file.json" "$f"
    ver=$(jq -r .version "$f")
    (cd "$TS_DIR" && _dms_reinstall trafficxapp "$ver" ./xapp-descriptor/config-file_updated.json ./xapp-descriptor/schema.json "$e/install-ts-grpc.log") || return 1
    _wait_new_ready ricxapp-trafficxapp- - 300 || return 1
    kc -n ricxapp get cm configmap-ricxapp-trafficxapp-appconfig -o jsonpath='{.data.config-file\.json}' |
        jq '.controls' | tee "$e/ts-deployed-controls.json"
    [ "$(jq -r .ts_control_api "$e/ts-deployed-controls.json")" = grpc ] || { echo "deployed TS config is not gRPC"; return 1; }
}

ts_ready() {
    local pod ready logs
    read -r pod ready _ < <(pod_info ricxapp ricxapp-trafficxapp-) && [ "$ready" = true ] || { echo "TS pod not ready"; return 1; }
    # here-strings, never `printf | grep -q`: grep -q exits on the first match and the writer dies of SIGPIPE
    # (141 under pipefail) once the kept pod's log outgrows the pipe buffer
    for _ in $(seq 30); do
        logs=$(kc -n ricxapp logs "$pod" 2>&1)
        grep -q 'listening on port 4560' <<<"$logs" && break
        sleep 2
    done
    grep -q 'listening on port 4560' <<<"$logs" || { echo "$pod: no 'listening on port 4560'"; return 1; }
    grep -E '\[ERROR\] a control api|unable to map cells' <<<"$logs" && { echo "$pod: control API or cell mapping error"; return 1; }
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
    # Ready comes before the first idle receive, so a receive-loop fault shows only seconds later
    local pod n
    sleep 8
    read -r pod _ < <(pod_info ricxapp "ricxapp-$STUB_NAME-") || return 1
    n=$(kc -n ricxapp get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')
    kc -n ricxapp logs "$pod" >"$e/stubqp-start.log" 2>&1
    [ "$n" = 0 ] && ! grep -q Traceback "$e/stubqp-start.log" || { echo "stub $pod restarted $n times or logged a traceback"; tail -n 20 "$e/stubqp-start.log"; return 1; }
    echo "stub $pod up 8 s after Ready, restart count 0, no traceback"
    # sender-qualified routes are accepted only when the sender's name equals RMR_SRC_ID:port
    [ "$(kc -n ricxapp get cm "configmap-ricxapp-$STUB_NAME-appenv" -o jsonpath='{.data.RMR_SRC_ID}')" = "service-ricxapp-$STUB_NAME-rmr.ricxapp" ] ||
        { echo "stub RMR_SRC_ID is not service-ricxapp-$STUB_NAME-rmr.ricxapp"; return 1; }
}

_appmgr() { local ip; ip=$(svc_ip ricplt service-ricplt-appmgr-http) || return 1; echo "http://$ip:8080/ric/v1"; }

xapp_list_save() { local u; u=$(_appmgr) && curl -sf -m 10 "$u/xapps" | jq . >"$1"; }

# _xapp_body <name>: the registration body built from the deployed descriptor (as ricxappframe 3.2.2 builds its own)
_xapp_body() {
    local cfg
    cfg=$(kc -n ricxapp get cm "configmap-ricxapp-$1-appconfig" -o jsonpath='{.data.config-file\.json}') || return 1
    [ -n "$cfg" ] || return 1
    jq -c --arg n "$1" '{appName: (.xapp_name // .name), appVersion: .version, configPath: "",
        appInstanceName: (.xapp_name // .name), httpEndpoint: ("service-ricxapp-" + $n + "-http.ricxapp:8080"),
        rmrEndpoint: ("service-ricxapp-" + $n + "-rmr.ricxapp:4560"), config: (. | tojson)}' <<<"$cfg"
}

# _xapp_listed_ok <name>: appmgr lists exactly one instance of that name at its rmr Service, port 4560 (its message
# lists are recorded by xapp_list_save; the routes rtmgr derives from them are judged by ts_routes_check)
_xapp_listed_ok() {
    local u cfg
    u=$(_appmgr) || return 1
    cfg=$(kc -n ricxapp get cm "configmap-ricxapp-$1-appconfig" -o jsonpath='{.data.config-file\.json}') || return 1
    curl -sf -m 10 "$u/xapps" | jq -e --arg n "$1" --argjson c "$cfg" '
        [.[] | select(.name == ($c.xapp_name // $c.name)) | .instances[]?
         | select(.name == ($c.xapp_name // $c.name) and .ip == ("service-ricxapp-" + $n + "-rmr.ricxapp") and .port == 4560)]
        | length == 1' >/dev/null
}

xapp_register() {
    local u body code
    u=$(_appmgr) || return 1
    body=$(_xapp_body "$1") || { echo "no deployed descriptor for $1"; return 1; }
    code=$(curl -s -m 10 -o "$EVIDENCE_DIR/register-$1.out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$body" "$u/register")
    echo "register $1: HTTP $code"
    [ "$code" = 201 ] || { cat "$EVIDENCE_DIR/register-$1.out"; return 1; }
    _xapp_listed_ok "$1" || { echo "appmgr does not list $1 as registered"; return 1; }
    echo "appmgr lists $1"
}

xapp_ensure_registered() {
    if _xapp_listed_ok "$1"; then echo "$1 already registered"; else xapp_register "$1"; fi
}

xapp_deregister() {
    local u n code
    u=$(_appmgr) || return 1
    n=$(curl -sf -m 10 "$u/xapps" | jq --arg n "$1" '[.[] | select(.name == $n) | .instances[]? | select(.name == $n)] | length')
    [ "$n" = 1 ] || { echo "appmgr does not list exactly one $1/$1 pair ($n); not deregistering"; return 1; }
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
        -d "{\"appName\": \"$1\", \"appInstanceName\": \"$1\"}" "$u/deregister")
    echo "deregister $1: HTTP $code"
    [ "$code" = 204 ]
}

ts_routes_check() {
    local t="$EVIDENCE_DIR/$1-routetable.txt" r30000 n
    grep -E '^mse\|20010(,[^|]+)?\|20008\|.*trafficxapp' "$t" || { echo "no 20010|20008 route to the TS xApp"; return 1; }
    [ "${2:-}" = ts ] && return 0
    grep -E "^mse\|30002,service-ricxapp-$STUB_NAME-rmr[^|]*\|-1\|.*trafficxapp" "$t" || { echo "no 30002 route from the stub to the TS xApp"; return 1; }
    r30000=$(grep -E '^mse\|30000(,[^|]+)?\|' "$t")
    echo "$r30000"
    n=$(echo "$r30000" | grep -c .)
    [ "$n" = 1 ] && echo "$r30000" | grep -qE "^mse\|30000,service-ricxapp-trafficxapp-rmr[^|]*\|-1\|service-ricxapp-$STUB_NAME-rmr[^|;,]*$" ||
        { echo "30000 must have exactly one row, from the TS xApp to the stub only ($n rows)"; return 1; }
}

# rtmgr_sessions <svc...>: ESTABLISHED (state 01) entries to <ClusterIP>:4561 (11D1) in rtmgr's /proc/net/tcp.
rtmgr_sessions() {
    local pod s ip hex tcp bad=0
    pod=$(kc -n ricplt get pods --no-headers | awk '/rtmgr/ && $3 == "Running" { print $1 }' | head -n 1)
    tcp=$(kc -n ricplt exec "$pod" -- cat /proc/net/tcp) || return 1
    for s in "$@"; do
        [[ "$s" == */* ]] || s="ricxapp/$s"
        ip=$(svc_ip "${s%%/*}" "${s#*/}") || { echo "no Service $s"; bad=1; continue; }
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
    # registrations survive a pod replacement (the Services stay) but not an appmgr restart
    xapp_ensure_registered trafficxapp && xapp_ensure_registered "$STUB_NAME" || return 1
    xapp_list_save "$EVIDENCE_DIR/$1-appmgr-xapps.json" || return 1
    a1mediator_restart "$1" || return 1
    rc_restart_rtmgr || return 1
    kc -n ricxapp get pods -o json >"$r-pods-after.json" || return 1
    python3 -I "$HARNESS_DIR/scripts/gates/check-ts-stub-reset.py" "$r" || return 1
    # rtmgr pushes routes within seconds of its start; give it a bounded wait for every session
    for _ in $(seq 20); do
        rtmgr_sessions "${RTMGR_PEERS[@]}" >/dev/null && break
        sleep 3
    done
    rtmgr_sessions "${RTMGR_PEERS[@]}"
}

ts_nodeb_list_check() {
    local pod ip line connected n
    read -r pod _ < <(pod_info ricxapp ricxapp-trafficxapp-) || return 1
    for _ in $(seq 30); do
        line=$(grep -m 1 'nodeb list is' < <(kc -n ricxapp logs "$pod" 2>&1)) && break
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

_a1_pod() { kc -n ricplt get pods --no-headers | awk '/a1mediator/ && $3 == "Running" { print $1 }' | head -n 1; }

a1mediator_restart() {
    local r="$EVIDENCE_DIR/$1-a1mediator-restart" old name deadline base code
    date -u +%Y-%m-%dT%H:%M:%SZ >"$r-start.txt"
    kc -n ricplt get pods -o json >"$r-pods-before.json" || return 1
    old=$(kc -n ricplt get pods --no-headers | awk '/a1mediator/ { print $1 }' | head -n 1)
    [ -n "$old" ] || { echo "no a1mediator pod"; return 1; }
    kc -n ricplt delete pod "$old" --wait=true >/dev/null || return 1
    deadline=$(($(date +%s) + 180))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        name=$(kc -n ricplt get pods --no-headers | awk '/a1mediator/ && $2 == "1/1" && $3 == "Running" { print $1 }' | head -n 1)
        [ -n "$name" ] && [ "$name" != "$old" ] && break
        sleep 3
    done
    [ -n "$name" ] && [ "$name" != "$old" ] || { echo "a1mediator did not come back"; return 1; }
    echo "a1mediator $old -> $name"
    kc -n ricplt get pods -o json >"$r-pods-after.json" || return 1
    python3 -I "$HARNESS_DIR/scripts/gates/check-ts-stub-reset.py" "$r" deployment-ricplt-a1mediator || return 1
    # the policy types live in SDL, so they survive the restart; GET only
    base=$(_a1) || return 1
    for _ in $(seq 20); do
        code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$base/policytypes/$TS_POLICY_TYPE")
        [ "$code" = 200 ] && break
        sleep 2
    done
    echo "policy type $TS_POLICY_TYPE after the restart: HTTP $code"
    [ "$code" = 200 ]
}

a1mediator_restart_count() { kc -n ricplt get pod "$(_a1_pod)" -o jsonpath='{.status.containerStatuses[0].restartCount}'; }

a1_ts_connection_check() {
    local f="$EVIDENCE_DIR/$1-a1mediator-proc-net-tcp.txt" ip hex
    kc -n ricplt exec "$(_a1_pod)" -- cat /proc/net/tcp >"$f" || return 1
    ip=$(svc_ip ricxapp service-ricxapp-trafficxapp-rmr) || return 1
    hex=$(echo "$ip" | awk -F. '{ printf "%02X%02X%02X%02X:11D0", $4, $3, $2, $1 }')
    # column 5 is tx_queue:rx_queue in hex
    awk -v d="$hex" '
        $3 == d && $4 == "01" && substr($5, 1, 8) == "00000000" { ok = 1 }
        $3 ~ /:11D0$/ && substr($5, 1, 8) != "00000000" { print "send queue not empty: " $2 " -> " $3 " state " $4 " queue " $5; bad = 1 }
        END { exit !(ok && !bad) }' "$f" || { echo "a1mediator has no clean ESTABLISHED connection to the TS xApp $ip:4560"; return 1; }
    echo "a1mediator -> TS xApp $ip:4560 ESTABLISHED, send queue empty; no :4560 connection with queued data"
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

# ts_threshold_logged <log-file> <id> <th>: a threshold line after this call's first A1 payload line. Only
# policy_callback prints both lines and stdout keeps its order, so such a line is this call's. A threshold line
# before it may be an earlier run's: the TS xApp flushes stdout only on the payload line's endl.
ts_threshold_logged() {
    awk -v p="\"policy_instance_id\":\"$2-" -v t="Setting Threshold for A1-P value: $3%" '
        index($0, "[INFO] Payload is ") && index($0, p) { seen = 1; next }
        seen && index($0, t) { found = 1; exit }
        END { exit !found }' "$1"
}

# _a1_delivered_attempt <log-file> <id>: the lowest instance k whose payload line is in the log, else null
# (recorded, never judged: it separates a delivery delay from the TS xApp's unflushed threshold line)
_a1_delivered_attempt() {
    local k
    for k in 1 2 3; do grep -qF "\"policy_instance_id\":\"$2-$k\"" "$1" && { echo "$k"; return; }; done
    echo null
}

# ts_policy_set <threshold> <instance-id>: a fresh instance id each time (the TS xApp never answers A1, so a
# delete would never complete); then the TS xApp's own log line, at most 3 instances, each logged. The log
# is read into $e/<id>-ts-log.txt and judged there (the last read stays as evidence).
ts_policy_set() {
    local th="$1" id="$2" base pod code i f="$EVIDENCE_DIR/$2-ts-log.txt"
    [[ "$th" =~ ^[1-9][0-9]*$ ]] || { echo "threshold must be a positive integer: $th"; return 1; }
    base=$(_a1) || return 1
    read -r pod _ < <(pod_info ricxapp ricxapp-trafficxapp-) || return 1
    for i in 1 2 3; do
        code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' \
            -d "{\"threshold\": $th}" "$base/policytypes/$TS_POLICY_TYPE/policies/$id-$i")
        echo "policy instance $id-$i threshold $th: HTTP $code"
        [ "$code" = 202 ] || [ "$code" = 201 ] || [ "$code" = 200 ] || return 1
        for _ in $(seq 20); do
            kc -n ricxapp logs "$pod" >"$f" 2>/dev/null
            if ts_threshold_logged "$f" "$id" "$th"; then
                grep -n -e 'Setting Threshold' -e "\"policy_instance_id\":\"$id-" "$f"
                echo "$i" >"$EVIDENCE_DIR/$id-a1-attempt.txt"
                _a1_delivered_attempt "$f" "$id" >"$EVIDENCE_DIR/$id-a1-delivered-attempt.txt"
                echo "threshold logged after attempt $i"; return 0
            fi
            sleep 1
        done
        log "ts_policy_set: no threshold line after a payload of $id in $pod 20 s after instance $id-$i (attempt $i/3)"
    done
    _a1_delivered_attempt "$f" "$id" >"$EVIDENCE_DIR/$id-a1-delivered-attempt.txt"
    # diagnostics for a stale a1mediator -> TS xApp connection: a1mediator's TCP table and the TS Service IP
    local a1pod; a1pod=$(kc -n ricplt get pods --no-headers | awk '/a1mediator/ && $3 == "Running" { print $1 }' | head -n 1)
    kc -n ricplt exec "$a1pod" -- cat /proc/net/tcp >"$EVIDENCE_DIR/a1mediator-proc-net-tcp.txt" 2>&1
    svc_ip ricxapp service-ricxapp-trafficxapp-rmr >"$EVIDENCE_DIR/a1-ts-service-ip.txt"
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
    for _ in $(seq 50); do grep -q '^READY' < <(dk logs "$INJ_NAME" 2>&1) && { echo "injector up, seed: $(tr '\n' ' ' <"$d/seed.rt")"; return 0; }; sleep 0.2; done
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

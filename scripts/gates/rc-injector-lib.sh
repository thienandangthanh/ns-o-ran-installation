#!/usr/bin/env bash
# rc-injector-lib.sh: the independent RIC control injector (VM side). Source after ts-lib.sh (it uses
# _dms_reinstall, _wait_new_ready, xapp_ensure_registered, xapp_deregister and RMR_PEER_IMAGE from there).
#
# The injector is tools/rmr-peer/rmr-injector.py deployed as the xApp ric-control-injector from the rmr-peer image
# (descriptor tools/rmr-peer/xapp-descriptor-ric-control-injector/). Registered with appmgr, it gets rtmgr's routes
# like rc: the sender-qualified "mse|12040,<its rmr Service>|-1|%meid" and the meid map, so a RIC_CONTROL_REQ it
# sends with a meid reaches the e2term that serves that E2 node. The PDUs come from the independent codec
# (scripts/probes/e2-probe-node.py control, in the asn1-indep image); answers are judged on the decoded wire, not
# on what the injector receives (rtmgr routes 12041/12042 by type only, and RMR keeps the last `-1` line).
#
#   injector_install              deploy the xApp (descriptor tag = RMR_PEER_IMAGE's), Ready, up 8 s with restart
#                                 count 0 and no traceback, RMR_SRC_ID = its rmr Service (sender-qualified routes
#                                 match only then); no registration, no rtmgr restart
#   injector_rmr_ready [timeout]  its log prints READY (RMR has a route table: after registration and an rtmgr push)
#   injector_routes_check <label> <meid...>  rtmgr's table (rc_route_dump <label>) has the injector's 12040 %meid
#                                 entry and maps every meid to one e2term endpoint (mme_ar)
#   injector_control <tag> <meid> <pdu-hex>  one control through the control socket (pod IP:8080); pass iff RMR
#                                 accepted it; reply in <tag>-injector-reply.json
#   injector_logs_save <label>    the injector's tx.jsonl and rx.jsonl into the evidence
#   injector_uninstall            deregister from appmgr (when listed) and uninstall
INJECTOR_NAME=ric-control-injector
INJECTOR_VERSION=0.1.0
INJECTOR_DESC_DIR="${RMR_PEER_DIR:-$HARNESS_DIR/tools/rmr-peer}/xapp-descriptor-ric-control-injector"
INJECTOR_CTL_PORT=8080

_injector_pod() { local pod; read -r pod _ < <(pod_info ricxapp "ricxapp-$INJECTOR_NAME-") && echo "$pod"; }

injector_install() {
    local e="$EVIDENCE_DIR" old pod n
    [ -n "$RMR_PEER_IMAGE" ] || { echo "no rmr-peer image tag"; return 1; }
    old=$(_injector_pod) || old=-
    jq --arg t "${RMR_PEER_IMAGE##*:}" '.containers[0].image.tag = $t' "$INJECTOR_DESC_DIR/config-file.json" \
        >"$e/$INJECTOR_NAME-config-file.json" || return 1
    _dms_reinstall "$INJECTOR_NAME" "$INJECTOR_VERSION" "$e/$INJECTOR_NAME-config-file.json" \
        "$INJECTOR_DESC_DIR/schema.json" "$e/install-$INJECTOR_NAME.log" || return 1
    _wait_new_ready "ricxapp-$INJECTOR_NAME-" "$old" 300 || return 1
    # Ready comes before the first idle receive, so a fault shows only seconds later
    sleep 8
    pod=$(_injector_pod) || return 1
    n=$(kc -n ricxapp get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')
    kc -n ricxapp logs "$pod" >"$e/$INJECTOR_NAME-start.log" 2>&1
    [ "$n" = 0 ] && ! grep -q Traceback "$e/$INJECTOR_NAME-start.log" ||
        { echo "injector $pod restarted $n times or logged a traceback"; tail -n 20 "$e/$INJECTOR_NAME-start.log"; return 1; }
    [ "$(kc -n ricxapp get cm "configmap-ricxapp-$INJECTOR_NAME-appenv" -o jsonpath='{.data.RMR_SRC_ID}')" = \
        "service-ricxapp-$INJECTOR_NAME-rmr.ricxapp" ] || { echo "injector RMR_SRC_ID is not its rmr Service"; return 1; }
    kc -n ricxapp get pod "$pod" -o jsonpath='{.spec.containers[0].command}' >"$e/$INJECTOR_NAME-command.json"
    echo "injector $pod up 8 s after Ready on $RMR_PEER_IMAGE, restart count 0, command $(cat "$e/$INJECTOR_NAME-command.json")"
}

injector_rmr_ready() {
    local pod f="$EVIDENCE_DIR/$INJECTOR_NAME-ready.log" deadline=$(($(date +%s) + ${1:-120}))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        pod=$(_injector_pod) && kc -n ricxapp logs "$pod" >"$f" 2>&1 && grep '^READY' "$f" && return 0
        sleep 3
    done
    echo "injector printed no READY line (no route table from rtmgr?)"; return 1
}

injector_routes_check() {
    local t="$EVIDENCE_DIR/$1-routetable.txt" m eps bad=0; shift
    grep -E "^mse\|12040,service-ricxapp-$INJECTOR_NAME-rmr\.ricxapp:4560\|-1\|%meid$" "$t" ||
        { echo "no 12040 %meid route from the injector"; bad=1; }
    for m in "$@"; do
        eps=$(grep -E "^mme_ar\|[^|]+\|(.* )?$m( .*)?$" "$t" | cut -d'|' -f2 | sort -u)
        if [ "$(echo "$eps" | grep -c .)" = 1 ]; then echo "meid $m -> e2term $eps"; else
            echo "meid $m maps to $(echo "$eps" | grep -c .) e2term endpoints, expected 1"; bad=1; fi
    done
    return $bad
}

injector_control() {
    local tag="$1" meid="$2" hex="$3" pod ip
    pod=$(_injector_pod) || { echo "no injector pod"; return 1; }
    ip=$(kc -n ricxapp get pod "$pod" -o jsonpath='{.status.podIP}') || return 1
    python3 -I - "$ip" "$INJECTOR_CTL_PORT" "$meid" "$hex" >"$EVIDENCE_DIR/$tag-injector-reply.json" <<'EOF' || {
import json, socket, sys
ip, port, meid, hexpdu = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
s = socket.create_connection((ip, port), timeout=10)
s.sendall(json.dumps({"op": "control", "meid": meid, "hex": hexpdu}).encode() + b"\n")
reply = json.loads(s.makefile().readline())
print(json.dumps(reply))
sys.exit(0 if reply.get("ok") is True else 1)
EOF
        echo "injector refused $tag: $(cat "$EVIDENCE_DIR/$tag-injector-reply.json")"; return 1; }
    echo "injector sent $tag to $meid: $(cat "$EVIDENCE_DIR/$tag-injector-reply.json")"
}

injector_logs_save() {
    local pod f
    pod=$(_injector_pod) || { echo "no injector pod"; return 1; }
    for f in tx rx; do
        kc -n ricxapp exec "$pod" -- sh -c "cat /tmp/injector/$f.jsonl 2>/dev/null" >"$EVIDENCE_DIR/$1-injector-$f.jsonl" || return 1
    done
    echo "injector logs: $(grep -c . "$EVIDENCE_DIR/$1-injector-tx.jsonl") sent, $(grep -c . "$EVIDENCE_DIR/$1-injector-rx.jsonl") received"
}

injector_uninstall() {
    local u n
    u=$(_appmgr) || return 1
    n=$(curl -sf -m 10 "$u/xapps" | jq --arg n "$INJECTOR_NAME" '[.[] | select(.name == $n)] | length')
    if [ "$n" != 0 ]; then xapp_deregister "$INJECTOR_NAME" || return 1; fi
    dms_cli uninstall "$INJECTOR_NAME" ricxapp >>"$EVIDENCE_DIR/install-$INJECTOR_NAME.log" 2>&1 || true
    for _ in $(seq 60); do _injector_pod >/dev/null || { echo "injector uninstalled"; return 0; }; sleep 2; done
    echo "injector pod still present"; return 1
}

#!/usr/bin/env bash
# Probe (VM side, M10 AC6 runtime + AC6a). Needs a running RIC with rc (r3p-green or later) and the asn1-indep image
# tarball copied to ~/asn1-indep/ (asn1-indep-<tag>.tar + SHA256SUMS) by the host. The VM must be reverted afterwards:
# e2mgr keeps the probe nodebs.
#
#   probe-e2-identity-setup.sh --image-tag TAG
#
# 1. FU3 live smoke: rtmgr restart, then rc readiness on rc's own route reader (rc_rmr_ready_after_rtmgr).
# 2. AC6a: an en-gNB probe node (Global en-gNB ID, 32-bit gNB ID 0x7F000001) and an eNB probe node (Global ENB ID,
#    macro eNB ID 0xFFFFE) built with the independent codec (scripts/probes/e2-probe-node.py) register with e2term.
#    Recorded: the decoded E2 Setup outcome, the meids, e2mgr's nodeb JSONs (nodeType, nbId length, ranFunctions);
#    then one KPM subscription to the eNB node through submgr's REST API under kpimon's client endpoint, with the
#    decoded request the node received and its answer.
# 3. AC6 runtime: a control through rc's gRPC to a registered probe node, then an ACK without RICcontrolOutcome
#    delivered straight to rc's RMR port (rtmgr routes 12041 elsewhere here): 3 s late (fixture B: the 2 s timer
#    has dropped the entry, rc keeps running), then at once (fixture A: rc panics and restarts); rc's RestartCount
#    before and after each, then rc readiness again.
# Everything the probe nodes send and receive is in node-*.jsonl; the docker0 capture holds the wire.
source "$(dirname "$0")/../gates/lib.sh"
gate_init e2id
source "$HARNESS_DIR/scripts/gates/bringup.sh"
source "$HARNESS_DIR/scripts/gates/capture.sh"
source "$HARNESS_DIR/scripts/gates/kpimon.sh"
source "$HARNESS_DIR/scripts/gates/agents.sh"
source "$HARNESS_DIR/scripts/gates/rc-lib.sh"

TAG=""
while [ $# -gt 0 ]; do
    case "$1" in --image-tag) TAG="$2"; shift 2 ;; *) log "unknown arg $1"; exit 2 ;; esac
done
e="$EVIDENCE_DIR"
IMG="localhost/asn1-indep:$TAG"
NODE_PY=/probes/e2-probe-node.py
ENGNB=en_gnb_001_001_7f000001   # e2term BuildRunName: "en_gnb_" + PLMN + 32-bit gNB ID in 8 hex digits
ENB=""                          # "enB_macro_" + PLMN + the 20-bit ID as e2term renders it, read back from e2mgr
SUBMGR_REST=""                  # set after bring-up: submgr's xapp-frame REST on its pod's port 8088
fact imageTag "$(json_str "$TAG")"
ric_watchdog_bg

image_loaded() {
    local d="$HOME/asn1-indep"
    (cd "$d" && sha256sum -c SHA256SUMS) || return 1
    dk load -i "$d/asn1-indep-$TAG.tar" && dk image inspect "$IMG" --format '{{.Id}}'
}
check e2id_image_checksum_verified_and_loaded image_loaded
e2term_addr() {
    kc -n ricplt get svc -o json | python3 -I -c '
import json, sys
s = [s for s in json.load(sys.stdin)["items"] if s["metadata"]["name"].startswith("service-ricplt-e2term-sctp")]
assert len(s) == 1, len(s)
print("%s:%d" % (s[0]["spec"]["clusterIP"], s[0]["spec"]["ports"][0]["port"]))' >"$e/e2term-addr.txt" && cat "$e/e2term-addr.txt"
}
# a fresh revert cold-boots the RIC: wait for every ricplt pod and for e2mgr/submgr's route readers first
check e2id_ric_ready_after_cold_boot gate_bringup ric
readers() { { rt_reader_ok e2mgr probe && rt_reader_ok submgr probe; } || ric_refresh_routes ric; }
check e2id_e2mgr_submgr_route_readers_ok readers
check e2id_e2term_service_resolved e2term_addr
E2TERM=$(cat "$e/e2term-addr.txt" 2>/dev/null)

# 1. the FU3 predicate on the live RIC (kongming P00-exit change 4)
check e2id_fu3_rtmgr_restarted rc_restart_rtmgr
check e2id_fu3_rc_ready_on_its_route_reader rc_rmr_ready_after_rtmgr

# 2. AC6a
ranfunc_src() {  # e2mgr's RNIB lives in dbaas memory and is empty after a cold boot, so the agent's list is a fixture
    cp "$HARNESS_DIR/scripts/probes/fixtures/agent-gnb-ranfunctions.json" "$e/ranfunc-src.json" && python3 -I -c '
import json, sys; d = json.load(open(sys.argv[1])); f = d["gnb"]["ranFunctions"]
print(d["_source"]); print("functions", [(x["ranFunctionId"], x["ranFunctionOid"]) for x in f]); sys.exit(0 if f else 1)' \
        "$e/ranfunc-src.json"
}
check e2id_ran_functions_copied_from_an_agent_nodeb ranfunc_src
check e2id_capture_started capture_start e2id docker0 'ip proto 132'
node_start() {   # node_start <name> <kind> <id> [node args...]
    local name="$1" kind="$2" id="$3"; shift 3
    dk rm -f "e2probe-$name" >/dev/null 2>&1
    dk run -d --name "e2probe-$name" --user "$(id -u):$(id -g)" -v "$HARNESS_DIR/scripts/probes:/probes:ro" -v "$e:/ev" "$IMG" \
        python3 "$NODE_PY" node --kind "$kind" --id "$id" --e2term "$E2TERM" --ranfunc-json /ev/ranfunc-src.json \
        --log "/ev/node-$name.jsonl" --hold 900 "$@" || return 1
    sleep 1
    dk inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' "e2probe-$name" | tee -a "$e/probe-node-ips.txt"
}
node_saw() {     # node_saw <name> <dir> <msg> [timeout-s]: the node's log holds such a PDU
    local deadline=$(($(date +%s) + ${4:-30}))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        grep -q "\"dir\": \"$2\", \"msg\": \"$3\"" "$e/node-$1.jsonl" 2>/dev/null && { grep "\"msg\": \"$3\"" "$e/node-$1.jsonl" | tail -n 1 | cut -c1-400; return 0; }
        sleep 1
    done
    echo "node $1: no $2 $3 within ${4:-30} s"; tail -n 3 "$e/node-$1.jsonl" 2>/dev/null | cut -c1-300; dk logs "e2probe-$1" 2>&1 | tail -n 5
    return 1
}
nodeb_record() { # nodeb_record <meid> <want nbId bits>: e2mgr's JSON, CONNECTED, the nbId length
    local deadline=$(($(date +%s) + 30))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        e2mgr_get "nodeb/$1" >"$e/e2mgr-nodeb-$1.json" 2>/dev/null
        python3 -I - "$e/e2mgr-nodeb-$1.json" "$2" <<'PY' && return 0
import json, sys
d = json.load(open(sys.argv[1])); nb = d.get("globalNbId", {})
body = d.get("gnb") or d.get("enb") or {}
print("ranName=%s status=%s nodeType=%s plmnId=%s nbId=%s (%d chars) body=%s ranFunctions=%s" % (
    d.get("ranName"), d.get("connectionStatus"), d.get("nodeType"), nb.get("plmnId"), nb.get("nbId"),
    len(nb.get("nbId", "")), "gnb" if "gnb" in d else ("enb" if "enb" in d else "none"),
    [f.get("ranFunctionId") for f in body.get("ranFunctions", [])]))
sys.exit(0 if d.get("connectionStatus") == "CONNECTED" and len(nb.get("nbId", "")) == int(sys.argv[2]) else 1)
PY
        sleep 2
    done
    return 1
}
check e2id_engnb_node_started node_start engnb en-gnb 7F000001 --sub-answer response
check e2id_engnb_setup_response_decoded node_saw engnb rx E2setupResponse
check e2id_engnb_meid_and_nodeb_connected_nbid_32 nodeb_record "$ENGNB" 32
check e2id_enb_node_started node_start enb enb FFFFE --sub-answer response
check e2id_enb_setup_response_decoded node_saw enb rx E2setupResponse
enb_meid() {
    ENB=$(e2mgr_states | python3 -I -c 'import json,sys; print("\n".join(n["inventoryName"] for n in json.load(sys.stdin) if n.get("inventoryName","").startswith("enB_macro_001_001_")))')
    echo "eNB meid(s): $ENB"; [[ "$ENB" =~ ^enB_macro_001_001_[0-9a-f]+$ ]]
}
check e2id_enb_meid_matches_enb_macro enb_meid
check e2id_enb_meid_and_nodeb_connected_nbid_20 nodeb_record "$ENB" 20
setup_log() {   # e2mgr's own account of both setups (the parsed XER and any save error)
    kc -n ricplt logs "$(ric_pod e2mgr)" --since=15m 2>/dev/null | grep -E "en_gnb_001_001_7f000001|enB_macro_001_001_" >"$e/e2mgr-setup-log.txt"
    grep -o 'failed saving nodebInfo[^"]*' "$e/e2mgr-setup-log.txt" | sort | uniq -c
    wc -l <"$e/e2mgr-setup-log.txt"
}
record e2id_e2mgr_setup_log_saved true "$(setup_log 2>&1 | head -c 300)"
enb_no_ranfunctions() {
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); f=(d.get("enb") or {}).get("ranFunctions") or (d.get("gnb") or {}).get("ranFunctions") or []
print("eNB nodeb ranFunctions:", f); sys.exit(0)' "$e/e2mgr-nodeb-$ENB.json"
}
record e2id_enb_nodeb_ranfunctions_recorded true "$(enb_no_ranfunctions 2>&1 | head -c 300)"

kpm_sub_bytes() {
    dk run --rm -v "$HARNESS_DIR/scripts/probes:/probes:ro" "$IMG" python3 "$NODE_PY" kpm-sub --period-ms 100 \
        --meas DRB.UEThpDl --meas RRU.PrbUsedDl >"$e/kpm-sub-bytes.json" && cat "$e/kpm-sub-bytes.json"
}
check e2id_kpm_subscription_octets_encoded kpm_sub_bytes
# the deployed service-ricplt-submgr-http is headless and maps only port 3800, while submgr serves its REST API on
# 8088 (xApps reach the pod through DNS); the VM reaches pod IPs directly
SUBMGR_REST="http://$(kc -n ricplt get pod "$(ric_pod submgr)" -o jsonpath='{.status.podIP}'):8088/ric/v1/subscriptions"
fact submgrRest "$(json_str "$SUBMGR_REST")"
enb_subscribe() {
    python3 -I - "$e/kpm-sub-bytes.json" "$ENB" >"$e/enb-sub-request.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))
print(json.dumps({"SubscriptionId": "", "Meid": sys.argv[2], "RANFunctionID": 2,
                  "ClientEndpoint": {"Host": "service-ricxapp-kpimon-go-http.ricxapp", "HTTPPort": 8080, "RMRPort": 4560},
                  "SubscriptionDetails": [{"XappEventInstanceID": 4242, "EventTriggers": b["eventTrigger"],
                                           "ActionToBeSetupList": [{"ActionID": 1, "ActionType": "report",
                                                                    "ActionDefinition": b["actionDefinition"]}]}]}))
PY
    curl -sS -m 20 -H 'Content-Type: application/json' -X POST --data @"$e/enb-sub-request.json" "$SUBMGR_REST" \
        >"$e/enb-sub-rest-answer.json" 2>"$e/enb-sub-rest-answer.err"
    local rc=$?; cat "$e/enb-sub-rest-answer.json" "$e/enb-sub-rest-answer.err"; return "$rc"
}
check e2id_enb_kpm_subscription_accepted_by_submgr_rest enb_subscribe
check e2id_enb_received_ric_subscription_request node_saw enb rx RICsubscriptionRequest 30
check e2id_enb_answered_ric_subscription_response node_saw enb tx RICsubscriptionResponse 5
enb_unsubscribe() {
    local id; id=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["SubscriptionId"])' "$e/enb-sub-rest-answer.json") || return 1
    curl -sS -m 20 -X DELETE -w ' http %{http_code}\n' "$SUBMGR_REST/$id"
}
check e2id_enb_kpm_subscription_deleted enb_unsubscribe
record e2id_enb_subscription_delete_seen true "$(node_saw enb rx RICsubscriptionDeleteRequest 20 2>&1 | head -c 200)"

# 3. AC6 runtime
rc_restarts() { kc -n ricxapp get pods -o json | python3 -I -c '
import json, sys
p = [p for p in json.load(sys.stdin)["items"] if p["metadata"]["name"].startswith("ricxapp-rc-")]
print(sum(c.get("restartCount", 0) for c in p[0]["status"]["containerStatuses"]))'; }
rc_ctl() {      # one control through rc's gRPC to the en-gNB probe node (rc answers at once, sends asynchronously)
    local ep; ep=$(rc_endpoint) || return 1
    "$GRPCURL" -plaintext -max-time 10 -d "{
      \"e2NodeID\": \"$CTL_MEID\", \"plmnID\": \"00F110\", \"ranName\": \"$CTL_MEID\",
      \"RICE2APHeaderData\": { \"RanFuncId\": 3, \"RICRequestorID\": 1 },
      \"RICControlHeaderData\": { \"ControlStyle\": 3, \"ControlActionId\": 1,
         \"UEID\": { \"GnbUEID\": { \"amfUENGAPID\": 1, \"gNBCUUEF1APID\": [1], \"gNBCUCPUEE1APID\": [1],
            \"guami\": { \"pLMNIdentity\": \"00F110\", \"aMFRegionID\": \"128\", \"aMFSetID\": \"1\", \"aMFPointer\": \"0\" } } } },
      \"RICControlMessageData\": { \"RICControlCellTypeVal\": 1, \"TargetCellID\": \"7F00000110\" },
      \"RICControlAckReqVal\": 2 }" "$ep" rc.MsgComm/SendRICControlReqServiceGrpc
}
# the fixtures address whichever probe node registered (the en-gNB when e2mgr accepted it, else the eNB): they
# test rc's handling of the ACK, which does not depend on the node type
if [ "$(e2mgr_node_status "$ENGNB")" = CONNECTED ]; then CTL_MEID=$ENGNB; CTL_NODE=engnb; else CTL_MEID=$ENB; CTL_NODE=enb; fi
fact ac6ControlNode "$(json_str "$CTL_MEID")"
RC0=$(rc_restarts); fact rcRestartsBefore "${RC0:-null}"
POD=$(kc -n ricxapp get pods --no-headers | awk '/^ricxapp-rc-/ { print $1 }')
# rtmgr routes RIC_CONTROL_ACK (12041) to another xApp in this deployment (the M9 route-owner rows), so rc never
# receives an E2 node's ACK. The fixtures deliver an ACK without RICcontrolOutcome straight to rc's RMR port through
# the RMR injector (static seed route, rtmgr bypassed), for the instance id the probe node saw in rc's request.
# Within the 2 s timer the entry is still awaited and GetControlOutcome indexes an empty slice (fixture A: rc
# restarts); 3 s later the timer has deleted the entry and the ACK is dropped before the decode (fixture B: rc runs).
INJ=e2id-rmr-injector; INJ_CTL=38511
acks_encoded() {
    mkdir -p "$e/acks" && dk run --rm --user "$(id -u):$(id -g)" -v "$HARNESS_DIR/scripts/probes:/probes:ro" -v "$e/acks:/o" \
        "$IMG" python3 "$NODE_PY" acks --requestor 1 --func 3 --first 1 --last 60 --out /o && ls "$e/acks" | wc -l
}
check e2id_ac6_outcome_less_acks_encoded acks_encoded
injector_up() {
    local ip nip img
    ip=$(kc -n ricxapp get svc service-ricxapp-rc-rmr -o jsonpath='{.spec.clusterIP}') || return 1
    nip=$(kc get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}') || return 1
    img="127.0.0.1:80/stubqp:$(git -C "$HARNESS_DIR" rev-parse --short=12 HEAD:tools/rmr-peer)"
    mkdir -p "$e/injector"
    printf 'newrt|start\nmse|12041|-1|%s:4560\nnewrt|end\n' "$ip" >"$e/injector/seed.rt"
    dk rm -f "$INJ" >/dev/null 2>&1
    dk run -d --name "$INJ" --network host --user "$(id -u):$(id -g)" -v "$e/injector:/out" -e RMR_SEED_RT=/out/seed.rt \
        -e RMR_RTG_SVC=-1 -e "RMR_SRC_ID=$nip" "$img" python3 -I /app/rmr-injector.py --rmr-port 4591 --ctl-port "$INJ_CTL" \
        --out /out >/dev/null || return 1
    for _ in $(seq 60); do dk logs "$INJ" 2>&1 | grep -q READY && { echo "injector READY, 12041 -> $ip:4560 ($img)"; return 0; }; sleep 1; done
    dk logs "$INJ" 2>&1 | tail -n 5; return 1
}
check e2id_ac6_rmr_injector_up_12041_to_rc injector_up
requests() { grep -c '"dir": "rx", "msg": "RICcontrolRequest"' "$e/node-$CTL_NODE.jsonl" 2>/dev/null; }
last_instance() {
    grep '"dir": "rx", "msg": "RICcontrolRequest"' "$e/node-$CTL_NODE.jsonl" | tail -n 1 |
        python3 -I -c 'import json, sys; print(json.loads(sys.stdin.read())["ies"]["id-RICrequestID"]["ricInstanceID"])'
}
control_then_ack() {  # control_then_ack <delay-s before the ACK>: echo "<instance> <ack-wall-delay>"
    local n0 inst t0 deadline
    n0=$(requests); t0=$(date +%s.%N)
    rc_ctl >/dev/null || return 1
    deadline=$(($(date +%s) + 10))
    until [ "$(requests)" -gt "$n0" ]; do [ "$(date +%s)" -lt "$deadline" ] || { echo "no request at the node"; return 1; }; sleep 0.05; done
    inst=$(last_instance)
    sleep "$1"
    bash "$HARNESS_DIR/scripts/gates/send-rmr.sh" "$INJ_CTL" raw 12041 "$e/acks/ack-$inst.hex" >/dev/null || { echo "inject failed"; return 1; }
    echo "$inst $(python3 -I -c 'import sys,time; print("%.2f" % (time.time() - float(sys.argv[1])))' "$t0")"
}
fixture_b() {
    local r0 out; r0=$(rc_restarts)
    out=$(control_then_ack 3) || { echo "$out"; return 1; }
    sleep 15
    echo "instance, ACK sent at s after the gRPC call: $out; rc restarts before $r0, after $(rc_restarts)"
    [ "$(rc_restarts)" = "$r0" ]
}
check e2id_ac6_fixture_b_ack_after_timer_is_dropped_rc_alive fixture_b
fixture_a() {
    local r0 out deadline; r0=$(rc_restarts)
    out=$(control_then_ack 0) || { echo "$out"; return 1; }
    deadline=$(($(date +%s) + 60))
    while [ "$(rc_restarts)" -le "$r0" ] && [ "$(date +%s)" -lt "$deadline" ]; do sleep 2; done
    kc -n ricxapp logs "$POD" --previous >"$e/rc-log-fixture-a-previous.txt" 2>&1
    grep -m 3 -E "panic|index out of range" "$e/rc-log-fixture-a-previous.txt"
    echo "instance, ACK sent at s after the gRPC call: $out; rc restarts before $r0, after $(rc_restarts)"
    [ "$(rc_restarts)" -gt "$r0" ] && grep -q "index out of range" "$e/rc-log-fixture-a-previous.txt"
}
check e2id_ac6_fixture_a_ack_without_outcome_inside_timer_panics_rc fixture_a
record e2id_ac6_injector_tx_log true "$(tail -n 2 "$e/injector/tx.jsonl" 2>/dev/null | cut -c1-200 | tr '\n' ' ')"
dk rm -f "$INJ" >/dev/null 2>&1
fact rcRestartsAfter "$(rc_restarts)"
check e2id_post_panic_rtmgr_restarted rc_restart_rtmgr
check e2id_post_panic_rc_ready_on_its_route_reader rc_rmr_ready_after_rtmgr

nodes_stop() { dk stop -t 10 e2probe-engnb e2probe-enb; dk rm -f e2probe-engnb e2probe-enb; }
check e2id_probe_nodes_stopped nodes_stop
disconnected() {
    sleep 5; local a b; a=$(e2mgr_node_status "$ENGNB"); b=$(e2mgr_node_status "$ENB")
    echo "$ENGNB $a; $ENB $b"; [ "$a" != CONNECTED ] && [ "$b" = DISCONNECTED ]
}
check e2id_probe_nodebs_disconnected_after_graceful_close disconnected
check e2id_capture_stopped capture_stop e2id
wire() {
    tshark -r "$e/e2id.pcap" -o sctp.reassembly:TRUE -Y 'sctp.data_payload_proto_id' -T fields -e ip.src -e ip.dst \
        -e sctp.data_payload_proto_id -e e2ap.procedureCode -e sctp.data_e_bit >"$e/e2id-wire.tsv" 2>"$e/e2id-wire.err" || return 1
    python3 -I - "$e/e2id-wire.tsv" "$e/probe-node-ips.txt" <<'PY'
import sys, collections
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
nodes = {l.strip() for l in open(sys.argv[2]) if l.strip()}
by = collections.Counter((r[0], r[2], r[3] if len(r) > 3 else "") for r in rows)
for k, v in sorted(by.items()):
    print("src %s%s ppid %s procedureCode %s: %d" % (k[0], " (probe node)" if k[0] in nodes else "", k[1], k[2], v))
# AC11 direction: every DATA chunk a probe node sent carries PPID 70, and every frame that ends a message (E bit
# set; a large setup is fragmented over several chunks) decodes as E2AP with no -d override
mine = [r + [""] * (5 - len(r)) for r in rows if r[0] in nodes]
noppid = [r for r in mine if set(r[2].split(",")) != {"70"}]
ends = [r for r in mine if "1" in r[4].split(",") or "True" in r[4].split(",")]
undecoded = [r for r in ends if not r[3]]
print("probe-node frames %d (from %s): PPID other than 70 %d; message-final frames %d, not decoded as E2AP %d" % (
    len(mine), sorted(nodes), len(noppid), len(ends), len(undecoded)))
sys.exit(0 if mine and ends and not noppid and not undecoded else 1)
PY
}
check e2id_wire_every_chunk_ppid_and_e2ap_without_override wire
ric_watchdog_stop
gate_finish

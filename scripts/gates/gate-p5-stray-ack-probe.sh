#!/usr/bin/env bash
# Gate p5 (VM side, a one-time dev run): the stray-ack probe of the TS xApp. rtmgr gives every non-platform xApp
# a 12041/12042 route at subid -1, and the TS xApp registers no handler for them (nor a default one), so an
# unmatched ack may be freed twice. The probe sends such acks straight to the TS xApp's RMR Service and records
# whether the pod crashed. Run it on a freshly installed TS xApp registered with appmgr (gate i2 --part ts), before
# any stub QP exists. Expected in the TS log after a 30003: `[ERROR] send failed` (no 30000 route without a stub).
#
# Payloads are real E2AP PDUs from the R1 capture (tools/rmr-peer/fixtures). Variants:
#   single  one 12041, then one 30003 (the phase file's probe)
#   burst   three each of 12041 and 12042, interleaved with 30003
# After each variant it waits >= 10 s and records the pod's uid, restart count, lastState.terminated and the log
# (glibc's message, if any). crashed = any restart, termination or pod change. probe.json holds the result; the
# gate passes when the probe ran completely, whatever the result (substitution 2 is decided from `crashed`).
source "$(dirname "$0")/lib.sh"
gate_init p5
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/ts-lib.sh"
e="$EVIDENCE_DIR"
FIX="$RMR_PEER_DIR/fixtures"
SEND="$HARNESS_DIR/scripts/gates/send-rmr.sh"
record p5_args true "TS pin $TS_SHA; rmr-peer image $RMR_PEER_IMAGE; injector ctl port $INJ_CTL_PORT"

check p5_ts_ready_listening ts_ready
no_stub() { ! kc -n ricxapp get pods --no-headers | grep "ricxapp-$STUB_NAME-" && echo "no stub QP pod"; }
check p5_no_stub_qp_deployed no_stub
check p5_rmr_peer_image_built_self_tested rmr_peer_build
# the premise: registered with appmgr, the TS xApp holds 12041/12042 -1 rows in rtmgr's table
check p5_appmgr_xapp_list_saved xapp_list_save "$e/p5-appmgr-xapps.json"
check p5_ts_xapp_registered xapp_ensure_registered trafficxapp
check p5_route_dump rc_route_dump p5
ack_rows() { grep -E '^mse\|1204[12](,[^|]+)?\|-1\|' "$e/p5-routetable.txt"; }
check p5_ack_rows_recorded ack_rows
check p5_injector_started_static_route_to_ts injector_start "$e/injector"

ts_state() {   # one JSON line: pod name, uid, restarts, lastState.terminated of the TS container
    kc -n ricxapp get pods -o json | python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    if p["metadata"]["name"].startswith("ricxapp-trafficxapp-") and not p["metadata"].get("deletionTimestamp"):
        cs = (p["status"].get("containerStatuses") or [{}])[0]
        print(json.dumps({"pod": p["metadata"]["name"], "uid": p["metadata"]["uid"], "restarts": cs.get("restartCount"),
                          "ready": cs.get("ready"), "state": list(cs.get("state", {}).keys()),
                          "lastTerminated": cs.get("lastState", {}).get("terminated")}))'
}

run_variant() {
    local v="$1" before after pod; shift
    before=$(ts_state)
    : >"$e/$v-sent.jsonl"
    for m in "$@"; do
        case "$m" in
            12041) bash "$SEND" "$INJ_CTL_PORT" raw 12041 "$FIX/ric-control-ack.hex" ;;
            12042) bash "$SEND" "$INJ_CTL_PORT" raw 12042 "$FIX/ric-control-failure.hex" ;;
            30003) bash "$SEND" "$INJ_CTL_PORT" anomaly 1 ;;
        esac | python3 -I -c 'import json,sys; r=json.loads(sys.stdin.read() or "{}"); r["mtype"]=int(sys.argv[1]); print(json.dumps(r))' "$m" >>"$e/$v-sent.jsonl"
        sleep 1
    done
    sleep 12
    after=$(ts_state)
    pod=$(echo "$after" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["pod"])') || return 1
    kc -n ricxapp logs "$pod" >"$e/$v-ts.log" 2>&1
    kc -n ricxapp logs --previous "$pod" >"$e/$v-ts-previous.log" 2>&1 || true
    python3 -I - "$v" "$before" "$after" "$e" <<'PY'
import json, os, sys
v, b, a, e = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3]), sys.argv[4]
sent = [json.loads(l) for l in open(os.path.join(e, v + "-sent.jsonl")) if l.strip()]
logs = open(os.path.join(e, v + "-ts.log"), errors="replace").read() + open(os.path.join(e, v + "-ts-previous.log"), errors="replace").read()
glibc = [l for l in logs.splitlines() if any(k in l for k in ("double free", "free():", "corrupted", "malloc", "Aborted", "Segmentation"))]
crashed = a["uid"] != b["uid"] or a["restarts"] != b["restarts"] or a["lastTerminated"] is not None or a["state"] != ["running"]
rec = {"variant": v, "sent": sent, "allSent": all(s.get("ok") for s in sent), "before": b, "after": a, "glibc": glibc, "crashed": crashed}
json.dump(rec, open(os.path.join(e, v + ".json"), "w"), indent=1)
print(json.dumps(rec))
sys.exit(0 if rec["allSent"] else 1)
PY
}
check p5_variant_single_12041_then_30003 run_variant single 12041 30003
check p5_variant_burst_12041_12042_interleaved_30003 run_variant burst 12041 30003 12042 30003 12041 30003 12042 30003 12041 30003 12042 30003
check p5_injector_stopped injector_stop "$e/injector"
probe() {
    python3 -I - "$e" "$(svc_ip ricxapp service-ricxapp-trafficxapp-rmr):4560" "$TS_SHA" <<'PY'
import json, os, sys
e, ep, sha = sys.argv[1:]
vs = [json.load(open(os.path.join(e, v + ".json"))) for v in ("single", "burst") if os.path.exists(os.path.join(e, v + ".json"))]
rows = [l.strip() for l in open(os.path.join(e, "p5-routetable.txt")) if l.startswith(("mse|12041", "mse|12042")) and "|-1|" in l]
apps = json.load(open(os.path.join(e, "p5-appmgr-xapps.json")))
out = {"endpoint": ep, "endpointKind": "TS xApp RMR Service ClusterIP (static seed route in the injector)", "tsSha": sha,
       "ackRowsMinusOne": rows, "tsHoldsAckRows": any("trafficxapp" in r for r in rows),
       "appmgrXapps": sorted(a["name"] for a in apps), "variants": vs, "crashed": any(v["crashed"] for v in vs)}
json.dump(out, open(os.path.join(e, "probe.json"), "w"), indent=1)
print(json.dumps({"crashed": out["crashed"], "tsHoldsAckRows": out["tsHoldsAckRows"], "variants": [(v["variant"], v["crashed"]) for v in vs]}))
sys.exit(0 if len(vs) == 2 else 1)
PY
}
check p5_probe_json_written probe
fact probe "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({"crashed": d["crashed"], "endpoint": d["endpoint"]}))' "$e/probe.json" 2>/dev/null || echo null)"
gate_finish

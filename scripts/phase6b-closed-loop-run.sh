#!/bin/bash
# Phase 6b Stage D (M-RC4) — TS-driven mock closed loop, re-runnable.
#
#   ensure injector pod -> clean (pkill ns-3 + clear RNIB) -> start ns-3 (5 gNBs,
#   wait 5 CONNECTED) -> restart TS (build_cell_mapping vs populated RNIB) ->
#   start tshark(sctp) -> inject >=2 mock TS_QOE_PREDICTION (30002) -> grep TS +
#   ns-3 logs + pcap -> print PASS/FAIL.
#
# The trigger is the TS xApp's own gRPC control emit (send_grpc_control_request),
# fired by the injected prediction — NO grpcurl in the loop (M-RC4 provenance:
# TS pod log line + absence of grpcurl; the wire bytes alone cannot prove origin).
#
# Mirrors phase6b-verify-multinode-recv.sh (setsid/tshark/wait-loop/results).
# Env: SIMTIME (default 100), PREDICTIONS_JSON (>=2 per-UE objects), REBUILD_INJECTOR=1.
set -u
NS3=/home/uc/ns-O-RAN-installation/ns3-mmwave-oran
SCRIPTS=/home/uc/ns-O-RAN-installation/scripts
NS=ricxapp
INJ_POD=phase6b-injector
INJ_IMG=phase6b-injector:latest
TS_RMR_EP=service-ricxapp-trafficxapp-rmr.ricxapp:4560
SIMTIME=${SIMTIME:-100}
# Default: 2 UEs that BOTH start on cell 2, sent to DISTINCT owning nodes — imsi 1 -> cell 4
# (node ...04), imsi 7 -> cell 5 (node ...05). Picked from the live imsi->serving-cell map
# under NoAuto (cell 2 = {1,7,9}, cell 4 = {5,11}, cell 5 = {2,4,6,8,10}, cell 3 = {12}); a
# UE must be sent to a cell it is NOT already on, else PerformHandover is a no-op (e.g. imsi 2
# is already on cell 5). Serving key = the UE's real serving cell key (16B8CE0202 = cell 2);
# it only feeds the threshold compare. Re-derive UEs/targets if the topology changes.
#
# KEY CASE: the CURRENTLY-DEPLOYED TS image (pre-D0-rebuild) populates cell_map with
# UPPERCASE keys 16B8CE0N0N — because the served requestPart is uppercase and the old
# toupper-prefix grep matches it. A D0 rebuild with the committed lowercase case-fix
# would make the keys LOWERCASE (16b8ce0N0N); override PREDICTIONS_JSON accordingly.
PREDICTIONS_JSON=${PREDICTIONS_JSON:-'[{"1":{"16B8CE0202":[1,1],"16B8CE0404":[9000,9000]}},{"7":{"16B8CE0202":[1,1],"16B8CE0505":[9000,9000]}}]'}

ts_pod()    { kubectl -n "$NS" get pod -l app=ricxapp-trafficxapp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null; }
e2mgr_pod() { kubectl -n ricplt get pod -o name 2>/dev/null | grep e2mgr | head -1; }

# ---------------------------------------------------------------- injector image+pod
ensure_injector() {
  if [ "${REBUILD_INJECTOR:-0}" = 1 ]; then
    docker rmi -f "$INJ_IMG" 2>/dev/null || true
    # the build-gate below checks containerd (k8s.io), not dockerd — drop it there too,
    # else the stale imported image is reused and the rebuild silently no-ops.
    sudo ctr -n k8s.io images rm "$INJ_IMG" 2>/dev/null || true
    kubectl -n "$NS" delete pod "$INJ_POD" --ignore-not-found >/dev/null 2>&1 || true
  fi
  if ! sudo ctr -n k8s.io images ls 2>/dev/null | grep -q "$INJ_IMG"; then
    echo "[injector] building image (vendoring librmr from TS pod)..."
    local ctx=/tmp/phase6b-injector-ctx
    rm -rf "$ctx"; mkdir -p "$ctx"
    local tsp; tsp=$(ts_pod)
    kubectl -n "$NS" exec "$tsp" -- tar cf - -C /usr/local/lib librmr_si.so.4.8.1 | tar xf - -C "$ctx"
    cp "$SCRIPTS/phase6b-injector.Dockerfile" "$ctx/Dockerfile"
    docker build -t "$INJ_IMG" "$ctx" || { echo "[injector] build FAILED"; return 1; }
    docker save "$INJ_IMG" -o "$ctx/img.tar"
    sudo ctr -n k8s.io image import "$ctx/img.tar" || { echo "[injector] ctr import FAILED"; return 1; }
  fi
  if ! kubectl -n "$NS" get pod "$INJ_POD" >/dev/null 2>&1; then
    echo "[injector] starting pod $INJ_POD..."
    kubectl -n "$NS" run "$INJ_POD" --image="$INJ_IMG" --image-pull-policy=Never \
      --restart=Never --command -- sleep 7200
  fi
  kubectl -n "$NS" wait --for=condition=Ready pod/"$INJ_POD" --timeout=120s || return 1
  kubectl -n "$NS" cp "$SCRIPTS/phase6b-mock-qp-inject.py" "$INJ_POD:/opt/inject/inject.py"
  echo "[injector] ready; inject.py copied in."
}

# ---------------------------------------------------------------- clean + ns-3 (5 gNBs)
clean() {
  cd "$NS3" || exit 1
  sudo pkill -9 -f scenario-zero 2>/dev/null || true
  sleep 1
  kubectl exec -n ricplt "$(e2mgr_pod)" -- curl -s -X PUT http://localhost:3800/v1/nodeb/shutdown >/dev/null 2>&1 || true
}

start_ns3_wait5() {
  E2TERM_IP=$(kubectl -n ricplt get pod -l app=ricplt-e2term-alpha -o jsonpath='{.items[0].status.podIP}')
  TS=$(date +%s)
  CAP=/home/uc/captures/phase6b-closedloop-$TS.pcapng
  LOG=/home/uc/captures/phase6b-closedloop-ns3-$TS.log
  echo "E2TERM_IP=$E2TERM_IP"; echo "CAP=$CAP"; echo "LOG=$LOG"
  setsid sudo tshark -i any -f 'sctp' -w "$CAP" </dev/null >/tmp/phase6b-cl-tshark-$TS.out 2>&1 &
  sleep 2
  setsid env NS_LOG="RicControlMessage=level_all:MmWaveEnbNetDevice=level_info:LteEnbRrc=level_info" \
    ./ns3 run \
    "scratch/scenario-zero --e2TermIp=$E2TERM_IP --simTime=$SIMTIME --handoverMode=NoAuto --reducedPmValues=1 --e2du=1 --e2cuUp=0 --e2cuCp=0 --enableE2FileLogging=false" \
    </dev/null >"$LOG" 2>&1 &
  echo "waiting for 5 E2 nodes CONNECTED (up to ~180s)..."
  local emp; emp=$(e2mgr_pod)
  for i in $(seq 1 36); do
    N=$(kubectl exec -n ricplt "$emp" -- curl -s http://localhost:3800/v1/nodeb/states 2>/dev/null \
        | grep -o '"connectionStatus":"CONNECTED"' | wc -l)
    if [ "$N" -ge 5 ]; then echo "$N nodes CONNECTED after ~$((i*5))s"; return 0; fi
    [ "$N" -ge 1 ] && echo "  ...$N CONNECTED (~$((i*5))s)"
    sleep 5
  done
  echo "TIMEOUT: <5 nodes CONNECTED"; tail -20 "$LOG"; return 2
}

restart_ts() {
  echo "[TS] restarting pod so build_cell_mapping runs against populated RNIB..."
  # delete by NAME and block until gone, so the subsequent Ready-wait can't be
  # satisfied by the still-Ready *terminating* pod (it would return instantly).
  local old; old=$(ts_pod)
  [ -n "$old" ] && kubectl -n "$NS" delete pod "$old" --wait=true >/dev/null 2>&1
  kubectl -n "$NS" wait --for=condition=Ready pod -l app=ricxapp-trafficxapp --timeout=120s \
    || echo "[TS] WARNING: TS not Ready in 120s; continuing"
  sleep 5   # let build_cell_mapping + gRPC channel settle
  echo "[TS] pod=$(ts_pod)"
}

# The rc xApp restarts intermittently; a TS->rc gRPC during an rc restart fails with
# UNAVAILABLE (error_code=14, "Socket closed"/"Connect Failed") and the control never
# reaches ns-3. Wait for rc Ready + a settle window before injecting.
wait_rc() {
  echo "[rc] waiting for rc xApp Ready (gRPC control endpoint)..."
  kubectl -n "$NS" wait --for=condition=Ready pod -l app=ricxapp-rc --timeout=120s || {
    echo "[rc] WARNING: rc not Ready in 120s; injecting anyway"; }
  sleep 8   # let rc's gRPC server + RMR finish coming up after Ready flips
}

ho_count() { local n; n=$(grep -c "PerformHandover ----- handover from" "$LOG" 2>/dev/null); echo "${n:-0}"; }

# Inject SEQUENTIALLY, one UE at a time, gating on each handover actually landing.
# The LTE master RRC serializes EN-DC handovers (a concurrent 2nd request is rejected:
# "handover not triggered because the UE is already performing HO"). So we fire UE N+1
# only after UE N's handover appears in the ns-3 log, and re-fire a UE whose control
# raced the in-flight HO (bounded). Per-UE objects are split out of PREDICTIONS_JSON.
inject() {
  echo "===== injecting predictions (sequential, handover-gated) ====="
  mapfile -t PREDS < <(echo "$PREDICTIONS_JSON" | python3 -c 'import sys,json
for p in json.load(sys.stdin): print(json.dumps(p))')
  echo "[inject] ${#PREDS[@]} UE predictions"
  local idx=0 p
  for p in "${PREDS[@]}"; do
    idx=$((idx+1))
    local before; before=$(ho_count)
    local landed=0 try
    for try in 1 2 3 4 5; do
      echo "[inject] UE $idx try $try: $p"
      # gating is on ho_count (the real effect), not the exec exit — the pipe to grep
      # also drops the injector's exit status by design; a send FAIL shows as the grepped
      # "FAIL" line and triggers the re-fire below.
      kubectl -n "$NS" exec "$INJ_POD" -- python3 /opt/inject/inject.py \
        --ts-rmr-ep "$TS_RMR_EP" --predictions-json "[$p]" 2>&1 | grep -E "msg [0-9]|done|FAIL"
      # bounded wait for THIS UE's handover to execute (sim advances slowly early)
      local w
      for w in $(seq 1 12); do
        sleep 3
        [ "$(ho_count)" -gt "$before" ] && { landed=1; break; }
      done
      [ "$landed" = 1 ] && { echo "[inject] UE $idx handover landed"; break; }
      echo "[inject] UE $idx not landed yet (master RRC busy?) — re-firing"
    done
    [ "$landed" = 1 ] || echo "[inject] WARNING: UE $idx handover never landed after retries"
    sleep 4   # let the HO fully complete before releasing the master RRC to the next UE
  done
}

results() {
  sleep 8
  local tsp; tsp=$(ts_pod)
  echo "=================== RESULTS ==================="
  echo "--- TS pod log (callback + routed control / drops) ---"
  kubectl -n "$NS" logs "$tsp" 2>/dev/null | grep -nE "Prediction Callback|in ts xapp grpc message|Control Request succeeded|Cannot find RAN name|serving cell" | tail -40
  local ts_emits; ts_emits=$(kubectl -n "$NS" logs "$tsp" 2>/dev/null | grep -c "in ts xapp grpc message content")
  local ts_drops; ts_drops=$(kubectl -n "$NS" logs "$tsp" 2>/dev/null | grep -c "Cannot find RAN name")
  echo "--- ns-3 log (decode + handover + ACK) ---"
  grep -nE "RIC Control Request: |targetCellId=|RC forced handover|handover from|not a valid mmWave|Generated RIC Control Acknowledge" "$LOG" | tail -40
  local ho; ho=$(grep -oE "handover from [0-9]+ to [0-9]+" "$LOG" | sort -u | wc -l)
  local imsis; imsis=$(grep -oE "imsi=[0-9]+" "$LOG" | sort -u | wc -l)
  local acks; acks=$(grep -c "Generated RIC Control Acknowledge" "$LOG")
  echo "--- pcap Control Request/Acknowledge (byte sigs; VM tshark lacks E2AP dissector) ---"
  sleep 2; sudo pkill -f "tshark -i any -f sctp" 2>/dev/null || true; sleep 1
  sudo chmod a+r "$CAP" 2>/dev/null
  bash /home/uc/ns-O-RAN-installation/scripts/l-release-validation/assert-pcap.sh \
    "$CAP" control-request control-ack 2>/dev/null || true
  echo "=============================================="
  echo "TS gRPC control emits (no grpcurl): $ts_emits   TS cell_map drops: $ts_drops"
  echo "distinct ns-3 handovers: $ho   distinct IMSIs: $imsis   ns-3 ACKs: $acks"
  if [ "$ts_emits" -ge 2 ] && [ "$ho" -ge 2 ] && [ "$imsis" -ge 2 ] && [ "$acks" -ge 2 ]; then
    echo "RESULT: PASS (M-RC4: >=2 TS-emitted controls -> >=2 distinct handovers / >=2 IMSIs)"
  else
    echo "RESULT: FAIL (see logs above; check cell_map keys / UE topology / threshold)"
  fi
  echo "LOG=$LOG  CAP=$CAP"
}

ensure_injector || { echo "ABORT: injector not ready"; exit 1; }
clean
start_ns3_wait5 || exit 2
restart_ts
wait_rc
inject
results

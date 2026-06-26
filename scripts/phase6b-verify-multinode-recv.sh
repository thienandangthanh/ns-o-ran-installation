#!/bin/bash
# Phase 6b — verify the per-instance client_fd fix: every embedded e2sim agent
# now reads its OWN SCTP socket. Sends one RIC Control (funcId 3) to EACH of the
# 5 E2 nodes scenario-zero registers (gnb_734_373_16b8ce0{1..5}) and counts how
# many nodes actually RECEIVE + ACK it.
#
#   Before the fix (global client_fd): only the last-connecting agent's socket is
#   ever read -> ~1 node receives, the rest are deaf.
#   After the fix (per-instance member): all 5 receive + ACK.
#
# Re-runnable (run a few times to confirm determinism). Leaves ns-3 running;
# `sudo pkill -9 -f scenario-zero` to stop.
set -u
NS3=/home/uc/ns-O-RAN-installation/ns3-mmwave-oran
PROTO_DIR=/home/uc/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/xApps/ts/ext/protobuf
SIMTIME=${SIMTIME:-100}

cd "$NS3" || exit 1
sudo pkill -9 -f scenario-zero 2>/dev/null || true
sleep 1

E2MGR_POD=$(kubectl get pod -n ricplt -o name | grep e2mgr)
kubectl exec -n ricplt "$E2MGR_POD" -- curl -s -X PUT http://localhost:3800/v1/nodeb/shutdown >/dev/null 2>&1 || true

E2TERM_IP=$(kubectl -n ricplt get pod -l app=ricplt-e2term-alpha -o jsonpath='{.items[0].status.podIP}')
RC_IP=$(kubectl -n ricxapp get pod -l app=ricxapp-rc -o jsonpath='{.items[0].status.podIP}')
TS=$(date +%s)
CAP=/home/uc/captures/phase6b-multinode-$TS.pcapng
LOG=/home/uc/captures/phase6b-multinode-ns3-$TS.log
echo "E2TERM_IP=$E2TERM_IP RC_IP=$RC_IP"
echo "CAP=$CAP"
echo "LOG=$LOG"

setsid sudo tshark -i any -f 'sctp' -w "$CAP" </dev/null >/tmp/phase6b-mn-tshark-$TS.out 2>&1 &
sleep 2
setsid env NS_LOG="RicControlMessage=level_all:MmWaveEnbNetDevice=level_info:LteEnbRrc=level_info" \
  ./ns3 run \
  "scratch/scenario-zero --e2TermIp=$E2TERM_IP --simTime=$SIMTIME --handoverMode=NoAuto --reducedPmValues=1 --e2du=1 --e2cuUp=0 --e2cuCp=0 --enableE2FileLogging=false" \
  </dev/null >"$LOG" 2>&1 &

# Wait until all 5 E2 nodes are CONNECTED (or as many as show up before timeout).
echo "waiting for E2 nodes to register (up to ~180s)..."
RANNAMES=""
for i in $(seq 1 36); do
  ST=$(kubectl exec -n ricplt "$E2MGR_POD" -- curl -s http://localhost:3800/v1/nodeb/states 2>/dev/null)
  N=$(echo "$ST" | grep -o '"connectionStatus":"CONNECTED"' | wc -l)
  if [ "$N" -ge 5 ]; then
    RANNAMES=$(echo "$ST" | grep -o '"inventoryName":"[^"]*"' | cut -d'"' -f4 | sort -u)
    echo "$N nodes CONNECTED after ~$((i*5))s"; break
  fi
  [ "$N" -ge 1 ] && echo "  ...$N CONNECTED so far (~$((i*5))s)"
  sleep 5
done
if [ -z "$RANNAMES" ]; then
  echo "TIMEOUT waiting for 5 nodes; got:"; kubectl exec -n ricplt "$E2MGR_POD" -- curl -s http://localhost:3800/v1/nodeb/states 2>/dev/null | grep -o '"inventoryName":"[^"]*"'
  tail -20 "$LOG"; exit 2
fi
echo "ranNames:"; echo "$RANNAMES" | sed 's/^/  /'
sleep 3

# Fan one control to each node. Distinct imsi per node; valid mmWave target cell
# (2..5). Node owning a given cell N has ranName suffix 16b8ce0N -> map to imsi N.
send_ctrl () {  # $1=ranName  $2=imsi  $3=targetCellHex(110X)
  echo "----- control -> $1  (imsi=$2 target=$3) -----"
  grpcurl -plaintext -import-path "$PROTO_DIR" -proto rc.proto -d "{
    \"e2NodeID\": \"$1\", \"plmnID\": \"373437\", \"ranName\": \"$1\",
    \"RICE2APHeaderData\": { \"RanFuncId\": 3, \"RICRequestorID\": 1 },
    \"RICControlHeaderData\": { \"ControlStyle\": 3, \"ControlActionId\": 1,
       \"UEID\": { \"GnbUEID\": { \"amfUENGAPID\": $2, \"gNBCUUEF1APID\": [$2], \"gNBCUCPUEE1APID\": [$2],
          \"guami\": { \"pLMNIdentity\": \"373437\", \"aMFRegionID\": \"128\", \"aMFSetID\": \"1\", \"aMFPointer\": \"0\" } } } },
    \"RICControlMessageData\": { \"RICControlCellTypeVal\": 1, \"TargetCellID\": \"$3\" },
    \"RICControlAckReqVal\": 2
  }" "$RC_IP:7777" rc.MsgComm/SendRICControlReqServiceGrpc 2>&1 | grep -iE "Response|Error|status" | head -3
  sleep 4
}

i=1
for RN in $RANNAMES; do
  # target a valid mmWave cell that differs from this node's own cell
  T=$(( (i % 4) + 2 ))     # -> 3,4,5,2,3 for i=1..5
  send_ctrl "$RN" "$i" "110$T"
  i=$((i+1))
done

sleep 6
echo "=================== RESULTS ==================="
printf "controls received by e2sim ('RIC control procedure'): "; grep -c "Received a message of RIC control procedure" "$LOG"
printf "RC requests decoded ('carries RAN function id 3'):     "; grep -c "carries RAN function id 3" "$LOG"
printf "ACKs generated ('Generated RIC Control Acknowledge'):  "; grep -c "Generated RIC Control Acknowledge" "$LOG"
echo "--- per-control decode lines (targetCellId / imsi / node ctx) ---"
grep -nE "RIC Control Request: |targetCellId=|RC forced handover|handover from|not a valid mmWave|Generated RIC Control Acknowledge" "$LOG" | tail -50
echo "===== ns-3 still running; LOG=$LOG CAP=$CAP ====="

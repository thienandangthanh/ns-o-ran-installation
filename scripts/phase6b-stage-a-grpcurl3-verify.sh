#!/bin/bash
# Phase 6b Stage A: verify ns-3 dispatches a RIC Control under funcId 3 (the OSC
# TS xApp's hardcoded RAN-Function-ID) — the same path Phase 4/5 drove under 300.
# Regression-proves the funcId-3 registration BEFORE deploying the TS xApp.
#
#   clean RNIB -> tshark(sctp) -> ns-3 scenario-zero (pod-IP, NoAuto)
#   -> wait gNB CONNECTED -> grpcurl rc:7777 (RanFuncId=3) -> grep handover+ACK
#
# Env overrides: FUNCID (default 3), TARGET (default 1105 -> cell 5),
#                RANNAME (default the scenario-zero gNB inventory name).
set -u
NS3=/home/uc/ns-O-RAN-installation/ns3-mmwave-oran
PROTO_DIR=/home/uc/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/xApps/ts/ext/protobuf
RANNAME=${RANNAME:-gnb_734_373_16b8cef1}
FUNCID=${FUNCID:-3}
TARGET=${TARGET:-1105}

cd "$NS3" || exit 1
sudo pkill -9 -f scenario-zero 2>/dev/null || true
sleep 1

E2MGR_POD=$(kubectl get pod -n ricplt -o name | grep e2mgr)
kubectl exec -n ricplt "$E2MGR_POD" -- curl -s -X PUT http://localhost:3800/v1/nodeb/shutdown >/dev/null 2>&1 || true

E2TERM_IP=$(kubectl -n ricplt get pod -l app=ricplt-e2term-alpha -o jsonpath='{.items[0].status.podIP}')
RC_IP=$(kubectl -n ricxapp get pod -l app=ricxapp-rc -o jsonpath='{.items[0].status.podIP}')
TS=$(date +%s)
CAP=/home/uc/captures/phase6b-stageA-$TS.pcapng
LOG=/home/uc/captures/phase6b-stageA-ns3-$TS.log
echo "E2TERM_IP=$E2TERM_IP RC_IP=$RC_IP FUNCID=$FUNCID TARGET=$TARGET"
echo "CAP=$CAP"
echo "LOG=$LOG"

setsid sudo tshark -i any -f 'sctp' -w "$CAP" </dev/null >/tmp/phase6b-tshark-$TS.out 2>&1 &
sleep 2
setsid env NS_LOG="RicControlMessage=level_all:MmWaveEnbNetDevice=level_info:LteEnbRrc=level_info" \
  ./ns3 run \
  "scratch/scenario-zero --e2TermIp=$E2TERM_IP --simTime=100 --handoverMode=NoAuto --reducedPmValues=1 --e2du=1 --e2cuUp=0 --e2cuCp=0 --enableE2FileLogging=false" \
  </dev/null >"$LOG" 2>&1 &

echo "waiting for gNB CONNECTED (up to ~150s)..."
CONNECTED=0
for i in $(seq 1 30); do
  ST=$(kubectl exec -n ricplt "$E2MGR_POD" -- curl -s http://localhost:3800/v1/nodeb/states 2>/dev/null)
  if echo "$ST" | grep -q '"connectionStatus":"CONNECTED"'; then
    echo "gNB CONNECTED after ~$((i*5))s: $ST"
    CONNECTED=1; break
  fi
  sleep 5
done
[ "$CONNECTED" = 0 ] && { echo "TIMEOUT: gNB never CONNECTED"; tail -20 "$LOG"; exit 2; }

sleep 3
echo "===== grpcurl SendRICControlReqServiceGrpc (RanFuncId=$FUNCID, TargetCellID=$TARGET) ====="
grpcurl -plaintext -import-path "$PROTO_DIR" -proto rc.proto -d "{
  \"e2NodeID\": \"$RANNAME\",
  \"plmnID\": \"373437\",
  \"ranName\": \"$RANNAME\",
  \"RICE2APHeaderData\": { \"RanFuncId\": $FUNCID, \"RICRequestorID\": 1 },
  \"RICControlHeaderData\": { \"ControlStyle\": 3, \"ControlActionId\": 1,
     \"UEID\": { \"GnbUEID\": { \"amfUENGAPID\": 1, \"gNBCUUEF1APID\": [1], \"gNBCUCPUEE1APID\": [1],
        \"guami\": { \"pLMNIdentity\": \"373437\", \"aMFRegionID\": \"128\", \"aMFSetID\": \"1\", \"aMFPointer\": \"0\" } } } },
  \"RICControlMessageData\": { \"RICControlCellTypeVal\": 1, \"TargetCellID\": \"$TARGET\" },
  \"RICControlAckReqVal\": 2
}" "$RC_IP:7777" rc.MsgComm/SendRICControlReqServiceGrpc

sleep 6
echo "===== ns-3 log: RC decode + handover + ACK ====="
grep -nE "RIC Control Request|ranFunctionId|imsi=|targetCellId|external HO control|handover from|RIC Control Acknowledge|not a valid mmWave" "$LOG" | tail -40
echo "===== done; ns-3 still running (simTime 150). pkill -9 -f scenario-zero to stop. ====="

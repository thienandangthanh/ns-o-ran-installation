#!/bin/bash
# Phase 6b: clean RNIB + start ns-3 scenario-zero (pod-IP connect, NoAuto),
# wait for gNB CONNECTED, dump the E2MGR nodeb detail (served-cell /
# e2nodeComponentRequestPart — the source TS NodebHandler turns into cell_map
# NRCGI keys), and leave ns-3 running for Stage C/D/E.
#
# Env: SIMTIME (default 100, the scenario-zero max).
set -u
NS3=/home/uc/ns-O-RAN-installation/ns3-mmwave-oran
SIMTIME=${SIMTIME:-100}
cd "$NS3" || exit 1
sudo pkill -9 -f scenario-zero 2>/dev/null || true
sleep 1

E2MGR_POD=$(kubectl get pod -n ricplt -o name | grep e2mgr)
kubectl exec -n ricplt "$E2MGR_POD" -- curl -s -X PUT http://localhost:3800/v1/nodeb/shutdown >/dev/null 2>&1 || true

E2TERM_IP=$(kubectl -n ricplt get pod -l app=ricplt-e2term-alpha -o jsonpath='{.items[0].status.podIP}')
TS=$(date +%s)
LOG=/home/uc/captures/phase6b-ns3-$TS.log
echo "E2TERM_IP=$E2TERM_IP"
echo "LOG=$LOG"
echo "$LOG" > /tmp/phase6b-ns3-log.path

setsid env NS_LOG="RicControlMessage=level_all:MmWaveEnbNetDevice=level_info:LteEnbRrc=level_info" \
  ./ns3 run \
  "scratch/scenario-zero --e2TermIp=$E2TERM_IP --simTime=$SIMTIME --handoverMode=NoAuto --reducedPmValues=1 --e2du=1 --e2cuUp=0 --e2cuCp=0 --enableE2FileLogging=false" \
  </dev/null >"$LOG" 2>&1 &

echo "waiting for gNB CONNECTED (up to ~150s)..."
RAN=""
for i in $(seq 1 30); do
  ST=$(kubectl exec -n ricplt "$E2MGR_POD" -- curl -s http://localhost:3800/v1/nodeb/states 2>/dev/null)
  if echo "$ST" | grep -q '"connectionStatus":"CONNECTED"'; then
    RAN=$(echo "$ST" | grep -o '"inventoryName":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "gNB CONNECTED after ~$((i*5))s; ranName=$RAN"; break
  fi
  sleep 5
done
[ -z "$RAN" ] && { echo "TIMEOUT: gNB not CONNECTED"; tail -15 "$LOG"; exit 2; }
echo "$RAN" > /tmp/phase6b-ranname.txt

echo "===== E2MGR /v1/nodeb/$RAN (served-cell / e2nodeComponentRequestPart) ====="
kubectl exec -n ricplt "$E2MGR_POD" -- curl -s "http://localhost:3800/v1/nodeb/$RAN" 2>/dev/null | head -c 5000
echo ""
echo "===== ns-3 running; LOG=$LOG ; ranName=$RAN ====="

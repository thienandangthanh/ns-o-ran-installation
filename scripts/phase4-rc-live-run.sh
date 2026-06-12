#!/bin/bash
# Phase 4 (M-RC1) live run: clean → capture → ns-3 scenario-zero (detached).
# Reproduces the Phase-0 recipe (pod-IP connect, simTime<=100). Backgrounds
# tshark + ns-3 via setsid so the launching shell returns immediately.
set -u
cd /home/uc/ns-O-RAN-installation/ns3-mmwave-oran

sudo pkill -9 -f scenario-zero 2>/dev/null || true
sleep 1
E2MGR_POD=$(kubectl get pod -n ricplt -o name | grep e2mgr)
kubectl exec -n ricplt "$E2MGR_POD" -- curl -s -X PUT http://localhost:3800/v1/nodeb/shutdown >/dev/null 2>&1 || true

TS=$(date +%s)
CAP=/home/uc/captures/phase4-rc-$TS.pcapng
LOG=/home/uc/captures/phase4-ns3-$TS.log
{ echo "CAP=$CAP"; echo "LOG=$LOG"; echo "TS=$TS"; } > /tmp/phase4-paths.env

setsid sudo tshark -i any -f 'sctp' -w "$CAP" </dev/null >/tmp/phase4-tshark-$TS.out 2>&1 &
sleep 2
setsid env NS_LOG="RicControlMessage=level_all" ./ns3 run \
  "scratch/scenario-zero --e2TermIp=10.244.0.13 --simTime=100 --reducedPmValues=1 --e2du=1 --e2cuUp=0 --e2cuCp=0 --enableE2FileLogging=false" \
  </dev/null >"$LOG" 2>&1 &

sleep 3
echo "launched TS=$TS"
echo "CAP=$CAP"
echo "LOG=$LOG"
pgrep -af 'tshark.*phase4' | head -1

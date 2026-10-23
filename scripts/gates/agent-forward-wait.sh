#!/usr/bin/env bash
# agent-forward-wait.sh <nodeId> <count> <timeout-s>: wait until the agent of E2 node <nodeId> has logged <count>
# controls forwarded to ns-3 ("-> ns-3 ctlId"); exit 0 then, 1 at the timeout. The pacer's stop trigger runs it
# to hold endAck until the agent holds the control as pending. A readiness precondition, never a judge.
set -uo pipefail
node="$1" want="$2" timeout_s="$3"
if docker info >/dev/null 2>&1; then dk=(docker); else dk=(sudo -n docker); fi
c=$("${dk[@]}" ps -q --filter label=ns3e2.agent=1 --filter "label=ns3e2.nodeId=$node" | head -n 1)
[ -n "$c" ] || { echo "no agent container for node $node"; exit 1; }
deadline=$(($(date +%s%N) / 1000000 + timeout_s * 1000))
while :; do
    n=$("${dk[@]}" logs "$c" 2>&1 | grep -c -- '-> ns-3 ctlId')
    [ "${n:-0}" -ge "$want" ] && { echo "node $node forwarded $n control(s) to ns-3"; exit 0; }
    [ $(($(date +%s%N) / 1000000)) -lt "$deadline" ] || { echo "node $node forwarded ${n:-0} of $want within ${timeout_s} s"; exit 1; }
    sleep 0.1
done

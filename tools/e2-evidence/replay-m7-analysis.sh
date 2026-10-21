#!/usr/bin/env bash
# replay-m7-analysis.sh <m7-evidence-dir> [work-dir]: re-run gate M7's post-capture wire and ns-3 trace checks offline
# on saved evidence (m7.pcap, ns3run/e2-ipc-trace-*.jsonl, agents.json, node-ips.json, checks/*.out).
# It sources the same m7-wire-trace-checks.sh as the gate, so the verdicts are the gate's own. The pcap is decoded
# afresh with tshark into <work-dir> (default: a temp dir); the evidence dir is never written.
# Exit 0 = every check passed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
e="${1:?usage: replay-m7-analysis.sh <m7-evidence-dir> [work-dir]}"
e="$(cd "$e" && pwd)"
W="${2:-$(mktemp -d)}"; mkdir -p "$W"
E2EV="$here"
F="$W/m7-facts.json"; Q="$E2EV/e2-facts-query.py"; RUN="$e/ns3run"
command -v tshark >/dev/null || { echo "tshark is required to decode $e/m7.pcap"; exit 2; }

# Inputs the gate keeps in variables: T_del and the ns-3 start come from the saved check output.
T_DEL=$(sed -n 's/^T_del \([0-9.]*\):.*/\1/p' "$e"/checks/m7_e2term_pod_deleted*.out | head -n 1)
NS3_START_EPOCH=$(sed -n 's/^ns-3 started pid\/pgid [0-9]* at \([0-9.]*\):.*/\1/p' "$e"/checks/m7_ns3_started*.out | head -n 1)
SERVICE_IP=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["agents"][0]["e2Term"].split(":")[0])' "$e/agents.json")
IDS=$(python3 -I -c 'import json,sys; print(",".join(str(n) for n in sorted(a["nodeId"] for a in json.load(open(sys.argv[1]))["agents"])))' "$e/agents.json")
[ -n "$T_DEL" ] && [ -n "$NS3_START_EPOCH" ] && [ -n "$SERVICE_IP" ] && [ -n "$IDS" ] || { echo "cannot derive T_del / ns-3 start / Service IP / node ids from $e"; exit 2; }
echo "evidence $e; work $W; T_del $T_DEL; ns-3 start $NS3_START_EPOCH; Service $SERVICE_IP; nodes $IDS"

python3 -I "$E2EV/e2ap-pcap-facts.py" "$e/m7.pcap" -o "$F" --text-out "$W/m7-e2ap-setup-subscription-decoded.txt" || exit 2

fails=0
check() { # same contract as lib.sh check: name, command; prints verdict and the command output
    local name="$1" out; shift
    if out=$("$@" 2>&1); then echo "PASS $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
    echo "$out" | sed 's/^/    /'
}
record() { if [ "$2" = true ]; then echo "INFO $1: $3" | cut -c1-1500; else echo "FAIL $1: $3"; fails=$((fails + 1)); fi; }
# shellcheck source=m7-wire-trace-checks.sh
source "$E2EV/m7-wire-trace-checks.sh"
m7_wire_trace_checks

echo "---- associations (informational)"
python3 -I "$Q" "$F" associations --after "$(python3 -c "print($T_DEL - 3600)")" | cut -c1-200
[ "$fails" -eq 0 ] && echo "replay: all checks passed" || echo "replay: $fails failing check(s)"
exit "$fails"

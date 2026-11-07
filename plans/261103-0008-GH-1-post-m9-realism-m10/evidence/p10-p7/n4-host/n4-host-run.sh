#!/usr/bin/env bash
# n4-host-run.sh <bin> <run-dir> <uloff|ulon>: one N4 free run on the host, as gate-n4-ul-metric.sh's det_run does it
# (paced-lib.sh paced_null_run, free pacing): the null sink on 38471-38473 with --save-lines, scenario-zero in
# <run-dir>/ns3run with the rung config (RngRun 1, steps UL pattern, outage threshold -1000, simStartEpochMs
# 1767225600000, 2 gNBs, NoAuto, simTime 10), then ns3-argv.txt with the run dir written as <run>, ns3-exit and the
# byte manifest.
set -u
BIN="$1"; RD="$2"; CFG="$3"
H=/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0
SINK="$H/tools/ipc-null-sink/ipc-null-sink.py"
rm -rf "$RD"; mkdir -p "$RD/ns3run" "$RD/trace"
ARGS=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --outageThreshold=-1000 --simStartEpochMs=1767225600000
      --RngRun=1)
[ "$CFG" = ulon ] && ARGS+=(--enableUlTraffic=true --ulTrafficPattern=steps)
ARGS+=("--e2TraceDir=$RD/trace")
python3 -I "$SINK" --ports 38471-38473 --out "$RD/sink" --save-lines >"$RD/sink.log" 2>&1 &
SP=$!
for _ in $(seq 50); do grep -q READY "$RD/sink.log" && break; sleep 0.2; done
grep -q READY "$RD/sink.log" || { echo "sink did not start"; kill $SP; exit 1; }
( cd "$RD/ns3run" && exec timeout --kill-after=30 3600 "$BIN" "${ARGS[@]}" >stdout.txt 2>stderr.txt </dev/null )
RC=$?
sleep 1; kill -TERM $SP; wait $SP
echo "$RC" >"$RD/ns3-exit"
args="${ARGS[*]}"
tr ' ' '\n' <<<"${args//"$RD"/<run>}" >"$RD/ns3-argv.txt"
python3 -I "$H/scripts/gates/n4-run-byte-identity.py" manifest "$RD" >/dev/null; MRC=$?
echo "$CFG: ns-3 exit $RC, manifest exit $MRC"

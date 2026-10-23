#!/usr/bin/env bash
# send-rmr.sh <ctl-port> anomaly <ue-id>             one 30003 TS_ANOMALY_UPDATE naming one UE (its ue-id a string)
# send-rmr.sh <ctl-port> raw <mtype> <hex-file> [subId]  one raw RMR message (the stray-ack probe)
#
# A client of the persistent RMR injector (tools/rmr-peer/rmr-injector.py, started by injector_start in
# ts-lib.sh): one request line over a local TCP socket, one reply line; exit 0 when RMR accepted the send.
# Pure bash, so a pacer trigger costs no interpreter start-up.
set -uo pipefail
port="$1" op="$2"
case "$op" in
    anomaly) req="{\"op\": \"anomaly\", \"ue\": \"$3\"}" ;;
    raw) req="{\"op\": \"raw\", \"mtype\": $3, \"subId\": ${5:--1}, \"hex\": \"$(tr -d ' \n' <"$4")\"}" ;;
    *) echo "unknown op $op" >&2; exit 2 ;;
esac
exec 3<>"/dev/tcp/127.0.0.1/$port" || exit 1
printf '%s\n' "$req" >&3
IFS= read -r -t 10 reply <&3 || { echo "no reply from the injector" >&2; exit 1; }
exec 3<&-
echo "$reply"
[[ "$reply" == *'"ok": true'* ]]

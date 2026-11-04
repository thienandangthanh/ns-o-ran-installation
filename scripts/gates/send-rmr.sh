#!/usr/bin/env bash
# send-rmr.sh <ctl-port> anomaly <ue-id>             one 30003 TS_ANOMALY_UPDATE naming one UE (its ue-id a string)
# send-rmr.sh <ctl-port> anomaly-from <file>         the same, the ue-id read from a file holding exactly one line
#                                                     (the key a pacer prepare certified for this step)
# send-rmr.sh <ctl-port> raw <mtype> <hex-file> [subId]  one raw RMR message (the stray-ack probe)
#
# A client of the persistent RMR injector (tools/rmr-peer/rmr-injector.py, started by injector_start in
# ts-lib.sh): one request line over a local TCP socket, one reply line; exit 0 when RMR accepted the send.
# The ue-id must be the KPM UE ID key of an en-gNB-UEID (enGnbUeId:<X2AP ID>@00F110-<macro eNB ID, 5 hex digits>),
# the key the TS xApp looks the UE up by in Influx; any other string (a decimal IMSI included), a missing or empty
# file, or a file of more than one line is refused with exit 2 and nothing is sent.
# Pure bash, so a pacer trigger costs no interpreter start-up.
set -uo pipefail
UE_ID_RE='^enGnbUeId:[0-9]{1,4}@00F110-[0-9A-F]{5}$'
[ $# -ge 2 ] || { echo "usage: send-rmr.sh <ctl-port> anomaly <ue-id> | anomaly-from <file> | raw <mtype> <hex-file> [subId]" >&2; exit 2; }
port="$1" op="$2"
ue_ok() { [[ "$1" =~ $UE_ID_RE ]] || { echo "refused: ue-id '$1' is not an en-gNB-UEID key" >&2; return 1; }; }
case "$op" in
    anomaly)
        [ $# -eq 3 ] || { echo "anomaly takes one ue-id" >&2; exit 2; }
        ue_ok "$3" || exit 2
        ue="$3" ;;
    anomaly-from)
        [ $# -eq 3 ] || { echo "anomaly-from takes one file" >&2; exit 2; }
        [ -s "$3" ] || { echo "refused: ue-id file '$3' is missing or empty" >&2; exit 2; }
        mapfile -t lines <"$3"
        # one line, its newline optional; a second line, even an empty one, is refused
        n=${#lines[@]}
        [ "$n" -eq 1 ] && [ "$(wc -l <"$3")" -le 1 ] || { echo "refused: ue-id file '$3' has $n lines, want 1" >&2; exit 2; }
        ue_ok "${lines[0]}" || exit 2
        ue="${lines[0]}" ;;
    raw) req="{\"op\": \"raw\", \"mtype\": $3, \"subId\": ${5:--1}, \"hex\": \"$(tr -d ' \n' <"$4")\"}" ;;
    *) echo "unknown op $op" >&2; exit 2 ;;
esac
[ "$op" = raw ] || req="{\"op\": \"anomaly\", \"ue\": \"$ue\"}"
exec 3<>"/dev/tcp/127.0.0.1/$port" || exit 1
printf '%s\n' "$req" >&3
IFS= read -r -t 10 reply <&3 || { echo "no reply from the injector" >&2; exit 1; }
exec 3<&-
echo "$reply"
[[ "$reply" == *'"ok": true'* ]]

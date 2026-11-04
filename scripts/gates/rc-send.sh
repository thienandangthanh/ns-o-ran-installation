#!/usr/bin/env bash
# rc-send.sh <grpc-endpoint> <viaNodeId> --ue-from <file> <targetKey10hex> [ackReq=2]
# rc-send.sh <grpc-endpoint> <viaNodeId> --en-gnb-ue-id <x2apId> <macroEnbId> <targetKey10hex> [ackReq=2]
#
# One E2SM-RC Style 5 action 3 (PSCell change) control through rc's gRPC (the pacer's trigger command; standalone so
# a shell function is not needed). rc answers at once and sends the RICcontrolRequest asynchronously, so a zero exit
# only means "queued". viaNodeId names the UE's source en-gNB (E2NodeID = ranName = meid_of viaNodeId, lib.sh). The
# UE is named by its en-gNB-UEID {m-eNB-UE-X2AP-ID, globalENB-ID {00F110, macro eNB ID}}:
#   --ue-from      the file a pacer prepare wrote (ue-id-prepare.py: the IMSI resolved through the run's context
#                  files and the key confirmed in Influx), one line enGnbUeId:<x2apId>@00F110-<macroEnbId %05X>;
#   --en-gnb-ue-id the two values given explicitly, with no Influx read (only for a UE ID that no UE holds).
# The key is the TS xApp cell key %08X10: the 9-hex NR Cell Identity (gNB ID, cell part 1) and the APER pad digit 0;
# rc encodes it as the APER NR-CGI and refuses any other form (InvalidArgument, no RIC message). A malformed UE ID,
# key or file exits 2 before anything is sent.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
usage() { echo "usage: $0 ENDPOINT VIA (--ue-from FILE | --en-gnb-ue-id X2AP MACRO) KEY [ACKREQ]" >&2; exit 2; }
[ $# -ge 4 ] || usage
ep="$1"; via="$2"
case "$3" in
    --ue-from)
        [ $# -ge 5 ] || usage
        [ -s "$4" ] || { echo "UE ID file '$4' is missing or empty" >&2; exit 2; }
        mapfile -t ue_lines <"$4"
        [ "${#ue_lines[@]}" -eq 1 ] || { echo "UE ID file '$4' has ${#ue_lines[@]} lines, not exactly one" >&2; exit 2; }
        tag="${ue_lines[0]}"
        [[ "$tag" =~ ^enGnbUeId:([0-9]{1,4})@00F110-([0-9A-F]{5})$ ]] || { echo "UE ID '$tag' is not an en-gNB-UEID key" >&2; exit 2; }
        x2ap="${BASH_REMATCH[1]}"; macro="${BASH_REMATCH[2]}"; shift 4 ;;
    --en-gnb-ue-id)
        [ $# -ge 6 ] || usage
        x2ap="$4"; macro="$5"; shift 5 ;;
    *) usage ;;
esac
key="$1"; ackreq="${2:-2}"
[[ "$x2ap" =~ ^[0-9]{1,4}$ ]] && [ "$((10#$x2ap))" -le 4095 ] || { echo "m-eNB-UE-X2AP-ID '$x2ap' not in 0..4095" >&2; exit 2; }
[[ "$macro" =~ ^[0-9A-F]{5}$ ]] || { echo "macro eNB ID '$macro' is not 5 uppercase hex digits" >&2; exit 2; }
[[ "$key" =~ ^[0-9A-F]{9}0$ ]] || { echo "target key '$key' is not the TS key %09X0" >&2; exit 2; }
[[ "$ackreq" =~ ^[0-9]+$ ]] || usage
grpcurl="${GRPCURL:-$HOME/grpcurl-1.9.1/grpcurl}"
name=$(meid_of "$via")
exec "$grpcurl" -plaintext -max-time "${RC_GRPC_MAX_TIME_S:-10}" -d "{
  \"e2NodeID\": \"$name\", \"plmnID\": \"00F110\", \"ranName\": \"$name\",
  \"RICE2APHeaderData\": { \"RanFuncId\": 3, \"RICRequestorID\": 1 },
  \"RICControlHeaderData\": { \"ControlStyle\": 5, \"ControlActionId\": 3,
     \"UEID\": { \"EnGnbUEID\": { \"mEnbUeX2apId\": $((10#$x2ap)), \"globalEnbPlmn\": \"00F110\", \"globalEnbMacroId\": \"$macro\" } } },
  \"RICControlMessageData\": { \"RICControlCellTypeVal\": 1, \"TargetCellID\": \"$key\" },
  \"RICControlAckReqVal\": $ackreq
}" "$ep" rc.MsgComm/SendRICControlReqServiceGrpc

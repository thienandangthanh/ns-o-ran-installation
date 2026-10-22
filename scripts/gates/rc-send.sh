#!/usr/bin/env bash
# rc-send.sh <grpc-endpoint> <viaNodeId> <amfUeNgapId=imsi> <targetKey10hex> [ackReq=2]
#
# One control through rc's gRPC (the pacer's trigger command; standalone so a shell function is not
# needed). rc answers at once and sends the RICcontrolRequest asynchronously, so a zero exit only
# means "queued". viaNodeId names the E2 node (ranName gnb_001_001_%08x), amfUeNgapId carries the
# decimal IMSI (recorded deviation: UE ID), the key is the 5-byte cell key `%08X%02X` (gNB id, cell id).
set -euo pipefail
[ $# -ge 4 ] || { echo "usage: $0 ENDPOINT VIA IMSI KEY [ACKREQ]" >&2; exit 2; }
ep="$1"; via="$2"; imsi="$3"; key="$4"; ackreq="${5:-2}"
grpcurl="${GRPCURL:-$HOME/grpcurl-1.9.1/grpcurl}"
name=$(printf 'gnb_001_001_%08x' "$via")
exec "$grpcurl" -plaintext -max-time "${RC_GRPC_MAX_TIME_S:-10}" -d "{
  \"e2NodeID\": \"$name\", \"plmnID\": \"00F110\", \"ranName\": \"$name\",
  \"RICE2APHeaderData\": { \"RanFuncId\": 3, \"RICRequestorID\": 1 },
  \"RICControlHeaderData\": { \"ControlStyle\": 3, \"ControlActionId\": 1,
     \"UEID\": { \"GnbUEID\": { \"amfUENGAPID\": $imsi, \"gNBCUUEF1APID\": [1], \"gNBCUCPUEE1APID\": [1],
        \"guami\": { \"pLMNIdentity\": \"00F110\", \"aMFRegionID\": \"128\", \"aMFSetID\": \"1\", \"aMFPointer\": \"0\" } } } },
  \"RICControlMessageData\": { \"RICControlCellTypeVal\": 1, \"TargetCellID\": \"$key\" },
  \"RICControlAckReqVal\": $ackreq
}" "$ep" rc.MsgComm/SendRICControlReqServiceGrpc

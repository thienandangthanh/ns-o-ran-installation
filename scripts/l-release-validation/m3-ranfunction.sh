#!/bin/bash
# M3 — RAN function accepted: the E2setupResponse lists RANfunctionsAccepted
# (ranFunctionID 2) and contains NO RANfunctionsRejected. Reuses the M2 pcap if
# present, else captures fresh. Run ON oran-kvm-2.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

PCAP="$CAP_DIR/m2-e2setup.pcap"
if [ ! -s "$PCAP" ]; then
  log "M3: no M2 pcap, capturing fresh"
  KLOG="$(mktemp)"
  capture_exchange 28 20 "$PCAP" "$KLOG"
  rm -f "$KLOG"
fi

log "M3: asserting RANfunctionsAccepted (func $RAN_FUNC_ID) and no reject"
bash "$HERE/assert-pcap.sh" "$PCAP" ranfunc-accepted no-ranfunc-reject
exit $?

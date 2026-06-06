#!/bin/bash
# M5 — dummy KPM indication: after a subscription, the sim emits RICindication
# carrying an E2SM-KPM v3 IndicationMessage (Format1, S-NSSAI) under func 2 /
# OID123. Asserts the v3 PDU shape, not a specific real OID (the reference sim
# uses dummy OID123, consistent with the Phase-1 golden).
#
# SUBSCRIBER REQUIRED (same gate as M4 — see Q4). Indications only flow once a
# RICsubscriptionRequest has been received by the sim.
#
# Usage: m5-dummy-kpm.sh [captured.pcap]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

PCAP="${1:-$CAP_DIR/m5-indication.pcap}"
if [ ! -s "$PCAP" ]; then
  log "M5: NOT RUN — needs a prior subscription (see M4 / Q4)."
  exit 2
fi
log "M5: asserting RICindication + E2SM-KPM v3 in $PCAP"
bash "$HERE/assert-pcap.sh" "$PCAP" ric-indication kpm-v3
exit $?

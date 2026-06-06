#!/bin/bash
# M2 — E2 Setup: e2term returns an E2setupResponse (successfulOutcome,
# id-E2setup) to the self-built sim. Run ON oran-kvm-2.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

PCAP="$CAP_DIR/m2-e2setup.pcap"
KLOG="$(mktemp)"

log "M2: capturing setup exchange"
capture_exchange 28 20 "$PCAP" "$KLOG"
log "M2: e2mgr nodeb states (best-effort): $(nodeb_states | head -c 200)"

log "M2: asserting E2setupResponse"
bash "$HERE/assert-pcap.sh" "$PCAP" e2setup-response
rc=$?
rm -f "$KLOG"
exit $rc

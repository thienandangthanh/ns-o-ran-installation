#!/bin/bash
# m3-ns3-funcdesc.sh — Phase 4 M3: E2 Setup advertising the REAL E2SM-KPM v3.00
# RAN-function-description (built by oran-interface/examples/kpm-func-desc-v3.h),
# instead of the Phase-3 printable placeholder.
#
# Asserts the setup is still accepted with the genuine descriptor on the wire:
#   e2setup-response + ranfunc-accepted + no-ranfunc-reject
# (E2Term does not validate descriptor content for acceptance — proven Phase 3 —
#  so M3 here = "real v3.00 descriptor advertised AND accepted".)
#
# Run ON oran-kvm-2:
#   NS3_E2_SETUP_BIN=/tmp/ns3-e2-phase4-build/e2-setup-minimal \
#   bash scripts/l-release-validation/m3-ns3-funcdesc.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

NS3_E2_SETUP_BIN="${NS3_E2_SETUP_BIN:-/tmp/ns3-e2-phase4-build/e2-setup-minimal}"
if [ ! -x "$NS3_E2_SETUP_BIN" ]; then
    echo "FAIL: NS3_E2_SETUP_BIN not executable: $NS3_E2_SETUP_BIN" >&2
    exit 1
fi

PCAP="$CAP_DIR/phase4-m3-ns3-funcdesc.pcap"
SIMLOG="$(mktemp)"

log "M3 (ns3-funcdesc): capturing setup exchange (binary: $NS3_E2_SETUP_BIN)"

# capture_exchange kills $KPM_SIM pattern to clear src port 36422 between tries.
KPM_SIM="$NS3_E2_SETUP_BIN"
capture_exchange 28 20 "$PCAP" "$SIMLOG"

log "M3 (ns3-funcdesc): sim log tail (expect 'descriptor: 1600 bytes'):"
grep -E "descriptor:|E2setup" "$SIMLOG" | tail -5 || tail -5 "$SIMLOG" || true
rm -f "$SIMLOG"

log "M3 (ns3-funcdesc): asserting E2setupResponse + RANfunctionsAccepted + no reject"
bash "$HERE/assert-pcap.sh" "$PCAP" e2setup-response ranfunc-accepted no-ranfunc-reject
rc=$?
if [ "$rc" -eq 0 ]; then
    log "M3 (ns3-funcdesc): ALL CHECKS PASSED — pcap: $PCAP"
else
    log "M3 (ns3-funcdesc): SOME CHECKS FAILED — inspect pcap: $PCAP"
fi
exit $rc

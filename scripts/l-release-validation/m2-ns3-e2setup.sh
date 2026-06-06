#!/bin/bash
# m2-ns3-e2setup.sh — Phase 3 M2: E2 Setup via the ns-3-linked e2-setup-minimal app.
# Captures the SCTP exchange on cni0 and asserts:
#   e2setup-response + ranfunc-accepted + no-ranfunc-reject
#
# Differences from m2-e2setup.sh (Phase 2 kpm_sim):
#   - Uses NS3_E2_SETUP_BIN instead of KPM_SIM
#   - Output pcap: captures/phase3-m2-ns3-setup.pcap
#
# Run ON oran-kvm-2:
#   NS3_E2_SETUP_BIN=/tmp/ns3-e2-phase3-build/e2-setup-minimal \
#   bash scripts/l-release-validation/m2-ns3-e2setup.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

# Override: use the Phase-3 binary instead of KPM_SIM
NS3_E2_SETUP_BIN="${NS3_E2_SETUP_BIN:-/tmp/ns3-e2-phase3-build/e2-setup-minimal}"
if [ ! -x "$NS3_E2_SETUP_BIN" ]; then
    echo "FAIL: NS3_E2_SETUP_BIN not executable: $NS3_E2_SETUP_BIN" >&2
    exit 1
fi

PCAP="$CAP_DIR/phase3-m2-ns3-setup.pcap"
SIMLOG="$(mktemp)"

log "M2 (ns3-e2): capturing setup exchange (binary: $NS3_E2_SETUP_BIN)"

# Temporarily override KPM_SIM so capture_exchange uses our binary.
# capture_exchange kills $KPM_SIM pattern to clear src port 36422 between tries.
KPM_SIM="$NS3_E2_SETUP_BIN"
capture_exchange 28 20 "$PCAP" "$SIMLOG"

log "M2 (ns3-e2): sim log tail:"
tail -5 "$SIMLOG" || true
rm -f "$SIMLOG"

log "M2 (ns3-e2): asserting E2setupResponse + RANfunctionsAccepted + no reject"
bash "$HERE/assert-pcap.sh" "$PCAP" e2setup-response ranfunc-accepted no-ranfunc-reject
rc=$?
if [ "$rc" -eq 0 ]; then
    log "M2 (ns3-e2): ALL CHECKS PASSED — pcap: $PCAP"
else
    log "M2 (ns3-e2): SOME CHECKS FAILED — inspect pcap: $PCAP"
fi
exit $rc

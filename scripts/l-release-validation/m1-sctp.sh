#!/bin/bash
# M1 — SCTP transport: self-built kpm_sim establishes an SCTP association with
# the live L-release E2Term over the NodePort path (INIT/INIT-ACK/COOKIE).
# Run ON oran-kvm-2.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

PCAP="$CAP_DIR/m1-sctp.pcap"
KLOG="$(mktemp)"

log "M1: capturing SCTP on $CAP_IFACE, running kpm_sim -> $E2TERM_NODE_IP:$E2TERM_NODEPORT"
# M1 only needs the SCTP handshake, not E2AP DATA -> min=0 (no DATA retry).
capture_exchange 18 12 "$PCAP" "$KLOG" 0

log "M1: asserting SCTP handshake"
bash "$HERE/assert-pcap.sh" "$PCAP" sctp-init
rc=$?
grep -q "Connection established" "$KLOG" \
  && echo "  PASS: kpm_sim reports [SCTP] Connection established" \
  || { echo "  FAIL: kpm_sim did not report connection"; rc=1; }
rm -f "$KLOG"
exit $rc

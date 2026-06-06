#!/bin/bash
# m4-subscription.sh — Phase 5 M4: a REAL kpimon-go RICsubscriptionRequest to the
# ns-3 E2 node's KPM function (RAN func id 2) is admitted and answered with a
# RICsubscriptionResponse(success).
#
# Unlike M2/M3 (one-shot setup capture over a transient association), M4 needs the
# node to stay CONNECTED long enough for kpimon-go to discover it in RNIB and
# subscribe. Two live-RIC facts learned in Phase 5 drive this flow:
#   1. Connect to the e2term POD IP:36422 (cni0), NOT the NodePort 32222 — the
#      NodePort/IPVS SNAT path resets the association (fine for a one-shot capture,
#      fatal for a persistent node).
#   2. e2term re-runs a fresh E2 Setup only for a NEW or SHUT_DOWN node; a stale
#      DISCONNECTED RNIB entry (left by a prior run with the same gNB-ID) makes
#      e2term skip setup and never reply. So clear RNIB (PUT /v1/nodeb/shutdown)
#      before connecting.
# kpimon-go scans RNIB at startup, so it is restarted once the node is CONNECTED
# to force it to discover the gNB and emit the subscription.
#
# Run ON oran-kvm-2:
#   NS3_E2_SETUP_BIN=/tmp/ns3-e2-build/e2-setup-minimal \
#   bash scripts/l-release-validation/m4-subscription.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

E2TERM_POD_SCTP="${E2TERM_POD_SCTP:-36422}"     # e2term pod's own SCTP port
NS3_E2_SETUP_BIN="${NS3_E2_SETUP_BIN:-/tmp/ns3-e2-build/e2-setup-minimal}"
PCAP="$CAP_DIR/phase5-m4-subscription.pcap"
NODE_LOG="$(mktemp)"

if [ ! -x "$NS3_E2_SETUP_BIN" ]; then
    echo "FAIL: NS3_E2_SETUP_BIN not executable: $NS3_E2_SETUP_BIN" >&2
    exit 1
fi

log "M4: clearing stale RNIB (PUT /v1/nodeb/shutdown) so a fresh setup runs"
curl -s -X PUT "http://$E2MGR_HTTP/v1/nodeb/shutdown" -w "  shutdown:%{http_code}\n" >/dev/null 2>&1
sleep 3

log "M4: capturing on $CAP_IFACE; node -> e2term pod $E2TERM_POD_IP:$E2TERM_POD_SCTP"
sudo rm -f "$PCAP"
sudo pkill -f "$NS3_E2_SETUP_BIN" 2>/dev/null
sudo timeout 150 tcpdump -i "$CAP_IFACE" -s0 -U -w "$PCAP" "sctp and host $E2TERM_POD_IP" \
    >/dev/null 2>&1 &
sleep 3

# Persistent node: must outlive kpimon's restart + discovery + subscription.
timeout 140 "$NS3_E2_SETUP_BIN" "$E2TERM_POD_IP" "$E2TERM_POD_SCTP" >"$NODE_LOG" 2>&1 &
sleep 12
log "M4: nodeb state after setup: $(nodeb_states)"

# Force kpimon-go to re-scan RNIB and find the now-CONNECTED gNB.
KPOD="$(kubectl -n ricxapp get pod -o name 2>/dev/null | grep kpimon | head -1)"
log "M4: restarting $KPOD to trigger subscription"
kubectl -n ricxapp delete "$KPOD" --wait=false >/dev/null 2>&1

# Wait (bounded) for our node to handle the subscription.
for i in $(seq 1 20); do
    sleep 6
    if grep -qiE "RICsubscriptionRequest handled|action\(s\) admitted" "$NODE_LOG"; then
        log "M4: node handled the subscription at ~$((i*6))s"
        break
    fi
done
log "M4: node subscription log:"
grep -iE "RICsubscriptionRequest handled|admitted|SETUP-RESPONSE-SUCCESS" "$NODE_LOG" | tail -5

sleep 3
sudo pkill -f "$NS3_E2_SETUP_BIN" 2>/dev/null
sudo pkill -f "tcpdump" 2>/dev/null
sleep 2
sudo chmod a+r "$PCAP" 2>/dev/null
rm -f "$NODE_LOG"

log "M4: asserting SCTP + E2setupResponse + RICsubscriptionResponse"
bash "$HERE/assert-pcap.sh" "$PCAP" sctp-init e2setup-response sub-response
rc=$?
if [ "$rc" -eq 0 ]; then
    log "M4: ALL CHECKS PASSED — pcap: $PCAP"
else
    log "M4: SOME CHECKS FAILED (note: VM tshark lacks E2AP dissector; decode with a"
    log "    4.x host for the authoritative verdict) — inspect pcap: $PCAP"
fi
exit $rc

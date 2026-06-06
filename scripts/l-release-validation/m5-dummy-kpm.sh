#!/bin/bash
# m5-dummy-kpm.sh — Phase 6 M5: after a real kpimon-go subscription is admitted,
# the ns-3 E2 node (e2-setup-minimal) emits a burst of E2SM-KPM v3.00
# RICindication PDUs (IndicationHeader-Format1 with an 8-byte colletStartTime +
# IndicationMessage-Format1 with a MeasurementData record labelled PLMN/S-NSSAI)
# for the admitted action.
#
# This is M4 + indications: the live flow is identical to m4-subscription.sh
# (persistent node on the e2term POD IP, clear RNIB, restart kpimon to trigger
# the subscription) but the capture window is extended past the subscription so
# the indication report loop lands on the wire, and the assertion adds
# ric-indication + kpm-v3. The same two live-RIC facts from Phase 5 apply:
#   1. Connect to the e2term POD IP:36422 (cni0), NOT the NodePort 32222.
#   2. Clear stale RNIB (PUT /v1/nodeb/shutdown) before connecting so e2term runs
#      a fresh E2 Setup; kpimon-go is restarted once the node is CONNECTED.
#
# Authoritative v3 correctness is the offline proof (kpm-indication-test, exit 0);
# this harness proves the indication reaches the wire under the live submgr.
#
# Run ON oran-kvm-2:
#   NS3_E2_SETUP_BIN=/tmp/ns3-e2-build/e2-setup-minimal \
#   bash scripts/l-release-validation/m5-dummy-kpm.sh
#
# Or assert an already-captured pcap (skip the live flow):
#   bash scripts/l-release-validation/m5-dummy-kpm.sh path/to/captured.pcap
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

# --- Fallback: assert a pre-captured pcap if one is passed -----------------
if [ "$#" -ge 1 ]; then
  PCAP="$1"
  if [ ! -s "$PCAP" ]; then
    log "M5: given pcap is empty/missing: $PCAP"; exit 2
  fi
  log "M5: asserting RICindication + E2SM-KPM v3 in $PCAP"
  bash "$HERE/assert-pcap.sh" "$PCAP" sctp-init e2setup-response sub-response \
       ric-indication kpm-v3
  exit $?
fi

# --- Live flow -------------------------------------------------------------
E2TERM_POD_SCTP="${E2TERM_POD_SCTP:-36422}"
NS3_E2_SETUP_BIN="${NS3_E2_SETUP_BIN:-/tmp/ns3-e2-build/e2-setup-minimal}"
PCAP="$CAP_DIR/phase6-m5-indication.pcap"
NODE_LOG="$(mktemp)"

# Indication burst: enough reports for kpimon to decode + enough wire frames to
# capture, but short enough to finish inside the node lifetime. Overridable.
export KPM_IND_COUNT="${KPM_IND_COUNT:-15}"
export KPM_IND_INTERVAL_MS="${KPM_IND_INTERVAL_MS:-1000}"

if [ ! -x "$NS3_E2_SETUP_BIN" ]; then
    echo "FAIL: NS3_E2_SETUP_BIN not executable: $NS3_E2_SETUP_BIN" >&2
    exit 1
fi

log "M5: clearing stale RNIB (PUT /v1/nodeb/shutdown) so a fresh setup runs"
curl -s -X PUT "http://$E2MGR_HTTP/v1/nodeb/shutdown" -w "  shutdown:%{http_code}\n" >/dev/null 2>&1
sleep 3

log "M5: capturing on $CAP_IFACE; node -> e2term pod $E2TERM_POD_IP:$E2TERM_POD_SCTP"
log "M5: indication burst = $KPM_IND_COUNT @ ${KPM_IND_INTERVAL_MS}ms"
sudo rm -f "$PCAP"
sudo pkill -f "$NS3_E2_SETUP_BIN" 2>/dev/null
sudo timeout 180 tcpdump -i "$CAP_IFACE" -s0 -U -w "$PCAP" "sctp and host $E2TERM_POD_IP" \
    >/dev/null 2>&1 &
sleep 3

# Persistent node: must outlive kpimon's restart + discovery + subscription +
# the full indication burst (count * interval).
timeout 170 "$NS3_E2_SETUP_BIN" "$E2TERM_POD_IP" "$E2TERM_POD_SCTP" >"$NODE_LOG" 2>&1 &
sleep 12
log "M5: nodeb state after setup: $(nodeb_states)"

# Force kpimon-go to re-scan RNIB and find the now-CONNECTED gNB.
KPOD="$(kubectl -n ricxapp get pod -o name 2>/dev/null | grep kpimon | head -1)"
log "M5: restarting $KPOD to trigger subscription"
kubectl -n ricxapp delete "$KPOD" --wait=false >/dev/null 2>&1

# Wait (bounded) for the node to handle the subscription AND finish the burst.
for i in $(seq 1 25); do
    sleep 6
    if grep -qiE "indication report loop done" "$NODE_LOG"; then
        log "M5: node finished the indication burst at ~$((i*6))s"
        break
    fi
    if grep -qiE "RICsubscriptionRequest handled" "$NODE_LOG"; then
        log "M5: subscription handled at ~$((i*6))s; indications in flight"
    fi
done
log "M5: node log (subscription + indications):"
grep -iE "RICsubscriptionRequest handled|admitted|indication report loop|sent RICindication" \
    "$NODE_LOG" | tail -8

sleep 3
sudo pkill -f "$NS3_E2_SETUP_BIN" 2>/dev/null
sudo pkill -f "tcpdump" 2>/dev/null
sleep 2
sudo chmod a+r "$PCAP" 2>/dev/null
rm -f "$NODE_LOG"

log "M5: asserting SCTP + E2setupResponse + RICsubscriptionResponse + RICindication + KPM v3"
bash "$HERE/assert-pcap.sh" "$PCAP" sctp-init e2setup-response sub-response \
     ric-indication kpm-v3
rc=$?
if [ "$rc" -eq 0 ]; then
    log "M5: ALL CHECKS PASSED — pcap: $PCAP"
else
    log "M5: SOME CHECKS FAILED (note: VM tshark lacks E2AP dissector; decode with a"
    log "    4.x host for the authoritative verdict) — inspect pcap: $PCAP"
fi
exit $rc

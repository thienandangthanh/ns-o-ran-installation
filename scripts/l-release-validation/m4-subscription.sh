#!/bin/bash
# M4 — RIC subscription: e2term/xApp drives a RICsubscriptionRequest to the sim
# and the sim returns a RICsubscriptionResponse.
#
# SUBSCRIBER REQUIRED. The bundled kpm_sim is REACTIVE-ONLY: it registers a
# subscription callback (kpm_callbacks.cpp: register_subscription_callback) and
# then blocks on "Waiting for SCTP data" — it cannot self-trigger an indication.
# A RICsubscriptionRequest must come from an external KPM xApp
# (scp-kpimon / kpimon-go). No KPM xApp is currently deployed in `ricxapp`
# (only ricxapp-hw-go). See OPEN QUESTION Q4 / Q3 (func-id 2 vs 0) in the
# handoff + implementation-notes.html.
#
# Usage:
#   1) Onboard a KPM xApp that subscribes to the sim, capture during the sub.
#   2) Run: m4-subscription.sh [captured.pcap]
# If a pcap arg is given it is asserted; otherwise this prints the gating note
# and exits 2 (not-run), so the harness stays honest.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

PCAP="${1:-$CAP_DIR/m4-subscription.pcap}"
if [ ! -s "$PCAP" ]; then
  log "M4: NOT RUN — needs an external RICsubscriptionRequest source (KPM xApp)."
  log "    Deploy scp-kpimon/kpimon-go OR pass a pre-captured pcap. See Q4."
  exit 2
fi
log "M4: asserting RICsubscriptionResponse in $PCAP"
bash "$HERE/assert-pcap.sh" "$PCAP" sub-response
exit $?

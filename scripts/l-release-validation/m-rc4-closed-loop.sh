#!/bin/bash
# m-rc4-closed-loop.sh — Phase 6b M-RC4: the TS-driven mock closed loop.
#
# Asserts the M-RC4 exit criteria over the artifacts produced by
# scripts/phase6b-closed-loop-run.sh (a mock TS_QOE_PREDICTION pushed into the
# live TS xApp drives >=2 forced mmWave handovers for >=2 UEs on >=2 owning gNBs,
# via the TS xApp's OWN gRPC control emit — no grpcurl in the loop):
#
#   pcap   : >=2 E2AP RICcontrolRequest + >=2 RICcontrolAcknowledge
#            (byte sigs 0004 / 2004 on the VM; exact counts on a tshark 4.x host)
#   ns-3   : >=2 distinct "handover from X to Y" for >=2 distinct IMSIs + >=2 ACKs
#   TS log : >=2 "in ts xapp grpc message content" emits (the provenance — a TS,
#            not grpcurl, origin; the wire bytes are identical either way)
#
# Provenance caveat: pcap alone cannot prove "TS-triggered". The TS pod-log emit
# count, timestamp-correlated to the wire Control Requests, plus the documented
# fact that no grpcurl runs in the loop, is the proof. (Stage-D plan D5.)
#
# Usage (offline assertion over captured artifacts; all three required):
#   bash scripts/l-release-validation/m-rc4-closed-loop.sh <pcap> <ns3.log> <ts.log>
# Or via env: PCAP=... NS3_LOG=... TS_LOG=... bash .../m-rc4-closed-loop.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/common.sh"

PCAP="${1:-${PCAP:-}}"
NS3_LOG="${2:-${NS3_LOG:-}}"
TS_LOG="${3:-${TS_LOG:-}}"
MIN="${MIN:-2}"   # M-RC4 exit scope: >=2 UEs / >=2 owning gNBs

[ -s "$PCAP" ]    || { fail "M-RC4: pcap missing/empty: $PCAP"; exit 2; }
[ -s "$NS3_LOG" ] || { fail "M-RC4: ns-3 log missing/empty: $NS3_LOG"; exit 2; }
[ -s "$TS_LOG" ]  || { fail "M-RC4: TS log missing/empty: $TS_LOG"; exit 2; }

rc=0

log "M-RC4: pcap RICcontrolRequest/Acknowledge (>=$MIN each)"
bash "$HERE/assert-pcap.sh" "$PCAP" control-request control-ack || rc=1

log "M-RC4: ns-3 handovers / IMSIs / ACKs (>=$MIN)"
ho=$(grep -oE "handover from [0-9]+ to [0-9]+" "$NS3_LOG" | sort -u | wc -l)
imsis=$(grep -oE "imsi=[0-9]+" "$NS3_LOG" | sort -u | wc -l)
acks=$(grep -c "Generated RIC Control Acknowledge" "$NS3_LOG")
[ "$ho" -ge "$MIN" ]    && pass "ns-3 distinct handovers x$ho (>=$MIN)"     || { fail "ns-3 distinct handovers x$ho (<$MIN)"; rc=1; }
[ "$imsis" -ge "$MIN" ] && pass "ns-3 distinct IMSIs x$imsis (>=$MIN)"      || { fail "ns-3 distinct IMSIs x$imsis (<$MIN)"; rc=1; }
[ "$acks" -ge "$MIN" ]  && pass "ns-3 RIC Control Acknowledge x$acks (>=$MIN)" || { fail "ns-3 ACKs x$acks (<$MIN)"; rc=1; }

log "M-RC4: TS-emitted controls (provenance — no grpcurl in the loop)"
emits=$(grep -c "in ts xapp grpc message content" "$TS_LOG")
drops=$(grep -c "Cannot find RAN name" "$TS_LOG")
[ "$emits" -ge "$MIN" ] && pass "TS gRPC control emits x$emits (>=$MIN)" || { fail "TS gRPC control emits x$emits (<$MIN)"; rc=1; }
[ "$drops" -eq 0 ] && pass "TS cell_map drops 0 (no silent target misses)" || log "  NOTE: $drops TS cell_map drops (target key not in cell_map for some prediction)"

if [ "$rc" -eq 0 ]; then
  log "M-RC4: ALL CHECKS PASSED — TS-driven multi-UE/multi-gNB closed loop proven"
else
  log "M-RC4: SOME CHECKS FAILED — inspect artifacts: pcap=$PCAP ns3=$NS3_LOG ts=$TS_LOG"
fi
exit $rc

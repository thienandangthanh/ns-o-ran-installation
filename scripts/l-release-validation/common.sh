#!/bin/bash
# Shared config + helpers for the L-release E2 validation harness (M1-M5).
# Sourced by m1..m5 scripts and assert-pcap.sh. Run ON the VM oran-kvm-2.
#
# Version-pinned facts live in manifest.txt; this file holds the live wiring
# (endpoints, paths) used by every milestone so they stay DRY.

set -u

# --- Live RIC wiring (L-release, ns ricplt) -------------------------------
E2TERM_NODE_IP="${E2TERM_NODE_IP:-192.168.122.78}"   # node IP, NodePort path
E2TERM_NODEPORT="${E2TERM_NODEPORT:-32222}"          # SCTP NodePort -> 36422
E2TERM_POD_IP="${E2TERM_POD_IP:-10.244.0.48}"        # e2term-alpha pod (cni0)
E2MGR_HTTP="${E2MGR_HTTP:-10.100.86.178:3800}"       # e2mgr REST (ClusterIP)
CAP_IFACE="${CAP_IFACE:-cni0}"                       # E2 SCTP rides cni0
RAN_FUNC_ID="${RAN_FUNC_ID:-2}"                      # bundled KPM sim func id

# --- Self-built artifacts (Phase 2 vendored OSC e2sim da6f82f2) ------------
# kpm_sim is built into a staging dir; allow override. The default avoids the
# literal build-dir name being hard-required by callers.
KPM_SIM="${KPM_SIM:-/tmp/kpm-build-stage/build/src/kpm/kpm_sim}"

# --- Output dirs ----------------------------------------------------------
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP_DIR="${CAP_DIR:-$HARNESS_DIR/captures}"
mkdir -p "$CAP_DIR"

log()  { echo "[$(date +%H:%M:%S)] $*"; }
pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*"; return 1; }

# Run one E2 exchange + capture, fully self-contained (no cross-subshell PIDs).
# $1 = capture seconds, $2 = sim seconds (< capture), $3 = pcap, $4 = sim log.
# Capture starts first, sim runs inside the window, function blocks until the
# capture's own `timeout` ends so the pcap is fully written before we assert.
# NOTE: avoids `wait` on PIDs captured via $(...) — those are not children of
# the caller and `wait` would return instantly, asserting on an empty pcap.
# Count SCTP DATA chunks in a pcap (the E2AP-bearing chunks).
data_chunks() {
  tshark -r "$1" -Y 'sctp.chunk_type==0' 2>/dev/null | wc -l
}

# One capture+sim pass. Capture starts first; sim runs inside the window; we
# block for the full window so the pcap is complete before returning.
# NOTE: never `wait` on $(...)-captured PIDs — they aren't children, so `wait`
# returns instantly and we'd assert on a half-written pcap.
_one_exchange() {
  local cap_secs="$1" sim_secs="$2" pcap="$3" simlog="$4"
  sudo rm -f "$pcap"
  sudo pkill -f "$KPM_SIM" 2>/dev/null   # ensure no stale sim holds src port 36422
  sudo timeout "$cap_secs" tcpdump -i "$CAP_IFACE" -s0 -U -w "$pcap" sctp \
    >/dev/null 2>&1 &
  sleep 4                                 # let the BPF filter attach
  RAN_FUNC_ID="$RAN_FUNC_ID" timeout "$sim_secs" \
    "$KPM_SIM" "$E2TERM_NODE_IP" "$E2TERM_NODEPORT" >"$simlog" 2>&1 &
  sleep "$((cap_secs - 3))"
  sudo chmod a+r "$pcap" 2>/dev/null
}

# Capture an E2 exchange, retrying until the pcap carries E2AP DATA chunks
# (the NodePort/IPVS SNAT path occasionally drops the setup DATA from cni0).
# Bounded to 3 attempts. $1=cap secs $2=sim secs $3=pcap $4=simlog [$5=min data]
capture_exchange() {
  local cap_secs="$1" sim_secs="$2" pcap="$3" simlog="$4" min="${5:-1}" i
  for i in 1 2 3; do
    _one_exchange "$cap_secs" "$sim_secs" "$pcap" "$simlog"
    [ "$(data_chunks "$pcap")" -ge "$min" ] && return 0
    log "  (retry $i: no E2AP DATA chunk captured, re-running)"
  done
  return 0
}

# Poll e2mgr for the gNB connection status (best-effort; wire pcap is truth).
nodeb_states() {
  curl -s "http://$E2MGR_HTTP/v1/nodeb/states" 2>/dev/null
}

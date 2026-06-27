#!/bin/bash
# assert-pcap.sh — assert E2AP milestones against a captured pcap.
#
# Usage: assert-pcap.sh <pcap> <check> [check ...]
#   checks: sctp-init | e2setup-response | ranfunc-accepted | no-ranfunc-reject
#           sub-response | ric-indication | kpm-v3 | control-request | control-ack
#
# Two decode paths, auto-selected:
#   (A) tshark WITH the E2AP dissector (Wireshark >= ~3.6 / the local 4.x host):
#       full verbose decode + field greps. Force-decode flags (Phase-1 gotcha):
#       E2AP rides SCTP PPID 70; the IP-fragmented E2setupRequest reassembles
#       with PPID 0 and tshark mis-dissects it as X2AP HandoverCancel[Malformed]
#       -> force both PPIDs to e2ap, disable x2ap, enable IP defrag.
#   (B) tshark WITHOUT E2AP (e.g. the VM's 3.2.3): fall back to matching E2AP
#       APER byte signatures + ASCII markers in the SCTP DATA payloads. The
#       wire bytes are dissector-independent, so the same facts are asserted.
#
# Prefer running on a tshark 4.x host for path (A) (richest). Both give the
# same PASS/FAIL on the milestone facts.

set -u

PCAP="${1:?usage: assert-pcap.sh <pcap> <check>...}"
shift

TSHARK="${TSHARK:-tshark}"
FLAGS=(-r "$PCAP"
  -o ip.defragment:TRUE
  --disable-protocol x2ap
  -d 'sctp.ppi==0,e2ap'
  -d 'sctp.ppi==70,e2ap')

# Does this tshark know E2AP? (3.2.3 does not.)
HAVE_E2AP=0
"$TSHARK" -G protocols 2>/dev/null | grep -qi 'e2ap' && HAVE_E2AP=1

DECODE="$(mktemp)"
HEXDUMP="$(mktemp)"
trap 'rm -f "$DECODE" "$HEXDUMP"' EXIT

if [ "$HAVE_E2AP" = 1 ]; then
  "$TSHARK" "${FLAGS[@]}" -Y e2ap -V >"$DECODE" 2>/dev/null
fi
# Always build a flat hex+ascii dump of SCTP DATA payloads for the fallback.
"$TSHARK" -r "$PCAP" -Y 'sctp.chunk_type==0' -x 2>/dev/null \
  | tr -s ' ' | sed 's/^[0-9a-f]\{4\} //' >"$HEXDUMP"
# Normalize to a single byte stream (lowercase hex, no spaces) + keep ascii col.
HEXSTREAM="$(grep -oE '([0-9a-f]{2} )+' "$HEXDUMP" | tr -d ' \n')"
ASCII="$(strings "$PCAP")"

rc=0
ok()   { echo "  PASS: $1"; }
bad()  { echo "  FAIL: $1"; rc=1; }

# Decode-path grep (path A) OR byte/ascii grep (path B).
has_decode() { [ "$HAVE_E2AP" = 1 ] && grep -qiE "$1" "$DECODE"; }
has_bytes()  { printf '%s' "$HEXSTREAM" | grep -qiE "$1"; }
has_ascii()  { printf '%s' "$ASCII"   | grep -qiE "$1"; }

check_sctp_init() {
  local n
  n=$("$TSHARK" -r "$PCAP" -Y 'sctp.chunk_type==1 || sctp.chunk_type==2' \
        2>/dev/null | wc -l)
  [ "$n" -ge 2 ] && ok "M1 SCTP INIT/INIT-ACK ($n handshake pkts)" \
                 || bad "M1 SCTP INIT/INIT-ACK (only $n)"
}

# E2setupResponse: successfulOutcome(0x20) + procedureCode id-E2setup(0x01) => "2001"
check_e2setup_response() {
  if has_decode "E2setupResponse" || has_bytes "2001003[0-9a-f]"; then
    ok "M2 E2setupResponse"
  else bad "M2 E2setupResponse"; fi
}

# RANfunctionsAccepted: IE id 9 (00 09) inside the response. ASCII RANfunction
# def (ORAN-E2SM-KPM) is in the request; accept either signal.
check_ranfunc_accepted() {
  if has_decode "RANfunctionsAccepted" \
     || { has_bytes "2001"  && has_bytes "0009"; } \
     || has_ascii "ORAN-E2SM-KPM"; then
    ok "M3 RANfunctionsAccepted"
  else bad "M3 RANfunctionsAccepted"; fi
}

# No RANfunctionsRejected: IE id 13 (00 0d) must NOT appear in a setup response.
check_no_ranfunc_reject() {
  if [ "$HAVE_E2AP" = 1 ]; then
    grep -qiE "RANfunctionsRejected|RANfunctions-Rejected" "$DECODE" \
      && { bad "M3 no RANfunctionsRejected (found reject IE)"; return; }
  fi
  ok "M3 no RANfunctionsRejected (correctly absent)"
}

# RICsubscriptionResponse: successfulOutcome(0x20) + procedureCode id-RICsub(0x08)
# then the open-type length octet(s). The success response is short (Phase-5 live
# response measured "2008 00 1d ..." for 1 admitted action), so match 2008 + 00 +
# a length byte rather than a fixed 0x3x nibble.
check_sub_response() {
  if has_decode "RICsubscriptionResponse" || has_bytes "200800[0-9a-f]{2}"; then
    ok "M4 RICsubscriptionResponse"
  else bad "M4 RICsubscriptionResponse"; fi
}

# RICindication: initiatingMessage(0x00) + procedureCode id-RICindication(0x05) => "0005"
check_ric_indication() {
  if has_decode "RICindication" || has_bytes "0005"; then
    ok "M5 RICindication"
  else bad "M5 RICindication"; fi
}

check_kpm_v3() {
  if has_decode "E2SM-KPM-IndicationMessage|ORAN-E2SM-KPM" \
     || has_ascii "ORAN-E2SM-KPM|OID123"; then
    ok "M5 E2SM-KPM v3 OID/IE"
  else bad "M5 E2SM-KPM v3 OID/IE"; fi
}

# Count E2AP RICcontrol PDUs of one outcome on a 4.x host; -1 if no E2AP dissector.
count_e2ap() {  # $1 = e2ap display-filter
  [ "$HAVE_E2AP" = 1 ] || { echo -1; return; }
  "$TSHARK" "${FLAGS[@]}" -Y "$1" 2>/dev/null | wc -l
}

# RICcontrolRequest: initiatingMessage(0x00) + procedureCode id-RICcontrol(0x04) => "0004".
# >=N requires the E2AP dissector (the byte sig is presence-only on the VM fallback).
check_control_request() {  # optional $1 = min count (default 1)
  local min="${1:-1}" n
  n=$(count_e2ap "e2ap.RICcontrolRequest_element")
  if [ "$n" -ge "$min" ]; then ok "M-RC4 RICcontrolRequest x$n (>=$min)"
  elif [ "$n" = -1 ] && has_bytes "0004"; then ok "M-RC4 RICcontrolRequest present (byte sig 0004; count needs 4.x host)"
  else bad "M-RC4 RICcontrolRequest (have $n, need >=$min)"; fi
}

# RICcontrolAcknowledge: successfulOutcome(0x20) + procedureCode id-RICcontrol(0x04) => "2004".
check_control_ack() {  # optional $1 = min count (default 1)
  local min="${1:-1}" n
  n=$(count_e2ap "e2ap.RICcontrolAcknowledge_element")
  if [ "$n" -ge "$min" ]; then ok "M-RC4 RICcontrolAcknowledge x$n (>=$min)"
  elif [ "$n" = -1 ] && has_bytes "2004"; then ok "M-RC4 RICcontrolAcknowledge present (byte sig 2004; count needs 4.x host)"
  else bad "M-RC4 RICcontrolAcknowledge (have $n, need >=$min)"; fi
}

for c in "$@"; do
  case "$c" in
    sctp-init)         check_sctp_init ;;
    e2setup-response)  check_e2setup_response ;;
    ranfunc-accepted)  check_ranfunc_accepted ;;
    no-ranfunc-reject) check_no_ranfunc_reject ;;
    sub-response)      check_sub_response ;;
    ric-indication)    check_ric_indication ;;
    kpm-v3)            check_kpm_v3 ;;
    control-request)   check_control_request 2 ;;
    control-ack)       check_control_ack 2 ;;
    *) bad "unknown check '$c'" ;;
  esac
done

[ "$HAVE_E2AP" = 1 ] || echo "  (note: tshark lacks E2AP dissector; used byte-signature fallback)"
exit $rc

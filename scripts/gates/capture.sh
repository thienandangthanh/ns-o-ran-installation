#!/usr/bin/env bash
# Packet-capture helpers for gates (sourced after lib.sh, never executed).
#
#   capture_start <name> <iface> [filter]   tcpdump -> $EVIDENCE_DIR/<name>.pcap (filter default: sctp)
#   capture_stop  <name>                    SIGINT, wait, assert the pcap holds packets
#   e2ap_decode   <pcap> <out.txt>          tshark -V decode plus a -T fields summary (<out>.fields.tsv)
#
# One interface per capture, never `-i any` (plan.md K10). Each capture runs in its
# own session/process group as root (tcpdump -Z root keeps the pcap writable in
# $HOME). State lives in $EVIDENCE_DIR/captures/<name>.{pid,log}; an EXIT trap
# stops any capture still running so nothing is orphaned (process-management rule).

CAPTURE_TRAP_SET=""

_capture_stop_all() {
    local f n
    for f in "$EVIDENCE_DIR"/captures/*.pid; do
        [ -e "$f" ] || continue
        n=$(basename "$f" .pid)
        capture_stop "$n" >/dev/null 2>&1 || true
    done
}

# Chain onto any EXIT trap already installed (e.g. the RIC watchdog stop).
_capture_install_trap() {
    [ -z "$CAPTURE_TRAP_SET" ] || return 0
    local prev
    prev=$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT\$/\1/")
    # shellcheck disable=SC2064
    trap "_capture_stop_all; $prev" EXIT
    CAPTURE_TRAP_SET=1
}

capture_start() {
    local name="$1" iface="$2" filter="${3:-sctp}"
    local dir="$EVIDENCE_DIR/captures" pcap="$EVIDENCE_DIR/$name.pcap" i
    mkdir -p "$dir"
    if [ "$iface" = any ]; then log "capture_start: -i any is not allowed"; return 2; fi
    command -v tcpdump >/dev/null 2>&1 || { log "capture_start: tcpdump missing"; return 127; }
    ip link show "$iface" >/dev/null 2>&1 || { log "capture_start: no interface $iface"; return 1; }
    if [ -s "$dir/$name.pid" ] && sudo -n kill -0 "$(cat "$dir/$name.pid")" 2>/dev/null; then
        log "capture_start: $name already running"; return 1
    fi
    sudo -n rm -f "$pcap" "$dir/$name.pid"
    # setsid: own session/process group. Root shell records the tcpdump PID (exec keeps it).
    # shellcheck disable=SC2016
    setsid sudo -n bash -c 'echo $$ >"$1"; shift; exec tcpdump "$@"' _ "$dir/$name.pid" \
        -i "$iface" -U -Z root -w "$pcap" "$filter" >"$dir/$name.log" 2>&1 </dev/null &
    for ((i = 0; i < 30; i++)); do
        grep -q 'listening on' "$dir/$name.log" 2>/dev/null && break
        sleep 0.5
    done
    if ! grep -q 'listening on' "$dir/$name.log" 2>/dev/null; then
        log "capture_start: $name did not start: $(tail -n 3 "$dir/$name.log")"; return 1
    fi
    _capture_install_trap
    log "capture $name started on $iface (pid $(cat "$dir/$name.pid"), filter '$filter')"
}

capture_stop() {
    local name="$1" dir="$EVIDENCE_DIR/captures" pid i
    local pcap="$EVIDENCE_DIR/$name.pcap"
    [ -s "$dir/$name.pid" ] || { log "capture_stop: $name not running"; return 1; }
    pid=$(cat "$dir/$name.pid")
    sudo -n kill -INT "$pid" 2>/dev/null
    for ((i = 0; i < 30; i++)); do
        sudo -n kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    if sudo -n kill -0 "$pid" 2>/dev/null; then
        log "capture_stop: $name ignored SIGINT, sending SIGTERM"
        sudo -n kill -TERM "$pid" 2>/dev/null; sleep 2
        sudo -n kill -KILL "$pid" 2>/dev/null
    fi
    rm -f "$dir/$name.pid"
    sudo -n chmod a+r "$pcap" 2>/dev/null
    log "capture $name stopped: $(grep -E 'packets (captured|received|dropped)' "$dir/$name.log" | tr '\n' ' ')"
    # pcap global header alone is 24 bytes: non-empty means at least one packet.
    [ "$(stat -c %s "$pcap" 2>/dev/null || echo 0)" -gt 24 ]
}

# e2ap_decode <pcap> <out.txt>: full -V decode, plus <out>.fields.tsv summary.
e2ap_decode() {
    local pcap="$1" out="$2"
    tshark -r "$pcap" -d sctp.port==36422,e2ap -V >"$out" 2>"$out.err" || return 1
    tshark -r "$pcap" -d sctp.port==36422,e2ap -T fields -E header=y -E separator=/t \
        -e frame.number -e frame.time_relative -e ip.src -e ip.dst \
        -e sctp.verification_tag -e sctp.chunk_type -e e2ap.procedureCode -e e2ap.E2AP_PDU \
        >"$out.fields.tsv" 2>>"$out.err"
    [ -s "$out" ]
}

# e2ap_sample_decode <pcap> <procedureCode> <n> <out>: full -V decode of the
# first n frames carrying that E2AP procedure. tshark's -c caps packets READ,
# not packets displayed, so "-Y ... -c n" would stop before the first match.
e2ap_sample_decode() {
    local pcap="$1" code="$2" n="$3" out="$4" frames
    frames=$(tshark -r "$pcap" -d sctp.port==36422,e2ap -Y "e2ap.procedureCode == $code" \
        -T fields -e frame.number 2>/dev/null | head -n "$n" | paste -sd',')
    [ -n "$frames" ] || { : >"$out"; return 1; }
    tshark -r "$pcap" -d sctp.port==36422,e2ap -Y "frame.number in {$frames}" -V >"$out" 2>/dev/null
}

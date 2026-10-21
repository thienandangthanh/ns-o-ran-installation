#!/usr/bin/env bash
# Gate M2 (VM side): reference E2 node (NIST kpm_sim) + golden pcap.
# Proves Docker-bridge -> e2term ClusterIP SCTP is stable for >= 5 min, that tshark
# decodes E2SetupRequest/Response from the capture, and (K10) that two concurrent
# associations from source port 36422 survive NAT/conntrack for 5 min.
#
# NIST scripts used (RIC_DIR = ~/nist/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC):
#   install_scripts/stop_e2sim.sh                 (additional_scripts/ holds a symlink)
#   install_scripts/run_e2sim_and_connect_to_ric.sh (same, via bringup refnode)
#   additional_scripts/fetch_connected_e2_nodes.sh
#   additional_scripts/check_e2ap_version.sh
# Wireshark install is NOT taken from NIST (its script adds the wireshark-dev PPA);
# noble apt tshark is used and the PPA fallback is an orchestrator decision (K15).
#
# Knobs: SUSTAIN_S (default 300) hold after CONNECTED; PROBE_HOLD_S (default 300);
# PROBE_IMAGE (default python:3.12-slim).
source "$(dirname "$0")/lib.sh"
gate_init m2
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"

NIST_DIR="$HOME/nist"
RIC_DIR="$NIST_DIR/RAN_Intelligent_Controllers/Near-Real-Time-RIC"
[ -d "$RIC_DIR" ] || RIC_DIR="$NIST_DIR/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC"
export RIC_DIR
SUSTAIN_S="${SUSTAIN_S:-300}"
PROBE_HOLD_S="${PROBE_HOLD_S:-300}"
PROBE_IMAGE="${PROBE_IMAGE:-python:3.12-slim}"
E2_PORT=36422
GOLDEN="golden-e2setup-sustained"
PROBE_CAP="probe-two-assoc"
PROBE_NAMES="m2probe-a m2probe-b"

# docker as the current user, else via sudo (group membership may not be active yet).

# tshark_count <pcap> <display filter>: number of matching frames on stdout.
tshark_count() { tshark -r "$1" -d "sctp.port==$E2_PORT,e2ap" -Y "$2" 2>/dev/null | wc -l; }

probe_cleanup() { local n; for n in $PROBE_NAMES; do dk rm -f "$n" >/dev/null 2>&1 || true; done; }

################################################################################
# a. tshark from noble apt, non-interactive
################################################################################
install_tshark() {
    if ! command -v tshark >/dev/null 2>&1 || ! command -v tcpdump >/dev/null 2>&1; then
        echo "wireshark-common wireshark-common/install-setuid boolean false" | sudo -n debconf-set-selections || return 1
        sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 apt-get update -q || return 1
        sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 \
            timeout 900 apt-get install -y -q tshark tcpdump </dev/null || return 1
    fi
    command -v tshark && tshark --version | head -n 1
}
check m2_tshark_installed install_tshark

tshark -G protocols >"$EVIDENCE_DIR/tshark-protocols.txt" 2>/dev/null
check m2_tshark_has_e2ap_dissector grep -iwq e2ap "$EVIDENCE_DIR/tshark-protocols.txt"
kpm_lines=$(grep -i kpm "$EVIDENCE_DIR/tshark-protocols.txt" | tr '\t' ' ' | tr '\n' '|')
record m2_tshark_kpm_dissector_informational true \
    "$(tshark --version 2>/dev/null | head -n 1); E2SM-KPM dissector: ${kpm_lines:-ABSENT (K15 PPA fallback is an orchestrator decision)}"

################################################################################
# b. stop the old kpm_sim, start the capture on docker0, then bring up the refnode
################################################################################
check m2_old_refnode_stopped nist_run 180 "$RIC_DIR/install_scripts/stop_e2sim.sh"
check m2_capture_started capture_start "$GOLDEN" docker0 sctp
sleep 2
check m2_refnode_up gate_bringup refnode
CONNECTED_AT=$(date +%s)

################################################################################
# c. NIST's own views of the node
################################################################################
fetch_connected() {
    nist_run 120 "$RIC_DIR/additional_scripts/fetch_connected_e2_nodes.sh" 2>&1 |
        sed 's/\x1b\[[0-9;]*m//g' | tee "$EVIDENCE_DIR/fetch_connected_e2_nodes.txt" >/dev/null
    grep -q '"connectionStatus": *"CONNECTED"' "$EVIDENCE_DIR/fetch_connected_e2_nodes.txt"
}
check m2_fetch_connected_e2_nodes_shows_connected fetch_connected

e2ap_version_report() {
    local s="$RIC_DIR/additional_scripts/check_e2ap_version.sh"
    if [ ! -x "$s" ]; then echo "check_e2ap_version.sh not found at $s"; return 1; fi
    # The script cds to $RIC_DIR and ls-es e2-interface/ and xApps/ there; it may exit
    # non-zero (set -e) when those trees are absent. Output is evidence either way.
    nist_run 60 "$s" >"$EVIDENCE_DIR/check_e2ap_version.txt" 2>&1
    local rc=$?
    cat "$EVIDENCE_DIR/check_e2ap_version.txt"
    return $rc
}
if e2ap_version_report >"$EVIDENCE_DIR/check_e2ap_version.console" 2>&1; then
    record m2_check_e2ap_version_recorded_informational true "$(tr '\n' '|' <"$EVIDENCE_DIR/check_e2ap_version.txt" | cut -c1-600)"
else
    record m2_check_e2ap_version_recorded_informational true \
        "script failed or missing (informational): $(tail -n 3 "$EVIDENCE_DIR/check_e2ap_version.console" | tr '\n' '|')"
fi

################################################################################
# d. sustained association: hold >= SUSTAIN_S after CONNECTED, sampling e2mgr
################################################################################
hold_and_sample() {
    local end=$((CONNECTED_AT + SUSTAIN_S)) bad=0 now
    : >"$EVIDENCE_DIR/e2mgr-samples.txt"
    while now=$(date +%s); [ "$now" -lt "$end" ]; do
        if e2_node_connected; then echo "$(date -u +%T) CONNECTED" >>"$EVIDENCE_DIR/e2mgr-samples.txt"
        else echo "$(date -u +%T) NOT-CONNECTED" >>"$EVIDENCE_DIR/e2mgr-samples.txt"; bad=1; fi
        sleep 30
    done
    echo "held $((now - CONNECTED_AT))s after CONNECTED; samples: $(grep -c . "$EVIDENCE_DIR/e2mgr-samples.txt"), not-connected: $(grep -c NOT "$EVIDENCE_DIR/e2mgr-samples.txt")"
    return $bad
}
check m2_e2mgr_stays_connected_during_hold hold_and_sample
check m2_e2mgr_connected_at_end e2_node_connected
check m2_golden_capture_stopped capture_stop "$GOLDEN"
GP="$EVIDENCE_DIR/$GOLDEN.pcap"

# assert_chunks <label> <filter> <min> <max>: count frames matching in the golden pcap.
assert_chunks() {
    local n
    n=$(tshark_count "$GP" "$2")
    echo "$1 frames: $n (want >= $3, <= $4)"
    [ "$n" -ge "$3" ] && [ "$n" -le "$4" ]
}
check m2_sctp_init_present      assert_chunks INIT      "sctp.chunk_type == 1" 1 99999
check m2_sctp_init_ack_present  assert_chunks INIT_ACK  "sctp.chunk_type == 2" 1 99999
check m2_sctp_heartbeat_present assert_chunks HEARTBEAT "sctp.chunk_type == 4" 1 99999
check m2_sctp_heartbeat_ack_present assert_chunks HEARTBEAT_ACK "sctp.chunk_type == 5" 1 99999
check m2_sctp_sack_present      assert_chunks SACK      "sctp.chunk_type == 3" 1 99999
check m2_sctp_zero_abort        assert_chunks ABORT     "sctp.chunk_type == 6" 0 0

################################################################################
# e. E2AP decode of the golden pcap
################################################################################
check m2_golden_decodes_e2ap e2ap_decode "$GP" "$EVIDENCE_DIR/golden-e2ap-decode.txt"
DEC="$EVIDENCE_DIR/golden-e2ap-decode.txt"

# E2SetupRequest = initiatingMessage / procedureCode 1; E2SetupResponse = successfulOutcome / 1.
has_pdu() {  # <pdu-choice> <message-name-regex>
    awk -v want="$1" -v msg="$2" '
        /^[ ]*E2AP-PDU: / { pdu = $2 }
        $0 ~ "procedureCode: id-E2setup \\(1\\)" && pdu == want { ok = 1 }
        END { exit !ok }' "$DEC" ||
        { grep -q "$1" "$DEC" && grep -q "$2" "$DEC"; }   # dissector wording differs by version
}
check m2_decodes_e2setup_request  has_pdu initiatingMessage E2setupRequest
check m2_decodes_e2setup_response has_pdu successfulOutcome E2setupResponse

# Evidence for later gates: RAN function IDs/OID and global E2 node ID / PLMN.
extract_e2setup_facts() {
    local f="$EVIDENCE_DIR/e2setup-facts.txt"
    {
        echo "--- ranFunctionID / ranFunctionDefinition / ranFunctionOID lines"
        grep -iE 'ranFunctionID|ranFunctionRevision|ranFunctionOID|RANfunction|oid' "$DEC" | sed 's/^[ ]*//' | sort -u | head -n 40
        echo "--- global E2 node ID / PLMN / gNB ID"
        grep -iE 'globalE2node-ID|gNB|pLMN|plmn|mCC|mNC|gNB-ID|nodeId' "$DEC" | sed 's/^[ ]*//' | sort -u | head -n 40
    } >"$f"
    cat "$f"
    grep -qi 'ranFunctionID' "$f"
}
check m2_e2setup_facts_recorded extract_e2setup_facts
record m2_e2setup_ran_functions_informational true \
    "$(grep -iE 'ranFunctionID|ranFunctionOID' "$DEC" | sed 's/^[ ]*//' | sort -u | head -n 8 | tr '\n' '|')"
record m2_e2setup_node_id_informational true \
    "$(grep -iE 'pLMN|gNB-ID|globalE2node' "$DEC" | sed 's/^[ ]*//' | sort -u | head -n 8 | tr '\n' '|')"

################################################################################
# f. K10 two-association probe: two containers, source port 36422 -> e2term ClusterIP
################################################################################
# Resolve the e2term SCTP Service on the VM; never hardcode the IP.
resolve_e2term() {
    kc -n ricplt get svc --no-headers 2>/dev/null | awk '$1 ~ /e2term-sctp/ {print $1, $3; exit}' >"$EVIDENCE_DIR/e2term-sctp-svc.txt"
    kc -n ricplt get svc -o wide >"$EVIDENCE_DIR/ricplt-svc-wide.txt" 2>&1
    E2TERM_SVC=$(awk '{print $1}' "$EVIDENCE_DIR/e2term-sctp-svc.txt")
    E2TERM_IP=$(awk '{print $2}' "$EVIDENCE_DIR/e2term-sctp-svc.txt")
    echo "service $E2TERM_SVC clusterIP $E2TERM_IP"
    [[ "$E2TERM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
check m2_probe_e2term_service_resolved resolve_e2term

PROBE_PY='
import os, select, socket, sys, time
host, port, hold = os.environ["TARGET_IP"], int(os.environ["TARGET_PORT"]), int(os.environ["HOLD_S"])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_SCTP)
s.bind(("", int(os.environ["SRC_PORT"])))
s.settimeout(30)
s.connect((host, port))
print("connected", s.getsockname(), "->", s.getpeername(), flush=True)
t0 = time.time()
while time.time() - t0 < hold:
    r, _, _ = select.select([s], [], [], 1)
    if r:
        try:
            d = s.recv(65535)
        except OSError as e:
            print("peer error", e, flush=True); sys.exit(2)
        if not d:
            print("peer closed after %ds" % (time.time() - t0), flush=True); sys.exit(2)
        print("unexpected data", len(d), flush=True)
s.close()
print("held %ds, closed intentionally" % hold, flush=True)
'

probe_prepare() {
    ip link show docker0 >/dev/null 2>&1 || return 1
    dk image inspect "$PROBE_IMAGE" >/dev/null 2>&1 || timeout 300 $(dk_cmd) pull -q "$PROBE_IMAGE" || return 1
    probe_cleanup
}
check m2_probe_image_ready probe_prepare

probe_run() {
    local n ip rc=0 pids=()
    capture_start "$PROBE_CAP" docker0 sctp || return 1
    sleep 2
    for n in $PROBE_NAMES; do
        dk run -d --name "$n" -e TARGET_IP="$E2TERM_IP" -e TARGET_PORT="$E2_PORT" -e SRC_PORT="$E2_PORT" \
            -e HOLD_S="$PROBE_HOLD_S" "$PROBE_IMAGE" python3 -c "$PROBE_PY" >/dev/null || return 1
    done
    : >"$EVIDENCE_DIR/probe-containers.txt"
    for n in $PROBE_NAMES; do
        PROBE_IP[$n]=$(dk inspect -f '{{.NetworkSettings.IPAddress}}' "$n")
        echo "$n ${PROBE_IP[$n]}" >>"$EVIDENCE_DIR/probe-containers.txt"
    done
    for n in $PROBE_NAMES; do
        ( timeout $((PROBE_HOLD_S + 120)) docker wait "$n" 2>/dev/null || timeout $((PROBE_HOLD_S + 120)) sudo -n docker wait "$n" ) \
            >"$EVIDENCE_DIR/probe-$n.exit" &
        pids+=($!)
    done
    wait "${pids[@]}"
    for n in $PROBE_NAMES; do
        dk logs "$n" >"$EVIDENCE_DIR/probe-$n.log" 2>&1
        echo "$n exit $(cat "$EVIDENCE_DIR/probe-$n.exit")"
        [ "$(cat "$EVIDENCE_DIR/probe-$n.exit")" = 0 ] || rc=1
    done
    return $rc
}
declare -A PROBE_IP
check m2_probe_both_containers_exit_0 probe_run
probe_cleanup
check m2_probe_capture_stopped capture_stop "$PROBE_CAP"
PP="$EVIDENCE_DIR/$PROBE_CAP.pcap"

probe_assoc_ips() {  # one INIT from each container IP, one INIT_ACK back to each
    local n ip bad=0
    for n in $PROBE_NAMES; do
        ip=$(awk -v n="$n" '$1 == n {print $2}' "$EVIDENCE_DIR/probe-containers.txt")
        [ -n "$ip" ] || { echo "$n: no IP"; bad=1; continue; }
        local i a
        i=$(tshark_count "$PP" "sctp.chunk_type == 1 && ip.src == $ip")
        a=$(tshark_count "$PP" "sctp.chunk_type == 2 && ip.dst == $ip")
        echo "$n ($ip): INIT=$i INIT_ACK=$a"
        { [ "$i" -ge 1 ] && [ "$a" -ge 1 ]; } || bad=1
    done
    local ips
    ips=$(awk '{print $2}' "$EVIDENCE_DIR/probe-containers.txt" | sort -u | grep -c .)
    echo "distinct container IPs: $ips"
    [ "$ips" -eq 2 ] && [ "$bad" -eq 0 ]
}
check m2_probe_two_distinct_associations probe_assoc_ips

probe_heartbeats() {
    local n ip c bad=0
    for n in $PROBE_NAMES; do
        ip=$(awk -v n="$n" '$1 == n {print $2}' "$EVIDENCE_DIR/probe-containers.txt")
        c=$(tshark_count "$PP" "sctp.chunk_type == 4 && ip.addr == $ip")
        echo "$n ($ip): HEARTBEAT=$c"
        [ "$c" -ge 1 ] || bad=1
    done
    return $bad
}
check m2_probe_heartbeats_during_hold probe_heartbeats

probe_no_abort() {
    local ip c bad=0
    while read -r _ ip; do
        c=$(tshark_count "$PP" "sctp.chunk_type == 6 && ip.addr == $ip")
        echo "ABORT frames for $ip: $c"
        [ "$c" -eq 0 ] || bad=1
    done <"$EVIDENCE_DIR/probe-containers.txt"
    return $bad
}
check m2_probe_zero_abort probe_no_abort
e2ap_decode "$PP" "$EVIDENCE_DIR/probe-sctp-decode.txt" || true

################################################################################
# g. captures stopped (EXIT trap covers failures above); pcaps hashed by vm-exec
################################################################################
check m2_no_capture_left_running bash -c '! pgrep -x tcpdump >/dev/null'
record m2_pcaps_in_evidence true "$(stat -c '%s %n' "$EVIDENCE_DIR"/*.pcap 2>/dev/null | tr '\n' ';')"

gate_finish

#!/usr/bin/env bash
# Gate i2 (VM side): the install step in front of R2 in the M9 chain: the TS xApp at its pinned commit through
# NIST's installer, switched to gRPC towards rc (G3), A1 policy type 20008, the stub QP xApp (rmr-peer image,
# self-tested), rtmgr restarted with a session to every xApp, and the routes R2 needs:
# 30002 and 20010|20008 to the TS xApp, 30000 to exactly one receiver, the stub.
#
#   gate-i2-ts-xapp-install.sh [--part all|ts|stub]
#
# --part ts installs only the TS xApp (the stray-ack probe runs before any stub exists); --part stub adds the
# stub to an installed TS xApp. The M9 chain runs --part all.
source "$(dirname "$0")/lib.sh"
gate_init i2
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
source "$(dirname "$0")/ts-lib.sh"
PART=all
while [ $# -gt 0 ]; do
    case "$1" in
        --part) PART="$2"; shift 2 ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
case "$PART" in all|ts|stub) ;; *) log "bad --part $PART"; exit 2 ;; esac
fact part "$(json_str "$PART")"
record i2_args true "part $PART; TS pin $TS_SHA; rc pin $RC_SHA; rmr-peer image $RMR_PEER_IMAGE"

# the installer that runs is the Testbed fork's at TESTBED_SHA (substitution 2, if ever applied, lives there)
installer_at_pin() {
    local f=RAN_Intelligent_Controllers/Near-Real-Time-RIC/additional_scripts/install_xapp_traffic_steering.sh
    git -C "$NIST_DIR" cat-file -e "$TESTBED_SHA^{commit}" 2>/dev/null || GIT_TERMINAL_PROMPT=0 git -C "$NIST_DIR" fetch -q origin || return 1
    git -C "$NIST_DIR" diff --quiet "$TESTBED_SHA" -- "$f" || git -C "$NIST_DIR" checkout -q "$TESTBED_SHA" -- "$f" || return 1
    git -C "$NIST_DIR" diff --quiet "$TESTBED_SHA" -- "$f" && echo "$f at $TESTBED_SHA"
}
check i2_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check i2_ts_installer_at_testbed_sha installer_at_pin
check i2_rc_installed_at_pin_and_ready rc_at_pin
SVCS=(service-ricxapp-rc-rmr service-ricxapp-kpimon-go-rmr)
if [ "$PART" != stub ]; then
    check i2_ts_installed_at_pin_switched_to_grpc ts_install
    check i2_a1_policy_type_20008_present ts_policy_type_ensure
fi
check i2_ts_ready_listening_no_control_api_error ts_ready
SVCS+=(service-ricxapp-trafficxapp-rmr)
if [ "$PART" != ts ]; then
    check i2_rmr_peer_image_built_self_tested_imported rmr_peer_build
    check i2_stub_qp_installed_as_its_own_xapp stub_install
    SVCS+=("service-ricxapp-$STUB_NAME-rmr")
fi
sessions() { for _ in $(seq 20); do rtmgr_sessions "${SVCS[@]}" >/dev/null && break; sleep 3; done; rtmgr_sessions "${SVCS[@]}"; }
check i2_rtmgr_session_to_every_xapp sessions
check i2_rc_rmr_ready_after_rtmgr_restart rc_rmr_ready
check i2_route_dump rc_route_dump i2
fact routeOwner12041 "$(json_str "${ROUTE_OWNER_12041:-}")"
fact routeOwner12042 "$(json_str "${ROUTE_OWNER_12042:-}")"
fact routeOwnerE2term12041 "$(json_str "${ROUTE_OWNER_E2TERM_12041:-}")"
fact routeOwnerE2term12042 "$(json_str "${ROUTE_OWNER_E2TERM_12042:-}")"
[ "$PART" = ts ] || check i2_routes_30002_20010_to_ts_30000_only_to_stub ts_routes_check i2
check i2_xapp_image_ids ts_image_ids
fact xappImageIds "$(cat "$EVIDENCE_DIR/xapp-image-ids.json" 2>/dev/null || echo null)"
check i2_pod_snapshot rc_pod_snapshot i2
check i2_restart_counts_zero rc_restarts_zero i2
gate_finish

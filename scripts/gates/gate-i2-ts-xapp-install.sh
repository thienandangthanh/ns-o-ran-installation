#!/usr/bin/env bash
# Gate i2 (VM side): the install step in front of R2 in the M9 chain: the TS xApp at its pinned commit through
# NIST's installer, switched to gRPC towards rc (G3), A1 policy type 20008, the stub QP xApp (rmr-peer image,
# self-tested), both registered with appmgr (neither registers itself), rtmgr restarted with a session to every
# xApp and a1mediator, the routes R2 needs (20010|20008 and 30002 to the TS xApp, one 30000 row from the TS xApp
# to the stub only), and the A1 threshold reaching the TS xApp.
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
record i2_args true "part $PART; TS pin $TS_SHA; substitutions 3 (A1 payload) and 2 (default RMR handler) applied; rc pin $RC_SHA; rmr-peer image $RMR_PEER_IMAGE"

# the installer that runs, and the patches it applies (substitutions 3 and 2), are the Testbed fork's at TESTBED_SHA
installer_at_pin() {
    local d=RAN_Intelligent_Controllers/Near-Real-Time-RIC
    local f=("$d/additional_scripts/install_xapp_traffic_steering.sh" "$d/install_patch_files/xApps/ts")
    git -C "$NIST_DIR" cat-file -e "$TESTBED_SHA^{commit}" 2>/dev/null || GIT_TERMINAL_PROMPT=0 git -C "$NIST_DIR" fetch -q origin || return 1
    git -C "$NIST_DIR" diff --quiet "$TESTBED_SHA" -- "${f[@]}" || git -C "$NIST_DIR" checkout -q "$TESTBED_SHA" -- "${f[@]}" || return 1
    git -C "$NIST_DIR" diff --quiet "$TESTBED_SHA" -- "${f[@]}" && ls "${TS_PATCHES[@]}" >/dev/null && echo "${f[*]} at $TESTBED_SHA"
}
check i2_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check i2_ts_installer_at_testbed_sha installer_at_pin
# start from rc, kpimon and hw-go pods this gate created: a kept pod's start-up line rotates out of its log
check i2_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket rc_ric_reset pre
check i2_rc_installed_at_pin_and_ready rc_at_pin
SVCS=(service-ricxapp-rc-rmr service-ricxapp-kpimon-go-rmr ricplt/service-ricplt-a1mediator-rmr)
if [ "$PART" != stub ]; then
    check i2_ts_installed_at_pin_switched_to_grpc ts_install
    check i2_a1_policy_type_20008_present ts_policy_type_ensure
fi
check i2_ts_source_is_pin_plus_exactly_the_testbed_patches ts_patches_check
fact substitution2Applied true
fact substitution3Applied true
check i2_ts_ready_listening_no_control_api_error ts_ready
SVCS+=(service-ricxapp-trafficxapp-rmr)
if [ "$PART" != ts ]; then
    check i2_rmr_peer_image_built_self_tested_imported rmr_peer_build
    check i2_stub_qp_installed_as_its_own_xapp stub_install
    SVCS+=("service-ricxapp-$STUB_NAME-rmr")
fi
# neither the TS xApp nor the stub registers itself; appmgr lists, so rtmgr routes, only registered xApps.
# Every registration comes before the rtmgr restart: rtmgr reads appmgr's list when it starts.
check i2_ts_xapp_registered_with_appmgr xapp_ensure_registered trafficxapp
[ "$PART" = ts ] || check i2_stub_qp_registered_with_appmgr xapp_ensure_registered "$STUB_NAME"
check i2_appmgr_xapp_list_saved xapp_list_save "$EVIDENCE_DIR/i2-appmgr-xapps.json"
# a1mediator's RMR connection to a replaced TS pod or Service is black-holed, never reconnected in time
check i2_a1mediator_restarted_fresh_policy_type_kept a1mediator_restart i2
fact a1mediatorRestart "$(jq -c '{fresh, problems, after}' "$EVIDENCE_DIR/i2-a1mediator-restart.json" 2>/dev/null || echo null)"
check i2_rtmgr_restarted_after_registration rc_restart_rtmgr
sessions() { for _ in $(seq 20); do rtmgr_sessions "${SVCS[@]}" >/dev/null && break; sleep 3; done; rtmgr_sessions "${SVCS[@]}"; }
check i2_rtmgr_session_to_every_xapp_and_a1mediator sessions
check i2_rc_rmr_ready_after_rtmgr_restart rc_rmr_ready_after_rtmgr
check i2_route_dump rc_route_dump i2
fact routeOwner12041 "$(json_str "${ROUTE_OWNER_12041:-}")"
fact routeOwner12042 "$(json_str "${ROUTE_OWNER_12042:-}")"
fact routeOwnerE2term12041 "$(json_str "${ROUTE_OWNER_E2TERM_12041:-}")"
fact routeOwnerE2term12042 "$(json_str "${ROUTE_OWNER_E2TERM_12042:-}")"
if [ "$PART" = ts ]; then
    check i2_route_20010_20008_to_ts ts_routes_check i2 ts
else
    check i2_routes_20010_to_ts_30002_stub_to_ts_30000_only_ts_to_stub ts_routes_check i2
fi
A1_TH=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["threshold"])' "$HARNESS_DIR/scripts/gates/r2-scenario.json")
check i2_a1_threshold_reaches_ts_xapp ts_policy_set "$A1_TH" "i2-$GATE_TS"
fact a1ThresholdAttempt "$(cat "$EVIDENCE_DIR/i2-$GATE_TS-a1-attempt.txt" 2>/dev/null || echo null)"
fact a1DeliveredAttempt "$(cat "$EVIDENCE_DIR/i2-$GATE_TS-a1-delivered-attempt.txt" 2>/dev/null || echo null)"
check i2_a1mediator_connection_to_ts_xapp_clean a1_ts_connection_check i2
fact a1mediatorRestartCountAtEnd "$(a1mediator_restart_count 2>/dev/null || echo null)"
fact xappRegistration "$(jq -c '[.[] | {name, instances: [.instances[]? | {name, ip, port}]}]' "$EVIDENCE_DIR/i2-appmgr-xapps.json" 2>/dev/null || echo null)"
check i2_xapp_image_ids ts_image_ids
fact xappImageIds "$(cat "$EVIDENCE_DIR/xapp-image-ids.json" 2>/dev/null || echo null)"
check i2_pod_snapshot rc_pod_snapshot i2
check i2_restart_counts_zero rc_restarts_zero i2
gate_finish

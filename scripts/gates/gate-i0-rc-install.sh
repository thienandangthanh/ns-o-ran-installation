#!/usr/bin/env bash
# Gate i0 (VM side): the install step in front of R0 in the M9 chain: the RC wire decoder, pinned grpcurl,
# and rc at its pinned commit through NIST's installer, Ready, answering gRPC describe, with its 12040 route.
# (f7 has only hw-go and kpimon; rc is installed here so M9 reproduces it from fresh-install.)
source "$(dirname "$0")/lib.sh"
gate_init i0
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/rc-lib.sh"
check i0_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check i0_build_tools_present agents_ensure_build_tools
check i0_rc_decoder_builds_and_round_trips bash "$HARNESS_DIR/tools/rc-decode/test-rc-decode.sh"
check i0_grpcurl_fetched_and_checksum_verified rc_grpcurl_fetch
check i0_rc_installed_at_pin_and_ready rc_install
check i0_rc_ready_describe_and_12040_route rc_ready
check i0_route_dump rc_route_dump i0
fact routeOwner12041 "$(json_str "${ROUTE_OWNER_12041:-}")"
fact routeOwner12042 "$(json_str "${ROUTE_OWNER_12042:-}")"
fact routeOwnerE2term12041 "$(json_str "${ROUTE_OWNER_E2TERM_12041:-}")"
fact routeOwnerE2term12042 "$(json_str "${ROUTE_OWNER_E2TERM_12042:-}")"
check i0_pod_snapshot rc_pod_snapshot i0
gate_finish

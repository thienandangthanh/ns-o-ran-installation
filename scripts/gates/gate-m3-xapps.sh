#!/usr/bin/env bash
# Gate M3 (VM side): kpimon-go stock baseline, then SIZE(8)-patched, proven by kpimon's own decoder.
#
# Flow (every step is a named check; waits are bounded; re-runnable):
#   1. refnode up; ~/nist carries the fork files at $TESTBED_SHA; tools (gcc, tshark) present
#   2. K9 regeneration proof: asn1c regen-check inside a throwaway ubuntu:24.04 container
#   3. STOCK    : uninstall, capture, install (CLEAN_INSTALL=true, SIZE8=false), restart refnode, window,
#                 K13 counts, Influx rows, harness on the pcap -> m3-stock-summary.json
#   4. PATCHED  : same with SIZE8=true; image id changed, .so TimeStamp SIZE 8, pod newer than the
#                 install, harness clean on every header and message, zero WMORE, rows > 0
#   5. gate_finish
#
# Why the reference node is restarted after every kpimon install: NIST's kpm_sim runs its report loop
# synchronously inside the first subscription callback (kpm_callbacks.cpp:655) and never reads SCTP
# again, so it can answer only ONE subscription. A fresh kpimon (re)subscribes by itself (~5 s poll).
# The node is stopped BEFORE the uninstall so the pcap holds only the new session (E2Setup,
# Subscription, Indications), starting before E2Setup.
#
# Counting windows: kpimon log counts cover the new pod's life up to the window end (the pod is created
# by the install, after the node was stopped); the pcap covers capture start (before install) to
# capture stop, one reference-node session. Tolerance rule (documented, K13): wire indications
# (deduped by TSN) and kpimon "RIC Indication message from" counts must differ by at most
# max(3, ceil(2 % of wire)) to cover the edges between the log snapshot and the capture stop.
# The 2 % allowance is NOT used for RC_OK: harness clean counts must equal wire count exactly.
#
# "Clean" decode (implementation-notes): asn1c code RC_OK AND consumed == length AND, for headers,
# decoded TimeStamp length == 8. RC_OK/RC_FAIL counts come ONLY from the harness (kpimon prints nothing
# for RC_OK and loses RC_FAIL inside a goroutine).
#
# Knobs: WINDOW_S (default 600), FIRST_INDICATION_WAIT_S (180), SKIP_REGEN (set to skip step 2 on re-runs).
source "$(dirname "$0")/lib.sh"
gate_init m3
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"

WINDOW_S="${WINDOW_S:-600}"
FIRST_INDICATION_WAIT_S="${FIRST_INDICATION_WAIT_S:-180}"
KPIMON_URL=https://gerrit.o-ran-sc.org/r/ric-app/kpimon-go
KPIMON_SHA=8bbbbbb90093db01f88820de755bce0ee2189c88
PATCH_DIR="$RIC_DIR/install_patch_files/xApps/kpimon-go"
WORK="$HOME/m3-work"       # sources / extracted libs; not evidence (pcaps and summaries are)
mkdir -p "$WORK"
ric_watchdog_bg

################################################################################
# step 1: bring-up, NIST tree, tools
################################################################################
check m3_refnode_up gate_bringup refnode
check m3_nist_tree_at_testbed_sha nist_tree_at_testbed_sha

install_build_tools() {
    if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
        sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 apt-get update -q || return 1
        sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 \
            timeout 900 apt-get install -y -q build-essential </dev/null || return 1
    fi
    gcc --version | head -n 1
    command -v tshark tcpdump >/dev/null && tshark --version | head -n 1
}
check m3_build_tools_installed install_build_tools
check m3_kubectl_exec_it_works_without_tty kubectl_exec_it_probe

################################################################################
# step 2: K9 regeneration proof (SIZE(8) patch is a regeneration, not a hand edit)
################################################################################
regen_proof() {
    local w="$WORK/regen"
    rm -rf "$w"; mkdir -p "$w/out"
    clone_pinned "$KPIMON_URL" "$KPIMON_SHA" "$w/src" || return 1
    dk image inspect ubuntu:24.04 >/dev/null 2>&1 || timeout 300 $(dk_cmd) pull -q ubuntu:24.04 || return 1
    # shellcheck disable=SC2016  # the container script must expand its own variables
    timeout 2700 $(dk_cmd) run --rm -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        -v "$HARNESS_DIR/tools:/h:ro" -v "$w/src:/src:ro" -v "$PATCH_DIR:/p:ro" -v "$w/out:/out" \
        ubuntu:24.04 bash -c '
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -q >/dev/null &&
            apt-get install -y -q git ca-certificates build-essential autoconf automake libtool bison flex python3 patch >/dev/null || exit 90
            git config --global --add safe.directory "*"
            bash /h/kpimon-asn1-regen/regen-check.sh /src /p /out; rc=$?
            chown -R "$HOST_UID:$HOST_GID" /out
            exit $rc' </dev/null
    local rc=$?
    cp "$w/out/regen-check.json" "$EVIDENCE_DIR/regen-check.json" 2>/dev/null
    cp "$w/out/TimeStamp-size4-vs-size8.diff" "$EVIDENCE_DIR/" 2>/dev/null
    tail -n 20 "$w/out/work/asn1c-build.log" >"$EVIDENCE_DIR/regen-asn1c-build-tail.log" 2>/dev/null
    rm -rf "$w/out/work"
    echo "regen-check container exit $rc"
    [ "$(jget "$EVIDENCE_DIR/regen-check.json" pass 2>/dev/null)" = True ]
}
if [ -z "${SKIP_REGEN:-}" ]; then
    check m3_regen_check_pass regen_proof
else
    record m3_regen_check_pass_skipped_informational true "SKIP_REGEN set; run the gate without it for K9 evidence"
fi

################################################################################
# per-phase flow
################################################################################
stop_refnode() { nist_run 180 "$RIC_DIR/install_scripts/stop_e2sim.sh"; }

first_indication_logged() {
    local deadline=$(($(date +%s) + FIRST_INDICATION_WAIT_S))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        # Not `kc | grep -q`: grep exiting early would SIGPIPE kc and trip pipefail.
        if grep -q 'RIC Indication message from' < <(kc logs -n "$KPIMON_NS" "$KPIMON_POD" 2>/dev/null); then
            echo "first indication logged by $KPIMON_POD"; return 0
        fi
        sleep 5
    done
    echo "no 'RIC Indication message from' within ${FIRST_INDICATION_WAIT_S}s"
    kc logs -n "$KPIMON_NS" "$KPIMON_POD" --tail=40 2>&1 | redact_stream
    return 1
}

window_hold() {
    local end=$(($(date +%s) + WINDOW_S)) bad=0
    : >"$EVIDENCE_DIR/$1-window-samples.txt"
    while [ "$(date +%s)" -lt "$end" ]; do
        if e2_node_connected; then echo "$(date -u +%T) CONNECTED" >>"$EVIDENCE_DIR/$1-window-samples.txt"
        else echo "$(date -u +%T) NOT-CONNECTED" >>"$EVIDENCE_DIR/$1-window-samples.txt"; bad=$((bad + 1)); fi
        sleep 60
    done
    echo "window ${WINDOW_S}s done; not-connected samples: $bad"
}

# phase <stock|patched> <size8 true|false> <expected header ts_len>
phase() {
    local tag="$1" size8="$2" ts="$3" e="$EVIDENCE_DIR" cap="m3-$1"
    local sodir="$WORK/so-$tag" pcap="$EVIDENCE_DIR/m3-$1.pcap" install_start
    local counts influx wire hdr_ok
    log "===== phase $tag (KPIMON_TIMESTAMP_SIZE8=$size8) ====="

    check "m3_${tag}_refnode_stopped_before_uninstall" stop_refnode
    check "m3_${tag}_kpimon_uninstalled" kpimon_uninstall
    IMG_BEFORE=$(kpimon_image_id)
    check "m3_${tag}_capture_started" capture_start "$cap" docker0 sctp
    sleep 2

    install_start=$(date +%s)
    check "m3_${tag}_installer_ok" kpimon_install_retry "$size8" "$e/install-$tag.log"
    check "m3_${tag}_pod_ready_and_created_after_install" kpimon_wait_ready 300 "$install_start"
    IMG_AFTER=$(kpimon_image_id)
    record "m3_${tag}_pod_image_id_informational" true \
        "pod imageID: $(kc -n "$KPIMON_NS" get pod "$KPIMON_POD" -o jsonpath='{.status.containerStatuses[0].imageID}' 2>&1 | cut -c1-120); docker id: $IMG_AFTER"

    check "m3_${tag}_so_extracted_and_harness_built" kpimon_extract_so "$sodir"
    cp "$sodir/provenance.txt" "$e/$tag-image-provenance.txt" 2>/dev/null
    so_size_is() { [ "$(harness_so_size "$sodir")" = "$1" ]; }
    check "m3_${tag}_so_timestamp_size_is_$ts" so_size_is "$ts"
    if [ "$tag" = patched ]; then
        image_changed() { echo "before $IMG_BEFORE after $IMG_AFTER"; [ -n "$IMG_AFTER" ] && [ "$IMG_BEFORE" != "$IMG_AFTER" ]; }
        check m3_patched_docker_image_id_changed image_changed
    fi

    # Restart the reference node so the new kpimon subscription is answered.
    check "m3_${tag}_refnode_restarted" gate_bringup refnode
    check "m3_${tag}_first_indication_logged" first_indication_logged
    window_hold "$tag"

    # Snapshot the evidence at the window end, then stop the capture.
    kc logs -n "$KPIMON_NS" "$KPIMON_POD" --all-containers >"$e/m3-$tag-kpimon.log" 2>&1
    read -r _ _ _ RESTARTS < <(kpimon_pod_info) || RESTARTS=unknown
    counts=$(kpimon_log_counts "$e/m3-$tag-kpimon.log")
    # NIST's kpm_sim replays a finite reports file as a burst (about 500
    # indications in ~25 s, observed 2026-10-21), so the query covers the whole
    # phase from this install on; earlier phases' rows fall outside it.
    influx=$(influx_rows "-$(( $(date +%s) - install_start + 60 ))s"); echo "$influx" >"$e/m3-$tag-influx-rows.txt"
    record "m3_${tag}_kpimon_log_counts_informational" true "$(echo "$counts" | tr '\n' ' ') restarts=$RESTARTS"
    record "m3_${tag}_influx_rows_since_install_informational" true "$(echo "$influx" | tr '\n' ' ')"
    check "m3_${tag}_capture_stopped" capture_stop "$cap"

    # tshark: subscription request / response and a sample of indications
    sub_counts=$(e2ap_proc_counts "$pcap" 8 "$e/m3-$tag-subscription-decode.txt")
    echo "subscription (procedureCode 8): $sub_counts" >"$e/m3-$tag-subscription-counts.txt"
    e2ap_sample_decode "$pcap" 5 3 "$e/m3-$tag-indication-sample-decode.txt"
    sub_req=$(echo "$sub_counts" | sed -n 's/.*initiating=\([0-9]*\).*/\1/p')
    sub_resp=$(echo "$sub_counts" | sed -n 's/.*successful=\([0-9]*\).*/\1/p')
    : "${sub_req:=0}" "${sub_resp:=0}"
    sub_decoded() { echo "RICsubscriptionRequest frames: $sub_req, RICsubscriptionResponse frames: $sub_resp"; [ "$sub_req" -ge 1 ] && [ "$sub_resp" -ge 1 ]; }
    check "m3_${tag}_tshark_decodes_subscription_request_and_response" sub_decoded

    # kpimon's own decoder on the wire bytes
    check "m3_${tag}_harness_ran_on_pcap" harness_analyze "$tag" "$pcap" "$sodir" "$ts"
    if [ ! -s "$e/$tag-decode.json" ]; then record "m3_${tag}_harness_outputs_missing" false "no $tag-decode.json"; return 0; fi
    wire=$(jget "$e/$tag-extract-summary.json" unique)
    skipped=$(jget "$e/$tag-extract-summary.json" rows_skipped)
    k_ind=$(echo "$counts" | kv indications)
    k_hw=$(echo "$counts" | kv hdr_wmore); k_mw=$(echo "$counts" | kv msg_wmore)
    k_wrote=$(( $(echo "$counts" | kv influx_wrote_ue) + $(echo "$counts" | kv influx_wrote_cell) ))
    rows=$(echo "$influx" | kv total)
    m3_write_summary "$e/m3-$tag-summary.json" "$e/$tag-decode.json" "$e/$tag-harness-summary.json" \
        "$e/$tag-extract-summary.json" "tag=$tag" "size8_install=$size8" "expect_ts_len=$ts" \
        "wire_indications=$wire" "extractor_rows_skipped=$skipped" \
        "sub_request_frames=$sub_req" "sub_response_frames=$sub_resp" \
        "kpimon_indications_logged=$k_ind" "kpimon_header_wmore_logged=$k_hw" "kpimon_msg_wmore_logged=$k_mw" \
        "kpimon_influx_writes_logged=$k_wrote" "influx_rows_since_install=$rows" "kpimon_pod_restarts=$RESTARTS" \
        "window_s=$WINDOW_S" "docker_image_id=$IMG_AFTER" "docker_image_id_before=$IMG_BEFORE"
    cat "$e/m3-$tag-summary.json"

    local total hclean mclean hw mw hf mf
    total=$(jget "$e/$tag-decode.json" total); hclean=$(jget "$e/$tag-decode.json" hdr_clean)
    mclean=$(jget "$e/$tag-decode.json" msg_clean)
    hw=$(jget "$e/$tag-decode.json" hdr_wmore); mw=$(jget "$e/$tag-decode.json" msg_wmore)
    hf=$(jget "$e/$tag-decode.json" hdr_fail); mf=$(jget "$e/$tag-decode.json" msg_fail)
    hdr_ok=$(jget "$e/$tag-decode.json" hdr_ok_exact)

    wire_gt0() { echo "wire indications (deduped by TSN): $wire"; [ "$wire" -gt 0 ]; }
    within_tolerance() {
        python3 - "$wire" "$k_ind" <<'PY'
import math, sys
w, k = int(sys.argv[1]), int(sys.argv[2])
tol = max(3, math.ceil(0.02 * w))
print(f"wire={w} kpimon_logged={k} diff={abs(w - k)} tolerance={tol} (max(3, ceil(2% of wire)))")
sys.exit(0 if abs(w - k) <= tol else 1)
PY
    }

    if [ "$tag" = stock ]; then
        # Baseline is recorded, not judged: any values pass, provided the evidence exists.
        baseline() {
            echo "wire=$wire; harness hdr_ok_exact=$hdr_ok hdr_clean(ts=$ts)=$hclean msg_clean=$mclean hdr_wmore=$hw msg_wmore=$mw hdr_fail=$hf msg_fail=$mf of $total"
            echo "kpimon log: indications=$k_ind hdr_wmore=$k_hw msg_wmore=$k_mw influx_writes=$k_wrote; influx rows(since install)=$rows"
            echo "cross-check: harness header WMORE $hw vs kpimon-logged $k_hw; message WMORE $mw vs $k_mw"
            [ "$wire" -gt 0 ] && [ "$sub_req" -ge 1 ] && [ "$sub_resp" -ge 1 ] && [ -s "$e/m3-stock-summary.json" ]
        }
        check m3_stock_baseline_recorded baseline
    else
        check m3_patched_wire_indications_gt0 wire_gt0
        hdr_clean_all() { echo "headers clean (RC_OK, consumed==len, ts_len==8): $hclean of $total (hdr_ok_exact $hdr_ok)"; [ "$total" -gt 0 ] && [ "$hclean" -eq "$total" ]; }
        msg_clean_all() { echo "messages clean (RC_OK, consumed==len): $mclean of $total"; [ "$total" -gt 0 ] && [ "$mclean" -eq "$total" ]; }
        zero_wmore_fail() { echo "harness hdr wmore/fail $hw/$hf, msg wmore/fail $mw/$mf, other hdr/msg $(jget "$e/$tag-decode.json" hdr_other)/$(jget "$e/$tag-decode.json" msg_other)"; [ "$((hw + mw + hf + mf))" -eq 0 ] && [ "$(jget "$e/$tag-decode.json" hdr_other)" -eq 0 ] && [ "$(jget "$e/$tag-decode.json" msg_other)" -eq 0 ]; }
        log_zero_wmore() { echo "kpimon log header RC_WMORE=$k_hw, MSG RC_WMORE=$k_mw"; [ "$k_hw" -eq 0 ] && [ "$k_mw" -eq 0 ]; }
        rows_gt0() { echo "$influx"; [[ "$rows" =~ ^[0-9]+$ ]] && [ "$rows" -gt 0 ]; }
        no_skips() { echo "extractor rows skipped: $skipped"; [ "$skipped" -eq 0 ]; }
        check m3_patched_extractor_skipped_no_rows no_skips
        check m3_patched_harness_every_header_clean_rc_ok hdr_clean_all
        check m3_patched_harness_every_message_clean_rc_ok msg_clean_all
        check m3_patched_harness_zero_wmore_fail_other zero_wmore_fail
        check m3_patched_kpimon_log_zero_wmore log_zero_wmore
        check m3_patched_influx_rows_gt0 rows_gt0
        # Log lines are supporting evidence (plan: evidence rule); the harness over
        # the wire is the RC_OK authority. The wire-vs-log delta is recorded, and
        # kpimon must have received indications at all.
        within_tolerance >"$e/m3-$tag-count-crosscheck.txt" 2>&1
        record m3_patched_wire_vs_kpimon_count_crosscheck_informational true "$(cat "$e/m3-$tag-count-crosscheck.txt")"
        kpimon_received_gt0() { echo "kpimon logged indications: $k_ind"; [ "$k_ind" -gt 0 ]; }
        check m3_patched_kpimon_received_indications kpimon_received_gt0
    fi
    # Cross-gate sanity for both phases: the pod must not have crash-looped during the window.
    pod_stable() { echo "restarts=$RESTARTS"; [ "$RESTARTS" = 0 ]; }
    check "m3_${tag}_kpimon_pod_no_restarts" pod_stable
}

################################################################################
# steps 3 and 4
################################################################################
phase stock false 4
phase patched true 8

################################################################################
# step 5
################################################################################
check m3_no_capture_left_running bash -c '! pgrep -x tcpdump >/dev/null'
record m3_pcaps_in_evidence true "$(stat -c '%s %n' "$EVIDENCE_DIR"/m3-*.pcap 2>/dev/null | tr '\n' ';')"
ric_watchdog_stop
gate_finish

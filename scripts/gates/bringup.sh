#!/usr/bin/env bash
# Bring-up profiles for gates (sourced after lib.sh, never executed).
#
#   gate_bringup <ric|refnode>
#   gate_bringup agents <node-list> [run_ns3_e2_agents.sh args, e.g. --env K=V]
#                                       node list e.g. gnb:2 or enb:1,gnb:2,gnb:3,gnb:4,gnb:5
#
# `agents` = ric, then stop NIST's kpm_sim (K6), build the agent image if missing, start one
# container per node (run_ns3_e2_agents.sh) and wait (bounded) until the e2mgr CONNECTED set equals
# exactly the expected agent names. Implemented in agents.sh (sourced on first use; it needs
# lib.sh, capture.sh and kpimon.sh sourced already).
#
# `ric`: wait (bounded) until every ricplt pod is Running
# with all containers Ready (Completed job pods are fine), applying the gate
# watchdog from plan.md K3 (delete e2term once if it is the only unready pod
# for > 10 min). The watchdog is also exposed as ric_watchdog_bg/_stop so a
# long install can run under it.
#
# Environment knobs:
#   BRINGUP_TIMEOUT_S      wait bound for gate_bringup ric (default 1200)
#   WATCHDOG_THRESHOLD_S   e2term-only-unready time before the delete (default 600)
#   BRINGUP_POLL_S         poll interval (default 15)

BRINGUP_TIMEOUT_S="${BRINGUP_TIMEOUT_S:-1200}"
WATCHDOG_THRESHOLD_S="${WATCHDOG_THRESHOLD_S:-600}"
BRINGUP_POLL_S="${BRINGUP_POLL_S:-15}"
WATCHDOG_BG_PID=""
_WD_SINCE=0   # epoch when e2term became the only unready pod (per process)

# kc <kubectl args>: kubectl as user uc. NIST's install_k8s_and_helm.sh copies
# admin.conf to $HOME/.kube/config and chowns it to the invoking user, so plain
# kubectl works after install, but KUBECONFIG is only exported inside the
# installer's own shell: pass it explicitly. Fall back to sudo + admin.conf.
# Returns 127 when kubectl or any usable credentials do not exist yet.
kc() {
    command -v kubectl >/dev/null 2>&1 || return 127
    if [ -r "$HOME/.kube/config" ]; then
        KUBECONFIG="$HOME/.kube/config" kubectl "$@"
    elif sudo -n test -r /etc/kubernetes/admin.conf 2>/dev/null; then
        sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl "$@"
    else
        return 127
    fi
}

# ricplt_unready_pods: print names of ricplt pods that are not Running+Ready
# (Completed and Terminating pods are skipped, as NIST does).
# rc 0 = listed (output may be empty), 2 = kubectl failed, 3 = namespace has no pods.
ricplt_unready_pods() {
    local out
    out=$(kc -n ricplt get pods --no-headers 2>/dev/null) || return 2
    [ -n "$out" ] || return 3
    echo "$out" | awk '{
        split($2, a, "/");
        if ($3 == "Terminating" || $3 == "Completed") next;
        if ($3 != "Running" || a[1] != a[2]) print $1
    }'
}

# One watchdog evaluation. State: _WD_SINCE (this process) and an atomic
# mkdir marker so the delete happens at most once per gate run, even if the
# background watchdog and gate_bringup both evaluate.
_ric_watchdog_tick() {
    local unready rc n pod now
    unready=$(ricplt_unready_pods); rc=$?
    n=$(echo "$unready" | grep -c .)
    if [ "$rc" -ne 0 ] || [ "$n" -ne 1 ] || ! echo "$unready" | grep -q 'ricplt-e2term'; then
        _WD_SINCE=0; return 0
    fi
    now=$(date +%s)
    [ "$_WD_SINCE" -ne 0 ] || _WD_SINCE=$now
    [ $((now - _WD_SINCE)) -gt "$WATCHDOG_THRESHOLD_S" ] || return 0
    mkdir "$EVIDENCE_DIR/.watchdog.fired" 2>/dev/null || return 0   # already fired once
    pod="$unready"
    log "WATCHDOG: $pod is the only unready ricplt pod for $((now - _WD_SINCE))s; deleting it once"
    kc -n ricplt delete pod "$pod" --wait=false >>"$EVIDENCE_DIR/watchdog.log" 2>&1
    echo "$(date -u +%FT%TZ) deleted $pod after $((now - _WD_SINCE))s as the only unready ricplt pod" >>"$EVIDENCE_DIR/watchdog.log"
}

# ric_watchdog_bg: run the watchdog in the background until ric_watchdog_stop
# (also killed on EXIT). Tolerates kubectl/cluster not existing yet.
ric_watchdog_bg() {
    [ -z "$WATCHDOG_BG_PID" ] || return 0
    (
        while :; do
            _ric_watchdog_tick 2>/dev/null
            sleep 15
        done
    ) &
    WATCHDOG_BG_PID=$!
    trap ric_watchdog_stop EXIT
    log "ric watchdog started (pid $WATCHDOG_BG_PID, threshold ${WATCHDOG_THRESHOLD_S}s)"
}

ric_watchdog_stop() {
    [ -n "$WATCHDOG_BG_PID" ] || return 0
    pkill -P "$WATCHDOG_BG_PID" 2>/dev/null
    kill "$WATCHDOG_BG_PID" 2>/dev/null
    wait "$WATCHDOG_BG_PID" 2>/dev/null
    log "ric watchdog stopped (pid $WATCHDOG_BG_PID)"
    WATCHDOG_BG_PID=""
}

_bringup_ric() {
    local deadline now unready rc tag missing c
    deadline=$(($(date +%s) + BRINGUP_TIMEOUT_S))
    tag=$(date -u +%H%M%S)
    log "bringup ric: waiting up to ${BRINGUP_TIMEOUT_S}s for ricplt pods"
    while :; do
        _ric_watchdog_tick
        unready=$(ricplt_unready_pods); rc=$?
        if [ "$rc" -eq 0 ] && [ -z "$unready" ]; then
            # Non-vacuous: the core RIC pods must exist, not just "no pod is unready".
            missing=""
            for c in ricplt-e2term ricplt-e2mgr ricplt-rtmgr ricplt-submgr ricplt-appmgr; do
                kc -n ricplt get pods --no-headers 2>/dev/null | grep -q "$c" || missing="$missing $c"
            done
            if [ -z "$missing" ]; then
                kc get pods -A -o wide >"$EVIDENCE_DIR/bringup-pods-wide-$tag.txt" 2>&1
                log "bringup ric: all ricplt pods Ready"
                _wait_e2t_registered || return 1
                _ric_route_readers_ready
                return
            fi
            log "bringup ric: pods missing:$missing"
        else
            log "bringup ric: rc=$rc unready: $(echo "$unready" | tr '\n' ' ')"
        fi
        now=$(date +%s)
        if [ "$now" -ge "$deadline" ]; then
            kc get pods -A -o wide >"$EVIDENCE_DIR/bringup-pods-wide-$tag.txt" 2>&1
            log "bringup ric: TIMEOUT after ${BRINGUP_TIMEOUT_S}s"
            return 1
        fi
        sleep "$BRINGUP_POLL_S"
    done
}

# e2mgr_get <path>: raw JSON of e2mgr's /v1/<path> via the API-server service proxy.
e2mgr_get() {
    kc get --raw "/api/v1/namespaces/ricplt/services/http:service-ricplt-e2mgr-http:3800/proxy/v1/$1" 2>/dev/null
}
# e2mgr_states: raw JSON of /v1/nodeb/states.
e2mgr_states() { e2mgr_get nodeb/states; }

# e2_node_connected: rc 0 when at least one e2mgr node is CONNECTED.
e2_node_connected() {
    e2mgr_states | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if any(n.get("connectionStatus") == "CONNECTED" for n in d) else 1)
' 2>/dev/null
}

REFNODE_RUN_TIMEOUT_S="${REFNODE_RUN_TIMEOUT_S:-600}"   # nist_run bound for the e2sim script
REFNODE_CONNECT_TIMEOUT_S="${REFNODE_CONNECT_TIMEOUT_S:-180}"

# refnode: RIC up, then (re)start NIST's kpm_sim container through NIST's own script.
# The script stops any previous oransim, starts a new one and loops until the
# E2SetupResponse shows in its log, so it is bounded by nist_run. Truth is e2mgr.
E2T_REGISTER_TIMEOUT_S="${E2T_REGISTER_TIMEOUT_S:-600}"
E2T_ROLL_AFTER_S="${E2T_ROLL_AFTER_S:-300}"
E2T_SETTLE_S="${E2T_SETTLE_S:-20}"
# _wait_e2t_registered: pods Ready is not enough. Until e2term has registered
# with e2mgr (an e2tAddress in /v1/e2t/list, after rtmgr is up), an E2 node's
# E2SetupRequest is accepted on SCTP but never answered, and NIST's kpm_sim
# never resends it (observed after cold boots, 2026-10-21). This is NIST's own
# readiness condition from wait_for_ricplt_pods.sh, including its single e2term
# roll when the list stays empty. A short settle lets rtmgr push routes.
_wait_e2t_registered() {
    local start now rolled=0 list
    start=$(date +%s)
    while :; do
        list=$(e2mgr_get e2t/list)
        if [[ "$list" == *'"e2tAddress"'* ]]; then
            log "bringup ric: e2term registered with e2mgr: $list"
            echo "$list" >"$EVIDENCE_DIR/bringup-e2t-list.json"
            sleep "$E2T_SETTLE_S"
            return 0
        fi
        now=$(date +%s)
        if [ "$rolled" = 0 ] && [ $((now - start)) -ge "$E2T_ROLL_AFTER_S" ]; then
            log "bringup ric: no e2term registered after ${E2T_ROLL_AFTER_S}s: rolling e2term once (NIST remedy)"
            echo "$(date -u +%FT%TZ) e2term rolled: e2t/list empty for ${E2T_ROLL_AFTER_S}s" >>"$EVIDENCE_DIR/watchdog.log"
            kc -n ricplt rollout restart deployment/deployment-ricplt-e2term-alpha &&
                kc -n ricplt rollout status deployment/deployment-ricplt-e2term-alpha --timeout=300s
            rolled=1
        fi
        if [ $((now - start)) -ge "$E2T_REGISTER_TIMEOUT_S" ]; then
            log "bringup ric: e2term not registered with e2mgr after ${E2T_REGISTER_TIMEOUT_S}s"
            return 1
        fi
        sleep 5
    done
}

RT_READER_WAIT_S="${RT_READER_WAIT_S:-120}"
RT_READER_SAMPLES="${RT_READER_SAMPLES:-5}"
# ric_pod <component>: the Running ricplt pod whose name contains <component> (e.g. e2mgr, rtmgr).
# ns_pod <ns> <comp>: the first Running pod named <ns>-<comp>-… (ricplt-e2mgr-…, ricxapp-rc-…)
ns_pod() { kc -n "$1" get pods --no-headers | awk -v c="$1-$2-" 'index($1, c) && $3 == "Running" { print $1 }' | head -n 1; }
ric_pod() { ns_pod ricplt "$1"; }

# ric_restart_rtmgr: delete rtmgr's pod and wait for the new one. rtmgr only opens a connection to an
# endpoint the first time it sees it, and never reconnects to a replaced pod, so it restarts after them.
ric_restart_rtmgr() {
    local old name deadline
    old=$(kc -n ricplt get pods --no-headers | awk '/rtmgr/ { print $1 }' | head -n 1)
    [ -n "$old" ] || { echo "no rtmgr pod"; return 1; }
    kc -n ricplt delete pod "$old" --wait=true >/dev/null || return 1
    deadline=$(($(date +%s) + 180))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        name=$(kc -n ricplt get pods --no-headers | awk '/rtmgr/ && $2 == "1/1" && $3 == "Running" { print $1 }' | head -n 1)
        [ -n "$name" ] && [ "$name" != "$old" ] && { echo "rtmgr $old -> $name"; sleep 5; return 0; }
        sleep 3
    done
    echo "rtmgr did not come back"; return 1
}

# rt_reader_ok <comp> <tag> [ns]: the component's RMR route-table reader drains what rtmgr sends it. <comp> is
# e2mgr or submgr in ricplt (the default namespace), or an xApp such as rc in ricxapp: every RMR endpoint
# receives its route table from rtmgr on local port 4561, so rtmgr's own "successful" push log is never enough.
# After a cold boot (2026-10-28, M9 attempt 3, m6) the readers in e2mgr and submgr stopped reading: the
# session from rtmgr stayed ESTABLISHED with ~126 KB unread, so neither a session check nor rtmgr's own
# "successful" log line shows it, and e2mgr had no route for the E2 Setup Response. Pass: an ESTABLISHED
# socket on local port 4561 exists (bounded wait), and every such socket shows rx_queue 0 in at least one
# of RT_READER_SAMPLES samples 2 s apart (a live reader drains each push at once). Rows go to rt-readers-<tag>.txt.
rt_reader_ok() {
    local comp="$1" tag="$2" ns="${3:-ricplt}" pod deadline i out="$EVIDENCE_DIR/rt-readers-$2.txt" samples
    pod=$(ns_pod "$ns" "$comp")
    [ -n "$pod" ] || { echo "rt reader $comp: no Running pod" | tee -a "$out"; return 1; }
    deadline=$(($(date +%s) + RT_READER_WAIT_S))
    until { kc -n "$ns" exec "$pod" -- cat /proc/net/tcp /proc/net/tcp6 2>/dev/null || true; } | awk '$2 ~ /:11D1$/ && $4 == "01" { f = 1 } END { exit !f }'; do
        [ "$(date +%s)" -lt "$deadline" ] || { echo "rt reader $comp $pod: no ESTABLISHED socket on :4561 within ${RT_READER_WAIT_S}s" | tee -a "$out"; return 1; }
        sleep 3
    done
    samples=$(for ((i = 1; i <= RT_READER_SAMPLES; i++)); do
        echo "sample $i"; kc -n "$ns" exec "$pod" -- cat /proc/net/tcp /proc/net/tcp6 2>/dev/null
        [ "$i" -lt "$RT_READER_SAMPLES" ] && sleep 2
    done)
    echo "$samples" | python3 -I -c '
import sys
comp, pod = sys.argv[1], sys.argv[2]
# Judge the sockets of the last sample that holds a /proc/net/tcp header: a failed exec is no evidence.
seen, drained, last, cur, n, ok = {}, set(), set(), set(), 0, False
for line in sys.stdin:
    f = line.split()
    if f[:1] == ["sample"]:
        if ok:
            last = cur
        n += 1; cur = set(); ok = False; continue
    if f[1:2] == ["local_address"]:
        ok = True; continue
    if len(f) < 5 or not f[1].endswith(":11D1") or f[3] != "01":
        continue
    rx = int(f[4].split(":")[1], 16)
    seen.setdefault(f[2], []).append(rx); cur.add(f[2])
    if rx == 0:
        drained.add(f[2])
if ok:
    last = cur
stuck = sorted(r for r in last if r not in drained)
for r in sorted(seen):
    print("rt reader %s %s: peer %s rx_queue %s" % (comp, pod, r, seen[r]))
print("rt reader %s %s: %s (%d samples, %d sockets now, stuck %s)" % (comp, pod, "OK" if last and not stuck else "STUCK", n, len(last), stuck))
sys.exit(0 if last and not stuck else 1)' "$comp" "$pod" | tee -a "$out" | tail -n 1
    return "${PIPESTATUS[1]}"
}

# ric_refresh_routes <level> [--e2term]: replace e2mgr and submgr (pod delete, not a rollout, so no surge copy
# runs beside them), wait for e2term's registration, restart rtmgr last, then require both readers OK. Bounded
# and logged; at most once per level in a gate run (atomic marker). rNIB lives in dbaas, which stays.
# --e2term (after an e2mgr image change): e2term is replaced too, after e2mgr, and e2mgr must log the new e2term's
# E2_TERM_INIT before rtmgr restarts. Seen on the VM (2026-11-03): after the e2mgr pod was replaced under a
# running e2term, e2term's RMR kept a connection to the new pod but no E2 Setup Request reached e2mgr for 10
# minutes; after an e2term restart, setups were received and answered within 3 s.
ric_refresh_routes() {
    local level="$1" with_e2term="${2:-}" e="$EVIDENCE_DIR" tag c old new deadline comps=(e2mgr submgr) since
    [ "$with_e2term" = --e2term ] && comps+=(e2term)
    tag="refresh-$level-$(date -u +%H%M%S)"
    mkdir "$e/.ric-refresh-$level" 2>/dev/null || { log "ric refresh ($level): already used once in this gate run"; return 1; }
    log "ric refresh ($level): replacing ${comps[*]}, then rtmgr"
    echo "$(date -u +%FT%TZ) ric refresh ($level) started" >>"$e/watchdog.log"
    for c in rtmgr e2mgr submgr; do
        kc -n ricplt exec "$(ric_pod $c)" -- cat /proc/net/tcp /proc/net/tcp6 >"$e/$tag-tcp-$c.txt" 2>&1
    done
    e2mgr_get e2t/list >"$e/$tag-e2t-list.json"
    for c in "${comps[@]}"; do
        old=$(ric_pod "$c")
        [ "$c" = e2term ] && since=$(date -u +%FT%TZ)
        kc -n ricplt logs "$old" --since=5m --timestamps >"$e/$tag-$c-before.log" 2>&1
        if [ -z "$old" ] || ! kc -n ricplt delete pod "$old" --wait=true >/dev/null; then log "ric refresh: delete $c failed"; return 1; fi
        deadline=$(($(date +%s) + 180))
        while :; do
            new=$(kc -n ricplt get pods --no-headers | awk -v c="ricplt-$c-" 'index($1, c) && $2 == "1/1" && $3 == "Running" { print $1 }' | head -n 1)
            [ -n "$new" ] && [ "$new" != "$old" ] && { log "ric refresh: $c $old -> $new"; break; }
            [ "$(date +%s)" -lt "$deadline" ] || { log "ric refresh: $c did not come back within 180s"; return 1; }
            sleep 3
        done
    done
    _wait_e2t_registered || return 1
    if [ -n "$since" ]; then
        deadline=$(($(date +%s) + 180))
        until [ "$(kc -n ricplt logs "$(ric_pod e2mgr)" --since-time="$since" 2>/dev/null | grep -c 'handling E2_TERM_INIT')" -gt 0 ]; do
            [ "$(date +%s)" -lt "$deadline" ] || { log "ric refresh: e2mgr logged no E2_TERM_INIT from the new e2term in 180s"; return 1; }
            sleep 3
        done
        log "ric refresh: e2mgr handled the new e2term's E2_TERM_INIT"
    fi
    ric_restart_rtmgr | while read -r l; do log "ric refresh: $l"; done
    [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
    if ! { rt_reader_ok e2mgr "$tag" && rt_reader_ok submgr "$tag"; }; then log "ric refresh ($level): a reader is still stuck"; return 1; fi
    echo "$(date -u +%FT%TZ) ric refresh ($level) done, readers OK" >>"$e/watchdog.log"
    sleep "$E2T_SETTLE_S"
}

# _ric_route_readers_ready: read-only check on every RIC bring-up; the refresh runs only when a reader is stuck.
_ric_route_readers_ready() {
    local tag
    tag="ric-$(date -u +%H%M%S)"
    rt_reader_ok e2mgr "$tag" && rt_reader_ok submgr "$tag" && return 0
    log "bringup ric: an RMR route-table reader is stuck"
    ric_refresh_routes ric
}

REFNODE_ATTEMPTS="${REFNODE_ATTEMPTS:-3}"
# kpm_sim_image_ppid_patched [--rebuild]: NIST's kpm_sim image (oransim:0.0.999) was built with the Testbed's
# SCTP send patch (every E2AP message with PPID 70): its e2sim.sctp.sha256 label equals the sha256 of the patch
# file at $TESTBED_SHA. The installer and the e2-interface patch files are taken from $TESTBED_SHA first (a
# snapshot's tree may be older). --rebuild runs NIST's install_e2sim.sh (bounded 3600 s) when the label differs;
# it restarts docker as NIST's full install does, so only M2 passes it, before kpm_sim starts.
# testbed_tree_to_pin <path>...: the Testbed commit $TESTBED_SHA is present (fetched when missing); a tree with clean
# tracked files and another HEAD moves to it as a whole (M3's nist_tree_at_testbed_sha rule), so later gates find it at
# the pin; the listed paths are then always taken from it (a no-op on a clean tree at the pin), so a tree NIST's
# installer edited still builds from the pinned files.
testbed_tree_to_pin() {
    git -C "$RIC_DIR" cat-file -e "$TESTBED_SHA^{commit}" 2>/dev/null ||
        GIT_TERMINAL_PROMPT=0 git -C "$RIC_DIR" fetch -q "$TESTBED_URL" "$TESTBED_SHA" || return 1
    if [ "$(git -C "$RIC_DIR" rev-parse HEAD)" != "$TESTBED_SHA" ] &&
        [ -z "$(git -C "$RIC_DIR" status --porcelain --untracked-files=no)" ]; then
        git -C "$RIC_DIR" checkout -q --detach "$TESTBED_SHA" || return 1
        echo "clean tree: detached checkout of $TESTBED_SHA"
    fi
    [ $# -eq 0 ] || git -C "$RIC_DIR" checkout "$TESTBED_SHA" -- "$@"
}

kpm_sim_image_ppid_patched() {
    local patch="install_patch_files/e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp" want have
    testbed_tree_to_pin install_scripts/install_e2sim.sh install_patch_files/e2-interface || return 1
    want=$(sha256sum <"$RIC_DIR/$patch" | cut -d' ' -f1)
    have=$(dk image inspect --format '{{index .Config.Labels "e2sim.sctp.sha256"}}' oransim:0.0.999 2>/dev/null)
    echo "oransim:0.0.999 e2sim.sctp.sha256=${have:-<none>}, patch at $TESTBED_SHA: $want"
    if [ "$have" != "$want" ] && [ "${1:-}" = --rebuild ]; then
        log "kpm_sim image lacks the PPID 70 patch: rebuilding with install_e2sim.sh (bound 3600s)"
        (cd "$RIC_DIR" && nist_run 3600 sudo -n ./install_scripts/install_e2sim.sh) >"$EVIDENCE_DIR/install-e2sim.log" 2>&1 ||
            { tail -n 20 "$EVIDENCE_DIR/install-e2sim.log"; return 1; }
        have=$(dk image inspect --format '{{index .Config.Labels "e2sim.sctp.sha256"}}' oransim:0.0.999 2>/dev/null)
        echo "after rebuild: e2sim.sctp.sha256=${have:-<none>}"
    fi
    [ "$have" = "$want" ]
}

# testbed_paths_at_pin <path>...: every path (relative to $RIC_DIR) equals $TESTBED_SHA's: no tracked difference and no
# untracked, non-ignored file. Run before an image is built from, or named after, Testbed files.
testbed_paths_at_pin() {
    git -C "$RIC_DIR" diff --quiet "$TESTBED_SHA" -- "$@" &&
        [ -z "$(git -C "$RIC_DIR" ls-files --others --exclude-standard -- "$@")" ] ||
        { echo "Testbed paths differ from $TESTBED_SHA: $*"; git -C "$RIC_DIR" diff --stat "$TESTBED_SHA" -- "$@"; return 1; }
}

# patchset_safe_relpath <path>: a relative path without "..", as a manifest entry or a patched file must be.
patchset_safe_relpath() { [[ "$1" =~ ^[A-Za-z0-9._][A-Za-z0-9._/+-]*$ && "$1" != *..* ]]; }

# patchset_digest_at_pin <rel-dir> <out-dir>: a Testbed fork patch set (<rel-dir>/patches.manifest and the files it
# lists, paths relative to <rel-dir>) from the Testbed objects at $TESTBED_SHA (git show, not the working tree) into
# <out-dir>. Sets PS_PATCHES (manifest order) and PS_DIGEST (sha256 of the manifest followed by each listed file, in
# manifest order: the installers' rule for the image's patchset.sha256 label).
patchset_digest_at_pin() {
    local rel="$1" d="$2" p
    PS_PATCHES=(); PS_DIGEST=""
    git -C "$RIC_DIR" cat-file -e "$TESTBED_SHA^{commit}" 2>/dev/null ||
        GIT_TERMINAL_PROMPT=0 git -C "$RIC_DIR" fetch -q "$TESTBED_URL" "$TESTBED_SHA" || return 1
    git -C "$RIC_DIR" show "$TESTBED_SHA:./$rel/patches.manifest" >"$d/patches.manifest" ||
        { echo "no $rel/patches.manifest at $TESTBED_SHA"; return 1; }
    mapfile -t PS_PATCHES < <(grep -vE '^\s*(#|$)' "$d/patches.manifest")
    [ "${#PS_PATCHES[@]}" -gt 0 ] || { echo "the $rel manifest at $TESTBED_SHA lists no patch"; return 1; }
    for p in "${PS_PATCHES[@]}"; do
        patchset_safe_relpath "$p" || { echo "bad manifest entry: $p"; return 1; }
        mkdir -p "$d/$(dirname "$p")"
        git -C "$RIC_DIR" show "$TESTBED_SHA:./$rel/$p" >"$d/$p" || { echo "$rel/$p is not at $TESTBED_SHA"; return 1; }
    done
    # shellcheck disable=SC2034  # PS_DIGEST is read by the callers (ts-lib.sh, rc-lib.sh, kpimon.sh)
    PS_DIGEST=$( (cat "$d/patches.manifest" && for p in "${PS_PATCHES[@]}"; do cat "$d/$p"; done) |
        sha256sum | cut -d' ' -f1)
}

# patchset_from_pin <rel-dir> <out-dir>: patchset_digest_at_pin, every listed file a patch; also sets PS_FILES (every
# file the patches change, from their diff headers).
patchset_from_pin() {
    local p f
    PS_FILES=()
    patchset_digest_at_pin "$@" || return 1
    mapfile -t PS_FILES < <(for p in "${PS_PATCHES[@]}"; do git apply --numstat "$2/$p" | cut -f3; done | sort -u)
    [ "${#PS_FILES[@]}" -gt 0 ] || { echo "the $1 patches name no file"; return 1; }
    for f in "${PS_FILES[@]}"; do patchset_safe_relpath "$f" || { echo "bad patched path: $f"; return 1; }; done
}

# tree_is_pin_plus_patchset <repo> <sha> <set-dir> <diff-out> [allowed-path]...: after patchset_from_pin into
# <set-dir>, every file in PS_FILES equals git show <sha>:<file> (absent if <sha> lacks it) plus PS_PATCHES in
# manifest order, byte for byte, and the repo's tracked changes to <sha> (staged or not) are within PS_FILES and the
# allowed paths. Writes the repo's diff of PS_FILES to <diff-out>.
tree_is_pin_plus_patchset() {
    local repo="$1" sha="$2" set="$3" out="$4" t p f unexpected rc=0
    shift 4
    git -C "$repo" diff "$sha" -- "${PS_FILES[@]}" >"$out" || return 1
    t=$(mktemp -d) || return 1
    # a repository of its own, so git apply resolves the paths against it whatever the temp dir's parents are
    git init -q "$t" || { rm -rf "$t"; return 1; }
    for f in "${PS_FILES[@]}"; do
        git -C "$repo" cat-file -e "$sha:$f" 2>/dev/null || continue
        mkdir -p "$t/$(dirname "$f")"
        git -C "$repo" show "$sha:$f" >"$t/$f" || { rm -rf "$t"; return 1; }
    done
    for p in "${PS_PATCHES[@]}"; do
        (cd "$t" && git apply --whitespace=nowarn "$set/$p") ||
            { echo "$p does not apply to the pinned files in manifest order"; rm -rf "$t"; return 1; }
    done
    for f in "${PS_FILES[@]}"; do
        cmp -s "$t/$f" "$repo/$f" || { echo "$f is not the pinned file plus exactly its patches"; rc=1; }
    done
    rm -rf "$t"
    unexpected=$(git -C "$repo" diff --name-only "$sha" | grep -vxF -f <(printf '%s\n' "$@" "${PS_FILES[@]}"))
    [ -z "$unexpected" ] || { echo "tracked change outside the patch set: $(echo "$unexpected" | paste -sd' ')"; rc=1; }
    return "$rc"
}

# The E2 Manager image built by the Testbed's install_scripts/install_e2mgr_patched.sh: its release, and the paths
# its build reads.
E2MGR_RELEASE=6.0.6
E2MGR_PATHS=(install_scripts/install_e2mgr_patched.sh install_patch_files/ric-plt/e2mgr commit_hashes.json)

# e2mgr_patched_expected: "<image> <source sha> <patch-set sha256>" from the Testbed objects at $TESTBED_SHA (git show,
# not the working tree), by the install script's rule: the source commit pinned for ric-plt/e2mgr.git in
# commit_hashes.json; the digest = sha256 of patches.manifest followed by each listed patch, in manifest order.
e2mgr_patched_expected() {
    local dir=install_patch_files/ric-plt/e2mgr src digest p
    git -C "$RIC_DIR" cat-file -e "$TESTBED_SHA^{commit}" 2>/dev/null ||
        GIT_TERMINAL_PROMPT=0 git -C "$RIC_DIR" fetch -q "$TESTBED_URL" "$TESTBED_SHA" || return 1
    src=$(git -C "$RIC_DIR" show "$TESTBED_SHA:./commit_hashes.json" |
        jq -r '.["https://gerrit.o-ran-sc.org/r/ric-plt/e2mgr.git"][1] // empty') || return 1
    [[ "$src" =~ ^[0-9a-f]{40}$ ]] || { echo "no e2mgr commit in commit_hashes.json at $TESTBED_SHA"; return 1; }
    digest=$( (git -C "$RIC_DIR" show "$TESTBED_SHA:./$dir/patches.manifest" &&
        for p in $(git -C "$RIC_DIR" show "$TESTBED_SHA:./$dir/patches.manifest" | grep -vE '^\s*(#|$)'); do
            git -C "$RIC_DIR" show "$TESTBED_SHA:./$dir/$p" || exit 1
        done) | sha256sum | cut -d' ' -f1) || return 1
    echo "127.0.0.1:80/ric-plt-e2mgr:$E2MGR_RELEASE-nist180-${digest:0:12} $src $digest"
}

# e2mgr_image_patched [--deploy]: the running e2mgr pod runs the patched E2 Manager built from the pin: its image is
# e2mgr_patched_expected's tag, its imageID equals that image's docker ID, the image's labels name the pinned source
# commit and the patch-set digest, and the pod is Ready. --deploy (dev chains on a snapshot, M2 only): when that
# fails, build and import the image with the Testbed script (whose build runs the patch set's unit tests), point the
# r4-e2mgr release at it (helm upgrade --reuse-values), wait for the rollout, refresh the RMR routes (e2mgr and
# submgr replaced, rtmgr last, both readers OK) and judge again. Evidence: e2mgr-image.txt, install-e2mgr.log.
e2mgr_image_patched() {
    local exp img src digest
    exp=$(e2mgr_patched_expected) || { echo "$exp"; return 1; }
    read -r img src digest <<<"$exp"
    _e2mgr_image_judge "$img" "$src" "$digest" && return 0
    [ "${1:-}" = --deploy ] || return 1
    log "e2mgr does not run the patched image $img: deploying it (bound 5400s)"
    testbed_tree_to_pin "${E2MGR_PATHS[@]}" || return 1
    testbed_paths_at_pin "${E2MGR_PATHS[@]}" || return 1
    (cd "$RIC_DIR" && nist_run 5400 ./install_scripts/install_e2mgr_patched.sh) >"$EVIDENCE_DIR/install-e2mgr.log" 2>&1 ||
        { tail -n 30 "$EVIDENCE_DIR/install-e2mgr.log"; return 1; }
    grep -qxF "E2MGR_IMAGE=$img" "$EVIDENCE_DIR/install-e2mgr.log" ||
        { echo "the Testbed script built another image than $img"; tail -n 3 "$EVIDENCE_DIR/install-e2mgr.log"; return 1; }
    helm upgrade r4-e2mgr "$RIC_DIR/ric-dep/helm/e2mgr" -n ricplt --reuse-values \
        --set e2mgr.image.registry=127.0.0.1:80 --set e2mgr.image.name=ric-plt-e2mgr --set "e2mgr.image.tag=${img##*:}" \
        >"$EVIDENCE_DIR/helm-upgrade-e2mgr.log" 2>&1 || { cat "$EVIDENCE_DIR/helm-upgrade-e2mgr.log"; return 1; }
    kc -n ricplt rollout status deployment/deployment-ricplt-e2mgr --timeout=300s || return 1
    ric_refresh_routes e2mgr-image --e2term || return 1
    _e2mgr_image_judge "$img" "$src" "$digest"
}

_e2mgr_image_judge() {
    local img="$1" src="$2" digest="$3" pod pimg pid ready did lsrc ldig
    pod=$(ric_pod e2mgr)
    read -r pimg pid ready < <(kc -n ricplt get pod "$pod" -o \
        jsonpath='{.status.containerStatuses[0].image} {.status.containerStatuses[0].imageID} {.status.containerStatuses[0].ready}' 2>/dev/null)
    did=$(dk image inspect --format '{{.Id}}' "$img" 2>/dev/null)
    lsrc=$(dk image inspect --format '{{index .Config.Labels "e2mgr.source.sha"}}' "$img" 2>/dev/null)
    ldig=$(dk image inspect --format '{{index .Config.Labels "patchset.sha256"}}' "$img" 2>/dev/null)
    {
        echo "expected image $img (source $src, patch set $digest; from $TESTBED_SHA)"
        echo "pod ${pod:-none}: image ${pimg:-none}, imageID ${pid:-none}, ready ${ready:-none}"
        echo "docker image: ID ${did:-none}, e2mgr.source.sha ${lsrc:-none}, patchset.sha256 ${ldig:-none}"
    } | tee "$EVIDENCE_DIR/e2mgr-image.txt"
    [ -n "$pod" ] && [ "$pimg" = "$img" ] && [ -n "$did" ] && [ "$pid" = "$did" ] && [ "$ready" = true ] &&
        [ "$lsrc" = "$src" ] && [ "$ldig" = "$digest" ]
}

# _bringup_refnode: start NIST's kpm_sim and wait until e2mgr lists it CONNECTED.
# kpm_sim sends its E2SetupRequest once and never resends it, so a setup lost
# to a not-yet-routable RIC stalls forever; attempts 2..N restart kpm_sim after
# re-checking RIC readiness (which includes e2term registration with e2mgr).
# Every attempt is logged to bringup-refnode-attempts.log.
_bringup_refnode() {
    local ric_dir="${RIC_DIR:-$HOME/nist/RAN_Intelligent_Controllers/Near-Real-Time-RIC}"
    local deadline rc attempt
    _bringup_ric || return 1
    for ((attempt = 1; attempt <= REFNODE_ATTEMPTS; attempt++)); do
        if ((attempt > 1)); then
            log "bringup refnode: attempt $attempt: restart kpm_sim"
            nist_run 180 "$ric_dir/install_scripts/stop_e2sim.sh" >>"$EVIDENCE_DIR/run_e2sim.log" 2>&1
            _bringup_ric || return 1
        fi
        log "bringup refnode: attempt $attempt: running NIST run_e2sim_and_connect_to_ric.sh (bound ${REFNODE_RUN_TIMEOUT_S}s)"
        nist_run "$REFNODE_RUN_TIMEOUT_S" "$ric_dir/install_scripts/run_e2sim_and_connect_to_ric.sh" \
            >>"$EVIDENCE_DIR/run_e2sim.log" 2>&1
        rc=$?
        log "bringup refnode: run_e2sim script exit $rc"
        deadline=$(($(date +%s) + REFNODE_CONNECT_TIMEOUT_S))
        until e2_node_connected || [ "$(date +%s)" -ge "$deadline" ]; do sleep 5; done
        e2mgr_states >"$EVIDENCE_DIR/bringup-e2mgr-states.json"
        if e2_node_connected; then
            echo "$(date -u +%FT%TZ) attempt $attempt CONNECTED" >>"$EVIDENCE_DIR/bringup-refnode-attempts.log"
            # kpm_sim's container IP, so a capture's PPID check can judge kpm_sim's own chunks (kpm_sim_ppid_check).
            dk inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' oransim >"$EVIDENCE_DIR/kpm-sim-ip.txt" 2>/dev/null
            log "bringup refnode: e2mgr shows a CONNECTED node (attempt $attempt)"
            return 0
        fi
        echo "$(date -u +%FT%TZ) attempt $attempt no CONNECTED node after ${REFNODE_CONNECT_TIMEOUT_S}s" >>"$EVIDENCE_DIR/bringup-refnode-attempts.log"
        log "bringup refnode: attempt $attempt: no CONNECTED node after ${REFNODE_CONNECT_TIMEOUT_S}s"
    done
    return 1
}
# agents.sh is sourced lazily so the ric/refnode gates do not need it.
_bringup_agents() {
    type agents_bringup >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/agents.sh"
    agents_bringup "$@"
}

gate_bringup() {
    case "${1:-}" in
        ric) _bringup_ric ;;
        refnode) _bringup_refnode ;;
        agents) _bringup_agents "${2:-}" "${@:3}" ;;
        *) log "gate_bringup: unknown profile '${1:-}'"; return 2 ;;
    esac
}

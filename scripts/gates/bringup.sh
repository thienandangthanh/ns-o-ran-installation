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
ric_pod() { kc -n ricplt get pods --no-headers | awk -v c="ricplt-$1-" 'index($1, c) && $3 == "Running" { print $1 }' | head -n 1; }

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

# rt_reader_ok <e2mgr|submgr> <tag>: the component's RMR route-table reader drains what rtmgr sends it.
# After a cold boot (2026-10-28, M9 attempt 3, m6) the readers in e2mgr and submgr stopped reading: the
# session from rtmgr stayed ESTABLISHED with ~126 KB unread, so neither a session check nor rtmgr's own
# "successful" log line shows it, and e2mgr had no route for the E2 Setup Response. Pass: an ESTABLISHED
# socket on local port 4561 exists (bounded wait), and every such socket shows rx_queue 0 in at least one
# of RT_READER_SAMPLES samples 2 s apart (a live reader drains each push at once). Rows go to rt-readers-<tag>.txt.
rt_reader_ok() {
    local comp="$1" tag="$2" pod deadline i out="$EVIDENCE_DIR/rt-readers-$2.txt" samples
    pod=$(ric_pod "$comp")
    [ -n "$pod" ] || { echo "rt reader $comp: no Running pod" | tee -a "$out"; return 1; }
    deadline=$(($(date +%s) + RT_READER_WAIT_S))
    until { kc -n ricplt exec "$pod" -- cat /proc/net/tcp /proc/net/tcp6 2>/dev/null || true; } | awk '$2 ~ /:11D1$/ && $4 == "01" { f = 1 } END { exit !f }'; do
        [ "$(date +%s)" -lt "$deadline" ] || { echo "rt reader $comp $pod: no ESTABLISHED socket on :4561 within ${RT_READER_WAIT_S}s" | tee -a "$out"; return 1; }
        sleep 3
    done
    samples=$(for ((i = 1; i <= RT_READER_SAMPLES; i++)); do
        echo "sample $i"; kc -n ricplt exec "$pod" -- cat /proc/net/tcp /proc/net/tcp6 2>/dev/null
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

# ric_refresh_routes <ric|agents>: replace e2mgr and submgr (pod delete, not a rollout, so no surge copy
# runs beside them), wait for e2term's registration, restart rtmgr last, then require both readers OK. Bounded
# and logged; at most once per level in a gate run (atomic marker). rNIB lives in dbaas, which stays.
ric_refresh_routes() {
    local level="$1" e="$EVIDENCE_DIR" tag c old new deadline
    tag="refresh-$level-$(date -u +%H%M%S)"
    mkdir "$e/.ric-refresh-$level" 2>/dev/null || { log "ric refresh ($level): already used once in this gate run"; return 1; }
    log "ric refresh ($level): replacing e2mgr and submgr, then rtmgr"
    echo "$(date -u +%FT%TZ) ric refresh ($level) started" >>"$e/watchdog.log"
    for c in rtmgr e2mgr submgr; do
        kc -n ricplt exec "$(ric_pod $c)" -- cat /proc/net/tcp /proc/net/tcp6 >"$e/$tag-tcp-$c.txt" 2>&1
    done
    e2mgr_get e2t/list >"$e/$tag-e2t-list.json"
    for c in e2mgr submgr; do
        old=$(ric_pod "$c")
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

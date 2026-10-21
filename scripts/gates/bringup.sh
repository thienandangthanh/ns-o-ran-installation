#!/usr/bin/env bash
# Bring-up profiles for gates (sourced after lib.sh, never executed).
#
#   gate_bringup <ric|refnode|agents>
#
# Only `ric` is implemented: wait (bounded) until every ricplt pod is Running
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
                return 0
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

_bringup_refnode() { log "bringup refnode: not implemented yet"; return 1; }
_bringup_agents()  { log "bringup agents: not implemented yet"; return 1; }

gate_bringup() {
    case "${1:-}" in
        ric) _bringup_ric ;;
        refnode) _bringup_refnode ;;
        agents) _bringup_agents ;;
        *) log "gate_bringup: unknown profile '${1:-}'"; return 2 ;;
    esac
}

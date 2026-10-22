#!/usr/bin/env bash
# paced-lib.sh: helpers for gates that run ns-3 against the lock-step pacer (VM side). Source after lib.sh,
# agents.sh and agents-ns3-run.sh. The caller sets:
#   e (evidence dir), RUNS (runs dir), CLI (ns-3 arguments common to every run), EPOCH_MS, T_GATE_S, T_CTL_S,
#   PACER_PORT, SINK, PACER, and optionally SINKX / PACERX (extra null-sink and pacer arguments).
#
#   paced_wait_ready <log> <what>         wait for a helper's READY line
#   paced_pacer_finish <pid>              bounded wait for the pacer; PACER_RC = its exit status (call it in the
#                                         shell that started the pacer, never inside $(...))
#   paced_null_run <label> <free|lockstep> <want-ns3-exit> [ns-3 args...]
#                                         one run against the null sink (and, lock-step, the pacer, which must
#                                         exit 0 after a clean run and 3 after an abort); output in $RUNS/<label>
paced_wait_ready() { for _ in $(seq 50); do grep -q READY "$1" && return 0; sleep 0.2; done; echo "$2 did not start: $(cat "$1")"; return 1; }

paced_pacer_finish() {
    for _ in $(seq 150); do kill -0 "$1" 2>/dev/null || break; sleep 0.2; done
    kill "$1" 2>/dev/null; wait "$1"; PACER_RC=$?
}

paced_null_run() {
    local label="$1" pacing="$2" want="$3" rd="$RUNS/$1" sp pp="" rc wantp
    shift 3
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    local sargs=(--ports 38471-38473 --out "$rd/sink" --save-lines "${SINKX[@]}")
    local nargs=("${CLI[@]}" "--simStartEpochMs=$EPOCH_MS" "$@" --e2TraceDir="$rd/trace")
    if [ "$pacing" = lockstep ]; then
        sargs+=(--lockstep)
        nargs+=(--e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S")
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" "${PACERX[@]}" >"$rd/pacer.log" 2>&1 &
        pp=$!
        paced_wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
    fi
    python3 -I "$SINK" "${sargs[@]}" >"$rd/sink.log" 2>&1 &
    sp=$!
    paced_wait_ready "$rd/sink.log" "null sink" || { kill "$sp" $pp; return 1; }
    ns3_start "$rd/ns3run" "${nargs[@]}" || { kill "$sp" $pp; return 1; }
    ns3_wait; rc=$NS3_RC
    [ -z "$pp" ] || paced_pacer_finish "$pp"
    sleep 1; kill -TERM "$sp"; wait "$sp"
    echo "$rc" >"$rd/ns3-exit"
    if [ "$want" = 0 ]; then wantp=0; else wantp=3; fi
    echo "$label ($pacing): ns-3 exit $rc (want $want)${pp:+; pacer exit $PACER_RC (want $wantp)}"
    [ "$rc" = "$want" ] && { [ -z "$pp" ] || [ "$PACER_RC" = "$wantp" ]; }
}

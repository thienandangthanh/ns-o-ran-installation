#!/usr/bin/env bash
# Gate N4 (VM side): the en-gNB cells' PDCP SDU volumes in cell.cuUp, no RIC: DRB.PdcpSduVolumeX2UL/X2DL, counted at
# the en-gNB's X2-U boundary, and DRB.PdcpSduVolumeUL/DL, which are 0. Two free runs in the rung radio config
# (agents' IPC goes to the null sink) at the pins.conf ns-3 and oran-interface SHAs:
#   uloff  UL traffic off: equal to the UL-off reference REF (the last free-run at the pre-N4 pins, K19) on the
#          ns-3 traces and on the IPC samples after the strict drop of exactly the four gNB cuUp PDCP SDU volume keys
#          (digest-run.py --n4-ul-off-drop); same trace file names; no N4AUDIT line; provenance at the pins.
#   ulon   UL traffic on (--enableUlTraffic, pattern from --ul-pattern): the per-PDU audit judges the counters
#          (check-pdcp-volume-totals.py, V3), and the UL flag creates no RandomVariable: ues.txt, enbs.txt,
#          CellIdStats.txt and MmWaveSwitchStats.txt equal uloff's, and X2Stats.txt lines before 0.1 s too.
#
# --part v3: the same uloff and ulon free runs with the rung radio config's own UL pattern and RngRun, judged by
# everything above except the comparison with a reference: no-audit on uloff, V3 and the no-RandomVariable check on
# ulon. The reference-equality checks it does not evaluate are recorded as the fact notEvaluated.
# The V5 window rule needs pandas and runs on the host on the archived ulon IPC trace.
#
# --part dump (K18, step 7): one null-control lock-step run in the same config with UL on, through the agents
# enb:1, gnb:2, gnb:3 and kpimon from a fresh RIC state (kpimon restarted, so the run first gates every agent's
# re-subscription, K13); restart counts 0 before and after; then the whole kpimon bucket as annotated CSV
# (n4-ul-on-dump.csv, token-checked on the VM, V6) and its IPC samples equal to the calibration run CAL's
# (null-control equivalence with UL on). The V5 rule runs on the host on that dump.
#
# --part determinism: two builds of the same source give byte-equal runs. uloff and ulon free runs (null sink; UL
# pattern and RngRun from rung-config.json) on the M4 build A twice (a1, a2) and once (b1) on build B, a fresh
# build-ns3.sh build at the same pins in $HOME/n4-twin-build that loads only its own libraries. n4-run-byte-identity.py
# judges a1 = a2 and a1 = b1 per config on its fixed compared set; uloff-a1 against ulon-a1 must differ. B's tree is
# removed at the end (also on an early exit); the a1 manifests are copied into the evidence dir.
#
# --part identity: a build that must change no wire byte gives the runs of the banked determinism reference. uloff and
# ulon once on the M4 build, in the determinism part's config, each compared by n4-run-byte-identity.py with the
# reference's a1 manifest (N4_IDENTITY_REF, SHA256SUMS checked first) on the same compared set except the audit header
# line, which the build may change on purpose; that line is judged on the ulon run by check-pdcp-volume-totals.py. The
# emitter pins are not a compared item: they must be the pins.conf pair.
#
#   gate-n4-ul-metric.sh --ref <VM dir of the reference run> [--ul-pattern constant|steps] [--dev]
#   gate-n4-ul-metric.sh --part dump --cal <VM dir of the ulon calibration run> [--ul-pattern constant|steps] [--dev]
#   gate-n4-ul-metric.sh --part determinism [--dev]
#   gate-n4-ul-metric.sh --part identity [--dev]
#   gate-n4-ul-metric.sh --part v3 [--dev]
# shellcheck disable=SC2034  # EPOCH_MS, SINK, PACER, CLI, SINKX, PACERX, PACER_PORT, T_GATE_S and T_CTL_S are read by paced-lib.sh
source "$(dirname "$0")/lib.sh"
gate_init n4
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"
source "$(dirname "$0")/paced-lib.sh"

DEV=0; REF=""; CAL=""; PART=v23; PATTERN=constant; PATTERN_SET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) REF="$2"; shift 2 ;;
        --cal) CAL="$2"; shift 2 ;;
        --part) PART="$2"; shift 2 ;;
        --ul-pattern) PATTERN="$2"; PATTERN_SET=1; shift 2 ;;
        --dev) DEV=1; shift ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
case "$PATTERN" in constant|steps) ;; *) log "bad --ul-pattern $PATTERN"; exit 2 ;; esac
case "$PART" in v23|determinism|identity|v3) ;; dump) source "$(dirname "$0")/rc-lib.sh"; source "$(dirname "$0")/influx-dump.sh" ;;
    *) log "bad --part $PART"; exit 2 ;; esac
e="$EVIDENCE_DIR"; RUNS="$e/runs"; mkdir -p "$RUNS"
CFG="$HARNESS_DIR/scripts/gates/rung-config.py"
# determinism runs the rung radio config's own UL pattern and RngRun, the values the byte-identity and v3 runs reuse
RUN_RNG=1
if [ "$PART" = determinism ] || [ "$PART" = identity ] || [ "$PART" = v3 ]; then
    [ "$PATTERN_SET" = 0 ] || { log "--part $PART takes its UL pattern from rung-config.json, not --ul-pattern"; exit 2; }
    [ "$PART" != v3 ] || [ -z "$REF" ] || { log "--part v3 compares no reference: --ref is refused"; exit 2; }
    PATTERN=$(python3 -I "$CFG" get ul_rate.value.pattern); RNG=$(python3 -I "$CFG" get scenario.RngRun)
    case "$PATTERN" in constant|steps) ;; *) log "bad rung-config ul_rate pattern '$PATTERN'"; exit 2 ;; esac
    [[ "$RNG" =~ ^[0-9]+$ ]] || { log "bad rung-config scenario.RngRun '$RNG'"; exit 2; }
    RUN_RNG=$RNG
fi
EPOCH_MS=$(python3 -I "$CFG" get scenario.simStartEpochMs)
THRESH=$(python3 -I "$CFG" get scenario.outageThreshold_dB)
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
PACER="$HARNESS_DIR/scripts/gates/pacer.py"
SIM_TIME_S=10
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto "--simTime=$SIM_TIME_S" "--outageThreshold=$THRESH")
SINKX=(); PACERX=(); PACER_PORT=38499; T_GATE_S=10; T_CTL_S=30
G="$HARNESS_DIR/scripts/gates"
fact dev "$([ "$DEV" = 1 ] && echo true || echo false)"
fact part "$(json_str "$PART")"
fact reference "$(json_str "$REF")"
fact calibration "$(json_str "$CAL")"
fact ulPattern "$(json_str "$PATTERN")"
fact outageThresholdDb "$THRESH"
fact vmLoadStart "$(json_str "$(uptime)")"
record n4_args true "part $PART; dev $DEV; ref $REF; cal $CAL; UL pattern $PATTERN; ns-3 $NS3_SHA; oran-interface $ORAN_INTERFACE_SHA"

# the reference is a UL-off free run whose emitter is not the gated pins (it predates the counters)
ref_ok() {
    [ -d "$REF/trace" ] && [ -d "$REF/ns3run" ] || { echo "no run under $REF"; return 1; }
    python3 -I - "$REF/trace" "$NS3_SHA" <<'PY'
import json, pathlib, sys
shas = set()
for p in pathlib.Path(sys.argv[1]).glob("e2-ipc-trace-*.jsonl"):
    h = json.loads(p.open().readline())
    shas.add(h["emitter"]["ns3Sha"])
print("reference emitter ns-3", sorted(shas))
sys.exit(0 if shas and sys.argv[2] not in shas else 1)
PY
}
[ "$PART" = v23 ] && check n4_reference_is_a_pre_n4_free_run ref_ok
check n4_build_tools_present agents_ensure_build_tools
check n4_ns3_binary_located_at_pins agents_ns3_locate

emitter_at_pins() {
    python3 -I - "$RUNS/$1/trace" "$NS3_SHA" "$ORAN_INTERFACE_SHA" <<'PY'
import json, pathlib, sys
got = set()
for p in pathlib.Path(sys.argv[1]).glob("e2-ipc-trace-*.jsonl"):
    em = json.loads(p.open().readline())["emitter"]
    got.add((em["ns3Sha"], em["oranInterfaceSha"]))
print("emitter", sorted(got))
sys.exit(0 if got == {(sys.argv[2], sys.argv[3])} else 1)
PY
}

no_stray() {
    local bad=0
    pgrep -f "scenario-zero" && bad=1
    pgrep -f ipc-null-sink && bad=1
    pgrep -f "gates/pacer.py" && bad=1
    [ -z "$(dk ps -aq --filter label=ns3e2.agent=1)" ] || { echo "agent container left"; bad=1; }
    ss -Sanp 2>/dev/null | grep -E ':3847[0-9]|:38499' && bad=1
    [ "$bad" = 0 ] && echo "no leftovers"
    return $bad
}

################################################################################
# dump: the K18 UL-on Influx dump for QP
################################################################################
if [ "$PART" = dump ]; then
    NODES="enb:1,gnb:2,gnb:3"; rd="$RUNS/dump"
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    cal_ok() { [ -d "$CAL/trace" ] && grep -q '^N4AUDIT v2' "$CAL/ns3run/stdout.txt" && echo "calibration run $CAL is UL on"; }
    check n4_dump_calibration_run_present cal_ok
    check n4_dump_nist_tree_at_testbed_sha agents_tree_at_testbed_sha
    check n4_dump_sctp_module_loaded agents_sctp_module
    check n4_dump_e2_ports_reserved agents_reserve_ports
    check n4_dump_ric_reset_fresh_pods_and_bucket rc_ric_reset dump
    check n4_dump_rc_at_pin_and_ready rc_at_pin
    check n4_dump_agents_connected_set_exact gate_bringup agents "$NODES"
    all_subscribed() {
        local deadline=$(($(date +%s) + 180)) rows
        while [ "$(date +%s)" -lt "$deadline" ]; do
            rows=$(agents_stats_all)
            echo "$rows" | awk '$4 == "READY" && $5 >= 1 { ok++ } END { exit !(ok == 3) }' && { echo "$rows"; return 0; }
            sleep 3
        done
        echo "$rows"; return 1
    }
    check n4_dump_kpimon_resubscribed_every_agent all_subscribed
    check n4_dump_pods_snapshot_before rc_pod_snapshot dump-before
    check n4_dump_restart_counts_zero_before rc_restarts_zero dump-before
    run_it() {
        local pp rc
        python3 -I "$PACER" --port "$PACER_PORT" --out "$rd/pacer" --t-ctl "$T_CTL_S" >"$rd/pacer.log" 2>&1 &
        pp=$!
        paced_wait_ready "$rd/pacer.log" pacer || { kill "$pp"; return 1; }
        ns3_start "$rd/ns3run" "${CLI[@]}" --RngRun=1 "--simStartEpochMs=$EPOCH_MS" --e2AgentHost=127.0.0.1 \
            --e2TraceDir="$rd/trace" --e2Pacing=lockstep "--e2PacerPort=$PACER_PORT" "--e2GateTimeout=$T_GATE_S" \
            --enableUlTraffic=true "--ulTrafficPattern=$PATTERN" || { kill "$pp"; return 1; }
        ns3_wait; rc=$NS3_RC
        paced_pacer_finish "$pp"
        echo "$rc" >"$rd/ns3-exit"
        echo "dump: ns-3 exit $rc, pacer exit $PACER_RC (want 0 and 0)"
        [ "$rc" = 0 ] && [ "$PACER_RC" = 0 ]
    }
    check n4_dump_null_control_lockstep_ul_on_run run_it
    check n4_dump_emitter_at_pins emitter_at_pins dump
    check n4_dump_pods_snapshot_after rc_pod_snapshot dump-after
    check n4_dump_restart_counts_zero_after rc_restarts_zero dump-after
    sleep 5   # kpimon writes each indication as it decodes it; let the last period land
    check n4_dump_agents_stopped agents_stop
    check n4_dump_influx_bucket_dumped_without_token influx_dump "$e/n4-ul-on-dump.csv"
    cal_eq() {
        python3 -I "$G/digest-run.py" --compare --components ipc CAL="$CAL" DUMP="$rd" >"$e/dump-vs-cal.json"
        local rc=$?
        python3 -I -c 'import json,sys; print("all_equal", json.load(open(sys.argv[1]))["all_equal"])' "$e/dump-vs-cal.json"
        return $rc
    }
    check n4_dump_ipc_equals_the_calibration_run cal_eq
    check n4_no_stray_process no_stray
    fact vmLoadEnd "$(json_str "$(uptime)")"
    gate_finish
    exit $?
fi

# det_run <label> [ns-3 args...]: one free null-sink run; then the arguments ns3_start echoed for it, one per line
# with the run dir as <run> (the binary path is not an argument: two builds differ there by construction), and its
# byte manifest, whose preconditions must hold
BYTES="$G/n4-run-byte-identity.py"
det_run() {
    local label="$1" rd="$RUNS/$1" plog="$RUNS/$1.paced-run.log" rc line args; shift
    paced_null_run "$label" free 0 "--RngRun=$RNG" "$@" >"$plog" 2>&1; rc=$?
    cat "$plog"; mv "$plog" "$rd/paced-run.log" || return 1
    [ "$rc" = 0 ] || return 1
    line=$(grep -m 1 '^ns-3 started pid/pgid ' "$rd/paced-run.log"); args=${line#*": $NS3_BIN "}
    [ -n "$line" ] && [ "$args" != "$line" ] || { echo "$label: no ns-3 start line naming $NS3_BIN"; return 1; }
    tr ' ' '\n' <<<"${args//"$rd"/<run>}" >"$rd/ns3-argv.txt"
    python3 -I "$BYTES" manifest "$rd" >/dev/null || return 1
    echo "$label: argv and byte manifest written, preconditions hold"
}

################################################################################
# identity: one uloff and one ulon run byte-equal to the banked determinism reference, except the audit header line
################################################################################
if [ "$PART" = identity ]; then
    IDREF="${N4_IDENTITY_REF:-$HARNESS_DIR/plans/261103-0008-GH-1-post-m9-realism-m10/reference/n4-sn-wrap}"
    UL=(--enableUlTraffic=true "--ulTrafficPattern=$PATTERN")
    fact rngRun "$RNG"
    fact identityReference "$(json_str "$IDREF")"
    # the reference dir's SHA256SUMS, parsed strictly (every line `<64 hex>  <name>`), has exactly one entry for each
    # a1 manifest compared below, and each manifest has that digest; the verified digests become a fact
    ref_sums() {
        python3 -I "$BYTES" verify-reference "$IDREF" n4-run-bytes-uloff-a1.manifest.json \
            n4-run-bytes-ulon-a1.manifest.json >"$e/identity-reference-digests.json"
        local rc=$?
        cat "$e/identity-reference-digests.json"
        return $rc
    }
    id_emitters() {
        local l bad=0
        for l in uloff ulon; do printf '%s: ' "$l"; emitter_at_pins "$l" || bad=1; done
        return $bad
    }
    # id_eq <cfg>: the run against the reference's a1 manifest of that config, without the audit header item
    id_eq() {
        local out="$e/compare-$1-vs-reference-a1.json" rc
        python3 -I "$BYTES" compare --except-audit-header "$RUNS/$1" "$IDREF/n4-run-bytes-$1-a1.manifest.json" >"$out"; rc=$?
        python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("equal", d.get("equal"), "items", d.get("itemsCompared"), "skipped", d.get("skipped"), "differing", (d.get("differing") or [])[:6], "precondition failures", {k: v["failures"] for k, v in (d.get("preconditions") or {}).items()}, "error", d.get("error"))' "$out"
        echo "compare $1 with the reference: exit $rc (want 0)"
        [ "$rc" = 0 ]
    }
    # the audit header line, left out of the comparison, is judged with the ulon run's whole audit
    id_audit() {
        python3 -I "$G/check-pdcp-volume-totals.py" "$RUNS/ulon" --sim-time-s "$SIM_TIME_S" >"$e/identity-ulon-v3.json"
        local rc=$?
        python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print({k: d.get(k) for k in ("hdr","hdrClass","a0","a1","a2","a3","a4","a5")})' "$e/identity-ulon-v3.json"
        return $rc
    }
    check n4_identity_reference_sha256_ok ref_sums
    fact identityReferenceDigests "$(cat "$e/identity-reference-digests.json" 2>/dev/null || echo null)"
    check n4_identity_uloff_free_run det_run uloff
    check n4_identity_ulon_free_run det_run ulon "${UL[@]}"
    check n4_identity_emitters_at_pins id_emitters
    check n4_identity_uloff_byte_equal_to_reference id_eq uloff
    check n4_identity_ulon_byte_equal_to_reference id_eq ulon
    check n4_identity_ulon_pdcp_audit_judge_passes id_audit
    for c in uloff ulon; do
        fact "compare-$c-vs-reference-a1" "$(cat "$e/compare-$c-vs-reference-a1.json" 2>/dev/null || echo null)"
        cp "$RUNS/$c/n4-run-bytes.manifest.json" "$e/n4-run-bytes-$c.manifest.json" || log "no $c manifest to copy"
    done
    check n4_no_stray_process no_stray
    fact vmLoadEnd "$(json_str "$(uptime)")"
    gate_finish
    exit $?
fi

################################################################################
# determinism: byte-equal runs on one build twice (a1, a2) and on a twin build of the same pins (b1)
################################################################################
if [ "$PART" = determinism ]; then
    TWIN="$HOME/n4-twin-build"; T0=$(date +%s)
    NS3_BIN_A="$NS3_BIN"; NS3_BIN_B=""; TWIN_BUILD_S=null; UL=(--enableUlTraffic=true "--ulTrafficPattern=$PATTERN")
    SHA_A=$(sha256sum "$NS3_BIN_A" 2>/dev/null | cut -d' ' -f1)
    fact rngRun "$RNG"
    fact binarySha256A "$(json_str "$SHA_A")"
    # twin_guard: TWIN may be built and removed only when no component of it is a symlink (its physical path equals its
    # lexical one, so an rm can never reach outside it), and it lies apart from build A (neither equal, nor inside it,
    # nor holding it) and is not /, $HOME or one of its ancestors. It runs before any rm and before the EXIT trap.
    twin_guard() {
        local t s a h
        [ -n "$TWIN" ] && [ -n "$M4_WORKDIR" ] || { echo "twin path '$TWIN' or build A path '$M4_WORKDIR' is empty"; return 1; }
        t=$(realpath -m -- "$TWIN") && s=$(realpath -ms -- "$TWIN") && a=$(realpath -m -- "$M4_WORKDIR") &&
            h=$(realpath -m -- "$HOME") || return 1
        [ ! -L "$s" ] && [ "$t" = "$s" ] || { echo "twin path $s is or passes through a symlink (resolves to $t)"; return 1; }
        # compare as directory prefixes with one trailing slash ("/" stays "/", not "//")
        local tp="${t%/}/" ap="${a%/}/" hp="${h%/}/"
        case "$hp" in "$tp"*) echo "twin path $t is \$HOME, / or an ancestor of \$HOME ($h)"; return 1 ;; esac
        case "$tp" in "$ap"*) echo "twin path $t is build A's $a or inside it"; return 1 ;; esac
        case "$ap" in "$tp"*) echo "twin path $t holds build A's $a"; return 1 ;; esac
        echo "twin path $t is apart from build A's $a"
    }
    TWIN_OK=0; TWIN_ID=""; TWIN_GUARD=$(twin_guard) && TWIN_OK=1 && TWIN=$(realpath -ms -- "$TWIN")
    log "$TWIN_GUARD"
    # twin_rm: removes TWIN only while it is still the directory twin_build created in this invocation: not a symlink,
    # no component turned into one, and the device:inode recorded at its creation (the build and the EXIT trap use it)
    twin_rm() {
        [ "$TWIN_OK" = 1 ] && [ -n "$TWIN_ID" ] || { echo "no twin directory of this invocation to remove"; return 1; }
        [ ! -L "$TWIN" ] && [ -d "$TWIN" ] && [ "$(realpath -m -- "$TWIN")" = "$TWIN" ] &&
            [ "$(stat -c %d:%i -- "$TWIN")" = "$TWIN_ID" ] || { echo "refused: $TWIN is no longer the created directory"; return 1; }
        rm -rf -- "$TWIN"
    }
    twin_build() {
        local t rc
        [ "$TWIN_OK" = 1 ] || { echo "refused: $TWIN_GUARD"; return 1; }
        t=$(date +%s)
        # a leftover tree from an earlier run goes first: a real entry at the guarded path, never a symlink
        if [ -L "$TWIN" ]; then echo "refused: $TWIN became a symlink"; return 1; fi
        if [ -e "$TWIN" ]; then
            [ "$(realpath -m -- "$TWIN")" = "$TWIN" ] || { echo "refused: a component of $TWIN became a symlink"; return 1; }
            rm -rf -- "$TWIN"
        fi
        mkdir -- "$TWIN" && TWIN_ID=$(stat -c %d:%i -- "$TWIN") || { echo "cannot create $TWIN"; return 1; }
        timeout --kill-after=60 1800 bash "$HARNESS_DIR/scripts/build-ns3.sh" "$TWIN" \
            >"$e/build-ns3-twin.stdout" 2>"$e/build-ns3-twin.stderr" </dev/null; rc=$?
        TWIN_BUILD_S=$(($(date +%s) - t)); NS3_BIN_B=$(tail -n 1 "$e/build-ns3-twin.stdout")
        tail -n 3 "$e/build-ns3-twin.stderr"
        echo "build-ns3.sh $TWIN: exit $rc after ${TWIN_BUILD_S}s; binary $NS3_BIN_B"
        [ "$rc" = 0 ] && [ -x "$NS3_BIN_B" ]
    }
    twin_fresh() {
        local s="$TWIN/ns-3"
        [ "$TWIN_OK" = 1 ] || { echo "refused: $TWIN_GUARD"; return 1; }
        echo "$TWIN_GUARD"
        case "$NS3_BIN_B" in "$s/build/scratch/"?*) ;; *) echo "twin binary '$NS3_BIN_B' is not under $s"; return 1 ;; esac
        [ "$(git -C "$s" rev-parse HEAD)" = "$NS3_SHA" ] &&
            [ "$(git -C "$s/contrib/oran-interface" rev-parse HEAD)" = "$ORAN_INTERFACE_SHA" ] || { echo "twin tree not at the pins"; return 1; }
        [ "$(stat -c %Y "$NS3_BIN_B")" -ge "$T0" ] && [ "$(stat -c %Y "$NS3_BIN_A")" -lt "$T0" ] ||
            { echo "mtimes: twin binary $(stat -c %Y "$NS3_BIN_B"), A's $(stat -c %Y "$NS3_BIN_A"), part start $T0"; return 1; }
        echo "twin tree at ns-3 $NS3_SHA, oran-interface $ORAN_INTERFACE_SHA; its binary built in this part, A's before it"
    }
    # every later run uses B's binary and B's build/lib alone (A's lib dir, exported by agents_ns3_locate, would
    # otherwise win over the binary's runpath); ldd must resolve every libns3* inside B's tree
    twin_libs() {
        NS3_BIN="$NS3_BIN_B"; NS3_BIN_RE=""
        [ -z "$NS3_BIN" ] || NS3_BIN_RE="^$(printf '%s' "$NS3_BIN" | sed 's/[][\.*^$+?(){}|/]/\\&/g')( |\$)"
        export LD_LIBRARY_PATH="$TWIN/ns-3/build/lib"
        [ -x "$NS3_BIN" ] || { echo "no twin binary"; return 1; }
        { echo "binary $NS3_BIN"; sha256sum "$NS3_BIN"; echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"; ldd "$NS3_BIN"; } \
            >"$e/ns3-binary-provenance-twin.txt" 2>&1 || { cat "$e/ns3-binary-provenance-twin.txt"; return 1; }
        awk -v t="$TWIN/" '$1 ~ /^libns3/ { n++; if (index($3, t) == 1) inside++; else print "outside the twin tree: " $0 }
            END { printf "libns3 libraries %d, resolved inside %s %d\n", n, t, inside; exit !(n > 0 && inside == n) }' \
            "$e/ns3-binary-provenance-twin.txt"
    }
    # the SHA tuple of every run's emitters; each run's node coverage ({1..n+1} IPC traces and UE context files, each
    # sample stream non-empty) is a manifest precondition, enforced in det_run and again in every det_eq
    all_emitters() {
        local l bad=0
        for l in uloff-a1 ulon-a1 uloff-a2 ulon-a2 uloff-b1 ulon-b1; do printf '%s: ' "$l"; emitter_at_pins "$l" || bad=1; done
        return $bad
    }
    # det_eq <run> <run> <wanted exit>: n4-run-byte-identity.py compare, its report in compare-<run>-vs-<run>.json
    det_eq() {
        local out="$e/compare-$1-vs-$2.json" rc
        python3 -I "$BYTES" compare "$RUNS/$1" "$RUNS/$2" >"$out"; rc=$?
        python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("equal", d.get("equal"), "differing", (d.get("differing") or [])[:6], "precondition failures", {k: v["failures"] for k, v in (d.get("preconditions") or {}).items()})' "$out"
        echo "compare $1 $2: exit $rc (want $3)"
        [ "$rc" = "$3" ]
    }
    twin_remove() {
        [ "$TWIN_OK" = 1 ] || { echo "nothing removed, the twin path was refused: $TWIN_GUARD"; return 1; }
        twin_rm && [ ! -e "$TWIN" ] && [ ! -L "$TWIN" ] && echo "removed $TWIN"
    }

    check n4_determinism_uloff_a1_free_run det_run uloff-a1
    check n4_determinism_ulon_a1_free_run det_run ulon-a1 "${UL[@]}"
    check n4_determinism_uloff_a2_free_run det_run uloff-a2
    check n4_determinism_ulon_a2_free_run det_run ulon-a2 "${UL[@]}"
    if [ "$TWIN_OK" = 1 ]; then
        prev_exit_trap=$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT\$/\1/")
        # shellcheck disable=SC2064  # the previous trap is expanded now; the twin goes on every exit, also a timeout stop
        trap "twin_rm >/dev/null 2>&1; $prev_exit_trap" EXIT
    fi
    check n4_determinism_twin_build_exit0 twin_build
    check n4_determinism_twin_tree_fresh_at_pins twin_fresh
    check n4_determinism_twin_loads_only_its_own_libraries twin_libs
    check n4_determinism_uloff_b1_free_run det_run uloff-b1
    check n4_determinism_ulon_b1_free_run det_run ulon-b1 "${UL[@]}"
    check n4_determinism_emitters_at_pins all_emitters
    check n4_determinism_uloff_same_binary_twice_byte_equal det_eq uloff-a1 uloff-a2 0
    check n4_determinism_uloff_two_builds_byte_equal det_eq uloff-a1 uloff-b1 0
    check n4_determinism_ulon_same_binary_twice_byte_equal det_eq ulon-a1 ulon-a2 0
    check n4_determinism_ulon_two_builds_byte_equal det_eq ulon-a1 ulon-b1 0
    check n4_determinism_compare_discriminates det_eq uloff-a1 ulon-a1 1
    SHA_B=$(sha256sum "$NS3_BIN_B" 2>/dev/null | cut -d' ' -f1)
    fact binarySha256B "$(json_str "$SHA_B")"
    if [ -z "$SHA_A" ] || [ -z "$SHA_B" ]; then fact twinBinaryBitIdentical null
    elif [ "$SHA_A" = "$SHA_B" ]; then fact twinBinaryBitIdentical true; else fact twinBinaryBitIdentical false; fi
    fact twinBuildDurationS "$TWIN_BUILD_S"
    for pair in uloff-a1-vs-uloff-a2 uloff-a1-vs-uloff-b1 ulon-a1-vs-ulon-a2 ulon-a1-vs-ulon-b1 uloff-a1-vs-ulon-a1; do
        fact "compare-$pair" "$(cat "$e/compare-$pair.json" 2>/dev/null || echo null)"
    done
    for c in uloff ulon; do   # the a1 manifests, the baseline the later byte-identity runs are compared with
        cp "$RUNS/$c-a1/n4-run-bytes.manifest.json" "$e/n4-run-bytes-$c-a1.manifest.json" || log "no $c-a1 manifest to copy"
    done
    check n4_determinism_twin_tree_removed twin_remove
    check n4_no_stray_process no_stray
    fact vmLoadEnd "$(json_str "$(uptime)")"
    gate_finish
    exit $?
fi

################################################################################
# uloff: V2 (v3: no reference comparison)
################################################################################
[ "$PART" = v3 ] && fact rngRun "$RNG"
check n4_uloff_free_run paced_null_run uloff free 0 "--RngRun=$RUN_RNG"
check n4_uloff_emitter_at_pins emitter_at_pins uloff
v2() {
    python3 -I "$G/digest-run.py" --compare --components ipc,traces --n4-ul-off-drop REF=absent,CAND=present \
        REF="$REF" CAND="$RUNS/uloff" >"$e/v2-digests.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("all_equal", d["all_equal"], json.dumps(d.get("n4Drop")))' "$e/v2-digests.json"
    return $rc
}
same_trace_names() {
    names() { find "$1" -maxdepth 1 -type f ! -name stdout.txt ! -name stderr.txt -printf '%f\n' | sort; }
    diff <(names "$REF/ns3run") <(names "$RUNS/uloff/ns3run") &&
        diff <(cd "$REF/trace" && ls) <(cd "$RUNS/uloff/trace" && ls) && echo "same trace file names"
}
if [ "$PART" = v23 ]; then
    check n4_v2_uloff_equals_reference_after_the_strict_drop v2
    fact v2Digests "$(cat "$e/v2-digests.json" 2>/dev/null || echo null)"
    check n4_v2_same_trace_file_names same_trace_names
else
    NOT_EVALUATED='["n4_reference_is_a_pre_n4_free_run","n4_v2_uloff_equals_reference_after_the_strict_drop","n4_v2_same_trace_file_names"]'
    record n4_v3_reference_equality_not_evaluated true "no reference is compared; not evaluated: $NOT_EVALUATED"
    fact notEvaluated "$NOT_EVALUATED"
fi
no_audit() { local n; n=$(grep -c '^N4AUDIT' "$RUNS/uloff/ns3run/stdout.txt"); echo "N4AUDIT lines: $n"; [ "$n" = 0 ]; }
check n4_v2_uloff_prints_no_audit no_audit

################################################################################
# ulon: V3 and the no-RandomVariable check
################################################################################
check n4_ulon_free_run paced_null_run ulon free 0 "--RngRun=$RUN_RNG" --enableUlTraffic=true "--ulTrafficPattern=$PATTERN"
check n4_ulon_emitter_at_pins emitter_at_pins ulon
v3() {
    python3 -I "$G/check-pdcp-volume-totals.py" "$RUNS/ulon" --sim-time-s "$SIM_TIME_S" >"$e/v3.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print({k: d[k] for k in ("a0","a1","a2","a3","a4","a5","a6","a7","a8","perCellMaxErrBits","periodSumMaxErrKbit","ties","residualBits","badCellRefs","malformedAuditLines","legCounts","x2ulEvents","forwardedEvents","conservation","lateSenderEvents","mnEvents","x2Events","gnbSamples")})' "$e/v3.json"
    return $rc
}
check n4_v3_counters_equal_the_pdcp_audit v3
fact v3 "$(cat "$e/v3.json" 2>/dev/null || echo null)"
no_rv() {
    local f bad=0
    for f in ues.txt enbs.txt CellIdStats.txt MmWaveSwitchStats.txt; do
        cmp -s "$RUNS/uloff/ns3run/$f" "$RUNS/ulon/ns3run/$f" || { echo "$f differs"; bad=1; }
    done
    cmp -s <(awk '$1 < 0.1' "$RUNS/uloff/ns3run/X2Stats.txt") <(awk '$1 < 0.1' "$RUNS/ulon/ns3run/X2Stats.txt") ||
        { echo "X2Stats.txt lines before 0.1 s differ"; bad=1; }
    [ "$bad" = 0 ] && echo "attach, positions, cell ids, switches and X2 before 0.1 s equal"
    return $bad
}
check n4_ul_flag_moves_no_random_draw no_rv
check n4_no_stray_process no_stray
fact vmLoadEnd "$(json_str "$(uptime)")"
gate_finish

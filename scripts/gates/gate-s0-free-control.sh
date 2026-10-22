#!/usr/bin/env bash
# Gate S0 (VM side): the P1 control path in free-run, without the RIC for V1/V3.
#
#   gate-s0-free-control.sh --ref-ns3 SHA --ref-oi SHA --a-ns3 SHA
#
# V1 free-run output unchanged (rule: plans/261023-0009-.../evidence/p1-free-run-reference/v1-rule.md):
#    ref1, ref2 at the P0 pins (--ref-ns3/--ref-oi), a = ns-3 commit A (--a-ns3) with --ref-oi,
#    new = the pins.conf pair; R0 config, null sink, no control; compare-free-run.py.
# V3 scripted free-run control: the new build with ipc-null-sink --controls (no RIC);
#    check-free-control-ledger.py.
# V2 agent unit test: rc-control-test inside the agent image built at TESTBED_SHA; its
#    ACK outcome octets decoded by the independent tools/rc-decode (K23).
# V4 request part: agents enb:1, gnb:2, gnb:3 against the RIC; each gNB's e2mgr
#    e2nodeComponentRequestPart decodes to hex text ending in %08X%02X (gNB id, cell
#    id), the eNB's to 72657170617274 ("reqpart").
#
# Builds: ref in ~/s0-build-ref (taken over from ~/m4-build when that is at the
# reference pins), a in ~/s0-build-a (removed at the end), new in ~/m4-build so
# M5-M7 reuse it. A build is reused only when its HEADs equal the wanted SHAs.
source "$(dirname "$0")/lib.sh"
gate_init s0
source "$(dirname "$0")/bringup.sh"
source "$(dirname "$0")/capture.sh"
source "$(dirname "$0")/kpimon.sh"
source "$(dirname "$0")/agents.sh"

REF_NS3=""; REF_OI=""; A_NS3=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ref-ns3) REF_NS3="$2"; shift 2 ;;
        --ref-oi) REF_OI="$2"; shift 2 ;;
        --a-ns3) A_NS3="$2"; shift 2 ;;
        *) log "unknown arg $1"; exit 2 ;;
    esac
done
e="$EVIDENCE_DIR"
CLI=(--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1)
SINK="$HARNESS_DIR/tools/ipc-null-sink/ipc-null-sink.py"
record s0_args true "ref ns-3 $REF_NS3 oi $REF_OI; a ns-3 $A_NS3; new ns-3 $NS3_SHA oi $ORAN_INTERFACE_SHA; cli ${CLI[*]}"
[ -n "$REF_NS3" ] && [ -n "$REF_OI" ] && [ -n "$A_NS3" ] || { record s0_args_complete false "need --ref-ns3 --ref-oi --a-ns3"; gate_finish; exit $?; }

at_shas() { [ "$(git -C "$1/ns-3" rev-parse HEAD 2>/dev/null)" = "$2" ] && [ "$(git -C "$1/ns-3/contrib/oran-interface" rev-parse HEAD 2>/dev/null)" = "$3" ]; }

# s0_build <workdir> <ns3> <oi>: reuse when at those SHAs, else build-ns3.sh; prints the binary.
s0_build() {
    local wd="$1" ns3="$2" oi="$3" bin
    if ! at_shas "$wd" "$ns3" "$oi"; then
        if [ "$wd" = "$HOME/s0-build-ref" ] && at_shas "$HOME/m4-build" "$ns3" "$oi"; then
            rm -rf "$wd" && mv "$HOME/m4-build" "$wd" || return 1
            echo "took over ~/m4-build (at the reference pins) as $wd"
        else
            timeout --kill-after=60 5400 bash "$HARNESS_DIR/scripts/build-ns3.sh" "$wd" --ns3-sha "$ns3" --oi-sha "$oi" \
                >"$e/build-$(basename "$wd").stdout" 2>"$e/build-$(basename "$wd").stderr" </dev/null || return 1
        fi
    fi
    at_shas "$wd" "$ns3" "$oi" || return 1
    bin=$(find "$wd/ns-3/build/scratch" -maxdepth 1 -type f -perm -u+x -name '*-scenario-zero-*' | head -n 1)
    [ -x "$bin" ] || return 1
    { echo "binary $bin"; echo "ns3 $ns3"; echo "oran-interface $oi"; sha256sum "$bin"; } | tee "$e/provenance-$(basename "$wd").txt"
}

# s0_use <workdir>: point NS3_BIN, NS3_BIN_RE and LD_LIBRARY_PATH (this build only) at a build.
# shellcheck disable=SC2034  # NS3_BIN and NS3_BIN_RE are read by ns3_start/ns3_stray (agents-ns3-run.sh)
s0_use() {
    NS3_BIN=$(find "$1/ns-3/build/scratch" -maxdepth 1 -type f -perm -u+x -name '*-scenario-zero-*' | head -n 1)
    NS3_BIN_RE="^$(printf '%s' "$NS3_BIN" | sed 's/[][\.*^$+?(){}|/]/\\&/g')( |\$)"
    export LD_LIBRARY_PATH="$1/ns-3/build/lib"
}

# s0_run <label> [controls.json]: one free run with the null sink; outputs in $e/runs/<label>.
s0_run() {
    local label="$1" ctl="${2:-}" rd="$e/runs/$1" sp rc
    rm -rf "$rd"; mkdir -p "$rd/ns3run" "$rd/trace"
    local sargs=(--ports 38471-38473 --out "$rd/sink" --save-lines)
    [ -n "$ctl" ] && sargs+=(--controls "$ctl")
    python3 -I "$SINK" "${sargs[@]}" >"$rd/sink.log" 2>&1 &
    sp=$!
    for _ in $(seq 50); do grep -q READY "$rd/sink.log" && break; sleep 0.2; done
    grep -q READY "$rd/sink.log" || { kill "$sp"; echo "null sink did not start: $(cat "$rd/sink.log")"; return 1; }
    ns3_start "$rd/ns3run" "${CLI[@]}" --e2TraceDir="$rd/trace" || { kill "$sp"; return 1; }
    ns3_wait; rc=$NS3_RC
    sleep 1; kill -TERM "$sp"; wait "$sp"
    echo "$label: ns-3 exit $rc; sink $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["totals"])' "$rd/sink/summary.json" 2>/dev/null)"
    [ "$rc" = 0 ]
}

################################################################################
# V1: free-run equality
################################################################################
check s0_build_ref_at_p0_pins s0_build "$HOME/s0-build-ref" "$REF_NS3" "$REF_OI"
s0_use "$HOME/s0-build-ref"
check s0_run_ref1 s0_run ref1
check s0_run_ref2 s0_run ref2
check s0_build_a_commit_a_with_ref_oi s0_build "$HOME/s0-build-a" "$A_NS3" "$REF_OI"
s0_use "$HOME/s0-build-a"
check s0_run_a s0_run a
check s0_build_new_at_pins s0_build "$HOME/m4-build" "$NS3_SHA" "$ORAN_INTERFACE_SHA"
s0_use "$HOME/m4-build"
check s0_run_new s0_run new
v1() {
    python3 -I "$HARNESS_DIR/scripts/gates/compare-free-run.py" ref1="$e/runs/ref1" ref2="$e/runs/ref2" \
        a="$e/runs/a" new="$e/runs/new" >"$e/v1-compare.json"
    local rc=$?
    python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print({k: v["pass"] for k, v in d["candidates"].items()}, "all_pass", d["all_pass"])' "$e/v1-compare.json"
    return $rc
}
check s0_v1_free_run_digest_unchanged_ref2_a_new v1

################################################################################
# V3: scripted free-run control on the new build
################################################################################
cat >"$e/controls.json" <<'JSON'
[
 {"nodeId": 1, "afterSeq": 20, "imsi": 6, "targetCellId": 3},
 {"nodeId": 2, "afterSeq": 20, "imsi": 6, "targetCellId": 3},
 {"nodeId": 3, "afterSeq": 20, "imsi": 1, "targetCellId": 2},
 {"nodeId": 2, "afterSeq": 30, "imsi": 4, "targetCellId": 2},
 {"nodeId": 3, "afterSeq": 30, "imsi": 99, "targetCellId": 2},
 {"nodeId": 2, "afterSeq": 40, "imsi": 3, "targetCellId": 1},
 {"nodeId": 2, "afterSeq": 40, "imsi": 3, "targetCellId": 7},
 {"nodeId": 3, "afterSeq": 60, "imsi": 6, "targetCellId": 3},
 {"nodeId": 2, "afterSeq": 99, "imsi": 4, "targetCellId": 3}
]
JSON
check s0_run_ctl_scripted_controls s0_run ctl "$e/controls.json"
v3() {
    local rd="$e/runs/ctl"
    python3 -I "$HARNESS_DIR/scripts/gates/check-free-control-ledger.py" "$rd/trace/e2-control-ledger.jsonl" \
        "$rd/sink/controls-sent.jsonl" "$rd/sink/control-acks.jsonl" >"$e/v3-ledger-check.json"
    local rc=$?
    cat "$e/v3-ledger-check.json"
    return $rc
}
check s0_v3_one_ledger_line_per_control_d0_c4_sorted_acks_match v3
rm -rf "$HOME/s0-build-a"

################################################################################
# V2 + V4: agent image at TESTBED_SHA, unit test, request parts in e2mgr
################################################################################
check s0_nist_tree_at_testbed_sha_with_agent_dir agents_tree_at_testbed_sha
check s0_build_tools_present agents_ensure_build_tools
check s0_sctp_module_loaded agents_sctp_module
check s0_bringup_agents_enb1_gnb2_gnb3 gate_bringup agents "enb:1,gnb:2,gnb:3"
v2() {
    local img
    img=$(sed -n 's/^NS3_E2_AGENT_IMAGE=//p' "$e/agent-image.env")
    dk run --rm --entrypoint /usr/local/bin/rc-control-test "$img" /usr/local/share/ns3-e2-agent/rc-control-requests.hex \
        >"$e/rc-control-test.out" 2>"$e/rc-control-test.log"
    local rc=$?
    cat "$e/rc-control-test.out"
    local name
    for name in ran-function-id-invalid action-not-supported control-message-invalid control-failed-to-execute \
        format1-on-ack bye-fails-all-pending; do
        grep -qx "PASS $name" "$e/rc-control-test.out" || { echo "missing PASS $name"; rc=1; }
    done
    return $rc
}
check s0_v2_agent_unit_test_all_cause_paths_pass v2
k23() {
    local tag hex
    tag=$(bash "$HARNESS_DIR/tools/rc-decode/build.sh" rc-decode:s0) || return 1
    hex=$(sed -n 's/^OUTCOME_HEX //p' "$e/rc-control-test.out")
    [ -n "$hex" ] || { echo "no OUTCOME_HEX"; return 1; }
    echo "ack outcome $hex" | dk run --rm -i "$tag" | tee "$e/k23-outcome-decode.jsonl" | python3 -I -c '
import json, re, sys
d = json.loads(sys.stdin.readline())
x = re.sub(r"\s+", "", d["xer"])
ok = d["ok"] and "<controlOutcome-Format1><ranP-List></ranP-List></controlOutcome-Format1>" in x
print("agent ACK outcome decodes as Format 1 with an empty ranP-List" if ok else "decode mismatch: %r" % d)
sys.exit(0 if ok else 1)'
}
check s0_k23_agent_outcome_decodes_with_independent_decoder k23
v4() {
    local node want got b64
    local rc=0
    for node in 1 2 3; do
        name=$(printf 'gnb_001_001_%08x' "$node")
        e2mgr_get "nodeb/$name" >"$e/e2mgr-node-$name.json" || { echo "no e2mgr node $name"; rc=1; continue; }
        b64=$(python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1]))
g = d.get("gnb") or d.get("enb") or {}
print(g.get("nodeConfigs", [{}])[0].get("e2nodeComponentRequestPart", ""))' "$e/e2mgr-node-$name.json")
        got=$(printf '%s' "$b64" | base64 -d 2>/dev/null)
        if [ "$node" = 1 ]; then want=72657170617274; else want=$(printf '%08X%02X' "$node" "$node"); fi
        echo "$name request part: base64 $b64 -> \"$got\" (want suffix $want)"
        case "$got" in *"$want") ;; *) rc=1 ;; esac
    done
    return $rc
}
check s0_v4_request_part_gnb_key_enb_reqpart v4
check s0_agents_stopped agents_stop

################################################################################
# hygiene (V6)
################################################################################
no_stray() {
    local bad=0
    pgrep -f "scenario-zero" && bad=1
    pgrep -f ipc-null-sink && bad=1
    [ -z "$(dk ps -aq --filter label=ns3e2.agent=1)" ] || { echo "agent container left"; bad=1; }
    ss -Sanp 2>/dev/null | grep -E ':3847[0-9]' && bad=1
    [ "$bad" = 0 ] && echo "no ns-3, sink, agent or SCTP/3847x leftovers"
    return $bad
}
check s0_v6_no_stray_process no_stray
gate_finish

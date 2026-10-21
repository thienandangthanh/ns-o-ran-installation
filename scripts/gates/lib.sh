#!/usr/bin/env bash
# Shared helpers for VM-side gate scripts (sourced, never executed).
#
# Contract every gate follows:
#   source "$(dirname "$0")/lib.sh"; gate_init m<N>
#   check <name> <command...>      # records one pass/fail line, never aborts
#   gate_finish                    # writes verdict.json, exits 0 on pass, 1 on fail
#
# Environment (set by vm-exec.sh; defaults allow manual runs):
#   EVIDENCE_DIR   where all evidence for this run goes
#   HARNESS_DIR    root of the harness clone (contains scripts/pins.conf)
#   HARNESS_SHA    harness commit under test (recorded in verdict.json)

set -uo pipefail

HARNESS_DIR="${HARNESS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=../pins.conf
source "$HARNESS_DIR/scripts/pins.conf"

gate_init() {
    GATE="$1"
    GATE_TS="${GATE_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
    EVIDENCE_DIR="${EVIDENCE_DIR:-$HOME/evidence/$GATE/$GATE_TS}"
    mkdir -p "$EVIDENCE_DIR"
    CHECKS_FILE="$EVIDENCE_DIR/checks.jsonl"
    : >"$CHECKS_FILE"
    GATE_START_EPOCH=$(date +%s)
    export GATE GATE_TS EVIDENCE_DIR
    # Mirror all gate output into the evidence dir.
    exec > >(tee -a "$EVIDENCE_DIR/gate.log") 2>&1
    log "gate $GATE start; evidence $EVIDENCE_DIR; harness ${HARNESS_SHA:-unknown}"
}

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# JSON-escape a string (stdin or $1) without jq, which fresh-install lacks.
json_str() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

# record <name> <pass:true|false> <detail>
record() {
    local name="$1" pass="$2" detail="$3"
    printf '{"name":%s,"pass":%s,"detail":%s}\n' \
        "$(json_str "$name")" "$pass" "$(json_str "$detail")" >>"$CHECKS_FILE"
    if [ "$pass" = true ]; then log "PASS $name"; else log "FAIL $name: $detail"; fi
}

# check <name> <command...>: run the command, record pass/fail with the last
# lines of its output. Full output goes to checks/<name>.out.
check() {
    local name="$1"; shift
    mkdir -p "$EVIDENCE_DIR/checks"
    local out="$EVIDENCE_DIR/checks/${name//[^A-Za-z0-9_.-]/_}.out"
    if "$@" >"$out" 2>&1; then
        record "$name" true "$(tail -n 3 "$out")"
    else
        record "$name" false "exit $?: $(tail -n 5 "$out")"
    fi
}

# retry <attempts> <delay-s> <command...>: each retry is logged.
retry() {
    local n="$1" delay="$2" i; shift 2
    for ((i = 1; i <= n; i++)); do
        "$@" && return 0
        log "retry $i/$n failed: $*"
        ((i < n)) && sleep "$delay"
    done
    return 1
}

# nist_run <timeout-s> <command...>: unattended NIST call. stdin never reaches
# EOF (busy-loop guard for `read -t`), and the whole call is bounded. The idle
# stdin comes from a process substitution, not a pipeline: bash waits for every
# pipeline member, so `sleep infinity | cmd` would never return.
nist_run() {
    local t="$1"; shift
    timeout --kill-after=60 "$t" "$@" < <(exec sleep $((t + 120)))
}

# disk_guard: VM / must keep >= 25 % free; prune docker build cache if docker exists.
disk_guard() {
    if command -v docker >/dev/null 2>&1; then
        sudo docker builder prune -af >/dev/null 2>&1 || true
    fi
    local used
    used=$(df --output=pcent / | tail -1 | tr -dc '0-9')
    df -h / >"$EVIDENCE_DIR/disk.txt"
    [ "$used" -le 75 ]
}

# clone_pinned <url> <sha> <dir>: fresh clone at an exact commit, no credentials.
clone_pinned() {
    local url="$1" sha="$2" dir="$3"
    rm -rf "$dir"
    GIT_TERMINAL_PROMPT=0 git clone -q "$url" "$dir" &&
        git -C "$dir" checkout -q "$sha" &&
        [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ]
}

# gate_finish: verdict.json = all checks passed (and at least one check ran).
gate_finish() {
    [ -n "${GATE_SKIP_DISK_GUARD:-}" ] || disk_guard || record disk_guard false "VM / above 75 % used: $(tail -1 "$EVIDENCE_DIR/disk.txt")"
    python3 - "$CHECKS_FILE" "$EVIDENCE_DIR/verdict.json" "$GATE" "$GATE_TS" \
        "${HARNESS_SHA:-unknown}" "$GATE_START_EPOCH" "$HARNESS_DIR/scripts/pins.conf" <<'PY'
import json, sys, time
checks_file, out, gate, ts, harness, start, pins = sys.argv[1:]
checks = [json.loads(l) for l in open(checks_file) if l.strip()]
pin_map = {}
for line in open(pins):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1)
        pin_map[k] = v
verdict = {
    "gate": gate, "ts": ts, "harness_sha": harness, "pins": pin_map,
    "duration_s": int(time.time()) - int(start),
    "pass": bool(checks) and all(c["pass"] for c in checks),
    "failed": [c["name"] for c in checks if not c["pass"]],
    "checks": checks,
}
json.dump(verdict, open(out, "w"), indent=2)
print(f"verdict {gate}: {'PASS' if verdict['pass'] else 'FAIL'} failed={verdict['failed']}")
PY
    local rc=$?
    [ $rc -eq 0 ] || return 2
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["pass"] else 1)' \
        "$EVIDENCE_DIR/verdict.json"
}

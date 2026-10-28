#!/usr/bin/env bash
# E2 agent helpers for gates M5-M7 (sourced after lib.sh, bringup.sh, capture.sh, kpimon.sh; never executed).
# The ns-3 / Influx / analysis helpers live in agents-ns3-run.sh, sourced at the end of this file.
#
#   agents_tree_at_testbed_sha        ~/nist at $TESTBED_SHA including ns3_e2_agent/ (also on the dirty-tree path)
#   agents_sctp_module                sctp kernel module loaded now and at every boot
#   agents_ensure_build_tools         gcc/make (for the harness build) + tshark + tcpdump present
#   agents_bringup <node-list>        bring-up profile `agents` (see bringup.sh); e.g. gnb:2 or enb:1,gnb:2,gnb:3,gnb:4,gnb:5
#   agents_stop                       stop_ns3_e2_agents.sh; no labelled container may remain
#   agents_expected_names             sorted expectedRanName values from run/agents.json
#   agents_record_ips <file>          {"<nodeId>": ["<container ip>", ...]}, union with what <file> already holds
#   agents_stats_last <container>     last JSON stats line the agent printed
#   agents_stats_all                  "<nodeId> <restartCount> <running> <state> <subs> <indTx>" per agent
#   e2mgr_connected_names             sorted CONNECTED inventory names (rc 1 when e2mgr is unreachable)
#   e2mgr_node_status <name>          connectionStatus or ABSENT
#   e2mgr_node_check <name> <plmn> <gnbId>   node JSON: CONNECTED, plmnId, nbId decimal, ranFunction 2 listed
#   pod_info <ns> <substr>            "<name> <ready> <created-epoch> <restarts>" of the newest live matching pod
#
# Environment knobs: AGENTS_CONNECT_TIMEOUT_S (default 300), AGENTS_STOP_E2SIM_TIMEOUT_S (180).

NIST_DIR="${NIST_DIR:-$HOME/nist}"
RIC_DIR="${RIC_DIR:-$NIST_DIR/RAN_Intelligent_Controllers/Near-Real-Time-RIC}"
[ -d "$RIC_DIR" ] || RIC_DIR="$NIST_DIR/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC"
AGENT_DIR="${AGENT_DIR:-$RIC_DIR/ns3_e2_agent}"
export E2EV="$HARNESS_DIR/tools/e2-evidence"
AGENTS_CONNECT_TIMEOUT_S="${AGENTS_CONNECT_TIMEOUT_S:-300}"
AGENTS_STOP_E2SIM_TIMEOUT_S="${AGENTS_STOP_E2SIM_TIMEOUT_S:-180}"
export E2AP_OID_KPM=1.3.6.1.4.1.53148.1.3.2.2   # read by the gate scripts that source this file
export E2AP_SHORT_NAME=ORAN-E2SM-KPM

################################################################################
# tree, tools, kernel module
################################################################################
agents_tree_at_testbed_sha() {
    nist_tree_at_testbed_sha || return 1
    if ! git -C "$RIC_DIR" diff --quiet "$TESTBED_SHA" -- ns3_e2_agent 2>/dev/null || [ ! -d "$AGENT_DIR" ]; then
        git -C "$RIC_DIR" checkout -q "$TESTBED_SHA" -- ns3_e2_agent || return 1
    fi
    git -C "$RIC_DIR" diff --quiet "$TESTBED_SHA" -- ns3_e2_agent &&
        [ -f "$AGENT_DIR/schema/metric-map.v1.json" ] && [ -x "$AGENT_DIR/install_scripts/run_ns3_e2_agents.sh" ] || return 1
    echo "ns3_e2_agent matches $TESTBED_SHA; metric-map sha256 $(sha256sum "$AGENT_DIR/schema/metric-map.v1.json" | cut -d' ' -f1)"
}

agents_sctp_module() {
    lsmod | grep -q '^sctp' || sudo -n modprobe sctp || return 1
    lsmod | grep '^sctp ' | head -n 1
    grep -qx sctp /etc/modules-load.d/sctp.conf 2>/dev/null || echo sctp | sudo -n tee /etc/modules-load.d/sctp.conf >/dev/null
    cat /etc/modules-load.d/sctp.conf
}

agents_ensure_build_tools() {
    if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 || ! command -v tshark >/dev/null 2>&1; then
        sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 apt-get update -q || return 1
        sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 \
            timeout 900 apt-get install -y -q build-essential tshark tcpdump </dev/null || return 1
    fi
    gcc --version | head -n 1
    command -v tcpdump >/dev/null || return 1
    ensure_tshark_kpm
}

# ensure_tshark_kpm: noble's tshark 4.2 throws "Malformed Packet" on E2SM-KPM
# REAL records (epan/asn1.c:232), observed 2026-10-22. Builds tools/tshark-kpm
# (Debian trixie, tshark 4.4.x) once and installs its wrapper as
# /usr/local/bin/tshark. The plan's K15 fallback was the wireshark-dev PPA;
# Launchpad returned 503s for whole gate runs, so the image uses Debian's archive.
ensure_tshark_kpm() {
    local ver i
    ver=$(tshark --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -n "$ver" ] && [ "$(printf '%s\n4.4.0\n' "$ver" | sort -V | head -n 1)" = 4.4.0 ]; then
        echo "tshark $ver (>= 4.4)"; return 0
    fi
    for i in 1 2 3; do
        # shellcheck disable=SC2046
        timeout 900 $(dk_cmd) build -q -t tshark-kpm:trixie "$HARNESS_DIR/tools/tshark-kpm" >/dev/null && break
        echo "tshark-kpm image build try $i failed; retrying"; sleep 30
    done
    sudo -n install -m 755 "$HARNESS_DIR/tools/tshark-kpm/tshark-wrapper.sh" /usr/local/bin/tshark || return 1
    hash -r
    ver=$(tshark --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    echo "tshark $ver via $(command -v tshark) (tshark-kpm:trixie)"
    [ -n "$ver" ] && [ "$(printf '%s\n4.4.0\n' "$ver" | sort -V | head -n 1)" = 4.4.0 ]
}

################################################################################
# bring-up: RIC -> stop kpm_sim -> agent image -> agents -> CONNECTED set exact
################################################################################
# NIST's scripts call plain docker/kubectl. The login session may not carry the
# docker group yet (fresh boot): fall back to a sudo shim on PATH.
_agents_prepare_env() {
    [ -r "$HOME/.kube/config" ] && export KUBECONFIG="$HOME/.kube/config"
    if ! docker info >/dev/null 2>&1; then
        mkdir -p "$EVIDENCE_DIR/.shims"
        printf '#!/bin/sh\nexec sudo -n /usr/bin/docker "$@"\n' >"$EVIDENCE_DIR/.shims/docker"
        chmod +x "$EVIDENCE_DIR/.shims/docker"
        export PATH="$EVIDENCE_DIR/.shims:$PATH"
        log "agents: docker needs sudo in this session; using a shim"
    fi
}

agents_expected_names() {
    python3 -I -c 'import json,sys; print("\n".join(sorted(a["expectedRanName"] for a in json.load(open(sys.argv[1]))["agents"])))' \
        "$AGENT_DIR/run/agents.json"
}

e2mgr_connected_names() {
    e2mgr_states | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print("\n".join(sorted(n["inventoryName"] for n in d if n.get("connectionStatus") == "CONNECTED" and n.get("inventoryName"))))
'
}

e2mgr_node_status() {
    e2mgr_states | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("UNREADABLE"); sys.exit(0)
print(next((n.get("connectionStatus", "?") for n in d if n.get("inventoryName") == sys.argv[1]), "ABSENT"))
' "$1"
}

e2mgr_node_check() {
    e2mgr_get "nodeb/$1" >"$EVIDENCE_DIR/e2mgr-node-$1.json"
    python3 -I - "$EVIDENCE_DIR/e2mgr-node-$1.json" "$1" "$2" "$3" <<'PY'
import json, sys
path, name, plmn, gid = sys.argv[1:]
d = json.load(open(path))
nb = d.get("globalNbId", {})
funcs = [f.get("ranFunctionId") for f in d.get("gnb", {}).get("ranFunctions", [])]
nbid = int(nb.get("nbId", "x"), 2) if set(nb.get("nbId", "x")) <= {"0", "1"} else None
print("ranName=%s status=%s plmnId=%s nbId=%s (decimal %s) nodeType=%s ranFunctions=%s" % (
    d.get("ranName"), d.get("connectionStatus"), nb.get("plmnId"), nb.get("nbId"), nbid, d.get("nodeType"), funcs))
ok = (d.get("ranName") == name and d.get("connectionStatus") == "CONNECTED" and nb.get("plmnId") == plmn
      and nbid == int(gid) and 2 in funcs)
sys.exit(0 if ok else 1)
PY
}

_agents_wait_connected_exact() {
    local deadline=$(($(date +%s) + AGENTS_CONNECT_TIMEOUT_S)) want got
    want=$(agents_expected_names)
    while :; do
        got=$(e2mgr_connected_names)
        if [ -n "$got" ] && [ "$got" = "$want" ]; then
            e2mgr_states >"$EVIDENCE_DIR/bringup-agents-e2mgr-states.json"
            log "bringup agents: e2mgr CONNECTED set equals the expected agents: $(echo "$got" | tr '\n' ' ')"
            return 0
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
            e2mgr_states >"$EVIDENCE_DIR/bringup-agents-e2mgr-states.json"
            log "bringup agents: TIMEOUT. want: $(echo "$want" | tr '\n' ' ') got: $(echo "$got" | tr '\n' ' ')"
            return 1
        fi
        sleep 3
    done
}

# agents_install_image: build the agent image unless run/image.env names an existing image built from this
# map at this Testbed commit (tag ns3-e2-agent:<short12 of the agent tree's HEAD>, the installer's convention).
agents_install_image() {
    local envf="$AGENT_DIR/run/image.env" image mapsha want
    image=$(sed -n 's/^NS3_E2_AGENT_IMAGE=//p' "$envf" 2>/dev/null)
    mapsha=$(sed -n 's/^NS3_E2_AGENT_METRIC_MAP_SHA256=//p' "$envf" 2>/dev/null)
    want="ns3-e2-agent:$(git -C "$AGENT_DIR" rev-parse --short=12 HEAD)"
    if [ "$image" = "$want" ] && dk image inspect "$image" >/dev/null 2>&1 &&
        [ "$mapsha" = "$(sha256sum "$AGENT_DIR/schema/metric-map.v1.json" | cut -d' ' -f1)" ]; then
        log "bringup agents: image $image exists (Testbed commit and map sha match); not rebuilding"
    else
        log "bringup agents: building the agent image (install_ns3_e2_agent.sh, bound 3600s)"
        nist_run 3600 "$AGENT_DIR/install_scripts/install_ns3_e2_agent.sh" >"$EVIDENCE_DIR/install-agent-image.log" 2>&1 || {
            tail -n 20 "$EVIDENCE_DIR/install-agent-image.log"; return 1; }
    fi
    image=$(sed -n 's/^NS3_E2_AGENT_IMAGE=//p' "$envf" 2>/dev/null)
    [ "$image" = "$want" ] || { log "bringup agents: image $image is not $want"; return 1; }
    cp "$envf" "$EVIDENCE_DIR/agent-image.env" && cat "$envf"
}

agents_bringup() {
    local nodes="${1:-}"
    [ -n "$nodes" ] || { log "agents_bringup: node list required"; return 2; }
    [ -x "$AGENT_DIR/install_scripts/run_ns3_e2_agents.sh" ] || { log "agents_bringup: $AGENT_DIR missing (run agents_tree_at_testbed_sha first)"; return 1; }
    _agents_prepare_env
    _bringup_ric || return 1
    log "bringup agents: stopping NIST kpm_sim so its node cannot mix into the CONNECTED set"
    nist_run "$AGENTS_STOP_E2SIM_TIMEOUT_S" "$RIC_DIR/install_scripts/stop_e2sim.sh" >>"$EVIDENCE_DIR/bringup-stop-e2sim.log" 2>&1
    log "bringup agents: stop_e2sim.sh exit $?"
    [ -z "$(dk ps -q --filter name=oransim)" ] || { log "bringup agents: oransim still running"; return 1; }
    agents_install_image || return 1
    nist_run 600 "$AGENT_DIR/install_scripts/run_ns3_e2_agents.sh" --nodes "$nodes" "${@:2}" >"$EVIDENCE_DIR/run-agents.log" 2>&1 || {
        tail -n 20 "$EVIDENCE_DIR/run-agents.log"; return 1; }
    cp "$AGENT_DIR/run/agents.json" "$EVIDENCE_DIR/agents.json"
    _agents_wait_connected_exact || return 1
    _agents_wait_ready && return 0
    # One remedy: e2mgr marks a node CONNECTED before it sends the E2 Setup Response, so the exact set can pass
    # while no response route exists (see rt_reader_ok). Stop the agents, refresh the routes, start them again.
    log "bringup agents: an agent is not READY within ${AGENTS_SETUP_WAIT_S}s; one remedy: stop, refresh routes, restart"
    { agents_stats_all; e2mgr_states; echo; } >>"$EVIDENCE_DIR/agents-ready-remedy.txt" 2>&1
    agents_stop || return 1
    ric_refresh_routes agents || return 1
    nist_run 600 "$AGENT_DIR/install_scripts/run_ns3_e2_agents.sh" --nodes "$nodes" "${@:2}" >>"$EVIDENCE_DIR/run-agents.log" 2>&1 || {
        tail -n 20 "$EVIDENCE_DIR/run-agents.log"; return 1; }
    cp "$AGENT_DIR/run/agents.json" "$EVIDENCE_DIR/agents.json"
    _agents_wait_connected_exact && _agents_wait_ready
}

AGENTS_SETUP_WAIT_S="${AGENTS_SETUP_WAIT_S:-60}"
# _agents_wait_ready: every agent's last stats line shows state READY and e2.setups >= 1 (bounded), the
# predicate m5's agent_ready and the rungs' all_subscribed already trust. The agent prints stats every 5 s.
_agents_wait_ready() {
    local deadline=$(($(date +%s) + AGENTS_SETUP_WAIT_S)) c bad
    while :; do
        bad=""
        for c in $(dk ps -q --filter label=ns3e2.agent=1); do
            agents_stats_last "$c" | python3 -I -c '
import json, sys
try:
    s = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
sys.exit(0 if s.get("state") == "READY" and s.get("e2", {}).get("setups", 0) >= 1 else 1)' || bad="$bad $c"
        done
        [ -n "$(dk ps -q --filter label=ns3e2.agent=1)" ] && [ -z "$bad" ] && {
            log "bringup agents: every agent READY with an E2 setup: $(agents_stats_all | tr '\n' ';')"; return 0; }
        [ "$(date +%s)" -lt "$deadline" ] || { log "bringup agents: not READY:$bad"; return 1; }
        sleep 3
    done
}

agents_stop() {
    nist_run 180 "$AGENT_DIR/install_scripts/stop_ns3_e2_agents.sh" >>"$EVIDENCE_DIR/stop-agents.log" 2>&1
    local rc=$?
    tail -n 12 "$EVIDENCE_DIR/stop-agents.log"
    [ "$rc" -eq 0 ] && [ -z "$(dk ps -aq --filter label=ns3e2.agent=1)" ]
}

################################################################################
# agent / pod observation
################################################################################
agents_stats_last() { dk logs --tail 400 "$1" 2>/dev/null | grep '^{"event"' | tail -n 1; }

agents_stats_all() {
    local c id rc run st
    for c in $(dk ps -aq --filter label=ns3e2.agent=1); do
        read -r id rc run < <(dk inspect --format '{{index .Config.Labels "ns3e2.nodeId"}} {{.RestartCount}} {{.State.Running}}' "$c")
        st=$(agents_stats_last "$c" | python3 -I -c '
import json, sys
try:
    s = json.loads(sys.stdin.read())
except Exception:
    print("? 0 0"); sys.exit(0)
print(s.get("state", "?"), s.get("subs", 0), s.get("indTx", 0))')
        echo "$id $rc $run $st"
    done | sort -n
}

agents_record_ips() {
    local f="$1"
    dk inspect $(dk ps -aq --filter label=ns3e2.agent=1) | python3 -I -c '
import json, os, sys
f = sys.argv[1]
out = json.load(open(f)) if os.path.exists(f) else {}
for c in json.load(sys.stdin):
    nid = c["Config"]["Labels"]["ns3e2.nodeId"]
    ips = [n["IPAddress"] for n in c["NetworkSettings"]["Networks"].values() if n.get("IPAddress")]
    out[nid] = sorted(set(out.get(nid, []) + ips))
json.dump(out, open(f, "w"), indent=1, sort_keys=True)
print(json.dumps(out, sort_keys=True))' "$f"
}

# pod_info <ns> <substr>: newest live pod whose name contains substr.
pod_info() {
    kc -n "$1" get pods -o json 2>/dev/null | python3 -I -c '
import datetime, json, sys
try:
    items = json.load(sys.stdin)["items"]
except Exception:
    sys.exit(1)
best = None
for p in items:
    m = p["metadata"]
    if sys.argv[1] not in m["name"] or m.get("deletionTimestamp"):
        continue
    ts = datetime.datetime.strptime(m["creationTimestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    ready = any(c["type"] == "Ready" and c["status"] == "True" for c in p.get("status", {}).get("conditions", []))
    restarts = sum(c.get("restartCount", 0) for c in p.get("status", {}).get("containerStatuses", []))
    cand = (int(ts.timestamp()), m["name"], "true" if ready else "false", restarts)
    if best is None or cand[0] > best[0]:
        best = cand
if best is None:
    sys.exit(1)
print(best[1], best[2], best[0], best[3])' "$2"
}

# shellcheck source=agents-ns3-run.sh
source "$(dirname "${BASH_SOURCE[0]}")/agents-ns3-run.sh"

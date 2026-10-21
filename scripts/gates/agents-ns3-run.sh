#!/usr/bin/env bash
# ns-3 launch, Influx export, kpimon log and wire/trace analysis helpers for gates M6/M7.
# Sourced by agents.sh (which provides RIC_DIR, E2EV, dk, kc, pod_info, agents_stop ...); never executed.
#
#   agents_ns3_locate                 NS3_BIN (+ NS3_BIN_RE, LD_LIBRARY_PATH) from the M4 build, rebuilt if missing
#   ns3_start <rundir> <args...>      scenario-zero directly, own session/process group, bounded; sets NS3_PID, NS3_START_EPOCH
#   ns3_alive | ns3_wait | ns3_stop   liveness (zombie-safe), reap exit code into NS3_RC, kill by PGID
#   agents_pick_simtime               M7 simTime from the M4 timing report (sets M7_SIMTIME, M7_TIMING_NOTE)
#   influx_export <tag> <start-epoch> pivoted cellMetrics/UeMetrics CSVs for ns3.* joins; influx_node_csv: ns3.nodeId series
#   kpimon_logs_since <epoch> <out>   kpimon pod log from an epoch
#   pcap_facts <pcap> <tag>           facts JSON + decoded setup/subscription text
#   wire_sub_counts <pcap>            "<requests> <responses>" of RICsubscription seen so far (live pcap is fine)
#   ranfunc_decode <node.json> <sodir> <out.jsonl>   e2mgr's ranFunctionDefinition hex through kpimon's library
#   agent_counters_assert <stats-line-file> <expected-samples>
#   endurance_sample <dir> <n>        one 60 s sample (pods, agents, RSS, e2mgr, ns-3, load, kpimon)
#   agents_hygiene                    no ns-3/agent process or container, no 3847x listener
# Environment knobs: M4_WORKDIR (default $HOME/m4-build), NS3_TIMEOUT_S (default 900).

M4_WORKDIR="${M4_WORKDIR:-$HOME/m4-build}"
NS3_TIMEOUT_S="${NS3_TIMEOUT_S:-900}"
NS3_BIN=""; NS3_BIN_RE=""; NS3_PID=""; NS3_START_EPOCH=""; NS3_RC=""
M7_SIMTIME=45; M7_TIMING_NOTE=""
_AGENTS_TRAP_SET=""

iso_utc() { date -u -d "@${1%.*}" +%Y-%m-%dT%H:%M:%SZ; }

################################################################################
# ns-3
################################################################################
agents_ns3_locate() {
    local lib="$M4_WORKDIR/ns-3/build/lib"
    NS3_BIN=$(find "$M4_WORKDIR/ns-3/build/scratch" -maxdepth 1 -type f -perm -u+x -name '*-scenario-zero-*' 2>/dev/null | head -n 1)
    if [ -z "$NS3_BIN" ]; then
        log "ns-3 binary missing under $M4_WORKDIR: rebuilding with build-ns3.sh (bound 5400s)"
        timeout --kill-after=60 5400 bash "$HARNESS_DIR/scripts/build-ns3.sh" "$M4_WORKDIR" \
            >"$EVIDENCE_DIR/build-ns3.stdout" 2>"$EVIDENCE_DIR/build-ns3.stderr" </dev/null || return 1
        NS3_BIN=$(tail -n 1 "$EVIDENCE_DIR/build-ns3.stdout")
    fi
    [ -x "$NS3_BIN" ] || return 1
    NS3_BIN_RE="^$(printf '%s' "$NS3_BIN" | sed 's/[][\.*^$+?(){}|/]/\\&/g')( |\$)"
    [ -d "$lib" ] && export LD_LIBRARY_PATH="$lib:${LD_LIBRARY_PATH:-}"
    echo "$NS3_BIN"
}

ns3_stray() { [ -n "$NS3_BIN_RE" ] && pgrep -f "$NS3_BIN_RE" | tr '\n' ' '; }
ns3_alive() { [ -n "$NS3_PID" ] && ps -o stat= -p "$NS3_PID" 2>/dev/null | grep -qv Z; }

# ns3_start <rundir> <args...>: `exec setsid` in a background subshell makes the subshell PID the process group
# leader (no fork), so $! is both the PID and the PGID; timeout bounds the run.
_agents_trap_install() {
    [ -z "$_AGENTS_TRAP_SET" ] || return 0
    local prev
    prev=$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT\$/\1/")
    # shellcheck disable=SC2064
    trap "ns3_stop; agents_stop >/dev/null 2>&1; $prev" EXIT
    _AGENTS_TRAP_SET=1
}

ns3_start() {
    local rd="$1"; shift
    mkdir -p "$rd"
    if [ -n "$(ns3_stray)" ]; then echo "stray scenario process: $(ns3_stray)"; return 1; fi
    ( cd "$rd" && exec setsid timeout --kill-after=30 "$NS3_TIMEOUT_S" "$NS3_BIN" "$@" >stdout.txt 2>stderr.txt </dev/null ) &
    NS3_PID=$!
    NS3_START_EPOCH=$(date +%s.%N)
    _agents_trap_install
    sleep 2
    ns3_alive || { echo "ns-3 exited immediately: $(tail -n 5 "$rd/stderr.txt")"; return 1; }
    echo "ns-3 started pid/pgid $NS3_PID at $NS3_START_EPOCH: $NS3_BIN $*"
}

ns3_wait() { wait "$NS3_PID" 2>/dev/null; NS3_RC=$?; echo "ns-3 exit code $NS3_RC"; NS3_PID=""; return "$NS3_RC"; }

ns3_stop() {
    [ -n "$NS3_PID" ] || return 0
    if ns3_alive; then
        kill -TERM -- "-$NS3_PID" 2>/dev/null
        for _ in $(seq 25); do ns3_alive || break; sleep 0.2; done
        kill -KILL -- "-$NS3_PID" 2>/dev/null
    fi
    wait "$NS3_PID" 2>/dev/null; NS3_RC=$?
    NS3_PID=""
}

# agents_pick_simtime: M7 simTime = ceil((900 + 300 + 120) / mean real-s-per-sim-s of the default config).
agents_pick_simtime() {
    local rep
    rep=$(ls -1 "$HOME"/evidence/m4/*/ns3-timing.json 2>/dev/null | sort | tail -n 1)
    if [ -n "$rep" ] && cp "$rep" "$EVIDENCE_DIR/m4-ns3-timing.json" &&
        M7_SIMTIME=$(python3 -I -c '
import json, math, sys
m = json.load(open(sys.argv[1]))["configs"]["default"]["mean"]
print(max(20, math.ceil((900 + 300 + 120) / m)))' "$rep" 2>/dev/null); then
        M7_TIMING_NOTE="simTime $M7_SIMTIME from $rep (default-config mean $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["configs"]["default"]["mean"])' "$rep") real s per sim s)"
    else
        M7_SIMTIME=45
        M7_TIMING_NOTE="M4 timing report missing or unreadable (looked in $HOME/evidence/m4/*/ns3-timing.json): fallback simTime 45"
    fi
    [ -z "${M7_SIMTIME_OVERRIDE:-}" ] || { M7_SIMTIME="$M7_SIMTIME_OVERRIDE"; M7_TIMING_NOTE="$M7_TIMING_NOTE; overridden to $M7_SIMTIME"; }
    echo "$M7_TIMING_NOTE"
}

agents_hygiene() {
    local bad=0
    ns3_stop
    if [ -n "$(ns3_stray)" ]; then echo "stray ns-3 process: $(ns3_stray)"; bad=1; fi
    if [ -n "$(dk ps -aq --filter label=ns3e2.agent=1)" ]; then echo "agent containers left: $(dk ps -a --filter label=ns3e2.agent=1 --format '{{.Names}}' | tr '\n' ' ')"; bad=1; fi
    if ss -tlnp 2>/dev/null | grep -E ':3847[0-9][[:space:]]'; then echo "listener on 3847x"; bad=1; fi
    [ "$bad" -eq 0 ] && echo "no ns-3 process, no agent container, no listener on 3847x"
    return "$bad"
}

################################################################################
# InfluxDB / kpimon log
################################################################################
# _flux <flux> <out>: Flux through the influx CLI inside the pod, token expanded inside the pod only.
_flux() {
    # shellcheck disable=SC2016
    timeout --kill-after=10 180 env KUBECONFIG="$HOME/.kube/config" kubectl exec -n ricplt "$INFLUX_POD" -- sh -c \
        'export INFLUX_TOKEN="${INFLUX_TOKEN:-$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}"; exec influx query --org influxdata --raw "$1"' \
        _ "$1" </dev/null >"$2" 2>"$2.err"
    local rc=$?
    redact_stream <"$2.err" >"$2.err.tmp"; mv "$2.err.tmp" "$2.err"
    [ "$rc" -eq 0 ] && ! grep -q '^error' "$2"
}

# influx_export <tag> <start-epoch>: <tag>-influx-cell.csv and <tag>-influx-ue.csv (pivot: one row per point).
influx_export() {
    local tag="$1" s e rc=0 m
    s=$(iso_utc $(($(printf '%.0f' "$2") - 30))); e=$(iso_utc $(($(date +%s) + 120)))
    for m in cell:cellMetrics ue:UeMetrics; do
        _flux "from(bucket: \"kpimon\") |> range(start: $s, stop: $e) |> filter(fn: (r) => r._measurement == \"${m#*:}\") |> pivot(rowKey: [\"_time\"], columnKey: [\"_field\"], valueColumn: \"_value\") |> drop(columns: [\"_start\", \"_stop\"])" \
            "$EVIDENCE_DIR/$tag-influx-${m%%:*}.csv" || { echo "flux export ${m%%:*} failed: $(head -c 300 "$EVIDENCE_DIR/$tag-influx-${m%%:*}.csv.err")"; rc=1; }
    done
    return "$rc"
}

# influx_node_csv <tag> <start-epoch>: the ns3.nodeId field series (_time,_value) per measurement.
influx_node_csv() {
    local tag="$1" s e rc=0 m
    s=$(iso_utc $(($(printf '%.0f' "$2") - 30))); e=$(iso_utc $(($(date +%s) + 120)))
    for m in cell:cellMetrics ue:UeMetrics; do
        _flux "from(bucket: \"kpimon\") |> range(start: $s, stop: $e) |> filter(fn: (r) => r._measurement == \"${m#*:}\" and r._field == \"ns3.nodeId\") |> keep(columns: [\"_time\", \"_value\"])" \
            "$EVIDENCE_DIR/$tag-influx-nodes-${m%%:*}.csv" || rc=1
    done
    return "$rc"
}

kpimon_logs_since() {
    local pod
    read -r pod _ < <(kpimon_pod_info) || return 1
    kc logs -n "$KPIMON_NS" "$pod" --all-containers --since-time="$(iso_utc "$1")" >"$2" 2>&1
}

################################################################################
# wire / decoder helpers
################################################################################
pcap_facts() {
    python3 -I "$E2EV/e2ap-pcap-facts.py" "$1" -o "$EVIDENCE_DIR/$2-facts.json" --text-out "$EVIDENCE_DIR/$2-e2ap-setup-subscription-decoded.txt"
}

wire_sub_counts() {
    tshark -r "$1" -d sctp.port==36422,e2ap -Y 'e2ap.procedureCode == 8' -T fields \
        -e e2ap.initiatingMessage_element -e e2ap.successfulOutcome_element 2>/dev/null |
        awk -F'\t' '{ if ($1 != "") i++; if ($2 != "") s++ } END { print i + 0, s + 0 }'
}

ranfunc_decode() {
    local json="$1" sodir="$2" out="$3"
    python3 -I -c '
import json, sys
fs = json.load(open(sys.argv[1]))["gnb"]["ranFunctions"]
print("ranfunc", next(f["ranFunctionDefinition"] for f in fs if f["ranFunctionId"] == 2))' "$json" >"$out.in" || return 1
    LD_LIBRARY_PATH="$sodir" "$sodir/kpimon-decode-harness" --ranfunc <"$out.in" >"$out" 2>"$out.stderr" || return 1
    [ -s "$out" ]
}

# agent_counters_assert <stats-line-file> <expected-samples>: every drop/overflow counter zero, samples in == forwarded.
agent_counters_assert() {
    python3 -I - "$1" "$2" <<'PY'
import json, sys
s = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
exp = int(sys.argv[2])
zero = dict(s["dropped"])
zero.update({"uesDropped." + k: v for k, v in s["uesDropped"].items()})
zero.update(int32Overflow=s["int32Overflow"], typeMismatch=s["typeMismatch"], realInexact=s["realInexact"],
            rxPduUndecodable=s["e2"]["rxPduUndecodable"], ctrlSendFailed=s["e2"]["ctrlSendFailed"],
            ipcBadJson=s["ipc"]["badJson"], ipcLineTooLong=s["ipc"]["lineTooLong"], helloRejected=s["ipc"]["helloRejected"])
nz = {k: v for k, v in zero.items() if v}
print("state=%s subs=%s samplesIn=%s forwarded=%s (trace %d) indTx=%s (cell %s ue %s) chunkSplits=%s nonzero=%s" % (
    s["state"], s["subs"], s["samplesIn"], s["samplesForwarded"], exp, s["indTx"], s["indTxCell"], s["indTxUe"],
    s["chunkSplits"], nz))
sys.exit(0 if not nz and s["samplesIn"] == exp == s["samplesForwarded"] and s["subs"] >= 1 else 1)
PY
}

endurance_sample() {
    local d
    d="$1/sample-$(printf %02d "$2")"
    mkdir -p "$d"
    date +%s >"$d/t"
    kc -n ricplt get pods -o json 2>/dev/null | python3 -I -c '
import json, sys
for p in sorted(json.load(sys.stdin)["items"], key=lambda p: p["metadata"]["name"]):
    print(p["metadata"]["name"], sum(c.get("restartCount", 0) for c in p.get("status", {}).get("containerStatuses", [])))' >"$d/pods.txt"
    agents_stats_all >"$d/agents.txt"
    dk stats --no-stream --format '{{.Name}} {{.MemUsage}}' $(dk ps -q --filter label=ns3e2.agent=1) >"$d/rss.txt" 2>&1
    e2mgr_connected_names >"$d/e2mgr.txt" 2>/dev/null
    if ns3_alive; then echo 1; else echo 0; fi >"$d/ns3.alive"
    cat /proc/loadavg >"$d/load.txt"
    pod_info ricxapp kpimon-go >"$d/kpimon.txt" 2>/dev/null
    log "endurance sample $2: load $(cut -d' ' -f1-3 "$d/load.txt"), ns3 alive $(cat "$d/ns3.alive"), agents: $(awk '{printf "%s:rc%s ", $1, $2}' "$d/agents.txt")"
}

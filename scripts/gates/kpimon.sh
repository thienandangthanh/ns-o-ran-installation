#!/usr/bin/env bash
# kpimon-go helpers for gates (sourced after lib.sh, bringup.sh and capture.sh; never executed).
# Used by gate-m3-xapps.sh; written so the M6 gate can reuse the same install / count /
# decode flow against the agent-fed pcap.
#
#   dk <docker args>                     docker as the current user, else via sudo
#   nist_run <timeout-s> <cmd...>        OVERRIDE of lib.sh nist_run (see below)
#   nist_tree_at_testbed_sha             make ~/nist carry the fork files at $TESTBED_SHA
#   kpimon_pod_info                      "<name> <ready:true|false> <created-epoch> <restarts>" of the newest live pod
#   kpimon_install <true|false> <log>    NIST installer, CLEAN_INSTALL=true, KPIMON_TIMESTAMP_SIZE8=<arg>
#   kpimon_log_counts <logfile>          K13 counts as key=value lines
#   influx_rows <range>                  Flux row counts (total + per measurement) via the influx CLI inside the pod
#   harness_analyze <tag> <pcap> <so-dir> <expect-ts>   pcap -> lines -> kpimon decoder -> <tag> decode summary
#   jget <json-file> <dotted.key>        read one value from a JSON file
#
# Secrets: nothing here reads or prints the InfluxDB token. The influx CLI inside the pod is
# already configured by NIST, so queries need no token on the command line; installer output is
# passed through a redaction filter before it reaches the evidence dir.

NIST_DIR="${NIST_DIR:-$HOME/nist}"
RIC_DIR="${RIC_DIR:-$NIST_DIR/RAN_Intelligent_Controllers/Near-Real-Time-RIC}"
[ -d "$RIC_DIR" ] || RIC_DIR="$NIST_DIR/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC"
export RIC_DIR
KPIMON_IMAGE="${KPIMON_IMAGE:-127.0.0.1:80/kpimon-go:latest}"
KPIMON_NS=ricxapp
INFLUX_POD=r4-influxdb-influxdb2-0
HARNESS_TOOLS="$HARNESS_DIR/tools/kpimon-decode-harness"
KPIMON_POD=""  # set by kpimon_wait_ready



# redact_stream: defensive filter for NIST installer output; strips anything shaped like an
# InfluxDB token (long base64 ending in ==) or a "token" JSON value. The scrubber is the backstop.
redact_stream() {
    sed -E 's/[A-Za-z0-9_-]{60,}={0,2}/REDACTED-LONG-TOKEN/g; s/("token"[[:space:]]*:[[:space:]]*")[^"]*/\1REDACTED/g'
}

jget() {
    python3 - "$1" "$2" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'):
    v = v[k]
print(json.dumps(v) if isinstance(v, (dict, list)) else v)
PY
}

################################################################################
# NIST tree at the Testbed SHA
################################################################################
# If HEAD != $TESTBED_SHA: fetch (anonymous https). Clean tracked files -> detached checkout.
# Modified tracked files (NIST's installer edits its own tree) -> save status+diffstat and
# check out only the installer and the kpimon-go patch dir from $TESTBED_SHA.
nist_tree_at_testbed_sha() {
    local head dirty
    head=$(git -C "$RIC_DIR" rev-parse HEAD) || return 1
    echo "nist HEAD $head, want $TESTBED_SHA"
    if [ "$head" != "$TESTBED_SHA" ]; then
        git -C "$RIC_DIR" cat-file -e "$TESTBED_SHA^{commit}" 2>/dev/null ||
            GIT_TERMINAL_PROMPT=0 git -C "$RIC_DIR" fetch -q "$TESTBED_URL" "$TESTBED_SHA" ||
            GIT_TERMINAL_PROMPT=0 git -C "$RIC_DIR" fetch -q origin || return 1
        git -C "$RIC_DIR" cat-file -e "$TESTBED_SHA^{commit}" || return 1
        dirty=$(git -C "$RIC_DIR" status --porcelain --untracked-files=no)
        if [ -z "$dirty" ]; then
            git -C "$RIC_DIR" checkout -q --detach "$TESTBED_SHA" || return 1
            echo "clean tree: detached checkout of $TESTBED_SHA"
            echo "full-checkout" >"$EVIDENCE_DIR/nist-tree-mode.txt"
        else
            {
                echo "# git status --porcelain (tracked)"; echo "$dirty"
                echo "# git diff --stat"; git -C "$RIC_DIR" diff --stat
            } >"$EVIDENCE_DIR/nist-tree-dirty-before-checkout.txt"
            git -C "$RIC_DIR" checkout "$TESTBED_SHA" -- \
                additional_scripts/install_xapp_kpi_monitor.sh install_patch_files/xApps/kpimon-go || return 1
            echo "dirty tree: only installer + install_patch_files/xApps/kpimon-go taken from $TESTBED_SHA"
            echo "partial-checkout" >"$EVIDENCE_DIR/nist-tree-mode.txt"
        fi
    else
        echo "already at $TESTBED_SHA" ; echo "already-at-sha" >"$EVIDENCE_DIR/nist-tree-mode.txt"
    fi
    # The fork files M3 depends on must be present now.
    # shellcheck disable=SC2016  # literal text searched for in the installer
    grep -q 'KPIMON_TIMESTAMP_SIZE8' "$RIC_DIR/additional_scripts/install_xapp_kpi_monitor.sh" &&
        grep -qF '${CLEAN_INSTALL:-false}' "$RIC_DIR/additional_scripts/install_xapp_kpi_monitor.sh" &&
        [ -f "$RIC_DIR/install_patch_files/xApps/kpimon-go/e2sm/asn1/kpm2_0.asn.timestamp-size8.patch" ] &&
        [ -f "$RIC_DIR/install_patch_files/xApps/kpimon-go/e2sm/lib/TimeStamp.c.timestamp-size8.patch" ]
}

################################################################################
# kpimon pod / install
################################################################################
# kpimon_pod_info: newest kpimon-go pod that is not being deleted.
kpimon_pod_info() {
    kc -n "$KPIMON_NS" get pods -o json 2>/dev/null | python3 -c '
import json, sys, datetime
try:
    items = json.load(sys.stdin)["items"]
except Exception:
    sys.exit(1)
best = None
for p in items:
    m = p["metadata"]
    if "kpimon-go" not in m["name"] or m.get("deletionTimestamp"):
        continue
    ts = datetime.datetime.strptime(m["creationTimestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    ready = any(c["type"] == "Ready" and c["status"] == "True" for c in p.get("status", {}).get("conditions", []))
    restarts = sum(c.get("restartCount", 0) for c in p.get("status", {}).get("containerStatuses", []))
    cand = (int(ts.timestamp()), m["name"], "true" if ready else "false", restarts)
    if best is None or cand[0] > best[0]:
        best = cand
if best is None:
    sys.exit(1)
print(best[1], best[2], best[0], best[3])
'
}

# kpimon_wait_ready <timeout-s> <min-created-epoch>: newest pod created >= epoch and Ready.
kpimon_wait_ready() {
    local deadline=$(($(date +%s) + $1)) min="$2" name ready created restarts
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if read -r name ready created restarts < <(kpimon_pod_info) && [ "$ready" = true ] && [ "$created" -ge "$min" ]; then
            echo "pod $name Ready, created epoch $created, restarts $restarts"
            # shellcheck disable=SC2034  # read by the gate script
            KPIMON_POD="$name"
            return 0
        fi
        sleep 5
    done
    echo "no Ready kpimon-go pod created >= $min within $1 s"
    kc -n "$KPIMON_NS" get pods -o wide 2>&1
    return 1
}

# kpimon_uninstall: dms_cli uninstall (not-found tolerated), then wait for the pods to vanish.
kpimon_uninstall() {
    local deadline
    export CHART_REPO_URL="${CHART_REPO_URL:-http://0.0.0.0:8090}"
    if command -v dms_cli >/dev/null 2>&1; then
        dms_cli uninstall kpimon-go "$KPIMON_NS" 2>&1 | tail -n 5 || true
    else
        echo "dms_cli not found (nothing to uninstall through it)"
    fi
    deadline=$(($(date +%s) + 180))
    while grep -q kpimon-go < <(kc -n "$KPIMON_NS" get pods --no-headers 2>/dev/null); do
        [ "$(date +%s)" -lt "$deadline" ] || { echo "kpimon-go pods still present"; return 1; }
        sleep 5
    done
    echo "no kpimon-go pod left"
}

kubectl_exec_it_probe() {
    # NIST's installer calls `kubectl exec -it` with no TTY. Verified on the VM:
    # kubectl warns "Unable to use a TTY" and still runs the command (rc 0). A
    # pty wrapper such as script(1) must NOT be used: with a tty, NIST's
    # start_sudo_refresh.sh runs `sudo -v`, which prompts for a password (uc has
    # both a password rule and a NOPASSWD rule) and hangs the gate forever.
    # The probe targets e2mgr because InfluxDB is created by the installer itself.
    local out="$EVIDENCE_DIR/kubectl-exec-it-probe.txt" pod rc
    pod=$(kc -n ricplt get pods -o name | grep -m1 e2mgr)
    timeout 90 env KUBECONFIG="$HOME/.kube/config" kubectl exec -it -n ricplt "$pod" -- sh -c "echo EXEC_IT_OK" < <(exec sleep 100) >"$out" 2>&1
    rc=$?
    echo "exit $rc on $pod: $(tr '\n' '|' <"$out")"
    [ "$rc" -eq 0 ] && grep -q EXEC_IT_OK "$out"
}

# kpimon_install_retry <size8> <logfile>: the installer builds the image with
# `go build`, which downloads modules from proxy.golang.org; a reset connection
# there fails the build (observed 2026-10-21). Retry up to 2 more times, only
# when the failed log carries a network-error signature. Every attempt keeps
# its own log, and the attempts are listed in <logfile>.attempts.
KPIMON_NET_ERR='connection reset by peer|i/o timeout|TLS handshake timeout|dial tcp|unexpected EOF|502 Bad Gateway|503 Service Unavailable'
kpimon_install_retry() {
    local size8="$1" log="$2" n rc
    for n in 1 2 3; do
        kpimon_install "$size8" "$log.try$n"; rc=$?
        echo "$(date -u +%FT%TZ) try $n exit $rc" >>"$log.attempts"
        cp "$log.try$n" "$log"
        [ "$rc" -eq 0 ] && return 0
        grep -Eaq "$KPIMON_NET_ERR" "$log.try$n" || { echo "not a network error: no retry"; return "$rc"; }
        log "kpimon install try $n failed on a network error; retrying"
        sleep 30
    done
    return "$rc"
}

# kpimon_install <size8:true|false> <logfile>
kpimon_install() {
    local size8="$1" log="$2" rc
    local envs="CLEAN_INSTALL=true KPIMON_TIMESTAMP_SIZE8=$size8"
    (
        cd "$RIC_DIR" || exit 1
        # shellcheck disable=SC2086
        nist_run 3600 env $envs ./additional_scripts/install_xapp_kpi_monitor.sh
    ) >"$log.raw" 2>&1
    # Never pipe NIST output (its chartmuseum daemon inherits stdout and would
    # hold a pipe open forever); redact the file afterwards instead.
    rc=$?
    redact_stream <"$log.raw" >"$log"; rm -f "$log.raw"
    echo "installer exit $rc (size8=$size8); log $log"
    tail -n 8 "$log"
    return "$rc"
}

kpimon_image_id() { dk image inspect --format '{{.Id}}' "$KPIMON_IMAGE" 2>/dev/null; }

# kpimon_extract_so <out-dir>: .so + harness from the CURRENT docker image; prints SIZE (4|8) on
# the last line. docker may need sudo when the group is not active yet.
kpimon_extract_so() {
    local out="$1"
    if docker info >/dev/null 2>&1; then
        "$HARNESS_TOOLS/extract-from-image.sh" "$KPIMON_IMAGE" "$out"
    else
        sudo -n "$HARNESS_TOOLS/extract-from-image.sh" "$KPIMON_IMAGE" "$out" &&
            sudo -n chown -R "$(id -u):$(id -g)" "$out"
    fi
}

# harness_so_size <so-dir>: TimeStamp SIZE lower bound compiled into the extracted .so.
harness_so_size() { "$1/kpimon-decode-harness" --timestamp-size; }

################################################################################
# Counting (K13)
################################################################################
# kpimon_log_counts <logfile>. Strings (kpimon-go 8bbbbbb9, control/control.go + NIST patch):
#   indication received : log.Printf("RIC Indication message from {%s} received") (handleIndication)
#   header WMORE        : fprintf(stderr, "\nheader RC_WMORE ")  (NIST wrapper.c.patch, e2sm_decode_ric_indication_header)
#   message WMORE       : fprintf(stderr, "\n MSG RC_WMORE ")     (NIST wrapper.c.patch, message decode)
#   influx writes       : xapp.Logger.Info("Wrote UE Metrics to InfluxDB") / ("Wrote Cell Metrics to InfluxDB")
# Occurrences, not lines (stderr fragments can share a line).
kpimon_log_counts() {
    local f="$1"
    echo "indications=$(grep -o 'RIC Indication message from' "$f" | wc -l)"
    echo "hdr_wmore=$(grep -o 'header RC_WMORE' "$f" | wc -l)"
    echo "msg_wmore=$(grep -o 'MSG RC_WMORE' "$f" | wc -l)"
    echo "influx_wrote_ue=$(grep -o 'Wrote UE Metrics to InfluxDB' "$f" | wc -l)"
    echo "influx_wrote_cell=$(grep -o 'Wrote Cell Metrics to InfluxDB' "$f" | wc -l)"
}

# influx_rows <range>: runs Flux inside the influxdb pod (CLI already configured by NIST; no token
# is passed or printed). Prints "total=N" and "m_<measurement>=N" lines; rc 1 on query/parse error.
influx_rows() {
    local range="${1:--5m}" raw
    local flux="from(bucket: \"kpimon\") |> range(start: $range) |> filter(fn: (r) => r._measurement == \"cellMetrics\" or r._measurement == \"UeMetrics\") |> group(columns: [\"_measurement\"]) |> count()"
    raw=$(kc exec -n ricplt "$INFLUX_POD" -- influx query --org influxdata --raw "$flux" </dev/null 2>&1) || {
        echo "influx query failed: $(echo "$raw" | redact_stream | tail -n 5)"; echo "total=ERR"; return 1; }
    echo "$raw" | python3 -c '
import csv, io, sys
hdr = None; per = {}
for line in sys.stdin:
    line = line.rstrip("\r\n")
    if not line or line.startswith("#"):
        continue
    row = next(csv.reader(io.StringIO(line)))
    if "_value" in row:
        hdr = {n: i for i, n in enumerate(row)}
        continue
    if hdr is None or len(row) <= max(hdr.get("_value", 0), hdr.get("_measurement", 0)):
        continue
    m = row[hdr["_measurement"]] if "_measurement" in hdr else "all"
    per[m] = per.get(m, 0) + int(row[hdr["_value"]])
print("total=%d" % sum(per.values()))
for k, v in sorted(per.items()):
    print("m_%s=%d" % (k, v))
' || { echo "total=ERR"; return 1; }
}

# kv <key> (stdin key=value lines) -> value
kv() { sed -n "s/^$1=//p" | head -n 1; }

################################################################################
# Decode: pcap -> kpimon's own decoder
################################################################################
# harness_analyze <tag> <pcap> <so-dir> <expect-ts-len>
# Writes $EVIDENCE_DIR/<tag>-{lines.txt,harness.jsonl,harness-summary.json,decode.json}.
# decode.json: clean counts. "Clean" (implementation-notes K9 decision) = code RC_OK AND
# consumed == length AND, for headers, ts_len == <expect-ts-len>; messages: RC_OK AND consumed == length.
harness_analyze() {
    local tag="$1" pcap="$2" sodir="$3" ts="$4" e="$EVIDENCE_DIR"
    local pl="$HARNESS_TOOLS/pcap-to-lines.py" h="$sodir/kpimon-decode-harness"
    python3 "$pl" "$pcap" --summary >"$e/$tag-extract-summary.json" || return 1
    python3 "$pl" "$pcap" >"$e/$tag-lines.txt" || return 1
    LD_LIBRARY_PATH="$sodir" "$h" --xer 2 <"$e/$tag-lines.txt" >"$e/$tag-harness.jsonl" 2>"$e/$tag-harness.stderr" || return 1
    python3 "$HARNESS_TOOLS/summarize.py" "$e/$tag-harness.jsonl" -o "$e/$tag-harness-summary.json" >/dev/null || return 1
    python3 - "$e/$tag-harness.jsonl" "$ts" "$e/$tag-decode.json" <<'PY'
import json, sys
src, ts, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
r = dict(total=0, hdr_ok_exact=0, hdr_clean=0, msg_clean=0, hdr_wmore=0, msg_wmore=0,
         hdr_fail=0, msg_fail=0, hdr_other=0, msg_other=0)
for line in open(src):
    if not line.strip():
        continue
    x = json.loads(line)
    r["total"] += 1
    h_exact = x["hdr_code"] == "RC_OK" and x["hdr_consumed"] == x["hdr_len"]
    m_exact = x["msg_code"] == "RC_OK" and x["msg_consumed"] == x["msg_len"]
    r["hdr_ok_exact"] += h_exact
    r["hdr_clean"] += h_exact and x["ts_len"] == ts
    r["msg_clean"] += m_exact
    for p, c in (("hdr", x["hdr_code"]), ("msg", x["msg_code"])):
        if c == "RC_WMORE": r[p + "_wmore"] += 1
        elif c == "RC_FAIL": r[p + "_fail"] += 1
        elif c != "RC_OK": r[p + "_other"] += 1
r["expect_ts_len"] = ts
json.dump(r, open(out, "w"), indent=2, sort_keys=True)
print(json.dumps(r, sort_keys=True))
PY
}

# e2ap_proc_counts <pcap> <procedureCode> <out-text>: prints "initiating=N successful=N" for
# the E2AP procedure, decoded by tshark (-V text kept as evidence).
e2ap_proc_counts() {
    local pcap="$1" code="$2" out="$3"
    tshark -r "$pcap" -d sctp.port==36422,e2ap -Y "e2ap.procedureCode == $code" -V >"$out" 2>"$out.err" || return 1
    awk '/^[ ]*E2AP-PDU: / { pdu = $2 }
         /procedureCode: id-/ { if (pdu ~ /^initiatingMessage/) i++; else if (pdu ~ /^successfulOutcome/) s++ }
         END { printf "initiating=%d successful=%d\n", i, s }' "$out"
}

# m3_write_summary <out.json> <decode.json> <harness-summary.json> <extract-summary.json> key=value...
m3_write_summary() {
    local out="$1"; shift
    python3 - "$out" "$@" <<'PY'
import json, re, sys
out, decode, harness, extract = sys.argv[1:5]
facts = {}
for kv in sys.argv[5:]:
    k, _, v = kv.partition("=")
    facts[k] = int(v) if re.fullmatch(r"-?\d+", v) else v
doc = {"decode": json.load(open(decode)), "harness": json.load(open(harness)),
       "extract": json.load(open(extract)), "facts": facts}
json.dump(doc, open(out, "w"), indent=2, sort_keys=True)
PY
}

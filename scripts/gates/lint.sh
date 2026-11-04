#!/usr/bin/env bash
# lint.sh: static checks for the gate harness; run before pushing a harness SHA.
#   1. bash -n on every script;
#   2. shellcheck (warnings) when installed;
#   3. no external wrapper (timeout, nist_run, sudo, env, xargs) around a shell
#      function defined in the harness: such wrappers exec a binary and fail
#      with "No such file or directory" at run time;
#   4. no `<logs> | grep -q|-m` or `| head`: the reader exits early, the writer dies of SIGPIPE and pipefail
#      turns that into a false failure (use a here-string, process substitution or a file);
#   5. ts_threshold_logged on a real TS xApp log fixture;
#   6. the self-tests of the judges (patch-set checks of the TS xApp, rc and kpimon, the TS cell-map replay, the pacer,
#      the UE ID prepare, the RC wire extractor, the R1 C4 arrival-order fixture, ...), the send-rmr.sh UE ID refusals
#      and the UE context counter helper on a restarted agent's log.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
rc=0
for f in scripts/gates/*.sh scripts/vm/*.sh scripts/*.sh tools/*/*.sh; do
    bash -n "$f" || { echo "syntax: $f"; rc=1; }
done
if command -v shellcheck >/dev/null; then
    shellcheck -x -e SC1090,SC1091,SC2046 -S warning scripts/gates/*.sh scripts/vm/*.sh scripts/*.sh || rc=1
fi
fns=$(grep -ho '^[a-z_][a-z0-9_]*()' scripts/gates/*.sh scripts/vm/*.sh | tr -d '()' | sort -u | paste -sd'|')
if grep -nE "(^|[;&|(]|\s)(timeout|nist_run|sudo|env|xargs)( +-[-a-zA-Z=0-9]+| +[A-Z_]+=[^ ]+| +[0-9]+)* +($fns)\b" \
    scripts/gates/*.sh scripts/vm/*.sh | grep -vE ':\s*#'; then
    echo "an external wrapper calls a shell function (see above)"; rc=1
fi
# Gate-id self-test: vm-exec.sh names evidence dirs and .last-<id> files by it.
source scripts/vm/vm-common.sh
ids=$(for s in gate-m5-agent-setup.sh gate-r0-rc-scripted.sh gate-s1-pacer-lockstep.sh gate-q7-qp-token-check.sh \
    gate-r3p-ts-predictor.sh; do gate_id "$s"; done | paste -sd' ')
echo "gate ids: $ids"
[ "$ids" = "m5 r0 s1 q7 r3p" ] || { echo "gate-id regex broken"; rc=1; }
for s in scripts/gates/gate-*.sh; do
    [[ "$(gate_id "$(basename "$s")")" =~ ^[a-z]+[0-9]+[a-z]?$ ]] || { echo "gate id of $s is not a short id"; rc=1; }
done
# the top rung's green snapshot is protected: r3p-green always, r2-green only once substitution 4 is recorded
prot() { R3P_SUBST4_FILE="$1" bash scripts/vm/vm-snapshot.sh check-protected "$2"; }
sub4=$(mktemp); nosub4="$sub4.absent"
for want in "fresh-install $nosub4 protected" "f7-rerun-green $nosub4 protected" "r3p-green $nosub4 protected" \
    "r2-green $nosub4 deletable" "r2-green $sub4 protected" "r0-green $sub4 deletable"; do
    read -r n f w <<<"$want"
    [ "$(prot "$f" "$n")" = "$w" ] || { echo "check-protected $n (substitution-4 file $([ -e "$f" ] && echo present || echo absent)) is not $w"; rc=1; }
done
rm -f "$sub4"
python3 -I scripts/gates/pod-log-window.py --self-test || rc=1
python3 -I scripts/gates/check-c9-handover-trace.py --self-test >/dev/null || { echo "c9 handover matcher self-test failed"; rc=1; }
python3 -I scripts/gates/n4-drop-selftest.py >/dev/null || { echo "n4 UL-off drop self-test failed"; rc=1; }
python3 -I scripts/gates/check-pdcp-volume-totals.py --self-test >/dev/null || { echo "n4 PDCP volume audit judge self-test failed"; rc=1; }
python3 -I scripts/gates/check-n4-v5-windows.py --self-test >/dev/null || { echo "n4 V5 window rule self-test failed"; rc=1; }
python3 -I scripts/gates/r3p-predictor.py --self-test >/dev/null || { echo "r3p predictor self-test failed"; rc=1; }
python3 -I scripts/gates/r3p-predictor.py lint scripts/gates/r3p-scenario.json >/dev/null ||
    { echo "r3p-scenario.json pre-registration does not lint (empty domain or template outside it)"; rc=1; }
python3 -I scripts/gates/check-n6-influx-window.py --self-test >/dev/null || { echo "N6 window certification self-test failed"; rc=1; }
python3 -I scripts/gates/r3p-dry-run-classifier.py --self-test >/dev/null || { echo "r3p dry-run classifier self-test failed"; rc=1; }
python3 -I scripts/gates/r3p-checks.py --self-test >/dev/null || { echo "r3p checks self-test failed"; rc=1; }
python3 -I scripts/gates/reference-compare.py --self-test >/dev/null || { echo "reference-compare self-test failed"; rc=1; }
python3 -I scripts/gates/reference-transform-compare.py --selftest >/dev/null || { echo "reference-transform-compare self-test (fixtures a-i) failed"; rc=1; }
timeout 120 bash scripts/vm/m9-runner-selftest.sh >/dev/null 2>&1 || { echo "M9 runner self-test (verdict, heartbeat monitor) failed"; rc=1; }
timeout 60 bash scripts/gates/rt-reader-selftest.sh >/dev/null 2>&1 || { echo "rc receiver-side RMR readiness self-test failed"; rc=1; }
timeout 120 bash scripts/gates/ts-patches-selftest.sh >/dev/null 2>&1 || { echo "TS xApp patch-set check self-test failed"; rc=1; }
timeout 120 bash scripts/gates/rc-at-pin-selftest.sh >/dev/null 2>&1 || { echo "rc pin + patch-set check self-test failed"; rc=1; }
timeout 120 bash scripts/gates/kpimon-guard-selftest.sh >/dev/null 2>&1 || { echo "kpimon install guard self-test failed"; rc=1; }
timeout 120 bash scripts/gates/lib-selftest.sh >/dev/null 2>&1 || { echo "lib.sh fact/nist_run self-test failed"; rc=1; }
timeout 60 bash scripts/vm/host-disk-watchdog-selftest.sh >/dev/null 2>&1 || { echo "host disk watchdog self-test failed"; rc=1; }
python3 -I scripts/gates/replay-ts-cell-map.py --self-test >/dev/null || { echo "TS cell-map replay self-test failed"; rc=1; }
python3 -I scripts/gates/e2i-wire-checks.py --self-test >/dev/null || { echo "e2i wire judge self-test failed"; rc=1; }
python3 -I scripts/disk-burst-h.py --self-test >/dev/null || { echo "disk-burst-h self-test failed"; rc=1; }
python3 -I scripts/gates/check-actuation-delay.py --self-test >/dev/null || { echo "check-actuation-delay self-test failed"; rc=1; }
python3 -I scripts/gates/identity-map-extract.py --self-test >/dev/null || { echo "identity-map-extract self-test failed"; rc=1; }
python3 -I scripts/gates/p12-records-check.py --self-test >/dev/null || { echo "p12 multi-record indication judge self-test failed"; rc=1; }
python3 -I scripts/gates/digest-run.py --self-test >/dev/null || { echo "digest-run ueContext-in-ipc-trace self-test failed"; rc=1; }
python3 -I tools/e2-evidence/ue-context-map.py --self-test >/dev/null || { echo "UE context map self-test failed"; rc=1; }
python3 -I tools/e2-evidence/kpm-ue-list-moves.py --self-test >/dev/null || { echo "KPM UE list / UE ID judge self-test failed"; rc=1; }
python3 -I tools/e2-evidence/e2-facts-query.py --self-test >/dev/null || { echo "e2-facts-query sub-actions self-test failed"; rc=1; }
python3 -I tools/e2-evidence/influx-ue-ueid-every-node.py --self-test >/dev/null || { echo "Influx UE-row ueId-to-IMSI every-node judge self-test failed"; rc=1; }
python3 -I tools/ipc-null-sink/ipc-null-sink.py --self-test >/dev/null || { echo "ipc-null-sink self-test failed"; rc=1; }
timeout 120 bash tools/e2-evidence/selftest.sh >/dev/null 2>&1 || { echo "e2-evidence self-test (incl. influx-vs-trace ueId) failed"; rc=1; }
timeout 300 python3 -I scripts/gates/pacer-selftest.py >/dev/null 2>&1 || { echo "pacer self-test (replay pairing, ueIdFrom) failed"; rc=1; }
python3 -I scripts/gates/ue-id-prepare.py --self-test >/dev/null || { echo "ue-id-prepare self-test failed"; rc=1; }
python3 -I tools/e2-evidence/wire-c1-extract.py --self-test >/dev/null || { echo "wire-c1-extract self-test failed"; rc=1; }
python3 -I scripts/gates/r0-checks.py --self-test >/dev/null || { echo "r0-checks self-test (the C4 arrival-order fixture must fail) failed"; rc=1; }
# send-rmr.sh refuses (exit 2, nothing sent) any ue-id that is not an en-gNB-UEID key, a missing or empty file and a
# file of two lines; a well-formed key reaches the socket step (exit 1 here: nothing listens on the port)
tmp=$(mktemp -d); srmr() { bash scripts/gates/send-rmr.sh 1 "$@" >/dev/null 2>&1; echo $?; }
printf 'enGnbUeId:3@00F110-00001\n' >"$tmp/ok.txt"; printf 'enGnbUeId:3@00F110-00001\nx\n' >"$tmp/two.txt"; : >"$tmp/empty.txt"
printf '3\n' >"$tmp/imsi.txt"
for want in "2 anomaly 3" "2 anomaly enGnbUeId:3@00f110-00001" "2 anomaly-from $tmp/missing.txt" "2 anomaly-from $tmp/empty.txt" \
    "2 anomaly-from $tmp/two.txt" "2 anomaly-from $tmp/imsi.txt" "1 anomaly enGnbUeId:3@00F110-00001" "1 anomaly-from $tmp/ok.txt"; do
    read -r w args <<<"$want"
    # shellcheck disable=SC2086
    [ "$(srmr $args)" = "$w" ] || { echo "send-rmr.sh $args: exit not $w"; rc=1; }
done
rm -rf "$tmp"
# agent_ue_context_counters_zero: the maximum over every stats line of every incarnation, so a count that a restart
# reset (an earlier incarnation's samplesNoUeContext 1) is red; a clean log is green
source <(sed -n '/^agent_ue_context_counters_zero()/,/^}/p' scripts/gates/agents-ns3-run.sh)
tmp=$(mktemp -d); echo '{"1": ["10.0.0.1"], "2": ["10.0.0.2"]}' >"$tmp/node-ips.json"
st() { printf '{"event":"stats","samplesNoUeContext":%d,"ipc":{"ueContext":%d,"ueContextRejected":%d}}\n' "$@"; }
{ st 0 1 0; st 0 3 0; } >"$tmp/agent-1.log"; { st 0 2 0; st 0 2 0; } >"$tmp/agent-2.log"
agent_ue_context_counters_zero "$tmp" >/dev/null || { echo "agent_ue_context_counters_zero: clean logs were red"; rc=1; }
{ st 1 2 0; echo "restart"; st 0 1 0; } >"$tmp/agent-2.log"
agent_ue_context_counters_zero "$tmp" >/dev/null && { echo "agent_ue_context_counters_zero: an earlier incarnation's samplesNoUeContext 1 passed"; rc=1; }
{ st 0 2 1; } >"$tmp/agent-2.log"
agent_ue_context_counters_zero "$tmp" >/dev/null && { echo "agent_ue_context_counters_zero: ueContextRejected 1 passed"; rc=1; }
rm -f "$tmp/agent-2.log"
agent_ue_context_counters_zero "$tmp" >/dev/null && { echo "agent_ue_context_counters_zero: a missing agent log passed"; rc=1; }
rm -rf "$tmp"
# kpimon decode harness host tests: they need kpimon's own library (KP_SO/KP_INC, KP_E2SM/TS_ORIG; see
# tools/kpimon-decode-harness/extract-from-image.sh). Without it each prints SKIP (exit 77), shown, never a pass.
tmp_kdh=$(mktemp)
for t in selftest-records.sh selftest.sh; do
    s=0; timeout 600 bash "tools/kpimon-decode-harness/$t" >"$tmp_kdh" 2>&1 || s=$?
    if [ "$s" -eq 77 ]; then sed -n 1p "$tmp_kdh"; elif [ "$s" -ne 0 ]; then echo "kpimon decode harness $t failed"; rc=1; fi
done
rm -f "$tmp_kdh"
# The TS xApp's UeMetrics query against InfluxDB 2.7 with mixed integer/float fields (needs podman and a local
# influxdb:2.7 image; without them it prints SKIP, exit 77, shown, never a pass).
tmp_tiq=$(mktemp)
s=0; timeout 300 python3 -I scripts/gates/ts-influx-query-selftest.py >"$tmp_tiq" 2>&1 || s=$?
if [ "$s" -eq 77 ]; then sed -n 1p "$tmp_tiq"; elif [ "$s" -ne 0 ]; then cat "$tmp_tiq"; echo "TS xApp Influx query self-test failed"; rc=1; fi
rm -f "$tmp_tiq"
# agent_counters_assert: the UE-context counters join the zero set, and ipc.ueContext >= 1
source <(sed -n '/^agent_counters_assert()/,/^}/p' scripts/gates/agents-ns3-run.sh)
tmp=$(mktemp -d)
# acs <name> <python dict-update expression on s>: an agent stats line, healthy unless the expression changes it
acs() {
    python3 -I - "$tmp/$1.json" "$2" <<'PY'
import json, sys
s = {"state": "READY", "subs": 1, "samplesIn": 10, "samplesForwarded": 10, "samplesUnreported": 0, "indTx": 10,
     "indTxCell": 10, "indTxUe": 10, "chunkSplits": 0, "dropped": {"x": 0}, "uesDropped": {"y": 0}, "int32Overflow": 0,
     "typeMismatch": 0, "realInexact": 0, "samplesGapDiscarded": 0, "samplesReportFailed": 0, "samplesNoUeContext": 0,
     "e2": {"rxPduUndecodable": 0, "ctrlSendFailed": 0},
     "ipc": {"badJson": 0, "lineTooLong": 0, "helloRejected": 0, "ueContext": 2, "ueContextRejected": 0}}
exec(sys.argv[2])
open(sys.argv[1], "w").write("stats " + json.dumps(s) + "\n" + json.dumps(s) + "\n")
PY
}
acs good 'pass'; acs noctx 's["samplesNoUeContext"] = 1'; acs rej 's["ipc"]["ueContextRejected"] = 1'; acs none 's["ipc"]["ueContext"] = 0'
agent_counters_assert "$tmp/good.json" 10 >/dev/null || { echo "agent_counters_assert: a clean stats line was red"; rc=1; }
for c in noctx rej none; do
    agent_counters_assert "$tmp/$c.json" 10 >/dev/null && { echo "agent_counters_assert: the $c UE-context stats line passed"; rc=1; }
done
rm -rf "$tmp"
if grep -nE '(\blogs\b[^|#]*|"\$[a-z_]*logs?"\s*)\|\s*(grep\s+-[a-zA-Z]*[qm]|head\b)' scripts/gates/*.sh |
    grep -vE '^[^:]+:[0-9]+:\s*#'; then
    echo "an early-exit reader on a log pipe (see above): SIGPIPE under pipefail"; rc=1
fi
# ts_threshold_logged: a stale threshold line before this call's first payload line must not pass, this
# call's own line after it must; the old `| grep -q` construction must die of SIGPIPE on a large log.
source <(sed -n '/^ts_threshold_logged()/,/^}/p' scripts/gates/ts-lib.sh)
fx=scripts/gates/fixtures/ts-threshold-log.txt tmp=$(mktemp -d)
head -n 5 "$fx" >"$tmp/stale.txt"
head -n 6 "$fx" >"$tmp/own.txt"
{ head -n 3 "$fx"; for _ in $(seq 12000); do head -n 1 "$fx"; done; } >"$tmp/big.txt"
ts_threshold_logged "$tmp/stale.txt" i2-20261024T032221Z 10 && { echo "ts_threshold_logged passed on a stale line"; rc=1; }
ts_threshold_logged "$tmp/own.txt" i2-20261024T032221Z 10 || { echo "ts_threshold_logged missed this call's line"; rc=1; }
ts_threshold_logged "$tmp/own.txt" i2-20261024T032221Z 20 && { echo "ts_threshold_logged ignored the threshold value"; rc=1; }
ts_threshold_logged "$tmp/own.txt" i2-20261024T030903Z 10 && { echo "ts_threshold_logged matched another run's id"; rc=1; }
# _ts_token_redact fails closed: with no config map (kubectl down) it still redacts through the auth-token file; a
# malformed source or a named-but-unreadable token wipes the file and returns 1; no source at all is a no-op.
# The token is random, in memory and in the test files only, and is never printed.
source <(sed -n '/^_ts_token_redact()/,/^}/p' scripts/gates/ts-lib.sh)
kc() { return 1; }
rtmp=$(mktemp -d); mkdir -p "$rtmp/ric/xApps/ts/xapp-descriptor"
rtok=$(python3 -I -c 'import secrets; print(secrets.token_urlsafe(66))')
(
    RIC_DIR="$rtmp/ric"; TS_DIR="$rtmp/ric/xApps/ts"; f="$rtmp/ev.txt"
    printf '{"token": "%s"}' "$rtok" >"$RIC_DIR/influxdb_auth_token.json"; echo "a $rtok b" >"$f"
    _ts_token_redact "$f" && ! grep -qF -- "$rtok" "$f" && grep -q REDACTED-INFLUX-TOKEN "$f" ||
        { echo "_ts_token_redact did not redact through the auth-token file"; exit 1; }
    echo '{"token": ' >"$RIC_DIR/influxdb_auth_token.json"; echo "a $rtok b" >"$f"
    _ts_token_redact "$f" 2>/dev/null && { echo "_ts_token_redact passed a malformed auth-token file"; exit 1; }
    grep -qF -- "$rtok" "$f" && { echo "_ts_token_redact kept the token after failing"; exit 1; }
    rm -f "$RIC_DIR/influxdb_auth_token.json"; echo '{"controls": {"influx_token": ""}}' >"$TS_DIR/xapp-descriptor/config-file_updated.json"
    echo "a b" >"$f"
    _ts_token_redact "$f" 2>/dev/null && { echo "_ts_token_redact passed a named but unreadable token"; exit 1; }
    rm -f "$TS_DIR/xapp-descriptor/config-file_updated.json"; echo "a b" >"$f"
    _ts_token_redact "$f" && [ "$(cat "$f")" = "a b" ] || { echo "_ts_token_redact changed a file with no token source"; exit 1; }
) || rc=1
unset -f kc; rm -rf "$rtmp"; unset rtok
# rc-send.sh reads exactly one UE ID line: two lines are refused, with or without a final newline, before any send.
rtmp=$(mktemp -d)
printf 'enGnbUeId:1@00F110-00001\nenGnbUeId:2@00F110-00001' >"$rtmp/unterminated"
printf 'enGnbUeId:1@00F110-00001\nenGnbUeId:2@00F110-00001\n' >"$rtmp/terminated"
for u in unterminated terminated; do
    bash scripts/gates/rc-send.sh 127.0.0.1:1 2 --ue-from "$rtmp/$u" 0000000210 >/dev/null 2>&1
    [ $? -eq 2 ] || { echo "rc-send.sh accepted a two-line UE ID file ($u)"; rc=1; }
done
rm -rf "$rtmp"
# shellcheck disable=SC2002
cat "$tmp/big.txt" | grep -q 'Setting Threshold for A1-P value: 10%'
[ "${PIPESTATUS[0]}" = 141 ] || { echo "fixture of $(wc -c <"$tmp/big.txt") B did not reproduce the SIGPIPE"; rc=1; }
rm -rf "$tmp"
# rc_restarts_zero_all: every run a mode makes needs a non-empty after-snapshot with all restart counts 0; a list
# without the c1-only runs passes, an empty list or file does not, and the fact form is exactly one word
source <(sed -n '/^rc_restarts_zero()/,/^}/p; /^rc_restarts_zero_all()/,/^}/p' scripts/gates/rc-lib.sh)
EVIDENCE_DIR=$(mktemp -d)
ok=$'pod\tricxapp-rc-a\tu\t0\t-\t-\nagent\t1\tc\t0\t-\t-'
printf '%s\n' "$ok" >"$EVIDENCE_DIR/live1-after-pods.tsv"
rc_restarts_zero_all live1 >/dev/null || { echo "restart judge: a single-mode run list was red"; rc=1; }
rc_restarts_zero_all live1 k9 >/dev/null && { echo "restart judge: a missing k9 snapshot passed"; rc=1; }
rc_restarts_zero_all >/dev/null && { echo "restart judge: an empty run list passed"; rc=1; }
: >"$EVIDENCE_DIR/k9-after-pods.tsv"
rc_restarts_zero_all live1 k9 >/dev/null && { echo "restart judge: an empty snapshot passed"; rc=1; }
printf '%s\n' "$ok" $'pod\tricxapp-trafficxapp-b\tu\t1\t-\t-' >"$EVIDENCE_DIR/k9-after-pods.tsv"
rc_restarts_zero_all live1 k9 >/dev/null && { echo "restart judge: a restart count of 1 passed"; rc=1; }
printf '%s\n' "$ok" >"$EVIDENCE_DIR/k9-after-pods.tsv"
rc_restarts_zero_all live1 k9 >/dev/null || { echo "restart judge: a complete c1 run list was red"; rc=1; }
[ "$(rc_restarts_zero_all live1 live2 >/dev/null 2>&1 && echo true || echo false)" = false ] ||
    { echo "restart fact form is not exactly false"; rc=1; }
rm -rf "$EVIDENCE_DIR"
# scrub-evidence.sh fails closed: exit 0 only when the exact-secret scan ran (token file read) or provably had
# nothing to scan (no token file and no InfluxDB pod); the exporters copy nothing after a failed scrub
tmp=$(mktemp -d); mkdir -p "$tmp/ric" "$tmp/ev" "$tmp/kc" "$tmp/nokc"
ln -s "$(command -v python3)" "$tmp/nokc/python3"; ln -s "$(command -v grep)" "$tmp/nokc/grep"
tok="tok$(printf 'x%.0s' $(seq 85))" adm="adm$(printf 'y%.0s' $(seq 29))"
scrub() { NIST_RIC_DIR="$tmp/ric" PATH="$1" "$BASH" scripts/gates/scrub-evidence.sh "$2" >/dev/null 2>&1; }
# fake kubectl: `get pods` runs $1; `get pod` prints a pod spec whose DOCKER_INFLUXDB_INIT_ADMIN_TOKEN comes from
# secret `auth` key `admin-token` (or, with $3 = literal, is the literal $2); `get secret` prints that secret holding
# $2, or fails when $2 is empty. There is no `exec`: an evicted pod cannot be exec'd into, and the scrub must not need it.
kc() {
    local env sec
    if [ "${3:-}" = literal ]; then env="{\"name\": \"DOCKER_INFLUXDB_INIT_ADMIN_TOKEN\", \"value\": \"${2:-}\"}"
    else env='{"name": "DOCKER_INFLUXDB_INIT_ADMIN_TOKEN", "valueFrom": {"secretKeyRef": {"name": "auth", "key": "admin-token"}}}'; fi
    if [ -n "${2:-}" ] && [ "${3:-}" != literal ]; then sec="echo '{\"data\": {\"admin-token\": \"$(printf %s "$2" | base64 -w0)\"}}'"
    else sec="exit 1"; fi
    printf '#!/bin/sh\ncase "$1 $2" in\n"get pods") %s ;;\n"get pod") echo '"'"'{"spec": {"containers": [{"env": [%s]}]}}'"'"' ;;\n"get secret") %s ;;\n*) exit 1 ;;\nesac\n' \
        "$1" "$env" "$sec" >"$tmp/kc/kubectl"
    chmod +x "$tmp/kc/kubectl"
}
printf '{"token": "%s"}' "$tok" >"$tmp/ric/influxdb_auth_token.json"; echo "x $tok y $adm z" >"$tmp/ev/log.txt"
kc 'echo "ricplt r4-influxdb-influxdb2-0 1/1 Running 0 1d"' "$adm"
scrub "$tmp/kc:$PATH" "$tmp/ev" && ! grep -q "$tok" "$tmp/ev/log.txt" && ! grep -q "$adm" "$tmp/ev/log.txt" ||
    { echo "scrub: the file token or the pod's admin token was not redacted"; rc=1; }
# an in-cluster Influx ueId read: both tokens go, every ueId string stays byte-unchanged
uid1='enGnbUeId:3@00F110-00001' uid2='enbUeId:1@3'
{ printf 'from(bucket: "kpimon") |> filter(fn: (r) => r.ueId == "%s" or r.ueId == "%s")\n' "$uid1" "$uid2"
  printf 'Authorization: Token %s\nAuthorization: Token %s\n' "$tok" "$adm"
  printf ',result,table,_time,ueId,ns3.imsi\n,,0,2026-11-04T00:00:00Z,%s,1\n,,1,2026-11-04T00:00:00Z,%s,1\n' "$uid1" "$uid2"
} >"$tmp/ev/influx-ueid-read.txt"
grep -o 'enGnbUeId:[^",]*\|enbUeId:[^",]*' "$tmp/ev/influx-ueid-read.txt" >"$tmp/ueids.before"
scrub "$tmp/kc:$PATH" "$tmp/ev" && ! grep -q "$tok" "$tmp/ev/influx-ueid-read.txt" && ! grep -q "$adm" "$tmp/ev/influx-ueid-read.txt" &&
    grep -o 'enGnbUeId:[^",]*\|enbUeId:[^",]*' "$tmp/ev/influx-ueid-read.txt" | cmp -s - "$tmp/ueids.before" &&
    [ "$(wc -l <"$tmp/ueids.before")" = 4 ] ||
    { echo "scrub: an Influx ueId read kept a token or changed a ueId string"; rc=1; }
kc 'echo "ricplt r4-influxdb-influxdb2-0 1/1 Running 0 1d"'
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: an unreadable admin token in a deployed InfluxDB pod passed"; rc=1; }
# an evicted InfluxDB pod: its spec and secret still give the admin token
echo "x $adm z" >"$tmp/ev/evicted.txt"
kc 'echo "ricplt r4-influxdb-influxdb2-0 0/1 Evicted 0 1d"' "$adm"
scrub "$tmp/kc:$PATH" "$tmp/ev" && ! grep -q "$adm" "$tmp/ev/evicted.txt" ||
    { echo "scrub: an evicted InfluxDB pod's admin token (from its secret) was not redacted"; rc=1; }
echo "x $adm z" >"$tmp/ev/evicted.txt"
kc 'echo "ricplt r4-influxdb-influxdb2-0 1/1 Running 0 1d"' "$adm" literal
scrub "$tmp/kc:$PATH" "$tmp/ev" && ! grep -q "$adm" "$tmp/ev/evicted.txt" ||
    { echo "scrub: a literal admin token in the pod spec was not redacted"; rc=1; }
kc 'echo "ricplt r4-influxdb-influxdb2-0 1/1 Running 0 1d"' "short" literal
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: an admin token under 20 characters passed"; rc=1; }
kc 'echo "ricplt r4-influxdb-influxdb2-0 1/1 Running 0 1d"' "$adm"
echo '{"token": ' >"$tmp/ric/influxdb_auth_token.json"
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: an unparseable token file passed"; rc=1; }
echo '{"token": "short"}' >"$tmp/ric/influxdb_auth_token.json"
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: a token file without a secret passed"; rc=1; }
printf '{"token": "%s"}' "${tok:0:40}" >"$tmp/ric/influxdb_auth_token.json"
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: a 40-character file token (not an Influx v2 token) passed"; rc=1; }
if [ "$(id -u)" != 0 ]; then
    printf '{"token": "%s"}' "$tok" >"$tmp/ric/influxdb_auth_token.json"; chmod 000 "$tmp/ric/influxdb_auth_token.json"
    scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: an unreadable token file passed"; rc=1; }
    chmod 600 "$tmp/ric/influxdb_auth_token.json"
    echo data >"$tmp/ev/locked.txt"; chmod 000 "$tmp/ev/locked.txt"
    scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: an unreadable evidence file passed"; rc=1; }
    rm -f "$tmp/ev/locked.txt"
fi
rm -f "$tmp/ric/influxdb_auth_token.json"
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: no token file with an InfluxDB pod passed"; rc=1; }
kc 'echo "The connection to the server was refused" >&2; exit 1'
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: no token file with a failing kubectl passed"; rc=1; }
kc 'echo "kube-system coredns-1 1/1 Running 0 1d"'
scrub "$tmp/kc:$PATH" "$tmp/ev" || { echo "scrub: no token file and no InfluxDB pod was red"; rc=1; }
scrub "$tmp/nokc" "$tmp/ev" || { echo "scrub: no token file and no kubectl (pre-RIC) was red"; rc=1; }
scrub "$tmp/nokc" "$tmp/missing" && { echo "scrub: a missing evidence dir passed"; rc=1; }
rm -rf "$tmp"
for f in scripts/vm/vm-exec.sh scripts/probes/vm-exec-probe.sh; do
    grep -A1 'scrub-evidence.sh \$ev"' "$f" | grep -q '^ *die "evidence scrub failed' ||
        { echo "$f: a failed scrub does not stop the evidence copy"; rc=1; }
done
# a check whose command is `bash -c "judge | tee f"` returns tee's status (a child bash does not inherit pipefail),
# so a red judge would pass: such a child shell must run with -o pipefail
if grep -nE 'check [^#]*bash -c "[^"]*\| *tee' scripts/gates/gate-*.sh; then
    echo "a check pipes inside bash -c without -o pipefail (see above): the judge's exit status is lost"; rc=1
fi
# a silenced cat of a named evidence file into a pipe: a mode that skips that run makes cat fail, pipefail red
if grep -nE 'cat [^|#]*"\$e"/[A-Za-z0-9_]+-[A-Za-z0-9_.-]+ [^|#]*2>/dev/null *\|[^|]' scripts/gates/*.sh; then
    echo "a silenced cat of a named evidence file into a pipe (see above)"; rc=1
fi
[ "$rc" = 0 ] && echo "lint: ok"
exit "$rc"

#!/usr/bin/env bash
# lint.sh: static checks for the gate harness; run before pushing a harness SHA.
#   1. bash -n on every script;
#   2. shellcheck (warnings) when installed;
#   3. no external wrapper (timeout, nist_run, sudo, env, xargs) around a shell
#      function defined in the harness: such wrappers exec a binary and fail
#      with "No such file or directory" at run time;
#   4. no `<logs> | grep -q|-m` or `| head`: the reader exits early, the writer dies of SIGPIPE and pipefail
#      turns that into a false failure (use a here-string, process substitution or a file);
#   5. ts_threshold_logged on a real TS xApp log fixture.
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
tok="tok$(printf 'x%.0s' $(seq 40))"
scrub() { NIST_RIC_DIR="$tmp/ric" PATH="$1" "$BASH" scripts/gates/scrub-evidence.sh "$2" >/dev/null 2>&1; }
kc() { printf '#!/bin/sh\n%s\n' "$1" >"$tmp/kc/kubectl"; chmod +x "$tmp/kc/kubectl"; }
printf '{"token": "%s"}' "$tok" >"$tmp/ric/influxdb_auth_token.json"; echo "x $tok y" >"$tmp/ev/log.txt"
kc 'echo "ricplt r4-influxdb-influxdb2-0 1/1 Running 0 1d"'
scrub "$tmp/kc:$PATH" "$tmp/ev" && ! grep -q "$tok" "$tmp/ev/log.txt" || { echo "scrub: a readable token was not redacted"; rc=1; }
echo '{"token": ' >"$tmp/ric/influxdb_auth_token.json"
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: an unparseable token file passed"; rc=1; }
echo '{"token": "short"}' >"$tmp/ric/influxdb_auth_token.json"
scrub "$tmp/kc:$PATH" "$tmp/ev" && { echo "scrub: a token file without a secret passed"; rc=1; }
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
# a silenced cat of a named evidence file into a pipe: a mode that skips that run makes cat fail, pipefail red
if grep -nE 'cat [^|#]*"\$e"/[A-Za-z0-9_]+-[A-Za-z0-9_.-]+ [^|#]*2>/dev/null *\|[^|]' scripts/gates/*.sh; then
    echo "a silenced cat of a named evidence file into a pipe (see above)"; rc=1
fi
[ "$rc" = 0 ] && echo "lint: ok"
exit "$rc"

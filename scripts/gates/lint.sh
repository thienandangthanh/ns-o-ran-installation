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
ids=$(for s in gate-m5-agent-setup.sh gate-r0-rc-scripted.sh gate-s1-pacer-lockstep.sh gate-q7-qp-token-check.sh; do
    gate_id "$s"; done | paste -sd' ')
echo "gate ids: $ids"
[ "$ids" = "m5 r0 s1 q7" ] || { echo "gate-id regex broken"; rc=1; }
python3 -I scripts/gates/pod-log-window.py --self-test || rc=1
python3 -I scripts/gates/check-c9-handover-trace.py --self-test >/dev/null || { echo "c9 handover matcher self-test failed"; rc=1; }
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
[ "$rc" = 0 ] && echo "lint: ok"
exit "$rc"

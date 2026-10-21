#!/usr/bin/env bash
# lint.sh: static checks for the gate harness; run before pushing a harness SHA.
#   1. bash -n on every script;
#   2. shellcheck (warnings) when installed;
#   3. no external wrapper (timeout, nist_run, sudo, env, xargs) around a shell
#      function defined in the harness: such wrappers exec a binary and fail
#      with "No such file or directory" at run time.
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
[ "$rc" = 0 ] && echo "lint: ok"
exit "$rc"

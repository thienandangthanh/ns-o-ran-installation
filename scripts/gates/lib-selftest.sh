#!/usr/bin/env bash
# lib-selftest.sh: host self-test of two lib.sh helpers and the agents' port check parser (run by lint.sh).
#   fact():     an empty value is written as null, text that is not JSON as a JSON string, JSON re-serialised onto
#               one line; every facts.jsonl line parses.
#   nist_run(): a command is stopped and nist_run returns 1 when the root's use is above NIST_RUN_MAX_ROOT_PCT; a
#               command below it returns its own status.
#   agents_ports_held(): lists the non-TIME-WAIT sockets whose local port is in AGENT_RESERVED_PORTS, nothing else.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
tmp=$(mktemp -d); trap 'rm -rf "${tmp:?}"' EXIT
export EVIDENCE_DIR="$tmp"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

fact empty ""
fact text "not json"
fact obj '{
  "a": 1
}'
fact num 3
python3 -I - "$tmp/facts.jsonl" <<'PY' || fail=1
import json, sys
got = {}
for line in open(sys.argv[1]):
    d = json.loads(line)          # every line parses
    got[d["key"]] = d["value"]
want = {"empty": None, "text": "not json", "obj": {"a": 1}, "num": 3}
if got != want:
    print("FAIL: fact values", got, "want", want)
    sys.exit(1)
PY
[ "$(wc -l <"$tmp/facts.jsonl")" -eq 4 ] || bad "fact wrote $(wc -l <"$tmp/facts.jsonl") lines, want 4"

used=$(df --output=pcent / | tail -1 | tr -dc '0-9')
start=$(date +%s)
NIST_RUN_MAX_ROOT_PCT=$((used - 1)) NIST_RUN_POLL_S=1 nist_run 120 sleep 100 2>"$tmp/guard.err"
rc=$?
[ "$rc" -eq 1 ] || bad "nist_run above the root threshold returned $rc, want 1"
[ $(($(date +%s) - start)) -lt 30 ] || bad "nist_run did not stop the command promptly"
grep -q 'guest root .* > .*: stopping sleep' "$tmp/guard.err" || bad "nist_run logged no stop line"
pgrep -f '^sleep 100$' >/dev/null && bad "the stopped command is still running"

NIST_RUN_MAX_ROOT_PCT=100 nist_run 30 sh -c 'exit 7'
rc=$?
[ "$rc" -eq 7 ] || bad "nist_run under the threshold returned $rc, want the command's 7"
NIST_RUN_MAX_ROOT_PCT=100 nist_run 2 sleep 30
rc=$?
[ "$rc" -eq 124 ] || bad "nist_run past its time bound returned $rc, want timeout's 124"

# shellcheck source=agents.sh
source "$here/agents.sh" >/dev/null 2>&1
printf '%s\n' 'ESTAB 0 0 127.0.0.1:38491 127.0.0.1:5432' 'TIME-WAIT 0 0 127.0.0.1:38472 127.0.0.1:41000' \
    'LISTEN 0 4096 [::1]:38499 [::]:*' 'ESTAB 0 0 10.0.0.1:38500 10.0.0.2:22' 'ESTAB 0 0 10.0.0.1:41000 127.0.0.1:38472' \
    'LISTEN 0 4096 *:38469 *:*' >"$tmp/ss.txt"
held=$(agents_ports_held "$tmp/ss.txt")
want=$'ESTAB 127.0.0.1:38491 127.0.0.1:5432\nLISTEN [::1]:38499 [::]:*'
[ "$held" = "$want" ] || bad "agents_ports_held listed '$held', want '$want'"
[ -z "$(printf 'TIME-WAIT 0 0 127.0.0.1:38480 1.2.3.4:5\n' | agents_ports_held /dev/stdin)" ] || bad "TIME-WAIT counted as held"

[ "$fail" -eq 0 ] && echo "lib self-test: ok"
exit "$fail"

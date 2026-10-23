#!/usr/bin/env bash
# influx-dump.sh: Influx dump of the kpimon bucket (VM side). Source after lib.sh, kpimon.sh and rc-lib.sh.
#
#   influx_dump <out.csv>   the whole kpimon bucket as annotated CSV
#
# The query runs inside the InfluxDB pod through rc-lib's _influx, with the pod's own token expanded inside the
# pod: the token never reaches this shell, argv or a log. The dump is then checked on the VM against every
# secret NIST's token file holds (the file scrub-evidence.sh reads) and the influx v2 token shape; only counts
# are printed, and any hit fails the dump. Evidence only: never a QP input (UL-off rows).
NIST_RIC_DIR="${NIST_RIC_DIR:-$HOME/nist/RAN_Intelligent_Controllers/Near-Real-Time-RIC}"

influx_dump() {
    local out="$1"
    _influx query --org influxdata --raw 'from(bucket: "kpimon") |> range(start: 0)' >"$out" 2>/dev/null || {
        echo "influx query failed"; return 1; }
    python3 -I - "$out" "$NIST_RIC_DIR/influxdb_auth_token.json" <<'PY'
import json, re, sys
out, token_file = sys.argv[1:]
secrets = set()
def walk(v):
    if isinstance(v, str) and len(v) >= 20:
        secrets.add(v)
    elif isinstance(v, dict):
        for x in v.values():
            walk(x)
    elif isinstance(v, list):
        for x in v:
            walk(x)
try:
    walk(json.load(open(token_file)))
except (OSError, ValueError):
    print("no readable token file: the exact-token check cannot run")
    sys.exit(1)
text = open(out, errors="replace").read()
rows = sum(1 for l in text.splitlines() if l and not l.startswith("#") and not l.startswith(",result"))
exact = sum(text.count(s) for s in secrets)
shaped = len(re.findall(r"[A-Za-z0-9_\-]{80,}==", text))
print(json.dumps({"rows": rows, "bytes": len(text), "knownSecrets": len(secrets), "tokenHits": exact, "tokenShapeHits": shaped}))
sys.exit(0 if rows > 0 and secrets and exact == 0 and shaped == 0 else 1)
PY
}

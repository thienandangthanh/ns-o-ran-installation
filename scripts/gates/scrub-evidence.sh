#!/usr/bin/env bash
# scrub-evidence.sh <evidence-dir>: redact secrets in place before evidence
# leaves the VM. Covers the InfluxDB token NIST stores in
# influxdb_auth_token.json (and seds into kpimon's control.go), plus any long
# base64 token-looking string. Binary files (pcaps) are left alone; they carry
# only SCTP/E2AP traffic.

set -uo pipefail
dir="$1"
[ -d "$dir" ] || exit 0
NIST_RIC_DIR="${NIST_RIC_DIR:-$HOME/nist/RAN_Intelligent_Controllers/Near-Real-Time-RIC}"

python3 - "$dir" "$NIST_RIC_DIR/influxdb_auth_token.json" <<'PY'
import json, os, re, sys
root, token_file = sys.argv[1:]
secrets = set()
def walk(v):
    if isinstance(v, str) and len(v) >= 20:
        secrets.add(v)
    elif isinstance(v, dict):
        for x in v.values(): walk(x)
    elif isinstance(v, list):
        for x in v: walk(x)
try:
    walk(json.load(open(token_file)))
except Exception:
    pass
token_re = re.compile(r'[A-Za-z0-9_\-]{80,}==')  # influx v2 shape; never matches 64-hex digests
redacted = 0
for d, _, files in os.walk(root):
    for f in files:
        p = os.path.join(d, f)
        if f.endswith(('.pcap', '.pcapng', '.gz')):
            continue
        try:
            text = open(p, encoding='utf-8').read()
        except (UnicodeDecodeError, OSError):
            continue
        new = text
        for s in secrets:
            new = new.replace(s, 'REDACTED-INFLUX-TOKEN')
        new = token_re.sub('REDACTED-TOKEN', new)
        if new != text:
            open(p, 'w', encoding='utf-8').write(new)
            redacted += 1
print(f"scrub: {redacted} file(s) redacted, {len(secrets)} known secret(s)")
PY

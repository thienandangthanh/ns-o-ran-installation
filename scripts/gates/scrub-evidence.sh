#!/usr/bin/env bash
# scrub-evidence.sh <evidence-dir>: redact secrets in place before evidence
# leaves the VM. Covers the InfluxDB token NIST stores in
# influxdb_auth_token.json (and seds into kpimon's control.go), plus any long
# base64 token-looking string. Binary files (pcaps) are left alone; they carry
# only SCTP/E2AP traffic.
#
# Fails closed (exit non-zero, the caller must not copy the evidence) when the
# exact-secret scan cannot run:
#   - the evidence dir is missing;
#   - the token file exists but cannot be read, parsed, or yields no secret;
#   - the token file is absent while an InfluxDB pod is deployed, or kubectl is
#     installed but cannot list pods (absent is fine only before the RIC exists:
#     no kubectl at all, or kubectl lists no influx pod);
#   - an evidence text file cannot be read or written.

set -uo pipefail
dir="$1"
[ -d "$dir" ] || { echo "scrub: no evidence dir $dir" >&2; exit 2; }
NIST_RIC_DIR="${NIST_RIC_DIR:-$HOME/nist/RAN_Intelligent_Controllers/Near-Real-Time-RIC}"
token_file="$NIST_RIC_DIR/influxdb_auth_token.json"

if [ ! -e "$token_file" ]; then
    if command -v kubectl >/dev/null; then
        pods=$(kubectl get pods -A --no-headers 2>&1) || { echo "scrub: no token file and kubectl cannot list pods: $pods" >&2; exit 3; }
        if grep -qi influx <<<"$pods"; then
            echo "scrub: an InfluxDB pod is deployed but $token_file is absent" >&2; exit 3
        fi
    fi
    echo "scrub: no token file and no InfluxDB deployed: regex scan only"
fi

python3 - "$dir" "$token_file" <<'PY'
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
if os.path.lexists(token_file):
    try:
        walk(json.load(open(token_file)))
    except (OSError, ValueError) as e:
        sys.exit(f"scrub: cannot read the token file {token_file}: {e}")
    if not secrets:
        sys.exit(f"scrub: the token file {token_file} yields no secret")
token_re = re.compile(r'[A-Za-z0-9_\-]{80,}==')  # influx v2 shape; never matches 64-hex digests
redacted = 0
for d, _, files in os.walk(root, onerror=lambda e: sys.exit(f"scrub: cannot walk {e.filename}: {e}")):
    for f in files:
        p = os.path.join(d, f)
        if f.endswith(('.pcap', '.pcapng', '.gz')) or os.path.islink(p):
            continue
        try:
            text = open(p, encoding='utf-8').read()
        except UnicodeDecodeError:
            continue  # binary: no text secret to redact
        except OSError as e:
            sys.exit(f"scrub: cannot read {p}: {e}")
        new = text
        for s in secrets:
            new = new.replace(s, 'REDACTED-INFLUX-TOKEN')
        new = token_re.sub('REDACTED-TOKEN', new)
        if new != text:
            try:
                open(p, 'w', encoding='utf-8').write(new)
            except OSError as e:
                sys.exit(f"scrub: cannot rewrite {p}: {e}")
            redacted += 1
print(f"scrub: {redacted} file(s) redacted, {len(secrets)} known secret(s)")
PY

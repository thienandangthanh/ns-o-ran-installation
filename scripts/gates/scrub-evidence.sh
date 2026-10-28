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
#   - the token file exists but cannot be read or parsed, or its "token" is not
#     an Influx v2 token (>= 80 characters);
#   - kubectl is installed but cannot list pods;
#   - the token file is absent while an InfluxDB pod is deployed (absent is fine
#     only before the RIC exists: no kubectl at all, or no influx pod);
#   - an InfluxDB pod is deployed and its admin token (the pod environment's
#     DOCKER_INFLUXDB_INIT_ADMIN_TOKEN, which the harness's in-pod queries use)
#     cannot be read into memory: it is redacted like the file's secrets and is
#     never printed or written;
#   - an evidence text file cannot be read or written.

set -uo pipefail
dir="$1"
[ -d "$dir" ] || { echo "scrub: no evidence dir $dir" >&2; exit 2; }
NIST_RIC_DIR="${NIST_RIC_DIR:-$HOME/nist/RAN_Intelligent_Controllers/Near-Real-Time-RIC}"
token_file="$NIST_RIC_DIR/influxdb_auth_token.json"

influx_pod=""
if command -v kubectl >/dev/null; then
    pods=$(kubectl get pods -A --no-headers 2>&1) || { echo "scrub: kubectl cannot list pods: $pods" >&2; exit 3; }
    influx_pod=$(awk 'tolower($2) ~ /influx/ { print $1 "/" $2; exit }' <<<"$pods")
fi
if [ ! -e "$token_file" ]; then
    [ -z "$influx_pod" ] || { echo "scrub: an InfluxDB pod is deployed but $token_file is absent" >&2; exit 3; }
    echo "scrub: no token file and no InfluxDB deployed: regex scan only"
fi

python3 - "$dir" "$token_file" "$influx_pod" <<'PY'
import json, os, re, subprocess, sys
root, token_file, influx_pod = sys.argv[1:]
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
    tok = json.load(open(token_file)).get("token") if secrets else None
    if not isinstance(tok, str) or len(tok) < 80:
        sys.exit(f"scrub: the token file {token_file} holds no Influx v2 token")
if influx_pod:
    ns, pod = influx_pod.split("/", 1)
    try:
        admin = subprocess.run(["kubectl", "exec", "-n", ns, pod, "--", "sh", "-c", 'printf %s "$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN"'],
                               capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL).stdout
    except (OSError, subprocess.TimeoutExpired):
        admin = ""
    if len(admin) < 20:
        sys.exit("scrub: cannot read the InfluxDB pod's admin token into memory")
    secrets.add(admin)
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

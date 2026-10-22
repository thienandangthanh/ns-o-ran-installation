#!/usr/bin/env bash
# test-rc-decode.sh [image-tag]: the decoder must
#   1. decode every committed RICcontrolRequest fixture PDU (probe pcap,
#      tshark-extracted RICcontrolHeader/RICcontrolMessage octets) with RC_OK
#      and every octet consumed;
#   2. show ric-Style-Type 3 and ric-ControlAction-ID 1 in each header
#      (E2SM-RC Connected Mode Mobility, Handover control) and the NR CGI
#      (RAN parameter 4 under Target Primary Cell ID) in each message;
#   3. round-trip a synthesized ControlOutcome Format 1 with an empty ranP-List.
set -uo pipefail
cd "$(dirname "$0")"
tag="${1:-$(./build.sh)}"
eng=docker; command -v docker >/dev/null || eng=podman
if ! $eng info >/dev/null 2>&1; then eng="sudo -n docker"; fi
fx=fixtures/rc-control-requests.hex
n=$(grep -c . "$fx")
tmp=$(mktemp)
awk '{print $1".h header "$2; print $1".m message "$3}' "$fx" | $eng run --rm -i "$tag" >"$tmp"
python3 - "$n" "$tmp" <<'PY'
import json, re, sys
n, path = int(sys.argv[1]), sys.argv[2]
rows = [json.loads(l) for l in open(path)]
hdr = [r for r in rows if r["type"] == "header"]
msg = [r for r in rows if r["type"] == "message"]
bad = []
for r in hdr:
    x = re.sub(r"\s+", "", r["xer"])
    if not (r["ok"] and "<ric-Style-Type>3</ric-Style-Type>" in x and "<ric-ControlAction-ID>1</ric-ControlAction-ID>" in x):
        bad.append(r["id"])
for r in msg:
    x = re.sub(r"\s+", "", r["xer"])
    if not (r["ok"] and re.search(r"<ranParameter-ID>4</ranParameter-ID><ranParameter-valueType><ranP-Choice-ElementFalse><ranParameter-value><valueOctS>[0-9A-F]+</valueOctS>", x)):
        bad.append(r["id"])
print(f"fixture lines {n}; headers ok {len(hdr) - sum(i.endswith('.h') for i in bad)}; messages ok {len(msg) - sum(i.endswith('.m') for i in bad)}")
sys.exit(0 if len(hdr) == n and len(msg) == n and not bad else 1)
PY
rc=$?
rm -f "$tmp"
$eng run --rm "$tag" --selftest-outcome || rc=1
[ "$rc" = 0 ] && echo "test-rc-decode: ok"
exit "$rc"

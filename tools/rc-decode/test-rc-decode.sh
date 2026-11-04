#!/usr/bin/env bash
# test-rc-decode.sh [image-tag]: the decoder (RANParameter-ID bounded 1..4294967295, ...) must
#   1. on fixtures/rc-control-nrcgi.hex (X.691 octets from tools/asn1-indep, make-nrcgi-fixture.py):
#      decode every header and message with RC_OK, every octet consumed and an exact APER re-encode
#      (asn1c == X.691); s3a1-* headers ric-Style-Type 3 / ric-ControlAction-ID 1 with a gNB-UEID, s5a3-x2ap<X>-*
#      headers ric-Style-Type 5 / ric-ControlAction-ID 3 with exactly the en-gNB-UEID {m-eNB-UE-X2AP-ID X,
#      globalENB-ID {00F110, macro eNB ID 1}} and no optional member; messages the RAN parameter
#      path 1 > 2 > 3 > 4 with parameter 4 = the APER NR-CGI named by the line id (gNB n: 0000F110 0000000n 10);
#   2. on fixtures/rc-control-requests.hex (the 30 M8 captures, kept byte-identical as history): decode
#      every header as above, and refuse every message (the unbounded RANParameter-ID encoding is not
#      E2SM-RC: not RC_OK, octets left, a different re-encode, or no 1 > 2 > 3 > 4 path);
#   3. round-trip a synthesized ControlOutcome Format 1 with an empty ranP-List.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
tag="${1:-$(./build.sh)}"
eng=docker; command -v docker >/dev/null || eng=podman
if ! $eng info >/dev/null 2>&1; then eng="sudo -n docker"; fi
tmp=$(mktemp)
for fx in fixtures/rc-control-nrcgi.hex fixtures/rc-control-requests.hex; do
    awk -v f="$(basename "$fx" .hex)" '{print f":"$1".h header "$2; print f":"$1".m message "$3}' "$fx"
done | $eng run --rm -i "$tag" >"$tmp"
python3 -I - "$tmp" fixtures/rc-control-nrcgi.hex fixtures/rc-control-requests.hex <<'PY'
import json, re, sys
path, nrcgi_fx, m8_fx = sys.argv[1:4]
rows = {r["id"]: r for r in map(json.loads, open(path))}
PATH = (r"<ranParameter-ID>1</ranParameter-ID><ranParameter-valueType><ranP-Choice-Structure><ranParameter-Structure>"
        r"<sequence-of-ranParameters><RANParameter-STRUCTURE-Item><ranParameter-ID>2</ranParameter-ID>.*?"
        r"<ranParameter-ID>3</ranParameter-ID>.*?<ranParameter-ID>4</ranParameter-ID><ranParameter-valueType>"
        r"<ranP-Choice-ElementFalse><ranParameter-value><valueOctS>([0-9A-F]+)</valueOctS>")
def flat(r): return re.sub(r"\s+", "", r["xer"])
def header_ok(r, kind="s3a1", x2ap=None):
    x = flat(r)
    if not (r["ok"] and r["reenc"]):
        return False
    if kind == "s3a1":
        return "<ric-Style-Type>3</ric-Style-Type>" in x and "<ric-ControlAction-ID>1</ric-ControlAction-ID>" in x and "<gNB-UEID>" in x
    ue = ("<ueID><en-gNB-UEID><m-eNB-UE-X2AP-ID>%d</m-eNB-UE-X2AP-ID><globalENB-ID><pLMNIdentity>00F110</pLMNIdentity>"
          "<eNB-ID><macro-eNB-ID>00000000000000000001</macro-eNB-ID></eNB-ID></globalENB-ID></en-gNB-UEID></ueID>" % x2ap)
    return (ue + "<ric-Style-Type>5</ric-Style-Type><ric-ControlAction-ID>3</ric-ControlAction-ID>") in x
def target(r):
    m = re.search(PATH, flat(r)) if r["ok"] and r["reenc"] else None
    return m.group(1) if m else None
bad = []
ids = [l.split()[0] for l in open(nrcgi_fx) if l.strip()]
for i in ids:
    gnb = int(re.search(r"gnb(\d+)$", i).group(1))
    want = "0000F110%08X10" % gnb
    h, m = rows.get(f"rc-control-nrcgi:{i}.h"), rows.get(f"rc-control-nrcgi:{i}.m")
    kind = i[:4]
    x2 = re.match(r"s5a3-x2ap(\d+)-", i)
    if kind not in ("s3a1", "s5a3") or (kind == "s5a3" and not x2): bad.append(f"nrcgi {i}: unknown fixture id")
    elif not (h and header_ok(h, kind, int(x2.group(1)) if x2 else None)): bad.append(f"nrcgi {i} header")
    if not (m and target(m) == want): bad.append(f"nrcgi {i} message (want {want}, got {m and target(m)})")
m8 = [l.split()[0] for l in open(m8_fx) if l.strip()]
for i in m8:
    h, m = rows.get(f"rc-control-requests:{i}.h"), rows.get(f"rc-control-requests:{i}.m")
    if not (h and header_ok(h)): bad.append(f"m8 {i} header")
    if not m or target(m) is not None: bad.append(f"m8 {i} message decoded strictly")
print(f"nrcgi fixture: {len(ids)} lines decoded strictly with the NR-CGI target; "
      f"M8 fixture: {len(m8)} headers decoded, {len(m8)} messages refused" if not bad else "FAIL " + "; ".join(bad))
if not any(i.startswith("s5a3-") for i in ids): bad.append("no Style 5 / action 3 fixture line")
if bad: print("FAIL " + "; ".join(bad))
sys.exit(0 if ids and len(m8) == 30 and not bad else 1)
PY
rc=$?
rm -f "$tmp"
$eng run --rm "$tag" --selftest-outcome || rc=1
[ "$rc" = 0 ] && echo "test-rc-decode: ok"
exit "$rc"

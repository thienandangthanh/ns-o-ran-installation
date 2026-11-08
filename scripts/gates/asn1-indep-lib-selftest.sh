#!/usr/bin/env bash
# asn1-indep-lib-selftest.sh [LIB]: host self-test of kpm_sub_decoded (asn1-indep-lib.sh, or LIB), run by lint.sh.
# A stub image (dk) and a stub decoder stand in for docker and e2-sub-setup-decode.py; the stub decode records each
# call and copies the capture's content into the sidecar, so a stale sidecar is visible. The sidecar is reused only
# when its provenance (capture sha256, decoder sha256, image tag and ID) matches the current ones:
#   a replaced capture, a changed decoder, another image ID, or a sidecar with missing or altered provenance is
#   decoded again; a cached sidecar never bypasses a missing image or a failing decode self-test; a failed decode
#   leaves no sidecar behind; a digest that cannot be computed fails before any cache lookup or decode.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lib="${1:-$here/asn1-indep-lib.sh}"
tmp=$(mktemp -d); trap 'rm -rf "${tmp:?}"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# shellcheck disable=SC2034  # HARNESS_DIR, ASN1_INDEP_DIR and GATE_TS are read by the sourced library
HARNESS_DIR="$tmp/harness"; ASN1_INDEP_DIR="$tmp/no-tarball"; GATE_TS=run1
mkdir -p "$HARNESS_DIR/tools/asn1-indep" "$HARNESS_DIR/tools/e2-evidence" "$ASN1_INDEP_DIR" "$tmp/e"
printf '#!/usr/bin/env bash\necho 0123456789abcdef\n' >"$HARNESS_DIR/tools/asn1-indep/image-tag.sh"
cat >"$HARNESS_DIR/tools/e2-evidence/e2-sub-setup-decode.py" <<'PY'
import json, os, sys
if sys.argv[1:] == ["--decode-self-test"]:
    sys.exit(1 if os.environ.get("STUB_SELFTEST_FAIL") else 0)
if sys.argv[1] == "collect":
    print(json.dumps({"capture": open(sys.argv[2]).read()}))
elif sys.argv[1] == "decode":
    open(os.environ["STUB_CALLS"], "a").write("decode\n")
    if os.environ.get("STUB_DECODE_FAIL"):
        sys.exit(1)
    print(json.dumps({"f1": [{"message": "E2setupRequest", "from": json.load(sys.stdin)["capture"]}]}))
PY
export STUB_CALLS="$tmp/calls"
: >"$STUB_CALLS"
FAKE_IMAGE_ID=sha256:aaaa

# dk: image inspect answers FAKE_IMAGE_ID (absent when empty), load fails, run executes the stub decoder on the host
dk() {
    case "$1" in
        image) [ -n "$FAKE_IMAGE_ID" ] && echo "$FAKE_IMAGE_ID" ;;
        load) return 1 ;;
        run)
            local a cmd=() on=0
            for a in "$@"; do
                [ "$a" = python3 ] && on=1
                [ "$on" = 1 ] && cmd+=("${a/#\/e2ev\//$HARNESS_DIR/tools/e2-evidence/}")
            done
            "${cmd[@]}" ;;
        *) return 1 ;;
    esac
}
# shellcheck source=asn1-indep-lib.sh
source "$lib"

pcap="$tmp/e/x.pcap"; facts="$tmp/e/x-facts.json"; side="$tmp/e/x-asn1-indep-decoded.json"
printf '{"pcap": "%s"}\n' "$pcap" >"$facts"
calls() { wc -l <"$STUB_CALLS"; }
from() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["f1"][0]["from"])' "$side" 2>/dev/null; }
run() { kpm_sub_decoded "$facts" >"$tmp/out" 2>"$tmp/err"; }

echo A >"$pcap"
run || bad "first decode failed: $(cat "$tmp/err")"
[ "$(from)" = A ] || bad "first sidecar decodes '$(from)', want A"
n=$(calls); run || bad "second call failed: $(cat "$tmp/err")"
[ "$(calls)" = "$n" ] || bad "an unchanged capture, decoder and image were decoded again"

echo B >"$pcap"
run || bad "decode after the capture was replaced failed: $(cat "$tmp/err")"
[ "$(from)" = B ] || bad "a replaced capture was judged on the old sidecar ('$(from)', want B)"

n=$(calls); echo "# changed" >>"$HARNESS_DIR/tools/e2-evidence/e2-sub-setup-decode.py"; run
[ "$(calls)" -gt "$n" ] || bad "a changed decoder script reused the sidecar"

n=$(calls); FAKE_IMAGE_ID=sha256:bbbb; run
[ "$(calls)" -gt "$n" ] || bad "another image ID reused the sidecar"

n=$(calls)
python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); d.pop("provenance", None); json.dump(d, open(sys.argv[1], "w"))' "$side"
run; [ "$(calls)" -gt "$n" ] || bad "a sidecar without provenance was reused"
n=$(calls)
python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); d.setdefault("provenance", {})["captureSha256"] = "0" * 64; json.dump(d, open(sys.argv[1], "w"))' "$side"
run; [ "$(calls)" -gt "$n" ] || bad "a sidecar with altered provenance was reused"

FAKE_IMAGE_ID=""
run && bad "a cached sidecar was used without the image"
FAKE_IMAGE_ID=sha256:bbbb

# shellcheck disable=SC2034
GATE_TS=run2; export STUB_SELFTEST_FAIL=1
run && bad "a cached sidecar was used although the decode self-test fails"
unset STUB_SELFTEST_FAIL

echo C >"$pcap"; export STUB_DECODE_FAIL=1
run && bad "a failed decode returned a sidecar"
[ -e "$side" ] && bad "a failed decode left a sidecar behind (decodes '$(from)')"
unset STUB_DECODE_FAIL

# a digest that cannot be computed (sha256sum fails, or prints no 64-hex digest) fails before any cache lookup or
# decode: nothing returned, nothing written
sha256sum() { return 1; }
n=$(calls); run && bad "a failing sha256sum returned a sidecar"
[ -s "$tmp/out" ] && bad "a failing sha256sum printed a sidecar path"
[ -e "$side" ] && bad "a failing sha256sum left a sidecar behind"
[ "$(calls)" = "$n" ] || bad "a failing sha256sum still decoded"
sha256sum() { echo "nothex  -"; }
run && bad "a malformed digest returned a sidecar"
[ -e "$side" ] && bad "a malformed digest left a sidecar behind"
unset -f sha256sum
run || bad "decode after the digest came back failed: $(cat "$tmp/err")"
sha256sum() { return 1; }
run && bad "a failing sha256sum reused the cached sidecar"
[ -s "$tmp/out" ] && bad "a failing sha256sum printed the cached sidecar's path"
unset -f sha256sum

[ "$fail" = 0 ] && echo "asn1-indep-lib self-test: ok"
exit "$fail"

#!/usr/bin/env bash
# selftest.sh: host unit test of kpimon-decode-harness.
# Builds two libe2smwrapper.so variants from the kpimon-go e2sm/ source:
#   SIZE8 = as shipped (TimeStamp ::= OCTET STRING (SIZE(8)))
#   SIZE4 = same but with the pristine upstream SIZE(4) TimeStamp.c
# encodes a KPM header (8-byte colletStartTime) + message with SIZE8, then
# checks: SIZE8 harness -> header RC_OK, msg RC_OK, ts_len 8;
#         SIZE4 harness -> header NOT cleanly decoded, msg RC_OK.
# Finding: the SIZE(4) decoder returns RC_OK for an 8-byte-timestamp header but
# consumes only 5 of 9 octets (ts_len 4, 4 trailing octets silently ignored,
# the timestamp is wrong). "Not cleanly decoded" therefore means
# code != RC_OK OR consumed < len, which is why summarize.py also reports
# RC_OK-with-trailing-bytes counts.
# Env: KP_E2SM (kpimon e2sm/ dir, SIZE(8) variant), TS_ORIG (pristine SIZE(4)
# TimeStamp.c). Defaults point at the session scratchpad copies.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
sp=/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/02de032a-7d76-4b6d-807e-d818d6b3facd/scratchpad
KP_E2SM=${KP_E2SM:-$sp/k9/kp-nist/e2sm}
TS_ORIG=${TS_ORIG:-$sp/ts-orig.c}
[ -d "$KP_E2SM/lib" ] || { echo "KP_E2SM not found: $KP_E2SM" >&2; exit 1; }
[ -f "$TS_ORIG" ] || { echo "TS_ORIG not found: $TS_ORIG" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Build a wrapper lib from a copy of e2sm/, same flags as kpimon's Dockerfile
# plus -O0 -std=gnu11 -w for modern GCC.
build_lib() { # <name> [TimeStamp.c override]
	local d="$tmp/$1"
	mkdir -p "$d"
	cp -r "$KP_E2SM"/. "$d/src"
	[ -n "${2:-}" ] && cp "$2" "$d/src/lib/TimeStamp.c"
	(cd "$d/src" && gcc -O0 -std=gnu11 -w -fPIC -D_GNU_SOURCE -Iheaders/ -c lib/*.c wrapper.c &&
		gcc ./*.o -shared -o "$d/libe2smwrapper.so")
	mkdir -p "$d/inc"
	cp "$d/src/wrapper.h" "$d/src/headers"/*.h "$d/inc/"
}
build_lib size8
build_lib size4 "$TS_ORIG"

gcc -O0 -std=gnu11 -w -D_GNU_SOURCE -I"$tmp/size8/inc" "$here/selftest-encoder.c" \
	-L"$tmp/size8" -l:libe2smwrapper.so -Wl,-rpath,"$tmp/size8" -lm -o "$tmp/encoder"
"$tmp/encoder" >"$tmp/lines.txt"
echo "input: $(cat "$tmp/lines.txt")"

"$here/build.sh" "$tmp/size8/libe2smwrapper.so" "$tmp/size8/inc" "$tmp/h8" >/dev/null
"$here/build.sh" "$tmp/size4/libe2smwrapper.so" "$tmp/size4/inc" "$tmp/h4" >/dev/null
r8=$("$tmp/h8" --xer 1 <"$tmp/lines.txt" 2>"$tmp/xer8.txt")
r4=$("$tmp/h4" <"$tmp/lines.txt" 2>/dev/null)
echo "SIZE8 .so: --timestamp-size=$("$tmp/h8" --timestamp-size)  result: $r8"
echo "SIZE4 .so: --timestamp-size=$("$tmp/h4" --timestamp-size)  result: $r4"

fail=0
check() { # <desc> <json> <python-expr over r>
	if python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if eval(sys.argv[2]) else 1)' "$2" "$3"; then
		echo "  ok   $1"
	else
		echo "  FAIL $1"
		fail=1
	fi
}
check "SIZE8 header RC_OK" "$r8" 'r["hdr_code"]=="RC_OK"'
check "SIZE8 message RC_OK" "$r8" 'r["msg_code"]=="RC_OK"'
check "SIZE8 ts_len 8" "$r8" 'r["ts_len"]==8'
check "SIZE8 msg_format 1" "$r8" 'r["msg_format"]==1'
check "SIZE4 header not cleanly decoded (code!=RC_OK or consumed<len)" "$r4" 'r["hdr_code"]!="RC_OK" or r["hdr_consumed"]<r["hdr_len"]'
check "SIZE4 message RC_OK" "$r4" 'r["msg_code"]=="RC_OK"'
if grep -q colletStartTime "$tmp/xer8.txt"; then echo "  ok   --xer printed header"; else echo "  FAIL --xer"; fail=1; fi
echo "$r8" | python3 -I "$here/summarize.py" >/dev/null && echo "  ok   summarize.py"

if [ "$fail" -eq 0 ]; then echo "PASS"; else echo "FAIL"; exit 1; fi

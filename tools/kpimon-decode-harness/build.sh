#!/usr/bin/env bash
# kpimon-decode-harness
# ---------------------
# Decodes E2SM-KPM RIC Indication header/message octets with kpimon-go's OWN
# decoder library (libe2smwrapper.so, built from kpimon's e2sm/ asn1c sources),
# calling asn_decode(ATS_ALIGNED_BASIC_PER) exactly as kpimon's wrapper.c does,
# and reports the asn1c return codes. It is the authority for "header RC_OK /
# message RC_OK" claims in the migration gates.
#
# Files:
#   kpimon-decode-harness.c  the harness (stdin lines "<id> <hdr_hex> <msg_hex>"
#                            -> JSONL; flags --xer N, --records, --timestamp-size,
#                            --ranfunc)
#   kpimon-decode-harness-records.c  --records: decoded header fields and record
#                            values (REAL as IEEE-754 bits, for bit-exact checks)
#   kpimon-decode-harness-ranfunc.c  --ranfunc: RAN function description decoded
#                            with kpimon's buildRanCellUeKpi and strictly
#   kpimon-decode-harness.h  shared declarations
#   build.sh                 this script
#   extract-from-image.sh    pull .so + headers out of a kpimon image (docker),
#                            record provenance, report TimeStamp SIZE (4 or 8)
#   pcap-to-lines.py         tshark pcap -> harness input lines (dedup by TSN)
#   summarize.py             harness JSONL -> JSON summary
#   selftest.sh              host test: SIZE(8) lib vs pristine SIZE(4) lib
#
# Usage:
#   build.sh <libe2smwrapper.so> <include-dir> <out-binary>
#     <include-dir> = dir holding wrapper.h and the asn1c headers
#                     (/usr/local/include/e2sm in the image).
#   LD_LIBRARY_PATH=<dir of .so> <out-binary> [--xer N] < lines > out.jsonl
#   LD_LIBRARY_PATH=<dir of .so> <out-binary> --records < lines   # + values
#   LD_LIBRARY_PATH=<dir of .so> <out-binary> --ranfunc < "<id> <hex>" lines
#   LD_LIBRARY_PATH=<dir of .so> <out-binary> --timestamp-size   # prints 4 or 8
#
# The binary records an rpath to the .so's directory, so LD_LIBRARY_PATH is only
# needed if the .so is moved. No network access.
set -euo pipefail

if [ "$#" -ne 3 ]; then
	sed -n '2,/^set -e/p' "$0" | sed -n '/^# Usage:/,/^# The binary/p' >&2
	exit 2
fi
so=$(readlink -f "$1")
inc=$(readlink -f "$2")
out=$3
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

[ -f "$so" ] || { echo "no such .so: $so" >&2; exit 1; }
[ -d "$inc" ] || { echo "no such include dir: $inc" >&2; exit 1; }

# -O0 -std=gnu11 -w: asn1c output is old C; modern GCC warns/mis-optimises.
gcc -O0 -std=gnu11 -w -D_GNU_SOURCE -I"$inc" -I"$here" "$here/kpimon-decode-harness.c" \
	"$here/kpimon-decode-harness-records.c" "$here/kpimon-decode-harness-ranfunc.c" \
	-L"$(dirname "$so")" -l:"$(basename "$so")" \
	-Wl,-rpath,"$(dirname "$so")" -lm -o "$out"
echo "built $out against $so"

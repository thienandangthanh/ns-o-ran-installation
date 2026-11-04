#!/usr/bin/env bash
# selftest-records.sh: host test of the --records UE ID judgement, against kpimon's own decoder library.
#
# Input: fixtures/format2-multi-item-ue-ids.lines, four real Format 2 RIC Indication messages from an M7 run
# (two en-gNB-UEID, two eNB-UEID, every one with several measCondUEidList items and several UE IDs per item).
# selftest-records-mutate.c changes one field of the LAST UE ID of the LAST condition item and re-encodes.
# Checks:
#   - the unchanged fixture decodes with ueIdsUniform true on every message, and every ueIdTags entry is a tag
#     (kpimon's formatter accepted every UE ID);
#   - each mutation produces exactly the expected number of messages (so the test is never vacuous), and every
#     mutated message decodes with ueIdsUniform false.
#
# Env (required; the layout extract-from-image.sh writes):
#   KP_SO   path to kpimon's libe2smwrapper.so (it must export e2sm_kpm_format2_ue_id_tag)
#   KP_INC  include dir holding wrapper.h and the asn1c headers (/usr/local/include/e2sm in the image)
# Without them the test prints SKIP and exits 77: it never passes without running.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$here/fixtures/format2-multi-item-ue-ids.lines
if [ -z "${KP_SO:-}" ] || [ -z "${KP_INC:-}" ] || [ ! -f "${KP_SO:-/nonexistent}" ] || [ ! -f "${KP_INC:-/nonexistent}/wrapper.h" ]; then
	echo "SKIP selftest-records: set KP_SO (libe2smwrapper.so) and KP_INC (its header dir); see extract-from-image.sh" >&2
	exit 77
fi
so_dir=$(cd "$(dirname "$KP_SO")" && pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$here/build.sh" "$KP_SO" "$KP_INC" "$tmp/harness" >/dev/null
gcc -O0 -std=gnu11 -w -D_GNU_SOURCE -I"$KP_INC" "$here/selftest-records-mutate.c" \
	-L"$so_dir" -l:"$(basename "$KP_SO")" -Wl,-rpath,"$so_dir" -lm -o "$tmp/mutate"

fail=0
judge() { # <desc> <records.jsonl> <expected count> <python predicate over one record x>
	if python3 -I - "$2" "$3" "$4" <<'EOF'; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
f2 = [x for x in recs if x.get("msg_format") == 2]
want, pred = int(sys.argv[2]), sys.argv[3]
bad = [x["id"] for x in f2 if not eval(pred, {}, {"x": x})]
if len(f2) != want or len(recs) != want or bad:
    print("    format2 %d of %d lines (want %d); failing: %s" % (len(f2), len(recs), want, bad[:4]))
    sys.exit(1)
EOF
}

"$tmp/harness" --records <"$fixture" >"$tmp/orig.jsonl"
judge "unchanged fixture: 4 Format 2 messages, every one ueIdsUniform with a tag per UE" "$tmp/orig.jsonl" 4 \
	'x["ueIdsUniform"] is True and x["condItems"] >= 2 and x["ueIdsPerItem"] >= 2 and len(x["ueIdTags"]) == x["ueIdsPerItem"] and all(t.startswith(("enGnbUeId:", "enbUeId:")) for t in x["ueIdTags"])'
for spec in x2ap:4 macro:2 optional:2 mme:2; do
	mode=${spec%%:*}
	"$tmp/mutate" "$mode" <"$fixture" >"$tmp/$mode.lines"
	"$tmp/harness" --records <"$tmp/$mode.lines" >"$tmp/$mode.jsonl"
	judge "$mode on the last item's last UE ID: ${spec#*:} messages, every one ueIdsUniform false" \
		"$tmp/$mode.jsonl" "${spec#*:}" 'x["ueIdsUniform"] is False'
done

if [ "$fail" -eq 0 ]; then echo "PASS"; else echo "FAIL"; exit 1; fi

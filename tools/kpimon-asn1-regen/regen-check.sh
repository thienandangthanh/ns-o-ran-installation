#!/usr/bin/env bash
# regen-check.sh <kpimon-src> <nist-kpimon-patch-dir> <out-dir>
#
# Proves the kpimon SIZE(8) TimeStamp patch is a regeneration, not a hand edit:
#   1. control: regenerating kpimon's stock e2sm2_0.asn + kpm2_0.asn reproduces
#      every shipped e2sm/lib + e2sm/headers file (ignoring "found in" lines);
#   2. footprint: on NIST's patched schema, SIZE(4) -> SIZE(8) changes exactly
#      one generated file, TimeStamp.c;
#   3. shipped: the fork's TimeStamp.c.timestamp-size8.patch applied to the
#      stock TimeStamp.c equals the regenerated SIZE(8) TimeStamp.c.
# Writes regen-check.json to <out-dir>; exit 0 only if all three hold.
#
# The generator is asn1c mouse07410@584d86e: its runtime skeletons are
# byte-identical to the 217 skeleton files shipped in kpimon 8bbbbbb9. It is
# built at -O0 because newer GCCs miscompile it at -O2 (the compiler segfaults).
# ASN1C may point at a prebuilt binary; otherwise it is built under <out-dir>.

set -euo pipefail
SRC=$(realpath "$1"); PATCHES=$(realpath "$2"); OUT=$(realpath -m "$3")
ASN1C_REPO=https://github.com/mouse07410/asn1c.git
ASN1C_SHA=584d86e22d54d401c5d349128f28b0c41fae4d24
FLAGS=(-pdu=auto -fincludes-quoted -fcompound-names -findirect-choice -fno-include-deps -no-gen-example -gen-APER)
mkdir -p "$OUT"; W="$OUT/work"; rm -rf "$W"; mkdir -p "$W"

if [ -z "${ASN1C:-}" ]; then
    git clone -q "$ASN1C_REPO" "$W/asn1c-src"
    git -C "$W/asn1c-src" checkout -q "$ASN1C_SHA"
    (cd "$W/asn1c-src" && autoreconf -i >"$W/asn1c-build.log" 2>&1 &&
        ./configure -q --prefix="$W/asn1c" CFLAGS="-O0 -g -w -std=gnu11" >>"$W/asn1c-build.log" 2>&1 &&
        make -j"$(nproc)" >>"$W/asn1c-build.log" 2>&1 && make install >>"$W/asn1c-build.log" 2>&1)
    ASN1C="$W/asn1c/bin/asn1c"
fi

gen() { # gen <asn-dir> <out>
    mkdir -p "$2"
    (cd "$2" && "$ASN1C" "${FLAGS[@]}" "$1/e2sm2_0.asn" "$1/kpm2_0.asn" >/dev/null 2>&1)
}
strip_found() { grep -v 'found in' "$1"; }

# Copies of the source tree: stock, and NIST-patched (as install_xapp_kpi_monitor.sh does).
cp -r "$SRC" "$W/stock"
cp -r "$SRC" "$W/nist"
(cd "$W/nist" && rm -f e2sm/headers/LogicalOR.h e2sm/headers/MatchingCondItem-Choice.h \
        e2sm/lib/LogicalOR.c e2sm/lib/MatchingCondItem-Choice.c &&
    for p in e2sm/asn1/kpm2_0.asn e2sm/headers/LogicalOR.h e2sm/headers/MatchingCondItem-Choice.h \
        e2sm/headers/MatchingCondItem.h e2sm/lib/LogicalOR.c e2sm/lib/MatchingCondItem-Choice.c \
        e2sm/lib/MatchingCondItem.c; do
        git apply --ignore-whitespace "$PATCHES/$p.patch"
    done)
cp -r "$W/nist" "$W/nist8"
(cd "$W/nist8" && git apply --ignore-whitespace "$PATCHES/e2sm/asn1/kpm2_0.asn.timestamp-size8.patch")
grep -q 'TimeStamp ::= OCTET STRING (SIZE(8))' "$W/nist8/e2sm/asn1/kpm2_0.asn"

gen "$W/stock/e2sm/asn1" "$W/gen-stock"
gen "$W/nist/e2sm/asn1" "$W/gen-nist4"
gen "$W/nist8/e2sm/asn1" "$W/gen-nist8"

# 1. control
same=0; differ=(); missing=()
for f in "$W/stock/e2sm/lib/"* "$W/stock/e2sm/headers/"*; do
    b=$(basename "$f"); g="$W/gen-stock/$b"
    if [ ! -f "$g" ]; then missing+=("$b"); continue; fi
    if diff -q <(strip_found "$f") <(strip_found "$g") >/dev/null; then same=$((same + 1)); else differ+=("$b"); fi
done
shipped_total=$(( $(ls "$W/stock/e2sm/lib" | wc -l) + $(ls "$W/stock/e2sm/headers" | wc -l) ))

# 2. footprint
changed=()
for g in "$W/gen-nist4/"*; do
    b=$(basename "$g")
    diff -q <(strip_found "$g") <(strip_found "$W/gen-nist8/$b") >/dev/null || changed+=("$b")
done

# 3. shipped patch == regeneration
cp -r "$W/stock" "$W/shipped8"
(cd "$W/shipped8" && git apply --ignore-whitespace "$PATCHES/e2sm/lib/TimeStamp.c.timestamp-size8.patch")
cp "$W/shipped8/e2sm/lib/TimeStamp.c" "$W/TimeStamp.shipped.c"
if diff -q <(strip_found "$W/TimeStamp.shipped.c") <(strip_found "$W/gen-nist8/TimeStamp.c") >/dev/null; then
    shipped_ok=true; else shipped_ok=false; fi
diff -u "$W/gen-nist4/TimeStamp.c" "$W/gen-nist8/TimeStamp.c" >"$OUT/TimeStamp-size4-vs-size8.diff" || true

python3 - "$OUT/regen-check.json" "$same" "$shipped_total" "$shipped_ok" "$ASN1C_SHA" \
    "${#differ[@]}" "${differ[*]:-}" "${#missing[@]}" "${missing[*]:-}" "${changed[*]:-}" <<'PY'
import json, sys
out, same, total, shipped_ok, sha, nd, d, nm, m, changed = sys.argv[1:]
changed = changed.split()
r = {
    "asn1c": f"mouse07410/asn1c@{sha}",
    "control": {"shipped_files": int(total), "identical": int(same),
                "differ": d.split(), "missing_from_regeneration": m.split()},
    "size8_footprint": changed,
    "shipped_patch_equals_regeneration": shipped_ok == "true",
}
r["pass"] = (int(same) == int(total) and changed == ["TimeStamp.c"] and r["shipped_patch_equals_regeneration"])
json.dump(r, open(out, "w"), indent=2)
print(json.dumps(r))
sys.exit(0 if r["pass"] else 1)
PY

#!/usr/bin/env bash
# ts-patches-selftest.sh: host-side check of ts_patches_check (ts-lib.sh) on temporary git repositories, no VM or k8s.
# A scratch Testbed repo holds an installer stand-in and a three-patch manifest over two TS files (one file patched
# twice, so manifest order matters); a scratch TS repo is the pin; `dk image inspect` is stubbed to print a label.
# The installed tree (pin + patches in manifest order + the installer's seed-route edit) with the patch-set label
# must pass; each fixture below must fail:
#   stale-image-label     the image carries the digest of another patch set
#   no-image              no trafficxapp image
#   unlisted-file-edit    a tracked file outside the patch set is edited
#   unlisted-file-staged  the same edit, staged
#   listed-file-extra     a patched file holds one more line than pin + its patches
#   listed-file-missing-patch  the last patch is not applied
#   testbed-manifest-edit the Testbed manifest differs from TESTBED_SHA's (uncommitted edit)
#   testbed-untracked     an untracked, non-ignored file in the Testbed patch directory
# Then ts_patch_ue_id_never_from_ns3_fields on the real Testbed patch set (O-RAN-Testbed-Automation): no line a listed
# patch adds names an `ns3.` measurement or field, and the one application patch that fills the RC UE ID (a call of
# ->mutable_engnbueid(); the generated protobuf code under ext/protobuf/ only defines it) sets
# it only from the struct parse_en_gnb_ue_id fills, and the string it parses is the one a function of the same patch
# looks up as the ueId tag of a UeMetrics row (its Flux filter r._measurement == "UeMetrics" and r.ueId ==); it must
# pass, and fail with a fixture patch that reads ns3.imsi for the UE identity or one that sets the ID from elsewhere.
# Exit 0 when the good tree passes and every fixture fails.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export EVIDENCE_DIR="$tmp/evidence"; mkdir -p "$EVIDENCE_DIR"
export HARNESS_DIR="$here/../.." RIC_DIR="$tmp/ric"
g() { git -c user.email=selftest@localhost -c user.name=selftest -c init.defaultBranch=main "$@"; }

# the TS pin: two files the patch set changes, the seed routes and one file it must leave alone
ts="$RIC_DIR/xApps/ts"
mkdir -p "$ts/src" "$ts/ext" "$ts/assets"
printf 'int main() {\n  return 0;\n}\n' >"$ts/src/a.cpp"
printf 'syntax = "proto3";\nmessage M {}\n' >"$ts/ext/b.proto"
printf 'mse|30003|-1|service-ricxapp-ad-rmr:4560\n' >"$ts/assets/bootstrap.rt"
printf 'untouched\n' >"$ts/other.txt"
g -C "$ts" init -q && g -C "$ts" add -A && g -C "$ts" commit -qm pin || exit 1
pin=$(git -C "$ts" rev-parse HEAD)

# the Testbed: installer stand-in, manifest and patches made from the pin
pd="$RIC_DIR/install_patch_files/xApps/ts"
mkdir -p "$RIC_DIR/additional_scripts" "$pd/src" "$pd/ext"
printf '#!/bin/bash\n' >"$RIC_DIR/additional_scripts/install_xapp_traffic_steering.sh"
printf '/xApps/\n' >"$RIC_DIR/.gitignore"
sed -i 's/^  return 0;/  int x = 1;\n  return 0;/' "$ts/src/a.cpp"; git -C "$ts" diff -- src/a.cpp >"$pd/src/a.cpp.one.patch"
g -C "$ts" commit -qam one
sed -i 's/^message M {}/message M { int32 v = 1; }/' "$ts/ext/b.proto"; git -C "$ts" diff -- ext/b.proto >"$pd/ext/b.proto.patch"
g -C "$ts" commit -qam two
sed -i 's/^  return 0;/  return x;/' "$ts/src/a.cpp"; git -C "$ts" diff -- src/a.cpp >"$pd/src/a.cpp.two.patch"
printf '# scratch patch set\nsrc/a.cpp.one.patch\next/b.proto.patch\n\nsrc/a.cpp.two.patch\n' >"$pd/patches.manifest"
git -C "$ts" reset -q --hard "$pin"
g -C "$RIC_DIR" init -q && g -C "$RIC_DIR" add -A && g -C "$RIC_DIR" commit -qm testbed || exit 1

# shellcheck source=bringup.sh
source "$here/bringup.sh"
# shellcheck source=ts-lib.sh
source "$here/ts-lib.sh"
# read by ts_patches_check (ts-lib.sh, bringup.sh)
# shellcheck disable=SC2034
TS_SHA="$pin" TESTBED_SHA=$(git -C "$RIC_DIR" rev-parse HEAD) TESTBED_URL=/nonexistent
log() { :; }
# the installer's digest rule, on the Testbed tree (at the pin here)
mapfile -t listed < <(grep -vE '^\s*(#|$)' "$pd/patches.manifest")
want=$( (cat "$pd/patches.manifest" && for p in "${listed[@]}"; do cat "$pd/$p"; done) | sha256sum | cut -d' ' -f1)
LABEL=""
dk() { [ "$1 $2" = "image inspect" ] && [ -n "$LABEL" ] && echo "$LABEL"; }

# installed <n>: the TS tree as the installer leaves it, with the first <n> listed patches applied
installed() {
    local p n=0
    g -C "$ts" checkout -q -f "$pin" -- . && g -C "$ts" reset -q && git -C "$ts" clean -qfdx || return 1
    git -C "$RIC_DIR" checkout -q HEAD -- install_patch_files && git -C "$RIC_DIR" clean -qfd -- install_patch_files
    for p in "${listed[@]}"; do
        [ "$n" -lt "$1" ] || break
        (cd "$ts" && git apply "$pd/$p") || return 1; n=$((n + 1))
    done
    sed -i 's/service-ricxapp-ad-rmr:4560/service-ricxapp-ad-rmr.ricxapp.svc.cluster.local:4560/' "$ts/assets/bootstrap.rt"
    LABEL="$want"
}

rc=0
# expect <pass|fail> <name>: run ts_patches_check on the tree as it stands
expect() {
    local got=0
    ts_patches_check >"$tmp/$2.out" 2>&1 || got=1
    if { [ "$1" = pass ] && [ "$got" = 0 ]; } || { [ "$1" = fail ] && [ "$got" = 1 ]; }; then
        echo "ok   $2: $1 ($(tail -n 1 "$tmp/$2.out"))"
    else
        echo "FAIL $2: expected $1"; cat "$tmp/$2.out"; rc=1
    fi
}
all=${#listed[@]}
installed "$all" && expect pass installed-tree-with-label
installed "$all" && LABEL=$(echo stale | sha256sum | cut -d' ' -f1) && expect fail stale-image-label
installed "$all" && LABEL="" && expect fail no-image
installed "$all" && echo edit >>"$ts/other.txt" && expect fail unlisted-file-edit
installed "$all" && echo edit >>"$ts/other.txt" && git -C "$ts" add other.txt && expect fail unlisted-file-staged
installed "$all" && echo '// extra' >>"$ts/src/a.cpp" && expect fail listed-file-extra
installed $((all - 1)) && expect fail listed-file-missing-patch
installed "$all" && echo '# edit' >>"$pd/patches.manifest" && expect fail testbed-manifest-edit
installed "$all" && echo x >"$pd/src/extra.patch" && expect fail testbed-untracked
installed "$all" && expect pass installed-tree-again

# ts_patch_ue_id_never_from_ns3_fields <patch dir> [<extra patch> <its manifest line>]: the static UE ID rule over the
# patches.manifest of <patch dir> (plus one extra listed patch, a fixture)
ts_patch_ue_id_never_from_ns3_fields() {
    python3 -I - "$@" <<'PY'
import os, re, sys
d, extra = sys.argv[1], sys.argv[2:]
man = os.path.join(d, "patches.manifest")
if not os.path.exists(man):
    sys.exit("no patch manifest %s" % man)
files = [l.strip() for l in open(man) if l.strip() and not l.lstrip().startswith("#")]
paths = [os.path.join(d, f) for f in files] + extra[:1]
problems, fillers = [], []
for p in paths:
    added = [l[1:] for l in open(p, errors="replace") if l.startswith("+") and not l.startswith("+++")]
    for l in added:
        if re.search(r"ns3\.", l):
            problems.append("%s adds a line naming an ns3. field: %s" % (os.path.basename(p), l.strip()[:120]))
    # the generated protobuf code (ext/protobuf/) defines the accessors; an application source that calls them fills
    if "/ext/protobuf/" not in p and any("->mutable_engnbueid()" in l for l in added):
        fillers.append((p, added))
if len(fillers) != 1:
    problems.append("%d patches fill the RC UE ID (mutable_engnbueid), want 1" % len(fillers))
for p, added in fillers:
    text = "\n".join(added)
    sets = re.findall(r"set_(menbuex2apid|globalenbplmn|globalenbmacroid)\(\s*([^)]*?)\s*\)", text)
    parsed = re.search(r"parse_en_gnb_ue_id\(\s*\w+\s*,\s*(\w+)\s*,", text)
    var = parsed.group(1) if parsed else None
    if sorted(k for k, _ in sets) != ["globalenbmacroid", "globalenbplmn", "menbuex2apid"]:
        problems.append("%s: setters %s, want each of the three once" % (os.path.basename(p), sets))
    bad = [(k, v) for k, v in sets if not var or not re.fullmatch(re.escape(var) + r"\.\w+", v)]
    if not parsed or bad:
        problems.append("%s: the UE ID is not set only from the struct parse_en_gnb_ue_id fills (%s)" % (os.path.basename(p), bad or "no parse"))
    # the parsed string is the ueId tag of a UeMetrics row: the same variable is passed to a function of this patch
    # whose Flux query filters UeMetrics by exactly that ueId tag
    src = re.search(r"parse_en_gnb_ue_id\(\s*(\w+)\s*,", text)
    confirmed = []
    for fn in set(re.findall(r"(\w+)\(\s*%s\s*[,)]" % re.escape(src.group(1)), text)) if src else ():
        if fn == "parse_en_gnb_ue_id":
            continue
        body = re.search(r"\b%s\s*\([^)]*\)\s*\{(.*?)\n\}" % re.escape(fn), text, re.S)
        if body and re.search(r'r\._measurement == \\"UeMetrics\\" and r\.ueId == ', body.group(1)):
            confirmed.append(fn)
    if not confirmed:
        problems.append("%s: the parsed UE ID is not confirmed as the ueId tag of a UeMetrics row (no function of the "
                        "patch takes it into a Flux filter on UeMetrics r.ueId)" % os.path.basename(p))
print("; ".join(problems) if problems else "%d listed patches: no ns3. field, the RC UE ID only from the parsed ueId tag" % len(paths))
sys.exit(1 if problems else 0)
PY
}
TB_TS="$HARNESS_DIR/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/install_patch_files/xApps/ts"
# expect_ue_id <pass|fail> <name> [extra patch]
expect_ue_id() {
    local got=0
    ts_patch_ue_id_never_from_ns3_fields "$TB_TS" "${@:3}" >"$tmp/$2.out" 2>&1 || got=1
    if { [ "$1" = pass ] && [ "$got" = 0 ]; } || { [ "$1" = fail ] && [ "$got" = 1 ]; }; then
        echo "ok   $2: $1 ($(tail -n 1 "$tmp/$2.out" | cut -c1-160))"
    else
        echo "FAIL $2: expected $1"; cat "$tmp/$2.out"; rc=1
    fi
}
expect_ue_id pass ts_patch_ue_id_never_from_ns3_fields
cat >"$tmp/imsi-from-ns3.patch" <<'PATCH'
--- a/src/ts_xapp/extra.cpp
+++ b/src/ts_xapp/extra.cpp
@@ -1,1 +1,2 @@
+  long imsi = row.get_long( "ns3.imsi" );
PATCH
expect_ue_id fail ts_patch_ue_id_fixture_reads_ns3_imsi "$tmp/imsi-from-ns3.patch"
# a second filler that sets the ID from a number of its own instead of the parsed tag
cat >"$tmp/id-from-elsewhere.patch" <<'PATCH'
--- a/src/ts_xapp/extra.cpp
+++ b/src/ts_xapp/extra.cpp
@@ -1,1 +1,4 @@
+  rc::enGNBUEID *e = h->mutable_ueid()->mutable_engnbueid();
+  e->set_menbuex2apid( imsi );
+  e->set_globalenbplmn( "00F110" ); e->set_globalenbmacroid( "00001" );
PATCH
expect_ue_id fail ts_patch_ue_id_fixture_sets_the_id_from_elsewhere "$tmp/id-from-elsewhere.patch"
# a copy of the real patch set whose UeMetrics lookup no longer filters by the ueId tag
cp -r "$TB_TS" "$tmp/ts-unconfirmed"
sed -i 's/ and r\.ueId == / and r.ueid_unchecked == /' "$tmp/ts-unconfirmed/src/ts_xapp/ts_xapp.cpp.style5_en_gnb_ueid.patch"
if ts_patch_ue_id_never_from_ns3_fields "$tmp/ts-unconfirmed" >"$tmp/unconfirmed.out" 2>&1; then
    echo "FAIL ts_patch_ue_id_fixture_parsed_id_not_a_ueid_tag: expected fail"; cat "$tmp/unconfirmed.out"; rc=1
else
    echo "ok   ts_patch_ue_id_fixture_parsed_id_not_a_ueid_tag: fail ($(cut -c1-160 "$tmp/unconfirmed.out"))"
fi
echo "ts-patches self-test: $([ "$rc" = 0 ] && echo ok || echo failed)"
exit "$rc"

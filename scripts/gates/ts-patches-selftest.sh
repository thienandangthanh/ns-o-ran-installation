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
echo "ts-patches self-test: $([ "$rc" = 0 ] && echo ok || echo failed)"
exit "$rc"

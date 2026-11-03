#!/usr/bin/env bash
# rc-at-pin-selftest.sh: host-side check of rc_at_pin (rc-lib.sh) on temporary git repositories, no VM or k8s.
# A scratch Testbed repo holds an installer stand-in, commit_hashes.json pinning rc and a two-patch manifest over one rc
# file (manifest order matters); a scratch rc repo is the pin. pod_info, kc, dk and rc_ready are stubbed: the pod runs
# IMAGE_ID, docker holds DOCKER_ID with labels SRC_LABEL and SET_LABEL.
# The installed tree (pin + patches in order) with a pod on the labelled image must pass; each fixture must fail:
#   stale-patchset-label  the image carries the digest of another patch set (a warm install that skipped the build)
#   wrong-source-label    the image names another rc commit
#   pod-runs-other-image  the pod's imageID is not the docker image's ID (the new image was never imported or rolled)
#   no-pod                no rc pod
#   unlisted-file-edit    a tracked rc file outside the patch set is edited
#   listed-file-missing-patch  the last patch is not applied
#   head-not-pin          rc's clone is at another commit
#   pin-disagrees         commit_hashes.json at TESTBED_SHA pins another rc commit than the harness
#   testbed-manifest-edit the Testbed manifest differs from TESTBED_SHA's
# Exit 0 when the good tree passes and every fixture fails.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export EVIDENCE_DIR="$tmp/evidence"; mkdir -p "$EVIDENCE_DIR"
export HARNESS_DIR="$here/../.." RIC_DIR="$tmp/ric"
g() { git -c user.email=selftest@localhost -c user.name=selftest -c init.defaultBranch=main "$@"; }

# the rc pin: one file the patch set changes twice and one it must leave alone
rcd="$RIC_DIR/xApps/rc"
mkdir -p "$rcd/control"
printf 'package control\n\nfunc Target() int {\n\treturn 0\n}\n' >"$rcd/control/rcControl.go"
printf 'untouched\n' >"$rcd/README.md"
g -C "$rcd" init -q && g -C "$rcd" add -A && g -C "$rcd" commit -qm pin || exit 1
pin=$(git -C "$rcd" rev-parse HEAD)
g -C "$rcd" commit -q --allow-empty -m later && other=$(git -C "$rcd" rev-parse HEAD) && git -C "$rcd" reset -q --hard "$pin"

# the Testbed: installer stand-in, commit_hashes.json, manifest and patches made from the pin
pd="$RIC_DIR/install_patch_files/xApps/rc"
mkdir -p "$RIC_DIR/additional_scripts" "$pd"
printf '#!/bin/bash\n' >"$RIC_DIR/additional_scripts/install_xapp_ric_control.sh"
printf '{"https://gerrit.o-ran-sc.org/r/ric-app/rc.git": ["k-release", "%s"]}\n' "$pin" >"$RIC_DIR/commit_hashes.json"
printf '/xApps/\n' >"$RIC_DIR/.gitignore"
sed -i 's/^\treturn 0$/\tx := 1\n\treturn 0/' "$rcd/control/rcControl.go"; git -C "$rcd" diff >"$pd/0001-one.patch"
g -C "$rcd" commit -qam one
sed -i 's/^\treturn 0$/\treturn x/' "$rcd/control/rcControl.go"; git -C "$rcd" diff >"$pd/0002-two.patch"
printf '# scratch rc patch set\n0001-one.patch\n\n0002-two.patch\n' >"$pd/patches.manifest"
git -C "$rcd" reset -q --hard "$pin"
g -C "$RIC_DIR" init -q && g -C "$RIC_DIR" add -A && g -C "$RIC_DIR" commit -qm testbed || exit 1

# shellcheck source=bringup.sh
source "$here/bringup.sh"
# shellcheck source=rc-lib.sh
source "$here/rc-lib.sh"
# read by rc_at_pin (rc-lib.sh, bringup.sh)
# shellcheck disable=SC2034
RC_SHA="$pin" TESTBED_SHA=$(git -C "$RIC_DIR" rev-parse HEAD) TESTBED_URL=/nonexistent
log() { :; }
mapfile -t listed < <(grep -vE '^\s*(#|$)' "$pd/patches.manifest")
want=$( (cat "$pd/patches.manifest" && for p in "${listed[@]}"; do cat "$pd/$p"; done) | sha256sum | cut -d' ' -f1)
POD="" IMAGE_ID="" DOCKER_ID="" SRC_LABEL="" SET_LABEL=""
pod_info() { [ -n "$POD" ] && echo "$POD true 0"; }
kc() { [ -n "$POD" ] && echo "$RC_IMAGE $IMAGE_ID"; }
dk() {
    [ "$1 $2" = "image inspect" ] || return 1
    case "$4" in
        '{{.Id}}') echo "$DOCKER_ID" ;;
        *rc.source.sha*) echo "$SRC_LABEL" ;;
        *patchset.sha256*) echo "$SET_LABEL" ;;
    esac
}
rc_ready() { echo "rc ready (stub)"; }

# installed <n>: rc's tree as the installer leaves it with the first <n> listed patches, the pod on the labelled image
installed() {
    local p n=0
    g -C "$rcd" checkout -q -f "$pin" && g -C "$rcd" reset -q --hard "$pin" && git -C "$rcd" clean -qfdx || return 1
    git -C "$RIC_DIR" checkout -q HEAD -- . && git -C "$RIC_DIR" clean -qfd -- install_patch_files
    for p in "${listed[@]}"; do
        [ "$n" -lt "$1" ] || break
        (cd "$rcd" && git apply "$pd/$p") || return 1; n=$((n + 1))
    done
    POD=xapp-rc-0 DOCKER_ID=sha256:aaaa IMAGE_ID=sha256:aaaa SRC_LABEL="$pin" SET_LABEL="$want"
}

rc=0
# expect <pass|fail> <name>: run rc_at_pin on the state as it stands
expect() {
    local got=0
    rc_at_pin >"$tmp/$2.out" 2>&1 || got=1
    if { [ "$1" = pass ] && [ "$got" = 0 ]; } || { [ "$1" = fail ] && [ "$got" = 1 ]; }; then
        echo "ok   $2: $1 ($(grep -vE '^(expected|pod |docker )' "$tmp/$2.out" | tail -n 1))"
    else
        echo "FAIL $2: expected $1"; cat "$tmp/$2.out"; rc=1
    fi
}
all=${#listed[@]}
installed "$all" && expect pass installed-tree-on-labelled-image
installed "$all" && SET_LABEL=$(echo stale | sha256sum | cut -d' ' -f1) && expect fail stale-patchset-label
installed "$all" && SRC_LABEL="$other" && expect fail wrong-source-label
installed "$all" && IMAGE_ID=sha256:bbbb && expect fail pod-runs-other-image
installed "$all" && POD="" && expect fail no-pod
installed "$all" && echo edit >>"$rcd/README.md" && expect fail unlisted-file-edit
installed $((all - 1)) && expect fail listed-file-missing-patch
installed "$all" && git -C "$rcd" checkout -q --detach "$other" -- 2>/dev/null; git -C "$rcd" checkout -q "$other" 2>/dev/null &&
    expect fail head-not-pin
installed "$all" && sed -i "s/$pin/$other/" "$RIC_DIR/commit_hashes.json" && g -C "$RIC_DIR" commit -qam repin &&
    TESTBED_SHA=$(git -C "$RIC_DIR" rev-parse HEAD) && expect fail pin-disagrees
TESTBED_SHA=$(git -C "$RIC_DIR" rev-parse HEAD~1) && git -C "$RIC_DIR" reset -q --hard "$TESTBED_SHA"
installed "$all" && echo '# edit' >>"$pd/patches.manifest" && expect fail testbed-manifest-edit
installed "$all" && expect pass installed-tree-again
echo "rc-at-pin self-test: $([ "$rc" = 0 ] && echo ok || echo failed)"
exit "$rc"

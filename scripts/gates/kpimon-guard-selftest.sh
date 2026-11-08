#!/usr/bin/env bash
# kpimon-guard-selftest.sh: host-side check of the kpimon install guard (kpimon.sh: testbed_paths_at_pin on
# KPIMON_TESTBED_PATHS, then kpimon_image_labelled) on a temporary Testbed repo, no VM or k8s. The scratch Testbed holds
# an installer stand-in, a kpimon patch set (manifest, two patches, the eNB measurement config, an unlisted backup
# file) and the agent's metric map, clause registry, lint, registry module and X2AP codec; `dk image inspect` is stubbed to print
# LABELS.
# The pinned tree with an image labelled (digest, size8) must pass; each fixture must fail:
#   stale-patchset-label   the image carries the digest of another patch set (a warm install that skipped the build)
#   wrong-size8-label      the image was built with the other KPIMON_TIMESTAMP_SIZE8
#   no-image               no kpimon image
#   unlisted-file-edit     a tracked file of the patch dir that the manifest does not list is edited
#   listed-config-edit     the eNB measurement config is edited (uncommitted)
#   untracked-patch-file   an untracked, non-ignored file in the patch dir
#   metric-map-edit        the agent's metric map differs from TESTBED_SHA's
#   clause-registry-edit   the lint's clause registry differs from TESTBED_SHA's
#   registry-module-edit   the lint's registry module differs from TESTBED_SHA's
#   x2ap-codec-edit        a source of the X2AP codec kpimon builds differs from TESTBED_SHA's
#   x2ap-codec-untracked   an untracked file in the X2AP codec directory
# Exit 0 when the pinned tree passes and every fixture fails.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export EVIDENCE_DIR="$tmp/evidence"; mkdir -p "$EVIDENCE_DIR"
export HARNESS_DIR="$here/../.." RIC_DIR="$tmp/ric" NIST_DIR="$tmp/nist"
g() { git -c user.email=selftest@localhost -c user.name=selftest -c init.defaultBranch=main "$@"; }

pd="$RIC_DIR/install_patch_files/xApps/kpimon-go"
mkdir -p "$RIC_DIR/additional_scripts" "$pd/control" "$pd/e2sm" "$RIC_DIR/ns3_e2_agent/schema" "$RIC_DIR/ns3_e2_agent/tests" \
    "$RIC_DIR/ns3_e2_agent/x2ap_codec"
printf '#!/bin/bash\n' >"$RIC_DIR/additional_scripts/install_xapp_kpi_monitor.sh"
printf 'diff --git a/e2sm/wrapper.c b/e2sm/wrapper.c\n' >"$pd/e2sm/wrapper.c.patch"
printf 'diff --git a/control/control.go b/control/control.go\n' >"$pd/control/control.go.patch"
printf '{"doc": [], "cell": [], "ue": [{"measName": "ns3.nodeId", "measId": 1001}]}\n' >"$pd/control/enb-kpm-measurements.json"
printf 'package control\n' >"$pd/control/control.go.previous"
printf '# scratch kpimon patch set\ne2sm/wrapper.c.patch\ncontrol/control.go.patch\n\ncontrol/enb-kpm-measurements.json\n' \
    >"$pd/patches.manifest"
printf '{"rows": []}\n' >"$RIC_DIR/ns3_e2_agent/schema/metric-map.v1.json"
printf '{"entries": []}\n' >"$RIC_DIR/ns3_e2_agent/schema/kpm-measurement-clauses.v1.json"
printf '#!/usr/bin/env python3\n' >"$RIC_DIR/ns3_e2_agent/tests/lint-metric-map.py"
printf '"""registry module stand-in"""\n' >"$RIC_DIR/ns3_e2_agent/tests/kpm-clause-registry.py"
printf '/* codec stand-in */\n' >"$RIC_DIR/ns3_e2_agent/x2ap_codec/x2ap-codec-cells.c"
printf '/xApps/\n' >"$RIC_DIR/.gitignore"
g -C "$RIC_DIR" init -q && g -C "$RIC_DIR" add -A && g -C "$RIC_DIR" commit -qm testbed || exit 1

# shellcheck source=bringup.sh
source "$here/bringup.sh"
# shellcheck source=kpimon.sh
source "$here/kpimon.sh"
# read by testbed_paths_at_pin and patchset_digest_at_pin (bringup.sh)
# shellcheck disable=SC2034
TESTBED_SHA=$(git -C "$RIC_DIR" rev-parse HEAD) TESTBED_URL=/nonexistent
log() { :; }
mapfile -t listed < <(grep -vE '^\s*(#|$)' "$pd/patches.manifest")
want=$( (cat "$pd/patches.manifest" && for p in "${listed[@]}"; do cat "$pd/$p"; done) | sha256sum | cut -d' ' -f1)
LABELS=""
dk() { [ "$1 $2" = "image inspect" ] && [ -n "$LABELS" ] && echo "$LABELS"; }

# guard <size8>: the checks kpimon_install makes before and after NIST's installer
guard() { testbed_paths_at_pin "${KPIMON_TESTBED_PATHS[@]}" && kpimon_image_labelled "$1"; }

# pinned: the Testbed tree at TESTBED_SHA and an image labelled with its patch set, built with size8=true
pinned() {
    git -C "$RIC_DIR" checkout -q HEAD -- . && git -C "$RIC_DIR" clean -qfd -- install_patch_files ns3_e2_agent
    LABELS="$want true"
}

rc=0
# expect <pass|fail> <name>: run the guard (size8=true) on the state as it stands
expect() {
    local got=0
    guard true >"$tmp/$2.out" 2>&1 || got=1
    if { [ "$1" = pass ] && [ "$got" = 0 ]; } || { [ "$1" = fail ] && [ "$got" = 1 ]; }; then
        echo "ok   $2: $1 ($(tail -n 1 "$tmp/$2.out"))"
    else
        echo "FAIL $2: expected $1"; cat "$tmp/$2.out"; rc=1
    fi
}
pinned && expect pass pinned-tree-labelled-image
pinned && LABELS="$(echo stale | sha256sum | cut -d' ' -f1) true" && expect fail stale-patchset-label
pinned && LABELS="$want false" && expect fail wrong-size8-label
pinned && LABELS="" && expect fail no-image
pinned && echo '// edit' >>"$pd/control/control.go.previous" && expect fail unlisted-file-edit
pinned && sed -i 's/1001/1002/' "$pd/control/enb-kpm-measurements.json" && expect fail listed-config-edit
pinned && echo x >"$pd/control/extra.patch" && expect fail untracked-patch-file
pinned && echo ' ' >>"$RIC_DIR/ns3_e2_agent/schema/metric-map.v1.json" && expect fail metric-map-edit
pinned && echo ' ' >>"$RIC_DIR/ns3_e2_agent/schema/kpm-measurement-clauses.v1.json" && expect fail clause-registry-edit
pinned && echo '# edit' >>"$RIC_DIR/ns3_e2_agent/tests/kpm-clause-registry.py" && expect fail registry-module-edit
pinned && echo '/* edit */' >>"$RIC_DIR/ns3_e2_agent/x2ap_codec/x2ap-codec-cells.c" && expect fail x2ap-codec-edit
pinned && echo x >"$RIC_DIR/ns3_e2_agent/x2ap_codec/extra.c" && expect fail x2ap-codec-untracked
pinned && expect pass pinned-tree-again
echo "kpimon-guard self-test: $([ "$rc" = 0 ] && echo ok || echo failed)"
exit "$rc"

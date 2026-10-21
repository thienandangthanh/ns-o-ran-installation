#!/usr/bin/env bash
# build-ns3.sh <workdir> [--ns3-sha SHA] [--oi-sha SHA]
#
# Clean, scripted build of ns-O-RAN scenario-zero without asn1c or e2sim:
#   1. installs missing apt build dependencies (non-interactive, nothing else
#      system-wide; no e2sim, no /usr/local headers, no manual ar);
#   2. clones NS3_URL@NS3_SHA into <workdir>/ns-3 and
#      ORAN_INTERFACE_URL@ORAN_INTERFACE_SHA into <workdir>/ns-3/contrib/oran-interface
#      (pins from scripts/pins.conf; --ns3-sha / --oi-sha override them for dev builds);
#   3. configures with the fixed flags below, records them in
#      <workdir>/ns3-configure-flags.txt, and builds the needed modules and scenario-zero.
# Logs go to stderr. The last stdout line is the absolute path of the scenario-zero binary.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=pins.conf
source "$HERE/pins.conf"

usage() { echo "usage: $0 <workdir> [--ns3-sha SHA] [--oi-sha SHA]" >&2; exit 2; }
[ $# -ge 1 ] || usage
WORKDIR="$1"; shift
while [ $# -gt 0 ]; do
    case "$1" in
        --ns3-sha) NS3_SHA="${2:?}"; shift 2 ;;
        --oi-sha) ORAN_INTERFACE_SHA="${2:?}"; shift 2 ;;
        *) usage ;;
    esac
done

# Fixed configure flags (recorded verbatim). "default" profile = -O2 -g with
# NS3_ASSERT and NS3_LOG on, as a plain `./ns3 configure` gives; only the
# modules scenario-zero needs (mmwave pulls lte, internet, ... as dependencies).
# shellcheck disable=SC2054  # the comma in --enable-modules is part of the value
CONFIGURE_FLAGS=(--build-profile=default --disable-examples --disable-tests --disable-python
                 --enable-modules=mmwave,oran-interface -G "Unix Makefiles"
                 -- -DNS3_CCACHE=OFF -DNS3_FAST_LINKERS=OFF)
APT_DEPS=(build-essential g++ cmake make python3 git ca-certificates)
JOBS="$(nproc)"

log() { echo "[build-ns3 $(date +%H:%M:%S)] $*" >&2; }

install_deps() {
    local missing=() p
    for p in "${APT_DEPS[@]}"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
    done
    [ ${#missing[@]} -eq 0 ] && { log "apt dependencies present"; return 0; }
    log "installing apt dependencies: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    sudo -n apt-get install -y -q "${missing[@]}" >&2 ||
        { sudo -n apt-get update -q >&2 && sudo -n apt-get install -y -q "${missing[@]}" >&2; }
}

# clone_at <url> <sha> <dir>: fresh shallow clone of exactly that commit.
clone_at() {
    local url="$1" sha="$2" dir="$3"
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$url"
    GIT_TERMINAL_PROMPT=0 git -C "$dir" fetch -q --depth 1 origin "$sha"
    git -C "$dir" checkout -q --detach FETCH_HEAD
    local head; head="$(git -C "$dir" rev-parse HEAD)"
    [ "$head" = "$sha" ] || { log "clone of $url is at $head, wanted $sha"; return 1; }
    log "cloned $url at $sha"
}

install_deps
mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
SRC="$WORKDIR/ns-3"

clone_at "$NS3_URL" "$NS3_SHA" "$SRC"
clone_at "$ORAN_INTERFACE_URL" "$ORAN_INTERFACE_SHA" "$SRC/contrib/oran-interface"

{
    echo "# ns-3 configure flags used by scripts/build-ns3.sh"
    printf './ns3 configure'; printf ' %q' "${CONFIGURE_FLAGS[@]}"; echo
    echo "ns3: $NS3_URL $NS3_SHA"
    echo "oran-interface: $ORAN_INTERFACE_URL $ORAN_INTERFACE_SHA"
    echo "build: ./ns3 build -j$JOBS scenario-zero"
    echo "compiler: $(g++ --version | head -n 1)"
    echo "cmake: $(cmake --version | head -n 1)"
    echo "host: $(. /etc/os-release && echo "$PRETTY_NAME") $(uname -m)"
} >"$WORKDIR/ns3-configure-flags.txt"

cd "$SRC"
log "configure: ./ns3 configure ${CONFIGURE_FLAGS[*]}"
./ns3 configure "${CONFIGURE_FLAGS[@]}" >&2
log "build: scenario-zero with $JOBS jobs"
./ns3 build -j"$JOBS" scenario-zero >&2

BIN="$(find "$SRC/build/scratch" -maxdepth 1 -type f -perm -u+x -name '*-scenario-zero-*' | head -n 1)"
[ -n "$BIN" ] || { log "scenario-zero binary not found under $SRC/build/scratch"; exit 1; }
log "done"
echo "$BIN"

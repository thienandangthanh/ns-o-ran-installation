#!/usr/bin/env bash
# build.sh [image-tag]: build the rc-decode image (docker or podman; the host's
# docker is a podman shim). The gates build it VM-side too, so a fresh VM
# (M9) gets the same decoder from the same pins.
set -euo pipefail
tag="${1:-localhost/rc-decode:local}"
cd "$(dirname "$0")"
eng=docker; command -v docker >/dev/null || eng=podman
if ! $eng info >/dev/null 2>&1; then eng="sudo -n docker"; fi
$eng build -q -t "$tag" . >/dev/null
echo "$tag"

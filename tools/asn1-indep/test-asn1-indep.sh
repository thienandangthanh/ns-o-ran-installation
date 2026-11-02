#!/usr/bin/env bash
# test-asn1-indep.sh [image]: run selftest.py inside the image, offline
# (--network=none), with the committed asn1c captures of tools/rc-decode/fixtures
# and tools/rmr-peer/fixtures mounted read-only for the cross-checks. Without an
# image argument it builds one with build.sh first. Exits with the selftest's code.
set -euo pipefail
cd "$(dirname "$0")"
image="${1:-$(./build.sh)}"
podman run --rm --network=none \
    -v "$PWD/../rc-decode/fixtures:/fixtures/rc-decode:ro" \
    -v "$PWD/../rmr-peer/fixtures:/fixtures/rmr-peer:ro" \
    "$image" python3 /opt/asn1-indep/selftest.py /fixtures
echo "test-asn1-indep: ok ($image)"

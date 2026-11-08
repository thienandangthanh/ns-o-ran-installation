#!/usr/bin/env bash
# image-tag.sh: print the asn1-indep image tag of this source tree on stdout: the first 16 hex digits of a sha256 over
# the build inputs (Dockerfile, requirements.txt, compile-asn.py, the selftest files, asn/ and e2indep/*.py, by path
# and content), so equal sources give equal tags. build.sh tags the image with it; the gates derive the image
# reference localhost/asn1-indep:<tag> from it. This script and build.sh are not inputs, so editing them keeps the tag.
set -euo pipefail
cd "$(dirname "$0")"
inputs=(Dockerfile requirements.txt compile-asn.py selftest.py selftest_kpm_and_fixtures.py)
mapfile -t -O "${#inputs[@]}" inputs < <(find asn e2indep -type f \( -name '*.asn' -o -name '*.txt' -o -name '*.py' \) \
    -not -path '*/__pycache__/*' | LC_ALL=C sort)
for f in "${inputs[@]}"; do printf '%s  %s\n' "$(sha256sum <"$f" | cut -d' ' -f1)" "$f"; done | sha256sum | cut -c1-16

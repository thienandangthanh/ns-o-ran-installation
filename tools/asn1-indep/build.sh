#!/usr/bin/env bash
# build.sh: build the asn1-indep image with podman, save it as a tarball and
# print the image reference on stdout (everything else goes to stderr).
#   tag      = image-tag.sh: first 16 hex digits of a sha256 over the build inputs
#              (Dockerfile, requirements.txt, compile-asn.py, the selftest files,
#              asn/ and e2indep/*.py, by path and content), so equal sources give
#              equal tags
#   image    = localhost/asn1-indep:<tag>
#   tarball  = dist/asn1-indep-<tag>.tar (podman save); tarballs of other tags
#              are removed, dist/SHA256SUMS lists the one left. dist/ is git-ignored.
set -euo pipefail
cd "$(dirname "$0")"
command -v podman >/dev/null || { echo "build.sh: podman not found" >&2; exit 1; }

tag=$(./image-tag.sh)
image="localhost/asn1-indep:$tag"

podman build -q -t "$image" . >/dev/null
out=dist
mkdir -p "$out"
tar="$out/asn1-indep-$tag.tar"
rm -f "$out"/asn1-indep-*.tar
podman save -q -o "$tar" "$image"
(cd "$out" && sha256sum "asn1-indep-$tag.tar" >SHA256SUMS)
size=$(stat -c %s "$tar")
sum=$(sha256sum "$tar" | cut -d' ' -f1)
echo "build.sh: image $image ($(podman image inspect -f '{{.Id}}' "$image" | cut -c1-12))" >&2
echo "build.sh: tarball $tar $size bytes sha256 $sum" >&2
echo "$image"

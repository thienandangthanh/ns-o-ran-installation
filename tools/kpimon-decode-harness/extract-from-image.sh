#!/usr/bin/env bash
# extract-from-image.sh <image> <out-dir>
# Copies /usr/local/lib/libe2smwrapper.so and /usr/local/include/e2sm out of a
# kpimon image (docker create + docker cp; no container is started), writes
# <out-dir>/provenance.txt (image ID, .so sha256, TimeStamp SIZE) and prints the
# TimeStamp constraint (4 or 8) read from the .so itself via the harness'
# --timestamp-size mode. Needs docker and gcc on this machine.
set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <image> <out-dir>" >&2
	exit 2
fi
image=$1
out=$2
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)

cid=$(docker create "$image" true)
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
docker cp "$cid:/usr/local/lib/libe2smwrapper.so" "$out/libe2smwrapper.so"
rm -rf "$out/e2sm"
docker cp "$cid:/usr/local/include/e2sm" "$out/e2sm"
image_id=$(docker image inspect --format '{{.Id}}' "$image")
sha=$(sha256sum "$out/libe2smwrapper.so" | cut -d' ' -f1)

"$here/build.sh" "$out/libe2smwrapper.so" "$out/e2sm" "$out/kpimon-decode-harness" >/dev/null
ts=$("$out/kpimon-decode-harness" --timestamp-size)

{
	echo "image: $image"
	echo "image_id: $image_id"
	echo "libe2smwrapper.so_sha256: $sha"
	echo "timestamp_size: $ts"
	echo "extracted_at: $(date -Iseconds)"
} >"$out/provenance.txt"
cat "$out/provenance.txt"
echo "TimeStamp SIZE in this .so: $ts"

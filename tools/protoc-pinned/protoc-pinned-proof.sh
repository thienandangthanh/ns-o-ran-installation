#!/usr/bin/env bash
# protoc-pinned-proof.sh: regenerate the RC xApp's gRPC protobuf code with pinned toolchains.
#
#   protoc-pinned-proof.sh prove    --rc-tree DIR --ts-tree DIR --out DIR
#       Regenerates the UNCHANGED committed rc.proto of both trees and compares every generated file byte for byte
#       with the committed one:
#         rc (Go):          protocol/grpc/ricmsgcommrpc/proto/rc.proto -> protocol/grpc/ricmsgcommrpc/rc/rc.pb.go
#         TS xApp (C++):    ext/protobuf/rc.proto -> ext/protobuf/rc.pb.{cc,h}, rc.grpc.pb.{cc,h}
#       Writes DIR/proof.json ({equal, files: [{side, file, committedSha256, regeneratedSha256, equal}], tools})
#       and exits 0 only if every file is equal. A changed proto is generated only after this passes.
#   protoc-pinned-proof.sh generate --go-proto FILE --cpp-proto FILE --out DIR
#       Generates DIR/go/rc.pb.go from --go-proto and DIR/cpp/rc.{pb,grpc.pb}.{cc,h} from --cpp-proto with the same
#       images, and writes DIR/generate.json with the tool versions and the sha256 of each output.
#
# Images (built locally from this directory; distro packages only, no downloaded binaries):
#   protoc-pinned-go:3.6.1-gen-go-20161116    Dockerfile.go-protoc-3.6.1-gen-go-20161116   (Ubuntu 20.04 protoc 3.6.1 + Debian 9 golang/protobuf 2016-11-16 source, Go 1.10)
#   protoc-pinned-cpp:3.6.1   Dockerfile.cpp-protoc-3.6.1  (Ubuntu 20.04 protobuf-compiler + protobuf-compiler-grpc)
# Env: CONTAINER (default podman; docker works the same way).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
engine=${CONTAINER:-podman}
mode=${1:-}; shift || true
rc_tree=""; ts_tree=""; out=""; go_proto=""; cpp_proto=""
while [ $# -gt 0 ]; do
	case "$1" in
		--rc-tree) rc_tree=$2; shift 2 ;;
		--ts-tree) ts_tree=$2; shift 2 ;;
		--go-proto) go_proto=$2; shift 2 ;;
		--cpp-proto) cpp_proto=$2; shift 2 ;;
		--out) out=$2; shift 2 ;;
		*) echo "unknown argument $1" >&2; exit 2 ;;
	esac
done
usage() { sed -n '2,20p' "$0" >&2; exit 2; }
[ -n "$out" ] || usage
case "$mode" in
	prove) [ -d "$rc_tree" ] && [ -d "$ts_tree" ] || usage
		go_proto=$rc_tree/protocol/grpc/ricmsgcommrpc/proto/rc.proto
		cpp_proto=$ts_tree/ext/protobuf/rc.proto ;;
	generate) [ -f "$go_proto" ] && [ -f "$cpp_proto" ] || usage ;;
	*) usage ;;
esac
mkdir -p "$out"
out=$(cd "$out" && pwd)
rm -rf "$out/go" "$out/cpp" "$out/in-go" "$out/in-cpp"
mkdir -p "$out/go" "$out/cpp" "$out/in-go" "$out/in-cpp"
# The generators see each proto as "rc.proto", the name the committed files were generated from.
cp "$go_proto" "$out/in-go/rc.proto"
cp "$cpp_proto" "$out/in-cpp/rc.proto"

GO_IMG=localhost/protoc-pinned-go:3.6.1-gen-go-20161116
CPP_IMG=localhost/protoc-pinned-cpp:3.6.1
"$engine" build -q -t "$GO_IMG" -f "$here/Dockerfile.go-protoc-3.6.1-gen-go-20161116" "$here" >/dev/null
"$engine" build -q -t "$CPP_IMG" -f "$here/Dockerfile.cpp-protoc-3.6.1" "$here" >/dev/null

run() { # <image> <in dir> <out dir> <sh -c command>
	"$engine" run --rm --network=none -v "$2:/in:ro" -v "$3:/out" -w /in "$1" sh -c "$4"
}
run "$GO_IMG" "$out/in-go" "$out/go" 'protoc --go_out=plugins=grpc:/out rc.proto'
run "$CPP_IMG" "$out/in-cpp" "$out/cpp" \
	'protoc --cpp_out=/out --grpc_out=/out --plugin=protoc-gen-grpc="$(command -v grpc_cpp_plugin)" rc.proto'

tools_json() { # <image> -> {"image": id, "protoc": version, "packages": {name: version}}
	local id ver pkgs
	id=$("$engine" image inspect --format '{{.Id}}' "$1")
	ver=$("$engine" run --rm --network=none "$1" protoc --version)
	pkgs=$("$engine" run --rm --network=none "$1" dpkg-query -W -f '${Package}=${Version}\n' \
		protobuf-compiler 'golang-goprotobuf-dev' protobuf-compiler-grpc libprotoc-dev 2>/dev/null || true)
	python3 -I -c 'import json,sys; print(json.dumps({"image": sys.argv[1], "protoc": sys.argv[2],
	  "packages": dict(l.split("=", 1) for l in sys.argv[3].splitlines() if "=" in l and l.split("=", 1)[1])}))' \
		"$id" "$ver" "$pkgs"
}
tools=$(printf '{"go": %s, "cpp": %s}' "$(tools_json "$GO_IMG")" "$(tools_json "$CPP_IMG")")

if [ "$mode" = generate ]; then
	python3 -I - "$out" "$tools" <<'EOF'
import hashlib, json, pathlib, sys
out, tools = pathlib.Path(sys.argv[1]), json.loads(sys.argv[2])
files = {str(p.relative_to(out)): hashlib.sha256(p.read_bytes()).hexdigest()
         for d in ("go", "cpp") for p in sorted((out / d).glob("*")) if p.is_file()}
json.dump({"tools": tools, "files": files}, open(out / "generate.json", "w"), indent=1)
print(json.dumps({"files": files}, indent=1))
EOF
	exit 0
fi

python3 -I - "$out" "$tools" "$rc_tree" "$ts_tree" <<'EOF'
import hashlib, json, pathlib, sys
out, tools = pathlib.Path(sys.argv[1]), json.loads(sys.argv[2])
rc, ts = pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
pairs = [("go", rc / "protocol/grpc/ricmsgcommrpc/rc/rc.pb.go", out / "go/rc.pb.go")]
pairs += [("cpp", ts / "ext/protobuf" / n, out / "cpp" / n) for n in ("rc.pb.cc", "rc.pb.h", "rc.grpc.pb.cc", "rc.grpc.pb.h")]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
files = [{"side": s, "file": str(c), "committedSha256": sha(c), "regeneratedSha256": sha(g),
          "equal": sha(c) is not None and sha(c) == sha(g)} for s, c, g in pairs]
extra = sorted(str(p.relative_to(out)) for d in ("go", "cpp") for p in (out / d).glob("*")
               if p.name not in {"rc.pb.go", "rc.pb.cc", "rc.pb.h", "rc.grpc.pb.cc", "rc.grpc.pb.h"})
r = {"equal": all(f["equal"] for f in files) and not extra, "files": files, "unexpectedOutputs": extra, "tools": tools}
json.dump(r, open(out / "proof.json", "w"), indent=1)
print(json.dumps({"equal": r["equal"], "files": [(f["side"], pathlib.Path(f["file"]).name, f["equal"]) for f in files],
                  "unexpectedOutputs": extra}))
sys.exit(0 if r["equal"] else 1)
EOF

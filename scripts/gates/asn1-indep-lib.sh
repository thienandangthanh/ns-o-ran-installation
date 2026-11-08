#!/usr/bin/env bash
# asn1-indep-lib.sh: the independent E2AP / E2SM-KPM / X2AP codec image (tools/asn1-indep, pycrate) for the gates'
# subscription and indication judges. Sourced by agents.sh after lib.sh (dk, dk_cmd); never executed.
#
#   asn1_indep_ready              the image of this harness tree's tag (tools/asn1-indep/image-tag.sh) is loaded:
#                                 already present, or loaded from $ASN1_INDEP_DIR/asn1-indep-<tag>.tar (default
#                                 ~/asn1-indep, copied by the host chain driver's pre-flight) after SHA256SUMS names
#                                 that tarball and checks; sets ASN1_INDEP_IMAGE and ASN1_INDEP_IMAGE_ID. Fails closed
#                                 with the reason.
#   kpm_sub_decoded <facts.json>  prints the path of the decoded-subscription sidecar of the fact sheet's capture,
#                                 <facts without -facts.json>-asn1-indep-decoded.json. Always first: the image ready
#                                 and its decode self-test (once per gate run). The sidecar carries its provenance
#                                 (key "provenance": the capture's sha256, e2-sub-setup-decode.py's sha256, the image
#                                 tag and ID) and is reused only when all four equal the current ones; otherwise (also
#                                 when the provenance is missing) it is removed and made again: e2-sub-setup-decode.py
#                                 collect (tshark on facts["pcap"]) piped into its decode mode inside the image
#                                 (offline, the script mounted read-only). The file appears only complete (written
#                                 aside, then renamed); a failed decode leaves no sidecar.
# Every caller runs these inside its own registered check, so a missing image fails that check.

ASN1_INDEP_DIR="${ASN1_INDEP_DIR:-$HOME/asn1-indep}"
ASN1_INDEP_IMAGE=""
ASN1_INDEP_IMAGE_ID=""
_ASN1_INDEP_SELFTEST_RUN=""

asn1_indep_ready() {
    local tag img id
    tag=$(bash "$HARNESS_DIR/tools/asn1-indep/image-tag.sh") || { echo "asn1-indep: image-tag.sh failed"; return 1; }
    img="localhost/asn1-indep:$tag"
    if ! dk image inspect "$img" --format '{{.Id}}' >/dev/null 2>&1; then
        [ -f "$ASN1_INDEP_DIR/SHA256SUMS" ] || { echo "asn1-indep: $img not loaded and no $ASN1_INDEP_DIR/SHA256SUMS"; return 1; }
        grep -q "  asn1-indep-$tag.tar\$" "$ASN1_INDEP_DIR/SHA256SUMS" ||
            { echo "asn1-indep: $ASN1_INDEP_DIR/SHA256SUMS does not name asn1-indep-$tag.tar"; return 1; }
        (cd "$ASN1_INDEP_DIR" && sha256sum -c SHA256SUMS) || { echo "asn1-indep: tarball checksum failed"; return 1; }
        dk load -i "$ASN1_INDEP_DIR/asn1-indep-$tag.tar" || { echo "asn1-indep: docker load failed"; return 1; }
    fi
    id=$(dk image inspect "$img" --format '{{.Id}}') || { echo "asn1-indep: $img not present after the load"; return 1; }
    echo "asn1-indep image $img $id"
    ASN1_INDEP_IMAGE="$img"
    ASN1_INDEP_IMAGE_ID="$id"
}

kpm_sub_decoded() {
    local facts="$1" out pcap tmp want e2ev="$HARNESS_DIR/tools/e2-evidence"
    out="${facts%-facts.json}-asn1-indep-decoded.json"
    pcap=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["pcap"])' "$facts") ||
        { echo "no pcap path in $facts" >&2; return 1; }
    [ -f "$pcap" ] || { echo "capture $pcap of $facts is missing" >&2; return 1; }
    asn1_indep_ready >&2 || return 1
    if [ "$_ASN1_INDEP_SELFTEST_RUN" != "${GATE_TS:-}-$ASN1_INDEP_IMAGE-$ASN1_INDEP_IMAGE_ID" ]; then
        dk run --rm --network=none -v "$e2ev:/e2ev:ro" "$ASN1_INDEP_IMAGE" python3 /e2ev/e2-sub-setup-decode.py \
            --decode-self-test >&2 || { echo "asn1-indep decode self-test failed" >&2; return 1; }
        _ASN1_INDEP_SELFTEST_RUN="${GATE_TS:-}-$ASN1_INDEP_IMAGE-$ASN1_INDEP_IMAGE_ID"
    fi
    want=$(python3 -I -c 'import json, sys; print(json.dumps(dict(zip(
        ("captureSha256", "decoderSha256", "imageTag", "imageId"), sys.argv[1:]))))' \
        "$(sha256sum <"$pcap" | cut -d' ' -f1)" "$(sha256sum <"$e2ev/e2-sub-setup-decode.py" | cut -d' ' -f1)" \
        "$ASN1_INDEP_IMAGE" "$ASN1_INDEP_IMAGE_ID") || { echo "asn1-indep provenance of $pcap failed" >&2; return 1; }
    if [ -s "$out" ]; then
        if python3 -I -c 'import json, sys; sys.exit(json.load(open(sys.argv[1])).get("provenance") != json.loads(sys.argv[2]))' \
            "$out" "$want" 2>/dev/null; then
            echo "asn1-indep sidecar $out reused: provenance $want" >&2
            echo "$out"; return 0
        fi
        echo "asn1-indep sidecar $out: provenance missing or not $want; decoding again" >&2
    fi
    rm -f "$out"
    tmp="$out.partial"
    python3 -I "$e2ev/e2-sub-setup-decode.py" collect "$pcap" >"$tmp.in" || { echo "collect failed on $pcap" >&2; return 1; }
    dk run --rm -i --network=none -v "$e2ev:/e2ev:ro" "$ASN1_INDEP_IMAGE" python3 /e2ev/e2-sub-setup-decode.py decode \
        <"$tmp.in" >"$tmp" || { echo "asn1-indep decode failed on $pcap" >&2; rm -f "$tmp" "$tmp.in"; return 1; }
    python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d, dict) and "provenance" not in d, "the decode is not a frame map"
d["provenance"] = json.loads(sys.argv[2])
json.dump(d, open(sys.argv[1], "w"))' "$tmp" "$want" || { echo "asn1-indep decode of $pcap is not a frame map" >&2; rm -f "$tmp" "$tmp.in"; return 1; }
    rm -f "$tmp.in"
    mv "$tmp" "$out" && echo "$out"
}

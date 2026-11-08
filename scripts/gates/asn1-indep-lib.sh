#!/usr/bin/env bash
# asn1-indep-lib.sh: the independent E2AP / E2SM-KPM / X2AP codec image (tools/asn1-indep, pycrate) for the gates'
# subscription and indication judges. Sourced by agents.sh after lib.sh (dk, dk_cmd); never executed.
#
#   asn1_indep_ready              the image of this harness tree's tag (tools/asn1-indep/image-tag.sh) is loaded:
#                                 already present, or loaded from $ASN1_INDEP_DIR/asn1-indep-<tag>.tar (default
#                                 ~/asn1-indep, copied by the host chain driver's pre-flight) after SHA256SUMS names
#                                 that tarball and checks; sets ASN1_INDEP_IMAGE. Fails closed with the reason.
#   kpm_sub_decoded <facts.json>  prints the path of the decoded-subscription sidecar of the fact sheet's capture,
#                                 <facts without -facts.json>-asn1-indep-decoded.json, made when absent: the image's
#                                 decode self-test (once per gate run), then e2-sub-setup-decode.py collect (tshark on
#                                 facts["pcap"]) piped into its decode mode inside the image (offline, the script
#                                 mounted read-only). The file appears only complete (written aside, then renamed).
# Every caller runs these inside its own registered check, so a missing image fails that check.

ASN1_INDEP_DIR="${ASN1_INDEP_DIR:-$HOME/asn1-indep}"
ASN1_INDEP_IMAGE=""
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
}

kpm_sub_decoded() {
    local facts="$1" out pcap tmp e2ev="$HARNESS_DIR/tools/e2-evidence"
    out="${facts%-facts.json}-asn1-indep-decoded.json"
    if [ -s "$out" ]; then echo "$out"; return 0; fi
    pcap=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["pcap"])' "$facts") ||
        { echo "no pcap path in $facts" >&2; return 1; }
    asn1_indep_ready >&2 || return 1
    if [ "$_ASN1_INDEP_SELFTEST_RUN" != "${GATE_TS:-}-$ASN1_INDEP_IMAGE" ]; then
        dk run --rm --network=none -v "$e2ev:/e2ev:ro" "$ASN1_INDEP_IMAGE" python3 /e2ev/e2-sub-setup-decode.py \
            --decode-self-test >&2 || { echo "asn1-indep decode self-test failed" >&2; return 1; }
        _ASN1_INDEP_SELFTEST_RUN="${GATE_TS:-}-$ASN1_INDEP_IMAGE"
    fi
    tmp="$out.partial"
    python3 -I "$e2ev/e2-sub-setup-decode.py" collect "$pcap" >"$tmp.in" || { echo "collect failed on $pcap" >&2; return 1; }
    dk run --rm -i --network=none -v "$e2ev:/e2ev:ro" "$ASN1_INDEP_IMAGE" python3 /e2ev/e2-sub-setup-decode.py decode \
        <"$tmp.in" >"$tmp" || { echo "asn1-indep decode failed on $pcap" >&2; return 1; }
    rm -f "$tmp.in"
    mv "$tmp" "$out" && echo "$out"
}

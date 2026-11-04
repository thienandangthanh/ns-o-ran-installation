#!/usr/bin/env python3
"""replay-ts-cell-map.py: the TS xApp's cell_map, rebuilt offline from e2mgr nodeb JSON files (G4).

  replay-ts-cell-map.py NODEB.json [NODEB.json ...] [--expect KEY=ranName ...] [--no-key ranName ...] [--no-wrong-node]
  replay-ts-cell-map.py --self-test

Mirrors the patched ts_xapp.cpp NodebHandler (ric-app-ts 19e169b plus the Testbed patch set, N1 =
install_patch_files/xApps/ts/src/ts_xapp/ts_xapp.cpp.nr_cell_map.patch):
  meid      = the last "ranName" string before the request part, e.g. en_gnb_001_001_00000002
  only an NR node has keys: meid ^(en_gnb|gnb)_<3 digits>_<3 digits>_<[0-9a-f]+>$; the last field (the gNB ID hex),
            upper-cased, is the suffix; any other meid (enB_macro_...) contributes no key
  message   = the text of base64-decode(e2nodeComponentRequestPart), decoded as the xApp does (stops at the first
              non-alphabet character): e2mgr keeps the request part as the uppercase hex text of its octets (its XER
              rendering of the OCTET STRING), so the text is the hex of the node's APER X2 setup message
  for every offset where the suffix occurs in `message`: cell_map[message[i:i+10]] = node
so gNB 2's EN-DC X2 SETUP REQUEST gives 0000000210 (its served NR CGI's NCI and 4 unused bits) and 0000000200 (its
Global en-gNB ID followed by the next IE id). Prints the map as JSON ({key: [ranName...]}); a key claimed by two
nodes is listed with both (the xApp keeps the last one it saw). --expect KEY=ranName requires exactly that owner,
--no-key ranName requires that node to own no key, --no-wrong-node requires every key to have one owner whose
suffix equals the key's first 8 hex. Exit 0 when every requirement holds.
"""
import argparse
import base64
import json
import re
import sys

NR_MEID = re.compile(r"^(en_gnb|gnb)_[0-9]{3}_[0-9]{3}_([0-9a-f]+)$")
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def base64_decode(s):
    """ts_xapp.cpp base64_decode: stop at the first character outside the alphabet ('=' included)."""
    out, val, valb = bytearray(), 0, -8
    for c in s:
        if c not in B64:
            break
        val = (val << 6) + B64.index(c)
        valb += 6
        if valb >= 0:
            out.append((val >> valb) & 0xFF)
            valb -= 8
    return bytes(out)


def strings_in_order(node):
    """(key, string value) pairs in document order, as rapidjson's SAX handler sees them."""
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, str):
                yield k, v
            else:
                yield from strings_in_order(v)
    elif isinstance(node, list):
        for v in node:
            yield from strings_in_order(v)


def suffix_of(meid):
    m = NR_MEID.match(meid or "")
    return m.group(2).upper() if m else None


def keys_of(doc):
    name, meid, out = doc.get("ranName"), "", []
    for key, value in strings_in_order(doc):
        if key == "ranName":
            meid = value
        elif key == "e2nodeComponentRequestPart":
            suffix = suffix_of(meid)
            if suffix is None:
                continue
            message = base64_decode(value).decode("latin-1")
            for i in range(0, len(message) - len(suffix) + 1):
                if message[i:i + len(suffix)] == suffix:
                    out.append(message[i:i + 10])
    return name, out


def judge(docs, expect=(), no_key=(), no_wrong_node=False):
    cell_map, owners = {}, {}
    for doc in docs:
        name, keys = keys_of(doc)
        owners[name] = keys
        for k in keys:
            if name not in cell_map.setdefault(k, []):
                cell_map[k].append(name)
    problems = []
    for e in expect:
        key, _, node = e.partition("=")
        if cell_map.get(key) != [node]:
            problems.append("key %s owned by %r, expected [%r]" % (key, cell_map.get(key), node))
    for n in no_key:
        if owners.get(n):
            problems.append("%s owns keys %r, expected none" % (n, owners[n]))
    if no_wrong_node:
        for key, names in sorted(cell_map.items()):
            if len(names) != 1:
                problems.append("key %s has %d owners %r, expected one" % (key, len(names), names))
            elif suffix_of(names[0]) != key[:8]:
                problems.append("key %s owned by %s, whose gNB ID is %s" % (key, names[0], suffix_of(names[0])))
    return {"cellMap": cell_map, "keysByNode": owners}, problems


# self-test fixtures: the agents' X2 request parts (hex) per meid; nodeb() stores each as e2mgr does (base64 of the
# uppercase hex text)
FIXTURE_HEX = {
    "en_gnb_001_001_00000002": "0024004100000100f4003a40000200fc00090000f110500000000200fd002600000400020000f110000000"
                               "0210001000f110410009a9f500004d004100071011353ea50000",
    "en_gnb_001_001_00000003": "0024004100000100f4003a40000200fc00090000f110500000000300fd002600000400020000f110000000"
                               "0310001000f110410009a9f500004d004100071011353ea50000",
    "enB_macro_001_001_000001": "0024003100000100f4002a000002001500080000f1100000001000fa0017000000010000f11000001010"
                                "001000f1100046b4006455",
}


# e2mgr's stored request part of the scripted en-gNB 0x7F000001, verbatim from its nodeb record
# (e2mgr-nodeb-en_gnb_001_001_7f000001.json in the identity probe's evidence, scripts/probes/probe-e2-identity-setup.sh)
E2MGR_RECORD_7F000001 = ("MDAyNDAwNDEwMDAwMDEwMEY0MDAzQTQwMDAwMjAwRkMwMDA5MDAwMEYxMTA1MDdGMDAwMDAxMDBGRDAwMjYwMDAwMDQw"
                         "MDAxMDAwMEYxMTA3RjAwMDAwMTEwMDAxMDAwRjExMDQxMDAwOUE5RjUwMDAwNEQwMDI3MDAwNzEwMTEzNTNFQTUwMDAw")


def nodeb(meid, hexpart, key="gnb"):
    part = base64.b64encode(hexpart.upper().encode()).decode()
    return {"ranName": meid, "connectionStatus": "CONNECTED",
            key: {"nodeConfigs": [{"e2nodeComponentInterfaceType": "x2", "e2nodeComponentRequestPart": part}]}}


def self_test():
    g2, g3, e1 = "en_gnb_001_001_00000002", "en_gnb_001_001_00000003", "enB_macro_001_001_000001"
    docs = [nodeb(g2, FIXTURE_HEX[g2]), nodeb(g3, FIXTURE_HEX[g3]), nodeb(e1, FIXTURE_HEX[e1], "enb")]
    cases = []
    out, problems = judge(docs, ["0000000210=" + g2, "0000000310=" + g3], [e1], True)
    cases.append(("en-gNB 2/3 keys, no eNB key, no wrong node", not problems
                  and out["keysByNode"] == {g2: ["0000000200", "0000000210"], g3: ["0000000300", "0000000310"], e1: []}))
    # the old gnb_ form is still an NR meid; an ASCII-hex request part (the old agent) yields no key from binary hex
    out, _ = judge([nodeb("gnb_001_001_00000002", FIXTURE_HEX[g2])])
    cases.append(("gnb_ meid parsed", out["keysByNode"]["gnb_001_001_00000002"] == ["0000000200", "0000000210"]))
    # the stored form decides: base64 of the binary octets (not what e2mgr keeps) yields no key
    raw = {"ranName": g2, "gnb": {"nodeConfigs": [{"e2nodeComponentRequestPart":
                                                   base64.b64encode(bytes.fromhex(FIXTURE_HEX[g2])).decode()}]}}
    out, _ = judge([raw])
    cases.append(("a request part stored as binary octets gives no key", out["keysByNode"][g2] == []))
    # e2mgr's real record of a scripted en-gNB
    real = {"ranName": "en_gnb_001_001_7f000001",
            "gnb": {"nodeConfigs": [{"e2nodeComponentRequestPart": E2MGR_RECORD_7F000001}]}}
    out, problems = judge([real], ["7F00000110=en_gnb_001_001_7f000001"], no_wrong_node=True)
    cases.append(("e2mgr's stored record gives its NR CGI key and its Global en-gNB ID key", not problems
                  and out["keysByNode"]["en_gnb_001_001_7f000001"] == ["7F00000100", "7F00000110"]))
    # an eNB meid never contributes, even when its request part holds the text
    out, problems = judge([nodeb("enB_macro_001_001_00000002", FIXTURE_HEX[g2])], no_key=["enB_macro_001_001_00000002"])
    cases.append(("enB_macro meid gives no key", not problems))
    # --no-wrong-node: two nodes with one gNB ID share every key; a gNB ID shorter than 8 hex gives keys whose first
    # 8 hex are not its own
    _, problems = judge([nodeb(g2, FIXTURE_HEX[g2]), nodeb("gnb_001_001_00000002", FIXTURE_HEX[g2])], no_wrong_node=True)
    cases.append(("a key with two owners fails --no-wrong-node", any("2 owners" in p for p in problems)))
    _, problems = judge([nodeb("gnb_001_001_000002", FIXTURE_HEX[g2])], no_wrong_node=True)
    cases.append(("a key not led by its owner's gNB ID fails --no-wrong-node", any("whose gNB ID" in p for p in problems)))
    _, problems = judge([nodeb(g2, FIXTURE_HEX[g2])], ["0000000310=" + g3])
    cases.append(("a missing expected key fails --expect", bool(problems)))
    _, problems = judge([nodeb(g2, FIXTURE_HEX[g2])], no_key=[g2])
    cases.append(("a node with keys fails --no-key", bool(problems)))
    # the xApp's decoder stops at '=': padding never adds bytes
    cases.append(("decoder stops at padding", base64_decode("AAE=") == b"\x00\x01"))
    for name, ok in cases:
        print("%s %s" % ("ok  " if ok else "FAIL", name))
    return 0 if all(ok for _, ok in cases) else 1


def main():
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--expect", action="append", default=[])
    ap.add_argument("--no-key", action="append", default=[])
    ap.add_argument("--no-wrong-node", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.files:
        ap.error("at least one NODEB.json is required")
    docs = []
    for f in a.files:
        with open(f) as fh:
            docs.append(json.load(fh))
    out, problems = judge(docs, a.expect, a.no_key, a.no_wrong_node)
    print(json.dumps(out, indent=1, sort_keys=True))
    for p in problems:
        print("problem: " + p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

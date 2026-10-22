#!/usr/bin/env python3
"""replay-ts-cell-map.py: the TS xApp's cell_map, rebuilt offline from e2mgr nodeb JSON files (G4).

  replay-ts-cell-map.py NODEB.json [NODEB.json ...] [--expect KEY=ranName ...] [--no-key ranName ...]

Mirrors ts_xapp.cpp (the nodeb loop that fills cell_map, ric-app-ts 19e169b as installed by NIST):
  meid      = the node's ranName, e.g. gnb_001_001_00000002
  suffix    = meid after its third underscore, lowercased (the gNB id hex, 00000002)
  message   = base64-decode(e2nodeComponentRequestPart), lowercased (e2mgr renders the 5 request-part
              octets as hex text)
  for every position where `suffix` occurs in `message`: cell_map[message[i:i+10]] = node
so a gNB agent's `00 00 00 02 02` request part gives the key 0000000202, and an eNB's "reqpart" gives
nothing. Prints the map as JSON ({key: [ranName...]}); a key claimed by two nodes is listed with both
(the xApp keeps the last one it saw). --expect KEY=ranName requires exactly that owner, --no-key
ranName requires that node to own no key. Exit 0 when every requirement holds.
"""
import argparse
import base64
import json
import sys


def keys_of(doc):
    name = doc["ranName"]
    parts = (doc.get("gnb") or doc.get("enb") or {}).get("nodeConfigs", [])
    out = []
    for cfg in parts:
        raw = cfg.get("e2nodeComponentRequestPart", "")
        message = base64.b64decode(raw).decode("latin-1").lower() if raw else ""
        suffix = name.split("_", 3)[3].lower() if name.count("_") >= 3 else ""
        if not suffix:
            continue
        for i in range(0, len(message) - len(suffix) + 1):
            if message[i:i + len(suffix)] == suffix:
                out.append(message[i:i + 10])
    return name, out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="+")
    ap.add_argument("--expect", action="append", default=[])
    ap.add_argument("--no-key", action="append", default=[])
    a = ap.parse_args()
    cell_map, owners = {}, {}
    for f in a.files:
        name, keys = keys_of(json.load(open(f)))
        owners[name] = keys
        for k in keys:
            cell_map.setdefault(k, []).append(name)
    print(json.dumps({"cellMap": cell_map, "keysByNode": owners}, indent=1, sort_keys=True))
    problems = []
    for e in a.expect:
        key, _, node = e.partition("=")
        if cell_map.get(key) != [node]:
            problems.append("key %s owned by %r, expected [%r]" % (key, cell_map.get(key), node))
    for n in a.no_key:
        if owners.get(n):
            problems.append("%s owns keys %r, expected none" % (n, owners[n]))
    for p in problems:
        print("problem: " + p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

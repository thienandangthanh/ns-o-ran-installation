#!/usr/bin/env python3
"""rung-config.py: read and write scripts/gates/rung-config.json, the values every R-rung gate uses.

  rung-config.py get PATH            print the value at a dotted path (scenario.simStartEpochMs)
  rung-config.py set PATH VALUE PROVENANCE   set the value (JSON) and its provenance text
  rung-config.py show                print the whole file

A path names an object holding "value" and "provenance" (deadlines.T_ctl_s), or a leaf scalar.
A value is never changed without a provenance that names the evidence directory or decision
behind it; `set` refuses an empty provenance.
"""
import json
import os
import sys

PATH = os.environ.get("RUNG_CONFIG", os.path.join(os.path.dirname(os.path.abspath(__file__)), "rung-config.json"))


def walk(cfg, dotted):
    node = cfg
    for part in dotted.split("."):
        node = node[part]
    return node


def main(argv):
    cfg = json.load(open(PATH))
    if len(argv) >= 2 and argv[0] == "get":
        node = walk(cfg, argv[1])
        v = node["value"] if isinstance(node, dict) and "value" in node else node
        print(json.dumps(v) if not isinstance(v, str) else v)
        return 0
    if len(argv) == 4 and argv[0] == "set":
        if not argv[3].strip():
            print("rung-config: a value needs a provenance", file=sys.stderr)
            return 2
        node = walk(cfg, argv[1])
        node["value"] = json.loads(argv[2])
        node["provenance"] = argv[3]
        json.dump(cfg, open(PATH, "w"), indent=2)
        open(PATH, "a").write("\n")
        return 0
    if argv == ["show"]:
        print(json.dumps(cfg, indent=2))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

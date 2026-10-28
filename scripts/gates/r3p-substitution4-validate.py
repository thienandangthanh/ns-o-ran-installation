#!/usr/bin/env python3
"""r3p-substitution4-validate.py: does the committed substitution 4 record still describe the frozen harness?

  r3p-substitution4-validate.py RECORD ROOT     exit 0 when valid, 1 otherwise (prints why)
  r3p-substitution4-validate.py --self-test
The record (scripts/gates/r3p-substitution4.json) is valid only when its dry-run evidence dir exists under ROOT and
its rung-config and scenario sha256s equal the files at ROOT/scripts/gates/. run-to-m9.sh selects R2 as the top
rung only with a valid record; an invalid one fails the M9 verdict.
"""
import hashlib
import json
import os
import pathlib
import sys
import tempfile

CFG, SCEN = "scripts/gates/rung-config.json", "scripts/gates/r3p-scenario.json"


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def validate(record, root):
    try:
        r = json.load(open(record))
        problems = []
        if not os.path.isdir(os.path.join(root, r["dryRunEvidenceDir"])):
            problems.append("dry-run evidence dir %s is missing" % r["dryRunEvidenceDir"])
        if sha(os.path.join(root, CFG)) != r["rungConfigSha256"]:
            problems.append("rung-config sha256 differs from the record")
        if sha(os.path.join(root, SCEN)) != r["scenarioSha256"]:
            problems.append("scenario sha256 differs from the record")
    except (OSError, ValueError, KeyError, TypeError) as e:
        problems = ["unreadable record or harness file: %s" % e]
    return problems


def self_test():
    bad = 0
    for name, mut, want in [("a valid record", {}, True), ("the evidence dir is missing", {"dir": "gone"}, False),
                            ("a wrong rung-config sha256", {"cfg": "0" * 64}, False),
                            ("a wrong scenario sha256", {"scen": "0" * 64}, False),
                            ("a record without its keys", {"empty": True}, False)]:
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            (root / "scripts/gates").mkdir(parents=True)
            (root / CFG).write_text('{"cfg": 1}')
            (root / SCEN).write_text('{"scen": 1}')
            (root / "evidence/r3p/dry").mkdir(parents=True)
            rec = {} if mut.get("empty") else {"dryRunEvidenceDir": "evidence/r3p/" + mut.get("dir", "dry"),
                                                "rungConfigSha256": mut.get("cfg", sha(root / CFG)),
                                                "scenarioSha256": mut.get("scen", sha(root / SCEN))}
            (root / "rec.json").write_text(json.dumps(rec))
            got = not validate(root / "rec.json", root)
        bad += got != want
        print(("ok   " if got == want else "FAIL ") + name)
    print("substitution 4 validator self-test: %s" % ("ok" if not bad else "%d failure(s)" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    p = validate(sys.argv[1], sys.argv[2])
    print("substitution 4 record %s" % ("validated" if not p else "does NOT validate: " + "; ".join(p)))
    sys.exit(0 if not p else 1)

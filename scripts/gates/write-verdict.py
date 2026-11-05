#!/usr/bin/env python3
"""Write a gate's verdict.json from its recorded checks and facts.

    write-verdict.py CHECKS_FILE OUT GATE TS HARNESS_SHA START_EPOCH PINS_CONF
        the verdict gate_finish (lib.sh) writes at the end of every gate: pass = at least one check ran and every
        check passed; failed = the names of the failed checks; facts.jsonl next to OUT adds top-level fields.
    write-verdict.py --outer-timeout SECONDS CHECKS_FILE OUT GATE TS HARNESS_SHA START_EPOCH PINS_CONF
        the verdict vm-exec.sh writes after its outer timeout stopped the gate's unit before gate_finish ran: the
        same verdict over the checks recorded so far, plus one failed check `outer_timeout` (also appended to
        CHECKS_FILE) and the field outerTimeoutS. A verdict.json the gate had already written is kept as
        verdict-before-outer-timeout.json, so a stopped run never reads as passed.
    write-verdict.py --self-test
"""
import json
import os
import sys
import tempfile
import time

RESERVED = ("gate", "ts", "harness_sha", "pins", "duration_s", "pass", "failed", "checks")


def read_pins(path):
    pins = {}
    for line in open(path).read().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            pins[k] = v
    return pins


def read_jsonl(path, tolerant):
    """The records of a JSONL file. Strict by default (the normal gate_finish path); tolerant after an outer-timeout
    stop, which can cut a record()/fact() printf short: unparseable lines are returned separately, never raised."""
    good, bad = [], []
    if not os.path.exists(path):
        return good, bad
    for line in open(path, errors="replace"):
        if not line.strip():
            continue
        try:
            good.append(json.loads(line))
        except ValueError:
            if not tolerant:
                raise
            bad.append(line.rstrip("\n"))
    return good, bad


def write_verdict(checks_file, out, gate, ts, harness, start, pins, outer_timeout_s=None):
    tolerant = outer_timeout_s is not None
    if tolerant:
        rec = {"name": "outer_timeout", "pass": False,
               "detail": f"vm-exec.sh stopped the gate unit after its {outer_timeout_s} s outer timeout, "
                         "before gate_finish wrote the verdict"}
        # start on a fresh line: the stop may have left a record without its newline
        cut = os.path.exists(checks_file) and os.path.getsize(checks_file) > 0 and \
            open(checks_file, "rb").read()[-1:] != b"\n"
        with open(checks_file, "a") as f:
            f.write(("\n" if cut else "") + json.dumps(rec) + "\n")
    checks, bad_checks = read_jsonl(checks_file, tolerant)
    if bad_checks:
        checks.append({"name": "unparseable_check_records", "pass": False,
                       "detail": f"{len(bad_checks)} line(s) of {os.path.basename(checks_file)} cut short by the stop: "
                                 + " | ".join(b[:200] for b in bad_checks)})
    verdict = {
        "gate": gate, "ts": ts, "harness_sha": harness, "pins": read_pins(pins),
        "duration_s": int(time.time()) - int(start),
        "pass": bool(checks) and all(c.get("pass") is True for c in checks),
        "failed": [c.get("name") for c in checks if c.get("pass") is not True],
        "checks": checks,
    }
    facts, bad_facts = read_jsonl(os.path.join(os.path.dirname(out), "facts.jsonl"), tolerant)
    for f in facts:
        if f["key"] not in RESERVED:
            verdict[f["key"]] = f["value"]
    if tolerant:
        verdict["outerTimeoutS"] = int(outer_timeout_s)
        verdict["unparseableFactLines"] = len(bad_facts)
        verdict["pass"] = False
    # publish atomically; after a stop, an earlier verdict is kept aside first so the run never reads as passed
    tmp = out + ".tmp"
    with open(tmp, "w") as f:
        json.dump(verdict, f, indent=2)
    if tolerant and os.path.exists(out):
        os.replace(out, os.path.join(os.path.dirname(out), "verdict-before-outer-timeout.json"))
    os.replace(tmp, out)
    print(f"verdict {gate}: {'PASS' if verdict['pass'] else 'FAIL'} failed={verdict['failed']}")
    return verdict


def self_test():
    ok = True
    with tempfile.TemporaryDirectory() as d:
        ck, out, pins = (os.path.join(d, n) for n in ("checks.jsonl", "verdict.json", "pins.conf"))
        open(pins, "w").write("# c\nNS3_SHA=abc\n")
        open(ck, "w").write('{"name":"a","pass":true,"detail":""}\n')
        open(os.path.join(d, "facts.jsonl"), "w").write('{"key":"agentsConnected","value":11}\n'
                                                        '{"key":"pass","value":true}\n')
        v = write_verdict(ck, out, "g", "t", "h", int(time.time()), pins)
        ok &= v["pass"] is True and v["agentsConnected"] == 11 and v["pins"] == {"NS3_SHA": "abc"}
        # a stopped unit whose gate had already written a passing verdict: the pass is kept aside, the verdict fails
        v = write_verdict(ck, out, "g", "t", "h", int(time.time()), pins, outer_timeout_s=5400)
        ok &= v["pass"] is False and v["failed"] == ["outer_timeout"] and v["outerTimeoutS"] == 5400
        ok &= json.load(open(os.path.join(d, "verdict-before-outer-timeout.json")))["pass"] is True
        ok &= json.loads(open(ck).read().splitlines()[-1])["name"] == "outer_timeout"
        # a unit stopped before any check ran: no checks file at all still yields a failing verdict
        os.remove(ck); os.remove(out)
        v = write_verdict(ck, out, "g", "t", "h", int(time.time()), pins, outer_timeout_s=60)
        ok &= v["pass"] is False and v["failed"] == ["outer_timeout"]
        # a stop that cut a check record and a fact record short: still a failing verdict, the fragment recorded
        open(ck, "w").write('{"name":"a","pass":true,"detail":""}\n{"name":"b","pa')
        open(os.path.join(d, "facts.jsonl"), "a").write('{"key":"x","val')
        v = write_verdict(ck, out, "g", "t", "h", int(time.time()), pins, outer_timeout_s=60)
        ok &= v["pass"] is False and v["failed"] == ["outer_timeout", "unparseable_check_records"]
        ok &= v["unparseableFactLines"] == 1 and v["agentsConnected"] == 11
        ok &= json.loads(open(ck).read().splitlines()[-1])["name"] == "outer_timeout"
        # the normal path stays strict: a cut record is an error, not a verdict
        try:
            write_verdict(ck, out, "g", "t", "h", int(time.time()), pins)
            ok = False
        except ValueError:
            pass
        os.remove(os.path.join(d, "facts.jsonl"))
        # no checks and no timeout: nothing ran, so the gate does not pass
        os.remove(ck)
        v = write_verdict(ck, out, "g", "t", "h", int(time.time()), pins)
        ok &= v["pass"] is False
    print("write-verdict self-test:", "ok" if ok else "FAILED")
    return 0 if ok else 1


def main(argv):
    if argv[:1] == ["--self-test"]:
        return self_test()
    outer = None
    if argv[:1] == ["--outer-timeout"]:
        outer, argv = argv[1], argv[2:]
    if len(argv) != 7:
        sys.exit(__doc__)
    write_verdict(*argv, outer_timeout_s=outer)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

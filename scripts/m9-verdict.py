#!/usr/bin/env python3
"""m9-verdict.py: the fail-closed M9 verdict (run-to-m9.sh; amendment A1, Codex F07/F08).

  m9-verdict.py STEPS_TSV OUT --expected m0,...,r3p --top r3p|r2 --full 0|1 --watchdog-dir DIR --pins FILE
                --harness SHA --prefix P --snapshots 0|1 --end-epoch E [--sub4 pass|fail|none] [--min-free-floor 25]
STEPS_TSV: step<TAB>pass|fail<TAB>evidence dir, one line per step run. The run passes only when:
  - the steps run are exactly the pre-registered list, in order (no missing or extra step), each green, and each
    step's own verdict.json (when it has evidence) agrees;
  - the run is the full chain (--full 1); a --from/--to subset is marked notM9 and never passes;
  - the top rung (R3′, or R2 under substitution 4) ran --mode c1, every check passed, and equalsReference is true;
  - under substitution 4 the committed record validated (--sub4 pass);
  - DIR/min-host-free-gb.txt holds an integer >= the floor (25 GB), no watchdog-tripped.json, watchdog-lost.json,
    wall-deadline.json or monitor-lost.json, and DIR/watchdog-alive.json shows the heartbeat never older than 2
    polling periods with the monitor's last check within 2 polling periods of the run's end (E, epoch seconds).
Every rung verdict's substitution3Applied is carried. Exit 0 iff the verdict passes.
  m9-verdict.py --self-test
"""
import json
import os
import sys
import tempfile


def arg(av, k, default=None):
    return av[av.index(k) + 1] if k in av else default


def read_json(p):
    try:
        return json.load(open(p))
    except (OSError, ValueError):
        return None


def facts(v):
    return v or {}


def judge(steps_tsv, expected, top, full, wd, sub4, floor, end):
    probs, steps = [], []
    for line in open(steps_tsv):
        if not line.strip():
            continue
        step, status, ev = (line.rstrip("\n").split("\t") + ["", ""])[:3]
        v = read_json(os.path.join(ev, "verdict.json")) if ev else None
        e = {"step": step, "pass": status == "pass", "evidence": ev}
        if v is not None:
            e.update(gatePass=v.get("pass"), failed=v.get("failed", []), pins=v.get("pins", {}), mode=v.get("mode"),
                     substitution3Applied=v.get("substitution3Applied"), equalsReference=v.get("equalsReference"))
            if v.get("pass") != e["pass"]:
                probs.append("%s: runner status %s, gate verdict pass %s" % (step, status, v.get("pass")))
        steps.append(e)
    ran = [s["step"] for s in steps]
    if ran != expected:
        probs.append("steps run %r, pre-registered %r" % (ran, expected))
    probs += ["%s is red" % s["step"] for s in steps if not s["pass"]]
    if not full:
        probs.append("a --from/--to subset is not M9 (notM9)")
    t = next((s for s in steps if s["step"] == top), None)
    if t is None or t.get("mode") != "c1" or t.get("gatePass") is not True or t.get("equalsReference") is not True:
        probs.append("top rung %s: mode %r, all checks %r, equalsReference %r" % (
            top, t and t.get("mode"), t and t.get("gatePass"), t and t.get("equalsReference")))
    if top == "r2" and sub4 != "pass":
        probs.append("R2 is the top rung but the substitution 4 record did not validate (%s)" % sub4)
    mf = None
    try:
        mf = int(open(os.path.join(wd, "min-host-free-gb.txt")).read().strip())
    except (OSError, ValueError):
        probs.append("no minHostFreeGb recorded")
    if mf is not None and mf < floor:
        probs.append("minHostFreeGb %d < %d" % (mf, floor))
    for f in ("watchdog-tripped.json", "watchdog-lost.json", "wall-deadline.json", "monitor-lost.json"):
        if os.path.exists(os.path.join(wd, f)):
            probs.append(f + " present")
    alive = read_json(os.path.join(wd, "watchdog-alive.json"))
    if not alive or not isinstance(alive.get("maxAgeS"), (int, float)) or alive["maxAgeS"] > 2 * alive.get("intervalS", 0) \
            or not alive.get("checks"):
        probs.append("watchdog heartbeat not shown alive throughout: %r" % alive)
    elif not isinstance(alive.get("lastCheckEpoch"), int) or not 0 <= end - alive["lastCheckEpoch"] <= 2 * alive.get("intervalS", 0):
        probs.append("the heartbeat monitor's last check (%r) is not within 2 polling periods of the run's end %d"
                     % (alive.get("lastCheckEpoch"), end))
    rungs = [s for s in steps if s["step"].startswith("r")]
    return {"steps": steps, "expectedSteps": expected, "exactStepSet": ran == expected, "notM9": not full,
            "topRung": top, "highestGreenRung": top if t and t["pass"] else None,
            "topRungC1Pass": bool(t and t.get("mode") == "c1" and t.get("gatePass") is True),
            "equalsReference": bool(t and t.get("equalsReference") is True), "substitution4": top == "r2",
            "substitution4Record": sub4, "substitution3Applied": {s["step"]: s.get("substitution3Applied") for s in rungs},
            "minHostFreeGb": mf, "minHostFreeFloorGb": floor, "watchdogAlive": alive,
            "problems": probs, "pass": not probs}


def main(av):
    expected = arg(av, "--expected").split(",")
    v = judge(av[0], expected, arg(av, "--top"), arg(av, "--full") == "1", arg(av, "--watchdog-dir"),
              arg(av, "--sub4", "none"), int(arg(av, "--min-free-floor", "25")), int(arg(av, "--end-epoch")))
    pins = {}
    for line in open(arg(av, "--pins")):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, val = line.split("=", 1)
            pins[k] = val
    v.update(harness_sha=arg(av, "--harness"), pins=pins, run_prefix=arg(av, "--prefix"),
             snapshots=arg(av, "--snapshots") == "1")
    json.dump(v, open(av[1], "w"), indent=2)
    print("M9 verdict: %s top rung %s, min host free %s GB -> %s%s" % (
        "PASS" if v["pass"] else "FAIL", v["highestGreenRung"], v["minHostFreeGb"], av[1],
        "" if v["pass"] else "; " + "; ".join(v["problems"][:4])))
    return 0 if v["pass"] else 1


END = 1_800_000_000


def self_test():
    full = ["m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "i0", "r0", "r1", "i2", "r2", "r3p"]
    sub4 = full[:-1]

    def build(d, steps, top_mode="c1", eq=True, mf="31", alive=None, extra=()):
        lines = []
        for s in steps:
            ev = os.path.join(d, s)
            os.makedirs(ev)
            v = {"pass": True, "failed": [], "substitution3Applied": True if s.startswith("r") else None}
            if s == steps[-1] and s.startswith("r"):
                v.update(mode=top_mode, equalsReference=eq)
            json.dump(v, open(os.path.join(ev, "verdict.json"), "w"))
            lines.append("%s\tpass\t%s\n" % (s, ev))
        open(os.path.join(d, "steps.tsv"), "w").write("".join(lines))
        wd = os.path.join(d, "wd")
        os.makedirs(wd)
        if mf is not None:
            open(os.path.join(wd, "min-host-free-gb.txt"), "w").write(mf)
        if alive is not False:
            json.dump(alive or {"intervalS": 60, "maxAgeS": 61, "checks": 400, "lastCheckEpoch": END - 30},
                      open(os.path.join(wd, "watchdog-alive.json"), "w"))
        for f in extra:
            open(os.path.join(wd, f), "w").write("{}")
        return os.path.join(d, "steps.tsv"), wd

    cases = [  # name, steps, expected, top, full, sub4, build kwargs, want
        ("full chain to R3′", full, full, "r3p", True, "none", {}, True),
        ("substitution 4: R2 top rung with a valid record", sub4, sub4, "r2", True, "pass", {}, True),
        ("substitution 4 record invalid", sub4, sub4, "r2", True, "fail", {}, False),
        ("no heartbeat record", full, full, "r3p", True, "none", {"alive": False}, False),
        ("a stale heartbeat (older than 2 polling periods)", full, full, "r3p", True, "none",
         {"alive": {"intervalS": 60, "maxAgeS": 125, "checks": 400, "lastCheckEpoch": END - 30}}, False),
        ("the monitor died after one early check (no check near the end)", full, full, "r3p", True, "none",
         {"alive": {"intervalS": 60, "maxAgeS": 60, "checks": 1, "lastCheckEpoch": END - 7200}}, False),
        ("a monitor record without its last-check time", full, full, "r3p", True, "none",
         {"alive": {"intervalS": 60, "maxAgeS": 60, "checks": 400}}, False),
        ("the runner saw a monitor exit", full, full, "r3p", True, "none", {"extra": ("monitor-lost.json",)}, False),
        ("the watchdog lost", full, full, "r3p", True, "none", {"extra": ("watchdog-lost.json",)}, False),
        ("the global wall deadline passed", full, full, "r3p", True, "none", {"extra": ("wall-deadline.json",)}, False),
        ("the watchdog tripped", full, full, "r3p", True, "none", {"extra": ("watchdog-tripped.json",)}, False),
        ("no minHostFreeGb", full, full, "r3p", True, "none", {"mf": None}, False),
        ("minHostFreeGb 24", full, full, "r3p", True, "none", {"mf": "24"}, False),
        ("a --from/--to subset", full, full, "r3p", False, "none", {}, False),
        ("a missing step", full[:9] + full[10:], full, "r3p", True, "none", {}, False),
        ("an extra step", full + ["r3"], full, "r3p", True, "none", {}, False),
        ("the top rung did not equal the reference", full, full, "r3p", True, "none", {"eq": False}, False),
        ("the top rung ran single, not c1", full, full, "r3p", True, "none", {"top_mode": "single"}, False),
    ]
    bad = 0
    for name, steps, exp, top, fl, s4, kw, want in cases:
        with tempfile.TemporaryDirectory() as d:
            tsv, wd = build(d, steps, **kw)
            got = judge(tsv, exp, top, fl, wd, s4, 25, END)["pass"]
        bad += got != want
        print(("ok   " if got == want else "FAIL ") + name)
    print("m9 verdict self-test: %s" % ("ok" if not bad else "%d failure(s)" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

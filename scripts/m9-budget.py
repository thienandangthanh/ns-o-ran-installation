#!/usr/bin/env python3
"""m9-budget.py: the M9 wall and disk budget from measured dev data (phase 9, amendment A1, Codex F02/F07/F08).

  m9-budget.py --steps m0,...,r3p --chain-log LOG --out-json scripts/m9-budget.json [--interval 30]
Per step, d = the longest green duration_s over every evidence verdict of that gate in the mode M9 runs (r0, r1, r2:
single; r3p: c1; r2 when it is the top rung: c1). timeout = ceil(1.5 x d) + 600 s. The chain log (a run-to-m7.sh
log from fresh-install) gives the revert and every snapshot boundary (graceful shutdown -> snapshot created) and the
host free at each boundary; globalWallS = ceil(1.5 x (sum d + revert + boundaries)). h, the watchdog's preventive
headroom: the fastest measured host-disk growth between boundaries (GB/s) x the longer stop path (2 polling periods
for a stale heartbeat + one monitor check + 30 s cancellation + 240 s graceful shutdown), rounded up; tripGb = 25 + h.
Prints the table as Markdown; refuses (exit 1) when a step has no green measurement.
"""
import glob
import json
import math
import re
import sys
from datetime import datetime

ROOTS = ("plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence", "plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence")
MODE = {"r0": "single", "r1": "single", "r2": "single", "r3p": "c1"}


def arg(av, k, d=None):
    return av[av.index(k) + 1] if k in av else d


def durations(steps, top):
    out = {}
    for s in steps:
        want = "c1" if s == top else MODE.get(s)
        best = None
        for root in ROOTS:
            for p in glob.glob("%s/%s/*/verdict.json" % (root, s)):
                try:
                    v = json.load(open(p))
                except (OSError, ValueError):
                    continue
                if v.get("pass") is True and isinstance(v.get("duration_s"), int) and (want is None or v.get("mode") == want) \
                        and not v.get("dev"):
                    if best is None or v["duration_s"] > best[0]:
                        best = (v["duration_s"], p.rsplit("/", 1)[0])
        out[s] = best
    return out


def chain(log):
    """(revert s, [boundary s], [(t, free GB)]) from a run-to-m7.sh log."""
    ts = lambda l: datetime.strptime(re.search(r"\[host (\d\d:\d\d:\d\d)\]", l).group(1), "%H:%M:%S")
    lines = [l for l in open(log) if l.startswith("[host ")]
    sec = lambda a, b: (ts(b) - ts(a)).seconds
    done = next((i for i, l in enumerate(lines) if "reverted to" in l), None)
    start = next((i for i in range(done or 0, -1, -1) if "graceful shutdown" in lines[i]), None) if done is not None else None
    if start is None:
        sys.exit("the chain log holds no revert (shutdown ... reverted to)")
    revert = sec(lines[start], lines[done])
    bounds, free = [], []
    for i, l in enumerate(lines):
        if "graceful shutdown" in l and i + 2 < len(lines) and "snapshot" in lines[i + 2] and "created" in lines[i + 2]:
            bounds.append(sec(l, lines[i + 2]))
        m = re.search(r"\(host free (\d+)G\)", l)
        if m:
            free.append((ts(l), int(m.group(1))))
    return revert, bounds, free


def main(av):
    steps = arg(av, "--steps").split(",")
    top = steps[-1]
    interval = int(arg(av, "--interval", "30"))
    d = durations(steps, top)
    missing = [s for s, v in d.items() if v is None]
    if missing:
        print("no green measurement for %s" % missing, file=sys.stderr)
        return 1
    revert, bounds, free = chain(arg(av, "--chain-log"))
    rates = []
    for (t0, f0), (t1, f1) in zip(free, free[1:]):
        dt = (t1 - t0).seconds
        if dt > 0 and f0 > f1:
            rates.append((f0 - f1) / dt)
    rate = max(rates)
    stop_path = 2 * interval + interval + 30 + 240
    h = math.ceil(rate * stop_path)
    total = sum(v[0] for v in d.values()) + revert + sum(bounds)
    budget = {"_comment": "measured by scripts/m9-budget.py; see plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md",
              "timeoutsS": {s: math.ceil(1.5 * v[0]) + 600 for s, v in d.items()},
              "measuredS": {s: {"durationS": v[0], "evidence": v[1]} for s, v in d.items()},
              "revertS": revert, "boundariesS": bounds, "globalWallS": math.ceil(1.5 * total),
              "watchdog": {"intervalS": interval, "maxGrowthGbPerS": round(rate, 5), "stopPathS": stop_path,
                           "hGb": h, "tripGb": 25 + h}}
    json.dump(budget, open(arg(av, "--out-json"), "w"), indent=1)
    print("| Step | Longest green (s) | Timeout (s) | Evidence |\n|---|---|---|---|")
    for s, v in d.items():
        print("| %s | %d | %d | `%s` |" % (s, v[0], budget["timeoutsS"][s], v[1]))
    print("\nrevert %d s, %d boundaries %d s, sum %d s, global wall %d s; max growth %.4f GB/s x stop path %d s -> h %d GB, "
          "trip %d GB" % (revert, len(bounds), sum(bounds), total, budget["globalWallS"], rate, stop_path, h, 25 + h))
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

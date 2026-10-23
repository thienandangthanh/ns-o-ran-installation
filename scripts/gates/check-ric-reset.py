#!/usr/bin/env python3
"""check-ric-reset.py PREFIX: was the per-run RIC reset fresh?

Reads PREFIX-start.txt (UTC time the reset began), PREFIX-bucket-before.txt / -after.txt (the kpimon Influx
bucket id) and PREFIX-pods-before.json / -after.json (`kubectl -n ricxapp get pods -o json`). Fresh means: one
new bucket id; rc, kpimon and hw-go each a different pod (name and uid) whose pod start time and container
start times are not before the reset began. Writes PREFIX.json; exit 1 when the reset was not fresh.
"""
import json
import sys

PODS = ("xapp-rc", "ricxapp-kpimon-go", "ricxapp-hw-go")


def pods(path):
    out = {}
    for p in json.load(open(path))["items"]:
        name = p["metadata"]["name"]
        for k in PODS:
            if k + "-" in name:
                cs = p["status"].get("containerStatuses", [])
                out[k] = {"name": name, "uid": p["metadata"]["uid"], "startTime": p["status"].get("startTime"),
                          "containerStartedAt": sorted(c.get("state", {}).get("running", {}).get("startedAt") or ""
                                                       for c in cs)}
    return out


def main(r):
    start = open(r + "-start.txt").read().strip()
    before, after = pods(r + "-pods-before.json"), pods(r + "-pods-after.json")
    bb, ba = open(r + "-bucket-before.txt").read().split(), open(r + "-bucket-after.txt").read().split()
    problems = []
    if len(ba) != 1 or ba == bb:
        problems.append("bucket id before %r, after %r: not one new id" % (bb, ba))
    for k in PODS:
        if k not in after:
            problems.append("%s: no pod after the reset" % k)
            continue
        if k in before and (before[k]["uid"] == after[k]["uid"] or before[k]["name"] == after[k]["name"]):
            problems.append("%s: the same pod before and after the reset" % k)
        times = [after[k]["startTime"] or ""] + after[k]["containerStartedAt"]
        if any(t < start for t in times):  # RFC 3339 UTC strings with a Z suffix compare in time order
            problems.append("%s started %r, before the reset began at %s" % (k, times, start))
    rec = {"resetStartUtc": start, "bucketBefore": bb, "bucketAfter": ba, "podsBefore": before, "podsAfter": after,
           "problems": problems, "fresh": not problems}
    with open(r + ".json", "w") as f:
        json.dump(rec, f, indent=1, sort_keys=True)
        f.write("\n")
    print(json.dumps({"bucketAfter": ba, "podsAfter": {k: v["name"] for k, v in after.items()}, "fresh": not problems}))
    for q in problems:
        print("problem: " + q)
    return 0 if not problems else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))

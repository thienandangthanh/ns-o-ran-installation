#!/usr/bin/env python3
"""check-ts-stub-reset.py PREFIX: were the TS xApp and stub QP pods recreated for this run?

Reads PREFIX-start.txt (UTC time the pod reset began) and PREFIX-pods-before.json / -after.json
(`kubectl -n ricxapp get pods -o json`). Fresh means: the TS xApp and the stub QP each a different pod (name
and uid) whose pod start time and container start times are not before the reset began, and a restart count
of 0. Writes PREFIX.json; exit 1 when the reset was not fresh.
"""
import json
import sys

PODS = ("ricxapp-trafficxapp", "ricxapp-stubqp")


def pods(path):
    out = {}
    for p in json.load(open(path))["items"]:
        name = p["metadata"]["name"]
        if p["metadata"].get("deletionTimestamp"):
            continue
        for k in PODS:
            if name.startswith(k + "-"):
                cs = p["status"].get("containerStatuses", [])
                out[k] = {"name": name, "uid": p["metadata"]["uid"], "startTime": p["status"].get("startTime"),
                          "containerStartedAt": sorted(c.get("state", {}).get("running", {}).get("startedAt") or ""
                                                       for c in cs),
                          "restarts": sum(c.get("restartCount", 0) for c in cs)}
    return out


def main(r):
    start = open(r + "-start.txt").read().strip()
    before, after = pods(r + "-pods-before.json"), pods(r + "-pods-after.json")
    problems = []
    for k in PODS:
        b, a = before.get(k), after.get(k)
        if a is None:
            problems.append("%s: no pod after the reset" % k)
            continue
        if b is not None and (a["name"] == b["name"] or a["uid"] == b["uid"]):
            problems.append("%s: the same pod before and after (%s)" % (k, a["name"]))
        # ISO-8601 UTC strings of one format compare correctly as text
        if not a["startTime"] or a["startTime"] < start:
            problems.append("%s: pod started %s, before the reset %s" % (k, a["startTime"], start))
        if not a["containerStartedAt"] or any(not t or t < start for t in a["containerStartedAt"]):
            problems.append("%s: a container started before the reset: %r" % (k, a["containerStartedAt"]))
        if a["restarts"] != 0:
            problems.append("%s: restart count %d" % (k, a["restarts"]))
    out = {"resetStart": start, "before": before, "after": after, "fresh": not problems, "problems": problems}
    json.dump(out, open(r + ".json", "w"), indent=1)
    print(json.dumps({"fresh": out["fresh"], "problems": problems}))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

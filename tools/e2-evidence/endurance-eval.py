#!/usr/bin/env python3
"""endurance-eval.py <samples-dir> --check pods|agents|e2mgr|ns3|kpimon|rss|load [--expected-names F]

Evaluates the 60 s endurance samples written by endurance_sample (one
sample-NN/ directory each: t, pods.txt "<pod> <restarts>", agents.txt
"<nodeId> <restartCount> <running> <state> <subs> <indTx>", rss.txt docker stats,
e2mgr.txt CONNECTED names, ns3.alive, load.txt /proc/loadavg, kpimon.txt pod_info).

  pods     no ricplt pod restart count increased, no pod appeared or vanished (vs the first sample)
  agents   every agent RestartCount stays 0 and every container stays running
  e2mgr    every sample's CONNECTED set equals --expected-names exactly
  ns3      ns-3 alive at every sample
  kpimon   the kpimon pod's restart count never increased and the pod name never changed
  rss      informational: per-container RSS first/last/max (MiB); always exit 0
  load     informational: 1/5/15-minute load averages per sample; always exit 0
Exit 0 on pass, 1 on a problem; prints a per-sample table either way.
"""
import argparse
import glob
import os
import re
import sys


def samples(d):
    out = []
    for p in sorted(glob.glob(os.path.join(d, "sample-*"))):
        def rd(name, p=p):
            try:
                return open(os.path.join(p, name)).read()
            except OSError:
                return ""
        out.append({"dir": p, "t": int(rd("t").strip() or 0), "pods": rd("pods.txt"), "agents": rd("agents.txt"),
                    "rss": rd("rss.txt"), "e2mgr": rd("e2mgr.txt"), "ns3": rd("ns3.alive").strip(),
                    "load": rd("load.txt").strip(), "kpimon": rd("kpimon.txt").strip()})
    return out


def mib(s):
    m = re.match(r"([\d.]+)\s*([KMG]i?B)", s)
    if not m:
        return None
    return float(m.group(1)) * {"KB": 1 / 1024, "KiB": 1 / 1024, "MB": 1, "MiB": 1, "GB": 1024, "GiB": 1024}[m.group(2)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--check", required=True)
    ap.add_argument("--expected-names")
    a = ap.parse_args()
    ss = samples(a.dir)
    bad = []
    if not ss:
        sys.exit("no samples in %s" % a.dir)
    print("%d samples, %ds apart (first %d, last %d)" % (len(ss), (ss[-1]["t"] - ss[0]["t"]) // max(1, len(ss) - 1), ss[0]["t"], ss[-1]["t"]))
    if a.check == "pods":
        base = dict(l.split() for l in ss[0]["pods"].splitlines() if l.strip())
        print("baseline: %d ricplt pods, total restarts %d" % (len(base), sum(int(v) for v in base.values())))
        for i, s in enumerate(ss):
            cur = dict(l.split() for l in s["pods"].splitlines() if l.strip())
            if set(cur) != set(base):
                bad.append("sample %d: pod set changed: +%s -%s" % (i, sorted(set(cur) - set(base)), sorted(set(base) - set(cur))))
            for k, v in cur.items():
                if k in base and int(v) > int(base[k]):
                    bad.append("sample %d: %s restarts %s -> %s" % (i, k, base[k], v))
    elif a.check == "agents":
        for i, s in enumerate(ss):
            rows = [l.split() for l in s["agents"].splitlines() if l.strip()]
            print("sample %d: %s" % (i, " ".join("n%s:rc%s:%s:%s" % (r[0], r[1], r[2], r[3]) for r in rows)))
            if not rows:
                bad.append("sample %d: no agent rows" % i)
            for r in rows:
                if r[1] != "0" or r[2] != "true":
                    bad.append("sample %d: node %s RestartCount %s running %s" % (i, r[0], r[1], r[2]))
    elif a.check == "e2mgr":
        want = sorted(x for x in open(a.expected_names).read().split() if x)
        for i, s in enumerate(ss):
            got = sorted(x for x in s["e2mgr"].split() if x)
            if got != want:
                bad.append("sample %d: CONNECTED %s != expected %s" % (i, got, want))
        print("expected %d names: %s" % (len(want), want))
    elif a.check == "ns3":
        dead = [i for i, s in enumerate(ss) if s["ns3"] != "1"]
        print("ns-3 alive in %d of %d samples" % (len(ss) - len(dead), len(ss)))
        bad += ["ns-3 not alive at sample %d" % i for i in dead]
    elif a.check == "kpimon":
        first = ss[0]["kpimon"].split()
        print("kpimon at first sample: %s" % ss[0]["kpimon"])
        for i, s in enumerate(ss):
            cur = s["kpimon"].split()
            if len(cur) < 4 or len(first) < 4:
                bad.append("sample %d: kpimon pod info unreadable: %r" % (i, s["kpimon"]))
            elif cur[0] != first[0] or int(cur[3]) > int(first[3]):
                bad.append("sample %d: kpimon %s restarts %s (first %s restarts %s)" % (i, cur[0], cur[3], first[0], first[3]))
    elif a.check == "rss":
        series = {}
        for s in ss:
            for l in s["rss"].splitlines():
                p = l.split(" ", 1)
                if len(p) == 2 and mib(p[1]) is not None:
                    series.setdefault(p[0], []).append(mib(p[1]))
        for k, v in sorted(series.items()):
            print("%s RSS MiB first %.1f last %.1f max %.1f (%d samples)" % (k, v[0], v[-1], max(v), len(v)))
    elif a.check == "load":
        for i, s in enumerate(ss):
            print("sample %d load %s" % (i, " ".join(s["load"].split()[:3])))
        print("max 1-min load %.2f" % max(float(s["load"].split()[0]) for s in ss if s["load"]))
    for b in bad:
        print("PROBLEM: " + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""r3p-predictor.py: the R3′ harness predictor (formula persistence-window-sum-v1 of r3p-scenario.json).

It reads only a window file that check-n6-influx-window.py certified (integers from Influx, never a second
read): {"T", "imsi", "cells": {"<node>": {"<seq>": dl}}, "membership": {"<imsi>": node}, "pass": true}.
Per gNB cell the answer is the sum of DRB.PdcpSduVolumeDL over [T-15, T]; UL is 0; the serving cell (the
gNB listing the IMSI at T) comes first, then the others by ascending nodeId; keys uppercase "%08X%02X".
The decision mirrors the TS xApp (hand over iff 100 x best other > (100 + threshold) x serving).

  r3p-predictor.py answer SCENARIO WINDOW OUT [--records FILE] [--expect handover|none]
        the 30002 answer {"predictions": {"<imsi>": [answer]}} for the stub; a record (no wall time) appended to
        --records; with --expect the mirrored decision must equal it (exit 1: "observations differ")
  r3p-predictor.py replay SCENARIO WINDOW [--swap]   decision on a window, --swap exchanges the two gNB cells' DL
  r3p-predictor.py lint SCENARIO                     the pre-registration is self-consistent (non-empty domain)
  r3p-predictor.py --self-test
"""
import json
import sys

INT_MAX = 2147483647


def load(p):
    return json.load(open(p))


def domain(sc):
    lo = sc["domain"]["rampGuard"] + sc["window"]["length"] - 1
    hi = sc["config"]["samples"] - 1 - sc["domain"]["tailGuard"]
    return lo, hi


def window_seqs(sc, t, clip=False):
    first = t - sc["window"]["length"] + 1
    return list(range(max(0, first) if clip else first, t + 1))


def answer(sc, win, imsi):
    """[[key, [dl, 0]], ...] serving first; raises ValueError when the window cannot support an answer."""
    t, cells = win["T"], win["cells"]
    serving = win["membership"].get(str(imsi))
    gnbs = sorted(int(n) for n in sc["cells"])
    if serving is None or int(serving) not in gnbs:
        raise ValueError("imsi %s has no serving gNB cell at seq %d" % (imsi, t))
    seqs = window_seqs(sc, t, clip=win.get("clipped", False))
    out = []
    for n in [int(serving)] + [g for g in gnbs if g != int(serving)]:
        col = cells.get(str(n), {})
        vals = [col.get(str(s)) for s in seqs]
        if any(type(v) is not int for v in vals):
            raise ValueError("cell %d: window [%d, %d] is not complete integers" % (n, seqs[0], t))
        dl = sum(vals)
        if not 0 <= dl <= INT_MAX:
            raise ValueError("cell %d: window sum %d outside 0..2^31-1" % (n, dl))
        out.append([sc["cells"][str(n)], [dl, 0]])
    return out


def decide(sc, ans):
    """("handover", target key) or ("none", None): the TS xApp's rule on integers."""
    serving = ans[0][1][0]
    best_key, best = ans[0][0], serving
    for key, (dl, _) in ans[1:]:
        if best < dl:  # strict, as the TS xApp
            best_key, best = key, dl
    th = sc["threshold"]
    if best_key != ans[0][0] and 100 * best > (100 + th) * serving:
        return "handover", best_key
    return "none", None


def eligibility(ans):
    """"handover", "none" or "margin" (the TS xApp compares with a float threshold: keep a band around it)."""
    serving, best = ans[0][1][0], max(dl for _, (dl, _) in ans[1:])
    if 20 * best >= 23 * serving:
        return "handover"
    if 20 * best <= 21 * serving:
        return "none"
    return "margin"


def swapped(win):
    w = json.loads(json.dumps(win))
    w["cells"]["2"], w["cells"]["3"] = win["cells"].get("3", {}), win["cells"].get("2", {})
    return w


def lint(sc):
    problems = []
    lo, hi = domain(sc)
    if lo > hi:
        problems.append("empty domain [%d, %d]" % (lo, hi))
    if not sc["imsis"]:
        problems.append("no IMSIs")
    for k in ("n1", "h1"):
        st = sc["scheduleTemplate"][k]
        if not lo <= st["step"] <= st["step"] + st["slot"] <= hi:
            problems.append("%s slot [%d, %d] outside the domain [%d, %d]" % (k, st["step"], st["step"] + st["slot"], lo, hi))
    m1 = sc["scheduleTemplate"]["m1"]
    h1 = sc["scheduleTemplate"]["h1"]
    if h1["step"] + h1["slot"] + m1["offset"] + m1["slot"] > hi:
        problems.append("m1's latest step is past the domain end %d" % hi)
    if m1["offset"] < sc["window"]["length"]:
        problems.append("m1's offset %d is inside the window after h1" % m1["offset"])
    for n, key in sc["cells"].items():
        if key != "%08X%02X" % (int(n), int(n)):
            problems.append("cell %s key %r is not the uppercase gNB key" % (n, key))
    if sc["formula"]["id"] != "persistence-window-sum-v1" or sc["counter"]["influxType"] != "long":
        problems.append("formula or counter type changed")
    return problems


def cmd_answer(a):
    sc, win, out = load(a[0]), load(a[1]), a[2]
    if not win.get("pass"):
        print("the window is not certified by N6")
        return 1
    imsi = win["imsi"]
    ans = answer(sc, win, imsi)
    dec, key = decide(sc, ans)
    rec = {"T": win["T"], "imsi": imsi, "answer": ans, "decision": dec, "target": key, "eligibility": eligibility(ans),
           "formula": sc["formula"]["id"]}
    json.dump({"predictions": {str(imsi): [ans]}}, open(out, "w"))
    if "--records" in a:
        with open(a[a.index("--records") + 1], "a") as f:
            f.write(json.dumps(rec, sort_keys=True) + "\n")
    print(json.dumps(rec, sort_keys=True))
    want = a[a.index("--expect") + 1] if "--expect" in a else None
    if want and want != dec:
        print("observations differ from the dry run: decision %s, scheduled %s" % (dec, want))
        return 1
    return 0


def cmd_replay(a):
    sc, win = load(a[0]), load(a[1])
    if "--swap" in a:
        win = swapped(win)
    ans = answer(sc, win, win["imsi"])
    dec, key = decide(sc, ans)
    print(json.dumps({"T": win["T"], "imsi": win["imsi"], "swap": "--swap" in a, "answer": ans, "decision": dec,
                      "target": key}, sort_keys=True))
    return 0


def self_test():
    import os
    sc = load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "r3p-scenario.json"))
    cells = {"2": {str(s): 8371 for s in range(100)}, "3": {str(s): 4186 for s in range(100)}}
    mem = {"1": 3, "2": 3, "3": 2, "4": 2, "5": 2, "6": 2}
    win = {"T": 30, "imsi": 1, "cells": cells, "membership": mem, "pass": True}
    bad = []
    a1 = answer(sc, win, 1)
    if a1 != [["0000000303", [66976, 0]], ["0000000202", [133936, 0]]] or decide(sc, a1) != ("handover", "0000000202"):
        bad.append("IMSI 1 on cell 3 hands over to cell 2: %r %r" % (a1, decide(sc, a1)))
    a3 = answer(sc, win, 3)
    if decide(sc, a3) != ("none", None) or eligibility(a3) != "none":
        bad.append("IMSI 3 on cell 2 stays")
    if decide(sc, answer(sc, swapped(win), 1))[0] != "none" or decide(sc, answer(sc, swapped(win), 3))[0] != "handover":
        bad.append("the swap flips both decisions")
    edge = {"T": 30, "imsi": 1, "cells": {"2": {str(s): 110 for s in range(100)}, "3": {str(s): 100 for s in range(100)}},
            "membership": mem}
    if decide(sc, answer(sc, edge, 1))[0] != "none" or eligibility(answer(sc, edge, 1)) != "margin":
        bad.append("exactly +10 % is no handover and lies in the margin band")
    hole = json.loads(json.dumps(win))
    del hole["cells"]["3"]["20"]
    for name, w, imsi in (("a missing seq", hole, 1), ("no serving cell", dict(win, membership={}), 1)):
        try:
            answer(sc, w, imsi)
            bad.append(name + " gave an answer")
        except ValueError:
            pass
    flt = json.loads(json.dumps(win))
    flt["cells"]["2"]["25"] = 8371.0
    try:
        answer(sc, flt, 1)
        bad.append("a float value gave an answer")
    except ValueError:
        pass
    if lint(sc):
        bad.append("the committed scenario lints: %r" % lint(sc))
    if not lint(dict(sc, domain={"rampGuard": 50, "tailGuard": 50})):
        bad.append("an empty domain passed the lint")
    for b in bad:
        print("FAIL " + b)
    print("r3p predictor self-test: %s" % ("ok" if not bad else "%d failure(s)" % len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    av = sys.argv[1:]
    if av == ["--self-test"]:
        sys.exit(self_test())
    if av[:1] == ["lint"] and len(av) == 2:
        p = lint(load(av[1]))
        print(json.dumps({"problems": p, "domain": list(domain(load(av[1]))), "pass": not p}))
        sys.exit(1 if p else 0)
    cmds = {"answer": (cmd_answer, 3), "replay": (cmd_replay, 2)}
    if not av or av[0] not in cmds or len(av) < 1 + cmds[av[0]][1]:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(cmds[av[0]][0](av[1:]))

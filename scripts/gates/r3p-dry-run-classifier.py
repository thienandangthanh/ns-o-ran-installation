#!/usr/bin/env python3
"""r3p-dry-run-classifier.py: classify the R3′ dry run (phase-08b Step-1 amendment), first match wins.

  stage-a SCENARIO RD OUT   stage A (null control, RIC up, every T of the domain observed for every IMSI):
        invalid       the stage did not run clean (RD/r3p-stage.json), or any T lacks a passing N6 or a membership
                      for every IMSI (no candidate is ever dropped) -> Failure Protocol
        substitution4 a clean, complete domain with no "handover" decision at all
        T3            a handover exists but n1 or h1 cannot be formed by the template (e.g. handovers only in the
                      margin band, or no none-eligible IMSI in n1's slot)
        formed        n1 and h1 chosen; stage B runs next with h1's control injected
  stage-b SCENARIO STAGE_A_OUT RD SCHEDULE_OUT OUT   stage B (h1 injected, observed from h1 + window length):
        invalid as above; T3 when h1's IMSI has no eligible decision in m1's slot; else the schedule
        (n1, h1, m1 with their expected answers) is written to SCHEDULE_OUT
  --self-test
Exit 0 for formed (stage A) or a written schedule (stage B), 4 for substitution4, 3 for T3, 1 for invalid.
"""
import hashlib
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("r3p_predictor", os.path.join(HERE, "r3p-predictor.py"))
P = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(P)
RC = {"formed": 0, "schedule": 0, "substitution4": 4, "T3": 3, "invalid": 1}


def load_stage(rd, ts):
    """{T: (n6 pass, window or None)} and the stage record."""
    out = {}
    for t in ts:
        n6, win = os.path.join(rd, "r3p", "n6-%d.json" % t), os.path.join(rd, "r3p", "window-%d.json" % t)
        ok = os.path.exists(n6) and json.load(open(n6)).get("pass") is True
        out[t] = (ok, json.load(open(win)) if os.path.exists(win) else None)
    st = os.path.join(rd, "r3p-stage.json")
    return out, (json.load(open(st)) if os.path.exists(st) else {"clean": False, "why": "no stage record"})


def judge(sc, wins, stage, imsis):
    """(problems, {(T, imsi): (decision, key, eligibility, answer)})."""
    probs = [] if stage.get("clean") else ["stage not clean: %s" % stage.get("why")]
    cand = {}
    for t, (ok, win) in sorted(wins.items()):
        if not ok or win is None:
            probs.append("seq %d: N6 failed or no window" % t)
            continue
        for i in imsis:
            try:
                ans = P.answer(sc, win, i)
            except ValueError as ex:
                probs.append("seq %d imsi %d: %s" % (t, i, ex))
                continue
            dec, key = P.decide(sc, ans)
            cand[(t, i)] = (dec, key, P.eligibility(ans), ans)
    return probs, cand


def pick(cand, lo, hi, imsis, want):
    for t in range(lo, hi + 1):
        for i in sorted(imsis):
            c = cand.get((t, i))
            if c and c[0] == want and c[2] == want:
                return t, i, c
    return None


def trig(sc, t, i, c, kind):
    node = {v: int(k) for k, v in sc["cells"].items()}.get(c[1])
    d = {"step": t, "imsi": i, "kind": kind, "decision": c[0], "expectedAnswer": c[3]}
    if c[0] == "handover":
        d.update({"via": node, "key": c[1], "targetCell": node, "expect": "applied"})
    return d


def stage_a(sc, wins, stage):
    lo, hi = P.domain(sc)
    probs, cand = judge(sc, wins, stage, sc["imsis"])
    if probs or set(wins) != set(range(lo, hi + 1)):
        return {"class": "invalid", "problems": probs[:20] or ["domain not fully observed"]}
    if not any(c[0] == "handover" for c in cand.values()):
        return {"class": "substitution4", "candidates": len(cand), "handovers": 0}
    tpl = sc["scheduleTemplate"]
    n1 = pick(cand, tpl["n1"]["step"], tpl["n1"]["step"] + tpl["n1"]["slot"], sc["imsis"], "none")
    h1 = pick(cand, tpl["h1"]["step"], tpl["h1"]["step"] + tpl["h1"]["slot"], sc["imsis"], "handover")
    counts = {k: sum(1 for c in cand.values() if (c[0], c[2]) == k) for k in
              [("handover", "handover"), ("handover", "margin"), ("none", "none"), ("none", "margin")]}
    summary = {"candidates": len(cand), "decisionEligibility": {"%s/%s" % k: v for k, v in counts.items()}}
    if not n1 or not h1:
        return dict(summary, **{"class": "T3", "problems": ["n1 not formable" if not n1 else "h1 not formable"]})
    return dict(summary, **{"class": "formed", "n1": trig(sc, *n1, "negative"), "h1": trig(sc, *h1, "positive")})


def stage_b(sc, a, wins, stage):
    h1, n1 = a["h1"], a["n1"]
    m = sc["scheduleTemplate"]["m1"]
    lo, hi = h1["step"] + sc["window"]["length"], P.domain(sc)[1]
    probs, cand = judge(sc, wins, stage, [h1["imsi"]])
    if probs or set(wins) != set(range(lo, hi + 1)):
        return {"class": "invalid", "problems": probs[:20] or ["stage B domain not fully observed"]}, None
    first = h1["step"] + m["offset"]
    for t in range(first, first + m["slot"] + 1):
        c = cand.get((t, h1["imsi"]))
        if c and c[0] == c[2]:
            m1 = trig(sc, t, h1["imsi"], c, "positive" if c[0] == "handover" else "negative")
            return {"class": "schedule", "m1": m1}, [n1, h1, m1]
    return {"class": "T3", "problems": ["m1: imsi %d has no eligible decision in [%d, %d]" % (h1["imsi"], first, first + m["slot"])]}, None


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def main(av):
    sc = json.load(open(av[1]))
    if av[0] == "stage-a":
        lo, hi = P.domain(sc)
        wins, stage = load_stage(av[2], range(lo, hi + 1))
        out = dict(stage_a(sc, wins, stage), stageDir=av[2], scenarioSha256=sha(av[1]))
        json.dump(out, open(av[3], "w"), indent=1, sort_keys=True)
    else:
        a = json.load(open(av[2]))
        lo = a["h1"]["step"] + sc["window"]["length"]
        wins, stage = load_stage(av[3], range(lo, P.domain(sc)[1] + 1))
        out, trigs = stage_b(sc, a, wins, stage)
        out.update(stageADir=a["stageDir"], stageBDir=av[3], scenarioSha256=sha(av[1]))
        if trigs:
            json.dump({"scenarioSha256": sha(av[1]), "stageADir": a["stageDir"], "stageBDir": av[3],
                       "triggers": sorted(trigs, key=lambda x: x["step"])}, open(av[4], "w"), indent=1, sort_keys=True)
        json.dump(out, open(av[5], "w"), indent=1, sort_keys=True)
    print(json.dumps({k: out[k] for k in out if k in ("class", "problems", "n1", "h1", "m1")}))
    return RC[out["class"]]


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        _fx = importlib.util.spec_from_file_location("r3p_dry_run_fixtures", os.path.join(HERE, "r3p-dry-run-fixtures.py"))
        FX = importlib.util.module_from_spec(_fx)
        _fx.loader.exec_module(FX)
        sys.exit(FX.self_test(sys.modules[__name__], P))
    if not sys.argv[1:] or (sys.argv[1] == "stage-a" and len(sys.argv) != 5) or (sys.argv[1] == "stage-b" and len(sys.argv) != 7) \
            or sys.argv[1] not in ("stage-a", "stage-b"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

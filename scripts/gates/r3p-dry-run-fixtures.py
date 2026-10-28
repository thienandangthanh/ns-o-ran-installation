"""r3p-dry-run-fixtures.py: synthetic V9a fixtures for r3p-dry-run-classifier.py --self-test (no real data).

Stage A windows over the domain with constant per-cell DL; stage B after IMSI 1 moved from cell 3 to cell 2.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
START = {"1": 3, "2": 3, "3": 2, "4": 2, "5": 2, "6": 2}


def windows(ts, dl2, dl3, mem=START, fail=()):
    cells = {"2": {str(s): dl2 for s in range(100)}, "3": {str(s): dl3 for s in range(100)}}
    return {t: (t not in fail, None if t in fail else {"T": t, "imsi": None, "cells": cells, "membership": dict(mem), "pass": True})
            for t in ts}


def self_test(C, P):
    sc = json.load(open(os.path.join(HERE, "r3p-scenario.json")))
    lo, hi = P.domain(sc)
    clean = {"clean": True}
    dom = range(lo, hi + 1)
    bad = []

    def expect(name, got, want):
        if got.get("class") != want:
            bad.append("%s: %s, want %s (%s)" % (name, got.get("class"), want, got.get("problems")))
        else:
            print("ok   " + name)

    a = C.stage_a(sc, windows(dom, 8371, 4186), clean)
    expect("happy path: n1 and h1 formed", a, "formed")
    if a.get("class") == "formed" and ((a["n1"]["step"], a["n1"]["imsi"]) != (20, 3) or
                                       (a["h1"]["step"], a["h1"]["imsi"], a["h1"]["key"], a["h1"]["via"]) != (30, 1, "0000000202", 2)):
        bad.append("happy path chose n1 %r h1 %r" % (a["n1"], a["h1"]))
    expect("a missing row inside the only handover-producing windows: invalid", C.stage_a(sc, windows(dom, 8371, 4186, fail=(30,)), clean), "invalid")
    expect("an unclean stage: invalid", C.stage_a(sc, windows(dom, 8371, 4186), {"clean": False, "why": "ns-3 exit 1"}), "invalid")
    expect("a domain not fully observed: invalid", C.stage_a(sc, windows(range(lo, hi), 8371, 4186), clean), "invalid")
    expect("a complete domain with no handover: substitution 4", C.stage_a(sc, windows(dom, 5000, 5000), clean), "substitution4")
    every = {k: 3 for k in START}
    expect("every IMSI hands over in n1's slot: T3", C.stage_a(sc, windows(dom, 8371, 4186, mem=every), clean), "T3")
    expect("handovers only in the margin band: T3", C.stage_a(sc, windows(dom, 112, 100), clean), "T3")
    if a.get("class") == "formed":
        moved = dict(START, **{"1": 2})
        bdom = range(a["h1"]["step"] + sc["window"]["length"], hi + 1)
        b, trigs = C.stage_b(sc, a, windows(bdom, 10464, 2093, mem=moved), clean)
        expect("stage B happy path: schedule n1, h1, m1", b, "schedule")
        if b.get("class") == "schedule" and ((b["m1"]["step"], b["m1"]["decision"]) != (50, "none") or len(trigs) != 3):
            bad.append("stage B chose m1 %r" % b["m1"])
        expect("stage B: m1 only in the margin band: T3", C.stage_b(sc, a, windows(bdom, 100, 108, mem=moved), clean)[0], "T3")
        expect("stage B: an N6 failure: invalid", C.stage_b(sc, a, windows(bdom, 10464, 2093, mem=moved, fail=(55,)), clean)[0], "invalid")
    if not P.lint(dict(sc, domain={"rampGuard": 50, "tailGuard": 50})):
        bad.append("an empty domain is not refused by the lint")
    else:
        print("ok   an empty domain is refused by the lint")
    for b in bad:
        print("FAIL " + b)
    print("r3p dry-run classifier self-test: %s" % ("ok" if not bad else "%d failure(s)" % len(bad)))
    return 1 if bad else 0

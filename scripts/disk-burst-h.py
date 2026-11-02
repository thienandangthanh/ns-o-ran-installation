#!/usr/bin/env python3
"""Watchdog headroom h: the largest host-free drop over any window of at most WINDOW_S seconds.

Input: any number of free-series.tsv files written by scripts/vm/host-disk-watchdog.sh (one "<epoch>\t<free GiB>"
row per check). For every file, every pair of rows (a, b) with 0 < t_b - t_a <= WINDOW_S counts as a window; its
drop is free_a - free_b. The script prints one JSON object:
  {"windowS": 370, "limitGiB": 12, "worstGiB": <largest drop>, "file": <path>, "window": [t_a, t_b, free_a, free_b],
   "perFile": [{"file": ..., "worstGiB": ..., "rows": ...}, ...]}
Exit 0 when worstGiB <= --limit, 2 when it is larger (the run then stops for a user ruling; h is never raised
silently), 1 on unreadable input. --self-test checks the window arithmetic on synthetic series.
"""
import argparse
import json
import sys

WINDOW_S = 370


def read_series(path):
    rows = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            parts = line.split()
            if not parts:
                continue
            if len(parts) != 2:
                raise ValueError("%s:%d: expected '<epoch> <free GiB>', got %r" % (path, n, line.rstrip()))
            rows.append((int(parts[0]), float(parts[1])))
    rows.sort()
    return rows


def worst_drop(rows, window_s):
    """Largest free_a - free_b over pairs with 0 < t_b - t_a <= window_s; (0.0, None) when no pair drops."""
    best, where = 0.0, None
    for i, (ta, fa) in enumerate(rows):
        for tb, fb in rows[i + 1:]:
            if tb - ta > window_s:
                break
            if tb > ta and fa - fb > best:
                best, where = fa - fb, [ta, tb, fa, fb]
    return best, where


def self_test():
    flat = [(t, 100.0) for t in range(0, 1000, 30)]
    assert worst_drop(flat, WINDOW_S) == (0.0, None)
    # a 10 GiB fall spread over 360 s is inside one window; the same fall over 400 s is not whole in any window
    inside = [(0, 100.0), (180, 95.0), (360, 90.0), (390, 90.0)]
    assert worst_drop(inside, WINDOW_S)[0] == 10.0, worst_drop(inside, WINDOW_S)
    outside = [(0, 100.0), (200, 95.0), (400, 90.0)]
    assert worst_drop(outside, WINDOW_S)[0] == 5.0, worst_drop(outside, WINDOW_S)
    # a rise never counts as a burst
    assert worst_drop([(0, 50.0), (30, 60.0)], WINDOW_S) == (0.0, None)
    print("disk-burst-h self-test: ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("series", nargs="*")
    ap.add_argument("--window", type=int, default=WINDOW_S)
    ap.add_argument("--limit", type=float, default=12.0, help="registered h in GiB (R11)")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        self_test()
        return 0
    if not a.series:
        ap.error("no free-series.tsv given")
    out = {"windowS": a.window, "limitGiB": a.limit, "worstGiB": 0.0, "file": None, "window": None, "perFile": []}
    try:
        for p in a.series:
            rows = read_series(p)
            w, where = worst_drop(rows, a.window)
            out["perFile"].append({"file": p, "worstGiB": w, "rows": len(rows), "window": where})
            if where is not None and w > out["worstGiB"]:
                out["worstGiB"], out["file"], out["window"] = w, p, where
    except (OSError, ValueError) as e:
        print("disk-burst-h: %s" % e, file=sys.stderr)
        return 1
    print(json.dumps(out, indent=1))
    return 0 if out["worstGiB"] <= a.limit else 2


if __name__ == "__main__":
    sys.exit(main())

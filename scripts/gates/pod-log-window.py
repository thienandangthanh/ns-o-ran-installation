#!/usr/bin/env python3
"""pod-log-window.py: a pod's container logs from a start time, across kubelet log rotation.

`kubectl logs` serves only the newest file of a container, so a rotation inside a gate's
window silently drops the lines before it. This reads /var/log/pods/<ns>_<pod>_<uid>/<container>/
itself (root only: run it with sudo -n) and prints, like `kubectl logs --all-containers
--since-time`, the content of every record at or after the start time.

  pod-log-window.py DIR --since EPOCH [--until EPOCH] [--manifest FILE]
  pod-log-window.py --self-test

DIR is the pod directory; every container subdirectory in it is read. Files per container:
`N.log` (live), `N.log.<date>-<time>` (rotated), `N.log.<date>-<time>.gz` (compressed),
`*.tmp` (skipped). When both X and X.gz exist the kubelet is between compressing and
removing X; X.gz is read once. Records are CRI lines `<RFC3339Nano> <stream> <P|F> <text>`;
a newline is added after an F (full) record only, so a line split in P/F records is whole
again. Timestamps are parsed (containerd trims trailing zeros, so strings do not compare).

Fail closed: for each container, the oldest record read must be earlier than --since, else
exit 3 (the window start was rotated away; a container that logged nothing before --since
also fails, so use it on pods that log continuously). The file set is listed before and after
reading; if it changed (a rotation during the read) the read is repeated, up to 3 times,
then exit 2. The manifest (JSON; default stderr) lists the files read with bytes, first and
last timestamp and records in the window, plus rotationsInWindow, coverage and retries.
"""
import argparse
import datetime
import gzip
import json
import os
import re
import sys
import tempfile

NAME = re.compile(r"^(\d+)\.log(?:\.(\d{8}-\d{6}))?(\.gz)?$")


def parse_ts(text):
    """RFC3339 with up to 9 fractional digits -> epoch seconds (float, ns precision lost)."""
    m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d+))?(Z|[+-]\d\d:\d\d)$", text)
    if not m:
        raise ValueError("bad timestamp %r" % text)
    base = datetime.datetime.fromisoformat(m.group(1) + ("+00:00" if m.group(3) == "Z" else m.group(3)))
    return base.timestamp() + float("0." + (m.group(2) or "0"))


def list_files(cdir):
    """[(restart, rotated-suffix or '~', name)] in read order, X.gz winning over its twin X."""
    names = [n for n in os.listdir(cdir) if NAME.match(n) and not n.endswith(".tmp")]
    gz = {n[:-3] for n in names if n.endswith(".gz")}
    out = []
    for n in names:
        if n in gz:
            continue  # twin of an X.gz: the kubelet is between compressing and removing X
        m = NAME.match(n)
        out.append((int(m.group(1)), m.group(2) or "~", n))
    return sorted(out)


def read_records(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split(" ", 3)
            if len(parts) < 3:
                continue
            yield parse_ts(parts[0]), parts[2], parts[3] if len(parts) > 3 else ""


def read_container(cdir, since, until):
    """(text, manifest entries) of one container; raises FileNotFoundError on a mid-read rotation."""
    entries, out, oldest = [], [], None
    for _restart, suffix, name in list_files(cdir):
        path = os.path.join(cdir, name)
        first = last = None
        n = size = 0
        for ts, flag, text in read_records(path):
            first = ts if first is None else first
            last = ts
            if since <= ts and (until is None or ts < until):
                out.append(text + ("\n" if flag == "F" else ""))
                n += 1
        size = os.path.getsize(path)
        if first is not None and (oldest is None or first < oldest):
            oldest = first
        entries.append({"file": name, "bytes": size, "first": first, "last": last, "recordsInWindow": n,
                        "rotatedAfterStart": suffix != "~" and _suffix_epoch(suffix) >= since})
    return "".join(out), entries, oldest


def _suffix_epoch(suffix):
    return datetime.datetime.strptime(suffix, "%Y%m%d-%H%M%S").replace(tzinfo=datetime.timezone.utc).timestamp()


def window(pod_dir, since, until=None):
    """-> (text, manifest, exit code)."""
    for attempt in range(4):
        before = {c: list_files(os.path.join(pod_dir, c)) for c in sorted(os.listdir(pod_dir))}
        text, containers, covered = [], {}, True
        try:
            for c in before:
                t, entries, oldest = read_container(os.path.join(pod_dir, c), since, until)
                text.append(t)
                containers[c] = entries
                # fail closed: kpimon-style pods log every second, so the oldest record read
                # predates the window unless the file holding the window start was rotated away
                if oldest is None or oldest >= since:
                    covered = False
        except FileNotFoundError:
            continue
        after = {c: list_files(os.path.join(pod_dir, c)) for c in sorted(os.listdir(pod_dir))}
        if before == after:
            rot = sum(1 for es in containers.values() for e in es if e["rotatedAfterStart"])
            manifest = {"podDir": pod_dir, "since": since, "until": until, "containers": containers,
                        "rotationsInWindow": rot, "coverage": covered, "retries": attempt}
            return "".join(text), manifest, (0 if covered else 3)
    return "", {"podDir": pod_dir, "error": "file set kept changing while reading", "retries": 3}, 2


def self_test():
    """Fixtures built at run time: rotation, a P/F split, a stderr fragment, an X/X.gz twin, an older instance."""
    ok = True
    with tempfile.TemporaryDirectory() as d:
        c = os.path.join(d, "kpimon-go")
        os.makedirs(c)

        def rec(sec, flag, text, stream="stdout"):
            return "2026-10-22T19:%02d:%02d.5Z %s %s %s\n" % (sec // 60, sec % 60, stream, flag, text)
        since = datetime.datetime(2026, 10, 22, 19, 33, 0, tzinfo=datetime.timezone.utc).timestamp()

        def at(sec):  # seconds after 19:30:00 -> record minute/second
            return 30 * 60 + sec
        old = "".join(rec(at(i), "F", "old %d" % i) for i in range(0, 120, 60))                      # before since
        rot = "".join(rec(at(190 + i), "F", "RIC Indication message from a") for i in range(3))        # in window
        rot += rec(at(195), "P", "RIC Indic") + rec(at(195), "F", "ation message from b")             # split marker
        live = rec(at(200), "F", "x") + rec(at(201), "F", "RIC Indication message from c")
        live += rec(at(203), "P", "\\nheader RC_WM", "stderr") + rec(at(203), "F", "ORE tail", "stderr")
        with open(os.path.join(c, "5.log"), "w") as f:
            f.write(rec(at(0), "F", "older instance RIC Indication message from z"))
        with gzip.open(os.path.join(c, "6.log.20261022-193400.gz"), "wt") as f:
            f.write(old + rot)
        with open(os.path.join(c, "6.log.20261022-193400"), "w") as f:   # twin, must not double count
            f.write(old + rot)
        with open(os.path.join(c, "6.log"), "w") as f:
            f.write(live)
        text, man, rc = window(d, since)
        text = text.replace("\\n", "\n")
        n = text.count("RIC Indication message from")
        ok &= rc == 0 and n == 5 and text.count("header RC_WMORE") == 1 and man["rotationsInWindow"] == 1
        print("self-test rotation: rc %d, indications %d (want 5), WMORE %d (want 1), rotations %d (want 1)" % (
            rc, n, text.count("header RC_WMORE"), man["rotationsInWindow"]))
        # window start older than anything on disk, container's first file gone -> exit 3
        os.remove(os.path.join(c, "5.log"))
        text, man, rc = window(d, since - 3600)
        ok &= rc == 3
        print("self-test uncovered start: rc %d (want 3)" % rc)
    print("pod-log-window self-test:", "ok" if ok else "FAIL")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--since", type=float)
    ap.add_argument("--until", type=float)
    ap.add_argument("--manifest")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.dir or a.since is None:
        ap.error("DIR and --since are required")
    text, manifest, rc = window(a.dir, a.since, a.until)
    sys.stdout.write(text)
    msg = json.dumps(manifest, indent=1)
    if a.manifest:
        with open(a.manifest, "w") as f:
            f.write(msg + "\n")
    else:
        print(msg, file=sys.stderr)
    if rc == 3:
        print("pod-log-window: window start not covered: the rotated file holding it is gone", file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())

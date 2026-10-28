#!/usr/bin/env python3
"""r3p-prepare.py: the pacer "prepare" command of an R3′ step (runs after `steps T`, before the trigger's t0).

  r3p-prepare.py observe SCENARIO T RD
        dry run: N6 for every scenario IMSI at T; the certified window goes to RD/r3p/window-T.json
  r3p-prepare.py trigger SCENARIO T IMSI EXPECT RD STUB_URL
        N6 for IMSI at T, the predictor's answer from that certified window only (its decision must equal the
        scheduled EXPECT), then the stub log since the previous load saved (a load resets it) and the one-entry
        table PUT; the stub must report exactly that UE with one entry
  r3p-prepare.py fixed SCENARIO T IMSI ANSWER_JSON RD STUB_URL
        W calibration: N6 for IMSI at T (window clipped at seq 0), then the fixed answer PUT instead of the
        predictor's
Every file lands in RD/r3p/ (integers and stub exchanges only). Never sources the gate library: no evidence
dir is created and no secret is read; Influx is queried only by check-n6-influx-window.py inside the pod.
Exit 0 when every part passed.
"""
import json
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def run(*cmd):
    p = subprocess.run([sys.executable, "-I"] + list(cmd), capture_output=True, text=True)
    sys.stdout.write(p.stdout[-600:])
    return p.returncode


def n6(scen, t, who, rd, clip=False):
    d = os.path.join(rd, "r3p")
    win, ver = os.path.join(d, "window-%d.json" % t), os.path.join(d, "n6-%d.json" % t)
    who = ["--all"] if who is None else ["--imsi", str(who)]
    rc = run(os.path.join(HERE, "check-n6-influx-window.py"), scen, str(t), *who, os.path.join(rd, "trace"),
             os.path.join(rd, "trace", "e2-control-ledger.jsonl"), win, ver, *(["--clip"] if clip else []))
    return rc, win


def stub_load(rd, t, url, table, imsi):
    d = os.path.join(rd, "r3p")
    with urllib.request.urlopen(url + "/log", timeout=10) as r:
        open(os.path.join(d, "stub-log-before-%d.json" % t), "wb").write(r.read())
    req = urllib.request.Request(url + "/table", data=json.dumps(table).encode(), method="PUT")
    with urllib.request.urlopen(req, timeout=10) as r:
        got = json.loads(r.read())
    if got != {"ues": [str(imsi)], "entries": 1}:
        print("stub load at %d answered %r" % (t, got))
        return 1
    print("stub loaded for imsi %s at %d" % (imsi, t))
    return 0


def main(av):
    mode, scen, t = av[0], av[1], int(av[2])
    if mode == "observe":
        rd = av[3]
        os.makedirs(os.path.join(rd, "r3p"), exist_ok=True)
        return n6(scen, t, None, rd)[0]
    if mode == "trigger":
        imsi, expect, rd, url = int(av[3]), av[4], av[5], av[6]
        os.makedirs(os.path.join(rd, "r3p"), exist_ok=True)
        rc, win = n6(scen, t, imsi, rd)
        if rc:
            return rc
        ans = os.path.join(rd, "r3p", "answer-%d.json" % t)
        rc = run(os.path.join(HERE, "r3p-predictor.py"), "answer", scen, win, ans, "--records",
                 os.path.join(rd, "r3p", "predictor-records.jsonl"), "--expect", expect)
        if rc:
            return rc
        return stub_load(rd, t, url, json.load(open(ans)), imsi)
    if mode == "fixed":
        imsi, answer, rd, url = int(av[3]), json.loads(av[4]), av[5], av[6]
        os.makedirs(os.path.join(rd, "r3p"), exist_ok=True)
        rc, _ = n6(scen, t, imsi, rd, clip=True)
        if rc:
            return rc
        return stub_load(rd, t, url, {"predictions": {str(imsi): [answer]}}, imsi)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

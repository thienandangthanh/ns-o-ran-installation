#!/usr/bin/env python3
"""r3p-prepare.py: the pacer "prepare" command of an R3′ step (runs after `steps T`, before the trigger's t0).

  r3p-prepare.py observe SCENARIO T RD
        dry run: N6 for every scenario IMSI at T; the certified window goes to RD/r3p/window-T.json
  r3p-prepare.py trigger SCENARIO T IMSI EXPECT RD STUB_URL
        N6 for IMSI at T; U := the UE's KPM UE ID key (en-gNB-UEID: the gNB tag of IMSI's entry in ctx(n, T),
        n = the certified window's membership[IMSI], over the run's context lines with seq <= T), which must equal
        the ueIdAtT that N6 certified on Influx; the predictor's answer from that certified window only, keyed by U
        (its decision must equal the scheduled EXPECT); then the stub log since the previous load saved (a load
        resets it) and the one-entry table PUT; the stub must report exactly [U] with one entry. Only then are
        RD/r3p/trigger-ue-T.txt (U and a newline: the trigger's send-rmr.sh anomaly-from file) and
        trigger-ue-T.json {T, imsi, ueId, node} written
  r3p-prepare.py fixed SCENARIO T IMSI ANSWER_JSON RD STUB_URL
        W calibration: N6 for IMSI at T (window clipped at seq 0) and U as for trigger, then the fixed answer
        PUT keyed by U instead of the predictor's, and the same trigger-ue files
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


def _uecm():
    import importlib.util
    spec = importlib.util.spec_from_file_location("ue_context_map", os.path.join(HERE, "..", "..", "tools", "e2-evidence",
                                                                                 "ue-context-map.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


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


def ue_key(rd, t, imsi, win_path):
    """(U, node, None) for IMSI at T, or (None, None, problem): U from ctx(membership[imsi], T) equal to N6's ueIdAtT."""
    try:
        win = json.load(open(win_path))
        ver = json.load(open(os.path.join(rd, "r3p", "n6-%d.json" % t)))
        node = int(win["membership"][str(imsi)])
    except (OSError, ValueError, KeyError, TypeError) as ex:
        return None, None, "window or N6 verdict at %d unreadable: %s" % (t, ex)
    m = _uecm()
    cm = m.UeContextMap(os.path.join(rd, "trace"), max_seq=t)
    if cm.problems:
        return None, None, "UE context: %s" % "; ".join(cm.problems[:3])
    u = cm.ctx(node, t).get(imsi)
    if u is None:
        return None, None, "IMSI %d is not in ctx(%d, %d)" % (imsi, node, t)
    tag = m.gnb_tag(u["lteRnti"], u["mnCellId"])
    if cm.imsi_of(u["lteRnti"], u["mnCellId"]) != imsi:
        return None, None, "I(%s) is not IMSI %d" % (tag, imsi)
    got = (ver.get("ueIdAtT") or {}).get(str(imsi))
    if got != tag:
        return None, None, "the context key %s of IMSI %d at %d is not N6's ueIdAtT %r" % (tag, imsi, t, got)
    return tag, node, None


def write_trigger_ue(rd, t, imsi, u, node):
    d = os.path.join(rd, "r3p")
    json.dump({"T": t, "imsi": imsi, "ueId": u, "node": node}, open(os.path.join(d, "trigger-ue-%d.json" % t), "w"), sort_keys=True)
    with open(os.path.join(d, "trigger-ue-%d.txt" % t), "w") as f:
        f.write(u + "\n")


def stub_load(rd, t, url, table, ue):
    d = os.path.join(rd, "r3p")
    with urllib.request.urlopen(url + "/log", timeout=10) as r:
        open(os.path.join(d, "stub-log-before-%d.json" % t), "wb").write(r.read())
    req = urllib.request.Request(url + "/table", data=json.dumps(table).encode(), method="PUT")
    with urllib.request.urlopen(req, timeout=10) as r:
        got = json.loads(r.read())
    if got != {"ues": [ue], "entries": 1}:
        print("stub load at %d answered %r, want {'ues': [%r], 'entries': 1}" % (t, got, ue))
        return 1
    print("stub loaded for %s at %d" % (ue, t))
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
        u, node, why = ue_key(rd, t, imsi, win)
        if why:
            print(why)
            return 1
        ans = os.path.join(rd, "r3p", "answer-%d.json" % t)
        rc = run(os.path.join(HERE, "r3p-predictor.py"), "answer", scen, win, ans, "--ue-id", u, "--trace-dir",
                 os.path.join(rd, "trace"), "--records", os.path.join(rd, "r3p", "predictor-records.jsonl"), "--expect", expect)
        if rc:
            return rc
        rc = stub_load(rd, t, url, json.load(open(ans)), u)
        if not rc:
            write_trigger_ue(rd, t, imsi, u, node)
        return rc
    if mode == "fixed":
        imsi, answer, rd, url = int(av[3]), json.loads(av[4]), av[5], av[6]
        os.makedirs(os.path.join(rd, "r3p"), exist_ok=True)
        rc, win = n6(scen, t, imsi, rd, clip=True)
        if rc:
            return rc
        u, node, why = ue_key(rd, t, imsi, win)
        if why:
            print(why)
            return 1
        rc = stub_load(rd, t, url, {"predictions": {u: [answer]}}, u)
        if not rc:
            write_trigger_ue(rd, t, imsi, u, node)
        return rc
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

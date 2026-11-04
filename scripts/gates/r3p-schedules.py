#!/usr/bin/env python3
"""r3p-schedules.py: the pacer schedules of gate r3p (one per run: the prepare commands name the run dir).

  r3p-schedules.py live SCENARIO SCHEDULE RD STUB_URL SEND CTL_PORT
        per trigger of r3p-schedule.json: prepare = r3p-prepare.py trigger (N6, the UE's KPM UE ID key, predictor,
        stub load, RD/r3p/trigger-ue-<step>.txt), then the 30003 trigger `send-rmr.sh CTL_PORT anomaly-from` that
        file; a handover waits for one control within T_ctl, a none requires none within W
  r3p-schedules.py observe SCENARIO RD [--after-h1 STAGE_A_CLASS]
        dry run: a prepare-only observe entry (mayFail: recorded, judged by the classifier) at every T of the
        domain; with --after-h1 (stage B) h1's control injected at h1's step via the source en-gNB, its ueId the
        IPC form of h1's UE ID read from the run's context files at that step (a prepare: ue-id-prepare.py
        --context-only, the inject's ueIdFrom), and observation from h1 + window length
  r3p-schedules.py calibrate SCENARIO R2_SCENARIO RD STUB_URL SEND CTL_PORT
        W calibration: R2's calibration block, each trigger prepared by N6 (window clipped at 0), the UE's key and
        the fixed answer loaded instead of the predictor's; the same anomaly-from trigger
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREP = os.path.join(HERE, "r3p-prepare.py")
UEP = os.path.join(HERE, "ue-id-prepare.py")


def _mod(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def trigger_entry(prep_cmd, send, port, rd, step, positive, timeout):
    """The prepare writes RD/r3p/trigger-ue-<step>.txt only once every part passed; the trigger sends that key."""
    ue = os.path.join(rd, "r3p", "trigger-ue-%d.txt" % step)
    e = {"prepare": {"cmd": prep_cmd, "timeoutS": timeout}, "trigger": {"cmd": ["bash", send, port, "anomaly-from", ue]}}
    if positive:
        e["expect"] = 1
    else:
        e["expect"], e["absence"] = 0, True
    return e


def live(a):
    sc, sched, rd, url, send, port = json.load(open(a[0])), json.load(open(a[1])), a[2], a[3], a[4], a[5]
    steps = {}
    for t in sched["triggers"]:
        cmd = ["python3", "-I", PREP, "trigger", a[0], str(t["step"]), str(t["imsi"]), t["decision"], rd, url]
        if str(t["step"]) in steps:
            sys.exit("step %d has two triggers" % t["step"])
        steps[str(t["step"])] = trigger_entry(cmd, send, port, rd, t["step"], t["decision"] == "handover", sc["prepareTimeoutS"])
    return {"steps": steps, "late": []}


def observe(a):
    sc, rd = json.load(open(a[0])), a[1]
    lo, hi = _mod("r3p_predictor", "r3p-predictor.py").domain(sc)
    steps = {}
    if "--after-h1" in a:
        h1 = json.load(open(a[a.index("--after-h1") + 1]))["h1"]
        base = os.path.join(rd, "r3p", "stageb-ue-%d" % h1["step"])
        steps[str(h1["step"])] = {
            "prepare": {"cmd": ["python3", "-I", UEP, os.path.join(rd, "trace"), str(h1["step"]),
                                "%d=%s" % (h1["imsi"], base), "--context-only"], "timeoutS": sc["prepareTimeoutS"]},
            "inject": [{"nodeId": h1["via"], "ctlId": 1, "ueIdFrom": base + ".json",
                        "targetCellId": h1["targetCell"], "afterSeq": h1["step"]}]}
        lo = h1["step"] + sc["window"]["length"]
    for t in range(lo, hi + 1):
        steps[str(t)] = {"prepare": {"cmd": ["python3", "-I", PREP, "observe", a[0], str(t), rd],
                                     "timeoutS": sc["prepareTimeoutS"], "mayFail": True}}
    return {"steps": steps, "late": []}


def calibrate(a):
    sc, r2sc, rd, url, send, port = json.load(open(a[0])), json.load(open(a[1])), a[2], a[3], a[4], a[5]
    steps = {}
    for t in _mod("r2_checks", "r2-checks.py").triggers(r2sc, True):
        cmd = ["python3", "-I", PREP, "fixed", a[0], str(t["step"]), str(t["imsi"]), json.dumps(t["predictions"]), rd, url]
        steps[str(t["step"])] = trigger_entry(cmd, send, port, rd, t["step"], True, sc["prepareTimeoutS"])
    return {"steps": steps, "late": []}


if __name__ == "__main__":
    cmds = {"live": (live, 6), "observe": (observe, 2), "calibrate": (calibrate, 6)}
    av = sys.argv[1:]
    if not av or av[0] not in cmds or len(av) - 1 < cmds[av[0]][1]:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    print(json.dumps(cmds[av[0]][0](av[1:]), indent=1))

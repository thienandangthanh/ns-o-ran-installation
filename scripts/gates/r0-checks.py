#!/usr/bin/env python3
"""r0-checks.py: schedule building and ledger checks for gates r0 and r1.

  r0-checks.py schedule SCENARIO ENDPOINT [--forced-late | --calibrate | --fault-stop] [--rc-send PATH]
                        [--confirm CMD...]
        the pacer schedule template of the scenario (every path under the run dir is written @RUN@; `render` fills
        it in per run). Per step one "prepare" (ue-id-prepare.py on @RUN@/trace at that step) resolves every IMSI
        the step's controls name to its en-gNB-UEID key and confirms it in Influx, writing @RUN@/ue-id/s<step>-i<imsi>.txt;
        each control is one rc-send trigger (Style 5 action 3 via the control's node, --ue-from that file; a
        control that names a ueId instead of an IMSI goes as --en-gnb-ue-id, with no prepare), expecting one
        control at ns-3 (several controls in one step become a "triggers" list, sent in scenario order). A control
        with path "enb" (answered by the eNB's agent itself, ran-function-id-invalid) must be alone in its step and
        expects none within W ("absence"). --forced-late: only the forced-late control, sent after `go`
        (goBeforeTrigger); --calibrate: the ten calibration controls; --fault-stop: the scenario's faultStop
        controls plus its stopTrigger (its IMSI resolved by the first step's prepare), confirmed by CMD (the rest
        of the arguments)
  r0-checks.py render TEMPLATE RUN_DIR      the template with @RUN@ replaced by RUN_DIR
  r0-checks.py tctl PACER_SUMMARY [--steps N]
        T_ctl from a calibration run: needs a run that ended without an abort and exactly N (10) complete
        trigger steps (one control, trigger rc 0, slack recorded); L = the largest per-control latency
        (pacer wall time at controlRx minus the time just before the trigger started: an upper bound on
        trigger-to-read); T_ctl = max(30, ceil(20 x L)), rounded up
  r0-checks.py expect SCENARIO LEDGER [--forced-late | --fault-stop]
        every control's ledger line has the expected outcome/cause and afterSeq = step, found by (via, imsi, target);
        an unknownUe control by (via, imsi 0, target, afterSeq = step), refused unknownUe, its e2-pacing-log.jsonl
        record (the ledger's directory) carrying the control's UE: an IMSI's {mEnbUeX2apId = its lteRnti in
        e2-ue-context-1.jsonl at seq <= step, mnCellId 1}, or the control's own ueId, which no IMSI of the run may
        hold; an "agent:<cause>" control has no line at (via, step); lines = controls without "agent:". With
        --forced-late the late line's pacing record must also name the control's IMSI (I(ueId) = imsi).
  r0-checks.py d7 SCENARIO LEDGER RC_MULTISET
        D7 over the applied lines: every one via its source en-gNB (viaNodeId = sourceCell), via both gNBs, two
        IMSIs, both gNBs targets; >= 1 path "nonSourceGnb" control refused unknownUe with imsi 0; the path "enb"
        controls (>= 1) each answered on the wire by node 1 with a failure ran-function-id-invalid and no step
  r0-checks.py c4 RUN_DIR     the R1 C4 sort was exercised, not arrival order: in (b) (step 30, IMSI 2, both via its
        source 3) the refused inHandover line has the lower ctlId and the applied one the higher; in (c) ns-3
        received node 3's control before node 2's, the via-3 line is refused unknownUe with imsi 0 and the via-2
        line applied for IMSI 3
  r0-checks.py --self-test    c4 on fixtures/r1-c4-arrival-order (a ledger as if arrival order replaced the sort:
        must fail) and on its sort-order counterpart (must pass)
"""
import copy
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
UEP = os.path.join(HERE, "ue-id-prepare.py")
RUN = "@RUN@"


def _uecm():
    path = os.path.join(HERE, "..", "..", "tools", "e2-evidence", "ue-context-map.py")
    spec = importlib.util.spec_from_file_location("ue_context_map", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def load(p):
    return json.load(open(p))


def ledger_lines(p):
    return [json.loads(l) for l in open(p) if l.strip()][1:]


def ue_file(step, imsi):
    return "%s/ue-id/s%s-i%d" % (RUN, step, imsi)


def send_cmd(send, ep, c, step):
    if "ueId" in c:  # a UE ID no UE holds: sent as given, no Influx read
        u = c["ueId"]
        return ["bash", send, ep, str(c["via"]), "--en-gnb-ue-id", str(u["mEnbUeX2apId"]), "%05X" % u["mnCellId"], c["key"]]
    return ["bash", send, ep, str(c["via"]), "--ue-from", ue_file(step, c["imsi"]) + ".txt", c["key"]]


def cmd_schedule(a):
    sc, ep = load(a[0]), a[1]
    send = a[a.index("--rc-send") + 1] if "--rc-send" in a else "rc-send.sh"
    steps = {}
    todo = sc["calibration"] if "--calibrate" in a else (
        [dict(sc["forcedLate"], goBeforeTrigger=True)] if "--forced-late" in a else (
            sc["faultStop"]["controls"] if "--fault-stop" in a else sc["controls"]))
    st = sc["faultStop"].get("stopTrigger") if "--fault-stop" in a else None
    by_step = {}
    for c in todo:
        by_step.setdefault(str(c["step"]), []).append(c)
    first = min(by_step, key=int) if by_step else None
    for k, cs in by_step.items():
        cmds = [send_cmd(send, ep, c, k) for c in cs]
        enb = [c for c in cs if c.get("path") == "enb"]
        if enb and len(cs) != 1:
            sys.exit("step %s: a control the eNB's agent answers itself must be alone in its step" % k)
        if len(cs) == 1:
            e = {"trigger": {"cmd": cmds[0]}, "expect": 1}
            if enb:
                e["expect"], e["absence"] = 0, True
            if cs[0].get("goBeforeTrigger"):
                e["goBeforeTrigger"] = True
        else:  # several controls in one step: sent one at a time, in list order
            if any(c.get("goBeforeTrigger") for c in cs):
                sys.exit("step %s: goBeforeTrigger needs a single control" % k)
            e = {"triggers": [{"cmd": cmd, "expect": 1} for cmd in cmds]}
        imsis = sorted({c["imsi"] for c in cs if "imsi" in c} | ({st["imsi"]} if st and k == first else set()))
        if imsis:
            e["prepare"] = {"cmd": ["python3", "-I", UEP, RUN + "/trace", k] + ["%d=%s" % (i, ue_file(k, i)) for i in imsis],
                            "timeoutS": 30}
        steps[k] = e
    out = {"steps": steps, "late": []}
    if st:  # a control sent after the final barrier; endAck waits until the agent has forwarded it
        if first is None:
            sys.exit("a stopTrigger needs a control step whose prepare resolves its IMSI")
        confirm = a[a.index("--confirm") + 1:] if "--confirm" in a else []
        out["stopTrigger"] = {"cmd": send_cmd(send, ep, st, first), "confirm": confirm, "timeoutS": st.get("timeoutS", 6)}
    print(json.dumps(out, indent=1))
    return 0


def cmd_render(a):
    def fill(o):
        if isinstance(o, str):
            return o.replace(RUN, a[1])
        if isinstance(o, list):
            return [fill(x) for x in o]
        if isinstance(o, dict):
            return {k: fill(v) for k, v in o.items()}
        return o
    print(json.dumps(fill(load(a[0])), indent=1))
    return 0


def expect_problems(todo, lines, trace_dir, forced_late=False):
    """The `expect` predicate over a ledger; problems (empty = pass)."""
    m = _uecm()
    pacing = m.pacing_controls(trace_dir)
    problems = []

    def record_ue(x):
        recs = pacing.get((x["viaNodeId"], x["ctlId"]), [])
        return recs[0].get("ueId") if len(recs) == 1 else None
    for c in todo:
        exp = c["expect"]
        if exp.startswith("agent:"):
            at = [x for x in lines if x["viaNodeId"] == c["via"] and (x["afterSeq"] == c["step"] or x["rxSeq"] == c["step"])]
            if at:
                problems.append("control via %d at step %d (%s): %d ledger lines, want none" % (c["via"], c["step"], exp, len(at)))
            continue
        if exp == "unknownUe":
            hit = [x for x in lines if x["viaNodeId"] == c["via"] and x["imsi"] == 0 and x["targetCell"] == c["targetCell"]
                   and x["afterSeq"] == c["step"]]
            if len(hit) != 1:
                problems.append("unknownUe control %r: %d ledger lines (via, imsi 0, target, afterSeq)" % (c, len(hit)))
                continue
            x = hit[0]
            if (x["outcome"], x["cause"]) != ("refused", "unknownUe"):
                problems.append("control via %d step %d: %s/%s, expected refused unknownUe" % (c["via"], c["step"], x["outcome"], x["cause"]))
            got = record_ue(x)
            if "ueId" in c:
                held = m.UeContextMap(trace_dir).holds(c["ueId"]["mEnbUeX2apId"], c["ueId"]["mnCellId"])
                if got != c["ueId"] or held:
                    problems.append("control via %d step %d: pacing ueId %r (want %r), held by IMSIs %s (want none)" % (
                        c["via"], c["step"], got, c["ueId"], held))
            else:
                u = m.UeContextMap(trace_dir, max_seq=c["step"]).ctx(1, c["step"]).get(c["imsi"])
                want = {"mEnbUeX2apId": u["lteRnti"], "mnCellId": 1} if u else None
                if want is None or got != want:
                    problems.append("control via %d step %d: pacing ueId %r, IMSI %d's {lteRnti, MN cell 1} %r" % (
                        c["via"], c["step"], got, c["imsi"], want))
            continue
        hit = [x for x in lines if x["viaNodeId"] == c["via"] and x["imsi"] == c["imsi"] and x["targetCell"] == c["targetCell"]]
        if len(hit) != 1:
            problems.append("control %r: %d ledger lines" % (c, len(hit)))
            continue
        x = hit[0]
        got = "applied" if x["outcome"] == "applied" else x["cause"]
        if got != exp:
            problems.append("control via %d imsi %d -> %d: %s, expected %s" % (c["via"], c["imsi"], c["targetCell"], got, exp))
        if forced_late:
            if not (x["afterSeq"] == c["step"] and x["rxSeq"] > c["step"]):
                problems.append("forced late control: afterSeq %d rxSeq %d, expected afterSeq %d and a later barrier" % (x["afterSeq"], x["rxSeq"], c["step"]))
            ue = m.x2_of(record_ue(x))
            named = m.UeContextMap(trace_dir).imsi_of(*ue) if ue else None
            if named != c["imsi"]:
                problems.append("forced late control: its pacing record names IMSI %r (ueId %r), not %d" % (named, record_ue(x), c["imsi"]))
        elif x["afterSeq"] != c["step"]:
            problems.append("control via %d imsi %d: afterSeq %d != step %d" % (c["via"], c["imsi"], x["afterSeq"], c["step"]))
    n = sum(1 for c in todo if not c["expect"].startswith("agent:"))
    if len(lines) != n:
        problems.append("%d ledger lines for %d controls that reach ns-3" % (len(lines), n))
    return problems


def cmd_expect(a):
    sc = load(a[0])
    lines = ledger_lines(a[1])
    todo = [sc["forcedLate"]] if "--forced-late" in a else (
        sc["faultStop"]["controls"] if "--fault-stop" in a else sc["controls"])
    problems = expect_problems(todo, lines, os.path.dirname(os.path.abspath(a[1])), "--forced-late" in a)
    print(json.dumps({"problems": problems, "pass": not problems}, indent=1))
    return 0 if not problems else 1


def cmd_d7(a):
    sc, lines, ms = load(a[0]), ledger_lines(a[1]), load(a[2])
    ap = [x for x in lines if x["outcome"] == "applied"]
    non_src = [c for c in sc["controls"] if c.get("path") == "nonSourceGnb"]
    enb = [c for c in sc["controls"] if c.get("path") == "enb"]
    non_src_lines = [x for c in non_src for x in lines if x["viaNodeId"] == c["via"] and x["imsi"] == 0
                     and x["targetCell"] == c["targetCell"] and x["afterSeq"] == c["step"]
                     and (x["outcome"], x["cause"]) == ("refused", "unknownUe")]
    enb_wire = [m for m in ms if m["viaNode"] == 1 and m["answer"] == "failure" and m["cause"] == "ran-function-id-invalid"
                and m["step"] is None]
    # nodeId n (n >= 2) is the gNB serving cell n; node 1 is the eNB (MN)
    d = {"applied": len(ap), "viaSourceGnb": sum(1 for x in ap if x["viaNodeId"] == x["sourceCell"]),
         "viaGnbs": sorted({x["viaNodeId"] for x in ap}), "distinctImsis": len({x["imsi"] for x in ap}),
         "targetGnbs": sorted({x["targetCell"] for x in ap}), "nonSourceRefused": len(non_src_lines),
         "enbRefused": len(enb_wire), "enbControls": len(enb),
         "form": "via the source en-gNB (SN-initiated, E2SM-RC Style 5 action 3)"}
    print(json.dumps(d))
    ok = (ap and d["viaSourceGnb"] == len(ap) and {2, 3} <= set(d["viaGnbs"]) and d["distinctImsis"] >= 2
          and {2, 3} <= set(d["targetGnbs"]) and d["nonSourceRefused"] >= 1 and d["enbRefused"] >= 1
          and d["enbRefused"] == len(enb))
    return 0 if ok else 1


def c4_problems(rd):
    led = ledger_lines(os.path.join(rd, "trace", "e2-control-ledger.jsonl"))
    b = [x for x in led if x["rxSeq"] == 30 and x["imsi"] == 2]
    ref = [x for x in b if (x["outcome"], x["cause"]) == ("refused", "inHandover")]
    app = [x for x in b if x["outcome"] == "applied"]
    summ = load(os.path.join(rd, "pacer", "pacer-summary.json"))
    order40 = [v for v, _ in summ["steps"]["40"]["rxOrder"]]
    c = [x for x in led if x["rxSeq"] == 40]
    c3 = [x for x in c if x["viaNodeId"] == 3]
    c2 = [x for x in c if x["viaNodeId"] == 2]
    ok_b = (len(b) == 2 and len(ref) == 1 and len(app) == 1 and ref[0]["ctlId"] < app[0]["ctlId"]
            and ref[0]["viaNodeId"] == app[0]["viaNodeId"] == 3)
    ok_c = (order40 == [3, 2] and len(c3) == 1 and (c3[0]["outcome"], c3[0]["cause"], c3[0]["imsi"]) == ("refused", "unknownUe", 0)
            and len(c2) == 1 and (c2[0]["outcome"], c2[0]["imsi"]) == ("applied", 3))
    print("step 30:", [(x["viaNodeId"], x["ctlId"], x["targetCell"], x["outcome"], x["cause"]) for x in b],
          "step 40 rx order:", order40, "step 40:", [(x["viaNodeId"], x["imsi"], x["outcome"], x["cause"]) for x in c])
    return ([] if ok_b else ["(b): no refused inHandover line with the lower ctlId beside the applied one, both via 3"]) + (
        [] if ok_c else ["(c): rx order, non-source unknownUe line or source applied line not as expected"])


def cmd_c4(a):
    p = c4_problems(a[0])
    print(json.dumps({"problems": p, "pass": not p}))
    return 0 if not p else 1


def self_test():
    import tempfile
    import shutil
    fx = os.path.join(HERE, "fixtures", "r1-c4-arrival-order")
    bad = []
    if not c4_problems(fx):
        bad.append("c4 passed the arrival-order ledger")
    else:
        print("ok   c4 fails the arrival-order fixture")
    with tempfile.TemporaryDirectory() as d:
        shutil.copytree(fx, d, dirs_exist_ok=True)
        lp = os.path.join(d, "trace", "e2-control-ledger.jsonl")
        rows = [json.loads(l) for l in open(lp) if l.strip()]
        for x in rows[1:]:  # the C4 order: target 2 (ctl 2) applied first, target 3 (ctl 1) then in handover
            if x.get("rxSeq") == 30 and x.get("imsi") == 2 and x.get("targetCell") == 3:
                x.update(outcome="refused", cause="inHandover")
        with open(lp, "w") as f:
            f.write("".join(json.dumps(x) + "\n" for x in rows))
        if c4_problems(d):
            bad.append("c4 failed the sort-order counterpart: %s" % c4_problems(d))
        else:
            print("ok   c4 passes the sort-order counterpart")
        summ = load(os.path.join(d, "pacer", "pacer-summary.json"))
        s2 = copy.deepcopy(summ)
        s2["steps"]["40"]["rxOrder"] = [[2, 3], [3, 3]]
        json.dump(s2, open(os.path.join(d, "pacer", "pacer-summary.json"), "w"))
        if not c4_problems(d):
            bad.append("c4 passed with node 2's control received first")
        else:
            print("ok   c4 fails when node 2's control arrived first")
    for b in bad:
        print("FAIL " + b)
    print("r0-checks self-test: %s" % ("ok" if not bad else "%d failure(s)" % len(bad)))
    return 1 if bad else 0


def cmd_tctl(a):
    import math
    summary = load(a[0])
    want = int(a[a.index("--steps") + 1]) if "--steps" in a else 10
    problems, ls = [], []
    if not summary.get("ended") or summary.get("aborted"):
        problems.append("the calibration run did not end cleanly (ended %r, aborted %r)" % (summary.get("ended"), summary.get("aborted")))
    steps = summary.get("steps", {})
    for k, rec in sorted(steps.items(), key=lambda kv: int(kv[0])):
        if "L" not in rec:
            continue  # an inject-only or untriggered step
        if rec.get("controls") != 1 or rec.get("triggerRc") != 0 or rec.get("slackS") is None or len(rec["L"]) != 1:
            problems.append("step %s is not a complete trigger step: %r" % (k, rec))
            continue
        ls.append(rec["L"][0])
    if len(ls) != want:
        problems.append("%d complete trigger steps, expected %d" % (len(ls), want))
    l_max = max(ls) if ls else None
    t_ctl = max(30, math.ceil(20 * l_max)) if l_max is not None else None
    print(json.dumps({"lMaxS": l_max, "lS": sorted(ls), "tCtlSeconds": t_ctl, "problems": problems, "pass": not problems}, indent=1))
    return 0 if not problems else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    cmds = {"schedule": cmd_schedule, "render": cmd_render, "expect": cmd_expect, "d7": cmd_d7, "c4": cmd_c4,
            "tctl": cmd_tctl}
    if len(sys.argv) < 3 or sys.argv[1] not in cmds:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

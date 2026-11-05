#!/usr/bin/env python3
"""s10-checks.py: schedule, trigger prepare and judges of gate s10 (AC15, 10 en-gNBs, TS xApp + stub QP).

SCEN is scripts/gates/s10-scenario.json, RD a run dir. key(c) = %08X10 (the TS xApp cell key, plan R-3), meid(c) as
lib.sh meid_of. A trigger's UE is picked at its step by the pre-registered rule (the scenario's _comment); its
record RD/s10/trigger-<step>.json {step, imsi, ueId, serving, servingKey, target, targetKey, answer, ...} is what the
judges read (never an xApp log).

  schedule SCEN SEND CTL_PORT RD STUB_URL
        the pacer schedule: per trigger, prepare = `s10-checks.py prepare` (timeout prepareTimeoutS), then the 30003
        `send-rmr.sh CTL_PORT anomaly-from RD/s10/ue-<step>.txt`; one control within T_ctl
  prepare SCEN RD STEP STUB_URL [--ue-csv FILE]
        over RD/trace's context lines with seq <= STEP (ns-3 waits at barrier STEP): the IMSI by rule (lowest IMSI
        held by exactly one gNB node g at STEP, g not the target nor in excludeServing, not used by an earlier
        trigger, whose record must exist); none fails. ue-id-prepare.py resolves its KPM UE ID key U and confirms
        a UeMetrics row with ueId U of node g at seq <= STEP in Influx (--ue-csv: a Flux CSV instead), writing
        RD/s10/ue-<step>.{txt,json}; then the stub log since the previous load is saved
        (RD/s10/stub-log-before-<step>.json; a load resets it) and the one-entry table {U: [answer]} PUT, answer =
        [[key(g), [servingDl, ul]], [key(target), [targetDl, ul]]]; the stub must report exactly [U] with one
        entry. Only then is the trigger record written
  expect SCEN RD
        per trigger exactly one ledger line (viaNodeId, imsi, targetCell, afterSeq) = (S, imsi, target, step),
        applied, sourceCell = S; ledger lines = triggers; no late line
  wire SCEN RD RC_MULTISET
        per trigger exactly one RICcontrolRequest at its step whose UE ID names its IMSI (I(ueId) over RD/trace's
        context files), to node S, Style 5 action 3, targetKey = key(target) (uppercase), answered by an ack;
        requests = triggers
  stub SCEN RD INJECTOR_TX
        the injector sent one 30003 per trigger in step order naming U, state 0; the stub log parts (joined in
        step order, then RD/stub-log.json) hold one 30000 per trigger naming exactly [U], answered in state 0 by a
        30002 that is exactly {U: answer} with the serving cell first
  applied-ge10 SCEN RD RC_MULTISET
        appliedPscellChangesToGe10: applied ledger lines with targetCell >= 10 whose RICcontrolRequest (step =
        rxSeq, node = viaNodeId, I(ueId) = imsi) is Style 5 action 3 to key(targetCell) and acked; pass iff >= 1
  influx-window SCEN RD INFLUX_CSV
        influxWindowHolds: per trigger a UeMetrics row with ueId U whose _time lies in [t_rx - influxWindowS, t_trig],
        t_trig = the pacer's trigger record and t_rx = the step's first controlRx (wall clock, pacer-log.jsonl):
        inside every 60 s query window the TS xApp can have opened between its trigger and its control
  agents STATES_JSON N
        agentsConnected: e2mgr's CONNECTED names equal meid(1) .. meid(N), each once
  cellmap-args SCEN
        the replay-ts-cell-map.py arguments: --expect key(c)=meid(c) for every en-gNB c, --no-key meid(1),
        --no-wrong-node (one per line)
  cellmap-facts SCEN REPLAY_OUT
        tsCellMapKeysGe10: the keys of the replayed cell map with gNB ID >= 10 owned by exactly their own node;
        pass iff they include key(c) for every expectCellIdsGe10
  rate PACER_LOG SIMTIME
        wall seconds per simulated second: over the run (first to last `ready`) and in steady state (after 1 s)
  scenario SCEN
        the pre-registration is self-consistent: en-gNB cells 2 .. nMmWaveEnbNodes + 1; trigger steps distinct, each in
        1 .. simTimeS / indicationPeriodicityS - 1; every target an en-gNB cell in excludeServing; expectCellIdsGe10 the
        targets' cells >= 10; answer targetDl > servingDl; maxNeigh 8
  --self-test
"""
import datetime
import importlib.util
import json
import os
import re
import sys
import tempfile
import threading
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, path
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


UECM = _mod("ue_context_map", os.path.join(HERE, "..", "..", "tools", "e2-evidence", "ue-context-map.py"))
N6 = _mod("check_n6", os.path.join(HERE, "check-n6-influx-window.py"))


def load(p):
    with open(p) as f:
        return json.load(f)


def key(c):
    return "%08X10" % c


def meid(c):
    return "enB_macro_001_001_000001" if c == 1 else "en_gnb_001_001_%08x" % c


def node_of(k):
    """The gNB ID of a key %08X10, else None."""
    return int(k[:8], 16) if isinstance(k, str) and re.fullmatch("[0-9A-F]{8}10", k) else None


def triggers(sc):
    ts = sorted(sc["triggers"], key=lambda t: t["step"])
    if len({t["step"] for t in ts}) != len(ts):
        raise ValueError("two triggers in one step")
    return ts


def answer(sc, serving, target):
    a = sc["answer"]
    return [[key(serving), [a["servingDl"], a["ul"]]], [key(target), [a["targetDl"], a["ul"]]]]


def s10_dir(rd):
    return os.path.join(rd, "s10")


def ue_base(rd, step):
    return os.path.join(s10_dir(rd), "ue-%d" % step)


def rec_path(rd, step):
    return os.path.join(s10_dir(rd), "trigger-%d.json" % step)


def ledger(rd):
    p = os.path.join(rd, "trace", "e2-control-ledger.jsonl")
    if not os.path.exists(p):
        return []
    with open(p) as f:
        return [json.loads(l) for l in f if l.strip()][1:]


def out(problems, **kw):
    print(json.dumps(dict(kw, problems=problems[:20], nProblems=len(problems), **{"pass": not problems}), sort_keys=True))
    return 0 if not problems else 1


def records(sc, rd):
    """({step: trigger record}, problems): one record per scenario trigger."""
    recs, probs = {}, []
    for t in triggers(sc):
        try:
            r = load(rec_path(rd, t["step"]))
        except (OSError, ValueError) as ex:
            probs.append("trigger %d has no record: %s" % (t["step"], ex))
            continue
        if (r.get("step"), r.get("target")) != (t["step"], t["target"]):
            probs.append("trigger %d record names step %r target %r" % (t["step"], r.get("step"), r.get("target")))
            continue
        recs[t["step"]] = r
    return recs, probs


################################################################################
# the pick and the prepare
################################################################################
def pick(cm, step, target, exclude, used):
    """(imsi, serving node, skipped [(imsi, holders, why)]) by the rule, or (None, None, skipped)."""
    holders = {}
    for g in sorted(n for n, k in cm.kinds.items() if k == "gnb"):
        for i in cm.ctx(g, step):
            holders.setdefault(i, []).append(g)
    skipped = []
    for i in sorted(holders):
        hs = holders[i]
        if i in used:
            why = "used by an earlier trigger"
        elif len(hs) != 1:
            why = "held by %d en-gNBs" % len(hs)
        elif hs[0] == target or hs[0] in exclude:
            why = "held by cell %d (the target or an excluded serving cell)" % hs[0]
        else:
            return i, hs[0], skipped
        skipped.append([i, hs, why])
    return None, None, skipped


def stub_http(url, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, method=method)
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.read()


def prepare(sc, rd, step, url, ue_csv=None):
    """(record or None, problems); writes the trigger files only when every part passed."""
    ts = {t["step"]: t for t in triggers(sc)}
    if step not in ts:
        return None, ["no trigger at step %d" % step]
    t, earlier = ts[step], [s for s in ts if s < step]
    used = set()
    for s in earlier:
        try:
            used.add(load(rec_path(rd, s))["imsi"])
        except (OSError, ValueError, KeyError) as ex:
            return None, ["the earlier trigger %d has no record: %s" % (s, ex)]
    trace = os.path.join(rd, "trace")
    cm = UECM.UeContextMap(trace, max_seq=step)
    if cm.problems:
        return None, ["UE context: " + p for p in cm.problems[:3]]
    imsi, serving, skipped = pick(cm, step, t["target"], set(sc["excludeServing"]), used)
    if imsi is None:
        return None, ["no UE qualifies at step %d for target %d (skipped %s)" % (step, t["target"], skipped)]
    uep = _mod("ue_id_prepare", os.path.join(HERE, "ue-id-prepare.py"))
    os.makedirs(s10_dir(rd), exist_ok=True)
    rec, p = uep.prepare(trace, step, imsi, ue_base(rd, step), ue_csv=ue_csv)
    if rec is None:
        return None, p
    if rec["nodes"] != [serving]:
        return None, ["ue-id-prepare places IMSI %d on %r, the rule on [%d]" % (imsi, rec["nodes"], serving)]
    u, ans = rec["ueId"], answer(sc, serving, t["target"])
    try:
        before = stub_http(url, "GET", "/log")
        with open(os.path.join(s10_dir(rd), "stub-log-before-%d.json" % step), "wb") as f:
            f.write(before)
        got = json.loads(stub_http(url, "PUT", "/table", {"predictions": {u: [ans]}}))
    except (OSError, ValueError) as ex:
        return None, ["stub at %d: %s" % (step, ex)]
    if got != {"ues": [u], "entries": 1}:
        return None, ["stub load at %d answered %r, want {'ues': [%r], 'entries': 1}" % (step, got, u)]
    r = {"step": step, "imsi": imsi, "ueId": u, "ipcUeId": rec["ipcUeId"], "influx": rec["influx"],
         "serving": serving, "servingKey": key(serving), "servingMeid": meid(serving),
         "target": t["target"], "targetKey": key(t["target"]), "targetMeid": meid(t["target"]),
         "answer": ans, "skipped": skipped, "usedBefore": sorted(used)}
    with open(rec_path(rd, step), "w") as f:
        json.dump(r, f, sort_keys=True)
    return r, []


def c_schedule(a):
    sc, send, port, rd, url = load(a[0]), a[1], a[2], a[3], a[4]
    steps = {}
    for t in triggers(sc):
        steps[str(t["step"])] = {
            "prepare": {"cmd": ["python3", "-I", os.path.join(HERE, "s10-checks.py"), "prepare", a[0], rd, str(t["step"]), url],
                        "timeoutS": sc["prepareTimeoutS"]},
            "trigger": {"cmd": ["bash", send, port, "anomaly-from", ue_base(rd, t["step"]) + ".txt"]},
            "expect": 1}
    print(json.dumps({"steps": steps, "late": []}, indent=1))
    return 0


def c_prepare(a):
    csv = a[a.index("--ue-csv") + 1] if "--ue-csv" in a else None
    r, p = prepare(load(a[0]), a[1], int(a[2]), a[3], csv)
    print("s10 trigger %s: %s" % (a[2], json.dumps({k: r[k] for k in ("imsi", "ueId", "serving", "target")}) if r
                                  else "FAIL " + "; ".join(p[:3])))
    return 0 if r else 1


################################################################################
# judges
################################################################################
def c_expect(a):
    sc, rd = load(a[0]), a[1]
    recs, probs = records(sc, rd)
    lines = ledger(rd)
    for s, r in sorted(recs.items()):
        hit = [x for x in lines if (x["viaNodeId"], x["imsi"], x["targetCell"], x["afterSeq"]) == (r["serving"], r["imsi"], r["target"], s)]
        if len(hit) != 1 or hit[0]["outcome"] != "applied" or hit[0]["sourceCell"] != r["serving"]:
            probs.append("trigger %d (IMSI %d via %d to %d): ledger %r" % (s, r["imsi"], r["serving"], r["target"], hit))
    late = sum(1 for x in lines if x.get("cause") == "late")
    if late or len(lines) != len(sc["triggers"]):
        probs.append("%d ledger lines (%d late) for %d triggers" % (len(lines), late, len(sc["triggers"])))
    return out(probs, triggers=len(sc["triggers"]), ledgerLines=len(lines), late=late)


def wire_imsis(rd, ms):
    cm = UECM.UeContextMap(os.path.join(rd, "trace"))
    for m in ms:
        x = UECM.x2_of(m.get("ueId"))
        m["imsi"] = cm.imsi_of(*x) if x else None
    return ["UE context: " + q for q in cm.problems]


def c_wire(a):
    sc, rd, ms = load(a[0]), a[1], load(a[2])
    recs, probs = records(sc, rd)
    probs += wire_imsis(rd, ms)
    for s, r in sorted(recs.items()):
        hit = [m for m in ms if m["step"] == s and m["imsi"] == r["imsi"]]
        if len(hit) != 1:
            probs.append("trigger %d IMSI %d: %d RICcontrolRequests" % (s, r["imsi"], len(hit)))
            continue
        m = hit[0]
        if (m["viaNode"], m["style"], m["action"], m["targetKey"], m["answer"]) != (r["serving"], 5, 3, r["targetKey"], "ack"):
            probs.append("trigger %d IMSI %d: via %r style %r action %r key %r answer %r, want via %d 5/3 key %s ack" % (
                s, r["imsi"], m["viaNode"], m["style"], m["action"], m["targetKey"], m["answer"], r["serving"], r["targetKey"]))
    if len(ms) != len(sc["triggers"]):
        probs.append("%d RICcontrolRequests for %d triggers" % (len(ms), len(sc["triggers"])))
    return out(probs, requests=len(ms), targetKeys=sorted({m["targetKey"] for m in ms if m.get("targetKey")}))


def stub_log(sc, rd):
    log = []
    for t in triggers(sc):
        p = os.path.join(s10_dir(rd), "stub-log-before-%d.json" % t["step"])
        log += load(p) if os.path.exists(p) else []
    p = os.path.join(rd, "stub-log.json")
    return log + (load(p) if os.path.exists(p) else [])


def c_stub(a):
    sc, rd = load(a[0]), a[1]
    recs, probs = records(sc, rd)
    with open(a[2]) as f:
        tx = [json.loads(l) for l in f if l.strip()]
    want = [recs[s]["ueId"] if s in recs else None for s in sorted(t["step"] for t in sc["triggers"])]
    an = [r for r in tx if r["mtype"] == 30003]
    try:
        sent = [json.loads(bytes.fromhex(r["payloadHex"]))[0]["ue-id"] for r in an]
    except (ValueError, KeyError, IndexError, TypeError):
        sent = None
    if sent != want or any(r["state"] != 0 for r in an):
        probs.append("injector sent %r (states %r), want %r" % (sent, sorted({r["state"] for r in an}), want))
    log = stub_log(sc, rd)
    reqs = [r for r in log if r["rx"]["mtype"] == 30000]
    if len(reqs) != len(want):
        probs.append("%d stub requests for %d triggers" % (len(reqs), len(want)))
    for s, r in zip(sorted(recs), reqs):
        rec = recs[s]
        try:
            asked = json.loads(r["rx"]["payload"])["UEPredictionSet"]
            sent30002 = list(json.loads((r.get("tx") or {}).get("payload", "null")).items())
        except (ValueError, KeyError, AttributeError, TypeError):
            asked, sent30002 = None, None
        good = (asked == [rec["ueId"]] and (r.get("tx") or {}).get("state") == 0 and sent30002 is not None
                and len(sent30002) == 1 and sent30002[0][0] == rec["ueId"]
                and list(sent30002[0][1].items()) == [(k, v) for k, v in rec["answer"]])
        if not good:
            probs.append("trigger %d: asked %r, sent %r, want %r" % (s, asked, sent30002, rec["answer"]))
    return out(probs, injected=len(an), stubRequests=len(reqs),
               stubOtherTypes=sorted({r["rx"]["mtype"] for r in log if r["rx"]["mtype"] != 30000}))


def c_applied_ge10(a):
    sc, rd, ms = load(a[0]), a[1], load(a[2])
    probs = wire_imsis(rd, ms)
    got = []
    for x in ledger(rd):
        if x["outcome"] != "applied" or x["targetCell"] < 10:
            continue
        hit = [m for m in ms if (m["step"], m["viaNode"], m["imsi"]) == (x["rxSeq"], x["viaNodeId"], x["imsi"])
               and (m["style"], m["action"], m["targetKey"], m["answer"]) == (5, 3, key(x["targetCell"]), "ack")]
        if len(hit) == 1:
            got.append({"step": x["rxSeq"], "imsi": x["imsi"], "via": x["viaNodeId"], "targetCell": x["targetCell"]})
    if not got:
        probs.append("no applied PSCell change to a cell >= 10 with its acked Style 5 action 3 request on the wire")
    return out(probs, appliedPscellChangesToGe10=len(got), changes=got)


def flux_time(s):
    """RFC 3339 UTC (nanosecond fraction allowed) -> epoch seconds."""
    m = re.fullmatch(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?Z", s or "")
    if not m:
        raise ValueError("time %r" % s)
    base = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc)
    return base.timestamp() + (float("0" + m.group(2)) if m.group(2) else 0.0)


def pacer_times(rd, step):
    """(wall time of the step's trigger, of its first controlRx) from pacer-log.jsonl; None when absent."""
    t_trig = t_rx = None
    with open(os.path.join(rd, "pacer", "pacer-log.jsonl")) as f:
        for l in f:
            if not l.strip():
                continue
            r = json.loads(l)
            m = r.get("msg") or {}
            if r.get("dir") == "pacer" and m.get("type") == "trigger" and m.get("seq") == step and t_trig is None:
                t_trig = r["t"]
            elif r.get("dir") == "rx" and m.get("type") == "controlRx" and m.get("seq") == step and t_rx is None:
                t_rx = r["t"]
    return t_trig, t_rx


def c_influx_window(a):
    sc, rd = load(a[0]), a[1]
    recs, probs = records(sc, rd)
    with open(a[2]) as f:
        rows = N6.parse(f.read())
    w = float(sc["influxWindowS"])
    per = []
    for s, r in sorted(recs.items()):
        t_trig, t_rx = pacer_times(rd, s)
        times = []
        for row, _ in rows:
            if row.get("_measurement") == "UeMetrics" and row.get("ueId") == r["ueId"]:
                try:
                    times.append(flux_time(row.get("_time")))
                except ValueError as ex:
                    probs.append("trigger %d: %s" % (s, ex))
        if t_trig is None or t_rx is None or t_rx < t_trig:
            probs.append("trigger %d: pacer trigger %r, first controlRx %r" % (s, t_trig, t_rx))
            per.append({"step": s, "ueId": r["ueId"], "holds": False})
            continue
        inside = [x for x in times if t_rx - w <= x <= t_trig]
        before = [x for x in times if x <= t_trig]
        per.append({"step": s, "ueId": r["ueId"], "rowsInWindow": len(inside), "holds": bool(inside),
                    "latestRowAgeAtTriggerS": round(t_trig - max(before), 3) if before else None,
                    "controlRxAfterTriggerS": round(t_rx - t_trig, 3)})
        if not inside:
            probs.append("trigger %d: no UeMetrics row with ueId %s in [t_rx - %g s, t_trig]" % (s, r["ueId"], w))
    return out(probs, influxWindowHolds=bool(per) and all(p["holds"] for p in per) and not probs, triggers=per)


def c_agents(a):
    states, n = load(a[0]), int(a[1])
    got = sorted(x.get("inventoryName") for x in states if x.get("connectionStatus") == "CONNECTED")
    want = sorted(meid(c) for c in range(1, n + 1))
    probs = [] if got == want else ["CONNECTED %r, want %r" % (got, want)]
    return out(probs, agentsConnected=len(set(got)) if got == want else len(got), connected=got)


def cellmap_args(sc):
    args = []
    for c in range(2, 2 + sc["nMmWaveEnbNodes"]):
        args += ["--expect", "%s=%s" % (key(c), meid(c))]
    return args + ["--no-key", meid(1), "--no-wrong-node"]


def cellmap_facts(sc, cell_map):
    keys = sorted(k for k, owners in cell_map.items()
                  if node_of(k) is not None and node_of(k) >= 10 and owners == [meid(node_of(k))])
    want = [key(c) for c in sc["expectCellIdsGe10"]]
    return keys, ([] if set(want) <= set(keys) else ["cell map keys >= 10 %r lack %r" % (keys, sorted(set(want) - set(keys)))])


def c_cellmap_facts(a):
    sc, rep = load(a[0]), load(a[1])
    keys, probs = cellmap_facts(sc, rep.get("cellMap") or {})
    return out(probs, tsCellMapKeysGe10=keys)


def scenario_problems(sc):
    p = []
    try:
        n, steps = sc["nMmWaveEnbNodes"], round(sc["simTimeS"] / sc["indicationPeriodicityS"])
        ts = triggers(sc)
        cells = set(range(2, n + 2))
        for t in ts:
            if not 1 <= t["step"] < steps:
                p.append("trigger step %d outside 1 .. %d" % (t["step"], steps - 1))
            if t["target"] not in cells or t["target"] not in sc["excludeServing"]:
                p.append("target %d is not an en-gNB cell in excludeServing" % t["target"])
        if sorted(sc["expectCellIdsGe10"]) != sorted(t["target"] for t in ts if t["target"] >= 10):
            p.append("expectCellIdsGe10 %r is not the targets >= 10" % (sc["expectCellIdsGe10"],))
        if not sc["answer"]["targetDl"] > sc["answer"]["servingDl"]:
            p.append("answer targetDl must exceed servingDl")
        if sc["neighbours"]["maxNeigh"] != 8:
            p.append("maxNeigh %r, not E2SM_REPORT_MAX_NEIGH 8" % sc["neighbours"]["maxNeigh"])
    except (KeyError, TypeError, ValueError, ZeroDivisionError) as ex:
        p.append("scenario malformed: %r" % (ex,))
    return p


def c_scenario(a):
    return out(scenario_problems(load(a[0])))


def c_rate(a):
    rd = []
    with open(a[0]) as f:
        for l in f:
            if l.strip():
                r = json.loads(l)
                if r.get("dir") == "rx" and (r.get("msg") or {}).get("type") == "ready":
                    rd.append((r["t"], r["msg"]["simTimeNs"]))
    sim = float(a[1])
    steady = [x for x in rd if x[1] >= 1_000_000_000]
    res = {"readyLines": len(rd), "wallS": round(rd[-1][0] - rd[0][0], 3) if len(rd) > 1 else None,
           "wallPerSimS": round((rd[-1][0] - rd[0][0]) / sim, 3) if len(rd) > 1 else None,
           "wallPerSimSSteady": round((steady[-1][0] - steady[0][0]) / ((steady[-1][1] - steady[0][1]) / 1e9), 3)
           if len(steady) > 1 and steady[-1][1] > steady[0][1] else None}
    print(json.dumps(res, sort_keys=True))
    return 0 if res["wallPerSimS"] is not None else 1


################################################################################
# self-test
################################################################################
X2_TEMPLATE = ("0024004100000100F4003A40000200FC00090000F11050{g}00FD0026000004{p}0000F110{g}10001000F110410009A7B600004D"
               "004100071011353C050000")  # the independent encoder's EN-DC X2 SETUP REQUEST of the agent's cell after the NR-ARFCN
# fix: Point A 632758, MTC SSB 633312, scs60/nrb24 (evidence/p10-d-r3-1-replay-dry)


def _nodeb(name, n):
    import base64
    part = base64.b64encode(X2_TEMPLATE.format(g="%08X" % n, p="%04X" % n).encode()).decode()
    return {"ranName": name, "connectionStatus": "CONNECTED",
            "gnb": {"nodeConfigs": [{"e2nodeComponentInterfaceType": "x2", "e2nodeComponentRequestPart": part}]}}


class _Stub:
    """A local stand-in of the stub QP's HTTP API (/log, /table) for the prepare self-test."""

    def __init__(self, answer_override=None):
        import http.server
        stub = self
        self.loads, self.log, self.override = [], [{"rx": {"mtype": 30000}}], answer_override

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                body = json.dumps(stub.log).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

            def do_PUT(self):
                t = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                stub.loads.append(t)
                stub.log = []
                ans = stub.override or {"ues": sorted(t["predictions"]), "entries": sum(len(v) for v in t["predictions"].values())}
                body = json.dumps(ans).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)
        self.srv = http.server.HTTPServer(("127.0.0.1", 0), H)
        self.url = "http://127.0.0.1:%d" % self.srv.server_port
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def close(self):
        self.srv.shutdown()
        self.srv.server_close()


def _run_fixture(d, ctx, steps_samples=40):
    """A run dir: eNB node 1 and gNB nodes 2, 3, 10, 11 with the context lines ctx {node: [(seq, [imsi...])]} (MN RNTI
    = imsi + 100 on MN cell 1) and samples listing ctx(n, s); a Flux CSV with one UeMetrics row per (node, seq, UE)."""
    tr = os.path.join(d, "trace")
    os.makedirs(tr, exist_ok=True)
    ue = lambda i: {"imsi": i, "lteRnti": i + 100, "mnCellId": 1, "mmeUeS1apId": i}
    rows = []
    for n, kind in ((1, "enb"), (2, "gnb"), (3, "gnb"), (10, "gnb"), (11, "gnb")):
        lines = sorted(ctx.get(n, []))
        with open(os.path.join(tr, "e2-ue-context-%d.jsonl" % n), "w") as f:
            for s, imsis in lines:
                f.write(json.dumps({"type": "ueContext", "v": 1, "nodeId": n, "seq": s, "ues": [ue(i) for i in sorted(imsis)]}) + "\n")
        with open(os.path.join(tr, "e2-ipc-trace-%d.jsonl" % n), "w") as f:
            f.write(json.dumps({"type": "hello", "nodeId": n, "kind": kind}) + "\n")
            for s in range(steps_samples):
                cur = [i for q, i in lines if q <= s]
                imsis = cur[-1] if cur else []
                f.write(json.dumps({"type": "sample", "nodeId": n, "seq": s, "ues": [{"imsi": i} for i in imsis]}) + "\n")
                if kind == "gnb":
                    rows += [["2026-01-01T00:00:00Z", "UeMetrics", UECM.gnb_tag(i + 100, 1), n, s] for i in imsis]
    csv = os.path.join(d, "ue.csv")
    with open(csv, "w") as f:
        f.write(N6._csv(["_time", "_measurement", "ueId", "ns3.nodeId", "ns3.seq"],
                        ["dateTime:RFC3339", "string", "string", "long", "long"], rows))
    return csv


def self_test():
    fails = []
    sc = {"triggers": [{"step": 30, "target": 10}, {"step": 50, "target": 11}], "excludeServing": [10, 11],
          "answer": {"servingDl": 100, "targetDl": 300, "ul": 0}, "prepareTimeoutS": 30, "nMmWaveEnbNodes": 10,
          "expectCellIdsGe10": [10, 11], "influxWindowS": 60}
    # IMSI 1 is on cell 10 (excluded), IMSI 2 on cells 2 and 3 at once (ambiguous), IMSI 3 on cell 3, IMSI 4 on cell 2
    ctx = {1: [(0, [1, 2, 3, 4])], 10: [(0, [1])], 2: [(0, [2, 4])], 3: [(0, [2, 3])], 11: [(0, [])]}
    with tempfile.TemporaryDirectory() as d:
        csv = _run_fixture(d, ctx)
        stub = _Stub()
        try:
            r1, p1 = prepare(sc, d, 30, stub.url, csv)
            r2, p2 = prepare(sc, d, 50, stub.url, csv)
        finally:
            stub.close()
        if not r1 or (r1["imsi"], r1["serving"], r1["answer"]) != (3, 3, [["0000000310", [100, 0]], ["0000000A10", [300, 0]]]):
            fails.append("trigger 30 picks IMSI 3 on cell 3 (IMSI 1 on cell 10, IMSI 2 on two cells): %r %r" % (r1, p1))
        if not r2 or (r2["imsi"], r2["serving"], r2["targetKey"]) != (4, 2, "0000000B10"):
            fails.append("trigger 50 picks IMSI 4 on cell 2 (IMSI 3 used): %r %r" % (r2, p2))
        if r1 and r2 and [list(t["predictions"]) for t in stub.loads] != [[r1["ueId"]], [r2["ueId"]]]:
            fails.append("the stub got one one-entry table per trigger: %r" % stub.loads)
        if not os.path.exists(os.path.join(d, "s10", "stub-log-before-50.json")) or open(ue_base(d, 30) + ".txt").read() != r1["ueId"] + "\n":
            fails.append("the stub log part and the trigger key file are written")
    # a trigger whose rule finds no UE fails the run and writes no record
    with tempfile.TemporaryDirectory() as d:
        csv = _run_fixture(d, {1: [(0, [1])], 10: [(0, [1])], 2: [(0, [])], 3: [(0, [])], 11: [(0, [])]})
        stub = _Stub()
        try:
            r, p = prepare(sc, d, 30, stub.url, csv)
        finally:
            stub.close()
        if r is not None or not any("no UE qualifies" in q for q in p) or os.path.exists(rec_path(d, 30)) or stub.loads:
            fails.append("a trigger with no qualifying UE must fail before any stub load: %r %r" % (r, p))
    # a stub answering another table fails the prepare
    with tempfile.TemporaryDirectory() as d:
        csv = _run_fixture(d, ctx)
        stub = _Stub(answer_override={"ues": [], "entries": 0})
        try:
            r, p = prepare(sc, d, 30, stub.url, csv)
        finally:
            stub.close()
        if r is not None or os.path.exists(rec_path(d, 30)):
            fails.append("a stub load that does not report [U] must fail: %r" % (r,))
    # a later trigger without the earlier record fails
    with tempfile.TemporaryDirectory() as d:
        csv = _run_fixture(d, ctx)
        r, p = prepare(sc, d, 50, "http://127.0.0.1:9", csv)
        if r is not None:
            fails.append("trigger 50 without trigger 30's record must fail")

    # judges on a synthetic run: the two triggers applied via their serving cells
    def judge_case(name, want, fn, mutate=None):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "s10"))
            os.makedirs(os.path.join(d, "trace"))
            os.makedirs(os.path.join(d, "pacer"))
            _run_fixture(d, ctx)
            ue = lambda i: UECM.gnb_tag(i + 100, 1)
            recs = {30: {"step": 30, "imsi": 3, "ueId": ue(3), "serving": 3, "servingKey": "0000000310", "target": 10,
                         "targetKey": "0000000A10", "answer": [["0000000310", [100, 0]], ["0000000A10", [300, 0]]]},
                    50: {"step": 50, "imsi": 4, "ueId": ue(4), "serving": 2, "servingKey": "0000000210", "target": 11,
                         "targetKey": "0000000B10", "answer": [["0000000210", [100, 0]], ["0000000B10", [300, 0]]]}}
            led = [{"type": "ledgerHeader", "v": 1}]
            ms, tx, logp, pl, csv_rows = [], [], {}, [], []
            for s, r in recs.items():
                led.append({"rxSeq": s, "afterSeq": s, "viaNodeId": r["serving"], "ctlId": 1, "imsi": r["imsi"],
                            "sourceCell": r["serving"], "targetCell": r["target"], "outcome": "applied", "cause": ""})
                ms.append({"step": s, "viaNode": r["serving"], "style": 5, "action": 3, "targetKey": r["targetKey"],
                           "answer": "ack", "ueId": {"type": "en-gNB-UEID", "mEnbUeX2apId": r["imsi"] + 100,
                                                     "globalEnbId": {"plmn": "00F110", "macroEnbId": "00001"}}})
                tx.append({"mtype": 30003, "state": 0, "payloadHex": json.dumps([{"ue-id": r["ueId"]}]).encode().hex()})
                logp[s] = [{"rx": {"mtype": 30000, "payload": json.dumps({"UEPredictionSet": [r["ueId"]]})},
                            "tx": {"state": 0, "payload": json.dumps({r["ueId"]: {k: v for k, v in r["answer"]}})}}]
                t0 = 1767225600.0 + 100 * s
                pl += [{"t": t0, "dir": "pacer", "msg": {"type": "trigger", "seq": s}},
                       {"t": t0 + 0.2, "dir": "rx", "msg": {"type": "controlRx", "seq": s}}]
                csv_rows.append([datetime.datetime.fromtimestamp(t0 - 20, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.123456789Z"),
                                 "UeMetrics", r["ueId"], r["serving"], s])
            st = {"recs": recs, "led": led, "ms": ms, "tx": tx, "logp": logp, "pl": pl, "csv": csv_rows}
            if mutate:
                mutate(st)
            for s, r in st["recs"].items():
                json.dump(r, open(rec_path(d, s), "w"))
            open(os.path.join(d, "trace", "e2-control-ledger.jsonl"), "w").write("".join(json.dumps(x) + "\n" for x in st["led"]))
            json.dump(st["ms"], open(os.path.join(d, "ms.json"), "w"))
            open(os.path.join(d, "tx.jsonl"), "w").write("".join(json.dumps(x) + "\n" for x in st["tx"]))
            json.dump(st["logp"][30], open(os.path.join(d, "s10", "stub-log-before-50.json"), "w"))
            json.dump(st["logp"][50], open(os.path.join(d, "stub-log.json"), "w"))
            open(os.path.join(d, "pacer", "pacer-log.jsonl"), "w").write("".join(json.dumps(x) + "\n" for x in st["pl"]))
            open(os.path.join(d, "influx.csv"), "w").write(N6._csv(["_time", "_measurement", "ueId", "ns3.nodeId", "ns3.seq"],
                                                                    ["dateTime:RFC3339", "string", "string", "long", "long"], st["csv"]))
            scp = os.path.join(d, "sc.json")
            json.dump(sc, open(scp, "w"))
            args = {"expect": [scp, d], "wire": [scp, d, os.path.join(d, "ms.json")], "stub": [scp, d, os.path.join(d, "tx.jsonl")],
                    "ge10": [scp, d, os.path.join(d, "ms.json")], "window": [scp, d, os.path.join(d, "influx.csv")]}[fn]
            f = {"expect": c_expect, "wire": c_wire, "stub": c_stub, "ge10": c_applied_ge10, "window": c_influx_window}[fn]
            import contextlib
            import io
            with contextlib.redirect_stdout(io.StringIO()):
                got = f(args) == 0
            if got != want:
                fails.append("%s (%s): pass %s, want %s" % (name, fn, got, want))

    for fn in ("expect", "wire", "stub", "ge10", "window"):
        judge_case("healthy run", True, fn)

    def via_wrong(st):
        st["ms"][0]["viaNode"] = 10
    judge_case("a control via the wrong node", False, "wire", via_wrong)

    def led_via_wrong(st):
        st["led"][1]["viaNodeId"] = 2
    judge_case("a ledger line via the wrong node", False, "expect", led_via_wrong)

    def refused(st):
        st["led"][1].update(outcome="refused", cause="inHandover")
        st["led"][2].update(outcome="refused", cause="inHandover")
    judge_case("refused lines", False, "expect", refused)
    judge_case("no applied change to a cell >= 10", False, "ge10", refused)

    def key_lower(st):
        st["ms"][1]["targetKey"] = "0000000b10"
    judge_case("a lowercase target key", False, "wire", key_lower)

    def style3(st):
        st["ms"][0]["style"], st["ms"][0]["action"] = 3, 1
    judge_case("a Style 3 action 1 request", False, "wire", style3)

    def extra_req(st):
        st["ms"].append(dict(st["ms"][0], step=31))
    judge_case("an extra RICcontrolRequest", False, "wire", extra_req)

    def stub_order(st):
        st["logp"][50][0]["tx"]["payload"] = json.dumps({st["recs"][50]["ueId"]: {"0000000B10": [300, 0], "0000000210": [100, 0]}})
    judge_case("a stub answer with the target first", False, "stub", stub_order)

    def inj_other(st):
        st["tx"][1]["payloadHex"] = json.dumps([{"ue-id": st["recs"][30]["ueId"]}]).encode().hex()
    judge_case("the injector naming the first UE twice", False, "stub", inj_other)

    def old_row(st):
        st["csv"][1][0] = datetime.datetime.fromtimestamp(1767225600.0 + 100 * 50 - 61, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    judge_case("the second UE's only row is 61 s before its trigger", False, "window", old_row)

    def no_record(st):
        del st["recs"][50]
    judge_case("a missing trigger record", False, "expect", no_record)

    # the cell map: the TS xApp key replay on en-gNB records 2..11 with the gate's arguments
    rep = _mod("replay_ts_cell_map", os.path.join(HERE, "replay-ts-cell-map.py"))
    args = cellmap_args(sc)
    exp = [args[i + 1] for i, x in enumerate(args) if x == "--expect"]
    docs = [_nodeb(meid(c), c) for c in range(2, 12)]
    res, p = rep.judge(docs, exp, [meid(1)], True)
    keys, kp = cellmap_facts(sc, res["cellMap"])
    if p or kp or keys != ["0000000A10", "0000000B10"]:
        fails.append("ten en-gNB records give every key, 0000000A10 and 0000000B10 among them: %r %r %r" % (p, kp, keys))
    _, p = rep.judge([d for d in docs if d["ranName"] != meid(11)], exp, [meid(1)], True)
    if not any("0000000B10" in q for q in p):
        fails.append("a missing cell 11 record must fail its --expect")
    _, p = rep.judge(docs + [dict(_nodeb("gnb_001_001_0000000a", 10))], exp, [meid(1)], True)
    if not any("2 owners" in q for q in p):
        fails.append("a key claimed by two nodes must fail --no-wrong-node")
    _, kp = cellmap_facts(sc, {"0000000A10": [meid(10)], "0000000B10": [meid(10)]})
    if not kp:
        fails.append("a cell 11 key owned by node 10 is not a cell-11 key")
    # the pre-registration lint: the committed scenario passes, each broken copy fails
    real = load(os.path.join(HERE, "s10-scenario.json"))
    if scenario_problems(real):
        fails.append("s10-scenario.json fails its own lint: %r" % scenario_problems(real))
    for name, mut in (("a target outside the en-gNB cells", lambda s: s["triggers"][1].update(target=12)),
                      ("a trigger step past the run", lambda s: s["triggers"][1].update(step=80)),
                      ("two triggers in one step", lambda s: s["triggers"][1].update(step=30)),
                      ("a target not excluded as serving", lambda s: s.update(excludeServing=[10])),
                      ("expectCellIdsGe10 not the targets", lambda s: s.update(expectCellIdsGe10=[10])),
                      ("a 9-neighbour cap", lambda s: s["neighbours"].update(maxNeigh=9))):
        bad = json.loads(json.dumps(real))
        mut(bad)
        if not scenario_problems(bad):
            fails.append("scenario lint passes %s" % name)
    for f in fails:
        print("FAIL " + f)
    print("s10-checks self-test: " + ("ok" if not fails else "%d failure(s)" % len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    cmds = {"schedule": (c_schedule, 5), "prepare": (c_prepare, 4), "expect": (c_expect, 2), "wire": (c_wire, 3),
            "stub": (c_stub, 3), "applied-ge10": (c_applied_ge10, 3), "influx-window": (c_influx_window, 3),
            "agents": (c_agents, 2), "cellmap-facts": (c_cellmap_facts, 2), "rate": (c_rate, 2),
            "scenario": (c_scenario, 1)}
    av = sys.argv[1:]
    if av == ["--self-test"]:
        sys.exit(self_test())
    if av[:1] == ["cellmap-args"] and len(av) == 2:
        print("\n".join(cellmap_args(load(av[1]))))
        sys.exit(0)
    if not av or av[0] not in cmds or len(av) - 1 < cmds[av[0]][1]:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(cmds[av[0]][0](av[1:]))

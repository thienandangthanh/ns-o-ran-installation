#!/usr/bin/env python3
"""r3p-checks.py: the judges of gate r3p (TS xApp + harness predictor). SCHED is r3p-schedule.json; RD a run dir
(RD/r3p/ holds the prepare step's windows, N6 verdicts, predictor records and the stub log parts).

  expect SCHED LEDGER         a handover trigger: exactly one ledger line (via, imsi, targetCell) with afterSeq =
                              its step, applied; a none trigger: no ledger line of its IMSI with afterSeq = its step
                              (step-scoped: m1 reuses h1's IMSI); lines = handovers; late = 0
  wire SCHED RC_MULTISET      RICcontrolRequests = handover triggers, each by (imsi, step), via the target's agent,
                              key = the predictor's target, uppercase, one terminal answer; none for a none trigger
  stub SCHED RD INJECTOR_TX   the injector sent one 30003 per trigger in order; the stub (log parts joined in step
                              order) got one 30000 naming exactly that UE and sent in state 0 exactly the predictor's
                              answer (same cells, serving first, uppercase keys, decimal IMSI)
  predictor SCEN SCHED RD     per trigger: N6 passed on an unclipped window; one record; its answer = the formula on
                              the certified window; its decision = the scheduled one
  influx-ipc SCEN RD [--cell-csv F]   full Influx = IPC for the read counter: for every gNB cell exactly one long
                              row per IPC seq, equal values, no extra seq; no eNB row carries the counter
  d7 LEDGER                   every applied line came through its target gNB's agent (recorded deviation P1)
  observation SCEN SCHED RD   the pre-registered observation change (DL of the two gNB cells swapped) gives the
                              pre-registered decisions on n1's and h1's certified windows (RIC-free replay)
  membership SCHED RD         m1's certified window lists h1's IMSI on h1's target cell
  driven SCHED LEDGER RD      predictorDrivenApplied: applied lines whose (imsi, rxSeq) is a scheduled handover
                              trigger and whose target is the predictor's argmax key; must be >= 1
  secrets RD TOKEN_FILE       no secret of the token file in RD/r3p (fails closed when the file cannot be read)
  --self-test
"""
import glob
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _mod(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


P = _mod("r3p_predictor", "r3p-predictor.py")
N6 = _mod("n6", "check-n6-influx-window.py")


def load(p):
    return json.load(open(p))


def ledger(p):
    return [json.loads(l) for l in open(p) if l.strip()][1:]


def node_of(key):
    """gNB node id from an uppercase cell key %08X%02X (the cell id equals the node id here)."""
    return int(key[-2:], 16) if key else None


def out(problems, **kw):
    print(json.dumps(dict(kw, problems=problems[:20], nProblems=len(problems), **{"pass": not problems}), sort_keys=True))
    return 0 if not problems else 1


def c_expect(a):
    ts, lines = load(a[0])["triggers"], ledger(a[1])
    probs, ho = [], [t for t in ts if t["decision"] == "handover"]
    for t in ho:
        hit = [x for x in lines if (x["viaNodeId"], x["imsi"], x["targetCell"], x["afterSeq"]) == (t["via"], t["imsi"], t["targetCell"], t["step"])]
        if len(hit) != 1 or hit[0]["outcome"] != "applied":
            probs.append("handover step %d imsi %d: %r" % (t["step"], t["imsi"], hit))
    for t in ts:
        if t["decision"] == "none" and any(x["imsi"] == t["imsi"] and x["afterSeq"] == t["step"] for x in lines):
            probs.append("none step %d imsi %d has a ledger line" % (t["step"], t["imsi"]))
    late = sum(1 for x in lines if x.get("cause") == "late")
    if late or len(lines) != len(ho):
        probs.append("%d ledger lines (%d late) for %d handovers" % (len(lines), late, len(ho)))
    return out(probs, handovers=len(ho), ledgerLines=len(lines), late=late)


def c_wire(a):
    ts, ms = load(a[0])["triggers"], load(a[1])
    probs, ho = [], [t for t in ts if t["decision"] == "handover"]
    for t in ho:
        hit = [m for m in ms if m["imsi"] == t["imsi"] and m["step"] == t["step"]]
        if len(hit) != 1 or hit[0]["viaNode"] != t["via"] or hit[0]["targetKey"] != t["key"] or hit[0]["answer"] not in ("ack", "failure"):
            probs.append("handover step %d imsi %d: %r" % (t["step"], t["imsi"], hit))
    for t in ts:
        if t["decision"] == "none" and any(m["imsi"] == t["imsi"] and m["step"] == t["step"] for m in ms):
            probs.append("none step %d imsi %d: a RICcontrolRequest on the wire" % (t["step"], t["imsi"]))
    if len(ms) != len(ho):
        probs.append("%d RICcontrolRequests for %d handovers" % (len(ms), len(ho)))
    return out(probs, requests=len(ms), handovers=len(ho), targetKeys=sorted({m["targetKey"] for m in ms}))


def records(rd):
    p = os.path.join(rd, "r3p", "predictor-records.jsonl")
    return [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []


def stub_log(rd):
    parts = sorted(glob.glob(os.path.join(rd, "r3p", "stub-log-before-*.json")), key=lambda p: int(p.rsplit("-", 1)[1][:-5]))
    log = []
    for p in parts + [os.path.join(rd, "stub-log.json")]:
        log += load(p) if os.path.exists(p) else []
    return log


def c_stub(a):
    ts, rd = load(a[0])["triggers"], a[1]
    tx = [json.loads(l) for l in open(a[2]) if l.strip()]
    probs, recs = [], {r["T"]: r for r in records(rd)}
    an = [r for r in tx if r["mtype"] == 30003]
    sent = [json.loads(bytes.fromhex(r["payloadHex"]))[0]["ue-id"] for r in an]
    if sent != [str(t["imsi"]) for t in ts] or any(r["state"] != 0 for r in an):
        probs.append("injector sent %r (states %r), want %r" % (sent, sorted({r["state"] for r in an}), [str(t["imsi"]) for t in ts]))
    reqs = [r for r in stub_log(rd) if r["rx"]["mtype"] == 30000]
    if len(reqs) != len(ts):
        probs.append("%d stub requests for %d triggers" % (len(reqs), len(ts)))
    for t, r in zip(ts, reqs):
        rec = recs.get(t["step"])
        try:
            asked = json.loads(r["rx"]["payload"])["UEPredictionSet"]
            sent30002 = list(json.loads((r.get("tx") or {}).get("payload", "null")).items())
        except (ValueError, KeyError, AttributeError):
            asked, sent30002 = None, None
        want = [(str(t["imsi"]), {k: v for k, v in rec["answer"]})] if rec else None
        if asked != [str(t["imsi"])] or (r.get("tx") or {}).get("state") != 0 or not sent30002 or want is None \
                or sent30002[0][0] != want[0][0] or list(sent30002[0][1].items()) != [(k, v) for k, v in rec["answer"]]:
            probs.append("step %d: asked %r, sent %r, predictor %r" % (t["step"], asked, sent30002, rec and rec["answer"]))
    return out(probs, triggers=len(ts), stubRequests=len(reqs))


def c_predictor(a):
    sc, ts, rd = load(a[0]), load(a[1])["triggers"], a[2]
    probs, recs = [], records(rd)
    for t in ts:
        mine = [r for r in recs if r["T"] == t["step"]]
        v = os.path.join(rd, "r3p", "n6-%d.json" % t["step"])
        w = os.path.join(rd, "r3p", "window-%d.json" % t["step"])
        if len(mine) != 1 or not os.path.exists(v) or not load(v)["pass"] or not os.path.exists(w):
            probs.append("step %d: %d records, N6 %s" % (t["step"], len(mine), os.path.exists(v) and load(v)["pass"]))
            continue
        win = load(w)
        ans = P.answer(sc, win, t["imsi"]) if not win.get("clipped") else None
        if ans is None or mine[0]["answer"] != ans or mine[0]["decision"] != t["decision"] or P.decide(sc, ans)[0] != t["decision"]:
            probs.append("step %d: record %r, formula %r, scheduled %s" % (t["step"], mine[0]["answer"], ans, t["decision"]))
    if len(recs) != len(ts):
        probs.append("%d records for %d triggers" % (len(recs), len(ts)))
    return out(probs, triggers=len(ts), records=len(recs))


def c_influx_ipc(a):
    sc, rd = load(a[0]), a[1]
    field, gnbs = sc["counter"]["field"], [int(n) for n in sc["n6"]["expectedCells"]]
    text = open(a[a.index("--cell-csv") + 1]).read() if "--cell-csv" in a else N6.query(N6.flux("cellMetrics", ["ns3.nodeId", "ns3.seq", field]))
    ipc = N6.ipc(os.path.join(rd, "trace"), 10 ** 9, gnbs)
    rows, probs = {}, []
    for r, ty in N6.parse(text):
        n, s = int(r["ns3.nodeId"]), int(r["ns3.seq"])
        if n not in gnbs:
            if r.get(field) is not None:
                probs.append("eNB/other node %d seq %d carries %s" % (n, s, field))
            continue
        rows.setdefault((n, s), []).append((r.get(field), ty.get(field)))
    for n in gnbs:
        if not ipc[n]:
            probs.append("node %d: no IPC samples" % n)
        for s, smp in sorted(ipc[n].items()):
            got, want = rows.pop((n, s), []), ((smp.get("cell") or {}).get("cuUp") or {}).get(field)
            if len(got) != 1 or got[0][1] != "long" or got[0][0] is None or int(got[0][0]) != want:
                probs.append("(%d, %d): influx %r, ipc %r" % (n, s, got, want))
    probs += ["(%d, %d): an Influx row with no IPC sample" % k for k in sorted(rows)]
    return out(probs, seqsPerNode={str(n): len(ipc[n]) for n in gnbs})


def c_d7(a):
    ap = [x for x in ledger(a[0]) if x["outcome"] == "applied"]
    via = sum(1 for x in ap if x["viaNodeId"] == x["targetCell"])
    return out([] if ap and via == len(ap) else ["%d of %d applied lines via the target gNB" % (via, len(ap))],
               applied=len(ap), viaTargetGnb=via, form="R3′: target-addressed (recorded deviation P1)")


def c_observation(a):
    sc, ts, rd = load(a[0]), load(a[1])["triggers"], a[2]
    cases, probs, got = sc["observationChange"]["cases"], [], {}
    named = {"n1": min((t for t in ts if t["decision"] == "none"), key=lambda t: t["step"]),
             "h1": min((t for t in ts if t["decision"] == "handover"), key=lambda t: t["step"])}
    for name, t in named.items():
        win = P.swapped(load(os.path.join(rd, "r3p", "window-%d.json" % t["step"])))
        got[name] = P.decide(sc, P.answer(sc, win, t["imsi"]))[0]
        if got[name] != cases[name]:
            probs.append("%s (step %d): swapped observations give %s, pre-registered %s" % (name, t["step"], got[name], cases[name]))
    return out(probs, decisions=got)


def c_membership(a):
    ts, rd = sorted(load(a[0])["triggers"], key=lambda t: t["step"]), a[1]
    h1 = next(t for t in ts if t["decision"] == "handover")
    after = [t for t in ts if t["step"] > h1["step"] and t["imsi"] == h1["imsi"]]
    probs, seen = [], {}
    for t in after:
        seen[t["step"]] = load(os.path.join(rd, "r3p", "window-%d.json" % t["step"]))["membership"].get(str(t["imsi"]))
        if seen[t["step"]] != h1["targetCell"]:
            probs.append("step %d: imsi %d on %r, h1 target %d" % (t["step"], t["imsi"], seen[t["step"]], h1["targetCell"]))
    return out(probs if after else ["no trigger of h1's IMSI after h1"], servingAfterH1=seen)


def c_driven(a):
    ts, lines, recs = load(a[0])["triggers"], ledger(a[1]), {r["T"]: r for r in records(a[2])}
    ho = {(t["imsi"], t["step"]) for t in ts if t["decision"] == "handover"}
    n = sum(1 for x in lines if x["outcome"] == "applied" and (x["imsi"], x["rxSeq"]) in ho and x["rxSeq"] in recs
            and node_of(recs[x["rxSeq"]]["target"]) == x["targetCell"])
    return out([] if n >= 1 else ["no predictor-driven applied handover"], predictorDrivenApplied=n)


def c_secrets(a):
    try:
        tok = load(a[1])
    except (OSError, ValueError) as ex:
        return out(["token file unreadable: %s" % ex])
    secrets = set()
    stack = [tok]
    while stack:
        v = stack.pop()
        if isinstance(v, str) and len(v) >= 20:
            secrets.add(v)
        elif isinstance(v, dict):
            stack += list(v.values())
        elif isinstance(v, list):
            stack += v
    hits = sum(open(p, errors="replace").read().count(s) for p in glob.glob(os.path.join(a[0], "r3p", "*")) for s in secrets)
    return out(["%d secret hit(s)" % hits] if hits or not secrets else [], files=len(glob.glob(os.path.join(a[0], "r3p", "*"))),
               knownSecrets=len(secrets))


CMDS = {"expect": (c_expect, 2), "wire": (c_wire, 2), "stub": (c_stub, 3), "predictor": (c_predictor, 3),
        "influx-ipc": (c_influx_ipc, 2), "d7": (c_d7, 1), "observation": (c_observation, 3), "membership": (c_membership, 2),
        "driven": (c_driven, 3), "secrets": (c_secrets, 2)}

if __name__ == "__main__":
    av = sys.argv[1:]
    if av == ["--self-test"]:
        sys.exit(_mod("r3p_checks_fixtures", "r3p-checks-fixtures.py").self_test(sys.modules[__name__]))
    if not av or av[0] not in CMDS or len(av) - 1 < CMDS[av[0]][1]:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(CMDS[av[0]][0](av[1:]))

"""r3p-checks-fixtures.py: synthetic fixtures for r3p-checks.py --self-test (no real data: the repo is public).

A coherent R3′ run: triggers n1 (step 20, IMSI 3, none), h1 (30, IMSI 1, handover to cell 2 via node 2) and m1 (50,
IMSI 1, none, now on cell 2); constant per-cell DL; IPC traces, certified windows, predictor records, stub log parts,
injector sends, ledger and decoded RC requests that agree. Each case mutates one thing and runs one judge.
"""
import contextlib
import io
import json
import pathlib
import tempfile

FIELD = "DRB.PdcpSduVolumeDL"
SCHED = {"triggers": [
    {"step": 20, "imsi": 3, "kind": "negative", "decision": "none"},
    {"step": 30, "imsi": 1, "kind": "positive", "decision": "handover", "via": 2, "key": "0000000202", "targetCell": 2, "expect": "applied"},
    {"step": 50, "imsi": 1, "kind": "negative", "decision": "none"}]}


def build(d, P, sc, mut):
    rd = d / "run"
    (rd / "trace").mkdir(parents=True)
    (rd / "r3p").mkdir()
    dl = {2: 8371, 3: 4186}
    mem = lambda s: {2: [3, 4, 5, 6] + ([1] if s > 30 else []), 3: [2] + ([] if s > 30 else [1])}
    for n in (2, 3):
        lines = [json.dumps({"type": "hello", "nodeId": n, "kind": "gnb"})]
        lines += [json.dumps({"type": "sample", "nodeId": n, "seq": s, "cell": {"cuUp": {FIELD: dl[n]}},
                              "ues": [{"imsi": i} for i in mem(s)[n]]}) for s in range(60)]
        (rd / "trace" / ("e2-ipc-trace-%d.jsonl" % n)).write_text("\n".join(lines) + "\n")
    cells = {str(n): {str(s): dl[n] for s in range(60)} for n in (2, 3)}
    recs, parts, tx = [], [], []
    for t in SCHED["triggers"]:
        m = {str(i): n for n in (2, 3) for i in mem(t["step"] if not mut.get("stuck") else 0)[n]}
        win = {"T": t["step"], "imsi": t["imsi"], "clipped": False, "cells": cells, "membership": m, "pass": True}
        (rd / "r3p" / ("window-%d.json" % t["step"])).write_text(json.dumps(win))
        (rd / "r3p" / ("n6-%d.json" % t["step"])).write_text(json.dumps({"pass": True}))
        ans = P.answer(sc, win, t["imsi"])
        dec, key = P.decide(sc, ans)
        recs.append({"T": t["step"], "imsi": t["imsi"], "answer": ans, "decision": dec, "target": key})
        sent = {mut.get("ueid", str(t["imsi"])): {(k.lstrip("0") if mut.get("unpadded") else k): [v[0] + mut.get("plus", 0), v[1]] for k, v in ans}}
        if mut.get("order"):
            sent = {u: dict(reversed(list(c.items()))) for u, c in sent.items()}
        parts.append([{"rx": {"mtype": 30000, "payload": json.dumps({"UEPredictionSet": [str(t["imsi"])]})},
                       "tx": {"mtype": 30002, "state": 0, "payload": json.dumps(sent)}}])
        tx.append({"mtype": 30003, "state": 0, "payloadHex": json.dumps([{"ue-id": str(t["imsi"])}]).encode().hex()})
    if mut.get("recplus"):
        recs[1]["answer"][0][1][0] += 1
    (rd / "r3p" / "predictor-records.jsonl").write_text("".join(json.dumps(r) + "\n" for r in recs))
    (rd / "r3p" / "stub-log-before-20.json").write_text("[]")
    (rd / "r3p" / "stub-log-before-30.json").write_text(json.dumps(parts[0]))
    (rd / "r3p" / "stub-log-before-50.json").write_text(json.dumps(parts[1]))
    (rd / "stub-log.json").write_text(json.dumps(parts[2]))
    (rd / "tx.jsonl").write_text("".join(json.dumps(x) + "\n" for x in tx))
    led = [{"type": "ledgerHeader"}] + ([] if mut.get("noapply") else
           [{"viaNodeId": mut.get("via", 2), "imsi": 1, "targetCell": 2, "afterSeq": 30, "rxSeq": 30, "outcome": "applied"}])
    led += mut.get("extra_ledger", [])
    (rd / "ledger.jsonl").write_text("".join(json.dumps(x) + "\n" for x in led))
    (rd / "rc.json").write_text(json.dumps([{"imsi": 1, "step": 30, "viaNode": 2, "targetKey": "0000000202", "answer": "ack"}]
                                           + mut.get("extra_rc", [])))
    rows = [(n, s, None if n == 1 else dl[n]) for n in (1, 2, 3) for s in range(60)]
    if mut.get("drop"):
        rows.remove(mut["drop"])
    rows += [mut["dup"]] if mut.get("dup") else []
    if mut.get("enb"):
        rows = [(n, s, 5 if (n, s) == (1, 0) else v) for n, s, v in rows]
    hdr = ["#datatype,string,long,long,long," + mut.get("dtype", "long"), "#group,false,false,false,false,false",
           "#default,_result,,,,", ",result,table,ns3.nodeId,ns3.seq," + FIELD]
    (rd / "cell.csv").write_text("\n".join(hdr + [",,0,%d,%d,%s" % (n, s, "" if v is None else v) for n, s, v in rows]) + "\n")
    (d / "sched.json").write_text(json.dumps(SCHED))
    (d / "tok.json").write_text(json.dumps({"token": "t" * 40}))
    if mut.get("leak"):
        (rd / "r3p" / "leak.txt").write_text("x" + "t" * 40)
    if mut.get("flat"):
        for t in SCHED["triggers"]:
            w = rd / "r3p" / ("window-%d.json" % t["step"])
            win = json.loads(w.read_text())
            win["cells"]["3"] = win["cells"]["2"]
            w.write_text(json.dumps(win))
    return rd


CASES = [
    # (name, judge, want, mutation)
    ("expect: pass", "expect", True, {}),
    ("expect: a ledger line for a none trigger", "expect", False, {"extra_ledger": [{"viaNodeId": 3, "imsi": 3, "targetCell": 3, "afterSeq": 20, "rxSeq": 20, "outcome": "applied"}]}),
    ("wire: pass", "wire", True, {}),
    ("wire: a request for a none trigger", "wire", False, {"extra_rc": [{"imsi": 1, "step": 50, "viaNode": 3, "targetKey": "0000000303", "answer": "ack"}]}),
    ("stub: pass", "stub", True, {}),
    ("stub: a 30002 value = formula + 1", "stub", False, {"plus": 1}),
    ("stub: serving cell not first", "stub", False, {"order": True}),
    ("stub: a cell key spelled differently (no zero padding; cells 2 and 3 have no hex letters to lowercase)", "stub", False, {"unpadded": True}),
    ("stub: a non-decimal ue-id", "stub", False, {"ueid": "imsi-1"}),
    ("predictor: pass", "predictor", True, {}),
    ("predictor: a record that differs from the formula", "predictor", False, {"recplus": True}),
    ("influx-ipc: pass", "influx-ipc", True, {}),
    ("influx-ipc: a missing seq", "influx-ipc", False, {"drop": (2, 33, 8371)}),
    ("influx-ipc: a duplicate (node, seq)", "influx-ipc", False, {"dup": (3, 12, 4186)}),
    ("influx-ipc: an eNB row carries the counter", "influx-ipc", False, {"enb": True}),
    ("influx-ipc: a double field", "influx-ipc", False, {"dtype": "double"}),
    ("d7: pass", "d7", True, {}),
    ("d7: an applied line not via the target gNB", "d7", False, {"via": 3}),
    ("observation: pass", "observation", True, {}),
    ("observation: equal cells, so the swap changes no decision", "observation", False, {"flat": True}),
    ("membership: pass", "membership", True, {}),
    ("membership: h1's IMSI still on its old cell at m1", "membership", False, {"stuck": True}),
    ("driven: pass", "driven", True, {}),
    ("driven: no applied handover", "driven", False, {"noapply": True}),
    ("secrets: pass", "secrets", True, {}),
    ("secrets: a token in the predictor dir", "secrets", False, {"leak": True}),
]


def argv(judge, d, rd):
    s, sc = str(d / "sched.json"), str(pathlib.Path(__file__).resolve().parent / "r3p-scenario.json")
    return {"expect": [s, str(rd / "ledger.jsonl")], "wire": [s, str(rd / "rc.json")],
            "stub": [s, str(rd), str(rd / "tx.jsonl")], "predictor": [sc, s, str(rd)],
            "influx-ipc": [sc, str(rd), "--cell-csv", str(rd / "cell.csv")], "d7": [str(rd / "ledger.jsonl")],
            "observation": [sc, s, str(rd)], "membership": [s, str(rd)], "driven": [s, str(rd / "ledger.jsonl"), str(rd)],
            "secrets": [str(rd), str(d / "tok.json")]}[judge]


def self_test(C):
    sc = json.load(open(pathlib.Path(__file__).resolve().parent / "r3p-scenario.json"))
    bad = 0
    for name, judge, want, mut in CASES:
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            rd = build(d, C.P, sc, mut)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                got = C.CMDS[judge][0](argv(judge, d, rd)) == 0
        bad += got != want
        print(("ok   " if got == want else "FAIL ") + name + ("" if got == want else ": " + buf.getvalue()[:300]))
    print("r3p checks self-test: %s" % ("ok" if not bad else "%d failure(s)" % bad))
    return 1 if bad else 0

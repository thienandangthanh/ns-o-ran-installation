"""r3p-checks-fixtures.py: synthetic fixtures for r3p-checks.py --self-test (no real data: the repo is public).

A coherent R3′ run: triggers n1 (step 20, IMSI 3, none), h1 (30, IMSI 1, handover to cell 2 via its source en-gNB,
node 3) and m1 (50, IMSI 1, none, now on cell 2); constant per-cell DL; IPC traces, UE context files (the
checkpoint-1 RNTIs, MN cell 1), certified windows, predictor records, stub log parts, injector sends, ledger and
decoded RC requests that agree. Every UE string is the UE's KPM UE ID key U(imsi) (en-gNB-UEID). Each case mutates
one thing and runs one judge.
"""
import contextlib
import io
import json
import pathlib
import tempfile

FIELD = "DRB.PdcpSduVolumeDL"
SCHED = {"triggers": [
    {"step": 20, "imsi": 3, "kind": "negative", "decision": "none"},
    {"step": 30, "imsi": 1, "kind": "positive", "decision": "handover", "via": 3, "key": "0000000210", "targetCell": 2, "expect": "applied"},
    {"step": 50, "imsi": 1, "kind": "negative", "decision": "none"}]}
RNTI = {1: 3, 2: 4, 3: 1, 4: 2, 5: 5, 6: 6}  # IMSI -> MN (eNB) RNTI = m-eNB-UE-X2AP-ID


def U(imsi):
    return "enGnbUeId:%d@00F110-00001" % RNTI[imsi]


def wire_ue(imsi):
    return {"type": "en-gNB-UEID", "mEnbUeX2apId": RNTI[imsi], "globalEnbId": {"plmn": "00F110", "macroEnbId": "00001"}}


def build(d, P, sc, mut):
    rd = d / "run"
    (rd / "trace").mkdir(parents=True)
    (rd / "r3p").mkdir()
    dl = {2: 8371, 3: 4186}
    mem = lambda s: {2: [3, 4, 5, 6] + ([1] if s > 30 else []), 3: [2] + ([] if s > 30 else [1])}
    for n in (2, 3):
        lines = [json.dumps({"type": "hello", "nodeId": n, "kind": "gnb"})]
        lines += [json.dumps({"type": "sample", "nodeId": n, "seq": s, "cell": {"cuUp": {FIELD: dl[n]}},
                              "ues": [{"imsi": i} for i in mem(s)[n]]}) for s in range(mut.get("samples", 100))]
        (rd / "trace" / ("e2-ipc-trace-%d.jsonl" % n)).write_text("\n".join(lines) + "\n")
        ctx = [{"type": "ueContext", "v": 1, "nodeId": n, "seq": s, "ues": [
            {"imsi": i, "lteRnti": RNTI[i], "mnCellId": 1, "mmeUeS1apId": i} for i in sorted(mem(s)[n])]} for s in (0, 31)]
        (rd / "trace" / ("e2-ue-context-%d.jsonl" % n)).write_text("".join(json.dumps(x) + "\n" for x in ctx))
    cells = {str(n): {str(s): dl[n] for s in range(100)} for n in (2, 3)}
    recs, parts, tx = [], [], []
    for t in SCHED["triggers"]:
        m = {str(i): n for n in (2, 3) for i in mem(t["step"] if not mut.get("stuck") else 0)[n]}
        win = {"T": t["step"], "imsi": t["imsi"], "clipped": False, "cells": cells, "membership": m, "pass": True}
        (rd / "r3p" / ("window-%d.json" % t["step"])).write_text(json.dumps(win))
        (rd / "r3p" / ("n6-%d.json" % t["step"])).write_text(json.dumps({"pass": True}))
        ans = P.answer(sc, win, t["imsi"])
        dec, key = P.decide(sc, ans)
        recs.append({"T": t["step"], "imsi": t["imsi"], "answer": ans, "decision": dec, "target": key})
        ue = {"decimal": str(t["imsi"]), "other": U(2)}.get(mut.get("ueid"), U(t["imsi"]))
        sent = {ue: {(k.lstrip("0") if mut.get("unpadded") else k): [v[0] + mut.get("plus", 0), v[1]] for k, v in ans}}
        if mut.get("order"):
            sent = {u: dict(reversed(list(c.items()))) for u, c in sent.items()}
        parts.append([{"rx": {"mtype": 30000, "payload": json.dumps({"UEPredictionSet": [ue]})},
                       "tx": {"mtype": 30002, "state": 0, "payload": json.dumps(sent)}}])
        tx.append({"mtype": 30003, "state": 0, "payloadHex": json.dumps([{"ue-id": ue}]).encode().hex()})
    if mut.get("recplus"):
        recs[1]["answer"][0][1][0] += 1
    if mut.get("n5target"):
        recs[1]["target"] = "0000000202"
    (rd / "r3p" / "predictor-records.jsonl").write_text("".join(json.dumps(r) + "\n" for r in recs))
    (rd / "r3p" / "stub-log-before-20.json").write_text("[]")
    (rd / "r3p" / "stub-log-before-30.json").write_text(json.dumps(parts[0]))
    (rd / "r3p" / "stub-log-before-50.json").write_text(json.dumps(parts[1]))
    (rd / "stub-log.json").write_text(json.dumps(parts[2]))
    (rd / "tx.jsonl").write_text("".join(json.dumps(x) + "\n" for x in tx))
    led = [{"type": "ledgerHeader"}] + ([] if mut.get("noapply") else
           [{"viaNodeId": mut.get("via", 3), "imsi": 1, "sourceCell": 3, "targetCell": 2, "afterSeq": 30, "rxSeq": 30,
             "outcome": "applied"}])
    led += mut.get("extra_ledger", [])
    (rd / "ledger.jsonl").write_text("".join(json.dumps(x) + "\n" for x in led))
    (rd / "rc.json").write_text(json.dumps([{"ueId": wire_ue(1), "step": 30, "viaNode": mut.get("wirevia", 3),
                                             "targetKey": "0000000210", "answer": "ack"}]
                                           + mut.get("extra_rc", [])))
    rows = [(n, s, None if n == 1 else dl[n]) for n in (1, 2, 3) for s in range(mut.get("samples", 100))]
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
    (d / "stage-a.json").write_text(json.dumps({"h1": SCHED["triggers"][1]}))
    if mut.get("noledger"):
        (rd / "ledger.jsonl").unlink()
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
    ("expect: a ledger line for a none trigger", "expect", False, {"extra_ledger": [{"viaNodeId": 2, "imsi": 3, "sourceCell": 2, "targetCell": 3, "afterSeq": 20, "rxSeq": 20, "outcome": "applied"}]}),
    ("expect: h1's line via its target gNB", "expect", False, {"via": 2}),
    ("wire: pass", "wire", True, {}),
    ("wire: a request for a none trigger", "wire", False, {"extra_rc": [{"ueId": wire_ue(1), "step": 50, "viaNode": 2, "targetKey": "0000000310", "answer": "ack"}]}),
    ("wire: h1's request via its target gNB", "wire", False, {"wirevia": 2}),
    ("stub: pass", "stub", True, {}),
    ("stub: a 30002 value = formula + 1", "stub", False, {"plus": 1}),
    ("stub: serving cell not first", "stub", False, {"order": True}),
    ("stub: a cell key spelled differently (no zero padding; cells 2 and 3 have no hex letters to lowercase)", "stub", False, {"unpadded": True}),
    ("stub: the decimal IMSI as ue-id", "stub", False, {"ueid": "decimal"}),
    ("stub: another UE's ueId", "stub", False, {"ueid": "other"}),
    ("predictor: pass", "predictor", True, {}),
    ("predictor: a record that differs from the formula", "predictor", False, {"recplus": True}),
    ("influx-ipc: pass", "influx-ipc", True, {}),
    ("influx-ipc: a missing seq", "influx-ipc", False, {"drop": (2, 33, 8371)}),
    ("influx-ipc: a duplicate (node, seq)", "influx-ipc", False, {"dup": (3, 12, 4186)}),
    ("influx-ipc: an eNB row carries the counter", "influx-ipc", False, {"enb": True}),
    ("influx-ipc: a double field", "influx-ipc", False, {"dtype": "double"}),
    ("influx-ipc: a tail truncated in both IPC and Influx", "influx-ipc", False, {"samples": 90}),
    ("d7: pass", "d7", True, {}),
    ("d7: an applied line not via the source en-gNB", "d7", False, {"via": 2}),
    ("observation: pass", "observation", True, {}),
    ("observation: equal cells, so the swap changes no decision", "observation", False, {"flat": True}),
    ("membership: pass", "membership", True, {}),
    ("membership: h1's IMSI still on its old cell at m1", "membership", False, {"stuck": True}),
    ("driven: pass", "driven", True, {}),
    ("driven: no applied handover", "driven", False, {"noapply": True}),
    ("driven: a predictor target in the old %08X%02X form names no node", "driven", False, {"n5target": True}),
    ("secrets: pass", "secrets", True, {}),
    ("secrets: a token in the predictor dir", "secrets", False, {"leak": True}),
    ("dry-ledger stage A: no ledger file (no control) passes", "dry-ledger-a", True, {"noledger": True}),
    ("dry-ledger stage A: a header-only ledger passes", "dry-ledger-a", True, {"noapply": True}),
    ("dry-ledger stage A: any ledger line fails", "dry-ledger-a", False, {}),
    ("dry-ledger stage B: exactly h1's applied line passes", "dry-ledger-b", True, {}),
    ("dry-ledger stage B: no ledger file fails", "dry-ledger-b", False, {"noledger": True}),
    ("dry-ledger stage B: h1's line via the wrong gNB fails", "dry-ledger-b", False, {"via": 2}),
    ("dry-ledger stage B: an extra line fails", "dry-ledger-b", False, {"extra_ledger": [{"viaNodeId": 2, "imsi": 3, "sourceCell": 2, "targetCell": 3, "afterSeq": 40, "rxSeq": 40, "outcome": "refused", "cause": "late"}]}),
    ("expect: no ledger at all with a scheduled handover fails", "expect", False, {"noledger": True}),
    ("d7: no ledger at all fails", "d7", False, {"noledger": True}),
    ("driven: no ledger at all fails", "driven", False, {"noledger": True}),
]


def argv(judge, d, rd):
    s, sc = str(d / "sched.json"), str(pathlib.Path(__file__).resolve().parent / "r3p-scenario.json")
    return {"expect": [s, str(rd / "ledger.jsonl")], "wire": [s, str(rd / "rc.json"), str(rd / "trace")],
            "stub": [s, str(rd), str(rd / "tx.jsonl")], "predictor": [sc, s, str(rd)],
            "influx-ipc": [sc, str(rd), "--cell-csv", str(rd / "cell.csv")], "d7": [str(rd / "ledger.jsonl")],
            "observation": [sc, s, str(rd)], "membership": [s, str(rd)], "driven": [s, str(rd / "ledger.jsonl"), str(rd)],
            "secrets": [str(rd), str(d / "tok.json")], "dry-ledger-a": [str(rd / "ledger.jsonl")],
            "dry-ledger-b": [str(rd / "ledger.jsonl"), "--h1", str(d / "stage-a.json")]}[judge]


def self_test(C):
    sc = json.load(open(pathlib.Path(__file__).resolve().parent / "r3p-scenario.json"))
    bad = 0
    for name, judge, want, mut in CASES:
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            rd = build(d, C.P, sc, mut)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                got = C.CMDS[judge.replace("-a", "").replace("-b", "") if judge.startswith("dry-") else judge][0](argv(judge, d, rd)) == 0
        bad += got != want
        print(("ok   " if got == want else "FAIL ") + name + ("" if got == want else ": " + buf.getvalue()[:300]))
    print("r3p checks self-test: %s" % ("ok" if not bad else "%d failure(s)" % bad))
    return 1 if bad else 0

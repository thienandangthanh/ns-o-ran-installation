"""n6-fixtures.py: synthetic fixtures for check-n6-influx-window.py --self-test (no real data: the repo is public).

A healthy barrier T = 30 in the R3′ radio config: gNB node 2 lists IMSIs 3-6 with cell DL 8371 kbit, node 3 lists
IMSIs 1-2 with 4186 (disjoint membership); IPC traces (the eNB node 1 with its hello only), the UE context files of
nodes 1-3 from a fixed MN RNTI map, cellMetrics and UeMetrics Flux CSVs (pivoted, typed; UeMetrics with kpimon's
ueId tag column) and a ledger with only its header. Each case mutates one thing.
"""
import json

FIELD = "DRB.PdcpSduVolumeDL"
MEMBERS = {2: [3, 4, 5, 6], 3: [1, 2]}
DL = {2: 8371, 3: 4186}
RNTI = {1: 3, 2: 4, 3: 1, 4: 2, 5: 5, 6: 6}


def ue_id(n, i):
    """kpimon's ueId tag of IMSI i on node n (the eNB node 1: eNB-UEID; a gNB: en-gNB-UEID)."""
    return "enbUeId:%d@%d" % (i, RNTI[i]) if n == 1 else "enGnbUeId:%d@00F110-00001" % RNTI[i]


def build(d, csv, T=30, imsis=(1,), drop_ue=None, ue_node=None, both_ipc=None, drop_cell=None, dup_cell=None,
          past_t=False, dl_off=None, dtype="long", ledger=(), ue_id_at=None):
    (d / "trace").mkdir()
    (d / "trace" / "e2-ipc-trace-1.jsonl").write_text(json.dumps({"type": "hello", "nodeId": 1, "kind": "enb", "periodNs": 100000000}) + "\n")
    for n in (1, 2, 3):
        ues = [{"imsi": i, "lteRnti": RNTI[i], "mnCellId": 1, "mmeUeS1apId": i} for i in sorted(MEMBERS[2] + MEMBERS[3] if n == 1 else MEMBERS[n])]
        (d / "trace" / ("e2-ue-context-%d.jsonl" % n)).write_text(json.dumps({"type": "ueContext", "v": 1, "nodeId": n, "seq": 0, "ues": ues}) + "\n")
    for n in (2, 3):
        lines = [json.dumps({"type": "hello", "nodeId": n, "kind": "gnb", "periodNs": 100000000})]
        for s in range(T + 1):
            ues = [{"imsi": i, "cuUp": {}} for i in MEMBERS[n]]
            if both_ipc and s == T and n == 2:
                ues.append({"imsi": both_ipc, "cuUp": {}})
            lines.append(json.dumps({"type": "sample", "nodeId": n, "seq": s, "cell": {"cuUp": {FIELD: DL[n]}}, "ues": ues}))
        (d / "trace" / ("e2-ipc-trace-%d.jsonl" % n)).write_text("\n".join(lines) + "\n")
    cell_rows = []
    for n in (1, 2, 3):
        for s in range(T + 2 if past_t else T + 1):
            if (n, s) == drop_cell:
                continue
            v = None if n == 1 else DL[n] + (1 if (n, s) == dl_off else 0)
            cell_rows.append([n, s, v])
            if (n, s) == dup_cell:
                cell_rows.append([n, s, v])
    ue_rows = []
    for n in (1, 2, 3):
        for s in range(T + 1):
            for i in (MEMBERS[2] + MEMBERS[3] if n == 1 else MEMBERS[n]):
                if (n, s, i) == drop_ue:
                    continue
                node = ue_node if (ue_node and s == T and i == 1 and n == 3) else n
                ue_rows.append([node, s, i, (ue_id_at or {}).get((n, s, i), ue_id(n, i))])
    ledger_path = d / "ledger.jsonl"
    ledger_path.write_text("\n".join([json.dumps({"type": "ledgerHeader"})] + [json.dumps(x) for x in ledger]) + "\n")
    return {"T": T, "imsis": list(imsis), "trace": str(d / "trace"), "ledger": str(ledger_path),
            "cell": csv(["ns3.nodeId", "ns3.seq", FIELD], ["long", "long", dtype], cell_rows),
            "ue": csv(["ns3.nodeId", "ns3.seq", "ns3.imsi", "ueId"], ["long", "long", "long", "string"], ue_rows)}


APPLIED_TO_2_AT_29 = {"imsi": 1, "outcome": "applied", "targetCell": 2, "viaNodeId": 2, "rxSeq": 29}
APPLIED_TO_3_AT_30 = {"imsi": 1, "outcome": "applied", "targetCell": 3, "viaNodeId": 3, "rxSeq": 30}

# (name, want pass, build kwargs)
CASES = [
    ("healthy disjoint membership, one IMSI", True, {}),
    ("healthy, every IMSI (dry-run observe)", True, {"imsis": (1, 2, 3, 4, 5, 6)}),
    ("a missing UE row at T", False, {"drop_ue": (3, 30, 1)}),
    ("the UE row at T on the wrong gNB", False, {"ue_node": 2}),
    ("an IMSI listed by both gNBs in IPC", False, {"both_ipc": 1}),
    ("a missing cell row in the window", False, {"drop_cell": (3, 20)}),
    ("a duplicate cell row", False, {"dup_cell": (2, 25)}),
    ("a row past T", False, {"past_t": True}),
    ("Influx DL differs from IPC", False, {"dl_off": (2, 28)}),
    ("a double-typed counter", False, {"dtype": "double"}),
    ("the last applied line targets a cell that does not list the IMSI", False, {"ledger": (APPLIED_TO_2_AT_29,)}),
    ("a handover applied at T (in progress)", False, {"ledger": (APPLIED_TO_3_AT_30,)}),
    ("the eNB's UeMetrics rows are never read (one dropped: still healthy)", True, {"drop_ue": (1, 30, 5)}),
    ("a UE row at T without ueId", False, {"ue_id_at": {(3, 30, 1): None}}),
    ("a ueId that resolves to another IMSI than the row's", False, {"ue_id_at": {(3, 30, 1): ue_id(3, 2)}}),
    ("a ueId absent from the UE context", False, {"ue_id_at": {(2, 12, 3): "enGnbUeId:99@00F110-00001"}}),
]

"""check-pdcp-volume-totals-fixtures.py: synthetic fixtures for check-pdcp-volume-totals.py --self-test.

A healthy UL-on run in miniature: the MN cell 1 (audit node 0) and the en-gNB cells 2 and 3 (audit nodes 1 and 2,
IPC trace nodes 2 and 3), read at 0.8 ms and 100.8 ms (seq 0 and 1), stopped at T = 200 ms. Cell 2 serves IMSI 3:
one X2-leg and one LTE-leg DL PDU, one UL PDU over X2. Cell 3 serves IMSI 4: two X2-leg DL PDUs, one UL PDU over X2.
Every PDU is 1310 B, a 1308 B SDU = 10464 bits. Both gNB traces carry all four cuUp keys. Each case changes one
thing and names the exact set of conjuncts that must be false (empty: the run passes).
"""
import json
import pathlib
import tempfile

T0, T1, STOP = 800000, 100800000, 200000000
HDR_LINE = "N4AUDIT v2 hdr=2 class=ns3::NrPdcpHeader"
END_LINE = "N4AUDIT end connected=2 present=2 missing=0"
DL2 = "N4AUDIT dltx 50000000 0 1 3 3 1310 2"
X2DL2 = "N4AUDIT x2dl 51000000 1 2 1 7 1310"
LTE2 = "N4AUDIT dltx 60000000 0 1 3 3 1310 0"
X2UL2 = "N4AUDIT x2ul 70000000 1 2 1 8 1310"
UL2 = "N4AUDIT ulrx 71000000 0 1 3 3 1310 2000000 2"
DL3A = "N4AUDIT dltx 52000000 0 1 4 3 1310 3"
X2DL3A = "N4AUDIT x2dl 53000000 2 3 1 17 1310"
DL3B = "N4AUDIT dltx 54000000 0 1 4 3 1310 3"
X2DL3B = "N4AUDIT x2dl 55000000 2 3 1 17 1310"
X2UL3 = "N4AUDIT x2ul 72000000 2 3 1 18 1310"
UL3 = "N4AUDIT ulrx 73000000 0 1 4 3 1310 2000000 3"
FWD = "N4AUDIT x2dl 56000000 2 3 2 9 1310"  # cell 3 receives from cell 2: forwarded en-gNB to en-gNB
AUDIT = [HDR_LINE, DL2, X2DL2, LTE2, X2UL2, UL2, DL3A, X2DL3A, DL3B, X2DL3B, X2UL3, UL3, END_LINE]
# per IPC node, seq 1's (X2UL, X2DL): cell 2 10 / 10 kbit, cell 3 10 / 21 kbit (20928 bits); seq 0 reads nothing
COUNTERS = {2: (10, 10), 3: (10, 21)}


def samples(counters=None, own=None, extra=()):
    """{node: [(seq, t, x2ul, x2dl, ownUl, ownDl)]} from seq 1's counters; `own` overrides (node, seq) own keys."""
    counters = {**COUNTERS, **(counters or {})}
    own = own or {}
    out = {}
    for n, (ul, dl) in counters.items():
        out[n] = [(0, T0, 0, 0) + own.get((n, 0), (0, 0)), (1, T1, ul, dl) + own.get((n, 1), (0, 0))]
    for n, row in extra:
        out[n].append(row)
    return out


def write_fixture(root, audit, smp, tail_hellos=None):
    """RUN_DIR with ns3run/stdout.txt (the audit among other stdout) and one gNB IPC trace per node; `tail_hellos`
    {node: [periodNs]} appends further hello lines after that node's samples."""
    (root / "ns3run").mkdir(parents=True)
    (root / "trace").mkdir()
    (root / "ns3run" / "stdout.txt").write_text("noise\n" + "\n".join(audit) + "\n")
    for node, rows in smp.items():
        lines = [json.dumps({"type": "hello", "nodeId": node, "kind": "gnb", "periodNs": 100000000})]
        for seq, t, x2ul, x2dl, ul, dl in rows:
            cu = {"DRB.PdcpSduVolumeUL": ul, "DRB.PdcpSduVolumeDL": dl,
                  "DRB.PdcpSduVolumeX2UL": x2ul, "DRB.PdcpSduVolumeX2DL": x2dl}
            lines.append(json.dumps({"type": "sample", "nodeId": node, "seq": seq, "simTimeNs": t, "cell": {"cuUp": cu},
                                     "ues": [{"imsi": 3 if node == 2 else 4, "cuUp": {}}]}))
        for period in (tail_hellos or {}).get(node, []):
            lines.append(json.dumps({"type": "hello", "nodeId": node, "kind": "gnb", "periodNs": period}))
        (root / "trace" / f"e2-ipc-trace-{node}.jsonl").write_text("\n".join(lines) + "\n")
    return root


def shifted(audit, dt):
    """The audit with every event's tNs (the third token of dltx, ulrx, x2dl and x2ul) moved by dt."""
    out = []
    for x in audit:
        f = x.split(" ")
        if f[1] in ("dltx", "ulrx", "x2dl", "x2ul"):
            f[2] = str(int(f[2]) + dt)
        out.append(" ".join(f))
    return out


def without(*drop):
    return [x for x in AUDIT if x not in drop]


def plus(*add):
    return AUDIT[:-1] + list(add) + [END_LINE]


def swap(old, new, audit=None):
    return [new if x == old else x for x in (audit or AUDIT)]


S = samples()
ZERO = samples({2: (0, 0), 3: (0, 0)})
# (name, audit, samples, conjuncts that must be false[, expected gNB nodes[, expected seqs per node[, tail hellos]]]);
# default [2, 3], 2, none
CASES = [
    ("pass", AUDIT, S, set()),
    ("pass, a forwarded x2dl inside the receiving cell's X2DL", plus(FWD), samples({3: (10, 31)}), set()),
    ("pass, residual after the final read",
     plus("N4AUDIT dltx 150000000 0 1 3 3 1310 2", "N4AUDIT x2dl 151000000 1 2 1 7 1310",
          "N4AUDIT x2ul 160000000 2 3 1 18 1310", "N4AUDIT ulrx 161000000 0 1 4 3 1310 2000000 3"), S, set()),
    ("pass, a UL PDU in flight at the stop", plus("N4AUDIT x2ul 199500000 1 2 1 8 1310"), S, set()),
    ("pass, a UL PDU sent at the stop instant", plus("N4AUDIT x2ul 200000000 1 2 1 8 1310"), S, set()),
    ("pass, a late transfer completed before the stop",
     plus("N4AUDIT dltx 198500000 0 1 3 3 1310 2", "N4AUDIT x2dl 199500000 1 2 1 7 1310"), S, set()),
    # the counter as ns-3 reported it before: all MN DL volume of the cell's UE, both legs
    ("X2DL equals all MN DL volume of both legs", AUDIT, samples({2: (10, 21)}), {"a4"}),
    ("X2DL swapped between cells 2 and 3, same sum", AUDIT, samples({2: (10, 21), 3: (10, 10)}), {"a4"}),
    ("DRB.PdcpSduVolumeDL = 1 on one gNB sample", AUDIT, samples(own={(3, 1): (0, 1)}), {"a7"}),
    ("DRB.PdcpSduVolumeUL = 1 on one gNB sample", AUDIT, samples(own={(2, 0): (1, 0)}), {"a7"}),
    ("only LTE-leg dltx", [HDR_LINE, DL2[:-1] + "0", LTE2, X2UL2, UL2, DL3A[:-1] + "0", X2UL3, UL3, END_LINE],
     samples({2: (10, 0), 3: (10, 0)}), {"a6"}),
    ("only X2-leg dltx", without(LTE2), S, {"a6"}),
    ("no x2ul", [x for x in swap(UL3, UL3[:-1] + "0", swap(UL2, UL2[:-1] + "0")) if x not in (X2UL2, X2UL3)],
     samples({2: (0, 10), 3: (0, 21)}), {"a6"}),
    ("a v1 header", swap(HDR_LINE, HDR_LINE.replace("v2", "v1")), S, {"a1"}),
    ("a forwarded x2dl left out of the receiving cell's X2DL", plus(FWD), S, {"a4"}),
    ("a forwarded x2dl credited to the source cell", plus(FWD), samples({2: (10, 20)}), {"a4"}),
    ("an x2dl at the eNB cell", plus("N4AUDIT x2dl 57000000 0 1 2 9 1310"), S, {"a4"}),
    ("an x2dl whose source is its own cell", plus("N4AUDIT x2dl 57000000 1 2 2 9 1310"), samples({2: (10, 20)}), {"a4"}),
    ("an x2ul to a gNB cell", plus("N4AUDIT x2ul 74000000 1 2 3 8 1310"), samples({2: (20, 10)}), {"a4"}),
    ("a dltx whose leg is no gNB cell", plus("N4AUDIT dltx 58000000 0 1 3 3 1310 9"), S, {"a4"}),
    ("a dltx at a gNB cell", plus("N4AUDIT dltx 58000000 0 2 3 3 1310 0"), S, {"a4"}),
    ("an X2-leg dltx with no x2dl at its cell", without(X2DL3B), samples({3: (10, 10)}), {"a8"}),
    ("an x2dl from the MN with no dltx", without(DL3B), S, {"a8"}),
    ("an x2ul with no ulrx", without(UL3), S, {"a8"}),
    ("a ulrx with no x2ul", without(X2UL3), samples({3: (0, 21)}), {"a8"}),
    ("an early X2-leg dltx with no x2dl, just before the in-flight window",
     plus("N4AUDIT dltx 198000000 0 1 3 3 1310 2"), S, {"a8"}),
    ("a tie on an x2dl", plus("N4AUDIT dltx 99000000 0 1 3 3 1310 2", "N4AUDIT x2dl 100800000 1 2 1 7 1310"), S,
     {"a4"}),
    ("a dltx with an extra token", plus("N4AUDIT dltx 58000000 0 1 3 3 1310 0 9"), S, {"a1"}),
    ("an x2ul with a negative size", plus("N4AUDIT x2ul 74000000 1 2 1 8 -1310"), S, {"a1"}),
    ("a number with a leading zero", plus("N4AUDIT dltx 058000000 0 1 3 3 1310 0"), S, {"a1"}),
    ("an x2 event after its cell's last read, which is not the run's final read",
     plus("N4AUDIT dltx 100650000 0 1 4 3 1310 3", "N4AUDIT x2dl 100750000 2 3 1 17 1310"),
     {2: S[2], 3: [(0, T0 - 100000) + S[3][0][2:], (1, T1 - 100000) + S[3][1][2:]]}, {"a4"}),
    ("a float X2 counter", AUDIT, samples({2: (10, 10.0)}), {"a4"}),
    ("a missing X2 counter", AUDIT, samples({2: (None, 10)}), {"a4"}),
    ("X2UL off by 1 kbit", AUDIT, samples({2: (11, 10)}), {"a4"}),
    ("a missing gNB cell", AUDIT, S, {"a0"}, [2, 3, 4]),
    # read instants off the trace's cadence: collapsed, every event becomes residual and zero counters would pass A4
    ("collapsed read instants with zero counters", AUDIT,
     {n: [(0, 0, 0, 0, 0, 0), (1, 0, 0, 0, 0, 0)] for n in (2, 3)}, {"a0"}),
    ("one read off cadence", AUDIT, {2: [S[2][0], (1, T1 + 1) + S[2][1][2:]], 3: S[3]}, {"a0"}),
    ("seq 0 read at sim time 0", AUDIT, {2: [(0, 0) + S[2][0][2:], (1, T1 - T0) + S[2][1][2:]], 3: S[3]}, {"a0"}),
    # audit events outside the run (0, T]: never residual; shifted 1 s past the stop, zero counters would pass A4
    ("every audit event shifted beyond the stop, zero X2 counters", shifted(AUDIT, 1000000000), ZERO, {"a1"}),
    ("an audit event at sim time 0", plus("N4AUDIT dltx 0 0 1 3 3 1310 0"), S, {"a1"}),
    ("an int hello followed by an equal-valued float hello", AUDIT, S, {"a0"}, [2, 3], 2, {2: [100000000.0]}),
    ("a hello period that is a bool", AUDIT, S, {"a0"}, [2, 3], 2, {3: [True]}),
    ("seq 0 read at the period", AUDIT,
     {2: [(0, 100000000) + S[2][0][2:], (1, 200000000) + S[2][1][2:]], 3: S[3]}, {"a0", "a4"}),
    ("a truncated tail", AUDIT, S, {"a0"}, [2, 3], 3),
    ("a duplicate seq", AUDIT, samples(extra=[(2, (1, T1, 10, 10, 0, 0))]), {"a0", "a4"}),
    ("an unexpected gNB node", AUDIT, S, {"a0", "a4"}, [2, 4]),
    ("an unconnected PDCP", swap(END_LINE, "N4AUDIT end connected=2 present=3 missing=1"), S, {"a1"}),
    ("no end line", without(END_LINE), S, {"a1"}),
    ("two end lines", AUDIT + [END_LINE], S, {"a1"}),
    ("two header lines", [HDR_LINE] + AUDIT, S, {"a1"}),
    ("header size 3", swap(HDR_LINE, HDR_LINE.replace("hdr=2", "hdr=3")), S, {"a1"}),
    ("header class LtePdcpHeader", swap(HDR_LINE, HDR_LINE.replace("NrPdcpHeader", "LtePdcpHeader")), S, {"a1"}),
    ("header line without a class", swap(HDR_LINE, "N4AUDIT v2 hdr=2"), S, {"a1"}),
    ("header class with a trailing field", swap(HDR_LINE, HDR_LINE + " x"), S, {"a1"}),
    ("UL SDU of 40 B", plus("N4AUDIT ulrx 74000000 0 1 4 3 42 1000 0"), S, {"a5"}),
    ("PDU counted at two RRCs", plus("N4AUDIT ulrx 71000000 7 9 3 3 1310 2000000 0"), S, {"a2", "a3"}),
]


def self_test(C):
    bad = 0
    for name, audit, smp, want_false, *exp in CASES:
        nodes, n_seq, tail_hellos = (exp + [[2, 3], 2, None][len(exp):])[:3]
        with tempfile.TemporaryDirectory() as t:
            v = C.judge(write_fixture(pathlib.Path(t), audit, smp, tail_hellos), nodes, n_seq, STOP)
        got_false = {"a%d" % k for k in range(9) if not v["a%d" % k]}
        ok = got_false == want_false and v["pass"] == (not want_false)
        bad += not ok
        print(("ok   " if ok else "FAIL ") + name + ("" if ok else ": false %s, want %s" % (sorted(got_false), sorted(want_false))))
    print("PDCP volume audit judge self-test: %s" % ("ok" if not bad else "%d failure(s)" % bad))
    return 1 if bad else 0

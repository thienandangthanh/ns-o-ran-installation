#!/usr/bin/env python3
"""n4-drop-selftest.py: fixtures for digest-run.py --n4-ul-off-drop.

A UL-off run that carries the two gNB CU-UP PDCP SDU volume keys must digest equal to the
same run without them, and every broken precondition must make the comparison fail:
a missing key, UL = 1, DL never positive, a float, an extra key, a reference that carries
the keys, and an eNB sample that carries one. Exit 0 only if every case behaves.
"""
import copy
import json
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
UL, DL = "DRB.PdcpSduVolumeUL", "DRB.PdcpSduVolumeDL"


def hello(node, kind):
    return {"type": "hello", "schema": "ns3-e2-ipc", "v": 1, "nodeId": node, "kind": kind}


def sample(node, seq, cu_up, ues=True):
    ue = {"imsi": 3, "du": {"x.UEID": 1}, "cuUp": {"y.UEID": 2}}
    return {"type": "sample", "v": 1, "nodeId": node, "seq": seq, "simTimeNs": 800000 + seq * 10**8,
            "ipcDropped": 0, "cell": {"du": {"TB.TotNbrDl.1": seq}, "cuUp": cu_up, "cuCp": {"numActiveUes": 1}},
            "ues": [ue] if ues else []}


def base():
    """The UL-off reference: an eNB node 1 and a gNB node 2 with an empty cuUp."""
    return {1: [hello(1, "enb"), sample(1, 1, {"pDCPBytesDL": 5}), sample(1, 2, {"pDCPBytesDL": 6})],
            2: [hello(2, "gnb"), sample(2, 1, {}), sample(2, 2, {})]}


def with_keys(dl=(0, 8371)):
    run = base()
    for msg, v in zip(run[2][1:], dl):
        msg["cell"]["cuUp"] = {UL: 0, DL: v}
    return run


def write(root, label, run):
    d = root / label / "trace"
    d.mkdir(parents=True)
    for node, msgs in run.items():
        (d / f"e2-ipc-trace-{node}.jsonl").write_text("".join(json.dumps(m) + "\n" for m in msgs))
    return root / label


def compare(ref, cand):
    with tempfile.TemporaryDirectory() as t:
        root = pathlib.Path(t)
        a, b = write(root, "REF", ref), write(root, "CAND", cand)
        p = subprocess.run([sys.executable, "-I", str(HERE / "digest-run.py"), "--compare", "--components", "ipc",
                            "--n4-ul-off-drop", "REF=absent,CAND=present", f"REF={a}", f"CAND={b}"],
                           capture_output=True, text=True)
        return p.returncode


def mutate(fn):
    run = with_keys()
    fn(run)
    return run


CASES = [
    ("pass: both keys, UL 0, DL > 0", base(), with_keys(), 0),
    ("fail: a missing key", base(), mutate(lambda r: r[2][1]["cell"]["cuUp"].pop(UL)), 1),
    ("fail: UL = 1", base(), mutate(lambda r: r[2][2]["cell"]["cuUp"].update({UL: 1})), 1),
    ("fail: DL never positive", base(), with_keys(dl=(0, 0)), 1),
    ("fail: DL as a float", base(), mutate(lambda r: r[2][2]["cell"]["cuUp"].update({DL: 8371.0})), 1),
    ("fail: an extra key", base(), mutate(lambda r: r[2][2]["cell"]["cuUp"].update({"DRB.Other": 1})), 1),
    ("fail: the reference carries the keys", with_keys(), with_keys(), 1),
    ("fail: an eNB sample carries a key", base(), mutate(lambda r: r[1][1]["cell"]["cuUp"].update({DL: 1})), 1),
    ("fail: a UE section carries a key", base(), mutate(lambda r: r[2][1]["ues"][0]["cuUp"].update({UL: 0})), 1),
]


def main():
    bad = 0
    for name, ref, cand, want in CASES:
        got = compare(copy.deepcopy(ref), copy.deepcopy(cand))
        ok = (got == 0) == (want == 0)
        bad += not ok
        print(("ok   " if ok else "FAIL ") + name + f" (exit {got})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

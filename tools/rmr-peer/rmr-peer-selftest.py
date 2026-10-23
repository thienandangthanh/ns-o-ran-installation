#!/usr/bin/env python3
"""rmr-peer-selftest.py: checks the stub's prediction builder and an injector -> RMR receiver loopback.

Runs inside the rmr-peer image (no RIC needed): the injector is started as a subprocess with a static seed
route to this process's RMR port, and one anomaly request must arrive here as 30003 with the exact payload.
Exit 0 when every check passes.
"""
import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check(cond, what, problems):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        problems.append(what)


def main():
    problems = []
    stub = load("stub-qp-rmr-peer")
    table = {"3": [[["0000000202", [100, 0]], ["0000000303", [200, 0]]]]}
    counts = {}
    ans, _ = stub.build_prediction(table, counts, b'{"UEPredictionSet": ["3"]}')
    check(ans == b'{"3":{"0000000202":[100,0],"0000000303":[200,0]}}', "prediction keeps the table's cell order", problems)
    ans2, note = stub.build_prediction(table, counts, b'{"UEPredictionSet": ["3"]}')
    check(ans2 is None and "no prediction left" in note, "a used-up UE gets no answer", problems)
    ans3, _ = stub.build_prediction(table, {}, b'{"UEPredictionSet": ["3", "4"]}')
    check(ans3 is None, "a request naming two UEs gets no answer", problems)
    ans4, _ = stub.build_prediction(table, {}, b'{"UEPredictionSet": []}')
    check(ans4 is None, "an empty UE list gets no answer", problems)

    inj = load("rmr-injector")
    want = inj.anomaly_payload("3")
    check(json.loads(want) == [{"du-id": 1010, "ue-id": "3", "measTimeStampRf": 0, "Degradation": "RSRP RSSINR"}],
          "anomaly payload: one UE, ue-id a JSON string", problems)

    d = tempfile.mkdtemp()
    seed = os.path.join(d, "seed.rt")
    with open(seed, "w") as f:
        f.write("newrt|start\nmse|30003|-1|127.0.0.1:4593\nnewrt|end\n")
    env = dict(os.environ, RMR_SEED_RT=seed, RMR_RTG_SVC="-1", RMR_SRC_ID="127.0.0.1")
    os.environ.update(RMR_SEED_RT=seed, RMR_RTG_SVC="-1")
    from ricxappframe.rmr import rmr
    ctx = rmr.rmr_init(b"4593", rmr.RMR_MAX_RCV_BYTES, rmr.RMRFL_NONE)
    p = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "rmr-injector.py"), "--rmr-port", "4592",
                          "--ctl-port", "38599", "--out", d], env=env, stdout=subprocess.PIPE, text=True)
    try:
        line = p.stdout.readline()
        check(line.startswith("READY"), "injector ready: %s" % line.strip(), problems)
        s = socket.create_connection(("127.0.0.1", 38599), timeout=10)
        s.sendall(b'{"op": "anomaly", "ue": "3"}\n')
        reply = json.loads(s.makefile().readline())
        check(reply.get("ok") is True, "injector reply %r" % reply, problems)
        buf, got = None, None
        deadline = time.time() + 10
        while time.time() < deadline:
            buf = rmr.rmr_torcv_msg(ctx, buf, 500)
            summ = rmr.message_summary(buf)
            if summ[rmr.RMR_MS_MSG_STATE] == rmr.RMR_OK:
                got = (summ[rmr.RMR_MS_MSG_TYPE], rmr.get_payload(buf))
                break
        check(got == (30003, want), "loopback received 30003 with the exact payload: %r" % (got,), problems)
    finally:
        p.terminate()
        p.wait(5)
    print(json.dumps({"pass": not problems, "problems": problems}))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

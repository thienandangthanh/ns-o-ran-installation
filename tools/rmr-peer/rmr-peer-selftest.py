#!/usr/bin/env python3
"""rmr-peer-selftest.py: checks the stub's prediction builder, an injector -> RMR receiver loopback, the injector's
meid-routed RIC control, and that the injector and the stub survive idle receive timeouts.

Runs inside the rmr-peer image (no RIC needed): the injector and the stub are started as subprocesses with one
static seed route table. One anomaly request must arrive here as 30003 with the exact payload; one control request
for a meid in the seed meid map must arrive here as 12040 with that meid and the exact payload, and one for a meid
outside the map must be refused by RMR (no endpoint: routing is by meid, not by type alone); after an idle
wait the injector must still run and log one message sent to it; the stub must stay up while idle, answer one
30000 with 30002, stay up after a second idle wait and log exactly that one request.
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
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MEID = "en_gnb_001_001_00000003"
# a RICcontrolRequest from the independent codec (e2-probe-node.py control --requestor 1 --instance 5 --func 3
# --imsi 2 --target-gnb 3); RMR carries it as opaque octets
CONTROL_HEX = ("00040052000004001d000500000100050005000200030016001716006000020000f1100100000001000000010103000000"
               "001700212000000100004400000001440000000244000000032a00090000f1100000000310")


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check(cond, what, problems):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        problems.append(what)


def rcv(rmr, ctx, mtype, timeout, with_meid=False):
    """(mtype, payload[, meid]) of the first message of that type within timeout seconds, else None."""
    buf, deadline = None, time.time() + timeout
    while time.time() < deadline:
        buf = rmr.rmr_torcv_msg(ctx, buf, 500)
        if not buf:  # RMR returns no buffer when the wait times out and none was passed in (a NULL pointer)
            continue
        summ = rmr.message_summary(buf)
        if summ[rmr.RMR_MS_MSG_STATE] == rmr.RMR_OK and summ[rmr.RMR_MS_MSG_TYPE] == mtype:
            got = (mtype, rmr.get_payload(buf))
            return got + (rmr.rmr_get_meid(buf).decode(),) if with_meid else got
    return None


def send(rmr, ctx, mtype, payload):
    """True when RMR accepted the message."""
    m = rmr.rmr_alloc_msg(ctx, max(2048, len(payload)))
    rmr.set_payload_and_length(payload, m)
    m.contents.mtype, m.contents.sub_id = mtype, -1
    for _ in range(50):
        m = rmr.rmr_send_msg(ctx, m)
        if m.contents.state != rmr.RMR_ERR_RETRY:
            break
        time.sleep(0.05)
    ok = m.contents.state == rmr.RMR_OK
    rmr.rmr_free_msg(m)
    return ok


def http(url, data=None, method="GET"):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method), timeout=5) as r:
            return r.status, r.read().decode()
    except OSError as ex:
        return None, str(ex)


def main():
    problems = []
    stub = load("stub-qp-rmr-peer")
    table = {"3": [[["0000000210", [100, 0]], ["0000000310", [200, 0]]]]}
    counts = {}
    ans, _ = stub.build_prediction(table, counts, b'{"UEPredictionSet": ["3"]}')
    check(ans == b'{"3":{"0000000210":[100,0],"0000000310":[200,0]}}', "prediction keeps the table's cell order", problems)
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
        # 4593 this process, 4592 the injector, 4594 the stub
        f.write("newrt|start\nmse|30003|-1|127.0.0.1:4593\nmse|30002|-1|127.0.0.1:4593\n"
                "mse|30004|-1|127.0.0.1:4592\nmse|30000|-1|127.0.0.1:4594\nmse|12040|-1|%%meid\nnewrt|end\n"
                "meid_map|start\nmme_ar|127.0.0.1:4593|%s\nmeid_map|end|1\n" % MEID)
    env = dict(os.environ, RMR_SEED_RT=seed, RMR_RTG_SVC="-1", RMR_SRC_ID="127.0.0.1")
    os.environ.update(RMR_SEED_RT=seed, RMR_RTG_SVC="-1")
    from ricxappframe.rmr import rmr
    ctx = rmr.rmr_init(b"4593", rmr.RMR_MAX_RCV_BYTES, rmr.RMRFL_NONE)
    while rmr.rmr_ready(ctx) == 0:
        time.sleep(0.1)
    p = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "rmr-injector.py"), "--rmr-port", "4592",
                          "--ctl-port", "38599", "--out", d], env=env, stdout=subprocess.PIPE, text=True)
    try:
        line = p.stdout.readline()
        check(line.startswith("READY"), "injector ready: %s" % line.strip(), problems)
        s = socket.create_connection(("127.0.0.1", 38599), timeout=10)
        s.sendall(b'{"op": "anomaly", "ue": "3"}\n')
        reply = json.loads(s.makefile().readline())
        check(reply.get("ok") is True, "injector reply %r" % reply, problems)
        got = rcv(rmr, ctx, 30003, 10)
        check(got == (30003, want), "loopback received 30003 with the exact payload: %r" % (got,), problems)
        s.sendall(json.dumps({"op": "control", "meid": MEID, "hex": CONTROL_HEX}).encode() + b"\n")
        reply = json.loads(s.makefile().readline())
        check(reply.get("ok") is True, "injector control reply %r" % reply, problems)
        got = rcv(rmr, ctx, 12040, 10, with_meid=True)
        check(got == (12040, bytes.fromhex(CONTROL_HEX), MEID),
              "loopback received 12040 with the meid and the exact payload: %r" % (got,), problems)
        s.sendall(json.dumps({"op": "control", "meid": "en_gnb_001_001_00000009", "hex": CONTROL_HEX}).encode() + b"\n")
        reply = json.loads(s.makefile().readline())
        check(reply.get("ok") is False, "a control for a meid outside the map is refused by RMR: %r" % reply, problems)
        s.sendall(b'{"op": "control", "meid": "", "hex": "00"}\n')
        reply = json.loads(s.makefile().readline())
        check(reply.get("ok") is False and "meid" in reply.get("error", ""), "a control without a meid is refused: %r"
              % reply, problems)
        time.sleep(2.5)
        check(p.poll() is None, "injector still running after 2.5 s of idle receive timeouts", problems)
        check(send(rmr, ctx, 30004, b"idle-check"), "sent one 30004 to the injector", problems)
        n, deadline = 0, time.time() + 5
        while time.time() < deadline and n < 1:
            time.sleep(0.2)
            with open(os.path.join(d, "rx.jsonl")) as f:
                n = sum(1 for _ in f)
        check(n == 1 and p.poll() is None, "injector logged exactly 1 received message (%d) and still runs" % n, problems)
    finally:
        p.terminate()
        p.wait(5)

    out = open(os.path.join(d, "stub.log"), "w")
    q = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "stub-qp-rmr-peer.py"), "--rmr-port", "4594",
                          "--http-port", "38598"], env=env, stdout=out, stderr=subprocess.STDOUT)
    base = "http://127.0.0.1:38598"
    try:
        deadline = time.time() + 20
        while time.time() < deadline and http(base + "/health")[0] != 200:
            time.sleep(0.2)
        time.sleep(2.5)
        check(q.poll() is None and http(base + "/health")[0] == 200, "stub up and healthy after 2.5 s idle", problems)
        code, _ = http(base + "/table", json.dumps({"predictions": table}).encode(), "PUT")
        check(code == 200, "stub accepted a table", problems)
        check(send(rmr, ctx, 30000, b'{"UEPredictionSet": ["3"]}'), "sent one 30000 to the stub", problems)
        got = rcv(rmr, ctx, 30002, 10)
        check(got == (30002, b'{"3":{"0000000210":[100,0],"0000000310":[200,0]}}'),
              "stub answered 30002 with the table's prediction: %r" % (got,), problems)
        time.sleep(2.5)
        code, body = http(base + "/log")
        rx = [r for r in json.loads(body)] if code == 200 else []
        check(q.poll() is None and len(rx) == 1 and rx[0]["rx"]["mtype"] == 30000,
              "stub still up after a second idle wait and logged exactly 1 request (%d)" % len(rx), problems)
    finally:
        q.terminate()
        q.wait(5)
        out.close()
        if problems:
            print(open(os.path.join(d, "stub.log")).read()[-2000:])
    print(json.dumps({"pass": not problems, "problems": problems}))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

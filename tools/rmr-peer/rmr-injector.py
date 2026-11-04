#!/usr/bin/env python3
"""rmr-injector.py: a persistent RMR sender for gate r2, the stray-ack probe and the RIC control injector.

Two deployments:
  - on the VM host network (gate r2, the stray-ack probe): it loads only its static seed route table
    (RMR_SEED_RT; RMR_RTG_SVC=-1 turns the route-manager collector off), so every message goes where the gate's
    seed file says (the TS xApp's RMR Service), never where rtmgr would route it;
  - as the xApp ric-control-injector (xapp-descriptor-ric-control-injector/): routes come from rtmgr like any
    registered xApp's, so a 12040 RIC_CONTROL_REQ with a meid goes to the e2term that serves that E2 node
    (rtmgr's sender-qualified entry "mse|12040,<this xApp>|-1|%meid" and its meid map), the way rc's do.
A persistent process keeps a trigger's cost to one local TCP round trip.

Control socket on 127.0.0.1:--ctl-port, one JSON request per line, one JSON reply per line:
  {"op": "anomaly", "ue": "<ue-id>"}   30003 TS_ANOMALY_UPDATE, payload
                                      [{"du-id": 1010, "ue-id": "<ue-id>", "measTimeStampRf": 0,
                                        "Degradation": "RSRP RSSINR"}]  (one UE, its ue-id a JSON string)
  {"op": "raw", "mtype": N, "subId": S, "hex": "<payload hex>"}   any message (the stray-ack probe)
  {"op": "control", "meid": "<ranName>", "hex": "<E2AP PDU hex>"}  12040 RIC_CONTROL_REQ, subId -1, that meid
                                      (an E2AP RICcontrolRequest from the independent codec; e2term forwards the
                                      payload to the E2 node as it is)
  reply {"ok": true|false, "state": <rmr state>, "tries": n, "sendS": seconds in rmr_send}
Logs in --out: tx.jsonl (every send) and rx.jsonl (everything received, e.g. the TS xApp's 30004 acks, or the
12041/12042 e2term returns for a control), each with the meid and the payload hex.
Prints READY once RMR is ready and the control socket listens on --ctl-host:--ctl-port. --ready-timeout 0 waits
for RMR without a limit (an xApp gets its first route table only after it is registered).
"""
import argparse
import json
import os
import socket
import socketserver
import sys
import threading
import time
import traceback

TS_ANOMALY_UPDATE, RIC_CONTROL_REQ = 30003, 12040


def anomaly_payload(ue):
    return json.dumps([{"du-id": 1010, "ue-id": str(ue), "measTimeStampRf": 0,
                        "Degradation": "RSRP RSSINR"}], separators=(", ", ": ")).encode()


def main():
    from ricxappframe.rmr import rmr
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rmr-port", default="4590")
    ap.add_argument("--ctl-host", default="127.0.0.1")
    ap.add_argument("--ctl-port", type=int, default=38510)
    ap.add_argument("--ready-timeout", type=float, default=20, help="seconds; 0 = no limit")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    txlog = open(os.path.join(args.out, "tx.jsonl"), "a")
    rxlog = open(os.path.join(args.out, "rx.jsonl"), "a")
    ctx = rmr.rmr_init(args.rmr_port.encode(), rmr.RMR_MAX_RCV_BYTES, rmr.RMRFL_NONE)
    deadline = time.time() + args.ready_timeout
    while rmr.rmr_ready(ctx) == 0:
        if args.ready_timeout and time.time() > deadline:
            print("rmr-injector: RMR not ready within %g s (seed route table?)" % args.ready_timeout, flush=True)
            return 1
        time.sleep(0.1)
    send_lock = threading.Lock()

    def receiver():
        buf = None
        try:
            while True:
                buf = rmr.rmr_torcv_msg(ctx, buf, 1000)
                if not buf:  # RMR returns no buffer when the wait times out and none was passed in (a NULL pointer)
                    continue
                s = rmr.message_summary(buf)
                if s[rmr.RMR_MS_MSG_STATE] == rmr.RMR_ERR_TIMEOUT:
                    continue
                payload, meid = rmr.get_payload(buf), rmr.rmr_get_meid(buf).decode(errors="replace")
                rxlog.write(json.dumps({"t": time.time(), "mtype": s[rmr.RMR_MS_MSG_TYPE], "subId": s[rmr.RMR_MS_SUB_ID],
                                        "state": s[rmr.RMR_MS_MSG_STATE], "meid": meid,
                                        "payload": payload.decode(errors="replace"),
                                        "payloadHex": payload.hex()}) + "\n")
                rxlog.flush()
        except BaseException:
            # a receiver that dies quietly in a daemon thread hides the fault; end the whole injector instead
            traceback.print_exc()
            sys.stdout.flush()
            os._exit(1)

    threading.Thread(target=receiver, daemon=True).start()

    def send(mtype, sub_id, payload, meid=None):
        with send_lock:
            m = rmr.rmr_alloc_msg(ctx, max(2048, len(payload)))
            rmr.set_payload_and_length(payload, m)
            m.contents.mtype, m.contents.sub_id = mtype, sub_id
            if meid is not None:
                rmr.rmr_set_meid(m, meid.encode())
            t0, tries = time.time(), 0
            while True:
                tries += 1
                m = rmr.rmr_send_msg(ctx, m)
                if m.contents.state != rmr.RMR_ERR_RETRY or tries >= 100:
                    break
                time.sleep(0.01)
            rec = {"t": t0, "mtype": mtype, "subId": sub_id, "meid": meid, "state": m.contents.state, "tries": tries,
                   "sendS": round(time.time() - t0, 6), "payloadHex": payload.hex()}
            rmr.rmr_free_msg(m)
            txlog.write(json.dumps(rec) + "\n")
            txlog.flush()
            return rec

    class H(socketserver.StreamRequestHandler):
        def handle(self):
            for line in self.rfile:
                try:
                    req = json.loads(line)
                    if req["op"] == "anomaly":
                        rec = send(TS_ANOMALY_UPDATE, -1, anomaly_payload(req["ue"]))
                    elif req["op"] == "control":
                        if not req["meid"]:
                            raise ValueError("control needs a meid")
                        rec = send(RIC_CONTROL_REQ, -1, bytes.fromhex(req["hex"]), str(req["meid"]))
                    elif req["op"] == "raw":
                        rec = send(int(req["mtype"]), int(req.get("subId", -1)), bytes.fromhex(req["hex"]))
                    else:
                        raise ValueError("unknown op %r" % req["op"])
                    reply = {"ok": rec["state"] == rmr.RMR_OK, "state": rec["state"], "tries": rec["tries"],
                             "sendS": rec["sendS"]}
                except (ValueError, KeyError, TypeError) as ex:
                    reply = {"ok": False, "error": str(ex)}
                self.wfile.write((json.dumps(reply) + "\n").encode())
                self.wfile.flush()

    class S(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    srv = S((args.ctl_host, args.ctl_port), H)
    srv.socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    print("READY rmr port %s ctl port %d" % (args.rmr_port, args.ctl_port), flush=True)
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())

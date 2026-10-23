#!/usr/bin/env python3
"""stub-qp-rmr-peer.py: the stub QP xApp of gate r2 (an RMR peer, deployed as an xApp named stubqp).

RMR (routes from rtmgr; the chart sets RMR_RTG_SVC and RMR_SRC_ID):
  rx 30000 TS_UE_LIST {"UEPredictionSet": ["<ue-id>"]}  -> tx 30002 TS_QOE_PREDICTION with rmr_send (routed,
     like QP itself, so R2 exercises R3's routing path): {"<ue-id>": {"<cellKey>": [dl, ul], ...}} with the
     cells in table order. The TS xApp takes the first cell as the serving cell, counts only unsigned integer
     values and picks the best cell on a strict `<`, so the table must list the serving cell first, use
     integers >= 0 and never tie. A request that does not name exactly one UE, or a UE whose predictions are
     used up, gets no answer (the gate then fails on T_ctl).
  any other message type is logged and freed (a safe default handler).
HTTP on --http-port (reached by pod IP from the node):
  PUT /table  {"predictions": {"<ue-id>": [[["<cellKey>", [dl, ul]], ...], ...]}} one entry per occurrence of
              that UE, in order; loading a table resets the occurrence counters and the log
  GET /log    every message received and every answer sent since the last table load
  GET /health "ok" once RMR is ready
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TS_UE_LIST, TS_QOE_PREDICTION = 30000, 30002


def build_prediction(table, counts, payload):
    """(answer bytes or None, note) for one TS_UE_LIST payload; advances counts on an answer."""
    try:
        ues = json.loads(payload)["UEPredictionSet"]
    except (ValueError, KeyError, TypeError):
        return None, "unparsable request"
    if not isinstance(ues, list) or len(ues) != 1 or not isinstance(ues[0], str):
        return None, "request does not name exactly one UE: %r" % (ues,)
    ue = ues[0]
    occ = counts.get(ue, 0)
    preds = table.get(ue, [])
    if occ >= len(preds):
        return None, "no prediction left for ue %s (occurrence %d)" % (ue, occ)
    counts[ue] = occ + 1
    cells = {key: [int(v[0]), int(v[1])] for key, v in preds[occ]}
    return json.dumps({ue: cells}, separators=(",", ":")).encode(), "ue %s occurrence %d" % (ue, occ)


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.table, self.counts, self.log = {}, {}, []
        self.ready = False


def http_server(port, st):
    class H(BaseHTTPRequestHandler):
        def reply(self, code, body):
            data = body.encode() if isinstance(body, str) else body
            self.send_response(code)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                self.reply(200 if st.ready else 503, "ok" if st.ready else "rmr not ready")
            elif self.path == "/log":
                with st.lock:
                    self.reply(200, json.dumps(st.log))
            else:
                self.reply(404, "no such path")

        def do_PUT(self):
            if self.path != "/table":
                return self.reply(404, "no such path")
            try:
                table = json.loads(self.rfile.read(int(self.headers["Content-Length"])))["predictions"]
            except (ValueError, KeyError, TypeError) as ex:
                return self.reply(400, "bad table: %s" % ex)
            with st.lock:
                st.table, st.counts, st.log = table, {}, []
            self.reply(200, json.dumps({"ues": sorted(table), "entries": sum(len(v) for v in table.values())}))

        def log_message(self, *a):
            pass

    srv = ThreadingHTTPServer(("0.0.0.0", port), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()


def main():
    from ricxappframe.rmr import rmr
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rmr-port", default="4560")
    ap.add_argument("--http-port", type=int, default=8080)
    args = ap.parse_args()
    st = State()
    http_server(args.http_port, st)
    ctx = rmr.rmr_init(args.rmr_port.encode(), rmr.RMR_MAX_RCV_BYTES, rmr.RMRFL_NONE)
    while rmr.rmr_ready(ctx) == 0:
        time.sleep(0.2)
    st.ready = True
    print("stubqp: RMR ready on %s" % args.rmr_port, flush=True)
    sbuf = None
    while True:
        sbuf = rmr.rmr_torcv_msg(ctx, sbuf, 1000)
        summ = rmr.message_summary(sbuf)
        if summ[rmr.RMR_MS_MSG_STATE] == rmr.RMR_ERR_TIMEOUT:
            continue
        mtype, payload = summ[rmr.RMR_MS_MSG_TYPE], rmr.get_payload(sbuf)
        rec = {"t": time.time(), "rx": {"mtype": mtype, "subId": summ[rmr.RMR_MS_SUB_ID],
                                        "state": summ[rmr.RMR_MS_MSG_STATE], "payload": payload.decode(errors="replace")}}
        if mtype == TS_UE_LIST and summ[rmr.RMR_MS_MSG_STATE] == rmr.RMR_OK:
            with st.lock:
                answer, rec["note"] = build_prediction(st.table, st.counts, payload)
            if answer is not None:
                out = rmr.rmr_alloc_msg(ctx, max(2048, len(answer)))
                rmr.set_payload_and_length(answer, out)
                out.contents.mtype, out.contents.sub_id = TS_QOE_PREDICTION, -1
                tries = 0
                while True:
                    tries += 1
                    out = rmr.rmr_send_msg(ctx, out)
                    if out.contents.state != rmr.RMR_ERR_RETRY or tries >= 50:
                        break
                    time.sleep(0.01)
                rec["tx"] = {"mtype": TS_QOE_PREDICTION, "payload": answer.decode(), "state": out.contents.state,
                             "tries": tries, "t": time.time()}
                rmr.rmr_free_msg(out)
        else:
            rec["note"] = "ignored (default handler)"
        print(json.dumps(rec), flush=True)
        with st.lock:
            st.log.append(rec)


if __name__ == "__main__":
    sys.exit(main())

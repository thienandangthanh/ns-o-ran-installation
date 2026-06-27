#!/usr/bin/env python3
# Phase 6b Stage D (M-RC4) — deterministic mock-QP prediction injector.
#
# Pushes UNSOLICITED RMR TS_QOE_PREDICTION (mtype 30002) messages straight to the
# live OSC Traffic-Steering xApp, replacing the QP xApp / grpcurl in the closed
# loop. Each message is a per-UE prediction JSON of the shape the TS
# prediction_callback expects:
#
#     {"<ueId>": {"<servingKey>": [dl, ul], "<targetKey>": [dl, ul], ...}}
#
#   * first key = serving cell (TS assumes this; ts_xapp.cpp ~:225-227)
#   * the cell with the highest *downlink* prediction becomes the handover target
#   * gate fires when highest_dl > serving_dl + thresh; with the default A1
#     downlink_threshold=0 (ts_xapp.cpp:96) thresh=0, so target_dl > serving_dl
#     is enough -> serving [1,1], target [9000,9000] always fires.
#   * keys MUST equal the live TS cell_map keys, which are the LOWERCASE 10-char
#     hex 16b8ce0N0N for ns-3 cell N (ts_xapp.cpp NodebHandler lowercases the
#     decoded requestPart, substr(i,10)); a wrong key is silently dropped at
#     cell_map.find (ts_xapp.cpp:643-650).
#
# Runs IN-CLUSTER (the phase6b-injector pod) so RMR reaches the TS RMR endpoint.
# It writes its own seed route table (mtype -> TS rmr svc) before rmr_init, so it
# does not depend on rtmgr distributing a route for an unregistered sender.
#
# Examples (run inside the injector pod):
#   python3 inject.py --ue 1 --serving-key 16b8ce0101 --target-key 16b8ce0404
#   python3 inject.py --predictions-json \
#     '[{"1":{"16b8ce0101":[1,1],"16b8ce0404":[9000,9000]}},
#       {"2":{"16b8ce0202":[1,1],"16b8ce0505":[9000,9000]}}]'
import argparse
import json
import os
import sys
import tempfile
import time

DEFAULT_TS_EP = "service-ricxapp-trafficxapp-rmr.ricxapp:4560"
MTYPE = 30002  # TS_QOE_PREDICTION
SUB_ID = -1  # RMR_VOID_SUBID


def write_seed_rt(ts_ep: str, mtype: int) -> str:
    """Static route table so the sender can reach TS without rtmgr."""
    rt = f"newrt|start\nmse|{mtype}|-1|{ts_ep}\nnewrt|end\n"
    fd, path = tempfile.mkstemp(prefix="phase6b-inject-", suffix=".rt")
    with os.fdopen(fd, "w") as f:
        f.write(rt)
    return path


def build_predictions(args) -> list:
    if args.predictions_json:
        preds = json.loads(args.predictions_json)
        if isinstance(preds, dict):  # allow a single object too
            preds = [preds]
        return preds
    if not (args.ue and args.serving_key and args.target_key):
        sys.exit("ERROR: supply --predictions-json OR (--ue --serving-key --target-key)")
    return [
        {
            str(args.ue): {
                args.serving_key: [args.serving_tput, args.serving_tput],
                args.target_key: [args.target_tput, args.target_tput],
            }
        }
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description="Mock-QP 30002 prediction injector (M-RC4)")
    ap.add_argument(
        "--ts-rmr-ep", default=DEFAULT_TS_EP, help="TS RMR endpoint host:port (default %(default)s)"
    )
    ap.add_argument("--mtype", type=int, default=MTYPE)
    ap.add_argument("--src-port", default="4562", help="injector's own RMR listen port")
    ap.add_argument("--predictions-json", help="JSON list of per-UE prediction objects")
    ap.add_argument("--ue", help="single-prediction UE id (amfUENGAPID -> ns-3 IMSI)")
    ap.add_argument("--serving-key", help="single-prediction serving cell_map key")
    ap.add_argument("--target-key", help="single-prediction target cell_map key")
    ap.add_argument("--serving-tput", type=int, default=1)
    ap.add_argument("--target-tput", type=int, default=9000)
    ap.add_argument("--delay", type=float, default=3.0, help="seconds between sends")
    ap.add_argument("--ready-timeout", type=float, default=20.0)
    args = ap.parse_args()

    predictions = build_predictions(args)
    if not predictions:
        sys.exit("ERROR: no predictions to send (empty list)")

    rt_path = write_seed_rt(args.ts_rmr_ep, args.mtype)
    os.environ["RMR_SEED_RT"] = rt_path
    os.environ.setdefault("RMR_SRC_ID", "phase6b-injector.ricxapp")
    # import only after env is set so rmr_init() reads our seed RT
    from ricxappframe.rmr import rmr

    print(f"[inject] seed RT {rt_path} -> mtype {args.mtype} routes to {args.ts_rmr_ep}")
    mrc = rmr.rmr_init(args.src_port.encode(), rmr.RMR_MAX_RCV_BYTES, rmr.RMRFL_NONE)
    try:
        deadline = time.time() + args.ready_timeout
        while rmr.rmr_ready(mrc) == 0:
            if time.time() > deadline:
                print("[inject] ERROR: rmr never became ready", file=sys.stderr)
                return 2
            time.sleep(0.2)
        print("[inject] rmr ready")

        sent_ok = 0
        for i, pred in enumerate(predictions):
            payload = json.dumps(pred).encode()
            ue = next(iter(pred))
            sbuf = rmr.rmr_alloc_msg(mrc, max(len(payload), 4096))
            rmr.set_payload_and_length(payload, sbuf)
            rmr.generate_and_set_transaction_id(sbuf)
            sbuf.contents.mtype = args.mtype
            sbuf.contents.sub_id = SUB_ID
            # one retry: first send can race the seed-RT load -> RMR_ERR_RETRY/NOENDPT
            for attempt in (1, 2):
                sbuf = rmr.rmr_send_msg(mrc, sbuf)
                state = sbuf.contents.state
                if state == rmr.RMR_OK:
                    break
                if attempt < 2:  # don't say "retrying" after the final attempt
                    print(f"[inject] send attempt {attempt} state={state} (retrying)")
                    time.sleep(0.5)
            ok = state == rmr.RMR_OK
            sent_ok += 1 if ok else 0
            print(
                "[inject] msg {}/{} ue={} state={} {} payload={}".format(
                    i + 1, len(predictions), ue, state, "OK" if ok else "FAIL", payload.decode()
                )
            )
            if i + 1 < len(predictions):
                time.sleep(args.delay)
    finally:
        rmr.rmr_close(mrc)
        try:
            os.unlink(rt_path)  # don't leak seed-RT temp files in the long-lived pod
        except OSError:
            pass
    print(f"[inject] done: {sent_ok}/{len(predictions)} sent RMR_OK")
    return 0 if sent_ok == len(predictions) else 1


if __name__ == "__main__":
    raise SystemExit(main())

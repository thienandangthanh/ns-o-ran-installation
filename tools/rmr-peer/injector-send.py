#!/usr/bin/env python3
"""injector-send.py --host IP --port P --meid MEID --hex PDU: one RIC control through the RIC control injector's
control socket (rmr-injector.py, op "control"); prints its JSON reply and exits 0 iff the injector reports that RMR
accepted the message. Standalone, so a pacer trigger can run it as a plain argv."""
import argparse
import json
import socket
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--meid", required=True)
    ap.add_argument("--hex", required=True)
    ap.add_argument("--timeout", type=float, default=10.0)
    a = ap.parse_args()
    with socket.create_connection((a.host, a.port), timeout=a.timeout) as s:
        s.sendall(json.dumps({"op": "control", "meid": a.meid, "hex": a.hex}).encode() + b"\n")
        reply = json.loads(s.makefile().readline())
    print(json.dumps(reply))
    return 0 if reply.get("ok") is True else 1


if __name__ == "__main__":
    sys.exit(main())

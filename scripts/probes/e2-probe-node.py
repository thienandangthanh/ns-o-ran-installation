#!/usr/bin/env python3
"""e2-probe-node.py: a scripted E2 node built on the independent codec (tools/asn1-indep), run inside its image.

  node     --kind en-gnb|enb --id HEX --e2term IP:PORT --ranfunc-json NODEB.json --log OUT.jsonl
           [--sub-answer response|failure|none] [--ctl-answers ack,late:3,no-outcome,...] [--hold S]
  kpm-sub  --period-ms MS --meas NAME [--meas NAME ...]     print the KPM v03.00 event trigger and action definition
  acks     --requestor R --func F --first N --last M --out DIR  write ack-<n>.hex: RICcontrolAcknowledge without the
           optional RICcontrolOutcome for instance ids N..M (for direct RMR delivery to an xApp)

The node opens one SCTP association to e2term with PPID 70 on every DATA chunk (O-RAN E2GAP: E2AP over SCTP), sends
an E2 Setup Request (Global ENB ID with a 20-bit macro eNB ID, or Global en-gNB ID with a 32-bit gNB ID; the RAN
functions are copied from an e2mgr nodeb JSON; one X2 component whose request part is an EN-DC X2 Setup Request),
then answers what e2term sends: RIC subscription requests (--sub-answer), RIC subscription delete requests, and RIC
control requests, one --ctl-answers entry per request in order (ack: ACK with an empty E2SM-RC outcome Format 1;
late:S: the same ACK after S seconds; no-outcome: ACK without the optional RICcontrolOutcome IE). Every PDU in and
out goes to --log as one JSON line {t, dir, msg, hex, ies}. It closes the association gracefully after --hold
seconds or on SIGTERM.
"""
import argparse
import json
import signal
import socket
import struct
import sys
import time

sys.path.insert(0, "/opt/asn1-indep")
from e2indep import e2ap, e2sm_rc, x2ap  # noqa: E402
from e2indep.codec import encode  # noqa: E402
from e2indep_gen import E2SM_KPM_v0300 as KPM  # noqa: E402

IPPROTO_SCTP, SCTP_DEFAULT_SEND_PARAM, MSG_EOR, E2AP_PPID = 132, 10, 0x80, 70
PLMN = bytes.fromhex("00F110")  # MCC 001, MNC 01 (BCD), as the agents send it


def jsonable(o):
    return o.hex() if isinstance(o, (bytes, bytearray)) else str(o)


class Node:
    def __init__(self, a):
        self.a, self.log = a, open(a.log, "a", buffering=1)
        self.ctl = [c for c in a.ctl_answers.split(",") if c]
        host, port = a.e2term.rsplit(":", 1)
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM, IPPROTO_SCTP)
        # struct sctp_sndrcvinfo: stream, ssn, flags, (pad), ppid (network order), context, ttl, tsn, cumtsn, assoc
        self.s.setsockopt(IPPROTO_SCTP, SCTP_DEFAULT_SEND_PARAM,
                          struct.pack("@HHHIIIIIi", 0, 0, 0, socket.htonl(E2AP_PPID), 0, 0, 0, 0, 0))
        self.s.connect((host, int(port)))
        self.note("connected", {"e2term": a.e2term, "ppid": E2AP_PPID})

    def note(self, what, extra):
        self.log.write(json.dumps({"t": time.time(), "dir": "info", "msg": what, **extra}, default=jsonable) + "\n")

    def send(self, buf):
        self.s.send(buf)
        self.record("tx", buf)

    def record(self, d, buf):
        try:
            dec = e2ap.decode_e2ap(buf)
            msg, ies = dec["message"], dec["ies"]
        except Exception as e:  # an undecodable PDU is evidence too
            msg, ies = "undecodable", {"error": str(e)}
        self.log.write(json.dumps({"t": time.time(), "dir": d, "msg": msg, "hex": buf.hex(), "ies": ies},
                                  default=jsonable) + "\n")
        return msg, ies

    def recv(self):
        buf = b""
        while True:
            data, _, flags, _ = self.s.recvmsg(65536)
            if not data and not flags:
                raise EOFError("association closed by e2term")
            buf += data
            if flags & MSG_EOR:
                return buf

    def setup(self):
        a, rf = self.a, []
        nb = json.load(open(a.ranfunc_json))
        for f in (nb.get("gnb") or nb.get("enb") or {}).get("ranFunctions", []):
            rf.append(e2ap.RanFunction(f["ranFunctionId"], f.get("ranFunctionRevision", 1), f["ranFunctionOid"],
                                       bytes.fromhex(f["ranFunctionDefinition"])))
        if not rf:
            raise SystemExit("no ranFunctions in %s" % a.ranfunc_json)
        nid = int(a.id, 16)
        mtc = x2ap.measurement_timing_configuration(633333)
        if a.kind == "en-gnb":
            node = e2ap.e2node_en_gnb(PLMN, nid)
            cell = x2ap.served_nr_cell(1, PLMN, x2ap.nr_cell_identity(nid, 1), 633333, 78, mtc, configured_tac=b"\x00\x01")
            req = x2ap.endc_x2_setup_request_en_gnb(PLMN, nid, [cell])
            peer = e2ap.x2_component_id(global_enb=e2ap.global_enb_id(PLMN, 0xFFFFE))
        else:
            node = e2ap.e2node_enb(PLMN, nid)
            cell = x2ap.served_eutra_cell(1, PLMN, (nid << 8) | 1, b"\x00\x01", 100, 18100)
            req = x2ap.endc_x2_setup_request_enb(PLMN, nid, [cell])
            peer = e2ap.x2_component_id(global_en_gnb=e2ap.global_en_gnb_id(PLMN, 0x7F000001))
        self.send(e2ap.e2_setup_request(1, node, rf, [e2ap.Component("x2", peer, req, b"")]))

    def answer(self, msg, ies):
        rid = ies.get("id-RICrequestID", {})
        rid = (rid.get("ricRequestorID"), rid.get("ricInstanceID"))
        fid = ies.get("id-RANfunctionID")
        if msg == "RICsubscriptionRequest" and self.a.sub_answer != "none":
            acts = sorted(set(find_all(ies.get("id-RICsubscriptionDetails"), "ricActionID"))) or [1]
            if self.a.sub_answer == "response":
                self.send(e2ap.ric_subscription_response(rid, fid, acts))
            else:
                self.send(e2ap.ric_subscription_failure(rid, fid, ("ricRequest", "action-not-supported")))
        elif msg == "RICsubscriptionDeleteRequest":
            self.send(e2ap.build("RICsubscriptionDeleteResponse",
                                 [("id-RICrequestID", {"ricRequestorID": rid[0], "ricInstanceID": rid[1]}),
                                  ("id-RANfunctionID", fid)]))
        elif msg == "RICcontrolRequest":
            mode = self.ctl.pop(0) if self.ctl else "ack"
            self.note("control-answer", {"mode": mode, "requestId": rid})
            if mode.startswith("late:"):
                time.sleep(float(mode.split(":", 1)[1]))
            out = None if mode == "no-outcome" else e2sm_rc.control_outcome()
            self.send(e2ap.ric_control_ack(rid, fid, outcome=out))

    def run(self):
        self.setup()
        end = time.time() + self.a.hold
        self.s.settimeout(1.0)
        while time.time() < end:
            try:
                buf = self.recv()
            except socket.timeout:
                continue
            msg, ies = self.record("rx", buf)
            self.answer(msg, ies)
        self.close("hold elapsed")

    def close(self, why):
        self.note("closing", {"why": why})
        try:
            self.s.shutdown(socket.SHUT_RDWR)
        finally:
            self.s.close()


def find_all(obj, key):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key:
                yield v
            yield from find_all(v, key)
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            yield from find_all(v, key)


def kpm_sub(a):
    ies = KPM.E2SM_KPM_IEs
    trig = encode(ies.E2SM_KPM_EventTriggerDefinition,
                  {"eventDefinition-formats": ("eventDefinition-Format1", {"reportingPeriod": a.period_ms})})
    meas = [{"measType": ("measName", m), "labelInfoList": [{"measLabel": {"noLabel": "true"}}]} for m in a.meas]
    act = encode(ies.E2SM_KPM_ActionDefinition,
                 {"ric-Style-Type": 1, "actionDefinition-formats":
                  ("actionDefinition-Format1", {"measInfoList": meas, "granulPeriod": a.period_ms})})
    print(json.dumps({"eventTrigger": list(trig), "actionDefinition": list(act),
                      "eventTriggerHex": trig.hex(), "actionDefinitionHex": act.hex()}))


def acks(a):
    for n in range(a.first, a.last + 1):
        with open("%s/ack-%d.hex" % (a.out, n), "w") as f:
            f.write(e2ap.ric_control_ack((a.requestor, n), a.func).hex() + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    n = sub.add_parser("node")
    n.add_argument("--kind", choices=("en-gnb", "enb"), required=True)
    n.add_argument("--id", required=True, help="gNB ID (32 bits) or macro eNB ID (20 bits), hex")
    n.add_argument("--e2term", required=True)
    n.add_argument("--ranfunc-json", required=True)
    n.add_argument("--log", required=True)
    n.add_argument("--sub-answer", choices=("response", "failure", "none"), default="response")
    n.add_argument("--ctl-answers", default="")
    n.add_argument("--hold", type=float, default=600)
    k = sub.add_parser("kpm-sub")
    k.add_argument("--period-ms", type=int, default=100)
    k.add_argument("--meas", action="append", required=True)
    c = sub.add_parser("acks")
    c.add_argument("--requestor", type=int, required=True)
    c.add_argument("--func", type=int, required=True)
    c.add_argument("--first", type=int, default=1)
    c.add_argument("--last", type=int, default=40)
    c.add_argument("--out", required=True)
    a = ap.parse_args()
    if a.cmd == "kpm-sub":
        return kpm_sub(a)
    if a.cmd == "acks":
        return acks(a)
    node = Node(a)
    signal.signal(signal.SIGTERM, lambda *_: (node.close("SIGTERM"), sys.exit(0)))
    node.run()


if __name__ == "__main__":
    main()

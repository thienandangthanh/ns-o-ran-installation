#!/usr/bin/env python3
"""Wire facts per ns-3 pause window, from a tshark field export of the docker0 capture.

Input TSV (tab-separated, one frame per line), produced by probe-ns3-pause-ric-reaction.sh:
  frame.time_epoch, ip.src, ip.dst, sctp.srcport, sctp.dstport, sctp.chunk_type,
  e2ap.procedureCode, e2ap.initiatingMessage_element, e2ap.successfulOutcome_element,
  e2ap.unsuccessfulOutcome_element
Multi-valued fields (bundled chunks) are comma-separated.

windows.json: [{"pause_s": 60, "t_stop": <epoch>, "t_cont": <epoch>}, ...]

Per window it counts, over [t_stop, t_cont]: SCTP HEARTBEAT/ACK, ABORT, SHUTDOWN, INIT; E2AP PDUs by
procedure code and message kind; RICindication frames (code 5) sent by agents. Prints JSON; exit 1 when any
window has ABORT, SHUTDOWN, INIT, a subscription delete (9), an ErrorIndication (2), an E2 reset (3) or a
new subscription request (8), or no heartbeats.

Usage: analyze-pause-window-wire.py <fields.tsv> <windows.json>
"""
import collections
import json
import sys

E2T_PORT = "36422"
CHUNK = {"1": "INIT", "4": "HEARTBEAT", "5": "HEARTBEAT_ACK", "6": "ABORT", "7": "SHUTDOWN", "8": "SHUTDOWN_ACK",
         "14": "SHUTDOWN_COMPLETE"}
PROC = {"2": "ErrorIndication", "3": "Reset", "4": "RICcontrol", "5": "RICindication", "8": "RICsubscription",
        "9": "RICsubscriptionDelete"}


def frames(path):
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        if len(f) < 10 or not f[0]:
            continue
        yield {"t": float(f[0]), "src": f[1], "dst": f[2], "sport": f[3], "dport": f[4],
               "chunks": [c for c in f[5].split(",") if c], "procs": [p for p in f[6].split(",") if p],
               "init": bool(f[7]), "succ": bool(f[8]), "unsucc": bool(f[9])}


def main(tsv, wpath):
    windows = json.load(open(wpath))
    fr = list(frames(tsv))
    out = {"frames_total": len(fr), "windows": []}
    bad = False
    for w in windows:
        lo, hi = w["t_stop"], w["t_cont"]
        chunks = collections.Counter()
        procs = collections.Counter()
        hb_assocs = set()
        for f in fr:
            if not lo <= f["t"] <= hi:
                continue
            for c in f["chunks"]:
                chunks[CHUNK.get(c, "type" + c)] += 1
                if c == "4":
                    hb_assocs.add((f["src"], f["sport"], f["dst"], f["dport"]))
            kind = "init" if f["init"] else "succ" if f["succ"] else "unsucc" if f["unsucc"] else "?"
            for p in f["procs"]:
                procs["%s/%s" % (PROC.get(p, "proc" + p), kind)] += 1
        flagged = {k: v for k, v in chunks.items() if k in ("ABORT", "SHUTDOWN", "INIT")}
        flagged.update({k: v for k, v in procs.items()
                        if k.split("/")[0] in ("ErrorIndication", "Reset", "RICsubscriptionDelete", "RICsubscription")})
        ok = not flagged and chunks.get("HEARTBEAT", 0) > 0
        bad |= not ok
        out["windows"].append({"pause_s": w["pause_s"], "duration_s": round(hi - lo, 3), "sctp_chunks": dict(chunks),
                               "heartbeat_associations": len(hb_assocs), "e2ap": dict(procs),
                               "flagged": flagged, "ok": ok})
    out["all_ok"] = not bad
    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    print()
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))

#!/usr/bin/env python3
"""e2ap-pcap-facts.py <pcap> -o <facts.json> [--text-out <decoded.txt>]

Turns a docker0 `ip proto 132` capture into a JSON fact sheet that the gate
assertions (e2-facts-query.py) read. Everything comes from tshark's E2AP
dissector (E2AP on SCTP 36422), never from log lines.

Pass 1 (-T fields, one row per frame): SCTP chunk events (INIT = chunk 1,
ABORT = 6, SHUTDOWN/-ACK/-COMPLETE = 7/8/14) and E2AP PDU kinds. RICindication
frames (procedureCode 5) are only aggregated per source address, because one
frame can bundle several PDUs; exact indication counts come from
pcap-to-lines.py (TSN-deduped), not from here.
Pass 2 (-V text, only procedureCode 1 and 8 frames): E2Setup request/response
and RICsubscription request/response details (RAN function ID, OID, short
name, global gNB-ID, PLMN, accepted RAN functions, requestor/instance IDs).

Facts: {"inits","init_acks","cookie_acks","aborts","shutdowns","pdus","setup_requests",
"setup_responses","sub_requests","sub_responses","ind_times_by_src","ind_events"}; every event carries
frame, t (epoch s), src, dst, sport, dport. init_acks / cookie_acks (SCTP chunks 2 / 11) and ind_events
(one per RICindication frame) let e2-facts-query.py attribute traffic by association (agent ip, source
port) instead of by IP: the container IPs are not stable across agent restarts.
"""
import argparse
import json
import re
import subprocess
import sys

DISSECT = ["-d", "sctp.port==36422,e2ap"]
FIELDS = ["frame.number", "frame.time_epoch", "ip.src", "ip.dst", "sctp.srcport", "sctp.dstport",
          "sctp.chunk_type", "e2ap.procedureCode", "e2ap.initiatingMessage_element",
          "e2ap.successfulOutcome_element", "e2ap.unsuccessfulOutcome_element"]
PROC = {1: "E2setup", 5: "RICindication", 8: "RICsubscription"}


def tshark(args):
    res = subprocess.run(["tshark", "-r", args[0]] + DISSECT + args[1:], capture_output=True, text=True)
    # A capture that is still being written can end in a partial packet: keep what was decoded.
    if res.returncode != 0 and "cut short" not in res.stderr:
        sys.exit("tshark failed: " + res.stderr.strip()[-400:])
    return res.stdout


def field_rows(pcap):
    cmd = [pcap, "-T", "fields", "-E", "separator=/t", "-E", "occurrence=a", "-E", "aggregator=,"]
    for f in FIELDS:
        cmd += ["-e", f]
    for line in tshark(cmd).splitlines():
        c = (line.split("\t") + [""] * len(FIELDS))[:len(FIELDS)]
        if not c[0]:
            continue
        yield {"frame": int(c[0]), "t": float(c[1] or 0), "src": c[2], "dst": c[3],
               "sport": int(c[4] or 0), "dport": int(c[5] or 0),
               "chunks": {int(x) for x in c[6].split(",") if x.strip().isdigit()},
               "procs": [int(x) for x in c[7].split(",") if x.strip().isdigit()],
               "kind": "initiating" if c[8] else "successful" if c[9] else "unsuccessful" if c[10] else ""}


def blocks(text):
    cur, num = [], None
    for line in text.splitlines():
        m = re.match(r"^Frame (\d+):", line)
        if m:
            if num is not None:
                yield num, cur
            num, cur = int(m.group(1)), []
        cur.append(line)
    if num is not None:
        yield num, cur


def parse_setup_request(lines):
    txt = "\n".join(lines)
    out = {"ran_function_ids": [], "short_names": [], "oids": [], "descriptions": [], "revisions": []}
    for pat, key in ((r"ranFunctionID: (\d+)", "ran_function_ids"),
                     (r"ranFunction-ShortName: (.+)", "short_names"),
                     (r"ranFunction(?:-E2SM-)?OID: (\S+)", "oids"),
                     (r"ranFunction-Description: (.+)", "descriptions"),
                     (r"ranFunctionRevision: (\d+)", "revisions")):
        vals = [v.strip() for v in re.findall(pat, txt)]
        out[key] = [int(v) if v.isdigit() and key in ("ran_function_ids", "revisions") else v for v in vals]
    m = re.search(r"plmn-id: ([0-9a-fA-F]+)", txt)
    out["plmn"] = m.group(1).lower() if m else None
    m = re.search(r"gnb-ID: .*decimal value (\d+)", txt)
    out["gnb_id"] = int(m.group(1)) if m else None
    return out


def parse_setup_response(lines):
    ids, on = [], False
    for ln in lines:
        if "RANfunctionsAccepted" in ln:
            on = True
        elif "RANfunctionsRejected" in ln:
            on = False
        elif on:
            m = re.search(r"ranFunctionID: (\d+)", ln)
            if m:
                ids.append(int(m.group(1)))
    if not ids and not any("RANfunctionsAccepted" in ln for ln in lines):
        ids = [int(v) for v in re.findall(r"ranFunctionID: (\d+)", "\n".join(lines))]
    return {"accepted": ids}


def parse_subscription(lines):
    txt = "\n".join(lines)
    out = {}
    for pat, key in ((r"ricRequestorID: (\d+)", "requestor"), (r"ricInstanceID: (\d+)", "instance"),
                     (r"[rR][aA][nN]functionID: (\d+)", "ran_function_id")):
        m = re.search(pat, txt)
        out[key] = int(m.group(1)) if m else None
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcap")
    ap.add_argument("-o", required=True)
    ap.add_argument("--text-out")
    a = ap.parse_args()

    facts = {"pcap": a.pcap, "frames": 0, "inits": [], "init_acks": [], "cookie_acks": [], "ind_events": [], "aborts": [], "shutdowns": [], "pdus": [],
             "setup_requests": [], "setup_responses": [], "sub_requests": [], "sub_responses": [],
             "ind_times_by_src": {}}
    by_frame = {}
    for r in field_rows(a.pcap):
        facts["frames"] += 1
        by_frame[r["frame"]] = r
        ev = {k: r[k] for k in ("frame", "t", "src", "dst", "sport", "dport")}
        if 1 in r["chunks"]:
            facts["inits"].append(ev)
        if 2 in r["chunks"]:
            facts["init_acks"].append(ev)
        if 11 in r["chunks"]:
            facts["cookie_acks"].append(ev)
        if 6 in r["chunks"]:
            facts["aborts"].append(ev)
        if r["chunks"] & {7, 8, 14}:
            facts["shutdowns"].append(dict(ev, chunks=sorted(r["chunks"] & {7, 8, 14})))
        for p in r["procs"][:1]:
            if p == 5:
                facts["ind_times_by_src"].setdefault(r["src"], []).append(round(r["t"], 3))
                facts["ind_events"].append(ev)
            else:
                facts["pdus"].append(dict(ev, proc=p, procName=PROC.get(p, str(p)), kind=r["kind"]))

    text = tshark([a.pcap, "-Y", "e2ap.procedureCode == 1 || e2ap.procedureCode == 8", "-V"])
    if a.text_out:
        open(a.text_out, "w").write(text)
    for num, lines in blocks(text):
        r = by_frame.get(num)
        pdu = next((re.match(r"\s*E2AP-PDU: (\w+)", ln) for ln in lines if re.match(r"\s*E2AP-PDU: (\w+)", ln)), None)
        proc = next((int(m.group(1)) for m in (re.search(r"procedureCode: id-\S+ \((\d+)\)", ln) for ln in lines) if m), None)
        if r is None or pdu is None or proc is None:
            continue
        ev = {k: r[k] for k in ("frame", "t", "src", "dst", "sport", "dport")}
        init = pdu.group(1).startswith("initiating")
        if proc == 1:
            if init:
                facts["setup_requests"].append(dict(ev, **parse_setup_request(lines)))
            else:
                facts["setup_responses"].append(dict(ev, **parse_setup_response(lines)))
        elif proc == 8:
            facts["sub_requests" if init else "sub_responses"].append(dict(ev, **parse_subscription(lines)))
    json.dump(facts, open(a.o, "w"), indent=1, sort_keys=True)
    print("frames=%d inits=%d aborts=%d shutdowns=%d setup_req=%d setup_resp=%d sub_req=%d sub_resp=%d ind_srcs=%s" % (
        facts["frames"], len(facts["inits"]), len(facts["aborts"]), len(facts["shutdowns"]),
        len(facts["setup_requests"]), len(facts["setup_responses"]), len(facts["sub_requests"]),
        len(facts["sub_responses"]), {k: len(v) for k, v in facts["ind_times_by_src"].items()}))


if __name__ == "__main__":
    main()

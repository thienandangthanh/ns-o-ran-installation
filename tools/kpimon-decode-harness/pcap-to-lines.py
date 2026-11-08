#!/usr/bin/env python3
"""pcap-to-lines.py <pcap> [--summary] [--actions OUT.jsonl]

Extract E2AP RICindication header/message octets from a pcap and print
"<id> <hdr_hex> <msg_hex>" lines for kpimon-decode-harness.

tshark command (E2AP on SCTP 36422, procedureCode 5 = RICindication):
  tshark -r <pcap> \
    -Y 'e2ap.procedureCode == 5 && e2ap.initiatingMessage_element' -T fields \
    -e frame.number -e sctp.data_tsn_raw -e sctp.assoc_index \
    -e e2ap.RICindicationHeader -e e2ap.RICindicationMessage

Field names verified against `tshark -G fields` (Wireshark on this host):
  e2ap.RICindicationHeader, e2ap.RICindicationMessage (FT_BYTES),
  e2ap.procedureCode, e2ap.initiatingMessage_element,
  sctp.data_tsn_raw (absolute TSN), sctp.assoc_index.
The task text named sctp.data_tsn; that is the RELATIVE TSN (rebased per
capture/stream), so the absolute sctp.data_tsn_raw is used for dedup. A
retransmission carries the same absolute TSN on the same association.

Dedup key: (sctp.assoc_index, TSN). Rows lacking a TSN fall back to the frame
number (never merged). id = "f<frame>". Caveat: an SCTP packet may bundle
several DATA chunks; tshark then emits comma-separated multi-values per frame,
and those rows are split pairwise when counts agree, else skipped and counted.

--actions OUT.jsonl: the same lines on stdout (same filter, dedup and ids),
plus one JSON record per printed line in OUT: {id, frame, t, src, sport,
actionId, requestor, instance, ranFunctionId}. The per-PDU columns
e2ap.RICactionID (the indication's RICactionID IE; e2ap.ricActionID is the
member of the subscription's action items and is empty in an indication),
e2ap.ricRequestorID, e2ap.ricInstanceID and e2ap.RANfunctionID must carry one
integer per header, and the frame-level ip.src, sctp.srcport and
frame.time_epoch exactly one value, which every PDU of the frame shares;
otherwise the row is skipped and counted. The summary line is printed on
stderr (with --summary also on stdout, in place of the lines). Field names
checked with `tshark -G fields` on TShark 4.4.19 (VM) and 4.7.4 (host).
"""
import json
import subprocess
import sys

FIELDS = ["frame.number", "sctp.data_tsn_raw", "sctp.assoc_index",
          "e2ap.RICindicationHeader", "e2ap.RICindicationMessage"]
PDU_FIELDS = ["e2ap.RICactionID", "e2ap.ricRequestorID", "e2ap.ricInstanceID", "e2ap.RANfunctionID"]
PDU_KEYS = ["actionId", "requestor", "instance", "ranFunctionId"]
FRAME_FIELDS = ["ip.src", "sctp.srcport", "frame.time_epoch"]


def run_tshark(pcap, fields):
    cmd = ["tshark", "-r", pcap,  # E2AP selected by SCTP PPID 70 (E2GAP v08.00 section 6.1)
           "-Y", "e2ap.procedureCode == 5 && e2ap.initiatingMessage_element",
           "-T", "fields", "-E", "separator=\t", "-E", "occurrence=a",
           "-E", "aggregator=,"]
    for f in fields:
        cmd += ["-e", f]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("tshark failed: " + res.stderr.strip())
    return res.stdout.splitlines()


def action_columns(cols, n):
    """[per-PDU dict] for the n PDUs of a row in --actions mode, or None when a column does not fit."""
    per = [c.split(",") for c in cols[5:5 + len(PDU_FIELDS)]]
    frame = cols[5 + len(PDU_FIELDS):5 + len(PDU_FIELDS) + len(FRAME_FIELDS)]
    if any(len(v) != n or not all(x.strip().isdigit() for x in v) for v in per):
        return None
    if len(frame) != len(FRAME_FIELDS) or any(not v or "," in v for v in frame):
        return None
    try:
        src, sport, t = frame[0], int(frame[1]), float(frame[2])
    except ValueError:
        return None
    return [dict({k: int(v[i]) for k, v in zip(PDU_KEYS, per)}, src=src, sport=sport, t=t) for i in range(n)]


def main(argv):
    summary = "--summary" in argv
    args = [a for a in argv[1:] if a != "--summary"]
    actions_out = None
    if "--actions" in args:
        i = args.index("--actions")
        if i + 1 >= len(args):
            sys.exit(__doc__)
        actions_out = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    fields = FIELDS + (PDU_FIELDS + FRAME_FIELDS if actions_out else [])
    seen = set()
    out, acts = [], []
    total = dup = skipped = 0
    for row in run_tshark(args[0], fields):
        cols = row.split("\t")
        if len(cols) < (len(fields) if actions_out else 5):
            skipped += 1
            continue
        frame, tsn, assoc, hdr, msg = cols[:5]
        hdrs, msgs = hdr.split(","), msg.split(",")
        tsns = tsn.split(",") if tsn else [""]
        if len(hdrs) != len(msgs) or not hdr or not msg:
            skipped += 1
            continue
        per = action_columns(cols, len(hdrs)) if actions_out else None
        if actions_out and per is None:
            skipped += 1
            continue
        if len(tsns) != len(hdrs):
            tsns = [tsns[0] if len(tsns) == 1 and len(hdrs) == 1 else ""] * len(hdrs)
        for i, (h, m, t) in enumerate(zip(hdrs, msgs, tsns)):
            total += 1
            key = (assoc, t) if t else ("frame", frame, i)
            if key in seen:
                dup += 1
                continue
            seen.add(key)
            ident = "f" + frame + ("" if len(hdrs) == 1 else "." + str(i))
            out.append((ident, h.replace(":", ""), m.replace(":", "")))
            if per is not None:
                acts.append(dict(per[i], id=ident, frame=int(frame)))
    line = ('{"indications_seen": %d, "retransmissions_dropped": %d, '
            '"unique": %d, "rows_skipped": %d}' % (total, dup, len(out), skipped))
    if actions_out:
        with open(actions_out, "w") as f:
            for a in acts:
                f.write(json.dumps(a, sort_keys=True) + "\n")
        print(line, file=sys.stderr)
    if summary:
        print(line)
    else:
        for ident, h, m in out:
            print(ident, h, m)


if __name__ == "__main__":
    main(sys.argv)

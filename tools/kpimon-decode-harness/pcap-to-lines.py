#!/usr/bin/env python3
"""pcap-to-lines.py <pcap> [--summary]

Extract E2AP RICindication header/message octets from a pcap and print
"<id> <hdr_hex> <msg_hex>" lines for kpimon-decode-harness.

tshark command (E2AP on SCTP 36422, procedureCode 5 = RICindication):
  tshark -r <pcap> -d sctp.port==36422,e2ap \
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
"""
import subprocess
import sys

FIELDS = ["frame.number", "sctp.data_tsn_raw", "sctp.assoc_index",
          "e2ap.RICindicationHeader", "e2ap.RICindicationMessage"]


def run_tshark(pcap):
    cmd = ["tshark", "-r", pcap, "-d", "sctp.port==36422,e2ap",
           "-Y", "e2ap.procedureCode == 5 && e2ap.initiatingMessage_element",
           "-T", "fields", "-E", "separator=\t", "-E", "occurrence=a",
           "-E", "aggregator=,"]
    for f in FIELDS:
        cmd += ["-e", f]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("tshark failed: " + res.stderr.strip())
    return res.stdout.splitlines()


def main(argv):
    summary = "--summary" in argv
    args = [a for a in argv[1:] if a != "--summary"]
    if len(args) != 1:
        sys.exit(__doc__)
    seen = set()
    out = []
    total = dup = skipped = 0
    for row in run_tshark(args[0]):
        cols = row.split("\t")
        if len(cols) < 5:
            skipped += 1
            continue
        frame, tsn, assoc, hdr, msg = cols[:5]
        hdrs, msgs = hdr.split(","), msg.split(",")
        tsns = tsn.split(",") if tsn else [""]
        if len(hdrs) != len(msgs) or not hdr or not msg:
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
    if summary:
        print('{"indications_seen": %d, "retransmissions_dropped": %d, '
              '"unique": %d, "rows_skipped": %d}' % (total, dup, len(out), skipped))
    else:
        for ident, h, m in out:
            print(ident, h, m)


if __name__ == "__main__":
    main(sys.argv)

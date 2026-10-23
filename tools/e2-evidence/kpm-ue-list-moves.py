#!/usr/bin/env python3
"""kpm-ue-list-moves.py: does each applied handover move its IMSI between the gNBs' decoded KPM UE lists?

  kpm-ue-list-moves.py PCAP --node-ips node-ips.json --ledger e2-control-ledger.jsonl --epoch-ms MS
                       --out FILE [--period-ms 100] [--t0 EPOCH] [--t1 EPOCH]

The UE list of node n at sample k is the union of the amf-UE-NGAP-IDs (gNB-UEID; the agents put the
decimal IMSI there) over every E2SM-KPM Indication Message Format 2 the node sent with the Collection Start
Time of sample k, across every measCondUEidList item (E2SM-KPM v03.00 8.2.1.4.2, "List of matched UE
IDs"). The agent stamps sample k with epoch + max(0, k - 1) x period, so samples 0 and 1 share a time and
k <= 1 is not judged. gNB node n serves cell n.

An applied ledger line (imsi i, source s, target t, barrier k) has moved when i is in U(s) and not in U(t)
at sample k, and not in U(s) and in U(t) at sample k + 1. A refused or late line must leave i's gNB
membership unchanged between k and k + 1. Problems (exit 1): a missing report, k <= 1, a frame whose
indications carry different times, a Format 2 indication without UE IDs, a UE ID that is not gNB-UEID,
an applied line that did not move, a refused or late line that did.
"""
import argparse
import json
import subprocess
import sys

DISSECT = ["-d", "sctp.port==36422,e2ap"]
NTP_UNIX_OFFSET_S = 2208988800


def tshark(pcap, display_filter, fields):
    cmd = ["tshark", "-r", pcap] + DISSECT + ["-Y", display_filter, "-T", "fields", "-E", "separator=\t",
                                              "-E", "occurrence=a", "-E", "aggregator=,"]
    for f in fields:
        cmd += ["-e", f]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 and "cut short" not in res.stderr:
        sys.exit("tshark failed: " + res.stderr.strip()[-400:])
    return [r.split("\t") for r in res.stdout.splitlines()]


def split(col):
    return col.split(",") if col else []


def ntp_ms(hexs):
    """8-octet RFC 5905 timestamp (E2SM-KPM v03.00 8.3.12) -> Unix milliseconds, rounded."""
    v = int(hexs.replace(":", ""), 16)
    return (v >> 32) * 1000 + round((v & 0xFFFFFFFF) * 1000 / 2 ** 32) - NTP_UNIX_OFFSET_S * 1000


def ue_lists(pcap, ip2node, t0, t1):
    rows = tshark(pcap, "e2ap.procedureCode == 5 && e2ap.initiatingMessage_element",
                  ["frame.number", "frame.time_epoch", "ip.src", "sctp.data_tsn_raw", "sctp.assoc_index",
                   "e2ap.colletStartTime", "e2ap.indicationMessage_formats", "e2ap.ueID", "e2ap.amf_UE_NGAP_ID"])
    lists, seen, problems, n_f2 = {}, set(), [], 0
    for c in rows:
        c += [""] * (9 - len(c))
        frame, t, src, tsn, assoc = c[0], float(c[1]), c[2], c[3], c[4]
        times, fmts, kinds, ids = split(c[5]), split(c[6]), split(c[7]), split(c[8])
        if (t0 is not None and t < t0) or (t1 is not None and t >= t1):
            continue
        key = (assoc, tsn) if tsn else ("frame", frame)
        if key in seen:
            continue  # SCTP retransmission
        seen.add(key)
        node = ip2node.get(src)
        if node is None:
            problems.append("indication frame %s from unknown source %s" % (frame, src))
            continue
        if len(set(times)) != 1:
            problems.append("frame %s: indications with different collection start times %r" % (frame, times))
            continue
        ms = ntp_ms(times[0])
        lists.setdefault((node, ms), set())
        if "1" not in fmts:
            continue  # Format 1 (cell level): no UE IDs
        n_f2 += 1
        if not ids:
            problems.append("frame %s: Format 2 indication without UE IDs" % frame)
        if len(kinds) != len(ids) or any(k != "0" for k in kinds):
            problems.append("frame %s: UE ID that is not gNB-UEID (ueID choices %r)" % (frame, sorted(set(kinds))))
        lists[(node, ms)].update(int(i) for i in ids)
    return lists, n_f2, problems


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("pcap")
    ap.add_argument("--node-ips", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--epoch-ms", type=int, required=True)
    ap.add_argument("--period-ms", type=int, default=100)
    ap.add_argument("--out", required=True)
    ap.add_argument("--t0", type=float)
    ap.add_argument("--t1", type=float)
    a = ap.parse_args()
    ip2node = {ip: int(n) for n, ips in json.load(open(a.node_ips)).items() for ip in ips}
    lists, n_f2, problems = ue_lists(a.pcap, ip2node, a.t0, a.t1)
    gnbs = sorted({n for n, _ in lists if n != 1})

    def at(node, k):
        key = (node, a.epoch_ms + max(0, k - 1) * a.period_ms)
        return lists.get(key)

    lines = [json.loads(l) for l in open(a.ledger) if l.strip()][1:]
    results, moved = [], {}
    for x in lines:
        i, k, s, t = x["imsi"], x["rxSeq"], x["sourceCell"], x["targetCell"]
        r = {"imsi": i, "rxSeq": k, "outcome": x["outcome"], "cause": x.get("cause", ""), "source": s, "target": t}
        if k <= 1:
            problems.append("ledger line imsi %d at k %d: samples 0 and 1 share a collection time, not judged" % (i, k))
            results.append(r)
            continue
        if x["outcome"] == "applied":
            need = [(s, k), (t, k), (s, k + 1), (t, k + 1)]
            missing = [nk for nk in need if at(*nk) is None]
            if missing:
                problems.append("applied imsi %d at k %d: no report for (node, sample) %r" % (i, k, missing))
                r["moved"] = False
            else:
                r["before"] = {"inSource": i in at(s, k), "inTarget": i in at(t, k)}
                r["after"] = {"inSource": i in at(s, k + 1), "inTarget": i in at(t, k + 1)}
                r["moved"] = (r["before"] == {"inSource": True, "inTarget": False}
                              and r["after"] == {"inSource": False, "inTarget": True})
                if not r["moved"]:
                    problems.append("applied imsi %d %d->%d at k %d did not move: %r -> %r" % (
                        i, s, t, k, r["before"], r["after"]))
            moved[str(i)] = moved.get(str(i), True) and r["moved"]
        else:
            # a refusal or a late answer: i's gNB membership is the same in the reports of k and k + 1
            missing = [(n, kk) for n in gnbs for kk in (k, k + 1) if at(n, kk) is None]
            if missing:
                problems.append("%s imsi %d at k %d: no report for (node, sample) %r" % (r["cause"], i, k, missing))
            else:
                r["membershipK"] = [n for n in gnbs if i in at(n, k)]
                r["membershipK1"] = [n for n in gnbs if i in at(n, k + 1)]
                r["unchanged"] = r["membershipK"] == r["membershipK1"]
                if not r["unchanged"]:
                    problems.append("%s imsi %d at k %d changed gNB: %r -> %r" % (
                        r["cause"], i, k, r["membershipK"], r["membershipK1"]))
        results.append(r)
    out = {"format2Indications": n_f2, "reports": len(lists), "gnbNodes": gnbs, "lines": results,
           "kpmUeListMoved": moved, "problems": problems, "pass": not problems}
    with open(a.out, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")
    print(json.dumps({"format2Indications": n_f2, "kpmUeListMoved": moved, "pass": not problems}))
    for q in problems[:20]:
        print("problem: " + q)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

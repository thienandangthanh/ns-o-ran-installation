#!/usr/bin/env python3
"""kpm-ue-list-moves.py: does each applied handover move its IMSI between the gNBs' decoded KPM UE lists?

  kpm-ue-list-moves.py PCAP --node-ips node-ips.json --ledger e2-control-ledger.jsonl --epoch-ms MS
                       --ue-context-dir TRACE_DIR --out FILE [--period-ms 100] [--t0 EPOCH] [--t1 EPOCH]
                       [--expect-format2-nodes N,N,...]

The UE list of node n at sample k is the set of IMSIs that the UE IDs of every E2SM-KPM Indication Message Format 2
the node sent with the Collection Start Time of sample k resolve to, across every measCondUEidList item (E2SM-KPM
v03.00 8.2.1.4.2, "List of matched UE IDs"). A UE ID resolves through the run's UE context map (ue-context-map.py,
TRACE_DIR's e2-ue-context-<n>.jsonl, anchored on ns-3's MN PDCP trace by its own check): U(n, k) = {R(n, {k}, id)}.
Every Format 2 UE ID of a gNB node must be en-gNB-UEID (UEID CHOICE index 5) with globalENB-ID {00F110, macro eNB
ID 1 (20 bits)} and no optional member; of the eNB node eNB-UEID (index 6) with gUMMEI {00F110, 1, 1},
m-eNB-UE-X2AP-ID present and globalENB-ID absent; a gNB-UEID (index 0) is always a problem, and so is an ID that does
not resolve. The node kind comes from the node's IPC trace hello. The agent stamps sample k with epoch + max(0, k - 1)
x period, so samples 0 and 1 share a time (resolved over S = {0, 1}) and k <= 1 is not judged.
gNB node n serves cell n. --expect-format2-nodes: each listed node sent >= 1 Format 2 indication.

With an actuation delay (ledger applySimTimeNs - rxSimTimeNs = delta), the radio state changes at the apply
time, so every line is judged at the barrier ka = k + delta // period (ka = k at delta = 0; delta = 150 at a
100 ms period applies between samples k + 1 and k + 2, so ka = k + 1) and k below means ka.
An applied ledger line (imsi i, source s, target t, barrier k) has moved when i is in U(s) and not in U(t)
at sample k, and not in U(s) and in U(t) at sample k + 1. A refused or late line must leave i's gNB
membership unchanged between k and k + 1, unless the same IMSI has an applied line in the same step (a
same-step pair: the applied line's move judges it). A line with imsi 0 (refused unknownUe: ns-3 resolved no UE at
the node it was sent through) is attributed through the e2-pacing-log.jsonl record of its (viaNodeId, ctlId) in
TRACE_DIR: i := I(ueId), the IMSI whose (lteRnti, mnCellId) in the context files equals the record's
(mEnbUeX2apId, mnCellId). If i exists, the line is judged as a refused line of IMSI i; if no IMSI holds the ID, the
line carries no UE and is recorded judgedBy "no UE holds the ID"; imsi 0 with another outcome or cause, or without
exactly one pacing record, is a problem. A missing ledger is no lines. --self-test runs the
judge on synthetic lists and the UE ID decode and resolution on synthetic tshark rows. Problems (exit 1): a missing
report, k <= 1, a frame whose indications carry different times, a Format 2 indication without UE IDs, a UE ID that
is not of its node's form or does not resolve, a gNB-UEID, a listed node without a Format 2 indication, an applied
line that did not move, a refused or late line that did.
"""
import argparse
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

# E2AP is selected by its SCTP PPID 70 (O-RAN E2GAP v08.00 section 6.1); no port decode-as is forced.
DISSECT = []
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


# tshark fields of one RIC Indication frame; every UE ID member field the UEID CHOICE alternatives the agents may send
# can carry (E2SM common v07.00 6.2.2.6: en-gNB-UEID, eNB-UEID; gNB-UEID only to name it as a problem). The names
# exist in tshark 4.4.19 (the VM's) and 4.7.
FIELDS = ["frame.number", "frame.time_epoch", "ip.src", "sctp.data_tsn_raw", "sctp.assoc_index",
          "e2ap.colletStartTime", "e2ap.indicationMessage_formats", "e2ap.ueID", "e2ap.amf_UE_NGAP_ID",
          "e2ap.m_eNB_UE_X2AP_ID", "e2ap.m_eNB_UE_X2AP_ID_Extension", "e2ap.pLMNIdentity", "e2ap.eNB_ID",
          "e2ap.macro_eNB_ID", "e2ap.gNB_CU_UE_F1AP_ID", "e2ap.gNB_CU_CP_UE_E1AP_ID_List", "e2ap.ran_UEID",
          "e2ap.mME_UE_S1AP_ID", "e2ap.pLMN_Identity", "e2ap.mME_Group_ID", "e2ap.mME_Code", "sctp.srcport"]
F = {name: i for i, name in enumerate(FIELDS)}
UEID_CHOICE = ["gNB-UEID", "gNB-DU-UEID", "gNB-CU-UP-UEID", "ng-eNB-UEID", "ng-eNB-DU-UEID", "en-gNB-UEID", "eNB-UEID"]


def _hex(v):
    return v.replace(":", "").upper()


def decode_ue_ids(c):
    """The UE IDs of one indication frame's tshark row, in the decode harness's representation, and the problems that
    stop a per-UE reading. Each ID's members are paired by position, so every member list must have one entry per UE
    ID; an optional member anywhere in the frame marks every ID of the frame (it cannot be attributed)."""
    col = lambda name: split(c[F[name]])
    kinds = col("e2ap.ueID")
    n, kset = len(kinds), set(kinds)
    if not kinds:
        return [], []
    if kset == {"5"}:
        # tshark (4.4.19 and 4.7) dissects the E2SM GlobalENB-ID with E2AP's own type: its PLMN is e2ap.pLMN_Identity
        x2, plmn, enb, macro = col("e2ap.m_eNB_UE_X2AP_ID"), col("e2ap.pLMN_Identity"), col("e2ap.eNB_ID"), col("e2ap.macro_eNB_ID")
        if len(x2) != n or len(plmn) != n or len(enb) != n:
            return [], ["en-gNB-UEID members do not pair (%d IDs, %d X2AP IDs, %d PLMNs, %d eNB IDs)" % (
                n, len(x2), len(plmn), len(enb))]
        opt = any(col(f) for f in ("e2ap.m_eNB_UE_X2AP_ID_Extension", "e2ap.gNB_CU_UE_F1AP_ID",
                                   "e2ap.gNB_CU_CP_UE_E1AP_ID_List", "e2ap.ran_UEID"))
        macro_ok = all(e == "0" for e in enb) and len(macro) == n
        out = []
        for j in range(n):
            g = {"plmn": _hex(plmn[j])}
            if macro_ok:
                g["macroEnbId"] = "%05X" % (int(_hex(macro[j]), 16) >> 4)  # BIT STRING (SIZE(20)), left-aligned in 3 octets
            else:
                g["eNBIdChoice"] = enb[j]
            u = {"type": "en-gNB-UEID", "mEnbUeX2apId": int(x2[j]), "globalEnbId": g}
            if opt:
                u["optional"] = True
            out.append(u)
        return out, []
    if kset == {"6"}:
        mme, gp, grp, code = col("e2ap.mME_UE_S1AP_ID"), col("e2ap.pLMN_Identity"), col("e2ap.mME_Group_ID"), col("e2ap.mME_Code")
        x2 = col("e2ap.m_eNB_UE_X2AP_ID")
        # a globalENB-ID (eNB-ID present) adds its PLMN after each gUMMEI's in the same field
        glob = bool(col("e2ap.eNB_ID"))
        gp = gp[0::2] if glob and len(gp) == 2 * n else gp
        if len(mme) != n or len(gp) != n or len(grp) != n or len(code) != n or len(x2) not in (0, n):
            return [], ["eNB-UEID members do not pair (%d IDs, %d S1AP IDs, %d gUMMEIs, %d X2AP IDs)" % (
                n, len(mme), len(gp), len(x2))]
        out = []
        for j in range(n):
            u = {"type": "eNB-UEID", "mmeUeS1apId": int(mme[j]),
                 "gummei": {"plmn": _hex(gp[j]), "mmeGroupId": _hex(grp[j]), "mmeCode": _hex(code[j])}}
            if x2:
                u["mEnbUeX2apId"] = int(x2[j])
            if glob:
                u["globalEnbPresent"] = True
            out.append(u)
        return out, []
    if kset == {"0"}:
        amf = col("e2ap.amf_UE_NGAP_ID")
        return [{"type": "gNB-UEID", "amfUeNgapId": int(amf[j]) if len(amf) == n else None} for j in range(n)], []
    return [{"type": UEID_CHOICE[int(k)] if k.isdigit() and int(k) < len(UEID_CHOICE) else "choice " + k} for k in kinds], []


def ue_lists(pcap, ip2node, t0, t1, rows=None, node_of=None):
    """{(node, collection ms): [decoded UE IDs]} over the capture's indications (a Format 1 report gives an empty
    list), the Format 2 count per node, and the problems. node_of(src, sport, t) -> (node, problem), when given,
    attributes a frame by its SCTP association instead of ip2node (container IPs are reassigned after restarts)."""
    rows = tshark(pcap, "e2ap.procedureCode == 5 && e2ap.initiatingMessage_element", FIELDS) if rows is None else rows
    lists, seen, problems, f2 = {}, set(), [], {}
    for c in rows:
        c = c + [""] * (len(FIELDS) - len(c))
        frame, t, src, tsn, assoc = c[0], float(c[1]), c[2], c[3], c[4]
        times, fmts = split(c[5]), split(c[6])
        if (t0 is not None and t < t0) or (t1 is not None and t >= t1):
            continue
        key = (assoc, tsn) if tsn else ("frame", frame)
        if key in seen:
            continue  # SCTP retransmission
        seen.add(key)
        if node_of is not None:
            node, why = node_of(src, int(c[F["sctp.srcport"]] or -1), t)
            if node is None:
                problems.append("indication frame %s: %s" % (frame, why))
                continue
        else:
            node = ip2node.get(src)
            if node is None:
                problems.append("indication frame %s from unknown source %s" % (frame, src))
                continue
        if len(set(times)) != 1:
            problems.append("frame %s: indications with different collection start times %r" % (frame, times))
            continue
        ms = ntp_ms(times[0])
        lists.setdefault((node, ms), [])
        if "1" not in fmts:
            continue  # Format 1 (cell level): no UE IDs
        f2[node] = f2.get(node, 0) + 1
        ids, p = decode_ue_ids(c)
        problems += ["frame %s node %d: %s" % (frame, node, x) for x in p]
        if not ids and not p:
            problems.append("frame %s: Format 2 indication without UE IDs" % frame)
        lists[(node, ms)] += [(frame, u) for u in ids]
    return lists, f2, problems


def resolve_lists(raw, cm, epoch_ms, period_ms):
    """U(n, k): {(node, ms): IMSI set}, every UE ID through R(n, S, id) with S the samples stamped at ms ({0, 1} at the
    epoch, {k} after it). Problems: an ID not of its node's form (a gNB-UEID included), an unresolved ID, a time off
    the sample grid. Also returns the gNB-UEID count."""
    lists, problems, n_gnb_ueid = {}, [], 0
    for (node, ms), ids in sorted(raw.items()):
        lists[(node, ms)] = set()
        d = ms - epoch_ms
        seqs = {0, 1} if d == 0 else ({d // period_ms + 1} if d > 0 and d % period_ms == 0 else set())
        if ids and not seqs:
            problems.append("node %d: collection time %d is off the sample grid (epoch %d, period %d ms)" % (
                node, ms, epoch_ms, period_ms))
            continue
        for frame, u in ids:
            n_gnb_ueid += u.get("type") == "gNB-UEID"
            imsi, p = cm.resolve_wire(node, seqs, u)
            if p:
                problems += ["frame %s node %d: %s" % (frame, node, x) for x in p]
            elif imsi is None:
                problems.append("frame %s node %d: UE ID %s unresolved in ctx(n, s) for s in %s" % (
                    frame, node, json.dumps(u, sort_keys=True), sorted(seqs)))
            else:
                lists[(node, ms)].add(imsi)
    return lists, list(dict.fromkeys(problems)), n_gnb_ueid  # one line per frame and problem (IDs repeat per metric)


def _module(name, filename):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), filename)
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, path
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _ue_context_map():
    return _module("ue_context_map", "ue-context-map.py")


def ip_nodes(node_ips):
    """node-ips.json {node: [ip, ...]} -> {ip: {nodes}}; an agent restart can hand one container IP to two nodes."""
    out = {}
    for n, ips in node_ips.items():
        for ip in ips:
            out.setdefault(ip, set()).add(int(n))
    return out


def assoc_node_of(facts, multi):
    """node_of(src, sport, t) over an e2ap-pcap-facts.py fact sheet: the node of the frame's SCTP association (the
    latest INIT_ACK to (src, sport) at or before t) is the Global E2 Node ID of that association's E2 Setup Request
    (e2-facts-query.py build_assocs), and node-ips.json must list src for that node."""
    assocs, _ = _module("e2_facts_query", "e2-facts-query.py").build_assocs(facts)
    by = {}
    for x in assocs:  # sorted by INIT_ACK time
        by.setdefault((x["ip"], x["sport"]), []).append(x)

    def node_of(src, sport, t):
        best = None
        for x in by.get((src, sport), []):
            if x["t_init_ack"] <= t:
                best = x
        if best is None:
            return None, "no SCTP association from %s:%d at t %.3f in the fact sheet" % (src, sport, t)
        if best["node"] is None:
            return None, "association %s:%d has no E2 Setup Request" % (src, sport)
        if best["node"] not in multi.get(src, ()):
            return None, "association %s:%d is node %d's (E2 Setup), but node-ips.json does not list %s for it" % (
                src, sport, best["node"], src)
        return best["node"], None
    return node_of


def judge(lines, at, gnbs, period_ns):
    """lines: ledger lines; at(node, k): the UE-ID set of node n's report of sample k, or None; period_ns: the
    sample period. Each line is judged at ka = rxSeq + (applySimTimeNs - rxSimTimeNs) // period_ns.
    Judged per (imsi, barrier k): with exactly one applied line, that line must move the IMSI from its source
    to its target gNB between k and k + 1 (a refused line of the same IMSI and step is covered by that
    move); with none, every refused or late line must leave the IMSI's gNB membership unchanged; two
    applied lines for one IMSI in one step are a problem. Returns (per-line records, moved, problems)."""
    problems, results, moved = [], [], {}
    applied_in = {}
    def ka(x):
        return x["rxSeq"] + (x["applySimTimeNs"] - x["rxSimTimeNs"]) // period_ns
    for x in lines:
        if x["outcome"] == "applied":
            applied_in[(x["imsi"], ka(x))] = applied_in.get((x["imsi"], ka(x)), 0) + 1
    for (i, k), n in sorted(applied_in.items()):
        if n > 1:
            problems.append("imsi %d at k %d: %d applied lines in one step" % (i, k, n))
    for x in lines:
        i, k, s, t = x["imsi"], ka(x), x["sourceCell"], x["targetCell"]
        r = {"imsi": i, "rxSeq": x["rxSeq"], "judgedAt": k, "outcome": x["outcome"], "cause": x.get("cause", ""),
             "source": s, "target": t}
        if "attributedFrom" in x:
            r["attributedFrom"] = x["attributedFrom"]
        if x["rxSeq"] <= 1:
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
        elif applied_in.get((i, k)):
            r["judgedBy"] = "the applied line of the same imsi and step"
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
    return results, moved, problems


def attribute_unresolved(lines, imsi_of, pacing, x2_of):
    """Lines with imsi 0 attributed to the UE their pacing-log record names: (lines to judge, records of the lines
    that carry no UE, problems). imsi_of(X, M) is I(id); pacing {(viaNodeId, ctlId): [records]}."""
    out, unheld, problems = [], [], []
    for x in lines:
        if x.get("imsi") != 0:
            out.append(x)
            continue
        key = (x["viaNodeId"], x["ctlId"])
        if (x.get("outcome"), x.get("cause")) != ("refused", "unknownUe"):
            problems.append("ledger line %s has imsi 0 but %s/%s, not refused unknownUe" % (key, x.get("outcome"), x.get("cause")))
            continue
        recs = pacing.get(key, [])
        ue = x2_of(recs[0].get("ueId")) if len(recs) == 1 else None
        if ue is None:
            problems.append("ledger line %s (imsi 0) has %d e2-pacing-log records with a ueId, want 1" % (key, len(recs)))
            continue
        i = imsi_of(*ue)
        if i is None:
            unheld.append({"imsi": 0, "viaNodeId": key[0], "ctlId": key[1], "rxSeq": x["rxSeq"], "ueId": list(ue),
                           "outcome": x["outcome"], "cause": x["cause"], "judgedBy": "no UE holds the ID"})
        else:
            out.append(dict(x, imsi=i, attributedFrom={"ledgerImsi": 0, "ueId": list(ue)}))
    return out, unheld, problems


def attribution_self_test(at, period_ns):
    """imsi-0 lines: a non-source unknownUe line of IMSI 2, which moved 3 -> 2 at k 30, fails alone and passes beside
    the applied line of IMSI 2; an unheld-ID line passes and is recorded; imsi 0 without a pacing record fails."""
    rx = 3_000_000_000
    ids = {(12, 1): 2, (11, 1): 1}
    x2_of = lambda u: (u["mEnbUeX2apId"], u["mnCellId"]) if isinstance(u, dict) else None
    pacing = {(2, 5): [{"ueId": {"mEnbUeX2apId": 12, "mnCellId": 1}}], (2, 6): [{"ueId": {"mEnbUeX2apId": 4095, "mnCellId": 1}}]}
    base = {"rxSeq": 30, "rxSimTimeNs": rx, "applySimTimeNs": rx, "outcome": "refused", "cause": "unknownUe", "imsi": 0,
            "sourceCell": 0, "targetCell": 2}
    non_source = dict(base, viaNodeId=2, ctlId=5)
    unheld = dict(base, viaNodeId=2, ctlId=6)
    applied = dict(base, viaNodeId=3, ctlId=1, imsi=2, sourceCell=3, outcome="applied", cause="")
    fails = []

    def run(lines):
        ls, uh, p = attribute_unresolved(lines, lambda x, m: ids.get((x, m)), pacing, x2_of)
        return ls, uh, p + judge(ls, at, [2, 3], period_ns)[2]
    if not run([non_source])[2]:
        fails.append("a non-source unknownUe line of a UE that moved without an applied line passed")
    if run([non_source, applied])[2]:
        fails.append("a non-source unknownUe line beside the UE's applied line failed: %s" % run([non_source, applied])[2])
    ls, uh, p = run([unheld])
    if p or ls or [u["judgedBy"] for u in uh] != ["no UE holds the ID"]:
        fails.append("an unheld-ID line: %s %s %s" % (ls, uh, p))
    if not run([dict(base, viaNodeId=3, ctlId=9)])[2]:
        fails.append("imsi 0 without a pacing record passed")
    if not run([dict(non_source, cause="alreadyOnTarget")])[2]:
        fails.append("imsi 0 with another cause passed")
    return fails


def self_test():
    """The judge on synthetic UE lists: a same-step pair for one IMSI, a wrong move, the imsi-0 attribution."""
    lists = {(2, 30): {3, 4}, (3, 30): {1, 2}, (2, 31): {2, 3, 4}, (3, 31): {1},   # imsi 2: 3 -> 2 at k 30
             (2, 32): {2, 3, 4}, (3, 32): {1}}                                     # no move 31 -> 32

    def at(n, k):
        return lists.get((n, k))
    T = 100_000_000
    rx = 3_000_000_000

    def line(d_ns=0, rxseq=30, **kw):
        return dict({"rxSeq": rxseq, "rxSimTimeNs": rx, "applySimTimeNs": rx + d_ns}, **kw)
    pair = [line(imsi=2, sourceCell=3, targetCell=2, outcome="applied"),
            line(imsi=2, sourceCell=3, targetCell=3, outcome="refused", cause="inHandover")]
    # delta = 100 ms and 150 ms: decided at k 29 (100) / 29 (150), applied between samples 30 and 31 -> ka = 30
    d100 = [line(100_000_000, 29, imsi=2, sourceCell=3, targetCell=2, outcome="applied")]
    d150 = [line(150_000_000, 29, imsi=2, sourceCell=3, targetCell=2, outcome="applied")]
    d150_at_rx = [line(150_000_000, 30, imsi=2, sourceCell=3, targetCell=2, outcome="applied")]   # ka 31: no move there
    bad = [dict(pair[0], imsi=1, targetCell=2)]                                       # imsi 1 stays on 3
    twice = [pair[0], dict(pair[0], targetCell=2)]
    lonely = [dict(pair[1], imsi=2)]                                                   # a refusal whose imsi moved
    checks = [("pair", judge(pair, at, [2, 3], T), True), ("wrong move", judge(bad, at, [2, 3], T), False),
              ("two applied", judge(twice, at, [2, 3], T), False), ("refusal that moved", judge(lonely, at, [2, 3], T), False),
              ("delta 100 judged at k + 1", judge(d100, at, [2, 3], T), True), ("delta 150 judged at k + 1", judge(d150, at, [2, 3], T), True),
              ("delta 150 does not judge at rx", judge(d150_at_rx, at, [2, 3], T), False)]
    fails = [n for n, (_, _, p), want in checks if (not p) != want]
    fails += attribution_self_test(at, T)
    fails += ue_id_self_test(lists, pair, T)
    print("kpm-ue-list-moves self-test: " + ("ok" if not fails else "FAIL " + ", ".join(fails)))
    return 0 if not fails else 1


def ue_id_self_test(lists, pair, period_ns):
    """The same UE lists sent as en-gNB-UEIDs (tshark rows) through the decode and the UE context map: the same-step
    pair passes; a gNB-UEID carrying the IMSI, an X2AP ID absent from ctx(n, s) and a wrong globalENB-ID fail."""
    cm_mod = _ue_context_map()
    epoch, period = 1767225600000, period_ns // 1_000_000
    rnti = {i: i + 10 for i in range(1, 5)}
    ip = {1: "172.17.0.2", 2: "172.17.0.3", 3: "172.17.0.4"}
    fails = []
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        ue = lambda i: {"imsi": i, "lteRnti": rnti[i], "mnCellId": 1, "mmeUeS1apId": i}
        ctx = {1: [(0, [1, 2, 3, 4])], 2: [(0, [3, 4]), (31, [2, 3, 4])], 3: [(0, [1, 2]), (31, [1])]}
        for n, kind in ((1, "enb"), (2, "gnb"), (3, "gnb")):
            (d / ("e2-ipc-trace-%d.jsonl" % n)).write_text(json.dumps({"type": "hello", "nodeId": n, "kind": kind}) + "\n")
            (d / ("e2-ue-context-%d.jsonl" % n)).write_text("".join(json.dumps(
                {"type": "ueContext", "v": 1, "nodeId": n, "seq": s, "ues": [ue(i) for i in imsis]}) + "\n" for s, imsis in ctx[n]))
        cm = cm_mod.UeContextMap(d)

        def ntp_hex(ms):
            sec, frac = divmod(ms, 1000)
            return "%016x" % (((sec + NTP_UNIX_OFFSET_S) << 32) | round(frac * 2 ** 32 / 1000))

        def row(frame, node, k, ids):
            c = {name: "" for name in FIELDS}
            c.update({"frame.number": str(frame), "frame.time_epoch": "1.0", "ip.src": ip[node], "sctp.data_tsn_raw": str(frame),
                      "sctp.assoc_index": str(node), "e2ap.colletStartTime": ntp_hex(epoch + max(0, k - 1) * period),
                      "e2ap.indicationMessage_formats": "1"})
            cols = {}
            for kind, vals in ids:
                cols.setdefault("e2ap.ueID", []).append({"g": "5", "e": "6", "n": "0"}[kind])
                for name, v in vals.items():
                    cols.setdefault(name, []).append(v)
            c.update({name: ",".join(v) for name, v in cols.items()})
            return [c[name] for name in FIELDS]

        def en_gnb(i, plmn="00f110", macro="000010"):
            return ("g", {"e2ap.m_eNB_UE_X2AP_ID": str(rnti.get(i, 99)), "e2ap.pLMN_Identity": plmn, "e2ap.eNB_ID": "0",
                          "e2ap.macro_eNB_ID": macro})

        def run(mutate=None):
            rows, frame = [], 0
            for (n, k), imsis in sorted(lists.items()):
                frame += 1
                ids = [en_gnb(i) for i in sorted(imsis)]
                if mutate:
                    ids = mutate(n, k, ids)
                rows.append(row(frame, n, k, ids))
            raw, _, p = ue_lists(None, {v: n for n, v in ip.items()}, None, None, rows=rows)
            got, p2, _ = resolve_lists(raw, cm, epoch, period)
            at = lambda n, k: got.get((n, epoch + max(0, k - 1) * period))
            return p + p2 + judge(pair, at, [2, 3], period_ns)[2]

        if run():
            fails.append("en-gNB-UEID lists: %s" % run()[:2])
        gnb_ueid = lambda n, k, ids: ids[:-1] + [("n", {"e2ap.amf_UE_NGAP_ID": ids[-1][1]["e2ap.m_eNB_UE_X2AP_ID"]})]
        if not any("gNB-UEID" in x for x in run(lambda n, k, ids: [("n", {"e2ap.amf_UE_NGAP_ID": "2"})] if (n, k) == (2, 31) else ids)):
            fails.append("a gNB-UEID carrying the IMSI passed")
        if not run(lambda n, k, ids: gnb_ueid(n, k, ids) if (n, k) == (3, 30) else ids):
            fails.append("a frame mixing en-gNB-UEID and gNB-UEID passed")
        if not run(lambda n, k, ids: ids + [en_gnb(9)] if (n, k) == (2, 30) else ids):
            fails.append("an X2AP ID absent from ctx(n, s) passed")
        if not run(lambda n, k, ids: [en_gnb(2)] + ids if (n, k) == (2, 30) else ids):
            fails.append("an X2AP ID that ctx(n, s) holds only after s passed")
        if not run(lambda n, k, ids: [en_gnb(i, macro="000020") for i in sorted(lists[(n, k)])] if (n, k) == (3, 31) else ids):
            fails.append("a wrong globalENB-ID passed")
        if not run(lambda n, k, ids: [(kd, dict(v, **{"e2ap.ran_UEID": "01"})) for kd, v in ids] if (n, k) == (2, 32) else ids):
            fails.append("an en-gNB-UEID with an optional member passed")
        enb = [("e", {"e2ap.mME_UE_S1AP_ID": str(i), "e2ap.pLMN_Identity": "00f110", "e2ap.mME_Group_ID": "0001",
                      "e2ap.mME_Code": "01", "e2ap.m_eNB_UE_X2AP_ID": str(rnti[i])}) for i in (1, 2, 3, 4)]
        raw, _, p = ue_lists(None, {ip[1]: 1}, None, None, rows=[row(1, 1, 30, enb)])
        got, p2, _ = resolve_lists(raw, cm, epoch, period)
        if p or p2 or got != {(1, epoch + 29 * period): {1, 2, 3, 4}}:
            fails.append("the eNB's eNB-UEIDs: %s %s" % (p + p2, got))
        with_glob = [(k, dict(v, **{"e2ap.pLMN_Identity": "00f110,00f110", "e2ap.eNB_ID": "0", "e2ap.macro_eNB_ID": "000010"}))
                     for k, v in enb]
        raw, _, _ = ue_lists(None, {ip[1]: 1}, None, None, rows=[row(1, 1, 30, with_glob)])
        if not resolve_lists(raw, cm, epoch, period)[1]:
            fails.append("an eNB-UEID with globalENB-ID passed")
        fails += assoc_self_test(row, en_gnb, cm, epoch, period)
    return fails


def assoc_self_test(row, en_gnb, cm, epoch, period):
    """Attribution by SCTP association: node 2 sends from IP X, then node 3 restarts onto X (node-ips.json lists X
    for both). Each frame goes to its association's E2 Setup node; an IP that node-ips.json does not list for that
    node and an association without an E2 Setup Request are problems; ip_nodes names the shared IP."""
    X, svc = "172.17.0.9", "10.0.0.1"
    fails = []

    def facts(setups):
        ev = lambda ip, sport, t: {"src": svc, "sport": 36422, "dst": ip, "dport": sport, "t": t, "frame": 0}
        return {"inits": [], "init_acks": [ev(X, 1000, 0.5), ev(X, 2000, 4.5)], "cookie_acks": [ev(X, 1000, 0.6), ev(X, 2000, 4.6)],
                "setup_requests": [{"src": X, "sport": sp, "dst": svc, "dport": 36422, "t": t, "node_id": n}
                                   for sp, t, n in setups],
                "setup_responses": [], "sub_requests": [], "sub_responses": []}

    def frame(num, node, sport, t, imsis):
        r = row(num, node, 1, [en_gnb(i) for i in imsis])
        r[FIELDS.index("ip.src")], r[FIELDS.index("sctp.srcport")], r[FIELDS.index("frame.time_epoch")] = X, str(sport), str(t)
        return r

    rows = [frame(1, 2, 1000, 1.0, [3, 4]), frame(2, 3, 2000, 5.0, [1, 2])]
    multi = ip_nodes({"2": [X], "3": [X]})
    if multi != {X: {2, 3}}:
        fails.append("ip_nodes did not name the shared IP: %s" % multi)
    setups = [(1000, 0.7, 2), (2000, 4.7, 3)]
    raw, _, p = ue_lists(None, {}, None, None, rows=rows, node_of=assoc_node_of(facts(setups), multi))
    got, p2, _ = resolve_lists(raw, cm, epoch, period)
    if p or p2 or got != {(2, epoch): {3, 4}, (3, epoch): {1, 2}}:
        fails.append("attribution by association after an IP reuse: %s %s" % (p + p2, got))
    _, _, p = ue_lists(None, {}, None, None, rows=rows, node_of=assoc_node_of(facts(setups), ip_nodes({"2": [X]})))
    if not any("does not list" in x for x in p):
        fails.append("an association IP that node-ips.json does not list for its node passed")
    _, _, p = ue_lists(None, {}, None, None, rows=rows, node_of=assoc_node_of(facts(setups[:1]), multi))
    if not any("no E2 Setup Request" in x for x in p):
        fails.append("an association without an E2 Setup Request passed")
    return fails


def main():
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("pcap")
    ap.add_argument("--node-ips", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--epoch-ms", type=int, required=True)
    ap.add_argument("--period-ms", type=int, default=100)
    ap.add_argument("--out", required=True)
    ap.add_argument("--t0", type=float)
    ap.add_argument("--t1", type=float)
    ap.add_argument("--ue-context-dir", required=True, help="the run's trace dir (e2-ue-context-*.jsonl, e2-ipc-trace-*.jsonl)")
    ap.add_argument("--expect-format2-nodes", default="", help="comma list: each node sent >= 1 Format 2 indication")
    ap.add_argument("--facts", help="e2ap-pcap-facts.py fact sheet of the capture: attribute frames by SCTP association")
    a = ap.parse_args()
    multi = ip_nodes(json.load(open(a.node_ips)))
    ip2node = {ip: min(ns) for ip, ns in multi.items() if len(ns) == 1}
    shared = {ip: sorted(ns) for ip, ns in multi.items() if len(ns) > 1}
    node_of = assoc_node_of(json.load(open(a.facts)), multi) if a.facts else None
    cm = _ue_context_map().UeContextMap(a.ue_context_dir)
    raw, f2, problems = ue_lists(a.pcap, ip2node, a.t0, a.t1, node_of=node_of)
    if shared and node_of is None:
        problems.insert(0, "node-ips.json lists an IP for more than one node %s: pass --facts to attribute by association"
                        % shared)
    problems = ["UE context: " + x for x in cm.problems] + problems
    lists, p, n_gnb_ueid = resolve_lists(raw, cm, a.epoch_ms, a.period_ms)
    problems += p
    n_f2 = sum(f2.values())
    for n in sorted(int(x) for x in a.expect_format2_nodes.split(",") if x):
        if not f2.get(n):
            problems.append("node %d sent no Format 2 indication" % n)
    gnbs = sorted({n for n, _ in lists if n != 1})

    def at(node, k):
        return lists.get((node, a.epoch_ms + max(0, k - 1) * a.period_ms))

    lines = [json.loads(l) for l in open(a.ledger) if l.strip()][1:] if os.path.exists(a.ledger) else []
    ucm = _ue_context_map()
    lines, unheld, p = attribute_unresolved(lines, cm.imsi_of, ucm.pacing_controls(a.ue_context_dir), ucm.x2_of)
    problems += p
    results, moved, p = judge(lines, at, gnbs, a.period_ms * 1_000_000)
    results += unheld
    problems += p
    out = {"format2Indications": n_f2, "format2ByNode": {str(n): v for n, v in sorted(f2.items())},
           "gnbUeIdCount": n_gnb_ueid, "reports": len(lists), "gnbNodes": gnbs, "lines": results,
           "kpmUeListMoved": moved, "problems": problems[:500], "problemCount": len(problems), "pass": not problems}
    with open(a.out, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")
    print(json.dumps({"format2Indications": n_f2, "format2ByNode": out["format2ByNode"], "gnbUeIdCount": n_gnb_ueid,
                      "kpmUeListMoved": moved, "pass": not problems}))
    for q in problems[:20]:
        print("problem: " + q)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:] == ["--self-test"] else main())

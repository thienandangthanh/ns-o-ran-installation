#!/usr/bin/env python3
"""kpm-indication-action-judges.py: every KPM RIC INDICATION answered in the format its action asked for, loaded by
e2-facts-query.py (query ind-actions) and p12-records-check.py through importlib; never run on its own.

Inputs, all from one capture:
  - the tshark fact sheet (e2ap-pcap-facts.py) and its associations (e2-facts-query.py build_assocs);
  - the asn1-indep decode of its setups and subscriptions (e2-sub-setup-decode.py, keyed "f<frame>");
  - the indication rows of pcap-to-lines.py --actions: {id, frame, t, src, sport, actionId (e2ap.RICactionID),
    requestor, instance, ranFunctionId};
  - kpimon-decode-harness --records over the same lines: per id the decode codes, msg_format (1 = Format 1,
    2 = Format 2), measDataItems and, for Format 1, every item's records in order.

Subscription join: an indication's association is the latest one born on its (agent ip, agent port) at or before it;
its subscription is the latest successful RIC SUBSCRIPTION RESPONSE on that association with the same (requestor,
instance, RAN function ID) at or before it (a failure-only or absent response is an unknown subscription), and the
action formats come from the latest RIC SUBSCRIPTION REQUEST with that key at or before the response. Only that
response's admitted action IDs count. The node is the association's E2 Setup node, never an IP.
"""
import importlib.util
import json
import os


def _sibling(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(os.path.dirname(os.path.abspath(__file__)), filename))
    assert spec is not None and spec.loader is not None, filename
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


KAS = _sibling("kpm_action_subscription_judges", "kpm-action-subscription-judges.py")
NODE_KIND = {"en-gNB": "gnb", "eNB": "enb"}


def cell_layout(map_path):
    """{"gnb": [...], "enb": [...]}: the KPM names of each node kind's cell list in metric-map order."""
    rows = json.load(open(map_path))["rows"]
    return {kind: [r["kpm"] for r in sorted((r for r in rows if r["kind"] == kind and r["list"] == "cell"),
                                            key=lambda r: r["order"])] for kind in ("gnb", "enb")}


def subscription_before(x, key, t, decoded):
    """The subscription of a frame at t with request key on association x (module docstring), or None:
    {key, respFrame, tResp, admitted, request (the decoded request or None), reqFrame}."""
    best = None
    for r in x["sub_responses"]:
        if r["t"] <= t and (best is None or r["t"] >= best[0]["t"]):
            hit = [d for d in KAS.pdus(decoded, r["frame"], "RICsubscriptionResponse") if KAS.key_of(d) == key]
            if hit:
                best = (r, hit[0])
    if best is None:
        return None
    r, d = best
    req = None
    for q in x["sub_requests"]:
        if q["t"] <= r["t"] and (req is None or q["t"] >= req[0]["t"]):
            hit = [dq for dq in KAS.pdus(decoded, q["frame"], "RICsubscriptionRequest") if KAS.key_of(dq) == key]
            if hit:
                req = (q, hit[0])
    return {"key": key, "respFrame": r["frame"], "tResp": r["t"], "admitted": d.get("admitted") or [],
            "request": req[1] if req else None, "reqFrame": req[0]["frame"] if req else None}


def indication_action(assocs, nodes, row, decoded):
    """(association, subscription, decoded action, problem) of one indication row; problem is None when it joins."""
    x = KAS.assoc_at(assocs, row["src"], row["sport"], row["t"])
    if x is None:
        return None, None, None, "on no association (%s:%s)" % (row["src"], row["sport"])
    if x["node"] is None:
        return x, None, None, "on association %s without an E2 Setup Request inside the capture" % KAS.where(x)
    if x["node"] not in nodes:
        return x, None, None, "on association %s of node %s, not an expected node" % (KAS.where(x), x["node"])
    key = (row["requestor"], row["instance"], row["ranFunctionId"])
    sub = subscription_before(x, key, row["t"], decoded)
    if sub is None:
        return x, None, None, "node %s: unknown subscription %s (no successful RIC SUBSCRIPTION RESPONSE before it)" % (
            x["node"], key)
    if row["actionId"] not in sub["admitted"]:
        return x, sub, None, "node %s subscription %s: action ID %s is not admitted (admitted %s, response frame %d)" % (
            x["node"], key, row["actionId"], sub["admitted"], sub["respFrame"])
    if sub["request"] is None:
        return x, sub, None, "node %s subscription %s: its RIC SUBSCRIPTION REQUEST is not inside the capture" % (
            x["node"], key)
    acts = [a for a in sub["request"].get("actions") or [] if a.get("id") == row["actionId"]]
    df = acts[0].get("definition") if len(acts) == 1 else None
    if df is None or "error" in df:
        return x, sub, None, "node %s subscription %s: action %s has %d request items, definition %s" % (
            x["node"], key, row["actionId"], len(acts), df)
    return x, sub, acts[0], None


def format1_node_problem(rec, names, node):
    """None when every measData item of a Format 1 record carries ns3.nodeId == node (position from the metric map's
    cell list of the node's kind), else the reason."""
    w, pos = len(names), names.index("ns3.nodeId")
    n, recs = rec.get("measDataItems") or 0, rec.get("records") or []
    if n < 1 or len(recs) != w * n:
        return "Format 1 with %d records for %s measData items of %d metrics" % (len(recs), n, w)
    got = [(recs[i * w + pos].get("t"), recs[i * w + pos].get("v")) for i in range(n)]
    wrong = [(i, g) for i, g in enumerate(got) if g != ("int", node)]
    return None if not wrong else "Format 1 item ns3.nodeId (item, value) %s, want node %s" % (wrong[:4], node)


def judge_ind_actions(f, decoded, nodes, assocs, after, rows, records, nlines, summary, layout):
    """Problems of the indication format rule (e2-facts-query.py ind-actions); prints the evidence. Problems of many
    indications are grouped by reason with a count and the first ids."""
    bad, grouped, seen = [], {}, {}
    if (summary or {}).get("rows_skipped") != 0:
        bad.append("the extractor skipped %s indication rows (want 0): %s" % ((summary or {}).get("rows_skipped"), summary))
    ids = [r.get("id") for r in rows]
    rec_by = {r.get("id"): r for r in records}
    if not (nlines == len(rows) == len(records)) or len(set(ids)) != len(ids) or set(ids) != set(rec_by):
        bad.append("lines %d, --actions rows %d, records %d (distinct ids %d): every line needs one row and one record" % (
            nlines, len(rows), len(records), len(set(ids))))
    if not rows:
        bad.append("no RIC INDICATION in the capture")

    def note(reason, ident):
        g = grouped.setdefault(reason, [])
        g.append(ident)

    judged = 0
    for row in sorted(rows, key=lambda r: r["t"]):
        if row["t"] < after:
            continue
        judged += 1
        x, sub, act, why = indication_action(assocs, nodes, row, decoded)
        if why:
            note(why, row["id"])
            continue
        aid, fmt = row["actionId"], act["definition"]["format"]
        seen.setdefault((id(x), sub["key"], aid), []).append(row["id"])
        rec = rec_by.get(row["id"])
        tag = "node %s subscription %s action %s (Format %s)" % (x["node"], sub["key"], aid, fmt)
        if rec is None or rec.get("hdr_code") != "RC_OK" or rec.get("msg_code") != "RC_OK":
            note("%s: the indication does not decode (%s/%s)" % (tag, rec and rec.get("hdr_code"), rec and rec.get("msg_code")),
                 row["id"])
            continue
        mf = rec.get("msg_format")
        if fmt == 1:
            if mf != 1:
                note("%s: indication message Format %s, want Format 1" % (tag, mf), row["id"])
                continue
            kind = NODE_KIND.get(x["setup_request"].get("e2node_type"))
            if kind not in layout:
                note("%s: node kind %s has no metric-map cell list" % (tag, x["setup_request"].get("e2node_type")), row["id"])
                continue
            why = format1_node_problem(rec, layout[kind], x["node"])
            if why:
                note("%s: %s" % (tag, why), row["id"])
        elif fmt == 3:
            if mf != 2:
                note("%s: indication message Format %s, want Format 2" % (tag, mf), row["id"])
        else:
            note("%s: no indication format is defined for an admitted Format %s action" % (tag, fmt), row["id"])
    # every admitted action of every subscription answered in the window on an expected node's association
    expected = {}
    for x in assocs:
        if x["node"] not in nodes:
            continue
        for r in x["sub_responses"]:
            if r["t"] < after:
                continue
            for d in KAS.pdus(decoded, r["frame"], "RICsubscriptionResponse"):
                for aid in d.get("admitted") or []:
                    expected.setdefault((id(x), KAS.key_of(d), aid), (x, r["frame"]))
    for (xid, key, aid), (x, fr) in sorted(expected.items(), key=lambda kv: (kv[1][1], kv[0][2])):
        n = len(seen.get((xid, key, aid), []))
        print("node %s %s subscription %s (response frame %d) action %s: %d indication(s)" % (
            x["node"], KAS.where(x), key, fr, aid, n))
        if n == 0:
            bad.append("node %s subscription %s: admitted action %s received no indication" % (x["node"], key, aid))
    print("indications judged %d (after %s), grouped problems %d" % (judged, after, len(grouped)))
    for reason, idents in sorted(grouped.items(), key=lambda kv: -len(kv[1])):
        bad.append("%d indication(s): %s (first: %s)" % (len(idents), reason, ", ".join(idents[:3])))
    return bad


################################################################################
# self-test fixtures: the subscription fixtures (kpm-action-subscription-judges.py) plus indications
################################################################################
LAYOUT = {"gnb": ["ns3.nodeId", "ns3.simTimeMs", "ns3.seq", "m1"], "enb": ["ns3.nodeId", "ns3.simTimeMs", "ns3.seq"]}


class IndSheet(KAS.Sheet):
    """Sheet with indications: rows, records and the extractor summary of pcap-to-lines.py --actions."""

    def __init__(self):
        super().__init__()
        self.rows, self.records, self.summary, self.seq = [], [], {"rows_skipped": 0}, 0

    def ind(self, n, action, msg_format, node_ids=None, items=2, inst=None, ip=None, port=None, t=None, decodes=True):
        """One indication from node n under action, message msg_format; Format 1 items carry node_ids (default all n)."""
        self.seq += 1
        ident = "f%d" % (1000 + self.seq)
        self.rows.append({"id": ident, "frame": 1000 + self.seq, "t": 200.0 + self.seq if t is None else t,
                          "src": ip or "172.17.0.%d" % (n + 1), "sport": port or 40000 + n, "actionId": action,
                          "requestor": 123, "instance": n if inst is None else inst, "ranFunctionId": 2})
        rec = {"id": ident, "hdr_code": "RC_OK", "msg_code": "RC_OK" if decodes else "RC_FAIL", "msg_format": msg_format,
               "measDataItems": items}
        if msg_format == 1:
            names = LAYOUT["enb" if n == 1 else "gnb"]
            ids = node_ids or [n] * items
            rec["records"] = [{"t": "int", "v": ids[i] if m == "ns3.nodeId" else 0} for i in range(items) for m in names]
        self.records.append(rec)
        return self

    def both(self, n, f1=1, f3=2):
        return self.ind(n, f1, 1).ind(n, f3, 2)


def ind_actions_cases():
    """(name, sheet, want pass, required reason substring) of the ind-actions self-test."""
    def good():
        return IndSheet().add(1).add(2).both(1).both(2)

    def fn(s, f):
        f(s)
        return s
    return [
        ("good: two nodes, Format 1 under action 1 and Format 2 under action 2", good(), True, None),
        ("Format 1 under the Format 3 action (one action per subscription, today's wire)",
         IndSheet().add(1, acts=[KAS.f3(1)]).add(2, acts=[KAS.f3(1)]).ind(1, 1, 1).ind(1, 1, 2).ind(2, 1, 1).ind(2, 1, 2),
         False, "want Format 2"),
        ("Format 2 under a Format 1 action", good().ind(2, 1, 2), False, "want Format 1"),
        ("an unknown action ID", good().ind(2, 3, 2), False, "is not admitted"),
        ("a silent action", IndSheet().add(1).add(2).both(1).ind(2, 1, 1), False, "received no indication"),
        ("another node's ns3.nodeId in item k > 0", good().ind(2, 1, 1, node_ids=[2, 3]), False, "want node 2"),
        ("another node's ns3.nodeId in item 0", good().ind(2, 1, 1, node_ids=[3, 2]), False, "want node 2"),
        ("an unknown request ID", good().ind(2, 2, 2, inst=77), False, "unknown subscription"),
        ("an action admitted by a failure-only subscription",
         IndSheet().add(1).add(2, answer="failure").both(1).both(2), False, "unknown subscription"),
        ("an indication before its subscription's response", good().ind(2, 2, 2, t=100.45 + 2), False,
         "unknown subscription"),
        ("an indication on no association", good().ind(2, 2, 2, ip="172.17.0.9"), False, "on no association"),
        ("an indication that does not decode", good().ind(2, 2, 2, decodes=False), False, "does not decode"),
        ("a Format 1 record whose record count is not items x metrics",
         fn(good(), lambda s: s.records[-2]["records"].pop()), False, "measData items"),
        ("a skipped extractor row", fn(good(), lambda s: s.summary.update(rows_skipped=1)), False, "skipped"),
        ("a line without its --actions row", fn(good(), lambda s: s.rows.pop()), False, "every line needs"),
        ("no indication at all", IndSheet().add(1).add(2), False, "no RIC INDICATION"),
        ("an admitted Format 2 action", IndSheet().add(1).add(2, acts=[KAS.f1(1, KAS.cells_of(2)[0]),
                                                                       dict(KAS.f3(2), definition={"format": 2, "style": 2,
                                                                                                   "granulPeriod": 100, "cgi": None})])
         .both(1).both(2), False, "no indication format is defined"),
    ]


def self_test(run_query):
    """run_query(f, decoded, sheet) -> problems for ind-actions; each case's verdict and, when failing, its reason."""
    fails = []
    for name, s, want, reason in ind_actions_cases():
        got = run_query(s)
        if (not got) != want or (reason and not any(reason in p for p in got)):
            fails.append("%s (problems: %s)" % (name, got[:3]))
    return fails

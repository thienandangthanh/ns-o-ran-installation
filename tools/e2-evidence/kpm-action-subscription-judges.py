#!/usr/bin/env python3
"""kpm-action-subscription-judges.py: the per-action E2SM-KPM subscription judge on the decoded wire, loaded by
e2-facts-query.py (query sub-actions) through importlib; never run on its own.

Inputs: the tshark fact sheet (e2ap-pcap-facts.py) for frames, times and SCTP associations, its associations
(e2-facts-query.py build_assocs, by normalized 4-tuple and time: an association's node is the Global E2 Node ID of the
E2 Setup Request sent on it),
and the decoded sidecar of the same capture (e2-sub-setup-decode.py, the asn1-indep image), keyed "f<frame>". Every
value judged here (served cells, action formats and CGIs, request IDs, admitted actions) comes from the sidecar,
never from tshark's E2SM labels; tshark's action labels are printed as information only.

Served cells of an association: the X2 request parts (e2nodeComponentRequestPart, never a response part) of the E2
Setup Request the association rule attaches to it. Each part must decode as an EN-DC X2 SETUP REQUEST whose
initiating node type and Global ID equal the setup's Global E2 Node ID (init-en-gNB for an en-gNB, init-eNB for an
eNB), and every part must list the same served CGI set. C is the size of that set. When the setup is not inside the
capture, does not decode, or a part fails, the association has no C (the judge fails closed; C is never 0).
"""
import json

NODE_PART = {"en-gNB": "init-en-gNB", "eNB": "init-eNB"}
NODE_RAT = {"en-gNB": "nr", "eNB": "eutra"}


def pdus(decoded, frame, message):
    return [d for d in decoded.get("f%d" % frame, []) if d.get("message") == message]


def key_of(d):
    return d.get("requestor"), d.get("instance"), d.get("ranFunctionId")


def from_agent(e):
    """The normalized 4-tuple (agent ip, agent port, RIC ip, RIC port) of an event sent by the agent."""
    return e["src"], e["sport"], e["dst"], e["dport"]


def to_agent(e):
    """The normalized 4-tuple of an event sent to the agent."""
    return e["dst"], e["dport"], e["src"], e["sport"]


def assoc_at(assocs, tup, t):
    """The association of a frame with normalized 4-tuple tup at time t: the latest one born (INIT_ACK) at or before t
    on that 4-tuple, as build_assocs attributes every event."""
    best = None
    for x in assocs:
        if (x["ip"], x["sport"], x["service"], x["service_port"]) == tuple(tup) and x["t_init_ack"] <= t:
            best = x
    return best


def where(x):
    return "%s:%d->%s:%d" % (x["ip"], x["sport"], x["service"], x["service_port"])


def served_cells(x, decoded):
    """(sorted served CGIs, the node's CGI kind "nr" | "eutra", problems) of association x (module docstring)."""
    s = x["setup_request"]
    if s is None:
        return None, None, ["association %s: no E2 Setup Request inside the capture, so its served cells are unknown "
                            "(C is never 0)" % where(x)]
    f = s["frame"]
    setups = pdus(decoded, f, "E2setupRequest")
    if len(setups) != 1:
        return None, None, ["E2 Setup frame %d: %d E2 Setup Requests decoded by asn1-indep, want 1 (%s)" % (
            f, len(setups), json.dumps(decoded.get("f%d" % f))[:200])]
    g, parts = setups[0]["globalId"], setups[0]["x2"]
    bad = []
    if g[3] != x["node"]:
        bad.append("E2 Setup frame %d: decoded Global E2 Node ID %s, the association's node is %s" % (f, g, x["node"]))
    if not parts:
        bad.append("E2 Setup frame %d node %s: no X2 request part" % (f, x["node"]))
    sets = []
    for i, p in enumerate(parts):
        if "error" in p:
            bad.append("E2 Setup frame %d node %s: X2 request part %d does not decode: %s" % (f, x["node"], i, p["error"]))
            continue
        if p["node"] != NODE_PART.get(g[0]) or p["globalId"] != g:
            bad.append("E2 Setup frame %d node %s: X2 request part %d initiated by %s %s, want %s %s (the setup's "
                       "Global E2 Node ID)" % (f, x["node"], i, p["node"], p["globalId"], NODE_PART.get(g[0]), g))
            continue
        sets.append(frozenset(tuple(c) for c in p["cells"]))
    if len(set(sets)) > 1:
        bad.append("E2 Setup frame %d node %s: the X2 request parts list different served cells %s" % (
            f, x["node"], [sorted(c) for c in sets]))
    if not bad and not sets[0]:
        bad.append("E2 Setup frame %d node %s: the X2 request part lists no served cell" % (f, x["node"]))
    if bad:
        return None, None, bad
    return sorted(sets[0]), NODE_RAT.get(g[0]), []


def attempts_on(f, assocs, x, decoded):
    """Every request attempt on association x with its answer, in (time, frame) order: each decoded RIC SUBSCRIPTION
    REQUEST is answered by the first RIC SUBSCRIPTION RESPONSE or RIC SUBSCRIPTION FAILURE on x with the same
    (requestor, instance, RAN function ID) strictly after it and strictly before the next request with that key on x,
    both bounds ordered by (time, frame), so an answer never serves two attempts and a later duplicate answers none.
    [{"req": request event, "d": decoded request, "key", "kind": "response" | "failure" | None, "ans": decoded answer
    with its frame or None, "ansEvent": answer event or None}]."""
    reqs = sorted(((q["t"], q["frame"], i, q, d) for q in x["sub_requests"]
                   for i, d in enumerate(pdus(decoded, q["frame"], "RICsubscriptionRequest"))), key=lambda a: a[:3])
    failures = [r for r in f.get("sub_failures", []) if assoc_at(assocs, from_agent(r), r["t"]) is x]
    answers = sorted(((r["t"], r["frame"], i, kind, r, a)
                      for kind, evs, msg in (("response", x["sub_responses"], "RICsubscriptionResponse"),
                                             ("failure", failures, "RICsubscriptionFailure"))
                      for r in evs for i, a in enumerate(pdus(decoded, r["frame"], msg))), key=lambda a: a[:3])
    out, inf = [], (float("inf"),)
    for n, (t, fr, i, q, d) in enumerate(reqs):
        k = key_of(d)
        nxt = next((a[:3] for a in reqs[n + 1:] if key_of(a[4]) == k), inf)
        hit = next((a for a in answers if key_of(a[5]) == k and (t, fr, i) < a[:3] < nxt), None)
        out.append({"req": q, "d": d, "key": k, "kind": hit[3] if hit else None,
                    "ans": dict(hit[5], frame=hit[1]) if hit else None, "ansEvent": hit[4] if hit else None})
    return out


def request_problems(tag, d, cells, rat):
    """Row shape of one decoded request against its association's C served cells: exactly C+1 items with IDs 1..C+1;
    IDs 1..C report actions in Format 1 whose cellGlobalID is a served cell of the node's kind, each cell once; ID C+1
    a report action in Format 3."""
    c, acts, bad = len(cells), d.get("actions") or [], []
    ids = [a.get("id") for a in acts]
    if len(acts) != c + 1 or sorted(ids) != list(range(1, c + 2)):
        bad.append("%s: action IDs %s, want exactly 1..%d (C = %d served cells, plus the Format 3 action)" % (
            tag, ids, c + 1, c))
    named = []
    for a in acts:
        df, i = a.get("definition"), a.get("id")
        if a.get("type") != "report":
            bad.append("%s: action %s type %s, want report" % (tag, i, a.get("type")))
        if df is None or "error" in df:
            bad.append("%s: action %s definition %s (want an E2SM-KPM action definition that decodes)" % (
                tag, i, "absent" if df is None else "does not decode: " + df["error"]))
            continue
        if isinstance(i, int) and 1 <= i <= c:
            cgi = tuple(df["cgi"]) if df.get("cgi") else None
            if df["format"] != 1:
                bad.append("%s: action %s is Format %s, want Format 1" % (tag, i, df["format"]))
            elif cgi is None:
                bad.append("%s: Format 1 action %s carries no cellGlobalID" % (tag, i))
            elif cgi[0] != rat:
                bad.append("%s: Format 1 action %s names a %s CGI %s, the node's cells are %s" % (tag, i, cgi[0], list(cgi), rat))
            elif cgi not in cells:
                bad.append("%s: Format 1 action %s names CGI %s, not a served cell %s" % (tag, i, list(cgi), [list(x) for x in cells]))
            else:
                named.append(cgi)
        elif i == c + 1 and df["format"] != 3:
            bad.append("%s: action %s is Format %s, want Format 3" % (tag, i, df["format"]))
    if sorted(named) != list(cells):
        bad.append("%s: the Format 1 actions name %s, want every served cell %s once" % (
            tag, [list(x) for x in named], [list(x) for x in cells]))
    return bad


def judge_sub_actions(f, decoded, nodes, assocs, after):
    """Problems of the per-action subscription rule (e2-facts-query.py sub-actions); prints the evidence."""
    owner = {id(r): x for x in assocs for r in x["sub_requests"]}
    bad, per, cache, paired = [], {n: 0 for n in nodes}, {}, {}
    for r in sorted(f["sub_requests"], key=lambda r: r["t"]):
        if r["t"] < after:
            continue
        x = owner.get(id(r))
        info = [(c.get("action_id"), c.get("definition_format")) for c in r.get("actions") or []]
        if x is None:
            bad.append("frame %d to %s:%s: on no association (no INIT_ACK on its 4-tuple at or before it)" % (
                r["frame"], r.get("dst"), r.get("dport")))
            continue
        if x["node"] is None:
            bad.append("frame %d to %s: no E2 Setup Request inside the capture on its association, so its served "
                       "cells are unknown (C is never 0)" % (r["frame"], where(x)))
            continue
        if x["node"] not in nodes:
            bad.append("frame %d to %s: on an association of node %s, not an expected node %s" % (
                r["frame"], where(x), x["node"], nodes))
            continue
        per[x["node"]] += 1
        if id(x) not in cache:
            cache[id(x)] = served_cells(x, decoded)
        cells, rat, cp = cache[id(x)]
        reqs = pdus(decoded, r["frame"], "RICsubscriptionRequest")
        print("frame %d to %s (node %s): served cells %s; %d request(s) decoded: %s; tshark (information only): %s" % (
            r["frame"], where(x), x["node"], cells, len(reqs),
            [(key_of(d), [(a.get("id"), a.get("type"), (a.get("definition") or {}).get("format"),
                           (a.get("definition") or {}).get("cgi")) for a in d.get("actions") or []]) for d in reqs], info))
        if cp:
            bad += ["frame %d: %s" % (r["frame"], p) for p in cp]
            continue
        if not reqs:
            bad.append("frame %d node %s: no RIC SUBSCRIPTION REQUEST decoded by asn1-indep (%s)" % (
                r["frame"], x["node"], json.dumps(decoded.get("f%d" % r["frame"]))[:200]))
        if id(x) not in paired:
            paired[id(x)] = {(id(a["req"]), id(a["d"])): a for a in attempts_on(f, assocs, x, decoded)}
        for d in reqs:
            tag = "frame %d node %s request %s" % (r["frame"], x["node"], key_of(d))
            bad += request_problems(tag, d, cells, rat)
            att = paired[id(x)].get((id(r), id(d)))
            kind, ans = (att["kind"], att["ans"]) if att else (None, None)
            if kind is None:
                bad.append("%s: no RIC SUBSCRIPTION RESPONSE on its association" % tag)
            elif kind == "failure":
                bad.append("%s: answered by RIC SUBSCRIPTION FAILURE (frame %d, cause %s)" % (tag, ans["frame"], ans.get("cause")))
            else:
                want = list(range(1, len(cells) + 2))
                print("  answered by frame %d: admitted %s, not admitted %s" % (ans["frame"], ans["admitted"], ans["notAdmitted"]))
                if sorted(ans["admitted"]) != want or ans["notAdmitted"]:
                    bad.append("%s: response frame %d admits %s, not admitted %s; want all of %s admitted" % (
                        tag, ans["frame"], ans["admitted"], ans["notAdmitted"], want))
    for n in nodes:
        if not per[n]:
            bad.append("node %s received no RIC SUBSCRIPTION REQUEST" % n)
    return bad


################################################################################
# self-test fixtures: synthetic fact sheets with their decoded sidecars
################################################################################
SVC, PLMN = "10.96.0.5", "00f110"


def gid(n):
    return ["eNB", "macro-eNB-ID", PLMN, 1, 20] if n == 1 else ["en-gNB", "gNB-ID", PLMN, n, 32]


def cells_of(n, k=1):
    return [["eutra", PLMN, (1 << 8) | 1, 28]] if n == 1 else [["nr", PLMN, (n << 4) | i, 36] for i in range(1, k + 1)]


def part(n, cells=None, node=None, g=None):
    return {"node": node or NODE_PART[gid(n)[0]], "globalId": g or gid(n), "cells": cells_of(n) if cells is None else cells}


def f1(i, cgi):
    return {"id": i, "type": "report", "definition": {"format": 1, "style": 1, "granulPeriod": 100, "cgi": cgi}}


def f3(i):
    return {"id": i, "type": "report", "definition": {"format": 3, "style": 3, "granulPeriod": 100, "cgi": None}}


def good_actions(n, k=1):
    cs = cells_of(n, k)
    return [f1(i + 1, c) for i, c in enumerate(cs)] + [f3(len(cs) + 1)]


class Sheet:
    """A fact sheet and its decoded sidecar for nodes {1: eNB, 2: en-gNB} (more with add()): per node an association
    (INIT, INIT_ACK, COOKIE_ACK), an E2 Setup Request with one X2 part, one subscription request and its response."""

    def __init__(self):
        self.f = {"inits": [], "init_acks": [], "cookie_acks": [], "setup_requests": [], "setup_responses": [],
                  "sub_requests": [], "sub_responses": [], "sub_failures": [], "ind_events": []}
        self.dec = {}

    def ev(self, frame, t, s, d, sp, dp, **k):
        return dict(frame=frame, t=t, src=s, dst=d, sport=sp, dport=dp, **k)

    def add(self, n, setup=True, parts=None, setup_gid=None, acts=None, request=True, answer="response",
            admitted=None, not_admitted=(), k=1, inst=None, base=None):
        ip, port, b = "172.17.0.%d" % (n + 1), 40000 + n, 10 * n if base is None else base
        inst = n if inst is None else inst
        self.f["inits"].append(self.ev(b, 100 + n, ip, SVC, port, 36422))
        self.f["init_acks"].append(self.ev(b + 1, 100.1 + n, SVC, ip, 36422, port))
        self.f["cookie_acks"].append(self.ev(b + 2, 100.2 + n, SVC, ip, 36422, port))
        if setup:
            self.f["setup_requests"].append(self.ev(b + 3, 100.3 + n, ip, SVC, port, 36422, node_id=n,
                                                    e2node_type=gid(n)[0]))
            ps = [part(n, cells_of(n, k))] if parts is None else parts
            self.dec["f%d" % (b + 3)] = [{"message": "E2setupRequest", "globalId": setup_gid or gid(n),
                                          "components": len(ps), "x2": ps}]
        acts = good_actions(n, k) if acts is None else acts
        if request:
            self.f["sub_requests"].append(self.ev(b + 4, 100.4 + n, SVC, ip, 36422, port, requestor=123, instance=inst))
            self.dec["f%d" % (b + 4)] = [{"message": "RICsubscriptionRequest", "requestor": 123, "instance": inst,
                                          "ranFunctionId": 2, "actions": acts}]
        rid = {"requestor": 123, "instance": inst, "ranFunctionId": 2}
        if answer == "response":
            self.f["sub_responses"].append(self.ev(b + 5, 100.5 + n, ip, SVC, port, 36422, requestor=123, instance=inst))
            adm = [a["id"] for a in acts] if admitted is None else admitted
            self.dec["f%d" % (b + 5)] = [dict(rid, message="RICsubscriptionResponse", admitted=adm,
                                              notAdmitted=[list(x) for x in not_admitted])]
        elif answer == "failure":
            self.f["sub_failures"].append(self.ev(b + 5, 100.5 + n, ip, SVC, port, 36422, requestor=123, instance=inst))
            self.dec["f%d" % (b + 5)] = [dict(rid, message="RICsubscriptionFailure", cause="ricRequest:action-not-supported")]
        return self

    def endpoint(self, n, svc, t0, base, answer="failure", request=True):
        """A further association of node n's agent socket (same ip and port) to another RIC endpoint svc, born at t0:
        its E2 Setup Request, and (request) a subscription request with node n's key answered by answer."""
        ip, port, inst = "172.17.0.%d" % (n + 1), 40000 + n, n
        rid = {"requestor": 123, "instance": inst, "ranFunctionId": 2}
        self.f["inits"].append(self.ev(base, t0, ip, svc, port, 36422))
        self.f["init_acks"].append(self.ev(base + 1, t0 + 0.1, svc, ip, 36422, port))
        self.f["cookie_acks"].append(self.ev(base + 2, t0 + 0.2, svc, ip, 36422, port))
        self.f["setup_requests"].append(self.ev(base + 3, t0 + 0.3, ip, svc, port, 36422, node_id=n, e2node_type=gid(n)[0]))
        self.dec["f%d" % (base + 3)] = [{"message": "E2setupRequest", "globalId": gid(n), "components": 1, "x2": [part(n)]}]
        if request:
            self.f["sub_requests"].append(self.ev(base + 4, t0 + 0.4, svc, ip, 36422, port, requestor=123, instance=inst))
            self.dec["f%d" % (base + 4)] = [dict(rid, message="RICsubscriptionRequest", actions=good_actions(n))]
        self.answer(n, svc, t0 + 0.5, base + 5, answer)
        return self

    def request(self, n, frame, t, svc=SVC):
        """A further subscription request to node n with node n's key and good actions, frame at t."""
        ip, port = "172.17.0.%d" % (n + 1), 40000 + n
        self.f["sub_requests"].append(self.ev(frame, t, svc, ip, 36422, port, requestor=123, instance=n))
        self.dec["f%d" % frame] = [{"message": "RICsubscriptionRequest", "requestor": 123, "instance": n,
                                    "ranFunctionId": 2, "actions": good_actions(n)}]
        return self

    def answer(self, n, svc, t, frame, kind):
        """An answer from node n's agent socket to endpoint svc with node n's key: "response" (all admitted) or
        "failure"; None adds nothing."""
        ip, port = "172.17.0.%d" % (n + 1), 40000 + n
        rid = {"requestor": 123, "instance": n, "ranFunctionId": 2}
        if kind == "response":
            self.f["sub_responses"].append(self.ev(frame, t, ip, svc, port, 36422, requestor=123, instance=n))
            self.dec["f%d" % frame] = [dict(rid, message="RICsubscriptionResponse",
                                            admitted=[a["id"] for a in good_actions(n)], notAdmitted=[])]
        elif kind == "failure":
            self.f["sub_failures"].append(self.ev(frame, t, ip, svc, port, 36422, requestor=123, instance=n))
            self.dec["f%d" % frame] = [dict(rid, message="RICsubscriptionFailure", cause="ricRequest:action-not-supported")]
        return self

    def retry(self, n, answer="response", dt=10.0):
        """A second attempt of node n's request (same key, same actions) dt seconds later, with its own answer."""
        ip, port, b, inst = "172.17.0.%d" % (n + 1), 40000 + n, 10 * n, n
        rid = {"requestor": 123, "instance": inst, "ranFunctionId": 2}
        self.f["sub_requests"].append(self.ev(b + 6, 100.4 + n + dt, SVC, ip, 36422, port, requestor=123, instance=inst))
        self.dec["f%d" % (b + 6)] = [dict(rid, message="RICsubscriptionRequest", actions=good_actions(n))]
        if answer == "response":
            self.f["sub_responses"].append(self.ev(b + 7, 100.5 + n + dt, ip, SVC, port, 36422, requestor=123, instance=inst))
            self.dec["f%d" % (b + 7)] = [dict(rid, message="RICsubscriptionResponse",
                                              admitted=[a["id"] for a in good_actions(n)], notAdmitted=[])]
        else:
            self.f["sub_failures"].append(self.ev(b + 7, 100.5 + n + dt, ip, SVC, port, 36422, requestor=123, instance=inst))
            self.dec["f%d" % (b + 7)] = [dict(rid, message="RICsubscriptionFailure", cause="ricRequest:action-not-supported")]
        return self


def sub_actions_cases():
    """(name, sheet, want pass, after, required reason substring) of the sub-actions self-test."""
    def two(**node2):
        return Sheet().add(1).add(2, **node2)
    other_cells = [["nr", PLMN, 0x91, 36]]
    no_setup = Sheet().add(1).add(2, setup=False)
    return [
        ("good: the eNB with an E-UTRA CGI, an en-gNB with an NR CGI, C = 1 each", two(), True, None, None),
        ("good: a two-cell en-gNB, Format 1 at IDs 1 and 2, Format 3 at 3", two(k=2), True, None, None),
        ("the old single Format 3 action at ID 1", two(acts=[f3(1)]), False, None, "want exactly 1..2"),
        ("a Format 1 action without a CGI", two(acts=[f1(1, None), f3(2)]), False, None, "carries no cellGlobalID"),
        ("a Format 1 action naming a foreign CGI", two(acts=[f1(1, other_cells[0]), f3(2)]), False, None, "not a served cell"),
        ("two Format 3 actions", two(acts=[f3(1), f3(2)]), False, None, "want Format 1"),
        ("a not-admitted action", two(admitted=[1], not_admitted=[(2, "ricRequest:action-not-supported")]), False, None,
         "want all of [1, 2] admitted"),
        ("X2 request parts that disagree", two(parts=[part(2), part(2, other_cells)]), False, None, "different served cells"),
        ("an X2 request part initiated by another node", two(parts=[part(2, g=gid(3))]), False, None, "initiated by"),
        ("an X2 request part of the eNB kind on an en-gNB", two(parts=[part(1)]), False, None, "initiated by"),
        ("an undecodable X2 request part", two(parts=[{"error": "CodecError: x"}]), False, None, "does not decode"),
        ("no X2 request part", two(parts=[]), False, None, "no X2 request part"),
        ("the E2 Setup outside the capture", no_setup, False, None, "no E2 Setup Request inside the capture"),
        ("a decoded Global E2 Node ID other than the association's node", two(setup_gid=gid(3)), False, None,
         "the association's node"),
        ("an NR CGI on the eNB", Sheet().add(1, acts=[f1(1, cells_of(2)[0]), f3(2)]).add(2), False, None, "the node's cells are eutra"),
        ("one cell named twice", two(k=2, acts=[f1(1, cells_of(2)[0]), f1(2, cells_of(2)[0]), f3(3)]), False, None,
         "every served cell"),
        ("action IDs 0..C", two(acts=[dict(f1(1, cells_of(2)[0]), id=0), dict(f3(2), id=1)]), False, None, "want exactly 1..2"),
        ("action IDs with a gap", two(acts=[f1(1, cells_of(2)[0]), f3(3)]), False, None, "want exactly 1..2"),
        ("C + 2 actions (an extra Format 1 action)", two(acts=good_actions(2) + [f1(3, cells_of(2)[0])]), False, None,
         "want exactly 1..2"),
        ("an insert action", two(acts=[f1(1, cells_of(2)[0]), dict(f3(2), type="insert")]), False, None, "want report"),
        ("an undecodable action definition", two(acts=[f1(1, cells_of(2)[0]), dict(f3(2), definition={"error": "x"})]),
         False, None, "does not decode"),
        ("no RIC SUBSCRIPTION RESPONSE", two(answer=None), False, None, "no RIC SUBSCRIPTION RESPONSE"),
        ("a RIC SUBSCRIPTION FAILURE", two(answer="failure"), False, None, "RIC SUBSCRIPTION FAILURE"),
        ("a node without a request", two(request=False, answer=None), False, None, "received no RIC SUBSCRIPTION REQUEST"),
        ("an extra request on no association",
         _extra(two(), lambda s: s.f["sub_requests"].append(s.ev(74, 107.4, SVC, "172.17.0.8", 36422, 40007,
                                                                  requestor=123, instance=7))), False, None, "on no association"),
        ("a request on an association of an unexpected node", two().add(9), False, None, "not an expected node"),
        ("a failed request whose same-key retry succeeds (the later response answers only the retry)",
         _extra(two(answer="failure"), lambda s: s.retry(2, answer="response")), False, None,
         "answered by RIC SUBSCRIPTION FAILURE"),
        ("a request answered by a response, then a same-key retry answered by a failure",
         _extra(two(), lambda s: s.retry(2, answer="failure")), False, None, "answered by RIC SUBSCRIPTION FAILURE"),
        ("a successful request and a successful same-key retry", _extra(two(), lambda s: s.retry(2)), True, None, None),
        ("a response sent from the node's agent socket to another RIC endpoint does not answer the request",
         two(answer=None).endpoint(2, "10.96.0.6", 101.0, 90, request=False, answer=None)
         .answer(2, "10.96.0.6", 102.6, 96, "response"), False, None, "no RIC SUBSCRIPTION RESPONSE on its association"),
        ("a failure sent from the node's agent socket to another RIC endpoint does not answer the request",
         two(answer=None).endpoint(2, "10.96.0.6", 101.0, 90, request=False, answer=None)
         .answer(2, "10.96.0.6", 102.6, 96, "failure"), False, None, "no RIC SUBSCRIPTION RESPONSE on its association"),
        ("two same-key requests at one timestamp and one response: the earlier-frame attempt is unanswered",
         two(answer=None).request(2, 26, 100.4 + 2).answer(2, SVC, 100.5 + 2, 27, "response"), False, None,
         "no RIC SUBSCRIPTION RESPONSE on its association"),
        ("a response at the request's timestamp but an earlier frame does not answer it",
         two(request=False, answer=None).request(2, 30, 102.45).answer(2, SVC, 102.45, 29, "response"), False, None,
         "no RIC SUBSCRIPTION RESPONSE on its association"),
        ("a response at the request's timestamp and a later frame answers it",
         two(request=False, answer=None).request(2, 30, 102.45).answer(2, SVC, 102.45, 31, "response"), True, None, None),
        ("a request before the window on no association is not judged",
         _extra(two(), lambda s: s.f["sub_requests"].append(s.ev(5, 50.0, SVC, "172.17.0.6", 36422, 40006,
                                                                  requestor=123, instance=5))), True, 60.0, None),
    ]


def _extra(sheet, fn):
    fn(sheet)
    return sheet


def self_test(run_query):
    """run_query(name, f, decoded, after) -> problems. Every case's verdict, and for the failing ones the reason."""
    fails = []
    for name, s, want, after, reason in sub_actions_cases():
        got = run_query("sub-actions", s.f, s.dec, after)
        if (not got) != want or (reason and not any(reason in p for p in got)):
            fails.append("%s (problems: %s)" % (name, got[:3]))
    return fails

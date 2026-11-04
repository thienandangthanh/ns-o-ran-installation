#!/usr/bin/env python3
"""ue-id-prepare.py: the UE ID key of an IMSI at a lock-step barrier, as the RIC is given it (a pacer "prepare").

  ue-id-prepare.py TRACE_DIR STEP IMSI=OUT_BASE [IMSI=OUT_BASE ...] [--context-only] [--deadline-s S] [--poll-s S]
                   [--ue-csv FILE]
  ue-id-prepare.py --self-test

ns-3 is blocked at barrier STEP, so its context files hold every line with seq <= STEP. Per IMSI:
  ctx  the run's e2-ue-context-*.jsonl lines with seq <= STEP pass row (a) to (c) of ue-context-map.py, and the IMSI
       is in ctx(n, STEP) of at least one gNB node n; U := its R-4 gNB tag enGnbUeId:<lteRnti>@00F110-<mnCellId %05X>
       (the ID is MN-scoped, so every such node gives the same U) and I(U) = IMSI;
  influx (unless --context-only) kpimon wrote U: a UeMetrics row whose ueId tag is U, of one of those gNB nodes, with
       ns3.seq <= STEP exists in Influx (polled up to --deadline-s, default 20 s: kpimon may still be writing). The
       query runs in the InfluxDB pod with the pod's own token (check-n6-influx-window.py `query`); the UE is never
       looked up by the ns3.imsi field.
Writes OUT_BASE.txt (U and a newline: the send-rmr.sh anomaly-from and rc-send.sh --ue-from file) and OUT_BASE.json
{step, imsi, ueId: U, ipcUeId: {mEnbUeX2apId, mnCellId} (the pacer's ueIdFrom member), nodes, influx: {node, seq} or
null}. Any failure exits 1 before any file of that IMSI is written. --ue-csv reads a Flux CSV instead of Influx (one
poll; the self-test).
"""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent


def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, path
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


N6 = _mod("check_n6", HERE / "check-n6-influx-window.py")
UECM = N6.UECM


def resolve(trace_dir, step, imsi):
    """(U, ipc ueId, gNB nodes whose ctx(n, step) holds the IMSI, problems) from the run's context files."""
    cm = UECM.UeContextMap(trace_dir, max_seq=step)
    ids, p = cm.identities()
    problems = ["UE context: " + q for q in cm.problems + p]
    nodes = sorted(n for n, k in cm.kinds.items() if k == "gnb" and imsi in cm.ctx(n, step))
    if not nodes:
        problems.append("IMSI %d is in no gNB node's context at seq %d" % (imsi, step))
    if imsi not in ids:
        problems.append("IMSI %d has no identity in the context files up to seq %d" % (imsi, step))
    if problems:
        return None, None, nodes, problems
    rnti, mn, _ = ids[imsi]
    u = UECM.gnb_tag(rnti, mn)
    if cm.imsi_of(rnti, mn) != imsi:
        return None, None, nodes, ["I(%s) = %r, not IMSI %d" % (u, cm.imsi_of(rnti, mn), imsi)]
    return u, {"mEnbUeX2apId": rnti, "mnCellId": mn}, nodes, []


def flux_ue(tag):
    """UeMetrics rows of one ueId tag (U is a validated enGnbUeId key, so it is safe to embed)."""
    return ('from(bucket: "kpimon") |> range(start: 0) |> filter(fn: (r) => r._measurement == "UeMetrics" and '
            'r.ueId == "%s" and (r._field == "ns3.nodeId" or r._field == "ns3.seq")) '
            '|> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value") '
            '|> drop(columns: ["_start", "_stop"])' % tag)


def influx_rows(text, tag, nodes, step):
    """The latest (seq, node) of the rows with ueId U on those nodes at seq <= step, or None."""
    best = None
    for r, _ in N6.parse(text):
        try:
            n, s = int(r["ns3.nodeId"]), int(r["ns3.seq"])
        except (KeyError, TypeError, ValueError):
            continue
        if r.get("ueId") == tag and n in nodes and s <= step and (best is None or s > best[0]):
            best = (s, n)
    return best


def confirm(tag, nodes, step, deadline_s, poll_s, ue_csv=None):
    """({node, seq} of the latest row, None) or (None, problem); polls Influx until the row exists."""
    end = time.time() + deadline_s
    why = None
    while True:
        try:
            text = open(ue_csv).read() if ue_csv else N6.query(flux_ue(tag))
            got = influx_rows(text, tag, nodes, step)
            if got:
                return {"node": got[1], "seq": got[0]}, None
            why = "no UeMetrics row with ueId %s on gNB node(s) %s at seq <= %d" % (tag, nodes, step)
        except (RuntimeError, subprocess.TimeoutExpired, OSError) as ex:
            why = "influx query: %s" % ex
        if ue_csv or time.time() + poll_s > end:
            return None, why
        time.sleep(poll_s)


def prepare(trace_dir, step, imsi, out_base, context_only=False, deadline_s=20.0, poll_s=0.5, ue_csv=None):
    """Resolve, confirm and write the two files; (record or None, problems)."""
    u, ipc, nodes, problems = resolve(trace_dir, step, imsi)
    if problems:
        return None, problems
    row = None
    if not context_only:
        row, why = confirm(u, nodes, step, deadline_s, poll_s, ue_csv)
        if why:
            return None, [why]
    rec = {"step": step, "imsi": imsi, "ueId": u, "ipcUeId": ipc, "nodes": nodes, "influx": row}
    os.makedirs(os.path.dirname(os.path.abspath(out_base)), exist_ok=True)
    with open(out_base + ".json", "w") as f:
        json.dump(rec, f, sort_keys=True)
    with open(out_base + ".txt", "w") as f:
        f.write(u + "\n")
    return rec, []


def self_test():
    cm_mod = UECM
    bad = []
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        tr = d / "trace"
        cm_mod._fixture(tr)  # IMSI 1 (RNTI 3) on gNB 2 from seq 0, IMSI 2 (RNTI 4) from seq 2
        csv = d / "ue.csv"
        cols = ["_time", "_measurement", "ueId", "ns3.nodeId", "ns3.seq"]
        csv.write_text(N6._csv(cols, ["dateTime:RFC3339", "string", "string", "long", "long"],
                               [["2026-01-01T00:00:00Z", "UeMetrics", "enGnbUeId:3@00F110-00001", 2, 1],
                                ["2026-01-01T00:00:01Z", "UeMetrics", "enGnbUeId:4@00F110-00001", 2, 5]]))

        def case(name, want, *a, **kw):
            rec, p = prepare(str(tr), *a, **kw)
            if (rec is not None) != want:
                bad.append("%s: %r %r" % (name, rec, p))
            return rec
        rec = case("IMSI 1 at seq 1 resolves and Influx carries its key", True, 1, 1, str(d / "u1"), ue_csv=str(csv))
        if rec and (rec["ueId"], rec["ipcUeId"], rec["influx"]) != ("enGnbUeId:3@00F110-00001",
                                                                    {"mEnbUeX2apId": 3, "mnCellId": 1}, {"node": 2, "seq": 1}):
            bad.append("IMSI 1 record %r" % rec)
        if rec and open(str(d / "u1") + ".txt").read() != "enGnbUeId:3@00F110-00001\n":
            bad.append("the key file is not the key and a newline")
        case("IMSI 2 before it joins a gNB fails", False, 1, 2, str(d / "u2a"), ue_csv=str(csv))
        case("IMSI 2 at seq 3 without an Influx row at seq <= 3 fails", False, 3, 2, str(d / "u2b"), ue_csv=str(csv))
        case("IMSI 2 at seq 5 with its row at seq 5", True, 5, 2, str(d / "u2c"), ue_csv=str(csv))
        case("IMSI 2 at seq 3, context only", True, 3, 2, str(d / "u2d"), context_only=True)
        case("an IMSI no context holds fails", False, 3, 9, str(d / "u9"), context_only=True)
        if os.path.exists(str(d / "u2b") + ".txt"):
            bad.append("a failed prepare wrote its key file")
    for b in bad:
        print("FAIL " + b)
    print("ue-id-prepare self-test: %s" % ("ok" if not bad else "%d failure(s)" % len(bad)))
    return 1 if bad else 0


def main(av):
    if av == ["--self-test"]:
        return self_test()
    opts = {"--deadline-s": 20.0, "--poll-s": 0.5, "--ue-csv": None}
    ctx_only, pos, i = False, [], 0
    while i < len(av):
        if av[i] == "--context-only":
            ctx_only = True
        elif av[i] in opts:
            if i + 1 >= len(av):
                print(__doc__, file=sys.stderr)
                return 2
            opts[av[i]] = av[i + 1] if av[i] == "--ue-csv" else float(av[i + 1])
            i += 1
        else:
            pos.append(av[i])
        i += 1
    if len(pos) < 3 or not pos[1].isdigit() or any("=" not in x for x in pos[2:]):
        print(__doc__, file=sys.stderr)
        return 2
    trace, step, rc = pos[0], int(pos[1]), 0
    for spec in pos[2:]:
        imsi, _, out = spec.partition("=")
        rec, p = prepare(trace, step, int(imsi), out, ctx_only, opts["--deadline-s"], opts["--poll-s"], opts["--ue-csv"])
        print("ue-id seq %d imsi %s: %s" % (step, imsi, rec["ueId"] if rec else "FAIL " + "; ".join(p[:3])))
        rc |= 0 if rec else 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

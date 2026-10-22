#!/usr/bin/env python3
"""ipc-null-sink: stand-in E2 agent for ns-3 emitter gates (M4).

Listens on 127.0.0.1:<port> for each requested port, reads newline-delimited
JSON (schema ns3-e2-ipc v1, ns-3 -> agent only), counts lines per port and per
node, validates required keys structurally (stdlib only; full JSON-Schema
validation is added automatically when the `jsonschema` package is importable
and the schema file is found), and writes DIR/summary.json on SIGTERM/SIGINT.
Nothing is sent back to the emitter unless --controls is given. Run with
`python3 -I`.

  ipc-null-sink.py --ports 38471-38475 --out DIR [--save-lines] [--controls FILE]

--controls FILE (scripted free-run control, no RIC): a JSON list of
{"nodeId", "afterSeq", "imsi", "targetCellId"}. Right after receiving sample
`afterSeq` of `nodeId`, the sink writes one ns3-e2-ipc v1 minor 1 `control`
line on that node's connection (ctlId counts from 1 per node), as an agent
does. Every `controlAck` received is kept in DIR/control-acks.jsonl and every
control sent in DIR/controls-sent.jsonl.

--lockstep (ns3-e2-ipc v1 minor 2, an agent stand-in without the RIC): when a
hello says pacing "lockstep" the sink answers `step` -1 at once (ready) and
`step` k after every sample k, as an agent does; --withhold-step K never sends
step K, on every node or, with --withhold-node N, on node N only.

--ports accepts "38471-38475", "38472", "38471,38473", or a mix.
--save-lines writes every valid received line, verbatim, to DIR/lines-<nodeId>.jsonl
so it can be byte-compared with the emitter's local trace.
Prints "READY" on stdout once every listener is bound.
"""
import argparse
import asyncio
import json
import os
import signal
import sys

MAX_LINE = 1024 * 1024  # schema: at most 1 MiB per line
HOST = "127.0.0.1"
DEFAULT_SCHEMA = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..",
    "O-RAN-Testbed-Automation", "RAN_Intelligent_Controllers", "Near-Real-Time-RIC",
    "ns3_e2_agent", "schema", "ns3-e2-ipc.v1.schema.json")


def parse_ports(spec):
    ports = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            lo, hi = part.split("-", 1)
            ports.extend(range(int(lo), int(hi) + 1))
        else:
            ports.append(int(part))
    if not ports or any(not 0 < p < 65536 for p in ports):
        raise ValueError("bad --ports: %r" % spec)
    return sorted(set(ports))


def _is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def structural_errors(msg):
    """Required keys and types per ns3-e2-ipc v1; returns a list of problems."""
    if not isinstance(msg, dict):
        return ["not an object"]
    t = msg.get("type")
    errs = []

    def need(key, pred, what):
        if key not in msg:
            errs.append("missing " + key)
        elif not pred(msg[key]):
            errs.append("bad %s (want %s)" % (key, what))

    node_ok = lambda v: _is_int(v) and 1 <= v <= 65535
    nonneg = lambda v: _is_int(v) and v >= 0
    if t == "hello":
        need("schema", lambda v: v == "ns3-e2-ipc", "ns3-e2-ipc")
        need("v", lambda v: v == 1 and _is_int(v), "1")
        need("minor", nonneg, "int>=0")
        need("nodeId", node_ok, "int 1..65535")
        need("kind", lambda v: v in ("gnb", "enb"), "gnb|enb")
        need("periodNs", lambda v: _is_int(v) and v >= 1, "int>=1")
        need("simStartEpochMs", _is_int, "int")
        need("runId", lambda v: isinstance(v, str), "string")
    elif t == "sample":
        need("v", lambda v: v == 1 and _is_int(v), "1")
        need("nodeId", node_ok, "int 1..65535")
        need("seq", nonneg, "int>=0")
        need("simTimeNs", nonneg, "int>=0")
        need("ipcDropped", nonneg, "int>=0")
        need("cell", lambda v: isinstance(v, dict), "object")
        need("ues", lambda v: isinstance(v, list), "array")
        if isinstance(msg.get("ues"), list):
            prev = -1
            for u in msg["ues"]:
                if not isinstance(u, dict) or not nonneg(u.get("imsi")):
                    errs.append("ue without integer imsi")
                    break
                if u["imsi"] < prev:
                    errs.append("ues not sorted by imsi")
                    break
                prev = u["imsi"]
    elif t == "controlAck":
        need("nodeId", node_ok, "int 1..65535")
        need("ctlId", nonneg, "int>=0")
        need("outcome", lambda v: v in ("applied", "refused"), "applied|refused")
        need("cause", lambda v: isinstance(v, str), "string")
    elif t == "bye":
        need("nodeId", node_ok, "int 1..65535")
        for k in ("lastSeq", "built", "sent", "droppedDisconnected", "droppedBackpressure"):
            need(k, _is_int, "int")
    else:
        errs.append("unknown type %r" % (t,))
    return errs


class Sink:
    def __init__(self, ports, out_dir, save_lines, schema_path, controls=None, lockstep=False,
                 withhold_step=None, withhold_node=None):
        self.ports = ports
        self.out_dir = out_dir
        self.save_lines = save_lines
        self.port_stats = {p: {"connections": 0, "hello": 0, "sample": 0, "bye": 0,
                               "controlAck": 0, "invalid": 0, "bytes": 0} for p in ports}
        self.controls = {}  # (nodeId, afterSeq) -> [control spec, ...]
        for c in controls or []:
            self.controls.setdefault((c["nodeId"], c["afterSeq"]), []).append(c)
        self.next_ctl = {}
        self.lockstep = lockstep
        self.withhold_step = withhold_step
        self.withhold_node = withhold_node
        self.paced = set()  # nodes whose hello said lockstep
        self.sent_file = None
        self.ack_file = None
        self.nodes = {}
        self.imsis = set()
        self.invalid_examples = []
        self.line_files = {}
        self.validator = None
        self.validation = "structural"
        self.writers = set()
        self._load_validator(schema_path)

    def _load_validator(self, schema_path):
        try:
            import jsonschema  # optional
            with open(schema_path) as f:
                schema = json.load(f)
            self.validator = jsonschema.Draft202012Validator(schema)
            self.validation = "structural+jsonschema"
        except Exception:  # missing module/schema: structural only
            self.validator = None

    def node(self, nid, port):
        n = self.nodes.get(nid)
        if n is None:
            n = self.nodes[nid] = {
                "port": port, "kind": None, "hello": 0, "sample": 0, "bye": 0,
                "last_seq": None, "seq_gaps": 0, "ue_counts": {}, "ipc_dropped_last": 0,
                "ipc_dropped_max": 0, "period_ns": None, "run_ids": [], "bye_msg": None,
                "controlAck": 0, "controls_sent": 0}
        return n

    def invalid(self, port, reason, raw):
        self.port_stats[port]["invalid"] += 1
        if len(self.invalid_examples) < 20:
            self.invalid_examples.append({"port": port, "reason": reason,
                                          "line": raw[:200].decode("utf-8", "replace")})

    def _append(self, attr, name, line):
        f = getattr(self, attr)
        if f is None:
            f = open(os.path.join(self.out_dir, name), "w")
            setattr(self, attr, f)
        f.write(line + "\n")
        f.flush()

    def _inject(self, nid, seq, writer):
        for c in self.controls.pop((nid, seq), []):
            ctl = self.next_ctl.get(nid, 1)
            self.next_ctl[nid] = ctl + 1
            line = json.dumps({"type": "control", "v": 1, "nodeId": nid, "ctlId": ctl,
                               "imsi": c["imsi"], "targetCellId": c["targetCellId"],
                               "afterSeq": seq}, separators=(",", ":"))
            writer.write(line.encode() + b"\n")
            self.nodes[nid]["controls_sent"] += 1
            self._append("sent_file", "controls-sent.jsonl", line)

    def _step(self, nid, seq, writer):
        if seq == self.withhold_step and self.withhold_node in (None, nid):
            return
        line = json.dumps({"type": "step", "v": 1, "nodeId": nid, "seq": seq, "forwarded": 0,
                           "droppedNoSub": 0, "controls": self.nodes[nid]["controls_sent"]},
                          separators=(",", ":"))
        writer.write(line.encode() + b"\n")

    def accept(self, port, raw, writer=None):
        """Process one received line (bytes without the trailing newline)."""
        try:
            msg = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as e:
            return self.invalid(port, "json: %s" % e, raw)
        errs = structural_errors(msg)
        if not errs and self.validator is not None:
            first = next(iter(self.validator.iter_errors(msg)), None)
            if first is not None:
                errs = ["jsonschema: %s" % first.message[:150]]
        if errs:
            return self.invalid(port, "; ".join(errs), raw)
        t, nid = msg["type"], msg["nodeId"]
        self.port_stats[port][t] += 1
        n = self.node(nid, port)
        n[t] += 1
        if t == "hello":
            if self.lockstep and msg.get("pacing") == "lockstep" and writer is not None:
                self.paced.add(nid)
                self._step(nid, -1, writer)
            n["kind"] = msg["kind"]
            n["period_ns"] = msg["periodNs"]
            if msg["runId"] not in n["run_ids"]:
                n["run_ids"].append(msg["runId"])
        elif t == "sample":
            seq = msg["seq"]
            if n["last_seq"] is not None and seq != n["last_seq"] + 1:
                n["seq_gaps"] += 1
            n["last_seq"] = seq
            k = str(len(msg["ues"]))
            n["ue_counts"][k] = n["ue_counts"].get(k, 0) + 1
            n["ipc_dropped_last"] = msg["ipcDropped"]
            n["ipc_dropped_max"] = max(n["ipc_dropped_max"], msg["ipcDropped"])
            for u in msg["ues"]:
                self.imsis.add(u["imsi"])
            if self.save_lines:
                self._save(nid, raw)
            if writer is not None:
                self._inject(nid, seq, writer)
                if nid in self.paced:
                    self._step(nid, seq, writer)
        elif t == "controlAck":
            self._append("ack_file", "control-acks.jsonl", raw.decode())
        elif t == "bye":
            n["bye_msg"] = {k: msg[k] for k in ("lastSeq", "built", "sent",
                                                "droppedDisconnected", "droppedBackpressure")}

    def _save(self, nid, raw):
        f = self.line_files.get(nid)
        if f is None:
            f = self.line_files[nid] = open(
                os.path.join(self.out_dir, "lines-%d.jsonl" % nid), "wb")
        f.write(raw + b"\n")
        f.flush()

    async def handle(self, port, reader, writer):
        self.port_stats[port]["connections"] += 1
        self.writers.add(writer)
        try:
            while True:
                try:
                    raw = await reader.readuntil(b"\n")
                except asyncio.IncompleteReadError as e:
                    if e.partial:  # last line without newline
                        self.invalid(port, "unterminated final line", e.partial)
                    break
                except (asyncio.LimitOverrunError, ValueError):
                    self.invalid(port, "line over 1 MiB", b"")
                    break
                self.port_stats[port]["bytes"] += len(raw)
                raw = raw.rstrip(b"\r\n")
                if raw:
                    self.accept(port, raw, writer)
        except (ConnectionError, OSError):
            pass
        finally:
            self.writers.discard(writer)
            writer.close()

    def summary(self):
        tot = {k: sum(s[k] for s in self.port_stats.values())
               for k in ("hello", "sample", "bye", "controlAck", "invalid", "connections")}
        tot["controls_sent"] = sum(n["controls_sent"] for n in self.nodes.values())
        tot["controls_never_sent"] = sum(len(v) for v in self.controls.values())
        tot["distinct_imsis"] = sorted(self.imsis)
        tot["n_distinct_imsis"] = len(self.imsis)
        return {"schema": "ipc-null-sink-summary.v1", "validation": self.validation,
                "ports": {str(p): s for p, s in self.port_stats.items()},
                "nodes": {str(k): v for k, v in sorted(self.nodes.items())},
                "totals": tot, "invalid_examples": self.invalid_examples}


async def main_async(args):
    controls = None
    if args.controls:
        with open(args.controls) as f:
            controls = json.load(f)
    sink = Sink(parse_ports(args.ports), args.out, args.save_lines, args.schema, controls,
                args.lockstep, args.withhold_step, args.withhold_node)
    os.makedirs(args.out, exist_ok=True)
    servers = []
    for p in sink.ports:
        servers.append(await asyncio.start_server(
            lambda r, w, p=p: sink.handle(p, r, w), HOST, p, limit=MAX_LINE))
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    print("READY", flush=True)
    await stop.wait()
    for s in servers:
        s.close()
    await asyncio.sleep(0.2)  # let in-flight lines land
    for w in list(sink.writers):
        w.close()
    await asyncio.sleep(0.05)
    for f in list(sink.line_files.values()) + [sink.sent_file, sink.ack_file]:
        if f is not None:
            f.close()
    tmp = os.path.join(args.out, "summary.json.tmp")
    with open(tmp, "w") as f:
        json.dump(sink.summary(), f, indent=2)
    os.replace(tmp, os.path.join(args.out, "summary.json"))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--ports", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--save-lines", action="store_true")
    ap.add_argument("--schema", default=DEFAULT_SCHEMA)
    ap.add_argument("--controls", help="JSON list of scripted controls (see the module doc)")
    ap.add_argument("--lockstep", action="store_true", help="answer step lines when paced")
    ap.add_argument("--withhold-step", type=int, help="never send this step")
    ap.add_argument("--withhold-node", type=int, help="withhold the step on this node only")
    args = ap.parse_args()
    try:
        asyncio.run(main_async(args))
    except OSError as e:
        print("ipc-null-sink: cannot bind: %s" % e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

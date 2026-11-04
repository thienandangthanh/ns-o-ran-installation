#!/usr/bin/env python3
"""reference-transform-compare.py: a live run against T(M9 files), the AC8b compare (plan R-2, R-8; Amendment 1).

  reference-transform-compare.py compare RUN M9RAW M9REF --file scenario=F --file schedule=F --file stage-a=F
  reference-transform-compare.py --selftest

RUN is a live run dir (trace/, ns3run/, r3p/, extra/). M9RAW holds the promoted raw M9 (or cp1 δ) files
(scenario/, r3p/, trace/, extra/, each listed in M9RAW/SHA256SUMS), M9REF the reference digests (digests.json, listed
in its parent's SHA256SUMS). The --file scenario, schedule and stage-a files are the ones the run used (the harness's
committed r3p files). The identity map is the identity-map-cp1.json of the nearest ancestor of M9RAW that holds one,
verified against the SHA256SUMS beside it. Every input's sha256 is checked before it is read.

Components and their predicates (any other differing byte fails and names its file and field):
  ipc, traces                   literal: digest-run.py's digests of RUN equal M9REF's (no ueContext line in the ipc trace)
  kpm-headers, collet-start-time literal: RUN/extra bytes equal M9RAW/extra bytes
  scenario, schedule, stage-a, predictor-records, ledger, rc-multiset   RUN bytes equal T(M9RAW bytes)
T (m9-transform.py) may touch only R-2's fields: every structural difference between an M9 file and T(it) must
classify into R-2's list, and the fields so touched, plus those whose source form occurs in no input (fieldsWithout
Occurrence), must equal R-2's list exactly. The JSON on stdout carries transformEqualsM9, transformedFields,
transformedFieldCounts, fieldsWithoutOccurrence, literalComponents and problems. Exit 0 equal, 1 not, 2 bad input.
"""
import hashlib, importlib.util, json, pathlib, re, shutil, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


T = _module("m9_transform", HERE / "m9-transform.py")
DIGEST = _module("digest_run", HERE / "digest-run.py")
FIXTURES = HERE / "fixtures" / "transform-compare"
MEID_RE = re.compile(r"\bgnb_001_001_[0-9a-f]{8}\b|\benB_macro_[0-9a-f_]+\b")
LITERAL_EXTRA = ("kpm-headers", "collet-start-time")


class Bad(Exception):
    """An input that cannot be compared (missing, not in its SHA256SUMS, or not matching it): exit 2."""


def sha_file(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


def verified(path):
    """The bytes of path, after its entry in the nearest ancestor SHA256SUMS (up to 3 levels) matched."""
    path = pathlib.Path(path).resolve()
    if not path.is_file():
        raise Bad(f"missing input {path}")
    for d in list(path.parents)[:3]:
        sums = d / "SHA256SUMS"
        if not sums.is_file():
            continue
        for line in sums.read_text().splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2 and (d / parts[1].strip()).resolve() == path:
                if parts[0] != sha_file(path):
                    raise Bad(f"{path} does not match its entry in {sums}")
                return path.read_text()
    raise Bad(f"{path} is in no SHA256SUMS of its three nearest ancestors")


def identity_map_path(m9raw):
    for d in [pathlib.Path(m9raw).resolve(), *pathlib.Path(m9raw).resolve().parents][:4]:
        if (d / "identity-map-cp1.json").is_file():
            return d / "identity-map-cp1.json"
    raise Bad(f"no identity-map-cp1.json in {m9raw} or its three nearest ancestors")


def json_paths(a, b, path=()):
    """The paths at which two parsed JSON values differ (a key present on one side only is a difference)."""
    if isinstance(a, dict) and isinstance(b, dict):
        out = []
        for k in sorted(set(a) | set(b)):
            out += json_paths(a.get(k, KeyError), b.get(k, KeyError), path + (k,)) if k in a and k in b else [path + (k,)]
        return out
    if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        return [p for i, (x, y) in enumerate(zip(a, b)) for p in json_paths(x, y, path + (i,))]
    return [] if a == b and type(a) is type(b) else [path]


def text_paths(a, b, jsonl):
    """Differing paths of two JSON (or JSON-lines) texts; a line index leads each JSON-lines path."""
    if jsonl:
        la, lb = a.splitlines(), b.splitlines()
        if len(la) != len(lb):
            return [("line count", len(la), len(lb))]
        return [(i,) + p for i, (x, y) in enumerate(zip(la, lb)) for p in json_paths(json.loads(x), json.loads(y))]
    return json_paths(json.loads(a), json.loads(b))


def classify(kind, path, old_doc):
    """The R-2 field a structural difference between an M9 file and T(it) belongs to, or None."""
    last = path[-1] if path else None
    keyish = [x for x in path if isinstance(x, str)]
    if kind == "scenario":
        if path[:1] == ("cells",):
            return "scenario.cells"
        if last == "ueId":
            return "scenario.ueId-description"
        if last == "inject" and "stageB" in keyish:
            return "scenario.stageB-P1-text"
        return None
    if kind in ("schedule", "stage-a"):
        if last == "scenarioSha256":
            return f"{kind}.scenarioSha256"
        if last == "via":
            return "schedule.via" if kind == "schedule" else "stage-a.h1.via"
        v = old_doc
        for x in path:
            v = v[x]
        return f"{kind}.keys" if isinstance(v, str) and T.N5_RE.fullmatch(v) else None
    if kind == "predictor-records":
        return {"answer": "predictor-records.answer-keys", "target": "predictor-records.target"}.get(path[1])
    if kind == "ledger":
        return "ledger.viaNodeId" if last == "viaNodeId" else None
    if kind == "rc-multiset":
        if len(path) >= 2 and path[1] in ("imsi", "ueId"):
            return "rc-multiset.imsi-to-ueId"
        return {"viaNode": "rc-multiset.viaNode", "style": "rc-multiset.style", "action": "rc-multiset.action",
                "targetKey": "rc-multiset.targetKey"}.get(str(path[1])) if len(path) > 1 else None
    return None


def compare(run, m9raw, m9ref, files):
    run, m9raw = pathlib.Path(run), pathlib.Path(m9raw)
    problems, counts, literal = [], {f: 0 for f in T.FIELDS}, []

    def need(cond, file, field, why):
        if not cond:
            problems.append({"file": file, "field": field, "why": why})
        return cond

    ref = json.loads(verified(pathlib.Path(m9ref) / "digests.json"))
    got = DIGEST.digests(run)
    need(got["ipcTraceUeContextLines"] == 0, "trace/e2-ipc-trace-*.jsonl", "ueContext",
         f"{got['ipcTraceUeContextLines']} ueContext line(s) in the ipc trace")
    for n in sorted(set(got["ipc"]) | set(ref["ipc"])):
        need(got["ipc"].get(n) == ref["ipc"].get(n), f"trace/e2-ipc-trace-{n}.jsonl", "sample lines",
             "the ipc sample digest differs from the reference")
    for n in sorted(set(got["traces"]) | set(ref["traces"])):
        need(got["traces"].get(n) == ref["traces"].get(n), f"ns3run/{n}", "file", "the trace digest differs from the reference")
    literal += ["ipc", "traces"]
    for n in LITERAL_EXTRA:
        rp = run / "extra" / f"{n}.json"
        if need(rp.is_file(), f"extra/{n}.json", "file", "missing in the run"):
            need(rp.read_text() == verified(m9raw / "extra" / f"{n}.json"), f"extra/{n}.json", "bytes",
                 "differs from the M9 file, which no transform touches")
        literal.append(n)

    im_path = identity_map_path(m9raw)
    idmap = json.loads(verified(im_path))
    m9 = {k: verified(m9raw / rel) for k, rel in [
        ("scenario", "scenario/r3p-scenario.json"), ("schedule", "scenario/r3p-schedule.json"),
        ("stage-a", "scenario/r3p-stage-a.json"), ("predictor-records", "r3p/predictor-records.jsonl"),
        ("ledger", "trace/e2-control-ledger.jsonl"), ("rc-multiset", "extra/rc-multiset.json")]}
    runf = {"scenario": pathlib.Path(files["scenario"]), "schedule": pathlib.Path(files["schedule"]),
            "stage-a": pathlib.Path(files["stage-a"]), "predictor-records": run / "r3p" / "predictor-records.jsonl",
            "ledger": run / "trace" / "e2-control-ledger.jsonl", "rc-multiset": run / "extra" / "rc-multiset.json"}
    transform = {
        "scenario": lambda t: T.t_scenario(t),
        "schedule": lambda t: T.t_schedule_like(t, m9["scenario"], m9["ledger"], "schedule"),
        "stage-a": lambda t: T.t_schedule_like(t, m9["scenario"], m9["ledger"], "stage-a"),
        "predictor-records": lambda t: T.t_predictor_records(t, m9["scenario"]),
        "ledger": lambda t: T.t_ledger(t),
        "rc-multiset": lambda t: T.t_rc_multiset(t, m9["ledger"], idmap, m9["scenario"]),
    }
    meid_seen = False
    for kind, old in m9.items():
        jsonl = kind in ("predictor-records", "ledger")
        meid_seen |= bool(MEID_RE.search(old))
        try:
            new = transform[kind](old)
        except T.TransformError as e:
            need(False, kind, "T", f"T refused the M9 file: {e}")
            continue
        old_docs = [json.loads(l) for l in old.splitlines()] if jsonl else json.loads(old)
        for p in text_paths(old, new, jsonl):
            doc = old_docs[p[0]] if jsonl else old_docs
            f = classify(kind, p, doc) if p and p[0] != "line count" else None
            if need(f is not None, kind, "/".join(map(str, p)), "T changed a field outside R-2's list"):
                counts[f] += 1
        rp = runf[kind]
        if not need(rp.is_file(), str(rp.name), "file", "missing in the run"):
            continue
        have = rp.read_text()
        if have != new:
            try:
                paths = text_paths(new, have, jsonl)
            except ValueError:
                paths = []
            for p in paths or [("bytes",)]:
                need(False, f"{kind} ({rp.name})", "/".join(map(str, p)), "differs from T(M9)")
    without = sorted(f for f, n in counts.items() if n == 0)
    # meid: R-2 maps every M9 meid; a meid in no compared M9 file is the one field allowed no occurrence
    for f in without:
        need(f == "meid" and not meid_seen, "T", f, "an R-2 field T never rewrote although its source form occurs")
    touched = [f for f in T.FIELDS if counts[f] > 0]
    need(sorted(touched + [f for f in without if f == "meid" and not meid_seen]) == sorted(T.FIELDS), "T",
         "transformedFields", "the touched fields differ from R-2's list")
    return {"transformEqualsM9": not problems, "transformedFields": touched, "transformedFieldCounts": counts,
            "fieldsWithoutOccurrence": without, "literalComponents": literal, "identityMap": str(im_path),
            "identityMapSha256": sha_file(im_path), "problems": problems}


def build_world(t):
    """A run that equals T(M9) for the committed M9 raw files, with a synthetic ns3run/ and ipc trace whose digests
    are written as the M9REF (the real M9 traces are not in git): the base every fixture mutates."""
    src = HERE.parent.parent / "plans/261103-0008-GH-1-post-m9-realism-m10/reference"
    m9raw, m9ref, run = t / "reference" / "m9raw", t / "m9ref" / "equal", t / "run"
    shutil.copytree(src / "m9-r3p-raw", m9raw, ignore=shutil.ignore_patterns("ns3run"))
    (m9raw / "SHA256SUMS").write_text("".join(l + "\n" for l in (m9raw / "SHA256SUMS").read_text().splitlines()
                                              if "ns3run/" not in l))
    shutil.copy(src / "identity-map-cp1.json", t / "reference")
    shutil.copy(src / "SHA256SUMS", t / "reference")
    for d in ("trace", "ns3run", "r3p", "extra"):
        (run / d).mkdir(parents=True)
    (run / "trace" / "e2-ipc-trace-2.jsonl").write_text(
        '{"type":"hello","nodeId":2,"kind":"gnb"}\n{"type":"sample","nodeId":2,"seq":0,"ipcDropped":0,"ues":[]}\n')
    (run / "ns3run" / "CellIdStats.txt").write_text("1 2 3\n")
    for n in LITERAL_EXTRA:
        shutil.copy(m9raw / "extra" / f"{n}.json", run / "extra")
    scen, led = (m9raw / "scenario/r3p-scenario.json").read_text(), (m9raw / "trace/e2-control-ledger.jsonl").read_text()
    idmap = json.loads((t / "reference" / "identity-map-cp1.json").read_text())
    files = {k: t / f"r3p-{k}.json" for k in ("scenario", "schedule", "stage-a")}
    files["scenario"].write_text(T.t_scenario(scen))
    for k in ("schedule", "stage-a"):
        files[k].write_text(T.t_schedule_like((m9raw / f"scenario/r3p-{k}.json").read_text(), scen, led, k))
    (run / "r3p/predictor-records.jsonl").write_text(T.t_predictor_records((m9raw / "r3p/predictor-records.jsonl").read_text(), scen))
    (run / "trace/e2-control-ledger.jsonl").write_text(T.t_ledger(led))
    (run / "extra/rc-multiset.json").write_text(T.t_rc_multiset((m9raw / "extra/rc-multiset.json").read_text(), led, idmap, scen))
    m9ref.mkdir(parents=True)
    d = DIGEST.digests(run)
    (m9ref / "digests.json").write_text(json.dumps({k: d[k] for k in ("ipc", "ledger", "traces", "extra")}, indent=1))
    (m9ref.parent / "SHA256SUMS").write_text(f"{sha_file(m9ref / 'digests.json')}  equal/digests.json\n")
    return run, m9raw, m9ref, {k: str(v) for k, v in files.items()}


def mutate(world, fx):
    """Applies one fixture's byte edit: `old` -> `new` at its first occurrence (which must exist), or byte `offset`
    XOR `xor`. side m9 edits an M9 raw file and re-writes its SHA256SUMS entry (so only the compare can catch it), run
    a run file, harness one of the committed r3p files the run used."""
    run, m9raw, _, files = world
    target = pathlib.Path(files[fx["file"]]) if fx["side"] == "harness" else {"m9": m9raw, "run": run}[fx["side"]] / fx["file"]
    b = target.read_bytes()
    if "xor" in fx:
        b = b[:fx["offset"]] + bytes([b[fx["offset"]] ^ fx["xor"]]) + b[fx["offset"] + 1:]
    else:
        old, new = fx["old"].encode(), fx["new"].encode()
        if old not in b:
            raise AssertionError(f"fixture text {fx['old']!r} is not in {target}")
        b = b.replace(old, new, 1)
    target.write_bytes(b)
    if fx["side"] == "m9":
        rel = "./" + fx["file"]
        lines = [l if l.split(None, 1)[1].strip() != rel else f"{sha_file(target)}  {rel}"
                 for l in (m9raw / "SHA256SUMS").read_text().splitlines()]
        (m9raw / "SHA256SUMS").write_text("\n".join(lines) + "\n")


def self_test():
    bad = []
    fixtures = sorted(FIXTURES.glob("*.json"))
    if [f.name[0] for f in fixtures] != list("abcdefghij"):
        print("FAIL: fixtures a-j are not exactly present:", [f.name for f in fixtures])
        return 1
    for f in fixtures:
        fx = json.loads(f.read_text())
        with tempfile.TemporaryDirectory() as t:
            t = pathlib.Path(t)
            world = build_world(t)
            if fx.get("mutation"):
                mutate(world, fx["mutation"])
            run, m9raw, m9ref, files = world
            try:
                out = compare(run, m9raw, m9ref, files)
                ok = out["transformEqualsM9"]
            except Bad as e:
                out, ok = {"bad": str(e)}, False
            want = fx["expect"] == "pass"
            if ok != want:
                bad.append(f"{f.name}: compare said {'equal' if ok else 'not equal'}, want {fx['expect']}: "
                           f"{json.dumps(out.get('problems', out))[:300]}")
            elif not want and not out.get("problems") and "bad" not in out:
                bad.append(f"{f.name}: failed without naming a file and field")
            elif want and sorted(out["transformedFields"] + [x for x in out["fieldsWithoutOccurrence"]]) != sorted(T.FIELDS):
                bad.append(f"{f.name}: transformedFields {out['transformedFields']} is not R-2's list")
            print(f"{f.name}: {'pass' if ok else 'fail'} (want {fx['expect']})"
                  + ("" if ok else f": {(out.get('problems') or [out])[0]}"))
    # an identity map that is not the frozen one is refused before any compare
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        run, m9raw, m9ref, files = build_world(t)
        im = t / "reference" / "identity-map-cp1.json"
        im.write_text(im.read_text().replace('"mEnbUeX2apId": 3', '"mEnbUeX2apId": 9'))
        try:
            compare(run, m9raw, m9ref, files)
            bad.append("an identity map that does not match its SHA256SUMS was used")
        except Bad:
            print("identity map off its SHA256SUMS: refused")
    # a T that also rewrites a field outside R-2's list is caught, even when the run carries the same rewrite
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        run, m9raw, m9ref, files = build_world(t)
        led = run / "trace" / "e2-control-ledger.jsonl"
        led.write_text(led.read_text().replace('"targetCell":2', '"targetCell":4'))
        orig = T.t_ledger
        T.t_ledger = lambda text: orig(text).replace('"targetCell":2', '"targetCell":4')
        try:
            out = compare(run, m9raw, m9ref, files)
        finally:
            T.t_ledger = orig
        if out["transformEqualsM9"] or not any(p["why"] == "T changed a field outside R-2's list" for p in out["problems"]):
            bad.append("a T that rewrote ledger targetCell was not caught")
        else:
            print("T rewriting a field outside R-2's list: caught")
    for b in bad:
        print("FAIL:", b)
    print("reference-transform-compare self-test:", "FAIL" if bad else "ok")
    return 1 if bad else 0


def main(av):
    if av[:1] == ["--selftest"]:
        return self_test()
    if len(av) < 4 or av[0] != "compare":
        print(__doc__, file=sys.stderr)
        return 2
    files = {}
    rest = av[4:]
    while rest:
        if rest[0] != "--file" or len(rest) < 2 or "=" not in rest[1]:
            print(f"bad argument {rest[0]}", file=sys.stderr)
            return 2
        k, v = rest[1].split("=", 1)
        files[k] = v
        rest = rest[2:]
    if sorted(files) != ["scenario", "schedule", "stage-a"]:
        print("need --file scenario=, schedule= and stage-a=", file=sys.stderr)
        return 2
    try:
        out = compare(av[1], av[2], av[3], files)
    except Bad as e:
        print(json.dumps({"transformEqualsM9": False, "bad": str(e)}))
        return 2
    print(json.dumps(out, indent=1))
    return 0 if out["transformEqualsM9"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

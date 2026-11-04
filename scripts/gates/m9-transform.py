#!/usr/bin/env python3
"""m9-transform.py: T, the enumerated rewrite of M9 files into their compliant form (plan R-2, contract AC8b / A1).

T is pure: each function maps the bytes of an M9 file (and, where R-2 names one, the M9 ledger or the frozen cp1
identity map) to the bytes the compliant harness must have. Every rewrite is a byte-level substitution that must
occur exactly the expected number of times, so a drifting input fails loudly instead of passing half-transformed.
Everything R-2 does not name stays byte-literal: IMSIs, steps, decisions, windows and every predictor number.

R-2's transforms (FIELDS lists them; the compare reports them as transformedFields):
  N5 cell key -> NCI key (%08X%02X -> %08X + "1" + "0") on key-valued fields only: the scenario's cells, the
  schedule's and stage-A classification's key fields, the predictor records' answer keys and target, and
  rc-multiset's targetKey. The N5 keys are exactly the values of the M9 scenario's "cells" map.
  via target -> source: the schedule's and stage-A's single "via", the ledger's viaNodeId and rc-multiset's viaNode,
  taken from the M9 ledger line's sourceCell.
  scenarioSha256 recomputed from T(scenario); the P1 description string and the ueId description replaced by the
  registered texts; rc-multiset style/action 3/1 -> 5/3 and imsi -> ueId (en-gNB-UEID from the identity map);
  meids gnb_001_001_%08x -> en_gnb_001_001_%08x and the eNB -> enB_macro_001_001_000001.

  m9-transform.py <kind> <M9 file> [--m9-raw DIR] [--identity-map FILE]   writes T(file) to stdout
      kind: scenario | schedule | stage-a | predictor-records | ledger | rc-multiset
"""
import hashlib, json, re, sys

FIELDS = [
    "scenario.cells", "scenario.ueId-description", "scenario.stageB-P1-text",
    "schedule.keys", "schedule.via", "schedule.scenarioSha256",
    "stage-a.keys", "stage-a.h1.via", "stage-a.scenarioSha256",
    "predictor-records.answer-keys", "predictor-records.target",
    "ledger.viaNodeId",
    "rc-multiset.viaNode", "rc-multiset.imsi-to-ueId", "rc-multiset.style", "rc-multiset.action",
    "rc-multiset.targetKey",
    "meid",
]
P1_OLD = "via the target gNB (deviation P1)"
P1_NEW = "via the source en-gNB (SN-initiated, E2SM-RC Style 5 action 3)"
UEID_OLD = '"ueId": "decimal IMSI string"'
UEID_NEW = '"ueId": "the KPM UE ID key of AC14b (en-gNB-UEID)"'
N5_RE = re.compile(r"[0-9A-F]{8}[0-9A-F]{2}")


class TransformError(Exception):
    pass


def need(cond, why):
    if not cond:
        raise TransformError(why)


def nci_key(n5):
    need(N5_RE.fullmatch(n5) is not None, f"not an N5 cell key: {n5!r}")
    return n5[:8] + "10"


def n5_keys(m9_scenario_text):
    """The M9 scenario's cell keys, each the registered N5 encoding of its cell: %08X%02X of the cellId, both parts."""
    cells = json.loads(m9_scenario_text)["cells"]
    for cell, key in cells.items():
        need(str(cell).isdigit() and key == "%08X%02X" % (int(cell), int(cell)),
             f"the M9 scenario's cell {cell} key {key!r} is not its N5 encoding")
    keys = sorted(set(cells.values()))
    need(keys, "the M9 scenario has no cells")
    return keys


def sub_keys(text, keys):
    """Every quoted occurrence of an N5 key becomes its NCI key; at least one must occur. The input may hold no other
    10-hex key (a key outside the scenario's N5 keys, an already converted NCI key included, is drift), and none
    may remain after the rewrite."""
    before = set(re.findall(r'"([0-9A-F]{10})"', text)) - set(keys)
    need(not before, f"cell keys other than the scenario's N5 keys in the M9 input: {sorted(before)}")
    n = 0
    for k in keys:
        n += text.count(f'"{k}"')
        text = text.replace(f'"{k}"', f'"{nci_key(k)}"')
    need(n > 0, "no N5 key to rewrite")
    stray = set(re.findall(r'"([0-9A-F]{10})"', text)) - {nci_key(k) for k in keys}
    need(not stray, f"cell keys outside the scenario's cells: {sorted(stray)}")
    return text


def sub_once(text, old, new, what):
    need(text.count(old) == 1, f"{what}: {old!r} occurs {text.count(old)} times, want 1")
    return text.replace(old, new)


def m9_applied(m9_ledger_text):
    lines = [json.loads(l) for l in m9_ledger_text.splitlines() if l.strip()]
    ctl = [d for d in lines if "ctlId" in d]
    applied = [d for d in ctl if d.get("outcome") == "applied"]
    need(len(applied) == 1, f"the M9 ledger has {len(applied)} applied lines, want 1 (h1)")
    return ctl, applied[0]


def t_scenario(text):
    text = sub_keys(text, n5_keys(text))
    text = sub_once(text, UEID_OLD, UEID_NEW, "scenario ueId description")
    return sub_once(text, P1_OLD, P1_NEW, "scenario P1 text")


def t_schedule_like(text, m9_scenario_text, m9_ledger_text, what):
    """The schedule and the stage-A classification: keys, the single h1 "via", scenarioSha256."""
    _, h1 = m9_applied(m9_ledger_text)
    text = sub_keys(text, n5_keys(m9_scenario_text))
    via = re.findall(r'"via": (\d+)', text)
    need(via == [str(h1["viaNodeId"])], f"{what}: via {via}, want exactly the M9 h1 viaNodeId {h1['viaNodeId']}")
    text = text.replace(f'"via": {via[0]}', f'"via": {h1["sourceCell"]}')
    old = hashlib.sha256(m9_scenario_text.encode()).hexdigest()
    new = hashlib.sha256(t_scenario(m9_scenario_text).encode()).hexdigest()
    return sub_once(text, f'"scenarioSha256": "{old}"', f'"scenarioSha256": "{new}"', f"{what} scenarioSha256")


def t_predictor_records(text, m9_scenario_text):
    keys = n5_keys(m9_scenario_text)
    out = []
    for line in text.splitlines(keepends=True):
        d = json.loads(line)
        need(set(re.findall(r'"([0-9A-F]{10})"', line)) <= set(keys), f"a predictor line holds a key outside {keys}")
        new = line
        for k in keys:
            new = new.replace(f'"{k}"', f'"{nci_key(k)}"')
        e = json.loads(new)
        need({k: v for k, v in e.items() if k not in ("answer", "target")} ==
             {k: v for k, v in d.items() if k not in ("answer", "target")}, "a predictor field outside answer/target moved")
        out.append(new)
    return "".join(out)


def t_ledger(text):
    out = []
    for line in text.splitlines(keepends=True):
        d = json.loads(line)
        if "ctlId" in d:
            line = sub_once(line, f'"viaNodeId":{d["viaNodeId"]},', f'"viaNodeId":{d["sourceCell"]},', "ledger viaNodeId")
        out.append(line)
    return "".join(out)


def meid(s):
    m = re.fullmatch(r"gnb_001_001_([0-9a-f]{8})", s)
    if m:
        return "en_gnb_001_001_" + m.group(1)
    return s


def t_rc_multiset(text, m9_ledger_text, idmap, m9_scenario_text):
    need(json.dumps(json.loads(text), indent=1, sort_keys=True) + "\n" == text,
         "the M9 rc-multiset is not in the extractor's format (indent 1, sorted keys)")
    ctl, _ = m9_applied(m9_ledger_text)
    out = []
    for e in json.loads(text):
        src = [d["sourceCell"] for d in ctl if d["afterSeq"] == e["step"] and d["imsi"] == e["imsi"]]
        need(len(src) == 1, f"rc-multiset entry step {e['step']} imsi {e['imsi']} matches {len(src)} M9 ledger lines")
        need((e["style"], e["action"]) == (3, 1), f"M9 rc-multiset style/action {(e['style'], e['action'])}, want (3, 1)")
        need(e["targetKey"] in n5_keys(m9_scenario_text), f"M9 rc-multiset targetKey {e['targetKey']!r} is not a scenario cell key")
        ue = idmap["ues"][str(e.pop("imsi"))]
        e.update(viaNode=src[0], style=5, action=3, targetKey=nci_key(e["targetKey"]),
                 ueId={"type": "en-gNB-UEID", "mEnbUeX2apId": ue["mEnbUeX2apId"], "globalEnbId": idmap["globalEnbId"]})
        e = {k: meid(v) if isinstance(v, str) else v for k, v in e.items()}
        out.append(e)
    return json.dumps(out, indent=1, sort_keys=True) + "\n"


def main(av):
    if len(av) < 2 or av[0] not in ("scenario", "schedule", "stage-a", "predictor-records", "ledger", "rc-multiset"):
        print(__doc__, file=sys.stderr)
        return 2
    kind, path = av[0], av[1]
    opt = dict(zip(av[2::2], av[3::2]))
    text = open(path).read()
    raw = opt.get("--m9-raw", "")
    scen = open(f"{raw}/scenario/r3p-scenario.json").read() if raw else None
    led = open(f"{raw}/trace/e2-control-ledger.jsonl").read() if raw else None
    try:
        if kind == "scenario":
            out = t_scenario(text)
        elif kind in ("schedule", "stage-a"):
            out = t_schedule_like(text, scen, led, kind)
        elif kind == "predictor-records":
            out = t_predictor_records(text, scen)
        elif kind == "ledger":
            out = t_ledger(text)
        else:
            out = t_rc_multiset(text, led, json.load(open(opt["--identity-map"])), scen)
    except (TransformError, KeyError, TypeError, ValueError) as e:
        print(f"m9-transform: {kind}: {e}", file=sys.stderr)
        return 1
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

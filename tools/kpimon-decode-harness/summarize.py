#!/usr/bin/env python3
"""summarize.py [harness.jsonl] [-o summary.json]

Reads kpimon-decode-harness JSONL (file or stdin) and prints (and optionally
writes) a JSON summary: totals, header/message return-code counts, ts_len and
msg_format histograms.
"""
import json
import sys
from collections import Counter


def main(argv):
    out_path = None
    src = None
    i = 1
    while i < len(argv):
        if argv[i] == "-o" and i + 1 < len(argv):
            out_path = argv[i + 1]
            i += 2
        else:
            src = argv[i]
            i += 1
    fh = open(src) if src else sys.stdin
    hdr, msg, ts, fmt = Counter(), Counter(), Counter(), Counter()
    total = 0
    hdr_trail = msg_trail = 0
    for line in fh:
        line = line.strip()
        if not line:
            continue
        r = json.loads(line)
        total += 1
        hdr[r["hdr_code"]] += 1
        msg[r["msg_code"]] += 1
        if r["hdr_code"] == "RC_OK" and r["hdr_consumed"] < r["hdr_len"]:
            hdr_trail += 1
        if r["msg_code"] == "RC_OK" and r["msg_consumed"] < r["msg_len"]:
            msg_trail += 1
        ts[str(r["ts_len"])] += 1
        fmt[str(r["msg_format"])] += 1
    summary = {
        "total": total,
        "hdr": {k: hdr.get(k, 0) for k in ("RC_OK", "RC_WMORE", "RC_FAIL")},
        "msg": {k: msg.get(k, 0) for k in ("RC_OK", "RC_WMORE", "RC_FAIL")},
        "hdr_other": {k: v for k, v in hdr.items() if k not in ("RC_OK", "RC_WMORE", "RC_FAIL")},
        "msg_other": {k: v for k, v in msg.items() if k not in ("RC_OK", "RC_WMORE", "RC_FAIL")},
        "hdr_ok_with_trailing_bytes": hdr_trail,
        "msg_ok_with_trailing_bytes": msg_trail,
        "ts_len_hist": dict(ts),
        "msg_format_hist": dict(fmt),
    }
    text = json.dumps(summary, indent=2, sort_keys=True)
    print(text)
    if out_path:
        with open(out_path, "w") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main(sys.argv)

#!/usr/bin/env python3
"""ts-influx-query-selftest.py: the TS xApp's UeMetrics existence query against a real InfluxDB 2.7 (run by lint.sh).

A throwaway InfluxDB 2.7 container (podman, localhost only, test-only credentials) is loaded with
fixtures/ts-influx-mixed/ue-metrics.lp: UeMetrics points of two ueId tags with integer and float fields, cut from a
live kpimon bucket, each point stamped a few seconds before now so it lies inside the query's window. Then:
  - the query that the TS xApp patch at the pinned Testbed commit builds (taken from the patch text, its C++ string
    concatenation evaluated, not retyped) answers HTTP 200 with a `_time` record for a present tag, and with none for
    a well-formed tag that has no point;
  - the pre-fix query (the same patch at PREFIX_TESTBED_SHA: group() before keep()) answers HTTP 400 "schema
    collision", which proves the fixture holds both field types; its body is written to --http400-body if given.
Exit 0 pass, 1 fail, 77 SKIP (no podman, no influxdb:2.7 image, or no Testbed clone with both commits).
"""
import pathlib, re, shutil, subprocess, sys, time, urllib.error, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
HARNESS = HERE.parent.parent
TESTBED = HARNESS / "O-RAN-Testbed-Automation"
PATCH = ("RAN_Intelligent_Controllers/Near-Real-Time-RIC/install_patch_files/xApps/ts/src/ts_xapp/"
         "ts_xapp.cpp.style5_en_gnb_ueid.patch")
PREFIX_TESTBED_SHA = "faeeb3482a0605a0da1c7d55ff24f158922562d8"  # the TS query before "keep only _time, then group"
IMAGE = "docker.io/library/influxdb:2.7"
ORG, BUCKET, TOKEN = "selftest", "kpimon", "selftest-token-local-only"
PRESENT, ABSENT = "enGnbUeId:1@00F110-00001", "enGnbUeId:7@00F110-00001"


def skip(why):
    print("SKIP:", why)
    sys.exit(77)


def pinned_testbed_sha():
    for line in (HARNESS / "scripts/pins.conf").read_text().splitlines():
        m = re.match(r'\s*TESTBED_SHA="?([0-9a-f]{40})"?', line)
        if m:
            return m.group(1)
    sys.exit("FAIL: no TESTBED_SHA in scripts/pins.conf")


def patch_text(sha):
    r = subprocess.run(["git", "-C", str(TESTBED), "show", f"{sha}:{PATCH}"], capture_output=True, text=True)
    if r.returncode:
        skip(f"the Testbed clone {TESTBED} has no {PATCH} at {sha[:12]}")
    return r.stdout


def query_from_patch(text, tag):
    """Evaluates the patch's `const string flux = ...;` with only the names it may use."""
    added = [l[1:] for l in text.splitlines() if l.startswith("+")]
    window = next((m.group(1) for l in added for m in [re.search(r'kUeMetricsWindow\s*=\s*"([^"]*)"', l)] if m), None)
    start = next((i for i, l in enumerate(added) if re.search(r"\bconst string flux\s*=", l)), None)
    if window is None or start is None:
        sys.exit("FAIL: the TS patch builds no `flux` query or has no kUeMetricsWindow")
    expr = ""
    for l in added[start:]:
        expr += l
        if l.rstrip().endswith(";"):
            break
    expr = expr.split("=", 1)[1].rstrip().rstrip(";")
    names = {"influx.bucket": BUCKET, "kUeMetricsWindow": window, "tag": tag}
    out = ""
    for tok in re.findall(r'"(?:[^"\\]|\\.)*"|[A-Za-z_][\w.]*|\+|\S', expr):
        if tok == "+":
            continue
        if tok.startswith('"'):
            out += re.sub(r'\\(.)', r'\1', tok[1:-1])
        elif tok in names:
            out += names[tok]
        else:
            sys.exit(f"FAIL: the TS query uses {tok!r}, which this test does not know; extend it deliberately")
    return out


def http(method, url, body=None, headers=None):
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def time_records(csv_text):
    rows, col = 0, None
    for line in csv_text.splitlines():
        cells = line.rstrip("\r").split(",")
        if not line.strip() or line.startswith("#"):
            col = None
            continue
        if col is None:
            col = cells.index("_time") if "_time" in cells else -1
            continue
        if col >= 0 and col < len(cells) and cells[col]:
            rows += 1
    return rows


def main():
    body_out = sys.argv[sys.argv.index("--http400-body") + 1] if "--http400-body" in sys.argv else None
    podman = shutil.which("podman") or ""
    if not podman:
        skip("no podman")
    if subprocess.run([podman, "image", "exists", IMAGE]).returncode:
        skip(f"no local {IMAGE} image (nothing is pulled here)")
    new_q_present = query_from_patch(patch_text(pinned_testbed_sha()), PRESENT)
    new_q_absent = query_from_patch(patch_text(pinned_testbed_sha()), ABSENT)
    old_q = query_from_patch(patch_text(PREFIX_TESTBED_SHA), PRESENT)
    lp = (HERE / "fixtures/ts-influx-mixed/ue-metrics.lp").read_text().splitlines()
    env = [f"DOCKER_INFLUXDB_INIT_{k}={v}" for k, v in [("MODE", "setup"), ("USERNAME", "selftest"),
           ("PASSWORD", "selftest-password"), ("ORG", ORG), ("BUCKET", BUCKET), ("ADMIN_TOKEN", TOKEN)]]
    cid = subprocess.run([podman, "run", "-d", "--rm", "-p", "127.0.0.1::8086"] + sum((["-e", e] for e in env), []) +
                         [IMAGE], capture_output=True, text=True, check=True).stdout.strip()
    fail = []
    try:
        port = subprocess.run([podman, "port", cid, "8086"], capture_output=True, text=True,
                              check=True).stdout.split(":")[-1].strip()
        base = f"http://127.0.0.1:{port}"
        for _ in range(60):
            try:
                if http("GET", base + "/health")[0] == 200 and http(
                        "GET", base + "/api/v2/buckets?name=" + BUCKET, headers={"Authorization": "Token " + TOKEN})[0] == 200:
                    break
            except (urllib.error.URLError, ConnectionError, OSError):
                pass
            time.sleep(1)
        now = time.time_ns()
        data = "\n".join(f"{l} {now - (i + 1) * 1_000_000_000}" for i, l in enumerate(lp)).encode()
        st, txt = http("POST", f"{base}/api/v2/write?org={ORG}&bucket={BUCKET}&precision=ns", data,
                       {"Authorization": "Token " + TOKEN, "Content-Type": "text/plain"})
        if st != 204:
            sys.exit(f"FAIL: writing the fixture answered {st}: {txt[:200]}")
        hq = {"Authorization": "Token " + TOKEN, "Content-Type": "application/vnd.flux", "Accept": "application/csv"}
        st, txt = http("POST", f"{base}/api/v2/query?org={ORG}", new_q_present.encode(), hq)
        n = time_records(txt)
        print(f"pinned query, present tag: HTTP {st}, {n} _time record(s)")
        if st != 200 or n < 1:
            fail.append(f"the pinned query found no point for {PRESENT}: HTTP {st} {txt[:200]}")
        st, txt = http("POST", f"{base}/api/v2/query?org={ORG}", new_q_absent.encode(), hq)
        n = time_records(txt)
        print(f"pinned query, absent tag: HTTP {st}, {n} _time record(s)")
        if st != 200 or n != 0:
            fail.append(f"the pinned query found a point for {ABSENT}, which has none: HTTP {st} {txt[:200]}")
        st, txt = http("POST", f"{base}/api/v2/query?org={ORG}", old_q.encode(), hq)
        print(f"pre-fix query, present tag: HTTP {st}: {txt.strip()[:160]}")
        if st != 400 or "schema collision" not in txt:
            fail.append(f"the pre-fix query did not answer HTTP 400 schema collision (HTTP {st}): the fixture may "
                        "no longer hold both field types")
        elif body_out:
            pathlib.Path(body_out).write_text(txt)
    finally:
        subprocess.run([podman, "rm", "-f", cid], capture_output=True)
    for f in fail:
        print("FAIL:", f)
    print("ts-influx-query self-test:", "FAIL" if fail else "ok")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Receiver-side route record of M7's replacement e2term (informational; ledger row 162).

After M7 deletes the e2term pod, rtmgr must push a route table to the replacement pod. In one M7 run of
21 it never did (P10 D-R3-1 chain attempt 1): the pod ran on its seed router.txt, so every E2 Setup
Request (12001) failed with RMR_ERR_NOENDPT. rtmgr's own push log is no proof either way, so this record
reads the receiver:
  stashPresent       /opt/e2/router.txt.stash exists (RMR writes it on every table it receives)
  e2term4561Est      ESTABLISHED sockets on the e2term's :4561 (rtmgr's route-push session)
  rtmgrToE2termSvc   ESTABLISHED rtmgr sockets to the e2term Service IP on :4561
  noEndpt12001       e2term log lines "RMR_ERR_NOENDPT ... sending request 12001"
matches = not stashPresent and e2term4561Est == 0 and noEndpt12001 > 0 (the no-route-table signature).

It never judges: M7's verdict comes from its checks. Under the user ruling of 2026-11-07 (option ii), an
M7 red whose record matches gets one re-run from the step's start state, outside the guided-fix budget;
two matching reds in a row are a PAUSE.

Usage: m7-e2term-route-record.py --ls LS --e2term-tcp TCP --rtmgr-tcp TCP --svc-ip IP --e2term-log LOG
       m7-e2term-route-record.py --self-test
"""
import argparse
import json
import re
import sys

PORT_4561 = "11D1"
NOENDPT_12001 = re.compile(r"RMR_ERR_NOENDPT.*sending request 12001\b")


def ip_hex_le(ip):
    """IPv4 as /proc/net/tcp prints it: the 32-bit word in host (little-endian) byte order."""
    return "".join("%02X" % int(b) for b in reversed(ip.split(".")))


def est_sockets(tcp_text):
    """(local, remote) address strings of every ESTABLISHED socket in /proc/net/tcp{,6} text."""
    out = []
    for line in tcp_text.splitlines():
        f = line.split()
        if len(f) > 3 and re.fullmatch(r"\d+:", f[0]) and f[3] == "01":
            out.append((f[1].upper(), f[2].upper()))
    return out


def record(ls_text, e2term_tcp, rtmgr_tcp, svc_ip, e2term_log):
    names = {line.split()[-1] for line in ls_text.splitlines() if line.split()}
    svc = ip_hex_le(svc_ip)
    r = {
        "stashPresent": "router.txt.stash" in names,
        "e2term4561Est": sum(1 for loc, _ in est_sockets(e2term_tcp) if loc.endswith(":" + PORT_4561)),
        "rtmgrToE2termSvc": sum(1 for _, rem in est_sockets(rtmgr_tcp) if rem.endswith(svc + ":" + PORT_4561)),
        "noEndpt12001": sum(1 for line in e2term_log.splitlines() if NOENDPT_12001.search(line)),
    }
    r["matches"] = (not r["stashPresent"]) and r["e2term4561Est"] == 0 and r["noEndpt12001"] > 0
    return r


def self_test():
    svc = "10.101.123.229"
    hdr = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"
    listen = "   0: 00000000:11D1 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 1 1\n"
    e2t_est = "   1: A100F40A:11D1 9E00F40A:ECF4 01 00000000:00000000 00:00000000 00000000 0 0 2 1\n"
    rtm_other = "   8: 9E00F40A:ECF4 E44F6F0A:11D1 01 00000000:00000000 02:00000031 00000000 0 0 3 2\n"
    rtm_svc = "   9: 9E00F40A:E6B0 %s:11D1 01 00000000:00000000 02:00000018 00000000 0 0 4 2\n" % ip_hex_le(svc)
    rtm_svc6 = "   2: 0000000000000000FFFF00009E00F40A:E6B1 0000000000000000FFFF0000%s:11D1 01 0:0 0:0 0 0 0 5 1\n" % ip_hex_le(svc)
    noendpt = ('{"msg":"RMR failed: RMR_ERR_NOENDPT - send//call could not find an endpoint based on msg type. '
               'sending request 12001 to Xapp from en_gnb_001_001_00000002"}\n')
    keepalive = '{"msg":"Failed to send E2_TERM_KEEP_ALIVE_RESP, on RMR state = 2 ( RMR_ERR_NOENDPT - ...)"}\n'
    ls_seed = "-rw-r--r-- 1 root root 1892 router.txt\n-rw-r----- 1 root root 0 router.txt.stash.inc\n"
    ls_ok = ls_seed + "-rw-r----- 1 root root 2816 router.txt.stash\n"
    cases = [
        # the 2026-11-05 signature: seed table only, no :4561 session, setups unroutable
        ("signature", (ls_seed, hdr + listen, hdr + rtm_other, svc, noendpt * 3 + keepalive),
         {"stashPresent": False, "e2term4561Est": 0, "rtmgrToE2termSvc": 0, "noEndpt12001": 3, "matches": True}),
        # a green recovery: table received, session up, the early NOENDPT lines do not make it match
        ("green", (ls_ok, hdr + listen + e2t_est, hdr + rtm_other + rtm_svc, svc, noendpt),
         {"stashPresent": True, "e2term4561Est": 1, "rtmgrToE2termSvc": 1, "noEndpt12001": 1, "matches": False}),
        ("tcp6-session-counted", (ls_ok, hdr + e2t_est, hdr + rtm_svc6, svc, ""),
         {"stashPresent": True, "e2term4561Est": 1, "rtmgrToE2termSvc": 1, "noEndpt12001": 0, "matches": False}),
        # no stash and no session but no unroutable setup: a different failure, not this signature
        ("no-setup-lost", (ls_seed, hdr + listen, hdr, svc, keepalive),
         {"stashPresent": False, "e2term4561Est": 0, "rtmgrToE2termSvc": 0, "noEndpt12001": 0, "matches": False}),
        ("stash-inc-is-not-a-stash", (ls_seed, hdr, hdr, svc, noendpt),
         {"stashPresent": False, "e2term4561Est": 0, "rtmgrToE2termSvc": 0, "noEndpt12001": 1, "matches": True}),
    ]
    bad = 0
    for name, args, want in cases:
        got = record(*args)
        if got != want:
            bad += 1
            print("self-test FAIL %s: got %s want %s" % (name, got, want))
    print("self-test %s (%d cases)" % ("FAIL" if bad else "ok", len(cases)))
    return 1 if bad else 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    p = argparse.ArgumentParser()
    for a in ("--ls", "--e2term-tcp", "--rtmgr-tcp", "--e2term-log"):
        p.add_argument(a, required=True)
    p.add_argument("--svc-ip", required=True)
    a = p.parse_args()

    def read(path):
        try:
            return open(path, errors="replace").read()
        except OSError:
            return ""
    r = record(read(a.ls), read(a.e2term_tcp), read(a.rtmgr_tcp), a.svc_ip, read(a.e2term_log))
    print(json.dumps(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())

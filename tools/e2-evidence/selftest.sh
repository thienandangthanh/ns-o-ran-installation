#!/usr/bin/env bash
# selftest.sh [dev-p5-smoke-dir]: host-side unit tests for the e2-evidence tools (gates M5-M7).
#
# 1. synthetic fact sheets / sample dirs / poll logs: every query must pass on good input and fail on a
#    deliberately broken one;
# 2. optional replay (needs tshark): with a smoke directory holding agent.pcap, trace.ndjson, influx-cell.csv,
#    influx-ue.csv, e2-ipc-trace-2.jsonl and e2-ue-context-2.jsonl (a dev smoke run of one agent, node 2; the last two
#    are the UE context map the Influx ueId tags resolve through), the pcap facts and the Influx-vs-trace comparison must
#    reproduce "setup func 2 / en-gNB 2 (32-bit gNB ID) / indications / all fields equal". A smoke recorded before the
#    agents registered as en-gNBs (a Global gNB ID) fails the setup identity, as it should.
# Needs python3 only for part 1. Exit 0 = all passed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
map="${MAP:-$here/../../O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/schema/metric-map.v1.json}"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
fails=0
expect() { # <rc-wanted> <name> <cmd...>
    local want="$1" name="$2" rc; shift 2
    "$@" >"$t/out" 2>&1; rc=$?
    if [ "$rc" -eq "$want" ]; then echo "ok   $name"; else echo "FAIL $name (rc $rc, want $want)"; tail -n 3 "$t/out"; fails=$((fails + 1)); fi
}
py() { python3 -I "$@"; }

python3 -I - "$t" <<'PY'
import json, os, sys
t = sys.argv[1]
svc = "10.96.0.5"
ev = lambda f, ts, s, d, sp, dp, **k: dict(frame=f, t=ts, src=s, dst=d, sport=sp, dport=dp, **k)
json.dump({"1": ["172.17.0.2"], "2": ["172.17.0.3"]}, open(t + "/ips.json", "w"))
good = {"inits": [ev(1, 100, "172.17.0.2", svc, 40001, 36422), ev(2, 100.1, "172.17.0.3", svc, 40002, 36422),
                  ev(3, 210, "172.17.0.2", svc, 40011, 36422), ev(4, 211, "172.17.0.3", svc, 40012, 36422)],
        "aborts": [ev(9, 205, svc, "172.17.0.2", 36422, 40001)], "shutdowns": [], "pdus": [],
        "setup_requests": [ev(6, 210.1, "172.17.0.2", svc, 40011, 36422, ran_function_ids=[2], oids=["1.3.6.1.4.1.53148.1.3.2.2"],
                              short_names=["ORAN-E2SM-KPM"], e2node_type="eNB", node_id=1, node_id_bits=20, plmn="00f110",
                              descriptions=[]),
                           ev(7, 211.1, "172.17.0.3", svc, 40012, 36422, ran_function_ids=[2])],
        "setup_responses": [ev(8, 212, svc, "172.17.0.2", 36422, 40011, accepted=[2]), ev(10, 213, svc, "172.17.0.3", 36422, 40012, accepted=[2])],
        "sub_requests": [ev(11, 214, svc, "172.17.0.2", 36422, 40011, requestor=123, instance=9, ran_function_id=2),
                         ev(12, 215, svc, "172.17.0.3", 36422, 40012, requestor=123, instance=10, ran_function_id=2)],
        "sub_responses": [ev(13, 214.1, "172.17.0.2", svc, 40011, 36422, requestor=123, instance=9, ran_function_id=2),
                          ev(14, 215.1, "172.17.0.3", svc, 40012, 36422, requestor=123, instance=10, ran_function_id=2)],
        "ind_times_by_src": {"172.17.0.2": [150, 214.5, 220], "172.17.0.3": [150, 216, 221]}}
def handshake(good, f, ts, ip, sport):    # INIT_ACK + COOKIE_ACK from the Service to (ip, sport)
    good["init_acks"].append(ev(f, ts + 0.05, svc, ip, 36422, sport))
    good["cookie_acks"].append(ev(f + 1, ts + 0.1, svc, ip, 36422, sport))
good["init_acks"], good["cookie_acks"] = [], []
for f, ts, ip, sp in ((101, 100, "172.17.0.2", 40001), (102, 100.1, "172.17.0.3", 40002),
                      (103, 210, "172.17.0.2", 40011), (104, 211, "172.17.0.3", 40012)):
    handshake(good, f, ts, ip, sp)
# setup requests of the first associations name node 1 (the eNB) / 2 (an en-gNB) (the later ones above already do or
# are filled below)
good["setup_requests"] = [ev(5, 100.2, "172.17.0.2", svc, 40001, 36422, node_id=1, ran_function_ids=[2]),
                          ev(6, 210.1, "172.17.0.2", svc, 40011, 36422, ran_function_ids=[2], oids=["1.3.6.1.4.1.53148.1.3.2.2"],
                             short_names=["ORAN-E2SM-KPM"], e2node_type="eNB", node_id=1, node_id_bits=20, plmn="00f110",
                             descriptions=[]),
                          ev(7, 211.1, "172.17.0.3", svc, 40012, 36422, ran_function_ids=[2], node_id=2),
                          ev(8, 100.3, "172.17.0.3", svc, 40002, 36422, node_id=2, ran_function_ids=[2])]
good["ind_events"] = [ev(20 + i, ts, ip, svc, sp, 36422) for i, (ts, ip, sp) in enumerate(
    ((150, "172.17.0.2", 40001), (214.5, "172.17.0.2", 40011), (220, "172.17.0.2", 40011),
     (150, "172.17.0.3", 40002), (216, "172.17.0.3", 40012), (221, "172.17.0.3", 40012)))]
json.dump(good, open(t + "/good.json", "w"))
# subscription period and failure: P = G = 100 answered; P = 150 answered by RIC SUBSCRIPTION FAILURE ricRequest:17
sub = json.loads(json.dumps(good))
for r in sub["sub_requests"]:
    r.update(reporting_period_ms=100, granul_periods_ms=[100])
json.dump(sub, open(t + "/sub-ok.json", "w"))
sub["sub_requests"][1]["granul_periods_ms"] = [100, 200]
json.dump(sub, open(t + "/sub-granul.json", "w"))
fail = json.loads(json.dumps(good))
for r in fail["sub_requests"]:
    r.update(reporting_period_ms=150, granul_periods_ms=[100])
fail["sub_failures"] = [dict(r, frame=r["frame"] + 100, cause="ricRequest:17", cause_label="ricRequest:eventTriggerNotSupported")
                        for r in fail["sub_responses"]]
fail["sub_responses"] = []
json.dump(fail, open(t + "/sub-fail.json", "w"))
fail["sub_failures"][0]["cause"] = "ricRequest:1"
json.dump(fail, open(t + "/sub-fail-cause.json", "w"))
# (a) IP swap after the restart: node 1 comes back as 172.17.0.3, node 2 as 172.17.0.2; node-ips.json holds the union
# (b) unanswered INIT retries (nobody listens) from both IPs before the new associations form
swap = json.loads(json.dumps(good))
swap["inits"] = [i for i in swap["inits"] if i["t"] < 200]
for ts, ip in ((206, "172.17.0.2"), (211, "172.17.0.2"), (206.5, "172.17.0.3")):
    swap["inits"].append(ev(30, ts, ip, svc, 41000 if ip.endswith("2") else 41001, 36422))
swap["inits"] += [ev(31, 212, "172.17.0.3", svc, 40021, 36422), ev(32, 212.1, "172.17.0.2", svc, 40022, 36422)]
swap["init_acks"] = [a for a in swap["init_acks"] if a["t"] < 200]
swap["cookie_acks"] = [a for a in swap["cookie_acks"] if a["t"] < 200]
handshake(swap, 105, 212, "172.17.0.3", 40021); handshake(swap, 107, 212.1, "172.17.0.2", 40022)
swap["setup_requests"] = [r for r in swap["setup_requests"] if r["t"] < 200] + [
    ev(40, 212.3, "172.17.0.3", svc, 40021, 36422, node_id=1, ran_function_ids=[2]),
    ev(41, 212.4, "172.17.0.2", svc, 40022, 36422, node_id=2, ran_function_ids=[2])]
swap["setup_responses"] = [ev(42, 213, svc, "172.17.0.3", 36422, 40021, accepted=[2]), ev(43, 213.1, svc, "172.17.0.2", 36422, 40022, accepted=[2])]
swap["sub_requests"] = [ev(44, 214, svc, "172.17.0.3", 36422, 40021, requestor=1, instance=1, ran_function_id=2),
                        ev(45, 214, svc, "172.17.0.2", 36422, 40022, requestor=1, instance=2, ran_function_id=2)]
swap["sub_responses"] = [ev(46, 214.1, "172.17.0.3", svc, 40021, 36422, requestor=1, instance=1, ran_function_id=2),
                         ev(47, 214.1, "172.17.0.2", svc, 40022, 36422, requestor=1, instance=2, ran_function_id=2)]
swap["ind_events"] = [x for x in swap["ind_events"] if x["t"] < 200] + [
    ev(50, 215, "172.17.0.3", svc, 40021, 36422)] + [ev(51 + i, 216 + i, "172.17.0.2", svc, 40022, 36422) for i in range(3)]
json.dump(swap, open(t + "/swap.json", "w"))
json.dump({"1": ["172.17.0.2", "172.17.0.3"], "2": ["172.17.0.2", "172.17.0.3"]}, open(t + "/ips-union.json", "w"))
bad = json.loads(json.dumps(good))
bad["inits"][3]["sport"] = 40002          # reconnect from the old source port
bad["init_acks"][3]["dport"] = 40002; bad["cookie_acks"][3]["dport"] = 40002
bad["setup_requests"][2]["sport"] = 40002; bad["sub_responses"][1]["dport"] = 36422
bad["sub_requests"] = bad["sub_requests"][:1]
json.dump(bad, open(t + "/bad.json", "w"))
# endurance samples
for n in range(3):
    d = "%s/end/sample-%02d" % (t, n)
    os.makedirs(d)
    open(d + "/t", "w").write(str(1000 + 60 * n))
    open(d + "/pods.txt", "w").write("a-1 0\nb-2 1\n")
    open(d + "/agents.txt", "w").write("1 0 true READY 1 5\n2 0 true READY 1 5\n")
    open(d + "/rss.txt", "w").write("ns3-e2-agent-1 %d.5MiB / 15GiB\n" % (20 + n))
    open(d + "/e2mgr.txt", "w").write("enB_macro_001_001_000001\nen_gnb_001_001_00000002\n")
    open(d + "/ns3.alive", "w").write("1\n")
    open(d + "/load.txt", "w").write("1.50 1.20 0.9 1/300 123\n")
    open(d + "/kpimon.txt", "w").write("kpimon-x true 1 0\n")
# ns-3 IPC traces: node 2 reconnects (2 hellos) and drops 2 samples; node 3 has a seq gap
def trace(path, hellos, built, sent, dd, gap=False):
    with open(path, "w") as fh:
        for _ in range(hellos):
            fh.write(json.dumps({"type": "hello", "nodeId": 2, "kind": "gnb", "periodNs": 100000000}) + "\n")
        for q in range(built):
            fh.write(json.dumps({"type": "sample", "seq": q + (1 if gap and q > 2 else 0), "ues": []}) + "\n")
        fh.write(json.dumps({"type": "bye", "built": built, "sent": sent, "droppedDisconnected": dd, "droppedBackpressure": 0, "lastSeq": built - 1}) + "\n")
trace(t + "/trace-ok.jsonl", 2, 10, 8, 2)
trace(t + "/trace-gap.jsonl", 2, 10, 8, 2, gap=True)
trace(t + "/trace-sum.jsonl", 2, 10, 9, 2)
open(t + "/names.txt", "w").write("enB_macro_001_001_000001\nen_gnb_001_001_00000002\n")
# the meid form before the en-gNB identity: recovery-eval must refuse it
open(t + "/names-old-form.txt", "w").write("enB_macro_001_001_000001\ngnb_001_001_00000002\n")
open(t + "/polls.tsv", "w").write(
    "1010.5\t\t1:1:true:HOLDOFF:0:0 2:1:true:HOLDOFF:0:0\n"
    "1030.5\tenB_macro_001_001_000001,en_gnb_001_001_00000002\t1:1:true:READY:1:7 2:1:true:READY:1:0\n"
    "1035.5\tenB_macro_001_001_000001,en_gnb_001_001_00000002\t1:1:true:READY:1:17 2:1:true:READY:1:3\n")
open(t + "/nodes.csv", "w").write("#datatype,string,long,dateTime:RFC3339,long\n,result,table,_time,_value\n"
                                  ",,0,2026-10-21T16:46:56.2Z,2\n,,0,2026-10-21T16:47:56Z,2\n,,1,2026-10-21T16:47:57Z,3\n")
PY

q="$here/e2-facts-query.py"
svc=10.96.0.5
expect 0 "facts: assoc-start good" py "$q" "$t/good.json" assoc-start --node-ips "$t/ips.json" --service-ip $svc --before 200
expect 1 "facts: assoc-start wrong service ip" py "$q" "$t/good.json" assoc-start --node-ips "$t/ips.json" --service-ip 1.2.3.4 --before 200
expect 0 "facts: no-abort window without the ABORT" py "$q" "$t/good.json" no-abort --from 100 --to 200
expect 1 "facts: no-abort window with the ABORT" py "$q" "$t/good.json" no-abort --from 100 --to 206
expect 0 "facts: post-delete good" py "$q" "$t/good.json" post-delete --node-ips "$t/ips.json" --service-ip $svc --after 205
expect 1 "facts: post-delete old port / missing subscription" py "$q" "$t/bad.json" post-delete --node-ips "$t/ips.json" --service-ip $svc --after 205
expect 0 "facts: indications for every node" py "$q" "$t/good.json" indications --node-ips "$t/ips.json"
expect 0 "facts: subscription request answered" py "$q" "$t/good.json" subscription --func-id 2
expect 0 "facts: setup-response accepts 2" py "$q" "$t/good.json" setup-response --func-id 2
expect 0 "facts: sub-period 100/100 answered" py "$q" "$t/sub-ok.json" sub-period --period-ms 100 --granul-ms 100
expect 1 "facts: sub-period wrong period" py "$q" "$t/sub-ok.json" sub-period --period-ms 1000 --granul-ms 100
expect 1 "facts: sub-period one action at another granularity" py "$q" "$t/sub-granul.json" sub-period --period-ms 100 --granul-ms 100
expect 1 "facts: sub-period without the KPM fields (old fact sheet)" py "$q" "$t/good.json" sub-period --period-ms 100
expect 0 "facts: sub-failure with the registered cause" py "$q" "$t/sub-fail.json" sub-failure --cause ricRequest:17
expect 1 "facts: sub-failure with another cause" py "$q" "$t/sub-fail-cause.json" sub-failure --cause ricRequest:17
expect 1 "facts: sub-failure when the requests were answered by responses" py "$q" "$t/sub-ok.json" sub-failure --cause ricRequest:17
expect 0 "facts: tshark subscription text -> period, granularities, cause index" py - "$here/e2ap-pcap-facts.py" <<'PYT'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("facts", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
req = m.parse_subscription(["ricRequestorID: 1001", "ricInstanceID: 3", "ranFunctionID: 2", "E2SM-KPM-EventTriggerDefinition",
                            "    reportingPeriod: 1000", "    granulPeriod: 100", "    granulPeriod: 100"])
fail = m.parse_subscription(["ricRequestorID: 1001", "ricInstanceID: 4", "ranFunctionID: 2", "Cause: ricRequest (0)",
                             "    ricRequest: eventTriggerNotSupported (17)"])
old = m.parse_subscription(["Cause: ricRequest (0)", "    ricRequest: Unknown (17)"])
print(req, fail, old)
sys.exit(0 if req["reporting_period_ms"] == 1000 and req["granul_periods_ms"] == [100, 100] and req["cause"] is None
         and fail["cause"] == "ricRequest:17" and fail["cause_label"] == "ricRequest:eventTriggerNotSupported"
         and old["cause"] == "ricRequest:17" else 1)
PYT
expect 0 "facts: service-ip" py "$q" "$t/good.json" service-ip --node-ips "$t/ips.json" --service-ip $svc
# (a) IP swap after restart: attribution follows the association, node-ips.json (union, both nodes on both IPs) is no help
expect 0 "facts: assoc-start before the restart, unanswered INIT retries ignored" py "$q" "$t/swap.json" assoc-start --node-ips "$t/ips-union.json" --service-ip $svc --before 200
expect 1 "facts: assoc-start counts a second established association per node" py "$q" "$t/swap.json" assoc-start --node-ips "$t/ips-union.json" --service-ip $svc --before 300
expect 0 "facts: post-delete after an IP swap" py "$q" "$t/swap.json" post-delete --node-ips "$t/ips-union.json" --service-ip $svc --after 205 --timeline-out "$t/swap-tl.json"
expect 0 "facts: IP swap attributes node 1 to 172.17.0.3:40021 and node 2 to 172.17.0.2:40022" py -c '
import json, sys
t = json.load(open(sys.argv[1]))
print({n: v["new_associations"] for n, v in t.items()})
sys.exit(0 if t["1"]["new_associations"] == ["172.17.0.3:40021"] and t["2"]["new_associations"] == ["172.17.0.2:40022"]
         and t["1"]["old_sports"] == [40001] and t["2"]["indications_post_delete"] == 3 else 1)' "$t/swap-tl.json"
expect 0 "facts: indications per node after an IP swap" py "$q" "$t/swap.json" indications --node-ips "$t/ips-union.json"
# (b) unanswered INIT retries belong to no association, are reported per IP and never counted as INITs of a node
expect 0 "facts: unanswered INIT retries are reported, not counted" bash -c "python3 -I '$q' '$t/swap.json' associations | grep -q 'INIT(s) from 172.17.0.2 never answered' && python3 -I '$q' '$t/swap.json' associations | grep -q '2 INIT(s) from 172.17.0.2'"
expect 1 "facts: a node whose only association has no E2SetupRequest has no association" py "$q" "$t/swap.json" assoc-start --nodes 1,2,3 --service-ip $svc --before 200
expect 0 "facts: service-ip with unanswered retries" py "$q" "$t/swap.json" service-ip --node-ips "$t/ips-union.json" --service-ip $svc
expect 0 "trace: reconnects and drops accepted, counters balance" py "$here/trace-facts.py" "$t/trace-ok.jsonl" --reconnects-ok --expect-nodes 2
expect 1 "trace: --require-clean still rejects reconnects" py "$here/trace-facts.py" "$t/trace-ok.jsonl" --require-clean --expect-nodes 2
expect 1 "trace: seq gap rejected" py "$here/trace-facts.py" "$t/trace-gap.jsonl" --reconnects-ok --expect-nodes 2
expect 1 "trace: built != sent + drops rejected" py "$here/trace-facts.py" "$t/trace-sum.jsonl" --reconnects-ok --expect-nodes 2
# --pdcp-stats on an ns3run dir: LCID-3 rows with nTxPDUs > 0 need TxBytes = nTxPDUs * (1308 + 2), or <= that on a row
# with a switch of its IMSI in [start - d, end + d); an SRB (LCID 1) row and a zero-PDU row are not judged
pdcp_row() { printf '%s\t%s\t1\t%s\t3\t%s\t%s\t%s\t168\t220080\t0.004\t0.0008\t0.003\t0.005\t1310\t0\t1310\t1310\t\n' "$@"; }
# pdcp_run <name> <extra rows...>: an ns3run dir whose stats hold three equal rows, the not-judged rows and the extra rows
pdcp_run() {
    local d="$t/pdcp-$1" r; shift; mkdir -p "$d"
    { printf '%% start\tend\tCellId\tIMSI\tRNTI\tLCID\tnTxPDUs\tTxBytes\tnRxPDUs\tRxBytes\tdelay\tstdDev\tmin\tmax\tPduSize\tstdDev\tmin\tmax\n'
      pdcp_row 0.1 0.2 1 3 178 233180; pdcp_row 0.2 0.3 2 3 2 2620; pdcp_row 0.9 1 3 3 198 259380
      pdcp_row 0.1 0.2 2 1 3 99; pdcp_row 0.1 0.2 4 3 0 0
      for r in "$@"; do read -r -a f <<<"$r"; pdcp_row "${f[@]}"; done; } >"$d/DlE2PdcpStats.txt"
}
short="1 1.1 3 3 253 331390"   # IMSI 3, epoch [1, 1.1): 253 PDUs, 40 octets short of 253 * 1310
pdcp_case() { # <want> <name> <switch lines for MmWaveSwitchStats.txt, '' = no file> <rows...>
    local want="$1" name="$2" sw="$3" dir; shift 3
    dir="pdcp-$(printf %s "$name" | tr -c 'a-z0-9' '-')"
    pdcp_run "${dir#pdcp-}" "$@"
    [ -z "$sw" ] || printf '%b' "$sw" >"$t/$dir/MmWaveSwitchStats.txt"
    expect "$want" "pdcp stats: $name" py "$here/trace-facts.py" --pdcp-stats "$t/$dir"
}
pdcp_case 0 "absent switch files, every row equal" ''
pdcp_case 0 "a short row, its switch in the same epoch" 'SwitchToMmWave 1.05 3 2 87 \n' "$short"
pdcp_case 0 "a short row, its switch in the previous epoch" 'SwitchToMmWave 0.95 3 2 87 \n' "$short"
pdcp_case 0 "a short row, its switch in the next epoch" 'SwitchToMmWave 1.15 3 2 87 \n' "$short"
pdcp_case 1 "1308 + 3 on a non-switch row" '' "0.3 0.4 1 3 10 13110"
pdcp_case 1 "1308 + 3 on a switch row with nTxPDUs > deficit" 'SwitchToMmWave 1.05 3 2 87 \n' "1 1.1 3 3 253 331643"
pdcp_case 1 "a short non-switch row" '' "$short"
pdcp_case 1 "a short row, its only switch two epochs away" 'SwitchToMmWave 1.25 3 2 87 \n' "$short"
pdcp_case 1 "a short row, the switch of another IMSI" 'SwitchToMmWave 1.05 5 2 87 \n' "$short"
pdcp_case 1 "a malformed switch line" 'SwitchToMmWave 1.05 3 2 87 \nSwitchToMmWave 1.07 3 2\n' "$short"
pdcp_case 1 "a switch line of the other kind" 'SwitchToLte 1.05 3 1 6 \n' "$short"
# the LTE file is read too: a SwitchToLte in the previous epoch covers the short row
pdcp_run lte "$short"; printf 'SwitchToLte 0.95 3 1 6 \n' >"$t/pdcp-lte/LteSwitchStats.txt"
expect 0 "pdcp stats: a short row, a SwitchToLte in the previous epoch" py "$here/trace-facts.py" --pdcp-stats "$t/pdcp-lte"
# no non-switch row: every judged row has a switch of its IMSI within one epoch
mkdir -p "$t/pdcp-allswitch"; { head -n 1 "$t/pdcp-lte/DlE2PdcpStats.txt"; pdcp_row 1 1.1 3 3 253 331390; } >"$t/pdcp-allswitch/DlE2PdcpStats.txt"
printf 'SwitchToMmWave 1.05 3 2 87 \n' >"$t/pdcp-allswitch/MmWaveSwitchStats.txt"
expect 1 "pdcp stats: no non-switch row" py "$here/trace-facts.py" --pdcp-stats "$t/pdcp-allswitch"
mkdir -p "$t/pdcp-nohdr"; tail -n +2 "$t/pdcp-lte/DlE2PdcpStats.txt" >"$t/pdcp-nohdr/DlE2PdcpStats.txt"
expect 1 "pdcp stats: rows without the column header fail" py "$here/trace-facts.py" --pdcp-stats "$t/pdcp-nohdr"
expect 1 "pdcp stats: a dir without DlE2PdcpStats.txt fails" py "$here/trace-facts.py" --pdcp-stats "$t/pdcp-missing"
# the fact counts switch and equality rows, overall and per IMSI (the 0.95 switch covers both IMSI-3 rows)
expect 0 "pdcp stats: the fact counts rows per IMSI" bash -c "python3 -I '$here/trace-facts.py' --pdcp-stats '$t/pdcp-lte' --out '$t/pdcp-fact.json' >/dev/null &&
    python3 -I -c 'import json,sys; f=json.load(open(sys.argv[1])); sys.exit(0 if (f[\"switchRows\"], f[\"equalityRows\"], f[\"perImsi\"][\"3\"]) == (2, 2, {\"switchRows\": 2, \"equalityRows\": 0}) else 1)' '$t/pdcp-fact.json'"
e="$here/endurance-eval.py"
for c in pods agents e2mgr ns3 kpimon rss load; do
    expect 0 "endurance: $c good" py "$e" "$t/end" --check "$c" --expected-names "$t/names.txt"
done
echo "a-1 2" >"$t/end/sample-02/pods.txt"; echo "1 1 true READY 1 0" >"$t/end/sample-02/agents.txt"; echo 0 >"$t/end/sample-02/ns3.alive"
for c in pods agents ns3; do expect 1 "endurance: $c broken" py "$e" "$t/end" --check "$c"; done
expect 0 "recovery: restart, reconnect, indications resume" py "$here/recovery-eval.py" "$t/polls.tsv" --after 1005 --expected-names "$t/names.txt"
expect 1 "recovery: delete after the last poll" py "$here/recovery-eval.py" "$t/polls.tsv" --after 1100 --expected-names "$t/names.txt"
expect 1 "recovery: an expected name in the old gnb_ form is refused" py "$here/recovery-eval.py" "$t/polls.tsv" --after 1005 \
    --expected-names "$t/names-old-form.txt"

# setup identity (e2ap-pcap-facts.py parse of tshark -V text): fixtures/setup-identity/ac6a-setup-requests.txt holds the
# E2 Setup Requests of a scripted en-gNB (frame 6, gNB ID 0x7F000001) and macro eNB (frame 17, ID 0xFFFFE) as tshark
# 4.4.19 prints them; each also names the other node in its X2 component, which must not count.
python3 -I - "$t" "$here" <<'PY'
import importlib.util, json, sys
t, here = sys.argv[1:]
spec = importlib.util.spec_from_file_location("facts", here + "/e2ap-pcap-facts.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
text = open(here + "/fixtures/setup-identity/ac6a-setup-requests.txt").read()
for num, lines in m.blocks(text):
    r = dict(frame=num, t=0, src="172.17.0.2", dst="10.96.0.5", sport=40001, dport=36422, **m.parse_setup_request(lines))
    json.dump({"setup_requests": [r]}, open("%s/setup-frame-%d.json" % (t, num), "w"))
PY
sr() { py "$q" "$t/setup-frame-$1.json" setup-request --func-id 2 --oid 1.3.6.1.4.1.53148.1.3.2.2 --short-name ORAN-E2SM-KPM \
    --plmn 00f110 "${@:2}"; }
expect 0 "setup identity: en-gNB, 32-bit gNB ID 0x7F000001, PLMN 00f110" sr 6 --node-type en-gNB --node-id 2130706433 --node-id-bits 32 \
    --not-node-id-hex B5C67788
expect 0 "setup identity: eNB, 20-bit macro eNB ID 0xFFFFE (its X2 component's en-gNB ID ignored)" sr 17 --node-type eNB \
    --node-id 1048574 --node-id-bits 20
expect 1 "setup identity: wrong CHOICE" sr 6 --node-type gNB --node-id 2130706433 --node-id-bits 32
expect 1 "setup identity: wrong bit length" sr 6 --node-type en-gNB --node-id 2130706433 --node-id-bits 22
expect 1 "setup identity: the eNB is not the X2 neighbour's en-gNB" sr 17 --node-type en-gNB --node-id 2130706433 --node-id-bits 32
expect 1 "setup identity: the reference node's ID (and >> 3) is refused" sr 6 --node-type en-gNB --node-id 2130706433 \
    --node-id-bits 32 --not-node-id-hex 7F000001
expect 0 "influx-node-rows: both nodes have rows after the delete" py "$here/influx-node-rows.py" "$t/nodes.csv" --after 1792601200 --nodes 2,3
expect 1 "influx-node-rows: node 4 has none" py "$here/influx-node-rows.py" "$t/nodes.csv" --after 1792601200 --nodes 2,4

# ppid (e2ap-pcap-facts.py --ppid facts): node 2 on 172.17.0.3:40002 and node 3 on 172.17.0.4:40003.
python3 -I - "$t" <<'PY'
import copy, json, sys
t = sys.argv[1]
svc = "10.96.0.5"
ev = lambda f, ts, s, d, sp, dp, **k: dict(frame=f, t=ts, src=s, dst=d, sport=sp, dport=dp, **k)
f = {"inits": [], "init_acks": [], "cookie_acks": [], "setup_requests": [], "setup_responses": [], "sub_requests": [],
     "sub_responses": [], "ind_events": [], "ppid": {"sctp_port": 36422, "to_port_by_assoc": {},
                                                     "e2ap_frames": {"by_ppid": 40, "forced_port": 40}}}
for n, (ip, port) in {2: ("172.17.0.3", 40002), 3: ("172.17.0.4", 40003)}.items():
    f["inits"].append(ev(n, 100, ip, svc, port, 36422))
    f["init_acks"].append(ev(10 + n, 100.1, svc, ip, 36422, port))
    f["cookie_acks"].append(ev(20 + n, 100.2, svc, ip, 36422, port))
    f["setup_requests"].append(ev(30 + n, 100.3, ip, svc, port, 36422, node_id=n))
    f["ppid"]["to_port_by_assoc"]["%s:%d" % (ip, port)] = {"src": ip, "sport": port, "counts": {"70": 20},
                                                           "t_first": 100.3, "t_last": 110}
json.dump(f, open(t + "/ppid-good.json", "w"))
b = copy.deepcopy(f); b["ppid"]["to_port_by_assoc"]["172.17.0.4:40003"]["counts"] = {"70": 19, "0": 1}
json.dump(b, open(t + "/ppid-wrong.json", "w"))
b = copy.deepcopy(f); b["ppid"]["e2ap_frames"]["by_ppid"] = 39
json.dump(b, open(t + "/ppid-count.json", "w"))
b = copy.deepcopy(f); del b["ppid"]["to_port_by_assoc"]["172.17.0.4:40003"]
json.dump(b, open(t + "/ppid-missing.json", "w"))
PY
expect 0 "ppid: every node PPID 70, decode counts equal" py "$q" "$t/ppid-good.json" ppid --nodes 2,3
expect 0 "ppid: source IP sent PPID 70" py "$q" "$t/ppid-good.json" ppid --source-ip 172.17.0.3
expect 1 "ppid: one chunk with PPID 0" py "$q" "$t/ppid-wrong.json" ppid --nodes 2,3
expect 1 "ppid: decode by PPID != forced on the port" py "$q" "$t/ppid-count.json" ppid --nodes 2,3
expect 1 "ppid: node 3 sent no PPID-70 chunk" py "$q" "$t/ppid-missing.json" ppid --nodes 2,3
expect 1 "ppid: absent source IP" py "$q" "$t/ppid-good.json" ppid --source-ip 172.17.0.9

# influx-vs-trace.py: the UE identity conjunct (every UeMetrics row's ueId resolves to its ns3.imsi) in both modes
python3 -I - "$t" <<'PY'
import json, os, sys
t = sys.argv[1] + "/ivt"
os.makedirs(t)
rows = [{"kind": "gnb", "list": lst, "order": o, "kpm": k, "type": "INTEGER", "scope": sc, "src": src, "xform": "none"}
        for lst, o, k, sc, src in (("cell", 1, "ns3.nodeId", "sample", "/nodeId"), ("cell", 2, "ns3.seq", "sample", "/seq"),
                                   ("ue", 1, "ns3.nodeId", "sample", "/nodeId"), ("ue", 2, "ns3.seq", "sample", "/seq"),
                                   ("ue", 3, "ns3.imsi", "ue", "/imsi"))]
json.dump({"rows": rows}, open(t + "/map.json", "w"))
with open(t + "/e2-ipc-trace-2.jsonl", "w") as f:
    f.write(json.dumps({"type": "hello", "nodeId": 2, "kind": "gnb"}) + "\n")
    for s in range(3):
        f.write(json.dumps({"type": "sample", "nodeId": 2, "seq": s, "ues": [{"imsi": 1}, {"imsi": 2}]}) + "\n")
with open(t + "/e2-ue-context-2.jsonl", "w") as f:
    f.write(json.dumps({"type": "ueContext", "v": 1, "nodeId": 2, "seq": 0, "ues": [
        {"imsi": i, "lteRnti": 2 + i, "mnCellId": 1, "mmeUeS1apId": i} for i in (1, 2)]}) + "\n")
def csv(path, cols, data):
    with open(path, "w") as f:
        f.write(",result,table," + ",".join(["_measurement"] + cols) + "\n")
        for r in data:
            f.write(",,0," + ",".join(["m"] + ["" if v is None else str(v) for v in r]) + "\n")
csv(t + "/cell.csv", ["ns3.nodeId", "ns3.seq"], [(2, s) for s in range(3)])
tag = lambda i: "enGnbUeId:%d@00F110-00001" % (2 + i)
ue = [(2, s, i, tag(i)) for s in range(3) for i in (1, 2)]
csv(t + "/ue-good.csv", ["ns3.nodeId", "ns3.seq", "ns3.imsi", "ueId"], ue)
csv(t + "/ue-nocol.csv", ["ns3.nodeId", "ns3.seq", "ns3.imsi"], [r[:3] for r in ue])
csv(t + "/ue-other.csv", ["ns3.nodeId", "ns3.seq", "ns3.imsi", "ueId"], ue[:-1] + [(2, 2, 2, tag(1))])
csv(t + "/ue-missing.csv", ["ns3.nodeId", "ns3.seq", "ns3.imsi", "ueId"], ue[:-1] + [(2, 2, 2, None)])
csv(t + "/ue-noimsi.csv", ["ns3.nodeId", "ns3.seq", "ns3.imsi", "ueId"], ue + [(2, 2, None, tag(1))])
csv(t + "/ue-lower.csv", ["ns3.nodeId", "ns3.seq", "ns3.imsi", "ueId"], ue[:-1] + [(2, 2, 2, tag(2).lower())])
PY
iv="$t/ivt"
ivt() { py "$here/influx-vs-trace.py" --map "$iv/map.json" --trace "$iv/e2-ipc-trace-2.jsonl" --influx-cell "$iv/cell.csv" \
    --influx-ue "$iv/$1.csv" --ue-context-dir "$iv" --out "$iv/$1.json" "${@:2}"; }
expect 0 "influx-vs-trace: every ueId resolves to its row's IMSI" ivt ue-good
expect 0 "influx-vs-trace --every-seq: every ueId resolves to its row's IMSI" ivt ue-good --every-seq
expect 1 "influx-vs-trace: a UE CSV without a ueId column" ivt ue-nocol
expect 1 "influx-vs-trace: a ueId that names another IMSI" ivt ue-other
expect 1 "influx-vs-trace --every-seq: a ueId that names another IMSI" ivt ue-other --every-seq
expect 1 "influx-vs-trace: a UE row without ueId" ivt ue-missing
expect 1 "influx-vs-trace: a UE row the old key skipped (no ns3.imsi)" ivt ue-noimsi
expect 1 "influx-vs-trace: a malformed (lowercase) ueId" ivt ue-lower
mv "$iv/e2-ue-context-2.jsonl" "$iv/ctx.bak"
expect 1 "influx-vs-trace: no UE context file" ivt ue-good
mv "$iv/ctx.bak" "$iv/e2-ue-context-2.jsonl"

smoke="${1:-}"
if [ -n "$smoke" ] && [ -f "$smoke/agent.pcap" ] && command -v tshark >/dev/null; then
    py "$here/e2ap-pcap-facts.py" "$smoke/agent.pcap" -o "$t/real.json" >"$t/facts.out" 2>&1 || cat "$t/facts.out"
    echo '{"2":["172.17.0.2"]}' >"$t/ips-real.json"
    expect 0 "real pcap: setup request func 2, OID, short name, en-gNB 2 (32 bits), plmn 00f110, not B5C67788" py "$q" \
        "$t/real.json" setup-request --func-id 2 --oid 1.3.6.1.4.1.53148.1.3.2.2 --short-name ORAN-E2SM-KPM \
        --node-type en-gNB --node-id 2 --node-id-bits 32 --plmn 00f110 --not-node-id-hex B5C67788
    expect 0 "real pcap: setup response accepts 2" py "$q" "$t/real.json" setup-response --func-id 2
    expect 0 "real pcap: subscription request/response" py "$q" "$t/real.json" subscription --func-id 2
    expect 0 "real pcap: one association, indications on the wire" py "$q" "$t/real.json" assoc-start --node-ips "$t/ips-real.json" --service-ip 10.106.169.160 --before 9999999999
    expect 0 "real trace: bye sent == built, no drops" py "$here/trace-facts.py" "$smoke/trace.ndjson" --require-clean --expect-nodes 2
    expect 0 "real Influx rows == trace: 3 picks bit-exact" py "$here/influx-vs-trace.py" --map "$map" --trace "$smoke/trace.ndjson" \
        --influx-cell "$smoke/influx-cell.csv" --influx-ue "$smoke/influx-ue.csv" --ue-context-dir "$smoke" --out "$t/vs.json"
    expect 0 "real Influx rows == trace: all fields equal" py -c '
import json, sys
a = json.load(open(sys.argv[1]))["all"]
print(a)
sys.exit(0 if a["all_fields_differ"] == 0 and a["all_fields_compared"] > 0 and a["all_samples_complete"] == a["trace_samples"] else 1)' "$t/vs.json"
fi
[ "$fails" -eq 0 ] && echo "selftest: ok"
exit "$fails"

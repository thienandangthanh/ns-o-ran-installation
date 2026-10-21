#!/usr/bin/env bash
# selftest.sh [dev-p5-smoke-dir]: host-side unit tests for the e2-evidence tools (gates M5-M7).
#
# 1. synthetic fact sheets / sample dirs / poll logs: every query must pass on good input and fail on a
#    deliberately broken one;
# 2. optional replay (needs tshark): with a smoke directory holding agent.pcap, trace.ndjson, influx-cell.csv,
#    influx-ue.csv (plans/.../evidence/dev-p5/smoke/<ts>), the pcap facts and the Influx-vs-trace comparison must
#    reproduce "setup func 2 / gNB-ID 2 / 99 indications / all fields equal".
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
                              short_names=["ORAN-E2SM-KPM"], gnb_id=1, plmn="00f110", descriptions=[]),
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
# setup requests of the first associations name gNB-ID 1 / 2 (the later ones above already do or are filled below)
good["setup_requests"] = [ev(5, 100.2, "172.17.0.2", svc, 40001, 36422, gnb_id=1, ran_function_ids=[2]),
                          ev(6, 210.1, "172.17.0.2", svc, 40011, 36422, ran_function_ids=[2], oids=["1.3.6.1.4.1.53148.1.3.2.2"],
                             short_names=["ORAN-E2SM-KPM"], gnb_id=1, plmn="00f110", descriptions=[]),
                          ev(7, 211.1, "172.17.0.3", svc, 40012, 36422, ran_function_ids=[2], gnb_id=2),
                          ev(8, 100.3, "172.17.0.3", svc, 40002, 36422, gnb_id=2, ran_function_ids=[2])]
good["ind_events"] = [ev(20 + i, ts, ip, svc, sp, 36422) for i, (ts, ip, sp) in enumerate(
    ((150, "172.17.0.2", 40001), (214.5, "172.17.0.2", 40011), (220, "172.17.0.2", 40011),
     (150, "172.17.0.3", 40002), (216, "172.17.0.3", 40012), (221, "172.17.0.3", 40012)))]
json.dump(good, open(t + "/good.json", "w"))
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
    ev(40, 212.3, "172.17.0.3", svc, 40021, 36422, gnb_id=1, ran_function_ids=[2]),
    ev(41, 212.4, "172.17.0.2", svc, 40022, 36422, gnb_id=2, ran_function_ids=[2])]
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
    open(d + "/e2mgr.txt", "w").write("gnb_001_001_00000001\ngnb_001_001_00000002\n")
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
open(t + "/names.txt", "w").write("gnb_001_001_00000001\ngnb_001_001_00000002\n")
open(t + "/polls.tsv", "w").write(
    "1010.5\t\t1:1:true:HOLDOFF:0:0 2:1:true:HOLDOFF:0:0\n"
    "1030.5\tgnb_001_001_00000001,gnb_001_001_00000002\t1:1:true:READY:1:7 2:1:true:READY:1:0\n"
    "1035.5\tgnb_001_001_00000001,gnb_001_001_00000002\t1:1:true:READY:1:17 2:1:true:READY:1:3\n")
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
e="$here/endurance-eval.py"
for c in pods agents e2mgr ns3 kpimon rss load; do
    expect 0 "endurance: $c good" py "$e" "$t/end" --check "$c" --expected-names "$t/names.txt"
done
echo "a-1 2" >"$t/end/sample-02/pods.txt"; echo "1 1 true READY 1 0" >"$t/end/sample-02/agents.txt"; echo 0 >"$t/end/sample-02/ns3.alive"
for c in pods agents ns3; do expect 1 "endurance: $c broken" py "$e" "$t/end" --check "$c"; done
expect 0 "recovery: restart, reconnect, indications resume" py "$here/recovery-eval.py" "$t/polls.tsv" --after 1005 --expected-names "$t/names.txt"
expect 1 "recovery: delete after the last poll" py "$here/recovery-eval.py" "$t/polls.tsv" --after 1100 --expected-names "$t/names.txt"
expect 0 "influx-node-rows: both nodes have rows after the delete" py "$here/influx-node-rows.py" "$t/nodes.csv" --after 1792601200 --nodes 2,3
expect 1 "influx-node-rows: node 4 has none" py "$here/influx-node-rows.py" "$t/nodes.csv" --after 1792601200 --nodes 2,4

smoke="${1:-}"
if [ -n "$smoke" ] && [ -f "$smoke/agent.pcap" ] && command -v tshark >/dev/null; then
    py "$here/e2ap-pcap-facts.py" "$smoke/agent.pcap" -o "$t/real.json" >"$t/facts.out" 2>&1 || cat "$t/facts.out"
    echo '{"2":["172.17.0.2"]}' >"$t/ips-real.json"
    expect 0 "real pcap: setup request func 2, OID, short name, gNB-ID 2, plmn 00f110, not B5C67788" py "$q" "$t/real.json" setup-request \
        --func-id 2 --oid 1.3.6.1.4.1.53148.1.3.2.2 --short-name ORAN-E2SM-KPM --gnb-id 2 --plmn 00f110 --not-gnb-id-hex B5C67788
    expect 0 "real pcap: setup response accepts 2" py "$q" "$t/real.json" setup-response --func-id 2
    expect 0 "real pcap: subscription request/response" py "$q" "$t/real.json" subscription --func-id 2
    expect 0 "real pcap: one association, indications on the wire" py "$q" "$t/real.json" assoc-start --node-ips "$t/ips-real.json" --service-ip 10.106.169.160 --before 9999999999
    expect 0 "real trace: bye sent == built, no drops" py "$here/trace-facts.py" "$smoke/trace.ndjson" --require-clean --expect-nodes 2
    expect 0 "real Influx rows == trace: 3 picks bit-exact" py "$here/influx-vs-trace.py" --map "$map" --trace "$smoke/trace.ndjson" \
        --influx-cell "$smoke/influx-cell.csv" --influx-ue "$smoke/influx-ue.csv" --out "$t/vs.json"
    expect 0 "real Influx rows == trace: all fields equal" py -c '
import json, sys
a = json.load(open(sys.argv[1]))["all"]
print(a)
sys.exit(0 if a["all_fields_differ"] == 0 and a["all_fields_compared"] > 0 and a["all_samples_complete"] == a["trace_samples"] else 1)' "$t/vs.json"
fi
[ "$fails" -eq 0 ] && echo "selftest: ok"
exit "$fails"

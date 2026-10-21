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
json.dump(good, open(t + "/good.json", "w"))
bad = json.loads(json.dumps(good))
bad["inits"][3]["sport"] = 40002          # reconnect from the old source port
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

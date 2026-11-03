#!/usr/bin/env bash
# run.sh <kpimon-image> <agent-image>: kpimon's eNB measurement path against the eNB agent's real RAN Function
# Description. The agent image's codec-probe writes the eNB description (ranfunc-enb, from the metric map's eNB rows);
# zz_enb_probe_test.go runs inside the kpimon image (go toolchain and modules from its build) with no network and
# requires: the Format 3 action definition from enb-kpm-measurements.json == the one kpimon builds from that
# description (encode_action_Definition, determine 3), the same cell and UE name lists (buildRanCellUeKpi), and
# isEnbNode true for an eNB nodeb record, false for an en-gNB one. Exit 0 = all hold.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
kpimon="${1:?kpimon image}" agent="${2:?agent image}"
eng=docker; command -v docker >/dev/null || eng=podman
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -r "$here/fixtures" "$here/zz_enb_probe.go" "$here/zz_enb_probe_test.go" "$tmp/"
$eng run --rm --network none --entrypoint sh "$agent" -c \
    'mkdir /tmp/cp && codec-probe /etc/ns3-e2-agent/metric-map.v1.json /tmp/cp >/dev/null 2>&1; cat /tmp/cp/ranfunc.txt' |
    awk '$1 == "ranfunc-enb" {print $2}' >"$tmp/enb-ranfunc2.hex"
[ -s "$tmp/enb-ranfunc2.hex" ] || { echo "no ranfunc-enb from $agent's codec-probe"; exit 1; }
chmod -R a+rX "$tmp"
$eng run --rm --network none -v "$tmp:/probe:ro" --entrypoint sh "$kpimon" -c \
    'cp /probe/zz_enb_probe.go /probe/zz_enb_probe_test.go /opt/control/ && cd /opt &&
     GOFLAGS=-mod=mod go test ./control -run TestEnbProbe -v -count=1 2>&1' >"$tmp/out.txt"
rc=$?
grep -E '^(CONFIG_FORMAT3|FROMDEF_FORMAT3|EQUAL|NAMES_EQUAL|UE_NAMES|IS_ENB|ok|FAIL|--- )' "$tmp/out.txt" | cut -c1-160
[ "$rc" = 0 ] && grep -q '^--- PASS: TestEnbProbe' "$tmp/out.txt" && echo "kpimon-enb-probe: ok" && exit 0
echo "kpimon-enb-probe: FAIL"; tail -n 20 "$tmp/out.txt"; exit 1

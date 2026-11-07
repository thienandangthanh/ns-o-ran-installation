#!/usr/bin/env bash
# per-case-mc.sh <tag>: runs the mc-pdcp-nr-header suite once per case in $NS3_TREE. ns-3 stops a
# suite at its first failing case, so a probe copy of the suite registers only the case whose
# index is MC_CASE (assertions unchanged); the suite file is restored after.
set -uo pipefail
S=/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/910ba118-28cd-4264-b831-5fa1b4929edd/scratchpad
N="$NS3_TREE"
tag="$1"
T="$N/src/lte/test/lte-test-mc-pdcp-nr-header.cc"
cp "$T" "$S/mc-suite-orig.cc"
python3 - "$T" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
head, ctor = s.split('class McPdcpNrHeaderTestSuite', 1)
n = ctor.count('AddTestCase(')
ctor = ctor.replace('AddTestCase(', 'AddSelected(')
ctor = ctor.replace('''  public:
    McPdcpNrHeaderTestSuite()''', '''  public:
    // Probe only: register just the case whose index is MC_CASE.
    int m_index = 0;
    void AddSelected(TestCase* c, TestCase::TestDuration d)
    {
        const char* want = std::getenv("MC_CASE");
        if (want && std::atoi(want) == m_index) { AddTestCase(c, d); } else { delete c; }
        m_index++;
    }
    McPdcpNrHeaderTestSuite()''', 1)
s = head.replace('#include <algorithm>', '#include <algorithm>\n#include <cstdlib>', 1) + 'class McPdcpNrHeaderTestSuite' + ctor
open(p, 'w').write(s)
open(p + '.ncases', 'w').write(str(n))
PY
n=$(cat "$T.ncases"); rm -f "$T.ncases"; n="${MC_NCASES:-$n}"
bash "$S/run-ns3.sh" compile "probe-$tag" >/dev/null
out="$S/per-case-$tag.txt"
: >"$out"
for i in $(seq 0 $((n - 1))); do
    MC_CASE=$i bash "$S/run-ns3.sh" runner "probe-$tag-$i" mc-pdcp-nr-header >/dev/null
    { echo "== case index $i"; grep -v "^PASS mc-pdcp-nr-header\|^FAIL mc-pdcp-nr-header" "$S/runner-probe-$tag-$i.txt"; } >>"$out"
done
cp "$S/mc-suite-orig.cc" "$T"
bash "$S/run-ns3.sh" compile "restore-$tag" >/dev/null
echo "cases: $n"
awk '/^== case/{i=$4} /^  (PASS|FAIL) /{r=$0; sub(/ [0-9.]+ s$/,"",r); sub(/^  /,"",r)} /^runner rc=/{print i": "r" ("$0")"; r="(no case line)"}' "$out"

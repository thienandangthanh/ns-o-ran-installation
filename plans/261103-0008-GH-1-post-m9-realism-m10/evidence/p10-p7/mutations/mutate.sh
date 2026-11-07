#!/usr/bin/env bash
# mutate.sh <tag> <file-rel> <python-replace-old> <python-replace-new>: apply one mutation to the
# build tree's copy of a production file, rebuild the test-runner, run suite cases 31-40 one per
# process, restore the file and rebuild. Never touches the worktree.
set -uo pipefail
S=/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/910ba118-28cd-4264-b831-5fa1b4929edd/scratchpad
N=/tmp/claude-1000/ns3-p7-fix-910ba118/ns-3
W=/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/ns-3-mmwave-oran
tag="$1"; f="$2"; old="$3"; new="$4"; old2="${5:-}"; new2="${6:-}"
python3 - "$N/$f" "$old" "$new" "$old2" "$new2" <<'PY' || exit 2
import sys
p, old, new, old2, new2 = sys.argv[1:]
s = open(p).read()
assert s.count(old) >= 1, "mutation anchor not found"
s = s.replace(old, new)
if old2:
    assert s.count(old2) >= 1, "second mutation anchor not found"
    s = s.replace(old2, new2)
open(p, 'w').write(s)
PY
out="$S/mutation-$tag.txt"
{ echo "# mutation $tag in $f"; echo "# - $old"; echo "# + $new"; diff <(cat "$W/$f") "$N/$f"; } >"$out"
export NS3_TREE="$N"
bash "$S/run-ns3.sh" compile "mut-$tag" >/dev/null
if grep -q "^rc=0" "$S/compile-mut-$tag.log"; then
  T="$N/src/lte/test/lte-test-mc-pdcp-nr-header.cc"
  cp "$T" "$S/mc-suite-orig.cc"
  python3 - "$T" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
head, ctor = s.split('class McPdcpNrHeaderTestSuite', 1)
ctor = ctor.replace('AddTestCase(', 'AddSelected(').replace('''  public:
    McPdcpNrHeaderTestSuite()''', '''  public:
    int m_index = 0;
    void AddSelected(TestCase* c, TestCase::TestDuration d)
    {
        const char* want = std::getenv("MC_CASE");
        if (want && std::atoi(want) == m_index) { AddTestCase(c, d); } else { delete c; }
        m_index++;
    }
    McPdcpNrHeaderTestSuite()''', 1)
open(p, 'w').write(head.replace('#include <algorithm>', '#include <algorithm>\n#include <cstdlib>', 1) + 'class McPdcpNrHeaderTestSuite' + ctor)
PY
  bash "$S/run-ns3.sh" compile "mutp-$tag" >/dev/null
  for i in $(seq 31 40); do
    MC_CASE=$i bash "$S/run-ns3.sh" runner "mut-$tag-$i" mc-pdcp-nr-header >/dev/null
    r=$(grep -E "^  (PASS|FAIL) " "$S/runner-mut-$tag-$i.txt" | sed -E 's/ [0-9.]+ s$//; s/^  //')
    first=$(grep 'test="' "$S/runner-mut-$tag-$i.txt" | head -1 | sed -E 's#^ +##; s# in="[^"]*/(lte-test-mc-pdcp-nr-header.cc:[0-9]+)"# \1#')
    nf=$(grep -c 'test="' "$S/runner-mut-$tag-$i.txt")
    echo "$i $r | failing checks $nf | first: $first" >>"$out"
  done
  cp "$S/mc-suite-orig.cc" "$T"
else
  echo "BUILD FAILED:" >>"$out"; grep -E " error|undefined reference" "$S/compile-mut-$tag.log" | head -5 | sed -E 's#/tmp/claude-1000/ns3-p7-fix-910ba118/ns-3/##g' >>"$out"
fi
cp "$W/$f" "$N/$f"
bash "$S/run-ns3.sh" compile "unmut-$tag" >/dev/null
cmp -s "$W/$f" "$N/$f" && echo "restored $f" >>"$out"
grep -E "^[0-9]+ |BUILD|error|undefined|restored" "$out" | cut -c1-220

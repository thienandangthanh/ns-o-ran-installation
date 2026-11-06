#!/usr/bin/env bash
# VM probe of the fixed M4 test tree (kongming-261107-0305): outside the gate, own scratch dir.
set -u
P=~/ub-preflight
cd "$P" || exit 9
sha256sum h/scripts/*
echo "df before: $(df -BG --output=avail / | tail -1)"
start=$(date +%s)
timeout 3600 bash h/scripts/build-ns3.sh "$P/tree" --tests >tree.stdout 2>tree.stderr
rc=$?
echo "test-tree rc $rc in $(( $(date +%s) - start )) s"
grep -m1 "configure:" tree.stderr
tail -n 3 tree.stderr
SRC=$(tail -n 1 tree.stdout)
echo "src $SRC head $(git -C "$SRC" rev-parse HEAD 2>/dev/null)"
if [ "$rc" -eq 0 ]; then
    (cd "$SRC" && timeout 600 ./test.py -n -v -s mmwave-neighbour-list) >suite.txt 2>&1
    echo "suite rc $?"
    sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' suite.txt >suite.plain
    grep -E "^\[[0-9]+/[0-9]+\] (PASS|FAIL|CRASH|SKIP|VALGR):" suite.plain
    if grep -Eq "^\[[0-9]+/[0-9]+\] PASS: TestSuite mmwave-neighbour-list\$" suite.plain &&
        ! grep -Eq "^\[[0-9]+/[0-9]+\] (FAIL|CRASH|VALGR|SKIP):" suite.plain; then
        echo "PROBE PREDICATE: PASS"
    else
        echo "PROBE PREDICATE: FAIL"
    fi
fi
echo "df after: $(df -BG --output=avail / | tail -1)"

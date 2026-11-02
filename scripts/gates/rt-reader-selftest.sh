#!/usr/bin/env bash
# rt-reader-selftest.sh: host-side check of rc's RMR readiness on fixtures (scripts/gates/fixtures/rt-reader/).
# The shipped functions (bringup.sh, rc-lib.sh) run against a stubbed kubectl: an rtmgr push log that says OK
# beside a stuck route-table reader must fail rc_rmr_ready_after_rtmgr, and the drained reader must pass it.
# Exit 0 when both hold.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fx="$here/fixtures/rt-reader"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export EVIDENCE_DIR="$tmp"
# shellcheck source=bringup.sh
source "$here/bringup.sh"
# shellcheck source=rc-lib.sh
source "$here/rc-lib.sh"
export RT_READER_WAIT_S=5 RT_READER_SAMPLES=2 RC_RMR_READY_TIMEOUT_S=5 RTMGR_PUSH_ACK_TIMEOUT_S=5
log() { :; }
pod_info() { echo "ricxapp-rc-6db9dcd964-zf8dr 0 2026-11-03T00:00:00Z"; }
TCP_FIXTURE=""
kc() {
    local ns="$2"; shift 2
    case "$1" in
        get) if [ "$ns" = ricplt ]; then echo "deployment-ricplt-rtmgr-74fb47b69d-5drjj 1/1 Running 0 1d"
             else echo "ricxapp-rc-6db9dcd964-zf8dr 1/1 Running 0 1d"; fi ;;
        logs) if [ "$ns" = ricplt ]; then cat "$fx/rtmgr-log-ok.txt"; else cat "$fx/rc-log.txt"; fi ;;
        exec) cat "$TCP_FIXTURE" "$fx/proc-net-tcp6-empty.txt" ;;
        *) return 1 ;;
    esac
}
rc=0
for case in stuck healthy; do
    TCP_FIXTURE="$fx/proc-net-tcp-$case.txt"
    rtmgr_push_acked service-ricxapp-rc-rmr >/dev/null || { echo "FAIL fixture: the rtmgr push log must read OK"; rc=1; }
    rc_rmr_ready_after_rtmgr >"$tmp/$case.out" 2>&1; got=$?
    want=0; [ "$case" = stuck ] && want=1
    if { [ "$want" = 0 ] && [ "$got" = 0 ]; } || { [ "$want" = 1 ] && [ "$got" != 0 ]; }; then
        echo "ok   rc readiness with a $case reader and an OK push log: exit $got ($(tail -n 1 "$tmp/$case.out"))"
    else echo "FAIL rc readiness with a $case reader: exit $got"; cat "$tmp/$case.out"; rc=1; fi
done
echo "rt-reader self-test: $([ "$rc" = 0 ] && echo ok || echo failed)"
exit "$rc"

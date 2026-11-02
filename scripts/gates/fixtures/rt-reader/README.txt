Fixtures for scripts/gates/rt-reader-selftest.sh (receiver-side RMR readiness).
rc-log.txt            rc's "RMR is ready after" start-up line
rtmgr-log-ok.txt      rtmgr's "Update Routes to Endpoint ... successful ... OK" push line for rc
proc-net-tcp-stuck    rc's /proc/net/tcp with rtmgr's session on :4561 holding 0x1EC5A (~126 KB) unread,
                      the shape seen in e2mgr and submgr after the 2026-10-28 cold boot (M9 attempt 3)
proc-net-tcp-healthy  the same session drained (rx_queue 0), as measured in rc on 2026-11-03
proc-net-tcp6-empty   header only
A push log that says OK beside a stuck reader must fail readiness; the healthy reader must pass.

# Findings: stuck RMR route-table readers after a cold boot (FU4)

Date: 2026-11-03 02:47 KST. Scope: AC5 of the M10 contract, a findings note only. The F″ remedy (`rt_reader_ok` plus `ric_refresh_routes` in `scripts/gates/bringup.sh`) is unchanged. Fixing the root cause is out of scope (contract §3).

## Symptom (recorded in M9)
- An RMR endpoint's route-table socket (local port 4561, the session rtmgr opens to push tables) stays ESTABLISHED, but its receive queue never drains. rtmgr still logs "Update Routes to Endpoint … successful … OK", so the push log alone cannot detect it.
- M9 attempt 3 (`evidence/m9/20261028T134954Z`, prefix p): after a cold boot before m6, both e2mgr and submgr stopped reading (about 126 KB unread). e2mgr had no route for the E2 Setup Response, so m6 went red. That incident led to fix F″.
- M9 attempt 4 (`evidence/m1/20261028T170205Z/rt-readers-ric-171502.txt`): right after the RIC install, e2mgr pod `…-p6lbf` held `rx_queue` 74,730 bytes, constant over 5 samples 2 s apart, from peer `0A00F40A` (10.244.0.10). One `ric refresh (ric)` replaced e2mgr and submgr and restarted rtmgr. Afterwards both readers were OK with `rx_queue` 0, and the new rtmgr peer was 10.244.0.22 (`rt-readers-refresh-ric-171510.txt`). Every other M9 gate read OK (run report, P-row m1).

## Reproduction attempt, 2026-11-03
- **Setup:** the VM booted cold from the post-M9 disk state (current snapshot `fresh-install`, active overlay from M9 attempt 4, the whole RIC including rc, TS xApp and stubqp installed). There was no install and no refresh, and the harness's shipped `rt_reader_ok` was run 3 minutes after boot. Evidence is in `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/fu3-fu4/20261102T174642Z/`.
- **Result: no reproduction.** e2mgr, submgr and rc each had one session on :4561 with `rx_queue` 0 in all 5 samples (`rt-readers-coldboot-live.txt`).
- **Side observations** (`checks/fu4-observations.out`):
  - e2mgr's previous container exited 20 s after start with `dial tcp: i/o timeout` and `#app.main - Failed setting GENERAL key` (dbaas not reachable yet). That makes 11 restarts over its life. It came back once dbaas was up.
  - rtmgr pushed to e2mgr, submgr, a1mediator, e2term, hw-go, kpimon and rc after boot, but not to `trafficxapp` (the TS xApp) or `stubqp`. Neither has a :4561 session, consistent with "rtmgr only opens a connection to an endpoint it learns from appmgr's xApp list". The TS rungs restart rtmgr after their own installs (`ts-rung-lib.sh`), so the gates are not affected today. A gate that relies on a kept TS xApp pod after a cold boot would need that restart too.

## Hypotheses (unverified; ranked by fit to the evidence)
1. **Push arrives before the reader thread runs.** The constant, non-zero `rx_queue` means the reader is not reading at all; a slow reader would show a moving value. One candidate is RMR's route-table collector thread being blocked or not started when rtmgr connects. Two things fit this: both incidents followed a moment when many pods started together (cold boot, fresh install), and e2mgr crash-loops early on dbaas timeouts. In this reading, the session is accepted by the kernel's listen backlog before the user-space reader exists.
2. **A session from a replaced rtmgr instance.** In the m1 incident, the stuck peer IP (10.244.0.10) differs from the rtmgr peer after the refresh (10.244.0.22). If an earlier rtmgr container pushed and then died, the endpoint may hold a half-open session that its reader no longer polls. Against this: a cold boot restarts every container, so the old session should have been reset.
3. **e2mgr restarts during rtmgr's first push round.** When e2mgr restarts after rtmgr has connected, rtmgr "never reconnects to a replaced pod" (`scripts/gates/rc-lib.sh` header). A new container that inherits nothing could end with a session in a bad state. This does not explain submgr, which did not restart in the p incident.

## What would isolate the trigger (not done; out of scope)
- Cold-boot loops (N ≥ 10) with `rt_reader_ok` sampling every 10 s from boot. For each boot, record the container start times of rtmgr, e2mgr, submgr and dbaas, and the first rtmgr push time per endpoint.
- In a stuck pod, a thread dump of the RMR collector (for example `gdb -p` or `/proc/<pid>/task/*/wchan`) to see where the reader blocks.
- If the trigger is isolated, an upstream bug report to OSC `ric-plt/lib/rmr` or `ric-plt/rtmgr` (upstream PRs are out of scope for M10).

## Unchanged remedy and the FU3 change that uses it
- `rt_reader_ok` (receiver-side evidence) plus a bounded `ric_refresh_routes`, at most once per level per gate run.
- FU3 (this goal) extends receiver-side readiness to rc: `rc_rmr_ready_after_rtmgr` now needs rc's own :4561 reader drained. rtmgr's push log is supporting evidence only (`scripts/gates/rc-lib.sh`, `scripts/gates/rt-reader-selftest.sh`).

## Unresolved questions
- Whether the TS xApp's missing rtmgr session after a cold boot matters for any M10 step. Today every TS rung restarts rtmgr first; P12 re-checks this when it builds the M10 step set.

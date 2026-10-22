# Kongming counsel: rc never becomes RMR-ready after its pod is recreated (P3, smoke q8 run 2)

- **When and where.** 2026-10-23 ~08:30 KST. Harness worktree HEAD `acff82f`. The VM was inspected read-only between 23:17Z and 23:30Z (kubectl get/logs/exec `cat /proc/...`, plus one HTTP GET to appmgr). Nothing was deleted, restarted or installed.
- **Sources.** Cloned into the scratchpad: rtmgr `0.9.6`, RMR `4.9.4`, xapp-frame `v0.8.3` (which rc builds with) and `v0.9.16` (which rtmgr uses). The local rc checkout is at `a2282ee`.
- **Runtime.** Opus 5.5, as the caller routed it.
- **Advisory only.** This is not user approval.

## TL;DR

**Root cause.**
- rtmgr pushes routes to each xApp through one RMR wormhole per endpoint name, opened once.
- When the pod behind that wormhole is replaced, the TCP session dies silently. rtmgr's RMR never re-dials it, so every later push to that xApp fails with EPIPE.
- rc has no seed route table, so it never becomes RMR-ready. That means `ReadyCB` never runs, `gControlData` stays nil, and rc panics on the first control.
- kpimon and hw-go only *look* healthy because they start from static seed tables. rtmgr cannot reach their new pods either.

**It was not the reset change alone.**
- Run 2's `rc_install` already ran the NIST script, which always does `dms_cli uninstall rc` before installing. That killed run 1's rc pod and its session.
- Run 1 worked only because that rtmgr process had never had an rc session before.

**Fix.** The per-run reset becomes:
1. a fresh bucket;
2. replace the rc, kpimon and hw-go pods;
3. after they are Ready, restart rtmgr (delete its pod);
4. gate on rc's `rmrClient: RMR is ready after` line plus evidence from rtmgr's side.

Never reinstall rc per run.

**Confirm it first:** delete only the rtmgr pod. The currently stuck rc should log `RMR is ready` within about a minute.

**Triggers.**
- No T3 or T4 if this design holds.
- This is an L-release defect. A strict reading makes it T5.
- My default is to report and not pause, if an rtmgr restart verifiably cures it. Print `PAUSE T5` if it does not.
- Raise it at Stop A in either case.

## 1. Root cause

### Certain (verified live or in source)

| # | Fact | Evidence |
|---|---|---|
| F1 | rc cannot become RMR-ready without a push from rtmgr. kpimon and hw-go can. | Pod env: rc has `RMR_RTG_SVC=4561` and **no `RMR_SEED_RT`**. kpimon has `RMR_SEED_RT=/opt/routes.txt` (2 routes: 20011→a1mediator, 12010→e2term). hw-go has `RMR_SEED_RT=config/uta_rtg.rt`. |
| F2 | rc's control path needs RMR to be ready. | xapp-frame v0.8.3 `rmr.go:196-214` loops on `rmr_ready()`, logs `Waiting for RMR…` every 10 s, and launches the ready callback only when ready. rc sets `gControlData` only in `ReadyCB` (`rcControl.go:50-52`). `GetSequenceNumber` dereferences it at `rcControl.go:149`. The gRPC server starts earlier, in `NewControl` (`rcControl.go:37`), so `describe` succeeds on an rc that is not ready. |
| F3 | k8s Ready says nothing about RMR. | xapp-frame v0.8.3 `restapi.go:216-219`: the readiness handler sets `healthReady=true` and returns 200 unconditionally. |
| F4 | rtmgr opens a push wormhole only when an endpoint first enters its map. | `sbi.go:85-115` calls `AddEndpoint` only for a new uuid. `nngpush.go:89-105` calls `Openwh(<svc>:4561)`. There is no reopen on failure. `send_data` (`nngpush.go:181-210`) uses a 200 ms `SendCallMsg` and retries ≤3× on the same whid. |
| F5 | RMR never marks a wormhole closed when a send fails. | `uta_ep_failed` (`rtable_si_static.c:54`) has **zero callers** in 4.9.4. `send_msg` only sets `RMR_ERR_SENDFAILED` (`sr_si_static.c:654`). `SIsendt` returns `SI_ERROR` without `SIterm`. The only path that closes an endpoint is the receive loop: `siwait.c:116-126` → `mt_disc_cb` (`mt_call_si_static.c:320-353`). |
| F6 | Re-adding the same endpoint name reuses the dead session. | `rmr_wh_open` looks the endpoint up by name (`rt_ensure_ep`, `rt_generic_static.c:1581-1607`). If it is still `open`, `rt_link2_ep` returns at once (`rtable_si_static.c:139`), so no new connection is made. `rmr_wh_close` only blanks the slot. Neither `dms_cli` reinstall nor an rtmgr prune/re-add can fix a stale endpoint. |
| F7 | Live: every xApp whose pod was replaced in run 2 is unreachable by rtmgr, permanently. | The rtmgr log shows a dead session on the first push after each old pod died: `send failed; errno` with `tp=110` (ETIMEDOUT), then `tp=32` (EPIPE) on every later push. The status is the echoed `newrt\|start`. rc from 23:07:41.013, kpimon from 23:08:52.367, hw-go from 23:09:56.769. The last successful pushes went to the *old* kpimon/hw-go pods during their 30 s grace (23:08:32, 23:08:54). The new kpimon and hw-go pods have never received a table from rtmgr. |
| F8 | Live: rtmgr has no TCP session to any xApp's port 4561. | rtmgr `/proc/net/tcp` shows ESTABLISHED `:4561` sessions only to submgr, e2mgr, a1mediator and e2term (×2). There are none to rc `10.98.131.130`, kpimon `10.109.115.169` or hw-go `10.111.79.228`. rtmgr PID 1 holds 23 socket fds, 6 of which are absent from the kernel TCP tables (fds 23, 27, 31, 35, 36, 38). These are dead sockets RMR still holds. |
| F9 | Run 2 replaced rc *twice* before `h4kxg`, the first time by `rc_install`. | `install_xapp_ric_control.sh:138-144` (VM tree `4c8397d`) always runs `dms_cli uninstall rc`. The "not found" message prints unconditionally because of `\|\| true` inside the `if`. The rc Services were recreated: gRPC ClusterIP `10.102.47.96` → `10.99.49.54`, Services 15 m old, while kpimon/hw-go Services are 24–25 h old. Pod `959jd` started 23:07:20, was deleted by `rc_ric_reset` at 23:07:40, and `h4kxg` started at 23:07:41. |
| F10 | rc never receives SIGTERM, so it never deregisters and appmgr never notifies rtmgr. | The Dockerfile has `CMD ./rc` (shell form), and rc logs `"PID":"7"`. rtmgr shows no `Data received on Http interface` between 23:06:45 and 23:07:41, although the uninstall happened at about 23:07:18. As a result, rtmgr kept the rc endpoint and its whid 8. |
| F11 | Run 1 worked because rc was new to this rtmgr. | At 23:02:39 the log shows `AddEndpoint for service-ricxapp-rc-rmr … count = 21` and `Wormhole ID is 8`, followed by a successful push. |

### Likely but unproven (it does not change the remedy)

- **Why rtmgr's receive loop never processed the deaths.**
  - The first send after each death returned the socket's *pending* ETIMEDOUT. So no `recv()` had run on that fd for 9–40 s, even though `siwait.c` would have closed it within 300 ms if it were polling it.
  - Supporting evidence: three inbound sessions on rtmgr:4560 have growing unread receive queues. They come from e2mgr `.154`, submgr `.157` and a1mediator `.171` (e.g. `0x24180`→`0x24C80` bytes in about 10 min). So rtmgr's SI95 loop is not servicing some of its sockets.
  - Candidate mechanism (medium): SI95's session list is changed from two threads without a lock. These are `siconnect.c:161-166` in the caller thread, and `sinewses.c:70-74` and `sibldpoll.c` in the receive thread.
  - I could not prove it. It is also inconsistent with the e2term pod replacement at about 22:15, which rtmgr did re-dial: new sessions, inodes 2594807 and 2601998. That case was probably a graceful exit.
- **Why ETIMEDOUT and not a clean close (medium).**
  - kube-proxy runs in **IPVS** mode (k8s v1.33.13). Once the old pod or Service is gone, the dying pod's FIN is likely dropped.
  - SI95 sets keepalive to idle 1 s / interval 1 s / count 1 (`siestablish.c:217-225`). That kills the session within about 2 s, with ETIMEDOUT.

## 2. Per-run reset mechanism

**Recommended (A): replace the xApp pods, then restart rtmgr.**
1. Reset the Influx bucket.
2. Delete the rc, kpimon and hw-go pods together, so the three 30 s graces run in parallel. `--grace-period=5` on rc loses nothing, because rc never sees SIGTERM.
3. Wait until each new pod is Ready, has a new name and has RestartCount 0.
4. Run `kubectl -n ricplt delete pod -l app=ricplt-rtmgr --wait=true`. Use pod delete rather than `rollout restart`, so the Deployment spec is not changed.
5. Wait until the new rtmgr pod is Ready.
6. Run the readiness gate in §3.

Properties of (A):
- **What the restart gives.** The new rtmgr process has a fresh RMR context. At startup it re-reads the xApps from appmgr, the E2Ts from e2mgr and the **subscriptions from submgr** (`httprestful.go:496-579`, `QuerySubscriptions` at :562). Then it opens fresh wormholes to every endpoint and pushes.
- **Order matters.** rtmgr must restart *after* the xApps are listening. Otherwise `AddEndpoint` sleeps 10 s, fails, and skips that endpoint until the next update (`nngpush.go:94-100`).
- **Cost.** About 1.5–2.5 min per run, comparable to the current serial 109 s. Measure it.
- **Risk to rtmgr's table.** None beyond today. The table is regenerated from the same sources.
- **12041/12042 −1 owner.** It re-rolls, as it already does on every regeneration. Periodic pushes come every 65 s: 23:03:26, 23:04:31, …, 23:09:56.
- **kpimon/hw-go.** They get real sessions again, instead of running on seed tables.

Rejected options:
- **(a) `dms_cli` uninstall+install per run.** It does not fix F6 (same endpoint name, so the same dead endpoint is reused).
  - It makes the problem worse: it deletes the Services, which guarantees the black-holed session.
  - It changes the rc ClusterIP each time. That would break `gate-r0-rc-scripted.sh`, which computes `RC_EP` once and embeds it in the schedules.
  - Run 1 is not evidence that it works repeatedly (F11).
- **(b) Pod delete plus a "forced route refresh".** No REST or notification lever helps. Every refresh goes through the same stale RMR endpoint (F5, F6). A new RMR context is the only cure, and that means an rtmgr restart.
- **(c) Keep the rc pod across runs.** This contradicts contract item 7, "Per-run RIC reset (rc, …)". It also lets rc's `ricRequestInstanceID` counter carry over between runs, which changes the wire between C1 runs. Do not adopt it without the user.
- **(d) Fallback only: a seed table for rc** (`RMR_SEED_RT` with `rte|12040|service-ricplt-e2term-rmr-alpha.ricplt:38000`), in the same way the testbed already seeds kpimon and hw-go.
  - It is cheap and robust for rc's control path.
  - But it changes the deployment of the system under test, hides rtmgr failures, and does nothing for TS↔QP xApp-to-xApp routes in P5/P8.
  - Use it only with user ratification.

## 3. Readiness gate that predicts a working rc

All of these must hold, with a bounded wait of about 90 s after the new rtmgr is Ready:
1. **Necessary basics (keep the current checks).**
   - Pod Ready, a new name, RestartCount 0, and container `startedAt` after the reset began.
   - gRPC `describe` through the Service.
   - rtmgr's table contains `12040` → e2term.
   - Note: none of these is sufficient (F2, F3). The 12040 check reads rtmgr's *intent*, not rc's table.
2. **The decisive check (startup state).** The *current* rc container's log has the line `rmrClient: RMR is ready after <n> seconds waiting...`. This is xapp-frame v0.8.3 `rmr.go:201`, logged once and immediately before the ready callback that sets `gControlData`. Its absence, or a trailing run of `Waiting for RMR`, means not ready.
3. **rtmgr side.** rtmgr's `/proc/net/tcp` has an ESTABLISHED session to `<rc-rmr ClusterIP>:4561` (port `11D1`). Its log since the restart shows `Update Routes to Endpoint: service-ricxapp-rc-rmr.ricxapp:4560 successful` and no `send failed; errno` for any xApp.
   - Treat rtmgr's other "failed"/"successful" lines as noise. Calls are serialized under xapp-frame's `contextMux` with a 200 ms timeout. A timeout also logs a freed tx buffer, which is where the garbage "state" numbers come from (`rmr.go:508-541` in v0.9.16; `send_msg` frees on success).
4. **Same session check for kpimon and hw-go.** Apply check 3 to them as well. Their "RMR ready" is meaningless because of their seed tables.

**No canary gRPC control.**
- On an rc that is not ready, a control panics it.
- On a ready rc, it puts a real RICcontrolRequest on the wire.
- It also uses instance ID 2, which shifts the per-run ID sequence and pollutes the wire, ledger and digests.

## 4. Recreating kpimon and hw-go per run

**Today it does damage.** Without an rtmgr restart, each pod replacement leaves another dead session in rtmgr (F7, F8). This is harmless for R0, because kpimon subscribes over REST and indications are routed by e2term's table. But rtmgr can never update those pods again, and the change adds retry noise.

**With (A) it is fine and literal-compliant.**
- Pods are replaced (the Deployment "stays deployed"), RestartCount is 0, and rtmgr re-dials.
- It also gives kpimon fresh per-run state.

**Why absolute 0 needs recreation.** Snapshots are `--disk-only` and taken with a shutdown (`vm-snapshot.sh:10-12, 41-60`). Every revert therefore boots the VM and adds 1 to every pod's RestartCount, which is how hw-go reached 8. So an absolute 0 for stay-deployed pods requires recreation after each boot or revert.

**The alternative needs the user.** "Unchanged during the run" is a re-reading of a locked signal: weaker, because a crash before the run is invisible.
- Do not adopt it silently.
- Record both values in `verdict.json` anyway: the absolute count after the reset and the in-run delta, plus `lastState.terminated`.

## 5. Triggers, and what needs the user at Stop A

- **T3.** Not fired with (A). Every item-7 signal can be met as written. It *would* fire if you adopted (c), or the delta reading, without the user.
- **T4.** Not fired. RMR and rtmgr internals are not 3GPP/O-RAN items. A seeded rc (fallback d) would be a change to the system's deployment, not a standards deviation, but it still goes to the user.
- **T5 (judgment call; record the reading you take).**
  - This is an L-release defect: rtmgr 0.9.6 with RMR 4.9.4 never re-dials a route-push session after the pod behind it is replaced.
  - The root cause is found, and the remedy uses only L components (restart rtmgr). No acceptance signal is weakened.
  - **Default: report, do not pause,** provided that E1 and the re-run of q8 (checklist) pass and the agents' KPM indications still reach kpimon.
  - **Pause T5** if the rtmgr restart does not cure rc, or if it regresses KPM or the M5–M7 behaviour.
  - A strict reader of "On an L failure: stop" would pause now. That is defensible, but costly.
- **Stop A items:**
  1. the L defect, and the reset now including an rtmgr restart (to ratify);
  2. kpimon and hw-go recreated per run to meet RestartCount 0 literally;
  3. the semantics of the −1 owner (§6.2);
  4. the cost per run in the M9 budget;
  5. the T5 reading taken.

## 6. Other worries before the R0 dev rehearsal and the gate

1. **`rc_install` is not idempotent.** On a VM where rc already exists, it reinstalls rc (F9), killing the session and changing the ClusterIPs.
   - In the per-run path, never call it. It belongs only in i0, and should be skipped when rc is already at the pin.
   - If it does run, always follow it with an rtmgr restart.
   - The old q8 design would also have failed on its second run.
2. **The recorded −1 owner is often wrong.**
   - `ROUTE_OWNER_*` comes from rtmgr's `getdebuginfo`. That disagreed with e2term's installed table (its stash) in 3 of 5 comparable dumps: run 1 subscribed and end, and run 2 start.
   - Causes: pushes are out of order (concurrent `send_sync` retries), and e2term's stash is overwritten by `updatert` deltas (run 2 "subscribed" has no −1 lines).
   - The owner can also flip every 65 s during a run.
   - Fixes:
     - record both views;
     - take the owner from e2term's stash only when it is a full `newrt`;
     - mark it "unknown" otherwise, and flag any change between start, subscribed and end.
   - For the true receiver of each ack, capture RMR on `cni0` (TCP to the xApps' port 4560, then decode mtype/sub_id).
3. **P5/P8 will hit the same defect.**
   - The TS xApp is restarted *after* the agents are CONNECTED. That needs an rtmgr restart with live E2 sessions and subscriptions.
   - Startup re-fetches the subscriptions (`httprestful.go:562`), but verify KPM continuity across that restart in the R2 dev run.
   - Check the TS and QP env for `RMR_SEED_RT`.
4. **Control-plane instability.** kube-controller-manager (19 restarts) and kube-scheduler (20) both restarted at about 23:01, during run 1. That is consistent with host load.
   - Record their restart counts at the start and end of every run.
   - A change before C1 is a bounded bring-up retry. It is never a reason to re-run C1.
5. **Possible build-up of appmgr subscriptions.** Each rtmgr start POSTs an appmgr subscription (`httprestful.go:579`). Today there is 1 rtmgr subscription plus 1 vespamgr. After the first rtmgr restart, check `GET /ric/v1/subscriptions`. If rtmgr's `targetUrl` now appears twice, notifications multiply per run. In that case, delete the stale id as part of the reset.
6. **Minor.**
   - `q8_facts` raises a traceback when no ledger exists; make it a clean fail.
   - Record rtmgr's pod uid and RestartCount in `*-pods.tsv`.
   - Run 2's ns-3 exit 5 and pacer exit 3 are downstream of the rc panic, not a pacing bug.

## What to avoid

- Gating on rc's k8s Ready, on gRPC `describe`, or on rtmgr's 12040 row alone. All three passed in run 2 while rc was dead.
- Reinstalling rc per run, or calling `rc_install` from a run gate.
- Sending a canary control.
- Interpreting rtmgr's "SendBuf failed" lines. They are Debug lines that appear on every call, including `state is good`.
- Restarting rtmgr *before* the xApp pods are listening.
- Silently switching RestartCount to a delta reading.

## Work checklist

1. **E1 (confirm, about 2 min).**
   - Delete only the rtmgr pod.
   - Expect the current `h4kxg` rc log to show `RMR is ready after …` within about 60 s.
   - Expect rtmgr `/proc/net/tcp` to show ESTABLISHED sessions to `10.98.131.130:4561`, `10.109.115.169:4561` and `10.111.79.228:4561`.
   - Expect no `send failed; errno` lines after the restart.
   - Note it on the resume card.
2. **Rewrite `rc_ric_reset`:**
   1. Reset the bucket.
   2. Delete the three pods in parallel.
   3. Wait until each new pod is Ready, has a new name and has RestartCount 0.
   4. Restart rtmgr.
   5. Wait until rtmgr is Ready.
   6. Run the §3 checks 2–4 with bounded waits, logged.
3. Remove `rc_install` from q8 and from the per-run path. Make i0 skip it when rc is at the pin.
4. Fix the owner recording as in §6.2. Add rtmgr and control-plane restart counts to the pod snapshots.
5. Re-run smoke q8 twice back to back. The second run is the real test.
6. Then the R0 dev rehearsal (`--dev`). Measure the reset time per run for the M9 budget.
7. Journal and implementation notes: the L defect, the evidence lines above, and the T5 reading taken.

## Success metrics

- Two back-to-back q8 runs are green on the wire (1 ACK with Outcome Format 1 plus 1 FAILURE), with RestartCount 0 for all five pods and the agents.
- rc logs `RMR is ready` within 90 s of each reset.
- rtmgr shows 0 `send failed; errno` lines for any xApp.
- kpimon writes to the fresh bucket, and its log window is complete.
- The reset time per run is ≤ 3 min. There is exactly one rtmgr subscription in appmgr after N restarts.

## Assumptions

- **Run 1's rc was the first rc that this rtmgr process had seen.** Medium confidence: rtmgr logs before 22:24Z have rotated away. If rc had been there earlier, run 1 means re-dialling *sometimes* works, which strengthens the need for the gate rather than changing the remedy.
- **An rtmgr restart cures rc and does not disturb KPM.** Medium-high: this follows from the source, F6 and `httprestful.go:496-579`, but has not been observed. E1 and the q8 re-runs decide it. If it fails, PAUSE T5.
- **The TS xApp and QP behave like rc for routes pushed by rtmgr.** Medium: their env was not checked.
- **"stays deployed" means the Deployment persists, not that the pod identity persists.** Medium. If the user means pod identity, Stop A item 2 decides it.

## Unresolved questions

1. Why rtmgr's SI95 receive loop does not service some sessions (§1, "Likely"). One packet capture on `cni0` during a single rc pod delete would show whether the FIN reaches rtmgr.
2. Does appmgr de-duplicate rtmgr's subscription when rtmgr restarts (§6.5)?
3. Do the TS xApp and QP set `RMR_SEED_RT`?

**Status:** DONE_WITH_CONCERNS. The root cause and the remedy are verified in source and in the live state. The remedy itself has not yet been exercised live (E1).

**Next steps:**
1. Run E1 (rtmgr restart only), and record the evidence on the resume card.
2. Implement the new `rc_ric_reset` (pods, then rtmgr, then the §3 gate), and remove `rc_install` from the per-run paths.
3. Fix the owner recording (both views, plus "unknown" when the stash holds a delta).
4. Run smoke q8 twice back to back.
5. Run the R0 dev rehearsal, and measure the reset cost.
6. Log the L defect and the T5 reading in the journal and implementation notes, and carry the five Stop A items.

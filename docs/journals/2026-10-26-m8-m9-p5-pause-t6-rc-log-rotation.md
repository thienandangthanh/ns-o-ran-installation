# M8–M9 paused in P5: gate i2 --part stub red on rc's rotated log (PAUSE T6), 2026-10-26 ~22:25 KST

Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`. Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/i2/20261026T125704Z/`. Counsel: `plans/reports/kongming-261026-2205-GH-1-p5-i2-rc-log-rotation.md` (advice only, not user approval).

## 1. Why this is a pause
The user re-issued the goal at 21:53 KST, which released the 2026-10-24 PAUSE T6. I applied the fix from that pause's journal (section 3), which was kongming's guidance, as harness `8c88b7a`, and re-ran gate i2 `--part stub` fresh. It failed again, on a different cause. The phase-05 Failure Protocol says: apply kongming's guidance, re-run the Verify step, and if it fails again, print PAUSE T6. The 2026-10-24 journal already read the protocol this way, including that a different root cause does not reset the count. kongming's earlier no-go trigger (a third harness red in this segment that is not an L-release cause means stop and re-scope) points the same way. This is the third such red, after `84c2a33` and `fa1bf1e`. No code was changed after the red.

It is not T3, because the acceptance signal can still be met as written. It is not T5, because kubelet rotating a chatty xApp's log is Kubernetes behaviour meeting a harness assumption, not an L-release defect. It is not T4, because no standard is involved.

## 2. What the run showed
- **The 8c88b7a fix worked.** `i2_ts_ready_listening_no_control_api_error` passed. `i2_a1_threshold_reaches_ts_xapp` passed on the ordering rule: a stale threshold line (7066) came before this run's first payload (7068) and was ignored, and the pass came from line 7069. The facts were `a1ThresholdAttempt=2` and `a1DeliveredAttempt=1`, as predicted. Restart counts were 0.
- **The red.** `i2_rc_installed_at_pin_and_ready` and `i2_rc_rmr_ready_after_rtmgr_restart` both failed in `rc_rmr_ready` (`scripts/gates/rc-lib.sh:87-99`): "no 'RMR is ready' line within 90 s".
- **The cause, verified on the VM.** The rc pod `ricxapp-rc-6db9dcd964-jbcb4` has run since 2026-10-23 08:58:59 UTC. rc logs one INFO line for every kubelet probe, about 149 KB/h. kubelet runs with its defaults (10 MiB, 5 files) and rotated rc's log at 2026-10-26 07:22:01 UTC. `kubectl logs` reads only the current `0.log`, so the one-time start-up line, now only in `0.log.20261026-072201`, is no longer visible. The start-up line disappears about 70 h after any rc pod starts.
- **rc itself is healthy.** The pod is Ready, gRPC describe through the Service works, and the 12040 route is present.
- **Exposure.** `rc_at_pin` is the first rc check of gates i2, r0, r1, r2 (and q8), always on the pod the previous gate left. Inside r2's per-run loop, `rc_ric_reset` replaces rc, and M9 starts from fresh-install, so only checks on a kept rc pod are hit.
- **The post-restart checks never proved their name.** On a kept pod, `i2_rc_rmr_ready_after_rtmgr_restart` re-finds an old line, and in r2 it finds the line from the first rtmgr restart of the run, not the second. The real post-restart evidence today is the rtmgr session check, which includes rc's Service.

## 3. Proposed fix, for the user's release (kongming section 3)
Rule: a gate reads a pod's one-time start-up line only from a pod the gate itself created; for a kept pod, liveness is proven by fresh evidence (an rtmgr acknowledgement, a session, or wire bytes).
1. **i2:** before `gate-i2-ts-xapp-install.sh:40`, add `check i2_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket rc_ric_reset pre`. It is the tested per-run reset (about 44 s), and `check-ric-reset.py` proves the pods and bucket are new.
2. **r0 and r1:** the same line before `gate-r0-rc-scripted.sh:87` and `gate-r1-rc-multi-control.sh:86`. These scripts belong to green rungs; their next run is in P6 and M9.
3. **r2:** before `gate-r2-ts-stub-qp.sh:104`, `rc_ric_reset pre`, then `ts_stub_pods_reset pre`, because `ts_at_pin` reads the kept TS xApp pod's one-time `listening on port 4560` line (the same hazard).
4. **Optional strengthening:** at `i2:67` and `r2:183`, run `rc_rmr_ready && rtmgr_push_acked service-ricxapp-rc-rmr`. The new helper polls the fresh rtmgr pod's log (process substitution, at most 90 s) for `Update Routes to Endpoint: service-ricxapp-rc-rmr.ricxapp:4560 successful`, which rtmgr writes only when rc's RMR answered its route-table call.
5. **`rc-lib.sh` header:** state the rule and the reason.
6. Then: lint, i2 `--part stub` fresh (expect `pre-reset.json` fresh, an rc pod other than `jbcb4`, the RMR-ready line, the rtmgr acknowledgement if adopted, `a1ThresholdAttempt=2`, `a1DeliveredAttempt=1`, restart counts 0), then gate r2 `--mode calibrate`. Any further i2 red, or a red in a new pre-reset check, is T6 with no further patching.

Rejected: reading the start-up line from the rotated files under `/var/log/pods` (a 3-day-old line says nothing about now, needs `.gz` handling and goes red after about 5 rotations); `kubectl logs --previous` (rc has not restarted); deleting the rc pod by hand and re-running unchanged (green on hand-made state); raising `containerLogMaxSize` on the VM (changes Kubernetes configuration outside scope and makes the dev VM differ from fresh-install).

No option changes the locked outcome: the contract already resets rc per run, every existing check keeps its name, and C1's compared components are unchanged. M9 gains about 1–3 min per gate, within `run-to-m9.sh`'s timeouts.

## 4. Other kept-pod aging hazards (kongming section 4)
- **TS xApp:** kept by i2 `--part stub` by design. Its log grows about 27 KB/h, so pod `2hx5c` reaches the rotation size around 2026-11-09. A resume with a kept TS xApp pod older than about 10 days should run i2 `--part all` first. M9 runs `--part all` with a fresh install.
- **kpimon:** fresh per run and read through the rotation-aware `pod-log-window.py`, which fails closed. Watch R3 (UL on, longer runs): a rotation shows as exit 3, never a false green.
- **Stub QP, hw-go, rtmgr, a1mediator, e2term, e2mgr:** fresh per run or not read through logs.
- **P8:** gate r3 must follow the same rule at its top.

## 5. State at the pause
- **VM:** running at `r0-green`, boot time 2026-10-23 07:56:59 UTC.
- **rc:** at `a2282ee`, pod `jbcb4` (kept, log rotated).
- **TS xApp:** `19e169b` with substitutions 3 and 2 (image `f521d56b…`), registered, threshold 10 set by this run.
- **Stub QP:** reinstalled by this run, registered, routes present. a1mediator fresh (restarted by i2). No agent containers.
- **Snapshots:** `fresh-install`, `f7-rerun-green`, `r0-green`.
- **Disk:** host `/home` 49 G free.
- **Pins:** ns-3 `962fabc7`, oran-interface `63155c49`, Testbed `597bdde2`. Harness: `8c88b7a` plus the evidence and pause commits.

## 6. Questions for the user
1. Does a release reset the Failure Protocol's one-fix budget? A standing ruling would settle this for later pauses.
2. Do you approve the rule "a start-up line only from a pod the gate created", including the edits to the green rungs' r0 and r1 scripts?
3. Should the rtmgr push acknowledgement be added to the `*_rc_rmr_ready_after_rtmgr_restart` checks, or should the smaller diff be taken (record that the check proves "this gate's rc container is RMR-ready" and let the session check carry the post-restart claim)?

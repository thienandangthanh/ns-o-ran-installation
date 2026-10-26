# Decisions: user rulings on the P5 rc log-rotation pause (2026-10-26 22:30 KST)

Pause: PAUSE T6, journal `docs/journals/2026-10-26-m8-m9-p5-pause-t6-rc-log-rotation.md` (section 6), counsel `plans/reports/kongming-261026-2205-GH-1-p5-i2-rc-log-rotation.md`. These rulings are the user's; kongming's counsel is not user approval.

## Rulings
1. **Re-issuing the goal resets the one-fix budget (standing ruling, every phase).** After a release, the first failed Verify gets one kongming-guided fix again; a red re-run of that fix is T6. Recorded in `plan.md` under T6, so it overrides the 2026-10-24 reading for later pauses.
2. **Own-pod rule approved: a gate reads a pod's one-time start-up line only from a pod it created itself.** The user approved the edits to the scripts of the green rungs r0 and r1, asked for the changes to be noted, and will have them regression tested.
3. **Option A: the post-restart checks also require rtmgr's push acknowledgement.** `*_rc_rmr_ready_after_rtmgr_restart` now passes only when rc's start-up line is in its current container and the running rtmgr pod logged `Update Routes to Endpoint: service-ricxapp-rc-rmr.ricxapp:4560 successful`.

## Changes made (harness `611271d`)
| File | Change |
|---|---|
| `scripts/gates/rc-lib.sh` | New `rtmgr_push_acked <svc> [ns]` (polls the running rtmgr pod's log through process substitution for at most 90 s) and `rc_rmr_ready_after_rtmgr`; a header note with the own-pod rule and the reason (rc logs every kubelet probe, about 150 KB/h; kubelet rotates at 10 MiB, about 70 h; `kubectl logs` reads only the newest file). |
| `scripts/gates/gate-i2-ts-xapp-install.sh` | New check `i2_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket` (`rc_ric_reset pre`) before `i2_rc_installed_at_pin_and_ready`; `i2_rc_rmr_ready_after_rtmgr_restart` runs `rc_rmr_ready_after_rtmgr`. |
| `scripts/gates/gate-r0-rc-scripted.sh` | New check `r0_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket` before `r0_rc_installed_at_pin_and_ready`. |
| `scripts/gates/gate-r1-rc-multi-control.sh` | New check `r1_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket` before `r1_rc_installed_at_pin_and_ready`. |
| `scripts/gates/gate-r2-ts-stub-qp.sh` | New checks `r2_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket` before `r2_rc_installed_at_pin_and_ready` and `r2_pre_ts_and_stub_pods_fresh_rtmgr_sessions` (`ts_stub_pods_reset pre`) before `r2_ts_xapp_at_pin_ready_in_grpc_mode`; `r2_<label>_rc_rmr_ready_after_rtmgr_restart` runs `rc_rmr_ready_after_rtmgr`. |

No check was removed, renamed or narrowed. The pre-reset reuses `rc_ric_reset` and `ts_stub_pods_reset`, the functions every per-run reset already calls, and their freshness proofs (`check-ric-reset.py`, `check-ts-stub-reset.py`) write `pre-reset*` and `pre-ts-reset*` files, which no verdict script globs. C1's compared components are unchanged. Each gate gains about 1–3 min.

## Regression for r0 and r1
The r0 and r1 scripts changed after their C1 passed (`evidence/r0/20261023T073520Z`, `evidence/r1/20261023T084654Z`). The changed lines run before any live run, so the C1 verdicts' compared components are unaffected. The regression test the user asked for: one live run each of gate r0 and gate r1 at harness `611271d` or later, with every check green, including the new `r?_pre_ric_reset_…` check. P6 already schedules one live run each of R0, R1 and R2; the r0 and r1 regression runs there unless the user wants it earlier.

## Verification so far
- `scripts/gates/lint.sh`: ok (bash -n, shellcheck, the log-pipe rule).
- The rtmgr success string was read from the live rtmgr pod on 2026-10-26 (`"msg":"Update Routes to Endpoint: service-ricxapp-rc-rmr.ricxapp:4560 successful, call_id: 1, …"`).
- Not run yet on the VM: gate i2 `--part stub` at `611271d`, then gate r2 `--mode calibrate`. They run when the user re-issues the goal.

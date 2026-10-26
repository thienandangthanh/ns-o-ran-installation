# kongming counsel: P6 r0 regression red on the restart counts of the kept TS xApp and stub pods

2026-10-27, about 02:35 KST. This is Failure Protocol counsel for P6, step "regression: gate r0 `--mode single` at the current pins, before any N4 code". It is the first failed Verify of P6. It is advice only and **not user approval**. Model: Opus 5.5 (the user's routing for kongming).

**Read for this counsel**
- `goal-packet.md`, `plan.md` and `phase-06`.
- `decisions-261026-2230`.
- My earlier P5-exit counsel, `kongming-261027-0145`.
- The evidence `evidence/r0/20261026T165654Z`: `gate.log`, both pods TSVs, `pre-reset-pods-before.json`, `live1-reset-pods-after.json`, `route-owners.tsv`, `r0-run-facts.json`.
- The harness: `rc-lib.sh`, `ts-lib.sh`, `check-ric-reset.py`, the r0, r1, r2, i2, m6 and m7 gates, `endurance-eval.py`, `run-to-m9.sh`, `vm-snapshot.sh`.

I did not touch the VM.

## TL;DR
1. **This is a harness/state interaction, not an L-release failure and not a product defect.** Not T5.
2. **Recommended fix: option B, with a guard.** Leave the harness unchanged. As a recorded precondition, recreate the TS xApp and stub pods once before r0, but only because a VM boot explains their restarts. Then re-run r0 single and run r1 single. Do not recreate them again before r1; check them read-only instead.
3. **Reject option A.** It narrows a contract-listed check and would hide a real signal.
4. **Reject option C.** It costs a lot and adds risk for no gain in strictness.
5. **M9 needs no change.** P7 (i3) and P8 (r3) must recreate every pod they judge.
6. **T6 budget.** This is the one guided fix for the r0/r1 regression step. Any red on that step afterwards, in r0 or in r1, for any cause, is PAUSE T6.

**Correction of my own counsel.** `kongming-261027-0145` (Q2, "One difference from M9") called the kept pods harmless during r0 and r1 and named only the −1 owner. I missed that the r0 and r1 restart judges cover every ricxapp pod. The resume card is also wrong: the TS xApp and stub are **not** "replaced by every gate's per-run reset". Only r2 and i2 replace them. r0 and r1 recreate only rc, kpimon and hw-go (`rc-lib.sh:212`).

## Q1. Cause: harness/state interaction (verified)
| Fact | Evidence |
|---|---|
| The two restarts predate the gate. None happened during it | `live1-before-pods.tsv` and `live1-after-pods.tsv` are identical. stubqp `rrkd6` and trafficxapp `f57mf` show 1 in both |
| The restart is the r2-green reboot, not a crash | `lastState.terminated` for both: `reason: Unknown`, `exitCode: 255`, `finishedAt 2026-10-26T16:26:52Z`, 4 s after the boot at 16:26:48. This is the kubelet's record of containers lost to a node restart. The new containers started at 16:27:17 and 16:27:22; the pods were created at 14:49:39 (`pre-reset-pods-before.json`). `vm-snapshot.sh:10` creates a snapshot as shutdown, then snapshot, then start |
| Every pod and container the rung uses is at 0 | rc `k5k8m`, kpimon `dlxth` and hw-go `h6rmv` were created by the live1 reset at 17:02:29. Agents 1–3 are at 0 |
| The judges are unchanged since R0 and R1 went green. The namespace changed | `rc_restarts_zero` (`rc-lib.sh:179`) and r0 `restart_all_zero` (`gate-r0-rc-scripted.sh:357`) are untouched since 5b137aa and acff82f, both before the R0 C1 at `cfc6ef4`. R0 C1 (073520Z) and R1 C1 (084654Z) snapshots list only rc, kpimon and hw-go. `git diff 94657df 29f287c -- scripts tools` is empty |
| The kept pods were inert in r0 | 12041 and 12042 −1 owner = kpimon at both start and end (`route-owners.tsv`). Nothing sends 30003 without r2's injector. The TS xApp starts with threshold 0 and never answers A1 (`ts-lib.sh:68`). C2 holds: 4 answers = 4 ledger lines |
| The regression's actual subject is green | `r0_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket` and `r0_live1_c9_handover_rows_match_applied_lines` pass. Every other check passes |

**Root cause.** The harness already states its own design rule: "the pods that stay deployed carry restarts from earlier VM boots, so they are recreated per run" (`rc-lib.sh:198-202`). The r0 and r1 gates follow that rule only for the pods that existed when they were written. P6 is the first time r0 runs with pods it neither creates nor recreates, after a VM boot. In M9 the order is i0 → r0 → r1 → i2, so these pods do not exist yet.

## Q2. The fix and the strictness argument
**Recommendation: B, with a boot guard. State, not code.**

**Why B keeps the test at least as strict**
- The code is identical to the red run, so the predicate and the judged set do not change. The predicate is absolute 0 on every ricxapp pod and every agent.
- P6 still judges a superset of what M9 judges: 5 pods plus agents, against 3 plus agents.
- Any restart after the precondition still turns the gate red. That includes a stray-ack crash of the TS xApp, which becomes a −1 candidate whenever rtmgr restarts.
- The only restarts B clears are ones with a recorded, external cause that predates the gate: the VM boot. That is exactly what `rc_ric_reset` already does for rc, kpimon and hw-go.
- The guard makes this safe. A restart that a boot does not explain is evidence of a crash and is never cleared.

**Why A is a narrowing.** It removes contract-listed components from a check: contract item 7 lists "RestartCount = 0 for rc, TS xApp, QP …". In P6 those pods are live −1 route candidates on R0's ack path, so a TS xApp crash during r0 is a real RIC-health signal. A would hide it. The check's name lists only the rung's own pods, but that does not license dropping coverage. A delta variant ("no restart during the run") would weaken the literal = 0. Either version needs a user ruling; kongming cannot approve it.

**Why not C** (uninstall the TS xApp and stub, then reinstall through i2 before r2):
- It means helm/dms churn, appmgr deregistration and route changes, and a TS xApp image rebuild.
- That costs several GB on a thin disk margin.
- The rebuilt image could differ from the image of the R2-green run.
- It needs i2 `--part all` at an unexercised harness. That is another possible red inside a one-fix budget.
- The only gain would be M9-representative −1 owner values, which r0 and r1 record without judging.

**D (alternative, not recommended now).** Teach the r0 and r1 per-run reset to recreate the TS xApp and stub when they are deployed, by calling `ts_stub_pods_reset`. This is the most literal reading of "per-run reset (rc, TS xApp, QP)". The costs:
- It is a third edit to green rungs, which the user would have to note.
- It is a branch M9 never runs.
- It adds an a1mediator restart, a second rtmgr restart, appmgr calls and a five-peer session check to every r0/r1 run. Each is a new way to go red inside the budget.
- It would also recreate the pods between gates and hide a crash in between.

Choose D only if the user rules that "per-run" literally covers r0 and r1.

**B, concretely**
| # | Action | Pass condition, else stop (T6) |
|---|---|---|
| 0 | Read-only checks: domstate, `snapshot-current` = r2-green, boot time still 2026-10-26 16:26:48 UTC. Save `kubectl -n ricxapp get pods -o json` to host evidence (`evidence/p6-pre/<UTC>/pods-before.json`, scrubbed) | Matches the resume card |
| 1 | **Boot guard**, for each of `f57mf` and `rrkd6` | All of these hold: restartCount = 1; `lastState.terminated` is `Unknown`/255 with `finishedAt` within 60 s after the boot; the running container started after the boot; the pod was created before the boot. Today: yes for both |
| 2 | `kubectl -n ricxapp delete pod ricxapp-trafficxapp-7c46768578-f57mf ricxapp-stubqp-685cb7ddf4-rrkd6 --grace-period=5`, keeping the default `--wait=true` | Both old pods are gone, with none left Terminating. A Terminating pod would otherwise appear in `rc_pod_snapshot` |
| 3 | Wait at most 300 s, the bound `_wait_new_ready` uses (`ts-lib.sh:87-96`). Save `pods-after.json` | One Ready pod per Deployment, each with a new name and uid and restartCount 0 |
| 4 | Do **not** register, set A1, or restart a1mediator or rtmgr | Registrations survive a pod replacement (`ts-lib.sh:293`). r0's own pre-reset restarts rtmgr (`rc-lib.sh:226`), which gives sessions to the new pods. a1mediator's black-holed connection is r2's to fix, and r2's `ts_stub_pods_reset` already does so |
| 5 | Commit and push the cause record, this counsel and the corrected resume card | `git diff --stat 94657df <sha> -- scripts tools` is empty, so this is the same code |
| 6 | `vm-exec.sh gate-r0-rc-scripted.sh --timeout 5400 -- --mode single` | Exit 0, every check PASS. `pre-reset-pods-before.json` shows the new pods at 0. All 8 rows of `live1-after-pods.tsv` are 0 |
| 7 | Before r1: read-only check. **Do not recreate again** | The pod names equal r0's `live1-after-pods.tsv`, their counts are 0, and the boot time is unchanged. Anything else means a restart between the gates: T6, and do not run r1 |
| 8 | `vm-exec.sh gate-r1-rc-multi-control.sh --timeout 5400 -- --mode single` | Exit 0, every check PASS, with `r1_live1_restart_counts_zero_rc_kpimon_hw_go_agents` (`:174`) and `r1_restart_counts_all_zero` (`:396`) green. Single mode is C8 plus live1. f2 runs only in c1 mode (`:270-272`) |

**r1.** Yes, the same trap applies to r1, because its judges at `:174` and `:396` have the same scope. The one recreation before r0 covers r1. If either pod restarted during or after r0, recreating it again would erase the evidence.

**Permissions.** If the auto-mode classifier refuses the ssh `kubectl delete`, that is T8. Do not work around it by falling back to A or D.

## Q3. Later snapshots, gates and invariants
- **The effect is general.** Every VM boot adds 1 to every kept container's restart count: a snapshot create (`vm-snapshot.sh:10`), a revert, `--no-snapshots` boundary reboots, or the user shutting the VM off during a pause. Only gates that judge absolute 0 on pods they do not recreate are exposed.
- **M5–M7: no change.** Their restart checks are deltas against a baseline (`gate-m6-kpm.sh:65-66, 136`; `endurance-eval.py:9,13`), built for this very snapshot reboot.
- **M9: no change.** Snapshots fall only at the m0–m7 boundaries (`run-to-m9.sh:51-66`; i0 to r3 have suffix `-`). The TS xApp, stub and QP do not exist before i2 and i3. Each later gate recreates the pods it judges.
- **P6 later (V4 r0 and r1 after N4).** With no reboot in between, the pods from step 3 are still at 0, or r2 has recreated them. After a boot, apply the same boot-guarded precondition. This is the standing procedure set by this fix, not a new fix. A restart without a boot is a V4 failed Verify.
- **K20 rollback to r2-green** brings back `f57mf` and `rrkd6`, with counts of 2 after that boot. The precondition applies there too.
- **P7 i3 and P8 r3** (to be written). If they use `rc_restarts_zero`, they judge every ricxapp pod. Before the r3-green boot, and before P9 regenerates the reference after it, both gates must:
  - start with `rc_ric_reset pre` and a TS xApp/QP pods reset, as i2 and r2 do;
  - reset per run as contract item 7 says;
  - fail closed on any unexpected ricxapp pod, which strengthens K12 (stub down).

  Put this into the P7 and P8 files as a design requirement.
- **Invariants.** The locked invariants do not change. Record a derived harness rule in `implementation-notes.html`: "RestartCount = 0 is judged literally. A gate reaches it by recreating pods, never by filtering or deltas. Only a boot-explained restart may be cleared, as a precondition." Offer it to the user at Stop B as a corollary of the 2026-10-26 own-pod rule. Do not add it to the card yourself.
- **Records.** Correct the resume card's VM line.
- **Stop B note** (no code now). The r0 and r1 `restart_map` facts (`gate-r0-rc-scripted.sh:360-377`) list only rc, kpimon, hw-go and the agents. The verdict therefore under-reports what the judge covered; in P6 the TSVs carry the rest.
- **Side benefit.** The recreation resets the TS xApp's log-aging clock, which the journal of 2026-10-26 puts at about 10 days to rotation (§4).

## Q4. T6 budget
- **Yes, this is the one guided fix.** The goal was re-issued and this is the first failed Verify since. The 22:30 ruling gives exactly one guided fix.
- **The step is the r0/r1 regression (ruling 2) as a whole.** One cause, one fix.
- **A red afterwards means PAUSE T6, with no second consult or fix.** That covers any of these, for any cause:
  - the boot guard or the recreation in steps 1–3 fails;
  - the r0 re-run fails;
  - the r1 pre-check fails;
  - r1 single fails.

  This matches the 2026-10-24 precedent: a different cause on the same Verify step was still T6. It also matches the resume card's "Any further red on this step is T6".
- **Later P6 Verify steps (V1–V6).** My reading is that each gets its own first-failure consult. The phase Failure Protocol is per Verify step, and the ruling addresses only the reset on release. The user has not ruled on that point explicitly; see Unresolved.
- The "red C1" rule does not apply to single runs. Its spirit does: cause recorded, change committed (step 5), then a fresh run.

## What to avoid
- Do not filter pods out of the judge, switch to deltas, or rename the check.
- Do not recreate before r1, or before any gate, when a boot does not explain the restart.
- Do not revert to r2-green to fix this; that makes the counts 2.
- Do not run gate i0. The boot time is unchanged.
- Do not restart a1mediator or rtmgr by hand in the precondition.
- Do not launch r0 while an old pod is still Terminating.

## Success metrics
- r0 and r1 single exit 0 with every check green.
- The before and after snapshots show 8 rows at 0, the TS xApp and stub pods created after step 2, and the same names in r1 as at the end of r0.
- No new harness diff under `scripts/` or `tools/`.

## Assumptions
- **High:** the restart came from the r2-green boot (kubelet `Unknown`/255, 4 s after boot, no change across the gate).
- **High:** M9 is unaffected (snapshot boundaries m0–m7 only).
- **Medium-high:** the TS xApp and stub are inert in r0 and r1. This rests on harness comments and the route-owner evidence, not on reading the TS xApp source. It does not affect the fix, because any restart still turns the gate red.
- **Medium-high:** T6 counts per Verify step per release, and r0+r1 is one step. If the user means one fix per release, any later P6 red is T6 directly.
- **Medium:** the classifier permits a two-pod `kubectl delete` over ssh. A refusal is T8.

## Unresolved questions
1. Does the user want "recreate, never filter; boot-explained only" ratified as an invariant? Ask at Stop B.
2. Is the T6 budget per Verify step or per release? Not explicitly ruled; the 22:30 ruling covers only the reset.
3. Is "per-run reset (rc, TS xApp, QP)" meant literally for r0 and r1 when those pods are deployed? That is option D, and only the user can rule on it.

Status: DONE
Summary: This is a harness/state interaction: the r2-green reboot restarted the kept TS xApp and stub pods, and the r0 and r1 judges cover every ricxapp pod. Fix with a boot-guarded recreation of those two pods before r0 (no code change, the judges unchanged), re-run r0 single and run r1 single; any further red on this step is PAUSE T6.
Concerns/Blockers: the T6 reading for later P6 Verify steps is not ruled; my 0145 counsel and the resume card misstated which gates replace the kept pods.

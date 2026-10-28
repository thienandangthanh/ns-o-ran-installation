# Failure Protocol counsel: P10 M9 attempt 3, m6 red (no E2 Setup Response)

Date: 2026-10-29 ~01:15 KST. Advisor: kongming on Opus 5.5 (`model: opus`), per the user's CLAUDE.md routing. This is advice only; it is never user approval. Scope: the first failed Verify after the 22:43 KST goal re-issue, so the one-fix budget is fresh (standing ruling of 2026-10-26).

## TL;DR
- **Root cause.** The fault is in the L-release RIC platform after a cold boot. rtmgr's route pushes to **e2mgr and submgr** never took effect, so the route tables of those two components stayed frozen at their boot-time version.
  - e2mgr therefore had no endpoint for 12002 (E2 Setup Response) or 1101 (keep-alive).
  - submgr could not have routed kpimon's subscription either.
  - The AddE2T HTTP 400s are a red herring: the green m5 boot shows the same three 400s.
- **Our agents and forks did not cause it.**
- **Recommended path: option (b), one guided fix F″, confined to the bring-up code.**
  - After the RIC is Ready and e2term is registered, restart rtmgr once per VM boot and require sessions from rtmgr. This is the restart the R-gates already do on every run.
  - Add an agent-level "E2 Setup answered" precondition with one bounded remedy.
  - Validate F″ on the live, still-broken VM before the revert.
  - Then run M9 attempt 4 from `fresh-install` with prefix `q`.
- **When to pause instead.** PAUSE T5 only if the live probe shows that no restart sequence cures the frozen tables.

## Reframed problem
- **What is being decided:** how to spend the single guided fix so that attempt 4 has a high chance of a green V1/V2, without changing the locked outcome.
- **The core requirement:** the M9 runner reboots the VM at every boundary (`scripts/run-to-m9.sh:176-177`, 13 cold boots per run). Every gate that needs E2 traffic must therefore start from a RIC whose route distribution is *measured* healthy (plan.md cross-cutting rule "RIC state is a measured precondition… Bounded, logged retries only for bring-up preconditions, never for C1").

## 1. Classification (Q1): your reading, corrected
Verified from `evidence/m9/20261028T134954Z/m6-diagnosis/`. Each log file holds the m6-boot container followed by a `=== previous` section, which is the **green m5 boot**: a free control. I also ran read-only live `kubectl get/logs` at 16:03Z.

**What the evidence shows**
1. **The AddE2T 400s are not the cause.**
   - The m5 boot (green) had the identical pattern: 400 at 15:35:38, 15:36:12 and 15:37:00, then 201 at 15:37:47, and its 12002 at 15:39:29 was sent.
   - In the m6 boot, the 4th AddE2T also succeeded. rtmgr logged `AddE2T Request Success` at 15:44:38, and e2mgr logged a 201 and "successfully added E2T instance".
   - So `_wait_e2t_registered` (`scripts/gates/bringup.sh:172-199`) passed truthfully at 15:44:39.
   - The "invalid Wormhole ID" errors only mean e2term was not up yet. Its previous container ended Error/137 at 15:42:09, and the pod became Ready at 15:44:28; those errors stop after that.
2. **The discriminator is the receivers' live route tables.** Each component prints `RMR [INFO] sends: … target=<endpoint>` every ~31 s for every endpoint in its current table.
   - **e2mgr, m6 boot:** the target set stayed {rsm, e2term-svc, submgr, a1mediator} from 15:41:38 through 15:51:18. It still had not changed live at 16:01:20Z.
     - It never contained `10.98.86.163:38000` (E2TERMINST), hw-go or kpimon.
     - Hence `12002 … could not find an endpoint` (e2mgr.log 15:45:10.5139) and the 1101 failures at 15:43:07, 15:45:07 and 15:47:07.
   - **e2mgr, m5 boot:** it gained hw-go and kpimon by 15:35:25, and `10.98.86.163:38000` by 15:38:00, 13 s after the AddE2T success. It then sent 2 messages to that endpoint.
   - **submgr, m6 boot:** its table stayed at {e2mgr} only. In the m5 boot it had hw-go, kpimon, e2mgr and a1mediator, and later the E2T. So kpimon's subscription would have failed even with a successful E2 setup.
3. **Sender side (rtmgr.log).**
   - Wormhole IDs 1 (submgr) and 2 (e2mgr) were opened at 15:41:19, 23 s after those pods started (15:40:46).
   - The first e2mgr push failure was at 15:41:45 (call 4). From 15:46:50 on, every push to e2mgr failed.
   - Live at 16:03Z, over the last 8 minutes: 33/33 pushes to e2mgr failed and 33/33 to submgr failed, while 11/11 to each of the other five endpoints succeeded.
   - So this is persistent, not a start-up transient that heals: the pushes to these two endpoints were broken for the whole window, and their tables never changed.
4. **rtmgr's "successful" lines are not delivery evidence.**
   - At 15:44:39.739, rtmgr logged `Update Routes … successful … OK` for all 7 endpoints with the same `call_id: 16`, including e2mgr and submgr, whose tables never changed.
   - Belief, not verified in source: acks are matched by call_id across concurrent pushes.
   - Consequence: `rtmgr_push_acked` (`scripts/gates/rc-lib.sh:111-121`) can be green for an endpoint that never received the table. Record this for after M9; do not change it now. It sits under the 2026-10-26 kept-pod evidence ruling, and rc's own "RMR is ready" line remains the primary evidence for rc.
5. **CONNECTED is set before the response.** e2mgr changed the status to CONNECTED at 15:45:10.5131 (e2mgr.log line 118). The 12002 send failed at 15:45:10.5139 (line 135). So `_agents_wait_connected_exact` (`scripts/gates/agents.sh:145-167`) and `m6_bringup_agents_kpm_sim_stopped_connected_set_exact` cannot detect this failure.

**Not caused by our agents or forks**
- e2term forwarded the agent's 12001 normally.
- e2mgr parsed it (RAN function 2), saved the nodeb, and built the E2 Setup Response; only e2mgr's RMR send failed.
- The frozen tables predate any agent traffic: the failures started at 15:41:45, and the agent's first association was at 15:45:07.
- All 10 failed checks are downstream of "no E2 Setup Response":
  - subs 0, forwarded 0, `e2Down` 57, zero indications, empty Influx.
  - The emitter's hello=2 / `droppedDisconnected` 3 fits the P3 design in which agents exit on association loss and Docker restarts them (`scripts/gates/gate-m7-multignb.sh:13`). That is why the final stats show `connectAttempts` 1. This last link is belief, but it is consistent with the evidence.

**Classification**
- **Root cause:** a defect in the L-release platform's route distribution at cold start (rtmgr 0.9.6 / RMR 4.9.4 towards e2mgr and submgr). It is nondeterministic per boot: the same procedure was green at the m1–m5 boots.
- **Contributing harness gap:** the bring-up precondition measured "CONNECTED" and "E2T listed", not "routes delivered / setup answered".
- **Why the R-gates are immune:** they run `rc_ric_reset`, which restarts rtmgr (`scripts/gates/rc-lib.sh:219-250`, `:129-141`), before every `gate_bringup agents` (`scripts/gates/ts-rung-lib.sh:50-53`, `gate-r0-rc-scripted.sh:159-165`, `gate-r1-rc-multi-control.sh:148-154`, `gate-r3p-ts-predictor.sh:131-132`). m2, m3, m5, m6 and m7 never restart rtmgr after the boundary reboot.
- **Not T5 by default.** The contract pre-authorizes bounded, logged bring-up remedies, and this project has handled every comparable L defect that way without T5:
  - P3: rtmgr stale wormhole;
  - P5: a1mediator stale connection;
  - P6: dbaas wiping the A1 type.

  T5 fits only if no in-contract remedy exists (see §2, the validation gate).
- **Your 2026-10-21 cold-boot note** ("accepted on SCTP but never answered") may have been the same failure class. That is speculation; no RIC logs exist from that run.

## 2. The one guided fix (Q2): option (b), F″, bring-up only

**Why not (a), a re-run without a code change**
- Rough estimate (wide uncertainty): 1 failure in ~9 exposed cold boots across attempts 1–3, so p ≈ 0.1 per boot.
- With six exposed gates per run (m1–m3, m5–m7), P(no repeat) ≈ 0.5, and a second red is T6 with nothing learned.
- It also skips "record the root cause and commit a change". That rule is C1's, but here it applies by analogy and by the Failure Protocol.

**Why not (c), a pause now:** see §1. Pause only through the validation gate below.

**F″ content**

All changes are in `scripts/gates/bringup.sh` and `scripts/gates/agents.sh`; the helpers move rather than being copied.

(1) **RIC-level prevention, once per VM boot**
- Where: `_bringup_ric`, right after `_wait_e2t_registered` (`bringup.sh:121`).
- Key: `/proc/sys/kernel/random/boot_id`, with a marker under the VM user's `$HOME`, so it fires only at the first bring-up after each boundary reboot.
- Steps:
  1. Restart rtmgr. Use the `rc_restart_rtmgr` logic, moved into bringup.sh as the single definition; rc-lib.sh keeps the name, or a one-line wrapper.
  2. Within a bounded wait (~120 s), require rtmgr ESTABLISHED sessions to `ricplt/service-ricplt-e2mgr-rmr`, `ricplt/service-ricplt-submgr-rmr` and `ricplt/service-ricplt-e2term-rmr-alpha`. Use the `rtmgr_sessions` and `svc_ip` logic from `ts-lib.sh:264-279` and `:73`, moved.
  3. Settle for `E2T_SETTLE_S`, then write the marker.
- Log each step to the gate log and `$EVIDENCE_DIR/watchdog.log`.
- On failure, `return 1` (fail-closed).

(2) **Agent-level measured precondition with one remedy**
- Where: `agents_bringup`, after `_agents_wait_connected_exact` (`agents.sh:198`).
- Wait (bound `AGENTS_SETUP_WAIT_S`, default 60 s; the agent prints stats every 5 s and retries setup every ~18 s) until every agent's last stats line shows `state == READY` and `e2.setups >= 1`. This is the predicate that `all_subscribed` (`ts-rung-lib.sh:6-14`) and m5's `agent_ready` (`gate-m5-agent-setup.sh:54-67`) already trust.
- On timeout, apply **one** remedy, logged with `agents_stats_all` and the e2mgr states:
  1. Stop the agents.
  2. Run the forced rtmgr refresh, which ignores the marker.
  3. Check the sessions.
  4. Start the agents again.
  5. Check the CONNECTED set, then READY.
- If it still fails, `return 1`.

**What F″ must not touch**
- No judged check, `run-to-m9.sh`, `m9-verdict.py`, `pins.conf`, `m9-budget.json`, `tools/` or `reference/`.
- No rtmgr, e2mgr or e2term code or config (out of scope).

**Contract fit**
- F″ adds checks and removes none, so it is not a weakened test.
- The remedy is a bounded bring-up retry. It fires before any judged evidence of the run, and never re-runs a C1 run.
- The locked outcome does not change, so the T6 "would change the outcome" clause does not apply.

**Freeze and reference**
- K14 then reads `git diff --quiet F″ HEAD -- scripts tools`.
- `reference/r3p/` holds no harness SHA (verified at F′). The bring-up runs before the simulation, and the R-gates already restart rtmgr on every run. So the digests should not move: high confidence, and M9's own r3p `--reference` compare is the proof.
- Unlike F′, F″ changes VM gate code. The honest trade-off is that the F rehearsal no longer covers it exactly. The mitigation is the live validation below, not a full r3p rehearsal.

**Codex:** print `Codex skipped: run cap reached` (CX-3). Under CX-1, have kongming (opus) review the F″ diff; a code-reviewer subagent can serve as an extra reader.

**Validation gate (before any revert)**
- Push F″ (vm-exec clones the pushed SHA: `scripts/vm/vm-exec.sh:27-29`).
- Run `gate-m6-kpm.sh` at F″ on the **live, still-broken VM**. This is the discriminating fixture: F′ on this state is red and stayed red for 20+ minutes.
- Expected: one refresh in the bring-up log, sessions OK, the agent READY within seconds, and m6 green. Its evidence is a dev run under `evidence/m6/`, not part of the M9 run.
- If it is red at the sessions or READY step, do one manual probe:
  1. Delete the e2mgr and submgr pods, then rtmgr.
  2. Re-check the e2mgr and submgr `sends:` targets.
  3. If that cures it, make it the refresh sequence and re-validate. This is still the same guided fix, pre-M9.
  4. If nothing cures it, PAUSE T5, with the root cause recorded and no in-contract remedy.

**Prefix:** `q` is within the Failure Protocol ("must use a prefix whose names do not exist", phase-10).
- Precedent: attempt 1's counsel chose `o` without a user ruling. `p` went to the user only because attempt 3 followed a PAUSE in which every item was ruled.
- `q` passes the runner's rules (`run-to-m9.sh:47-53`: one lower-case letter, not f or l, no `q[0-9]-*` snapshots).
- Record the choice; do not ask.

## 3. Release order and root-cause record (Q3)
Yes: before the re-run, record the root cause and commit F″. The C1 rule applies by analogy, and the Failure Protocol requires it as well.
1. Capture the live facts (§4).
2. Record the root cause: resume card, `implementation-notes.html`, a pointer to this counsel. Commit and push (plans only).
3. Implement F″. Run `lint.sh`, `m9-runner-selftest.sh` and `m9-verdict.py --self-test`. Get the kongming diff review. Commit and push.
4. Validation gate (§2).
5. Freeze record: an F″ addendum in `m9-budget.md` and `m9-run-report-template.md`, both showing F″ and q.
   - `git diff --name-only F′ F″ -- scripts tools <reference>` lists only the bring-up files.
   - `git diff --quiet F′ F″ -- tools <reference> scripts/run-to-m9.sh scripts/m9-verdict.py scripts/pins.conf scripts/m9-budget.json` exits 0.
   - No budget change is needed: the worst case adds ~1–3 min per boot plus ≤ 5 min if a remedy fires, against m6's 1088 s budget (~8 min observed) and the 20,199 s wall.
   - Commit and push.
6. Launch-route amendment order (phase-10), with F″ and q:
   1. Resume checks (chain plus m0-probe n, o and p allowed).
   2. Pre-flight 2–6 at F″, and no `q[0-9]-*` or `m0-*-q*` names, and no `m9-*` unit.
   3. Resume card.
   4. Smokes `m9-q-smoke` and `m9-q-clientkill`.
   5. Revert `fresh-install`.
   6. Leaked-overlay checks 1–5 on the active overlay at revert time only. Confirm it with `domblklist` and `snapshot-dumpxml`; the caller identifies it as `ubuntu24.1793195425`. Then `rm` and `pool-refresh`, logged under `evidence/p10-disk/<ts>/`. **Never** delete `ubuntu24.1793195253` (frozen data of `m0-probe-p10281349`) or `ubuntu24.1793186494` (frozen data of `m0-probe-o…`).
   7. `df -BG /home` ≥ 84, else T2.
   8. `r3p-green` is listed.
   9. Access smoke `m9-q-access`.
   10. Memory gate ≥ 23 GiB, else T3.
   11. Projection row.
   12. Launch the `m9-q` unit, logging to `evidence/m9/runner-q.log`.
- No host reboot is needed: the reaper environment variable is already in this session; record `printenv` and `pgrep` for browsers as facts.
7. On exit, apply V1–V5 per the Stop B mapping. Any red → `PAUSE T6`; there is no second fix.

## 4. Capture before anything touches the VM (Q4)
These are read-only. Save them into `…/m6-diagnosis/live-<UTC>/`.
- **rtmgr TCP state:** `kubectl -n ricplt exec <rtmgr> -- cat /proc/net/tcp /proc/net/tcp6`, plus `kubectl -n ricplt get svc -o wide`.
  - Question: are there ESTABLISHED sessions to the e2mgr and submgr VIPs on :4561 (`11D1`)? What are `tx_queue` and the retransmit counts?
  - This decides whether `rtmgr_sessions` can detect the failure or merely gates it.
- **Receiver TCP state:** the same `/proc/net/tcp` read inside e2mgr and submgr, looking for :4561 peers (rtmgr pod IP 10.244.0.105?).
- **Node IPVS state:** `/proc/net/ip_vs_conn` filtered to those VIPs, and `sudo -n ipvsadm -Ln` if allowed.
- **rtmgr route table:** `kubectl get --raw` through the service proxy to rtmgr `/ric/v1/getdebuginfo`.
- **Persistence:** fresh `kubectl logs --since=15m` for e2mgr, submgr and rtmgr. I verified at 16:03Z that e2mgr's targets were unchanged and the push failures were 33/33; save it as a file.
- **e2term and cluster events:** `kubectl describe pod` for e2term (reason for the 137) and `kubectl get events -A --sort-by=.lastTimestamp`. Also kube-proxy logs since boot.

## What to avoid
- Re-running without a change. Pausing T5 before the live remedy probe.
- Trusting e2mgr CONNECTED, `e2t/list` or rtmgr's "successful … OK" as delivery evidence, or building F″ on `rtmgr_push_acked`.
- Restarting rtmgr on every `_bringup_ric` call. That creates churn inside the R runs; once per boot is enough.
- Changing judged checks, timeouts, the budget, the runner or the verdict. Editing rtmgr, e2mgr or e2term.
- Consuming the broken VM state (for example a manual rtmgr delete) before the §4 capture and the F″ validation run.
- Reusing p, or choosing f, l, m, n or o. Deleting any probe's frozen-data overlay.

## Alternatives and trade-offs
- **(2) only, the conditional agent-level fix.** It leaves green paths untouched, but m2, m3 and m7's peers stay exposed; m2 and m3 depend on submgr too. That is weaker.
- **(1) only.** It is simpler, but it relies on sessions as a proxy. Without (2), any residual case again shows up as 10 confusing reds.
- **Moving the R-gates' full `rc_ric_reset` into the M-gates.** It is heavier, recreates kept xApp pods and perturbs validated M-gates. Not worth it.

## Work checklist
1. §4 capture.
2. Root-cause records; push.
3. F″ code, lint and self-tests, `Codex skipped: run cap reached`, kongming review; push.
4. m6 at F″ on the live VM (validation gate; the T5 off-ramp).
5. Freeze record; push.
6. Pre-flight and release order with q; launch `m9-q`.
7. V1–V5; GOAL DONE or PAUSE T6.
8. After M9: record the `rtmgr_push_acked` false-OK finding and the `finish()` orphan gap (ruling 6) in the handoff.

## Success metrics
- The validation m6 run at F″ is green on the broken state, and its log shows exactly one refresh and READY within ≤ 20 s.
- In attempt 4, every exposed gate's log shows "rtmgr refreshed (boot …)", sessions OK, and READY without the remedy (or a logged remedy that heals).
- V1 = 0, the exact step set, r3p `equalsReference = true`, `minHostFreeGb` ≥ 25.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| Restarting rtmgr cures, or once all pods are Ready prevents, the frozen e2mgr and submgr tables. Basis: P3 precedent and the R-gates' per-run restarts. | medium-high | The validation run fails → manual e2mgr+submgr+rtmgr probe → T5 if nothing cures it. |
| The failure is stochastic per cold boot. | medium | It recurs on the validation run despite the refresh. |
| The F″ bring-up does not change any r3p digest. | high | `equalsReference` false in attempt 4 → T6. |
| Prefix q is within the Failure Protocol. | medium-high | A user ruling that requires prefix approval. |
| rtmgr's false "OK" comes from call_id-shared acks. | medium (the mechanism is speculation; the symptom is verified) | rtmgr or RMR source reading. |

## Unresolved questions
- The exact transport mechanism that froze the wormholes to e2mgr and submgr. The §4 `/proc/net/tcp` and `ip_vs_conn` capture should settle it.
- Whether earlier green chains had near-misses: no RIC logs were kept.

Status: DONE_WITH_CONCERNS
Summary: root cause = cold-boot L-release rtmgr route distribution never reached e2mgr/submgr (AddE2T 400s are normal, not causal); guided fix F″ = once-per-boot rtmgr refresh + agent READY precondition with one remedy, validated on the live broken VM, then attempt 4 with prefix q; T5 only if no restart cures it.
Concerns: F″ changes VM bring-up code after the freeze (mitigated by live validation, not a rehearsal); remedy efficacy is unproven until the validation run.

## Addendum after the §4 capture (2026-10-29 ~01:40 KST)
Source: `evidence/m9/20261028T134954Z/m6-diagnosis/live-20261028T161753Z/`. I decoded `tcp-*.txt` myself and confirm the caller's reading.

**Facts from the capture**
- **e2mgr is not reading its route-table socket.** Its `:4561 <- 10.244.0.105:59314` socket is ESTABLISHED with rx_queue 126,454.
- **submgr is not reading either.** Its `:4561 <- 10.244.0.105:46316` socket has rx_queue 126,145.
- **rtmgr is blocked on exactly those two sessions.** Its tx_queue is 60,410 towards the e2mgr VIP and 59,149 towards the submgr pod IP. Every other :4561 session has tx_queue 0. Retransmits are 0.
- **The transport is healthy.** The RMR route-table collector inside e2mgr and inside submgr stopped reading.
- **The first push was never acked.** Call 1 (15:41:24–25) got an empty status from both e2mgr and submgr. The "OK" on call 2 is the cross-matched ack described in §1.4.
- **What follows for F″ as first written:**
  - `rtmgr_sessions` cannot detect this state; it would pass now.
  - Restarting rtmgr alone probably cannot cure it, because a wedged collector would not read a new connection either.

**Trigger (speculation; the mechanism is unknown).** Both collectors started 23 s before rtmgr existed, during a cold boot. This is not the R-gates' pattern. There, xApp receivers are replaced while the old rtmgr is up and rtmgr is restarted afterwards, and that has stayed healthy across every R-run.

### Adjusted F″ (replaces §2's items 1–2)
**Detection predicate: receiver-side, transport-level, no logs.** A new helper, `rt_reader_ok <e2mgr|submgr>`:
1. Read `kubectl -n ricplt exec <pod> -- cat /proc/net/tcp /proc/net/tcp6`. `ss` may be missing from the image; `cat` is proven to work.
2. Wait up to 120 s until at least one socket has local port `:11D1` and state `01`.
3. Take up to 5 samples, 2 s apart. The receiver is OK when every such socket shows rx_queue `0` in at least one sample.
4. Why this discriminates:
   - A healthy collector drains the ~4 KB pushes immediately.
   - A wedged one only accumulates (126 KB here).
   - "No ESTABLISHED socket" also catches the P3 stale-wormhole class (rtmgr still holding a replaced pod).
5. Log the decoded rows to `$EVIDENCE_DIR/rt-readers-<tag>.txt`.

**Refresh sequence: `ric_refresh_routes`, in `bringup.sh`.**
- Bounded and logged to the gate log and `watchdog.log`. At most one RIC-level and one agent-level use per gate run, guarded by `mkdir` markers in `$EVIDENCE_DIR`.
1. Save evidence: the three `/proc/net/tcp` dumps, the `e2t/list` output, and `logs --since=5m` for e2mgr and submgr.
2. Delete the e2mgr and submgr pods together.
   - Use `kc -n ricplt delete pod <e2mgr> <submgr> --wait=true`.
   - Use `delete pod`, never `rollout restart`: a surge would briefly run two e2mgr or two submgr against the same SDL.
   - Wait for each new pod to be Running 1/1, bound 180 s each.
3. Run `_wait_e2t_registered`. The E2T instance lives in rNIB (dbaas), and dbaas is not restarted, so this should pass immediately. The NIST e2term roll still applies after 300 s.
4. Restart rtmgr last, with the moved `rc_restart_rtmgr` logic. rtmgr must restart after the receivers for two reasons:
   - its wormholes to the old e2mgr VIP backend and the old submgr pod IP would otherwise stay stale (P3);
   - its startup fetch should read the E2T list from the new e2mgr.
5. Apply `rt_reader_ok` to both receivers, then settle for `E2T_SETTLE_S`. If it still fails, `return 1`.

**Hooks**
1. **`_bringup_ric`, after `_wait_e2t_registered` (`bringup.sh:121`).** Run `rt_reader_ok` for e2mgr and submgr on every call; it is read-only and takes ~5–15 s. Only if it fails, run `ric_refresh_routes`.
   - The boot-id marker and the unconditional rtmgr restart from §2 item 1 are dropped.
   - This also covers m1 (fresh install), m2 and m3 (refnode), and the R-gates. In the R-gates the check runs after `rc_ric_reset`, because `agents_bringup` calls `_bringup_ric` first.
2. **`agents_bringup`, after `_agents_wait_connected_exact` (`agents.sh:198`).** Keep the READY predicate (`state == READY` and `e2.setups >= 1`, bound 60 s). On timeout, the one remedy is:
   1. stop the agents;
   2. run `ric_refresh_routes --force` (it ignores only the RIC-level marker);
   3. start the agents again;
   4. check the CONNECTED set, then READY.

**Side effects, checked against the capture and the earlier logs**
- **nodeb and CONNECTED state.** The RIC-level refresh runs before any agent of the gate. After a reboot, dbaas is empty (e2mgr returned "0 identity" at 15:45:08), so there is no RAN state to lose. Replacing e2mgr keeps the rNIB contents (nodebs, E2T instance). The exact CONNECTED-set check counts only CONNECTED nodes, so stale DISCONNECTED records do not matter; the R-runs already rely on this.
- **submgr and subscriptions.** submgr restores its subscriptions from SDL. Before agents exist there is nothing to break. kpimon re-subscribes on every reconnect ("it will be subscribed again after reconnecting", m6 kpimon log). Neither e2term nor kpimon had an open RMR connection to submgr (`open=0` in their `sends:` lines), so the headless pod-IP change cannot strand a sender.
- **Residual risk: e2term's existing connection to the e2mgr VIP:3801 (`open=1`) goes stale when e2mgr is replaced.**
  - Prediction from the 2026-10-24 IPVS note: a local RST, at most one lost message, then a re-dial.
  - The lost message could be one E2 Setup Request (the agent retries every ~18 s, inside the 60 s READY bound) or one keep-alive reply (keep-alives run every 120 s; the response timeout is far longer).
  - The validation run tests exactly this.
- **Budget.**
  - Green path: about +5–15 s per bring-up.
  - Remedy path: typically ~2–3 min, at worst ~8 min.
  - m6 (1088 s budget, ~8 min observed) fits one remedy. m5 and m7 have ample room. No budget or timeout change.
- **Untouched:** no judged check, runner, verdict, pins, budget, `tools/` or `reference/` changes. No rtmgr, e2mgr or e2term code or config changes, only pod restarts.

**Validation gate: still stands, and it is stronger now.** The live VM is in the exact wedged state. Push F″, then run `gate-m6-kpm.sh` at F″ on it. Expected:
1. `rt_reader_ok` reports rx ≈ 126 KB for e2mgr and submgr, i.e. wedged.
2. One refresh: e2mgr and submgr replaced, the E2T still listed, then rtmgr restarted.
3. Both receivers show rx 0.
4. The agent reaches READY.
5. m6 is green.
6. Check afterwards, by hand and not in code: e2mgr's `sends:` targets include `10.98.86.163:38000`, and submgr's include the E2T and kpimon.

**Off-ramp.** If any of these happen, the root cause is recorded but no in-contract remedy exists, so PAUSE T5 and stop iterating:
- the post-refresh `rt_reader_ok` fails;
- READY never comes;
- the new collectors wedge again.

### Corrections to earlier sections
- **§2:** replace "sessions" with `rt_reader_ok` everywhere.
- **§4:** the capture is done.
- **Success metrics:** add that every exposed gate's log shows `rt_reader_ok` passing for e2mgr and submgr, or one logged refresh that ends with it passing.
- **What to avoid:** add "detecting with `rtmgr_sessions` or rtmgr tx success", and "restarting rtmgr alone as the cure".

Status: DONE_WITH_CONCERNS
Summary: The capture shows wedged route-table collectors in e2mgr and submgr. F″ now detects them by receiver rx_queue on :4561 and remedies by replacing e2mgr and submgr, then restarting rtmgr last. Run the check on every `_bringup_ric` call and keep the agent READY backstop. Validate on the live wedged VM; PAUSE T5 if that does not cure it.

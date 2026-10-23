# Kongming PAUSE note: M8–M9 paused in P3 at the CPU hold (T3)

- **When.** 2026-10-23. My checks ran at 12:31 KST by the host clock. The brief says "~10:00 KST", and the journal and resume card say 09:55–10:00, so use the real `date` in the journal, the card and the PAUSE commit.
- **Runtime.** Claude Code, Opus 5.5 (per the user's CLAUDE.md). This is advice only and never counts as user approval.
- **Method.** The VM was inspected read-only: virsh, `uptime`, `kubectl get/logs`, and one appmgr GET. Nothing was changed, and no file was created under `plans/**/evidence`.

## Findings first

1. **The state is consistent and safe to resume from, but not yet ready to PAUSE.** The VM, the snapshots, rc and git all match the card's intent (§1 table). Before the PAUSE line:
   - commit the journal (untracked), the watchdog record (modified, 76 → 58) and this report, then push;
   - fix 3 stale lines on the resume card;
   - fix one wrong claim in the journal and add six missing items to it (§1).
2. **The calibration has no mechanism.** Worse, `gate-r0-rc-scripted.sh:49` hard-codes the provenance "contract start value (not calibrated)" whenever `--tctl` is absent. As a result:
   - a calibration mode would fail its own `r0_t_ctl_is_calibrated_or_run_is_dev` check;
   - **M9 would be red by construction**, because `run-to-m9.sh:61` runs r0 with `--mode single` and no `--tctl`.

   Fix: add `--mode calibrate` to gate r0, and have the gate read T_ctl's provenance from `rung-config.json` (§2).
3. **Gate i0 has never run.** No `evidence/i0` exists in either plan. rc was installed by the early q8 runs. i0 is P3 step 1, and it is the M9 chain step in front of r0 (`run-to-m9.sh:60`). It is hold-safe, so run it before the calibration.
4. **T3 is the right id.** Keep the PAUSE line strictly in its fixed format (§3).
5. **Do not revert.**
   - The card's three checks cannot detect a revert to `f7-rerun-green`, because snapshot-current is the same. Add the VM boot time as a marker: `2026-10-22 16:40:08 UTC`.
   - A revert to `fresh-install` now would probably cross the 20 GB host floor (T2) when the dev branch is rebuilt (§4).

## 1. Pause state (Q1)

| Item | Card / journal | Observed 12:31 KST | OK? |
|---|---|---|---|
| domstate, snapshot-current, snapshots | running, `f7-rerun-green`; `fresh-install`, `f7-rerun-green` | same (tree: fresh-install → f7-rerun-green) | yes |
| rc | installed at its pin | `~/nist/.../xApps/rc` at `a2282ee`. Pod `ricxapp-rc-6db9dcd964-q6qcp` is 169 m old, has 0 restarts, and its log has the line `RMR is ready after 30 seconds` | yes |
| rtmgr, kpimon, hw-go | recreated | rtmgr `…-4ld4k`, kpimon and hw-go each 169 m old with 0 restarts (from rehearsal 2's k9 reset) | yes |
| leftovers | none | no `gate-*` unit, no ns-3, pacer or agent container | yes |
| appmgr subscriptions | (0830 open question 2) | 2 entries after ≥ 12 rtmgr restarts, so they do not build up | closes 0830 Q2 |
| control plane | restarted at about 23:01Z | kube-controller-manager 19 and kube-scheduler 20 restarts, unchanged since then | yes |
| VM disk; host `/home` | 52 G; 58 G | 52 G; 58 G | yes |
| host load | (evidence only) | 0.88 / 0.86 / 0.73 on 20 CPUs. The top process is our qemu at 69 %. Two `claude` processes started at about 06:45 and 07:44 KST, each at 1–2 % CPU | not a release |
| git | pushed | HEAD `d8ba00e` = origin. Untracked: the journal. Modified: `…0009…/evidence/watchdog/min-host-free-gb.txt` (76→58, the M9 floor record). The stray `…1823…/evidence/watchdog/` is still there (P2-exit should-do 4), and `.claude/` and `.remember/` are pre-existing | commit the first two; do not commit the stray |

**Resume card (`plan.md:24-35`), stale lines:**
- **:26.** "Next: smoke q8, then Q2, G4…, repeat-gate, gate r0": all of these are done.
- **:29 vs :32.** The card gives 60 G in one line and 58 G in the other. Keep one value (58 G).
- **:31.** The harness SHA line still names the P2 commits. Replace it with the pause commit, and note that rehearsal 2 ran at `e67641a`.
- **Additions:**
  - VM boot `2026-10-22 16:40:08 UTC`;
  - rc pod `q6qcp`;
  - "gate i0 never ran";
  - the calibration mechanism (§2).

**Journal (`docs/journals/2026-10-23-m8-m9-p3-pause-cpu-hold.md`):**
- **Wrong (§3).** "Smoke q8 … Three runs with the final reset are green" is not what happened. At `30151ff` the runs were `234952Z` PASS and `235400Z` FAIL (the SIGPIPE in the readiness check). At `4919b30` the run was `000106Z` PASS. So 2 of 3 are green, and the one red was a harness defect fixed in `4919b30`.
- **Not true yet (§2).** "at the commit that carries this journal (pushed)". Make it true before printing the PAUSE line.
- **Missing (§4, option 2).** Without `--tctl` the gate is red at its first check (`:49`, `:67-68`). Option 2 needs `-- --tctl 30 --tctl-provenance "contract start value 30 s; calibration pending (user ruling <KST time>)"`.
- **Missing (§5.2).** There is no calibration mode. Name the mechanism in §2 below. Also: "slack from aborted steps (check)" is done (`pacer.py:213-215, 243-248`), but `pacer.py:211` still writes `L` for incomplete steps, so the calibration reader must filter.
- **Missing (§5.3).** The VM clones the **pushed** SHA (`vm-exec.sh:9-10, 30-31`). So `rung-config.json` with the new T_ctl must be committed and pushed before the real gate.
- **Missing (§5.4).** Give N. I recommend `--need-gb 11`, the remaining-dev projection from the P2 exit: 58 ≥ 31, so it passes. `vm-snapshot.sh` already refuses below 20 + N.
- **Missing (§5).**
  - Step 0: probe the VM boot time and the rc pod.
  - Run gate i0 before the calibration.
  - Record the host `uptime` and the top-CPU list at the calibration.
- **Missing (§6).** Two carry-forwards and one record fix:
  - `run-to-m9.sh:61` → r0 single mode is red by construction (finding 2);
  - `rung-config.json` is stale: substitution 1 `applied: false`, threshold −5 and `schedules.r0.path: null`, while both rehearsals applied substitution 1 from their own Q2 (5 switches);
  - in implementation-notes, rehearsal 1's harness is `4919b30`, not "c40ec1c-line".

## 2. Resume readiness (Q2)

**What L is.** For one trigger step, L = the pacer's wall time when it reads ns-3's `controlRx` (`pacer.py:124`) minus the wall time just before it spawns the trigger (`:190`). It covers:
- bash and grpcurl start-up;
- gRPC to rc;
- rc's RMR 12040 → e2term → SCTP → the agent;
- agent IPC → the ns-3 hub (blocked at barrier k);
- `controlRx` → the pacer.

A `controlRx` that arrives while `subprocess.run` is still blocking is stamped only when grpcurl exits. So L is a **conservative upper bound** on "trigger injected → control read by ns-3". Rehearsal 2 measured 12 values of 8.8–12.5 ms (labelled, recorded under the hold).

**What must not feed T_ctl:**
- steps that are not complete: `slackS` null, `controls ≠ expect`, `triggerRc ≠ 0`. `L` is still written for these (`:211`);
- `goBeforeTrigger` steps (k9). ns-3 is simulating when they arrive, so their L is not path latency;
- any run whose pacer exit or ns-3 exit is not 0;
- every L recorded under the hold (q8, both rehearsals, S1);
- slack values of any kind (`slackS`, `minSlack.*`). These derive from the old T_ctl;
- barrier and `stepsWaitS` waits;
- pcap request → answer times;
- rc, e2term or grpcurl logs.

**Recommended mechanism: `gate-r0-rc-scripted.sh --mode calibrate`.** It reuses `r0_live`, so the reset, CLI, capture and extractor are identical to the gated runs. The evidence goes to `evidence/r0/<ts>` with `mode: calibrate`; the run is not C1.
1. **`r0-scenario.json`.** Add `"calibration"`: 10 controls. The first four are the R0 controls at their steps 20/30/40/50 (C1 conditions, including the first control after a reset). The other six are alreadyOnTarget refusals, with zero radio risk. The layout after step 50 is 1→c2, 2→c3, 3→c3, 4→c2, 5→c2, 6→c3:

   | Step | via | imsi | target |
   |---|---|---|---|
   | 60 | 1 | 2 | 3 |
   | 66 | 2 | 4 | 2 |
   | 72 | 3 | 3 | 3 |
   | 78 | 1 | 5 | 2 |
   | 84 | 2 | 1 | 2 |
   | 90 | 3 | 6 | 3 |

   A refusal still produces `controlRx`, as step 50 did in both rehearsals. L ends before the hub decides the outcome, so the outcome cannot change L.
2. **`r0-checks.py`.** Add a `--calibration` selector to `schedule` and `expect`, the same way as `--forced-late`. Add `tctl SUMMARY N`, which requires:
   - `ended && !aborted`;
   - exactly N steps with `window == "T_ctl"`, no `goBeforeTrigger`, `controls == 1`, `triggerRc == 0`, `slackS != null` and one L each;
   - output `{L, LMaxS, tCtlS = max(30, ceil(20 × L_max))}` (round up, never down).
3. **Gate.** In calibrate mode:
   - prechecks, then Q2 (it sets −1000, identical CLI), then `r0_live cal … 10`, then `expect --calibration`, then `tctl`;
   - skip C8, G4, D7, the refusal check, k9 and C1. The D7 and refusal checks at `:188-203` run unconditionally today, so put them behind the mode;
   - `tctl_ok` must accept calibrate mode, because it necessarily runs at the 30 s start value.
4. **Provenance read (fixes M9 too).**
   ```bash
   [ -n "$TCTL_S" ] || { TCTL_S=$(python3 -I "$CFG" get deadlines.T_ctl_s); TCTL_PROV=$(python3 -I "$CFG" get deadlines.T_ctl_s.provenance); }
   tctl_ok() { [ "$DEV" = 1 ] || [ "$MODE" = calibrate ] || grep -Eq 'evidence/r0/[0-9]{8}T[0-9]{6}Z|user ruling' <<<"$TCTL_PROV"; }
   ```
   `rung-config.py get deadlines.T_ctl_s.provenance` already prints the string (`walk` returns the leaf).
5. **Host side.**
   - Run `rung-config.py set deadlines.T_ctl_s <tCtlS> "evidence/r0/<ts> (mode calibrate): L_max <x> s over 10 controls; max(30 s, 20 x L_max); host load <uptime>"`.
   - Also set substitution 1 (`applied: true`), threshold −1000 and `schedules.r0.path`, citing the same dir's `q2-outage-switches.txt`.
   - Commit and push. Then run the real gate with **no** `--tctl` arguments: `EVIDENCE_HOST_ROOT=<plan>/evidence scripts/vm/vm-exec.sh gate-r0-rc-scripted.sh --timeout 10800`.
6. **Keep the C1 path byte-identical** apart from those two lines, so that rehearsal 2 stays representative. Run `lint.sh`.
7. **Labels.** Rename the `lLabelledUnusedUnderHold` fact in the real gate to something like `lRecordedNotUsedForTctl`; after the release, the current label is false. Optionally add the fact `20 × max(L_gate) ≤ T_ctl`.

**First-gate-red risks I checked:**
- Determinism: proven at `e67641a` (103/103).
- `rc_at_pin` precheck: it passes now, because rc is RMR-ready. It **can fail after any VM boot**, because rtmgr may start before rc listens. This is unverified, since rc did not exist at the 16:40Z boot. The calibration run, preceded by i0, is the canary.
- Expected cost: i0 about 5 min, the calibration about 7 min, the gate 21 min, the snapshot about 5 min.
- The expected result is T_ctl = 30 s. It changes only if L_max > 1.5 s.

## 3. Pause id (Q3)

T3 fits: "an acceptance signal that cannot be met as written". V7's calibrated `tCtlSeconds` cannot be produced without breaking the user's 02:30 instruction, and the user re-confirmed the hold at 09:50. The other ids do not fit:
- T6: no Verify failed.
- T8: no permission refusal.
- T5: the L-release defect is already handled.

Print exactly `PAUSE T3 evidence=plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r0/20261023T002614Z journal=docs/journals/2026-10-23-m8-m9-p3-pause-cpu-hold.md`. Add nothing else; the only allowed suffixes are `kongming=unavailable` and `push=refused`. Put "user-directed, not a failure; T3 reading = V7" in the journal's first line. It is nearly there; add the user's 09:50 answer verbatim.

## 4. If the user reverts (Q4)

- **No revert, no boot: the expected case.** The boot time is still `16:40:08Z`. Run i0 → calibrate → gate.
- **Reboot only.** The boot time changes; the disk state is kept; every pod restarts.
  - Run i0 first: its `rc_install` ends with an rtmgr restart and RMR-ready.
  - Then calibrate, then the gate.
  - Before printing anything, update the card.
- **Revert to `f7-rerun-green`.** The card's three checks still match, so detect it by the boot time, rc being absent, and `~/m4-build` being off the pins.
  - The gates self-heal the builds: ns-3 is rebuilt when off the pins (≤ 5400 s, `agents-ns3-run.sh:41-48`), and the agent image is rebuilt on a tag mismatch (≤ 3600 s, `agents.sh:166-181`).
  - Sequence: i0 → calibrate with `--timeout 10800` (it absorbs the rebuilds) → gate.
  - If the user did not announce the revert, it is a card mismatch: PAUSE T3 with the difference.
  - Unverified: whether the discarded P1–P3 overlay frees `/home`. Check `vm-snapshot.sh list` and `du`.
- **Revert to `fresh-install`.** This means M0–M7 again, plus a second dev overlay of roughly 37–48 G next to the undeletable f7 chain. 58 − 40 ≈ 18 G, which is below the floor: T2.
  - Do not rebuild in segment 1 without a user ruling.
  - Print PAUSE T3 (mismatch) and let the user decide at a Stop-B-like ruling.
- **No new snapshot as a "safety net."** A name outside the snapshot rule's deletable list (`m0-*`, `r0-green`, `r2-green`, M9's) becomes undeletable without the user, which makes T1 likely later.

## 5. For the user before releasing (Q5)

- **The hold protects provenance, not the value.** 20 × L ≈ 0.2–0.3 s ≪ 30 s, so the calibrated value is almost surely 30 s. The rehearsals also show C1 digests equal under host load 2–4. T_gate slack is 9.997 s of 10.
- **Work allowed under the hold today.** Gate i0 (not a measurement) and the host-only code for §2 (calibrate mode, provenance read, rung-config fields). The user may allow these before releasing the hold.
- **After the release, about 1 h to the P3 exit:** i0, calibrate, commit, the real gate, `r0-green`, the checklist, and kongming on P4.
- **Each snapshot create or revert reboots the VM.** So P4's first R1 gate runs after the `r0-green` boot: run i0 first, or make the R-gate precheck reset before `rc_at_pin` (carry-forward to P4).
- **Stop A additions:**
  - the calibration mechanism (a plan deviation: a mode, not a separate gate);
  - the phase-03 file list collapsed into `gate-r0` + `rc-lib.sh` (no `repeat-gate.sh`, `ric-reset.sh`, `rtmgr-route-dump.sh` or `rc-install.sh`);
  - i0's first run date.

## Assumptions

- **High.** The L path ends at `controlRx`, before the outcome is decided, so refusals measure the same L. Step 50 in both rehearsals completed with expect 1.
- **High.** Digests do not depend on T_ctl (0735 §3).
- **Medium.** rc may miss RMR-ready after a cold boot. This is inferred from 0830 §2 "order matters", not observed.
- **Medium.** `--need-gb 11` is adequate. It is the P2-exit projection; P3's measured growth is about 2 G.
- **Medium.** One of the two host `claude` processes is the caller's session. I could not tell whether the other session is done, and that is not my call.

## Unresolved questions

1. Does the user release the hold, or allow option 2 (30 s first with explicit arguments)?
2. Does the user allow i0 and the §2 code under the hold?

**Status:** DONE_WITH_CONCERNS. The state is safe; the PAUSE prerequisites are listed in §1. Two latent defects need fixing before the real gate: the hard-coded provenance (M9 red) and i0 never having run.

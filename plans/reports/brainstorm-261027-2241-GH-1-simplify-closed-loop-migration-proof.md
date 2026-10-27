# Brainstorm (--ultra, debated with Codex): simplify the closed loop to prove the migration? (2026-10-27 22:41 KST)

User idea: the closed loop is a means of proving that the migration to NIST v1.8.0 / OSC L-release works. The ultimate goal is a ready-to-use ns-O-RAN testbed for handover and traffic-steering experiments with ns-3 scenarios more complex than scenario-zero. So simplify the closed loop to just prove the migration.

Method:
- Five independent read-only candidates (opus) worked from one immutable evidence packet.
- Two Codex perspectives (read-only, `task --fresh --effort high`), arguing for and against the idea.
- One kongming verifier (opus) scored the anonymized candidates against a 6-criterion rubric, with both Codex positions as the counterarguments each candidate had to survive.
- The winning candidate is reproduced **unchanged** below, followed by the verifier's caveats, the debate summary and the ranking.

---

## Winning contract (verbatim)

# Brainstorm contract: simplify the M8–M9 closed loop so it only proves the migration

Read-only session. Verified facts are cited by file. Anything marked (inf) is my inference.

**Steelman.** The interfaces are already proven, each by its own gate:
- KPM uplink: M6/M7 show Influx = IPC.
- RC downlink with C1 determinism: R0 and R1.
- The official TS xApp loop: R2 C1 green (`r2-green`). It covers A1 policy, RMR 30003/30002, rc gRPC, E2SM-RC and the ns-3 handover. Its negative case n2 shows the A1 threshold took effect (`scripts/gates/r2-scenario.json`).

R3 costs the most and tells us the least:
- QP was only ever run on replayed VIAVI data.
- It crashes on our constant DL.
- Its prediction quality is already out of scope.
- The planned R3 would train on a start-up artefact (`brainstorm-261027-2155…qp-training-scenario-fit.md`).

**Critique.** In R2 the decision comes from fixed predictions in the harness stub, not from RAN data. So no rung shows KPM → Influx → xApp decision → RC → handover. That data-driven path is exactly what a TS experiment needs.
- NIST's QP reader uses a wall-clock window, `range(-1600ms)`. Under lock-step pacing that window is meaningless.
- So any data-driven xApp will need sim-time windows. That is a testbed problem, not just a QP problem (inf).

**Also verified:** `goal-packet.md` is LOCKED, and its scope guard pauses on reduced scope (T3). Any simplification therefore has to be a user amendment you record yourself; the agent cannot make it.

## 1. Outcome
One unattended M9 run from `fresh-install` that proves the port:
- M0–M7;
- R0–R2, plus one rung where the handover decision comes from measured data (R3′);
- the top rung's C1 equals the committed reference.

Then docs that tell an experimenter what works and what is fixed. The QP fork and R3-with-QP are deferred, not deleted.

## 2. Constraints
- Never weaken or skip an existing test. R0–R2 C1 evidence stands.
- Free-run stays the default and pacing stays opt-in. M5–M7 stay green after every change.
- Judge on wire bytes, the ledger, traces and digests, never on rc's log.
- Protected snapshots: `fresh-install`, `f7-rerun-green` (and `r3-green` if it is created). The disk watchdog trips at 25 GB.
- Check choices against the specs in Zotero. Write "TS xApp" and "3GPP TS <n>". Markdown only in `plans/` or `docs/`.
- The descoping is recorded as a user decision: a decisions report plus a goal-packet amendment.

## 3. Non-goals
- The QP fork (P7), R3 with real QP, and QP training options B, A, S2 and S3.
- AD and QP prediction quality.
- C1 for future user scenarios.
- Making the harness work with any scenario (next milestone).
- Realism items P1–P7, scenario-one, the default 12-UE config, and leaving NoAuto.

## 4. Acceptance criteria
1. **A fresh green r2 single at the current pins**, after the one guided fix for the A1 type 20008 404 (Codex F06). Gate: `gate-r2-ts-stub-qp.sh --mode single`.
2. **The N4 code is pinned and causes no regression:**
   - V2: with the flag off, the digest is unchanged.
   - V3: passes after the judge is hardened with missing-cell and truncated-tail fail fixtures (F04). Script: `check-pdcp-volume-totals.py`.
   - V4: the m5–r2 chain is green.
3. **R3′ (only if you choose it): C1 pass and ≥ 1 applied handover.**
   - The stub's 30002 values must equal Influx for that trigger's sim-time window, and Influx must equal IPC for the counter it reads.
   - The outcome of each trigger is the same across the 3 runs.
   - This needs a new gate script.
4. **M9′:**
   - Revert `fresh-install`, then `run-to-m9.sh` exits 0.
   - `verdict.json` holds exactly this step set: m0–m7, i0, r0, r1, i2, r2, and r3′ if chosen (no i3).
   - The top rung's C1 equals the reference.
   - `minHostFreeGb` ≥ 25 is recorded and the watchdog is alive. This means making Codex F07 and F08 executable in the runner.
5. **Export fails closed when the scrub fails** (F09), shown by a fixture test of `scrub-evidence.sh` and `vm-exec.sh`.
6. **Records and docs:**
   - The P10 report lists P1–P9, N5 and the descoping (F10).
   - Every verdict carries `substitution3Applied`.
   - Docs are updated and checked against the run log (§7).

## 5. Trade-offs
| | A: stop at R2 | B: R2 + R3′, a stub that answers from Influx (persistence forecast) | C: contract as is (real QP, B+A or S2) |
|---|---|---|---|
| Cost | Lowest: r2 fix, P6 close, P9, P10 | A + about 1 harness gate. No fork, push, image or Testbed pickup (inf: days) | P7 commits 2–5, image, pickup, F03 proof, P8 C1; weeks at the pause rate seen so far |
| Depends most on | "Migration" meaning each interface works on its own | The constant per-cell DL (8371 vs 4186 kbit) differing enough for the TS xApp's 10 % threshold to move a UE | QP being able to train in the image on our data |
| Fails first when | A reviewer or the first experiment asks for a handover driven by live KPM | The dry run shows no handover (vacuous); then fall back to A | The F03 proof or the dry run gives T3; ADF crashes on constant DL |
| Worst case | The first real experiment hits the sim-time and Influx timing gap undocumented | Lose about 1 gate cycle, end at A | Weeks spent proving plumbing behind a meaningless model |

The simplest option that still proves the migration is A. B is the smallest option that also closes the loop through data.

## 6. Better approaches
Better approaches: none — recommended direction is the requested one (QP needs a live-data adapter even at NIST, per its README; R2 C1 already proves the official TS xApp control chain, per `r2-green` and `r2-scenario.json`).

B is a refinement of your idea, not a different one.

## 7. Recommended direction
**B, with A pre-authorized as the fallback if the R3′ dry run is vacuous.**

What happens to each pending item:
- **r2 regression red:** fix it under the existing one-fix budget, with kongming (F06). This is mandatory, because R2 becomes the main proof.
- **P6 N4:** close V1–V4 with the V3 judge hardened (F04).
  - The K18 dump and V5/V6 exist only for QP's window rule, so they become moot.
  - Keep F05's checks for missing seqs, duplicates, and full Influx = IPC equality, but only for the counter R3′ reads.
  - N4 remains an opt-in feature for experimenters.
- **P7 QP fork:** deferred. `381a824` stays local; T8 and F01 become moot. No `QP_URL`/`QP_SHA` in `pins.conf`.
- **P8 R3:** replaced by R3′. Under A it is removed.
- **P9:** freeze the pins without QP, build the dev reference for the top rung, budget for 25 GB plus measured growth (F02), apply F07, F08 and F10, then Stop B.
- **P10 M9:** run the amended step set. Disk should shrink without the QP image (inf; re-measure).
- **The 10 Codex findings:**
  - Accept: F02, F04, F06, F07, F08, F09, F10.
  - Partly accept: F05 (the window predicate is moot).
  - Moot because their scope is deferred: F01, F03. Record them as moot, not rejected.
- **Docs:**
  - `docs/system-architecture-l-release.md` §8 is stale. It still says RC control and pacing are "not implemented".
  - Add a section on running your own experiment, covering:
    - `agents-ns3-run.sh:40` hard-codes the `*-scenario-zero-*` binary;
    - the N5 key is only digits up to cellId ≤ 9;
    - pacing is opt-in;
    - deviations P1–P9;
    - QP/AD cannot use live data without an adapter.
  - Mark P7/P8 in `plan.md` as "deferred by user ruling".

Second-order effects:
- The testbed claims a TS xApp loop that is closed through data, but not one that uses QP. TS experiments that need QP pay the P7 cost later.
- The one-command reproduction from M9 is kept; it is the most valuable "ready-to-use" artifact.

## 8. Unresolved questions
1. A or B? Is a predictor owned by the harness (persistence, read from Influx by sim time) acceptable as the "decision" component?
2. Should the M9 top rung keep its full C1 equal to the reference? I recommend yes; it is already met for R2.
3. Is QP/AD documented as a future milestone ("needs a live-data adapter")?
4. Which comes first in the next milestone: a harness that works with any scenario, a scenario-one smoke run, or realism items P1–P7?
5. Do you approve the wording of the goal-packet amendment?

Files:
- `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/goal-packet.md`
- `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`
- `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/reports/codex-stuck-audit-261027-2058-GH-1-m8-m9-what-did-we-miss.md`
- `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/scripts/gates/r2-scenario.json`
- `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/scripts/gates/agents-ns3-run.sh`
- `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/scripts/run-to-m9.sh`
- `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/docs/system-architecture-l-release.md`

Status: DONE
Summary: Your direction holds. The best version is to stop at R2, plus one rung where the handover decision comes from Influx data (R3′, a harness stub, no QP), with stop-at-R2 pre-authorized as the fallback. P7 is deferred and M9 is redefined.

---

## Verifier caveats on the winner (not fixed in the text above)
1. "`381a824` stays local; T8 and F01 become moot" is false. The commit is pushed on origin `dev/l-release-nist180`, and T8 was released by ruling 6.
2. "M6/M7 show Influx = IPC" overclaims:
   - M6's exit judges only 3 picked samples (`tools/e2-evidence/influx-vs-trace.py:165-184`), and its all-sample comparison is informational (`gate-m6-kpm.sh:147-148`).
   - M7 checks only that rows are present (`gate-m7-multignb.sh:216-217`).
   - The winner omits the runner-up's hardening of this judge (the accepted non-QP part of F05). That hardening should be added.
3. It is internally inconsistent. The Outcome puts R3′ in M9 unconditionally, while AC3 says "only if you choose it". The "Better approaches: none" line is a stretch when R3′ is an addition.
4. Dropping the K18 dump, V5 and V6 must be listed explicitly as a user-ruled scope change, not called "moot".
5. The R3′ acceptance criteria miss two of the Codex skeptic's demands:
   - a controlled change in the observations must change the decision;
   - after the handover, the policy must observe the changed serving-cell membership.

   The cost ("about 1 gate, days") is likely low. R3′ also needs N6 pacer certification, a W calibration, serving-cell, decimal-IMSI and eNB-exclusion logic in the stub, and a Zotero spec check for using per-cell PDCP volume as the predicted throughput.
6. `minHostFreeGb ≥ 25` silently replaces the contract's ≥ 20. It is stricter; tie it explicitly to F02.
7. `gate-r2-ts-stub-qp.sh` has only the `c1|single|calibrate` modes, with no `--reference`. Retargeting M9 to R2 or R3′ needs that flag. This applies to every candidate.

## Debate: the two Codex perspectives
- **Advocate** (`codex-advocate`): end at R2. The bounded claim is: "the pinned ns-O-RAN implementation interoperates with the NIST 1.8.0 / OSC L-release deployment for telemetry and externally controlled EN-DC handovers".
  - Defer P7 and P8.
  - Keep the P9/P10 discipline and C1 for the reference scenario.
  - Replace QP with experiment readiness:
    - a quickstart;
    - a scenario template;
    - **one example where a simple rule consumes live KPM and causes an RC handover**;
    - a matrix of capabilities and limitations.
  - Strongest counterargument it concedes: telemetry and actuation can each work while no policy consumes the telemetry.
- **Skeptic** (`codex-skeptic`): accept simpler decision logic; reject R2 alone as proof of a measurement-driven testbed.
  - R2 injects both the trigger and QP's answer, so sim time vs wall time, serving and neighbour mapping, decimal IMSI, eNB exclusion and DL-first ordering stay unproven on the measurement side. Those concerns apply to any future custom xApp.
  - Keep the pacer, ledger, null control, RIC-free replay, frozen pins, the fresh-install M9, and C1 for the regression fixture.
  - Narrowest acceptable simplification: **defer OSC QP and add a deterministic measurement-driven policy rung** that drives a completed handover, observes the change, and changes its decision when the inputs change. Fix F04–F09 first. Get a fresh green r2.
- **Where they converge:** drop QP training from this goal and keep a measurement-driven decision example. They disagree on whether that example is a gated rung (skeptic) or a documented example (advocate).

## Ranking appendix
| Candidate | Recommendation | Total (of 120) | Decisive notes |
|---|---|---|---|
| D (winner) | Stop at R2 + R3′ (harness predictor reads Influx by sim time); stop-at-R2 pre-authorized as fallback | 101 | Only one that survives both Codex positions (criterion 6: 18) |
| B | Stop at R2; harden the M6 KPM-in judge | 100 | Unique finding: M6 judges 3 samples; does not close the measurement-consumption gap |
| A | Goal 1 ends at R2; QP/R3 move to Goal 2 on varying traffic | 99 | Sharpest runner and verdict criteria; honest "scripted decision source" wording |
| C | R2 at full M9 strength, then X1 scenario-portability smoke | 97 | Densest citations; retires F05 wrongly |
| E | R2 at N4 pins + experimenter docs | 88 | Strawman alternative; ignores the measurement gap |

Verifier confidence: medium. A–D lie within 4 points. If the aim is only migration proof, not experiment readiness, A or B would be equally defensible.

ultra: picked=D/5 margin=low unanimous=no rejected_all=no

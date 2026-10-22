# Ultra verdict: M8–M9 delivery route through `/ak:goal-warmup` + `/goal`

Date: 2026-10-22 21:05 KST. Verifier: kongming on `model: opus` (Opus 5.5, xhigh), as the user's CLAUDE.md requires. The verifier worked read-only apart from this file. Inputs: evidence packet `plans/reports/brief-261022-2054-GH-1-m8-m9-goal-warmup-route-evidence-packet.md`, and the anonymized candidates anon-A … anon-E in the session scratchpad.

## Outcome

**Winner: candidate B.** B is one warmup with one locked contract and one plan, run as three user-started `/goal` segments from one resumable opener, with planned stops after R1 and before M9.

- **Totals:** B 103, D 101 (disqualified), C 100, A 95, E 90.
- **Margin:** low. **Unanimous:** no. **Rejected all:** no.
- **Why B wins:**
  - B is the only candidate that honours every clause of the locked N4 decision. It places N4 after R2, so R0–R2 never wait for it (decision record line 23).
  - B catches that QP needs a UL-on Influx dump. UL-off R1 rows would make the UL series constant, and `adfuller` would raise (decision record line 53).
  - B finds the M9 harness defects, including the one nobody else found: a no-snapshot M9 run has no host-free-space check after M0.
  - B's warmup brief lists the superseded contract text that must not come back.
- **Biggest defects in B:**
  - It has no preflight row for the long run's permission mode.
  - It does not design its stops around how the `/goal` evaluator works.
  - Candidate C covers both of these, and they are raised below as additions.

## 1. Hard constraints

| | H1 locked decisions and rules | H2 warmup gates | H3 secrets | H4 naming | H5 items (a)–(f) | Eligible |
|---|---|---|---|---|---|---|
| A | **Contested.** N4 runs in S0, before R0, so M8 waits for the UL metric. The decision record says "Required by R3; R0–R2 do not wait for it" (`decisions-261022-2013…:23`). A's reason ("so R0–R3 share one image", contract §8.1) is the contract's reason for N5 (`brainstorm-261022-1739…:137`), not for N4. Counted as a pass for scoring. | pass | pass | pass | pass | yes (contested) |
| B | **pass.** N4 sits at P6, after R2 at P5. Each snapshot deletion gets its own `ask_user`. −5 dB is counted first in P2. D7 is reworded. kongming runs on opus. | pass | pass | pass (it only quotes the rule) | pass | **yes** |
| C | pass. Minor: R2 comes after N4. | pass | pass | pass (it only quotes the rule) | pass | yes |
| D | pass. Minor: R2 comes after N4. | pass | pass | **FAIL.** Line 101, inside its Outcome Contract draft, writes the TS xApp fork as a bare "TS" ("kpimon/" + the bare abbreviation + " forks"). That draft would go to the warmup unchanged. | pass | **no** |
| E | pass. Minor: it cites "R0–R2 must not wait" and still orders N4 (P6) before R2 (P7). | pass | pass | pass (it only quotes the rule) | pass | yes |

**Robustness of the pick.** If the user reads decision line 23 as a binding sequencing rule, A fails H1 outright, and C, D and E break it for R2. B is then the only eligible candidate. If the line is read as a plain dependency note, B still has the top eligible total. **B wins under either reading.**

## 2. Scores (1–20 per criterion)

| Criterion | A | B | C | D | E |
|---|---|---|---|---|---|
| 1 Faithfulness to the request and locked scope | 14 | **18** | 15 | 16 | 15 |
| 2 Evidence grounding (true, cited) | 17 | 17 | 17 | **18** | 13 |
| 3 Sharpness of acceptance criteria | 17 | **18** | 16 | 15 | 15 |
| 4 Honesty about unknowns | 16 | 16 | 17 | **18** | 16 |
| 5 Conditional fields (trade-offs, better approaches) | 17 | **18** | 17 | **18** | 17 |
| 6 Operational soundness of the long run | 14 | 16 | **18** | 16 | 14 |
| **Total / 120** | **95** | **103** | **100** | **101** | **90** |

### Rationale by candidate

**A (95).**
- Strengths:
  - Seven source facts, all true.
  - Its `--advice` mapping matches `advice-mode.md:10-16` best: a go/no-go after each phase, a check on any failed Verify, and a review before high-stakes actions.
  - It has a resume opener and a write-before-proceed rule.
  - It is the only candidate to raise the G6 identity question. rc and the TS xApp identify the UE with an NG-style AMF-UE-NGAP-ID in an EN-DC/EPC scenario, which may be a new standards deviation. A labels this as an inference that needs a Zotero check.
- Weaknesses:
  - The N4 placement puts the riskiest unverified item (the per-cell UL PDCP counter in the EN-DC split bearer) on M8's critical path.
  - No permission-mode preflight.
  - It does not engage with how `/goal` evaluates its condition.
  - No disk watchdog for M9.

**B (103).**
- Strengths:
  - It respects N4 ordering. Its regression check is one live run each of R0, R1 and R2 on the new image.
  - It catches the need for a UL-on dump before QP's dry run.
  - It is the only candidate with an M9 disk watchdog.
  - P9 freezes the pins and regenerates the dev reference.
  - It has a phase-exit checklist.
  - Its handoff lists superseded text so it cannot reappear: N4 `RRU.PrbUsedDl` / `DRB.MeanActiveUeDl`, the automatic deletions in contract §8, `control-timer-expired`, and the old D7 wording. All four are verified stale.
  - It verified the ns-3 UL counter lead at the pinned SHA.
  - Its route acceptance items AR1–AR6 are pass/fail.
- Weaknesses:
  - No permission-mode preflight.
  - Its stops are not designed around the `/goal` evaluator.
  - kongming fires only "after two failed attempts". The `--advice` Failure Protocol stops on the first failed Verify.
  - Two claims are overstated (see §7).

**C (100).**
- Strengths:
  - It is the only candidate that checked `/goal` against the official docs, and every mechanics claim is true. It designs a stop clause the evaluator can check from the transcript ("PAUSE <id>"), and acceptance item A5 caps the opener at 4,000 characters.
  - It adds a permission-mode preflight item and a deny rule on snapshot deletion.
  - It records the contract copy into `plan.md` as a warmup decision.
  - It drafts an opener of about 2,000 characters.
- Weaknesses:
  - Its "In scope" pulls in contract §5 and §8 by reference. Those sections still hold superseded text: N4 = `RRU.PrbUsedDl`, checked "on R1's Influx dump", and automatic deletions. The decision record's precedence wins, but this is exactly how C ended up with a QP offline gate "on R1's Influx CSV" (P6) and a dry run on R1/R2 rows (P9). With UL opt-in off by default, those rows have a constant UL series.
  - It misses the M9 snapshot-name collision and the gate-id regex.
  - No M9 disk watchdog.

**D (101, disqualified by H4).**
- Strengths:
  - It is the only candidate to find the UL measName conflict, and it is verified true.
  - It finds all four harness defects and adds the permission row.
  - It proposes an invariants card and moving the design forks into the warmup (`ak-codex-goal/SKILL.md:34-40`, verified).
- Weaknesses:
  - The QP dry run uses R1/R2 rows.
  - Its route acceptance is the weakest.

**E (90).**
- Strengths:
  - It is the only candidate to say that deleting intermediate snapshots frees almost nothing. This is verified.
  - It insists that `r3-green` must exist before the revert to `fresh-install`.
  - It forbids re-running a red C1 until it turns green.
  - It updates the resume block before long VM operations.
- Weaknesses:
  - It misses all four harness defects.
  - "Both precedents copied the contract verbatim" is half false.
  - Its opener ("Pause only at Z1–Z7, and stop when M9 and P11 are done") gives the evaluator no terminal state for a pause.
  - The QP dry run uses R1/R2 rows.

## 3. Ranking

| Rank | Candidate | Total | Note |
|---|---|---|---|
| 1 | **B** | 103 | winner |
| 2 | C | 100 | runner-up among eligible candidates |
| 3 | A | 95 | H1 contested |
| 4 | E | 90 | |
| — | D | 101 | disqualified by H4; would rank second on score |

## 4. Winner rationale

The decisive issues are in the long-run plan itself, because those are hard to repair once the warmup has locked the contract.

- **B places N4 correctly.** No other candidate does.
- **B's QP dry run feeds on UL-on data.** C, D and E would hit `adfuller` on constant UL, and only at run time.
- **B fixes the M9 runner defects.**
  - The `f7-rerun-green` collision: `run-to-m7.sh:44-46` together with `vm-snapshot.sh:33`.
  - The gate-id regex: `vm-exec.sh:29`.
  - The evidence root: `vm-common.sh:14`.
  - A disk check during a no-snapshot M9.
- **B guards the warmup against stale contract text,** through its explicit superseded list.

C's lead lies in how the opener is written and in the permission preflight. Both can be added to B's packet without restructuring it, because the warmup writes the opener and runs the preflight anyway. B's lead, by contrast, would need phase reordering and new phases in C. So B is the safer candidate to emit unchanged with the defects raised separately.

## 5. Margin, unanimity, confidence

- **Margin: low.** B leads the eligible runner-up C by 3 of 120, and D by 2. On criteria 1, 2 and 6 the lead is 51 to 50 over C. Both gaps are far below 30.
- **Unanimous: no.**
  - B tops criteria 1 and 3, and ties D on criterion 5.
  - C tops criterion 6.
  - D tops criteria 2 and 4.
- **Confidence: medium.**
  - B wins under both readings of decision line 23.
  - The B-versus-C call is a trade: B is right about plan content, C is right about `/goal` mechanics. I judged plan-content defects costlier because they cannot be fixed without restructuring the plan.
  - A reviewer who weights criterion 6 above everything else could prefer C.

## 6. Winner defects the controller must raise with the user

1. **There is no permission-mode preflight row.**
   - Every gate starts through `ssh … sudo systemd-run` (`scripts/vm/vm-exec.sh:55`).
   - The classifier refused that call in the rtmgr probe session (`plans/reports/probe-261022-1544-GH-1-rtmgr-route-table-live-dump.md:44`).
   - The `/goal` docs say a goal does not change the permission mode; unattended turns need auto mode.
   - Fix: add C's "must provide" row: allow rules for `vm-exec.sh`, virsh, `ssh oran-kvm-2404` and `git push`.
2. **The stops are not designed around the `/goal` evaluator.**
   - The evaluator is a small fast model that reads only the transcript and calls no tools. The condition is capped at 4,000 characters, and a context overflow that compaction cannot clear also clears the goal (code.claude.com/docs/en/goal).
   - B's Stop A, Stop B and triggers T1–T7 must be terminal states in the condition, or the evaluator will answer "not yet met" and push past a user decision.
   - B's opener ("start or resume at the first phase not marked done") has no stop clause.
   - Fix: adopt C's stop clause (§9 of C): print "PAUSE <id>", its evidence path and its journal path, and start no further work; a pause is neither failure nor completion.
3. **The kongming trigger is weaker than `--advice` requires.**
   - B fires kongming "after two failed attempts on one gate".
   - The `--advice` Failure Protocol says to STOP and consult kongming on the first failed Verify (`~/.claude/skills/ak-plan/references/advice-handover-plan.md:79-97`).
   - `advice-mode.md:10-12` adds a go/no-go after each phase.
   - Fix: use A's mapping.
4. **The UL measName conflict is missing.**
   - `DRB.PdcpSduVolumeUL_Filter` contains `_`. The agent's metric-map lint forbids that: "PrintableString-legal (no '_')" at `ns3_e2_agent/tests/lint-metric-map.py:10`, with the regex at `:32`.
   - The existing map drops `_Filter`: `QosFlow.PdcpPduVolumeDL` with legacyName `QosFlow.PdcpPduVolumeDL_Filter`, at `ns3_e2_agent/schema/metric-map.v1.json:33`.
   - E2SM-KPM's `MeasurementTypeName` is a PrintableString (decision record line 60).
   - Fix: add it to B's "resolve during warmup planning" list as a spec-backed choice (D).
5. **Stop B's deletion menu over-promises.** B's unresolved Q6 offers `f7-rerun-green`, `r0-green` and `r2-green` as deletion candidates. The P5 housekeeping README says deleting intermediate external snapshots "frees almost nothing" and needs temporary space equal to each overlay. Show the user that before any disk ruling (E).
6. **Two of B's harness claims are overstated; the fixes stay the same.**
   - "A no-snapshot run checks free disk nowhere": `gate-m0-host.sh:33` checks once, at M0. Nothing checks again during the run, so the watchdog is still needed.
   - "`vm-common.sh:14` hard-codes the evidence root": it is a default that the environment can override.
7. **The P0 decoder test depends on a host-only file.** It round-trips `evidence/rc-control-latency/20261022T025759Z/rclat.pcap`, which exists on the host but is gitignored. It is a host-only dev check and cannot run from git or inside M9.
8. **The spec gaps are inferences.** "E2SM-RC v02.00 and E2SM-KPM v03.00 are likely missing" comes from the packet's list, not from a Zotero query. The warmup must confirm it through zotero-mcp.
9. **One unresolved question is not a user decision.** B's Q8 (did M0–M7 resume in the same session?) should be answered from the records or dropped.
10. **The handoff has a placeholder.** It names `plans/reports/brainstormer-<this-run>-…`. The controller must substitute the committed path, and commit the locked inputs first, which B itself lists as a must-provide item.

## 7. Spot-checks

### Verified true

| Claim (source letter) | Evidence |
|---|---|
| M9 with prefix `f` dies at the M7 boundary (A, B, D) | `scripts/run-to-m7.sh:44` forces `f7-rerun-green`. `:45` creates it even with `--no-snapshots`. `scripts/vm/vm-snapshot.sh:33` dies when the name exists, and the snapshot exists (packet §5). |
| The gate-id regex (A, B, D) | `scripts/vm/vm-exec.sh:29` runs `sed -E 's/^gate-(m[0-9]+).*/\1/'`. Several `gate-m8-*` scripts would share `.last-m8` (`vm-exec.sh:88`, `run-to-m7.sh:60-61`). An `r0` name does not match, so the gate id becomes the whole file name. |
| The evidence root (A, B, C, D) | `scripts/vm/vm-common.sh:14` defaults to `plans/261021-1823-…/evidence`. The environment can override it. |
| The delete guard (C, D) | `scripts/vm/vm-snapshot.sh:62-67` refuses only `fresh-install`. There is no approval guard. |
| No mid-run host check without snapshots (B, with the caveat in §6) | The only host checks are `vm-snapshot.sh:34-36` and `gate-m0-host.sh:33`. |
| The UL measName conflict (D) | `lint-metric-map.py:10,32` and `metric-map.v1.json:33` in the Testbed worktree, at `725b167` = `pins.conf:7`. |
| The `/goal` mechanics (C) | Fetched from code.claude.com/docs/en/goal: 4,000 characters; the evaluator is a small fast model with no tools that judges from the transcript; a new goal replaces the old one; an overflow that compaction cannot clear clears the goal; the goal is restored on `--continue`/`--resume`; a goal does not change the permission mode (auto mode is needed); it is unavailable when `disableAllHooks` is set; check-ins start at 30 minutes; automatic retry or pause needs v2.1.269+. |
| The classifier refused `systemd-run` (C, D, E) | `probe-261022-1544…:44` |
| kongming's model routing (A, C) | `~/.claude/agents/kongming.md:8-9` sets opus/xhigh. `ak-brainstorm/references/advisory-supervision.md:17,44` still says fable. |
| What the warmup skill parses and stores (A, C, D) | `ak-goal-warmup/SKILL.md:8`: the argument hint lists only `--fast`. `:103`: contract state is session + handoff only. `references/outcome-contract.md:41`. |
| The Failure Protocol and advice checkpoints (A, C) | `ak-plan/references/advice-handover-plan.md:79-97`; `ak-brainstorm/references/advice-mode.md:10-16`; `ak-plan/SKILL.md:8,47` (`ak:plan` accepts `--advice`). |
| ns-3 UL lead (B) | At `ace32168`, `mmwave-enb-net-device.cc` about `:648-670` sums the DL cell volume with `GetDlTxData(imsi,3)`. `mmwave-bearer-stats-calculator.h:250` declares `GetUlRxData`; `:306` declares `GetDlTxData`. |
| Fork state (A, D) | `git ls-remote`: the QP fork has no `dev/l-release-nist180` and `master` = `47a35ca`. The heads of Testbed, ns-3, oran-interface and e2sim equal `pins.conf`. `gh`: the parent repo is PUBLIC. |
| zotero is configured (A) | It is the only user-scope MCP server. Only key names were read. |
| Deleting intermediate snapshots frees almost nothing (E) | `plans/261022-1026-…/evidence/p5-snapshot-housekeeping/20261022T030653Z/README.md`, "Lesson" paragraph. The chain is 39.7 GB. |
| The superseded text (B) | `brief-261022-1713…:14`: `control-timer-expired` was wrong. Contract `:102-104` (N4 U2 and the `DRB.MeanActiveUeDl` fallback). Contract `:140-141` (automatic deletions). |
| Timing of the TS xApp stray-ack probe (all) | kongming Q4 says "before R2" (`kongming-261022-1739…:109`), and §4 says "first RIC-facing phase" (`:152`). Both placements are supported. |
| asn1c pin `584d86e` (B) | It appears in `docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md` and `docs/system-architecture-l-release.md`. |

### Falsified or inaccurate

| Claim (source letter) | Finding |
|---|---|
| "plan.md holds the locked contract verbatim, as both precedents did" (E) | Half false. The pacing-gate `plan.md:12-48` restates it, but the M0–M7 `plan.md:11` reads "Locked outcome (summary; full contract in the goal packet)". |
| "N4 in S0 so R0–R3 share one image (contract §8.1)" (A) | Misattributed. §8.1's one-image reason is for N5 (`:137`), and decision line 23 says R0–R2 do not wait for N4. |
| QP offline gate or dry run on R1 (or R1/R2) rows (C, D, E) | This wording predates N4 (contract §8.5, §9). With UL opt-in and off by default, those rows have a constant UL series, and `adfuller` raises (decision record line 53). A and B caught it. |
| "R0–R2 must not wait for it" (E) | E cites the rule and orders N4 (P6) before R2 (P7). C and D use the same order without the citation. |
| Off-by-one citations (A, C) | Trivial. `vm-exec.sh:13` should be `:14` (A). `decisions.md:9` should be `:8` (C). |

## 8. Optional additions from losing candidates (offer separately; do not merge into B)

- **C:**
  - The evaluator-checkable stop clause and its draft opener of about 2,000 characters (its §9).
  - Route acceptance A5: the opener stays under 4,000 characters and contains a stop clause.
  - The permission-mode preflight item.
  - W3, a permission deny rule for `vm-snapshot.sh delete` and `virsh … snapshot-delete` in the `/goal` session.
  - W1: record the contract copy in `plan.md` as a warmup decision, because it departs from the default at `SKILL.md:103`.
  - A preflight check of the Claude Code version and `disableAllHooks`.
- **D:**
  - The UL measName choice: drop `_Filter`, following `metric-map.v1.json:33`, or another spec-backed encoding.
  - Whether kpimon carries the new cell row without code changes. If it needs them, that is a possible outcome-change request, because it widens the locked SIZE(8)-only patch scope.
  - An invariants card in `plan.md`: raw 5 bytes, eNB keeps `reqpart`, uppercase `cellKey`, decimal-IMSI `ue-id`, Format 1 on every ACK, never rc's log, never delete a snapshot, −5 dB first.
  - Moving the open design forks into warmup planning (`ak-codex-goal/SKILL.md:34-40`).
- **A:**
  - The G6 UE-identity question as a "should decide" item. It is an inference and needs a check of the E2SM UE ID choices for EN-DC.
  - "kongming counsel never counts as user approval."
  - A policy for re-running a failed C1 set: at most one re-run after the root cause is recorded.
  - The `--advice` mapping aligned with `advice-mode.md`.
- **E:**
  - `r3-green` must exist before P10 reverts to `fresh-install`, because a revert discards the active overlay.
  - Update the resume block before any VM operation longer than 10 minutes, and on resume verify `virsh domstate` and `snapshot-current` before acting.
  - Never re-run a red repeat gate to get green.
  - Exactly one session owns the VM.

## Unresolved questions

1. Is decision record line 23 ("R0–R2 do not wait for it") a binding sequencing rule or a dependency note? The answer decides whether A, C, D and E breach H1. It does not change the winner.
2. Did the M0–M7 `/goal` session run in auto mode with allow rules for `vm-exec.sh`? If so, defect 1 is a quick confirmation rather than a blocker.
3. Should defects 1 and 2 be given to the warmup as inputs alongside B, or raised with the user first? B is emitted unchanged either way.

ultra: picked=B margin=low unanimous=no rejected_all=no

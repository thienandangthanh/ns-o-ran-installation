# kongming: P10 (M9) phase exit and goal go/no-go (amendment A1)

- Date: 2026-10-29 ~05:50 KST. Reviewer: kongming on Opus 5.5 (caller-pinned `model: opus`). Advisory only; never user approval.
- Scope: plan.md phase-exit checklist items 1 and 8 for P10, plus the goal-level scope guard against the LOCKED contract A1 (`goal-packet.md`). Read-only: no VM, host or git changes, no Codex.

## Verdict

**GO: declare `GOAL DONE M9`** once the closing records commit below has been made (2 must-do items, about 10 minutes, records only). Neither item is a PAUSE trigger. Nothing calls for a re-run, a VM operation or a user ruling. No T3 mismatch was found.

## TL;DR

Every M9 signal holds on the committed evidence and on independent re-checks: exit 0, exact step set, 14/14 pass, pins equal to the remote heads, R3′ c1 all true and `equalsReference: true` against an unchanged reference, min free 59 GiB, a live watchdog, and no trip files. The A1 deliverables 1–9 are all present. F″ fits within the Failure Protocol. The only real defect is in the records: the run report cites the wrong source for V1, and the true source sits in volatile `/tmp`.

## 1. V1–V5 as mapped (phase-10 Stop B mapping :73–90, F″ addendum :99–103)

| Signal | Evidence (verified) | Result |
|---|---|---|
| V1 exit 0 | Client: `tasks/bicn5cb5m.output` tail shows `Finished with result: success`, `status=0/SUCCESS`, `M9 CLIENT EXIT rc=0`. Unit journal: no `Main process exited` or `Failed with result` line, where attempt 3's `unit-journal.txt` has both. `runner.log` ends `M9 verdict: PASS` | pass. **Records defect, see must-do 1** |
| V2 | `verdict.json`: `expectedSteps` = m0..m7 i0 r0 r1 i2 r2 r3p; `exactStepSet: true`, `notM9: false`, 14× `pass: true`, `problems: []`; every step and the top level carry `pins`, and these equal `scripts/pins.conf` and `git ls-remote` heads (c6d1434a, ba954440, 96efc40e, 2209995a) | pass |
| V3 | `highestGreenRung: r3p`, `substitution4: false`; the r3p gate verdict has `mode: c1`, `c1` {liveRunsEqual, replayEqual, rngRun2Differs} all true, `equalsReference: true`, `referenceDir` `reference/r3p`; `git diff e0a6ac5 HEAD -- reference/` is empty | pass |
| V4 | `minHostFreeGb: 59` ≥ 25; `watchdogAlive` intervalS 30, maxAgeS 30 ≤ 60; `lastCheckEpoch` 1793219319 is 29 s before the end (1793219348); `free-series.tsv` 421 samples, max gap 41 s, min 59; no tripped, lost, wall-deadline or monitor-lost file in the run dir (only attempt 1's dir has `watchdog-lost.json`) | pass |
| V5 | Run report: P1–P9 and N5 at :60–69; Q2 = 5 at :72; substitutions 1–4 at :84–87; S1–S3 at :76–78; bring-up remedies at :49–54. That last table matches the evidence: the only `ric refresh` pair is in `m1/20261028T170205Z/watchdog.log`, and there is no `agents-ready-remedy*` in any step dir | pass (accuracy nits: should-do 1–4) |

## 2. Contract A1 in-scope items 1–9 (goal-packet.md:10–18)

All delivered:
- Items 1, 2 and 6 were done in earlier phases.
- Item 3: verdict fields and the fail-closed runner.
- Item 4: P6 done.
- Item 5: r3p reports `predictorDrivenApplied` 1/1/1 and an `observationChange` n1→handover, h1→none.
- Item 7: `restartCountsAllZero` true on r0–r3p, start and end route tables, `routeOwner12041/12042`.
- Item 9: both Codex ledgers end `Status: complete`.

Item 8, docs checked directly:
- The stale §8 line ("RIC Control and M8 … nothing implements it", f9c2d81) is gone. §8 is now the RC path, pacing, UL/DL rows and the R3′ predictor (`docs/system-architecture-l-release.md:141–176`).
- "Run your own experiment" §11 (`:194–205`) names `agents-ns3-run.sh:40` (verified: that is the `find … '*-scenario-zero-*'` line), the scenario-zero-only globals, the N5 key limit for IDs ≤ 9, opt-in pacing and the QP/AD live-data adapter.
- The deployment guide has run-to-m9 (`:68–87`), the manual rc loop (`:273–298`), the TS xApp loop (`:300–327`) and the scope statement (`:87`). The commands I spot-checked against the scripts match: the `rc-send.sh` arg order, the `pacer.py` flags, `send-rmr.sh … anomaly`, the stub `PUT /table` on :8080, the A1 path and the service names. The hand loops are honestly marked "(unverified as a hand run)". They derive from gate code that M9 ran green, so this meets "verified against the M9 log".
- `901f8c5` → `381a824`: the phase-07/08 banners and the T8 journal :78 have been updated, and the remaining hits are dated historical reports.
- Every verdict carries `substitution3Applied` under interpretation (i). A journal exists for each of the 10 pauses. Each phase file has a standards ledger.

## 3. F″ within the contract and the Failure Protocol

- Budget: the goal was re-issued 22:43 KST after T8 (resume card). Attempt 3's m6 went red, and the guided fix F″ was the first fix since that re-issue. Counsel kongming-261029-0100 led to ce86613; review kongming-261029-0135 (GO) led to the final 39b3ba2. It was validated on the wedged VM (`plans/261021-…/evidence/m6/20261028T164804Z`: refresh pair, pass). One Verify re-run followed (attempt 4) and was green. This fits phase-10 :45 and the standing ruling (plan.md T6).
- Codex: cap reached. The spare run was consumed by accident; that is disclosed in `docs/journals/2026-10-28-m8-m9-p10-pause-t1-leaked-overlay.md:10`. kongming reviewed F″ (CX-1).
- The reference stands. F′..F″ touches only `scripts/gates/{agents,bringup,rc-lib}.sh`, and F″..HEAD is empty for scripts/tools/reference.
- One caveat to keep disclosed, not reversed: the remedy fired in **m1**, right after the fresh RIC install. `ricplt_stable_10min` then measured the replaced pods (baseline 0, 10 samples). That is consistent with the bounded, pre-judgment remedy, like NIST's e2term watchdog, so it is not T5. It does make handoff follow-up 4 (root-cause the reader wedge) the top post-goal item.

## 4. Invariants and the snapshot rule

- The snapshot tree is fresh-install > f7-rerun-green > r0-green > r2-green > r3p-green, plus m0-probe-n/o/p/q. The probe q is the run's own allowed probe.
- The protected probe data files `ubuntu24.1793195253` and `…186494` are still present.
- Leaked overlay deletions: `…186558` and `…195425`, each logged with checks 1–5 (`evidence/p10-disk/20261028T134728Z`, `…165516Z`, both committed).
- There are no host orphans: no runner, watchdog or vm-exec process, and no `m9-*` unit.

## 5. Writing rules

There is no bare "TS" in the run report, handoff, journal, README, either docs file, or the lines 86d274d added to implementation-notes/phase-10. A PCRE scan found 0 hits.

## Must-do before printing GOAL DONE (records only; not PAUSE triggers)

1. **Make V1 durable and correctly cited.** `plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md:12` cites `unit-journal.txt` for `Result=success`, `ExecMainStatus=0`, but that file holds neither value. `systemctl --user show m9-q.service` now returns `LoadState=not-found`, and its other fields are defaults, not evidence.
   - Copy the client tail (the 6 lines from `Running as unit` to `M9 CLIENT EXIT rc=0`) from `/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/d8d75ba4-1960-4c73-8e26-fad9eabff481/tasks/bicn5cb5m.output` to `evidence/m9/20261028T165825Z/client-exit.txt`. `/tmp` is session-volatile.
   - Change :12 to cite that file, plus the journal's lack of failure lines compared with attempt 3.
2. **Checklist item 8 record.** Add this report's path to the resume card (`plan.md:26`) and to implementation-notes. Commit this report with them and push.

## Should-do (same commit, optional)

1. Run report :65, P6 row: add "MAC-sourced". This is the contract's definition (`goal-packet.md:19`; source `decisions-261022-2013…md:164`), and the row currently omits the part that actually deviates.
2. Run report :89–103: the labels no longer match Stop B §4 (`docs/journals/2026-10-28-m8-m9-stop-b.md:68–80`). Item 10 says "(j)" but is Stop B's (k), and Stop B's (j) (record slips) is missing. Also drop the blank lines at :70, :92–93 and :104.
3. Run report :113: say the spare Codex run was consumed by accident (see the T1 journal :10).
4. Run report :45: r0 and r1 have no TS xApp or stub QP (their `restartCounts` keys are agents, hw-go, kpimon and rc). Say "for the pods in each rung's path".
5. Commit the modified `.last-*` pointers and `evidence/watchdog/min-host-free-gb.txt`, and commit or delete the untracked `plans/reports/docs-manager-261028-1830-GH-1-m9-docs-draft.md`. Add files selectively only; never force-add the untracked raw validation files. The f2138f0 slip must not repeat.

## What to avoid

- Running `systemctl --user show` on a GC'd transient unit as success evidence. It returns defaults.
- Ratifying the A1 interpretations on the user's behalf. Re-issuing the goal after Stop B is not an explicit ruling. They don't block GOAL DONE, because none weakens a signal:
  - (a) and (h) are stricter.
  - (b) is prediction quality, out of scope at `goal-packet.md:19`.
  - (c) has the same N.
  - (d) is dominated by W's 1 s floor (L_max 5.4 ms).
  - (f) is "recorded" per the contract.
  - (g): pins.conf governs (`goal-packet.md:8`).
  - (i): the TS xApp is absent before i2, so `null` is truthful.
  - (k) is a mapping.
  - They stay listed as unresolved.
- Any VM revert, overlay deletion or `r3p-green` deletion as part of closing. The leak is handoff follow-up 2 and is out of scope now.
- Any tool call after the final line. Print the verdict summary (exit 0, exactStepSet, 14/14, highestGreenRung r3p, c1 all true, equalsReference true, minHostFreeGb 59, watchdog alive) in the same final message, then end with exactly `GOAL DONE M9 verdict=plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/verdict.json` (K21).

## Assumptions

- The task output file is the `systemd-run --wait` client of `m9-q`. Confidence: high (same runtime, 3h 30min 43.357s, as the journal). If it is lost before the copy, cite the journal comparison alone and say the client rc is recorded only in the transcript.
- The precheck order in the code (unknown IMSI, unknown target, in handover, already on target, LTE fallback; `lte-enb-rrc.cc` at ba954440) differs from the order listed in the contract sentence. I treat that list as a set that was accepted at P1, not a sequence spec. Confidence: medium-high. The docs match the code.

## Unresolved questions (user)

1. Explicit ratification of A1 interpretations (a)–(k) (Stop B §4).
2. The f2138f0 history rewrite (handoff :25).
3. Which handoff follow-ups (:19–24) go into the next goal's contract. Reader-wedge root cause and the revertDisks leak first.

Status: DONE
Summary: GO for GOAL DONE M9 after a records-only closing commit (archive the V1 client exit, fix the run-report :12 citation, record this report); no PAUSE trigger, no T3 mismatch.

# P9 harness side: en-gNB X2 PDCP SDU volume counters (2026-11-07 13:33 KST)

Status: DONE_WITH_CONCERNS. Uncommitted in the worktree. No VM, pins.conf or submodule tree touched.

## Outcome
- `bash scripts/gates/lint.sh` exits 0 ("lint: ok"). The ns-3 source lint still reads 4318e43b, as expected.
- The new judge self-test passes all 47 fixtures. Each fixture asserts the **exact set** of false conjuncts, not just pass/fail.
- The judge FAILS on the archived pre-P9 ulon run (today's behaviour fails).

## Files (lines +/−)
- `scripts/gates/check-pdcp-volume-totals.py` (+208/−176, 317 lines). The new judge.
- `scripts/gates/check-pdcp-volume-totals-fixtures.py` (new, 147 lines). The fixtures and the self-test, split out on the r3p-checks-fixtures precedent. `--self-test` loads it, so no new lint wiring was needed.
- `scripts/gates/gate-n4-ul-metric.sh` (+30/−14). `--part v3`, `cal_ok` matches `^N4AUDIT v2`, and the `v3()` key list.
- `scripts/gates/n4-run-byte-identity.py` (+4/−4). HDR is `v2`. Its self-test stdout now uses v2 lines (header token, plus a trailing leg on ulrx/dltx).
- Row 152:
  - `r3p-scenario.json` (:2 field and §5.1.2.1.1.2, :8, :9, :13, :29);
  - `r3p-predictor.py:6`, `n6-fixtures.py:10`, `r3p-checks-fixtures.py:15`;
  - `check-n4-v5-windows.py:7,29,30`, `gate-r3p-ts-predictor.sh:3`;
  - `digest-run.py` (four-key drop), `n4-drop-selftest.py`.
- `r3p-schedule.json:2` and `r3p-stage-a.json:58`: `scenarioSha256` changes from 392feefc… to `8ac00477e38f41f9524c577aad9a79b09d27513b8d9a1d2293a83facc02755d9`. Byte-verified that nothing else changed (HEAD copy with the sha swapped is identical to the new file).
- `scripts/gates/gate-m4-ns3-build.sh` (+4). Adds `m4_ns3_epc_x2_mc_pdcp_volume_suite_passes`, which runs `ns3_suite_passes epc-x2-mc-pdcp-volume`.
- `evidence/p10-chain/p10-gate-chain.sh` (+2). Step 14 `n4|gate-n4-ul-metric.sh|3600|--part v3`, plus a header line describing it.

## Judge (per the Row 151 amendment)
- **A1, line forms.** Each `N4AUDIT*` line must fully match one of the six regex forms. Numbers are `0|[1-9][0-9]*`, so a negative, a float or a leading zero is malformed. The run needs exactly one v2 header and exactly one end line.
- **A4, per cell.** Truth for each cell is computed over its x2dl/x2ul lines between that cell's own reads, with no LCID filter. Tolerances are 500 bits per sample and 1 kbit per cell for the period sum. Ties fail. Residual bits are allowed only after the run's final read; bits after a cell's last read that is not the final read are counted as `residualBeforeFinalReadBits` and fail A4. Any `badCellRefs` also fails A4.
- **A6.** Needs an LTE-leg lcid-3 dltx, an X2-leg lcid-3 dltx, and at least one x2ul.
- **A7.** Both own keys must be the int 0.
- **A8, inclusion form.** For each pair (MN cell m, gNB cell g):
  - x2dl(g, src m) ⊆ dltx(m, leg g);
  - dltx(m, leg g, tNs ≤ T−2 ms) ⊆ x2dl(g, src m);
  - ulrx(m, leg g) ⊆ x2ul(g, dst m);
  - x2ul(g, dst m, tNs ≤ T−2 ms) ⊆ ulrx(m, leg g).

  The sender events after T−2 ms are reported as `lateSenderEvents`. T is `--sim-time-s`.
- **Verdict fields.** Same as counsel §4, with `overlaps`, `unverifiedResidualBits`, `events` and `perUeUlPdusPerPeriod` removed (the last one depended on UE-list ownership).
- **Non-vacuity check.** I made four one-line mutations of the judge: A8 forced true, forwarded x2dl dropped from truth, the per-sample A4 check removed, and the in-flight exclusion removed. Each one turned the self-test red: 5, 2, 3 and 1 cases respectively.

## Evidence
Judge on the archived pre-P9 ulon run `evidence/n4/20261107T030354Z/runs/ulon` (`--sim-time-s 10`), exit 1:
```
pass False | a0 True a1 False a2 False a3 True a4 False a5 False a6 False a7 False a8 True
auditVersion v1, headerLines 0, malformedAuditLines 123795, mnEvents 0, x2Events 0, x2ulEvents 0,
legCounts {lte 0, x2 0}, ownPdcpNonZeroSamples 196, nonIntCounters 400
```
The old judge passed this same run (a0–a5 true, perCellMaxErrBits 496).

Self-tests:
- check-pdcp-volume-totals: "PDCP volume audit judge self-test: ok" (47/47).
- n4-drop-selftest: 13/13 ok. New cases: a missing X2 key, DL ≠ 0, X2UL = 1, X2DL never positive, X2DL float, DL float 0.0.
- n4-run-byte-identity: "self-test: ok (37 fixtures)".
- check-n4-v5-windows: exit 0.
- r3p-predictor, check-n6-influx-window, r3p-dry-run-classifier, r3p-checks, reference-compare and reference-transform-compare: all ok.

Full lint output:
```
ns-3 source lint on ns-3-mmwave-oran@4318e43b: 2799 files, ok
gate ids: m5 r0 s1 q7 r3p
self-test rotation: rc 0, indications 5 (want 5), WMORE 1 (want 1), rotations 1 (want 1)
self-test uncovered start: rc 3 (want 3)
pod-log-window self-test: ok
SKIP selftest-records: ... SKIP selftest: ...   (pre-existing skips, same as the baseline)
lint: ok
```
- `python3 -m py_compile` passes on all 9 edited or new Python files.
- shellcheck is clean on the edited gate scripts.
- `p10-gate-chain.sh` has two SC2034 warnings (`ref`, `m9ref`). Both exist at HEAD, and the file is outside lint's shellcheck scope.

## Choices beyond the letter of the spec (all stricter, none weakens a check)
- A8 is paired per (m, g). This is the same as pooling over M when there is one MN, which is today's topology.
- A dltx/ulrx at a cell in G counts as a badCellRef, because classifying forwarded events needs M and G to be disjoint.
- `--part v3` runs uloff/ulon with the rung-config RngRun (`RUN_RNG`). Full mode keeps `--RngRun=1`, so its arguments and predicates are byte-for-byte the same.
- The `n4Drop` report renames `ulNonZero`→`nonZero` (per key) and `dlPositiveByNode`→`x2dlPositiveByNode`. The gate only prints these fields.

## Concerns
- `gate-n4-ul-metric.sh` full mode now runs the four-key drop, as row 152 (b) requires. Its V2 against K19 is already red by design, and nothing new is lost.
- The identity part's `id_audit` still prints only a0–a5. It would still work, but identity is not a P9 gate, so I left it.
- `lint.sh:58` runs the Testbed `lint-metric-map.py` self-test from the parallel implementer's tree. It passed during my run, but a later run depends on their state.

## Unresolved questions
- Should `n4-run-byte-identity.py`'s ulon precondition also require at least one x2dl and one x2ul line? It currently counts ulrx, dltx and end only. Adding them would change a predicate, which no row registers, so I did not.

## Codex fix (2026-11-07, A0 read cadence)

Finding: A0 never validated `simTimeNs`. With every sample at t = 0 and every X2 counter at 0, all events became residual and the judge passed. The finding was reproduced.

Fix: A0 now also checks the read cadence of every gNB trace.
- `simTimeNs(seq k)` must equal `simTimeNs(seq 0) + k × that trace's hello periodNs`.
- `0 < simTimeNs(seq 0) < periodNs`.
- The trace must have one valid int period and one valid int seq-0 instant.

A trace that breaks the rule is listed in the new verdict field `offCadence` (`{node: {periodNs, seq0Ns, offCadenceSamples}}`). The docstring states the rule.

Fixtures:
- One existing fixture, "an x2 event after its cell's last read, which is not the run's final read", moved only one of node 3's reads. That breaks cadence. Both of node 3's reads now move by −0.1 ms, so it stays on cadence and still fails A4 alone.
- New must-fail fixtures:

| Fixture | False conjuncts |
|---|---|
| collapsed read instants with zero counters (the Codex reproduction) | {a0} |
| one read off cadence (+1 ns) | {a0} |
| seq 0 read at sim time 0 | {a0} |
| seq 0 read at the period | {a0, a4} |

Non-vacuity: with the cadence conjunct removed, the self-test goes red on exactly these four fixtures, and the Codex case passes the judge again.

Results:
- Judge self-test: "PDCP volume audit judge self-test: ok", 51/51. The healthy pass fixtures are unchanged and pass.
- Archived pre-P9 ulon run `evidence/n4/20261107T030354Z/runs/ulon`: still exit 1.
  - `pass False`; a1, a2, a4, a5, a6 and a7 are false; malformedAuditLines is 123795.
  - Its real traces are on cadence: `offCadence {}`, a0 True.
- py_compile: ok on both judge files.
- The other self-tests I own all exit 0: n4-drop, byte-identity, V5, r3p-predictor, r3p-checks, n6 and digest-run.

lint.sh: exits 1, but only on a step outside my files.
- The failing step is `lint.sh:58`, "metric-map strict lint self-test failed". It runs from the parallel implementer's uncommitted O-RAN-Testbed-Automation tree, where `lint-metric-map.py`, its self-test, `metric-map.v1.json` and `kpm-measurement-clauses.v1.json` are modified.
- The lint reports that registry entries 7–10 (DRB.PdcpSduVolumeDL, UL, X2UL, X2DL) have no value-check sources in the form `<repo>@<sha> <file>:<line>`. That fits the ns-3 commit SHA not existing yet.
- Every other lint step passed (ns-3 source lint ok, gate ids, rotation, pod-log-window, the two pre-existing SKIPs).
- My first lint run, before the Testbed edits landed, ended "lint: ok".

Unresolved: the ledger block that registers this fix, "Row 151, amended before code, continued", is not in the worktree or at HEAD 86faad5d. I implemented the rule as the coordinator's message states it.
(Update: the block is now committed, 25894695.)

### Follow-up review fixes (spec: the "Follow-up review" bullet of the same block)

1. **Audit events must lie inside the run (high).**
   - Every dltx, ulrx, x2dl and x2ul event must satisfy 0 < tNs ≤ T, where T is the `--sim-time-s` stop.
   - Events outside that range are counted in the new verdict field `outOfRunEvents`, and they fail **A1**. A1 is the audit's validity judge, so the run fails whatever the counters say.
   - A4 skips these events, so its residual now means only x2 events in (final read, T].
2. **Every hello's period must be a positive int (medium).**
   - Each gNB hello line is checked on its own, before any merging: `periodNs` must be a JSON int greater than 0, not a bool and not an equal-valued float.
   - Each bad hello is recorded in the new field `invalidHelloPeriods` (`[{trace, periodNs}]`), and **A0** fails.
   - `expected_from_config` applies the same check per hello before it merges periods, so the CLI path returns n_seq 0, which fails A0.

**New fixtures.** Each one names the exact set of conjuncts that must be false.

| Fixture | Must be false |
|---|---|
| every audit event shifted 1 s past the stop, zero X2 counters (Codex reproduction) | {a1} |
| an audit event at sim time 0 | {a1} |
| an int hello followed by an equal-valued float hello (Codex reproduction) | {a0} |
| a hello period that is a bool | {a0} |
| a UL PDU sent at the stop instant (t = T is inside the run) | none, must pass |

**Mutation checks.**
- Without the out-of-run rule, both a1 fixtures go red.
- Without the per-hello check, both a0 fixtures go red.

**CLI runs (`--sim-time-s 0.2`).**

| Fixture | Exit | Key fields |
|---|---|---|
| healthy | 0 | |
| float hello | 1 | a0 false, expectedSeqsPerNode 0, invalidHelloPeriods names e2-ipc-trace-2.jsonl / 100000000.0 |
| shifted | 1 | a1 false, outOfRunEvents 11, residualBits 0 |

**Results.**
- Judge self-test: "PDCP volume audit judge self-test: ok", 56/56. All healthy fixtures pass.
- Archived pre-P9 ulon run: still exit 1, `pass False`, outOfRunEvents 0, offCadence {}, invalidHelloPeriods [].
- py_compile: ok on both judge files.
- `lint.sh`: exits 1, with the same single red as before, `lint.sh:58` "metric-map strict lint self-test failed". That self-test runs from the parallel implementer's uncommitted O-RAN-Testbed-Automation tree. Every other lint step passed.

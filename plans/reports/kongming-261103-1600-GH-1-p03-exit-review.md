# kongming: P03 exit review (P12 KPM period/granularity, AC10 + AC8 run 2)

Date: 2026-11-03 ~16:00 KST. Model: Opus 5.5, per the user's CLAUDE.md override (not `fable`). Advisory only: no code, plan, evidence or VM touched. Local probes ran in the scratchpad only.

## Verdict: GO-WITH-CHANGES

**TL;DR.**
- AC10 (option B, no SUB-P12) and AC8 run 2 are met on the evidence.
- The row-59 judge fix reads the agent and E2SM-KPM Format 2 correctly. Standalone it is laxer than the old judge in one input class, but the gate as a whole is not, because `influx-vs-trace --every-seq` covers that class.
- Resuming at p12 with M3–M5 kept from b71ad2c is sound. The ordering slip was real (the ledger row was committed 63 s after the p12 run at 83443e1 had started) but it is not material.
- **One must: tag `m10-cp1` only after the extended seam smoke passes at the pins.** The tag cannot be moved.

## Q1. Are AC10 and AC8 run 2 met? Are any validation fields missing?

**AC10 is met.** Each clause of the contract, with its evidence (contract §3 AC10):

| Contract clause | Evidence |
|---|---|
| Period and granularity configurable | `p12_{a,b,c}_kpimon_config_carries_p{1000,150,100}_g100` pass in `evidence/p12/20261103T054241Z/checks/` |
| Gated rungs at 100/100 | `r3p_live{1,2,3}_kpimon_subscription_reporting_period_decoded` pass in `evidence/r3p/20261103T063029Z/checks.jsonl` |
| One indication per 10 seqs, 10 records | `p12_a_one_indication_per_10_seqs_with_10_records.out`: 10 F1 + 10 F2, 100 seqs covered, `measDataItemsHistogram {"10": 20}`, 0 problems |
| Influx = IPC for every seq | `p12_a_influx_equals_ipc_trace_every_seq.out`: 100/100 samples complete, 14,694 fields, 0 differ, UE rows 193 = 193 |
| kpimon decodes multi-record | `p12_a_kpimon_logged_every_wire_indication_zero_wmore`: 20/20, RC_WMORE 0/0 |
| Not-multiple period → not admitted | `p12_b_decoded_…`: 2 requests at P = 150 → 2 RIC SUBSCRIPTION FAILURE, `ricRequest:17` eventTriggerNotSupported. tshark (an independent decoder) gives the label. The cause was pre-registered at 125a24a (10:54 KST), before the agent code eb29f1a (11:56 KST) |
| Restore | `p12_c_restored_subscription_period_decoded`: request period 100. Later rungs assert 100 again |

I re-ran `p12-records-check.py` on the green `p12-a-records.jsonl`: it passes with 0 problems. I also checked every one of the 20 indications: each carries `granulPeriod` 100.

**AC8 run 2 is met.** `reference-compare.json` shows `equalsReference: true` and `differingComponents: []`. The default components include `extra` (`scripts/gates/reference-compare.py:27`), and the M9 `digests.json` has extra = {collet-start-time, kpm-headers, rc-multiset}. The only recorded difference is `xapp-image-ids.json`, which is recorded, not compared.

**Validation fields.** All five listed facts are present in `facts.jsonl`. Gaps outside those fields:
- The standards ledger is still a stub (S4).
- The unit-test result for the G ≠ T and K-bound paths of plan R-6 is not recorded anywhere durable (S1).
- `substitutionP12Applied: false` is not stated explicitly (S5).
- The exit record lists only ledger row 59, but rows 6–9 are also P03 changes (S5).

## Q2. Is the judge fix (row 59) correct, and is it not weaker?

**The reading of the agent is correct.** All of these were checked in the source:
- `simTimeMs = simTimeNs // 10^6` matches the agent's integer division at `sample-forwarder.cpp:106`.
- The UE list of a report is the union of the UEs in its samples (`:119-124`).
- An absent UE gets default `MeasValue` records (`:128`, `:139`), and the default `kind` is `NoValue` (`metric-map.hpp:34`).
- In the green run, the first Format 2 indication has item 0 all noValue (116/116 records), and seq 0 of the trace has no UE. This matches `first_with_ues seq=1` in the influx check.

**The reading of the spec is also correct.** The records are metric-major ("same order as in the Measurements Information Condition UE List", §8.2.1.4.2). Item 0 being all noValue is what the spec requires:
- E2SM-KPM §7.4.4.4 (v07.00 text, vault `SDJ6XPRF`) says: "If the List of matched UE IDs IE is used and a UE … appeared in the middle of the reporting period, then NULL shall be reported for the granularity periods priori to the UE appearing". It also requires NULL after the UE leaves, until the end of the period.
- So the old item-0 predicate was wrong to spec.
- The KPM v03.00 text is not cached in the vault, so equality with v03.00 is [U]. Format 2 for style 3 dates from v02.03.

**Is it weaker? Not as a gate, but yes as a standalone judge.** I mutated the green records and re-ran the new judge (script: `/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/39287615-82f4-4a9e-b9bd-7066dc8e447b/scratchpad/kongming-p03/mut.py`). It **passes all six** mutations:

| Mutation | `p12-records-check` alone | Whole p12 gate | Old judge |
|---|---|---|---|
| M1: present UEs blanked in items 0–2 | pass | **fail** (Influx rows missing → `every_seq_equal` false) | fail |
| M2: present UEs blanked in item 5 | pass | fail (same) | pass |
| M3: one F2 dropped | pass | fail (UE rows missing) | pass |
| M4: one F2 duplicated | pass | fail (`duplicate_keys`) | pass |
| M5: `granulPeriod` 1000 on every indication | pass | **pass**: no check reads it | pass |
| M6: no Format 2 at all | pass | fail (UE rows missing) | pass |

What this shows:
- Only M1 is a true relaxation against the old judge. That relaxation is spec-mandated.
- The truth of "the UE was absent" is judged only indirectly, through kpimon's all-noValue row skip and the trace→Influx completeness check (`influx-vs-trace.py:155-156,197-200`; ledger row 8).
- Row 59's argument ("the old checker could not pass on any real trace") is true, but it is not a no-weakening argument (S2).
- M5 is an unguarded hole (S3). It was also unguarded before, so it is not a regression.

## Q3. Is resuming at p12 at 83443e1, with M3–M5 from b71ad2c, sound?

**Yes. No rerun is needed before the tag.**
- `git diff b71ad2c 83443e1 -- scripts tools` touches only `p12-records-check.py` and `kpimon-decode-harness-records.c`. pins.conf is unchanged.
- `print_message_records` runs only under `--records` (`kpimon-decode-harness.c:159`).
- M3, M6 and M7 decode with `--xer 2` (`kpimon.sh:291`). M4 and M5 use neither changed file.
- `git diff 83443e1 c9061fd -- scripts tools` is empty.
- The plan invariant "M5–M7 re-pass after every agent or ns-3 change" is not triggered: the change touches only a judge.
- AC8 defines cp1 by the r3p C1 at the tagged commit, and that ran at 83443e1.
- The M10 end run re-runs every step from `fresh-install` anyway.

Put this reasoning in the annotated tag message (S7).

## Q4. Does the commit ordering breach scope-guard rule 3?

**In letter yes; materially no. The premise in the question is also wrong.**
- 83443e1 was committed at 05:41:30Z.
- The p12 gate at 83443e1 started at 05:42:42Z (`evidence/p12/20261103T054241Z/gate.log:1`).
- cd7d370, which adds row 59, was committed at 05:43:45Z. That is 63 s after a run had started using the changed judge.

Why it is not material:
- The verdict did not exist until about 06:03Z.
- Row 59 has not been edited since: the ledger's last commit is cd7d370.
- The change is spec-backed and adds per-item checks.
- p12 is a new M10 gate, outside AC18's m0–r3p scope.

Record the fact; do not argue it away (S2). Make the order atomic from now on: the predicate and its ledger row in one commit, as ddc6c44 and 6ad6bb2 did (same second). P04's #9 registrations are contractually "recorded before the code".

## Q5. Changes before tagging and P04

### Must
1. **Tag only after the extended seam smoke passes at the pins.**
   - Run `probe-delta-seam-smoke.sh` (1cf145f: d100tie, d150stop, emitter SHAs) with `vm-exec.sh --harness-sha 83443e1`. The smoke takes minutes.
   - Why: if it fails, ns-3 or oran-interface changes, then AC8 needs a run 3, and cp1 ("after the δ seam", contract AC8) belongs to a later commit. An immutable tag on 83443e1 would then mark a superseded state (`phase-04:57`; `goal-packet.md:49`).
   - The resume card already lists the smoke first (`plan.md:42`). This makes it a gate on the tag, not just a step before the δ runs (`phase-02:52`).

### Should
1. **Unit-test record.**
   - `kpm-report-period-test: ok` (tt byte-identical, p1000, p150 cause 17, g200 cause 1, k20/k21, period-*) exists only in the volatile scratchpad (`…/scratchpad/imgout/test.txt`, 11:55 KST).
   - The agent tree is unchanged from eb29f1a to 809fb2d (verified with an empty diff).
   - Copy it into the evidence, cite it in the exit record, and close `code-reviewer-261103-1140…:158` (Q4 there).
   - It is the only proof of R-6's G ≠ T bullet (`plan.md:218`).
2. **Ledger row 59** (`check-diff-ledger.md:65`):
   - Cite KPM §7.4.4.4 (NULL before the UE appears).
   - Say plainly that accepting a noValue item 0 relaxes the old predicate on spec grounds, and that UE presence is judged by row 8's `--every-seq`.
   - Add the 63 s ordering fact.
3. **Strengthen the judge** (after the tag is fine; land it with its own ledger row in the same commit):
   - (a) every indication's `granulPeriod` == G. Today there are 0 predicates on it (`p12-records-check.py` has no `granulPeriod` check), and M5 passes the whole gate.
   - (b) Trace-aware Format 2: the nodeId of item i for UE j is noValue iff that IMSI is absent from the trace at seq0 + i. This makes the judge strictly stronger than the old one on every input, independent of kpimon's row skip.
   - (c) Every period with at least one UE in the trace has a Format 2 indication, and no (period, IMSI) pair is reported twice.
   - (d) In `influx-vs-trace --every-seq`, also assert `influx_ue_rows == trace_ue_rows` and `influx_cell_rows == trace_samples`. Today these are reported but not judged (`:192-200`).
4. **Standards ledger** (`phase-03:34-39`):
   - Fill rows 2 and 3 and drop "(stub)", as P02 did (`phase-02:41-46`).
   - Row 3 cites §8.2.1.2/§9.2.x, but R-6 verified §8.2.1.4 (p. 17) and §9.2.1 (p. 62) (`plan.md:217`). Use R-6's sections.
   - Mark v03.00-only clauses "unverified against Zotero" (AC20).
5. **Exit record** (`phase-03:49-53`):
   - Check changes: rows 6–9 and 59.
   - Disclose that kpimon's Format 2 handler was patched to loop over the measData items (Testbed control.go.patch, P03). Format 1 already looped, which is what the contract tests, so AC10's "without a decoder rewrite" holds.
   - State `substitutionP12Applied: false`.
6. **Archive now.** Move the AC8 run 2 raw evidence (r3p 170 MB, p12 12 MB) to the /mnt/data archive at tag time, not at Stop A. AC8 (tag) requires the archive (`phase-04:9`). /mnt/data has 20 GiB free, and the worktree holds the only copy.
7. **Annotated tag message:**
   - harness 83443e1, the 4 fork pins, and the AC8 run 2 and p12 evidence paths;
   - "M3–M5 green at b71ad2c; the scripts/tools diff is p12 judge + `--records` printer, unused by M3–M5";
   - verify that each fork SHA is on its remote before tagging.
8. **Identity map** (`phase-04:18`): extract from the AC8 run 2 live1 `DlE2PdcpStatsLte.txt` (at cp1) and assert its sha256 equals the promoted M9 file. The traces component equality already implies this, so "at the cp1 commit" becomes literal at no cost.

### Could
- Set p12 simTime to 10.5 s. Today 100 mod 10 = 0 (`unreportedAtBye 0`, `gate-p12-kpm-period.sh:25`), so "no partial indication at bye" is only unit-tested.
- The `kpm-report-period-test.cpp:561` PASS label prints a stale `err` ("decode RC_FAIL consumed 0 of 1475"), which reads like a failure.

## Assumptions
- The scratchpad unit-test output came from the tree committed 62 s later as eb29f1a. Medium confidence. If it did not, re-run the test from the pinned image (`/usr/local/bin/kpm-report-period-test`).
- KPM v03.00 §7.4.4.4 matches the v07.00 text. Medium confidence. If v03.00 differs, the noValue fill becomes a deviation to list, not a judge bug.
- kpimon writes no Influx row for an all-noValue UE item (code-review §d). The Go loop was not re-read. Medium-high confidence. A null-keyed row would still be missing from the index, so M1 and M2 still fail.
- The seam smoke takes 5–15 min on the VM. Medium confidence. It does not change the must.

## Unresolved questions
- Did `check-report-period.py` (the independent pycrate decode of the unit-test octets) run, and with what result? No record was found.

Status: DONE
Summary: GO-WITH-CHANGES. AC10 (option B) and AC8 run 2 are met, and the row-59 fix is spec-correct (KPM §7.4.4.4). Tag `m10-cp1` = 83443e1 only after the extended seam smoke at the pins. The shoulds are record fixes plus a stricter p12 judge (granulPeriod unchecked; noValue judged only via Influx).

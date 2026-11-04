# P07 phase-exit review (E2SM-RC Style 5 action 3 to the source en-gNB)

Date: 2026-11-05 (Asia/Seoul). Reviewer: kongming (Opus 5.5, advisory only; Claude Code runtime, `model: opus` per the user's CLAUDE.md override). Harness HEAD `3dfe627` (last gate code `c88d3e4`). Pins: Testbed `36dbcc3`, ns-3 `ea6e46f6`, oran-interface `53253fe`, e2sim `e2705816`. Pre-P07 harness `2e7abf4`; P06b fork pins Testbed `89d45af`, ns-3 `e5b02094`, oran-interface `e5ad09d`.

I did no VM operation. My host-side work was git reads and offline re-runs of committed judges over the raw evidence in the worktree: `reference-compare.py`, `check-actuation-delay.py`, the row 115 counter helper, and `ts-patches-selftest.sh`.

## Verdict: GO-WITH-CHANGES

## TL;DR

P07's exit is met on the evidence. Every Validation bullet has a passing committed verdict, and I strengthened two of them offline:
- The live R3′ C1 at P07 pins already satisfies the dry form of AC8b. ipc and traces are byte-equal to M9. The ledger differs only in `viaNodeId` 2 → 3, and rc-multiset only in R-2's enumerated fields.
- HandoverStart − apply = 3.0 ms holds on every applied line of R0, R1, R2, Q8, e2i and the calibration run, not only in R3′.

No check was weakened, narrowed or deleted. Every removed check line has a renamed, stricter successor.

Seven record changes, all host-only, must be made before the exit is recorded. Two carry the most weight:
- **The Failure Protocol was skipped.** Three reds were fixed without the kongming consult the protocol requires.
- **A pre-registration changed after the phase started.** The TS xApp now takes the serving cell from the QP answer and only confirms the `ueId` in Influx. That contradicts plan R-4 (`plan.md:202`), and by the plan's own rule (`plan.md:140`) a change like this is T3. It does not contradict the contract, so it goes to the user as a Stop A′ question rather than a pause now.

The mixed pass set is acceptable for this exit. P08 should restore one pin set by running the full chain at the cp2 SHA, which it largely has to do anyway.

## Reframed problem

- **The decision:** can P07 close at harness `7ef324f`/`3dfe627` and Testbed `36dbcc3` on a pass set spread over three harness revisions? The questions behind it:
  - Does AC14 / AC14b (RIC half) / AC18 hold?
  - Did any of the three chain-failure fixes, or the controller's rulings, quietly change a contract or pre-registration item?
- **Requirements:**
  - AC14: Style 5/3, the source en-gNB, an SN-initiated change, en-gNB-UEID from KPM via Influx, the I-4 IDs in the standards ledger, R2/R3′ green.
  - AC14b: the TS xApp reads the UE ID from Influx.
  - AC18: rows before code, nothing weaker.
  - G1 (seam smoke), S1 (f2 via agent 2).
  - The scope guard (`goal-packet.md:43-49`).
- **Non-goals:** AC8b itself (P08), D-06b-1 (P10), `ns3.imsi` removal (Stop A′).

## Q1. Is the exit met?

| Item (`phase-07-…md:121-130`, contract AC14/AC14b/AC18) | Committed artifact | Status |
|---|---|---|
| Decoded wire: header Format 1, Style 5, action 3, en-gNB-UEID = the Influx row's IDs and R-4 values; meid = source (`viaMeidEqualsNode`); ledger `viaNodeId == sourceCell` | `r2/20261104T190033Z` `r2_live*_wire_requests_equal_positives_via_source_with_stub_key`, `r2_d7_every_control_via_the_source_en_gnb_both_gnbs` (4/4 via source, viaGnbs [2,3]); `r3p/20261104T194024Z` `r3p_live*_wire_requests_equal_handovers_via_source_with_predictor_key`, `r3p_live*_d7_source_en_gnb_addressed`, `runs/live1/extra/c1-extract-summary.json` `viaMeidEqualsNode: true`; Q8, R0 and R1 extracts likewise. Influx equality is transitive: prepare requires U = N6's `ueIdAtT` (row 108), and the wire requires I(ueId) = the trigger IMSI over a bijective map (row 113) | met |
| rc RestartCount 0 everywhere, incl. the nil-UE-ID fixture | `<gate>_restart_counts_*` in every run; `q8/20261104T174509Z` `q8_rc_refuses_a_control_without_ue_id_invalid_argument` | met |
| R0/R1 under the registered predicates; the C4 arrival-order fixture fails; the order suite passes | `r0/20261104T174948Z` and `r1/20261104T201649Z` D7 (3 and 4 applied via source, 1 non-source and 1 eNB refusal); `r1_c4_check_fails_the_arrival_order_fixture`, `r1_live*_c4_sort_exercised_not_arrival_order`; `p07-host-suite/20261104T133712Z` (oran-interface `53253fe`, 1/1 and 31/31) | met. The swapped-comparator mutant run is described in prose only (`:206`) |
| R3′ preparation: stub keyed by `ueId`, calibration keyed by `ueId`, stage B via source, IMSIs kept | `r3p/20261104T192532Z` (calibrate, 25 triggers); `r3p/20261104T193344Z` `r3p_dryb_*`; scenario/schedule/stage-A diffs since `2e7abf4` touch only `ueId` text and `scenarioSha256` (R-2) | met |
| R2 C1 and R3′ C1 with `replayEqual: true` | Both verdicts `c1: {liveRunsEqual, replayEqual, rngRun2Differs}` all true | met |
| e2i: independent Style 5 applied; 3/1 → `action-not-supported`; non-source → `unknownUe`; eNB → `ran-function-id-invalid` | `e2i/20261104T200321Z` `e2i_injected_controls_on_the_wire_and_answered` (five tags, expected answers), `e2i_independent_target_applied_ledger_and_handover_start` (two lines, non-source names IMSI 3), `e2i_style5Action3Announced` | met. The wire cause for non-source is `control-failed-to-execute` (disclosure, Q4) |
| HandoverStart − apply = c on every applied line | Gate: R3′ only (`r3p_*_actuation_delay_…`). **Offline at HEAD** (`check-actuation-delay.py --delta-ms 0`): pass on r0 live1 (3), r1 live1 (4), r1 f2 (1), r2 live1/live2 (4 each), r3p calib (25), q8 (1), e2i (1) | met (stronger than gated) |
| G1: seam smoke green at P07 pins; row 106 predates the first code commit | `delta-seam-smoke/20261104T200900Z` 32/32 (ns-3 `ea6e46f6`, oran-interface `53253fe`, `--expect 9`, stop and tie cases); `e66b263` is the parent of `760ce3e` | met. Row 106's content still awaits user confirmation (Stop A′) |
| S1: f2 via agent 2 (forwarded 2, failedOnBye 1, rejIpcDown 0, pending 0; agents 1 and 3 at 0) | `r1/20261104T201649Z` `r1_f2_control_after_final_barrier_one_failure_no_ledger_line_failed_on_bye` (stop control ueId X2AP 2 = IMSI 4, failure on the wire) | met |
| **AC14** (contract `:94-100`) | All the above; I-4 and I-1 rows read from the PDFs (`phase-07-…md:135-141`) | met. The I-1 mapping is shown at Stop A′ |
| **AC14b RIC half** (`:104`) | TS patch: `parse_en_gnb_ue_id` then `ue_has_metrics_row` (an exact-tag Flux filter); `EnGnbUEID` is filled from the parsed tag; row 125's n3 on the wire (no request with X2AP 4095; TS log "no UeMetrics point … in the last 60s"); row 128's static check passes at HEAD (I re-ran it) | met **under an interpretation**: the ID is confirmed in Influx, not read back from it, and the serving cell comes from the QP answer. This changes pre-registration R-4 (Q4) |
| **AC18** | Q2 | met, with three process notes |
| Step 3 "hard gate" (`:109`, `:147`): traces byte-equal to cp1 **with controls entering at the source SN** | The host proof was a **no-control** run (`:207`), which never calls `ApplyE2SnChange`. **Offline at HEAD:** `reference-compare.py compare r3p/20261104T194024Z/runs/live1 <M9 ref>` gives ipc and traces equal and differing components `[ledger, extra]` only. The ledger diff is exactly `viaNodeId 2 → 3`. rc-multiset differs exactly in `action 1→3`, `style 3→5`, `imsi 1 → ueId {mEnbUeX2apId 3, 00F110/00001}`, `targetKey 0202→0210`, `viaNode 2→3`; kpm-headers and collet-start-time are byte-equal | met, but **only by my offline compare; no committed artifact** (required change 4) |

## Q2. AC18 audit (harness `2e7abf4..3dfe627`; Testbed `89d45af..36dbcc3`; oran-interface `e5ad09d..53253fe`; ns-3 `e5b02094..ea6e46f6`)

**Commit order (author = commit time, KST):**
- Rows 106–128 and the rulings went in at `e66b263` 20:59:12. It is the parent of `760ce3e` (protoc) and precedes every fork code commit:
  - Testbed `0ba9812` 21:16 onwards;
  - oran-interface `efd5802`/`8a3cb21` 21:31;
  - ns-3 `ea6e46f6` 21:31.
- The harness predicate code came later still: `2bb047c`, `f1b0a73` and `8511fa2`, all at 22:00.
- The row 124 note (`990981a`, 21:34) came after the ns-3 code, which produced the fact it rules on. It also came before the harness code that matches stop-time `late` lines, so the rows-before-code rule holds for predicates.
- The serving-cell note (`8c47f73`, 21:37) came before the TS code (`990f8d2`, 21:45).

**No check was deleted.** `git diff 2e7abf4 HEAD -- scripts tools` removes 11 `check` lines and adds 48. Every removed line has a renamed successor that is stricter or registered:
- D7 target → source (rows 10–12);
- wire via-target → via-source with a context dir (rows 13, 14, 113);
- `e2i_injector_routes_…_and_the_enb`;
- two → five e2i controls (row 120).

Sampled predicate diffs match their rows:
- `r3p-checks.py` `c_d7`, `c_wire`, `c_stub`;
- `e2i-wire-checks.py` `rcdef_problems` (exactly `[(5, 3)]`, recursive IDs ⊇ {1,2,3,4} ∪ wire IDs);
- the `wire-c1-extract.py` filter `:376` (style 5, action 3, key and `ueId` all required).

**`8963fa4` (row 129).**
- The check is purely additive: `agents_reserve_ports` (`agents.sh:69`) adds a fail condition before any agent or pacer starts. The frozen S0/S1/probe scripts are untouched.
- **Process note 1:** row 129 was committed in the same commit as its code, so "row first" cannot be shown from history. A new check is not a changed predicate, so this is tolerable, but future rows should be committed on their own first.
- **Process note 2:** the row labels itself "No (P4, ordinary)". It is an ops check unrelated to P4. Fix this with a dated note, not by rewriting the row.
- **Residual weakness, not a weakening:** a reservation stops new ephemeral allocations but does not evict a socket that already holds a port in 38470–38499. A stronger conjunct would assert that no socket holds a local port in that range at check time (P08 hand-off 6).

**`c88d3e4` (`ts_rc_logs_save`, `ts-lib.sh:489-502`, called bare at `ts-rung-lib.sh:72`).**
- It is record-only in fact. It is not wrapped in `check`, every failure path echoes into the log file, and it returns 0. It changes no predicate and so needs no row.
- I found no token in any raw `ts-xapp.log` or `rc.log`. The TS xApp prints only "token set".
- **Commit hygiene:** a harness feature sits inside a `build(pins)` commit. The commit is pushed and must not be rewritten. State in the work record that `c88d3e4` carries it.

**The TS query change (`36dbcc3`).**
- Old: `filter → group() → limit(1) → keep(_time)`. New: `filter → keep(_time) → group() → limit(1)`.
- The filter (measurement, exact `ueId` tag) and the 60 s range are unchanged, as is the CSV rule (a record with a non-empty `_time`; any `error` column refuses). The result is the same existence answer, and the old form never worked on kpimon's mixed int/float data. It is not weaker.
- **Record correction:** the work record says the fixed query "returns the UE's latest `_time`" (`:249`). `limit(n: 1)` after `group()` returns the first row of the merged table, not the latest. This has no behavioural effect because the check is existence-only.

**Rows whose pre-landing condition is not recorded.**
- Row 115 says the helper is "replayed offline on the archived M7, R0, R1 and r3p runs, and all must pass" before landing. The work record has no such entry.
- I ran the helper at HEAD on `m7/20261104T093642Z`, `r0/20261104T100125Z` live1 and k9, `r1/20261104T102205Z` live1 and f2, and `r3p/20261104T082155Z` live1. All pass, with max `samplesNoUeContext` 0 and `ueContextRejected` 0. M7 has 266–271 stats lines per node across restarts.
- The record must cite this (required change 5).

**Stricter changes without a row (minor).** `5aa31d5` makes token redaction fail closed and `rc-send.sh` require exactly one UE line. It adds lint negatives. Both are stricter, and neither is an m0–r3p check, so no row is needed. Name them in the work record's AC18 line.

## Q3. The mixed pass set

**Verified spread:**
- M2–R0 ran at harness `d04843d` with Testbed `faeeb34`.
- R1 single ran at `5727196` with `faeeb34`.
- I2, R2, R3′ (×3), e2i, the seam smoke and R1 C1 ran at `7ef324f` with `36dbcc3`.
- The ns-3, oran-interface and e2sim pins are the same throughout.
- Harness `d04843d..7ef324f`: 17 files, +51/−1, all port-reservation check lines plus `ts_rc_logs_save`.
- Testbed `faeeb34..36dbcc3`: one file, the TS patch.

**What the controller's disclosure omits.** The agent image is keyed by the Testbed commit, so the TS-only pin bump **rebuilt the agent image**:
- M5, M6, M7, Q8, R0 and R1 single judged `ns3-e2-agent:faeeb3482a06`, image `sha256:035da816…`.
- R2 onwards judged `ns3-e2-agent:36dbcc3881ff`, image `sha256:53029b61…` (from the gate logs).
- The sources are identical, but the build does an unpinned `apt-get install`. "The gates never touch the changed files" is true for the sources, not for the artifact under test.

**Re-run now at `7ef324f`/`36dbcc3` (M2–R0, about 2 h of VM time, about 25 GiB of /home growth):**
- Benefit: one pin set for P07's own record, and the reservation check exercised in M5–R0.
- Cost: real VM time and disk. And P08 starts from `f7-rerun-green` with new harness code (`reference-transform-compare.py`, `--reference-transform`), so P07's SHA will never be the cp2 SHA anyway.
- The marginal assurance is close to zero: the sources are identical, the reservation can only add failures, and R2/R3′/e2i/R1 C1 exercised the rebuilt image under KPM, Influx = IPC and the counters.

**Recommendation:**
- Accept the mixed set for the P07 exit as a disclosure. Add the agent-image rebuild to that disclosure.
- Restore uniformity in P08. Run M2 → M7, I0, Q8, R0, R1 single, I2, R2 C1, then the three R3′ C1s (δ 0/150/500) at one harness SHA and one pin set, and tag `m10-cp2` at that SHA.
- That adds only about 45 min (Q8, R0, R1, R2) to the chain P08 must run from `f7-rerun-green` anyway.

**Is it the user's call?** Not for this exit. Judging whether evidence is sufficient is the controller's job (with kongming), and it goes to Stop A′ as a disclosure. It becomes a Stop A′ **question** only if cp2 would be tagged without a uniform-pin chain.

## Q4. Scope guard

Diffing the delivered behaviour against the locked contract finds **no material contract mismatch**:
- AC14: Style 3/1 is gone from the control path (agent `action-not-supported`, RAN function exactly {(5,3)}, rc InvalidArgument for anything else).
- AC13's announcement is narrowed correctly.
- No compat mode was added. rc keeps the `GnbUEID` proto field but refuses it.
- Nothing out of scope was delivered.

Two items, though, are not the controller's to rule:

1. **The R-4 pre-registration change. This is the user's decision.**
   - `plan.md:202` pre-registers: "The TS xApp reads the UE's latest row by key from Influx (serving cell and ID fields) to build the control."
   - The delivered TS xApp takes the serving cell from the QP answer (`ts_xapp.cpp` patch `:204-216`). It uses Influx only as an exact-tag existence check (`:56-108`). It fills `EnGnbUEID` from the tag string it received (`:119-128`, `:165-168`).
   - `plan.md:140`: "changing one after its phase starts is PAUSE T3". The controller's note (`phase-07-…md:91-96`, 21:37, after the phase started at 20:39) made the change as a ruling, and `plan.md:202` has no note.
   - **Why I do not ask for a pause now:**
     - The contract text (AC14 `:98`, AC14b `:104`) concerns the UE ID's source, not the serving cell.
     - The ID bytes equal the Influx tag by construction (equality filter), and row 125 makes the dependency falsifiable on the wire.
     - The upstream TS design takes the serving cell from QP.
     - cp2's AC8b evidence does not depend on which source provides the serving cell, because in R3′ both equal the ledger `sourceCell`. My offline compare shows via 3 = sourceCell 3.
   - **What it needs:**
     - A dated note at `plan.md:202` that names it a pre-registration change. It should give the T3 reading and why the change was treated as non-material.
     - A Stop A′ question with the default "accept". The alternative is R-4 as written: kpimon tags the reporting node, and the TS xApp reads the serving cell and IDs from the latest row. That needs a kpimon rebuild and would be bundled into P10 with D-06b-1 and P15.
2. **The VM dangling-image prune "ops rule" (`phase-07-…md:192`) is a standing self-grant against §5 "Nothing is deleted autonomously" (`contract…:142`).**
   - I recommended registering it at P06b, by analogy with `plan.md:131`. It is still the user's constraint.
   - Ask for ratification at Stop A′. Until then, P08 should not prune without a ruling. P07 itself pruned nothing.

**The remaining rulings are the controller's to make, and are disclosures:**
- **The 60 s window (`kUeMetricsWindow`):** an implementation parameter. Each run gets a fresh bucket, so it is defence in depth. The largest wall-clock gap between rows is T_ctl (30 s) plus a step. P09 should record that the window still holds at s10's rate.
- **The token written at install time into a git-ignored config:** this follows the kpimon/QP precedent, T7 holds, and no `influx_token` value is in any evidence file.
- **The e2i non-source answered with `control-failed-to-execute`:** E2AP's RIC-request causes have no UE-unknown value. The E2AP text reads "Requested control procedure initiated by RIC Control Request failed to be executed in the E2 Node", and the same mapping already applies to every ns-3 refusal (R0 k9 since M9).
- **Stop-time `late` lines carry imsi 0** (the row 124 note).

**Contract-constraint and protocol breaches to disclose (not scope changes):**
- **/home fell to 17 GiB, below the 20 GiB dev floor** (`contract…:142`; invariant `plan.md:58`; `phase-07-…md:238`).
  - The breach was resolved by an in-rule revert, not a T2 pause, and no snapshot was deleted.
  - Its red M5 evidence was lost, because the scrub failed closed when Influx was evicted (`:241`).
- **The Failure Protocol was not followed.**
  - The rule ("Failure Protocol and phase exit: as in M8–M9. One kongming-guided fix", `plan.md:316`; the M8–M9 text "STOP this phase… Spawn the `kongming` subagent… Never continue by self-reasoning", `plans/261023-0009-…/phase-05-r2-ts-xapp-stub-qp-stray-ack-probe.md` § Failure Protocol) was not applied to any of the three reds. No kongming report exists between `kongming-261104-1958` and this one.
  - The substance was sound. Each cause was reproduced on the VM, each fix is minimal, and each passed at the next run.
  - **This review gives retroactive counsel on all three fixes and endorses them:**
    - `--disable-test-asan` is correct, with one caveat: "the generated C does not change" is supported functionally (e2i `x2apRequestPartDecodes`, the hex sidecars equal the wire) but not byte-for-byte;
    - the port reservation is correct, but incomplete (P08 hand-off 6);
    - the Flux reorder is correct.
  - From P08 on, the protocol must be followed literally.

## Q5. Required changes, P08 hand-offs, Stop A′

### Required before the exit is recorded (host-only, record work)

1. **Failure Protocol record.** Add a dated work-record entry saying that three Verify reds (M5 hang, R1 port bind, R2 Flux 400) were fixed without the required kongming consult, that this review is the retroactive counsel, and that P08 follows the protocol literally. List it for Stop A′.
2. **R-4 note.** Add a dated note at `plan.md:202` (and cross-reference `phase-07-…md:90-96`). It must say that the serving cell comes from the QP answer, that Influx is an exact-tag existence check, and that `EnGnbUEID` comes from the parsed tag. It must call this a pre-registration change after the phase started (T3 by the letter, treated as non-material for the reasons in Q4) and put it as Stop A′ question 1.
3. **Floor breach record.** Label `:238` as a breach of the §5/invariant 20 GiB floor (minimum 17 GiB) with the revert recovery, and note the lost red-run evidence. Disclose both at Stop A′.
4. **Commit the step 3 / AC8b dry-form evidence.** Write `reference-compare-m9-dry.json` (the allowlist admits `reference-compare*.json`) into `r3p/20261104T194024Z` with:
   - the compare output and the per-component breakdown;
   - the exact ledger and rc-multiset diffs above;
   - the computing harness SHA, and a note that it was computed offline after the run.

   Then amend step 3's record (`:207-209`): the host no-control proof does not exercise `ApplyE2SnChange`; the with-control invariant rests on this live compare. Optionally add the c-offset results for R0/R1/R2/Q8/e2i/calibration under the same name prefix.
5. **Record row 115's pre-landing replay.** Cite this review's offline pass, or re-run it and commit the JSON.
6. **Complete the spread disclosure (`:264`).** Add the agent-image rebuild (`035da816` → `53029b61`, same sources), that `c88d3e4` carries `ts_rc_logs_save`, that R1 C1 ran after the TS rungs (environment ≠ the M10 order; the M10 order is covered by R1 single at `5727196`), and that the "latest `_time`" wording is wrong. Add dated notes to row 129 (same-commit landing; "P4" → ops).
7. **Standard exit hygiene.** Update the resume card (`plan.md:37-38` still says "next P07"), the phase table row (`plan.md:76` "pending"), disk (/home 57 GiB, /mnt/data 7 GiB on 2026-11-05) and the projection.

### P08 hand-offs (in order)

1. **Host-side disk-floor watchdog for dev chains before the first VM step.**
   - Reuse `scripts/vm/host-disk-watchdog.sh` (it already stops the gate unit and shuts the VM down, `:48`) from `vm-exec.sh` / the chain driver with `--min-gb 22` (floor plus a 2 GiB margin) and a 15–30 s interval.
   - A trip fails the gate (Failure Protocol). Register a "new check" row first.
   - Add a guest-side guard: wrap agent and xApp `docker build` in `timeout`, and abort when the guest root exceeds 85 %, so kubelet DiskPressure never evicts the RIC.
2. **Red-run evidence survives.**
   - `scrub-evidence.sh` should read the token from a source that survives an Influx pod eviction (the k8s secret or the installer's `influxdb_auth_token.json`), still failing closed.
   - `fact()` (`scripts/gates/lib.sh:79`) must not emit `{"value":}`. Both failed runs (`r1/20261104T175831Z` facts line 9, `r2/20261104T182917Z` lines 26–27) lost `verdict.json` this way.
   - The call sites `gate-r1-rc-multi-control.sh:257,321` and `gate-r2-ts-stub-qp.sh:151` use `cat … || echo null`, which misses an **empty** file. This is the known P6 fact-JSON trap, still live.
3. **One harness SHA, one pin set** for M2 → R3′ (incl. Q8, R0, R1 single, R2 C1, the three R3′ C1s), with `m10-cp2` at that SHA (Q3).
4. **Codex adversarial review (read-only, one call)** over harness `519d2bb..HEAD` plus Testbed `ff704ab..36dbcc3`, before the cp2 tag. No audit covers the three post-audit fixes. Do not call `adversarial-review --help`: that accident has now happened twice.
5. **The TS xApp's Influx test fixture.**
   - The step-5 throwaway InfluxDB held one field type, which is why the 400 slipped through.
   - Add a host test, run in the TS image build or `lint.sh`, against InfluxDB 2.7 loaded from an archived `influx-kpimon.csv`, which has mixed int/float `UeMetrics`.
   - Assert that a present tag passes and an absent tag fails. Add a parser case built from the real HTTP 400 schema-collision body. New-check row first.
6. **Port reservation, second conjunct.** No socket holds a local port in 38470–38499 at check time (`ss -Htan`, `sport` in range). Amend row 129 first.
7. **D-06b-1 stays scheduled in P10** (`phase-10-…md:76`). Optional: if the user rules R-4 "as written", bundle the kpimon node tag with it.

### Stop A′: questions (the user decides; each has a default)

1. **R-4 serving-cell change and the AC14b reading:** accept "serving cell from the QP answer, `ueId` confirmed in Influx" (default), or require the serving cell and IDs read from the latest Influx row (kpimon node tag, bundled into P10).
2. **Confirm the #9 rows 106, 120 and 121.** They were recorded before code, and their content is unconfirmed (ruling 1).
3. **Ratify the VM dangling-image prune rule** against §5, including P06b's prune (default: ratify, limited to untagged builds of this plan, every prune logged).
4. Carried from P06b: keep `ns3.imsi` through M10 (default) or remove it by amendment; D-06b-1 in P10 (default) or before cp2.

### Stop A′: disclosures (no ruling)

- The pass-set spread and the agent-image rebuild (Q3), with P08's uniform chain as the remedy.
- The /home 17 GiB floor breach and the lost red M5 evidence.
- The Failure Protocol deviation, the three fixes, and this retroactive endorsement.
- I-1 mapping table; e2i cause mapping; stop-time `late` imsi 0; 60 s window; token install pattern; T_ctl/W provenance strings still cite M9-era calibrations, while P07's calibration re-measured L_max 15.3 ms with `tCtlCoversTwentyLMax: true`.
- The TS xApp keeps upstream's REST control path (`ts_control_api`), which the harness switches to gRPC at install. It does not reproduce M9, but the shipped default is not the Style 5 route. P12 could make the installer write gRPC.
- /mnt/data has 7 GiB free against the 5 GiB floor. The M10 end-run raw archive (M9: 5.8 GB raw, roughly 13:1 compression) needs re-projection.

### The two sub-questions

- **Should a gate abort itself when host free space falls below the floor?**
  - Yes, but put the logic on the host side around the VM run (hand-off 1), not inside each gate.
  - The guest cannot see host free space, and the M9 watchdog already implements stop-and-shutdown.
  - Trip at floor plus margin, because qcow2 growth continues briefly after the kill.
  - Aborting fails the gate loudly, which is stronger, not weaker.
- **Should R2 gain a live Influx-error negative?**
  - No. R2's four positives already fail on any live Influx error: no control, then a pacer abort, exactly as `r2/20261104T182917Z` did. n3 covers "no row → no control".
  - Inducing an HTTP error or an HTTP 200 error table live would mean restarting the TS xApp with a broken token, or a broken query, inside the lock-step window. That adds a restart and complexity to the rung, and it mostly tests InfluxDB.
  - The regression that bit was a fixture gap, so fix it with hand-off 5. The error paths are fail-closed by construction and have 12 parser cases in the image build.

## What to avoid

- Re-running M2–R0 on the VM now to make P07's own record uniform. It costs about 2 h and about 25 GiB, and P08's chain at the cp2 SHA supersedes it.
- Rewriting rows 124 or 129, or commit `c88d3e4`. Append dated notes. Pushed history stays.
- Treating the R-4 change as settled because the contract text allows it. The plan made pre-registrations user-owned after the phase starts.
- Any VM prune in P08 before the user ratifies the rule.
- Fixing the next red without a kongming consult, however obvious the cause.

## Success metrics

- `git ls-files` shows `reference-compare-m9-dry.json` in `r3p/20261104T194024Z` with ipc and traces equal and only R-2 fields differing.
- `plan.md:202` carries the dated R-4 note, and the Stop A′ journal lists it as question 1.
- P08's chain is green at one harness SHA equal to `git rev-parse m10-cp2`, including Q8, R0, R1 and R2.
- No dev chain after P07 lets /home fall below 20 GiB, and the watchdog's trip record exists.
- The next red run in any gate still writes a `verdict.json`.

## Assumptions

| Assumption | Confidence | What would change the answer |
|---|---|---|
| The raw files in the worktree are the ones archived and hashed (`evidence-sha256.txt` committed in `bbe0e8c`) | High | A mismatch would make my offline compares non-authoritative; re-run them from the `.tar.zst` |
| P07 started at 20:39 KST (`af726f1`), so `8c47f73` (21:37) changed R-4 after the phase started | High | If the controller treats "phase start" as the first code commit, the change still came after the rows and before the TS code, and the T3 reading weakens to a recording gap |
| No kongming consult happened off-record for the three reds | Medium-high (no report in `plans/reports/` between 1958 and now; the work record names none) | If consults happened, required change 1 becomes "commit the notes" |
| The rebuilt agent image is functionally identical (same sources; unpinned apt only) | Medium-high | A differing package version that changes encoding would show in P08's uniform chain (M5–M7) |
| `--disable-test-asan` leaves the asn1c binary and generated C unchanged | Medium (functional evidence only; I did not diff the generated C) | A byte diff of `x2ap-gen` between the two builds would settle it |
| The privacy hook blocked `agent-image.env`; I read image IDs from the gate logs instead | High | None |

## Unresolved questions

1. User, at Stop A′: accept the TS xApp's serving cell from the QP answer with an Influx existence check (default), or require R-4 as written?
2. User, at Stop A′: confirm the #9 rows 106, 120 and 121, and ratify the VM dangling-image prune rule.
3. Controller: were any of the three P07 reds discussed with kongming off the record? If not, does the controller accept the retroactive-counsel record, or want each fix re-justified separately?
4. Controller: will P08 include Q8, R0, R1 and R2 in its chain so cp2 rests on one pin set, or should the Stop A′ packet ask the user to accept a cp2 tag on the mixed set?

Status: DONE_WITH_CONCERNS
Summary: P07 is GO-WITH-CHANGES. Every Validation bullet and AC14/AC14b/AC18 is met, and offline re-runs confirm the AC8b dry form and c = 3.0 ms in every rung. Seven host-only record changes are required first, chiefly the skipped Failure Protocol, the R-4 serving-cell pre-registration change (a Stop A′ user question) and the /home floor breach. The mixed pass set is acceptable now and should be made uniform by P08's chain at the cp2 SHA.

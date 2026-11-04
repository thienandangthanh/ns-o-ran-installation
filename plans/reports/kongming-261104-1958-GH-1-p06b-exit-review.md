# P06b phase-exit review (KPM UE IDs, X2AP context export, kpimon to Influx)

Date: 2026-11-04 (Asia/Seoul). Reviewer: kongming (Opus 5.5, advisory only). Harness HEAD `ba2c8df` (gate code `28d4508`). Pins: Testbed `89d45af`, ns-3 `e5b02094`, oran-interface `e5ad09d`, e2sim `e2705816`.

## Verdict: GO-WITH-CHANGES

The live evidence meets P06b's codec, context and Influx exit. R2/R3′ are deferred to P07 as the plan pre-registered. None of `9a64fd3`, `d8e7692` or `28d4508` weakened, skipped or deleted a check, and each code commit came after its ledger rows. One Validation bullet has no committed verdict: the checkpoint-1 byte equality. I re-ran that comparison offline and the claim holds. Finding 1 must be committed before the exit is recorded. It is host-only, and no VM rerun is needed. The other findings are fixes for P07 and for the records.

## Reframed problem

- **The decision:** can P06b close on the evidence at harness `28d4508`, with R2/R3′ judged at P07, without breaking AC14b, AC18 or the scope guard?
- **The requirements:**
  - AC14b: the context channel leaves the IPC traces literal; the KPM carries en-gNB-UEID and eNB-UEID with no gNB-UEID; kpimon stores the UE ID in Influx.
  - AC18: every changed predicate has a ledger row first, and none is weaker.
- **Also in scope:** what P07 must take over, and which disclosures go to Stop A′.

## Q1. Is the exit met?

| Validation bullet (`phase-06b-…md:55-58`) | Committed verdict | Status |
|---|---|---|
| Decoded KPM: every gNB UE ID is en-gNB-UEID resolved by the UE context, globalENB-ID {00F110, 1}; eNB-UEID per R-4; zero gNB-UEID | `m6/20261104T093457Z` `m6_kpm_ue_ids_…` (99 Format 2, 0 gNB-UEID). `m7/20261104T093642Z` `m7_kpm_ue_ids_…` (2,959 Format 2; node 1 has 1,131; 0 gNB-UEID). The rungs' `kpm_ue_lists_move_…` in R0/R1/r3p. P12 records with `ueIdTags` | met |
| `digest-run.py` ipc digests equal checkpoint 1; no `ueContext` line in any IPC trace | "No `ueContext` line": met by the C8/C1 digests (`ipcTraceUeContextLines` 0) and by conjunct (e) in m6/m7/p12/r0/r1. **"Equal to checkpoint 1": no committed artifact** (finding 1) | partly met |
| Influx `ueId` tags in the R-4 form; `influx-vs-trace.py` passes | `m6_influx_three_samples_…` (193 UE rows, 0 mismatches), `p12_a_influx_equals_ipc_trace_every_seq`, `m7_influx_ue_rows_ueid_resolves_…` (all five nodes, 0 mismatches) | met |
| M5–M7 green; the R-8 live cross-check passes | M5 PASS `072003Z` at `9a64fd3`. `28d4508` changed only `q_sub_actions` and the self-test in `e2-facts-query.py`, and M5 calls neither, so M5 still holds. M6/M7 PASS at `28d4508`. `r3p_live1_ue_context_equals_identity_map_cp1` PASS, inside a verdict that fails by design | met (with a note) |

The R2/R3′ deferral is correct. The plan's P06b row (`plan.md:74`) and dependency notes (`plan.md:89-90`) register it, and the contract puts "R2 and R3′ still pass" under AC14 (`contract…:100`), which is P07's gate.

## Q2. AC18 audit of the three commits

- **Rows came before code.**
  - `56a7092` (rows 79–100 and the rulings, 14:36) came before `9a64fd3` (15:14).
  - `ae937f7` (row 101, 16:50) came before `d8e7692` (16:53).
  - `1feb90a` (rows 102–105, 17:41) came before `28d4508` (17:54).
- **No check was removed.** A diff scan of every gate script found no removed `check` line. Arguments were only added (`--ue-context-dir`, `--facts`).
- **Predicates changed only in additive ways:**
  - The old `check-n6-influx-window.py` `elif s == t` became `continue` plus `if`. This is equivalent, because the `s > t` branch already excluded `s == t`.
  - The UE row that `influx-vs-trace.py` used to skip silently now fails (self-test case `ue-noimsi`).
  - `ipc-null-sink` still rejects malformed `ueContext` lines.
- **Row 101 (attribution by association) is correct, but its "why not weaker" text overstates.** See finding 7.
  - When no IP is shared, the new rule picks the same node as the old one. It also fails closed on a missing association or E2 Setup (`kpm-ue-list-moves.py:227-249`, `:477-482`).
  - The final M7 really had shared IPs (`m7/20261104T093642Z/node-ips.json`: 172.17.0.3/.4/.5/.7 each listed for two nodes), so the rule was exercised live and passed.
  - The rungs call `kpm_moves` without `--facts`, so they now fail closed on a shared IP instead of letting the last-listed node win.
- **The two r3p failures are honest and untouched.**
  - None of the three commits touched `r3p-checks.py`.
  - The live1 ledger is byte-identical to P05's green run (`cmp` of the two `e2-control-ledger.jsonl` files): `viaNodeId 2`.
  - The expectation moved in P06 at `e7644c7` (`r3p-schedule.json:52` is now `"via": 3`, row 22).
  - The same run passes the old D7 `r3p_live1_d7_target_addressed`. So at HEAD the gate requires "via target" (D7, row 10, still P07) and "via source" (rows 14/15) at once, and it is red by construction (finding 6).
- **Offline re-judgement at HEAD:**
  - `e2-facts-query.py sub-actions` on `r3p/…/live1-sub-facts.json` exits 0 (three requests, each with one action, ID 1, Format 3).
  - `ue-context-map.py check --expect-map` on r3p live1 passes with `ipcTraceUeContextLines` 0.
  - So the r3p run, made at `d8e7692`, also meets rows 103 and 105.

## Findings

1. **(Must, host-only, before the exit is recorded.) The checkpoint-1 byte equality has no committed artifact.**
   - **Evidence:**
     - Validation bullet `phase-06b-…md:56` and step 2 `:48`; the risk table calls it a hard gate (`:79`).
     - The claim is prose only (`:116`). `r3p/20261104T082155Z` has no `reference-compare*.json` on disk, in git, or in the raw archive list (`plans-evidence-raw-m10-p06b-20261104.list0`).
     - P05 set the precedent: `r3p/20261103T204341Z/reference-compare-cp1.json`.
     - My offline run of `reference-compare.py compare runs/live1 plans/261023-0009-…/reference/r3p` exits 1 with `differingComponents: ["extra"]` and no `--file`s.
     - The `digest-run.digests` breakdown shows ledger, ipc and traces equal, and `extra` differs only in `rc-multiset`. The rc-multiset diff is exactly `targetKey` `0000000202` → `0000000210`, and `ipcTraceUeContextLines` is 0.
   - **Required change:**
     - Commit the compare output into that run directory. `plans/.gitignore:26` already admits `reference-compare*.json`. Add a per-component breakdown under the same name prefix, the harness SHA that computed it, and a note that it was computed offline after the run.
     - Correct the citation at `:116`. The rc-multiset `targetKey` change is R-2's enumerated rc-multiset transform (`plan.md:159`); row 22 is the schedule.
     - Record two step deviations:
       - The "local proof before any VM run" (`:27`, `:48`) ran after M4–M7, on the VM. This is harmless because the result is equal, and stronger, because it covers P05 + P06 + P06b together.
       - Step 5 (`:51`, "no TS xApp decision path") used the full r3p single gate.

2. **(Should; choose the fix phase now, before P08.) The eNB-UEID carries the MeNB UE X2AP ID before DC is established, and this is visible on M7's wire.**
   - **Evidence:**
     - The deviation is stated at `phase-06b-…md:76`. R-4's own reason is "present because DC is established" (`plan.md:193`).
     - In the archived M7 context files (`m7/20261104T093642Z/ns3run/e2-ue-context-*.jsonl`), the eNB lists IMSIs 2 and 3 from seq 1. IMSI 2 is in no en-gNB context until seq 6, and IMSI 3 until seq 3.
     - Row 81 requires the X2AP ID on every eNB-UEID (`check-diff-ledger.md:87`), so the judge itself encodes the deviation.
     - AC14b says "P4 ends fixed … for KPM" (`contract…:105`), and §7 forbids a "listed" end (`:161`).
     - The phase text "Fix to spec at P07 if Stop A′ rules" cannot happen in that order, because Stop A′ follows P08 (`plan.md:76-77`, `:113`).
     - "P3" collides with the contract's item P3 (δ).
   - **Required change:**
     - Relabel the deviation (for example "D-06b-1, minor") and decide the fix phase now, without a user round trip, under the standing fix-to-spec rule.
     - Default: bundle it into P10 with P15, which rebuilds the agent and kpimon anyway. The alternative is P07 if the disk budget allows a kpimon rebuild.
     - Before any code, register a row that changes row 81's eNB conjunct to "present iff the UE is in some en-gNB's ctx(g, s)". Derive this from the en-gNB context files, not from the eNB's own flag, and add one negative each way.
     - The code side: ns-3 adds a DC flag to the eNB `ueContext`, the agent omits the member when DC is not set up, and kpimon's tag formatter handles the absent member. The n6 and Influx form checks follow.
     - At Stop A′, report P4-KPM as fixed, or as fixed with one scheduled residual.

3. **(Should, in P07: the agent is rebuilt there.) A UE that leaves in mid-period drops the whole sample.**
   - **Evidence:**
     - The disclosure is at `phase-06b-…md:105`. The agent keeps only "the latest context set, which each line replaces whole" (`:93`). The harness defines ctx(n, s) per seq (`check-diff-ledger.md:85`).
     - No gate exercises P > T with mobility. P12 runs one gNB with `--e2lteEnabled=false` (`gate-p12-kpm-period.sh:4`, `:123`), and every other gate runs at P = T.
   - **Required change:**
     - The agent encodes each sample with the context valid at its seq: keep the lines keyed by seq until the period is reported.
     - Add a host unit test with a context change in mid-period: all K records are encoded, and the departed UE appears only in its own samples.
     - Withdraw the "P07–P10 must use one sample per period wherever handovers happen" constraint. A gate-configuration rule that hides a defect is a narrowing.

4. **(Should, before P07's first M7 or rung run.) The counter meant to "fail loudly" is not asserted where contexts change.**
   - **Evidence:**
     - Row 98 asserts `samplesNoUeContext` and `ipc.ueContextRejected` only in M6 and P12 (`gate-m6-kpm.sh:148`, `gate-p12-kpm-period.sh:163`).
     - M7 has no `agent_counters_assert`, and the rungs' `agent_c2` reads rc counters only (`ts-rung-lib.sh:155-170`).
     - M7 is the only gate where agents restart and ns-3 must re-send contexts. My read of the final M7 agent logs: the maximum `samplesNoUeContext` and `dropped.encode` over every stats line is 0, across 2–3 counter resets per agent. The same holds for R0 live1.
   - **Required change:** add a ledger row, then the two zero conjuncts. Take the maximum over every stats line, across restarts, in M7 and in each rung's agent check. Replay them offline on the raw M7, R0, R1 and r3p runs. They will pass.

5. **(Should, before the first P07 code commit.) P07 sites with no ledger row.**
   - **Evidence:**
     - R-7 lists `r3p-prepare.py:48`, `:74-79` and `r3p-schedules.py:31-32` (`plan.md:233-235`). P07 changes them (`phase-07-…md:66-67`). No row names `r3p-prepare`, `stub_load` or `trigger_entry`.
     - Row 13 promises an "ordinary P06b/P07 row" for the wire `(imsi, step)` attribution (`check-diff-ledger.md:19`). It does not exist.
     - The pacer replay's UE-identity tuple (`phase-07-…md:48`) has only P02's row 57.
     - The G1 seam-smoke #9 row (`phase-07-…md:77`) is not written yet.
   - **Required change:** write these rows (old → new, why not weaker) before P07 code.

6. **(Should, P07.) The r3p gate is self-contradictory until P07's migration lands whole.**
   - **Evidence:** see Q2. The two failing `.out` files are `checks/r3p_live1_expected_outcomes_step_scoped_late_zero.out:1` and `checks/r3p_live1_wire_requests_equal_handovers_via_target_with_predictor_key.out:1`, and D7 still passes on via-target.
   - **Required change:** land rows 10, 14, 15 and 25 with the TS xApp patch at one harness pin. Run no r3p on a partial migration. State this in P07's work record.

7. **(Should, record fix.) Rows 100 and 101 do not match what they claim.**
   - **Evidence:**
     - Row 101 says "attribution can only become stricter" (`check-diff-ledger.md:107`). In the shared-IP case the old result depended on list order (M7 attempt 1 failed by misattribution), and the new rule passes such runs.
     - Row 100 says the action definition is decoded by `tools/asn1-indep` (`:106`). The ruling (`:113`) and the code (`e2-facts-query.py:434-436`) use tshark's dissector label.
   - **Required change:** append dated notes, and do not rewrite the original text.
     - Row 101: identical to the old rule when no IP is shared; where the old result depended on list order, the node now comes from the E2 Setup identity and is cross-checked against the IP list.
     - Row 100: tshark's label is used, and an undecoded label fails closed.

8. **(Should, now, while the scratchpad still exists.) The decode harness's C-side negative is not committed.**
   - **Evidence:**
     - `tools/kpimon-decode-harness/selftest.sh:19` hard-codes another session's scratchpad and tests only the TimeStamp size. No `lint.sh` line runs it.
     - The records path (rows 83 and 102; `ue_id_lists_equal` in `kpimon-decode-harness-records.c`) has no committed host test.
     - The "later item's X2AP ID changed in re-encoded real M7 messages" negative (`phase-06b-…md:127`) lives in the controller's session scratchpad. The Python judge's counterpart is committed (`p12-records-check.py:361`).
   - **Required change:**
     - Commit that negative as a records self-test. It runs with an extracted kpimon `.so`, and when the `.so` is absent it skips with a clear message, never a silent pass.
     - Make `selftest.sh` require its inputs from the environment, or mark it retired.

9. **(Disclosure classing.) The `ns3.imsi` vendor measurement is an interpretation of R-4, not a contract issue.**
   - **Evidence:**
     - R-4 says "The IMSI stays inside the IPC; the agent uses it only to map sample UEs to their IDs" (`plan.md:198`). The work record quotes "never encoded" (`phase-06b-…md:103`), which is not R-4's text.
     - Rows 85, 86 and 90 registered before code (`56a7092`) that `ns3.imsi` stays (`check-diff-ledger.md:91,92,96`).
     - AC14b forbids only an IMSI carried as a gNB-UEID (`contract…:103`).
     - Changing a pre-registration after its phase starts is PAUSE T3 (`plan.md:139`).
   - **Why no PAUSE is needed:** R-4's sentence sits in the context-channel bullet, and the pre-code rows show retention was planned.
   - **Required change:**
     - Record it as an explicit interpretation with the exact R-4 quote.
     - Tell Stop A′ that, because it follows cp2, its options are "keep through M10" or "remove by amendment".
     - Hand two items to P10: the AC16 lint (`contract…:114`) must classify the `ns3.*` vendor measNames, and P07 must keep the TS xApp off `ns3.*` fields for the UE identity.

10. **(Record.) The integration-boundary wording conflicts with the runs that were made.**
    - **Evidence:**
      - The text says "this phase's pins are never used for a rung run" (`phase-06b-…md:3`; `plan.md:90`).
      - R0 and R1 ran C1 at the P06b pins (`r0/20261104T100125Z`, `r1/20261104T102205Z`, `"mode": "c1"`), and r3p ran single.
    - **Required change:** add a dated note that these are regression evidence and the step-5 cross-check, never R2/R3′ acceptance.

11. **(Ops, the first thing P07 does.) Disk and VM-root headroom.**
    - **Evidence:**
      - Host `/home` fell from 46 GiB to 30 GiB during P06b (`host-disk.tsv`: m4 start 46, p12 end 30; overlay from 41 to 55 GiB allocated). The kpimon rebuild in M3 alone took 45 → 34 GiB. `df` now shows 30 GiB on `/home` and 12 GiB on `/mnt/data`.
      - The dev floor is 20 GiB (`contract…:142`).
      - The VM root went from 77 % to 68 % only after a `docker image prune -f` (`phase-06b-…md:130-132`), against the P12 guard of 75 %.
      - P07 rebuilds rc, the TS xApp and the agent, and runs R2 C1, R3′ C1 and e2i.
    - **Required change:**
      - Project P07's `/home` use before its first VM step. If the projection crosses 20 GiB, plan a revert point or PAUSE for the user. Do not delete anything autonomously.
      - Register the VM dangling-image prune as an ops rule (superseded images built by this plan only).
      - Disclose P06b's prune at Stop A′ as an interpretation of §5 ("Nothing is deleted autonomously"), by analogy with the plan's image rule (`plan.md:130`).

## Q3. Disclosures for Stop A′: are they complete and correctly classed?

| Disclosure | Class | Block the exit? | Fix before P07? |
|---|---|---|---|
| `ns3.imsi` stays | An interpretation of R-4, consistent with the contract (finding 9) | No | No. Record the exact quote, and keep the TS xApp off it in P07 |
| MeNB UE X2AP ID without DC | A real spec deviation, live in M7 (finding 2) | No | Decide the phase now (default P10 with P15); fix before Stop A′'s P4 accounting where possible |
| UE leaving in mid-period | A latent agent defect in this phase's code, not exercised by any gate (finding 3) | No | Yes, in P07 (agent rebuilt anyway) |
| e2i association-based mapping | Harness robustness, not a product choice | No | Yes, before P07's e2i run: reuse `assoc_node_of`, with a row first. Turn the Stop A′ "user question" (`phase-12-…md:66`) into a disclosure |
| Stale `selftest.sh` | Old debt (commit `3159266`) | No | Fix now with finding 8 |
| "Later item differs" negative only in the scratchpad | A test-coverage gap that evaporates with the session | No | Commit now (finding 8) |
| MME UE S1AP ID = IMSI (ns-3 construction) | Correctly disclosed; conjunct (c) checks it | No | No |

Missing from the list:
- the P06b VM image prune (finding 11);
- the step-2 and step-5 sequencing deviations (finding 1);
- the GUMMEI values {00F110, 0001, 01}, which are chosen constants because ns-3 models no GUMMEI. Say so in the standards ledger.

## Q4. Hand-offs to P07, and what P07 must do first

1. **First:** the disk projection and the VM-root rule (finding 11). Then the missing ledger rows (finding 5), the M7 and rung counter row (finding 4), and the e2i association row.
2. **Rows 88–95** (stub, fixtures, scenario `:17`, predictor, r2 stub/schedule/table, `send-rmr`/injector, rmr-peer self-test): implement them with the TS xApp change. Rows 10, 14, 15 and 25 land at the same pin (finding 6).
3. **TS xApp reading `ueId` from Influx:**
   - Use in-cluster credentials (T7). Re-measure T_ctl, because the Influx read sits inside the lock-step window.
   - The `ueId` tag is MN-scoped: a UE has the same tag on every en-gNB. Define which row counts as serving (the latest seq from the node that currently reports the UE). Around an SN change, rows from both gNBs carry the tag.
   - Make "reads it from Influx" non-vacuous on the wire. The anomaly string already encodes every en-gNB-UEID member, so add a negative: a well-formed `ueId` with no Influx row must give zero RIC CONTROL requests on the wire. Judge on the wire, not on logs.
   - Never use `ns3.*` fields for the UE identity.
4. **The AD stand-in's source:**
   - The P06b design says the injector reads the `ueId` from Influx (`phase-06b-…md:35`). P07 resolves IMSI → `ueId` through the context files and then confirms the key in Influx (`phase-07-…md:66`).
   - Take P07's route, because it survives a later `ns3.imsi` removal. Amend `:35` with a dated note, and state that the stand-in is harness-side, while the TS xApp's AC14 rule applies only to the TS xApp.
5. **Via the source en-gNB:**
   - Remove the eNB's transitional RC acceptance and Style 3/1 from RAN function 3 (P06 review, Q5 item 1).
   - Re-encode the N5-form negative as Style 5/3.
   - Pass `--facts` (the rung's existing `$label-sub-facts.json`) to every `kpm_moves` call, so a rung with an agent restart attributes frames by association instead of failing closed.
6. **The fork fixes this review recommends for P07:** the per-seq context in the agent (finding 3). Optionally the eNB DC flag in ns-3, if the controller chooses P07 for finding 2.

## Q5. Scope guard

No material mismatch was found against the locked contract, and no PAUSE T3 is needed.
- AC14b's TS xApp half lands in P07, as pre-registered.
- The `ns3.imsi` question is an interpretation backed by rows registered before code.
- Two items need accounting rather than a pause:
  - the eNB X2AP residual against "P4 ends fixed for KPM";
  - the VM image prune against §5's "Nothing is deleted autonomously".
  Both should go to Stop A′ with evidence, and the X2AP residual should have a scheduled fix.

## What to avoid

- Rerunning r3p on the VM to "get a PASS" before P07: it cannot pass (finding 6).
- Keeping the "one sample per period wherever handovers happen" rule as a test constraint instead of fixing the agent.
- Rewriting the text of rows 100 or 101. Append dated notes.
- Pruning, or deleting snapshots or overlays, to stay above the 20 GiB floor without a user ruling.
- Letting the P07 TS xApp patch build the RC UE ID by parsing the anomaly string alone. That would satisfy the wire while bypassing AC14b's "reads it from Influx".

## Work checklist

1. Write and commit `reference-compare-cp1.json` and its breakdown for `r3p/20261104T082155Z`. Fix the `:116` citation, and record the step-2 and step-5 deviations (finding 1).
2. Update the resume card (it still reads "P06 DONE; next P06b" at `plan.md:37-38`, with P06 fork SHAs at `:47`), the phase table row (`plan.md:74`, "pending") and the exit record.
3. Append the dated notes to rows 100 and 101 and to `phase-06b-…md:3`, `:35`, `:76` and `:103` (findings 2, 7, 9, 10).
4. Commit the decode-harness records negative, and fix or retire `selftest.sh` (finding 8).
5. Record the fix phase for D-06b-1 (default P10 with P15) and its row plan (finding 2).
6. Before P07 code, write the ledger rows: the P07 sites (finding 5), the counter conjuncts (finding 4) and e2i association.
7. Before P07's first VM step, write the disk projection and the VM-root prune rule (finding 11).

## Success metrics

- `git ls-files` lists a `reference-compare*.json` in `r3p/20261104T082155Z` showing ledger, ipc and traces equal to cp1, and `extra` differing only in the rc-multiset `targetKey`.
- P07's first M7 and every rung carry a passing `samplesNoUeContext = 0` conjunct taken over every stats line.
- P07's r3p and R2 C1 go green at one harness pin. No r3p verdict exists on a partially migrated pin.
- A committed agent unit test shows a mid-period departure encoded with all K records.
- Stop A′'s P-table shows P4-KPM as fixed, or as fixed with D-06b-1 scheduled, and the `ns3.imsi` interpretation quotes `plan.md:198`.
- `/home` never goes below 20 GiB during P07 without a recorded user ruling.

## Assumptions

| Assumption | Confidence | What would change the answer |
|---|---|---|
| The raw files in the worktree are the ones archived (`.list0` holds 4,233 entries, matching the work record) | High | A mismatch would make my offline recomputations non-authoritative. Re-run them from the archive |
| "Secondary RLC set up" at the en-gNB marks DC established (ns-3 `e5b02094`, per `phase-06b-…md:91`) | Medium-high | If ns-3 sets up the SN RLC before the 3GPP SgNB addition completes, the M7 pre-DC window would be shorter, but it would not disappear |
| E2SM v07.00 §6.2.2.6 ties the MeNB UE X2AP ID to DC. I did not re-read it: vault key `QW6VJ83M` returns 404. An O-RAN WG1 text (`9FFQ6JG2`) says it is "reported when the UE operate in DC with EPC" | Medium | If the clause allowed the ID for any UE, finding 2 would drop to a note |
| P07 does not rebuild kpimon | Medium-high (`phase-07-…md:74` Files) | If P07 rebuilds kpimon anyway, do finding 2 in P07 |
| Testbed `2d256d2` (agent) is an ancestor of the pinned `89d45af` | Medium (the agent image tag `ns3-e2-agent:89d45afb8cf9` is named after the pin) | If not, the codec-probe host results would describe a different agent tree |

## Unresolved questions

1. User, at Stop A′: keep the `ns3.imsi` vendor measurement through M10 (the default, consistent with the contract), or remove it by amendment?
2. User, at Stop A′: confirm that D-06b-1 (MeNB UE X2AP ID without DC) is fixed in P10 together with P15, or require it before cp2 (in P07).
3. Was the Testbed's `compare-codec-probe.py` updated to read `ueIds` after row 83? The work record (`phase-06b-…md:93`) says it "waits". This cannot be checked without the fork.
4. Should the GUMMEI constants be recorded as chosen values ("ns-3 models no GUMMEI") in the standards ledger, or cited elsewhere?

Status: DONE
Summary: P06b is GO-WITH-CHANGES. The codec, context and Influx exits are met, R2/R3′ are correctly deferred, and no check was weakened. The one must-fix is to commit the offline-verified checkpoint-1 byte-compare. The eNB X2AP-without-DC deviation and the agent's mid-period-departure defect need scheduled fixes, and P07 must start with missing ledger rows, M7/rung counter checks and a disk projection.

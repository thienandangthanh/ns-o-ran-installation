# P6 draft: user rulings R1–R4 and Q5 applied (2026-11-07)

This is still a draft. Nothing was committed or pushed, no VM was touched, and no VM gate was run. I did not touch `scripts/vm/` or `~/.cache/ns-o-ran-frozen-harness/`.

Inputs:
- the rulings: `decisions-261107-0045` item 4;
- the debate's recommended set, its cleanup list, and its missed issues 2–6: `brainstorm-261106-2359`;
- ledger rows 147 and 151 with their 2026-11-07 amendments.

## Result

- **Shipped lint:** 0 findings. The only expected failures (XFAIL) are gnb cell 34 and 35, which carry pendingFix "P9".
- **`--self-test`:** passes. It now runs the shipped pair, a new passing control, and 42 must-fail fixtures.
- **`--require-no-pending`:** fails only on the two P9 rows.
- **`lint.sh` and `kpimon-guard-selftest.sh`:** both exit 0.
- **3GPP names:** no map row passes under a 3GPP name. The only rows whose `kpm` is not `ns3.*` are the two pending rows:
  - gnb cell 34 (measId 34), `DRB.PdcpSduVolumeUL`, pendingFix P9
  - gnb cell 35 (measId 35), `DRB.PdcpSduVolumeDL`, pendingFix P9

## Files changed (all uncommitted)

All six are in the Testbed, under `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/`. I made no superproject edit in this round: `kpimon.sh` and `kpimon-guard-selftest.sh` needed no change, because no file was added to or removed from `KPIMON_TESTBED_PATHS`.

| File | Change |
|---|---|
| `ns3_e2_agent/schema/kpm-measurement-clauses.v1.json` (307 lines) | R1 doc text; new interpretations; TB name form; eNB `RRC.ConnMean` set to `holds: false` with a `reAudit`; three new 32.425 entries; Q5 wording; plan references removed; ns-3 sources moved to the 74c165f1 pin |
| `ns3_e2_agent/tests/kpm-clause-registry.py` (160 lines) | Requires an explicit `gaps: []` on every check that holds; `gaps` must be a list; ledger references removed from docstrings |
| `ns3_e2_agent/tests/lint-metric-map.py` (298 lines) | Conjunct (3) now states the R1 rule. A row whose check holds without `gaps: []` fails at row level too. Ledger references removed. |
| `ns3_e2_agent/tests/lint-metric-map-selftest.py` (211 lines) | Passing control; fixtures (a)–(c); eNB legacy-name fixtures; TB fixtures moved; ledger references removed |
| `ns3_e2_agent/schema/metric-map.v1.json` | Five rows changed (below); `pendingFix` doc line reworded |
| `install_patch_files/xApps/kpimon-go/control/enb-kpm-measurements.json` | Regenerated from the map's eNB rows: cell measId 8 is now `ns3.cuCp.meanRrcUes` (10 renames vs HEAD in total) |

The map changes were checked by script. The only fields that changed are `kpm`, `unit`, `clause` and `layer`, and every `order` and `measId` is unchanged.

| Row | Change |
|---|---|
| enb cell 8 (measId 8) | `RRC.ConnMean` → `ns3.cuCp.meanRrcUes`; clause `vendor`; unit `count` → `UEs`; legacyName stays `RRC.ConnMean` |
| enb cell 5 | unit `bytes` → `kbit/period (constant 0)` |
| enb cell 6 | unit `bytes` → `kbit/period` |
| enb ue 10 | unit `bytes/period` → `kbit/period` |
| gnb ue 29 `ns3.cuUp.txPdcpPduNrRlc` | layer `PDCP` → `RLC` (debate cleanup 8; it is an NR RLC PDU count, like gnb ue 28) |

## Per item

1. **R1 strict: done.**
   - The registry doc now states the count-once rule. Only the counting instant may shift: by at most 1 slot for a count, or by 1 of the clause's own sampling steps for a sampled value. The E2 report period is never a sampling step. The text labels this allowance as the project's tolerance, not a 3GPP number.
   - A residual is now defined as an event counted once but, because of that shift, in the adjacent period. This uses the debate's count-conserving wording.
   - `check_registry` now rejects three cases on a check that holds: no `gaps` key, a non-empty `gaps`, and a `gaps` that is not a list.
   - `row_findings` also fails such a row, so the row is not only flagged at registry level.
2. **eNB `RRC.ConnMean`: done.**
   - The row is renamed to `ns3.cuCp.meanRrcUes`. The lint's uniqueness rules allow this: it is one name with one type (INTEGER) across the map, the name is unique within enb/cell, and the vendor-name rule passes.
   - The 32.425 entry now has `holds: false`. Its reason starts "Attach bound not yet proven by a run". It cites:
     - LTE control errors being on by default (`lte-spectrum-phy.cc:222-227`);
     - the 15 ms connection-request timeout (`lte-enb-rrc.cc:3177-3183`).
   - The old attach residual became the reason, so `residuals: []`.
   - New `reAudit`: the check must be judged again when scenario-zero's `ns3::MmWaveHelper::UseIdealRrc` is set false (it is true at `scenario-zero.cc:492`). I worded the trigger as that invariant, with no AC or checkpoint id (item 6).
3. **R2 renames: verified present.**
   - gnb ue 27 is `ns3.du.rlcPduSizeOverDelayDl` (legacy `DRB.UEThpDl.UEID`).
   - gnb cell 33 is `ns3.cuCp.meanRrcUes` (legacy `RRC.ConnMean`).
   - gnb cell 26 is `ns3.du.numActiveUes` (legacy `DRB.MeanActiveUeDl`).
4. **R4 unit texts: done** (table above). I checked the evidence at 74c165f1 `src/lte/model/lte-enb-net-device.cc`:
   - `:1110-1111`: txBytes is converted with `* 8 / 1e3 // in kbit`;
   - `:1112`: `cellDlTxVolume += txBytes`;
   - `:1134`: the LTE RLC bytes are converted to kbit;
   - `:1233-1234`: `FillCuUpValues(plmId, 0, cellDlTxVolume)`, so UL is constant 0.
5. **Q5: done.**
   - Neither the registry nor the lint had an explicit S-SN→T-SN exclusion. The Q2 exclusion came in only through the "user ruling Q2" citations in the reasons of the two pending entries.
   - Both reasons now state the invariant instead. The DL reason says `DRB.PdcpSduVolumeX2DL` counts, at the receiving cell, both the PDCP PDUs the MN sends over X2 and the data a source SN forwards to it over X2 during an SN change.
   - The UL reason says the X2UL counter uses the same counting rule.
   - `pendingFix: "P9"` is kept on gnb cell 34 and 35, and on their registry checks.
6. **Non-mandated references: removed.**
   - "ledger row 147 (n)" is gone from the lint, the registry module, the self-test and the registry.
   - "user ruling Q2, 2026-11-06 19:52" is gone from both reasons, so it no longer appears in any printed XFAIL line.
   - "outside M10" is gone from the TB reasons. They now say: "A correct counter counts per cell on transmission by the gNB; its counting site is not chosen here" (debate cleanup 2).
   - "P9 fixes it" now reads "the fix that pendingFix names".
   - The only plan id left is the mandated value "P9": in `PENDING_ALLOWED`, in the pendingFix fields, and as that value in the docstring and map doc line.
7. **eNB rename reasons: done.** There are three new 32.425 V19.0.0 entries. I read each page as a PDF page of attachment 3IK5R7U8, and the units come from KPM 7.9.1 p.14. All three have `holds: false`.
   - **`DRB.PdcpSduVolumeDl`** (§4.4.7.1 p.58; Kbit per KPM 7.9.1; INTEGER; `_Filter` total under `interpretations.filter`).
     - Value check: enb ue `/cuUp/DRB.PdcpSduVolumeDl_Filter.UEID`.
     - Reason: the value counts PDCP PDU bytes, the PDCP header included (`mc-enb-pdcp.cc:259` before the traces at `:221` and `:238`). The clause counts SDU bits, and the map row is REAL.
   - **`DRB.PdcpSduBitrateDl`** (§4.4.1.1 p.48; kbit/s; INTEGER; templates `[["qci"]]`; total false, because item e) gives only `.QCI` and item d) names the sum with `.sum`).
     - Value check: enb ue `/cuUp/DRB.PdcpSduBitRateDl.UEID`.
     - Reason: PDU bits, REAL, a `.QCI` sub-counter that KPM labels, and the legacy name misspells `Bitrate`.
   - **`DRB.PdcpSduDelayDl`** (§4.4.3.1 p.52; ms; INTEGER; templates `[["qci"]]`; total false).
     - Value checks: enb cell `/cell/cuUp/DRB.PdcpSduDelayDl` (an unweighted mean of per-UE means) and enb ue `/cuUp/DRB.PdcpSduDelayDl.UEID`.
     - Reasons: 0.1 ms, REAL, `.QCI`.
   - The old self-test fixture "3GPP name with no entry" used `DRB.PdcpSduDelayDl`, which now has an entry. It now uses `Tot.PdcpSduNbrDl`.
8. **TB.TotNbrDl bare name: done, but with a deviation from the literal task wording.**
   - I set `nameForms.total` to **false**, following the debate's final ruling C5 and cleanup 1 ("the bare-name permission is removed now").
   - `totalBasis` records that item e) p.112 lists only `TB.TotNbrDl.X`. It also records that reading the bare name as the SISO total would go beyond item e), and that a per-cell TB counter must settle the name first.
   - I did not keep `total = true` with a note. Keeping it would leave a permission the user-adopted debate removed, and the stricter setting only adds failures.
   - The "TB drops at SN change" fixture moved to `TB.TotNbrDlInitial`, as cleanup 1 asks. A new fixture shows that the bare `TB.TotNbrDl` fails the grammar check.
   - If the orchestrator wants `total: true` plus a note instead, it is a one-field change and the bare-name fixture's expected text changes with it.
9. **ns-3 citations: done.** Every `ns-3-mmwave-oran@ea6e46f6` source is now `@74c165f1`, and none of the old pin is left.
   - Between ea6e46f6 and 74c165f1, only `src/mmwave/model/mmwave-enb-net-device.cc` changed among the cited files. `git diff --quiet` is clean for `src/lte`, `src/mmwave/helper`, `mmwave-spectrum-phy.cc`, `mmwave-phy-mac-common.cc` and `scratch/scenario-zero.cc`.
   - I moved the lines with a difflib line map between the two blobs. Every cited range maps 1:1 to unchanged lines, and I spot-checked the content at the new lines.
   - The map rows' `origin` fields cite older pins (8c42089d, ba954440, 5f547ae). That is HEAD text the draft did not add, so I left it untouched.
10. **Self-test: done.**
    - (a) `holds-true-without-a-gaps-key`, (b) `holds-true-with-gaps` and (c) `enb-RRC.ConnMean-under-its-3GPP-name` were added.
    - (d) was **skipped**: the lint does not check the unit of `ns3.*` rows (conjunct (6) checks the clause, the layer and the name only).
    - Eight fixtures were anchored on the eNB `RRC.ConnMean` row, which used to pass. They now start from a **passing control**: that row put back under `RRC.ConnMean`, with its check set to `holds: true` and `gaps: []`. The control itself must give 0 findings, so each of those fixtures fails only through its own change.

Other debate cleanups applied, all inside my files:
- gnb ue 29 layer set to RLC (cleanup 8).
- `interpretations.kbitRounding` (cleanup 10). The current pending rows round with `(bits + 500) / 1000` (`mmwave-enb-net-device.cc:835-837`).
- The interpretations that the row-147 amendment lists are now in the registry: `kpmUnitMatch`, `documentScope` and `vendorNames`, next to the existing `filter`.

## Citation moves (`src/mmwave/model/mmwave-enb-net-device.cc`, ea6e46f6 → 74c165f1)

| Entry / check | Old | New |
|---|---|---|
| TB.TotNbrDl gnb cell | 1158-1160,1339 | 1128-1130,1309 |
| TB.TotNbrDlInitial gnb cell | 1163-1165,1339 | 1133-1135,1309 |
| RRC.ConnMean (28.552) gnb cell | 602,898-906,908-922,933,1047 | 603,883-891,893-907,918,1017 |
| DRB.PdcpSduVolumeDL / UL gnb cell | 672-708,834-836 | 673-709,835-837 |
| QosFlow.PdcpPduVolumeDL gnb cell | 1167-1169 | 1137-1139 |
| QosFlow.PdcpPduVolumeDL gnb ue | 710-725,819-821 | 711-726,820-822 |
| RRU.PrbDl gnb cell | 1185-1207,1349,1371,1374-1375 | 1155-1177,1319,1341,1344-1345 |
| RRU.PrbDl reason prose | :1148, :1207 | :1118, :1177 |
| DRB.EstabSucc gnb ue | 947,1034-1036 | 932,1004-1006 |

These files kept their line numbers and were only re-qualified to the new pin:
- `lte-enb-rrc.cc` 5582-5612,5892-5900 and the bare `:5869`;
- `mmwave-phy-trace.cc` 242-248 / 250-254 / 262 / 398-422;
- `mmwave-spectrum-phy.cc` 431-437 and 707-732;
- `mmwave-phy-mac-common.cc` 94-95;
- `lte-enb-net-device.cc` 1041,1283-1306,1318,1354 and 1108-1157,1196-1198;
- `scenario-zero.cc` 525,527.

## Commands (run from the Testbed `.../Near-Real-Time-RIC/ns3_e2_agent` unless noted)

| Command | Exit |
|---|---|
| `python3 -I tests/lint-metric-map.py --registry schema/kpm-measurement-clauses.v1.json schema/metric-map.v1.json --kpimon-enb ../install_patch_files/xApps/kpimon-go/control/enb-kpm-measurements.json` | 0. Findings 0; rowsFailingClauseChecks 0; 2 XFAIL (gnb cell 34/35 "pending P9") |
| `python3 -I tests/lint-metric-map.py --self-test` | 0. Shipped pair ok, passing control ok, 42/42 fixtures ok |
| `python3 -I tests/lint-metric-map.py --require-no-pending schema/metric-map.v1.json` | 1. 4 findings, all on gnb cell 34/35 (the value check plus pendingFix set) |
| `bash scripts/gates/kpimon-guard-selftest.sh` (superproject) | 0. 12 cases ok, including clause-registry-edit and registry-module-edit |
| `bash scripts/gates/lint.sh` (superproject) | 0. "lint: ok". Two SKIP lines are unrelated and were present before: the kpimon codec self-tests need KP_SO/KP_INC and KP_E2SM/TS_ORIG. |
| `git -C ns-3-mmwave-oran diff --quiet ea6e46f6 74c165f1 -- src/lte src/mmwave/helper …` | 0 (those files are unchanged) |

## Not done / deviations

- Fixture (d) was skipped, because the lint has no unit check for `ns3.*` rows.
- TB.TotNbrDl is set to `total: false`, not `true` with a note (item 8 above).
- I did not edit the ledger, the decision logs or the P6 amendment text: they are outside my file list. That covers debate cleanup 6 (the 2246 note) and cleanup 9 (the ad-cell and vendor-rule disclosure).
- The wire impact is the same as in the first draft, plus one more name. Indications carry measIds only, so the indication bytes and the KPM T/T golden do not change. The map's sha8 and the eNB kpimon list both change again.

## Unresolved questions

1. Item 8: is `nameForms.total: false` for TB.TotNbrDl accepted, given the debate's C5 and the literal wording "total = true … as a registry note"?
2. The 32.425 bitrate and delay entries read `.sum` as "no bare-name total" (`total: false`). A later counter that reports a QCI sum would need a ruling on whether `.sum` goes on the wire or the bare name with noLabel is used.

## Codex round 1 fixes (2026-11-07)

Codex's adversarial review raised three medium findings, and all three are accepted. Each fix is in the files I already owned. I again made no commit, push or VM change, and did not edit `scripts/vm/`, the frozen harness or `lint.sh`.

1. **Null `clause` or `layer` passed the lint.**
   - **Bug:** conjunct (1) checked only that the field was present, and the clause and layer comparisons skipped a null value.
   - **Fix in `lint-metric-map.py` `row_findings`:**
     - (1) now requires both fields to be non-empty strings.
     - On 3GPP rows, `clause` and `layer` are compared with the registry entry even when they are null.
     - On `ns3.*` rows, clause must equal `vendor` and layer must be a known layer or `none`, also unconditionally.
     - A `kpm` that is not a string is reported as a finding instead of raising.
   - **New fixtures:** null clause and null layer on the pending row gnb cell 35; null clause and null layer on the passing control; an empty clause on an `ns3.*` row. These now fail with "(1) fields". On the pending row they are not hidden as XFAIL, because (1) is not the value-check conjunct.
2. **Value checks ignored `xform`.**
   - Every registry value check now carries an `xform` field, and all 15 are `"none"`. A script checked that each check's xform equals the xform of the shipped rows with the same kind, list and src.
   - The validator requires `xform` and only accepts `none` or `ns_to_ms_floor`.
   - A new row conjunct, "(3) xform", fails when the row's xform differs from its check's xform. It is a separate conjunct so that it is never swallowed by a pending row's XFAIL.
   - The registry doc line now says value checks are given per map row source and xform.
   - **New fixtures:** an xform-only change on the passing control (`ns_to_ms_floor`); a check with no `xform`; a check with an unknown `xform`.
3. **A malformed registry crashed the lint.**
   - **`check_registry` in `kpm-clause-registry.py`** now checks types before it reads anything:
     - the registry, `documents`, `slotKinds`, `families`, `placeholders` and `entries` containers;
     - each entry and each value check (`ENTRY_FIELDS` and `CHECK_FIELDS` are now name → type maps);
     - `owningNode` items, template items, `legacyName.v17` and `source` items;
     - every slot-kind pattern must compile.
   - **New `evaluate()` in `lint-metric-map.py`:** when the registry check finds anything, it prints those findings and "registry has findings: clause checks skipped", skips the clause conjuncts, and exits 1.
   - **`main()`** reports a map or registry that cannot be read or parsed as one FAIL line and exits 1, without a traceback.
   - **The self-test** now calls the lint's `evaluate()`. It wraps every fixture so that any exception fails that fixture, and a mutation may return a replacement (doc, registry) tuple.
   - **New fixtures** check that each of these cases gives findings and no exception:
     - a value check missing `holds`, `src`, `reason` or `xform`;
     - `holds` that is not a boolean, or `source` that is not a list;
     - a value check that is not an object;
     - an entry without `name`, or an entry that is not an object;
     - `valueChecks` that is not a list, `nameForms` that is null, or `owningNode` that contains a non-string;
     - `entries`, `slotKinds`, `families` or `documents` that is null;
     - a registry that is not a JSON object;
     - a check that the clause conjuncts are skipped when the registry has findings.
   - **CLI check by hand:**
     - a registry with `holds` removed: exit 1, 2 FAIL lines, no traceback;
     - `entries: null`: exit 1, no traceback;
     - a file that is not JSON: exit 1 with "FAIL cannot read the map or the registry", no traceback.

### Files touched in this round

- `ns3_e2_agent/tests/kpm-clause-registry.py` (now 218 lines)
- `ns3_e2_agent/tests/lint-metric-map.py` (now 321 lines)
- `ns3_e2_agent/tests/lint-metric-map-selftest.py` (now 266 lines)
- `ns3_e2_agent/schema/kpm-measurement-clauses.v1.json`: added `xform` to the 15 value checks and changed one doc line

The map and the kpimon eNB list did not change in this round.

### Acceptance re-run

| Command | Exit / result |
|---|---|
| shipped lint with `--registry`, `--kpimon-enb` | 0. Findings 0, rowsFailingClauseChecks 0, 2 XFAIL (gnb cell 34/35, pending P9) |
| `--self-test` | 0. Shipped pair ok, passing control ok, 67/67 fixtures ok (42 from before plus 25 new) |
| `--require-no-pending` | 1. 4 FAIL lines, all on gnb cell 34/35 |
| kpimon eNB list vs the map's eNB rows | equal, checked both by the lint (`--kpimon-enb`) and by a separate script |
| rows whose `kpm` is not `ns3.*` | only gnb cell 34 `DRB.PdcpSduVolumeUL` and gnb cell 35 `DRB.PdcpSduVolumeDL` (pendingFix P9) |
| `bash scripts/gates/kpimon-guard-selftest.sh` | 0. 11 cases ok. **Correction:** the first part of this report said 12 cases; both runs have 11. |
| `bash scripts/gates/lint.sh` | 0, "lint: ok". The same two SKIP lines as before (KP_SO/KP_INC, KP_E2SM/TS_ORIG). |

I did not re-run the fixtures against the lint as it was before the fix, because there is no saved copy of that uncommitted version. Instead, each new fixture asserts the exact finding text that only the new code produces.

## Codex round 2 fixes (2026-11-07)

Codex's follow-up raised two more medium findings, and both are fixed. I kept the same constraints as before: no commit, push or VM change, and no edit to `scripts/vm/`, the frozen harness or `lint.sh`.

1. **A missing value check could hide under a pendingFix.**
   - **What Codex showed:** on gnb cell 35, change src to `/cell/cuUp/DRB.PdcpSduVolumeUL` and xform to `ns_to_ms_floor`. The lint then exited 0 with 2 XFAIL, because "no value check" was classed as the value-check conjunct and the pendingFix waived it.
   - **Fix in `lint-metric-map.py`:**
     - A missing check is now its own conjunct, "(3) value check", which a pendingFix never waives.
     - A new `matched_check()` finds the row's own check: its entry in the row's document, with the same kind, list and src.
     - `strict()` gives XFAIL only when every finding is the value-check conjunct **and** the matched check exists, has the row's xform, and holds false.
     - A pendingFix on a row whose matched check holds is now a finding: "pendingFix P9 is stale: the row's value check holds; remove the marker". The existing fixture "pendingFix-row-that-passes" now expects that text.
     - Docstring (8) states the rule.
   - **New fixtures:**
     - `pending-row-with-another-src-and-xform` (Codex's exact case);
     - `pending-row-with-another-xform`;
     - `pending-entry-without-value-checks`, where the pending entry's `valueChecks` is `[]`.
   - **CLI check:** Codex's mutated map now exits 1 with "FAIL gnb/cell/35/DRB.PdcpSduVolumeDL: (3) value check: no value check for gnb/cell /cell/cuUp/DRB.PdcpSduVolumeUL".
2. **Some slot-kind patterns crashed the registry check.**
   - **Fix in `kpm-clause-registry.py`:** `check_registry` now catches any `Exception` from `re.compile`, not only `re.error`, and reports it as "slot kind X pattern does not compile: <ExceptionType>: <message>". Under Python 3.14, `a{4294967296}` raises OverflowError and 1,000 nested parentheses raise RecursionError. With the registry finding present, the clause checks are skipped as before.
   - **New fixtures:** `slot-kind-pattern-overflow` and `slot-kind-pattern-too-deep`. Each must produce its diagnostic, and the self-test fails any fixture that raises an exception.

### Files touched in this round

- `ns3_e2_agent/tests/lint-metric-map.py` (now 339 lines)
- `ns3_e2_agent/tests/kpm-clause-registry.py` (218 lines)
- `ns3_e2_agent/tests/lint-metric-map-selftest.py` (now 283 lines)

The map, the registry JSON and the kpimon eNB list are unchanged in this round.

### Acceptance re-run

| Command | Exit / result |
|---|---|
| shipped lint with `--registry`, `--kpimon-enb` | 0. Findings 0, rowsFailingClauseChecks 0, 2 XFAIL (gnb cell 34/35, pending P9) |
| `--self-test` | 0. Shipped pair ok, passing control ok, 72/72 fixtures ok (67 from before plus 5 new) |
| `--require-no-pending` | 1. 4 FAIL lines, all on gnb cell 34/35 |
| kpimon eNB list vs the map's eNB rows | equal |
| rows whose `kpm` is not `ns3.*` | only gnb cell 34 `DRB.PdcpSduVolumeUL` and gnb cell 35 `DRB.PdcpSduVolumeDL` (pendingFix P9) |
| `bash scripts/gates/kpimon-guard-selftest.sh` | 0. 11 cases ok |
| `bash scripts/gates/lint.sh` | 0, "lint: ok". The same two SKIP lines as before (KP_SO/KP_INC, KP_E2SM/TS_ORIG). |

## Codex round 3 fixes (2026-11-07)

Codex round 3 raised three medium findings and one test gap, and all four are fixed. The same constraints held: no commit, push or VM change, and no edit to `scripts/vm/`, the frozen harness or `lint.sh`.

1. **Duplicate checks were resolved by array order.**
   - **Fix in `kpm-clause-registry.py`:** `check_registry` now rejects two cases as registry findings:
     - a second value check with the same (kind, list, src) inside one entry;
     - a second entry with the same (document, name).
   - Either finding skips the clause checks, so no verdict depends on which copy comes first in the array. `RRC.ConnMean` legitimately appears in both 28.552 and 32.425; those are different documents, so the rule allows it.
   - **New fixtures:**
     - a holding duplicate of the pending DL check, placed last and placed first;
     - a failing duplicate of the passing-control check, placed last and placed first;
     - a duplicated 32.425 `RRC.ConnMean` entry.
2. **A trailing dot passed the name grammar.**
   - **Fix:** `match_entry` returns no suffix tokens only when the name is exactly the entry name. So `X.` yields `['']`, and `suffix_findings` reports "name has an empty suffix component (a leading, trailing or doubled '.')".
   - **New fixtures:** `RRC.ConnMean.` on the passing control, and `DRB.PdcpSduDelayDl..9`.
3. **Map containers were not validated before traversal.**
   - **Fix in `lint-metric-map.py`:** a new `map_findings()` checks, before any traversal:
     - that the map is a JSON object;
     - that `rows` is a list;
     - that every row is an object;
     - that every row field the checks read has the right JSON type (`ROW_TYPES`; `order` and `measId` must be integers, not booleans).
   - If it finds anything, `evaluate()` reports those findings plus "map has findings: structural and clause checks skipped". `main()` then also skips `--samples`, `--kpimon-enb` and the row summary.
   - **New fixtures:** map not an object; `rows` null; `rows` not a list; a null row; a non-object row; `kpm` null; `order` a boolean; and a check that the other checks are skipped.
   - **CLI check:** a map with `rows: null` exits 1 with two FAIL lines and no traceback.
4. **Test gap: a src-only `matched_check` passed every fixture.**
   - **Why it survived:** `row_findings` looks up the row's check itself and reports a missing one. So a `matched_check` that matched by src only could change only the XFAIL and stale decisions, and no fixture exercised those against a decoy.
   - **New fixtures that kill it:**
     - two rows sharing one src in different lists, with the UE-list check placed first and placed last; each row must be judged by its own list's check;
     - a check with the right src but another list or another kind, on the passing control;
     - the pending DL row's only matching check placed in another document's entry;
     - four decoy fixtures, where a check with the same src sits in another list of the same entry or in an earlier 32.425 entry:
       - two expect "pendingFix P9 is stale", because the row's own check holds and the decoy fails;
       - two are positive fixtures: the row's own check fails and the decoy holds, and the run must give no finding and exactly 2 XFAIL.
   - **Self-test harness changes:** `want=None` now means "no finding and exactly 2 XFAIL". An exception inside a fixture's mutation now fails that fixture instead of aborting the self-test.

### Mutation check (on scratch copies; the tree was not edited)

I applied each mutant below to a copy of the tests and schema, ran `--self-test`, and counted the fixtures that failed. Every mutant was caught.

| Mutant | Fixtures that catch it |
|---|---|
| `value_check` matches by src only | 6 |
| `matched_check` scans every entry by src only (Codex's regression) | 4 |
| `matched_check` matches by src only within the entry | 2 |
| duplicate-check rule removed | 4 |
| old trailing-dot parse restored | 1 |
| map validation removed | 8 |

### Files touched in this round

- `ns3_e2_agent/tests/kpm-clause-registry.py` (now 232 lines)
- `ns3_e2_agent/tests/lint-metric-map.py` (now 372 lines)
- `ns3_e2_agent/tests/lint-metric-map-selftest.py` (now 386 lines)

The self-test file is long because it is mostly a table of fixtures, so I did not split it. The map, the registry JSON and the kpimon eNB list did not change in this round.

### Acceptance re-run

| Command | Exit / result |
|---|---|
| shipped lint with `--registry`, `--kpimon-enb` | 0. Findings 0, rowsFailingClauseChecks 0, 2 XFAIL (gnb cell 34/35, pending P9) |
| `--self-test` | 0. Shipped pair ok, passing control ok, 96/96 fixtures ok (72 from before plus 24 new) |
| `--require-no-pending` | 1. 4 FAIL lines, all on gnb cell 34/35 |
| kpimon eNB list vs the map's eNB rows | equal |
| rows whose `kpm` is not `ns3.*` | only gnb cell 34 `DRB.PdcpSduVolumeUL` and gnb cell 35 `DRB.PdcpSduVolumeDL` (pendingFix P9) |
| `bash scripts/gates/kpimon-guard-selftest.sh` | 0. 11 cases ok |
| `bash scripts/gates/lint.sh` | 0, "lint: ok". The same two SKIP lines as before (KP_SO/KP_INC, KP_E2SM/TS_ORIG). |

## Codex round 4 fixes (2026-11-07)

Codex round 4 left two medium gaps, and both are fixed. I kept the same constraints: no commit, push or VM change, and no edit to `scripts/vm/`, the frozen harness or `lint.sh`.

1. **The layer rules did not apply to `ns3.*` rows.**
   - **Identity rows.** The map's doc header defines them: both lists start with ns3.nodeId, ns3.simTimeMs and ns3.seq, and ns3.imsi is UE item 4. The lint now encodes that as `IDENTITY` (`LEAD`, plus `ns3.imsi` in the UE list). Layer `none` is now required on those rows and allowed on no other row.
   - **Section fit.** Every other `ns3.*` row must fit its src section exactly as a 3GPP row does (du → PHY/MAC/RLC, cuUp → PDCP, cuCp → RRC).
   - **Exceptions.** Five shipped vendor rows break that rule because ns-3 reports the quantity outside its layer's section. They are listed by name in `VENDOR_LAYER_EXCEPTIONS`, with sources at 74c165f1:
     - cuUp with layer RLC: `ns3.cuUp.txPdcpPduBytesNrRlc` and `ns3.cuUp.txPdcpPduNrRlc` (NR RLC TX counters, `mmwave-enb-net-device.cc:711-726`), and `ns3.cuUp.txPdcpPduLteRlc` and `ns3.cuUp.txPdcpPduBytesLteRlc` (LTE RLC, `lte-enb-net-device.cc:1124-1134`);
     - du with layer RRC: `ns3.du.numActiveUes` (the RRC UE-map size, `mmwave-enb-net-device.cc:1372`).
   - **Why names, not sections.** I listed rows by name rather than widening the sections. That way `ns3.du.macPdu` with layer RRC, or `ns3.cuUp.pdcpTxVolumeDl` with layer RLC, still fails.
   - **Doc header.** The map's doc header now states the identity-row rule and points to the exception list.
   - **Both reproduced bypasses now exit 1** (each changed only gnb cell 4 `ns3.du.macPdu`):
     - layer `none`: "(1) fields: layer 'none' is for the identity rows only";
     - layer `PDCP`: "(6) vendor: src section 'du' does not fit layer PDCP".
   - **New fixtures:** both bypasses; an identity row given a layer; du with layer RRC (not excepted); cuUp with layer MAC; cuUp with layer RLC (not excepted); cuCp with layer PDCP; a vendor row reading an identity src (`/nodeId`); an excepted row moved to another section.
2. **Missing required fields reached the optional checks.**
   - `map_findings()` now rejects any row that lacks a field in `FIELDS`, before any traversal: structural, clause, `--kpimon-enb` and `--samples`.
   - **CLI repro:** with `order` removed from the first enb cell row and `--kpimon-enb` given, the lint now exits 1 with "FAIL map: row 93 ('ns3.nodeId') missing ['order']" and no traceback.
   - **New in-process fixture:** `map-row-missing-a-required-field`.
   - **New CLI-level cases** (`cli_cases`: `main()` on temp files with stdout captured; any exception fails the case):
     - `order` missing, with `--kpimon-enb` (check_kpimon_enb reads `order`): exit 1;
     - `src` missing, with `--samples` (check_samples reads `src`): exit 1;
     - the shipped map with `--kpimon-enb`: exit 0, `"findings": 0`.

### Mutation check (on scratch copies; the tree was not edited)

I applied each mutant to a copy of the tests and schema, ran `--self-test`, and counted the checks that failed. Every mutant was caught.

| Mutant | Checks that catch it |
|---|---|
| no mutation (control) | 0, the self-test passes |
| `value_check` matches by src only | 6 |
| `matched_check` scans every entry by src only | 4 |
| `matched_check` matches by src only within the entry | 2 |
| duplicate-check rule removed | 4 |
| old trailing-dot parse restored | 1 |
| map validation removed | 8 |
| vendor section check removed | 7 |
| layer `none` allowed on any vendor row | 1 |
| exceptions widened to whole sections | 2 |
| identity-row layer check removed | 1 |
| required-field check removed from `map_findings` | 3: the in-process fixture and both CLI cases |

### Files touched in this round

- `ns3_e2_agent/tests/lint-metric-map.py` (now 398 lines)
- `ns3_e2_agent/tests/lint-metric-map-selftest.py` (now 458 lines; mostly the fixture table)
- `ns3_e2_agent/schema/metric-map.v1.json` (doc header line only; no row changed)

The registry and the kpimon eNB list did not change in this round.

### Acceptance re-run

| Command | Exit / result |
|---|---|
| shipped lint with `--registry`, `--kpimon-enb` | 0. Findings 0, rowsFailingClauseChecks 0, 2 XFAIL (gnb cell 34/35, pending P9) |
| `--self-test` | 0. Shipped pair ok, passing control ok, 106/106 fixtures ok (96 from before plus 10 new), 3/3 CLI cases ok |
| `--require-no-pending` | 1. 4 FAIL lines, all on gnb cell 34/35 |
| kpimon eNB list vs the map's eNB rows | equal |
| rows whose `kpm` is not `ns3.*` | only gnb cell 34 `DRB.PdcpSduVolumeUL` and gnb cell 35 `DRB.PdcpSduVolumeDL` (pendingFix P9) |
| `bash scripts/gates/kpimon-guard-selftest.sh` | 0. 11 cases ok |
| `bash scripts/gates/lint.sh` | 0, "lint: ok". The same two SKIP lines as before (KP_SO/KP_INC, KP_E2SM/TS_ORIG). |

Status: DONE_WITH_CONCERNS
Summary: Codex round 4 is fixed. Identity rows alone may have layer none, and every other ns3.* row must fit its src section unless it is one of the five rows named in the exception list. A missing required row field now stops every traversal, including --kpimon-enb and --samples, with exit 1 and no traceback. All 11 mutants were caught, the shipped lint stays at 0 findings plus the two P9 XFAILs, the self-test passes 106/106 fixtures and 3/3 CLI cases, and lint.sh and the kpimon guard self-test exit 0.
Concerns/Blockers: item 8 is unchanged: it follows the debate's C5 (`total: false`) rather than the literal "total = true plus a note". New: the five vendor layer exceptions are a judgement call (the layer follows what ns-3 counts, while the section follows where ns-3 reports it). If you prefer, those rows could instead take their section's layer.

## Codex rounds 5–10 (fixed by the controller session)

Each round's fix was mutation-checked: the new fixtures fail against the code they replaced. After every fix the shipped lint gives 0 findings and 2 XFAIL (gnb cell 34/35), and `lint.sh` and `kpimon-guard-selftest.sh` exit 0.

- **Round 5.** A name with a trailing newline passed, because Python's `$` matches before a final newline. `PRINTABLE`, `SOURCE_REF` and the slot-kind patterns now use `fullmatch`. Three fixtures: an ns3 name, a family and a placeholder, each with `\n`.
- **Round 6.** A negative INTEGER `maxValue` passed. The value must now satisfy 0 ≤ maxValue ≤ INT32_MAX, and booleans are refused. Three fixtures: 2³¹, −2³¹−1 and −1.
- **Round 7.** A slot label of `0`, `false`, `[]`, `{}` or blank disabled the label restriction. A label must now be null or a non-empty string. Five fixtures.
- **Round 8.** `maxValueBasis` and `totalBasis` accepted truthy non-strings. They must now be non-blank strings, and so must every string field in `ENTRY_FIELDS` and `CHECK_FIELDS`. Eleven fixtures.
- **Round 9.** A blank family name crashed the vendor-name check, and the diagnostic picked the family by truthiness. Family and placeholder names must now be non-blank, the family is picked by membership, and an ns3 name with an empty component is a finding. Four fixtures, including Codex's combined input.
- **Round 10.** Approve, with no findings. Codex reported 31,140 JSON mutations with no crash.

Self-test total: 136 fixtures plus the CLI cases.

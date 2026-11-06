# P10 pre-registration: questions for the user (2026-11-06 ~05:25 KST)

These must be ruled before the next commit after D-R3-1 (P6 or the UB fix). D-R3-1's own gate chain runs in the meantime and does not depend on them.

Sources:
- the draft: `plans/reports/researcher-261106-0500-GH-1-p10-pre-registration-draft.md`, with draft ledger rows 147–158;
- the verification: `plans/reports/kongming-261106-0500-GH-1-p10-pre-registration-verification.md`, which agrees with the draft except on P7's rationale;
- the neighbour-loop UB: phase-09's corrected finding and `kongming-261106-0414` §5.

| # | Question | Recommended | Alternative and trade-off | Due before |
|---|---|---|---|---|
| UB | ns-3 neighbour loop `--sortFlipMap.begin()` drops the only neighbour in 2-entry maps when the serving cell is the higher cellId and the strongest (82/594 r2 blocks) | Fix it under contract Amendment 4, as its own ns-3 commit before P6 | Disclose only (the default if there is no answer). This keeps the defect in every 2-gNB reference's ipc component | the next commit |
| Q1 | P6: `QosFlow.PdcpPduVolumeDL` is split-gNB-only and excludes Dual-Connectivity (3GPP TS 28.552 §5.1.3.6.1.1); 28.552 has no MAC volume measurement | Rename the MAC value, and every name that fails the lint (about 20), in place (same order and measId) to vendor `ns3.*` names. The eNB rows cite 3GPP TS 32.425, which is not in Zotero | Keep a 28.552 name with a recorded deviation; P6 would stay a deviation | P6 code |
| Q2 | P9: under a strict 28.552 / 37.340 reading, `DRB.PdcpSduVolumeDL` at the en-gNB is 0, because the MN hosts the PDCP | Option A: report the via-SN volume as `DRB.PdcpSduVolumeX2DL/UL` (28.552 Annex A.25). The predictor keeps its formula on the X2 counter, which needs a T3 ruling on `r3p-scenario.json` (a #9 file) | B: keep the name with a recorded reading. P9 would then not end fixed, so that is a contract Decision. A′: rename rows :56-57 in place, a leaner variant of A | P9 code (it shapes the revert plan now) |
| Q3 | P7: PDCP SN width on the EN-DC bearer | **Revised 07:44 after the Codex cross-check:** 12 bits, with the SN-wrap fix as its own commit just before P7. Both advisors agree. Reasons: no widening of the 16-bit SN fields or X2 SN Status Transfer, and the wrap fix runs live. The NR proof is a consumer lint, byte identity with the wrap commit, and the wrap test | 18 bits (kongming's first advice). Right if AC16 is read as requiring a visible wire difference at cp3 | P7 code |

Request: please add 3GPP TS 32.425 (E-UTRAN performance measurements) to Zotero for the eNB rows of the metric-map lint.

Controller-decided (recorded and shown at the next Stop): P7 check (b) baseline rule, the SN-wrap fix inside P7's commit, the c-judging rule, and the row 158 additive amendment. Kongming projects three revert cycles and about 14–17 h of wall time for P10.

**Revised 2026-11-06 07:44 KST** after Codex's independent opinion (`codex-261106-0732-…`) and kongming's cross-check of it (the verification report's new section). Q3 on the eNB rows now uses a strict fallback: without 32.425, every unverifiable eNB name is renamed to `ns3.*` unless the user grants a named exception. Plain-language page: `plans/261103-0008-GH-1-post-m9-realism-m10/visuals/explain-p10-pre-registration-questions.html`.

## User rulings, 2026-11-06 18:59 KST (via /ak-explain checklist)

- **UB: fix it.** Approved as contract Amendment 4: its own ns-3 commit right after D-R3-1 and before P6, with a ledger row and the widened tests (map sizes 1, 2, 8, 9, 10, ties; r2/r3p exactly min(8, eligible) neighbours; one s10 run). The amendment text is written into the contract in the docs commit before the UB code.
- **Q1 (P6): rename.** The MAC value and every name failing the AC16 lint are renamed in place to `ns3.*` (same order and measId), under the pre-registered rename rule with the `owningNode`/`countingEvent` registry fields and the "pending P9" marker on rows `:56-57`. The user asked where the names came from; the explainer answers it (researcher-261106-1859).
- **Q3: done by the user.** 3GPP TS 32.425 V19.0.0 is in Zotero (`9XR9PVRW`); 28.552 V20.2.0 stays `5SZUBP6M`. AC16's clause for eNB rows is read as 32.425, with the strict fallback for any name it cannot verify.
- **Q2 (P9) and Q4 (P7): still open.** The user asked follow-up questions; the explainer answers them. Q2 is due before P9 code (it shapes the revert plan); Q4 before the SN-rollover and P7 code.

## User rulings, 2026-11-06 19:52 KST

- **Q2 (P9): Option A, the X2 counters.** At every en-gNB, DRB.PdcpSduVolumeDL/UL report 0 (the en-gNB hosts no PDCP for the MN-terminated split bearer). New map rows DRB.PdcpSduVolumeX2DL/UL carry the volume the MN sends over X2 to that cell (28.552 §5.1.2.1.1.2 and its UL twin; Annex A.25). Counting: at the MN, each PDCP PDU submitted on the X2 leg to its `targetCellId`, SDU bits (PDU minus header), including SDUs re-sent after an LTE→NR switch. SN→SN forwarding during an SN change is excluded and disclosed. The ruling includes the T3 change of `scripts/gates/r3p-scenario.json` as described (counter `:8-10`, formula `:13`, transform `:29`, clause citation `:2`): the predictor reads X2DL with its formula, window, thresholds and decision rule unchanged. Contract open point 2's "corrected counter" is recorded as the X2 counter. The V3 judge becomes per-cell with a swapped-attribution negative fixture and its own run route.
- **Q4 (P7): 12-bit PDCP SN, with the wrap fix.** The NR PDCP header on the EN-DC bearer uses a 12-bit SN in both directions (38.323 §6.2.2.2). The pre-existing SN-wrap defects (`lte-rlc-am.h:208` / `lte-rlc-am.cc:1808` ordering; `lte-enb-rrc.cc:1105` and `lte-ue-rrc.cc:1774` predecessor test) are fixed in their own ns-3 commit right before P7, with checks (a) consumer lint plus header class from bearer context, (b) byte identity of P7's N4 runs with the wrap-fix commit, (c) a wrap test red at cp2 and green after the fix. AC16's trace clause is recorded as a format check that also passes at cp2.
- **Commit order now:** D-R3-1 (M7 red, under diagnosis), UB fix, P6, SN-wrap fix, P7, P9, P15, D-06b-1, kpimon node tag, TS serving cell, UseIdealRrc.
- **Zotero:** the user added 3GPP TS 28.552 V17.17.0 (`XU985K2J`). Its attachment does not resolve to a local file yet (`zotero-cli path` reports *unresolved*), so this session uses the identical ETSI PDF `ts_128552v171700p.pdf` that the researcher downloaded. At 19:57 the user attached the PDF (attachment `WJPE6SBD`); it is byte-identical to that ETSI copy (`cmp`), so the advisors' citations hold for the Zotero item.
- **Still open:** the lint's 28.552 version and the sub-counter rule. Both were put to kongming and Codex.

## User rulings, 2026-11-06 20:46 KST (P6 lint)

- **Lint version: 3GPP TS 28.552 V20.2.0 only, with the successor rule.** The strict lint judges NR names against V20.2.0 (`5SZUBP6M`) and eNB names against 32.425 V19.0.0 (`9XR9PVRW`), pinned by exact version; there is no V17 compatibility mode. An old or misspelled name moves to its V20.2.0 successor (e.g. `RRU.PrbTotDl` → `RRU.PrbDl`, `TB.ErrTotalNbrDl` → `TB.ErrTotNbrDl`) only when the definition is the same (unit, object, counting point) and the row's value passes the value check; otherwise the row becomes `ns3.*`. Each registry row records whether V17.17.0 (`XU985K2J`) has identical text. Per both advisors, in P6 this renames no row to a successor: `RRU.PrbTotUl` (constant 0), `RRU.PrbTotDl` (14-symbol denominator) and `TB.ErrTotalNbrDl.1` (counts retransmissions) fail their value checks and become `ns3.*`.
- **PRB source fix: a follow-up outside M10.** The ns-3 change that would source real PRB counts (the hard-coded 139 vs 28 RBs), fix the DL denominator and model UL usage is recorded as a follow-up, not added to M10. Until then the PRB family stays `ns3.*`.
- **Still open, explained on the page first:** sub-counters in names (KPM §8.3.9), the per-UE check against KPM §7.9, and the lint's data-type rule.

## User rulings, 2026-11-06 21:37 KST (last P6 lint rulings)

- **L2, sub-counters: flag.** The strict lint parses each 3GPP name against its clause's name grammar and fails any suffix that encodes a sub-counter for which KPM v03.00 §8.3.11 has a label (PLMN, S-NSSAI, 5QI, QFI, QCI, MU-MIMO layer, distribution bin). The row uses the bare name with noLabel only if the clause defines a total and the value is that total; otherwise it becomes `ns3.*`. Modulation suffixes (no KPM label) stay as the clause lists them. `ns3.*` names may not reuse a 3GPP family name or placeholder. P6 encodes no labels; noLabel stays everywhere, so indication bytes and the KPM T/T golden stay identical. Label support is not in M10. `_Filter` reading recorded as an interpretation: bare name with noLabel = unfiltered total.
- **L4, per-UE check: yes.** A UE-list row keeps a 3GPP name only if KPM v03.00 §7.9 (pp.13–14) lists its measurement type for per-UE conversion. gNB UE `TB.TotNbrDl(.1)` and `TB.TotNbrDlInitial` therefore become `ns3.*`; `DRB.UEThpDl` keeps its name (throughput is listed).
- **L5, data type: 3GPP type.** A row with a 3GPP name must use its clause's data type (item d), or KPM §7.9.1's replacement where one exists. A spec-integer value that could exceed kpimon's int32 range fails the lint instead of switching to REAL. `ns3.*` rows keep the map's overflow rule. Verified against V20.2.0: every row that keeps a 3GPP name already matches, so no P6 row changes type.
- **All P10 pre-registration rulings are now made.** Next, on the user's go: register rows 147–158 (amended for these rulings), the c judgement, the row-139 amendment and Amendment 4 in one docs commit before code. That happens after the resume housekeeping (frozen checkouts) and the M7 diagnosis of the D-R3-1 chain.

## Amendment, 2026-11-07 00:45 KST (user rulings at PAUSE T6, `decisions-261107-0045-GH-1-p10-pause-t6-rulings.md` item 4)
- **R2 replaces one line of the 21:37 L4 ruling.** The line "`DRB.UEThpDl` keeps its name (throughput is listed)" no longer holds. The P6 draft's value check found that ns-3 reports mean RLC PDU size divided by mean RLC delay, which is not 28.552's UE throughput, so the row becomes `ns3.du.rlcPduSizeOverDelayDl`. The L4 per-UE rule itself stands.
- **Also renamed under R1/R2:** the gNB `RRC.ConnMean` (28.552 §1 p.28: EN-DC RRC connection measurements belong to E-UTRAN), `DRB.MeanActiveUeDl`, and the gNB TB cell pair. The eNB `RRC.ConnMean` stays `ns3.*` until a run proves its attach bound.
- **Effect:** until P9, no row in the map passes under a 3GPP name.
- **Record:** the 21:37 text above is left unedited.


## Correction, 2026-11-07 06:33 KST (controller, not a user ruling; unanimous consensus `brainstorm-261107-0632-GH-1-sn-wrap-rulings-ultra-debate.md`, record `decisions-261107-0633-GH-1-sn-wrap-consensus-rulings.md`)
- **The reason "the wrap fix runs live" is wrong:** it appears in the Q3 row at `:15` and in the explainer's `explain-p10-pre-registration-questions.page.yaml` (`:330`, `:357`, reason 5 at `:368`).
  - scenario-zero's DRBs run RLC UM: `MmWaveHelper::RlcAmEnabled` defaults to false and nothing overrides it.
  - The code the SN-wrap fix changes is AM-only, so it runs live at neither 12 nor 18 bits.
  - What does wrap live is the PDCP SN in the MC entities and the header codec (4095 -> 0), and row 148 (b) covers that.
- **The advisor's reversal to 12 bits leaned on this reason** (kongming-261106-0500 C.2 item 4). It is disclosed for that reason.
- **The other reasons stand:**
  - The MC PDCP SN fields are live `uint16_t` (`mc-enb-pdcp.h:226-235`).
  - The X2 SN Status Transfer widening is latent under UM (it runs for AM DRBs only), but fix-to-spec would still forbid leaving it truncating.
  - The decision rule shown to the user, AC16 wire visibility (yaml `:342`), is untouched.
- **The Q4 ruling at `:33` stands:** P7's code is the last cheap point to reverse it. The SN-wrap commit survives a width change with only its modulus changed.
- **Scope note on Q4:** the SN-wrap commit also fixes the RLC 10-bit wrap by the same mechanism, because it orders by RLC transmission order. The row 160 amendment in the ledger gives the details.
- **Record:** the text above is left unedited. The explainer stays as a historical page.

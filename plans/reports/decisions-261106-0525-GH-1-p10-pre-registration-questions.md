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

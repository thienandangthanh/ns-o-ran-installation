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
| Q3 | P7: PDCP SN width on the EN-DC bearer | 18 bits: 38.323 Table 6.3.2-1 and 38.331 allow 12 and 18, and 18 is the usual EN-DC eMBB setting. The window is 2^17. The NR header class's own unit test carries the NR proof | 12 bits: adequate at this traffic, but byte-identical to E-UTRA on the wire, so P7 does not show in the checkpoint-3 diff | P7 code |

Request: please add 3GPP TS 32.425 (E-UTRAN performance measurements) to Zotero for the eNB rows of the metric-map lint.

Controller-decided (recorded and shown at the next Stop): P7 check (b) baseline rule, the SN-wrap fix inside P7's commit, the c-judging rule, and the row 158 additive amendment. Kongming projects three revert cycles and about 14–17 h of wall time for P10.

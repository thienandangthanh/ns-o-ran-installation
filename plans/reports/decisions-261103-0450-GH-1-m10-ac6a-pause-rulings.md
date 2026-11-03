# User rulings on the M10 P01 PAUSE T3 (AC6a en-gNB refusal), 2026-11-03 ~04:50 KST

Source: the user's answers in the session, given through the question dialog after the PAUSE (`docs/journals/2026-11-03-m10-p01-pause-t3-ac6a-en-gnb-refusal.md`; counsel `plans/reports/kongming-261103-0440-GH-1-m10-ac6a-en-gnb-refusal-decision.md`).

| # | Question | Ruling |
|---|---|---|
| D1 | How M10 proceeds after e2mgr 6.0.6 refused the en-gNB E2 Setup | **Patch e2mgr** (option A). It is a one-tag e2mgr fork patch, built as our own image through the Testbed and pinned after `m10-cp1`, with **Amendment 2** to the contract (below). P5 still ends fixed. |
| D2 | Whether T-B (P02–P04) continues while identity work waits | **Yes.** Resume at P02. P04's AC18 #9 registration holds no P5 meid rows until the patched e2mgr is proven (the meids follow R-3: `en_gnb_001_001_%08x`). |
| D3 | P14 (RANParameter-ID encoded unconstrained by rc and the agent) | **In scope.** Fix the bound in the rc fork's ASN.1 to E2SM-RC v03.00 `(1..4294967295, ...)` and regenerate rc's and the agent's codecs inside the T-A fork patches; `tools/rc-decode` is rebuilt from the corrected ASN.1. |
| D4 | 3GPP TS 38.331 citation source | **The user adds 3GPP TS 38.331 to Zotero** before P06; the standards ledger cites the Zotero copy. |
| — | Unpinned e2mgr feasibility build before `m10-cp1` | Not asked a ruling; not done. The e2mgr patch is built and probed after `m10-cp1`, per the T-A rule. |

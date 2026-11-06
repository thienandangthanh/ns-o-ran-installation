# SN-wrap commit: consensus rulings (2026-11-07 06:33 KST)

These rulings came from a unanimous brainstorm consensus under the user's standing rule of 2026-11-07 02:21: questions that would need the user go to a brainstorm, and unanimous answers are applied without asking. They are **not user rulings**. They are shown at the next Stop, where the user can reopen any of them.

Source: `brainstorm-261107-0632-GH-1-sn-wrap-rulings-ultra-debate.md`.
- Five candidates were run: four kongming and one Codex.
- A blind kongming verifier ranked them and checked the contested claims in source and in ETSI TS 136 322 V16.0.0.
- Codex, the only dissenter on Q1, conceded all four questions in the debate round.

| Q | Ruling |
|---|---|
| Q1 | **One ns-3 commit using RLC transmission order.** It walks the AM window from VT(A), takes the transmitted PDU before the retransmitted one, removes both `MergeBuffers`, returns SDUs in first-reassembly order and keeps the modular lookback. Row 160 is amended additively with (c)–(g), keeping the same check name, in the docs commit before the code. The widest-gap draft is withdrawn, and its diff is saved with its sha256. |
| Q2 | **Correction only; the user's 12-bit ruling (0525 Q4) stands.** "The wrap fix runs live" was wrong, because the DRBs run RLC UM. A correction is appended to `decisions-261106-0525`. |
| Q3 | **The six pre-existing LteRlcAm defects are observations only.** They are listed in phase-10 as follow-up candidates outside M10, with no ledger rows and no fixes. |
| Q4 | **The records are additive:** the 0525 correction, the ledger's row 160 amendment, the ledger's "Row 148 notes", and the phase-10 notes. No ruled or registered text is edited. |

## For the next Stop (disclosure; non-blocking)
1. The "runs live" correction. The advisor's reversal to 12 bits leaned on it. P7's code is the last cheap point to reverse the width.
2. Q4's scope note: the SN-wrap commit also fixes the RLC 10-bit wrap by the same mechanism.
3. The six AM defects (phase-10 list).
4. Please add 3GPP TS 36.322 to Zotero. Until then, the ETSI TS 136 322 V16.0.0 copy is cited.
5. The claim that scenario-zero runs RLC UM rests on static code reading. It is not a gated runtime probe.

## Unresolved questions
None blocking.

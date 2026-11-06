# PDCP SN-wrap commit: ultra + debate result (2026-11-07 06:32 KST)

This was a read-only advisory run, and no code changed. It answers four questions that would otherwise need the user, under the user's standing rule of 2026-11-07 02:21: a consensus is applied without asking, and a hard split goes to the user.

**Why the questions arose:**
- Codex's pre-ship review rejected the first draft (`fullstack-developer-261107-0550-…`). Its widest-gap COUNT inference reverses sparse SNs that never wrapped, for example {10, 3010}, on a split bearer.
- kongming (`kongming-261107-0555-…`) proposed RLC transmission order as the fix.
- kongming also found that scenario-zero runs RLC UM, not AM. `MmWaveHelper::RlcAmEnabled` defaults to false (`mmwave-helper.cc:93`, `:164-168`), so the AM code being fixed never runs live.

**Method (same as the P6 rulings):**
- Five independent candidates received one identical evidence packet: four kongming runs on Opus 5.5 and one Codex run.
- A kongming verifier scored them blind (A–E) and checked the contested claims in source and in ETSI TS 136 322 V16.0.0.
- Codex, the dissenting candidate, then got a debate round to challenge the verifier's answers with new evidence or concede.

## Contract
- **Outcome:** one ns-3 commit before P7 that orders the LteRlcAm lossless-handover forwarding buffer correctly across the 12-bit PDCP wrap and the 10-bit RLC wrap, judged by an amended row 160, with the records corrected.
- **Constraints:**
  - additive ledger amendment, same check name;
  - no widest-gap fallback and no legacy path;
  - UM paths, PDCP entities and plain-build flags untouched;
  - the docs commit before the code;
  - the Codex follow-up review is mandatory;
  - gate chains run from a frozen checkout.
- **Non-goals:** the six pre-existing AM defects, 18-bit SNs, the X2 SN Status Transfer, enabling RLC AM in any scenario, and P7's header work.
- **Acceptance:** listed under Q1 below.

## Final answers

| Q | Answer | Vote | Confidence |
|---|---|---|---|
| Q1 | **One ns-3 commit** (kongming's design) with an additive row 160 amendment (c)–(g) | 4–1, then the debate (below) | high |
| Q2 | **Correction only; the 12-bit ruling stands.** Disclosed at the next Stop, not blocking | 5–0 | high |
| Q3 | **Observations only:** a phase-10 list of follow-up candidates outside M10, with no ledger rows and no fixes | 5–0 | high |
| Q4 | **Additive records** in the docs commit before the code; no ruled text edited | 5–0 in substance | high |

### Q1: one commit
- **Design:**
  - walk the AM transmitting window VT(A) ≤ SN < VT(S), with VT(A) as the modulus base (TS 36.322 §7.1, §5.1.3.1.1; AM_Window_Size 512, §7.2);
  - at each SN take the PDU from the transmitted buffer, else from the retransmission buffer;
  - remove both `MergeBuffers`;
  - the getter returns PDCP SNs in first-reassembly order;
  - keep the modular lookback;
  - remove `OrderPdcpSnsByCount`, `GetTxedBuffer` and `GetRetxBuffer`.
- **Why one commit (verified by the verifier):**
  - "One fix per commit" means one commit-order item for P11's run-level bisection (phase-10 `:100`, `:296`; contract `:115` is about P6, P7 and P9 with no switches; phase-11 `:16` treats "P7 (with its SN-wrap commit)" as one unit; kongming-261106-0500 C.3 item 2).
  - The walk is a precondition of the getter. Over the raw `vector[1024]` walk, the getter would return the newest SDUs first at an RLC wrap, which is worse than m10-cp2.
  - DRBs run RLC UM, so neither half of a split changes a run byte, and a split would only add a second gated chain.
  - The user's Q4 ruling put the "defects", plural, in one commit (`decisions-261106-0525:33`).
- **Row 160 amendment** (additive; check name `m4_ns3_pdcp_sn_wrap_suite_passes` unchanged):
  - (c) {10, 3010} and {3010, 10} come back in transmission order;
  - (d) an RLC driven through its SAP at VT(A) = 1022 holds RLC SNs 1022, 1023, 0, 1, carrying PDCP SNs 4094, 4095 (the SDU straddles PDUs), 0, 1, and they come back in order with the straddling SDU whole;
  - (e) the same after a STATUS PDU with ACK_SN 0 and NACK {1022, 1023};
  - (f) no-wrap identity at VT(A) = 5;
  - (g) an RLC wrap without a PDCP wrap (PDUs 1022 = [100], 1023 = [head of 101], 0 = [tail of 101 + 102], 1 = [103]) gives 100–103 with SDU 101 whole. This gives the RLC-wrap fix its own red-to-green attribution inside the one commit.
  - The pass rule reads the set in RLC transmission order. It states openly that the RLC 10-bit wrap is fixed by the same mechanism, and that no M5–M7 or N4 run executes these paths.
  - Residuals: the X2 double-hop race at an SN-change target; SNs 4096 apart sharing one map key; the never-cleared SDU vector, so COUNT order is guaranteed only on an RLC entity's first forwarding.
- **Test details adopted:**
  - the cp2 shim is diff-matched to cp2's text, with its sha256 recorded;
  - save the widest-gap draft diff with its sha256 before replacing it;
  - (d), (e) and (g) assert the FI flags of the boundary PDUs, so a mis-sized fixture cannot pass;
  - B3 asserts only "each SN once, latest copy", so the gate never pins the never-cleared defect.
- **Not adopted:** a runtime UM probe as a gate, because it would be a new check. The UM claim is labelled "static code reading".
- **Acceptance:**
  1. The docs commit comes first.
  2. Red at the cp2 shim: L0, L1, B0, (c) second half, (d), (e), (g). Green at cp2: (c) first half and (f). (c) first half and (g) are red at the saved draft. Everything is green at the commit.
  3. `MergeBuffers`, `OrderPdcpSnsByCount`, `GetTxedBuffer(` and `GetRetxBuffer(` are absent from `src/` (bindings excluded).
  4. `lte-rlc-am-transmitter`, `lte-rlc-am-e2e`, `lte-rlc-header` and `mmwave-neighbour-list` pass.
  5. M4 and M5–M7 are green, and two builds give byte-equal N4 runs (row 148 (b) baseline).
  6. The Codex follow-up review leaves no ordering finding open.

### Q2: correction only
- The PDCP SN wraps live in the MC entities and the header codec (4095 → 0), and row 148 (b) covers that. No site the wrap fix changes runs live, and none would at 18 bits.
- The reason "the wrap fix runs live" (`0525:15`; explainer `.page.yaml` `:357`, reason 5 at `:368`) is therefore wrong.
- The advisor's reversal to 12 bits leaned on it (kongming-261106-0500 C.2 item 4), so disclosure is mandatory.
- The other reasons stand. The decision rule the user was shown (AC16 wire visibility, yaml `:342`) is untouched.
- The X2 widening argument is latent under UM, while the MC PDCP `uint16_t` fields are live (`mc-enb-pdcp.h:226-235`).
- P7's code is the last cheap point to reverse. The SN-wrap commit survives a width change with only its modulus changed.
- **Flips only if** the user says live AM exercise was decisive. Even then, 18 bits restores no AM coverage.

### Q3: observations only
- **The six AM defects** (kongming-261107-0555, "What to avoid"):
  1. the never-cleared SDU vector;
  2. the lookback includes the head SN, so the head SDU is sent twice;
  3. `m_segmented_rlcsdu` is never reset;
  4. SNs 4096 apart collapse into one map key;
  5. `m_txedRlcSduBuffer` misses the first SDU of each PDU;
  6. the SN Status Transfer reads the hidden `GetStatus` (`lte-enb-rrc.cc:925-927`).
- They are AM-only, dead in scenario-zero, and each changes no-wrap behaviour.
- They are recorded in phase-10 next to the PRB and TB follow-ups. Their trigger is any gate or scenario that enables AM DRBs.
- If P7's step 2(b)/(c) unit tests trip on one of them, it becomes a P7 blocker with its own row and a ruling.

### Q4: records (docs commit before the code)
1. `decisions-261106-0525`: append "Correction, 2026-11-07 (controller, not a user ruling)". The ruling at `:33` stands.
2. Ledger: the row 160 amendment block, and "Row 148 notes (record only)". The note says (b) covers the PDCP entities, the header codec and the UM paths. AM-only consumers rest on (a), row 160's suite and step 2(c). "Broke no consumer" means "no consumer on a path N4 runs". The predicate is unchanged.
3. Phase-10, under the SN-wrap gates: M5–M7 and N4 are no-regression guards, not coverage. Add the Q3 list.
4. The next Stop lists the correction, the Q1 scope note, the Q3 list, and a request to add TS 36.322 to Zotero. The ETSI TS 136 322 V16.0.0 copy is cited meanwhile, as was done for 28.552.

## Ranking (verifier, blind)

| Rank | Candidate | Total /100 | Note |
|---|---|---|---|
| 1 | D (kongming #4) | 95 | conjunct (g); found that the 12-bit reversal leaned on the false reason; cp2 shim diff |
| 2 | B (kongming #1) | 94 | broadest verified citations; honest that the UM claim is static |
| 3 | C (kongming #2) | 89 | never-cleared residual; B3 restriction |
| 4 | A (kongming #3) | 87 | explicit "scope extension" label; cited explainer lines from the `.html`, not the yaml |
| 5 | E (Codex) | 60 | read "one fix per commit" as one defect per commit; vague acceptance |

ultra: picked=4/5 margin=low unanimous=no rejected_all=no

## Debate
- **The Codex debate round** (`task --fresh`, effort high) received the verifier's spot-checks and final answers. It was asked to challenge them with new source evidence or concede.
- Its reply: Q1 CONCEDE ("I withdraw the split recommendation. I found no new source evidence overturning the verifier's one-commit answer"), Q2 CONCEDE, Q3 CONCEDE, Q4 CONCEDE. Its final line: "Q1 position: one-commit".
- **Result: unanimous on all four questions.** Under the standing rule the answers are applied without asking the user. They are recorded in `decisions-261107-0633-GH-1-sn-wrap-consensus-rulings.md` and shown at the next Stop.

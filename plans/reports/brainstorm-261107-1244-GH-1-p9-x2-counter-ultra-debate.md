# P9 X2 counter design: ultra + debate result (2026-11-07 13:15 KST)

This was a read-only advisory run; no code changed. It decides the open questions of the P9 design counsel `kongming-261107-1215-GH-1-p9-x2-counter-design.md` under the user's standing rule of 2026-11-07 02:21: unanimous answers are applied, hard calls go to the user.

**Method (same as the P6, SN-wrap and row 149 rulings).** One evidence packet went to five independent candidates: four kongming runs on Opus 5.5 (k1–k4) and one Codex run (c5). A blind kongming verifier scored them, anonymized as A–E, and re-checked the load-bearing claims in source at ns-3 4318e43b, Testbed 254027ca, oran-interface 53253fe2 and harness 7ac51b00. All five then got a debate round on the two points still contested.

## Contract
- **Outcome.** At every en-gNB, `DRB.PdcpSduVolumeUL/DL` report 0, and `DRB.PdcpSduVolumeX2DL/UL` carry the X2 volume of that cell under their 3GPP names. The registry value check holds under row 147's R1 and (3). R3′ reads X2DL with its predicate unchanged.
- **Constraints.** Fix to spec, no switches, additive ledger text before code, P9 lands as one harness pin commit, no M10 scope expansion without the user.
- **Non-goals.** Fixing the MC-setup aliasing defect, per-UE X2 rows, SN-terminated or AM bearers, a live SN change in the V3 runs, re-forming the R3′ schedule.
- **Acceptance.**
  - The lint reports 0 findings and no `pendingFix` remains.
  - M4 is green, including the row 163 suite, and a recorded mutation turns that suite red.
  - M5–M7 are green.
  - `n4 --part v3` passes: a0–a8 are true, `x2ulEvents` is above 0 and the inclusion counts are 0.
  - R3′ single reproduces the scheduled decisions.
  - The golden decode diff shows only two appended cell items.
- **Trade-offs.**
  - (R) assumes that receiving a PDU over X2-U is the event the NRCellCU counts. It fails first if the clause is read as counting at the sender, which the en-gNB cannot see.
  - (M) assumes R1 tolerates a 4-slot shift. It fails first at the registry's `holds` check and at (3).
- **Better approaches:** none beyond (R), A8 in inclusion form and the row 163 suite. The verifier confirmed that each of these improves on the counsel's text.

## Final answers

| Q | Answer | Vote | Confidence |
|---|---|---|---|
| Q-1 | (R): count at the en-gNB's X2-U boundary. DL is counted at reception, before the forward-map test (`epc-x2.cc:626`, `:642`); UL is counted at the send (`DoReceiveMcPdcpSdu`, before `:1291`). Recorded as "revises Q2's counting sentence (node and instant only), settled by consensus". | 5–0 | high (design), medium-high (authority) |
| Q-1b | A redirected PDU counts at both the S-SN and the T-SN, because these are two X2 transfers into two NRCellCUs. Disclosed: Σ_g X2DL exceeds the MN's X2 output during an SN change. | 5–0 | high |
| Q-2 | The forwarded RLC UM tail is an **R1 gap**, not an interpretation. Its remedy goes to the user before P9 code. | after the debate, 5–0 (before it 1–4) | medium-high |
| Q-3 | (b): a new ns-3 suite `epc-x2-mc-pdcp-volume`, gated at M4 (row 163). | 5–0 | high |
| Q-4 (i) | A6 also requires ≥ 1 x2ul. | 5–0 | high |
| Q-4 (ii) | A8 is required, in the verifier's inclusion form (below). | after the debate, 5–0 | high |
| Q-4 (iii) | Remove the lint's pending machinery (row 147 note; stricter). | 5–0 | high |
| Q-4 (iv) | Row 152 additions (a)–(d). | 5–0 | high |
| Q-4 (v) | Fixture row 164 for the regenerated KPM T/T golden. | 5–0 | high |
| Q-4 (vi) | Audit v2 grammar; identity is not a P9 gate (row 150 note); fix the v3 key list at `gate-n4-ul-metric.sh:420`. | 5–0 | high |

**A8 (inclusion form).** For each cell g, compare multisets of pduBytes, with T = the run's stop time:
- DL: x2dl(src ∈ M) ⊆ dltx(leg g), and dltx(leg g, tNs ≤ T − 2 ms) ⊆ x2dl(src ∈ M).
- UL: ulrx(leg g) ⊆ x2ul(g), and x2ul(g, tNs ≤ T − 2 ms) ⊆ ulrx(leg g).
- Report the count of sender events in (T − 2 ms, T] as a fact; that count bounds what the inclusion form can mask.
- Why not equality: a sender event in (T − 2, T − 1] ms whose receive arrives before T makes a one-sided exclusion with equality go falsely red. Equality with no exclusion goes falsely red while UL is still draining at T; in ulon-a1 the last gNB→MN X2-U arrival is at 9.97233 s.

**Q-2 mechanism (verified by the verifier and conceded by all five).**
- On the S-SN RLC-buffer forward (`lte-enb-rrc.cc:905` → `:939`/`:943`, where `removePdcpHeader` is false), the unsent tail of a segmented SDU sits at the head of the `LteRlcUmLowLat` TX buffer (`lte-rlc-um-lowlat.cc:274-282`).
- If its first octet has the top bit set, `DeliverRlcForwardingBuffer` passes it (`lte-rlc-forwarding-buffer.cc:190-191`, `:201`) as a PDCP PDU.
- All N of its bytes are SDU payload, but (R) counts 8 × (N − 2). That loses 16 bits per forwarded tail, an error in value and not in timing, so it breaks R1 (registry `kpm-measurement-clauses.v1.json:10-11`, ledger `:153`).
- Calling it an interpretation would repeat the relabelling that the P6 debate rejected (`brainstorm-261106-2359:70`, C4).
- The tail is detectable: it still carries `LteRlcSduStatusTag` LAST_SEGMENT or MIDDLE_SEGMENT (`lte-rlc-um-lowlat.cc:258-282`), and packet tags are stripped only after the D/C test (`lte-rlc-forwarding-buffer.cc:194`).
- Incidence is likely low, because payloads are zero-filled after the IP, UDP and SeqTs headers.

## Ranking (verifier, blind)

| Rank | Candidate | Total /100 | Note |
|---|---|---|---|
| 1 | C (k1) | 83 | the only correct A8; best evidence on authority (the user's explainer `:212`, `:249`); found the fire order and the no-drop queue; numbered its suite row 162, which collides with the existing row 162 |
| 2 | D (k4) | 79 | the SwitchToLte and unrouted-arrival interpretations; one wrong grep claim about the stage-A sha |
| 3 | A (k3) | 78 | strongest source checks (ulon-a1 6194 = 6194); reversed the D/C and tag-strip order |
| 4 | B (c5) | 76 | the only candidate to call Q-2 a gap from the start; no factual error found; its A8 had no exclusion at all |
| 5 | E (k2) | 75 | made A8 required; its A8 exclusion was on the wrong side and used the wrong anchor |

ultra: picked=1/5 margin=low unanimous=no rejected_all=no

## Debate
- **Q-2.** k1, k2, k3 and k4 each conceded "gap". Codex kept "gap". Each concession says that "what the model's PDCP parses" would make the defective model the truth. Three candidates also gave new evidence that the fix is small: one status-tag test (FULL_SDU) before the D/C test.
- **A8.** Codex conceded its complete equality; k2, k3 and k4 conceded their one-sided exclusions; k1 already had the inclusion form.
- **Result: unanimous on every question.** Q-2's remedy remains a user decision. Recorded in `decisions-261107-1244-GH-1-p9-x2-counter-consensus-rulings.md`.

## Unresolved (for the user)
- The Q-2 remedy:
  - (a) fix the tail framing in its own ns-3 commit before P9, scoped either narrowly (the S-SN forward only, which leaves row 149's P7 counts untouched) or to every caller (which also absorbs the "RLC UM tail re-submission" follow-up and changes row 149's counts);
  - (b) a user-owned exception of at most 16 bits per forwarded D/C = 1 tail;
  - (c) `ns3.*` names, which undo Option A.
- Whether the row 163 suite can drive `EpcX2::AddX2Interface` without a full EPC stack (implementation cost).

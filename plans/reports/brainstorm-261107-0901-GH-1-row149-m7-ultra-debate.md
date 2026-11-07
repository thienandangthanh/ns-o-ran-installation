# Row 149 at M7: ultra + debate result (2026-11-07 09:01 KST)

This was a read-only advisory run, and no code changed. It decides how ledger row 149 (P7, "traces show an NR PDCP header", `<step>_pdcp_dl_pdu_bytes_eq_sdu_plus_nr_header`) judges M7, under the user's standing rule of 2026-11-07 02:21.

**Why the question arose:** the harness developer (`fullstack-developer-261107-0821-GH-1-p7-harness-checks.md` §3) found that the registered equality fails in all 15 archived M7 runs, on 13–14 short rows per run. All 15 M6 runs pass.

**Method (same as the P6 and SN-wrap rulings):**
- One evidence packet went to five independent candidates: four kongming runs on Opus 5.5 (k1–k4) and one Codex run (c5).
- A blind kongming verifier scored them (anonymized as A–E) and checked the load-bearing claims in source at 4a0871d6 and in all 30 archives.
- Codex, the dissenter, then got a debate round.

## Contract
- **Outcome:** row 149 judges the 12-bit NR header size on the EN-DC bearer at M6 and M7. It goes green at P7 exactly when every MC TX PDU carries a 2-octet header, and stays robust through the UseIdealRrc commit.
- **Constraints:** additive amendment in the docs commit before the harness code; P7 stays one ns-3 commit; no new ns-3 instrumentation; fix to spec; no legacy modes.
- **Non-goals:** fixing UM forwarding; judging SDU integrity; turning row 149 into a discriminator (user ruling Q4).
- **Acceptance:**
  - the amendment lands before the code;
  - the self-test fixtures behave as listed;
  - the offline replay of all 30 archives passes;
  - P7's M6 and M7 are green;
  - the follow-up is recorded in phase-10.

## Final answers

| Q | Answer | Vote | Confidence |
|---|---|---|---|
| Q1 | (a′): amend with a ±1-epoch switch window (switch rows ≤, others =, ≥ 1 equality row) | 4–1, then the debate: unanimous | high on the direction, medium on the window width |
| Q2 | A follow-up outside M10, not a P7 blocker | 4–1, then the debate: unanimous | high |

**Ruled out:**
- **(b) M6 only:** it drops about 3300 exact rows per run on the multi-gNB gate, and M6 also has 78 switches.
- **(c) Keep as registered:** a guaranteed red for a pre-existing cause that is not the header, and a risk of PAUSE T6.
- **(d) Another source:** the PduSize columns are RX-side, and a per-PDU line would be new instrumentation and change the N4 compared set.
- **Diagnose first:** a diagnosis cannot flip either answer, because the header verdict rests on observed facts.

**Trade-off of the winner:** it assumes the RRC and X2 skew stays under 100 ms after `UseIdealRrc=false`. If not, it fails red, never a false green.

## Ranking (verifier, blind)

| Rank | Candidate | Total /100 | Note |
|---|---|---|---|
| 1 | A (k3) | 85 | the only text that admits the weakening; most complete fixtures; wrong RLC class and branch cites (corrected when applied) |
| 2 | D (k4) | 82 | every cite correct; found the E2 counter reset in the gNB report loop; argued that no root cause is needed |
| 3 | E (k2) | 81 | one header-add function on every TX PDU; the "absent file = no events" rule (adopted) |
| 4 | C (k1) | 77 | mechanism cites right; noted that M6 has switches; wrong reset cite; no single-sample caveat |
| 5 | B (c5) | 50 | rightly called "not weaker" a logical error; no predicate |

ultra: picked=4/5 margin=low unanimous=no rejected_all=no

## Debate
- Codex (`task --fresh`, effort high) received the verifier's verdict and was asked to challenge it with new evidence or concede.
- Its reply: "I concede both questions. My read-only recheck found no new evidence that overturns the verifier." It recounted all 30 archives: 205 of 205 short rows have a same-IMSI switch in their own epoch, and no row is long. It confirmed the 6 runs at `ea6e46f6` and withdrew mandatory investigation before P7.
- It closed with "Q1 position: concede" and "Q2 position: concede".
- **Result: unanimous.** Applied without asking the user; recorded in `decisions-261107-0901-GH-1-row149-m7-consensus-rulings.md`.

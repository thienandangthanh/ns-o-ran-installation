# M10, P10: PAUSE T3, the P9 X2 counter waits for the UM-tail remedy (2026-11-07 13:55 KST)

## What happened
- **P7 is done (12:10 KST).** ns-3 34b7f3cc added the NR PDCP header, and 4318e43b added the Control PDU discard, which was the one Failure Protocol fix after M4 red #1. On the harness side, 3dac03b8 added the gates and 83b01bc6 moved the pin. The chain at 83b01bc6 is green on M4–M7. N4 identity is byte-equal to `reference/n4-sn-wrap/` on 36 items. Recorded in 7ac51b00; raw archive p10h.
- **P9 design.**
  - kongming wrote the design counsel `kongming-261107-1215`. It left three questions open; I put them to an ultra + debate brainstorm (five candidates, a blind verifier, then a debate round).
  - All five candidates now agree on every question (`decisions-261107-1244`). The rulings cover:
    - the counting point: the en-gNB's own X2-U boundary, which revises the "at the MN" sentence of user ruling Q2 in node and instant only;
    - the audit v2 format;
    - A8 in its inclusion form;
    - the M4 suite (row 163) and the golden fixture (row 164);
    - row 152 (a)–(d).
  - Registered before code in 3cdbc72f, with a further A0 rule in e34e940f and 25894695 from the Codex reviews of the judge.
- **P9 code is written on the host, uncommitted:**
  - **ns-3:** the EpcX2 traces, the McEnbPdcp leg traces, the gNB X2 counters and zeros, audit v2, and the suite `epc-x2-mc-pdcp-volume` with its mutation evidence.
  - **oran-interface:** the CU-UP helper.
  - **Testbed:** the metric map rows 36/37, the registry, the lint without the pending path, and the golden.
  - **Harness:** the judge, `--part v3`, the row 152 files with the sha recompute, the M4 check and chain step 14.
- **Reviews:**
  - The harness judge went through three Codex rounds. The first found the timestamp-collapse bypass, the second found the out-of-run events and the float hello. All were fixed, and the third round approved.
  - The ns-3 review and the Testbed/oran-interface review each report a single finding: the registered UM-tail gap. They found nothing else.
- **Host verification:**
  - ns-3 builds; all four suites pass; the mutation turns the new suite red.
  - In a ulon run, the IPC X2DL/X2UL equal the audit x2 lines in 100/100 windows.
  - The ns3run traces are byte-equal to P7, so row 149's facts are unchanged.
  - The golden decode diff shows only the two appended cell items.

## Why it pauses
The forwarded RLC UM tail is an R1 gap (consensus Q-2, 5–0 after the debate; the verifier sided with Codex).
- On the S-SN RLC-buffer forward, the unsent tail of a segmented SDU can pass the D/C test. The counter then subtracts 2 "header" octets that are really payload, so it is 16 bits low per forwarded tail.
- Until the gap is resolved, the X2DL value check holds false. The strict metric-map lint therefore stops `lint.sh`, `install_xapp_kpi_monitor.sh` and `install_ns3_e2_agent.sh`, and P9 cannot be committed or pinned.
- Every remedy changes M10's scope or a user ruling, so this is a user decision (scope guard item 4, PAUSE T3).
- The user asked at 13:22 not to be asked now, but to pause when the work that does not depend on the answer is done.

Kongming notes: `kongming-261107-1215-GH-1-p9-x2-counter-design.md` (design), plus the verifier verdict summarized in `brainstorm-261107-1244-GH-1-p9-x2-counter-ultra-debate.md`.

## Decision needed from the user
Explainer: `plans/261103-0008-GH-1-post-m9-realism-m10/visuals/explain-p9-um-tail-remedy.html`.
- **(a-narrow), recommended:** fix the tail framing on the S-SN secondary-cell forward only, in its own ns-3 commit right before P9 (forward only FULL_SDU-tagged packets, with the tag tested before the D/C test). Row 149's P7 counts stay as they are.
- **(a-wide):** apply the same fix on every forwarding caller. This absorbs the "RLC UM tail re-submission" follow-up into M10 and changes row 149's M7 short rows.
- **(b):** a user-owned exception, at most 16 bits per forwarded D/C = 1 tail.
- **(c):** `ns3.*` names, which undoes Option A. No agent recommends it.

Also for review (non-blocking): every consensus ruling in `decisions-261107-1244`, the row 149 consensus (`decisions-261107-0901`), the UM forwarding defects and the class-A aliasing follow-up, and the class-A ledger question (default: observation only).

## Resume plan
1. Apply the ruling.
   - (a): register its row and a design check, then implement, review and commit the tail fix.
   - (b): write the exception into the registry and the ledger.
2. Commit the forks:
   - ns-3, then oran-interface;
   - replace the `@UNCOMMITTED` source refs with the SHAs;
   - Testbed;
   - the harness pin commit.
   Lint must report 0 findings first.
3. Run the chain: steps 2–7, then 14, then 10. Before it, check `df` (≥ 34 GiB for the kpimon rebuild).
4. Record and archive the result, then continue with P15.

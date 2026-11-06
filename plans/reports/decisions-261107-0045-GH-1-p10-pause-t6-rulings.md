# User rulings at PAUSE T6 (2026-11-07 00:45 KST)

These are the answers to the four questions in `docs/journals/2026-11-07-m10-p10-pause-t6-d-r3-1-chain-e2i.md`. The user chose the recommended option each time.

1. **D-R3-1 verification: option (a).** Copy and verify the asn1-indep tarball, then run only e2i (step 8 of `p10-gate-chain.sh` at a7943bf, with a fresh log dir) on the current VM. The outcome rule is the one in phase-10, "D-R3-1 chain attempt 2":
   - read-only pre-checks first;
   - the copy is checked with `sha256sum -c` on the host and in the VM;
   - **green** = exit 0, the run-dir cross-check passes, and the image Id equals P08's; D-R3-1 is then fixed at both SHAs;
   - **any red** = a kongming note, then PAUSE.

   This is a user-authorized resume from the PAUSE, not a reclassification.
2. **M7 failures with the no-route-table signature: (ii).**
   - M7 gains an additive, informational, receiver-side record after recovery: the e2term `router.txt.stash` and its mtime, the e2term :4561 sessions, rtmgr's sessions to the e2term Service, and the NOENDPT 12001 lines. It gets its own ledger row and lands after D-R3-1 is verified.
   - An M7 failure whose record matches the signature gets one re-run from the step's start state, outside the guided-fix budget. Two matching failures in a row mean PAUSE.
   - The same rule applies to the M10 end run (record it at Stop B).
3. **T5: the Failure Protocol reading is right.** Known L-release hazards go through the Failure Protocol first, and T5 applies only if the guided remedy fails.
4. **P6 rulings: the recommended set, as stated in `brainstorm-261106-2359-GH-1-p6-rulings-ultra-debate.md`.**
   - **R1 strict.** A row keeps its 3GPP name only if ns-3 counts the clause's events exactly once on every path the runs reach. Only timing may differ: up to 1 slot for counts, or 1 of the clause's own sampling steps for sampled values. The gNB TB pair becomes `ns3.*`, and so does the eNB `RRC.ConnMean` until a run proves its attach bound.
   - **R2.** Accept the three renames (`DRB.UEThpDl`, the gNB `RRC.ConnMean`, `DRB.MeanActiveUeDl`). This replaces the 21:37 L4 line "DRB.UEThpDl keeps its name". The L4 per-UE rule stands, and the 21:37 text is left unedited.
   - **R3.** The TB counter fix is a follow-up outside M10, next to the PRB fix.
   - **R4.** Accept the unit-text corrections, extended to three eNB rows (enb cell 5, enb cell 6, enb ue 10).
   - **Q5.** Count the X2 forwarding from the source SN to the target SN at the receiving cell. This revises Q2 and row 151, and is applied before P9 code.

   Row 147's amendment states the R1 rule and the registry interpretations before the P6 code commit.

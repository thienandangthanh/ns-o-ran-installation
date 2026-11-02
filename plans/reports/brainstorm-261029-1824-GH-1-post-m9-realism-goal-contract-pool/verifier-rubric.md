# Verifier rubric: post-M9 realism contract (brainstorm --ultra, 9-candidate pool by user request)

You judge anonymized candidates (labels only; order randomized; no authorship, no self-ratings). The evidence packet every candidate received is at
`/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/9d18942e-df88-409a-8d18-bd3047c2aa88/scratchpad/post-m9-realism-evidence-packet.md`.
Read it first. You may read repo files (read-only) to check cited claims. Do not write any file.

## Hard constraints (a candidate failing any one cannot win; say which)
- H1 In scope: all three tracks T-A (P1, P2, P4, P5, P8, P10, P11, N5 + scale gate > 9 gNBs), T-B (δ seam with δ = 0 byte-equal, δ sweep, P12), T-C (P6, P7, P9); the ops prelude (follow-ups 1, 2, 3, 5; 4 investigation-only); a new unattended from-fresh-install run as the end state. A candidate may challenge a ruling only under "Better approaches" with evidence, and must still deliver the ruled scope in its draft contract (or clearly route the challenge to a user decision).
- H2 Out of scope: real QP / R3, scenario-one smoke, scenario-agnostic harness.
- H3 M9 references stay reproducible: δ = 0 (and every new flag off) is byte-equal to the committed M9 references.
- H4 P10, P11 and scale-gate acceptance match the user's rulings in packet §3.
- H5 Recommends exactly one δ source with justification.
- H6 Contains the `ak:goal-warmup` Outcome Contract schema with every field.

## Scored criteria (1–20 each)
1. Faithfulness to the request and the session rulings (no silent scope cuts or additions).
2. Evidence grounding: claims cite real paths/lines or reports; [V]/[C]/[I] labels honest; spot-check at least 3 [V] citations per finalist.
3. Acceptance-criteria sharpness: each AC is script- or evidence-checkable; covers every in-scope item, the prelude, byte-equality, the unattended run, records.
4. Feasibility and budget realism: disk (59 GiB free now vs 84 GiB M9 requirement; overlay leak), wall time of the bigger run, ordering that de-risks (what can break the regression), single-goal size vs split.
5. Standards grounding: each fix tied to a 3GPP / O-RAN clause; honest about editions not verified against Zotero; correct technical substance (e.g., NR CGI gNB-ID length choice, PPID 70, en-gNB UE ID, EN-DC X2 SETUP).
6. Honesty about unknowns: unresolved questions are real user decisions or unverifiable items, not padding; unverified advisor claims flagged.
7. Conditional fields: Trade-offs name per-approach load-bearing assumption and first-failure condition, compared on worst case; Better approaches is either evidence-backed or the explicit "none — …(evidence)" line.

## Output
- Per candidate: hard-constraint pass/fail (which), the 7 scores, 2–4 lines of evidence-backed rationale.
- Ranking, winner (or REJECT-ALL with reasons), runner-up, margin on deciding criteria (high if winner leads runner-up by > 5 points on the deciding criteria sum-normalized, else low), whether the winner topped every criterion (unanimous yes/no), confidence note.
- List material defects in the winner that the controller must surface to the user as open items (the winner is materialized unchanged; you do not rewrite it).

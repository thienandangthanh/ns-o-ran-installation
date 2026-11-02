# Goal packet (from ak:goal-warmup), M10 post-M9 realism

State: **Ready**. Final summary confirmed by the user on 2026-11-03 at about 02:25 KST. Warmup never starts `/goal`; the user starts the long run.

## Outcome contract (LOCKED)
Authoritative text: `plans/reports/contract-261103-0001-GH-1-post-m9-realism-outcome-contract.md`. Approved 2026-11-03; Amendment 1 re-approved 01:10 KST; AC11 citation corrected 01:45 KST with the requirement unchanged.
- **Intended result:**
  - On VM `ubuntu24.04`, the ops prelude, T-B timing, T-A E2 interop/identity/control, the ≥ 10-gNB scale gate and T-C radio/counter realism all land behind three tagged checkpoints (cp1 literal M9 equality, cp2 registered transforms, cp3 explained new references).
  - Then one unattended M10 run from `fresh-install` exits 0 with the exact pre-registered step set.
  - P1–P13 and N5 end fixed. An item may end "listed" only under an approved substitution.
- **In scope:**
  - FU1–FU5 and the probes AC6/AC6a/AC6b;
  - the δ seam, the {100, 150, 200, 500} ms sweep and P12;
  - P10 (every E2 node, e2sim included), P11/N5 (32-bit gNB ID), P2/P5/P8 (with the N1 TS xApp patch), P4 (RC and KPM UE IDs, AC14b), P1/P13 (E2SM-RC Style 5 action 3 to the source en-gNB);
  - scale ≥ 10 gNBs; P6/P7/P9 and `UseIdealRrc=false`;
  - rc, TS xApp, kpimon and e2sim fork patches; the M10 runner; the records.
- **Out of scope:**
  - real QP/R3, scenario-one, a scenario-agnostic harness;
  - free-run gates and `RealtimeSimulatorImpl`; window or late-apply lock-step modes;
  - kpimon measurement-time stamping; an MN-decided inter-frequency SN change;
  - compat/legacy modes and default-off switches;
  - the RMR stuck-reader root cause; upstream PRs, the N release, host changes, publication.
- **Acceptance signals:** AC1–AC20, including AC6a, AC6b, AC8b and AC14b, as written in the contract.
- **Constraints:**
  - A1 carry-overs; fix to spec with no legacy modes;
  - lock-step is the gate mode; standards ledgers;
  - disk: ≥ 20 GiB in dev, watchdog trip 37 GiB (h = 12);
  - kongming `--advice` at Opus xhigh; Codex read-only, one at a time, disclosed, no cap;
  - Stops A, A′ and B; A1 interpretations (a)–(k) ratified.
- **Allowed substitutions:** A1 substitutions 1–3, SUB-1 (hardened as AC8b), SUB-H, S-R, SUB-P12.
- **Decision owner:** user.

## Plan
- Path: `plans/261103-0008-GH-1-post-m9-realism-m10/plan.md` (rev 3), with phase files P00–P13 and P06b.
- Contract traceability: present (plan.md "Traceability").
- Review ledger: `reports/warmup-review-ledger.md` (round 1: kongming + Codex; round 2: Codex), status complete.

## Preflight (`reports/preflight-matrix.md`)
- Blocking at start: none.
- Blocking later, by design: /home ≥ T′ at Stop B. A shortfall is projected (T′ ≈ 100–107 GiB by the method sum vs about 96 GiB reachable); the user frees space and rules the T′ base at Stop B.
- Deferred: the 5 GiB /mnt/data floor (proposed, unconfirmed); the AC6/AC6a/AC6b outcomes, which are in-run gates with Decision-required exits.

## Scope guard (MUST follow during the long run)
At each phase boundary and at every Stop:
1. Diff the proposed deliverables against the locked contract.
2. On a material mismatch, pause for the user (PAUSE T3). Do not finish under reduced scope.
3. Do not weaken, skip, narrow or delete checks to satisfy a stop condition (AC18); every changed predicate goes into the check-diff ledger first.
4. Pause for a human decision instead of inventing product or spec choices. That includes an AC6a refusal, AC14 finding no X2AP-type UE ID, and an FU5 burst over 12 GiB.
5. No T-A code is pinned before tag `m10-cp1`, and no T-C code before `m10-cp2`. Checkpoint tags are never moved.

## Codex opener
```text
/goal Complete the M10 post-M9 realism goal on VM ubuntu24.04 as defined by the LOCKED contract plans/reports/contract-261103-0001-GH-1-post-m9-realism-outcome-contract.md.
Read first: plans/261103-0008-GH-1-post-m9-realism-m10/plan.md, then the current phase file, and goal-packet.md (scope guard).
Constraints: contract §5 and §3; fix to spec, no legacy modes; snapshots fresh-install and f7-rerun-green are never deleted; disk ≥ 20 GiB in dev, watchdog trip 37 GiB; pause at Stops A, A′, B.
Validate after each phase: that phase's exit gate (AC numbers in plan.md's phase table) with evidence under the plan's evidence/ directory.
Keep the resume card and journals up to date.
Stop when M10 exits 0 with exactStepSet true and AC20 records are written, or when a Stop or a Decision-required trigger needs human input.
Follow the scope guard.
```

## Claude long-run opener
```text
Complete the M10 post-M9 realism goal (plan rev 3: plans/261103-0008-GH-1-post-m9-realism-m10/plan.md).
Honor the LOCKED outcome contract plans/reports/contract-261103-0001-GH-1-post-m9-realism-outcome-contract.md (incl. Amendment 1).
Validate each phase against its exit gate (AC1–AC20, AC6a, AC6b, AC8b, AC14b); pause at Stops A, A′ and B with a journal, a kongming note and a PAUSE line.
Apply the scope guard in goal-packet.md at every phase boundary. Stop when done or when a human decision is required. Do not auto-expand scope.
```

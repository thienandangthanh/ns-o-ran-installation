# Candidate B

## 1. Outcome

[I] Deliver one post-M9 goal covering E2 interoperability and scale, timing, and radio/counter realism. After reverting `fresh-install`, one unattended invocation must pass the M0–M9 regression and every pre-registered realism gate, exit 0, and produce an independently checkable verdict.

[V] The existing verdict records the exact M9 step set, R3′ C1, reference equality, and PASS: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/verdict.json:298–337`.

## 2. Constraints

[I] This is a proposed contract, not approval or a Ready packet. New acceptance requirements below are proposals; [V] identifies evidence inspected this pass, and [C] identifies carried claims.

- Preserve lock-step gating, late-control refusal, frozen M9 references, and protected snapshots. Never replace a failed reference with the failing output.
- Use Ubuntu 24.04, L-release RIC and NIST 1.8.0; develop on our forks’ branches.
- Preserve raw evidence with hashes; fail closed on missing checks, incomplete captures, stale watchdogs or unsuccessful scrubbing.
- Verify technical choices against the project’s exact Zotero editions before implementation. Missing text blocks the affected choice.
- Resolve audit accounting before warmup: two plan reviews, one pre-ship review and one spare remain the stated cap; this brainstorm’s accounting is unresolved.
- Counsel never substitutes for user approval.

[C] Standards pointers, **unverified against Zotero in this pass**: P1—3GPP TS 38.300 §9.2.3 / 37.340 §10.5.1; P2/P5/P8—E2AP v03 §§9.2.27, 9.2.6, 8.2.4.3; P4/P11—E2SM common v07 §§6.2.2.6, 6.2.3.7; P10—E2GAP v08 §6.1; P6/P9—3GPP TS 28.552 §§5.1.3.6.1.1, 5.1.2.1.1.1; P7—37.340 §4.2.2; P12—KPM v03 §§7.3.2, 8.2.1.1.1, 8.2.1.2.3, 8.3.8. Source: `plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md:60–71`.

## 3. Non-goals

Real QP/R3, scenario-one portability, a scenario-agnostic harness, real AD, prediction-quality claims, publication, and physical-network timing certification remain excluded.

[I] Recommend excluding `UseIdealRrc=false` from delivery. P7 still requires its own PDCP correction; enabling realistic RRC signalling is a separate behavioural expansion. Keep the F″ route-reader remedy; investigate its cause without requiring an upstream remedy.

## 4. Acceptance criteria

All filenames below denote proposed artifacts under the new plan directory.

1. **Operations prelude.** `ops-verdict.json` proves cancellation stops remote gates even after the local wrapper exits; TERM diagnostics identify the actual cancellation source; repeated probe/create/delete/revert cycles leave no newly orphaned overlay; protected images remain referenced and intact. A false sender-side “OK” with a stuck receiver fails `rt_reader_ok`. Watchdog tests cover trip, stale heartbeat and bounded shutdown, with headroom at least approximately 9 GiB and increased when measurements require it. Investigation-only findings go in `route-reader-investigation.md`.  
   [V] The current cleanup depends on the wrapper still existing: `scripts/run-to-m9.sh:120–125`.

2. **P1/P2/P4/P5/P8/N5.** `interop-verdict.json` checks decoded setup and control traffic against an independently specified identity manifest: correct EN-DC mobility owner, valid X2 SETUP component payload, correct eNB/en-gNB node and UE identity alternatives, advertised RC function, and unambiguous cell mapping. Positive controls and wrong-owner, unknown-UE and unknown-cell negatives must agree with ledger/traces. The TS xApp must discover cells from the corrected representation.

3. **P10/P11.** Every expected agent must have nonempty traffic in every new live capture; every agent→e2term DATA chunk must carry PPID 70. An encoder independent of rc sends a standard NR CGI and obtains `applied` plus matching handover traces. Wrong PLMN, malformed and out-of-range targets fail. Recommend a **28-bit gNB ID plus 8-bit local cell component**, with explicit overflow rejection.  
   [V] Current target parsing requires nine custom octets: `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/rc-control.cpp:25–32`.

4. **Scale.** A pre-registered 10-gNB fixture demonstrates cell IDs ≥10 and a decoded KPM report containing at least nine neighbours. `scale-verdict.json` checks expected agents, complete measurements through InfluxDB, unique identities, and successful control to an ID ≥10. Silent truncation at eight fails. Run this integration witness with δ=500 ms.  
   [V] Scenario-zero permits 1–85 gNBs: `ns-3-mmwave-oran/scratch/scenario-zero.cc:283–286`.

5. **M9 compatibility.** With the new delay implementation and δ=0, `compatibility-verdict.json` proves byte equality against the unchanged M9 comparison artifacts. **Proposed interpretation requiring approval:** use an explicit M9 compatibility profile; the corrected realism profile receives separately frozen references. PPID 70 applies in both profiles. This avoids pretending corrected routing and counter semantics can preserve every historical byte.  
   [V] The ledger includes `viaNodeId` and currently sets application time equal to receipt time: `oran-interface/model/e2-control-hub.cc:283–300`.

6. **P3 delay semantics.** Gate δ∈{100,150,200,500 ms}. For accepted controls, application occurs exactly at acceptance-barrier time+δ, including off-grid 150 ms. Recheck mobility state at application; test competing controls, already-completed mobility, late arrival and simulation shutdown. Each acknowledgement-requesting control receives one terminal response; queued receipt is not successful execution. Three live runs and RIC-free replay agree for each δ; RNG sensitivity remains tested. Record measurement age, acceptance, application and handover completion separately. No decision consumes future observations.

7. **P12 and measurement time.** Approve a dedicated P12 brainstorm and plan before fixing it. `subscription-verdict.json` checks configurable kpimon periods and agent option B using `(report,granularity)` milliseconds `(100,100)`, `(500,100)`, `(1000,200)`, plus rejected unsupported combinations. Compare aggregation, multi-record decoding, cadence, deletion and resubscription against IPC ground truth. Keep the TS xApp loop at 100/100 by default. Include opt-in measurement-time stamping: each record’s database timestamp equals decoded collection start plus its record offset; retention and run isolation preserve every expected row.

8. **P6/P7/P9.** `radio-counter-verdict.json` compares packet-level PDCP observations, IPC, decoded KPM and InfluxDB for DL/UL, handover, retransmission and interval boundaries. P6 must use the correct measurement source, type, units and scope. P7 must implement and test the required NR PDCP behaviour, not merely rename the LTE header. P9 must remove false NRCellCU attribution: publish counters under their actual owner; any experimental per-cell allocation must be explicitly named and reconciled without double counting. R3′ must remain measurement-driven after this correction.

9. **Unattended integration.** Freeze `expected-steps.json` before launch: the existing 14 steps plus explicitly named compatibility, interoperability, scale, timing, subscription and counter gates. One invocation after `fresh-install` passes every entry exactly once at the orchestration level, exits 0, preserves R3′ C1/reference checks, and leaves no owned processes. Missing, duplicate or subset steps fail. `budget.json`, watchdog evidence and final `verdict.json` must establish compliance.

10. **Records.** Deliver standards/decision traceability, pins and reference hashes, reviewed gate fixtures, audit accounting, resume/rollback instructions, and a deviation closure matrix covering P1–P12/N5. Update README, architecture and deployment documentation against the final run. Record every remedy, substitution and unresolved limitation. P1–P3-class publication blockers cannot be declared resolved merely through disclosure.

## 5. Trade-offs

[I] Compare the worst plausible case:

| Approach | Principal assumption | Fails first when |
|---|---|---|
| **Fixed δ sweep** | The goal is controlled sensitivity evidence. | Relevant delays lie outside the sweep; it cannot establish field realism. |
| **Campaign first, then choose δ** | Host measurements represent the intended loop. | Simulator slowdown and host load dominate observations, producing misleading calibration and delaying delivery. |
| **Both: campaign informs, fixed sweep gates** | Diagnostic value justifies extra runs. | Disk/wall pressure or incomplete instrumentation makes the campaign expensive but inconclusive. |
| **Sequential milestones in one goal** | Track boundaries permit useful checkpoints. | A shared identity/counter contract changes late; earlier integration needs rerunning. |
| **Develop all tracks together, integrate once** | Shared changes remain independently diagnosable. | A combined failure obscures whether encoding, timing or radio semantics caused it. |

[V] Existing latency measurement excludes preparation: `scripts/gates/pacer.py:28–31,46–48`. Therefore equating measured wall latency with δ is unjustified.

## 6. Better approaches

**none — recommended direction is the requested one.** [C] Both timing reviews favour preserving deterministic gates and adding explicit sim-time delay: `plans/reports/codex-261029-1426-GH-1-timing-realism-advice.md:74–76`.

## 7. Recommended direction

[I] Choose the **fixed sweep**, including 150 ms. It is the smallest sufficient delivery and avoids presenting host-dependent measurements as physical calibration. Defer a free-run campaign to a separate diagnostic decision.

Order the milestones: operations prelude; isolated δ seam and M9 equality; T-A identity/interoperability; approved P12 design and remaining T-B; T-C and predictor reconciliation; combined scale rehearsal; freeze, budget and unattended run.

[C] The old allocation was 55 GiB growth plus reserve: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md:43–46`. [I] With h≥9, provisional need is **≥89 GiB plus new growth**, versus the packet’s 59 GiB available. Count only space actually reclaimed. Budget `/mnt/data` separately.

Recompute wall limits from measured durations and cold-path bounds using the prior 1.5 margin; do not assume the old 20,199-second ceiling covers new gates. Bound evidence retention and avoid intermediate snapshots. Freeze both budgets before launch; insufficient capacity blocks readiness.

[C] The recorded burst rate exceeds the rate behind h≈9; remeasure shutdown-window growth before accepting that headroom: `plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md:20`.

## 8. Draft `ak:goal-warmup` Outcome Contract

- **Intended result:** One fresh-install unattended run passing M0–M9 and all realism gates, exit 0.
- **In scope:** Operations follow-ups 1/2/3/5; investigation-only 4; T-A, T-B including measurement timestamps, T-C; acceptance criteria 1–10.
- **Out of scope:** Section 3; free-run calibration campaign.
- **Acceptance signals:** Exact step manifest, passing verdicts, unchanged M9 reference equality, corrected-profile references, standards ledger, resource evidence and verified documentation.
- **Constraints:** Section 2; approved disk/wall budgets; no weakened gates or silent scope changes.
- **Allowed substitutions:** **Proposed:** explicit M9 compatibility profile for historical byte equality, alongside mandatory corrected-profile gates. No reduced-track or stop-at-R2 substitution proposed.
- **Decision owner:** user.

## 9. Unresolved questions

- Approve the compatibility interpretation, 28/8 identity split, measurement timestamps and exclusion of `UseIdealRrc=false`?
- Do these four brainstorm candidates consume the next goal’s Codex allowance?
- Ratify or replace the carried A1 interpretations and substitutions explicitly.
- Exact Zotero texts, P9 ownership mapping, kpimon multi-record support, rc ACK/timer behaviour, QP’s window and AD polling remain unverified here.
- Final disk availability, shutdown headroom and scale runtime require measurement.

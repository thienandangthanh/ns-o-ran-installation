# Candidate E

## 1. Outcome

[I] Deliver one unattended invocation, after reverting `fresh-install`, that passes the M0–M9 regression and all three realism tracks, exits 0, and records exactly the pre-registered steps. Preserve M9 reproducibility while establishing separately identified evidence for corrected behavior.

All proposed requirements below are [I]. [V] means inspected this pass; [C] means carried from a report. New evidence filenames are proposed.

## 2. Constraints

- Remain on Ubuntu 24.04, L-release RIC and NIST 1.8.0; develop on our forks. Lock-step remains the gate mode.
- Preserve original references, protected snapshots and raw evidence. Never weaken checks, regenerate references after a failed comparison, or treat counsel as approval.
- Check implementation choices against the specified Zotero editions before coding. The [deviation table:60–71](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md:60) supplies the clause map [C]; clauses not explicitly verified below remain **unverified against Zotero**.
- Resolve the Codex accounting before warmup reviews: two plan runs, one pre-ship and one spare remain the stated feature cap.
- This candidate performs no implementation or VM operations.

## 3. Non-goals

Real QP/R3, scenario-one, a scenario-agnostic harness, real AD integration, policy-quality claims, physical-network certification, publication, and replacing the F″ remedy.

Recommend excluding optional `UseIdealRrc=false` and a free-run measurement campaign from this contract. Preserve their status as future choices.

## 4. Acceptance criteria

1. **Operations prelude.** `ops-verdict.json` proves cancellation stops owned VM gates even after the local step process exits; two probe/revert cycles leave no untracked overlay; a sender-success/receiver-stuck case fails readiness through `rt_reader_ok`; watchdog loss, disk trip and deadline expiration fail closed. Record investigation-only findings about stuck readers and retain F″. The orphan guard remains present [V, runner:120–131](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/scripts/run-to-m9.sh:120).

2. **P1/P2/P4/P5/P8/N5.** `interop-verdict.json` links independently decoded setup/control messages to the topology and UE mappings: control reaches the EN-DC owner selected from serving context; component configuration contains a decodable EN-DC X2 SETUP REQUEST; node and UE identity alternatives match their actual roles; RC function 3 is advertised; canonical cell keys round-trip without truncation or collisions. Standards ledger covers 3GPP TS 37.340 §10.5.1, 36.423 §9.1.2.31, E2AP v03 §§9.2.6, 9.2.27, 8.2.4.3 and E2SM common v07 §6.2.2.6 [C, deviation table].

3. **P11.** Propose a 28-bit gNB ID plus 8-bit local cell ID; reject overflow instead of truncating. An encoder independent of rc supplies a standard NR CGI; the ledger says `applied`, and handover start/completion traces identify the intended UE and target. Include wrong-PLMN and unknown-target negatives. NR CGI contains PLMN plus 36-bit NCI [V, Zotero `QW6VJ83M`, §6.2.3.7, p.20]; EN-DC split verification remains outstanding.

4. **P10.** Every expected agent has nonempty agent→e2term DATA traffic in every live capture; every such chunk has PPID 70. Missing agents/captures fail. Judge per association and agent, including compatibility runs. Basis: E2GAP v08 §6.1 [C].

5. **Scale.** A ten-gNB scenario-zero gate proves IDs ≥10 survive setup, storage, prediction and control. At least one UE has nine measured neighbours represented without silent truncation through IPC, KPM and Influx. Record expected versus observed identities and counts. The current limit is eight [V, mmwave header:71](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.h:71).

6. **P3 and compatibility.** `ActuationDelay` defaults to zero. The final delay-capable build, under an explicitly approved M9 compatibility fixture, matches every original judged reference component byte-for-byte; no fields are removed. Corrected profiles receive separate references. This distinction needs approval because references include ledger, IPC, traces and decoded extras [V, comparator:5–11](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/scripts/gates/reference-compare.py:5).

7. **Delayed execution.** Gate δ ∈ {100,150,200,500} ms. For accepted decisions, execution occurs at decision sim-time + δ, including 150 ms without boundary rounding. Advance simulation while waiting; perform state prechecks at execution. Test overlapping controls, stale state and shutdown with pending controls; require exactly one appropriate terminal answer, deterministic ordering, no future observations, and distinct initiation/completion timestamps. Each δ passes three live runs and RIC-free replay; changed RNG produces the registered difference. Current application is instantaneous [V, hub:243–288](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/oran-interface/model/e2-control-hub.cc:243).

8. **P12.** Approve its dedicated brainstorm and plan before implementation. Configure kpimon and implement agent option B. Proposed supported domain: granularity G is an integer multiple of sample period T; reporting R is an integer multiple of G. Unsupported requests receive standards-valid rejection. Gate `(G,R)` of `(100,100)`, `(200,1000)` and `(10000,10000)` ms plus invalid combinations. Check counts, interval boundaries, metric-specific aggregation, multiple-record decoding and subscription deletion. The closed loop uses 100 ms, not stock 10 s. KPM v03 distinguishes these intervals [V, Zotero `F82PYZVK`, §§7.3.2, 7.4.2.2–4, 8.2.1.1.1].

9. **Measurement time.** Include opt-in kpimon measurement-time stamping: each record uses Collection Start Time plus its granularity offset. `timestamp-verdict.json` proves correct times, unique retained rows and complete windows despite delayed arrival; isolated bucket retention admits the pinned epoch. Compatibility mode retains its historical timestamp behavior.

10. **P6/P7/P9.** `radio-counter-verdict.json` proves actual PDCP PDU measurement replaces the MAC-derived mislabeled row, with correct type, unit and measurement object; EN-DC uses NR PDCP serialization on both endpoints; SDU/PDU accounting handles header size and handovers without duplication. Standard counters belong to their actual owner. Propose explicitly private per-secondary-cell attribution for R3′ where needed. Recheck complete Influx=IPC windows and observation-sensitive decisions. Governing clauses include 3GPP TS 37.340 §4.2.2 and 28.552 §§5.1.3.6.1.1, 5.1.2.1.1.1 [C].

11. **Final unattended run.** Commit `expected-steps.json` before execution. It includes `m0…m7,i0,r0,r1,i2,r2,r3p`, compatibility verification and every realism gate above. Require fresh-install provenance, exit 0, exact ordered steps, all verdicts passing, frozen pins/references, watchdog continuity and resource compliance. Partial runs and skipped tracks cannot pass.

12. **Records.** Deliver the standards/decision ledger, traceability matrix, pins, reference manifests, budget, resume card, run report, deviation closure table and audit dispositions. Update README, architecture and deployment instructions against actual results. Explicitly distinguish modeled delay, wall latency, handover initiation and completion.

## 5. Trade-offs

| Approach | Principal assumption | First failure in the worst plausible case |
|---|---|---|
| **Fixed δ sweep** | A sensitivity study satisfies timing realism | Readers mistake chosen delays for measured network latency |
| Campaign first | Host measurements meaningfully inform δ | Slowdown/load dominate measurements and no defensible δ emerges |
| Both | Extra campaign cost buys useful interpretation | Campaign expands while disk and integration budgets are already tight |
| **One goal, sequential milestones** | Interfaces can be frozen between tracks | P9 changes invalidate predictor assumptions late |
| Separate goals per track | Intermediate releases are acceptable | Delivery stops before the user’s combined unattended outcome |
| Parallel track implementation | Shared identity, ledger and metric contracts are stable | Conflicting changes force repeated reference generation |

Recommend fixed sweeps and one sequential goal. Separate goals conflict with the present ruling; parallel implementation offers little protection against shared-contract changes.

## 6. Better approaches

**A larger, measured watchdog margin is better supported than adopting h≈9 unchanged.**

[V] M9 lost 2 GiB in 30 seconds at [free-series.tsv:143–144](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/free-series.tsv:143). [C] The budget’s stop path is 370 seconds ([budget:34](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md:34)). [I] Its formula therefore gives h=25 GiB before measurement uncertainty.

Propose retaining that conservative margin until finer measurements or a shorter proven stop path justify less. Operational delta: earlier stopping and more required free space. Switching cost: budget/watchdog configuration and validation. This challenges h≈9 explicitly; it does not authorize changing it.

## 7. Recommended direction

[I] Order: operations prelude; identity/interop and scale; delay compatibility proof; dedicated P12 design and timing implementation; radio/counter corrections; integrated references and rehearsal; final unattended run.

Use fixed δ sweeps as modeled sensitivity evidence. Include measurement timestamps; leave ideal-RRC replacement for a separate decision.

[C] The old budget required 55 GiB growth plus floor/headroom. With proposed h=25, reserve **105 GiB plus measured additional peak growth**. At the packet’s 59 GiB free, the provisional shortfall is **46 GiB plus additions**. Do not count `/mnt/data` as `/home` capacity or assume overlay reclamation succeeds.

Measure cold builds, scale and sweep costs; freeze per-step limits and a global wall budget before launch. Retain the 25 GiB floor, supervised execution and fail-closed cancellation. The old 20,199-second cap is historical, not a promise for this larger run.

## 8. Draft `ak:goal-warmup` Outcome Contract

- **Intended result:** One fresh-install unattended regression-plus-realism run satisfying criteria 1–12.
- **In scope:** T-A, T-B and T-C; operations prelude; bounded route-reader investigation; reproducibility, evidence and documentation.
- **Out of scope:** Section 3.
- **Acceptance signals:** Criteria 1–12, exact step manifest, exit 0 and passing aggregate verdict.
- **Constraints:** Section 2; approved compatibility boundary; measured disk/wall budgets; no silent scope reduction.
- **Allowed substitutions:** **Proposed:** historical behavior confined to the M9 compatibility fixture, with PPID 70 still mandatory; private per-secondary-cell predictor attribution while standard counters retain correct ownership. Neither is approved.
- **Decision owner:** user.

## 9. Unresolved questions

- Approve the compatibility fixture, private predictor metric, optional-item exclusions and larger headroom?
- Do this brainstorm’s four Codex runs consume the next goal’s cap?
- Ratify inherited interpretations (a)–(k); do not silently inherit substitution 4’s R2 fallback.
- Verify remaining Zotero clauses, EN-DC identity ownership, rc’s outcome-less-ACK behavior and timer, kpimon multi-record handling, retention, and actual resource costs. AD polling and QP wall-window semantics remain unverified and outside this delivery.

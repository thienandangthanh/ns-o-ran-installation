# Candidate I

## 1. Outcome

[I] Deliver one unattended invocation from `fresh-install` that passes the M0–M9 regression and all three realism tracks, exits 0, and produces a verdict matching a frozen, pre-registered step manifest.

[V] The existing M9 verdict records exact-step success, R3′ reference equality, and 59 GiB minimum free space ([verdict.json:314](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/verdict.json:314)).

All proposed requirements below are [I]; evidence claims carry separate labels. Named new evidence files are proposed deliverables, not existing results.

## 2. Constraints

- Preserve lock-step, deterministic ordering, late refusal, original M9 references, protected snapshots, and fail-closed gates.
- Use Ubuntu 24.04, L-release RIC, NIST 1.8.0, and branches on our forks. Record exact pins.
- Judge decoded wire traffic, ledgers, counters and handover traces; distinguish initiation from completion.
- Check each technical decision against versioned standards through Zotero before implementation. Missing text remains an explicit preflight dependency.
- Preserve the Codex cap pending the user’s accounting ruling. Kongming advises; the user approves.
- This candidate remains read-only; it neither starts warmup nor authorizes execution.

## 3. Non-goals

Real QP/R3, scenario-one, scenario-agnostic harness, real AD integration, unscheduled-control redesign, real-time simulator replacement, prediction quality, publication, and physical-network latency guarantees.

Recommend excluding optional `UseIdealRrc=false`: it adds a signalling-model change beyond P6/P7/P9. [V] Scenario-zero currently forces ideal RRC ([scenario-zero.cc:483](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/ns-3-mmwave-oran/scratch/scenario-zero.cc:483)); compatibility of the alternative remains untested.

## 4. Acceptance criteria

1. **Ops prelude:** `ops-verdict.json` proves cancellation stops owned VM gates even when the host step already died; TERM attribution is accurate; repeated probe/revert cycles leave no untracked overlay; receiver checks reject a false sender-side OK; watchdog-loss and disk-trip tests pass. Set provisional headroom h≈9 and validate its stop-path coverage. `route-reader-investigation.md` records findings without replacing F″.

2. **M9 preservation:** Original references remain hash-identical. A pinned build containing the delay implementation, before semantics-changing realism fixes, reproduces M9 at default δ=0 across every original comparison component, without filtering changed fields. The final runner retains this compatibility stage. Corrected realism builds receive separately frozen references. **This comparison boundary requires explicit user approval.**

3. **P1/P2/P4/P5/P8/N5:** `interop-verdict.json` proves source/control-owner routing, populated EN-DC X2 SETUP content, role-correct eNB/en-gNB identities, valid UE-context mapping, RC function advertisement and acceptance, and consistent cell identity across setup, TS xApp, rc and agent. Malformed, unknown and misaddressed cases fail predictably.

4. **P10:** Every agent has nonempty captured traffic. Every agent→e2term SCTP DATA chunk in every realism live capture carries PPID 70, judged per agent. Missing associations or incomplete captures fail.

5. **P11:** An encoder independent of rc builds the spec-format NR CGI; its control produces `applied`, matching handover-start and completion traces. Recommend a **28-bit en-gNB ID plus 8-bit cell portion**, with explicit overflow rejection and PLMN validation. [V] Common E2SM v7 permits 22–32-bit node IDs and specifies 36-bit NCI; RC v3 §8.4.4.1 identifies parameter 4 as NR CGI (Zotero `QW6VJ83M`, PDF pp.19–20; `XRWZU3SS`, p.166).

6. **Scale:** A locked **10-gNB** scenario exercises cell IDs ≥10, successful control to such a cell, and at least one populated report containing **nine neighbours**, verified through IPC, decoded KPM and Influx. No silent truncation, missing nodes or duplicate rows passes. [V] Current neighbour extraction is capped ([mmwave-enb-net-device.cc:974](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:974)).

7. **P3:** `delay-verdict.json` covers δ={0,100,150,200,500} ms. Application occurs exactly at decision time+δ, including off-grid 150 ms. Release the barrier before awaiting delayed application. Recheck eligibility at application; preserve deterministic ordering; fail pending controls at stop; produce exactly one requested terminal response. Record decision, reception, application and completion separately. [V] Present code applies synchronously and records identical reception/application times ([e2-control-hub.cc:266](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/oran-interface/model/e2-control-hub.cc:266)).

8. **P12:** Approve its dedicated brainstorm and plan before fixing it. Configure kpimon and implement agent option B together. Gate 100/100-ms granularity/reporting, 200/1000-ms aggregation, multi-record decoding, subscription changes, and explicit rejection of unsupported periods. Verify aggregation semantics per metric. [V] KPM v3 defines reporting milliseconds and collection granularity separately (Zotero `F82PYZVK`, PDF pp.21,29, §§8.2.1.1.1,8.3.8).

9. **Measurement time:** Include opt-in kpimon measurement-time stamping. `timestamp-verdict.json` checks decoded collection start plus record offsets, distinct arrival diagnostics, complete row cardinality, and pinned-epoch retention/isolation. Preserve compatibility-mode output.

10. **P6/P7/P9:** `radio-counter-verdict.json` reconciles DL/UL counters against independent per-PDU accounting before, during and after handover. Verify source layer, units, encoding type, aggregation and hosting entity. Implement NR PDCP framing on both EN-DC endpoints with serialization, reception and sequence-boundary tests. Standard metric names must match their actual semantics.

11. **R3′ continuity:** After counter corrections, its documented input still comes from complete, duplicate-free Influx windows and demonstrably changes decisions. A custom per-secondary-cell projection is acceptable **only under the proposed substitution below**; no silent fallback to the old mislabelled counter.

12. **Repeatability and integration:** Each delay case passes three live runs plus RIC-free replay; the seed-change check remains effective. The 10-gNB case also passes at δ=500 ms with aggregated reporting. Freeze inputs before judged runs.

13. **Unattended completion and records:** One invocation executes the original 14-step regression, required corrected-stack regressions and all new gates. `verdict.json` rejects omitted, duplicate, substituted or partial steps; records pins, references, wall time, disk minima and watchdog continuity. Deliver standards/deviation ledgers, budget, audit accounting, resume card, run report, and verified README/architecture/deployment updates.

## 5. Trade-offs

| Approach | Main assumption | First failure in the worst plausible case |
|---|---|---|
| **Fixed δ sweep** | Sensitivity analysis satisfies this goal’s timing claim | Deployment latency lies outside the sweep; deployment claims remain unsupported |
| Campaign first, then select δ | Host measurements represent relevant latency | Slow simulation and partial-loop measurements produce misleading values |
| Campaign plus fixed gates | Additional measurement cost is affordable | Campaign consumes disk/time without changing any gated conclusion |

Recommend the fixed sweep. [C] Timing counsel explicitly warns that measured L excludes parts of the loop and is host-dependent ([timing advice:222](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/reports/kongming-261029-1426-GH-1-timing-realism-advice.md:222)).

For goal shape, **serial milestones within one goal** assume intermediate interfaces can be frozen; they fail first through schedule growth. Concurrent tracks assume stable shared schemas; they fail first through incompatible identity, ledger and counter changes. Serial delivery has the smaller integration risk.

## 6. Better approaches

**none — recommended direction is the requested one**, with explicit compatibility/reference separation.

[V] M9’s current ledger contains routing identity, while its counters subtract an LTE PDCP header and attribute MN-hosted volume to secondary cells ([e2-control-hub.cc:289](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/oran-interface/model/e2-control-hub.cc:289); [mmwave-enb-net-device.cc:653](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:653)). [I] Correcting those semantics changes compared evidence; identical corrected-output bytes cannot be presumed.

## 7. Recommended direction

Choose the **fixed sweep**, labelled modelled sensitivity points. A free-run campaign can follow separately; it does not choose or alter this goal’s gates.

Order: ops prelude → delay implementation and δ=0 compatibility checkpoint → T-A identity/interoperability → P12 and measurement timestamps → T-C counters/radio → combined scale/delay validation → freeze, resource approval and unattended run.

Use two pinned build manifests instead of adding compatibility switches throughout every component. Budget both installations and their evidence.

[C] The old requirement was 84 GiB with h=4 ([m9-budget.md:43](/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md:43)). [I] With unchanged growth and h=9, the starting estimate becomes **89 GiB plus realism growth**, already ≥30 GiB above the packet’s 59 GiB.

Measure cold-path duration and peak storage for the exact manifest; include builds, captures, reboots and cleanup. Freeze per-step and global caps before launch. Use sequential runs, bounded evidence retention and the repaired overlay lifecycle. Neither the old 20,199-second cap nor `/mnt/data` space automatically covers this workload.

## 8. Draft `ak:goal-warmup` Outcome Contract

- **Intended result:** One unattended fresh-install execution passes M0–M9 compatibility and all post-M9 realism gates.
- **In scope:** Ops follow-ups 1/2/3/5; investigation-only follow-up 4; T-A, T-B and T-C; measurement timestamps; scale; regression and documentation.
- **Out of scope:** Section 3; S1/S3 remain deferred.
- **Acceptance signals:** Criteria 1–13, frozen manifests, successful exact-step verdict and archived evidence.
- **Constraints:** Section 2; approved resource budget; standards checks; immutable references; no weakened gates.
- **Allowed substitutions:** **Proposed:** evaluate original-byte equality using the delay-enabled compatibility build and corrected semantics using new references. **Proposed:** retain useful per-secondary-cell MN volume under an explicit custom metric, alongside correctly attributed standard counters, and update R3′ accordingly.
- **Decision owner:** user.

## 9. Unresolved questions

- Approve the compatibility/reference split and custom-counter substitution?
- Accept the fixed sweep, included timestamps and excluded optional real RRC?
- Do these four brainstorming Codex runs consume the next goal’s cap? Ratify A1 interpretations explicitly?
- Remaining standards checks include E2AP v3 §§9.2.6/9.2.27/8.2.4.3, E2GAP v8 §6.1, 3GPP TS 37.340 §4.2.2 and 28.552 §§5.1.3.6.1.1/5.1.2.1.1.1: **unverified against Zotero** this pass.
- Reconcile h≈9 with the reported 0.067 GiB/s burst and 370-second stop path: sustained growth would require approximately 25 GiB headroom [I]. Live timing, rc failure behaviour and final resource needs remain untested.

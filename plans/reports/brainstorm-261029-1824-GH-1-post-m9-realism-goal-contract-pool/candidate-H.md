# Candidate H

## 1. Outcome

[I] Deliver one post-M9 goal covering interoperability, timing and radio/counter realism. After reverting `fresh-install`, one unattended invocation passes the M0–M9 regression and every new realism gate, exits 0, and produces a verdict matching a frozen step manifest.

[I] Preserve M9 byte equality through an explicitly approved compatibility profile; judge corrected semantics against separate references. This boundary requires approval before planning.

## 2. Constraints

Requirements and recommendations below are [I]. [V] identifies code/evidence inspected this pass; [C] identifies carried report claims.

- Keep lock-step, deterministic ordering, late refusal, independent wire decoding, ledger/trace checks and fail-closed supervision.
- Use Ubuntu 24.04, L-release RIC and NIST 1.8.0; develop on `origin` forks.
- Preserve protected snapshots, original references and raw evidence. Never weaken checks or regenerate references during the final run.
- Check technical decisions against the specified Zotero editions before implementation. Zotero configuration resolved, but reads failed because the read-only sandbox had no usable temporary directory. Clauses below are **unverified against Zotero**.
- P12 requires its own brainstorm and plan before modification.
- Resolve Codex accounting before warmup’s reviews; counsel is never approval.

## 3. Non-goals

Real QP/R3, scenario-one, a scenario-agnostic harness, real AD, prediction-quality claims, physical-RAN certification, `RealtimeSimulatorImpl`, stochastic delay distributions and publication remain excluded.

[I] Recommend leaving optional `UseIdealRrc=false` outside acceptance: P7 already changes radio serialization, while nonideal RRC adds another execution model. The current setting is explicitly true [V, `ns-3-mmwave-oran/scratch/scenario-zero.cc:483`].

## 4. Acceptance criteria

All new evidence filenames below are proposed under the new plan.

1. **Ops prelude.** `evidence/ops/verdict.json` proves cancellation cleans remote gates even after the local child exits; TERM messages identify the actual cause; repeated M0-probe/revert cycles leave no untracked overlay; protected backing chains remain intact. Receiver readiness uses `rt_reader_ok`, including a sender-success/receiver-stuck negative case. The orphan guard exists [V, `scripts/run-to-m9.sh:122`]. Follow-up 4 produces a bounded investigation report, with “cause unresolved” permitted; F″ remains.

2. **Budget and supervision.** `budget.json` records measured growth, cold-path durations, stop latency, per-step limits and a global deadline. Adopt headroom **at least 9 GiB**, increasing it if burst measurements require. Cancellation, stale/missing watchdog and deadline tests must fail closed. Final minimum free space is ≥25 GiB; development retains its ≥20 GiB floor.

3. **P1/P2/P4/P5/P8/N5.** `evidence/interop/verdict.json` checks source/procedure-owner routing; role-correct eNB/en-gNB and UE identities; independently decoded EN-DC X2 SETUP content; advertised RC function and supported controls; collision-free cell mapping. Wrong-owner, unknown-UE and unsupported-function requests fail explicitly. Standards anchors [C]: 3GPP TS 37.340 §10.5.1; E2AP v03 §§9.2.6, 9.2.27, 8.2.4.3; E2SM common v07 §6.2.2.6 (`plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md:60`).

4. **P10.** Every expected agent has captured outbound DATA chunks, and **every agent → e2term DATA chunk in every live capture carries PPID 70**, checked per association and agent. Missing-agent captures fail. This includes compatibility runs. The current sender uses plain `send()` [V, `oran-e2sim/e2sim/src/SCTP/e2sim_sctp.cpp:228`]. Standard anchor [C]: E2GAP v08 §6.1.

5. **P11.** Recommend a **28-bit gNB ID plus 8-bit cell component** within the 36-bit NCI, with explicit range rejection. An encoder independent of rc constructs the target; decoded identity, ledger `applied`, handover-start and handover-end traces agree. Test boundary values, malformed encodings and unknown targets. Current decoding requires nine proprietary octets [V, `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/rc-control.cpp:25`]. Anchors [C]: E2SM-RC v03 §8.4.4.1; common v07 §6.2.3.7; 3GPP TS 36.423 §§9.2.111–112.

6. **Scale.** `evidence/scale/verdict.json` proves a 10-gNB run, controls involving cell IDs ≥10, and KPM reports containing **at least nine distinct neighbours reaching kpimon** without truncation, misidentification or dropped required records. Merely configuring ten nodes fails acceptance. The configured range is 1–85 [V, `ns-3-mmwave-oran/scratch/scenario-zero.cc:283`]; neighbour emission is currently capped [V, `ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:974`].

7. **P3 and reproducibility.** `ActuationDelay` defaults to zero. The approved compatibility profile matches every existing M9 reference component byte-for-byte. Corrected-profile runs cover δ={0,100,150,200,500} ms. Ledger checks require application exactly at decision time+δ, including 150 ms without rounding to a reporting boundary. Recheck eligibility at application; test competing controls, stale targets and pending controls at shutdown. Require deterministic repeats, RIC-free replay and seed nonvacuity. Receipt and application currently share one timestamp [V, `oran-interface/model/e2-control-hub.cc:285`].

8. **Timing causality.** `timing-events.jsonl` separates collection, decision, receipt, application and handover completion; decisions consume no later observations. Each request has the prescribed terminal response, with no premature success. Delayed execution must not deadlock the pacer. Exercise δ=500 ms at scale. `APPLIED` currently follows handover initiation [V, `ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:4605`].

9. **P12.** After its dedicated design approval, configurable kpimon periods and agent option B pass wire-to-storage tests: default 100/100 ms; a longer equal-period case; and reporting 1000 ms with granularity 100 ms. Verify record count, collection intervals, metric-specific aggregation, subscription deletion and explicit rejection of unsupported requests. No silent rounding or stock-10-second starvation. Anchors [C]: KPM v03 §§7.3.2, 8.2.1.1.1, 8.2.1.2.3, 8.3.8 (`plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md:71`).

10. **Measurement time.** Include opt-in kpimon measurement-time stamping in the corrected profile. `measurement-time-verdict.json` proves `_time` equals decoded collection start plus each record’s granularity offset, independent of arrival delay. Test ordering, timestamp collisions and retention of the pinned epoch. Preserve arrival time separately. Existing storage uses arrival time [C, `docs/system-architecture-l-release.md:111`].

11. **P6/P7/P9.** `radio-counter-audit.json` reconciles packet-level PDCP evidence, IPC, decoded KPM and Influx across UL/DL and handover. P6 uses genuine PDCP PDU measurements and verified units; P7 implements NR PDCP header encoding/decoding and sequence boundaries for the exercised bearer; P9 reports MN-hosted totals under their correct scope. Any per-serving-cell derived series used by R3′ gets an explicit simulator-specific name. No double counting or standard-name disguise. Anchors [C]: 3GPP TS 37.340 §4.2.2; 28.552 §§5.1.3.6.1.1, 5.1.2.1.1.1. Current code uses `LtePdcpHeader` [V, `ns-3-mmwave-oran/src/lte/model/mc-enb-pdcp.cc:247`].

12. **Integrated delivery.** Freeze `expected-steps.json`, pins, schedules, both reference sets and budget before the final invocation. `steps.tsv` must match exactly, with no missing, duplicate, extra or skipped steps. Include the existing fourteen steps plus registered realism gates; retain R3′, its complete data-window checks and C1. Verdict, exit status and supervision must agree. Update README, architecture/deployment docs, standards ledger, resume card and run report with evidence links, remaining limitations and applied substitutions.

## 5. Trade-offs

| Approach | Main assumption | First failure in the worst plausible case |
|---|---|---|
| **Fixed δ sweep** | Sensitivity coverage is useful without claiming measured realism. | Actual latency lies outside the range; conclusions need explicit bounds. |
| **Campaign first, then select δ** | Free-run latency transfers meaningfully to the modeled loop. | Simulator slowdown and host load distort the selection; preparation latency is omitted. |
| **Both** | Additional diagnostic evidence justifies campaign cost. | Campaign expands disk/wall demand without changing deterministic acceptance. |
| **Complete timing first** | Counter and identity semantics remain stable. | P9/P12 later invalidate timing fixtures and references. |
| **Semantic foundations first, with an early zero-delay check** | Dependency ordering reduces rework. | Radio work delays integration; bounded milestone gates expose this before the final run. |

[C] Counsel specifically warns against equating measured wall latency with gated δ (`plans/reports/kongming-261029-1426-GH-1-timing-realism-advice.md:229`).

## 6. Better approaches

**none — recommended direction is the requested one**, with an explicit compatibility boundary. Existing comparison covers ledger, IPC, traces and extra digests [V, `scripts/gates/reference-compare.py:5`]; silently replacing those references would conceal semantic changes.

## 7. Recommended direction

Choose the **fixed sweep**, including 150 ms. It provides repeatable sensitivity evidence with bounded scope. Describe it as modeled latency, without claiming the values are empirically realistic.

Order: ops prelude; universal PPID correction and zero-delay compatibility proof; T-A identity/control work; T-C radio/counters; T-B subscription/timestamps and delay sweeps; integrated scale; freeze; unattended run.

[C] The old disk allocation was 84 GiB with h=4 (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md:43`). With h≥9, budget **at least 89 GiB plus incremental growth**, subject to burst recalibration. The packet’s 59 GiB leaves ≥30 GiB plus that increment unfunded. Do not count `/mnt/data` as interchangeable or assume leaked space is recoverable.

Recalculate wall limits from measured cold paths; the previous 20,199-second allowance does not automatically cover new gates. Keep sequential VM execution and the supervised systemd launch route.

## 8. Draft `ak:goal-warmup` Outcome Contract

- **Intended result:** One unattended fresh-install regression and realism run passes its exact frozen step set and exits 0.
- **In scope:** Acceptance criteria 1–12; all three tracks; ops fixes and bounded route-reader investigation; measurement-time stamping.
- **Out of scope:** Section 3 exclusions, including optional nonideal RRC.
- **Acceptance signals:** Scripted verdicts, independent wire evidence, packet/counter reconciliation, deterministic replay, preserved M9 equality, exact-step final verdict and verified documentation.
- **Constraints:** Sections 2 and 7; standards verification; protected evidence/snapshots; explicit budgets; no weakened gates.
- **Allowed substitutions:** **proposed** — scope historical byte equality to an explicit M9 compatibility profile while corrected semantics use separately frozen references. PPID 70 remains universal. No automatic R2 fallback or track reduction.
- **Decision owner:** user.

## 9. Unresolved questions

- Approve the compatibility boundary, 28/8 identity split, fixed sweep, measurement-time inclusion and nonideal-RRC exclusion.
- Do this brainstorm’s four Codex runs consume the next goal’s cap?
- Ratify or resolve inherited interpretations (a)–(k) and substitution carry-over.
- Verify Zotero clauses, kpimon multi-record handling, rc’s outcome-less-ACK/timer claims, AD polling and QP window semantics before relying on them.
- Establish the recoverable disk amount and acceptable revised wall ceiling before declaring Ready.

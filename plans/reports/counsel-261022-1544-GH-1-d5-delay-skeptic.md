# D5 counsel: the case against a "transmission delay" (skeptic and minimalist lens)

I have not read the other two D5 counsel reports (`counsel-261022-1544-GH-1-d5-*`), and this report does not use them.

- **Date:** 2026-10-22 (Asia/Seoul).
- **Runtime:** Opus 5.5 at xhigh effort, as the caller's CLAUDE.md asks, not `fable`.
- **Inputs read:**
  - the pacing checkpoint journal;
  - pacing counsels A, B and C, read for their d = 0 / d = 1 passages;
  - the ns-3 fork at `ace32168`;
  - the M7 and probe evidence traces.
- **Mode:** read-only. Nothing ran on the VM. No commits.

---

## TL;DR

**Keep d = 0 as the permanent default.** Strike "transmission delay" from the roadmap. It names the wrong quantity, because lock-step collapses every loop latency into one sim-time apply offset, and the E2 downlink is the smallest part of that offset. Wall-clock delay is erased by the barrier, so if it is ever modelled it can only live in ns-3's sim time. At ≤ 10 ms against a 0.1 s observation period, it cannot change anything the RIC sees.

Build a delay only when a written latency-sensitivity study needs it. It would then be a multi-period `controlLoopDelay` sweep, with the prechecks and the ACK moved to apply time. That is a different feature from the one D5 describes.

**One premise in the brief is wrong, and correcting it weakens my own case.** The in-sim handover is not "multi-hundred-ms": it takes about 5–6 ms of sim time (§2, A3). So 10 ms is small next to the KPM period, but not small next to the handover. My argument rests on the period alone.

---

## 1. Reframed problem

**The real decision.** D5 asks for a realism knob. The question underneath is: *which sim-time latency between "the KPM report for period k exists" and "the control acts in the RAN" does this testbed claim to model, and does any result depend on it?*

- **Requirements already locked:**
  - lock-step, one step = P = 0.1 s;
  - ns-3 is the only clock;
  - the repeat gate is bit-identical;
  - controls are sorted, prechecked, applied synchronously and ACKed once scheduled.
- **Goal of the testbed.** The contract's goal is an integration port: "RC control must cause a handover inside ns-3" (`plans/reports/brainstorm-261017-0308-GH-1-ns-oran-l-release-nist-1-8-0-contract.md:32-37`). A realism study is not the goal.
- **Contract non-goal:** "Changing ns-3 radio/scenario behaviour" (`:57-64`).
- **Not in question:** any wall-clock mechanism. Lock-step already absorbs wall latency.

---

## 2. Evidence (verified unless marked)

| # | Fact | Source |
|---|---|---|
| E1 | Scenario-zero sets no EPC link delay. The defaults apply: X2 = 1 ms, S1-AP = 15 ms, S1-U = 1 ms. | `ns-3-mmwave-oran/src/mmwave/helper/mmwave-point-to-point-epc-helper.cc:189-226`. Grep of `scratch/scenario-zero.cc` for those attributes: no hits. The 10 ms p2p at `:427-430` is PGW ↔ remote host only. |
| E2 | Ideal RRC is used, with a 0.5 ms message delay. | `scratch/scenario-zero.cc:350`; `src/mmwave/model/mmwave-rrc-protocol-ideal.cc:60` |
| E3 | The control path is `PerformHandoverToTargetCell`. It sends an X2 McHandoverRequest (LTE → source gNB). Then: source → target HO Request, then target → source HO Request Ack. The eNB `HandoverStart` trace fires at the source **after the Ack**, so 3 X2 hops ≈ 3 ms after apply. The end is followed by one more X2 hop (SecondaryCellHandoverCompleted → LTE). | `src/lte/model/lte-enb-rrc.cc:4478-4532`, `:5053-5061`, `:5193-5206`, `:880-913`, `:1860-1876` |
| E4 | **Measured** eNB HandoverStart → HandoverEnd in sim time: min 1.568 ms, p50 1.70 ms, max 1.80 ms (n = 385, DynamicTtt). The UE side is 0.57–0.72 ms. | `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m7/20261021T233129Z/ns3run/{Enb,Ue}Handover{Start,End}Stats.txt` (paired rows, same IMSI) |
| E5 | **Derived:** control apply → handover end ≈ 3 ms + 1.7 ms ≈ 4.7 ms. The LTE master marks the UE free again ≈ 1 ms later. Busy window ≈ 5–6 ms. | E1 + E3 + E4. Not measured end-to-end: no control-path trace exists yet. |
| E6 | Under NoAuto, `TriggerUeAssociationUpdate` still runs every 1.6 ms. It can still switch an IMSI to LTE on outage. `m_e2ControlledUes` skips a UE only after `TakeUeHoControl`, which the plan does not call. | `lte-enb-rrc.cc:3318-3322` (CrtPeriod 1600 µs), `:4817`, `:4690`, `:4755-4778`; scenario-zero `:173-176` ("use -1000.0 with NoAuto"); journal §5 item 7 |
| E7 | `PerformHandoverToTargetCell` on a UE that is already in handover is a silent no-op that only prints a warning. | `lte-enb-rrc.cc:4519-4529` |
| E8 | KPM counters are period aggregates that reset at each report. The L3 SINR is a last-value snapshot. | `src/mmwave/model/mmwave-enb-net-device.cc:778`, `:1152`, `:352-355`; report reschedule `:1510` |
| E9 | UE speed is 2–4 m/s. The channel and channel-condition update period is 100 ms. | `scratch/scenario-zero.cc:486-490`, `:360-362` |
| E10 | `indicationPeriodicity` accepts values down to 0.01 s. | `scratch/scenario-zero.cc:166-168` |
| E11 | ns-3 orders same-timestamp events by insertion uid. This is deterministic, and the default is MapScheduler. | `src/core/model/scheduler.h:273-280`; `src/core/model/simulator.cc:78-80` |
| E12 | Prior art: the authors' own lock-step (ns-o-ran-gym file mode) applies controls with `Seconds(0)` at the barrier's sim time. | `src/lte/model/lte-enb-net-device.cc:189-194`, after `sem_wait` `:123-130` |
| E13 | The measured 6.6 ms p50 (max 9.9 ms) is wall clock and includes grpcurl start-up. | journal §6, `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md:145` |
| E14 | The near-RT RIC loop is 10 ms – 1 s. Loops under 10 ms (scheduling, beam management) are outside the near-RT RIC. | Polese et al., "Understanding O-RAN", IEEE COMST 2023, [arXiv 2202.01032](https://arxiv.org/pdf/2202.01032); [dApps, arXiv 2203.02370](https://arxiv.org/pdf/2203.02370). Secondary sources; the WG1 AD text was not read. |
| E15 | Counsel C proposed d = 1 for **wall-time overlap** (max(C, W) instead of C + W), not mainly for realism. | `plans/reports/counsel-261022-1045-GH-1-pacing-c.md:52-60`. Journal D1 then chose a pacer that releases non-trigger steps at once (§5 item 2). |

---

## 3. Answers to the five questions

### Q1. What "transmission time from sender to receiver" means, and double counting

**The hops.**

| Hop | In the real world | Modelled in sim time today? |
|---|---|---|
| TS decides | xApp compute | No |
| TS → rc (gRPC) | process to process | No |
| rc → RMR → e2term | RIC platform | No |
| e2term → E2 node (SCTP) | the actual "transmission" | No |
| E2 node → RRC | E2 node processing | No |
| RRC/X2/RACH until the UE moves | inside the RAN | **Yes**: ns-3 models about 5–6 ms of it (E5) |

All wall latency on the RIC side is absorbed by the barrier: ns-3 waits until it has read the control.

**Double counting depends on what "receiver" means.**
- If the receiver is the E2 node, an E2-downlink delay is *not* double counting. ns-3 has no E2 transport model, and I concede this point.
- If the receiver is "the UE has moved", ns-3 already models that part. Adding it again would count it twice.

**The decisive point is the uplink.** In lock-step, the RIC sits outside sim time. An uplink delay (indication → xApp) and an xApp compute time leave ns-3's trajectory unchanged until the control lands. Every loop component therefore collapses into one identifiable number: `d_loop = d_E2up + d_xApp + d_E2down`, applied as `t_apply = t_k + d_loop`.

A "transmission time from sender to receiver" models only `d_E2down`. That is at most a third of the loop, and the smallest third.
- If you ever model this, model `d_loop`.
- Do not take its value from the 6.6 ms wall figure. That figure measures a VM's k8s networking plus a grpcurl start-up (E13), not any deployment's E2 link.

**Cosmetic next to the period?** Yes. See Q3.

### Q2. Is the observation side the bigger realism error?

The asymmetry is weaker than the brief suggests.
- **Aggregation is modelled.** d = 0 does not ignore the aggregation lag. The xApp decides on counters aggregated over (t_{k−1}, t_k] (E8). In the real system, information is equally between 0 and P old when the report leaves the node. What d = 0 drops is the loop latency, and by Q1 that is one number, not two asymmetric errors.
- **The observation side already departs much further from reality, on purpose:**
  - P = 0.1 s, while kpimon requests 10 s. The testbed honours 0.1 s because 10 s starves QP (journal §3, Q5 row; counsel C trap at `counsel-…-c.md:217`). That is a 100× change in observation rate.
  - Ideal RRC (E2).
  - The SINR field is a last-value snapshot (E8).

  Adding 10 ms of actuation "realism" on top of these is an uneven realism budget.
- **d = 0 is not faster than near-RT.** Measured from the first sample in the window to the action, the loop is still up to P = 100 ms (mean age P/2 = 50 ms). That is inside the 10 ms – 1 s envelope (E14). The objection "d = 0 is faster than any near-RT RIC" is only half true.

### Q3. Does ≤ 10 ms change any plausible result? (quantified)

**Discrete observations do not change.**
- With d = 0, the handover finishes about 5–6 ms after the barrier (E5).
- With d = 10 ms, it finishes at about 16 ms.
- The next KPM sample is at ≈ (k+1)·P + 0.8 ms (E8 reschedule).
- So for every d in [0, about 90 ms], sample k+1 shows the UE on its new cell.

Any xApp whose decision depends on serving cell or UE-list membership (TS's serving-cell logic) sees an **identical discrete observation sequence**. The decision ledger is therefore invariant to d < P − 6 ms. This is my main argument.

**Continuous observations change at the second order.**
- Per control, up to 10 ms (≤ 10 % of one period) of one UE's traffic moves from the target cell to the source cell in the k+1 report.
- In 10 ms the UE moves 2–4 cm (E9).
- A channel-condition update (every 100 ms) falls inside a 10 ms window with probability ≈ 10 %, assuming a uniform phase (unverified).

**Back of the envelope (unverified estimate):**
- M8 config: 6 UEs × 10 s = 60 UE-seconds.
- 10 controls × 10 ms = 0.1 UE-s served by a different cell, which is **≈ 0.17 %**.
- The interruption itself (≈ 1.7 ms, E4) does not change length; only its position shifts.

**R3 noise is larger.** R3 with stock QP is statistical by design: a 1.6 s wall-clock window (G2, D6). Its run-to-run noise dwarfs a 0.17 % shift.

**Where delay does matter:**
- **A latency-sensitivity study.** Example: "TS gain versus loop latency under LOS/NLOS flips". The interesting range is 10 ms – 1 s, i.e. 0.1 to 10 periods, which is the cross-barrier regime with all the risks in Q4. A ≤ 10 ms "transmission delay" is the uninteresting corner of that study.
- **A shorter period.** At P = 10 ms (allowed, E10), 10 ms is a whole period.
- **Leaving NoAuto.** Under DynamicTtt, delay widens the RIC-versus-TTT race window that counsel C showed can trip `lte-enb-rrc.cc:4401-4405`.

### Q4. Risks of adding it

| Risk | d = 0 | d > 0, d < P | d ≥ P (the only regime where results can change) |
|---|---|---|---|
| **Stale precheck** | None: the precheck and the apply happen in one synchronous call | ~d / 1.6 ms association updates per IMSI can switch it to LTE on outage before apply (E6). In-handover state can appear and turn the apply into a silent no-op (E7). | Same, plus a later barrier's precheck cannot see a pending earlier control. Example: control A at k, control B for the same IMSI at k+1 passes its precheck, A applies, B becomes a silent no-op while ACKed "applied". |
| **ACK semantics** | "ACK once scheduled" equals "ACK once applied" | ACK at barrier: a promise that can break, and E2AP has no retraction after an ACK (belief, from counsel B's reading of R004 §8.2.4). So the ACK must move to apply time, sent mid-step from the sim thread. | ACK at apply crosses barriers. ACK wall latency ≈ ⌈d/P⌉ × C, i.e. 3.2 s per period at the default config, past rc's 2 s ack timer (logs only, per counsel B; rc's behaviour on a late ACK is unverified). Agents must hold E2 transactions open across steps. |
| **Determinism** | Trivial | Deterministic (E11) | Deterministic, but d = n·P ties with the k+n emitter and barrier. Whether sample k+n "sees" the control then depends on event-insertion order: an artefact, not a model. A rule is needed (d ≠ n·P, or "apply first at barrier k+n"). |
| **Ledger / replay** | `(seq, applySimTimeNs, …)` is enough | Add outcome-at-apply; replay must schedule on `applySimTimeNs` | Add `decideSeq` ≠ `applySeq`, a pending queue that survives barriers, end-of-sim handling (a control scheduled after `simTime`: was it ACKed?), and a dual-semantics test matrix (counsel C: "a second semantics to test", `counsel-…-c.md:56-58`) |
| **Gates** | One-to-one join of handover row ↔ control | Join after `applySimTimeNs` | Same-IMSI refusal case (R1) changes meaning |

**Wrong place, stated plainly.** Any wall-clock delay (tc netem on the E2 link, a sleep in the agent, gRPC throttling) does **nothing** in sim time under lock-step. The barrier simply waits longer. It only eats into T_ctl/W and the wall budget. The only correct place is a sim-time offset inside ns-3 at the barrier.

### Q5. Verdict

**Keep d = 0 permanently.** Do not build a "transmission delay". Add a loop-latency knob only when **all** of these hold:
1. **A written study.** The research question's conclusion is expected to depend on loop latency, and the sweep spans **≥ 1 period**, i.e. 0.1–1 s, the near-RT band in E14. A single value ≤ 10 ms never qualifies.
2. **A green baseline.** The rung's repeat gate is already green at d = 0, so the knob varies a proven baseline.
3. **Semantics decided up front:**
   - it is sim-time only, named `controlLoopDelay`, and models d_up + d_xApp + d_down;
   - the precheck and the ACK run at apply time;
   - pending controls survive barriers and are prechecked against both the pending set and live state;
   - the tie rule against n·P;
   - end-of-sim handling.
4. **A cheap sensitivity probe shows it matters.** First run R1 at d = 0 and at d = P (one constant `Schedule` offset, a throwaway branch). If the decision ledger and the KPIs of interest do not move beyond the noise floor, stop.

**What would change my mind:**
- the user plans to lower `indicationPeriodicity` towards 10–20 ms (E10);
- the user moves off NoAuto, where RIC-versus-auto-handover timing is the research object;
- a reviewer or advisor requires a latency-sensitivity figure for a TS/QP claim;
- evidence that a real xApp's decision at k+1 depends on fine-grained throughput deltas that a sub-period shift would flip. That would break the invariance argument in Q3.

---

## 4. Debate reply to the user

**My position.** Your instinct is right that d = 0 makes the RIC infinitely fast in sim time. The fix you name, a transmission time from sender to receiver, is the wrong quantity in the wrong regime. Keep d = 0, write down what it means, and build a multi-period loop-latency sweep only on the day a study needs one.

**Strongest arguments:**
1. **Lock-step leaves one identifiable number.** The loop is `d_up + d_xApp + d_down`, applied once in ns-3. "Transmission time" models only the downlink, which is the smallest term. The dominant term, xApp decision time (TS plus QP's Influx query), is a property of the software under test, not of the radio. Its wall value on this VM says nothing about a deployment. (Q1, E13)
2. **Below one period, d is invisible to the closed loop.** The handover finishes about 5–6 ms after apply (E4, E5). Any d below about 90 ms gives the RIC the same discrete observation at k+1, so the same decisions and the same ledger. The residue is about 0.17 % of UE-time on a different cell at the M8 config (Q3, estimate).
3. **A realistic d is the dangerous one.** d is only worth having at ≥ P, the near-RT band. That is where prechecks go stale (association updates every 1.6 ms can still trigger an outage switch under NoAuto, E6). It is also where ACKs must cross barriers and outlive rc's 2 s timer, and where a silent no-op could be ACKed as "applied" (E7). d = 0 is the only value at which "validated", "scheduled", "applied" and "ACKed" are the same instant. (Q4)
4. **Wall-clock delay is erased.** Under the barrier, netem or a sleep changes nothing in sim time. Only an ns-3 sim-time offset is a model.
5. **Prior art and plan history favour d = 0.**
   - The ns-O-RAN authors' own lock-step applies at `Seconds(0)` (E12).
   - d = 1 was proposed for wall-time overlap (E15), and that benefit vanished once the pacer (D1) began releasing non-trigger steps at once.
   - The observation side already departs much further from reality: a 0.1 s period against kpimon's 10 s request, ideal RRC, and a snapshot SINR (Q2).

**Strongest counterargument to my own position.** "Without the knob you cannot even show that latency does not matter. A reviewer will call TS gains an optimistic upper bound. A sim-time offset is one `Schedule` call that keeps bit-identity (counsel A already sketched `Schedule(applyDelaySim)`, `counsel-…-a.md:112`). So build it now while the barrier code is fresh, default 0."

**I partly concede.** A d ∈ {0, P, 2P} sensitivity check is good science if you publish TS/QP claims, and keeping the door open is cheap (checklist below). But "one `Schedule` call" holds only for d < P with the precheck and the ACK moved to apply time. That regime cannot change results (argument 2). The regime that can change results is not one call: it is a pending queue plus cross-barrier ACKs plus a tie rule. Building it before M8 is green spends complexity on the riskiest milestone.

**Questions back to you:**
1. **Which result is at stake?** Name the post-M9 research question whose conclusion would change with a delay under 10 ms. If there is none, may "transmission delay" become, in the roadmap, "a loop-latency sweep (≥ 1 period), built only for a latency study"?
2. **What does "receiver" mean?**
   - The E2 node (an E2 transport ns-3 does not model): a sim-time offset.
   - The UE actually switching cells (≈ 5–6 ms that ns-3 already models with X2, RRC and RACH): that would be double counting.
3. **Is a shorter period planned?** Do you plan to drop `indicationPeriodicity` below 0.1 s, or to leave NoAuto, in a later study? Either one turns this from cosmetic into first-order and changes my verdict.

---

## 5. What to do, what to avoid, alternatives

**Do:**
- Approve D5 as d = 0 and record its meaning in the plan: "RIC loop latency = 0 in sim time; information age at actuation = 0..P".
- Keep `applySimTimeNs` in the ledger and in `controlAck`, as already planned.
- Make the replay oracle schedule on `applySimTimeNs`, not on `seq`. With that, a future knob needs no schema change.

**Avoid:**
- Any wall-clock delay mechanism (netem, sleeps, gRPC throttling).
- Calibrating d from the 6.6 ms wall measurement.
- d = n·P values without a tie rule.
- ACKing at the barrier while applying later.
- Adding the knob before R1 is green.
- Calling it "transmission delay". The name invites a one-way, downlink-only model.

**Alternatives:**

| Option | Cost | Benefit | My take |
|---|---|---|---|
| d = 0 permanent (recommended) | None | Simplest semantics; matches the gym | Default |
| Sim-time `controlLoopDelay`, d < P, precheck and ACK at apply | Small: one `Schedule`, moving the precheck and ACK into the apply event, an outcome-at-apply ledger field | Answers "RIC infinitely fast" rhetorically | Cosmetic: it cannot change the decision ledger (Q3). Not worth a second semantics. |
| Multi-period sweep, d ∈ {0, P, …, 10P} | Medium to high: pending queue, cross-barrier ACKs, tie rule, a test matrix | The only variant that answers a real latency question | Build only under the conditions in §3 Q5 |
| Wall-clock delay (netem) | Low | None in sim time | Reject |

## 6. Work checklist (if the user accepts)

1. Mark D5 = d = 0 (permanent default) in `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/plan.md`, with the one-line model statement.
2. In the M8 ledger/replay design, assert that replay schedules on `applySimTimeNs`.
3. Add to the roadmap: "loop-latency sweep: sim-time only, ≥ 1 period, preconditions §3 Q5 of this report".
4. Optional, post-R1: the throwaway d = P probe on R1 (decision ledger and KPI diff) to settle whether the knob is ever worth building.

## 7. Success metrics

- M8–R1 repeat gates go green with a single control semantics (validated = scheduled = applied = ACKed).
- No gate or ledger field depends on wall latency.
- If the optional probe runs, the d = P ledger matches d = 0 on (imsi, target, decision step). Only applySimTime and KPIs move, within noise.

## 8. Assumptions

| # | Assumption | Confidence | What would change the answer |
|---|---|---|---|
| A1 | Future xApps (TS, QP) act on discrete state, or on statistics coarse enough that a ≤ 10 % shift in one period's bytes for one UE does not flip a decision | medium | QP/TS decisions found to be sensitive to small per-UE throughput deltas |
| A2 | `indicationPeriodicity` stays at 0.1 s | medium | A study at 10–20 ms |
| A3 | The busy window ≈ 5–6 ms (3 X2 hops + measured 1.6–1.8 ms + 1 hop), derived from code and DynamicTtt traces, not from a control-path run | medium-high | The M8 trace showing control → HandoverEnd ≫ 6 ms |
| A4 | E2AP gives no way to turn an ACK into a FAILURE after the fact | medium (counsel B's reading of R004 v08.00; not re-read here) | Spec text allowing a later failure indication |
| A5 | The outage switch stays active under NoAuto in M8 configs (`outageThreshold` stays −5 dB) | medium | The harness sets −1000; that removes E6's stale-precheck path for d > 0 but not E7's |
| A6 | The 10 ms – 1 s near-RT band from secondary sources matches the O-RAN WG1 AD | high | — |

## Unresolved questions

1. The end-to-end control apply → HandoverEnd sim time is unmeasured until M8 has a control path. Measure it in R0.
2. rc's behaviour on an ACK that arrives after its 2 s timer (relevant only to d ≥ P).
3. The phase of the 100 ms channel-condition updates relative to the barrier (relevant only to the ≈ 10 % crossing estimate).

Sources: [Polese et al., Understanding O-RAN (arXiv 2202.01032)](https://arxiv.org/pdf/2202.01032); [dApps (arXiv 2203.02370)](https://arxiv.org/pdf/2203.02370). Everything else is cited inline by repo file:line.

# D5 counsel: build the actuation delay as an extension point

I did not read the other two D5 counsel reports (`counsel-261022-1544-GH-1-d5-*`).

- Lens: architect for the extension point. I accept d = 0 now and stress-test how cheap a later δ would be.
- Model: Opus 5.5, following the user's CLAUDE.md override of the `fable` default.
- Date: 2026-10-22.
- Read-only, apart from this file. Evidence is marked ✔ where I checked it in source at the worktree's pins (ns-3 fork `ace32168`, oran-interface `438a839`). Statements I could not check are labelled.

## Position

Approve d = 0. Do not build the delay. Do build M8 so that a later δ is a code addition, not a contract change.

What is expensive to change after R3 is not the scheduling code. It is the **contracts** and the **golden artefacts** that M8–R3 will freeze:
- the ledger schema and its write order;
- the meaning of an ACK;
- where the state prechecks run;
- the agent's pending-control model;
- the replay key;
- how the gate scripts pair a request with its answer;
- the reference ledgers and digests that M9 compares against.

All of these cost nothing to get right at d = 0. Every one of them breaks, or breaks silently, when δ > 0 if M8 bakes in "receipt = apply = ack".

The scheduling branch itself (about 40 lines, plus an end-of-sim drain and one δ > 0 test run) should wait until someone actually wants δ.

## Strongest arguments

1. **The natural way to generalise the sketches is the wrong one.**
   - Counsel A's barrier says "Validate, `Schedule(applyDelaySim)` each control, write the ledger, send a `controlAck`" (`counsel-…-pacing-a.md:112`).
   - Counsel B defines `applied` as "committed for execution at `applySimTimeNs`" (`counsel-…-pacing-b.md:162`).
   - With δ > 0 both mean: validate at receipt, ACK at receipt, apply later. That is wrong because the state can change between receipt and apply:
     - The outage fallback runs every `CrtPeriod` = 1600 µs even under NoAuto (`lte-enb-rrc.cc:3318-3321`, `:4755-4790` before the NoAuto branch at `:4805-4808` ✔).
     - A handover completion flips `m_mmWaveCellSetupCompleted` and `m_lastMmWaveCell` (`:2079`, `:2116-2117` ✔).
     - A handover start clears it (`:4519` ✔).
   - So a precheck made at receipt is stale at apply.
   - E2AP has no way to take back an ACK. RIC Control ends with one terminal answer (E2AP R004 v08.00 §8.2.4, as read by counsel B; I did not re-read it).
   - The journal's §5.3 (synchronous precheck + apply + ack inside the barrier) is safe at d = 0 only because the three times coincide. Write the rule down now: **the ACK is the D4 method's return value at `applySimTimeNs`**.

2. **The worst δ > 0 failure is an abort, not a wrong number.**
   - Take two controls for the same IMSI and the same target T, received at barriers k and k+1, with δ > P.
   - A receipt-time precheck on the second control sees the UE still on its source, so it passes.
   - At apply time the first control has already moved the UE to T. The second becomes a handover to the serving cell, which hits `NS_ASSERT_MSG(m_x2InterfaceSockets.find(targetCellId) …)` at `epc-x2.cc:693-694` ✔ (counsel C's same-cell path).
   - If the state prechecks live only inside the D4 method and run at apply time, the same case becomes a deterministic `alreadyOnTarget` or `in-handover` refusal. No new precheck cause is needed.

3. **The ledger's `seq` is ambiguous, and the replay depends on it.**
   - At d = 0, "the step it was received in" and "the step it was applied in" are the same number.
   - Counsel C's replay sink writes the recorded `control` lines and then `step(k)` (`counsel-…-pacing-c.md:109`), so it re-injects at the recorded step and ns-3 re-applies its own δ.
   - If the ledger stores the apply step, the replay applies at 2δ, and every R0–R3 reference ledger has to be regenerated.
   - Renaming the field to `rxSeq` and adding `rxSimTimeNs` now costs nothing. Doing it after R3 invalidates every committed reference digest, including M9's dev-run reference (§8).

4. **"d = 1" in the journal means two different things.**
   - D5's alternative reads "realism and overlap" (journal `:217`).
   - **Realism lag** is a fixed sim-time δ. It is repeatable, and under the D1 pacer it costs no wall time.
   - **Pacing overlap** is counsel C's hybrid: "apply window-k controls at barrier k+1", for max(C, W) instead of C + W (`counsel-…-pacing-c.md:52-57`). It lets a control *arrive* at barrier k or k+1 depending on wall speed. The anchor must then be the step the decision was based on, not `rxSeq`.
   - The agent's `afterSeq` cannot recover that basis step once ns-3 runs ahead, because the RIC does not tag which indication it used.
   - Overlap is therefore a redesign of the anchor and of the freeze semantics in D2, not a δ parameter. Split it out of D5 so nobody later thinks "set d = 1" buys it.

5. **Most of the seam is needed at d = 0 anyway, so it is not YAGNI.**
   - **Several pending controls per agent.** R1 sends two controls through one agent in one step, so the agent's pending map must hold N outstanding controls keyed by `ctlId`.
   - **Fail everything on bye or EOF.** A control that reaches the agent after the final barrier never gets a `controlAck`, because the emitter only sends `bye` at Destroy (`e2-ipc-emitter.cc:151-157` ✔).
   - **Route acks by `viaNodeId` through a registry.** The barrier sorts controls across all sockets before applying them, so "the socket I just read from" is not in hand.
   - **Prechecks inside D4.** This is already the D4 design.

## Q1. What changes when δ > 0

The anchor in this table is apply = `rxSimTimeNs` + δ, where `rxSimTimeNs` is the barrier's sim time. The barrier time is the last emitter's emission time. The emitters reschedule themselves with `Schedule(Seconds(m_e2Periodicity))`: `lte-enb-net-device.cc:1436-1438`, `mmwave-enb-net-device.cc:1510-1512` ✔.

| Area | Sub-period δ (0 < δ < P) | Crossing barriers (δ ≥ P) | Rule that keeps it correct |
|---|---|---|---|
| **Prechecks** | State can change in δ: about δ / 1.6 ms outage evaluations, a handover can complete, a handover started by another control can start (refs above). A receipt-time check is stale. | The same, plus another control for the same IMSI can be in flight. | State prechecks only inside D4, at apply. The barrier and the agent check only static validity (decode, RAN function 3, style/action 3/1, IPC up). |
| **Two controls for one IMSI** | Only possible within one barrier: both apply at the same instant, in canonical order. The second is refused `in-handover` (`:4519` sets the flag ✔). R1's oracle holds. | A from k and B from k+1 both pending. At B's apply: `in-handover` if A's handover has not completed, `alreadyOnTarget` if it completed to the same target, otherwise a second valid handover. All deterministic. | No new cause and no "supersede" logic. The R1 oracle holds only for a fixed δ. A random per-control δ can reorder the pair. |
| **ACK timing and E2AP** | The ACK is sent from the apply event, during the compute of step k→k+1. Wall latency is under C. | The ACK arrives about ⌈δ/P⌉ × (C + gate) wall seconds later. At the default config that is more than 3.2 s, past rc's 2 s window (`rcControl.go:333-343` per counsel B), so rc never decodes it; at 2 gNBs it does. rc's logs therefore become config-dependent, which G9 already says not to gate on. | ACK and FAILURE are decided when D4 runs; never ACK at receipt. Modelling reason: δ *is* the transport delay to the node, so in model time the node has not received the request until `applySimTimeNs`. The agent must not have a wall-clock ack timer that turns into FAILURE, or it would fail controls that ns-3 later applies. |
| **Ledger** | `rxSeq` ≠ apply step only in sim time; written at apply. | Lines are written in apply order, not receipt order. `sourceCell` is the serving cell at apply. | Columns `rxSeq`, `rxSimTimeNs`, `applySimTimeNs`. Write order (`applySimTimeNs`, `rxSeq`, imsi, nodeId, ctlId). `ctlId` and the RIC ids go in `diag`. |
| **Replay** | Replay injects at `rxSeq` and ns-3 recomputes the apply time. | Same. If the replay used the apply step, the delay would be applied twice. | Replay is keyed on `rxSeq`. There is no path that injects an apply time. Record the δ model in the ledger header or the run manifest so the replay runs with the same δ. |
| **Canonical order** | Within a barrier, unchanged. Same-timestamp events run FIFO by uid (`default-simulator-impl.cc:223-237` ✔), and they are inserted in sorted order. | Controls received at different barriers can share an apply time (random δ). | The order key leads with `applySimTimeNs`, then `rxSeq`, then the settled (imsi, nodeId, ctlId). At d = 0 it reduces to the settled key. |
| **End-of-sim drain** | A control received at the last barrier with apply ≥ simTime never runs. `Simulator::Stop` discards it, so it gets no terminal answer and no ledger line. | Up to ⌈δ/P⌉ barriers of controls are left pending. | Before the sockets close: write a ledger line `refused / simEnded` and send a FAILURE. **Ordering trap:** destroy events run FIFO (`default-simulator-impl.cc:90-102, 285-294` ✔). The emitters register theirs at t = 0 (`e2-ipc-emitter.cc:99`, scheduled from `lte-enb-net-device.cc:947` and `mmwave-enb-net-device.cc:491` ✔). A drain hook added later would therefore run after the sockets are closed. The pacer's hook must be registered before `Run`. |
| **Null-control gate** | A fixed δ cannot affect it, because the δ path never runs without controls. | Same. | A δ drawn from an ns-3 RNG with the default `Stream = -1` uses up an automatic stream index when it is constructed (`random-variable-stream.cc:60-68, 113-126`; `rng-seed-manager.cc:107-113` ✔). That shifts every random variable created after it, so the zero-control digest changes and so does every d = 0 reference. Use an explicit stream (`CreateObjectWithAttributes(…"Stream", IntegerValue(n))`, the deterministic range at `:127-134` ✔) or a stateless hash. I have not verified that `ConstructSelf` skips the default setter when an initial value is supplied; check it with a null-control run. |
| **`Schedule` semantics** | `Simulator::Schedule` takes a relative delay and asserts it is not negative (`default-simulator-impl.cc:229` ✔). | Same. | Compute `X − Now()` and assert it is ≥ 0. Prior art got this wrong: ns-O-RAN's `ScheduleControlMessages` calls `Schedule(MilliSeconds(timestamp))` with an absolute CSV timestamp (`lte-enb-net-device.cc:238-242` ✔), on a read that first happens at P + 5 ms (`:1032-1033` ✔). It also adds an ad-hoc "+0.001" for ordering (`:255-258` ✔). |

**δ = P exactly** is deterministic. At t_{k+1} the order is: every sample k+1 is emitted, then the apply event (inserted at barrier k), then barrier k+1 (inserted with `ScheduleNow` during the last emit). This depends on uid tie-breaking, so assert it in the δ > 0 smoke run; do not assume it.

## Q2. Build now, or defer

| # | Item | Tier | Cost now | Why |
|---|---|---|---|---|
| 1 | Ledger: rename `seq` → **`rxSeq`**; add **`rxSimTimeNs`**; define `applySimTimeNs` as "the sim time D4 ran" and `sourceCell` as "serving cell at apply"; write at apply in (`applySimTimeNs`, `rxSeq`, settled key) order | **Now, must** | One column and a rename | Changing it later invalidates every reference ledger and digest and the replay parser |
| 2 | ACK definition in the acceptance text and in code: the terminal answer is D4's outcome at `applySimTimeNs`; never at receipt or queueing; `controlAck.seq` = `rxSeq` | **Now, must** | Wording | Prevents the A/B generalisation trap (argument 1) |
| 3 | State prechecks only inside the D4 method; static validation only at receipt | **Now, must** | Already planned (D4) | Turns the X2 abort into a refusal (argument 2) |
| 4 | Agent: N pending keyed by `ctlId`; **no wall-clock ack timeout**; FAILURE for every pending control on IPC `bye` or EOF | **Now, must** | Needed at d = 0 anyway | A wall timer would emit FAILURE before ns-3 applies when δ > 0, so the RIC and ns-3 would disagree |
| 5 | `controlAck` routed by `viaNodeId` through the pacer's emitter registry | **Now, must** | Natural after the global sort | Sending from an apply event has no socket in scope |
| 6 | Replay sink keyed on `rxSeq`; ns-3 computes the apply time itself; one ingestion path | **Now, must** | The same as planned | Avoids applying δ twice and keeps a second code path out |
| 7 | Gate scripts pair each RICcontrolRequest with its terminal answer by (requestorId, instanceId) *within* a run, never by "same step". The ledger check includes `applySimTimeNs − rxSimTimeNs == δ` (= 0 today) and `rxSeq == afterSeq` | **Now, must** | A few lines of gate code | A step-grouped wire gate silently encodes d = 0. The check also catches any accidental delay or pacing leak today |
| 8 | One `ApplyDue()` over a pending list; at d = 0 the barrier calls it inline after sorting. The δ constant lives in one place; X > Now is `NS_ABORT("applyDelay>0 not implemented")` | Now, cheap | About the same code as an inline loop | Makes δ a later addition with no refactor |
| 9 | Pacer destroy hook registered before `Run`, asserting the pending list is empty | Now, cheap | One line | It is the hook point for the drain, ahead of the emitters' `bye` |
| 10 | Ledger header line recording the δ model (`fixed`, 0) | Now, cheap | One line | Adding a header later also changes the ledger bytes |
| 11 | δ attribute or CLI flag; the scheduled branch for X > Now; the end-of-sim drain; a RIC-less δ = P smoke run on the replay or Fallback-1 harness | Defer | About 40 lines plus one offline run (2 gNB, 10 s ≈ 64 s wall) | Untested δ code would rot. Do it when δ is actually wanted |
| 12 | Seeded or trace-driven δ; per-UE δ | Defer | — | Document the explicit-stream rule now; build later |
| 13 | Pacing overlap (anchor on a pacer-tagged basis step) | Defer, **separate decision** | — | It is a redesign, not δ (argument 4) |
| 14 | Free-run δ (apply = t(afterSeq) + δ, clamped at Now with a `late` flag) | Defer | — | Only useful in demo mode |
| 15 | Connection-epoch guard on acks (using `E2IpcTcpClient::GetConnectCount`, `e2-ipc-tcp-client.h:69` ✔) | Defer | — | Matters only when an ack crosses a `Service()` reconnect, which is impossible at d = 0 (see below) |
| 16 | Two-phase ledger (received / applied lines), a pending count in the pacer's `ready`, an uplink delay | YAGNI | — | One downlink δ is a complete model of the loop in lock-step (see Q3) |

Why item 15 cannot happen at d = 0: the client reconnects only inside `Service()`, which runs from `EmitSample` (`e2-ipc-emitter.cc:108` ✔). An ack sent inside the same barrier cannot cross a reconnect. With δ > 0 an agent restart resets `ctlId` to 0, so an old ack could close the new agent's ctlId 0. That has to be fixed when δ lands.

## Q3. Delay models and bit-repeatability

| Model | Repeatable? | Condition |
|---|---|---|
| Fixed δ in sim ns (includes d·P) | Yes | None. It costs no wall time under the D1 pacer |
| Seeded random δ per control | Yes, conditionally | Two conditions. First, the draw is a pure function of (RngRun, control identity) and is made **after** the canonical sort: either a stateless hash of (RngRun, rxSeq, imsi, viaNodeId, targetCell), or an ns-3 RNG with an explicit stream. Second, it is not drawn in wall arrival order and does not use an automatic stream |
| Trace-driven δ (an empirical distribution from a file, sampled as above) | Yes | Same conditions |
| State-dependent δ (load, number of pending controls) | Yes | The sim state is deterministic |
| **Wall-measured latency** (agent `rxMonoMs`, rc→agent ms, or any wall quantity converted to sim time) | **No** | This is the merge-time stamping problem the plan already rejected (`default-simulator-impl.cc:177` ✔). The values are also VM noise, not E2 latency: rc→agent p50 is 6.6 ms on this VM (journal §6) |
| A δ keyed on `ctlId` | No, in one case | `ctlId` follows arrival order at an agent, and that order is wall-dependent when rc's goroutines race (see the side finding) |

**Modelling note.** In lock-step the RIC is infinitely fast in sim time: sample k is "received" and decided at t_k. One δ applied at the node is therefore a complete model of the whole loop (E2 uplink + xApp + E2 downlink + node processing), because nothing in sim time observes the intermediate hops. Size δ as the *loop* latency, not just "sender to receiver" transmission. The source should be a specification or literature value. The 10 ms–1 s near-RT band is commonly quoted from O-RAN WG1/WG3; I did not re-read it here (only a patent restates it, [US 12127008](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12127008)). It should not be a testbed measurement.

**The exact invariant the repeat gate must check.** For the 3 live runs and the replay:
1. The ledger is byte-identical outside `diag`. It is written at apply time in (`applySimTimeNs`, `rxSeq`, imsi, nodeId, ctlId) order, with lines (`rxSeq`, `rxSimTimeNs`, `applySimTimeNs`, viaNodeId, imsi, sourceCell, targetCell, outcome, cause).
2. Every line satisfies `applySimTimeNs − rxSimTimeNs = δ(model, RngRun, key)`, with δ recomputed by the gate script. This is **0 today**.
3. Every line satisfies `rxSeq = afterSeq`.
4. `rxSimTimeNs` equals the barrier time of `rxSeq` taken from the IPC traces.
5. #`control` lines read by ns-3 = #ledger lines = #terminal E2AP answers on the wire.
6. The null-control digest at the configured δ model equals free-run's.

In one sentence: the applied-control sequence is a pure function of (args, RngRun, the controls received per `rxSeq`). The 3 live runs test that it is a function. The replay tests that it is pure.

## Q4. What not preparing costs if δ arrives after R3

**Unprepared** (barrier does receive → validate → apply → ack inline, the ledger has an ambiguous `seq`, the agent assumes the ack arrives within the step):
1. Refactor the ns-3 barrier: split receive from apply, add a pending list, a scheduled apply, acks sent from apply, a shutdown drain, and fix the destroy-hook order.
2. Audit and move every receipt-time state check into D4. Re-test every refusal cause: unknownImsi, alreadyOnTarget, unknownTarget, in-handover, ueOnLteFallback.
3. Change the ledger schema. Then rewrite the replay sink, the ledger comparator and the wire-per-step grouping. Regenerate the reference ledgers and digests for R0, R1, R2, the R3 D0 replay and M9's dev reference, and re-run every rung's repeat gate (3 + 1 runs each).
4. Rework the agent's control state machine (N pending, no wall timer, fail all on bye), rebuild the image and redeploy.
5. Rewrite the acceptance text: the ACK definition, request/answer pairing, the end-of-sim terminal-answer count, the R1 oracle.
6. Re-prove the null-control gate and the RngRun non-vacuity check for the δ model.

**Prepared:**
- Items 1–6 shrink to: item 11 (about 40 lines plus one RIC-less run), plus new reference ledgers *only for δ > 0 runs*.
- **The d = 0 references stay valid**, because the d = 0 output is byte-unchanged. Make that a gate when δ lands: "all d = 0 digests unchanged".

## Q5. Verdict

Approve D5 at d = 0, on these conditions:
- M8 builds items 1–7 of Q2 (contracts) and preferably 8–10 (seams).
- Items 11–16 wait.
- D5's "d = 1 (realism **and overlap**)" alternative is split in two. Realism is a δ parameter. Overlap is a separate decision that changes the anchor and D2.

**Strongest counterargument.** This is still speculative design. If δ never comes, `rxSimTimeNs`, the `ApplyDue` indirection and the extra gate checks are carried forever. If δ does come, it may be per-UE, distribution-driven or overlap-motivated, and invalidate the seam anyway. The honest YAGNI answer would be to ship the gyms' d = 0 inline loop and pay later.

**My reply.**
- Items 2–7 are needed or free at d = 0. They are correctness for R1 and end-of-run, not speculation.
- Item 1 is one column and a rename whose later cost is golden-artefact churn.
- The genuinely speculative code (item 11 onward) is deferred.
- The counterargument does land on overlap: no seam I propose makes overlap cheap. That is why I ask for it to be split out.

## Side finding (applies at d = 0; not reopening the sort)

The settled key is (imsi, nodeId, ctlId), and `ctlId` follows arrival order at the agent. rc sends each request from its own goroutine (`rcControl.go:141`, cited by all three pacing counsels). So two controls for **the same IMSI through the same agent in one step**, with **different targets**, are ordered by a wall race. Which target is applied, and which one is refused `in-handover`, is then nondeterministic.

There are two fixes:
- route R1's same-IMSI pair through two different agents (nodeId then breaks the tie); or
- insert `targetCellId` before `ctlId` in the tie-break, so content-identical controls become order-irrelevant.

## Questions back to you

1. **What should δ model?** One-way E2 downlink transmission, or the full loop (indication uplink + xApp decision + control downlink + node processing)? In lock-step only one δ exists, so "sender to receiver" understates it. And where does its value come from: a specification or literature number (fixed), or a distribution (seeded)? Never from this testbed's wall measurements.
2. **Do you want pacing overlap ("d = 1" to hide W behind C) ever?** If yes, it needs its own decision now, because the anchor moves from `rxSeq` to a pacer-tagged basis step. If no, strike "and overlap" from D5's alternative.
3. **Before or after M9?** If δ is likely before M9, promote item 11 (scheduled branch, drain, one RIC-less δ = P run) into M8. It costs about 1 offline run, and then δ really is a parameter. Otherwise keep it deferred.

## Assumptions

| Assumption | Confidence | What would change the answer |
|---|---|---|
| The D1 pacer and D2(a) freeze are approved, so `rxSeq == afterSeq` in lock-step | Medium-high | If D2(c) continue-and-flag were used in gate runs, `rxSeq` would become wall-dependent and the anchor argument would extend to late controls |
| The ledger is the replay input, as in counsel C's replay sink | High | A replay that reads the IPC trace instead would move item 6's key there, with the same logic |
| E2AP RIC Control has exactly one terminal answer and no retraction | Medium-high (counsel B's reading; not re-read) | A spec clause that allows a later failure would weaken argument 1's E2AP half; the state-staleness half stands |
| `CreateObjectWithAttributes` with an explicit `Stream` does not use up an automatic stream index | Medium (not verified in `ObjectBase::ConstructSelf`) | If it does, use the stateless hash for seeded δ |
| Handover duration under NoAuto is tens of ms of sim time, below P | Low (not measured) | It only changes which refusal the in-flight pair gets, not the design |

## Unresolved questions

1. The E2AP cause value for a `simEnded` FAILURE (`misc: unspecified` or a `ricRequest` value). Not verified.
2. Whether the M8 trace gate needs the inbound `control` lines in the IPC trace (today inbound bytes are drained and ignored, `e2-ipc-tcp-client.h:27` ✔) or reads them from the ledger alone.
3. Whether the δ = P uid ordering at t_{k+1} (emits, then apply, then barrier) holds when the barrier is scheduled by `ScheduleNow` from inside `EmitSample`. I derived it by reasoning; confirm it in the first δ > 0 run.

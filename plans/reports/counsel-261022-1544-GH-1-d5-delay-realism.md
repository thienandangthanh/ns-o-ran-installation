# D5 counsel: actuation delay of RIC controls (realism lens)

I did not read the other two D5 counsel reports (`plans/reports/counsel-261022-1544-GH-1-d5-*`). My inputs are listed in §11.

Date: 2026-10-22 (Asia/Seoul). Runtime: Claude Code, Opus 5.5, as the caller routed it, not `fable`.

Read-only, apart from this file and my agent memory. One new offline analysis of committed ns-3 traces (§5); no VM, no commits.

---

## 0. Position

**Keep d = 0 as the value for M8, R0–R2 and the R3 acceptance gate. Do not defer the mechanism, though, and do not model the delay as "transmission time".**

1. **Build the actuation-delay seam in M8, now.**
   - The seam is:
     - one `ActuationDelay` attribute, default 0 s;
     - one `ApplyControl` function, which runs the precheck, the handover, the ledger line and the `controlAck` at apply time;
     - two ledger fields.
   - At δ = 0 this is the journal's plan byte for byte.
   - Adding δ after M9 instead changes the ACK/precheck contract, the replay rule and every reference digest.
2. **Model δ as the whole RIC loop that lock-step collapses to zero sim time:** indication → kpimon → Influx → QP → TS → rc → E2 node. The wire is the smallest term on this testbed.
3. **Add one R3 run at δ = 150 ms.** It is a functional run, not a gate on numbers. With d = 0 plus ns-3's 0.7 ms handover, one real closed-loop path can never be reached: TS re-issuing a control while its view of the UE is stale.

**Concession the evidence forces on me.** In this scenario, d = 0 does not materially bias which cell a TS-style decision picks. My offline analysis of the M8-config and default-config SINR traces shows that δ ≤ 100 ms costs at most about 2 % of the decision's value (§5). So I am not asking you to change the default before R3. I am asking you not to freeze a contract that makes δ expensive later, and not to publish any closed-loop number without a δ sweep.

## 1. Reframed problem

The real decision is not 0 versus some number. It is three decisions:
- **(a) Where the delay lives in the control contract.** This covers when the precheck runs, when the ACK is sent, what the ledger keys on, and how a replay injects. This gets frozen in M8.
- **(b) Which value each rung runs at.**
- **(c) What "realistic" means**: wire time, or loop time.

| | |
|---|---|
| Goals | Deterministic gates stay intact. Closed-loop results stay defensible to a reviewer. Retrofitting stays cheap. |
| Non-goals | Changing pacing (settled). Stochastic delay now. Modelling E2 congestion. |

## 2. Strongest arguments

**A1. d = 0 is outside the regime the stack claims to emulate.**
- **The spec bound.** O-RAN.WG3.TS.E2GAP-R004-v08.00 §5.1.1: "E2 interface shall support latency requirements for near-real-time optimization, i.e. from 10 milliseconds up to 1 second as specified in O-RAN WG1.TS.OAD".
- **Where d = 0 lands.** The barrier runs at the last emitter's time, about k·P + 0.8 ms (counsel A §Q3, from the M4 traces). The control applies in that same event. Actuation therefore comes 0 ms after the last report and about 1 ms after the end of the measurement window. That is the < 10 ms real-time class.
- **Who owns that class.** O-RAN leaves it to dApps; D'Oro et al. list near-RT as 10–1000 ms and real-time as < 10 ms, and name handover as a near-RT use case (IEEE ComMag 2022, DOI 10.1109/MCOM.002.2200079).
- **The ns-O-RAN authors name the gap themselves.** "While the real-world near-RT RIC is expected to work with control loops between 10 ms and 1 s, ns-3 … can execute faster or slower than the wall clock time, thus generating a possible time gap" (Lacava et al., WNS3 2023 §3, DOI 10.1145/3592149.3592161). They fix timestamps only.
- **Consequence.** A closed-loop number at d = 0 is a number for a RIC that O-RAN does not define.

**A2. The seam is nearly free in M8 and a contract change later.**
- **What the spec says.** E2GAP §5.3.2.4, step 4(i): the E2 node sends RIC CONTROL ACKNOWLEDGE "if the requested control service is successfully executed".
- **What that means for δ > 0.** Execution happens at t_k + δ, so the precheck, apply, ledger line and ACK all belong at apply time.
- **The tempting design has a time-of-check/time-of-use bug.** Validating at the barrier and applying at t_k + δ goes wrong because NoAuto keeps the outage fallback (D3), which can move the UE in between.
- **Cost if deferred.** Suppose M8 freezes "validate and ack at the barrier" and a ledger without `decisionSeq`/`delayNs`. Then a later δ changes:
  - ns-3's control path;
  - the controlAck timing;
  - the replay sink, which must inject at the decision step;
  - every reference digest, including the M9 dev-run reference.
- **Cost if built now.** If M8 builds one `ApplyControl` and calls it synchronously when δ = 0, the later change is a config value.

**A3. d = 0 hides a real closed-loop failure mode, structurally.**
- **TS keeps no record of controls in flight.**
  - `prediction_callback` decides from the prediction message alone and assumes "the first cell in the prediction message is the serving cell".
  - It sends a control whenever a neighbour's predicted DL beats serving × (1 + threshold).
  - Source: ric-app-ts @19e169b `src/ts_xapp/ts_xapp.cpp:673-731`, `:695`, `:723-729`.
- **What happens in a deployment.** δ plus handover execution (45.5/49.5 ms min/typical for legacy LTE, 3GPP TR 36.881 §5.2.2, read via a mirror) often reaches one 100 ms KPM period. A trigger at k+1 then still sees the source cell, re-issues the handover, and gets a FAILURE.
- **What happens here.** At d = 0, ns-3's handover completes in 0.57–0.77 ms from start row to end row: 17 handovers in `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m4/20261021T165230Z/runs/regress/UeHandover{Start,End}Stats.txt`. With `UseIdealRrc=true` (`scratch/scenario-zero.cc:350`), ideal RRC takes 0.5 ms per message (`src/mmwave/model/mmwave-rrc-protocol-ideal.cc:60`) and X2 takes 1 ms (`src/mmwave/helper/mmwave-point-to-point-epc-helper.cc:222-226`). Report k+1 therefore always shows the new cell.
- **Why it matters for R3.** R3 is the first rung whose loop sees its own actions. At d = 0 it cannot reach this path.

**A4. Realism and wall time pull the same way once δ ≥ P.**
- **δ is the lookahead.** A control decided at k is needed in sim time only at t_k + δ. With δ ≥ P the pacer could release step k at once and collect the RIC's answer while ns-3 computes step k+1.
- **What that saves.** A trigger step then costs max(C, L + W) of wall time instead of C + L + W. This is counsel C's d = 1 hybrid, stated as conservative-PDES lookahead (research §4a–b: HLA "time stamp ≥ the federate's current time + L").
- **d = 0 is zero lookahead,** which Fujimoto names as the case that makes repeatability and concurrency harder.
- This overlap is an optional later pacer optimisation and is not in my v1 proposal. Realism makes it legal; d = 0 forbids it forever.

**A5. "Transmission time" is the smallest term.**
- **What this testbed measured** (journal §1, §6):
  - the subscription is answered in under 1 ms;
  - kpimon → Influx write p50 10 ms, p99 30 ms;
  - rc gRPC → agent p50 6.6 ms (5.6–9.9).
- **Not measured yet:** QP query plus VAR inference.
- **The stock TS use case** runs AD every 0.5 s over a 1.6 s window (counsel A §Q4, `ad main.py:44`).
- **The transport itself:**
  - at the edge, about 1 ms one way (assumption);
  - a cloud RIC is "> 15 ms latency" (EdgeRIC, NSDI 2024).
- Modelling only the wire gives δ ≈ 2 ms, which changes nothing measurable and makes no defensible claim.

## 3. Q1: latency components of a real near-RT loop, and what lock-step does to each

| Component | Typical value | Source | Here, under lock-step |
|---|---|---|---|
| KPM report period | 10 ms–1 s or more. TS paper uses 100 ms; kpimon asks for 10 000 ms | E2GAP §5.1.1; Lacava TMC 2024 §5.1 (DOI 10.1109/TMC.2023.3266642); contract Q2 | **Modelled.** 100 ms (option A) |
| Aggregation age | mean P/2 = 50 ms at report time | arithmetic | **Modelled.** Report at k·P + 0.5 ms (LTE) and + 0.8 ms (gNB) |
| E2 indication transport (SCTP) | edge ≈ 0.5–5 ms (assumption: metro fibre plus switching); cloud: EdgeRIC's twin injects 15 and 30 ms of total loop | EdgeRIC §5 and Table 2 (arXiv 2304.11199) | 0 |
| E2T decode, RMR to xApp | < 1 ms (subscription path) | journal §1 | 0 |
| kpimon decode and Influx write | p50 10 ms, p99 30 ms (wall, this VM) | journal §1 | 0 |
| Trigger cadence | AD every 0.5 s on wall clock, so a uniform 0–500 ms wait | counsel A §Q4 | 0 (harness trigger) |
| QP: Influx query and VAR predict | **unmeasured**; assumed 10–100 ms | P-B3 open | 0 |
| TS decision | sub-ms, C++ comparison (inferred from `ts_xapp.cpp:697-731`) | code | 0 |
| ML xApp inference (reference point) | 1–25 µs; end-to-end service < 4 ms (OAI + FlexRIC) | arXiv 2607.01583 (ICCCN 2026, abstract only) | n/a |
| rc gRPC → RMR → E2T → E2 node | p50 6.6 ms, max 9.9 ms (wall, includes grpcurl start) | journal §6 | 0 |
| E2 node decode and RRC trigger | ≈ 1 ms (assumption) | — | 0 (decode happens in the agent) |
| Handover execution | LTE legacy 45.5/49.5 ms min/typical | TR 36.881 §5.2.2 (mirror) | **Modelled, optimistic.** 0.57–0.77 ms; X2 1 ms, ideal RRC 0.5 ms, S1-AP 15 ms (`mmwave-point-to-point-epc-helper.cc:207-211`) |
| Whole loop | **10 ms – 1 s** | E2GAP §5.1.1; Polese et al. COMST 2023 (DOI 10.1109/COMST.2023.3239220); ColO-RAN (DOI 10.1109/TMC.2022.3188013) | ≈ 1 ms |

**Budget sum.**
- Edge RIC, event-triggered TS + QP: 1 + 1 + (10–30) + (10–100) + 1 + 7 + 1 ≈ **30–150 ms**, which is my working estimate.
- Add 0–500 ms if AD sets the cadence.
- Add about 15–30 ms for a cloud RIC.

**Published precedent ran at near-zero, uncontrolled δ** (inference). In ns-O-RAN's online, free-run mode, a control with wall latency L lands L/s sim seconds later, where s is wall seconds per sim second. At this repo's s ≈ 32, 100 ms of wall time becomes 3 ms of sim time. The TS paper reports about 50 % throughput gains over SON1 (3 dB, fixed 110 ms TTT) and SON2 (dynamic TTT). I found no actuation delay stated in it (searched arXiv 2209.14171 for latency/delay). That is a d ≈ 0 xApp compared against baselines that are made to wait.

## 4. Q2: deterministic modelling options

| Option | Determinism | Realism | Verdict |
|---|---|---|---|
| **Fixed δ in sim time,** `Simulator::Schedule(δ)` at the barrier, in sorted order | Holds. Fixed offset, and equal timestamps run in uid order (`src/core/model/scheduler.h:273-285`), so the canonical sort survives | First-order (the mean of the budget) | **Accept, v1** |
| Whole-period lookahead d = 1 | Holds | Equals δ = P, plausible. But it ties the model to P (change `indicationPeriodicity` and the delay changes) and conflates a wall-clock optimisation with a model | **Accept only as δ = P** of the fixed-δ attribute. The overlap is a separate later pacer feature |
| Stochastic δ from a seeded ns-3 RNG | Holds only with (i) an explicit `Stream ≥ 0` given at construction and (ii) draws in canonical-sort order. **Trap:** a `RandomVariableStream` left at the default `Stream = -1` takes the next automatic stream index in `SetStream` during construction (`src/core/model/random-variable-stream.cc:60-67, 113-136`). That shifts every stream created after it, so the free-run digest changes and both null-control equivalence and the M4–M7 references break. It can also reorder two controls for the same UE | Second-order (jitter) | **Defer.** Reserve the attribute name only |
| Modelled E2 link (a P2P node inside ns-3) | Holds | Nothing: no E2 traffic exists inside ns-3, because the control arrives over IPC. The link would carry a synthetic packet only to produce a fixed delay | **Reject** |
| **Live mapping of measured wall latency into sim time** | Fails | False | **Reject.** Reasons below |

**Why live mapping is rejected.**
1. **Not repeatable.** Fujimoto's condition is the same timestamp for each external input in every run (research §4b). Here the latency varies from 5.6 to 9.9 ms per call, so bit-identity is gone.
2. **Not representative.**
   - The RIC shares the VM with a CPU-bound ns-3.
   - Messages go over the pod network, not an E2 transport.
   - The number includes grpcurl process start.
3. **Incomplete.** It covers only the rc → agent hop.
4. **It brings back the coupling lock-step was built to remove.**

**What I accept instead: offline calibration.**
- Measure the component latencies once per rung; the plan already measures L for T_ctl.
- Take medians, add a stated transport assumption, round, and freeze the result in the run manifest.
- EdgeRIC's twin does the same: "appropriate delays are artificially induced", fixed at 15 and 30 ms.

## 5. Q3: does d = 0 bias R2/R3?

There are three separate effects.
- **(a) The decision at a trigger.** δ cannot change it: TS decides from data up to t_k either way.
- **(b) The decision's outcome.** The channel changes between t_k and t_k + δ.
- **(c) Later decisions.** These depend on whether a control is still in flight.

### (b): new offline evidence (no VM)

**Method.**
- **Input.** `MmWaveSinrTime.txt` is `LteEnbRrc::NotifyMmWaveSinr`: the LTE coordinator's SINR per (IMSI, mmWave cell), sampled every 1.6 ms CRT (`src/lte/model/lte-enb-rrc.cc:3354-3358`; connector `mmwave-bearer-stats-connector.cc:388-389`).
- **Decision.** At each t_k = k·0.1 s, pick c* = argmax of the mean dB SINR over (t_k − P, t_k].
- **Check.** For each δ, compare c* with the best cell over [t_k + δ, t_k + δ + P).
- **Baseline.** "Random" is the expected loss of a uniformly random cell choice.
- **Script.** Reproduced in the appendix.

| δ | 2 gNB (M8 config): hit rate | loss, dB | default (4 gNB, 12 UE): hit rate | loss, dB |
|---|---|---|---|---|
| 0 | 0.938 | 0.21 | 0.885 | 0.48 |
| 10 ms | 0.934 | 0.23 | 0.876 | 0.57 |
| 50 ms | 0.928 | 0.22 | 0.864 | 0.60 |
| 100 ms | 0.922 | 0.34 | 0.848 | 0.76 |
| 200 ms | 0.902 | 0.43 | 0.828 | 0.91 |
| 500 ms | 0.854 | 0.77 | 0.782 | 1.33 |
| 1 s | 0.795 | 1.35 | 0.730 | 1.92 |
| random choice | — | 6.68 | — | 14.73 |

**Traces used.**
- 2 gNB: `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/ns3-timing-two-gnb/20261022T025217Z/timing/two/r1/MmWaveSinrTime.txt`. 528 decisions, 6 UEs, 10 s.
- Default: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m7/20261021T233129Z/ns3run/MmWaveSinrTime.txt`. 5 256 decisions, 12 UEs, 45 s.

**Reading.**
- **Share of the attainable gain kept** (1 − loss / random loss):

  | δ | 2 gNB | default |
  |---|---|---|
  | 0 | 96.9 % | 96.7 % |
  | 50 ms | 96.7 % | 95.9 % |
  | 100 ms | 94.9 % | 94.8 % |
  | 500 ms | 88.5 % | 91.0 % |

- **Why the decay is slow:**
  - UEs walk at 2–4 m/s (`scratch/scenario-zero.cc:487-488`), so a UE moves about 0.3 m per period.
  - LOS is re-drawn independently per link every 100 ms (`src/propagation/model/channel-condition-model.cc:379-396, 452`; `scenario-zero.cc:360-361`), but a re-draw rarely flips the ranking. There were 50 jumps over 10 dB in 10 s over 12 links. They land in the first 0–10 ms of a period (98 %, 2 gNB) or the first 0–40 ms (default).
- **Verdict on (b).** No material bias up to 100 ms. Delay only starts to cost at AD-like cadences.

**Caveats.**
- This is a proxy: TS ranks QP-predicted DL throughput, which also follows load.
- One seed, from free-run DynamicTtt runs.

### (c): a structural bias, not a statistical one

- **The in-flight window** lasts δ + T_HO:
  - at d = 0 it is about 0.7 ms;
  - at δ = 150 ms it is longer than one period.
- **At δ = 150 ms with triggers on consecutive steps:**
  - TS re-issues a handover for the same UE;
  - at apply time the precheck refuses it (`alreadyOnTarget`, or `inHandover`);
  - the agent sends a RICcontrolFailure.
- **Why it matters.** The run stays deterministic and exercises the refusal path inside a real closed loop. d = 0 can never produce this.

### R2 and R3

- **R2** (stub QP): δ has no effect on the gate.
- **R3** (stock QP): the dominant distortion is G2, on the observation side, and it is far larger than any δ.
  - QP's 1.6 s wall-clock window covers about 2.5 steps (0.25 s of sim time) at 2 gNBs and less than 1 step at the default config.
  - Fix G1/G2 first.

**Answer to Q3.**
- Do not change the value before R3.
- Do build the seam in M8, and add one R3 run at δ = 150 ms.
- Before any comparative or published closed-loop claim, sweep δ. This matters most against TTT baselines, as in the TS paper.

## 6. Q4: concrete proposal

**Parameters**

| Name | Where | Type / units | Default | Rules |
|---|---|---|---|---|
| `ActuationDelay` | Attribute on the M8 control-path / pacer object in oran-interface (match the name M8 picks, e.g. `ns3::E2ControlPacer`). The delay is a property of the RIC loop, not of the RRC | ns-3 `TimeValue` | `0s` | ≥ 0. Applies in lock-step and in free-run (added to the service point). Log a warning for 0 < δ < 10 ms or δ > 1 s (outside near-RT) |
| `--e2ActuationDelayMs` | scenario-zero `GlobalValue` → `Config::SetDefault` | double, ms | 0 | Written into the run manifest |
| `StopTime` | same object, set from `simTime` by scenario-zero | `TimeValue` | — | Needed for the end-of-run refusal below. ns-3 has no public getter for `Simulator::Stop`'s time |
| `actuationDelayNs` | IPC `hello` (ns-3 → agents and pacer) | int64 ns | 0 | Digest-relevant, so not inside `diag` |
| *(reserved)* `ActuationDelayJitter` | same object | `PointerValue` to a `RandomVariableStream` | null (no RNG object is created) | Not built now. When built, it must carry an explicit `Stream ≥ 0` (§4) |

**Placement.** The exact text matters, because δ = 0 must add no event:

```text
barrier k (sim thread), after the canonical sort (imsi, nodeId, ctlId):
  for c in sorted:
    c.decisionSeq = k; c.decisionSimTimeNs = Now()
    if Now() + δ >= StopTime: Refuse(c, "beyondSimEnd"); continue   // terminal answer at once, deterministic
    if δ == 0: ApplyControl(c)                                       // = journal §5 item 3, unchanged
    else:      Simulator::Schedule(δ, &ApplyControl, c)              // sorted order gives increasing uids
ApplyControl(c), at apply time: D4 precheck → PerformHandoverToTargetCell → ledger line → controlAck
```

**IPC and ledger.**
- **controlAck:** add `decisionSeq`. `seq` and `applySimTimeNs` become the step and time of the apply.
- **Ledger line:** the journal's `(seq, applySimTimeNs, viaNodeId, imsi, sourceCell, targetCell, outcome, cause)`, plus `decisionSeq`, `decisionSimTimeNs` and `delayNs`.
  - `sourceCell` is read at apply time.
  - At δ = 0, `decisionSeq == seq` and `delayNs == 0`, so the M8 references already carry the final schema.
  - New cause: `beyondSimEnd`, mapped to the same E2AP cause family as the other ns-3 refusals.
- **Agents:** no logic change. A `controlAck` may now arrive at any time, and the agent loop is already non-blocking.

**How the repeat gate still holds.**
- **Deterministic.** δ is a constant, controls apply in canonical order, and ties break by uid.
- **Replay.** The replay sink injects each ledger control at its `decisionSeq`, never at its apply step. ns-3 re-applies the δ recorded in the manifest, and the gate requires `actuationDelayNs` to be equal across the 3 runs and the replay.
- **New checks:**
  1. **δ-inertness.** A no-control run has the same digest at δ = 0 and at δ = 50 ms. This proves the knob creates no events or RNG streams.
  2. **δ-liveness.** In R0 at δ = 50 ms, the first applied control's `UeHandoverStartStats` row is exactly δ later than at δ = 0. (I expect a constant X2/RRC offset; verify that slot alignment adds less than one TTI.)
  3. **Ledger rule.** Every ledger line has `applySimTimeNs − decisionSimTimeNs == delayNs`.

**Values per rung.**
- R0, R1 and R2 gates: δ = 0.
- R3 acceptance: δ = 0, as the journal plans.
- **R3 extra run** at δ = 150 ms. It must pass these functional checks:
  - each control gets exactly one terminal answer;
  - if the harness triggers on consecutive steps, at least one duplicate-control refusal appears;
  - rc RestartCount is 0;
  - ns-3 keeps running.
  - Why 150 ms: it sits in the edge budget and is not a multiple of P, which avoids the tie in "What to avoid".
- **Before any performance claim:** sweep δ ∈ {0, 20, 50, 100, 150, 200, 500} ms with ≥ 3 `RngRun` values each.
- **My falsifiable prediction from §5:** the outcome stays within about 3 % of d = 0 up to 100 ms in this scenario. A steeper curve would itself be a finding about TS + QP, for example load dynamics.

**Wall cost.**
- **Pacer waits:** zero extra. Controls are still read at barrier k.
- **ACK latency** grows by about (δ / P) · C:

  | Config | δ = 50 ms | δ = 150 ms |
  |---|---|---|
  | 2 gNB | 0.32 s | 0.96 s |
  | default | 1.6 s | 4.8 s |

  4.8 s is past rc's 2 s ack timer. That timer only logs (counsel B), and gates never read rc's log (G9).

**Work checklist (for the M8 plan).**
1. Add `ActuationDelay`, `StopTime` and `--e2ActuationDelayMs`; default 0.
2. Make `ApplyControl` the only path to the D4 method. Call it synchronously when δ = 0.
3. Add `decisionSeq`, `decisionSimTimeNs`, `delayNs` and `beyondSimEnd` to the ledger and to `controlAck`. Add `actuationDelayNs` to `hello` and the manifest.
4. Replay sink: inject at `decisionSeq`.
5. Add checks 1–3 to the R0 gate.
6. Add the R3 δ = 150 ms functional run to the R3 plan.
7. Put the δ sweep and a stated latency budget (§3) in the results template.

## 7. Q5: the strongest counterargument to my position

**It is my own data.**
- In this scenario, δ ≤ 100 ms moves decision quality by at most about 2 % of its value.
- R3's dominant non-realism is QP's wall-clock window (G2), not actuation.
- Every precedent runs at d ≈ 0: ns3-gym, ns-o-ran-gym, and ns-O-RAN online in practice.
- M8's deliverable is functional ("RC control causes a handover").
- So δ is second-order for everything this project gates, and the effort should go to G1/G2.
- And `Simulator::Schedule` is "one line" whenever it is needed.

**My reply.**
- I agree on priority. That is why I ask only for the seam and one R3 run, not a new default.
- "One line" is true only if the precheck, the ACK and the ledger already live at apply time. If M8 puts them at the barrier, the later change touches the control contract and the replay rule, and forces a re-baseline after M9.
- Also: a δ alone is not realism. The RAN side is idealised too: a 0.7 ms handover against about 49.5 ms for legacy LTE. Any "realistic" profile must state both.

## 8. What to avoid

- Mapping per-control wall latency into sim time (§4).
- A stochastic δ with an auto-assigned RNG stream (§4 trap).
- Prechecking at the barrier and applying at t + δ (time-of-check/time-of-use; the NoAuto outage fallback).
- Expressing δ as "d periods". It ties the model to P and mixes it up with the overlap optimisation.
- Using δ = n·P exactly without a written tie rule.
  - The apply then lands on the same timestamp as step k+n's emission and barrier.
  - It runs after that step's report (uid order), so it is deterministic but surprising.
- Calling the result "realistic" with only the wire time modelled, the handover still at 0.7 ms, and no stated budget.
- Reporting any closed-loop gain, above all against TTT baselines, without the δ sweep.

## 9. Success metrics

- **M8:**
  - the δ = 0 digests equal those of the seam-less design (null-δ equivalence);
  - checks 1–3 pass;
  - no reference digest changes when δ is later set non-zero in a new run.
- **R3 at δ = 150 ms:**
  - every control has one terminal answer;
  - the duplicate-control refusal is observed, and deterministically so across repeats;
  - no crash.
- **Results:** every closed-loop figure carries δ and the handover model, and a δ-sensitivity curve.

## 10. Questions back to you

1. **What will R3's output be used for?** A functional "the loop closes" demo, or the first numbers you compare against a baseline or publish? If the latter, which δ will you defend to a reviewer, and how will you show insensitivity without a knob?
2. **Do you accept moving the precheck, ACK and ledger to apply time in M8?** It is identical at δ = 0, and it makes a later δ a config change rather than a contract change. If you do not, what will the ACK semantics be once δ arrives?
3. **By "transmission time from sender to receiver", which do you mean?** Only the E2 wire (about 1–5 ms), or the full loop (about 30–150 ms at the edge)? And will the RAN-side handover execution, the larger gap (`UseIdealRrc=true` is hard-set at `scenario-zero.cc:350`), be handled in the same realism step?

## 11. Assumptions

| # | Assumption | Confidence | What would change the answer |
|---|---|---|---|
| 1 | R3, or work after it, will eventually feed comparative or published closed-loop claims | medium | If it never does, my case shrinks to the seam alone |
| 2 | Edge-deployed RIC, about 1–5 ms of transport each way | medium | A cloud RIC adds about 15–30 ms. Use 50 → 80 ms as the central value |
| 3 | QP query plus VAR inference takes 10–100 ms | low (unmeasured, P-B3) | If it exceeds 200 ms, the central δ moves past one period and the R3 extra run should use about 250 ms |
| 4 | SINR best-cell persistence is a fair proxy for TS's throughput-ranked decision | medium | Strong load dynamics would make δ matter more. Re-run the analysis on R3's PDCP traces |
| 5 | The M8 control path is not written yet, so the seam costs tens of lines | high (journal: nothing in M8 started) | — |
| 6 | The offset between `ApplyControl` and the handover-start row is constant | medium | If slot alignment varies it, check 2 becomes "within one TTI" |
| 7 | The SINR trace does not depend on the handover mode (all cells are measured) | medium-high | — |

## 12. Inputs and sources

**Repo, as read:**
- `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md`
- the pacing counsels A, B and C, and the prior-art research (`plans/reports/*-261022-1045-*`)
- the fact pack and the contract
- the ns-3 fork @ace32168 and oran-interface @438a839, at the lines cited above

**Third-party code:** ric-app-ts @19e169b2e81a0dbaf3d9dc526de0415cc995ee8b, shallow-fetched into the scratchpad.

**Specs:**
- O-RAN.WG3.TS.E2GAP-R004-v08.00 §5.1.1 and §5.3.2.4. I read the user's cached full text: `thienandangthanh/zotero-vault` `storage/WVKTACCS/.zotero-ft-cache`, via `gh api`.
- 3GPP TR 36.881 §5.2.2, read via the mirror <https://itecspec.com/3gpp/36.881/s/5.2.2>. I did not read the 3GPP PDF.

**Literature** (DOIs checked on Crossref):
- D'Oro et al., "dApps…", IEEE ComMag 2022, [10.1109/MCOM.002.2200079](https://doi.org/10.1109/MCOM.002.2200079). I read the full arXiv text, [2203.02370](https://arxiv.org/abs/2203.02370).
- Polese et al., "Understanding O-RAN…", IEEE COMST 2023, [10.1109/COMST.2023.3239220](https://doi.org/10.1109/COMST.2023.3239220) (arXiv 2202.01032).
- Lacava et al., "ns-O-RAN", WNS3 2023, [10.1145/3592149.3592161](https://doi.org/10.1145/3592149.3592161), §3 (arXiv 2305.06906).
- Lacava et al., TS xApp, IEEE TMC 2024, [10.1109/TMC.2023.3266642](https://doi.org/10.1109/TMC.2023.3266642) (arXiv 2209.14171).
- Polese et al., ColO-RAN, IEEE TMC 2023, [10.1109/TMC.2022.3188013](https://doi.org/10.1109/TMC.2022.3188013).
- Ko et al., EdgeRIC, NSDI 2024, <https://www.usenix.org/conference/nsdi24/presentation/ko>. I read the full arXiv text, [2304.11199](https://arxiv.org/abs/2304.11199): the abstract's "> 15 ms" and the twin delays of 15 and 30 ms (Table 2).
- Schmidt et al., FlexRIC, CoNEXT 2021, [10.1145/3485983.3494870](https://doi.org/10.1145/3485983.3494870). Abstract level only ("reduces round trip time by two" against O-RAN's reference implementation); I could not read absolute RTTs.
- Obiuwevwi et al., arXiv [2607.01583](https://arxiv.org/abs/2607.01583) (ICCCN 2026). Abstract only; preprint.
- Fujimoto, and HLA lookahead: as cited in the research report §4b.

**Not verified:**
- the EdgeRIC slides' "~30 ms cloud RIC";
- an aggregator's "10–50 ms per cycle (Lacava et al. 2023)", which I found no primary source for and do not use;
- FlexRIC's absolute RTTs.

## 13. Unresolved questions

1. QP's real latency: the query plus VAR inference, and the first-call training time. Measure at R2/R3 (P-B3).
2. Whether an ACK that arrives after rc's 2 s timer, which happens at the default config with δ > 0, takes any code path other than logging. Counsel B says it only logs; re-verify at rc @a2282ee.
3. Whether `UseIdealRrc=false` works in this EN-DC fork, for RAN-side handover realism.
4. How the phase of the 3GPP channel re-draws relative to the barrier drifts over long runs. It matters only for δ < 40 ms, and only slightly.
5. Which E2AP cause to use for `beyondSimEnd`. Take it from the M8 refusal mapping.

---

## Appendix: offline analysis script

This script is the evidence behind §5. It uses the standard library only; run it with `python3 -I <script> <MmWaveSinrTime.txt>…`. The random-baseline column is computed inside the δ loop as `sum(ev[co] - ev[c] for c in ev) / len(ev)`.

```python
P, DELAYS, JUMP_DB = 0.1, [0.0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0], 10.0
# load: series[imsi][cell] = [(t, sinr_dB)]  from lines "t imsi cell sinr"
# for each imsi, k >= 1 while k*P + P + max(DELAYS) <= tmax:
#   obs[c]  = mean sinr over (k*P - P, k*P]          ; cstar = argmax obs
#   for d in DELAYS:
#     ev[c] = mean sinr over [k*P + d, k*P + d + P)   ; co = argmax ev
#     hit[d] += (co == cstar); loss[d] += ev[co] - ev[cstar]
#     rnd[d] += mean_c(ev[co] - ev[c])
# jump phase: for consecutive samples of one (imsi, cell) with |dSINR| > 10 dB, histogram (t mod P)/P in 10 bins
```

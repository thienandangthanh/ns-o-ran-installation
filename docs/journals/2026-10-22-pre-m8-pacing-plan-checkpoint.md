# Pre-M8 checkpoint: pacing plan for ns-3 ↔ E2 agents ↔ OSC Near-RT RIC L-release (approval required before M8)

Date: 2026-10-22. Plan: `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/plan.md`. Status: **awaiting the user's approval** (section 9). Nothing in M8, R0–R3 or M9 has started.

This journal is meant to be read cold. It records where the port stands, what three blind counsels and an independent prior-art search concluded, what the probes measured, and which points need a yes, a no or an edit.

Inputs (all committed):

| Input | Path |
|---|---|
| Counsel brief (brief SHA `552a58f`) | `plans/reports/brief-261022-1043-GH-1-pre-m8-pacing-counsel-input.md` |
| Counsel A, determinism lens | `plans/reports/counsel-261022-1045-GH-1-pacing-a.md` |
| Counsel B, RIC/E2 timing lens | `plans/reports/counsel-261022-1045-GH-1-pacing-b.md` |
| Counsel C, ns-3 internals lens | `plans/reports/counsel-261022-1045-GH-1-pacing-c.md` |
| Prior-art research | `plans/reports/research-261022-1045-GH-1-ns3-external-controller-pacing-prior-art.md` |
| RC/TS/QP fact pack | `plans/reports/scout-261022-1026-GH-1-rc-ts-qp-ns3-control-fact-pack.md` |
| Probe evidence | `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/` |

All three counsels ran on Opus 5.5 at xhigh effort, were spawned in one message, and state in their first line that they read neither another counsel's report nor the research.

## 1. Where we are, and the evidence

- **M0–M7 are green** in the dev run and in one unattended re-run from `fresh-install` (P8, harness `8ed1d9f`, snapshot `f7-rerun-green`). Every verdict was re-checked on decoded wire bytes (`plans/reports/handoff-261022-0416-GH-1-pre-m8-pacing-planning-gate.md` §6).
- **ns-3 is the slow side.** Wall seconds per simulated second, ns-3 `default` profile, null sink, 3 repeats, CV < 1 % (`plans/reports/timing-261022-0217-GH-1-ns3-scenario-zero-real-vs-sim-time.md`; P8 re-run `evidence/m4/20261021T225423Z`):

| Config | Wall s per sim s | One 0.1 s KPM period |
|---|---|---|
| 1 gNB, no LTE E2 node | 1.685 (P8: 1.644) | 0.17 s |
| `--nMmWaveEnbNodes=2` (eNB 1 + gNB 2–3), probe | 6.360 (6.322–6.411, CV 0.7 %) | 0.64 s |
| default (eNB 1 + gNB 2–5, 12 UEs) | 31.96 (P8: 29.72) | 3.2 s |

- **Free-run ns-3 output already repeats bit for bit** (probe P-A, offline, `evidence/p-a-free-run-digest/20261022T020913Z/`). IPC `sample` lines with `ipcDropped` removed are identical across 6 M4 runs (dev and the P8 rebuild from `fresh-install`; 5 nodes × 100 samples) and across 3 live M7 runs under the RIC, including e2term pod deletes, agent restarts and dropped samples (5 nodes × 420 samples). The handover traces match over their common prefix. 38 of 45 M4 trace files are byte-identical; the rest differ only in wall-clock fields and in two `DlE2RlcStatsLte.txt` columns (cause not confirmed). Counsel A found this first; the orchestrator re-ran it with `scripts/probes/compare-ns3-ipc-sample-digests.py`.
- **Consequence.** The only external input to ns-3 is a control. A repeatable closed loop therefore reduces to a repeatable *applied-control sequence*: the step, sim time, IMSI and target of every control. Pacing has to make that sequence a function of ns-3's output, and make any violation visible.
- **Measured RIC hops** (counsel B, re-checked by the orchestrator against `evidence/m7/20261021T233129Z/m7.pcap` and `evidence/m6/20261021T232516Z/m6-kpimon.log`): E2Setup round trip ≈ 3.0 s (8 of 10 associations, 5 ms for 2); E2SetupResponse → kpimon RICsubscriptionRequest 0.25–4.99 s (kpimon's 5 s poll phase); subscription answered in < 1 ms; kpimon receive → InfluxDB write p50 10 ms, p99 30 ms.
- **rc control path** (probe, section 6): a gRPC call to rc reaches the target agent as a RICcontrolRequest in 5.6–9.9 ms (p50 6.6 ms, n = 30, under ns-3 default load), so the RIC chain is negligible against ns-3's step cost.
- **RIC behaviour while ns-3 is paused** (probe, section 6): nothing reacts. SIGSTOP of ns-3 for 60, 300 and 900 s gave zero E2AP frames, continuous SCTP heartbeats, no ABORT/SHUTDOWN/re-subscription/delete/ErrorIndication, all nodes CONNECTED, and indications resumed within 8 s; the paused run's samples equal free-run's.

**Probes run in this gate.** Each started from a revert of `f7-rerun-green`, took no snapshot and pushed nothing to the forks. The scripts are in `scripts/probes/` at harness `d87effa` (launcher `vm-exec-probe.sh`). Each evidence directory has a README.

| Probe | Requested by | Decision it informs | Evidence | Result |
|---|---|---|---|---|
| P-A free-run digest (offline) | A | whether bit-identity is a realistic gate | `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/p-a-free-run-digest/20261022T020913Z/` | identical across 9 runs |
| ns-3 pause 60/300/900 s | A, B, C | T bounds; freeze safety | `…/evidence/ns3-pause-ric-reaction/20261022T022027Z/` | no RIC reaction |
| 2-gNB timing | B, C | M8 sizing; d = 0 vs d = 1 | `…/evidence/ns3-timing-two-gnb/20261022T025217Z/` | 6.36 wall s per sim s |
| rc gRPC → agent latency | B, C | W and T values | `…/evidence/rc-control-latency/20261022T025759Z/` | p50 6.6 ms, max 9.9 ms |

Not run:
- the optimized-profile timing. All three counsels marked it optional, and no decision depends on it.
- probe (b), the pcap round-trip proxy. The direct rc probe replaces it.

Deviation from the plan: the orchestrator (Opus) wrote the probe scripts itself instead of a Sonnet agent. It re-computed every probe number on the host from the raw pcap or trace.

## 2. Locked RC inputs and the R2/R3 gaps

**Locked by the user (2026-10-22), not reopened here:**
- A RICcontrolRequest may land on **any** E2 node's agent and is routed by IMSI inside ns-3 to the LTE master RRC (`PerformHandoverToTargetCell`). Every agent, the eNB included, advertises RC **RAN function 3**, because TS hard-codes 3 (`ts_xapp.cpp:614-615`).
- **E2SM-RC v2.0**, generated from rc @a2282ee `e2sm/e2sm-rc-2.0.asn` with a pinned generator.
- Ladder target **R3** (real TS + real QP). M9 = revert `fresh-install`, one unattended invocation to the highest green rung.

**Gaps that block or shape R2/R3** (sources: fact pack §5–§8; counsels as cited; the orchestrator re-checked the items marked ✔):

| # | Gap | Effect | Source |
|---|---|---|---|
| G1 | QP reads InfluxDB `UEReports`/`CellReports`; kpimon writes `UeMetrics`/`cellMetrics` | QP cannot read kpimon's data as-is; a field-level mapping is not designed yet | fact pack §7 ✔ |
| G2 | **NIST's QP patch queries `range(start: -1600ms)` of wall clock** ✔ | Under lock-step the window holds at most the last step's rows. At the default config QP has < 10 rows and falls back to repeating the last value; at 1 gNB it sits at the ≥ 10-row threshold and can flip run to run. R3 is wall-clock coupled. | `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/install_patch_files/xApps/qp/src/database.py.patch:98`, applied by `additional_scripts/install_xapp_qoe_predictor.sh:111`; counsel A §Q4, B §Q4 |
| G3 | TS's default control transport is `rest` to a 127.0.0.1 echo | Must be set to gRPC → rc:7777; NIST patches only the AD route | fact pack §6 |
| G4 | TS builds `cell_map` once at start-up from e2mgr `e2nodeComponentRequestPart`, searching for the uppercased ranName suffix | Our agents' E2Setup must carry that suffix in the component request part, and TS must start after every agent is CONNECTED | fact pack §6 ✔; counsel A §Q7 |
| G5 | TS is triggered only by an A1 policy (type 20008, threshold) or an AD anomaly (RMR 30003); real AD runs on a 0.5 s wall schedule | R2/R3 need a harness-driven 30003 trigger (an RMR route for a stub); real AD cannot drive a repeatable rung | fact pack §6; counsel A §Q4, B §Q7 |
| G6 | TS hard-codes the UE id (`stoi`) and VIAVI GUAMI constants; rc requires AMF-UE-NGAP-ID, GUAMI and F1AP/E1AP id lists | The agent maps AMF-UE-NGAP-ID to the IMSI and ignores the other ids | fact pack §5–§6 ✔; counsel C §Q3 |
| G7 | TS dereferences a failed map lookup when QP's prediction lacks the serving cell | An empty QP window (G2) can crash or corrupt TS | `ts_xapp.cpp:702-703`; counsels A, B |
| G8 | **rc panics on a RICcontrolAcknowledge without `RICcontrolOutcome`** ✔ | `GetControlOutcome` takes `&buffer[0]` of an empty slice in an unrecovered goroutine; every ACK must carry an E2SM-RC ControlOutcome Format 1 (an empty list is legal) | rc `rcE2SmRc.go:134`, `rcControl.go:90,345`; counsel B §Q6 |
| G9 | rc's request instance counter increments twice per request ✔ and lives as long as the pod; acks are RMR-routed by `ricInstanceID`, which can collide with submgr subscription ids (kpimon's) | Ack delivery to rc is not deterministic; gates must judge acks on the wire, never on rc's log; restart rc per run | rc `rcControl.go:136-141`; counsel B risk 1 (routing tables not re-checked) |
| G10 | QP keeps model files between runs; TS keeps `cell_map` and the A1 threshold for its process lifetime | Per-run reset of rc, QP, TS and the Influx bucket is part of repeatability | counsels A §Q7, B risk 5 |

None of these is fixed in this gate. They are inputs to the M8 and R2/R3 planning.

## 3. Counsel consensus and dissent

Legend: ● agrees with the row's recommendation, ◐ agrees with a variation, ○ dissents.

| Q | Point | A | B | C | Synthesis |
|---|---|---|---|---|---|
| Q1 | Lock-step; ns-3 owns sim time; the RIC cannot be clock master (no "done"/"no action" on E2) | ● | ● | ● | Consensus |
| Q1 | One step = one KPM period (0.1 s sim) | ● | ● | ● | Consensus |
| Q1 | Real time rejected; free-run kept as demo and rollback | ● | ● | ● | Consensus (HardLimit aborts once lag > 0.1 s, `realtime-simulator-impl.cc:62-72,362-382` ✔) |
| Q1/Q2 | **Who releases a step** | harness *pacer* (a fourth IPC peer) knows the trigger steps; other steps release in ms | wall gate T after the last forward-ack, on every step | agent holds `step(k)` for a window W, on every step that carried an indication (= every step under option A) | **Dissent.** Recommendation: pacer (section 5) |
| Q2 | T only detects faults, apart from a quiet window W | ● | ◐ (T is the window) | ● (T_step = W + 2 s) | Mostly agreed |
| Q2 | **On expiry** | freeze, then fail the run | continue; late control → RICcontrolFailure `control-timer-expired`; run tainted | continue and flag; detach a node after 3 timeouts | **Dissent.** User decision D2 |
| Q2 | Repeat gate | 3 runs, bit-identical ledger and trace digest, replay oracle, `RngRun` non-vacuity | 3 runs per rung, identical samples, ledger, handover trace, decoded RC | 2 live runs + 1 replay | Recommendation: A's gate (D8) |
| Q3 | Barrier is one sim-thread event after the last emitter; poll all agent sockets; no IPC thread, no cross-thread `ScheduleWithContext` | ● | ● | ● | Consensus (cross-thread events are stamped `m_currentTs + delay` at merge time, `default-simulator-impl.cc:157-182` ✔; `Schedule` asserts the main thread, `:226-227` ✔) |
| Q3 | Controls sorted canonically before applying (rc sends each from its own goroutine) | ● | ● | ● | Consensus |
| Q3 | Only ns-3 blocks; agents never block | ● | ● | ● | Consensus (a blocked agent misses submgr's 2 s × 2 timer) |
| Q3 | Start barrier: wait until every agent is READY with ≥ 1 subscription | ● (reset step) | ● | ● (`step(-1)`) | Consensus |
| Q4 | No RIC/E2 timer fires on an indication pause | ◐ (e2term/e2mgr unverified) | ● (read at deployed tags) | ◐ | Consensus; probe result in section 6 |
| Q4 | QP's and AD's wall-clock windows are the real coupling | ● | ● | ◐ (read upstream QP, not NIST's patch) | Consensus after the orchestrator's check of the NIST patch |
| Q5 | Keep option A through R3; option B bins on `floor(simTimeNs / P_rep)` | ● | ● | ● | Consensus; honouring kpimon's 10 000 ms literally starves QP (all three) |
| Q6 | ACK when ns-3 has validated and scheduled the handover; FAILURE with a cause on refusal; never ack on queue or on completion | ● | ● | ● | Consensus |
| Q6 | ns-3 must pre-check refusals (unknown IMSI → `GetUeManager(0)` assert ✔; same/unknown target → X2 assert ✔; in-handover → silent no-op) | ● | ● | ● | Consensus |
| Q6 | ACK carries a ControlOutcome Format 1 | — | ● | — | Adopted (G8, verified) |
| Q6 | One additive public `LteEnbRrc` method for the prechecks (the needed maps are private) | — | — | ● | User decision D4 |
| Q7 | `--handoverMode=NoAuto` for M8–R3 | ○ (DynamicTtt + `TakeUeHoControl`) | ● | ● | Recommendation NoAuto (D3): C showed a TTT-scheduled handover can trip `NS_ASSERT_MSG(sourceCellId == m_lastMmWaveCell)` after a RIC handover (`lte-enb-rrc.cc:4401-4405` ✔) |
| Q7 | Per-run RIC reset (rc, QP, TS after CONNECTED, Influx bucket) | ● | ● | — | Adopted |
| Q7 | R2/R3 are not bit-repeatable with stock QP/AD | ● (needs a decision) | ● | ● | Consensus; user decision D6 |
| Q8 | Pacing behind an opt-in attribute, default free-run (M5–M7 unchanged) | ● | ● | ● | Consensus |
| Q8 | Fallback | scripted lock-step without the RIC, then free-run with controls at the next boundary | free-run with controls at each service point; or freeze on scripted steps | same control path polled per period with zero wait | Merged in section 7 |

**Biggest risk named by each counsel:** A, R3's xApps assume real time (G2, G5, G7). B, rc crashes on an ACK without an outcome and ack routing is random (G8, G9). C, ns-3 aborts on an unguarded control (prechecks, NoAuto).

## 4. Research findings

Full report, with every source: `plans/reports/research-261022-1045-GH-1-ns3-external-controller-pacing-prior-art.md`. The orchestrator spot-checked four citations against the source: ns-o-ran-gym `ns_env.py:354-362` ✔, ns3-gym `opengym_interface.cc` @cfff7f3 ✔, the HELICS v3.7.0 force-grant quote ✔, and the ns3-gym and ns-O-RAN DOIs on Crossref ✔.

- **Every lock-step precedent blocks without a step-level timeout**: ns3-gym (Gawłowicz and Zubow, MSWiM 2019, [10.1145/3345768.3355908](https://doi.org/10.1145/3345768.3355908); ns-3 holds a ZMQ REQ socket and blocks in `recv`, then runs the actions inline), ns-o-ran-gym (named semaphores, one step per E2 period; on timeout it only checks whether the sim ended and waits again), helics-ns3, SUMO TraCI, FMI `doStep` and mosaik. Where timeouts exist they are liveness or diagnostic checks.
- **Continuing past a late peer costs determinism, by the precedents' own documentation.** HELICS: a real-time force grant "can lead to non-deterministic behavior" ([v3.7.0 config reference](https://github.com/GMLC-TDC/HELICS/blob/v3.7.0/docs/references/configuration_options_reference.md)). Fujimoto ("Zero Lookahead and Repeatability in the HLA"): repeatability needs the same timestamp for each external input in every run, and a fixed order for simultaneous events.
- **ns-O-RAN has never paced ns-3 against a live RIC.** Online mode runs free and rebases timestamps (Lacava et al., WNS3 2023, [10.1145/3592149.3592161](https://doi.org/10.1145/3592149.3592161), §3). Lock-step exists only in gym file mode, without a RIC, and in the fork that path is mutually exclusive with IPC emission (`lte-enb-net-device.cc:936-1035, 1430` ✔), so it cannot be reused.
- **Colosseum avoids pacing by being real time** (real SDRs and an FPGA channel emulator; slower models are computed offline and replayed). Its repeatability evidence is statistical (Bonati et al., DySPAN 2021, [10.1109/DySPAN53946.2021.9677430](https://doi.org/10.1109/DySPAN53946.2021.9677430); Polese et al., OJ-COMS 2024, [10.1109/OJCOMS.2024.3447472](https://doi.org/10.1109/OJCOMS.2024.3447472)).
- **ns-3 `RealtimeSimulatorImpl`** cannot pace a simulator slower than real time: BestEffort falls behind, HardLimit aborts.
- **No digital-twin primary source** paces a slower-than-real-time simulator against a live near-RT RIC. OpenTwin (2026 preprint) keeps ns-O-RAN outside the per-action loop; NVIDIA AODT is client-stepped with no E2 interface in the pages read.
- **Gap in the literature:** no source discusses E2/RIC procedure timers under a paused simulator. Section 6's pause probe covers it for this stack.

## 5. Recommendation

**Mode: pacer-gated lock-step, one step per KPM period, ns-3 the only time base and the only component that blocks.**

1. **Roles.** ns-3 owns sim time. A harness *pacer* grants each step. The RIC is a function evaluated inside a step and never a clock. Wall clock is used only for deadlines. (Counsel A's structure, with B's and C's mechanics.)
2. **Why a pacer instead of a window on every step.** In this stack every control starts from a trigger the harness injects: an rc gRPC call (R0/R1) or the 30003 message that TS acts on (R2/R3) (counsel A §Q1, citing `ts_xapp.cpp:785-799, 726-729` and `rcControl.go:101-141`). The pacer therefore knows which steps can produce controls and releases every other step at once. A window on every step (B, C) costs W per step and gives only "repeatable if nothing was late"; at the 2-gNB config (C = 0.64 s per step, probe) a 1 s window on every step multiplies wall time by about 2.6, against about 1.0 with the pacer.
3. **Thread path (all three counsels).** One pacer object in oran-interface; every emitter registers in `Start`. When the last registered emitter has emitted seq k, the pacer schedules the barrier with `Simulator::ScheduleNow`. The barrier, on the sim thread: flush the queued samples; `poll()` all agent sockets plus the pacer socket; buffer every `control`; wait until every node has sent `step{k}` (or hit EOF) and the pacer has sent `go`; sort the controls by (imsi, nodeId, ctlId); run the prechecks and the handover synchronously through a handler registered by the LTE master device (oran-interface cannot call `LteEnbRrc`; lte and mmwave link it, counsel C §Q3); write each outcome to the ledger and the trace; send one `controlAck` per control; return. A start barrier (`step` with k = −1) waits for every agent READY with ≥ 1 subscription before the first sample.
4. **Agents never block.** Each agent forwards sample k, then sends `step{k, forwarded, …}`. On an inbound RICcontrolRequest it decodes E2SM-RC v2.0, rejects what it can itself (decode error, RAN function ≠ 3, style/action ≠ 3/1, IPC down), and forwards `control` over IPC. It answers RICcontrolAcknowledge (with a ControlOutcome Format 1) or RICcontrolFailure (with a cause) when ns-3's `controlAck` arrives.
5. **IPC messages** (schema v1, minor bump; receivers ignore unknown keys, so free-run v1 peers keep working):

| Message | Direction | Fields (wall-clock values only inside `diag`, excluded from digests) |
|---|---|---|
| `control` | agent → ns-3 | `nodeId`, `ctlId` (agent-monotonic), `ric{requestorId, instanceId, ranFuncId}`, `style`, `action`, `imsi` (from AMF-UE-NGAP-ID), `targetCellId` (from the NR CGI), `afterSeq`, `diag{}` |
| `controlAck` | ns-3 → agent | `nodeId`, `ctlId`, `outcome` (`applied` / `refused`), `cause`, `seq`, `applySimTimeNs`, `sourceCellId` |
| `step` | agent → ns-3 | `nodeId`, `seq` (−1 = ready), `forwarded`, `droppedNoSub`, `controls` |
| `step` | ns-3 ↔ pacer | ns-3 → pacer `ready{seq, simTimeNs, buffered controls}`; pacer → ns-3 `go{seq, expect?}` or `abort{reason}` |
| `hello` | ns-3 → agent | adds `pacing: "lockstep" | "free"` and the deadlines |

6. **Actuation time.** Controls apply at the barrier's sim time (d = 0), as both ns-3 gyms do. A one-period lookahead (d = 1) is kept as an option (D5).
7. **Handover policy.** `--handoverMode=NoAuto` for M8–R3, without `TakeUeHoControl`. Every handover line then joins one-to-one with an applied control, and NoAuto keeps the outage fallback (D3).
8. **Ledger.** ns-3 writes one line per control: `(seq, applySimTimeNs, viaNodeId, imsi, sourceCell, targetCell, outcome, cause)`. It is the closed loop's ground truth, and the replay sink can feed it back to ns-3 without the RIC.

## 6. How T is set, and the run-out semantics

**Measured inputs:** step compute C = 0.17 s (1 gNB), 0.64 s (2 gNB, `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/ns3-timing-two-gnb/20261022T025217Z/timing/ns3-timing.json`), 3.2 s (default) of wall time per 0.1 s period; RIC hops in milliseconds (section 1); rc gRPC call → RICcontrolRequest at the agent on the wire min 5.6 ms, p50 6.6 ms, max 9.9 ms (n = 30, ns-3 default config running, grpcurl start included; `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/rc-control-latency/20261022T025759Z/`, README there, re-computed on the host from the pcap).

**RIC reaction to a paused ns-3** (`plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/ns3-pause-ric-reaction/20261022T022027Z/`, README there): with 5 agents subscribed, ns-3 was stopped for 60, 300 and 900 s. Inside every window the wire carried 0 E2AP frames and only SCTP HEARTBEAT/ACK (59, 285 and 858 pairs over all 10 association directions); no ABORT, SHUTDOWN, INIT, RICsubscription, RICsubscriptionDelete, ErrorIndication or Reset; e2mgr showed all 5 nodes CONNECTED in every 30 s sample, agent RestartCount stayed 0 and subscriptions stayed admitted; e2term and submgr logged only RMR statistics. Indications resumed on every node within 8 s of SIGCONT, and the run's 73 samples per node equal the M7 free-run samples. **So a frozen ns-3 is protocol-safe for at least 900 s; no deadline needs to stay below an E2 timer.** (The probe's three FAIL checks are a design error in the probe: they compared agent stats counters that refresh only every 5 s; the wire is the ground truth. See the README.)

**Deadlines.** None of them includes C, because each clock starts only once ns-3 is blocked at the barrier.

| Deadline | Applies to | Formula | Start value |
|---|---|---|---|
| T_start | start barrier (every agent READY with ≥ 1 subscription) | covers 8 s hold-off + ≈ 3 s E2Setup + ≤ 5 s kpimon poll + margin | 120 s |
| T_gate | every step: every agent's `step{k}` and the pacer's `go` | fault detection only | 10 s |
| T_ctl | trigger steps with a known number of controls (R0, R1, R2 positive cases) | max(30 s, 20 × L_max), L = trigger injected → `control` read by ns-3 | 30 s, re-set from R0's measured L |
| W | only where the *absence* of a control must be confirmed (R2 negative cases, R3) | max(1 s, 3 × p99.9 of L at that rung) | 1 s. With L ≈ 10 ms at R0 (probe), the 1 s floor dominates; R2/R3 add TS and QP, measured at R2 |

**Wall budget per run:** T_start_actual + (simTime / 0.1) × (C + ε) + Σ over trigger steps of (L + W), with ε a few milliseconds. At the default config this is ≈ free-run speed; at 2 gNBs, simTime 10 s costs about 100 × 0.64 s = 64 s plus the start barrier and the trigger steps.

**What happens when a deadline runs out.** Options for the user (D2):

| Option | Determinism | Repeat gate it allows | Who argued for it |
|---|---|---|---|
| **(a) Freeze, then fail the run** (recommended for gate runs). Hold until the deadline, then abort with a verdict naming the step. Any control that arrives later gets RICcontrolFailure `control-timer-expired`. | Bit-identical, or no verdict at all. A violation can never pass silently. | Bit-identity of ledger and trace digest | A; matches every precedent (section 4) |
| (b) Continue, fail the late control. Release at the deadline; a late control gets RICcontrolFailure `control-timer-expired` and is not applied; the run is marked tainted. | Repeatable only for runs with zero late controls | Same as (a), plus `late == 0` | B |
| (c) Continue and flag. Release at the deadline; a late control applies at the next barrier with a `late` flag; detach a node after 3 timeouts. | Statistical; the ledger can shift by whole steps | Distribution or margin only | C; recommended here for **demo mode only** |
| Drop the late control silently | Worst; violates E2AP (no terminal answer) | none | rejected by all three |

## 7. Rollback

- **Code.** Pacing is an ns-3 attribute plus the `hello.pacing` field, default `free`. With `free`, ns-3, the agents and the gates behave exactly as in M5–M7. The control path, prechecks and ledger work in both modes, so free-run still records which controls applied where.
- **Staging inside M8** (counsel C §Q8): first the control path, prechecks and ack under `free` (controls drained at each period with zero wait), then the barrier.
- **Fallback 1, if the lock-step barrier fails:** scripted lock-step without the RIC, where the pacer injects `control` directly. Deterministic; proves the ns-3 half and localises the fault.
- **Fallback 2, if the RIC half cannot be paced:** free-run with controls applied at the next per-period service point. This meets the contract's M8 text (rc control → handover in the trace, ≥ 2 gNBs), but the repeat gate relaxes to "the same (imsi, target) handovers each run; the step may differ", labelled non-repeatable. The user decides whether to accept it.
- **Not fallbacks:** file-mode semaphores (they bypass E2 and the wire gate) and `RealtimeSimulatorImpl` (section 4).
- **Environment.** `vm-snapshot.sh revert f7-rerun-green`; revert the fork branches. A crash on a control is a precheck bug, not a reason to drop lock-step.

## 8. Changes to the M8 / R0–R3 / M9 acceptance criteria

These add to the contract's acceptance criteria; nothing is removed.

**Common to every paced rung**
- The control ledger is ground truth. Repeat gate per rung: **3 live runs** from the same snapshot and arguments with an explicit `--RngRun`, plus **1 replay** of the ledger without the RIC. Required equal: the ledger, the IPC `sample` lines (no `hello`, `ipcDropped` asserted 0), every ns-3 trace file except the two known `DlE2RlcStatsLte.txt` columns, and the decoded E2SM-RC content per step. Non-vacuity: `--RngRun=2` must change the digest. Margin report: minimum slack per deadline; late controls = 0; agent restarts = 0; rc RestartCount = 0; `droppedNoSub` = 0 after the start barrier.
- Per-run reset before ns-3 starts: restart rc, QP and TS (TS after every agent is CONNECTED, then set the A1 threshold explicitly), and use a fresh Influx bucket.
- Wire comparison ignores E2AP request and transaction ids and the KPM header `colletStartTime`, unless gated runs pin `simStartEpochMs` (D10).
- **Null-control equivalence:** lock-step with no controls gives the same digest as free-run with the same arguments.

**M8 = R0** (scripted rc gRPC, real rc)
- Config: `--nMmWaveEnbNodes=2` (eNB 1 + gNB 2–3) with NoAuto, unless the user picks the default config (D9).
- "≥ 2 gNBs" means ≥ 2 IMSIs handed over to ≥ 2 distinct target gNBs, with at least one control delivered through a non-target agent, the eNB agent included (D7).
- Wire: each injected control gives one decoded RICcontrolRequest (E2AP plus an E2SM-RC v2.0 decode with the pinned generator, independent of the agent's codec) and exactly one terminal answer; each ACK's `RICcontrolOutcome` decodes as Format 1.
- One deliberate refusal (UE already on the target, or an unknown IMSI): a RICcontrolFailure with the expected cause, a `refused` ledger line, no handover, and ns-3 still running.
- ns-3: each applied control is followed by a handover start/end row for that IMSI to that target after the apply time, and by the IMSI moving between the gNBs' decoded KPM UE lists. No handover row without an applied control.
- Never gate on rc's "ack decoded" log (G9).

**R1** (scripted, ≥ 2 gNBs, several controls)
- Controls through different agents; one same-step pair for two IMSIs (exercises the canonical sort); one same-IMSI pair in one step (the second is refused as in-handover).

**R2** (real TS, stub QP, harness 30003 trigger)
- TS uses gRPC to rc:7777 (G3) and starts after every agent is CONNECTED (G4). Positive cases are bit-repeatable; negative cases use W and are labelled statistical.

**R3** (real TS, real QP)
- State the regime at acceptance: with stock NIST QP, R3 is functional plus a D0 replay, not bit-repeatable (G2). A bit-repeatable R3 needs D6.
- QP must never return a prediction without the serving cell (G7); the gate records the time from the step's rows being written to QP's query and its margin under 1.6 s.

**M9**
- Revert `fresh-install`, one unattended invocation up to the highest green rung; that rung runs its repeat gate and its ledger and digest must equal the dev-run reference (cross-install equality already holds for free-run, section 1).

## 9. Decisions for the user (approve or edit) and unresolved questions

| # | Decision | Recommendation | Alternatives |
|---|---|---|---|
| D1 | Step release by a harness pacer (a fourth IPC peer) | **Approve** | agent-held window W on every step (B, C): simpler protocol, costs W per step, only "repeatable if nothing late" |
| D2 | Deadline run-out in gate runs | **(a) freeze, then fail** | (b) continue and fail late controls; (c) continue and flag (kept for demo mode) |
| D3 | Handover mode for M8–R3 | **`--handoverMode=NoAuto`**, no `TakeUeHoControl` | DynamicTtt + `TakeUeHoControl` per UE (A), which needs a fix for the TTT race |
| D4 | One additive public `LteEnbRrc` method that runs the prechecks, cancels any pending TTT event, performs the handover and returns an outcome (control path, not radio or scenario) | **Approve** | prechecks without touching `LteEnbRrc` are not possible: the maps are private (`lte-enb-rrc.h:2005-2007`) |
| D5 | Actuation delay | **d = 0** (apply at the barrier) | d = 1 period: realism and overlap, plus 0.1 s of control delay |
| D6 | R3 repeatability | **Statistical R3 with a D0 replay** (stock NIST QP) | patch QP's window on a fork (scope change); harness compresses `_time` into the last 1.6 s (unverified idea) |
| D7 | Reading of "≥ 2 gNBs" | **≥ 2 IMSIs to ≥ 2 distinct targets, ≥ 1 control through a non-target agent** | contract text literally |
| D8 | Repeat count | **3 live runs + 1 replay** per paced rung | 2 + 1 (C) |
| D9 | M8 config | **`--nMmWaveEnbNodes=2`** (6.36 wall s per sim s, probe) | default config (32 s per sim s) |
| D10 | Pin `simStartEpochMs` in gated runs so KPM header bytes also repeat | **Yes** | compare decoded content only |

**P5 housekeeping as run** (`plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/p5-snapshot-housekeeping/20261022T030653Z/README.md`):
- Deleted one at a time with the VM shut off, every libvirt delete rc 0: `m0-probe-f10212128`, then `f5`, `f4`, `f6`, `f3`, `f1`, `f0`.
  - A guard kept the estimated peak free space ≥ 20 GiB.
  - Each non-leaf delete commits its overlay into the backing image, so the peak need is about the overlay's size.
- `f2-refnode` would have peaked at about 12 GiB free, so the user was asked.
  - The user chose to delete the unreferenced 39.55 GB image `ubuntu24.1792610322` first, then `f2`.
- Kept: `fresh-install` and `f7-rerun-green`.
  - `fresh-install` reverts and boots clean, and its raw base is unchanged.
  - `f7-rerun-green` reverts and boots with all 14 `ricplt` pods Ready.
- `/home` free space went from 31.9 GB to 77 G.

**Unresolved questions**
1. Field-level mapping from kpimon's `UeMetrics`/`cellMetrics` to QP's `UEReports`/`CellReports` (G1); not designed.
2. ~~Whether e2term 6.0.6 forwards a RICcontrolRequest to a node that does not advertise RAN function 3.~~ Answered by the rc probe: it does (30 of 30 delivered to agents that advertise only function 2), so the agent must validate the RAN function itself.
3. The cause of the two differing `DlE2RlcStatsLte.txt` columns (RNTI, LCID) on 9 rows (uninitialised values suspected).
4. The exact `UeHandoverEndStats` columns the M8 trace gate matches on.
5. rtmgr's 12041 route table (counsel B's ack-routing claim) was read in source, not dumped live.
6. Whether NIST's AD patch changes AD's wall-clock window (only relevant if real AD is ever used).
7. The E2AP ack/failure semantics were read in E2AP R004 v08.00; the v02/v03 prose was not read (the ASN enumeration is identical).

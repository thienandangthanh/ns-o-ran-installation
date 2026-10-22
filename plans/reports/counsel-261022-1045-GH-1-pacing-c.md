Blindness: I did not read any `plans/reports/counsel-261022*` or `plans/reports/research-261022*` file. Brief SHA `552a58fb2854c4e5eb889ecc25d31852a91496bf`. Lens C (ns-3 internals and thread safety first).

# Counsel C: pre-M8 pacing, from the ns-3 internals and thread-safety side

Date: 2026-10-22. Kongming, run as `model: opus` (Opus 5.5) per the user's CLAUDE.md override, not `fable`.
Code basis:
- ns-3-mmwave-oran fork `ace3216`, oran-interface fork `438a839` and testbed `725b167` (agent);
- ns-o-ran-gym `0e8ea58`;
- QP `47a35ca`, read with `gh api`.

All paths are relative to the repo root. "NS3" means `ns-3-mmwave-oran/src`, "OI" means `oran-interface/model`, and "AG" means `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src`.

## 1. Executive recommendation

1. **Mode: lock-step.** One barrier per KPM period (0.1 s of sim time). ns-3 owns sim time. Each agent grants the step by sending `step(k)`. The RIC is not, and cannot be, a clock master. Real time is impossible at the measured speeds. *(high)*
2. **Thread model: everything on the sim thread.** The barrier is a single ns-3 event. The last emitter's `EmitSample` for seq k schedules it with `ScheduleNow`. It blocks in one `poll()` over all the emitter sockets. Do **not** add an IPC thread or a cross-thread `ScheduleWithContext`: `DefaultSimulatorImpl` has no wake-up, it stamps the sim time when it merges the event, and `E2IpcTcpClient` is not thread-safe. *(high)*
3. **Two timers, not one.** The decision window W sits in the agent: it holds `step(k)` for W after forwarding indication k, so W is the pacing knob. The ns-3 timeout T_step = W + Δ only detects faults. A crashed agent is seen at once through EOF, not after T. There is also a separate start barrier, T_start. *(high for the split; medium for the values)*
4. **On T expiry: continue and flag.** Record the overrun in the trace, never drop a control, and never freeze. After 3 consecutive timeouts, detach the node. *(medium; the user decides)*
5. **Apply controls in the barrier, synchronously, through prechecks.** The prechecks guard paths that otherwise crash ns-3: an unknown IMSI, a target equal to the source, an unknown target, and a pending TTT event. Ack on apply; send RICcontrolFailure on a refusal. Never wait for handover complete. *(high)*
6. **M8–R3 run with `--handoverMode=NoAuto`.** Do not call `TakeUeHoControl` in NoAuto. In auto modes a RIC handover can trip an `NS_ASSERT` (the TTT race). *(high)*
7. **Repeat gate: 2 live runs plus 1 replay run.** This proves that ns-3 is a pure function of the applied-control log. *(medium)*
8. **Rollback.** Pacing is an opt-in attribute and defaults to free-run, so M0–M7 are unchanged. The fallback is the same control path, polled per period with zero wait. *(high)*

## 2. Q1–Q8

### Q1. Mode, clock master, step

**Recommendation.**
- Use lock-step with one barrier per ns-3 E2 period (`indicationPeriodicity`, 0.1 s of sim time).
- **ns-3 is the time master.** Only ns-3 advances sim time.
- **The agents are step grantors.** `step(k)` means "my window for sample k is closed".
- Step = 1 period. Do not use k-period steps. The agent can grant at once (W ≈ 0) on steps that need no decision, so a coarser step buys nothing.
- Keep free-run (today's M5–M7 behaviour) as the demo and rollback mode. Do not use `RealtimeSimulatorImpl`.

Confidence: **high**.

**Reasoning.**
- **Real time is impossible.** ns-3 runs 1.685× slower than wall time with 1 gNB and 31.96× with the default config (M4, `evidence/m4/20261021T165230Z`).
- **HardLimit aborts.** `RealtimeSimulatorImpl` in `HardLimit` mode raises `NS_FATAL_ERROR` once the wall-clock jitter exceeds `HardLimit`, which defaults to 0.1 s (NS3 `core/model/realtime-simulator-impl.cc:67-72, 362-381`). The default config passes that within about 0.1 s of sim time.
- **BestEffort only adds overhead.** `BestEffort`, the default mode (`:62-66`), just runs behind, which is free-run with extra overhead. Its cross-thread `ScheduleWithContext` stamps events with the wall-derived time (`:549-560`), so it is non-deterministic by design.
- **The RIC cannot be master.** No xApp sends a per-indication "done" or "no action":
  - rc's gRPC `rspCode 0` means only "queued";
  - acks and failures are only logged (fact pack §5);
  - TS acts on A1 or AD triggers (fact pack §6).
- **So the window has to be a timer.** "Nothing to do" cannot be told apart from "not finished" except by a timer. That timer is W. It belongs in the agent, the only process that sees both SCTP and IPC. With TCP ordering, `step(k)` becomes a consistent cut: every `control` written before `step(k)` on that socket belongs to window k.
- **Prior art matches.** ns-o-ran-gym is strict lock-step with zero sim-time actuation delay and "freeze" semantics:
  - ns-3 does `sem_post` and then `sem_wait` with no timeout (NS3 `lte/model/lte-enb-net-device.cc:115,127`) and applies the CSV controls at the same sim time (`:189-195`);
  - the Gym side retries forever (`ns-o-ran-gym/src/nsoran/ns_env.py:354-376`).
  We keep its barrier shape (block once per period, apply at that time) and replace the infinite wait with W/T, because our controller is asynchronous and crash-only.
- **The gym path cannot be reused.** File mode and IPC are mutually exclusive in the fork. The semaphore and `ReadControlFile` path is set up only when `EnableE2FileLogging=true` (`lte-enb-net-device.cc:952-1035`), and that same flag disables IPC emission (`:936-951, 1430-1434`; NS3 `mmwave/model/mmwave-enb-net-device.cc:480-495, 1504-1508`). This verifies fact-pack open item 3.

**Hybrid (an option, not the default).**
- **How it works.** The same barrier runs with a one-period actuation lookahead (d=1). The agent closes window k when sample k+1 arrives, or at W_min, whichever is later. ns-3 applies the window-k controls at barrier k+1.
- **Wall cost.** Wall time per step becomes max(C, W) instead of C + W. The determinism margin grows to about C (3.2 s in the default config) at no wall cost.
- **Costs.**
  - It adds 0.1 s of sim-time control delay.
  - The ack latency rises to about C, which is beyond rc's 2 s timer.
  - It is a second semantics to test.
- **When to switch.** Only if probe P1 shows C ≪ W for the M8 config.

Confidence: medium.

### Q2. How T is set, expiry semantics, repeat gate

**Recommendation (formulas).**

| Symbol | Meaning | Value / formula |
|---|---|---|
| P | step in sim time | 0.1 s (`indicationPeriodicity`) |
| C | ns-3 wall time per step | 0.17 s (1 gNB), 3.2 s (default) [M4]; N=2 **unmeasured** (P1) |
| R | wall latency from trigger to the control reaching the agent: harness or xApp → rc → RMR → e2term → SCTP | **unmeasured** (P2) |
| W | agent decision window, held after the agent forwards indication k | `clamp(3 × R_p99, 0.25 s, 1.5 s)`; **assume 1.0 s** until P2. The 1.5 s cap keeps the ack inside rc's 2 s ack timer for controls that arrive within their own window. |
| T_step | ns-3 barrier timeout (fault detection only) | `W + Δ`, Δ = 2 s → 3 s with W = 1 s |
| T_start | start barrier (`step(-1)`, readiness) | 60 s. The agent needs 8 s hold-off + ≤ 3 s connect + ≤ 10 s setup (AG `agent-config.hpp:23-26`). kpimon needs ≤ 5 s of poll + about 3 s to subscribe (handoff §2). The rest is margin. |
| Wall time per run | | ≈ T_start_actual + (simTime/P) × (C + W_eff), where W_eff = W on decision steps and about 1–5 ms otherwise |

Worked examples at simTime 10, all W_eff = 1 s:
- default config: 100 × 4.2 = 420 s, against 320 s free-run;
- 1 gNB: 100 × 1.17 = 117 s, against 17 s free-run.

Confidence: medium for the values; high for the structure.

**On T_step expiry: continue and flag (recommended).**
- The pacer treats the missing `step(k)` as "no controls from node j in window k".
- It writes a cumulative `stepTimeouts` counter into the sample and `bye` lines. This is an additive key and needs a minor bump.
- After 3 consecutive timeouts it **detaches** node j: it stops waiting for that node until the node sends a fresh `step` for the current barrier.
- A crash (agent exit 2 or 3, then a Docker restart) shows up as EOF in `Drain` (OI `e2-ipc-tcp-client.cc:153-156`). The pacer stops waiting for that node at once, with no T penalty.

| Expiry semantics | ns-3 determinism | Live run-to-run | Liveness | Verdict |
|---|---|---|---|---|
| Continue and flag | D0 holds (ns-3 is a pure function of the applied-control log) | D1 holds only if `stepTimeouts == 0` | ns-3 never stalls more than 3 × T per node | **Recommend** |
| Freeze (wait forever, the gym semantics) | D0 | D1 kept | **Hangs.** A restarted agent has empty state and never answers the old seq (AG `e2-session.cpp:98,153,178`). | Reject |
| Drop late controls | D0 | Not D1: "late" is decided by wall time | OK | Reject: loses intent and gains nothing |
| Abort the run | — | Run invalid | Fails fast but wastes 20+ min | Gate-mode option only |

**Determinism levels** (for the user's decision):
- **D0, always.** ns-3 output is a deterministic function of (build profile, seed, CLI, applied-control log).
  - The fork's event order is deterministic: ts and then uid ordering (NS3 `core/model/default-simulator-impl.cc:222-241`).
  - No seed is set, so the defaults apply. That is `(unverified)` for the harness; `scripts/` has no `RngRun`.
  - Wall clock enters only through the hello epoch (NS3 `mmwave/helper/mmwave-helper.cc:3311-3317`), `ipcDropped`, and the KPM `colletStartTime`. None of these schedules sim events.
- **D1, lock-step with no overrun and R < W.** Live runs with step-keyed scripted triggers give bit-equal traces.
- **D2, R2/R3: no live repeatability.**
  - TS triggers and QP reads depend on wall time;
  - QP reads "last N rows" (`ORDER BY DESC LIMIT`, `ric-app-qp@47a35ca src/database.py:57-73`; NIST's InfluxDB v2 patch may change this, unverified);
  - kpimon stamps `time.Now()`.
  Only D0 holds there.

**Repeat gate.**
- **M8 and R1: 2 live runs plus 1 replay run.** Replay uses a replay sink in `tools/`, analogous to `tools/ipc-null-sink`. It writes the recorded `control` lines and then `step(k)` for each sample k. That keeps ns-3's code path identical and needs no ns-3 replay mode.
- **Compare:**
  1. the applied-control records (`controlAck` lines: seq, nodeId, ctrlId, imsi, target, outcome) are equal;
  2. the per-node `e2-ipc-trace-N.jsonl` sample lines are byte-equal once `ipcDropped`, `stepTimeouts` and the hello lines are removed;
  3. the handover stats files are byte-equal (`UeHandoverEndStats.txt` and others; NS3 `mmwave/helper/mmwave-bearer-stats-connector.cc:195-199`);
  4. `stepTimeouts == 0` in both live runs.
- **Wire bytes cannot be compared byte-for-byte**, because `colletStartTime` carries the wall epoch. Compare the decoded values with the timestamp excluded.
- **R2/R3:** 1 live run plus 1 replay run (D0), plus the functional criteria.
- **M9:** 1 live run plus 1 replay run, to bound the run time.

Confidence: medium.

### Q3. Control path into the ns-3 thread; message shapes; where it blocks

**Recommendation: poll from a sim event on the sim thread. Never use an IPC thread.** Confidence: **high**.

Why not `ScheduleWithContext` from an IPC thread, at the fork pin:
1. **No wake-up.** A cross-thread call only appends to `m_eventsWithContext` under a mutex (NS3 `core/model/default-simulator-impl.cc:260-272`). The sim thread merges that queue only after each event returns (`:147`) and at `Run` start (`:192`). There is no condition variable.
   - If the sim thread is blocked inside an event, as `sem_wait` at `lte-enb-net-device.cc:127` or a barrier `poll` would be, nothing is processed until that event returns.
   - So any design where an IPC thread hands work to a blocked sim thread needs a second primitive. That means two mechanisms where one suffices.
2. **The sim time is chosen at merge.** The stamp is `m_currentTs + delay` (`:177`), the timestamp of whatever event happened to be finishing. In free-run that depends on wall time and is non-deterministic.
   - If merged right after a barrier event, it lands at the barrier time.
   - The uid order among controls from different agents then follows the IPC thread's wall-clock order, so the controls still have to be sorted.
3. **Formal data race.** `m_eventsWithContextEmpty` is a plain `bool` (`default-simulator-impl.h:107`), read without the lock (`.cc:159`). It is the same on upstream ns-3-dev master (https://gitlab.com/nsnam/ns-3-dev/-/raw/master/src/core/model/default-simulator-impl.h, line 97). It is benign on x86 in practice `(unverified)`, but it is UB.
4. **`Schedule` from a non-main thread aborts.** It hits `NS_ASSERT_MSG` (`:226-227`) in the `default` profile (asserts on, per the M4 report). It silently corrupts the scheduler in `optimized`.
5. **The client is single-threaded by contract.** `E2IpcTcpClient` (OI `e2-ipc-tcp-client.h:19-28`): `Fail()` closes and resets `m_fd` and the buffers (`.cc:216-238`) while the sender uses them. An IPC thread means a rewrite.
6. **The "known hazard" is concrete.** The legacy callback ran `TakeUeHoControl` directly on the e2sim thread (`lte-enb-net-device.cc:434`, now compiled out at `:406-465`). That races `m_e2ControlledUes.insert` (NS3 `lte/model/lte-enb-rrc.cc:4474`) against the iteration in `TriggerUeAssociationUpdate`, which runs every 1.6 ms (`:4690`, `CrtPeriod` `:3318-3322`).

**Where the blocking read sits: a pacer barrier event, not `EmitSample`.**
- **Emission times differ by node.** The LTE eNB's first sample is at 500 µs and the gNBs' at 800 µs, then every period (`lte-enb-net-device.cc:947-950`, `mmwave-enb-net-device.cc:491-494`). Blocking in each `EmitSample` serialises up to 5 waits per period.
- **Routing needs a shared object.** A control received on a gNB's socket must reach the LTE RRC. `oran-interface` cannot call `LteEnbRrc`: lte and mmwave link oran-interface (NS3 `lte/CMakeLists.txt:373`, `mmwave/CMakeLists.txt:153`), not the other way round.
- **Design:**
  1. One pacer object per simulation, in oran-interface. Emitters register in `Start`.
  2. When the last registered emitter has emitted seq k, the pacer does `Simulator::ScheduleNow(barrier, k)`. This is deterministic: same timestamp, next uid.
  3. A start barrier (`k = -1`) at a fixed early time, about 100 µs, after all `Start` events at t=0 and before the first sample.
- **Barrier body, all on the sim thread:**
  1. `Flush` each connected client that queued sample k (OI `e2-ipc-tcp-client.cc:262-280`). Otherwise the agent may never see sample k and never send `step(k)`.
  2. Loop on one `poll()` over all pending fds with the remaining T. Call a line-parsing `Drain`; today it discards (`:142-168`, `:151`). Call `Service()` for idle clients so they can reconnect.
  3. Stop when every node has sent `step(k)`, hit EOF, or the deadline has passed.
  4. Sort the window's controls by (nodeId, ctrlId), never by arrival across sockets.
  5. Call the registered LTE handler synchronously.
  6. Write each `controlAck` to the receiving node's trace first (trace = wire), then `Enqueue` and `Flush` it.
- **Wait only for nodes whose sample k was `Queued`.** A `Disconnected` sample (OI `e2-ipc-emitter.cc:118-128`) never reached the agent.
- **Lock-step must be opt-in.** Use an attribute or CLI such as `e2Pacing=free|lockstep`, default `free`. The emitter's documented contract today is "never blocks the simulation" (`e2-ipc-emitter.h:24-33`; architecture doc §3).

**IMSI routing from any node.**
- Every agent forwards `control` over its own IPC socket. The pacer hands it to a handler registered by the LTE master `LteEnbNetDevice`.
- Scenario-zero has exactly one LTE eNB (`scratch/scenario-zero.cc:409`). Every UE is an MC device attached to it (`:519`), so the LTE RRC's `m_imsiRntiMap` covers every IMSI (`lte-enb-rrc.cc:3589-3630`).
- Route by "the LTE RRC for which `GetRntiFromImsi(imsi) != 0`".
- Do not call `PerformHandoverToTargetCell` on a mmWave RRC. `m_mmWaveCellSetupCompleted` is maintained on the LTE side (`lte-enb-rrc.cc:1684-1751`, inferred), so on a gNB it is a silent no-op.
- **Trap.** Register the handler regardless of whether the LTE eNB has an emitter. With `--e2lteEnabled=false` there is none (NS3 `mmwave/helper/mmwave-helper.cc:2510-2513`), and `UpdateConfig`'s E2 block is skipped (`lte-enb-net-device.cc:931`).

**Message shapes** (NDJSON, v1 with a minor bump; the trace is the wire):
- **`control`** (agent → ns-3):
  ```
  {"type":"control","v":1,"nodeId":N,"ctrlId":<agent-monotonic>,"stepSeq":<last sample seq the agent had seen>,"kind":"handover","imsi":<u64>,"targetCellId":<u16>,"ric":{"requestorId":..,"instanceId":..,"ranFuncId":3}}
  ```
  - The agent does all the E2SM-RC v2.0 decoding.
  - It maps `amf-UE-NGAP-ID` to the IMSI, which is consistent with the agent's KPM UE ids (AG `kpm-indication-message.cpp:64-69`).
  - It maps the NR CGI to a cellId.
  - `stepSeq` is a diagnostic cross-check only.
- **`controlAck`** (ns-3 → agent):
  ```
  {"type":"controlAck","v":1,"nodeId":N,"ctrlId":..,"appliedSeq":k,"appliedSimTimeNs":..,"outcome":"initiated"|"refused","cause":"unknownImsi"|"notAssociated"|"hoInProgress"|"alreadyOnTarget"|"unknownTargetCell"|"ueOnLteFallback","sourceCellId":..}
  ```
- **`step`** (agent → ns-3):
  ```
  {"type":"step","v":1,"nodeId":N,"seq":k,"controls":<count sent in this window>}
  ```
  - `seq: -1` is the start or readiness handshake, sent when E2 is READY and at least one KPM subscription exists. It also tells ns-3 the agent can do lock-step, so no new message type is needed.
  - The agent must emit `step(k)` at once while E2 is not READY. ns-3's content does not depend on it, and a freeze would only burn wall time.
- **Hello.** The ns-3 hello adds `"pacing":"lockstep","stepTimeoutMs":T`. A v1 agent ignores unknown keys and types (AG `main.cpp:97-99`). A v1 emitter drains them (OI `e2-ipc-tcp-client.cc:151`), so both directions stay compatible.

**Where a step blocks: in ns-3 only.**
- The agent never blocks. It delays the `step` line with a deadline in its `poll()` loop.
- If the agent blocked, its SCTP heartbeats and E2 procedures would stall, the association would be lost and the agent would exit 2.
- Note: the agent's timer is a 100 ms `timerfd` and its poll timeout is 1 s (AG `main.cpp:135-137, 154`). Either compute the poll timeout from the step deadline, or accept 100 ms of W granularity.

### Q4. Timers while sim time is paused

**Recommendation.** No RIC-side change is needed. Use the agent-held W, bounded at 1.5 s, and T_start = 60 s. Confirm with probe P3. Confidence: **medium**. Lens B owns the e2term and submgr internals; the claims below are partly unverified.

- **SCTP and E2 liveness are decoupled.** The agent is a separate process with a 5 s heartbeat (handoff §2). A barrier wait stops KPM content only.
- **The system already runs with long gaps.** In free-run, M7 sent one indication per node per 3.2 s of wall time for more than 15 minutes with zero ABORTs (handoff §1, §6). Lock-step only adds W on decision steps.
- **E2 procedure timers in e2term and submgr** guard procedures: setup, subscription and delete. The agent answers those at once from its own loop (AG `e2-session.cpp:157-229`), independent of ns-3. I know of no indication-inactivity timer `(unverified; probe P3)`.
- **kpimon's 5 s poll** watches e2mgr connection state, not the indication rate (handoff §2). It is unaffected while the association is up.
- **rc's 2 s ack timer only logs** (fact pack §5).
  - With d=0 and W ≤ 1.5 s, a control caused by indication k is acked within about W.
  - A control triggered by wall time and arriving during ns-3's compute waits up to C + W (4.2 s in the default config). That logs a timeout at rc and is harmless.
  - Gates count acks on the wire, not rc's logs.
- **ns-3's own wall timers** (connect timeout 5 s, backoff 0.1–5 s; OI `e2-ipc-tcp-client.cc:28-30, 233`) never schedule sim events. The barrier loop calls `Service()`, so reconnects proceed during a wait.

### Q5. Subscription option B on sim time

**Recommendation.**
- Keep option A through R3 unless an xApp needs B.
- If B is built:
  - bins are `floor(simTimeNs / P_rep)`;
  - the reporting period P_rep must be a whole multiple of P, otherwise reject the subscription or clamp it to P;
  - `colletStartTime` = hello epoch + bin start, as `sample-forwarder.cpp:62-66` already computes;
  - each metric has a declared aggregation in the metric map: sum, mean or last.
- The step stays one ns-3 period. The agent applies W only on **decision steps**, those that sent an indication, and grants the others at once.

Confidence: **medium**.

**Reasoning.**
- Binning keeps B agent-only, which honours the locked rule, and leaves the pacing contract unchanged.
- Wall overhead becomes C + W × (P / P_rep).
- **Trap for R3.** If B honours kpimon's requested granularity (`granulPeriod = 10000`, contract "User answers" Q2; assumed to be ms), each node reports once per 10 s of sim time. In the default config that is about 320 s of wall time per row. QP, which reads the last N rows, would starve.

### Q6. RC ack semantics and how a refusal surfaces

**Recommendation.**
- **The agent sends RICcontrolAcknowledge** when ns-3's `controlAck.outcome == "initiated"`. That means the X2 McHandoverRequest was sent at `appliedSimTimeNs`.
- **It sends RICcontrolFailure** for:
  - an ns-3 refusal;
  - an agent-side refusal before IPC:
    - undecodable E2SM-RC;
    - a RAN function other than 3;
    - a style or action other than 3/1;
    - a CGI that does not parse or has the wrong PLMN;
    - an IMSI out of range;
  - IPC down.
- **Never ack "on handover complete".** No completion signal exists toward the RIC (fact pack §1). Completion takes sim time beyond the barrier, and its failure modes are unknown.
- **Prove completion from evidence instead:** the ns-3 handover trace, and the IMSI moving between the gNBs' decoded KPM UE lists.
- Map causes to E2AP `CauseRICrequest` values, for example `control-message-invalid` and `control-failed-to-execute`. The exact enum names are `(unverified)`.

Confidence: **high** for ack on apply; medium for the cause map.

**Refusals must be prechecks.** `PerformHandoverToTargetCell` returns `void` (`lte-enb-rrc.h:1635`). Its own guards only print `NS_LOG_UNCOND "## Warn"` (`lte-enb-rrc.cc:4503-4531`). Several paths crash ns-3:

| Case | What ns-3 does today | Precheck → cause |
|---|---|---|
| Unknown IMSI | `PerformHandoverToTargetCell`: a no-op "not associated" (`:4488-4499, 4530`). But `GetUeManager(GetRntiFromImsi(imsi))` with rnti 0 hits `NS_ASSERT` (`:3582-3584`). Even the legacy file path does this (`lte-enb-net-device.cc:180-181`). | `GetRntiFromImsi == 0` → `unknownImsi` |
| UE mid-handover | No-op, "already performing HO" (`:4505, 4521-4526`) | `hoInProgress` |
| Target = current cell | **Not guarded** here, unlike `PerformHandover` (`:4431`) and `ReadControlFile` (`lte-enb-net-device.cc:182-187`). The source mmWave RRC goes to `SendHandoverRequest(rnti, self)` (`:5053-5061, 5193-5206`). Then `EpcX2::DoSendHandoverRequest` asserts the target is in its X2 map (NS3 `lte/model/epc-x2.cc:693-694`). That is an abort in `default` and UB in `optimized` (inferred that a node has no X2 entry for itself, unverified). | `UeManager::GetMmWaveCellId()` (`:2431`) == target → `alreadyOnTarget` |
| Unknown or non-mmWave target (for example 1 = LTE, or 7) | Same X2 assert, or an undefined secondary handover to the LTE cell `(unverified)` | target ∉ this UE's measured mmWave cells → `unknownTargetCell` |
| Source UeManager in an unexpected state | `NS_FATAL_ERROR` in `PrepareHandover` (`:789-791`), even in `optimized` | partly covered by the `hoInProgress` check; residual risk |
| UE on LTE fallback | Sends McHandover to the outage cell; the path is unexplored `(unverified)` | `ueOnLteFallback` (v1 refusal) |
| Pending TTT event (auto modes) | See Q7: an assert abort | Use NoAuto, or cancel the event |

The maps the prechecks need are private (`lte-enb-rrc.h:2005-2007`, after `private:` at `:1655`): `m_mmWaveCellSetupCompleted`, `m_lastMmWaveCell`, `m_imsiUsingLte` and `m_imsiCellSinrMap`. The cleanest fix is **one additive public `LteEnbRrc` method**. It runs the guards, cancels any pending TTT event and performs the handover. It returns an outcome enum and changes nothing when unused.

This is control-path code, not a radio or scenario change. Still, the user should approve it explicitly (see section 6).

Call it **synchronously** inside the barrier, so the outcome is known for the `controlAck`. Do not use `ScheduleWithContext(1, …)`. The hard-coded context 1 (`lte-enb-net-device.cc:190`) is not the LTE eNB's node: mmWave nodes are created first (`scenario-zero.cc:447-448`; inferred).

Same-IMSI conflicts inside one window are resolved deterministically by the (nodeId, ctrlId) sort. The second control is refused with `hoInProgress` naturally, because the first sets `m_mmWaveCellSetupCompleted[imsi] = false` (`:4519`).

### Q7. Acceptance-criteria changes (M8 / R0–R3 / M9)

**Recommendation.** Confidence: **medium-high**.

**Handover policy: `--handoverMode=NoAuto` for M8 and R0–R3. Do not call `TakeUeHoControl` in NoAuto.**
- In auto modes a TTT-scheduled `PerformHandover` (`lte-enb-rrc.cc:4336-4356`; TTT 25–150 ms, `:3296-3305`) can fire after a RIC handover has changed `m_lastMmWaveCell`. It then trips `NS_ASSERT_MSG(sourceCellId == m_lastMmWaveCell)` (`:4401-4405`).
- `TakeUeHoControl` does not cancel that event (`:4469-4475`).
- `TakeUeHoControl` also removes the UE from the **outage fallback** (the `continue` at `:4690-4694` comes before the outage logic at `:4755-4790`). NoAuto keeps the fallback and only skips TTT and threshold handovers (`:4805-4808`).
- NoAuto also makes attribution exact: every handover line must match an applied control.

**M8 = R0.**
- **Config.** Use the smallest config with ≥ 2 gNBs (`--nMmWaveEnbNodes=2`; size it with probe P1), NoAuto and lock-step.
- **Interpret "≥ 2 gNBs" as:** ≥ 2 IMSIs handed over to ≥ 2 distinct target gNBs. At least one control is delivered through a **non-target** node's agent, for example the eNB agent (cellId 1), to prove any-node routing.
- **Wire evidence:**
  - a decoded RICcontrolRequest through an E2SM-RC v2.0 decoder independent of the agent's codec;
  - a decoded RICcontrolAcknowledge for each initiated control;
  - a decoded RICcontrolFailure for one deliberately invalid control (`alreadyOnTarget` or `unknownImsi`), with ns-3 still running afterwards. This is the negative test for the crash paths.
- **ns-3 evidence:**
  - the `controlAck` (initiated, appliedSeq k) in `e2-ipc-trace-N.jsonl`;
  - then `UeHandoverEndStats` / `EnbHandoverEndStats` for (IMSI, target) at a sim time after t_k (`mmwave-bearer-stats-connector.cc:195-199`);
  - and, in decoded KPM, the IMSI leaving the source gNB's Format-2 UE list and appearing in the target's;
  - no unmatched handover lines.
- **Trigger.** Scripted gRPC calls are **keyed to the step**: the harness reacts to seq k in the flushed trace (OI `e2-ipc-emitter.cc:117`, `:183-190`), never to wall time.
- **Repeat.** As in Q2: 2 live runs plus 1 replay run, with `stepTimeouts == 0`.

**R1.** Adds:
- several controls over time;
- one same-IMSI burst inside one window (to show deterministic ordering, the second refused as `hoInProgress`);
- both receiving-agent styles.

**R2/R3.** Functional criteria plus the D0 replay. Live runs are not bit-repeatable (D2). This should be stated in the acceptance text.

**M5–M7.** Unchanged, under `e2Pacing=free`. Optionally add an M6 variant under lock-step that asserts `droppedNoSub == 0`. The start barrier removes the start-up drops that depend on subscription timing (AG `main.cpp:78-85`).

**M9.** Unattended up to the highest green rung, plus 1 replay.

### Q8. Rollback and the biggest risk

**Recommendation.**
- **Stage M8.**
  1. First build the control path, the prechecks and the ack on the sim thread with `e2Pacing=free`. In this polled hybrid, controls are drained at each per-period barrier with zero wait. That gives M8 functional.
  2. Then turn the barrier on for the repeat criterion.
- **Rollback** is an attribute flip to `free`. It keeps D0 because the applied-control log is still in the trace. It loses only D1.
- **If lock-step is too slow,** switch the agent to the d=1 window policy (Q1 hybrid).
- **If ns-3 crashes on controls,** that is a precheck bug, not a pacing failure. Fix the guard; do not drop lock-step.

Confidence: **high**.

**Biggest risk.** See section 4, item 1.

## 3. Requested probes

| # | Command or method | Measures | Decision it changes |
|---|---|---|---|
| P1 | On `f7-rerun-green`, run the scenario binary directly against `tools/ipc-null-sink` with `--nMmWaveEnbNodes=2 --simTime=10`, 3 repeats, `time.monotonic()` (adapt `scripts/measure-ns3-timing.sh` in `scripts/probes/`, because its configs are fixed at `:5-8`). No rebuild. | C for the M8 config | M8 run sizing; choosing d=0 vs d=1 (if C ≲ W, d=0 roughly doubles wall time) |
| P2 | On f7, install the rc xApp (NIST script) and capture `docker0` with `ip proto 132`. Send 20 `grpcurl` calls to rc :7777 for `gnb_001_001_00000002`. Take the host send time and the agent's `rx RICcontrolRequest` log time: the agent already classifies and logs it (AG `e2ap-inbound.cpp:100`, `e2-session.cpp:166, 200`, ms UTC stamps in `agent-log.hpp`), plus the pcap timestamp. Revert. | R_p50 and R_p99, one way, gRPC → agent | W and T_step. It also shows whether e2term forwards control to a node that does not advertise function 3 (if not, P2 needs the M8 agent). |
| P2' (offline fallback) | From the M5/M6 pcaps, take the RICsubscriptionRequest → Response delta | A loose lower bound on RIC-internal latency | Only a floor for W |
| P3 | On f7, with kpimon subscribed to all 5 nodes, `SIGSTOP` ns-3 for 60 s and then 300 s, then `SIGCONT`. Check: e2mgr node states, agent stats (`subs`, `rxPdu`, `errorIndications`), kpimon, e2term and submgr logs for deletes or timeouts, and whether indications resume with no re-subscribe. | RIC reaction to long indication gaps | T_start (60 s) and continue-semantics safety. If subscriptions are deleted, the start barrier must re-check them. |
| P4 (optional) | `optimized` profile timing | Speed-up | Only if wall time blocks the gates. It also disables the asserts that catch the crash paths, so keep gates on `default`. |

## 4. Biggest risks (ranked)

1. **ns-3 aborts or hits UB on an unguarded control.**
   - The X2 asserts (`epc-x2.cc:693`, `:1352`).
   - `PrepareHandover`'s `NS_FATAL_ERROR` (`lte-enb-rrc.cc:789-791`).
   - `GetUeManager(0)` (`:3582`).
   - The TTT-race assert (`:4401-4405`).
   One bad TS decision kills a 20+ minute run. Mitigate with the prechecks (Q6), NoAuto (Q7) and a negative test in M8.
2. **Window misassignment (R > W)** silently breaks live repeatability. Mitigate by measuring R (P2) and checking `stepTimeouts` and `stepSeq`.
3. **A hang or crawl from protocol mismatch:**
   - an old agent that sends no `step` costs T per step;
   - a missing `Flush` before the wait means the agent never sees sample k.
   Mitigate with the `step(-1)` capability handshake, detach after 3, and flush-then-wait.
4. **Someone "simplifies" to an IPC thread plus `ScheduleWithContext`.** That gives a wall-dependent apply time and a race on the client. Mitigate with the single-thread rule, written into the M8 plan.
5. **R3 data starvation** if option B honours a 10 s sim period (Q5), and R3 is inherently non-repeatable (D2). Set expectations in the acceptance text.
6. **Build-profile drift.** Traces are comparable only within one profile `(unverified for floating point)`.

## 5. Unresolved questions

1. R_p99 (P2) and C for N=2 (P1): W, T_step and the M8 sizing depend on them.
2. Does e2term route a RICcontrolRequest to a node that did not advertise RAN function 3? This affects whether P2 is feasible.
3. User decision: is one additive public `LteEnbRrc` method (prechecks, TTT-event cancel, outcome enum) acceptable within M8? It is control-path code, not a radio or scenario change.
4. User decision: is "≥ 2 gNBs" read as ≥ 2 distinct targets, with ≥ 1 delivery through a non-target agent?
5. User decision: zero-delay barrier (d=0, recommended) or one-period lookahead (d=1)? And the expiry semantics: continue-and-flag (recommended) or abort in gate mode?
6. The exact E2AP `CauseRICrequest` enum names for the failure map (lens B).
7. Whether NIST's InfluxDB v2 patch to QP changes its "last N rows" query.
8. The `UeHandoverEndStats` columns (IMSI, cellId, RNTI) are assumed from the connector, not read.

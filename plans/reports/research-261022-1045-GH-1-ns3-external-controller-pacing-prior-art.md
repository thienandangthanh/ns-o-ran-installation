# Research: how prior art paces a DES (ns-3 first) against an external controller

Date 2026-10-22 (Asia/Seoul). Independent input for the pre-M8 pacing gate. I did **not** read any `plans/reports/counsel-261022*` file. Brief read: `plans/reports/brief-261022-1043-GH-1-pre-m8-pacing-counsel-input.md` §1–4 only (commit 552a58f, blob 982d94c6f182). This report gives no project recommendation. The last section is the researcher's reading, not a decision.

Local pins: `ns-o-ran-gym` @0e8ea58, `ns-3-mmwave-oran` @ace32168 (ns-3 3.38.rc1 base; `realtime-simulator-impl.cc` is byte-identical to upstream tag ns-3.38, checked with `diff`). External code was read at the commits given inline.

## 0. Outcome first

- **Every lock-step precedent I found blocks without a step-level timeout.** That covers ns3-gym, ns-O-RAN gym, ns3-ai, helics-ns3, SUMO TraCI and FMI `doStep`. Where a timeout exists, it is a liveness or diagnostic check and never a "skip the step and continue" rule. ns-O-RAN gym re-checks whether the process is alive and then waits again. HELICS `grant_timeout` triggers diagnostics. HLA Evolved has "federate lost", which auto-resigns the lost federate.
- **Continuing past a late peer is documented as giving up determinism.** HELICS says this directly: a forced grant "can lead to non-deterministic behavior". Fujimoto's condition for repeatability is that each external input gets the same timestamp in every run.
- **The ns-O-RAN line has never paced ns-3 against a live RIC.** Online mode lets ns-3 run free and rebases the E2 timestamps (Unix-ms baseline + sim time); xApps "shall use the timestamp". Lock-step exists only in the gym file mode, where a Python agent replaces the RIC: two named POSIX semaphores, one step per E2 period, and no timeout on the ns-3 side.
- **Colosseum avoids pacing by being real time.** Real SDRs and srsRAN run against an FPGA channel emulator that loads new taps every 1 ms. Anything slower than real time (ray tracing) is computed offline and replayed. Its repeatability claim is statistical (tight 95 % CIs), not bit-exact.
- **ns-3 `RealtimeSimulatorImpl` offers no pacing for a simulator slower than real time.** BestEffort lets the simulation fall behind the wall clock, which makes it effectively free-running. HardLimit `NS_FATAL_ERROR`s once jitter exceeds `HardLimit` (default 0.1 s).
- **In the found precedents the controller adds no sim-time latency.** ns3-gym and ns-O-RAN gym both apply the action at the current sim instant (`ExecuteActions` inline; `Schedule(Seconds(0))`).
- **No O-RAN digital-twin source paces a slower-than-real-time simulator against a live near-RT RIC.** OpenTwin (preprint) runs ns-O-RAN in offline "segments" outside the per-action loop. AODT is stepped by the client and has no RIC or E2 interface in the docs I read.

## 1. ns-O-RAN (online mode) and ns-o-ran-gym (file mode)

Sources: Lacava et al., "ns-O-RAN: Simulating O-RAN 5G Systems in ns-3", WNS3 2023, DOI [10.1145/3592149.3592161](https://doi.org/10.1145/3592149.3592161), arXiv [2305.06906](https://arxiv.org/abs/2305.06906). Lacava, Pietrosanti, Polese, Cuomo, Melodia, "Enabling Online Reinforcement Learning Training for Open RAN", IFIP Networking 2024, pp. 577–582, DOI [10.23919/IFIPNetworking62109.2024.10619796](https://doi.org/10.23919/IFIPNetworking62109.2024.10619796) (full text from NSF PAR, [par.nsf.gov/servlets/purl/10543773](https://par.nsf.gov/servlets/purl/10543773)). Lacava et al., "Programmable and Customized Intelligence for Traffic Steering in 5G Networks Using Open RAN Architectures", IEEE TMC 23(4) 2024, DOI [10.1109/TMC.2023.3266642](https://doi.org/10.1109/TMC.2023.3266642), arXiv [2209.14171](https://arxiv.org/abs/2209.14171). I verified all three titles via Crossref. I found no arXiv copy of the IFIP paper. The ES demo (Bordin et al., CCNC 2025, arXiv [2601.02240](https://arxiv.org/abs/2601.02240)) adds nothing on pacing.

**Online mode (ns-3 ↔ real RIC)**
- **Clock master:** none. ns-3 runs free. ns-O-RAN paper §3: ns-3 "can execute faster or slower than the wall clock time … at the beginning of the simulation ns-3 stores the current Unix time in milliseconds and uses it as the baseline timestamp. Whenever an E2 message is sent … ns-3 will sum the simulation time elapsed and the baseline timestamp … The xApps … shall use the timestamp provided by these messages to follow the simulation". The TMC paper §3 says the same.
- **Step:** none.
- **Blocking:** none. E2 runs in per-node threads inside ns-3 ("multiple threads in ns-3 to establish independent SCTP connections for each E2 link", ns-O-RAN §3).
- **Expiry:** not applicable.
- **Determinism:** the paper calls the loop "controlled and reproducible" (§4) but gives no run-to-run evidence. Upstream scenario-zero sets no `RealtimeSimulatorImpl` (local grep finds no `SimulatorImplementationType` in `scratch/`).
- **Failure modes:** the authors themselves name the time gap with the wall-clock RIC. Wall-clock RIC timers and sim time diverge by the slowdown factor (my inference).

**File mode plus gym (ns-3 ↔ Python agent; no RIC, no E2)**
- **Clock master:** ns-3 owns sim time. The Python agent grants each step.
- **Step:** one E2 period. The first `ReadControlFile` is scheduled at `E2Periodicity + 5 ms` (`lte-enb-net-device.cc:1032-1034`) and then every `E2Periodicity` (`:347`; default 0.1 s, `:567-571`). The paper confirms: "The periodicity of the KPMs generation coincides with the E2 SM KPM Indication Message Periodicity".
- **Where it blocks:**
  - ns-3, single-threaded. `ReadControlFile` posts `/sem_metrics_<dir>` (`:110-121`), then calls `sem_wait` on `/sem_control_<dir>` (`:123-133`) with no timeout. The whole simulator freezes in both sim time and wall time.
  - Python. `step()` writes the CSV, calls `controlSemaphore.release()` (`ns_env.py:371-373`), then `_wait_data_availability()` (`:375`).
  - Scope: one sync point per simulation. It lives only on the `LteEnbNetDevice` (LTE eNB) and only in the file-logging branch (`else` of `if (!m_forceE2FileLogging)`, `:936`/`:952`; semaphores created with `O_CREAT` at `:980-1025`). The NIST IPC branch (`:936-949`) never reaches it.
- **Timeout and expiry:**
  - Python. `metricsReadySemaphore.acquire(timeout=…)` catches `BusyError` and calls `is_simulation_over()`. If ns-3 is still alive it waits again (`ns_env.py:354-362`). Expiry therefore means freeze and keep waiting, never continue or drop. The default is `timeout=10` and `reset()` uses `timeout=5` (`:345`). The paper says "a 10-second window".
  - ns-3. No timeout (`sem_wait`, `:127`). If the semaphore is missing, ns-3 aborts (`NS_ABORT_MSG_IF … SEM_FAILED`, `:111`, `:124`).
- **When the action applies:** at the current sim instant. TS: `TakeUeHoControl`, then `ScheduleWithContext(1, Seconds(0), PerformHandoverToTargetCell…)` (`:189-195`). The CSV timestamp is parsed but not used for TS (`:163`; comment "TODO adapt to the scheduling"). With `ScheduleControlMessages=false` the file is truncated after each read (`:329-338`).
- **Determinism:** the paper states that ns-3 "was not designed to accept external inputs to ensure the reproducibility of each single simulation upon the same random seed. This restriction does not apply to DRL since the reproducibility … is based on a statistical evaluation". It gives no bit-exact evidence. The paper's timing study measures only overhead: ms of gym overhead against minutes of simulation (Fig. 4).
- **Failure modes:** read from code; none of these are reported.
  - An agent crash leaves ns-3 blocked forever.
  - A hung but alive ns-3 makes Python loop forever.
  - `close()` releases the metrics semaphore and calls `kill()` before `unlink()` (`:466-474`). Named semaphores outlive a `kill -9` of Python (POSIX semantics, (unverified) here).
  - The semaphore name is derived from the cwd basename (`:985-997`), so two runs in same-named directories collide.

## 2. ns3-gym (Gawłowicz & Zubow; the task's "Gawłowski and Gawłowski" is a misattribution)

Sources: P. Gawłowicz and A. Zubow, "ns-3 meets OpenAI Gym: The Playground for Machine Learning in Networking Research", MSWiM 2019, DOI [10.1145/3345768.3355908](https://doi.org/10.1145/3345768.3355908) (Crossref-verified). The arXiv version is titled "ns3-gym: Extending OpenAI Gym for Networking Research", [1810.03943](https://arxiv.org/abs/1810.03943). Code: [tkn-tub/ns3-gym @cfff7f3](https://github.com/tkn-tub/ns3-gym/tree/cfff7f3217b7da2c263c717a4540d6adf189eeb1) (branch `app-ns-3.36+`, the default).

- **Clock master:** the ns-3 script. Python only replies.
- **Step:**
  - Defined in the paper: "the step … can be executed every predefined time-interval (time-based step), e.g. every 100 ms, or fired by an occurrence of specific event (event-based step)".
  - Time-based example: `ScheduleNextStateRead` re-schedules itself at `Seconds(envStepTime)` and calls `NotifyCurrentState()` (`examples/opengym/sim.cc:128-131`). `envStepTime = 0.1` is hard-coded (`:140`).
  - The Python `Ns3Env(stepTime=…)` is passed to `initialize_env(stepInterval)` and never used (`model/ns3gym/ns3gym/ns3env.py:150`, `:396`). Step time is owned by ns-3 alone.
- **Where it blocks:**
  - ns-3 is the ZMQ **REQ** client (`model/opengym_interface.cc:81`). `NotifyCurrentState()` sends the state (`:259`), then calls blocking `recv` (`:264`), then `ExecuteActions` runs inline (`:284`). The simulator thread is frozen for the agent's whole compute time.
  - Python is **REP** (`ns3env.py:40`). `step()` = `send_actions` then `rx_env_state` → `socket.recv()` (`:227-229`, `:180`).
- **Timeout:**
  - None on either side. No `RCVTIMEO` or `LINGER` appears in either file.
  - Expiry = hang. Issue [#25](https://github.com/tkn-tub/ns3-gym/issues/25) (open): "sometimes the code will get stuck at env.step(action)". A user workaround sets `self.socket.RCVTIMEO = 100000` to surface ns-3 crashes.
  - Issue [#53](https://github.com/tkn-tub/ns3-gym/issues/53) (open): `ZMQError: Operation cannot be accomplished in current state` around game-over. This is a REQ/REP lock-step state-machine error.
  - Stop request: `Simulator::Stop(); Simulator::Destroy(); std::exit(0)` (`opengym_interface.cc:273-278`).
- **Determinism:** the seed goes to `RngSeedManager::SetRun(simSeed)` (`sim.cc:160-161`). When `simSeed==0` Python picks a random seed (`ns3env.py:59-62`). There is no repeatability claim or evidence. Action latency is zero sim time (inline `ExecuteActions`).
- **Failure modes:** permanent block on peer death (#25); REQ/REP state errors (#53); a step-time parameter that suggests Python control but has none.

**Adjacent (secondary, same pattern).** ns3-ai, Yin et al., WNS3 2020, DOI [10.1145/3389400.3389404](https://doi.org/10.1145/3389400.3389404). The code at [hust-diangroup/ns3-ai @b8c9858](https://github.com/hust-diangroup/ns3-ai/tree/b8c9858294b1d6a7f122b5154a3ce25057a54740) uses shared memory with a busy-spin `sem_wait` (`model/msg-interface/ns3-ai-semaphore.h:65-77`, `do { … } while (true)`). It is lock-step with no timeout and burns a core while waiting.

## 3. Colosseum (real-time HIL) and its near-RT RIC

Sources:
- Bonati et al., "Colosseum: Large-Scale Wireless Experimentation Through Hardware-in-the-Loop Network Emulation", DySPAN 2021, DOI [10.1109/DySPAN53946.2021.9677430](https://doi.org/10.1109/DySPAN53946.2021.9677430), arXiv [2110.10617](https://arxiv.org/abs/2110.10617).
- Villa et al., "Colosseum as a Digital Twin: Bridging Real-World Experimentation and Wireless Network Emulation", IEEE TMC 2024, DOI [10.1109/TMC.2024.3359596](https://doi.org/10.1109/TMC.2024.3359596), arXiv [2303.17063](https://arxiv.org/abs/2303.17063).
- Polese et al., "ColO-RAN: Developing ML-based xApps for Open RAN Closed-loop Control on Programmable Experimental Platforms", IEEE TMC, DOI [10.1109/TMC.2022.3188013](https://doi.org/10.1109/TMC.2022.3188013), arXiv [2112.09559](https://arxiv.org/abs/2112.09559).
- SCOPE: Bonati et al., MobiSys 2021, DOI [10.1145/3458864.3466863](https://doi.org/10.1145/3458864.3466863). Crossref-verified; I did not read the full text, and the SCOPE claims below come from ColO-RAN.
- Colosseum RIC code: local `colosseum-near-rt-ric/` @e3161c1 (README: "minimal version of the O-RAN Software Community near-real-time RIC (Bronze release)").

- **Clock master:** the wall clock, with hardware in the loop. "SRNs … are synchronized in time and frequency through hierarchical OctoClock clock distributors" (DySPAN §II).
- **Step:** none in the control loop.
  - Channel emulation: MCHEM FPGAs apply "512 pre-computed complex-valued taps" by FIR convolution (DySPAN §II).
  - "Every millisecond, the RF Scenario Server loads different pre-defined channel taps into the Colosseum FPGAs" (Colosseum-as-DT §3).
- **How pacing is avoided:**
  - Everything in the loop runs at line rate. Base stations run SCOPE (srsRAN-based) and talk to the near-RT RIC over E2 in real time; ColO-RAN calls these "data-driven real-time control loops between the base stations and the xApps" (§3).
  - The slower-than-real-time part is moved offline: "RF scenarios are currently generated offline, and then replayed in real-time by the scenario server" (Polese et al., "Colosseum: The Open RAN Digital Twin", IEEE OJ-COMS 2024, DOI [10.1109/OJCOMS.2024.3447472](https://doi.org/10.1109/OJCOMS.2024.3447472), arXiv [2404.17317](https://arxiv.org/abs/2404.17317), §IV-A).
- **Blocking and expiry:** none; the RIC and the RAN are both real-time systems (no source states a timeout policy).
- **Determinism:** statistical only. The RF scenarios enable "reproducibility and repeatability of experiments at scale" (DySPAN §III), and the evidence is "tight 95% confidence intervals … This confirms the reliability and repeatability of Colosseum emulation" (DySPAN §V). No bit-exact claim.
- **Failure modes:**
  - Precomputed scenarios cannot react to the live state; the OJ-COMS §IV-B "Roadmap Toward Real-Time Twinning" says replay "is not suitable for those cases in which the channel … need[s] to dynamically change in real-time".
  - DySPAN footnote 3 notes that "only 4 channel taps are non-zero-valued" because of compute and storage cost.
  - ns-O-RAN runs on Colosseum too (OJ-COMS §III) but keeps its unpaced online mode (§1 above).

## 4. Co-simulation time synchronization

### 4a. Conservative and optimistic PDES

- **Conservative (Chandy–Misra–Bryant).** Chandy & Misra, IEEE TSE 1979, DOI [10.1109/TSE.1979.230182](https://doi.org/10.1109/TSE.1979.230182). Chandy & Misra, CACM 1981, DOI [10.1145/358598.358613](https://doi.org/10.1145/358598.358613). Bryant 1977 MIT tech report (unverified; not located). Survey: Fujimoto, CACM 1990, DOI [10.1145/84537.84545](https://doi.org/10.1145/84537.84545).
  - Clock master: none central. Each LP advances only to a safe time bounded by its inputs plus lookahead.
  - Blocking: an LP waits until no earlier message can arrive. Null messages carry lower-bound promises.
  - Failure modes: deadlock without null messages; zero lookahead kills concurrency. These are textbook statements; I read them in ns-3's distributed doc and Fujimoto's slides, not in the 1979/1981 originals (unverified).
- **ns-3 implements both conservative variants.** `src/mpi/doc/distributed.rst:35-49`: "two conservative synchronization algorithm with lookahead are used in ns-3". `DistributedSimulatorImpl` is "globally synchronized … MPI collective operation"; `NullMessageSimulatorImpl` uses "local communication and null messages". Docs: [nsnam distributed](https://www.nsnam.org/docs/models/html/distributed.html).
- **Optimistic (Time Warp).** Jefferson, "Virtual Time", ACM TOPLAS 7(3) 1985, DOI [10.1145/3916.3988](https://doi.org/10.1145/3916.3988).
  - It speculates and rolls back with antimessages. "GVT can thus be viewed as a moving commitment horizon: any event with virtual time less than GVT cannot be rolled back, and may be irrevocably committed with safety" (§4).
  - Irreversible output ("dispense money, launch missile") is the stated complication (§3).
  - Implication from the source: an external real system (a RIC that has already acted) cannot be rolled back, so optimistic sync needs output held until commit.

### 4b. HLA (IEEE 1516) time management

Sources: Fujimoto, "Time Management in the High Level Architecture", SIMULATION 71(6) 1998, DOI [10.1177/003754979807100604](https://doi.org/10.1177/003754979807100604) (Crossref-verified; full text not read). Fujimoto's HLA TM slides, [sigsim.acm.org](https://sigsim.acm.org/conf/mskr/Courseware/Fujimoto/Slides/FujimotoSlides-21-HLATimeManagement.pdf). Fujimoto, "Zero Lookahead and Repeatability in the HLA", [Georgia Tech PADS](https://sites.cc.gatech.edu/computing/pads/PAPERS/Zero_Lookahead_and_Repeatability.pdf). Möller et al. (Pitch), "Developing Fault Tolerant Federations using HLA Evolved", 05S-SIW-048, [pdf](https://onearc.com/wp-content/uploads/2023/06/05S-SIW-048.pdf). I did not read the IEEE 1516.1 standard text.

- **Clock master:** the RTI grants time; "logical time only advances when that federate explicitly requests an advance".
- **Step:** Time Advance Request TAR(T) for time-stepped federates, Next Message Request for event-stepped ones. The RTI "invokes Time Advance Grant (T) when it can guarantee all TSO messages with time stamp ≤ T have been delivered". "Grant time always matches the requested time" (slides p. 9).
- **Lookahead:** "any TSO message sent by the federate must have a time stamp ≥ the federate's current time + L" (slides p. 15).
- **Wall clock:** "Federates responsible for pacing logical time advances with wallclock time in real-time executions" (slides p. 8).
- **Non-time-aware federates:** "Neither time constrained nor regulating (e.g., DIS-style training …)" (slides p. 6).
- **Blocking:** the federate waits for TAG.
- **Expiry:** there is no TAR timeout in the TM services I read. HLA Evolved adds "Federate Lost". The RTI then "do[es] a resign on behalf of the lost federate … all federation-wide synchronized operations like time-management are recovered. If for example all federates are waiting for a specific federate to advance time and that federate has crashed this would otherwise have prevented the entire federation from advancing" (SIW-048 §2.4). Detection is by socket close or polling, which "may not be 100% accurate under varying load and latency conditions" (§2.5). The response is to drop the federate, not to skip the step.
- **Determinism:** "external inputs can be applied in a repeatable fashion by ensuring the same time stamp is assigned to each external input in subsequent executions". Simultaneous events must be "processed in the same order on each execution". "Reading the real-time clock" is a named non-repeatable operation (Zero-Lookahead paper §1).
- **Failure modes:** a hung federate stalls the federation (SIW-048 §1.2, Level 5: "a federate hangs or gets stuck in debugger"); zero lookahead complicates repeatability.

### 4c. FMI co-simulation `doStep`

Source: FMI 3.0.1 spec, [fmi-standard.org/docs/3.0.1](https://fmi-standard.org/docs/3.0.1/#fmi3DoStep).

- **Clock master:** the importer (master).
- **Step:** "The importer requests the computation of the next time step"; "Only fmi3DoStep can change the time of a Co-Simulation FMU from the outside"; "The FMU is expected to compute until time t_{i+1} = t_i + h_i".
- **Blocking:** `doStep` is a synchronous call. FMI 3.0 removed the FMI 2.0 asynchronous mode because "this mode was not supported by tools and it can be suitably replaced by Co-Simulation implementations that control the asynchronous computation of FMUs via separate processes/threads" (§1.1).
- **Expiry:** the spec has no timeout. The FMU may return `earlyReturn` with `lastSuccessfulTime`. `fmi3Discard` means "the FMU is in the same state as before the call … but the computation may continue"; `fmi3Error` means "the simulation must not be continued".
- **Real time:** Scheduled Execution only; "a violation of a timing constraint usually results in an overrun exception".
- **Determinism:** no explicit claim. The `currentCommunicationPoint` plus step-size design avoids "accumulation of numerical errors".

### 4d. mosaik

Source: [OFFIS-mosaik/mosaik @3.7.1](https://github.com/OFFIS-mosaik/mosaik/tree/3.7.1) (bb90698); docs [scheduler](https://mosaik.readthedocs.io/en/latest/scheduler.html).

- **Clock master:** the mosaik scheduler. A simulator's `step(time, inputs, max_advance)` returns its next step time. `max_advance` is "the simulation time until the simulator can safely advance it's internal time without causing any causality errors" (`mosaik/scheduler.py:338-339`).
- **Blocking:** `await wait_for_dependencies(…)`, then `await sim.step(…)` with no timeout (`scheduler.py:108`, `:345`). `start_timeout`/`stop_timeout` cover only process start and stop (`async_scenario.py:94-95`, `:235-236`).
- **Real-time mode:** `rt_factor` sleeps when the simulator is ahead (`scheduler.py:182-191`). When behind, `rt_check` raises `RuntimeError("Simulation too slow for real-time factor …")` if `rt_strict`, otherwise it warns (`:365-382`). Docs: "If the simulators are too slow … mosaik will only print a warning by default" (`async_scenario.py:1008-1011`). The docs also warn that "*max_advance* is not necessarily appropriate for real-time simulations" (`docs/scheduler.rst:209`).
- **Determinism:** no explicit claim found.

### 4e. ns-3 `RealtimeSimulatorImpl`

Sources: [ns-3 manual: RealTime](https://www.nsnam.org/docs/manual/html/realtime.html) (local `ns-3-mmwave-oran/doc/manual/source/realtime.rst`). Source [ns-3.38 realtime-simulator-impl.cc](https://gitlab.com/nsnam/ns-3-dev/-/blob/ns-3.38/src/core/model/realtime-simulator-impl.cc), identical to the local file.

- **Clock master:** the wall clock. Between events "the simulator sleeps until that realtime is reached"; it uses sleep plus busy-wait (`realtime.rst:21-29`, `:69-87`).
- **Step:** none; pacing is per event.
- **Modes:**
  - `SynchronizationMode` is "What to do if the simulation cannot keep up with real time", BestEffort (default) or HardLimit (`realtime-simulator-impl.cc:61-66`). `HardLimit` defaults to `Seconds(0.1)`, "Maximum acceptable real-time jitter" (`:67-72`).
  - BestEffort: "the simulator will just try to catch up to realtime by executing events until it reaches a point where the next event is in the (realtime) future … it is possible for the simulation to consume more time than the wall clock time" (`realtime.rst:37-41`).
  - HardLimit: on each event, if `|now_real − ts| > m_hardLimit`, it calls `NS_FATAL_ERROR("… Hard real-time limit exceeded (jitter = …)")` (`:362-382`; the code comment says "commit ritual suicide"). That means abort, not continue or freeze.
- **Thread-safe injection:** `ScheduleRealtime*` / `ScheduleRealtimeNow*` (`realtime-simulator-impl.h:112-132`; a mutex guards the event list, e.g. `.cc:148`, `:317`). In-tree usage: `src/lte/examples/lena-simple-epc-emu.cc:67-71` (HardLimit, emulation).
- **Determinism:** none claimed. Event times depend on wall time when input is injected (my inference).

### 4f. Network-simulator co-simulation with lock-step

- **HELICS plus helics-ns3.** Docs: [HELICS v3.7.0 config reference](https://github.com/GMLC-TDC/HELICS/blob/v3.7.0/docs/references/configuration_options_reference.md). Code: [GMLC-TDC/helics-ns3 @264dfb9](https://github.com/GMLC-TDC/helics-ns3/tree/264dfb9acfbcda6b9f8bae2c335ada3de3a0e689).
  - helics-ns3 replaces the ns-3 `SimulatorImpl`. It processes events only while `nextTime <= grantedTime`, then blocks in `helics_federate->requestTime(Next())` (`model/helics-simulator-impl.cc:222-285`, `:267`). The broker grants time: conservative lock-step inside ns-3 itself.
  - Timeouts: `--grant_timeout` is "Time in ms to wait to allow a time request to wait before triggering diagnostic actions" (cfg ref L339). `--tick` is a heartbeat; after 2 missed ticks "secondary actions" run (L333). `--max_cosim_duration` terminates the co-simulation (L340). `--error_timeout` (L337).
  - Real time: `real_time` with `rt_lag`/`rt_lead` (default 0.2 s). "If the federate is running slower than real time this will cause a force grant, which can lead to non-deterministic behavior. `rt_lag` can be set to maxVal to disable force grant" (L710-711). `uninterruptible` and `period` make grants occur only at `n*period` (L618, L632).
- **SUMO TraCI (used by Veins).** Docs: [TraCI](https://sumo.dlr.de/docs/TraCI/index.html). Paper: Sommer, German, Dressler, IEEE TMC 2011, DOI [10.1109/TMC.2010.133](https://doi.org/10.1109/TMC.2010.133) (Crossref-verified; not read).
  - SUMO "waits for all external applications to connect". "The simulation does not advance to the next step until all clients have called the 'simulationStep' command".
  - Multiple clients need `SetOrder`: "client commands will be handled in the order from the lowest to the highest value within each simulation step".
  - No timeout is documented.
- **Non-network precedents (secondary; documentation only).**
  - [CARLA synchronous mode](https://carla.readthedocs.io/en/latest/adv_synchrony_timestep/): "the server waits for a client tick". Determinism requires sync mode plus a fixed delta; "only one client should tick".
  - [PX4](https://docs.px4.io/main/en/simulation/): SITL and the simulator "run in lockstep … makes it possible to run the simulation at different speeds, and also pause".
- **Not found:** a peer-reviewed network co-simulation paper that specifies "lock-step with per-step timeout, then continue". The closest are the HELICS `grant_timeout` (diagnostic only) and the HELICS rt force grant (continue, documented as non-deterministic).

## 5. Digital-twin pacing

- **Colosseum DT and CaST** (§3). Real-time replay of offline-generated taps at 1 ms granularity (arXiv 2303.17063 §3: "for each discrete time instant t spaced at least 1 ms"). The clock master is the wall clock. This is the only primary source I found that runs an O-RAN DT in real time with a live RIC.
- **OpenTwin.** Zhang et al., arXiv [2605.24662](https://arxiv.org/abs/2605.24662) (2026 preprint; not peer-reviewed; low maturity).
  - The backbone simulator is ns-O-RAN-flexRIC ([Orange-OpenSource/ns-O-RAN-flexric](https://github.com/Orange-OpenSource/ns-O-RAN-flexric)).
  - "The DT advances in segments, where a segment denotes one block of simulated time that the backbone simulator executes without pausing and that carries at most one applied control action".
  - Running the DT forward costs "approximately 123 s per eight-second closed-loop segment … it runs only on resynchronization rather than inside the per-action loop".
  - The paper fits RTF (wall-clock s per simulated s) = K·T·cells^1.19·UEs^0.95 (R² 0.949).
  - Pacing, as I read it: the slow simulator stays out of the real-time loop and runs in batches between resyncs. There is no lock-step and no timeout.
- **TwinRAN.** arXiv [2407.13340](https://arxiv.org/abs/2407.13340) (IEEE ©2025). It is a FlexRIC-based twin; copies are "connected to an NS-3 simulation to test what-if scenarios" (§VI). No pacing mechanism is described in the text I grepped.
- **NVIDIA AODT.** [v1.5.1 Interactive Mode](https://docs.nvidia.com/aerial/aodt/v-1-5-1/dynamic-mode.md): the client script "drive[s] an EM simulation step-by-step" with explicit `SlotIndex`/`TimeStepIndex` requests. [v1.1 RAN DT](https://docs.nvidia.com/aerial/archive/aerial-dt/1.1/text/ran_digital_twin.html) adds batches, slots and samples, plus "simulation mode 3" online ML that passes state "at every simulation time step to Python through bindings". The clock master is the client or the batch config. No wall-clock coupling, RIC or E2 interface is stated in the pages read, and I found no pacing statement for an external RIC. That is a primary source for "client-stepped", but none exists for RIC pacing.
- **Digital Twin for O-RAN Towards 6G** (arXiv [2410.02954](https://arxiv.org/abs/2410.02954), IEEE ComMag): grep found no pacing mechanism (vision paper).

## 6. Comparison table

| System | Clock master | Step | Blocks where | Timeout / expiry | Determinism claim / evidence | Known failure modes | Source type |
|---|---|---|---|---|---|---|---|
| ns-O-RAN online | none (free-run DES) | none | nowhere | n/a | "reproducible" (prose); none | sim/RIC wall-time gap | paper + code |
| ns-O-RAN gym (file) | ns-3 sim time, agent grants | 1 E2 period (0.1 s), +5 ms offset | ns-3 `sem_wait`; Py `acquire(timeout)` | ns-3: none (freeze). Py: liveness re-check, then re-wait (freeze) | per-run explicitly not targeted; statistical | infinite block on peer death; name collision; zero-latency action | paper + code |
| ns3-gym | ns-3 script | `envStepTime` (ns-3) or event | ns-3 ZMQ REQ `recv`; Py REP `recv` | none; hang (#25) | seed via `SetRun`; none | hang, REQ/REP state error (#53) | paper + code + issues |
| ns3-ai | ns-3 | user-defined | shm spin-wait | none | none | CPU burn, hang | paper + code |
| Colosseum + RIC | wall clock (HW) | none (1 ms tap updates) | n/a | n/a | statistical (95 % CI) | offline scenarios not reactive | papers |
| Conservative PDES | per-LP safe time | event/lookahead | LP waits on inputs | none (null msgs avoid deadlock) | deterministic if TS order + tie rule | deadlock, low lookahead | papers + ns-3 docs |
| Time Warp | none (speculative) | event | none (rollback) | n/a | commit below GVT | irreversible external output | paper |
| HLA TM | RTI grants | TAR/NMR → TAG | federate awaits TAG | none in TM; Evolved: lost federate auto-resigned | repeatable if same TS on external inputs + tie order | hung federate stalls federation | papers + slides |
| FMI 3 CS | importer | `doStep(t,h)` | synchronous call | none; `earlyReturn`/`Discard`/`Error` | none explicit | n/a | spec |
| mosaik | scheduler | `step()` returns next t | `await sim.step` | none on step; rt: warn or `RuntimeError` | none explicit | too slow for `rt_factor` | code + docs |
| ns-3 RT BestEffort | wall clock | per event | sleep/busy-wait | runs late (free-run when slow) | none | drift unbounded | docs + code |
| ns-3 RT HardLimit | wall clock | per event | sleep/busy-wait | jitter > 0.1 s → `NS_FATAL_ERROR` (abort) | none | abort | docs + code |
| HELICS / helics-ns3 | broker grants | `requestTime(next)` | ns-3 in `requestTime` | `grant_timeout` → diagnostics; rt force grant → continue (non-deterministic) | deterministic unless force grant | stalls, force grants | docs + code |
| SUMO TraCI | clients collectively | `simulationStep` | SUMO waits for all clients | none documented | ordering via `SetOrder` | n/a (not documented) | docs |
| OpenTwin | DT orchestrator | sim "segment" | offline, outside action loop | n/a | seeded runs | RTF ≫ 1 | preprint |
| AODT | client / batch config | slot / time step | client call | none stated | seeded mobility option | none stated | docs |

## 7. Implications for an ns-3 ↔ RIC lock-step design (researcher's reading, not a decision)

1. **A timeout that fires breaks the repeatability guarantee in every framework surveyed.** Prior art treats a per-step timeout T as either a liveness alarm or an explicitly non-deterministic forced advance (HELICS). A design that continues after T is repeatable only for runs in which T never fired. That makes "did T fire (count, step ids)" a natural run-level fact to record.
2. **The RIC is a non-time-aware peer.** In HLA terms it is "neither constrained nor regulating": no xApp sends a per-period "done" or no-op over E2. All found precedents (gym, ns3-gym, TraCI, HLA, FMI) need an explicit reply each step. Step completion with a RIC must therefore be inferred, from a control message or a quiet window. A quiet window is a timeout by construction.
3. **Repeatability hinges on when the control lands in sim time.** Fujimoto's condition is the same timestamp for each external input in every run. Both ns-3 gyms apply actions at the current sim instant (zero sim latency). With a real RIC, applying at wall-clock arrival would tie sim effects to RIC latency. Applying at a sim-defined point (e.g. next step boundary) matches the precedent.
4. **Five agents give a fan-in barrier.** SUMO's rule is "does not advance until all clients have called simulationStep", plus `SetOrder` for deterministic per-step ordering. CARLA says "only one client should tick". Fujimoto requires simultaneous events in the same order. With several RC requests in one step, a fixed tie order (e.g. by node/IMSI) is the cited remedy.
5. **Real time is not reachable by ns-3 pacing alone at 1.7× to 32× slowdown.** This is arithmetic from the brief's §2 numbers and my inference. HardLimit (0.1 s) would be exceeded after about 0.15 s sim at 1.685× (lag 0.685 s per sim s) and after about 3 ms sim at 31.96×. BestEffort at those rates equals free-run. Every precedent that is real time with a live RIC either runs real hardware (Colosseum) or does not pace and rebases timestamps instead (ns-O-RAN online).
6. **The step size precedent is one E2 report period.** ns-O-RAN gym uses `E2Periodicity`; the ns3-gym example uses 0.1 s. That is about 0.17 s wall per step at 1 gNB and about 3.2 s at the default config, before RIC RTT. RIC RTT is unmeasured (brief §2).
7. **Wall-clock E2 liveness keeps running while sim time is paused.** That holds for all lock-step designs with a wall-clock peer. The HLA Evolved "federate lost" precedent drops the peer; it does not pause it. None of the sources discuss E2/RIC procedure timers under a paused simulator. This gap is not covered by prior art.
8. **No surveyed network source provides bit-exact run-to-run evidence.** Colosseum is statistical; ns-O-RAN gym disclaims per-run reproducibility. A repeatability claim for this gate would need its own evidence, such as identical ns-3 trace digests across runs (my inference).
9. **Known failure modes are worth designing against** (taken from the cited issues and code): permanent block on peer death (ns3-gym #25; ns-O-RAN `sem_wait`), protocol state desync (#53), a timeout misread as end-of-sim (gym `BusyError` path), resource names that collide across runs (`/sem_*_<dir>`), and busy-wait CPU burn (ns3-ai).

## 8. Source credibility and adoption risk

- **High.** The ns-3 manual and source (in-tree, identical to tag 3.38), FMI 3.0.1 spec, HELICS docs at tag v3.7.0, mosaik at tag 3.7.1, and peer-reviewed DES classics (DOIs verified).
- **Medium-high.** ns-O-RAN, IFIP gym, ns3-gym and Colosseum papers (peer-reviewed, by the codebase authors). Their pacing claims match the code at the pins.
- **Medium.** The SIW-048 conference paper (industry RTI vendor), the SUMO, CARLA and PX4 docs (current `latest`, not pinned), and the AODT docs (vendor; v1.1 is archived).
- **Low.** OpenTwin (2026 arXiv preprint). TwinRAN (accepted IEEE, but pacing not described).
- **Adoption signals:** ns3-gym has open, unanswered hang issues (#25, #53); maintenance is active (pushed 2026-02). helics-ns3 is active (pushed 2025-11). ns-o-ran-gym pin 0e8ea58 is from 2025-04.

## 9. Limitations

- I did not read the IEEE 1516.1 standard text, the Chandy–Misra/Bryant originals, the full Fujimoto 1998 paper or the full SCOPE paper. Claims about them rest on Fujimoto's slides and papers, the ns-3 docs and Crossref metadata.
- Nothing was run (no builds, no VM). All code claims come from static reading at the stated commits. The ns-O-RAN gym failure modes are inferred from code, not reproduced.
- I did not survey OMNeT++-native co-simulation, OAI rfsimulator time coupling, the VIAVI or Keysight RIC testers, or ns-3 5G-LENA/FlexRIC timing beyond a README grep. Any of these could hold a "lock-step with timeout" precedent.
- The OpenRAN Gym Computer Networks paper (DOI [10.1016/j.comnet.2022.109502](https://doi.org/10.1016/j.comnet.2022.109502)) did not extract from arXiv 2207.12362, so it was not read.

## Unresolved questions

1. Does any O-RAN RIC test product (VIAVI TeraVM RIC Test, Keysight RICtest) or OAI rfsim + FlexRIC setup pace a slower-than-real-time RAN model against a live RIC? I found no primary source.
2. Is ns-O-RAN gym repeatable bit for bit under a fixed action sequence and seed? The design suggests yes (zero-latency actions at fixed sim instants), but there is no published evidence.
3. HLA 1516.1-2010: does the standard itself (not the vendor paper) define any timeout on TAR/TAG? It was not verified.
4. Should the gym paper's "10-second window" or the code's 5 s/10 s split (`reset` vs `step`) be treated as the reference behaviour? The code is authoritative at the pin; the paper may describe an older version.

Status: DONE
Summary: Cited prior art across all 5 areas, with code-level file:line evidence at pinned commits. The common finding is lock-step that blocks without a step timeout; timeouts are liveness or diagnostic only, and continuing past a late peer is documented as non-deterministic (HELICS).
Concerns/Blockers: The task named the ns3-gym authors "Gawłowski and Gawłowski"; they are Gawłowicz and Zubow. Digital-twin pacing has no primary source that covers a live RIC, apart from the Colosseum real-time replay and the OpenTwin preprint.

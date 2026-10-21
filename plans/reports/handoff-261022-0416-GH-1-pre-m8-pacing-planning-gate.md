# Handoff: pre-M8 pacing planning gate (M0–M7 done, M8 not started)

Date: 2026-10-22. Plan: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/`. Contract: `plans/reports/brainstorm-261017-0308-GH-1-ns-oran-l-release-nist-1-8-0-contract.md`, section "User answers — pacing".

**Status.** M0–M7 are green in the dev run, and every gate is backed by decoded wire evidence. The unattended re-run from `fresh-install` (P8) is reported in section 6.

The contract imposes a hard stop before M8. **M8 (RC), the closed-loop ladder R0–R3 and M9 have not started, and they must not start until the steps in section 5 are done and the user approves the pacing plan.**

## 1. Measurements the pacing decision needs

**ns-3 speed** (M4, `plans/reports/timing-261022-0217-GH-1-ns3-scenario-zero-real-vs-sim-time.md`). Wall time per simulated second, with the IPC emitter active, a null sink, simTime 10 s, 3 repeats, and CV below 1 %:

| Config | Mean | Min–max | One 0.1 s KPM period takes |
|---|---|---|---|
| 1 gNB (`--nMmWaveEnbNodes=1 --e2lteEnabled=false`) | 1.685 s | 1.680–1.690 | 0.17 s wall |
| default (4 mmWave + 1 LTE eNB, 12 UEs) | 31.96 s | 31.73–32.11 | 3.2 s wall |

**Under the full system** (M7, evidence `evidence/m7/20261021T184727Z`):
- **Run length.** simTime 42 took about 22 minutes of wall time with 5 agents, the RIC and kpimon all running. That is the same rate as M4.
- **Load.** The maximum 1-minute load average was 2.45 on 8 vCPUs (1.49 in the previous M7 attempt). ns-3 is single-threaded, so **ns-3 itself is the bottleneck**; CPU headroom is not.
- **Agents.** RSS was flat at 1.3–7.2 MiB per agent over 15 minutes, with no restarts during endurance.
- **Data volume.** Each node sent one KPM sample per 3.2 s of wall time: 4539 indications in about 37 minutes across 5 nodes, with cell and UE messages split.

## 2. Timing facts on the E2 side (wall-clock, independent of sim time)

- **Agent timers.**
  - It holds off 8 s before connecting, retries the connect every 2 s with a 3 s timeout, and exits after a 10 s E2Setup timeout.
  - SCTP heartbeat 5 s; path and association max retransmissions 3.
  - On SIGTERM it ends the association with SHUTDOWN.
- **kpimon** sends a RICsubscriptionRequest about 3 s after E2Setup and re-subscribes only after its 5 s poll sees the node not CONNECTED.
- **e2term pod delete.**
  - The Service has no endpoint for about 40–150 s, so agent INITs every 5 s go unanswered.
  - Once the new pod accepts INIT, E2Setup is still unanswered until e2term has registered with e2mgr, so agents restart on the 10 s setup timeout (RestartCount 3–9).
  - First indication again at about +190–200 s for the gNBs and +237–241 s for the eNB.
  - ns-3 dropped 3–8 samples per node in that window, with zero backpressure drops.
- **Cold boot.** E2 nodes must wait for an e2tAddress in e2mgr's `/v1/e2t/list`, or their setup is silently lost. The harness bring-up already waits for it.

**Consequence for pacing.** The agents are separate processes, so SCTP and E2 keep-alive run on wall clock whatever ns-3 does. A lock-stepped (paused) ns-3 does not starve the RIC association. It only stops KPM content.

## 3. What the current design already reserves for M8

- **IPC.** Schema `ns3-e2-ipc` v1 reserves the message types `control`, `controlAck` and `step` (ns-3 ← agent). v1 emitters already drain and ignore inbound bytes.
- **Agent.** It owns a single `poll()` loop, so RC dispatch (RICcontrol to IPC `control`) can be added without touching NIST code.
- **ns-3.** The old asn1c RC path is compiled out behind `NS3_ORAN_LEGACY_ASN1_RIC_CONTROL`. `LteEnbNetDevice::ReadControlFile` and the file-mode semaphores (`UseSemaphores`) are unchanged.
- **S2.** The LTE eNB registers as a gNB-type node. RC handover addressing must account for this, because the LTE master RRC performs EN-DC handovers.

## 4. Open questions for the pacing plan (from the contract)

1. **Mode.** Lock-step vs real-time vs a hybrid.
   - Real time is impossible for the default config (32× slower than wall).
   - Lock-step only makes sense with the RIC as the clock master per period.
2. **T and timeouts.** How to choose the per-step timeout T, and what happens when it runs out: continue, freeze, or drop the control.
   - Measured inputs: the step cost is 0.17 s (1 gNB) or 3.2 s (default) of wall time per 0.1 s period, plus the RIC round trip (indication → xApp → control).
3. **Control path into ns-3.** How a control reaches the ns-3 thread safely.
   - Candidates: the emitter's socket polled from a simulator event, or `Simulator::ScheduleWithContext` from an IPC thread.
   - Today the first report is already scheduled from the sim thread; the old in-process design called it from the e2sim thread, which was a known hazard.
4. **Keep-alive vs lock-step** (section 2). SCTP liveness is decoupled by design. The questions that remain are E2 procedure timers in e2term/submgr and kpimon's subscription poll while sim time is paused.
5. **Subscription option B.** Aggregation and filtering in the agent must use sim time (`simTimeNs`), not wall time, or pacing would change KPM content.
6. **Prior art to research, with citations.**
   - ns-O-RAN / OpenRAN Gym (file-mode semaphores, `UseSemaphores`), ns3-gym, Colosseum.
   - Co-simulation and digital-twin pacing.

## 5. Required before any M8 work (contract, binding)

1. M4 timing results: done (section 1). More runs only if the pacing design needs other configs.
2. Several **independent kongming counsels** (Opus 5.5 xhigh), each blind to the others, each given this handoff and the contract.
3. Best-practice research with cited sources (section 4.6).
4. One synthesized pacing plan as a journal checkpoint: recommendation, how T is set, rollback, and M8 acceptance-criteria changes.
5. **User approval of that plan.**

## 6. P8 unattended re-run

(Filled in when the re-run completes.)

## 7. Known issues carried forward (none blocks M0–M7)

- **kpimon's own RICsubscriptionRequest** carries a v2-schema action definition that Wireshark's KPM v3 dissector flags as malformed. The agent ignores it under option A; option B will need to parse it.
- **Wireshark.** Ubuntu 24.04's tshark 4.2 cannot dissect E2SM-KPM REAL values. Gates use `tools/tshark-kpm` (Debian trixie, tshark 4.4).
- **NIST's dummy NGAP bytes** inside the E2SetupRequest decode as malformed NGAP. They are carried unchanged.
- **kpimon dropped log lines.** It occasionally fails to log 2 % of indications during a 20/s burst (NIST's kpm_sim). ns-3's rate (≤ 10/s per node) logged 100 %.
- **E2T recovery** after an e2term restart takes about 3–4 minutes, set by e2term's re-registration with e2mgr.

## 8. Pointers

- Implementation notes (every decision, deviation and failed attempt): `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/implementation-notes.html`.
- Agent design (signed off): `docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md`.
- Docs: `README.md`, `docs/deployment-guide-l-release.md`, `docs/system-architecture-l-release.md`.

## Unresolved questions

1. All of section 4. These are for the pacing planning gate.
2. Whether M8 RC must target the LTE eNB (the EN-DC master) or the gNBs, given S2.

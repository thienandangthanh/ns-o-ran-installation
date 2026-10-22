# Counsel brief: pre-M8 pacing (lock-step vs real time) for ns-3 ↔ E2 agents ↔ OSC Near-RT RIC L-release

Date: 2026-10-22. Plan: `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/plan.md`. Repo root: `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0` (branch `migrate-l-release-NIST-1-8-0`). All paths below are relative to that root unless they are URLs.

This brief is the single input for three blind counsels. It states the measured facts, the locked decisions and what is open. Read the cited files for detail; do not trust this summary over the files.

## 0. Rules for the counsel

- **Blind.** Do not read any `plans/reports/counsel-261022*` or `plans/reports/research-261022*` file, even if one appears while you work. Start your report with one line stating that you did not, and the brief SHA you were given.
- **Advisory only.** Do not edit code, do not touch the VM (`ssh oran-kvm-2404`), do not run `virsh` or any `scripts/vm/*`. Reading repo files, the submodules, and public GitHub sources (`gh api`, WebFetch) is allowed.
- **Probes.** If a number you need is missing, list the probe: the exact command or method, what it measures, and which of your recommendations it would change and how. The orchestrator decides whether to run it.
- **Answer Q1–Q8 (section 6), each with a recommendation and a confidence (high / medium / low).** Cite file:line or URL for every factual claim about code. Mark anything you inferred without reading the source as `(unverified)`.
- **Scope.** This gate designs pacing only. Do not write an M8 implementation plan, and do not propose N-release, upstream PRs, host changes or ns-3 radio/scenario changes.

## 1. System as built (M0–M7 green)

- Architecture and reasons: `docs/system-architecture-l-release.md`. Agent design record (S1–S4 signed off): `docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md`. Commands: `docs/deployment-guide-l-release.md`.
- Shape: ns-3 scenario-zero (single process, single-threaded) → one IPC emitter per E2 node → NDJSON over TCP `127.0.0.1:(38470+cellId)` → one ns3-e2-agent container per node (own netns, single-threaded `poll()` loop) → SCTP to the e2term ClusterIP Service → e2term/e2mgr/submgr/rtmgr (L pins) → kpimon-go (SIZE(8) patch) → InfluxDB.
- Node set (default): cellId 1 = LTE eNB (registers as a **gNB-type** E2 node, S2), cellIds 2–5 = mmWave gNBs; 3 UEs per gNB, RandomWalk2d 2–4 m/s; e2mgr names `gnb_001_001_0000000N`.
- Sources (submodules at the pins in `scripts/pins.conf`):
  - Agent: `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/` (`e2-session.cpp`, `ipc-server.cpp`, `sample-forwarder.cpp`, `agent-config.hpp` for timer defaults).
  - IPC schema: `.../ns3_e2_agent/schema/ns3-e2-ipc.v1.schema.json`.
  - ns-3 emitter: `oran-interface/model/e2-ipc-emitter.cc`, `oran-interface/model/e2-ipc-tcp-client.cc` (`Service()` :49, `Drain()` :143).
  - ns-3 legacy pacing and control: `ns-3-mmwave-oran/src/lte/model/lte-enb-net-device.cc` (`UseSemaphores` attribute :609, `sem_post` :115, `sem_wait` :127, `ReadControlFile`), `ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc` (`PerformHandoverToTargetCell`, `TakeUeHoControl`).
  - Prior art in-tree: `ns-o-ran-gym/` (pin 0e8ea58; `src/nsoran/ns_env.py`), `colosseum-near-rt-ric/`.
- Upstream xApps (not local; read via `gh api repos/o-ran-sc/<repo>/contents/<path>?ref=<sha>`): `ric-app-rc` @a2282ee, `ric-app-ts` @19e169b, `ric-app-qp` @47a35ca, `ric-app-kpimon-go` @8bbbbbb (all four per the NIST pin file `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/commit_hashes_l_release.json`). Platform components run as images from ric-dep @ee47a347: e2term/e2mgr 6.0.6, submgr 0.10.2, rtmgr 0.9.6 (`docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md` §1); their sources are `o-ran-sc/ric-plt-e2`, `ric-plt-e2mgr`, `ric-plt-submgr` (match the tag to the image version yourself).

## 2. Measured numbers (cite these by their evidence path)

ns-3 speed, M4 (`plans/reports/timing-261022-0217-GH-1-ns3-scenario-zero-real-vs-sim-time.md`; evidence `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m4/20261021T165230Z/`). Wall s per sim s, IPC emitter active, null sink, simTime 10, 3 repeats, CV < 1 %, ns-3 `default` profile (-O2 -g, asserts and logs on; optimized profile **not measured**):

| Config | Mean | Min–max | One 0.1 s KPM period |
|---|---|---|---|
| 1 gNB (`--nMmWaveEnbNodes=1 --e2lteEnabled=false`) | 1.685 | 1.680–1.690 | 0.17 s wall |
| default (4 mmWave + 1 LTE eNB, 12 UEs) | 31.96 | 31.73–32.11 | 3.2 s wall |

The P8 unattended re-run reproduced this: 1.644 / 29.716 wall s per sim s (`evidence/m4/20261021T225423Z`).

Under the full system, M7 (`evidence/m7/20261021T184727Z`, re-run `evidence/m7/20261021T233129Z`): simTime 42 ≈ 22 min wall with 5 agents + RIC + kpimon (same rate as M4); max 1-min load 2.45 / 1.36 on 8 vCPU, so ns-3 (single-threaded) is the bottleneck; agent RSS flat 1.3–7.2 MiB; 4539 indications in ≈ 37 min across 5 nodes.

**Not measured:** the RIC round trip (indication → xApp → RICcontrolRequest at the agent). A candidate offline proxy is the kpimon subscription-response latency in the M5/M6 pcaps (`evidence/m5/20261021T231733Z`, `evidence/m6/20261021T232516Z`).

## 3. E2-side timing facts (wall clock, independent of sim time)

Source: `plans/reports/handoff-261022-0416-GH-1-pre-m8-pacing-planning-gate.md` section 2.

- Agent: 8 s hold-off, connect retry every 2 s with 3 s timeout, exit(3) after 10 s E2Setup timeout, exit(2) on association loss (Docker restarts it with empty state), SCTP heartbeat 5 s, path/assoc max retrans 3, SHUTDOWN on SIGTERM.
- kpimon sends RICsubscriptionRequest ≈ 3 s after E2Setup and re-subscribes only after its 5 s poll sees the node not CONNECTED.
- e2term pod delete: no endpoints 40–150 s; agents restart on setup timeout; indications resume at +146 s to +241 s.
- **Consequence:** the agents are separate processes, so SCTP/E2 liveness runs on wall clock whatever ns-3 does. A paused ns-3 stops KPM content, not the association. Still open: E2 procedure timers in e2term and submgr, and kpimon's poll, while sim time is paused.

## 4. What is reserved and what is locked

**Reserved (v1):** IPC message types `control`, `controlAck`, `step` (ns-3 ← agent); v1 emitters drain and ignore inbound bytes. The ns-3 IPC client runs on the sim thread and is serviced from `EmitSample` (no separate IPC thread exists today). The agent's single `poll()` loop can add RC dispatch without touching NIST code. ns-3 has no `RealtimeSimulatorImpl` in use. The old asn1c RC path is compiled out (`NS3_ORAN_LEGACY_ASN1_RIC_CONTROL` never defined); file-mode semaphores (`UseSemaphores`, `ReadControlFile`) are unchanged.

**Locked by the user (2026-10-22), not up for debate:**
- **RC routing:** a RICcontrolRequest may land on **any** E2 node's agent; it is routed by IMSI inside ns-3 to the LTE master RRC (`PerformHandoverToTargetCell`). Every agent, the eNB included, advertises RC **RAN function 3** (TS hard-codes 3).
- **RC version:** E2SM-RC **v2.0**, generated from rc @a2282ee `e2sm/e2sm-rc-2.0.asn` with a pinned generator.
- **Ladder target:** R3 (real TS + real QP). Ladder: R0 = M8 (rc xApp control → handover in ns-3 trace), R1 (scripted, ≥ 2 gNBs), R2 (real TS + stub QP), R3 (real TS + real QP, KPM from ns-3 via InfluxDB).
- **M9:** revert `fresh-install`, then one unattended invocation up to the highest green rung.
- **User preference:** repeatable lock-step (results that repeat run to run); real-time only as a possible demo mode. Lock-step with a per-step timeout T is the planned design from M8, **not final** until this gate passes.
- Every IPC sample carries the full metric set and `simTimeNs`; subscription option B (agent-side filtering/aggregation) must change only the agent.

**Contract M8 acceptance today** (`plans/reports/brainstorm-261017-0308-GH-1-ns-oran-l-release-nist-1-8-0-contract.md` §4 and "User answers — pacing"): an rc xApp control causes a handover visible in the ns-3 trace, for at least 2 gNBs. Gates are judged by decoded wire bytes; logs are supporting evidence.

## 5. RC / TS / QP / ns-3 control facts

Read `plans/reports/scout-261022-1026-GH-1-rc-ts-qp-ns3-control-fact-pack.md` in full (verified 2026-10-22). Load-bearing points:
- Old ns-O-RAN: e2sim called the control callback on its SCTP thread and always sent RICcontrolAcknowledge; execution via `Simulator::ScheduleWithContext` cross-thread (known hazard). LTE master RRC performs EN-DC handover; `PerformHandoverToTargetCell` requires `m_mmWaveCellSetupCompleted[imsi]`. No handover-complete report to the RIC.
- ns-o-ran-gym: named POSIX semaphores + file mode; one step = one indication period in sim time; metric-semaphore wait times out after 10 s and only re-checks whether the sim ended, then retries — it never fails the step.
- rc xApp: gRPC :7777, E2SM-RC v2.0, Control Header format 1 with gNB_UEID (AMF-UE-NGAP-ID, GUAMI, F1AP/E1AP ids), Control Message format 1 (Target Primary Cell → NR CGI = `"00"+PLMNhex+TargetCellID`, hex), RMR 12040 to the ranName MEID; acks 12041 / failures 12042 only logged; 2 s ack timer only logs; gRPC rspCode 0 = queued.
- TS xApp: triggered by A1 type 20008 or AD anomaly (RMR 30003); asks QP (30000 → 30002); ranfuncid 3 hard-coded; addresses the **target cell's** node via `cell_map` built from e2mgr `e2nodeComponentRequestPart`; default control transport is REST to a 127.0.0.1 echo (must be set to gRPC → rc:7777).
- QP: reads InfluxDB `UEReports` / `CellReports`; kpimon writes `UeMetrics` / `cellMetrics` → QP cannot read kpimon's data as-is.
- NIST e2-interface has no E2SM-RC codec and no RICcontrol handler; the E2AP RICcontrol* types exist.

## 6. Questions (answer all, each with recommendation + confidence)

- **Q1. Mode.** Lock-step, real time or a hybrid. Who is the clock master, and what is one step (one KPM period, or k periods)?
- **Q2. T.** How T is chosen from the measured inputs (0.17 s and 3.2 s of wall time per 0.1 s sim period, plus the unmeasured RIC round trip). On expiry: continue, freeze, or drop the control? What determinism semantics does each give, and what repeat gate (how many runs, compared on what) does it allow?
- **Q3. Control path into the ns-3 thread.** The emitter socket polled from a sim event versus `ScheduleWithContext` from an IPC thread. Message shapes for the reserved `control`, `controlAck` and `step`. Where a step blocks (ns-3, agent, or both).
- **Q4. Timers while sim time is paused.** E2 procedure timers in e2term and submgr, kpimon's 5 s subscription poll, rc's 2 s ack timer, SCTP keep-alive (decoupled by design).
- **Q5. Subscription option B on sim time** (`simTimeNs`): aggregation/reporting period derived from sim time, and how it interacts with the step definition.
- **Q6. RC ack semantics.** When the agent sends RICcontrolAcknowledge versus RICcontrolFailure: on queue, on apply at sim time t, or on handover complete. How an ns-3 refusal surfaces (e.g. the `m_mmWaveCellSetupCompleted` guard, UE already on target, unknown IMSI).
- **Q7. M8/R0–R3/M9 acceptance-criteria changes.** The ns-3 trace (a handover per IMSI, the target cell, ≥ 2 gNBs); the wire (decoded RICcontrolRequest and RICcontrolAck through an E2SM-RC v2.0 decode); the repeat count; the automatic-handover policy (`--handoverMode=NoAuto` versus `TakeUeHoControl` per UE).
- **Q8. Rollback and the biggest risk.** What to do if lock-step fails at M8.

## 7. Report format

Write to the path the orchestrator gives you. Structure:
1. Blindness statement + brief SHA + lens.
2. Executive recommendation (≤ 10 lines).
3. Q1–Q8, each: recommendation, reasoning, confidence, citations.
4. Requested probes (if any): command/method, measurement, decision it changes.
5. Biggest risks (ranked).
6. Unresolved questions.

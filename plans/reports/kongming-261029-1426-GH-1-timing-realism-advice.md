# Kongming counsel: timing, O-RAN compliance and real-network fitness of the L-release port

Date: 2026-10-29 (Asia/Seoul). Runtime: Claude Code, Opus 5.5 as the caller routed it (not `fable`). Read-only: no VM, no git state change; this file and one agent-memory note are the only writes. Zotero MCP tools were not available to me. I read the spec text from the user's `zotero-vault` full-text caches with `gh api` (attachment keys in §2). Paths are relative to the worktree root unless stated otherwise; `@master` means `git show master:<path>` in that submodule.

Labels: **[V]** verified in code, evidence or spec text in this pass; **[C]** taken from an earlier counsel report and not re-verified; **[I]** my inference.

---

## TL;DR

1. **Real network (Q1).** The xApp code changes are small, portable and timing-free: the opt-in kpimon TimeStamp SIZE(8) patch, and the TS xApp's default RMR handler and A1 string payload. What would break against real gNBs and eNBs is the contract the xApps were tuned to. Four items are already recorded: P1 (control sent to the target node), P4 (IMSI in AMF-UE-NGAP-ID), P11 (9-octet target), and P2/N5 (cell map built from agent bytes). Two items are not on the P1–P11 list:
   - kpimon subscribes with a **10 s reporting period and 10 s granularity**, and it receives 100 ms data only because the agent ignores the subscription.
   - rc crashes on a RIC CONTROL ACKNOWLEDGE that omits the optional outcome. Our agent always sends the outcome, so M9 never tested that case.
2. **Compliance (Q2).**
   - **Wire format** of every timing-related IE and procedure is compliant: the 8-octet NTP Collection Start Time, the Granularity Period IE, one terminal answer per RIC control, and no E2 timer that a pause can fire. P10 (PPID) is the exception, and it is not about timing.
   - **Timing semantics** are idealised. In lock-step, d = 0 puts the loop below the 10 ms floor in sim time; this is recorded as P3. The agent admits a subscription whose period it does not honour; this is unrecorded. Collection Start Time is simulated UTC.
3. **Reactivity (Q3).**
   - **Lock-step:** the xApp is always "in time", but only at steps the harness chose, and with zero sim-time latency. Any unscheduled control is refused as late.
   - **Free run:** the effective delay is about one period (100 ms) at the 2-gNB config, because ns-3 is about 7× slower than real time. The exact value depends on the wall clock.
   - **Real network:** slower than both modes. With stock kpimon it is 10 s slower.
4. **Pausing (Q4).**
   - ns-3 pauses only in lock-step: once per period, after the last node's sample k at sim time k·T + 0.8 ms.
   - The barrier waits for two things: every agent has read sample k and handed its indications to SCTP, and the pacer has sent `go`. It does not wait for e2term, kpimon or InfluxDB, except at R3′ trigger steps, where the pacer certifies InfluxDB.
   - In M9 a pause took 0.5–0.8 ms at most steps, about 10 ms at R0 triggers and 1.0–1.2 s at absence steps.
5. **Original ns-O-RAN (Q5).**
   - ns-3 ran free with an in-process e2sim thread. Timestamps were wall time at start plus sim milliseconds, as a big-endian integer of milliseconds since 1970, not NTP format.
   - An RC control was applied at whatever sim time the main loop had reached, and no RIC CONTROL ACKNOWLEDGE or FAILURE was sent.
   - Pausing existed only in the gym's file mode, with semaphores and without a RIC: d = 0 at k·T + 5 ms.
6. **Recommendations (Q6), ranked:**
   - build the sim-time actuation-delay seam and sweep δ;
   - record and fix the subscription-timing deviation;
   - put wall-window xApps on the measurement-time base before a real QP or AD joins the loop;
   - define how lock-step treats data-driven controls;
   - use free run as a measurement campaign, not as a gate;
   - do not use `RealtimeSimulatorImpl`.

---

## 1. Q1: Tweaks that affect using the xApps in a real network

What is being decided: whether anything we changed or configured on the RIC side would misbehave against real E2 nodes, and what the M9 green does not prove for that case. Harness and ns-3 items matter only because they are what the xApps were validated against.

| # | Item | Where | Effect against real gNBs and eNBs | Verdict |
|---|---|---|---|---|
| 1 | kpimon TimeStamp SIZE(8) patch, opt-in, default off | `O-RAN-Testbed-Automation/.../additional_scripts/install_xapp_kpi_monitor.sh:40,124`; `docs/system-architecture-l-release.md` §6 | Correct for KPM v03+ nodes (E2SM-KPM v07.00 §8.3.12: SIZE(8)). Wrong for KPM v02.00 nodes (v02.00 §8.3.12: SIZE(4), the first 4 NTP octets); a fixed-size SIZE(8) decode misreads a 4-octet field [I]. kpimon discards the header fields anyway, so timing is unaffected [V]. | Keep opt-in; set it per node KPM version. |
| 2 | kpimon's subscription (stock NIST, unchanged by us) | `install_patch_files/xApps/kpimon-go/control/control.go.previous:429-438` (event trigger bytes `8,39,15`, commented "10000 ms reporting period"); `e2sm/wrapper.previous.c:239` (`granulPeriod = 10000`); InfluxDB points use `time.Now()` (`control.go.previous:957-980`) | A node that follows the spec reports every 10 s with 10 s granularity, 100× coarser than this port's 100 ms [V for the request, I for node behaviour]. Our agent admits the subscription and ignores both values (`ns3_e2_agent/src/sample-forwarder.cpp:62-70`, "option A" in the architecture doc §4) [V]. So no TS, QP or R3′ behaviour seen here transfers as is. | **Must change for a real network:** make kpimon's period configurable (≤ 1 s for a near-RT TS loop), and either make the agent honour the subscription or record this as a deviation (§6 R2). |
| 3 | TS xApp default RMR handler | `install_patch_files/xApps/ts/src/ts_xapp/ts_xapp.cpp.default_handler.patch` (one line: drop unhandled types) | Needed on this platform with real nodes too: rtmgr's ack fallback route can deliver stray 12041/12042 [C, counsel B]. Not timing-related. | Keep. |
| 4 | TS xApp A1 string payload | `.../ts_xapp.cpp.patch` | Needed with a1mediator 3.x regardless of the RAN. Not timing-related. | Keep. |
| 5 | TS control API switched to gRPC towards rc | `scripts/gates/ts-lib.sh:55,142` | Portable. | Keep. |
| 6 | TS xApp upstream behaviour that the harness works around (unchanged code) | `ts-lib.sh:40` (node list read once at start-up); `ts-lib.sh:52` (starts with threshold 0, never answers A1); no record of controls in flight [C, D5 counsel] | Real network: a node that connects later stays invisible until the TS xApp restarts. After a restart the threshold is 0, so the TS xApp hands a UE to any better cell until the A1 policy is sent again. | Needs an operational rule or an upstream fix. |
| 7 | rc → E2 control content: P1, P4, P11, P2/N5, P8 | run report P1–P11; `ns3_e2_agent/src/rc-control.cpp:25-33` (accepts only the 9-octet form) | A real node would refuse or mis-apply the control: wrong node, wrong UE ID type, non-standard NR CGI, no cell map. ns-3 hides P1, because the hub applies every node's control at the LTE master (`ns-3-mmwave-oran/src/lte/model/lte-enb-net-device.cc:951-952`) [V]. | Real-network blockers. They are already in the realism pass; the P10 and P11 fix acceptance is ruled. |
| 8 | rc and a RIC CONTROL ACKNOWLEDGE without an outcome | rc panics on an ACK without RIC Control Outcome within 2 s (`rcE2SmRc.go:134` at `a2282ee`) [C, counsel B] | The outcome is optional: E2AP v08.00 §8.2.4.2, and E2GAP v08.00 §5.3.2.4 step 4(i) "with the optional RIC Control Outcome" [V]. Our agent always sends ControlOutcome Format 1 (`ns3_e2_agent/src/rc-control.hpp:5-6`) [V], so M9 masks the bug. | Real-network risk: guard or fix it in rc, and add an agent test mode that omits the outcome. |
| 9 | QP and AD (NIST patches; not in the M9 loop) | QP `range(start: -1600ms)` (`install_patch_files/xApps/qp/src/database.py.patch:98`) [V]; AD is replaced by harness 30003 messages (`scripts/gates/send-rmr.sh:2,11`) [V] | QP's window is wall-clock based. With a real node at kpimon's 10 s period it is mostly empty [I]. In this slower-than-real-time simulator it holds about 2 periods instead of 16 [I, from C ≈ 0.7 s per period]. | Both need live-data adapters and a window that matches the subscribed period (§6 R3). |
| 10 | Harness-only parts: pacer, stub QP, R3′ predictor, `ns3.*` correlation KPIs | `scripts/gates/r3p-scenario.json` (`counter.cellKey`/`ueKey` use `ns3.seq` and `ns3.imsi`) | Not deployable. A real node sends no `ns3.*` rows. | Expected; document it. |
| 11 | Platform remedies: manual appmgr registration of the TS xApp and stub, a1mediator and rtmgr restarts, the RMR route-reader refresh | `ts-lib.sh` header; run report "Bring-up remedies" | These are L-release platform hazards, not simulation artefacts. A real deployment inherits them. | Carry them into operations docs. |
| 12 | ns-3 regime the xApps were validated in: NoAuto, `outageThreshold=-1000` (substitution 1), `UseIdealRrc=true`, d = 0 | `ns-3-mmwave-oran/scratch/scenario-zero.cc:483`; `scripts/gates/rung-config.json:40-47` | A real RAN runs its own mobility and RLF recovery at the same time as RIC control. Conflicts between the two are untested. | Realism-pass scope, not a deployment defect. |
| 13 | ACK semantics | `ApplyExternalHandover` sends an X2 MC handover request; completion is asynchronous (`ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:4601-4607`) [V] | The agent's ACK means "handover initiated". That matches E2GAP §5.3.2.4 4(i) ("successfully executed") if initiation counts as execution. An xApp must not read an ACK as "UE is on the target". | Note for xApp authors. |

**Answer.** None of the timing mechanisms lives in an xApp: the pacer, the barrier, `simStartEpochMs` and d = 0. So none of them would misbehave against a real node. What would misbehave falls into three groups:
- configuration choices that were hidden by the agent: kpimon's 10 s period (and the QP and AD windows built on it), and the kpimon TimeStamp variant;
- the RC addressing contract: P1, P4, P11, P2/N5 and P8;
- two upstream defects that the agent masks or the harness works around: rc's crash on an outcome-less ACK, and the TS xApp's threshold 0 and start-up-only node list.

---

## 2. Q2: O-RAN timing compliance

**Spec text read [V].** All six came from `gh api repos/thienandangthanh/zotero-vault/contents/storage/<key>/.zotero-ft-cache`:

| Spec | Vault key |
|---|---|
| O-RAN.WG3.TS.E2GAP-R004-v08.00 | `WVKTACCS` |
| O-RAN.WG3.TS.E2AP-R004-v08.00 | `M6MJY9U9` |
| O-RAN.WG3.TS.RICARCH-R005-v08.00 | `RIUNHU8T` |
| O-RAN.WG3.TS.E2SM-KPM-R004-v07.00 | `SDJ6XPRF` |
| O-RAN.WG3.E2SM-KPM-v02.00 | `JD6P3V8N` |
| O-RAN.WG3.E2SM-RC-R003-v03.00 | `JRDTL7XS` |

The project cites **KPM v03.00** (Zotero item `F82PYZVK`), whose text I did not read. The KPM clause numbers below come from v07.00 and must be re-checked against v03.00.

| Clause | What it says (verified text) | Port, wire format | Port, timing semantics |
|---|---|---|---|
| E2GAP §5.1.1; RICARCH v08.00 §5.1.3 [REQ-API-Generic-002] | The E2 interface "shall support latency requirements … from 10 milliseconds up to 1 second". RIC APIs "shall support the Near-RT RIC control loop of execution time from 10 milliseconds to 1 second". | Not applicable. | These are capability requirements, not a minimum delay. In **wall time**, the RIC half (trigger → control read by ns-3) has L_max 12.9 ms at R0, 8.2 ms at R2 and 5.4 ms at R3′ (`rung-config.json:12-19,145-147`) [V], inside the range. In **sim time**, lock-step maps that latency to 0 (`oran-interface/model/e2-control-hub.cc:288`; ledger header `"delta-model":"fixed 0"` at `:356`) [V]. That is idealised below the 10 ms floor. It is not a violation, but it must be disclosed with any closed-loop number (P3). |
| E2GAP §5.3.2.2 (REPORT "with each occurrence of RIC trigger event condition"); KPM v07.00 §7.3.2 and §8.2.1.1.1 (reporting period in ms); §7.4.2.2 (granularity period = "collection interval"); §7.4.2.4 (records "collected at every granularity period during the reporting period"); §8.3.8 | — | Format 1 and 2 messages carry Granularity Period = the IPC period (`sample-forwarder.cpp:69`; `kpm-indication-message.cpp:119,161`) [V]. | **Non-compliant behaviour, not recorded:** the agent admits kpimon's 10 s / 10 s request and reports every 100 ms sim with granularity 100 ms. The compliant options are to honour the action definition, or to answer the action as not admitted (E2AP §8.2.1). The original ns-O-RAN did the same (§5). |
| KPM v07.00 §7.4.2.3 and §8.3.12 (v02.00 §8.3.12: SIZE(4)) | Collection Start Time in UTC, OCTET STRING SIZE(8), the RFC 5905 §6 64-bit format, rounded to milliseconds. | Compliant: NTP seconds since 1900 plus fraction (`ns3_e2_agent/src/kpm-ran-function-description.cpp:69-77`) [V]. | The value is `simStartEpochMs + (simTimeMs − periodMs)`, clamped at 0 (`sample-forwarder.cpp:62-65`) [V], so it is **simulated UTC**. Gated runs pin it to 2026-01-01 (`rung-config.json:48-51`). The default 0 means wall time at helper creation (`scenario-zero.cc:303-306`; `ns-3-mmwave-oran/src/mmwave/helper/mmwave-helper.cc:121,1859,3320-3325`), which falls behind wall time by (slowdown − 1) × sim time. It marks the start of the window, about 0.8 ms early, which is more faithful than the original (end of window). |
| E2AP §8.2.4.2–8.2.4.4; E2GAP §5.3.2.4 | The RIC starts TRICcontrol (unless NoAck). The node sends ACK, with an optional outcome, when the control is executed, or FAILURE with a cause. If TRICcontrol expires, the RIC sends ERROR INDICATION. | Compliant: exactly one terminal answer, and no agent wall-clock timer (`rc-control.hpp:1-15`) [V]. | Lock-step: the ACK leaves within milliseconds at a trigger step. Free run: the ACK waits for the next period boundary, up to C of wall time (0.7 s at 2 gNB, 3.2 s at the default config). At the default config that can exceed a 2 s TRICcontrol. rc's 2 s timer only logs [C]. |
| E2AP §8.2.1.2 (TRICEVENTcreate) and the other RIC timers | They run only during subscribe, delete, modify and query. | — | Pausing is protocol-safe: a 900 s freeze drew no E2AP reaction (pause probe, `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md` §6) [C]. |
| E2AP §8.2.3.2 and §9.2.13; E2SM-RC v03.00 §6.4–6.5 | The spec's own "RAN waits for the RIC" mechanism is INSERT with Subsequent Action **Halt** and a **RIC Time to Wait** (1 ms … 60 s) for **one associated procedure**, for example an A3-triggered handover, answered by a CONTROL that accepts or denies. | — | The barrier is not this mechanism. It freezes the whole RAN once per period under REPORT + CONTROL. That is outside the spec's time model, but the RIC cannot see it apart from gaps between indications. So the wire is compliant and the semantics are simulated. |
| E2SM-RC CONTROL style 3, action 1 | No timing IE; the control executes on receipt. | — | The port applies it at the next barrier or boundary. |
| E2GAP §6.1 | SCTP PPID 70. | Deviation P10 (not timing). | — |

**Answer.**
- **Wire format:** every timing-bearing IE and procedure the port uses is compliant. P10 stays an open wire deviation, not about timing.
- **Timing semantics** are simulated in three places:
  - d = 0 in lock-step (P3);
  - the agent ignores the subscribed reporting period and granularity (a new deviation to record);
  - Collection Start Time is simulated UTC (disclosed under D10).
- **Whole-RAN pause:** it has no counterpart in O-RAN. The nearest construct is the per-procedure INSERT/Halt with Time to Wait.

---

## 3. Q3: Can the xApp act in time at the significant moment?

**Lock-step [V mechanics, I consequence].**
- **When a control is accepted.** It is applied only if it reaches ns-3 while ns-3 is blocked at barrier k, and the agent stamped `afterSeq ≥ k`. The agent stamps the last sample it read (`ns3_e2_agent/src/main.cpp:179`). ns-3 refuses `afterSeq < seq` as late (`e2-control-hub.cc:256-262`).
- **How long barriers last.** The pacer releases every non-trigger step at once (`scripts/gates/pacer.py:14`). Those barriers last about 1 ms (§4).
- **At a scheduled trigger step:** the control is always in time. The RIC gets up to T_ctl = 30 s of wall time, and the control applies at the sim time of sample k. The loop decides on data up to "now" and acts "now", with zero staleness, which no real network achieves.
- **At an unscheduled moment:** a data-driven xApp, a live AD, or a TS retry almost always arrives while ns-3 is computing. That is about 0.7 s of each 0.7 s cycle (§4). The control then carries `afterSeq = k` and is refused as late at barrier k + 1, with RIC CONTROL FAILURE `control-failed-to-execute`. The `goBeforeTrigger` case (`pacer.py:16-17`) exercises exactly this path.
- **Who picks the moment.** The "significant moment" is chosen by the harness: from a dry run, by a pre-registered template (`r3p-scenario.json` `domain`/`scheduleTemplate`). The xApp is never asked to detect it.

So lock-step answers "is the decision right at this instant?", not "is the xApp fast enough?".

**Free run [V mechanics, I numbers].**
- **Mechanics.** The hub drains controls without blocking at each period boundary and applies them without the late check (`e2-control-hub.cc:229-230`; the check at `:256` is lock-step only).
- **Delay.** A control based on sample k reaches ns-3 after L of wall time. ns-3 needs C of wall time per period: 0.70–0.72 s at 2 gNB (M9 pacer logs, §4), 3.2 s at the default config, and 0.17 s at 1 gNB (M4 timing report). The control lands at boundary k + j, with j about ⌈L / C⌉ and at least 1. That gives δ = 100 ms for any L < 0.7 s at 2 gNB.
- **What the RIC looks like.** It appears C / T times faster than it is: about 7× at 2 gNB and 32× at the default config. Near a boundary, and under host load, the landing step is not deterministic.

**Real network [I].**
- δ is the sum of report delay, RIC processing, E2 control and handover execution. With 100 ms granularity that is at least about 100 ms, plus tens to hundreds of milliseconds.
- With stock kpimon's 10 s period, decisions use 10-second aggregates, far slower than either simulator mode.
- No gate measures the sensing half (indication → kpimon → InfluxDB → AD).

**Does it matter in scenario-zero?**
- The D5 counsel's offline analysis found δ ≤ 100 ms costs at most about 2 % of the decision's value, and 500 ms costs about 10 % (`plans/reports/counsel-261022-1544-GH-1-d5-delay-realism.md` §0, §5) [C]. So d = 0 does not bias cell choice in this scenario.
- What d = 0 hides is the stale-view and duplicate-control failure mode, because the TS xApp keeps no memory of controls in flight.
- Faster mobility or mmWave blockage would make timing matter more [I].

---

## 4. Q4: Does ns-3 pause every interval T?

- **Free run (default): no pause [V].**
  - Without controls the hub writes nothing and schedules nothing. At each boundary it only drains inbound lines without blocking (`e2-control-hub.cc:229-230`; architecture doc §8).
  - The only wall-time waits are a 200 ms connect wait per emitter at start (`oran-interface/model/e2-ipc-emitter.cc:96`) and at most 2 s + 1 s of flush at the end (`:190,:202`).
  - Samples sent before a subscription are dropped by the agent (`main.cpp:73-76`).
- **Lock-step: yes, once per period [V].**
  - **Start barrier.** It runs at 1 µs (`e2-control-hub.cc:133-139,422-430`) and waits up to T_start = 120 s for every agent's step −1, which means E2 READY with at least one subscription (`main.cpp:220-223`).
  - **Per-period barrier.** After that there is one barrier per seq k, scheduled when the last emitter has emitted k (`e2-control-hub.cc:209-227`).
  - **Barrier sim time.** That is k·T + 0.8 ms: the first gNB report is at 800 µs (`mmwave-enb-net-device.cc:493-495`), rescheduled every period (`:1530`), and the eNB reports at 500 µs (`lte-enb-net-device.cc:948`).
  - **Period length.** T = `indicationPeriodicity`, default 0.1 s, allowed range 0.01–2.0 s (`scenario-zero.cc:246-248`).
- **What the barrier waits for (`e2-control-hub.cc:440-527`) [V]:**
  1. Every emitter's queued lines are flushed to TCP, up to 2 s each (`:445-448`).
  2. ns-3 sends `ready{k}` to the pacer.
  3. It polls the agents and the pacer every 20 ms.
  4. It releases when every agent has sent a `step` ≥ k (or has disconnected, for k ≥ 0) **and** the pacer has sent `go` ≥ k (`:495-515`).
  - **The agent's `step k` means:** the agent has read sample k and called SCTP send for its indications, or dropped them (`main.cpp:112-123`; `e2-session.cpp:189-215`). It does **not** mean that e2term received them, that kpimon decoded them, or that InfluxDB stored them.
  - **The pacer's `go`.** At a non-trigger step it is sent at once (`pacer.py:14`). At a trigger step it comes after `steps k`, then the prepare hook (R3′: N6 certifies that InfluxDB holds every row of [T−15, T], deadline 20 s), then the trigger, then the expected `controlRx` lines within T_ctl = 30 s, or the W = 1 s absence window (`pacer.py:16-32`). So InfluxDB is waited for only at R3′ trigger steps, and only by the pacer.
- **Deadlines [V].**
  - T_gate = 10 s counts only while steps are missing (`:516-520`).
  - Waiting for `go` has no deadline in ns-3; the pacer owns T_ctl, W and the prepare timeout.
  - An abort ends the run with exit code 5 (`:578-616`).
- **Measured in M9 live1 runs** (`e2-pacing-log.jsonl` and `pacer-log.jsonl` under `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/{r0/20261028T193510Z,r2/20261028T195650Z,r3p/20261028T200710Z}/runs/live1/`) [V]:

| Rung | Barriers | Median wait | Longest waits | Total wait | ns-3 compute per period (median) |
|---|---|---|---|---|---|
| r0 | 100 | 0.5 ms | about 9–10 ms (rc triggers) | 0.09 s | 0.70 s |
| r2 | 100 | 0.6 ms | 1.00 s × 2 (absence W) | 2.1 s | 0.70 s |
| r3p | 100 | 0.8 ms (p90 1.6 ms) | 1.21 s (steps 20, 50: negatives), 0.22 s (step 30: prepare + L ≈ 4 ms) | 2.7 s of a 74 s run | 0.72 s |

So ns-3 spends at least 96 % of its wall time computing. The pause is small, and it does not depend on RIC throughput.

---

## 5. Q5: The original ns-O-RAN, before the port

| Aspect | Original (`master` of ns-3-mmwave-oran and oran-interface; colosseum `ns-o-ran`; ns-o-ran-gym) | Port |
|---|---|---|
| Process model | e2sim is linked into ns-3, with one detached thread per node (`oran-interface/model/oran-interface.cc@master:105-139`) [V] | One agent process per node, over IPC |
| Sim time vs wall time | `DefaultSimulatorImpl`, free-running; no realtime simulator in `scratch/` (git grep: no hit) [V]. Reporting starts when the RIC subscription arrives (`lte-enb-net-device.cc@master:94-109`; `mmwave-enb-net-device.cc@master:82-95`), then repeats every E2Periodicity of sim time through `ScheduleWithContext` (`lte@master:1491-1500`) [V] | Emits from t = 0; lock-step is optional |
| KPM timestamp | `m_startTime` is the wall-clock ms at helper creation (`mmwave-helper.cc@master:121,3300`), plus `Simulator::Now()` in ms, taken when the report is built, which is the end of the window (`lte@master:1119`; `mmwave@master:674`). It is sent as 8 octets, big-endian ms since 1970 (`kpm-indication.cc@master:181-190`; `kpm-indication.h@master:51`) [V]. That is not the NTP layout of KPM v02.00 or v03+ [I; the v01-era schema it was compiled against is unchecked] | NTP-64 time of the window start; epoch can be pinned |
| Control timing | The RC callback runs in the e2sim thread and calls `ScheduleWithContext(1, Seconds(0), PerformHandoverToTargetCell)` (`lte@master:434-470`). `DefaultSimulatorImpl` stamps a cross-thread event with `m_currentTs` when the main loop next processes it (`src/core/model/default-simulator-impl.cc@master:157-177,244-270`) [V]. So a control applied at whatever sim time ns-3 had reached: tied to the wall clock, not aligned to a period, not repeatable. **No RIC CONTROL ACKNOWLEDGE or FAILURE** is sent (none in the callback) [V], against E2AP §8.2.4.2 | Applied at a period boundary; exactly one terminal answer |
| Pausing | The online (RIC) mode never paused. Gym file mode (`useSemaphores`, on master since `86862bd9`, 2024-06-30) works like this [V]: `ReadControlFile` runs at T + 5 ms and then every T (`lte@master:1043,374`). It does `sem_post(metrics)`, then `sem_wait(control)` with **no timeout** (`lte@master:135-160`). Handovers apply at `Seconds(0)` when parsed (`ScheduleControlMessages` defaults to false, `lte@master:622-628`; `:217-222`). This path exists only with `EnableE2FileLogging`, so there is no RIC (`lte@master:955-990`) | Lock-step on the E2 wire with a live RIC |
| Gym driver | `ns_env.py:235-243` creates the semaphores. `ns_env.py:354-383`: `step` writes the action CSV, releases `control`, then waits for `metrics` in a loop whose timeout only checks whether the simulation ended. `ts_use_case.json` sets `useSemaphores` 1 and `indicationPeriodicity` 0.1 [V] | Pacer with T_gate, T_ctl and W; freeze, then fail |
| xApp side (colosseum `ns-o-ran`) | The sample xApp only logs what it receives (`setup/sample-xapp/run_xapp.py`). The connector subscribes with a HelloWorld event trigger that has no reporting period (`setup/xapp-sm-connector/src/xapp-asn/e2sm/e2sm_subscription.cc@ns-o-ran-xapp-control:32-56`) [V]. So ns-3's own period also drove the reports there | kpimon asks 10 s; the agent ignores it (same habit) |

**Answer.**
- The port's lock-step has the gym's semantics (pause once per period, d = 0), now on the E2 wire with a live RIC.
- The port's free run is more disciplined than the original online mode: controls apply at period boundaries, and every control gets an E2AP answer.
- Neither original mode modelled RIC latency in sim time. Lacava et al. (WNS3 2023 §3) name the gap and only rebase timestamps [C].

---

## 6. Q6: Recommendation for the post-M9 realism pass, ranked

**R1. Make the actuation delay δ a sim-time parameter, and sweep it (highest).**
- **What.**
  - Add an `ActuationDelay` attribute to `E2ControlHub`, default 0.
  - The decision is taken at barrier k. The precheck, handover, ledger line and `controlAck` all run in one apply event at t_k + δ, scheduled with a relative `Simulator::Schedule`.
  - The ledger gains `decisionSeq` and `delayNs`, and a replay injects at the decision step.
  - Controls still pending at the stop get FAILURE.
- **Values.** δ = 0 stays the regression value; the δ = 0 runs must stay byte-equal to the M9 references. The sweep is δ ∈ {100, 200, 500 ms}. One off-grid value, such as 150 ms, separates the effect of δ from the period boundaries.
- **Trade-off.** It stays deterministic and repeatable, because δ is sim time, and it turns P3 into a disclosed knob. It does not model the distribution of the latency.
- **Cost.**
  - It changes the contract: ledger schema, ACK timing and new references, for δ > 0 runs only.
  - The ACK's wall latency grows to about (δ / T) × C, for example about 3.6 s for δ = 500 ms at 2 gNB. That is beyond rc's log-only 2 s timer. Record it; do not gate on it.
- **Landmines** [C, D5 counsel]:
  - a new `RandomVariableStream` without an explicit stream index shifts every digest;
  - the destroy-hook order is FIFO;
  - a precheck at receipt with a delayed apply can reach the `epc-x2.cc` assert, so run the precheck at apply time.
- This is the only change that turns the largest realism gap into a controlled, repeatable variable. Every closed-loop number published from this port should come with a δ sweep.

**R2. Record the subscription-timing deviation (say P12), then fix it.**
- **The deviation.** kpimon requests 10 s / 10 s, and the agent admits that but sends 100 ms. The governing clauses are E2GAP §5.3.2.2, KPM §7.3.2, §8.2.1.1.1, §7.4.2.2 and §8.3.8, and E2AP §8.2.1.
- **The fix.** Do both of these:
  - (a) Let kpimon's requested period be configured to what the experiment needs: granularity = T, and a reporting period of T or 1 s.
  - (b) Make the agent honour the action: aggregate ⌈granularity / T⌉ ns-3 samples, report every reporting period, and answer non-multiples as not admitted. This is "option B"; it changes only the agent.
- **Trade-off.** Real-network fitness and spec semantics improve. The cost is one kpimon patch and agent work. Check first that kpimon handles more than one record per Format 1 message (unverified). Honouring the stock 10 s literally would starve the TS loop, so (a) is required together with (b).

**R3. Put wall-window xApps on the measurement time base before a real QP or AD enters the loop.**
- **What.** Behind a flag, kpimon stamps InfluxDB points with the decoded Collection Start Time instead of `time.Now()`. It already decodes the header and then discards it. QP and AD then query windows in that time base.
- **Why.** In a slower-than-real-time simulator, QP's `-1600ms` covers about 2 periods, not 16. Against a real network, measurement time is the correct key anyway, not arrival time.
- **Trade-off.** It adds one more divergence from upstream kpimon. Pinned epochs (2026-01-01) may collide with InfluxDB bucket retention (unverified). Free-run experiments should use the wall time at start (`simStartEpochMs=0`).
- R3′ already follows this rule: it windows by `ns3.seq`.

**R4. Decide how lock-step treats data-driven, unscheduled controls.** Today they are refused as late, so a live AD → TS loop cannot run in lock-step. Options:
- **(a) Window mode.** Apply a per-step window W at every step, with W derived from measured L instead of the 1 s floor. With W = 50–100 ms and C = 0.7 s, wall time grows by about 7–14 %. The run stays deterministic as long as nothing is late, because freeze-then-fail stays. W must also cover the sensing half; AD's polling interval is unmeasured.
- **(b) Late-apply mode.** A late control applies at the next barrier with δ += T. This is statistical and must be labelled so; use it for demos only.
- **(c) Event-triggered pause.** Pause only at RAN events, mirroring E2SM-RC INSERT/Halt (§6.4). This gives the most faithful decision instants. It is long-term research: the TS xApp does not use INSERT, and the agent and ns-3 would need it.

Recommendation: (a) for any rung with a real AD or QP, (b) for demos.

**R5. Free run as a measurement campaign, not a gate (cheap; can run first to choose R1's δ values).**
- Run the R2 and R3′ configs free with live rc and the TS xApp. For each control, record L, `rxSeq − afterSeq` (the effective δ in periods), the ACK's wall latency, and C / T.
- Also measure C with an `optimized` ns-3 build; this is unresolved since M4.
- **Trade-off:** the results are not repeatable, but no code change is needed. `check-free-control-ledger.py` exists, and no live-RIC free-run gate exists today.

**R6. Model execution latency.** Add a realism flag for `UseIdealRrc=false`, so RRC signalling takes air time, and combine it with the δ sweeps. It changes the free-run digests, so it needs its own references.

**What to avoid.**
- **`RealtimeSimulatorImpl`.** Even 1 gNB runs 1.685× slower than real time in the default profile, 2 gNB about 7× and the default config 32×. HardLimit aborts and BestEffort drifts. Reconsider it only if an optimized build at the target scale runs faster than about 0.8× real time with margin; measure that first.
- **Making "δ = measured wall L" a gate.** L is host-dependent and covers only trigger → control. Use it only as an experiment, with δ_k logged so a replay can reproduce the run.
- **Relaxing the late refusal in gate runs.** That destroys repeatability.
- **Publishing a closed-loop number at d = 0 alone.**

| Option | Repeatability | Realism | Cost |
|---|---|---|---|
| R1 fixed δ sweep | Full (sim time) | Medium: fixed latency | Contract change, new δ > 0 references |
| R4(a) window mode | Full if nothing is late | Medium: real decision instants | +7–14 % wall; W calibration |
| R5 free run | None (statistical) | Medium-high: real L, compressed by C / T | Almost none |
| δ_k = measured L | Replay only | High for the RIC half only | Low code, high noise |
| Realtime simulator | None | High only if faster than real time | Not viable today |

---

## Assumptions

- "Real network" means real E2 nodes speaking E2AP v03+, KPM v03+ and E2SM-RC to this same L-release RIC and these xApps. Confidence: high.
- Lock-step stays the gate mode in the realism pass, as in the architecture doc §8 and the rulings. Confidence: high. If gates moved to free run, R1 would lose its main benefit, and R5 would become the gate design.
- The rc behaviour (2 s log-only ACK timer; panic on an outcome-less ACK) is taken from counsel B (2026-10-22) at pin `a2282ee`. Confidence: medium. It was not re-read in this pass.

## Unresolved questions

1. Should the subscription-timing behaviour be recorded as a numbered deviation (P12), and is the fix "honour it in the agent" plus "configure kpimon's period"? This is a user decision.
2. Which δ values define "realistic" for the realism pass: a fixed sweep {100, 200, 500 ms}, or values derived from an R5 free-run measurement? This is a user decision.
3. Must lock-step support data-driven xApp decisions in future rungs (a real AD or QP)? If so, window mode or late-apply mode?
4. The KPM v03.00 text (`F82PYZVK`) was not read. Clauses §7.3.2, §7.4.2.2–7.4.2.4, §8.2.1.1.1, §8.3.8 and §8.3.12 should be confirmed against it.
5. rc's outcome-less-ACK panic and its 2 s ACK timer were not re-verified at `a2282ee` in this pass.
6. AD's InfluxDB polling interval (the latency of the sensing half) is unmeasured, and it sets W for R4(a).
7. Does kpimon decode Format 1 messages with more than one record? R2(b) needs that.
8. Would InfluxDB bucket retention drop points stamped with a pinned past epoch if R3 is adopted?

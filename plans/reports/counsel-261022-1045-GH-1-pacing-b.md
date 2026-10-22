I did not read any `plans/reports/counsel-261022*` or `plans/reports/research-261022*` file. Brief SHA `552a58fb2854c4e5eb889ecc25d31852a91496bf`. Lens B: RIC and E2 protocol timing first. Model: Opus 5.5 (kongming).

# Counsel B: pre-M8 pacing, RIC and E2 timing lens

Date: 2026-10-22. Advisory only. No VM access, no builds. Upstream sources were read at the deployed tags and pins:

| Short name | Source |
|---|---|
| `submgr` | `o-ran-sc/ric-plt-submgr@0.10.2` (64238c3) |
| `e2term` | `ric-plt-e2@6.0.6` (472cb9f) |
| `e2mgr` | `ric-plt-e2mgr@6.0.6` (09036c6) |
| `rtmgr` | `ric-plt-rtmgr@0.9.6` (85d4b0b) |
| `rmr` | `ric-plt-lib-rmr@4.9.4`, the version e2term's Dockerfile installs (`e2term RIC-E2-TERMINATION/Dockerfile:46-49`) |
| `rc` | `ric-app-rc@a2282ee` |
| `ts` | `ric-app-ts@19e169b` |
| `qp` | `ric-app-qp@47a35ca` |
| `ad` | `ric-app-ad@f9f97b8` |
| `kpimon` | `ric-app-kpimon-go@8bbbbbb` with NIST's `control.go.patch` applied after CRLF→LF. Line numbers refer to the patched file. |

The image tags were checked in two places: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m1/20261021T111011Z/checks/image_tags_recorded.out`, and each repo's `container-tag.yaml`.

Deployed timer values come from the ric-dep@ee47a347 helm templates, `helm/submgr/templates/configmap.yaml` and `helm/e2mgr/templates/configmap.yaml`. NIST does not patch the timer keys.

**Spec text.** O-RAN.WG3.TS.E2AP-R004-v08.00 §8.2.4 and §9.2.21. I read it from the full-text cache `thienandangthanh/zotero-vault storage/M6MJY9U9/.zotero-ft-cache`. v2.0 semantics are corroborated by O-RAN SC Jira RIC-722, read through the REST API (https://lf-o-ran-sc.atlassian.net/rest/api/2/issue/RIC-722), and by ONE Summit 2021 slide 7 (https://static.sched.com/hosted_files/onesummit2021/62/ONeS_NA_2021_Thoralf_Czichy_Matti_Hiltunen_lessons_learned_near_rt_RIC_and_xApps.pdf).

## 2. Executive recommendation

1. **Lock-step, with ns-3 as the only clock owner and the only component that ever blocks.**
   - One step is one KPM period (0.1 s of sim time).
   - The RIC cannot be the clock master. E2 has no "decision complete" or "no action" message, and the TS xApp's no-op decision is silent (`ts ts_xapp.cpp:731-734`).
   - A step is released by a wall-clock gate T. T starts when the last agent confirms it has forwarded step k.
2. **Pausing sim time is protocol-safe.** Every RIC and E2 timer runs on wall clock, and no indication pause triggers any of them. Two things must hold: the agent's poll loop never waits on ns-3, and step 0 is gated on E2 readiness (setup done and a subscription admitted on every node).
3. **T = max(1.0 s, 3 × p99.9 of the RIC-chain latency), set per rung.**
   - Provisional values: 1.0 s for R0/R1 and 3.0 s for R2/R3.
   - R3 also needs T + t_step ≥ 2.0 s, because QP reads a 1.6 s wall-clock window.
4. **On expiry, continue.** A control that arrives after the gate gets a `RICcontrolFailure` with cause `ricRequest: control-timer-expired`, and the run is marked tainted. The repeat gate requires zero late controls.
5. **Ack semantics: validate and commit on receipt while sim time is frozen, apply at release, ACK at once.**
   - Every `RICcontrolAcknowledge` **must carry a valid E2SM-RC ControlOutcome**. Without one, rc panics (Q6).
   - Any refusal by ns-3 becomes a `RICcontrolFailure` with cause `control-failed-to-execute`.
6. **Gate on wire bytes only, never on rc's ack logs.** RMR routes 12041 by `ricInstanceID`, which collides with submgr subscription IDs, and the fallback route is chosen in Go map order.

## 3. Answers

### Q1. Mode, clock master, step

**Recommendation.**
- Use **gated lock-step**: ns-3 owns sim time, and a step barrier runs as a sim event on the sim thread, just after the last node's sample k.
- Release the barrier when two things hold:
  - all N agents have sent a forward-ack (`step`) for seq k;
  - T has elapsed since the last of those acks.
- An optional early release by the harness can come later as a speed-up. It is not needed for M8.
- **One step is one KPM period.** Larger steps are only a speed knob, and only in combination with option B (Q5).
- Free-run, as proven in M5–M7, stays as the demo mode and the rollback (Q8).
- Real time is impossible: ns-3 runs 1.7× to 32× slower than real time (brief §2).

**Reasoning.**
1. **Why the RIC cannot be the clock master.**
   - The RIC Control procedure "shall be initiated by the Near-RT RIC" (E2AP §8.2.4.1). E2 therefore has no message meaning "RIC finished thinking about period k".
   - TS issues a gRPC control only when it decides to act. Otherwise it only prints "serving cell is the best one" (`ts ts_xapp.cpp:719-734`).
   - kpimon, QP and rc expose no per-period completion signal either.
   - So any barrier must end on wall time, or on an out-of-band harness token in scripted rungs.
2. **Why pausing is safe.** All RIC and E2 timers are wall-clock and none is fed by indications (Q4). Only ns-3 needs to stop, and nothing on the RIC side notices.
3. **Why one step equals one period.**
   - KPM is the RIC's only input, and kpimon stamps Influx points with `time.Now()` (`kpimon control.go:978,999`).
   - With k > 1, the k samples land in Influx spread over k × t_step of wall time (3.2 s each in the default config).
   - QP's 1.6 s query window (Q2) then sees at most one of them. A larger step adds reaction latency without adding information.
   - ns-o-ran-gym also uses one indication period per step (fact pack §4; `ns-o-ran-gym/src/nsoran/ns_env.py:237-376`).
4. **Why only ns-3 blocks.** The agent's single `poll()` loop also answers submgr, which has a 2 s timer, and keeps SCTP alive (`ns3_e2_agent/src/main.cpp:144-176`). Blocking it would break E2 procedures (Q4).

**Confidence.** High for the mode and the clock-master argument. Medium for one period as the default step (it depends on run-length budget).

### Q2. How T is set, expiry semantics, repeat gate

**Recommendation.**
- **What T measures.** T covers only the RIC chain. ns-3 compute time (0.17 s / 3.2 s per period) is spent before the gate opens. Wall time per step = t_step + t_fwd (milliseconds) + T.
- **Formula:** `T_rung = max(T_floor = 1.0 s, 3 × p99.9(L_rung))`.
  - L_rung is the wall time from "last agent forward-ack of seq k" to "control for step k read by ns-3".
  - Measure it per rung, excluding warm-up steps.
- **Extra constraints for R3:**
  - `T + t_step ≥ 1.6 s + 0.4 s`, so that QP's window never spans two steps. This holds automatically in the default config; small configs need T ≥ 2.0 − t_step.
  - The TS trigger for step k must fire only after Influx holds every `ns3.seq = k` row.
  - QP's query must then land within about 1.2 s of the last write, so the window is never empty.
- **Hard caps (exceeding one aborts the run):**
  - start barrier: 120 s;
  - forward-ack wait per step: 10 s;
  - total T per step: 3 × T_rung.
- **Provisional values until the probes:**
  - R0/R1: T = 1.0 s;
  - R2/R3: T = 3.0 s.
  - Default config at T = 1.0 s: 4.2 s of wall time per 0.1 s of sim time. simTime 6 s takes about 4.2 min plus about 20 s of start barrier.

**Inputs I measured offline** from committed evidence. These are counsel-computed and need an orchestrator re-check (see P-B0):

| Hop | Value | Source |
|---|---|---|
| Indication wire → kpimon "Message received" | ≤ 3 ms (n = 199; kpimon timestamps have 1 ms resolution) | M6 |
| kpimon receive → next "Wrote … InfluxDB" | p50 10 ms, p99 30 ms, max 31 ms | M6, n = 199 |
| kpimon receive → next "Wrote … InfluxDB" | p50 9 ms, p99 33 ms, max 38 ms | M7, about 2.7 k receives, 5 nodes |
| E2Setup round trip | ≈ 3.0 s for 8 of 10 associations, 5 ms for 2 | M7 pcap |
| E2SetupResponse → kpimon RICsubscriptionRequest | 0.25–4.99 s (kpimon's 5 s poll phase) | M7 pcap |
| Agent RICsubscriptionRequest → RICsubscriptionResponse | < 1 ms | M7 pcap |

So the measured RIC hops are milliseconds. Not yet measured:
- the rc → e2term → agent path, expected to be milliseconds on the same RMR and SCTP machinery (unverified);
- grpcurl process start (unverified);
- QP read and forecast, including first-call training per cell (`qp main.py:96-104`, `qptrain.py:128`). This one is unknown and may take seconds.

**Expiry semantics:**

| On expiry | Trajectory semantics | E2 conformance | Verdict |
|---|---|---|---|
| **Continue + fail late** (recommended) | The trajectory is a function of (seed, controls on time). A late control is never applied. | Every request gets a terminal answer: FAILURE with `control-timer-expired`. RIC-722 and slide 7 describe "FAILURE … if control timer on E2 expired". | Clean accounting. A run with late > 0 is tainted. |
| Continue + apply late at next boundary | Depends on how many steps late a control arrives, which is wall-jitter dependent. | ACK after a delay. | Equally tainted, and harder to diagnose. More realistic. A user option. |
| Freeze (wait for the control) | Deterministic only if something says a control is expected. | n/a | **Not usable as the default.** A silent TS no-op is indistinguishable from a slow RIC, so freeze deadlocks or aborts falsely. Usable for scripted steps only (Q8, fallback B). |
| Drop silently | Same as fail-late. | **Violates E2AP.** With the Ack Request absent, the node must ACK on success or FAILURE on failure (§8.2.4.2-3). | Reject. |

**Repeat gate.**
- Run each of M8/R0, R1, R2 and R3 three times with the same seed and config, and require all of the following:
  1. ns-3 IPC trace `sample` lines byte-identical. Exclude `hello` and `bye`, which carry wall fields.
  2. Applied-control log identical: (seq, simTimeNs, imsi, source cell, target, result, reason).
  3. ns-3 handover trace identical.
  4. Per step, an identical multiset of decoded E2SM-RC (UE id, target CGI) values, and exactly one ACK or FAILURE per request with an identical result. Ignore RICrequestID values and every wall timestamp.
  5. Invariants:
     - late = 0;
     - `droppedNoSub` = 0 after the start barrier;
     - agent restarts = 0;
     - rc RestartCount = 0.
- **M9:** one run per rung, compared with the dev-run golden on items 1–4. Equality proves determinism across a fresh install.
- **Prerequisite for R2/R3:** reset xApp state between runs (Q8 risk 5).

**Confidence.** Medium for the formula and semantics. Low for the R2/R3 value until P-B3 has run.

### Q3. Control path into ns-3, message shapes, where a step blocks

**Recommendation.**
- **Poll the emitter sockets from the sim-thread barrier event.** Do not use `ScheduleWithContext` from an IPC thread.
  - This follows the existing design: one thread, with `Service()` called from `EmitSample` (`oran-interface e2-ipc-emitter.cc:103-131`, `e2-ipc-tcp-client.cc:49-67`).
  - From the E2 side, an event inserted by an IPC thread gets the sim timestamp current at insertion. That ties placement to wall timing, unless ns-3 is already parked in a barrier, which makes the thread pointless. (ns-3 detail unverified here; lens C.)
- **What the barrier does:**
  1. On entry, drain all N sockets. Anything already waiting arrived during compute and is **late**.
  2. Then `poll()` all N sockets until every forward-ack for k is in and T has elapsed.
  3. Validate and commit each control as it arrives, and reply with `controlAck` at once.
  4. At release, apply the committed controls through `Simulator::Schedule(0)`, sorted by (imsi, target).
  - Sorting is needed because rc sends each request from its own goroutine, so wire order is not deterministic (`rc control/rcControl.go:141`).
- Controls may arrive on any node's socket (locked any-node routing), so the barrier is global, not per node.
- **Where a step blocks.** Only ns-3 blocks. The agent never waits on IPC; its sends are non-blocking with a bounded buffer. The RIC never blocks.

**Message shapes.** New types within v1 bump `minor`. `hello` gains `pacing: "lockstep"|"free"` and `gateMs`, so a free-run emitter keeps v1 behaviour.

- `control` (agent → ns-3):
  ```
  {type, v, nodeId, ctrlId, ricRequestorId, ricInstanceId, ranFuncId, style, action,
   imsi (from gNB-UEID amf-UE-NGAP-ID), targetCellId (decoded from the NR CGI),
   afterSeq (last sample seq forwarded), rxMonoMs}
  ```
- `controlAck` (ns-3 → agent):
  ```
  {type, v, nodeId, ctrlId, result: "applied"|"rejected",
   reason: "unknown-imsi"|"not-associated"|"in-handover"|"same-cell"|"unknown-target"|"duplicate"|"late"|"not-ready",
   seq, applySimTimeNs, servingCellId}
  ```
  "applied" means committed for execution at `applySimTimeNs`.
- `step` (agent → ns-3):
  - `phase: "ready"` with `{e2State, subs}` feeds the start barrier.
  - `phase: "forwarded"` with `{seq, indTx, droppedNoSub, droppedE2Down}` is the forward-ack.
- Optional `step` (ns-3 → agent), `phase: "released", seq`. It is for observability only. ns-3 stays the authority on whether a control was on time.

**Confidence.** High for the sim-thread poll and for only ns-3 blocking. Medium for the exact field set.

### Q4. Timers while sim time is paused

**Recommendation.** No RIC or E2 timer is triggered by an indication pause of any length. Two rules keep it that way:
- the agent never blocks its loop;
- an agent disconnect during a lock-step run aborts the run.

| Component | Timer (deployed value) | What starts it | Effect of a paused ns-3 | Source |
|---|---|---|---|---|
| e2term | None per procedure. `epoll_wait` timeout −1, RMR send retries off. | — | None. A single per-node state value only gates "E2Setup seen"; a pending control does not block indications or subscriptions. | `e2term sctpThread.cpp:529, 3211, 3530-3551, 2919-2948, 2450-2463, 3060-3080` |
| e2term SCTP | Env-driven heartbeat and max-retrans | Kernel | None. Decoupled. | `sctpThread.cpp:357-389, 985-1001` |
| e2mgr | E2T keep-alive with e2term only (delay 120000 ms, response timeout 360000 ms). E2 reset timer, only when a node sends Reset. | e2mgr ↔ e2term; node Reset | None. No per-E2-node inactivity timer exists. | `e2mgr managers/e2t_keep_alive_worker.go:54`; `handlers/rmrmsghandlers/e2_reset_request_handler.go:143-150`; ric-dep e2mgr configmap |
| submgr | Subscription request: 2000 ms × 2 tries. Delete: 2000 ms × 2. On expiry: an internal delete plus a failure to the xApp. | Only while a subscription or delete procedure runs | None, as long as the **agent** answers. A subscription is removed only on `_DISCONNECTED` or `_UNDER_RESET`, or an explicit delete. | `submgr control.go:1253-1280, 1156-1163`; `e2if_state.go:112-137`; ric-dep submgr configmap |
| kpimon | 5 s ticker. Subscribes when a node is CONNECTED and route-ready and not yet subscribed. Clears the flag only when the node is no longer CONNECTED. | Node status | None. Indication gaps are invisible to it. | `kpimon control.go:1146-1189` |
| rc | `controlAckTimer` = 2 s. On expiry it only logs; the error indication is never sent. | Each RICcontrolRequest | None on E2. It only changes logs, but it gates the ack-decode crash path (Q6). | `rc rcControl.go:156-198`; `xapp-descriptor/config.json:72` |
| TS | No timer. Its gRPC call to rc sets no deadline. | — | None. | `ts ts_xapp.cpp:608, 656` |
| QP | **The query window is wall-clock: `range(start: -1600ms)`.** | Each prediction request | **Coupled.** Lock-step must keep the trigger within the window (Q2). | NIST `install_patch_files/xApps/qp/src/database.py.patch` (added line at patch line 98) |
| AD (if used as TS trigger) | 0.5 s schedule; −1600 ms window (upstream) | Wall clock | Coupled. Prefer a scripted trigger (Q7). | `ad src/main.py:44`, `src/database.py:88` (NIST patches the queries; patched window not verified) |
| Agent | Hold-off 8 s, connect retry 2 s, setup timeout 10 s, stats every 5 s, 100 ms timerfd, 1 s poll timeout | E2 lifecycle | None after READY | `ns3_e2_agent/src/agent-config.hpp:24-27`; `main.cpp:135-176` |
| Agent SCTP | Heartbeat 5 s, max-retrans 3 | Kernel | None. Decoupled by design (brief §3). | brief §3 |

The E2AP Indication procedure starts a timer only for INSERT actions (RIC Time to Wait, with a Call Process ID). REPORT actions, which are all this system uses, start none (E2AP §8.2.3.2). A v2/v3 subscription has no lifetime; the pinned ASN has no subscription-time IE.

**Two lock-step obligations follow:**
- **The agent stays non-blocking.** If it waits on ns-3 for more than about 2 s while kpimon re-subscribes, submgr times out twice and deletes the subscription internally.
- **Step 0 is gated on E2 readiness.** In free-run, samples that arrive before the subscription are dropped (`main.cpp:82-85`). The first indication then lands 2.8–12.9 s after the subscription (M7 pcap). Without the gate, the KPM start is wall-timing dependent.

**Confidence.** High. I read every component's source at its deployed tag. P-B2 would confirm this empirically.

### Q5. Subscription option B on sim time

**Recommendation.**
- **Keep option A (forward every period) through M8–R3.**
- When option B is built:
  - Window boundaries come from `floor(simTimeNs / reportingPeriodNs)`, aligned to sim time 0.
  - The aggregate is emitted in the step that closes the window.
  - Wall-clock timers never drive reporting: the agent's 100 ms timerfd is for liveness only.
  - The KPM header `colletStartTime` is the window start (already sim-derived, `sample-forwarder.cpp:62-66`).
  - Granularity stays one period (`sample-forwarder.cpp:69`).
- **Interaction with the step.**
  - A window is m steps long, where m is the reporting period divided by the KPM period.
  - Keep gating **every** step, so a control's landing step does not depend on which steps produce indications.
  - Gating only the window-closing steps would cut wall time by about (m−1)·T per window, but it moves controls injected mid-window. Allow that only with an explicit user decision.
- **Fork for the user.** kpimon's event trigger asks for **10 000 ms** (`kpimon control.go:439-447`).
  - Honouring it in sim time means one indication per node every 100 steps, which is 320 s of wall time in the default config. TS/QP in R3 could then act only once every 10 s of sim time.
  - **Default recommendation:** option A for the ladder. Under option B, honour the trigger but allow a harness-configured override period.
  - **What would flip it:** a requirement that the E2 contract be honoured literally.

**Confidence.** Medium (the sim-time mechanics: high).

### Q6. RC ack semantics and how refusals surface

**Recommendation.**
- **ACK when the control has been validated and committed for execution at the step's apply time.** That is "successfully processed" in E2AP's sense: sim time is frozen while ns-3 sits in the barrier, so commit and apply happen at the same sim instant.
- **Do not ACK on queue.** That repeats the old e2sim always-ack hazard (fact pack §1).
- **Do not ACK on handover complete.** Completion lands one or more steps later in wall time (> 2 s). Nothing reports it to the RIC, and it can still fail later. Handover completion is a trace gate (Q7), not an E2 outcome.

**Spec basis.**
- rc never encodes `RICcontrolAckRequest` (`rc e2ap/wrapper.c:30-139`).
- With the IE absent, "the E2 Node shall respond with the RIC CONTROL ACKNOWLEDGE message" on success. On failure to execute, an E2SM encoding error, an unknown RAN function or an unsupported action, it "shall respond with the RIC CONTROL FAILURE" (E2AP R004 v08.00 §8.2.4.2-3).
- The pinned v2/v3 ASN has the same `{noAck, ack}` enumeration (`rc e2ap/e2ap.asn:579-583`; NIST `e2ap-pdu-v03.01.asn:740-783`). I did not read the v02/v03 prose (unverified for those versions).

**The ACK must carry `RICcontrolOutcome`**, an E2SM-RC v2.0 `E2SM-RC-ControlOutcome` Format 1. An empty `ranP-List` is legal (`rc e2sm/e2sm-rc-2.0.asn:895-907`).

How rc crashes without it:
1. It decodes the ack (`rc rcE2AP.go:59-61`): `C.GoBytes(nil, 0)` gives an empty slice.
2. `HandleControlResponse` runs in a bare goroutine (`rcControl.go:90`).
3. It calls `GetControlOutcome` (`rcControl.go:345`), which takes `&buffer[0]` (`rcE2SmRc.go:134`).
4. Index out of range: an unrecovered panic, and the whole rc process exits.

This happens only when the ack reaches rc within its 2 s window (`rcControl.go:333-343`), so it is intermittent (risk 1). A `RICcontrolFailure` is safe; its handler does not decode the outcome (`rcControl.go:359-387`).

**Refusal mapping.** Pre-checks are mandatory because ns-3's own guards are silent or unsafe:
- `PerformHandoverToTargetCell` only prints a warning for "not associated" or "already performing HO" (`lte-enb-rrc.cc:4525, 4530`).
- It has no same-cell check, unlike the automatic path at `:4430-4450`.
- `GetRntiFromImsi` returns 0 for an unknown IMSI (`:3620-3630`). The file path would then call `GetUeManager(0)`, which likely aborts (unverified).

| Condition | Who decides | E2 answer (Cause) |
|---|---|---|
| E2SM-RC decode error, or the UE ID is not gNB-UEID | agent | FAILURE, `ricRequest: control-message-invalid` |
| `ranFuncId` ≠ 3 | agent | FAILURE, `ricRequest: ran-function-id-invalid` |
| Style/action ≠ (3, 1) | agent | FAILURE, `ricRequest: action-not-supported` |
| ns-3 IPC down, or before the start barrier | agent | FAILURE, `ricRequest: system-not-ready` |
| Late (read at barrier entry) | ns-3 → agent | FAILURE, `ricRequest: control-timer-expired` |
| Unknown IMSI | ns-3 | FAILURE, `control-failed-to-execute` |
| Not associated (`m_mmWaveCellSetupCompleted` missing) | ns-3 | FAILURE, `control-failed-to-execute` |
| In handover (flag false), or a second commit for the same IMSI in the same step | ns-3 | FAILURE, `control-failed-to-execute`; the duplicate also increments a taint counter |
| Target not a mmWave cell | ns-3 | FAILURE, `control-failed-to-execute` |
| Same cell | ns-3 | FAILURE, `control-failed-to-execute` |
| All checks pass | ns-3 commits | ACK with a Format 1 outcome. `ranP-List` empty, or carrying the target, an inference. |

Cause enumeration: `rc e2ap/e2ap.asn:271-287`.

**Confidence.** High for the ACK-on-commit semantics and for the mandatory outcome IE. Medium for the cause mapping.

### Q7. Acceptance-criteria changes

**Recommendation.**

**M8 (R0).**
- **Wire:**
  - each injected control yields one decoded `RICcontrolRequest` (E2AP v2 plus an E2SM-RC v2.0 decode with the pinned generator);
  - exactly one terminal answer with a matching RICrequestID;
  - the ACK's `RICcontrolOutcome` decodes as Format 1.
- **Negative case:** one deliberately invalid control (an unknown IMSI or the same cell) yields a FAILURE with the expected cause.
- **Any-node routing:** at least one control lands on the eNB agent (cellId 1), and at least one on a gNB agent that is not the target.
- **Trace:** each ACKed control has a handover in the ns-3 trace for that IMSI to the target. At least 2 distinct target gNBs. Applied at the committed seq/simTimeNs.
- **Invariants:** rc RestartCount = 0; late = 0; `droppedNoSub` = 0 after the start barrier.
- **Repeat:** 3 runs (Q2).
- **Never require rc's "ack decoded" log.** Routing of 12041 is not deterministic (risk 1).

**R1.** Same as M8, scripted, with at least 2 gNBs and at least 2 controls per gNB.
- The harness injects only after the barrier for seq k is open (tail ns-3's barrier log).
- If R1 repeats fail because of injection timing, switch R0/R1 to fallback B (Q8).

**R2/R3.**
- Trigger TS with a scripted 30003 message once Influx holds every seq-k row, not with AD. AD runs on a 0.5 s wall schedule (`ad main.py:44`).
- Restart TS after every node is CONNECTED. `cell_map` is built once at TS start (`ts ts_xapp.cpp:889-891`).
- Use a fresh QP pod per run. QP persists model files under `src/<cid>` (`qp main.py:123-125`).
- QP must never return a prediction without the serving cell. TS dereferences `find()` without checking for the end (`ts_xapp.cpp:702-703`), which is undefined behaviour.
- R3 has to accept the persistence forecast. QP needs at least 10 distinct rows (`qptrain.py:90`); otherwise it returns `tail(1)` (`prediction.py:31`). That is inferred to be the normal case under a 1.6 s window.

**Automatic handover.**
- Use `--handoverMode=NoAuto` for M8–R3 by default. Every handover in the trace then joins one-to-one with an ACKed control on (imsi, target, seq).
- DynamicTtt plus `TakeUeHoControl` per UE (`lte-enb-rrc.cc:4470-4476`) is a realism option for R2/R3. It needs a separate attribution rule.

**M9.** Revert to `fresh-install`, then one unattended invocation up to the highest green rung. Each rung runs once and is compared with the dev-run golden on Q2 items 1–4.

**Confidence.** Medium-high for M8/R1. Medium for R2/R3.

### Q8. Rollback and the biggest risk

**Recommendation.**
- Put pacing behind one switch: the `hello.pacing` field plus an ns-3 attribute. The agent's E2 behaviour is identical in both modes.
- If lock-step fails at M8:
  - **Fallback A (default).** Free-run, proven in M5–M7, with controls read at each `EmitSample` service point on the sim thread and ACK on commit. M8 acceptance relaxes to "handover visible for every ACKed control, ≥ 2 gNBs, wire decode". Repeatability relaxes to "same (imsi, target) set; sim times may differ". Determinism is lost and the evidence must say so.
  - **Fallback B (scripted rungs only).** Freeze on the expected control. The harness passes the scripted seq list, and the barrier at those seqs waits for the control up to a hard cap of 30 s, then aborts. This is deterministic and insensitive to T, but it cannot serve R2/R3 (Q2).
- Not as fallbacks:
  - file-mode semaphores: they bypass E2 and fail the wire gate;
  - `RealtimeSimulatorImpl`: ns-3 runs 1.7–32× slower than real time.

**Biggest risk:** section 5, item 1.

**Confidence.** Medium.

## 4. Requested probes

**P-B0 (offline, no VM).** Re-check my numbers from committed evidence.
- Method:
  - `tshark -r <m6|m7>.pcap -d sctp.port==36422,e2ap -Y e2ap -T fields -e frame.time_epoch -e ip.src -e sctp.data_tsn -e e2ap.procedureCode -e sctp.srcport -e sctp.dstport`
  - The agent sends PPID 0, so without `-d` tshark 4.x decodes the frames as malformed X2AP.
  - Dedupe on (src, TSN). Pair the 199 M6 indications in order with the `"ts"` of kpimon's "Message received … RIC_INDICATION" lines in `m6-kpimon.log`, and pair each receive with the next "Wrote … InfluxDB" line.
  - Evidence: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m6/20261021T232516Z/` and `…/m7/20261021T233129Z/`.
- It measures the fixed RIC hops (Q2 table). It confirms T_floor = 1.0 s is dominated by jitter, not by the RIC.

**P-B1 (VM, from `f7-rerun-green`, no M8 code).** The rc path latency and the ack routing table.
- Install rc with NIST's `install_xapp_ric_control.sh`.
- Run default ns-3 free-run with the agents.
- Send 50 gRPC controls to `rc:7777` with grpcurl, spread across `ranName` values, while capturing on `docker0`.
- Record grpcurl send time → `RICcontrolRequest` on the wire. The agent only logs the request today.
- Dump rtmgr's routes with `GET http://service-ricplt-rtmgr-http.ricplt:3800/ric/v1/getdebuginfo` (port unverified). Check the `12041|-1` and `12041|<subId>` entries.
- Decisions:
  - T for R0/R1: if p99.9 is under 300 ms, T = 1.0 s stands.
  - It confirms the ack-routing claim (risk 1).

**P-B2 (VM, the brief's probe c).** Pause behaviour.
- During free-run with kpimon subscribed, `SIGSTOP` ns-3 for 120 s, then `SIGCONT`.
- Expected per my reading of the sources: no subscription delete, no `ErrorIndication`, no e2mgr state change, heartbeats continue, and indications resume with no re-subscription.
- Decision: if anything fires, cap T below that timer. Confidence that nothing fires is high, so this probe is optional.

**P-B3 (VM, at the start of R2, not before M8).** The TS/QP chain.
- Deploy TS (gRPC → rc:7777) and QP.
- Inject 30003 after Influx holds seq k. Measure trigger → `RICcontrolRequest` on the wire, including QP's first-call training.
- Decisions:
  - T for R2/R3;
  - whether QP's 1.2 s freshness constraint holds;
  - whether a warm-up step is needed.

**P-B4 (VM; overlaps lens C).** Measure M4-style timing for `--nMmWaveEnbNodes=2`.
- Decision: the run length for M8/R1 if the ≥ 2-gNB config is not the default 4.

## 5. Biggest risks (ranked)

1. **rc crashes on an ACK without `RICcontrolOutcome`, and RMR makes it intermittent.**
   - The crash path: `rcE2SmRc.go:134`, through `rcControl.go:90,345`. It fires only if the ack reaches rc within 2 s.
   - How acks are routed:
     - e2term sets the ack's RMR `sub_id` to `ricInstanceID` (`e2term sctpThread.cpp:2640, 2807`).
     - rc's instance IDs are 2, 4, 6, … because of a double increment (`rcControl.go:139-141, 146-154`; counter starts at 0, `rcTypes.go:25-31`).
     - submgr subscription IDs come from a FIFO pool 1..65534 (`submgr registry.go:107`). rtmgr routes `12041|<subId>` to the subscribing xApp (`rtmgr rpe.go:255-256, 278-279`).
     - So rc's acks can land at kpimon, which discards them (`kpimon control.go:668`).
     - Any other ack falls back to `12041|-1` (`rmr rtable_si_static.c:463-477`). One such route exists per xApp (`rpe.go:172-177`). The last one written wins (`rmr rt_generic_static.c:548-552`), and the order comes from iterating a Go map (`rpe.go:424`, `rtmgr/types.go:46`), so it is random.
   - The failure looks like a "flaky rc pod". During restarts, TS's gRPC calls fail, and R2/R3 controls are lost.
   - Mitigation:
     - always include a Format 1 outcome;
     - gate on rc RestartCount = 0;
     - gate on the wire.
   - O-RAN SC still lists "routing control ack to selected xApps" as open (Jira RIC-783, To Do).
2. **R3 is coupled to wall clock through QP's −1600 ms window.**
   - An empty window leaves the serving cell out of the prediction, which leads to TS's `end()` dereference (`ts_xapp.cpp:702-703`; undefined behaviour, outcome unverified).
   - A window spanning two steps makes QP's input nondeterministic.
   - Mitigation: the trigger waits for Influx seq k; T + t_step ≥ 2 s; P-B3.
3. **The start is nondeterministic** without the readiness barrier: samples before the subscription are dropped, E2Setup takes about 3 s, and kpimon's poll phase adds 0.25–5 s.
4. **Agent blocking.** If the agent waited on ns-3, submgr's 2 s × 2 timer would delete subscriptions internally. The design rule is that the agent never waits.
5. **xApp state leaks between repeat runs.**
   - QP model files (`qp main.py:123-125`);
   - TS's static `cell_map`;
   - rc's instance counter (reset only by a pod restart);
   - submgr subscription IDs grow across runs, which changes ack routing.
   - Mitigation: restart rc, TS and QP before each repeat run. kpimon and the platform may stay.
6. **T too small under VM load.** Late controls taint runs. T is measured per rung, a late counter is kept, and the repeat gate requires 0.
7. **Modelling caveat.** Lock-step makes the RIC infinitely fast in sim time: a control decided on step k data is applied at t_k. An optional sim-time actuation delay `d_sim` (0 or one period) keeps determinism and adds realism. This is a user decision.

## 6. Unresolved questions

1. **Delay knob.** Should a sim-time actuation delay `d_sim` exist, with default 0 or one period? (User modelling choice.)
2. **Late controls.** Drop and fail them (recommended), or apply them late? Either way the run is tainted.
3. **Option B.** Honour kpimon's 10 000 ms literally, or allow a harness override (Q5)?
4. **Handover mode for R2/R3.** NoAuto (recommended), or DynamicTtt plus `TakeUeHoControl`?
5. **Spec version.** I read the Ack-Request-absent semantics in E2AP R004 v08.00. The v02.xx/v03.01 prose is unread, though the ASN enumeration is identical.
6. **Handover-complete trace source.** Which ns-3 trace source should M8 gate on? That is lens C's call.
7. **Unmeasured latencies.** rc/TS/QP chain latency and QP first-call training time (P-B1, P-B3).
8. **rtmgr debug port.** 3800 is unverified for P-B1.

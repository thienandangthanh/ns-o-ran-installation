Blindness: I did not read any `plans/reports/counsel-261022*` or `plans/reports/research-261022*` file. Brief SHA `552a58fb2854c4e5eb889ecc25d31852a91496bf`. Lens A: determinism and repeatability first.

# Counsel A: pre-M8 pacing, determinism and repeatability first

Date: 2026-10-22. Advisory only. Runtime: Opus 5.5 (the caller set `model: opus`), not `fable`. Paths are relative to the repo root. Upstream links are pinned to the SHAs in the brief §1. `(unverified)` marks an inference I did not check against source or a run.

## 1. Executive recommendation

1. **Mode: pacer-gated lock-step, with one step equal to one KPM period (0.1 s sim).** ns-3 is the only time base. A harness *pacer* grants each step. The RIC never acts as a clock, and wall clock is used only for failure deadlines, plus one quiet window in R3.
2. **ns-3 blocks in one sim-thread gate event per period.** The gate runs after every node has emitted. It polls all the agent sockets and the pacer socket. Controls are applied only when the gate releases, in a canonical order. There is no IPC thread and no cross-thread `ScheduleWithContext`.
3. **Agents never block.** Each agent reports `step{k}`, meaning "sample k was forwarded to a live subscription". In a gated run, any drop aborts the run.
4. **T detects failures; it is not a semantic knob.** When T expires, the run freezes and then fails, with the verdict "non-repeatable". Never drop a control. "Continue and flag" exists only for demo mode.
5. **Repeat gate.** Over 3 runs, the control ledger and the normalized ns-3 trace digest must be bit-identical. A replay oracle and an `RngRun` non-vacuity check complete the gate. M8, R0, R1 and R2 can meet this by construction.
6. **R3 caveat.** The NIST-patched QP reads a wall-clock window, `range(start: -1600ms)`. Under lock-step at the default config, QP falls back to predicting the last value. At the 1-gNB config, its behaviour can change from run to run. A bit-repeatable R3 needs a user decision.
7. **A per-run reset of RIC state (rc, QP, TS, Influx) matters as much as pacing does.**

### 1.1 Baseline evidence I produced offline from committed evidence (no VM)

These comparisons ground everything that follows. They show that free-running ns-3 is a deterministic function of its binary, its arguments and its seed. Wall-clock disturbances do not leak into sim state.

| Comparison | Result |
|---|---|
| sha256 of every trace file, M4 default `r1`/`r2`/`r3` (`plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m4/20261021T165230Z/timing/default/`) | 40 files byte-identical, including `UeHandoverEndStats.txt`, `RxPacketTrace.txt` and `MmWaveSinrTime.txt`. `DlE2RlcStatsLte.txt` differs only in columns 5–6 (RNTI, LCID) on 9 rows, all CellId 4 / IMSI 11. The values look uninitialized (unverified). With those two columns cut, all 3 runs are identical. |
| IPC `sample` lines, same 3 runs, nodes 1–5 | identical, raw |
| `sample` lines with `ipcDropped` removed, sim time < 9.8 s: M4 dev vs P8 M4 (rebuilt from fresh-install, `m4/20261021T225423Z`) vs three M7 runs under the live RIC (`m7/20261021T181249Z`, `184727Z`, `233129Z`) | 98/98 per node identical |
| The same comparison across the three M7 runs, sim time < 41.8 s. These runs include e2term pod deletes, agent restarts and drop counts of 1, 3, 4, 8 and 9 per node (their `bye` lines) | 418/418 per node identical. The handover traces (`UeHandoverEndStats`, `CellIdStatsHandover`, `EnbHandoverStartStats`) are identical too: 365 handovers. |

**Conclusion.** The only external input to ns-3 is a control. Closed-loop determinism therefore reduces to determinism of the *control ledger*: for each applied control, the step, the apply sim time, the IMSI, the target and the outcome. Pacing has two jobs: make that ledger a deterministic function of ns-3's outputs, and make any violation detectable.

Fields that vary run to run and must be normalized:
- `hello` (wall-clock `simStartEpochMs` from `ns-3-mmwave-oran/src/mmwave/helper/mmwave-helper.cc:3312-3317`, and the runId containing the pid, from `oran-interface/model/e2-ipc-emitter.cc:83`);
- `ipcDropped` (`e2-ipc-emitter.cc:113-115`);
- the two `DlE2RlcStatsLte` columns.

## 2. Answers Q1–Q8

### Q1. Mode, clock master, step

**Recommendation.** Use lock-step with three distinct roles:
- **ns-3 is the time master.** It is the only source of time-stamped content.
- **The harness pacer is the advance master.** It sends "go" for each step.
- **The RIC is a function evaluated inside a step.** It is never a time source.

One step is **1 KPM period** (0.1 s sim). Reject k > 1: in the pacer-gated design a step with no trigger costs only milliseconds, so coarser steps gain nothing and coarsen when a control can take effect. Reject real time for gates. Keep the M5–M7 free-run as the demo mode.

**Reasoning.**
- **Why control is the only input.** Section 1.1 shows ns-3 is deterministic when no control is applied. In this stack every control is caused by a trigger that the harness injects:
  - TS sends a prediction request only from `ad_callback`, on RMR 30003 ([ts_xapp.cpp:785-799](https://github.com/o-ran-sc/ric-app-ts/blob/19e169b/src/ts_xapp/ts_xapp.cpp#L785-L799)).
  - TS sends a control only from `prediction_callback` ([:726-729](https://github.com/o-ran-sc/ric-app-ts/blob/19e169b/src/ts_xapp/ts_xapp.cpp#L726-L729)).
  - rc sends 12040 only for a gRPC request ([rcControl.go:101-141](https://github.com/o-ran-sc/ric-app-rc/blob/a2282ee/control/rcControl.go#L101-L141)).
  - A1 only sets a threshold ([ts_xapp.cpp:509-524](https://github.com/o-ran-sc/ric-app-ts/blob/19e169b/src/ts_xapp/ts_xapp.cpp#L509-L524)).
- **What follows.** The pacer knows which steps can produce controls, and can release every other step at once.
- **Prior art.** ns-o-ran-gym makes the controller the master and lets ns-3 wait forever (`ns-3-mmwave-oran/src/lte/model/lte-enb-net-device.cc:115-127`; `ns-o-ran-gym/src/nsoran/ns_env.py:354-375`). That is deterministic because the controller answers *every* step. Stock xApps never answer "no control", so the pacer has to supply that answer.
- **Why not real time.** The default config is 32× slower than real time, and the 1-gNB config 1.7× slower (brief §2). Under real time, the sim time at which a control takes effect depends on wall-clock arrival, so it cannot repeat by construction.

**Alternative D1** (no pacer; each agent holds `step{k}` for a quiet window W on every step): it is statistical only, and it costs W on every step (Q2).

**Confidence.** High for the mode and the step. Medium for where the pacer lives: it could be folded into the agents at D1's cost.

### Q2. How T is set, what happens when it expires, and the repeat gate

**Recommendation.** Use three deadlines. None of them uses the step compute time c (0.17 s or 3.2 s): their clocks start only when ns-3 is blocked at the gate.

| Deadline | Applies to | Formula | Start value |
|---|---|---|---|
| T_gate | Every step: all agents' `step{k}` and the pacer's `go` | max(10 s, 20 × max observed gate latency) | 10 s. A normal forward takes ms (estimate, unverified). |
| T_ctl | Trigger steps where the expected number of controls is known (R0, R1, R2 positive cases) | max(30 s, 20 × L_max), where L = trigger injected → `control` received by ns-3 | 30 s, re-set from R0's measured L |
| W (quiet window) | Only where the *absence* of a control must be confirmed (R2 negative cases, R3) | max(1 s, 10 × p99 of L_post), where L_post = last observable (QP prediction rows visible) → `control` at ns-3, measured over ≥ 30 triggers at R2 | 1 s |

- **Wall budget per run, pacer-gated:** steps × (c + ε) + Σ over trigger steps of (L + W), where ε is a few ms (unverified).
  - Default config: about 32 s per sim second, the same as free-run.
  - 1-gNB config: about 1.7–1.8 s per sim second.
- **D1 for comparison,** with W = 0.5 s on every step:
  - default 10 × (3.2 + 0.5) = 37 s per sim second (+16 %);
  - 1-gNB 10 × (0.17 + 0.5) = 6.7 s per sim second (×3.9).
- **D1 with lag-1 overlap,** where a control is applied at the next boundary: the wait is max(0, W − c). That is free at default and 5 s per sim second at 1-gNB. It is still statistical.

**What happens on expiry, and what it means for determinism:**

| Option | Determinism | Repeat gate it allows |
|---|---|---|
| **Freeze, then fail** (recommended for gates). Hold, and at T abort with the verdict "step k deadline". | Bit-identical, or no verdict at all. A violation can never pass silently. | Bit-identity of the ledger and the digest |
| Continue and flag (demo or exploration). Release at T; a late control applies at the next boundary with `flags:[late]`. | Statistical. The ledger can shift by whole steps. | Distribution or margin only. Honest only if late = 0 is reported. |
| Drop the late control | Worst. The ledger loses an entry silently, and the run differs from the RIC's view (rc logged it as sent). | None. Reject. |

**Repeat gate (per rung):**
1. **N = 3 runs** from the same snapshot, with the same args, an explicit `--RngRun`, and the per-run RIC reset (Q7).
2. **Compare the ledger exactly:** (k, applySimTimeNs, viaNodeId, imsi, sourceCell, targetCell, outcome, cause).
3. **Compare the ns-3 digest:** the sha256 of every trace file. In the IPC traces, take only the `sample` lines, with `ipcDropped` asserted to be 0. In `DlE2RlcStatsLte`, cut columns 5–6.
4. **Compare the decoded E2SM-RC header and message,** and the E2SM-KPM indication messages joined on (nodeId, seq).
5. **Replay oracle, once:** feed the ledger to ns-3 with no RIC and get the same digest.
6. **Non-vacuity:** `RngRun=2` must change the digest.
7. **Margin report:** the minimum slack (deadline − arrival) for every wait, and the count of late or unsolicited controls, which must be 0.

**Why 3 runs.** Bit-identity is a deterministic claim: one mismatch falsifies it, and the replay oracle localizes the cause. A run takes minutes (5 sim s at default ≈ 2.7 min).

**Confidence.** High for the semantics and the gate. Medium for the numbers: the RIC chain latency has not been measured.

### Q3. Getting a control into the ns-3 thread

**Recommendation.** Poll the emitter sockets from a sim event. Do not use `ScheduleWithContext` from an IPC thread.

**Why not the IPC thread.** In ns-3.38, a cross-thread `ScheduleWithContext` is memory-safe: it takes a mutex (`ns-3-mmwave-oran/src/core/model/default-simulator-impl.cc:260-272`). But the event's time becomes `m_currentTs` at whatever moment the sim thread next calls `ProcessEventsWithContext` (`:147`, `:157-182`). That makes the apply time a function of wall-clock arrival, so it cannot repeat. Validating RRC state from the IPC thread would also be a data race.

The old legacy path already did this. It called `TakeUeHoControl` on the e2sim thread, which mutated `m_e2ControlledUes` while the sim thread iterated it: `lte-enb-net-device.cc:434-443` (compiled out, `:406-465`) and `lte-enb-rrc.cc:4690`.

**Where a step blocks: ns-3 only.** One gate event per period, at a fixed phase after the last emitter. The M4 traces show the LTE eNB at k·P + 0.5 ms and the gNBs at k·P + 0.8 ms, so for example k·P + 1 ms. At the gate:
1. Block in `poll()` over the 5 agent sockets and the pacer socket.
2. Buffer every `control`.
3. Wait for `step{k}` from every agent, then send `step ready` to the pacer.
4. On `go`, sort the buffer canonically, by (imsi, then viaNodeId, then the per-socket order).
5. Validate, `Schedule(applyDelaySim)` each control, write the ledger, send a `controlAck` per control, and return.

**Rules around the gate:**
- **Agents never block.** Their loop must keep serving SCTP and E2 (`.../ns3_e2_agent/src/main.cpp:144-176`).
- **Bytes read elsewhere are only buffered.** `Drain()` runs from `EmitSample` (`oran-interface/model/e2-ipc-tcp-client.cc:49-67,143-168`); anything it reads there is buffered, never applied.
- **The canonical sort is mandatory.** rc sends each control in its own goroutine ([rcControl.go:141](https://github.com/o-ran-sc/ric-app-rc/blob/a2282ee/control/rcControl.go#L141)), so the order in which controls cross sockets is not defined.
- **Late and unsolicited controls are flagged.** A control that arrives while ns-3 is not held, or for a step already released, is flagged and fails the gate.

**Message shapes** (NDJSON, schema minor bump):

| Message | Direction | Fields |
|---|---|---|
| `control` | agent → ns-3 | `nodeId`, `ctlId` (agent-local, monotonic), `e2{requestorId, instanceId, ranFuncId}`, `style`, `action`, `imsi` (from AMF-UE-NGAP-ID), `targetCellId` (integer decoded from the NR CGI), `diag{}` |
| `controlAck` | ns-3 → agent | `nodeId`, `ctlId`, `outcome` (accepted or rejected), `cause`, `k`, `applySimTimeNs` |
| `step` | agent → ns-3 | `nodeId`, `k` (= sample seq), `forwarded` (bool), `reason`, `indications` |
| `step` | ns-3 → pacer | `phase` `ready` with `k`, `simTimeNs`, the `forwarded` map and the buffered controls; or `phase` `controlRx` |
| `step` | pacer → ns-3 | `phase` `go` with `k` (optionally `expect`: n), or `phase` `abort` with `reason` |

- `diag{}` (agent wall-clock receive time) is informational only; ns-3 never reads it.
- Wall-clock fields appear only inside `diag` and are excluded from digests.

**Confidence.** High.

### Q4. Timers while sim time is paused

**Recommendation.** No RIC timer that is driven by E2 procedures reacts to a paused ns-3, provided the association stays up (one point unverified; probe C below). The "timers" that do change content are the **wall-clock data windows in QP and AD**.

| Timer | Behaviour while ns-3 is held | Effect on determinism | Source |
|---|---|---|---|
| SCTP heartbeat (5 s) | Kernel-level, runs regardless | none (decoupled by design) | brief §3 |
| Agent timers | `tick()` does nothing in READY | none | `.../ns3_e2_agent/src/e2-session.cpp:32-43` |
| submgr: `e2tSubReqTimeout_ms` 2000, 2 tries; `checkE2State` true | Active only during a subscription or delete. The agent answers those from its own loop whatever ns-3 is doing | none | [submgr-config.yaml@0.10.2](https://github.com/o-ran-sc/ric-plt-submgr/blob/0.10.2/config/submgr-config.yaml); `e2-session.cpp:121-171` |
| kpimon 5 s poll | Re-subscribes only after seeing the node not CONNECTED; a pause does not disconnect | none | [control.go:1110](https://github.com/o-ran-sc/ric-app-kpimon-go/blob/8bbbbbb/control/control.go#L1110) (stock numbering; the NIST patch shifts it about +20) |
| rc 2 s ack timer | Only logs on expiry. An ack can also lose a race with the timer's registration (`rmrSend` comes before `setEventRicControlCreateExpiredTimer`), which only logs too | none on the wire or in the ledger | [rcControl.go:156-196,302-310](https://github.com/o-ran-sc/ric-app-rc/blob/a2282ee/control/rcControl.go#L156-L196) |
| e2term / e2mgr idle detection | None known (unverified) | Must be verified | probe C |
| **QP** `range(start: -1600ms)` on wall-clock `_time` | Data visible to QP = rows written in the last 1.6 s of wall time | **First-order, R3** | `O-RAN-Testbed-Automation/.../install_patch_files/xApps/qp/src/database.py.patch:98`, applied by `.../additional_scripts/install_xapp_qoe_predictor.sh:111` |
| **AD** `schedule.every(0.5).seconds` with `time>now()-1600ms` | Periodic on wall clock | Real AD cannot be used in a repeatable rung | [ad main.py:44](https://github.com/o-ran-sc/ric-app-ad/blob/f9f97b8/src/main.py#L44), [database.py:87-94](https://github.com/o-ran-sc/ric-app-ad/blob/f9f97b8/src/database.py#L87-L94) |

**Confidence.** Medium. The QP and AD rows are high, because I read the code. The e2term and e2mgr row stays unverified until probe C.

### Q5. Subscription option B on sim time

**Recommendation.**
- **Sim-time windows.** Aggregation windows are global and aligned to sim time: window w = floor(simTimeNs / reportPeriodNs). The report period is m whole KPM periods, with m = round(reportPeriod / P), and the agent rejects or rounds a non-integer m by a fixed rule.
- **When reports go out.** A report is emitted when the agent receives the sample whose `simTimeNs` closes the window. It is never emitted on a wall-clock timer, and windows are never measured from when the subscription arrived.
- **A subscription arriving mid-run** starts at the next window boundary, and a partial first window is skipped. This makes the content the same after a re-subscription.
- **Deterministic arithmetic.** Accumulate in seq order, use integers where possible, and never let concurrency reorder a floating-point reduction.
- **The agent sends `step{k}` for every sample**, including samples it only accumulated (`forwarded: "aggregated"`). The barrier is then independent of report boundaries.
- **Pacer triggers fall on report-boundary steps.** One step stays one ns-3 period.
- **The header follows the existing rule.** `colletStartTime` is already derived from sim time plus the epoch (`.../ns3_e2_agent/src/sample-forwarder.cpp:62-66`); keep the window start on that rule.

**A cross-dependency to record.** Suppose option B honours kpimon's requested period (granulPeriod 10000 ms, contract Q2 answer). The RIC then sees one report per 100 steps. At 3.2 s of wall time per step, that is about 320 s of wall time between reports, so QP's 1.6 s window is almost always empty. **Keep option A for R2 and R3** unless the QP window changes.

**Confidence.** High for the rules. Medium on what kpimon's period field actually means (whether it is a reporting period or a granularity, unverified).

### Q6. RC ack semantics

**Recommendation.** Validate when the gate releases, at sim time t_k^gate, in canonical order, and then:
- send a **RICcontrolAcknowledge** once ns-3 has accepted the control and scheduled the handover;
- send a **RICcontrolFailure** with a cause for a refusal.

The outcome is then a pure function of sim state, never of wall time.

**Handover completion stays off the wire.** It goes to the ledger, joined with the `UeHandoverEndStats` row.

**ns-3 must pre-validate these refusals**, because `PerformHandoverToTargetCell` only logs, or crashes:
- **Unknown IMSI.** `GetRntiFromImsi` returns 0 (`ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:3619-3629`), and then `GetUeManager(0)` fails `NS_ASSERT` (`:3579-3585`). That aborts the default build and is undefined behaviour in an optimized build.
- **Handover already in progress.** `m_mmWaveCellSetupCompleted[imsi]` is false; the code only logs (`:4522-4527`).
- **UE not associated** (`:4528-4531`).
- **UE already on the target.** The old file path skipped this (`lte-enb-net-device.cc:180-188`).
- **Unknown target cell.**
- **Duplicate IMSI in the same step.** The first in canonical order wins.

The agent rejects an undecodable E2SM-RC itself.

**Why not "ack on queue".** Old ns-O-RAN always acknowledged (fact pack §1). That hides refusals and makes the wire useless as evidence. Acking on completion would arrive steps later, can fail late, and adds tracking for no gain in determinism.

rc only logs acks (fact pack §5; [rcControl.go:322-387](https://github.com/o-ran-sc/ric-app-rc/blob/a2282ee/control/rcControl.go#L322-L387)). With the pacer, the ack goes out within ms of arrival on positive-count steps; in R3 it goes out after W.

**Confidence.** High.

### Q7. Changes to the M8 / R0–R3 / M9 acceptance criteria

**Recommendation** (adds to the contract's acceptance criteria; nothing is removed):

**Common to all rungs**
- **The new control ledger is ground truth.** It sits in ns-3's trace directory, holds the fields from Q2, and its `diag` field is excluded from digests.
- **Per-run reset, before ns-3 starts:**
  1. Restart rc. Its `ricRequestInstanceID` is a counter for the pod's lifetime, and each request increments it twice ([rcControl.go:139-153](https://github.com/o-ran-sc/ric-app-rc/blob/a2282ee/control/rcControl.go#L139-L153)).
  2. Restart QP. It keeps `src/<cid>` model files ([main.py:123-125](https://github.com/o-ran-sc/ric-app-qp/blob/47a35ca/src/main.py#L123-L125)).
  3. Restart TS **after** every agent is CONNECTED, because `cell_map` is built only at start-up ([ts_xapp.cpp:826-872,890](https://github.com/o-ran-sc/ric-app-ts/blob/19e169b/src/ts_xapp/ts_xapp.cpp#L826-L872)). Then set the A1 threshold explicitly; it is a global for the process lifetime (`:96`, `:523`).
  4. Give Influx a fresh bucket, or delete the measurements.
  5. Wait until every agent is READY with at least 1 subscription. Agents drop samples before that (`.../ns3_e2_agent/src/main.cpp:78-85`).
- **Wire normalization.** Compare decoded E2SM content. Exclude E2AP request and transaction IDs (from submgr and rc counters) and the KPM header `colletStartTime` (wall-clock epoch). Optionally pin `simStartEpochMs` in gated runs, which makes the header bytes identical too.

**M8 / R0** (scripted rc gRPC, real rc)
1. **Null-control equivalence.** Lock-step with no controls gives the same digest as free-run with the same args, at the default and 1-gNB configs. This proves the gate does not perturb ns-3.
2. **Controls.** At least 2 IMSIs, steered to at least 2 different gNB targets, injected at declared steps. Pick each target from the step-k sample's `l3.servCellId` so that target ≠ serving.
   - On the wire: a decoded RICcontrolRequest (E2SM-RC v2.0 header gNB_UEID, message Target Primary Cell NR CGI) and a RICcontrolAcknowledge.
   - In the ledger: accepted.
   - In the handover trace: a start/end row for that IMSI to that target within Δ_sim of the apply time (verify the column semantics).
3. **One deliberate refusal,** such as a UE already on the target. This gives a RICcontrolFailure with a cause, a "rejected" ledger entry and no handover.
4. **Repeat gate** from Q2: 3 runs, plus the replay oracle and the non-vacuity check. Late controls = 0.

**R1** (scripted, 2 or more gNBs)
- Controls go through different agents (any-node routing).
- Include one **same-step pair** of controls for two IMSIs, which exercises the canonical sort.
- **Unverified prior hint** from the dead-end project: the LTE master RRC serializes EN-DC handovers. Treat it as a hypothesis the R1 trace will confirm or refute. It is deterministic either way.

**R2** (real TS, stub QP, AD-style 30003 stub driven by the pacer)
- The expected control count is known from the stub's predictions, so positive cases are bit-identical.
- Negative cases are confirmed with W and labelled statistical.
- TS must use gRPC, pointing at rc:7777.

**R3** (real TS, real QP)
- **State the regime.** At the default config, the 1.6 s window holds exactly the latest step's rows, so QP takes `constant()` (< 10 rows, [qptrain.py:81-92](https://github.com/o-ran-sc/ric-app-qp/blob/47a35ca/src/qptrain.py#L81-L92)) and predicts the last value ([prediction.py:31-34](https://github.com/o-ran-sc/ric-app-qp/blob/47a35ca/src/prediction.py#L31-L34)). The VAR model never trains.
- **Do not run R3 at the 1-gNB config.** There the 1.6 s window holds about 9 rows, right at the ≥ 10 threshold, so QP can change behaviour run to run.
- **The gate requires** the time from the step's rows being written to QP's query to be below 1.6 s minus a margin, and reports that margin.
- **"Bit-repeatable R3"** needs one of these user decisions:
  - (a) patch QP's window to a row-count window on a fork;
  - (b) have the R3 adapter rewrite the last N steps with `_time` compressed into the last 1.6 s (unverified idea).
- **Without either decision,** label R3 "statistically repeatable".
- **TS has a crash path.** If the trigger reaches QP too late, QP returns empty predictions, and TS dereferences `end()` ([ts_xapp.cpp:702-703](https://github.com/o-ran-sc/ric-app-ts/blob/19e169b/src/ts_xapp/ts_xapp.cpp#L702-L703)). That aborts the run.

**M9**
- The top rung runs 3 times inside the unattended invocation.
- Its ledger and digest must **equal the dev-run reference** for that rung. Cross-install equality already holds for free-run (section 1.1: P8 equals dev).

**Automatic handover policy.** Keep the default `DynamicTtt` and call `TakeUeHoControl` per controlled UE. The call is permanent and removes that UE from automatic handover (`lte-enb-rrc.cc:4470-4475,4690-4694`). The free-run default has 89 automatic handovers in 10 sim s (M4 `UeHandoverEndStats.txt`), so the gate attributes a handover by (imsi, target, start within Δ_sim of apply). Use `--handoverMode=NoAuto` only as a diagnostic run, where the handover count equals the accepted count.

**Confidence.** High for the gate structure. Medium for the handover policy. Medium-low for option (b) of R3.

### Q8. Rollback, and the biggest risk

**Recommendation.**
- **Pacing sits behind a flag whose default is off,** which is exactly the M5–M7 behaviour. Null-control equivalence proves that "on" with no controls gives the same result as "off".
- **If lock-step fails at M8:**
  1. **Diagnose with the replay oracle.** A replay digest that differs from the live one means the ns-3 control path is nondeterministic; fix it there. Ledgers that differ between runs mean an arrival or pacing problem; read the late flags and the slack.
  2. **Fallback A, scripted lock-step without the RIC.** The pacer injects `control` directly. This is deterministic and proves the ns-3 half.
  3. **Fallback B, free-run with controls applied at the boundary after arrival** (the "continue" semantics). This meets the contract's M8 (rc control → handover in the trace). The repeat gate drops to "the same (imsi, target) handovers in every run, while the step may differ", labelled non-repeatable. The user decides whether to accept it.
  4. **Environment and code.** Revert to `f7-rerun-green`; reset the fork branch.
- **Biggest risk:** see section 4, item 1.

**Confidence.** High.

## 3. Requested probes

| Probe | Method | What it measures | Decision it changes |
|---|---|---|---|
| **P-A (offline, already run)** | Recompute the section 1.1 comparisons: per-file `sha256sum` across `.../m4/20261021T165230Z/timing/default/r{1,2,3}`, and `sample` lines without `ipcDropped` across M4 dev, P8 M4 and the 3 M7 runs. Commit the output as evidence; I cannot write evidence files. | Baseline free-run determinism, and the normalization list | Grounds the ledger-based gate. If it ever failed, bit-identity would be off the table. |
| **P-C (VM, from `f7-rerun-green`)** | In the M7 setup, `kill -STOP` ns-3 for 60 s, 300 s and 900 s, then `-CONT`. Capture on docker0 and poll e2mgr. | Whether heartbeats continue; 0 ABORT/SHUTDOWN; no new RICsubscriptionRequest or Delete; no ErrorIndication; node CONNECTED; agent RestartCount 0; next indication seq = last + 1 | If the RIC reacts after X s, T_gate and T_ctl must stay below X and long R3 holds become infeasible. If it is clean at 900 s, freezing is safe for any T. |
| P-OPT (VM, optional) | Optimized-profile build: run the timing and **compare digests against the default-profile digests** | Speed, and whether results are the same across profiles | Only if the digests are equal can the optimized build replace the default without re-baselining. Profiles also differ on asserts (`NS_ASSERT` in `GetUeManager`). Never use `-march=native`. |
| P-RNG (fold into M8) | 1-gNB, 10 s, `--RngRun=1` vs `2` | Non-vacuity | none; it is a gate check |
| P-B (pcap proxy) | **Decline.** Subscription-response latency measures the agent's processing, not the rc → e2term → agent chain. | — | None of my recommendations. Measure L at R0 through gate instrumentation instead (gRPC call → 12040 on docker0 → `control` at ns-3). |

## 4. Biggest risks (ranked)

1. **The R3 xApps assume real time.**
   - The NIST-patched QP uses a `-1600ms` wall window, and AD runs on a 0.5 s wall schedule.
   - So R3 cannot be bit-repeatable without a decision.
   - At the default config, QP degenerates to predicting the last value; at the 1-gNB config it can flip at the ≥ 10-row threshold.
   - TS has undefined behaviour when the prediction is empty.
2. **RIC state carried between runs** (the rc counter, QP model files, TS `cell_map` built at start-up and its A1 threshold, Influx rows). Without the reset protocol, run 2 differs from run 1 even with perfect pacing.
3. **rc's ordering and acknowledgements.**
   - It dispatches each control in its own goroutine, so the order across controls is undefined.
   - A gRPC `rspCode 0` is returned before validation ([rcService.go:39-52](https://github.com/o-ran-sc/ric-app-rc/blob/a2282ee/control/rcService.go#L39-L52); validation at [rcControl.go:118-137](https://github.com/o-ran-sc/ric-app-rc/blob/a2282ee/control/rcControl.go#L118-L137)).
   - So: count controls at ns-3, never gRPC successes, and the canonical sort is mandatory.
4. **An agent or e2term failure mid-run breaks exactly-once delivery.** The agent `exit(2)`s and loses its state. Gated runs must abort.
5. **Hidden nondeterminism in the ns-3 control path,** for example pointer-keyed containers in X2 or handover code (unverified). The 3-run gate and the replay oracle catch it.
6. **The RIC may react to long holds** (unverified). Probe C settles it.

## 5. Unresolved questions

1. **R3:** bit-repeatable (QP window patch, or adapter time compression) or statistically repeatable with stock QP? This is the user's call.
2. **Default gate semantics:** freeze-then-fail (recommended) or continue-and-flag?
3. **Pacer placement:** is a fourth IPC peer, the harness pacer socket, acceptable? Or must pacing live in the agents (D1, which costs W on every step)?
4. **The 30003 trigger for R2/R3:** an AD-style stub needs an RMR route. Real AD is periodic on wall clock and incompatible with a repeatable rung.
5. **Handover trace columns:** which ones to match on (verify).
6. **Should gated runs pin `simStartEpochMs`** so the KPM header bytes are identical?

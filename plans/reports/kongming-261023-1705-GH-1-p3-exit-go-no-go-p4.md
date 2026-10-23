# kongming: P3-exit go/no-go on P4 (R1, fault run (ii), Stop A)

Date 2026-10-23 ~17:30 KST. Model: Opus 5.5 (as routed by the caller). Advisory only; never user approval.
Verified against: harness HEAD `77f855f`; pinned forks fetched fresh into the scratchpad (oran-interface `63155c49`, ns-3 `962fabc7`, Testbed `4c8397d0`); rc `a2282ee` (o-ran-sc/ric-app-rc); R0 green evidence `evidence/r0/20261023T073520Z`; S1 evidence `evidence/s1/20261022T191853Z`. The local fork checkouts in the worktree are stale (oran-interface `438a839`, ns-3 `ace32168`, Testbed `725b167`) and were not used.

## TL;DR
- **GO for P4**, with 11 must-do items done before the first R1 gate (ordered list in §6). Every item is a harness change. No fork change is needed.
- **Fault run (ii) needs neither P2-deferred fork change.**
  - It can be met deterministically at the current pins. The pacer sends the control after ns-3's `stopping`, through the **eNB agent (node 1)**, and holds `endAck` until the agent has forwarded it.
  - The result is exactly one RICcontrolFailure from agent 1's bye path, with 0 ledger lines.
  - The earlier advice (my P1-exit R4: "DrainAll in the stop loop", recorded as "P4 fault run (ii) needs both") was **wrong in direction**. That change would make ns-3 read the control and write a `late` ledger line, so it would break V4. Correct the note. Do not implement it.
- **Three harness defects would make R1 red by construction.** Fix them before any run:
  - the schedule builder keeps only one control per step;
  - the KPM UE-list checker fails a refused line whose IMSI moved because of the same-step applied line (cases b and c);
  - rc sends each control in its own goroutine, so a same-agent pair can swap ctlIds between runs, and the C1 ledger digest goes red at random.
- **Case (b) yields `inHandover`, not `alreadyOnTarget`.** Verified at the pin: the in-handover check comes before the target comparison. Send target 3 **first** so the cause proves the C4 sort rather than arrival order.
- **Gate r1 should be a new script that copies gate r0's run loop. Do not edit gate r0.** This follows the S0/S1 precedent. Shared Python tools get only additive changes, and each one is regression-checked byte-equal on R0's green evidence.

## 1. Reframed problem
The decision is not just "start P4". It is how to reach R1 C1 plus fault run (ii) without three things:
- moving the fork pins, which would cost M5–M7, the free-run digest and R0 re-validation;
- invalidating R0's green evidence;
- spending the one-fix budget on harness defects (Failure Protocol → T6).

Constraints: the locked contract (C1–C9, R1 cases, (ii) "exactly one FAILURE", C2 identity with static and post-bye counted separately), the K5 amendment, "never weaken a test", and no `r1-green`.

## 2. Q1: GO / NO-GO
**GO.** P3 exit is clean on the evidence:
- R0 green at `073520Z` (109/109, V1–V9);
- calibration provenance in `rung-config.json`;
- `r0-green` taken;
- no fork change pending.

The open problems are all harness-side and can be fixed host-side before the VM is touched. Must-do list in §6.

## 3. Q2: P4 design

### 3.1 Gate r1 vs gate r0 (recommendation: copy the loop, share the tools)
- **Do not modify `gate-r0-rc-scripted.sh`.** Write the r1 gate as a new script that sources the same libraries (`lib.sh`, `bringup.sh`, `capture.sh`, `kpimon.sh`, `agents.sh`, `rc-lib.sh`, `paced-lib.sh`). It carries its own copy of `r0_live` and the fact blocks, with the R1 deltas listed below.
  - Precedent: "Gate S1 keeps its own build helper (a copy of S0's) … so S0's passed evidence stays tied to unchanged code" (implementation-notes, P2 tradeoff).
  - Re-running R0 C1 after a refactor would put a green C1 back at risk for no contract gain.
- **Name mismatch, fix first.** `scripts/run-to-m9.sh:62` already calls `gate-r1-rc-multi.sh`, but phase-04 says `gate-r1-rc-multi-control.sh`. Pick one name and make both agree.
- **Shared Python tools: additive changes only.** Each change gets a regression on `073520Z` that shows identical output for R0's inputs:
  - `pacer.py`
  - `r0-checks.py` (`schedule`)
  - `tools/e2-evidence/kpm-ue-list-moves.py`
  - `r0-run-facts.py`, if the fault-run label needs it
- M9 will run gate r0 in single mode at the final harness anyway. So the requirement is "R0's behaviour unchanged, proven by fixture", not "files untouched".

**R1 deltas compared with gate r0**
1. **Threshold.** Read it from `rung-config.json` (after must-do 2), and assert that its provenance names `evidence/r0/`. Do not re-run Q2.
   - Keep C8 (free == null lock-step at −1000). It costs about 2 ns-3 runs, and it keeps "C1–C9 hold" literally true in this rung's verdict.
   - No G4 and no K9 (both are R0-only).
2. **Live runs.** live1–3 use the R1 schedule. After live1, and before live2's reset deletes the bucket, run `influx-dump.sh` (V6; see §5 on T7).
3. **Fault run.** Add a fault run `f2` (§4), in `--mode c1` only, outside the digest set.
4. **Replay, rng2, C1 and the K10 facts** as in gate r0. Include `f2` wherever gate r0 lists `k9`: restart map, reset evidence, `facts_final`.
5. **New in-gate checks**, cheap and deterministic:
   - **No departure or reconnect.** ns-3's own end-of-run line per emitter shows `connects=1 droppedDisconnected=0`, and each agent's last stats line shows `ipc.accepted == 1` (`stdout.txt`: `E2IPC node N … connects=1`). This compensates for the hub counting an EOF node as done (§4.3).
   - **Non-vacuity of the C4 sort.** In step 30 the refused (target 3) line has a lower ctlId than the applied (target 2) line from the same agent. In step 40 the pacer log shows node 3's `controlRx` before node 2's.
   - **C2 split.** `staticRejects` (agent `rejFunc+rejDecode+rejAction+rejIpcDown`) = 0 and `postBye` (agent `failedOnBye`) are reported as separate fields.
6. **`--dev` flag**, so a rehearsal is labelled `dev: true` (see must-do 11).

### 3.2 R1 scenario (RngRun 1, `outageThreshold −1000`; start: IMSIs 1, 2 on cell 3; IMSIs 3–6 on cell 2)
List order within a step is the send order. The pacer sends the next control only after ns-3 has reported `controlRx` for the previous one (must-do 3).

| Step | Case | Send order (via → imsi → target, key) | Expected ledger line | Path |
|---|---|---|---|---|
| 20 | (a) | 1 → 6 → 3 (`0000000303`); then 3 → 1 → 2 (`0000000202`) | both `applied` (6: src 2; 1: src 3) | viaEnb; viaServingGnb |
| 30 | (b) | 2 → 2 → **3** (own cell, sent first, ctlId 1); then 2 → 2 → 2 (ctlId 2) | target 2 `applied` (src 3); target 3 `refused inHandover` (src 3, tgt 3) | viaTargetGnb |
| 40 | (c) | 3 → 3 → 3 (sent first); then 2 → 3 → 3 | via 2 `applied` (src 2); via 3 `refused inHandover` | viaServingGnb |
| 50 | (d) | 2 → 99 → 2 | `refused unknownImsi` (src 0) | — |

- **Ledger (C4 order per barrier).** 7 lines: 4 applied (IMSIs 1, 6, 2, 3) and 3 refused (2 × inHandover, 1 × unknownImsi). Agent ctlIds: node 1 {1}; node 2 {1, 2, 3, 4}; node 3 {1, 2}.
- **Wire.** 7 requests; 4 ACKs (Format 1); 3 FAILUREs with `control-failed-to-execute`. C2: 7 = 7 + 0.
- **D7.** viaEnb 1, viaServingGnb 2, viaTargetGnb 1, distinctImsis 4, targetGnbs [2, 3].
- **C9.** 4 HandoverStart rows and 4 HandoverEnd rows; none for the 3 refused lines.
- **kpmUeListMoved** = {1, 2, 3, 6} all true:
  - IMSI 6: 2→3 at k 20; IMSI 1: 3→2 at k 20; IMSI 2: 3→2 at k 30; IMSI 3: 2→3 at k 40;
  - IMSI 99 is absent in both reports (unchanged).
- **Final layout.** Cell 2 {1, 2, 4, 5}; cell 3 {3, 6}. Each IMSI is used in only one step, so no case depends on an earlier handover still being in flight.

**Why (b) gives `inHandover` (verified at ns-3 `962fabc7`):** `ApplyExternalHandover` checks, in order, `unknownImsi` (lte-enb-rrc.cc:4564-4567), `unknownTarget` (:4568-4571), **in-handover `!setup->second`** (:4574-4577), then already-on-target (:4583-4586), then LTE fallback (:4587-4590). The applied target-2 control sets `m_mmWaveCellSetupCompleted[imsi] = false` (:4606), while `m_lastMmWaveCell` stays 3 until the handover completes (comment :4572-4573).
- So the target-3 control sees `inHandover`, with sourceCell 3 and targetCell 3.
- Under arrival order (target 3 sent first) it would instead give `alreadyOnTarget`, and target 2 would be applied.
- So sending target 3 first makes the cause prove the C4 sort (hub sort at e2-control-hub.cc:248-251 is `imsi, viaNodeId, targetCellId, ctlId`).
- The S1 fb1 ledger already shows the same shape: imsi 6 via node 2, target 2 (own cell) → `inHandover`.
- (c) is analogous: by arrival order node 3 would win; by C4, node 2 wins.

### 3.3 Harness defects that would make R1 red by construction (verified)
1. **Schedule builder.** `r0-checks.py:33-41` sets `steps[str(step)] = …`, so a second control in the same step overwrites the first. Group by step, in list order. Emit the existing single `trigger` form when a step has one control, so the regenerated R0 schedule is byte-equal.
2. **Pacer.** It runs one trigger per step (`pacer.py:175-225`).
   - rc dispatches every control in a new goroutine (`rcControl.go:141`, `go …SendRicControlRequest`), after a FIFO channel (`:106`). Two quick gRPC calls can reach the agent in either order. The agent numbers ctlIds by arrival (`rc-control.cpp` `nextCtlId_++`). The ledger digest covers ctlId. So C1 for case (b) would be red at random.
   - Fix: add a `"triggers": [{cmd, expect}, …]` list per step. Run each command in turn, wait for the cumulative `controlRx` count within T_ctl of that command's start, record L per control, then send `go`. Leave the single-trigger path unchanged, because calibration's `tctl` expects `controls == 1`.
3. **KPM negative rule.** `kpm-ue-list-moves.py:127-138` requires a refused or late line to leave its IMSI's gNB membership unchanged between k and k+1. In (b) and (c) that IMSI moves, legitimately, because of the applied line in the same step.
   - Generalize per (imsi, k):
     - exactly 1 applied line → today's moved check;
     - 0 applied lines → membership unchanged;
     - ≥ 2 applied lines → a problem.
   - This is not weakening: for R0's shapes the output is identical, and the IMSI's motion stays fully constrained by the positive check. Record that reasoning in the notes, pre-empting the scope guard.
   - Also treat a missing ledger as zero lines (`:103` opens it unconditionally), as `check-ledger.py` and `check-c9` already do.

## 4. Q3: fault run (ii) at the current pins

### 4.1 Mechanism (verified in code and on R0 evidence)
- **Destroy order.** Each emitter's `Stop` is scheduled with `ScheduleDestroy` at `Start` (e2-ipc-emitter.cc:105). Start and stop order is node 1, 2, 3 (`runs/live1/ns3run/stdout.txt` `E2IPC node N` lines, in both places).
- **Node 1's `Stop`** (:181-213) runs in this order:
  - `DeliverInbound` on its own socket, then `OnEmitterStopping`;
  - `m_stopping = true` and **one** `DrainAll`;
  - buffered controls are answered `late`;
  - `stopping` is sent to the pacer;
  - the loop then **polls only the pacer** until `endAck`, for at most GateTimeout of 10 s (e2-control-hub.cc:380-411);
  - `end` is sent, node 1 is erased (:414), and the client flushes, sends `bye` and closes.
- **Nothing reads node 1's lines again.** `Flush` → `Service` → `Drain` (e2-ipc-tcp-client.cc:50-65, :144) buffers inbound bytes into `m_inLines`, but no `TakeInboundLines` follows (:363). Because the kernel buffer is drained, the close is a FIN, not an RST.
- **Agent 1.** It forwards the control while its IPC is up and records it as pending (`rc-control.cpp:96-98`). On `bye` (main.cpp:126-129), or on EOF or an error (ipc-server.cpp:81-87, main.cpp:215-218), it runs `fail_all_pending` → FAILURE `control-failed-to-execute`, and `ctlFailedOnBye++` (rc-control.cpp:127-134).
  - Result: **1 FAILURE on the wire, 0 ledger lines**, deterministic once the control reaches agent 1 inside the hold.
- **Through nodes 2 and 3 instead**, the same control is read by that node's own `Stop → DeliverInbound`. With `m_stopping` set, it is answered `late` (:183-187): a ledger line plus an ns-3 refusal FAILURE. This is also deterministic, but it is not the V4 path.
- So the "timing dependence" in the P2 note really depends on which node is used and when the control arrives. The pacer controls both.

### 4.2 Design (harness only)
- **Pacer schedule key** `"stopTrigger": {"cmd": [...], "confirm": [...], "timeoutS": 6}`. On `stopping`, after any `late` lines:
  - run `cmd` (rc-send via node 1);
  - run `confirm`, which polls agent 1's log for its `control … -> ns-3 ctlId` line (ALOG_I in rc-control.cpp after the forward), bounded by `timeoutS` ≤ 6 s, under GateTimeout 10 s;
  - then send `endAck`;
  - record `stopTriggerRc` and the confirm result in `pacer-summary.json`.
- **Fault run `f2`**, R1 config:
  - one ordinary control at step 20 (1 → 6 → 3, applied), so "0 ledger lines for it" is not vacuous on an empty ledger (the S1 hardening precedent);
  - then the stop control (1 → 4 → 3), sent after the final barrier.
- **Checks:**
  - ns-3 and pacer both exit 0; confirm succeeded;
  - wire: 2 requests, both via node 1; one ACK (step 20); **exactly 1 FAILURE `control-failed-to-execute`** for the stop control, paired by (requestorId, instanceId), coming from node 1;
  - ledger: exactly 1 line (step 20), none for the stop control;
  - extractor `--expect-requests 2 --expect-agent-local 1` (wire-c1-extract.py:213; the join maps node 1's 2nd request to ctlId 2, which has no ledger line);
  - C2: 2 = 1 + 1, split as `staticRejects 0` and `postBye 1`;
  - **agent 1 stats:** `rc.forwarded 2, rc.failedOnBye 1, rc.rejIpcDown 0, rc.pending 0`. Capture them by polling for a stats line with `ipc.bye ≥ 1`, bounded at 15 s. Today the logs are taken before the post-bye 5 s tick: gate-r0:190-193; `stop-agents.log` "last stats" shows `ipc.bye 0`. `failedOnBye 1` together with `rejIpcDown 0` is what proves the bye path, not the "ns-3 gone" static reject. On the wire alone the two look the same.
  - C9: 1 start row and 1 end row.
- **This is not test narrowing.** V4 and (e) name the bye/EOF path, and node 1 is the only node whose post-stop control takes it. Record the node asymmetry openly (Stop A item).

### 4.3 The two P2-deferred items
- **Stop loop polling agents (`DrainAll` in the stop loop plus a notice). Drop it.** It would read the control and write a `late` line (:183-187), contradicting V4's "0 ledger lines". Correct the implementation-notes P2 deferral and the resume-card "next action".
- **Departure inside a barrier** (`done = … || (seq >= 0 && !IsConnected())`, e2-control-hub.cc:497-499). Not needed for (ii), which happens after the final barrier. In gated runs a departure is already caught: by `ipcDropped`/`droppedDisconnected` > 0, by RestartCount, by the C1 digests, and by the new `connects=1` / `ipc.accepted == 1` check. Leave the code as is and raise it at Stop A.
  - If the user wants the fix, bundle it into **P6's** oran-interface/ns-3 change, which already re-pays the re-validation, and add S1 to P6's exit.

### 4.4 If a fork change is made anyway
Re-validation:
- **Contract minimum** (Constraints: "free-run stays the default, M5–M7 stay green after every agent or ns-3 change"; C8):
  1. Free-run digest equal to the P1/P2 reference: IPC samples and traces, rule as in S0 V1.
  2. M5, M6 and M7 re-pass, fresh, at the new pins.
  3. Each later rung's own C8 (null lock-step == free-run).
- **Plan-consistent additions** (P6 exit precedent "R0/R1/R2 one live run each"; S1 is the hub's own gate):
  4. Gate S1 re-run, if the hub or barrier code changed.
  5. R0 `--mode single` at the new pins.
  6. R1's C1 at the new pins.
- **Not required:** re-running R0's full C1.

## 5. Q5: T-trigger risks

| Trigger | Risk | Mitigation |
|---|---|---|
| T6 | The §3.3 defects and an untested fault-run path spend the one-fix budget on harness bugs. A second red Verify after one fix pauses. | Fix host-side first. Fixture-test on `073520Z` and S1. Run one `--dev` rehearsal (R0 precedent: rehearsals caught 2 harness defects). A red rehearsal is not a Verify, but record it honestly and never loosen a check. |
| T5 | The VM cold-booted at 07:56:59 UTC (r0-green). rc RMR readiness after a cold boot is unverified, and `rc_at_pin` runs before any reset. Gate i0 has **never run**, yet M9 runs it. | Run gate i0 first (it ends with an rtmgr restart and rc `RMR is ready after`). This also de-risks M9. If i0 fails without an L-only remedy, that is T5. |
| T7 | `influx-dump.sh` handles the deployed token. | Read the token on the VM inside the script; never pass it in argv (`curl -H @file` or stdin); no `set -x`. VM-side `grep -rF` of the exact token over the evidence dir must give 0 before any copy. Host-side pattern grep plus `scrub-evidence.sh`. |
| T8 | The classifier may refuse a command that reads a credential file or `kubectl exec`s with a secret. | Keep every token read inside a scripted gate on the VM via `vm-exec.sh`. Never `cat` the token in the transcript. A refusal is T8: pause, do not work around it. |
| T3 | Resume-card drift. The user may read (ii) as "any agent". | Run the 3 resume checks plus the boot-time check. Record the node-1 choice; if the user rejects it, the alternative is the uniform post-stop rule fork change (§7 Alt B), which is Decision required. |
| T4 | None new expected. | Fill the P4 ledger rows by reading E2AP v03.00 §8.2.4.3 (RIC Control unsuccessful operation) and §9.2.1 (cause) through zotero-mcp (`WEE5IEXF`) before the fault-run code lands. |
| T2 | Low: R1 adds roughly 2–3 G of overlay; 57 G free. | Record `df` at exit; the M9 projection (about −19 G) goes to Stop A/B. |

## 6. Must-do before the first R1 gate (ordered)
1. **Correct the record.**
   - In implementation-notes: the P2 "Deferred to P4 … (ii) needs both" note is wrong for V4 (§4.3); state the P4 design.
   - Resume card "next action": drop the two fork items; add i0.
2. **`rung-config.json`.** This is the journal §6 carry-forward, still stale at `:22-25`, `:40-43`, `:63-66`.
   - `substitutions.outage_threshold_minus_1000.applied = true`, provenance `evidence/r0/20261023T073520Z q2OutageSwitches 5`;
   - `scenario.outageThreshold_dB = -1000` with the same provenance;
   - `schedules.r0.path`;
   - later, `schedules.r1.path`.
   - Gate r0 reads none of these keys, so R0 is unaffected. Commit before the gate (the VM clones the pushed SHA).
3. **`pacer.py`.** Add sequential `triggers` and `stopTrigger` with confirm (§3.3 #2, §4.2). Add a stub-ns-3 self-test covering the single trigger (old path, same summary fields), multi-trigger ordering, the stop hold, and a confirm timeout.
4. **`r0-checks.py schedule`.** Group by step. Regenerate R0's schedule with the same endpoint; it must be byte-equal to `073520Z/r0-schedule.json`.
5. **`kpm-ue-list-moves.py`.** Per-(imsi, k) rule and a missing-ledger tolerance (§3.3 #3). Regression: `kpm-ue-moves.json` byte-equal for live1–3 and k9 of `073520Z`. Add a synthetic test of the judge (split it from the tshark parsing) for the (b), (c) and unknown-IMSI shapes.
6. **`r1-scenario.json`.** Contents:
   - the four cases of §3.2, with send order and expectations;
   - the `f2` block;
   - an `_comment` stating the layout and why target 3 and node 3 go first.
7. **The r1 gate**, under the one name shared with `run-to-m9.sh:62`. It contains every delta in §3.1, the §4.2 checks, and `--mode c1|single` plus `--dev`. `run-to-m9.sh` is already wired; verify the T_ctl provenance path works in single mode.
8. **`influx-dump.sh`**, token-safe as in §5 T7.
9. **Standards rows for P4**, read and dated through zotero-mcp before the fault-run code lands.
10. **Checks, then commit.**
    - Run `lint.sh`, the e2-evidence selftest, and the fixture regressions (items 3–5).
    - Then commit and push the harness and record its SHA.
    - Update the resume card (the operation runs longer than 10 min).
11. **VM run.**
    - Pre-flight: resume checks and boot time.
    - Run gate i0 and record that it ran for the first time.
    - Run **one `--dev` rehearsal** of the r1 gate.
    - Then the gated run, `vm-exec.sh <gate-r1> --timeout 10800`.
    - Then V1–V6 under the Failure Protocol.

## 7. Alternatives and trade-offs
- **Alt A (rejected): a shared rung library or a parametrised gate now.** DRY, but it edits gate r0. Re-tying R0 then needs a fresh R0 C1 (about 20 min plus T6 exposure on a green rung) for no contract gain. Revisit after M9, if ever.
- **Alt B (not needed; Decision required if the user wants it): a uniform post-stop rule in the hub.** After `stopping`, no agent line is read again, so every post-stop control takes the bye path. This removes the node asymmetry. Cost: §4.4 re-validation (free-run digest, M5–M7, S1, R0 single, R1 at the new pins), about 2–3 h of VM time.
- **Alt C (rejected): a fixed `sleep` between same-step sends instead of pacer sequencing.** Probably fine (sleep is far larger than L_max 12.9 ms), but nothing proves it. A rare swap shows up as a red C1, which is a T6 path.

## 8. What to avoid
- `DrainAll` in the stop loop. Any agent fork change in P4.
- Sending target 2 or node 2 first in (b) and (c). The test would then pass whether or not the hub sorts.
- Judging (ii) on V4's wire and ledger counts alone. The rejIpcDown path also gives 1 FAILURE and 0 lines.
- Capturing agent stats before the post-bye tick.
- Adding `kpm-ue-moves.json` or the Influx dump to C1's digested components.
- Re-running R0 C1.
- A token in argv, or in any check output.

## 9. Q4: Stop A content, beyond phase-04 step 5

**Segment 1 summary**
- R0 = M8 green and R1 green: evidence paths, harness SHAs, pins, gate durations (R0 c1 19 min; R1 c1 measured).
- Report-only items: substitution 1 applied (Q2 = 5 at −5 dB); T_ctl = 30 s (L_max 12.9 ms); W still the start value; N5 match (G4 keys `0000000202`, `0000000303`).

**User rulings needed, each with a recommended default**
1. The T8 reading of the P0 refused probe. Default: not T8; "any refusal = T8" from now on.
2. K5 shown by integration cases (S1 fb1, R1 (b)) rather than an ns-3 unit test. Default: accept.
3. "late" covers a mid-run missed barrier (K9). Default: yes.
4. RAN function 3 is not announced in E2 Setup (E2AP v03.00 §8.2.4.3). Known and approved; ask whether to list it as a recorded deviation.
5. hw-go and kpimon are recreated each run, against "hw-go (stays deployed)". Default: the pod is recreated, the deployment stays.
6. The rtmgr restart in the reset, and the T5 reading (an L-only remedy). The −1 owner moves within a run; both views are recorded; owner identity is not a pass condition.
7. ns-3 trace text files are gitignored, with sha256 manifests.
8. Fault run (ii) runs through node 1. Post-stop controls through nodes 2 and 3 get a `late` line by design. The P2-deferred items are dropped, and the departure fix is optional for P6 (§4.3).
9. C9's file naming: the contract says `UeHandover*`, the checker reads `EnbHandover*`, and both agree.

**Carry-forward**
- P5/P8 will hit the rtmgr defect whenever the TS xApp or QP pods are replaced (`RMR_SEED_RT`, rtmgr restart, KPM continuity).
- Fix M3's kpimon log reader (`gate-m3-xapps.sh:162`) and re-run M3 before Stop B.
- Record kube-controller-manager and kube-scheduler restart counts.
- M7's 150 indications are still unexplained (informational).
- P0 partials:
  - K13: `run-to-m9` does not read `rung-config`;
  - K16: VM-side traces are not deleted;
  - `--harness-sha HEAD` is not resolved to a full SHA;
  - `--min-gb` cannot be passed through the runner;
  - watchdog files are not archived per run;
  - shellcheck skips `tools/`.
- The colletStartTime collision of samples 0 and 1 (observation).
- i0's first-run date.

**Disk**
- K2 projection with the measured segment-1 growth (76 G at P0 → about 55 G at P4 exit).
- Updated M9 projection (about −19 G), and the options listed in phase-04 step 5.

**Segment 2 pre-flags**
- P5: TS xApp after every agent is CONNECTED; the A1 threshold; the stray-ack probe and then substitution 2; W calibration.
- A kongming consult before P6's UL counter lands.

## 10. Success metrics
- The R1 gate exits 0.
- C1 all true.
- V2 outcomes exactly as in §3.2, with the non-vacuity checks green.
- D7 1/2/1.
- kpmUeListMoved {1, 2, 3, 6} true.
- c5 true/true.
- `f2`: 1 FAILURE, 0 lines for the stop control, `failedOnBye 1`, `rejIpcDown 0`.
- `connects=1` on every emitter.
- Influx token grep 0.
- R0 fixture regressions byte-equal.
- No pin change, so M5–M7 and R0 remain valid as recorded.

## 11. Assumptions
- **Destroy order stays node 1, 2, 3 at these pins.** High confidence: ScheduleDestroy runs FIFO in Start order, and the R0 stdout shows it. The `f2` confirm plus the `failedOnBye` check would catch a change.
- **The agent log line `control … -> ns-3 ctlId` is a usable readiness signal.** High confidence: emitted right after `pending_` is set. It is a precondition only, never a judge.
- **The user accepts (ii) through the eNB agent.** Medium confidence. If not, Alt B with a fork change (Decision required).
- **"0 ledger lines" in V4 means the bye path is intended.** High confidence: phase-04 (e) names "bye/EOF FAILURE-all-pending".
- **Linux keeps already-queued data readable when an RST arrives.** Medium confidence, and moot: the close is a FIN (§4.1), and the agent fails pending controls on EOF or an error as well.

## Unresolved questions
- The exact gate file name (`gate-r1-rc-multi.sh` vs `gate-r1-rc-multi-control.sh`): the caller should pick one.
- Whether the user wants the departure fix bundled into P6 (Stop A ruling).

# P2 exit go/no-go on P3: M8–M9 plan 261023-0009 (kongming, 2026-10-23 ~07:45 KST)

Runtime: Claude Code, model Opus 5.5 (per the user's CLAUDE.md). This is advice only and never counts as user approval.

**What I checked against the actual code and evidence:**
- **Harness.** HEAD `025a6f7` equals upstream.
- **VM.** `running`, snapshot-current `f7-rerun-green`. Host `/home` has 60 G free. Host load is 1.20/1.36/1.79 on 20 CPUs at 07:41; the top consumer is our own qemu, at 85 % of one core.
- **Code read at the pins.** The pins were shallow-cloned into the scratchpad:
  - oran-interface `63155c49`: `e2-control-hub.cc`, `e2-ipc-emitter.cc`, `e2-ipc-message-encoder.cc`;
  - Testbed `4c8397d0`: agent `main.cpp`, `rc-control.{hpp,cpp}`, the IPC schema;
  - ns-3 `962fabc7`: `scenario-zero.cc`.
- **RIC xApp source.** rc `a2282ee` (`rcControl.go`, `rcService.go`, `rcE2SmRc.go`) and the TS xApp `19e169b` (`ts_xapp.cpp`).
- **Evidence read.** The S1 `verdict.json`, `facts.jsonl`, the per-run `v3-fault-check.json` files, the schedules, ledgers, pacer logs and summaries, and `LteSwitchStats.txt`. Also M7 `20261022T215841Z`: I re-partitioned `m7.pcap` against `m7-kpimon.log`.

## TL;DR
**GO-with-must-do.** P2 meets its exit gate and In scope 2. The S1 evidence is genuine and non-vacuous where it matters. No T-trigger is present now.

P3 has five prerequisites that do not exist yet. Two of them would make R0's first C1 fail, or make it unreachable, by construction:
1. **The agent's `ctlId` counter lives for the whole process** (`rc-control.hpp:77` `nextCtlId_ = 1`, constructed once at `main.cpp:175`). If the agents stay up across C1's live runs, run 2's ledger carries different `ctlId`s, so the ledger digest differs and C1 is red. Restart the agents for every live run, or reset the counter on each hello.
2. **Q2 is already answered by evidence you hold.** S1's null-control run in the R0 config (−5 dB, RngRun 1, simTime 10) logs **5 `SwitchToLte`** events, for UEs 3, 1, 4, 2 and 6 between 0.20 and 4.35 s. Substitution 1 is practically certain. The R0 schedule must therefore be designed on the −1000 config, and C8 (null = free) must be shown again at that config.

On the CPU hold: do all non-timing work first. The calibration, and with it the R0 C1 gate, waits for the user's explicit release. If nothing else remains and the transcript holds no release, print **PAUSE T3**. Never infer the release from the load average.

## 1. Scope-guard diff for P2 (Q1)

| In scope 2 / acceptance | Evidence (S1 `20261022T191853Z`, 35/35, harness `ca65920`) | Verdict |
|---|---|---|
| Pacer + barrier (D1), all-of | Exact barriers −1…99 (`101 ready seqs`). Fault runs withhold on node 3 only: the reason reads `no step 30 from node(s) 3`, `stepKFrom [1,2]` | ok |
| T_gate 10 s | `blockedToAbortWallS` 10.004 / 10.005 ≤ 15, measured from the barrier entry (`hub.cc:444`) | ok |
| T_ctl 30 s | tctl run: `abortStep 15`, `blockedToAbortWallS 30.05`, ns-3 exit 5, pacer exit 3 | ok |
| T_start 120 s | Attribute plus the hello `tStartS`; `minSlack.T_start` 119.9995, i.e. the agents were ready before ns-3 started. **No T_start run-out was ever run** | weaker than C7's literal "a deadline run-out". Should-do 1 (cheap) |
| D2 freeze-then-fail | `e2-pacing-abort.json`, exit 5. faultsink: 3 ledger lines before K, 0 at or after K | ok |
| IPC minor bump | hello `"minor":2,"pacing":"lockstep","tStartS":120.0,"tGateS":10.0` (encoder `:164-182`), and the schema text exists | ok |
| Replay sink, Fallback-1 | fb1 8 lines; replay digest equals fb1; one ack per line; six outcomes fixed by construction | ok |
| K5 precheck order | fb1 `2,1` imsi 6 → 2 gives `refused inHandover`; the reverse order would give `alreadyOnTarget` | ok (integration case; the user rules on the wording at Stop A) |
| Mid-run late (D2(a), C3) | midlate: step 20 `afterSeq 19` is refused late; step 21 shows `sourceCell 2` (old cell, nothing applied) | ok. The replay path for a mid-run late line is untested; it matters only if a gated run is late, and that already fails C7 |
| Null-control equivalence | `nullControlDigestEqualsFreeRun: true`, `freeRunEqualsP1: true`, 29 traces, 100 samples per node | ok **at −5 dB only**; see §2 must-do 6 |
| `simStartEpochMs` pinned (D10) | Gate S1 hard-codes `EPOCH_MS=1767225600000` (`gate-s1:59`), and the hello carries it | **record gap:** `rung-config.json` still has `simStartEpochMs: null`, and no script reads `rung-config.json` (grep). Must-do 3 |
| K10 facts | `ipcDropped 0`, `droppedNoSub 0`, `minSlack` with T_ctl/W null plus a hold note | ok |
| V5 / K19 | M5 21/21, M6 37/37 (199 = 199), M7 52/52 at `e97ed53`; V6 free run = P1 | ok |

**Vacuity:**
- The faultagent run has no controls, so its "no ledger line from K" holds trivially. faultsink covers the ledger side. This is accepted as designed.
- Nothing else is vacuous.
- The P1-exit landmines are fixed (`steps` gating, mid-run late, one-node fault, facts) or deferred to P4 on the record (departed, stop drain).

**No T3:** nothing in P2 is missing or narrowed against the locked contract.

## 2. P3 readiness (Q2)

### Prerequisites that do not exist yet (verified by grep)
- **Already reusable:**
  - the rc install, pinned grpcurl and describe path (`probes/probe-rc-control-latency.sh:37-63`);
  - the rtmgr route-dump method (`probe-261022-1544`);
  - the KPM decode harness (`tools/kpimon-decode-harness`);
  - the P0 RC decoder (`tools/rc-decode`);
  - the K11 guard (`digest-run.py:87-92`).
- **Missing:**
  - the C1 wire extractor;
  - `replay-ts-cell-map.py`;
  - `check-c9-handover-trace.py`;
  - `ric-reset.sh`, `rc-install.sh` and `rtmgr-route-dump.sh` as gate scripts;
  - the gRPC trigger rendering (the rc endpoint changes on every reset);
  - the fresh-Influx-bucket mechanism;
  - per-run RestartCount and pod UID capture;
  - `repeat-gate.sh`;
  - any reader of `rung-config.json`.
- **Not exercised yet:** no gate has sent a real rc control to the **P1** agent. S0 used the null sink plus unit tests, and the pre-M8 probe ran the pre-P1 agent, which never answered. So in P3, real 12041/12042 cross RMR for the first time:
  - rc's instance IDs 2 and 4 hit kpimon by exact key;
  - the rest go to the −1 fallback owner chosen by Go map order;
  - kpimon, hw-go and rc must all survive this, so RestartCount must stay 0.

### Determinism landmines for C1
1. **`ctlId` drift across runs.** Detail in the TL;DR. The ledger digest is the full text (`digest-run.py:59`), so this cannot be avoided without narrowing C1, which is forbidden.
2. **Defining the RC multiset.**
   - The contract content is "(decoded E2SM-RC content, terminal answer type)".
   - Keep `requestorId`/`instanceId` out of it. rc's counter (`rcControl.go:150-153`) depends on rc's lifetime. Use the IDs only for C5 pairing.
   - Assign each request to a step through the ledger join on `(viaNodeId, imsi, targetCell)`, and assert that the join is a bijection: every wire request maps to exactly one ledger line or one agent-local FAILURE. That also gives C2's count identity.
3. **KPM headers** means the decoded E2SM-KPM IndicationHeader per node, in order. Keep the E2AP `RICrequestID`/SN envelope out. kpimon's subscription IDs change whenever agents re-subscribe.
   - colletStartTime = `simStartEpochMs + simTime − period` (`sample-forwarder.cpp:62-65`), so it is deterministic.
   - There are several indications per sample: the eNB sends about 3, a gNB about 2 (faultagent `indTx` 91/61 for 31 samples).
4. **`kpmUeListMoved`** needs the Format 2 `matchingUEidList` IMSIs (the agent puts the IMSI in `amf_UE_NGAP_ID`, `kpm-indication-message.cpp:64-69`). The extractor must emit the IMSI set per (node, seq), not headers alone.

### Step order (recommended; it keeps phase-03's 1→2→3→5 and adds a smoke)
1. **Host-only (hold-safe):**
   - the standards rows first;
   - the pacer fixes;
   - the extractor, fixture-tested on the M7 pcap (KPM) and the P0 RC fixture (requests; answers are validated on the smoke pcap, since no pcap has any yet);
   - `replay-ts-cell-map.py`, fixture-tested on S0's three e2mgr JSONs: request parts decode to `0000000202`, `0000000303` and `72657170617274` (verified), so the expected keys are 0202 and 0303 and none for the eNB;
   - `check-c9` on S1 fb1, which holds an applied imsi 6 → 3 plus `UeHandover{Start,End}Stats.txt`;
   - the reset, install and route-dump scripts;
   - `rung-config` wiring.
2. **VM, step 1:** rc install, then readiness: pod Ready, gRPC `describe`, the route dump shows rc's 12040 route, RestartCount 0, and the rc SHA equals `a2282ee`.
3. **VM, step 2:**
   - Q2 at the final R0 CLI: null sink, −5 dB, RngRun 1. Count `SwitchToLte`, expect ≥ 1, and apply substitution 1.
   - Then null and free at −1000: this gives C8 for R0's config and the UE→cell map at the trigger steps, which you need to design the schedule.
4. **VM, step 4:** G4 plus the cell_map replay on the live e2mgr JSON.
5. **Scenario.** Write `r0-scenario.json`.
6. **One labelled smoke** (not C1; outside the `gate-r0` id, e.g. through `vm-exec-probe.sh`): one lock-step live run with real rc carrying ≥ 1 applied and 1 refused control, plus the extractor, a replay, and RestartCounts after real acks. This is where integration bugs belong, before any gated run.
7. **Timing, blocked by the hold:**
   - step 3, calibration: 10 controls in their own run, writing T_ctl to `rung-config.json` with its provenance;
   - then `gate-r0` fresh, which reads it: C1, C8 at the gated config, K9, V1–V9;
   - then step 6, `r0-green`.

The `steps` gating fits this order. Every R0 trigger waits for `steps k` (`pacer.py:170`), so `afterSeq = k` is deterministic. The pacer waits for `controlRx` at barrier k, so `rxSeq = k`.

### Contract versus plan: no T3, with four readings to pin down
- **D7 counters.** Count over `applied` lines only. The already-on-target refusal must not satisfy any path counter. This is the stricter reading.
- **C8 is per rung.** Null = free must hold at R0's gated config (−1000), which phase-03's V-list does not name. Add it inside `gate-r0`; it is cheap (two runs of about 60 s through the null sink).
- **K9.** Use the mid-run variant only (§5).
- **Fresh Influx bucket.** C8 and In scope 7 require it for every paced rung, R0 included, even though nothing in R0 reads it.

## 3. The CPU hold (Q3)
**Allowed under the hold.** These do not measure or set a timing value:
- the extractor, replay, checker and reset scripts;
- the rc install;
- Q2 (a trace count, deterministic in RngRun);
- null and free at −1000;
- G4 and the replay;
- the scenario design;
- the smoke;
- the K9 run design.

This is the same reasoning that let S1 run under the hold. Fixed contract deadlines are not calibrations.

**Must wait:**
- the calibration run (L → T_ctl = max(30 s, 20 × L_max));
- the R0 C1 gate, because phase-03 orders calibration before it and V7 needs `tCtlSeconds`;
- any use of L or slack as a gate value.

Record L from the smoke and the C1 runs, label it "recorded under the user's CPU hold", and never reuse it.

**Pause point.** When only the calibration and the gate remain:
- If the transcript holds the user's explicit release, calibrate.
- If not, run the full pause protocol first: journal, kongming note, resume card, push. Attach `uptime` and the top-CPU list for host and VM, then print `PAUSE T3`. T3 fits because "an acceptance signal that cannot be met as written": V7's calibrated `tCtlSeconds` cannot be produced without breaking a user instruction.
- Today's load (1.2–1.8 on 20 CPUs, with our VM the top process) is evidence for the user to weigh. It is not a release.

**No T-trigger now.**

Alternative to offer at the pause (the user's call, not yours): run C1 at the contract's 30 s first, and calibrate afterwards. This is outcome-neutral:
- digests do not depend on T_ctl, because T_ctl lives only in the pacer and the hello is excluded from the digest;
- a pass at 30 s implies a pass at any max(30, …).

The cost is a V7 provenance that gets stitched together after the gate.

## 4. Carry-forward items (Q4)
- **M3 reader fix and M3 re-run before Stop B: agree.**
  - The code switch to `pod-log-window.py` can land any time; it is harness-only, with lint and the self-test.
  - The M3 *run* reinstalls kpimon (`CLEAN_INSTALL=true`), so keep it in the P9 window, not in P3.
- **One kpimon log window per rung run: agree.**
  - Informational in R0, because R0 judges on the wire and decodes the KPM UE lists from the pcap.
  - It stays under the retention ceiling at 3 nodes.
- **`slackS` on aborted steps.**
  - It is still there: `pacer.py:199-200` gives `budget − max(L or [0])`, which is 30.0 for the tctl step with no control.
  - Must-do before the calibration: `slackS = null` when the step did not get exactly `expect` controls, and `minSlack.T_ctl` only over complete steps.
- **P4 departed logging and the stop drain: still P4.**
  - P3 avoids both: R0 detects an agent crash through `ipcDropped`/RestartCount, and K9 must not use the stop path.
  - The code is unchanged: EOF counts as done (`hub.cc:499`), and the stop loop polls only the pacer fd (`hub.cc:393-411`).
- **M7's 150-indication gap: now explained offline.** It does not block P3.

  | M7 window (relative to the e2term delete T_del) | Wire | kpimon | Lost |
  |---|---|---|---|
  | Old pod's 30 s termination grace, `[T_del, +31 s)`; the SCTP SHUTDOWN comes at +30.05 s | 121 frames | 0 (12 delivered in the first second) | **109** |
  | The ~25 s after nodes 2–5 re-subscribe at +159.45 s | — | — | **41** |
  | From +200 s on | 1448 | 1448 | 0 |

  - 109 + 41 = 150.
  - The 41 are most likely a route-propagation window for the new subscriptions. This is unverified.
  - It is specific to the delete. M6 at a fresh bring-up shows 199 = 199.
  - It does not matter for R0–R2, which are judged on the wire.
  - For R3, N6 already checks Influx completeness per seq. If N6 ever fails on early seqs right after fresh subscriptions, suspect this first.
  - Replace the "unexplained" note in implementation-notes with these numbers.

## 5. Other risks before R0 (Q5)
1. **rc readiness is three things, not one.**
   - rc queues gRPC calls and answers success at once (`rcService.go`), then sends over RMR asynchronously. A pod that is Ready but has no routes yet loses the request silently, and you only see it as a 30 s T_ctl abort.
   - Gate on all three: pod Ready, gRPC `describe`, and the route dump showing rc → e2term for 12040.
   - Optionally, send one canary control before the capture starts. The agent answers `ns-3 not connected` before it assigns a `ctlId` (`rc-control.cpp:71-76`), so the canary costs no ID.
   - Resolve the rc endpoint again for every run: prefer the Service DNS name, because the pod IP changes on each reset. Give grpcurl `-max-time`, so a hung call fails as a clean trigger error.
2. **Stale state between runs.**
   - Per-run rc reset: delete the pod. Then record that the pod UID is the same at the start and end of the run, and that RestartCount is 0 at the end.
   - rtmgr re-rolls the −1 owner on every reset. Record it from the dumps at start and end. A change is a record, not a failure.
   - e2mgr still lists DISCONNECTED `gnb_…04/05` from M7. The TS xApp walks `/v1/nodeb/states` without a status filter (`ts_xapp.cpp:804-855`), so a faithful replay also prints `0000000404`/`0000000505`. V5 allows that ("every gNB agent key, no eNB key"). Record it, because it becomes R2's stale-target risk in P5.
3. **Q2 at RngRun 1 / −5 dB.** Detail in the TL;DR.
   - ns-3's own option comment says "use -1000.0 with NoAuto" (`scenario-zero.cc:173-174`).
   - Run the formal count anyway, so `q2OutageSwitches` lives in R0's own evidence.
   - At RngRun 2 the scripted controls may be refused. K10 allows that, as long as C2/C7 hold and the pacer's `controlRx` counts still match.
4. **N5 match.** It will match: S0's e2mgr JSONs, the TS algorithm (`ts_xapp.cpp:331-373`: base64, the meid suffix after the 3rd `_`, uppercase, `substr(i,10)`), and the agent's octets 4–8 parse are consistent. Report it, do not pause on it.
5. **K9 design.**
   - Use the mid-run variant with a go-before-trigger option in the pacer: send `go k`, then grpcurl, with `expect 0`.
   - The control then reaches ns-3 after barrier k. The agent stamps `afterSeq = k` because ns-3 is still simulating period k+1 (S1 p50 is 0.58 s per period, against tens of ms for the rc path). The hub then refuses it late (`hub.cc:256-262`).
   - Assert the precondition `afterSeq == k`, `cause late`, one wire FAILURE `control-failed-to-execute`, and 0 HandoverStart rows.
   - Never use the after-final-barrier variant here. It depends on wall timing (`hub.cc:393-411`), and P4 (ii) expects 0 ledger lines for it.
   - If the precondition fails once, the fallback is a test-only agent hold hook. That is a product change, followed by M5–M7.
6. **Influx token (T7).** The bucket reset (a same-name delete and create, which gives a new bucket id) runs on the VM, with the token read from the VM file. Never echo it, and run the scrubber before the commit.
7. **Hygiene.** There is an untracked stray file, `plans/261021-1823-…-m0-m7/evidence/watchdog/min-host-free-gb.txt`, left by a manual `host-disk-watchdog.sh --once` run without `EVIDENCE_HOST_ROOT` (default at `vm-common.sh:18`). Delete it, and export the root before any manual watchdog run.

## Verdict: GO-with-must-do

### Must-do (before R0's first gated run; items 1–10 do not need the hold lifted)
1. **Standards first.**
   - Through zotero-mcp, fill phase-03's "Target NR CGI" row: E2SM-RC v03.00 `XRWZU3SS` (Target Primary Cell, NR CGI) and E2SM common v07.00 `QW6VJ83M` (NR CGI), with the read date.
   - Record that rc's raw `00‖PLMN‖key` (not an APER NR CGI) is covered by N5, so it is not T4.
   - Anything the reading finds beyond N5 is T4.
2. **`ctlId` determinism.**
   - Restart the agent containers for every live run as part of the per-run reset. This is a harness change, with no product change and no pin move.
   - Add a check that, in every live run, each node's `ctlId`s start at 1.
   - Alternative: the agent resets `nextCtlId_` on an accepted hello, which needs a Testbed pin bump and an M5–M7 re-pass.
3. **`rung-config.json`.**
   - Set `simStartEpochMs = 1767225600000`, with provenance `evidence/s1/20261022T191853Z`.
   - `gate-r0` reads the epoch, deadlines, threshold and schedule path from it and records the provenance.
   - Q2 writes substitution 1, and the calibration writes T_ctl, each with its evidence dir.
4. **`pacer.py`.**
   - `slackS` is null for incomplete steps, and `minSlack.T_ctl` covers complete steps only.
   - Add a `goBeforeTrigger` option for K9.
   - Add grpcurl `-max-time` in the trigger template.
5. **Extractor, host-side first** (per the P1-exit amendment), with the definitions in §2:
   - the RC multiset without RIC request IDs, step-joined to the ledger with the bijection asserted;
   - the KPM IndicationHeader and colletStartTime per node and seq;
   - C5 facts, the C2 identity, and `kpmUeListMoved` from the Format 2 IMSIs;
   - fixture tests on `m7.pcap` and the P0 fixture.
6. **Q2 first, then C8 at the gated config.**
   - The Q2 run at the final R0 CLI and −5 dB gives `q2OutageSwitches`; apply substitution 1 if it is ≥ 1, and report it.
   - Add null and free at −1000 inside `gate-r0` (C8 for R0).
   - Design `r0-scenario.json` from the −1000 run's UE/cell map.
7. **Per-run RIC reset and readiness (§5.1–5.2).**
   - rc: Ready, plus `describe`, plus the 12040 route.
   - Pod UID and RestartCount for rc, kpimon, hw-go and every agent.
   - A fresh Influx bucket, with its id recorded.
   - Route dumps at start and end, giving `routeOwner12041`/`12042`.
8. **One labelled smoke run** outside the `r0` gate id, before any gated run (§2, step 6).
9. **K9** = the mid-run variant with the explicit precondition (§5.5). Never use the stop path.
10. **D7 counters** over `applied` lines only.
11. **CPU hold.**
    - The calibration and the R0 gate wait for the user's explicit release.
    - If nothing else is left and there is no release, follow the full pause protocol and print `PAUSE T3`, with the load evidence attached.
    - Never infer the release.

### Should-do
1. **A T_start run-out case.** One node is never READY, giving an abort at 120 s that names step −1. About 2 min, in `gate-r0`'s non-C1 runs or in P4. It closes C7's literal "a deadline".
2. **Notes.** Record the M7 150 = 109 + 41 explanation (§4), the stale e2mgr keys (§5.2), and the hold annotation on every recorded L.
3. **M3 reader code fix.** Land it early, with lint and self-test only; the M3 run stays at P9.
4. **Stray watchdog file.** Delete it (§5.7).

## What to avoid
- Taking T_ctl from S1 or smoke L values, or from `slackS` on any step that did not complete.
- Excluding `ctlId` from the ledger digest, or adding a tolerance. Either one narrows C1.
- Running the smoke under the `gate-r0` id, or as a 3-run C1. A red there would look like a red C1.
- Using the stop handshake for K9.
- Judging anything in R0 on kpimon's log or on Influx.
- Applying substitution 1 from S1's numbers alone, without R0's own Q2 run.

## Alternatives and trade-offs
- **`ctlId`.**
  - Per-run agent restart (recommended): no pin move, a fresh state each run, and about 45 s per run.
  - Reset on hello: cleaner semantics, but a product change with a Testbed pin bump, an M5–M7 re-pass (about 31 min), and a new unit test.
- **Hold.**
  - The literal order plus PAUSE T3 (recommended): clean V7 provenance.
  - C1 at 30 s first: outcome-neutral and about 1 h earlier after the release, but V7's basis is stitched in later. Offer it to the user at the pause.
- **K9.**
  - Go-before-trigger (recommended): harness-only, probabilistically safe with a margin of more than 10×.
  - The agent hold hook: deterministic, but a product change. Use it only if the precondition fails once.

## Assumptions
- **High.** R0's CLI equals S1's apart from the threshold and the pacing schedule, so S1's 5 outage switches predict Q2. A longer simTime only adds switches.
- **High.** A per-run agent restart resets every agent state that reaches the ledger or the C1 components. kpimon's new subscription IDs reach only the E2AP envelope, which the KPM component excludes.
- **Medium.** kpimon keeps writing after a same-name bucket is deleted and re-created, because writes resolve the bucket by name. Verify it in the smoke with a row count.
- **Medium.** The 41 indications lost after re-subscription in M7 are a route-propagation window. This is inferred from timing only.
- **Medium-high.** kpimon and hw-go discard unknown message types. This was read at the upstream tags, not in the NIST-patched kpimon, which is why the smoke checks RestartCount.

## Unresolved questions (for the user, at the pause or at Stop A)
1. Is the CPU hold released? If not, may C1 run at the contract's 30 s before the calibration (§3 alternative)?
2. Stop A, carried over: K5 closed by an integration case; "late" includes mid-run; the function-3-not-announced question.

## Status
DONE. GO-with-must-do (11 items). No T-trigger now. The expected pause point is PAUSE T3 at the calibration step, unless the user releases the hold.

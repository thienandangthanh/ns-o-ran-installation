# kongming: Stop A segment-1 review and P5 go/no-go

Date 2026-10-23, started ~18:15 KST, resumed after an API limit, finished ~19:40 KST. Model: Opus 5.5, routed by the caller per the user's CLAUDE.md. This is advice only and never user approval.

**What was verified**
- Harness HEAD `b40b2c3`, equal to origin.
- Evidence: R0 C1 `evidence/r0/20261023T073520Z`, R1 C1 `evidence/r1/20261023T084654Z` (`verdict.json`, `c1-*.json`, schedules, pacer summaries, Influx dump).
- Records: plan.md, goal-packet.md, phase-04, phase-05, the milestone report, the journal, implementation-notes (P3 and P4), and kongming -1615 and -1705.
- Upstream code, cloned fresh into the scratchpad at the pins: ric-app-ts `19e169b`, xapp-frame-cpp `2.3.6`, ric-app-rc `a2282ee`, ric-app-qp `47a35ca`, Testbed fork `4c8397d0`.
- Live, read-only: `df` (54 G free at 19:32 KST); VM running at `r0-green`; active overlay 2.2 G.

## TL;DR
- **Segment 1 matches the locked contract for R0 and R1.** I found no gap, no narrowing and no weakened test.
  - The per-(imsi, k) KPM rule is not a weakening.
  - Running fault run (ii) through node 1 is the faithful reading.
  - Reasons for both are in §2.2.
- **Fix 8 record items in the milestone report before printing PAUSE A** (§2.4). All are wording or record fixes; no run is needed. The ones that matter most:
  - The disk option "r2-green is optional to keep" contradicts P5 V6.
  - The report does not link this segment review.
  - It omits the R1 latency finding: the second control in a step through the same agent takes 0.20 s.
  - Ruling 8 presents a result read from the code as if it had been run.
- **GO for P5**, after the user's rulings. Ruling 6 (rtmgr restart) directly governs P5's reset.
- **Five P5 landmines are verified at the pins.** None is in the plan yet:
  1. NIST's TS xApp installer deploys in **REST** mode, so G3 needs a harness override to gRPC.
  2. The TS xApp has an `RMR_SEED_RT`, so its readiness **hides the rtmgr defect**. Its seed table also sends 30000 to `service-ricxapp-qp-rmr`.
  3. The TS xApp **never answers A1** and resets its threshold to 0 on every restart.
  4. The prediction format: the **serving cell is the first key**, values must be unsigned integers, and ties are broken by `unordered_map` order.
  5. Substitution 2's default callback must be registered **before `xfw->Run`**.
- **No T-trigger now.** PAUSE A is the correct terminal line.

## 1. Reframed problem
There are three decisions:
- Is segment 1 complete under the locked contract, so that Stop A is a clean milestone and not a hidden T3?
- What must be corrected in the Stop A record so the user rules on accurate facts?
- How should segment 2 start, so that P5 does not spend its one-fix budget (Failure Protocol, then T6) on predictable harness or integration defects?

Constraints:
- C1–C9 hold on every rung.
- R2 negatives are judged by ledger count plus late = 0.
- G3, the decimal-IMSI `ue-id`, and substitution 2 only on a probe crash.
- No TS xApp change beyond substitution 2.
- Never weaken a test.

## 2. Task 1: segment review

### 2.1 Conformance (verified on the evidence)
| Contract item | R0 (`073520Z`) | R1 (`084654Z`) | Verdict |
|---|---|---|---|
| C1: 3 live runs equal on the ledger, IPC, traces and `extra` (rc multiset, KPM headers, colletStartTime); replay equal on the ledger, IPC and traces; rng2 differs | true/true/true | true/true/true; `c1-live.json` components are ledger, ipc, traces, extra | met |
| C2: count identity, static rejects and post-bye counted separately | met | live 7 = 7 + 0; f2 2 = 1 + 1; `c2AgentSplit` static 0, postBye 1 in f2 only | met |
| C3: every ACK carries Format 1, decoded with the P0 decoder | met (V2 fix) | `extra/rc-answers.json` `outcomeXer` shows Format 1 | met |
| C4: the sort key | n/a | step 30: the refused line holds node 2's lower ctlId; step 40 rx order is 3 then 2, in all 3 runs | met, and not vacuous |
| C5: pairing by (requestorId, instanceId); answers via `viaNodeId` | true | true in every run | met |
| C6: pending controls by ctlId; bye fails every pending control; static rejects 0 | met | f2 `failedOnBye` 1, `rejIpcDown` 0 | met |
| C7: slack, late, restarts, droppedNoSub | met | minSlack recorded; restarts 0 (24 entries); droppedNoSub 0. Live-run late = 0 is enforced only through exact expected outcomes; there is no explicit field (rng2 has one) | met; note it |
| C8: null control equals free run; per-run reset | met | `c8NullEqualsFree` true; reset evidence fresh in 4 runs | met |
| C9: handover rows equal the applied lines | met | met | met |
| D7 | 1/1/1, 3 IMSIs | 1/2/1, 4 IMSIs, targets {2, 3} | met |
| R1 (a)–(d), K5, R1(d) amendment | — | as designed in all 3 live runs | met |
| Fault run (ii) | — | 1 FAILURE `control-failed-to-execute` via node 1; 0 ledger lines for it; a non-vacuous step-20 line | met (§2.2) |
| K10 fields | present | present | met |
| Influx dump (V6) | — | 39,257 rows; checked on the VM against 44 known secrets with 0 hits and 0 shape hits | met |

The byte difference between the check (4,751,959) and the file (4,791,331) is the 39,372 CRLF line ends, which Python's text read folds. It is benign.

### 2.2 The two suspected narrowings
- **The KPM per-(imsi, k) rule is not a weakening.** In `tools/e2-evidence/kpm-ue-list-moves.py:87-138` the rule is:
  - with one applied line, that line's move check judges the IMSI;
  - with none, a refusal must leave the membership unchanged;
  - two applied lines are a problem.

  A refused line in a same-step pair is still constrained three ways:
  1. the applied line's move check pins the IMSI's location at k+1 to the applied target;
  2. C9 forbids any handover start row without an applied line;
  3. the "≥ 2 applied" rule forbids a second execution.

  R0's four outputs regenerate byte-equal (implementation-notes, P4). The UE-list check was added in P3 (V9) as cross-evidence. Refusals were never judged by it alone: C9 and the ledger carry that.
- **Fault run (ii) through node 1 is the faithful reading.**
  - The contract says "a control after the final barrier → exactly one FAILURE". Phase-04 (e) names the bye/EOF FAILURE-all-pending path, and V4 adds "0 ledger lines".
  - At the pins, only node 1 takes the bye path.
  - Through nodes 2 and 3 the control is answered `late`: one FAILURE plus one ledger line. So "exactly one FAILURE" holds on every node, and only V4's "0 ledger lines" is node-1 specific.
  - Two caveats:
    - The node 2 and 3 behaviour comes from code reading (`e2-ipc-emitter.cc:181-213`, my -1705 §4.1). It was never run.
    - The post-stop `late` code path is distinct from the mid-run late path (K9, S1 `midlate`), so no gate covers it.
  - The milestone must say this (§2.4 item 5). It is low risk, and ruling 8 is the right place for it.

### 2.3 Observations that are not gaps
- **R1 control latency L** (`pacer-summary.json`, steps 20, 30, 40):

  | Control | L |
  |---|---|
  | First in a step | 7–12 ms |
  | Second in a step, another agent | ~0.040 s |
  | Second in a step, the same agent (node 2 → node 2) | 0.1999 / 0.2027 / 0.2060 s, in 3 of 3 runs |

  - R0's L_max was 12.9 ms.
  - T_ctl = 30 s still covers this with a wide margin: 20 × 0.206 = 4.1 s.
  - My hypothesis, which is speculation: Nagle-like bundling plus the 200 ms delayed SACK on the e2term→agent SCTP association.
  - It matters for W (§3.5).
- **Influx dump in git.** `runs/live1/influx-kpimon.csv` (4.8 MB) is committed, but `evidence/.gitignore` says "raw Influx dumps stay out of git", and its patterns (`influx-dump*/`, `*.lp.gz`) do not match the file. It contains no token. Practice and comment disagree.
- **rung-config.** `schedules.r1.provenance` cites the kongming report rather than the green evidence (r0's entry cites `073520Z`).
- **Disk.** `/home` free went from 55 G (18:05) to 54 G (19:32) with the VM idle. The active overlay grew only from 2.1 G to 2.2 G. The rest is outside this run, or df rounding. The floor margin should not assume `/home` is static.
- **Commit messages.** Several carry plan labels (for example "record the P4 design"). The user's global rule forbids phase numbers, audit labels and finding codes in commit messages. Do not rewrite pushed history; describe the behaviour from now on.

### 2.4 Milestone report: must-fix before PAUSE A (ordered)
1. **Link this report.** Phase-04 step 5 asks for the segment review as an advice report. Add its path to the milestone (header and Carry-forward) and to the journal §4.
2. **Disk options.** Replace "fewer dev snapshots: `r2-green` is optional to keep" with:
   - skipping `r2-green` needs a user ruling, because it is P5's exit snapshot (V6) and the rollback point for P6–P8;
   - it saves little, because a snapshot boundary only duplicates blocks rewritten after it.

   Add that `/mnt/data` has 21 G free (91 % used), so moving the 2.5 G of local evidence there is a small lever.
3. **Projection arithmetic.**
   - The sentence "−19 GB at P2 and P3 because those projections assumed about 8 G" is wrong for P2: P2 used 11 G (60 − 11 − 48 − 20); P3 used 8 G.
   - State the basis of "~10 remaining dev": P5 ~2, P6 ~5 (ns-3/agent rebuild, M5–M7, R0–R2 single, UL-on dump), P7 ~2, P8 ~2–3. That is 10–12 G, so the projection is **−23 to −25 GB**.
   - State the basis of "~48 M9": f7's measured M0–M7 overlay of 37 G plus about 11 G for i0–r3. It is an estimate, re-measured at P8/P9.
   - Add the 19:32 reading of 54 G.
4. **Report only.** Add the R1 L finding (§2.3) and that T_ctl = 30 s still covers it. It feeds W at P5.
5. **Ruling 8 wording.** Say:
   - the nodes 2 and 3 `late` result was read from the code at the pins, not run;
   - "exactly one FAILURE" holds through every node;
   - V4's "0 ledger lines" holds only through node 1.
6. **Carry-forward.**
   - Add the deadline "finish the P0 partials by P9" (as implementation-notes P0 says).
   - Add that K16 (VM-side traces never deleted) inflates the M9 overlay and so the projection.
7. **Carry-forward: P5 pointer.** Point to §3.3 of this report for the P5 must-do list. The -1705 §9 "segment 2 pre-flags" are otherwise missing from the milestone.
8. **Two small notes.**
   - Live-run late = 0 is enforced through exact expected outcomes, with no explicit field. R2 adds one.
   - The Influx-dump-in-git question. Default: add `influx-*.csv` to `evidence/.gitignore` with a sha256 manifest. Alternatively keep the file and fix the comment. This is the user's call, and either is fine; it is evidence only.

Then:
- commit (describe the behaviour, no plan labels);
- push;
- update the resume card's "kongming notes" (it already names -1815);
- print `PAUSE A evidence=<milestone report or the R1 evidence dir> journal=docs/journals/2026-10-23-m8-m9-stop-a.md` and call no further tool.

The `schedules.r1` provenance fix (§2.3) is harness config. Fold it into the first P5 commit; do not do it now.

## 3. Task 2: P5 go/no-go

### 3.1 Verdict
**GO**, after the user rules on items 1–9. If the user rejects ruling 6 (the rtmgr restart in the reset), P5's reset design (§3.3 step 5) has no L-only remedy, and that is T3 or T5.

### 3.2 New facts verified at the pins (scratchpad clones)
| # | Fact | Source | Consequence for P5 |
|---|---|---|---|
| F1 | The TS xApp descriptor defaults to `ts_control_api: "rest"`, endpoint `http://127.0.0.1:5000/api/echo`. NIST's installer only edits the image fields and runs `dms_cli uninstall` before `install`. | ts `xapp-descriptor/config-file.json:53-54`; Testbed `install_xapp_traffic_steering.sh:99, :157` | G3 needs a harness override: `controls.ts_control_api = "grpc"`, `ts_control_ep = "service-ricxapp-rc-grpc-server.ricxapp:7777"`. Uninstall-first recreates the Service (new ClusterIP), so restart rtmgr afterwards. Also record the deployed configmap's `controls` as proof of G3. |
| F2 | `build_cell_mapping()` runs only on the gRPC path, once, in `main`. It logs `[INFO] nodeb list is …`. | ts_xapp.cpp:890, :812 | That log line is cheap per-run proof that the gRPC mode is active and of the nodeb list it saw (all three CONNECTED). Use it as a precondition, not a judge. |
| F3 | The TS image sets `RMR_SEED_RT=/data/bootstrap.rt`. Its seed table routes 30000 to `service-ricxapp-qp-rmr.ricxapp.svc.cluster.local:4560`. | ts Dockerfile:153; `assets/bootstrap.rt` | The TS xApp's "ready" hides the rtmgr defect, as with kpimon and hw-go. Name the stub something other than `qp`, so the seed route cannot mask a missing rtmgr push. Check that rtmgr's session to the TS xApp's :4561 is ESTABLISHED (the -0830 method). |
| F4 | The TS xApp never sends 20011 and never queries A1. It sends only 30000 and the 30004 return-to-sender. `downlink_threshold` starts at 0. A non-integer threshold reaches `Double()`, which does nothing, so it is silently ignored. | ts_xapp.cpp:96, :159-187, :509-526, :775, :797 | After **every** TS xApp pod replacement, re-create the policy instance. The threshold must be a positive integer. Bring-up precondition: the log line `Setting Threshold for A1-P value: N%`, within a bounded and logged retry. The judge is behavioural (§3.6). |
| F5 | **Prediction parsing:** the first cell key is taken as the serving cell; values count only if unsigned integers; the highest cell wins on a strict `<` over an `unordered_map` (ties go by hash order); an empty serving cell dereferences `end()`; an empty `ue-id` list yields `{"UEPredictionSet": [}`; `stoi(ue_id)` sits outside any try. | ts_xapp.cpp:224-239, :702, :711, :755, :622-624 | Stub rules: list the true serving cell first; integers ≥ 0 only; never a tie; always ≥ 2 cells; echo the decimal IMSI. 30003 rule: exactly one `"ue-id"` given as a JSON **string**. |
| F6 | xfcpp 2.3.6 `Listen` looks up the default callback once, before its loop. With no match and no default, the mbuf stays owned by the `Message`, giving the double free. | messenger.cpp:248-268 | Substitution 2: `xfw->Add_msg_cb(xapp::Messenger::DEFAULT_CALLBACK, <no-op>, NULL)` placed **before** `xfw->Run` (ts_xapp.cpp:905). After Run it has no effect. The corruption may surface later than the next message, so a "no crash" probe is weak evidence (§3.7). |
| F7 | rc ignores the gRPC cell type (the compiled encoder hard-codes RAN parameter IDs 1–4) and the AckReqVal ("not Encoded"). It parses the GUAMI region and pointer with `strtol(…, 2)`. | rc `e2sm/wrapper.c:265-330, :55, :88`; `rc.proto:62` | The TS request's E2SM-RC message equals rc-send's: the same NR CGI, PLMN `00F110` from e2mgr. The header differs: GUAMI 160/0/1 against rc-send's 1/1/0, and F1AP/E1AP IDs equal to the IMSI. Both are inside recorded deviation P4. Add one standards-ledger row (E2SM common v07.00 §6.2.2.6, `QW6VJ83M`) noting this. |
| F8 | QP answers 30002 with `rmr_send`, not return-to-sender. | qp `src/main.py:71` | The stub should also use `rmr_send`, so R2 tests R3's routing path, and P8 does not meet the rtmgr defect for the first time. |
| F9 | The TS image clones `Tencent/rapidjson` HEAD unpinned and builds on `nexus3.o-ran-sc.org:10002/…/bldr-ubuntu20-c-go:1.0.0`. The TS xApp has never been built or installed on this VM. | ts Dockerfile:34, :60-67; no `trafficxapp` in `scripts/` | First-time build risk: a registry outage is T5. Record the TS image digest in `verdict.json`. The image is not bit-reproducible across M9's rebuild; C1 never depends on it. |

### 3.3 Ordered must-do list for segment 2's start
1. **Pre-flight.**
   - Read the user's rulings 1–9.
   - Run the three resume checks and the boot-time check (07:56:59 UTC). If the boot time differs, run gate i0 first.
   - Check `df -h /home`.
2. **Make the names agree before any code** (the r1 lesson):
   - `run-to-m9.sh:63-64` names `gate-i2-ts-xapp-install.sh` and `gate-r2-ts-stub-qp.sh`;
   - phase-05 lists `ts-xapp-install.sh`.

   Default: `gate-i2-ts-xapp-install.sh` covers the TS xApp install with the gRPC override, the stub install and the route checks, and is what M9 runs. `stray-ack-probe.sh` is a one-time dev run with its own evidence dir. M9 does not re-probe; it inherits substitution 2 through the Testbed pin. Record this.
3. **Standards rows before code lands,** read through zotero-mcp:
   - F7's header content under P4 (E2SM common v07.00 §6.2.2.6);
   - a "no spec decision" row for stray-ack routing (O-RAN SC RMR behaviour, not E2AP).
4. **Host-side harness, committed before the VM work.**
   - **(a) `gate-i2`.** Run NIST's installer at the Testbed pin (`commit_hashes.json` pins ts to `19e169b`). Then apply the jq override (F1), re-onboard, uninstall and install, and restart rtmgr. Precondition checks:
     - the TS log shows "listening on port 4560" and no `[ERROR] a control api`;
     - the rtmgr dump shows 20010|20008 → TS, 30002 → TS, and exactly one 30000 receiver, the stub (K12 V7).
   - **(b) Stub.**
     - Registered by its own descriptor under a name ≠ `qp`.
     - rx `TS_UE_LIST`, tx `TS_QOE_PREDICTION`; a default handler that frees.
     - Answers 30002 with `rmr_send`.
     - Fixed predictions come from `r2-scenario.json`, keyed by (imsi, occurrence) and obeying F5.
     - Built from a minimal pinned base; never QP's Dockerfile, which carries the token sed (T7). Record the image digest.
     - Undeployed before any QP deploy.
   - **(c) `send-rmr.sh` (30003, 12041, 12042).**
     - Static seed route to the TS xApp's ClusterIP:4560; RMR route-table service disabled.
     - One string `ue-id` per 30003.
     - Measure its own start-up time. If it is above ~100 ms or jittery, use a persistent injector before calibrating W, so W measures the system rather than the harness.
   - **(d) Gate r2.** A new script that copies r1's run loop. Gates r0 and r1 stay untouched. Shared tools change only additively, each proven byte-equal on **both** `073520Z` and `084654Z`. Deltas against r1 are in §3.4.
5. **Per-run reset for R2,** in this order:
   1. Run the existing `rc_ric_reset`: bucket, rc, kpimon, hw-go, rtmgr restart, rc RMR ready.
   2. Bring up the agents: CONNECTED and subscribed.
   3. Delete the TS xApp and stub **pods**. The Services stay, so the ClusterIPs stay too.
   4. Restart rtmgr a second time.
   5. Check rtmgr has ESTABLISHED sessions to the TS and stub :4561, and dump the routes.
   6. Confirm the TS log's nodeb list (F2).
   7. Ensure policy type 20008 exists; delete and re-create the instance with the integer threshold; wait (bounded) for the threshold log line (F4).
   8. Start the pacer and ns-3.

   Record reset evidence (UIDs, start times) for the TS and the stub, as for rc. Check KPM continuity after the second rtmgr restart: kpimon's indication count equals the wire indication count for each run.

   If A1 never arrives after a Service recreation, the L-only remedy is an a1mediator pod restart. Record it as a T5 reading, like rtmgr. Without a remedy it is T5.
6. **VM, in phase-05 order.**
   1. i2.
   2. The stray-ack probe (§3.7), before the stub starts.
   3. On a crash: substitution 2 (§3.7), reinstall, restart rtmgr, re-probe.
   4. Start the stub and check V7.
   5. Calibration (§3.5).
   6. Commit W, the A1 threshold and the schedule with provenance in `rung-config.json`.
   7. One `--dev` rehearsal (at least 2 consecutive resets, because the stale-endpoint class shows only on the second pod replacement).
   8. The gated C1.
   9. Then V1–V7 (counting Verify fields, not checks), free space, `r2-green`, and the phase exit.
7. **If substitution 2 is applied** (a Testbed commit, so the pin moves):
   - Prove the agent tree is unchanged: `git diff --quiet <old> <new> -- <agent dir>`, plus the same metric-map sha.
   - Record that M5–M7 and R0/R1 stay valid, because no agent code changed.
   - The agent image is rebuilt under its new tag from identical sources.
   - P6's planned pin move and re-validation (M5–M7, R0/R1/R2 single runs) covers it in any case.

### 3.4 Gate r2 relative to r0 and r1
- **Keep:**
  - C8 null-control equals free-run;
  - the one-connection-per-emitter and per-agent check;
  - agent stats taken after bye;
  - the C2 split (static 0, postBye 0);
  - C5, C9, the KPM UE-list moves, restartCounts, route owners in both views, reset evidence, replay, rng2, `--dev`;
  - threshold and T_ctl provenance read from `rung-config.json`.
- **Change:**
  - D7 becomes "every control through the target's agent" (recorded deviation P1). Do not copy r1's 1/2/1 assertion.
  - Positives use T_ctl; negatives use the pacer's existing absence mode (`expect: 0` within W, `pacer.py:21, :278`).
- **Add:**
  - an explicit per-run `late` (must be 0);
  - **wire RICcontrolRequest count = number of positives** in each capture, each request attributed to its trigger by (IMSI, decoded NR CGI key);
  - per positive: the target agent and exactly 1 terminal answer;
  - `wSeconds`, `a1Threshold`, `substitution2Applied`, the TS and stub image digests;
  - per run, whether the TS xApp or the stub held 12041/12042 −1 in either view;
  - RestartCount for the TS xApp and for the stub (as "QP").

  The wire count is stricter than "ledger count + late = 0" and costs nothing. A control from a negative trigger that arrives after the run would otherwise show only as postBye.

### 3.5 W calibration
- Define L exactly as the gate does: from the start of the 30003 send to ns-3's `controlRx`.
- With n = 10, p99.9 cannot be estimated; in practice it is the sample maximum. Write W = max(1 s, 3 × max L), record n, and prefer 20–30 positive triggers, since each costs milliseconds.
- **The calibration must use the gated per-step shape:** one trigger per step, the same agents. R1 shows the shape alone moves L from 8 ms to 200 ms.
- Also confirm 20 × L_max ≤ T_ctl. If the TS path breaks this, report it; T_ctl is not re-set at R2 by contract.
- An undersized W fails loudly: a slow control becomes a `late` line or a post-bye FAILURE, so the gate goes red and never falsely green.

### 3.6 R2 scenario shape (RngRun 1, −1000; IMSIs 1 and 2 on cell 3, IMSIs 3–6 on cell 2)
- **Positives:** at least one per gNB key (`0000000202`, `0000000303`). Each IMSI is used in one step only. One trigger per step.
- **Negatives:**
  - (n1) the serving cell is best;
  - (n2) the neighbour is above the serving cell but under the threshold. With threshold T = 10, use serving 100 and neighbour 105. Under threshold 0, n2 would be a positive, so **0 ledger lines for n2 proves the A1 policy took effect on the wire.**
- Never a tie between cells (F5). Keys are uppercase `%08X%02X`. `ue-id` is the decimal IMSI string.

### 3.7 Stray-ack probe
Probe settings:
- Run it on a freshly installed TS xApp, before the stub exists.
- Send directly to the TS xApp's RMR endpoint through a static seed route (K12), and record that endpoint.
- Use **real payloads**: an ACK and a FAILURE PDU taken from the R1 pcap. tcache behaviour depends on the chunk size.

Sequence:
1. Exactly as phase-05: one 12041, then one 30003.
2. A burst variant: three of each of 12041 and 12042, interleaved with 30003.
3. Wait at least 10 s after the last message.

Record:
- pod UID and RestartCount, before and after;
- `lastState.terminated` reason and exit code (134 means SIGABRT);
- glibc's message, if any.

`crashed` = any restart or termination. **This strengthens the probe and does not change the user's rule** (probe first, patch only on a crash).

If `crashed: false`, the gated runs still carry the stray-ack risk whenever the TS xApp holds the −1 route. The per-run owner record (§3.4) is what attributes any later RestartCount > 0. Apply substitution 2 exactly as in F6, through the Testbed installer: an idempotent edit, made before `docker build`.

## 4. Task 3: T-triggers
**None fires now.**
- **T1 and T2:** no deletion is needed, and 54 G is free.
- **T3:** no material mismatch (§2.1, §2.2). The resume card matches the live state.
- **T4:** the unannounced RAN function 3 was known before the contract and approved, and is ruling 4; it is not new.
- **T5:** the rtmgr finding has an L-only remedy and is ruling 6.
- **T6:** no failed Verify.
- **T7:** the token grep is 0.
- **T8:** the P0 refusal is not a scripted command under the locked definition, and is ruling 1.

P5 risks:

| Trigger | Risk | Mitigation |
|---|---|---|
| T5 | The first TS build pulls from nexus3. A1 may not reach a replaced TS pod. | Pull the base image first in i2. Use the a1mediator-restart reading (§3.3 step 5). |
| T3 | Any TS xApp code need beyond substitution 2: ties, the empty list, the missing A1 reply. | Avoid each one through stub and scenario design (F5), never by patching. |
| T6 | Integration defects reaching the first Verify. | Use the `--dev` rehearsal with at least 2 resets, and count Verify fields. |
| T7 | The stub built from QP's Dockerfile. | Forbidden (§3.3 step 4b). |
| T8 | `sudo dms_cli` or `ctr` from the NIST installer. | Run only inside scripted gates through `vm-exec.sh`; a refusal pauses. |

## 5. What to avoid
- Relying on the TS xApp's Ready status or on its seed table.
- Naming the stub `qp`.
- Assuming the A1 threshold survives a TS xApp restart.
- A float threshold.
- Equal predictions.
- Copying r1's D7 assertion into r2.
- Calibrating W with a different per-step shape than the gate.
- Registering the default callback after `Run`.
- Editing gate r0 or gate r1.
- Plan labels in commit messages.

## 6. Alternatives and trade-offs
- **Reset alternative: agents first, then one combined reset with a single rtmgr restart.** It saves about 30 s per run, but it reorders a reset already proven green and changes when kpimon subscribes. Rejected for R2; reconsider only if the double restart misbehaves.
- **Stub replies with return-to-sender.** More robust against stale endpoints, but it leaves P8's routing path untested until R3. Rejected; use `rmr_send` (F8).
- **G3 through a Testbed installer change** (environment-driven `ts_control_*`). Cleaner, but it moves the Testbed pin without substitution 2. Prefer the harness jq override; take the installer route only if substitution 2 moves the pin anyway.

## 7. Success metrics
- PAUSE A is printed after the 8 record fixes, with no new run.
- P5: i2 passes on its first run; `probe.json` records both variants; W and the threshold are committed with provenance before the gate; the R2 rehearsal and C1 pass V1–V7 with:
  - wire requests equal to positives;
  - 0 lines for n1 and n2;
  - late 0;
  - postBye 0;
  - TS and stub restarts 0;
  - both gNB keys covered.

## 8. Assumptions
- **The user accepts ruling 6.** Medium confidence. Otherwise P5's reset has no L-only remedy (T3 or T5).
- **The stale-endpoint class also affects a1mediator → TS.** Low-to-medium confidence, unverified, so it is mitigated by a precondition check, not assumed fixed.
- **appmgr lists the TS xApp through helm,** although xfcpp 2.3.6 never registers itself; nothing under xfcpp `src/` registers. Medium confidence; i2's route dump verifies it.
- **The 200 ms L comes from SCTP.** Low confidence (speculation). It does not change the advice, which is to calibrate with the gated shape.
- **The line numbers are correct at the pins** named above, from scratchpad clones on 2026-10-23.

## Unresolved questions
- The user's rulings 1–9, and the Influx-dump-in-git choice (§2.4 item 8).
- The a1mediator API version and path in this L-release deployment (`/A1-P/v2/...`). Check on the VM in i2.

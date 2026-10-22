# Kongming advice checkpoint: M8–M9 delivery contract (winner D)

Date 2026-10-22 KST. Advisory only; no project files changed except this report. Model: Opus 5.5 at xhigh (user CLAUDE.md overrides the `fable` routing).
Inputs: `brainstorm-261022-1739-…-m8-m9-delivery-contract.md`, `verifier-261022-1723-…-ultra-verdict.md`, `brief-261022-1713-…-evidence-packet.md`.
Spot-checks at the pins: TS 19e169b, rc a2282ee, QP 47a35ca, kpimon 8bbbbbb (+ NIST patch), ric-plt-e2 5aa396f, ns-3 ace32168, Testbed 725b167. Scratchpad clones (not committed): xapp-frame-cpp tag 2.3.6, RMR tag 4.8.1, rtmgr tag 0.9.6.

## TL;DR

**GO for `ak:plan` after one user round** (the 6 questions in §3). D's core design holds on source.

One new defect, missed by both D and the verifier:
- Under N1(b), stray control acks can land on TS.
- TS's C++ framework frees the buffer twice for any message type it has no handler for.
- Because the pod resets re-roll the route on every run, this is a likely crash that makes R2, R3 and M9 flaky.
- The plan needs a guard (Q4).

Everything else is an acceptance amendment (group b) or a drop.

## 1. Go / no-go

**GO, conditional on the user answering §3, or accepting the recommended defaults.**
- **The load-bearing parts are verified:**
  - F3 (TS addresses the target's agent);
  - N5 needs raw octets;
  - the R1 in-handover refusal is synchronous;
  - rc's FAILURE path is safe;
  - XER renders octets as uppercase hex.
- **The verifier's defects are additive:** missing tests and predicates. None forces rework.
- **The TS stray-ack path is the exception.** It only bites from R2 onward, so the plan can schedule a cheap probe plus a guard before R2.
- **No further research is needed before planning.**

## 2. Sorting: (a) user, (b) fold into the plan, (c) drop

### Verifier defects (verdict §5)

| # | Defect | Grp | Amendment / reason |
|---|---|---|---|
| 1 | D2 freeze-then-fail is never exercised | b | Add a forced fault run: the agent withholds `step{k}`. The run aborts within T_gate + 5 s, the verdict names k, and there is no ledger line after k (B C8). Follows from D2. |
| 2 | The bye/EOF FAILURE-all-pending rule passes vacuously | b | Add an R1 case with a control after the final barrier (B R1(e)). The wire must show exactly one FAILURE per pending request. Follows from packet §4. |
| 3 | C1 omits KPM headers and `colletStartTime` | b | Add both to C1's byte-equal set. Pinning them is D10's stated purpose. |
| 4 | N6 checks only seq T | b* | The pacer checks every seq in QP's 1600 sim-ms window (16 steps), not only T. *Applies if the user approves N6 = pacer (Q6). |
| 5 | No recalibration of T_ctl or W | b | R0: set T_ctl from the measured L (journal §6). R3: a calibration run that includes QP's first inline training, then W = max(1 s, 3 × p99.9) (E). |
| 6 | Health check omits kpimon and hw-go | b | RestartCount = 0 for **every** xApp (rc, TS, QP, kpimon, hw-go) and for the agents. TS and QP are added because of §5.1. |
| 7 | Snapshot deletions are planned automatically | a | Q3. |
| 8 | N7 misses installer steps | b | Verified. `install_xapp_qoe_predictor.sh:62-68` clones gerrit `qp.git` into `qp`, then runs `cd qp`; the fork's URL basename `ric-app-qp` breaks that, so pass NAME=`qp`. The Dockerfile sed (`:112-118`) and the token sed must survive the switch. Add a gate check that the token never appears in the public fork's tree. |
| 9 | The eNB request part | b | Keep the eNB's request part non-matching (stock `reqpart`). D4 refuses non-mmWave targets as `unknownTarget`. R0's G4 check reads "every **gNB** agent". |
| 10 | Demo mode is not addressed | a | Q5. |
| 11 | The N5 caveat can be narrowed | b | Narrowed further: e2term's XER emits uppercase hex (`RIC-E2-TERMINATION/3rdparty/oranE2/OCTET_STRING.c:604`). The only R0 check left is B's offline replay of TS's `cell_map` algorithm on the nodeb JSON. |
| 12 | Key format nit | c | Keep D's `%08X%02X`, with no user question. rc copies the octets raw, and nothing decodes the NCI. Strictly, neither form is NCI-correct, because a 4-bit cell ID belongs in the high nibble of byte 5. Record that in the plan. |

### Ideas from the losing candidates

- **(a) user:**
  - B: `--outageThreshold=-1000` (Q2);
  - C: the agent-reject cause mapping (Q5);
  - C: no snapshot for R1 (Q3).
- **(b) fold:**
  - **B:**
    - the offline TS `cell_map` replay at R0;
    - the QP image digest and `pip freeze` recorded in `verdict.json`;
    - QP model files exist only after this run's restart;
    - R1(d): a same-IMSI pair through two agents, where the lower nodeId wins (this tests C4's nodeId field).
  - **E:**
    - `RRU.PrbUsedDl` variance as N4 evidence, re-checked at 2 gNB on R1's dump;
    - the calibration run (merged into #5);
    - the QP unit-test list plus an in-image forecast SHA;
    - N7 commit 1 verified as an empty tree diff against gerrit + `git apply`;
    - ledger detail causes `alreadyOnTarget|inHandover|unknownImsi|unknownTarget|lteFallback|late`, while the E2AP cause stays `control-failed-to-execute` (D2);
    - HandoverStart row count == applied count;
    - M9 runs one live run per lower rung and the full C1 on R3. D is silent here, so state it (see Unresolved 2).
  - **C:**
    - zero handover rows in the null-control run;
    - `OPENBLAS_NUM_THREADS=1` and `OMP_NUM_THREADS=1` as the **default** in the QP image, not a fallback.
  - **A:**
    - R0 measures apply → HandoverEnd (report only; it feeds the realism pass);
    - a global M9 wall deadline;
    - "a control at a non-trigger step is late", which makes C7 explicit.
- **(c) drop:**
  - B, the QP fork in fixed-prediction mode as R2's stub: it couples R2 to the fork and to N7 (the verifier marked it ✘).
  - B, building pacer injection before the agent control path: D's S0 → S1 order is fine, so this is the planner's call.
  - C, anchoring W on QP's write-back: superseded by the calibration run.
  - A, R0 refuses a handover to the serving cell: already in D's R0.

## 3. User questions (6, plain language)

**Q1. What must R2 and R3 prove?**
- **Recommended:**
  - **R0** keeps the full D7: ≥ 2 IMSIs moved to gNB 2 and gNB 3, with ≥ 1 control through a non-target agent, the eNB agent included.
  - **R1** meets D7 by construction.
  - **R2:** ≥ 2 IMSIs to ≥ 2 targets, chosen by the stub, with the non-target clause dropped.
  - **R3:** ≥ 1 QP-driven handover plus full C1 determinism. Report ≥ 2/≥ 2 if it happens, but do not require it.
- **Reason:**
  - TS always sends a control to the target's own agent (`ts_xapp.cpp:639-643`), so from R2 on the non-target clause cannot be met.
  - Real QP's choices cannot be predicted, and R3 is a functional demo (D5).

**Q2. Should paced rungs add `--outageThreshold=-1000`?**
- **Recommended:** keep the default −5 dB (D3 as written), unless S1's null-control run shows ≥ 1 LTE switch in the M8 config. In that case, add −1000 to the paced-rung arguments only, before R0. Keep D4's LTE-fallback refusal either way.
- **Reason:** −1000 is ns-O-RAN's own hint for NoAuto (`scenario-zero.cc:173-176`). But the journal says NoAuto "keeps the outage fallback" (D3), so decide on evidence.

**Q3. Which snapshots do we keep, and do we delete any?**
- **Recommended:** plan no deletions.
  - Keep `fresh-install`, `f7-rerun-green`, `r0-green`, `r2-green` and `r3-green`.
  - Skip `r1` because R1 is harness-only on the same image.
  - Check free space before each snapshot. Ask the user at the moment any deletion would be needed.
- **Reason:**
  - P5 showed that deleting a non-leaf snapshot frees almost nothing and needs temporary space about the size of its overlay (P5 README lines 25 and 31).
  - The real space consumer is M9's fresh overlay; P5's merged install chain was 39.7 GB.

**Q4 (new). TS can crash when a stray control ack reaches it. How do we guard against that?**
- **Recommended:** run a 10-minute probe before R2: send TS one 12041, then one 30003.
  - If TS dies, allow a 1-line TS patch, applied by the Testbed fork's installer, that registers a do-nothing default RMR callback.
  - If TS survives, change nothing.
- **Reason:**
  - rtmgr gives **every** xApp a 12041/12042 route at subid −1 (`rtmgr pkg/rpe/rpe.go:165-177`).
  - TS has no default handler, and its framework frees the buffer twice (§5.1).
  - The per-run pod resets in C8 re-roll which xApp owns that route on every run.
  - The alternative that leaves TS unchanged is a per-run route-table check and re-roll. It is fragile if rtmgr regenerates the table mid-run, which is unknown (probe Q1).

**Q5. Two D2 clarifications.**
- **(a) Build demo mode (continue-and-flag) now?** Recommended: **no.** Make it a post-M9 non-goal.
- **(b) Which cause does the agent use when it rejects a malformed control itself, before ns-3?** Recommended: E2AP-specific causes:
  - `ran-function-id-invalid` when the RAN function is not 3;
  - `control-message-invalid` when the E2SM-RC header or message does not decode;
  - `action-not-supported` when the style or action is not 3/1.
  - Every refusal inside ns-3 and every late control keeps `control-failed-to-execute`.
- **Reason:**
  - No gate exercises demo mode, so it would be untested pacer code.
  - Gated runs require 0 agent-local rejects (C6), so (b) changes no gate and follows E2AP's cause meanings.

**Q6. Accept N1–N7 as recommended?**
- **Recommended:** yes.
  - **N1 (b), gate on the wire only.** Option (a) cannot be done in scope anyway: rtmgr adds a −1 route for every xApp, and rc's instance IDs are hard-coded.
  - **N2:** P1 pins.
  - **N3:** restart the QP pod each run.
  - **N4:** `RRU.PrbUsedDl`, with `DRB.MeanActiveUeDl` as the fallback.
  - **N5:** 5 raw octets in `%08X%02X` layout.
  - **N6:** the pacer, with the widened predicate (#4).
  - **N7:** the fork carries NIST's 4 patches as commit 1.
- **Reason:** each is the only measured or source-verified option, and none reopens D1–D10.

## 4. Next risk to watch in planning

**Primary: RIC state that sits outside the determinism envelope.** ns-3 and the pacer are deterministic; the RIC is not:
- which xApp owns the −1 ack route (Go map order, re-rolled on every pod reset);
- TS's `cell_map`, built once at startup;
- rc's ack panic path.

Unless the plan treats RIC state as a measured per-run precondition, R2/R3's 3-run C1 and the unattended M9 will flake. Concretely:
- Dump the route table at the start and end of every run, and record the 12041/12042 −1 owner in `verdict.json`.
- Require RestartCount = 0 for all xApps.
- Restart TS only after every agent is CONNECTED.
- Schedule the TS stray-ack probe (Q4) in the first RIC-facing phase.

**Secondary risks:**
- **M9 disk.**
  - The fresh-install overlay will be about 40 GB. This is inferred from P5's 39.7 GB merged chain, not measured.
  - The rung overlays come on top of that, against 77 G free and a 20 GB floor.
  - Budget it at R3, before M9, not during it.
- **R3 vacuity.** Real QP may never pick a better cell. Choose R3's fixed trigger schedule from an offline dry run of the QP fork on recorded R1/R2 Influx rows, and say so in the verdict.
- **S0 overload.** S0 lands 8 changes in one image. Plan them as separately verified commits:
  - check the free-run digest is unchanged after D4 lands (D4 must not create RNG streams, per the D5 landmines);
  - re-pass M5–M7 at the end of S0.

## 5. Errors in the winner that the verifier missed

1. **N1(b)'s premise is incomplete. (New finding; medium-high confidence on the code path.)** F1 and F2 cover only rc and kpimon. The chain:
   - **TS gets the route.** rtmgr 0.9.6 `pkg/rpe/rpe.go:165-177` gives every non-platform xApp that has any tx/rx message a `RIC_CONTROL_ACK`/`FAILURE` route at subid −1. So TS and QP join the lottery in R2 and R3 (the live dump shows rc, hw-go and kpimon entries).
   - **TS has no default handler.** It registers only 20010, 30002 and 30003 (`ts_xapp.cpp:901-903`).
   - **The framework frees the buffer twice.**
     - TS uses xapp-frame-cpp 2.3.6 (TS `Dockerfile:45`). In its `messenger.cpp:259-266`, when no callback matches, `mbuf` stays owned by the `unique_ptr<Message> m`.
     - RMR 4.8.1 then frees that buffer on the next receive (`rmr_si.c:962-963`, `:1021-1022`).
     - The next `m =` assignment frees it again (`message.cpp:137-143`).
   - **It is a real double free.** RMR is built without `KEEP`, so `rmr_free_msg` calls `free()` directly (`rmr_si.c:248-256`). The runtime image is `ubuntu:20.04` (TS `Dockerfile:108`), so glibc 2.31 should abort at TS's next message, which is the next trigger.
   - **Not observed live.** The probe saw 0 acks on RMR, because the agents send none yet.
   - **The other xApps are safe.** QP's default handler frees the buffer correctly (`main.py:53-59`). kpimon discards unknown types (`control.go:649-653`), and the NIST patch leaves that code alone.
   - **Effect:** N1(a)'s "rc as the sole −1 owner" is infeasible without undeploying TS, QP and kpimon. N1 is therefore forced to (b), and (b) needs a TS guard (Q4).
2. **C2's count identity breaks in the very fault runs that #2 adds.** "#control read by ns-3 = #ledger lines = #terminal answers" fails as soon as a post-bye FAILURE exists. The verifier caught this for A but not for D. Amend it to: #terminal answers = #ledger lines + #agent-local FAILUREs, counted separately for static rejects and for bye.
3. **Copy hazard in the controller's appendix (not in D's body).** It says "raw bytes `00 00 00 0N 0C`, which render as `00000000NC`". Those bytes render as `0000000N0C`. D's body (`0000000202`) is correct, so the plan must copy from the body.
4. **TS calls `stoi(ue_id)` outside any try block.**
   - The call is at `ts_xapp.cpp:622-624`. Only the JSON parse is guarded (`:680-684`); the send at `:729` is not.
   - So the stub's and the QP fork's `ue-id` must be the decimal IMSI. A non-numeric ID throws an uncaught exception and terminates TS.
   - The agent must map AMF-UE-NGAP-ID to IMSI.
   - Fold this into the R2/R3 criteria and the QP unit tests.
5. **The N5 trade-off row is slightly off.** Case does not "depend on e2mgr"; e2term's XER output is uppercase. The remaining constraint is that QP's `cellKey` must emit uppercase, because TS's `cell_map.find` is an exact match (`:639`).
6. **Minor: R2's negative cases need not be "labelled statistical".** With the stub QP and harness 30003, TS's decision is deterministic. Check negatives by ledger count, plus late = 0 for the rest of the run.

**Verified OK (no action needed):**
- F3: `ts_xapp.cpp:639-647`. The TS key algorithm is a 10-character substring at the uppercased ranName suffix (`:331-373`).
- R1's in-handover refusal is synchronous. `PerformHandoverToTargetCell` sets `m_mmWaveCellSetupCompleted[imsi]=false` (`lte-enb-rrc.cc:4519`), and its guard reads that flag (`:4493`). So a second control in the same step sees "in handover".
- rc's FAILURE handler decodes no outcome (`rcControl.go:358-385`). ControlOutcome Format 1's list is `SIZE(0..)` (`e2sm-rc-nov2021.asn:1300`), and the outcome decoder handles a nil result (`rcE2SmRc.go:141-143`).
- `scenario-zero.cc:173-176`: the default is −5 dB, with the hint "use -1000.0 with NoAuto".

## Assumptions

- **N1–N7 are not yet user-approved** (packet §5: "the user decides"). Confidence high. If they are already approved, drop Q6.
- **TS dies on a stray ack.** Based on static reading, not a run. Confidence medium-high on the code path, medium on whether it aborts or corrupts silently. The Q4 probe settles it.
- **M9's overlay is about 40 GB.** Inferred from P5's chain size. Confidence medium. Measure it at R3.
- **"TS and kpimon are not forked" (H4) is user-locked.** Confidence high, which is why Q4 is a question and not folded in.

## Unresolved questions

1. Does rtmgr regenerate, and so re-order, the table mid-run (probe Q1)? The answer decides whether a per-run route check could replace the TS patch.
2. How many runs does M9 make on the lower rungs: 1 live run each (default, E) or the full C1? Flip the default if the user reads D8 as binding inside M9.

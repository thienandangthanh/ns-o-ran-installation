# M8–M9 delivery contract (brainstorm --ultra --advice winner)

Date: 2026-10-22 17:39 KST. Input: `plans/reports/brief-261022-1713-GH-1-m8-m9-contract-evidence-packet.md`. The winning candidate is reproduced **unchanged** below; the verifier's ranking and the defects to resolve follow in the appendix.

---


I worked read-only: no files written, no VM or git changes. I re-checked five facts in source that the packet does not state. They change the recommendations below.
- **F1 (rc does not wait for the ack).** rc queues the request (`ric-app-rc@a2282ee control/rcService.go:39`) and answers gRPC `GRPC_SUCCESS` straight away (`:50`). When its ack timer runs out it only logs: the "Send ErrorIndication" at `rcControl.go:176-181` is a comment, and there is no retry. Whether an ack reaches rc therefore changes nothing that TS or ns-3 sees.
- **F2 (stray acks are harmless at kpimon).** kpimon logs and discards any message type it does not know (`kpimon-go@8bbbbbb control/control.go:649-653`). I did not re-read the NIST-patched copy.
- **F3 (TS addresses the target's agent).** TS sends each control to `cell_map[target]`'s ranName (`ts_xapp.cpp:643`). So in R2/R3 every control goes through the target's own agent. D7's "through a non-target agent" clause can only be met at R0/R1.
- **F4 (cell key must be pure hex).** rc builds the CGI as `hex.DecodeString("00"+PLMN+TargetCellID)` and ignores the error (`rcE2SmRc.go:101-102`). A key that is not pure hex silently produces a short, wrong CGI.
- **F5 (outage fallback writes no handover row).** Under NoAuto the outage fallback calls `SendRrcConnectionSwitch` and writes no HandoverStart row (`lte-enb-rrc.cc:4755-4780`). The trace join stays one-to-one, but D4 must refuse a UE that is on LTE fallback.

## 1. Outcome
Paced closed-loop rungs R0 (= M8), R1, R2 and R3 each pass their repeat gate: 3 live runs plus 1 replay, bit-identical (D8). Control flows rc, then TS + stub QP, then TS + QP fork, into ns-3 handovers. M9 reaches R3 by one unattended run from `fresh-install`, and its R3 ledger and digests equal the dev reference.

## 2. Constraints
- Every decision locked in packet §2 stands: D1–D10 and the earlier ones.
- Gates are scripted and clone forks at the SHAs in `scripts/pins.conf`. QP gets its own URL/SHA lines there.
- Verdicts come from decoded wire bytes, the ledger, ns-3 traces and digests. rc's log is never evidence.
- Keep ≥ 20 GB free on the host. Never delete `fresh-install`.
- Free-run stays the default. M5–M7 gates must stay green after every change to the agent or ns-3.
- Code lives on `dev/l-release-nist180` of ns-3, oran-interface, the Testbed (agent) and QP. The harness lives on the parent branch.

## 3. Non-goals
- **Post-M9 realism pass:** a whole-loop delay plus `UseIdealRrc=false`. No delay attribute and no `ApplyDue` scheduled branch in this scope.
- Pacing overlap (struck), a shorter period, and leaving NoAuto.
- Forking kpimon or TS, fixing real AD, and building any AD path to UEReports.
- The `DlE2RlcStatsLte` cols 5–6 fix (Q3; stays excluded).
- Improving QP's prediction quality (the raw vs differenced model mismatch). Option B per-subscription aggregation. The default 12-UE config.
- Making rc receive its acks (see N1), and any rtmgr or e2term changes.

## 4. Acceptance criteria (all pass/fail)
**Common to every paced rung (C)**
- C1, repeat gate: 3 live runs with explicit `--RngRun` and pinned `simStartEpochMs`, plus 1 ledger replay without the RIC. Each must be byte-equal on:
  - the ledger, excluding `diag`;
  - the IPC `sample` lines, with `hello` excluded and `ipcDropped` = 0;
  - every ns-3 trace file, except `DlE2RlcStatsLte.txt` cols 5–6;
  - the per-step **multiset** of (decoded E2SM-RC content, terminal answer type).
  `--RngRun=2` must change the digest.
- C2, ledger schema: lines `(rxSeq, rxSimTimeNs, applySimTimeNs, viaNodeId, imsi, sourceCell, targetCell, outcome, cause)`, plus a header recording δ-model = fixed 0. Lines are written at apply time in sorted order. The gate checks four things per line:
  - `applySimTimeNs − rxSimTimeNs == 0`;
  - `rxSeq == afterSeq`;
  - `rxSimTimeNs` equals the barrier time of `rxSeq`;
  - the counts match: #`control` read by ns-3 = #ledger lines = #terminal E2AP answers.
- C3, apply-time contract (D5):
  - State prechecks run only inside D4. They refuse: unknown IMSI, unknown target, already on target, in-handover, and LTE-fallback (F5).
  - ACK = D4 returned `applied`. Every ACK carries a ControlOutcome Format 1 that decodes on the wire.
  - Every refusal and every late control gets a RICcontrolFailure with cause `control-failed-to-execute` (D2).
  - ns-3 never aborts on a control.
- C4, sort key: `(imsi, nodeId, targetCellId, ctlId)`.
- C5, pairing: the gate pairs each request with its answer by (requestorId, instanceId) within a run, never by step. Acks route back through `viaNodeId`.
- C6, agent:
  - holds N pending controls keyed by `ctlId`, with no wall-clock ack timer;
  - on `bye`/EOF, sends FAILURE for every pending control, and the wire shows exactly one terminal answer per request;
  - static rejects in gated runs = 0.
- C7, deadlines: under D2 a deadline run-out fails the run with a verdict that names the step. The margin report covers min slack per deadline, late = 0, restarts = 0 (agents, rc, TS, QP) and `droppedNoSub` = 0.
- C8, equivalences:
  - null control: lock-step with no controls gives the same digest as free-run;
  - pacing stays opt-in, and the M5–M7 gates re-pass;
  - per-run reset: rc, TS (after all CONNECTED, then the A1 threshold set explicitly), QP, and a fresh Influx bucket.
- C9, handover trace (Q4): each `applied` line is followed by a `UeHandoverStartStats` row with time ≥ apply (compared at the trace's printed precision), the same imsi, its target, and source ≠ target. A later `UeHandoverEndStats` row for that imsi and target follows. No start row exists without an `applied` line. A refused control writes no row.

**R0 = M8.** Config: `--nMmWaveEnbNodes=2`, NoAuto, real rc driven by scripted gRPC.
- D7: ≥ 2 IMSIs handed over to targets on gNBs 2 and 3, with ≥ 1 control through a non-target agent, the eNB agent among them.
- For each control: one decoded RICcontrolRequest and one terminal answer. The IMSI moves between the gNBs' decoded KPM UE lists.
- One deliberate already-on-target refusal. It exercises the `epc-x2.cc:693` guard and must give FAILURE, a `refused` line, no handover row, and ns-3 still running.
- G4 is verified on this rung: the e2mgr nodeb JSON for every agent decodes to its N5 key.

**R1.** Scripted, several controls.
- One same-step pair for two IMSIs through different agents.
- One same-IMSI pair through **the same agent** with different targets. The lower `targetCellId` is applied; the other is refused in-handover (this proves the C4 fix).
- One unknown-IMSI refusal.

**R2.** Real TS with gRPC to rc:7777 (G3), stub QP, harness 30003 carrying one UE per message.
- `cell_map` covers every agent's key. Shown by: each positive trigger produces a wire RICcontrolRequest whose CGI carries the stub's chosen key, addressed to the target's agent (F3).
- Positive cases pass C1.
- Negative cases (serving best, or below threshold) show no RICcontrolRequest within W and are labelled statistical.

**R3.** Real TS plus the QP fork (D6). Fixed trigger schedule; the pacer certifies that the rows are in Influx (N6).
- ≥ 1 handover applied from a QP-driven decision.
- Every trigger's outcome (control or none) is identical across C1's runs.
- QP never sends 30002 without a valid serving pair (G7). eNB UE rows are excluded. Values are clamped to uint32.
- The QP fork's offline test of exact package pins shows a bit-identical forecast across 3 runs inside the image.

**M9.**
- Revert `fresh-install`, then make one invocation with no prompts. Exit code 0.
- `verdict.json` lists M0–M7 and R0–R3 with pass/fail and pins, and the highest green rung is R3.
- That rung's C1 passes, and its ledger and digests equal the committed dev reference.
- Free disk stays ≥ 20 GB throughout.

## 5. Recommendations N1–N7
- **N1 = (b)**, gate on the wire only.
  - Reason: by F1 and F2 a misrouted ack changes nothing that TS or ns-3 sees.
  - Fix (a) is fragile. rtmgr reorders the `-1` routes on each rebuild, and rc's IDs 2, 4, … collide with submgr's 1–5 (`probe-261022-1544…` §Answer).
  - Add rc RestartCount = 0 as a check (C7), since G8 can still fire if an ack ever lands at rc.
- **N2 = P1 pins:** pandas 1.5.3, numpy 1.26.4, statsmodels 0.14.6, scikit-learn exact, base image pinned by digest.
  - Reason: this is the only combination measured working and deterministic (research §2.2, Q9). P2 has not been measured on pandas 3.
- **N3 = M2**, restart the QP pod per run.
  - Reason: no new code, and G10 already requires the reset. With a fixed trigger schedule, training-once is deterministic (research §3).
- **N4 = U2, `RRU.PrbUsedDl`**, DL first.
  - Reason: no change to the agent or the M6/M7 data.
  - It must be non-constant in the 16-row window of the M8 config (adfuller crash, research §1.3). Check this on R1's Influx dump. The fallback is `DRB.MeanActiveUeDl`.
- **N5 = key `%08X%02X`(gNB-id, cellId)**, for example `0000000202`.
  - The agent puts these 5 raw bytes in `e2nodeComponentRequestPart`; it is 4 bytes of the ranName suffix plus the cell byte.
  - QP's `cellKey(nodeId)` emits the same string.
  - The agent parses the target from the last 5 bytes of rc's `00‖PLMN‖key` CGI and refuses anything that does not match.
  - Reason: TS takes `substr(i,10)` at the uppercased suffix (`ts_xapp.cpp:335-373`). Within this scope (cellId ≤ 9) the key is all digits, so it is both case-proof and valid hex (F4).
  - The same layout ran live in M-RC4 on the old stack (journal 2026-06-28). It is **unverified on this e2mgr** until R0.
- **N6 = the pacer.**
  - Reason: ns-3 is frozen at barrier T, so there are no T+1 rows (K2).
  - The pacer already knows the trigger steps. It can count Influx rows with `ns3.simTimeMs == T` against the records in IPC sample k, and report that margin.
  - A QP-side wait would put a wall-clock wait inside QP.
- **N7 = the fork carries NIST's 4 patches as its first commit**, then our changes on `dev/l-release-nist180` from 47a35ca.
  - The Testbed fork drops QP's 4 `git apply` steps and changes the URL and the `commit_hashes_l_release.json` entry. pins.conf gets `QP_URL`/`QP_SHA`.
  - Reason: about 100–150 changed lines need to be tested inside the QP repo. A patch on top of patches cannot be unit-tested (research §4).

## 6. Trade-offs
| Choice | Option: depends most on → fails first when |
|---|---|
| N1 | (b): rc's output does not depend on the ack (F1) → an rc version that blocks gRPC on the ack. (a): stable rtmgr route order → the first rtmgr regeneration. |
| N2 | P1: the image resolves a pandas 1.5.3 wheel for its Python (3.11 per research §5) → a base-image Python bump. P2: no other pandas-3 breakage → the first untested call path. |
| N3 | M2: the trigger schedule is fixed and the first training window repeats → the trigger schedule changes or the restart is skipped. M1: fit cost < W → about 19 VAR fits per cell exceed W (not timed). |
| N4 | U2: the metric varies under the M8 load → full-buffer saturation makes it constant. U1: ns-3 gNBs expose UL PDCP (unverified) → they do not, and the M6/M7 data change. |
| N5 | Digit key: ≤ 9 cells → a cellId ≥ 10 brings hex letters back, and then case depends on e2mgr. |
| N6 | Pacer: the expected row count can be derived from IPC sample k → kpimon drops a write (blocking write error). QP: knows the topology → needs a wall-clock wait. |
| N7 | Patches as first commit: NIST's QP patches stay static → a NIST bump forces a manual rebase. 5th patch: changes stay small → the ≥ 100-line edit. |
| Sort race | `targetCellId` in the key: the ledger and wire are compared as multisets with no `ctlId` → someone adds `ctlId` to the ledger. Different agents: the scenario author remembers the rule → R2/R3, where TS picks the agent (F3). |

## 7. Better approaches
Better approaches: none — recommended direction is the requested one (D1–D10 hold against F1–F5; the one improvement is sequencing, §8).

## 8. Sequencing
1. **S0, ns-3 + agent in free-run**, one agent image:
   - D4 method; ledger; `viaNodeId` routing; C4 sort; agent pending/bye logic; Format 1; D2 cause;
   - **the G4/N5 request part, landed now**, so R0–R3 share one image;
   - M5–M7 re-pass.
2. **S1, barrier + pacer:** Fallback-1 scripted lock-step without the RIC, the replay sink, and null-control equivalence.
3. **R0**, then snapshot `r0-green`. Delete `f7-rerun-green` only after `r0-green` reverts and boots.
4. **R1**, then snapshot `r1-green`. Delete `r0-green` after a free-space check.
5. **In parallel from S0:** QP fork (D6) plus N2 pins, unit-tested on R1's Influx CSV inside the image, then the Testbed pickup (N7).
6. **R2:** G3 config, the stub RMR peer (30003 out, 30000 in / 30002 out), an rtmgr route dump. Then snapshot.
7. **R3**, then snapshot.
8. **M9** from `fresh-install`.

Before every snapshot: free space ≥ 20 GB + estimated overlay.

## 9. Risks and unknowns
**Discoverable**
- How e2mgr renders the request part on this stack: check the nodeb JSON at R0.
- Whether the outage fallback fires in the M8 config: grep the null-control run for LTE switches.
- Whether `RRU.PrbUsedDl` varies: check R1's Influx data.
- Whether QP's lag search (1..19) fails on short windows: offline in the image.
- QP training latency against W: time it in the image.
- statsmodels/BLAS determinism inside the image.
- Routes for 30003/30000/30002: rtmgr dump at R2.
- Whether hw-go survives stray 12041/12042: its RestartCount.

**Unknowable now**
- Whether real-QP decisions on ns-3 data produce any handover. An offline dry-run of the QP fork against R1's rows narrows this; only R3 settles it.
- How often D2 freeze-fail trips in R3 because of TS/QP wall jitter under VM load.

## 10. Unresolved questions
1. Is D7's non-target clause scoped to R0/R1 (F3)?
2. R3 bar: ≥ 1 QP-driven handover, or ≥ 2 IMSIs to ≥ 2 targets?
3. If the outage fallback fires, add `--outageThreshold=-1000` to the gated args, or rely on the LTE-fallback refusal?
4. Snapshot retention: keep only the latest rung, or also the previous one?
5. Undeploy hw-go for R-rungs?
6. Keep `control-failed-to-execute` for agent static rejects too, or use E2AP-specific causes?

Status: DONE
Summary: A full contract for R0–R3/M9 with pass/fail criteria and all N1–N7 answered, backed by five source checks (rc acks don't matter to TS; TS addresses the target's agent; rc's CGI needs a pure-hex key; the outage fallback writes no handover row).

---

## Appendix: ultra verifier ranking

Verdict: `plans/reports/verifier-261022-1723-GH-1-m8-m9-contract-ultra-verdict.md` (kongming, Opus 5.5 xhigh). All five candidates passed the hard constraints H1–H5. Scores out of 120: D 100 (this contract), E 98, B 93, A 87, C 86. Confidence medium.

Deciding criterion: N5. e2term passes the E2 Setup request part to e2mgr as hex text, and e2mgr stores base64 of that text. The controller checked this against dev-p5: `NzI2NTcxNzA2MTcyNzQ=` decodes to `72657170617274`, the hex of "reqpart". TS then searches the decoded hex text (`ts_xapp.cpp:333-366`). So the agent must write **raw bytes** `00 00 00 0N 0C`, which render as `0000000N0C`. Writing ASCII text would leave `cell_map` empty. Only this candidate specified raw bytes.

Defects in the winner and optional additions from other candidates are listed in the verdict file. The controller raises them with the user before planning.

ultra: picked=2/5 margin=low unanimous=no rejected_all=no

---

**Amended 2026-10-22 20:13 KST:** user decisions and a standards check are in `plans/reports/decisions-261022-2013-GH-1-m8-m9-contract-user-decisions-and-standards-check.md`. That record overrides this contract where they differ: Q2 keeps −5 dB, checked first; N4 is reopened toward a real UL metric; D7 is reworded; and every technical pick must cite a spec.

**Naming (2026-10-22 20:50 KST):** in this contract and the reports it cites, a bare "TS" means the OSC Traffic Steering xApp (`ric-app-ts`), never a 3GPP Technical Specification. New text writes "TS xApp" and "3GPP TS <number>" to avoid confusion. Deviations P1–P3 must be corrected before publication; see §6 of the decision record.

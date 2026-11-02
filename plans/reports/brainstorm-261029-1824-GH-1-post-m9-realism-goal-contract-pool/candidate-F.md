# Candidate F

## 1. Outcome
From `revert fresh-install`, one unattended invocation ("M10") exits 0 with an exact pre-registered step set:
- First, M9's 14 steps under the runtime profile `baseline` (δ = 0; r3p equals the M9 reference).
- Then the realism steps under the profile `spec`: P1, P2, P4, P5, P8, P10, P11, N5 and P12 fixed; P3 becomes a sim-time δ with a gated sweep; P6, P7 and P9 fixed behind switches; a 10-gNB scale gate.

Ops follow-ups 1, 2, 3 and 5 land first; follow-up 4 is investigated only.

## 2. Constraints
- Lock-step gates; free run stays the default.
- The profile, δ, the kpimon period and the T-C switches are runtime configuration, not separate images, so M10 keeps one install path. Every default reproduces M9's bytes; a fix that cannot → T3.
- Testbed-fork patches to the agent, rc, TS xApp and kpimon only where a ruled fix needs them. No change to e2term, e2mgr, submgr or rtmgr (an L-release refusal → T5).
- A1 constraints carry over: gates at `pins.conf` SHAs; judging on decoded wire, ledger, traces and digests; snapshot and leaked-overlay rules; `/home` ≥ 20 GiB in dev and ≥ 25 GiB through M10; a Zotero standards ledger; `--advice` kongming; CX-1–CX-4; Stops and T1–T9; naming rules.
- Rewriting a check that encodes a ruled deviation (e.g. the "via target" check at `scripts/gates/gate-r3p-ts-predictor.sh:234` [V]) is a contract change registered before code lands, not a weakening.

## 3. Non-goals
Real QP/R3; the scenario-one smoke; a scenario-agnostic harness; a free-run measurement campaign; kpimon measurement-time stamping (§6); modes for unscheduled controls; δ distributions; `RealtimeSimulatorImpl`; an optimized ns-3 build; a root-cause fix for the RMR readers; upstream PRs; publication; host changes.

## 4. Acceptance criteria
**Prelude**
1. `finish()` stops the gate units without the `kill -0` guard (`scripts/run-to-m9.sh:122` [V]). The TERM message is fixed (:131). A self-test covers "step already exited".
2. A rehearsal revert, then the m0-host probe (`scripts/gates/gate-m0-host.sh:46-48` [V]), then another revert leaves no untracked image in `/home/andang/VMs`.
3. No check passes on `rtmgr_push_acked` (`scripts/gates/rc-lib.sh:111-123` [V]); `rt_reader_ok` judges instead. A fixture with "rtmgr OK, reader stuck" fails.
4. `scripts/m9-budget.json` holds hGb 9 and trip 34 (now 4 and 29, :105-106 [V]).
5. An investigation report on the stuck RMR readers exists; the F″ remedy is unchanged.
6. A scale cost probe (not a gate) records 10-gNB free-run wall time, disk and memory.

**T-B**
7. The hub gets an actuation-delay attribute, default 0. Under `baseline` at δ = 0:
   - r3p `--reference` equals `reference/r3p/` on all components;
   - r0, r1 and r2 live1 digests equal those recomputed from M9's runs;
   - the ledger header stays `"delta-model":"fixed 0"` and lines gain no fields (`oran-interface/model/e2-control-hub.cc:288,356` [V]).
8. Under `spec` at the R3′ config, for δ ∈ {100, 150, 200, 500} ms:
   - applySimTimeNs − rxSimTimeNs = δ on every applied line, and HandoverStart = applySimTimeNs;
   - the precheck runs at apply time; controls pending at stop get FAILURE and C2 holds;
   - rc RestartCount is 0, and digests differ across δ.
   - δ = 150 ms passes full C1 and gets a committed reference.
   - One R1-config run at δ = 200 ms: the second in-flight control for one IMSI is refused at apply.
   - A tie rule for δ multiples of T is pre-registered and checked.
9. P12: `baseline` keeps option A. Under `spec`:
   - kpimon's period comes from config;
   - the agent honours G and R, and answers non-multiples of T as not admitted on the wire (E2AP §8.2.1);
   - the spec chain runs G = R = T;
   - one run at non-default G/R shows the decoded subscription values, cadence R in sim time, R/G records equal to a pre-registered aggregation of IPC samples, and Influx = IPC.

**T-A** (`spec`)
10. P10, both profiles: in every M10 live capture, every agent's agent→e2term DATA chunks carry PPID 70, judged per agent.
11. P2, P5, P8, P11, N5: the decoded E2 Setup of each agent shows:
    - a Global en-gNB or eNB ID;
    - an EN-DC X2 SETUP REQUEST request part with a spec NR CGI;
    - RAN function 3 with a decodable E2SM-RC description, accepted by the RIC.

    One pre-registered gNB-ID length is used everywhere. TS xApp keys derive from the NR CGI, and rc emits a spec NR CGI. An independently encoded control gets `applied` in the ledger and a handover in the ns-3 traces.
12. P4: KPM UE reports and RC controls carry en-gNB-UEID or eNB-UEID; no IMSI appears in AMF-UE-NGAP-ID.
13. P1: every R2/R3′ control reaches the pre-registered serving E2 node at its decision seq.
14. Spec R3′ (T-C switches off) live1 equals baseline r3p live1 on `ipc` and `traces`. The ledger differs only in pre-registered fields (viaNodeId). Spec R3′ passes full C1 with a new reference.
15. Scale, `nMmWaveEnbNodes=10` (cells 2–11):
    - all 11 agents are CONNECTED;
    - every seq is decoded and Influx = IPC per node;
    - at least one UE with ≥ 9 neighbours reports exactly its best 8 (`ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.h:71` [V]);
    - a control to a cell ≥ 10 is applied, and AC10 holds.

**T-C**
16. P6, P7 and P9 sit behind switches. Each counter's name, unit, type, source layer and reporting node match its Zotero-checked clause. The wire value equals a pre-registered formula over the ns-3 traces. The P9 volume comes from the node that hosts PDCP.
17. `UseIdealRrc=false`: a null-control run and one scripted handover pass (HandoverEnd after HandoverStart), or substitution (b) applies.

**End run and records**
18. M10: exit 0; the exact step set and pins; minHostFreeGb ≥ 25 with the watchdog alive; wall time within budget; the next revert leaks nothing.
19. Records: the run report (status of P1–P12 and N5, substitutions), the standards ledger, and the README and docs (deployment §3; architecture: profiles, δ, P12), all checked against M10's log; journals; implementation notes; pins and references pushed.

## 5. Trade-offs
**δ source**

| Approach | Rests most on | Fails first when | Worst plausible case |
|---|---|---|---|
| A. Pre-registered sweep {100, 150, 200, 500} ms, gated | Realistic δ lies in the 10 ms–1 s loop envelope (E2GAP §5.1.1 [C]) and is at least one granularity period T | A reviewer wants a measured distribution | The grid is called arbitrary; stating its provenance and framing it as a sensitivity sweep answers that |
| B. Free-run campaign, then pick δ | Free run measures a representative δ | Immediately: the sensing half is driven by the harness [C]; free-run δ_eff = ⌈L/C⌉·T = 100 ms for any L < 0.7 s at 2 gNB [C]; no live-RIC free-run harness exists [C] | New tooling plus a mid-goal pause to pick a value the grid already holds |
| C. Both | The campaign adds information | Same as B | Cost of A + B for the same grid |

**Goal shape and order**

| Approach | Rests most on | Fails first when | Worst plausible case |
|---|---|---|---|
| O1. Prelude → δ seam → Stop A → T-A → P12 → scale → T-C → freeze → Stop B → M10 | The seam lands on an unchanged baseline | e2mgr refuses en-gNB/eNB node types (P5) → T5 | The prelude and the δ = 0 proof are already banked; the pause stays inside T-A |
| O2. T-A first | Interop value arrives earliest | Same T5, with nothing banked | The δ = 0 proof gets tangled with wire diffs |
| O3. Realism on by default, no `baseline` | T-A leaves the simulation untouched | P1 changes the ledger's viaNodeId; P7, P9 and UseIdealRrc change ipc and traces | Breaks "M9 references byte-equal", or needs a narrowed compare (forbidden) |

## 6. Better approaches
None on direction: the tracks and the single end run stand. Three evidence-backed refinements inside the rulings:
1. **Defer kpimon measurement-time stamping.**
   - Nothing in scope would consume it: QP and AD are out, and R3′ windows by `ns3.seq` (`scripts/gates/check-n6-influx-window.py:100` [V]).
   - kpimon writes untagged points stamped `time.Now()` (`install_patch_files/xApps/kpimon-go/control/control.go.previous:955-980` [V]; the patch leaves these lines alone).
   - Stamping every node's point with the same millisecond Collection Start Time would make points with the same series and time overwrite each other [I]. N6 also pivots on `_time` (:37-38 [V]).
   - A working version would need tags as well: more divergence from upstream kpimon, and no gate would use it.
2. **The P10 fix belongs in the agent, not e2sim.**
   - The agents send through their own `SctpAssociation::send`, which calls plain `::send` (`ns3_e2_agent/src/sctp-association.cpp:147`, called from `e2-session.cpp:81,179,200` [V]). They do not use e2sim's `sctp_send_data`.
   - Fix it in the Testbed agent, for example by setting a default send PPID of 70 at connect time [I]. The e2sim pin can likely stay as it is.
   - The M2 reference node keeps PPID 0; record that.
3. **Add a runtime profile switch.**
   - This reconciles "fix P1–P12" with "δ = 0 byte-equal". `--reference` compares ledger, ipc, traces and extra (`scripts/gates/ts-rung-lib.sh:207-222`, `reference-compare.py:94` [V]), and the P11 fix changes rc-multiset by definition.
   - It follows the project's existing opt-in pattern (pacing, N4).

## 7. Recommended direction
**δ: approach A.**
- Only sim time can be gated. A campaign cannot observe the sensing half in this testbed.
- The lock-step RIC half (L ≤ 13 ms [C]) is far below T, so the grid's lower bound is the granularity period, not RIC latency.
- δ values that are multiples of T land exactly on a later barrier instant (k·T + 0.8 ms [C]), so event ordering ties matter; 150 ms isolates that effect.
- Revisit a campaign once a real AD or QP closes the sensing half.

**Order O1.**
- Stop A comes after AC1–7: a kongming go/no-go, and the budget re-projected from AC6.
- Inside T-A:
  1. P10.
  2. The identity cluster (P11, N5, P2, P5 and P8 share the cell key), starting with a quick test of whether e2mgr accepts en-gNB.
  3. P4.
  4. P1.
- The scale gate comes after T-A, so cells ≥ 10 use the spec NR CGI.
- T-C goes last.
- Freeze: pins, references, budget, Codex pre-ship audit. At Stop B the user frees any disk shortfall.

**Budget (M9 method).**
- Wall: 12,643 s measured in M9 [C] plus about 5–7 ks for realism [I] gives a cap of about 29 ks.
- Disk: (25 + 9) + 42 (M9 went from 101 to 59 GiB [C]) + a realism term measured in dev (about 12–16 GiB [I]) ≈ 92 GiB, against about 101 GiB free after a leak-free revert [C]. Run with `--no-snapshots`.
- Scale: ns-3 ran at 1.7×, 7× and 32× real time for 1, 2 and 4 gNBs [C], which extrapolates to about 240× at 10 [I]. So the scale gate is one lock-step run of at most 3 s sim time.

## 8. Draft `ak:goal-warmup` Outcome Contract
- **Intended result:** §1. Code on the forks' `dev/l-release-nist180`, the harness on the parent branch, pins in `scripts/pins.conf`.
- **In scope:** prelude (follow-ups 1–3 and 5; investigation of 4; scale probe); T-B (δ, sweep, P12 option B); T-A (P1, P2, P4, P5, P8, P10, P11, N5, scale gate); T-C (P6, P7, P9, `UseIdealRrc=false`); profiles; M10 runner and budget; records.
- **Out of scope:** §3.
- **Acceptance signals:** AC1–AC19.
- **Constraints:** §2; Stop A after AC7, Stop B before M10; T1–T9; Codex cap 4.
- **Allowed substitutions:** M9's substitutions 1–3 carry over (applied). Proposed, each for user approval:
  - (a) a δ that makes the R3′ schedule infeasible runs at the R1 config instead, and is reported;
  - (b) if `UseIdealRrc=false` is still red after one kongming-guided fix, record it as a deviation and continue;
  - (c) if the probe exceeds the scale budget, use 1 UE per gNB through a new scenario knob (default 3, byte-equal);
  - (d) if kpimon cannot decode multi-record Format 1, the P12 run uses G = R = 2T and the defect is recorded.
- **Decision owner:** user.

## 9. Unresolved questions
1. Which profile is the default after the goal? Recommended: `baseline` until publication.
2. The gNB-ID length. Recommended: 32 bits, with gNB ID = ns-3 cell ID and a constant 4-bit cell part [I].
3. Who receives P1 controls: the serving en-gNB (recommended) or the MN eNB (3GPP TS 37.340 §10.5.1)?
4. Do the brainstorm's 4 Codex runs count against this goal's cap?
5. R3′ is not gated with the T-C counters on, because the P9 fix changes the predictor's input. Re-registering its formula is a follow-up.
6. Not verified:
   - whether kpimon decodes multi-record Format 1;
   - rc's panic on an ACK without an outcome, and its 2 s timer, at `a2282ee`;
   - whether e2mgr accepts en-gNB/eNB node types;
   - the 10-gNB cost;
   - the KPM v03.00 text;
   - whether PPID 70 leaves the digests unchanged.
7. The A1 interpretations (a)–(k) are still not ratified [C].

# Candidate C

Labels: [V] = verified this pass (path:line); [C] = carried from a report; [I] = inference. I did not read Zotero, so the clause numbers below are unverified against it.

## 1. Outcome
After `revert fresh-install`, one unattended invocation runs the M0–M9 regression plus the new realism steps on frozen final pins, and exits 0 with the exact pre-registered step set.
- P1, P2, P4–P11 and N5 are fixed, with evidence.
- P3 becomes a sim-time delay δ with a gated sweep.
- P12 is honoured.
- Before any fix that changes wire bytes lands, δ = 0 is proven byte-equal to M9's R3′ reference.

## 2. Constraints
- Lock-step is the gate mode. Free run and δ = 0 are the defaults.
- L-release on NIST 1.8.0, forks only, pins in `scripts/pins.conf`. The harness is frozen before the end run.
- Gates judge wire bytes, the ledger, traces and digests, never rc's log. No test is weakened.
- A Zotero standards ledger is kept per milestone. Write "TS xApp" and "3GPP TS".
- `/home` keeps ≥ 20 GiB free during development and ≥ 25 GiB during the end run. M9's snapshot and leaked-overlay rules apply.
- kongming `--advice` (opus, xhigh) never counts as user approval. Codex follows CX-1 to CX-4.
- The TS xApp, rc and kpimon change only through Testbed-fork installer patches, and each patch is named in the run report.

## 3. Non-goals
- The QP fork and R3 with QP.
- Scenario-one, and a scenario-agnostic harness.
- A free-run campaign, and δ jitter.
- Window, late-apply or event-driven lock-step.
- `RealtimeSimulatorImpl`.
- Fixing rc's panic, or fixing follow-up 4.
- Upstream PRs and publication.

## 4. Acceptance criteria
**Ops prelude**
1. A runner self-test covers a TERM that arrives after the step has exited while VM gate units are still alive: `vm_stop_gates` still runs. The `kill -0` guard at `scripts/run-to-m9.sh:122` [V] is removed and the trap message is fixed.
2. After one real m0-host probe cycle and a revert, every file in `/home/andang/VMs` is tracked by a snapshot or by the active disk (`overlay-audit.txt`).
3. Lint proves that no gate passes on `rtmgr_push_acked` (`scripts/gates/rc-lib.sh:111` [V]). Route health is judged by `rt_reader_ok`.
4. h is derived from M9's `free-series.tsv` over a window of at least 5 min, so a single 1 GiB rounding step does not set it [I]. Expect about 9 [C].
5. A follow-up-4 investigation report exists. The F″ remedy stays.

**T-B timing**
6. **E0:** build the δ seam (`ActuationDelay`, default 0) and P12 at gate settings, with every other pin at M9.
   - `gate-r3p --mode c1 --reference reference/r3p` reports `equalsReference: true`.
   - At δ = 0 the ledger keeps `"delta-model":"fixed 0"` (`oran-interface/model/e2-control-hub.cc:356` [V]) and gains no key.
7. **δ > 0:**
   - every ledger line has `applySimTimeNs − rxSimTimeNs = δ` (both are `rxNs` today, `:287-288` [V]) and a `decisionSeq`;
   - HandoverStart and the precheck happen at apply time;
   - controls still pending at stop get a FAILURE;
   - C2 holds.
8. **Sweep** δ ∈ {100, 150, 200, 500 ms} on R3′ at the final pins:
   - every value: one live run plus a RIC-free replay, with equal digests;
   - 150 ms: the full C1;
   - 500 ms: a pre-registered duplicate trigger for the same UE gives one applied and one refused (with a cause), and no abort;
   - the sweep table is recorded, not thresholded.
9. Before criterion 8: verify the 6b rc claims (the 2 s ACK timer, and the panic on an ACK without an outcome, at `a2282ee`), and record the ACK wall latency for each δ.
10. **P12:**
    - kpimon's reporting and granularity periods are configurable, and gates set both to T;
    - the agent aggregates ⌈G/T⌉ samples, reports once per reporting period, and answers a granularity that is not a multiple of T as "not admitted" (E2AP §8.2.1);
    - a 1 s / 100 ms gate shows Influx = IPC for every seq;
    - a 150 ms request is refused on the wire.
11. Measurement-time stamping is built only if criterion 10 loses a seq to an Influx timestamp collision.

**T-A interop and scale**
12. **P10:** every agent → e2term DATA chunk in every live capture carries PPID 70, judged per agent.
13. **P5, P2, N5:**
    - the eNB agent registers as `eNB` and the gNB agents as `en-gNB`, each with its Global ID;
    - the request part decodes as an EN-DC X2 SETUP REQUEST whose NR CGI follows criterion 14;
    - the TS xApp builds its cell map from it, and the 5-byte key path is gone.
14. **P11:**
    - the gNB ID length L (22–32 bits) is recorded;
    - a gate sends an NR CGI built by an encoder independent of rc, and gets `applied` in the ledger and in ns-3's handover traces;
    - rc's own target bytes equal that encoder's output.
15. **P8:** E2 Setup announces RAN function 3 with an E2SM-RC definition that decodes.
16. **P1:** every R2 and R3′ control goes to the UE's serving node at decision time (ledger `viaNodeId`).
17. **P4:**
    - KPM and RC carry `en-gNB-UEID` or `eNB-UEID` (E2SM common §6.2.2.6);
    - no IMSI appears in AMF-UE-NGAP-ID;
    - the IMSI is reachable only through `ns3.imsi`.
18. **Scale** at `nMmWaveEnbNodes=10`:
    - all 11 agents are READY;
    - KPM = IPC for every node and seq;
    - at least one UE report lists 8 neighbours while that UE heard 9 or more cells;
    - the TS xApp's keys include `0A` and `0B`;
    - a control to a cell ≥ 10 is applied.

**T-C radio and counters**
19. **P6:** the `QosFlow.PdcpPduVolumeDL` row is sourced from PDCP PDU bytes with the 3GPP TS 28.552 unit and type, or it is renamed `ns3.*`. A lint table checks it, and Influx = IPC.
20. **P9:** PDCP SDU volume is credited to the node that hosts PDCP. R3′'s counter is re-registered against 3GPP TS 28.552 before code lands.
21. **P7:** an ns-3 test asserts the NR PDCP header on the EN-DC bearer (3GPP TS 37.340 §4.2.2). The N4 totals are unchanged.
22. **`UseIdealRrc=false`** (a flag, default true; `ns-3-mmwave-oran/scratch/scenario-zero.cc:483` [V]): one gated run in which HandoverEnd rows = applied and the RRC delay is > 0.

**End run and records**
23. R3′ reference v2 comes with an attribution file: every digest that differs from `reference/r3p` names the fix that changed it. An unattributed difference fails.
24. **End run:**
    - revert, one invocation, exit 0;
    - exactly the steps m0–m7, i0, r0, r1, i2, r2, r3p, scale, p12, dsweep, rrc;
    - equal to v2;
    - `minHostFreeGb ≥ 25`, with the watchdog alive throughout.
25. **Records:**
    - the run report marks each of P1–P12 and N5 as fixed (with an evidence path) or substituted;
    - the standards ledger;
    - README and docs checked against the run;
    - the journal, the handoff and `implementation-notes.html`.

## 5. Trade-offs
**δ source**
- **A. Fixed sweep, gated.**
  - Assumes a fixed sim-time δ inside the near-RT range of 10 ms–1 s (E2GAP §5.1.1, RICARCH §5.1.3 [C]) bounds the real delay.
  - Fails first when someone demands a measured distribution.
  - Worst case: flat results (δ ≤ 100 ms costs at most 2 % [C]). That is still a repeatable, disclosed bound, at about 3,100 s per end run [I].
- **B. Free-run campaign first.**
  - Assumes free-run landing steps reflect the real delay.
  - Fails at once. Landings are quantised by C/T, so any L < 0.7 s lands at +100 ms with 2 gNBs [C]. The harness also triggers the TS loop, so there is no autonomous decision to time.
  - Worst case: a phase spent on a host artifact that cannot be gated, and A is still needed.
- **C. Both.** Costs B plus A, and B's numbers are probably discarded.

**Goal shape**
- **G1. The ruled order, A → B → C.**
  - Fails first when the P4/P2/P5 identity cluster needs changes to rc, the TS xApp, kpimon and e2mgr.
  - Worst case: by then the wire bytes have changed, so δ = 0 can no longer be checked against M9.
- **G2. Seams first (recommended).**
  - Assumes the δ seam and P12 at G = R = T are byte-neutral [I].
  - Worst case: one extra r3p C1, about 1,300 s.
- **G3. Two goals.** This breaks the one-goal ruling and needs two end runs, each about 100 GiB and 8 h.

## 6. Better approaches
This is an evidence-backed refinement of the ruling "δ = 0 byte-equal to M9 references", not an override. You decide.
- **Evidence:** M9's R3′ reference also pins `rc-multiset`, `kpm-headers`, `collet-start-time` and `predictor-records` (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p/equal/digests.json:2-6`, `files.json`; compared per `scripts/gates/ts-rung-lib.sh:207-208` [V]).
- **Consequence:** P11 and P4 must change the RC bytes, and P9 changes R3′'s input. So equality to M9 can hold only before those fixes land.
- **Delta and cost:** prove equality at E0, then judge against v2 with the attribution file. This costs one r3p C1.

**Corrections:**
- **P10's owner is the agent, not e2sim.** The agent sends with its own plain `::send`, which carries no PPID (`O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/sctp-association.cpp:147`, called from `e2-session.cpp:81,179,200` [V]). The fix therefore belongs in the Testbed fork.
- **The scale gate needs N = 10.**
  - LTE is cell 1 (`ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:973` [V]). So N = 9 gives exactly 8 non-serving cells, which only equals `E2SM_REPORT_MAX_NEIGH` (`mmwave-enb-net-device.h:71` [V]) and does not exceed it.
  - Cells 10 and 11 give the keys `0A` and `0B`, which are untested (`docs/system-architecture-l-release.md:200` [V]).

## 7. Recommended direction
**δ: approach A** (the sweep in criterion 8, plus δ = 0).
- Lock-step already measured the RIC half: L_max is 12.9, 8.2 and 5.4 ms (`scripts/gates/rung-config.json:14,18,146` [V]), far below one period.
- The unknowns are report delay and execution, and only a bound covers them honestly.
- Revisit only for a named real deployment with measured latency.

**Measurement-time stamping: against, for now.**
- Nothing in scope needs it: R3′ windows by `ns3.seq` (`scripts/gates/r3p-scenario.json:9-10` [V]).
- kpimon writes each measData item separately (`install_patch_files/xApps/kpimon-go/control/control.go.previous:548-553` [V]).
- It stays conditional, per criterion 11.

**`UseIdealRrc=false`:** include it as an opt-in flag, covered by substitution 5.

**Milestones:**
1. M-0: the ops prelude.
2. M-1: E0, then Stop A.
3. M-2: T-A, in the order P10, P8, P5/P2/N5/P11, P1, P4.
4. M-3: the scale gate.
5. M-4: T-C.
6. M-5: re-pin, reference v2, the sweep, a rehearsal, the freeze and the budget, then Stop B.
7. M-6: the end run.

**Budget:**
- **Wall:** (13,466 s + about 7,000 s of new steps) × 1.5 ≈ 31,000 s [I]. Measure C at N = 10 first: 4 gNBs already run 32× slower than real time [C], and each gNB has 3 UEs (`scenario-zero.cc:542` [V]).
- **Disk:** (25 + 9) + 43 + about 22 ≈ 100 GiB [I], against 59 GiB free now. With ops fix 2, the revert frees the post-M9 overlay; you free the rest at Stop B.

## 8. Draft `ak:goal-warmup` Outcome Contract
- **Intended result:** §1.
- **In scope:**
  - ops follow-ups 1–3 and 5, plus the follow-up-4 investigation;
  - T-A: P1, P2, P4, P5, P8, P10, P11, N5 and the N = 10 scale gate;
  - T-B: the δ seam and sweep, P12 (configurable kpimon periods plus the agent's option B), and conditional measurement-time stamping;
  - T-C: P6, P7, P9 and the `UseIdealRrc` flag;
  - R3′ reference v2;
  - Testbed-fork patches to the TS xApp, rc and kpimon for these items;
  - the end run and the records.
- **Out of scope:** §3.
- **Acceptance signals:** criteria 1–25.
- **Constraints:** §2, plus M9's triggers T1–T9. Stop A comes after E0 and Stop B before the end run.
- **Allowed substitutions:**
  - (proposed) carry substitutions 1–3 over from A1;
  - (proposed) 4: stop at R2 if the R3′ v2 dry run forms no schedule;
  - (proposed) 5: if an EN-DC handover cannot complete with `UseIdealRrc=false` after one kongming-guided fix, record it as P13 and keep the flag off;
  - (proposed) 6: if N = 10 exceeds the step budget, add a `uesPerGnb` global (default 3, byte-equal) and set it to 1.
- **Decision owner:** user.

## 9. Unresolved questions
1. Do this brainstorm's 4 Codex runs count against the next goal's cap? A1 did not count the runs made before its contract (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/goal-packet.md:26` [V]).
2. Do you accept the E0 + v2 reading of the δ = 0 ruling?
3. Which gNB ID length L should P11 use?
4. Should P1's control go to the source en-gNB or to the MN eNB (3GPP TS 37.340 §10.5.1)?
5. Which counter should R3′ read after the P9 fix?
6. Can about 100 GiB be freed on `/home` before the end run?
7. Not verified:
   - rc's 2 s timer and its panic;
   - how e2mgr and kpimon handle the `en-gNB` and `eNB` types (kpimon splits nodes by type at `control.go.previous:97,114` [V]);
   - the RMR route for injecting the independently encoded RIC CONTROL (mtype 12040);
   - the KPM v03.00 clauses;
   - [I] at exactly 8 heard cells, `mmwave-enb-net-device.cc:974-977` pads one neighbour triple too few, which shifts trace columns.

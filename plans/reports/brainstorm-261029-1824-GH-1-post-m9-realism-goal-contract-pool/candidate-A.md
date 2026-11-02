# Candidate A

## 1. Outcome
The run starts with a revert to `fresh-install`. Then one unattended `systemd-run --user --wait` invocation of the M9 runner's successor exits 0 with the exact pre-registered step set. That set has two parts:
- **The M0–M9 regression in the compat profile** (M9 behaviour, δ = 0). Its top rung still compares equal to the unchanged `reference/r3p/`.
- **Realism steps in the realism profile:**
  - E2 interop: P1, P2, P4, P5, P8, P10, P11, N5;
  - a scale run with 10 or more gNBs;
  - a δ sweep;
  - P12 option B with a configurable kpimon period, plus measurement-time stamping;
  - the counter and radio fixes: P6, P7, P9, and a probe with `UseIdealRrc=false`.

  Every realism step that claims determinism has a committed reference.

Before all of this, ops follow-ups 1, 2, 3 and 5 are fixed and follow-up 4 is investigated.

## 2. Constraints
- **Rulings.** All rulings in packet §2–§3 bind. Lock-step stays the gate mode. A δ = 0 run must be byte-equal to M9.
- **Profile rule** (needs user approval; see §6). Any change that alters a digested component ships behind a run-time switch whose default is compat. The digested components are:
  - the ledger, including `viaNodeId` [V `oran-interface/model/e2-control-hub.cc:287-290`];
  - the wire `rc-multiset` (viaNode, imsi, target) [V `tools/e2-evidence/wire-c1-extract.py:9-13`];
  - `kpm-headers`;
  - the ns-3 traces.

  A change may be unconditional only if the unchanged M9 reference still compares equal. P10 is a candidate: PPID is in no digest [I].
- **xApp patches.** Patches to rc (`a2282ee`, [V `scripts/gates/rc-lib.sh:35`]), the TS xApp and kpimon become in scope, applied through the Testbed-fork installer. Contract A1 had them out of scope. Each xApp image is built once, and the profile is chosen at deploy time.
- **P12** gets its own design note and a user stop before any code (ruling).
- **Before any δ > 0 run,** verify the handoff 6b claims at `a2282ee`: does rc panic on an ACK without an outcome, and what does its 2 s ACK timer do? At δ = 500 ms the ACK's wall latency is about 3.6 s [C kongming R1].
- **Disk.** Dev floor 20 GiB. End-run floor 25 GiB, with the trip point computed from measured growth. Follow-up 2 is fixed before the first dev revert.
- **Standards.** Every phase has a standards ledger. Cite the clause and write "unverified against Zotero" where the text was not read. Write "TS xApp" and "3GPP TS n".
- **Process.** Never weaken a test. Use our forks; `pins.conf` governs. Freeze the harness before the end run. kongming runs on opus at xhigh and its counsel is never user approval. The Codex cap is 4 runs (see §9).

## 3. Non-goals
- the real QP fork and R3;
- the scenario-one smoke and a scenario-agnostic harness;
- a fix for the stuck RMR readers (investigation only);
- lock-step support for unscheduled data-driven controls (kongming R4);
- `RealtimeSimulatorImpl`;
- free-run gates;
- δ distributions or jitter;
- prediction quality;
- upstream PRs, the N release, and publication.

## 4. Acceptance criteria

**Prelude**
1. `run-to-m9.sh` no longer guards `vm_stop_gates` with `kill -0 "$step_pid"` [V `scripts/run-to-m9.sh:122`]. A runner self-test case sends TERM after the step client has died and asserts that `vm_stop_gates` ran. The TERM trap message is corrected.
2. An orphan-overlay check passes after the end run's opening revert and again after m0: every file in the VM image directory is tracked by the domain or by a snapshot. Output goes to `orphan-overlays.txt`. The probe branch in `gate-m0-host.sh:46-52` [V] no longer untracks the active overlay.
3. No gate judges on `rtmgr_push_acked` [V `rc-lib.sh:111-123`]; readiness is judged on receiver-side evidence. A fixture in which rtmgr logs OK but the receiver is stuck fails the check.
4. A report on follow-up 4 under `plans/reports/` records the repro attempts and the trigger hypotheses. The F″ remedy is unchanged, and every `ric refresh` in the end run is disclosed.
5. The budget is recomputed with h taken from growth smoothed over windows of at least 300 s, giving trip ≥ 34 GiB. M9's single-sample 0.067 GiB/s is a 1 GiB rounding artefact and is not used [C].

**T-B: timing**
6. `E2ControlHub` gets an `ActuationDelay` attribute in sim time, default 0. At δ = 0:
   - the ledger header stays `"delta-model":"fixed 0"` [V `:356`];
   - the apply stays synchronous, with no zero-delay event, because that could reorder same-time events [I];
   - a RIC-free replay of M9's r3p live1 ledger at the new pins gives ledger, IPC and trace digests equal to `reference/r3p/equal/digests.json`. This replay is re-run as a dev guard after every ns-3 change.
7. At δ > 0:
   - apply time − decision time = δ exactly on every ledger line;
   - the precheck runs at apply time;
   - the HandoverStart trace time equals the apply time;
   - every control still pending at the stop gets exactly one FAILURE;
   - no RNG stream is added without an explicit index.
8. The δ sweep runs R3′ in the realism profile at δ ∈ {100, 150, 200, 500 ms}, one live run each, with the C2 identity and the checks of item 7. The full C1 runs at δ = 150 ms and is committed as a reference. A per-δ table (applied, refused in handover, late, ACK wall latency) is recorded, not judged. R0 in the realism profile at δ = 500 ms adds the pending-at-stop fault run.
9. **P12.**
   - kpimon's reporting period (RP) and granularity period (GP) are configurable and checked on the decoded wire.
   - The agent honours the action: RP/GP records per report. A GP that is not a multiple of T is answered "not admitted" (E2AP §8.2.1).
   - The gate runs RP = 1 s and GP = 100 ms: each report carries 10 records, and Influx = IPC for every seq with no duplicates.
   - The regression runs RP = GP = T, so the indications are unchanged and the reference stays equal [I].
10. **Measurement-time stamping.** Behind a flag, kpimon writes Influx time = colletStartTime + i·GP. It is required on for the gate in item 9, because the stock `time.Now()` [V `control.go.previous:957`] gives all 10 records of one report the same time, so the points would collide [I].
11. A measured-latency record (not a gate) puts the L and sensing-lag distributions from the pacer logs next to the δ grid in the run report.

**T-A: E2 interop and scale**
12. **P10.** In every live capture, every agent's agent → e2term DATA chunks carry PPID 70, judged per agent.
    - The fix belongs at the agent's own `::send` [V `ns3_e2_agent/src/sctp-association.cpp:147`]. e2sim's `sctp_send_data` [V `e2sim_sctp.cpp:224-228`] is not on the agent's send path.
    - The PPID passed to `sctp_sendmsg` must be in network byte order [V `e2sim_defs.h:29`].
13. **P11.** A gate builds a spec NR CGI (PLMN + 36-bit NCI) with an encoder independent of rc and expects `applied` in the ledger and in the ns-3 handover traces. The gNB ID length is recorded; 28 bits is recommended, which leaves an 8-bit cell ID and maps one to one. rc in the realism profile emits the same octets.
14. **P5 and P8.** The decoded E2 Setup shows a Global eNB ID for the eNB agent and Global en-gNB IDs for the gNB agents, and RAN function 3 (E2SM-RC) announced with a decodable description. e2mgr lists every node CONNECTED. An unannounced RC function is refused.
15. **P4.** UE IDs are eNB-UEID or en-gNB-UEID (E2SM common §6.2.2.6). They carry real ns-3 identities: the MME UE S1AP ID equals the IMSI in ns-3 [V `epc-mme-application.cc:112`]. The xApps still resolve the UE.
16. **P1.** Every realism control goes to the UE's serving E2 node, checked on the wire. The plan picks the addressee under 3GPP TS 37.340 §10.5.1.
17. **P2 and N5.** The request part is a decodable EN-DC X2 SETUP REQUEST (3GPP TS 36.423). The TS xApp builds its cell map from it, and the N5 key is retired in the realism profile.
18. **Scale.** One lock-step run in the realism profile with `nMmWaveEnbNodes` ≥ 10, which means 11 agents and 30 UEs [V `scenario-zero.cc:543-544`]:
    - every agent CONNECTED;
    - Influx = IPC for cell IDs ≥ 10;
    - at least one UE report fills `maxNeigh` = 8 [V `mmwave-enb-net-device.h:71`] while ns-3 itself has more than 8 neighbours;
    - the cell map holds every cell;
    - at least one handover to a cell ≥ 10 is applied;
    - the checks of items 12–17 pass.

**T-C: counters and radio**
19. **P6.** The DL volume row is either PDCP-sourced INTEGER kbit (3GPP TS 28.552 §5.1.3.6.1.1) or renamed to the MAC measurement it really is. The lint passes.
20. **P9.** MN-hosted PDCP volume is credited to the MN cell. The R3′ predictor's counter is pre-registered again against 3GPP TS 28.552 before any code.
21. **P7.** The EN-DC bearer gets an NR PDCP header (3GPP TS 37.340 §4.2.2), behind the profile switch. With the switch off, the digests are unchanged.
22. **`UseIdealRrc=false` probe.** One realism run completes without an abort, with at least one HandoverEnd. Otherwise substitution 5 applies.

**End run and records**
23. The end run exits 0. `verdict.json` holds the exact step set, the pins and the profile of each step. The regression has `equalsReference: true` against the unchanged `reference/r3p/`, and every realism C1 equals its new reference. `minHostFreeGb` ≥ 25 with the watchdog alive throughout, and RestartCount is 0.
24. The run report updates every P row (fixed with evidence, or still present with the reason) and records each new reference's provenance and every substitution. README, the deployment guide and the architecture doc are verified against the run. A journal is written at every pause, `implementation-notes.html` is kept, and every phase has a standards ledger.

## 5. Trade-offs

**δ source**

| Option | Assumption it depends on most | Fails first when | Worst plausible case |
|---|---|---|---|
| Fixed grid {100, 150, 200, 500} | δ is a model parameter that brackets the near-RT envelope of 10 ms–1 s (E2GAP §5.1.1, unverified against Zotero) | a reviewer wants δ tied to a measured distribution | values are called arbitrary; mitigated by the envelope citation and item 11 |
| Free-run campaign first | free-run timing reflects RIC latency | always here: ns-3 runs 7× (2 gNB) to 32× (4 gNB) slower than real time [C timing report], and free run applies controls at the next boundary [V `e2-control-hub.cc:228-229`], so measured δ = ⌈L/C⌉·T = 100 ms for any L < 0.7 s | a mid-goal user decision on numbers that describe the simulator |
| Both | the campaign informs without blocking | the campaign suggests an off-grid value | pre-registration is redone mid-goal; the cost of both options at once |

**Goal shape**

| Option | Depends on | Fails first when |
|---|---|---|
| Serial: prelude → δ seam → T-A → T-C → P12 → sweep → end run | the δ seam can be separated from the rest | P7 or P9 shift digests; contained by the profile switch |
| T-A first | the interop fixes need no profile mechanism yet | P1, P4 or P11 break reference equality before the profile exists, and it has to be retrofitted |
| Two goals | the user accepts a split | contradicts the ruling |

**How M9 equality is kept**
- **Profile switch (recommended).** Cost: code paths for both profiles in the agent, rc and the TS xApp.
- **Re-baseline.** All fixes on by default, with new references. M9 stays reproducible only from the old pins, so the end run's regression could not show equality to the M9 reference.

## 6. Better approaches
None. The recommended direction is the requested one. The evidence:
- The measured RIC-half latency L_max is 5.4–12.9 ms [V `rung-config.json:14,18,146`], so a campaign adds nothing on the RIC half.
- Free run collapses δ to one period (§5).

Two refinements need user approval; neither overrides a ruling:
- **The profile switch.** Without it, "δ = 0 byte-equal to M9" conflicts with P1, P4 and P11, which change the ledger and wire components that are digested.
- **P10's fix location.** The fix belongs in the agent's own send, not in e2sim.

## 7. Recommended direction
**δ source: the fixed grid**, with 0 as the regression value and 150 ms as the off-grid value that tests applies between barriers. The reasons:
- it is deterministic and can be pre-registered;
- it brackets the measured testbed loop, about 5–220 ms including sensing [C];
- it covers the range where the D5 analysis shows the decision value moving by roughly 2 % to 10 % [C];
- the measured latencies are reported next to the grid, not used to pick it.

**Milestones**

| Milestone | Content |
|---|---|
| G0 | prelude (items 1–5) |
| G1 | δ seam and the replay guard (items 6–7) |
| G2 | T-A ordered by risk: P10 → an e2mgr probe of the en-gNB and eNB node types → P4 → P11 → P1 → P2/N5 → scale |
| G3 | T-C, then the P12 design stop, then items 9–10 |
| G4 | realism references made once: sweep and C1 |
| G5 | freeze, budget, Stop B |
| G6 | end run |

**Budget [I]**
- **Wall.** About +5,500 s on M9's 12,643 s, so the global wall is about 27,000 s at 1.5×.
- **Disk.**
  - Growth: about 0.55 GiB per run [C] across about 15 runs.
  - Requirement: (25 + 9) + 43 + 12 + 10 ≈ 99 GiB free before the revert.
  - Available: about 101 GiB after the revert and the deletion of the leaked overlay.
  - So at Stop B the user frees about 10 GiB, or the evidence archive moves to `/mnt/data`.
- **Scale cost.** It is measured first. Cost grows roughly quadratically with the gNB count.

## 8. Draft `ak:goal-warmup` Outcome Contract
- **Intended result:** §1.
- **In scope:**
  - prelude follow-ups 1, 2, 3 and 5, plus the follow-up 4 report;
  - T-A: P1, P2, P4, P5, P8, P10, P11, N5 and the scale gate;
  - T-B: δ seam, sweep, P12 option B and measurement-time stamping;
  - T-C: P6, P7, P9 and the `UseIdealRrc` probe;
  - the compat and realism profiles;
  - rc, TS xApp and kpimon patches through the Testbed fork;
  - the end run and the records.
- **Out of scope:** §3.
- **Acceptance signals:** items 1–24.
- **Constraints:** §2.
- **Allowed substitutions:**
  - Substitutions 1–4 carry over from contract A1.
  - **5 (proposed).** If the `UseIdealRrc=false` probe aborts or completes no handover after one recorded fix, record it as P13 and drop item 22. Report it; do not pause.
  - **6 (proposed).** If kpimon cannot decode multi-record Format 1 without rewriting its decoder, the item 9 gate runs at RP = GP = 200 ms, and the multi-record gap is recorded.
- **Decision owner:** user.

## 9. Unresolved questions
1. Approve the profile switch, or re-baseline?
2. Approve the rc, TS xApp and kpimon patches?
3. P1 addressee: the source en-gNB (SN-initiated change) or the MN?
4. gNB ID length: 28 bits?
5. P12 values: RP = 1 s / GP = 100 ms for the gate, and RP = GP = T for the regression?
6. Do the brainstorm's 4 Codex runs count against the goal's cap of 4?
7. Should the A1 interpretations (a)–(k) be ratified?
8. Not verified:
   - e2mgr's acceptance of the en-gNB and eNB node types;
   - kpimon's multi-record decoding;
   - rc's ACK timer and its panic on an ACK without an outcome;
   - the scale wall cost;
   - the KPM v03.00 clauses against Zotero;
   - whether a replay at the new pins equals the reference.

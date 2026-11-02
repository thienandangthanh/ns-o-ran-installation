# Candidate G

## 1. Outcome
As in M9: revert `fresh-install`, then one unattended `systemd-run --user --wait` invocation exits 0 with the exact pre-registered step set (M9's 14 steps plus the realism steps). Its verdict proves:
- the ops prelude fixes work;
- P1, P2, P4, P5, P8, P10, P11 and N5 are fixed on decoded wire bytes, and a run with more than 9 gNBs is green;
- δ is gated at 0 (equivalent to M9) and over a pre-registered sweep, with the subscribed KPM period honoured;
- P6, P7 and P9 are fixed, and `UseIdealRrc=false` is available as a flag.

The run report marks each P-item as fixed (with evidence) or still present.

## 2. Constraints
- Gates run in lock-step, and free run stays the default. Each realism knob is a flag whose default reproduces M9.
- L-release only. Fork branches are `dev/l-release-nist180`, pins come from `pins.conf`, and the harness is frozen by SHA before the end run.
- Check the standards before writing code. A new deviation is a PAUSE.
- Judge on the wire, ledger, traces and digests, never on logs. Never weaken a test. A red C1 follows M9's rule.
- Keep `/home` ≥ 20 GiB at dev times and ≥ 25 + h during the end run. Keep `fresh-install`, `f7-rerun-green` and `r3p-green`. The leaked-overlay ruling stands.
- Carried over: kongming `--advice` (opus xhigh, never counted as approval); Codex CX-1 to CX-4; "TS xApp" vs "3GPP TS"; no secrets.
- The user approves the P12 design and the T-A identity scheme (gNB-ID length, P1 recipient, P4 UE-ID type) before any code.

## 3. Non-goals
- Real QP, R3 and QP/AD adapters; scenario-one; a scenario-agnostic harness.
- Modes for unscheduled controls; `RealtimeSimulatorImpl`; δ jitter; judging decision quality.
- kpimon measurement-time stamping (§6); a fix for the stuck-reader root cause; an optimized ns-3 build for gates; the N release; upstream PRs; publication.

## 4. Acceptance criteria
*Prelude*
1. **Orphan gap:** the runner self-test kills the step process, then sends TERM. `vm_stop_gates` still runs, no `gate-*` unit remains, and the TERM message is corrected (guard at `scripts/run-to-m9.sh:122` [V]).
2. **Overlay leak:** after `gate-m0-host.sh` and the next revert, an orphan check finds every `ubuntu24.*` file referenced by `domblklist` or a `snapshot-dumpxml`.
3. **False OK:** no pass condition uses `rtmgr_push_acked` (`rc-lib.sh:111` [V]). rc, the TS xApp and the stub are judged on receiver evidence. A fixture with rtmgr logging "OK" and a stuck reader fails.
4. **Headroom:** the budget's h comes from byte-resolution samples over a sliding window and is at least the attempt-1 rate (h ≈ 9, trip ≈ 34; `m9-budget.md:82` [V]). Do not use M9's 0.067 GiB/s peak; it is a rounding artefact [C].
5. **Stuck readers:** a report on what triggers them. The F″ remedy stays unchanged.

*T-A*
6. **P10:** in every capture, every agent → e2term DATA chunk carries PPID 70, judged per agent.
7. **P11:** a gate sends a spec NR CGI (PLMN + 36-bit NCI with the approved gNB-ID length), built by an encoder independent of rc. The ledger and ns-3's handover trace show `applied`. The 9-octet form gets `control-message-invalid`.
8. **P5/P2/N5/P8:** in the decoded E2 Setup:
   - the eNB has a Global eNB ID and the gNBs have Global en-gNB IDs;
   - the request part decodes as an EN-DC X2 SETUP REQUEST whose NR CGI matches AC 7;
   - RAN function 3 is announced;
   - the TS xApp's cell map is keyed from that CGI, with no 5-byte key.
9. **P4:** UE IDs in RC controls and KPM Format 2 use the approved en-gNB-UEID/eNB-UEID. IMSI correlation goes only through `ns3.*` rows.
10. **P1:** controls in r2 and r3p go to the approved recipient, never to the target's node.
11. **Scale:** a lock-step run with `nMmWaveEnbNodes=10`:
    - all 11 agents meet AC 6;
    - ≥ 1 TS xApp control to a cell ≥ 10 is applied;
    - ≥ 1 KPM report lists 8 neighbours where ≥ 9 exist (`E2SM_REPORT_MAX_NEIGH`, `mmwave-enb-net-device.h:71` [V]), and Influx = IPC;
    - RestartCount is 0.

*T-B*
12. **δ seam:** ns-3 gets an `ActuationDelay` attribute in sim time, default 0. AC 20 holds at 0.
13. **Sweep:** R3′ config, δ ∈ {100, 150, 200, 500 ms}. For each δ:
    - 2 live runs plus the replay are byte-equal;
    - `applySimTimeNs − decisionSimTimeNs = δ`;
    - the ACK follows the apply, and HandoverStart is at the apply;
    - controls still pending at the stop get exactly one FAILURE each;
    - the outcome table is recorded, not judged.

    Multiples of T land on the next sample, since both happen at k·T + 0.8 ms [C]. Pre-register and assert the order of same-timestamp events.
14. **P12:** kpimon's reporting period (RP) and granularity period (GP) become install options; the harness default is RP = GP = T. The agent reports every RP with RP/GP records (`granulPeriod` = GP, `colletStartTime` = window start) and does not admit non-multiples (E2AP §8.2.1 [C]). A gate with GP = T and RP = 5T shows Influx = IPC per `ns3.seq`.

*T-C*
15. **P6:** the MAC-sourced row is sent as the matching 3GPP TS 28.552 counter, with that counter's type and unit.
16. **P7:** the NR PDCP header (3GPP TS 38.323) passes a bit-layout unit test. A 12-bit SN keeps 2 octets, the same as `LtePdcpHeader` [C], so the digests should not change [I].
17. **P9:** volume is credited per 3GPP TS 28.552 to the node hosting PDCP, or to an X2-U volume counter if one exists [I]. If the values change, R3′ is re-pre-registered.
18. **`UseIdealRrc` flag:** today it is hard-coded at `scenario-zero.cc:483` [V]; the flag defaults to true. With false, a forced R0 handover completes, 2 runs are equal, and HandoverEndOk − HandoverStart exceeds the ideal value.

*End run, records*
19. **End run:** meets M9's criteria. In addition, the top rung's C1 equals its new reference, `minHostFreeGb` ≥ 25 + h with the watchdog alive, and the wall time stays within the frozen budget.
20. **M9-equivalence:** at δ = 0 with all defaults, compare the r0, r2 and r3p configs with `evidence/r0/20261028T193510Z`, `evidence/r2/20261028T195650Z` and `reference/r3p` [V, all present]:
    - `ipc` and `traces` are byte-equal;
    - `ledger` and `extra` are equal after a projection that is frozen before the first T-A wire fix, with each projected field attributed to one fix ID;
    - r3p is exempt only if P9 forces R3′ to be re-pre-registered.
21. **Records:** run report (deviations, δ table, substitutions), standards ledger, README and docs, journal, `implementation-notes.html`.

## 5. Trade-offs
**Where the δ values come from**
- **A. Fixed sweep.**
  - Assumes: the spec's near-RT range of 10 ms–1 s (E2GAP §5.1.1 [C]) brackets the real δ.
  - Fails first: if outcomes jump between grid points.
  - Worst case: more grid points are needed, which is cheap and deterministic.
- **B. Free-run measurement campaign first.**
  - Assumes: free run measures RIC latency.
  - Fails immediately. At 2 gNBs, ns-3 needs about 0.70 s per 100 ms period, against an L_max of 5–13 ms [C]. Every control therefore lands at the next boundary, and δ = T by construction.
  - Worst case: host-dependent ns-3 slowness is reported as network latency, a phase is lost, and nothing can be gated.
- **C. Both:** B's cost for A's answer.

**Ordering** (one goal, as ruled)
- **O1. By track (prelude → T-A → T-B → T-C).**
  - Assumes: T-A converges.
  - Fails first: P5 renames the e2mgr RAN names [I], and P4 needs a UE identity that IPC lacks (IPC carries only the IMSI, `e2-ipc-message-encoder.cc:236` [V]).
  - Worst case: δ, which both advisors rank first [C], lands last, and the reference is cut twice.
- **O2. By reference churn (recommended).**
  - Assumes: the equivalence projection is frozen early.
  - Fails first: if the identity scheme is not approved at warmup.
  - Worst case: δ, P10 and P12 still ship even if T-A stalls, and the reference is cut once.

## 6. Better approaches
- **P10 lives in the agent, not e2sim [V].** The agent sends with its own `::send()` (`ns3_e2_agent/src/sctp-association.cpp:147`) and never uses libe2sim's send path (`main.cpp:4-6`).
  - Fix it in the Testbed fork with `htonl(70)`; the e2sim pin does not change.
  - Watch the byte order: e2sim's `X2AP_PPID 452984832` is `htonl(27)` (`e2sim_defs.h:29`).
- **A literal "δ = 0 is byte-equal to M9" conflicts with T-A [V].** P1 changes the ledger's `viaNodeId`. P11 and P4 change `extra/rc-multiset`. P9 changes R3′'s pre-registered input (`r3p-scenario.json:8-13`), which its own rule at `:2` treats as T3. Proposed: the projection in AC 20.
- **P2 and N5 need a TS xApp patch.** Upstream `cell_map` searches for the gNB-ID hex inside the request-part hex and takes the next 10 characters (`replay-ts-cell-map.py:4-13` [V]). A real X2AP PDU breaks that search [I].
- **Leave measurement-time stamping out of this goal.** No in-scope reader uses Influx `_time`: joins use `ns3.nodeId` and `ns3.seq` (`gate-m6-kpm.sh:12` [V]). Its consumers, QP and AD, are out of scope. Build it in the QP/R3 goal.

## 7. Recommended direction
**δ: option A**, the sweep {100, 150, 200, 500 ms}. The values come from the spec range and from D5's sensitivity results: ≤ 100 ms costs ≤ 2 % of decision value, 500 ms about 10 % [C]. L and the sensing latency are recorded inside the sweep runs. I also propose adding δ = 10 ms, the spec floor and about the measured RIC L, so that the δ < T case is covered.

**Milestones**
- **M-0, warmup approvals:** P12 design, identity scheme, projection, δ grid.
- **M-1:** prelude, equivalence tool, δ seam, P10. Then Stop A′.
- **M-2:** P5, P2, N5, P11 and P8 as one unit, then P4 and P1. Measure the 10-gNB compute time per period (C) before the scale run; 4 gNBs already ran 32× slower than real time [V].
- **M-3:** T-C. Re-pre-register R3′ only if P9 changes its input.
- **M-4:** P12, sweep, new reference, freeze, budget. Then Stop B′.
- **M-5:** end run.

**Budget**
- **Wall:** apply `m9-budget.py`'s formula to the measured steps. M9 took 12,643 s [V]; expect +1.5–2.5 h [I].
- **Disk:** T = (25 + h ≈ 9) + M9's measured 42 GiB drop (101 → 59 [V]) + 1.25 × the measured realism growth, about 88–92 GiB. About 101 GiB is available after the revert and the leaked-overlay deletion [I]. A shortfall goes to Stop B′.

## 8. Draft `ak:goal-warmup` Outcome Contract
- **Intended result:** the §1 end-run verdict (exit 0, exact step set, AC 19–20 green).
- **In scope:** follow-ups 1, 2, 3 and 5, plus 4 as investigation only; T-A (P1, P2, P4, P5, P8, P10, P11, N5, scale > 9 gNBs); T-B (δ seam and sweep, P12); T-C (P6, P7, P9, the `UseIdealRrc` flag); the end run; records.
- **Out of scope:** §3. S1 and S3 stay deferred.
- **Acceptance signals:** AC 1–21.
- **Constraints:** §2.
- **Allowed substitutions (all proposed):**
  - (1–3) M9's substitutions 1–3, carried over;
  - (4) a TS xApp fork patch that keys `cell_map` from the decoded NR CGI;
  - (5) if the re-pre-registered R3′ forms no schedule, R2 becomes the top rung;
  - (6) if `UseIdealRrc=false` is still red after one guided fix, it is recorded and dropped;
  - (7) the scale run is capped at 20 periods if the 10-gNB compute time demands it.
- **Decision owner:** user

## 9. Unresolved questions
1. gNB-ID length: it must be 22–29 bits so the NCI can hold cellId ≤ 86. I lean to 28 [I].
2. P1 recipient: the serving en-gNB or the MN (3GPP TS 37.340 §10.5.1, unverified)?
3. Which counter P9 should use, and is re-pre-registering R3′ acceptable?
4. Do you approve the AC 20 projection and δ = 10 ms?
5. Do this brainstorm's Codex runs count against the goal's cap?
6. Should the A1 interpretations be ratified (carried over)?
7. Unverified:
   - whether the deployed kpimon decodes multi-record reports (stock `control.go.previous:752-766` treats measData items as "cells" [V]);
   - the 10-gNB slowdown;
   - rc's panic on an ACK without an outcome;
   - the KPM v03.00 clause numbers.

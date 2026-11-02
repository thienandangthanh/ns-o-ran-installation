# Brainstorm: post-M9 realism goal contract (input to `ak:goal-warmup`, then `/goal`)

Date: 2026-10-29 17:22–18:25 KST. Mode: `ak:brainstorm --ultra --advice`, with a 9-candidate pool at the user's request: 5 kongming (Opus 5.5, xhigh) and 4 Codex `gpt-6-astra` (xhigh), read-only, one identical evidence packet. Verifier: kongming (Opus 5.5, xhigh), on the same tier as the candidates, so this is same-tier best-of-9 with rubric selection, not an asymmetric verifier. Status: **winner selected; open user decisions below; not yet approved as an Outcome Contract** (approval happens in `ak:goal-warmup`).

Pool, packet, rubric and verdict: `brainstorm-261029-1824-GH-1-post-m9-realism-goal-contract-pool/`.

## User rulings in this session (17:30 KST, binding)
- Tracks in this one goal: E2 interop + scale (P1, P2, P4, P5, P8, P10, P11, N5, > 9 gNBs); timing realism (δ seam with δ = 0 byte-equal, δ sweep, P12, measurement-time stamping offered); radio/counter realism (P6, P7, P9, `UseIdealRrc=false` possibly).
- Out: real QP / R3, scenario-one, scenario-agnostic harness.
- Ops follow-ups 1, 2, 3, 5 as a prelude; follow-up 4 investigation only.
- End state: a new unattended run from `fresh-install`, like M9.
- δ source: delegated to this brainstorm ("5 kongming --ultra and 4 codex gpt-6-astra").

## Selected contract (candidate D, materialized unchanged)

### 1. Outcome
On VM `ubuntu24.04`, the ops prelude and all three tracks land. Then a new unattended run ("M10") reverts `fresh-install`, runs as one invocation and exits 0 with an exact pre-registered step set. That set is the M9 regression (m0–m7, i0, r0, r1, i2, r2, r3p) plus new steps for E2 interop, the δ sweep, the KPM subscription period, the radio-realism profile and scale (more than 9 gNBs). Before any wire change landed, the code at δ = 0, with every new switch at its default, reproduced the committed M9 `reference/r3p/` byte for byte. Each P1–P12 and N5 item ends as fixed, behind a disclosed switch, or listed with evidence.

### 2. Constraints
- **Carried from A1:** the pins.conf rule, judging on decoded wire bytes, the ledger and traces, never weakening a test, the snapshot rules (`fresh-install` and `f7-rerun-green` are never deleted), T8, no secrets, "TS xApp" vs "3GPP TS", Markdown only in plans/ and docs/, conventional commits, and branches on the forks.
- **Gate mode:** lock-step is the gate mode. Free run stays the default, and M5–M7 stay green after every agent or ns-3 change.
- **Switches:** every change that alters ns-3 output (δ > 0, T-C, `UseIdealRrc`) is a switch whose default reproduces M9.
- **Fork patches:** T-A needs patches to the rc, TS xApp and possibly kpimon forks through the Testbed `install_patch_files`. A1 excluded these, so they must be explicitly in scope here.
- **Standards:** a standards ledger in every phase, with clauses not read marked "unverified against Zotero".
- **Disk:** at least 20 GiB free on /home at dev times; during the end run, the watchdog trip computed per AC4.
- **Review:** kongming on opus at xhigh as `--advice`; Codex rules CX-1 to CX-4, cap 4.

### 3. Non-goals
- Real QP and R3 with real QP; the scenario-one smoke; a scenario-agnostic harness (S1/S3).
- Free-run gates; `RealtimeSimulatorImpl`.
- Window, late-apply or event-paused lock-step modes (counsel R4).
- Fixing the root cause of the stuck RMR route readers.
- Upstream PRs, the N release, host changes, publication.
- Migrating to E2SM-RC Style 5 (P13 candidate, §6).
- kpimon measurement-time stamping (§6 B3).

### 4. Acceptance criteria

**Ops prelude**
1. **FU1:** `finish()` stops the VM gate units without the `kill -0` guard [V `scripts/run-to-m9.sh:122`], and the TERM message [V `:131`] is corrected. A runner self-test case passes: the step pid has exited while a gate unit still runs, and the unit gets stopped.
2. **FU2:** after the M0 probe (branch create and delete) [V `scripts/gates/gate-m0-host.sh:46-52`] and a revert to `fresh-install`, an orphan check lists zero untracked overlays in the image directory. The check runs in dev and after the end run.
3. **FU3:** no check passes on `rtmgr_push_acked` [V `scripts/gates/rc-lib.sh:111`] alone; readiness needs receiver-side evidence, as `rt_reader_ok` does [V `bringup.sh:227`]. A fixture with an "OK" push log and a stuck reader fails.
4. **FU5:** h is computed by a script as the largest host-free drop over any 370 s window, across every M9 attempt's `free-series.tsv`. The output is recorded, and the trip = 25 + h.
5. **FU4:** a findings note on the stuck route readers (hypotheses, reproduction attempts). The F″ remedy is unchanged.
6. **Unverified rc claims:** rc's outcome-less-ACK panic and its 2 s ACK timer are verified with file:line at the deployed rc SHA before δ > 0 code lands. At δ = 500 ms the ACK takes about 3.5 s of wall time [C].

**T-B: timing realism**
7. **δ seam:** an `ActuationDelay` in sim time, default 0. The decision is taken at barrier k; the precheck, handover, ledger line and ACK run in one apply event at t_k + δ. At δ = 0 the ledger header stays `"delta-model":"fixed 0"` [V `oran-interface/model/e2-control-hub.cc:356`] and no new ledger field appears. Each control still pending at stop gets one FAILURE.
8. **Literal M9 equality:** with every switch at default (δ seam and P12 landed, nothing from T-A yet), the r3p C1 with `--reference` against the committed M9 `reference/r3p/` passes on every component, including the `extra` components `rc-multiset`, `kpm-headers` and `collet-start-time` [V `reference/r3p/equal/digests.json`]. This evidence is archived.
9. **δ sweep** on R3′ with δ ∈ {100, 150, 200, 500} ms:
   - in dev, a full C1 per δ and a committed sim-side reference per δ;
   - in every run, `applySimTimeNs − decisionSimTimeNs = δ` on each applied line, with HandoverStart at that time;
   - at least 1 applied handover per δ;
   - an outcome-vs-δ table in the run report.
10. **P12:**
    - kpimon's reporting period and granularity are configurable [today hard-coded: V `control.go.previous:437`, `wrapper.c.patch:401`]; the gated rungs use T/T.
    - The agent honours the action (option B). At T/T the output is unchanged (AC8).
    - At granularity T with a 1 s reporting period: one indication per 10 seqs carrying 10 records, and Influx = IPC for every seq. This also proves that kpimon decodes more than one record per message.
    - A non-multiple period is answered as not admitted on the decoded E2AP.

**T-A: E2 interop and scale**
11. **P10:** in every live capture of the end run, every agent → e2term DATA chunk carries PPID 70, judged per agent, and tshark decodes E2AP without a `-d` override.
12. **P11/N5:**
    - The gNB ID length is pre-registered, and the E2 Setup Global gNB ID uses it. Today the ID is 29 bits [V `ns3_e2_agent/src/e2ap-builders.cpp:110`].
    - rc and the agent use the spec NR CGI.
    - A target built by an independent encoder (asn1tools or pycrate from the spec ASN.1, not rc's asn1c) is `applied` in the ledger and in the ns-3 handover traces.
    - The 9-octet form [V `rc-control.cpp:25-33`] is answered `control-message-invalid`.
13. **P2/P5/P8:** on the decoded E2 Setup:
    - the eNB agent registers with a Global ENB ID, and the gNB agents with en-gNB IDs;
    - the request part decodes as an EN-DC X2 SETUP REQUEST listing the served NR CGIs;
    - RAN function 3 (RC) is announced;
    - every node is CONNECTED and kpimon subscribes to all of them;
    - the TS xApp builds its cell map from the decoded setup.
14. **P4/P1:**
    - The decoded RC UE ID is the pre-registered E2SM common §6.2.2.6 choice.
    - Controls go to the pre-registered serving node: the decoded meid and the ledger `viaNodeId` match it.
    - R2 and R3′ still pass.
15. **Scale gate:** `nMmWaveEnbNodes` ≥ 10 with all 11 agents CONNECTED.
    - Influx = IPC for every node and every seq.
    - Non-vacuity: at least one UE period where ns-3 measured more than 8 neighbours and the decoded KPM carries exactly 8 (`E2SM_REPORT_MAX_NEIGH = 8`, [V `mmwave-enb-net-device.h:71`]).
    - Cell IDs ≥ 10 appear in the decoded KPM and in the TS xApp's cell map, with at least one applied handover to such a cell.
    - simTime is set from a measured wall-seconds-per-sim-second rate at 10 gNB.

**T-C: radio and counter realism**
16. **P6/P7/P9:** each fix sits behind a realism switch, default off.
    - Switch off: digests unchanged.
    - Switch on: the lint matches each measName's source, unit and type to its 3GPP TS 28.552 clause, and the traces show an NR PDCP header on the EN-DC bearer (3GPP TS 37.340 §4.2.2).
    - One C1 under the realism profile, with its own reference.
17. **`UseIdealRrc=false`** [today true: V `scenario-zero.cc:483`]: a probe run. If it completes with at least one applied handover, it joins the profile; otherwise it is recorded as a deviation (proposed S-R).

**Regression, end run and records**
18. A check-diff ledger lists every changed m0–r3p check as old → new predicate, with why the new one is not weaker. No check is deleted.
19. **End run:** exit 0, `exactStepSet: true`, the top rung equals its committed reference, the watchdog never trips, and AC2 passes after the post-run revert.
20. **Records:**
    - a run report with the deviation table in its final state;
    - the standards ledgers;
    - updated README and docs (switches, δ, kpimon period, scale);
    - a journal at every pause, and a handoff.

### 5. Trade-offs

**Where δ comes from**

| Approach | Assumption it depends on most | Fails first when | Worst plausible case |
|---|---|---|---|
| Fixed sweep {100, 150, 200, 500} | Values anchored to the spec bracket a real loop | A reviewer asks "why 200?" | Disclosed and repeatable, but a model rather than a measurement |
| Free-run campaign first | Free run reveals RIC latency | At 2 gNB, C ≈ 0.70 s per period is far above L ≈ 5–13 ms [V `rung-config.json:14,18`], so every control lands at k+1 and δ_eff = 100 ms always [I]. It also needs a live-RIC free-run harness, which does not exist [C] | A phase spent learning "1 period"; the result depends on the host |
| Both | The campaign adds information | Same as the campaign | The cost of both, plus a mid-goal redesign if the campaign "disagrees" |

**Goal shape**

| Shape | Assumption it depends on most | Fails first when | Worst plausible case |
|---|---|---|---|
| G1: one goal in sequential milestones, with a literal-equality checkpoint before wire changes | The tracks can be ordered | T-A design choices stall | Long, but every digest change can be attributed |
| G2: one goal with the tracks interleaved | Changes are independent | P1 changes `viaNodeId` [V `e2-control-hub.cc:289-290`] and T-C changes traces | Reference drift with no attribution; equality is lost for good |
| G3: three goals | Separate runs lower the risk | It contradicts the ruling | Three runs of ~3.5 h each, and repeated disk freeing |

### 6. Better approaches

- **B1 (challenges a ruling): scope of the "δ = 0 byte-equal" requirement.**
  - Evidence: the r3p reference holds the wire components `rc-multiset` and `kpm-headers`. P11 and P4 change the RC payload, P1 changes the ledger's `viaNodeId`, and P5 may change the header.
  - So literal equality cannot hold after T-A without keeping legacy wire modes alive.
  - Delta: prove literal equality once (AC8), before T-A. After that, M10 references must equal M9 on IPC, traces and predictor records, and on the ledger and `extra` components after the pre-registered field transforms (for example, the P1 `viaNodeId` rule).
  - Switching cost: one transform-compare script that reads the archived raw files of the M9 reference.
  - Proposed substitution SUB-1.
- **B2 (challenges a ruling): h ≈ 9 is too low.**
  - Evidence: M9's own `free-series.tsv` fell 84 → 72 GiB between 17:50:07Z and 17:55:37Z [V, computed], a 12 GiB drop inside a 370 s window. h = 9 sits below a burst that M9 itself measured.
  - Delta: h = 12, trip 37. Cost: 3 GiB more disk.
- **B3: measurement-time stamping in kpimon, argued out.**
  - It has no consumer in scope: R3′ windows by `ns3.seq`, and QP is out.
  - The harness queries Influx by wall-time range [V `scripts/gates/agents-ns3-run.sh:161`], so stamping by measurement time would break judges that pass today.
  - Defer it to the real-QP goal.
- **B4: P10 lives in the agent, not e2sim.** The agents send through their own `::send` [V `ns3_e2_agent/src/sctp-association.cpp:147`]. e2sim's `send()` is at [V `oran-e2sim/e2sim/src/SCTP/e2sim_sctp.cpp:228`]. Fix: set `SCTP_DEFAULT_SNDINFO` to PPID 70 in the agent; the e2sim pin can stay.
- **P13 candidate (record only).** E2SM-RC v03.00 §7.6.6.1 Style 5 action 3, "DC PSCell Change control", and action 4, "DC Secondary Node Change Control" (§8.4.6.3–8.4.6.4) [V, vault cache `JRDTL7XS`], fit an inter-en-gNB move better than Style 3 action 1. This bears on the P1 fix.

Otherwise the recommended direction is the one requested.

### 7. Recommended direction

**δ source: the fixed sweep gates, with no campaign.** Reasons:
- Gating needs determinism, and lock-step stays the gate mode.
- At 2 gNB, free-run measurement collapses to the period quantum.
- The RIC-half latency is already measured at no cost (L_max 12.9 / 8.2 / ~5.4 ms; R3′ [C]). Record it as context.
- {100–500} lies inside the E2GAP §5.1.1 range of 10 ms–1 s [C].
- 150 ms falls between barriers.
- The D5 analysis puts the cost at about 2 % at 100 ms and about 10 % at 500 ms [C], so the sweep spans the range where the effect appears.

**Milestones:**
- **MA, ops prelude:** AC1–6.
- **MB, no-op-at-default changes:** δ seam and P12, then AC8 (literal equality), then δ references.
- **MC, T-A:** P10 first, then the ID set P11/N5/P2/P5/P8, then P4/P1.
- **MD, scale gate:** after N5/P11.
- **ME, T-C switches.**
- **Stop B, disk, then the end run.**

T-A design choices (gNB ID length, the UE ID choice, the serving node) are pre-registered in the plan and approved at warmup.
- **gNB ID length:** 32 bits, hex-aligned with the TS xApp's 10-hex-digit key ("36 bit long, last 4 bit unused") [V, upstream clone `ric-app-ts/src/ts_xapp/ts_xapp.cpp:366`] [I].

**Budget:**
- **Disk:** T′ = (25 + 12) + 43 + 12 + N_new, where N_new is measured in dev (8–15 GiB inferred [I]).
- **Clearing the last leak:** the post-M9 overlay leaks one last time (about 42 GiB) [I]. Delete it under the 2026-10-28 ruling.
- **Start condition:** the end run starts only when X′ − T′ ≥ 0.
- **Wall:** ceil(1.5 × Σ longest green) [I ≈ 27–30 ks].
- **Scale step:** its simTime is chosen so the step takes ≤ 45 min.

### 8. Draft `ak:goal-warmup` Outcome Contract
> Superseded on 2026-11-03 by `contract-261103-0001-GH-1-post-m9-realism-outcome-contract.md` (kongming fixes and user rulings R1–R12 applied). Kept as the historical draft.

- **Intended result:** §1. All fork code is pushed on `dev/l-release-nist180` and pinned in `scripts/pins.conf`.
- **In scope:**
  - ops prelude FU1, 2, 3, 5 and the FU4 note;
  - T-A: P1, P2, P4, P5, P8, P10, P11, N5 and the scale gate of more than 9 gNBs;
  - T-B: δ seam and the {100, 150, 200, 500} sweep; P12 option B with a configurable kpimon period;
  - T-C: P6, P7, P9 behind switches, with `UseIdealRrc=false` probed first;
  - rc, TS xApp and kpimon fork patches;
  - the M10 runner; records.
- **Out of scope:** §3.
- **Acceptance signals:** AC1–AC20.
- **Constraints:** §2.
- **Allowed substitutions:** the A1 substitutions 1–3 carry over (applied), plus:
  - SUB-1 (proposed): B1's transform-equal reference after the literal checkpoint;
  - S-R (proposed): `UseIdealRrc` stays ideal and is recorded, if its probe fails;
  - SUB-H (proposed): h = 12 instead of 9.
- **Decision owner:** user.

### 9. Unresolved questions
1. Approve SUB-1, or keep legacy wire switches so literal equality holds forever?
2. h = 12 (B2) or the ruled ≈ 9?
3. Do measurement-time stamping (B3) and the P13 Style 5 item stay out?
4. The P1 serving node (the MN, or the source SN as in 3GPP TS 37.340 §10.5.1), and the P4 UE ID fields. These are user and spec decisions.
5. Do this brainstorm's 4 Codex runs count against M10's cap? A1's precedent says no [V `goal-packet.md:26`].
6. P9 is fixed by honest crediting, but R3′'s predictor reads that counter. Which counter does it read under the realism profile?
7. Unverified: e2mgr L-release accepting en-gNB/eNB node types; the cost of ns-3 at 10 gNB; the KPM v03.00 clauses (not read); the rc claims (AC6).


## Ranking appendix

| Rank | Label | Source | Total (7 × 20) | Hard constraints |
|---|---|---|---|---|
| 1 | D | kongming 1 | 121 | pass (H3 conditional) |
| 2 | A | kongming 3 | 118 | pass |
| 3 | F | kongming 4 | 116 | pass |
| 4 | C | kongming 5 | 113 | pass (H3 conditional) |
| 5 | G | kongming 2 | 104 | fail H3 (no literal M9 equality check) |
| 6 | E | Codex 2 | 89 | pass (scale caveat) |
| 7 | B | Codex 4 | 88 | pass (scale caveat) |
| 8 | I | Codex 3 | 88 | fail H4 (PPID 70 only on realism captures) |
| 9 | H | Codex 1 | 85 | pass (scale caveat); wrong P10 sender |

Why D won (verifier): the most accurate budget (counts the last post-M9 overlay leak and sets a start condition), h = 12 matches M9's measured 12 GiB burst in 370 s, complete trade-off tables, and every challenge to a ruling is routed to the user. Why low margin: A is more faithful to the literal δ = 0 ruling (a compat profile keeps the end run equal to the unchanged `reference/r3p/`); a user preference for literal equality would flip D and A.

Spot-checks the verifier made in the repo (read-only):
- Literal δ = 0 equality cannot survive unconditional P1/P4/P11 fixes: `reference/r3p/equal/digests.json` pins `ledger` and `extra{rc-multiset, kpm-headers, collet-start-time}`, compared by `scripts/gates/ts-rung-lib.sh:207-221`.
- P10's sender is the agent's own `::send` (`ns3_e2_agent/src/sctp-association.cpp:147`), not e2sim; the run report's P10 location is wrong.
- The scale gate needs `nMmWaveEnbNodes` ≥ 10: the neighbour map includes the serving cell, so N = 9 only reaches `maxNeigh` = 8.
- Measurement-time stamping has no in-scope consumer and would overwrite untagged kpimon points across nodes.

ultra: picked=1/9 margin=low unanimous=no rejected_all=no

## Winner defects to settle (from the verifier; for the warmup interview)
1. δ = 0 ruling narrowed: literal equality to `reference/r3p` only at the AC8 checkpoint before T-A, then SUB-1 (transform-equal). The alternative is a compat profile (A, F): literal equality in the end run, at the cost of dual wire modes in agent, rc and TS xApp; AC12 and the end-run step set would then change.
2. Measurement-time stamping excluded (B3, Q3), although you offered it inside T-B. If kept, it needs kpimon tags and changed harness range queries.
3. h = 12 (SUB-H) instead of the ruled ≈ 9; about +3 GiB disk.
4. AC19 under-specified: which reference, `minHostFreeGb ≥ 25`, RestartCount 0, the exact end-run step list and δ steps in it.
5. Outcome lets a P item end "listed with evidence"; only an approved substitution should allow that.
6. P11 gNB ID length 32 bits (4-bit cell part) vs most candidates' 28 + 8; needs a user decision.
7. P12 gate depends on kpimon decoding multi-record Format 1; no fallback (A's substitution 6 / F's (d) have one).
8. AC8 assumes P12 at T/T is byte-neutral [I].
9. P1 requires rewriting the `via_target` check at `scripts/gates/gate-r3p-ts-predictor.sh:234`; register it as a contract change before code.
10. Unverified: e2mgr accepting en-gNB/eNB node types; rc outcome-less-ACK panic and 2 s timer at `a2282ee`; 10-gNB cost; KPM v03.00 and RC Style 5 clause text.
11. Citation slip: `rung-config.json:15,19` should be :14, :18.

## Process disclosures
- One accidental Codex run: `task --help` started a real read-only task (it printed a skill list) at about 17:30 KST, the same slip as in M9. With the 4 requested candidate runs, this session made 5 Codex calls.
- One candidate wrote a 265 KB spec-text cache into the controller's scratchpad despite the read-only brief; nothing was written in the repo (`git status` clean apart from the pre-existing `.claude/`, `.remember/`).
- The pool exceeds the skill's default of 5 candidates by the user's explicit request.

## Unresolved questions
1. δ = 0: SUB-1 (literal before T-A, transform-equal after) or a compat profile (literal in the end run)?
2. Measurement-time stamping: out (evidence) or in (needs kpimon tags)?
3. h = 12 or 9?
4. P11 gNB ID length: 32 (D) or 28 + 8 (A, C, G)?
5. P1 serving node: MN eNB or source en-gNB (3GPP TS 37.340 §10.5.1); P4 UE-ID choice.
6. Do this brainstorm's Codex runs count against the next goal's cap of 4? A1 precedent: earlier runs were not counted (`goal-packet.md:26`).
7. Ratify the A1 interpretations (a)–(k)?

## Advisory checkpoint (kongming, 18:33 KST)
Verdict **GO-WITH-CHANGES**: hand D to `ak:goal-warmup`; no redo, no switch to A. Before contract approval, fix verifier defects #1 (SUB-1 plus hardening: tag the AC8 commit; after T-A, ipc/traces/predictor-records/scenario/schedule stay literal; transforms only on enumerated fields with a negative fixture), #4, #5, #6, #7 and #9 (widened: every predicate encoding P1, P5 or N5 is a registered contract change), plus a new defect N1 (e2term names en-gNBs `en_gnb_…`, so the stock TS xApp cell map is empty; AC13 must name the patch). Use three Stops (A after the δ seam and checkpoint, A′ after the T-A identity cluster, B before the end run) and two prelude probes (e2mgr/e2term acceptance of en-gNB/eNB setups; a 10-gNB wall and disk probe). Next risk: the T-A identity cluster. Full counsel: `kongming-261029-1833-GH-1-post-m9-realism-brainstorm-go-no-go.md`.

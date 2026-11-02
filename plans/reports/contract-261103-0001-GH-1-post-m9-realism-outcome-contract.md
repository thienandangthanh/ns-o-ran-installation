# Outcome Contract: post-M9 realism goal (M10)

Date: 2026-11-03 00:05 KST. Status: **APPROVED by the user in `ak:goal-warmup`, 2026-11-03**, including the three open points at the end (en-gNB-UEID, P9 corrected counter, S-R and SUB-P12 approved). Immutable: any outcome or scope change is a Decision required.

**Amendment 1 (2026-11-03 01:05 KST, user rulings on warmup review findings):** AC8b (F1, option a), AC11 (e2sim PPID), AC14 and new AC14b (F5, option A). Sources: `kongming-261103-0034-GH-1-m10-plan-review.md`, Codex plan review run 1. Rows marked "A1" in the change log. **Re-approved by the user 2026-11-03 01:10 KST.**

Built from candidate D (`brainstorm-261029-1824-GH-1-post-m9-realism-goal-contract.md` §1–§8). It applies kongming's required fixes #1, #4, #5, #6, #7, #9 and N1 (`kongming-261029-1833-GH-1-post-m9-realism-brainstorm-go-no-go.md`) and the user rulings R1–R12 (`decisions-261102-2235-GH-1-post-m9-realism-user-rulings.md`). The change log at the end maps each edit to its source.

Notation: [V] verified at file:line; [I] inferred; [C] carried from earlier evidence. "TS xApp" is the traffic-steering xApp; "3GPP TS" is a 3GPP specification.

## 1. Intended result

On VM `ubuntu24.04`, the ops prelude and all three tracks land. A new unattended run ("M10") then reverts `fresh-install`, runs as one invocation and exits 0 with the exact pre-registered step set of AC19.

Proof of continuity with M9 is a chain of tagged checkpoints:
- **Checkpoint 1**, before any wire change: the code reproduces the committed M9 `reference/r3p/` byte for byte (AC8).
- **Checkpoint 2**, after T-A: the non-wire components are still literally equal, and the wire components are equal under enumerated transforms only (AC8b).
- **Checkpoint 3**, after T-C: new references, with a diff that names every changed component and its cause (AC16).

After each checkpoint, the compliant behaviour is the only behaviour; M9's behaviour survives in git tags, committed references and archived evidence, never as a mode in the code (principle, R1/R8).

Each item P1–P13 and N5 ends **fixed**. An item may end **listed with evidence** only under an approved substitution (§7).

## 2. In scope

- **Ops prelude (MA):** FU1, FU2, FU3, FU5; an FU4 findings note; two probes (AC6a, AC6b).
- **T-B, timing (MB):** P3 via the δ seam and the sweep {100, 150, 200, 500} ms; P12 option B with a configurable kpimon reporting period and granularity.
- **T-A, E2 interop, identity and control (MC):** P10, then the identity cluster P11/N5/P2/P5/P8, then P4/P1/P13.
- **Scale gate (MD):** N ≥ 10 gNBs, after P11/N5.
- **T-C, radio and counter realism (ME):** P6, P7, P9; `UseIdealRrc=false` after its probe.
- **Fork patches** through the Testbed `install_patch_files`: rc, TS xApp (including the N1 `en_gnb_` meid patch), kpimon (including the AC14b UE ID), and e2sim (AC11 PPID), as needed. All fork code is pushed on `dev/l-release-nist180` and pinned in `scripts/pins.conf`.
- **The M10 runner** and the records (AC20).

## 3. Out of scope

- Real QP, and R3 with real QP; the scenario-one smoke; a scenario-agnostic harness (S1/S3).
- Free-run gates; `RealtimeSimulatorImpl`; window, late-apply or event-paused lock-step modes.
- kpimon measurement-time stamping (R2; deferred to the real-QP goal).
- An MN-decided inter-frequency SN change (E2SM-RC Style 5 actions 1+2 to the MN). scenario-zero is single-carrier [V `scenario-zero.cc:512,525`].
- Compat profiles, legacy wire modes, or switches whose default reproduces M9 (R1, R8).
- Fixing the root cause of the stuck RMR route readers (FU4 is a note only).
- Upstream PRs, the N release, host changes, publication.

## 4. Acceptance signals

### Ops prelude (MA)
1. **FU1:** `finish()` stops the VM gate units without the `kill -0` guard [V `scripts/run-to-m9.sh:122`], and the TERM message [V `:131`] is corrected. Runner self-test: the step pid has exited while a gate unit still runs, and the unit gets stopped.
2. **FU2:** after the M0 probe (branch create and delete) [V `scripts/gates/gate-m0-host.sh:46-52`] and a revert to `fresh-install`, an orphan check lists zero untracked overlays in the image directory. It runs in dev and after the end run.
3. **FU3:** no check passes on `rtmgr_push_acked` [V `scripts/gates/rc-lib.sh:111`] alone; readiness needs receiver-side evidence, like `rt_reader_ok` [V `bringup.sh:227`]. A fixture with an "OK" push log and a stuck reader fails.
4. **FU5:** a script computes h as the largest host-free drop over any 370 s window across every M9 attempt's `free-series.tsv` and every dev rehearsal of the new steps. **h = 12 GiB, trip = 37 GiB** (R11). If the script's worst burst exceeds 12, the run stops for a user ruling instead of raising h silently.
5. **FU4:** a findings note on the stuck route readers (hypotheses, reproduction attempts). The F″ remedy is unchanged.
6. **rc claims:** rc's outcome-less-ACK panic and its 2 s ACK timer are verified with file:line at the deployed rc SHA before δ > 0 code lands.
   - **6a, identity probe:** the live e2mgr and e2term of the deployed L-release images accept an E2 Setup from an eNB (Global ENB ID) and from an en-gNB (32-bit Global en-gNB ID). The probe records the meids e2term produces (expected `enB_macro_…`, `en_gnb_…` [V master `BuildRunName.h:150-200`]) and the e2mgr nodeb JSON. If either is refused, the goal stops with Decision required.
   - **6b, scale probe:** one 10-gNB ns-3 run measures the wall seconds per sim second and the disk growth. The result sets the AC15 simTime and the disk budget (Stop B).

### T-B: timing (MB)
7. **δ seam:** an `ActuationDelay` in sim time, default 0. δ is a model parameter, not a compat switch. The decision is taken at barrier k; the precheck, handover, ledger line and ACK run in one apply event at t_k + δ. At δ = 0 the apply stays synchronous (no zero-delay event, so ties cannot reorder), the ledger header stays `"delta-model":"fixed 0"` [V `oran-interface/model/e2-control-hub.cc:356`] and no ledger field is added. Each control still pending at stop gets one FAILURE.
8. **Checkpoint 1, literal M9 equality:** after the δ seam, and again after P12 (at T/T), the r3p C1 with `--reference` against the committed M9 `reference/r3p/` passes on every component, the `extra` ones included (`rc-multiset`, `kpm-headers`, `collet-start-time`) [V `reference/r3p/equal/digests.json`]. The passing commit is **tagged**; the evidence is archived. No T-A code lands before this tag.
   - **8b, Checkpoint 2 (SUB-1, hardened, R1):** after T-A, at δ = 0 and before T-C:
     - ipc and traces are still literally equal to M9;
     - predictor records, scenario and schedule equal a pre-registered transform of the M9 files (A1, F1 option a): N5 cell key → NCI key, `via` target → source, `scenarioSha256` recomputed, the two P1 description strings replaced, and `ueId` per AC14b. Every other byte, including every predictor number, stays literal;
     - the ledger and `extra` components are equal after transforms on an enumerated field list only (viaNodeId, the RC UE ID, the RC action and its target encoding in rc-multiset, meid);
     - a negative fixture shows that a mutated M9 file fails the transform-compare;
     - the passing commit is tagged.
9. **δ sweep** on R3′ with δ ∈ {100, 150, 200, 500} ms:
   - in dev, a full C1 per δ and a committed sim-side reference per δ;
   - in every run, `applySimTimeNs − decisionSimTimeNs = δ` on each applied line, with HandoverStart at that time;
   - at least 1 applied handover per δ;
   - an outcome-vs-δ table in the run report.
10. **P12:**
    - kpimon's reporting period and granularity are configurable [today hard-coded: V `control.go.previous:437`, `wrapper.c.patch:401`]; the gated rungs use T/T = 100/100 ms.
    - The agent honours the action (option B). At T/T the output is unchanged (AC8).
    - At granularity T with a 1 s reporting period: one indication per 10 seqs carrying 10 records, and Influx = IPC for every seq. This proves kpimon decodes multi-record Format 1. If it cannot without rewriting its decoder, SUB-P12 applies (§7).
    - A period that is not a multiple of T is answered as not admitted on the decoded E2AP.

### T-A: E2 interop, identity and control (MC)
11. **P10:** in every live capture of the end run, every E2 node → e2term DATA chunk carries PPID 70, judged per node, and tshark decodes E2AP without a `-d` override. "Every E2 node" covers the ns-3 agents (fix in their own `::send` [V `ns3_e2_agent/src/sctp-association.cpp:147`]) and the M2/M3 reference node kpm_sim (fix in the `send()` of the e2sim kpm_sim is built from: the Testbed's OSC `e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp`, patched through `install_patch_files/e2-interface/` [V `install_scripts/install_e2sim.sh:49-59`]) (A1; citation corrected 2026-11-03 01:45 KST, requirement unchanged).
12. **P11/N5, gNB ID and NR CGI (R5):**
    - The gNB ID is **32 bits** and equals the ns-3 cellId; the NR Cell Identity is the 32-bit gNB ID plus a constant 4-bit cell part (one cell per gNB). Today the agent sends a 29-bit ID left-aligned [V `ns3_e2_agent/src/e2ap-builders.cpp:110-113`].
    - On the live RIC: the e2term meid suffix is the right-aligned hex of the ID (for example `…_00000002`) and the e2mgr `nbId` is a 32-character binary string.
    - rc, the TS xApp key, and the agent use the spec NR CGI; the agent maps the gNB ID to the cell, no longer `o[8]` [V `rc-control.cpp:31`].
    - A target encoded by an independent encoder (asn1tools or pycrate from the spec ASN.1, not rc's asn1c) is `applied` in the ledger and in the ns-3 handover traces.
    - The 9-octet form [V `rc-control.cpp:25-33`] is answered `control-message-invalid`.
13. **P2/P5/P8, E2 Setup (and N1):** on the decoded E2 Setup:
    - the eNB agent registers with a Global ENB ID and the gNB agents with Global en-gNB IDs;
    - the request part decodes as an EN-DC X2 SETUP REQUEST listing the served NR CGIs;
    - RAN function 3 (E2SM-RC) is announced with Control Style 5 action 3 in its definition;
    - every node is CONNECTED and kpimon subscribes to all of them;
    - **N1:** the TS xApp fork is patched to parse `en_gnb_…` meids (4 underscores; the stock parser counts 3 [V upstream `ts_xapp.cpp:330-372`]), and it builds a non-empty cell map from the decoded setup.
14. **P4/P1/P13, RC control (R6, R7, R10):**
    - Mobility controls are **E2SM-RC Control Style 5 action 3, "DC PSCell Change control"** (E2SM-RC v03.00 §8.4.6.3) [V Zotero `JRDTL7XS`]. Style 3 action 1 is removed from the control path. With one cell per gNB every PSCell change is inter-SN, that is an SN-initiated SN change (3GPP TS 37.340 §10.5.1; E2SM-RC §8.4.6.4).
    - Each control is addressed to the UE's **source en-gNB**: the decoded meid and the ledger `viaNodeId` equal the source en-gNB.
    - ns-3 executes the control as an SN-initiated SN change toward the target PSCell.
    - The decoded RC UE ID is the pre-registered E2SM common §6.2.2.6 choice, **en-gNB-UEID**, filled with identifiers ns-3 really holds (cited file:line in the plan). The TS xApp takes these values from the KPM UE IDs of AC14b, never from an ns-3 side channel (A1). If ns-3 holds no X2AP-type UE ID, the goal stops with Decision required.
    - The RAN parameter IDs used for action 3 are read from the E2SM-RC version that the rc fork's ASN.1 implements and are recorded in the standards ledger.
    - R2 and R3′ still pass.
14b. **P4 KPM UE IDs (A1, F5 option A):**
    - ns-3 exports each UE's X2AP context (the IDs the en-gNB and eNB really hold) on a channel that leaves the existing IPC trace files literal.
    - On the decoded KPM, the en-gNB agents report UE IDs as en-gNB-UEID and the eNB agent as eNB-UEID (E2SM common §6.2.2.6); no IMSI is carried as a gNB-UEID.
    - kpimon stores the decoded UE ID in Influx, and the TS xApp reads it from there to build the AC14 control.
    - P4 ends "fixed" for both RC and KPM.
15. **Scale gate (MD):** `nMmWaveEnbNodes` ≥ 10 with all 11 agents CONNECTED.
    - Influx = IPC for every node and every seq.
    - Non-vacuity: at least one UE period in which ns-3 measured more than 8 neighbours and the decoded KPM carries exactly 8 (`E2SM_REPORT_MAX_NEIGH = 8` [V `mmwave-enb-net-device.h:71`]).
    - Cell IDs ≥ 10 appear in the decoded KPM and in the TS xApp's cell map, with at least one applied PSCell change to such a cell.
    - simTime is set from AC6b's measured rate so the step takes ≤ 45 min.

### T-C: radio and counter realism (ME)
16. **P6/P7/P9 (R8, no switches):** each fix lands at its own commit and is then the only behaviour.
    - The lint matches each measName's source, unit and type to its 3GPP TS 28.552 clause.
    - The traces show an NR PDCP header on the EN-DC bearer (3GPP TS 37.340 §4.2.2).
    - P9: R3′'s predictor reads the corrected counter; any predicate change is registered per AC18.
    - **Checkpoint 3:** new references for every C1 rung, and a diff report that lists each changed component with the fix that changed it. Components not explained by a T-C fix must stay equal to checkpoint 2. The commit is tagged.
17. **`UseIdealRrc=false`** [today true: V `scenario-zero.cc:483`]: a probe run comes first. If it completes with at least one applied PSCell change, `false` becomes the only setting before checkpoint 3. Otherwise S-R applies (§7).

### Regression, end run and records
18. **Check-diff ledger:** every changed m0–r3p check is listed as old → new predicate, with why the new one is not weaker. No check is deleted. **Rewriting any predicate that encodes P1, P5 or N5 is a registered contract change, recorded before the code** (#9). Known sites:
    - d7 "via the target gNB (recorded deviation P1)" [V `r3p-checks.py:203-207`], used by r0, r1, r2, r3p;
    - `via_target` [V `scripts/gates/gate-r3p-ts-predictor.sh:234`];
    - cell-map expectations [V `gate-r0-rc-scripted.sh:150-152`];
    - meid literals [V `gate-m5-agent-setup.sh:25`], in `rc-send.sh`, `replay-ts-cell-map.py` and the probes.
19. **End run (M10)** (#4):
    - **Step set**, pre-registered in the plan before runner code: M9's m0–m7, i0, r0, r1, i2, r2, r3p; plus one E2-interop step (AC11–AC13), one P12 step (AC10), one full C1 at δ = 150 ms, short δ-identity runs at δ = 100, 200 and 500 ms, and the scale step (AC15). The verdict requires `exactStepSet: true`.
    - **References:** r3p at δ = 0 equals the checkpoint-3 reference; the δ = 150 C1 equals its own reference. The M9 `reference/r3p/` stays reachable through the checkpoint-1 and checkpoint-2 tags.
    - **Health:** exit 0, every step green, `minHostFreeGb ≥ 25`, the watchdog (trip 37) never trips, rc RestartCount 0, and AC2 passes after the post-run revert.
20. **Records:**
    - a run report with the P1–P13/N5 table in its final state and every substitution used;
    - a standards ledger per phase (clauses not read marked "unverified against Zotero");
    - updated README and docs (δ, kpimon period, gNB ID format, RC Style 5, scale);
    - a journal at every Stop, and a handoff.

## 5. Constraints

- **Carried from A1:** the pins.conf rule; judging on decoded wire bytes, the ledger and traces; never weakening a test; snapshots `fresh-install` and `f7-rerun-green` are never deleted; T8; no secrets; "TS xApp" vs "3GPP TS"; Markdown only in plans/ and docs/; conventional commits; branches on the forks.
- **Spec compliance (R1, R8):** fixes follow the official O-RAN and 3GPP specs; no compat profiles, legacy wire modes, or default-off switches. Old behaviour lives only in git tags, committed references and archived evidence.
- **Gate mode:** lock-step is the gate mode. Free run stays the default, and M5–M7 stay green after every agent or ns-3 change.
- **Standards:** a standards ledger in every phase.
- **Disk:** at least 20 GiB free on /home during dev; during the end run, watchdog trip 37 GiB (h = 12). Nothing is deleted autonomously beyond the 2026-10-28 overlay ruling.
- **Review:** kongming on Opus 5.5 at xhigh as `--advice`. Codex read-only, one call at a time, each run disclosed; **no run cap** (R3).
- **Stops (user checkpoints, the goal pauses):**
  - **Stop A** after MB: checkpoint 1 tagged, δ references banked, budget re-projected.
  - **Stop A′** after the T-A identity cluster (P11/N5/P2/P5/P8) and P4/P1/P13: checkpoint 2 tagged.
  - **Stop B** before M10: disk check (start only when free ≥ T′), the user frees space if short.
- **A1 interpretations (a)–(k)** from `run-report-261029-0535-GH-1-m8-m9-deviations.md` are ratified and carry over (R12).

## 6. Decision owner
User.

## 7. Allowed substitutions

- A1 substitutions 1–3 carry over (applied).
- **SUB-1** (approved, R1): transform-equal comparison after checkpoint 1, hardened as AC8b.
- **SUB-H** (approved, R11): h = 12, trip 37.
- **S-R** (approved 2026-11-03): if the `UseIdealRrc=false` probe fails, `UseIdealRrc` stays `true` and P-row "ideal RRC" is listed with the probe evidence.
- **SUB-P12** (approved 2026-11-03, #7): if kpimon cannot decode multi-record Format 1 without rewriting its decoder, the P12 period gate runs at granularity = reporting period = 2T (one record per indication at a non-default period), and the multi-record gap is listed.

No other item may end as "listed with evidence".

## Change log against candidate D

| Edit | Source |
|---|---|
| §1: literal M9 equality only at tagged checkpoint 1; checkpoint chain 1–3 | #1, R1, R8 |
| AC8b: hardening (literal non-wire components, enumerated transforms, negative fixture, tag) | #1 |
| §2/§5 "Switches" removed; AC16/AC17 compliant-only | R8 |
| AC4: h = 12, trip 37; extended to dev rehearsals | R11, kongming Q2.3 |
| AC6a/AC6b: two prelude probes | kongming Q4 |
| AC7: synchronous apply at δ = 0 | #8 |
| AC10: T/T = 100/100 ms named; SUB-P12 fallback | #7 |
| AC12: 32-bit gNB ID, RIC rendering | #6, R5 |
| AC13: N1 TS xApp `en_gnb_` patch; Style 5 in the RAN function definition | N1, R7 |
| AC14: Style 5 action 3 to the source en-gNB; en-gNB-UEID; P13 in scope | R6, R7, R10 |
| AC18: P1/P5/N5 predicate rewrites are registered contract changes | #9 |
| AC19: step list, references, minHostFreeGb, RestartCount, watchdog | #4 |
| §1/§7: "listed" only under an approved substitution | #5 |
| §3: measurement-time stamping out; MN-decided inter-frequency SN change out | R2, R7 |
| §5: Codex no cap; A1 (a)–(k) ratified; three Stops | R3, R12, kongming Q4 |
| P3 named under T-B (the δ seam is its fix) | run report P3 row |
| Citation `rung-config.json:15,19` → `:14,:18` (in the brainstorm report) | #11 |
| A1: AC8b predictor records, scenario, schedule → registered transform | warmup F1, user option (a) |
| A1: AC11 covers every E2 node; e2sim `send()` patched | kongming plan review, user ruling |
| A1: AC14 UE ID sourced from KPM; new AC14b (KPM en-gNB-UEID / eNB-UEID, kpimon → Influx → TS xApp) | warmup F5, user option A |

## Open points for approval
1. **P4 RC UE ID = en-gNB-UEID** follows from R6 (source en-gNB addressee) but was not ruled separately.
2. **P9:** the predictor reads the corrected counter, which may move R3′'s outcome; this resolves brainstorm Q6.
3. **S-R and SUB-P12** are proposed, not yet approved.

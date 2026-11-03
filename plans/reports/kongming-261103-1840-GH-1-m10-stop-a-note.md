# kongming: M10 Stop A note (after P04)

Date: 2026-11-03 18:40 KST. This is `--advice` counsel for the Stop. It is read-only: I did not touch the VM, code, plan, ledger, evidence or journal. Runtime: Opus 5.5 (`model: opus`), per the user's CLAUDE.md override of the `fable` routing. Counsel is not user approval.

## Verdict: FIX-FIRST (3 musts; text edits plus a push, about 20 min, no VM)

**TL;DR**
- **The Stop A entry condition is met in substance.** I verified all of it:
  - `m10-cp1` is annotated and pushed in all 5 repos, with peeled SHAs equal to the pins;
  - the 4 δ references and `m9-r3p-raw` pass `sha256sum -c`;
  - the 25/12/5/4 split of ledger rows 10–55 is correct;
  - I-1 to I-9 are listed;
  - T′ is given under both bases.
- **The journal's budget section has to be fixed before `PAUSE A`.**
  - It says AC6b "has not run". AC6b ran in P01 and was green, and phase-04 requires its numbers in the re-projection.
  - It reads the 52 GiB overlay as a sign that the 42 GiB base is low. That conclusion does not follow: the two step mixes are not comparable.
  - The three commits since `876c8d6` are not pushed.
- **On δ (Q2): no ruling is needed.** AC9 is met as written. AC7's breadth comes from the seam smoke, which also shows δ changing an outcome. Two plan gaps should be disclosed at Stop A:
  - the seam smoke is never re-run after P07 changes the hub;
  - the δ rungs have no cp2 baseline for AC16.

## Q1. Is Stop A's entry condition met?

| Condition (plan.md:106-110; phase-04:12) | Status | Evidence I checked |
|---|---|---|
| cp1 tagged | ✓ | `git rev-parse m10-cp1^{commit}` gives harness 83443e1, Testbed 809fb2d, ns-3 48d41a5, oran-interface b2342c6, e2sim 2209995, matching `scripts/pins.conf` at 83443e1. `git ls-remote origin refs/tags/m10-cp1^{}` peels to the same 5 SHAs, and the remote tag objects (8109b77, b9a0b35, 379a154, 91fcb19, a5001e4) equal the local ones. Each fork SHA is on `origin/dev/l-release-nist180`, and 83443e1 is on `origin/migrate-l-release-NIST-1-8-0`. All tags are annotated, at 16:19:43 KST. The AC8 run-2 verdict has `harness_sha` 83443e1, 177 checks, `equalsReference` true. The seam smoke at 83443e1 (`evidence/delta-seam-smoke/20261103T071157Z`, 25/25) ended about 07:17:48Z, before the tag at 07:19:43Z, so my P03 must holds |
| δ references banked | ✓ | `reference/r3p-d{100,150,200,500}/SHA256SUMS` and `m9-r3p-raw/SHA256SUMS` are OK, and `reference/SHA256SUMS` covers `identity-map-cp1.json`. The four C1 verdicts at 876c8d6: 176/176, `deltaMs` 100/150/200/500, `appliedHandovers` ≥ 1, the `actuation_delay` check passes with offsets [3.0]. The ledger apply − rx is exactly δ (for example 3,500,800,000 − 3,000,800,000 at δ = 500). `git diff 83443e1 876c8d6 -- scripts tools` touches only p12 files, so the refs are equivalent to cp1 for r3p. The extractor `--self-test` is ok, and its fixtures cover two RNTIs and a non-MN cell |
| #9 rewrites registered | ✓ | I parsed rows 10–55: P1 rows 10, 11, 12, 15, 16, 24, 25, 30 (8); N5 rows 26, 27, 40, 42, 46, 47 (6); P1 + N5 (11); held under D2 (12); pending (31, 43, 44, 45, 48); ordinary (50–52, 55). That is 46 rows. The planner's phase-file edits are applied in phase-06, phase-07 and plan R-2/R-3/R-7 |
| Interpretations listed | ✓ (by reference) | Journal:54-59 |
| T′ under both bases | ✓ in form, ✗ in content | Arithmetic: 37 + 43 + 12 + (8–15) = 100–107 and 37 + 42 + (8–15) = 87–94, both correct. Content: see must 1 and must 2 |
| Packet: journal, kongming note, resume card, push, PAUSE line (plan.md:105) | push missing | `origin/migrate-l-release-NIST-1-8-0` is at 876c8d6. af2ddda, 23f85dc (the δ references) and cc4485b (the journal) exist only locally |

**Overstated or missing in the journal**
1. **Journal:69 and :78.** "AC6b (s10) has not run" is false. AC6b passed in P01 (`evidence/ns3-scale-ten-gnbs/20261102T182547Z`, 13/13; plan phase table "AC6b ✓"). Its terms are in `plans/reports/probe-261103-0315-GH-1-m10-prelude-probes.md:47-51`:
   - 171 wall s per sim s;
   - AC15 simTime 8 s;
   - s10 ≈ 2,100 s;
   - host growth ≈ 0.7 GiB per 10-gNB run (at 4 sim s).

   What is still unrun is the AC15 *step* (P09). The stale text comes from plan.md:121 ("pending AC6b").
2. **Journal:64-67 and :72.** "So the 42 GiB base looks low for M10" is a non sequitur. See Q3.
3. **Journal:41-43.** The δ table leaves out the one outcome-relevant δ effect in R3′:
   - The predictor records equal M9's (`c94fef…`) at δ = 100, 150 and 200, but differ at δ = 500 (`fc5e84…`, `reference/r3p-d500/equal/files.json`).
   - The m1 record's answers move from 167,424 / 33,488 to 165,331 / 35,581 (live1 `r3p/predictor-records.jsonl`). The decision stays "none"; the margin drops from 5.0 : 1 to 4.65 : 1.
4. **Journal:24-25.** The seam smoke is RIC-free. Its stop-path FAILURE is judged at the ledger and ack level; the wire RICcontrolFailure is inferred, not observed (`phase-02-delta-actuation-seam.md:53`, against the Validation text at `:39`). Say so.
5. **Journal:109-110 (decision 4).** This is already pre-registered, not open. See Q4.
6. **Missing decision.** The /mnt/data 5 GiB floor is still "proposed, unconfirmed" (plan.md:323; `goal-packet.md:41`). The journal (:74) treats it as settled.
7. **Identity map (minor).** f5beca2 is a descendant of the tag, so `identity-map-cp1.json` is not in the `m10-cp1` tree. Phase-04 step 2b says "under the m10-cp1 tag". It can be rebuilt from the tag alone: the extractor (60a43f5) and the source trace (sha256 `d3dd93…`) are both in 83443e1's tree. One line in the journal settles this.

## Q2. Does "one control, all applied, no refused or late" weaken AC7, AC9 or AC16?

**AC9: not weakened.** The contract's AC9 asks for:
- a C1 and a sim-side reference per δ;
- apply − decision = δ on each applied line;
- HandoverStart at that time (I-2);
- at least one applied line per δ;
- a table.

All five are met. The refs also discriminate δ, because each δ has distinct ledger and ipc digests.

**AC7: the breadth is in the seam smoke, and that is enough for Stop A.** At the pins (25/25, `evidence/delta-seam-smoke/20261103T071157Z`) it covers:
- a refusal judged at apply time at δ = 150 and 500 (lteFallback, inHandover, unknownImsi, unknownTarget), with apply − rx = δ;
- the tie rule (d100tie);
- the event cancelled at the stop (d150stop);
- the queued late at the stop (d500stop);
- one δ-induced outcome change: IMSI 6's step-30 control is `alreadyOnTarget` at δ = 0 and 150 but `lteFallback` at δ = 500 (`runs/d{0,150,500}/trace/e2-control-ledger.jsonl`).

So the evidence that "δ can change outcomes" exists, but it is RIC-free and informational. It does not need a ruling. Record it in the table's text.

**Do not add a δ-sensitive schedule to the references.**
- It would edit R3′'s frozen scenario (phase-04:53), the AC19 step set and R-1, which would mean a contract change.
- In gated R3′ a late answer at the stop is impossible by design: `expect` requires late = 0, and the last apply is at step 35.

**Two real gaps (plan additions; no ruling, but disclose them):**
- **G1. The seam smoke is never re-run after P07.**
  - P07 owns `e2-control-hub.cc`, and the UE resolution there happens "in the apply event" (`phase-07:47`).
  - P07 validates only at δ = 0 (`phase-07:88`), and P11 bisects only at δ = 0 (`phase-11:22`).
  - My P02 carry ("add one δ = 500 dev case in P07", `kongming-261103-1210`, Q3) never landed.
  - The smoke's schedules address controls by IMSI and through the eNB or target (`scripts/probes/probe-delta-seam-smoke.sh:51-71`), which encodes P1 and P4. So it must be *migrated*, with a #9 row registered before P07 code, and then re-run at P07 exit and in P11.
  - Without that, after T-A nothing evidences AC7's tie and stop paths, or the apply-time resolution.
- **G2. AC16 has no cp2 baseline for the δ rungs.**
  - AC16 says that components not explained by a T-C fix "stay equal to checkpoint 2", and I-7 makes the δ refs C1 rungs.
  - But AC8b and P08 run only at δ = 0 (`phase-08:12,43`), so the cp3 δ diff would mix T-A and T-C.
  - The fix:
    - now: promote each δ ref's raw ledger and predictor records, as `m9-r3p-raw` was;
    - in P08: run d150 and d500 (d500 is the most δ-sensitive) with `--reference-transform` against the cp1 δ refs.
  - The cost is about 2 short runs.

## Q3. Budget: is the 52 GiB reasoning sound, and what should the user be asked?

**The sound part.**
- On the host, the 52 GiB is real: `du` of `/home/andang/VMs/ubuntu24.04-r2-green.1793678878` gives 52G, and `df -BG /home` shows 37G free.
- It is unlinked at the next revert, per `vm-orphan-overlays.sh --pending` at the start of the P04 chain (scratchpad `p04-chain.log:1`). That log is volatile; re-run `--pending` and keep its output in evidence.
- In-VM `used` grew only by 14 GiB. The recorded domain XML has `<driver name='qemu' type='qcow2'/>` with no `discard` attribute (`plans/261021-1823-…/evidence/m7/20261021T233129Z/snapshot-f7-rerun-green.xml`). So every cluster the guest ever writes stays in the overlay, and in-VM numbers must never feed T′.

**The unsound part.** The chain is not like-for-like with M9's m0–r3p:
- it contains M3, five C1s, two p12 runs and an M4 rebuild;
- it contains no m0–m2, i0 or i2.

M9's own free-series, sliced by step start times (`…/evidence/m9/20261028T165825Z/free-series.tsv` with `steps.tsv`), gives the per-step host drop:

| Step | GiB |
|---|---|
| m0 | 3 |
| **m1** | **13** |
| m2 | 0 |
| **m3** | **20** |
| m4 | 1 |
| m5–m7 | 0 |
| i0 | 3 |
| r0 | 0 |
| r1 | 1 |
| i2 | 0 |
| r2 | 0 |
| r3p | 1 |

So M3 alone is about half of M9's 42 GiB, and an M9 r3p C1 cost about 1 GiB.
- The P03/P04 window minus an M3-sized term leaves about 32 GiB over 14 runs, about 2.3 GiB per run. That is heavier than M9's rungs. It is evidence that N_new is uncertain, not that the base is low [I].
- On the M9 profile, N_new would be about 4–8 GiB [speculative]. On the P03/P04 rate it would be about 12–18 GiB.

**Today's Stop B projection.**
- Reachable after the next revert: 37 + 52 ≈ 89 GiB.
- Under the method base, the shortfall is 11–18 GiB. Under the measured base it is 0–5 GiB.
- So the base ruling is worth roughly 10–15 GiB that the user must free.

**What to ask the user now.**
- (a) No base ruling yet.
- (b) Approve the P11 measurement method:
  - at every step boundary of every rehearsal and of the cold i0/i2/m3 re-measures, record `df -BG /home` and the active overlay's allocated size (`du -B1` or `qemu-img info` actual-size);
  - at Stop B, compute T′_measured′ = 37 + (M9 per-step growth for the unchanged steps) + (P11 host measurements for the changed and new steps).

  A step measured from a fresh overlay roughly overstates its marginal cost inside a chain, so the sum is conservative [I].
- (c) Then rule at Stop B: max(method, measured′), or measured′ alone.

A lever exists if Stop B is short: `discard='unmap'` on the disk plus `fstrim` between steps. It is a host/VM configuration change, outside §3 unless the user rules it in, so I do not recommend it here.

## Q4. Decisions: recommendation and a one-line reason each

| # | Decision | Recommendation | Reason |
|---|---|---|---|
| 1 | Gap 5 (row 31) | **Option A** (the ns-3 emitter change) | It keeps the live failedOnBye path and removes the node-order asymmetry. Verified: `Stop()` calls `DeliverInbound()` before `OnEmitterStopping()` (`oran-interface/model/e2-ipc-emitter.cc:187-188` at b2342c6), and the hub answers `late` while `m_stopping` (`e2-control-hub.cc:196-199`). The R0 forcedLate (step 60) is mid-run, so it is unaffected. Re-run d150stop/d500stop after the change |
| 2 | Gap 15 (rows 43–45, 48) | **Option A, with the fail-fast header made required** (exit non-zero: "frozen at m10-cp1") | S0 V1/V3 are free-run (§3), none is in R-1, and successors exist at HEAD. A silent stale gate at HEAD is a trap. Exception: the δ seam smoke is *not* in this class; migrate it (G1) |
| 3 | M1 → P15 | **List it as P15 now and fix it in scope (Amendment 3), landed in T-C/P10. Exit to "record only" if a short scoping read at P05 shows the fix needs e2mgr RAN-function cell lists (the F7 limit)** | It is a live E2SM-KPM deviation on every indication: Format 1 is sent under the one Format 3 action (`code-reviewer-261103-1140…:36-42`). D3 set the precedent. Putting it in T-C keeps cp2's AC8b untouched and lets cp3 attribute the change. Cost: kpimon must add a Format 1 action for ns-3 nodes (its per-cell loop yields none today), the agent must route per action, and p12 must be re-baselined |
| 4 | d100/d200/d500 path | **No ruling: confirm the single-run gate** `gate-d-delta-identity.sh`, built and rehearsed in P11 before the tag | It is already pre-registered (plan.md:141, contract AC19 "short δ-identity runs" :125, phase-12:33-34). Running C1 instead contradicts "short" and adds about 2.7 ks to the step sum. The gate's predicates: one live run, δ and c checks, the δ-aware KPM move, late = 0, and `reference-compare` on ledger/ipc/traces against the cp3 sim-side ref. It gets its own ledger row ("new check") |
| 5 | T′ base | **Defer to Stop B; approve the P11 per-step host measurement now** | See Q3. The 52 GiB does not by itself show that the base is low |
| 6 | Confirm the 25 #9 rows | **Confirm.** Also confirm row 45 now: its new predicate is the same under gap-15 A and B, and only the runner differs | The counts and the re-grep check out. Add the missing seam-smoke row (G1) before P07 code |
| + | /mnt/data 5 GiB floor | **Confirm** | 20 GiB is free, and the archives are about 0.2 GiB per checkpoint |

## Q5. Fix before printing PAUSE A

**Must**
1. **Journal budget section** (:69, :78): replace "AC6b (s10) has not run" with the AC6b terms: s10 ≈ 2,100 s wall at simTime 8 s, and ≈ 0.7 GiB host per run at 4 sim s (`probe-261103-0315…:47-51`). The only terms still inferred are e2i, d* and p12. This is required by phase-04:12, "T′ and W′ with the AC6b numbers".
2. **Journal budget reasoning** (:64-67, :72): replace "the 42 GiB base looks low" with the Q3 reading:
   - the chain is not comparable (M3 ≈ 20 GiB of M9's 42 per M9's own series);
   - in-VM numbers understate growth (no discard);
   - per-step host growth for the new steps is unmeasured.

   Add the Stop B shortfall under each base (11–18 vs 0–5 GiB).
3. **Push** the harness branch after committing this note: three local commits, including the δ references. Then print the PAUSE line (plan.md:105).

**Should** (in the journal now, or at P05 start)
- S1. Table text: the δ = 500 predictor-record shift, and the smoke's δ = 500 outcome change (Q1 items 3 and 4).
- S2. State that the wire FAILURE at the stop is inferred (phase-02:53). Also state that rc never receives ACKs in this deployment (P01 AC6), so the δ runs do not exercise rc's 2 s timer.
- S3. Recast decision 4 as "confirm", and add the /mnt/data floor decision.
- S4. Disclose G1 (migrate and re-run the seam smoke at P07 and P11, with a #9 row before P07 code) and G2 (promote the δ raw files now; d150 and d500 transform-compares at P08).
- S5. From P05 on, write `df -BG /home` and the active overlay's `du` at every gate boundary in the chain scripts. P11 runs about 4 + 4 C1s, 7 rehearsals and 3 cold installs. At the P03/P04 rate one overlay would cross the 20 GiB dev floor from an 89 GiB start, so plan the revert boundaries.
- S6. Re-run `vm-orphan-overlays.sh --pending` (host, read-only) and keep its output in evidence for the "≈ 89 GiB after revert" claim.
- S7. One line each in the journal: the identity map is reproducible from the tag (Q1 item 7); 83443e1..876c8d6 touches only p12 files.

**Could**
- Add a one-line gist of each I-n to the journal.
- `agent-image.env`: either ask the user once for read approval at the Stop, or rename the recorded file at its source in P05 (for example `agent-image-id.txt`) so that provenance includes the agent image.
- The archive sizes mix MB and MiB (170.8 MiB and 77.9 MiB on disk).

## What to avoid
- Do not let the 52 GiB number drive the T′ ruling. It mixes M3, five C1s and a rebuild, and M9's own per-step series already gives a better prior.
- Do not "strengthen" AC9 by editing R3′ or adding steps. That is a contract change, for evidence the seam smoke already provides.
- Do not freeze the δ seam smoke with S0/S1. It is live AC7 evidence and must follow the hub through P07.

## Assumptions
- The domain disk still has no `discard` attribute (medium-high). I read it from Oct-21 evidence, not live. If discard is on, the in-VM vs host gap needs another explanation (churn would then be the qcow2 metadata or the backing chain).
- M9's per-step drops are attributed by evidence-directory start times (high). The free-series is in integer GiB (±1 per step).
- The P15 fix size (low confidence). It hinges on why kpimon's per-cell Format 1 loop yields no actions for ns-3 nodes, which I did not read. If it needs e2mgr cell lists, record-only is the better choice.
- N_new under either rate (low). This is speculative until P11 measures it.

## Unresolved questions
1. Why kpimon builds no Format 1 action for ns-3 nodes: is it the RAN function definition or e2mgr? This decides whether P15 is cheap.
2. Will the P11 rehearsals start from snapshots (isolated per step) or run as one chain? This changes how per-step growth is read.

Status: DONE
Summary: FIX-FIRST. Stop A's conditions are met and verified, including tags in all 5 repos, refs and the #9 counts. Before PAUSE A, fix the journal's budget section (AC6b did run; the 52 GiB does not show the 42 GiB base is low) and push. Gap 5 → A, gap 15 → A with a required header, P15 → fix in T-C, decision 4 is already pre-registered (single-run gate), and T′ is deferred with a per-step host-measurement method.

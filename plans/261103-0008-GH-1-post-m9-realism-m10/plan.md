---
title: "ns-O-RAN on the L-release RIC, M10: post-M9 realism (ops prelude, timing, E2 interop and identity, scale, radio and counter realism, M10 end run)"
description: "Fix P1–P13 and N5 to the O-RAN/3GPP specs behind three tagged checkpoints, then one unattended M10 run from fresh-install."
status: "ready rev 3 — contract A1 re-approved; warmup review rounds 1–2 complete; final summary confirmed 2026-11-03 ~02:25 KST (goal-packet.md)"
priority: P1
effort: "15 phases (P00–P13 incl. P06b); VM-sequential; wall and disk per the budget sketch"
branch: migrate-l-release-NIST-1-8-0
tags: [l-release, e2ap, e2sm-rc, e2sm-kpm, ns-3, m10, realism]
created: 2026-11-03
contract: plans/reports/contract-261103-0001-GH-1-post-m9-realism-outcome-contract.md (APPROVED; Amendment 1 re-approved 2026-11-03 01:10 KST; Amendment 2 2026-11-03 ~04:50 KST; Amendment 3 (P15) 2026-11-04 Stop A)
advice: --advice (kongming on Opus 5.5 at xhigh, model: opus; counsel never counts as user approval)
---

# Plan: M10, post-M9 realism on the L-release RIC

## Outcome (summary; the contract is authoritative)
On VM `ubuntu24.04`, land the ops prelude (MA), timing (MB), E2 interop/identity/control (MC), the 10-gNB scale gate (MD) and radio/counter realism (ME). Then M10: revert `fresh-install`, one unattended invocation, exit 0, the exact pre-registered step set (AC19). Three tagged checkpoints prove continuity with M9:
- literal M9 equality before any wire change (AC8);
- equality after T-A under pre-registered transforms (AC8b, as amended);
- new references with an explained diff after T-C (AC16).

After each checkpoint the compliant behaviour is the only behaviour (R1, R8). Every P1–P13 and N5 item ends fixed, or is listed only under an approved substitution (§7).

## Precedence of inputs
0. The contract, including Amendment 1 (AC8b, AC11, AC14, AC14b). An outcome or scope change is a Decision required (PAUSE T3).
1. Rulings R1–R12: `plans/reports/decisions-261102-2235-GH-1-post-m9-realism-user-rulings.md`.
2. Warmup review round 1:
   - `plans/reports/kongming-261103-0034-GH-1-m10-plan-review.md`;
   - Codex plan review run 1;
   - disposition in `reports/warmup-review-ledger.md` (written by the controller).
3. kongming go/no-go: `plans/reports/kongming-261029-1833-GH-1-post-m9-realism-brainstorm-go-no-go.md`; brainstorm §5–§7: `plans/reports/brainstorm-261029-1824-GH-1-post-m9-realism-goal-contract.md`.
4. Deviation table and A1 interpretations (a)–(k), ratified by R12: `plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md`.
5. Conventions carried from `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`: resume card, invariants, PAUSE lines, Failure Protocol, phase-exit checklist.

## Resume card (filled at execution; update before every VM operation > 10 min and at every phase exit)
```text
last-updated: 2026-11-04 06:40 KST
current phase: P05 DONE; next P06 (start with its "Hand-offs from the P05 exit review" section, then the AC18 rows, the S2 fail-fast headers, the Amendment 2 e2mgr patch and its dev route, the AC6a re-probe).
P02: DONE (AC8 run 1 ✓ evidence/r3p/20261103T024628Z; M4–M7 ✓; verdicts in 73068f1). kongming GO-WITH-CHANGES: KPM move judge δ-aware 281d709 (ledger row 56); seam smoke extended 1cf145f (d100tie, d150stop, pins + emitter SHAs) — run it via `vm-exec.sh probes/probe-delta-seam-smoke.sh` (08f72bc) after the P03 chain, before any P04 δ run. Exit record in phase-02.
P03: DONE (p12 ✓ 52/52, AC8 run 2 ✓ evidence/r3p/20261103T063029Z at 83443e1). kongming exit review GO-WITH-CHANGES (kongming-261103-1600): must = seam smoke at pins ✓ 25/25 (evidence/delta-seam-smoke/20261103T071157Z); shoulds done (rows 59 amended, 60 stricter p12 judge 1794f97; R-6 unit-test record evidence/p03-unit; standards ledger; raw archive). Exit record in phase-03.
AC18 #9: ledger rows 10–55 + 56 (119c91d, 281d709): 25 registered (P1/N5), 12 P5 held per D2 until the P06 AC6a re-probe, 5 pending Stop A rulings (gap 5 row 31, gap 15 rows 43–45, 48). Planner report planner-261103-1150 (NR-CGI APER = 9 octets; eNB meid enB_macro_001_001_000001 verified).
P04: DONE. m10-cp1 = 83443e1 (+ 4 fork pins), pushed. identity-map-cp1.json frozen f5beca2, NS_LOG cross-check ✓. δ refs reference/r3p-d{100,150,200,500} from C1 at 876c8d6 (176/176 each; 1 applied handover per live run; HandoverStart − apply = 3.0 ms all δ). p12 re-run with the stricter judge ✓. R-7 re-grep at 23f85dc: no rows 10–55 predicate moved. Raw archives m10-cp1 + m10-p04 on /mnt/data. Exit record in phase-04.
Stop A rulings (2026-11-04): S1 gap 5 = A (P07 emitter change); S2 gap 15 = A + required fail-fast header (P06); S3 P15 in scope, fix in P10, scoping read in P05, record-only exit only on the F7 limit; S4 d100/d200/d500 single-run gate confirmed; S5 T′ base deferred to Stop B + per-step host measurement from P05; S6 25 #9 rows + row 45 confirmed; S7 /mnt/data floor 5 GiB; G1 seam smoke migrated (#9 row before P07 code, re-run at P07 exit and P11); G2 δ raw promotion before P05 VM work, d150/d500 transform-compare in P08.
P05: DONE (AC11 dev form ✓: chain-2 GREEN 19:20–20:54Z at 9a95504, every node PPID 70 at every gate, r3p single equalsReference vs the M9/cp1 reference). Attempt 1 M5 red = stale HEAD-keyed agent image → fix 9a95504 (rows 64–65, kongming-261104-0410). Exit review GO-WITH-CHANGES (kongming-261104-0600): kpm_sim --source-ip (row 66, offline proof), S3 record corrected (eNB in P15; P10 decoder = P06 X2AP codec), P06 hand-offs written. Raw evidence archived (…-m10-p05-20261104.tar.zst).
VM / snapshots / host free: VM idle on the r3p-green overlay (20 GiB, unlinked at the next revert); snapshots fresh-install f7-rerun-green m0-probe-{d11021754,n,o,p,q} r0-green r2-green r3p-green; /home 68 GiB (≈ 88 after the next revert), /mnt/data 20 GiB
fork SHAs (pins.conf): Testbed d84068ca, ns-3 48d41a50, oran-interface b2342c66, e2sim e2705816 (cp1 pins: Testbed 809fb2d3, e2sim 2209995a)
checkpoint tags: m10-cp1 = 83443e1 (pushed, all 5 repos), m10-cp2 (none), m10-cp3 (none)
in-flight jobs: none
```

## Invariants card (never violate)
- Judge on decoded wire bytes, the ledger, ns-3 traces and digests; never on xApp logs. Never weaken, narrow or delete a check (AC18).
- No compat profile, legacy wire mode, legacy IMSI control mode or default-off switch whose default reproduces M9 (R1, R8). δ is a model parameter (AC7).
- No T-A code lands before tag `m10-cp1`; no T-C code lands before `m10-cp2`.
- Snapshots `fresh-install` and `f7-rerun-green` are never deleted; leaked overlays are deleted only under the 2026-10-28 ruling.
- Disk: ≥ 20 GiB free on /home in dev; end-run watchdog trip 37 GiB (h = 12, R11); /mnt/data per the budget line.
- Free run stays the ns-3 default; M5–M7 re-pass after every agent or ns-3 change.
- An xApp image is used only if it carries its pinned patch-set digest (stale-image guards for rc, kpimon and the TS xApp).
- Write "TS xApp" (the xApp) vs "3GPP TS <n>" (the spec). No secrets in any tree; the Influx token never leaves the cluster (T7).

## Phases

| # | Milestone | Phase | Exit gate | Status |
|---|---|---|---|---|
| P00 | MA | [Ops prelude: runner finish, overlay orphans, receiver readiness, headroom, FU4 note](phase-00-ops-prelude-runner-overlays-readiness-headroom.md) | AC1–AC5 | done 2026-11-03 (harness 6cc7798) |
| P01 | MA | [rc claims, identity probe, scale probe, ASN.1 toolchain, standards preflight](phase-01-rc-claims-identity-and-scale-probes.md) | AC6, AC6a, AC6b; F10/F11 preflight | AC6 ✓, AC6b ✓, F10 ✓ (static), F11 12/13 (T4 38.331); AC6a: eNB ✓, en-gNB refused by e2mgr 6.0.6 → PAUSE T3 → rulings D1–D4 (Amendment 2): e2mgr patch, AC6a en-gNB re-probe in P06 after cp1 | done 2026-11-03 (AC6a en-gNB carried to P06) |
| P02 | MB | [δ actuation seam](phase-02-delta-actuation-seam.md) | AC7; AC8 run 1 | done 2026-11-03 (AC8 run 1 ✓ r3p/20261103T024628Z; kongming GO-WITH-CHANGES; seam smoke re-run at the pins with the tie and stop cases before P04 δ runs) |
| P03 | MB | [P12: KPM reporting period and granularity](phase-03-p12-kpm-reporting-period-granularity.md) | AC10; AC8 run 2 | done 2026-11-03 (p12 ✓ 52/52; AC8 run 2 ✓ evidence/r3p/20261103T063029Z; cp1 = 83443e1) |
| P04 | MB | [Checkpoint 1 tag, δ sweep references, predicate registration](phase-04-checkpoint-1-tag-delta-references.md) | AC8 tag, AC9, AC18 #9 registration | done 2026-11-03 (m10-cp1 = 83443e1; δ refs 100/150/200/500; Stop A) |
| — | — | **Stop A** | user | ruled 2026-11-04 (S1–S7, G1, G2) |
| P05 | MC | [P10: SCTP PPID 70 on every E2 node (agents and kpm_sim)](phase-05-p10-sctp-ppid-70.md) | AC11 (dev form); P15 scoping read (S3) | done (AC11 dev ✓; P15 stays a fix) |
| P06 | MC | [Identity cluster: P11/N5/P2/P5/P8, N1, independent RIC control injector](phase-06-identity-cluster-gnb-id-nr-cgi-e2-setup.md) | AC12, AC13 | pending |
| P06b | MC | [P4 KPM UE IDs: X2AP context export, en-gNB-UEID/eNB-UEID in KPM, kpimon → Influx](phase-06b-kpm-ue-ids-x2ap-context-export.md) | AC14b (codec, context, Influx gates; R2/R3′ integration exits in P07) | pending |
| P07 | MC | [P4/P1/P13: Style 5 action 3 to the source en-gNB](phase-07-rc-style5-pscell-change-source-en-gnb.md) | AC14; AC14b integration (R2/R3′ green with the migrated UE-ID consumers); gap 5 option A (S1); seam smoke migrated and re-run (G1) | pending |
| P08 | MC | [Checkpoint 2: transform-compare, negative fixtures, tag](phase-08-checkpoint-2-transform-compare.md) | AC8b; d150 and d500 transform-compare against the cp1 δ references (G2) | pending |
| — | — | **Stop A′** | user | — |
| P09 | MD | [Scale gate, ≥ 10 gNBs](phase-09-scale-gate-ten-gnbs.md) | AC15 (cp2 pins; re-validated at cp3 in P11) | pending |
| P10 | ME | [T-C fixes P6/P7/P9 and the UseIdealRrc probe](phase-10-tc-counter-pdcp-realism-ideal-rrc.md) | AC16 (fixes), AC17; P15 fix (S3, Amendment 3) | pending |
| P11 | ME | [Checkpoint 3: rehearsals, Codex audit, new references incl. all δ, diff report, tag](phase-11-checkpoint-3-references-diff-report.md) | AC16 (checkpoint 3), AC9 re-bank, AC4 rehearsals; seam smoke re-run (G1); per-step host growth (S5) | pending |
| P12 | — | [M10 runner, check-diff ledger close-out, budget](phase-12-m10-runner-step-set-ledger-budget.md) | AC18, AC19 groundwork | pending |
| — | — | **Stop B** | user (disk ≥ T′) | — |
| P13 | — | [M10 end run and records](phase-13-m10-end-run-and-records.md) | AC19, AC11, AC2 post-run, AC20 | pending |

**Dependencies.**
- VM work is strictly sequential: P00 → P01 → … → P06 → P06b → P07 → … → P13.
- Code may be written ahead on fork branches, but no T-A code is pinned before `m10-cp1`, and no T-C code before `m10-cp2`.
- P06b needs P06 (meids, eNB Global ID, the injector).
- P07 needs P06b's **codec, context and Influx exit**: the TS xApp reads the UE ID from Influx (AC14).
- **P06b + P07 form one integration boundary for R2/R3′** (Codex round 2 #2). P06b does not run R2/R3′ as its exit, because the TS xApp keeps `stoi(ue_id)` until P07. R2/R3′ go green only after P07's consumer migration: the TS xApp, `r3p-prepare.py`, `r3p-schedules.py`, the stub and the pacer. No pin between P06b and P07 is used for a rung run.
- P09 needs P07 (an applied PSCell change).
- P11 needs P10. P12 is runner-only and needs the references P11 tags. P13 needs Stop B.

**File ownership.** Phases run in sequence; hot files and the phases that own them:
- `oran-interface/model/e2-control-hub.cc`: P02, P07.
- `oran-interface/model/e2-ipc-emitter.cc`: P06b.
- `ns3_e2_agent/src/e2ap-builders.cpp`: P03, P06.
- `ns3_e2_agent/src/sample-forwarder.cpp`: P03, P06b.
- `scripts/run-to-m9.sh`: P00, P12.
- `install_patch_files/xApps/kpimon-go/*`: P03, P06, P06b.
- `install_patch_files/xApps/ts/*` and `scripts/gates/ts-lib.sh`: P06, P07.
- `scripts/gates/pacer.py`: P02, P07.
- `scripts/gates/r3p-checks.py`: P02, P07, P10.
- `tools/e2-evidence/wire-c1-extract.py`: P06, P07.

## Stops and pause triggers
The mechanism is the same as M8–M9: a journal in `docs/journals/`, a kongming note, a resume-card update and a push, then one terminal line `PAUSE <id> evidence=<path> journal=<path>`. T1–T9 keep their M8–M9 meanings. T3 also covers every contract "Decision required": an AC6a refusal, AC14 finding no X2AP-type UE ID, or an FU5 burst over 12 GiB.
- **Stop A** (after P04):
  - checkpoint 1 tagged and the δ references banked;
  - the AC18 #9 rewrites registered for user confirmation;
  - the interpretations below listed in the journal;
  - T′ re-projected under both bases (budget).
- **Stop A′** (after P08):
  - checkpoint 2 tagged;
  - the F2 X2 message mapping (I-1) shown;
  - scale and T-C cost re-projected.
- **Stop B** (after P12): M10 starts only when `df -BG /home` ≥ T′ and the /mnt/data line holds. The user frees any shortfall; nothing is deleted autonomously beyond the 2026-10-28 ruling.

## Budget sketch (re-projected at Stop A, Stop A′ and Stop B)
- **Disk, /home (end run):** T′ = max(T′_method, T′_measured).
  - T′_method = (25 + h) + M0–M7 + R section + N_new = 37 + 43 + 12 + N_new [method `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md:43`].
  - T′_measured = 37 + 42 + N_new. The 42 GiB is M9's measured consumption, 101 → 59 GiB [V `…/evidence/m9/20261028T165825Z/free-series.tsv`].
  - N_new is the growth of the new steps (e2i, d150, d100/d200/d500, s10, p12). It is inferred at 8–15 GiB [I] and is **pending AC6b** and the P11 rehearsals.
  - With today's numbers T′_method ≈ 100–107 GiB is the binding value and T′_measured ≈ 87–94 GiB the lower reference. The user may rule which base applies (flagged at Stop A, decided at Stop B).
  - **Stop A ruling S5 (2026-11-04):** the base is decided at Stop B. From P05 on, every chain script records `df -BG /home` and the active overlay's allocated size (`du -BG <overlay>`, allocated blocks, not apparent size) at every gate boundary. At Stop B, T′_measured′ = 37 + M9's per-step growth for unchanged steps + the P11 host measurements for changed or new steps; the user rules max(T′_method, T′_measured′) or T′_measured′ alone. Plan the revert points so P11 stays above the 20 GiB dev floor.
  - Reachable: 54 GiB free now plus about 42 GiB of the post-M9 overlay leak ≈ 96 GiB [kongming §4]. Expect a shortfall that the user frees.
  - **Update 2026-11-03 (P00):** the post-M9 leak `ubuntu24.1793206761` was deleted under the 2026-10-28 ruling (42.4 GiB freed; log `evidence/fu2/20261102T174920Z/leak-deletion/`, kept in this plan instead of the M8–M9 `p10-disk/` folder the ruling names). /home is now 96 GiB free, which is the "reachable" figure above.
- **Disk, /mnt/data:** 20 GiB free, 91 % used [V `df`]. It holds rootless podman storage (new images: `asn1-indep`, the protoc containers) and the raw-evidence archive (M9's evidence was 5.8 GB).
  - Every phase records `df -BG /mnt/data`.
  - Only images this plan built may be pruned.
  - If a new image or archive copy would leave < 5 GiB, that is PAUSE T2 (floor confirmed at Stop A, ruling S7).
- **Watchdog:** h = 12 GiB, trip 37 GiB (R11). `disk-burst-h.py` must confirm no measured 370 s burst exceeds 12, else Decision required.
- **Wall:** W′ = ceil(1.5 × Σ longest green per step).
  - The M9 green run took 12,584 s, and the M9 budget sum is 13,466 s (`m9-budget.md:28`).
  - New steps [I]: e2i ~600 s, d150 ~1,300 s, three δ-identity runs ~1,350 s, s10 ≤ 2,700 s, p12 ~600 s. So W′ ≈ 27–31 ks.
  - Cold i0, i2 and m3 are re-measured with the patched builds (rc, TS xApp, kpimon) in the P11 rehearsals. The s10 term is pending AC6b.
  - One `systemd-run --user --wait` invocation, as M9.

## Pre-registrations (fixed before code; changing one after its phase starts is PAUSE T3)

**R-1. M10 step set and order (AC19).** `m0 m1 m2 m3 m4 m5 m6 m7 i0 r0 r1 i2 r2 r3p e2i d150 d100 d200 d500 s10 p12`.
- m0–r3p are the M9 steps: r0, r1 and r2 run `--mode single`; r3p runs `--mode c1 --reference <cp3 r3p>` at δ = 0.
- `e2i` is the E2-interop step: AC11 per E2 node, AC12, AC13 and the AC14 negatives. It sends through the independent injector with the TS xApp down.
- `d150` is a full R3′ C1 at δ = 150 ms against its cp3 reference. `d100`, `d200` and `d500` are one live run each, checked against their cp3 sim-side references:
  - `applySimTimeNs − rxSimTimeNs = δ` on every applied line;
  - HandoverStart − applySimTimeNs = c (I-2);
  - at least one applied control.
- `s10` is the scale step (AC15), with simTime from AC6b.
- `p12` runs last, because it changes kpimon's subscription globally. It restores 100/100 at its end, and every rung also asserts that the decoded subscription period is 100 ms.
- Verdict: `exactStepSet: true`, every step green, exit 0, `minHostFreeGb ≥ 25`, the watchdog never trips (37), rc RestartCount 0.

**R-2. AC8b transforms (A1; enumerated; any other differing byte fails).**
- **Literal:** ipc (the digested `sample` lines, `scripts/gates/digest-run.py`) and traces. kpm-headers and collet-start-time are also kept literal [I: no enumerated field touches them].
- **Ledger:** `viaNodeId` changes from M9's target node to the line's `sourceCell` (P1). `imsi` stays literal, because ns-3 resolves it (R-4).
- **rc-multiset:**
  - `viaNode` (P1);
  - `imsi` → `ueId` per R-4 (P4), using the **frozen cp1 identity map** (R-8). The M9 entry `"imsi": 1` becomes `"ueId": {"type": "en-gNB-UEID", "mEnbUeX2apId": 3, "globalEnbId": {"plmn": "00F110", "macroEnbId": "00001"}}`. That is exactly the representation the migrated `wire-c1-extract.py` writes; no other key changes;
  - `style`/`action` 3/1 → 5/3 (P13);
  - `targetKey` → the NCI key (P11/N5).
- **meid:** `gnb_001_001_%08x` → `en_gnb_001_001_%08x` for the gNBs, and the eNB → `enB_macro_001_001_000001` (macro eNB ID 1, 20 bits; e2term renders the bit string right-aligned, 2 hex per octet [V ric-plt-e2 `BuildRunName.h:56-118,190-192`]; AC6a: 0xFFFFE → `enB_macro_001_001_0ffffe` [V `evidence/e2-identity-setup/20261102T192656Z/`]).
- **Scenario, schedule and predictor records = T(M9 files)** (A1, F1 option a). T is pure and pre-registered:
  - N5 key → NCI key (`%08X%02X` → `%08X` + `1` + `0`) on key-valued fields only: `r3p-scenario.json:5`; `r3p-schedule.json:10,17,33,40,48,58,65`; the predictor records' `answer` keys and `target`.
  - Schedule `via` (`r3p-schedule.json:52`): target → the source cell, taken from the M9 ledger line's `sourceCell`.
  - `scenarioSha256` (`r3p-schedule.json:2`): recomputed from T(scenario).
  - The two P1 description strings (`r3p-scenario.json:27` "via the target gNB (deviation P1)", and the schedule/fixture text that names P1) are replaced by registered text: "via the source en-gNB (SN-initiated, E2SM-RC Style 5 action 3)".
  - `ueId` (`r3p-scenario.json:17`, "decimal IMSI string") → "the KPM UE ID key of AC14b (en-gNB-UEID)".
  - `r3p-stage-a.json` (the committed stage-A classification): key-valued fields `:15,22,30,40,47` by the same key rule; `h1.via` (`:34`) target → the M9 ledger line's `sourceCell`; `scenarioSha256` (`:58`) recomputed from T(scenario); everything else literal (incl. `stageDir`).
  - Everything else stays literal: IMSIs, steps, decisions, windows and every predictor number.

**R-3. Identity layout (R5, I-6).**
- gNB ID: 32 bits = the ns-3 cellId [V `ns3_e2_agent/src/agent-config.hpp:19`]. PLMN 001/01, BCD `00F110` [V `:17`].
- NR Cell Identity = gNB ID (32 bits) ‖ cell part (4 bits); the cell part is 1 for every gNB.
- TS xApp key: `%08X10` (gNB 2 → `0000000210`). It is the 9-hex NCI plus the APER pad digit (the take is at `ts_xapp.cpp:366`).
- meid: `en_gnb_001_001_%08x`; e2mgr `nbId` is 32 binary characters.
- eNB meid: `enB_macro_001_001_000001` (see R-2).
- Target NR CGI (RAN parameter 4 `valueOctS`) = APER NR-CGI, 9 octets: `00` ‖ `00F110` ‖ NCI (36 bits) ‖ 4 zero pad bits; gNB 2 → `0000F1100000000210` [V pycrate, image `asn1-indep`]. The TS key is its last 10 hex digits; rc's gRPC `TargetCellID` is that key. The N5 form `0000F110`‖`%08X%02X` re-encodes differently (nonzero pad) for every cell ≠ 0x10.
- The agent's internal sample `kind` stays `gnb`/`enb`, because `metric-map.cpp:76` and the hello check at `sample-forwarder.cpp:41` key on it. The wire identity is derived from the kind: `gnb` → Global en-gNB ID (scenario-zero is EN-DC only); `enb` → Global ENB ID, macro eNB ID (20 bits) = LTE cellId 1.
- AC6a probe IDs: gNB IDs 0x7F000001 and up, macro eNB 0xFFFFE. They cannot collide with ns-3 cellIds (≤ 86), and the VM is reverted after the probe.
- **X2AP constants (served cell info, I-5):**
  - NR PCI = cellId; TAC `000001`; broadcast PLMN `00F110`;
  - `nrModeInfo` TDD, NR-ARFCN 633333 (3.5 GHz), band n78, transmission bandwidth for 20 MHz at 30 kHz SCS;
  - `measurementTimingConfiguration` (mandatory [V `oran-e2sim/e2sim/previous/ASN1c/ServedNRCell-Information.h`]) is a valid 3GPP TS 38.331 `MeasurementTimingConfiguration` (SSB at the same ARFCN, 20 ms periodicity);
  - eNB served E-UTRA cell: PCI = 1, TAC `000001`, EARFCN per the ns-3 LTE config [I].
  - All values are [I] until cited in P06's ledger. P06 also confirms, from E2AP v03.00 §9.2.27, whether the request part is the whole X2AP-PDU or only the message.

**R-4. UE IDs (AC14, AC14b).**
- **RC UE ID: en-gNB-UEID** [V `ric-app-rc/e2sm/e2sm-common.asn:235-245`]:
  - `m-eNB-UE-X2AP-ID` = the MN's LTE RNTI. ns-3 holds it at the en-gNB [V `ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:570`, `:1482`; `epc-x2-sap.h:241`; X2AP UE ID = sender RNTI `:726`]. The range is 0..4095 [V `e2sm-common.asn:331`].
  - `globalENB-ID` = {`00F110`, macro eNB ID = MN cellId} [V `:1479`].
  - Optional fields are absent.
- **KPM UE IDs (AC14b):**
  - The en-gNB agents report the same en-gNB-UEID.
  - The eNB agent reports eNB-UEID [V `e2sm-common.asn:247-256`]: `mME-UE-S1AP-ID` = ns-3's `mmeUeS1apId`, which ns-3 sets to the IMSI [V `epc-mme-application.cc:111`, `lte-enb-rrc.cc:730`] (disclosed); `gUMMEI` = {`00F110`, MME group 1, MME code 1} [I]; `m-eNB-UE-X2AP-ID` = the LTE RNTI (present because DC is established, `:250-251`); `globalENB-ID` absent ("reported only by SeNB").
  - No IMSI is carried as a gNB-UEID.
- **Context channel:** ns-3 sends a new IPC line type `ueContext` {nodeId, seq, ues: [{imsi, lteRnti, mnCellId, mmeUeS1apId}]} on the existing per-node TCP connection.
  - It is sent before the sample of a seq whenever the context changes (attach, SN change).
  - It is written to a separate file, `e2-ue-context-<node>.jsonl`. `e2-ipc-trace-<node>.jsonl` and its sample lines stay byte-identical (I-8).
  - The IMSI stays inside the IPC; the agent uses it only to map sample UEs to their IDs.
- **Influx UE key:** kpimon stores the decoded UE ID as tag `ueId` = `enGnbUeId:<x2apId>@<plmn>-<macroEnbId hex>` (eNB rows: `enbUeId:<mmeUeS1apId>@<x2apId>`) [I, format pre-registered here].
  - The AD stand-in (`send-rmr.sh anomaly`) names the UE by that key, read from Influx.
  - The TS xApp reads the UE's latest row by key from Influx (serving cell and ID fields) to build the control.
  - The R3′ predictor and the stub map the key back to the IMSI through the run's `e2-ue-context-*.jsonl` (harness side), so the predictor records keep `imsi`.
- **Resolution in ns-3:**
  - The source SN finds the UeManager whose stored `lteRnti` and MN cell match, and checks that it is the UE's **current** SN (not a stale `RlcBearerInfo`). Otherwise the line is refused `unknownUe`, with `imsi` 0 (ns-3 IMSIs start at 1).
  - The hub resolves every control before the batch sort, so the sort key `(imsi, viaNodeId, targetCellId, ctlId)` (`e2-control-hub.cc:247-250`) uses the resolved IMSI.

**R-5. δ and the ledger (AC7, AC9; I-2, I-3).**
- Attribute `ns3::E2ControlHub::ActuationDelay` (Time, default 0).
- Ledger header `"delta-model":"fixed <δ ms>"`; it stays `"fixed 0"` at δ = 0 [V `e2-control-hub.cc:356`].
- `decisionSimTimeNs` := `rxSimTimeNs` [V `:285-286`]; no new field at any δ.
- **Tie rule:**
  - If δ is a multiple of T, the batch is not scheduled as an event. It is queued to barrier k + δ/T and applied there, after that seq's samples were emitted and before that barrier's own batch.
  - Otherwise (δ = 150) one event is scheduled at t_k + δ.
  - A self-test covers both cases.

**R-6. KPM period (AC10).**
- T = ns-3 `indicationPeriodicity` = 100 ms; gated rungs use 100/100 ms.
- P12 tests:
  - G = 100, P = 1,000 → 10 records per indication;
  - P = 150 → a RIC SUBSCRIPTION FAILURE, because the period sits in the event trigger, which applies to the whole subscription. **Cause (pre-registered 2026-11-03 before P03 code): `ricRequest` / `eventTriggerNotSupported`** [V E2AP v03.00 §8.2.1.4 ("RIC Subscription Details IE that does not align with the Near-RT RIC Service Model → RIC SUBSCRIPTION FAILURE with an appropriate cause value", Zotero `WEE5IEXF` p. 17) and §9.2.1 cause table "Event Trigger not supported: Requested event trigger definition or modification not supported" (p. 62); the value exists in the agent's E2AP v03.01 ASN.1 (`CauseRICrequest`, extension `eventTriggerNotSupported`)].
  - An action whose granularity ≠ T (period admitted) is not admitted with `ricRequest` / `action-not-supported` (§9.2.1), in a RIC SUBSCRIPTION RESPONSE that admits the other actions; with no action left, RIC SUBSCRIPTION FAILURE with the same cause.

**R-7. Check-diff ledger seed (AC18).** `check-diff-ledger.md` in this plan dir has one row per changed check: old → new, why it is not weaker, and a contract-change flag. P1/P5/N5 rows are registered at Stop A. The sites, re-grepped at P04 start:
- **P1:** `scripts/gates/r3p-checks.py:17,73,203-207,270`; `r0-checks.py:18-19,71,89-99`; `r2-checks.py:15-18,23-24,56,96,179-185`; `gate-r3p-ts-predictor.sh:240,246`; `gate-r2-ts-stub-qp.sh:121,135-137`; `gate-r0-rc-scripted.sh:238-253`; `gate-r1-rc-multi-control.sh:109,252-295`; `r0/r1/r2-scenario.json` via fields; `r3p-stage-a.json:34`; `r3p-dry-run-classifier.py:76-81`; `r3p-schedules.py:9,57-58`; `r3p-checks-fixtures.py:3,16,56,59,89,91,106,120,121`; `r3p-dry-run-fixtures.py:33-35`; `wire-c1-extract.py:178-185,230,296`.
- **R1 addressing (source-aware replacements in P07):** `gate-r1-rc-multi-control.sh:252-267`:
  - C4 (b): a same-step pair for IMSI 2 through one node; the hub sort `(imsi, viaNodeId, targetCellId, ctlId)` [V `oran-interface/model/e2-control-hub.cc:247-250`] applies the **higher-ctlId, lower-target** control first, and the lower-ctlId one is refused `inHandover`;
  - C4 (c): arrival order [3,2] across two agents;
  - `:276-295` fault-stop via agent 1, `failedOnBye == 1`.
- **P5/N5 meids and keys:** `gate-m5-agent-setup.sh:25`; `gate-r0-rc-scripted.sh:150-152`; `rc-send.sh:6,12`; `rc-lib.sh:243-248`; the whole of `replay-ts-cell-map.py`; `gate-s0-free-control.sh:177,184`; `gate-q8-rc-smoke.sh:69-70`; `probes/probe-rc-control-latency.sh:89`; `r2-checks.py:53`; `r3p-predictor.py:7,106,154`; `r3p-checks.py:60`; the scenario/schedule/stage JSONs; `tools/rmr-peer/rmr-peer-selftest.py:76-142`; `tools/e2-evidence/recovery-eval.py:6,26`; `selftest.sh:109,124,127-128`; `e2ap-pcap-facts.py:84-87`; `e2-facts-query.py:26,45-70,186-189`; `gate-m5-agent-setup.sh:97-98`; Testbed `run_ns3_e2_agents.sh:86-96`; `tools/rc-decode/fixtures/*`; `test-rc-decode.sh`; `asn1-indep/selftest_kpm_and_fixtures.py:13-19,85-93`; `rc-control-test.cpp:176-205`; `ts-rung-lib.sh:208-221`. S0, S1 and the probe: per the gap-15 ruling at Stop A (`check-diff-ledger.md` rows 43–45, 48).
- **P5 node type:** `agents.sh:128-160`; `agents-ns3-run.sh:215-224`.
- **P4 (UE IDs):** `tools/e2-evidence/kpm-ue-list-moves.py:55`; `tools/kpimon-decode-harness/kpimon-decode-harness-records.c:51`; `tools/e2-evidence/wire-c1-extract.py:230`; the r3p stub check "decimal IMSI"; the R1 unknown-IMSI case.
- **Replay:** `pacer.py:63-77` (rebuilds controls from the ledger IMSI) and `ts-rung-lib.sh:169` (replay in C1).
- **R3′ preparation (Codex round 2 #1, migrated in P07):**
  - `scripts/gates/r3p-prepare.py:48` (the stub load must answer `{"ues": [str(imsi)]}`) and `:74-79` (calibration builds an IMSI-keyed `{"predictions": {str(imsi): …}}`);
  - `scripts/gates/r3p-schedules.py:31-32` (decimal IMSI anomaly trigger) and `:57` (stage-B injection with the removed `{nodeId: via, imsi}` control schema, via the target).
- **TS patch validation:** `ts-lib.sh:57-58` (list of exactly two patches) and `:98-112` (`ts_patches_check`, one file).
- **Readiness:** `rc-lib.sh:111,123`.

**R-8. Frozen cp1 identity map (source for R-2's RC UE ID transform; Codex round 2 #4).**
- **Source:** independent of the new wire output. It is derived from ns-3's own trace `DlE2PdcpStatsLte.txt` (columns `CellId IMSI RNTI`; the MN's PDCP per UE) of the committed M9/cp1 r3p live1 run. That file is in the literal `traces` component, so it stays valid through cp2.
- **Example (M9 live1, `CellId 1`):** IMSI 1 → 3, 2 → 4, 3 → 1, 4 → 2, 5 → 5, 6 → 6 [V `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r3p/20261028T044557Z/runs/live1/ns3run/DlE2PdcpStatsLte.txt`].
- **Freeze at P04 (cp1):**
  - `reference/identity-map-cp1.json` = `{"source": "<path>@<cp1 sha>", "sourceSha256": …, "mnCellId": 1, "globalEnbId": {"plmn": "00F110", "macroEnbId": "00001"}, "ues": {"<imsi>": {"mEnbUeX2apId": <LTE RNTI>}}}`, with its sha256 in `reference/SHA256SUMS`;
  - the extraction script asserts one RNTI per IMSI on the MN cell for the whole run;
  - a cross-check against an ns-3 dump at the cp1 commit (a run with `NS_LOG` UE-context output) must agree.
- **Transform input and output:** an M9 rc-multiset entry `{…, "imsi": N, …}` becomes the same entry with `imsi` removed and `ueId` set per R-2's representation from `ues[N]`. M9 meids map per R-2.
- **Live cross-check (P06b):** every run's `e2-ue-context-*.jsonl` `lteRnti` equals the frozen map for the same IMSI.

## Interpretations (no ruling needed; listed in the Stop A journal)
- **I-1 (F2).** The SN-initiated SN change is an in-process, zero-latency call at the source SN. Mapping disclosed in P07's standards ledger and shown at Stop A′:
  - the in-process call ≈ SgNB Change Required;
  - MN → S-SN `McHandoverRequest` ≈ SgNB Change Confirm;
  - ns-3's SN↔SN X2 leg is not 3GPP TS 37.340 §10.5.1 message by message.
- **I-2 (F3).** On every applied line at every δ, HandoverStart − applySimTimeNs = c, with c = 3.0 ms registered from the M9 reference (ledger `3000800000` vs `EnbHandoverStartStats.txt` 3.0038) at the trace's 0.1 ms resolution.
- **I-3 (F4).** AC9's `decisionSimTimeNs` is the ledger's `rxSimTimeNs`.
- **I-4 (F6).** The Style 5 action 3 RAN parameter IDs come from E2SM-RC v01.03 (`PSHY8566`) and v03.00 (`JRDTL7XS`) §8.4.6.3. The tables are identical in both: 1 Target PSCell ID, 2 CHOICE Target Cell, 3 NR Cell, 4 NR CGI, 7 Secondary Node ID, … 15–17 en-gNB (kongming, PDF pp. 180/183).
  - rc's `e2sm-rc-2.0.asn` sits between the two versions.
  - §8 is read from the PDF (`pdftotext -layout`), not the truncated `.zotero-ft-cache`.
  - Control Outcome Format 1 with no item stays valid (§7.6.6.5).
- **I-5 (F8).** The eNB sends an init-eNB `ENDCX2SetupRequest` (served E-UTRA cells) as its request part. The e2i verdict has an eNB row.
- **I-6 (F9).** Cell part = 1, so a decode test can tell cell bits from padding.
- **I-7 (AC16).** The four δ references count as C1 rungs. All four are re-banked at cp3 (P11), and the P04 ones stay in git as history.
- **I-8 (AC14b).** "Existing IPC trace files literal" is read as: `e2-ipc-trace-<node>.jsonl` gets no new line type, and the digested sample lines stay byte-identical. The `controlAck` lines in that file already change with P1 (`nodeId`), which AC8b allows, since ipc = sample lines.
- **I-9 (AC11).** kpm_sim is built from OSC `sim/e2-interface` by the Testbed (`install_scripts/install_e2sim.sh:49-59`), whose `send()` is at `sim-e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp:235`. The contract cites the wineslab fork (`oran-e2sim/e2sim/src/SCTP/e2sim_sctp.cpp:228`, pin `E2SIM_SHA`), which kpm_sim does not use.
  - The pinned patch is delivered as a Testbed `install_patch_files/e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp` copy (pinned by `TESTBED_SHA`).
  - The wineslab fork gets the same one-line fix so that both cited trees agree.

## Traceability

| Phase | Contract items | Acceptance signals | Facts / assumptions / prereqs / user decisions |
|---|---|---|---|
| P00 | §2 MA; §5 disk, snapshots | AC1 self-test; AC2 zero orphans; AC3 stuck-reader fixture fails; AC4 h script; AC5 note | [V] `scripts/run-to-m9.sh:122`, `:131`; [V] `gate-m0-host.sh:46-52`; [V] `rc-lib.sh:111,123` (callers `gate-i2-ts-xapp-install.sh:69`, `ts-rung-lib.sh:58`); [V] `bringup.sh:227`; [V] four M9 `free-series.tsv`; [U] R11 |
| P01 | §2 MA probes; §4 AC6, AC6a, AC6b | AC6 file:line; AC6a meids, nodeb JSON incl. eNB without `ranFunctions`, one KPM subscription to the eNB node; AC6b rate and GiB from a dedicated 10-gNB probe; F10/F11 preflight | [V] rc `rcE2SmRc.go:134`, `rcControl.go:156-197`, `config.json:72`; [V] `BuildRunName.h:120-200`; [V] e2mgr 6.0.6 (`reference/r3p/recorded/deployed-image-ids.json:43`) stores RAN functions for gNB only [kongming §1 F7]; [V] `measure-ns3-timing.sh:35-41` accepts only `--repeats`/`--simtime`; [P] Zotero: 3GPP TS 38.323 `MSNDDXJH`, 3GPP TS 36.423 `3ML7Y29A`, 28.552 presence |
| P02 | §2 T-B P3 | AC7; AC8 (run 1) | [V] `e2-control-hub.cc:243-275`, `:285-288`, `:356`, `:380-415`; [V] `scenario-zero.cc:420-432`; [I] R-5 tie rule |
| P03 | §2 T-B P12 | AC10; AC8 (run 2) | [V] `control.go.previous:437`, `wrapper.c.patch:401`; [V] `e2-session.cpp:150-174`, `sample-forwarder.cpp:69`, `e2ap-builders.cpp:125`; [U] SUB-P12; [I] R-6 failure cause |
| P04 | §1 checkpoint 1; Stop A | AC8 tag; AC9 sweep and refs; AC18 #9; R-8 identity map frozen and checksummed | [V] `DlE2PdcpStatsLte.txt` CellId/IMSI/RNTI in M9 live1; [V] M9 ref `plans/261023-0009-…/reference/r3p/equal/`; [V] raw live1 on host; [I] I-2 constant c; [U] R1 |
| P05 | §2 T-A P10, e2sim patch | AC11 (dev) | [V] `ns3_e2_agent/src/sctp-association.cpp:147`; [V] kpm_sim `send()` `sim-e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp:235`; [U] A1 AC11; [I] I-9 |
| P06 | §2 T-A P11/N5/P2/P5/P8, N1 | AC12 (strict NR-CGI); AC13 (en-gNB and eNB rows); AC14 negatives via the injector | [V] `e2ap-builders.cpp:61-114`; [V] `rc-control.cpp:25-33`; [V] `ts_xapp.cpp:335-372,639-643,890`; [V] `ts-lib.sh:57-58,98-112`; [V] `metric-map.cpp:76`, `sample-forwarder.cpp:41`; [V] rmr-peer routes TS-only (`tools/rmr-peer/xapp-descriptor/config-file.json:26-27`); [V] legacy X2AP asn1c; [I] R-3 X2AP constants; [U] R5 |
| P06b | §2 fork patches (kpimon UE ID); P4 KPM half | AC14b codec, context and Influx gates (R2/R3′ integration in P07) | [U] A1 AC14b; [V] `e2-ipc-emitter.cc:153-155` (`SendLine` writes the ipc trace); [V] `kpm-ue-list-moves.py:55`; [V] `epc-mme-application.cc:111`, `lte-enb-rrc.cc:570,730,1482`; [V] `e2sm-common.asn:235-256`; [I] R-4 Influx key; [P] Influx read access for the TS xApp without a token in git (T7) |
| P07 | §2 T-A P4/P1/P13 | AC14; AC14b integration: R2/R3′ green, R3′ live prepare, calibration and stage-B injection with migrated UE IDs | [U] R6, R7, R10, A1 AC14; [V] `rcService.go:35` (`GnbUEID.Guami` deref) with `rc.pb.go:151` (pointer); [V] `rc.pb.h:11` (protoc 3.6.1); [V] `rc-lib.sh:47,126` (source-only pin check); [V] `pacer.py:63-77`, `ts-rung-lib.sh:169`; [V] `gate-r1-rc-multi-control.sh:249-256,275-290`; [V] ns-3 hook `lte-enb-rrc.cc:4556-4608,5129-5137`; [I] I-1, I-4 |
| P08 | §1 checkpoint 2; SUB-1; Stop A′ | AC8b (A1), incl. RC UE-ID transform from R-8 with wrong-X2AP-ID and wrong-Global-ENB-ID negatives | [V] `r3p-scenario.json:5,17,27`, `r3p-schedule.json:2,48,52`; [V] M9 `files.json`; [U] A1 F1 option a |
| P09 | §2 MD | AC15 | [V] `mmwave-enb-net-device.h:71`; [V] `scenario-zero.cc:283,540-544`; [V] TS cell map built at start `ts_xapp.cpp:890`; [I] simTime from AC6b |
| P10 | §2 T-C P6/P7/P9, UseIdealRrc; R8 | AC16 fixes; AC17 | [V] P6 `mmwave-indication-message-helper.cc:132`, `metric-map.v1.json:33`; [V] P7 every `LtePdcpHeader` consumer: `mc-enb-pdcp.cc:247,313`, `mc-ue-pdcp.cc:197,258`, `lte-ue-rrc.cc:1700,1759,1829`, `lte-enb-rrc.cc:1034,1091,1176`, `lte-rlc-am.cc:1801`, `lte-pdcp.cc:180,221`, `mmwave-enb-net-device.cc:658`; [V] P9 `mmwave-enb-net-device.cc:653-689`; [V] `scenario-zero.cc:483`; [U] S-R, open point 2 |
| P11 | §1 checkpoint 3 | AC16 refs, diff, tag; AC9 re-bank of all four δ; AC4 rehearsals; s10 at cp3 pins; Codex pre-ship audit | [I] I-7; [V] `reference-compare.py:42-48`; [U] R3 (Codex, no cap) |
| P12 | §2 runner | AC18 complete; AC19 runner, budget, self-test | [V] `run-to-m9.sh:70-90`, `m9-verdict.py:39-86`, `m9-budget.json` |
| P13 | §1 outcome; Stop B | AC19 run; AC11 on every end-run capture per E2 node; AC2 post-run; AC20 records | [V] M9 launch route (README:51); [P] /home ≥ T′, /mnt/data line |
| all | §5 standards | standards ledger per phase; journals at Stops; handoff | Zotero: OAD v18 `TBVJDMLF`, E2GAP v08 `AE3NUEDK`, KPM v03.00 `F82PYZVK`, E2SM-RC v03.00 `JRDTL7XS` and v01.03 `PSHY8566`, 3GPP TS 37.340 `E6VYJPXJ`, 3GPP TS 38.300 `PSYCJSXT`, 3GPP TS 38.323 `MSNDDXJH`, 3GPP TS 36.423 `3ML7Y29A`; [C] re-verify in P01: E2SM common v07.00 `QW6VJ83M`, E2AP v03.00 `WEE5IEXF`, 3GPP TS 28.552 `5SZUBP6M`; 3GPP TS 38.331 `WF2FTADX` (V19.4.0, added 2026-11-03) |

## Findings for warmup review: disposition (round 1)
- **F1:** resolved by Amendment 1 (AC8b, option a) → R-2 transform T, P08 fixtures.
- **F2:** resolved within contract → I-1; mapping in P07's ledger; shown at Stop A′.
- **F3:** resolved → I-2 (constant c = 3.0 ms).
- **F4:** resolved → I-3.
- **F5:** resolved by Amendment 1 (AC14, AC14b, option A) → R-4, new phase P06b, P07.
- **F6:** resolved → I-4 (v01.03 and v03.00 §8.4.6.3; not a T4).
- **F7:** redesigned. e2mgr 6.0.6 stores no RAN functions for eNB nodes, so kpimon takes the eNB's KPM measurement list from its own config (the metric-map `enb` rows), disclosed as an L-release e2mgr limit (P06). AC6a records the eNB nodeb JSON without `ranFunctions` and sends one KPM subscription to the eNB probe node (P01).
- **F8:** resolved → I-5.
- **F9:** resolved → I-6.
- **F10:** preflight in P01 (kpm_sim at 100 ms); P03 step 2 runs before AC8 run 2.
- **F11:** preflight in P01: presence check of every needed Zotero document (keys in the table above). A missing one is T4 at P01, not mid-phase.
- **F12:** applied in P06/P07:
  - the rc patch includes `rcService.go:35`;
  - stale-image guards for rc and kpimon tie each image to its patch-set digest (like `ts-lib.sh:116-140`);
  - the protoc toolchain proof regenerates the unchanged `rc.proto` byte-equal to the committed `rc.pb.*` before any change;
  - one ordered TS patch manifest drives both the installer and `ts_patches_check`.
- **New, I-9:** the AC11 citation points at the wineslab e2sim fork. The fix is delivered where kpm_sim is actually built.

## Review disposition
Every warmup round-1 item (kongming plan review, Codex run 1 items 1–6) is dispositioned in `plans/261103-0008-GH-1-post-m9-realism-m10/reports/warmup-review-ledger.md`, maintained by the controller. The plan text above and the phase files carry the applied changes.

## Cross-cutting rules
- **Evidence:** `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/<gate>/<UTC ts>/` via `EVIDENCE_HOST_ROOT`, scrubbed; only the verdict layer goes into git (`plans/.gitignore` gets `m10/*/*` in P12). References go under `…/reference/`.
- **Code delivery:** forks on `dev/l-release-nist180` (ns-3, oran-interface, the Testbed including the agent and all xApp/e2-interface patches, the wineslab e2sim for I-9); every pin in `scripts/pins.conf`; conventional commits; no plan IDs in code or commits.
- **Offline end run:** the independent encoder (`tools/asn1-indep`) and the protoc containers ship as image tarballs with sha256, or their outputs are pre-encoded on the host; nothing is fetched from PyPI inside the M10 run.
- **Failure Protocol and phase exit:** as in M8–M9. One kongming-guided fix; a second red is PAUSE T6. The phase exit records `df -BG /home /mnt/data` and the projection against T′.
- **Review:** kongming at every phase exit and Stop. Codex read-only, one call at a time, disclosed, no cap (R3); plan gate round 2 next; the pre-ship audit runs in P11, before the cp3 tag.
- **M5–M7 regression** after every agent or ns-3 change (P02, P03, P05, P06, P06b, P07, P10).

## Rollback
- Environment: revert the phase's start snapshot, with the VM shut off first.
- Code: revert commits on the fork branches. Pushed history is never rewritten without the user, and checkpoint tags are never moved.
- Rolling back a fix means re-pinning the previous SHA, and the matching tag reproduces the earlier references (R8).

## Unresolved questions
1. T′ base: the method sum (binding by default) or the measured base′. The user rules at Stop B (S5: deferred, with the per-step host measurement approved).
2. ~~The /mnt/data 5 GiB floor~~ confirmed at Stop A (S7, 2026-11-04).
3. ~~I-9~~ resolved 2026-11-03 01:45 KST: the contract's AC11 citation was corrected to the Testbed `e2-interface` tree (requirement unchanged).
4. P15 (contract Amendment 3) stays a fix unless the P05 scoping read shows it needs e2mgr RAN-function cell lists (the F7 limit); then it exits to record-only, reported at the next Stop.

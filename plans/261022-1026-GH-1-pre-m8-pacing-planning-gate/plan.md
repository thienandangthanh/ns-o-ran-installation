---
title: Pre-M8 pacing planning gate (counsels, research, pacing journal, stop for approval)
status: ready (goal-warmup 2026-10-22; contract approved by user)
created: 2026-10-22
contract: Outcome Contract locked 2026-10-22 (goal-warmup session; restated below)
parent: plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/ (M0–M7 green, P8 green, snapshot f7-rerun-green)
scope: pacing gate only; no M8/R0–R3/M9 implementation; no M8 plan
---

# Plan: pre-M8 pacing planning gate

## Locked outcome contract (verbatim intent; immutable)

- **Intended result.** One committed and pushed journal checkpoint, `docs/journals/2026-10-2x-pre-m8-pacing-plan-checkpoint.md`. It synthesizes at least 3 blind kongming counsels and cited prior-art research into one pacing plan. The run then **stops for the user's explicit approval**, and nothing implements M8.
- **In scope.**
  1. The counsel brief.
  2. At least 3 blind kongming counsels (Opus 5.5 xhigh, `model: opus`).
  3. Cited research.
  4. Bounded VM probes, only if a number is needed. They start from `f7-rerun-green`, take no snapshots, push no M8 code, and revert afterwards.
  5. The journal: recommendation, how T is set and the run-out semantics, rollback, the M8/R0–R3/M9 acceptance-criteria changes, the locked RC inputs, and the R2/R3 gaps.
  6. Deleting `f0`–`f6` and `m0-probe-f10212128` after verifying their evidence is archived. `fresh-install` and `f7-rerun-green` are kept. If libvirt refuses a delete, STOP.
- **Out of scope.**
  - Any M8, R0–R3 or M9 code.
  - The M8 plan, which is the next warmup.
  - The N release.
  - Host changes or host sudo.
  - Upstream PRs.
  - ns-3 radio or scenario changes.
- **Acceptance signals.**
  - At least 3 counsel reports, each stating its blindness and the brief SHA.
  - A research report with at least 1 primary source for each prior-art area.
  - A journal with the 4 required sections, a consensus and dissent table, and an approve/edit decision list.
  - Probe numbers with their evidence path and commit.
  - Pushed conventional commits with no AI references.
  - A final stop for approval.
- **Constraints.**
  - Never delete `fresh-install`.
  - No secrets in any output.
  - Work on fork branches only.
  - Opus orchestrates and synthesizes; Sonnet does only bounded tasks.
  - The orchestrator re-checks every Sonnet number against raw evidence.
- **Locked decision inputs (user, 2026-10-22).**
  - **RC routing.** RC lands on **any node** and is routed by IMSI in ns-3 to the LTE master RRC (`PerformHandoverToTargetCell`). Every agent, the eNB included, advertises RC **RAN function 3**, because TS hard-codes 3.
  - **RC version.** **E2SM-RC v2.0**, generated from rc @a2282ee `e2sm/e2sm-rc-2.0.asn` with a pinned generator.
  - **Ladder target.** **R3** (real TS plus real QP).
  - **M9.** Revert `fresh-install`, then one unattended invocation that runs up to the highest green rung.
  - **Determinism and T run-out semantics.** The counsels propose them, and the user decides at journal approval.

## Inputs (read-only)

- Handoff: `plans/reports/handoff-261022-0416-GH-1-pre-m8-pacing-planning-gate.md`
- Contract (LOCKED): `plans/reports/brainstorm-261017-0308-GH-1-ns-oran-l-release-nist-1-8-0-contract.md`, the sections "User answers — pacing" and Q3
- S1–S4: `docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md`
- `docs/system-architecture-l-release.md`, `docs/deployment-guide-l-release.md`
- Timing: `plans/reports/timing-261022-0217-GH-1-ns3-scenario-zero-real-vs-sim-time.md`
- Fact pack (verified 2026-10-22): `plans/reports/scout-261022-1026-GH-1-rc-ts-qp-ns3-control-fact-pack.md`

## Phases

| # | Phase | Owner / model | Gate (exit) | Depends |
|---|---|---|---|---|
| P0 | Pre-run checks | orchestrator | the preflight matrix "must" rows are re-checked green | — |
| P1 | Counsel brief | orchestrator (Opus) | the brief is committed, and its SHA is recorded | P0 |
| P2a | 3 blind counsels | 3 × kongming, `model: opus` | 3 reports, each answering Q1–Q8 below | P1 |
| P2b | Prior-art research | researcher (independent of P2a) | a report with citations, at least 1 primary source per area | P1 |
| P3 | Probes, conditional | Sonnet writes the scripts; the orchestrator verifies | each requested number has a raw evidence path; the VM is reverted to `f7-rerun-green` | P2a |
| P4 | Synthesis journal | orchestrator (Opus) | the journal has every required section and passes the self-check | P2a, P2b, P3 |
| P5 | Commit, push, disk housekeeping, STOP | orchestrator | pushed; `f0`–`f6` deleted per the contract; final stop message | P4 |

### P0. Pre-run checks
- Read every input in the order listed above.
- Re-check four things:
  - host `df /home` is at least 20 G;
  - `virsh snapshot-list` includes `fresh-install` and `f7-rerun-green`;
  - `ssh oran-kvm-2404` answers;
  - the branch is clean and level with origin.
- Record the starting HEAD.
- Commit this plan, the fact pack (`plans/reports/scout-261022-1026-…`) and the review/matrix report, which the warmup left uncommitted. Push them.
- Spawn kongming with `model: opus` and `effort: xhigh`. The user explicitly asked for Opus 5.5 xhigh.

### P1. Counsel brief
- Write `plans/reports/brief-<ts>-GH-1-pre-m8-pacing-counsel-input.md`.
- It must be self-contained. Cite the input files by path rather than retyping them.
- Contents:
  - the measured numbers (handoff sections 1 and 2);
  - the reserved IPC types;
  - the locked RC inputs;
  - the fact-pack pointers;
  - the user's preference for repeatable lock-step;
  - what is open.
- Commit it. Each counsel receives the brief SHA.
- **Counsel questions** (each counsel must answer all of them, with a recommendation and confidence):
  - **Q1. Mode.** Lock-step, real time or a hybrid. Who is the clock master, and what is one step (one KPM period, or k periods)?
  - **Q2. T.** How T is chosen from the measured inputs: 0.17 s and 3.2 s of wall time per 0.1 s sim period, plus the RIC round trip. What happens on expiry: continue, freeze, or drop the control? What determinism semantics does each choice give, and what repeat gate does it allow?
  - **Q3. Control path into the ns-3 thread.** The emitter socket polled from a sim event, versus `ScheduleWithContext` from an IPC thread. Message shapes for the reserved `control`, `controlAck` and `step`. Where a step blocks.
  - **Q4. Timers while sim time is paused.** E2 procedure timers in e2term and submgr, kpimon's 5 s subscription poll, rc's 2 s ack timer, and SCTP keep-alive, which is decoupled by design.
  - **Q5. Subscription option B on sim time** (`simTimeNs`).
  - **Q6. RC ack semantics.** When the agent sends a RICcontrolAcknowledge versus a RICcontrolFailure: queued, applied at sim time t, or handover complete. How an ns-3 refusal surfaces, for example the `m_mmWaveCellSetupCompleted` guard or a UE already on the target.
  - **Q7. M8/R0–R3/M9 acceptance-criteria changes.**
    - The ns-3 trace: a handover per IMSI, the target cell, at least 2 gNBs.
    - The wire: a decoded RICcontrolRequest and RICcontrolAck, through an E2SM-RC v2.0 decode.
    - The repeat count.
    - The automatic-handover policy (`--handoverMode=NoAuto` versus `TakeUeHoControl` per UE).
  - **Q8. Rollback and the biggest risk.** What to do if lock-step fails at M8.
- **Blindness rules.** No counsel may read `plans/reports/counsel-261022*` or `research-261022*`. Each counsel is spawned in the same message, so none can see another's output. Each report starts with a statement of its blindness.

### P2a. Counsels
- Three `kongming` agents, `model: opus`, spawned in one message.
- Each gets the same prompt with a different **lens**, so the independence buys diversity:
  - A: determinism and repeatability first;
  - B: RIC and E2 protocol timing first;
  - C: ns-3 internals and thread safety first.
- Each must still answer Q1–Q8.
- Outputs: `plans/reports/counsel-261022-<hhmm>-GH-1-pacing-{a,b,c}.md`.
- Counsels are advisory only and must not run VM probes. They list any probe they need, with the exact command and the decision it would change.

### P2b. Research
- One researcher agent.
- Areas, with at least 1 primary source each:
  - ns-O-RAN and OpenRAN Gym semaphore pacing (the ns-O-RAN paper or repo, the ns-o-ran-gym docs or paper);
  - ns3-gym (Gawłowski et al., the repo and its step semantics);
  - Colosseum (scenario real-time emulation, the RF channel emulator, SCOPE);
  - co-simulation time synchronization (conservative versus optimistic, HLA/FMI/mosaik, ns-3 `RealtimeSimulatorImpl` hard-limit semantics);
  - digital-twin pacing (O-RAN digital twin, the NVIDIA Aerial Omniverse DT or similar, if a primary source exists).
- Output: `plans/reports/research-261022-<hhmm>-GH-1-ns3-external-controller-pacing-prior-art.md`.
- Every claim gets a URL or DOI. Anything unverified is marked as such.
- The orchestrator spot-checks at least 3 citations, including at least 1 from each of the ns-O-RAN gym and ns3-gym areas.

### P3. Probes (conditional)
- Run only the probes that at least one counsel says would change a decision. Candidates:
  - (a) Optimized-profile timing for the 1-gNB and default configurations. This needs an ns-3 rebuild on the VM, which is VM-only and pushes no code.
  - (b) An RIC round-trip estimate on the idle stack. kpimon subscription response latency from the M5/M6 pcaps is acceptable as an offline proxy, with no VM needed.
  - (c) E2 and kpimon behaviour while an agent stops sending indications for a time longer than T. This can be done by pausing ns-3 with SIGSTOP on `f7-rerun-green`.
- **Rules.**
  - Each probe starts with `vm-snapshot.sh revert f7-rerun-green`. Shut the VM off before reverting.
  - Probes take no snapshot create and push nothing to the fork branches.
  - Throwaway scripts go under `scripts/probes/`, committed to the harness branch only.
  - Evidence goes to `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/<probe>/<UTC-ts>/`, scrubbed.
  - After each probe, revert to `f7-rerun-green`.
  - A probe gets 2 attempts. If it fails twice, record it as an open question; do not block on it.
- Disk: check `df /home` before each revert. A revert leaves orphaned overlay files behind.

### P4. Synthesis journal (Opus orchestrator)
- File: `docs/journals/2026-10-2x-pre-m8-pacing-plan-checkpoint.md`. Use the actual date.
- Sections:
  1. Where we are, and the evidence.
  2. The locked RC inputs and the R2/R3 gaps:
     - QP's measurements against kpimon's;
     - TS's REST default;
     - `cell_map` built from the E2Setup bytes, which needs the ranName suffix inside `e2nodeComponentRequestPart`;
     - TS's trigger (A1 type 20008 or an AD anomaly);
     - the hard-coded UE-ID and GUAMI values.
  3. Counsel consensus and dissent, as a table per question.
  4. Research findings, cited.
  5. **The recommendation**: mode, step definition, the IPC messages, and the thread path.
  6. **How T is set**, with a formula and the measured inputs, plus the run-out semantics as user options with a recommendation.
  7. **Rollback**: what is reverted and the fallback mode.
  8. **The M8/R0–R3/M9 acceptance-criteria changes.**
  9. The decision list for the user (approve/edit), and the unresolved questions.
- Self-check before commit:
  - every number cites an evidence path or report;
  - all four contract-mandated sections are present;
  - no secrets.

### P5. Commit, push, disk, STOP
- Commit the reports and the journal: `docs(journal): ...` and `docs(reports): ...` (conventional, no AI references). Push to `origin migrate-l-release-NIST-1-8-0`.
- **Disk housekeeping** (contract-authorized):
  1. Check that `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m{0..7}/` holds the f-run directories (`20261021T212837Z-host` … `m7/20261021T233129Z`) and `p8-attempt2-run-to-m7.log`.
  2. Shut the VM off.
  3. Delete with `vm-snapshot.sh delete`, one snapshot at a time: `m0-probe-f10212128`, then `f0`…`f6` in an order libvirt accepts. Record the image directory before and after.
  4. If libvirt refuses a delete, STOP and ask.
  5. Never touch `fresh-install` or `f7-rerun-green`.
  6. Check that `f7-rerun-green` still reverts and boots: revert, ssh, `kubectl get pods -n ricplt` all Ready.
- Update `.remember/remember.md`-style handoff only if the session tooling asks for it.
- **STOP.** Print the journal path and the decision list, and wait for the user's approval. Do not start M8 or write the M8 plan.

## Traceability

| Phase | Contract items | Acceptance signals | Facts (F) / assumptions (A) / prereqs (X) / user decisions (U) |
|---|---|---|---|
| P0 | constraints | must rows green | F: host 35 G free; f0–f7 and fresh-install present; ssh OK; branch at 45764a2 pushed; gh authed (2026-10-22 10:3x KST) |
| P1 | brief | brief SHA recorded | F: fact pack verified; U: RC any-node/IMSI routing, func 3, RC v2.0, R3 target |
| P2a | ≥3 blind counsels | 3 reports, blindness stated | X: kongming agent is available; A: `model: opus` resolves to Opus 5.5 xhigh (CLAUDE.md) |
| P2b | cited research | ≥1 primary source per area | X: WebSearch/WebFetch are available (deferred tools); A: the primary sources are reachable |
| P3 | bounded probes | evidence path and commit per number | F: `vm-snapshot.sh revert` is proven (P8); U: probes from f7, no snapshots, revert after |
| P4 | journal | 4 sections, consensus table, decision list | U: the determinism semantics are proposed by the counsels and decided by the user at approval |
| P5 | disk; stop | pushed; snapshots per the contract; stop | F: the f-run evidence is archived (dirs present on the host); A: libvirt 12.8 deletes non-leaf external snapshots when the leaf is kept (the D2 deletion in P8 was leaf-first, so a non-leaf delete is unproven) → STOP on refusal |

## Cross-cutting rules
- L only. No N release in any form without asking.
- Gates are judged by decoded wire bytes. Log lines are supporting evidence only. The only gates that apply here are the probes'.
- No host sudo or host changes. No secrets, and the InfluxDB token is redacted in all evidence.
- Work on fork branches only, with no upstream PRs and conventional commits without AI references.
- At each phase boundary, compare the proposed work to the locked contract. On any material mismatch, pause for the user.

## Rollback
- Docs and reports: `git revert` on the harness branch.
- VM: `vm-snapshot.sh revert f7-rerun-green`.
- Deleted `f0`–`f6` cannot be restored. Their evidence is on the host, and `fresh-install` plus `run-to-m7.sh` can rebuild any state.

# Evidence packet: post-M9 realism goal (immutable; identical for every candidate)

Worktree root (all relative paths): `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0`
Date 2026-10-29, timezone Asia/Seoul, language English. You are READ-ONLY: do not edit, create, commit, ssh to the VM, run virsh, start ns-3, or call Codex. Return your answer as your final message only.

## 1. The request (user's words)
"The goal M9 is done. Now we need to brainstorm for the post-M9, comes to realism. Brainstorm the contract for `/ak-goal-warmup` and then `/goal`."
The contract you write will be fed to `ak:goal-warmup` (Outcome Contract → plan → preflight → Ready packet), which hands a long-running `/goal` to an autonomous agent.

## 2. User rulings captured in this session (2026-10-29 ~17:30 KST) — binding
- **Tracks IN this one goal:** (T-A) E2 interop + scale; (T-B) Timing realism; (T-C) Radio/counter realism.
  - T-A = fix P1, P2, P4, P5, P8, P10, P11, N5, plus the scale gate > 9 gNBs.
  - T-B = P3 → sim-time actuation delay δ (default 0 byte-equal to M9) and a δ sweep; P12 subscription period honoured (kpimon period configurable + agent option B); measurement-time stamping in kpimon (offered as part of the track; you may argue for or against inside the track).
  - T-C = P6, P7, P9; possibly `UseIdealRrc=false` (offered as "possibly").
- **Track OUT:** real QP fork + R3 with real QP, scenario-one portability smoke, scenario-agnostic harness (deferrals S1/S3 stay deferred).
- **Ops follow-ups:** a prelude phase fixes handoff follow-ups 1 (finish() orphan gap), 2 (revertDisks overlay leak), 3 (rtmgr_push_acked false OK → judge on rt_reader_ok) and 5 (watchdog headroom h≈9). Follow-up 4 (root cause of stuck RMR route readers) is investigation-only; the F″ remedy stays.
- **End state:** a new unattended run like M9: revert `fresh-install`, one unattended invocation runs the M0–M9 regression plus the new realism gates, exit 0, exact pre-registered step set.
- **δ source:** NOT ruled by the user. The user asked this brainstorm to decide it. Options on record: fixed sweep δ ∈ {100, 200, 500 ms} + one off-grid (150 ms); free-run measurement campaign first (not a gate) then pick δ; both (campaign informs, sweep gates). You must recommend one and justify it.

## 3. Earlier user rulings that still bind
- P10 fix acceptance (2026-10-29): a gate check that every agent's agent → e2term DATA chunks in every live capture carry SCTP PPID 70, judged per agent.
- P11 fix acceptance (2026-10-29): a gate sends a spec-format NR CGI target built by an encoder independent of our rc and expects `applied` in the ledger and in ns-3's handover traces. A fix must choose a gNB ID length (40-bit gNB ID+cell ID does not fit the 36-bit NCI one to one).
- Scale gate (2026-10-29): a gated run with more than 9 gNBs (scenario-zero allows 1–85, `nMmWaveEnbNodes`) so cell IDs ≥ 10 and KPM reports with more than the 8 neighbours `maxNeigh` allows are exercised.
- P12 (2026-10-29): needs its own brainstorm and plan before any fix; honouring kpimon's stock 10 s literally would starve the TS xApp loop.
- Lock-step (pacer barrier) stays the gate mode; M9 references must stay reproducible (δ = 0 byte-equal).
- Standards rule (user memory): check every technical pick against 3GPP / O-RAN specs (the user's Zotero library; Zotero MCP may be unavailable to you — cite clause numbers and say "unverified against Zotero" when you could not read the text). Write "TS xApp" for the traffic-steering xApp vs "3GPP TS" for specs. Deviations P1–P3-class must be fixed before publication.
- Codex challenge/audit rule (`~/.claude/rules/codex-challenge-audit.md`): plan gate 2 runs + pre-ship 1 + spare 1 = cap 4 Codex runs per feature. NOTE: the user requested 4 Codex runs for THIS brainstorm; whether those count against the next goal's cap is unresolved.
- kongming counsel never counts as user approval. Branch on our forks (origin), never the cloned upstream branch. VM `ubuntu24.04` (ssh `oran-kvm-2404`), Ubuntu 24.04, single-node k8s L-release RIC, NIST Testbed 1.8.0.

## 4. Current state (verified by the controller at 17:30 KST)
- M9 PASS: `plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md` (read it fully: deviations table P1–P12, N5, scale ruling, substitutions 1–4, interpretations (a)–(k), unresolved Qs). Verdict `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/verdict.json`. Wall 12,643 s of 20,199 s budget. Frozen harness F″ `39b3ba2`; pins in `scripts/pins.conf`.
- Host disk now: `/home` 59 GiB free (327 G total); `/mnt/data` 21 GiB free. The M9 budget required ≥ 84 GiB free on `/home` before reverting `fresh-install` (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/m9-budget.md`). Each revert after an M9 run leaks the active overlay (16–41.5 GB) until follow-up 2 is fixed.
- Handoff with follow-ups 1–7, 6a (P12), 6b (timing decisions + unverified claims to check first: rc panics on an outcome-less RIC CONTROL ACKNOWLEDGE; rc's 2 s ack timer at `a2282ee`; QP's -1600ms window being wall time; AD's InfluxDB polling interval): `plans/reports/handoff-261029-0540-GH-1-m8-m9-done.md`.
- Timing counsel (read §6 recommendations R1–R6 and "What to avoid"): `plans/reports/kongming-261029-1426-GH-1-timing-realism-advice.md`; `plans/reports/codex-261029-1426-GH-1-timing-realism-advice.md`; explainer `plans/visuals/explain-ns3-sim-time-vs-ric-wall-time.html`.
- Previous goal contract and plan for format and invariants: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/goal-packet.md`, `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`, `.../m9-budget.md`.
- Architecture and deployment docs: `docs/system-architecture-l-release.md`, `docs/deployment-guide-l-release.md`.
- Code seams (verify before claiming): `oran-interface/model/e2-control-hub.cc` (d = 0 at ~:285, barrier ~:495), `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/` (`sample-forwarder.cpp:69` granulPeriod, `rc-control.cpp:25-33` 9-octet target, `main.cpp`), `e2sim` (`e2sim/src/SCTP/e2sim_sctp.cpp:222` plain send → PPID 0), `scripts/gates/` (pacer.py, rung-config.json, r3p-*), `scripts/run-to-m9.sh`, `scripts/gates/gate-m0-host.sh`, `scripts/gates/bringup.sh`, `ns-3-mmwave-oran/` (scenario-zero, lte-enb-rrc.cc), kpimon patches under `O-RAN-Testbed-Automation/.../install_patch_files/xApps/kpimon-go/`.
- Prior journals / Stop B: `docs/journals/2026-10-28-m8-m9-stop-b.md`, `docs/journals/2026-10-29-m8-m9-m9-green.md`.

## 5. What you must produce (one complete candidate)
Markdown, ≤ 1,800 words, in this order:
1. **Outcome** (the observable end state).
2. **Constraints.**
3. **Non-goals.**
4. **Acceptance criteria** — numbered, each observable and checkable by a script or a named evidence file (not "works well"). Cover every in-scope track item, the ops prelude, δ = 0 byte-equality to M9 references, the new unattended run, and records/docs.
5. **Trade-offs** — required (you must compare ≥ 2 viable approaches, at least for the δ source and for goal shape/ordering). For each approach: the assumption it depends on most, and the condition under which it fails first; compare on worst plausible case.
6. **Better approaches** — required heading: either an evidence-backed better approach than what the user ruled (state evidence, operational delta, switching cost), or `none — recommended direction is the requested one (<evidence>)`. A user ruling may be challenged only with evidence; never silently override it.
7. **Recommended direction** — δ source decision with justification; ordering of prelude/tracks/end run as coarse milestones (no detailed phase files); how the new unattended run stays within a disk and wall budget.
8. **Draft `ak:goal-warmup` Outcome Contract** in exactly this schema: Intended result / In scope / Out of scope / Acceptance signals / Constraints / Allowed substitutions (only ones you propose for explicit user approval — mark them "proposed") / Decision owner: user.
9. **Unresolved questions** (user decisions that remain; things you could not verify).

Label claims [V] verified by you in code/evidence this pass (cite path:line), [C] carried from a report without re-verifying, [I] inference. Do not invent file contents. Prefer the smallest approach that satisfies the rulings.

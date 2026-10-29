# HANDOFF: ns-3 real-time work after post-M9 and sufficient speed

## Mission and current status

Preserve our finding about ns-3 real-time documentation for a later goal. The user decided on 2026-10-29: revisit real-time operation only after post-M9 is complete and sufficient simulation speed has been achieved.

Done: read-only feasibility assessment, official documentation lookup, and capture of the findings below. Remaining: future performance measurements and, once the prerequisites hold, a separately scoped real-time goal. This handoff does not start that goal or assert either prerequisite is satisfied.

## Scope and guardrails

Workspace: `.` (the repository/worktree root). All local paths in this document are relative to that root, wherever the repository is checked out.

In scope now: this single continuation document. Out of scope now: implementation, benchmarks, VM access or CPU allocation changes, commits, and runtime dispatch.

Constraints: finish post-M9 and demonstrate sufficient simulation speed before starting real-time work. More VM CPU resources are an available option in principle, not a resource change performed or authorized by this capture. Do not silently reduce radio fidelity, topology, UE count, or traffic to claim real-time success. Preserve existing lock-step/replay contracts unless a later accepted goal explicitly changes them.

Safety boundaries: inspect current instructions and state before future work; this document is context, not authorization to operate the VM or launch a goal.

## Current state

Observed before writing this artifact, 2026-10-29 22:48 KST:

- Branch: `migrate-l-release-NIST-1-8-0`.
- HEAD: `cca884004c3a6bffa05ad12fa0d14910450d8c03`.
- Working tree: `.` (repository/worktree root); no tracked changes reported by `git status --short`.
- Changed files: none reported before capture.
- Untracked files/directories: `.claude/`, `.remember/`, `plans/reports/brainstorm-261029-1824-GH-1-post-m9-realism-goal-contract-pool/`, `plans/reports/brainstorm-261029-1824-GH-1-post-m9-realism-goal-contract.md`, and `plans/reports/kongming-261029-1833-GH-1-post-m9-realism-brainstorm-go-no-go.md`.
- Intentional local modifications: not captured for those pre-existing paths; leave them untouched. This handoff is the sole intentional addition from this capture.

Post-M9 completion and current VM configuration were not verified. The existing M9 completion handoff records historical M9 success; M9 success does not establish post-M9 completion.

## Decisions and rationale

- **User decision:** defer real-time work until post-M9 completion and sufficient speed. No goal was launched.
- **Documentation finding:** `RealtimeSimulatorImpl` paces execution against wall time; it cannot supply missing compute capacity. First demonstrate that the intended workload can keep up, then evaluate clock synchronization. Official reference: <https://www.nsnam.org/docs/manual/html/realtime.html>.
- **Source finding:** the checked-out default simulator runs `ProcessOneEvent()` in a sequential loop. More vCPUs do not automatically parallelize that loop. Extra capacity may reduce competition from RIC services; measure contention before expecting improvement. References: `ns-3-mmwave-oran/src/core/model/default-simulator-impl.cc:187` and <https://www.nsnam.org/docs/manual/html/events.html>.
- **Build finding:** `scripts/build-ns3.sh:30` selects the `default` profile, documented locally as `-O2 -g` with assertions/logging enabled. An optimized build is a candidate for a future performance effort, not a measured solution or a promised speedup.
- **Timing-contract finding:** current lock-step barriers wait for agents/pacer processing. Sufficient raw ns-3 speed is necessary but does not alone prove the closed loop meets wall-clock deadlines. Treat real-time operation as a separate acceptance contract; do not casually replace the repeatability mechanism.
- **Assessment, not proof:** one-gNB real time is a reasonable first experimental target. The historical four-gNB workload requires a much larger improvement; CPU count alone is not an evidence-backed route to it. MPI/parallel simulation would require model compatibility and partitioning investigation, rather than a VM setting change.

## Work performed

- The earlier assessment read the root README, deployment/architecture docs, timing report, build script, and default simulator source, and searched official ns-3 documentation.
- This capture reread the historical timing report, timing checkpoint, build flags, lock-step documentation, default event loop, and existing M9 completion handoff.
- Ran Git repository detection, root/branch/HEAD probes, and bounded `git status --short`; observed the state recorded above. Discovered existing handoffs under `plans/handoffs/` and legacy `plans/reports/`.
- Created only this Markdown artifact. No simulation, VM command, configuration edit, staging, commit, or dispatch was performed.
- An earlier lookup omitted the `-time` suffix from the timing report filename and failed; the correct existing path is listed below.

0 redactions applied. The drafted content was reviewed against the skill's redaction categories before writing; it contains no credentials or incidental personal data.

## Verification

| Check | Outcome | When |
| --- | --- | --- |
| Git root, branch, HEAD, status | Observed as recorded in Current state; status had five entries, no truncation | Capture |
| Historical timing and methodology | Confirmed in local report/checkpoint | Earlier assessment and capture |
| Build profile and sequential event loop | Confirmed in checked-out source | Earlier assessment and capture |
| Lock-step waits for pacer/agents | Confirmed in architecture documentation | Earlier assessment and capture |
| Official real-time documentation | Consulted during earlier assessment; links preserved, not refreshed during capture | Earlier assessment |

Historical baseline (2026-10-22, not a current or post-M9 benchmark):

| Configuration | Wall seconds per simulated second | Approximate speedup to 1:1 |
| --- | ---: | ---: |
| 1 gNB, LTE E2 disabled | 1.685 | 1.7x |
| 2 gNBs | 6.360 | 6.4x |
| 4 mmWave gNBs plus LTE eNB, 12 UEs | 31.958 | 32x |

The M4 report used 10 simulated seconds, three repeats, full-buffer UDP DL, an IPC null sink, an 8-vCPU Ubuntu VM, and the default build profile. RIC services were running but idle. The two-gNB result is from the separate checkpoint probe. Later model changes can invalidate these rates.

Not run: fresh benchmarks, optimized-build comparisons, CPU profiling, VM resource inspection, or real-time scheduler integration. This was advice and documentation capture only.

## Open risks and blockers

- Type: dependency. Owner: future goal owner. Impact: post-M9 completion and sufficient speed must be evidenced before real-time implementation begins.
- Type: question. Owner: user and future goal owner. Impact: the target topology, traffic, reporting interval, run duration, acceptable lag, deadline-miss rate, and headroom have not been selected. No real-time acceptance threshold was approved in this session.
- Type: risk. Owner: future goal owner. Impact: average wall/simulation ratio can hide bursts and accumulated lag; include computation, IPC, RIC/barrier waits, and any intentional delay in the timing contract.
- Type: risk. Owner: future goal owner. Impact: official rolling documentation may describe a newer ns-3 architecture than this fork. Reconcile with pinned source before choosing APIs or runtime attributes.
- Type: question. Owner: future performance effort. Impact: optimized-build gains and CPU contention remain unmeasured; changing build flags may affect numerical results and requires appropriate output/replay validation.

## Exact next actions

1. **First safe step** — when the user revisits this topic, run `git rev-parse HEAD` and `git status --short`, reread current repository instructions, and verify the post-M9 completion evidence and performance report for the intended scenario. If either prerequisite is absent, keep real-time implementation deferred.
2. Once both prerequisites are met, define the later goal's workload and measurable clock-lag/deadline acceptance criteria with the user. Separate startup from steady-state behavior and specify overrun handling.
3. Refresh the official real-time/events documentation below and reconcile it with the then-pinned simulator and pacing source. Explicitly decide how wall-clock operation coexists with deterministic lock-step and replay.
4. Under the later goal's operational authorization, benchmark free-run and closed-loop behavior with identical topology, traffic, seeds, and recorded build/CPU settings. Measure interval-level cost and lag, not only total runtime.
5. Evaluate `RealtimeSimulatorImpl` only when measured capacity supports the agreed deadlines with headroom; verify simulation outputs, control timing, deadline misses, and accumulated lag. If speed is insufficient, return to the separately scoped performance effort.

## Source pointers

- `plans/reports/timing-261022-0217-GH-1-ns3-scenario-zero-real-vs-sim-time.md` — M4 timing methods, results, and historical pins.
- `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md:24` — one/two/four-gNB rates; optimized timing explicitly not run at that checkpoint.
- `scripts/build-ns3.sh:30` — build profile and configure flags.
- `scripts/measure-ns3-timing.sh` — existing timing entry point; read its current usage before invoking.
- `ns-3-mmwave-oran/src/core/model/default-simulator-impl.cc:187` — sequential event loop.
- `docs/system-architecture-l-release.md:162` — current lock-step/repeatability contract.
- `plans/reports/handoff-261029-0540-GH-1-m8-m9-done.md` — historical M9 completion and deferred follow-ups; verify later state independently.
- <https://www.nsnam.org/docs/manual/html/realtime.html> — real-time scheduler behavior and policies.
- <https://www.nsnam.org/docs/manual/html/events.html> — simulator execution model.
- <https://github.com/nsnam/ns-3-dev-git/blob/master/README.md> — upstream overview, including limited MPI support.

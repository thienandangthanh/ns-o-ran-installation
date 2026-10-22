# Contract-preserving review and preflight matrix: pre-M8 pacing planning gate

Date: 2026-10-22. Plan: `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/plan.md`. The review is local to the warmup (collect, then classify; the default red-team apply step was not run). The plan was edited only for `mitigation-within-contract` findings.

## Review findings

| # | Finding | Class | Action |
|---|---|---|---|
| R1 | Deleting the non-leaf external snapshots f0–f6 while keeping the leaf f7 is unproven on libvirt 12.8. P8's D2 deletion went leaf-first, so the f7 chain could be refused or damaged. | preflight-required + mitigation | The plan shuts the VM off, deletes one snapshot at a time, STOPs if libvirt refuses, and then proves that f7 reverts, boots and has all ricplt pods Ready. If f7 is damaged, `fresh-install` + `run-to-m7.sh` rebuilds it (about 2.5 h, P8). |
| R2 | Counsels could see each other's output, or the research, if those files appear mid-run. | mitigation-within-contract | All 3 are spawned in one message, they are forbidden to read `counsel-261022*` and `research-261022*`, and each report states its blindness. |
| R3 | Three counsels given identical prompts tend to converge, which wastes the independence. | mitigation-within-contract | Each gets a different lens (determinism / RIC timing / ns-3 threading), and each must still answer Q1–Q8. |
| R4 | The orchestrator might accept a counsel or research claim without checking it. | mitigation-within-contract | The journal cites a source for every number, and the orchestrator spot-checks at least 3 research citations and any Sonnet-produced probe number. |
| R5 | Probe (a) rebuilds ns-3 with the optimized profile on the VM, which could leak into the fork pins. | mitigation-within-contract | The build is VM-local and pushes nothing to the forks. The VM reverts to f7 afterwards. |
| R6 | Each revert leaves orphaned overlay files that eat host disk. | preflight-required | `df /home` is checked before each revert, with the 20 G floor from the contract. |
| R7 | The determinism and T run-out semantics are left open in the contract. | none (user decision) | The user chose "counsels propose". The journal presents the options and the user decides at approval. No outcome change. |
| R8 | The R2/R3 data gaps (QP and kpimon measurement names, TS REST default, TS `cell_map`, TS trigger) could tempt the run into fixing them. | mitigation-within-contract | They are journal content only. Any code is out of scope. |
| R9 | The kongming effort is set by the agent definition, but the user explicitly asked for xhigh. | mitigation-within-contract | Spawn with `model: opus` and `effort: xhigh`. |

There are no `blocker` or `outcome-change-request` findings.

## Preflight matrix (checked 2026-10-22 ~10:30 KST, non-mutating)

| Phase | Check | Status | Evidence |
|---|---|---|---|
| all | Host `/home` free ≥ 20 G | ✅ 35 G | `df -h /home` |
| P3, P5 | Snapshots `fresh-install` and `f7-rerun-green` present | ✅ | `virsh snapshot-list ubuntu24.04` |
| P3 | VM reachable | ✅ ssh OK, VM `/` 57 G free | `ssh oran-kvm-2404` |
| P5 | f-run evidence archived on the host | ✅ m0 `20261021T212837Z-host`/`212930Z` … m7 `20261021T233129Z`, plus `p8-attempt2-run-to-m7.log` | `ls plans/261021-…/evidence` |
| P0, P5 | Branch clean, origin at HEAD 45764a2 | ✅ (only `.claude/` and `.remember/` are untracked) | `git status`, `git log origin/…` |
| P5 | `gh` and git push authenticated | ✅ (token redacted) | `gh auth status` |
| P2a | kongming agent available; `model: opus` = Opus 5.5 | ✅ (the session model is Opus 5.5) | agent list |
| P2b | WebSearch and WebFetch | ✅ available (deferred tools) | tool list |
| P5 | Deleting non-leaf external snapshots | ⚠ unknown | R1; STOP on refusal |
| P3 | Optimized ns-3 build fits the VM disk and time | ⚠ unknown | conditional probe; 2 attempts, then an open question |

**Must provide before the long run:** none.
**Should decide before the long run:** none open. Determinism is deferred to journal approval by the user's choice.
**Can be deferred (the contract allows it):** probes (a) to (c), and the snapshot deletion if libvirt refuses.

## Unresolved questions
1. Whether libvirt 12.8 deletes the external non-leaf snapshots f0–f6 cleanly while f7 is kept (answered at P5).
2. e2term 6.0.6's E2AP version (not needed for pacing; carried to the M8 warmup).

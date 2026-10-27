# Preflight matrix, M8–M9 amendment A1 (2026-10-27 23:41 KST)

Contract: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/goal-packet.md` (A1, approved 23:24 KST). Contract-preserving review: Codex plan gate, `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reports/codex-plan-gate.md` (`Status: complete`; 10 findings, all mitigation-within-contract and applied; no outcome-change request). All checks were read-only; no VM state changed.

**Result:** no hard blocker. One item should be decided before the long run (commit A1 first). One item is scheduled for Stop B, as the contract allows.

| Phase | Requirement | Check method | Status | Owner / unblock action | Blocking? |
|---|---|---|---|---|---|
| all | VM running, current snapshot equals the resume card | `virsh domstate` → running; `snapshot-current` → `r2-green` | available | — | no |
| all | Protected and dev snapshots present | `snapshot-list`: fresh-install, f7-rerun-green, r0-green, r2-green | available | — | no |
| all | Host free ≥ 20 GB at dev times | `df -h /home` → 63 G | available | — | no |
| all | Fork heads equal pins | `git ls-remote` of each URL in `scripts/pins.conf`: ns-3 `ba954440`, oran-interface `96efc40e`, e2sim `2209995a`, Testbed `c6d1434a` all equal | available | — | no |
| all | Parent branch pushed | `git ls-remote origin` → `0230254`; A1 edits and five reports uncommitted | pending | Commit and push A1 before re-issue so the pre-build sha includes it (user approval) | should decide |
| all | Advisors | `~/.claude/agents/kongming.md` present; Codex `setup --json` ready | available | — | no |
| all | Spec documents | Zotero `5SZUBP6M` (3GPP TS 28.552) present; its record says version 20.0.2, the ledgers write V20.2.0 | available (note) | P8′ step 2 records the version Zotero shows; not a missing document, so not T4 | no |
| P6 | r2 single red fix, V3 hardening, F09 fixtures | Gate scripts present (`gate-r2-ts-stub-qp.sh`, `check-pdcp-volume-totals.py`, `scrub-evidence.sh`, `vm-exec.sh`) | available | First goal actions; one-fix budget fresh on re-issue | no |
| P6 | Records citing `901f8c5` updated to `381a824` | QP fork branch head `381a8244` on the remote; same tree `aece41f6` | available | Goal's first action (ruling 6) | no |
| P8′ | Influx reads by the harness without exposing the token | `scripts/gates/influx-dump.sh` reads on the VM; the predictor design keeps the token out of pods and committed files | available (design) | P8′ step 1 confirms with kongming; any exposure is T7 | no |
| P8′ | Stub QP RMR peer and routes | `tools/rmr-peer/stub-qp-rmr-peer.py`, R2 route check exists | available | — | no |
| P8′ | Feasibility of a predictor-driven handover | Unknown until the dry run (constant per-cell DL) | unknown | Decided by the dry-run classifier; a valid no-handover result is substitution 4 (pre-authorized) | no |
| P9 | Codex pre-ship audit | Codex ready; fork checkouts present locally (ns-3, oran-interface, Testbed) for offline diffs after the controller fetches | available | — | no |
| P9/P10 | M9 disk budget ≥ 0 against 25 + h GB | Last estimate about −3 to −5 GB against 25 GB (before h); re-measured at P8′/P9 | pending | User frees the measured shortfall at Stop B (contract) | no (scheduled) |

## Must provide before the long run
None.

## Should decide before the long run
1. Commit and push amendment A1 (packet, plan, phase files, new phase-08b, Codex ledger) and the five reports of 2026-10-27 before re-issuing, so the pre-build sha recorded by the goal already contains the contract it audits against.

## Can be deferred (allowed by the contract)
- The M9 disk shortfall (Stop B).
- The R3′ outcome: schedule or substitution 4 (P8′ dry run).

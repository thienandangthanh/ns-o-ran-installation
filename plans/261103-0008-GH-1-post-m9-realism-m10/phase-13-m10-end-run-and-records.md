# P13: M10 end run from fresh-install, and the records

**Start state:** Stop B released; `df -BG /home ≥ T′`; harness SHA F₁₀ on origin; pins frozen. **Snapshot at exit:** none (`--no-snapshots`).

## Context
M10 repeats M9's launch route: a release order, then one transient user unit. That is `systemd-run --user --wait --unit=m10-<prefix> … scripts/run-to-m10.sh --harness-sha F₁₀ --run-prefix <p> --no-snapshots` after `scripts/vm/vm-snapshot.sh revert fresh-install` (README:51; M8–M9 phase-10 Launch-route amendment). A red step during the run is PAUSE T6. The run is never relaunched while a unit is active.

## Requirements (contract)
- **AC19:** one invocation, exit 0, exactly the R-1 step set (`exactStepSet: true`), every step green. r3p at δ = 0 equals the cp3 reference, and d150 equals its cp3 reference. `minHostFreeGb ≥ 25`; the watchdog (trip 37) never trips; rc RestartCount 0. AC2 passes after the post-run revert.
- **AC11 (judged here, A1):** every E2 node → e2term DATA chunk in every live capture of the run carries PPID 70, judged per node: the ns-3 agents and kpm_sim (M2/M3). tshark decodes E2AP without `-d`.
- **AC2 (post-run):** after the post-run revert to `fresh-install`, `scripts/vm/vm-orphan-overlays.sh` lists zero untracked overlays.
- **AC20 (records):**
  - a run report with the P1–P13/N5 table in its final state and every substitution used (A1 1–3, SUB-1, SUB-H, and S-R and SUB-P12 if applied);
  - a standards ledger per phase (unread clauses marked "unverified against Zotero");
  - README and docs updated (δ, kpimon period, gNB ID format, RC Style 5, KPM UE IDs and the X2AP context channel, the eNB measurement-list disclosure, scale);
  - a journal at every Stop, and a handoff.

## Files
- Create (Markdown): `plans/reports/run-report-<date>-GH-1-m10-realism.md`, `plans/reports/handoff-<date>-GH-1-m10-done.md`, `docs/journals/<date>-m10-green.md`.
- Modify: `README.md` (an M10 section: command, steps, recorded verdict, the deviation table's final state), `docs/system-architecture-l-release.md` (δ seam, KPM period/granularity, identity layout R-3/R-4, Style 5 path, scale), `docs/deployment-guide-l-release.md` (M10 run, new gates, Stop B disk rule).
- Evidence: `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/m10/<UTC ts>/`.

## Steps
1. Release order: unit smokes (as M9), `vm-snapshot.sh revert fresh-install`, leaked-overlay handling only under the 2026-10-28 ruling (checks 1–5, logged), `df -BG /home ≥ T′` and the /mnt/data line, memory gate, access smoke. Image tarballs (`asn1-indep`, injector) are present with matching sha256 (offline run).
2. Launch the unit; record the launch record and the re-attach commands in the resume card.
3. On exit 0 with verdict pass: copy the client exit record; post-run revert; AC2 orphan check.
4. Records: run report (per-step table, P-table final state, outcome-vs-δ table from P04 and the d-steps, substitutions), README and docs, journal, handoff.
5. kongming go/no-go on the records; push.

## Validation
- `evidence/m10/<ts>/verdict.json`: `pass: true`, `problems: []`, `exactStepSet: true`, `expectedSteps` = R-1, `minHostFreeGb ≥ 25`, no `watchdog-tripped.json`, `watchdog-lost.json`, `wall-deadline.json` or `monitor-lost.json`; `rcRestartCount == 0`; r3p and d150 `equalsReference: true`.
- `ppid70PerNode: true` in every step that captures (m2, m3, m5–m7, every rung, e2i, s10, p12), for kpm_sim and every agent.
- `vm-orphan-overlays.sh` after the post-run revert: empty.
- The run report's P-table: every P1–P13 and N5 row reads "fixed (commit, gate evidence)", or "listed" with its approved substitution.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| The run report collects every phase's ledger rows; no new decisions here. | — | — | — |

## Risks
- Environmental reaps or route-reader stalls (Medium/Medium; M9 attempts 2 and 3). Mitigation: the F″ remedy stays; FU3 receiver evidence; the launch route as M9; T8 for refusals.
- Disk falls below the trip (High/Low with T′ honoured). The watchdog stops the run and the verdict fails closed.

## Rollback
The run changes nothing in code. A failed run leaves its evidence; it is re-run only after the cause is recorded and a change committed (Failure Protocol, then a full fresh M10).

## Review amendment (kongming P00-exit review)
The release order names both overlay checks explicitly: `vm-orphan-overlays.sh` (zero untracked files) and `vm-orphan-overlays.sh --pending` (the active overlay is recorded for unlink), once after the pre-run revert and before launch, and again before and after the post-run revert (AC2). The m0 checks of the same name are a backstop only.

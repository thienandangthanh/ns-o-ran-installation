# P11 (ME): checkpoint 3: rehearsals, Codex audit, new references (incl. all four δ), diff report, tag

**Start state:** P10 pins; `f7-rerun-green`. **Snapshot at exit:** none (the tag is the checkpoint).

## Context
After T-C the outputs legitimately change. Checkpoint 3 does four things:
- makes new references for every C1 rung;
- explains every changed component by the T-C fix that changed it;
- validates every new M10 step at the final pins;
- runs the Codex code audit.

All of this happens **before** the cp3 tag, so that a fix forced by a rehearsal or by the audit does not invalidate tagged references (kongming #8). P12 is then runner-only. The C1 rungs are r3p at δ = 0, plus the four δ references (I-7): d150 is a full C1 in M10; d100, d200 and d500 are single runs against their references.

## Requirements (contract)
- **AC16 (checkpoint 3):** new references for every C1 rung, and a diff report that lists each changed component with the fix that changed it. Components not explained by a T-C fix stay equal to checkpoint 2. The commit is tagged.
- **AC9 (re-bank, I-7):** all four δ references are re-made at the cp3 pins; the P04 ones stay as history.
- **AC17:** `UseIdealRrc` is final before these references are made.
- **AC4 (dev rehearsals):** `disk-burst-h.py` over the free-series of every rehearsal below. If any 370 s burst exceeds 12 GiB, the run stops for a user ruling.
- **AC15 at final pins:** s10 passes again at the cp3 pins.

## Design
- **Attribution by bisection** over the T-C commits (P6, P7, P9 and, if the probe passed, `UseIdealRrc=false`). Run R3′ C1 at δ = 0 at each successive commit from `m10-cp2` and digest each component; the first commit at which a component changes is its cause. A change at a commit that cannot plausibly touch it is a red Verify.
- **`scripts/gates/reference-diff-report.py A B`** prints the per-component digest diff (ledger, ipc per node, traces per file, extra, files) as JSON and Markdown.
- **Rehearsals at the final pins (before the tag),** each from its start snapshot with the watchdog's free-series recorded:
  - `e2i`, `d150`, `d100`, `d200`, `d500`, `s10`, and `p12` last;
  - cold i0, i2 and m3 with the patched rc, TS xApp and kpimon builds (cold timing for the budget);
  - the M10 step order as pre-registered.
- **Codex pre-ship audit** (read-only, disclosed, no cap, R3) on `39b3ba2..HEAD` of the harness plus the fork diffs, before the tag. Findings are triaged into `plans/261103-0008-GH-1-post-m9-realism-m10/reports/codex-pre-ship.md`. An accepted fix re-runs the affected rehearsal and the references before the tag.

## Files
- Create:
  - `plans/261103-0008-GH-1-post-m9-realism-m10/reference/r3p/`, `…/reference/r3p-d100-cp3/`, `…/r3p-d150-cp3/`, `…/r3p-d200-cp3/`, `…/r3p-d500-cp3/` (made by `scripts/gates/reference-compare.py make` [V `:42-48`]);
  - `scripts/gates/reference-diff-report.py`.
- Create (Markdown): `plans/reports/checkpoint-3-<date>-GH-1-m10-reference-diff.md`; `plans/261103-0008-GH-1-post-m9-realism-m10/reports/codex-pre-ship.md`.

## Steps
1. Confirm AC17 is final.
2. Bisection C1s; build the attribution table.
3. Final R3′ C1 at δ = 0 and four δ runs (C1 for d150, C1 for each of d100/d200/d500 to bank its reference). `reference-compare.py make`; commit.
3b. **G1 (Stop A, `plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`):** re-run the migrated δ seam smoke at the cp3 candidate pins before the tag.
4. Rehearsals of every new step plus cold i0/i2/m3; record `df -BG /home` and the active overlay's `du -BG` at every gate boundary (S5) so Stop B can compute T′_measured′; `disk-burst-h.py` over their free-series; record durations for P12's budget.
5. Codex pre-ship audit and triage. If a fix lands, repeat steps 3–4 for the affected parts.
6. Diff report; tag `m10-cp3` (harness and forks); push. Phase exit.

## Validation
- r3p and the four δ C1 verdicts are green, with `equalsReference: true` on a fresh run against the new dirs.
- The diff report attributes every changed component to exactly one T-C commit; every other component is "equal to cp2".
- G1: the seam smoke is green at the cp3 pins. S5: per-step host growth is tabulated for every changed or new step. The diff report attributes P15's p12 change to its T-C commit.
- `gate-d-delta-identity.sh` carries a per-node PPID 70 check on its live capture (`--node-ips`), as every rung does since P05 (AC11 in P13).
- Every rehearsal verdict is green; s10 is green at the cp3 pins; `disk-burst-h.py` gives `worstGiB ≤ 12`.
- `codex-pre-ship.md` ends `Status: complete`, or the journal records `Codex skipped: <reason>`.
- `git rev-parse m10-cp3^{commit}` equals the harness SHA of the final references and rehearsals. (2026-11-05 note: the checkpoint tags are annotated, so the plain `git rev-parse m10-cp3` would print the tag object.)

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| None new; attribution cites the P10 ledger rows. | — | — | — |

## Risks
- A T-C fix moves R3′'s decision so that no handover happens (Medium/Medium; open point 2 accepted this). R3′ still requires ≥ 1 predictor-driven applied control. A red goes to the Failure Protocol; a scenario change is PAUSE T3.
- Cost: about 4 bisection C1s, 4 δ C1s, 7 rehearsals and 3 cold installs (≈ 6–8 h wall, plus disk) (Medium). It is accounted for in the budget and re-projected at Stop A′.
- A rehearsal burst over 12 GiB (Medium/Low–Medium) is a contract stop.

## Rollback
Tags are never moved. A wrong reference is replaced by a new C1 at a new commit before the tag.

# P04 (MB): checkpoint 1 tag, δ sweep references, predicate registration; then Stop A

**Start state:** P03 pins; `f7-rerun-green`. **Snapshot at exit:** none (the tag is the checkpoint).

## Context
Checkpoint 1 is the last point where the code reproduces the M9 `reference/r3p/` byte for byte. AC8's two runs (after P02 and after P03) are green. This phase tags that commit, banks the δ references while every other wire item is still M9, and registers the AC18 #9 predicate rewrites (P1, P5, N5) before any T-A code, so the user sees them at Stop A. The reference compare is `rung_reference` [V `scripts/gates/ts-rung-lib.sh:207-221`] against `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p/equal/{digests,files}.json` [V].

## Requirements (contract)
- **AC8 (tag):** the passing commit of AC8 run 2 is tagged `m10-cp1`; the harness SHA, every pin and the evidence are archived (host archive per the evidence-retention ruling; verdict layer in git).
- **AC9:** R3′ with δ ∈ {100, 150, 200, 500} ms. In dev: one full C1 per δ, and one committed sim-side reference per δ (ledger, ipc, traces). In every run: `applySimTimeNs − rxSimTimeNs = δ` on each applied line (R-5, I-3), HandoverStart − applySimTimeNs = c, c = 3.0 ms registered from the M9 reference at 0.1 ms resolution (I-2), and ≥ 1 applied handover per δ. An outcome-vs-δ table goes in the run report.
- **AC18 #9:** every predicate that encodes P1, P5 or N5 is written as old → new in `check-diff-ledger.md`, marked "registered contract change", and presented at Stop A before T-A code. This includes the R-7 additions from the warmup review: the r3p fixtures, the rmr-peer self-test keys, `rc-lib.sh:238`, and the R1 source-aware replacements (`gate-r1-rc-multi-control.sh:249-256,275-290`).
- **Stop A:** checkpoint 1 tagged, δ references banked, budget re-projected (T′ and W′ with the AC6b numbers).

## Files
- Create: `plans/261103-0008-GH-1-post-m9-realism-m10/reference/r3p-d100/`, `…/r3p-d150/`, `…/r3p-d200/`, `…/r3p-d500/` (each `equal/digests.json` for ledger/ipc/traces, `equal/files.json`, `SHA256SUMS`, made by `scripts/gates/reference-compare.py make` [V `:42-48`]).
- Create: `plans/261103-0008-GH-1-post-m9-realism-m10/reference/m9-r3p-raw/`: the M9 reference run's raw `trace/e2-control-ledger.jsonl`, `extra/*.json`, `r3p/predictor-records.jsonl`, plus the frozen scenario and schedule, copied from `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r3p/20261028T044557Z/runs/live1/` [V on host]. sha256 must equal the archive; P08's transform-compare reads these.
- Create: `plans/261103-0008-GH-1-post-m9-realism-m10/check-diff-ledger.md` (seed from plan R-7, re-grepped).
- Create: `plans/261103-0008-GH-1-post-m9-realism-m10/reference/identity-map-cp1.json` (plan R-8) with its entry in `reference/SHA256SUMS`, and `scripts/gates/identity-map-extract.py`. The script reads `ns3run/DlE2PdcpStatsLte.txt` (`CellId IMSI RNTI`) of the M9 live1 run at the cp1 commit, asserts one RNTI per IMSI on the MN cell for the whole run, and writes the R-8 JSON.
- Modify: `scripts/gates/gate-r3p-ts-predictor.sh` (a `--delta-ms` C1 with `--reference <dir>`, `sim-side` component set), `scripts/m9-budget.py` inputs for the re-projection.
- Create (Markdown): `docs/journals/<date>-m10-stop-a.md`.

## Steps
1. Tag `m10-cp1` on the harness commit of AC8 run 2, and tag the fork SHAs it pins (same tag name per fork). Push the tags.
2. Promote the M9 raw files (step above), verify their sha256 against the archive manifest, and commit.
2b. Freeze the identity map (R-8):
    - `identity-map-extract.py` on the promoted live1 traces;
    - cross-check against an ns-3 run at the cp1 commit with UE-context logging (`NS_LOG` on the RRC UE-context creation), which must agree IMSI for IMSI;
    - commit the JSON and its sha256 under the `m10-cp1` tag.

    It is never regenerated from post-cp1 output.
3. For each δ: R3′ C1 at that δ; on green, `reference-compare.py make` into `reference/r3p-d<δ>/`; commit. A δ with 0 applied handovers is a red Verify (Failure Protocol), not a pass.
4. Build the outcome-vs-δ table (applied/refused/late per δ, apply-to-HandoverStart offsets, which must all equal c).
5. Re-grep the R-7 patterns; write every P1/P5/N5 row old → new with "why not weaker"; mark them registered.
6. Budget re-projection: T′_method and T′_measured (plan budget), the /mnt/data line, and the T′ base question raised for the user. Stop A packet (journal with the interpretations I-1 to I-9, kongming note, resume card, push) → `PAUSE A`.

Note: these four δ references are re-banked at cp3 (P11, I-7); the ones made here stay in git as history.

## Validation
- `sha256sum -c reference/SHA256SUMS` covers `identity-map-cp1.json`. The extractor's self-test fails on a fixture with two RNTIs for one IMSI, and on one with a non-MN cell.
- `git tag -l m10-cp1` exists in the harness repo and each fork; `git rev-parse m10-cp1` equals the AC8 run-2 harness SHA in its verdict.
- Four C1 verdicts green with `deltaMs` 100/150/200/500, each `appliedHandovers ≥ 1` and the `delta` check passing.
- `sha256sum -c reference/r3p-d*/SHA256SUMS` and `reference/m9-r3p-raw/SHA256SUMS` pass.
- `check-diff-ledger.md` holds a row for every R-7 site that P05–P07 will change; no site is left "TBD".

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| δ values bracket the Near-RT loop; 150 ms between barriers | E2GAP v08.00 §5.1.1; OAD v18 Near-RT RIC section | `AE3NUEDK`, `TBVJDMLF` | to cite |
| Predicate rewrites for P1 (source en-gNB addressing) | E2SM-RC v03.00 §8.4.6.3–8.4.6.4; 3GPP TS 37.340 §10.5.1 | `JRDTL7XS`, `E6VYJPXJ` | to cite |

## Risks
- A δ that never yields an applied handover in the R3′ schedule (Medium/Low at 500 ms). Mitigation: the Failure Protocol; the scenario is not edited after its run.
- The raw M9 files are missing from the archive (High/Low). They are present on the host today [V]; the copy step verifies sha256 first.

## Rollback
References and tags are additive. A wrong reference is replaced only by a new C1 at a new commit; tags are never moved.

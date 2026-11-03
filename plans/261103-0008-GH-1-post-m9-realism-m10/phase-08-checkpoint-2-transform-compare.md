# P08 (MC): checkpoint 2, transform-compare against M9, negative fixtures, tag; then Stop A′

**Start state:** P07 pins; `f7-rerun-green`. **Snapshot at exit:** none (the tag is the checkpoint).

## Context
After T-A, only ipc (the digested sample lines) and traces stay literal. Everything else must equal the M9 files under plan R-2's enumerated transforms (Amendment 1, F1 option a). The compare reads the promoted raw M9 files (`reference/m9-r3p-raw/`, P04) and the M9 digests (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p/equal/`). The transformed fields sit at these places:
- `scripts/gates/r3p-scenario.json:5,17,27`;
- `r3p-schedule.json:2,10,17,33,40,48,52,58,65`;
- the M9 live1 `r3p/predictor-records.jsonl` (`answer` keys, `target`).

## Requirements (contract, A1)
- **AC8b**, at δ = 0 and before T-C:
  - ipc and traces literally equal to M9;
  - predictor records, scenario and schedule = T(M9 files): the N5 → NCI key, `via` target → source, `scenarioSha256` recomputed, the two P1 strings replaced, `ueId` per AC14b. Every other byte, including every predictor number, is literal;
  - the ledger and `extra` equal after transforms on the enumerated fields only (viaNodeId, the RC UE ID, the RC action and target encoding in rc-multiset, meid);
  - a negative fixture shows a mutated M9 file fails;
  - the passing commit is tagged.
- **Stop A′:** the I-1 message mapping is shown; budget re-projected.

## Design
- `scripts/gates/reference-transform-compare.py RUN M9RAW M9REF`:
  1. Digest-compare ipc and traces (literal).
  2. Apply T to the M9 scenario, schedule and predictor records. T is the pure function of R-2, written once in `scripts/gates/m9-transform.py` and used both to rewrite the committed harness files in P06 and here. Then require byte equality with the run's files.
  3. Apply the enumerated ledger / rc-multiset / meid transforms to the M9 side and require byte equality. The RC UE-ID transform reads only `reference/identity-map-cp1.json` (plan R-8; its sha256 is verified first; a mismatch fails). Input `{…, "imsi": N, …}` → output `{…, "ueId": {"type": "en-gNB-UEID", "mEnbUeX2apId": map.ues[N].mEnbUeX2apId, "globalEnbId": map.globalEnbId}, …}`, with `imsi` removed and nothing else touched. kpm-headers and collet-start-time are compared literally (no enumerated field touches them).
  4. Any byte outside the enumerated fields that differs fails and names the field.
- **Negative fixtures** (`scripts/gates/fixtures/transform-compare/`):
  - (a) ledger `targetCell` changed → fail;
  - (b) rc-multiset `step` changed → fail;
  - (c) one trace byte changed → fail;
  - (d) identity transform on the untouched M9 raw → pass;
  - (e) one predictor `answer` number changed → fail;
  - (f) a schedule `step` changed → fail;
  - (g) a scenario key left in N5 form → fail;
  - (h) an rc-multiset `ueId.mEnbUeX2apId` that differs from `identity-map-cp1.json` for that IMSI → fail;
  - (i) an rc-multiset `ueId.globalEnbId` with a wrong PLMN or macro eNB ID → fail.

## Files
- Create: `scripts/gates/reference-transform-compare.py`, `scripts/gates/m9-transform.py`, `scripts/gates/fixtures/transform-compare/` (fixtures a–i); a `--reference-transform` mode in `scripts/gates/ts-rung-lib.sh` (next to `rung_reference`, `:207-221`), used by `gate-r3p-ts-predictor.sh`.
- Create (Markdown): `docs/journals/<date>-m10-stop-a-prime.md` (including the I-1 mapping table).

## Steps
1. Script and fixtures; host-only self-test.
2. R3′ C1 at δ = 0 at the P07 pins with `--reference-transform`.
2b. **G2 (Stop A, `plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`):** R3′ C1 at δ = 150 and δ = 500 at the P07 pins with `--reference-transform` against the cp1 δ references (`reference/r3p-d150`, `reference/r3p-d500`, raw files promoted in P05 step 0). d500 is the most δ-sensitive rung. These give AC16 its checkpoint-2 baseline for the δ rungs.
3. On green, tag `m10-cp2` (harness and forks) and push.
4. Budget re-projection (T′ both bases, /mnt/data, s10 and T-C rebuild costs); Stop A′ packet → `PAUSE A′`.

## Validation
- `python3 scripts/gates/reference-transform-compare.py --selftest`: fixtures a, b, c, e, f, g, h, i fail and d passes.
- R3′ C1 verdict:
  - `liveRunsEqual`, `replayEqual` and `rngRun2Differs` are true;
  - `transformEqualsM9: true`;
  - `transformedFields` equals the R-2 list exactly;
  - `literalComponents ⊇ {ipc, traces}`.
- G2: the d150 and d500 transform-compare verdicts are green with the same predicates as δ = 0 (`transformEqualsM9` read against the cp1 δ reference).
- `git rev-parse m10-cp2` equals the verdict's harness SHA.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| None new; each transform traces to a P06/P06b/P07 ledger row. | — | — | — |

## Risks
- kpm-headers change through the rebuilt kpimon or agent (Medium/Low). That component has no enumerated transform, so it fails loudly and goes to the Failure Protocol; if the cause is a legitimate T-A field, it is a T3 (contract) question, not a silent transform.
- T drifts between the file rewrite and the compare (Low). There is a single implementation, `m9-transform.py`.

## Rollback
Tags are never moved. A red C1 is re-run only as a full fresh set after the cause is recorded and a change committed.

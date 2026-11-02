# Post-M9 realism goal: user rulings (2026-11-02)

Input to `ak:goal-warmup` for the contract in `brainstorm-261029-1824-GH-1-post-m9-realism-goal-contract.md` (candidate D).

## Guiding principle (user, 22:35 KST)

After the migration, the problems are fixed and comply with the official specifications. Old work is kept for historical checks (git history, tags, the committed M9 `reference/r3p/` and archived evidence). Legacy, non-compliant code is **not** kept alive in the code base: no compat profiles or legacy wire modes, because they slow maintenance and future development.

## Rulings

| # | Question | Ruling | Notes |
|---|---|---|---|
| R1 | δ = 0 reading (brainstorm Q1, defect #1) | **(a) SUB-1, hardened per kongming**: prove literal byte equality with `reference/r3p/` once, before any T-A wire change (AC8), and tag that commit. After T-A, ipc, traces, predictor records, scenario and schedule stay literal; transforms apply only to enumerated fields, with a negative fixture. | Compat profile (candidate A/F) rejected by the principle above. |
| R2 | kpimon measurement-time stamping (B3, Q3) | **Out for now.** | No in-scope consumer (R3′ windows by `ns3.seq`; QP is out); the harness queries Influx by wall-time range (`scripts/gates/agents-ns3-run.sh:161`). Revisit in the real-QP goal. |
| R3 | Codex run cap | **Not enforced.** Invoke Codex whenever necessary; disclose each run. | Makes brainstorm Q6 (do the brainstorm's runs count) moot. |
| R4 | KPM v03.00 | Readable via `zotero-cli` (item `F82PYZVK`). | Verified 2026-11-02: §7.3.2 (Event Trigger Style 1 sets the report period), §8.2.1.1.1 (Reporting Period, ms), §8.3.8 (Granularity Period = collection interval within a reporting period). Clears these three from defect #10. |

## Consequences to settle at warmup (not yet ruled)

1. **Switch defaults vs the principle.** Contract §2 makes every output-changing fix (T-C P6/P7/P9, `UseIdealRrc`) a switch whose default reproduces M9. Under the principle, the compliant behaviour should become the only (or default) behaviour after its checkpoint, with M9 behaviour kept only in history. Needs a ruling per item.
2. **P1 addressee, recommendation revised.** E2SM-RC v03.00 §8.4.6.4 (DC Secondary Node Change Control): the E2 node invokes "SN Change (only SN-initiated)". 3GPP TS 37.340 §7.2: the MN triggers an SN change "only for inter-frequency secondary node change"; scenario-zero runs every gNB on one carrier (`scenario-zero.cc:512,525`, 3.5 GHz). So the spec-consistent addressee is the **source en-gNB**, not the MN eNB recommended on 2026-11-02 21:xx.
3. **P13 (E2SM-RC Style 5) scope.** Moving an EN-DC UE between en-gNBs is an SN change / inter-SN PSCell change (TS 37.340 §10.5.1), which E2SM-RC models as Control Style 5 actions 3/4 (§8.4.6.3–8.4.6.4), not Style 3 action 1 (handover). Under the principle, P13 may need to move from "record only" into scope.

## Rulings, round 2 (23:46 KST)

| # | Question | Ruling | Notes |
|---|---|---|---|
| R5 | P11 gNB ID length | **32 bits.** gNB ID = ns-3 cellId; NCI = gNB ID (32) + constant 4-bit cell part. | RIC rendering checked, see below. |
| R6 | P1 addressee | **Source en-gNB.** | E2SM-RC v03.00 §8.4.6.3–8.4.6.4 (inter-SN change "only SN-initiated"); 3GPP TS 37.340 §7.2. |
| R7 | P13 (E2SM-RC Style 5) | **In scope.** Replaces Style 3 action 1 for moving an EN-DC UE between en-gNBs. | Action 3 vs 4 to settle at warmup. |
| R8 | Switch defaults (consequence 1) | **Yes**: after each fix's checkpoint, the compliant behaviour is the only behaviour; M9 behaviour survives only in history. | Applies to P6, P7, P9 and `UseIdealRrc` (the latter still subject to its probe, S-R). |
| R9 | Disk margin h | ~~h = 9 GiB~~ superseded by R11. | — |

### How the RIC renders the gNB ID (verified 2026-11-02)
- **e2term (RAN name / meid):** `buildRanName` → `translateBitStringToChar` (`ric-plt-e2/RIC-E2-TERMINATION/BuildRunName.h:58-117`, master `5aa396f`) shifts the BIT STRING's trailing unused bits to leading zeros and prints whole octets in lowercase hex. A gNB ID is therefore printed right-aligned: ID 2 → `…_00000002` for any length 25–32. en-gNBs get the prefix `en_gnb_` (`:150-157`). Live confirmation on the deployed L-release image: the agents send a 29-bit ID left-aligned (`ns3_e2_agent/src/e2ap-builders.cpp:110-113`) and the evidence shows `gnb_001_001_00000001` … `00000005`.
- **e2mgr (nodeb JSON `globalNbId.nbId`):** a binary-digit string of exactly the ID's bit length; live: `"nbId":"00000000000000000000000000010"` (29 chars) in `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/dev-p5/smoke/20261021T164639Z/e2mgr-nodeb.json`. With 32 bits it becomes 32 chars.
- **Consequence for the TS xApp key:** with 32 bits the meid suffix `00000002` equals the first 4 octets of the NCI `00000002 0|0`, so the substring match is exact. With 28 bits the NCI is `0000002 00|0`; the suffix `00000002` matches only when the octet before the NCI ends in a 0 nibble (e.g. PLMN `…10`), and the copied 10-digit key is then shifted by a nibble. The TS xApp parser still needs the N1 patch (`en_gnb_001_001_00000002` has 4 underscores; it counts 3).

### A1 interpretations
- (c) confirmed by data: IPC traces number samples from 0 (e.g. `evidence/ns3-pause-ric-reaction/20261022T022027Z/ns3run/e2-ipc-trace-2.jsonl`: 73 samples, seq 0–72).

## Rulings, round 3 (23:55 KST)

| # | Question | Ruling | Notes |
|---|---|---|---|
| R10 | E2SM-RC Style 5 action | **Action 3, PSCell change control** (§8.4.6.3), sent to the source en-gNB. | Covers intra-SN and inter-SN PSCell change; with one cell per gNB every change is inter-SN ("SN Change, only SN-initiated"). |
| R11 | Disk margin h | **h = 12 GiB, trip = 37 GiB** (SUB-H accepted; supersedes R9). | Matches M9's measured 12 GiB drop in 370 s (B2). AC4's script still computes and records the worst burst. |
| R12 | A1 interpretations (a)–(k) | **All ratified.** | As listed in `run-report-261029-0535-GH-1-m8-m9-deviations.md` §"Interpretations made under A1". |

## Status
All brainstorm open questions are ruled. Next: edit the contract text (kongming defects #1, #4, #5, #6, #7, #9, N1, plus R1–R12), then `ak:goal-warmup`.

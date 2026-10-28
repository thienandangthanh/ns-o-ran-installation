# M9 run report (template; filled in P10 from the M9 log and verdict)

Fill every `<...>` from `evidence/m9/<ts>/verdict.json`, `steps.tsv` and the runner log; never from memory. Contract: `goal-packet.md` (A1).

## Run

| Item | Value |
|---|---|
| Runner command | `scripts/run-to-m9.sh --harness-sha <F> [--run-prefix n]` |
| Harness SHA (frozen, P9) | `<F>` |
| Pins (`scripts/pins.conf`) | Testbed `c6d1434a`, ns-3 `ba954440`, oran-interface `96efc40e`, e2sim `2209995a` (verdict `pins`) |
| Start / end (UTC) / wall | `<start>` / `<end>` / `<s>` of the budgeted 20,199 s |
| Exit code | `<0>` |
| Step set (pre-registered) | `m0 m1 m2 m3 m4 m5 m6 m7 i0 r0 r1 i2 r2 r3p` = verdict `steps`: `<equal?>` |
| Top rung | R3′ (no substitution 4 record) — or R2 under substitution 4: `<which>` |
| Top rung C1 | `<evidence/r3p/<ts>>`: liveRunsEqual `<>`, replayEqual `<>`, rngRun2Differs `<>` |
| equalsReference | `<true>` against `reference/r3p/` (made from `evidence/r3p/20261028T044557Z` live1) |
| minHostFreeGb / watchdog | `<n>` GiB (≥ 25) / alive throughout `<watchdog-alive.json>`, trip 29 GiB, `free-series.tsv` peak growth `<GiB/s>` vs the budget's 0.0093 |
| substitution3Applied per rung | r0 `false`, r1 `false`, r2 `<true>`, r3p `<true>` (verdict `substitution3Applied`) |

## Per step

| Step | Status | Duration (s) | Timeout (s) | Evidence |
|---|---|---|---|---|
| m0 … r3p | `<pass>` | `<>` | from `scripts/m9-budget.json` | `<evidence dir>` |

## Recorded deviations (out of scope, not fixed; the post-M9 realism pass)

| Id | What this port does | Standard | Status in M9 |
|---|---|---|---|
| P1 | The TS xApp sends the handover control to the target cell's E2 node | 3GPP TS 38.300 §9.2.3; 3GPP TS 37.340 §10.5.1 | present |
| P2 | The agent sends 5 raw bytes (gNB id, cell id) in `e2nodeComponentRequestPart`, not an EN-DC X2 SETUP REQUEST | E2AP v03.00 §9.2.27; 3GPP TS 36.423 §9.1.2.31 | present |
| P3 | d = 0: controls apply at the next step, no whole-loop delay | decision D5 | present |
| P4 | UE ID `gNB-UEID` with the IMSI in AMF-UE-NGAP-ID, not `en-gNB-UEID` / `eNB-UEID` | E2SM common v07.00 §6.2.2.6 | present |
| P5 | Every agent registers as `gNB` with a Global gNB ID | E2AP v03.00 §9.2.6 | present |
| P6 | DL volume row sent as `QosFlow.PdcpPduVolumeDL`, REAL bytes per period | E2SM-KPM v03.00 §7.9.1; 3GPP TS 28.552 §5.1.3.6.1.1 | present |
| P7 | ns-3 puts an E-UTRA PDCP header on the EN-DC bearer | 3GPP TS 37.340 §4.2.2 | present; changes none of the N4 numbers |
| P8 | RAN function 3 (RC) is not announced in E2 Setup; the agents accept RC controls anyway (Stop A ruling 4) | E2AP v03.00 §8.2.4.3 | present |
| P9 | MN-hosted PDCP SDU volume credited to the en-gNB cell (`DRB.PdcpSduVolumeDL/UL`) | 3GPP TS 28.552 §5.1.2.1.1.1 (NRCellCU) | present; R3′'s predictor reads this counter |
| N5 | gNB agents send `%08X%02X` (5 bytes) as the TS xApp's cell key; key-length limit for other experiments | — | present |

## Descoping (user rulings, 2026-10-27)

- **S1:** R3 with real QP and the QP fork are deferred to a later goal; R3′ (harness predictor reading per-cell DL from Influx by sim time) is the top rung, with stop-at-R2 (substitution 4) pre-authorized.
- **S2:** the N4 counters and the UL flag stay as an opt-in feature; the QP-only checks (K18 dump, V5 window predicate, V6) are dropped.

## Substitutions (only these are allowed)

| # | Substitution | Applied in M9 | Evidence |
|---|---|---|---|
| 1 | `--outageThreshold=-1000` after the R0-config null-control run counted LTE outage switches | `<true>` (verdict `substitution1Applied`, `outageThresholdDb`) | `<r0 evidence>` |
| 2 | Do-nothing default RMR handler in the TS xApp (Testbed fork) | `<true>` (`substitution2Applied`) | `<r2/r3p evidence>` |
| 3 | TS xApp parses an A1 policy body sent as a JSON string under `payload` (Testbed fork) | `<true>` on r2/r3p, `false` on r0/r1 (TS xApp not in their control path) | `<>` |
| 4 | Stop at R2 when the R3′ dry run forms no schedule | `<not applied>`: the R3′ dry run formed a schedule (`scripts/gates/r3p-schedule.json`) | `evidence/r3p/20261028T041902Z` |

## Interpretations made under A1 (ratified at Stop B: `<ruling ref>`)

1. F09: an absent Influx token file passes the scrub only while provably no secret exists (no kubectl, or no Influx pod).
2. The R3′ persistence formula sends UEs toward the more loaded cell under CBR (anti-load-balancing); prediction quality is out of scope.
3. "Every seq 1..N" (P6 A1 V3) reads as N consecutive seqs 0..N−1.
4. R3′'s W was calibrated through R2's fixed-answer block on the R3′ prepare path.
5. The R3′ dry run ran in two stages (A: class; B: schedule).
6. Route owners of 12041/12042 differ between runs; they are recorded facts, not judged.

## Records

- R3′ C1: 167 checks, none failed (the 168th PASS line in its `gate.log` is the verdict line).
- Known record slips: `<list or none>`.
- Stale submodule gitlinks in the parent repo vs `pins.conf`: `<updated at the freeze, or disclosed here>`; `pins.conf` governs.
- tshark in `tools/tshark-kpm` (unpinned `debian:trixie-slim`): `<version at run>` (4.4.19 at P9).

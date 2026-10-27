# Brainstorm: does scenario-zero fit the TS, QP and AD xApps, and how should QP train? (2026-10-27 21:55 KST)

The user asked us to look back at the setup the TS, QP and AD xApps were originally built for before ruling on QP training. Sources:
- the researcher report `plans/reports/researcher-261027-2155-GH-1-original-ts-qp-ad-scenarios.md`;
- the Zotero item `79CU8L45` (Lacava et al., IEEE TMC 2024, §V);
- the local source of `ric-app-qp@381a824` and `ns-3-mmwave-oran@ba954440`;
- a replay of QP's training code (below).

## Bottom line
- None of the three xApps was built for an ns-3 scenario.
  - From the D release on, they were built around **VIAVI RIC Test** synthetic data: 13 sites × 3 layers (39 cells), 24 UEs, reports every 10 ms.
  - The use case was demonstrated only by replaying recorded files into InfluxDB, never as a live E2 loop.
- QP's design assumption is a **time-varying per-cell throughput series**. On its own bundled data it trains a model for every cell that carries traffic.
- Scenario-zero's constant-rate DL breaks that assumption.
- Neither the original VIAVI layout nor ns-O-RAN's traffic-steering scenario (scenario-one) can be reused as is within this goal.
- The real choice is between:
  - keeping scenario-zero and training on its start-up transient (B with A as fallback), or
  - adding an opt-in **variable-DL traffic flag** to scenario-zero, the way N4 added UL (S2).

## What the original setup was (verified)
| Item | Original O-RAN SC setup | Ours (scenario-zero, R3 config) |
|---|---|---|
| Data source | VIAVI RIC Test replay; `insert.py` loops `src/cells.csv` into InfluxDB (`ric-app-qp/insert.py`: "temporary … until data will be coming through KPIMON") | Live ns-3 → E2 agents → kpimon → InfluxDB |
| Cells | 13 sites × {B2, B13, N77} = 39 cells; 14 to 16 carry traffic (14 by my count of non-constant DL) | 2 mmWave gNB cells plus 1 LTE eNB (excluded from QP) |
| UEs | 24 in the VIAVI config (10 pedestrians, 1 car, 3 train passengers, 10 waiting); AD `ue.csv` has 20 | 6 (3 per gNB) |
| Mobility | Manhattan paths at speeds 0.5 to 20 | RandomWalk2dOutdoor; no automatic handover (NoAuto; outage threshold −1000 dB) |
| Report period | 10 ms | 100 ms |
| Per-cell DL | Varies; `pdcpBytesDl/Ul` are cumulative ramps (≈3.7 per step, std 0.33 of the step) | **Constant**: 8371 or 4186 kbit in 97 of 100 samples, after a 3-sample start-up ramp |
| QP training read | `limit=4800` rows (stock); NIST's patch: Flux `range(start: -1600ms)` of wall time | P7 commit 4 plan: 16 sim steps ending at the trigger |
| AD | IsolationForest on UE reports; sends 30003 to TS | Out of scope (contract); the pacer triggers TS instead |

ns-O-RAN's own traffic-steering scenario, scenario-one (Lacava TMC 2024 §V, `scratch/scenario-one.cc`):
- 1 eNB + 7 gNBs, with 7 UEs per gNB (49 UEs);
- random walk at 2 to 4 m/s;
- 100 ms reports;
- DL as a mixture of 4 traffic models, 25 % of UEs each: full buffer 20 Mbit/s, and bursty on/off at 3 Mbit/s, 0.75 Mbit/s and 0.15 Mbit/s with exponentially distributed on/off times.

It drove WINES's own reinforcement-learning traffic-steering xApp, not the O-RAN SC TS + QP pair. Scenario-zero is a smoke-test scenario ("New test scenario #99", 2022-11), with full-rate CBR DL for every UE.

## Replay of QP's training (evidence)
I wrote a script that reproduces `qptrain.py`: `constant()`, the ADF test, the differencing, the 1–19 lag search and the VAR fit. I ran it in a scratch virtual environment with the N2 pins (pandas 1.5.3, numpy 1.26.4, statsmodels 0.14.6).
- Script: `/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/91ee888f-ce20-4fe0-8dd5-7cf35ce98b6e/scratchpad/qp_train_probe.py`
- Data: QP's own `src/cells.csv` and the N4 UL-on IPC traces (`evidence/n4/20261027T031836Z/runs/ulon/trace/e2-ipc-trace-{2,3}.jsonl`).

| Input | Result |
|---|---|
| QP's own `cells.csv`, 39 cells | 14 trained models (lags 1 to 18); 25 all-zero cells skipped by `constant()`; **no crash** |
| Ours, 16-step window ending at T ≤ 17 | Model trained (lag 1) for both gNB cells |
| Ours, 16-step window ending at T ≥ 18 | `adfuller` **raises `ValueError: x is constant`**, which is uncaught, so the QP process exits |
| Ours, history [0, T] for any T up to 99 | Model trained, but only because seqs 0–2 hold the start-up ramp |

Two new facts from the QP source (`src/main.py:115-117`, `src/prediction.py`):
- **Training happens once per cell**, on the first request that names the cell (`train_model` skips the cell if a model file exists).
- Later forecasts run `constant()` and `model.forecast` but never ADF. So under B the crash risk sits only at the first trigger. Both gNB cells appear in every UE's serving-plus-neighbour list, so both train at that trigger. With one QP pod restart per run (N3), this repeats identically in every run.

This makes B less fragile than kongming-1300 assumed: later trigger windows do not re-run ADF. It does not make B meaningful: the model learns from 0, 0, 7534, then a flat line, so its forecasts follow the start-up transient, not load.

## Options
| Option | What changes | Assumption it depends on most | Fails first when | Cost | Needs a ruling? |
|---|---|---|---|---|---|
| **B + A (fallback)** | Nothing in ns-3. The first R3 trigger is at seq ≤ 17 (B). If the in-image proof (Codex F03) fails, training reads [0, T] (A) | A model learned from the start-up ramp is enough for "≥ 1 QP-driven handover" | The dry run finds no trigger where QP's forecast picks a non-serving cell (R3 vacuous, T3) | Lowest: P7 as planned, plus the F03 in-image proof | A needs one; B does not |
| **S2: variable-DL flag in scenario-zero** (`--dlTrafficModel=mixed`, opt-in, default off) | Port scenario-one's 4-class DL mixture into scenario-zero behind a flag, like N4's `--enableUlTraffic`. Re-register `r3Config.dl`. Add a DL clause to the V5-style window predicate, so `constant()` is False and DL varies in every window. Calibrate once | Flag-gated on/off apps with exponential durations stay deterministic per RngRun, and the default free-run digest is unchanged (the same proof as N4 V2) | 6 UEs give too little load variation for QP to ever pick the other cell (also T3), or the bursty load breaks W/T_ctl calibration | Medium: one ns-3 commit and pin bump, a V2 (flag off = old digest) gate, a calibration run, a dry run; about the size of N4 | Yes: changes the pre-registered `r3Config.dl` (kongming's option D) |
| **S3: switch scenario** (scenario-one, or a VIAVI-like layout) | A new topology with 8 E2 nodes and 49 UEs (or 39 multi-layer cells) | All S0/S1/N4 work (D4, N4 counters, UL flag, pacer, agents, D10) ports to the new scenario, and R0–R2 re-prove determinism | The very first port: every rung's references and calibrations are invalid; disk and wall time grow | High: re-does M8 work; the contract's out-of-scope list already excludes even scenario-zero's default 12-UE config | Yes: a contract change |

C (catch ADF/VAR errors, persistence forecast) stays what kongming advised: crash-proofing with a test that it never fires for an R3 cell. It is not a training option.

## Trade-offs
- **B + A** proves the plumbing (TS xApp → QP → RC → ns-3 handover, deterministically) and nothing about prediction. The contract already lists "QP prediction quality" as out of scope, so this is within the contract. A reviewer who reads the forecasts, though, will see that QP learned only from a start-up artefact.
- **S2** makes R3 exercise QP the way its designers assumed (a varying per-cell series), using traffic models from the ns-O-RAN traffic-steering paper rather than invented ones. It costs one more N4-sized cycle before P7, and it changes a pre-registered value, so it needs your ruling.
- **S3** is the realism pass, not M9 work. Its worst case is redoing M8.

## Recommendation
- Smallest option that meets the contract: **B with A pre-authorized**, plus C's guard. It is cheapest to abandon: if the F03 proof or the dry run fails, S2 is still open.
- **Better approach, if R3 should mean something about QP:** S2. The evidence:
  - QP trains on every traffic-carrying cell of its own data and fails on ours only because our DL is a CBR flat line;
  - S2 reuses scenario-one's published traffic mix (Lacava TMC 2024 §V);
  - it follows the N4 pattern already proven: opt-in flag, V2 digest unchanged, pre-registered, calibrated once.

  Switching costs one ns-3 cycle before P7 (no VM or snapshot risk beyond N4's).
- Defer S3 to the post-M9 realism pass, next to P1–P7.

## Brainstorm contract (for the ruling)
- **Outcome:** a ruled QP training basis that lets P7 step 6 (in-image tests) and step 9 (dry run → `r3-schedule.json`) proceed without a crash or a T3, with the choice pre-registered in phase-07 before step 6.
- **Constraints:**
  - free-run stays the default, and M5–M7 and R0–R2 digests stay unchanged;
  - determinism holds (3 live runs byte-equal; `--RngRun=2` changes the digest);
  - no test is weakened;
  - each technical choice is checked against the specs;
  - no VM work until the goal is re-issued.
- **Non-goals:** QP prediction quality, AD, switching the topology (S3), and the realism items P1–P7.
- **Acceptance:**
  - the ruling is recorded in a `decisions-…` report and in the phase-07 amendments;
  - for B/A: the in-image F03 proof (model file per R3 cell, deterministic forecasts, ≥ 1 applied QP-driven handover);
  - for S2: additionally, the flag-off V2 digest is unchanged, and a pre-registered DL window predicate passes on calibration.

## Unresolved questions
1. B with A pre-authorized (no scenario change), or S2 (variable-DL flag) before P7?
2. If S2: is scenario-one's 4-class mix acceptable as is (full buffer 20 Mbit/s and bursty 3, 0.75 and 0.15 Mbit/s, 25 % of UEs each, exponential on/off), given that 6 UEs give at most 1–2 UEs per class?
3. The VIAVI units for `pdcpBytes` and speed are unknown (the manual is not public). This does not block either option.

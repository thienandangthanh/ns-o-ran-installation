# Kongming counsel: P8′ step 1, the R3′ predictor design and its pre-registration (2026-10-28 12:20 KST)

Advisory only; never user approval. Runtime: Claude Opus 5.5 (the caller's opus routing).

Scouted:
- harness `02c6b81` (worktree);
- forks at the pins (`ns-3` ba954440, `oran-interface` 96efc40e, Testbed c6d1434a);
- the TS xApp source `ric-app-ts@19e169b` (scratchpad clone);
- the host evidence `r0/20261027T035415Z` (c8null, UL off, N4 pins) and `m6/20261027T032457Z` (Influx export).

## TL;DR
- **Go on the default design, with three corrections.**
  1. N6, the predictor and the stub load run in a new pacer **`prepare` hook**, before the trigger's `t0`. They must not run inside the trigger command: inside it, they would inflate L and use up the absence window W.
  2. The stub log is saved before every `PUT /table`, because each PUT wipes the log.
  3. The dry run gets a **stage B** (a scripted first handover), because a null-control run cannot predict the post-handover trigger.
- **Formula: use persistence of the per-cell 16-seq DL volume, not per-UE share.** Per-UE share is vacuous by construction under CBR: 2,092.75 vs 2,093 kbit, so it ends in substitution 4 every time. Persistence is the concept the user approved ("persistence forecast", `brainstorm-261027-2241` §5 B).
  - It crosses the threshold with a ratio of 2.0 against 1.1.
  - It yields this schedule: n1 = (step 20, IMSI 3, none), h1 = (step 30, IMSI 1, handover to cell 2), m1 = (step 50, IMSI 1, decision from stage B; expected none).

## Reframed problem
The real decision is how to make "KPM → Influx → decision → RC → handover" deterministic and pre-registered without changing the TS xApp, the stub's role or the token boundary.

Two hidden constraints decide it:
- **The pacer's timing semantics.** The trigger's L and W both count from the command's start.
- **The dry run cannot observe its own consequences.** A null-control run has no handover, so it has no post-handover data.

Non-goals:
- prediction quality (out of scope);
- UL;
- a scenario change (S2 and S3 are deferred).

## 1. Go/no-go and the data flow

### Go/no-go
**Go: VM-side predictor in the harness, stub unchanged, token stays in the InfluxDB pod.**

Rejected designs:
- a predictor inside the stub pod (it would need the token in a pod: T7);
- a host-side predictor over ssh (adds latency, and the run dir is on the VM);
- a predictor that reads IPC directly (bypasses Influx, so it breaks the contract).

### Verified facts the design rests on
| Fact | Where |
|---|---|
| The trigger's `t0` is taken before `subprocess.run`. The absence wait is `t0 + W`, and L = controlRx − `t0`. A slow trigger command therefore inflates L and can use up all of W; a late control is then refused at T+1 instead of failing the negative. | `scripts/gates/pacer.py:266`, `:278`, `:287` (also `:194`) |
| After `steps T`, ns-3 waits for `go` with no timeout. T_gate applies only while a step is missing. | `oran-interface/model/e2-control-hub.cc:509-517` |
| The agent forwards the KPM indication **before** it sends `step T`. | `ns3_e2_agent/src/main.cpp:122-123` |
| The IPC trace is written and fflushed before the enqueue (`e2-ipc-emitter.cc:121`, `:231-232`). The ledger is fflushed per line (`e2-control-hub.cc:357-360`). Both can be read live at barrier T. | as listed |
| `PUT /table` resets both the counters **and the log**. | `tools/rmr-peer/stub-qp-rmr-peer.py:78-79` |
| TS xApp decision logic: | `ts_xapp.cpp:213-236`, `:689-728` |
| - the values are stored in `unordered_map<string,int>`; | |
| - the first Uint key is taken as serving; | |
| - the highest cell is taken over **all** cells, serving included, on a strict `<`; | |
| - `float thresh = serving × (th/100.0)`; | |
| - it hands over if `highest > serving + thresh`; it uses DL only. | |
| kpimon's `control.go` holds the Influx token as a literal (sed), so the kpimon tree and image on the VM contain it. | `install_xapp_kpi_monitor.sh:158` |

### Per-trigger flow at step T (who waits on whom)
1. **ns-3 reaches seq T.**
   - Every emitter writes its trace line T and sends sample T.
   - `StepBarrier(T)` sends `ready{T}` to the pacer.
2. **Each agent** encodes sample T, sends the indication (SCTP → e2term → kpimon → Influx, asynchronously), then sends `step{T}`.
3. **ns-3** waits for every agent's `step{T}`, at most T_gate, then sends `steps{T}`. From here it blocks until `go{T}`.
4. **The pacer** waits for `steps{T}` (at most T_ctl) and then runs **`prepare`** (`prepareTimeoutS`). The prepare script `r3p-prepare.sh` does three things:
   1. **N6** (`check-n6-influx-window.py`, §3):
      - polls Influx through a `_flux`-style in-pod query (at most `n6DeadlineS`);
      - reads the IPC traces up to seq T and the ledger;
      - writes `rd/r3p/window-T.json`, the certified rows (integers only), and `rd/r3p/n6-T.json`;
      - exits 1 on failure.
   2. **Predictor** (`r3p-predictor.py answer`):
      - takes as input **only** that certified file (no second read, so no gap between check and use);
      - writes `answer-T.json` and appends to `predictor-records.jsonl` (no wall time);
      - asserts that the mirrored decision equals the scheduled decision. On a mismatch it exits 1, so the run fails fast with the reason "observations differ from the dry run".
   3. **Stub:**
      - `GET /log` → `rd/stub-log-part-<k-1>.json`;
      - `PUT /table {"predictions":{"<imsi>":[answer]}}`;
      - assert that the response is `{"ues":["<imsi>"],"entries":1}`.

   A non-zero exit or a timeout → the pacer aborts with "step T: prepare …".
5. **The pacer** sets `t0` and runs the trigger `send-rmr.sh <port> anomaly <imsi>`: 30003 goes to the TS xApp.
6. **The TS xApp** sends 30000 to the stub. The stub answers 30002 from its one-entry table.
7. **The TS xApp decides.** On a handover:
   - gRPC → rc → E2 control to the **target** gNB's agent (P1) → IPC → ns-3 `controlRx{T}`;
   - the pacer waits for 1 control within T_ctl. For a none decision, it requires 0 within W.
8. **`go{T}`.** ns-3 then runs `Apply(T)` (D4) and writes the ledger line with `rxSeq` T.

### Pacer hook (schedule hook, not a harness-side loop)
Add an optional field to a schedule entry: `"prepare": {"cmd": [...], "timeoutS": s, "mayFail": false}`.

Semantics in `step()`:
1. Any `inject` first.
2. Wait for `steps k`.
3. Run `prepare`, recording `prepareRc`, `prepareWallS` and `prepareOut`.
4. On failure: abort, or with `mayFail` record and continue.
5. Then continue with `trigger`/`triggers`, or send `go` when the entry has no trigger.

L and W are unchanged because `t0` follows `prepare`.

`pacer-selftest.py` cases to add:
1. order: `steps` rx, then prepare, then trigger, then go;
2. L excludes a 0.5 s prepare;
3. prepare rc ≠ 0 → abort naming "prepare";
4. prepare timeout → abort;
5. `mayFail` → no abort;
6. a prepare-only entry → go.

The existing cases 1–4 prove that R0–R2 schedules, which carry no `prepare`, behave as before.

The harness-side loop is rejected: it is a second process plus file handshakes, with races and no gain.

## 2. Pre-registration list (commit before any R3′ VM run)

### The arithmetic decides the formula
Data: UL off, N4 pins, `r0/20261027T035415Z/runs/c8null`. Node 2 lists IMSIs {3,4,5,6} with DL 8371; node 3 lists {1,2} with DL 4186. Both hold in 97 of 100 samples. The ramp is seq 0 (no UEs), seq 1 (DL 0), seq 2 (7534/3767). seqs run 0–99. The per-UE value is 2,092.8 kbit per 100 ms (200 PDUs × 1,308 B). A steady 16-seq window gives V2 = 133,936 and V3 = 66,976.

| Formula | UE on cell 3 (IMSIs 1, 2) | UE on cell 2 (IMSIs 3–6) | Verdict |
|---|---|---|---|
| Per-UE share V/n (caller's example) | 4186/2 = 2,093 vs 8371/4 = 2,092.75 | 2,092.75 vs 2,093 | Ratio ≈ 1.0001 → none everywhere |
| Share "as if the UE joined": V_d/(n_d+1) | serving 2,093 vs 8371/5 = 1,674.2 | serving 2,092.75 vs 4186/3 = 1,395.3 | Never a handover, so **substitution 4 by construction** |
| Joined, with the UE's own volume added: (V_d+ū)/(n_d+1) | 2,093 vs 2,092.8 | 2,092.75 vs 2,092.9 | Ratio ≈ 0.9999 / 1.0001 → none, and an ε-tie (fragile) |
| **P: persistence, Σ of 16 seqs per cell** | serving 66,976; bound 66,976 + 6,697.6 = 73,673.6 < 133,936 → **handover to 0000000202** (ratio 1.9998) | serving 133,936 is the highest → **none** (other/serving 0.5001) | Crosses with a wide margin |
| E: inverse post-move load (alternative) | L3 = 66,976 vs L2′ = 133,936 + 33,488 → none (0.40) | L2 = 133,936 vs L3′ = 66,976 + 33,484 = 100,460 → handover to 3 (1.333) | Crosses, but it is a new policy |

Under unsaturated CBR, any "the UE's share of the measured volume" equals the CBR rate in every cell. Only a load proxy can cross the threshold.

Recommend **P**:
- it is the user-approved concept;
- it has no free parameters;
- it is QP's I/O contract with a persistence model;
- it repeats R2's proven handover IMSI 1 → cell 2.

Record honestly that under CBR the per-cell volume is a proxy for the UE count. That is acceptable, because prediction quality is out of scope.

Post-handover belief under P (stage B measures it):
- after IMSI 1 moves 3 → 2, cell 2 = 16 × 10,464 = 167,424 and cell 3 = 16 × 2,093 = 33,488;
- IMSI 1, now serving on cell 2, gets **none** (0.2). Its decision flips from h1's handover, which is the membership demonstration;
- IMSI 2 would still hand over (5.0).

### `scripts/gates/r3p-scenario.json` (draft; every value is configuration, none comes from the dry run)
```json
{
 "config": {"nodes": "enb:1,gnb:2,gnb:3", "cli": "R2 radio config (--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --outageThreshold=<rung-config>)",
            "RngRun": 1, "enableUlTraffic": false, "periodS": 0.1, "samples": 100},
 "threshold": 10,
 "cells": {"2": "0000000202", "3": "0000000303"}, "excludedNodes": [1],
 "imsis": [1, 2, 3, 4, 5, 6],
 "counter": {"measurement": "cellMetrics", "field": "DRB.PdcpSduVolumeDL", "influxType": "long",
             "cellKey": ["ns3.nodeId", "ns3.seq"], "ueKey": ["ns3.nodeId", "ns3.seq", "ns3.imsi"]},
 "window": {"length": 16, "last": "T"},
 "formula": {"id": "persistence-window-sum-v1",
             "dl": "for each gNB cell c: sum of DRB.PdcpSduVolumeDL(c, s) for s in [T-15, T] (integer kbit per 1.6 s)",
             "ul": 0, "order": "serving gNB cell first (the gNB whose UeMetrics row at seq T lists the IMSI), then the others by ascending nodeId",
             "bounds": "0 <= dl <= 2147483647 (the TS xApp stores int), else fail closed", "ueId": "decimal IMSI string"},
 "decisionMirror": {"source": "ric-app-ts@19e169b src/ts_xapp/ts_xapp.cpp:689-728", "handoverIff": "10*max_other_dl > 11*serving_dl"},
 "margin": {"handoverEligibleIff": "20*max_other_dl >= 23*serving_dl", "noneEligibleIff": "20*max_other_dl <= 21*serving_dl"},
 "domain": {"rampGuard": 5, "tailGuard": 10, "tLo": 20, "tHi": 89,
            "rule": "tLo = rampGuard + length - 1; tHi = samples - 1 - tailGuard; every IMSI at every T"},
 "scheduleTemplate": {
   "n1": {"step": 20, "slot": 10, "decision": "none", "imsi": "lowest none-eligible IMSI in stage A at the first slot step that has one"},
   "h1": {"step": 30, "slot": 10, "decision": "handover", "imsi": "lowest handover-eligible IMSI in stage A, same slot rule"},
   "m1": {"offset": 20, "slot": 10, "imsi": "h1's", "decision": "stage B's eligible decision at that step"},
   "stageB": {"inject": "h1's control at h1.step via the target gNB (P1)", "observeFrom": "h1.step + 16"}},
 "observationChange": {"mode": "RIC-free predictor replay on each live run's certified windows",
   "transform": "swap DRB.PdcpSduVolumeDL between gNB nodes 2 and 3 at every seq of the window; membership unchanged",
   "cases": {"h1": "none", "n1": "handover"}},
 "n6": {"deadlineS": 20, "pollS": 0.5, "settleSeqs": 1, "expectedCells": [2, 3]},
 "prepareTimeoutS": 30
}
```
More values to pre-register:
- **Counter and UL.** Read only `DRB.PdcpSduVolumeDL`; UL is off. This keeps R2's radio config verbatim, and the TS xApp ignores UL (`ts_xapp.cpp:688-689`). In UL-off runs the DL key is present with UL = 0 (`digest-run.py` N4Drop). `ul` is the constant 0, as in R2.
- **Window.** Keep 16 seqs ending at T inclusive. It mirrors NIST's 1600 ms, and seq T must be in Influx anyway for the UE rows.
- **Influx = IPC "full".** Define the seq set as every IPC sample seq of gNB nodes 2 and 3 (0–99). The M6 export at the N4 pins already shows seq 0–99, no duplicates, field type `long` (`m6/20261027T032457Z`).

### `rung-config.json`
Add `"r3pConfig"` with:
- `W_s` (null until step 5; its provenance must name `evidence/r3p/`);
- `prepareTimeoutS` 30 and `n6DeadlineS` 20, each with provenance;
- the scenario and schedule paths with their evidence dirs.

Add `schedules.r3p`. Leave `deadlines.W_s` and `a1_threshold` alone; `gate-r2` `cfg_ok` reads them.

The gate-r3p `cfg_ok` checks:
- `W_s` provenance names `evidence/r3p/` (except in the calibrate and dryrun modes);
- threshold = scenario threshold = 10.

### Spec check (step 2)
Read 3GPP TS 28.552 V20.2.0 §5.1.2.1.1.1 (`5SZUBP6M`) through zotero-mcp and confirm three points:
1. It counts the DL PDCP SDU bits delivered to the lower layers **per granularity period** (additive over periods), so a 16-period sum ÷ 1.6 s is the mean cell PDCP DL throughput.
2. The measured object is NRCellCU. This is already recorded as **deviation P9** (MN-hosted PDCP credited to the en-gNB cell).
3. The unit was settled at P6 (INTEGER, kbit, E2SM-KPM v03.00 §7.9.1).

Add one ledger row: "TS xApp predicted-throughput field: no 3GPP or O-RAN definition. The persistence mapping is a harness policy, not a measurement." I expect no new deviation, so no T4.

## 3. N6 certification (`check-n6-influx-window.py`)
**Inputs:**
- one Influx read, two `_flux` queries (cell and UE): `range(start: 0)` on the run's fresh bucket, filter the measurement and the needed fields **before** `pivot(rowKey:["_time"])`, then filter `ns3.seq >= T-15`. There is no upper bound, so stray seqs stay visible;
- the IPC traces up to seq T;
- the ledger.

**Pass iff all of the following hold:**
- **(c1) Cells.** For n ∈ {2,3} and every s ∈ [T−15, T]: exactly one cellMetrics row (n, s); `DRB.PdcpSduVolumeDL` present with `#datatype long`; its value equals IPC `/cell/cuUp/DRB.PdcpSduVolumeDL` (INTEGER rule).
- **(c2) Nothing past T.** No row of any node has seq > T (K2).
- **(u1) IPC membership.** At T, the IMSI is listed by exactly one gNB node s.
- **(u2) Influx membership.** The UeMetrics rows (n, T, imsi) over the gNB nodes are exactly {s}, with no duplicates. Influx serving = IPC serving.
- **(h) No handover in progress.** For the IMSI's applied ledger lines (all have `rxSeq` < T at barrier T), the last one has target node = s and `rxSeq` ≤ T − 1. Refused lines are ignored. A failed RRC after an applied line therefore fails N6, which is what we want.

**Polling and evidence:**
- Poll every 0.5 s until pass, at most 20 s.
- Write the certified integers and the verdict. The poll count and wall time go to a separate `timing-T.json`, which is never digested.
- eNB rows are never read.
- In dry-run "observe" mode, u1/u2/h run for **all** IMSIs at T, because every IMSI is a candidate.

**Beyond the contract's wording (deliberate):**
- Value equality in c1 makes each window "Influx = IPC" at certification time. Any c1 failure would also fail V3, so this fails earlier and never spuriously.
- **Influx = IPC, full (V3, `r3p-checks.py influx-ipc`, end of run).** For nodes 2 and 3, the set of Influx keys (n, seq) equals the set of IPC seqs (0–99); each key has exactly one row, type long, value equal to IPC; no node-1 row carries the field. Reuse `read_rows`, `expect` and `same` from `tools/e2-evidence/influx-vs-trace.py` by path import (the `digest-run.py` pattern).

## 4. Dry run: stages, classifier and schedule formation
### Stage A
`gate-r3p --mode dryrun --stage a`:
- R3′ config with the RIC up: rc_ric_reset, capture, agents subscribed. The TS xApp is not needed.
- Pacer schedule: one prepare-only "observe" entry (`mayFail: true`) at every T ∈ [20, 89]. Each runs N6 for all IMSIs and records the window.
- Post-run: the full Influx = IPC check, and 0 HandoverStart rows.
- Commit stage A's classification (h1 chosen) before stage B.

### Stage B
`--stage b`:
- The same, plus the pacer `inject` of h1's control at h1.step (viaNodeId = target gNB, the replay mechanism).
- Observe at T ∈ [h1+16, 89].

Equivalence to the live run: the live h1 control is applied at the same barrier with the same (via, imsi, target). The C1 replay equality already shows that controls injected this way reproduce the IPC. As a determinism check, the live m1 window must equal stage B's window at the same T.

### Classifier
`r3p-predictor.py classify` (or `r3p-dry-run-classifier.py` importing the predictor; keep each file under ~200 LOC). The first matching class wins:
1. **invalid**: an N6 failure at any (T, IMSI) of a domain that ran, a stage's Influx ≠ IPC, or a missing or duplicate row. Never drop a candidate → Failure Protocol.
2. **substitution 4**: stage A valid and **zero** candidates with the exact decision "handover" (any margin). Commit `r3p-substitution4.json`.
3. **T3**: a handover decision exists but n1 or h1 has no eligible IMSI in its slot (for example, every IMSI hands over, or the handovers lie only in the margin band); or stage B is valid but m1 is not eligible.
4. **schedule formed**: write `r3p-schedule.json` and commit it before step 5.

`r3p-schedule.json` uses R2's trigger shape: step, imsi, kind, predictions = the expected answer, via, key, targetCell, expect. Add an expected decision per trigger and the stage A/B evidence dirs with the scenario sha256.

Expected under P:
- n1: (20, 3, none);
- h1: (30, 1, handover, key 0000000202, via 2);
- m1: (50, 1, none, serving key 0000000202 first).

## 5. `--reference`, determinism, T7, fixtures
### `--reference <dir>`
- Valid only with `--mode c1`, in gate-r3p and gate-r2. It adds a check, and gate-r2's c1, single and calibrate judgement stay unchanged.
- **Check order:**
  1. `sha256sum -c <dir>/SHA256SUMS`.
  2. `digest-run.py runs/live1` vs `<dir>/equal/digests.json` on ledger, ipc, traces and extra. C1 already proves live1 = live2 = live3.
  3. For r3p, also compare the sha256 of `predictor-records.jsonl`, `r3p-schedule.json` and `r3p-scenario.json`.
- **Outputs:**
  - `reference-compare.json`;
  - fact `equalsReference`;
  - `recorded/` (image IDs) is diffed and reported, never judged (P9 K8).
- Do **not** add the predictor records to `digest-run.py` `EXTRA_EXPECTED` (`:48`). It is a fixed tuple, and adding to it would break R0–R2. Compare them in r3p-checks instead.

### Determinism risks and mitigations
| Risk | Mitigation |
|---|---|
| kpimon out-of-order or late writes | N6 polls; the predictor uses the certified snapshot only |
| Influx latency | Outside L and W (prepare comes before `t0`); deadline 20 s → abort, never a degraded answer. The dry run and the calibration record the N6 wait |
| Wall clock | No `_time` filter (`range(start:0)`, fresh bucket); records carry no wall time; the stub's `t` is never digested |
| Duplicate or colliding points (kpimon has no tags, so the same `_time` overwrites) | Exactly-one-row and IPC equality fail closed |
| Float field | `#datatype long` is required |
| The TS xApp's float threshold | Margin band; r3p-checks asserts that the live TS xApp decision equals the mirror on every trigger |
| Stub log wiped per PUT | `GET /log` before each PUT; concatenate in step order |
| Stub pod IP | Resolve once per run; a changed IP makes the PUT fail → abort, plus the RestartCount check |

### T7 (token)
- Every query goes through a single-quoted in-pod `sh -c` (as `_flux`/`_influx` do). The argv holds only the Flux text, the pod name and the stub IP.
- Raw CSV is parsed and deleted; only integer JSON is kept.
- The prepare script must **not** source anything that calls `gate_init`, because that would create a new evidence dir.
- Never run `influx auth|config`, `env` in the pod, `kubectl get secret`, `describe` the Influx pod, or read `influxdb_auth_token.json` from the predictor or N6.
- Never copy the kpimon tree, diffs or images (they hold the literal token).
- Run the existing exact-secret scan (`influx-dump.sh` checker) over `rd/r3p/` at the end of each run, fail-closed.
- Fixtures are synthetic only (the repo is public).
- The reference holds digests, the schedule and the scenario only.

### Fixtures
- **V3 (`r3p-checks.py`):** a pass case. Fail cases:
  - a missing seq;
  - a duplicate (node, seq);
  - an eNB row used;
  - a `double` field;
  - a 30002 payload that is formula +1;
  - serving not first;
  - a lowercase key;
  - a non-decimal ue-id.
- **V4 (N6):** a healthy disjoint membership case (node 2 lists 3–6, node 3 lists 1–2). Fail cases:
  - a missing UE row at T;
  - the UE row at the wrong node;
  - an IMSI listed by both gNBs;
  - a missing cell row;
  - a duplicate cell row;
  - a row with seq > T;
  - Influx DL ≠ IPC;
  - a handover in progress (an applied line at `rxSeq` T−0, or the target not yet listing the IMSI).
- **V9a (classifier):**
  - a missing row inside the only handover-producing windows → invalid;
  - an empty domain → refused by `lint.sh` (`r3p-predictor.py lint`: tLo ≤ tHi, IMSIs non-empty, template steps inside the domain, m1 ≤ tHi);
  - a complete domain with no handover → substitution 4;
  - every IMSI handing over at n1's slot → T3;
  - handovers only in the margin band → T3;
  - stage B m1 not eligible → T3;
  - a stage B N6 failure → invalid;
  - the happy path, synthetic 8371/4186 → the expected schedule.

## 6. Underspecified or T3/T4-forcing items in phase-08b
1. **Post-handover trigger.** Step 4's single null-control run cannot classify m1. Amend step 4 to stages A + B before the dry run; this is a plan edit within the contract. Without it, m1's expected outcome is a belief, so a red C1 or a T3 is likely.
2. **Trigger-embedded prepare.** If it is not specified as a pre-`t0` hook, the natural implementation (all work in the trigger command) corrupts L, W and the negatives.
3. **Stub log reset.** Record "stub unchanged: save the log before each PUT" (step 1 asks for this reason).
4. **R2's checkers are IMSI-scoped for negatives** (`r2-checks.py` `expect`/`wire`: "no ledger line or request for the IMSI"), and `d7` requires both gNBs as targets (`:185`). m1 reuses h1's IMSI, and every CBR-consistent formula targets one gNB only. r3p-checks needs step-scoped negatives (imsi, afterSeq or step) and a target-addressed-only D7. This is not a weakening: the contract's D7 for R3′ is "target-addressed (P1)". `r2-checks stub`, C9 and KPM-moves are reusable as they are.
5. **W calibration.** The predictor cannot produce 25 handovers. Pre-register the calibration as R2's fixed-table block run through the R3′ path:
   - prepare = N6 plus a per-trigger PUT of the fixed answer;
   - `W = max(1 s, 3 × L_max)`, with p99.9 equal to the max at n = 25.
6. **Domain constants.** "First full window after the ramp" needs a number. Use rampGuard 5 (configuration; the observed ramp is 3) and tailGuard 10; commit them before stage A.
7. **Boundary classification.** Define it now (margin band; T3, not substitution 4) so a classifier argument cannot become a T3 later.
8. **`predictorDrivenApplied`.** Define it as applied ledger lines whose (imsi, `rxSeq`) is a scheduled handover trigger and whose target = the argmax key of the predictor's answer.
9. **pacer.py changes affect R0–R2 at M9.** The self-test covers the old paths. As cheap insurance, run one `gate-r2 --mode single` after the hook lands; otherwise P10 is the first real test.

## What to avoid
- Per-UE share formulas: they guarantee substitution 4.
- Changing the formula after stage A (T3).
- Choosing IMSIs or steps by eye. Only the template rule is allowed.
- Running N6 or the predictor in the trigger command.
- A second Influx read in the predictor.
- Wall-time windows (`range(start: -…)`).
- Putting the predictor in a pod.
- Raising `n6DeadlineS` or W blindly (T3).
- Reusing `r2-checks expect/wire/d7` for R3′.

## Alternatives and trade-offs
- **E (inverse post-move load):** it is load-balancing semantics, a reviewer finds it more intuitive, and its margin is still 1.33. But it is a new policy invented after seeing the data, and it adds a ū estimate. Take E only if the user prefers it; it is a re-pre-registration, not a contract change.
- **Run-time expectations (prepare writes the expected count, the pacer reads it) instead of stage B:** it saves one run. But it is a bigger pacer change, and m1's outcome would no longer be pre-registered. Weaker; not recommended.
- **UL on:** it exercises N4 in the loop. But it doubles the N6 and V3 scope, changes the radio config away from R2's proven one, and the TS xApp ignores UL. Not worth it.

## Work checklist
1. Amend phase-08b:
   - step 4 → stages A/B;
   - calibration = fixed table through the R3′ path;
   - an r3p-specific D7 and step-scoped negatives;
   - stub unchanged, log saved before each PUT.
2. Zotero read of 3GPP TS 28.552 §5.1.2.1.1.1; ledger rows.
3. Commit `r3p-scenario.json` and `r3pConfig`, with lint.
4. Build:
   - the pacer `prepare` hook and its self-test;
   - `r3p-prepare.sh`, `check-n6-influx-window.py`, `r3p-predictor.py` (answer, replay, classify, lint), `r3p-checks.py`;
   - gate-r3p (`c1|single|calibrate|dryrun`, `--reference`);
   - gate-r2 `--reference`;
   - synthetic fixtures.
5. Stage A → commit its classification → stage B → commit `r3p-schedule.json` (or substitution 4).
6. Then the phase's steps 5–11.

## Success metrics
- Stage A: 420 candidates, 0 N6 failures; IMSIs 1–2 hand over and 3–6 stay, at every T.
- Stage B: the m1 window equals the live m1 window.
- C1: 3 live runs have byte-equal predictor records; 1 applied handover each; `equalsReference` true at M9.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| UL-off DL equals the c8null values in R3′ runs (same CLI, RngRun 1) | high | The dry run decides; P's margin tolerates large drift |
| kpimon writes every seq, including seq 0 (seen in M6 at the N4 pins) | medium-high | A systematic seq-0 gap → invalid → T3 to redefine "full" |
| The Testbed patches leave the decision code untouched (A1 payload parsing, default handler) | high | Re-read `ts_xapp.cpp` with both patches applied |
| A handover settles within one period (Start + 3 ms, End + 1.72 ms) | high | A slower RRC shows up as an N6 (h) failure in stage B |
| A 20 s N6 deadline is ample (an in-pod query takes ~0.3–1 s) | medium | The stage A timing file shows it |

## Unresolved questions
- Does the user accept P (persistence, cells with more UEs attract UEs) as R3′'s policy, given that it is the approved "persistence forecast" but is anti-load-balancing under CBR? Default: P.
- Is the stage-B addition to the dry run acceptable as a plan edit, without a user ruling? My view: yes. It adds verification and changes no acceptance signal.

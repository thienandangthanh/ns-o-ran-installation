# kpimon → QP mapping (open question 1) and QP-fork facts for D6

Date: 2026-10-22. This was a read-only investigation: no VM, no commits. The only file written is this report. Scratch probes live under the session scratchpad and are not committed.

## 0. Outcome

1. **G1 is worse than a renaming problem.**
   - kpimon writes `UeMetrics`/`cellMetrics` with **no tags at all**. Each point carries only KPM fields and the wall-clock `time.Now()`. Identity exists only as our agent's `ns3.*` integer fields.
   - QP needs four things the data lacks: string cell ids that match TS's `cell_map` keys, a string `ue-id`, a `pdcpBytesUl` column, and exclusion of the eNB's UE rows. The table in §1.3 shows each case.
   - A reader-side mapping inside a QP fork covers all of it. Uplink is the only field with no source (§1.3, U-options).
2. **Stock NIST QP crashes as soon as it has enough data to train.**
   - NIST's `setup.py` patch drops upstream's `pandas==1.5.3` pin. Today an unpinned build resolves pandas 3.0.6, and the training path raises a TypeError (`fillna(method=)`). Under pandas 2.x it raises an AttributeError (`iteritems`) instead. Both were measured in this session; see §2.2.
   - The exception is uncaught, and it kills ricxappframe's dispatch loop. The QP process then exits.
   - So G2's "flips run to run at the ≥ 10-row threshold" really means "flips between the last-value fallback and a QP crash". Any QP fork must pin its dependencies or port these two lines.
3. **The serving cell can be lost on more paths than G7 describes.**
   - TS treats the *first* `Uint` in QP's reply as downlink. QP's list order is `[UL, DL]`, so TS steers on predicted **UL** (§2.4).
   - TS ignores negative values and nulls. Stock QP emits both: VAR forecasts go negative in the probe, and QP returns `[None, None]` when it has no data.
   - G7, the dereference of `end()`, fires only when the reply contains **no** `Uint` at all. Without a crash, the "serving cell" TS uses is whichever cell was listed first with a valid value.
   - A QP fork alone can close G7 (§3).
4. **Recommendation for D6, ranked.**
   - **Option 1:** a single QP fork with a reader-side mapping and a sim-time window keyed on `ns3.simTimeMs`, with no kpimon fork. The model state then needs one of two treatments: a per-run QP pod restart (M2) or stateless training (M1).
   - Rejected: a kpimon fork (option 2), an Influx task (option 3), and harness-written rows or `_time` compression (option 4). Each one either still needs the QP window patch or re-couples R3 to wall clock.
5. **Fork status.**
   - `thienandangthanh/ric-app-qp` already exists. It is **private**, it is not a GitHub fork, and its master is 47a35ca. Its two extra branches belong to an unrelated InfluxDB-v1 project.
   - Gates clone anonymously, so the repo must become public (or gates need credentials).
   - Branch from gerrit `ric-app/qp` **l-release = 47a35ca**, which is what NIST pins.

Source shorthands:

| Shorthand | Source |
|---|---|
| `kp` | kpimon-go @8bbbbbb with NIST's 9 patches and our SIZE(8) patch applied, giving the patched `control/control.go`; upstream line numbers are given in parentheses |
| `qp` | ric-app-qp @47a35ca with NIST's 4 patches applied |
| `ts` | ric-app-ts @19e169b `src/ts_xapp/ts_xapp.cpp` |
| `map` | Testbed @725b167 `RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/schema/metric-map.v1.json`, one row per line |
| `nist` | Testbed @725b167 `RAN_Intelligent_Controllers/Near-Real-Time-RIC/` |
| `ev6` | `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m6/20261021T232516Z/` |
| `ev7` | `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m7/20261021T233129Z/` |

Version checks:
- The local kpimon clone's HEAD is 8bbbbbb, which equals `KPIMON_SHA` (`scripts/gates/gate-m0-preflight.sh:14-15`).
- The local QP clone's HEAD is 47a35ca. That equals NIST's pin `["l-release","47a35ca…"]` (`nist/commit_hashes.json:17`, identical in `commit_hashes_l_release.json:17`) and gerrit `refs/heads/l-release`, checked with `git ls-remote`.
- Gerrit master has moved to 9c6dfa7 (2026-10-14). The changes since l-release are docs and tox only.
- One thing differs from what the caller expected: the user's standalone `~/Documents/UCLAB/projects/O-RAN-DW/O-RAN-Testbed-Automation` is at a8e3af9, not the pin, and it carries *whole-file* QP patches. The pinned worktree submodule `O-RAN-Testbed-Automation/` (725b167) carries the `.patch` files that the journal cites, so it was used throughout.

## 1. Schemas

### 1.1 What kpimon writes

| Item | Value | Source |
|---|---|---|
| Client | `influxdb2.NewClient("http://r4-influxdb-influxdb2.ricplt:80", <NIST token>)` | `kp:80` |
| Org / bucket | `WriteAPIBlocking("influxdata","kpimon")`, one blocking write per point | `kp:967, 988` |
| Measurements | `UeMetrics` (IndicationMessage format 2) and `cellMetrics` (format 1) | `kp:978` (959) and `kp:999` (980) |
| Tags | **none**: there is no `AddTag` in the file (grep count 0) | `kp` whole file |
| Fields | One field per KPM measName, using the name the agent advertised for that RAN (`ranCellKpi[RanName]` / `ranUeKpi[RanName]`). `INTEGER` is cast to `int32`, giving Influx `long`; `REAL` becomes `float64`, giving `double`. A noValue record prints "Wrong Data Type" and **omits** the field. | `kp:780, 833, 795-812, 865-878, 979-981`; types confirmed by the `#datatype` row of `ev6/m6-influx-ue.csv` |
| Rows | One point per cell measData item (format 1). For format 2, one point per UE. | `kp:784-819, 856-884` |
| Timestamp | **Wall clock `time.Now()` at write time**, ns precision. kpimon never reads `colletStartTime`: no reference exists in `control/` or `e2sm/wrapper.c`, and the header is decoded only for its format. | `kp:978, 999`; grep |
| Concurrency | **One goroutine per RIC Indication** (`go c.handleIndication(msg)`), so the write order (`_time`) is not the arrival order | `kp:666` (651) |

What our agent actually puts in those fields (`map`):
- **gNB cell list:** `ns3.nodeId` (= ns-3 cellId), `ns3.simTimeMs`, `ns3.seq`, then 30 KPIs. The only DL volume is `QosFlow.PdcpPduVolumeDL` (REAL, bytes/period, `map:33`). There is **no UL byte metric**; the only UL items are `RRU.PrbAvailUl` and `RRU.PrbTotUl`, which count PRBs (`map:50,52`).
- **gNB UE list:**
  - Identity and timing: `ns3.nodeId`, `ns3.simTimeMs`, `ns3.seq`, `ns3.imsi` (`map:56-59`).
  - Serving cell: `ns3.l3.servCellId`, `servSinrDb`, `servSinr3gpp` (`map:87-89`).
  - Neighbours: `ns3.l3.nbr1..8.{cellId,sinrDb,sinr3gpp}` (`map:90-113`).
  - DL volume: `ns3.du.QosFlow.PdcpPduVolumeDL` (`map:66`) and `QosFlow.PdcpPduVolumeDL` (cuUp, `map:83`).
  - Throughput: `DRB.UEThpDl` (`map:82`).
- **eNB lists:**
  - Cell: `ns3.cuUp.pDCPBytesUL` and `pDCPBytesDL`, cell scope (`map:118-119`).
  - UE rows also carry `ns3.imsi` and `ns3.l3.servCellId` (`map:125, 136`).
- **The map's own rules:** join keys are `(ns3.nodeId, ns3.seq[, ns3.imsi])`, "never on `_time`" (`map:19`); missing or null values become noValue (`map:18`).

Observed in the data:
- **1 gNB, M6:** 193 UE rows and 100 cell rows; `ns3.nodeId` is always 2. The neighbour fields are absent, because noValue is omitted (`ev6/m6-influx-ue.csv`, `m6-influx-cell.csv`).
- **1 eNB + 4 gNB, M7:**
  - The kpimon log shows `ns3.l3.nbr1..3.cellId` populated with cells 2..5.
  - **The eNB (nodeId 1) emits 1836 UE rows, all with `ns3.l3.servCellId:1`.** That is about one per UE per step, alongside the 1845 gNB UE rows (`ev7/m7-kpimon.log`, counted in this session).
  - The eNB cell row has `ns3.cuUp.pDCPBytesUL:0`.

Agent `colletStartTime` is `ntp64(hello.simStartEpochMs + simTimeMs − periodMs)` (`ns3_e2_agent/src/sample-forwarder.cpp:62-65`). `simStartEpochMs` is a wall-clock epoch: "wall-clock epoch ms mapped to sim time 0" (`oran-interface/model/e2-ipc-message-encoder.h:26`; set from `m_startTime` at `ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:488`). colletStartTime therefore **changes on every run**. Sim-time keys must use the `ns3.simTimeMs` field, which is deterministic, not colletStartTime.

### 1.2 What QP reads (NIST-patched)

Config (`qp/src/qp_config.ini`):
- `bucket = kpimon` (:6)
- `uemeas = UEReports`, `cellmeas = CellReports` (:9-10)
- `thptDL = pdcpBytesDl`, `thptUL = pdcpBytesUl`, `ue = ue-id`, `nbcells = nbCell`, `servcell = nrCell`, `cid = nrCellIdentity` (:14-19)

Query (`qp/src/database.py:77-104`), built as:
```
from(bucket:"kpimon") |> range(start: -1600ms) |> filter(fn:(r)=> r._measurement == "<meas>")
 |> pivot(rowKey:["_time"], columnKey:["_field"], valueColumn:"_value")
 |> filter(fn:(r)=> r["<ue-id|nrCellIdentity>"] == "<Id>")     # string literal comparison
 |> sort(columns:["_time"], desc:true) |> limit(n:<limit>)
```
- **UE lookup:** `ueid` forces `limit=1` (:85-89).
- **Cell lookup:** `limit=101` when predicting (`qp/src/main.py:106`) and `limit=4800` when training (`qp/src/qptrain.py:128`).
- **Errors:** every exception inside `query()`, a Flux type error included, is caught and returns an empty DataFrame (:106-138). The result is then re-indexed on `_time` ascending (:129).
- **Feature order:** `thptparam = [thptUL, thptDL]`, **UL first** (:190-193).

How QP uses the rows:

| Use | Columns | Threshold | Source |
|---|---|---|---|
| UE's cells | `df.filter(regex="nrCell")` (serving) + `df.filter(regex="nbCell")` (neighbours) of row 0, i.e. **substring regex**; the list is `srvc + nbc` | 1 row | `qp/src/main.py:79-90` |
| Cell series | `db.data[[pdcpBytesUl, pdcpBytesDl]]` | — | `main.py:109` |
| Train or predict gate | `constant()`: drop duplicate rows, drop constant columns, drop NaN rows, drop all-zero columns, then require **≥ 10 rows** | ≥ 10 | `qptrain.py:81-92` |
| Train | runs once per cell id, only while `src/<cid>` is absent; VAR with lag chosen from 1..19 by 75/25 RMSE | — | `main.py:123-125`, `qptrain.py:106-140` |
| Predict | with a model file and a non-constant series: `model.forecast(y=raw data, steps=1)`; otherwise `data.tail(1)` (last value); then `astype(int)` | — | `prediction.py:31-38` |
| Reply | RMR 30002 `{"<ue>": {"<cid>": [UL, DL] or [None, None]}}`, sent **every time** | — | `main.py:71, 112-120` |
| Write-back | measurement `QP` in bucket `kpimon`, indexed at the last `_time` + 10 ms | — | `database.py:157-167`, `prediction.py:37` |

### 1.3 Field-by-field mapping

"Derivable" means the value exists in our data and needs a transform or a filter.

| QP column (meas) | QP's use / type requirement | Our source (kpimon field) | Status |
|---|---|---|---|
| measurement `UEReports` | filter | `UeMetrics` | **derivable** (rename) |
| measurement `CellReports` | filter | `cellMetrics` | **derivable** (rename) |
| `ue-id` (UE) | Flux `== "<str>"`; it comes from TS's payload, and TS later calls `stoi()` on it (`ts:622`) | `ns3.imsi` (long, `map:59`) | **derivable**: needs a decimal string. As stored, it is a long, so the comparison is a Flux type error, the error is swallowed, and QP sees no data. |
| UE row restricted to gNB rows | not in QP | `ns3.nodeId ≥ 2`, or `ns3.l3.servCellId == ns3.nodeId` | **derivable; required**. The eNB UE rows (servCellId 1) otherwise compete for `limit 1` (§1.1). |
| column matching `/nrCell/` (UE, serving) | must be a **string** equal to TS's `cell_map` key. An int or NaN crashes at `'src/'+cid` (`main.py:124`), uncaught. | `ns3.l3.servCellId` (long, `map:87`) | **derivable**: needs `cellKey(id)`. The key format depends on the G4 fix (see below). |
| columns matching `/nbCell/` (UE, neighbours) | same string rule; no NaN | `ns3.l3.nbr1..8.cellId` (long, `map:90-111`) | **derivable at ≥ 2 gNBs** (absent at 1 gNB). Omitted neighbours must be dropped, not passed on as NaN. |
| `nrCellIdentity` (cell) | `== "<cid>"` filter | `ns3.nodeId` (long, `map:23`) | **derivable**: inverse of `cellKey`, or filter on the int directly |
| `pdcpBytesDl` (cell) | VAR input | `QosFlow.PdcpPduVolumeDL` (double, bytes/period, `map:33`), or the sum of the UEs' `ns3.du.QosFlow.PdcpPduVolumeDL` | **direct** (rename). Units differ in meaning from VIAVI's but are numeric. |
| `pdcpBytesUl` (cell) | VAR input, emitted **first** | none for gNB cells; the eNB's `ns3.cuUp.pDCPBytesUL` is LTE-only and 0 in M7 | **missing** |
| `_time` (ordering, window) | sort and `range` | wall `time.Now()` | replace with `ns3.simTimeMs` (+ `ns3.seq` as tie-break): **direct** |

Uplink options:
- **U2 (preferred).** Replace UL with another varying cell KPI as the second VAR variable, e.g. `RRU.PrbUsedDl` or `DRB.MeanActiveUeDl` (`map:31, 48`), and emit DL first. This needs no agent change.
- **U1.** Add a UL metric to the agent map. Whether ns-3 mmWave gNBs expose UL PDCP volume is unverified.
- **U3.** Set UL to 0. This **crashes stock QP**: `constant()` drops the zero column, the DL column still clears the 10-row gate, and then `make_stationary` → `adfuller(constant)` raises `ValueError: Invalid input, x is constant`, which is uncaught. This was measured.
- Note that statsmodels refuses a single-variable VAR ("Only gave one variable to VAR", measured), so dropping UL alone is not an option.

**cellKey and G4.**
- TS's `cell_map` keys are `substr(i,10)` of the base64-decoded `e2nodeComponentRequestPart`, taken at each match of the uppercased ranName suffix after the third `_` (`ts:335-373`).
- Our agents send the request part `"72657170617274"` (hex of "reqpart") for `gnb_001_001_00000002` (`plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/dev-p5/smoke/20261021T164639Z/e2mgr-nodeb.json`). That gives **no match, so `cell_map` is empty, and TS skips every control** ("Cannot find RAN name", `ts:645-647`).
- QP's `cellKey(nodeId)` must emit exactly the 10-character string that the G4 fix places in the request part. The agent must also parse the same id back out of rc's `"00"+PLMN+TargetCellID` CGI. These three must be designed together.

## 2. Nondeterministic and wall-clock dependencies

### 2.1 QP

| # | Dependency | Effect under lock-step | Source |
|---|---|---|---|
| Q1 | `range(start: -1600ms)` uses Influx's `now()` | The visible row set depends on wall time between write and query (G2) | `database.py:93` |
| Q2 | `sort(_time desc)` + `limit(n)`; re-indexed on `_time` | Order and selection follow kpimon's write time, and that time is nondeterministic (K2) | `database.py:99-101, 129` |
| Q3 | `constant()` ≥ 10-row gate | Training vs. last-value fallback depends on the Q1 row count | `qptrain.py:81-92` |
| Q4 | Model state: trains **once per cell id per pod lifetime**, at the first request where the series is non-constant; it writes `src/<cid>` into the container filesystem and never retrains. The descriptor has no volume. | The model depends on the window of the first successful training. The state is reset only by a pod restart (G10). | `main.py:123-125`, `qptrain.py:136-138`, `qp/xapp-descriptor/config.json` (no volumes) |
| Q5 | Unpinned dependencies: `pandas>=1.1.3`, `statsmodels>=0.11.1`, `numpy`, `scikit-learn` resolve at `docker build` (`pip install /tmp`) | The result depends on the build date. **Today: pandas 3.0.6, statsmodels 0.15.0, numpy 2.4.6, so the training path crashes** (§2.2). | `qp/setup.py:24-35`; `qp/Dockerfile` (`FROM continuumio/miniconda3:23.10.0-1`, `RUN pip install /tmp`) |
| Q6 | An uncaught handler exception ends the dispatch loop | Any `KeyError`, `TypeError`, `ValueError` or `AttributeError` in `predict()` kills QP. Only `queue.Empty` is caught around the handler. | ricxappframe 3.2.2 `xapp_frame.py:949-963` (local `xapp-frame-py` tag 3.2.2) |
| Q7 | Threading | Deterministic: a single dispatch loop (`run(thread=False)`) and `numWorkers 1`; the RMR receive and registration threads do not touch the DB | `main.py:138-140`; `xapp_frame.py:119, 977-980`; `config.json` `rmr.numWorkers` |
| Q8 | Dict and column order | Deterministic: the output dict keeps insertion order (`srvc + nbc`). The column order of neighbours comes from the pivot and DataFrame column order, which is **unverified** for Flux pivot. A fork should order neighbours explicitly. | `main.py:87-89, 119` |
| Q9 | Numerical determinism of statsmodels VAR | **Bit-identical across 3 separate processes**: identical forecast SHA-256 for 4 series sizes. Measured with pandas 1.5.3, statsmodels 0.14.6, numpy 1.26.4 on the laptop. Not measured inside the image (BLAS build or threads may differ). | scratch probe |
| Q10 | `connect()` sleeps 120 s on failure | Start-up only | `database.py:71-75` |
| Q11 | Write-back to measurement `QP` in bucket `kpimon` | Pollutes the bucket; harmless to reads, which filter by measurement. Covered by the per-run bucket reset (G10). | `database.py:157-167` |

### 2.2 The training-path crash, measured

The probe reproduced QP's real `qptrain.train` and `prediction.forecast` on synthetic UL/DL frames of 10, 16, 40 and 101 rows, with only `mdclogpy` stubbed:

| Resolved deps | Result |
|---|---|
| pandas 3.0.6 (today's unpinned resolve) | `TypeError: NDFrame.fillna() got an unexpected keyword argument 'method'` (`qptrain.py:40`) |
| pandas 2.2.3 | `AttributeError: 'DataFrame' object has no attribute 'iteritems'` (`qptrain.py:60`) |
| pandas 1.5.3, numpy < 2 (upstream's original pin) | works; models saved; forecasts identical across 3 runs; **forecasts can be negative** (e.g. `[-6297, -51313]`) |

Through Q6, a crash in `train_model` exits QP. The 4 cited stock lines can only run once ≥ 10 varied rows are visible. Under stock NIST, QP therefore survives only while it is starved of data.

The prior commit `6a3a917` on the user's existing fork shows the same thing independently: it restores `pandas==1.5.3` and adds `numpy<2`, because otherwise "numpy.dtype size changed" (`gh api …/compare/master...phase2-stage3-tagged-read-side`, setup.py hunk).

### 2.3 kpimon (the writer)

| # | Dependency | Effect | Source |
|---|---|---|---|
| K1 | `_time = time.Now()` | Wall time, different every run; it carries no sim information | `kp:978, 999` |
| K2 | One goroutine per indication | Points for the same cell can land out of `ns3.seq` order, and **after** the pacer thinks the step is done. The pacer must wait until the expected row count for `ns3.simTimeMs = T` is visible in Influx before injecting 30003. | `kp:666` |
| K3 | No tags: all nodes share one series per measurement | Two points with an identical ns `_time` would merge field by field. Very unlikely but not impossible (unverified on kvm-clock). | `kp:978-981, 999-1002` |
| K4 | `range` over a Go map in `AddField` | Field order is random but irrelevant: Influx stores fields by key | `kp:979-981` |

### 2.4 TS reading QP's reply (G7 and its semantics)

- **How TS parses the reply** (`PredictionHandler`, `ts:212-262`):
  - The first JSON key is the UE id; later keys are cell ids.
  - Only the `Uint` callback records a value. `Null`, `Int` (negative), `Double` and `Uint64` (> 2³²−1) are ignored.
  - `serving_cell_id` is the first key that receives any `Uint`.
  - A single global `down_val` toggle assigns alternate `Uint`s to down and up. Because QP emits `[UL, DL]`, **TS's "downlink" is QP's UL**. An ignored value shifts the alternation.
- **G7.** `throughput_map.find(serving)->second` (`ts:702-703`) dereferences `end()` **only if the reply contains no `Uint` at all**. That happens with `{}`, with a UE with no cells, or with every value null or negative. Otherwise the serving entry always exists, but it may be the wrong cell.
- **Decision rule.** TS picks the strictly highest value, breaking ties by `unordered_map` iteration order, which is deterministic for identical input. It hands over if that value is above serving × (1 + threshold) (`ts:706-723`).
- **Multiple UEs.** TS sends every AD `ue-id` in one 30000 (`ts:264-283, 785-800, 755-765`). With several UEs, only the first UE id survives and the cells of all UEs merge, so **the harness should inject one UE per 30003**.

## 3. Patch options for a bit-repeatable R3

**Option 1. QP fork with a reader-side mapping and a sim-time window (recommended).**

Files touched (all in the QP fork):
- `src/database.py`:
  - Query `UeMetrics`/`cellMetrics` over `range(start: 0)` (a bucket reset per run keeps the scan small).
  - Pivot, then filter `ns3.nodeId ≥ 2`, `ns3.imsi == int(ue)` and `ns3.simTimeMs ∈ (T−W, T]`.
  - Sort on `ns3.simTimeMs, ns3.seq`.
  - Rename to QP's columns with `cellKey()`, drop absent neighbours, and set the index to `ns3.simTimeMs`.
- `src/qp_config.ini`: measurement names, `W` (for example 1600 sim-ms, i.e. 16 rows at 100 ms, which clears the ≥ 10 gate), the cellKey format, and the second VAR feature (U2).
- `src/main.py`:
  - Put DL first.
  - Clamp predictions to 0..2³²−1 integers, falling back to the last value when the model output is invalid.
  - **Do not send 30002 unless the serving cell has a valid pair**, which closes G7.
  - Wrap `predict()` so an exception logs and suppresses instead of killing the loop.
- `setup.py`: exact pins. Either P1 (`pandas==1.5.3`, `numpy<2` plus exact statsmodels and scikit-learn; measured working) or P2 (port `iteritems`→`items` and `fillna(method='bfill')`→`bfill()` at `qptrain.py:40,60`, then pin current versions).
- Optionally `Dockerfile`: pin the base image by digest.

How T (the step's sim time) reaches QP:
- **1a (preferred).** `T = max(ns3.simTimeMs)` in `cellMetrics`. This is valid only if the pacer guarantees that every row for T has landed and no T+1 row exists (K2).
- **1c.** A harness-written marker measurement.
- **1b.** Carry T in the RMR payload. Rejected: TS rebuilds 30000 from `ue-id` only, so this needs a TS fork.

Model state:
- **M2 (preferred, no code).** Keep the train-once behaviour and restart the QP pod per run (already part of G10). It is deterministic given a deterministic trigger schedule.
- **M1.** Train statelessly per request on the window. No hidden state, at the cost of about 19 VAR fits per cell per request (not timed).
- **M3.** Ship pre-trained `src/<cid>` files. This needs a training pipeline and model versioning; the most work.

| | |
|---|---|
| Risk | Medium. QP becomes our code (≈ 100–150 changed lines, estimated). Prediction quality is not improved: QP forecasts on raw data with a model fit on differenced data (`prediction.py:34` vs `qptrain.py:62-64`). Deterministic, but semantically off. |
| G7 | **Closed in QP**: send only when a serving entry exists, keep the serving cell first, never send null or negative values. |
| Also closes | G1, G2, the QP part of G10 (with M2), and the §2.2 crash |
| kpimon and the M6/M7 gates | untouched |

**Option 2. kpimon fork writes `UEReports`/`CellReports` with tags and sim time.**
- Touches `control/control.go` (writeUe/CellMetrics_db), on top of NIST's 9 patches and SIZE(8).
- It **does not remove the QP patch.** QP's `range(-1600ms)` stays relative to `now()`, so the window still has to change. K2 also remains unless the goroutine is serialized.
- It adds a second, cgo-based fork and touches the data that the M6/M7 gates compare.
- G7 is not closed (that needs QP or TS). **Rejected.**

**Option 3. An InfluxDB v2 task maps the measurements.**
- Tasks run on a wall-clock `every`/`cron` schedule, which reintroduces wall-clock lag.
- The QP window patch is still needed, and G7 is not closed. **Rejected.**

**Option 4. The harness writes QP-schema rows, or compresses `_time` into the last 1.6 s (D6's "unverified idea").**
- This bypasses kpimon in R3.
- Compressing `_time` races QP's query against wall time, so it is not bit-repeatable. G7 is not closed. **Rejected.**

| Criterion | Opt 1 QP fork | Opt 2 kpimon fork | Opt 3 Influx task | Opt 4 harness rows |
|---|---|---|---|---|
| Bit-repeatable R3 | yes (with 1a+M2 and pins) | no (QP window remains) | no | no (compression) / partial |
| Forks added | 1 (QP) | 2 (kpimon + QP) | 1 (QP) | 1 (QP) |
| Closes G7 | yes | no | no | no |
| Touches M6/M7 gates | no | yes | no | no |
| Exercises the real kpimon→QP path | yes | yes | yes | no |
| Complexity | medium | high (cgo, 9 NIST + 2 SIZE(8) patches) | medium | low–medium |

## 4. The fork on GitHub

- **What exists.** `gh repo list thienandangthanh --limit 100` lists `thienandangthanh/ric-app-qp`.
  - `gh api` shows `private: true`, `fork: false`, no parent. It was created 2026-05-26 and last pushed 2026-06-20.
  - Branches:
    - `master` = 47a35ca, identical to gerrit l-release.
    - `phase-1-workload-characterization` (57b1a26) and `phase2-stage3-tagged-read-side` (6a3a917) come from a different project: InfluxDB v1 `DataFrameClient`, VIAVI "Naive/Tagged" schema, docker-compose routing (`rte|30002|qp:4560`). They are not NIST-patched. **Do not build on them.** The only part worth reusing is the pin rationale (§2.2).
  - The local clone `~/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-qp` already has remote `fork` pointing at it. A `ric-app-ts` fork does **not** exist (404). `ric-app-kpimon-go` exists, but it is private and unused by the gates.
- **Upstream to fork from.** Gerrit `https://gerrit.o-ran-sc.org/r/ric-app/qp`, branch `l-release` @ **47a35ca**, which equals NIST's pin. Branch on the fork as `dev/l-release-nist180` (`scripts/pins.conf:4` convention).
- **Blockers for the gates.**
  - `pins.conf` says gates clone "anonymous HTTPS" (`scripts/pins.conf:1`), and `fetch_sha` runs with `GIT_TERMINAL_PROMPT=0` (`gate-m0-preflight.sh`, §7). A private repo fails that, so it must be made public or credentials must be added.
  - NIST's installer clones gerrit (`nist/additional_scripts/install_xapp_qoe_predictor.sh:65`) and then `git restore` + `git apply`s 4 patches (:81-111). `git_clone.sh` pins by URL key in `commit_hashes.json` (`nist/install_scripts/git_clone.sh:134-163`).
  - Pointing at the fork therefore needs a Testbed-fork change: the URL, a `commit_hashes*.json` entry, and either keep NIST's patches as the fork's first commit and skip `git apply`, or keep the fork at stock 47a35ca and add a fifth patch.

## 5. Adoption risk

- **QP upstream is effectively dormant.** The only change since 2024-04 is a 2026-10 docs commit, so a fork carries little merge burden.
- **The Python stack is pinned to 2023-era pandas** (1.5.3, Python 3.11 wheels exist; installed and run in this session). This is stable but frozen; P2 avoids freezing it at the cost of a two-line port.
- **Statsmodels determinism** has only been shown on the laptop. The image may link a different BLAS.

## 6. Limitations

- Nothing was run on the VM. The QP image was not built, and the pandas version inside a real NIST build is inferred from today's resolver, not observed.
- The Flux pivot column order and the result of `query_data_frame` were not checked live.
- No probe covered the cost of option M1 or the latency of a `range(start:0)` query.
- The U1 feasibility (UL PDCP volume in ns-3 mmWave) was not investigated.
- The design of G4 (`cellKey`) is outside this report.

## Unresolved questions

1. The cell-key format. What 10-character string will the G4 fix put in `e2nodeComponentRequestPart`, so that QP's `cellKey(nodeId)`, TS's `cell_map` and the agent's CGI parse all agree?
2. U1 vs U2 for the second VAR variable: is there a real UL volume in ns-3 gNBs?
3. M1 (stateless) vs M2 (train-once plus a per-run pod restart).
4. P1 (freeze pandas 1.5.3) vs P2 (port 2 lines, pin current versions).
5. Make `thienandangthanh/ric-app-qp` public, or give the gates credentials?
6. Should QP or the pacer own the "all rows for T landed" check (K2)?
7. The real TS service and RMR route for 30002. QP's seed `local.rt` points to `service-ricxapp-trafficxapp-rmr` (`qp/tests/fixtures/local.rt`), and rtmgr's live table was not checked.

Status: DONE_WITH_CONCERNS
Summary: kpimon writes untagged, wall-clock-timestamped `UeMetrics`/`cellMetrics`. A QP fork can map them, and every QP field is derivable from our `ns3.*` fields except UL; a QP fork with a sim-time window (`ns3.simTimeMs`), pinned dependencies and a guarded 30002 reply makes R3 repeatable and closes G7. Concern: stock NIST QP crashes on its training path under today's unpinned pandas, and the existing GitHub repo is private and holds unrelated branches.

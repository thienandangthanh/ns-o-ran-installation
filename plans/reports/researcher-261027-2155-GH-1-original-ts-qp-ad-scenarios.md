# Original scenario and data behind the O-RAN SC TS / QP / AD xApps

Date: 2026-10-27 (Asia/Seoul). Read-only research. Repos cloned to `/tmp/claude-1000/research-xapps/{ad,ts,qp,qp-driver,nist}` (gerrit HEAD; NIST `usnistgov/O-RAN-Testbed-Automation` @ 6088882, 2026-09-02). Wiki pages read through the Confluence REST API (`lf-o-ran-sc.atlassian.net/wiki/rest/api/content/<id>?expand=body.storage`), because the wiki is JS-rendered and WebFetch returns an empty page.

## Bottom line

The AD/QP/TS chain from the Dawn (D) release onward was built around **VIAVI RIC Test** (`PROJECT: e2-sim`) synthetic data. That data covers a 13-site, 3-layer (B2/B13/N77) urban map with 39 cells and 20–24 named UEs (Pedestrian, Car, Train passenger, Waiting passenger) under Manhattan mobility, reported every 10 ms with Viavi-injected anomalies. In D/E the use case was **only ever demoed by replaying recorded Viavi files into InfluxDB** (`insert.py`). That was not a live E2 loop: the D-release test page says "the test case can only be tested starting from the inFlux DB". QP forecasts **one 10 ms step ahead** with a per-cell VAR on cumulative PDCP byte counters. NIST runs the same replay, and its README says live KPI needs an adapter. I found no paper that ran this exact chain on ns-3/ns-O-RAN.

## Verified facts (with sources)

### Q1. What QP was trained on: Viavi RIC Test, D release
- The first ML commit is qp `a1cb1ab` (2021-07-06, HCL, "First version with ML prediction code"). It bundled `qp/cell.json.7z`, which unpacks to `SimulatedReports-2021-07-02-131023-v2h03t3q.json` (13,506 JSON lines). The first line is the metadata, quoted verbatim: `"PRODUCT":"VIAVI RIC Test","VERSION":"v0.9-beta2-bigfile.7991-b49c9b56", ... "PROJECT":"e2-sim"`. Its `insert.py` header reads: "temporary ... populate cell data into influxDB. This will be depreciated once KPIMON push cell info. into influxDB."
- `src/cells.csv` was added in qp `30a9743` (Release 0.0.5, 2022-12-16, RICAPP-207). It replaced `qp/dummy.csv` and the json. It is byte-identical to this repo's `ric-app-qp/src/cells.csv` (checked with diff). Its timestamps (2021-06-11T05:40:32.420 → 05:40:33.700) come from a different Viavi run than the json.
- The scenario layout comes from the Viavi config embedded in that json:
  - `cells.number: 13`, `neighbours: 5`, `distance: 1000` (m), `antenna_height: 10`. An ASCII map shows sites c1…c13, a train station (b1), areas a1/a2/a3 and streets 20 m wide.
  - There are three layers per site: `B2` 1900 MHz, 120 PRB; `B13` 700 MHz, 91 PRB; `N77` 3600 MHz, 273 PRB. Each `du-id` 1001…1013 equals one site, and each cell is named `cN/<layer>`. Every cell also carries `nrCellIdentity5G` (for example c1/B2 = 4096, c1/B13 = 4097, c1/N77 = 4098). Viavi reports all 39 cells as NR cells. B2/B13 here are frequency layers, not separate LTE eNBs.
  - UE groups (`type2_ues`):
    - Pedestrian-{n}: 10 UEs, speed 0.5, "short range", targetTput 0.25 ("250 Mbps", so the unit is Gbps).
    - Car-{n}: 1 UE, "A car driving North from cell 1", Manhattan mobility, speed 20, path `NNWSEES...`, targetTput 0.75.
    - Train passenger {n}: 3 UEs, Manhattan mobility, speed 10, arriving from the East.
    - Waiting passenger {n}: 10 UEs, static in building b1, targetTput 0.1.
    - Every group uses simulator handover `"RSRP (threshold=5)"`.
  - Anomalies (`Anomalies`):
    - "Intermittent Throughput issue in cell 1": throughput 80 % degradation on `Car*, Pedes*`.
    - Two radio anomalies (RSRP/RSRQ/RSSINR −20 dB) on `Train*` and `Waiting*`.
  - `System.report_ms: 10`.
- `cells.csv` contents (my analysis):
  - 5,000 rows, 129 timestamps 10 ms apart, 39 cells. The last step is truncated (129 × 39 = 5,031).
  - Only 16 of the 39 cells carry traffic.
  - `pdcpBytesDl/Ul` are **cumulative ramps**: each 10 ms step adds 10.24 × `throughput`. For example c3/N77 has throughput 0.2, adds 2.048 per step and ends at 260.1. Per-cell throughput is almost constant.

### Q2. QP model, horizon and window (qp HEAD `src/qptrain.py`, `prediction.py`, `main.py`)
- Features are `[pdcpBytesUl, pdcpBytesDl]` per cell (`qp_config.ini`: `thptDL = pdcpBytesDl`, `cid = nrCellIdentity`, `servcell = nrCell`, `nbcells = nbCell`).
- Stationarity is checked with ADF (`adfuller`, autolag AIC, p ≤ 0.05). If any series fails, QP takes **one** first difference.
- The VAR lag is searched over 1–19 by RMSE on a 75/25 split.
- A model is trained **once per cell, lazily on the first prediction request** (`train_model` runs only if `src/<cid>` does not exist). Training uses `read_data(cellid, limit=4800)`, which upstream (InfluxQL) is the 4,800 newest rows with no time bound.
- `constant()` refuses to train unless there are **≥ 10 distinct, non-zero, non-constant rows**. With no model, the forecast is the last observed value.
- The forecast is `forecast(inp, mcid, 1)` on the last 101 rows, indexed `freq='10ms'`. The **horizon is 1 step (10 ms)**, and the result is inverted back to cumulative scale.
- QP returns `{ue: {cell: [DL, UL]}}`, serving cell first (`cells = srvc + nbc`, RICAPP-181, 2021-12).
- So QP needs counters that move over time. It does not need varying *rates*: a constant-rate ramp passes the ADF/diff path and VAR extrapolates it.
- Features planned for E/F but never delivered: "incorporate predicted load as a feature, provide sequence of predictions" (E-release notes, https://docs.o-ran-sc.org/en/e-release/). Release 0.0.5 only changed the database code.

### Q3. Expected sizes and mobility in the original demos

| Era | Data | Cells | UEs | Mobility |
|---|---|---|---|---|
| Bronze, TS 1.0.x, 2020 | `ts/test/populatedb/src/write_sdl.cpp`, SDL `TS-UE-metrics`/`TS-cell-metrics` | 3 (`310-680-200-555001..3`) | 1 (`12345`) | none (static mock) |
| Cherry AD 0.0.1 | `ad/ue_data/12345..12444.csv` (deleted in `4674f4a`) | 3 (555001–3) | 100 | synthetic, `Category` labels such as "Excellent Signal" / "Poor Signal" |
| Dawn+ (AD 0.0.2, QP 0.0.4, 2021-07) | Viavi RIC Test SimulatedReports | 39 (13 sites × 3) | 24 in the 2021-07-02 config (10/1/3/10); **20 in `ad/src/ue.csv`** (Car-1..4, Pedestrian-1..3, Train passenger 1..3, Waiting passenger 1..10) | cars 20, trains 10, pedestrians 0.5, waiting static |

- A SIM meeting on 2020-02-27 (wiki page 13434921) planned to use the Viavi TM500 in the OSNL Berlin lab to "Generate flat files with RF reports define 7-8 cells … static users in first phase", which an E2 Simulator would replay.
- The Viavi case study (https://www.viavisolutions.com/en-us/literature/ran-intelligent-ric-traffic-steering-case-studies-en.pdf) describes the scenario: "RIC Test creates a throughput reduction anomaly for a UE"; QP "finds improvement in Cell 2"; TS "initiates a handover request to RAN". The emulated UEs are "static, moving at speed (i.e. in a vehicle)".
- The F-release notes say: "VIAVI RIC test tool is used to test Traffic Steering use case." They also say "(Currently AD is working on Static data)" (https://docs.o-ran-sc.org/en/f-release/).
- The wiki page "xApp testing for D Release" (id 14516480) says: "we are lacking a E2 Simulator that implements the E2SM KPM 2.0.3, so the test case can only be tested starting from the inFlux DB. The AD xApp repo includes scripts for populating the inFlux DB with data from Viavi E2 simulator."

### Q4. What AD consumes and sends
- AD reads the InfluxDB database `RIC-Test`, measurement `UEReports`. Features (`ad_config.ini`): `DRB.UEThpDl`, `RF.serving.RSRP/RSRQ/RSSINR`, `RRU.PrbUsedDl`. The label is `Viavi.UE.anomalies` (Viavi ground truth, used only for validation F1). `ue-id` is the key.
- The bundled `src/ue.csv` was added in AD `77f7c38` (2022-12-10) and derives from the D-release `ad/ue.json.gz` = Viavi `uedata.json` dated 2021-07-02. It holds 10,000 rows, 20 UEs, 3,187 timestamps (2021-06-25 11:42:33.695 → 11:43:06.815, about 33 s), 13 DUs, and serving + 5 neighbour RSRP/RSRQ/SINR. 25.7 % of rows are labelled anomalous.
- Training uses an IsolationForest with RandomizedSearchCV (`ad_train.py`):
  - Training window: `now-75m … now-5m`, at least 1,000 rows.
  - Validation window: the last 5 min, at least 300 rows.
- Inference runs every 0.5 s on `time > now()-1600ms`.
- Degradation is labelled by rule (`ad_model.CAUSE.find`) against the UE's maximum over the last 20 s:
  - Throughput is flagged when it falls below max × (100 − thr)% (default `threshold = 70`).
  - RSRP is flagged when it falls below max − 15.
  - RSRQ is flagged when it falls below max − 10.
- Output: RMR **30003** `TS_ANOMALY_UPDATE` with `[{"ue-id", "time", "Degradation"}]`. TS acknowledges with **30004**.
- Code facts that matter:
  - Only `Anomaly == 1` rows are sent. Combined throughput+radio rows become `Anomaly = 2` and are **not** forwarded (`main.py` L103–106).
  - AD's A1 handler (msg 20010, `thp_threshold`) assigns a *local* `threshold` with no `global`, so A1 has no effect on AD.

### Q5. TS flow (ts HEAD `src/ts_xapp/ts_xapp.cpp`, `docs/user-guide.rst`)
- **A1 type 20008, `{"threshold": 5}`.** The schema is an integer with default 0 (wiki "Traffic Steering Flows", id 14516265). The meaning of `threshold` changed over time:
  - Bronze (1.0.x): an **RSRP threshold**. TS polled SDL and requested predictions for UEs whose `serving_cell_rsrp < rsrp_threshold` (tag 1.0.13 L538).
  - From TS 1.1.0 (2021-05-28, "Release D use case"): AD triggers TS instead.
  - From 1.2.3 (2022-05-10, "enforce A1 policy on throughput"): a **percent DL margin**.
- The chain is AD → TS (30003) → TS → QP (30000, `{"UEPredictionSet": [ue]}`) → QP → TS (30002).
- Decision rule (L689–735): only the DL prediction is used, and the first cell is taken as the serving cell. TS takes the cell with the highest predicted DL among all cells. If `highest > serving × (1 + threshold/100)`, it hands over to that cell.
- Control path: REST `{"command":"HandOff",...}` (default `ts_control_ep` is the echo server `http://127.0.0.1:5000/api/echo`) or gRPC to the RC xApp (`ControlStyle 3, ControlActionId 1, TargetCellID`).
- There is no ping-pong timer in the code, although the D-release slide `AD-TS-flow.pptx` lists "Check if best is current serving cell. Avoid ping-pong issue."

### Q6. NIST and others
- NIST README (Near-RT RIC, items `ad`/`qp`/`trafficxapp`):
  - AD: "The installer loads sample `UEReports` data into the `kpimon` bucket for the Traffic Steering sample flow. Direct use of live KPI data requires an adapter to the `UEReports` schema."
  - QP: "loads sample `CellReports` data".
  - TS "does not read InfluxDB directly".
  - The same text is in the local v1.8.0 copy (README L84/L89).
  - NIST therefore runs the **bundled Viavi replays**, not srsRAN/OAI KPIs. Its own kpimon-go writes `UeMetrics`/`cellMetrics`, a different schema.
- NIST QP patches (`install_patch_files/xApps/qp/`):
  - `database.py`, `insert.py`, `qp_config.ini`: InfluxDB 1.x `DataFrameClient` replaced by 2.x `influxdb_client`, with token/org=`influxdata`/bucket=`kpimon`, host `r4-influxdb-influxdb2.ricplt:80`, and Flux queries.
  - `setup.py`: `influxdb` → `influxdb_client`, `pandas==1.5.3` → `>=1.1.3`, `numpy` added.
  - The Dockerfile now copies `insert.py`, and the installer starts `python3 /src/insert.py` in the pod.
  - Reason: the L-release platform ships InfluxDB 2 (`r4-influxdb-influxdb2`). This is stated in the README as "Patched to support InfluxDB version 2.X instead of InfluxDB 1.X".
  - AD gets the equivalent patch.
- Papers: I found no NIST or academic paper that ran OSC TS + QP + AD against ns-3, ns-O-RAN or srsRAN. ns-O-RAN's own TS work (Lacava et al., WNS3 2023, https://www.nsnam.org/workshops/wns3-2023/05-lacava-slides-wns3-2023.pdf) uses its own RL TS xApp, not the OSC chain.

## Inference (code-derived, not stated by any source)
1. **The NIST patch silently disables VAR training.**
   - The patched `read_data` uses `range(start: -1600ms)` for *both* training and prediction. `insert.py` writes one 39-cell step every 0.4 s, so each cell has about 4 rows in the window.
   - Four rows is below the 10-row `constant()` gate, so no model file is ever written and QP returns the last value: a persistence predictor.
   - Upstream InfluxQL had no time bound and could train on up to 4,800 rows.
   - This repo's `ric-app-qp` (commit `381a824`) carries the same `-1600ms` window (`src/database.py` L93).
   - For live ns-3 data, ≥ 10 distinct cell rows within 1.6 s means a cell report period of about 150 ms or less.
2. **TS compares cumulative counters, not rates.** QP predicts the next *cumulative* `pdcpBytesDl`, so TS ranks cells by accumulated volume since run start. With Viavi ramps, this roughly tracks rate × elapsed time. With a per-period counter (e.g. KPM `DRB.PdcpSduVolumeDL`), the stationary path holds and VAR predicts the next period's volume, which is a more sensible comparison.
3. **The two bundled datasets are not mutually consistent.** `cells.csv` (run of 2021-06-11) and `ue.csv` (run of 2021-06-25) come from different Viavi runs, so a UE's serving/neighbour cells may have flat or zero traffic in `cells.csv`. Only 16 of the 39 cells carry traffic.
4. **Mapping to ns-O-RAN.** The original geometry (13 sites, 3 co-sited layers, 1,000 m spacing) and the UE mix (about 20–24 UEs, a few at 10–20 m/s) map to an ns-O-RAN scenario with co-sited multi-band gNBs. The xApps never relied on LTE/NR distinction: "B2/B13" are simply frequency layers.

## Source credibility
- Highest weight: code and bundled artefacts in gerrit (git history, embedded Viavi metadata). The Viavi config inside `cell.json.7z` is a primary record of the scenario.
- Next: O-RAN SC wiki pages (official, read through the REST API) and docs.o-ran-sc.org release notes.
- Context only: the Viavi case study, which is vendor marketing.
- Viavi units (speed in m/s, Gbps throughput) are inferred from the "250 Mbps" description; I found no Viavi manual to confirm them.

## Unresolved questions
1. Units of the Viavi `pdcpBytes*` fields (per-step increment = 10.24 × throughput: Mbit? kB?) and of `speed`. This would need the Viavi RIC Test user manual, which is not public.
2. Whether a later Viavi RIC Test live E2 (KPM 2.0.3) demo of AD+QP+TS happened (E/F "Integration ... with Viavi simulator") and with which scenario. I found no recorded config beyond the July 2021 files. The RICAPP meeting slides (`RICAPP-20-08-04.pptx`) and the Dawn demo recording were not reviewed.
3. Whether any team fixed QP's 1.6 s window under InfluxDB 2. If we feed ns-3 data, we must decide whether to widen the training range (e.g. `-10m`) or rely on persistence.
4. The source of `cells.csv` (2021-06-11 run) is not in git history, and its scenario config may differ from the 2021-07-02 config (e.g. 4 cars vs 1).

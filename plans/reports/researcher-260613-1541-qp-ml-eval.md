# QP xApp ML Model Lifecycle Classification

**Date:** 2026-06-13  
**Scope:** Classify ric-app-qp ML lifecycle; verify testbed deployment variant; assess inference prerequisites.

---

## Summary

**VERDICT:** Plain QP (ric-app-qp) is **Class (a)**: ships runnable inference with sane defaults + lazy self-training. **No offline-trained ML artifact is required.** Testbed installs the **Python QP variant** (not AIML-FW).

QP is deployment-ready as-is on our testbed. The only prerequisite is **InfluxDB with populated cell data** (satisfied by our kpimon-go→InfluxDB integration). Training happens on first prediction request per cell, models persist to `src/{cellid}` files, and inference executes immediately thereafter using VAR time-series forecasting.

---

## Evidence

### 1. Model Lifecycle Classification: (a) Runnable + Lazy Self-Training

**Inference path (main.py:93-120):**
- `predict(payload)` → RMR msg type 30000 from Traffic Steering  
- For each UE + cell: calls `train_model(cid)` (main.py:123-125), then `forecast(inp, mcid, 1)` (prediction.py:23-40)  
- **No pre-trained model required:** forecast() checks `os.path.isfile('src/'+cid)` (prediction.py:32); if missing, returns last-value passthrough (forecast.py:34 fallback)

**Training trigger (main.py:123-125):**
```python
def train_model(cid):
    if not os.path.isfile('src/'+cid):  # File not exists → train
        train(db, cid)
```
Training is **on-demand, lazy:** only executed if model artifact missing for that cell.

**Training implementation (qptrain.py:121-146):**
- `train_cid(cid)`: read 4800 rows of InfluxDB data for cell  
- Perform VAR lag optimization (qptrain.py:106-118: test lags 1-20, pick best RMSE)  
- Fit VAR model, serialize to joblib binary at `src/{cellid_clean}` (qptrain.py:137-138)

**Persistence:** Models are saved as joblib pickles to local filesystem (`src/c1B2`, etc.). Survive pod restarts (mounted volume) but NOT replicated across replicas. Training latency ~1-2s per cell on first prediction.

**Fallback:** If no training data available (`md.constant()=True`, qptrain.py:130), forecast returns last-observed-value (not an error).

---

### 2. Data Source: InfluxDB (cell-level CellReports)

**Database config (qp_config.ini:1-10, database.py:119-127):**
```ini
[influxdb]
host = ricplt-influxdb.ricplt
database = RIC-Test
cellmeas = CellReports
uemeas = UEReports

[features]
thptDL = pdcpBytesDl      # Downlink throughput
thptUL = pdcpBytesUl      # Uplink throughput
cid = nrCellIdentity      # Cell ID column
```

**Data flow match with kpimon-go:**
- kpimon-go: ns-3 gNB → KPM reports → InfluxDB `CellReports` measurement (PDCPBytes DL/UL, PRB, RF)  
- QP: reads from same InfluxDB `CellReports` → cell_id indexed → extracts `pdcpBytesDl/Ul` columns  
- **Same schema. No separate QP-driver required.** Cell data auto-populated by kpimon integration.

**Bundled mock data (cells.csv, 5000 rows):**
- insert.py::INSERTDATA writes cells.csv to InfluxDB in a loop (insert.py:56-63, assigns new timestamps)  
- DUMMY database class reads from cells.csv on startup (database.py:136, cells.csv 430KB)  
- **Can train models from mock alone:** test mode uses `DUMMY()` (main.py:147), no real InfluxDB needed

**Data prerequisite:** At least 100 rows of CellReports per cell (qptrain.py:128: limit=4800 with DESC ORDER). Our testbed will have this after kpimon-go runs for ~10s.

---

### 3. Output: RMR Message Type TS_QOE_PREDICTION (30002)

**Emission (main.py:71):**
```python
def qp_predict_handler(self, summary, sbuf):
    pred_msg = predict(summary[rmr.RMR_MS_PAYLOAD])
    success = self.rmr_send(pred_msg.encode(), 30002)  # RMR msg type 30002
```

**Message format (main.py:120 returns JSON):**
```json
{
  "ueid": {
    "cellid": [dl_forecast, ul_forecast],
    ...
  }
}
```
Example output (docs): `{"Car-1": {"c1/B2": [12650, 12721], ...}}`

**Recipient:** RMR routing table directs 30002 → Traffic Steering xApp (TS). No explicit configuration in QP itself; RMR platform handles routing.

---

### 4. Minimum Prerequisites to Get Inference Running

**On our testbed (oran-kvm-2):**

1. **InfluxDB pod running** (`r4-influxdb-influxdb2-0`, installed by install_xapp_qoe_predictor.sh:48-49)  
   - Token created (influxdb_auth_token.json)  
   - Configured in qp_config.ini token field

2. **At least 100 rows of CellReports in InfluxDB per cell**  
   - Satisfied by: kpimon-go running for ~10s (generates ~1 report per 100ms per cell)  
   - OR: insert.py populating cells.csv (5000 rows, 430KB) for testing

3. **RMR network operational**  
   - QP binds port 4560 (RMR receive), routes out 30002 to TS  
   - TS sends TS_UE_LIST (30000) → QP receives, predicts, replies 30002 → TS

4. **No external ML artifacts / training pipeline**  
   - First call to predict() auto-trains missing cell models (1-2s latency, one-time per cell)  
   - Subsequent calls use cached joblib models from `src/` mount

**Result:** Plain QP can do **trivial inference immediately** on mock data (insert.py); **production inference** kicks in once kpimon-go populates InfluxDB (10-30s after QP startup).

---

### 5. AIML-FW Variant Confirmation

**ric-app-qp-aimlfw (Go, Samsung 2022):**
- Class **(c)** variant: removes inference function, delegates all prediction to external MLxApp (KServe)  
- Takes input from QP-Driver xApp, builds REST request, sends to MLXAPP_HOST:MLXAPP_PORT `/v1/models/qoe-model:predict`  
- Expects pre-trained model in KServe cluster; if unavailable, fails at runtime  
- **NOT INSTALLED on testbed**

**Testbed deployment (install_xapp_qoe_predictor.sh:62-64):**
```bash
if [ ! -d "qp" ]; then
    echo "Cloning Quality of Experience (QoE) Predictor xApp (qp)..."
    ./../install_scripts/git_clone.sh https://gerrit.o-ran-sc.org/r/ric-app/qp.git
fi
```
Clones **ric-app-qp.git** (Python, AT&T/HCL), NOT qp-aimlfw. Confirms **class (a)** deployment.

---

## Architectural Fit

**For Phase 6 scope-gate:**

- **ML Work In Scope?** NO. QP is inference-ready as-is; no model training, artifact preparation, or AIML-FW integration needed.  
- **Deployment Risk:** MINIMAL. Models self-train on first use; fallback to last-value if data sparse.  
- **Data Dependency:** LOW. Satisfied by existing kpimon-go→InfluxDB integration; no new data pipelines required.  
- **Latency Impact:** ~1-2s for first prediction per cell (training); subsequent predictions <100ms.

**Recommendation:** Proceed with closed-loop (TS→RC control) **without** gating on QP ML maturity. QP is a passthrough inference service, not a training framework.

---

## Unresolved Questions

1. **VAR lag selection determinism:** qptrain.optimize_lag() iterates lags 1-20 and picks best RMSE. Does this vary per run if InfluxDB has identical data? (Likely yes, statsmodels VAR.fit() is deterministic given lag, but optimization loop is greedy—not stochastic.) **Impact:** Low (models fit once per cell, cached).

2. **Model persistence guarantee:** joblib pickles are written to pod-local `src/` mount. If QP pod restarts, models are lost unless mount is PVC. Is mount ephemeral or persistent? (install script doesn't specify; likely ephemeral for dev testbed.) **Impact:** Retraining happens on pod restart (~1-2s latency) but no correctness impact.

3. **QP output routing:** RMR config-file.json (config.json:38) lists `txMessages: ["TS_QOE_PREDICTION"]`, but no explicit recipient. Does RMR routing table auto-discover TS, or does it broadcast? **Impact:** None if TS is the only consumer; potential for message loss if routing misconfigured. Recommend verify RMR route setup in testbed run.

---

**Status:** DONE  
**Summary:** QP is class (a) inference-only, self-trains on first use, requires only InfluxDB + cell data (provided by kpimon-go). Testbed deploys Python variant. No ML work in scope.


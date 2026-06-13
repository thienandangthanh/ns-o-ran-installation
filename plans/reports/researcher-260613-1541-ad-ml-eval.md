# Anomaly Detection (AD) xApp: ML Model Lifecycle Analysis

**Research Date:** 2026-06-13  
**Analyst:** Researcher Agent  
**Scope:** Classified AD startup flow, model loading, data dependencies, and training trigger logic.

---

## Executive Summary

**VERDICT: Category (b) — HARD-REQUIRES offline-trained artifact before inference runs.**

AD ships no pre-trained model, expects a committed `src/model` joblib file. Startup calls `train_model()` which checks for this file; if missing, it attempts training from InfluxDB. However, training is **blocking and fragile**: requires ≥1000 training samples + ≥300 validation samples from InfluxDB in defined time windows, **with explicit population NOT happening during testbed install** (insert.py is commented out). Without pre-seeded data, startup hangs. **Inference cannot run until model exists.**

---

## 1. Model Lifecycle: Startup Flow

**File:** `src/main.py` (lines 37–62)

```
entry() flow:
  1. connectdb()           → connects to InfluxDB
  2. train_model()         → CHECK FOR ARTIFACT (line 60-62)
  3. load_model()          → load joblib files
  4. schedule.every(0.5s).do(predict, self)  → inference loop
```

**Line 60-62 (critical):**
```python
def train_model():
    if not os.path.isfile('src/model'):
        mt = ModelTraining(db)
        mt.train()
```

**Interpretation:** If `src/model` does not exist, training **blocks startup**. The xApp cannot proceed to `load_model()` until training completes.

---

## 2. Model Artifacts: Are They Committed?

**Status:** NO. Searched repo tree; no joblib files found:
```bash
find /home/andang/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-ad \
  -name "model" -o -name "num_params" -o -name "scale" -o -name "*.pkl" -o -name "*.joblib"
# Returns: (empty)
```

**Artifacts required:**
- `src/model` — joblib-serialized IsolationForest
- `src/num_params` — feature columns list
- `src/scale` — Normalizer scaler object

All three are **generated during training** (ad_train.py, lines 108–128) and **not in repo**.

---

## 3. Training Trigger and Data Prerequisites

**File:** `src/ad_train.py` (lines 46–70)

Training flow:
```python
class ModelTraining(object):
    def __init__(self, db):
        self.read_train()    # Lines 53-60: fetch ≥1000 samples from InfluxDB
        self.read_test()     # Lines 62-70: fetch ≥300 samples from InfluxDB
    
    def read_train(self):
        self.db.read_data(train=True)  # Query: time<now()-5m AND time>now()-75m
        while self.db.data is None or len(self.db.data.dropna()) < 1000:
            logger.warning("...Not sufficient data for Training")
            time.sleep(120)  # BLOCKING LOOP
            self.db.read_data(train=True)
```

**Requirements:**
- `src/model` must NOT exist (triggers training)
- InfluxDB must have ≥1000 non-null rows in measurement `ueMeasReport` (configurable via `ad_config.ini`)
- Data must span 75-minute training window + 5-minute validation window (time-based queries)
- **No fallback; no mock data; no graceful degradation**

**Query windows (database.py:77–94):**
- Training: `where time<now()-5m and time>now()-75m` (last 70 mins)
- Validation: `where time>now()-5m` (last 5 mins)

---

## 4. Data Source and Schema

**Source:** InfluxDB measurement (default: `UEReports` per README.txt:22)

**Columns read (features):** KPMs from UE reports:
- `RRU.PrbUsedDl` (PRB usage)
- `DRB.UEThpDl` (downlink throughput)
- `RRU.Dl.Seconds` (others defined in ad_config.ini)

**Is this the same as kpimon-go → InfluxDB data stream?**  
✅ **YES, semantically compatible.** kpimon-go writes KPM data to InfluxDB; AD reads from the same DB. However:
- AD **requires historical depth (1000+ samples)** for training
- AD **requires specific column names** in config (ad_config.ini, section `[features]`)
- **Mismatch risk:** If kpimon-go publishes different column names or schema, AD queries return empty

**Mock data fallback:** DUMMY class (database.py:145–149) uses hardcoded `src/ue.csv` but is only used if `connectdb(thread=True)` is called—this is NOT the production path.

---

## 5. Output: What Does AD Emit?

**File:** `src/main.py` (lines 82–114)

AD detects anomalies and sends:
```python
# RMR message type 30003 → Traffic Steering (TS)
msg_to_ts(self, val):
    success = self.rmr_send(val, 30003)  # Line 120
    
# Payload structure (lines 107–110):
{
  'UEID': <string>,
  'time': <timestamp>,
  'Degradation': <string>  # e.g., "Throughput RSRP"
}
```

**Message type:** `30003` (TS_ANOMALY_UPDATE) → triggers TS xApp to steer traffic  
**Recipient:** Traffic Steering (TS) xApp (RMR port implied)  
**Acknowledgement:** TS responds with `30004` (TS_ANOMALY_ACK)

**Is AD optional for TS?**  
❓ **UNKNOWN from code alone.** TS listens for message type `30003` but code review of TS xApp needed. Likely AD is **optional for TS to function** (TS can operate without anomaly input), but **AD enables closed-loop steering**.

---

## 6. Model Details: Algorithm and Validation

**Algorithm:** Isolation Forest (scikit-learn)
- **Lines 22, 87:** `IsolationForest(contamination=<tuned>, n_estimators=100–900)`
- **Hyperparameter search:** RandomizedSearchCV over contamination [0.01–0.5], n_estimators [100–900], max_samples [0.005–0.4]
- **Scoring:** F1-macro on validation set
- **Output:** Binary classification: 1 (anomaly, -1 in IsoForest), 0 (normal)

**Degradation classification (ad_model.py:94–130):** Rule-based post-processing:
```python
if throughput < threshold_baseline * (100 - threshold) / 100:
    degradation += "Throughput"
if rsrp < baseline_rsrp - 15:
    degradation += "RSRP"
if rsrq < baseline_rsrq - 10:
    degradation += "RSRQ"
```
(threshold defaults to 70%, configurable via A1 policy)

---

## 7. Variants: `ad` vs `ad-cell`

**Difference:**
- **`ad`** (UE-level): Detects anomalies in **individual UE** metrics (UEID)
- **`ad-cell`** (Cell-level): Detects anomalies in **5G cell** aggregated metrics

**Code topology:**
- Both are separate repos: `ric-app/ad.git` and `ric-app/ad-cell.git`
- Both install via separate scripts: `install_xapp_anomaly_detection.sh` and `install_xapp_5g_cell_anomaly_detection.sh`
- Both follow **same pattern: check for `src/model`, train if missing, then predict**

**ML lifecycle verdict:** **Both are category (b).** No pre-trained artifacts; both require InfluxDB data to train at startup.

**Testbed default:** Neither is pre-selected; install scripts are **optional additional scripts**. Deployment depends on user choice. kpimon-go is the only **mandatory** data pipeline.

---

## 8. Critical Failure Points

| Failure Mode | Trigger | Consequence |
|---|---|---|
| No `src/model` file + empty InfluxDB | Startup after fresh deploy | **Hangs indefinitely in training loop** (120s sleep × infinite retries) |
| Missing InfluxDB connection | DB unreachable | Logs error, sleeps 120s, retries (lines 73–75, 54–57) |
| Schema mismatch (kpimon columns ≠ config) | Config points to non-existent columns | Query returns empty; training hangs waiting for 1000 rows |
| No validation data | Training data ≥1000 but validation <300 in 5-min window | Hangs in `read_test()` (line 65–68) |
| Inference runs before model loads | Race condition in load_model() | **CRASH** at line 99 (`md.predict()` on None model) |

**Mitigation in current code:** NONE. No timeout, no retry limit, no graceful degradation.

---

## 9. A1 Policy Integration

AD listens for A1 policy (RMR message type 20010) to update the throughput threshold (lines 145–171):
```json
{
  "operation": "CREATE",
  "payload": "{\"thp_threshold\": 74}",
  "policy_instance_id": "demo-1",
  "policy_type_id": "9997"
}
```

This is **runtime tuning only**; does not affect model training.

---

## 10. Deployment Reality: Insert.py Not Called

**Install script:** `install_xapp_anomaly_detection.sh` (line ~223)
```bash
# echo "Inserting data into the InfluxDB..."
# POD_NAME=$(kubectl get pods --all-namespaces | grep ricxapp-ad | awk '{print $2}')
# kubectl exec -n ricxapp -it $POD_NAME -- /bin/sh -c "python3 /src/insert.py"
```

**Status:** COMMENTED OUT. The testbed does **NOT** pre-populate mock data from `src/ue.csv`. AD pod starts with **empty InfluxDB**.

**Required workaround:** kpimon-go must already be running and emitting data to InfluxDB *before* AD starts, *and* data must accumulate for ≥75 minutes before training succeeds.

---

## Summary Table

| Aspect | Finding |
|---|---|
| **ML Classification** | Category (b): Requires offline training |
| **Pre-trained model in repo?** | NO |
| **Training trigger** | Missing `src/model` at startup |
| **Data source** | InfluxDB `UEReports` measurement (same as kpimon-go) |
| **Training data prerequisite** | ≥1000 samples in 75-min window |
| **Inference readiness** | Only AFTER training completes |
| **Output** | RMR msg type 30003 to Traffic Steering |
| **Optional for TS?** | Likely YES (TS can function without AD) |
| **ad vs ad-cell** | Both category (b); UE-level vs cell-level variants |
| **Testbed insert.py called?** | NO (commented out) |

---

## Unresolved Questions

1. **Does TS xApp explicitly require AD output, or is it purely optional?** Needs TS code review.
2. **What is the actual kpimon-go → InfluxDB schema?** Are column names guaranteed to match `ad_config.ini` defaults?
3. **Is there a pre-seed step in the testbed automation that populates 75+ minutes of kpimon data before deploying AD?** Deployment sequence not documented in install script.
4. **How does the project plan to handle the 75-minute cold-start on first deployment?** No documented timeout or fallback.

---

**Status:** DONE  
**Summary:** AD is category (b)—requires offline training from InfluxDB. No runnable inference without ≥1000 historical KPM samples. Testbed install does not pre-populate data; AD will block at startup unless kpimon-go has already accumulated sufficient history.


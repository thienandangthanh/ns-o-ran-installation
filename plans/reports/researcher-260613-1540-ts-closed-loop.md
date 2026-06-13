# Traffic Steering xApp + Closed-Loop to RC: Research Report

**Phase 6 Scope Gate Analysis** | Date: 2026-06-13 | Researcher: Claude Code

---

## 1. INPUTS: QoE Predictions & Anomalies

### RMR Message Types (TS Receives)
TS listens on **port 4560** (config-file.json:19) for three inbound message types:

1. **TS_QOE_PREDICTION** (type 30002) — from QP xApp  
   - Contains throughput predictions per UE per cell  
   - **Payload format**: JSON object with UE ID keys → cell predictions {downlink, uplink}  
   - Parsed via `PredictionHandler` (ts_xapp.cpp:212–262)  
   - Extracts: `cell_pred_down`, `cell_pred_up`, `serving_cell_id`  
   
2. **TS_ANOMALY_UPDATE** (type 30003) — from AD xApp  
   - JSON array of anomalous UE IDs with metadata (DU-ID, degradation type)  
   - **Payload format**: `[{"du-id": 1010, "ue-id": "Train passenger 2", "Degradation": "RSRP RSSINR"}, ...]`  
   - Parsed via `AnomalyHandler` (ts_xapp.cpp:264–284)  
   - Callback: `ad_callback()` (ts_xapp.cpp:785–800)  
   
3. **A1_POLICY_REQ** (type 20010) — from A1 Mediator  
   - Policy type **20008** (A1-P decision thresholds)  
   - JSON: `{"operation": "CREATE", "policy_type_id": 20008, "payload": {"threshold": 5}}`  
   - Parsed via `PolicyHandler` (ts_xapp.cpp:141–210)  
   - Sets **downlink_threshold** global var (ts_xapp.cpp:521–524)  

### SDL Data (Not Required for Mock Run)
TS does **not read SDL directly** for QoE/anomaly data—it waits for RMR messages from QP and AD xApps.  
- KPIMON populates SDL with KPI metrics (README:37–38)  
- QP Driver reads SDL, computes predictions → sends RMR to TS  
- **Implication**: TS can run standalone with mock message injection (no live SDL needed)  

---

## 2. DECISION LOGIC

**Decision Point**: Callback `prediction_callback()` (ts_xapp.cpp:673–736)

**Algorithm**:
1. Receive TS_QOE_PREDICTION message (RMR type 30002)  
2. Extract UE ID, serving cell ID, and all cell throughput predictions  
3. Find **highest throughput prediction across all cells** (loop: 706–716)  
4. Apply **A1 policy threshold** (ts_xapp.cpp:718–721):  
   ```
   thresh = serving_cell_throughput × (downlink_threshold / 100.0)
   ```  
5. **Steer if**: `highest_throughput > (serving_cell_throughput + thresh)`  

**Output Decision**: `(UE ID, target_cell_id)` — handover target = highest-throughput cell.

**No explicit QP/AD model training in TS**—it consumes predictions already computed by external xApps.

---

## 3. OUTPUT: Control Message Emission

TS emits **two possible control transports** (config-file.json:52–55, ts_xapp.cpp:879–896):

### Option A: REST (Default)
- **Config**: `ts_control_api: "rest"`, `ts_control_ep: "http://127.0.0.1:5000/api/echo"`  
- **Function**: `send_rest_control_request()` (ts_xapp.cpp:529–604)  
- **Payload**: JSON HandOff command  
  ```json
  {
    "command": "HandOff",
    "seqNo": 1,
    "ue": "ueid-here",
    "fromCell": "CID1",
    "toCell": "CID3",
    "timestamp": "...",
    "reason": "HandOff Control Request from TS xApp",
    "ttl": 10
  }
  ```  
- **Recipient**: Custom REST endpoint (e.g., mock server, E2 adapter)  
- **Transport**: HTTP POST to `ts_control_ep`

### Option B: gRPC (To RC xApp)
- **Config**: `ts_control_api: "grpc"`, `ts_control_ep: "<rc-service-dns>:7777"`  
- **Function**: `send_grpc_control_request()` (ts_xapp.cpp:607–671)  
- **Proto**: `RicControlGrpcReq` (rc.proto:55–63)  
  - Destination: rc xApp's `SendRICControlReqServiceGrpc()` method (rc:14)  
  - Encodes: E2 RAN function ID 3 (ranfuncid:3, line 614), UE ID (GUAMI), **target cell ID** (line 637)  
  - **Key field**: `TargetCellID` (proto:50) — hex cell ID string  
  - **Recipient**: RC xApp gRPC stub at `ts_control_ep`

**RMR Output** (config-file.json:41–44):
- TS transmits **TS_UE_LIST** (type 30000) to QP xApp (routes.txt:3)  
- TS transmits **TS_ANOMALY_ACK** (type 30004) to AD xApp (routes.txt:4)  
- **Neither is a control request**—they are housekeeping replies.

---

## 4. STANDALONE (MOCK DATA)

### README Mock Mechanism (lines 34–73)
TS **can run without live QoE/anomaly sources** via docker + SDL mock injection:

```bash
cd test/populatedb
./populate_db.sh  # Helm chart writes mock SDL data
```

**How**:
1. Helm chart (populate_db.sh:22–24) builds image `ts-write-sdl:0.0.1` → writes network metrics to SDL  
2. TS still waits for RMR messages (QP, AD, A1), but **test/app/** provides mock senders:
   - `qp_xapp.cpp` — mock QP that reads SDL, sends synthetic TS_QOE_PREDICTION  
   - `ad_xapp.cpp` — mock AD that sends TS_ANOMALY_UPDATE  
   - Python REST mock server — echoes control requests  

**Conclusion**:
- ✓ TS **can run end-to-end without trained models**  
- ✓ Mock data substitutes for live KPI/prediction sources  
- ✓ Control logic is purely threshold-based, no ML in TS itself  

---

## 5. CLOSED LOOP: TS → RC → NS-3 (CRITICAL)

### Current State (Phases 4–5)
Manual rc path works:
```
grpcurl -d '{"ranFuncId": 3, ...}' rc-service:7777 rc.MsgComm/SendRICControlReqServiceGrpc
  → rc xApp processes request
  → encodes E2SM-RC RIC Control message
  → sends to e2term
  → ns-3 decodes, forces handover ✓
```

### Automated TS → RC Linkage

**TS Configuration for gRPC**:
- ts_xapp.cpp:879–896: If `ts_control_api == "grpc"`, build gRPC channel to `ts_control_ep`  
- rc_stub created: `rc::MsgComm::NewStub(channel, ...)` (line 895)  
- **Call site**: `send_grpc_control_request()` invokes `rc_stub->SendRICControlReqServiceGrpc()` (line 656)

**RC Acceptance** (rcService.go:14–60):
- RC listens on gRPC port (grpcserver.go:22) — **default port from config**: `controls.ricHOControlgRpcServerPort`  
- Validates mandatory fields: e2NodeID, targetCellID, UE GUAMI, RAN name, PLMN ID  
- If valid, **queues to channel** `gChan_RicControlReq_handle` (rcService.go:39)  
- Processes async → encodes E2SM-RC → sends to e2term (RAN function 300)

**Transport/Format Match**:
- ✓ TS emits gRPC proto `RicControlGrpcReq`  
- ✓ RC consumes `SendRICControlReqServiceGrpc(RicControlGrpcReq) → RicControlGrpcRsp`  
- ✓ **No proto mismatch**—same message definition (protocol/grpc/ricmsgcommrpc/proto/rc.proto)  

**Required Glue**:

1. **TS Config Update** — Set `ts_control_api: "grpc"` + `ts_control_ep: "service-ricxapp-rc-rmr:7777"` (K8s DNS or IP:port)  
2. **Cell Mapping** — TS calls `build_cell_mapping()` (ts_xapp.cpp:826–871) to populate `cell_map` (UE ID → RAN name, PLMN, E2 node ID). Requires E2MGR REST API endpoint (line 829–832, default: `http://service-ricplt-e2mgr-http.ricplt:3800`).  
3. **RC Config** — Ensure rc xApp config has correct gRPC port listening address (grpcserver.go:24).  
4. **RMR Route** — Testbed deployable scripts auto-configure RMR routing; no manual tuning needed if using OSC Helm charts.

**Reachability Classification**: **TRIVIAL**

**Justification**:
- No transport protocol mismatch (both use gRPC)  
- No message format gap (TS proto matches rc proto exactly)  
- Cell mapping is deterministic (E2MGR inventory → cell_map)  
- Only config change: YAML key `ts_control_api: "grpc"` + endpoint URL  
- RC callback is already production-ready (validates, queues, processes)

**Diff vs. Manual Phase 4–5 Path**:
- **Phase 4–5**: Manual `grpcurl` → rc (human-in-the-loop)  
- **Phase 6 Automated**: TS decision logic → `send_grpc_control_request()` → rc (closed loop)  
- **Additional requirements**: None beyond config change + cell mapping init

---

## Unresolved Questions

1. **QP xApp ML Training Scope** — Does QP embed pre-trained throughput models, or require live data training? (Deferred to Task #2)  
2. **AD xApp ML Training Scope** — Does AD embed pre-trained anomaly detection, or require live data training? (Deferred to Task #3)  
3. **E2MGR Cell Mapping Robustness** — What if cell inventory changes during runtime? (Minor risk; cell_map is loaded at startup only)  
4. **gRPC Channel Lifecycle** — Does rc_stub handle reconnection on service restart? (Likely handled by gRPC client layer; needs integration test)

---

**Status:** DONE  
**Summary:** TS xApp is a threshold-based steering decision engine consuming QoE predictions from QP, not a ML training pipeline. TS-to-RC closed loop is **trivial to implement**—configure TS to use gRPC (`ts_control_api: grpc`), point to RC service endpoint, and ensure cell mapping initialization. No proto/transport gaps; all machinery already exists in Phase 4–5 validated RC path. Mock data injection via SDL populator allows end-to-end testing without live KPI/model sources.


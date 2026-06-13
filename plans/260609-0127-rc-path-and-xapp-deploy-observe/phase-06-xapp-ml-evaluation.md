# Phase 6: xApp ML Evaluation (Scope-Gate) — M-RC3

**Date**: 2026-06-13
**Type**: Scope-gate / evaluation (NOT an implementation phase)
**Component**: OSC xApps ts / qp / ad vs. the proven RC control path
**Status**: VERDICT WRITTEN (M-RC3 exit met) — live demo decision pending user

## Scope-gate question (from plan)
Inspect `ts/ad/qp` xApp source: do they (a) ship a runnable model / sane defaults / self-train for
inference, (b) hard-require an offline-trained artifact, or (c) fetch from AIML-FW? **Decide if ANY ML
work is in scope.** If a closed loop (TS decision → rc gRPC → ns-3) is cheaply reachable, document the
minimal path; else defer. Project preference: **run existing inference, do not build/train a pipeline.**

## Method
3 parallel `researcher` agents (one per xApp) over LOCAL clones (`OSC-repos/`, `O-RAN-Testbed-Automation/`),
then direct source verification of the load-bearing claims. Evidence reports:
- `plans/reports/researcher-260613-1540-ts-closed-loop.md`
- `plans/reports/researcher-260613-1541-qp-ml-eval.md`
- `plans/reports/researcher-260613-1541-ad-ml-eval.md`

---

## Findings per xApp (a/b/c)

| xApp | Class | Lifecycle | Offline artifact needed? | On control path? |
|---|---|---|---|---|
| **ts** (traffic steering) | n/a (no ML) | Deterministic threshold decision engine | No | **YES** — emits the control |
| **qp** (QoE predictor) | **(a)** | Self-trains lazily, per-cell, on first predict | No | Indirect (feeds TS) |
| **ad** (anomaly detect) | **(b)** | Trains at startup if `src/model` absent; blocks until data | No (self-trains from DB) | Optional TS input |
| **qp-aimlfw** | **(c)** | Go variant, fetches model from AIML-FW | (framework) | **Not deployed** by testbed |

### TS — no ML; threshold logic (`ric-app-ts`, OSC `19e169b`, C++)
- Decision: `prediction_callback` picks highest predicted-throughput cell; steers if
  `highest > serving + serving*(thresh/100)` (`ts_xapp.cpp:673-736`, A1 threshold `:521-524`).
- Inputs via RMR: `TS_QOE_PREDICTION` 30002 (from QP), `TS_ANOMALY_UPDATE` 30003 (from AD),
  `A1_POLICY_REQ` 20010. No direct SDL read for the decision.
- **Runs standalone on mock data**: bundled `test/populatedb/` + `test/app/{qp_xapp,ad_xapp}` mock senders
  (README "Mock network data"). No live KPM / trained models required to exercise TS end-to-end.

### QP — class (a), self-training, no artifact (`ric-app-qp`, Python)
- `main.py:93-125`: `predict()` → if no model for cell → `train_model(cid)` → `qptrain.train(db, cid)`.
  No committed model artifact; model built on demand from DB data (in-memory).
- Data: InfluxDB cell reports (same family as our kpimon-go output); needs a minimum row count per cell
  before a prediction is meaningful. Bundled mock inserter for offline runs.
- Output: RMR `TS_QOE_PREDICTION` (30002) → TS.
- **Testbed deploys plain Python `qp`** (`install_xapp_qoe_predictor.sh` clones `ric-app/qp.git`), NOT the
  aimlfw Go variant. ⇒ no AIML-FW dependency on the deployed path.

### AD — class (b), trains-at-startup (`ric-app-ad`, Python)
- `main.py` `entry()` → `train_model()`; `train_model()`: `if not os.path.isfile('src/model'): ModelTraining(db).train()`
  (`main.py:60-62`). No committed artifact ⇒ first start trains from InfluxDB history; **blocks/retries until
  enough data** (researcher: ≥~1000 samples, 120s retry, no timeout → cold-start hang risk).
- Output: RMR anomaly msg (30003) → TS. **AD is an optional TS input**, not on the control path — TS steers
  off QP predictions; missing AD just means no anomaly-driven prioritization.

### qp-aimlfw — class (c), AIML-FW (not used)
- Go xApp fetching a trained model from AIML-FW. Confirmed as the (c) reference; the testbed does **not**
  install it. AIML-FW training pipeline therefore stays out of scope (matches plan intent).

---

## Closed loop TS → rc → ns-3 — reachable, LOW (bounded) effort

The transport already exists and is a perfect match — verified in source, not assumed:

- TS has a native gRPC control path: `send_grpc_control_request()` builds `rc::RicControlGrpcReq` and calls
  `rc_stub->SendRICControlReqServiceGrpc()` (`ts_xapp.cpp:607-671`, esp. `:611,:656`); selected by
  `ts_control_api == gRPC` (`:726-729,:888`).
- rc accepts exactly that: `rpc SendRICControlReqServiceGrpc(RicControlGrpcReq)` (`rc.proto:74`,
  msg `:55`, `TargetCellID :50`, `RICE2APHeaderData :59`).
- **The deployed testbed TS binary already has the gRPC stub compiled in** (`xApps/ts/ext/protobuf/rc.grpc.pb.cc:34`).
- This is the *same* `SendRICControlReqServiceGrpc` we drove manually with grpcurl in Phase 4/5. TS just
  replaces the human-in-the-loop grpcurl with automated decision logic.

**But it is not pure-config.** Direct source check surfaced bounded glue items:

1. **RAN-Function-ID mismatch (the real seam).** TS hardcodes `apHeader->set_ranfuncid(3)`
   (`ts_xapp.cpp:614`); rc forwards that value straight through as the E2 RAN-Function-ID
   (`rcControl.go:271` `lFuncId = ...RanFuncId`; `:274` `SetRicControlRequestPayload(..., lFuncId, ...)`).
   Our ns-3 registered the RC function as **funcId 300** (Phase 4/5), not 3. ⇒ align one integer:
   patch TS `:614` to 300 + rebuild the TS image, **or** register funcId 3 in ns-3, **or** make it
   configurable. Small, but a code touch + image rebuild, not a YAML flip. *(Phase 4/5 grpcurl worked
   because the operator sent funcId 300 explicitly.)*
2. **Cell-ID format.** TS sets `TargetCellID` from its `cell_map`/QP cell ids (`ts_xapp.cpp:637`); ns-3
   decodes `TargetCellID` as hex with cell N == `"110N"` (Phase-5 convention). TS's cell ids must be
   expressed in that form (or ns-3's decode generalized). This is the Phase-5 carry-forward
   "real NRCGI↔cellId mapping" item, now concrete.
3. **Cell-map bootstrap (mandatory).** TS builds `cell_map` from E2MGR REST
   (`service-ricplt-e2mgr-http:3800`, `build_cell_mapping()` `ts_xapp.cpp:826-871`); if a target cell is
   absent it **silently drops the control** (`:639-647`). rc also rejects requests missing
   E2NodeID/TargetCellID/GUAMI/RanName/PlmnID (`rcService.go:35`). ⇒ ns-3 gNB must be registered in E2MGR
   and its cell ids present in `cell_map` before TS can emit.
4. **GUAMI / UE id.** TS hardcodes GUAMI (VIAVI RSG values, `:627-629`) and maps `ue_id → amfUENGAPID`
   (`:622`). Phase 5 already established `amfUENGAPID == ns-3 IMSI`, so the UE id path is consistent.

**Classification: LOW effort / reachable.** No new subsystems, no proto/transport gap, gRPC already in the
deployed binary. Residual = one funcId integer + cell-id format mapping + E2MGR/endpoint config. Contrast
the researcher's "TRIVIAL/zero-code": the funcId pass-through (item 1) makes it low-code, not no-code.

---

## M-RC3 VERDICT

1. **No ML pipeline work is in scope.** None of the deployed xApps requires us to build or train an offline
   model: TS is deterministic; QP self-trains lazily from DB; AD self-trains at startup from DB (needs data
   present, not a pipeline); the AIML-FW (c) variant is not deployed. The only "ML-adjacent" effort is
   ensuring InfluxDB has data for QP/AD to self-train — that is data plumbing (our existing
   kpimon-go→InfluxDB path), not ML. **Matches the plan's "evaluate-only" intent → ML deferred/closed.**
2. **The closed loop is reachable (LOW effort)** and the minimal path is documented below. Transport + proto
   are a verified match already compiled into the deployed TS; the bounded glue is a funcId alignment, a
   cell-id format mapping, and E2MGR/endpoint config.
3. **Exit M-RC3 = written verdict: MET.** Executing the live demo is a discrete, stateful testbed operation
   (deploy qp+ts, flip config, run ns-3) — proposed as an optional follow-on, user-gated, not required to
   close Phase 6.

## Minimal closed-loop demo path (if/when executed)
Prereqs: ns-3 mmWave gNB registered in E2MGR; rc deployed (proven Phase 4/5).
1. Align funcId: TS `ts_xapp.cpp:614` `set_ranfuncid(3)` → `300` (rebuild TS image) **or** register funcId 3
   in ns-3 oran-interface. *(pick one; funcId-300 patch is the least-surprise.)*
2. Deploy QP (`install_xapp_qoe_predictor.sh`) so TS gets `TS_QOE_PREDICTION`; **or** drive TS with the
   bundled `test/app` mock QP to skip live data entirely for a first proof.
3. Configure TS: `ts_control_api: "grpc"`, `ts_control_ep: <rc gRPC svc>:7777`
   (`xApps/ts/.../config-file.json`), re-onboard/install (`install_xapp_traffic_steering.sh`).
4. Ensure TS cell ids reach ns-3 in `"110N"` form (item 2 above); confirm gNB cells present in `cell_map`.
5. Observe: TS decision → `SendRICControlReqServiceGrpc` → rc → E2SM-RC → ns-3 `handover from X to Y` + ACK
   (same evidence chain as Phase 5, now triggered automatically).
Validation hook: extend the M-series harness — pcap shows a Control Request whose **trigger was a TS gRPC
call** (not grpcurl); ns-3 log shows the correlated handover.

## Risks / bounded glue
- funcId pass-through (TS 3 vs ns-3 300) — must align or control is dropped by ns-3 (wrong RAN function).
- Cell-id encoding (`110N` hex) — Phase-5 carry-forward; TS/E2MGR cell ids must map to it.
- AD cold-start hang (`main.py:60-62`, no train timeout) — if AD is deployed, start it only AFTER InfluxDB
  has history, or it blocks. AD is optional for the loop ⇒ can be skipped for the demo.
- rc mandatory-field validation (`rcService.go:35`) — TS must populate E2NodeID/TargetCellID/GUAMI/RanName/PlmnID.

## Carry-forward / deferred
- Live closed-loop demo execution (deploy + run) — **deferred to a user-gated follow-on**.
- Canonical NRCGI↔cellId mapping (replaces `110N` hex convention) — Phase-7 / real-deployment concern.
- KPM indication-header timestamp truthfulness (open-Q6) — out of scope (would need kpimon-go v03.00 decoder
  upgrade); only matters if ML training-set timing is pursued, which this verdict says it is not.

## Open questions
- funcId 3 vs 300: confirmed pass-through in rc source; on-wire behavior to be confirmed when demo is run.
- QP/AD InfluxDB column-name match vs our kpimon-go schema: researchers flag a possible `ad_config.ini` /
  measurement-name mismatch (`UEReports`/`CellReports`); affects live-data self-training, not the mock demo.
  Verify against the live InfluxDB if the live (non-mock) loop is pursued.

**Plan reference**: `plans/260609-0127-rc-path-and-xapp-deploy-observe/plan.md` (Phase 6 row, M-RC3)

# Phase 6: xApp ML Evaluation (M-RC3 Milestone)

**Date**: 2026-06-13
**Severity**: Medium (scope-gate evaluation, not implementation)
**Component**: OSC xApps (ts / qp / ad) + RC closed-loop feasibility
**Status**: Resolved (verdict written)

## What Happened

Completed M-RC3 milestone: evaluated the three OSC xApps (traffic steering, QoE prediction, anomaly detection) to determine if any ML pipeline work was in scope. Three parallel researcher agents inspected source code in local clones (OSC-repos/ + O-RAN-Testbed-Automation/) and classified each xApp by its ML lifecycle. Verdict: **no offline ML training required**. TS is deterministic threshold logic; QP self-trains on first prediction; AD self-trains at startup from InfluxDB. The AIML-FW (class-c) variant is not deployed. Closed-loop (TS decision → rc gRPC → ns-3 handover) is **reachable with LOW bounded effort**, not the "zero-config" the parallel research summary initially claimed. Deferred live demo as user-gated follow-on.

## The Brutal Truth

The parallel research concluded the TS→RC loop was **"TRIVIAL / zero-code."** Reading the actual source code revealed a subtle but load-bearing mismatch: TS hardcodes `ranfuncid(3)` when building the gRPC control request, but rc forwards that value straight through as the E2 RAN-Function-ID, and our ns-3 registered RC as funcId 300, not 3. So an operator using grpcurl (Phase 4/5) could explicitly set funcId 300; TS cannot—it always sends 3. The control arrives at rc, rc encodes it with funcId 3, ns-3 discards it as an unknown RAN function.

This is not a "do this config tweak" problem. It is a "verify the pass-through chain and pick a seam to align" problem. No showstopper, but it means live closure requires either (a) a one-line TS patch + image rebuild, (b) registering funcId 3 in ns-3, or (c) making TS's funcId configurable. The researcher summary glossed over the transport layers and didn't trace the integer through the stack.

## Technical Details

**xApp Classification (source-verified)**:

1. **TS (traffic steering)**: No ML. Threshold-based decision (`prediction_callback()` ts_xapp.cpp:673-736). Inputs: QoE predictions from QP, anomalies from AD, A1 policy threshold. Decision: `highest_throughput_cell > serving_cell + (serving_cell × threshold%)`. Outputs via gRPC to RC (native stub compiled in ts.grpc.pb.cc:34) or REST (mock). Runs standalone on mock SDL data (`test/populatedb/`).

2. **QP (QoE predictor)**: Class (a)—runnable inference with lazy self-training. No pre-trained artifact in repo. On first prediction per cell, calls `train_model(cid)` → `qptrain.train()` → VAR lag optimization (1-2s) → serialize joblib to `src/{cellid}`. Subsequent calls use cached model. Data: InfluxDB `CellReports` (same schema as our kpimon-go output). Testbed deploys plain Python QP (not AIML-FW Go variant). Output: RMR 30002 to TS.

3. **AD (anomaly detection)**: Class (b)—requires offline training from InfluxDB. Startup calls `train_model()` → if `src/model` absent, blocks on `ModelTraining(db).train()` (main.py:60-62). Requires ≥1000 samples in 75-minute window + ≥300 in 5-minute validation window (ad_train.py:71-76, retry 120s loop, **no timeout**). Install script comments out `insert.py` (no mock data pre-population). AD will cold-start hang unless kpimon-go has accumulated 75+ minutes of history. AD is optional for TS (not on control path, only feeds anomaly messages).

4. **qp-aimlfw**: Class (c)—Go variant fetching trained models from AIML-FW. Not installed by testbed. Out of scope.

**Net**: Only data plumbing needed (InfluxDB present for self-training). No offline pipeline work.

**The funcId Seam (critical catch)**:
- TS sends: `apHeader->set_ranfuncid(3)` (ts_xapp.cpp:614)
- rc forwards: `lFuncId = ...RanFuncId` (rcControl.go:271), then `SetRicControlRequestPayload(..., lFuncId, ...)` (rcControl.go:274)
- ns-3 registered: funcId 300 (Phase 4/5)
- Result: Control reaches rc, rc encodes it with funcId 3, ns-3 ignores it (wrong RAN function). Alignment needed.

**Cell-ID Format (Phase-5 carry-forward)**:
TS sets `TargetCellID` from `cell_map` (ts_xapp.cpp:637); ns-3 decodes as hex (`"110N"` = cell N). TS's cell ids must map to that form, or E2MGR cell inventory must be aligned.

**Cell-Map Bootstrap (mandatory)**:
TS calls `build_cell_mapping()` (ts_xapp.cpp:826-871) → queries E2MGR REST (`:3800`). If target cell absent, silently drops control (`:639-647`). rc also validates required fields (rcService.go:35). ns-3 gNB must be registered in E2MGR before TS can emit.

## What We Tried

1. **Parallel classification of xApps**: Three agents independently analyzed TS, QP, AD source to determine ML artifact requirements.
2. **Trust-but-verify source inspection**: Researchers' "TRIVIAL" summary prompted deep read of TS→RC gRPC stack; uncovered funcId pass-through.
3. **Traced the control path end-to-end**: TS encode → rc forward → ns-3 decode; identified the funcId 3/300 mismatch.

## Root Cause Analysis

**Why the researcher summary missed the funcId seam**: The summary layer checked that TS has gRPC support and rc accepts gRPC messages, concluding "no protocol gap." It did not trace the **content** of the TS gRPC encode (hardcoded `set_ranfuncid(3)`) through the rc forward (pass-through) to the ns-3 decode (funcId 300 expected). A surface-level "same proto" check is not enough; the integer value itself is load-bearing.

**Why AD will cold-start hang**: The startup training loop has no timeout (ad_train.py:72-75, `time.sleep(120)` → retry forever). If InfluxDB is empty, AD blocks indefinitely. Install script does not pre-populate mock data (`insert.py` commented out). This is a testbed-integration risk, not a verdict problem—AD is optional, and deferring it to live demo avoids the hang.

## Lessons Learned

1. **Summary-layer research is a starting point, not ground truth**: "Zero-code," "TRIVIAL," etc., are useful for triage but must be verified against source. A researcher correctly identified no protocol mismatch, but did not trace the hardcoded integer through the stack.

2. **Integer pass-throughs are silent landmines**: `set_ranfuncid(3)` looks like configuration but is hardcoded. No comment in rc's forward path explaining why it passes the value straight through. If someone later changed TS to set funcId 300 without checking rc, or changed ns-3 to register 3, the loop would break silently (control drops, no error).

3. **Testbed topology constrains the closed loop**: Only the gNB is a live E2 node on oran-kvm-2 (Phase 5 pivot already taught this). E2MGR must know the gNB's cells. If TS's cell_map is empty (E2MGR unreachable or out of sync), TS silently drops control. Timing: E2MGR REST must be reachable at TS startup, and gNB cells must already be registered.

4. **Self-training is not "pipeline work"**: QP and AD do not require us to build a pipeline. They self-train from InfluxDB if data exists. The "ML-adjacent" work is ensuring the data is there (kpimon-go→InfluxDB, already in place). Do not conflate runtime self-training with offline artifact preparation.

5. **Optional components can be deferred safely**: AD is optional for TS (not on control path). QP alone suffices to drive TS→rc loop. Defer AD to live demo to avoid the cold-start hang and the 75-minute InfluxDB warm-up. Phase 6 verdict is unaffected.

## Next Steps

**M-RC3 complete**: Scope-gate verdict written. No ML pipeline work in scope.

**Minimal closed-loop demo path (if/when executed, deferred as user-gated follow-on)**:
1. Align funcId: patch TS `ts_xapp.cpp:614` to `set_ranfuncid(300)` + rebuild image **or** register funcId 3 in ns-3 oran-interface.
2. Deploy QP (plain Python, self-trains); optionally inject mock data to skip live InfluxDB warm-up.
3. Configure TS: `ts_control_api: "grpc"`, `ts_control_ep: service-ricxapp-rc-rmr:7777` in config-file.json.
4. Ensure E2MGR bootstrap: ns-3 gNB registered, cell ids in `cell_map` in `"110N"` hex form.
5. Observe: TS decision → gRPC `SendRICControlReqServiceGrpc` (now with aligned funcId) → rc → E2SM-RC → ns-3 handover + ACK.

**Carry-forward**:
- Live demo execution (deploy TS+QP, align funcId, run ns-3, capture pcap + ns-3 logs) — user-gated follow-on.
- Canonical NRCGI↔cellId mapping (replace `"110N"` hex convention) — Phase-7 / real deployment concern.
- AD cold-start hang mitigation (e.g., InfluxDB pre-seed or startup timeout) — not in Phase-6 scope since AD is optional.

**Commits** (not pushed):
- oran-interface: none (no code changes; verdict only)
- ns3-mmwave-oran: none
- superproject: none

**Artifacts**:
- Research reports: plans/reports/researcher-260613-154{0,1}*.md (3 variants: ts, qp, ad)
- Phase plan: plans/260609-0127-rc-path-and-xapp-deploy-observe/phase-06-xapp-ml-evaluation.md (detailed)

**Plan reference**: `plans/260609-0127-rc-path-and-xapp-deploy-observe/plan.md` (Phase 6 row, M-RC3)

---

**Unresolved / Next**:
- funcId 3 vs 300: source verified pass-through, but on-wire alignment to be confirmed when live demo executes.
- QP/AD InfluxDB column-name match vs our kpimon-go schema (`UEReports`/`CellReports` measurements, `pdcpBytesDl` columns). Researchers flag possible `ad_config.ini` mismatch. Verify against live InfluxDB if live (non-mock) loop pursued.
- Canonical NRCGI encoding (Phase-7 concern).

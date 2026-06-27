# Phase 6b · Stage D (detailed) — Mock-prediction TS→rc→ns-3 multi-UE/multi-gNB loop (M-RC4)

**Date**: 2026-06-27
**Parent**: `phase-06b-live-closed-loop-demo.md` (Decision 4 §Stages → Stage D)
**Type**: Live testbed execution (oran-kvm-2). Code is DONE/committed; this stage is orchestration + a mock injector + one TS rebuild.
**Goal**: Drive ≥2 forced mmWave handovers (≥2 distinct UEs, target cells on ≥2 distinct E2 nodes) **from the TS xApp's own gRPC control emit**, triggered by a **mock QoE prediction** (RMR `TS_QOE_PREDICTION` 30002) — replacing the Phase-4/5/Stage-A `grpcurl`.
**Exit M-RC4**: pcap shows ≥2 `RICcontrolRequest`→`RICcontrolAcknowledge` pairs; ns-3 log shows ≥2 distinct `handover from X to Y` for ≥2 distinct IMSIs; the trigger is TS (`send_grpc_control_request`), evidenced by TS pod logs with **no grpcurl in the loop**; the ≥2 targets resolve to ≥2 distinct `cell_map` owning nodes.

---

## Why this is now executable (prereqs already GREEN)

- **SCTP blocker RESOLVED (2026-06-27)** — process-global `client_fd` → per-instance `E2Sim` member (`oran-e2sim 75257c7`, pin `222ac76`). Verified live: a control fanned to all 5 nodes `gnb_734_373_16b8ce0{1..5}` → **5/5 receive + decode (funcId 3) + ACK**. `scripts/phase6b-verify-multinode-recv.sh`.
- **Decision-4 code committed** — per-gNB E2 identity + real served-cell NRCGI bytes (`oran-e2sim`), funcId-3 dual-register (`oran-interface`, `ns3-mmwave-oran`), pin `52f547e`.
- **Stage C′ proven** — E2MGR shows 5 distinct nodes; each `e2nodeComponentRequestPart` decodes to `16B8CE0N0N`; ranName suffix `16b8ce0N`. **Case render is inverted from the journal's first guess**: requestPart hex = **UPPERCASE**, ranName suffix = **lowercase** → the TS case-insensitive grep fix is load-bearing and correct.
- **Stage A′ proven** — grpcurl funcId-3 still routes to ONE specific node among 5 + per-UE (imsi) targeting.

**What is NOT yet done (this stage does it):**
1. TS `ts_xapp.cpp` case-insensitive fix is applied on the VM testbed tree (`ts_xapp.cpp.orig-phase6b` backup) but **the trafficxapp image is NOT rebuilt/re-onboarded** → the running TS still has the old grep → `cell_map` is still empty in the live pod. **D0 fixes this.**
2. No mock prediction injector exists yet. **D2 builds it.**
3. `grpcurl` has driven every prior handover. **D3/D4 replace it with a TS-emitted control.**

---

## Verified mechanics this stage relies on (source-grounded, do not re-derive)

- **TS `prediction_callback` is self-contained** (`ts_xapp.cpp:677`, registered `:906` for 30002). It does NOT require TS to have first sent a `TS_UE_LIST`/30000 request (`:742`) or an anomaly. An **unsolicited 30002** drives it end-to-end. Flow: first JSON key = serving cell (`:225-227`); pick highest-throughput cell; if `highest_throughput > serving + thresh` (`:727`, `thresh = serving*(downlink_threshold/100)` `:724`) → `cell_map.find(target_cell_id)` (`:643`) → on hit, `send_grpc_control_request` (gRPC branch `:730`); on miss → **silent `return`** (drops control).
- **Prediction JSON shape**: `{"<ueId>": {"<servingKey>":[dl,ul], "<targetKey>":[dl,ul], ...}}`. Keys must be the **10-char `cell_map` keys** `16B8CE0N0N`. `<ueId>` → `amfUENGAPID` → ns-3 IMSI.
- **`cell_map` is built ONCE at TS startup** (`build_cell_mapping`, `main:~890`) from E2MGR REST (:3800). ⇒ **TS must (re)start AFTER all gNBs are CONNECTED.**
- **rc mandatory fields** are populated by TS itself: `ranfuncid(3)`, `controlstyle(3)/actionid(1)`, `amfuengapid=ue_id`, `gnbcuuef1apid/gnbcucpuee1apid=ue_id` (rc forward layer `rcControl.go:119-135` requires these non-empty — TS satisfies it), GUAMI hardcoded (VIAVI). The mock only supplies `ueId` + cell keys + throughput.
- **Wire/decode chain (unchanged, proven)**: `target_cell_id` = 10-char key → rc hex-decodes 5 bytes → ns-3 reads **last byte = N** (`ric-control-message.cc:274`) → `PerformHandoverToTargetCell(imsi, N)` via LTE master RRC (Option B). Valid mmWave targets are **{2,3,4,5}** (Phase-5 proved 4,5); invalid target → clean reject (`MmWaveCellExists` guard), no crash.
- **Bundled mock `test/app/qp_xapp.cpp` is NOT usable as-is**: it is request-driven (responds to 30000), emits **random** throughput on placeholder keys `CID1/2/3`, and uses a local `127.0.1.1` route table. Reuse its RMR/rapidjson scaffolding only.

---

## Stage D execution (sub-steps D0–D5)

### D0 — TS rebuild + re-onboard (the gating prereq)
- Clean slate: `sudo pkill -9 -f scenario-zero`; clear RNIB (e2mgr `PUT /v1/nodeb/shutdown` :3800).
- Confirm the case-insensitive fix is in the VM tree: `diff ts_xapp.cpp.orig-phase6b ts_xapp.cpp` (NodebHandler `~:347-366` normalises both prefix and compared substring to one case).
- Confirm `xapp-descriptor/config-file.json` `controls`: `ts_control_api:"grpc"`, `ts_control_ep:"service-ricxapp-rc-grpc-server.ricxapp:7777"` (baked at onboard; backup `config-file.json.orig`).
- Rebuild image + re-onboard: `cd …/Near-Real-Time-RIC && sudo ./additional_scripts/install_xapp_traffic_steering.sh` (builds image + `dms_cli onboard` + install). If the script is idempotent-install only, force: rebuild docker image, `dms_cli onboard`, uninstall+install the trafficxapp.
- **Verify**: `kubectl -n ricxapp get pod -l app=ricxapp-trafficxapp` Running; TS logs show gRPC channel to rc established; image tag/digest changed from the prior deploy.

### D1 — Topology up + `cell_map` verification (the de-risk GATE — do before any injection)
- Start ns-3 (5 gNBs): reuse `scripts/phase6b-start-ns3.sh`, but wait for **5** CONNECTED (the multinode-recv script already has the 5-node wait loop — lift that). `simTime` max **100** (DoubleChecker), `--handoverMode=NoAuto`, pod-IP connect, `--reducedPmValues=1`.
- After 5 nodes CONNECTED in `/v1/nodeb/states` (`gnb_734_373_16b8ce0{1..5}`), **restart the TS pod** (`kubectl -n ricxapp delete pod -l app=ricxapp-trafficxapp`) so `build_cell_mapping` runs against a populated RNIB.
- **GATE — verify `cell_map` is non-empty (the entire payoff of the bilateral fix):** in TS logs after restart, confirm the cell→node mapping built **5 entries** keyed `16B8CE0N0N`. (Pre-fix this was empty → every control dropped at `:643`. First end-to-end confirmation it is populated.) If empty → STOP; re-check the case-fix render against Stage-C′ facts (requestPart UPPERCASE).
- **Discovery (records for crafting predictions):**
  - imsi→serving-cell map: grep ns-3 log for UE attach / connection (which IMSI sits on which cell under NoAuto — stable). Phase-5 reference: imsi 1 on cell 2.
  - Valid mmWave handover targets: {2,3,4,5} (Phase-5 proved 4,5; smoke 2,3 with one grpcurl if unsure). Note cell **1** registers as an E2 node (so 5 nodes) but is the LTE eNB identity / likely NOT a valid handover target — **never target cell 1**. *(Reconcile the 4-mmWave-gNB vs 5-E2-node count here empirically; does not block — only target verified mmWave cells.)*

### D2 — Build the deterministic mock injector (resolves the parent's central open-Q)
**Decision: push an UNSOLICITED, deterministic `TS_QOE_PREDICTION` (30002) into the live TS pod.** (Source-verified D-mechanics above justify push-only.)
- **Injector form (DECIDED — validation 2026-06-28): in-cluster Python RMR sender.** A small `ricxappframe.rmr` program that `rmr_send`s mtype **30002** with the crafted JSON, run **in-cluster** (transient pod / `kubectl run` an image that has `ricxappframe`, or exec inside an existing xApp pod that ships it) so RMR reaches the TS RMR endpoint. Fastest to iterate, no C++/container build, full control of the JSON; lives in the committed `scripts/` tree.
  - Fallback (only if the Python RMR runtime is awkward to place in-cluster): adapt `test/app/qp_xapp.cpp` to (i) push 30002 on a timer instead of only-on-30000, (ii) emit our 10-char keys, (iii) deterministic throughput — but this is a VM-testbed-tree C++ build, so prefer Python.
- **RMR delivery to TS**: TS listens RMR on **4560** (`routes.rt`: `mse|30002|-1|…:4560`). Discover the in-cluster endpoint: `kubectl -n ricxapp get svc | grep traffic` (expect `service-ricxapp-trafficxapp-rmr`). Deliver via a static route table (`RMR_SEED_RT` mapping `30002 → <ts-rmr-svc>:4560`) so the sender does not depend on rtmgr distributing a route for an unregistered app. Smoke the path first (sender connects, TS logs "Prediction Callback got a message").
- **Threshold**: make the gate fire unambiguously — serving `[1,1]`, target `[9000,9000]`. Confirm the A1 `downlink_threshold` default does not require an A1 policy push; if it does, push the A1 policy (mtype `A1_POLICY_REQ` 20010) or set a low threshold. (Open-Q: default value — read at D2.)
- **Craft JSON** (per UE): `{"<imsi>": {"<servingKey>":[1,1], "<targetKey>":[9000,9000]}}` where `servingKey` = that UE's actual serving cell key (first key = serving), `targetKey` = a **verified valid mmWave** cell key on a **different** gNB.

### D3 — Single-UE proof (isolate injection/routing before multi)
- Start tshark (`-f 'sctp'`), inject ONE prediction for UE A.
- **Observe** in order: TS log `Prediction Callback` → threshold crossed → `send_grpc_control_request` (funcId 3, target node resolved from `cell_map`) → rc "Success Response" + forward → ns-3 `RIC Control Request: imsi=A targetCellId=Qa` → `RC forced handover … via LTE master RRC` → `handover from servingA to Qa` → `Generated RIC Control Acknowledge (funcId=3)`; pcap has the Request→Ack pair.
- If TS logs the callback but **drops at `cell_map.find`** → target key not in map (re-check D1 keys). If threshold not crossed → raise target throughput / fix A1 threshold.

### D4 — Multi-UE / multi-gNB loop (the M-RC4 core)
- Inject **≥2** predictions: UE A → target `Qa` (owning node a), UE B → target `Qb` (owning node b), with **node a ≠ node b** and **imsi A ≠ imsi B**, each target a verified mmWave cell ≠ its serving cell.
- **Observe**: ≥2 TS `send_grpc_control_request` emits → rc forwards both → ns-3 logs **2 distinct** `handover from X to Y` for **2 distinct IMSIs** → 2 ACKs on wire; `cell_map` resolved 2 distinct owning nodes (multi-gNB routing proven).
- Capture one combined pcap + one ns-3 log spanning both controls.

### D5 — Evidence, provenance, re-runnable script, M-RC4 assertion
- **Provenance caveat (must document)**: on the wire a TS-emitted control and a grpcurl-emitted control are byte-identical (both → rc → same E2 control). The pcap alone CANNOT prove "TS-triggered." Provenance = **TS pod log** (`send_grpc_control_request` line) timestamp-correlated to the wire Control Request, **plus** the fact that **no grpcurl runs in the loop**. State this explicitly in the result.
- Write `scripts/phase6b-closed-loop-run.sh`: clean → start ns-3 (5 gNBs, wait 5 CONNECTED) → restart TS → assert cell_map non-empty → start tshark → run mock injector (≥2 UEs) → grep TS+ns-3 logs + pcap → print PASS/FAIL. Mirror the structure of `phase6b-verify-multinode-recv.sh` (setsid/tshark/wait-loop/results block).
- Extend `scripts/l-release-validation/`: add an **M-RC4** assertion — pcap has ≥2 Control Request/Ack pairs; ns-3 log has ≥2 distinct handovers for ≥2 IMSIs; a TS log line precedes each. Keep the byte-signature style of the existing M-series.

*(Stage E — real QP — and Stage F — finalize/commit/docs/journal — remain as in the parent doc; this plan covers Stage D only. Stage F's commit set will add the mock injector + `phase6b-closed-loop-run.sh` + M-RC4 assertion; no fork code changes are expected in Stage D — TS lives in the testbed tree, not our forks.)*

---

## Files

**Create (committed tree, virtiofs):**
- `scripts/phase6b-closed-loop-run.sh` — re-runnable clean→ns-3→TS-restart→mock-inject→capture→assert.
- mock injector — `scripts/phase6b-mock-qp-inject.py` (in-cluster Python `ricxappframe.rmr` 30002 push; DECIDED at validation).
- `scripts/l-release-validation/` M-RC4 assertion (extend existing harness; exact filename per that dir's convention).

**Modify (VM testbed tree — NOT our forks, document only):**
- `…/xApps/ts/src/ts_xapp/ts_xapp.cpp` — case-insensitive grep (already applied; rebuilt at D0).
- `…/xApps/ts/xapp-descriptor/config-file.json` — gRPC control endpoint (already applied).

**No edits expected** in `oran-e2sim` / `oran-interface` / `ns3-mmwave-oran` (Decision-4 + SCTP fix already committed).

---

## Risks / mitigations
- **`cell_map` still empty after TS rebuild** (case-fix wrong / E2MGR render assumption off) → D1 GATE verifies the 5 keys directly before any injection; Stage-C′ already empirically pinned the render (requestPart UPPERCASE, ranName lowercase).
- **RMR 30002 never reaches the TS pod** (k8s routing) → use a static `RMR_SEED_RT` to `<ts-rmr-svc>:4560`, run the sender in-cluster, smoke-test the callback log before crafting real predictions.
- **Threshold gate never fires** (A1 `downlink_threshold` default high / unset) → exaggerate target throughput (serving `[1,1]`, target `[9000,9000]`); push an A1 policy if a default is required.
- **Target not in `cell_map` → silent drop** (`:643`) → only target keys verified present in D1.
- **Targeting cell 1 / LTE identity** → never target cell 1; restrict to verified mmWave {2,3,4,5}.
- **UE not actually on the claimed serving cell** → discover imsi→serving in D1; set JSON serving = real, target = different valid mmWave cell.
- **TS image config baked** → re-onboard (D0), not just pod restart, when config changed.
- **VM load + ns-3 CPU** → bounded `simTime≤100`, one ns-3 at a time, `pkill -9` between runs, inject within the sim window.
- **Provenance not provable from pcap** → rely on TS pod log + no-grpcurl; documented in D5.

## Open questions (resolve during the run)
1. Exact TS RMR service/port for in-cluster 30002 delivery (D2: `kubectl get svc -n ricxapp | grep traffic`; expect `service-ricxapp-trafficxapp-rmr:4560`).
2. A1 `downlink_threshold` default — does the gate fire without an A1 policy push? (D2.)
3. Are all 5 registered E2 nodes valid handover targets, or is cell 1 the LTE eNB (valid E2 node, invalid HO target)? Reconcile 4-mmWave-gNB vs 5-E2-node count. (D1; does not block — target verified cells only.)
4. ~~Mock injector form~~ — **RESOLVED (validation 2026-06-28): in-cluster Python `ricxappframe.rmr` sender.** Only sub-question left: where the Python+RMR runtime runs in-cluster (transient pod image vs exec inside an xApp pod that ships `ricxappframe`) — D2 placement detail, not a design choice.

---

## Validation Log

### Verification Results (2026-06-28)
- Tier: **Light** (single phase, 6 sub-steps; Fact Checker).
- Claims checked: 6 · **Verified: 6 · Failed: 0 · Unverified: 0**.
- Evidence: `scripts/l-release-validation/` exists (M1–M5 → M-RC4 extensible); `ric-control-message.cc:274` last-byte NRCGI read confirmed verbatim; TS `ts_xapp.cpp` line refs (677/906/698-731/643/225-227/742) + `routes.rt` `30002→4560` verified live (read-only ssh); `phase6b-*`/`phase4-rc-live-run.sh` present.
- No FAILED claims → plan eligible for implementation.

### Decisions confirmed (interview 2026-06-28)
1. **Injector form** → in-cluster **Python `ricxappframe.rmr`** 30002 push (C++ `qp_xapp.cpp` = fallback only). Propagated to D2 + Files; open-Q4 resolved.
2. **M-RC4 exit scope** → **≥2 UEs / ≥2 distinct owning gNBs** (already the plan's D4 goal; no change).
3. **Stage E (real QP)** → **deferred** to a follow-on (open-Q8 InfluxDB schema match out of this push; already the plan's stance; no change).
4. **A1 threshold** → **exaggerate throughput only** (serving `[1,1]` / target `[9000,9000]`); no A1 policy push in the mock loop (already the plan's D2 stance; no change). The default `downlink_threshold` is still read at D2 only to confirm the exaggeration clears it.

### Whole-Plan Consistency Sweep (2026-06-28)
- Re-read the Stage-D plan + parent `phase-06b-live-closed-loop-demo.md` pointer + `plan.md` Phase-6 results. No contradictions: decisions 2–4 matched the plan's existing recommended stances; decision 1 narrowed an open option (no stale alternative left dangling — D2, Files, and open-Q4 all updated). Parent-doc Stage-D pointer remains accurate. **Zero unresolved contradictions.**

**Parent**: `phase-06b-live-closed-loop-demo.md` · **Plan**: `plan.md` (Phase 6, M-RC3 → M-RC4 live) · **SCTP-fix journal**: `docs/journals/2026-06-16-phase6b-decision4-multi-gnb-closed-loop.md` (Correction 2026-06-27).

---

## Results — M-RC4 ACHIEVED (2026-06-28)

**Status: GREEN.** A mock RMR `TS_QOE_PREDICTION` (30002), injected in-cluster, drove the TS xApp's own gRPC control emit → **2 distinct forced mmWave handovers** for **2 distinct IMSIs** on **2 distinct owning gNBs**, with **no grpcurl** in the loop. The re-runnable `scripts/phase6b-closed-loop-run.sh` prints `RESULT: PASS`; `scripts/l-release-validation/m-rc4-closed-loop.sh` asserts all checks (exit 0).

**Evidence (oran-kvm-2):** `captures/phase6b-closedloop-1782599483.pcapng` (RICcontrolRequest x2 + RICcontrolAcknowledge x2), `…-ns3-1782599483.log` (handover from 2→4 imsi 1, 2→5 imsi 7; ACK inst 24/2), `…-ts-1782599483.log` (2 `Control Request succeeded`, 0 cell_map drops).

### Per-substep outcomes
- **D0 — NOT NEEDED (key finding).** The *un-rebuilt* TS image already builds a working `cell_map`, keyed **UPPERCASE** `16B8CE0N0N`. Reason: the served requestPart decodes uppercase (Stage C′) and the old `toupper`-prefix grep matches it. The committed lowercase case-fix only changes the resulting key *case*; it does not fix a real breakage on this E2MGR. ⇒ mock JSON keys must be **UPPERCASE** against the deployed image (a D0 rebuild would flip them to lowercase). **Decision deferred to user** (source⇄deploy parity vs keep the working image).
- **D1 — cell_map GATE passed** via first routed injection (no `Cannot find RAN name`), since `cell_map` has no positive logging. imsi→serving-cell map under NoAuto (12 UEs = 3×4 gNBs): **cell 2 = {1,7,9}, cell 3 = {12}, cell 4 = {5,11}, cell 5 = {2,4,6,8,10}**; cell 1 = LTE eNB (never targeted).
- **D2 — injector built + RMR path proven.** `scripts/phase6b-injector.Dockerfile` (python:3.11-slim + librmr vendored from the TS pod + `ricxappframe==3.2.2`; needs `gcc`/`libc6-dev` for hiredis); `scripts/phase6b-mock-qp-inject.py` writes its own seed RT (`30002 → service-ricxapp-trafficxapp-rmr.ricxapp:4560`). Smoke (ns-3 down): TS logged `Prediction Callback got a message, type=30002` then the expected `Cannot find RAN name` (empty cell_map). A1 `downlink_threshold` default = **0** ⇒ gate `highest>serving` fires with serving `[1,1]`/target `[9000,9000]`, **no A1 policy push**.
- **D3 — single-UE proof:** imsi 1 (cell 2) → cell 4: TS `Control Request succeeded code=0` → ns-3 `funcId 3` → `targetCellId=4` → `RC forced handover via LTE master RRC` → ACK → `handover from 2 to 4`.
- **D4 — multi-UE/multi-gNB:** added imsi 7 (cell 2) → cell 5 (node …05, distinct from imsi 1's …04) → `handover from 2 to 5`. **Two real fixes were needed beyond the keys:** (1) the **rc xApp restarts intermittently** — a TS→rc gRPC during an rc restart fails `UNAVAILABLE (Socket closed/Connect Failed)`; the script now `wait_rc`s for rc Ready before injecting. (2) the **LTE master RRC serializes EN-DC handovers** (concurrent 2nd HO rejected: `handover not triggered because the UE is already performing HO`); the script injects **sequentially, gating each handover's landing** (re-firing if a control races an in-flight HO). Also: target a UE only to a cell it is *not* already on (imsi 2→5 was a silent no-op).
- **D5 — evidence + re-runnable script + assertion:** `scripts/phase6b-closed-loop-run.sh` (clean→ns-3→TS-restart→wait_rc→sequential gated inject→grep+pcap→PASS/FAIL) and `scripts/l-release-validation/m-rc4-closed-loop.sh` (+ `assert-pcap.sh` `control-request`/`control-ack` byte-sig/dissector checks). **Provenance:** wire bytes are identical for a TS-emitted vs grpcurl-emitted control; the proof is the TS pod-log emit timestamp-correlated to the wire Control Request **plus no grpcurl in the loop** (documented).

### Open question for the user
**Do the optional D0 TS rebuild for source⇄deploy parity, or keep the working deployed image + UPPERCASE keys?** M-RC4 is proven on the deployed (un-rebuilt) image; the committed lowercase case-fix is correct code but not required on this E2MGR. Rebuild ≈ 10 min + re-onboard, then flip `PREDICTIONS_JSON` to lowercase.

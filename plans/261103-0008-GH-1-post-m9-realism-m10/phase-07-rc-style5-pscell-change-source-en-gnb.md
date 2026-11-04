# P07 (MC, T-A P4/P1/P13): E2SM-RC Control Style 5 action 3 to the source en-gNB

**Start state:** P06b pins; `f7-rerun-green`. **Snapshot at exit:** none. **Preconditions:** P06b's codec, context and Influx exit green (KPM UE IDs in Influx); the I-4 IDs read from the PDFs. **This phase closes the P06b + P07 integration boundary:** R2/R3′ must go green here (Codex round 2 #2).

## Context
- **rc:**
  - hard-codes the header UE ID as gNB-UEID [V `ric-app-rc/e2sm/wrapper.c:29-38`] and the message as Style 3 parameters 1 → 2 → 3 → 4 [V `wrapper.c:389-455`, `control/rcTypes.go:11-19`];
  - its gRPC `UeId` has only `GnbUEID` [V `protocol/grpc/ricmsgcommrpc/proto/rc.proto:30-31`], a pointer in Go [V `rc.pb.go:151`];
  - `rcService.go:35` dereferences `UEID.GnbUEID.Guami.*` unconditionally [V], so an EnGnbUEID-only request would panic rc;
  - the committed protobuf code requires protoc 3.6.1 on the C++ side [V `ric-app-ts/ext/protobuf/rc.pb.h:11`].
- **TS xApp:** Style 3 action 1 with `stoi(ue_id)` [V `ts_xapp.cpp:618-626`]; addressed to the target's node [V `:639-643`]; the serving cell is available at the call site [V `:727-729`].
- **ns-3:**
  - every control goes to the MN handler [V `oran-interface/model/e2-control-hub.cc:264-267`; registration `ns-3-mmwave-oran/src/lte/model/lte-enb-net-device.cc:953-954`];
  - MN admission [V `lte-enb-rrc.cc:4556-4608`], then X2 `McHandoverRequest`, then the source SN's `SendHandoverRequest` [V `:5129-5137`];
  - the batch sort uses the IMSI [V `e2-control-hub.cc:247-250`].
- **Harness:**
  - the C1 replay rebuilds controls from the ledger's `imsi` [V `scripts/gates/pacer.py:63-77`], and R2/R3′ C1 use it [V `scripts/gates/ts-rung-lib.sh:169`];
  - R1 asserts addressing-dependent behaviour [V `gate-r1-rc-multi-control.sh:252-267` (C4 (b): a same-step IMSI 2 pair, where the hub sort `(imsi, viaNodeId, targetCellId, ctlId)` [V `e2-control-hub.cc:247-250`] applies the higher-ctlId, lower-target control first; C4 (c): arrival [3,2] across two agents), `:276-295` (fault-stop: agent 1 forwards 2 and fails 1 pending control on bye)].

## Requirements (contract)
- **AC14:**
  - Style 5 action 3; Style 3 action 1 removed from the control path;
  - addressed to the source en-gNB (decoded meid and ledger `viaNodeId`);
  - executed as an SN-initiated SN change (I-1);
  - RC UE ID = en-gNB-UEID (R-4), **taken by the TS xApp from the KPM UE IDs in Influx (AC14b), never from an ns-3 side channel**;
  - action 3 RAN parameter IDs per I-4, in the standards ledger;
  - R2 and R3′ still pass.
- **AC14b (RIC half):** the TS xApp reads the UE ID from Influx to build the control.
- **AC18:** the P1 rows were registered at Stop A. The ordinary rows (R1 replacements, replay, wire extractor) are written before code.

## Design
- **Protoc toolchain proof (F12).** Before any proto change, regenerate the **unchanged** `rc.proto` in containers pinned to the committed versions (Go side per `rc.pb.go`'s header; C++ protoc 3.6.1) and require byte equality with the committed `rc.pb.go` / `rc.pb.cc` / `rc.pb.h`. Only then add `EnGnbUEID {mEnbUeX2apId, globalEnbPlmn, globalEnbMacroId}` as an alternative in `UeId`, and regenerate both sides. Each generated file is in its fork's manifest (P06).
- **rc patch:**
  - header Format 1 {en-gNB-UEID, style 5, action 3};
  - message Format 1 with the I-4 parameters (Target PSCell ID → … → NR CGI from P06's encoder);
  - `rcService.go:35` validates whichever `UeId` alternative is set and returns an invalid-argument gRPC error when neither is, so it never dereferences a nil `GnbUEID`;
  - `rcTypes.go` constants for style 5 and action 3.
- **TS xApp patch (in the ordered manifest):** the trigger names the UE by its Influx `ueId` key (P06b). The TS xApp reads the latest UeMetrics row with that tag from Influx (serving cell and ID fields; in-cluster credentials, T7), fills `EnGnbUEID`, sets style 5 / action 3, and addresses `cell_map[serving cell]`. `stoi` is gone.
- **Agent:** accepts only style 5 / action 3 with an en-gNB-UEID header. Style 3/1 → `action-not-supported` (tested by the injector); a decode failure → `control-message-invalid`. The IPC control carries `{ueId: {mEnbUeX2apId, mnCellId}, targetCellId}` (schema bump for control lines only).
- **ns-3:**
  - The hub dispatches to the handler registered for `viaNodeId`.
  - Before the sort it resolves each control's UE at that node: the en-gNB's UeManager whose `lteRnti` and MN cell match **and** that is the UE's current SN (the MN's `m_lastMmWaveCell[imsi] == viaNodeId`, read-only). A stale `RlcBearerInfo` cannot resolve.
  - Unresolved → refused `unknownUe` with ledger `imsi` 0.
  - The sort key stays `(imsi, viaNodeId, targetCellId, ctlId)` on the resolved IMSI.
  - The en-gNB's `ApplyE2SnChange` performs the zero-latency in-process "SgNB Change Required" to the MN, which runs today's admission (bookkeeping and the X2 `McHandoverRequest` leg; I-1).
  - The eNB registers no RC handler; its agent does not announce function 3 and answers `ran-function-id-invalid`.
  - δ > 0 uses R-5's tie rule; resolution happens in the apply event.
- **Replay (Codex 2).** The hub records each inbound control's IPC tuple `{viaNodeId, ctlId, ueId, targetCellId, afterSeq}` in `e2-pacing-log.jsonl`, which is not digested (`WriteLog`, `e2-control-hub.cc:366-377`). `pacer.py --replay` keeps the ledger for scheduling (rxSeq, late) and takes the UE-identity tuple of the same `(viaNodeId, ctlId)` from live1's pacing log. It sends the identical IPC control, including `unknownUe` cases, whose ledger `imsi` is 0. There is no IMSI control mode. Pacer fixtures and `pacer-selftest.py` migrate; C1's `replayEqual` must hold.
- **R1 source-aware replacements (Codex 3, registered rows; same strength):**
  - (b) same-step, same-UE pair (IMSI 2, on cell 3 at step 30 per `r1-scenario.json`), both sent through its **source en-gNB 3**, in reverse-target arrival order: first target 3 (lower ctlId), then target 2 (higher ctlId).
    - Because the hub sorts on `targetCellId` before `ctlId`, the target-2, higher-ctlId control applies first, and the target-3, lower-ctlId control is refused `inHandover`.
    - The check asserts exactly this: refused `inHandover` with the lower ctlId, applied with the higher ctlId, both via 3.
    - Fixture `scripts/gates/fixtures/r1-c4-arrival-order/`: a ledger produced as if the sort were replaced by arrival order (target 3 first → refused `alreadyOnTarget`, then target 2 applied) must **fail** the C4 check.
    - The hub test suite (Files) also runs the comparator swapped for arrival order, which must fail the same assertion.
    - The sort comparator becomes a named function used by `Apply`; `oran-interface/test/e2-control-order-test-suite.cc` asserts the (b) order differs from arrival order and the full `(imsi, viaNodeId, targetCellId, ctlId)` order.
    - This preserves C4's sort-not-arrival assertion.
  - (c) two agents for one UE: the control via the non-source en-gNB is refused `unknownUe`, and the one via the source is applied. Arrival order is still recorded and asserted as [3,2] where the scenario sends them that way. This keeps wrong-node rejection. The via-3 line is refused `unknownUe` with `imsi` 0 and is matched by (viaNodeId, imsi 0, targetCell, afterSeq) and attributed to its UE through `e2-pacing-log` (`ueId`) and `e2-ue-context-1` (`lteRnti`).
  - (a): IMSI 6's control goes via its source 2 (was the eNB); the pair still spans agents 2 and 3.
  - f2 fault-stop: the pending control goes through the **source en-gNB agent** of that UE (not agent 1). The predicate becomes `forwarded == 2`, `failedOnBye == 1`, `rejIpcDown == 0`, `pending == 0` on that agent. This keeps pending-control failure on shutdown.
  - Negatives in R0 and R1 (scenario path `"enb"`/`"nonSourceGnb"`): a control via the eNB → agent-local `ran-function-id-invalid` (no ledger line; the pacer requires none at ns-3 within W); a control via a non-source en-gNB → `unknownUe`. Both feed the shared D7.
  - Scenario comment texts:
    - `r0-scenario.json:2`: "… via = the E2 node whose agent receives the control: the UE's serving gNB (its source en-gNB) for every positive; node 1 (the eNB) and a non-serving gNB appear only as negatives. key = the TS key of the target NR CGI, %08X10 (gNB ID, cell part 1, APER pad)."
    - `r1-scenario.json:2`, case (c): "… Case (c): the same UE's control is sent first through a non-source en-gNB (node 3), refused unknownUe, then through its source (node 2), applied. Case (e): a control to the eNB, answered ran-function-id-invalid by its agent."
    - `r1-scenario.json:13`: per the gap-5 ruling (Risks).
- **R3′ preparation migration (Codex round 2 #1).** Identities are translated consistently at the RIC boundary, and IMSIs stay in every continuity record (predictor records, `r3p-schedule.json`, ledger):
  - `r3p-prepare.py`: the trigger/prepare path resolves IMSI → `ueId` key through the run's `e2-ue-context-*.jsonl` (R-4 format), confirms the key exists in Influx (as the AD stand-in would observe it), and writes `$rd/r3p/trigger-ue-<step>.txt`. `stub_load` (`:41-52`) checks `{"ues": [<ueId key>], "entries": 1}`. The calibration branch (`:74-79`) builds `{"predictions": {<ueId key>: [answer]}}`. The `stub-log`, `answer-*.json` and window files record both the IMSI and the key.
  - `r3p-schedules.py`: `trigger_entry` (`:31-32`) runs `send-rmr.sh <port> anomaly-from <trigger-ue file>` (new op in `scripts/gates/send-rmr.sh`; the file is written by the step's prepare). Stage B (`:57`) injects `{nodeId: <source en-gNB = the M9 ledger line's sourceCell>, ctlId, ueId: <from e2-ue-context at that step>, targetCellId, afterSeq}`, the migrated IPC control schema, with no IMSI control.
  - Self-tests: `r3p-dry-run-fixtures.py` and `r3p-checks-fixtures.py` migrate, keeping their IMSI assertions on the continuity fields.
- **D7 and P1 rows** per check-diff-ledger rows 10–16 (r0/r1 D7 also requires viaGnbs ⊇ {2,3}, a non-source `unknownUe` and an eNB `ran-function-id-invalid`; r2 D7 requires viaGnbs ⊇ {2,3}). The TS xApp, the r2 calibration triggers and the dry-run classifier address the UE's serving gNB. `wire-c1-extract.py` records `viaMeid` (association GlobalE2node-ID rendered by `meid_of`) and fails if it differs from `meid_of(viaNode)`.

## Integration interfaces (controller, 2026-11-04; binding for every P07 change)
The ledger rows 106–128 and the rulings after them use these forms. A change to any of them is a ledger note first.
1. **gRPC, TS xApp or `rc-send.sh` → rc** (`rc.proto`, field 2 of `UeId`, proven toolchain `tools/protoc-pinned/`):
   - `message enGNBUEID { int64 mEnbUeX2apId = 1; string globalEnbPlmn = 2; string globalEnbMacroId = 3; }` (X2AP ID 0..4095; PLMN 6 hex digits; macro eNB ID 5 hex digits, at most FFFFF). `UeId { gNBUEID GnbUEID = 1; enGNBUEID EnGnbUEID = 2; }`.
   - The request names the **source en-gNB**: `E2NodeID`/`RanName` = its meid `en_gnb_001_001_%08x`; `PlmnID` `00F110`; `RICControlHeaderData` {ControlStyle 5, ControlActionId 3, UEID {EnGnbUEID {mEnbUeX2apId, globalEnbPlmn "00F110", globalEnbMacroId "00001"}}}; `RICControlMessageData` {NR cell, TargetCellID = the target's TS key `%09X0`}.
   - rc refuses with gRPC InvalidArgument and sends nothing when `EnGnbUEID` is absent, when `GnbUEID` is also set, when a member is out of range or malformed, or when the style/action is not 5/3. It never dereferences a nil member (no panic, rc RestartCount 0).
2. **E2 wire, rc → agent:** RIC CONTROL REQUEST with RIC Control Header Format 1 {UE ID = en-gNB-UEID {m-eNB-UE-X2AP-ID, globalENB-ID {pLMN-Identity, eNB-ID macro (20 bits)}}, no optional member; RIC Style Type 5; Control Action ID 3} and RIC Control Message Format 1 with RAN parameters 1 → 2 → 3 → 4 (NR CGI, APER, unchanged from rc patch 0002).
3. **Agent:**
   - gNB agents announce RAN function 3 with Control Style 5 / action 3 only, listing RAN parameters 1, 2, 3, 4. The eNB agent does not announce RAN function 3 and answers any RIC CONTROL with cause `ran-function-id-invalid`; nothing reaches ns-3.
   - Style ≠ 5 or action ≠ 3 → RIC CONTROL FAILURE `action-not-supported`. An undecodable header or message, a UE ID that is not en-gNB-UEID, an optional member, or a PLMN other than the node's → `control-message-invalid`. Nothing reaches ns-3 in either case.
   - IPC control line (hello minor 4; `control` keeps `"v":1`): `{"type":"control","v":1,"nodeId":N,"ctlId":K,"ric":{...},"style":5,"action":3,"ueId":{"mEnbUeX2apId":X,"mnCellId":M},"targetCellId":T,"afterSeq":S}`, where M is the macro eNB ID as an integer. The member `imsi` is gone. `controlAck` cause `unknownImsi` becomes `unknownUe`. The schema `schema/ns3-e2-ipc.v1.schema.json` changes exactly so.
   - Per-seq UE context: the agent keeps the `ueContext` lines keyed by seq until their period is reported and encodes each sample with the context valid at its seq (row 127). The counters `samplesNoUeContext` and `ipc.ueContextRejected` keep their names (row 115).
4. **ns-3 hub (oran-interface) and ns-3:**
   - The hub dispatches each control to the handler registered for its `viaNodeId`. Before the sort, it resolves the UE at that node: the en-gNB's UE manager whose LTE RNTI and MN cell equal (X, M) **and** that is the UE's current SN (the MN's `m_lastMmWaveCell[imsi] == viaNodeId`, read-only). Unresolved → refused `unknownUe`, ledger `imsi` 0.
   - Every ledger line, `late` included, carries the resolved IMSI. A `late` line resolves read-only at rx; any other line resolves at the event that decides its outcome. The sort key stays (imsi, viaNodeId, targetCellId, ctlId) in a named comparator used by `Apply` (test suite `oran-interface/test/e2-control-order-test-suite.cc`).
   - `ApplyE2SnChange` on the en-gNB makes the in-process "SgNB Change Required" call to the MN, which runs today's admission (I-1). The eNB registers no RC handler.
   - Pacing log: on each inbound control, the hub writes `{"type":"control","v":1,"viaNodeId":N,"ctlId":K,"ueId":{"mEnbUeX2apId":X,"mnCellId":M},"targetCellId":T,"afterSeq":S}` to `e2-pacing-log.jsonl` (not digested).
   - Gap 5 (S1): `E2IpcEmitter::Stop()` skips `DeliverInbound()` once the hub is stopping.
   - Samples, traces and the ledger of a run with no control stay byte-identical to checkpoint 1 (step 3 byte-compare).
5. **Influx and the TS xApp:** the TS xApp builds the control after the QP prediction. It reads the latest UeMetrics row with the trigger's `ueId` tag from the node that currently reports the UE (latest seq), takes its serving cell, and addresses `cell_map[serving cell]`. It fills `EnGnbUEID` from the tag, never from an `ns3.*` field (row 128). Influx is read with in-cluster credentials (T7). A well-formed `ueId` with no Influx row produces no RIC CONTROL (row 125).

## Files
- ns-3 / oran-interface: `oran-interface/model/e2-control-hub.cc`, `e2-control-hub.h`, `e2-ipc-json-reader.cc`; `ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc`, `lte-enb-rrc.h`, `lte-enb-net-device.cc`, `lte-enb-net-device.h`; `src/mmwave/model/mmwave-enb-net-device.cc`; new `oran-interface/test/e2-control-order-test-suite.cc` and `oran-interface/CMakeLists.txt`.
- Agent: `ns3_e2_agent/src/rc-control.cpp`, `rc-control.hpp`, `rc_codec/rc-codec.c`, `rc_codec/rc-codec.h`, `schema/ns3-e2-ipc.v1.schema.json`, `tests/rc-control-test.cpp`, `tests/fixtures/`.
- Forks: `install_patch_files/xApps/rc/` (`wrapper.c`, `rcControl.go`, `rcE2SmRc.go`, `rcTypes.go`, `rcService.go`, `rc.proto`, regenerated `rc.pb.go`, manifest), `install_patch_files/xApps/ts/` (Style 5 + Influx read patch, `rc.proto`, regenerated `rc.pb.cc/.h`, manifest); new `tools/protoc-pinned/` (two Dockerfiles, byte-equality proof script).
- Harness: `scripts/gates/r3p-prepare.py`, `r3p-schedules.py`, `send-rmr.sh` (`anomaly-from`), `r3p-dry-run-fixtures.py`, `fixtures/r1-c4-arrival-order/`, `scripts/gates/pacer.py`, `pacer-selftest.py`, `ts-rung-lib.sh`, `rc-send.sh` (Style 5, source node, UE ID read from Influx), `rc-lib.sh`, `r0-checks.py`, `r0-scenario.json`, `r1-scenario.json`, `gate-r0-rc-scripted.sh`, `gate-r1-rc-multi-control.sh`, `gate-r2-ts-stub-qp.sh`, `gate-r3p-ts-predictor.sh`, `r2-checks.py`, `r3p-checks.py`, `r3p-checks-fixtures.py`, `tools/e2-evidence/wire-c1-extract.py`, `tools/rc-decode/rc-decode.c`, `gate-e2i-interop.sh` (Style 5 injector cases), `scripts/pins.conf`, `scripts/gates/r2-scenario.json`, `r3p-dry-run-classifier.py`, `tools/e2-evidence/kpm-ue-list-moves.py` (imsi-0 lines carry no UE), `tools/rc-decode/fixtures/rc-control-nrcgi.hex`, `tools/rc-decode/test-rc-decode.sh`.

## Steps
0. **G1 (Stop A, `plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`), before any P07 code:** register a #9 row in `check-diff-ledger.md` for the δ seam smoke (`scripts/probes/probe-delta-seam-smoke.sh:51-71`: its schedules address controls by IMSI and through the eNB or the target, which encodes P1 and P4), with old → new and "why not weaker". The smoke is migrated with the hub change (source-en-gNB addressee, en-gNB-UEID), keeping its tie, cancel-at-stop and pins/emitter-SHA cases.
1. Standards-ledger row for I-4 from the PDFs (§8.4.6.3 table, both versions) and the I-1 mapping row, written before code.
2. Protoc proof (unchanged proto byte-equal), then the proto change.
3. ns-3 dispatch, resolution and `ApplyE2SnChange`. Local byte-compare: the R3′-config run's traces are byte-equal to checkpoint 1 with controls entering at the source SN (the I-1 invariant).
4. Agent, rc and TS patches; image builds; `gate-q8-rc-smoke.sh` gRPC smoke with an EnGnbUEID-only request (rc RestartCount 0).
5. Pacer replay migration; self-test.
6. M5–M7; R0, R1 single (with the C4 fixture self-test); R2 C1; the R3′ preparation checks:
   - (a) live prepare and trigger at every scheduled step;
   - (b) the W calibration branch (fixed answer keyed by `ueId`);
   - (c) a stage-B injection dry run.

   Then R3′ C1 at δ = 0 (the dry form of P08's transform-compare) and `gate-e2i-interop.sh` Style 5 injector cases. Green R2/R3′ here closes the P06b + P07 integration boundary (AC14b integration).
7. Re-run the migrated seam smoke at the P07 pins (`vm-exec.sh probes/probe-delta-seam-smoke.sh`), including d150stop and d500stop after the gap-5 emitter change (G1, S1).
8. Phase exit.

## Validation
- Decoded wire, every control: header Format 1, style 5, action 3, UEID en-gNB-UEID equal to the Influx row's IDs and the R-4 values; meid = the source en-gNB (`c1-extract-summary` `viaMeidEqualsNode: true`, joined to the ledger); ledger `viaNodeId == sourceCell`.
- rc RestartCount 0 across every run, including the nil-`GnbUEID` fixture.
- R0/R1 under the registered predicates; the C4 arrival-order fixture fails `c4_used`; `e2-control-order` test suite passes, while the live run passes it.
- R3′ preparation: every live prepare loads the stub with exactly the `ueId` key; calibration answers are keyed by `ueId`; the stage-B injection is applied via the source en-gNB; IMSIs are unchanged in the predictor records and the schedule.
- R2 C1 and R3′ C1 green with `replayEqual: true` (AC14b integration).
- e2i: an independently encoded Style 5 control is applied; Style 3/1 → `action-not-supported`; a control to the non-source en-gNB → `unknownUe`; a control to the eNB → `ran-function-id-invalid`.
- HandoverStart − applySimTimeNs = c (I-2) on every applied line.
- G1: the migrated seam smoke is green at the P07 pins, and its #9 row predates the first P07 code commit.
- S1: R1 f2 passes via agent 2 (forwarded 2, failedOnBye 1, rejIpcDown 0, pending 0; agents 1 and 3 rc counters 0; one ledger line, IMSI 6).

## Standards ledger
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| Control Style 5 "Dual Connectivity control", Control Action ID 3 = "DC PSCell Change control" ("To control PSCell change of a UE within a secondary node or to another secondary node"), RAN parameters in §8.4.6.3; action 4 (DC Secondary Node Change Control, §8.4.6.4) is not used | E2SM-RC v03.00 §7.6.6.1, PDF pp. 39–40; v01.03 §7.6.6.1, PDF pp. 38–39 (same table) | `JRDTL7XS`, `PSHY8566` | ✓ 2026-11-04 |
| Header = RIC Control Header IE Format 1 (UE ID, Control Service Style ID, Control Action ID); message = RIC Control Message IE Format 1; outcome = RIC Control Outcome IE Format 1 with RAN parameter 1 ReceivedTimestamp OCTET STRING (SIZE(8)) | E2SM-RC v03.00 §7.6.6.2, §7.6.6.3, §7.6.6.5, PDF p. 40 | `JRDTL7XS` | ✓ 2026-11-04 |
| **I-4:** action 3 RAN parameter IDs used: 1 Target PSCell ID (STRUCTURE) → 2 >CHOICE Target Cell (STRUCTURE) → 3 >>NR Cell (STRUCTURE) → 4 >>>NR CGI (ELEMENT, key flag FALSE, NR CGI IE in 3GPP TS 38.423 §9.2.2.7). Parameters 5–24 (E-UTRA cell, Secondary Node ID, PDU session and DRB lists) are not sent | E2SM-RC v03.00 §8.4.6.3, PDF pp. 183–184; v01.03 §8.4.6.3, PDF p. 180 (same IDs 1–4) | `JRDTL7XS`, `PSHY8566` | ✓ 2026-11-04 |
| Inter-SN PSCell change: the E2 node invokes "*SNChange* (only SN-initiated)" | E2SM-RC v03.00 §8.4.6.3, PDF p. 183 | `JRDTL7XS` | ✓ 2026-11-04 |
| SN change can be triggered "by both the MN (only for inter-frequency secondary node change) and the SN"; the scenario is single-carrier, so the change is SN-initiated, and the control goes to the source en-gNB | 3GPP TS 37.340 v18.7.0 §7.2, p. 18 (PDF p. 19) | `E6VYJPXJ` | ✓ 2026-11-04 |
| SN-initiated SN change, EN-DC: 1 the source SN sends SgNB Change Required (target SN ID); 2/3 MN ↔ T-SN SgNB Addition; 4/5 RRCConnectionReconfiguration(Complete); 6 the MN confirms the release of the source SN (SgNB Change Confirm) | 3GPP TS 37.340 v18.7.0 §10.5.1, Figure 10.5.1-2, pp. 61–62 (PDF pp. 62–63) | `E6VYJPXJ` | ✓ 2026-11-04 |
| **Disclosed message mapping (I-1):** the en-gNB's in-process call to the MN ≈ step 1 SgNB Change Required; the MN's admission and X2 `McHandoverRequest` to the source SN ≈ steps 2/3 and 6; the SN↔SN X2 leg and the RRC steps are ns-3's model, not §10.5.1 message by message | 3GPP TS 37.340 v18.7.0 §10.5.1 | `E6VYJPXJ` | ✓ 2026-11-04; shown at Stop A′ |
| UE ID = en-gNB-UEID {MeNB UE X2AP ID, Global eNB ID} | E2SM v07.00 §6.2.2.6, p. 14 (cited in phase 06b) | `QW6VJ83M` | ✓ 2026-11-04 (P06b) |
| eNB UE X2AP ID INTEGER (0..4095) | E2SM v07.00 §6.2.3.23, from 3GPP TS 36.423 §9.2.24, p. 24 (cited in phase 06b) | `QW6VJ83M`; `3ML7Y29A` | ✓ 2026-11-04 (P06b) |

## Risks
- Protobuf regeneration mismatch (Medium/Medium). The byte-equality proof comes first.
- The zero-latency admission changes event order (High/Low). The step 3 byte-compare is a hard gate.
- A stale SN context (Medium/Medium) is handled by the current-SN check; a fixture covers it.
- The TS xApp's Influx read adds latency inside the lock-step window (Medium/Medium). The read happens in the TS xApp's request path before rc; T_ctl is re-measured, and a red is handled under the Failure Protocol.
- **Ruled at Stop A (S1, gap 5 = option A, `plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`):** `E2IpcEmitter::Stop()` skips `DeliverInbound()` once the hub is stopping (Files + `oran-interface/model/e2-ipc-emitter.cc`, `e2-control-hub.h`; plan file ownership `e2-ipc-emitter.cc`: P06b, P07). f2 goes via agent 2 with `agent-forward-wait.sh 2 2 5`, failedOnBye 1, and the `r1-scenario.json:13` comment is restated (ledger row 31). The seam smoke's d150stop and d500stop cases are re-run after the change (G1).

## Rollback
Re-pin the P06b SHAs; `m10-cp1` reproduces checkpoint 1.

## Hand-offs from the P06 exit review (kongming-261104-1340)
- Drop Style 3/1 from the gNB's RAN function 3 definition and remove the eNB agent's RC handler (it applies controls on a RAN function it no longer announces). The definition must list every RAN parameter this phase's controls send; the e2i judge today checks only that parameters 1–4 are present, so extend it (ledger row first).
- Re-encode the e2i N5-form negative (`0000F1100000000303`) as a Style 5/3 control. Left as Style 3/1 it is refused for its style, not its target, and AC12's negative stops testing the target.
- Before this phase's e2i re-run, write hex sidecars beside the e2mgr record files (the scrubber replaces their request parts with `REDACTED-TOKEN`), so the records stay judgeable after the scrub.


## Hand-offs from the P06b exit review (kongming-261104-1958)
Do these first, in this order, before the first P07 code commit or VM step:
1. **Disk projection and the VM-root rule.**
   - P06b took /home from 46 to 30 GiB free; M3's kpimon rebuild alone took about 11 GiB. The dev floor is 20 GiB.
   - P07 rebuilds rc, the TS xApp and the agent, and runs R2 C1, R3′ C1 and e2i. Project its /home use, from the per-step `host-disk.tsv`, before the first VM step. If the projection crosses 20 GiB, plan a revert point or PAUSE for the user. Never delete snapshots or overlays autonomously.
   - The VM root is at 68 % against P12's 75 % guard. Register as an ops rule that a VM `docker image prune -f` removes only dangling images, that is, superseded builds of this plan. P06b's prune goes to Stop A′ as an interpretation of the contract's §5.
2. **Ledger rows that do not exist yet** (old → new, why not weaker), all written before code:
   - `r3p-prepare.py` `stub_load` (`:48`) and the calibration branch (`:74-79`);
   - `r3p-schedules.py:31-32` `trigger_entry`;
   - the pacer replay's UE-identity tuple (only P02's row 57 covers the pacer today);
   - row 13's promised `(imsi, step)` wire-attribution row;
   - the G1 seam-smoke #9 row (step 0);
   - the counter conjuncts in item 3;
   - e2i association-based frame-to-node mapping, reusing `kpm-ue-list-moves.py` `assoc_node_of`, before P07's e2i run. This is harness work; the P06 hand-off in phase 12 that made it a user question becomes a disclosure.
3. **Agent counters where contexts change.** Today `samplesNoUeContext` and `ipc.ueContextRejected` are asserted only in M6 and P12. Add `samplesNoUeContext == 0` and `ueContextRejected == 0`, taken as the maximum over every stats line across agent restarts, to M7 and to every rung's agent check. Replay them offline on the archived M7, R0, R1 and r3p runs; the review read 0 on all of them.
4. **The agent's per-seq UE context** (P06b disclosure, finding 3). The agent keeps the `ueContext` lines keyed by seq until the period is reported and encodes each sample with the context valid at its seq. Add a host unit test with a mid-period context change: all K records are encoded, and the departed UE appears only in its own samples.
5. **One harness pin for the r3p migration.** At HEAD the r3p gate cannot pass: D7 (row 10) still requires "via target" while rows 14 and 15 require "via source". Land rows 10, 14, 15 and 25 with the TS xApp patch and rows 88–95 at one harness pin, and run no r3p on a partial migration.
6. **The TS xApp reads the UE ID from Influx.**
   - The `ueId` tag is MN-scoped, so a UE has the same tag on every en-gNB. Define the serving row as the latest seq from the node that currently reports the UE. Around an SN change, rows from both gNBs carry the tag.
   - The read uses in-cluster credentials (T7). T_ctl is re-measured, because the read sits inside the lock-step window.
   - Add a wire negative so that "reads it from Influx" is not vacuous (the anomaly string already carries every UE ID member): a well-formed `ueId` with no Influx row must give zero RIC CONTROL requests on the wire.
   - The TS xApp never uses an `ns3.*` field for the UE identity.
7. **The rungs' UE-list judge.** Pass `--facts` (the rung's `$label-sub-facts.json`) to every `kpm_moves` call, so a rung with an agent restart attributes frames by association instead of failing closed on a shared IP.
8. D-06b-1 (the MeNB UE X2AP ID before DC) is scheduled in P10 with P15; see phase 10. Take it into P07 only if P07 rebuilds kpimon anyway.

## Work record (in progress, 2026-11-04)
- **Disk projection (hand-off 1), before any VM step:**
  - Host /home has 30 GiB free. The VM's active vda is the overlay `ubuntu24.04-r2-green.1793744306` (54 GiB allocated). `vm-orphan-overlays.sh --pending` passes: it is the overlay the current snapshot's revert record unlinks at the next revert. No untracked overlay exists.
  - P07's start state is a revert to `f7-rerun-green`. That revert unlinks the active overlay through libvirt's own record, with no manual deletion, so /home goes to about 84 GiB free.
  - P07's VM use, from P05's and P06b's per-step `host-disk.tsv`: M2 about 1 GiB, M3 about 11–14 GiB (kpimon and kpm_sim images), M6/M7 about 4 GiB, and the rung chains and image rebuilds (rc, TS xApp, agent) about 15–20 GiB. That totals about 35–40 GiB, leaving about 45 GiB, well above the 20 GiB floor. No PAUSE is needed.
  - The revert also resets the VM root to the snapshot's image set, so P12's 75 % guard starts from the snapshot state.
  - **Ops rule (registered here):** a VM `docker image prune -f` is allowed only for dangling (untagged) images, which are superseded builds of this plan. Never a tagged image, never `-a`, and every prune is logged in the work record with the space freed. P06b's prune is disclosed at Stop A′.
- **Step 1, standards ledger:** the I-4 and I-1 rows are cited from the PDFs (E2SM-RC v03.00 and v01.03 §7.6.6.1–§7.6.6.5 and §8.4.6.3; 3GPP TS 37.340 v18.7.0 §7.2 and §10.5.1). Parameters 1–4 have the same IDs in both versions.
- **Step 0 and the hand-off rows (e66b263):** ledger rows 106–127 come from the AC18 inventory (`plans/reports/planner-261104-2100-GH-1-p07-ac18-inventory.md`); row 128 and the controller's rulings on the inventory's 13 questions were written before any P07 code commit. The G1 seam-smoke row is 106. Rows 106, 120 and 121 are registered contract changes (#9), shown for confirmation at Stop A′ (ruling 1).
- **Step 2, protoc toolchain proof (760ce3e, after the rows):** `tools/protoc-pinned/` regenerates the unchanged `rc.proto` of rc (a2282eed) and of the TS xApp (19e169b2) byte for byte, all five files (`evidence/p07-protoc-proof/20261104T114648Z/proof.json`).
  - **Go side:** `rc.pb.go` needs protoc 3.6.1 (Ubuntu 20.04), whose FileDescriptorProto for `rc.proto` equals the gzipped one in `rc.pb.go`, with protoc-gen-go from golang/protobuf's 2016-11-16 snapshot (source from Debian 9's golang-goprotobuf-dev) compiled with Go 1.10.
    - Debian 9's own binary (Go 1.7) differs only in the gzip MTIME field.
    - Ubuntu 18.04's protoc 3.0.0 lower-cases `json_name`, and its 2017 protoc-gen-go uses the newer header.
  - **C++ side:** Ubuntu 20.04's protoc 3.6.1 and grpc_cpp_plugin 1.16.1.
  - Everything comes from distro packages and Debian source; no binary is downloaded. The commit was first made before the rows, undone locally before any push, and made again after them.
- **Interfaces (1270008):** the binding forms between rc, the agent, ns-3 and the harness are in the section "Integration interfaces".
- **Step 3, ns-3 and oran-interface (local fork commits, not yet pinned):** oran-interface efd5802 (the emitter stop change) and 8a3cb21 (dispatch per node, read-only UE resolution, the named comparator, the pacing-log record, hello minor 4, the test suite); ns-3 ea6e46f6 (resolution getters, `ApplyE2SnChange`, no RC handler on the eNB).
  - Host proof, in the `localhost/ns3-e2-agent:dev-x2` image (Ubuntu 22.04, g++ 11):
    - `./test.py -s e2-control-order` passes 6 of 6 cases.
    - `./test.py -c unit` passes 31 of 31.
    - With the comparator swapped for arrival order, the hub-order case fails and the suite exits 1.
    - A no-control run with the R3′ radio configuration is byte-equal to the baseline binary: traces, samples and context files.
    - The M7 configuration is byte-equal except one row of `DlE2RlcStatsLte.txt`, which also differs between two runs of the same binary. That is ns-3 nondeterminism from before this change.
  - The VM's M4 build uses `--disable-tests`, so the suite's proof is this host run. It is repeated at the pinned SHAs at the phase exit, and its output goes into the evidence.
  - The stop-time `late` lines are ruled in the ledger note on row 124 (990981a).

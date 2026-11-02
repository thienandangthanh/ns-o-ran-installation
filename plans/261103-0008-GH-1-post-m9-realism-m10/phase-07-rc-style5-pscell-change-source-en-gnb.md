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
  - R1 asserts addressing-dependent behaviour [V `gate-r1-rc-multi-control.sh:249-256` (C4 (b): a same-step IMSI 2 pair, where the hub sort `(imsi, viaNodeId, targetCellId, ctlId)` [V `e2-control-hub.cc:247-250`] applies the higher-ctlId, lower-target control first; C4 (c): arrival [3,2] across two agents), `:275-290` (fault-stop: agent 1 forwards 2 and fails 1 pending control on bye)].

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
    - An ns-3 hub unit test with the comparator swapped for arrival order also fails the same assertion.
    - This preserves C4's sort-not-arrival assertion.
  - (c) two agents for one UE: the control via the non-source en-gNB is refused `unknownUe`, and the one via the source is applied. Arrival order is still recorded and asserted as [3,2] where the scenario sends them that way. This keeps wrong-node rejection.
  - f2 fault-stop: the pending control goes through the **source en-gNB agent** of that UE (not agent 1). The predicate becomes `forwarded == 2`, `failedOnBye == 1`, `rejIpcDown == 0`, `pending == 0` on that agent. This keeps pending-control failure on shutdown.
  - A control sent to the eNB → `ran-function-id-invalid`: a new negative, added, not substituted.
- **R3′ preparation migration (Codex round 2 #1).** Identities are translated consistently at the RIC boundary, and IMSIs stay in every continuity record (predictor records, `r3p-schedule.json`, ledger):
  - `r3p-prepare.py`: the trigger/prepare path resolves IMSI → `ueId` key through the run's `e2-ue-context-*.jsonl` (R-4 format), confirms the key exists in Influx (as the AD stand-in would observe it), and writes `$rd/r3p/trigger-ue-<step>.txt`. `stub_load` (`:41-52`) checks `{"ues": [<ueId key>], "entries": 1}`. The calibration branch (`:74-79`) builds `{"predictions": {<ueId key>: [answer]}}`. The `stub-log`, `answer-*.json` and window files record both the IMSI and the key.
  - `r3p-schedules.py`: `trigger_entry` (`:31-32`) runs `send-rmr.sh <port> anomaly-from <trigger-ue file>` (new op in `scripts/gates/send-rmr.sh`; the file is written by the step's prepare). Stage B (`:57`) injects `{nodeId: <source en-gNB = the M9 ledger line's sourceCell>, ctlId, ueId: <from e2-ue-context at that step>, targetCellId, afterSeq}`, the migrated IPC control schema, with no IMSI control.
  - Self-tests: `r3p-dry-run-fixtures.py` and `r3p-checks-fixtures.py` migrate, keeping their IMSI assertions on the continuity fields.
- **D7 and P1 rows:** r0/r2/r3p d7 and `via_target` become `viaNodeId == sourceCell` on every applied line. The `wire-c1-extract.py:230` filter reads style 5 / action 3 and the en-gNB-UEID.

## Files
- ns-3 / oran-interface: `oran-interface/model/e2-control-hub.cc`, `e2-control-hub.h`, `e2-ipc-json-reader.cc`; `ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc`, `lte-enb-rrc.h`, `lte-enb-net-device.cc`, `lte-enb-net-device.h`; `src/mmwave/model/mmwave-enb-net-device.cc`.
- Agent: `ns3_e2_agent/src/rc-control.cpp`, `rc-control.hpp`, `rc_codec/rc-codec.c`, `rc_codec/rc-codec.h`, `schema/ns3-e2-ipc.v1.schema.json`, `tests/rc-control-test.cpp`, `tests/fixtures/`.
- Forks: `install_patch_files/xApps/rc/` (`wrapper.c`, `rcControl.go`, `rcE2SmRc.go`, `rcTypes.go`, `rcService.go`, `rc.proto`, regenerated `rc.pb.go`, manifest), `install_patch_files/xApps/ts/` (Style 5 + Influx read patch, `rc.proto`, regenerated `rc.pb.cc/.h`, manifest); new `tools/protoc-pinned/` (two Dockerfiles, byte-equality proof script).
- Harness: `scripts/gates/r3p-prepare.py`, `r3p-schedules.py`, `send-rmr.sh` (`anomaly-from`), `r3p-dry-run-fixtures.py`, `fixtures/r1-c4-arrival-order/`, `scripts/gates/pacer.py`, `pacer-selftest.py`, `ts-rung-lib.sh`, `rc-send.sh` (Style 5, source node, UE ID read from Influx), `rc-lib.sh`, `r0-checks.py`, `r0-scenario.json`, `r1-scenario.json`, `gate-r0-rc-scripted.sh`, `gate-r1-rc-multi-control.sh`, `gate-r2-ts-stub-qp.sh`, `gate-r3p-ts-predictor.sh`, `r2-checks.py`, `r3p-checks.py`, `r3p-checks-fixtures.py`, `tools/e2-evidence/wire-c1-extract.py`, `tools/rc-decode/rc-decode.c`, `gate-e2i-interop.sh` (Style 5 injector cases), `scripts/pins.conf`.

## Steps
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
7. Phase exit.

## Validation
- Decoded wire, every control: header Format 1, style 5, action 3, UEID en-gNB-UEID equal to the Influx row's IDs and the R-4 values; meid = the source en-gNB; ledger `viaNodeId == sourceCell`.
- rc RestartCount 0 across every run, including the nil-`GnbUEID` fixture.
- R0/R1 under the registered predicates; the C4 arrival-order fixture and the swapped-comparator hub test both fail the C4 check, while the live run passes it.
- R3′ preparation: every live prepare loads the stub with exactly the `ueId` key; calibration answers are keyed by `ueId`; the stage-B injection is applied via the source en-gNB; IMSIs are unchanged in the predictor records and the schedule.
- R2 C1 and R3′ C1 green with `replayEqual: true` (AC14b integration).
- e2i: an independently encoded Style 5 control is applied; Style 3/1 → `action-not-supported`; a control to the non-source en-gNB → `unknownUe`; a control to the eNB → `ran-function-id-invalid`.
- HandoverStart − applySimTimeNs = c (I-2) on every applied line.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| Style 5 action 3 and its RAN parameter IDs | E2SM-RC v01.03 and v03.00 §7.6.6.1, §8.4.6.3 (identical tables, PDF pp. 180/183); outcome §7.6.6.5 | `PSHY8566`, `JRDTL7XS` | to cite (PDF) |
| SN-initiated SN change; MN-triggered only inter-frequency | 3GPP TS 37.340 §10.5.1, §7.2 | `E6VYJPXJ` | to cite |
| **Disclosed message mapping (I-1):** in-process call ≈ SgNB Change Required; MN→S-SN `McHandoverRequest` ≈ SgNB Change Confirm; the SN↔SN X2 leg is not §10.5.1 message by message | 3GPP TS 37.340 §10.5.1 | `E6VYJPXJ` | to cite; shown at Stop A′ |
| UE ID en-gNB-UEID and its fields | E2SM common v07.00 §6.2.2.6 | `QW6VJ83M` [C] | to cite |
| eNB UE X2AP ID | 3GPP TS 36.423 §9.2.24 | `3ML7Y29A` | to cite |

## Risks
- Protobuf regeneration mismatch (Medium/Medium). The byte-equality proof comes first.
- The zero-latency admission changes event order (High/Low). The step 3 byte-compare is a hard gate.
- A stale SN context (Medium/Medium) is handled by the current-SN check; a fixture covers it.
- The TS xApp's Influx read adds latency inside the lock-step window (Medium/Medium). The read happens in the TS xApp's request path before rc; T_ctl is re-measured, and a red is handled under the Failure Protocol.

## Rollback
Re-pin the P06b SHAs; `m10-cp1` reproduces checkpoint 1.

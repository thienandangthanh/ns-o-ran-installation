# Phase 7 — Reconnect ns-3 scenario-zero (end-to-end) + M6

## Context Links
- Overview: [plan.md](plan.md); indications from [phase-06](phase-06-port-kpm-indications.md)
- Research: [researcher-260606-2214-m6-kpm-metric-mapping.md](../reports/researcher-260606-2214-m6-kpm-metric-mapping.md), [researcher-260606-2214-ns3-build-e2-adapter.md](../reports/researcher-260606-2214-ns3-build-e2-adapter.md)
- v3 reference (proven): `oran-interface/examples/kpm-indication-builder.h`, `kpm-func-desc-v3.h`, `kpm-subscription-handler.h`
- Scenario: `ns3-mmwave-oran/scratch/scenario-zero.cc`; helper `ns3-mmwave-oran/run-test.sh`

## Overview
- **Priority:** P0. **Status:** ✅ DONE — live M1–M6 all GREEN against L-release RIC. Real scenario-zero KPM decoded by kpimon-go (5 cell metrics) and written to InfluxDB. Three live-only bugs fixed (funcId 2, SCTP source-port collision, PDU double-free) + cell-style reduced-PM. Finalization (README/docs/pins/commit) remaining.
- Port the **real ns-3 KPM pipeline** to E2SM-KPM v3.00 so the unmodified scenario-zero streams decodable v3 indications to kpimon-go. M6 = real ns-3 KPM values, not the dummy builder.

## Locked decisions (this session)
- **D1 — M6 strategy = Path X:** port the real `model/` pipeline to v3 (NOT extend the standalone `examples/` builder). The real emit path already exists and is wired: `MmWaveEnbNetDevice::BuildAndSendReportMessage` (`mmwave-enb-net-device.cc:1515`) → `MmWaveIndicationMessageHelper` → `KpmIndicationMessage`/`KpmIndicationHeader` (`model/kpm-indication.cc`) → `m_e2term->SendE2Message`. The `examples/` v3 builders are the proven-correct reference to port against. `examples/` left intact as standalone reference.
- **D2 — Session scope:** code port + DoStart adapter + **clean full ns-3 build on `oran-kvm-2`** + offline/structural proof. **Defer** the live M1–M6 RIC run to the next session (handoff).
- **D3 — DoStart adapter = Option A:** rewrite `E2Termination::DoStart` to build `argv` and call `run_loop(int,char**)` (matches commented-out original intent + `e2-setup-minimal.cc`).
- **D4 — Builder placement:** v3 logic lives in `model/` classes (single source of truth); `asn1c-types::MeasurementItem` already abstracts metrics as (name,value) → maps to v3 `MeasurementInfoItem.measName` + `MeasurementRecordItem`.

## Key Insights
- Scenario logic unchanged by design; only the E2 endpoint + E2/KPM stack version change.
- `model/kpm-indication.cc` is built on the **v2 container model** (`PM-Containers-Item`, `PF-Container`, `PerUE-PM-Item`, `CUUPMeasurement-Container`, `ODU/OCUUP/OCUCP-PF-Container`). v3.00 replaces this with the flat `MeasurementData`/`MeasurementRecord` + `MeasurementInfoList`/`MeasurementInfoItem`/`MeasurementType`/`MeasurementLabel` model (proven in `examples/kpm-indication-builder.h`).
- `asn1c-types.h:309 MeasurementItem` wraps the v2 `PM_Info_Item_t` but stores (name, long/double value) → the (name,value) abstraction survives the port; only the asn1c target type changes.
- kpimon-go gate (`control.go:387`): `no_of_cell_metrics == len(tmpCellKpi)`, where `tmpCellKpi` = measNames advertised in the RAN-function descriptor. **The indication's measInfo/measData lists must match the advertised descriptor names in count + ordinal order.**

## M6 metric reconciliation (D5 — target = smallest green)
- Descriptor (`model/kpm-function-description.cc`) currently advertises 9 RLC/L1M names (Phase-4 OSC parity) that ns-3 does NOT emit.
- ns-3 helper (reduced-PM, `m_reducedPmValues`) emits DU cell names: `TB.TotNbrDlInitial.Qpsk` / `.16Qam` / `.64Qam`, `RRU.PrbUsedDl`, `DRB.MeanActiveUeDl`.
- **M6 target:** make descriptor-advertised names == helper-emitted names for the chosen container/style so `len(tmpCellKpi)==no_of_cell_metrics`. Start cell-level / reduced-PM (smallest set). Document the OSC-9 → ns-3 deviation in notes.

## Implementation Stages (ordered by dependency, smallest-risk first)
### Stage A — DoStart adapter (D3)
- File: `oran-interface/model/oran-interface.cc:116-138`. Build `argv[]={prog, ricAddr, ricPort, clientPort, gnbId, plmnId, NULL}` (manage string lifetimes), call `m_e2sim->run_loop(6, argv)`. Ref `examples/e2-setup-minimal.cc`.

### Stage B — Indication header port
- File: `model/kpm-indication.cc` `KpmIndicationHeader::FillAndEncodeKpmRicIndicationHeader`. Port to v3 `IndicationHeader-Format1` with **8-byte** `colletStartTime` (v2 was 4-byte TimeStamp). Match `examples/kpm-indication-builder.h` exact shape.

### Stage C — Indication message port (the big one)
- `model/asn1c-types.{h,cc}` `MeasurementItem`: retarget from `PM_Info_Item_t` to v3 `MeasurementInfoItem`(measName)+`MeasurementRecordItem`(value), preserving the (name,value) ctors.
- `model/kpm-indication.cc` `KpmIndicationMessage`: rewrite encode to assemble v3 `IndicationMessage-Format1` (one `MeasurementData` with N `MeasurementRecordItem`s + `MeasurementInfoList` with N `MeasurementInfoItem`s, ordinal-correspondent) from the collected `MeasurementItem`s. Drop v2 PM-container includes/types.
- `helper/indication-message-helper.cc` + `helper/mmwave-indication-message-helper.cc`: feed the v3 flat model; keep `Add*PmItem` signatures stable where possible (minimize `mmwave-enb-net-device.cc` churn).

### Stage D — Descriptor reconciliation (D5)
- `model/kpm-function-description.cc`: advertised measName list == helper-emitted names for the M6 container/style. Verify count/order parity with what Stage C emits.

### Stage E — Full ns-3 build on oran-kvm-2
- `cd /home/uc/ns-O-RAN-installation/ns3-mmwave-oran && ./ns3 build` (oran-interface is a contrib module; CMake already lists model+helper sources). Iterate v2→v3 compile errors to **clean build**.

### Stage F — Offline/structural proof
- Confirm the ported `model/` path round-trips a valid v3 indication (extend the existing offline proof or a model-level check). **Live M1–M6 RIC run deferred** (handoff).

## Todo List
- [x] Stage A: DoStart builds argv, calls run_loop(3,argv) (argc>3 → e2sim exit(1))
- [x] Stage B: v3 IndicationHeader-Format1 (8-byte colletStartTime) — proof 38 B
- [x] Stage C: MeasurementItem + KpmIndicationMessage → v3 flat model; helpers feed it
- [x] Stage D: descriptor measNames == reduced-PM Du emit (5 names)
- [x] Stage E: clean full ns-3 build on oran-kvm-2 (scenario-zero links; +libasn1c_e2.a; E2SM-RC excluded)
- [x] Stage F: offline model proof PASS (kpm-v3-model-proof: hdr 38 B + msg 192 B, 5 metrics, exit 0)
- [x] code-review (0 crit, 1 high FIXED + M1/M3 made loud; M2/L1 documented for live run)
- [x] **Live M1–M6 (DONE):** scenario-zero end-to-end vs L-release RIC — all green. funcId 200→2 (kpimon hardcodes 2) + Trampoline2; SCTP per-gNB source-port fix (e2sim); PDU double-free fix (5 sites); cell-only reduced-PM (5 metrics == descriptor). kpimon decoded values → InfluxDB. Evidence: scripts/l-release-validation/captures/phase7-m5m6-scenario-zero.pcap. Journal: docs/journals/2026-06-07-phase7-live-m1-m6-end-to-end.md
- [ ] **Finalize:** README L-release section; docs/ migration writeup; submodule pins (forks + super); finalize implementation-notes.html; commit/push

## Success Criteria (this session)
Real ns-3 `model/` KPM pipeline ported to v3.00; DoStart adapter in place; **full ns-3 build compiles clean on oran-kvm-2**; offline proof shows a valid v3 indication from the real path. Live end-to-end M1–M6 deferred to next session with a clean handoff.

## Risk Assessment
- v2→v3 rewrite of `kpm-indication.cc`/helpers surfaces many compile errors → iterate on VM; keep `examples/` reference open.
- 3 containers (CuUp/CuCp/Du) × 5 styles → descriptor/emit parity is fiddly; start cell-level reduced-PM.
- Constraint failure currently `exit(1)` (review I1) → switch to error-return before feeding dynamic values (one bad report must not kill the node).

## Deferred to next session (live run)
- Live M1–M6 against L-release RIC (kpimon choreography per Phase-5/6 handoff gotchas), full-run pcap, golden compare, README/docs migration writeup, submodule pins, finalize `implementation-notes.html`.

## Next Steps (follow-up, out of scope)
→ Port **E2SM-RC v2.0** for closed-loop control → Traffic Steering / Slicing / Prediction xApps on L-release.

# Phase 6 — Port KPM indication messages (area D = ns-3 metric mapping)

## Context Links
- Overview: [plan.md](plan.md); subscription from [phase-05](phase-05-port-subscription-handling.md)
- Source: `oran-interface/model/kpm-indication.cc`/`.h`, `oran-interface/helper/mmwave-indication-message-helper.cc`, `…/lte-indication-message-helper.cc`
- Metric source: `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc` (`BuildAndSendReportMessage`), `…/lte/model/lte-enb-net-device.cc`

## Overview
- **Priority:** P0. **Status:** ✅ DONE (M5 GREEN). M6 (real ns-3 metrics) deferred to Phase 7 (needs first full ns-3 build + mmwave scenario run — same scope as P7).
- Emit valid **E2SM-KPM v3.00 RICindication** PDUs carrying ns-3 metrics: first static (**M5 dummy**), then live sim values (**M6 real**).

## Result (M5 GREEN — 2026-06-06)
Mirrored the Phase-5 pattern (standalone builder in `examples/`, NOT touching the ns-3 `model/kpm-indication.cc`). Vendored libe2sim already provides the indication encoder + all v3 ASN.1 types; only the E2SM-KPM header/message builders were ported (from OSC `encode_kpm.cpp`).

**Three-level proof:**
1. **Offline** `kpm-indication-test` exit 0 — header 38 B / message 27 B, both APER round-trip; E2AP PDU proc-5; Format1 + 8-byte timestamp asserted.
2. **Wire** (Wireshark 4.6.5 E2SM-KPM dissector): 15× RICindication (proc 5) decoded as `IndicationHeader-Format1` (8-byte `colletStartTime` = `"20200613"`) + `IndicationMessage-Format1` (PLMN 747, S-NSSAI SD 100); RICrequestID 123/2, RANfunctionID 2, actionID 1.
3. **Live decode** kpimon-go logs: `Message received: name=RIC_INDICATION ... len=122` → `Indication Header format = 1` → `No of cell metrics = 1`. kpimon decodes the v3 structure.

**Deviation:** kpimon logs benign `no_of_cell_metrics != len(tmpCellKpi)` + header `RC_WMORE` — dummy `measID=1`/integer value does NOT populate kpimon's named-metric table. Expected for dummy data; closing it is exactly the M6 (real ns-3 metric mapping) work in Phase 7.

**Evidence pcap:** `scripts/l-release-validation/captures/phase6-m5-indication.pcap` (25.4 KB).

## Key Insights
- v3 indication changes: **8-byte TimeStamp** (was 4), `MeasurementLabel` 24 fields, `QosFlowIdentifier`, `S-NSSAI`, IndicationMessage Format1.
- ns-3 metric collection logic (DU/CU-UP/CU-CP containers, throughput/PRB/CQI/SINR/RLC/PDCP) is reusable; only the **encoding target** changes — map existing values into v3 `MeasurementRecord`.
- This is the area that proves real data flows; gate M6 on decode by the actual xApp.

## Requirements
- `kpm-indication.cc` builds v3 header+message; helpers map ns-3 PM values into v3 measurement items; kpimon-go decodes them.

## Related Code Files
- Modify (`oran-interface` `dev/l-release`): `model/kpm-indication.cc`/`.h` (v3 header/message, 8-byte timestamp, label/types), `helper/mmwave-indication-message-helper.cc` + `lte-indication-message-helper.cc` (`Fill*Values`/`Add*PmItem` → v3 records).
- No ns-3 scenario logic change (metric sources unchanged).

## Implementation Steps
1. Rewrite `KpmIndicationHeader` to v3 `IndicationHeader-Format1`: 8-byte TimeStamp, correct GlobalE2node/cell IDs.
2. Rewrite `KpmIndicationMessage` to v3 `IndicationMessage-Format1`: `MeasurementData`/`MeasurementRecord`, v3 `MeasurementLabel`, `QosFlowIdentifier`, `S-NSSAI`.
3. Update helpers to populate v3 measurement items from existing ns-3 metrics (keep metric names/units; map to v3 item types).
4. **M5 dummy:** emit indications with static values from the minimal app; confirm kpimon-go decodes (`logs <kpimon>`), capture pcap.
5. **M6 real:** wire helpers to live `BuildAndSendReportMessage` in a short ns-3 run; confirm decoded values track the sim.
6. Harness: add M5/M6 assertions (RICindication present, E2SM-KPM v3 OID, decodable measurement records). Update notes with any metric-mapping deviations.

## Todo List
- [x] v3 IndicationHeader (8-byte timestamp) — `kpm-indication-builder.h:BuildIndicationHeader`
- [x] v3 IndicationMessage (MeasurementRecord, v3 label/types) — `BuildDummyIndicationMessage`
- [ ] helpers map ns-3 metrics → v3 items — **deferred to Phase 7 (M6)**
- [x] **M5 dummy KPM** decoded by kpimon-go (`Indication Header format = 1`, `No of cell metrics = 1`)
- [ ] **M6 real ns-3 KPM** decoded; values track sim — **Phase 7**
- [x] harness M5 assertions (`m5-dummy-kpm.sh` live + offline proof); M6 assertions → Phase 7

## Success Criteria
kpimon-go decodes E2SM-KPM v3.00 indications carrying ns-3 metrics (M5 then M6); harness asserts both.

## Risk Assessment
- Decode fails on label/record shape → diff vs golden indication; verify 8-byte timestamp + label field order.
- Metric→item mismatch (units/types) → validate a couple of values by hand against sim logs; record mapping table in notes.

## Security Considerations
- None new.

## Next Steps
→ Phase 7: run full scenario-zero end-to-end against the L-release RIC.

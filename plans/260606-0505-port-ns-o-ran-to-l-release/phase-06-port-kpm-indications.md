# Phase 6 — Port KPM indication messages (area D = ns-3 metric mapping)

## Context Links
- Overview: [plan.md](plan.md); subscription from [phase-05](phase-05-port-subscription-handling.md)
- Source: `oran-interface/model/kpm-indication.cc`/`.h`, `oran-interface/helper/mmwave-indication-message-helper.cc`, `…/lte-indication-message-helper.cc`
- Metric source: `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc` (`BuildAndSendReportMessage`), `…/lte/model/lte-enb-net-device.cc`

## Overview
- **Priority:** P0. **Status:** planned.
- Emit valid **E2SM-KPM v3.00 RICindication** PDUs carrying ns-3 metrics: first static (**M5 dummy**), then live sim values (**M6 real**).

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
- [ ] v3 IndicationHeader (8-byte timestamp)
- [ ] v3 IndicationMessage (MeasurementRecord, v3 label/types)
- [ ] helpers map ns-3 metrics → v3 items
- [ ] **M5 dummy KPM** decoded by kpimon-go
- [ ] **M6 real ns-3 KPM** decoded; values track sim
- [ ] harness M5/M6 assertions

## Success Criteria
kpimon-go decodes E2SM-KPM v3.00 indications carrying ns-3 metrics (M5 then M6); harness asserts both.

## Risk Assessment
- Decode fails on label/record shape → diff vs golden indication; verify 8-byte timestamp + label field order.
- Metric→item mismatch (units/types) → validate a couple of values by hand against sim logs; record mapping table in notes.

## Security Considerations
- None new.

## Next Steps
→ Phase 7: run full scenario-zero end-to-end against the L-release RIC.

# Phase 4 — Port E2SM-KPM v3.00 RAN function definition (area C)

## Context Links
- Overview: [plan.md](plan.md); E2 Setup from [phase-03](phase-03-port-e2-setup.md)
- Source: `oran-interface/model/kpm-function-description.cc`/`.h`
- Target ASN.1: `…/e2-interface/e2sim/asn1c/asn/v03/e2sm-kpm-v03.00.asn`
- kpimon-go func-ID/OID: from [phase-01](phase-01-confirm-lrelease-e2term.md) `lrelease-facts.md`

## Overview
- **Priority:** P0. **Status:** ✅ DONE (2026-06-06) — v3.00 descriptor encodes (1600 B), round-trips, live M3 GREEN with real descriptor on wire.
- Build a valid **E2SM-KPM v3.00 RAN function description** so the E2Term/e2mgr **accept** the ns-3 node's KPM function (**M3**).

## Key Insights
- v3 changes: `ric_ReportStyle_Type`→`ric_Style_Type`; `ric_KPM_Node_List` **removed**; real KPM v3 OID (`…53148 e2(1) version3(3) e2sm(2) e2sm-KPMMON-IEs(2)`); ActionDefinition now Formats 1–5.
- Dummy `OID123` placeholder in Bronze code **will be rejected** → must emit the real OID.
- RAN-function-ID must match what kpimon-go subscribes to (Phase 1), not the legacy 200.

## Requirements
- `kpm-function-description.cc` emits a v3.00-valid RAN function description with correct OID + style/format; advertised in E2 Setup; accepted by RIC.

## Related Code Files
- Modify (`oran-interface` `dev/l-release`): `model/kpm-function-description.cc`/`.h` (OID, `ric_Style_Type`, drop node list, report/trigger styles valid for v3), `model/oran-interface.cc` (RAN func ID registration).
- Regenerate (`oran-e2sim`): E2SM-KPM v3 C types from `e2sm-kpm-v03.00.asn` (pinned `asn1c`).

## Implementation Steps
1. Confirm new e2sim base ships generated E2SM-KPM v3 C types (it should, from `e2-interface`); else regenerate with pinned `asn1c` per manifest. Never hand-edit generated files.
2. Rewrite `kpm-function-description.cc`: set real KPM v3 OID; build `E2SM-KPM-RANfunction-Description` with v3 field names (`ric_Style_Type`), report style type=1, trigger style periodic; remove `ric_KPM_Node_List` usage.
3. Set RAN-function-ID to the kpimon-go-expected value (from Phase 1). If kpimon uses a fixed ID, stop hardcoding 200; centralize as a constant. Document rationale in notes.
4. Rebuild; re-run the E2 Setup app (Phase 3) advertising the KPM function.
5. Assert **M3**: function present in E2 Setup Response / `kubectl -n ricplt logs <e2mgr>` shows RAN function registered; no `RANfunction rejected`. Compare to golden pcap RAN-func IE.

## Todo List
- [x] E2SM-KPM v3 C types available (vendored OSC `da6f82f2`, asn1c 0.9.29 — no regen)
- [x] OID emitted = `OID123` (golden parity; "real OID" plan note superseded by evidence — OSC sim + E2Term use OID123) — user-approved
- [x] v3 field port applied: `ric_Indication{Header,Message}Format_Type` rename + `ric_ActionFormat_Type` + `measInfo_Action_List` (per-style, free-safe); EventTrigger unchanged; `ric_KPM_Node_List` already absent in v3 struct
- [x] RAN-func-ID = **2** (mirrors OSC kpm_sim / Phase 2-3; kpimon func-0 vs 2 = Q3, deferred Phase 5)
- [x] **M3 RAN function accepted** — live E2Term, real 1600 B descriptor on wire, all 4 asserts PASS

## Success Criteria
✅ MET. ns-3-side encoder produces a valid E2SM-KPM v3.00 RAN-function-description (1600 B, round-trip decode consumes all bytes, 1 trigger + 5 report styles + 9 measurements), advertised in E2 Setup and accepted by the live L-release RIC (E2setupResponse + RANfunctionsAccepted, no reject). Descriptor content (ORAN-E2SM-KPM/OID123/KPM Monitor/Periodic Report/E2 Node Measurement/DRB./L1M. metrics) verified on the wire.

## Risk Assessment
- OID/version still rejected → byte-diff RAN-func IE vs golden pcap; verify OID arc + version3.
- Func-ID mismatch → subscriptions never arrive in Phase 5; lock ID from kpimon-go evidence now.

## Security Considerations
- None new.

## Next Steps
→ Phase 5: accept RIC subscriptions for the now-registered KPM function (M4).

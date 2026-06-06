# Phase 3 — Port E2 Setup procedure (area A SCTP + area B E2AP)

## Context Links
- Overview: [plan.md](plan.md); base from [phase-02](phase-02-standalone-e2sim-test.md)
- Source: `oran-interface/model/oran-interface.cc` (E2Termination), `oran-e2sim/e2sim/src/encoding/encode_e2apv1.*`, `…/messagerouting/e2ap_message_handler.cpp`, `…/SCTP/e2sim_sctp.cpp`
- Build: `oran-interface/CMakeLists.txt` (`find_external_library(e2sim)`), `ns3-mmwave-oran/e2term-ns3-build.sh`

## Overview
- **Priority:** P0. **Status:** DONE — M2 GREEN.
- Relink `oran-interface` onto the new e2sim base and make the ns-3-built E2 termination complete **E2 Setup (M2)** against the live L-release E2Term. Keep version specifics behind an **adapter boundary** in `oran-interface/model/`.

## Key Insights
- The E2 Setup byte format is now E2AP v3.01 (APER, `ProtocolIE-Container` `85P21`, updated `GlobalE2node-ID`). Old `generate_e2apv1_*` paths must be replaced with v3 generators from the new base.
- ns-3 = SCTP client/initiator; only the destination changes (node-IP:32222) plus the PDU encoding.
- Isolate removed/renamed structs so ns-3 callers (`E2Termination` API) stay stable.

## Requirements
- `oran-interface` compiles + links against new `libe2sim`; minimal E2 termination sends a valid v3.01 E2SetupRequest and parses E2SetupResponse from the live RIC.

## Architecture
- Adapter: a thin `model/` translation unit wrapping v3 setup encode/decode so `oran-interface.cc` public API is unchanged. All `87P11`/`ric_*` renames absorbed here.

## Related Code Files
- Modify (`oran-interface` `dev/l-release`): `model/oran-interface.cc`/`.h` (connect params, setup send/parse), `model/asn1c-types.*` (include paths `<>`→`""`, S-NSSAI/QosFlowIdentifier types), `CMakeLists.txt` (e2sim include/lib paths).
- Modify (`oran-e2sim`): ensure v3 setup generators exported (from `e2-interface` base).
- Modify (`ns3-mmwave-oran`): expose `--e2TermPort` (default 32222) alongside `--e2TermIp`; wire into `E2Termination`.

## Implementation Steps
1. Point `oran-interface/CMakeLists.txt` at new e2sim headers/libs; rebuild via `e2term-ns3-build.sh` on `oran-kvm-2`; fix compile breaks (include style, `S-NSSAI.h`, `QosFlowIdentifier_t`, container template params).
2. Replace E2 Setup encode path: swap `generate_e2apv1_setup_*` for v3 equivalents; build `GlobalE2node-ID` (gNB/eNB) per v03 IEs.
3. Make E2Term endpoint configurable: add `e2TermPort` GlobalValue in `ns3-mmwave-oran`; default 32222; pass to `oran-interface` SCTP connect.
4. Build a minimal harness target (or reuse `oran-interface/examples/oran-interface-example.cc`) that only does SCTP connect + E2 Setup; run on `oran-kvm-2` → node-IP:32222.
5. Capture pcap; assert via harness **M2**: E2setupRequest→Response, no failure; compare structure to golden L-release pcap.
6. Log all struct renames/removals handled in `implementation-notes.html` (esp. `ric_KPM_Node_List` removal, `ric_Style_Type`).

## Todo List
- [x] `oran-interface` compiles+links on new e2sim base (standalone app; `E2Termination::DoStart` adapter → Phase 6)
- [x] v3.01 E2SetupRequest generated; GlobalE2node-ID correct (run_loop handles internally)
- [x] `--e2TermPort` plumbed (default 32222 via `argv[2]`)
- [x] minimal E2-setup app runs on `oran-kvm-2` (`/tmp/ns3-e2-phase3-build/e2-setup-minimal`)
- [x] **M2 E2 Setup** green vs golden pcap (`captures/phase3-m2-ns3-setup.pcap`; all 4 assertions PASS)
- [x] adapter boundary documented in notes (§3d adapter table in implementation-notes.html)

## Success Criteria
ns-3-built E2 termination completes E2 Setup against the live L-release E2Term (M2), API surface unchanged for ns-3 callers.

## Risk Assessment
- Linker errors from container template/type renames (HIGH) → fix in adapter; do not hand-edit generated ASN.1c.
- E2Term rejects setup (version/OID) → diff against golden pcap byte-by-byte; verify APER vs PER.

## Security Considerations
- None new.

## Next Steps
→ Phase 4: port the E2SM-KPM v3.00 RAN function definition (area C) so the function is accepted (M3).

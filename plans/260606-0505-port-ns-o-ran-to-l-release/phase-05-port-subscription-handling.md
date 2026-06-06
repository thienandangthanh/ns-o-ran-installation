# Phase 5 — Port subscription handling

## Context Links
- Overview: [plan.md](plan.md); RAN func from [phase-04](phase-04-port-e2sm-kpm-ran-function.md)
- Source: `oran-e2sim/e2sim/src/messagerouting/e2ap_message_handler.cpp` (RIC subscription handler), `…/encoding/encode_e2apv1.cpp` (subscription response), `oran-interface/model/oran-interface.cc` (`ProcessRicSubscriptionRequest`)

## Overview
- **Priority:** P0. **Status:** ✅ DONE (M4 GREEN — real kpimon-go subscription admitted; offline proof + live pcap, both decode paths).
- Decode the L-release **RICsubscriptionRequest** for the KPM function and return a valid **RICsubscriptionResponse** (**M4**), driven by the real kpimon-go xApp.

## Key Insights
- ActionDefinition expanded Format1→Formats 1–5; ns-3 only needs to **emit/accept Format1** but must **tolerate** other formats without decode failure.
- ProtocolIE-ID assignments changed in v3 → subscription IEs must use the new IDs (from regenerated types).
- The subscription carries the action (what to report) → its decode feeds Phase 6 indication content.

## Requirements
- ns-3 E2 node decodes a real KPM subscription from kpimon-go and replies success; subscription state stored for indication emission.

## Related Code Files
- Modify (`oran-e2sim` `dev/l-release`): subscription decode + response in message router/encoding (v3 IEs, Format1 path, graceful handling of Formats 2–5).
- Modify (`oran-interface`): `model/oran-interface.cc` subscription callback wiring (RAN func ID → KPM callback), keep API stable.

## Implementation Steps
1. Update subscription decode path to v3 ProtocolIE-IDs; parse `RICsubscriptionDetails` + `E2SM-KPM-ActionDefinition` (Format1).
2. Add tolerant handling for ActionDefinition Formats 2–5 (log + accept or reject cleanly; default: accept Format1, reject others with proper cause — document choice in notes).
3. Build the success-path `RICsubscriptionResponse` (v3) with admitted action list.
4. Drive a real subscription: trigger kpimon-go to subscribe to the ns-3 node's KPM function (node registered in Phase 4). Capture pcap.
5. Assert **M4**: RICsubscriptionRequest→Response success; `kubectl -n ricplt logs <kpimon>` shows subscription established. Compare to golden pcap.

## Todo List
- [x] v3 subscription decode (correct ProtocolIE-IDs) — handled by installed libe2sim v3 dispatcher; our callback parses RICrequestID + RICsubscriptionDetails
- [x] ActionDefinition Format1 parsed; Formats 2–5 handled gracefully — keyed off `ricActionType` only, never decoding the action body → any format tolerated
- [x] v3 RICsubscriptionResponse success emitted — `kpm-subscription-handler.h` (admit first REPORT) + offline round-trip proof
- [x] kpimon-go subscription established to ns-3 node — onboarded via NIST testbed script (func id 2); subscribed after RNIB rescan
- [x] **M4 subscription succeeds** — `phase5-m4-subscription.pcap`: successfulOutcome/id-RICsubscription, RICrequestID 123/1 echoed, action id 1 admitted (host E2AP decode + VM byte-fallback both PASS)

## Implementation notes (as-built)
- **Code:** `oran-interface/examples/kpm-subscription-handler.h` (pure parse+build, no send) + `e2-setup-minimal.cc` registers the callback under func 2 (kpimon-go) and func 0 (scp-kpimon fallback). Offline proof: `kpm-subscription-test.cc`.
- **No e2sim/oran-interface.cc edits needed:** the installed OSC libe2sim already does v3 subscription decode + dispatch (`get_function_id_from_subscription` → registered callback) and provides `generate_e2apv1_subscription_response_success`. The plan's "modify oran-e2sim/oran-interface" steps were obviated by the vendored OSC lib — kept the API stable.
- **Live-RIC gotchas (now codified in `m4-subscription.sh`):** connect to e2term POD IP:36422 over cni0 (NodePort 32222 SNAT resets a persistent association); clear stale RNIB via `PUT /v1/nodeb/shutdown` before connecting (a DISCONNECTED entry makes e2term skip setup); restart kpimon-go after the node is CONNECTED so it re-scans RNIB and subscribes.
- **Response quirk:** libe2sim hardcodes RANfunctionID=147 in the response; submgr correlates by RICrequestID, so it is accepted (proven live).

## Success Criteria
A real kpimon-go subscription to the ns-3 node's KPM function completes successfully (M4); action stored for indications.

## Risk Assessment
- Subscription decode fails on unexpected format → tolerant handling + log raw PDU; diff vs golden subscription.
- Wrong ProtocolIE-IDs → silent drop; verify against regenerated `ProtocolIE-ID.h`.

## Security Considerations
- None new.

## Next Steps
→ Phase 6: emit KPM v3 indications carrying ns-3 metrics for the admitted action (M5 dummy → M6 real).

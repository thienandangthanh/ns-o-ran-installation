# Phase 4 — RC receive + ACK (plumbing, M-RC1)

**Plan:** `260609-0127-rc-path-and-xapp-deploy-observe` · **Depends:** Phase 3 (M3 DONE — RC-2.0 asn.1 in `libasn1c_e2.a`).
**Exit M-RC1:** deployed `rc` xApp → RIC Control Request (funcId 300) decoded by ns-3 + **RIC Control Acknowledge on wire**.
**Status:** ✅ **M-RC1 DONE (2026-06-13)** — RICcontrolRequest→RICcontrolAcknowledge pair on wire; ACK byte-verified; RC-2.0 decode of real bytes confirmed (settles open Q4). See §"Phase 4 result".

## Goal (scoped)
Prove the **receive + ACK** half of the control loop with a **no-op action**. ns-3 must: (1) dispatch the
incoming `RICcontrolRequest` (procedureCode 4) — today e2sim drops it at the `default:` handler, (2) decode
header/message as RC-2.0, (3) encode + send a `RICcontrolAcknowledge`. **No handover yet** (Phase 5). **No
RAN-parameter act** (Phase 5). **No RANFunctionDefinition advertisement rewrite** (deferred — see §Scope).

## Evidence baseline (verified 2026-06-12, read-only)
- **e2sim drops control.** `oran-e2sim/.../e2ap_message_handler.cpp` `switch(procedureCode)` has **no
  `case ProcedureCode_id_RICcontrol` (=4)** → falls to `default: "No available handler"`. Matches Phase-0
  "ns-3 RX 87 B ×3, no ACK". Fix = add the case + dispatch to a callback keyed by funcId.
- **No ACK encoder.** `encode_e2apv1.{hpp,cpp}` has setup/subscription/indication/service-update/reset — **no
  control-acknowledge**. Outer type `asn_DEF_RICcontrolAcknowledge` **is** in `libasn1c_e2.a` (`asn1c/RICcontrolAcknowledge.c`).
- **Callback transport.** `E2Sim::encode_and_send_sctp_data(pdu)` sends on the global `client_fd` (stored at
  connect). So a control callback can ACK via `m_e2term->SendE2Message(ackPdu)` — **no socket_fd plumbing**.
- **Dispatch map.** `subscription_callbacks` keyed by funcId; `get_subscription_callback(id)` throws
  `out_of_range` if unregistered. KPM=funcId 2 registered today; RC=funcId 300 **not** registered.
  Trampoline300 already exists in `oran-interface.cc` (g_cbMap[300]).
- **RC-2.0 type drift vs v1-era code (the real work):**
  - `ric-control-message.cc` (commented out, `CMakeLists.txt:51/64`): header reads use v1 names
    `ueId`/`ric_ControlStyle_Type`. RC-2.0 `E2SM_RC_ControlHeader_Format1_t` = `ueID`, `ric_Style_Type`,
    `ric_ControlAction_ID`, `*ric_ControlDecision`. → **renames** (small).
  - `ExtractRANParametersFromControlMessage` uses v1 `ranParameters_List` + `RANParameter_Item_t`. RC-2.0
    `E2SM_RC_ControlMessage_Format1` = `ranP_List` of `E2SM_RC_ControlMessage_Format1_Item`. → **stub for
    M-RC1** (extraction is Phase-5 act); decode message, confirm `controlMessage_Format1` present, log, skip extract.
  - `ric-control-function-description.cc` (also commented out): built on `RIC_ControlStyle_Item_t` /
    `ric_ControlStyle_List` — **these do not exist in RC-2.0** (RC-2.0 = `RANFunctionDefinition-Control`,
    `RANFunctionDefinition-Control-Item`, `…-Action-Item`). Full structural **rewrite** → **deferred** (§Scope);
    NOT re-enabled in Phase 4.
- **Phase-0 control facts:** rc is gRPC-driven (`:7777 SendRICControlReqServiceGrpc`), funcId 300,
  `RICControlAckReqVal` enum NO_ACK=1/ACK=2, `RICControlCellTypeVal` NR=1/EUTRAN=2. e2term forwards control
  to the E2 node **by funcId, without requiring the node to advertise RC** (proven Phase-0) → advertisement
  not needed for M-RC1.

## Scope decision (why M-RC1 ≠ full Phase 4 text)
Plan §Phase-4 also says "advertise an RC RANfunction in E2 Setup (real OID + funcId)". That requires a
**ground-up rewrite** of `ric-control-function-description.cc` to the RC-2.0 `RANFunctionDefinition-Control`
tree (the v1 `RIC-ControlStyle-Item` type is gone). Phase-0 proved control is delivered by funcId **without**
advertisement, so the rewrite is **not on the critical path for ACK-on-wire**. Phase 5 ("act") needs the RAN-
parameter extraction anyway and is the natural home for the descriptor + real OID. **Phase 4 = callback-only
registration for funcId 300** (no descriptor). Advertisement + real OID + `ranP_List` extraction → **Phase 5**.

## Architecture (data flow)
```
rc xApp --gRPC--> ricxapp-rc --E2AP RICcontrolRequest(funcId300)--> e2term --SCTP--> ns-3 e2sim client_fd
  e2ap_handle_sctp_data: procedureCode==RICcontrol(4)  [NEW case]
    -> func_id = get_function_id_from_control(pdu)      [NEW helper]
    -> cb = e2sim->get_subscription_callback(func_id)    (300 -> Trampoline300 -> g_cbMap[300])
    -> cb(pdu)
       = MmWaveEnbNetDevice::RicControlMessageCallback(pdu)   [NEW]
           RicControlMessage rc(pdu)        // decode hdr+msg (RC-2.0), no-op
           build RICcontrolAcknowledge(reqId, ranFuncId, status=success)   [NEW encoder]
           m_e2term->SendE2Message(ackPdu)  // -> encode_and_send_sctp_data -> client_fd
ns-3 --SCTP RICcontrolAcknowledge--> e2term --> rc   (ACK on wire)
```

## Related code files
**Modify — e2sim (`oran-e2sim/e2sim/`, rebuilds `libe2sim_shared.so`):**
- `src/messagerouting/e2ap_message_handler.cpp` — add `case ProcedureCode_id_RICcontrol` → dispatch.
- `src/encoding/encode_e2apv1.{cpp,hpp}` — add `generate_e2apv1_control_acknowledge(...)` +
  `get_function_id_from_control(pdu)` helper (mirror `get_function_id_from_subscription`).
- (No e2sim.hpp change — **reuse** `subscription_callbacks` map; funcId 300 disjoint from KPM 2.)

**Modify — oran-interface (`oran-interface/`, rebuilds with ns-3):**
- `CMakeLists.txt` — re-enable `model/ric-control-message.cc` + `.h` (lines 51,64). **Leave
  `ric-control-function-description.*` commented** (deferred).
- `model/ric-control-message.{cc,h}` — RC-2.0 field renames in header-decode; stub
  `ExtractRANParametersFromControlMessage` (guard/return empty, TODO Phase-5 `ranP_List`); keep ACK-relevant
  getters (`m_ricRequestId`, `m_ranFunctionId`, `m_ricCallProcessId`).
- `model/oran-interface.{cc,h}` — add `RegisterSmControlCallback(funcId, cb)` (callback-only: store in
  g_cbMap + `register_subscription_callback`, NO `register_e2sm`). Optional ACK-build helper or leave in enb.

**Modify — ns-3 mmwave (`ns3-mmwave-oran/src/mmwave/model/`):**
- `mmwave-enb-net-device.{cc,h}` — add `RicControlMessageCallback(E2AP_PDU_t*)`; register it for funcId 300
  in the E2 setup path (next to `RegisterKpmCallbackToE2Sm`, ~line 638). Builds + sends ACK.

## Implementation steps
1. **e2sim ACK encoder.** In `encode_e2apv1.cpp`: `generate_e2apv1_control_acknowledge(E2AP_PDU* ack, long
   requestorId, long instanceId, long ranFuncId, RICcallProcessID_t* callProc /*nullable*/)`. Build
   `SuccessfulOutcome` / `ProcedureCode_id_RICcontrol` / `RICcontrolAcknowledge` with IEs: RICrequestID,
   RANfunctionID, (optional RICcallProcessID), RICcontrolStatus=success. Mirror IE-container pattern from
   `generate_e2apv1_subscription_response_success`. **DO NOT call `asn_check_constraints`** (Phase-3 landmine).
   Declare in `.hpp`.
2. **e2sim control dispatch.** `get_function_id_from_control(pdu)` helper (read RANfunctionID IE from
   `RICcontrolRequest`). Add `case ProcedureCode_id_RICcontrol:` in handler → `initiatingMessage` branch:
   get func_id, `get_subscription_callback(func_id)`, `cb(pdu)`; try/catch out_of_range like subscription.
3. **Rebuild + install e2sim** (VM, strict order): `cd oran-e2sim/e2sim && cmake -B _bld && make -C _bld -jN
   && sudo make install` (libe2sim_shared.so) → `sudo cp src/base/e2sim.hpp /usr/local/include/e2sim/` →
   ensure `libasn1c_e2.a` intact (RC symbols). Sanity: `nm -DC /usr/local/lib/libe2sim_shared.so | grep -i
   control_ack` resolves.
4. **oran-interface: re-enable + reconcile.** Uncomment ric-control-message in CMakeLists; apply RC-2.0
   renames; stub extract. Add `RegisterSmControlCallback`.
5. **ns-3 enb callback + ACK.** Implement `RicControlMessageCallback`: `RicControlMessage msg(pdu)` (decode +
   log header/action id), build ACK via `encoding::generate_e2apv1_control_acknowledge(...)` using
   `msg.m_ricRequestId`/`m_ranFunctionId`/`m_ricCallProcessId`, `m_e2term->SendE2Message(ack)`. Register for
   funcId 300 in setup path.
6. **Build ns-3** (VM, cached/fast): `cd /home/uc/ns-O-RAN-installation/ns3-mmwave-oran && ./ns3 build`.
7. **Live test (M-RC1 gate).** Per Phase-0 recipe: ricplt healthy, kpimon-go Running, deploy rc; `pkill -9`
   stale ns-3; run scenario (connect via working **pod-IP**, NOT NodePort — Phase-0/M2 D2); gNB CONNECTED;
   `grpcurl … rc:7777 SendRICControlReqServiceGrpc` (funcId 300, ackReq=ACK). Capture SCTP. **Assert pcap
   shows RICcontrolRequest → RICcontrolAcknowledge pair**; ns-3 log shows decode + "Sent RIC Control Ack".
8. **Commit + sync.** VM `dev/l-release`: `feat(rc): Phase 4 RC receive+ACK (M-RC1)` on oran-e2sim +
   oran-interface + ns3-mmwave-oran; push origin; pull locally. Update plan.md status + Phase-4 result.

## Todo
- [ ] e2sim: `generate_e2apv1_control_acknowledge` + `get_function_id_from_control` (+ .hpp decls)
- [ ] e2sim: `case ProcedureCode_id_RICcontrol` dispatch
- [ ] e2sim: rebuild + install libe2sim_shared.so (libasn1c_e2.a intact)
- [ ] oran-interface: re-enable ric-control-message.cc; RC-2.0 renames; stub extract
- [ ] oran-interface: `RegisterSmControlCallback` (callback-only)
- [ ] ns-3: `RicControlMessageCallback` (decode + ACK) + register funcId 300
- [ ] ns-3 build GREEN
- [ ] Live: RICcontrolRequest → Acknowledge pair on wire (pcap + logs)
- [ ] Commit/push forks + plan sync-back

## Success criteria (M-RC1)
- [ ] e2sim dispatches procedureCode 4 to ns-3 (no more `default:` drop).
- [ ] ns-3 decodes captured Control Request (RC-2.0 header Format1; action id logged) without crash.
- [ ] ns-3 emits a valid `RICcontrolAcknowledge`; pcap shows Request→Acknowledge pair (Wireshark/offline asn1c).
- [ ] KPM path unaffected (regression: scenario still produces KPM indications → InfluxDB).
- [ ] Re-runnable: live recipe documented; commits pinned.

## Risks / landmines
- **asn_check_constraints** infinite-loops on RANParameter-bearing RC PDUs (Phase-3) — never call on RC encode/decode.
- **ACK IE container type** (`ProtocolIE_Container_85P15_t`) — get the exact IE id/criticality from
  `RICcontrolAcknowledge-IEs.h`; copy the container-build idiom from subscription-response.
- **client_fd send-thread**: callback runs on e2sim run_loop thread; `SendE2Message` on same fd is safe
  (synchronous within handler), mirrors subscription-response send.
- **RC-2.0 vs nov2021** (open Q4): decode the real captured 87 B as 2.0; if it fails, test nov2021. Settle here.
- **v1→2.0 reconcile creep**: keep extraction stubbed; resist pulling Phase-5 act work forward.
- **VM-only validation**: live ACK-on-wire only verifiable on oran-kvm-2 (single-node RIC).

## Out of scope (→ Phase 5)
- RC RANFunctionDefinition advertisement rewrite (RC-2.0) + real OID at registration.
- `ranP_List` RAN-parameter extraction; Control Action → ns-3 handover; ACK reflecting act outcome.

## Open questions
1. ACK content depth: bare success (RICrequestID+RANfunctionID+status) vs include RICcontrolOutcome? M-RC1 =
   bare success (no-op). **Resolved:** bare RICrequestID+RANfunctionID ACK accepted (grpcurl returned
   "Success Response"; rc forwarded without error). E2AP v03.01 RICcontrolAcknowledge has no RICcontrolStatus IE.
2. Reuse `subscription_callbacks` map for control vs add dedicated `control_callbacks` map — chose **reuse**
   (KISS, funcId-disjoint). Revisit only if a funcId ever needs both subscribe + control.

## Phase 4 result (M-RC1 GREEN, 2026-06-13)
- **Wiring reality corrected mid-impl:** the live RC E2 node = the **mmwave gNB** (`gnb_734_373_16b8cef1`),
  not the LTE eNB. e2term routes control by the target node's SCTP association; the gNB's e2sim instance had
  only funcId 2 (KPM) → `get_subscription_callback(300)` threw `out_of_range` ("No RAN Function … for control").
  Fix: register the RC control function (funcId 300) on **`mmwave-enb-net-device`** too (defined the declared-
  but-empty `ControlMessageReceivedCallback`). lte-enb path kept (harmless; ACKs if ever targeted).
- **Files changed (8):** e2sim — `encode_e2apv1.{hpp,cpp}` (`generate_e2apv1_control_acknowledge` +
  `get_function_id_from_control`), `e2ap_message_handler.cpp` (`case ProcedureCode_id_RICcontrol` dispatch).
  oran-interface — `CMakeLists.txt` (re-enable `ric-control-message.cc`), `oran-interface.h` (drop stub
  `RicControlMessage`, keep `RicControlFunctionDescription` stub), `ric-control-message.{h,cc}` (real RC-2.0
  minimal decoder: nested `ric_controlHeader_formats.choice`; RAN-param extraction stubbed → Phase 5).
  ns-3 — `lte-enb-net-device.cc` + `mmwave-enb-net-device.cc` (decode + ACK, register funcId 300).
- **Build:** `libe2sim_shared.so` rebuilt+installed (`asn1c-rc`/`libasn1c_e2.a` untouched); ns-3 GREEN; new
  symbols present. RC asn symbols (`asn_DEF_E2SM_RC_*`) link via oran-interface (re-enabled .cc references them).
- **Live (pod-IP `10.244.0.13`, scenario-zero, gNB CONNECTED):** grpcurl→rc:7777 (funcId 300, Style 3,
  Action 1, AckReq=ACK) → "Success Response". ns-3 log: dispatch funcId 300 → callback → **RC-2.0
  ControlHeader Format1 decoded `ric_Style_Type=3 ric_ControlAction_ID=1`** (matches payload) → ControlMessage
  Format1 decoded → ACK APER-encoded **22 B** → `sctp_send_data`. No crash; ns-3 stayed up.
- **On wire (pcap `phase4-rc-1781277669.pcapng`):** frame 2205 `RICcontrolRequest` (e2term→ns-3) ; frame 2207
  22 B SCTP DATA (ns-3→e2term :36422) = the ACK. Byte-decode: `20`(successfulOutcome) `04`(procCode RICcontrol)
  IE `1d`=RICrequestID{req 2, inst 10}, IE `05`=RANfunctionID `01 2c`=**300**. Request→Acknowledge pair proven.
- **Open Q4 settled:** the captured rc Control Request decodes cleanly as **RC-2.0** (header Format1 `RC_OK`);
  nov2021 not needed.
- **Notes/landmines:** ns-3 e2sim sends ACK with **SCTP PPID 0** (not 70) → tshark 3.2.3 heuristic mislabels
  the ACK frame as "X2AP" (cosmetic; e2term accepts it; matches existing KPM-indication PPID behavior).
  `asn_check_constraints` deliberately NOT called on the ACK (Phase-3 landmine). KPM funcId 2 still registered
  + advertised alongside 300 (E2 Setup succeeded with both) — KPM code paths untouched (not separately
  re-subscribed live this session).
- **Phase-5 carry-forward:** RAN-parameter (`ranP_List`) extraction + Control-Action→ns-3 handover; real RC
  RANFunctionDefinition advertisement (OID + control-style tree) replacing the null-buffer stub.

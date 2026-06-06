# Handoff — Phase 5 (Subscription handling, M4 GREEN) → Phase 6 start

**Date:** 2026-06-06 · **Branch (super):** `dev/migrate-to-l-release` · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/`
**Scope this session:** Phase 5 only — port subscription handling: decode a real L-release `RICsubscriptionRequest` for the KPM RAN function and reply `RICsubscriptionResponse(success)`. Milestone M4.

## What this session did

- Built standalone (no-send) subscription handler `oran-interface/examples/kpm-subscription-handler.h`: `kpm_v3::BuildSubscriptionResponse(E2Sim&, E2AP_PDU* req, vector<long>& accepted, vector<long>& rejected)` — parses RICrequestID + RICsubscriptionDetails, admits the FIRST REPORT action / rejects rest, builds `RICsubscriptionResponse(success)` via installed `E2Sim::generate_e2apv1_subscription_response_success`. Mirrors OSC `kpm_callbacks.cpp:callback_kpm_subscription_request` MINUS the indication report loop (Phase 6).
- Wired into `e2-setup-minimal.cc`: file-scope `g_e2sim` + free fn `HandleKpmSubscription` (BuildSubscriptionResponse → `encode_and_send_sctp_data`); registered the callback under func id **2** (kpimon-go) AND func id **0** (scp-kpimon fallback). Setup behavior (M2/M3) unchanged.
- Added offline round-trip correctness proof `oran-interface/examples/kpm-subscription-test.cc` → **PASS**.
- Rewrote `CMakeLists-standalone-e2-setup.cmake` to a multi-target recipe (macro `add_e2_target`): `e2-setup-minimal` + `kpm-func-desc-v3-test` + `kpm-subscription-test`.
- Replaced the Q4-gated placeholder `m4-subscription.sh` with the real live harness; relaxed `assert-pcap.sh` sub-response byte-fallback signature.
- Onboarded **kpimon-go** into `ricxapp` (RIC-cluster-modifying, user-authorized) to drive the real subscription → **M4 GREEN** verified on the wire + offline.
- Code-review clean (DONE_WITH_CONCERNS → no critical/high; port fixes 3 latent OSC bugs).
- **KEY:** NO edits needed to `oran-e2sim` or `oran-interface/model/oran-interface.cc` (the plan anticipated them). Vendored OSC libe2sim already does v3 subscription decode + dispatch (`get_function_id_from_subscription` → registered callback) and provides the response encoder. API kept stable.

## M4 Result Table

| M | Target | Result |
|---|---|---|
| M1 | SCTP INIT/INIT-ACK | **GREEN** (handshake pkts) |
| M2 | E2setupResponse | **GREEN** (`20 01` successfulOutcome/id-E2setup) |
| M4 | RICsubscriptionResponse, action admitted | **GREEN** (proc 8 SUCCESSFUL; 1 action admitted, 0 rejected) |

**Correctness proof (no network):** `kpm-subscription-test` synthesizes a `RICsubscriptionRequest` (requestor **22**/instance **6**, one REPORT action id **5**) → `BuildSubscriptionResponse` → assert admit **1**/reject **0** → APER encode (**33 bytes**) + round-trip decode consumes all 33 → assert `successfulOutcome`/`id-RICsubscription`, RICrequestID echo **22/6**, admitted action id **5**. exit 0.

**Live decode (host tshark 4.x, E2AP dissector — authoritative path A):**
- Frame 5 = E2SetupRequest (proc 1, initiating); 7 = E2setupResponse (proc 1, successful); 151 = RICsubscriptionRequest (proc 8, initiating, from kpimon via e2term); 152 = RICsubscriptionResponse (proc 8, SUCCESSFUL).
- Frame 152: `successfulOutcome`/`id-RICsubscription`; RICrequestID requestorID=**123** instanceID=**1** (kpimon's real IDs); RANfunctionID=**147** (libe2sim hardcode quirk — accepted, submgr correlates by RICrequestID); RICactions-Admitted: 1 item, ricActionID=1.
- Node log: `[e2-setup-minimal] RICsubscriptionRequest handled: 1 action(s) admitted, 0 rejected -> sending RICsubscriptionResponse(success)`.

**Assert command (all PASS):**
```bash
bash scripts/l-release-validation/assert-pcap.sh \
  scripts/l-release-validation/captures/phase5-m4-subscription.pcap \
  sctp-init e2setup-response sub-response
```
PASS M1 SCTP INIT/INIT-ACK, PASS M2 E2setupResponse, PASS M4 RICsubscriptionResponse (rc=0). VM byte-fallback also PASS after the signature fix (live response measured `20 08 00 1d …`, length `0x1d` not `0x3x` → relaxed `2008003[0-9a-f]` to `200800[0-9a-f]{2}`).

**Evidence pcap:** `scripts/l-release-validation/captures/phase5-m4-subscription.pcap` (21.5 KB).

## Key design decisions

- **Q3 RESOLVED (by code):** kpimon-go hardcodes `funcId=int64(2)` and filters `RanFunctionId==2` (`control/control.go`) → matches our advertised func id 2. scp-kpimon uses func 0 → handled by the fallback registration. **Q4 RESOLVED:** onboarded kpimon-go.
- **Offline proof split** (pure builder, no socket) so M4 logic is verifiable deterministically, independent of the flaky live capture.
- **ActionDefinition Formats 1–5 tolerated** by keying only off `ricActionType` (never decoding the action body); guards the action-item union present-tag.
- **Response intentionally NOT freed** (mirrors OSC) — libe2sim's encoder uses shallow struct copies → `ASN_STRUCT_FREE` would be a double-free hazard.

## Files changed (all in working tree, NOT committed)

| File | Action | Notes |
|---|---|---|
| `oran-interface/examples/kpm-subscription-handler.h` | **Created** | Pure (no-send) `BuildSubscriptionResponse`; mirrors OSC `callback_kpm_subscription_request` minus indication loop |
| `oran-interface/examples/e2-setup-minimal.cc` | **Modified** | `g_e2sim` + `HandleKpmSubscription`; callback registered func 2 + 0; setup unchanged |
| `oran-interface/examples/kpm-subscription-test.cc` | **Created** | Offline round-trip correctness proof (PASS, 33-byte response) |
| `oran-interface/examples/CMakeLists-standalone-e2-setup.cmake` | **Rewritten** | Multi-target (`add_e2_target` macro): minimal + func-desc-v3-test + subscription-test |
| `scripts/l-release-validation/m4-subscription.sh` | **Replaced** | Real harness (clear RNIB → persistent node → restart kpimon-go → capture → assert) |
| `scripts/l-release-validation/assert-pcap.sh` | **Modified** | Relaxed `sub-response` byte fallback `2008003[0-9a-f]`→`200800[0-9a-f]{2}` |
| `scripts/l-release-validation/captures/phase5-m4-subscription.pcap` | **Created** | M4 evidence (21.5 KB) |
| `plans/.../implementation-notes.html` | **Modified** | §3f Phase 5 + running log |
| `plans/.../phase-05-port-subscription-handling.md` | **Modified** | Status DONE, todos ticked |
| `plans/.../plan.md` | **Modified** | P5 → DONE, P6 next |

**Suggested commits when approved** (oran-interface fork `dev/l-release`, then superproject):
- `feat(e2sm-kpm): handle RICsubscriptionRequest, reply RICsubscriptionResponse(success) [func 2/0]`
- `test(l-release): Phase-5 M4 offline proof + live kpimon-go subscription harness + evidence pcap`

## Build recipe (reproducible, oran-kvm-2)

```bash
rm -rf /tmp/ns3-e2-build && mkdir /tmp/ns3-e2-build && cd /tmp/ns3-e2-build
cp <repo>/oran-interface/examples/CMakeLists-standalone-e2-setup.cmake CMakeLists.txt
cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo && make -j$(nproc)
./kpm-subscription-test    # offline proof, exit 0, 33-byte response
NS3_E2_SETUP_BIN=/tmp/ns3-e2-build/e2-setup-minimal \
  bash <repo>/scripts/l-release-validation/m4-subscription.sh
```

## Live-RIC operations performed (oran-kvm-2, user-authorized)

- Onboarded **kpimon-go** via NIST testbed script `~/O-RAN-Testbed-Automation/.../Near-Real-Time-RIC/additional_scripts/install_xapp_kpi_monitor.sh` (builds image locally → containerd, no nexus3 pull; `RAN_FUNC_ID=2`; deploys to `ricxapp`). Side effects: installed an **InfluxDB** pod into `ricplt` + a local chartmuseum. kpimon-go now Running in `ricxapp`.
- Fixed a permissions bug: the whole `~/O-RAN-Testbed-Automation/.../Near-Real-Time-RIC` tree was root-owned from a prior sudo run → `sudo chown -R uc:uc` restored ownership (was blocking the install script's `set -e` on backup cp).
- RNIB cleanup: e2mgr has no per-node REST DELETE (405); used `PUT http://<e2mgr>/v1/nodeb/shutdown` (HTTP 204) to clear the stale node. Only one node existed.

## Live-RIC gotchas discovered (CRITICAL for Phase 6/7 — codified in `m4-subscription.sh`)

1. **Persistent node MUST connect to the e2term POD IP** (`10.244.0.48:36422`) over `cni0`, **NOT** the NodePort `192.168.122.78:32222` — the NodePort/IPVS-SNAT path RESETS a persistent association (fine for one-shot M2/M3 wire captures, fatal for a node that must stay CONNECTED).
2. **Stale RNIB blocks setup:** e2term runs a fresh E2 Setup (→ E2setupResponse → CONNECTED) only for a NEW or SHUT_DOWN node. A stale DISCONNECTED RNIB entry with the same gNB-ID makes e2term accept the SCTP but SKIP setup and never reply (node stuck "Waiting for SCTP data"; gNB stays DISCONNECTED). Always clear RNIB (shutdown) before reconnecting. Each disconnect re-marks the entry DISCONNECTED → clear again before the next run.
3. **kpimon-go scans RNIB at startup:** restart it (`kubectl -n ricxapp delete pod <kpimon>`) AFTER the node is CONNECTED so it discovers the gNB and emits the subscription. gNB-ID seen live: `gnb_734_373_16b8cef1` (plmn 373437).
4. **VM tshark 3.2.3 lacks the E2AP dissector** → use the byte-signature fallback OR copy the pcap to a 4.x host (has E2AP) for the authoritative verbose decode.
5. **SSH drops (exit 255)** when an interactive command tears down the node's SCTP association — run disruptive steps inside a detached (`setsid`/`nohup`) script, not in the live SSH command. Escape hatch for a wedged testbed: `~/O-RAN-Testbed-Automation/stop.sh` then `run.sh`.

## START CHECKLIST — Phase 6 (Port KPM v3 indication messages → M5/M6)

File: `plans/260606-0505-port-ns-o-ran-to-l-release/phase-06-port-indication-messages.md`

1. **Port KPM v3 indication** (D metric mapping); emit RIC indications for the admitted action — **M5** (dummy values) → **M6** (real ns-3 KPM). The Phase-5 callback currently only logs "admitted"; the indication report loop is the Phase-6 work, hooked where `HandleKpmSubscription` notes it.
2. **RANfunctionID for the indication:** the handler does NOT currently capture the request's RANfunctionID (the dropped IE case). `generate_e2apv1_indication_request_parameterized` needs a funcId — decide: extract it from the request IE, OR thread the registration funcId via a file-scope global. Decide **before** the handler signature churns.
3. **`E2Termination::DoStart` adapter** (carried from Phase 4): rewrite to build `argv` from `m_ricAddress`+`m_ricPort` and call `run_loop(3, argv)`.
4. **ns-3 module full compile** of `kpm-function-description.cc` (carried from Phase 4) — first real ns-3 build confirms (OctetString ownership already verified safe).
5. Cluster left as: kpimon-go Running in `ricxapp`, InfluxDB pod added to `ricplt`, node not running (gNB DISCONNECTED — harmless; clear via shutdown before next live run).

## Carried open questions

- **Phase-6 RANfunctionID source (from review):** extract from request IE vs thread registration funcId via global — decide before handler signature change.
- **`E2Termination::DoStart` adapter (Phase 6):** wineslab `run_loop(string,uint16_t,…)` absent from installed lib; standalone app bypasses `E2Termination`.
- **ns-3 module compile (Phase 6/7):** `kpm-function-description.cc` ported but not yet compiled in a full ns-3 build.

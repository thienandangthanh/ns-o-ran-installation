# Handoff — Phase 6 (KPM v3.00 indications, M5 GREEN) → Phase 7 start

**Date:** 2026-06-06 · **Branch (super):** `dev/migrate-to-l-release` · **oran-interface fork:** `dev/l-release` · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/`
**Scope this session:** Phase 6 only, **M5 (dummy) scope** (user decision — M6 real-ns-3 deferred to Phase 7). Emit valid E2SM-KPM v3.00 RICindications after a subscription; have the live kpimon-go decode them.

## What this session did

- Built pure (no-send) v3 indication builders `oran-interface/examples/kpm-indication-builder.h`:
  - `kpm_v3::BuildIndicationHeader(E2SM_KPM_IndicationHeader_t*)` → `IndicationHeader-Format1` (senderName/Type/vendorName + **8-byte `colletStartTime`** = ASCII `"20200613"`, matching the v3 OCTET-STRING TimeStamp width).
  - `kpm_v3::BuildDummyIndicationMessage(E2SM_KPM_IndicationMessage_t*)` → `IndicationMessage-Format1` (one `MeasurementData` integer record + one `MeasurementInfoItem` `measID=1` labelled PLMN `747` + S-NSSAI SST `1`/SD `100`); runs `asn_check_constraints` like OSC. Mirrors OSC `encode_kpm.cpp:cell_meas_kpm_report_indication_message_style_1_initialized` (@317), the smallest valid v3 message.
  - `kpm_v3::SendIndication(E2Sim&, requestor, instance, funcId, action, seqNum)` → APER-encode header+message, `E2Sim::generate_e2apv1_indication_request_parameterized` (proc-5 RICindication), `encode_and_send_sctp_data`. **Frees the two E2SM structs (leak-free per report; safer than OSC which leaks); leaves the libe2sim-built E2AP_PDU unfreed (shallow-copy, same no-free rule as Phase 5).**
- Wired the report loop into `e2-setup-minimal.cc:HandleKpmSubscription`: after sending `RICsubscriptionResponse(success)`, emits a burst of dummy indications for the first admitted action. Count/interval via `KPM_IND_COUNT`/`KPM_IND_INTERVAL_MS` (default 10 / 1000 ms; harness sets 15 / 1000 ms).
- **RANfunctionID (Phase-5 carried Q) RESOLVED:** used the registration global `KPM_RAN_FUNC_ID=2` (mirrors OSC `gFuncId`), NOT extract-from-IE — the indication encoder takes funcId parameterized, so no handler-signature churn. Extended `BuildSubscriptionResponse` with two **optional** out-params (`out_requestorId`/`out_instanceId`, default `nullptr`) so the loop can address the indication back to the subscriber; the Phase-5 offline test caller is unaffected (purely additive).
- Added offline correctness proof `oran-interface/examples/kpm-indication-test.cc` → **PASS** (new CMake target `kpm-indication-test`).
- Rewrote `scripts/l-release-validation/m5-dummy-kpm.sh` from a placeholder-asserter to a full live harness (mirrors `m4-subscription.sh`); kept a pre-captured-pcap arg as a fallback. `assert-pcap.sh` already had the `ric-indication` + `kpm-v3` checks — **no assert change needed**.
- **KEY (same as Phase 5):** NO edits to `oran-e2sim`, `oran-interface/model/kpm-indication.cc`, or `oran-interface.cc`. Vendored libe2sim already provides the indication encoder + every v3 ASN.1 type. The Bronze v2 ns-3 `model/kpm-indication.cc` is untouched — the standalone builder is the M5 vehicle; mapping real ns-3 values into it is Phase 7 (M6).
- Code-review clean: **DONE, no critical/high.** Ownership verified against asn1c struct layouts.

## M5 Result Table

| M | Target | Result |
|---|---|---|
| M1 | SCTP INIT/INIT-ACK | **GREEN** (2 handshake pkts) |
| M2 | E2setupResponse | **GREEN** (2× proc-1) |
| M4 | RICsubscriptionResponse | **GREEN** (2× proc-8) |
| M5 | **RICindication, v3 KPM decoded by kpimon-go** | **GREEN** (15× proc-5; kpimon `Indication Header format = 1`, `No of cell metrics = 1`) |

**Correctness proof (no network):** `kpm-indication-test` builds the v3 header (38 B) + message (27 B), APER round-trips both (full consume), wraps in a proc-5 RICindication (122 B) via the libe2sim encoder, round-trips the E2AP-PDU, asserts `IndicationHeader-Format1` with an **8-byte** `colletStartTime` + `IndicationMessage-Format1` with ≥1 measData record / ≥1 measInfo item, + `initiatingMessage/id-RICindication`. **exit 0.**

**Live decode (authoritative, host tshark 4.6.5 WITH E2SM-KPM dissector):** pcap `captures/phase6-m5-indication.pcap` — procedures present: **2× proc-1, 2× proc-8, 15× proc-5**. Each RICindication: RICrequestID requestor **123**/instance **2** (kpimon's real IDs), RANfunctionID **2**, RICactionID **1**, RICindicationSN, RICindicationType `report(0)`; RICindicationHeader → `E2SM-KPM-IndicationHeader / indicationHeader-Format1` (hex `…3230323030363133…` = `"20200613"`); RICindicationMessage → `E2SM-KPM-IndicationMessage / indicationMessage-Format1` (carries `747` + `100`).

**Live kpimon-go decode (the plan's M5 success criterion):**
```
Message received: name=RIC_INDICATION meid=gnb_734_373_16b8cef1 subId=2 ... len=122
RIC Indication message from {gnb_734_373_16b8cef1} received
Indication Header format = 1
parsing for cell metrics / No of cell metrics = 1
```

**Assert command (all PASS):**
```bash
bash scripts/l-release-validation/m5-dummy-kpm.sh \
  scripts/l-release-validation/captures/phase6-m5-indication.pcap
# PASS M1 SCTP, M2 E2setupResponse, M4 sub-response, M5 RICindication, M5 E2SM-KPM v3
```

## Key design decisions

- **Dummy message = OSC cell-meas "style 1" shape**, not the UE-JSON loop — smallest PDU that validates + decodes, no file/JSON dependency. Self-contained static values (PLMN 747, S-NSSAI 1/100, integer record 1).
- **funcId via registration global, not IE extraction** (KISS; mirrors OSC `gFuncId`; encoder is parameterized so no signature churn).
- **`SendIndication` deep-frees the two E2SM structs** (the message is large per-report; a deep free is leak-free and verified single-owner against asn1c layouts) but leaves the libe2sim-built E2AP_PDU unfreed (shallow-copy double-free hazard — same rule as Phase 5).
- **Offline proof split** (pure builder, no socket) so M5 logic is deterministically verifiable, independent of the flaky live capture.

## Deviation discovered (EXPECTED — defines the M6 gap)

kpimon-go logs benign `no_of_cell_metrics != len(tmpCellKpi)` and header `RC_WMORE` alongside the successful decode. The **dummy** `measID=1`/integer record does NOT populate kpimon's named-metric (`tmpCellKpi`) table — kpimon decodes the v3 *structure* (`format = 1`, 1 cell metric) but has no named PM values to store. Closing this is exactly **M6**: map real ns-3 KPM values (throughput/PRB/CQI/…) into named `MeasurementType.measName` + matching records. Not a bug; the dummy is intentionally minimal.

## Files changed (committed to oran-interface `dev/l-release`? NO — all in working tree)

| File | Action | Notes |
|---|---|---|
| `oran-interface/examples/kpm-indication-builder.h` | **Created** | Pure v3 header/message builders + `SendIndication` |
| `oran-interface/examples/e2-setup-minimal.cc` | **Modified** | report loop in `HandleKpmSubscription`; `KPM_RAN_FUNC_ID=2`; `<unistd.h>` |
| `oran-interface/examples/kpm-subscription-handler.h` | **Modified** | `BuildSubscriptionResponse` +2 optional out-params (RICrequestID) |
| `oran-interface/examples/kpm-indication-test.cc` | **Created** | Offline round-trip proof (PASS) |
| `oran-interface/examples/CMakeLists-standalone-e2-setup.cmake` | **Modified** | +`kpm-indication-test` target |
| `scripts/l-release-validation/m5-dummy-kpm.sh` | **Rewritten** | Live harness (mirrors m4) + pre-captured-pcap fallback |
| `scripts/l-release-validation/captures/phase6-m5-indication.pcap` | **Created** | M5 evidence (25.4 KB) |
| `plans/.../implementation-notes.html` | **Modified** | §3g Phase 6 + running log |
| `plans/.../phase-06-port-kpm-indications.md` | **Modified** | Status DONE, todos, result |
| `plans/.../plan.md` | **Modified** | P6 → DONE, P7 next (absorbs M6) |
| `plans/reports/code-review-260606-2129-phase6-indications.md` | **Created** | Review report |

**Suggested commits when approved** (oran-interface fork `dev/l-release`, then superproject):
- `feat(e2sm-kpm): emit E2SM-KPM v3.00 RICindication for admitted action [func 2]`
- `test(l-release): Phase-6 M5 offline proof + live dummy-indication harness + evidence pcap`

## Build recipe (reproducible, oran-kvm-2)

```bash
rm -rf /tmp/ns3-e2-build && mkdir /tmp/ns3-e2-build && cd /tmp/ns3-e2-build
cp /home/uc/ns-O-RAN-installation/oran-interface/examples/CMakeLists-standalone-e2-setup.cmake CMakeLists.txt
cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo && make -j$(nproc)
./kpm-indication-test    # offline proof, exit 0 (hdr 38 B, msg 27 B, PDU 122 B)
NS3_E2_SETUP_BIN=/tmp/ns3-e2-build/e2-setup-minimal \
  bash /home/uc/ns-O-RAN-installation/scripts/l-release-validation/m5-dummy-kpm.sh
```

## Live-RIC state (oran-kvm-2 / cluster on oran-kvm-3, user-authorized)

- e2term-alpha pod **`10.244.0.48:36422`** (cni0, unmoved from Phase 5, age 140d), e2mgr REST `10.100.86.178:3800`, NodePort `32222`→`36422`. All match `common.sh` defaults.
- **kpimon-go Running** in `ricxapp` (it restarts/renames on each `kubectl delete pod`; current name discovered dynamically by the harness via `grep kpimon`). InfluxDB pod still in `ricplt` (from Phase 5).
- Node not running at end (gNB DISCONNECTED — harmless; harness clears RNIB via `PUT /v1/nodeb/shutdown` before each run).

## Live-RIC gotchas (re-confirmed; same as Phase 5 — see `m4`/`m5` headers)

1. Persistent node → **e2term POD IP `10.244.0.48:36422` over cni0**, NOT the NodePort (NodePort/IPVS SNAT resets a persistent association).
2. Clear stale RNIB (`PUT /v1/nodeb/shutdown`) before reconnecting; e2term re-runs setup only for a NEW/SHUT_DOWN node.
3. Restart kpimon (`kubectl -n ricxapp delete pod <kpimon>`) AFTER the node is CONNECTED so it discovers the gNB and subscribes.
4. VM tshark 3.2.3 lacks the E2AP/E2SM dissector → byte-signature fallback on the VM; copy the pcap to a 4.x host (this repo machine has 4.6.5) for the authoritative verbose decode.
5. **SSH returns 255** at harness teardown (tearing down the node SCTP drops the session) — this happens AFTER "ALL CHECKS PASSED" prints; the harness rc is 0. Don't read 255 as a failure; read the harness's own PASS lines.

## START CHECKLIST — Phase 7 (Reconnect ns-3 scenario-zero end-to-end + M6)

File: `plans/260606-0505-port-ns-o-ran-to-l-release/phase-07-reconnect-scenario-zero.md`

1. **M6 (real ns-3 KPM) lives here now.** Map live ns-3 metrics into the v3 message: replace the dummy `measID=1`/integer with named `MeasurementType.measName` + records sourced from `mmwave-enb-net-device.cc:BuildAndSendReportMessage` (and the lte path). Target: kpimon-go's `no_of_cell_metrics == len(tmpCellKpi)` (named-metric table populated), values track the sim.
2. **First full ns-3 module compile** (carried Phase 4/5): compile `oran-interface/model/kpm-function-description.cc` + `kpm-indication.cc` in a real ns-3 build. Decide: port the new v3 builders into the ns-3 `model/` classes, OR keep the standalone-header approach and have ns-3 call into it. The standalone builders are the proven-correct reference either way.
3. **`E2Termination::DoStart` adapter** (carried Phase 4/5): wineslab `run_loop(string,uint16_t,…)` is absent from the installed lib; rewrite `DoStart` to build `argv` from `m_ricAddress`+`m_ricPort` and call `run_loop(int, char**)` — OR keep bypassing `E2Termination` as the standalone app does.
4. **Indication loop blocks the SCTP-read thread** (review I3): fine for single-subscriber M5; if scenario-zero needs continuous indications during the sim, move the loop off the read thread (the OSC reference runs `run_report_loop` similarly, so likely OK for one subscriber).
5. **Constraint failure handling** (review I1): `BuildDummyIndicationMessage` does `exit(1)` on constraint failure — fine for static dummy data, but switch to an error-return before feeding dynamic ns-3 values so one bad report doesn't kill the node.

## Carried open questions

- **Phase-7 metric mapping (M6):** which of kpimon-go's named metrics to populate first, and exact `measName` strings kpimon's `tmpCellKpi` table expects (read kpimon-go's KPM parser to get the names) — verify before wiring values.
- **ns-3 build vs standalone-header strategy (Phase 7 #2):** port builders into `model/` classes or call the headers from ns-3 — decide before the first full ns-3 compile.

# Handoff — Phase 4 (E2SM-KPM v3.00 RAN function def, M3 GREEN) → Phase 5 start

**Date:** 2026-06-06 · **Branch (super):** `dev/migrate-to-l-release` · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/`
**Scope this session:** Phase 4 only — port the E2SM-KPM v3.00 RAN-function-description (area C); make the advertised descriptor genuine; validate M3 with the real descriptor on the wire.

## What this session did

- Built standalone v3.00 descriptor encoder `oran-interface/examples/kpm-func-desc-v3.h` (no ns-3 dep), mirroring OSC `encode_kpm.cpp:encode_kpm_function_description` (the code that produced the Phase-1/2 golden) field-for-field.
- Added round-trip correctness test `oran-interface/examples/kpm-func-desc-v3-test.cc`: APER-encode → `aper_decode_complete` → assert full-buffer consume + style counts + XER dump.
- Wired the real descriptor into `e2-setup-minimal.cc` (replaced the Phase-3 printable placeholder); re-ran live setup → **M3 GREEN**.
- Ported the ns-3 source-of-record `oran-interface/model/kpm-function-description.cc` to v3 (compiled Phase 6/7, not this phase).
- Added Phase-4 harness `scripts/l-release-validation/m3-ns3-funcdesc.sh` + evidence pcap.
- Code-review clean (DONE_WITH_CONCERNS → the one ownership question resolved safe).
- Updated `implementation-notes.html` §3e + running log; ticked all phase-04 todos; bumped plan.md (P3+P4 DONE, P5 next).

## M3 Result Table

| M | Target | Result |
|---|---|---|
| M1 | SCTP INIT/INIT-ACK | **GREEN** (2 handshake pkts) |
| M2 | E2setupResponse | **GREEN** (`20 01` successfulOutcome/id-E2setup) |
| M3 | RANfunctionsAccepted, no reject, **real v3.00 descriptor** | **GREEN** (`00 09` accepted; no reject IE; 1600 B descriptor on wire) |

**Correctness proof (no network):** `kpm-func-desc-v3-test` → encode **1600 bytes**, round-trip decode consumes all 1600, decodes to **1 event-trigger style + 5 report styles**, exit 0.

**Assert command (all 4 PASS):**
```bash
bash scripts/l-release-validation/assert-pcap.sh \
  scripts/l-release-validation/captures/phase4-m3-ns3-funcdesc.pcap \
  sctp-init e2setup-response ranfunc-accepted no-ranfunc-reject
```

**Evidence pcap:** `scripts/l-release-validation/captures/phase4-m3-ns3-funcdesc.pcap` (5900 B, 30 SCTP frames — vs Phase-3's 2706 B; the +Δ is the real descriptor). All 7 content markers present on the wire: `ORAN-E2SM-KPM`, `OID123`, `KPM Monitor`, `Periodic Report`, `E2 Node Measurement`, `DRB.RlcSduTransmittedVolumeDL`, `L1M.UL-SRS-RSRP`.

## Descriptor content (golden parity with OSC kpm_sim)

- RANfunction-Name: short_name `ORAN-E2SM-KPM`, desc `KPM Monitor`, instance `1`, OID **`OID123`**.
- 1 event-trigger style: type 1, `Periodic Report`, format 1.
- 5 report styles (type / name / actionFormat / indMsgFormat; indHeaderFormat always 1):
  1 `E2 Node Measurement` /1/1 · 2 `…single UE` /2/1 · 3 `Condition-based, UE-level…` /3/2 · 4 `Common Condition-based…` /4/3 · 5 `…multiple UEs` /5/3.
- 9 measurements (per style): `DRB.RlcSduTransmittedVolumeDL/UL`, `DRB.PerDataVolume{DL,UL}Dist.Bin`, `DRB.RlcPacketDropRateDLDist`, `DRB.PacketLossRateULDist`, `L1M.DL-SS-RSRP.SSB`, `L1M.DL-SS-SINR.SSB`, `L1M.UL-SRS-RSRP`.

## v3 struct delta ledger (area C — KPM func description)

| Bronze v2 | OSC v3 (installed) | Action |
|---|---|---|
| `ric_ReportIndicationHeaderFormat_Type` | `ric_IndicationHeaderFormat_Type` | renamed |
| `ric_ReportIndicationMessageFormat_Type` | `ric_IndicationMessageFormat_Type` | renamed |
| (absent) | `ric_ActionFormat_Type` | **added** (required) |
| (absent) | `measInfo_Action_List` (embedded SEQ OF) | **added** (required; per-style fresh list) |
| `ric_ReportStyle_Type` field name | unchanged (type is `RIC_Style_Type_t`) | none |
| EventTrigger item fields | unchanged | none |
| `ric_KPM_Node_List` | absent from v3 top-level struct | none (no removal code) |
| OID `1.3.6.1.4.1.53148…` (plan note) | `OID123` (OSC sim + E2Term reality) | **kept OID123** (user-approved) |

**Free-safety note:** OSC shares one `measInfo` list across all 5 styles (shallow copy → multi-free under `ASN_STRUCT_FREE`; OSC never frees). Port builds a fresh per-style list → single-free, APER-identical. ns-3 ctor's `ASN_STRUCT_FREE_CONTENTS_ONLY`+`delete` verified safe; `OctetString::~OctetString` does not free `buf` (commented out) so ShortName is single-free too.

## Build recipe (reproducible, oran-kvm-2)

CMake at `/tmp/ns3-e2-phase4/CMakeLists.txt` (regenerable — see command below): two targets `kpm-func-desc-v3-test` + `e2-setup-minimal`, same `asn1_objects` (OBJECT lib from `oran-e2sim/e2sim/asn1c/*.c`) + `libe2sim.a` + `pthread sctp` recipe as Phase 3; include dirs add `oran-interface/examples` for `kpm-func-desc-v3.h`.

```bash
# configure + build (~3 min)
rm -rf /tmp/ns3-e2-phase4-build && mkdir /tmp/ns3-e2-phase4-build
cd /tmp/ns3-e2-phase4-build
cmake /tmp/ns3-e2-phase4 -DCMAKE_BUILD_TYPE=RelWithDebInfo
make kpm-func-desc-v3-test e2-setup-minimal -j$(nproc)

# correctness (no network)
./kpm-func-desc-v3-test /tmp/kpm-func-desc-v3.bin    # → [PASS], exit 0, 1600 B

# live M3
NS3_E2_SETUP_BIN=/tmp/ns3-e2-phase4-build/e2-setup-minimal \
  bash /home/uc/ns-O-RAN-installation/scripts/l-release-validation/m3-ns3-funcdesc.sh
```

Note: the harness exits non-zero / SSH may drop on the IPVS-SNAT capture retries (Phase-2 known issue) even when the assert PASSES — **trust the pcap + assert verdict, not the wrapper exit code.** Re-running `assert-pcap.sh` on the captured pcap gives the clean exit-0 verdict.

## Files changed (all in working tree, NOT committed)

| File | Action | Notes |
|---|---|---|
| `oran-interface/examples/kpm-func-desc-v3.h` | **Created** | Standalone v3.00 descriptor builder (no ns-3 dep) |
| `oran-interface/examples/kpm-func-desc-v3-test.cc` | **Created** | Encode/decode round-trip correctness test |
| `oran-interface/examples/e2-setup-minimal.cc` | **Modified** | Advertise the real 1600 B descriptor |
| `oran-interface/model/kpm-function-description.cc` | **Modified** | ns-3 source-of-record v3 port (compiled Phase 6/7) |
| `scripts/l-release-validation/m3-ns3-funcdesc.sh` | **Created** | Phase-4 M3 harness |
| `scripts/l-release-validation/captures/phase4-m3-ns3-funcdesc.pcap` | **Created** | M3 evidence (5900 B) |
| `plans/.../implementation-notes.html` | **Modified** | §3e Phase 4 + running log |
| `plans/.../phase-04-port-e2sm-kpm-ran-function.md` | **Modified** | Status DONE, todos ticked |
| `plans/.../plan.md` | **Modified** | P3+P4 → DONE, P5 next |
| `/tmp/ns3-e2-phase4/CMakeLists.txt` | VM-only temp | Not in repo; recipe above recreates |

**Suggested commits when approved** (oran-interface fork `dev/l-release`, then superproject):
- `feat(e2sm-kpm): port v3.00 RAN-function-description encoder + round-trip test`
- `test(l-release): Phase-4 M3 harness + real-descriptor evidence pcap`

## START CHECKLIST — Phase 5 (Port subscription handling → M4)

File: `plans/260606-0505-port-ns-o-ran-to-l-release/phase-05-port-subscription-handling.md`

1. **Subscriber needed (Q4):** M4/M5 require an external `RICsubscriptionRequest` — the e2sim/our app is reactive-only. Onboard `scp-kpimon` / `kpimon-go` (`~/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-kpimon-go`) into the `ricxapp` namespace to drive a subscription. This is RIC-cluster-modifying.
2. **Resolve Q3 empirically:** our node advertises RAN-func-ID **2**; scp-kpimon subscribes func **0**. When the real subscription arrives, confirm which ID matches — adjust `e2sim.register_e2sm(<id>, …)` / kpimon config so the subscription targets our function. The genuine v3.00 descriptor (this phase) now exposes the 5 report styles + action/format types the subscriber parses.
3. **Handle the subscription in our app:** `e2-setup-minimal` only does setup. Phase 5 needs the app to accept `RICsubscriptionRequest`, build `RICsubscriptionResponse` (RIC action admitted), per the registered report style. Check `e2sim` callback hooks (`register_subscription_callback` or equivalent in installed `e2sim.hpp`).
4. **Target M4:** `RICsubscriptionResponse` with admitted action → assert via harness (`assert-pcap.sh … ric-sub-response`, sig `20 08`). Capture the indication golden if the xApp triggers reports (sets up M5).
5. The Phase-4 round-trip test + builder are the source of truth for the report-style/action-format values the subscription must reference.

**Key files to read before starting:**
- `/usr/local/include/e2sim/e2sim.hpp` — subscription callback API
- `oran-e2sim/e2sim/e2sm_examples/kpm_e2sm/src/kpm/kpm_callbacks.cpp` — OSC reference subscription + indication handling
- `oran-interface/examples/kpm-func-desc-v3.h` — the styles/formats the subscriber targets
- `plans/.../baseline/golden-lrelease-e2.pcap` + Phase-0 Bronze full pub-sub pcap — subscription wire reference

## Carried open questions

- **Q3 (Phase 5):** func **2** (our node) vs **0** (scp-kpimon) — resolve when the real subscription runs.
- **Q4 → Phase 5:** onboard scp-kpimon/kpimon-go to drive M4/M5 (decided in Phase 2/3).
- **`E2Termination::DoStart` adapter (Phase 6):** wineslab `run_loop(string,uint16_t,…)` absent from installed lib; standalone app bypasses `E2Termination`. Phase 6 rewrites `DoStart` to build `argv` from `m_ricAddress`+`m_ricPort` and call `run_loop(3, argv)`.
- **ns-3 module compile (Phase 6/7):** `kpm-function-description.cc` ported but not yet compiled in a full ns-3 build — first real ns-3 build will confirm (OctetString ownership already verified safe).

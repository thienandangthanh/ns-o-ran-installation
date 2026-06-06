# Handoff — Phase 3 (E2 Setup port, M2 GREEN) → Phase 4 start

**Date:** 2026-06-06 · **Branch (super):** `dev/migrate-to-l-release` · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/`
**Scope this session:** Phase 3 only — relink oran-interface onto the new libe2sim base, build minimal E2-setup app, validate M2 against live E2Term.

## What this session did

- Built standalone `e2-setup-minimal` app (`oran-interface/examples/e2-setup-minimal.cc`) linked against:
  - Installed `libe2sim.a` (E2AP v3.01, Phase 2 dpkg) + `asn1_objects` OBJECT lib from `oran-e2sim/e2sim/asn1c/*.c` (vendored pre-generated C)
  - Build system: temporary `CMakeLists.txt` at `/tmp/ns3-e2-phase3/CMakeLists.txt` (reproducible recipe below)
- Ran the binary against live E2Term `192.168.122.78:32222` → **M2 GREEN**: E2setupResponse received, RANfunctionsAccepted func 2 / OID123 / rev 2, no reject
- Added harness script `scripts/l-release-validation/m2-ns3-e2setup.sh` for the ns-3-side binary
- Updated `implementation-notes.html` §3d (Phase 3 section + adapter boundary table + Q4 resolved + running log)
- Ticked all 6 todos in `phase-03-port-e2-setup.md`
- **Q4 resolved → deferred Phase 5** (M4/M5 need xApp subscriber; not needed for E2 Setup)

## M2 Result Table

| M | Target | Result |
|---|---|---|
| M1 | SCTP INIT/INIT-ACK | **GREEN** (2 handshake pkts) |
| M2 | E2setupResponse | **GREEN** (`successfulOutcome/id-E2setup`, TransactionID 1) |
| M3 | RANfunctionsAccepted, no reject | **GREEN** (func 2 / OID123 / rev 2 accepted; no RANfunctionsRejected IE) |

**Assert command (all 4 assertions PASS):**
```bash
bash scripts/l-release-validation/assert-pcap.sh \
  captures/phase3-m2-ns3-setup.pcap \
  sctp-init e2setup-response ranfunc-accepted no-ranfunc-reject
```

**Structural match vs golden:** E2setupResponse `20 01` + RANfunctionsAccepted `00 09` byte-identical structure; E2setupRequest carries `ORAN-E2SM-KPM` + `OID123` ASCII + PLMN `7478` + gnb-id `b5c67788` + `E2nodeComponentConfigAddition` IE — all matching. Request is shorter than golden (minimal descriptor vs full KPM v3.00 func def — Phase 4).

**Evidence pcap:** `scripts/l-release-validation/captures/phase3-m2-ns3-setup.pcap` (2706 bytes, 15 SCTP frames)

## Adapter / Rename Ledger (Phase 3 — E2 Setup path)

| Delta | Where absorbed | Notes |
|---|---|---|
| `run_loop(string, uint16_t, ...)` wineslab ext not in lib | `e2-setup-minimal.cc` calls `run_loop(int, char**)` directly | `E2Termination::DoStart` adapter deferred to Phase 6 |
| `libe2sim_shared.so` missing asn1c symbols at link | CMakeLists links `asn1_objects` OBJECT lib from `oran-e2sim/e2sim/asn1c/*.c` | Same pattern as `kpm_sim` |
| `ProtocolIE-Container 87P11→85P21` | Absorbed in installed libe2sim | No change needed in oran-interface |
| `ric_ReportStyle_Type→ric_Style_Type` | Only used in KPM func description | Phase 4 |
| `ric_KPM_Node_List` removed | Not in E2 Setup path | Phase 4 |
| `QFI→QosFlowIdentifier`, `SNSSAI→S-NSSAI` | Installed libe2sim headers use v3 names; `asn1c-types.h` mismatch deferred | Phase 4 |
| Include style `<>→""` | Not needed for standalone app | Phase 4 (oran-interface lib build) |
| `--e2TermPort` default 32222 | `argv[2]` in standalone app | Run: `./e2-setup-minimal 192.168.122.78 32222` |

## Exact Build Recipe (reproducible, oran-kvm-2)

```bash
# 1. Create temporary CMakeLists.txt (or reuse /tmp/ns3-e2-phase3/CMakeLists.txt if present)
mkdir -p /tmp/ns3-e2-phase3
cat > /tmp/ns3-e2-phase3/CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.10)
project(e2-setup-minimal CXX C)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(ASN1C_DIR "/home/uc/ns-O-RAN-installation/oran-e2sim/e2sim/asn1c")
file(GLOB ASN1C_SOURCES "${ASN1C_DIR}/*.c")
add_library(asn1_objects OBJECT ${ASN1C_SOURCES})
target_include_directories(asn1_objects PUBLIC ${ASN1C_DIR})
set(E2SIM_INCLUDE_DIR "/usr/local/include/e2sim")
set(E2SIM_LIB_DIR     "/usr/local/lib")
add_executable(e2-setup-minimal
    /home/uc/ns-O-RAN-installation/oran-interface/examples/e2-setup-minimal.cc
)
target_include_directories(e2-setup-minimal PRIVATE
    ${E2SIM_INCLUDE_DIR} ${ASN1C_DIR})
target_link_libraries(e2-setup-minimal
    asn1_objects
    ${E2SIM_LIB_DIR}/libe2sim.a
    asn1_objects
    pthread sctp
)
EOF

# 2. Configure + build (~3 min, 493 asn1c sources + 1 app file)
rm -rf /tmp/ns3-e2-phase3-build && mkdir /tmp/ns3-e2-phase3-build
cd /tmp/ns3-e2-phase3-build  # must cd to non-blocked path first
cmake /tmp/ns3-e2-phase3 -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j$(nproc)
# Binary: /tmp/ns3-e2-phase3-build/e2-setup-minimal

# 3. Run against live E2Term
/tmp/ns3-e2-phase3-build/e2-setup-minimal 192.168.122.78 32222

# 4. Capture + assert (harness)
NS3_E2_SETUP_BIN=/tmp/ns3-e2-phase3-build/e2-setup-minimal \
  bash /home/uc/ns-O-RAN-installation/scripts/l-release-validation/m2-ns3-e2setup.sh
```

## Files Changed (all in working tree, NOT committed)

| File | Action | Notes |
|---|---|---|
| `oran-interface/examples/e2-setup-minimal.cc` | **Created** | Standalone minimal E2 Setup app |
| `oran-interface/examples/CMakeLists-standalone-e2-setup.cmake` | **Created** | Reference cmake snippet (non-functional as top-level; see recipe above) |
| `scripts/l-release-validation/m2-ns3-e2setup.sh` | **Created** | M2 harness for ns-3-side binary |
| `scripts/l-release-validation/captures/phase3-m2-ns3-setup.pcap` | **Created** | M2 evidence pcap (2706 bytes) |
| `plans/260606-0505-port-ns-o-ran-to-l-release/implementation-notes.html` | **Modified** | Added §3d Phase 3 + Q4 resolved + running log |
| `plans/260606-0505-port-ns-o-ran-to-l-release/phase-03-port-e2-setup.md` | **Modified** | Status DONE, all 6 todos ticked |
| `/tmp/ns3-e2-phase3/CMakeLists.txt` | VM-only temp | Not in repo; recipe above recreates it |

**Not committed** — orchestrator/user to approve. Suggested commit when ready:
- `feat(e2-setup): add standalone Phase-3 E2 Setup minimal app + M2 harness`

## START CHECKLIST — Phase 4 (Port E2SM-KPM v3.00 RAN Function Definition, area C → M3)

File: `plans/260606-0505-port-ns-o-ran-to-l-release/phase-04-port-e2sm-kpm-func-desc.md`

1. **Build `oran-interface/model/kpm-function-description.cc`** against the installed libe2sim headers. This currently uses:
   - `ric_ReportStyle_Type` → must rename to `ric_Style_Type` (installed header: `E2SM-KPM-RANfunction-Description.h` uses `ric_ReportStyle_List` with `ric_ReportStyle_Item`)
   - `SNSSAI.h` (wineslab/Bronze) → must use `S-NSSAI.h` (installed: `S-NSSAI.h`, type `S_NSSAI_t`)
   - `QFI` / `QosFlowIdentifier_t` — check installed vs wineslab types
   - Include style `<>→""` for asn1c headers in `asn1c-types.h`
2. **Port the KPM v3.00 E2SM-KPM-RANfunction-Description** APER encode path in `kpm-function-description.cc`. The full func def (short_name `ORAN-E2SM-KPM`, `KPM Monitor`, `Periodic Report`, measurement items) must encode to the golden's bytes (see golden pcap request at offset `0050–0x00e0+`).
3. **Register the full func description** in `e2-setup-minimal.cc` (or a new test harness target) so the E2setupRequest carries the v3.00 descriptor — this makes M3 meaningful (E2Term accepts the real OID/SM).
4. **Target M3**: E2setupResponse with RANfunctionsAccepted carrying the real KPM OID (currently `OID123` is hardcoded in libe2sim `run_loop`; the real OID is `1.3.6.1.4.1.53148.1.2.2.2` — check if E2Term requires this or accepts `OID123`).
5. Check if `E2SM-KPM-RANfunction-Description.h` in the installed headers matches the `kpm-function-description.cc` field names exactly, or requires the adapter.
6. Run `assert-pcap.sh … ranfunc-accepted` again — it should still pass (M3 was already green in Phase 3, but now with a real descriptor the response should be identical or richer).

**Key files to read before starting:**
- `/usr/local/include/e2sim/E2SM-KPM-RANfunction-Description.h` — v3 struct layout
- `oran-interface/model/kpm-function-description.cc` — current wineslab v2 encode
- `plans/260606-0505-port-ns-o-ran-to-l-release/baseline/golden-lrelease-e2setup.xml` — target bytes for the func description field

## Carried Open Questions

- **Q3 (Phase 5):** ns-3 advertises func **2** (mirror sim) vs scp-kpimon subscribing func **0** — resolve empirically when a real subscription runs.
- **Q4:** RESOLVED → deferred Phase 5. M4/M5 need external KPM xApp subscriber (scp-kpimon/kpimon-go).
- **`E2Termination::DoStart` adapter (Phase 6):** the wineslab `run_loop(string, uint16_t, ...)` overload is absent from the installed lib. The standalone app bypasses `E2Termination` entirely. When plugging into ns3-mmwave-oran (Phase 6), `DoStart` must be rewritten to construct `char* argv[]` from `m_ricAddress` + `m_ricPort` and call `run_loop(3, argv)`.

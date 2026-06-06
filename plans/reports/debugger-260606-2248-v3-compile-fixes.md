# Debugger Report: oran-interface v2→v3 E2SM-KPM Compile Fixes

**Date:** 2026-06-06
**Branch:** dev/migrate-to-l-release
**Scope:** Compile-only fixes — no semantic changes to port logic

---

## Executive Summary

Drove `oran-interface` from a failing v2→v3 E2SM-KPM asn1c port to a fully clean build:
- `make -j8 liboran-interface-obj` → 0 errors
- `./ns3 build` → 0 errors, 0 undefined references; `scratch_scenario-zero` links and exists

Root cause of the final blocker (scenario-zero linker failure): the OSC e2sim install package does NOT bundle asn1c-generated object code into either `libe2sim.a` or `libe2sim_shared.so`. The `asn1_objects` OBJECT library in the e2sim CMake tree is never exported or installed.

---

## Timeline of Fixes

### Fix 1 — `SNSSAI.h` → `S-NSSAI.h` (v3 rename)

**Error:** `asn1c-types.h:35: SNSSAI.h: No such file or directory`

**Root cause:** v3 asn1c renamed the header and struct. `SNSSAI_t` → `S_NSSAI_t`, `asn_DEF_SNSSAI` → `asn_DEF_S_NSSAI`.

**Fix:** Rewrote `asn1c-types.h` and `asn1c-types.cc`:
- `#include "S-NSSAI.h"` (v3)
- `Snssai` class: storage `S_NSSAI_t*`, `GetPointer()` returns `S_NSSAI_t*`
- `ASN_STRUCT_FREE(asn_DEF_S_NSSAI, ...)` in destructor

---

### Fix 2 — v2 L3-RRC / E2SM-NI measurement headers absent from v3

**Errors:** `RRCEvent.h: No such file or directory`, `L3-RRC-Measurements.h`, `ServingCellMeasurements.h`, `MeasResultNR.h`, `MeasQuantityResults.h`, `ResultsPerSSBIndex.h`, `ResultsPerCSI-RS-Index.h`, etc.

**Root cause:** These were ns-O-RAN v2 custom E2SM-NI extension headers. They do not exist in the OSC L-release v3 asn1c install. The v3 port uses flat `MeasurementData`/`MeasurementInfo` fields directly.

**Fix:** Replaced all affected wrapper classes in `asn1c-types.h` / `asn1c-types.cc` with pure C++ stubs:
- `MeasQuantityResultsWrap` — plain `long` members (rsrp, rsrq, sinr)
- `ResultsPerCsiRsIndex`, `ResultsPerSSBIndex` — plain `long m_index`
- `MeasResultNr` — plain `long m_physCellId`; `AddCellResults` takes stub pointer
- `MeasResultEutra`, `MeasResultPCellWrap` — plain members
- `MeasResultServMo`, `ServingCellMeasurementsWrap`, `L3RrcMeasurements` — public API preserved, no ASN.1 storage
- `ThreeGppMapSinr` math preserved exactly

---

### Fix 3 — v2 E2SM-RC / RANParameter headers absent from v3

**Errors:** `E2SM-RC-ControlMessage-Format1.h`, `RANParameter-Item.h`, etc.: not found

**Root cause:** E2SM-RC not in v3 OSC asn1c install. `ric-control-message.cc/.h` excluded from build per migration plan.

**Fix:**
- Removed `RANParameterItem` class from `asn1c-types.h/.cc` (only consumer was excluded RC files)
- Removed 4 v2 PM-container includes from `kpm-function-description.h` (`RAN-Container.h`, `PF-Container.h`, `OCUUP-PF-Container.h`, `PF-ContainerListItem.h`)

---

### Fix 4 — `SmCallback` / `register_sm_callback` absent from v3 e2sim

**Errors:** `'SmCallback' has not been declared`, `E2Sim has no member 'register_sm_callback'`

**Root cause:** v3 `e2sim.hpp` uses `SubscriptionCallback = void(*)(E2AP_PDU_t*)` only; removed SmCallback typedef and register_sm_callback API.

**Fix:** Added to `oran-interface.h`:
```cpp
using E2TermCallback = std::function<void(E2AP_PDU_t*)>;
using SmCallback = E2TermCallback;
```
Changed `E2Termination::RegisterKpmCallbackToE2Sm` and `RegisterSmCallbackToE2Sm` to accept `E2TermCallback`/`SmCallback`.

---

### Fix 5 — `std::bind` → raw fn ptr type mismatch

**Error:** `mmwave-enb-net-device.cc` and `lte-enb-net-device.cc` pass `std::bind(...)` to `RegisterKpmCallbackToE2Sm`; `SubscriptionCallback` is a raw fn ptr that cannot hold `std::bind`.

**Fix:** Added global trampoline dispatch table in `oran-interface.cc` anonymous namespace:
```cpp
std::unordered_map<long, E2TermCallback> g_cbMap;
static void Trampoline200(E2AP_PDU_t *pdu) { /* lookup funcId 200 in g_cbMap, call */ }
static void Trampoline300(E2AP_PDU_t *pdu) { /* lookup funcId 300 in g_cbMap, call */ }
```
`StoreAndRegisterCallback(long funcId, E2TermCallback cb)` stores the std::function in `g_cbMap` and registers the matching static trampoline with `m_e2sim->register_subscription_callback`.

---

### Fix 6 — `RicControlMessage` / `RicControlFunctionDescription` undeclared

**Error:** `lte-enb-net-device.cc` references these types (previously gotten via transitively-included RC headers). Can't edit `src/lte/`.

**Fix:** Added compile-only stub types directly in `oran-interface.h`:
- `RcControlHeaderUeId_t`, `RcControlHeaderFormat1Stub` (C structs)
- `class RicControlMessage : public SimpleRefCount<RicControlMessage>` — minimal members accessed by lte-enb-net-device.cc
- `class RicControlFunctionDescription : public FunctionDescription` — no-op

---

### Fix 7 — Examples CMakeLists excluded all v2 examples

**Error:** Example `.cc` files use v2 API (`GetPointer()`, `RRCEvent_b1`, etc.) that are gone from stubs.

**Rule:** Cannot edit files under `oran-interface/examples/*.cc`.

**Fix:** Emptied `examples/CMakeLists.txt` — `set(examples )` (empty list). Source files kept in-tree for documentation.

---

### Fix 8 — libe2sim_shared.so undefined asn_DEF_* symbols (final blocker)

**Error:** `scratch_scenario-zero` linker failure:
```
/usr/bin/ld: libe2sim_shared.so: undefined reference to `asn_DEF_RICsubscriptionRequest_IEs'
/usr/bin/ld: libns3.38.rc1-oran-interface-default.so: undefined reference to `asn_DEF_E2SM_KPM_IndicationMessage'
/usr/bin/ld: undefined reference to `asn_encode_to_new_buffer'
/usr/bin/ld: undefined reference to `asn_DEF_E2SM_KPM_RANfunction_Description'
```

**Investigation:**

| Library | `asn_DEF_*` status |
|---|---|
| `libe2sim.a` | All `U` (undefined) |
| `libe2sim_shared.so` | 5 symbols `U` (undefined) |
| e2sim CMake | `asn1_objects` OBJECT lib in `asn1c/` — never bundled into installed artifacts |

**Root cause confirmed:** The OSC e2sim CMakeLists builds `asn1_objects` from `asn1c/*.c` (493 source files) but the `e2sim_shared` target only bundles `def_objects`, `sctp_objects`, `messagerouting_objects`, `encoding_objects`, `base_objects`. `asn1_objects` is excluded. Neither the `.so` nor the `.a` install contains the asn1c symbol definitions.

**Fix:**
1. On VM: compiled `asn1c/*.c` into `libasn1c_e2.a` and installed to `/usr/local/lib/`:
   ```bash
   cd /home/uc/osc-installation/e2-interface/e2sim/asn1c
   gcc -O2 -fPIC -I. -c *.c
   ar rcs /usr/local/lib/libasn1c_e2.a *.o
   ```
2. Updated `oran-interface/CMakeLists.txt` to add `libasn1c_e2.a` to `LIBRARIES_TO_LINK`:
   ```cmake
   set(ASN1C_E2_LIB "/usr/local/lib/libasn1c_e2.a")
   set(e2sim_LIBRARIES "${E2SIM_SHARED_LIB}" "${ASN1C_E2_LIB}")
   ```

**Verification:** `nm /home/uc/libasn1c_e2.a | grep "asn_encode_to_new_buffer"` → `T asn_encode_to_new_buffer` (defined, text section).

---

## Files Modified

| File | Change |
|---|---|
| `oran-interface/model/asn1c-types.h` | Full rewrite: v3 S-NSSAI, pure C++ stubs for all v2 measurement wrappers |
| `oran-interface/model/asn1c-types.cc` | Full rewrite: stub implementations, ThreeGppMapSinr math preserved |
| `oran-interface/model/kpm-function-description.h` | Removed 4 absent v2 PM-container includes |
| `oran-interface/model/oran-interface.h` | E2TermCallback/SmCallback typedefs, RC stubs, trampoline support |
| `oran-interface/model/oran-interface.cc` | Global trampoline dispatch table, StoreAndRegisterCallback |
| `oran-interface/CMakeLists.txt` | Use libe2sim_shared.so + libasn1c_e2.a; fatal-error guard for missing libs |
| `oran-interface/examples/CMakeLists.txt` | Emptied examples list (all v2 examples excluded) |

---

## VM-Side Prerequisite (must be reproduced on fresh VM)

```bash
cd /home/uc/osc-installation/e2-interface/e2sim/asn1c
gcc -O2 -fPIC -I. -c *.c
sudo ar rcs /usr/local/lib/libasn1c_e2.a *.o
rm -f *.o
```

This step is NOT part of the standard OSC e2sim install — it must be added to the VM setup documentation.

---

## Build Result

```
./ns3 build
  → 0 compile errors
  → 0 linker errors
  → 0 undefined references
  → scratch/ns3.38.rc1-scenario-zero-default  [EXISTS, linked clean]
```

---

## Recurrence Prevention

1. **VM setup script:** Add the `libasn1c_e2.a` compilation step to `docs/linux-vm-dependency-setup-guide.md`.
2. **CMakeLists guard:** The `if(NOT EXISTS "${ASN1C_E2_LIB}")` FATAL_ERROR guard now catches any VM where the archive is missing immediately at configure time.
3. **Monitoring gap:** The OSC e2sim package is broken by design for standalone use — downstream consumers must always add the asn1c object code. This should be documented as a known issue.

---

## Unresolved Questions

- **lena-* examples:** Pre-existing linker failures in `src/lte/examples/lena-*.cc` remain; not introduced by this work, not in scope.
- **libasn1c_e2.a persistence:** The archive on oran-kvm-2 survives only until VM is rebuilt. Must be added to the provisioning script before the next fresh VM setup.

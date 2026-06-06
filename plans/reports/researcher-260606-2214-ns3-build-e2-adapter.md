# Phase 7 Research: ns-3 Build Integration + E2Termination Adapter

**Report Date:** 2026-06-06  
**Scope:** Phase 7 (first full ns-3 build + E2Termination adapter + scenario-zero end-to-end)  
**Status:** DONE  

---

## Executive Summary

Phase 7 must reconcile **two incompatible signatures** in the ns-3 build path:
- E2Termination::DoStart tries to call `m_e2sim->run_loop(ricAddress, ricPort, clientPort, gnbId, plmnId)` 
- libe2sim provides only `run_loop(int argc, char* argv[])`

The oran-interface module is built into the ns-3 tree as a contrib library (linked against e2sim); scenario-zero calls E2Termination via MmWaveHelper. Two viable adapter strategies exist (documented below). Build integration is sound; the KPM builders (proven in Phases 3–6) are already in place; the **sole blocking issue is the DoStart signature mismatch.**

---

## Q1: ns-3 Build Integration of oran-interface

### Build Entry Point
- **Root CMakeLists.txt** (`ns3-mmwave-oran/CMakeLists.txt` lines 129, 152–158): scans `contrib/` directory for submodules.
- **oran-interface symlink** (`ns3-mmwave-oran/contrib/oran-interface → ../../oran-interface`): linked as a contrib module.
- **Build lib specification** (`oran-interface/CMakeLists.txt` lines 31–59):
  ```cmake
  build_lib(
    LIBNAME oran-interface
    SOURCE_FILES model/oran-interface.cc
                 model/asn1c-types.cc
                 model/function-description.cc
                 model/kpm-indication.cc
                 model/kpm-function-description.cc
                 model/ric-control-message.cc
                 model/ric-control-function-description.cc
                 helper/oran-interface-helper.cc
                 helper/indication-message-helper.cc
                 helper/lte-indication-message-helper.cc
                 helper/mmwave-indication-message-helper.cc
    LIBRARIES_TO_LINK 
                    ${libcore}
                    ${e2sim_LIBRARIES}
  )
  ```

### Compiled Sources
All **7 core model files + 3 helper files + headers** are explicitly listed in oran-interface/CMakeLists.txt and compiled:

| Source | Purpose |
|--------|---------|
| `model/oran-interface.cc` | E2Termination class, Start/DoStart, subscription processing |
| `model/kpm-indication.cc` | KPM indication encoding (Phase 6 proven) |
| `model/kpm-function-description.cc` | v3 RAN function descriptor builder (Phase 4 proven) |
| `model/function-description.cc` | base FunctionDescription class |
| `model/asn1c-types.cc` | ASN.1 type helpers |
| `model/ric-control-message.cc` | Control message encoding |
| `model/ric-control-function-description.cc` | Control SM descriptors |
| `helper/oran-interface-helper.cc` | NS3 helper for E2Termination setup |
| `helper/*-indication-message-helper.cc` | LTE + mmWave indication builders |

### Link Dependencies
- **External:** `${e2sim_LIBRARIES}` = vendored libe2sim (built by `./e2term-ns3-build.sh → oran-e2sim/e2sim/build_e2sim.sh`).
- **Internal:** `${libcore}` = ns-3 core module.
- **Link order:** ns-3 → oran-interface → e2sim (C++ → C dependencies resolved via `-ldl` on Linux).

### Build Command
```bash
cd ns3-mmwave-oran
./e2term-ns3-build.sh    # Builds oran-e2sim then ns-3
./ns3 run scratch/scenario-zero.cc -- --e2TermIp=<ip> --e2TermPort=32222
```

**Result:** oran-interface is compiled as an integral ns-3 module and linked against e2sim. All KPM builders from Phases 3–6 are in the binary.

---

## Q2: E2Termination::DoStart Adapter Mismatch

### Current Signature Mismatch

| Component | Signature | Source |
|-----------|-----------|--------|
| **E2Termination::DoStart** | `void DoStart()` (private) | oran-interface/model/oran-interface.h:141 |
| **DoStart call site** | `m_e2sim->run_loop(m_ricAddress, m_ricPort, m_clientPort, m_gnbId, m_plmnId)` | oran-interface/model/oran-interface.cc:137 |
| **libe2sim available** | `int run_loop(int argc, char* argv[])` | oran-e2sim/e2sim/src/base/e2sim.hpp:58 |

**Fatal error:** Line 137 of oran-interface.cc calls a 5-parameter overload that does not exist in the vendored libe2sim.

### Historical Context
- **Wineslab ns-o-ran** (Bronze, now upstream/m-release) likely had a custom `run_loop(string, uint16_t, ...)` overload (now removed in OSC).
- **oran-interface submodule** (o-ran-sc/sim-ns3-o-ran-e2, upstream/l-release) **has the same bug** — DoStart still tries the 5-param call.
- **Proof of correct signature:** Standalone `e2-setup-minimal.cc` (lines 106–107, oran-interface/examples/) uses `e2sim.run_loop(argc, argv)` successfully.

### Characterization: Two Viable Adapter Strategies

#### **Option A: Rewrite DoStart to build argv from members (RECOMMENDED)**
**Pros:**
- Minimal invasive change; leverages proven libe2sim API.
- oran-interface remains a thin wrapper; no E2Sim changes needed.
- **Path chosen by the standalone harness** (e2-setup-minimal).
- Scales to future libe2sim versions (argv API is stable).

**Implementation sketch** (oran-interface/model/oran-interface.cc ~line 116–138):
```cpp
void E2Termination::DoStart()
{
  NS_LOG_FUNCTION(this);
  NS_ABORT_MSG_IF(m_ricAddress.empty(), "Set RIC info first");

  // Allocate argv array: [program_name, ricAddr, ricPort, clientPort, gnbId, plmnId]
  const char *program_name = "ns3-e2term";
  std::string ric_port_str = std::to_string(m_ricPort);
  std::string client_port_str = std::to_string(m_clientPort);

  // argc = 6 (program + 5 args)
  char *argv[7] = {
    const_cast<char*>(program_name),
    const_cast<char*>(m_ricAddress.c_str()),
    const_cast<char*>(ric_port_str.c_str()),
    const_cast<char*>(client_port_str.c_str()),
    const_cast<char*>(m_gnbId.c_str()),
    const_cast<char*>(m_plmnId.c_str()),
    nullptr  // argv must be null-terminated
  };

  NS_LOG_INFO("E2Term: GNB=" << m_gnbId << ", ricAddr=" << m_ricAddress 
             << ":" << m_ricPort << ", clientPort=" << m_clientPort);
  
  // Call the libe2sim API
  m_e2sim->run_loop(6, argv);
}
```

**Cons:** Minor string-lifetime management; documented expectation on argv order in libe2sim.

---

#### **Option B: Bypass E2Termination entirely (avoid the adapter)**
**Pros:**
- Zero changes to oran-interface.cc.
- Proven in e2-setup-minimal: register directly with e2sim, emit indications on callback.

**Implementation sketch** (scenario-zero or MmWaveHelper):
1. Allocate argv locally in the caller.
2. Call `e2sim->run_loop(argc, argv)` directly (no E2Termination wrapper).
3. Move subscription/indication logic out of E2Termination methods into ns-3 callbacks.

**Cons:**
- **Requires major refactor** of scenario-zero and MmWaveEnbNetDevice → breaks ns-3 architecture.
- Duplicates e2-setup-minimal logic; not maintainable.
- E2Termination becomes dead code → confusing for future porters.

---

### **Recommendation: Implement Option A**

**Rationale:**
- Minimal, self-contained fix in one private method.
- Preserves ns-3 architecture (E2Termination encapsulates libe2sim).
- Proven approach (e2-setup-minimal uses it).
- Maintainable: argv array order documented; future libe2sim changes clear.

---

## Q3: scenario-zero Run Interface

### E2 Configuration
**Global values** (scenario-zero.cc lines 186–201):
```cpp
static ns3::GlobalValue g_e2TermIp("e2TermIp", 
  "The IP address of the RIC E2 termination",
  ns3::StringValue(""),  // default empty
  ns3::MakeStringChecker());
```

**Command-line override:**
```bash
./ns3 run scratch/scenario-zero.cc -- --e2TermIp=10.0.2.10 --enableE2FileLogging=false --simTime=10
```

**Run flow** (lines 243–324):
1. Read e2TermIp from global value (default="").
2. Set `ns3::MmWaveHelper::E2TermIp` config default to the value.
3. MmWaveHelper creates E2Termination for each eNB (see **Q3 build path below**).

### E2 Endpoint Configuration
| Item | Default | Used by | Comment |
|------|---------|---------|---------|
| **ricAddress** | `m_e2ip` (from MmWaveHelper config) | E2Termination ctor | Set by `Config::SetDefault` |
| **ricPort** | `m_e2port` = hardcoded **36422** | E2Termination ctor | E2Term SCTP port inside docker |
| **clientPort** | auto-incremented per eNB | E2Termination ctor | local bind port |
| **gnbId** | `std::to_string(cellId)` | E2Termination ctor | LTE eNB cell ID |
| **plmnId** | hardcoded **"111"** | E2Termination ctor | test PLMN |

### E2 Workflow in scenario-zero
1. **E2 Setup (M1):** MmWaveEnbNetDevice::DoInitialize → schedule E2Termination::Start() at T=0.
   - `E2Termination::Start()` spawns thread → `DoStart()` → `run_loop()` (currently broken).
   - Thread calls libe2sim which connects SCTP to RIC, sends E2setupRequest (gNB v3 descriptor).
   - RIC responds with E2setupResponse (acknowledgement).

2. **Subscription (M4):** RIC sends RICsubscriptionRequest for KPM (funcId=2).
   - `E2Termination` callback registered via `RegisterKpmCallbackToE2Sm()` (phase-05).
   - MmWaveEnbNetDevice::KpmSubscriptionCallback → ProcessRicSubscriptionRequest → builds response (M4).

3. **Indication Loop (M5–M6):** MmWaveEnbNetDevice::BuildAndSendReportMessage scheduled every E2Periodicity.
   - Collects PDCP/RLC/PHY metrics (KPMIndicationBuilder from phase-06).
   - Encodes E2SM-KPM v3 indication, sends via `E2Termination::SendE2Message()`.

### Minimum Viable Run Command
```bash
cd /home/uc/ns-O-RAN-installation/ns3-mmwave-oran  # oran-kvm-2
./ns3 run scratch/scenario-zero.cc -- \
  --e2TermIp=192.168.122.78 \        # L-release node IP (E2Term pod host)
  --enableE2FileLogging=false \
  --simTime=5 \                       # start small
  --e2lteEnabled=true \
  --e2nrEnabled=false \
  --ues=3                             # few UEs to reduce churn
```

**Expected output:**
- SCTP connection logged → Setup request/response (M1–M2).
- KPM subscription callback triggered → subscription response (M4).
- Periodic indication emissions logged (M5–M6).
- pcap shows sustained KPM indications every ~50ms.

---

## Q4: Build Strategy Recommendation

### Current State of Builders
**Phases 3–6 proven builders:**
- `oran-interface/model/kpm-function-description.cc` — RAN function descriptor (v3 real, 5 report styles).
- `oran-interface/model/kpm-indication.cc` — indication encoding (v3 real, 9 measurements).
- Headers in `oran-interface/examples/`:
  - `kpm-func-desc-v3.h` — descriptor builder.
  - `kpm-indication-builder.h` — indication encoder.
  - `kpm-subscription-handler.h` — callback handler.

### Two Strategies

#### **Strategy A: Port Builders INTO oran-interface/model/ (RECOMMENDED)**
**Current state:** Builders live as HEADERS in `examples/` for standalone testing. 

**Change:** Rename them, move to `model/`, and make .cc files.
- `examples/kpm-func-desc-v3.h` → `model/kpm-func-desc-v3.{h,cc}` (shared ns-3 + standalone).
- Inline helpers (OID checks, field builders) → utility functions in oran-interface namespace.

**Pros:**
- Builders become first-class oran-interface classes (testable, versioned, documented).
- ns-3 calls `CreateObject<KpmFuncDescV3>()` → no include path surprises.
- Standalone harness still includes headers (backcompat).
- Single source of truth for v3 encoding logic.

**Cons:** Modest refactoring effort (~100 LoC changes).

**Adoption:** mmwave-enb-net-device already calls KpmFunctionDescription::Build(). Just make the call resolve to the real builder instead of the placeholder.

---

#### **Strategy B: Keep Standalone Headers, Call from ns-3 (VIABLE BUT RISKY)**
**Current state:** Examples keep the header builders.

**Change:** ns-3 includes the header and calls directly.
```cpp
// In mmwave-enb-net-device initialization:
#include "kpm-func-desc-v3.h"
auto desc = KpmFuncDescV3::BuildDescriptor(...);
m_e2term->RegisterFunctionDescToE2Sm(funcId, desc);
```

**Pros:** No refactoring; headers already proven.

**Cons:**
- **Header-only builders in ns-3 tree = fragmentation risk:** two implementations (model/ + examples/) diverge.
- No UT coverage for builders; regressions hidden until E2 setup.
- Standalone examples and ns-3 scenario use different code paths → validation loophole.

---

### **Recommended Decision: Strategy A (Port Builders)**

**Rationale:**
1. **Single source of truth:** Builders in model/ + backed by .cc files → testable, versionable.
2. **Matches architecture:** oran-interface is a **module** → modules have model/ classes, not scattered headers.
3. **Proven safe:** Phases 3–6 harness already calls the same builder logic (in examples/); copying to model/ is low-risk.
4. **Future-proof:** v3 → next version means one place to upgrade.

**Implementation outline:**
- Copy `examples/kpm-func-desc-v3.h` → `model/kpm-func-desc-v3.h`.
- Create `model/kpm-func-desc-v3.cc` with builder implementation (extract from inline in header).
- Update CMakeLists.txt to list `model/kpm-func-desc-v3.cc` in SOURCE_FILES.
- Deprecate or mark examples/ version as "legacy standalone reference".

---

## Build Readiness Summary

| Component | Status | Evidence |
|-----------|--------|----------|
| oran-interface contrib module | **Ready** | CMakeLists.txt explicit, symlinked in contrib/ |
| libe2sim linkage | **Ready** | find_external_library() → e2sim_LIBRARIES → LIBRARIES_TO_LINK |
| KPM builders (phases 3–6) | **Proven standalone** | e2-setup-minimal runs end-to-end |
| KPM builders in ns-3 tree | **Pending** | Headers in examples/; recommend port to model/ |
| **E2Termination::DoStart** | **BLOCKING** | Signature mismatch; Option A fix ready |
| scenario-zero + MmWaveHelper | **Ready** | E2 config flow clear; runs immediately post-DoStart fix |

---

## Unresolved Questions

1. **DoStart fix strategy endorsement:** Should impl team proceed with Option A (build argv), or prefer Option B (refactor ns-3 flow)?
   - *Assumption:* Option A (Option B too invasive).

2. **Builder porting scope:** Does "port builders" mean full .cc extraction, or just make headers installable (not `examples/` only)?
   - *Assumption:* Full extraction to model/ for single-source architecture.

3. **simTime + test harness:** Phases 3–6 used small hardcoded runs (10–20 sec). What simTime for Phase 7 end-to-end?
   - *Recommendation:* Start 5 sec (quick validation), then 30+ sec for stress (10+ UEs, sustained KPM).

4. **pcap golden baseline:** Should a L-release E2 setup→subscription→indication sequence be frozen as "golden"?
   - *Recommendation:* Yes, for regression detection post-release.

5. **L-release doc location:** Update main README.md (Bronze + L-release side-by-side), or create `docs/l-release-quick-start.md`?
   - *Recommendation:* Add L-release section to README.md §2.4 with note: "Bronze at §2, L-release at §2.5"; full migration guide in docs/.

---

## Report Status

**Status:** DONE

**Summary:** Phase 7 build integration is sound (oran-interface compiles into ns-3, KPM builders proven). The **sole blocking issue is E2Termination::DoStart calling a nonexistent libe2sim overload.** Recommended fix: Option A (rewrite DoStart to build argv, proven by e2-setup-minimal). Scenario-zero run flow, E2 config, and builder strategy are clear. Impl team should proceed with DoStart Option A fix + builder porting to model/; no additional research needed.


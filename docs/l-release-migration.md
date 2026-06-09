# L-release Migration: Bronze → OSC Near-RT RIC

**Status**: Complete (Phase 7 live M1–M6 all green). Branch: `dev/l-release` on all forks.

---

## Overview

ns-O-RAN migrated from **Bronze** RIC (E2AP v01.00, E2SM-KPM v02.00.03) to **OSC L-release** (E2AP v03.01, E2SM-KPM v03.00). This document summarizes the migration scope, code changes, and key decisions.

| Aspect | Bronze | L-release |
|--------|--------|-----------|
| E2AP version | v01.00 | **v03.01** |
| E2SM-KPM version | v02.00.03 | **v03.00** |
| e2sim | wineslab v1.0 (2209995) | OSC da6f82f2 |
| e2term | Docker 10.0.2.10:36422 | k8s ricplt, POD IP 10.244.0.48:36422 |
| TimeStamp encoding | 4 bytes | **8 bytes** (APER htobe64) |
| KPM RAN func ID | 200 | **2** (kpimon-go hardcoded) |
| KPM model | Nested PM-containers | **Flat MeasurementData/MeasurementInfoList** |

---

## Code Changes

### oran-e2sim (branch dev/l-release)

**Rebase**: OSC `e2-interface` `da6f82f2` wholesale rebase. Two key enhancements:

1. **SCTP source-port per-instance** (`e2sim_sctp.{hpp,cpp}`, `e2sim.hpp`):
   - Vendored e2sim hardcoded source port 36422 → all instances collide on bind → `EADDRNOTAVAIL` crash on 2nd+ gNB.
   - Fix: Added `set_client_src_port(uint16_t)` + `sctp_start_client(..., src_port)` param (0 = auto-bind).
   - ns-3 per-gNB port computation now flows to e2sim.

2. **ASN.1 header install** (setup guide):
   - OSC distribution omits `asn_DEF_*` symbols in compiled libraries.
   - Must build separate `libasn1c_e2.a` from `e2sim/asn1c/*.c` and link after libe2sim.
   - Documented in `docs/linux-vm-dependency-setup-guide.md`.

### oran-interface (branch dev/l-release)

**Adapter layer** (public `E2Termination` API unchanged):

1. **DoStart** (`model/oran-interface.cc`):
   - `run_loop(string, uint16_t, ...)` (wineslab) → `run_loop(int argc, char** argv)` (OSC).
   - Calls OSC library directly; argc>3 causes library exit(1).

2. **v3 KPM header** (`model/kpm-indication.cc`):
   - IndicationHeader-Format1: 8-byte `colletStartTime` (was 4 bytes).
   - Dropped v2 GlobalE2node_ID switch (absent in v3).

3. **v3 flat KPM message** (`model/kpm-indication.cc`):
   - v2 nested PM-container hierarchy deleted.
   - New flat `MeasurementData` array + `MeasurementInfoList` array (name ↔ value pairs).
   - `MeasurementItem` refactored (plain name/value holder, no v2 PM_Info_Item_t struct).
   - All `Add*PmItem` / `Fill*` helper signatures preserved → zero churn in ns-3.

4. **RAN function registration** (`model/oran-interface.cc`):
   - funcId 200 (Bronze) → **funcId 2** (kpimon-go hardcoded).
   - Callback trampoline: raw fn-ptr (OSC) vs std::bind (wineslab).
   - Added mutex-guarded `g_cbMap` + static trampolines for funcId 2/200/300.

5. **Descriptor** (`model/kpm-function-description.cc`):
   - v3 struct deltas absorbed: `ric_ReportStyle_Type` → fields unchanged; `+ric_ActionFormat_Type`; `+per-style measInfo_Action_List`.
   - Free-safety: per-style lists (safe) vs OSC shared list (shallow copy → multi-free hazard).

### ns3-mmwave-oran (branch dev/l-release)

**KPM pipeline v3 port** + **three live-run bug fixes**:

1. **v3 model port** (`src/mmwave/model/mmwave-enb-net-device.cc`, `src/lte/model/lte-enb-net-device.cc`):
   - funcId registration: 200 → **2** (two locations).
   - Header/message builders call v3 ASN.1 APIs (e.g., `IndicationHeader-Format1` vs v2 type).

2. **Memory contract fixes** (all in ns3 files; oran-e2sim/oran-interface unchanged):
   - **Bug 1: funcId mismatch** (M5 silent no-op):
     - ns-3 registered KPM under 200; kpimon-go subscribes funcId 2 (hardcoded).
     - Trampoline dispatch was 200-only → callback silently no-op'd for funcId 2.
     - Fix: Added case 2 to trampoline; changed registration call to funcId 2.
   
   - **Bug 2: SCTP source-port collision** (M1-M4 crash with EADDRNOTAVAIL):
     - e2sim per-instance source port wasn't wired from mmwave-helper.
     - Fix: `set_client_src_port()` call in `oran-interface::DoStart()` before agent start.
   
   - **Bug 3: PDU double-free** (M5 malloc crash "double free or corruption"):
     - e2sim's `e2ap_asn1c_encode_pdu()` frees the PDU after encode.
     - Prior session fixed model leak but ns-3 also called `delete pdu_*` → double-free.
     - Fix: Removed ns-3 delete calls (5 sites); changed `new E2AP_PDU` → `calloc()` to match e2sim contract.

3. **Reduced-PM mode** (M6 metric count parity):
   - v3 flat model merges cell + per-UE items into one array.
   - Descriptor advertises 5 cell-only metric names.
   - kpimon gate: `no_of_cell_metrics == descriptor count`.
   - Fix: Guard `AddDuUePmItem` with `&& !m_reducedPmValues` (cell-only when reduced mode on).

4. **Build infrastructure**:
   - E2SM-RC excluded (no v3 asn1c types; KPM-only scope).
   - Compile stubs for RC callbacks (lte/mmwave code references them; safe on KPM path).
   - Callback trampoline: raw fn-ptr dispatch (vs wineslab std::bind).

---

## Validation Milestones (M1–M6)

All green; evidence in `scripts/l-release-validation/captures/`:

| # | Milestone | Assertion | Evidence |
|---|-----------|-----------|----------|
| M1 | SCTP INIT | 5 associations (1 per gNB + harness) | pcap SCTP frames |
| M2 | E2 Setup | Setup request+response, no rejects | `phase7-m1m3-scenario-zero.pcap` |
| M3 | RAN functions | KPM funcId 2 accepted | E2setupResponse IE / OID123 present |
| M4 | Subscription | kpimon-go admits action | `phase7-m4m6-scenario-zero.pcap` RICsubscriptionResponse |
| M5 | Indication (structure) | 231 RICindication frames decoded v3 Format1 | `phase7-m5m6-scenario-zero.pcap` IndicationHeader/Message-Format1 |
| M6 | Indication (metric parse) | kpimon parses 5 cell metrics → InfluxDB write | kpimon log + InfluxDB metrics written |

**Harness**: `scripts/l-release-validation/assert-pcap.sh` validates byte signatures (E2AP procedure codes, KPM OID, v3 structure markers).

---

## Design Decisions

### funcId = 2 (kpimon-go compatible)

Bronze used 200 (arbitrary); L-release kpimon-go hardcodes funcId 2 in `control/control.go`. Trade-off: funcId is now tied to the xApp. Future xApps may need funcId 3/4/etc. → Consider callback registry for next phase.

### Cell-only reduced-PM (M6 metric count)

v3 flat model can emit cell + per-UE items in one array. Descriptor advertises 5 cell names only (kpimon gate rejects mismatched counts). Per-UE reporting still works in non-reduced mode (future xApp work). Reduced-PM = cell-style only (Phase 7 live).

### Separate libasn1c_e2.a

OSC e2sim CMake exports only headers; compiled ASN.1 objects are in an `OBJECT` library not bundled into libe2sim. Must build and install separately. Documented in setup guide.

### Cross-version interop: ns-3 KPM v03.00 ↔ deployed kpimon-go v2.0

The deployed kpimon-go decodes with **E2SM-KPM v2.0** (`kpm2_0.asn`), not v3. Root-caused on captured bytes (M1, `plans/260609-0127-rc-path-and-xapp-deploy-observe/reports/phase1-kpm-version-rootcause.md`). **Verdict = SPLIT:**

- **IndicationMessage Format1 (the metrics) is genuinely byte-compatible** v2.0↔v03.00 — Format1 + whole MeasurementData/Info family identical (only v3 additions are post-extension-marker optionals never sent). Verified: real captured 194B v3 message → v2 decoder = `RC_OK`, full consume, exact values. This is **by ASN.1 design**, not luck — safe to rely on.
- **IndicationHeader does NOT decode under v2** (`TimeStamp` 4→8 bytes + always-present sender strings ⇒ `RC_WMORE`). It is harmless: `wrapper.c` returns the partial struct on RC_WMORE, asn1c sets `present=Format1` pre-failure, and `control.go` never reads header content (uses its own ingest timestamp). The Phase-0 "Indication Header format=1" log was this salvaged partial, not a successful decode.
- **Implication:** keeping ns-3 at v03.00 is safe for KPM monitoring. The header mismatch is a **latent risk** only if a future xApp parses the indication header. No rollback warranted.

---

## Phase 2 — Version Decision Gate (M2, 2026-06-10)

Decision gate following Phase-0 capture (M0) + Phase-1 root-cause (M1). **Outcome: keep ns-3 at E2SM-KPM v03.00; both carried debts documented and deferred (no code change this phase).**

### Decision 1 — KEEP KPM v03.00 (no rollback to v2.0)

Rationale (on Phase-1 SPLIT verdict, ground-truth bytes):
- **Monitoring payload is genuinely compatible.** IndicationMessage Format1 + whole MeasurementData/Info family byte-identical v2.0↔v03.00 (v3-only fields are post-extension-marker optionals, never sent). Captured 194 B v3 message → deployed v2.0 decoder = `RC_OK`, exact values → InfluxDB. Compatible **by ASN.1 design**, not luck.
- **Header mismatch is inert.** v2 `TimeStamp SIZE(4)` vs v3 `SIZE(8)` ⇒ `RC_WMORE`, but `control.go` never reads header content (uses own ingest timestamp); failure silently salvaged. No live impact.
- **Rollback gains nothing + costs.** Would re-vendor v2 KPM asn (open-Q5), re-port the message model, and lose v3 alignment — while the RC work ahead is intrinsically v3 / RC-2.0. Header-truthfulness concern (open-Q6) is a *future* kpimon-go decoder upgrade, orthogonal to ns-3's emit version.

**Verdict:** ns-3 stays v03.00. Revisit only if a future xApp must parse the KPM indication header (→ upgrade kpimon-go decoder to v03.00, not roll ns-3 back).

### Decision 2 — NodePort connect debt → arg-override + scripted pod-IP discovery (no source edit)

Phase-0 reframed the original "replace `mmwave-helper.cc:~300` hardcode" debt:
- **NodePort SCTP is non-viable with stock kube-proxy.** Handshake succeeds then `Connection reset by peer` → ns-3 SIGSEGV (kube-proxy DNATs INIT but e2term pod return path bypasses the NodePort VIP). Evidence: `phase0-kpm-*-nodeport-attempt.pcapng`.
- **pod-IP `<e2term-pod-IP>:36422` is the working sustained path.** The `mmwave-helper.cc:300` value is only a *default* — fully overridable at runtime: `--e2TermIp=<ip>` (GlobalValue) + `--ns3::MmWaveHelper::E2Port=<port>` (attribute name is `E2Port`). **No source edit required.**

**Resolution:** keep arg-override as the connect mechanism; close the "durable connect" gap with **scripted pod-IP discovery** at run time (cheapest, robust):

```bash
E2TERM_IP=$(kubectl -n ricplt get pod -l app=ricplt-e2term-alpha \
  -o jsonpath='{.items[0].status.podIP}')
./ns3 run "scratch/scenario-zero --e2TermIp=$E2TERM_IP --simTime=100 ..."
```

A stable e2term ClusterIP / MetalLB LoadBalancer / hostNetwork e2term remains a *future* option if a fixed address is later justified; **deferred** (not needed for RC phases).

### Decision 3 — Dummy `OID123` debt → keep for KPM; introduce real OIDs at Phase-4 RC registration

- KPM subscription routing keys on **funcId 2**, not OID; e2term 6.x does **not** hard-validate the advertised OID (Phase-0: `OID123` accepted ×22). No functional need to change it for KPM.
- The **golden validation harness asserts `OID123`** (`scripts/l-release-validation/assert-pcap.sh:113`, `manifest.txt:39`). Changing it now breaks golden parity for zero gain.
- Code already pre-scoped this: `kpm-function-description.cc:131` — *"OID123 kept to match the L-release golden (Phase-4 OID decision)."*

**Resolution:** keep `OID123` for the KPM RANfunction now. **Phase 4** (RC receive+ACK) introduces real, distinct OIDs when advertising the RC RANfunction — that is where funcId/OID-keyed dispatch genuinely needs them. Canonical E2SM-KPM v03.00 RANfunction OID for the eventual switch: `1.3.6.1.4.1.53148.1.2.2.2` (confirm against deployed kpimon-go at Phase 4; module-OID base `…53148 e2(1) version3(3) e2sm(2)` per `e2sm-kpm-v03.00.asn`).

**Exit M2:** decision recorded here. No code/build/validation change this phase. Next: Phase 3 — add `e2sm-rc-2.0.asn` to ns-3 e2sim, regenerate via asn1c, round-trip.

---

## Known Limitations & Follow-up Work

1. **S-NSSAI SD encoding**: Currently ASCII "100" (3 bytes). Live kpimon accepted it; spec validation pending.
2. **Per-UE KPM**: Currently suppressed in reduced-PM mode. Full per-UE descriptor requires xApp request.
3. **Valgrind under load**: PDU double-free fix verified on 231 indication frames (one session). Long-running sustained test would be gold (VM valgrind not available).
4. **Callback trampoline generalization**: funcId 2 hardcoded. Next xApp may need funcId 3/4/etc. → Consider callback registry or configurable funcId.

---

## Reproducibility

**Build order** (critical; do not skip):

1. `oran-e2sim`: cmake + make e2sim_shared + sudo make install + ldconfig
2. `oran-e2sim/e2sim/asn1c`: gcc + ar (build libasn1c_e2.a) + sudo cp to /usr/local/lib
3. `oran-e2sim`: sudo cp e2sim.hpp to /usr/local/include/e2sim (manual install)
4. `ns-3-mmwave-oran`: ./ns3 build

**Run**:

```bash
./ns3 run "scratch/scenario-zero \
  --enableE2FileLogging=false \
  --e2TermIp=10.244.0.48 \
  --simTime=20 \
  --reducedPmValues=1 \
  --e2du=1 \
  --e2cuUp=0 \
  --e2cuCp=0"
```

**Choreography**:

1. Clear RNIB: `curl -X PUT http://<e2mgr>:3800/v1/nodeb/shutdown`
2. Start ns-3 (above run command)
3. Wait ~10s for SCTP handshake + E2 Setup
4. Restart kpimon-go pod (force RNIB scan + subscription)
5. Wait ~60s total for indication flow + InfluxDB write

---

## Git History

- Branch: `dev/l-release` (all forks: oran-e2sim, oran-interface, ns3-mmwave-oran)
- Superproject pins: latest dev/l-release commits on each fork
- Commits: Clean history (no merge commits; feature-branch approach)
- Submodule vendoring: `git read-tree --prefix=` (preserves commit history integrity)

---

## References

- **Plan**: `plans/260606-0505-port-ns-o-ran-to-l-release/plan.md`
- **Phase 7 live report**: `docs/journals/2026-06-07-phase7-live-m1-m6-end-to-end.md`
- **KPM model report**: `docs/journals/2026-06-07-phase7-v3-kpm-model-port.md`
- **Validation harness**: `scripts/l-release-validation/`
- **OSC e2-interface**: `https://gerrit.o-ran-sc.org/gitweb?p=sim/e2-interface.git` (commit da6f82f2)

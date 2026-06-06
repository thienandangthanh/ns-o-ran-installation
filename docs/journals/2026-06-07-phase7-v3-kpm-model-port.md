# Phase 7: Real ns-3 KPM Model Port to v3 — Code Clean, Live Deferred

**Date**: 2026-06-07 00:17  
**Severity**: Medium (deferred issue) / High (payload correctness)  
**Component**: oran-interface E2SM-KPM v2→v3 port; ns-3 scenario-zero integration  
**Status**: Resolved (code-port); Live run blocked on funcId reconciliation  

---

## What Happened

Completed Phase 7's **code-port half** of the ns-O-RAN → OSC L-release migration. The real ns-3 KPM pipeline (not the dummy standalone builder) ported from v2 ASN.1 container model (nested PM-Containers/PF-Container/PerUE-PM-Item) to v3 flat MeasurementData/MeasurementInfoList. Achieved clean full ns-3 build on the VM for the first time against E2SM-KPM v3.00, validated with an offline structural proof. Deferred live RIC end-to-end run (M1–M6) to the next session pending funcId reconciliation.

**Scope delivered:**
- DoStart adapter (argc guard, e2sim callback trampoline)
- v3 IndicationHeader/Message port (8-byte colletStartTime; flat metric model)
- Descriptor reconciliation (advertised names match reduced-PM DU emit)
- Infra fix (libasn1c_e2.a separate archive — OSC e2sim doesn't bundle asn1c types)
- Code review (1 high leak fixed; M3 footgun made loud)
- Offline proof (38 B header + 192 B message, valid encode)

---

## The Brutal Truth

This session was a relief *and* a kick in the teeth. Relief: the real pipeline was already wired; the v2→v3 transition was structural but not novel (matched the `examples/` reference exactly). Kick: we discovered the OSC L-release bundle is incomplete *by design* — libe2sim doesn't ship asn1c-generated object code, just the forward headers. Without knowing that, a developer rebuilds the VM and linker fails with undefined `asn_DEF_*` symbols. We had to reverse-engineer the e2sim CMake tree and build a separate static archive (`libasn1c_e2.a`) from the source. That's now part of the VM setup guide.

The code-review leak (H1) was frustrating because it was a regression — the v2 original had explicit `ASN_STRUCT_FREE` calls that the port *dropped*. That means on the live periodic loop, every indication leaks the entire Format1 subtree (header + message). The 1-shot offline proof never surfaces it. Only the code-reviewer's side-by-side diff caught it.

---

## Technical Details

**v2→v3 structural delta:**
- v2: nested PM-containers (`PM-Containers-Item` → `PF-Container` → `PerUE-PM-Item` → `CUUPMeasurement-Container`/`ODU-PF-Container`)
- v3: flat `MeasurementData` (array of `MeasurementRecordItem` with choice: integer/real/no-value) + `MeasurementInfoList` (array of `MeasurementInfoItem` with measName string + label bits)
- **Payload:** Both emit the same 5 Du cell metrics (TB.TotNbrDlInitial.Qpsk/16Qam/64Qam, RRU.PrbUsedDl, DRB.MeanActiveUeDl); only the ASN.1 target type changed.

**Build surfaced latent issues:**
- `SNSSAI_t` → `S_NSSAI_t` (v3 asn1c rename; cascaded to header, struct, ASN_DEF_*)
- E2SM-RC headers entirely absent from v3 install (excluded from KPM-only migration; added compile stubs for lte-enb-net-device.cc)
- v2 L3-RRC/MeasResult wrappers (`RRCEvent.h`, `MeasResultNR.h`, `ServingCellMeasurements.h`) don't exist in v3; stubbed to plain C++ types (off the KPM path)
- **Critical:** `asn_DEF_*` symbols undefined at link time → debugger traced it: OSC `libe2sim.a` exports headers but not object code. Built `libasn1c_e2.a` from `e2sim/asn1c/*.c` and linked after the shared lib.

**DoStart adapter bug (caught by reading e2sim source):**
- Research sketch suggested `run_loop(argc=6, argv={prog, ricAddr, ricPort, clientPort, gnbId, plmnId, NULL})`
- **Actual behavior:** vendored `read_input_options` reads argv[1]=ip, argv[2]=port when `argc==3`, then `exit(1)` for argc>3. Had to revert to `run_loop(3, argv)` and confirm gnbId/plmnId come from the registered descriptor, clientPort from SCTP.

**Code-review H1 (memory leak, FIXED):**
- Port dropped v2's `ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationHeader_Format1, …)` after encode
- Same for message Format1
- Result: per-indication leak of the entire Format1 subtree (nested buffers, PrintableString, MeasurementRecord, InfoList)
- Unbounded growth on the periodic live report loop
- **Fix:** Restored both `ASN_STRUCT_FREE` calls after `Encode()` and on constraint-fail early-return paths; nulled the choice pointer to prevent double-free vs shell `delete`
- Also fixed latent UB: `m_buffer/m_size` were uninitialized → init to 0/null up-front (soft-fail return + dtor `free(m_buffer)` were UB)

**Offline proof vs live gap:**
- scenario-zero's offline/file-logging mode skips ASN.1 encode entirely (writes CSV), so it does NOT exercise the ported model path
- Had to write dedicated tiny proof (`kpm-v3-model-proof.cc`) that drives real `KpmIndicationMessage`/`KpmIndicationHeader` → confirmed 38 B header + 192 B message, valid encode, exit 0
- The leak would never surface in the offline proof; code-review found it

**Unresolved footgun (M3, made loud):**
- Callback trampoline hardcodes funcId **200** (KPM) and **300** (RC) in the dispatch switch
- Any other funcId silently no-ops; callback never invoked
- Phase-5/6 standalone proof used funcId **2** (because kpimon-go expects it)
- If live run needs funcId 2, must change both the `RegisterKpmCallbackToE2Sm(200, ...)` call AND add a `TrampolineN` case
- Made this loud (NS_LOG_WARN at registration), but not yet resolved pending live kpimon query

---

## What We Tried

1. **Path A: Extend Phase-6 dummy builder** — rejected. The real pipeline was already wired end-to-end; extending the dummy would be duplicate code.
2. **Path B: Rewrite from scratch** — rejected. The `examples/` v3 builders were proven correct; mirror them to de-risk.
3. **Path X (chosen):** Port the real `model/` pipeline by mirroring `examples/` shapes → v2 container code deleted, v3 flat model built, single source of truth.
4. **DoStart argc=6 sketch** — didn't work (e2sim exit(1)s). Read source, found argc==3 hard requirement, reverted.
5. **Linker undefined asn_DEF_* symbols** — tried linking just `libe2sim.a` (failed). Traced CMake tree, found `asn1c_objects` OBJECT library never exported. Built separate `libasn1c_e2.a`, updated link order.
6. **Offline proof only** — caught by code-review. Leak never surfaces in 1-shot run; added dedicated model proof driving real path.

---

## Root Cause Analysis

**Why the v2→v3 transition was harder than it looked:**

The v2 model was a nested hierarchy of C structs (PM-Containers → PF-Container → PerUE-PM-Item → ODU/CuUp/CuCp containers). The code built these step-by-step (`FillPmContainer` → `FillOCuUp` → `FillOCuCp` → `FillODu`), then passed them to the encoder. v3 flattened this entirely — no containers, just a flat array of records + a metadata array. The data itself (metrics as name-value pairs) was already abstracted by `MeasurementItem`, so the port reused that abstraction; only the ASN.1 target type changed. This alignment to `examples/` made it straightforward, but the devil was in the details:

- **Latent compile errors:** The ns-3 module had never compiled against v3 before. Every v2-ism (SNSSAI, L3-RRC wrappers, E2SM-RC includes) was baked in but never tested. The full build was the archaeological dig.
- **Infra gaps:** OSC's distribution of e2sim was incomplete by design (headers only, no object code). We had to reverse-engineer and build the missing piece. This is now in the VM setup guide, but a developer who skips that step is stuck with undefined references.
- **API contract risk:** The e2sim callback API changed from std::bind-compatible to raw fn-ptr. The research sketch didn't catch that; only reading the source did. The trampoline table was the fix.
- **Regression in the port:** Explicitly deleting two lines of v2 cleanup code (the ASN_STRUCT_FREE calls) meant the leak was introduced in this session. Code-review caught it, but only because they did a side-by-side diff with git history.

**Why the offline proof wasn't enough:**

The offline/file-logging mode is a debug feature that bypasses the ASN.1 encode entirely. It writes a CSV of metrics to disk, which is fast and safe but also a completely different code path. The leak (failure to free the Format1 subtree) only shows up when indications are periodically encoded and sent. A 1-shot standalone proof can't see that.

---

## Lessons Learned

1. **Reverse-engineer library contracts at the source, not from sketches.** The research suggested argc=6; the library source code hardcodes argc==3. Reading the code beat reading the sketch.
2. **Incomplete distributions are a gotcha.** OSC's e2sim ships headers but no object code. This isn't documented. It became a blocker until we reverse-engineered the CMake tree. **Action:** Document this in the infra guide and mention it in PR reviews when refactoring e2sim integration.
3. **Offline debug modes hide regressions.** The offline proof mode doesn't exercise the real code path. A leak or resource growth that happens on the periodic loop is invisible. **Action:** Always pair offline proofs with a live/periodic variant when refactoring encode paths, or mandate code review for memory cleanup.
4. **V2→V3 transitions are structural, not just renames.** The change from nested containers to flat arrays required more than search-and-replace. The `examples/` reference was gold because it was already proven for v3. **Action:** When porting major ASN.1 models, start by mirroring a proven reference, not by trying to mechanically adapt the old code.
5. **Trampoline dispatch tables are a footgun for configuration.** Hardcoding funcId 200/300 means the code silently fails if funcIds change. The NS_LOG_WARN helps, but it's reactive. **Action:** For the live run, reconcile the actual funcIds kpimon-go uses and either add cases or make funcId configurable.

---

## Next Steps

**Immediate (next session, live M1–M6 end-to-end):**
1. **funcId reconciliation (BLOCKER for M5/M6):** Query kpimon-go L-release for the funcId it subscribes KPM under. If ≠200, add a `TrampolineN` case in `oran-interface.cc` and change the `RegisterKpmCallbackToE2Sm` call.
2. **M2 descriptor/UE item parity:** The message appends UE items to the cell items in the same record/infoList. The descriptor only advertises 5 cell names. If the live report includes UE items, the count won't match kpimon's gate. Decide: suppress UE items for cell style, separate descriptor, or verify kpimon accepts the union.
3. **Live pcap + golden compare:** Run scenario-zero against L-release RIC, capture pcap, hand to a tshark 4.x host for authoritative E2SM-KPM decode, compare to the Phase-5/6 reference.
4. **Finalize docs/README:** L-release section in README, migration summary in `./docs/`, submodule pins (forks + super), finalize `implementation-notes.html`.

**After live run:**
- Valgrind memory profiling (if VM allows; currently not installed) to confirm H1 fix doesn't grow unbounded.
- Port E2SM-RC v2.0 for closed-loop control (xApps).

---

## Carried Open Questions

- **funcId mismatch:** ns-3 registers KPM under 200 (Bronze default); Phase-5/6 standalone proof used 2 (kpimon-go compatible). Live run will reveal if this is a real conflict or if they're in different contexts.
- **S-NSSAI SD encoding:** Copied as 3 ASCII bytes ("100") from the reference. Live kpimon may expect 3-byte BCD.
- **Cell-style descriptor coverage:** Does kpimon decoder require ALL emitted measNames to be advertised, or does it skip unknown names? (M2 — gates the UE item decision.)
- **Leak under load:** H1 fix unverified under sustained periodic reporting (valgrind not available on VM). Live run will confirm no growth.

---

**Status: Code-port DONE. Live run BLOCKED on funcId reconciliation. Branch ready for hand-off to live test phase.**

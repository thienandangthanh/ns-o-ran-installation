# Code Review — Phase 7 / M6 E2SM-KPM v2→v3 port (oran-interface)

Date: 2026-06-06 | Branch: dev/l-release | Reviewer: code-reviewer
Scope: oran-interface/ model/{kpm-indication,asn1c-types,oran-interface,kpm-function-description}.* + CMake
Build CLEAN, offline proof PASSES. Focus: correctness / memory-safety / maintainability.

## Verdict
Port is structurally sound and wire-shape matches the proven reference. One real
memory leak (High) regressed vs v2; rest are latent footguns for the deferred
live run. No critical encode-corrupting or security defect found.

---

## HIGH

### H1. Format1 subtree leaked on every header AND message encode
`model/kpm-indication.cc:82-91` (header ctor) and `:241-247` (message ctor).
- ctor does `new E2SM_KPM_IndicationHeader_t()` … `FillAndEncode…()` … `delete descriptor;`
- `delete descriptor` frees ONLY the outer C++-`new`'d shell. The inner
  `indicationHeader_Format1` / `indicationMessage_Format1` subtree is `calloc`'d
  inside FillAndEncode (kpm-indication.cc:125, :443) and its nested
  buf/PrintableString/MeasurementRecord/InfoList allocations are NEVER freed.
- **Regression**: v2 original explicitly freed it —
  `git show HEAD:model/kpm-indication.cc` line 200
  `ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationHeader_Format1, ind_header);`
  and line 478 for the message Format1. The port dropped both.
- Impact: leak per indication. KPM reports fire periodically for the whole sim →
  unbounded growth on the live ns-3 run (offline 1-shot proof won't surface it).
- Fix (header) — after `Encode(descriptor);` in FillAndEncodeKpmRicIndicationHeader,
  before returning:
  ```c
  ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationHeader_Format1, fmt);
  descriptor->indicationHeader_formats.choice.indicationHeader_Format1 = nullptr;
  ```
  Same for the message: free `fmt` via
  `ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationMessage_Format1, fmt);` after
  Encode() (and on the constraint-fail early-return path at :475 — free before
  `return`, else the soft-fail path leaks the whole tree too).
  NOTE the comment at kpm-indication.cc:178-182 claims "caller deletes … so no
  explicit free needed" — that reasoning is wrong (delete ≠ ASN_STRUCT_FREE);
  remove it.
- Alternative: stop `new`/`delete`ing the descriptor and ASN_STRUCT_FREE the whole
  descriptor by value, matching the reference's `ASN_STRUCT_FREE(asn_DEF_…, imsg)`
  pattern (kpm-indication-builder.h:286-287). Cleaner; but minimally, restore the
  two inner frees.

---

## MEDIUM

### M1. Negative metric wraps to huge unsigned in MeasurementRecordItem.integer
`model/kpm-indication.cc:397` `recItem->choice.integer = (unsigned long) item->GetIntValue();`
- v3 asn1c `integer` field is `unsigned long` (verified MeasurementRecordItem.h:38;
  ASN.1 INTEGER(0..). A negative `long` metric (GetIntValue returns signed long)
  becomes ~1.8e19 on the wire. Constraint check passes (value ≥0 after wrap), so
  it is silently wrong, not caught.
- Today's reduced-PM set (TB counts, PrbUsedDl, MeanActiveUeDl) are all ≥0, so
  no live impact NOW — but the AddItem<long> API accepts any signed value and a
  future metric (e.g. a power offset / delta) would corrupt silently.
- Fix: guard or route negatives to `real`:
  ```c
  long v = item->GetIntValue();
  if (v < 0) { recItem->present = MeasurementRecordItem_PR_real;
               recItem->choice.real = (double) v; }
  else       { recItem->present = MeasurementRecordItem_PR_integer;
               recItem->choice.integer = (unsigned long) v; }
  ```
  At minimum NS_LOG_WARN on `v < 0`.

### M2. Descriptor advertises cell metrics only; UE items emitted but not advertised
`kpm-function-description.cc` advertises 5 cell names; `FillAndEncodeKpmIndicationMessage`
(kpm-indication.cc:363-369) ALSO flattens `m_ueIndications` UE items into the same
record/infoList. So an indication can carry measNames absent from the RAN-function
descriptor. kpimon-go's gate is `len(advertised)==no_of_cell_metrics`; UE measNames
not in the descriptor may be dropped or rejected by the decoder on the live run.
- Not a memory/encode bug; flagged for the deferred live verification. The TODO at
  kpm-function-description.cc already notes CuUp/CuCp reconciliation — extend it to
  cover the UE-item names actually emitted, or gate UE-item emission until advertised.

### M3. Trampoline silently no-ops for any funcId other than 200/300
`model/oran-interface.cc:75-84` GetTrampoline switch → `TrampolineFallback` (no-op)
for any other ID. `StoreAndRegisterCallback` stores the std::function in g_cbMap
under the real id, but registers the FALLBACK trampoline with e2sim — so the stored
cb is never invoked. Subscriptions silently dropped, no error/log.
- Relevant to deferred live run: if kpimon-go subscribes KPM under a funcId != 200
  (it is configurable), indications stop with zero diagnostics.
- Fix: in TrampolineFallback, at least NS_LOG_WARN/abort; better, add a generic
  registration path or assert `funcId ∈ {200,300}` in StoreAndRegisterCallback so a
  mis-ID fails loudly at registration, not silently at dispatch.
  ```c
  static void TrampolineFallback(E2AP_PDU_t*) {
    fprintf(stderr,"[e2term] indication for unregistered funcId — dropped\n"); }
  ```

---

## LOW / INFORMATIONAL

### L1. Constraint-fail / encode-fail leaves m_size=0 — caller guard unverified
kpm-indication.cc:266-271 (Encode error) and :471-475 (soft constraint fail) both
return with m_buffer=NULL, m_size=0 — correct, non-fatal by design. BUT the actual
SendE2Message caller (mmwave-enb-net-device.cc, BuildRicIndication path) lives in the
external ns-3 mmwave tree, NOT in this repo, so I could not confirm it checks
`m_size>0` before wrapping/sending. If it does not, a 0-length buffer (or NULL
m_buffer) gets wrapped into a RICindication. ACTION: verify the caller guards
`msg->m_size > 0 && msg->m_buffer != nullptr` before
generate_e2apv1_indication_request_parameterized. (Unresolved — see questions.)

### L2. Stubbed L3-RRC/MeasResult wrappers — confirmed OFF the KPM encode path
asn1c-types.cc:191-417 stubs (MeasResultNr/Eutra, ServingCellMeasurements,
L3RrcMeasurements, etc.) hold only plain C++ members, no ASN.1. The only KPM-path
touchpoint is MeasurementItem::ValueType::RRC, which kpm-indication.cc:405-413 maps
to PR_noValue (+warn). No stub is reachable from the compiled cell/UE integer/real
encode path → stubbing cannot corrupt a live KPM encode. OK. (RRC items silently
become noValue on the wire — acceptable for M6, already logged.)

### L3. measName buf calloc(1, name.size()) — fine but fragile on empty name
kpm-indication.cc:335-338: if name were "" calloc(1,0) may return NULL and size=0
violates MeasurementTypeName SIZE(1..150) → caught by soft constraint check, not a
crash. All current names are non-empty constants. No change needed.

### L4. ODR — static libasn1c_e2.a + e2sim shared lib
CMake links libasn1c_e2.a statically (compiled from e2sim/asn1c/*.c). If the e2sim
runtime lib also embeds the same asn_DEF_* symbols, duplicate definitions could
arise. Build is CLEAN and runtime proof passes, so not materializing in practice
(link order comment at CMakeLists already addresses ordering). Informational only.

### L5. g_cbMap thread-safety — adequate, single-writer note
g_cbMtx guards both StoreAndRegisterCallback writes and Trampoline reads; the e2sim
read thread (DoStart→run_loop, oran-interface.cc:206, detached) dispatches under the
lock. Correct. Single-instance-per-funcId limit is documented (oran-interface.cc:50).
Caveat: the std::function is invoked WHILE holding g_cbMtx — if a callback re-enters
E2Termination registration it self-deadlocks. None do today; note for future.

---

## POSITIVE
- record[i]↔info[i] ordinal correspondence is guaranteed: both built in one loop
  over orderedItems with lockstep ASN_SEQUENCE_ADD (kpm-indication.cc:386-427),
  including noValue items — counts stay aligned. Solid.
- Shallow-copy-then-free-wrapper pattern (measRecord/measLabel/measData,
  kpm-indication.cc:319-330, 432-453) matches the reference exactly — no double
  free: only the wrapper struct is freed, nested array/pointers transferred.
- SST/SD/PLMNIdentity sizes verified against generated constraints
  (SST SIZE(1..1)=1B "1"; SD SIZE(3)="100"; PLMN SIZE(3)="747") — all pass.
- TimeStamp 8-byte width + htobe64 matches v3 OCTET STRING shape and reference.
- Encode error path downgraded NS_FATAL_ERROR→NS_LOG (message) so one bad report
  won't kill the node — good production hygiene.

---

## Unresolved questions
1. Does mmwave-enb-net-device.cc (external tree) guard `m_size>0`/non-NULL m_buffer
   before sending? (blocks L1 closure)
2. Live kpimon-go subscription funcId — is it pinned to 200? (M3 severity depends)
3. Are UE-level measNames meant to ride the same indication as cell metrics, or a
   separate report style? (M2)

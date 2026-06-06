# Phase 7 M6 — E2SM-KPM v2 → v3.00 Model Port Report

Date: 2026-06-06  
Branch: dev/migrate-to-l-release  
Status: DONE_WITH_CONCERNS (see Unresolved Questions)

---

## Files Modified

| File | Change |
|------|--------|
| `oran-interface/model/kpm-indication.h` | Stage B+C: full rewrite — v2 container types/methods removed, v3 header/message structs; all public caller APIs preserved |
| `oran-interface/model/kpm-indication.cc` | Stage B+C: full rewrite — v2 GlobalE2node_ID path replaced by v3 sender-strings+colletStartTime; v2 FillPm*/FillOCu*/FillODu removed; v3 flat Format1 builder added |
| `oran-interface/model/asn1c-types.h` | Stage C1: MeasurementItem refactored from PM_Info_Item_t-backed to plain C++ storage; PM-Info-Item.h include removed |
| `oran-interface/model/asn1c-types.cc` | Stage C1: MeasurementItem implementation replaced; v2 ASN.1 free calls removed |
| `oran-interface/model/kpm-function-description.cc` | Stage D: g_kpmPerfMeasurements updated to 5 reduced-PM Du cell names |

---

## v2 → v3 Type Mapping Table

| v2 type / field | v3 replacement | Notes |
|---|---|---|
| `PM_Info_Item_t` | removed — plain C++ in `MeasurementItem` | v3 uses MeasurementRecordItem + MeasurementInfoItem separately |
| `MeasurementValue_t` (valueInt/valueReal/valueRRC) | `MeasurementItem::ValueType` enum + member fields | RRC → PR_noValue + NS_LOG_WARN |
| `id_GlobalE2node_ID` (IndicationHeader-Format1 field) | removed — not in v3 Format1 | v3 has colletStartTime + sender strings only |
| `collectionStartTime` (v2 field name) | `colletStartTime` (v3 field name, note typo in spec) | 8-byte OCTET STRING; htobe64(m_timestamp) |
| `descriptor->present = E2SM_KPM_IndicationHeader_PR_*` | `descriptor->indicationHeader_formats.present = ...` | Outer wrapper renamed in v3 |
| `E2SM_KPM_IndicationMessage_PR_indicationMessage_Format1` | `E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format1` | Full enum name |
| `format->pm_Containers` / `PM_Containers_Item_t` | removed | v3 Format1 has no pm_Containers |
| `format->cellObjectID` | removed from ASN.1 encoding | CellObjectID not in v3 Format1 |
| `format->list_of_PM_Information` | `MeasurementInfoList_t *measInfoList` | Now a pointer OPTIONAL in Format1 |
| `format->list_of_matched_UEs` / `PerUE_PM_Item_t` | UE items appended into single MeasurementRecord | v3 Format1 is flat; per-UE identity lost in this encoding (see concerns) |
| `PF_Container_t`, `RAN_Container_t`, `OCUUP_PF_Container_t`, `OCUCP_PF_Container_t`, `ODU_PF_Container_t` | all removed from ASN.1 path | Container value classes retained as C++ holders for caller ABI |
| `MeasurementValue_PR_valueRRC` | `MeasurementRecordItem_PR_noValue` + NS_LOG_WARN | No v3 mapping; data is lost for RRC items |
| `GlobalE2node_gNB_ID_t`, `GlobalE2node_eNB_ID_t`, etc. | all removed | Not in v3 IndicationHeader-Format1 |

---

## MeasurementItem Refactor (C1)

**Before**: backed by `PM_Info_Item_t*` + `MeasurementValue_t*` + `MeasurementType_t*` (all v2 only).  
**After**: plain C++ members — `std::string m_name`, `ValueType` enum (Int/Real/RRC), `long m_valueInt`, `double m_valueReal`, `Ptr<L3RrcMeasurements> m_rrcValue`.

**Removed APIs** (were returning v2 types):
- `PM_Info_Item_t* GetPointer()`
- `PM_Info_Item_t GetValue()`

**Added APIs**:
- `std::string GetName() const`
- `ValueType GetValueType() const`
- `long GetIntValue() const`
- `double GetRealValue() const`
- `Ptr<L3RrcMeasurements> GetRrcValue() const`

Three public constructors `(name,long)`, `(name,double)`, `(name,Ptr<L3RrcMeasurements>)` unchanged — all `AddItem<T>()` call sites compile without modification.

Confirmed: no helper file calls `GetPointer()`/`GetValue()` on `MeasurementItem`; helpers only call `AddItem<T>()` and `GetItems()`.

---

## Record/InfoList Order Decision

Items are appended in this order (deterministic within one encode call):
1. Cell items from `m_cellMeasurementItems->GetItems()` in AddItem insertion order
2. UE items from each `MeasurementItemList` in `m_ueIndications` (set iteration order), then each list's items in AddItem order

`record[i] ↔ infoList[i]` is guaranteed because both are filled in the same single loop over `orderedItems`.

---

## Label Decision

Each `MeasurementInfoItem` carries a static `LabelInfoList` with:
- `PLMNIdentity_t`: "747" (3 ASCII bytes)
- `S_NSSAI.sST`: "1" (1 byte)
- `S_NSSAI.sD`:  "100" (3 bytes)

Rationale: mirrors `kpm_v3::BuildDummyIndicationMessage` exactly. Deriving PLMN from `m_pmContainerValues` would require type-checking the container and is deferred.

TODO(Phase7-live): derive PLMN from actual cell PLMN. Also verify whether SD should be 3 BCD bytes or ASCII — kpimon-go decoder may be lenient.

---

## Stage D — Emitted Names Found vs Descriptor Set

**AddDuCellPmItem reduced-PM emit** (always emitted, `m_reducedPmValues` ignored for these):
```
TB.TotNbrDlInitial.Qpsk   (macQpskCellSpecific)
TB.TotNbrDlInitial.16Qam  (mac16QamCellSpecific)
TB.TotNbrDlInitial.64Qam  (mac64QamCellSpecific)
RRU.PrbUsedDl             (ceil(prbUtilizationDl))
DRB.MeanActiveUeDl        (activeUeDl)
```

**Descriptor `g_kpmPerfMeasurements[]` set to** (same 5, same order):
```c
"TB.TotNbrDlInitial.Qpsk", "TB.TotNbrDlInitial.16Qam",
"TB.TotNbrDlInitial.64Qam", "RRU.PrbUsedDl", "DRB.MeanActiveUeDl"
```
`g_kpmNumberMeasurements = 5`.

Previous value was 9 RLC/L1M names unrelated to the Du reduced-PM cell emit.

---

## Constraint Handling (I1)

`asn_check_constraints` called before `Encode()` in `FillAndEncodeKpmIndicationMessage`.  
On failure: `NS_LOG_WARN` + early return (m_buffer/m_size stay 0).  
Callers that check `m_size > 0` before using the buffer are safe; callers that do not are at risk of sending a zero-length payload — flagged for VM build loop verification.

`Encode()` itself: converted from `NS_FATAL_ERROR` to `NS_LOG_ERROR + return` for robustness; documented in code comment.

IndicationHeader `Encode()`: kept `NS_FATAL_ERROR` (header encode failure is a programming error, not a data error; matches original convention).

---

## Items NOT Verified Without Compiling

1. **`MeasurementRecordItem.choice.integer` type**: header shows `unsigned long`. We cast `long GetIntValue()` to `unsigned long` at assignment — safe for non-negative values; negative metric values would wrap. Flag for VM review.

2. **`free(record)` after shallow-copy**: mirrors the reference exactly (`free(record)` after `dataItem->measRecord = *record`). The `list.array` pointer is now owned by `dataItem`. This is the same pattern as the reference; should be correct but cannot execute to verify.

3. **`free(lbl)` after shallow-copy into `lblItem->measLabel`**: same pattern as `kpm_v3::BuildDummyIndicationMessage`. Pointer members `plmnID`/`sliceID` in `lbl` are now owned by `lblItem->measLabel`. Verify no double-free on ASN_STRUCT_FREE of the outer message.

4. **`free(measData)` after `fmt->measData = *measData`**: `measData->list.array` owned by `fmt->measData` after shallow copy. Same pattern as reference.

5. **UE item identity loss**: UE IMSI (the `MeasurementItemList` ID) is no longer embedded in the v3 PDU. The v3 Format2/Format3 would be needed for per-UE identity. This is a known scope gap for M6 (cell-level focus); noted but not blocking.

6. **m_cellObjectId unused**: `KpmIndicationMessageValues.m_cellObjectId` is no longer written into the PDU (v3 Format1 has no CellObjectID field). Callers that set it still compile; the field is silently ignored. Document if kpimon-go needs it via a different IE.

7. **`asn_check_constraints` availability**: present in asn1c-0.9.29 (confirmed by reference file usage). Not a risk.

---

## Unresolved Questions

1. Are any negative `long` metric values expected? If so, `(unsigned long)` cast in `PR_integer` path needs a signed encoding workaround (use `PR_real` for negative integers or extend the range check).

2. Does kpimon-go expect the `MeasurementInfoItem.measType` to use `PR_measID` (integer index) or `PR_measName` (string)? The reference uses `PR_measID=1` for the dummy case. We use `PR_measName` with the actual metric name string for generality. Verify against live kpimon subscription decode log.

3. The `S-NSSAI.sD` field in the reference carries ASCII "100". Does live kpimon-go expect 3-byte BCD (0x00 0x00 0x00 for SD=0) instead? Needs live pcap verification.

4. `mmwave-enb-net-device.cc:BuildRicIndicationHeader` — confirm it passes a non-zero `m_timestamp` (current sim time in nanoseconds or similar). If it passes 0, the 8-byte colletStartTime will be all-zeros — valid wire shape but degenerate.

---

**Status:** DONE_WITH_CONCERNS  
**Summary:** All four stages (B/C/C1/D) implemented; v2 ASN.1 types fully replaced in kpm-indication.{h,cc} and asn1c-types.{h,cc}; descriptor aligned to 5 Du reduced-PM cell names. Concerns: unsigned-long cast for negative metrics, measType PR_measName vs PR_measID live parity, SD encoding, and UE identity loss in flat Format1 all require live VM verification.

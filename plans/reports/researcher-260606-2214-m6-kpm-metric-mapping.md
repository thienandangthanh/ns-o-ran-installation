# M6 Research: Real ns-3 KPM Metric Mapping for Phase 7

**Date:** 2026-06-06 | **Scope:** E2SM-KPM v3.00 metric bridge (ns-3 → kpimon-go named table population)

---

## Summary (TL;DR)

**Q1: kpimon-go expects 9 named metrics** (extracted from RAN function definition format1 via `buildRanCellUeKpi()`):
- `DRB.RlcSduTransmittedVolumeDL`, `DRB.RlcSduTransmittedVolumeUL`
- `DRB.PerDataVolumeDLDist.Bin`, `DRB.PerDataVolumeULDist.Bin`
- `DRB.RlcPacketDropRateDLDist`, `DRB.PacketLossRateULDist`
- `L1M.DL-SS-RSRP.SSB`, `L1M.DL-SS-SINR.SSB`, `L1M.UL-SRS-RSRP`

kpimon-go **populates `tmpCellKpi`** by parsing `measInfo_Action_List` from RAN function definition (format 1, ric_ActionFormat_Type=1). The conditional `if (no_of_cell_metrics != len(tmpCellKpi))` fails when the indication message doesn't match.

**Q2: ns-3 Bronze v2 collects diverse PM values** across three container types (DU/CU-CP/CU-UP), including TB counts, PRB usage, SINR bins, RLC buffers, PDCP throughput, etc. The **DU cell-level metrics** include 6 items (reduced PM mode):
- `TB.TotNbrDlInitial.Qpsk`, `TB.TotNbrDlInitial.16Qam`, `TB.TotNbrDlInitial.64Qam`
- `RRU.PrbUsedDl` (PRB utilization, continuous double → ceil to long)
- `DRB.MeanActiveUeDl` (active UE count)

**Q3: v3 builder minimal shape** (`kpm-indication-builder.h:BuildDummyIndicationMessage()`):
- One `MeasurementDataItem` with one `MeasurementRecordItem` (integer or float choice)
- One `MeasurementInfoList` with one `MeasurementInfoItem` per metric
- **Currently uses measID=1** (by integer choice), not by name; no label beyond PLMN+S-NSSAI

**Q4: Name reconciliation gap** — the 9 advertised metrics in the RAN function definition do NOT match ns-3's current DU cell metrics. The advertised list is RLC/L1M focused; ns-3 provides TB/PRB/SINR counts instead.

---

## Q1: kpimon-go's Expected Metric Names & Corresponding Logic

### Where Metrics are Discovered (Q1.1)

**File:** `/home/andang/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-kpimon-go/control/control.go`

**Logic flow:**
1. `buildRanCellUeKpi(hex_string)` [wrapper.c, line ~1] decodes RAN function description (E2SM_KPM_RANfunction_Description_t).
2. For `ric_ActionFormat_Type == 1` (cell metrics), iterates `measInfo_Action_List` and extracts `measName` + `measID` from each `MeasurementInfo_Action_Item`.
3. Returns `ranCellUeKpi_t { cellKpi=char**, cellKpiSize=int }` — array of metric name strings.
4. **Stored in:** `ranCellKpi[RAN_name]` map (control.go:54).

**At indication decode** (control.go, e2sm.go:349+):
```c
CellKpi := ranCellKpi[params.Meid.RanName]  // Extract expected metric names
tmpCellKpi := filter(CellKpi, non-empty)    // Build ordered list
if no_of_cell_metrics != len(tmpCellKpi) {  // FAIL if count mismatch
  return error("no_of_cell_metrics !=len(tmpCellKpi)")
}
// For each MeasurementRecordItem, index into tmpCellKpi to populate values[]
values[tmpCellKpi[i]] = record_value  // e.g., values["DRB.RlcSduTransmittedVolumeDL"] = 42
```

### Exact Advertised Metric Names (Q1.2)

**Source:** `/home/andang/Documents/UCLAB/projects/O-RAN-DW/ns-O-RAN-installation/oran-interface/model/kpm-function-description.cc:74–81`

```c
static const char *const g_kpmPerfMeasurements[] = {
    "DRB.RlcSduTransmittedVolumeDL",    // measID 1
    "DRB.RlcSduTransmittedVolumeUL",    // measID 2
    "DRB.PerDataVolumeDLDist.Bin",      // measID 3
    "DRB.PerDataVolumeULDist.Bin",      // measID 4
    "DRB.RlcPacketDropRateDLDist",      // measID 5
    "DRB.PacketLossRateULDist",         // measID 6
    "L1M.DL-SS-RSRP.SSB",               // measID 7
    "L1M.DL-SS-SINR.SSB",               // measID 8
    "L1M.UL-SRS-RSRP"                   // measID 9
};
static const int g_kpmNumberMeasurements = 9;
```

Each is added to `MeasurementInfo_Action_Item` in all 5 report styles (ric_ActionFormat_Type 1–5), via `BuildKpmMeasInfoActionList()` (line 95):
- Calls `SetKpmOctetString(&item->measName, g_kpmPerfMeasurements[i])`
- Sets `item->measID = i + 1`
- Adds to `measInfo_Action_List`

### Correspondence: MeasurementRecord ↔ MeasurementInfo Order (Q1.3)

**Critical:** kpimon-go expects **ordinal correspondence**. The indication message must contain:
- N `MeasurementRecordItems` in `MeasurementData[0].measRecord.list`
- N `MeasurementInfoItems` in `IndicationMessage.measInfoList.list`
- In **exact same order**: record[i] ↔ info[i], so index i maps record value to name `tmpCellKpi[i]`.

**Current dummy violation** (kpm-indication-builder.h:151–189):
- ONE `MeasurementDataItem` with ONE `MeasurementRecordItem` (integer 1).
- ONE `MeasurementInfoItem` with label (PLMN 747, S-NSSAI SST 1, SD 100) and `measType.choice.measID = 1` (not by name).
- **Result:** `no_of_cell_metrics = 1` but `len(tmpCellKpi) = 9` → mismatch → kpimon log error (benign for M5, blocking for M6).

---

## Q2: Real KPM Values ns-3 Produces (Bronze v2 Path)

### Source Locations (Q2.1)

1. **ns-3 metric collection:** `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:BuildAndSendReportMessage()` (line ~1900+).
2. **Helper that maps metrics to items:** `oran-interface/helper/mmwave-indication-message-helper.cc` (Q2.2 below).
3. **Actual values collected:** `ns3-mmwave-oran` simulation logs (not in static code; depends on scenario).

### DU Cell-Level Metrics (Reduced PM Mode) — Q2.2

**File:** `oran-interface/helper/mmwave-indication-message-helper.cc:116–162` (`AddDuCellPmItem()`)

**Parameters passed in (from BuildAndSendReportMessage):**
```cpp
macPduCellSpecific, macPduInitialCellSpecific,    // TB total/initial counts
macQpskCellSpecific, mac16QamCellSpecific, mac64QamCellSpecific,  // MCS distributions
prbUtilizationDl,                                  // double, PRB usage %
macRetxCellSpecific, macVolumeCellSpecific,       // Retx, PDCP volume (verbose mode)
macMac04CellSpecific, ..., macMac2529CellSpecific,  // SINR bins (verbose mode)
rlcBufferOccupCellSpecific,                       // RLC buffer (verbose mode)
activeUeDl                                        // Active UE count (key metric)
```

**Mapped to measurement items (with item names):**
```cpp
if (!m_reducedPmValues) {
    cellVal->AddItem<long>("TB.TotNbrDl.1", macPduCellSpecific);
    cellVal->AddItem<long>("TB.TotNbrDlInitial", macPduInitialCellSpecific);
}
cellVal->AddItem<long>("TB.TotNbrDlInitial.Qpsk", macQpskCellSpecific);
cellVal->AddItem<long>("TB.TotNbrDlInitial.16Qam", mac16QamCellSpecific);
cellVal->AddItem<long>("TB.TotNbrDlInitial.64Qam", mac64QamCellSpecific);
cellVal->AddItem<long>("RRU.PrbUsedDl", (long)std::ceil(prbUtilizationDl));

if (!m_reducedPmValues) {
    cellVal->AddItem<long>("TB.ErrTotalNbrDl.1", macRetxCellSpecific);
    cellVal->AddItem<long>("QosFlow.PdcpPduVolumeDL_Filter", macVolumeCellSpecific);
    cellVal->AddItem<long>("CARR.PDSCHMCSDist.Bin1..6", macMac*CellSpecific);
    cellVal->AddItem<long>("L1M.RS-SINR.Bin*", macSinrBin*CellSpecific);
    cellVal->AddItem<long>("DRB.BufferSize.Qos", rlcBufferOccupCellSpecific);
}
cellVal->AddItem<long>("DRB.MeanActiveUeDl", activeUeDl);  // Always added
```

**Reduced PM (m_reducedPmValues=true) cell metrics: 6 items**
1. `TB.TotNbrDlInitial.Qpsk` ← macQpskCellSpecific
2. `TB.TotNbrDlInitial.16Qam` ← mac16QamCellSpecific
3. `TB.TotNbrDlInitial.64Qam` ← mac64QamCellSpecific
4. `RRU.PrbUsedDl` ← ceil(prbUtilizationDl)
5. `DRB.MeanActiveUeDl` ← activeUeDl

**Source of values (from mm-wave MAC/PHY):**
- `macQpskCellSpecific` etc.: Count of TB transmissions per MCS (QPSK, 16-QAM, 64-QAM) — logged per TTI.
- `prbUtilizationDl`: Ratio of used PRBs to total PRBs in a scheduling period.
- `activeUeDl`: Count of UEs with pending DL traffic in the reporting period.

### Other Container Metrics (for reference)

- **CU-UP:** `QosFlow.PdcpPduVolumeDL_Filter.UEID`, `DRB.PdcpPduNbrDl.Qos.UEID` (per UE PDCP counts).
- **CU-CP:** `DRB.EstabSucc.5QI.UEID`, `HO.SrcCellQual.RS-SINR.UEID` (per UE RRC/HO metrics).

---

## Q3: v3 Builder Shape & Minimal ASN.1 Changes

### Current Dummy Structure (Q3.1)

**File:** `oran-interface/examples/kpm-indication-builder.h:127–216`

**Current Message:**
```c
// One MeasurementData record item (integer 1)
MeasurementRecordItem_t *recItem = calloc(1, sizeof(...));
recItem->present = MeasurementRecordItem_PR_integer;
recItem->choice.integer = 1;  // ← DUMMY VALUE

MeasurementDataItem_t *dataItem = calloc(1, sizeof(...));
dataItem->measRecord = *record;  // Record wraps the recItem
dataItem->incompleteFlag = 0;

// One MeasurementInfoItem with static label
MeasurementInfoItem_t *infoItem = calloc(1, sizeof(...));
infoItem->measType.present = MeasurementType_PR_measID;
infoItem->measType.choice.measID = 1;  // ← measID by integer, NOT by name
infoItem->labelInfoList = *labelList;  // PLMN 747, S-NSSAI SST 1, SD 100

// Format1 assembly
fmt->measData = *measData;       // One MeasurementData (one item)
fmt->measInfoList = infoList;    // One MeasurementInfoList (one item)
```

### Extension for N Metrics (M6 Logic) — Q3.2

To support real ns-3 metrics, **generalize** the builder to accept N metric names + values:

```c
/**
 * Build a v3 IndicationMessage-Format1 with N named metrics + values.
 * 
 * @param imsg: caller-allocated E2SM_KPM_IndicationMessage_t
 * @param metricNames: array of N metric name strings (const char*)
 * @param metricValues: array of N values (int or double; encode as MeasurementRecordItem)
 * @param count: N (number of metrics)
 */
inline void
BuildIndicationMessage (
    E2SM_KPM_IndicationMessage_t *imsg,
    const char **metricNames,           // e.g., ["RRU.PrbUsedDl", "TB.TotNbrDlInitial.Qpsk", ...]
    const union MetricValue *values,    // e.g., {42L, 100L, ...}; integers for now
    int count)
{
    // Build MeasurementRecord: one item per metric
    MeasurementRecord_t *record = calloc(1, sizeof(MeasurementRecord_t));
    for (int i = 0; i < count; i++) {
        MeasurementRecordItem_t *recItem = calloc(1, sizeof(...));
        recItem->present = MeasurementRecordItem_PR_integer;
        recItem->choice.integer = values[i].i64;  // Cast double values if needed
        ASN_SEQUENCE_ADD(&record->list, recItem);
    }
    
    MeasurementDataItem_t *dataItem = calloc(1, sizeof(...));
    dataItem->measRecord = *record;
    dataItem->incompleteFlag = 0;
    
    MeasurementData_t *measData = calloc(1, sizeof(...));
    ASN_SEQUENCE_ADD(&measData->list, dataItem);
    
    // Build MeasurementInfoList: one item per metric (name-indexed)
    MeasurementInfoList_t *infoList = calloc(1, sizeof(...));
    for (int i = 0; i < count; i++) {
        MeasurementInfoItem_t *infoItem = calloc(1, sizeof(...));
        
        // Key change: use measName, not measID
        infoItem->measType.present = MeasurementType_PR_measName;
        SetKpmOctetString(&infoItem->measType.choice.measName, metricNames[i]);
        
        // Static label (PLMN + S-NSSAI) — same for all items in this call
        infoItem->labelInfoList = *labelList;
        
        ASN_SEQUENCE_ADD(&infoList->list, infoItem);
    }
    
    // Format1 assembly
    E2SM_KPM_IndicationMessage_Format1_t *fmt = calloc(1, sizeof(...));
    fmt->granulPeriod = 1;
    fmt->measData = *measData;
    fmt->measInfoList = infoList;
    
    imsg->indicationMessage_formats.present = 
        E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format1;
    imsg->indicationMessage_formats.choice.indicationMessage_Format1 = fmt;
    
    // ASN.1 constraint check (exit 1 on failure, per Phase 5 pattern)
    char err_buf[300] = {0};
    size_t err_len = sizeof(err_buf);
    if (asn_check_constraints(&asn_DEF_E2SM_KPM_IndicationMessage, imsg, err_buf, &err_len)) {
        fprintf(stderr, "[ind] constraint check failed: %s\n", err_buf);
        exit(1);
    }
}
```

### Key Changes (Q3.3)

| Aspect | M5 (Dummy) | M6 (Real) |
|--------|-----------|----------|
| `MeasurementRecordItem` count | 1 (hardcoded) | **N** (param) |
| Record values | integer 1 (dummy) | **Real ns-3 values** (ints or floats) |
| `MeasurementInfoItem` count | 1 (hardcoded) | **N** (param) |
| Metric identification | `measID` integer choice (1) | **`measName` string choice** (e.g., "RRU.PrbUsedDl") |
| Label (PLMN+S-NSSAI) | Static ("747", "1", "100") | **Param or derived from ns-3 context** |
| ASN.1 validation | `asn_check_constraints` exit(1) | **Same (fatal on constraint failure)** |

### Constraint Check Behavior (Q3.4 — Note I1 Clarification)

`asn_check_constraints(&asn_DEF_E2SM_KPM_IndicationMessage, imsg, err_buf, &err_len)` validates:
- All mandatory fields present.
- Field sizes within defined limits (OCTET STRING length, INTEGER ranges).
- SEQUENCE count constraints.
- **Mismatch: if `measInfoList.count != measData[0].measRecord.count`, constraint may fail** (depends on ASN.1 grammar; typically not enforced, but log manually).

**kpimon-go's stricter check** (Q1):
- Decodes both lists.
- **Explicitly asserts** `no_of_cell_metrics == len(tmpCellKpi)` in application logic (control.go).
- **Fails the entire indication** if mismatch, preventing metric population.

→ **M6 build must ensure ordinal correspondence** (record[i] ↔ info[i]).

---

## Q4: Name Reconciliation & M6 Starting Set

### Gap Analysis (Q4.1)

| RAN Function Advertised (9) | ns-3 DU Reduced Produces (6) | Mapping | Status |
|-----|-----|-------|--------|
| DRB.RlcSduTransmittedVolumeDL | — | — | ❌ Not in reduced PM |
| DRB.RlcSduTransmittedVolumeUL | — | — | ❌ Not in reduced PM |
| DRB.PerDataVolumeDLDist.Bin | — | — | ❌ Not in reduced PM |
| DRB.PerDataVolumeULDist.Bin | — | — | ❌ Not in reduced PM |
| DRB.RlcPacketDropRateDLDist | — | — | ❌ Not in reduced PM |
| DRB.PacketLossRateULDist | — | — | ❌ Not in reduced PM |
| L1M.DL-SS-RSRP.SSB | — | — | ❌ Not in reduced PM |
| L1M.DL-SS-SINR.SSB | — | — | ❌ Not in reduced PM |
| L1M.UL-SRS-RSRP | — | — | ❌ Not in reduced PM |
| (none) | TB.TotNbrDlInitial.Qpsk | — | ❌ Advertised but not produced |
| (none) | TB.TotNbrDlInitial.16Qam | — | ❌ Advertised but not produced |
| (none) | TB.TotNbrDlInitial.64Qam | — | ❌ Advertised but not produced |
| (none) | RRU.PrbUsedDl | — | ❌ Advertised but not produced |
| (none) | DRB.MeanActiveUeDl | — | ❌ Advertised but not produced |

**Root cause:** RAN function definition lists 9 RLC/L1M metrics (golden parity with OSC encode_kpm.cpp, Phase 4); ns-3's helper populates **TB (transport block)** + **PRB** counts instead.

### Recommended M6 First Step (Q4.2)

**Option A: Map 4 Existing ns-3 Metrics** (minimal viable M6)

Modify RAN function definition to advertise 4 ns-3-available metrics instead of 9:
```c
static const char *const g_kpmPerfMeasurements[] = {
    "TB.TotNbrDlInitial.Qpsk",      // matches ns-3 output
    "TB.TotNbrDlInitial.16Qam",
    "TB.TotNbrDlInitial.64Qam",
    "RRU.PrbUsedDl"                 // PRB util ← ceil(prbUtilizationDl)
};
static const int g_kpmNumberMeasurements = 4;
```

**Pros:** kpimon's tmpCellKpi matches indication message (4 records ↔ 4 info items). **M6 unblocks immediately.**
**Cons:** Deviates from OSC golden (9 metrics) — architectural trade-off for fast M6 delivery.

**Option B: Extend ns-3 to Produce RLC/L1M Metrics** (scope creep, Phase 8+)

Add RLC/L1M collection to ns-3 (low-level simulator enhancement). Phase 7 focuses on *mapping*, not *new metric sources*.

**Recommendation:** Adopt **Option A** for M6 (Phase 7). Document the deviation. Phase 8 can backport RLC/L1M collection if OSC parity becomes a requirement.

---

## Unresolved Questions

1. **Q: How are ns-3 double values (e.g., prbUtilizationDl) encoded into MeasurementRecordItem?**
   - Current code uses `std::ceil()` to convert double → long before AddItem().
   - kpm-indication-builder.h choice is `MeasurementRecordItem_PR_integer` (long) or `PR_real` (double)?
   - **Action:** Check E2SM-KPM v3.00 ASN.1 grammar; both are valid; choose based on Phase 5 experience.

2. **Q: What PLMN/S-NSSAI labels should M6 use for cell metrics?**
   - M5 hardcodes PLMN 747, S-NSSAI SST 1, SD 100 (static).
   - M6 could derive from ns-3 context (gnbId, cellId) or keep static.
   - **Action:** Verify if kpimon-go filters by label; if not, static is fine.

3. **Q: What's the correct measID-to-name mapping if both are advertised?**
   - RAN function def assigns measID (1..N), but kpimon-go extracts measName.
   - Does measID influence decoding order, or only measName?
   - **Action:** Check e2sm wrapper (ric-app-kpimon-go/e2sm/wrapper.c) for priority.

4. **Q: Should M6 stay in `examples/` or move to `model/kpm-indication.cc`?**
   - Phase 5 pattern: standalone `examples/` for offline proof.
   - Phase 6 did same (kpm-indication-builder.h in examples/).
   - M6 likely needs live ns-3 integration (hook into BuildAndSendReportMessage).
   - **Action:** Likely merge into `model/` after M5 proof; confirm with Phase 7 lead.

5. **Q: Are UE-level metrics (DRB throughput, SINR bins) part of M6, or cell-level only?**
   - Phase 6 notes mention "cell_meas_kpm_report_indication_message_style_1".
   - mmwave-indication-message-helper has both AddDuCellPmItem and AddDuUePmItem.
   - **Action:** M6 scope definition needed; Phase 7 likely targets cell metrics first (simpler).

---

## Concrete Deliverable for Phase 7 (M6 Implementation Plan)

### ASN.1 Build Changes

**File to modify:** `oran-interface/examples/kpm-indication-builder.h` (or new Phase 7 equivalent)

**Function signature for M6:**
```cpp
inline void
BuildIndicationMessage (
    E2SM_KPM_IndicationMessage_t *imsg,
    const std::vector<std::string> &metricNames,
    const std::vector<long> &metricValues);  // All long for M6.0; float support in M6.1
```

**Exact ASN.1 calls:**
```cpp
// Iterate per metric
for (size_t i = 0; i < metricNames.size(); i++) {
    // MeasurementRecordItem
    MeasurementRecordItem_t *recItem = calloc(1, sizeof(MeasurementRecordItem_t));
    recItem->present = MeasurementRecordItem_PR_integer;
    recItem->choice.integer = metricValues[i];
    ASN_SEQUENCE_ADD(&record->list, recItem);
    
    // MeasurementInfoItem with measName
    MeasurementInfoItem_t *infoItem = calloc(1, sizeof(MeasurementInfoItem_t));
    infoItem->measType.present = MeasurementType_PR_measName;
    infoItem->measType.choice.measName.buf = (uint8_t*)metricNames[i].c_str();
    infoItem->measType.choice.measName.size = metricNames[i].size();
    infoItem->labelInfoList = *labelList;  // Static for now
    ASN_SEQUENCE_ADD(&infoList->list, infoItem);
}
```

### RAN Function Definition Update

**File:** `oran-interface/model/kpm-function-description.cc:75–81`

**Change to:**
```cpp
static const char *const g_kpmPerfMeasurements[] = {
    "TB.TotNbrDlInitial.Qpsk",       // measID 1 ← align with ns-3
    "TB.TotNbrDlInitial.16Qam",      // measID 2
    "TB.TotNbrDlInitial.64Qam",      // measID 3
    "RRU.PrbUsedDl"                  // measID 4 ← PRB utilization
};
static const int g_kpmNumberMeasurements = 4;
```

### Harness Assertions (M6)

Add to `scripts/l-release-validation/m6-real-kpm.sh`:
```bash
# 1. Live ns-3 + RIC: confirm kpimon logs "no_of_cell_metrics = 4"
# 2. Wireshark dissect: confirm 4 MeasurementRecordItems + 4 MeasurementInfoItems
# 3. kpimon metric table: confirm values["RRU.PrbUsedDl"] populated (not empty)
# 4. Value sanity: PRB utilization 0–100, TB counts > 0
```

---

## Source Evidence Summary

| Question | File:Line | Evidence |
|----------|-----------|----------|
| Q1a: tmpCellKpi build | ric-app-kpimon-go/control/control.go:330+ | CellKpi := ranCellKpi[]; tmpCellKpi filter |
| Q1b: ranCellKpi populate | ric-app-kpimon-go/e2sm/wrapper.c:51 | buildRanCellUeKpi() parses measInfo_Action_List.measName |
| Q1c: Check constraint | ric-app-kpimon-go/control/control.go:387 | if no_of_cell_metrics != len(tmpCellKpi) return error |
| Q2a: DU collect source | ns3-mmwave-oran/.../mmwave-enb-net-device.cc:~1900 | BuildAndSendReportMessage() calls Build*Message helpers |
| Q2b: DU map to items | oran-interface/helper/mmwave-indication-message-helper.cc:116 | AddDuCellPmItem() adds items with measName strings |
| Q2c: Reduced PM items | mmwave-indication-message-helper.cc:128–161 | if (!m_reducedPmValues) gate; 6 items in reduced mode |
| Q3a: v3 builder shape | oran-interface/examples/kpm-indication-builder.h:127 | BuildDummyIndicationMessage() with measID choice |
| Q3b: Constraint check | kpm-indication-builder.h:209 | asn_check_constraints() exit(1) on failure |
| Q4a: Advertised metrics | oran-interface/model/kpm-function-description.cc:75 | g_kpmPerfMeasurements[9] RLC/L1M names |
| Q4b: ns-3 names | mmwave-indication-message-helper.cc:134–159 | AddItem<>("TB.TotNbrDlInitial.Qpsk", ...) |

---

**Status:** DONE

**Summary:** Phase 7 M6 can proceed with 4-item mapping (TB/PRB metrics). kpimon-go expectations clear; v3 builder shape documented; name reconciliation gap identified (RLC/L1M vs TB/PRB — resolved by updating RAN function def). No blocking unknowns; minor questions flagged for design discussion.

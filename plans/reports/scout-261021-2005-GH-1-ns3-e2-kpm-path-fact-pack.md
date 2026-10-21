# Fact pack: how ns-O-RAN's ns-3 produces and sends E2 KPM data today

Date: 2026-10-21. Read-only scout (Sonnet Explore). It feeds the P3 E2-agent design.
Repos: ns-3-mmwave-oran `8c42089d` (NS3), oran-interface `5f547ae` (OI), oran-e2sim `2209995` (E2SIM).
Abbreviations: scen = `NS3/scratch/scenario-zero.cc`, MW = `NS3/src/mmwave/model/mmwave-enb-net-device.cc`, LTE = `NS3/src/lte/model/lte-enb-net-device.cc`, MWH = `NS3/src/mmwave/helper/mmwave-helper.cc`. Line numbers marked ~ are approximate.

## 1. scenario-zero
- **CLI options.** All are `GlobalValue`s.
  - e2lteEnabled true (scen:142), e2nrEnabled true (:145), e2du true (:148), e2cuUp true (:151), e2cuCp true (:154).
  - reducedPmValues true (:157), indicationPeriodicity 0.1 s (:166), simTime 2 s (:170).
  - e2TermIp "10.0.2.10" (:190), enableE2FileLogging false (:194), controlFileName "" (~:198), useSemaphores false (:203).
  - E2Port 36422 and E2LocalPort 38470 are `MmWaveHelper` attributes only (MWH:298-306).
- **Node counts.** Hardcoded (scen:378-381): `nMmWaveEnbNodes=4`, `nLteEnbNodes=1`, `ues=3`, `nUeNodes=12`.
- **Traffic.** Full-buffer UDP DL: 1280 B every 500 µs per UE, from 0.1 s to simTime−0.1 s (scen:504-523).
- **cellIds.** LTE eNB = 1, mmWave gNBs = 2..5 (MWH:90, 1847, 2268; derived, not run).
- **The LTE eNB is an E2 node by default** (E2ModeLte true, MWH:288-291), so there are 5 E2 nodes by default.

## 2. Identity
- **NR** (MWH:2191-2203): `local_port = 38470 + cellId`, `gnb_id = to_string(cellId)`, `plmnId = "111"`, `CreateObject<E2Termination>(ip, 36422, local_port, gnb_id, plmn)`.
- **LTE** (MWH:2503-2512): same pattern.
- **Encoding.** The PLMN is the ASCII "111" (0x31 0x31 0x31). In the KPM header, the gNB ID is a 4-byte memcpy of the decimal string's ASCII (kpm-indication.cc:110-139), so short IDs read past the string.

## 3. Reporting path
- **Start.** `E2Termination::Start` is scheduled at t=0 (MW:499-508, LTE:956-958).
- **KPM function ID is 200** (MW:638, LTE:1078). RC is 300, LTE only (LTE:1085).
- **Online mode.** Reporting starts only after a subscription. `KpmSubscriptionCallback` calls `BuildAndSendReportMessage` (MW:82-97, LTE:94-107). It then reschedules itself every `E2Periodicity` with `ScheduleWithContext(1, …)` (MW:1604, LTE:1491).
- **Per call, up to 3 separate RICindications:**
  - **CU-UP** (MW:690, LTE:1134).
  - **CU-CP** (MW:938, LTE:1344).
  - **DU** (MW:1124, mmWave only).

  The sequence number is hardcoded to 1. scenario-zero enables all three kinds.
- **File-logging mode** (no subscription, no ASN.1): `cu-up-cell-<id>.txt`, `cu-cp-cell-<id>.txt`, `du-cell-<id>.txt`. Each row starts with `timestamp = m_startTime + now_ms` (MW:512-596).

## 4. Metric set
- Names are literals in `OI/helper/{mmwave,lte,}-indication-message-helper.cc`.
- `MeasurementItem(name,long)` becomes `valueInt` and `(name,double)` becomes `valueReal` (asn1c-types.cc:816-828). Items marked [full] are emitted only with reducedPmValues=false.
- **DU per UE** (MIH:72-113; UE ID = 5-digit IMSI string):
  - [full], all long: `TB.TotNbrDl.1.UEID`, `TB.TotNbrDlInitial{,.Qpsk,.16Qam,.64Qam}.UEID`, `TB.ErrTotalNbrDl.1.UEID`, `QosFlow.PdcpPduVolumeDL_Filter.UEID`, `RRU.PrbUsedDl.UEID`, `CARR.PDSCHMCSDist.Bin1..6.UEID`, `L1M.RS-SINR.Bin34/46/58/70/82/94/127.UEID`, `DRB.BufferSize.Qos.UEID`.
  - Always sent: `DRB.UEThpDl.UEID` (double, kbit/s).
- **DU per cell** (MIH:116-162):
  - Always sent: `TB.TotNbrDlInitial.{Qpsk,16Qam,64Qam}`, `RRU.PrbUsedDl`, `DRB.MeanActiveUeDl` (long).
  - [full]: `TB.TotNbrDl.1`, `TB.TotNbrDlInitial`, `TB.ErrTotalNbrDl.1`, `QosFlow.PdcpPduVolumeDL_Filter`, `CARR.PDSCHMCSDist.Bin1..6`, `L1M.RS-SINR.Bin*`, `DRB.BufferSize.Qos`.
  - DU container: available PRBs 139/139 (hardcoded); per-QCI dl/ul PRB usage, 0-100.
- **CU-UP:**
  - MW per UE, [full]: `QosFlow.PdcpPduVolumeDL_Filter.UEID`, `DRB.PdcpPduNbrDl.Qos.UEID`.
  - LTE per UE, [full]: `DRB.PdcpSduVolumeDl_Filter.UEID` (long), `Tot.PdcpSduNbrDl.UEID` (long), `DRB.PdcpSduBitRateDl.UEID` (double), `DRB.PdcpSduDelayDl.UEID` (double).
  - LTE per cell: `DRB.PdcpSduDelayDl`.
  - Container: `pDCPBytesDL/UL` (INTEGER).
- **CU-CP:**
  - Per UE, [full]: `DRB.EstabSucc.5QI.UEID`, `DRB.RelActNbr.5QI.UEID`.
  - MW per UE, always sent: `HO.SrcCellQual.RS-SINR.UEID` and `HO.TrgtCellQual.RS-SINR.UEID` as `valueRRC` (L3 serving and neighbour SINR).
  - Container: `numberOfActive_UEs`.
- **int32 risk.** Transport carries a 64-bit `long`, so the risk is a consumer that casts to int32. MAC counters are uint32; PDCP volumes are uint64 kbit.

## 5. KPM indication header (kpm-indication.cc)
- Format 1, APER.
- **Timestamp.** `m_startTime + Simulator::Now().GetMilliSeconds()` (MW:674, LTE:1119). `m_startTime` is the wall-clock epoch ms taken at helper construction (MWH:3299-3305). It is encoded as 8 big-endian bytes (`htobe64`, `TIMESTAMP_LIMIT_SIZE=8`, kpm-indication.cc:181-191, .h:51).
- `m_nrCellId` is not written into the header.

## 6. Subscription handling
- `ProcessRicSubscriptionRequest` (oran-interface.cc:146-280):
  - It accepts the first report action and replies with success immediately.
  - It **ignores the event trigger** ("TODO", :210-220).
- **KPM RAN function description** (kpm-function-description.cc:72-145):
  - Short name "ORAN-WG3-KPM" and OID "OID123"; no version field is set.
  - Event trigger style 1, periodic. Report style 1, header format 1 and message format 1.

## 7. asn1c/e2sim coupling outside OI
- `#include <ns3/oran-interface.h>` at lte-enb-net-device.h:36 and mmwave-enb-net-device.h:47. `encode_e2apv1.hpp` at LTE:36 and MW:34.
- **`E2AP_PDU_t`** appears in:
  - the headers: lte-enb-net-device.h:239-240 and mmwave-enb-net-device.h:109, 138;
  - LTE:94, 434, 1446, 1473;
  - MW:82, 1534, 1561, 1588.
- `L3RrcMeasurements` is used at MW:972-1040.
- CMake: `src/lte/CMakeLists.txt:373` and `src/mmwave/CMakeLists.txt:153` link `${liboran-interface}`. OI's `find_external_library(e2sim)` calls `return()` when e2sim is missing (OI/CMakeLists.txt:17-29).

## 8. RC path (to compile out in P4)
- `LteEnbNetDevice::ControlMessageReceivedCallback` (LTE:434-486) uses `RicControlMessage`.
  - For a handover it calls `TakeUeHoControl`, then `PerformHandoverToTargetCell`.
  - For QoS it is fatal.
- RC registration is at LTE:1081-1092.
- `ReadControlFile` (LTE:128-376) is ASN-free and stays.

## 9. Threading
- One detached e2sim thread per E2 node (oran-interface.cc:105-114).
- The first `BuildAndSendReportMessage` runs on that thread (hazard). Later calls run on the simulator thread.
- `client_fd` is shared between the receive thread and sends, with no lock.
- `UseSemaphores` is file-mode control sync only.

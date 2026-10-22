# Fact pack: RC, TS, QP and the ns-3 control path (input for the pre-M8 pacing counsels)

Date: 2026-10-22. Two read-only scouts, with the load-bearing claims re-checked by the orchestrator against the sources (marked ✔).

Sources:
- `rc` = ric-app/rc @a2282ee
- `ts` = ric-app/ts @19e169b
- `qp` = ric-app/qp @47a35ca
- `e2i` = sim/e2-interface @da6f82f
- `kpm` = kpimon-go @8bbbbbb

The NIST `Near-Real-Time-RIC/commit_hashes.json` equals `commit_hashes_l_release.json` ✔. On the ns-3 side, "upstream" means ns-3 @8c42089 and oran-interface @5f547ae, and "fork" means ns-3 @ace3216 and oran-interface @438a839.

## 1. Old ns-O-RAN control path (upstream)

- **Who handles control.** Only `LteEnbNetDevice` registers a control callback, for RAN function 300 (`lte-enb-net-device.cc:1082`). `MmWaveEnbNetDevice` registers KPM only. Its `ControlMessageReceivedCallback` is declared and never defined.
- **The ack.** e2sim calls the callback on its own SCTP thread and then always sends a RICcontrolAcknowledge, whatever the outcome (`oran-e2sim e2ap_message_handler.cpp:~227-246`).
- **Decode.** The RC is a pre-v2 "E2SM-KPM-RC" asn1c module.
  - The IMSI is taken from ControlHeader `ueId`.
  - The target cell is taken from `cgi.back()`, one digit (`ric-control-message.cc:141-143`).
- **Execution.**
  - `TakeUeHoControl(imsi)` removes the UE from automatic handover.
  - `Simulator::ScheduleWithContext(1, 0s, LteEnbRrc::PerformHandoverToTargetCell)` then runs the handover. The call is cross-thread, which is the known hazard.
- **Who performs the handover.** In EN-DC the **LTE master RRC** initiates it ✔. `PerformHandoverToTargetCell` (`lte-enb-rrc.cc:4478-4527`) requires `m_mmWaveCellSetupCompleted[imsi]` and calls `SendMcHandoverRequest`. That sends an X2 McHandover to the source mmWave RRC, which runs `SendHandoverRequest(rnti, target)`.
- **No handover-completion report** is sent back to the RIC.

## 2. File mode and semaphores (upstream; identical in the fork)

- **Reader.** `LteEnbNetDevice::ReadControlFile` exists for LTE only. It runs first at E2Periodicity + 5 ms and then every E2Periodicity.
- **Lock-step.** With `UseSemaphores` it does `sem_post(/sem_metrics_<cwd>)` and then `sem_wait(/sem_control_<cwd>)`, which blocks the sim thread. Only after that does it read and then truncate the CSV.
- **Control files.**
  - `ts_actions_for_ns3.csv`: `timestamp,imsi,targetCellId`. A multi-digit target is accepted.
  - `es_actions_for_ns3.csv` and `qos_actions.csv` also exist.
- **Prerequisite (unverified).** It appears to require `enableE2FileLogging=1`, because the file-mode set-up sits in the `else` branch of `!m_forceE2FileLogging`.

## 3. Our fork today

- **Legacy control is compiled out.** The asn1c control callback is behind `NS3_ORAN_LEGACY_ASN1_RIC_CONTROL`, which is never defined. `TakeUeHoControl`, `PerformHandoverToTargetCell` and `ReadControlFile` remain.
- **The IPC client is single-threaded.** It runs on the sim thread. `E2IpcTcpClient::Drain` discards inbound bytes (`e2-ipc-tcp-client.cc:142-170`) and is called from `Service()` on each `EmitSample`.
- **No real-time scheduler.** `RealtimeSimulatorImpl` is not used.
- **Node IDs.** cellId 1 is the LTE eNB, and the gNBs are 2..N+1.
- **UEs and mobility.** There are 3 UEs per gNB on RandomWalk2d at 2–4 m/s.
- **Automatic handover.** It is on by default (`handoverMode=DynamicTtt`). `--handoverMode=NoAuto` disables it.

## 4. ns-o-ran-gym pacing

- **Mechanism.** Named POSIX semaphores plus the file mode.
- **One step.** `step()` writes the action CSV, releases the control semaphore, waits for the metric semaphore (timeout 10 s), and reads the datalake.
- **Step size.** One step is one indication period, in **sim** time.
- **Timeout.** A `BusyError` timeout only checks whether the simulation has ended, then retries. It never fails the step (`src/nsoran/ns_env.py:237-376`).
- **Scenario.** It targets scenario-one.

## 5. rc xApp (Go, gRPC :7777)

- **RC version.** E2SM-RC **v2.0** (`e2sm/e2sm-rc-2.0.asn`, module `version1(1) … e2sm-RC-IEs(3)`) ✔.
- **E2AP.** Its E2AP schema uses OID version2.
- **Request fields.** RAN function, style and action all come from the gRPC request; the constants are style 3 and action 1.
- **Control Header.** Format 1 with a gNB_UEID: AMF-UE-NGAP-ID, GUAMI, and F1AP and E1AP id lists, all required.
- **Control Message.** Format 1, RANParameter tree 1/2/3/4 = Target Primary Cell / Target Cell / NR Cell / NR CGI. The CGI is `"00"+PLMNhex+TargetCellID` (`rcE2SmRc.go:101`) ✔, so TargetCellID is a hex string.
- **Routing.** It sends RMR 12040 to the MEID derived from `ranName`. It never checks whether the node advertises RC.
- **Acks.** RICControlAckRequest is not encoded.
  - Acks (12041) and failures (12042) are only logged.
  - The 2 s ack timer only logs on expiry.
  - A gRPC `rspCode 0` means "queued".

## 6. TS xApp (C++)

- **Data.** It reads no metrics itself.
- **Trigger and prediction.**
  - Triggers: an A1 policy of type 20008 (threshold %) and AD anomalies (RMR 30003).
  - It sends a UE list to QP (RMR 30000) and receives predictions back on 30002.
  - It hands over when the best cell's DL is above serving × (1 + threshold/100).
- **Hard-coded values.** `ranfuncid=3`, requestor 1, style 3, action 1 ✔ (`src/ts_xapp/ts_xapp.cpp:614-615`). All UE ids are `stoi(ue_id)`. The GUAMI is the VIAVI constants ✔ (`:627`).
- **Addressing.** It sends to the e2NodeID and ranName of the **target cell's** node, taken from `cell_map`.
- **`cell_map`.** It GETs e2mgr `/v1/nodeb/<name>`, base64-decodes `e2nodeComponentRequestPart`, and searches it for the UPPERCASED ranName suffix. Each match keeps `substr(i,10)` ✔ (`:353-366`).
- **Unmapped targets.** A target that is not in the map is skipped silently.
- **Control transport.** The descriptor default is `ts_control_api: rest` to a 127.0.0.1 echo endpoint. It must be set to gRPC → rc:7777. NIST's installer patches only the AD RMR route.

## 7. QP xApp (Python)

- **Configuration.** NIST patches it to InfluxDB v2, bucket `kpimon`.
- **Reads.** The measurements `UEReports` and `CellReports` ✔.
  - UE rows are keyed by `ue-id`, with `nbCell*` / `nrCell*` columns.
  - Cell rows are keyed by `nrCellIdentity`, with `pdcpBytesDl` / `pdcpBytesUl`.
- **Model.** A statsmodels VAR predicting one step ahead.
- **Output.** RMR 30002 `{ue:{cell:[DL,UL]}}`.
- **Mismatch.** kpimon writes `UeMetrics` and `cellMetrics` (`control.go:955,976`) ✔, so **QP cannot read kpimon's data as-is**. Field-level mapping is not done.

## 8. NIST e2-interface

- **No E2SM-RC.** There is no E2SM-RC ASN or generated code ✔. The ASN directory holds only e2ap v03.01, e2sm v03.01 and e2sm-kpm v03.00.
- **No control handler.** The message router has no RICcontrol case ✔.
- **E2AP types exist.** The generated E2AP types include RICcontrolRequest, RICcontrolAcknowledge, RICcontrolFailure and RICcontrolAckRequest.
- **E2AP OID.** The files are named v03.01, but the OID is `version2`.

## 9. Version alignment

| | E2SM-RC | E2AP OID |
|---|---|---|
| rc xApp | v2.0 | version2 |
| e2-interface (agent) | none (agent must add a v2.0 codec from rc's ASN) | version2 |
| L e2term 6.0.6 | n/a | not determined |

## Not found / unverified

1. e2term 6.0.6's E2AP version.
2. kpimon's exact field keys versus QP's.
3. Whether file control requires `enableE2FileLogging=1`.
4. The Bronze TS xApp source (outside the given repos).

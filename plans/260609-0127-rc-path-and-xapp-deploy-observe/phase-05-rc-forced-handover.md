# Phase 5 — RC act: forced handover (M-RC2)

**Plan:** `260609-0127-rc-path-and-xapp-deploy-observe` · **Depends:** Phase 4 (M-RC1 DONE — RC receive + ACK on wire).
**Exit M-RC2:** deployed `rc` xApp → RIC Control Request (ControlStyle 3 = handover) → ns-3 forces a UE
secondary-cell handover to the target cell, **verified in ns-3 handover traces**, correlated to the control msg; ACK still on wire.
**Status:** ✅ **M-RC2 DONE (2026-06-13)** — xApp RIC Control forces a UE secondary-cell handover (Imsi 1, cell 2→5 and cell 2→4), completed in ns-3 traces (RRC reconf + path switch + old-cell release); invalid targets rejected (no crash); ACK on wire. Implemented via **Option B** (live pivot — Option A's LTE-eNB precondition failed). See §"Phase 5 result".

## Decisions (locked with user 2026-06-13)
- **D1 — Canonical LTE-eNB path.** Control targets the **LTE eNB** E2 node (`ranName=<lte-enb>`); re-enable the
  original `LteEnbNetDevice::ControlMessageReceivedCallback` handover → `m_rrc->PerformHandoverToTargetCell`.
  No ns-3 core/helper wiring. (`e2lteEnabled` defaults true → LTE eNB already an E2 node + registers funcId 300.)
- **D2 — I drive the VM** (SSH `oran-kvm-2`). Repo is **virtiofs-shared** (local edits == VM files); loop = edit
  local → SSH build → SSH live-test. No git push/pull needed to test.
- **D3 — Defer RANFunctionDefinition advertisement** (null-buffer stub kept; control works without it, Phase-0/4 proven).

## Why the prior attempt (reverted) was wrong
Reverted commits: oran-interface `e3d1825` (extraction — sound), ns3 `95f0f381` (handover — **flawed**).
`95f0f381` put the handover on the **mmWave gNB** and called `m_rrc->SendHandoverRequest(rnti, targetCellId)` on
the **gNB's own RRC**. Verified flaws:
- `mmwave-helper.cc` makes **separate `LteEnbRrc` objects** (gNB RRC line 2000 `m_ismmWave=true`; LTE master line 2328).
  The gNB's `m_rrc` is NOT the master.
- scenario-zero is **EN-DC**: a UE's mmWave serving-cell change is a *secondary-cell handover* coordinated by the
  **LTE master RRC** via `PerformHandoverToTargetCell` → `m_x2SapProvider->SendMcHandoverRequest`, using master-only
  state (`m_mmWaveCellSetupCompleted[imsi]`, `m_lastMmWaveCell[imsi]`). `SendHandoverRequest` on the gNB RRC bypasses all of it.
- Canonical upstream ns-O-RAN (commit `8585bec`/`8c42089d`): `LteEnbNetDevice::ControlMessageReceivedCallback` →
  `m_rrc->TakeUeHoControl(imsi)` + `ScheduleWithContext(1, Seconds(0), &LteEnbRrc::PerformHandoverToTargetCell, m_rrc, imsi, targetCellId)`.

## Data flow (M-RC2, canonical)
```
rc xApp --gRPC(ranName=<lte-enb>, UEID.amfUENGAPID=imsi, ControlStyle 3, TargetCellID)-->
  ricxapp-rc --E2AP RICcontrolRequest(funcId 300)--> e2term --SCTP--> LTE-eNB e2sim client_fd
    e2ap_handle_sctp_data: procedureCode==RICcontrol(4) -> get_subscription_callback(300)
      -> LteEnbNetDevice::ControlMessageReceivedCallback(pdu)         [e2sim run_loop thread]
          RicControlMessage rc(pdu)   // decode hdr+msg (RC-2.0): m_imsi, m_targetCellId
          ACK (always)  -> m_e2term->SendE2Message(ack)               // M-RC1 path, unchanged
          if (m_imsi>0 && m_targetCellId>0):
            ScheduleWithContext(1, 0s, &LteEnbRrc::TakeUeHoControl,         m_rrc, imsi)
            ScheduleWithContext(1, 0s, &LteEnbRrc::PerformHandoverToTargetCell, m_rrc, imsi, targetCellId)
              -> [sim thread] SecondaryHandoverParams{imsi,targetCellId,oldCell} -> X2 SendMcHandoverRequest
                 -> target mmWave eNB -> HandoverStart/HandoverEndOk traces  (M-RC2 evidence)
```
**Thread-safety improvement over original:** both `TakeUeHoControl` and `PerformHandoverToTargetCell` are scheduled
on the sim thread (original called `TakeUeHoControl` directly from the e2sim thread → data race on `m_e2ControlledUes`).
FIFO same-time ordering guarantees `TakeUeHoControl` runs first.

## Files to change
**oran-interface (`oran-interface/model/`):** — extraction only, additive.
- `ric-control-message.h` — add `uint64_t m_imsi {0};` + `uint16_t m_targetCellId {0};`; declare
  `static uint16_t ExtractTargetCellFromRanPList(E2SM_RC_ControlMessage_Format1_t*);`; add RANParameter/UEID includes.
- `ric-control-message.cc` — in `DecodeRicControlMessage`: header → extract `amf_UE_NGAP_ID` via `asn_INTEGER2ulong`
  into `m_imsi`; message Format1 → `m_targetCellId = ExtractTargetCellFromRanPList(fmt1)`. Add the 4-level
  nested-`ranP_List`→NRCGI navigator (from reverted `e3d1825`, with null-guards). **Never call `asn_check_constraints`** (Phase-3 landmine).

**ns3-mmwave-oran (`src/lte/model/`):** — handover trigger on the master.
- `lte-enb-net-device.cc` — `ControlMessageReceivedCallback`: after the ACK, if `m_imsi>0 && m_targetCellId>0 && m_rrc`,
  `ScheduleWithContext(1,0s,&LteEnbRrc::TakeUeHoControl,m_rrc,imsi)` then
  `ScheduleWithContext(1,0s,&LteEnbRrc::PerformHandoverToTargetCell,m_rrc,imsi,targetCellId)`. Mirror original; keep ACK.
- **gNB callback unchanged** (decode + ACK; no handover — control is targeted at the LTE eNB per D1).

## Bring-up aid
First live run: temporarily `xer_fprint(stderr, &asn_DEF_E2SM_RC_ControlMessage, msg)` to dump the real `ranP_List`
structure → confirm/adjust the navigator + the cell-id encoding (TargetCellID → NRCGI → ns-3 cellId). Quiet after confirmed.

## Live test (M-RC2 gate, on oran-kvm-2)
1. Build (strict order): `oran-e2sim/e2sim` cmake+make e2sim_shared + `sudo make install` + `sudo cp src/base/e2sim.hpp
   /usr/local/include/e2sim/`; `libasn1c_e2.a` intact; install oran-interface headers if changed; `ns3-mmwave-oran/./ns3 build`.
2. ricplt + kpimon-go + rc Running. `pkill -9 -f scenario-zero`; clear RNIB (`/v1/nodeb/shutdown`).
3. `tshark -i any -f sctp -w cap.pcapng &`; run scenario-zero (pod-IP `10.244.0.13`, `--simTime>=100`, e2lteEnabled default true).
4. After gNB+eNB CONNECTED: confirm **LTE eNB** present in e2mgr `/v1/nodeb/states` → record its `ranName`. Restart kpimon to force KPM subscribe (regression).
5. Pick a UE IMSI attached to a mmWave cell + a different target mmWave cellId (from ns-3 log "mmWave eNB ... cellId").
6. `grpcurl … rc:7777 SendRICControlReqServiceGrpc` with `ranName=<lte-enb>`, `UEID.amfUENGAPID=<imsi>`,
   `ControlStyle 3`, `ControlActionId 1`, `TargetCellID=<target>`, `AckReq=ACK`.
7. **Assert:** ns-3 log `PerformHandover ----- handover from <old> to <target>`; `HandoverStart`/`HandoverEndOk` fire;
   pcap RICcontrolRequest→Acknowledge pair. KPM still flows (regression).

## Success criteria (M-RC2)
- [ ] ns-3 decodes Control Request → extracts imsi + targetCellId (logged, matches grpcurl payload).
- [ ] `PerformHandoverToTargetCell` runs on the LTE master RRC → secondary-cell HO triggered (X2 SendMcHandoverRequest).
- [ ] Handover observed in ns-3 traces (`HandoverEndOk` for the UE to the target cell), correlated in time to the control msg.
- [ ] ACK still on wire (RICcontrolRequest→Acknowledge); KPM path unaffected (regression).
- [ ] Re-runnable recipe documented; commits pinned on `dev/l-release` forks.

## Risks / landmines
- **Option-A precondition:** LTE eNB must connect to the L-release e2term + be targetable by `ranName`. **Verify live at step 4** (first thing). If it does NOT connect/register → escalate (fallback = wire master RRC into gNB).
- **ranP_List structure mismatch** → `ExtractTargetCellFromRanPList` returns 0 (no HO). Mitigation: xer dump on first run.
- **TargetCellID→ns-3 cellId mapping** unknown until live (NRCGI last-byte heuristic from reverted commit; validate).
- **UE must be associated to a mmWave cell** (`m_mmWaveCellSetupCompleted[imsi]==true`) else PerformHandover warns "not associated yet". Send control after attach settles; long enough simTime.
- `asn_check_constraints` infinite-loops on RC RANParameter PDUs (Phase-3) — never call.
- Callback on e2sim thread → MUST use `ScheduleWithContext` (not `Schedule`) for the HO.

## Todo
- [ ] oran-interface: `m_imsi` + `m_targetCellId` + `ExtractTargetCellFromRanPList` (RC-2.0, null-guarded)
- [ ] ns-3: LTE eNB callback → schedule TakeUeHoControl + PerformHandoverToTargetCell on master
- [ ] Build VM (strict order) GREEN
- [ ] Live: confirm LTE eNB E2 node + ranName (Option-A precondition)
- [ ] Live: grpcurl handover → HandoverEndOk in ns-3 traces + ACK on wire (M-RC2)
- [ ] Commit forks (oran-interface + ns3-mmwave-oran) `dev/l-release`; plan sync-back

## Open questions
1. Exact NRCGI encoding of grpcurl `TargetCellID` → ns-3 cellId. **RESOLVED:** `TargetCellID` is a HEX string; decoder's NRCGI last byte = its low byte (`"1113"`→0x13=19, `"1104"`→4, `"1105"`→5). Target cell N (2–5) ⇒ `TargetCellID="110N"`.
2. Does the L-release LTE eNB complete E2 Setup + appear with a targetable ranName? **RESOLVED: NO.** Only the mmWave gNB connects (single-node e2term sustains one association). ⇒ Option A dead; pivoted to Option B.

---

## Phase 5 result (M-RC2 GREEN, 2026-06-13)
xApp RIC Control → forced mmWave secondary-cell handover, completed end-to-end + verified live on oran-kvm-2.

**Live pivot A→B (decided with user mid-run).** Option-A precondition FAILED: only the mmWave gNB
(`gnb_734_373_16b8cef1`) is a live E2 node — the LTE eNB starts its E2 agent ("E2sim start in cell 1") but
never establishes with the single-node L-release e2term (e2term only ever addresses the gNB; e2mgr lists only
it; 5 E2 agents start, 1 connects). Phase-4 already showed control arrives at the **mmWave gNB** ⇒ the LTE-eNB
callback never fires. **Pivot to Option B:** trigger the handover from the **mmWave gNB callback**, locating the
LTE master RRC at runtime via NodeList (`FindMasterLteEnbRrc`). Canonical LTE-eNB path kept (harmless, dead here).

**Files changed (4):**
- oran-interface `model/ric-control-message.{h,cc}`: `m_imsi` (ControlHeader UEID.gNB_UEID.amf_UE_NGAP_ID via
  `asn_INTEGER2ulong`) + `m_targetCellId` (`ExtractTargetCellFromRanPList`: 4-level nested ranP_List → NRCGI last
  byte, fully null-guarded). Fixed a latent bug from the reverted attempt: the nested
  `RANParameter_STRUCTURE__sequence_of_ranParameters` named at file scope = incomplete-type in C++; use `auto`.
- ns3 `src/lte/model/lte-enb-net-device.cc`: canonical handover on `m_rrc` (master) — kept, dead in this testbed.
- ns3 `src/mmwave/model/mmwave-enb-net-device.cc`: **LIVE path.** `FindMasterLteEnbRrc()` + `MmWaveCellExists()`
  (NodeList scans); control callback → master `TakeUeHoControl` + `PerformHandoverToTargetCell` via
  `ScheduleWithContext` (e2sim run_loop thread → sim thread; FIFO so TakeUeHoControl runs first).

**Robustness fix.** An invalid target cell (e.g. 19) crashed ns-3 (`epc-x2.cc:693` NS_ASSERT "Missing infos for
targetCellId" → NS_FATAL). Added `MmWaveCellExists()` guard: the callback rejects a non-live mmWave target
("not a valid mmWave cell; ignoring control") — no crash. Verified live.

**Live evidence (scenario-zero, `--handoverMode=NoAuto`, pod-IP 10.244.0.13, gNB CONNECTED):**
grpcurl→rc:7777 (ranName `gnb_734_373_16b8cef1`, amfUENGAPID=1 = Imsi 1 on cell 2, Style 3, Action 1, AckReq=ACK):
- `TargetCellID=1105`→ decoded `targetCellId=5` → `RC forced handover … via LTE master RRC` →
  `TakeUeHoControl: UE 1 has external HO control` → `PerformHandover ----- handover from 2 to 5` →
  `SendHandoverRequest cell 2 rnti 1 → cellId 5` → `DoRecvHandoverRequest isMc=1` → `RecvHandoverRequestAck`
  (RLC fwd) → `RRC connection reconf completed on cell 5` → `path switch to LTE coordinator` →
  `Imsi 1 m_mmWaveCellSetupCompleted set to 1 for cell 5` → `RecvUeContextRelease: Remove UE 1 from eNB 2`.
- `TargetCellID=1104`→ `targetCellId=4`, full lifecycle again (cell 2→4), ns-3 stayed up.
- Invalid `1113`→19: `target cell 19 is not a valid mmWave cell; ignoring control`, ns-3 ALIVE.
- ACK: `Sending RIC Control Acknowledge` per control (format byte-verified Phase 4, encoder unchanged).
- Evidence: `oran-kvm-2:/home/uc/captures/phase5-ns3-1781327671.log`, `phase5-rc-1781327671.pcapng`.

**Build:** ns3 GREEN (oran-interface + lte + mmwave recompiled; e2sim `libe2sim_shared.so`/`libasn1c_e2.a` untouched).
**Notes / carry-forward:** TargetCellID→cellId is a hex "last-byte" test convention (document for xApp operators;
a real NRCGI↔cellId mapping = future work). `NoAuto` isolates the forced HO + bounds the log; default-mode
auto-HO coexists (`TakeUeHoControl` suppresses auto-HO for the controlled UE). RANFunctionDefinition
advertisement still deferred (D3). The dead canonical LTE-eNB path can be exercised iff LTE-eNB E2 connectivity
is ever fixed (separate effort).

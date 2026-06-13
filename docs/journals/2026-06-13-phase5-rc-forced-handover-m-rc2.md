# Phase 5: RC Forced Handover (M-RC2 Milestone)

**Date**: 2026-06-13
**Severity**: High (first action control)
**Component**: ns-O-RAN E2SM-RC control → mmWave handover in ns-3 EN-DC
**Status**: Resolved

## What Happened

Completed M-RC2 milestone: proved RC control loop's receive+*action* half end-to-end. An xApp sends RICcontrolRequest (funcId 300, Style 2, Action 1 = "force handover") specifying a UE IMSI and target mmWave cell. ns-3 e2sim decodes, forces a secondary-cell handover via the LTE eNB master RRC, and emits Control Acknowledge. Validated live on oran-kvm-2 against scenario-zero (EN-DC topology, `--handoverMode=NoAuto`). Multiple handovers (cells 2→5, 2→4) completed successfully; invalid targets (cell 19) rejected gracefully.

## The Brutal Truth

A prior session implemented Phase 5 then reverted all commits to redo "with Opus." We recovered the reverted code and analyzed it. The implementation was fundamentally wrong: it put the handover on the mmWave gNB's own RRC and called `LteEnbRrc::SendHandoverRequest` directly on it. **That cannot work.** In EN-DC, a secondary-cell handover is coordinated by the LTE eNB's master RRC via `PerformHandoverToTargetCell`, which uses master-only UE state and X2 SAP. A gNB RRC instance is isolated and can't orchestrate master state.

Then came the live pivot. Only the mmWave gNB registers as a live E2 node on the testbed (oran-kvm-2)—the LTE eNB starts its E2 agent but never connects to the single-node e2term. Control arrives at the gNB. So the canonical "target the LTE eNB" path was dead. We had to make the gNB callback work: callback finds the master RRC at runtime via NodeList, then schedules `TakeUeHoControl` + `PerformHandoverToTargetCell` on it via `Simulator::ScheduleWithContext` (the callback runs on the e2sim thread, not the ns-3 sim thread—`Schedule` would be unsafe).

That pivot—from wrong architecture to live-constrained workaround—took discipline. The reverted code taught us what not to do. The live testbed taught us what was actually wired.

## Technical Details

**Decode challenge**: Extract UE IMSI from ControlHeader `UEID.gNB_UEID.amf_UE_NGAP_ID` (maps directly to IMSI in this testbed). Extract target cell from the nested `ranP_List` → NRCGI, reading the last byte.

**The hex-encoding surprise**: RC treats `TargetCellID` as HEX string. First live test sent `TargetCellID="1113"` and the decoder produced cell 19 → ns-3 NS_FATAL (epc-x2.cc: no X2 socket for cell 19). Root cause: `"1113"` → 0x13 = 19 decimal. Solution: mmWave cells are 2–5; `TargetCellID "110N"` encodes cell N. Now we validate the target.

**Compilation landmine**: The reverted code had a latent incomplete-type C++ bug. A nested `RANParameter_STRUCTURE__sequence_of_ranParameters` was named at file scope—should have been `auto`. Compiler only complained when instantiated. Fixed and rebuilt.

**Crash prevention**: First invalid-target test (cell 19) crashed ns-3 (tried X2 socket to non-existent cell). Added `MmWaveCellExists()` guard: bad targets from the xApp are now rejected ("not a valid mmWave cell; ignoring control") instead of crashing.

**Code review catch**: An independent review flagged that the kept-but-dead LTE-eNB handover path lacked the `MmWaveCellExists` guard while still being a registered funcId-300 endpoint—an unguarded crash path. Resolved by removing the LTE-eNB handover block (keeping decode+ACK), since the LTE eNB isn't a live E2 node in this topology. Also added a null-guard on the E2AP `initiatingMessage` (attacker-input hardening). Rebuilt + smoke-tested.

## What We Tried

1. **Attempted path A (canonical, wrong architecture)**: Reverted code put handover on gNB's own RRC → doesn't have master state → can't orchestrate EN-DC handover
2. **Pivot to path B (live-constrained)**: Route control to master RRC via runtime NodeList lookup + thread-safe scheduler
3. **Hex-encoding assumptions**: Guessed decimal cell IDs, crashed on cell 19 → added validation
4. **Independent review of live code**: Flagged unguarded LTE path → removed it

## Root Cause Analysis

**Architectural misunderstanding in reverted code**: EN-DC handovers are master RRC's responsibility. A gNB RRC can't do it. The reverted author conflated "target is a gNB cell" with "gNB RRC should orchestrate it."

**Live testbed reality**: Only the gNB E2 agent connects to e2term. Control arrives at the gNB callback. The canonical LTE-eNB path is unreachable in this topology.

**The fix required a workaround**: gNB callback must schedule work on master RRC via `ScheduleWithContext` (async, thread-safe) because the callback runs on e2sim's thread, not the ns-3 sim main thread.

## Lessons Learned

1. **EN-DC architecture is deceptive**: Cells are dual-stack (eNB + gNB) but orchestration is master-only. "Target is a gNB cell" ≠ "gNB RRC does the work." Study the SAP chain (X2, RRC delegation) before coding.

2. **Live testbed reveals topological constraints**: The canonical path (LTE eNB) is dead on oran-kvm-2 because e2term isn't multi-node-aware here. Unit tests won't find this. Real E2 agents must register against actual deployed e2term.

3. **Thread safety in callbacks**: e2sim threads the message handler. Cross-thread scheduling must use `ScheduleWithContext` (context = destination event UID), not `Schedule`. Document this in the handover callback.

4. **Validation before crash**: Invalid targets from the xApp (fuzzing, misconfiguration, attack) caused ns-3 segfault. Guard with existence checks before any ns-3 resource access.

5. **Hex-encoding conventions are silent landmines**: TargetCellID `"110N"` = cell N in hex. No RFC, just format. Encode the convention in comments and validation code.

## Next Steps

**M-RC2 complete**: Handover control (decode + execute + ACK) proven end-to-end.

**Carry-forward**: 
- Real NRCGI ↔ cellId mapping (currently using the hex-encoding last-byte convention). Phase 7 concern if E2 standard defines canonical mapping.
- RANFunctionDefinition advertisement still deferred (Phase 6). RC v2.0 doesn't have the v1 `RIC-ControlStyle-Item` structure; spec review needed.

**Commits** (not pushed):
- oran-interface: `2bfd027` (rc-handover.cc new file, decode + LTE-RRC interaction)
- ns3-mmwave-oran: `f349063a` (MmWaveCellExists guard, ScheduleWithContext, null-check hardening)
- superproject: `f82df3a` (submodule pins)

**Artifacts**:
- Build: GREEN (ns-3 + libe2sim + libasn1c)
- Live test: imsi=1 targetCellId=5 → `PerformHandover from 2 to 5` → X2 isMc=1 → RRC reconf → old-cell release → ACK
- Invalid target (cell 19): rejected, ns-3 stayed up

**Plan reference**: `plans/260609-0127-rc-path-and-xapp-deploy-observe/phase-05-rc-forced-handover.md`

---

**Unresolved / Next**:
- Canonical NRCGI encoding (vs. hex last-byte guess); affects Phase 7 real deployment if network uses standard NRCGI ↔ cellId mapping
- RC v2.0 RANFunctionDefinition advertisement format (Q5 from Phase 4, still open)

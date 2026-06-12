# Phase 4: RC Receive + ACK (M-RC1 Milestone)

**Date**: 2026-06-13
**Severity**: Low (success milestone)
**Component**: ns-O-RAN E2SM-RC control-path → OSC L-release port
**Status**: Resolved

## What Happened

Completed M-RC1 milestone: proved the E2SM-RC control loop's receive+acknowledge half (no-op action) end-to-end against live deployed rc xApp on testbed. RICcontrolRequest (funcId 300, Style 3, Action 1) routed through e2term → ns-3 e2sim → xApp callback → Control Acknowledge sent back to e2term. Decoded wire traffic confirms RC-2.0 semantics (not nov2021). Live verification on oran-kvm-2 = host oran-kvm-3 (192.168.122.78).

## The Brutal Truth

This should have worked in Phase 0. The vendored OSC e2sim had the procedure code dispatch wired since day one—but RICcontrol (code 4) fell into `default:` and was silently dropped. Spent Phase 0 confused about why ns-3 was receiving 87B packets and emitting nothing. The fix was trivial (add the case statement), but the silence—no error, no log, just void—meant we debugged the wrong layer for two months. That's the cost of inherited code without explicit enumeration of what it handles.

## Technical Details

**Root gap**: Vendored e2sim had no dispatch for `ProcedureCode_id_RICcontrol` in the procedure code switch. RIC Control Requests arrived, matched the SCTP stream rule, got queued to e2sim's `ProcessMessage()`, and vanished at the default case.

**Fix applied**:
1. Added `case ProcedureCode_id_RICcontrol:` dispatch in e2sim message router
2. Wrote new `generate_e2apv1_control_acknowledge()` encoder (E2AP v03.01 spec: ACK contains RICrequestID + RANfunctionID only; no RICcontrolStatus IE in this asn1c tree)
3. Extracted control message source node via `get_function_id_from_control()` to route ACK back correctly

**RC-2.0 decode reshaping**: Re-enabled real `ric-control-message.cc` decoder. RC-2.0 flattened the v1-era nested CHOICE into `ric_controlHeader_formats.choice.controlHeader_Format1`. Updated header extraction; RAN-parameter decoding (`ranP_List`) intentionally stubbed—Phase 5 responsibility.

**The key debugging lesson**: Dispatch threw `std::out_of_range("No RAN Function with this ID exists for control")`. Initially looked like a logic bug. Root cause: control request targeted **mmwave gNB** (e2term SCTP routing by target node = gnb_734_373_16b8cef1), but only LTE eNB had legacy funcId-300 registered. gNB registered only KPM funcId 2. Fixed by registering RC control function (funcId 300) on mmwave-enb-net-device and defining its `ControlMessageReceivedCallback` (empty stub for Phase 5). **The lesson**: SCTP association routing isn't symmetric across node types. e2term knows the target node; we know the sender. Silent mismatches here cause dispatch failures that look like logic bugs. Add explicit logging for cross-node message routing in future ports.

Bonus finding: existing LTE-eNB stub callback would have crashed (`std::stoi("")`) if it had been dispatched—no-op ACK rewrite avoids the landmine.

## What We Tried

1. Assumed missing e2term handler → e2term logs showed messages arriving correctly
2. Assumed ns-3 queue corruption → traced incoming bytes as valid S1AP encapsulation
3. Assumed v1 decoder was broken → v1 code wasn't even being called (silent drop)
4. Added verbose logging at SCTP layer → found procedure code dispatch was the gate
5. Registered funcId-300 on gNB → dispatch succeeded, ACK generated

## Root Cause Analysis

Two independent issues that combined into confusion:
- **e2sim gap**: Procedure code dispatch table incomplete since import; no explicit error for unhandled codes
- **Cross-node routing**: e2term routes by target SCTP association (correct), but ns-3 dual-stack (eNB + gNB) hadn't registered control functions on both nodes; only KPM was multi-node aware

Shipping inherited code without explicit capability audits leaves these gaps. The code wasn't broken—it was intentionally incomplete. We just didn't know where.

## Lessons Learned

1. **Silent drops are worse than crashes**: When a message handler default-cases with no log, you debug the wrong layer. Add explicit `LOG_ERROR` or assert on unhandled procedure codes in future ports.
2. **Cross-node state sync is easy to miss**: Function registration must cover all nodes that can receive messages on that function. Consider a pre-deployment verification: iterate all node types × all function IDs, assert all expected combinations are wired.
3. **Test with live targets early**: The mmwave gNB vs. LTE eNB routing choice only surfaced in live e2term dispatch. Testbed setup (multi-node with specific target routing) found it; unit tests would not.
4. **Asn1c tree changes are opaque**: RC-2.0 flattened the CHOICE nesting from v1. No compile errors, just silent decoder mismatches if you don't trace the spec. Always diff the generated code or regenerate from scratch per release.

## Next Steps

**Phase 5 (Deferred)**: 
- Extract RAN-parameter list from `ranP_List` (currently stubbed)
- Map Control-Action ID to ns-3 xApp behavior trigger
- Implement real RC RANFunctionDefinition advertisement (v1's `RIC-ControlStyle-Item` tree is absent in RC-2.0; need spec review)
- Non-trivial: determine how RC v2.0 advertises supported styles/actions (Q5 open)

**Scope held to M-RC1**: Decode + ACK only. No ranP extraction, no action forwarding.

**Artifacts**:
- 8 files changed across 3 forks (oran-e2sim, oran-interface, ns3-mmwave-oran)
- Committed locally on dev/l-release (not pushed)
- libe2sim_shared.so rebuilt and installed on oran-kvm-2
- libasn1c_e2.a untouched
- ns-3 build: GREEN
- Wire pcap verified: RICcontrolRequest (frame 2205) → RICcontrolAcknowledge (frame 2207), 22 bytes, RANfunctionID 300

**Live verification result**: 
```
grpcurl -d '{"ranFunctionId":300,"ricControlStyle":3,"ricControlAction":1,"ackRequest":"ACK"}' localhost:7777 rc.pb.v1.RC/SendControl
→ ns-3 decoded RC-2.0 ControlHeader Format1 (ric_Style_Type=3, ric_ControlAction_ID=1)
→ emitted 22-byte Control Acknowledge
→ e2term received ACK at frame 2207 (SCTP stream for gnb_734_373_16b8cef1)
```

Note: ns-3 e2sim sends ACK with SCTP PPID 0 (not 70), so tshark 3.2.3 heuristically mislabels the frame as "X2AP"—cosmetic. e2term accepts it correctly.

---

**Unresolved / Next**:
- Q5: RC v2.0 RANFunctionDefinition advertisement format (spec vs. asn1c tree mismatch)—Phase 5 blocker, currently carrying open question from earlier planning

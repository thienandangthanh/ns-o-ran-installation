# Phase 6b Decision 4: Multi-gNB + Multi-UE Bilateral Fix — Implementation Complete; "SCTP Flakiness" Root-Caused to a Global client_fd (RESOLVED 2026-06-27)

**Date**: 2026-06-16 03:45 (correction appended 2026-06-27)  
**Severity**: High (Stage-D blocker — now resolved)  
**Component**: E2SM-RC control path (e2sim encode, TS xApp, ns-3 multi-node)  
**Status**: Code GREEN. The "inbound-SCTP" blocker was root-caused + **FIXED 2026-06-27** (process-global `client_fd` → per-instance `E2Sim` member). See the Correction below.

> ## ⚠️ CORRECTION (2026-06-27) — the root-cause analysis in this journal is WRONG
> The "multi-instance inbound-SCTP race / half-established association / deaf-from-start"
> diagnosis below is a **misdiagnosis**. The true cause was a **process-global `client_fd`**
> at `oran-e2sim/e2sim/src/base/e2sim.cpp:36` — a file-scope global, NOT a member of `E2Sim`.
> ns-3 runs one `E2Sim` per gNB in a single process, each `run_loop()` on its own detached
> thread; every agent's `connect()` overwrote the shared global, so the **last connector won**
> and ALL recv loops `recv()`'d that one socket — the other agents' sockets were never read
> (the kernel ACKs the data, userspace never `recv()`s it).
>
> The pcap actually shows all 5 agents bound **distinct** source ports (38471–38475) and each
> read ≥1 PDU — they were **not** "deaf." The single healthy node was simply the **last to
> INIT**, which is random per run — that is the entire "flakiness."
>
> **Fix:** move `client_fd` into `E2Sim` as a per-instance member (mirrors `m_client_src_port`).
> 2 lines. `oran-e2sim` `75257c7`, superproject pin `222ac76`.
> **Verified live:** a RIC Control fanned to all 5 nodes `gnb_734_373_16b8ce0{1..5}` →
> **5/5 receive + decode (funcId 3) + ACK** (was 1). Re-runnable: `scripts/phase6b-verify-multinode-recv.sh`.
> **Stage D (mock loop + TS rebuild) is unblocked.**

## What Happened

Implemented Decision 4 (bilateral fix for multi-gNB + multi-UE closed-loop): ns-3 now emits **unique, per-gNB identities** + **real served-cell NRCGI bytes** into E2 setup; TS xApp greps cell-map **case-insensitively**. Stage C′ discovery verified 5 distinct gNBs in E2MGR (was 1 before); Stage A′ regression confirmed rc path still drives handovers. But during Stage A′, a fifth gNB's control arrived on the wire (kernel-SACK'd) yet its e2sim never read it — exposing a latent multi-instance SCTP inbound race in ns-O-RAN that gates Stage D (mock loop with multiple targets).

## The Brutal Truth

The code work is solid and the encoding scheme is proven. But we've hit a pre-existing architectural flaw: in a single ns-3 process with 5 in-process e2sim agents sharing one recv thread pool, not all agents reliably read their inbound SCTP. This was masked when all gNBs collapsed into one node; now that controls route to *specific* nodes, it's exposed. Cell 4's control read cleanly; cell 5's didn't. This is not a regression — it's a land mine in the ns-O-RAN/e2sim codebase that only shows up at >1 gNB. We can't reliably drive multi-target handovers until this is fixed or worked around.

## Technical Details

**Code (5 edits, all committed or verified deployable):**
- `oran-e2sim/e2sim/src/base/e2sim.{hpp,cpp}`: Added `m_gnb_id_value`, `m_served_cells` members + `set_e2node_identity(uint32_t, std::vector<uint8_t>)` setter (mirroring `set_client_src_port` pattern).
- `oran-e2sim/e2sim/src/encoding/encode_e2apv1.{hpp,cpp}`: Extended `generate_e2apv1_setup_request_parameterized()` to accept `(gnbIdValue, servedCells)` params; replaced hardcoded gnb-id `[B5 C6 77 88]` with unique bytes `[0x16, 0xB8, 0xCE, N]` per cell; replaced `"reqpart"` placeholder with `[gnbId_4B || cellByte]` per served cell.
- `oran-interface/model/oran-interface.cc`: `DoStart()` parses `m_gnbId` → int N; calls `m_e2sim->set_e2node_identity(0x16B8CE00u | (N & 0xFF), {(uint8_t)N})`.
- `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc`: Dual-register RC under funcId **3** (TS hardcode) + **300** (Phase-4/5 golden-pcap parity).
- TS `ts_xapp.cpp` NodebHandler (~:334–366): Case-insensitive prefix grep (normalize both `message` and prefix to lowercase).

Build strict order (per CLAUDE.md): rebuild libe2sim, **re-copy headers** `e2sim.hpp` + `encode_e2apv1.hpp`, rebuild ns-3 (asn1c untouched).

**Stage C′ Results (discovery) — GREEN:**
E2MGR `/v1/nodeb/states` now shows 5 DISTINCT ranNames: `gnb_734_373_16b8ce0{1..5}`. Each `e2nodeComponentRequestPart` base64-decodes to `16B8CE0N0N` (N = 1..5 cell id). Per-gNB unique identity achieved; collision eliminated.

**Stage A′ Results (regression + multi-node routing) — MOSTLY GREEN:**
grpcurl funcId-3 to cell 4 → rc → ns-3 cell-4 → `RIC Control Request: imsi=1 targetCellId=4` → `RC forced handover: imsi=1 -> targetCellId=4` → ACK on wire. Confirms: (i) gNB-id bytes change did NOT regress rc path; (ii) rc routes to ONE node among 5 correctly; (iii) per-UE targeting (imsi decoded) live.

**Stage A′ Critical Finding (inbound-SCTP flakiness):** *(2026-06-27: the "only 4/5 logged `Received new data`" attribution was a MISREAD — the logs from 5 threads are interleaved and untagged, so per-instance attribution was unreliable. Re-analysing the pcap shows all 5 agents bound distinct ports and each read ≥1 PDU. The real cause is the global `client_fd` — see the Correction at the top.)*
In the same 5-gNB run, a control to cell 5 was wire-delivered and **kernel-SACK'd by ns-3** (evidence: DATA frame on port 38475 + SACK in pcap), yet cell-5's e2sim never logged `Received new data` (only 4/5 did). Cell-4's control processed fully. This is **pre-existing** (no SCTP-fd code touched in Decision 4), now **exposed** because controls no longer collapse onto one node.

Evidence: `oran-kvm-2:/home/uc/captures/phase6b-stageA-1781437269.{pcapng,ns3-1781437269.log}` — pcap shows DATA→38475 + SACK; ns3 log shows only cells 2,3,4,5 logged inbound (1 missing), and 5's line is absent entirely.

## What We Tried

Built and tested incrementally:
1. `set_e2node_identity()` plumbing + encoder parameterization — clean compile.
2. Stage C′ live run with 5 gNBs — E2MGR shows 5 nodes (proven unique identity).
3. Stage A′ grpcurl to cell 4 — handover succeeds (regression holds).
4. Observed Stage A′ with target cell 5 — control on wire, e2sim silent.

No retry of cell-5 yet; the inbound issue is the blocker, not a transient failure.

## Root Cause Analysis

> **❌ SUPERSEDED (2026-06-27) — this analysis is WRONG; kept for the record.** There is no
> SCTP connect/recv race and no "half-established association." The real cause is a process-global
> `client_fd` shared by all in-process `E2Sim` agents (see the Correction at the top). The text below
> correctly notes "each E2Termination spawns its own detached recv thread … blocking on
> `sctp_receive_data(client_fd)`" — but missed that `client_fd` was a **file-scope global**, so every
> thread blocked on the SAME fd (the last connector's), not "its own association." The "deaf from the
> start" conclusion is a misread of untagged interleaved logs.

Each E2Termination spawns its OWN detached recv thread (`oran-interface.cc:208`), each blocking on `sctp_receive_data(client_fd)` for its own association — there is NO shared thread/pollfd pool. So the race is per-instance, not a shared reader. Likely culprit is the SCTP client bind/connect path: all 5 agents bind distinct source ports (`m_e2localPort + cellId`) and `connect()` near-simultaneously to the same e2term, so one association may be left half-established (its `client_fd` recv stalls) while the others are fine. Fits the evidence: cell-5's e2sim logged neither its setup-response NOR the control (only 4/5 instances logged inbound), i.e. that agent was deaf from the start, not just for the control. This was hidden when all gNBs shared one identity — E2MGR coalesced them, rc routed to one unified "node," and only that one e2sim ever saw inbound. Now it's visible.

Not a ns-3 stack issue (ns-3 correctly ACK'd the segment); not an rc issue (rc sent the right port). It's an e2sim architectural assumption: "one gNB in this process" or "one dominant receiver." The testbed violates that.

## Lessons Learned

1. **Multi-instance shared-resource races hide in single-node scenarios.** Stress-testing with real topology (5 gNBs) earlier would have surfaced this. We traded integration completeness for perceived simplicity and found the cost late.
2. **E2 node identity must be baked into the agent before SCTP comes up.** The setter pattern is sound; the initialization order in E2Termination/DoStart must be ironclad.
3. **Testbed fidelity has a cost.** The single-node workaround (Option 1 from the decision tree) would sidestep this; we chose the proper multi-node path. Both are valid; multi-node exposed a latent bug.
4. **Kernel ACK ≠ app read.** A packet can be ACK'd by the OS and still miss userspace due to thread scheduling or fd registration lag.

## Next Steps

**Blocker resolution (required for Stage D):**
1. **Root-cause investigation:** Trace e2sim recv-thread startup in E2Termination. Does each agent register its fd before the thread loop? Is there a synchronization point?
2. **Mitigation options:**
   - **(a) Fix the race:** Make each per-gNB SCTP association fully establish before the next connects — stagger/serialize the per-instance `connect()`s, or have each agent verify its `client_fd` actually received the setup-response (retry) so no instance is left deaf.
   - **(b) Single-node workaround:** Route all multi-gNB controls to one healthy "representative" node (requires small TS override but no threading fix).
   - **(c) Defer multi-gNB Stage D:** Use Stage-D mock with only cell 4 (one healthy instance), prove the mock loop works single-target, then tackle the threading issue post-M-RC4.

**Recommendation:** (a) is the proper fix but needs e2sim internals expertise. Start with (c) as a parallel track: mock loop with cell 4 only, commit the proven Stage C′/A′ code, document the flakiness, and hand off the threading fix to the next session. This unblocks M-RC4 validation without requiring a deep e2sim rewrite now.

**Unresolved questions:** *(all RESOLVED 2026-06-27 — see Correction.)*
- ~~Is the recv race deterministic or load-dependent?~~ There is no recv race. The "winner" node varies per run only because it is the last thread to write the global `client_fd`.
- ~~Does the recv-fd registration happen before the poll loop starts in E2Termination?~~ N/A — the bug was a shared global fd, not registration ordering.
- ~~Is the flakiness in libe2sim's event loop, or in how e2sim agents are spawned/wired?~~ It was a shared global `client_fd` in libe2sim; fixed by making it a per-instance `E2Sim` member.

**Status (updated 2026-06-27):** Decision-4 code committed (`oran-e2sim a24e8f9`, pin `52f547e`). The "SCTP flakiness" blocker is **RESOLVED** — global `client_fd` made per-instance (`oran-e2sim 75257c7`, pin `222ac76`); verified live 5/5 nodes receive + ACK. Stage D (mock loop + TS rebuild) unblocked.

# Understanding Checklist — Phase 6b Live Closed-Loop Demo (M-RC4)

**Legend:** ⬜ not started · 🔄 in progress · ✅ mastered  ·  **STATUS: all items ✅ mastered (2026-06-14)**

**Builds on:** the Phase 4/5 RC path (`../../phase-04-rc-receive-ack.md`, `../../phase-05-rc-forced-handover.md` — funcId-300 RC receive+ACK and forced handover, both GREEN). This doc covers the *automated* loop (M-RC4): replacing manual grpcurl with the OSC **TS xApp**'s own decision, and the cell_map gap that blocks it.

Source material (verified against code this session):
- `docs/journals/2026-06-13-phase6b-live-closed-loop-demo.md`
- `../../phase-06b-live-closed-loop-demo.md`
- Code: `oran-e2sim/.../encode_e2apv1.cpp:271-276`, `oran-interface/model/oran-interface.cc:73-102,172`,
  `oran-interface/model/ric-control-message.cc:274`, `ns3-mmwave-oran/.../mmwave-enb-net-device.cc:655-667`

---

## Stage 1 — The Problem (motivation & the branches)

- ✅ **1.1 The goal of M-RC4** — automated loop = xApp's *own* decision drives the handover; critical path is TS→rc→ns-3 (AD skipped, QP later). vs manual grpcurl.
- ✅ **1.2 The loop's actors & hops** — TS → gRPC → rc → E2AP → e2term → SCTP → ns-3 → handover → ACK. Learner correctly located the break at the FIRST arrow (TS never emits).
- ✅ **1.3 Open loop vs closed loop** — decision-maker moves from human (grpcurl) to xApp (TS). Learner's envelope/letter analogy banked; corrected "ns-3 can't accommodate" → "TS never sends."
- ✅ **1.4 The funcId seam** — funcId = local dispatch key (port-like); spec ties meaning to OID, ID is node-assigned. 3 (TS) vs 300 (ns-O-RAN) → GetTrampoline(3) hit fallback → silent drop. Dual-register both → same callback; safe via deep-copy.

## Stage 2 — The Solution & the Blocker (what was done + why stuck)

- ✅ **2.1 Stage A fix — dual-register 3 + 300** — both → same callback; safe via per-call deep-copy. rc two validation layers (entry vs async-forward; UE IDs needed at Layer 2).
- ✅ **2.2 Stage B — TS deployed + pointed at rc gRPC** — `ts_control_api:grpc`, `ts_control_ep:…:7777`; baked at onboard → config change = re-onboard.
- ✅ **2.3 cell_map crux** — cell_map: NRCGI→owning E2 node; TS needs node identity to address a control. find() miss → silent `return`. build_cell_mapping() greps e2nodeComponentRequestPart once at startup.
- ✅ **2.4 Two independent failures** — (a) `"reqpart"` placeholder = no NRCGIs; (b) E2MGR lowercase vs TS uppercase grep. Either alone is fatal.
- ✅ **2.5 The discovery/delivery asymmetry** — discovery (setup→reqpart→cell_map) broken; delivery (explicit TargetCellID→NRCGI last byte) works. grpcurl skips discovery; TS can't.
- ✅ **2.6 The options (3 + a 4th the learner found)** — patch TS / synthetic ns-3 cells / defer; **Option 4 (learner): bilateral proper fix** = ns-3 emits real NRCGIs (fixes *a*) + TS case-insensitive grep (fixes *b*). Option 1 fallback works for 1 gNB only; Option 4 generalizes to N. Hex case is NOT spec-mandated (binary on wire; case is text-rendering; E2MGR likely Go-default lowercase). TS rebuild cost is the same either way → case-fix is nearly free once rebuilding.

## Stage 3 — The Broader Context (why it matters & what it changes)

- ✅ **3.1 What M-RC4 unblocks / limits** — proves a RIC-resident xApp's own decision drives ns-3 (a control-loop substrate). Limits persist: null-buffer RANFunctionDefinition stub, single-UE/gNB, real-QP InfluxDB schema Q8.
- ✅ **3.2 The integration-seam lesson** — same disease twice: spec fixes meaning (OID / binary value), leaves surface rep free (funcId integer / hex case). TS built for VIAVI-RSG; ns-3 gives placeholder; nobody documented the assumption.
- ✅ **3.3 Live state & reversibility** — uncommitted forks (SOUND), VM-only TS config (.orig backup), ns-3 stopped, trafficxapp running, 2 new scripts. Decision is forward, not cleanup.
- ✅ **3.4 Decision → next-steps** — M-RC4 is a user-gated BONUS beyond Phase 6's met exit (M-RC3). "Phase 7" in journal = build-repro (M-REPRO), orthogonal. Decision = fidelity-investment timing, NOT unblocking.

---

## Misconceptions revisited (resolved this session)
- ❌→✅ "ns-3 can't accommodate the request" → ns-3 *can* (grpcurl proved it); **TS never emits** (empty cell_map → silent return).
- ❌→✅ "ns-3's asn1c encoder sets the hex case" → encoder emits **binary**; case is a **text-rendering** choice in E2MGR (likely Go-default lowercase), not on the wire.
- ❌→✅ "the one-line TS case-fix is sufficient" → insufficient alone; `"reqpart"` still has zero NRCGIs → need ns-3 to emit real cells too (Option 4 = both).
- ❌→✅ "M-RC4 blocks Phase 6 / critical path" → M-RC4 is an **opt-in bonus**; Phase 6 exit (M-RC3 verdict) already MET; project not blocked.
- ❌→✅ "Option 2 is just infeasible" → infeasible only *if TS stays stock*; allowing a 1-line TS change dissolves it → enables the learner's **Option 4** (bilateral proper fix).

## Learner's original contribution (folded in)
- **Option 4 (bilateral robust fix)**: ns-3 emits real served-cell NRCGIs (fixes failure *a*) + TS case-insensitive grep (fixes failure *b*). Generalizes to N gNBs (Option 1's fallback is single-node only). Decision driver: will demos ever run >1 gNB? Yes → Option 4; only-ever-1 → Option 1 (KISS/YAGNI). Now folded into `../../phase-06b-live-closed-loop-demo.md`.

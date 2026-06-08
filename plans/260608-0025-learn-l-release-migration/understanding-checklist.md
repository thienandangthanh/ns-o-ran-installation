# Understanding the L-release Migration — Learning Checklist

> Running tracker. We work through this **incrementally**. A box gets checked only
> after you've *demonstrated* understanding (restate / quiz / read code), not just nodded.
> Legend: ⬜ not started · 🔄 in progress · ✅ mastered

---

## Stage 1 — The Problem (the WHY)
- ✅ 1.1 What O-RAN / Near-RT RIC / E2 / xApp actually are (the domain) — *note: xApp ≠ E2 node*
- ✅ 1.2 What ns-O-RAN is and why we simulate the RAN instead of using real hardware
- ✅ 1.3 "Bronze" vs "L-release" — what these are, why they differ
- ✅ 1.4 The core problem: ASN.1 schema v2→v3 changed → wire bytes mismatch
- ✅ 1.5 Why this migration was needed *now* (end goal: xApp dev on near-commercial RIC)
- ✅ 1.6 The branches/forks setup and why (oran-e2sim, oran-interface, ns3-mmwave-oran)

## Stage 2 — The Solution (the WHAT & HOW)
- ✅ 2.1 The 3-layer architecture: e2sim ↔ oran-interface (adapter) ↔ ns-3
- ✅ 2.2 Strategy: rebase e2sim on OSC, keep ns-3 stable, adapt in the middle. Why?
- ✅ 2.3 The phased approach (Phase 0→7) and why strict ordering (transport→E2AP→KPM)
- ✅ 2.4 Key wire-format changes: 8-byte TimeStamp, flat KPM model, funcId 2
- ✅ 2.5 The 3 live-only bugs — Bug 1 (funcId) ✅ · Bug 2 (SCTP port) ✅ · Bug 3 (double-free) ✅
- ✅ 2.6 Why each bug was invisible offline but fatal live — shared pattern: offline omitted real conditions
- ✅ 2.7 The M1–M6 validation harness — what each milestone proves
- ✅ 2.8 Edge cases & trade-offs (reduced-PM ✅, trampoline ✅, separate libasn1c ✅)

## Stage 3 — The Broader Context (the SO-WHAT)
- ✅ 3.1 What this unblocks — KPM telemetry foundation → monitoring/prediction xApps (NOT closed-loop yet)
- ✅ 3.2 What's deferred — E2SM-RC (control), per-UE KPM, S-NSSAI SD, funcId registry, valgrind soak
- ✅ 3.3 Reproducibility — strict build order (libe2sim → libasn1c_e2 → cp header → ns3 build)
- ✅ 3.4 Risks carried forward — ephemeral pod-IP hardcode, funcId-2 tied to xApp

---

## ✅ ALL STAGES MASTERED (verified via restate + quiz + live code reading)

### Key mental models locked in
- **The crux:** migration = re-encode everything to the v3 ASN.1 schema + relink (everything else follows).
- **Adapter pattern:** oran-interface absorbs version churn; ns-3 API unchanged; e2sim rebased free.
- **Why bugs hid:** offline simplified topology (no real xApp / single instance / dummy driver) omitted the real conditions.
- **Ownership contracts:** e2sim's encode is a "sink" (it frees) → calloc + don't delete.
- **Telemetry vs control:** KPM (read) unblocked; RC (write/steer) deferred.

---

## Notes / misconceptions to revisit
_(filled in as we go)_

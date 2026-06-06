---
title: Port ns-O-RAN to OSC Near-RT RIC L-release (E2AP v3.01 / E2SM-KPM v3.00)
slug: 260606-0505-port-ns-o-ran-to-l-release
status: planned
created: 2026-06-06
branch: dev/migrate-to-l-release
scope: KPM-only (E2SM-RC / closed-loop Traffic Steering deferred to follow-up)
blockedBy: []
blocks: []
related: [plans/ns-o-ran-development-plan.md]   # Bronze gym/xApp plan; its L-release xApp work depends on this migration
---

# Port ns-O-RAN to OSC Near-RT RIC L-release

## Context
Current ns-O-RAN is pinned to **Bronze** RIC (E2AP v01.00, E2SM-KPM v02.00.03, wineslab `oran-e2sim` v1.0,
Docker e2term `10.0.2.10:36422`). Target: connect the ns-3 RAN (`ns3-mmwave-oran`) to the **OSC L-release**
near-RT RIC deployed by `O-RAN-Testbed-Automation` on `oran-kvm-2`, so the lab can build Traffic
Prediction / Slicing / Steering xApps against a near-commercial-grade RIC. **Stabilize the E2 stack first
(transport → E2AP → E2SM-KPM); do not touch ns-3 scenario logic until E2 works.**

## Source → Target gap (crux)
| Aspect | Source (Bronze) | Target (L-release) |
|---|---|---|
| E2AP | v01.00 | **v03.01** |
| E2SM-KPM | v02.00.03 | **v03.00** |
| e2sim | wineslab v1.0 (`2209995`) | OSC `e2-interface` `da6f82f2` |
| e2term | Docker `10.0.2.10:36422` | k8s `ric-plt-e2:3.0.1`, **NodePort SCTP 32222**, ns `ricplt` |
| TimeStamp | 4 bytes | **8 bytes**; codec APER |
| KPM RAN func ID | 200 | bundled e2sim=2; kpimon-go expects specific ID → verify Phase 1 |

Breaking ASN.1 deltas: `ProtocolIE-Container` `87P11`→`85P21`; `ric_ReportStyle_Type`→`ric_Style_Type`;
ActionDefinition `Format1`→`Formats 1-5`; `MeasurementLabel` 17→24; `ric_KPM_Node_List` removed;
`QFI`→`QosFlowIdentifier`; `SNSSAI`→`S-NSSAI`; include `<>`→`""`.

## Locked decisions
- ns-3 **co-located on `oran-kvm-2`**, connects to E2Term node-IP:**32222**.
- **KPM-only** this migration; E2SM-RC deferred.
- e2sim **rebased onto OSC `e2-interface` `da6f82f2`**; ns-3 bits re-applied as **adapter layer** in `oran-interface/model/`.
- **Versioned M1–M6 harness**, version-pinned, re-runnable for future releases.
- VC: feature branch `dev/l-release` per fork (`origin`=our fork, `upstream`=original); no upstream PRs.
- Maintain **`implementation-notes.html`** (this plan dir) running: design decisions, deviations, tradeoffs, open questions.

## Resolved facts
- `oran-kvm-2` = Ubuntu 20.04.6 (same as `oran-kvm`); has only the testbed installed; ns-O-RAN installed gradually there. `oran-kvm` = Bronze reference for regression.
- kpimon-go local clone: `~/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-kpimon-go`.
- SSH granted to both VMs. Forks already exist.

## Phases
| # | Phase | File | Status |
|---|---|---|---|
| 0 | Freeze working Bronze baseline (regression anchor) | [phase-00](phase-00-freeze-bronze-baseline.md) | ✅ DONE (full pub-sub golden pcap) |
| 1 | Confirm L-release E2Term behavior (golden pcap) | [phase-01](phase-01-confirm-lrelease-e2term.md) | ✅ DONE (setup golden tshark-verified; indication deferred to P2/P5) |
| 2 | Standalone L-release e2sim test (M1–M5, no ns-3) | [phase-02](phase-02-standalone-e2sim-test.md) | ✅ DONE (M1–M3 green, golden-matched; vendored e2sim builds; harness done) · ⚠ M4/M5 subscriber-gated (Q4 escalated) |
| 3 | Port E2 Setup procedure (A SCTP + B E2AP) | [phase-03](phase-03-port-e2-setup.md) | ✅ DONE (M2 green, golden-matched) |
| 4 | Port E2SM-KPM RAN function definition (C) | [phase-04](phase-04-port-e2sm-kpm-ran-function.md) | ✅ DONE (v3.00 descriptor 1600 B, round-trip + live M3 green) |
| 5 | Port subscription handling | [phase-05](phase-05-port-subscription-handling.md) | ✅ DONE (M4 GREEN — real kpimon-go sub admitted; offline proof + live pcap) |
| 6 | Port KPM indication messages (D metric mapping) | [phase-06](phase-06-port-kpm-indications.md) | ✅ DONE (M5 GREEN — dummy v3 indications decoded by kpimon-go; M6 real-ns-3 → P7) |
| 7 | Reconnect ns-3 scenario-zero (end-to-end) | [phase-07](phase-07-reconnect-scenario-zero.md) | ◐ code-port DONE (M6 v3 model port + clean full ns-3 build + offline proof PASS); live M1–M6 run = next session |

## Validation milestones (harness `scripts/l-release-validation/`)
M1 SCTP · M2 E2 Setup · M3 RAN function accepted · M4 subscription · M5 dummy KPM · M6 real ns-3 KPM.
Each asserted via pcap/`tshark` on E2AP procedure codes + E2SM version OIDs. Manifest pins e2sim commit,
`asn1c` version, e2term image tag → re-runnable for M/N releases.

## Key dependencies
- VM setup: repo **already virtiofs-mounted** on `oran-kvm-2`. Remaining: install ns-3/e2sim build deps on `oran-kvm-2` (Phase 2).
- Phase order is strict 0→7 (each milestone gates the next). Phases 3–6 = the Phase-4 A/B/C/D code-area split.

## Key risks
APER wire mismatch (→ golden-pcap diff every milestone) · asn1c version drift (pin, never hand-edit generated C) ·
RAN-func-ID/OID mismatch (verify kpimon-go Phase 1) · NodePort SCTP reachability (validated standalone Phase 2).

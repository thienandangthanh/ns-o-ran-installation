---
title: RC control path + deploy-and-observe real xApps (post-KPM L-release)
slug: 260609-0127-rc-path-and-xapp-deploy-observe
status: draft (handoff — expand phases in fresh session)
created: 2026-06-09
branch: dev/migrate-to-l-release (continue on dev/l-release per fork)
scope: Observe deployed xApps → resolve KPM v3/v2 question → port E2SM-RC control path → enable offline-trained ML xApps
depends_on: KPM L-release migration (DONE, docs/l-release-migration.md)
report: plans/reports/handoff-260609-0127-xapp-version-audit-and-rc-roadmap.md
---

# RC Control Path + Deploy-and-Observe Real xApps

## Context (1 paragraph)
KPM L-release migration is DONE (ns-3 → kpimon-go → InfluxDB, M1–M6 GREEN). A version audit found the
**deployed testbed xApps speak v2.0-era E2SM** (kpimon-go=KPM v2.0, rc=RC v2.0/nov2021) while ns-O-RAN
emits **KPM v03.00** — a mismatch that M6 nonetheless passed (mechanism unknown). "L-release" pins the RIC
*platform*, not the bundled xApps' service-model versions. Goal of THIS plan: observe the real system, settle
the version question on evidence, then add the **RC (control) direction** — the genuinely new capability —
and set up **offline ML training** for the steering/prediction/anomaly xApps.

## Guiding principles
- **Observe before changing ns-O-RAN** (mirror KPM's bottom-up, golden-pcap discipline).
- **Match the deployed counterparty's contract** (the logic that forced funcId 2 — extend to service-model VERSION).
- **RC plumbing before intelligence** (prove receive+ACK+act with a trivial action first).
- **Offline training only** (O-RAN WG2 mandate; also faster — pure Python on collected data, no testbed loop).
- Re-runnable, version-pinned validation harness (extend the existing M-series to RC milestones).

## Phases (draft — expand into phase-XX files next session)

| # | Phase | Goal | Exit milestone |
|---|---|---|---|
| 0 | **Deploy & observe xApps** | Bring up kpimon-go + rc (+ ts/qp/ad) on current L testbed; tshark-capture their real on-wire E2SM version / OID / funcId / Control Format. Answer: do they run with **no SDR/USRP**? | Golden captures saved; behavior documented |
| 1 | **Resolve KPM v3↔v2** | From captures, explain how M6 passed (Format1 compat? octet-string leniency? partial parse?). Confirm whether v3 interop is robust or lucky. | Root-cause written; H1–H4 decided |
| 2 | **Version decision gate** | Decide: keep KPM v3.00 OR roll ns-O-RAN KPM → v2.0 to match deployed kpimon-go. Record rationale. | Decision in docs/l-release-migration.md |
| 3 | **RC ASN.1 base** | Add E2SM-RC asn to e2sim (e2-interface l-branch has NO RC asn — source from rc repo `e2sm-rc-2.0`/`nov2021` or m-branch). Regenerate via asn1c (never hand-edit). | RC types compile + round-trip |
| 4 | **RC receive + ACK (plumbing)** | ns-3/adapter: DECODE an E2SM-RC Control Request, send RIC Control ACK. (New direction — KPM was send-only.) Trivial/no-op action first. | M-RC1: Control Req decoded + ACK on wire |
| 5 | **RC act: forced handover** | Wire a trivial control action (e.g., forced handover) from rc xApp → ns-3 gNB actuation. | M-RC2: handover triggered by xApp control |
| 6 | **Data collection** | Run KPM scenarios; dump datasets (CSV/SQLite) for offline training. | Dataset captured + schema documented |
| 7 | **Offline ML training** | Train TS/AD/QoE models on collected data (pure Python, no testbed). | Trained model + eval metrics |
| 8 | **Inference xApp deploy** | Deploy trained model as inference xApp → control via rc → closed loop. | M-RC3: end-to-end closed loop |

## Key open questions (carry from report §7)
1. How did v3-sender / v2-receiver KPM decode succeed? (gates Phase 2)
2. Do kpimon-go/rc/ts/qp/ad run without SDR/USRP? (pure-sim viability)
3. Target RC version: `nov2021` (v01.03) vs `e2sm-rc-2.0` — match deployed rc.
4. Does deployed `rc` work end-to-end on this L testbed? Which Control Action Format?
5. If rollback: source of v2 KPM asn (wineslab Bronze tree vs re-vendor).
6. Real KPM/RC OIDs (replace dummy `OID123`).

## Risks (carry from report §6)
Ephemeral pod-IP hardcode (mmwave-helper.cc:300) · funcId 2 hardcoded · dummy OID123 ·
reduced-PM 5-metric cap · strict build order (header copy) · no valgrind soak.

## References
- Handoff report: `plans/reports/handoff-260609-0127-xapp-version-audit-and-rc-roadmap.md`
- KPM migration: `docs/l-release-migration.md`, `plans/260606-0505-port-ns-o-ran-to-l-release/`
- Deployed xApps: `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/xApps/{kpimon-go,rc,ts,qp,ad}/`
- RC xApp upstream: `https://gerrit.o-ran-sc.org/r/ric-app/rc.git` (branches h/k/m — no L)
- E2 sim base: `https://gerrit.o-ran-sc.org/r/sim/e2-interface.git` (branches k/l/m)

# Handoff Report — xApp Version Audit + RC Roadmap

**Date:** 2026-06-09 · **Author:** session handoff (post L-release-migration review)
**Purpose:** Self-contained handoff for a FRESH session. Captures a version-audit
finding that reframes next steps, plus the agreed strategy. No prior chat context needed.
**Companion plan:** `plans/260609-0127-rc-path-and-xapp-deploy-observe/plan.md`

---

## 0. TL;DR (read this first)

1. **L-release KPM migration is DONE & GREEN** (ns-3 KPM v3 → kpimon-go → InfluxDB, M1–M6). See `docs/l-release-migration.md`.
2. **NEW FINDING that reframes the future:** the **deployed** testbed xApps speak **v2.0-era** E2SM, NOT v3:
   - `kpimon-go` → **E2SM-KPM v2.0** (`kpm2_0.asn`, `e2sm2_0.asn`)
   - `rc` → **E2SM-RC v2.0 / nov2021** (`e2sm-rc-2.0.asn`, `e2sm-rc-nov2021.asn`)
   - ns-O-RAN `oran-e2sim` → **E2SM-KPM v03.00** (`e2sm-kpm-v03.00.asn`)
   - ⇒ KPM ends are **version-mismatched** (v3 sender vs v2 receiver), yet M6 reported GREEN. **HOW it passed is an open question** (§3).
3. **"L-release" = RIC platform version, not service-model version.** The platform (e2term/e2mgr images) is L; the bundled xApps still use v2.0 service models.
4. **Agreed strategy:** *deploy the real xApps → observe/capture behavior → then decide* whether to keep KPM v3 or **roll ns-O-RAN back to KPM v2.0 to match the deployed kpimon-go.** Do the **RC plumbing path** before the ML xApps. Train ML **offline** (spec-mandated; also far faster).

---

## 1. Two version axes (don't conflate)

- **O-RAN Alliance WG3 spec versions** — per component, independent: **E2AP v03.01**, **E2SM-KPM v03.00**, **E2SM-RC** (v01.03 "nov2021" / v2.0), E2SM-common.
- **OSC release train** (Bronze→…→K→L→M→N) — a *software bundle*. The release name pins **platform images**, and *loosely* a set of service-model versions — but **bundled xApps may lag** (see §2).

**How to verify a version in any repo (authoritative → weakest):**
1. `ls <e2sim>/asn1c/asn/vXX/` — **filenames ARE the version** (`e2sm-kpm-v03.00.asn`).
2. Generated header top comment: `* found in "e2sm-kpm-v03.00.asn"`.
3. On-wire: E2SM **OID** in the RANfunction descriptor. ⚠ ns-O-RAN currently sends **dummy `OID123`** (`oran-interface/model/kpm-function-description.cc:137`), not the real KPM OID — works on e2term 6.0.6, risky for stricter RIC.

---

## 2. Version matrix (verified 2026-06-09)

| Component | Repo (gerrit.o-ran-sc.org) | ASN.1 files present | Service-model version | Branches available | **l-release branch?** |
|---|---|---|---|---|---|
| e2sim (ns-O-RAN base) | `sim/e2-interface` | `e2ap-*-v03.01`, `e2sm-kpm-v03.00`, `e2sm-v03.01` | **E2AP v03.01 + KPM v03.00** | k / l / m | ✅ yes |
| kpimon-go (deployed) | `ric-app/kpimon-go` | `kpm2_0.asn`, `e2sm2_0.asn` | **KPM v2.0** | j / J / k / m | ❌ **no L** |
| rc (deployed) | `ric-app/rc` | `e2sm-rc-2.0.asn`, `e2sm-rc-nov2021.asn`, `e2sm-common.asn` | **RC v2.0 / nov2021** | h / k / m | ❌ **no L** |

**Implication:** neither deployed xApp has an L-release branch. The testbed pulls k/m-era xApps onto the L platform. So the *de-facto* interop target for service models is **v2.0**, even though e2sim offers v3.

**Local paths:**
- Deployed xApps: `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/xApps/{kpimon-go,rc,ts,qp,ad}/`
- kpimon-go golden clone: `~/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-kpimon-go/`
- ns-O-RAN e2sim asn: `oran-e2sim/e2sim/asn1c/asn/v03/`
- `.asn` provenance: vendored from OSC `e2-interface da6f82f2` in commit `3b90440 feat(e2sim): vendor OSC e2-interface da6f82f2 as L-release base`. The `develop` worktree (wineslab Bronze, `2209995`) has **no `asn/` dir** — confirms the v3 asn entered via this migration.

---

## 3. The KPM v3↔v2 mismatch: how did M6 pass? (must resolve)

M5/M6 reported GREEN: kpimon-go decoded **5 cell metrics** → InfluxDB. But sender=v3.00, receiver=v2.0. Candidate explanations to test (do NOT assume):
- **H1 — Format1 byte-compatibility:** E2SM-KPM IndicationMessage-Format1 (name↔value, the 5 reduced-PM metrics) may be byte-similar enough between v2 and v3 that a v2 decoder parses the v3 bytes for these specific simple fields.
- **H2 — OCTET STRING leniency:** the "4→8 byte TimeStamp" change is a content-length change inside an OCTET STRING; a v2 decoder may accept an 8-byte octet string without error.
- **H3 — partial/forgiving parse:** kpimon-go may extract the 5 names it expects and ignore structural deltas.
- **H4 — the deployed build differs** from the `kpm2_0.asn` source on disk.

**Why it matters:** if interop "works by luck" on 5 simple metrics, it will likely **break** for richer payloads (per-UE, more formats, RC). Resolving this decides the §4 version question.

---

## 4. The open decision: keep KPM v3, or roll back to v2.0?

| Option | Pro | Con |
|---|---|---|
| **Keep v3.00** (current) | forward-looking; matches e2sim L base; ready for future v3 xApps | mismatched with deployed v2 kpimon-go; relies on lucky decode (§3) |
| **Roll ns-O-RAN KPM → v2.0** to match deployed kpimon-go | exact contract match (same logic that forced funcId 2); robust interop now | partial reversal of the migration goal; must source v2 asn into OSC e2sim (e2-interface l-branch has only v3) |

**Decision gate:** make this call ONLY after §5 observation. Record rationale in `docs/l-release-migration.md`.

---

## 5. Agreed strategy (next session)

**Principle:** *observe the working system before changing ns-O-RAN.* Mirror the KPM bottom-up discipline for RC.

1. **Deploy & observe the real xApps** on the current L testbed (kpimon-go, rc, and the ts/qp/ad chain). Capture: do they come up? do they subscribe? what E2SM version/OID/funcId do they actually emit on the wire (tshark)? **Open curiosity to answer: do they run with NO SDR/USRP (pure sim/synthetic), or do they need real radio?**
2. **Resolve §3** (how M6 passed) from the captures.
3. **Decide §4** (v3 vs v2 KPM) from evidence.
4. **RC plumbing first** (before ML): ns-3 must **receive** an E2SM-RC Control Request + send **ACK** + act (e.g., forced handover). This is the *new* direction — KPM was send-only; RC is receive+act. Validate with the deployed `rc` xApp (a gRPC-driven control forwarder) + a trivial action.
5. **Data collection** (KPM already works) → dump datasets.
6. **Offline ML training** (TS/AD/QoE): O-RAN WG2 mandates offline training (Non-RT RIC/SMO); inference-only in Near-RT RIC. Also far faster — pure Python on collected CSV/SQLite, no testbed/ns-3 in the loop.
7. **Deploy trained model as inference xApp** → emits control via `rc` → closes the loop.

**OSC traffic-steering pipeline (deployed, modular):**
`KPIMON (metrics) → QP (QoE predict) + AD (anomaly) → TS (decision) → gRPC → RC → E2SM-RC Control/E2AP → ns-3 gNB → RIC Control ACK`
⇒ `rc` is the **"kpimon-go analog" for control** — a deployed xApp with a real on-wire contract to match.

---

## 6. Carried-forward risks / debt (from KPM migration)

- **Ephemeral pod-IP hardcode:** ns-3 → e2term **POD IP `10.244.0.48:36422`** hardcoded (`mmwave-helper.cc:300`), not the stable NodePort. Pod redeploy → new IP → silent connect failure. **First thing to check** if connectivity breaks.
- **funcId 2 hardcoded** to kpimon-go (`oran-interface.cc` trampoline switch). Future xApps need a funcId/OID-keyed registry.
- **Dummy `OID123`** instead of real KPM OID (§1).
- **Reduced-PM = 5 cell metrics only**; per-UE suppressed.
- **Strict build order:** libe2sim → libasn1c_e2.a → `sudo cp e2sim.hpp /usr/local/include/e2sim/` → `./ns3 build`. Skipping the header copy silently compiles against the stale API.
- **No valgrind soak** of the PDU double-free fix (verified one session/231 frames).

---

## 7. Open questions (for next session)

1. **§3 — how did v3-sender/v2-receiver KPM decode succeed?** (resolve via capture)
2. **Do kpimon-go / rc / ts / qp / ad run without SDR/USRP** on the current testbed? (pure sim viability)
3. **Which RC version to target** — `nov2021` (v01.03) vs `e2sm-rc-2.0`? Match whatever the deployed `rc` xApp emits.
4. **Does the deployed `rc` actually work** on this L testbed, end-to-end, and what Control Action style (Format) does it send?
5. **Source of v2 KPM asn** if rollback chosen — wineslab Bronze tree vs re-vendor into OSC e2sim.
6. **Real KPM/RC OIDs** — replace `OID123`; confirm what the deployed xApps require.
7. **L-release component→spec-version table** from OSC wiki/release-notes as a cross-check (release notes only partially document ASN.1 versions; `.asn` filenames are authoritative).

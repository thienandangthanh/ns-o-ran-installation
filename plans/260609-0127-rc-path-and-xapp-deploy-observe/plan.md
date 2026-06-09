---
title: RC control path + deploy-and-observe real xApps (post-KPM L-release)
slug: 260609-0127-rc-path-and-xapp-deploy-observe
status: Phase 1 DONE (M1 GREEN 2026-06-09); Phase 2 next
created: 2026-06-09
updated: 2026-06-09
branch: dev/migrate-to-l-release (continue on dev/l-release per fork)
scope: Observe deployed xApps → resolve KPM v3/v2 question → port E2SM-RC (RC-2.0) control path. ML = evaluate-only, not full pipeline.
focus: RC (control direction). NOT a full ML training pipeline.
depends_on: KPM L-release migration (DONE, docs/l-release-migration.md)
report: plans/reports/handoff-260609-0127-xapp-version-audit-and-rc-roadmap.md
---

# RC Control Path + Deploy-and-Observe Real xApps

## Context (why)
KPM L-release migration is DONE (ns-3 → kpimon-go → InfluxDB, M1–M6 GREEN). A version audit found the
**deployed testbed xApps speak v2.0-era E2SM** (kpimon-go=KPM v2.0, rc=RC-2.0/nov2021) while ns-O-RAN
emits **KPM v03.00** — a mismatch M6 nonetheless passed (mechanism unknown). "L-release" pins the RIC
*platform*, not the bundled xApps' service-model versions. **Goal of THIS plan:** observe the real system,
settle the version question on evidence, then add the **RC (control) direction** — the genuinely new
capability (KPM was send-only; RC is receive+ACK+act). **ML is out of scope as a pipeline** — we only
*evaluate* whether the existing ts/ad/qp xApps need training or can run inference as-is.

## Verified testbed state (2026-06-09, read-only probes)

| Fact | Value |
|---|---|
| Cluster | **Single-node**: `oran-kvm-2` is control-plane **and** worker (hostname == ssh name). No oran-kvm-3. |
| RIC platform | L-release `ricplt` fully Running (e2term-**alpha**, e2mgr, submgr, rtmgr, a1, dbaas, InfluxDB). |
| kpimon-go | **Already deployed & Running** (KPM v2.0, k-release `8bbbbb9`, `RAN_FUNC_ID=2`). |
| rc / ts / qp / ad | **NOT deployed.** |
| E2 nodes (gNB) | **NONE registered** — e2mgr `/v1/nodeb/states` empty ⇒ kpimon-go idle. Need ns-3 connected for live capture. |
| e2term SCTP | NodePort **`36422:32222/SCTP`**. ns-3 hardcodes ephemeral **pod IP** (`mmwave-helper.cc:~300`, handoff risk #1) → must retarget to `<oran-kvm-2-IP>:32222`. |
| Capture | `tshark` + `tcpdump` present on oran-kvm-2 (E2SM-dissect capability TBD — Phase 0). |
| e2sim on VM | **v3 KPM** system-installed (`/usr/local/lib/libe2sim.a`, v3 headers). |
| ns-3 | `/home/uc/ns-O-RAN-installation/ns3-mmwave-oran/` — built in prior sessions (CMake cache → **rebuild is fast**); scratch `scenario-zero..five.cc`. |

## xApp pins (commit_hashes.json) — all pure-synthetic, NO SDR/USRP

| xApp | Pin | Service model | Deploy |
|---|---|---|---|
| kpimon-go | k `8bbbbbb9` | **E2SM-KPM v2.0** | Docker → dms_cli onboard → install |
| rc | k `a2282ee` | **E2SM-RC 2.0** (asn: `e2sm-rc-2.0.asn`, `e2sm-rc-nov2021.asn`) | same; gRPC-driven control forwarder |
| ts | h `19e169b` | RMR-only | same |
| qp | l `47a35ca` | RMR-only | same |
| ad | l `f9f97b8` | RMR-only | same |

## ASN.1 sourcing (decided)
- **RC target = RC-2.0**, sourced from the **deployed rc xApp clone** (authoritative for the contract):
  `O-RAN-Testbed-Automation/.../xApps/rc/e2sm/e2sm-rc-2.0.asn`.
- The OSC **golden** `sim-e2-interface` (`OSC-repos/sim-e2-interface`) has **no RC** asn; e2-interface l-branch has no standalone RC. ⇒ do **not** source RC from e2sim.
- `worktrees/oran-e2sim-develop/.../e2sm-kpm-rc.asn` (merged KPM+RC, v1-era) = structural reference only, not the contract.

## Does Near-RT RIC enforce strict E2 ASN.1 version match?
**No global strict match.** e2term/e2mgr/submgr route E2AP PDUs by **RAN-Function-ID** and forward the
**opaque E2SM octet payload** without decoding it. Strictness is narrower:
1. **E2AP** (outer protocol) must be mutually intelligible — e2term 6.x is tolerant.
2. **The xApp's E2SM decoder is strict** — kpimon-go's v2.0 decoder must parse ns-3's v3.00 bytes (the §3 mismatch; Phase 1).
3. **funcId + OID** in E2 Setup `RANfunction-Item`: subscriptions key on funcId; OID advertised but e2term 6.0.6 does not hard-validate (ns-3 sends dummy `OID123` and still works — forward risk on stricter RIC).
⇒ "Match the deployed counterparty's contract (version included)" is the right discipline.

## Guiding principles
- Observe before changing ns-O-RAN (mirror KPM's bottom-up, golden-pcap discipline).
- Match deployed counterparty's contract (extend the funcId-2 logic to service-model VERSION).
- RC plumbing before intelligence (prove receive+ACK+act with a trivial action first).
- Re-runnable, version-pinned validation harness (extend M-series with M-RC milestones).

---

## Phases

| # | Phase | Goal | Exit milestone |
|---|---|---|---|
| 0 | Deploy & observe | Live KPM via ns-3→e2term; deploy rc; tshark-capture real E2SM version/OID/funcId/Control-Format; confirm no-SDR | ✅ **M0 DONE** — see `reports/phase0-capture-analysis.md` |
| 1 | Resolve KPM v3↔v2 | Explain how v2.0 decoder parsed v3.00 bytes (H1–H4) | ✅ **M1 DONE** — see `reports/phase1-kpm-version-rootcause.md` |
| 2 | Version decision gate | Keep KPM v3.00 vs roll ns-3 → v2.0; fold in NodePort + real-OID debt | **M2** decision in docs/l-release-migration.md |
| 3 | RC-2.0 ASN.1 base | Add `e2sm-rc-2.0.asn` to ns-3 e2sim; regenerate via asn1c; round-trip | **M3** RC types compile + round-trip |
| 4 | RC receive + ACK | ns-3 decodes RIC Control Request, returns Control Acknowledge (no-op action) | **M-RC1** Control Req decoded + ACK on wire |
| 5 | RC act: forced handover | Map a trivial Control Action → ns-3 gNB handover | **M-RC2** handover triggered by xApp control |
| 6 | xApp ML evaluation (scope-gate) | Inspect ts/ad/qp source: do they need offline-trained models, or ship runnable inference/defaults? Decide if ANY ML work is in-scope. | **M-RC3** written verdict + (if needed) minimal closed-loop demo path |

### Phase 0 — Deploy & Observe (executable; single-node oran-kvm-2)
**0.1 Pre-flight (read-only):** ricplt healthy, kpimon-go Running, InfluxDB up; record `oran-kvm-2` InternalIP → NodePort target `<IP>:32222` SCTP.
**0.2 Start capture BEFORE traffic:** `tshark -i any -f 'sctp' -w ~/captures/phase0-$(date +%s).pcapng` on oran-kvm-2 (or in-pod tcpdump on e2term-alpha). Keep running through 0.3–0.4.
- **Check tshark E2SM dissection** on a sample pkt; if absent, plan offline asn1c decode of the E2SM octet string.
**0.3 ns-3 → live KPM:** `cd /home/uc/ns-O-RAN-installation/ns3-mmwave-oran && ./ns3 build` (cached → fast; respect strict order: libe2sim → libasn1c_e2.a → `sudo cp e2sim.hpp /usr/local/include/e2sim/` → build). **Retarget connect to NodePort `<IP>:32222`** (not pod IP `10.244.0.48:36422`). Run KPM scenario → gNB appears in e2mgr `/v1/nodeb/states` → kpimon-go subscribes → RIC Indication(KPM) flows; verify kpimon-go logs decode + InfluxDB points (M5/M6 path).
**0.4 Deploy rc + capture control:** `cd /home/uc/O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC && sudo ./additional_scripts/install_xapp_ric_control.sh`. Confirm `ricxapp-rc-*` Running. **Verify whether rc self-emits a Control Request or needs an external gRPC driver/policy** (open Q2) — inspect rc docs/CLI; trigger one Control Request toward the E2 node; capture it.
**0.5 Decode & document:** `tshark -r *.pcapng -V -Y e2ap` (+ offline asn1c if needed). Write `reports/phase0-capture-analysis.md`: per-PDU table (type, funcId, OID, E2SM version, Control Format), SDR answer, RC-2.0-vs-nov2021 on-wire confirmation, raw bytes for Phase 1.
- **Cross-ref:** revise/append findings to old plan `plans/260606-0505-port-ns-o-ran-to-l-release` journal/reports if capture contradicts prior notes.
**Exit M0:** kpimon-go+rc Running; ns-3 gNB registered; KPM live path GREEN via NodePort; ≥1 RC Control Request captured+decoded; SDR-free confirmed; analysis report written.

### Phase 1 — Resolve KPM v3↔v2
Test with Phase-0 bytes: **H1** Format1 byte-compat (feed captured v3 bytes to a built v2 decoder), **H2** OCTET STRING leniency (4→8B TimeStamp), **H3** partial/forgiving parse (read kpimon-go decode path), **H4** deployed build ≠ on-disk `kpm2_0.asn` (pull asn/decoder from running pod). **Exit M1:** each H confirmed/refuted; verdict robust vs lucky.

### Phase 2 — Version decision gate
Decide keep-v3.00 vs roll-ns-3→v2.0 on Phase-1 robustness + roadmap fit. Fold in two carried debts as gating sub-tasks (bite any path): durable **NodePort connect** (replace `mmwave-helper.cc:~300`), real **KPM OID** (replace `OID123`, `kpm-function-description.cc:137`). **Exit M2:** decision + rationale in `docs/l-release-migration.md`.

### Phase 3 — RC-2.0 ASN.1 base
Source `e2sm-rc-2.0.asn` from the rc xApp clone → add to ns-3 e2sim ASN1c tree → regenerate via **asn1c** (never hand-edit generated C) → integrate into libasn1c_e2 build → re-copy headers to `/usr/local/include/e2sim/`. Round-trip encode→decode a sample RC ControlHeader/Message Format. **Exit M3:** compiles + round-trip GREEN.

### Phase 4 — RC receive + ACK (plumbing)
Extend funcId trampoline (hardcoded funcId-2→kpimon) into a **funcId/OID-keyed dispatch**; advertise an RC RANfunction in E2 Setup (real OID + funcId). Implement Control Request decode + Control Acknowledge encode in the E2 adapter; **no-op action first**; drive with deployed rc. **Exit M-RC1:** captured Control Request decoded by ns-3 + ACK on wire.

### Phase 5 — RC act: forced handover
Decode RC Control Message target (UE/cell + action) → call ns-3 mmwave handover API → verify handover in ns-3 traces, correlated to control msg; ACK reflects outcome. **Exit M-RC2.**

### Phase 6 — xApp ML evaluation (scope-gate, NOT a pipeline)
Inspect `xApps/{ts,ad,qp}/` source: do they (a) ship a runnable model / sane defaults for inference, (b) hard-require an offline-trained artifact, or (c) fetch from AIML-FW? Reference `OSC-repos/{ric-app-ts,ric-app-ad,ric-app-qp,ric-app-qp-aimlfw,aiml-fw}`. **Decide if any ML work is in-scope at all** — prefer running existing inference over training. If a closed loop is cheaply reachable (TS→gRPC→rc→ns-3), document the minimal path. **Exit M-RC3:** written verdict; closed-loop demo path IF trivial, else explicitly deferred.

---

## Critical files
- Connect/pod-IP hardcode: `ns3-mmwave-oran/src/.../mmwave-helper.cc:~300` → NodePort `<oran-kvm-2-IP>:32222`.
- funcId trampoline + RANfunction reg + dummy OID: `oran-interface/.../oran-interface.cc`, `oran-interface/model/kpm-function-description.cc:137`.
- e2sim asn tree: `oran-e2sim/e2sim/asn1c/asn/v03/` (+ RC-2.0 added Phase 3).
- RC-2.0 asn source: `O-RAN-Testbed-Automation/.../xApps/rc/e2sm/e2sm-rc-2.0.asn`.
- Install scripts: `O-RAN-Testbed-Automation/.../additional_scripts/install_xapp_*.sh`; pins `O-RAN-Testbed-Automation/commit_hashes.json`.
- Docs: `docs/l-release-migration.md`. Old plan to cross-ref: `plans/260606-0505-port-ns-o-ran-to-l-release`.

## Verification (end-to-end)
- **M0:** `kubectl get pods -n ricxapp` → kpimon-go+rc Running; e2mgr `/v1/nodeb/states` lists ns-3 gNB; kpimon-go logs decode metrics; InfluxDB receives points; pcap has E2 Setup + RIC Subscription + RIC Indication(KPM) + RIC Control Request; decoded report lists OID/funcId/format/version.
- **M-RC1/2:** pcap shows Control Request→Acknowledge pair; ns-3 logs show handover triggered by control.
- Re-runnable: extend M-series harness with M-RC milestones; xApp commits already pinned.

## Risks
Pod-IP vs NodePort connect (fix first) · funcId-2 hardcode · dummy `OID123` · reduced-PM 5-metric cap ·
strict build order (header copy) · no valgrind soak · rc may need external gRPC driver (Phase-0 verify) ·
tshark E2SM dissector gap (offline asn1c fallback).

## Phase 0 result (M0 GREEN, 2026-06-09)
- KPM live path reproduced (subscribe→indication→decode→InfluxDB, 5 cell metrics); v3→v2 "lucky decode" repeatable (Phase-1 input).
- RC control PROVEN on wire: grpcurl→rc→E2SM-RC ControlMessage Format1 (funcId 300)→ns-3 RX 87B ×3 (no ACK yet, expected).
- **NodePort SCTP NOT viable** (handshake OK then reset→ns-3 SIGSEGV); **pod-IP `10.244.0.13:36422` is the working path.** Connect target fully arg-overridable (`--e2TermIp`, `--ns3::MmWaveHelper::E2Port`) — no source edit. Rewrites Phase-2 NodePort debt.
- Ops gotchas: always `pkill -9` ns-3 (zombie holds SCTP src port); restart kpimon AFTER gNB CONNECTED to force subscribe.
- Full detail + reproducible procedure: `reports/phase0-capture-analysis.md`.

## Phase 1 result (M1 GREEN, 2026-06-09)
Root cause settled on **ground-truth captured bytes** (Python pcapng parser + v3 e2sim asn1c E2AP split + built v2 decoder). **Verdict = SPLIT:**
- **MESSAGE (carries metrics→InfluxDB) = ROBUST.** IndicationMessage Format1 + whole MeasurementData/Info family byte-identical v2.0↔v03.00 (only v3 diff = 3 post-extension-marker optionals in MeasurementLabel, never sent). Real captured 194B v3 msg → v2 decoder = `RC_OK 194/194`, values `[2154,765,0,86,3]` + 5 metric names exactly = InfluxDB fields. Compatible **by ASN.1 design**.
- **HEADER = BROKEN but inert.** v2 `TimeStamp SIZE(4)` vs v3 `SIZE(8)` + always-present sender strings ⇒ real 38B v3 header → v2 = `RC_WMORE consumed=0` (**fails**). Phase-0 "Indication Header format=1" was a **salvaged partial**: `wrapper.c` returns the partial struct on RC_WMORE; asn1c set `present=Format1` pre-failure; `control.go` logs only `present` and **never reads header content** (sender-field reads commented out; kpimon uses its own ingest timestamp). Decode failure silently swallowed (stderr `header RC_WMORE`).
- **H-scorecard:** H1 confirmed-robust · H2 confirmed (header breakage point) · H3 confirmed (salvaged *failed* parse via `asn_decode` non-`_complete` + wrapper RC_WMORE branch) · H4 refuted (binary == on-disk `kpm2_0.asn`; `pm_Containers` code is dead legacy).
- **Phase-2 steer:** keep KPM v03.00 (monitoring payload genuinely compatible; rollback gains nothing, RC work is v3/RC-2.0). Header mismatch = latent risk only if a future xApp parses the indication header.
- Full detail + reproducible harnesses: `reports/phase1-kpm-version-rootcause.md`.

## Open questions
1. ns-3 already built — rebuild fast (cached). **Resolved:** cache hit, fast.
2. Does deployed **rc** self-emit or need a gRPC driver? **Resolved:** gRPC-driven forwarder (:7777 `SendRICControlReqServiceGrpc`); does NOT self-emit.
3. Can VM tshark dissect E2SM? **Resolved: NO** (tshark 3.2.3, no E2AP dissector). Use xApp/ns-3 asn1c logs + offline asn1c; E2AP=SCTP PPID 70.
4. RC-2.0 from rc repo clone — **decided** (OSC golden sim-e2-interface has no RC). On-wire 2.0-vs-nov2021 inconclusive by OID (ns-3 dummy) → confirm Phase 3.
5. If KPM rollback chosen: source of v2 KPM asn (wineslab Bronze tree vs re-vendor). *(open, Phase 2)*

## References
- Handoff: `plans/reports/handoff-260609-0127-xapp-version-audit-and-rc-roadmap.md`
- KPM migration: `docs/l-release-migration.md`, `plans/260606-0505-port-ns-o-ran-to-l-release/`
- OSC upstreams (non-exhaustive): `OSC-repos/{sim-e2-interface,ric-app-*,ric-plt-*,aiml-fw}`
- Deployed xApps: `O-RAN-Testbed-Automation/.../xApps/{kpimon-go,rc,ts,qp,ad}/`

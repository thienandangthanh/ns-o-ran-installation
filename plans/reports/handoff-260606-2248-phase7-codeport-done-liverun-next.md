# Handoff — Phase 7 code-port DONE (v3 model + clean ns-3 build + offline proof) → live M1–M6 run next

**Date:** 2026-06-06 · **Branch (super):** `dev/migrate-to-l-release` · **oran-interface fork:** `dev/l-release` · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/`
**Scope this session:** Phase 7 **code-port half** (user decision: port real `model/` pipeline to v3 + clean full ns-3 build + offline proof; **defer live RIC run**). The first-ever full ns-3 compile of the oran-interface module against E2SM-KPM v3.00.

## Locked decisions (this session)
- **D1 Path X:** ported the REAL ns-3 `model/` KPM pipeline to v3 (NOT the standalone `examples/` builder). The real emit path was already wired (`MmWaveEnbNetDevice::BuildAndSendReportMessage` → `MmWaveIndicationMessageHelper` → `KpmIndicationHeader/Message` → `m_e2term->SendE2Message`); it was just built on v2 ASN.1. `examples/kpm-indication-builder.h` was the proven-correct v3 reference to mirror.
- **D2 scope:** code + DoStart + clean full build + offline proof this session; **live M1–M6 deferred**.
- **D3 DoStart = Option A**, **D4 v3 in model/**, **D5 metric set = reduced-PM Du cell (5 names)** — all applied.

## What this session did (Stages A–F all GREEN)
- **A — DoStart adapter** (`model/oran-interface.cc`): build `argv={prog, ricAddr, ricPort, NULL}` and call `run_loop(3, argv)`. **CORRECTION to research:** vendored libe2sim `read_input_options` reads ONLY argv[1]=ip/argv[2]=port when `argc==3`, and **`argc>3` → `exit(1)`** — so the 6-arg sketch would have killed the node. gnbId/plmnId come from the registered descriptor; clientPort from the SCTP client.
- **B — header → v3** (`model/kpm-indication.cc`): `IndicationHeader-Format1` = senderName/Type/vendorName + **8-byte `colletStartTime`** (htobe64 of real `m_timestamp`). Dropped the entire v2 `GlobalE2node_ID`/nodeType switch (not in v3 header). ABI of `KpmRicIndicationHeaderValues` + ctor preserved.
- **C — message → v3 flat model** (`model/kpm-indication.cc`, `model/asn1c-types.*`, helpers): v2 nested PM-container build (`FillPmContainer`/`FillOCuUp`/`FillOCuCp`/`FillODu`) **deleted**; replaced by flat `MeasurementData`(N `MeasurementRecordItem`) + `MeasurementInfoList`(N `MeasurementInfoItem` w/ `measName`), record[i]↔info[i]. `MeasurementItem` refactored from v2 `PM_Info_Item_t` to a plain `(name, tagged long/double/RRC)` holder (v2 `PM-Info-Item.h`/`MeasurementValue.h` absent in v3). All `Add*PmItem`/`Fill*Values` helper signatures preserved → zero churn in `mmwave-enb-net-device.cc`.
- **D — descriptor reconciliation** (`model/kpm-function-description.cc`): advertised measNames **9 RLC/L1M → 5 reduced-PM Du cell** to match the helper emit: `TB.TotNbrDlInitial.Qpsk`, `.16Qam`, `.64Qam`, `RRU.PrbUsedDl`, `DRB.MeanActiveUeDl`. (kpimon gate: `no_of_cell_metrics == len(tmpCellKpi)`.)
- **E — clean full ns-3 build on oran-kvm-2** (`./ns3 build` → 0 errors, `scenario-zero` links). First full compile surfaced LATENT module-wide v2→v3 issues, fixed:
  - v2→v3 renames (`SNSSAI.h`→`S-NSSAI.h`, `SNSSAI_t`→`S_NSSAI_t`, …).
  - **E2SM-RC excluded** from build (`CMakeLists.txt` + `oran-interface.h` includes): OSC e2sim install ships no E2SM-RC asn1c types and nothing in the KPM path uses it (deferred per KPM-only migration). Inline compile-stubs for `RicControlMessage`/`RicControlFunctionDescription` keep lte/mmwave TUs compiling.
  - **Callback trampoline** (`oran-interface.cc`): v3 e2sim `register_subscription_callback` takes raw `void(*)(E2AP_PDU_t*)`, not `std::bind`. Added a global `g_cbMap` (mutex-guarded) + static trampolines for funcId **200 (KPM)** and **300 (RC)** dispatching through the map. ns-3 registers KPM under **200** (verified `mmwave-enb-net-device.cc:637`).
  - **`libasn1c_e2.a`** (infra finding): OSC `libe2sim*` do NOT bundle the asn1c type defs (`asn_DEF_*` all undefined). Built a separate archive from `e2sim/asn1c/*.c`, installed `/usr/local/lib/libasn1c_e2.a`, linked after the shared lib. **Documented in `docs/linux-vm-dependency-setup-guide.md`** (required for any fresh VM rebuild).
- **F — offline model proof PASS** (`examples/kpm-v3-model-proof.cc`, new): drives the REAL `KpmIndicationMessage`/`KpmIndicationHeader` with the 5 named cell metrics → **header 38 B (matches Phase-6 reference) + message 192 B, exit 0**, no ASN.1 constraint failure. (Offline file-logging mode does NOT exercise the ASN.1 encode — `IsOffline()` skips the item-adds + writes CSV — so a dedicated proof was needed.)

## Code-review outcome (0 critical, 1 high, 3 med, 5 low) — HIGH FIXED
- **H1 (FIXED):** the port dropped the v2 `ASN_STRUCT_FREE(...Format1, …)` → leaked one Format1 sub-tree per indication (header + message + soft-fail path); unbounded on the periodic live loop. Restored recursive frees + nulled the choice pointer (no double-free vs the shell `delete`). Also fixed latent UB: `m_buffer/m_size` were uninitialised → init to 0/null up-front (soft-fail return + dtor `free(m_buffer)` were UB). Rebuilt + re-ran proof: still 38 B/192 B PASS.
- **M1 (made loud):** negative metric wraps in the `unsigned long` integer record → now `NS_LOG_WARN` (all reduced-PM metrics ≥0, so no live impact).
- **M3 (made loud):** trampoline no-ops for any funcId ∉ {200,300} → now `NS_LOG_WARN` at registration. **Live footgun:** if you change the ns-3 KPM funcId (e.g. to **2** to match the Phase-5/6 standalone/kpimon-go proof), add a `TrampolineN` + `GetTrampoline` case or the callback silently never fires.
- **M2 / L1 (documented, deferred):** see open questions.

## Files changed (oran-interface `dev/l-release`, working tree — NOT committed)
| File | Action |
|---|---|
| `model/oran-interface.cc` / `.h` | DoStart argv adapter; callback trampoline; E2SM-RC compile-stubs |
| `model/kpm-indication.cc` / `.h` | v3 header (Stage B) + v3 flat message (Stage C); H1 frees; soft-fail; warns |
| `model/asn1c-types.cc` / `.h` | `MeasurementItem` v2→plain holder; v2 L3-RRC/MeasResult wrappers stubbed (OFF the KPM path — verified) |
| `model/kpm-function-description.cc` / `.h` | advertised measNames 9→5 (reduced-PM Du) |
| `CMakeLists.txt` | link `libasn1c_e2.a`; exclude E2SM-RC sources |
| `examples/CMakeLists.txt` + `examples/kpm-v3-model-proof.cc` (NEW) | offline model proof target |
| `docs/linux-vm-dependency-setup-guide.md` | **libasn1c_e2.a build step (REQUIRED)** |
| `plans/.../phase-07-*.md`, `plan.md` | status sync |
| `plans/reports/` | researcher×2, dev, debugger, code-review reports + this handoff |

**Suggested commits when approved** (oran-interface fork `dev/l-release`, then superproject):
- `feat(e2sm-kpm): port ns-3 KPM model pipeline to E2SM-KPM v3.00 (flat MeasurementData/Info)`
- `fix(e2-term): adapt DoStart to libe2sim run_loop(argc,argv); std::function callback trampoline`
- `build(oran-interface): link libasn1c_e2.a; exclude deferred E2SM-RC; reduced-PM Du metric set`
- `test(l-release): Phase-7 offline model proof (kpm-v3-model-proof)`

## Build recipe (reproducible, oran-kvm-2 = 192.168.122.78, hostname oran-kvm-3)
```bash
# one-time (if /usr/local/lib/libasn1c_e2.a missing — see docs/linux-vm-dependency-setup-guide.md):
cd /home/uc/osc-installation/e2-interface/e2sim/asn1c && gcc -O2 -fPIC -I. -c *.c && sudo ar rcs /usr/local/lib/libasn1c_e2.a *.o && rm -f *.o
# build + offline proof:
cd /home/uc/ns-O-RAN-installation/ns3-mmwave-oran
./ns3 configure --enable-examples && ./ns3 build         # scenario-zero links clean
./ns3 run kpm-v3-model-proof                              # -> hdr 38 B + msg 192 B, PASS, exit 0
```
Repo is **virtiofs-mounted** on the VM (`/home/uc/ns-O-RAN-installation` == host repo) → host edits are live on the VM; build over SSH.

## START CHECKLIST — next session (LIVE M1–M6 end-to-end)
File: `plans/260606-0505-port-ns-o-ran-to-l-release/phase-07-reconnect-scenario-zero.md` (Todo last item).
1. **funcId reconciliation (BLOCKER for M5/M6 live):** ns-3 registers KPM under **200**; the Phase-5/6 standalone proof used **2** because kpimon-go expected it. Determine what funcId kpimon-go L-release subscribes under. If ≠200, change the `RegisterKpmCallbackToE2Sm(200,…)` call in `mmwave-enb-net-device.cc:637` (and lte:1076) AND add a matching `TrampolineN`+`GetTrampoline` case in `oran-interface.cc` (else callback silently never fires — M3).
2. **M2 — UE items vs cell descriptor:** the v3 message appends UE `m_ueIndications` items after cell items into the SAME record/infoList, but the descriptor advertises only the 5 cell names. If scenario-zero's Du report adds UE items, `no_of_cell_metrics` ≠ `len(tmpCellKpi)` → kpimon rejects. Decide: separate report style for UE, or descriptor advertises the union, or suppress UE items for the cell style. Verify against live kpimon parser.
3. **L1 — sender m_size guard:** `mmwave-enb-net-device.cc:1585` checks `duMsg!=nullptr` but not `m_size>0`; a soft-fail (constraint) message would send a 0-length payload. Add `&& duMsg->m_size>0` if constraint failures ever occur live (none in offline proof). (External ns-3 src — left unchanged this session to minimise churn.)
4. **Live run:** per Phase-5/6 handoff gotchas — e2term POD IP `10.244.0.48:36422` over cni0 (not NodePort); clear RNIB (`PUT /v1/nodeb/shutdown`); restart kpimon AFTER node CONNECTED; copy pcap to a 4.x-tshark host for the authoritative E2SM-KPM decode; SSH-255 at teardown is harmless. Run: `./ns3 run "scenario-zero --e2TermIp=10.244.0.48 --enableE2FileLogging=false --simTime=5"` (small first), capture pcap, run harness M1–M6.
5. **Finalize:** README L-release section, `docs/` migration writeup, submodule pins (forks + super), finalize `implementation-notes.html`.

## Carried open questions
- kpimon-go L-release KPM **funcId** (200 vs 2) — read its subscription/`tmpCellKpi` setup live (gates #1, M3).
- Does kpimon decode the **cell** style with `measName` (we emit `PR_measName`, not `measID`)? Phase-6 dummy used `measID`; confirm live.
- **S-NSSAI SD** "100" copied as 3 ASCII bytes from the reference — live kpimon may want 3-byte BCD.
- H1 leak fix unverified under load (valgrind NOT installed on VM) — confirm no growth during the live periodic loop.

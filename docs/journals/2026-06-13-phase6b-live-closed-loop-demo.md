# Phase 6b: Live Closed-Loop Demo — TS Cell Map Gap Blocks Automation

**Date**: 2026-06-13 18:40  
**Severity**: High (automated loop BLOCKED; manual rc-path still GREEN)  
**Component**: ns-3 e2sim `encode_e2apv1.cpp`; TS `NodebHandler`; rc gRPC ↔ ns-3 forced handover  
**Status**: Partially resolved (M-RC4 deferred pending decision on 3 options)

---

## What Happened

Attempted to close the automated loop: OSC **Traffic Steering xApp** → gRPC `SendRICControlReqServiceGrpc` → **rc** → **E2SM-RC** → **ns-3** forced mmWave handover + RIC Control Acknowledge. This replaces the manual `grpcurl` commands of Phase 4/5 with TS's own steering decisions (mock QP first, then real).

**Net result**: Stage A (RC funcId 3 registration in ns-3) ✅ **GREEN**, Stage B (TS deploy + config) ✅ **DONE**, Stage C (gNB cell-map bootstrap) ❌ **BLOCKED**. Decision pending on 3 options to unblock. All code changes **uncommitted**; ns-3 stopped.

---

## The Brutal Truth

We have a **hidden gap in TS's cell-resolution logic** that nobody documented: TS can advertise a control request but can't *resolve* which E2 node owns a target cell because it relies on a 100% parsing dependency that ns-3's e2sim doesn't satisfy. Worse, the gap is invisible — TS accepts the control, prints "cell_map.find() missed", and silently drops it. No error logs, no exceptions. You don't realize the loop is broken until you trace the gRPC and find nothing on the rc side.

The frustration is **we built and verified the entire rc path (funcId 3, handover, ACK) manually with `grpcurl`, so we *know* the machinery works.** The gap is purely in the TS→E2 integration layer — a mismatch between what TS expects (served-cell NRCGIs in uppercase hex from E2MGR) and what ns-3 provides (a hardcoded placeholder with no cells at all). It's not a design flaw; it's a data-format assumption that's fine for VIAVI-RSG but breaks against ns-3.

---

## Technical Details

### Stage A — Register RC funcId 3 in ns-3 ✅ GREEN

**Code changes** (uncommitted, both submodules):

1. `oran-interface/model/oran-interface.cc`:
   - Added `Trampoline3` mirroring `Trampoline300` (lines ~77).
   - `GetTrampoline()` switch (line 85): added `case 3: return Trampoline3;`.
   - No-warn guard (line 161): added `&& ranFunctionId != 3`.

2. `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc` (~line 652):
   - `RegisterSmCallbackToE2Sm(3, …)` calling same `ControlMessageReceivedCallback`.
   - **Crucially**: kept a second call `RegisterSmCallbackToE2Sm(300, …)` to preserve Phase 4/5 grpcurl-300 parity (regression hedge).

3. `ns3-mmwave-oran/src/lte/model/lte-enb-net-device.cc` (~line 1066): aligned to funcId 3 (LTE eNB doesn't connect but kept consistent).

**Build**: `./ns3 build` on VM (cached, ~14s). E2MGR advertises ranFunctions 2 (KPM) + 3 + 300. ✓

**Verification (live run)**:
```bash
grpcurl -d '{"RanFuncId":3,"TargetCellID":"1105",...}' \
  service-ricxapp-rc-grpc-server.ricxapp:7777 rc.RC/SendRICControlReqServiceGrpc
# Response: Success Response
```

Evidence chain:
- e2sim logs: `RIC Control Request carries RAN function id 3` ✓
- ns-3 logs: `targetCellId=5 ranFunctionId=3 imsi=1` ✓
- Handover: `RC forced handover … via LTE master RRC; from 2 to 5` ✓
- ACK: `Generated RIC Control Acknowledge (funcId=3)` ✓
- pcap: Control Request carries funcId 3 byte. ✓

Artifacts: `/home/uc/captures/phase6b-stageA-{pcapng,log}`.

**code-reviewer verdict**: SOUND (0 crit/high/med; dual-registration safe because `RegisterSmCallbackToE2Sm` deep-copies the OCTET_STRING per call).

**Bonus finding**: rc has **two validation layers**:
- Layer 1 (`rcService.go:35`): gRPC entry point → "Success Response" (accepts if ranFuncId/TargetCellID/GUAMI/RanName/PlmnID non-empty).
- Layer 2 (`rcControl.go:119-135`): async forward (ALSO requires non-empty `gNBCUUEF1APID` + `gNBCUCPUEE1APID`). First attempt omitted these → forwarded NOT, ns-3 saw nothing. TS sets `gNBCUUEF1APID/gNBCUCPUEE1APID = ue_id`, so TS is fine.

### Stage B — Deploy + configure TS xApp ✅ DONE

- `install_xapp_traffic_steering.sh` → `ricxapp-trafficxapp-…` Running.
- Config baked at onboard (dms_cli): edited `…/xApps/ts/xapp-descriptor/config-file.json` to set `ts_control_api:"grpc"` and `ts_control_ep:"service-ricxapp-rc-grpc-server.ricxapp:7777"`. Backup `.orig` kept.

**TS internals** (`ts_xapp.cpp`):
- `send_grpc_control_request()` sets `ranfuncid(3)`, `controlstyle(3)/actionid(1)`, `amfuengapid=ue_id`, `gnbcuuef1apid/gnbcucpuee1apid=ue_id`, GUAMI hardcoded. ✓
- **Cell resolution**: `TargetCellID = highest_throughput_cell_id`, then **`cell_map.find(target)` — on miss does `return` (drops control, silent).**
- `build_cell_mapping()` runs **once at TS startup** (main:890). TS must restart after gNB registers to populate `cell_map`.

### Stage C — gNB + E2MGR cell-map bootstrap ❌ BLOCKED

**Root cause** (found via live trace):

ns-3's e2sim sets `e2nodeComponentRequestPart` = hardcoded **`"reqpart"`** placeholder (`oran-e2sim/e2sim/src/encoding/encode_e2apv1.cpp:271-276`). This field is what **TS's `NodebHandler` parses to build the cell map.**

TS `NodebHandler.build_cell_mapping()` logic:
```cpp
// From E2MGR GET /v1/nodeb/{ranName} → e2nodeComponentRequestPart field
string reqpart = nodeb["e2nodeComponentRequestPart"];  // = "reqpart" (placeholder, no NRCGIs)
// grep-match uppercased ranName gNB-id hex (e.g., "16B8CEF1") inside reqpart
// Extract base64-decode + search for hex → NRCGI tuples → cell keys
cells.push_back(message.substr(i, 10));  // e.g., "16B8CEF105" → cell 5
```

**Two independent failures**:
1. Placeholder `"reqpart"` has **no served-cell data** → no NRCGIs to extract.
2. ~~E2MGR returns hex as **lowercase** (`16b8cef1`) while TS greps **uppercase** (`16B8CEF1`) → can't match even if cells were present.~~ **[SUPERSEDED — misdiagnosis; see Correction (2026-06-16) below.]**

Result: `cell_map` is **empty** → `cell_map.find(target_cell)` always misses → TS drops every control at the `return` statement (silent failure, no logs, no exceptions).

> **Correction (2026-06-16):** Failure #2 above is a **misdiagnosis**. Live Stage C′ verification (2026-06-14, captures on `oran-kvm-2:/home/uc/captures/phase6b-stageA-*`) showed E2MGR REST renders `e2nodeComponentRequestPart` = `base64(hex(raw bytes))` with the hex in **UPPERCASE** (`16B8CE0202`); only the *ranName* gNB-id suffix is lowercase (`16b8ce02`, and that case is set by ns-3, not E2MGR). Stock TS `toupper`s its needle, so it **already matched** the uppercase haystack — **case never blocked discovery**. The real second blocker (beyond the `"reqpart"` placeholder) was that all in-process mmWave e2sim agents shared **one gNB-id → one ranName**, so E2MGR coalesced them into a single node. Both were fixed by Decision 4 (ns-3 emits a per-gNB unique gNB-id + real served-cell requestParts; the TS lower-both change is **defensive normalisation, not the unblocker**). See memory `phase6b-cellmap-gap-and-option4` and `plans/260609-0127-rc-path-and-xapp-deploy-observe/phase-06b-live-closed-loop-demo.md` (`## DECISION 4`). Note: the `ts_xapp.cpp` fix comment still says "lowercase" — also wrong, same misdiagnosis.

**Decoder side (rc → ns-3) works fine**: rc hex-decodes the `TargetCellID` string to bytes; ns-3 reads NRCGI **last byte** (`oran-interface/model/ric-control-message.cc:274`). So a key like `"16B8CEF105"` maps to cell 5 (consistent with Phase-5 `"1105"`).

**Symptom**: ns-3 CONNECTED in E2MGR; E2MGR serves the gNB with `ranFunctions` 2+3+300; TS starts OK. But `kubectl logs ricxapp-ts-*` shows zero `send_grpc_control_request` calls — TS never steers because `cell_map.find` always misses.

---

## Decision Pending (3 options, no single path forward)

**Option 1 (Recommended): Minimal TS patch + rebuild**
- When `cell_map.find(target)` misses, fall back to the single connected E2 node (resolve via `ran_name`, `plmn_id`, `nbId` from `get_nodeb_list()` top-level fields, which parse correctly).
- Scope: ~10 lines in `ts_xapp.cpp`.
- Rebuild trafficxapp image + dms_cli re-onboard.
- **Pro**: yields a real TS→rc→ns-3 loop; minimal code change.
- **Con**: revisits the "no TS rebuild" lean (though that was the funcId seam; this gap is separate + unavoidable).
- **Likelihood**: ~high, solves the immediate blocker.

**Option 2: ns-3 synthetic served cells (TS stock)**
- Make ns-3 emit crafted served-cell NRCGI bytes in TS's uppercase-hex grep form.
- Edit `encode_e2apv1.cpp:271-276` to generate instead of placeholder.
- **Pro**: keeps TS stock (no rebuild).
- **Con**: ~~likely **BLOCKED by the uppercase/lowercase mismatch**~~ **[corrected 2026-06-16: no case mismatch — E2MGR renders UPPERCASE, matching TS's uppercase grep; see Correction above]**; requires reverse-engineering TS's exact hex encoding + deciding on cell ID encoding scheme.
- **Likelihood**: ~low, brittle.

**Option 3: Defer automation, document gap**
- Keep TS stock; mark M-RC4 as "blocked-by-TS-cell-map-gap" in roadmap.
- Retain Stage-A grpcurl→ns-3 handover as proof of rc-path correctness.
- Proceed to Phase 7 with manual rc proof.
- **Pro**: no code changes; acknowledges the gap is a TS/ns-3 integration issue.
- **Con**: defers the "automated loop" milestone.
- **Likelihood**: ~acceptable if TS patch is too risky.

---

## What We Learned

1. **Cell-map bootstrap is TS-critical but poorly tested.** The `build_cell_mapping()` runs once at startup, greps a hardcoded field format, and silently fails if cells aren't there. No telemetry, no fallback. For a testbed that uses ns-3 (which provides a placeholder), this silently breaks.

2. **Data-format mismatches hide in integration seams.** TS was written for VIAVI-RSG (uppercase hex, real served-cells in `e2nodeComponentRequestPart`). ns-3 provides a placeholder. Neither party documented the integration assumption. The result: two systems that individually work fine but can't talk to each other. *(Per the 2026-06-14 verification this "uppercase hex" is correct and matches our E2MGR too — the actual seam was the placeholder + shared ranName, not case.)*

3. **Two-layer validation in rc is deep.** The gRPC entry accepts the control; the async forward layer does more validation. This is good for robustness but makes debugging harder — you see a "Success Response" but then nothing happens downstream.

---

## Next Steps

**Immediate (decision required)**:
1. **Decide**: pick Option 1, 2, or 3 above.
2. If **Option 1**: patch `ts_xapp.cpp` `send_grpc_control_request()` with fallback logic, rebuild trafficxapp, re-onboard, re-run Stage C.
3. If **Option 2**: patch `encode_e2apv1.cpp` to emit uppercase hex NRCGIs, rebuild ns-3, re-run Stage C.
4. If **Option 3**: document gap in `docs/l-release-migration.md` (M-RC4 blocked-by) + proceed to Phase 7 with grpcurl proof.

**After decision**:
- **Stage D** (mock QP inject → deterministic handover): awaits Stage C unblock.
- **Stage E** (real QP → full loop): awaits Stage D.
- **Stage F** (validate + document): commit code across forks, add M-RC4 validation script, update roadmap.

**Documentation** (post-decision):
- Update `phase-06b-live-closed-loop-demo.md` with decision + outcome.
- Update `docs/l-release-migration.md` (Phase 6 status, M-RC3 DONE, M-RC4 TBD).
- Write `/ck:journal` entry (this file).

---

## Artifacts This Session

- Scripts: `scripts/phase6b-stage-a-grpcurl3-verify.sh`, `scripts/phase6b-start-ns3.sh` (virtiofs-shared, runnable on VM).
- VM evidence: `/home/uc/captures/phase6b-stageA-*.{pcapng,log}`, `/home/uc/captures/phase6b-ns3-*.log`.
- Code: oran-interface (funcId 3), ns3-mmwave-oran (dual-register 3+300). **All uncommitted.**
- TS config: testbed tree only (`config-file.json` + `.orig` backup; not in repo).

---

## Unresolved / Next

1. **Option decision**: which path to unblock cell-map? (recommend Option 1 but user call).
2. **TS rebuild risk**: if Option 1 chosen, what's the rebuild/re-onboard timeline?
3. **Option 2 feasibility**: if preferred, can we reverse-engineer the exact NRCGI encoding TS expects from E2MGR?
4. **Phase 7 readiness**: if Option 3 chosen, is grpcurl→handover proof enough for Phase 7 kickoff, or must M-RC4 be done?

**Status: Awaiting user decision on M-RC4 approach. Stage A GREEN (manual rc-path proven). Stage B DONE (TS deployed). Stage C BLOCKED (cell-map empty due to data-format mismatch). M-RC3 ✓, M-RC4 pending.**

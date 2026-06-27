# Phase 6b: Live Closed-Loop Demo — TS xApp → rc → ns-3 (M-RC4)

**Date**: 2026-06-13
**Type**: Live testbed execution (the Phase-6 deferred, now user-gated open)
**Goal**: Automated closed loop — OSC **TS xApp** decision → `SendRICControlReqServiceGrpc` → **rc** → E2SM-RC → **ns-3** forced mmWave handover + ACK. Replaces the manual `grpcurl` of Phase 4/5 with TS's own decision logic.
**Exit M-RC4**: pcap shows a RIC Control Request whose trigger was a **TS gRPC call** (not grpcurl); ns-3 log shows the correlated `handover from X to Y`; ACK on wire.

## Decisions (user-gated, 2026-06-13)
- **Target**: OSC closed loop (not the PPO/ns-o-ran-gym RL track).
- **funcId seam**: register RC under **funcId 3** in ns-3 (TS hardcodes 3). No TS image rebuild.
- **TS driver**: **mock/synthetic QP first** (deterministic handover proof) → **then real QP** (full live loop).

## Key environment facts (verified this session)
- **Repo is virtiofs-shared**: host `…/ns-O-RAN-installation` == VM `/home/uc/ns-O-RAN-installation`. Edit locally → instantly on VM → build/run on VM via `ssh oran-kvm-2`. (Commit at end; no push/pull in the loop.)
- RIC `ricplt` healthy (e2term-alpha, e2mgr, submgr, InfluxDB). `ricxapp`: kpimon-go ✓, **rc ✓**, hw-go ✓. **TS/QP/AD not deployed.**
- E2MGR RNIB: 1 leftover gNB `gnb_734_373_…`, `DISCONNECTED` (no ns-3 running). Clean before runs.
- Working RC path (Phase 4/5): connect to **e2term POD-IP**:36422 (NodePort SCTP non-viable); rc gRPC on :7777; `pkill -9` ns-3 between runs (zombie holds SCTP src port); restart kpimon AFTER gNB CONNECTED.
- VM under sustained load (~4.2; rc RMR threads spin). ns-3 is CPU-heavy → run with bounded `simTime`.

---

## Stage A — Register RC funcId 3 in ns-3 (code; our forks)
Files (all local = VM via virtiofs):
1. `oran-interface/model/oran-interface.cc`
   - Add `Trampoline3` mirroring `Trampoline300` (key 3) — after :77.
   - `GetTrampoline()` switch (:85): add `case 3: return Trampoline3;`.
   - No-warn guard (:161): add `&& ranFunctionId != 3`.
2. `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:652-657` — register RC under **3** (keep a second `RegisterSmCallbackToE2Sm(300, …)` call so Phase 4/5 grpcurl-300 + golden pcap parity still hold → zero regression; both dispatch to `ControlMessageReceivedCallback`).
3. `ns3-mmwave-oran/src/lte/model/lte-enb-net-device.cc:1066` — align to 3 (inert: LTE eNB never connects, but keep consistent).
- **Build** on VM: `cd ns3-mmwave-oran && ./ns3 build` (cached → fast; respect lib order if e2sim touched — it is not).
- **Verify (regression first)**: clean RNIB → run scenario-zero (pod-IP) → gNB CONNECTED → drive **grpcurl with `ranFuncId:3`** (adapt `phase4-rc-live-run.sh`) → ns-3 logs decode + `handover` + ACK on wire. Confirms funcId-3 path before adding TS.
- Code-review the diff (`code-reviewer`).

## Stage B — Deploy + configure TS xApp
- `cd /home/uc/O-RAN-Testbed-Automation/.../Near-Real-Time-RIC && sudo ./additional_scripts/install_xapp_traffic_steering.sh`.
- Discover rc gRPC service: `kubectl get svc -n ricxapp | grep rc` → set TS `ts_control_api:"grpc"`, `ts_control_ep:"<rc-grpc-svc>:7777"` in TS `config-file.json`; re-onboard/install if config baked at build.
- Verify `ricxapp-ts-*` Running; gRPC channel to rc established (TS logs).

## Stage C — gNB + E2MGR cell-map bootstrap
- Clean RNIB (`PUT /v1/nodeb/shutdown` via e2mgr pod), `pkill -9` stale ns-3.
- Start tshark (`-f 'sctp' -w …`), then ns-3 scenario-zero (pod-IP connect, `simTime` long enough for TS loop, e.g. 100), restart kpimon after CONNECTED.
- Verify gNB **CONNECTED** in `/v1/nodeb/states`; record its cell ids (the NRCGI/cellId set ns-3 advertises).
- Cross-check TS `build_cell_mapping()` (E2MGR REST :3800) populated `cell_map` with those cells. TS must (re)start AFTER cells present.

## Stage D — Mock QP injection → deterministic handover
- Inspect ric-app-ts `test/app/{qp_xapp,ad_xapp}` + `test/populatedb` on VM; pick the lightest injector (bundled mock QP **or** a small RMR `TS_QOE_PREDICTION` (30002) sender) crafting a prediction where a **valid target mmWave cell** beats serving by > A1 threshold.
- Ensure `TargetCellID` maps to ns-3 form (Phase-5: cell N ⇔ hex `"110N"`); pick a target that `MmWaveCellExists()` accepts (Phase-5 used 4/5).
- **Observe**: TS `prediction_callback` → `send_grpc_control_request` (funcId 3) → rc → ns-3 `handover from X to Y` + ACK. Capture pcap + ns-3 log.

## Stage E — Real QP → full live loop
- Deploy QP: `sudo ./additional_scripts/install_xapp_qoe_predictor.sh` (plain Python; self-trains lazily).
- Ensure InfluxDB has CellReports (ns-3 running → kpimon-go → InfluxDB); verify schema match vs QP `qp_config.ini` (`CellReports`, `pdcpBytesDl/Ul`, `nrCellIdentity`) — open-Q8.
- TS now receives real `TS_QOE_PREDICTION` from QP → emits control when threshold crossed → ns-3 handover. Observe full automated loop (no mock, no grpcurl).

## Stage F — Validate + document + finalize
- Extend M-series: add **M-RC4** assertion to `scripts/l-release-validation/` — pcap has Control Request correlated to a TS gRPC emit; ns-3 log shows handover. Add a re-runnable `scripts/phase6b-closed-loop-run.sh`.
- Update `plan.md` (Phase 6 live demo → DONE), this phase doc (results), `docs/l-release-migration.md` (Phase 6 live), write `/ck:journal` entry.
- Commit across forks (oran-interface, ns3-mmwave-oran) + superproject pins per version-control strategy (branch `dev/l-release` on forks; no push unless asked).

---

## Risks / mitigations
- **funcId pass-through** (TS 3 → rc → ns-3 3): registering both 3+300 removes regression risk; Stage-A grpcurl-3 test de-risks before TS.
- **Cell-id format** (`110N` hex): pick a target cell verified via `MmWaveCellExists`; invalid target is rejected (no crash, Phase-5 guard).
- **E2MGR cell-map empty** → TS silently drops control: enforce ordering (gNB CONNECTED + cells in E2MGR **before** TS emits; restart TS if needed).
- **rc mandatory fields** (`rcService.go:35`: E2NodeID/TargetCellID/GUAMI/RanName/PlmnID): mock injector must populate all; TS hardcodes GUAMI (VIAVI), maps ue_id→amfUENGAPID (= ns-3 IMSI, Phase 5).
- **AD cold-start hang**: AD is optional / off the control path — **skip** for this demo.
- **VM load + ns-3 CPU**: bounded `simTime`; one ns-3 at a time; `pkill -9` between runs.
- **TS image config baking**: if `config-file.json` is baked at onboard, a config change needs re-onboard (dms_cli) — discover at Stage B.

## Open questions (resolve during run)
- rc gRPC service DNS/port exact value (Stage B discovery).
- Mock injection mechanism: bundled `test/app` mock QP vs hand-rolled RMR sender (Stage D).
- QP/AD InfluxDB column/measurement match vs kpimon-go schema (open-Q8; Stage E).

**Plan ref**: `plans/260609-0127-rc-path-and-xapp-deploy-observe/plan.md` (Phase 6, M-RC3 → M-RC4 live).

---

## Live session progress & findings (2026-06-13, paused for deep-understanding)

**Net state**: Stage A GREEN, Stage B done, Stage C was BLOCKED on a TS cell_map gap → **DECISION (2026-06-14): Option 4 chosen** (multi-gNB + multi-UE bilateral fix). Full implementation plan in **`## DECISION 4 (2026-06-14)`** below. All Stage-A code changes UNCOMMITTED. ns-3 stopped.

### Environment (verified live)
- **Repo is virtiofs-shared**: host `…/ns-O-RAN-installation` == VM `oran-kvm-2:/home/uc/ns-O-RAN-installation`. Edit locally → instantly on VM → `ssh oran-kvm-2` to build/run. (`ssh oran-kvm-2` = host oran-kvm-3, user `uc`, passwordless sudo.)
- e2term connect = **pod-IP `10.244.0.13:36422`** (NodePort SCTP non-viable). rc gRPC = svc `service-ricxapp-rc-grpc-server.ricxapp:7777` (ClusterIP 10.101.81.179; rc pod 10.244.0.24). `grpcurl` at `/usr/bin/grpcurl`; proto `…/xApps/ts/ext/protobuf/rc.proto`.
- gNB: ranName `gnb_734_373_16b8cef1`, plmn `373437`. scenario-zero: `simTime` max **100** (DoubleChecker 0.1–100), use `--handoverMode=NoAuto`. gNB CONNECTED ~10s after launch.
- VM under sustained load (~4.2; rc `rc-rt` RMR threads spin at ~100%×4).

### Stage A — Register RC funcId 3 in ns-3 — ✅ GREEN
- Edits (uncommitted): `oran-interface/model/oran-interface.cc` (`Trampoline3` + `GetTrampoline` `case 3` + funcId 3 in no-warn guard); `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:~652` + `src/lte/model/lte-enb-net-device.cc:~1066` (RC registered under **BOTH 3 and 300** — TS uses 3, 300 keeps Phase 4/5 grpcurl + golden-pcap parity; both → same `ControlMessageReceivedCallback`).
- `./ns3 build` cached-fast (~14s). E2MGR `/v1/nodeb/{ranName}` confirms ns-3 advertises **ranFunctions 2 (KPM) + 3 + 300**.
- Verified live (`scripts/phase6b-stage-a-grpcurl3-verify.sh`): grpcurl `RanFuncId=3, TargetCellID=1105` → `Success Response` → e2sim `RIC Control Request carries RAN function id 3` → ns-3 `targetCellId=5 ranFunctionId=3 imsi=1` → `RC forced handover … via LTE master RRC` → `Generated RIC Control Acknowledge (… funcId=3)` → `PerformHandover ----- handover from 2 to 5`. Evidence: `oran-kvm-2:/home/uc/captures/phase6b-stageA-*.{pcapng,log}`.
- **code-reviewer verdict: SOUND** (0 crit/high/med; 2 cosmetic low). Double-registration safe: `RegisterFunctionDescToE2Sm` deep-copies the OCTET_STRING per call; one shared `ricCtrlFd` Ptr is fine; freed once by base dtor. (Cosmetic L1: add a half-line comment noting the deep-copy — not yet applied.)
- **rc has TWO validation layers** (learned the hard way): `rcService.go:35` (gRPC entry → "Success Response") AND `rcControl.go:119-135` (async forward). The forward layer ALSO requires non-empty `gNBCUUEF1APID` + `gNBCUCPUEE1APID` (repeated int64) — first grpcurl attempt omitted them → forwarded NOT, ns-3 saw nothing. Fixed in the verify script. (TS itself sets these = ue_id, so TS is fine.)

### Stage B — Deploy + configure TS xApp — ✅ done
- `ricxapp-trafficxapp-…` Running. `install_xapp_traffic_steering.sh` built image + `dms_cli onboard` + install OK.
- Config baked at onboard: edited `…/xApps/ts/xapp-descriptor/config-file.json` `controls` → `ts_control_api:"grpc"`, `ts_control_ep:"service-ricxapp-rc-grpc-server.ricxapp:7777"` (backup `config-file.json.orig`).
- TS internals confirmed (`…/xApps/ts/src/ts_xapp/ts_xapp.cpp`): `send_grpc_control_request` sets `ranfuncid(3)` ✓, `controlstyle(3)/actionid(1)`, `amfuengapid=ue_id`, `gnbcuuef1apid/gnbcucpuee1apid=ue_id`, GUAMI hardcoded (VIAVI RSG); `TargetCellID = highest_throughput_cell_id` then **`cell_map.find(target)` — on miss does `return` (drops control)**. `prediction_callback`: steer to highest-throughput cell if `highest > serving + serving*(A1threshold/100)`; first cell key in the pred JSON = serving. Prediction JSON shape: `{"<ue>": {"<servingCell>":[dl,ul], "<targetCell>":[dl,ul]}}`. `build_cell_mapping()` runs **once at startup** (main:890) → **TS must restart after gNB registers**.

### Stage C — gNB + E2MGR cell-map bootstrap — ❌ BLOCKED (root cause found)
- `scripts/phase6b-start-ns3.sh`: ns-3 up, gNB CONNECTED, dumped `/v1/nodeb/{ranName}`.
- **ROOT CAUSE**: ns-3 e2sim sets `e2nodeComponentRequestPart` = hardcoded **`"reqpart"`** placeholder (`oran-e2sim/e2sim/src/encoding/encode_e2apv1.cpp:271-276`) → ns-3 advertises **NO served-cell data**. TS `NodebHandler` builds `cell_map` ONLY by base64-decoding that field and grep-matching the **uppercased** ranName gNB-id hex (`16B8CEF1`) inside it (`cells.push_back(message.substr(i,10))`, key by NRCGI). Two independent reasons it can't match: (1) the placeholder has no NRCGIs; (2) E2MGR returns the octet as **lowercase** hex while NodebHandler greps **uppercase** → can't match for a gNB-id containing a–f. ⇒ **`cell_map` empty → TS drops every control at the `cell_map.find` miss.** NodebHandler is written for VIAVI-RSG encoding, not ns-3.
- Decoder side OK: rc hex-decodes the `TargetCellID` string to bytes; ns-3 reads NRCGI **last byte** (`oran-interface/model/ric-control-message.cc:274`). So a cell_map key like `"16B8CEF105"` → cell 5 (consistent w/ Phase-5 `"1105"`).

### DECISION PENDING (how to bridge cell→E2-node resolution so TS emits)

**Framing first — not a blocker, a fidelity-investment choice.** M-RC4 (TS-triggered loop) is a **user-gated bonus**: Phase 6's exit (M-RC3 written verdict) is already MET (`plan.md:228`), and Stage-A grpcurl→handover already proves the rc path. So the project is NOT blocked; the question is *how much testbed fidelity to bank now vs later*. (Note: the "proceed to Phase 7" framing elsewhere is misleading — Phase 7 = build reproducibility / M-REPRO, orthogonal to this loop.)

**Key insight — the hex case is NOT O-RAN-mandated, and it lives downstream of ns-3.** On the E2AP wire the gNB-id is **binary** (BIT STRING); "case" exists only when a component renders bytes as a hex *string*. E2MGR renders **lowercase** (very likely Go-default `%x`/`hex.EncodeToString`), TS greps **UPPERCASE**. Neither is non-compliant — same disease as the funcId seam (spec fixes *meaning*, leaves *surface representation* free). Consequence: **ns-3 cannot fix the case mismatch (failure b) no matter what bytes it emits** — the conversion happens in E2MGR, between producer and consumer. Only the *consumer* (TS) — or E2MGR — can resolve it.

1. **Minimal TS patch + rebuild** — when `cell_map` lookup misses, resolve target to the single connected E2 node (ran_name/plmn/nbId from `get_nodeb_list`; those top-level fields DO parse). ~10 lines in `ts_xapp.cpp`, rebuild trafficxapp image + re-onboard. Yields a real TS→rc→ns-3 loop. **Caveat: a single-gNB shortcut** — the "sole connected node" assumption breaks the day a scenario runs >1 gNB. (Revisits the no-TS-rebuild lean, but that was the funcId seam; this gap is separate + unavoidable.)
2. **ns-3 synthetic served cells (TS stock)** — make ns-3 emit crafted served-cell NRCGI bytes in TS's grep form. **Infeasible *if TS stays stock*** — fixes failure (a) but cannot fix failure (b) (the lowercase rendering is E2MGR's, per the Key insight above). Collapses into "modify ns-3 AND still patch the consumer" → strictly worse than Opt 4. Not recommended alone.
3. **Defer automation, document gap** — keep TS stock; M-RC4 (TS-triggered) blocked-by-cell-map; retain Stage-A grpcurl→ns-3 handover as the rc-path proof. Go do Phase 7 (build-repro) meanwhile.
4. **(Robust / recommended if multi-node ever matters) Bilateral proper fix** — fix BOTH sides: ns-3 emits **real served-cell NRCGIs** (fixes a) + TS greps **case-insensitively** (fixes b, ~1 line). Generalizes to **N gNBs** (true cell→node resolution, not a shortcut) and makes ns-3 a more faithful E2 node for *any* consumer xApp. **TS rebuild+re-onboard cost is identical to Option 1**, so the case-fix is nearly free once rebuilding; the real extra cost is the ns-3 served-cell encode work. The one-line TS case-fix is **necessary but not sufficient** alone — a case-insensitive grep over `"reqpart"` still finds zero NRCGIs, so ns-3 MUST also emit real cells.

**Deciding question:** will these demos / future ML scenarios ever run **more than one gNB**? **Yes (or want a reusable, faithful testbed)** → Option 4. **Only ever one gNB** (pure YAGNI) → Option 1 is simpler and sufficient. Option 3 if any TS rebuild is currently too risky.

---

## DECISION 4 (2026-06-14) — Option 4 chosen: bilateral fix, multi-gNB + multi-UE closed loop

**Choice**: Option 4 (bilateral proper fix). scenario-zero already instantiates **4 mmWave gNBs + 12 UEs**, so >1 gNB is the actual case, not hypothetical. Option 4 makes ns-3 a faithful multi-node E2 agent for *any* consumer xApp; TS rebuild cost is identical to Option 1, so the case-fix is ~free once rebuilding.

### Verified design facts (this session — live testbed + source, high confidence)
- **E2MGR contract (decisive, empirically confirmed)**: the RNIB `e2nodeComponentRequestPart` REST field = `base64( lowercase_hex( raw_requestPart_bytes ns-3 sent ) )`. Proof: placeholder `"reqpart"` → field `NzI2NTcxNzA2MTcyNzQ=` → base64-decodes to ASCII `"72657170617274"` (= hex of "reqpart"). So **ns-3's raw OCTET_STRING bytes get hex-rendered (lowercase) by E2MGR**, then TS base64-decodes that hex string and greps it.
- **TS NodebHandler** (`ts_xapp.cpp:331-376`): prefix = ranName chars after the **3rd `_`** (the gNB-id hex, e.g. `16b8cef1`), `toupper`'d; greps base64-decoded field for prefix; per match grabs `substr(i,10)` (10 hex chars = gNB-id 8 + cell byte 2) as a `cell_map` key; `cell_map[key] = nodeb`. `send_grpc_control_request` (`:606-676`) resolves `e2nodeid/plmnid/ranname` from `cell_map[target]->nodeb`; **miss → silent `return`**.
- **Multi-gNB blocker #0 (gNB-id collision)**: e2sim `encode_e2apv1.cpp:162-170` HARDCODES gnb-id buf `[B5 C6 77 88]`/`bits_unused=3` → value `0x16B8CEF1` → every E2 node's ranName = `gnb_734_373_16b8cef1` → E2MGR coalesces all 4 into ONE node. (Each cell ALREADY has its own SCTP assoc + `E2Termination`, src port `38470+cellId` — `mmwave-helper.cc:2193-2202` — so the only thing missing is a unique identity.)
- **Failure a (empty served cells)**: requestPart = `"reqpart"` placeholder, no NRCGIs (`encode_e2apv1.cpp:271-276`).
- **Failure b (case)**: E2MGR hex lowercase vs TS `toupper` grep.
- **Multi-UE in ns-3: ALREADY DONE (Phase 5)**: `ControlMessageReceivedCallback` (`mmwave-enb-net-device.cc:718-787`) reads `m_imsi` (decoded from `amf_UE_NGAP_ID`, `ric-control-message.cc:139-149`) + `m_targetCellId` and calls `LteEnbRrc::TakeUeHoControl(imsi)` + `PerformHandoverToTargetCell(imsi, targetCellId)`. Hands over the **specific UE**. **No ns-3 multi-UE change needed.**
- **Each E2 node serves exactly ONE cell** = its own cellId (no per-gNB cell registry). So each node's requestPart carries one served-cell entry.
- **e2sim plumbing hook**: `E2Sim` already has the `set_client_src_port(int)` setter + `m_client_src_port` member (`e2sim.hpp:42,48`), called from `E2Termination::DoStart` (`oran-interface.cc:232`). Mirror this to inject identity. `generate_e2apv1_setup_request_parameterized(pdu, all_funcs)` is the single setup encoder, called at `e2sim.cpp:162`.
- **mmwave-helper** sets per-cell `gnb_id = std::to_string(cellId)`, `plmnId = "111"` (`mmwave-helper.cc:2194-2196`) → already unique per device, just not on the wire. mmWave cells are **2,3,4,5** (LTE eNB = cell 1, does not connect to E2).

### Encoding scheme (one change fixes collision + failure a together)
For an E2 node with ns-3 cellId `N` (one served cell):
- **gNB-id BIT_STRING**: `buf=[0x16,0xB8,0xCE,(uint8_t)N]`, `size=4`, `bits_unused=0` → value `0x16B8CE0N` → E2MGR ranName suffix `16b8ce<NN>` (top nibble `1` ⇒ stable 8-nibble width, no leading-zero strip). **Unique per cell ⇒ unique ranName ⇒ E2MGR keeps all 4 nodes.**
- **requestPart raw bytes**: `[0x16,0xB8,0xCE,N, N]` (gNB-id 4 bytes ++ cell byte `N`). E2MGR hex → `16b8ce<NN><NN>`. TS prefix `16b8ce<NN>` matches at pos 0 → `cell_map` key `16b8ce<NN><NN>`.
- **delivery (unchanged, already works)**: `target_cell_id` = that 10-char key → rc hex-decodes 5 bytes → ns-3 reads **last byte** = `N` (`ric-control-message.cc:274`). Consistent with Phase-5 last-byte convention.

### Work items

**ns-3 / e2sim (fixes failure a + multi-gNB identity) — our forks:**
1. `oran-e2sim/e2sim/src/base/e2sim.hpp` — add `m_gnb_id_value` (uint32) + `m_served_cells` (`std::vector<uint8_t>`) members + `set_e2node_identity(uint32_t, std::vector<uint8_t>)` setter (mirror `set_client_src_port`).
2. `oran-e2sim/e2sim/src/encoding/encode_e2apv1.{hpp,cpp}` — extend `generate_e2apv1_setup_request_parameterized` to accept `(gnbIdValue, servedCells)`; replace hardcoded gnb-id (`:162-170`) with bytes from `gnbIdValue`; replace `reqPart` placeholder (`:271-276`) with concatenated `[gnbIdBytes ++ cellByte]` per served cell. **Do NOT touch `responsePart`** (TS doesn't read it).
3. `oran-e2sim/e2sim/src/base/e2sim.cpp:162` — pass `m_gnb_id_value`, `m_served_cells` into the encode call.
4. `oran-interface/model/oran-interface.cc` `DoStart` (after `:232`) — parse `m_gnbId` → int N; `m_e2sim->set_e2node_identity(0x16B8CE00u | (N & 0xFF), {(uint8_t)N})`.

**TS xApp (fixes failure b) — `ts_xapp.cpp` NodebHandler (`:347-366`):**
5. Make prefix match **case-insensitive** (normalize both `last_matching_bits` and the compared `message` substring to one case). ~3 lines. This is the **only** TS code change — `build_cell_mapping` already loops all nodebs (multi-gNB) and `send_grpc_control_request` already resolves per-cell owning node; `prediction_callback` already does one control per UE (multi-UE).

**Build (strict order — e2sim is touched, per CLAUDE.md):**
6. On VM: rebuild libe2sim (`cmake . && make e2sim_shared && sudo make install && sudo ldconfig`) → **re-copy header** `sudo cp src/base/e2sim.hpp /usr/local/include/e2sim/` → rebuild `libasn1c_e2.a` (only if asn1c touched — it is NOT, skip) → `cd ns3-mmwave-oran && ./ns3 build`. Then rebuild TS image + `dms_cli` re-onboard (config already points at rc gRPC).

### Stages (execution order)
- **Stage A′ (regression)** — re-verify grpcurl funcId-3 → handover still GREEN after e2sim id change. NOTE: gNB-id bytes change ⇒ Stage-A golden pcap signature shifts (expected; update assertion intentionally, not a regression).
- **Stage C′ (discovery — the de-risk GATE, do BEFORE TS rebuild)** — start ns-3 (4 gNBs); confirm E2MGR `/v1/nodeb/states` shows **4 CONNECTED ranNames** `gnb_734_373_16b8ce0{2,3,4,5}`; for each, dump `e2nodeComponentRequestPart`, base64-decode, **assert hex == `16b8ce<NN><NN>`** and ranName suffix == `16b8ce<NN>`. This empirical check catches any width/case surprise before spending a TS rebuild.
- **Stage D (mock multi-UE/multi-gNB loop)** — inject predictions for **≥2 UEs (distinct IMSIs)** targeting cells on **≥2 different gNBs** → TS emits ≥2 gRPC controls → rc → ns-3 hands over each UE to its target. Capture pcap + ns-3 log showing 2 distinct `handover from X to Y` for 2 IMSIs. (Mock = we craft prediction JSON whose cell-id keys == the 10-char cell_map keys.)
- **Stage E (real QP, optional/may defer)** — deploy QP; align kpimon→InfluxDB CellReport cell-id format to the 10-char keys (open-Q8). Defer if schema mismatched; mock already proves the loop.
- **Stage F (finalize)** — add M-RC4 assertion to `scripts/l-release-validation/` + a re-runnable `scripts/phase6b-closed-loop-run.sh`; update `plan.md` (M-RC4 DONE), this doc (results), `docs/l-release-migration.md`; `/ck:journal`; commit across forks (oran-e2sim, oran-interface, ns3-mmwave-oran) + superproject pins (branch `dev/l-release`, no push unless asked).

### Risks / mitigations (Decision 4)
- **gNB-id render width** (E2MGR nibble count) → mitigated by top-nibble-`1` (stable 8 nibbles) + **Stage-C′ empirical gate** before any TS rebuild.
- **golden-pcap parity** → gNB-id bytes change shifts the Stage-A signature; update the golden assertion deliberately.
- **e2sim build order** → must rebuild libe2sim + re-copy header before `./ns3 build` or stale symbols/headers; asn1c archive untouched (no RC ASN.1 change).
- **Real-QP cell-id schema** (Stage E) → kpimon cell-id vs 10-char key mismatch; deferred, mock is the proof of the automated loop.
- **TS case-fix side effect** → changing `cell_map` key case must stay consistent with the case used in mock prediction JSON keys (we control both).

### Open questions (Decision 4)
- Stage E only: does kpimon-go emit a cell-id into InfluxDB CellReports that QP turns into a key matching the 10-char `cell_map` form? (open-Q8; gates real-QP, not mock.)
- Mock injector mechanism: bundled `ric-app-ts/test` QP vs hand-rolled RMR `TS_QOE_PREDICTION` (30002) sender (decide at Stage D).

### Stage C′ + A′ results (2026-06-14) — code GREEN, multi-node path PROVEN

**Code**: all 5 edits applied (e2sim `e2sim.{hpp,cpp}` + `encode_e2apv1.{hpp,cpp}`, `oran-interface.cc`; TS `ts_xapp.cpp`). libe2sim + ns-3 rebuilt clean (strict order; headers `e2sim.hpp`+`encode_e2apv1.hpp` re-copied). TS case-insensitive fix applied on VM (backup `ts_xapp.cpp.orig-phase6b`). **TS NOT yet rebuilt/re-onboarded** (deferred to Stage D).

**Stage C′ (discovery) — GREEN.** scenario-zero now registers **5 DISTINCT** E2 nodes in E2MGR (was 1 — all collapsed under the hardcoded id): `gnb_734_373_16b8ce0{1..5}`, each `nbId=0x16B8CE0N`, each `e2nodeComponentRequestPart` decoding to `16B8CE0N0N`. Encoding matches the design exactly.
- **Correction to a prior assumption**: E2MGR hex-renders the requestPart **UPPERCASE** (`16B8CE0202`), while the ranName suffix is **lowercase** (`16b8ce02`). So the case mismatch is real but *inverted* from the journal's guess — the TS case-insensitive fix (normalise both sides) is load-bearing and correct. After TS rebuild, `cell_map` will hold 5 cell→node entries.

**Stage A′ (regression + multi-node routing) — GREEN.** grpcurl funcId-3 → rc → e2term → ns-3 cell-4 → `RIC Control Request: imsi=1 targetCellId=4` → `RC forced handover: imsi=1 -> targetCellId=4 via LTE master RRC` → `handover from 2 to 4` + Control Acknowledge. Confirms: (i) the gNB-id change did **not** regress the RC path; (ii) rc routes a control to ONE specific node among 5; (iii) per-UE targeting (imsi decoded + used) → multi-UE ready on the ns-3 side.

**Finding — "multi-instance e2sim inbound-SCTP flakiness" → ROOT-CAUSED + FIXED (2026-06-27).** Symptom (seen here): in a 5-gNB run a control to cell **5** was wire-delivered (DATA→port 38475) and kernel-SACK'd by ns-3, but cell-5's e2sim never processed it; only one node worked. This was first (journal 2026-06-16) **misdiagnosed** as an "SCTP recv-thread startup race / half-established association." **True cause:** `client_fd` was a **process-global** at `oran-e2sim/e2sim/src/base/e2sim.cpp:36`, NOT an `E2Sim` member. ns-3 runs one `E2Sim` per gNB in one process, each `run_loop()` on its own detached thread; every agent's `connect()` overwrote the shared global, so the **last connector won** and ALL recv loops `recv()`'d that one socket — the other agents' sockets were never read (kernel ACKs the data, userspace never `recv()`s it). Re-analysing the pcap: all 5 agents bound **distinct** ports (38471–38475) and each read ≥1 PDU (NOT "deaf"); the healthy node was simply the **last to INIT**, random per run — that is the entire "flakiness." **Fix:** move `client_fd` into `E2Sim` as a per-instance member (mirrors `m_client_src_port`) — 2 lines, `oran-e2sim 75257c7`, superproject pin `222ac76`. **Verified live:** a RIC Control fanned to all 5 nodes `gnb_734_373_16b8ce0{1..5}` → **5/5 receive + decode (funcId 3) + ACK** (was 1). Re-runnable: `scripts/phase6b-verify-multinode-recv.sh`. **Stage D unblocked.** Evidence — original symptom: `oran-kvm-2:/home/uc/captures/phase6b-stageA-1781437269.{pcapng,ns3-...log}`; fix verify: `phase6b-multinode-*.{pcapng,log}`.

**State (updated 2026-06-27)**: Decision-4 code committed across forks (`oran-e2sim`, `oran-interface`, `ns3-mmwave-oran`; pin `52f547e`) plus the SCTP fix (`oran-e2sim 75257c7`, pin `222ac76`). The SCTP-flakiness blocker is **RESOLVED**; Stage D (mock multi-UE loop + TS rebuild/re-onboard) is ready to run. TS config + case-fix remain VM-only (testbed tree).

---

### Artifacts / scripts (this session)
- Scripts (committed-tree, virtiofs): `scripts/phase6b-stage-a-grpcurl3-verify.sh`, `scripts/phase6b-start-ns3.sh`, `scripts/phase6b-verify-multinode-recv.sh` (per-instance client_fd fix verify).
- VM evidence: `/home/uc/captures/phase6b-stageA-*.{pcapng,log}`, `/home/uc/captures/phase6b-ns3-*.log`, `/home/uc/captures/phase6b-multinode-*.{pcapng,log}`.
- Committed: `oran-interface` (funcId 3) + `ns3-mmwave-oran` (dual-register 3+300) + `oran-e2sim` (per-gNB identity `a24e8f9`; per-instance `client_fd` `75257c7`) — superproject pins `52f547e`, `222ac76`. TS config + case-fix remain VM-only testbed tree (`config-file.json`, `ts_xapp.cpp.orig-phase6b` backups).
- Tasks: #1 (Stage A) done, #2 (Stage B) done, Stage C′/A′ done; SCTP blocker RESOLVED 2026-06-27; Stage D (mock loop + TS rebuild) ready.

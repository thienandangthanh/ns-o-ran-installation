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

**Net state**: Stage A GREEN, Stage B done, **Stage C BLOCKED on a TS cell_map gap** → automated loop NOT yet closed. Decision pending (3 options). All code changes UNCOMMITTED. ns-3 stopped.

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

### Artifacts / scripts (this session)
- Scripts (committed-tree, virtiofs): `scripts/phase6b-stage-a-grpcurl3-verify.sh`, `scripts/phase6b-start-ns3.sh`.
- VM evidence: `/home/uc/captures/phase6b-stageA-*.{pcapng,log}`, `/home/uc/captures/phase6b-ns3-*.log`.
- Uncommitted code: `oran-interface` (funcId 3), `ns3-mmwave-oran` (dual-register 3+300). TS config edit on VM-only testbed tree (`config-file.json` + `.orig` backup).
- Tasks: #1 (Stage A) done, #2 (Stage B) done, #3 (Stage C) blocked, #4–6 pending.

# P06 (MC, T-A): identity cluster P11/N5/P2/P5/P8, N1, and the independent RIC control injector

**Start state:** P05 pins; `f7-rerun-green`. **Snapshot at exit:** none. **Preconditions:** Stop A released; AC6a green, including the eNB subscription result (P01); the AC18 #9 rows registered (P04).

## Context
Today [V, agent paths under `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/`]:
- every agent registers as a gNB with a 29-bit Global gNB ID written left-aligned (`e2ap-builders.cpp:105-114`), and the eNB is skipped by that patch (`:107`);
- a gNB's request part is 5 raw octets (`:62-73`), and the eNB keeps the generator's `reqpart` (`:61`);
- only the KPM RAN function is announced (`:95`), with the NG component type (`:82-85`);
- the control target is accepted only as 9 raw octets, with the cell taken from `o[8]` (`rc-control.cpp:25-33`);
- the internal sample kind `gnb`/`enb` drives the metric-map filter (`metric-map.cpp:76`) and the hello check (`sample-forwarder.cpp:41`).

On the RIC side:
- rc builds the target as `"00"+PLMN+key` (`ric-app-rc/control/rcE2SmRc.go:101-102`);
- the TS xApp counts 3 underscores and takes 10 hex digits (`ric-app-ts/src/ts_xapp/ts_xapp.cpp:335-372`), and builds its cell map only at start (`:890`);
- the gate's TS validator accepts exactly two patches to one file (`scripts/gates/ts-lib.sh:57-58,98-112`);
- rc's pin check looks only at the source SHA (`rc-lib.sh:47,126`); the TS xApp has an image-freshness guard (`ts-lib.sh:116-140`);
- kpimon reads only `resp.Gnb` (`ric-app-kpimon-go/control/types.go:50-59`; NIST `control.go.patch:319-329`), and e2mgr 6.0.6 stores no RAN functions for ENB nodes (kongming F7);
- rmr-peer has routes only for TS messages (`tools/rmr-peer/xapp-descriptor/config-file.json:26-27`).

The control path stays Style 3 action 1 in this phase. P07 switches it to Style 5 action 3 and reuses the NR CGI codec built here.

## Requirements (contract)
- **AC12 (P11/N5, R5):**
  - gNB ID 32 bits = cellId; NCI = gNB ID ‖ cell part 1 (R-3).
  - Live meid suffix right-aligned; e2mgr `nbId` 32 characters.
  - rc, the TS xApp key and the agent use the spec NR CGI, and the agent maps gNB ID → cell.
  - An independently encoded target is `applied` in the ledger and the traces, and the old N5 form (gNB ID left-aligned in the NCI, fixture `0000F1100000000303`) is answered `control-message-invalid`.
- **AC13 (P2/P5/P8, N1), on the decoded E2 Setup:**
  - the eNB uses a Global ENB ID and the gNBs Global en-gNB IDs;
  - request parts: EN-DC X2 SETUP REQUEST, init-en-gNB with the served NR CGIs for the gNBs, init-eNB with the served E-UTRA cells for the eNB (I-5);
  - RAN function 3 with Style 5 action 3 in its definition (gNBs only);
  - every node CONNECTED, and kpimon subscribes to all of them;
  - the TS xApp parses `en_gnb_…` and builds a non-empty cell map.
- **AC18:** every changed check (R-7 P5/N5 sites, the TS patch validator, readiness) has its row before code.

## Design
- **Wire identity vs internal kind (Codex 5).** The internal `kind` stays `gnb`/`enb`, so the metric map and hello are unchanged. `build_setup_request` derives the Global E2 Node ID choice from it: `gnb` → `GlobalE2node_ID_PR_en_gNB` (gNB-ID BIT STRING, 4 octets, bits_unused 0, value = gnbId); `enb` → `GlobalE2node_ID_PR_eNB`, macro eNB ID 20 bits = nodeId. No new kind value. `run_ns3_e2_agents.sh` keeps the kinds and writes `expectedRanName` per kind: `gnb` → `en_gnb_<mcc>_<mnc>_%08x`, `enb` → `enB_macro_<mcc>_<mnc>_%06x` (e2term rendering, plan R-3).
- **Component config.** Interface type `x2`, with the node's own global ID. The request part is the APER bytes of an X2AP `ENDCX2SetupRequest` carrying the R-3 constants, including the mandatory `nrModeInfo` and `measurementTimingConfiguration`. Read E2AP v03.00 §9.2.27 first to settle whole X2AP-PDU vs message; the choice is recorded in the ledger before code.
- **X2AP codec.** A separate `libx2ap_codec.so` with hidden asn1c symbols, exporting only `x2c_*` (the `librc_codec` pattern [V `ns3_e2_agent/CMakeLists.txt:16-29`]). It is generated from the legacy X2AP asn1c [V `oran-e2sim/e2sim/previous/ASN1c/ENDCX2SetupRequest.h`] or regenerated from the 3GPP TS 36.423 ASN.1 (Zotero `3ML7Y29A`); the choice goes to whichever decodes cleanly in tshark and `tools/asn1-indep`.
- **RAN function 3.** `rcc_encode_ran_function_definition` from rc's generated `E2SM-RC-RANFunctionDefinition`: Control Style 5, action 3 and its RAN parameter list (I-4: 1 Target PSCell ID, 2, 3, 4 NR CGI, …). The OID is cited. The setup passes two `ran_func_info` entries (`e2ap-builders.cpp:94-95`).
- **Strict NR CGI (kongming #14).** The agent decodes RAN parameter 4 as APER `NR-CGI`, re-encodes it, and requires byte equality and 9 octets (APER NR-CGI, plan R-3); it then checks PLMN and cell part = 1 and maps NCI >> 4 → cellId. Anything else → `control-message-invalid`, so a lenient decode of the old 9-octet form cannot pass. The N5-form fixture is `0000F1100000000303`.
- **rc fork (new `install_patch_files/xApps/rc/` + ordered `patches.manifest`).** `SetRicControlMessage` encodes the NR CGI with `e2sm_encode_nrcgi` [V `ric-app-rc/e2sm/wrapper.c:177`]. The installer applies the manifest after the clone (`additional_scripts/install_xapp_ric_control.sh:65-68`). gRPC `TargetCellID` = the TS key (`^[0-9A-F]{9}0$`); NCI = `key[:9]`; any other string → InvalidArgument, no RIC message. `wrapper.c:486` passes the 3 PLMN octets.
- **Image guards (F12, kongming #5).** `rc_at_pin` (`rc-lib.sh:126`) and the kpimon install also require the image to carry the label `patchset.sha256` = the digest of the manifest's patch files. A warm install that skipped the rebuild fails the guard (the same idea as `ts-lib.sh:116-140`).
- **TS xApp fork (Codex 4).** One ordered manifest `install_patch_files/xApps/ts/patches.manifest` lists every patch and every patched file: `src/ts_xapp/ts_xapp.cpp`, and in P07 `ext/protobuf/rc.proto`, `rc.pb.cc`, `rc.pb.h`. Both the installer (`install_xapp_traffic_steering.sh:90-97`) and `ts_patches_check` (`ts-lib.sh:98-112`) read it. The check rebuilds every listed file from the pin plus the patches and requires byte equality, and fails on any edit to an unlisted file (`git diff --name-only` ⊆ manifest). The new N1 patch extracts keys only for `en_gnb_` and `gnb_` meids (prefix by name, then the two PLMN fields, then 10 hex at each occurrence of the upper-cased suffix); a node of any other RAN type (`enB_macro_`) contributes no key, since only NR cells are PSCell targets (3GPP TS 37.340 §10.5.1).
- **kpimon fork (F7, redesigned).** For a gNB node, the RAN function 2 definition still comes from e2mgr. For an ENB node, which has no `ranFunctions` in e2mgr 6.0.6, the KPM measurement list comes from kpimon's own config: the metric-map `enb` rows, as a config file installed with the patch set. This is disclosed as an L-release e2mgr limit in the standards ledger and the run report. `E2mgrResponse` gains `Enb` for the node identity only.
- **Independent RIC control injector (kongming #1).** `tools/rmr-peer` gains a role `ric-control-injector`:
  - its own xApp descriptor (tx `RIC_CONTROL_REQ` 12040; rx 12041/12042), registered with appmgr, and an rtmgr route for 12040 → e2term (meid-routed) and 12041/12042 → injector;
  - it sends PDUs encoded by `tools/asn1-indep` (offline image tarball, or pre-encoded on the host);
  - answers are judged only on the decoded wire;
  - the TS xApp is scaled to 0 while the injector runs, because a stray ACK double-frees in its xfcpp 2.3.6 [M kongming];
  - it carries AC12's independent target and the old-N5-form refusal, and P07's Style 3/1 → `action-not-supported`.
- **Harness.** One meid helper (`scripts/gates/lib.sh: meid_of <node>`) and every R-7 P5/N5 site switched to it. `replay-ts-cell-map.py` replays the patched parser. `meid_of <node>`: node 1 → `enB_macro_001_001_000001`, node ≥ 2 → `en_gnb_001_001_%08x`; bring-up asserts `agents.json` `expectedRanName == meid_of nodeId`. `e2mgr_node_check` adds nodeType GNB, gnbType EN_GNB, nbId length 32, {2,3} ⊆ ranFunctions (the body key stays `gnb`: e2mgr stores an en-gNB as GNB). `replay-ts-cell-map.py` mirrors N1 and gains `--no-wrong-node`. `recovery-eval.py`, `e2ap-pcap-facts.py`/`e2-facts-query.py` and `wire-c1-extract.py` follow the pinned rules in check-diff-ledger rows 37, 39, 40. `r3p-stage-a.json` is rewritten by T with the other r3p files. Scenario/schedule keys are rewritten by the R-2 transform T, which is applied to the files themselves and committed (the same T that P08 checks).

## Files
- Agent: `ns3_e2_agent/src/e2ap-builders.cpp`, `e2ap-builders.hpp`, `agent-config.cpp`, `agent-config.hpp`, `rc-control.cpp`, `rc-control.hpp`, `main.cpp`, `rc_codec/rc-codec.c`, `rc_codec/rc-codec.h`, new `x2ap_codec/`, `CMakeLists.txt`, `Dockerfile`, `tests/rc-control-test.cpp`, `tests/codec-probe-e2ap.cpp`.
- Testbed: new `install_patch_files/xApps/rc/` (+ `patches.manifest`); `install_patch_files/xApps/ts/patches.manifest` and the new N1 patch; `install_patch_files/xApps/kpimon-go/control/control.go.patch` (+ types patch, eNB measurement config); `additional_scripts/install_xapp_ric_control.sh`, `install_xapp_traffic_steering.sh`, `install_xapp_kpi_monitor.sh`; `ns3_e2_agent/install_scripts/run_ns3_e2_agents.sh`.
- Tools: `tools/rmr-peer/` (injector role, descriptor, self-test), `tools/asn1-indep/` (encoders for the injector), `tools/e2-evidence/wire-c1-extract.py`, `tools/e2-evidence/fixtures/setup-identity/`, `tools/rc-decode/fixtures/` (new `rc-control-nrcgi.hex`; the M8 file unchanged), `tools/rc-decode/test-rc-decode.sh`, `tools/asn1-indep/selftest_kpm_and_fixtures.py`.
- Harness: `scripts/gates/lib.sh`, `ts-lib.sh`, `rc-lib.sh`, `kpimon.sh`, `agents.sh`, `agents-ns3-run.sh`, `gate-m5-agent-setup.sh`, `gate-r0-rc-scripted.sh`, `gate-s0-free-control.sh`, `gate-q8-rc-smoke.sh`, `rc-send.sh`, `replay-ts-cell-map.py`, `r2-checks.py`, `r3p-predictor.py`, `r3p-checks.py`, `r3p-checks-fixtures.py`, `r3p-dry-run-fixtures.py`, the r0/r1/r2/r3p scenario, schedule and stage JSONs (including `scripts/gates/r3p-stage-a.json`), `tools/rmr-peer/rmr-peer-selftest.py`, `tools/e2-evidence/e2ap-pcap-facts.py`, `e2-facts-query.py`, `recovery-eval.py`, `selftest.sh`, `scripts/probes/probe-rc-control-latency.sh`; new `scripts/gates/gate-e2i-interop.sh` (M10 step `e2i`); `scripts/pins.conf`.

## Steps
1. Write the remaining AC18 rows before code.
2. Agent: IDs, X2 request parts, RAN function 3, strict NR CGI. Unit tests (`rc-control-test` PASS names): `nrcgi-applied-path`, `n5-target-refused` (`control-message-invalid`), `m8-capture-refused` (`control-message-invalid`), `ran-function-id-invalid`, `control-failed-to-execute`, `format1-on-ack`, `bye-fails-all-pending`.
3. Forks: rc NR CGI + manifest + image label; TS manifest + N1; kpimon eNB config + image label. Cold builds on the VM, timed for the budget.
4. Injector: descriptor, appmgr registration, route; self-test against a scratch E2 node.
5. M5–M7 with the new meids; then `gate-e2i-interop.sh` in dev (TS xApp down for the injector part, then up again for the cell map, recreated after every agent is CONNECTED).
6. R0, R1, R2 single runs under the registered predicates; phase exit.

## Validation
- `gate-e2i-interop.sh` verdict:
  - `globalIds` (eNB macro 1; en-gNB 32-bit = cellId);
  - `x2apRequestPartDecodes` for every gNB (served NR CGIs = R-3) and for the eNB (init-eNB, served E-UTRA cell);
  - `ranFunctions {gNBs: [2,3], eNB: [2]}` on the wire;
  - `style5Action3Announced`;
  - meids per R-3; `nbIdBits: 32`;
  - `kpimonSubscribedAll` (eNB included, from the config list);
  - `tsCellMap` holds every gNB key `%08X10`, no eNB key, and every key's first 8 hex equal its single owner's gNB ID;
  - `independentTargetApplied` (ledger + `EnbHandoverStartStats.txt`);
  - `n5FormRefused: control-message-invalid` (`0000F1100000000303`);
  - `agentRcControlUnitTest` (the Steps 2 PASS list);
  - `ppidPerNode70`;
  - `tsXappDownDuringInjector: true`.
- `ts_patches_check`, `rc_at_pin` and the kpimon guard pass, and each fails on a stale-image fixture and on an unlisted-file edit.
- M5–M7, R0, R1, R2 green.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| Global E2 Node ID: en-gNB and eNB | E2AP v03.00 §9.2.6 | `WEE5IEXF` [C] | to cite |
| Component request part, interface type X2 | E2AP v03.00 §9.2.26–9.2.27 | `WEE5IEXF` [C] | to cite |
| EN-DC X2 SETUP REQUEST (init-en-gNB / init-eNB), served cells, mandatory `nrModeInfo` and MTC | 3GPP TS 36.423 §9.1.2.31, §9.2.111–9.2.112; 3GPP TS 38.331 (MeasurementTimingConfiguration) | `3ML7Y29A`; 38.331 [P01 preflight] | to cite |
| NR CGI = PLMN + NCI(36); gNB ID = leftmost 22–32 bits | E2SM common v07.00 §6.2.3.7; 3GPP TS 38.300 §8.2 | `QW6VJ83M` [C], `PSYCJSXT` | to cite |
| Target NR CGI as RAN parameter 4 | E2SM-RC v01.03 / v03.00 §8.4.4.1 | `PSHY8566`, `JRDTL7XS` | to cite |
| RAN function 3 definition in E2 Setup | E2AP v03.00 §8.2.4.3; E2SM-RC §9.2 | `WEE5IEXF` [C], `JRDTL7XS` | to cite |
| eNB KPM measurement list from kpimon config (e2mgr 6.0.6 stores none for ENB) | disclosure; KPM v03.00 §7.4 (RAN function definition) | `F82PYZVK` | to cite |

## Risks
- X2AP/E2AP asn1c symbol clashes (High/High if linked flat). Mitigation: the hidden-symbol `.so`.
- submgr may refuse the eNB subscription (High/Medium). AC6a already showed the outcome; a refusal there paused before this phase.
- The TS xApp may find spurious keys in an APER request part (Medium/High). The check asserts that no key maps to a wrong node.
- Injector routing conflicts with rc's routes for 12041/12042 (Medium/Medium). Mitigation: the injector runs with rc's routes unchanged and is judged by meid and requestorId; route dumps go into the evidence.
- Stale images (Medium/Medium), covered by the guards.
- **Ruled at Stop A (S2, gap 15 = option A, `plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`):** S0 V2/V3/V4 (`gate-s0-free-control.sh`), `gate-s1-pacer-lockstep.sh` and `scripts/probes/probe-rc-control-latency.sh` are frozen at `m10-cp1`; no predicate is rewritten. The fail-fast header is **required**: before P06 code, each of the three scripts gets a first executable line that prints "frozen at m10-cp1: run it from the tag" and exits non-zero, so a stale gate never runs at HEAD. That header is the only edit to them. Successors at HEAD: e2i `e2i_agent_rc_control_unit_test_cause_paths` (V2, row 55), e2i `x2apRequestPartDecodes` + G4 (V4), R0/R1 expect + C2 + the wire join (V3); none for the probe (AC6 closed). Ledger rows 43–45, 48. The δ seam smoke is not frozen (G1, P07).

## Rollback
Re-pin the `m10-cp1` SHAs; rc, the TS xApp and kpimon reinstall from the pinned manifests.

## Amendment 2 work items (user rulings D1, D3, 2026-11-03; kongming-261103-0440)
- **e2mgr fork patch (D1):** `EnGnb.GlobalGNBID` tag `global-gNB-ID` → `global-en-gNB-ID` (`E2Manager/models/e2_setup_request_message.go:54` at 6.0.6, SHA `09036c6`), plus the upstream fixture `tests/resources/setupRequest/setupRequest_en-gNB.xml:27,32` and a negative unit test (the v01 tag yields an empty plmnId). Built from gerrit 6.0.6 in the Testbed install path, `ctr import`ed, and the recipe's e2mgr image overridden (`ric-dep RECIPE_EXAMPLE/example_recipe_latest_stable.yaml:97-101`; yq as in `full_install.sh:315`). The image carries the source SHA and patch-set digest as labels; `gate-m1-ric-up.sh:103,127-136` gets a stronger predicate (patched tag, source label, digest) registered in the check-diff ledger first; the patched image is never tagged `6.0.6`.
- **AC6a re-probe (closes AC6a):** `scripts/probes/probe-e2-identity-setup.sh` on the patched e2mgr: en-gNB E2setupResponse, meid `en_gnb_001_001_7f000001`, nodeb CONNECTED GNB/EN_GNB with 32-char nbId and RAN function 2, no "empty plmnId" log line, KPM subscription admitted and deleted, a second setup after a graceful close accepted; eNB rows unchanged. Evidence run `…/e2-identity-setup/20261102T192656Z` stays as the "before" record.
- **P14 (D3):** rc fork ASN.1 `RANParameter-ID ::= INTEGER (1..4294967295, ...)`; regenerate rc's and the agent's asn1c codecs and `tools/rc-decode`; an asn1c/pycrate cross-check on a control message is part of AC12.
- **Correction:** the X2 component ID names the **neighbour** eNB or en-gNB (E2AP §9.2.32), not the node itself.

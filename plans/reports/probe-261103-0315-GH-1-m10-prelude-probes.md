# M10 prelude probes (P01): rc claims, identity probe, scale probe, toolchain, standards preflight

Date: 2026-11-03 (KST). Plan: `plans/261103-0008-GH-1-post-m9-realism-m10/phase-01-rc-claims-identity-and-scale-probes.md`. Evidence root: `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/`.

**VM start state:** `r3p-green` instead of the phase file's `f7-rerun-green`. It is a superset: the same M0–M7 install plus rc, the TS xApp and the stub at the M9 pins. AC6 needs a live rc, so the superset is required. The VM is reverted to `fresh-install` after the identity probe, because e2mgr keeps the probe nodebs.

## AC6: rc claims at the deployed rc SHA `a2282ee`

Source: OSC `ric-app-rc` at `a2282eedc9e32f60298bf530456ad367bef0824b` (`scripts/gates/rc-lib.sh:35`).

| Claim | Static evidence (file:line at `a2282ee`) | Runtime result |
|---|---|---|
| An ACK without ControlOutcome panics rc | `control/rcControl.go:345` calls `e2sm.GetControlOutcome(controlAck.ControlOutcome)` for every decoded ACK that is still awaited. `control/rcE2SmRc.go:134` then takes `unsafe.Pointer(&buffer[0])`, so an empty slice is an index-out-of-range panic with no `recover` | **Confirmed.** An outcome-less RICcontrolAcknowledge for rc's instance 4, delivered to rc's RMR port 0.06 s after the gRPC call: `panic: runtime error: index out of range [0] with length 0`, RestartCount 1 → 2 |
| The ACK timer is 2 s and only logs | `xapp-descriptor/config.json:72` sets `"controlAckTimer" : 2`. `control/rcControl.go:161-164` reads it as seconds. `:171-181` deletes the map entry on expiry and returns, with only a log line ("Send ErrorIndication message on Timeout" is a comment, `:179`) | **Confirmed.** The same outcome-less ACK for instance 2, delivered 3.10 s after the call: rc keeps running (RestartCount 1 → 1), so the entry was gone before the decode |
| A late ACK is dropped | `control/rcControl.go:334-339`: an InstanceId missing from the map logs "RIC_CONTROL_REQ has been deleted!" and returns before the outcome decode | **Confirmed.** The same outcome-less ACK for instance 2, delivered 3.10 s after the call: rc keeps running (RestartCount 1 → 1), so the entry was gone before the decode |

- **Runtime evidence:** `evidence/e2-identity-setup/20261102T192656Z` (checks `e2id_ac6_*`, `rc-log-fixture-a-previous.txt`, `injector/tx.jsonl`). Delivery path: in this deployment rtmgr routes RIC_CONTROL_ACK (12041) to another xApp (M9 route-owner rows: hw-go, stubqp or kpimon), so **rc never receives an E2 node's ACK at all**. The fixtures used the RMR injector (`tools/rmr-peer/rmr-injector.py`, static seed `12041 → service-ricxapp-rc-rmr:4560`, rtmgr bypassed) with ACKs encoded by the independent codec for the instance ids the probe node saw in rc's requests. The rc timer's own log lines go to a logger that is silent at the deployed level, so fixture B proves the timer through behaviour, not logs.
- **Consequence for P02 (δ > 0):** with the deployed routing, rc can neither panic on nor time out against an agent's ACK; a δ up to 500 ms cannot change rc's state. The agent's ACK still carries Control Outcome Format 1, so the panic stays unreachable even if the routing changes. RestartCount stays a gate signal (AC19).

## AC6a: identity probe — **en-gNB REFUSED (Decision required)**
Probe `scripts/probes/probe-e2-identity-setup.sh` with `scripts/probes/e2-probe-node.py` (independent codec), runs under `evidence/e2-identity-setup/`; the conclusive run is `20261102T192656Z` (earlier runs `184414Z`, `185156Z`, `190049Z` and `191332Z` fixed harness defects: the eNB meid spelling, a cold-boot race, the submgr REST port, the RAN-function source and the fixture route).

| Item | eNB (Global ENB ID, macro eNB ID 0xFFFFE) | en-gNB (Global en-gNB ID, 32-bit gNB ID 0x7F000001) |
|---|---|---|
| E2 Setup outcome on the wire | E2 SETUP RESPONSE (RAN function 2 accepted) | **none**: no response, no failure |
| meid | `enB_macro_001_001_0ffffe` (matches `^enB_macro_001_001_[0-9a-f]+$`; e2term pads the 20-bit ID to 6 hex digits) | `en_gnb_001_001_7f000001` (built by e2term and seen by e2mgr) |
| e2mgr nodeb | CONNECTED, `nodeType` ENB, `nbId` 20 characters, body `enb`, **`ranFunctions` []** | not stored: `SaveNodeb ... global_nb_id:{} node_type:GNB`, then `failed saving nodebInfo. Error: #utils.ValidateAndBuildNodeBIdKey - an empty plmnId received` |
| KPM subscription | through submgr's REST API (kpimon's client endpoint, pod port 8088): accepted (`SubscriptionId` returned), the RIC SUBSCRIPTION REQUEST reached the node (RAN function 2, event trigger `0063` = 100 ms), RIC SUBSCRIPTION RESPONSE admitted action 1, the REST delete led to a RIC SUBSCRIPTION DELETE REQUEST (HTTP 204) | not reachable |
| Wire | PPID 70 on every probe DATA chunk; every message-final frame decodes as E2AP without `-d` (host tshark also decodes the X2AP request part) | same for the request |

**Root cause (source):** e2mgr 6.0.6, the deployed image `ric-plt-e2mgr:6.0.6`, reads an en-gNB's identity from the XML path `en-gNB/global-gNB-ID/...` (`E2Manager/models/e2_setup_request_message.go:45-55`), the E2AP v01 field name. E2AP v02 and later name it `global-en-gNB-ID`, and the deployed e2term renders the v03-era structure, so e2mgr finds an empty PLMN and drops the setup without answering. The struct is the same at 6.0.8 and on current master.

**Other findings:**
- The deployed `service-ricplt-submgr-http` is headless and maps only port 3800, while submgr serves its REST API on 8080/8088. xApps reach it through DNS on the pod IP.
- After a cold boot e2mgr's RNIB is empty (dbaas is in memory), so the probe takes the agent's RAN-function list from a fixture (`scripts/probes/fixtures/agent-gnb-ranfunctions.json`).
- The FU3 live smoke passed: `rc_restart_rtmgr` then `rc_rmr_ready_after_rtmgr`, before and after the rc panic (`rt-readers-rc-*.txt`).


## AC6b: scale probe (10 gNBs)
Probe `scripts/probes/probe-ns3-scale-ten-gnbs.sh` (lock-step, empty pacer schedule, `--nMmWaveEnbNodes=10 --handoverMode=NoAuto`, 30 UEs, 11 live agents, docker0 capture as in M7), run from `r3p-green`.

| Run | Evidence | Result |
|---|---|---|
| 1, simTime 10 s | `evidence/ns3-scale-ten-gnbs/20261102T180303Z` | FAIL: ns-3 was cut by the default 900 s `NS3_TIMEOUT_S` at seq 49 (4.9 sim s). Every failed check (`lockstep_run_exits_clean`, stats after bye, clean traces, counters) follows from that cut. 11 agents CONNECTED, READY and subscribed. Host /home −0.68 GB |
| 2, simTime 4 s (timeout sized from simTime) | `evidence/ns3-scale-ten-gnbs/20261102T182547Z` | **PASS**, all 13 checks: ns-3 and the pacer exit 0; every node's trace has one hello and one bye, 40 samples, no gaps, zero drops; every agent forwarded 40 of 40 with zero drop counters |

- **Rate:** 171 wall s per simulated second in steady state (run 2, after the first simulated second; run 1's per-step series agrees at 17.1 to 18.7 s per 100 ms step). The whole run 2 was 692 s for 4 sim s. For comparison, 2 gNBs free-run measured 6.36 wall s per sim s before M8, so 10 gNBs with 30 UEs is about 27 times slower per simulated second.
- **Disk:** VM root +0.13 GiB per run; evidence 58 MB (traces 2.6 MB, capture 2.5 MB); host /home −0.67 GB from revert to the end of the run.
- **AC15 simTime: 8 s.** The step budget is ≤ 45 min = 2,700 s. Run 2 needed 344 s from unit start to ns-3 start (revert excluded, agent bring-up included). An s10 step also resets rc, the TS xApp and the stub like a rung, so the pre-run overhead is taken as 600 s and the post-run as 120 s. ns-3 at 8 s × 171 ≈ 1,370 s, so the step is ≈ 2,090 s ≈ 35 min, a 23 % margin. 10 s would be ≈ 2,430 s (41 min, 10 % margin), too thin for one measurement. P09 re-checks the rate on the s10 dev runs.
- **N_new (s10 term):** about 0.7 GiB of host growth per 10-gNB run, so s10 is a small term in T′. The budget's 8–15 GiB inference for all new steps stays until the P11 rehearsals.
- **Wall (s10 term):** ≈ 2,100 s, inside the plan's "s10 ≤ 2,700 s".

- **UseIdealRrc smoke (informational): not runnable at the M9 pins.** scenario-zero sets `ns3::MmWaveHelper::UseIdealRrc` to `true` with `Config::SetDefault` after `cmd.Parse` (`ns-3-mmwave-oran/scratch/scenario-zero.cc:356`, `:483`), so no command-line value reaches it. Making it settable is T-C code, which may not land before checkpoint 2. AC17's real probe stays in P10. The s10 budget therefore uses the ideal-RRC rate, and P10/P11 re-measure.

## Toolchain (`tools/asn1-indep`)
- Commit `735e2a7`. Image `localhost/asn1-indep:aab70be470e0803c`, 167 MB, saved as `tools/asn1-indep/dist/asn1-indep-aab70be470e0803c.tar` (sha256 `9bfed29f426e045a7a6b058491b342cc8ffe52455eea9e898bd2d9fba76917b2`; the tarball is not in git).
- pycrate 0.8.1 pinned by hash. Inputs: E2AP v03.01, E2SM v03.01 and E2SM-KPM v03.00 from OSC `sim/e2-interface`; E2SM common and E2SM-RC from rc `a2282ee`; X2AP (3GPP TS 36.423 Rel-18) and NR RRC (3GPP TS 38.331 Rel-18, ≥ v18.6.0) from pycrate's bundled modules, recompiled byte-equal from pinned text. Pins are in `tools/asn1-indep/asn/SOURCES.txt`.
- Self-test 45/45 offline (`--network=none`). Every committed asn1c capture of E2AP (RIC control ACK and failure) and all 30 E2SM-RC control headers decode and re-encode byte-equal.
- Three build-time edits to a temporary copy of the ASN.1, none of which changes a wire byte against the spec: a missing `RICtimeToWait` import, the `RICQuery*` import spelling, and `RANParameter-ID` written with the spec's bound `(1..4294967295, ...)` instead of rc's `(1..2^32, ...)`.

### New deviation found: RANParameter-ID is encoded unconstrained (proposed row P14)
- **Spec:** O-RAN E2SM-RC v03.00 ASN.1, `RANParameter-ID ::= INTEGER (1..4294967295, ...)` (Zotero `JRDTL7XS`, p. 287). Under X.691 APER this is an extensible constrained whole number: id 1 encodes as `00 00`.
- **Deployed:** rc `a2282ee` `e2sm/e2sm-rc-2.0.asn:200` writes `INTEGER (1..2^32, ...)`, which is not valid ASN.1 value notation. asn1c dropped the constraint (`e2sm/lib/RANParameter-ID.c:36-38`, `APC_UNCONSTRAINED`), so rc puts each id on the wire as an unconstrained INTEGER (`01 01` for id 1). The agent's RC codec is generated from the same rc tree (`rc-lib.sh` header: "the agent's codec uses the same one"), so rc and the agent agree with each other and disagree with the spec. Every RC control message, every outcome with items and every RC RAN function definition is affected.
- **Effect on this goal:** the P01 probes do not decode RAN parameters. AC12, however, requires a target encoded by an independent spec encoder to be applied, which the current agent cannot decode. Fixing it means correcting the bound in the rc fork's ASN.1 and regenerating rc's and the agent's codecs inside the T-A fork patches (P06/P07). No code is written for it before checkpoint 1.
- **Status:** registered for the user at Stop A, as a scope confirmation: it is not one of P1–P13/N5, but AC12 and R1 ("fix to spec") imply it.


## Standards preflight (F11)

| Document | Zotero key | Present |
|---|---|---|
| O-RAN E2SM-RC v01.03 | `PSHY8566` | yes (PDF) |
| O-RAN E2SM-RC v03.00 | `JRDTL7XS` | yes (PDF) |
| O-RAN E2SM-KPM v03.00 | `F82PYZVK` | yes |
| O-RAN E2GAP v08 | `AE3NUEDK` | yes |
| O-RAN OAD v18 | `TBVJDMLF` | yes |
| 3GPP TS 37.340 | `E6VYJPXJ` | yes |
| 3GPP TS 38.300 | `PSYCJSXT` | yes |
| 3GPP TS 38.323 | `MSNDDXJH` | yes |
| 3GPP TS 36.423 | `3ML7Y29A` | yes |
| O-RAN E2SM common v07.00 (carried) | `QW6VJ83M` | yes |
| O-RAN E2AP v03.00 (carried) | `WEE5IEXF` | yes |
| 3GPP TS 28.552 (carried) | `5SZUBP6M` | yes |
| 3GPP TS 38.331 (R-3 `MeasurementTimingConfiguration`) | `WF2FTADX` | **added by the user 2026-11-03 10:55 KST** (ETSI TS 138 331 V19.4.0; T4 closed) |

**T4 on 3GPP TS 38.331.** The phase file says a missing document is PAUSE T4 now. The document is first needed in P06 (R-3's X2AP served-cell constants), and Stop A comes before P06, so the T4 is deferred to Stop A with the user notified on 2026-11-03 at 03:10 KST. This is a recorded deviation from "PAUSE T4 now". No P01–P05 decision depends on 3GPP TS 38.331.

## F10: kpm_sim and the subscription period
- **Static finding:** kpm_sim (OSC `sim/e2-interface` at `da6f82f`, the tree NIST builds it from) ignores the event trigger. `e2sim/e2sm_examples/kpm_e2sm/src/kpm/kpm_callbacks.cpp:590-592` reads `ricEventTriggerDefinition` and comments "We are ignoring the trigger definition". The report loop (`:136-156`) replays `reports.json` with a fixed 50 ms sleep after each indication (`:390`, `:527`) and ends when the file ends (the finite burst seen in M2/M3).
- **Consequence for P03:** any kpimon reporting period, 100 ms included, leaves kpm_sim's output unchanged. M2/M3 predicates that count kpm_sim indications do not depend on the period.
- **Runtime confirmation:** runs in P03 step 2 (M3 with kpimon at 100/100). kpimon's period is hard-coded until P03 makes it configurable (`control.go.previous:437`), so a P01 runtime probe would need an unpinned kpimon rebuild for an answer the source already gives.

# kongming: P5 gate i2 is red because the TS xApp is not registered with appmgr

Date 2026-10-24, 02:45–03:40 KST. Model: Opus 5.5 (the caller's routing, per the user's CLAUDE.md). Advice only; this is never user approval.

**What was verified (read-only)**
- **VM `oran-kvm-2404`, 2026-10-23 17:42–17:55 UTC:**
  - Images: appmgr `0.5.8`, rtmgr `0.9.6`, a1mediator `3.2.2`.
  - `GET appmgr /ric/v1/xapps` lists only `hw-go`, `rc` and `kpimon-go`.
  - `GET /ric/v1/subscriptions` lists rtmgr (`maxRetries 5`, `retryTimer 10`) and vespamgr.
  - The TS pod has `spec.hostname=trafficxapp` and no readiness probe. It has only the `service-ricxapp-trafficxapp-rmr` Service; there is no `-http` Service.
  - The TS appenv sets `RMR_SRC_ID=service-ricxapp-trafficxapp-rmr.ricxapp` and `RMR_RTG_SVC=4561`.
  - The TS seed table holds three routes: `20011→a1mediator`, `30000→service-ricxapp-qp-rmr…`, `30004→ad`.
  - a1mediator's `local.rt` comment says its 20010 routing "is a dynamic process triggered by the xapp manager".
  - rtmgr's `/proc/net/tcp` shows ESTABLISHED sessions to a1mediator-rmr, rc, kpimon, hw-go and e2term on `:4561`, and none to the TS xApp.
  - The rtmgr config has `periodicRoutes: enable`.
- **Source, cloned into the scratchpad:**
  - appmgr tag `0.5.8` (`da426ab`);
  - rtmgr `0.9.6` (`85d4b0b`);
  - RMR `4.9.4`;
  - ric-app-ts `19e169b`;
  - ric-app-qp `47a35ca`;
  - the ricxappframe `3.2.2` wheel;
  - xapp-frame-go `0.8.3`.
- **Evidence:** `evidence/i2/20261023T171928Z`, including `gate.log`, `i2-routetable.txt` and `ts-config-file.json`.

## TL;DR
1. **Registering the TS xApp and the stub through appmgr's own REST API is an acceptable integration step.**
   - It is not a TS xApp change and not an outcome change.
   - It is an L-release integration gap with an L-only remedy, the same class as ruling 6.
   - Record it as **L finding 2 (T5 reading)**. Report it, do not pause, and put it on the Stop B ruling list.
   - Not registering is what breaks the contract. Without registration, "the A1 threshold is set" cannot reach the TS xApp, and K12 V7 cannot be met. That path would be a PAUSE T3.
2. **Registration is all-or-nothing for the TS xApp's RMR peers.**
   - Once registered, the TS xApp receives rtmgr's table. That table **replaces** its seed (RMR `newrt` keeps only the meid space), so the seed's 30000→qp route disappears.
   - The stub must therefore be registered too, and QP in P8, which will not register itself either.
3. **Two harness defects will turn the re-run red unless fixed first:**
   - `ts_routes_check` expects `mse|30002|-1|…` and `mse|30000|…`, but registered peers produce **sender-qualified** rows such as `mse|30000,service-ricxapp-trafficxapp-rmr.ricxapp:4560|-1|…`.
   - Registration must come **before** the last rtmgr restart of each install or reset.
4. **The stray-ack premise comes back with registration.** The TS xApp and the stub join the 12041/12042 −1 set.
   - Run the probe after registration.
   - The injector's static route stays as it is.
   - W is unaffected in practice.
5. **New predicted landmine:** after a TS pod is replaced, a1mediator→TS delivery is likely to go stale, the same defect class as rtmgr.
   - Diagnose it in the `--dev` rehearsal.
   - The remedy is an a1mediator pod restart before the reset's rtmgr restart, recorded as an extension of ruling 6.

## 1. Classification under the locked contract (Q1)

**Verdict: acceptable. Report it; do not pause.** The reasons, in order of weight:

1. **The remedy is required by the contract, not added to it.**
   - In scope 6 needs "then the A1 threshold is set".
   - a1mediator routes 20010|20008 only through rtmgr, and rtmgr routes only appmgr-listed xApps:
     - rtmgr's xApp endpoints come from appmgr's list (`sbi.go:85-115`);
     - A1 routes come from each listed xApp's `policies` (`rpe.go:179-185`);
     - appmgr lists only xApps that registered (`restful.go:386-402` reads `xappmap`, which only register and deregister fill, at `:346-384` and `:286-304`).
   - The binding review amendment K12 V7 ("an rtmgr dump shows exactly one receiver for 30000") and the whole stray-ack design ("rtmgr gives every non-platform xApp a −1 route") presuppose that rtmgr routes the TS xApp.
2. **It is not a TS xApp change.** The image, code, descriptor and deployed config are all unchanged.
   - The registration body is the TS xApp's own deployed descriptor, sent the way ricxappframe 3.2.2 registers itself (`xapp_frame.py:226-234`).
   - Nothing is invented: the rx/tx lists and policies come verbatim from the descriptor's `rmr` section, which is the section appmgr parses (`restful.go:247-260`).
3. **It is an L-release failure with an L-only remedy.**
   - xapp-frame-cpp 2.3.6 never registers.
   - appmgr 0.5.8 lists only xApps that register.
   - a1mediator's own config says its A1 routing is triggered by the xApp manager.
   - The remedy uses only L components' public APIs; there is no rtmgr or e2term change.
   - This is exactly the pattern of ruling 6, which the user accepted at Stop A after the run had already taken it.
4. **The scope guard ("do not invent product choices") is respected.** Of the three ways to make the platform know the TS xApp:
   - TS self-registration is a TS change, so T3;
   - an rtmgr dynamic route by hand breaks K12 V7 (§5 B);
   - harness registration is the only one that leaves the contract untouched.

**When it flips to a PAUSE:**
- **T3:** the registration needs any message type or policy that is not in the TS xApp's deployed descriptor, or any edit to the TS image or descriptor.
- **T5:** after registration plus an rtmgr restart, rtmgr still has no session or no `20010|20008` row; or the threshold never reaches the TS xApp even after the a1mediator remedy (§4 L7).
- **T6:** the re-run of gate i2 fails again for any reason. This is the Failure Protocol's one kongming-guided fix.

**My dissent, recorded:** a strict reading of "on an L failure: stop" would pause T5 now. The cost of that reading is one pause cycle. The user's ruling 6 shows this class is accepted, so I advise continuing.

**The "no registration" alternative cannot meet the contract.**
- It means seed routes only, the stub named `qp`, and the A1 threshold never delivered.
- It is NIST's and upstream's static TS↔QP wiring: the TS seed sends 30000 to qp, and QP's `tests/fixtures/local.rt` sends 30002 to the TS xApp.
- **What fails:**
  - the A1 threshold cannot reach the TS xApp through A1;
  - the n2 negative (proof that A1 took effect) cannot be built;
  - K12 V7 has no 30000 row at all;
  - the stray-ack item loses its premise.
- That is a PAUSE T3 with a user decision, so it is not recommended.

## 2. Registration: bodies, placement, idempotence, deregistration (Q2)

**API facts (appmgr 0.5.8)**
- The call is `POST http://<appmgr-http ClusterIP>:8080/ric/v1/register`. It returns **201** on success and 400 on failure.
- The required fields are `appName`, `appInstanceName`, `httpEndpoint` and `rmrEndpoint` (`api/appmgr_rest_api.yaml:595-616`).
- **The instance IP is derived from `appInstanceName`:** `service-ricxapp-<appInstanceName>-rmr.ricxapp` (`restful.go:354`). Only the **port** is taken from `rmrEndpoint`, through `strings.Split(…, ":")[1]` (`:348, :355`).
  - Without a `:port`, that index panics and the client sees an empty reply.
- `config` must be a JSON **string**.
  - When it is present, it is parsed once.
  - Unparsable JSON gives a 400 after one attempt (`:312-338`).

**TS xApp body** (built by jq from the deployed configmap, never hand-written):
```json
{"appName":"trafficxapp","appVersion":"1.2.5","configPath":"","appInstanceName":"trafficxapp",
 "httpEndpoint":"service-ricxapp-trafficxapp-http.ricxapp:8080",
 "rmrEndpoint":"service-ricxapp-trafficxapp-rmr.ricxapp:4560",
 "config":"<jq -c of configmap-ricxapp-trafficxapp-appconfig .data[\"config-file.json\"]>"}
```

**Stub body:** the same form with `stubqp`, `0.1.0`, `service-ricxapp-stubqp-http.ricxapp:8080` (that Service exists), `service-ricxapp-stubqp-rmr.ricxapp:4560`, and `configmap-ricxapp-stubqp-appconfig`.

**How each field is chosen**
- `appName` = the pod hostname (the chart sets it to the descriptor name). This is what both frameworks send.
- `appInstanceName` = the descriptor's `xapp_name // name`.
  - The TS descriptor has `"name": null`. Reading `.name` would register `null` and route to `service-ricxapp-null-rmr`.
- `appVersion` = the descriptor `.version`.
- `rmrEndpoint` uses the Service FQDN rather than the ClusterIP, so it survives Service recreation; only its port is used.
- **`httpEndpoint` must be non-empty and unique as a substring.** appmgr's SDL bookkeeping removes every stored entry that *contains* it (`resthooks.go:271-289`).
  - An empty string, or something like `:8080`, would wipe rc's, kpimon's and hw-go's SDL entries.
  - The TS value names a Service that does not exist. That is deliberate: if appmgr restarts and tries to fetch the config (`restful.go:86-113` → `:318`), it fails on DNS and never sends HTTP bytes to the TS xApp's RMR port.
- Record the body with `config` replaced by its sha256, plus the HTTP code, in `$e/<label>-register-<name>.json`.

**Placement (ordering rule: every registration and every pod replacement comes before the last rtmgr restart of that step)**
- **Gate i2 `--part ts`:**
  1. `ts_install` without its trailing `rc_restart_rtmgr`;
  2. `xapp_register trafficxapp`;
  3. `rc_restart_rtmgr`;
  4. the sessions check;
  5. `rc_route_dump`;
  6. a TS-only route check (`20010|20008`, `30003|-1`, and 12041/12042 −1 rows naming the TS xApp);
  7. **new:** `ts_policy_set <int> i2-<ts>`, which proves the A1 path once, end to end.
- **Gate i2 `--part stub`:**
  1. `stub_install` without its trailing restart;
  2. `xapp_register stubqp`;
  3. `rc_restart_rtmgr`;
  4. sessions to the TS xApp and the stub;
  5. the fixed `ts_routes_check`;
  6. the stub's `/health` is `ok` (its RMR becomes ready only after rtmgr's push, because it has no seed).
- **Gate r2 per-run (`ts_stub_pods_reset`):**
  - The Services stay, so the registrations stay valid; appmgr stores nothing pod-specific.
  - Add an "ensure" step after the new pods are Ready and before `rc_restart_rtmgr`: run `GET /ric/v1/xapps`; register only an entry that is absent or whose rx/tx/policies differ from the deployed descriptor; save `$e/<label>-appmgr-xapps.json`.
  - This also covers an appmgr restart or a VM reboot, which lose the registration (§4 L3).
- **Why register before the restart:**
  - A notification posted while rtmgr is restarting can be lost.
  - After 5 cumulative failures appmgr even drops rtmgr's subscription (`resthooks.go:175-186`); rtmgr's next start re-subscribes (`httprestful.go:578-582`).
  - rtmgr's start-up fetch (`httprestful.go:496-516`) is the only authority to judge on.

**Idempotence**
- Register only if the entry is absent or differs; do not re-register blindly.
- Re-registration overwrites `xappmap` correctly, but **toggles** the SDL copy out (`resthooks.go:281-301`). It also triggers a full route redistribution.

**Deregistration**
- When: before P8 replaces the stub with QP (K12: "undeployed before any QP deploy").
- Sequence:
  1. `POST /ric/v1/deregister {"appName":"stubqp","appInstanceName":"stubqp"}`, which returns 204;
  2. confirm `GET` shows no `stubqp`;
  3. `dms_cli uninstall stubqp`.
- Only call it when `GET` lists that exact pair. An unknown instance under a known appName dereferences nil and panics appmgr's handler (`restful.go:290-292`).
- `dms_cli uninstall` alone does **not** deregister: appmgr 0.5.8 has no helm watch. A stale `stubqp` entry would make rtmgr fan 30000 out to a dead endpoint, and V7 would fail.
- Keep the stub registered through P6, which re-runs R2.

**P8 consequence (verify there)**
- QP 47a35ca will not register itself:
  - ricxappframe registers only when `CONFIG_FILE` names a readable file (`xapp_frame.py:97-117`), and QP's Dockerfile does not set it;
  - QP's descriptor has no http port, so `get_service` would call `.split` on `None` (`:148`) inside the registration thread.
- So the harness registers `qp` the same way, under the same T5 reading. This must also be in M9's chain.

**What to check after each registration**
1. Appmgr's xApp list.
   - The TS entry has `ip=service-ricxapp-trafficxapp-rmr.ricxapp` and `port=4560`.
   - Its rx, tx and policies equal the descriptor's `rmr` section: rx `[TS_QOE_PREDICTION, A1_POLICY_REQ, TS_ANOMALY_UPDATE]`, tx `[TS_UE_LIST, TS_ANOMALY_ACK]`, policies `[20008]`.
   - The stub's entry likewise.
2. rtmgr sessions after the restart: ESTABLISHED to `trafficxapp-rmr`, `stubqp-rmr`, rc and kpimon on `:4561`. **Also add a1mediator** (`service-ricplt-a1mediator-rmr.ricplt`); it is in ricplt, so `rtmgr_sessions` needs a namespace argument.
3. rtmgr rows (rendered by `rmr.go:61-64`):
   - `mse|20010|20008|service-ricxapp-trafficxapp-rmr.ricxapp:4560`
   - `mse|30000,service-ricxapp-trafficxapp-rmr.ricxapp:4560|-1|service-ricxapp-stubqp-rmr.ricxapp:4560`: exactly one 30000 row, with that sender and that single receiver.
   - `mse|30002,service-ricxapp-stubqp-rmr.ricxapp:4560|-1|service-ricxapp-trafficxapp-rmr.ricxapp:4560`. Before the stub exists this row is `mse|30002|-1|…trafficxapp…`.
   - `mse|30003|-1|…trafficxapp…`
   - 12041/12042 `-1` rows for the TS xApp and the stub (`rpe.go:162-177`).
4. A1: the TS log shows `Setting Threshold for A1-P value: N%`. That is the existing `ts_policy_set`.

## 3. Effect on the probe, W and gate r2 (Q3)

**Stray-ack probe**
- Run it after `i2 --part ts` with registration, and before the stub, as planned.
- **The premise holds again:** once registered, the TS xApp holds 12041/12042 −1 rows, so in-RIC acks can reach it whenever it is the e2term −1 owner.
- **The injector's static seed route still makes sense.** Keep it: it is deterministic, independent of the −1 order, and what K12 (probe) asks for. Never register the injector.
- Add to `probe.json`:
  - the appmgr list;
  - the rtmgr −1 rows naming the TS xApp.
- **Expected and harmless in the probe:** after its 30003, the TS xApp logs `[ERROR] send failed` (`ts_xapp.cpp:775`). With registration and no stub, its rtmgr table has no 30000 row; the seed's qp route is gone (§4 L5).

**Probe strength**
- R2's natural stray-ack exposure is **nondeterministic**:
  - the −1 order changes with each table regeneration;
  - e2term's RMR connection to the TS Service probably goes stale after each TS pod replacement (L7 class).
- So the burst variant with real payloads (already built) is the test that counts. A later stray-ack crash in a gated run is a red C1. Substitution 2 is tied to the probe result, so applying it after a gated-run crash would be T3.

**W**
- There is no material change. L still runs from the 30003 send to ns-3's `controlRx`.
- The first trigger after a reset now includes fresh TCP connects (TS→stub, stub→TS, TS→rc gRPC). These are a few milliseconds and are covered by calibrating after a full reset.
- The 1 s floor dominates.

**Gate r2 changes, in addition to §2**
- (a) **Must fix:** `ts_routes_check` regexes (`ts-lib.sh:131, :133`) must allow `(,[^|]+)?` after the message type.
  - Assert the 30000 sender is the TS xApp and the 30002 sender is the stub.
  - As written, the check fails on every registered table.
- (b) Record the appmgr list per run, plus a verdict fact `xappRegistration`: who registered each entry (harness or self) and the body sha256.
- (c) The stub log's `stubOtherMessages` may now hold 12041/12042 entries when the stub is the −1 owner.
  - Record their mtypes; they are not a failure.
  - Route owners now range over 5 xApps. Per ruling 6 this stays "recorded, not a pass condition".
- (d) Keep the probe, the injector and the C1 design unchanged.

## 4. Other landmines, verified read-only at the pins (Q4)
- **L1. appmgr validation** (`restful.go`):
  - required fields per `appmgr_rest_api.yaml:595-616`;
  - a missing `:port` panics (`:348/:355`);
  - the IP comes from `appInstanceName` (`:354`);
  - the `rmr` section wins over `messaging` (`:247`).
- **L2. appmgr has no locking.** `xappmap` is a plain global map written and read by concurrent HTTP handlers and by `RetrieveApps` (`:59, :373-380, :388`).
  - Concurrent registrations can trigger Go's fatal "concurrent map writes" and kill appmgr.
  - Never register while rc, kpimon or hw-go pods are starting; they register about 5 s after Ready.
  - The r2 order (register after the agents connect) is safe; keep the calls serial.
- **L3. Registration does not survive an appmgr restart.**
  - SDL stores the body without `config` (`resthooks.go:255-258`).
  - `RetrieveApps` re-fetches the config over HTTP (`restful.go:105` → `:318`), fails for the TS xApp and the stub, and deletes them.
  - Hence the per-run "ensure" step, and i2 always registers (M9 starts from fresh-install).
- **L4. rtmgr ignores `httpEndpoint` entirely.** It uses only `ip:port`, tx/rx and policies (`types.go:86-94`, `sbi.go:85-115`). An xApp without an http Service is fine.
  - On a notification it re-fetches every xApp and redistributes (`httprestful.go:128-155`).
  - Deregistration prunes the endpoint (`sbi.go:70-83`).
  - At start-up it fetches and subscribes (`httprestful.go:496-582`), then pushes 7 times over about 65 s. After that, `periodicRoutes: enable` re-runs `updateEp` from its **stored** list, never re-fetching appmgr (`control.go:240-264`).
- **L5. An rtmgr table replaces the seed.** `newrt|start` calls `prep_new_rt(ctx, SOME)`, which clones only the meid space (RMR `rt_generic_static.c:1049, :1467-1488`).
  - The TS xApp's seed 30000→qp route is gone after the first push. This is why the stub, and later QP, must be registered.
  - Verified on RMR 4.9.4. The TS image's RMR is older (4.8.1, from earlier counsel); the logic is long-standing (assumption A1).
- **L6. Sender-qualified rows are accepted only if the sender's `my_name` matches.** `my_name` = `RMR_SRC_ID` + `:port` (`rmr_si.c:724-748`; match at `rt_generic_static.c:588-590`).
  - The TS appenv has the right `RMR_SRC_ID`.
  - **Verify that the stub's appenv carries `RMR_SRC_ID=service-ricxapp-stubqp-rmr.ricxapp`** (same dms_cli template) and that the stub binds 4560. Otherwise it silently drops its own 30002 row.
- **L7. a1mediator→TS after a TS pod replacement (not verifiable read-only; predicted).**
  - Same class as rtmgr's stale wormhole: a1mediator's RMR keeps its TCP endpoint to the TS Service. The old pod's close never reaches it, as with rc in P3. Each 20010 is then written into a dead connection: no error, no delivery.
  - Mechanism guess, which is speculation: IPVS removes the real server and conntrack before the old pod's FIN.
  - **Diagnostic in the `--dev` rehearsal (≥ 2 resets).** If `ts_policy_set` fails while the `20010|20008` row and the a1mediator session are present:
    1. capture a1mediator's `/proc/net/tcp` row to `<TS ClusterIP>:11C0` (a non-zero `tx_queue` or retransmits);
    2. add an a1mediator pod restart to the reset, **after** the TS and stub pods are Ready and **before** `rc_restart_rtmgr` (rtmgr's wormhole to a1mediator would otherwise go stale too);
    3. record it as an extension of ruling 6 for Stop B.
  - Policy types and instances live in SDL, so an a1mediator restart keeps type 20008.
- **L8. TS log order.** The TS xApp prints `listening on port 4560` *before* `new Xapp(port, true)` (`ts_xapp.cpp:898-899`). The line does not prove RMR init. This is harmless, because the seed table makes RMR ready at once; do not use it as the RMR proof.
- **L9. Registration fires an appmgr notification to vespamgr as well.** vespamgr skips entries with inline config when it builds its config (`restful.go:409-411`). Expect only log noise.

## 5. Alternatives and trade-offs
- **A. Harness registration (recommended).**
  - Pros: it preserves every contract item and K12 V7; routes are derived from descriptors; one mechanism covers the TS xApp, the stub and QP.
  - Costs: the TS xApp leaves upstream's static seed wiring; the TS xApp enters the −1 set (a crash risk the contract already planned for); appmgr state is volatile, hence the "ensure" step.
- **B. One rtmgr dynamic route for A1 only, plus the upstream seeds.**
  - How: `POST rtmgr /ric/v1/handles/addrmrroute` for `20010|20008`. It is persisted in SDL and restored at start-up (`httprestful.go:584-600, :710-750`). The stub is named `qp` and given a seed for 30002→TS.
  - Pros: the smallest RIC footprint; the TS xApp never enters the −1 set; P8 works out of the box with QP's own seed.
  - Costs: a hand-written route (invented, not derived); K12 V7 unmeetable as written; F3 reversed; the stray-ack premise removed.
  - **Needs a user ruling (T3).** Offer it at Stop B only if the user rejects A.
- **C. Seed only, no A1.** Fails In scope 6; T3. Rejected.
- **D. TS self-registration (patch or sidecar).** A TS xApp change, so T3. Rejected.

## 6. Work checklist
1. **ts-lib.sh:**
   - `xapp_register <name>`: built from the configmap with jq, checks for 201, then verifies the GET; registers only if absent or different.
   - `xapp_deregister <name>`: guarded by the GET, checks for 204.
   - `xapp_list_save <label>`.
   - Remove the trailing `rc_restart_rtmgr` from `ts_install` and `stub_install`; the callers order register → restart.
   - Fix the `ts_routes_check` regexes and the sender asserts.
   - Let `rtmgr_sessions` take a namespace, and add the a1mediator session.
2. **Gate i2:**
   - registration checks for the TS xApp and the stub;
   - a TS-only route check for `--part ts`;
   - `i2_a1_threshold_reaches_ts_xapp` via `ts_policy_set`.
3. **Gate r2 `ts_stub_pods_reset`:** the "ensure" step before the rtmgr restart; the appmgr list in evidence; the `xappRegistration` verdict fact; record the stray-ack mtypes in the stub's other messages.
4. **Gate p5:** add the appmgr list and the −1 rows to `probe.json`; run it only after a green i2 `--part ts`.
5. **Records:**
   - a standards-ledger row: "xApp registration with appmgr: no spec decision (O-RAN SC appmgr/rtmgr behaviour)";
   - implementation notes, plus a resume-card entry "L finding 2 (T5 reading)";
   - the Stop B ruling list: L finding 2, and L7 if it fires;
   - the P8/M9 notes: deregister `stubqp`, harness-register `qp`.
6. Commit (describe the behaviour, with no plan labels), push, and pull on the VM.
7. **Re-run** `gate-i2-ts-xapp-install.sh --part ts` as a full fresh gate through `vm-exec.sh`. If it is red → `PAUSE T6`.
8. Then gate p5, `i2 --part stub`, calibration, `--dev` (≥ 2 resets; watch L7), C1.

Never register ad hoc on the VM to "see if it works". The Failure Protocol forbids improvising; go through the scripted gate.

## 7. Success metrics
- **i2 `--part ts` green:**
  - appmgr lists `trafficxapp` with descriptor-equal rx, tx and policies;
  - rtmgr has an ESTABLISHED session to `trafficxapp-rmr:4561`;
  - the `20010|20008` and 12041/12042 −1 rows name the TS xApp;
  - the TS log shows `Setting Threshold`.
- **i2 `--part stub` green:**
  - exactly one 30000 row, TS xApp → `stubqp`;
  - a 30002 row, `stubqp` → TS xApp;
  - the stub's `/health` is `ok`.
- **`--dev` with ≥ 2 resets:** a threshold line every run (or L7 diagnosed and remedied); sessions every run; the appmgr list every run.
- **R2 C1 V1–V7 pass**, including V7.

## 8. Assumptions
| # | Assumption | Confidence | What would change the answer |
|---|---|---|---|
| A1 | The seed-replacement semantics (L5) hold for the TS image's older RMR. | Medium-high | If a seed row survives in the TS xApp's table, stub registration would still be required for V7, so the advice stands. |
| A2 | L7 (a1mediator→TS stale connection) will appear after a TS pod replacement. The mechanism is speculation. | Medium | If the threshold arrives in every `--dev` run, no a1mediator restart is needed. |
| A3 | QP will not self-register in P8. | Medium-high | Verify there with a GET after QP is Ready. If QP does register, use its own registration and do not double-register. |
| A4 | The user ratifies L finding 2 at Stop B, as they did ruling 6. | Medium-high | If rejected, only alternative B or C remains, and both need a ruling. |
| A5 | The stub's chart sets `RMR_SRC_ID` like the TS xApp's (L6). | High | Verify after install. |
| A6 | e2term's connection to the TS xApp goes stale after each TS pod replacement, so R2 runs give a nondeterministic stray-ack exposure. | Medium (speculation) | It does not change any step; it only lowers the weight of a "no crash" result in the runs. |

## Unresolved questions
- The user's Stop B ruling on L finding 2, and on L7 if it fires.
- Whether the user would prefer alternative B (upstream seed wiring plus one A1 route) over A. Ask only if A is rejected.

Status: DONE. The TS xApp's missing appmgr registration is an L integration gap: harness registration of the TS xApp and the stub with their own descriptors keeps the contract (T5 reading, report, ratify at Stop B). Fix `ts_routes_check` (sender-qualified rows) and register before the last rtmgr restart, re-run i2 `--part ts` once (red → T6), and watch for a1mediator going stale after TS pod replacement.

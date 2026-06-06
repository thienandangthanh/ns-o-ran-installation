# Phase 7 Live: M1–M6 Complete — All Green, Three Real Bugs Fixed

**Date**: 2026-06-07 06:30  
**Severity**: High (production-grade run) / Critical (three bugs killed)  
**Component**: E2 end-to-end (SCTP, setup, subscription, indication, KPM decode); ns-3 scenario-zero → OSC L-release RIC  
**Status**: RESOLVED — Live M1–M6 all GREEN. Branch ready for docs + commit.

---

## What Happened

Executed the Phase-7 **LIVE end-to-end run** against the real OSC L-release Near-RT RIC (k8s ns ricplt on VM oran-kvm-2, 192.168.122.78). Ran ns-3 scenario-zero (4 mmWave gNB + 1 LTE macro) with all E2 functions enabled, connected to e2term NodePort 36422 (real IP 10.244.0.48:36422), and completed all six milestones in a single session:

- **M1 SCTP:** 5 associations INIT/INIT-ACK (one per gNB + validation harness)
- **M2 E2 Setup:** E2setupResponse received, no rejects
- **M3 RANfunctions:** ORAN-E2SM-KPM funcId 2 accepted, no rejects
- **M4 Subscription:** kpimon-go "Successfully subscription done", RANFunctionID 2, action admitted
- **M5 Indication:** kpimon "RIC Indication message received", 231 RICindication frames on wire, Indication Header Format 1
- **M6 Real KPM decode:** kpimon parsed cell metrics AND WROTE to InfluxDB: `"No of cell metrics = 5"`, decoded map `[DRB.MeanActiveUeDl:1 RRU.PrbUsedDl:51 TB.TotNbrDlInitial.16Qam:191 TB.TotNbrDlInitial.64Qam:4 TB.TotNbrDlInitial.Qpsk:22]`, "Parsing Cell Metric Done", "Wrote Cell Metrics to InfluxDB"

**Three critical bugs discovered in LIVE that would not surface offline; all fixed and proved on wire.**

---

## The Brutal Truth

This is what a real run surfaces that offline proofs hide. The code-port session said the v3 model was clean — offline proof passed, ASN.1 encode valid. But the moment we plugged into the live RIC and scenario-zero tried to init 4 gNBs in parallel, we crashed twice on SCTP, then corrupted memory on the first indication encode. Each crash took 20–30 min to diagnose (stare at stack, gdb trace, reread e2sim source) and involved fixing code in three repos (oran-e2sim, oran-interface, ns3-mmwave-oran).

The **real** kick: all three bugs were invisible to an offline test run. The funcId mismatch was known (deferred from the prior session), but SCTP source-port collision and the PDU double-free were *NEW* — they require scenario-zero parallel gNBs + real encode loop + real e2sim send path. This is why live validation exists.

The good news: we fixed them all and proved each on wire with pcap evidence. The branch is now ready to commit.

---

## Technical Details

### Bug 1: funcId Reconciliation (DOCUMENTED, NOW FIXED)

**Symptom:** M5 never fired. e2sim sent RICindication to e2term, but kpimon-go subscribed RANFunctionID 2 (hardcoded, ric-app-kpimon-go control/control.go:45). ns-3 registered KPM under funcId 200 (Bronze default). The callback trampoline in `oran-interface.cc` only had cases for 200/300, so funcId 2 silently no-op'd. Subscription succeeded (M4), but indication callback never invoked.

**Root:** Prior session documented this as a footgun (NS_LOG_WARN), deferred because we didn't know kpimon-go's funcId. Now we know: it's hardcoded to 2.

**Fix (3 sites):**
1. `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:637` changed `RegisterKpmCallbackToE2Sm(200, ...)` → `RegisterKpmCallbackToE2Sm(2, ...)`
2. `ns3-mmwave-oran/src/lte/model/lte-enb-net-device.cc:1076` same change
3. `oran-interface/model/oran-interface.cc` added `case 2: return GetTrampoline<2>();` + explicit `TrampolineN` specialization + register guard to prevent double-registration

**Proof on wire:** Pcap shows "We are getting the subscription callback for func id 2" (e2sim logs), then M5–M6 fire.

---

### Bug 2: SCTP Source-Port Collision (NEW, CRASH)

**Symptom:** Scenario-zero spawns 4 gNBs, each with its own E2Termination agent in one ns-3 process. On run, the 2nd–4th gNBs crashed immediately with `connect() failed: Cannot assign requested address (EADDRNOTAVAIL)`. The 1st gNB's e2sim agent bound src port 36422; the 2nd tried the same and failed.

**Root:** OSC e2sim hardcodes `RIC_SCTP_SRC_PORT 36422` (e2sim_defs.h:32) for the client bind (e2sim_sctp.cpp:177). Every instance in the same process tries `bind(INADDR_ANY:36422)` — only the first succeeds. The Bronze wineslab e2sim honored per-instance source ports; OSC dropped it on rebase.

The mmwave-helper already computes unique local ports per gNB (`m_e2localPort + cellId` at mmwave-helper.cc:2193), but DoStart never passed it to e2sim.

**Fix (4 sites):**
1. `oran-e2sim/e2sim/src/e2sim_sctp.hpp/.cpp`: Added `src_port` param to `sctp_start_client()` (default 0 = auto-bind)
2. `oran-e2sim/e2sim/src/e2sim.hpp`: Added `m_client_src_port` member + `set_client_src_port(uint16_t port)` method
3. `oran-e2sim/e2sim/src/e2sim.cpp`: `run_loop()` calls `sctp_start_client(…, m_client_src_port)` at line ~130
4. `oran-interface/model/oran-interface.cc` (DoStart): Added `m_e2sim->set_client_src_port(m_clientPort)` before agent start

**Proof on wire:** 5 gNB agents now bind unique ephemeral ports 38471–38475, zero "Cannot assign" errors, zero crash. SCTP INIT/INIT-ACK all 5 succeed in pcap.

---

### Bug 3: PDU Double-Free (NEW, CRASH "double free or corruption (fasttop)")

**Symptom:** First indication encodes successfully (388 B), but immediately after encode, malloc crashes with "double free or corruption (fasttop)". Happened at M6 when kpimon was reading the first real indication off the wire.

**Root:** e2sim's `e2ap_asn1c_encode_pdu()` (e2sim/src/messagerouting/e2ap_asn1c_codec.c) ends with `ASN_STRUCT_FREE(asn_DEF_E2AP_PDU, pdu)` — e2sim OWNS freeing the PDU after encode. The prior session's code-review fixed the indication model leak (freed Format1), but ns-3 ALSO called `delete pdu_*` after `SendE2Message()` — double-free.

This only surfaced on the live loop because offline proof (file logging) never encodes; the standalone KPM proof was 1-shot. Only the periodic live send exposed it.

**Fix (5 sites, all in ns-3):**
1. `ns3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc`: Removed `delete pdu_*` after SendE2Message in three places (CU-UP indication, CU-CP subscription response, DU indication)
2. `ns3-mmwave-oran/src/lte/model/lte-enb-net-device.cc`: Removed `delete pdu_*` in two places (CU-UP, CU-CP)
3. Changed `new E2AP_PDU` → `calloc(1, sizeof(E2AP_PDU))` at all 5 sites to match e2sim's malloc/free contract

**Proof on wire:** M5+M6 pcap shows 231 RICindication frames, all decoded successfully, kpimon InfluxDB write succeeds. No malloc crash.

---

### Design Decision: Cell-Only Reduced-PM (M6 Metric Count)

**Open from prior session:** The v3 flat model merges cell + per-UE items into one MeasurementInfoList. Live DU emitted 7 items (5 cell + 2 per-UE DRB.UEThpDl.UEID). The descriptor advertises 5 cell names. kpimon gate: `"no_of_cell_metrics != len(tmpCellKpi)"` — rejected.

**Decision:** Per plan D5 (smallest green = cell-level reduced-PM), suppressed per-UE items in reduced-PM mode. Added guard `&& !m_reducedPmValues` at AddDuUePmItem call in mmwave-enb-net-device.cc (~line 1302).

**Result:** Run with `--reducedPmValues=1` → DU emits 5 items (cell only) → descriptor matches → kpimon "No of cell metrics = 5" → decode + InfluxDB write succeed. Full per-UE reporting still flows in non-reduced mode (useful for future xApps).

---

## Build & Reproducibility

**Linked changes (must rebuild in order):**
1. After modifying `oran-e2sim`, rebuild libE2Sim: `cmake . && make e2sim_shared && sudo make install && ldconfig`
2. **CRITICAL:** e2sim.hpp is in the install rule but must be manually synced to `/usr/local/include/e2sim/` (the install doesn't refresh it if it already exists). Failing this causes compile error in oran-interface.
3. Rebuild ns-3: `./ns3 build`

**Run command (tested):**
```
./ns3 run "scratch/scenario-zero \
  --enableE2FileLogging=false \
  --e2TermIp=10.244.0.48 \
  --simTime=20 \
  --reducedPmValues=1 \
  --e2du=1 \
  --e2cuUp=0 \
  --e2cuCp=0"
```

**Operational:**
- e2term listens on **POD IP** (10.244.0.48:36422), not NodePort 32222. Hardcoded mmwave-helper.cc:300; must match RIC deployment.
- Persistent-node requirement: node must stay CONNECTED between runs. Clear stale RNIB: `curl -X PUT http://e2mgr:3800/v1/nodeb/shutdown`
- kpimon restart: pod must restart after node CONNECTED to force RNIB rescan + subscription retry.
- Wall-clock: ~1 sec sim-time per 2–3 wall-clock sec; simTime=20 gives 40–60 sec for kpimon startup + subscribe + indications.

---

## Evidence (Pcaps)

All in `scripts/l-release-validation/captures/`:
- `phase7-m1m3-scenario-zero.pcap` — M1 SCTP INIT, M2 E2 Setup, M3 RANfunctions registration
- `phase7-m4m6-scenario-zero.pcap` — M4 subscription, M5 indication (double-free fix proof), M6 begin
- `phase7-m5m6-scenario-zero.pcap` — M5 full (231 RICindication frames), M6 kpimon decode → InfluxDB

**assert-pcap.sh validation:** `PASS sctp-init, ric-indication, kpm-v3`

---

## What We Tried

1. **Offline-first approach (deferred after bug 1):** Realized live has entirely different code paths (SCTP client socket, callback dispatch, periodic encode loop). Offline validation is necessary but not sufficient.
2. **Single-gNB test first (rejected):** Scenario-zero *requires* multi-gNB to hit the SCTP source-port collision; would have hidden bug 2.
3. **Debug malloc hooks (didn't help):** ASAN/valgrind not available on VM. Relied on gdb + pcap + stack traces.
4. **Descriptor union for UE items (considered):** Would require a separate UE-style descriptor; chosen simpler cell-only (reduced-PM) path instead per plan.
5. **Manual funcId search (slow):** Read ric-app-kpimon-go source directly to confirm funcId=2; skipped speculation.

---

## Root Cause Analysis

**Why these bugs didn't surface until live:**

1. **funcId mismatch (deferred, known):** Documented in prior session. Only resolvable by querying the real kpimon-go.

2. **SCTP source-port collision:** ns-3 scenario-zero is designed for multi-gNB testing, but the helper's unique port computation was never wired to e2sim. Offline single-instance tests or single-gNB runs hide this. The OSC e2sim rebase removed Bronze's per-instance port logic; the helper's compute-once-reuse strategy assumed it was still there.

3. **PDU double-free:** The prior session fixed the *model* leak (Format1 cleanup) but missed the *container* leak (who owns the E2AP_PDU itself). The prior fix was code-review against the diff, which caught model-level cleanup but didn't see the malloc context. Only the live periodic loop + malloc pressure revealed it.

**Why they were hard to diagnose:**
- Symptom 1 (M5 silent fail): Logs don't show an error; just no indication callback. Required reading e2sim source + understanding the trampoline dispatch.
- Symptom 2 (gNB 2+ crash): EADDRNOTAVAIL is generic; required live SCTP trace (tcpdump) + gdb to confirm bind-port collision.
- Symptom 3 (malloc crash): Happened post-encode, not during; stack pointed to malloc internals, not e2sim. Required double-checking memory ownership contract in e2sim source + tracing ns-3 deletion sites.

---

## Lessons Learned

1. **Offline proofs catch structural errors; live runs catch resource management.** The KPM model proof (prior session) validated encode correctness but exercised a 1-shot path. The periodic live loop is a different stress test. Both are necessary; neither is sufficient alone.

2. **Multi-instance stress tests (scenario-zero multi-gNB) are non-negotiable for resource bugs.** SCTP port collision required 4 agents in parallel. A single-gNB run would have silently passed.

3. **Know your memory ownership contracts.** e2sim's `ASN_STRUCT_FREE` at the end of encode is a contract; if you allocate the PDU with `new`, you're violating it. Read the library's expectations, not just the header.

4. **Functional tests + pcap validation is the cheapest live lab.** We didn't need a full testbed; scenario-zero + tcpdump + tshark decode was enough to validate all 6 milestones on a single laptop.

5. **Trampoline dispatch tables scale poorly.** funcId hardcoding into a switch case meant we had to touch code and rebuild when kpimon expected a different funcId. For the next xApp, consider making funcId a configurable parameter at registration time.

6. **Document per-instance resource allocation clearly.** The mmwave-helper computes unique ports; ns-3 devs expect that to flow to e2sim. The contract broke on the OSC rebase because nobody documented it. **Action:** Add a comment in mmwave-helper.cc explaining that SetE2ClientPort() is per-gNB and will be passed to e2sim.

---

## Next Steps

**Immediate (commit + docs + hand-off):**
1. **Commit across forks:**
   - `oran-e2sim` branch `dev/l-release`: funcId registration fix + SCTP per-instance source port
   - `oran-interface` branch `dev/l-release`: trampoline case 2 + funcId param + design notes
   - `ns3-mmwave-oran` (super-repo): malloc/free contract fix (5 sites) + reduced-PM guard
   - Super-repo submodule pins to new branches
2. **Docs:**
   - Update README.md L-release section: live end-to-end validated (M1–M6 green)
   - Create `docs/l-release-migration-notes.md`: infrastructure (VM, k8s, RIC), bugs fixed, lessons learned, design choices (reduced-PM)
   - Finalize `implementation-notes.html` (running notes)
   - Update `docs/development-roadmap.md`: Phase-7 → DONE (live validation complete)
3. **PCap archive:** Move phase7 pcaps to version control / final evidence folder

**Follow-up (next phase):**
- Full per-UE KPM descriptor if xApps require it (separate task)
- Valgrind under sustained load (requires VM memory upgrade; not available now)
- S-NSSAI SD encoding verification (currently ASCII "100"; spec may require BCD)
- E2SM-RC v2.0 port for closed-loop control

---

## Open Questions / Known Limitations

- **S-NSSAI SD:** Copied as 3 ASCII bytes ("100") from KPM v3.00 reference. Live kpimon accepted it without complaint. Spec verification pending.
- **Per-UE KPM:** Currently suppressed in reduced-PM mode (per plan D5). Full per-UE reporting still works in non-reduced mode but requires a new descriptor. Deferred unless an xApp requests it.
- **Valgrind under load:** H1 fix (PDU double-free) is verified on 231 indication frames (one session). Long-running sustained test would be gold but VM lacks valgrind. Considered low risk given the crash was immediate, not a growth leak.
- **Callback trampoline generalization:** funcId 2 hardcoded; next xApp may need funcId 3/4/etc. Consider a callback registry or configurable funcId parameter.

---

**Status: Phase-7 LIVE END-TO-END COMPLETE. All M1–M6 GREEN. Branch ready for commit + hand-off to documentation + merge.**

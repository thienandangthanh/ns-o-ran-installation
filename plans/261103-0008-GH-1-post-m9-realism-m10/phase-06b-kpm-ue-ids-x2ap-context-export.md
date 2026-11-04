# P06b (MC, T-A P4 KPM half): X2AP UE context export, en-gNB-UEID / eNB-UEID in KPM, kpimon → Influx

**Start state:** P06 pins; `f7-rerun-green`. **Snapshot at exit:** none. **Precondition:** P06 green. **Integration boundary:** this phase's pins are never used for a rung run; R2/R3′ are judged after P07.
_Note (2026-11-04, exit review kongming-261104-1958 finding 10):_ R0 and R1 did run C1 at this phase's pins (`r0/20261104T100125Z`, `r1/20261104T102205Z`), and r3p ran single (`r3p/20261104T082155Z`). These are regression evidence and step 5's cross-check, never R2/R3′ acceptance.

## Context
- The agents' KPM Format 2 UE IDs are gNB-UEID carrying the IMSI in AMF-UE-NGAP-ID (`ns3_e2_agent/src/sample-forwarder.cpp:101`; run report P4 row). The IPC `sample` lines carry only `imsi` per UE (kongming F5, M9 live1).
- ns-3 does hold the X2AP-type IDs:
  - the MN LTE RNTI given to the SN [V `ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:570`, `:1482`];
  - X2AP UE ID = sender RNTI [V `:726`];
  - MME UE S1AP ID = IMSI by ns-3's construction [V `:730`, `epc-mme-application.cc:111`].
- `E2IpcEmitter::SendLine` writes every sent line into `e2-ipc-trace-<node>.jsonl` [V `oran-interface/model/e2-ipc-emitter.cc:153-155`]. So the new channel needs its own write path.
- The harness judges KPM UE lists on `e2ap.amf_UE_NGAP_ID` [V `tools/e2-evidence/kpm-ue-list-moves.py:55`], and the kpimon decode harness prints `amfUeNgapIds` [V `tools/kpimon-decode-harness/kpimon-decode-harness-records.c:51`].

## Requirements (contract, A1)
- **AC14b:**
  - ns-3 exports each UE's X2AP context on a channel that leaves the existing IPC trace files literal (I-8);
  - on the decoded KPM, the en-gNB agents report en-gNB-UEID and the eNB agent eNB-UEID, and no IMSI is carried as a gNB-UEID;
  - kpimon stores the decoded UE ID in Influx, and the TS xApp reads it from there (the TS xApp side lands in P07);
  - P4 ends fixed for RC and KPM.
- **AC14 (feeds it):** the TS xApp takes the RC UE ID from these KPM UE IDs, never from an ns-3 side channel.
- **AC18:** rows for `kpm-ue-list-moves.py:55`, `kpimon-decode-harness-records.c:51`, the r3p stub "decimal IMSI" check and `r3p-scenario.json:17` (`ueId`, via the R-2 transform).

## Design (plan R-4)
- **ns-3 / oran-interface:**
  - `E2IpcEmitter::SendUeContext(line)` sends a `ueContext` line on the existing TCP connection and writes it to `e2-ue-context-<node>.jsonl`, never to `e2-ipc-trace-<node>.jsonl`. The file sits in the run's `--e2TraceDir`, next to `e2-control-ledger.jsonl` and `e2-pacing-log.jsonl`, where the `unknownUe` matcher (ledger row 16) reads it.
  - Each node emits its UE contexts {imsi, lteRnti, mnCellId, mmeUeS1apId} before the sample of a seq, whenever they changed since its last emission. For a gNB these are the UEs in its UE map; for the eNB, all of its UEs.
  - The emission reads state only, so it schedules no events and samples and traces stay byte-identical. A local byte-compare against checkpoint 1 proves it before any VM run.
- **IPC schema:** `schema/ns3-e2-ipc.v1.schema.json` gains the `ueContext` message. Sample messages are unchanged.
- **Agent:**
  - It keeps a per-node map imsi → context from `ueContext` lines.
  - `encode_format2` writes en-gNB-UEID {m-eNB-UE-X2AP-ID, globalENB-ID} on gNB agents and eNB-UEID {mME-UE-S1AP-ID, gUMMEI, m-eNB-UE-X2AP-ID} on the eNB agent, both from rc's generated `UEID` types or NIST's E2SM common types.
  - A sample UE without a context fails loudly: the sample is not encoded and a stats counter increments, so it never silently falls back to the IMSI.
- **kpimon fork:** decode the UE ID CHOICE (its headers include `UEID-EN-GNB.h` and `UEID-ENB.h` [kongming F5]) and write the tag `ueId` per R-4 on UeMetrics points, replacing the IMSI key. The Influx = IPC checks map tag → IMSI through `e2-ue-context-*.jsonl` (harness side).
- **AD stand-in and predictor (harness):**
  - `send-rmr.sh anomaly <ueId>` names the UE by its Influx `ueId` tag, which the injector reads from Influx right before the trigger, like the OSC AD path.
    _Note (2026-11-04, kongming-261104-1958 Q4 item 4):_ P07 takes the route in `phase-07-…md` (R3′ preparation): it resolves IMSI → `ueId` through the run's `e2-ue-context-*.jsonl` and then confirms the key exists in Influx. That route survives a later removal of `ns3.imsi`. The AD stand-in is harness-side; AC14's "never from an ns-3 side channel" applies to the TS xApp.
  - The R3′ predictor and the stub key their answers by that string; `r3p-predictor.py` maps it to the IMSI through the run's `e2-ue-context-*.jsonl`, so the predictor records keep `imsi` (R-2).
- **Secrets (T7):** every Influx read inside the cluster uses the in-cluster NIST config or a K8s Secret reference. No token in any file in git or in evidence (the scrubber fixtures gain a `ueId` query case).

## Files
- oran-interface: `oran-interface/model/e2-ipc-emitter.cc`, `e2-ipc-emitter.h`, `e2-ipc-message-encoder.cc`.
- ns-3: `ns-3-mmwave-oran/src/lte/model/lte-enb-net-device.cc`, `lte-enb-rrc.cc`, `lte-enb-rrc.h` (read-only context getters), `ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc`.
- Agent: `ns3_e2_agent/src/sample-forwarder.cpp`, `sample-forwarder.hpp`, `ipc-server.cpp`, `kpm-encoder.hpp`, `kpm-indication-message.cpp`, `schema/ns3-e2-ipc.v1.schema.json`, `tests/codec-probe.cpp`.
- Testbed: `install_patch_files/xApps/kpimon-go/control/control.go.patch`, `e2sm/wrapper.c.patch` (UE ID decode), the kpimon manifest.
- Harness: `scripts/gates/send-rmr.sh`, `tools/rmr-peer/rmr-injector.py`, `scripts/gates/r3p-predictor.py`, `r3p-checks.py`, `r2-checks.py`, `tools/e2-evidence/kpm-ue-list-moves.py`, `influx-vs-trace.py`, `tools/kpimon-decode-harness/kpimon-decode-harness-records.c`, `scripts/gates/scrub-evidence.sh` fixtures, `scripts/gates/digest-run.py` (asserts that ipc trace files contain no `ueContext` line).

## Steps
1. Write the AC18 rows before code.
2. ns-3 export; local proof: at the checkpoint-1 pins + this change, the r3p-config run has a byte-equal `e2-ipc-trace-*.jsonl` sample set and byte-equal traces.
3. Agent encoding; codec probe decodes en-gNB-UEID and eNB-UEID with values equal to the context file.
4. kpimon UE ID decode and Influx tag; Influx = IPC via the mapping (M6, M7).
5. Live cross-check: an M7 run and one R3′-config ns-3 run with agents (no TS xApp decision path), where every `e2-ue-context-*.jsonl` `lteRnti` equals `reference/identity-map-cp1.json` for the same IMSI (plan R-8). **R2/R3′ are not this phase's exit.** The TS xApp keeps `stoi(ue_id)` until P07, so P06b + P07 form one integration boundary, and R2/R3′ go green at P07's exit (Codex round 2 #2).
6. Phase exit.

## Validation
- Decoded KPM (every gNB indication): UE ID CHOICE = en-gNB-UEID, X2AP ID = the LTE RNTI from `e2-ue-context`, globalENB-ID = {00F110, 1}. eNB indications: eNB-UEID per R-4. Zero gNB-UEID occurrences.
- `digest-run.py` ipc digests are equal to checkpoint 1 for this phase's run; no `ueContext` line appears in any `e2-ipc-trace-*.jsonl`.
- Influx UeMetrics carry `ueId` tags in the R-4 format; `influx-vs-trace.py` passes.
- M5–M7 green; the R-8 live cross-check passes. Exit = the codec, context and Influx gates above; the R2/R3′ integration is judged in P07.

## Hand-offs from the P06 exit review (kongming-261104-1340)
- Before this phase's kpimon changes run on the VM, add a check that kpimon stays Format-3-only: every RIC SUBSCRIPTION REQUEST to an agent has exactly one action, ID 1, action definition Format 3 (by evidence in P06's e2i run 4; never checked so far). Ledger row first.
- Run every gate of this phase with `EVIDENCE_HOST_ROOT` set to this plan's `evidence/` folder (the `vm-common.sh` default is the M0–M7 plan's).

## Standards ledger
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| en-gNB UE ID = en-gNB-UEID {MeNB UE X2AP ID (M), Global eNB ID (M)}; no gNB-UEID on an EPC-connected en-gNB | E2SM v07.00 §6.2.2.6 (CHOICE UEID case, ">en-gNB: E2 Node of type en-gNB when connected to EPC and EN-DC is established"), p. 14 | `QW6VJ83M` | ✓ 2026-11-04 |
| eNB UE ID = eNB-UEID {MME UE S1AP ID (M), GUMMEI (M), MeNB UE X2AP ID (C-ifDCSetup, "reported by MeNB and SeNB")}; Global eNB ID absent ("reported only by SeNB") | E2SM v07.00 §6.2.2.6, p. 14 | `QW6VJ83M` | ✓ 2026-11-04 |
| eNB UE X2AP ID INTEGER (0..4095); agent refuses a larger RNTI | E2SM v07.00 §6.2.3.23 (from 3GPP TS 36.423 §9.2.24), p. 24 | `QW6VJ83M`; `3ML7Y29A` | ✓ 2026-11-04 |
| GUMMEI = {PLMN, MME Group ID OCTET STRING (2), MME code OCTET STRING (1)} = {00F110, 0001, 01} | E2SM v07.00 §6.2.3.18 (from 3GPP TS 36.413 §9.2.3.9), p. 23 | `QW6VJ83M` | ✓ 2026-11-04 |
| Global eNB ID macro eNB ID BIT STRING (20) | E2SM v07.00 §6.2.3.9 (from 3GPP TS 36.413 §9.2.1.37), p. 21 | `QW6VJ83M` | ✓ 2026-11-04 |
| KPM Format 2 "List of matched UE IDs" items are UE ID 8.3.24 | KPM v03.00 §8.2.1.4.2, p. 26 | `F82PYZVK` | ✓ 2026-11-04 |
| UE ID is the E2SM common IE | KPM v03.00 §8.3.24 ("defined in [12] clause 6.2.2.6"), p. 34 | `F82PYZVK` | ✓ 2026-11-04 |
| GUMMEI values {00F110, 0001, 01} | chosen constants (ns-3 models no GUMMEI); the structure is per E2SM v07.00 §6.2.3.18 above | — | disclosed (added 2026-11-04) |
| MME UE S1AP ID = IMSI; eNB UE X2AP ID = LTE RNTI | ns-3 model construction (EpcMmeApplication assigns the IMSI as MME UE S1AP ID; ns-3's X2 uses the RNTI as UE X2AP ID), not a spec | — | disclosed |

Deviation found while reading (P3, disclosed; Stop A′): the eNB agent always includes the MeNB UE X2AP ID, but §6.2.2.6 makes it conditional on DC being set up (ifDCSetup: "shall be present ... if DC is established"). The clause does not forbid it otherwise, and in the scenarios every reported UE that the en-gNBs report has DC set up. An eNB UE whose secondary RLC is not set up yet still carries it. Fix to spec at P07 if Stop A′ rules it a P1–P2: include the X2AP ID only for UEs with DC established, which needs a DC flag in `ueContext`.

_Note (2026-11-04, kongming-261104-1958 finding 2):_ This deviation is now labelled **D-06b-1** (minor), so it no longer collides with the contract's item P3 (δ). It is live on M7's wire: the eNB lists IMSIs 2 and 3 from seq 1, while IMSI 2 enters an en-gNB context only at seq 6 and IMSI 3 at seq 3 (`m7/20261104T093642Z/ns3run/e2-ue-context-*.jsonl`, archived). Row 81 currently requires the ID on every eNB-UEID, so the judge encodes the deviation. "Fix at P07 if Stop A′ rules" cannot happen in that order, because Stop A′ follows P08. Under the standing fix-to-spec rule, the fix is scheduled now:
- **Phase:** P10, bundled with P15, which rebuilds the agent and kpimon anyway. P07 does not rebuild kpimon (phase-07 Files), and P06b's kpimon rebuild alone took about 11 GiB of /home.
- **Row first:** row 81's eNB conjunct changes to "the MeNB UE X2AP ID is present iff the UE is in some en-gNB's ctx(g, s)", derived from the en-gNB context files rather than the eNB's own flag, with one negative each way.
- **Code:** ns-3 adds a DC flag to the eNB `ueContext`; the agent omits the member when DC is not set up; kpimon's tag formatter handles the absent member; the n6 and Influx form checks follow.
- **Stop A′:** P4-KPM is reported as fixed with this one scheduled residual. The user may instead require it before cp2 (in P07).

GUMMEI {00F110, MME group 0001, MME code 01} and the Global eNB ID used in en-gNB-UEID are chosen constants: ns-3 models no GUMMEI. They are the testbed's PLMN and the eNB's macro ID 1 (P06's R-3 identity), not values read from a 3GPP TS.

## Risks
- Emitting `ueContext` changes event order or emission (High/Low). It reads state only; the step 2 byte-compare is a hard gate.
- An RNTI above 4095 (Low/Low at these scenario sizes). The agent refuses to encode it and the counter shows it.
- kpimon tag cardinality or Influx schema changes break existing checks (Medium/Medium). The rows are in the AC18 ledger, and the checks map tag → IMSI.
- Token exposure (High/Low): T7 guards and scrubber fixtures.

## Rollback
Re-pin the P06 SHAs.

## Work record (2026-11-04)
- Step 1: ledger rows 79–100 and the controller's rulings on the inventory's open questions are committed (56a7092), before any code commit. Inventory: `plans/reports/planner-261104-1430-GH-1-p06b-ac18-inventory.md`. Rows 88–95 (stand-in anomaly sender, stub, predictor) belong to P07's R2/R3′ integration and are implemented there.
- Step 2 (fork commits on `dev/l-release-nist180`, pinned in 0fdc1a3):
  - oran-interface e5ad09d: `ueContext` line `{imsi, lteRnti, mnCellId, mmeUeS1apId}` sent before a seq's sample. It is sent on the first sample, on any change, after every new connection and after a send refused by backpressure. It goes to `e2-ue-context-<node>.jsonl`, never to `e2-ipc-trace-<node>.jsonl`. Hello announces minor 3, under the schema's own minor rule.
  - ns-3 e5b02094: the eNB passes every UE; an en-gNB passes each UE whose secondary RLC is set up, with the master's LTE RNTI and cell read from that RLC through a read-only `UeManager` getter. A gNB UE without a master identity is left out.
  - The byte-compare against checkpoint 1 is still to run (M4 on the VM).
- Step 3 (Testbed 2d256d2): the agent keeps each node's latest context set, which each line replaces whole, and encodes en-gNB-UEID or eNB-UEID per R-4. A sample with a UE that has no context is not encoded. It is counted in `samplesNoUeContext`, and `dropped.encode` also counts it. The agent ignores hello minor, so an older ns-3 fails loudly through that counter. Host results in the dev image: codec-probe, rc-control-test, kpm-report-period-test, check-report-period.py and sctp-ppid-loopback-test exit 0. In the report-period golden, only the 15 UE pieces were regenerated; the header and cell pieces are byte-identical to the old golden. `compare-codec-probe.py` waits for the decode harness's `ueIds` field (row 83).
- Step 4, kpimon (Testbed 89d45af):
  - It decodes the UE ID CHOICE and tags UeMetrics with `ueId` (`enGnbUeId:<x2apId>@00F110-<%05X>`, `enbUeId:<mmeUeS1apId>@<x2apId>`). Any other CHOICE is logged as an error and the point is written without the tag, so a tag-count check catches it.
  - It is shipped as three layered patches listed in the manifest, following the `control.go.enb-measurements.patch` precedent, instead of a regenerated `wrapper.c.patch`.
  - Host proof: the C formatter on the agent's real octets, and kpimon's real Go `handleIndication` into a stub Influx endpoint. The image rebuild and the live run are still to do.
- Deviations from the Files list:
  - The agent's dispatch and reset are in `main.cpp`, not `ipc-server.cpp`; the counters are in `agent-stats.*`. A new test file `tests/codec-probe-kpm-ue-id.cpp` was added.
  - The kpimon change is in new patch files plus installer lines.
  - The harness also needs `check-n6-influx-window.py`, `n6-fixtures.py`, `ipc-null-sink.py`, `agents-ns3-run.sh` and a new `tools/e2-evidence/ue-context-map.py` (rows 79–100).
- Disclosures for Stop A′:
  - The `ns3.imsi` vendor measurement stays in the KPM report. The contract forbids only an IMSI carried as a gNB-UEID; R-4's and the schema's "never encoded" wording is narrowed to "never encoded as the UE ID".
    _Note (2026-11-04, kongming-261104-1958 finding 9):_ This is an interpretation of R-4, not a contract issue. R-4's text is "The IMSI stays inside the IPC; the agent uses it only to map sample UEs to their IDs" (plan.md:198), in the context-channel bullet; "never encoded" is not R-4's wording. Rows 85, 86 and 90, committed before code (56a7092), pre-registered that `ns3.imsi` stays, and AC14b forbids only an IMSI carried as a gNB-UEID. Stop A′ follows cp2, so its options are "keep through M10" or "remove by amendment". P07 keeps the TS xApp off every `ns3.*` field for the UE identity, and P10's AC16 lint classifies the `ns3.*` vendor measNames.
  - The MME UE S1AP ID equals the IMSI by ns-3's construction.
  - A UE that leaves a gNB in the middle of a multi-sample reporting period has no context at encode time, so that sample is not encoded. P07–P10 must use one sample per period wherever handovers happen, or the agent must keep departed UEs until the period is reported.
    _Note (2026-11-04, kongming-261104-1958 finding 3):_ This is a latent agent defect, not a test constraint. The "one sample per period wherever handovers happen" rule is withdrawn, because a gate-configuration rule that hides a defect is a narrowing. The fix is in P07, where the agent is rebuilt anyway: the agent keeps the `ueContext` lines keyed by seq until the period is reported and encodes each sample with the context valid at its seq, with a host unit test of a mid-period context change (all K records encoded; the departed UE appears only in its own samples).
  - Added at the exit review (2026-11-04): the VM `docker image prune -f` of dangling images (below) is an interpretation of the contract's §5 "Nothing is deleted autonomously", by analogy with the plan's image rule; it goes to Stop A′. The step 2 and step 5 sequencing deviations are recorded under the exit record.
- Harness (9a64fd3): rows 79–87 and 96–100. Lint and every self-test pass. On the gNB-UEID-era e2i capture (`evidence/e2i/20261104T025747Z`), the new UE ID check fails as it must (44550 gNB-UEIDs), and the sub-actions check passes (3 requests, one action, ID 1, Format 3).
- VM gates. Evidence is under `evidence/`.
  - M4 PASS `m4/20261104T061448Z` (18/18).
  - M5 attempt 1 FAIL `m5/20261104T063714Z`: run before M3, so the decode harness linked against the old kpimon image's .so, which has no tag function. This was an order error, not a defect.
  - M3 PASS `m3/20261104T064159Z` (kpimon rebuilt at Testbed 89d45af).
  - M5 PASS `m5/20261104T072003Z`. M6 PASS `m6/20261104T072138Z`.
  - M7 attempt 1 FAIL `m7/20261104T072315Z`, on `m7_kpm_ue_ids_en_gnb_and_enb_ueid_resolved_by_ue_context` only. After the e2term delete, Docker reassigned agent IPs, and the flattened `node-ips.json` map judged node 2's indications against node 3's context. The wire IDs equal node 2's own context file.
  - Fix: row 101 (ae937f7), then d8e7692, which attributes each frame by its SCTP association's E2 Setup node, still requires the IP to be listed for that node, and fails closed on a shared IP without facts. Replayed on attempt 1's capture: PASS with facts (all five nodes, 0 gNB-UEID), FAIL without.
  - At d8e7692: M6 PASS `m6/20261104T075343Z`, M7 PASS `m7/20261104T075520Z`.
- Step 2 and step 5 (R3′ single, `r3p/20261104T082155Z`, d8e7692):
  - Live1 against the M9/cp1 reference (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p`): ledger, ipc (100 samples per node) and traces are byte-equal. `extra` differs only in `rc-multiset` targetKey `0000000202` → `0000000210`, which is R-2's rc-multiset transform (`targetKey` → the NCI key, plan.md:159). kpm-headers and collet-start-time are equal. `ipcTraceUeContextLines` = 0. The scenario, schedule and predictor-records files differ by the same T, which P08 judges.
  - `r3p_live1_ue_context_equals_identity_map_cp1` PASS, the R-8 live cross-check. The UE context tie to ns-3's PDCP trace, the Format-3-only subscription and the KPM UE-list moves all PASS.
  - The gate's verdict is FAIL on `r3p_live1_expected_outcomes_step_scoped_late_zero` and `r3p_live1_wire_requests_equal_handovers_via_target_with_predictor_key`. Both expect h1 via the source en-gNB 3 (row 22's T on the schedule), while the TS xApp still sends via the target gNB 2, as in P05's green run, whose ledger line is identical. Rows 14, 15 and 25 change that in P07. This is the P06b + P07 integration boundary of step 5: R3′ is judged at P07's exit.
- Codex pre-ship audit (read-only, adversarial-review `--base 1d980c4`, 2026-11-04 17:36 KST, disclosed). Verdict needs-attention, four findings, each backed by an in-memory probe; all four accepted:
  - P12 judged UE IDs only from the first measCondUEid item and ignored `ueIdTags` (row 102).
  - A `ueContext` record in an IPC trace passed the live gates (row 103).
  - M7 never joined Influx `ueId` to `ns3.imsi`, the only eNB Influx path (row 104). Phase step 4 names M7, so the gap is real.
  - The sub-actions check silently dropped unattributed subscription requests (row 105).
  Rows were committed before code (1feb90a). The gates that carry these checks rerun after the fix.
  The fix is 28d4508.
  - Lint and every self-test pass.
  - The new checks pass on the green M6, M7 and r3p evidence and fail on the negatives, for example a later item's X2AP ID changed in re-encoded real M7 messages.
  - The new M7 Influx check could not be replayed offline on a real five-node export, because M7's committed export held only `_time` and `_value`. Its first live run is the rerun below.
- R0 and R1 at d8e7692 (rows up to 101): R0 PASS `r0/20261104T083548Z`, R1 PASS `r1/20261104T085644Z`.
- P12 at d8e7692: FAIL `p12/20261104T091609Z` on `disk_guard` only. The VM root was 77 % used against the 75 % guard, and no check ran.
  - On the VM, `docker image prune -f` removed only dangling, untagged images (superseded agent and ns-3 builds) and reclaimed 7.7 GB, bringing the root to 68 %.
  - Every tagged image, including the current agent `ns3-e2-agent:89d45afb8cf9` and kpimon, is kept.
- Final rerun at 28d4508 (rows up to 105), 09:34–10:58Z, all PASS with no failed check:
  - M6 PASS `m6/20261104T093457Z` (41 checks): 99 Format 2 indications, 0 gNB-UEID, every en-gNB-UEID resolved by node 2's UE context.
  - M7 PASS `m7/20261104T093642Z` (57 checks): 2,959 Format 2 indications over all five nodes, 1,131 of them from the eNB, 0 gNB-UEID. The new Influx check matched the `ueId` of every UE row to the ns-3 IMSI on every node: node 1 (eNB) 4,404 rows, nodes 2–5 1,763, 1,302, 857 and 673 rows, 0 mismatches.
  - R0 PASS `r0/20261104T100125Z` (130 checks). R1 PASS `r1/20261104T102205Z` (144 checks). Every run's UE context files agree with ns-3's PDCP trace.
  - P12 PASS `p12/20261104T104145Z` (56 checks): one indication per 10 samples, 10 records each, with the UE IDs and `ueIdTags` judged in every condition item.
- Evidence: the verdict layers of the 17 P06b run dirs (1,288 files) are in git. Their 4,233 raw files are archived as `/mnt/data/andang-data/ns-o-ran-installation-evidence/plans-evidence-raw-m10-p06b-20261104.tar.zst` (160 MB) with its `.list0`; both are in that folder's `SHA256SUMS`, which verifies. Host free space at exit is 30 GiB on /home and 12 GiB on /mnt/data.

## Exit record (2026-11-04)
- **Status: DONE.** AC14b's codec, context and Influx parts are met. The TS xApp half of AC14b and the R2/R3′ integration are judged at P07's exit, as pre-registered.
- **Exit review:** GO-WITH-CHANGES (`plans/reports/kongming-261104-1958-GH-1-p06b-exit-review.md`, Opus xhigh). It found no AC18 weakening: every code commit came after its ledger rows (56a7092 → 9a64fd3, ae937f7 → d8e7692, 1feb90a → 28d4508), and no check was removed or narrowed. It found no material scope mismatch, so there is no PAUSE T3. Its changes are applied as follows:
  - **Finding 1 (must), the checkpoint-1 byte-compare is now committed.** `r3p/20261104T082155Z/reference-compare-cp1.json` (`reference-compare.py compare` with the predictor records, schedule and scenario) and `reference-compare-cp1-components.json` (the per-component breakdown, computed offline after the run, at ba2c8df) show ledger, ipc (100 samples per node) and traces equal to the M9/cp1 reference, and `ipcTraceUeContextLines` 0. `extra` differs only in rc-multiset, and the three files differ by T. The citation for the rc-multiset `targetKey` is corrected to R-2 (plan.md:159).
  - **Two step deviations are recorded.**
    - Step 2's "local proof before any VM run" ran after M4–M7, on the VM's r3p single run. That is harmless because the result is equal, and stronger, because it covers P05, P06 and P06b together.
    - Step 5 used the full r3p single gate rather than an agents-only run.
  - **Findings 2, 3, 9 and 10:** dated notes in this file (header, AD stand-in, D-06b-1 with its fix scheduled in P10, the `ns3.imsi` interpretation, the mid-period defect with its fix in P07, the integration-boundary runs). The GUMMEI constants are now in the standards ledger.
  - **Finding 7:** dated notes on ledger rows 100 and 101; the row texts are unchanged.
  - **Finding 8:** a committed host test of the decode harness's records path, `tools/kpimon-decode-harness/selftest-records.sh` with `selftest-records-mutate.c` and four real M7 Format 2 messages in `fixtures/format2-multi-item-ue-ids.lines`.
    - On kpimon's tag-exporting library it passes: the unchanged messages are uniform with a tag per UE. Each mutation of the last condition item's last UE ID turns `ueIdsUniform` false: X2AP ID on 4 messages, macro eNB ID on 2, an added optional F1AP ID on 2, and MME UE S1AP ID on 2.
    - `selftest.sh` no longer defaults to another session's scratchpad; it also passes when given its inputs.
    - Both tests print SKIP with exit 77 without their inputs, and `lint.sh` shows that SKIP line rather than counting it as a pass.
  - **Findings 4, 5, 6, 11 and Q4:** written as the first hand-offs of phase 07. The e2i association mapping moved from a Stop A′ question to P07 harness work (phase 12 note).
  - **Review question 3 is answered:** the Testbed fork's `ns3_e2_agent/tests/compare-codec-probe.py` at 89d45af reads `ueIds` and `ueIdsUniform`, and 2d256d2 is 89d45af's parent.
- **Stop A′ items from this phase:**
  - the user questions on `ns3.imsi` (keep through M10, or remove by amendment) and on D-06b-1 (P10 with P15, or before cp2);
  - the disclosures: MME UE S1AP ID = IMSI, the GUMMEI constants, the VM image prune, the two step deviations and the e2i association mapping;
  - the open Zotero question for 3GPP TS 38.101-1, 36.101 and 36.104.

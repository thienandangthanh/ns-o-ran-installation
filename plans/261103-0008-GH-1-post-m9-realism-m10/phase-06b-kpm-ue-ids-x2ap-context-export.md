# P06b (MC, T-A P4 KPM half): X2AP UE context export, en-gNB-UEID / eNB-UEID in KPM, kpimon → Influx

**Start state:** P06 pins; `f7-rerun-green`. **Snapshot at exit:** none. **Precondition:** P06 green. **Integration boundary:** this phase's pins are never used for a rung run; R2/R3′ are judged after P07.

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
  - `E2IpcEmitter::SendUeContext(line)` sends a `ueContext` line on the existing TCP connection and writes it to `e2-ue-context-<node>.jsonl`, never to `e2-ipc-trace-<node>.jsonl`.
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

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| UE ID CHOICE: en-gNB-UEID (en-gNB), eNB-UEID (eNB) | E2SM common v07.00 §6.2.2.6 | `QW6VJ83M` [C] | to cite |
| KPM Format 2 UE IDs | KPM v03.00 §8.2.1.4.2, §8.3.24 | `F82PYZVK` | to cite |
| eNB UE X2AP ID, MME UE S1AP ID semantics | 3GPP TS 36.423 §9.2.24; 3GPP TS 36.413 (MME UE S1AP ID) | `3ML7Y29A`; 36.413 [P01 preflight] | to cite |
| MME UE S1AP ID equals the IMSI in ns-3 (model construction, disclosed) | ns-3 model, not a spec | — | — |

## Risks
- Emitting `ueContext` changes event order or emission (High/Low). It reads state only; the step 2 byte-compare is a hard gate.
- An RNTI above 4095 (Low/Low at these scenario sizes). The agent refuses to encode it and the counter shows it.
- kpimon tag cardinality or Influx schema changes break existing checks (Medium/Medium). The rows are in the AC18 ledger, and the checks map tag → IMSI.
- Token exposure (High/Low): T7 guards and scrubber fixtures.

## Rollback
Re-pin the P06 SHAs.

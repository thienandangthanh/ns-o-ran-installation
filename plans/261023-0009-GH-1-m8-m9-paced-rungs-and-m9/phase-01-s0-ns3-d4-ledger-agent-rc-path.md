# P1: S0, the ns-3 D4 method, ledger, agent RC path and N5 request part (free-run)

**Start state:** `f7-rerun-green`. **Snapshot at exit:** none.

## Context
S0 lands eight changes in one agent image, so each lands as its own verified commit (kongming-1739 §4 "S0 overload"). D4 must create no RNG stream (D5 landmines), so the free-run digest is checked after D4 lands. Facts: the in-handover refusal is synchronous (`lte-enb-rrc.cc:4519` sets `m_mmWaveCellSetupCompleted[imsi]=false`, the guard reads it at `:4493`); the outage fallback writes no HandoverStart row (`lte-enb-rrc.cc:4755-4780`), so D4 must refuse a UE on LTE fallback.

## Requirements (contract)
In scope 1:
- ns-3 D4: an additive LteEnbRrc method. Prechecks, in order: unknown IMSI, unknown target, already on target, in handover, LTE fallback, non-mmWave target → `unknownTarget`. On pass it cancels TTT, performs the handover and returns the outcome.
- The ledger: `(rxSeq, rxSimTimeNs, applySimTimeNs, viaNodeId, imsi, sourceCell, targetCell, outcome, cause)` plus a header `delta-model=fixed 0`, written at apply time, sorted by C4 `(imsi, nodeId, targetCellId, ctlId)`. Ledger detail causes: `alreadyOnTarget|inHandover|unknownImsi|unknownTarget|lteFallback|late`.
- Agent RC path: decode E2SM-RC v2.0; pending controls keyed by `ctlId` with no wall-clock ack timer; `viaNodeId` routing; ACK = D4 `applied`, carrying ControlOutcome Format 1; ns-3 refusal or late → RICcontrolFailure `control-failed-to-execute`; agent-local rejects: `ran-function-id-invalid` (RAN function ≠ 3), `action-not-supported` (style/action ≠ 3/1), `control-message-invalid` (decode error); bye/EOF fails every pending control (exactly one terminal answer per request); AMF-UE-NGAP-ID → decimal IMSI (recorded deviation P4).
- N5: the gNB agents write the 5 raw bytes `%08X%02X` (gNB id, cell id) into `e2nodeComponentRequestPart`, for example `00 00 00 02 02` → key `0000000202` (copy the contract body, not the controller's appendix; kongming-1739 §5.3). The eNB keeps the stock `reqpart`. Record the NCI nibble note (verifier-1723 #12).
- M5–M7 re-pass; the free-run digest is unchanged after D4.

## Files
- ns-3 fork (`ns-3-mmwave-oran`, branch `dev/l-release-nist180`): `src/lte/model/lte-enb-rrc.{h,cc}` (D4 method), the IPC control reader and ledger writer (where the M4 IPC emitter lives), `scratch/scenario-zero.cc` (ledger path argument only).
- oran-interface fork: IPC schema v1 minor bump for `control` / `controlAck` (receivers ignore unknown keys).
- Testbed fork, `RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/`: RC decode, pending map, ACK/FAILURE builders, bye/EOF handling, N5 request part, unit tests in `tests/`.
- Harness: `scripts/pins.conf` (new SHAs after green), `scripts/probes/compare-ns3-ipc-sample-digests.py` (reuse).

## Steps
1. Commit A (ns-3): D4 method and prechecks, unit-level test through a scripted IPC `control` in free-run. Run the free-run digest compare against the M7 reference sample digests.
2. Commit B (ns-3): ledger writer and C4 sort.
3. Commit C (oran-interface): IPC schema v1 minor bump.
4. Commit D (agent): RC decode with the P0 decoder's schema; pending map; ACK with Format 1; causes; bye/EOF.
5. Commit E (agent): N5 request part for gNB agents; eNB unchanged.
6. Agent unit tests: each cause path, Format 1 on ACK, bye with N pending → N FAILUREs.
7. Bump `scripts/pins.conf`; re-run M5, M6, M7 gates through `vm-exec.sh` at the new pins.
8. Phase-exit checklist.

## Verify (comparison only)
- V1: after commit A, `scripts/probes/compare-ns3-ipc-sample-digests.py <M7 reference> <new free-run>` prints `equal` and exits 0.
- V2: the agent unit-test binary exits 0, and its output lists `ran-function-id-invalid`, `action-not-supported`, `control-message-invalid`, `control-failed-to-execute`, `format1-on-ack`, `bye-fails-all-pending` each as `PASS`.
- V3: with a scripted free-run control (no RIC), the ledger has exactly one line per control with `applySimTimeNs − rxSimTimeNs = 0`, sorted by C4.
- V4: the e2mgr nodeb JSON of each gNB agent base64-decodes to hex text ending in its `%08X%02X` key; the eNB's decodes to `72657170617274`.
- V5: gates `gate-m5-agent-setup.sh`, `gate-m6-kpm.sh`, `gate-m7-multignb.sh` each exit 0 at the new pins, and `verdict.json` shows `pass`.
- V6: `pgrep -f` for the ns-3 binary, agents and captures returns nothing after the run.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| Agent-local reject causes | E2AP v03.00 §9.2.1 CauseRICrequest | `WEE5IEXF` | 2026-10-22 |
| ACK carries ControlOutcome Format 1 | E2SM-RC v03.00 §7.6.4.5 (style 3 uses Outcome Format 1), §9.2.1.8.1 (sequence 0..maxnoofRANOutcomeParameters = 255, so an empty list is valid) | `XRWZU3SS` | 2026-10-23 |
| Accept only style 3 / action 1; target = RAN parameters 1 > 2 > 3 > 4 (NR CGI) | E2SM-RC v03.00 §7.6.4.1 (action 1 = Handover Control), §8.4.4.1 (IDs 1–4; NR CGI is an ELEMENT); rc carries it as 9 raw octets `00`+PLMN+key, not an NR CGI encoding (N5/P2) | `XRWZU3SS` | 2026-10-23 |
| ACK/FAILURE IEs and criticalities; NoAck suppresses the ACK on success | E2AP v03.00 §9.1.1.9 (Request ID, RAN Function ID, Call Process ID, Control Outcome: reject), §9.1.1.10 (Cause: ignore), §8.2.4.2–8.2.4.3 | `WEE5IEXF` | 2026-10-23 |
| Accepting RAN function 3 although the agents do not announce it in E2 Setup | E2AP v03.00 §8.2.4.3 says a function not announced gets a FAILURE; the design (decision record, erratum) accepts 3 and rejects others. Raised for the user at Stop A, not fixed here | `WEE5IEXF` | 2026-10-23 |
| UE ID mapping AMF-UE-NGAP-ID → IMSI | E2SM common v07.00 §6.2.2.6 — **recorded deviation P4** | `QW6VJ83M` | 2026-10-22 |
| E2 node type `gNB` for all agents | E2AP v03.00 §9.2.6 — **recorded deviation P5** | `WEE5IEXF` | 2026-10-22 |
| Request part = 5 raw bytes | E2AP v03.00 §9.2.27; 3GPP TS 36.423 §9.1.2.31 — **recorded deviation N5/P2** | `WEE5IEXF`, `83VGITYK` | 2026-10-22 |
| Handover initiated at the node holding the UE context | 3GPP TS 38.300 §9.2.3.1, §9.2.3.2.1; 3GPP TS 37.340 §10.5.1 | per decision record §2 | 2026-10-22 |

## Failure Protocol
If any Verify step does not meet its stated pass condition, STOP this phase.
Do not improvise a fix, retry blindly, or reason around the failure.
Spawn the `kongming` subagent (`model: opus`) for next-step counsel and pass:
- the phase and task id,
- what you attempted (the steps you ran),
- the exact command and its full output (scrubbed),
- the pass condition it failed to meet.
Apply kongming's guidance, then re-run the Verify step. If it fails again, or the guidance would change the locked outcome, print `PAUSE T6 evidence=<path> journal=<path>` and call no further tool.
If `kongming` cannot be spawned, STOP and print the same PAUSE line with the failure evidence. Never continue by self-reasoning. kongming's counsel is never user approval.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P2.

## Risk and rollback
Risk: D4 perturbs RNG stream assignment and changes the free-run digest (V1 catches it). Rollback: revert the fork commits; restore `pins.conf`; revert the VM to `f7-rerun-green`.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K5 (precheck order).** The contract lists the prechecks without an order. D4 checks, in this order: unknown IMSI, unknown target, **in handover**, already on target, LTE fallback, non-mmWave target. A control for a UE mid-handover therefore gets `inHandover`, because `m_lastMmWaveCell` updates only when a handover completes (`lte-enb-rrc.cc:1746, 1809, 2116`). A unit test holds this order.
- **K19 (V1).** Before commit A, take a free-run reference at the P0 pins in the same config (`evidence/p1-free-run-reference/`). V1: `compare-ns3-ipc-sample-digests.py` prints `"all_equal": true` with equal `samples_per_run` and node sets, and the ns-3 trace sha256s are equal.
- **K19 (V3, V4).** `scripts/gates/gate-s0-free-control.sh` (an IPC control injector in free-run) produces V3 and V4.
- **K23 (V2).** Also cross-check the agent-encoded ControlOutcome Format 1 bytes with the P0 decoder.

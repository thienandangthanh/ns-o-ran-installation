# P3: R0 = M8, rc driven by scripted gRPC (2 gNBs, NoAuto)

**Start state:** `f7-rerun-green` with the P2 pins. **Snapshot at exit:** `r0-green`, only after the free-space check.

## Context
rc (`ric-app-rc@a2282ee`) queues each gRPC request and answers `GRPC_SUCCESS` immediately; its ack timer only logs (contract F1). So R0 is judged on the wire and the ledger, never on rc's log. rc builds the CGI as `hex.DecodeString("00"+PLMN+TargetCellID)` and ignores errors, so the target key must be pure hex (F4). e2term's XER renders the request part as uppercase hex (kongming-1739 §2 #11). rc's UE ID is `UEID-GNB` with AMF-UE-NGAP-ID (recorded deviation P4). rc installs through a gate script so M9 reproduces it (f7 has only hw-go and kpimon).

## Requirements (contract)
R0: `--nMmWaveEnbNodes=2`, `--handoverMode=NoAuto`, real rc driven by scripted gRPC (grpcurl to rc:7777), lock-step pacing.
- D7: ≥ 2 IMSIs handed over to targets on gNBs 2 and 3, with ≥ 1 control through the eNB (MN) agent, ≥ 1 through the UE's serving-gNB agent and ≥ 1 through the target gNB agent.
- Each control: one decoded RICcontrolRequest, one terminal answer; the IMSI moves between the gNBs' decoded KPM UE lists.
- One deliberate already-on-target refusal (`epc-x2.cc:693` guard): FAILURE `control-failed-to-execute`, a `refused` ledger line, no handover row, ns-3 still running.
- G4 on every **gNB** agent: the e2mgr nodeb JSON decodes to its N5 key; plus an offline replay of the TS xApp's `cell_map` algorithm (`ts_xapp.cpp:331-373`) on that JSON.
- Q2 first: a null-control run in the R0 config counts LTE outage switches. ≥ 1 → substitution 1 (`--outageThreshold=-1000` for the gated runs, reported).
- T_ctl re-set from the measured L (trigger injected → `control` read by ns-3): T_ctl = max(30 s, 20 × L_max).
- C1–C9 hold; per-run RIC reset; rtmgr route dumps at start and end; 12041/12042 −1 owner in `verdict.json`; RestartCount = 0 for rc, kpimon, hw-go and every agent; report apply → HandoverEnd time (report only).

## Files
- Create: `scripts/gates/gate-r0-rc-scripted.sh`, `scripts/gates/rc-install.sh` (rc at the pinned SHA via the NIST installer path), `scripts/gates/ric-reset.sh`, `scripts/gates/rtmgr-route-dump.sh` (reuse `evidence/rtmgr-route-dump/` method), `scripts/gates/replay-ts-cell-map.py`, `scripts/gates/r0-scenario.json` (the scripted control list), `scripts/gates/check-c9-handover-trace.py`, `scripts/gates/repeat-gate.sh` (C1: 3 live runs + 1 replay + `--RngRun=2`).
- Modify: `scripts/run-to-m9.sh` (add gate r0).

## Steps
1. Install rc through `rc-install.sh`; confirm rc CONNECTED in e2mgr's view of xApps and RestartCount 0.
2. Q2 null-control run in the R0 config; count LTE outage switches in the ns-3 traces. Apply substitution 1 only if ≥ 1; report either way.
3. Calibration: 10 scripted controls; measure L; set T_ctl; record it.
4. G4 + offline cell_map replay on every gNB agent's nodeb JSON.
5. Write `r0-scenario.json` with the D7 three paths and the already-on-target refusal; run `repeat-gate.sh r0`.
6. Free-space check (`df` ≥ 20 GB + measured growth), then `vm-snapshot.sh create r0-green --need-gb <n>`.
7. Phase-exit checklist.

## Verify (comparison only)
- V1: `gate-r0-rc-scripted.sh` exits 0; `verdict.json` `c1.liveRunsEqual = true`, `c1.replayEqual = true`, `c1.rngRun2Differs = true`.
- V2: decoded wire: per control exactly 1 RICcontrolRequest and 1 terminal answer (paired by requestorId, instanceId); every ACK's ControlOutcome Format 1 decodes with the P0 decoder.
- V3: `verdict.json` `d7.viaEnb ≥ 1`, `d7.viaServingGnb ≥ 1`, `d7.viaTargetGnb ≥ 1`, `d7.distinctImsis ≥ 2`, `d7.targetGnbs ⊇ {2,3}`.
- V4: the refusal: one FAILURE `control-failed-to-execute`, ledger `outcome=refused cause=alreadyOnTarget`, 0 HandoverStart rows for it, ns-3 exit code 0.
- V5: `replay-ts-cell-map.py` prints every gNB agent key (`0000000202`, `0000000303`) and no eNB key.
- V6: `check-c9-handover-trace.py` exits 0 (each `applied` line has a later HandoverStart and HandoverEnd for that imsi and target; no orphan rows).
- V7: `verdict.json` has `restartCounts` all 0, `routeOwner12041`, `routeOwner12042`, `q2OutageSwitches`, `tCtlSeconds`.
- V8: `vm-snapshot.sh list` shows `r0-green`.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| D7: control at the node holding the UE context (eNB/MN, serving gNB) plus the TS xApp's target path | 3GPP TS 38.300 §9.2.3.1, §9.2.3.2.1; 3GPP TS 37.340 §10.5.1, §3; E2SM-RC v03.00 §7.6.4.2 | per decision record §2; `XRWZU3SS` | 2026-10-22 |
| Outage fallback stands in for SCG failure (−5 dB kept) | 3GPP TS 37.340 §7.7 | per decision record §2 | 2026-10-22 |
| Control Header UE ID — **recorded deviation P4** | E2SM common v07.00 §6.2.2.6 | `QW6VJ83M` | 2026-10-22 |
| Target NR CGI in the control message | E2SM-RC v03.00 §8.4.4.1 (Handover Control, RAN parameter 1 Target Primary Cell ID → 2 CHOICE Target Cell → 3 NR Cell → 4 NR CGI, an ELEMENT, "NR CGI IE in 3GPP TS 38.423 §9.2.2.7"; a missing Target Primary Cell ID gets a RIC CONTROL FAILURE); E2SM common v07.00 §6.2.3.7 (NR CGI = PLMN Identity + NR Cell Identity BIT STRING (SIZE(36))). rc carries the element as 9 raw octets `00‖PLMN‖5-byte key`, not the 36-bit encoding: this is covered by the recorded deviation N5/P2 (P1 ledger), nothing new; anything found beyond N5 is T4 | `XRWZU3SS`, `QW6VJ83M` | 2026-10-23 |

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
A red C1 is re-run only after its root cause is recorded and a change committed, then as a full fresh set.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P4.

## Risk and rollback
Risk: route ownership re-rolls per reset and an ack lands somewhere unexpected; RestartCount and route dumps make it visible. Rollback: revert VM to `f7-rerun-green`; revert harness commits.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K9.** Add one forced-late case with the RIC: a control that reaches ns-3 after its barrier gets exactly one wire RICcontrolFailure `control-failed-to-execute`, a ledger line `cause=late`, and no handover row. This is a separate scripted run, outside C1's digest set.
- **K10.** Add V9, which checks these verdict fields:
  - per applied IMSI, `kpmUeListMoved = true` (from decoded KPM UE lists);
  - `c5.pairsByReqId = true` and `c5.answerViaNodeId = true`;
  - reset evidence: pod UIDs and start times, and the Influx bucket id;
  - the `--RngRun=2` run exits cleanly, with C2 and C7 holding;
  - `ipcDropped = 0`, `droppedNoSub = 0`, `minSlack`.
- **K11.** C1 as read on 01:03 KST: the replay is compared on the ledger, IPC samples and traces.
- **P1-exit review (kongming 03:20, sequence-only move).** The wire extractor for C1's live-only components (per-step RC multiset, KPM headers, colletStartTime) is built here, before R0's first C1, not in P2. It writes `extra/rc-multiset.json`, `extra/kpm-headers.json` and `extra/collet-start-time.json` per live run; `digest-run.py --components ledger,ipc,traces,extra` fails when a run lacks any of them. Fixture-test it on an M7 pcap and the P0 probe fixture first. Triggers start only after the pacer has `steps k` (ns-3's notice that every agent has read sample k).

# P4: R1, scripted multi-control, unknown IMSI, fault run (ii); then Stop A

**Start state:** `r0-green`. **Snapshot at exit:** none (no `r1-green`, user decision).

## Context
The C4 sort key `(imsi, nodeId, targetCellId, ctlId)` decides which of two same-step controls for one IMSI applies; the second sees "in handover" synchronously (`lte-enb-rrc.cc:4519, 4493`). The bye/EOF rule (every pending control gets FAILURE) passes vacuously without a forced case (verifier-1723 #2).

## Requirements (contract)
R1, scripted through rc gRPC, lock-step, R0 config:
- (a) one same-step pair for two IMSIs through different agents, both applied;
- (b) one same-IMSI pair through **the same agent** with different targets: the lower `targetCellId` is applied, the other refused `inHandover`;
- (c) R1(d): one same-IMSI pair through **two agents**: the lower `nodeId` wins;
- (d) one unknown-IMSI refusal (`unknownImsi`);
- (e) fault run (ii): a control after the final barrier gets exactly one RICcontrolFailure on the wire (bye/EOF FAILURE-all-pending).
- D7 three paths hold again (eNB, serving gNB, target gNB ≥ 1 each). C1–C9 hold.
- Archive the Influx dump of one live run (UL off; kept as evidence only, never used as QP input).

## Files
- Create: `scripts/gates/gate-r1-rc-multi-control.sh`, `scripts/gates/r1-scenario.json`, `scripts/gates/influx-dump.sh` (reads with the deployed token from the VM file; the dump is scrubbed and the token never leaves the VM).
- Modify: `scripts/run-to-m9.sh` (add gate r1).

## Steps
1. Write `r1-scenario.json` with cases (a)–(d); run `repeat-gate.sh r1`.
2. Run fault run (ii) as a separate scripted run (not part of C1's digest set).
3. Archive the Influx dump of live run 1.
4. Phase-exit checklist.
5. **Stop A** (end of segment 1):
   - write the milestone report `plans/reports/milestone-<ts>-GH-1-m8-m9-segment-1-stop-a.md` and a journal `docs/journals/<date>-m8-m9-stop-a.md`;
   - kongming (opus) segment review, as an advice report next to the journal;
   - disk ledger: `df`, chain sizes, the updated M9 projection; if the projection is negative, the report lists the options (free space outside VM images; fewer dev snapshots; a user-approved deletion after `r3-green` and the reference, measured first, since a non-leaf delete frees almost nothing);
   - update the resume card to "next: P5" and push;
   - print `PAUSE A evidence=<path> journal=<path>` and call no further tool.

## Verify (comparison only)
- V1: `gate-r1-rc-multi-control.sh` exits 0; `verdict.json` C1 fields all true.
- V2: ledger: case (a) two `applied`; case (b) `applied` for the lower `targetCellId`, `refused inHandover` for the other; case (c) `applied` for the lower `nodeId`; case (d) `refused unknownImsi`.
- V3: C2 count identity: #terminal answers = #ledger lines + #agent-local FAILUREs (static rejects = 0, post-bye counted separately).
- V4: fault run (ii): exactly 1 RICcontrolFailure for the late control on the wire, 0 ledger lines for it.
- V5: `verdict.json` `d7.viaEnb ≥ 1`, `d7.viaServingGnb ≥ 1`, `d7.viaTargetGnb ≥ 1`.
- V6: the Influx dump file exists, and the token-pattern grep over it = 0.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| Refusal and post-bye answers are RICcontrolFailure with a cause | E2AP v03.00 §9.2.1; RIC Control procedure | `WEE5IEXF` | 2026-10-22 |
| D7 paths (as in P3) | 3GPP TS 38.300 §9.2.3; 3GPP TS 37.340 §10.5.1 | per decision record §2 | 2026-10-22 |

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
Run the plan's phase-exit checklist and kongming go/no-go, then Stop A as in step 5.

## Risk and rollback
Risk: case (b) and (c) interact if scheduled in the same step; keep them in different steps. Rollback: revert VM to `r0-green`.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K5 (cases b, c).**
  - (b): the UE is on cell 3; in one step, through the same agent, targets 2 and 3. Target 2 (the lower `targetCellId`) is applied; target 3 is refused `inHandover`.
  - (c): the same IMSI, one non-serving target, through two agents. The lower `nodeId` is applied; the other is refused `inHandover`.
  - V2 reads accordingly.
- **K10.** Verdicts carry `c5.pairsByReqId`, `c5.answerViaNodeId`, `ipcDropped`, `droppedNoSub` and `minSlack`.
- **Stop A disk.** The Stop A report includes the K2 projection with measured segment-1 growth.

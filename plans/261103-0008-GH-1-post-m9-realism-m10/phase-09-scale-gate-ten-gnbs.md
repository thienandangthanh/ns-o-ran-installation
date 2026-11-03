# P09 (MD): scale gate with ≥ 10 gNBs

**Start state:** checkpoint-2 pins; `f7-rerun-green`. **Snapshot at exit:** none. **Note:** s10 is validated here at cp2 pins and validated again at cp3 pins in P11 before the cp3 tag (after T-C: `UseIdealRrc`, the NR PDCP header and the P9 counter).

## Context
M9 ran 2 gNBs, so cell IDs ≥ 10 and the 8-neighbour cap have never been exercised (run report, scale ruling). The KPM neighbour list is capped at `E2SM_REPORT_MAX_NEIGH = 8` [V `ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.h:71`]. The neighbour map includes the serving cell, so N = 9 gNBs reaches only 8 neighbours. N ≥ 10 is needed (brainstorm verifier spot-check). `nMmWaveEnbNodes` is a scenario global [V `scratch/scenario-zero.cc:283`, used `:540-544`]. With N = 10 the gNB cellIds are 2–11, so cells 10 and 11 exercise IDs ≥ 10 [I: LTE eNB is cell 1, gNBs follow]. The simTime comes from AC6b's measured rate (P01).

## Requirements (contract)
- **AC15:** `nMmWaveEnbNodes ≥ 10` with all 11 agents CONNECTED.
  - Influx = IPC for every node and every seq.
  - Non-vacuity: at least one UE period in which ns-3 measured more than 8 neighbours, and the decoded KPM carries exactly 8.
  - Cell IDs ≥ 10 appear in the decoded KPM and in the TS xApp's cell map, with at least one applied PSCell change (Style 5 action 3, P07) to such a cell.
  - simTime is set from AC6b's rate so that the step takes ≤ 45 min.

## Design
- `scripts/gates/gate-s10-scale.sh` (M10 step `s10`) runs lock-step with 10 gNBs and 11 agents (ports 38470 + cellId), the TS xApp and the R3′ predictor (or a scripted Style 5 control through `rc-send.sh` to a cell ≥ 10 if the predictor schedule has no such target [I]; the choice is pre-registered here before the first run). The scenario JSON `scripts/gates/s10-scenario.json` fixes simTime, UEs per gNB, the trigger and the target cell ≥ 10.
- Neighbour non-vacuity: compare the ns-3 per-UE measurement count (ns-3 trace `LteDlRsrpSinrStats.txt` / `MmWaveSinrTime.txt` per UE per period [I: the source file is fixed in dev]) with the decoded Format 2 neighbour count.

## Files
- Create: `scripts/gates/gate-s10-scale.sh`, `scripts/gates/s10-scenario.json`, `scripts/gates/check-s10-neighbours.py`.
- Modify: `scripts/gates/agents.sh` (N agents), `scripts/gates/rung-config.json`, `tools/e2-evidence/influx-vs-trace.py` (N nodes), `scripts/gates/replay-ts-cell-map.py` (N keys).

## Design (addition)
- The TS xApp builds its cell map only at start [V `ric-app-ts/src/ts_xapp/ts_xapp.cpp:890`]. s10 restarts the TS xApp after all 11 agents are CONNECTED (the r2 pattern), then checks the map.
- The AD stand-in names the UE by its Influx `ueId` (P06b); the control is Style 5 action 3 to the source en-gNB (P07).

## Steps
1. Pre-register `s10-scenario.json` (simTime from AC6b, ≤ 45 min with margin; the target cell ≥ 10).
2. Dev run; measure disk growth and wall time for the budget.
3. On a red: Failure Protocol. A change to the scenario after its first run is PAUSE T3.
4. Phase exit.

## Validation
- `verdict.json`: `agentsConnected == 11`, `influxEqualsIpc: true` (all nodes, all seqs), `ueTicksWithMoreThan8Measured ≥ 1` with `decodedNeighbours == 8` for those ticks, `cellIdsGe10InKpm ⊇ {10, 11}`, `tsCellMapKeysGe10 ⊇ {10, 11}` (NCI keys per R-3), `appliedPscellChangesToGe10 ≥ 1`, `stepWallS ≤ 2700`.
- `s10_e2ap_ppid70_every_node`: every one of the 11 nodes sends PPID-70 chunks and nothing else toward e2term, judged with `--node-ips` (AC11 judged per node in P13; P05 exit review).

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| Neighbour cap of 8 in the KPM UE report (ns-3 model limit, disclosed) | KPM v03.00 §8.2.1.4.2 (Format 2) | `F82PYZVK` | to cite |
| PSCell change to a cell ≥ 10 | E2SM-RC §8.4.6.3 (via P07) | `JRDTL7XS` | to cite |

## Risks
- The 10-gNB rate makes 45 min too short for a decision (Medium/Medium). Mitigation: AC6b sizes simTime first; the trigger is placed early.
- Host memory or CPU with 11 agents (Medium/Medium). Mitigation: AC6b measures it; the agents' container limits are unchanged.
- Disk growth from 11 captures (Medium/High). Mitigation: capture filters as in M7; growth feeds T′.

## Rollback
The gate is additive; delete the commits.

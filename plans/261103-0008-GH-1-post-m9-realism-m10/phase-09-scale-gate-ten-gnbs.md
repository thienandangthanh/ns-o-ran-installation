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

## Hand-offs from the P06 exit review (kongming-261104-1340)
- Before the s10 run, replay the TS xApp key parser (`replay-ts-cell-map.py`) on synthetic e2mgr records for gNB IDs 2–12 and require no cross-node key.

## Hand-offs from the P08 exit review (kongming-261105-1606)
Do these in order, after the Stop A′ rulings.
1. **p12 at the cp2 pins first.** Run it right after the prefix (M2–I2) and before any s10 run.
   - p12 last passed at the P06b pins (`p12/20261104T104145Z`, harness 28d4508).
   - P07 then changed the per-seq UE context that p12's 10-record indications use.
   - This re-proves AC10 before any T-C code, and gives P11 the cp2 baseline it needs to attribute P15's change.
2. **The P08 safeguards:** start from a revert (about 80 GiB on /home), reuse the frozen-checkout chain driver and its run-dir cross-check, and keep the 22 GiB watchdog.
3. **Cells 10 and 11 bring the first live hex letters** (`en_gnb_001_001_0000000a`, key `0000000A10`). The replay models the TS xApp's upper-casing of the meid suffix (`replay-ts-cell-map.py:11,61`), but no live run has exercised it. The dry run in the P06 hand-off above covers this; it must include IDs 10 and 11.
4. **Record that the 60 s Influx window holds** at s10's report rate (kongming-261105-0536).
5. **The s10 scenario must steer at least one UE to a cell ≥ 10,** so AC15's applied PSCell change reaches a hex-letter cell.

## Stop A′ rulings that bind this phase (2026-11-05 23:38 KST, `plans/reports/decisions-261105-2349-GH-1-m10-stop-a-prime-rulings.md`)
- **The serving cell (ruling 1).** P09 runs at the cp2 pins, so the TS xApp still takes the serving cell from the QP answer's first entry, as the cp2 form (phase-07 controller note). The R-4 change lands in P10, and s10 is re-validated at cp3 in P11 with the new TS xApp.
- **A docs commit (extra item).** Fix the kpimon description in `docs/system-architecture-l-release.md`, as its own docs commit in this phase:
  - line 7 ("patched only for an 8-byte TimeStamp") and §6 ("Nothing else in kpimon changes") are out of date;
  - describe all our layered changes:
    - the 8-byte TimeStamp (47920a4);
    - the configurable reporting and granularity periods, with subscription by measurement ID (4b4a61a, 809fb2d);
    - the eNB measurement lists from `enb-kpm-measurements.json` (75e80ba);
    - the `ueId` tag on UeMetrics (89d45af);
  - point to `install_xapp_kpi_monitor.sh:38-59` and `patches.manifest` as the authority, without copying their detail.
- **VM image prune (ruling 3):** dangling images only, and only above 75 % guest root. Log `docker system df` and the removed IDs before and after. Never during a gate.
- **Codex triage (ruling 7):** kongming-261105-1050's rule. No harness commit lands while a chain runs.
- **/mnt/data (ruling 8):** 18 GiB free. Archive this phase's raw evidence to the existing location.


## s10 build review (controller, 2026-11-06 ~00:55 KST)
Built offline by a subagent (`plans/reports/fullstack-developer-261106-0008-GH-1-p09-s10-gate-build.md`). It is reviewed here before its first run; the scripts are committed only after the P09 prefix chain ends (Stop A′ ruling 7).
- **Neighbour source fixed (resolves the `[I]` above):** `MmWaveSinrTime.txt`. The same trace source fills the KPM neighbour map (`ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:302-303, 349-372`). measured(g, s, i) counts the distinct cells other than g in [t_s − T + 1 ms, t_s − 1 ms], only while i is in node g's IPC sample at s − 1 and s. The decoded side is the 8 slots `ns3.l3.nbr1..8.cellId`. Pass: at least one tick with more than 8 measured, and each such tick decodes exactly 8; no decoded list repeats a cell or names its serving cell.
- **Interpretations accepted:**
  1. The outage threshold follows rung-config substitution 1 (−1000), like every gated rung.
  2. The trigger UE must be held by exactly one en-gNB at the trigger step, so the source node is unambiguous.
  3. A decoded list may not repeat a cell or name its serving cell. AC6b's 10-gNB data passes it: 1140 ticks with 9 measured and 8 decoded.
  4. The Influx window is [first controlRx − 60 s, trigger].
  5. `s10_e2ap_ppid70_every_node` is emitted under its pre-registered name.
  6. `--indicationPeriodicity=0.1` is passed explicitly.
- **Shared-file changes:** `ts-rung-lib.sh` gains `RUNG_NNODES` and `RUNG_SUBSCRIBE_WAIT_S`, with defaults that keep the old behaviour (ledger row 145). `lint.sh` gains three registrations. `no_stray` and `agents_hygiene` miss ports 38480–38481, so s10 adds its own check, `s10_no_socket_on_agent_or_pacer_ports`, rather than change a shared predicate.
- **Lint:** red only on the host disk watchdog self-test, which hits lint's 60 s bound on a host loaded by the running chain and passes alone. lint.sh is re-run green after the chain, before the harness commit.
- **Finding for the user (not fixed; outside the contract's T-C list):** ns-3's neighbour loop at `mmwave-enb-net-device.cc:1001-1003` stops at `--sortFlipMap.begin()`, which is undefined behaviour. When a UE's SINR map has 2 entries and the serving cell is the strongest, it drops the only neighbour. On r2 this predicts all 594 KPM blocks that decode 0 neighbours where 1 was measured. It cannot bite with 10 gNBs (s10 needs only 8 of 9 neighbours), but it shapes the KPM neighbour lists of every 2-gNB rung (r0, r2, r3p) and their references. Listed for the user at Stop B as a disclosure candidate.

## Prefix chain and p12 at the cp2 pins (2026-11-05 15:20 – 17:40 UTC): 12 of 12 green
- **What ran:** the frozen-checkout driver `evidence/p09-chain/p09-gate-chain.sh` at harness 673fe7b (cp2 pins, plus docs-only commits), under `systemd-run --user` unit `p09-prefix-673fe7b`, from `f7-rerun-green`. It ran M2, M3, M4, M5, M6, M7, I0, Q8, R0 `--mode single`, R1 `--mode single`, I2 and p12. Every step exited 0, and p12's verdict is PASS with an empty failure list. Wall time was 2 h 40 min.
- **Disk:** /home fell from 74 to 46 GiB free across the chain, staying above the 22 GiB watchdog. /mnt/data had 18 GiB free (ruling 8 recheck).
- **Evidence:**
  - The driver tsv, step logs and as-run script are in `evidence/p09-chain/673fe7b/`.
  - The verdict layer and an `evidence-sha256.txt` for each of the 12 run dirs are committed with this record.
  - 1,627 raw files (115 MB) are archived as `/mnt/data/andang-data/ns-o-ran-installation-evidence/plans-evidence-raw-m10-p09a-20261106.tar.zst` (60 MB) with its `.list0`, both added to that folder's `SHA256SUMS` and verified.

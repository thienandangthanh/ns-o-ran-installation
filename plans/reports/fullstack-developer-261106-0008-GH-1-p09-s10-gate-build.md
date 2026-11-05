# P09 s10 scale gate: offline build report

Date 2026-11-06 (Asia/Seoul). Worktree branch `migrate-l-release-NIST-1-8-0`, harness HEAD 8aaee98, nothing committed.
Offline only: no VM, ssh or virsh, no git commit, push or stash. The running chain's frozen checkout and its watchdog
(PID 4061730) were not touched.

## Outcome

The gate `scripts/gates/gate-s10-scale.sh` is built.
- Its scenario, trigger rule, judges and neighbour non-vacuity rule are pre-registered and self-tested.
- Every predicate also has failing fixtures.
- bash -n and shellcheck (warning level) are clean.
- lint.sh passes apart from one failure that predates this work and does not involve any file I touched (see Tests).
- The KPM does carry the neighbour count (eight per-UE `nbrK.cellId` slots, noValue when absent), so this is not a
  NEEDS_CONTEXT case.

## Files

| File | Lines | Change |
|---|---|---|
| scripts/gates/gate-s10-scale.sh | 293 | new: the gate |
| scripts/gates/s10-checks.py | 753 | new: schedule, prepare, judges, `--self-test` (about 330 of the lines are the self-test) |
| scripts/gates/check-s10-neighbours.py | 368 | new: the neighbour non-vacuity judge, `--self-test` |
| scripts/gates/s10-scenario.json | 27 | new: the pre-registration |
| scripts/gates/ts-rung-lib.sh | +7/−5 | additive parameters (below) |
| scripts/gates/lint.sh | +3 | registers the two self-tests and the scenario lint |

These files are unchanged, because no change was needed:
- agents.sh
- rung-config.json
- influx-vs-trace.py (already filters by `--node`; `--every-seq` passed for the eNB and both gNBs on r2 data)
- replay-ts-cell-map.py

## Additive changes to shared files, and why existing callers are unaffected

- **ts-rung-lib.sh, `all_subscribed`.** The wait and the agent count are now
  `$(( $(date +%s) + ${RUNG_SUBSCRIBE_WAIT_S:-180} ))` and `awk -v n="${RUNG_NNODES:-3}" … exit !(ok == n)`.
  - r2 and r3p set neither variable, so they keep 180 s and 3.
  - The awk comparison is the same (numeric strnum). Checked with n unset, 3 and 11, and against the original
    expression on the same rows: identical exit codes.
- **ts-rung-lib.sh, `one_connection`.** The heredoc python gets `"${RUNG_NNODES:-3}"` as argv[2] and compares
  `len(em) == n` / `len(acc) == n`. With the default it is the old `== 3`.
- **ts-rung-lib.sh header.** A comment documents both optional variables.
- **lint.sh.** Three new lines after the r0-checks line. No existing line changed.
- No existing predicate changed (AC18).

Two port regexes miss the s10 agent ports 38480 and 38481: `no_stray` in ts-rung-lib.sh (`:3847[0-9]|:38499`) and
`agents_hygiene` in agents-ns3-run.sh. I did not widen them, because that would change the predicate for r2 and r3p.
Instead the gate adds its own check, `s10_no_socket_on_agent_or_pacer_ports`, with the regex
`:(3847[0-9]|3848[01]|38499)` over `ss -tlnp` and `ss -Sanp`.

## Neighbour pre-registration (file:line, forks at their current HEADs)

ns-3-mmwave-oran ea6e46f6, oran-interface 53253fe, O-RAN-Testbed-Automation 554d6d6.

- **Measured source (ground truth).** `MmWaveSinrTime.txt`, columns `time imsi cellId sinrDb`, in the run's ns3run dir.
  - It is written by `MmWaveBearerStatsConnector::PrintMmWaveSinr` (src/mmwave/helper/mmwave-bearer-stats-connector.cc:515-531).
  - That function is connected to `/NodeList/*/DeviceList/*/LteEnbRrc/NotifyMmWaveSinr` at :388-389. The file name
    is set at :260.
  - The same trace source feeds the KPM's map: `MmWaveEnbNetDevice::RegisterNewSinrReading`
    (src/mmwave/model/mmwave-enb-net-device.cc:349-372, connected at :302-303). It sets `m_l3sinrMap[imsi][cellId]`
    (:368) only while the IMSI is in that gNB's own `ueMap` (:352-363). The map is never cleared.
  - Every cell reports every UE every 1.6 ms (r0 cp2 live1: 6250 rows per (imsi, cell)).
- **Decoded field.**
  - ns-3 builds the list in `BuildRicIndicationMessageCuCp` (:925). `nNeighbours = E2SM_REPORT_MAX_NEIGH` (8,
    mmwave-enb-net-device.h:71), or map size − 1 when the map is smaller (:996). The loop over the SINR-sorted map
    skips the serving cell (:1001-1023).
  - oran-interface caps the list at `MAX_MEAS_RESULTS_ITEMS` (model/l3-rrc-measurements.cc:54).
  - The agent carries it as `ns3.l3.nbr1..8.cellId`: metric-map.v1.json gnb ue list orders 35, 38, …, 56 (measIds
    1035-1056), src `/cuCp/l3/neigh/K-1/cellId`. An absent value is noValue (src/metric-map.cpp:131). Format 2
    records are metric-major (src/kpm-indication-message.cpp:184-188).
- **Rule** (check-s10-neighbours.py, scenario `neighbours`).
  - measured(g, s, i) = the distinct cellIds ≠ g in the SINR rows of IMSI i with time in
    [t_s − T + 1 ms, t_s − 1 ms]. It is counted only when i is in node g's IPC sample at s − 1 and at s.
  - decoded = the non-noValue `nbrK.cellId` slots of the UE block that kpimon's library decodes from the capture.
  - The check passes iff:
    - at least one judged (UE, period) has measured > 8;
    - every such tick decodes exactly 8;
    - no block decodes more than 8, or repeats a cell, or names its serving cell;
    - the map has exactly 8 slots.
  - The window count is a lower bound of the map's entries, because the map is cumulative and the membership
    requirement keeps the UE in g's ueMap.
- **Finding (ns-3 undefined behaviour, does not affect s10).** The loop stops at `it != --sortFlipMap.begin()`
  (:1002).
  - In libstdc++, decrementing `begin()` returns `end()` unless the tree's root is its leftmost node. That is only
    possible with at most 2 entries; in that case it returns `begin()`, so the lowest-SINR entry is skipped.
  - On r2 live1 (2 gNBs) this predicts the 82 UE blocks that decode 0 neighbours where 1 was measured, matching 594
    of 594 blocks.
  - With 3 or more entries the root always has a left child, so the loop visits every entry. s10's judged ticks have
    ≥ 10 entries.
  - It does matter for anyone who reads the neighbour lists of the 2-gNB rungs (r0, r2, r3p).

## Scenario (scripts/gates/s10-scenario.json, `_comment` abbreviated)

```json
{
 "_comment": "s10 (AC15) … Each trigger's prepare picks the UE by rule: … the lowest IMSI held by exactly one en-gNB at that step (ctx(g, step) of one gNB node g only), g not the target and not in excludeServing, and not used by an earlier trigger; S = g. A trigger whose rule finds no UE fails the run (no fallback). The stub answer is [[key(S), [servingDl, ul]], [key(target), [targetDl, ul]]], serving first … key(c) = %08X10 …",
 "simTimeS": 8,
 "simTimeProvenance": "… AC6b: 171 wall s per sim s …; 600 s pre + 8 x 171 s + 120 s post = 2,090 s",
 "nMmWaveEnbNodes": 10, "handoverMode": "NoAuto", "indicationPeriodicityS": 0.1,
 "outageThresholdFrom": "rung-config.json scenario.outageThreshold_dB (substitution 1: gated runs use -1000)",
 "agentPortBase": 38470, "prepareTimeoutS": 30, "subscribeWaitS": 240,
 "triggers": [{"step": 30, "target": 10}, {"step": 50, "target": 11}],
 "excludeServing": [10, 11],
 "answer": {"servingDl": 100, "targetDl": 300, "ul": 0},
 "neighbours": {"maxNeigh": 8, "sinrTrace": "MmWaveSinrTime.txt", "guardMs": 1, "_comment": "…"},
 "expectCellIdsGe10": [10, 11], "influxWindowS": 60, "stepWallMaxS": 2700
}
```

## Gate flow

1. Read the scenario, then export NS3_TIMEOUT_S = 8·300 + 600 = 3000 before sourcing.
2. Source lib, bringup, capture, kpimon, agents, rc-lib, ts-lib, paced-lib, influx-dump and ts-rung-lib.
3. Set `RUNG=s10`, NODES = enb:1, gnb:2..11, `RUNG_NNODES=11`, `RUNG_SUBSCRIBE_WAIT_S=240`.
4. Run with CLI `--nMmWaveEnbNodes=10 --handoverMode=NoAuto --simTime=8 --indicationPeriodicity=0.1 --outageThreshold=<rung-config>`.
5. Run the config and provenance check (and `s10-checks.py scenario`), the three self-tests, and `rung_preconditions`.
6. Extract kpimon's .so and the decode harness into `$HOME/s10-work/so` (removed after the decode).
7. Run `rung_live live1 --dump` with two hooks:
   - **rung_stub_setup:** write the schedule, empty the stub, then save e2mgr `nodeb/states` and `nodeb/<meid>` for
     nodes 1..11. This happens after the TS xApp restart.
   - **rung_judges:** expect, wire and stub.
8. Run the verdict checks below, then disk, `rung_final_facts`, `agents_hygiene`, the port check, and stepWallS.

## Checks → predicates

| Verdict fact | Check | Predicate |
|---|---|---|
| agentsConnected == 11 | s10_live1_e2mgr_nodeb_records_saved_after_ts_restart_all_nodes_connected | e2mgr CONNECTED names == meid(1..11), each once |
| (per trigger) | s10_live1_ledger_one_applied_line_per_trigger_via_its_serving_en_gnb | exactly one line (viaNodeId, imsi, targetCell, afterSeq) = (S, imsi, target, step), applied, sourceCell S; lines == triggers; late 0 |
| (per trigger) | s10_live1_wire_one_acked_style5_action3_request_per_trigger_to_its_serving_en_gnb | one RICcontrolRequest at the step whose I(ueId) is the IMSI, viaNode S, Style 5 / action 3, targetKey == key(target) uppercase, ack; requests == triggers |
| (per trigger) | s10_live1_injector_and_stub_one_request_and_answer_per_trigger | injector 30003 names U in step order, state 0; the joined stub log has one 30000 [U] per trigger, answered state 0 by exactly {U: answer}, serving first |
| influxEqualsIpc | s10_influx_equals_ipc_trace_every_seq_every_node | influx-vs-trace.py --every-seq --node n for n = 1..11 |
| (decode) | s10_kpm_every_indication_decoded_by_kpimons_library | pcap-to-lines count == harness records, all RC_OK |
| ueTicksWithMoreThan8Measured ≥ 1, decodedNeighbours [8] | s10_kpm_neighbour_list_exactly_8_when_more_than_8_cells_measured | the rule above |
| cellIdsGe10InKpm ⊇ {10, 11} | s10_kpm_names_cell_ids_10_and_11 | decoded F1 nodeId, F2 nodeId, servCellId and nbr cellIds ≥ 10 include 10 and 11 |
| tsCellMapKeysGe10 ⊇ {0000000A10, 0000000B10} | s10_ts_cell_map_replay_every_en_gnb_key_no_enb_key_no_wrong_node | replay-ts-cell-map.py on the saved records with --expect for all ten en-gNBs, --no-key for the eNB, --no-wrong-node; then keys ≥ 10 owned by exactly their own node |
| appliedPscellChangesToGe10 ≥ 1 | s10_applied_pscell_change_to_a_cell_ge_10_ledger_and_wire | applied ledger line to a cell ≥ 10 joined (rxSeq, viaNodeId, I(ueId)) to an acked Style 5 / action 3 request with key(targetCell) |
| influxWindowHolds | s10_trigger_ue_rows_inside_the_ts_xapp_influx_window | per trigger a UeMetrics row with ueId U whose _time is in [t_controlRx − 60 s, t_trigger] (pacer wall clock; raw Influx dump) |
| s10_e2ap_ppid70_every_node | s10_e2ap_ppid70_every_node (also s10_live1_… from rung_live) | e2-facts-query.py ppid --node-ips over all 11 nodes |
| stepWallS ≤ 2700 | s10_step_wall_within_budget | now − GATE_START_EPOCH |
| (cleanup) | s10_no_socket_on_agent_or_pacer_ports, s10_hygiene, s10_no_stray_process | no agent, ns-3 or pacer left; no socket on 38470-38481 or 38499 |

Facts recorded:
- triggers (step, imsi, ueId, S, serving and target keys)
- wallRate (whole run and steady state)
- disk (VM root delta, evidence, trace, ns3run and pcap bytes)
- ns3TimeoutS, scenarioSha256, pacerAbortReason

Capture filters are as in M7: `rung_live` uses capture_start docker0 'ip proto 132'.

## Offline test results

**Self-tests.** Every `--self-test` passes: s10-checks, check-s10-neighbours, replay-ts-cell-map, ue-id-prepare,
ue-context-map.

The required failing fixtures, all red as intended:

| Predicate | Fixture |
|---|---|
| Non-vacuity | "8 cells measured is never more than 8" |
| More than 8 decoded | "a 9-slot map decoding 9 neighbours" |
| Missing key ≥ 10 | node 11's record removed, so `--expect 0000000B10` fails |
| Wrong-node key | a key claimed by two nodes fails `--no-wrong-node`; a 0000000B10 owned by node 10 is not counted |
| A trigger with no qualifying UE | prepare fails before any stub load and writes no record |
| A control via the wrong node | wire `viaNode` 10; ledger `viaNodeId` 2 |

Further red fixtures:
- Neighbour judge: 7 decoded with more than 8 measured; a list naming its serving cell; a repeated cell; UE
  membership; a cell seen only at the window edges; a malformed SINR row.
- Checks script: refused lines; a lowercase key; Style 3 action 1; an extra request; a stub answer with the target
  first; the injector naming the wrong UE; a row 61 s old; a missing record; a stub answering the wrong table; a
  later trigger without the earlier record; six broken scenario copies.
- The prepare self-test runs against a local HTTP stand-in of the stub, checking for each trigger:
  - the pick (IMSI 1 is excluded on cell 10, IMSI 2 is on two cells, IMSI 3 is used);
  - a one-entry table;
  - the saved log part.

**Shell checks and lint.**
- bash -n and shellcheck at warning level: clean. The only notes are info-level SC2329 on hook-local functions,
  the same pattern as r2.
- lint.sh: one red line, `host disk watchdog self-test failed`, in both runs. It predates this work.
  - `scripts/vm/host-disk-watchdog-selftest.sh` is unchanged from HEAD.
  - Under lint's `timeout 60` it exits 124 at 60 s. Alone it passes in under 120 s.
  - It is a timing bound on this host; scripts/vm is outside my ownership.
  - Everything else in lint.sh is green, including the three new lines.

**Dry runs on real data** (copies in the scratchpad; nothing written under plans/ except this report):
- **Prepare and judges on r2 live1 (cp2, 2 gNBs, evidence/r2/20261105T044701Z).** I used a scenario variant with
  r2's first two triggers (steps 20 and 30, targets 2 and 3).
  - The rule picked exactly r2's actual trigger UEs: IMSI 1 on cell 3, then IMSI 3 on cell 2.
  - expect, wire, stub and influx-window pass on r2's own ledger, multiset, injector, stub log and Influx dump.
  - In the influx window, the latest row was 0.12 s old at the trigger, with 683 and 1110 rows inside the window.
  - applied-ge10 is correctly red (no cell ≥ 10 exists).
  - rate: 7.39 wall s per sim s.
- **kpimon decode of r2 live1.pcap.** I built the harness locally against a copy of a kpimon .so with TimeStamp
  SIZE 8. 716 indications decoded, all RC_OK (Format 1: 300, Format 2: 416).
  - The neighbour judge on this real decode is correctly red on non-vacuity (2 gNBs: at most 1 measured).
  - That run surfaced the ns-3 undefined-behaviour finding above.
- **Neighbour judge pass path at 10 gNBs (AC6b run, evidence/ns3-scale-ten-gnbs/20261102T182547Z).** That capture
  predates the PPID-70 fix and yields no decodable lines, so I rendered its IPC samples as `--records` lines in map
  order. Pass:
  - 1140 judged ticks, all with 9 measured and 8 decoded;
  - cellIdsGe10InKpm [10, 11] from nodeId, servCellId and nbr cellId.
- **influx-vs-trace --every-seq on r2 live1** (raw dump pivoted the way influx_export does): nodes 1 (eNB), 2 and 3
  all every_seq_equal, ueid mismatch 0.
- **Cell-map replay with the gate's own arguments** on the synthetic e2mgr records (evidence/p09-replay-dry, eNB plus
  nodes 2..11): pass, tsCellMapKeysGe10 [0000000A10, 0000000B10]. Without node 11's record it is red.

## Interpretations made (flag for review)

1. **Outage threshold.** I read "the probe's settings" as subject to substitution 1, so `--outageThreshold` comes
   from rung-config (−1000 dB). The AC6b probe ran with the default −5 dB.
2. **Uniqueness.** The rule requires the IMSI to be held by exactly one en-gNB at the step. A UE listed by two gNBs'
   contexts is skipped and recorded under `skipped`.
3. **Decoded-list validity.** The neighbour judge also rejects a decoded list that repeats a cell or names its
   serving cell (ns-3's loop skips m_cellId).
4. **influxWindowHolds.** The window is [first controlRx − 60 s, trigger], from pacer wall clock. It is inside every
   60 s query window the TS xApp can open between the trigger and its control.
5. **s10_e2ap_ppid70_every_node** is a gate-level re-query of the facts file that `rung_live` already judged as
   `s10_live1_e2ap_ppid70_every_node`, so the pre-registered name appears in the verdict.
6. **`--indicationPeriodicity=0.1`** is passed explicitly, as the probe did. r2 relied on the default.

## VM risks

- **Wall budget.** 80 steps at the AC6b rate (171 s per sim s) is about 1,370 s, plus preconditions. The preconditions
  include two RIC resets, two TS and stub pod resets, rmr-peer and rc-decoder builds, and the .so extraction. They are
  estimated at about 600 s, which leaves about 600 s of margin to 2700. A slower VM, or a long prepare (Influx confirm
  up to 20 s per trigger), eats into that.
- **Disk.**
  - MmWaveSinrTime.txt grows to about 1.5 M rows (AC6b at 4 s had 750 k).
  - The 11-node pcap and the IPC traces add to that.
  - The kpimon .so dir is removed after the decode.
- **TS xApp at 11 nodes.** `ts_nodeb_list_check` needs the TS log's nodeb list to name all 11 CONNECTED nodes. This
  is an existing check; the verdict facts do not rely on the xApp log.
- **Prepare ↔ pacer.** ns-3's GateTimeout bounds only the agents' step arrival, not the wait for `go`
  (oran-interface e2-control-hub.cc:727-755), so a prepare of up to 30 s cannot abort ns-3. A prepare failure aborts
  the run (pacerAbortReason fact).
- **Stub log resets on each table load.** The parts are saved before each load (s10/stub-log-before-<step>.json) and
  joined in step order with the final log.
- **Root required on the VM.** `kpimon_extract_so` needs docker or `sudo -n`, the same as p12.

Status: DONE_WITH_CONCERNS
Summary: Built the s10 scale gate, its pre-registered scenario, the trigger-prepare/judge script and the neighbour non-vacuity judge, all self-tested with failing fixtures per predicate and dry-run on real r2 and AC6b data. The only shared-file changes are default-preserving parameters in ts-rung-lib.sh and the lint registrations.
Concerns:
- lint.sh is red only on host-disk-watchdog-selftest. It predates this work: it exceeds lint's 60 s bound on this host, and scripts/vm is unchanged.
- ns-3's `--sortFlipMap.begin()` undefined behaviour drops the only neighbour in 2-entry maps. It does not affect s10, but it does affect the neighbour lists of the 2-gNB rungs.
- Six interpretations are flagged above, the outage threshold −1000 among them.
- The port regexes in no_stray and agents_hygiene miss 38480 and 38481. s10 covers them with its own check; the shared predicates were left unchanged.

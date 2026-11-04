# P06b AC18 inventory (KPM UE IDs, X2AP context export)

Date: 2026-11-04 (Asia/Seoul). Step 1 of `phase-06b-kpm-ue-ids-x2ap-context-export.md`: the rows go in before any code. Rows 79–100 are appended to `plans/261103-0008-GH-1-post-m9-realism-m10/check-diff-ledger.md`. All 22 are ordinary ("No"). None of them encodes P1, P5 or N5, so none is a registered contract change. No code was changed.

## Basis

- `ns3.imsi` stays a UE-scope KPM measurement (metric map measId 1004). This follows the controller's interpretation, which is disclosed and will be asked at Stop A′. kpimon adds the tag `ueId` (R-4 format) to UeMetrics points. So the Influx rows (85, 86, 87) keep their `(nodeId, seq, imsi)` value checks. They add one conjunct: each row's `ueId` must resolve to that row's `ns3.imsi` through the run's `e2-ue-context-*.jsonl`.
- Every UE ID is resolved by one shared definition, written in row 79:
  - ctx(n, s) is the `ues` of node n's last `ueContext` line with seq ≤ s.
  - R(n, S, id) is the IMSI whose R-4 ID equals id.
  - U(i) is IMSI i's gNB tag `enGnbUeId:<lteRnti>@00F110-<mnCellId %05X>`.
  - Row 79 anchors the map on ns-3's own `DlE2PdcpStatsLte.txt` (MN cell), not on the new IPC channel. This is what keeps the UE-list and Influx judges from being weaker after the IMSI leaves the UE ID.
- Pre-registered rows referenced, not duplicated: 27 (`r3p-scenario.json:17` is P4), 47 (rmr-peer self-test UE key), 56 (kpm-ue-list-moves judge), 8 and 60 (influx-vs-trace, p12), 9 (agent counters), 13, 16, 31 and 40 (P07 UE-ID parts).

## Rows by owner

**Shared identity map (new):** `tools/e2-evidence/ue-context-map.py` holds row 79 (context files consistent with the ns-3 MN PDCP trace, plus the definition of R) and row 80 (the R-8 live cross-check against `reference/identity-map-cp1.json`).

**KPM wire judges:**
- `tools/e2-evidence/kpm-ue-list-moves.py`: row 81 (en-gNB-UEID / eNB-UEID decode, resolution, zero gNB-UEID), plus row 82 (new M6/M7 calls with no ledger, which make the "Decoded KPM" Validation a gate verdict).
- `tools/kpimon-decode-harness/kpimon-decode-harness-records.c`: row 83 (`ueIds` replaces `amfUeNgapIds`).
- `scripts/gates/p12-records-check.py`: row 84.

**Influx judges:**
- `tools/e2-evidence/influx-vs-trace.py` (M6, p12, e2-evidence smoke): row 85.
- `scripts/gates/check-n6-influx-window.py` (R3′ N6): row 86.
- `scripts/gates/n6-fixtures.py`: row 87.

**AD stand-in, stub and predictor (verdicts at P07, the R2/R3′ boundary):**
- `r3p-checks.py` `c_stub`: row 88 (the AC18-named "decimal IMSI" stub check).
- `r3p-checks-fixtures.py`: row 89.
- `r3p-scenario.json:17`: row 90 (`:10` `ueKey` stays literal under the controller's interpretation).
- `r3p-predictor.py`: row 91 (answers keyed by ueId; records unchanged).
- `r2-checks.py`: row 92 (`cmd_stub`, also used by `r3p_<label>_calibration_stub`) and row 93 (schedule and table drivers).
- `send-rmr.sh` and `rmr-injector.py`: row 94.
- `rmr-peer-selftest.py`: row 95.

**IPC channel integrity (I-8):**
- `digest-run.py`: row 96. It exits 3, never 1, so `c1_rng2`'s "must differ" check cannot pass on a ueContext line that leaked into the ipc trace.
- `tools/ipc-null-sink/ipc-null-sink.py`: row 97. Without it, every M4 summary check would go red on the new line type.
- `agents-ns3-run.sh` `agent_counters_assert`: row 98 (`samplesNoUeContext`, `ipc.ueContextRejected`, `ipc.ueContext`).

**Secrets and kpimon guard:**
- `lint.sh` scrubber fixtures: row 99 (the `ueId` query case).
- New `e2-facts-query.py sub-actions` plus a facts extension: row 100 (kpimon Format-3-only; it must land before P06b's first kpimon VM run).

## Left to P07 (the plan assigns them there; no rows written now)

- `wire-c1-extract.py:192,245` (the RC header UE ID, rc-multiset `imsi` → `ueId`) and the r2/r3p wire `(imsi, step)` attribution (rows 13, 14).
- `pacer.py:63-77` replay.
- `r3p-prepare.py:48,74-79` and `r3p-schedules.py:31-32,57`.
- `rc-send.sh` (row 41), the R1 unknown-IMSI case, the e2i Style 5 injector cases (`gate-e2i-interop.sh:123-125`) and the seam smoke (G1).

## Checked and found unaffected

`influx-node-rows.py`, `influx_node_csv`, `kpimon.sh` measurement counts and `influx-dump.sh` read no UE key. The ledger-IMSI judges (`check-ledger.py`, `check-c9-handover-trace.py`, `check-actuation-delay.py`, `r3p-checks.py` expect/driven/membership) read ns-3's ledger `imsi`, which stays literal (R-2). `trace-facts.py` reads only hello, sample and bye.

## Observations

- The phase's Files list omits `check-n6-influx-window.py`, `n6-fixtures.py`, `ipc-null-sink.py`, `agents-ns3-run.sh`, `lint.sh`, `r3p-checks-fixtures.py`, `rmr-peer-selftest.py`, `e2ap-pcap-facts.py`/`e2-facts-query.py` and the new `ue-context-map.py`. Rows 86–89, 95 and 97–100 need them.
- The step 2–3 code (ns-3, oran-interface and agent `ueContext` export and encoding) is already in the working trees, uncommitted. To keep "rows before code" visible in history, the ledger rows should be committed before that code.
- R-4's "the IMSI stays inside the IPC" and the new schema text "the IMSI ... is never encoded" contradict the kept `ns3.imsi` measurement. This belongs in the Stop A′ disclosure.
- Row 84 resolves a Format 2 UE over the period's seqs. If a UE leaves a gNB mid-period while K > 1, the agent's "replace the whole set" context map would make it skip that sample (`samplesNoUeContext`). p12 has no handovers, but P07–P10 should keep K = 1 wherever handovers happen, or the agent should keep departed UEs until the period is reported.

## Unresolved questions

1. Under the other reading (`ns3.imsi` removed from the metric map and the KPM report), these changes would also be needed: Influx joins keyed on R(ueId) instead of ns3.imsi, `r3p-scenario.json:10` `ueKey` → `ueId` (not enumerated in R-2's T, so a T3 pre-registration change), the p12 per-block `ns3.imsi` record cross-check dropped, and new rows for `lint-metric-map.py`, the kpimon eNB measurement list and the M6 field counts. No rows were written for this reading.
2. The R-4 tag format is [I]. The rows pin `enGnbUeId:%d@00F110-%05X` (5 uppercase hex digits, as R-2's `macroEnbId` "00001") and `enbUeId:%d@%d`. Please confirm.
3. Step 5 names "an M7 run" for the R-8 cross-check against the cp1 map. M7's configuration (5 nodes) is not the cp1 configuration, so its RNTIs need not match. Row 80 applies the frozen map only to R3′-config runs, and M7 gets row 79's per-run anchor. Is that the intent?
4. The r2 stub table must be keyed by ueId before the first trigger (row 93). Should it be built from the run's context files at a barrier before the first trigger (as proposed), or from the frozen cp1 map, since R2's radio config equals cp1's?
5. Row 94 has the caller read the ueId from Influx right before the trigger. Should r2 reuse P07's `anomaly-from <file>` path (prepare writes the file after an Influx confirmation), or should the injector query Influx itself (credentials inside the rmr-peer container, T7)?
6. Row 100 decodes the action definition with `tools/asn1-indep` on the VM. Is the asn1-indep image acceptable as a dependency of every KPM gate (m6, m7, p12, the rungs), or should the check accept tshark's format label where it decodes?

# P03 (MB, T-B P12): KPM reporting period and granularity (option B)

**Start state:** P02 pins; `f7-rerun-green`. **Snapshot at exit:** none.

## Context
kpimon subscribes with a fixed 10 s reporting period (event trigger bytes `8, 39, 15` [V `install_patch_files/xApps/kpimon-go/control/control.go.previous:437`]) and a 10 s granularity (`granulPeriod = 10000` [V `install_patch_files/xApps/kpimon-go/e2sm/wrapper.c.patch:401`]). The agents ignore both: the subscription handler admits the actions and reports per ns-3 sample (`e2-session.cpp:150-174`), with `granulPeriod` set to the ns-3 period (`sample-forwarder.cpp:69`) [V, paths under `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/`]. The generator's not-admitted branch corrupts the PDU, so it is never used (`e2ap-builders.cpp:125-127`). Stock kpimon iterates the Format 1 `measData` list as if each item were a cell (`ric-app-kpimon-go/control/control.go:548-553`); how the NIST-patched code handles 10 records is [U] and is what AC10 tests.

## Requirements (contract)
- **AC10:** kpimon's reporting period and granularity are configurable; the gated rungs use T/T = 100/100 ms (R-6). The agent honours the action (option B); at T/T the output is unchanged (AC8). At granularity T with a 1 s reporting period: one indication per 10 seqs carrying 10 records, and Influx = IPC for every seq. A period that is not a multiple of T is answered as not admitted on the decoded E2AP. Because the period lives in the event trigger, which covers the whole subscription, the E2AP form of "not admitted" here is a RIC SUBSCRIPTION FAILURE, in which every action is not admitted (kongming #10; cause cited from E2AP v03.00). If kpimon cannot decode multi-record Format 1 without a decoder rewrite, SUB-P12 applies (G = P = 2T, one record per indication; the gap listed).
- **AC8 (run 2):** after P12 at T/T, R3′ C1 against the M9 reference passes again on every component.

## Design
- kpimon fork: the period and granularity come from the xApp config (`controls.reportingPeriodMs`, `controls.granularityPeriodMs` in `config.json`, default 100/100 for this testbed). The event trigger is encoded from the value, not a byte literal. This lives in the existing `control.go.patch` and `wrapper.c.patch`, and `install_xapp_kpi_monitor.sh` passes the values. The values are model parameters; no "M9 mode" exists.
- In M10, `p12` runs last (plan R-1). Every rung also asserts that the decoded kpimon subscription period is 100 ms (new check in `scripts/gates/ts-rung-lib.sh` and the rung gates).
- Agent: `summarize_subscription` (`e2ap-inbound.cpp:18-40`) also decodes the event trigger (Style 1 period) and the action definition (Format 1 granularity). `on_subscription` admits when P mod T == 0 and G == T. A trigger period that is not a multiple of T fails the whole subscription (RIC SUBSCRIPTION FAILURE, pre-registered cause). A granularity ≠ T on one action puts that action in a hand-built not-admitted list, not the generator's (`e2ap-builders.cpp:125`). The forwarder buffers P/T samples and emits one indication with P/T records (Format 1 cell, Format 2 UE). The header's collection start time is the first record's.
- SUB-P12 path, only if needed: also admit G = k·T and aggregate per metric-map row (`schema/metric-map.v1.json` gains `agg: sum|mean|last`, each justified in the standards ledger).

## Files
- Agent: `ns3_e2_agent/src/e2ap-inbound.cpp`, `e2ap-inbound.hpp`, `e2-session.cpp`, `e2-session.hpp`, `e2ap-builders.cpp` (not-admitted response), `sample-forwarder.cpp`, `sample-forwarder.hpp`, `kpm-indication-message.cpp`, `tests/` (new codec-probe cases).
- kpimon fork: `install_patch_files/xApps/kpimon-go/control/control.go.patch`, `install_patch_files/xApps/kpimon-go/e2sm/wrapper.c.patch`, `additional_scripts/install_xapp_kpi_monitor.sh`.
- Harness: `scripts/gates/kpimon.sh` (install values), `scripts/gates/gate-p12-kpm-period.sh` (new; becomes M10 step `p12`), `tools/e2-evidence/influx-vs-trace.py` (multi-record), `scripts/pins.conf`.

## Steps
1. Agent and kpimon changes; local codec tests: a 10-record Format 1 decodes with the NIST KPM decoder harness (`tools/kpimon-decode-harness`).
2. On the VM: M3 with kpimon at 100/100. Check the kpm_sim behaviour (finding F10); any M3 predicate change goes into the ledger first.
3. `gate-p12-kpm-period.sh`: (a) G = 100, P = 1,000 → decoded wire shows one indication per 10 seqs with 10 records; Influx = IPC per seq. (b) P = 150 → a decoded **RIC SUBSCRIPTION FAILURE**, because the period sits in the event trigger, which applies to the whole subscription. Its cause is pre-registered from the E2AP v03.00 text before code (plan R-6). (c) At the end of the step, kpimon is restored to 100/100 and the restored subscription is decoded. If (a) fails only in kpimon's decode, record the evidence, apply SUB-P12, and run G = P = 200.
4. M5–M7 re-pass; AC8 run 2 (R3′ C1 vs the M9 reference at T/T); archive.
5. Phase exit.

## Validation
- `gate-p12-kpm-period.sh` verdict: `recordsPerIndication == 10`, `indicationsPerTenSeqs == 1`, `influxEqualsIpcEverySeq: true`, `nonMultipleSubscriptionFailure: true` (cause as pre-registered), `restoredPeriodMs: 100` (or the SUB-P12 fields, with `substitutionP12Applied: true`).
- AC8 run 2: `equalsReference: true` against the M9 reference.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| Reporting period from Event Trigger Style 1 | KPM v03.00 §7.3.2, §8.2.1.1.1 | `F82PYZVK` (R4 read) | 2026-11-02 |
| Granularity = collection interval within the reporting period; records per indication | KPM v03.00 §8.2.1.2.3, §8.3.8, §8.2.1.4.1 | `F82PYZVK` | to cite |
| Not-admitted action answer | E2AP v03.00 §8.2.1.2 (RIC Subscription, unsuccessful/partial), §9.2.x RIC Action Not Admitted List | `WEE5IEXF` [C] | to cite |

## Risks
- kpimon's patched decoder may mis-store 10 records (High/Medium). SUB-P12 is the approved fallback; it is used only on evidence.
- At T/T, any byte change in the KPM header or message breaks AC8 (High/Low). Mitigation: a codec-probe byte-compare of T/T indications against M9 captures before the VM run.
- The kpm_sim reference node at M2/M3 may react to 100 ms (Medium/Unknown, F10).

## Rollback
Re-pin the previous Testbed SHA; kpimon reinstalls from the pinned patch set.

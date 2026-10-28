# P8′: R3′, TS xApp with a harness predictor that reads Influx by sim time

**Start state:** the VM after P6's exit (descends from `r2-green`, not reverted). **Snapshot at exit:** `r3p-green`, only after the free-space check. Added by amendment A1 (user ruling S1, 2026-10-27; contract approved 23:24 KST). Replaces the deferred P7/P8 on the M9 path.

## Context
- R2 proved the official TS xApp control chain (A1 policy, RMR 30003/30002, rc gRPC, E2SM-RC, ns-3 handover) with C1, but its predictions are fixed in the stub's table, so no rung yet shows KPM → Influx → decision → RC → handover (Codex skeptic, `brainstorm-261027-2241` debate).
- The stub QP is harness code: `tools/rmr-peer/stub-qp-rmr-peer.py` (pod `ricxapp-stubqp-*`), loaded per trigger with a table by `gate-r2-ts-stub-qp.sh` (`stub_table_load`). rtmgr already routes 30000 → stub and 30002 → TS xApp (R2 check `routes_30002_20010_to_ts_30000_only_to_stub`).
- ns-3 is frozen at barrier T, so Influx holds no T+1 rows (K2), and kpimon writes out of order; the pacer must certify the window's rows in Influx before it triggers the TS xApp (N6). NIST's QP reader used a wall-clock window (`range(start: -1600ms)`), which is meaningless under lock-step pacing; the predictor reads by `ns3.seq`/sim time only.
- Scenario-zero's per-gNB-cell DL is constant after a 3-sample start-up ramp (8371 / 4186 kbit, `brainstorm-261027-2155…qp-training-scenario-fit.md`). Whether a pre-registered formula on those values moves a UE past the TS xApp's 10 % A1 threshold is the load-bearing assumption; the dry run (step 4) decides it, and substitution 4 covers a vacuous result.
- The Influx token lives only in the VM's `influxdb_auth_token.json`. The predictor must never place it in a public tree, a committed file, an evidence file or a pod spec that is committed (T7).

## Requirements (contract A1)
R3′: the real TS xApp plus the harness predictor, fixed pre-registered trigger schedule (`r3p-schedule.json`).
- ≥ 1 handover applied from a predictor decision; every trigger's outcome (control or none) identical across C1's 3 live runs; C1–C9.
- For every trigger: the 30002 values equal the pre-registered formula applied to Influx over the trigger's sim-time window; Influx = IPC for the counter(s) read (full, duplicate-free, no missing seq).
- N6 (membership-aware): before each trigger the pacer certifies the `cellMetrics` rows of every seq in the window for every expected gNB cell, and, for the triggered IMSI, exactly the `UeMetrics` rows at seq T that the agents' IPC samples at T list (UE membership is disjoint across gNBs, e.g. `031836Z` seq 20: node 2 lists IMSIs 3–6, node 3 lists 1–2); it checks that the IMSI's serving cell is consistent between IPC and Influx and that no handover of that IMSI is in progress at T. This replaces K6's "from each gNB agent".
- A pre-registered controlled change of the observations changes the decision; after a handover, the predictor observes the changed serving-cell membership.
- eNB rows excluded; `ue-id` = decimal IMSI; target-addressed controls recorded as deviation P1.
- HandoverStart row count = applied count; zero handover rows in the R3′-config null-control run.
- W = max(1 s, 3 × p99.9) from a calibration run.
- Per-run reset of rc, TS xApp, stub/predictor, fresh Influx bucket; RestartCount = 0 for rc, TS xApp, stub, kpimon, hw-go and every agent; route dumps; the −1 owner recorded.
- A `--reference` mode on the gate, so P9/P10 compare against `reference/r3p/` (and `gate-r2-ts-stub-qp.sh --reference` for substitution 4).
- Measure the overlay growth for the M9 budget.

## Files
- Modify (host helpers): `scripts/vm/vm-common.sh` (`gate_id` regex to `^gate-([a-z]+[0-9]+[a-z]?)-` so `gate-r3p-…` → `r3p`, with its K24 self-test extended: `m5 r0 s1 q7 r3p`; protection of the top rung's green snapshot: `r3p-green` always, `r2-green` when substitution 4 is recorded; `vm-snapshot.sh check-protected` self-test for both), `scripts/gates/lint.sh` if it enumerates gate ids.
- Create: `scripts/gates/gate-r3p-ts-predictor.sh` (modes `c1|single|calibrate|dryrun`, plus `--reference <dir>`), `scripts/gates/r3p-predictor.py` (the pre-registered formula; reads a scrubbed Influx window, writes the per-trigger table and a decision log), `scripts/gates/r3p-checks.py` (Influx = IPC for the read counter; predictor-output equality; observation-change and membership-change checks), `scripts/gates/check-n6-influx-window.py` (cell and UE cases), `scripts/gates/r3p-scenario.json`, fixtures under `scripts/gates/fixtures/`.
- Modify: `scripts/gates/pacer.py` (N6 window certification hook), `scripts/gates/gate-r2-ts-stub-qp.sh` (`--reference` mode only; no change to its c1/single/calibrate judgement), `scripts/gates/rung-config.json` (`r3pConfig` with its own `W_s` value and provenance naming `evidence/r3p/`; R2's `deadlines.W_s` and its `evidence/r2/` provenance stay unchanged, because `gate-r2-ts-stub-qp.sh` `cfg_ok` requires it), `scripts/run-to-m9.sh` (steps for R3′; see P9).
- Reuse unchanged: `tools/rmr-peer/stub-qp-rmr-peer.py` and its install path, unless step 1 records why a change is needed.

## Steps
1. **kongming before code** (opus): pass this Context; ask for the predictor design and the pre-registration list. Default design to evaluate first: the predictor runs host/VM-side in the harness at barrier T (after N6 certification), computes the 30002 answer for the triggered UE from the Influx window, and loads it into the existing stub through `stub_table_load`; the stub stays a dumb RMR peer, so no Influx token enters any pod.
2. **Spec check, then pre-register** in `r3p-scenario.json` and `rung-config.json` (commit before any R3′ VM run): the counter(s) read (default `DRB.PdcpSduVolumeDL`; UL flag on or off), the window (16 seqs ending at T, unless kongming advises otherwise), the formula mapping per-cell volume and serving-cell membership to the TS xApp's per-cell predicted throughput, the observation-change control, the A1 threshold, and the **candidate domain** for the dry run, derived only from configuration (the scenario's IMSIs, and the seq range from the first full window after the start-up ramp to the last seq before the run's tail, from the pre-registered window length and sim time), never from observed data; it must be non-empty when committed. Ledger row: 3GPP TS 28.552 §5.1.2.1.1.1 (`5SZUBP6M`) for using PDCP SDU volume as the throughput input; a deviation, if any, is T4.
3. Build the gate, predictor and checks; self-test fixtures (pass; fail on a missing seq, a duplicate (node, seq), an eNB row, a float field, a predictor answer that differs from the formula).
4. **Dry run** (null-control lock-step in the R3′ config, one live run): record the Influx windows, evaluate the formula offline over the whole pre-registered candidate domain, and classify the dry run as exactly one of:
   - **invalid**: any missing or duplicate row, Influx ≠ IPC for the read counter, or an N6 failure anywhere in the committed domain (no candidate may be dropped for bad data) → Failure Protocol; never substitution 4;
   - **valid, schedule formed**: choose ≥ 1 trigger whose decision is a handover, ≥ 1 trigger whose decision is none, and one trigger after the first handover to show the membership change; write `r3p-schedule.json` and commit it before step 5;
   - **valid, no handover in the whole domain**: **substitution 4** — commit `r3p-substitution4.json` (dry-run evidence dir, config and scenario sha256s, the per-candidate decisions), report, mark P8′ "dropped (substitution 4)", and go to P9 with R2 as the top rung;
   - **valid, a handover candidate exists but a required schedule element cannot be formed** → T3 (not substitution 4).
5. Calibration run; measure L; set W; record it in `rung-config.json` with the evidence dir.
6. R3′-config null-control run: 0 HandoverStart rows.
7. Observation-change control: the pre-registered change of the observations (step 2) gives the pre-registered different decision (live run, or the RIC-free predictor replay on recorded rows, as pre-registered).
8. `gate-r3p-ts-predictor.sh --mode c1` (3 live runs + RIC-free replay; `--RngRun=2` changes the digest).
9. Record the image chain sizes; compute the measured M9 overlay estimate.
10. Free-space check, then `vm-snapshot.sh create r3p-green --need-gb <n>`.
11. Phase-exit checklist.

## Verify (comparison only)
- V1: `gate-r3p-ts-predictor.sh --mode c1` exits 0; `verdict.json` C1 fields all true.
- V2: `verdict.json` `predictorDrivenApplied ≥ 1`; per trigger, the outcome list is identical across the 3 live runs.
- V3: `r3p-checks.py` exits 0 on every run: per trigger, 30002 values = formula(Influx window); Influx = IPC for the read counter(s) with no missing seq and no duplicate.
- V4: `check-n6-influx-window.py` exits 0 for every trigger (every window seq present per gNB cell, and the UE row at T, before release).
- V5: HandoverStart rows = ledger `applied` lines; the null-control run has 0 HandoverStart rows.
- V6: the observation-change control gives the pre-registered different decision; the post-handover trigger's predictor input shows the UE in its new serving cell.
- V7: `verdict.json` `restartCounts` all 0, `wSeconds`, `routeOwner12041`, `routeOwner12042`, `substitution3Applied`.
- V8: `vm-snapshot.sh list` shows `r3p-green`; `evidence/p8b-disk/<ts>/chain-sizes.txt` exists.
- V9a: the dry-run classifier's fixtures: missing data in the only handover-producing candidate → invalid (not substitution 4); an empty domain → refused at commit; a complete domain with no handover → substitution 4; a candidate without a formable schedule → T3.
- V9: `gate_id` self-test prints `m5 r0 s1 q7 r3p`; `vm-snapshot.sh check-protected r3p-green` prints `protected`; `gate-r2-ts-stub-qp.sh` `cfg_ok` still passes against the final `rung-config.json`; N6 fixtures pass a healthy disjoint-membership case and fail a missing expected UE row.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| Predictor input: PDCP SDU volume as the per-cell throughput basis | 3GPP TS 28.552 V20.2.0 §5.1.2.1.1.1 (and §5.1.2.1.2.1 if UL is read) | `5SZUBP6M` | read in step 2 |
| Target-addressed control — **recorded deviation P1** | 3GPP TS 38.300 §9.2.3; 3GPP TS 37.340 §10.5.1 | per decision record §2 | 2026-10-22 |
| UE ID — **recorded deviation P4** | E2SM common v07.00 §6.2.2.6 | `QW6VJ83M` | 2026-10-22 |

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
A red C1 is re-run only after its root cause is recorded and a change committed, then as a full fresh set. A pre-registered value (counter, window, formula, schedule, observation-change control) never changes after the run that uses it; a needed change is T3. A vacuous dry run is substitution 4, not T3.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P9.

## Risk and rollback
Risk: no seq moves a UE past the 10 % threshold (substitution 4); the predictor's Influx read races kpimon (N6 catches it); wall jitter in the TS xApp exceeds W (T3, never raise W blindly). Rollback: revert the VM to `r2-green` and re-run M4, M5 and the P6 builds; revert the harness commits.

## Step-1 amendment (binding, 2026-10-28; kongming counsel, not user approval)
Source: `plans/reports/kongming-261028-1220-GH-1-p8b-r3prime-predictor-design-and-preregistration.md`. Every item adds verification or fixes an underspecified point; none changes an acceptance signal, a recorded user ruling or the scope. The formula is the "persistence forecast" of option B, which the user chose (`brainstorm-261027-2241` §5 B, ruling S1).
- **Design: go on the default** (VM-side predictor in the harness, stub QP unchanged as a dumb RMR peer, the Influx token stays inside the InfluxDB pod). Rejected: a predictor in a pod (T7), host-side over ssh, reading IPC directly (bypasses Influx).
- **Pacer `prepare` hook (schedule entry field `prepare: {cmd, timeoutS, mayFail}`)**, run after `steps T` and before the trigger's `t0`, so N6, the predictor and the stub load never count toward L or W. Absent `prepare`, R0–R2 schedules behave as before (pacer self-test; plus one `gate-r2 --mode single` after the hook lands).
- **Stub unchanged; reason recorded (step 1):** `PUT /table` resets the stub's counters and log, so the prepare step saves `GET /log` before every PUT; the parts are joined in step order.
- **Formula `persistence-window-sum-v1`:** per gNB cell, the sum of `DRB.PdcpSduVolumeDL` over seqs T−15..T (integer kbit), UL 0, serving cell first (the gNB whose UeMetrics row at T lists the IMSI), then by ascending nodeId. Per-UE-share formulas are rejected: under the scenario's CBR they equal the CBR rate in every cell, so they never cross 10 % (substitution 4 by construction). Recorded honestly: under CBR the per-cell volume is a proxy for the UE count, and prediction quality is out of scope.
- **Step 4 becomes a two-stage dry run.** Stage A: null-control with the RIC up, a prepare-only observe entry at every T of the domain. Its classification is committed before stage B. Stage B: the same plus a pacer inject of h1's control at h1.step via the target gNB (P1), observing from h1.step + 16; it pre-registers m1, the post-handover membership trigger. The classifier (first match wins): invalid → Failure Protocol; stage A with zero handover decisions → substitution 4; a handover exists but n1/h1/m1 cannot be formed by the template (including handovers only in the margin band) → T3; else schedule formed.
- **Margin band** (the TS xApp compares with a float threshold): handover-eligible iff 20·best ≥ 23·serving; none-eligible iff 20·best ≤ 21·serving. Decision mirror: handover iff 10·best_other > 11·serving.
- **Domain (configuration only):** rampGuard 5, tailGuard 10, window 16 → T ∈ [20, 89], every IMSI 1–6.
- **Schedule template:** n1 at step 20 (lowest none-eligible IMSI), h1 at step 30 (lowest handover-eligible IMSI), m1 at h1 + 20 with h1's IMSI; each may slide up to 10 steps.
- **Observation-change control:** a RIC-free replay of the predictor on each live run's certified windows with the DL of gNB nodes 2 and 3 swapped; pre-registered result: h1 → none, n1 → handover.
- **W calibration:** the predictor cannot produce 25 handovers, so the calibration runs R2's fixed-prediction block through the R3′ prepare path (N6 plus a per-trigger PUT of the fixed answer); W = max(1 s, 3 × L_max) as at R2.
- **R3′-specific checks** (`r3p-checks.py`, not `r2-checks.py`): negatives scoped by step, not by IMSI (m1 reuses h1's IMSI); D7 is target-addressed only (contract: R2/R3′ target-addressed, deviation P1). `predictorDrivenApplied` = applied ledger lines whose (imsi, rxSeq) is a scheduled handover trigger and whose target is the argmax key of the predictor's answer.
- **N6 adds value equality:** each certified cell row equals its IPC value; no row past T; the triggered IMSI listed by exactly one gNB in IPC and in Influx; its last applied ledger line targets its current cell and was applied at T−1 or earlier.
- **`--reference`:** `--mode c1` only; `sha256sum -c`, then live1's digests (ledger, ipc, traces, extra) against `equal/`, plus the sha256 of the predictor records, schedule and scenario for R3′; `recorded/` is reported, never judged. The predictor records stay out of `digest-run.py`'s fixed list.
- **T7:** queries only through the in-pod single-quoted `sh -c`; raw CSV parsed and deleted, integer JSON kept; the prepare script never calls `gate_init`; the exact-secret scan runs over the run's predictor dir at the end of each run; fixtures synthetic only.

### Standards ledger rows added 2026-10-28
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| Predictor input: DL Cell PDCP SDU Data Volume, a cumulative counter (CC) of SDU bits entering PDCP per granularity period on NRCellCU, so a sum over 16 consecutive periods is the volume of 1.6 s; unit gap (3GPP Mbit vs E2SM-KPM kbit) and measured object (deviation P9) already recorded at P6; no new deviation | 3GPP TS 28.552 V20.2.0 §5.1.2.1.1.1 (PDF p. 183) | `5SZUBP6M` | 2026-10-28 |
| TS xApp predicted-throughput field: no 3GPP or O-RAN definition; the persistence mapping is a harness policy, not a measurement | — (none exists) | — | 2026-10-28 |

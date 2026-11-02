# P02 (MB, T-B P3): δ actuation seam

**Start state:** `f7-rerun-green` plus i0/i2 installs as the r3p gate needs (as in M9). **Snapshot at exit:** none.

## Context
P3 (run report row: "d = 0: controls apply at the next step") is fixed by a whole-loop actuation delay δ in sim time. Today `Apply` answers every buffered control at the barrier's sim time, and the ledger writes `applySimTimeNs = rxNs` [V `oran-interface/model/e2-control-hub.cc:243-275`, `:285-288`]. The ledger header is `"delta-model":"fixed 0"` [V `:356`]. At stop, buffered controls are answered `late` [V `:380-392`]. Scenario-zero sets the hub attributes from globals [V `ns-3-mmwave-oran/scratch/scenario-zero.cc:420-432`]. AC6 (rc ACK timer) is verified in P01 before this code lands.

## Requirements (contract)
- **AC7:** `ActuationDelay` in sim time, default 0, a model parameter (R-5). The decision is taken at barrier k; the precheck, handover, ledger line and ACK run in one apply event at t_k + δ. At δ = 0 the apply stays synchronous (no zero-delay event), the header stays `"fixed 0"` and no ledger field is added. Each control still pending at stop gets exactly one FAILURE.
- **AC8 (run 1):** after the seam, at δ = 0, R3′ C1 with `--reference plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p` passes on every component including `extra` (`rc-multiset`, `kpm-headers`, `collet-start-time`).

## Design
- `E2ControlHub` gains attribute `ActuationDelay` (TimeValue, default 0). `Apply(seq)`: sort as today; answer `late` controls at the barrier as today. If δ == 0, run the existing loop unchanged. If δ > 0, the tie rule of plan R-5 applies:
  - If δ is a multiple of T (100, 200, 500 ms), the batch is not scheduled as an event. It is queued in `m_dueAtBarrier[k + δ/T]`. `StepBarrier(k + δ/T)` applies due batches after that seq's samples were emitted and before its own batch, so the order never depends on the scheduler's same-timestamp ordering.
  - Otherwise (150 ms), the batch becomes one `Simulator::Schedule(δ, &E2ControlHub::ApplyBatch, …)` event, whose EventId and batch are kept in `m_pendingApply`.
  - `pacer-selftest.py` and a local ns-3 test cover both cases, including a due batch and a new batch at the same barrier.
- `ApplyBatch` runs the precheck and handler per control in the stored order, then calls `Answer` with `rxNs = t_k` and `applyNs = t_k + δ`. `Answer` gets a separate apply-time argument; at δ = 0 both are equal, so the bytes are unchanged.
- Header: `"fixed " + δ in ms` (`"fixed 0"` at δ = 0).
- Stop: `OnEmitterStopping` also cancels every pending apply event, drains `m_dueAtBarrier`, and answers each of its controls once with FAILURE, cause `late` (same cause and path as buffered ones, so R1's late predicate is unchanged).
- The pacer's `applied` line is still sent at the barrier. At δ > 0 its `controls` counts the scheduled controls; the pacer and checks learn the apply time from the ledger (pacing log not digested [V `scripts/gates/digest-run.py` docstring]).
- scenario-zero: a global `actuationDelayMs` (default 0), set through `Config::SetDefault("ns3::E2ControlHub::ActuationDelay", …)` next to `:420-432`. Harness: `rung-config.json` gets `deltaMs` per run; `gate-r3p-ts-predictor.sh` passes `--delta-ms`.

## Files
- ns-3 / oran-interface: `oran-interface/model/e2-control-hub.cc`, `oran-interface/model/e2-control-hub.h`, `ns-3-mmwave-oran/scratch/scenario-zero.cc`.
- Harness: `scripts/gates/rung-config.json`, `scripts/gates/rung-config.py`, `scripts/gates/gate-r3p-ts-predictor.sh`, `scripts/gates/r3p-checks.py` (new check `delta`: on every applied line `applySimTimeNs − rxSimTimeNs == δ` and HandoverStart − applySimTimeNs = c with c = 3.0 ms registered from the M9 reference, plan I-2), `scripts/gates/check-ledger.py` (header form), `scripts/gates/pacer.py` (stop handshake waits for pending applies), `scripts/gates/pacer-selftest.py`.
- Pins: `scripts/pins.conf` (new ns-3 / oran-interface SHAs).

## Steps
1. Implement the seam; unit-level check in a local ns-3 build: δ = 0 ledger and traces byte-equal a free-run and a lock-step run at the M9 pins (`scripts/gates/compare-free-run.py`).
2. δ = 150 and 500 smoke (dev): `applySimTimeNs − rxSimTimeNs = δ`; a control pending at stop gets one FAILURE (forced with a short simTime).
3. Push forks; update `pins.conf`; M5–M7 re-pass at the new pins.
4. AC8 run 1: `gate-r3p-ts-predictor.sh --mode c1 --reference plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p` at δ = 0; archive the evidence.
5. Phase exit.

## Validation
- `verdict.json`: `c1.liveRunsEqual`, `replayEqual`, `rngRun2Differs` true; `equalsReference: true` with the M9 reference path; zero failed checks.
- `head -1 trace/e2-control-ledger.jsonl` equals `{"type":"ledgerHeader","v":1,"delta-model":"fixed 0"}`.
- M5, M6, M7 verdicts pass at the new pins.
- Dev smoke: the pending-at-stop fixture yields exactly one RICcontrolFailure per pending control on the decoded wire.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| Whole-loop delay δ ∈ {100, 150, 200, 500} ms inside the Near-RT loop bracket | E2GAP v08.00 §5.1.1 (10 ms–1 s); OAD v18 (Near-RT RIC control loop) | `AE3NUEDK`, `TBVJDMLF` | to cite |
| Control applied in one event (precheck, handover, answer) | E2AP v03.00 §8.2.4 (RIC Control) | `WEE5IEXF` [C] | to cite |

## Risks
- A zero-delay event at δ = 0 would reorder ties and break AC8 (High/Low with the synchronous rule). Mitigation: δ == 0 takes the unchanged code path, and a byte-compare test runs before any VM run.
- The pacer stop handshake may close before the pending applies fire (Medium/Medium). Mitigation: the stop path answers them FAILURE; pacer self-test case.
- With δ = 500 ms (5 periods) a UE may get a second decision while one is pending (Medium/Medium). The ns-3 precheck at apply time refuses `inHandover`/`alreadyOnTarget` as today; report-only in the δ table.

## Rollback
Re-pin the previous ns-3/oran-interface SHAs; the M9 tag `39b3ba2` reproduces the M9 references.

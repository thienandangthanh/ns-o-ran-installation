# kongming: M10 P02 phase-exit review (δ actuation seam, AC7, AC8 run 1)

Date: 2026-11-03 12:10 KST. Mode: `--advice` phase-exit counsel, read-only, no VM access. Runtime: Opus 5.5 (`model: opus`, per the user's CLAUDE.md override of the `fable` routing). Counsel is not user approval.

## TL;DR

**Verdict: GO-WITH-CHANGES.** Both parts of the P02 exit gate hold in substance.
- **AC8 run 1** is fully evidenced. I independently checked the surfaces the digests do not cover; they are identical to M9.
- **AC7** is evidenced for its core: the δ = 0 path is synchronous and byte-identical, and at δ = 150/500 the controls apply at t_k + δ. The probe also showed one late answer at the stop on the queued path.
- Three items are not evidenced: the R-5 tie-rule self-test, the stop path on the event route (δ = 150), and the wire FAILURE for a control still pending at the stop.

The more important finding is **a certain red in P04**. The check `kpm_ue_lists_move_applied_and_keep_refused` (`tools/e2-evidence/kpm-ue-list-moves.py:109`) judges an applied handover's UE move between samples rxSeq and rxSeq + 1. At any δ > 0 the move happens later, so every δ C1 in P04 would fail on its first live run. Fix it before the δ runs. P03's AC8 run 2 runs at δ = 0 and is not affected.

## Reframed problem

P02 must leave behind two things:
1. a δ seam that is *the* behaviour: a model parameter, synchronous at 0, one apply event at t_k + δ, one FAILURE per control still pending at the stop;
2. proof that the seam did not move a single M9 byte at δ = 0.

The questions are whether the evidence proves both, and whether anything already in the harness will break the four δ C1s in P04. Non-goals: P03 (KPM period), and T-A content.

## Q1. Does P02 meet its exit gate?

### AC8 run 1: met

- Verdict `evidence/r3p/20261103T024628Z/verdict.json`:
  - harness `73bbda6`, pins ns-3 `48d41a5` and oran-interface `b2342c6` (Testbed still `c6d1434`, the M9 value);
  - `pass` true, 168 checks, 0 failed;
  - `c1` = {liveRunsEqual, replayEqual, rngRun2Differs} all true;
  - `equalsReference` true against `plans/261023-0009-…/reference/r3p`, with no `--components` argument, so the default set including `extra` was compared; `differingComponents` [].
- The ledger header is literally `{"type":"ledgerHeader","v":1,"delta-model":"fixed 0"}` (`runs/live1/trace/e2-control-ledger.jsonl:1`). The ledger digest hashes the whole file, header included (`scripts/gates/digest-run.py`, `digests()`), so the header is inside the equality.
- **The build carries the seam (verified).** The live1 `hello` lines name `emitter.ns3Sha` 48d41a5… and `oranInterfaceSha` b2342c6…. The binary sha256 `4c63e522…` is the same in m5, m7 and r3p. M4 rebuilt at the pins (`m4_build_ns3_exit0`, 183 s). This matters because δ = 0 equality cannot tell the seam from a stale M9 build: both pass.
- M4–M7 pass at harness 73bbda6 and the new pins (verdicts `m4/20261103T015440Z`, `m5/…021740Z`, `m6/…021915Z`, `m7/…022052Z`).
- `recordedDiffers: ["xapp-image-ids.json"]`: the `stubqp` image ID differs from M9 (`ff076b…` → `7d67e1…`) under the same tag `stubqp:07c6dc93df2f`. The trafficxapp ID is unchanged. This is report-only by design; note it in the exit record.

### AC7: core met, three gaps

| AC7 clause | Evidence | Status |
|---|---|---|
| `ActuationDelay` in sim time, default 0, a model parameter | `oran-interface/model/e2-control-hub.cc` GetTypeId (TimeValue `Seconds(0)`); `scenario-zero.cc` `actuationDelayMs` → `Config::SetDefault` (48d41a5) | ✓ code |
| δ = 0 is synchronous: no zero-delay event, header `fixed 0`, no new field | `:268` `synchronous`; `Defer` (`:313`, which is the only `Schedule`, `:327`) is reachable only with δ > 0; `ApplyDue` (`:260`) is a map lookup on an empty map; AC8 run 1 | ✓ code + run |
| Decided at barrier k; precheck, handover, ledger line and ACK in one apply at t_k + δ | `ApplyOne` (`:303`) does handler, Answer and controlAck together; smoke d150/d500 `apply − rx` = 150/500 ms; ACK `applySimTimeNs` = ledger (`acks_match`) | ✓ smoke |
| One FAILURE per control still pending at the stop | Queued path (δ = 500): smoke `d500stop`, one late ledger line (rx = barrier 97, apply = 10 s) and one ack. Event path (δ = 150, `Simulator::Cancel` at `:479`): **never run**. Wire FAILURE: **not observed**. The smoke had no RIC, and the phase Validation asks for it "on the decoded wire" | partial |
| R-5 tie rule: "a self-test covers both cases", including a due batch and a new batch at the same barrier | `pacer.py` and `pacer-selftest.py` are unchanged since P01, and no ns-3 unit test exists. The smoke covers one batch per path, never a collision | **not done** (a pre-registration item) |

**Smoke provenance (verified by me).** The smoke ran at harness `fee75dc`, before the pin commit, on an uncommitted dev tree: its verdict pins say ba95…/96ef…. I compared its `build-diff.txt` with `git diff ba954440 48d41a50` + `git diff 96efc40 b2342c6`. They are identical, context lines included (index lines excluded). The smoke binary sha `4c63e522…` also equals the exit-chain binary. So the smoke tested exactly the pinned code. Record this; nothing in the verdict layer says it today.

**Smoke verdict layer reads FAIL.** In the committed `verdict.json`, `pass` is false: `dseam_same_outcomes_at_every_delta` failed (at d500, IMSI 6 hits `lteFallback`, not `alreadyOnTarget`). 73bbda6 then made that check informational without re-running. The relaxation is sound: δ moves the apply into a different radio state, and the smoke uses the default −5 dB outage threshold. But the resume card's "dev smoke green" is not what the evidence says. Required change 2 re-runs the smoke and fixes this as a side effect.

**I-2 holds at δ > 0 (verified now on raw smoke traces).** `check-actuation-delay.py` on smoke d0/d150/d500 gives offsets [3.0] each and passes. HandoverEnd is at apply + 4.72 ms in all three. So at δ = 150, the next sample (+50 ms) has a wide margin.

**Plan Step 1 was substituted, not done.** Step 1 was a local byte-compare at the M9 pins with `compare-free-run.py`. Coverage came instead from r3p `c8` (lock-step null control = free run at the new pins) plus AC8 run 1. That is acceptable. Record it as a substitution.

## Q2. δ = 0 byte identity beyond the reference compare

**No residual risk found.** By construction:
- at δ = 0 no event is added (the `Defer`/`Schedule` path is unreachable), so the event UIDs and same-timestamp ordering are unchanged;
- `ApplyOne` stamps `Simulator::Now()`, which equals the barrier's `now` inside the same event;
- the header is `"fixed " + to_string(0)`;
- no `RandomVariableStream` was added, so there is no auto-stream shift (the D5 landmine);
- the GlobalValue and the attribute do not touch the RNG.

I diffed the surfaces the digests skip, live1 of this run against the M9 reference run `…/evidence/r3p/20261028T044557Z/runs/live1`:
- the IPC trace's non-sample lines (controlAck, everything except hello/bye) are **identical** on all three nodes;
- the `bye` lines are identical;
- the `hello` lines differ only in `runId` and the emitter SHAs, as expected;
- the pacer rx lines (`ready`/`applied`/`controlRx`/`stopping`/`end`) are **identical**;
- `e2-pacing-log.jsonl` without its wall-time fields is equal as a multiset. Line order differs between M9's live1 and this run, but the cause is wall-time arrival order across nodes within a step, so it is not seam-caused.

Minor, not a δ = 0 risk:
- `RegisterEmitter` now aborts on mixed `periodNs` (`:135`) and on non-whole-ms δ (`:137`). This is fine for every planned config, P09 included.
- `ApplyDue` uses an exact-key `find`. If a seq is ever skipped (free pacing, an emitter drop), a due batch would wait until the stop and be answered late. That is harmless today; see optional O1.

## Q3. Carry into P04 (δ C1 at 100/150/200/500)

### Certain red: fix before the δ runs (required change 1)

`kpm-ue-list-moves.py:109` builds `need = [(s, k), (t, k), (s, k + 1), (t, k + 1)]` with k = `rxSeq` (`ts-rung-lib.sh:124`, every live run).
- At δ = n·T the batch applies at barrier k + n, after sample k + n has been emitted (`Apply` → `ApplyDue`, `:257-260`).
- At δ = 150 it applies between samples k + 1 and k + 2.
- So the UE is still in the source list at k + 1, the check reports "did not move" at every δ > 0, and the aggregate `r3p_runs_kpm_moved_c2_c5_reset_fresh` fails with it.

Fix:
- Judge at k_a = rxSeq + (applySimTimeNs − rxSimTimeNs) // period. The tool already takes `--period-ms`. At δ = 0, k_a = rxSeq, so the predicate is identical.
- Refused-at-apply lines are judged at k_a. Late lines keep rxSeq.
- Add self-test cases: δ = 100, where the move at (k+1, k+2) passes and the move at (k, k+1) fails; and δ = 150, where (k+1, k+2) passes.
- Add a check-diff ledger row ("δ = 0 identical; δ > 0 judged at the apply barrier; not weaker").

### Predicates that should hold per δ run (my read of the code and schedule)

- **Seam checks:**
  - `c2`/`rng2_c2` with `--delta-ms` give header `fixed δ` and apply − rx = δ;
  - `check-actuation-delay.py` gives HandoverStart = apply + 3.0 ms and ≥ 1 applied line;
  - c9 already windows on `applySimTimeNs` (`check-c9-handover-trace.py:49-53`).
- **R3′ schedule:**
  - The pre-trigger windows are identical at every δ: the sim is the same until the first apply. So the n1 (step 20) and h1 (step 30) decisions and the observation-change cases are δ-invariant.
  - h1 applies at step 30 + δ/T, at most 35. `expect` requires `applied` and `late == 0`. With `--outageThreshold=-1000` and NoAuto, IMSI 1 stays on cell 3 until then, so this is low risk. The smoke's d500 `lteFallback` came from the default −5 dB config, not R3′'s.
  - m1 (step 50, window [35, 50]): the `membership` check needs IMSI 1 on cell 2 at T = 50, which holds for apply ≤ 49, i.e. δ ≤ 1.9 s. The decision "none" has a ~5:1 margin at δ = 0 (167424 vs 33488), so it is robust.
  - The N6 `h` rule (`check-n6-influx-window.py:138`) uses `rxSeq <= T-1`. At δ > 0 the real rule is k_a ≤ T − 1. The u1 serving check makes it redundant for R3′, so this is a note only.
- **C1:**
  - `liveRunsEqual` at δ = 150 is the real determinism test of the event path. One `Schedule` at t_k + 150.8 ms, insertion-ordered, should be deterministic. If it ever isn't, that is a seam defect, not noise.
  - Replay injects the live1 line at rxSeq; ns-3 defers it again, so replay should equal live.
  - The CLI carries `--actuationDelayMs` into replay, rng2 and c8 (`gate-r3p-ts-predictor.sh:82`, `paced-lib.sh:25`).
- **Tie rule (R-5) coverage in P04:** δ = 100/200/500 use the queued path with one batch, and δ = 150 uses the event path. No collision and no stop case occurs. Required change 2 covers both in dev.
- **Pending-at-stop late path at δ = 500:** not exercised by R3′. The last apply is at step 35, far from 99, and `expect` would go red on any late line. The AC7 stop evidence therefore stays with the smoke; cite it at Stop A.
- **Latent replay defect (should fix):** `pacer.py:73` sends a ledger line with `cause == late and afterSeq >= rxSeq` at the stop handshake. A δ > 0 pending-at-stop line matches that test (afterSeq = rxSeq = k). The replay then writes rxSeq = last barrier and rxSimTimeNs = stop instead of barrier k, so replayEqual fails. I reproduced the classification on the smoke `d500stop` ledger. R3′ never produces such a line, so P04 is safe.
  - Fix: a late line with `applySimTimeNs > rxSimTimeNs` is injected at its rxSeq. Add a selftest case.
- **Budget per δ C1:** about 1,370 s wall (P02's r3p), the same at any δ because the sim work is unchanged. Raw evidence is about 170 MB on the host. The four runs come to about 92 min plus `make`.
  - Host /home is 90 GiB free now (the resume card said 96), and /mnt/data has 20 GiB.
  - Record `df -BG /home /mnt/data` after each δ run, because overlay growth per run is unmeasured.

### Further carries (not P04)

- **P12 / M10 runner:** R-1's d100/d200/d500 are "one live run each, checked against their cp3 sim-side references". The gate refuses `--reference` outside `--mode c1` (`gate-r3p-ts-predictor.sh:51`). The single-run reference path must be added (or the step definition changed, which is T3) before the P12 runner. The kpm-moves fix above is also needed there.
- **P07 (owns the hub next):** R-4 resolves UE IDs before the batch sort, at the barrier. At δ > 0 the "current SN" validation must run again inside `ApplyOne` (apply time). A resolve-time-only check brings back the D5 stale-precheck landmine (same-cell handover into the X2 assert). Add one δ = 500 dev case in P07.

## Required changes (numbered)

1. **δ-aware KPM move judge** (before any P04 δ run): `kpm-ue-list-moves.py` judged at k_a as above; self-test cases; a check-diff ledger row.
2. **R-5 / AC7 dev coverage, re-run at the pins** (before the P04 δ runs; about 5 min VM). Extend `scripts/probes/probe-delta-seam-smoke.sh` with:
   - (a) δ = 100: injections at consecutive steps (20 and 21, different IMSIs) plus a forced-late control at 21, then assert:
     - the due batch's lines (rxSeq 20, apply t_21) are written before step 21's late line;
     - 21's own batch applies at t_22;
     - check-ledger order passes;
   - (b) δ = 150 with an injection at step 99: the event is cancelled at the stop, and exactly one late line is written, with rx = t_99, apply = stop, and one ack.

   Keep the outcome table informational. A green verdict under the committed script replaces the FAIL verdict layer.
3. **Records at exit:**
   - Smoke provenance: diff identical to the pinned commits, binary sha identical, hello emitter SHAs.
   - The smoke FAIL and the assertion relaxed after observation, with the reason.
   - Step 1 substituted by c8 + AC8.
   - AC7 wire FAILURE inferred from the shared path: an ns-3 `refused/late` controlAck goes to the agent and becomes a RIC CONTROL FAILURE (M9 r0 k9, `gate-r0-rc-scripted.sh:21`). Ordering: `OnEmitterStopping` (`e2-ipc-emitter.cc:188`) runs before the `bye` (`:197`).
   - `rung-config.json` `deltaMs` dropped in favour of `--delta-ms` + verdict fact + ledger header.
   - Standards ledger rows: E2GAP v08.00 §5.1.1, E2AP v03.00 §8.2.4. Cite or mark "unverified against Zotero". Confirm the key: memory has the E2GAP text cached under `WVKTACCS`, while the plan says `AE3NUEDK`.
   - Resume-card pins line (still the M9 values) and the P02 status row.
   - `df` and the T′ projection.

## Should / optional

- **S1** (before P11 at the latest): the `pacer.py` replay fix for pending-at-stop lines, plus a selftest.
- **S2:** a stale-build guard in `rung_live`. The `hello` `emitter.ns3Sha`/`oranInterfaceSha` must equal `pins.conf` (only `gate-n4-ul-metric.sh` checks this today). It is an added check and needs a ledger row. It is the only cheap discriminator at δ = 0.
- **S3:** the single-run `--reference` path for the M10 δ-identity steps (P12).
- **O1:** `ApplyDue` applies every due key ≤ seq (stranding robustness; no δ = 0 effect).
- **O2:** at δ > 0, also record `extra` and assert it equals the cp1 δ = 0 `extra`. rc-multiset step = rxSeq and the KPM headers are δ-independent, so this strengthens the δ refs for free.

## What to avoid

- Do not start the P04 δ sweep before change 1. Burning the Failure Protocol's single fix on a known harness coupling wastes the PAUSE-T6 budget.
- Do not read a red `kpm_ue_lists_move` at δ > 0 as a seam bug, and do not "fix" the seam to apply earlier.
- Do not add `--components` or relax `expect`'s `late == 0` for δ runs. The R3′ late = 0 rule is the guard that keeps the replay defect latent.
- Do not cite the smoke's `verdict.json` as green as it stands.

## Assumptions

- The hello `emitter` SHAs are compile-time values from the built oran-interface library (high). If they are only read from git at runtime, S2 becomes more important.
- R3′'s h1 stays `applied` at δ = 500 (high: NoAuto, outage switch disabled, IMSI 1 on cell 3).
- ns-3 single-thread event insertion order keeps δ = 150 deterministic across live runs (medium-high). P04's `liveRunsEqual` decides.
- The agent's existing late → FAILURE mapping is unchanged at the P03 Testbed pin `4b4a61a` (medium-high; P03 touched the agent, not `rc-control.cpp`'s answer path). This was not re-verified line by line.

## Verification I ran

- Diff of the smoke's `build-diff.txt` against the pinned fork diffs: FULL-IDENTICAL.
- Binary sha across the smoke, m5, m7 and r3p: equal.
- `check-actuation-delay.py` on smoke d0/d150/d500: [3.0] each. `--self-test` ok.
- Non-digested surfaces of P02 live1 against M9 live1: identical, as listed in Q2.
- `pacer.load_schedule(--replay d500stop ledger)`: puts the pending line in `late`.

## Unresolved questions

1. R-1's d100/d200/d500 "one live run each against a sim-side reference": should the gate gain a `--mode single --reference` path, or do these steps run as C1? The latter changes the wall budget and is a step-definition change, so the user would rule at Stop A.
2. Zotero key for E2GAP v08.00: `AE3NUEDK` (plan) or `WVKTACCS` (D5 counsel cache)? It may be item key vs attachment key; confirm when filling the standards ledger.

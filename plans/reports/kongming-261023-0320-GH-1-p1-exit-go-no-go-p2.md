# P1 exit go/no-go on P2: M8–M9 plan 261023-0009 (kongming, 2026-10-23 ~03:30 KST)

Runtime: Claude Code, model opus (per user CLAUDE.md). This is advisory only and never counts as user approval.

Verified state:
- Harness `ea057af` is pushed (HEAD == upstream).
- The `dev/l-release-nist180` heads equal `pins.conf` (`git ls-remote`): ns-3 `d3bc4d96`, oran-interface `2817f7e4`, Testbed `0fd195ed`.
- The `wip/p2-pacing` heads are `c4646328`, `fcd43ce` and `8bdd248`.
- VM `running`, snapshot-current `f7-rerun-green`. Host `/home` 68 G free, load average 1.33 at 03:25.
- Code was read at the wip SHAs: `fcd43ce` `model/e2-control-hub.cc`, `e2-pacer-link.cc`, `e2-ipc-tcp-client.cc` and `e2-ipc-emitter.cc`; `8bdd248` `ns3_e2_agent/src/main.cpp` and `tests/rc-control-test.cpp`; `c4646328` scenario-zero and mmwave-helper.

## TL;DR
**GO-with-must-do.** P1 meets its exit gate, with one exception: the binding K5 "unit test holds the precheck order" was never delivered. Close it inside S1.

Gate S1 checks V1–V4 and K19 in substance, but has four problems:
- It omits verdict fields that the phase file names (V1 `nullControlDigestEqualsFreeRun`, V3 `abortStep`, K10's facts).
- Both fault runs withhold step K on **every** node, so they cannot tell an all-of barrier from an any-of one.
- The hub refuses a control as `late` only at the stop. A control that misses its barrier mid-run gets **applied** at the next barrier, against D2(a), C3 and P3's K9.
- The pacer runs a trigger at `ready k`, before the agents have read sample k. This is a determinism race that the S1 gate cannot show; in P3 it would appear as a random red C1.

Fix all of this in the commits you are about to re-make anyway, before the S1 gate runs, so the pins move once. No T-trigger is present. Your CPU-hold reading is correct, with the caveats in §5.

## 1. P1 exit and In scope 1 (scope-guard diff)

| In scope 1 item | Evidence | Verdict |
|---|---|---|
| D4 additive method, prechecks, cancels TTT, performs the handover, returns the outcome | `786527b3` `ApplyExternalHandover`, K5 order, LTE-fallback rule as advised at P0. Live causes in S0's `runs/ctl` ledger: applied, alreadyOnTarget, lteFallback, unknownImsi, unknownTarget, late | ok |
| **K5: "A unit test holds this order"** (binding P1 amendment) | No ns-3 test exists. `inHandover` never occurs in S0. The case that tells the two orders apart (a UE mid-handover, with target = its current secondary cell → `inHandover`; the reversed order gives `alreadyOnTarget`) is not exercised anywhere. S1's fb1 pair (`imsi 6 → 3` twice) gives `inHandover` under either order, because `m_lastMmWaveCell` is 2 ≠ 3 | **gap**, close in S1 (must-do 5) |
| Ledger + C4 sort | S0 V3: 9 lines, header `fixed 0`, `apply − rx = 0`, sorted, acks 9 | ok |
| Agent RC path, causes, bye/EOF, Format 1, IMSI | S0 V2 (13 PASS lines incl. the six named), K23 decode `0000` | ok |
| N5 request part | S0 V4: `0000000202`, `0000000303`, eNB `72657170617274` | ok (the verdict entry carries the wrong name, see §6 should-do 9) |
| Free-run digest unchanged after D4 | S0 V1: ref2, a and new all equal ref1, with the C1 trace rule fixed beforehand | ok |
| M5–M7 re-pass | `m5/20261022T174330Z`, `m6/…174436Z`, `m7/…174612Z`: pass, harness `5ce2a07`, pins d3bc4d96/2817f7e4/0fd195ed, image `ns3-e2-agent:0fd195ed393a`, ns-3 provenance at the pins | ok |
| Phase-exit items 2–7 | Resume card 03:16, notes, pushes, disk 68 G / −13 GB projection (Stop B route), no stray process, ledger rows dated | ok |

Nothing here should stop P2. K5 is a P1 deliverable that was marked done while still undelivered. Record it in `implementation-notes.html` as "closed in S1 by a deterministic scripted case; integration-level, not an ns-3 unit test". The user can rule on that wording at Stop A.

## 2. Gate S1 against P2 V1–V5 and K9, K10, K11, K19

| Item | What `gate-s1-pacer-lockstep.sh` does | Weaker than written? |
|---|---|---|
| V1 | free vs null with `digest-run.py` on ledger, IPC and traces (`:139-147`) | **Yes.** `verdict.json` holds only `checks[]` (`lib.sh:123-129`); the field `nullControlDigestEqualsFreeRun` does not exist. Also `s1_null_run_paced_every_step` accepts `readyCount > 90` (`:155`): the name claims "every step", but the check would pass with up to 10 barriers skipped or merged |
| V2 | `check-ledger.py --expect 8` plus replay digest (`:178-208`) | Partly. Three checks are tautological here: the per-seq count compares ns-3's ledger with ns-3's own `applied` message; `rxSeq == afterSeq` is preset by the schedule; and no expected outcome or cause per control is asserted, so a precheck regression passes. C2's "#terminal answers" is not counted: pacer acks are never matched 1:1 against ledger lines |
| V3 | two fault runs, `v3_fault` (`:215-253, 287-288`) | **Yes, on three counts.** `abortStep` sits only in per-run `v3-fault-check.json`. Both runs withhold on all nodes (`ipc-null-sink.py:193-195`; `--env` reaches every container, `run_ns3_e2_agents.sh:30,85`). The bound is timed from the pacer receiving `ready`, which is sent after up to 2 s × nodes of `FlushOutbound` (`hub.cc:434-452`), not from "barrier block". Non-vacuity of "no ledger line after k" is never asserted (faultagent has no controls at all) |
| V4 (K9) | ledger `cause=late` + ack `refused/late` + agent unit test `late-refusal-control-failed-to-execute` in the image at `TESTBED_SHA` | ok. Reading K9's "outcome late" as outcome `refused` + cause `late` matches the IPC schema. But only the after-final-barrier case exists; see §3 R2 |
| V5 | planned separately after S1 | ok |
| K10 | `k10-facts.json` (`:306-332`) | **Yes.** K10 says "verdicts carry" these facts; they are not in `verdict.json`. T_ctl/W = null with a reason is honest for S1 |
| K11 | `digest-run.py` has an `extra/` hook; live components come "from the rung gates" | Deferred, with a trap: `extra` is excluded from the default components and from `overall` (`digest-run.py:63,70`). Two runs that both lack `extra/` compare as `{} == {}` → equal. Needs a guard now |
| K19 (V6) | p1 vs free0 with `compare-free-run.py`, provenance of both builds | ok |

**Is per-run `v3-fault-check.json` enough for V3's "verdict.json field abortStep = k"?** No. The phase names `verdict.json`, which is the artifact the M9 runner, the run report and reviewers read. Leaving the field out narrows a Verify as written. The fix is a few lines (must-do 4).

## 3. Barrier/abort risks a gate run would not reveal (most serious first)

- **R1, high (determinism): a trigger can race the agent's read of sample k.**
  - What happens: the pacer runs a trigger the moment it receives `ready k` (`pacer.py:138-151`). `ready` only means ns-3 wrote sample k into the socket (`hub.cc:434-452`). The agent stamps `afterSeq = stats().lastSeq` when the RIC control arrives (`main.cpp:179`). Within one poll iteration it handles SCTP before IPC (`main.cpp:208` before `:213`).
  - The race: if the RIC control reaches the agent before the agent has read sample k, the control carries `afterSeq = k−1` and lands at barrier k. C2's `rxSeq == afterSeq` then fails, and the ledger bytes differ between live runs.
  - Likelihood: rare, because the gRPC → RICcontrolRequest path takes at least 5.6 ms (journal §5). It becomes likelier under host CPU contention, and it applies to every rung (R0–R3 triggers are all harness-injected). It would show up as a non-reproducible red C1, the costliest failure mode in this plan (root cause → commit → full fresh set, T6 path).
  - Fix: the hub sends `{"type":"steps","seq":k}` to the pacer the first time every node's step k is in (`hub.cc:494-497`, where `stepsWaitS` is set). The pacer starts a trigger only after `steps k`; T_gate still covers that wait on the ns-3 side. This also gives L a clean start point for the P3 calibration.
- **R2, high (contract): the hub refuses `late` only at the stop.**
  - Code: `OnInboundLine` answers `late` only when `m_stopping` (`hub.cc:183-187`). `Apply` applies everything buffered (`:243-259`).
  - Effect: a control that misses barrier k (read after `go k`, `afterSeq = k`) is applied at k+1. It gets an ACK and changes sim state. C2 turns red, but D2(a) ("any control that arrives later gets RICcontrolFailure"), C3 ("every late control gets a RICcontrolFailure") and P3's K9 ("a control that reaches ns-3 after its barrier … cause=late, **no handover row**") are all violated.
  - Fix: under lockstep only, a control with `afterSeq < seq` at `Apply(seq)` is answered `refused/late` and the handler is not called. Free mode stays as P1 (S0's controls legitimately apply at `afterSeq + 1`).
  - This rule is only safe once R1 is fixed; otherwise the race would refuse a legitimate control.
  - Replay: `load_schedule` sends every `late` line at the stop (`pacer.py:53-54`). Gated runs must have late = 0 (C7), so test the mid-run case in a separate scripted run rather than inside fb1/replay.
- **R3, medium: EOF counts as done (`hub.cc:486-489`, D1 "or hit EOF"), and the client can reconnect inside the barrier.**
  - `DeliverInbound → Service()` also calls `StartConnect` (`tcp-client.cc:50-66`). A node that dropped can therefore flip from "done" back to "missing" in the middle of a barrier, which leads to a misleading T_gate abort.
  - A drop after the last sample loses no samples, so `ipcDropped` stays 0 and the run passes silently.
  - Keep D1, but once a node hits EOF after the start barrier, log `{"type":"departed",...}` in `e2-pacing-log.jsonl` and never count it as missing again. K10 then fails on any departure before the stop.
- **R4, medium (P4 readiness): the stop handshake polls only the pacer fd (`hub.cc:383-402`).**
  - Agent-path late controls are read only if a later emitter's `Stop → DeliverInbound` happens to run after they arrive. If the control's own emitter has already gone, the ack is dropped (`:324-328`) and the agent's bye FAILURE answers it instead.
  - Exactly one wire answer still holds, but whether a ledger line exists depends on wall timing. P4 fault run (ii) needs `DrainAll()` in the stop loop, plus a notice to the pacer so it can hold `endAck` until the expected late control has been read.
- **R5, low.** `subprocess.run(..., timeout=T_ctl)` raises `TimeoutExpired` uncaught (`pacer.py:151`): the pacer dies without writing `pacer-summary.json`, ns-3 aborts with "pacer link lost", and the checks then crash on the missing file.
- **No deadlock found in barrier poll vs agent sockets.**
  - Every 20 ms tick runs `DrainAll → DeliverInbound → Service()`, which pumps inbound and outbound (`SendPending`). An incomplete 2 s flush therefore cannot strand sample k.
  - The pacer link uses blocking send, but the line volume is tiny.
  - Pacer-injected controls precede `go` on the same stream, so they are buffered before the barrier breaks.
  - `m_stepSeq` uses `max`, so stale steps cannot release a barrier.

## 4. Fault run with all three agents withholding K
**Not adequate as the only real-agent evidence.** The contract says "an agent withholds step{k}".
- With every node withholding, a barrier that wrongly releases on *any* node's step still aborts, so both fault runs pass for a correct and a broken barrier alike.
- The code is all-of (`hub.cc:484-506`), but gates must prove it, not code reading.
- Make each fault run withhold on exactly one node:
  - null sink: `--withhold-node N`;
  - agent: a test-only node filter (e.g. `E2_TEST_WITHHOLD_NODE`, compared with `cfg.nodeId`). This is cheaper than per-node env in `run_ns3_e2_agents.sh`.
- Assert that the abort reason names exactly that node (`"no step 30 from node(s) 3"`) and that `e2-pacing-log.jsonl` holds step K from the other nodes.

## 5. T-triggers and the CPU hold
- **T1–T8: none present.**
  - T2: 68 G free, and P2 takes no snapshot. Run `host-disk-watchdog.sh --once` before the long gate.
  - T3: every gap above can be fixed within scope and changes no outcome.
  - T4: function-3-not-announced is the known Stop A question, not a new deviation.
  - T6: no Verify failed.
  - T8: no refusal.
- **CPU hold: your reading is right.** T_start 120 s and T_gate 10 s are contract start values that P2 does not re-set. T_gate + 5 s is a fixed acceptance bound, and `minSlack` is recorded, not used as a gate value. Caveats:
  - (a) Label S1's slack "recorded under the user's CPU hold" and never reuse it, or any S1 wall time, for T_ctl (P3) or W (P5/P8).
  - (b) If you add a T_ctl run-out test, use the contract's 30 s, not a tuned value.
  - (c) Record `uptime`/loadavg on host and VM at gate start and end, so a load-induced red can be root-caused rather than re-run.
  - (d) A red V3 under load goes to the Failure Protocol, never to a re-run until green.

## 6. Verdict: GO-with-must-do

### Must-do: complete these before the S1 gate run, in the commits that replace the wip drafts
1. **Standards ledger first.** Through zotero-mcp, fill P2's row "exactly one terminal answer" with E2AP v03.00 §8.2.4 (`WEE5IEXF`) and the read date. Add a row for the mid-run late refusal (E2AP v03.00 §9.2.1 `control-failed-to-execute`; D2(a)). The plan requires this before the code lands.
2. **Hub + pacer protocol (R1 and R2).** One oran-interface commit:
   - lockstep `afterSeq < seq` → `refused/late`, handler not called;
   - `steps{k}` sent to the pacer.

   One harness commit:
   - `pacer.py` runs triggers only after `steps k`;
   - it catches `TimeoutExpired` and aborts with a reason.

   S1 then gains two runs: a separate scripted run where a control misses its barrier mid-run (ledger `late`, ack `refused/late`, the next control for that IMSI shows the old `sourceCell`); and a no-op trigger step (`true`, expect 0) whose `pacer-log.jsonl` shows `steps k` before the trigger.
3. **Fault run (i) on one node** (§4).
   - Both runs withhold on a single node, and the check asserts the named node and the others' step K.
   - For `faultsink`, add non-vacuity: exactly the 3 step-20 ledger lines exist, and no line has `rxSeq ≥ K` (stricter than "after k", consistent with freeze-then-fail).
4. **Verdict fields.** Add a facts merge to `gate_finish` (for example `fact <key> <json>` → `facts.jsonl` → top-level keys). Backward compatible: no file means no keys.
   - S1 `verdict.json` then carries `nullControlDigestEqualsFreeRun`, `abortStep` per fault run, `ipcDropped`, `droppedNoSub` and `minSlack{T_start,T_gate,T_ctl,W}`, with T_ctl/W null plus a reason.
   - Make the null-run check exact: ready seqs = {−1, 0 … N−1}, with N = samples per node from the sink.
5. **K5 + expected outcomes in fb1.**
   - Change step 20's node-2 control to `imsi 6 → targetCellId 2` (its current cell). Expect `inHandover`; the reversed order would give `alreadyOnTarget`.
   - Assert a per-(nodeId, ctlId) expected table for the cases fixed by construction: first of the pair `applied` (precondition), second `inHandover`, imsi 99 `unknownImsi`, targets 1 and 7 `unknownTarget`, ctl 9 `late`.
   - Record that K5 is closed here.
6. **K11 guard.** `digest-run.py` exits non-zero when `extra` is a requested component and any run lacks the three expected `extra/*.json` files. Record a sequence-only deviation (the wire extractor lands in P3, before R0's first C1) in the notes and in `phase-03`.

Then bump `pins.conf`, run S1 with `--p1-ns3 d3bc4d96… --p1-oi 2817f7e4…`, then M5–M7 (V5). R1/R2 change only the lockstep path, so V6 still applies unchanged.

### Should-do (cheap; same commits if convenient)
1. A T_ctl run-out fault run (trigger `true`, expect 1, T_ctl 30 s): exit 5, abort names the step. This is C7 for the pacer-owned deadline.
2. ns-3 writes `blockedToAbortWallS` (steady clock from barrier entry) into `e2-pacing-abort.json`, and V3 checks it ≤ T_gate + 5, which is the literal "barrier block".
3. V2: pacer acks match ledger lines 1:1 by (nodeId, ctlId), with the same outcome and cause (C2 terminal answers).
4. R3 `departed` logging, and K10 fails on any departure before the stop.
5. R4: `DrainAll()` in the stop loop, plus a late-read notice to the pacer (needed by P4 (ii)).
6. `s1_run` asserts the pacer exit code (0 normal, 3 fault); it is captured today but never checked (`:110`).
7. Write the hold annotation and loadavg into the S1 evidence.
8. Hygiene on re-commit: drop `D1`/`D2`/`C4`/"fault run i" labels from the new comments (`hub.cc:36`, `hub.h:53,62,68`, `agent-config.hpp:32`), and keep "P2"/"wip" out of commit messages.
9. `gate-s0-free-control.sh:177` assigns `name` without `local`, which clobbers `check()`'s `name` (`lib.sh:52`). That is why S0's V4 verdict entry is named `gnb_001_001_00000003`; the `.out` file and the detail are correct. Use `local name`, or a collision-proof variable in `check()`.
10. Build the wire extractor for KPM headers, colletStartTime and the per-step RC multiset now, and fixture-test it on `m7.pcap` and the P0 probe fixture. This de-risks P3.

## Assumptions
- **High.** The S0, M5–M7 evidence and pins are what they claim. I verified the verdicts, provenance, image tag and `ls-remote`.
- **High.** "Late" in D2(a)/C3 includes a control that misses its barrier mid-run (P3 K9 says "after its barrier … no handover row"; `check-ledger.py`'s docstring says "arrived after its barrier"). If the user means only "after the final barrier", R2 drops to should-do. That change would need a user ruling, not mine.
- **Medium.** R1's race is rare; the probability is speculation. The fix is cheap and deterministic either way.
- **Medium.** The local dev results (null == free, replay byte-equal, 10.016 s abort) hold on the VM. They come from a loaded host container and are not evidence.

## Unresolved questions (for Stop A)
1. K5: does a deterministic scripted lock-step case satisfy "a unit test holds this order", or does the user want an ns-3 unit test?
2. Confirm that "late" covers the mid-run case (the assumption above). Implementing it is contract-conformant either way.

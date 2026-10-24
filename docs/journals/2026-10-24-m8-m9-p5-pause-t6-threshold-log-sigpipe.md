# M8–M9 paused in P5: gate i2 --part stub red twice (PAUSE T6), 2026-10-24 ~12:35 KST

Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`. Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/i2/20261024T032221Z/` (second red) and `…/i2/20261024T030903Z/` (first red).

## 1. Why this is a pause
The phase-05 Failure Protocol: after one kongming-guided fix, a Verify that fails again is PAUSE T6. Gate i2 `--part stub` failed twice, each time on a harness bug of my own, with different causes:
1. **Run 1** (`20261024T030903Z`): `i2_restart_counts_zero`, because the stub QP crash-looped. It called `rmr.message_summary` on the NULL pointer that RMR 4.9.0 returns when a receive times out with no buffer passed in. kongming (`plans/reports/kongming-261024-1215-GH-1-p5-stub-qp-null-rcv-buffer.md`) confirmed the cause. The fix landed in harness `ba528c6`; the new self-test passes on the fix and fails on the old code.
2. **Run 2** (`20261024T032221Z`): every stub check passed (self-test in the image, stub up 8 s after Ready, restart count 0). `i2_a1_threshold_reaches_ts_xapp` failed, but A1 itself worked: a1mediator was restarted fresh, and its connection to the TS xApp ClusterIP had an empty queue. The TS xApp logged "Setting Threshold for A1-P value: 10%" for this run's instances (log lines 160 and 163).
   - The check is `kc logs "$pod" | grep -q "Setting Threshold…"` (`scripts/gates/ts-lib.sh:398`) under `set -o pipefail` (`lib.sh:14`).
   - `--part stub` does not replace the TS pod, so its log already held the same line from earlier runs, near the start. `grep -q` exits on that early match, `kubectl logs` dies of SIGPIPE (141), and pipefail fails the pipeline. Reproduced on the VM: three tries out of three gave status 141 (PIPESTATUS `141 0`).
   - The same construction also lets a stale line from an earlier run pass the check. So the check is wrong in both directions.

I print T6 rather than fix again because the protocol says so literally, and the previous segment paused the same way (i2 run 2 after the appmgr fix).

## 2. What is done in P5 since the resume at 08:25 KST (all pushed)
- **Substitution 3** (user, 08:25): Testbed `c7628145`. **L finding 4** (a1mediator stale RMR connection): `a1mediator_restart` in i2 and in the r2 reset (kongming-0840), for Stop B.
- **Gate p5:** the probe crashed the TS xApp (glibc double free, exit 139, `evidence/p5/20261024T000354Z`). **Substitution 2** is applied: Testbed `597bdde2`, a do-nothing default RMR handler.
- **Gate i2 --part ts run 5 PASS** (`evidence/i2/20261024T030327Z`), with both patches built in. The **re-probe p5 PASS**: crashed false, restart count 0 → 0, both variants complete (`evidence/p5/20261024T030729Z`). **V1 met.**
- **Stub fix** (`ba528c6`): the receive guard in the stub, the injector and the self-test; the injector receiver is now fatal on any exception; idle self-test cases; a post-Ready stability check in `stub_install`.

## 3. Proposed fix, for the user's release (as corrected by kongming's pause note)
Source: `plans/reports/kongming-261024-1255-GH-1-p5-pause-t6-threshold-log-sigpipe.md`. It is a conditional GO to resume at i2 `--part stub`, then r2 `--mode calibrate`.

1. **`ts_policy_set` (`ts-lib.sh:398`): use an ordering rule, not a count.**
   - My first draft (count rise plus this instance's payload line) would have passed on a stale line. The TS xApp does not flush the threshold line, so the previous run's line became visible together with this run's first payload line.
   - **New rule:** save the log to `$EVIDENCE_DIR/$id-ts-log.txt`, then pass only on a "Setting Threshold for A1-P value: <th>%" line that comes after this call's first `Payload is …"policy_instance_id":"<id>-` line. Stdout keeps its order, and only `policy_callback` prints that payload line.
   - It is strictly stronger than the old check. It normally passes at attempt 2.
   - Add an unjudged fact `a1DeliveredAttempt`.
2. **`ts_ready` (`:155`, `:158`): it fails the check.** `printf '%s\n' "$logs" | grep -q` returned 141 in 2 of 3 tries at 60 KB and 3 of 3 at 70 KB on the VM. The kept TS pod's log grows by about 19 KB/h, so `i2 --part stub` would go red there within hours. Fix: `grep -q … <<<"$logs"`.
3. **`ts_nodeb_list_check` (`:307`):** it returns 141 but does not fail the check; it wastes about 60 s of polling. Fix: `grep -m 1 … < <(kc … logs …)`.
4. **`injector_start` (`:434`):** low risk, fixed the same way for consistency.
5. **Guard (third time this pattern has appeared):**
   - Add a `lint.sh` regex for `| grep -q` and `| grep -m` after a command or a `printf`.
   - Add a fixture test from TS log lines 155–165: the stale line plus `Payload…-1` must not pass; with line 160 added, it must pass; the old construction must return 141 on a fixture of 70 KB or more.
6. **Re-run `gate-i2 --part stub` fresh.** Expect `a1ThresholdAttempt=2` and `a1DeliveredAttempt=1`. Then gate r2 `--mode calibrate`.

No test is weakened. A plain re-run would fail again (the 141 is deterministic), so a fresh green i2 proves the fix. kongming adds: a third harness red in this segment that is not an L-release cause means stop and re-scope, not another patch.

## 4. State at the pause
- **VM:** running at `r0-green`, boot time 2026-10-23 07:56:59 UTC.
- **rc:** at `a2282ee`.
- **TS xApp:** `19e169b` with substitutions 3 and 2 (image `f521d56b…`), registered, threshold 10 set.
- **Stub QP:** `stubqp:07c6dc93df2f` deployed, registered, routes present (30000 only from the TS xApp to the stub; 30002 from the stub to the TS xApp).
- **a1mediator:** fresh. No agent containers.
- **Snapshots:** `fresh-install`, `f7-rerun-green`, `r0-green`.
- **Disk:** host `/home` about 51 G free.
- **Pins:** ns-3 `962fabc7`, oran-interface `63155c49`, Testbed `597bdde2`.

## 5. Resume steps
1. Run the 3 resume checks and the boot-time check.
2. Apply the fix in section 3 (on the user's release).
3. Run i2 `--part stub` fresh.
4. Run gate r2: `--mode calibrate`, commit W and `a1_threshold`, then `--dev` with 2 or more resets, then C1.
5. Stop B list: L findings 2, 3 and 4.

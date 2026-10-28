# Codex pre-ship audit (CX-3, phase-09 Amendment A1)

- Run: `adversarial-review --wait --json --base 47aee0b` with the focus built from `~/.claude/templates/codex/pre-ship-focus.md`; 2026-10-28 14:39–14:5x KST; Codex run 3 of 4 (plan gate 2, this one; spare 1 unused).
- Range: `47aee0b..HEAD` (Codex reviewed HEAD `5dcd9d9`; `.context.summary`: "Reviewing branch migrate-l-release-NIST-1-8-0 against 47aee0b from merge-base 47aee0bed1af1ec2cd8738cb21869546ec70d469."). Forks: no pin changed since 47aee0b (`scripts/pins.conf` unchanged), so no fork diff is in the inventory.
- Verdict: **needs-attention**. Do not ship: healthy runs exit nonzero, cancellation is unbounded, and monitor death can leave stale evidence accepted as healthy.

## Inventory coverage (38 material parent files: `git diff --name-only 47aee0b HEAD` minus plans/ and docs/)

| File | Codex |
|---|---|
| `scripts/gates/check-n6-influx-window.py` | reviewed |
| `scripts/gates/check-pdcp-volume-totals.py` | reviewed |
| `scripts/gates/gate-n4-ul-metric.sh` | reviewed |
| `scripts/gates/gate-r0-rc-scripted.sh` | reviewed |
| `scripts/gates/gate-r1-rc-multi-control.sh` | reviewed |
| `scripts/gates/gate-r2-ts-stub-qp.sh` | reviewed |
| `scripts/gates/gate-r3p-ts-predictor.sh` | reviewed |
| `scripts/gates/lint.sh` | reviewed |
| `scripts/gates/n6-fixtures.py` | reviewed |
| `scripts/gates/pacer-selftest.py` | reviewed |
| `scripts/gates/pacer.py` | reviewed |
| `scripts/gates/r3p-checks-fixtures.py` | reviewed |
| `scripts/gates/r3p-checks.py` | reviewed |
| `scripts/gates/r3p-dry-run-classifier.py` | reviewed |
| `scripts/gates/r3p-dry-run-fixtures.py` | reviewed |
| `scripts/gates/r3p-predictor.py` | reviewed |
| `scripts/gates/r3p-prepare.py` | reviewed |
| `scripts/gates/r3p-scenario.json` | reviewed |
| `scripts/gates/r3p-schedule.json` | reviewed |
| `scripts/gates/r3p-schedules.py` | reviewed |
| `scripts/gates/r3p-stage-a.json` | reviewed |
| `scripts/gates/r3p-substitution4-validate.py` | reviewed |
| `scripts/gates/reference-compare.py` | reviewed |
| `scripts/gates/rung-config.json` | reviewed |
| `scripts/gates/scrub-evidence.sh` | reviewed |
| `scripts/gates/ts-lib.sh` | reviewed |
| `scripts/gates/ts-rung-lib.sh` | reviewed |
| `scripts/m9-budget.json` | reviewed |
| `scripts/m9-budget.py` | reviewed |
| `scripts/m9-verdict.py` | reviewed |
| `scripts/probes/vm-exec-probe.sh` | reviewed |
| `scripts/run-to-m9.sh` | reviewed |
| `scripts/vm/host-disk-watchdog.sh` | reviewed |
| `scripts/vm/m9-heartbeat-monitor.sh` | reviewed |
| `scripts/vm/m9-runner-selftest.sh` | reviewed |
| `scripts/vm/vm-common.sh` | reviewed |
| `scripts/vm/vm-exec.sh` | reviewed |
| `scripts/vm/vm-snapshot.sh` | reviewed |

Every inventory item is marked reviewed by Codex.

## Round 1 triage

| # | Finding (severity, confidence) | Decision | Change and verification |
|---|---|---|---|
| X1 | Missing failure markers force healthy runs to exit 1: `write_verdict` returned the status of a `cp` that always names absent markers; `cp` could also mask a failed judge (`scripts/run-to-m9.sh:103-114`; high, 1.0) | **accept** (reproduced: the extracted old function returns 1 on a healthy fixture) | `d66e3c3`: return the judge's status; copy only markers that exist, a failed copy fails. Fixture (5) in `m9-runner-selftest.sh` (`32b5792`) runs the shipped `write_verdict` text: healthy → 0, watchdog lost → 1; against the old runner the healthy case FAILs. |
| X2 | Cancellation can hang before shutdown or runner termination: unbounded `ssh … systemctl stop` in the monitor's `cancel` and the watchdog's `trip` (`scripts/vm/m9-heartbeat-monitor.sh:34-39`; high, 0.99) | **accept** | `0dfd01c`: `vm_gate_units` (10 s) and `vm_stop_gates` (`CANCEL_TIMEOUT_S`, default 30 s) with `timeout --kill-after` in `vm-common.sh`, used by both stop paths; `virsh shutdown` under `timeout 10`; a `--stop-cmd` fixture runs under the same bound. The budget's stop path is now 3 × 30 + 30 + 10 + 240 = 370 s (h still 4 GiB, trip 29). Fixture (4): a stop command that never returns (`kill $unit; sleep 1000`, bound 2 s) still stops the runner within 9 s. |
| X3 | An early monitor record can certify an unmonitored run: the verdict accepted any `watchdog-alive.json` with checks > 0 and no recency; the runner never supervised the monitor (`scripts/m9-verdict.py:74-77`; high, 0.99) | **accept** | `d66e3c3`: the monitor writes `lastCheckEpoch`; `m9-verdict.py --end-epoch` requires the last check within 2 polling periods of the run's end; the runner runs each foreground step (`vm-exec.sh`, `gate-m0-host.sh`, snapshot create) under `supervised`, which checks both monitor PIDs every 5 s and on an exit writes `monitor-lost.json` (a verdict failure marker), stops the step and the VM gate units (bounded) and fails the step. Fixtures: verdict self-test cases "monitor died after one early check", "record without its last-check time", "runner saw a monitor exit" (all fail as required); runner fixture (6) `supervised` cancels when the watchdog PID is gone (FAILs against the old runner). |

Codex's note: predictor/classifier self-tests and static syntax/JSON checks passed under its read-only run; lint and VM tests were not run by Codex. After the fixes: `lint.sh` ok, `m9-runner-selftest.sh` ok (7 cases), `m9-verdict.py --self-test` ok. None of the three fixes touches an R3′ gate input (K14: `git diff d2e1ab4..HEAD` changes no file the r3p gate reads), so the reference `reference/r3p/` stands.

## Round 2: the fixes, reviewed by the normal reviewer

Codex reviewed the code before the fixes existed, so the fix diff `5dcd9d9..32b5792 -- scripts` went to an independent `code-reviewer` subagent (read-only; ran `bash -n`, both self-tests, and local mocks of the shipped `supervised`/`finish`/trap text). Its conclusion: the three fixes work for their target defects. That covers the verdict status, the bounded remote stops, the end-epoch rule, and a single verdict write in the trip sweep, which it checked by simulation. It found two new gaps:

| # | Finding | Decision | Change and verification |
|---|---|---|---|
| R1 | When the watchdog dies, `supervised` cancels within 5 s and `finish` then kills the heartbeat monitor before it can act. So the VM is never shut down, contrary to phase-09 A1 ("runs the same cancellation and shutdown"). | **accept** | `2d1314e`: `supervised`'s cancel now also runs `vm_shutdown` (path ≈ 5 + 32 + 10 + 240 s, under the 370 s budget). Fixture (6), `2e8f04f`, covers both the watchdog-dead and the monitor-dead branch, asserts that the gate stop and the shutdown both ran, and takes its dead PID from a reaped child. It FAILs on the previous runner (no shutdown). |
| R2 | A TERM to the runner alone orphans the running step, because the step is now a background child and `finish` never signalled it (reproduced). | **accept** | `2d1314e`: `supervised` keeps `step_pid`; `finish` TERMs a live step and stops the VM gate units (bounded) before writing the verdict. The watchdog's comment is updated. Fixture (7) sends a TERM to a runner mid-step and asserts the step is gone and the gate units are stopped. It FAILs on the previous runner (step left alive). |
| R3 | Hardening, low: `ssh` without `-n` on the bounded calls can stall on a tty; `watchdog-alive.json` truncated by `>` can be read empty. | **accept** | `2d1314e`: `ssh -n` in `vm_gate_units`/`vm_stop_gates`; the monitor writes the record to a temp file and renames it. |
| R4 | Low: `virsh domstate` in `wait_state` has no timeout; the stop budget leaves out kill-after and polling overhead (about 372–380 s, not 370). | **reject, no change** | `virsh domstate` is a local libvirt call, not ssh (`vm-common.sh`), and libvirt's keepalive limits it. At the measured 0.0093 GiB/s, h stays 4 GiB up to a 429 s stop path (`m9-budget.py`: h = ceil(rate × path)). |
| R5 | Low: fixture (4) bounds only the `--stop-cmd` path; removing the `timeout` from `vm_stop_gates` would not fail any self-test. | **accept as a known gap** | `vm_stop_gates` and `vm_gate_units` are one-line wrappers whose `timeout` the review read directly. A fixture would need a fake ssh, which is out of scope for P9. |

After the Round 2 fixes: `lint.sh` ok; `m9-runner-selftest.sh` ok (10 cases); `m9-verdict.py --self-test` ok (18 cases). No R3′ gate input changed (K14), so `reference/r3p/` stands.

## Coverage

Every material inventory item is reviewed. Codex reviewed all 38 inventory files. The normal reviewer reviewed the post-audit fix diff (`scripts/run-to-m9.sh`, `scripts/m9-verdict.py`, `scripts/m9-budget.py`, `scripts/m9-budget.json`, `scripts/vm/vm-common.sh`, `scripts/vm/host-disk-watchdog.sh`, `scripts/vm/m9-heartbeat-monitor.sh`, `scripts/vm/m9-runner-selftest.sh`). The Round 2 change (`2d1314e`, `2e8f04f`) applies the reviewer's own recommendations, and its fixtures were back-tested against the previous runner. No finding needs a user ruling (no T9).

Status: complete

# kongming: P10 attempt 3, reaper env var vs `systemd-run --user` launch route

Date: 2026-10-28 ~22:40 KST. Runtime: Claude Code, model opus (Opus 5.5), per the user's CLAUDE.md override (not `fable`). Advisory only.
- Host inspection was read-only: systemctl/loginctl/journalctl reads, /proc, ps, id. No SSH, no virsh, no git writes.
- The Codex report on the same question was deliberately not read.

## TL;DR
- **Recommendation: both, as one hybrid route.**
  - The user starts the attempt-3 Claude Code session with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`.
  - The runner runs as a transient user unit: `systemd-run --user --wait`, launched from the Claude Code background shell, with `KillMode=mixed`.
  - The agent keeps its exit notification. The background command's exit status *is* the runner's exit status (V1).
  - Before launch, the user rules a records-only clarification of step 5 and adds a no-VM route smoke. If the user will not amend step 5, use the env var alone.
- **Q1 (env var): yes.**
  - The reaper cannot relieve this workload's memory pressure. 17 s after the attempt-2 reap, MemAvailable was still 3 GiB; it reached 19 GiB only after `vm_shutdown`. The memory belongs to qemu, which libvirtd owns, outside Claude's process tree.
  - Disabling the reaper removes a kill that only does harm and adds no memory risk. The OOM and thrash risk is the same either way; the reboot plus the 23 GiB gate cover it.
  - Leave `oom_score_adj` alone.
- **Q2 (systemd-run): better, but only with `KillMode=mixed`.**
  - The default `control-group` mode reproduces the reaper's group-wide TERM, and with it the `finish()` orphan gap.
  - `mixed` sends TERM to the runner alone. That is self-test case 7's path: `finish()` stops the step and the VM gate units.
  - The host is suitable: linger is on, systemd-oomd is off, and the environment is effectively the same as the Claude shell.
  - Override two user-manager defaults: `OOMPolicy=stop` and the 90 s stop timeout.
- **Q3:** see the exact command in Q3 below.

## Reframed problem
- **The decision.** How should the M9 runner be hosted for about 4 h, so that nothing outside the test can kill it, without changing any test, pass condition or budget, and while keeping V1 (the exit code) observable to the agent?
- **Two independent levers:**
  - (a) the Claude Code reaper, which can kill background shells;
  - (b) where the runner process lives, which decides its fate on a reap, a Claude/Orca crash or an operator stop, and its TERM semantics.
- **Constraints:**
  - K14 freezes `scripts` and `tools` at F′ `fb3554a`.
  - Phase-10 step 5 says "through the harness's background facility".
  - The reaper notice forbids an agent-initiated restart.
  - Only the user may set the env var or amend step 5. Kongming counsel is never approval.

## Verified evidence (host, read-only, 2026-10-28 ~22:30 KST)
- **The reap freed nothing.**
  - `evidence/m9/20261028T112207Z/reap/host-state.txt`: at 12:41:28Z, 17 s after the reap, the host had 3 GiB available and 13 GiB of swap in use.
  - "Host after: available 19 GiB" came only after `vm_shutdown`.
  - The runner log shows `Terminated sleep 5`, so the TERM went to the whole process group (`runner.log`).
- **The env var is official.** The Claude Code v2.1.193 release notes say: "Added automatic memory-pressure reaping for idle background shell commands (disable with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`)". The docs pages still omit it.
- **Lingering and logind.** `loginctl show-user andang`: `Linger=yes`, `State=active`. The user manager is systemd 262.1-arch. It reports `degraded` only because `redshift.service` failed, which is harmless.
- **No OOM policy anywhere.**
  - systemd-oomd is `inactive` and `disabled`.
  - `user@1000.service`, `user.slice` and `app.slice` all have `ManagedOOMMemoryPressure=auto` and `ManagedOOMSwap=auto`, so no kill policy.
  - There is no Fedora-style oomd drop-in.
  - `user@1000.service` has `MemoryHigh` and `MemoryMax` set to `infinity`.
  - No earlyoom or nohang process runs.
- **User-manager defaults:**
  - `DefaultOOMPolicy=stop`: if the kernel OOM-kills any process in the unit, systemd stops the whole unit.
  - `DefaultTimeoutStopUSec=90s`.
  - `DefaultOOMScoreAdjust=200`.
  - `DefaultStandardOutput=journal`, `DefaultStandardError=inherit`.
- **Claude Code already lives under the same user manager.**
  - The `claude` processes' cgroup is `user@1000.service/orca_ptys_…slice/orca_pty_…scope`.
  - The user manager (pid 1244) and the Claude shell have identical supplementary groups, including `libvirt` (959).
- **Environment differences are cosmetic for the runner.**
  - The manager's `PATH` is `/usr/local/bin:/usr/bin`. `python3`, `virsh`, `ssh`, `git`, `timeout`, `tshark`, `pgrep`, `tar`, `du` and `df` resolve to the same `/usr/bin` binaries under both PATHs.
  - The manager has `DISPLAY=:0`, `HOME`, `LANG` and the `DBUS`/`XDG_RUNTIME_DIR` variables. It lacks `SSH_AUTH_SOCK` and Claude's `GIT_*` variables (`GIT_TERMINAL_PROMPT=0`, `credential.interactive=false`).
  - The ssh-agent holds **no identities**, so the VM and GitHub ssh use the key file. That works in both contexts; BatchMode ssh already works from the background shell.
  - No `VM_*`, `EVIDENCE_*`, `HARNESS_*` or `CANCEL_*` override is set in the Claude shell.
  - `umask` is 0022.
- **The script does not depend on the working directory.** It derives `here` from `$0` (`scripts/run-to-m9.sh:27`), and `vm-common.sh` derives `REPO_ROOT` from `BASH_SOURCE` (`:17`).
- **Stop semantics in the script.**
  - `finish()` (`run-to-m9.sh:120-131`) stops the step and the gates only if `kill -0 $step_pid` succeeds.
  - Self-test case 7 is "a TERM to the runner alone stops the running step" (`scripts/vm/m9-runner-selftest.sh` header).
  - The watchdog and the monitor TERM the runner's children and then the runner (`host-disk-watchdog.sh:53-54`, `m9-heartbeat-monitor.sh:40-41`). That logic does not change when the runner moves into a unit.
- **systemd-run `--wait`** (systemd source `src/run/run.c`, main branch):
  - It installs no signal handler for `--wait` without a pty, and it never calls `StopUnit`. So if the client dies, the unit keeps running.
  - It pins the unit with `AddRef` so it can read the result.
  - It returns `unit_result_to_exit_status()`: `success` gives 0, `exit-code` gives the main process's status, and `signal` gives `EXIT_EXCEPTION`.
  - I checked this against `main`, not against the 262 tag; the code path is long-standing.
- **qemu's PID is not stable during a run.** Each no-snapshot boundary runs `vm_shutdown && vm_start` (`run-to-m9.sh:176-177`), and `gate-m0-host` reverts. So any per-PID `oom_score_adj` setting lapses after m0.
- **Memory today** (not the attempt-3 state): there are 3 `claude` processes (245–448 MB each), `zotero-mcp` (1.15 GB plus 0.16 GB), `codex` (0.32 GB), `warp-svc` (0.40 GB) and Orca (about 1.2 GB across processes). Swap is zram 4 G at priority 100 plus NVMe 32 G, with swappiness 60.

## Q1: should the session start with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`?
**Yes.**
- **Risk removed.** The reaper can no longer kill the runner, or in the hybrid route the notification client.
  - With the reboot and the gate, a genuine pressure reap becomes unlikely.
  - False triggers remain plausible over a 4 h idle wait: the reaper reads PSI, and m1 image pulls and the m4 ns-3 build cause reclaim stalls even with free memory. Third-party reports describe reaps with 26–41 GB available.
  - Each reap costs a full revert and re-run, and a PAUSE.
- **Risk added: effectively none for this workload.**
  - The reaper only kills Claude-tracked shells: a few MB of bash, ssh and sleep.
  - It cannot touch qemu, which holds the memory, so it never relieved pressure. Attempt 2 proved this (3 GiB available after the reap).
  - Kernel OOM and swap thrash are equally likely with or without it.
  - The only real loss is the reaper's side effect as an alarm. Replace that with records (below).
- **Thrash and OOM, handled outside the reaper:**
  - With 35 GiB of swap, the host thrashes long before it OOMs.
  - Thrash slows the guest. Timing-sensitive rungs (r0 and r1 control latency, pacing) could fail on their own merits, which is an honest environmental failure and not a harness one.
  - If a kernel OOM did happen, it would pick qemu: 16.5 GiB RSS at about adj 0 dominates `oom_badness`. The Claude/Orca processes' adj of 0–200 adds at most about 6 GiB-equivalent each.
- **Mitigations that change no test:**
  1. The approved gate: MemAvailable + qemu RSS ≥ 23 GiB after the revert, VM running.
  2. Exactly **one** Claude Code session, no Codex and no second worktree session. Each session brings its own MCP servers.
     - **Optional:** start that session without the Zotero MCP (about 1.3 GiB). P10 makes no new standards decision, so it is not needed during the run. The gate measures it either way.
  3. No browser, Zotero or GUI preview until the run ends. The user owns this.
  4. Records only, never gating: `free -g` and `/proc/pressure/memory` at each step boundary the agent sees in the log, plus `printenv CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` at pre-flight.
- **Do not:**
  - Set qemu `oom_score_adj`. It needs root. It lapses at every boundary and at the m0 revert, because the PID changes; a persistent libvirt hook would be a root host config change. It would only move the OOM victim to Orca or Claude.
  - Change swappiness or zram, or run swapoff (less cushion means an earlier OOM).
  - Add a memory watchdog: that is a frozen-script change.
- **How to set the variable.**
  - Set it in the environment that launches `claude` in the Orca terminal: `env CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 claude`. This works in fish and bash.
  - Avoid relying on `settings.json` `env`. It is not documented whether that is applied before the reaper is armed.
  - Verify from the Bash tool: `printenv CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` → `1`. Record it.

## Q2: `systemd-run --user` instead of a bare Claude background shell?
**Better, as the hybrid**: launch `systemd-run --user --wait …` *through* `run_in_background`.

| Concern | Bare bg shell (step 5 as run) | Hybrid `systemd-run --wait` in bg shell |
|---|---|---|
| Reaper | Kills the runner's group, which orphans the VM unit (attempt 2) | Can kill only the client; the unit keeps running (run.c: no StopUnit). With the env var set, there is no reap at all. |
| Claude Code crash, exit or restart; Orca pty or daemon crash | Fate undocumented (belief: killed or HUP'd; the runner has no HUP trap, so no verdict) | Unaffected: the runner's parent is the user manager, in `app.slice/m9-p.service`. Linger is on, so logout does not stop it either. |
| Context compaction | No effect | No effect; the unit name is a stable handle for any later session |
| Operator stop | TaskStop or KillShell sends a group kill, which leaves the orphan gap | `systemctl --user stop m9-p` with `KillMode=mixed` sends TERM to the runner only; `finish()` then sees `step_pid` alive, TERMs vm-exec, runs `vm_stop_gates` (≤ 32 s) and writes the verdict; systemd then SIGKILLs leftovers (orphaned `sleep`/`ssh`). This is self-test case 7. |
| `KillMode=control-group` (the default) | n/a | The same group TERM as the reaper, so the orphan gap returns. **Never use the default.** |
| oomd and slice policy | n/a | systemd-oomd is off; no ManagedOOM kill policy and no memory limits, so nothing kills it. Only `OOMPolicy=stop` differs: set `continue` so an OOM-killed helper fails one call (as in the bg shell) instead of systemd stopping the whole runner. |
| Stop timeout | n/a | Default 90 s. Worst-case trap latency is one foreground command (up to about 60 s for an ssh ServerAlive stall) plus `vm_stop_gates` (≤ 32 s) plus the verdict, so set `TimeoutStopSec=180`. |
| Environment | Claude shell | Manager env plus `-E PATH -E SSH_AUTH_SOCK -E GIT_TERMINAL_PROMPT` for parity; same uid and groups, so libvirt access via `qemu:///system` and the group is identical, and ssh uses the key file. Keep `$` and `%` out of the argv: systemd expands `${VAR}` and `%` specifiers in the transient ExecStart. The runner line has neither. |
| Log | bg output file | `StandardOutput=append:<abs log>`, `StandardError=inherit`. **Never use `--pipe`**: if the client dies, the runner's next `hlog` write hits a broken pipe, SIGPIPE kills the runner, and no verdict is written. |
| Exit code (V1) | bg notification | The same notification. The client prints `Finished with result: …` / `Main processes terminated with: code=exited, status=N` and exits with N. Status 3 shows as `3/NOTIMPLEMENTED`, which is only systemd's LSB label. |

- **If the client is lost** (reap with the env var unset, or a Claude restart):
  - Do not relaunch anything.
  - Re-attach with a waiter in a new background shell: `while systemctl --user is-active -q m9-p.service; do sleep 60; done; journalctl --user -u m9-p.service -o cat --no-pager | grep -E 'Main process exited|Deactivated successfully|Failed with result'`.
  - V1 is then read from that journal line. The journal is persistent: `/var/log/journal` exists.
  - Omit `--collect`. A failed unit then stays inspectable (`systemctl --user status m9-p`) for a fresh session. Unit names are unique per attempt; run `reset-failed` after recording.
- **Step-5 fit.** By the letter, the hybrid still runs "through the harness's background facility": the launcher and the exit notifier are the Claude Code background shell. But it changes where the runner lives and how it stops, and the reaper notice says not to work around it. So it is legitimate only as an **explicit user ruling**, recorded as a records-only clarification of step 5 and Stop B step 10 (proposed text in the checklist). It weakens no signal. K14 is untouched, since no file under `scripts` or `tools` changes.
- **Coupled landmine.** The pre-registered post-reap operator cleanup (`vm_gate_units` → `vm_stop_gates` → `vm_shutdown`, from the 21:45 counsel) must now first check `systemctl --user is-active m9-p.service`. Under the hybrid, a dead client usually means a **healthy, still-running** runner, and that cleanup would kill it. Likewise, a client reap is not T8: keep waiting.

## Q3: recommendation
**One line: both (env var at session start + hybrid `systemd-run --user --wait` with `KillMode=mixed`, after the user's step-5 clarification and a green route smoke); if the user declines the amendment, env var only.**

Exact launch, run from the worktree root via the Bash tool with `run_in_background: true`:

```
systemd-run --user --wait --unit=m9-p --description='M9 attempt 3 prefix p' --same-dir \
  -E PATH -E SSH_AUTH_SOCK -E GIT_TERMINAL_PROMPT \
  -p KillMode=mixed -p TimeoutStopSec=180 -p OOMPolicy=continue \
  -p StandardOutput=append:/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/runner-p.log \
  -p StandardError=inherit \
  /home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0/scripts/run-to-m9.sh \
  --harness-sha fb3554af67010dfedb6ae500e533acb7cdac9530 --run-prefix p --no-snapshots
```

- Do not add `--collect`, `--pipe`, `--pty`, `--scope` or `-q`.
  - `--scope` keeps the runner in Claude's process tree, which defeats the purpose.
  - `-q` hides the result lines.
- Operator stop: `systemctl --user stop m9-p.service`.
- Live log: `tail -n 20 …/evidence/m9/runner-p.log`. After the exit, move the log to `evidence/m9/<run_ts>/runner.log`.

## What to avoid
- `KillMode=control-group` (the default) or `process`.
  - `control-group` reproduces the orphan gap.
  - `process` leaves the watchdog and monitor running after the runner dies.
- `--pipe` or `--pty` with a detached runner: SIGPIPE kills the runner silently.
- An agent-initiated switch of route without the user's ruling, or a relaunch after any reap or client loss.
- Running the old post-reap cleanup without checking the unit state first.
- Setting `oom_score_adj`, changing swap, or running a memory watchdog.
- Opening a browser on the host during the run.
- A second Claude or Codex session during the run.

## Alternatives and trade-offs
- **Env var only (step 5 as written).**
  - No amendment, and the route is proven twice up to the reap.
  - It still has the Claude/Orca crash exposure (probability low but non-zero over 4 h). An operator stop through TaskStop still orphans the VM unit.
  - **This is the right fallback if the user wants zero amendments.**
- **Detached `systemd-run` without `--wait`, env var unset.**
  - The run is immune to everything above.
  - V1 must come from polling or the journal, and the agent still needs a background waiter to be woken, and that waiter is reapable. Re-attaching after a reap is a judgment call against the notice's wording.
  - Strictly weaker than the hybrid, for no gain.
- **Neither.** Rejected: attempt 2 already shows the loss mode.

## Work checklist (after the user's rulings; records only, no test changes)
1. User: reboot. Start Orca and **one** `env CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 claude` session (optionally without the Zotero MCP).
2. User rules the step-5 / Stop B step 10 clarification. Proposed text:

   > The runner runs as the transient user unit `m9-<prefix>.service`, started by `systemd-run --user --wait` (KillMode=mixed, TimeoutStopSec=180, OOMPolicy=continue, log via StandardOutput=append) through the Claude Code background facility; that command's exit status is V1. A lost client is not a stop: never relaunch; re-attach with the journal waiter; V1 is the journal's main-process status. Operator stop is `systemctl --user stop`. Pre-flight 6 adds: no `m9-*` user unit loaded. The post-reap cleanup runs only when the unit is inactive.

3. Pre-flight: everything already ratified, plus `printenv` of the variable (record).
4. Route smoke, before the revert (no VM needed):
   - (a) run the same `systemd-run` line with `--unit=m9-p-smoke`, the log `…/m9/runner-p-smoke.log`, and the command `scripts/vm/m9-runner-selftest.sh`. Expect exit 0.
   - (b) client-kill check: start `systemd-run --user --wait --unit=m9-p-clientkill sleep 120` in the background, kill the client, and expect `systemctl --user is-active m9-p-clientkill` to report `active`. Then `systemctl --user stop m9-p-clientkill`.
5. After the revert, with the VM running, an access smoke through the same route: `--unit=m9-p-access … /usr/bin/bash -c 'virsh -q -c qemu:///system domstate ubuntu24.04 && ssh -o BatchMode=yes -o ConnectTimeout=8 oran-kvm-2404 true && git ls-remote origin HEAD'`. Expect exit 0.
   - If any smoke is red, launch per step 5 as written (bare background shell, env var on). This is not a PAUSE.
6. Memory gate, then commit the projection row and update the resume card with the unit name, the log path and the re-attach command, so that a fresh session can resume.
7. Launch (Q3). Record the start epoch and the deadline (wall 20199 s).
8. Write a record row at each boundary (`free -g`, PSI).
9. On exit: V1 from the client's exit code, cross-checked against the journal line. V2–V4 from `verdict.json`. Run `systemctl --user reset-failed m9-p` if it failed. Move the log.

## Success metrics
- The smokes are green, the variable is recorded as `1`, and the memory gate is green.
- The client exits 0 with `Finished with result: success`. `verdict.json` is PASS with all 14 steps.
- There is no reap notice. No `gate-*` unit or `m9-*` unit remains afterwards.
- The boundary records show no sustained PSI `full`.

## Assumptions
- **High.** The reaper cannot free qemu memory. Source: attempt-2 host state 17 s after the reap.
- **High.** Environment parity for the runner. Verified: same groups and binaries, file-based ssh key, linger on, oomd off.
- **Medium-high.** Killing the `--wait` client leaves the unit running, and exit codes propagate. Source: run.c and unit-result.c on `main`, not the 262 tag. Smoke 4b verifies it locally; if 4b fails, drop the hybrid and use the env var only.
- **Medium.** The variable is honoured when set in the launch environment. Source: official release note; not documented for `settings.json`.
- **Medium.** Claude Code kills or abandons its background shells on exit. This is a belief and is undocumented. It only matters for the "env var only" alternative.
- **Judgment.** The 23 GiB gate (user-approved) and the 180 s stop timeout (derived from the script's bounded calls).

## Unresolved questions (user)
1. Rule the hybrid route (the step-5 clarification text above), or env var only?
2. Ratify smokes 4–5 as pre-flight items, with "red falls back to step 5 as written"?
3. Still open from before: confirm prefix `p`; timing of the orphan-gap fix (default after M9; under `KillMode=mixed` it no longer matters for operator stops).

## Sources
- [Claude Code v2.1.193 release notes](https://github.com/anthropics/claude-code/releases/tag/v2.1.193)
- [Docs omit memory-pressure reaping (#71459)](https://claudeissues.com/issue/71459-docs-background-shell-docs-omit-memory-pressure-reaping-and-claude-code-disable)
- [Reap kills only the tracked shell (#79727)](https://claudeissues.com/issue/79727-bug-memory-pressure-reap-kills-only-the-tracked-shell-child-process-tree-survive)
- [systemd-run(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html)
- [systemd src/run/run.c](https://github.com/systemd/systemd/blob/main/src/run/run.c)
- [systemd src/shared/unit-result.c](https://github.com/systemd/systemd/blob/main/src/shared/unit-result.c)

Status: DONE_WITH_CONCERNS
Summary: Both, as a hybrid: set the env var, and run `systemd-run --user --wait` with `KillMode=mixed` from the Claude Code background shell. It needs a user-ruled step-5 clarification and a no-VM route smoke; without the amendment, use the env var only.
Concerns: client-death behaviour was checked against systemd `main`, not the 262 tag (smoke 4b closes this). The post-reap cleanup rule must be gated on the unit state.

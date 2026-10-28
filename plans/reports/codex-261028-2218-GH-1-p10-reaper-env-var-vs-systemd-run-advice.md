# Codex advisory: reaper env var vs systemd-run --user (2026-10-28 22:18 KST)

User-requested run (22:15 KST), read-only `task --fresh --effort high`, outside the A1 CX-3 cap of 4 (cap already reached). Brief: the question set given to kongming in `plans/reports/kongming-261028-2215-GH-1-p10-reaper-env-var-vs-systemd-run-advice.md`. Advisory only; not a user ruling.

**Prefer a detached systemd user service with `KillMode=mixed`.** The environment variable is a reasonable fallback if you retain Claude Code’s background facility.

1. **Disabling the reaper**

`CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 claude` prevents Claude’s memory-pressure cancellation; it does not disable Linux OOM handling. The variable is now [officially documented](https://code.claude.com/docs/en/env-vars).

It removes the interruption seen in [host-state.txt:3](plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T112207Z/reap/host-state.txt:3). By allowing work to continue under pressure, it increases exposure to prolonged swap thrashing, desktop unresponsiveness, timeout failures, and kernel OOM kills of qemu, Claude, Orca, or another eligible process. It adds no memory consumption itself.

Keep the approved 23 GiB gate and close heavy applications throughout. That gate implies roughly 6 GiB available when qemu reaches 17 GiB RSS; it guarantees no future headroom. Monitor MemAvailable, swap-in/out and `/proc/pressure/memory`. A sustained 4 GiB available-memory warning floor is reasonable operational judgment; automatic cancellation would introduce another supervisor policy.

Keep swap enabled and avoid untested swappiness changes; current host swappiness is 60. Lower values do not reserve RAM. [Kernel guidance](https://docs.kernel.org/admin-guide/sysctl/vm.html#swappiness).

A privileged, modest negative qemu `oom_score_adj` can reduce its selection likelihood, but shifts risk elsewhere; avoid `-1000` immunity. Setting it on the runner does not protect separately managed qemu. [Kernel documentation](https://docs.kernel.org/filesystems/proc.html).

2. **Why systemd is preferable**

A transient **service**, without `--scope`, `--pipe` or `--pty`, is parented by the user manager. It therefore escapes Claude’s background process group and survives Claude crashes/restarts; context compaction cannot affect its lifetime. Claude’s background facility offers convenient completion notifications but remains runtime-managed. [systemd-run](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html).

On `systemctl --user stop`:

- Default `KillMode=control-group` TERMs runner and children together, recreating the race in [finish():122](scripts/run-to-m9.sh:122).
- `KillMode=mixed` TERMs only the main Bash runner, allowing its trap to stop the step and guest gates before remaining host children receive SIGKILL on main-process exit or timeout. It improves cleanup but cannot eliminate the existing dead-`step_pid` gap. Neither mode directly controls guest units. [Kill semantics](https://www.freedesktop.org/software/systemd/man/latest/systemd.kill.html).

Lingering preserves the user manager after logout. The host already has [/var/lib/systemd/linger/andang](/var/lib/systemd/linger/andang); otherwise `loginctl enable-linger andang` establishes it. Logout may still terminate a session-owned SSH agent. Lingering does not survive shutdown as a running process. [loginctl](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html).

Systemd is not OOM immunity: `systemd-oomd` can SIGKILL eligible descendant cgroups, bypassing traps; ancestor memory limits also apply. After reboot, inspect `oomctl` and effective user-slice policies. `ManagedOOMMemoryPressure=auto` does not override an ancestor’s policy. [OOM policies](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html).

3. **Suggested launch, after preflight**

This replaces [phase-10 step 5’s route](plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/phase-10-m9-unattended-run-from-fresh-install.md:18). Nothing was launched or modified.

```bash
cd /home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0
m9_env=(--setenv="PATH=$PATH")
[[ -z ${SSH_AUTH_SOCK:-} ]] ||
  m9_env+=(--setenv="SSH_AUTH_SOCK=$SSH_AUTH_SOCK")

systemd-run --user --unit=m9-attempt3 --service-type=exec \
  --remain-after-exit --working-directory="$PWD" \
  "${m9_env[@]}" \
  -p KillMode=mixed -p TimeoutStopSec=120s -p Restart=no \
  -p StandardOutput=journal -p StandardError=journal \
  /usr/bin/bash "$PWD/scripts/run-to-m9.sh" \
  --harness-sha fb3554af67010dfedb6ae500e533acb7cdac9530 \
  --run-prefix p --no-snapshots
```

The service receives no interactive shell initialization. PATH and optional agent socket are explicit; HOME comes from the user manager. Libvirt URI is already explicitly `qemu:///system` in [vm-common.sh:22](scripts/vm/vm-common.sh:22).

Omit `--collect` to preserve failure status; `--remain-after-exit` retains successful completion too. Poll:

```bash
systemctl --user show m9-attempt3.service \
  -p ActiveState -p SubState -p Result -p ExecMainCode -p ExecMainStatus
journalctl --user -u m9-attempt3.service --no-pager -n 40
```

Launch success is not test success; check these fields and `verdict.json`. There is no automatic Claude completion notification.

**Recommendation: systemd-run only, with mixed termination, retained status, reboot and the approved memory gate.**



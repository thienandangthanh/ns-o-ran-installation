# User rulings for P10 attempt 3: memory gate and release order (2026-10-28 22:10 and 22:19 KST)

Context: PAUSE T8 after the memory reap of M9 attempt 2 (`docs/journals/2026-10-28-m8-m9-p10-pause-t8-memory-reap.md`; counsel `plans/reports/kongming-261028-2145-GH-1-p10-attempt-2-memory-reap-failure-counsel.md`).

## Ruling 1: pre-launch memory gate (user, 22:10 KST, verbatim: "I approve the memory check.")
After the revert to `fresh-install`, with the VM running and before the runner starts: host `MemAvailable` + qemu RSS (the `ubuntu24.04` guest process) must be ≥ 23 GiB. If it is lower, do not launch and print PAUSE T3. The gate only adds a check: no test, pass condition or budget changes. The 23 GiB figure is a judgment (about 17 GiB qemu peak plus 6 GiB headroom), not a measurement. Record `free -g`, `/proc/pressure/memory` and `pgrep` for browsers at pre-flight as facts, never as gates.

## Ruling 2: host environment (user, 22:10 KST, verbatim: "I'll reboot the whole host machine and start only orca, claude for the task.")
Attempt 3 runs after a host reboot, with only Orca and Claude Code started. The VM is shut off before the reboot (it is now), so the reboot does not touch its state.

## Ruling 3: release order, item 5 (user, 22:19 KST, verbatim: "I approve Item 5.")
Phase-10 pre-flight item 7 (`df -BG /home` ≥ 84, else PAUSE T2) moves after the revert and the leaked-overlay deletion. The order for attempt 3:
1. Resume checks (VM shut off, current `fresh-install`, chain fresh-install > f7-rerun-green > r0-green > r2-green > r3p-green plus `m0-probe-n10280921` and `m0-probe-o10281122`).
2. Pre-flight items 2–6 at F′ `fb3554af67010dfedb6ae500e533acb7cdac9530`, and no `p[0-9]-*` or `m0-*-p*` names.
3. Update the resume card, commit and push.
4. `scripts/vm/vm-snapshot.sh revert fresh-install`.
5. Leaked-overlay checks 1–5 on `ubuntu24.1793186558` only (`plans/reports/decisions-261028-2014-GH-1-leaked-overlay-deletion-ruling.md`), then `rm` and `virsh -c qemu:///system pool-refresh VMs`, logged under `evidence/p10-disk/<ts>/` with the space freed. `ubuntu24.1793186494` (frozen data of `m0-probe-o10281122`) is never deleted.
6. `df -BG /home` ≥ 84 (88 with the margin; about 101 expected), else PAUSE T2. Confirm `r3p-green` is listed.
7. The memory gate (ruling 1).
8. Commit the projection row, then launch with prefix `p`.

The 84 GiB threshold itself is unchanged: T = (25 + h) + M0–M7 + R section = 29 + 43 + 12 (`m9-budget.md`).

## Ruling 4: reaper environment variable (user, 22:35 KST, verbatim: "1 yes")
The user starts the attempt-3 Claude Code session with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` in its launch environment (for example `env CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 claude`). Pre-flight records `printenv CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` as a fact.

## Ruling 5: hybrid launch route (user, 22:35 KST, verbatim: "2 hybrid")
The runner runs as a transient user unit started by `systemd-run --user --wait` with `KillMode=mixed`, launched through the Claude Code background shell, per `plans/reports/kongming-261028-2215-GH-1-p10-reaper-env-var-vs-systemd-run-advice.md` (Q3 command, work checklist items 3–9; Codex's view in `plans/reports/codex-261028-2218-GH-1-p10-reaper-env-var-vs-systemd-run-advice.md`). Recorded as the binding "Launch-route amendment" block in `phase-10-m9-unattended-run-from-fresh-install.md`. It changes no test, pass condition, budget or file under `scripts`/`tools` (K14 holds at F′).

## Ruling 6: `finish()` orphan gap (user, 22:35 KST, verbatim: "4 after M9")
Recorded, not fixed before M9; listed in the handoff as a post-M9 harness fix (drop the `kill -0` guard before `vm_stop_gates`; correct the TERM trap message).

## Ruling 7: prefix (user, 22:38 KST, verbatim: "approve prefix p.")
Re-issuing the goal means M9 attempt 3 with `--run-prefix p` at F′ `fb3554af67010dfedb6ae500e533acb7cdac9530`, under rulings 1–6.

All attempt-3 questions are ruled.

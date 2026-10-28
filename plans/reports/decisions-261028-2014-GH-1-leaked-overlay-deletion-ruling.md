# User ruling: deleting leaked VM overlay files (2026-10-28 20:14 KST)

**Ruling (user, verbatim):** "I approve you to delete similar files like that. only do it after the same checks, logging each one with the space."

**Context.** PAUSE T1 (`docs/journals/2026-10-28-m8-m9-p10-pause-t1-leaked-overlay.md`). A revert to `fresh-install` did not unlink M9 attempt 1's working overlay, `/home/andang/VMs/ubuntu24.1793179340` (16 GiB). The cause is that `gate-m0-host.sh`'s probe branch create and delete clear libvirt's `revertDisks` record, so the overlay that becomes active after the probe is untracked (`plans/reports/kongming-261028-1945-GH-1-p10-attempt-2-disk-go-no-go.md`). The user deleted that file at about 20:10 KST. Afterwards host free was 101 GiB, the VM was running on `ubuntu24.1793183688` over `ubuntu24.04`, and every snapshot's frozen data was present.

## What the agent may now delete

A file in `/home/andang/VMs/` that is a **leaked former-active overlay**: an `ubuntu24.<epoch>` or `ubuntu24.04-*.qcow2` image that was the VM's active disk earlier in this project and survived a revert. Nothing else is covered: no snapshot, no base image, no file outside `/home/andang/VMs/`.

## The checks (all must pass, run read-only, before each deletion)

1. The file is not the active disk: it is absent from `virsh -c qemu:///system domblklist ubuntu24.04`.
2. No domain definition references it: `virsh -c qemu:///system dumpxml ubuntu24.04` and `dumpxml --inactive` both lack its name.
3. No snapshot references it: its name appears in no section of any `snapshot-dumpxml` (`disks`, `revertDisks` or `domain`).
4. No other image can depend on it. Every image created after it has a known backing file, and none is this file (from the snapshot XMLs and the gates' `disk-chain-*.txt` evidence).
5. Nothing has it open: the VM state and the file's mtime show it has not been written since the run that used it stopped, and its evidence is already archived on the host.

## Logging (each deletion)

Write `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/p10-disk/<UTC-ts>/` holding:
- the outputs of checks 1–5;
- `ls -la --time-style=full-iso /home/andang/VMs` and `df -BG /home` before and after the deletion;
- the command run (`rm <file>`, then `virsh -c qemu:///system pool-refresh VMs`);
- the space freed in GiB.

Add one line to the resume card and to `m9-budget.md` (file, size, space freed). If any check fails, do not delete; that is still PAUSE T1.

## Precedence

This ruling extends the snapshot rule (plan.md invariants card) for these files only. `fresh-install`, `f7-rerun-green` and the top rung's green snapshot, together with their frozen data files, stay protected.

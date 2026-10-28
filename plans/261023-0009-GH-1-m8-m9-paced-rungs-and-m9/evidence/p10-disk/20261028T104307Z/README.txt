P10 attempt-2 disk evidence (2026-10-28 19:43 KST), read-only host captures.
After `vm-snapshot.sh revert fresh-install` at 10:34Z, df -BG /home stayed 85 GiB: attempt 1's overlay
/home/andang/VMs/ubuntu24.1793179340 (16 GiB, root:root 0600, mtime 18:59:44 KST) was not unlinked by libvirt.
Orphan proof: not the active vda (domblklist.txt); referenced by no live/inactive domain disk XML and by no
snapshot (snapshot-source-files.txt); it was attempt 1's active vda on ubuntu24.04
(../../m0/20261028T092148Z-host/disk-chain-after-branch-delete.txt). virtqemud journal for the revert window:
no lines readable (virtqemud-journal-revert.txt). Pool VMs is active (pool-list.txt): pool-refresh after a delete.
Counsel: plans/reports/kongming-261028-1945-GH-1-p10-attempt-2-disk-go-no-go.md

# Probe P-A (offline): is free-run ns-3 output repeatable?

Run 2026-10-22T02:09Z on the host, from committed evidence only (no VM). Script: `scripts/probes/compare-ns3-ipc-sample-digests.py`. It compares IPC `sample` lines per node by `seq`, after dropping `ipcDropped`; `hello` lines are excluded because they carry the wall-clock epoch and a pid-based run id.

| File | Runs compared | Result |
|---|---|---|
| `m4-default-dev-vs-p8.json` | M4 default r1–r3 dev (`m4/20261021T165230Z`) and r1–r3 P8 rebuild from fresh-install (`m4/20261021T225423Z`) | 5 nodes × 100 samples, 0 mismatches |
| `m7-three-live-runs.json` | M7 dev attempt 1 (`m7/20261021T181249Z`), attempt 2 (`m7/20261021T184727Z`), P8 (`m7/20261021T233129Z`), live RIC, e2term delete, agent restarts | 5 nodes × 420 common samples, 0 mismatches |
| `m7-live-vs-m4.json` | the three M7 runs and M4 dev r1 | 5 nodes × 100 common samples, 0 mismatches |
| `m7-handover-trace-prefix-digests.txt` | `UeHandoverEndStats.txt` and `CellIdStats.txt`, first 366 lines | identical across the three M7 runs (P8 is longer because simTime was 45, not 42) |

Byte compare of the 45 files of the M4 default r1–r3 directory (orchestrator, `md5sum`): 38 identical. The differences are `stdout.txt` (timing), the 5 IPC traces (`hello`, `ipcDropped`) and `DlE2RlcStatsLte.txt`. The last one differs in RNTI/LCID columns, which counsel A reports for 9 rows of cell 4 / IMSI 11; the cause is not confirmed.

**Conclusion.** With no external input, ns-3 sim output is bit-identical run to run, across rebuilds, and under a live RIC with drops and reconnects. Repeatability of a closed loop therefore reduces to the repeatability of the applied-control sequence: the step, sim time, IMSI and target of each control.

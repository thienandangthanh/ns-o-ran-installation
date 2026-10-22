# Probe: RIC/E2 reaction to a paused ns-3 (SIGSTOP 60 s, 300 s, 900 s)

Run 2026-10-22T02:20–02:49Z on the VM from a revert of `f7-rerun-green`, harness `d87effa`, script `scripts/probes/probe-ns3-pause-ric-reaction.sh`, launcher `scripts/probes/vm-exec-probe.sh`. Default config: 5 agents (eNB 1, gNB 2–5) with kpimon subscribed, ns-3 free-run. No snapshot was taken and nothing was pushed to the forks. The VM was reverted afterwards.

**Result: no RIC or E2 component reacted to any pause, up to 900 s.**

| Evidence | 60 s | 300 s | 900 s | Source |
|---|---|---|---|---|
| E2AP frames on docker0 during the pause | 0 | 0 | 0 | `pause-wire-facts.json` (from `pause-wire-fields.tsv`, tshark `-d sctp.port==36422,e2ap`) |
| SCTP HEARTBEAT / HEARTBEAT-ACK | 59 / 59 | 285 / 285 | 858 / 858 | same; all 10 association directions |
| ABORT, SHUTDOWN, INIT, RICsubscription, RICsubscriptionDelete, ErrorIndication, Reset | none | none | none | same |
| e2mgr: all 5 nodes CONNECTED in every sample; agent RestartCount 0, READY, subs ≥ 1; ricplt pod restarts and kpimon pod unchanged | yes | yes | yes | `checks/pause_*_ric_state_unchanged_every_sample.out`, `pause-*/sample-*` (every 30 s) |
| Indications resume on every node after SIGCONT | within 3 s | within 8 s | within 8 s | `gate.log`, `checks/pause_*_indications_resume_on_every_node.out` |
| RIC logs inside the window (e2term, submgr, e2mgr, rtmgr, kpimon) | RMR statistics and periodic polls only; no error/timeout/delete/disconnect/reset line | same | same | `ric-logs-in-pause-windows.txt` |

**ns-3 output is unchanged by the pauses.** All 5 IPC traces have 73 contiguous samples with `ipcDropped` 0, and those samples equal the M7 P8 free-run samples (`m7/20261021T233129Z`) for the common 73 seqs: `paused-vs-m7-free-run-digest.json`, 0 mismatches.

**The three FAIL checks in `verdict.json` are a probe-design error, not a finding.** `pause_*_no_indication_sent_while_stopped` compared the agents' `indTx` counters read just before SIGSTOP and just before SIGCONT. Those counters come from each agent's stats line, which is printed only every 5 s, so the "before" reading lagged by up to one stats period on every node (for example node 1: 5 → 9 in the 60 s window). The wire, which is the ground truth, shows 0 E2AP frames inside every window.

Large ns-3 trace files (> 2 MB) are not committed; their sha256 values are in `ns3run-large-files-sha256.txt`.

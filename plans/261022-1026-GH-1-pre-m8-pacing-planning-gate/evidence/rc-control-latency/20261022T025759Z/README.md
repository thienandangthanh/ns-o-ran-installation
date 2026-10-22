# Probe: rc gRPC call → RICcontrolRequest at the agent (wall latency)

Run 2026-10-22T02:58–03:03Z on the VM, from a revert of `f7-rerun-green`.
- Harness `d87effa`; script `scripts/probes/probe-rc-control-latency.sh`.
- rc xApp installed by NIST's `install_xapp_ric_control.sh` at rc `a2282ee` (`rc-sha.txt`).
- grpcurl 1.9.1, sha256-checked against the release checksum file.
- 5 default agents, kpimon subscribed, ns-3 default config running free during the calls (realistic CPU load).
- No snapshot was taken and nothing was pushed to the forks. The VM was reverted afterwards.

**Result.** 30 gRPC calls were made round-robin over the 5 nodes, 2 s apart. Each produced exactly one RICcontrolRequest on docker0 to that node's container.

| Measure | Value | Source |
|---|---|---|
| grpcurl start → RICcontrolRequest frame at the agent | min 5.6 ms, p50 6.5 ms, p90 7.7 ms, max 9.9 ms (n = 30) | `rc-latency.json`; re-computed on the host with tshark 4.7.4 from `rclat.pcap`: min 5.6, p50 6.6, max 9.9 ms (`rc-control-frames-host-tshark.tsv`) |
| grpcurl call duration (gRPC `rspCode 0` means "queued") | p50 7.4 ms, max 11.4 ms | `calls.tsv` |
| RICcontrolRequest frames on the wire / malformed | 30 / 0 | host tshark |
| Agent log `rx RICcontrolRequest (procedure 4)` | 6 per agent, 30 in total | `agent-*.log` |
| rc pod RestartCount before / after | 0 / 0, same pod | `rc-pod-before.txt`, `rc-pod-after.txt` |
| RICcontrolAcknowledge / Failure on the wire | 0. Today's agents only log the request. | host tshark |

The latency includes the grpcurl process start, so the RIC chain itself (rc → RMR → e2term → SCTP) is under 10 ms on this stack.

**Side finding.** e2term 6.0.6 forwarded every RICcontrolRequest to the nodes even though no agent advertises RAN function 3 today. Routing is by ranName/MEID only. The agents must therefore validate the RAN function themselves.

Large ns-3 trace files (> 2 MB) are not committed; their sha256 values are in `ns3run-large-files-sha256.txt`. The pcap stays out of git, and `pcap-sha256.txt` holds its sha256.

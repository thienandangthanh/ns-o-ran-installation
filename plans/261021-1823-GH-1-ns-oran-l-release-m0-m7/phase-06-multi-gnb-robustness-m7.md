# P6 — Multi-gNB robustness (M7)

## Requirements
- One agent per scenario-zero E2 node (4 mmWave gNBs, plus the LTE eNB if it is an E2 node by default; the set is fixed in P3). Each agent has its own netns and a distinct global node ID.
- A start-all and stop-all script that is idempotent.

## Gate M7 (`gate-m7-multignb.sh`)
1. **All connected.** e2mgr lists every node CONNECTED with distinct IDs. The pcap shows one SCTP association per agent, each from its own netns address, with no src-port collision.
2. **Per-node indications.** For every node, tshark sees RICindications, and the kpimon harness gives `RC_OK` for header and message. InfluxDB has rows per cell.
3. **Endurance.** A 15-min wall-clock run (simTime chosen from the M4 timing to cover it) with no crash in ns-3, the agents or kpimon. ricplt pods show zero new restarts and no SCTP ABORT.
4. **e2term pod delete.**
   1. `kubectl -n ricplt delete pod <e2term>`, then wait for the new pod to become Ready.
   2. Within a bounded time (record it), every node is CONNECTED again and indications resume. Prove this with tshark (new associations to the same Service address) and with fresh InfluxDB rows.
   3. No manual IP or config change.
   4. ns-3 keeps running throughout. Record the samples dropped while agents were down (that is expected).

Pass → snapshot `l7-multignb`.

## Risks
- **e2mgr or e2term may treat a reconnecting node with the same ID as a duplicate.** Observe it, don't assume. Consult kongming after 2 failed attempts.
- **The run may be CPU-bound** (5 agents + ns-3 + RIC on 8 vCPU). Watch load in the evidence and note it for the pre-M8 pacing gate.

## Review amendments (contract-preserving review, 2026-10-21)
- **K2:** "rows per cell" means Influx rows per `ns3.nodeId`.
- **K10:** capture on `docker0` (one interface) for the per-agent associations. Each agent's own container IP is visible there, before NAT.
- **K7: e2term pod-delete step.**
  - Bounded wait; record time-to-CONNECTED and time-to-first-indication per node.
  - Assert on the wire a **new RICsubscriptionRequest per node**. submgr drops subscriptions on DISCONNECTED and kpimon re-subscribes.
  - Agents restart via `--restart always`, and ns-3 survives (`MSG_NOSIGNAL`).

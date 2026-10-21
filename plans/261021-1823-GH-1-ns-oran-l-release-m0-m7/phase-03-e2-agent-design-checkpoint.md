# P3 — E2 agent design checkpoint (user sign-off before P4)

## Inputs
- The P2 golden pcap and harness: wire truth for E2Setup, Subscription and Indication from NIST's own node.
- The ns-3 metric set from the scout:
  - cell: `TB.TotNbrDl.1`, `RRU.PrbUsedDl`, `CARR.PDSCHMCSDist.*`, `L1M.RS-SINR.*`, …
  - per UE: `DRB.UEThpDl.UEID`, …
  - The cell object is `NRCellCU`. The CU-UP, CU-CP and DU split matches the file-logging CSVs.
- ns-3 E2 identity today: `gnb_id = cellId`, PLMN `111`, `local_port = 38470 + cellId`. scenario-zero has 4 mmWave gNBs and 1 LTE eNB.

## Questions to settle (kongming counsel, Opus 5.5 xhigh, then a journal)
1. **IPC format.** One sample per gNB per `indicationPeriodicity`, carrying:
   - the full metric set
   - sim time (ns, int64)
   - the gNB/cell identity
   - a sequence number

   Candidates: length-prefixed protobuf, CBOR, or line-delimited JSON. Requirement: option B later changes only the agent.
2. **Transport and placement.** Each agent needs its own netns.
   - (a) One Docker container per agent, like NIST's `oransim`. ns-3 connects over TCP to a host-published port per agent.
   - (b) One k8s pod per agent (Deployment or StatefulSet), with ns-3 reaching it over TCP.
   - UDS is possible only with a shared volume.
   - Also choose the target address. It must be the e2term **Service** (ClusterIP or DNS), never a pod IP.
3. **Agent source home and build.** Build with NIST's e2-interface build (`install_e2sim.sh` style, `da6f82f2`).
   - Where the agent's main/IPC code lives: a new dir on the `oran-e2sim` fork branch, or `install_patch_files/e2-interface/...` on the Testbed fork, as NIST does with `kpm_e2sm`.
4. **E2SM content.**
   - RAN function ID **2**, a hypothesis to re-check against the live kpimon.
   - The RAN function definition: KPM v3 with the real OID, or keep `OID123`. Re-check whether e2term 6.0.6 or kpimon cares.
   - The 8-byte TimeStamp encoding from the sample's sim time plus a start epoch.
5. **Subscription option A.** Accept every subscription, reply with the requested actions admitted, and forward every sample under each active subscription's RIC request ID. Ignore the period and the metric list. Document how option B would slot in.
6. **Robustness.**
   - When the agent loses SCTP (e2term pod deleted): exit and let the restart policy reconnect, or reconnect in-process.
   - How ns-3 behaves while its agent is down: non-blocking send, drop and count, never stall sim time. KPM-only runs free with no pacing.
7. **Lifecycle.** Who starts N agents and with which IDs, how gate scripts discover them, and process hygiene.

## Deliverables
- `docs/journals/<date>-p3-e2-agent-design-checkpoint.md`: options, kongming advice, the recommendation, and how each choice serves M5–M7 and keeps M9 possible.
- An IPC schema file (versioned) in the chosen source home.
- An implementation-notes entry.

## Gate
**The user signs off on the journal.** Per the checkpoint-before-hard-decisions habit, the journal must be self-sufficient for a cold `/deep-understanding` session. Do not start P4 until sign-off.

## Review amendments (contract-preserving review, 2026-10-21)
Mandatory P3 items:
- **K1: E2 node identity (verified).**
  - e2-interface `da6f82f2` hardcodes gNB ID `B5 C6 77 88` and PLMN `"747"` (`encode_e2apv1.cpp:158-174`), and `run_loop` hardcodes `OID123`. Every agent would register as the same node.
  - Choose:
    - (a) Recommended by kongming: a NIST-style whole-file patch to `encode_e2apv1.cpp` that reads gNB ID, PLMN and OID from env vars, with today's constants as defaults so `oransim`/kpm_sim behave identically.
    - (b) An agent-owned setup and receive loop built from e2sim's exported pieces.
  - Recommended source home: the Testbed fork, `install_patch_files/e2-interface/e2sim/e2sm_examples/<agent>/`, built with a Dockerfile derived from `e2sim/Dockerfile_kpm`. Nothing then links the wineslab `oran-e2sim` tree. The `oran-e2sim` fork branch stays as the cut-from-pin branch the contract lists, possibly unused, and that is recorded.
- **K2: kpimon ingest profile.**
  - kpimon writes Influx points with **no tags** and `time.Now()` (`control.go:957-980`).
  - It drops a format-1 message when the record count differs from the declared KPI count (`:773-775`).
  - It reads format-2 as metric-major `measData[0]` (`:845`) and casts integers to int32.
  - It creates format-1 actions only from an F1 component config (`f1apServer.go:91-98`). e2sim sends NG, so kpimon creates 0 format-1 actions and 1 format-3 action.
  - The design must specify:
    - a fixed, ordered cell KPI list (noValue or 0 when a value is missing);
    - kpimon's format-2 layout;
    - REAL encoding for values that can exceed int32;
    - how cell metrics reach Influx under option A;
    - **synthetic correlation KPIs** in both lists (`ns3.nodeId`, `ns3.simTimeMs`, `ns3.seq`), so the M6 and M7 joins work without patching kpimon beyond SIZE(8). Patching kpimon to add tags would widen the locked patch scope and needs user approval.
- **K5: the ns-3 side is v1-style.**
  - ns-3 builds Format1 with PF-Containers (`kpm-indication.cc:404-468`) and sends 3 indications per period (CU-UP, CU-CP, DU).
  - The design must add a versioned **metric-mapping table** (ns-3 field → KPM v3 measName), which the M6 gate also uses.
  - One merged sample per node per period, including the LTE CU-CP per-UE L3 measurements.
  - The emitter is scheduled at init. Online reporting today starts only on a subscription.
- **K7: restart semantics.**
  - e2sim `exit(1)`s on send/recv -1, and a graceful close makes `run_loop` return 0.
  - submgr 0.10.2 drops a node's subscriptions on DISCONNECTED, and kpimon re-subscribes after its 5 s poll.
  - Requirements:
    - Docker `--restart always`.
    - The agent starts with an empty subscription table and handles subscription delete.
    - ns-3 IPC writes use `MSG_NOSIGNAL` and reconnect without blocking, with backoff.
- **K11: single-node configuration.** Decided as D3 in plan.md: scenario-zero gets an optional `--nMmWaveEnbNodes` (default 4), and P3 states which E2 nodes exist for 1 and for 4.

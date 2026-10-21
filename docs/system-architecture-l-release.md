# System architecture: ns-O-RAN on the OSC Near-RT RIC L-release (Approach A)

This note explains how ns-3 scenario-zero reaches the Near-RT RIC after the L-release port, and why it is built that way. Code owns the exact behaviour; this note owns the reasons and the map. Commands are in [deployment-guide-l-release.md](deployment-guide-l-release.md). The decision record, with the alternatives that were rejected, is the dated journal [journals/2026-10-21-p3-e2-agent-design-checkpoint.md](journals/2026-10-21-p3-e2-agent-design-checkpoint.md); it is a snapshot in time and this note does not replace it.

## 1. Outcome and approach

Every E2 node that scenario-zero simulates is served by its own out-of-process E2 agent. ns-3 does not link asn1c or e2sim and does not speak SCTP. Each agent runs in its own container and network namespace, connects to the e2term SCTP **Service** (never a pod IP), and presents itself to the RIC as a separate E2 node. The RIC side is NIST O-RAN-Testbed-Automation v1.8.0 on the L pins, with kpimon-go patched only for an 8-byte TimeStamp.

Why this shape:

- The old design linked an E2 library into ns-3 and ran all nodes in one process. That fixes ns-3 to one asn1c and E2AP version and makes the simulator carry RIC protocol code. The agent boundary moves that code out and lets the RIC side change without touching ns-3 physics.
- Each node needs its own SCTP association, identity and lifecycle, and the RIC must see distinct nodes. One container per node gives that without shared global state.
- NIST's reference node cannot be the agent. Its loop runs a report loop inside the subscription callback and never reads SCTP again, never dispatches a subscription delete, calls `exit(1)` on send or receive errors, and hard-codes its identity. The agent therefore owns its loop and reuses NIST's E2AP generators and asn1c codecs unmodified, editing the generated PDUs in place where they are wrong. No NIST file is changed.

## 2. Components and data flow

```mermaid
flowchart LR
    subgraph sim[ns-3 process]
        S[scenario-zero]
        E[IPC emitter per node]
        T[(local trace<br/>e2-ipc-trace-N.jsonl)]
        S --> E
        E --> T
    end
    E -- "NDJSON over TCP<br/>127.0.0.1:38470+cellId" --> A1
    subgraph agents[one container per E2 node, own netns]
        A1[ns3-e2-agent<br/>node N]
        A2[ns3-e2-agent<br/>other nodes]
    end
    A1 -- "E2AP / E2SM-KPM over SCTP" --> SVC
    A2 -- "E2AP / E2SM-KPM over SCTP" --> SVC
    subgraph ric[Near-RT RIC on k8s]
        SVC[e2term SCTP Service<br/>ClusterIP :36422]
        E2T[e2term]
        MGR[e2mgr]
        KP[kpimon-go xApp]
        DB[(InfluxDB)]
        SVC --> E2T
        E2T <--> MGR
        E2T -- RMR --> KP
        KP --> DB
    end
```

| Component | Role | Owner (where to look) |
|---|---|---|
| ns-3 `scenario-zero` | Simulates cells and UEs; builds one sample per node per period | fork of ns-3-mmwave-oran (pin in `scripts/pins.conf`) |
| IPC emitter | Serialises each sample as one JSON line, writes it to the local trace, then sends it to the agent | `oran-interface/model/e2-ipc-*` (fork pin in `scripts/pins.conf`), `oran-interface/README.md` |
| E2 agent | One per node. Speaks E2AP and E2SM-KPM to e2term, forwards ns-3 samples as indications | `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/` |
| e2term Service | The stable address of e2term; survives pod deletes | resolved by `install_scripts/run_ns3_e2_agents.sh` |
| kpimon-go | Subscribes to each connected node, decodes KPM, writes InfluxDB points | NIST `additional_scripts/install_xapp_kpi_monitor.sh` and its patches |
| Gate harness | Builds, runs and judges everything above | `scripts/`, `tools/` |

Placement and transport choices, and what was rejected:

- **Container per agent**, not a Kubernetes pod. This is the path the M2 probe proved (Docker bridge to the ClusterIP). Pods would need an image import into containerd, pod IPs change, and CrashLoopBackOff backoff reaches minutes.
- **ClusterIP resolved at agent start.** Containers cannot resolve cluster DNS, so the launcher resolves the single `service-ricplt-e2term-sctp*` Service with kubectl and passes its IP. The ClusterIP is stable across e2term pod deletes.
- **NodePort SCTP is not used.** Earlier testbed work recorded it as not viable on this stack (not re-tested in this port, unverified).
- **ns-3 to agent is TCP on the loopback**, port `38470 + cellId`. Agent containers publish that port on `127.0.0.1`.

Node identity: each agent registers as a gNB-type E2 node with gNB-ID equal to the ns-3 cellId and PLMN `00101` by default, so e2mgr names it `gnb_001_001_<id as 8 hex digits>`. The LTE eNB (cellId 1) also registers as a gNB-type node while reporting its eNB metric set. Both are deliberate and signed off; they are labelled in the evidence.

## 3. IPC schema v1

The schema is the authority: `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/schema/ns3-e2-ipc.v1.schema.json`. Summary of intent only:

- **Transport.** Newline-delimited JSON over TCP, UTF-8, one object per line, at most 1 MiB per line, ns-3 to agent only.
- **Messages.** `hello` (sent on every connect: node, kind, period, the wall-clock epoch that maps to sim time 0, run id, emitter SHAs), `sample` (one per node per period: cell sections and a UE list sorted by IMSI, a per-run sequence number, the sim time and the emitter's drop counter), `bye` (final counters).
- **Full-set rule.** A sample carries every value ns-3 computes, regardless of `reducedPmValues`. A later subscription filter (option B) can then live in the agent alone.
- **Exact values.** Doubles use the shortest round-trip decimal so values compare bit for bit. Non-finite doubles are `null`.
- **Trace equals wire.** ns-3 writes the identical line to its local trace before sending, so the trace is the ground truth the gates compare Influx against, including samples dropped because the agent was down.
- **Evolution.** Receivers ignore unknown keys; a new key bumps `minor`, a breaking change bumps `v`. The types `control`, `controlAck` and `step` are reserved for RC and pacing; v1 emitters drain and ignore inbound bytes.
- **Emitter behaviour.** Non-blocking sends, a bounded buffer that drops and counts on overflow, reconnect with backoff, scheduling at init. ns-3 never waits for a subscription and never stalls simulated time.

Why JSON: the NIST build image already ships a JSON library, ns-3 needs only a small serialiser, shortest round-trip doubles give bit-exact comparison, and the trace file doubles as the wire record. Protobuf would add code generation in two toolchains; CBOR gains nothing here.

## 4. Agent state machine and robustness

The agent is a single-threaded `poll()` loop over the SCTP socket, the IPC listener and client sockets, and a timer. States and timings (defaults in `src/agent-config.hpp`, logic in `src/e2-session.cpp`):

1. **Hold-off**, 8 s after start.
2. **Connecting** on a fresh socket with an **ephemeral SCTP source port**, retried every 2 s without end.
3. **Setup sent.** No E2SetupResponse within 10 s, or an E2SetupFailure, exits with code 3.
4. **Ready.** The subscription table starts empty. A subscription request for the KPM function is admitted and stored, a subscription delete removes the entry and is answered, a service query is answered with a service update, and an undecodable PDU is logged and counted, never fatal.
5. **Association lost** exits with code 2. Invalid configuration exits with code 1.

Docker's `--restart always` restarts the container, which returns with empty state and goes through the hold-off to a fresh E2Setup. Every agent writes a JSON stats line every 5 s.

Why these choices:

- **8 s hold-off.** kpimon re-subscribes only after one of its 5 s polls has seen the node not CONNECTED. A faster return leaves a node that is CONNECTED but silent.
- **Ephemeral port.** A reconnect from the same NAT five-tuple can be forwarded to a dead pod's conntrack entry. A new port is a new flow. NIST's kpm_sim uses a fixed 36422, and the probe showed both work for a first connect.
- **Retry forever while connecting.** Exiting because e2term is not up yet would make Docker's restart backoff grow to a minute.
- **Exit on loss, let Docker restart.** It gives the same clean-state path after an agent crash, an e2term pod delete, or a lost setup. The cost is minutes of recovery after an e2term delete, because agents retry until the new e2term has registered with e2mgr. This was measured in the development run of M7.
- **Graceful stop.** On SIGTERM the agent sends an SCTP SHUTDOWN (bounded 2 s wait) while its network namespace still exists, and the stop script uses `docker stop -t 10` before removing the container. Without that, e2term learns of the loss only from heartbeat timeouts, e2mgr keeps a stale CONNECTED node, and kpimon never re-subscribes to it.
- **Subscription option A.** The agent admits the subscription without interpreting the action definition and forwards every sample. Option B (honouring the action definition) would change only the agent.

Constraints from NIST's E2AP generators, handled by in-place edits of the generated PDUs: the subscription response hard-codes a RAN function id, the "not admitted" branch writes into the admitted list, the setup request leaves some OCTET STRING contexts uninitialised, and the indication generator copies into a fixed 8192-byte buffer.

## 5. E2SM-KPM content

Facts checked against kpimon's code (`control.go`, `wrapper.c`) and the golden capture from the reference node:

- **RAN function 2**, short name `ORAN-E2SM-KPM`, and the real KPM OID `1.3.6.1.4.1.53148.1.3.2.2`. kpimon subscribes with function 2 and requires the node to advertise it. Wireshark selects its KPM dissector by the exact short name. e2term accepted the real OID (checked by M5); `E2_KPM_OID=OID123` is the documented fallback.
- **Two report styles** in the function description: style 1 with action format 1 and the **cell** measurement list, and style 3 with action format 3 and the **UE** list. kpimon builds its single action from both lists.
- **Header.** Indication header format 1 with an 8-octet `colletStartTime` in NTP-64 form (seconds since 1900 plus fraction), computed from the hello's epoch plus sim time. kpimon decodes the header and discards its fields; Influx stamps `time.Now()`.
- **Messages.** Both go under kpimon's single subscription, and kpimon dispatches by message format. Cell metrics use **Format 1**, records in exactly the advertised list order with `noValue` for missing values (kpimon drops a message whose record count differs from the list length). UE metrics use **Format 2**, metric-major, then UE by UE in IMSI order.
- **REAL versus INTEGER.** kpimon casts INTEGER to int32. INTEGER is therefore used only for values guaranteed in 0 to 2^31-1 (IDs, bounded per-period counts, percentages). Volumes, bytes, throughput, delay and SINR in dB are REAL. An out-of-range INTEGER becomes `noValue` and is counted.
- **Correlation KPIs.** Both lists start with `ns3.nodeId`, `ns3.simTimeMs` and `ns3.seq`; the UE list adds `ns3.imsi`. The gates join InfluxDB rows to the ns-3 trace on `(nodeId, seq)` and `(nodeId, seq, imsi)`, never on `_time`, because kpimon stamps its own time.
- **Metric map.** `ns3_e2_agent/schema/metric-map.v1.json` maps each ns-3 field (a JSON pointer into the sample) to a KPM measurement name, list, order, id, type and unit. Names must be PrintableString-legal, so `_` is not used and `_Filter` and `.UEID` are dropped from legacy names. The L3 SINR items are flattened into numeric `ns3.l3.*` columns. The agent logs the file's sha256 and advertises its short hash in the function description, and the M6 gate asserts that the hash on the wire equals the file at the pinned commit. `ns3_e2_agent/tests/lint-metric-map.py` checks one type per name, legal characters, and unique stable ids; `install_ns3_e2_agent.sh` runs it before every build.
- **Sizing.** At most four UEs go into one indication, and the chunk is halved if the E2SM message exceeds 7000 bytes, which keeps clear of the generator's 8192-byte buffer.
- **Version mismatch, handled by a rule.** The agent encodes with NIST's KPM v3 asn1c; kpimon decodes with its v2 schema. The structures used are identical in both. The rule is never to set a v3-only extension field. The agent's sender type is `ns-3-sim` because v3 limits it to eight characters.
- **Known dissector noise.** tshark 4.4 still flags two non-indication frames as malformed: NIST's dummy component-config bytes inside the E2SetupRequest (carried unchanged), and kpimon's own subscription request (format 3 action definition encoded with kpimon's v2 schema). Neither comes from this project's code, and the gates require zero malformed indication frames instead.

## 6. kpimon TimeStamp SIZE(8) patch

**Problem.** kpimon's decoder is pre-generated asn1c C for E2SM-KPM v2.0, with `TimeStamp ::= OCTET STRING (SIZE(4))`. KPM v3 nodes, including NIST's reference node, send an 8-byte TimeStamp. The stock decoder returns `RC_WMORE` for the header (and a SIZE(4) decoder that does return `RC_OK` consumes only part of the header and yields a wrong timestamp).

**Change.** `KPIMON_TIMESTAMP_SIZE8=true` makes `install_xapp_kpi_monitor.sh` apply two patches from `install_patch_files/xApps/kpimon-go/e2sm/`: the schema (`asn1/kpm2_0.asn.timestamp-size8.patch`) and the generated constraint tables (`lib/TimeStamp.c.timestamp-size8.patch`). Nothing else in kpimon changes.

**Proof that it is a regeneration, not a hand edit** (`tools/kpimon-asn1-regen/regen-check.sh`, run by gate M3):

1. The generator is asn1c `mouse07410@584d86e`, whose runtime skeletons are byte-identical to the 217 skeleton files shipped in kpimon. It is built at `-O0`, because newer GCC versions miscompile it at `-O2`.
2. Control: regenerating kpimon's stock schema reproduces every shipped file.
3. Footprint: changing SIZE(4) to SIZE(8) changes exactly one generated file, `TimeStamp.c`.
4. The shipped patch equals the regenerated file.

**Proof that it works** (`tools/kpimon-decode-harness`, run by gates M3, M6 and M7). The harness links kpimon's own `libe2smwrapper.so`, extracted from the kpimon image (`extract-from-image.sh`), and calls `asn_decode` as kpimon's wrapper does. In the green M3 run, the stock build decoded no header cleanly while the patched build decoded every header and message cleanly, and kpimon's log showed no `RC_WMORE` after the patch.

**What "RC_OK" means in the gates.** Return code OK, all input octets consumed, and for headers an 8-octet TimeStamp. A bare return-code check would pass a broken decode.

## 7. Evidence model

A gate is green only when wire bytes decode with tshark and, for KPM, through kpimon's own decoder; log lines are supporting evidence. Captures run on `docker0` with BPF `ip proto 132` (never `-i any`), start before the first E2Setup because Wireshark learns the E2SM mapping only from the setup, and are counted deduplicated by SCTP TSN and attributed by association. tshark 4.2.2 from noble cannot dissect KPM REAL records, so the gates use the `tshark-kpm` image (`tools/tshark-kpm`). Details of layout and tools: the deployment guide and `tools/e2-evidence/`.

## 8. Deliberately out of scope

- **RIC Control and M8.** The IPC message types and the agent's loop leave room for it; nothing implements it.
- **Pacing.** M5 to M7 run free: ns-3 emits at wall-clock speed without lock-step. The timing report `plans/reports/timing-261022-0217-GH-1-ns3-scenario-zero-real-vs-sim-time.md` (stateful, dated) records why this matters: the default scenario is much slower than real time, so the simulator is the slow side of any lock-step loop.
- **Subscription option B.** Honouring the action definition and reporting period is deferred; it would change only the agent.
- **N release.** The port targets L only. There is no fallback to another release.
- **Bronze RIC.** The legacy flow in the README is not exercised by the gates.
- **Scenario and radio changes.** None, apart from the optional `--nMmWaveEnbNodes` argument (default 4, unchanged behaviour) and the IPC emitter.

## 9. Known gaps against the target

- The agent's behaviour after an e2term pod delete depends on e2mgr and kpimon timing outside this repo's control. The design handles it by restarting agents; recovery takes minutes, not seconds.
- kpimon logs slightly fewer indications than the wire carried during very fast bursts in some runs (about 2 % in the M3 reference-node burst). The gates record this as a cross-check, not a pass criterion; M6 re-measures at ns-3's rate.
- Gate-level confirmation of M7 on the unattended re-run is recorded in the evidence directory, not in this note.

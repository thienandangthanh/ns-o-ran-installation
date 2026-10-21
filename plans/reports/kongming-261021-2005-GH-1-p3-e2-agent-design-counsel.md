# P3 counsel: E2 agent design (IPC, placement, build, E2SM, mapping, robustness, lifecycle)

Date: 2026-10-21 (Asia/Seoul). Author: kongming, running on Opus 5.5 (xhigh) per the user's routing rule. This is advice only; no project code was edited.

Inputs read: the contract (with both "User answers" sections), plan.md, phase-02/03/04/05/06, implementation-notes.html, the scout fact pack and the K-review report.

No M2/M3 evidence exists yet (the plan's `evidence/` holds only m0 and m1), so every wire-level statement here comes from source. Statements marked **(belief)** are inferences that a gate or probe must confirm.

## Evidence basis (abbreviations used in citations)

| Tag | What it is |
|---|---|
| E2SIM | NIST e2-interface `da6f82f2`, `e2sim/` (session scratchpad clone `.../scratchpad/p3/e2-interface/e2sim`) |
| NRT | Testbed fork `RAN_Intelligent_Controllers/Near-Real-Time-RIC/` (worktree submodule @ `0b1cf7a`) |
| KPC | kpimon-go `8bbbbbb9` `control/control.go` **after** NIST `control.go.patch`, with CRLF converted to LF. This is what `install_xapp_kpi_monitor.sh:130-135` deploys. Plan K2 cites pre-patch numbers, which run about 20 lower. To rebuild it, apply `NRT/install_patch_files/xApps/kpimon-go/control/control.go.patch` to 8bbbbbb9 after `sed 's/\r$//'`. |
| KPW / KPH | kpimon `e2sm/wrapper.c` (NIST-patched) / `e2sm/headers`, `e2sm/lib` (SIZE(8) applied), in scratchpad `k9/kp-nist` |
| OI, NS3, MW, LTE, MWH | oran-interface `5f547ae`, ns-3-mmwave-oran `8c42089d`. MW = `src/mmwave/model/mmwave-enb-net-device.cc`, LTE = `src/lte/model/lte-enb-net-device.cc`, MWH = `src/mmwave/helper/mmwave-helper.cc`. OI helper = `oran-interface/helper/*-indication-message-helper.cc` |
| WS | Wireshark `release-4.2` `epan/dissectors/asn1/e2ap/packet-e2ap-template.c` and `e2ap.cnf` (fetched) |
| RMR | ric-plt-lib-rmr **master** `src/rmr/si/src/mt_call_si_static.c`. Version caveat: kpimon's pinned RMR may differ. |
| MOBY | moby **master** `daemon/internal/restartmanager/restartmanager.go` |
| E2T | ric-plt-e2 **master** `RIC-E2-TERMINATION/BuildRunName.h`. Version caveat: deployed e2term is 6.0.6. |

---

## TL;DR

1. **Agent.** Build one small C++ agent per E2 node, each in its own Docker container on the default bridge (`--init --restart always`).
   - It links NIST's **unmodified** libe2sim and E2SM-KPM v3 asn1c for all encoding.
   - It owns its SCTP socket and E2AP dispatch in a single-threaded `poll()` loop: no `run_loop`, no callbacks, no patch to any e2sim file. Identity, OID and two e2sim bugs are fixed by editing the generated PDU in place.
2. **IPC.** ns-3 sends newline-delimited JSON over TCP to `127.0.0.1:(38470+cellId)`.
   - Every sample carries every value ns-3 computes today, in both the ASN.1 path and the file-logging path.
   - ns-3 writes the identical line to a local trace. That trace is the M6 ground truth.
3. **KPM content.** RAN function 2, short name `ORAN-E2SM-KPM`, the real KPM v3 OID, and an NTP-64 TimeStamp.
   - Cell data goes out as Format 1 and per-UE data as Format 2 (metric-major), both under kpimon's single format-3 action.
   - Correlation KPIs `ns3.nodeId`, `ns3.simTimeMs`, `ns3.seq` lead both lists, plus `ns3.imsi` in the UE list.
   - Volumes and anything that can go negative or exceed int32 are REAL, so M6 can require bit-exact equality, floats included.
4. **Robustness.** The agent exits on association loss (crash-only). On every start it waits 8 s, then retries the connect in-process forever from an **ephemeral** source port.
   - This makes the M7 e2term pod delete produce, per node, a new association, a new E2Setup and a new RICsubscriptionRequest.
   - It also avoids two traps: kpimon's 5 s poll missing a short outage, and reuse of the NAT 5-tuple.

---

## Reframed problem

**What P3 decides:** the contract between three things that M5–M7 gates must check independently:
- ns-3, which emits samples;
- the agent, which owns E2 and SCTP;
- kpimon, whose ingest rules are fixed because only the SIZE(8) patch is allowed.

**Requirements:**
- Gate evidence must be decodable from bytes (tshark plus the kpimon harness).
- Influx rows must join to the ns-3 trace without kpimon tags.
- The design must survive an e2term pod delete with no manual step.
- Option B and RC must remain agent-only or IPC-additive changes.

**Non-goals:** pacing, RC, option B and any kpimon change beyond SIZE(8).

The real fork inside Q3 is one level up from "patch e2sim or not": **who owns the event loop.** Once the agent owns it, the patch question disappears.

---

## Q1. IPC format and versioned schema: newline-delimited JSON over TCP, schema `ns3-e2-ipc` v1

**Recommendation: NDJSON.** Not length-prefixed protobuf, not CBOR.

**Why:**
- **No new dependency in the agent build.** NIST's kpm image already installs nlohmann/json (`E2SIM/Dockerfile_kpm:79-81`). NIST's kpm_sim already ingests line-delimited JSON with `getline` + `json::parse`, from a file or from a TCP feed: the VIAVI connector on port 3001 (`NRT/install_patch_files/.../kpm_e2sm/src/kpm/kpm_callbacks.cpp:143-176`, `:145`). The precedent sits inside the exact build we must use.
- **ns-3 side: about 100 lines of hand-written serializer, no library.** Doubles use `std::to_chars`, which gives the shortest round-trip form (GCC 13 has floating `to_chars`). Integers are int64.
- **M6 exactness.**
  - Shortest round-trip decimal to float64 is bijective, and nlohmann and Python `json` both parse with correct rounding.
  - The agent then carries the same float64 into an asn1c REAL (see Q4).
  - So float comparison can be **0 ULP**, which is stronger than the plan's "documented rounding rule".
- **The trace is the wire.** ns-3 appends the exact line it sends, so M6 joins on `(nodeId, seq)` with no re-serialization.
- **Schema evolution.** Additive keys plus a `v` major field. The agent ignores unknown keys. Option B reads only fields that already exist. RC/M8 adds new `type` values on the same socket.
- **Cost.** About 5–20 KB per sample per node at 10 Hz, which is noise next to ns-3's own CPU use.
- **Rejected options.**
  - Protobuf needs protoc and libprotobuf in two toolchains: the jammy builder image and the noble ns-3 CMake build. That adds codegen to the M4 surface, and its binary traces need extra tooling for M6.
  - CBOR is binary with no exactness gain over shortest-form JSON, and ns-3 would still need a writer.

**Schema v1.**
- Normative files: `ns3_e2_agent/schema/ns3-e2-ipc.v1.md`, plus `ns3-e2-ipc.v1.schema.json` for gate validation.
- Framing: UTF-8, one object per line, `\n`-terminated, at most 1 MiB per line. Non-finite numbers become `null`.
- Direction in v1: ns-3 → agent only. The agent never writes on the socket in v1. Emitters must still drain and ignore inbound bytes, so a v1.x can add controls without breaking anything.

| Message | Fields (type) |
|---|---|
| `hello`: first line after every (re)connect | `type:"hello"`, `schema:"ns3-e2-ipc"`, `v:1`, `minor:0`, `nodeId` (int, = ns-3 cellId), `kind` (`"gnb"`\|`"enb"`), `periodNs` (int64, E2Periodicity), `simStartEpochMs` (int64, ns-3 `m_startTime`), `reducedPmValues` (bool, informational), `maxNeigh` (int, 8), `runId` (string, e.g. `"<epochMs>-<pid>"`), `emitter:{ns3Sha, oranInterfaceSha}` |
| `sample`: one per node per period, **merged** DU+CU-UP+CU-CP | `type:"sample"`, `v:1`, `nodeId`, `seq` (int64, 0-based per run, incremented for every **built** sample including dropped ones), `simTimeNs` (int64, `Simulator::Now()` at build), `ipcDropped` (int64, cumulative drops for this node before this sample), `cell:{du:{…}, cuUp:{…}, cuCp:{…}}`, `ues:[{imsi, du:{…}, cuUp:{…}, cuCp:{…, l3:{servCellId, servSinrDb, servSinr3gpp, neigh:[{cellId, sinrDb, sinr3gpp}]≤8}}}]` (UEs sorted by IMSI; `neigh` in ns-3's own sort order) |
| `bye`: at simulator end (optional; EOF is equivalent) | `type:"bye"`, `v:1`, `nodeId`, `lastSeq`, `built`, `sent`, `droppedDisconnected`, `droppedBackpressure` |

- **Keys inside sections** are the exact strings ns-3 passes to `AddItem`, for example `"TB.TotNbrDl.1.UEID"`. This lets P4 just swap the asn1c-backed `MeasurementItemList` storage for a `std::map<string, variant<int64,double>>` (K5).
- **Container values and file-logging-only values** use their plain C++ names: `dlAvailablePrbs`, `ulAvailablePrbs`, `qci`, `dlPrbUsage`, `ulPrbUsage`, `pDCPBytesUL`, `pDCPBytesDL`, `numActiveUes`, `meanRrcUes`, `txPdcpPduLteRlc`, … Values are int64, double or `null`. A disabled section (for example `--e2cuUp=false`) is omitted.
- **Full-set rule.** The emitter captures every value the builders compute in **both** the ASN.1 branch and the CSV branch, regardless of `reducedPmValues`. Two LTE examples:
  - the per-UE serving SINR exists only in the CSV branch (`LTE:1400-1409`);
  - some CU-UP columns exist only in the CSV header (`LTE` ~:963-973).

**Main risk.** P4 misses a CSV-only value, or gets "per-period vs cumulative" wrong, which breaks the INTEGER/REAL choice. **Mitigation:** the M4 gate asserts that every `src` pointer in the metric map (Q5) resolves in at least one emitted sample of that kind.

**Checkability.** The trace is the M6 truth; `seq` gaps plus `ipcDropped` give M7 its drop accounting. v1 reserves the `type` values `control`, `controlAck` and `step` for M8 RC and lock-step, so M8/M9 stay additive.

---

## Q2. Transport and placement: (a) one Docker container per agent

**Recommendation:**
- **Image:** `ns3-e2-agent:<testbed-sha>`.
- **Run command:** `docker run -d --init --restart always --name ns3-e2-agent-<cellId> --label ns3e2.agent=1 --label ns3e2.nodeId=<cellId> --log-opt max-size=20m --log-opt max-file=3 -p 127.0.0.1:<38470+cellId>:<38470+cellId> -e … ns3-e2-agent:<sha>`.
- **Network:** default bridge, so each agent gets its own netns and IP. No host networking, no extra capabilities.
- **ns-3 → agent:** TCP to `127.0.0.1:(E2AgentPortBase + cellId)`, base 38470.
  - These are the same numbers as the old `local_port = 38470 + cellId` (MWH:2191-2203), so the docs map one-to-one.
  - New knobs: MmWaveHelper attribute `E2AgentPortBase` (default 38470) and a scenario-zero CLI `--e2AgentHost` (default 127.0.0.1).
  - `e2TermIp` and `E2LocalPort` stay accepted and log "ignored in IPC mode", so old invocations don't hit the unknown-arg exit.
- **Agent → e2term:** the host resolves the SCTP Service once, at agent start.
  - Use NIST's own selector (`NRT/install_scripts/run_e2sim_and_connect_to_ric.sh:95,106-108`), but with `kubectl -n ricplt get svc -o json`. Select the single Service whose name starts with `service-ricplt-e2term-sctp`, assert exactly one match, and read `.spec.clusterIP` and its SCTP port into `E2_TERM_ADDR` / `E2_TERM_PORT`.
  - The ClusterIP survives e2term pod deletes because the Service object is untouched, so M7 needs no IP change.
- **Restart behaviour:**
  - Keep `--restart always` (K7). Docker's restart backoff is 100 ms doubling up to 60 s, reset only after 10 s of uptime (MOBY `restartmanager.go:12-14`, `:66-78`).
  - Therefore the agent must **never exit on "cannot connect yet"** (Q6). Otherwise, reconnect after e2term returns can lag by up to a minute.
  - stop-all uses `docker rm -f` by label, so nothing comes back after a reboot at a snapshot boundary.

**Why not (b) pods:**
- k8s does not see Docker's image store, so every rebuild would need an import into containerd.
- Pod IPs change on restart, so ns-3 would need one Service per agent.
- kubelet's CrashLoopBackOff caps at 5 min, not 1 min.
- The M2/K10 probe and the plan's docker0 capture rule validate the **Docker** path, not pod-to-Service.
- The only gain is cluster DNS, which a host-resolved ClusterIP already makes unnecessary.

**Why not UDS:** it needs bind-mounted socket directories and permission handling across restarts. TCP is debuggable with `nc`.

**Main risk:** five concurrent Docker-bridge → ClusterIP SCTP associations, and NAT state across restarts (R2). Mitigated by ephemeral source ports (Q6) and the K10 probe.

**Checkability:**
- A capture on docker0 shows each agent's own IP before NAT (plan K10). Use BPF `ip proto 132` so the IPC TCP traffic, which also crosses docker0, stays out of the pcap.
- `docker inspect -f '{{.RestartCount}}'` per agent is M7 evidence.
- Nothing touches the host, so M9 stays scriptable.

---

## Q3. Agent source home and build: keep K1's home, change K1's mechanism

**Recommendation: change K1 from (a) "whole-file patch of `encode_e2apv1.cpp`/`e2sim.cpp`" to (b) "agent-owned loop".** This disagrees with the earlier kongming recommendation. The evidence:

- **`run_loop` cannot be reused whatever we patch:**
  - it connects and calls `exit(1)` on failure (`E2SIM/src/SCTP/e2sim_sctp.cpp:188-191`);
  - it hard-codes `OID123` (`E2SIM/src/base/e2sim.cpp:137`);
  - it then blocks in an rx loop (`e2sim.cpp:198-207`) that dispatches subscriptions synchronously to a plain function-pointer callback (`e2sim.hpp:30`; `src/messagerouting/e2ap_message_handler.cpp:103-107`) and frees the PDU on return (`:198`);
  - kpm_sim's callback never returns (`kpm_callbacks.cpp:655`).
- **RICsubscriptionDelete is not dispatched at all.** It falls into `default` (`e2ap_message_handler.cpp:194-196`). NIST's patched handler only adds RICcontrol logging (`NRT/install_patch_files/e2-interface/e2sim/src/messagerouting/e2ap_message_handler.cpp:194-213`). No delete-response generator exists in `encode_e2apv1.cpp`.
- **The library send and receive paths would crash the agent.** Send calls `exit(1)` on −1 and has no `MSG_NOSIGNAL` (`e2sim_sctp.cpp:233-243`); receive calls `exit(1)` on −1 (`:275-279`); an inbound decode failure exits (`e2ap_message_handler.cpp:39-45`).
- **A library patch would also change kpm_sim's image.** `install_e2sim.sh:54-66` builds both from the same tree, so the patch would put the M2/M3 reference at risk for no benefit.

**What the agent reuses unchanged:**
- `encoding::generate_e2apv1_setup_request_parameterized` (`encode_e2apv1.cpp:158`);
- `generate_e2apv1_subscription_response_success` (`:649`);
- `generate_e2apv1_indication_request_parameterized` (`:891`);
- `generate_e2apv1_service_update` (`:98`);
- `get_function_id_from_subscription` (`:64`);
- the E2AP and E2SM-KPM v3 asn1c types and APER codecs (`E2SIM/asn1c/`).

**In-place post-edits of generated PDUs (landmines found in this review):**
1. **E2SetupRequest identity.** Overwrite the 3-byte PLMN and 4-byte gNB-ID buffers the generator allocated (`encode_e2apv1.cpp:161-174`). Keep `bits_unused = 3`, the 29-bit layout e2term already parses for kpm_sim. Edit in place; never swap in your own pointers, so `ASN_STRUCT_FREE` stays valid.
2. **Subscription response RANfunctionID.** The generator hard-codes `RANfunctionID = 147` (`:668`). Set it to the request's ID.
3. **Never pass rejected actions.** The not-admitted branch writes the reject list into the **admitted** IE's union and appends the not-admitted IE once per action (`:719`, `:733`), which corrupts the PDU. Option A admits every action anyway; non-REPORT actions are only logged.
4. **E2SM message size.** The indication generator allocates a fixed 8192-byte buffer and copies `message_length` into it (`:958`, `:969`). An E2SM message over 8192 bytes overflows the heap, so the agent enforces a cap (Q4).
5. **Registration buffer.** `run_loop` writes a NUL one byte past each registered RAN-function buffer (`e2sim.cpp:145-147`). The agent does not use it, but anyone tempted to should allocate `size+1`.

**Agent-owned code (each file under 200 lines, per the repo rule):**
- the RICsubscriptionDeleteResponse builder;
- the E2SM-KPM RANfunction-Description, IndicationHeader-Format1, and IndicationMessage-Format1/Format2 encoders.

NIST's `encode_kpm.cpp` is not reusable:
- its 9 measurement names are fixed (`:30-40`) and its OID is `OID123` (`:45-47`);
- its TimeStamp is the ASCII string `"20200613"` (`:223-227`);
- every record is integer 1 with `incompleteFlag = true` (`:250-278`).

**Threads: one thread, one `poll()` loop.**
- File descriptors: the SCTP association, the IPC listen socket, the IPC client socket, and a timerfd for timeouts and stats.
- No `E2Sim` object and no use of the global `client_fd` (`e2sim.cpp:36`). Do not define a symbol with that name in the agent, or it clashes at link time.
- Ordering is deterministic: a subscription processed before a sample always applies to that sample, and no locks are needed.
- SCTP sends use `MSG_NOSIGNAL|MSG_DONTWAIT`. On `EAGAIN` the agent drops the sample and counts it, so it never blocks the IPC reader.
- Encoding takes well under 1 ms per sample. A second thread would add races without adding throughput.

**Layout (Testbed fork, branch `dev/l-release-nist180`):**
```
RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/
  CMakeLists.txt                # add_subdirectory(asn1c) + link e2sim (same shape as e2sm_examples/kpm_e2sm/CMakeLists.txt)
  Dockerfile                    # derived from e2sim/Dockerfile_kpm
  src/  main  e2-session  e2ap-dispatch  subscription-table  ipc-server  kpm-encoder  metric-map  sctp-socket  (.hpp/.cpp)
  schema/ ns3-e2-ipc.v1.md  ns3-e2-ipc.v1.schema.json  metric-map.v1.json
  tests/ codec-probe.cpp        # R1 probe, kept as the agent selftest
install_scripts/install_ns3_e2_agent.sh
install_scripts/run_ns3_e2_agents.sh   install_scripts/stop_ns3_e2_agents.sh
```

K1's `install_patch_files/e2-interface/e2sim/e2sm_examples/<agent>/` would also work. I prefer a dedicated directory because `install_patch_files` holds whole-file replacements of upstream files, which NIST's own sync script rewrites by name (`NRT/additional_scripts/apply_changes_to_patch_files.sh:101-111`). New code is not a replacement. The stakes are low.

**Build (`install_ns3_e2_agent.sh`):**
- Assert `git -C e2-interface rev-parse HEAD` = `da6f82f2…`. Run after `install_e2sim.sh`, so the tree matches the reference, including NIST's handler copy (`install_e2sim.sh:54`).
- Copy `ns3_e2_agent/` to `e2-interface/e2sim/e2sm_examples/ns3_e2_agent/`.
- Build with `docker build --build-arg CONTAINER_PULL_REGISTRY=nexus3.o-ran-sc.org:10002 -f e2sm_examples/ns3_e2_agent/Dockerfile -t ns3-e2-agent:<testbed-sha> .` from `e2-interface/e2sim`. This is the same context and registry NIST uses (`install_e2sim.sh:59-66`). Record the image ID.

**Dockerfile changes compared with `Dockerfile_kpm`:**
- Replace the unpinned `git clone nlohmann_json_release` (HEAD of a third-party repo, `Dockerfile_kpm:79-81`) with jammy's `nlohmann-json3-dev` apt package.
- Use `ENTRYPOINT ["/usr/local/bin/ns3-e2-agent"]`, so the agent is PID 1 under `--init`. NIST's `CMD sleep` + `docker exec` pattern (`install_scripts/revise_e2sim_dockerfile.sh:57-65`; `run_e2sim_and_connect_to_ric.sh:129`) hides exits from the restart policy.
- `COPY` the metric map to `/etc/ns3-e2-agent/`.

**Agent environment** (all have defaults except the first three):

| Env | Default | Meaning |
|---|---|---|
| `E2_NODE_ID` | (required) | ns-3 cellId; must equal `hello.nodeId` |
| `E2_NODE_KIND` | (required) | `gnb`\|`enb`; selects the metric-map section; must equal `hello.kind` |
| `E2_TERM_ADDR` | (required) | e2term SCTP Service ClusterIP (resolved by the host) |
| `E2_TERM_PORT` | 36422 | |
| `E2_PLMN` | `00101` | MCC 001 / MNC 01, written as BCD `00 F1 10` |
| `E2_GNB_ID` | `=E2_NODE_ID` | 29-bit value, left-aligned (`bits_unused = 3`) |
| `E2_RAN_FUNC_ID` | 2 | |
| `E2_KPM_OID` | `1.3.6.1.4.1.53148.1.3.2.2` | Used for both the E2AP RANfunctionOID and `ranFunction-E2SM-OID` |
| `E2_SCTP_SRC_PORT` | 0 (ephemeral) | `36422` reproduces NIST's behaviour; fallback only |
| `E2_CONNECT_HOLDOFF_S` | 8 | Wait before the first connect after every (re)start |
| `E2_CONNECT_RETRY_S` / `E2_CONNECT_TIMEOUT_S` | 2 / 3 | In-process retry; never exit on a connect failure |
| `E2_SETUP_TIMEOUT_S` | 10 | No E2SetupResponse in time → `exit(3)` |
| `E2_IPC_PORT` | `38470 + E2_NODE_ID` | TCP listen port inside the container |
| `E2_METRIC_MAP` | `/etc/ns3-e2-agent/metric-map.v1.json` | |
| `E2_UES_PER_IND` | 4 | UEs per Format-2 indication |
| `E2_MAX_E2SM_BYTES` | 7000 | Split the UE chunk if the encoded message is larger |
| `E2_STATS_INTERVAL_S` | 5 | One JSON stats line to stdout |

**Main risk:** hidden behaviour in the reused generators; two bugs are already known. **Mitigation in M5:** decode the agent's E2SetupRequest and kpm_sim's (from the golden pcap) to XER and diff them. They must differ only in GlobalE2node_ID, RANfunctionOID and ranFunctionDefinition.

**Checkability:**
- No NIST file changes, so the reference node is untouched.
- The image tag equals the Testbed SHA, so M9 rebuilds from pins.
- M8 adds a second RAN function to the same vector the setup generator already accepts (`encode_e2apv1.cpp:158`), plus a `control` IPC type.

---

## Q4. E2SM content (verified against kpimon's code)

**4.1 RAN function ID = 2. Verified.**
- kpimon uses `funcId = int64(2)` (KPC:46) and subscribes with it (KPC:443).
- `initializeNode` skips nodes that don't advertise it (KPC:1027-1037).
- `encode_action_format1`/`format3` hard-code `RanFunctionId == 2` (KPC:194, :251).
- NIST's `RAN_FUNC_ID` sed rewrites only the first `funcId = int64(N)` (`install_xapp_kpi_monitor.sh:178-182`). So any other ID silently breaks action encoding.
- ns-3's 200 (MW:638) is retired.

**4.2 RAN function definition (E2SM-KPM RANfunction-Description):**
- **`ranFunction-ShortName` must be exactly `"ORAN-E2SM-KPM"`.**
  - Wireshark picks the E2SM dissector by an exact match on the short name (WS template:153, :272-283; hook in `e2ap.cnf:287-294`).
  - ns-3's old `"ORAN-WG3-KPM"` would never be dissected, which would sink the M6 "tshark decodes as v3" check.
  - kpm_sim already uses the right name (`encode_kpm.cpp:45`).
- **Other name fields:**
  - E2SM-OID `"1.3.6.1.4.1.53148.1.3.2.2"`;
  - Description `"ns-O-RAN KPM map v1 <sha8 of metric-map>"`, PrintableString-legal, which puts the map version on the wire for M5;
  - Instance 1.
- **OID: nothing in the chain is known to check it.**
  - kpimon never reads it: it is only a struct field (`kp-nist/control/types.go:12`) and is unused in KPC.
  - Wireshark uses the OID only to choose among KPM versions, and falls back to the one registered, kpm_v3 (template:455-469, :737).
  - Wireshark's own KPM v3 OID string has a typo, `"1.2.6.1.4.1.53148.1.3.2.2"` (template:663, :678). Expect a harmless version expert-info and do not chase it.
  - e2term, e2mgr and submgr: **(belief)** they do not validate the OID, since kpm_sim's `OID123` passes M2/M3.
  - The real OID is the honest v3 marker. `E2_KPM_OID=OID123` is the fallback if M5 rejects it.
- **Event trigger style:** `{1, "Periodic Report", format 1}`.
- **Report styles, exactly two:**
  - `{type 1, "E2 Node Measurement", actionFormat 1, header 1, message 1, measInfo = CELL list}`;
  - `{type 3, "Condition-based, UE-level E2 Node Measurement", actionFormat 3, header 1, message 2, measInfo = UE list}`.
  - Every item carries measName plus measID, with stable IDs from the map.
- **Why two styles:**
  - kpimon builds its cell list from the style with ActionFormat 1 and its UE list from ActionFormat 3 (KPW:60-100).
  - It builds its single format-3 action from the UE list with style type 3 (KPW:298-301).
  - An empty UE list would make kpimon's Format-2 parser divide by zero, and the panic would kill the goroutine (KPC:842). The map must never produce one.
- **Names must be PrintableString-legal.**
  - MeasurementTypeName's permitted alphabet excludes `_` (`E2SIM/asn1c/MeasurementTypeName.c:3-11`, check at `:57`).
  - APER would still encode `_`, because the PER alphabet range is 32..122 (`:84-86`), but `asn_check_constraints` and strict decoders flag it.
  - So `…_Filter` names drop the 3GPP filter placeholder (filters are KPM labels; option A has none), and `.UEID` suffixes drop too (UE identity is Format 2's job).

**4.3 Header (IndicationHeader-Format1):**
- **`colletStartTime`:** 8 bytes in RFC 5905 NTP-64 form, i.e. be32 seconds since 1900-01-01 followed by be32 fraction of 2^-32 s.
  - Value: `simStartEpochMs + max(0, simTimeMs − periodMs)`, the start of the collection window, at ms precision.
  - **(belief)** KPM v3 defines TimeStamp as the RFC 5905 64-bit format; v2 used its first 4 bytes, hence SIZE(4).
  - ns-3's old `htobe64(epoch-ms)` (fact pack §5) and kpm_sim's ASCII string are both non-conformant. M3's "8-byte" baseline proves only the size.
- **Optional fields:** `senderName "ns3-cell-<id>"`, `senderType "simulator"`, `vendorName "ns-O-RAN"`.
- **What kpimon does with the header:**
  - It decodes the header, checks only that it is Format 1, and discards the fields (KPC:711-746).
  - A header decode failure drops the whole indication (KPC:715-717).
  - Influx points get `time.Now()` (KPC:978, :999).
  - So the header never affects M6 values. What matters is the harness's "clean RC_OK" rule: all 8 octets consumed.

**4.4 Message formats under option A, and what kpimon writes (verified):**

| ns-3 data | E2SM encoding | kpimon behaviour | Influx result |
|---|---|---|---|
| Cell: DU + CU-UP + CU-CP merged | **Format 1**: `measData` = 1 item; `measRecord` in exact CELL-list order, `noValue` where missing; `measInfoList` with measID + `noLabel`; `granulPeriod` = periodMs; no `incompleteFlag` | Loops over measData items (KPC:770). **Drops the whole message** if the record count ≠ cell-list length (:790-793). INTEGER → `int32` (:803), REAL → `float64` (:807), `noValue` → field omitted (:808-810) | One point in `cellMetrics`; fields = cell-list names; no tags; `time.Now()` (:999-1004) |
| Per-UE | **Format 2**: `measData` = 1 item (kpimon reads only `[0]`, :831). `measRecord` is metric-major: for each metric in the UE list, for each UE in the chunk (sorted by IMSI), one value (:864). `measCondUEidList`: one item per UE-list metric, with `measType` = measID, `matchingCond` = `[measLabel{noLabel}]`, `matchingUEidList` = `[gNB-UEID{amf-UE-NGAP-ID = imsi, GUAMI fixed}]` | `no_of_ue = records / UE-list length` (:842-843); one point per UE (:846-888); same int32 cast (:871) | Points in `UeMetrics`; no tags |

- **Both formats go under the node's single subscription**, using its lowest admitted action ID. kpimon dispatches on message format, not on action (KPC:764, :823). That is how cell rows reach Influx under option A:
  - kpimon creates format-1 actions only for cells advertised over F1 (KPC:327-367, fed from its localhost:8090 F1 server at :1097-1115);
  - e2sim advertises only an NG component (`encode_e2apv1.cpp:255`);
  - so kpimon sends 0 format-1 actions and 1 format-3 action (KPC:390-402).
- **Flag for later:** Format 1 under a format-3 action is a documented option-A non-conformance. Under option B with stock kpimon, cell rows would therefore disappear.
- **Size cap.**
  - Hard limit: the E2SM message must stay ≤ 8192 bytes, or the generator overflows (Q3 landmine 4).
  - Agent rule: encode at most `E2_UES_PER_IND` UEs. If the result is over `E2_MAX_E2SM_BYTES` (7000), halve the chunk. Each sample then produces one cell indication plus ⌈n/4⌉ UE indications per subscription.
  - kpimon's RMR `maxSize` of 2072 (`kp-nist/deploy/config.json:57`) is very likely a default, not a cap, because RMR master reallocates for larger messages (RMR :265-270). kpimon's pinned RMR version is unverified (R3).
- **int32 and sign.**
  - Record INTEGER is unsigned `(0..4294967295)` (`E2SIM/asn1c/MeasurementRecordItem.c:48`, `.h:38`), and kpimon casts it to int32.
  - So INTEGER is safe only for 0..2^31−1: IDs, bounded per-period counts, percentages, enums.
  - Everything else is REAL: volumes, bytes, anything cumulative, throughput, delay, and SINR in dB (can be negative).
  - Agent guard: an out-of-range INTEGER is encoded as `noValue` and counted in `int32Overflow`; M6 asserts that count is 0.
- **REAL exactness (belief).** asn1c REAL is base-2 binary, exact for finite doubles. kpimon reads it as float64 and Influx stores float64, and every decimal hop uses shortest round-trip, so M6 can demand 0 ULP. kpm_sim never sends REAL, so this path is untested until R1.
- **Wire compatibility: v3 encoder (e2sim) to v2-plus-patches decoder (kpimon).**
  - The asn1c structs differ only by v3 **extension additions**: `MeasurementCondUEidItem.matchingUEidPerGP`, `UEID-GNB.globalNG-RANNode-ID`, `MeasurementInfo-Action-Item.binRangeDef`, and `MeasurementLabel.ssbIndex/nonGoB/mIMO` (compare `E2SIM/asn1c/*.h` with the KPH headers).
  - These are struct-identical: Format1, Format2, MeasurementDataItem, MeasurementRecordItem, MatchingCondItem (+Choice), UEID, Header-Format1, RANfunction-Description and RIC-ReportStyle-Item.
  - The PER constraints of MeasurementTypeName and MeasurementTypeID are identical (`E2SIM/asn1c/MeasurementTypeName.c:84-86` vs `KPH/lib/MeasurementTypeName.c:89-91`; `MeasurementTypeID.c:40-42` vs `:45-47`).
  - **Rule: the agent never sets a v3 extension addition.**

**4.5 Correlation KPIs.**
- Both lists start with `ns3.nodeId`, `ns3.simTimeMs` (= ⌊simTimeNs/1e6⌋) and `ns3.seq`, all INTEGER.
- The UE list adds `ns3.imsi` (INTEGER) at position 4. Without it, the UE rows of one sample are indistinguishable, because kpimon ignores UEIDs.
- **Join keys:**
  - `cellMetrics` on `(ns3.nodeId, ns3.seq)`;
  - `UeMetrics` on `(ns3.nodeId, ns3.seq, ns3.imsi)`;
  - both inside the run's wall-clock window (hello → bye). `simTimeMs` is a cross-check.
- No run-ID KPI is needed: kpimon stamps `time.Now()`, so the window separates runs.

**Main risk:** R1. **Checkability:** kpimon caches exactly the definition's lists per node (KPC:1040-1111). So M5 can decode the definition from the E2Setup with kpimon's own library and know in advance what M6 will see.

---

## Q5. Metric-mapping table (K5)

**Where it lives:** `ns3_e2_agent/schema/metric-map.v1.json` in the Testbed fork.
- It is copied into the image, and the agent logs its sha256 at start and puts sha8 into `ranFunction-Description`.
- The M6 gate reads the **same file** from the Testbed clone at the `pins.conf` SHA and asserts the sha matches the one on the wire (from E2Setup) or in the agent log.
- ns-3 does not read the map; it emits native names only. The M4 gate checks that every `src` resolves.

**Row schema:** `{kind, list:"cell"|"ue", order, measId, kpm, type:"INTEGER"|"REAL", scope:"sample"|"ue", src (JSON pointer), xform:"none"|"ns_to_ms_floor", unit, origin (file:line), legacyName}`.

**Naming rules:**
- Keep the ns-3/3GPP name; drop `.UEID` and `_Filter`.
- When two sections collide in the merged sample, CU-UP keeps the 3GPP name and the DU copy gets an `ns3.du.` prefix. This happens for `QosFlow.PdcpPduVolumeDL_Filter.UEID`: DU per-UE `macVolume` (OI mmwave helper:89) versus CU-UP per-UE `txPdcpPduBytesNrRlc` (:43).
- Unnamed container or CSV values become `ns3.<section>.<field>`, unless a TS 28.552 name fits exactly (`RRU.PrbAvailDl/Ul`, `RRU.PrbTotDl/Ul`, `RRC.ConnMean`).
- Types marked **P4** need P4 to confirm per-period vs cumulative. Default to REAL if unsure.

**gNB (`kind:"gnb"`), CELL list (Format 1):**

| measId | KPM name | type | src (sample scope) | origin |
|---|---|---|---|---|
| 1–3 | `ns3.nodeId`, `ns3.simTimeMs`, `ns3.seq` | INTEGER | `/nodeId`, `/simTimeNs` (ns_to_ms_floor), `/seq` | — |
| 4–5 | `TB.TotNbrDl.1`, `TB.TotNbrDlInitial` | INTEGER | `/cell/du/<name>` | OI mmwave helper:130-131 |
| 6–8 | `TB.TotNbrDlInitial.Qpsk` / `.16Qam` / `.64Qam` | INTEGER | same | :134-136 |
| 9 | `RRU.PrbUsedDl` | INTEGER | same (ns-3 already applies `ceil`) | :137 |
| 10 | `TB.ErrTotalNbrDl.1` | INTEGER | same | :141 |
| 11 | `QosFlow.PdcpPduVolumeDL` | REAL | `/cell/du/QosFlow.PdcpPduVolumeDL_Filter` | :142 |
| 12–17 | `CARR.PDSCHMCSDist.Bin1`…`Bin6` | INTEGER | same | :143-148 |
| 18–24 | `L1M.RS-SINR.Bin34/46/58/70/82/94/127` | INTEGER | same | :149-155 |
| 25 | `DRB.BufferSize.Qos` | REAL | same | :156 |
| 26 | `DRB.MeanActiveUeDl` | INTEGER | same | :159 |
| 27–28 | `RRU.PrbAvailDl`, `RRU.PrbAvailUl` | INTEGER | `/cell/du/dlAvailablePrbs`, `ulAvailablePrbs` | MW:1376-1377, 1412-1413 |
| 29–30 | `RRU.PrbTotDl`, `RRU.PrbTotUl` (%) | INTEGER | `/cell/du/dlPrbUsage`, `ulPrbUsage` | MW:1379, 1420-1422 |
| 31 | `ns3.du.qci` | INTEGER | `/cell/du/qci` | MW:1420 |
| 32 | `ns3.cuCp.numActiveUes` | INTEGER | `/cell/cuCp/numActiveUes` | MW ~:1057 (`FillCuCpValues(ueMap.size())`) |
| 33 | `RRC.ConnMean` | INTEGER | `/cell/cuCp/meanRrcUes` | MW:931-935, :947 (CSV only) |

**gNB UE list (Format 2):**

| measId | KPM name | type | src (UE scope unless noted) | origin |
|---|---|---|---|---|
| 1001–1003 | `ns3.nodeId`, `ns3.simTimeMs`, `ns3.seq` | INTEGER | sample scope | — |
| 1004 | `ns3.imsi` | INTEGER | `/imsi` | — |
| 1005–1009 | `TB.TotNbrDl.1`, `TB.TotNbrDlInitial`, `.Qpsk`, `.16Qam`, `.64Qam` | INTEGER | `/du/<name>.UEID` | OI mmwave helper:83-87 |
| 1010 | `TB.ErrTotalNbrDl.1` | INTEGER | same | :88 |
| 1011 | `ns3.du.QosFlow.PdcpPduVolumeDL` | REAL | `/du/QosFlow.PdcpPduVolumeDL_Filter.UEID` | :89 |
| 1012 | `RRU.PrbUsedDl` | INTEGER | same | :90 |
| 1013–1018 | `CARR.PDSCHMCSDist.Bin1`…`6` | INTEGER | same | :91-96 |
| 1019–1025 | `L1M.RS-SINR.Bin34`…`Bin127` | INTEGER | same | :97-103 |
| 1026 | `DRB.BufferSize.Qos` | REAL | same | :104 |
| 1027 | `DRB.UEThpDl` | REAL | same (always sent) | :110 |
| 1028 | `QosFlow.PdcpPduVolumeDL` | REAL | `/cuUp/QosFlow.PdcpPduVolumeDL_Filter.UEID` | :43 |
| 1029 | `DRB.PdcpPduNbrDl.Qos` | REAL (P4) | `/cuUp/DRB.PdcpPduNbrDl.Qos.UEID` | :46 |
| 1030–1031 | `DRB.EstabSucc.5QI`, `DRB.RelActNbr.5QI` | INTEGER | `/cuCp/<name>.UEID` | :180-181 |
| 1032–1034 | `ns3.l3.servCellId` (INTEGER), `ns3.l3.servSinrDb` (REAL), `ns3.l3.servSinr3gpp` (INTEGER) | — | `/cuCp/l3/…` | MW:972-982 |
| 1035–1058 | `ns3.l3.nbr<k>.cellId` (INTEGER), `.sinrDb` (REAL), `.sinr3gpp` (INTEGER), k = 1..8, padded with `noValue` | — | `/cuCp/l3/neigh/<k-1>/…` | MW:1004-1040; `E2SM_REPORT_MAX_NEIGH = 8` (`mmwave-enb-net-device.h:71`) |

The `legacyName` for rows 1032–1058 is `HO.SrcCellQual.RS-SINR.UEID` / `HO.TrgtCellQual.RS-SINR.UEID`, sent as `valueRRC` (OI mmwave helper:184-185). KPM v3 records allow only integer, real or noValue (`MeasurementRecordItem.h:26-29`), so the L3 structure must be flattened. Eight slots match ns-3's own CSV width (MW:1037-1040).

**eNB (`kind:"enb"`, the LTE CU-UP + CU-CP; no DU):**

| list | measId | KPM name | type | src | origin |
|---|---|---|---|---|---|
| cell | 1–3 | correlation KPIs | INTEGER | sample scope | — |
| cell | 4 | `DRB.PdcpSduDelayDl` | REAL | `/cell/cuUp/DRB.PdcpSduDelayDl` | OI lte helper:69 |
| cell | 5–6 | `ns3.cuUp.pDCPBytesUL`, `ns3.cuUp.pDCPBytesDL` | REAL | `/cell/cuUp/pDCPBytesUL`, `pDCPBytesDL` | lte helper:77-78; LTE:1270 |
| cell | 7–8 | `ns3.cuCp.numActiveUes`, `RRC.ConnMean` | INTEGER | `/cell/cuCp/numActiveUes`, `meanRrcUes` | LTE:1375; CSV |
| ue | 1001–1004 | correlation KPIs + `ns3.imsi` | INTEGER | — | — |
| ue | 1005–1008 | `DRB.PdcpSduVolumeDl` (REAL), `Tot.PdcpSduNbrDl` (REAL, P4), `DRB.PdcpSduBitRateDl` (REAL), `DRB.PdcpSduDelayDl` (REAL) | — | `/cuUp/<ns-3 name>` | lte helper:48-57 |
| ue | 1009–1012 | `ns3.cuUp.txPdcpPduLteRlc`, `ns3.cuUp.txPdcpPduBytesLteRlc`, `QosFlow.PdcpPduVolumeDL`, `DRB.PdcpPduNbrDl.Qos` | REAL (P4) | `/cuUp/…` (CSV-only today) | LTE ~:963-973 CSV header |
| ue | 1013–1014 | `DRB.EstabSucc.5QI`, `DRB.RelActNbr.5QI` | INTEGER | `/cuCp/<name>.UEID` | lte helper:96-97 |
| ue | 1015–1017 | `ns3.l3.servCellId`, `ns3.l3.servSinrDb`, `ns3.l3.servSinr3gpp` | INT / REAL / INT | `/cuCp/l3/…` | LTE:1400-1409 (CSV-only) |

**Gate lint for the map:**
- each `kpm` name has exactly one type across all kinds (an Influx field-type conflict would make kpimon's write fail silently, see "What to avoid");
- all names are PrintableString-legal;
- no name overlaps kpm_sim's 9 names (`encode_kpm.cpp:30-40`) that already sit in `cellMetrics` from M3;
- measIds are unique and stable.

---

## Q6. Robustness (K7): crash-only on association loss, in-process connect retry, hold-off, ephemeral port

**Agent state machine:**

1. **START → HOLDOFF.** Wait `E2_CONNECT_HOLDOFF_S` = 8 s.
2. **CONNECTING.** Use a fresh socket per attempt, an ephemeral source port and a non-blocking connect with a 3 s timeout. Retry every 2 s, forever.
3. **SETUP_SENT.** If no response arrives within 10 s, `exit(3)`.
4. **READY.** The subscription table starts empty. Messages are handled as follows:
   - **RICsubscriptionRequest for function 2:** admit all actions; store `{requestorId, instanceId, actionIds}`; reply through the generator with the 147 fix. A duplicate `(requestor, instance)` replaces the old entry. Other function IDs are logged and get no reply in v1.
   - **RICsubscriptionDeleteRequest:** remove the entry (idempotent) and reply with a DeleteResponse.
   - **RICserviceQuery:** reply with a RICserviceUpdate, mirroring e2sim (`e2ap_message_handler.cpp:150-162`).
   - **ErrorIndication, Reset, RICcontrol:** log only.
   - **An undecodable inbound PDU:** log, count and keep running. e2sim exits here (`:39-45`), which turns one bad message into an association loss.
5. **Association loss** means recv returns 0 or −1, send fails with EPIPE/ECONNRESET, an `SCTP_COMM_LOST` notification arrives, or heartbeats fail. The agent prints its final stats and calls `exit(2)`. Docker restarts it (RestartCount + 1), and it goes back to HOLDOFF.
   - This is crash-only by design: a new process means an empty table and a fresh E2Setup.
   - **(belief)** That is what E2AP expects after a re-setup, and it matches submgr dropping a node's subscriptions on DISCONNECTED (plan K7).
6. **SCTP options:** `SCTP_NODELAY`; heartbeat interval 5 s and path max retransmissions 3, so a silently vanished peer is detected in about 20 s instead of minutes.

**Why the 8 s hold-off:** kpimon re-subscribes only if one of its 5 s polls sees the node not CONNECTED (KPC:1146-1189); the `subscribed` flag is cleared only when a poll misses the node (:1178-1185). An agent restart faster than 5 s leaves kpimon believing it is subscribed to a subscription that submgr has dropped. The node then shows CONNECTED but sends nothing. 8 s exceeds the 5 s poll plus propagation.

**Why an ephemeral source port (belief, standard netfilter semantics):**
- A flow's NAT binding is fixed at its first packet and reused for as long as the conntrack entry lives.
- NIST binds source port 36422 (`e2sim_sctp.cpp:175-184`). A reconnect from the same 5-tuple (container IP:36422 → ClusterIP:36422) while the old entry lives can be DNAT'd to the dead e2term pod IP.
- A fresh port per attempt makes every association a new flow with a fresh DNAT. It also removes the K10 port-collision question by construction.
- `E2_SCTP_SRC_PORT=36422` remains as a fallback.

**Dropped samples on the agent side:** samples that arrive before READY or while no subscription exists are dropped and counted (`droppedE2Down`, `droppedNoSub`). This is normal until kpimon's first poll.

**IPC server rules:**
- One client at a time; a second concurrent connection is closed with a log line.
- A hello mismatch (`v` major, `nodeId` or `kind`) closes the connection and increments `helloRejected`; the agent keeps running.

**ns-3 emitter requirements (for P4):**
- Non-blocking TCP with `TCP_NODELAY`. Every send uses `MSG_NOSIGNAL|MSG_DONTWAIT`.
- Pending buffer up to 4 MiB. On overflow, drop the whole sample and count `droppedBackpressure`.
- On error: discard any partial line, close, count `droppedDisconnected`, then reconnect with a non-blocking connect checked at the next emit. Backoff is 0.1 s doubling to a 5 s cap, measured on `CLOCK_MONOTONIC`, never sim time.
- Send `hello` on every connect.
- **Write and flush the trace line before any send attempt**, so the trace also contains dropped samples. Send `bye` at the end.
- Schedule like the file-logging mode: first build at +500 µs, then every E2Periodicity (LTE:984-987, :1491-1500). Never wait for a subscription.

**What M7's e2term pod delete should show on docker0, per node** (record each timestamp):
1. The old association ends with SHUTDOWN or ABORT from e2term, or with heartbeat timeouts if the pod vanished silently.
2. A Docker `restart` event.
3. About 8 s later, an INIT from a **new** source port. While the Service has no ready endpoint, expect no reply or an ICMP error, with retries every 2 s.
4. INIT-ACK and COOKIE, then E2SetupRequest (same global ID), then E2SetupResponse with RAN function 2 accepted.
5. Within 5 s (kpimon's poll), a **RICsubscriptionRequest with a new RIC instance ID**, then its response.
6. RICindications resume once ns-3's IPC reconnects (at most 5 s of backoff).

On the ns-3 side, the trace `seq` stays continuous, and `ipcDropped` grows during the outage, then stays flat. The expected bound is detection time + 8 s + e2term readiness + 5 s + 5 s.

---

## Q7. Lifecycle: node set, IDs, discovery, hygiene

**Node-set function.** One source of truth, `scripts/lib/e2-node-set.sh`, used by both the agent launcher and the ns-3 launcher so they cannot disagree:
- `enb {1}` if `e2lteEnabled`;
- `gnb {2..1+nMmWaveEnbNodes}` if `e2nrEnabled`.
- The cellIds (LTE = 1, mmWave 2..5) come from the fact pack (MWH:90, 1847, 2268), **derived, not run**. M4 must assert them from the emitted `hello` lines and trace file names.

| scenario-zero config | E2 nodes | agents | IPC ports | expected e2mgr names |
|---|---|---|---|---|
| default (`nMmWaveEnbNodes=4`, LTE on) | enb 1 + gnb 2–5 | 5 | 38471–38475 | `gnb_001_001_00000001` … `_00000005` |
| `--nMmWaveEnbNodes=1` | enb 1 + gnb 2 | 2 | 38471–38472 | `…01`, `…02` |
| **P5:** `--nMmWaveEnbNodes=1 --e2lteEnabled=false` | gnb 2 | 1 | 38472 | `gnb_001_001_00000002` |

- **`--e2lteEnabled=false` changes nothing on the radio side.** It only skips the LTE E2Termination (MWH:2502). The PDCP/RLC stats it would otherwise affect stay alive because NR mode keeps them (MWH:3186, :3216).
- **Name formula.** e2term prints `gnb_` + BCD MCC_MNC + `_` + the gNB-ID bits right-aligned in hex (E2T `BuildRunName.h:34-54`, `:56-117`). For PLMN `00 F1 10` and 29-bit ID N, that gives `gnb_001_001_0000000N`.
  - kpm_sim (PLMN `"747"` ASCII, ID `B5C67788`; `encode_e2apv1.cpp:161-174`) yields `gnb_734_373_16b8cef1` under the same formula, so the two are distinct by construction.
  - The formula comes from master; M5 confirms it against e2term 6.0.6 and pins it.
- **Every node registers as a GlobalE2node gNB**, the LTE eNB included, because e2sim's generator only builds gNB IDs (`encode_e2apv1.cpp:176-196`). This is a recorded deviation; the node kind travels in `E2_NODE_KIND` and the cell list.

**Gate run order:**
1. `gate_bringup agents` (stop_e2sim.sh).
2. Assert `lsmod | grep sctp`, and persist the module in `/etc/modules-load.d/sctp.conf`, because snapshot gates reboot.
3. **Start tcpdump on docker0 before the agents start.** Wireshark learns the RAN-function → dissector mapping only from E2Setup (`e2ap.cnf:287-302`).
4. Run `run_ns3_e2_agents.sh`: `rm -f` any old containers, resolve the ClusterIP, start N containers, and write `run/agents.json` (`{nodeId, kind, container, ipcPort, e2Term, expectedRanName, imageId}`).
5. Wait until the e2mgr CONNECTED set equals the expected set.
6. Wait for exactly 1 subscription per node (agent stats).
7. Start ns-3 (direct binary, its own PGID).
8. Collect evidence.
9. Stop ns-3 by PGID, stop the agents with `docker rm -f` by label, stop the capture.

**Discovery and evidence:** `docker ps --filter label=ns3e2.agent=1` plus `run/agents.json`. The agent prints a JSON stats line every 5 s to `docker logs` (`state`, `subs`, `samplesRx`, `indTx`, drops by reason, `int32Overflow`, `chunkSplits`); that is the machine-readable evidence.

**Hygiene:** the agents' SCTP sockets live in their container netns, so the host's `ss -Sanp` shows nothing. Use `nsenter -t $(docker inspect -f '{{.State.Pid}}' <c>) -n ss -Sanp`, or the host's `conntrack -L -p sctp`. After teardown, assert 0 labelled containers and 0 SCTP conntrack entries to the ClusterIP.

---

## Three biggest risks to M5–M7, each with a cheap early probe

| # | Risk | Why it is real | Cheap probe and when |
|---|---|---|---|
| **R1** | **E2SM codec paths that M3 never exercises:** REAL records, Format 2 with `measCondUEidList` / `MatchingCond` / `UEID`, and a RANfunction-Description with a format-3 style and measIDs. They are encoded by e2sim's v3 asn1c and decoded by kpimon's patched v2 decoder. | kpm_sim sends only Format 1 with integer 1s (`encode_kpm.cpp:250-264`). Its UE reports land in `cellMetrics`, and its 1-record cell reports are dropped by the count check (KPC:790-793). So `UeMetrics` and REAL stay unproven until M6. The struct diff is favourable (only extension additions differ) but is not proof. | **About 2 h, right after P3 sign-off and before P4 fixes the types; no RIC needed.** Build `tests/codec-probe.cpp` in the agent image. It encodes (a) the RAN function definition, (b) a header, (c) Format 1 with INTEGER/REAL/noValue, including 0.1, −0.0, 2^53 and 1e300, and (d) Format 2 with 3 metrics × 2 UEs, including UEIDs. Feed them to `tools/kpimon-decode-harness`, adding a mode that calls kpimon's own `buildRanCellUeKpi` (KPW:12-113) on the definition hex. Pass when: header and messages decode RC_OK with every byte consumed; the lists match the map; and the decoded doubles are bit-identical (`%a`). |
| **R2** | **Reconnect after the e2term pod delete ends in "CONNECTED but silent".** | Possible causes: kpimon's 5 s poll misses the outage (KPC:1146-1189); submgr does not drop the old subscription, or dedupes kpimon's re-subscribe; e2mgr is slow to mark the node DISCONNECTED; NAT/conntrack is reused under a fixed source port. | **About 1 h in P5 with one agent, after M6, before P6.** (a) `docker restart` the agent and assert a new RICsubscriptionRequest arrives (tests the hold-off). (b) `kubectl -n ricplt delete pod <e2term>` and record the six-step timeline in Q6. (c) Informational: repeat (b) with `E2_SCTP_SRC_PORT=36422`. If M2's K10 probe has not run yet, add "delete the e2term pod while 2 probe containers hold associations, then reconnect from the same port vs a new port" there. It costs minutes. |
| **R3** | **Size and rate limits silently thin out Influx.** | The E2SM 8192-byte overflow (`encode_e2apv1.cpp:958`, `:969`); kpimon's RMR `maxSize` of 2072 (`deploy/config.json:57`) with its RMR version unverified; a goroutine per indication (KPC:666) doing blocking writes whose errors are ignored (:983, :1003). A free-running 1-gNB ns-3 may also run faster than real time. | **About 1 h in P5.** Write a tiny `tools/ipc-replay.py` that replays a trace (or synthetic samples with duplicated UEs) into the agent. Check that Influx gets rows for Format-2 messages of about 1.5, 3 and 6 KB. Then replay at 10× nominal rate for 60 s and compare Influx row rate with indications sent. Watch `docker stats` RSS: it must stay flat, since every PDU must be `ASN_STRUCT_FREE`d and the generator callocs 8 KB per indication. |

---

## Flags in the plan I believe are wrong or incomplete (flagged, not changed)

1. **phase-05 req 2 ("1 agent, 1 E2 node").** D3's `--nMmWaveEnbNodes=1` alone still gives **2** E2 nodes, because `e2lteEnabled` defaults to true (scenario-zero:142, :294). P5 also needs `--e2lteEnabled=false`, an existing flag that gates only the LTE E2 node (MWH:2502).
2. **K7 "Docker `--restart always` + empty table" is necessary but not sufficient.** Without a hold-off longer than kpimon's 5 s poll (KPC:1147, :1178-1185), a fast restart loses the subscription silently. Also, an agent that `exit`s on a refused connect inherits Docker's backoff of up to 60 s (MOBY :12-14).
3. **K1 option (a) is superseded** by the evidence in Q3: the library patch does not remove the need for an agent-owned loop, and it touches kpm_sim's build.
4. **phase-03 Q5 "reply with the requested actions admitted".** e2sim's response generator corrupts the PDU when any action is not admitted (`encode_e2apv1.cpp:719`, `:733`) and hard-codes RANfunctionID 147 (`:668`). The agent must admit all and post-edit.
5. **K13 "count Influx writes from `Wrote … Metrics`".** kpimon logs that line even when the write failed, because `WritePoint` errors are ignored (KPC:983-984, :1003-1004). It is an upper bound only; the Influx query must be the authority (M3/M6 already query, so just don't trust the log count).
6. **K14/M6 teardown "`ss -Sanp`".** Agent SCTP sockets are inside container netns and invisible to the host's `ss`. Use `nsenter` or `conntrack` (Q7).
7. **The M3 expectation should say that `UeMetrics` stays empty with kpm_sim** (see R1). Otherwise someone will "fix" it.
8. **phase-05 M6 "documented rounding rule for floats".** 0 ULP is achievable (Q1/Q4). Keep the rule, but set it to exact. That is stricter, never looser.
9. **The plan's P5 traceability line "F: ns-3 timestamp is 8-byte `htobe64`"** is obsolete after decoupling. The agent now writes the header, in NTP-64.
10. **The K10 capture "on docker0"** also catches the IPC TCP traffic (via docker-proxy). Add the BPF filter `ip proto 132`.

## What to avoid

- **Don't reuse `run_loop`, `E2Sim` callbacks, `encode_and_send_sctp_data` or `sctp_start_client`.** They exit, block, truncate to `MAX_SCTP_BUFFER = 10000` (`e2sim.cpp:74-77`; `e2sim_defs.h:33`) or reuse the global fd.
- **Don't exit on "e2term not reachable yet".** Retry in-process; only association loss and setup timeout exit.
- **Don't put per-UE values into Format 1, and don't add F1 configs to trick kpimon** into creating format-1 actions. Both widen scope.
- **Don't let an INTEGER carry a value that can be ≥ 2^31 or negative**, and don't let one KPM name have two types. Influx then rejects the point, kpimon ignores the error, and M6 goes mysteriously sparse.
- **Don't emit names containing `_`**, and don't set any v3 extension addition.
- **Don't join Influx on `_time`.** It is kpimon's wall clock.
- **Don't reflect ns-3's `reducedPmValues` into the KPM definition.** The definition is static agent config; IPC always carries the full set.
- **Don't start the capture after the agents.** Wireshark can't decode E2SM without the E2Setup.
- **Don't vendor a JSON library into ns-3 just for writing.** A 100-line writer is simpler and fully under control.

## Alternatives and trade-offs (short)

- **Lock-step or real-time pacing now:** out of scope by user decision. The IPC reserves `step`/`control` types, so nothing precludes it.
- **Agent restart policy `unless-stopped`:** behaves the same for crashes, and `docker rm -f` in stop-all already prevents ghosts. Keep K7's `always`.
- **User-defined Docker network with static IPs** (`--ip 172.30.0.(10+cellId)`), with ns-3 connecting to the container IP and no docker-proxy:
  - Benefit: deterministic per-node addresses in captures.
  - Cost: the K10 probe and the docker0 capture rule are about the default bridge, and it adds one more lifecycle object.
  - Worth it only if docker-proxy causes trouble.
- **Omit `matchingUEidList` in Format 2:** about 3× smaller messages and less decoder surface. kpimon ignores UEIDs, and `ns3.imsi` already carries identity. Keep it as the fallback if R1 shows a UEID decode mismatch; the default includes UEIDs for fidelity.

## Work checklist (P3 → P5)

1. Journal `docs/journals/<date>-p3-e2-agent-design-checkpoint.md`, written from this counsel. Explicitly ask for sign-off on these four deviations:
   - K1 (a) → (b);
   - the hold-off;
   - the ephemeral source port;
   - the LTE eNB registering as a gNB.
2. Commit the schema files (`ns3-e2-ipc.v1.md`, `.schema.json`, `metric-map.v1.json`) on the Testbed fork branch. The map lint becomes a unit test.
3. Run the R1 codec probe and extend the harness with the RANfunction-Description mode **before** P4 freezes the INTEGER/REAL choices.
4. P4: implement the emitter as in Q6, and add the M4 checks: every `src` resolves, and the cellId-to-node mapping is asserted from the hello lines.
5. P5: run `install_ns3_e2_agent.sh` and the run/stop scripts.
   - M5 adds the XER diff against kpm_sim, the definition decoded through the kpimon library, the pinned expected inventory name and RAN function 2 in `RANfunctionsAccepted`.
   - M6 adds exact equality including floats, one cell row per `(nodeId, seq)`, UE rows equal to the UE count, `int32Overflow = 0` and subscriptions = 1 per node.
6. Run the R2 and R3 probes before P6.
7. M7 adds per-node RestartCount (0 before the delete, 1 after), the six-step timeline, flat agent RSS, and `ipcDropped` accounting.

## Success metrics

- **M5:** e2mgr shows `gnb_001_001_0000000N`, CONNECTED. The XER diff against kpm_sim shows only identity, OID and definition. kpimon's library decodes the definition with list lengths equal to the map's.
- **M6:** harness header RC_OK = message RC_OK = indication count, and RC_WMORE = RC_FAIL = 0. Three sampled `(nodeId, seq)` rows equal the trace bit-for-bit, cell and UE.
- **M7:** all 5 nodes resubscribe after the pod delete, with a recorded bound under about 60 s, zero manual steps, and zero agent restarts outside that window. The 15-minute run shows flat RSS and no `int32Overflow`.
- **Reuse:** none of NIST's e2sim or kpm_sim files is modified, and the reference node's image is byte-for-byte NIST's.

## Assumptions (made in place of questions)

| # | Assumption | Confidence | What would change the answer |
|---|---|---|---|
| A1 | e2term 6.0.6, e2mgr and submgr do not validate the KPM OID or the subscription-response RANfunctionID | medium | M5 rejection → `E2_KPM_OID=OID123`; keep the 147 fix unless the response is rejected |
| A2 | KPM v3 TimeStamp is the RFC 5905 64-bit NTP format | medium-high | The spec PDF says otherwise → change only the agent's header encoder |
| A3 | asn1c REAL and Format-2 APER interoperate between e2sim's and kpimon's skeletons | medium | R1 fails → fall back to omitting UEIDs; if REAL fails, consult before changing types (M6 meaning) |
| A4 | submgr 0.10.2 drops subscriptions on DISCONNECTED (plan K7) and does not dedupe kpimon's fresh subscribe | medium | R2 shows "CONNECTED but silent" even with the hold-off → Decision required (would need a kpimon/submgr-side change) |
| A5 | Netfilter reuses the NAT binding for a repeated 5-tuple while the entry lives | high (mechanism), unknown (whether it actually bites here) | Irrelevant with ephemeral ports; R2(c) documents it |
| A6 | kpimon's RMR accepts messages over 2072 bytes | medium-high | R3 fails → set `E2_MAX_E2SM_BYTES` to about 1800 and `E2_UES_PER_IND` to 1–2 |
| A7 | cellIds are LTE = 1, mmWave = 2..1+N | medium (derived, not run) | M4 hello lines show otherwise → only the node-set function changes |
| A8 | The user accepts the LTE eNB registering as a gNB-type E2 node | medium | Rejection → the agent needs its own eNB setup builder (e2sim has none) |

## Unresolved questions (for the journal and sign-off)

1. Sign-off on the four deviations in checklist item 1.
2. If R2 shows that submgr or kpimon keep a stale subscription despite the hold-off, is a kpimon or RIC-side change in scope? (Decision required; it is not needed if R2 passes.)
3. Keep UEIDs in Format 2 (fidelity) or drop them (size and decoder surface)? The default is keep, pending R1.

## Sources

External sources fetched during this review:
- [Wireshark release-4.2 packet-e2ap-template.c](https://gitlab.com/wireshark/wireshark/-/raw/release-4.2/epan/dissectors/asn1/e2ap/packet-e2ap-template.c)
- [Wireshark release-4.2 e2ap.cnf](https://gitlab.com/wireshark/wireshark/-/raw/release-4.2/epan/dissectors/asn1/e2ap/e2ap.cnf)
- [RMR mt_call_si_static.c (master)](https://raw.githubusercontent.com/o-ran-sc/ric-plt-lib-rmr/master/src/rmr/si/src/mt_call_si_static.c)
- [RMR rmr_alloc_msg man page](https://docs.o-ran-sc.org/projects/o-ran-sc-ric-plt-lib-rmr/en/latest/rmr_alloc_msg.3.html)
- [moby restartmanager.go (master)](https://raw.githubusercontent.com/moby/moby/master/daemon/internal/restartmanager/restartmanager.go)
- [ric-plt-e2 BuildRunName.h (master)](https://raw.githubusercontent.com/o-ran-sc/ric-plt-e2/master/RIC-E2-TERMINATION/BuildRunName.h)
- [Wireshark docs: ran_function_dissector_t](https://wireshark.org/docs/wsar_html/structran__function__dissector__t.html)

Local sources: E2SIM (`da6f82f2`), NRT (`0b1cf7a`), kpimon `8bbbbbb9` plus NIST patches, OI (`5f547ae`), NS3 (`8c42089d`), cited inline.

# L-release RIC facts (Phase 1) — pinned reference

Captured 2026-06-06 on VM `oran-kvm-2` (SSH alias; real hostname `oran-kvm-3`). Source of truth for Phases 2–7.

## RIC / E2Term
| Item | Value |
|---|---|
| Namespace | `ricplt` |
| E2Term deployment | `deployment-ricplt-e2term-alpha` (pod `...-5xm9v`, IP `10.244.0.48`) |
| **E2Term image** | `nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-e2:6.0.6` (recon doc said 3.0.1 — **actual is 6.0.6**) |
| E2Term SCTP svc | `service-ricplt-e2term-sctp-alpha`, ClusterIP `10.105.242.197`, **NodePort `32222` → targetPort `36422`** |
| **Node IP (E2 endpoint for ns-3)** | `192.168.122.78` (iface `enp2s0`); connect ns-3 → `192.168.122.78:32222` |
| kube-proxy mode | **IPVS** (`kube-ipvs0`); pod network Flannel (`cni0` 10.244.0.1/24) |
| e2mgr REST | `service-ricplt-e2mgr-http` `/v1/nodeb/states` (used to verify CONNECTED) |

## Bundled KPM sim (reference E2 node = the wire gold standard)
- Runs in Docker container **`oransim:0.0.999`** (built, 2.7 GB); binary `kpm_sim <e2term-ip> <port>`.
- Source: `O-RAN-Testbed-Automation/.../e2-interface/e2sim/e2sm_examples/kpm_e2sm/`. **libe2sim already built** (`.../e2sim/build/libe2sim_shared.so`, `.a`).
- **RAN function ID = 2** (`gFuncId = 2`, env `RAN_FUNC_ID` default "2"), short_name `ORAN-E2SM-KPM`, func_desc `KPM Monitor`, **e2sm OID = `OID123` (dummy!)**.
- Launcher: `.../install_scripts/run_e2sim_and_connect_to_ric.sh` (connects to ClusterIP:36422 by default).

## Phase 1 result (verified live)
- kpm_sim → **NodePort `192.168.122.78:32222`** → `[SCTP] Connection established` ✓ (**NodePort path that ns-3 will use is reachable** — de-risks Phases 2/3).
- E2 Setup completed: e2mgr `/v1/nodeb/states` → `{"inventoryName":"gnb_734_373_16b8cef1","globalNbId":{"plmnId":"373437","nbId":"10110101110001100111011110001"},"connectionStatus":"CONNECTED"}` → **M2 (E2 Setup) + M3 (RAN function accepted) demonstrated by the bundled sim.**
- Golden pcap `baseline/golden-lrelease-e2.pcap`: 10 SCTP pkts (2 INIT, 2 COOKIE, 3 SACK, **2 DATA = E2setupRequest + E2setupResponse**), captured on `cni0` (`sctp`).
- Full decoded PDU: `baseline/golden-lrelease-e2setup.xml`. Contains `TransactionID`, `GlobalE2node-ID/gNB`, and **`E2nodeComponentConfigAddition-List`** — a v2.0+/v3.01 IE **absent in Bronze v01.00** (confirms the E2AP version jump on the wire).

## Key findings / decisions
1. **e2term 6.0.6 accepts dummy `OID123`** in the E2 Setup RAN function (sim uses it and registers CONNECTED). ⇒ The OID is **not** validated at E2 Setup; it matters for the **xApp subscription** (Phase 5), revising the Phase-4 assumption that `OID123` "will be rejected."
2. **RAN-func-ID ambiguity (open):** bundled sim **registers func 2**; testbed `ric-scp-kpimon` **subscribes with `funcID = 0`** (`control/control.go:90` `sendRicSubRequest(1001,1001,0)`). Working assumption: ns-3 advertises **func 2** (mirror the reference sim); resolve empirically when a real subscription is driven in **Phase 5**.
3. **No xApp deployed** (`ricxapp` ns empty) ⇒ no subscription/indication available yet. Like Bronze, the **E2 Setup golden is captured now**; the **subscription+indication golden (M4/M5) is deferred** until an xApp (scp-kpimon / kpimon-go) is onboarded.

## Capture how-to (reproducible)
- L-release E2 SCTP to e2term pod rides **`cni0`** (pod `10.244.0.48`). Capture: `sudo tcpdump -i cni0 -s0 -U -w out.pcap 'sctp'`.
- Run sim: `docker run -d -it --name oransim -e RAN_FUNC_ID=2 oransim:0.0.999` then `docker exec -i oransim sh -c 'kpm_sim 192.168.122.78 32222 >/app/logs/e2sim_output.txt 2>&1 &'`.
- Verify: `curl <e2mgr-http-clusterip>:<port>/v1/nodeb/states | jq` → `connectionStatus: CONNECTED`.

## Unresolved questions
- Q (func-ID): does the real subscription target func **2** or **0**? (Phase 5 empirical.)
- Q (indication golden): onboard `scp-kpimon`/`kpimon-go` to capture M4/M5 golden, or rely on standalone sim-driven indications in Phase 2?

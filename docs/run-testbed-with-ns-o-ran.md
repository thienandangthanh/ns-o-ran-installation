# Running the Testbed with ns-O-RAN (instead of srsUE)

How to drive the O-RAN control loop with **ns-O-RAN (ns-3)** as the RAN, rather than
booting the NIST `O-RAN-Testbed-Automation/run.sh` srsRAN+srsUE stack.

## Key idea: ns-O-RAN replaces the entire RAN + RF + core

`../O-RAN-Testbed-Automation/run.sh` boots a **real-software RAN**:
`5G Core (Open5GS) → srsRAN gNB → srsUE` linked by a **ZMQ virtual radio**, and its
RIC `run.sh` additionally attaches an **e2sim** as the E2 node.

ns-O-RAN does **not** plug into that chain. The ns-3 simulation *is* the gNB **and**
the UE **and** the RF channel **and** the E2 node. So you do **not** run:

- ❌ `5G_Core_Network/run.sh` (Open5GS)
- ❌ `Next_Generation_Node_B/run.sh` (srsRAN gNB)
- ❌ `User_Equipment/run.sh` (srsUE) — the srsue + ZMQ + netns machinery is entirely unused
- ❌ the testbed `run.sh` top-level orchestrator
- ❌ the testbed's bundled e2sim (`kpm_sim`) — ns-O-RAN brings its own E2 termination per gNB

The **only** testbed component ns-O-RAN needs is the **Near-RT RIC** (E2Term + xApps).

| Component | NIST `run.sh` path | ns-O-RAN path |
|---|---|---|
| 5G Core | Open5GS | not used (RAN simulated) |
| gNB / UE / PHY | srsRAN gNB + srsUE | **ns-3 scenario** |
| RF / channel | ZMQ ideal wire | **ns-3 channel model** |
| E2 node | testbed e2sim (`kpm_sim`) | **ns-3 per-gNB E2 agent** |
| Near-RT RIC + xApps | **required** | **required** (same) |

## Startup sequence

### 1. Bring up only the Near-RT RIC + xApps
Use your existing OSC L-release RIC (k8s ns `ricplt` on `oran-kvm-2`, 192.168.122.78),
or the testbed RIC. With the testbed RIC, run **only**:

```bash
cd ../O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC
sudo ./run.sh        # brings up ricplt pods + onboards xApps
```

> Note: this script also auto-attaches a testbed e2sim. It's harmless (ns-O-RAN
> connects as a separate E2 node), but for a clean topology you can stop it:
> `sudo ./install_scripts/stop_e2sim.sh`. Deploy your KPM/RC xApp (e.g. kpimon-go)
> the same way as today.

### 2. Find the E2Term SCTP endpoint
ns-O-RAN connects to the e2term **POD IP**, not the NodePort:

```bash
kubectl get pods -n ricplt -o wide | grep e2term     # POD IP, e.g. 10.244.0.48
kubectl get svc  -n ricplt | grep e2term-sctp        # SCTP port (36421/36422)
```

### 3. Launch the ns-3 scenario as the RAN/E2 node
From the ns-3 tree, point the scenario at that endpoint:

```bash
./ns3 run "scratch/scenario-zero \
  --e2TermIp=10.244.0.48 \
  --enableE2FileLogging=false \
  --simTime=20 \
  --reducedPmValues=1 \
  --e2du=1 --e2cuUp=0 --e2cuCp=0"
```

ns-3 now performs the full E2 handshake (SETUP → RANfunctions → subscription →
indication) directly with the RIC. KPM indications flow to the xApp exactly as they
would from a real gNB — no srsUE, no ZMQ, no Open5GS involved.

## Gotchas (from live Phase-7 run)

- **e2term IP must match `mmwave-helper.cc:300`** (hardcoded). Rebuild ns-3 if the RIC
  is redeployed and the pod IP changes, or align the helper to the new IP.
- **Stale RNIB between runs**: clear the disconnected node so the xApp re-subscribes:
  `curl -X PUT http://<e2mgr>:3800/v1/nodeb/shutdown`, then restart the xApp pod.
- **funcId match**: ns-3 must register the KPM RANFunctionID the xApp subscribes to
  (kpimon-go hardcodes funcId 2). See [[version-verification-and-rc-roadmap]].
- **Multi-gNB SCTP src-port collision** already patched in `oran-e2sim` /
  `oran-interface` — required for scenario-zero's parallel gNBs.

See `docs/journals/2026-06-07-phase7-live-m1-m6-end-to-end.md` for the validated run.

## Why choose this over srsUE+ZMQ
You get a **fully customizable wireless environment** (channel models, mobility,
multi-cell interference, many UEs) feeding a **real E2/RIC control loop** — at the
cost of a *simulated* (not production) RAN stack. The srsUE+ZMQ path is the inverse:
real stack, ideal/uncustomizable channel. Pick ns-O-RAN when the **environment** is
the variable under study.

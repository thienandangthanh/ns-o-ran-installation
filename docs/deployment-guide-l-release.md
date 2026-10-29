# Deployment and re-run guide: ns-O-RAN on the OSC Near-RT RIC L-release (NIST v1.8.0)

This guide gets you from a clean `fresh-install` VM snapshot to a green M0 to M7 chain or a green M9 run, and shows how to run single gates, the E2 agents, ns-3, rc controls and the TS xApp loop by hand. The scripts are the authority for commands and flags; this guide cites them and does not restate their logic. For the design and the reasons behind it, read [system-architecture-l-release.md](system-architecture-l-release.md).

Where a step was not checked against a script or a run, it is marked "(unverified)".

## 1. Prerequisites

| Item | Requirement | Owner |
|---|---|---|
| Host | libvirt/KVM; the host user manages `qemu:///system` without sudo; `ssh`, `git`, `python3`, `gh` | `scripts/vm/vm-common.sh`, `scripts/gates/gate-m0-host.sh` |
| VM | libvirt domain `ubuntu24.04`, Ubuntu 24.04.5, at least 8 vCPU, 14 GiB RAM, 60 GB free on `/`, `sctp` kernel module available | `scripts/gates/gate-m0-preflight.sh` |
| VM user | `uc` with passwordless sudo, no git credentials | `gate-m0-host.sh` (`vm_no_git_credentials`) |
| Snapshot | `fresh-install`, offline and disk-only; never deleted by the scripts | `scripts/vm/vm-snapshot.sh` |
| ssh alias | `oran-kvm-2404` by default, key-based | `VM_SSH` in `vm-common.sh` |
| Host disk | `/home` free space of at least 20 GB plus the growth of the next gate | `vm-snapshot.sh create`, growth table in `run-to-m7.sh` |
| Harness repo | public on GitHub, harness SHA pushed to an `origin` branch | `scripts/vm/vm-exec.sh` |

Host-side overrides (environment variables, defaults in `vm-common.sh` and `vm-exec.sh`): `VM_DOMAIN`, `VM_SSH`, `VM_IMAGE_DIR`, `HOST_MIN_FREE_GB`, `EVIDENCE_HOST_ROOT`, `HARNESS_URL`.

For host-side libvirt and virtiofs setup, see [linux-vm-setup-guide.md](linux-vm-setup-guide.md).

Disk budget rule: the sum of the growth column in `run-to-m7.sh` is about 54 GB, and the reserve is 20 GB, which is where the "about 70 GB" figure comes from. A revert does not delete the overlay files it leaves behind, so they count against the budget. `vm-snapshot.sh create` refuses to run when the budget is not met; when it does, free space (see "Snapshots") or stop and decide.

## 2. Pins

`scripts/pins.conf` is a shell-sourceable file with the URL and commit of every fork the gates clone (Testbed, ns-3, oran-interface, oran-e2sim) and the fork branch name. It holds no secrets. It is named `.conf` on purpose: a `*.env` name trips the local privacy hook and breaks unattended runs.

The harness commit cannot pin itself, so it is passed as `--harness-sha`. Every `verdict.json` records the harness SHA and the pins that were in force.

Check before a run:

```bash
scripts/gates/lint.sh        # bash -n, shellcheck if installed, wrapper-around-function check
git push origin HEAD         # vm-exec.sh refuses a SHA that is not on an origin branch
git rev-parse HEAD           # the value for --harness-sha
```

## 3. Run the whole chain

```bash
scripts/vm/vm-snapshot.sh revert fresh-install
scripts/run-to-m7.sh --harness-sha <pushed SHA> --run-prefix f
```

What happens (see `scripts/run-to-m7.sh`):

1. For gate 0, the host half `gate-m0-host.sh` runs first.
2. Each gate runs on the VM through `vm-exec.sh`, which copies the scrubbed evidence back.
3. After a green gate the VM is snapshotted offline (graceful shutdown, snapshot, start, wait for ssh), so every gate boundary is also a reboot.
4. The chain stops at the first red gate and prints the evidence directory.
5. After M7 with prefix `f`, the final snapshot is `f7-rerun-green`.

Options: `--from N`, `--to N` (default 0 and 7), `--no-snapshots` (still reboots at each boundary so every run sees the same cadence; `f7-rerun-green` is still taken).

### Resuming after a red gate

Read the failing checks first (`failed` in `verdict.json`, section 5) and the troubleshooting table (section 8). Then return the VM to the last green boundary and resume from the failed gate:

```bash
scripts/vm/vm-snapshot.sh list
scripts/vm/vm-snapshot.sh revert f2-refnode
scripts/run-to-m7.sh --harness-sha <new pushed SHA> --run-prefix f --from 3
```

With `--from N` greater than 0 the M0 host half is skipped. A snapshot that already exists makes `create` fail, so after a red gate that you revert past, delete the stale later snapshots of your own prefix first (`vm-snapshot.sh delete <name>`; it refuses `fresh-install`). Do not reuse a prefix for a different run.

### M9: the chain plus the closed-loop rungs

```bash
scripts/vm/vm-snapshot.sh revert fresh-install
scripts/run-to-m9.sh --harness-sha <pushed SHA> --run-prefix n --no-snapshots
```

Usage, step order and stop paths are in the header of `scripts/run-to-m9.sh`. In short:

- The steps are M0 to M7, then `i0` (rc install), `r0`, `r1`, `i2` (TS xApp and stub QP install), `r2` and `r3p`. Rungs below the top run `--mode single`; the top rung runs `--mode c1 --reference` against `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/`.
- The runner refuses to start when `scripts/`, `tools/` or that reference differ from the harness SHA in your worktree, when they hold untracked files, when `scripts/m9-budget.json` is missing, when the prefix is `f` or `l`, or when snapshots with the prefix already exist.
- Revert `fresh-install` yourself first; the runner never reverts.
- `--no-snapshots` takes no snapshot, M7 included, and reboots the VM at each gate boundary instead. The M0 host half still creates its own `m0-probe-*`/`m0-branch-*` pair.
- Per-step timeouts, the global wall deadline and the disk watchdog's polling interval and trip point come from `scripts/m9-budget.json`; `m9-budget.md` in the plan directory explains them and gives the host free space to have before the revert. Below the trip point the watchdog stops the run; a stale watchdog heartbeat or the wall deadline cancels it the same way.
- `--from` and `--to` run a subset, which the verdict marks `notM9`.
- A revert to `fresh-install` after an M9 run can leave that run's working overlay in `/home/andang/VMs/` (the M0 probe's branch create and delete untrack it in libvirt). `df -BG /home` then shows the space still used. Check that no domain, snapshot or image references the file before you delete it; the checks used are in `plans/reports/decisions-261028-2014-GH-1-leaked-overlay-deletion-ruling.md`.
- Every RIC bring-up checks that e2mgr's and submgr's RMR route-table readers drain what rtmgr sends them. After a cold boot or a fresh RIC install they can stop reading, and then e2mgr cannot answer an E2 Setup. If a reader is stuck, the bring-up replaces e2mgr and submgr and restarts rtmgr once (`ric_refresh_routes` in `scripts/gates/bringup.sh`), logged in the gate's `watchdog.log` and `rt-readers-*.txt`. In the recorded M9 run it fired once, in m1.
- The verdict is `evidence/m9/<UTC timestamp>/verdict.json` under the plan directory, written by `scripts/m9-verdict.py` in every case. Read `pass`, `problems`, `exactStepSet`, `notM9`, `highestGreenRung`, `equalsReference`, `minHostFreeGb` and `watchdogAlive`. Each step's own evidence is listed in `steps.tsv` next to it.

Scope: M9 proves the closed loop with the TS xApp and a harness predictor in place of QP. The QP fork and an R3 rung with the real QP are deferred to a later goal; AD is not used. The deviations from the O-RAN and 3GPP specifications that the port keeps knowingly (P1 to P10, N5) are listed, with their standards, in the M9 run report `plans/reports/run-report-261029-0535-GH-1-m8-m9-deviations.md`. The recorded M9 run passed: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/verdict.json`.

## 4. Run one gate

```bash
scripts/vm/vm-exec.sh gate-m5-agent-setup.sh --harness-sha <pushed SHA> --timeout 5400
```

`vm-exec.sh <gate-script> [--harness-sha SHA] [--timeout S] [-- gate args...]` does the following:

1. Clones the harness on the VM anonymously and checks out the exact SHA.
2. Launches the gate as a transient systemd unit (`gate-<m>-<timestamp>`) running as `uc`, so an ssh drop never kills it.
3. Polls for the `exit_code` file, which the wrapper writes last. A gate that crashes without a verdict still ends the poll.
4. On timeout it stops the unit and records exit code 124.
5. Runs the scrubber, writes `pcap-sha256.txt`, and copies the evidence to the host.
6. Exits with the gate's status, 0 meaning pass.

A single gate expects the VM to be in the state its predecessor left. Gates M5 to M7 need the RIC, the patched kpimon and the M4 ns-3 build; revert to the previous gate snapshot rather than running a gate on an arbitrary state.

Gate scripts, default timeouts (seconds) and the growth reserve for the snapshot that follows are in the `GATES` table of `run-to-m7.sh`. Knobs inside a gate (for example `ENDURANCE_S`, `NS3_TIMEOUT_S`, `SUSTAIN_S`, `M4_WORKDIR`) are listed in the header comment of the gate script. `vm-exec.sh` does not forward arbitrary environment variables to the gate unit, so changing a knob means editing its default in the gate script (unverified: no run has overridden a knob).

## 5. Snapshots and evidence

### Snapshot names

| Prefix | Use |
|---|---|
| `l*` | the development run (`l0-preflight` to `l7-multignb`) |
| `f*` | the unattended re-run (`f0-preflight` to `f6-kpm`, then `f7-rerun-green`) |
| `n*` (default of `run-to-m9.sh`) | the M9 run; none are created with `--no-snapshots` |
| `m0-probe-<run>`, `m0-branch-<run>` | M0 snapshot probes |
| `fresh-install` | the protected base; `vm-snapshot.sh delete` refuses it |

Gate suffixes are `preflight`, `ric-up`, `refnode`, `xapps`, `ns3-build`, `agent-setup`, `kpm`, `multignb` (from the `GATES` table). Snapshot overlay files are named `ubuntu24.04-<snapshot>.qcow2` in `VM_IMAGE_DIR`, so a revert-generated file can never collide with a later gate name.

Commands (`scripts/vm/vm-snapshot.sh`):

```bash
scripts/vm/vm-snapshot.sh list
scripts/vm/vm-snapshot.sh create <name> [--need-gb N] [--evidence DIR]
scripts/vm/vm-snapshot.sh revert <name>
scripts/vm/vm-snapshot.sh delete <name>
```

Always shut the VM off before a revert; `revert` does this gracefully and never forces it. Snapshots are offline, disk-only and external: a raw base image plus qcow2 overlays. Deleting a leaf snapshot removes its overlay file; overlays left behind by a revert are not removed by libvirt.

### Evidence layout

Per gate, on the host under `$EVIDENCE_HOST_ROOT/<gate>/<UTC timestamp>/` (default root `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence`):

| File | Content |
|---|---|
| `verdict.json` | `gate`, `ts`, `harness_sha`, `pins`, `duration_s`, `pass`, `failed` (names), `checks` (name, pass, detail) |
| `checks.jsonl`, `checks/<name>.out` | one line per check, and its full output |
| `gate.log`, `launch.log`, `exit_code` | gate output, the systemd wrapper's output, the gate's exit status |
| `*.pcap`, `pcap-sha256.txt` | captures (ignored by git) and their sha256 manifest |
| gate-specific files | tshark decodes, harness JSONL, agent stats, Influx exports, ns-3 traces |

The M0 host half writes `<ts>-host/verdict.json` next to the VM half. M0 is green only when both pass. `<root>/.last-mN` holds the path of the latest evidence for gate N.

Print a verdict:

```bash
python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); print(v["gate"], "PASS" if v["pass"] else "FAIL", v["failed"])' <evidence dir>/verdict.json
```

A gate is green only when every check in it passes. The evidence rule is: wire bytes decode with tshark and, for KPM, through kpimon's own decoder (`tools/kpimon-decode-harness`). Log lines are supporting evidence only.

### Scrubber

`scripts/gates/scrub-evidence.sh <evidence-dir>` runs on the VM before evidence is copied. It redacts every string from NIST's `influxdb_auth_token.json` and any InfluxDB-token-shaped string (80 or more base64url characters ending in `==`). It leaves pcaps alone. It cannot match 64-hex digests, so sha256 manifests survive.

### Comparing two runs

M1 records the resolved package and image versions. The installer takes the newest available package, so a re-run can drift:

```bash
python3 scripts/compare-run-versions.py <dev M1 evidence dir> <re-run M1 evidence dir> [--out FILE]
```

It always exits 0 and reports drift in its JSON; judge the report, do not ignore it.

### Replaying analysis offline

```bash
tools/e2-evidence/replay-m7-analysis.sh <m7 evidence dir> [work dir]
```

Re-runs M7's wire and trace checks on saved evidence with the gate's own code; it needs tshark and never writes into the evidence directory.

## 6. Timeouts and hang protection

- Every NIST script call goes through `nist_run <seconds> <cmd>` (`scripts/gates/lib.sh`): bounded by `timeout` and given a stdin that never reaches EOF, so NIST's `read -t` prompts neither block nor spin.
- Waits inside gates are bounded and logged; the retries are bounded too and each one is logged.
- The gate watchdog (`scripts/gates/bringup.sh`) deletes the e2term pod once if it is the only unready ricplt pod for more than 10 minutes. This is NIST's own remedy, logged in `watchdog.log`.
- Each gate checks that VM `/` stays at least 25 % free and prunes the Docker build cache (`disk_guard` in `lib.sh`).
- NIST has known unbounded loops (`wait_for_ricplt_pods.sh`, `run_e2sim_and_connect_to_ric.sh`, `full_install.sh`); only the outer timeout bounds them. They are listed in the header of `gate-m1-ric-up.sh`.

## 7. Run the agents and ns-3 by hand

Use this to debug on a VM that is at a green M4 or later state. The gates do the same thing; see `scripts/gates/agents.sh` and `scripts/gates/agents-ns3-run.sh`.

### Build ns-3

```bash
scripts/build-ns3.sh ~/m4-build [--ns3-sha SHA] [--oi-sha SHA] 2>build.log | tail -n 1
```

The script installs missing apt build dependencies, clones the pinned ns-3 and oran-interface commits, configures with fixed flags (recorded in `<workdir>/ns3-configure-flags.txt`) and builds `scenario-zero`. The last line on stdout is the absolute path of the binary. The libraries are in `<workdir>/ns-3/build/lib`; export `LD_LIBRARY_PATH` to that directory before running the binary.

### Build and start the agents

Run from the `Near-Real-Time-RIC` directory of the NIST tree on the VM. NIST's `install_scripts/install_e2sim.sh` must have run before (the agent build asserts it) and NIST's reference node must be stopped (`install_scripts/stop_e2sim.sh`), otherwise its node mixes into the CONNECTED set.

```bash
./ns3_e2_agent/install_scripts/install_ns3_e2_agent.sh > install-agent.log 2>&1 < /dev/null
./ns3_e2_agent/install_scripts/run_ns3_e2_agents.sh --nodes gnb:2
./ns3_e2_agent/install_scripts/run_ns3_e2_agents.sh --nodes enb:1,gnb:2,gnb:3,gnb:4,gnb:5
./ns3_e2_agent/install_scripts/stop_ns3_e2_agents.sh
```

- `install_ns3_e2_agent.sh` builds the image `ns3-e2-agent:<testbed short sha>` inside NIST's e2-interface tree and writes `ns3_e2_agent/run/image.env`. Environment: `E2_INTERFACE_DIR`, `NS3_E2_AGENT_TAG`, `CONTAINER_PULL_REGISTRY`, `BUILD_TIMEOUT_S`.
- `run_ns3_e2_agents.sh --nodes <kind:id>[,...] [--image IMG] [--env KEY=VAL]... [--plmn DIGITS]` starts one container per node (`kind` is `gnb` or `enb`, `id` is the ns-3 cellId) and writes `ns3_e2_agent/run/agents.json`. It resolves the e2term SCTP Service ClusterIP with kubectl. Use the second example for the default scenario-zero node set.
- `stop_ns3_e2_agents.sh` runs `docker stop -t 10` before `docker rm -f`, so the agents end their SCTP association cleanly. Never remove an agent container with a bare `docker rm -f` while the RIC is up.
- The agent's environment variables and defaults are in `ns3_e2_agent/src/agent-config.hpp`.
- Node set per scenario-zero configuration:

| ns-3 arguments | E2 nodes | `--nodes` | IPC ports |
|---|---|---|---|
| none (default) | eNB 1, gNB 2 to 5 | `enb:1,gnb:2,gnb:3,gnb:4,gnb:5` | 38471 to 38475 |
| `--nMmWaveEnbNodes=1` | eNB 1, gNB 2 | `enb:1,gnb:2` | 38471, 38472 |
| `--nMmWaveEnbNodes=1 --e2lteEnabled=false` | gNB 2 | `gnb:2` | 38472 |

Check the result:

```bash
docker ps --filter label=ns3e2.agent=1
docker logs --tail 5 ns3-e2-agent-2        # stats lines start with {"event"
```

e2mgr should list `gnb_001_001_00000002` as CONNECTED (the name is `gnb_<MCC>_<MNC>_<gNB-ID hex>` for PLMN `00101`).

### Run ns-3

Run the compiled binary directly, not `./ns3 run`, so you can control its process group:

```bash
"$BIN" --nMmWaveEnbNodes=1 --e2lteEnabled=false --simTime=10 --indicationPeriodicity=0.1 \
    --e2AgentHost=127.0.0.1 --e2TraceDir=./run1
```

Flags (declared in `ns-3-mmwave-oran/scratch/scenario-zero.cc` on the pinned commit):

| Flag | Default | Meaning |
|---|---|---|
| `--nMmWaveEnbNodes` | 4 | number of mmWave gNBs, 1 to 85 |
| `--e2lteEnabled` | true | whether the LTE eNB (cellId 1) is an E2 node |
| `--simTime` | 2 | simulated seconds, 0.1 to 100 |
| `--indicationPeriodicity` | 0.1 | seconds between samples, 0.01 to 2.0 |
| `--e2AgentHost` | 127.0.0.1 | host of the agents; the agent of cellId N listens on 38470 + N |
| `--e2TraceDir` | current directory | directory of `e2-ipc-trace-<cellId>.jsonl`, the local copy of every line sent |
| `--handoverMode` | `DynamicTtt` | the rungs use `NoAuto` (no automatic handover; RC controls move the UEs) |
| `--outageThreshold` | -5 | SNR outage threshold in dB; the rungs use -1000 (no LTE outage switch) |
| `--e2LedgerPath` | `e2-control-ledger.jsonl` in `e2TraceDir` | one line per applied or refused control |
| `--e2Pacing` | `free` | `lockstep` connects to the pacer at `127.0.0.1:<e2PacerPort>` |
| `--e2PacerPort` | 38499 | pacer TCP port |
| `--e2StartTimeout`, `--e2GateTimeout` | 120, 10 | lock-step barrier deadlines in seconds (start barrier, every other barrier) |
| `--simStartEpochMs` | 0 (wall clock at start) | epoch mapped to sim time 0; the rungs pin it so KPM timestamps repeat |
| `--enableUlTraffic`, `--ulTrafficPattern` | false, `constant` | opt-in UL traffic and the PDCP volume audit on stdout |

Timing: the default scenario needs far more wall time than simulated time; plan `--simTime` from the measured ratio. Measure it with:

```bash
scripts/measure-ns3-timing.sh <scenario-binary> <out-dir> [--repeats N] [--simtime S]
```

### Null sink (no RIC, no agent)

`tools/ipc-null-sink/ipc-null-sink.py` stands in for the agents when you only test ns-3's emitter:

```bash
python3 -I tools/ipc-null-sink/ipc-null-sink.py --ports 38471-38475 --out ./sink [--save-lines]
```

It prints `READY` when all listeners are bound, validates every line against the IPC schema, and writes `summary.json` on SIGTERM or SIGINT. It never replies. Stop ns-3 and the sink when done and verify no `3847x` listener is left (`ss -ltnp`).

### Send an rc control by hand

Use a VM at a green i0 state or later: rc is installed and Ready, and grpcurl is at `~/grpcurl-1.9.1/grpcurl`. `vm-exec.sh` leaves the harness clone at `~/harness`. The steps follow the smoke gate `scripts/gates/gate-q8-rc-smoke.sh`, which owns this loop (unverified as a hand run).

1. Start the agents for eNB 1, gNB 2 and gNB 3 (`run_ns3_e2_agents.sh --nodes enb:1,gnb:2,gnb:3`, above) and wait until each is READY with a kpimon subscription; the lock-step start barrier waits for exactly that.
2. Write a pacer schedule with one trigger and start the pacer; wait for `READY` in `pacer.log`:

    ```bash
    export KUBECONFIG=$HOME/.kube/config
    RC_EP="$(kubectl -n ricxapp get svc service-ricxapp-rc-grpc-server -o jsonpath='{.spec.clusterIP}'):7777"
    cat >sched.json <<JSON
    {"steps": {"20": {"trigger": {"cmd": ["bash", "$HOME/harness/scripts/gates/rc-send.sh", "$RC_EP", "2", "6", "0000000303"]}, "expect": 1}}, "late": []}
    JSON
    python3 -I ~/harness/scripts/gates/pacer.py --port 38499 --out ./pacer --t-ctl 30 --schedule sched.json >pacer.log 2>&1 &
    ```

3. Run ns-3 in lock-step:

    ```bash
    "$BIN" --nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1 --outageThreshold=-1000 \
        --e2AgentHost=127.0.0.1 --e2TraceDir=./run1 --e2Pacing=lockstep --e2PacerPort=38499 --e2GateTimeout=10
    ```

At step 20, once every agent has read sample 20, the pacer runs `rc-send.sh <endpoint> <viaNodeId> <imsi> <target key> [ackReq]`: here through the agent of node 2, for IMSI 6, to the key `0000000303` (`%08X%02X`, gNB 3, cell 3). rc answers the gRPC call at once and sends the RIC control request asynchronously, so exit 0 only means "queued". Judge the result on `./run1/e2-control-ledger.jsonl` (a header line, then one line per control with `viaNodeId`, `imsi`, `sourceCell`, `targetCell`, `outcome`, `cause`) and on the wire: an applied control is acknowledged with an E2SM-RC ControlOutcome Format 1, a refused one gets a RIC control failure with cause `control-failed-to-execute`. rc's log is not evidence. The pacer's schedule format is described in the header of `scripts/gates/pacer.py`.

Free run: without the pacer and the `--e2Pacing`, `--e2PacerPort` and `--e2GateTimeout` flags, call `rc-send.sh` directly while ns-3 runs. ns-3 applies the control after the next sample, at a step that depends on wall-clock timing, so the run does not repeat (unverified with the RIC; gate S0 checks free-run control against the null sink).

### Drive the TS xApp by hand

Use a VM at a green i2 state or later: the TS xApp switched to gRPC towards rc, A1 policy type 20008, and the stub QP xApp `stubqp`, both registered with appmgr. The per-run order is `rung_live` in `scripts/gates/ts-rung-lib.sh`; the commands are in `scripts/gates/ts-lib.sh` (unverified as a hand run).

1. Start the agents as above, then replace the TS xApp and stub pods: the TS xApp reads e2mgr's node list only at start-up. Follow `ts_stub_pods_reset` in `ts-lib.sh`: delete both pods, wait for new Ready pods, make sure both are still registered with appmgr (neither registers itself), replace the a1mediator pod, then restart rtmgr (it never reconnects to a replaced pod).
2. Set the A1 threshold. The TS xApp starts at 0 and never answers A1, so use a new policy instance id each time; its log then shows `Setting Threshold for A1-P value: 10%`:

    ```bash
    A1="http://$(kubectl -n ricplt get svc service-ricplt-a1mediator-http -o jsonpath='{.spec.clusterIP}'):10000/A1-P/v2"
    curl -s -X PUT -H 'Content-Type: application/json' -d '{"threshold": 10}' "$A1/policytypes/20008/policies/manual-1"
    ```

3. Load the stub's predictions by pod IP. The table format is in the header of `tools/rmr-peer/stub-qp-rmr-peer.py`: per UE, one answer per trigger, each a list of `["<cell key>", [dl, ul]]` with the serving cell first, integers only and no tie:

    ```bash
    STUB_IP=$(kubectl -n ricxapp get pods -o jsonpath='{range .items[*]}{.metadata.name} {.status.podIP}{"\n"}{end}' | awk '/^ricxapp-stubqp-/ {print $2}')
    curl -s "http://$STUB_IP:8080/health"                      # "ok" once its RMR is ready
    curl -sf -X PUT --data-binary @table.json "http://$STUB_IP:8080/table"
    ```

4. Start the RMR injector as `injector_start` in `ts-lib.sh` does: the rmr-peer image on the host network, with a static seed route that sends message type 30003 to the TS xApp's RMR Service, and its control port on 38510.
5. Run ns-3 (lock-step with this trigger in the pacer schedule, as the gates do, or free run) and trigger one UE by decimal IMSI:

    ```bash
    bash ~/harness/scripts/gates/send-rmr.sh 38510 anomaly 6
    ```

The TS xApp asks the stub for a prediction (30000), receives it (30002), and when the best other cell beats the serving cell by more than the threshold it calls rc's gRPC (`service-ricxapp-rc-grpc-server.ricxapp:7777`), addressing the control to the target cell's E2 node (recorded deviation P1). Check the ledger and the wire as in the rc loop. In R3′ the pacer's prepare hook (`scripts/gates/r3p-prepare.py`) replaces step 3 for every trigger: it certifies the InfluxDB window, computes the predictor's answer and loads it into the stub.

### Process hygiene

Run each long process in its own process group, record its PID and stop it by PGID. `pkill -x` cannot match the scenario binary because the kernel truncates `comm` to 15 characters; match the full path with `pgrep -f`. The gates verify at their end that no ns-3 process, agent container or `3847x` listener is left.

## 8. Troubleshooting

| Symptom | Cause | What to do |
|---|---|---|
| M1 fails: `file: command not found`, then "Helm archive download failed" | NIST's `install_k8s_and_helm.sh` validates the Helm tarball with `file(1)`, which the Ubuntu 24.04 server image lacks | Fixed on the Testbed fork (the script installs `file` itself). If you use another NIST tree, `apt-get install file` first. |
| M1 installer exits non-zero after a finished install | `full_install.sh` pipes its duration report into `bc(1)`, absent on noble, under `set -e` | Fixed on the fork (installs `bc`). Otherwise `apt-get install bc`. |
| An NIST call never returns, or a `tee` never sees EOF | NIST leaves chartmuseum (`helm servecm`) running as a daemon that inherits stdout | Never pipe NIST output. Redirect it to a file and filter the file afterwards (see `kpimon_install` in `scripts/gates/kpimon.sh`). |
| `sleep infinity \| cmd` hangs | bash waits for every pipeline member | Use `nist_run` (process substitution for stdin), not a pipeline. |
| A NIST script hangs at a `sudo` prompt | With a TTY, `start_sudo_refresh.sh` runs `sudo -v`, which prompts for `uc` | Run NIST scripts without a TTY (`< /dev/null`, no `ssh -t`, no `docker exec -it` wrapper). `kubectl exec -it` without a TTY only warns and runs. |
| Reference node or agent sits after `E2SetupRequest` and never gets a response | Right after a cold boot, ricplt pods are Ready before e2term has registered with e2mgr (`/v1/e2t/list` is `[]`). The request is accepted on SCTP but never answered. kpm_sim sends setup once and never resends. | Wait for an `e2tAddress` in e2mgr's `/v1/e2t/list` before starting a node (`gate_bringup ric` does). Do not restart e2term repeatedly; each roll empties the list again. The agent recovers by itself: its setup timeout makes it exit and restart. |
| kpimon install fails with `connection reset by peer` in `go build` | Transient failure fetching Go modules | `kpimon_install_retry` retries only on network-error signatures, with a separate log per attempt. Re-run otherwise. |
| After an agent was removed, e2mgr shows the node CONNECTED for minutes and kpimon never re-subscribes | `docker rm -f` killed the agent with its network namespace, so no SHUTDOWN or ABORT left | Stop agents with `stop_ns3_e2_agents.sh` (SIGTERM, graceful SCTP SHUTDOWN, then remove). |
| Influx CLI returns 401 after an InfluxDB pod restart | The in-pod CLI config is gone after a restart | Use the pod's `DOCKER_INFLUXDB_INIT_ADMIN_TOKEN`, expanded inside the pod so it is never printed (`influx_rows` in `kpimon.sh`). Never put the token on a command line or in a document. |
| tshark reports `Malformed Packet` (`epan/asn1.c:232`) on RICindication frames | noble's tshark 4.2.2 cannot dissect E2SM-KPM REAL records | Use the `tshark-kpm` image (`tools/tshark-kpm`, Debian trixie, tshark 4.4.x) behind the `/usr/local/bin/tshark` wrapper. Gates install it (`ensure_tshark_kpm` in `agents.sh`). |
| `ppa:wireshark-dev/stable` fails with HTTP 503 | Launchpad outage | Do not depend on the PPA; use the `tshark-kpm` image above. |
| `docker inspect` returns an empty container IP | Docker 29 removed the top-level `NetworkSettings.IPAddress` | Read the per-network IP under `NetworkSettings.Networks`. The gates do. |
| An M7 check counts a second "initial" INIT for a node, or the wrong node's traffic | Docker reassigns container IPs when agents restart (nodes swapped) | Attribute traffic by SCTP association, using the gNB-ID in that association's E2SetupRequest, never by IP (`tools/e2-evidence/`). |
| After an e2term pod delete, agents restart several times before indications resume | Agents retry INIT every few seconds, exit on the 10 s setup timeout, and Docker restarts them until the new e2term has registered with e2mgr | Expected. Recovery took minutes in the development run; `RestartCount` of 1 or more is a pass criterion in M7. |
| `vm-snapshot.sh create` says host free space is too low | The `/home` budget is not met | Delete your own earlier snapshots (never `fresh-install`) after the evidence is archived, or free host disk. If libvirt refuses to delete, stop and ask. |
| `vm-exec.sh` says the harness SHA is not on any origin branch | The SHA was not pushed | `git push origin HEAD`, then pass that SHA. |
| Anonymous clone on the VM fails | The harness repo is private | Make it public, or set `HARNESS_URL` to a reachable anonymous URL (unverified for URLs other than the default). |

## 9. Maintenance checks

```bash
scripts/gates/lint.sh
tools/e2-evidence/selftest.sh [dev smoke dir]
python3 -I O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/tests/lint-metric-map.py \
    O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/schema/metric-map.v1.json
```

`tools/kpimon-decode-harness/selftest.sh` needs `KP_E2SM` (kpimon's `e2sm/` directory with the `SIZE(8)` patch) and `TS_ORIG` (the pristine `TimeStamp.c`) in the environment. Its defaults point at a scratch directory of the original author and do not exist elsewhere.

# ns-O-RAN Installation

## ns-O-RAN on the OSC Near-RT RIC L-release (NIST v1.8.0)

This is the primary path of the repo. It runs the ns-O-RAN `scenario-zero` ns-3 simulation against the O-RAN Software Community Near-RT RIC **L release**, installed with the NIST O-RAN-Testbed-Automation v1.8.0 scripts (on our fork, branch `dev/l-release-nist180`). ns-3 no longer links asn1c or e2sim and no longer opens SCTP itself. Each simulated E2 node is served by its own small E2 agent that speaks E2AP and E2SM-KPM to the RIC. Gates M0 to M7 prove the chain from an empty VM to a multi-gNB run. Everything is scripted and reproducible from a VM snapshot. The control path (RC, M8) is not part of this scope yet.

### Architecture

```text
ns-3 scenario-zero --NDJSON over TCP 127.0.0.1:(38470+cellId)--> one ns3-e2-agent container per E2 node
   --E2AP/E2SM-KPM over SCTP--> e2term SCTP Service (ClusterIP, :36422) --> kpimon-go xApp --> InfluxDB
```

- ns-3 writes one JSON line per node per indication period to a local trace file and to the agent's TCP port.
- Each agent runs in its own Docker container (own network namespace), connects to the e2term Service, and sends KPM indications.
- kpimon-go decodes them with the TimeStamp `SIZE(8)` patch and writes InfluxDB points.
- Details and rationale: [docs/system-architecture-l-release.md](docs/system-architecture-l-release.md).

### Prerequisites

- A libvirt/KVM VM `ubuntu24.04` (Ubuntu 24.04.5, at least 8 vCPU, 14 GiB RAM, 60 GB free on `/`) with an offline snapshot named `fresh-install`. The VM user `uc` needs passwordless sudo. Defaults live in `scripts/vm/vm-common.sh` and can be overridden with `VM_DOMAIN`, `VM_SSH`, `VM_IMAGE_DIR`.
- An ssh alias for the VM (default `oran-kvm-2404`, key-based, no prompts). The host user manages `qemu:///system` without sudo.
- About 70 GB of free host disk under `/home`: a 20 GB reserve plus the per-gate snapshot growth listed in `scripts/run-to-m7.sh`.
- This repo pushed to a public GitHub repository. The VM clones it anonymously at the harness SHA you pass on the command line. The SHA must be on an `origin` branch.
- Internet access from the VM (apt, Docker registries, GitHub, the Go module proxy).

### Reproduce M0 to M7 with one command

```bash
git push origin HEAD                      # the harness SHA must be on origin
scripts/vm/vm-snapshot.sh revert fresh-install
scripts/run-to-m7.sh --harness-sha <pushed SHA> --run-prefix f
```

The chain runs each gate on the VM, copies the scrubbed evidence back, snapshots the VM, and stops at the first red gate. Per-gate timeouts are set in the `GATES` table of `scripts/run-to-m7.sh`. A green run ends with the snapshot `f7-rerun-green`. Use a run prefix that no existing snapshot uses (`l` for development runs, `f` for the re-run). The step-by-step guide, single-gate runs, and troubleshooting are in [docs/deployment-guide-l-release.md](docs/deployment-guide-l-release.md).

### What each gate proves

| Gate | Script | Proves |
|---|---|---|
| M0 | `gate-m0-host.sh`, `gate-m0-preflight.sh` | Host and VM facts, public harness repo, anonymous clone, snapshot revert semantics, package availability on noble, and that the NIST patches apply. |
| M1 | `gate-m1-ric-up.sh` | The Near-RT RIC installs on the L pins, all ricplt pods are Ready, and they stay stable for 10 minutes. |
| M2 | `gate-m2-refnode.sh` | NIST's reference node (kpm_sim) holds an SCTP association to the e2term ClusterIP for 5 minutes, and tshark decodes the E2 setup (the golden capture). |
| M3 | `gate-m3-xapps.sh` | Stock kpimon fails to decode an 8-byte TimeStamp cleanly; the `SIZE(8)` build decodes every header and message, shown with kpimon's own decoder. |
| M4 | `gate-m4-ns3-build.sh` | ns-3 builds from a clean pinned clone without e2sim or asn1c, the IPC emitter behaves, and the wall-time per simulated second is measured. |
| M5 | `gate-m5-agent-setup.sh` | One agent registers with e2term (RAN function 2, real OID), e2mgr lists it CONNECTED, and a graceful stop leaves it DISCONNECTED. |
| M6 | `gate-m6-kpm.sh` | Single-gNB KPM end to end: indications decode on the wire and through kpimon, and InfluxDB values equal the ns-3 trace bit for bit. |
| M7 | `gate-m7-multignb.sh` | Five agents (eNB 1, gNB 2 to 5) run for 15 minutes, then survive an e2term pod delete, reconnect, and resume indications. |

### Where evidence lands

- Per gate on the host: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/<gate>/<UTC timestamp>/` (override with `EVIDENCE_HOST_ROOT`). The verdict is `verdict.json` in that directory; `.last-mN` in the evidence root points at the latest one.
- Pcaps are not committed. Each evidence directory carries a `pcap-sha256.txt` manifest.
- Layout and the scrubber are explained in the deployment guide.

### Documents

| Document | Read it for |
|---|---|
| [docs/deployment-guide-l-release.md](docs/deployment-guide-l-release.md) | VM preparation, running gates and the chain, manual agent and ns-3 runs, troubleshooting. |
| [docs/system-architecture-l-release.md](docs/system-architecture-l-release.md) | Components, data flow, IPC schema, agent robustness, E2SM-KPM content, the kpimon patch, out-of-scope items. |
| [docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md](docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md) | The signed-off design record (stateful, dated). |
| [docs/linux-vm-setup-guide.md](docs/linux-vm-setup-guide.md) | Host-side libvirt/virtiofs setup. |

---

## Legacy (Bronze RIC)

> Everything below, down to "Reference material", describes the original Bronze-RIC flow (Ubuntu 20.04, `colosseum-near-rt-ric`, `oran-e2sim` linked into ns-3). It is kept for reference and is not the maintained path. It is not used by the gates above.

This repo helps you install and run **ns-O-RAN**: ns-3 5G simulation talking to an O-RAN near-real-time RIC (E2) over SCTP. It is based on the "5G ns-3 with O-RAN near-RT RIC bronze" tutorial and the Lacava et al. ns-O-RAN and Traffic Steering papers.

---

## What is in this repo

- **Near-RT RIC (Bronze)**: Docker stack (e2term, e2mgr, db, e2rtmansim, sample xApp) from `colosseum-near-rt-ric`.
- **ns-3 + O-RAN**: `ns-3-mmwave-oran` (5G mmWave, E2) and `oran-e2sim` (E2 encode/decode, SCTP).
- **Docs**: `docs/` for reports and guides. `converted/` holds the tutorial HTML and paper PDFs for reference.

---

## Target environment

- **VM**: Ubuntu 20.04.6, with Docker (VirtualBox, VMware, or libvirt/KVM)
- **Repo in VM**: `~/ns-O-RAN-installation`

> **Note for Linux users**: If you're using libvirt/KVM with virtiofs, see `docs/linux-vm-setup-guide.md` for host setup instructions.

---

## Repo layout

| Path | Role |
|------|------|
| `colosseum-near-rt-ric/` | RIC Docker images and `setup-scripts/` to run the RIC |
| `ns-3-mmwave-oran/` | ns-3 with mmWave and O-RAN E2 (scenarios in `scratch/`) |
| `oran-e2sim/` | E2 library used by ns-3 to talk to e2term |
| `docs/` | Project docs and connectivity/status reports |
| `converted/` | Tutorial and papers (HTML/PDF) |
| `CLAUDE.md`, `AGENTS.md` | Rules for AI coding agents |

`colosseum-near-rt-ric`, `ns-3-mmwave-oran`, and `oran-e2sim` are git submodules.

---

## Quick start (on the VM)

### 1. Repo and submodules

```bash
git clone git@github.com:thienandangthanh/ns-o-ran-installation.git ~/ns-O-RAN-installation

cd ~/ns-O-RAN-installation
git submodule update --init --recursive
ln -s ../../oran-interface ./ns-3-mmwave-oran/contrib/oran-interface
```

### 2. Start the near-RT RIC (Docker)

```bash
cd ~/ns-O-RAN-installation/colosseum-near-rt-ric/setup-scripts
# One-time: pull and tag RIC images
./import-wines-images.sh
# Build and start RIC (db, e2mgr, e2rtmansim, e2term). SCTP on 10.0.2.1:36422, e2term at 10.0.2.10
./setup-ric-bronze.sh
```

Check: `docker ps` (db, e2mgr, e2rtmansim, e2term running), `ping 10.0.2.10`, `ss -lnp | grep 36422`.

### 3. Build oran-e2sim and ns-3

```bash
cd ~/ns-O-RAN-installation/ns-3-mmwave-oran
./e2term-ns3-build.sh
```

This builds `oran-e2sim` then ns-3. Use `./ns3` or `./waf` as in the ns-3 docs.

### 4. Run ns-3 (scenario-zero) toward the RIC

```bash
cd ~/ns-O-RAN-installation/ns-3-mmwave-oran
./ns3 run scratch/scenario-zero.cc -- --e2TermIp=10.0.2.10 --enableE2FileLogging=false --simTime=10
```

`e2TermIp=10.0.2.10` is the e2term IP in the `ric` network (see `colosseum-near-rt-ric/setup-scripts/setup-lib.sh`).

### 5. (Optional) Sample xApp

```bash
cd ~/ns-O-RAN-installation/colosseum-near-rt-ric/setup-scripts
./setup-sample-xapp.sh ns-o-ran
# then: ./start-xapp-ns-o-ran.sh  (or follow start-xapp.sh for your gNB ID)
```

---

## Main config (setup-lib.sh)

| Item | Value |
|------|--------|
| RIC subnet | 10.0.2.0/24 |
| e2term IP | 10.0.2.10 |
| e2term SCTP | 36422 |
| e2mgr | 10.0.2.11 |
| db (Redis) | 10.0.2.12 |
| e2rtmansim | 10.0.2.15 |
| sample xApp | 10.0.2.24 |

---

## Reference material

- **Tutorial**: "5G ns-3 with O-RAN near-RT RIC bronze" (see `converted/`).
- **Papers**: Lacava et al. "ns-O-RAN: Simulating O-RAN 5G Systems in ns-3" (2023); "Programmable and Customized Intelligence for Traffic Steering in 5G Networks Using Open RAN Architectures" (2024). In `converted/`.
- **OpenRAN Gym**: https://openrangym.com/tutorials/ns-o-ran

---

## Working on this repo (team and AI agents)

1. **Read this README first** for context.
2. **Agents**: Follow `CLAUDE.md` or `AGENTS.md`; use the workflows under `./.claude/rules/` and `./.opencode/`.
3. **Docs**: Put important project docs in `docs/` and keep them updated.
4. **Code**: Follow `./.claude/rules/development-rules.md` (e.g. YAGNI, KISS, DRY; file naming; tests before push).

---

## Submodules

| Submodule | URL | Role |
|-----------|-----|------|
| colosseum-near-rt-ric | wineslab/colosseum-near-rt-ric (branch ns-o-ran) | RIC Docker and scripts |
| oran-e2sim | wineslab/ns-o-ran-e2-sim | E2 sim for ns-3 |
| ns-3-mmwave-oran | wineslab/ns-o-ran-ns3-mmwave | ns-3 + mmWave + O-RAN E2 |

After `git clone`, run `git submodule update --init --recursive`. When pulling, update submodules if the expected commits changed.

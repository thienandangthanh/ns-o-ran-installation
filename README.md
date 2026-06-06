# ns-O-RAN Installation

This repo helps you install and run **ns-O-RAN**: ns-3 5G simulation talking to an O-RAN near-real-time RIC (E2) over SCTP. It is based on the "5G ns-3 with O-RAN near-RT RIC bronze" tutorial and the Lacava et al. ns-O-RAN and Traffic Steering papers.

---

## What is in this repo

- **Near-RT RIC (Bronze)**: Docker stack (e2term, e2mgr, db, e2rtmansim, sample xApp) from `colosseum-near-rt-ric`.
- **ns-3 + O-RAN**: `ns-3-mmwave-oran` (5G mmWave, E2) and `oran-e2sim` (E2 encode/decode, SCTP).
- **Docs**: `docs/` for reports and guides. `converted/` holds the tutorial HTML and paper PDFs for reference.

---

## Target environment

Two deployment options are now supported:

### Option 1: Bronze Near-RT RIC (Legacy)
- **RIC**: Docker stack on same VM (`ric` network, 10.0.2.0/24)
- **VM**: Ubuntu 20.04.6, with Docker (VirtualBox, VMware, or libvirt/KVM)
- **Repo in VM**: `~/ns-O-RAN-installation`

### Option 2: OSC L-release Near-RT RIC (L-release, v3 protocol)
- **RIC**: Kubernetes cluster on dedicated VM (`oran-kvm-2`, node IP 192.168.122.78)
- **ns-3**: Co-located on same VM (virtiofs-mounted repo)
- **Namespace**: `ricplt` (e2term, e2mgr, ricxapp, kpimon-go)
- **E2 protocol**: E2AP v03.01, E2SM-KPM v03.00

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

`colosseum-near-rt-ric`, `ns-3-mmwave-oran`, and `oran-e2sim` are git submodules.

---

## Prerequisites

Install these on the VM before cloning and building (based on the [OpenRAN Gym ns-O-RAN tutorial](https://openrangym.com/tutorials/ns-o-ran)).

### Docker

Docker is required to host the near-RT RIC on localhost. Follow the official guide for Ubuntu:

- https://docs.docker.com/engine/install/ubuntu/#installation-methods

> The Docker Engine installation steps are maintained by Docker and may change over time, so always follow the official guide above rather than a copy pinned here. After installing, add your user to the `docker` group (`sudo usermod -aG docker $USER`, then re-login) so you can run Docker without `sudo`.

### Build dependencies (e2sim and ns-3)

Update the package index, then install the build tools and libraries:

```bash
sudo apt-get update

# Dependencies for oran-e2sim (E2 encode/decode, SCTP)
sudo apt-get install -y build-essential git cmake libsctp-dev autoconf automake libtool bison flex libboost-all-dev

# Dependencies for ns-3
sudo apt-get install -y g++ python3
```

| Package | Needed by | Purpose |
|---------|-----------|---------|
| `build-essential` | e2sim, ns-3 | gcc/g++/make toolchain |
| `git` | both | clone repo and submodules |
| `cmake` | e2sim | build system |
| `libsctp-dev` | e2sim | SCTP transport for E2 |
| `autoconf`, `automake`, `libtool` | e2sim | autotools build |
| `bison`, `flex` | e2sim | ASN.1 parser generation |
| `libboost-all-dev` | e2sim | Boost libraries |
| `g++`, `python3` | ns-3 | compiler and ns-3 (`./ns3`) tooling |

> The build is driven through the bundled `./ns3` wrapper (see `e2term-ns3-build.sh`); you do not need to install ns-3 separately.

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

This builds `oran-e2sim` then ns-3. Use `./ns3` as in the ns-3 docs.

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

## L-release Quick Start (E2AP v03.01 / E2SM-KPM v03.00)

**Prerequisites**: ns-3 and e2sim build dependencies (same as Bronze); L-release RIC deployed on `oran-kvm-2`.

### Build

The build order differs from Bronze due to e2sim dependencies:

```bash
cd ~/ns-O-RAN-installation

# 1. Build libe2sim from OSC e2-interface (branch dev/l-release)
cd oran-e2sim/e2sim
cmake . && make e2sim_shared && sudo make install && sudo ldconfig

# 2. CRITICAL: Manually install e2sim.hpp (make install does not refresh existing files)
sudo cp src/base/e2sim.hpp /usr/local/include/e2sim/

# 3. Build asn1c static archive (libe2sim does not bundle asn_DEF_* symbols)
cd ../asn1c
gcc -O2 -fPIC -I. -c *.c
ar rcs /usr/local/lib/libasn1c_e2.a *.o
sudo cp /usr/local/lib/libasn1c_e2.a /usr/local/lib/

# 4. Build ns-3 (branch dev/l-release)
cd ~/ns-O-RAN-installation/ns-3-mmwave-oran
./ns3 build
```

### Run scenario-zero against L-release RIC

**Before each run**: Clear stale RNIB state and restart kpimon-go pod (force subscription retry):

```bash
# SSH to RIC VM
ssh oran-kvm-2

# Clear RNIB
curl -X PUT http://localhost:3800/v1/nodeb/shutdown

# Restart kpimon-go pod (e2term POD IP 10.244.0.48 must be reachable from ns-3 VM)
kubectl -n ricxapp delete pod <kpimon-pod-name>
```

**Run ns-3 scenario-zero**:

```bash
cd ~/ns-O-RAN-installation/ns-3-mmwave-oran
./ns3 run "scratch/scenario-zero \
  --enableE2FileLogging=false \
  --e2TermIp=10.244.0.48 \
  --e2TermPort=36422 \
  --simTime=20 \
  --reducedPmValues=1 \
  --e2du=1 \
  --e2cuUp=0 \
  --e2cuCp=0"
```

**Key points**:
- e2term **POD IP** (`10.244.0.48:36422`), not NodePort (`192.168.122.78:32222`). The NodePort IPVS SNAT resets persistent SCTP associations.
- `reducedPmValues=1`: Emits 5 cell-level KPM metrics (DRB/RRU/TB DL counts); matches the advertised descriptor (kpimon gate: metric count == descriptor count).
- `simTime=20`: Wall-clock ~40–60 sec (1 sec sim-time ≈ 2–3 wall-clock sec). Enough for kpimon startup + subscription + indications.

### Validation

All milestones (M1 SCTP, M2 E2 Setup, M3 RAN functions, M4 subscription, M5 indication, M6 real KPM decode) are green. See `scripts/l-release-validation/` for the harness and evidence pcaps:

```bash
cd ~/ns-O-RAN-installation
scripts/l-release-validation/assert-pcap.sh captures/phase7-m5m6-scenario-zero.pcap \
  sctp-init e2setup-response sub-response ric-indication kpm-v3
```

Expected output: `PASS` for all 4 assertions.

### Submodule branches

L-release migration spans three submodule forks (all on `dev/l-release`):
- `oran-e2sim`: OSC `e2-interface` rebased; per-instance SCTP source-port fix
- `oran-interface`: v3 model port (KPM indication headers/messages), funcId=2 registration
- `ns3-mmwave-oran` (super-repo): v3 flat-message KPM model, malloc/free memory contract fixes, reduced-PM support

Run `git submodule update --init --recursive` to sync to the branch pins.

---

## Python `nsoran` package (ns-o-ran-gym)

To use the Python environments from the `ns-o-ran-gym` submodule (e.g., `TrafficSteeringEnv` and the `traffic_steering.py` example), you need to build and install the `nsoran` package.

```bash
cd ~/ns-O-RAN-installation
python3 -m pip install --user uv
uv venv
source .venv/bin/activate
uv sync

cd ns-o-ran-gym
pip install --user hatch && hatch build

cd ~/ns-O-RAN-installation
uv pip install ./ns-o-ran-gym/dist/nsoran-0.0.2.tar.gz
```

Verify the install:

```bash
cd ~/ns-O-RAN-installation
source .venv/bin/activate
python3 - << 'EOF'
import nsoran, sys
print("nsoran OK")
print(sys.version)
EOF
```

Once this is done, follow `docs/run-ns-o-ran-gym-traffic-steering-example.md` to run the `traffic_steering.py` example.

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
- **Papers**:
  - Lacava et al. "ns-O-RAN: Simulating O-RAN 5G Systems in ns-3" (2023)
  - Lacava et al. "Programmable and Customized Intelligence for Traffic Steering in 5G Networks Using Open RAN Architectures" (2024).
  - Bonati et al. "OpenRAN Gym: AI/ML Development, Data Collection, and Testing for O-RAN on PAWR Platforms" (2023)
- **OpenRAN Gym**: https://openrangym.com/tutorials/ns-o-ran

---

## Contributing

1. **Read this README first** for context.
2. See `docs/CONTRIBUTING.md` for code formatting, pre-commit hooks, and development workflow.
3. Put important project docs in `docs/` and keep them updated.

---

## Submodules

| Submodule | URL | Role |
|-----------|-----|------|
| colosseum-near-rt-ric | wineslab/colosseum-near-rt-ric (branch ns-o-ran) | RIC Docker and scripts |
| oran-e2sim | wineslab/ns-o-ran-e2-sim | E2 sim for ns-3 |
| ns-3-mmwave-oran | wineslab/ns-o-ran-ns3-mmwave | ns-3 + mmWave + O-RAN E2 |
| oran-interface | o-ran-sc/sim-ns3-o-ran-e2 | ns-3 module for multiple O-RAN E2 interface terminations |
| ns-o-ran-gym | wineslab/ns-o-ran-gym | Gymnasium RL environment for ns-O-RAN |

After `git clone`, run `git submodule update --init --recursive`. When pulling, update submodules if the expected commits changed.

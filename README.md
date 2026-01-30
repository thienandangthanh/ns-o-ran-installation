# ns-O-RAN Installation

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

## Working on this repo (team and AI agents)

1. **Read this README first** for context.
2. **Contributors**: See `docs/CONTRIBUTING.md` for code formatting, pre-commit hooks, and development workflow.
3. **Agents**: Follow `CLAUDE.md` or `AGENTS.md`; use the workflows under `./.claude/rules/` and `./.opencode/`.
4. **Docs**: Put important project docs in `docs/` and keep them updated.
5. **Code**: Follow `./.claude/rules/development-rules.md` (e.g. YAGNI, KISS, DRY; file naming; tests before push).

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

# ns-O-RAN Installation

This repo helps you install and run **ns-O-RAN**: ns-3 5G simulation talking to an O-RAN near-real-time RIC (E2) over SCTP. It is based on the "5G ns-3 with O-RAN near-RT RIC bronze" tutorial and the Lacava et al. ns-O-RAN and Traffic Steering papers.

---

## What is in this repo

- **Near-RT RIC (Bronze)**: Docker stack (e2term, e2mgr, db, e2rtmansim, sample xApp) from `colosseum-near-rt-ric`.
- **ns-3 + O-RAN**: `ns-3-mmwave-oran` (5G mmWave, E2) and `oran-e2sim` (E2 encode/decode, SCTP).
- **Docs**: `docs/` for reports and guides. `converted/` holds the tutorial HTML and paper PDFs for reference.

---

## Target environment

- **VM**: `ssh oran-kvm`
- **Repo in VM**: `~/ns-O-RAN-installation` (shared from host via virtiofs)
- **VM OS**: Ubuntu 20.04.6, with Docker

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
cd ~/ns-O-RAN-installation
git submodule update --init --recursive
```

If the repo is not there yet, clone it first then run the above. With virtiofs from the host, the tree is already at this path; you may only need to init and update submodules.

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

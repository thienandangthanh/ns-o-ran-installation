## Running the ns-O-RAN-Gym Traffic Steering Example

This guide shows how to run the `traffic_steering.py` example from `ns-o-ran-gym` on the `oran-kvm` VM, assuming you already:

- Have the repo at `~/ns-O-RAN-installation` inside the VM.
- Can SSH into the VM as `ssh oran-kvm`.
- Have already started the near-RT RIC and successfully run `scenario-zero` from ns-3 toward the RIC (as in `README.md`).
- Have built and installed the `nsoran` Python package using the steps in `docs/python-ns-oran-gym.md`.

The flow follows the OpenRAN Gym paper: start the O-RAN control architecture (ColO-RAN / near-RT RIC), attach the softwarized RAN (here ns-3 with E2 termination), then run a data-driven control loop (here via the Gym environment).

---

### Important: this example is Gym mode (file+semaphore control), not a near-RT RIC xApp

`ns-o-ran-gym/examples/traffic_steering.py` is a **smoke-test/demo** that:
- launches `scenario-one` locally via `NsOranEnv` (subprocess),
- **samples random actions** from the environment action space,
- writes actions to `ts_actions_for_ns3.csv`,
- reads KPM-like outputs from ns-3 output files (e.g., `cu-*-cell-*.txt`, `du-cell-*.txt`) into SQLite.

It does **not** subscribe to E2SM-KPM or send E2SM-RC control via E2AP as a real xApp would.

If your goal is a **real RIC xApp loop**, keep this doc only as a quick sanity check that ns-3 + `nsoran` works, then follow the xApp workflow once it is added (see `docs/python-xapp-e2sm-kpm-rc.md`).

---

### 1. Ensure RIC and ns-3 are ready on the VM

SSH into the VM:

```bash
ssh oran-kvm
```

Inside the VM:

```bash
cd ~/ns-O-RAN-installation
```

- **Check RIC stack** is running (Docker containers for `e2term`, `e2mgr`, `e2rtmansim`, `db`):

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

If the RIC is not running, (re)start it:

```bash
cd colosseum-near-rt-ric/setup-scripts
./setup-ric-bronze.sh
```

- **Check ns-3 + oran-e2sim build** is available:

```bash
cd ~/ns-O-RAN-installation/ns-3-mmwave-oran
ls ./ns3 ./waf
```

Rebuild if needed:

```bash
./e2term-ns3-build.sh
```

You should already have verified the E2 path by running:

```bash
./ns3 run scratch/scenario-zero.cc -- --e2TermIp=10.0.2.10 --enableE2FileLogging=false --simTime=10
```

---

### 2. Create/activate the Python environment and verify `nsoran`

On the VM we use `uv` with a `.venv` in the repo root.

From the VM home:

```bash
cd ~/ns-O-RAN-installation
python3 -m pip install --user uv
uv venv          # creates .venv if it does not exist
source .venv/bin/activate
uv sync
```

Build and install `nsoran` (once):

```bash
cd ~/ns-O-RAN-installation/ns-o-ran-gym
pip install --user hatch && hatch build

uv pip install ./dist/nsoran-0.0.2.tar.gz
```

Verify that `nsoran` is importable:

```bash
cd ~/ns-O-RAN-installation
source .venv/bin/activate
python3 - << 'EOF'
import nsoran, sys
print("nsoran OK")
print(sys.version)
EOF
```

---

### 3. Understand the traffic steering example configuration

The `traffic_steering.py` example uses:

- Environment class: `TrafficSteeringEnv` in `src/environments/ts_env.py`.
- Default configuration file: `src/environments/scenario_configurations/ts_use_case.json`.
- Default ns-3 path: `/workspace/ns3-mmwave-oran` (container-style path used by upstream OpenRAN Gym).

In this repo/VM layout:

- The ns-3 directory is at `~/ns-O-RAN-installation/ns-3-mmwave-oran`.
- The example and configs are inside `~/ns-O-RAN-installation/ns-o-ran-gym`.

So when calling `traffic_steering.py` we must override `--ns3_path` to point at the actual ns-3 directory on the VM.

---

### 4. Run the traffic steering example

Still inside the activated virtual environment on the VM:

```bash
cd ~/ns-O-RAN-installation/ns-o-ran-gym

python examples/traffic_steering.py \
  --config src/environments/scenario_configurations/ts_use_case.json \
  --output_folder output_ts_example \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --num_steps 1000 \
  --optimized \
  --verbose
```

Notes:

- **`--optimized`**: matches the OpenRAN Gym design, using optimized ns-3 builds where available.
- **`--verbose`**: prints detailed status, actions, and observation traces to the terminal.
- The environment will:
  - Launch an ns-3 simulation with the traffic steering scenario.
  - Perform `env.reset()` to sync with the ns-3 process.
  - Iterate for up to `num_steps`, sampling random actions from the action space.

You should see logs like:

- `Creating TS Environment`
- `Environment Created!`
- `Launch reset ... done`
- Per-step logs with actions, observations, rewards, and termination flags.

---

### 5. Verifying successful execution

Consider the run successful if:

- The script exits without Python exceptions.
- The log shows at least one completed step (`Step 2 ... done`) and prints observations and rewards.
- The run terminates due to `terminated` or `truncated` being `True`, or after `num_steps` iterations.
- The `output_ts_example` directory is created and populated with CSVs and logs produced by `nsoran` / the `TrafficSteeringEnv`.

On the VM:

```bash
cd ~/ns-O-RAN-installation/ns-o-ran-gym
ls output_ts_example
```

You should see one or more subdirectories with timestamps and CSV files corresponding to KPM traces and environment logs.

---
### 6. Cleanup

After the run finishes, you can:

- Deactivate the virtualenv:

```bash
deactivate
```

- Stop the RIC stack if you are done experimenting:

```bash
cd ~/ns-O-RAN-installation/colosseum-near-rt-ric/setup-scripts
docker rm $(docker stop db e2mgr e2rtmansim e2term)
```

Refer back to the OpenRAN Gym paper "OpenRAN Gym: AI/ML Development, Data Collection, and Testing for O-RAN on PAWR Platforms" (Bonati et al., 2023) for the conceptual mapping between:
- Data collection and control framework (SCOPE / ns-3 in this repo),
- O-RAN control architecture (ColO-RAN / near-RT RIC and E2 termination),
- and the xApp-like data-driven logic embedded here in the `TrafficSteeringEnv` Gym environment.

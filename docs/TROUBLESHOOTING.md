## Troubleshooting Guide

This file is the one-stop place for common setup and runtime issues in this repo.

If a problem is complex or scenario-specific, this file will link to a dedicated guide in `docs/`.

---

### 1. Python / `uv` / virtual environment issues

- **`python: command not found`**
  - Use `python3` instead:
    - `python3 -m pip install --user uv`

- **`uv` not found after install**
  - Ensure your user-local bin is on `PATH`:
    - `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`
    - `source ~/.bashrc`
  - Then run:
    - `uv venv`
    - `source .venv/bin/activate`
    - `uv sync`

- **Virtual environment confusion**
  - On the VM, this repo assumes:
    - Venv directory: `.venv` in `~/ns-O-RAN-installation`
    - Activate with:
      - `cd ~/ns-O-RAN-installation`
      - `source .venv/bin/activate`

---

### 2. Installing the `nsoran` package (ns-o-ran-gym)

If you see `ModuleNotFoundError: No module named 'nsoran'` or issues importing `environments.ts_env`, follow this once on the VM:

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

Verify:

```bash
cd ~/ns-O-RAN-installation
source .venv/bin/activate
python3 - << 'EOF'
import nsoran, sys
print("nsoran OK")
print(sys.version)
EOF
```

If this still fails, ensure the `dist/` directory inside `ns-o-ran-gym` contains `nsoran-0.0.2.tar.gz`.

---

### 3. ns-3 / RIC connectivity issues

- **Symptom:** ns-3 scenario (e.g. `scenario-zero` or `traffic_steering`) starts but no E2 traffic / SCTP errors.

Check the RIC containers:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

You should see `e2term`, `e2mgr`, `e2rtmansim`, `db` all `Up`.

If not, (re)start:

```bash
cd ~/ns-O-RAN-installation/colosseum-near-rt-ric/setup-scripts
./setup-ric-bronze.sh
```

Check the SCTP port:

```bash
ss -lnp | grep 36422
```

Make sure you pass the correct RIC IP to ns-3 (for `scenario-zero` this is `--e2TermIp=10.0.2.10`).

---

### 4. `traffic_steering.py` example (ns-o-ran-gym)

For detailed run instructions see `docs/run-ns-o-ran-gym-traffic-steering-example.md`.

Common specific errors:

- **`Cannot open 'src/environments/scenario_configurations/ts_use_case.json' file`**
  - Run from the `ns-o-ran-gym` root:
    - `cd ~/ns-O-RAN-installation/ns-o-ran-gym`
  - Or pass an absolute path:
    - `--config ~/ns-O-RAN-installation/ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case.json`

- **`ModuleNotFoundError` for `nsoran` or `environments.ts_env`**
  - Activate the venv:
    - `source ~/ns-O-RAN-installation/.venv/bin/activate`
  - Ensure you are in `ns-o-ran-gym` when running:
    - `cd ~/ns-O-RAN-installation/ns-o-ran-gym`
  - Reinstall `nsoran` as in section 2 if needed.

- **ns-3 path errors**
  - Make sure `--ns3_path` matches:
    - `~/ns-O-RAN-installation/ns-3-mmwave-oran`
  - Confirm the wrapper is executable:
    - `cd ~/ns-O-RAN-installation/ns-3-mmwave-oran && ./ns3 --help`

---

### 5. RIC teardown / cleanup

To cleanly stop the RIC containers after experiments on the VM:

```bash
docker rm $(docker stop db e2mgr e2rtmansim e2term)
```

If that fails (e.g., containers already stopped), inspect with `docker ps -a` and remove them manually using `docker rm`.


## PPO baseline training pipeline (Traffic Steering)

This repo does not yet include the paper’s CQL/REM implementation. The first step is a **robust on-policy baseline** using **PPO** with **Stable-Baselines3** (SB3), trained against the `TrafficSteeringEnv`.

### What PPO is training against (important)

PPO trains in **Gym mode**:
- Actions are written to `ts_actions_for_ns3.csv` (file control).
- Synchronization is done via semaphores (`useSemaphores=1`).
- KPM-like metrics are consumed from ns-3 output files into SQLite.

This is **not** the same as deploying a near-RT RIC xApp. Use PPO here to validate:
- observation design,
- action mapping,
- reward shape and stability,
- offline dataset collection.

### Install RL dependencies (on the VM)

Inside the repo venv on the VM:

```bash
cd ~/ns-O-RAN-installation
source .venv/bin/activate

# SB3 + torch + tensorboard
uv pip install stable-baselines3 torch tensorboard
```

### Training script

Use:
- `scripts/train-ppo-traffic-steering.py`

Example:

```bash
cd ~/ns-O-RAN-installation
source .venv/bin/activate

python scripts/train-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case.json \
  --output_dir output/ppo_ts \
  --total_timesteps 20000 \
  --seed 0 \
  --optimized \
  --skip_configuration
```

### Evaluation script

Use:
- `scripts/evaluate-ppo-traffic-steering.py`

Example:

```bash
python scripts/evaluate-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case.json \
  --model_path output/ppo_ts/model.zip \
  --vecnormalize_path output/ppo_ts/vecnormalize.pkl \
  --episodes 5 \
  --optimized \
  --skip_configuration
```

### Practical notes for “small-scale first”

- **Episodes are expensive**: each episode starts a new ns-3 run.
- If PPO “does nothing useful”, first increase data per episode:
  - raise `simTime`,
  - keep `indicationPeriodicity` reasonable (e.g., 0.1s),
  - increase `num_steps` only matters for the old demo script; PPO drives env until ns-3 ends.


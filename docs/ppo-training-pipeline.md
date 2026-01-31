## PPO baseline training pipeline (Traffic Steering)

This repo does not yet include the paper's CQL/REM implementation. The first step is a **robust on-policy baseline** using **PPO** with **Stable-Baselines3** (SB3), trained against the `TrafficSteeringEnv`.

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

### Training script

Use:
- `scripts/train-ppo-traffic-steering.py`

Example:

```bash
cd ~/ns-O-RAN-installation
source .venv/bin/activate

python scripts/train-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_small.json \
  --output_dir output/ppo_ts \
  --total_timesteps 500 \
  --seed 0 \
  --optimized \
  --tensorboard
```

**Important flags:**
- `--optimized`: Use optimized ns-3 build (faster, required for reasonable training times)
- `--tensorboard`: Enable tensorboard logging for monitoring training progress
- `--verbose_env`: Enable detailed environment logging (useful for debugging)
- `--n_envs N`: Number of parallel environments (default: 1, recommended: 4-8 for multi-core systems)

### Evaluation script

Use:
- `scripts/evaluate-ppo-traffic-steering.py`

Example:

```bash
python scripts/evaluate-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_small.json \
  --model_path output/ppo_ts/run-*/model.zip \
  --vecnormalize_path output/ppo_ts/run-*/vecnormalize.pkl \
  --episodes 3 \
  --optimized
```

**Note**: Use shell glob or specify the exact run directory path for model and vecnormalize files.

### Configuration Presets

Three configuration presets are provided to balance training speed vs data richness:

#### 1. Small (Fast Iteration)
- **File**: `ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_small.json`
- **Settings**: `simTime=2s`, `ues=1` per gNB, `indicationPeriodicity=0.1s`
- **Steps per episode**: ~19 steps
- **Episode runtime**: ~50-60 seconds per episode
- **Use case**: Quick debugging, smoke tests, rapid prototyping
- **Example**: 200 timesteps ≈ 10-11 episodes ≈ 10 minutes

#### 2. Medium (Balanced)
- **File**: `ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_medium.json`
- **Settings**: `simTime=5s`, `ues=2` per gNB, `indicationPeriodicity=0.1s`
- **Steps per episode**: ~49 steps
- **Episode runtime**: ~2-3 minutes per episode
- **Use case**: Standard training runs, algorithm comparison
- **Example**: 5000 timesteps ≈ 100 episodes ≈ 4-5 hours

#### 3. Default (Original)
- **File**: `ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case.json`
- **Settings**: `simTime=0.7s`, `ues=2` per gNB, `indicationPeriodicity=0.1s`
- **Steps per episode**: ~6 steps
- **Episode runtime**: ~35-40 seconds per episode
- **Use case**: Reproducing paper results (very short episodes)
- **Note**: Too short for effective training - use small or medium instead

**Recommendation for daily development**: Use `ts_use_case_small.json` for rapid iteration.

### Integration Points Validation

The following integration points have been validated:

1. **FlattenObservation wrapper**: Successfully flattens the `Box(shape=(n_ues, n_features))` observation from `TrafficSteeringEnv` into a 1D vector for MlpPolicy.

2. **MultiDiscrete action space**: PPO's MlpPolicy correctly handles the `MultiDiscrete([7] * n_ues)` action space. Each UE gets an independent action (0=no HO, 1-6=target cell).

3. **VecNormalize**: Observation normalization works correctly. Running statistics are collected and saved to `vecnormalize.pkl` for evaluation.

4. **Monitor wrapper**: Episode returns and lengths are logged to `monitor.csv` for analysis.

5. **Tensorboard**: Training metrics are logged when `--tensorboard` flag is used. View with:
   ```bash
   tensorboard --logdir output/ppo_ts/run-*/tb
   ```

### Parallel Training (Multi-Core Acceleration)

**Problem:** By default, training uses only 1 CPU core, leaving other cores idle.

**Solution:** Use the `--n_envs` flag to run multiple parallel environments:

```bash
python scripts/train-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_medium.json \
  --output_dir output/ppo_ts_medium \
  --total_timesteps 10000 \
  --seed 0 \
  --optimized \
  --tensorboard \
  --n_envs 8
```

**How it works:**
- Each environment runs in its own subprocess (using `SubprocVecEnv`)
- Each subprocess runs an independent ns-3 simulation
- PPO collects experiences from all environments simultaneously
- Effective speedup: ~N× faster (where N = number of environments)

**Recommendations:**
- **For 16 cores + 8GB RAM**: Use `--n_envs 4` to `--n_envs 8`
  - Each ns-3 simulation uses ~500MB-1GB RAM
  - Leave headroom for OS and PPO training
- **Memory consideration**: `n_envs × (ns-3 RAM + output files)` must fit in available RAM
- **CPU consideration**: Optimal `n_envs` ≈ `cpu_count - 2` (leave cores for OS)

**Trade-offs:**
- **Pros**: 
  - Dramatic speedup (8 envs = ~8× faster training)
  - Better exploration (diverse experiences from parallel envs)
  - More efficient CPU utilization
- **Cons**: 
  - Higher RAM usage
  - Each environment creates separate output directories
  - Slightly more complex debugging (multiple simulation logs)

**Expected performance improvement:**
- Single env: 500 timesteps in ~22 minutes (from your test)
- 8 parallel envs: 500 timesteps in ~3-4 minutes (estimated)
- 8 parallel envs: 10,000 timesteps in ~60-80 minutes (estimated for medium preset)

**Note:** This parallelization is at the **environment level** (multiple ns-3 simulations), not within ns-3 itself. ns-3 build already uses all cores (`-j` flag), but individual simulations are single-threaded.

### Troubleshooting

#### Issue: Training extremely slow

**Symptom:** Episodes take 5+ minutes each, or only 1-2 episodes complete in 10 minutes.

**Causes:**
- `simTime` is too large (e.g., 10s+)
- ns-3 simulation time scales roughly linearly with `simTime`
- Each episode launches a new ns-3 process (expensive startup)

**Fix:**
- Use `ts_use_case_small.json` with `simTime=2s` for development
- Consider `simTime ≤ 5s` for reasonable training times
- GPU access won't help (bottleneck is ns-3 CPU simulation, not NN training)

**Expected performance:**
- `simTime=0.7s`: ~35-40 seconds per episode
- `simTime=2s`: ~50-60 seconds per episode
- `simTime=5s`: ~2-3 minutes per episode
- `simTime=10s`: ~8-10 minutes per episode

#### Issue: Training times out before saving model

**Symptom:** No `model.zip` or `vecnormalize.pkl` files created.

**Cause:** Training interrupted before completion (timeout, Ctrl+C, system issue).

**Fix:**
- Reduce `--total_timesteps` for smoke tests (e.g., 200-500)
- Use smaller config (`ts_use_case_small.json`)
- Let training complete naturally (model is saved at the end)

#### Issue: Negative rewards

**Symptom:** All episode returns in `monitor.csv` are negative (e.g., -70 to -90).

**Status:** This is **expected** behavior, not a bug.

**Explanation:**
- The reward function penalizes handovers and suboptimal throughput
- Random or untrained policies will have negative returns
- As the policy improves, rewards should increase toward positive values
- Initial episodes may show high variance as VecNormalize collects statistics

#### Issue: Very short episodes (6 steps)

**Symptom:** `monitor.csv` shows `l=6` for all episodes.

**Cause:** Using default config with `simTime=0.7s` and `indicationPeriodicity=0.1s` gives 7 time points (0, 0.1, 0.2, ..., 0.6), but first observation is used for initialization.

**Fix:** Use `ts_use_case_small.json` or `ts_use_case_medium.json` for longer episodes.

#### Issue: Progress bar shows numbers exceeding total_timesteps limit

**Symptom:** Progress bar displays something like `680/500` and keeps counting up, or training doesn't stop at the specified `--total_timesteps` limit.

**Cause:** Stable-Baselines3's progress bar shows **iterations** (batches of timesteps), not individual timesteps. Each iteration processes `n_steps` timesteps (default: 2048). The progress bar can be misleading, but training should still respect the `total_timesteps` limit.

**Fix:** 
- The training script now includes a `TimestepTrackingCallback` that:
  - Tracks actual timesteps (not iterations)
  - Logs progress every 50 timesteps
  - Ensures training stops exactly at the `total_timesteps` limit
- Look for log messages like `[Actual timesteps: X/500]` to see real progress
- Training will automatically stop when the limit is reached, regardless of what the progress bar shows

### Output Artifacts

After successful training, the output directory structure is:

```
output/ppo_ts/run-YYYYMMDD-HHMMSS-seedN/
├── model.zip              # Trained PPO model
├── vecnormalize.pkl       # VecNormalize statistics
├── run-info.json          # Training configuration
├── monitor.csv            # Episode returns and lengths
├── tb/                    # Tensorboard logs
│   └── PPO_1/
└── env/                   # ns-3 simulation outputs
    ├── UUID-1/            # Episode 1 ns-3 output
    ├── UUID-2/            # Episode 2 ns-3 output
    └── ...
```

### Practical notes for "small-scale first"

- **Episodes are expensive**: Each episode starts a new ns-3 run (~10-20s startup overhead + simTime).
- **Start small**: Use `ts_use_case_small.json` and 200-500 timesteps for smoke tests.
- **Monitor progress**: Use `tail -f output/*/monitor.csv` to watch episode completions in real-time.
- **Tensorboard**: Essential for longer runs - monitor reward trends, policy loss, value loss.
- **Episode length matters**: Longer episodes (higher `simTime`) give more data per episode but take longer to run. Balance is key.

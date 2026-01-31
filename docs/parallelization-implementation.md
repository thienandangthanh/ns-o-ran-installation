# Parallel Training Implementation

## Summary

Implemented multi-environment parallel training to utilize all available CPU cores, dramatically reducing training time.

## Problem

Original training script used only 1 environment (`DummyVecEnv([env_fn])`), resulting in:
- Only 1 CPU core fully utilized (out of 16 available)
- Training 500 timesteps took ~22 minutes
- Projected 10,000 timesteps would take ~7-8 hours

## Solution

Added `SubprocVecEnv` support with `--n_envs` flag to run N parallel environments simultaneously.

## Changes Made

### 1. Updated `scripts/train-ppo-traffic-steering.py`

**Added imports:**
```python
from stable_baselines3.common.vec_env import SubprocVecEnv
import subprocess
```

**Added pre-configuration function:**
```python
def _configure_and_build_ns3(ns3_path: str, optimized: bool):
    """Pre-configure and build ns-3 before creating parallel environments.
    
    This avoids multiple subprocesses trying to configure ns-3 simultaneously.
    """
    # ... configures and builds ns-3 once in main process
```

**Critical fix:** When using parallel environments, all subprocesses were trying to configure/build ns-3 simultaneously, causing lock conflicts. The solution:
1. Pre-configure and build ns-3 **once** in the main process
2. Pass `skip_configuration=True` to each subprocess environment
3. This requires manually initializing `TrafficSteeringEnv` to expose the `skip_configuration` parameter

**Added CLI argument:**
```python
parser.add_argument("--n_envs", type=int, default=1, 
                   help="Number of parallel environments (default: 1)")
```

**Replaced single environment creation with parallel-aware logic:**

**Before:**
```python
def env_fn():
    env = _make_env(...)
    return Monitor(env, filename=os.path.join(run_root, "monitor.csv"))

vec_env = DummyVecEnv([env_fn])
```

**After:**
```python
# Pre-configure ns-3 ONCE before creating parallel environments
_configure_and_build_ns3(args.ns3_path, args.optimized)

def make_env(rank: int):
    """Create a single environment with unique output directory."""
    def _init():
        env = _make_env(
            ...,
            run_dir=os.path.join(run_root, f"env_{rank}"),
            skip_config=True,  # Skip since we already configured
            ...
        )
        return Monitor(env, filename=os.path.join(run_root, f"monitor_{rank}.csv"))
    return _init

# Create vectorized environment with n_envs parallel workers
if args.n_envs > 1:
    print(f"Creating {args.n_envs} parallel environments using SubprocVecEnv...")
    vec_env = SubprocVecEnv([make_env(i) for i in range(args.n_envs)])
else:
    print("Using single environment (DummyVecEnv)...")
    vec_env = DummyVecEnv([make_env(0)])
```

**Key changes:**
- Each environment gets unique output directory: `env_0/`, `env_1/`, ..., `env_N/`
- Each environment gets unique monitor CSV: `monitor_0.csv`, `monitor_1.csv`, ..., `monitor_N.csv`
- `SubprocVecEnv` creates N separate subprocesses, each running its own ns-3 simulation
- Backward compatible: `--n_envs 1` (default) uses original single-env behavior

### 2. Updated `docs/ppo-training-pipeline.md`

Added comprehensive "Parallel Training" section covering:
- How to use `--n_envs` flag
- Architecture explanation (SubprocVecEnv + independent ns-3 processes)
- Performance recommendations for 16 cores + 8GB RAM
- Expected speedup estimates
- Memory/CPU trade-offs
- Best practices

## Usage

### Single Environment (Original Behavior)
```bash
python scripts/train-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_medium.json \
  --output_dir output/ppo_ts_medium \
  --total_timesteps 10000 \
  --seed 0 \
  --optimized \
  --tensorboard
```

### Parallel Environments (Recommended for Multi-Core)
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

## Performance Expectations

### Your System (16 cores, 8GB RAM)

**Recommended configuration:** `--n_envs 4` to `--n_envs 8`

**Estimated speedup:**
- `n_envs=1`: 500 timesteps = 22 minutes (baseline from your test)
- `n_envs=4`: 500 timesteps ≈ 6 minutes (4× speedup)
- `n_envs=8`: 500 timesteps ≈ 3 minutes (8× speedup)

**Medium preset training (10,000 timesteps):**
- `n_envs=1`: ~7-8 hours
- `n_envs=4`: ~2 hours
- `n_envs=8`: ~1 hour

### Memory Considerations

Each environment uses approximately:
- ns-3 simulation process: ~500MB-1GB
- Output files (CSV, SQLite): ~50-100MB per episode
- Total per env: ~600MB-1.2GB

**For 8GB RAM system:**
- `n_envs=8`: 8 × 1GB = ~8GB (tight, may cause swapping)
- `n_envs=6`: 6 × 1GB = ~6GB (safer)
- `n_envs=4`: 4 × 1GB = ~4GB (conservative, leaves headroom)

**Recommendation:** Start with `n_envs=4`, monitor RAM usage (`htop`), then increase if stable.

## How It Works

### Architecture

```
Main Process (PPO Agent)
│
├── VecNormalize (observation normalization)
│   │
│   └── SubprocVecEnv (manages N subprocesses)
│       │
│       ├── Subprocess 0: Monitor → TrafficSteeringEnv → ns-3 sim (env_0/)
│       ├── Subprocess 1: Monitor → TrafficSteeringEnv → ns-3 sim (env_1/)
│       ├── Subprocess 2: Monitor → TrafficSteeringEnv → ns-3 sim (env_2/)
│       └── ...
│       └── Subprocess N-1: Monitor → TrafficSteeringEnv → ns-3 sim (env_N-1/)
│
└── PPO collects experiences from all envs → batch update
```

### Training Loop

1. **Step**: PPO sends actions to all N environments simultaneously
2. **Parallel execution**: Each subprocess runs its ns-3 simulation independently
3. **Gather**: PPO collects (obs, reward, done) from all environments
4. **Buffer**: Experiences added to replay buffer
5. **Update**: When buffer full (2048 timesteps default), PPO performs batch gradient update
6. **Repeat**: Next batch of parallel steps

### Key Benefits

- **N× speedup**: Training wall-clock time reduced by factor of N
- **Better exploration**: N independent environments explore different trajectories
- **Same learning**: PPO sees same total number of timesteps, just collected faster
- **Stable training**: VecNormalize aggregates statistics across all environments

## Output Structure

### Single Environment (`n_envs=1`)
```
output/ppo_ts_medium/run-20260130-HHMMSS-seed0/
├── model.zip
├── vecnormalize.pkl
├── run-info.json
├── monitor_0.csv          # Episode logs
├── tb/                    # Tensorboard
└── env_0/                 # ns-3 outputs
    ├── UUID-1/
    ├── UUID-2/
    └── ...
```

### Parallel Environments (`n_envs=4`)
```
output/ppo_ts_medium/run-20260130-HHMMSS-seed0/
├── model.zip
├── vecnormalize.pkl
├── run-info.json          # Includes "n_envs": 4
├── monitor_0.csv          # Env 0 episodes
├── monitor_1.csv          # Env 1 episodes
├── monitor_2.csv          # Env 2 episodes
├── monitor_3.csv          # Env 3 episodes
├── tb/                    # Tensorboard (aggregated)
├── env_0/                 # ns-3 outputs env 0
│   ├── UUID-1/
│   └── ...
├── env_1/                 # ns-3 outputs env 1
│   ├── UUID-2/
│   └── ...
├── env_2/                 # ns-3 outputs env 2
└── env_3/                 # ns-3 outputs env 3
```

## Monitoring Parallel Training

### Check CPU utilization
```bash
htop
# Should see N ns-3 processes at ~100% CPU
```

### Check RAM usage
```bash
free -h
# Watch "used" memory, ensure it stays below ~80% of total
```

### Monitor training progress
```bash
# Tensorboard (aggregated metrics)
tensorboard --logdir output/ppo_ts_medium/run-*/tb

# Watch episode completions (all environments)
watch -n 1 'wc -l output/ppo_ts_medium/run-*/monitor_*.csv'
```

## Troubleshooting

### Issue: "CalledProcessError: Command ['python3', './ns3', 'configure', ...] returned non-zero exit status 1"

**Cause:** Multiple subprocesses trying to configure/build ns-3 simultaneously causes lock conflicts

**Symptoms:**
- Error occurs when creating parallel environments
- Multiple `ForkServerProcess` errors
- `ConnectionResetError: [Errno 104] Connection reset by peer`

**Fix:** Already implemented! The training script now:
1. Pre-configures and builds ns-3 once in the main process
2. Passes `skip_configuration=True` to each subprocess
3. You should see "Pre-configuring and building ns-3..." before environment creation

**If you still see this error:**
- Ensure you're using the latest version of `train-ppo-traffic-steering.py`
- Try manually building ns-3 first: `cd ~/ns-3-mmwave-oran && python3 ./ns3 build`

### Issue: Out of memory / system freezing

**Cause:** Too many parallel environments for available RAM

**Fix:** Reduce `--n_envs`:
```bash
# Try n_envs=4 instead of 8
--n_envs 4
```

### Issue: No speedup observed

**Cause:** System has < N cores, or CPU-bound by single-core bottleneck

**Check:**
```bash
# Verify CPU count
nproc
# Should be >= n_envs for full speedup
```

**Fix:** Set `n_envs ≤ (cpu_count - 2)` to avoid oversubscription

### Issue: Different environments giving very different rewards

**Status:** Expected behavior - this is good for exploration!

**Explanation:**
- Each environment has independent randomness
- Different UE trajectories, channel conditions, etc.
- VecNormalize will normalize across all environments
- PPO benefits from diverse experiences

## Next Steps

### For Your Medium Preset Training

**Recommended command:**
```bash
python scripts/train-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_medium.json \
  --output_dir output/ppo_ts_medium \
  --total_timesteps 10000 \
  --seed 0 \
  --optimized \
  --tensorboard \
  --n_envs 6
```

**Why `n_envs=6`:**
- Conservative for 8GB RAM (6GB used, 2GB headroom)
- Still 6× speedup over single environment
- 10,000 timesteps in ~1.5-2 hours instead of 7-8 hours

**Monitor first run:**
1. Start training
2. Watch `htop` for first ~5 minutes
3. Check RAM usage stays < 7GB
4. If stable, consider increasing to `n_envs=8` for future runs
5. If RAM issues, reduce to `n_envs=4`

## Technical Notes

### Why SubprocVecEnv instead of DummyVecEnv?

- `DummyVecEnv`: Runs all environments sequentially in main process (no parallelism)
- `SubprocVecEnv`: Runs each environment in separate subprocess (true parallelism)
- Trade-off: `SubprocVecEnv` has IPC overhead, but massively worth it for ns-3's long episode times

### Why not use threading?

- ns-3 simulations are CPU-bound (not I/O-bound)
- Python's GIL prevents true thread-level parallelism for CPU work
- Multiprocessing (subprocesses) bypasses GIL, enabling true parallel CPU usage

### Reproducibility with multiple environments

- Each environment gets same seed + rank offset: `env.seed(seed + rank)`
- Episode order will differ from single-env training
- Final policy should be statistically equivalent (same total experiences)
- For exact reproducibility, use `n_envs=1` with fixed seed

## References

- Stable-Baselines3 Vectorized Environments: https://stable-baselines3.readthedocs.io/en/master/guide/vec_envs.html
- SubprocVecEnv documentation: https://stable-baselines3.readthedocs.io/en/master/common/vec_env.html#stable_baselines3.common.vec_env.SubprocVecEnv

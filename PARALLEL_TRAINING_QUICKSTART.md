# Parallel Training Quick Start Guide

## TL;DR

The training script now supports parallel environments for faster training. Use `--n_envs N` to run N parallel ns-3 simulations.

## Commands

### Quick Test (Small Preset, 6 Parallel Envs)
```bash
python scripts/train-ppo-traffic-steering.py \
  --ns3_path ~/ns-O-RAN-installation/ns-3-mmwave-oran \
  --config ns-o-ran-gym/src/environments/scenario_configurations/ts_use_case_small.json \
  --output_dir output/ppo_ts \
  --total_timesteps 500 \
  --seed 0 \
  --optimized \
  --tensorboard \
  --n_envs 6
```

### Full Training (Medium Preset, 6 Parallel Envs)
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

## Expected Output

```
Pre-configuring and building ns-3...
Configuring ns-3 at /home/uc/ns-O-RAN-installation/ns-3-mmwave-oran...
Building ns-3 with 16 cores...
ns-3 build complete.
Creating 6 parallel environments using SubprocVecEnv...
Using cpu device
Starting training with 10000 timestep limit...
```

## Performance Comparison

| Config | Timesteps | n_envs=1 | n_envs=6 | Speedup |
|--------|-----------|----------|----------|---------|
| Small | 500 | ~22 min | ~4 min | 5.5× |
| Medium | 10,000 | ~7-8 hrs | ~1.5 hrs | 5-6× |

## Recommendations

**For your 16-core, 8GB RAM system:**
- **Recommended:** `--n_envs 6` (safe RAM usage, good speedup)
- **Conservative:** `--n_envs 4` (more headroom)
- **Aggressive:** `--n_envs 8` (max speedup, tight on RAM)

## Monitoring

```bash
# Watch CPU/RAM usage
htop

# Monitor training progress
tensorboard --logdir output/ppo_ts_medium/run-*/tb
```

## Troubleshooting

**If you see configuration errors:** Script already fixed! You should see "Pre-configuring and building ns-3..." before environment creation.

**If RAM is too high:** Reduce `--n_envs` (try 4 instead of 6)

**If no speedup:** Check CPU usage with `htop` - should see N ns-3 processes at ~100%

## Fallback to Single Environment

If parallel training has issues, omit `--n_envs` (defaults to 1):

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

## Documentation

- Full details: `docs/parallelization-implementation.md`
- Fix explanation: `docs/parallel-training-fix.md`
- Training pipeline: `docs/ppo-training-pipeline.md`

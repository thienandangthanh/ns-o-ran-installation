import argparse
import json
import os
from datetime import datetime

import gymnasium as gym


def _require_sb3():
    try:
        from stable_baselines3 import PPO  # noqa: F401
        from stable_baselines3.common.monitor import Monitor  # noqa: F401
        from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize  # noqa: F401
    except Exception as e:  # pragma: no cover
        raise RuntimeError(
            "Missing RL deps. In the VM venv run:\n"
            "  uv pip install stable-baselines3 torch tensorboard\n"
        ) from e


def _load_scenario_config(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def _make_env(ns3_path: str, scenario_config: dict, run_dir: str, optimized: bool, verbose: bool, skip_configuration: bool):
    from environments.ts_env import TrafficSteeringEnv

    env = TrafficSteeringEnv(
        ns3_path=ns3_path,
        scenario_configuration=scenario_config,
        output_folder=run_dir,
        optimized=optimized,
        verbose=verbose,
        skip_configuration=skip_configuration,
    )
    env = gym.wrappers.FlattenObservation(env)
    return env


def main():
    _require_sb3()
    from stable_baselines3 import PPO
    from stable_baselines3.common.monitor import Monitor
    from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize

    parser = argparse.ArgumentParser(description="Train PPO on ns-o-ran-gym TrafficSteeringEnv")
    parser.add_argument("--ns3_path", required=True, help="Path to ns-3-mmwave-oran")
    parser.add_argument("--config", required=True, help="Path to ts_use_case.json")
    parser.add_argument("--output_dir", default="output/ppo_ts", help="Base output directory")
    parser.add_argument("--total_timesteps", type=int, default=20_000, help="SB3 total timesteps")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--optimized", action="store_true")
    parser.add_argument("--verbose_env", action="store_true", help="Enable env debug logging")
    parser.add_argument("--skip_configuration", action="store_true", help="Skip ns-3 configure step (build still happens)")
    parser.add_argument("--tensorboard", action="store_true", help="Enable tensorboard logging")
    args = parser.parse_args()

    scenario_config = _load_scenario_config(args.config)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    run_root = os.path.join(args.output_dir, f"run-{timestamp}-seed{args.seed}")
    os.makedirs(run_root, exist_ok=True)

    def env_fn():
        env = _make_env(
            ns3_path=args.ns3_path,
            scenario_config=scenario_config,
            run_dir=os.path.join(run_root, "env"),
            optimized=args.optimized,
            verbose=args.verbose_env,
            skip_configuration=args.skip_configuration,
        )
        return Monitor(env, filename=os.path.join(run_root, "monitor.csv"))

    vec_env = DummyVecEnv([env_fn])
    vec_env = VecNormalize(vec_env, norm_obs=True, norm_reward=False, clip_obs=10.0)
    vec_env.seed(args.seed)

    tb_log = os.path.join(run_root, "tb") if args.tensorboard else None

    model = PPO(
        policy="MlpPolicy",
        env=vec_env,
        seed=args.seed,
        verbose=1,
        tensorboard_log=tb_log,
    )

    model.learn(total_timesteps=args.total_timesteps, progress_bar=True)

    model_path = os.path.join(run_root, "model.zip")
    vecnorm_path = os.path.join(run_root, "vecnormalize.pkl")
    model.save(model_path)
    vec_env.save(vecnorm_path)

    with open(os.path.join(run_root, "run-info.json"), "w") as f:
        json.dump(
            {
                "ns3_path": args.ns3_path,
                "config": args.config,
                "optimized": args.optimized,
                "skip_configuration": args.skip_configuration,
                "seed": args.seed,
                "total_timesteps": args.total_timesteps,
                "model_path": model_path,
                "vecnormalize_path": vecnorm_path,
            },
            f,
            indent=2,
        )

    print(f"Saved model: {model_path}")
    print(f"Saved VecNormalize: {vecnorm_path}")


if __name__ == "__main__":
    main()


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
        raise RuntimeError("Missing RL deps. In the VM venv run:\n  uv sync\n") from e


def _load_scenario_config(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def _make_env(ns3_path: str, scenario_config: dict, run_dir: str, optimized: bool, verbose: bool):
    from environments.ts_env import TrafficSteeringEnv

    env = TrafficSteeringEnv(
        ns3_path=ns3_path,
        scenario_configuration=scenario_config,
        output_folder=run_dir,
        optimized=optimized,
        verbose=verbose,
    )
    env = gym.wrappers.FlattenObservation(env)
    return env


def main():
    _require_sb3()
    from stable_baselines3 import PPO
    from stable_baselines3.common.callbacks import BaseCallback
    from stable_baselines3.common.monitor import Monitor
    from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize

    class TimestepTrackingCallback(BaseCallback):
        """Callback to track actual timesteps and ensure training stops at limit."""

        def __init__(self, total_timesteps_limit: int, verbose=0):
            super().__init__(verbose)
            self.total_timesteps_limit = total_timesteps_limit
            self.last_logged = 0

        def _on_step(self) -> bool:
            # Get current timestep count from the model
            # Note: self.num_timesteps is updated after each step
            current_timesteps = self.num_timesteps

            # Log progress every 50 timesteps (or at start)
            if current_timesteps == 0 or current_timesteps - self.last_logged >= 50:
                print(
                    f"\n[Actual timesteps: {current_timesteps}/{self.total_timesteps_limit}]",
                    flush=True,
                )
                self.last_logged = current_timesteps

            # Stop training if we've reached or exceeded the limit
            # SB3 may process slightly more timesteps due to batching, but we enforce the limit
            if current_timesteps >= self.total_timesteps_limit:
                print(
                    f"\n[Training stopping] Reached {current_timesteps} timesteps (limit: {self.total_timesteps_limit})",  # noqa: E501
                    flush=True,
                )
                return False  # Stop training

            return True  # Continue training

        def _on_training_end(self) -> None:
            """Called when training ends."""
            final_timesteps = self.num_timesteps
            print(
                f"\n[Training ended] Final timestep count: {final_timesteps}/{self.total_timesteps_limit}",  # noqa: E501
                flush=True,
            )

    parser = argparse.ArgumentParser(description="Train PPO on ns-o-ran-gym TrafficSteeringEnv")
    parser.add_argument("--ns3_path", required=True, help="Path to ns-3-mmwave-oran")
    parser.add_argument("--config", required=True, help="Path to ts_use_case.json")
    parser.add_argument("--output_dir", default="output/ppo_ts", help="Base output directory")
    parser.add_argument("--total_timesteps", type=int, default=20_000, help="SB3 total timesteps")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--optimized", action="store_true")
    parser.add_argument("--verbose_env", action="store_true", help="Enable env debug logging")
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

    # Create callback to track timesteps and ensure training stops at limit
    timestep_callback = TimestepTrackingCallback(total_timesteps_limit=args.total_timesteps)

    print(f"Starting training with {args.total_timesteps} timestep limit...", flush=True)
    print(
        "Note: Progress bar shows iterations (batches of ~2048 timesteps), not individual timesteps.",  # noqa: E501
        flush=True,
    )
    print("Actual timestep progress will be logged periodically.\n", flush=True)

    model.learn(total_timesteps=args.total_timesteps, progress_bar=True, callback=timestep_callback)

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

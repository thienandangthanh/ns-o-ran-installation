import argparse
import json
import os

import gymnasium as gym


def _require_sb3():
    try:
        from stable_baselines3 import PPO  # noqa: F401
        from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize  # noqa: F401
    except Exception as e:  # pragma: no cover
        raise RuntimeError(
            "Missing RL deps. In the VM venv run:\n"
            "  uv pip install stable-baselines3 torch tensorboard\n"
        ) from e


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
    from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize

    parser = argparse.ArgumentParser(description="Evaluate PPO on TrafficSteeringEnv")
    parser.add_argument("--ns3_path", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--model_path", required=True)
    parser.add_argument("--vecnormalize_path", required=True)
    parser.add_argument("--episodes", type=int, default=5)
    parser.add_argument("--optimized", action="store_true")
    parser.add_argument("--verbose_env", action="store_true")
    parser.add_argument("--output_dir", default="output/ppo_ts_eval")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    scenario_config = _load_scenario_config(args.config)

    def env_fn():
        return _make_env(
            ns3_path=args.ns3_path,
            scenario_config=scenario_config,
            run_dir=args.output_dir,
            optimized=args.optimized,
            verbose=args.verbose_env,
        )

    vec_env = DummyVecEnv([env_fn])
    vec_env = VecNormalize.load(args.vecnormalize_path, vec_env)
    vec_env.training = False
    vec_env.norm_reward = False

    model = PPO.load(args.model_path, env=vec_env)

    episode_returns = []
    for ep in range(args.episodes):
        obs = vec_env.reset()
        done = False
        ep_ret = 0.0
        while not done:
            action, _ = model.predict(obs, deterministic=True)
            # VecEnv returns 4 values (old gym API): obs, reward, done, info
            obs, reward, done, _info = vec_env.step(action)
            # reward is an array from VecEnv, extract scalar with [0]
            ep_ret += float(reward[0])
            done = bool(done[0])
        episode_returns.append(ep_ret)
        print(f"episode={ep} return={ep_ret}")

    out_path = os.path.join(args.output_dir, "evaluation.json")
    with open(out_path, "w") as f:
        json.dump({"episode_returns": episode_returns}, f, indent=2)
    print(f"Wrote: {out_path}")


if __name__ == "__main__":
    main()

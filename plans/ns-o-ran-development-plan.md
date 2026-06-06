# ns-O-RAN (Gym + xApp) Development Plan

## Scope and deliverables

- Add a small set of developer docs in `docs/` (this repo) focused on your lab workflow:
  - docs/dev-workflow-ns-o-ran-gym.md: repo + VM + component map; how to iterate quickly.
  - docs/ns-o-ran-gym-architecture-and-extension-points.md: how NsOranEnv launches ns-3, semaphores, datalake
  schema, action logging.
  - docs/traffic-steering-scenario-and-reward.md: how traffic steering is modeled end-to-end
  (state/action/reward), and which parts match the Lacava 2024 paper vs not.
  - docs/ppo-training-pipeline.md: PPO baseline with Stable-Baselines3, training/eval loop, artifacts,
  reproducibility knobs.
  - docs/python-xapp-e2sm-kpm-rc.md: how to run a Python "policy" inside Bronze as an xApp with E2SM-KPM
  subscribe + E2SM-RC control.
  - docs/cql-rem-reproduction-roadmap.md: offline dataset format, sanity checks, then CQL/REM implementation
plan.

## Phase 1 — Build correct mental model (read + diagram)

- Map the two control loops already present:
  - Gym-in-the-loop (not xApp): ns-o-ran-gym/examples/traffic_steering.py drives TrafficSteeringEnv which extends NsOranEnv.
    - TrafficSteeringEnv uses file+semaphore control and reads KPM CSV outputs into SQLite (ActionController + SQLiteDatabaseAPI).
    - Key files: ns-o-ran-gym/src/environments/ts_env.py, ns-o-ran-gym/src/nsoran/ns_env.py.
  - RIC xApp loop (xApp container + connector): colosseum-near-rt-ric/setup/sample-xapp/run_xapp.sh runs a Python "agent" (socket server) and a C++ connector (xapp-sm-connector) that speaks RMR/E2AP/E2SM.
    - Key files: colosseum-near-rt-ric/setup/sample-xapp/*.py, colosseum-near-rt-ric/setup/xapp-sm-connector/src/xapp.cc.
- Add a mermaid diagram (in docs) that shows both loops and where they differ.

## Phase 2 — Align scenario + KPIs with the paper

- Confirm scenario-one already matches the paper’s channel model requirements:
  - ns-3-mmwave-oran/scratch/scenario-one.cc uses ThreeGppUmiStreetCanyon* models.
- Document the TS reward already implemented:
  - TrafficSteeringEnv._compute_reward() implements log-throughput delta minus HO cost (Cf, lambdaf) in ns-o-ran-gym/src/environments/ts_env.py.
- Define evaluation metrics pipeline (throughput, CQI/SINR, spectral efficiency proxies, HO overhead) using existing exported KPM columns stored by SQLiteDatabaseAPI.

## Phase 3 — PPO baseline (discrete actions)

- Implement a clean SB3 PPO baseline around TrafficSteeringEnv:
  - Observation shaping + normalization (vectorize env, VecNormalize).
  - MultiDiscrete policy considerations (either flatten MultiDiscrete to single Discrete per-UE policy, or use a factorized MultiDiscrete policy wrapper).
  - Logging artifacts: model checkpoints, tensorboard, and exported evaluation CSVs.
- Add a "small-scale reproducible run" preset (short sim, small UE count) and a "scale-out knobs" section.

## Phase 4 — Real Bronze xApp with E2SM-KPM + E2SM-RC over E2AP

- Gap to close: current xapp-sm-connector is built around E2SM-HelloWorld ASN.1 (colosseum-near-rt-ric/setup/xapp-sm-connector/asn1c_defs/*HelloWorld*). It must be extended/replaced for E2SM-KPM + E2SM-RC.
- Plan for the xApp architecture you asked for:
  - Keep Python as the policy/logic.
  - Add/extend a C/C++ "connector" that:
    - subscribes to KPM SM and decodes indications,
    - encodes/sends RC control messages for traffic steering.
  - Reuse existing ASN.1 sources already in the repo:
    - KPM/RC ASN.1 is present under oran-e2sim/e2sim/src/ASN1c/ (e.g. e2sm-kpm-rc.asn + generated C).
    - ns-3 side already expects KPM (RAN func ID 200) and RC (RAN func ID 300): see scenario-one.cc + net devices; RC function description in oran-interface/model/ric-control-function-description.cc.
  - Update Bronze container build so setup-scripts/setup-sample-xapp.sh produces a container with the new connector + Python policy.
- Verification steps (run on VM):
- Run scenario-one with --enableE2FileLogging=false --e2TermIp=10.0.2.10.
- Confirm xApp receives KPM indications and control causes actual HO via RicControlMessage decode path.

## Phase 5 — CQL + REM (offline RL) reproduction path

- Define a dataset spec (one row per transition) derived from:
  - Gym loop traces (state, action, reward, next_state, done) + attached raw KPM snapshots.
  - Optionally RIC-loop traces once xApp is working.
- Implement offline training pipeline:
  - CQL discrete-action variant + REM Q-ensemble.
  - Evaluation protocol: fixed seeds, held-out scenarios/configs, report the paper’s metrics.

## "Paper parity" audit checklist

- Verify which items exist today vs missing:
  - Reward formulation (present in ts_env.py).
  - Discrete HO action semantics (present: MultiDiscrete mapping UE→target cell).
  - DRL algorithms (missing: traffic_steering.py currently samples random actions).
  - Real xApp deployment using E2SM-KPM/RC (not currently present; sample xApp connector is HelloWorld).
  - Offline RL + large dataset tooling (missing; to be added).

## Suggested doc improvements (quick wins)

- Update docs/run-ns-o-ran-gym-traffic-steering-example.md to explicitly state it runs file+semaphore control,
not a near-RT RIC xApp loop.
- Add a short "Which mode are you running?" section (Gym mode vs RIC xApp mode) with expected flags:
  - Gym: EnableE2FileLogging=true + semaphores.
  - RIC: EnableE2FileLogging=false + e2TermIp=10.0.2.10 + xApp container.

## Task tracking list

- [x] Write docs explaining ns-o-ran-gym architecture, dataflow, and extension points (NsOranEnv, semaphores, ActionController, SQLite datalake).
- [x] Document traffic steering scenario-one config, action/obs/reward, and how it matches the Lacava 2024 formulation.
- [ ] Implement a PPO baseline training/eval pipeline (SB3) for the discrete TS action space with reproducible configs.
- [ ] Design and implement a Python-policy xApp in Bronze with a KPM/RC-capable connector (reuse ASN.1 from oran-e2sim/oran-interface), plus end-to-end verification against ns-3.
- [ ] Define dataset format and implement offline RL (CQL + REM) reproduction pipeline with evaluation metrics.

## Traffic Steering use case: scenario, state/action/reward, and paper parity

This doc explains the traffic steering (TS) setup as implemented in this repo:
- ns-3 scenario: `ns-3-mmwave-oran/scratch/scenario-one.cc`
- Gym env: `ns-o-ran-gym/src/environments/ts_env.py`
- Example runner: `ns-o-ran-gym/examples/traffic_steering.py`

### Scenario summary (`scenario-one`)

#### Topology and deployment shape

- **Cells**:
  - 1 LTE eNB (cellId 1)
  - 7 NR mmWave gNBs (cellId 2..8)
  - The LTE eNB and 1 mmWave BS are **co-located at the center**.
  - The remaining mmWave BSs are placed on a circle at distance `isd`.
- **UEs**:
  - Total UEs = `ues` (per gNB) \(\times\) 7
  - Mobility: `RandomWalk2dOutdoorMobilityModel` within a 4000x4000 area.

#### Channel model (matches the paper’s "UMi street canyon")

`scenario-one` explicitly sets:
- Pathloss: `ThreeGppUmiStreetCanyonPropagationLossModel`
- Channel condition: `ThreeGppUmiStreetCanyonChannelConditionModel`

This matches the "3GPP UMi street canyon" requirement discussed in Lacava et al. (TMC 2024).

#### External control interfaces

`scenario-one` supports **external step-by-step control** via:
- `controlFileName` (default: `ts_actions_for_ns3.csv`)
- `useSemaphores` (enables the semaphores used by `NsOranEnv`)

In Gym mode, ns-3 reads the control file and applies handover decisions.

### Environment mapping (`TrafficSteeringEnv`)

#### Observation (state)

In `ns-o-ran-gym/src/environments/ts_env.py`, the state columns are:
- `RRU.PrbUsedDl`
- `L3 serving SINR`
- `DRB.MeanActiveUeDl`
- `TB.TotNbrDlInitial.Qpsk`
- `TB.TotNbrDlInitial.16Qam`
- `TB.TotNbrDlInitial.64Qam`
- `TB.TotNbrDlInitial`

The env builds a matrix observation with shape:
- `(#UEs_total, #features + 1)`
- The extra `+1` is for `timestamp` (as returned by the datalake query).

#### Action space (discrete handover recommendations)

The TS action space is:
- `spaces.MultiDiscrete([7] * (#UEs_total))`
- Per UE, the action value means:
  - `0`: no action (no handover command sent)
  - `1..6`: handover to one of the mmWave gNBs

The env converts Gym actions to ns-3 target cell IDs as:
- `targetCellIdGym + 2` → produces NR `nrCellId` in the range 2..8.

This matches the paper’s statement that the agent **recommends a handover to a target cell** at each decision time.

#### Reward (log-throughput improvement minus HO cost)

The reward is computed in `TrafficSteeringEnv._compute_reward()` as:
- For each UE \(u\), compute:
  - \( \Delta \log_{10}(T_u) = \log_{10}(T_{u,t+1}) - \log_{10}(T_{u,t}) \) (with safe handling of 0)
  - A handover cost that penalizes frequent HOs:
    - if an HO occurred: \( C_f \cdot (1-\lambda_f)^{\Delta t} \)
- Total reward is the sum across UEs:
  - \( r_t = \sum_u (\Delta \log_{10}(T_u) - \text{HoCost}_u) \)

The throughput metric used by the env is:
- `DRB.UEThpDl.UEID` (and it uses `nrCellId` to detect HO events)

The cost parameters are exposed as env args:
- `Cf` (cost factor)
- `lambdaf` (decay factor)

### What the current example does (and does not do)

`ns-o-ran-gym/examples/traffic_steering.py` currently:
- creates `TrafficSteeringEnv`,
- resets the env,
- then uses `env.action_space.sample()` (random actions) for each step.

So, today it is a **demo/sanity check**, not the paper’s DRL solution.

### Paper parity checklist (TS paper vs this repo today)

- **Scenario family** (dense deployment, UMi street canyon):
  - **Present**: `scenario-one` uses 3GPP UMi street canyon channel models and a dense multi-cell layout.
- **Action semantics** (discrete HO recommendation):
  - **Present**: `MultiDiscrete` action mapping to NR cell IDs.
- **Reward** (log-throughput improvement minus HO cost):
  - **Present**: implemented in `TrafficSteeringEnv._compute_reward()`.
- **DRL training** (policy optimization, e.g., PPO/CQL/REM):
  - **Missing**: example runner uses random actions; no PPO/CQL/REM pipeline in this repo yet.
- **Deployment as near-RT RIC xApp** (E2SM-KPM subscribe + E2SM-RC control over E2AP):
  - **Not implemented yet**: current Gym loop is file+semaphore based; the sample xApp connector in Bronze is HelloWorld-based and must be adapted for KPM/RC.


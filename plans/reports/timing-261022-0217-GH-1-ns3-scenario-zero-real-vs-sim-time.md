# ns-3 scenario-zero timing: real seconds per simulated second (M4)

Date: 2026-10-22. Gate M4 (green), evidence `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m4/20261021T165230Z/` (`ns3-timing.json`, `ns3-timing.txt`).

**Result.** With one gNB, ns-3 needs **1.685 s of wall time per simulated second**. With the default 4 mmWave gNBs plus 1 LTE eNB it needs **31.96 s**. Both measurements are tight: the coefficient of variation is below 1 %.

| Config | Args | Repeats | Mean | Min | Max | Stdev | Samples per node |
|---|---|---|---|---|---|---|---|
| single gNB | `--nMmWaveEnbNodes=1 --e2lteEnabled=false` | 3 | 1.685 | 1.680 | 1.690 | 0.005 | 100 (node 2) |
| default | none (4 mmWave + 1 LTE eNB, 12 UEs) | 3 | 31.958 | 31.730 | 32.108 | 0.201 | 100 (nodes 1–5) |

**Method.**
- **Run settings:** `--simTime=10`, the default `--indicationPeriodicity=0.1`, and the default UE and traffic load (full-buffer UDP DL).
- **Sink:** the IPC emitter is active against a null-sink agent (`tools/ipc-null-sink`), so the emit cost is included.
- **Timing:** the scenario binary runs directly in its own process group. Wall time is measured with `time.monotonic()` around it (`scripts/measure-ns3-timing.sh`).
- **Machine:** VM with 8 vCPU and Ubuntu 24.04.5; the binary was built with the ns-3 `default` profile (-O2 -g, asserts and logs on).
- **Load:** the RIC was running on the VM but idle, with no E2 nodes attached. Load averages were 1.82/2.52/1.32 before and 1.05/1.51/1.41 after.

**Commits.**
- ns-3-mmwave-oran `ace321688130834fb79cf724050178a661ed4cf8`
- oran-interface `438a839aad69854acca41ef435ff681ee7bd3134`
- harness `d1b0edccb4ca85451ad348781ab09263ee6cf9e8`

**What it means.**
- The default scenario runs about 32× slower than real time, and the single-gNB one about 1.7× slower. So the simulator, not the RIC, is the slow side of any lock-step loop.
- With the default 0.1 s indication period, each node emits one sample every 3.2 s of wall time. In the single-gNB config it is one every 0.17 s.
- M7 sizes its simTime from this: about 42 simulated seconds covers the 15-minute endurance window plus the e2term pod-delete phase.
- These numbers feed the pre-M8 pacing gate. They have not been tried in a lock-step design here.

## Unresolved questions
- How much the default profile's asserts and logging cost compared with an `optimized` build. This was not measured.

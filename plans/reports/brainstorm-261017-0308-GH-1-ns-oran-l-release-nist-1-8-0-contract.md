# Brainstorm contract: moving ns-O-RAN to the OSC Near-RT RIC L-release on NIST v1.8.0

Date: 2026-10-17. Flags: `--advice --ultra`. This contract feeds `/ak-goal-warmup` and then `/goal`.

**How this was produced.** Five independent Opus candidates each wrote a full contract. A kongming verifier (Opus 5.5, xhigh effort) scored them blind and selected the winner, which is reproduced below **unchanged**, as the `--ultra` rules require. The verifier's errata come after it as annotations. They take precedence wherever they conflict with the contract text.

**User directive (binding).** The earlier `dev/l-release` migration was a dead end. Use it only as a reference for what went wrong; do not reuse its code, branches or approach.

---

# Brainstorm contract (candidate #2): ns-O-RAN (Bronze) → OSC Near-RT RIC L-release on NIST O-RAN-Testbed-Automation v1.8.0

This revision follows the user directive: the prior `dev/migrate-to-l-release` work and its forks' `dev/l-release` branches are used only for failure archaeology. Nothing is reused or rebased from them.

## New evidence I checked (read-only)
- **Selecting L is a file drop-in, not a hand edit.** `Near-Real-Time-RIC/install_scripts/git_clone.sh:115-118` reads `$PARENT_DIR/commit_hashes.json` first, and `PARENT_DIR` is `RAN_Intelligent_Controllers/Near-Real-Time-RIC/`. It only falls back to the repo-root file if that one is missing. So copying `commit_hashes_l_release.json` to `Near-Real-Time-RIC/commit_hashes.json` switches the RIC to L and leaves the root pins alone.
- **L and the default (N) differ only in the RIC platform.** I diffed the two pin files. e2-interface `da6f82f2`, kpimon-go `8bbbbbb`, rc `a2282ee`, ts, qp and ad have the same hashes in both; only the branch labels differ. The RIC-side differences are ric-dep (`ee47a34` vs `d9298b0`), appmgr and it/dep. Conclusion: all work on the E2-node side is the same for L and N. The L-specific risk sits in the ric-dep install.
- **The patch script stops on the first failure.** `apply_patches.sh` runs with `set -e` and `git apply`s patches into `ric-dep/depRicKubernetesOperator/...`, `helm/e2mgr`, `helm/rtmgr` and `new-installer/...`. Those paths and hunks were written against the m-release ric-dep. Any mismatch on L stops the install there.
- **Kubernetes version.** The patched `install_k8s_and_helm.sh` sets `KUBEV="1.33"`. Ubuntu 20.04 uses cgroup v1 by default, and whether k8s 1.33 works on it here is unverified. Preflight must check this.
- **No upstream L port exists to reuse.** OSC `sim-ns3-o-ran-e2` has an `l-release` branch, but it is 1 commit *behind* our pin 5f547ae (`gh compare`). wineslab `ns-o-ran-e2-sim` has `develop` (3 build-fix commits, 2026-10-06) and `x5g-e2sim`. The x5g README says it targets RIC "E Release" and is fed protobuf by an external RAN process.
- **NIST already runs its E2 node outside the RIC.** `run_e2sim_and_connect_to_ric.sh` runs `kpm_sim` in a Docker container (`oransim:0.0.999`) and points it at the e2term ClusterIP:36422.
- **Correction to the evidence packet.** The "kpimon v2 vs ns-O-RAN v3, why green?" question *was* answered: prior journal `docs/journals/2026-06-09-phase1-kpm-v3v2-rootcause.md` (in `dev/migrate-to-l-release`). The message body decodes as v2 by design. The header fails to decode, but the failure is silently salvaged by `wrapper.c` (`RC_WMORE` returns a partial struct). In other words, the old "green" covered up a broken header.

## Why the prior path dead-ended (inference from its journals; not proven)
1. **It rebased the whole wineslab e2sim fork onto OSC e2sim.** That dropped behaviour the Bronze version relied on, such as per-instance SCTP source ports. Bugs that come from process-wide state (hardcoded src port 36422, a single global `client_fd`, a double-free) then surfaced one at a time in live runs. Each fix pushed the fork further from upstream (journals of 2026-06-07 and 2026-06-16/27).
2. **ns-3 linked the ASN.1/E2AP code in-process.** That required a hand-built `libasn1c_e2.a`, manual header copies, a stale install rule, a pinned asn1c fork, and avoiding `asn_check_constraints`. None of this was reproducible from scripts.
3. **"Green" was declared from logs, not from decoded bytes.** The header-decode failure above is the example.
4. **The connection target was a fragile workaround.** ns-3 connected to the e2term pod IP because NodePort SCTP did not work. A pod restart breaks that.
5. **What ran drifted from the source.** The TS fix was never deployed, QP was mocked, and Stage E was deferred.
6. **Nothing could be rebuilt.** The environment was a hand-built 2-VM setup whose disks are now gone.

## 1. Outcome
A single Ubuntu 20.04 VM, rebuilt by scripts from its fresh-install snapshot, runs:
- the NIST v1.8.0 Near-RT RIC on the **L** pins;
- kpimon-go (plus rc, and TS if confirmed) deployed with NIST's own scripts;
- an unmodified-logic ns-O-RAN `scenario-zero` with N gNBs that connects over E2AP v3.01 / E2SM-KPM v3.
KPM data must reach InfluxDB and decode correctly on the wire for both header and message. RC control must cause a handover inside ns-3. All code lives on fresh `dev/...` branches of the user's forks, and one script reproduces the whole stack.

## 2. Constraints
- **Where changes happen.** Only inside the VM, the VM's libvirt snapshots, and new fork branches. Do not touch the host: sudo there needs interactive auth, so treat host sudo as unavailable.
- **Snapshots.** Take one at every exit gate (`l0-preflight`, `l1-ric-up`, `l2-refnode`, `l3-xapps`, …). If the environment is contaminated, revert to the last gate snapshot instead of repairing it, and log every revert in `implementation-notes.html`. Never delete the `fresh-install` snapshot.
- **virtiofs.** Source is shared over virtiofs; build and Docker/containerd data stay on VM-local disk. Git commits are made from one place only, the host worktree, so there is a single writer. Measure the ns-3 build on virtiofs during preflight before relying on it.
- **Forks and branches.** Create new branches (e.g. `dev/l-release-nist180`) cut from the *upstream* pins: O-RAN-Testbed-Automation 6088882, ns-3-mmwave-oran 8c42089d, oran-interface 5f547ae, oran-e2sim. Never base on the old `dev/l-release`. Do not commit to cloned branches and do not open upstream PRs.
- **Platform.** Ubuntu 20.04 only. VM disk at least 120 GB; NIST asks for ≥57 GB, and ns-3 plus images add more. Use the `VMs-HDD` pool (1.17 TiB free).
- **Roles.**
  - The Sonnet orchestrator owns gates, snapshots and commits.
  - Sonnet workers each own one bounded task with named files.
  - kongming (Opus 5.5, xhigh) is consulted at every design fork and after 2 failed attempts on the same gate.
- **Stop and ask the user when:**
  - the L install still fails after a time-boxed patch-porting budget (falling back to N is the user's call);
  - an approach switch is needed;
  - anything would mutate the host;
  - disk is below 20 GB free;
  - a consequential fork comes up (journal a checkpoint and wait for a fresh session).
- **Don't trust old notes.** Prior landmines (funcId 2, 8-byte TimeStamp, LTE serialising EN-DC handovers, uppercase cell_map keys) are hypotheses to re-verify, not facts.

## 3. Non-goals
- Reviving or rebasing the prior forks' `dev/l-release` branches, or its adapter-layer/in-process-rebase design.
- Running N as the delivered RIC (it is only a diagnostic fallback, and only with user approval).
- Moving to Ubuntu 22.04.
- Supporting the Bronze Docker RIC (colosseum).
- The OAI/srsRAN/OCUDU/Non-RT RIC parts of NIST.
- Upstream PRs.
- Changing ns-3 radio/scenario behaviour.

## 4. Acceptance criteria (staged)
- **M0 Preflight**
  - VM name, IP, snapshot and virtiofs tag recorded.
  - `lsb_release -r` = 20.04.
  - `df -h /` ≥ 120G total; RAM ≥ 8 GiB.
  - virtiofs mount lists the worktree.
  - `virsh snapshot-list` shows `fresh-install`.
  - k8s 1.33/cgroup-v1 and containerd feasibility checked (dry-run or doc check).
- **M1 RIC L up**
  - `git -C ric-dep rev-parse HEAD` = `ee47a347…`; appmgr = `4c05932…`.
  - All `ricplt` pods Running/Ready for 10 min.
  - e2term image tag recorded.
  - Any ported patch is committed as a `.patch` in the fork's `install_patch_files`.
- **M2 Reference node**
  - NIST `kpm_sim` → `fetch_connected_e2_nodes.sh` shows CONNECTED.
  - `check_e2ap_version.sh` output saved.
  - Golden pcap of E2Setup / Subscription / Indication decoded by tshark.
- **M3 xApps**: `install_xapp_kpi_monitor.sh` succeeds, and kpm_sim indications land in InfluxDB.
- **M4 Build**: ns-3 configures and builds from a clean clone by script, with no manual `ar` or header copies.
- **M5 Single gNB**: ns-3 E2SetupRequest is decoded; E2SetupResponse `RANfunctionsAccepted` contains the KPM function ID.
- **M6 KPM**: wire indications decode as v3 *and* through kpimon's own decoder with `RC_OK` for **header and message**; InfluxDB values match the ns-3 trace for 3 samples.
- **M7 Multi-gNB robustness**
  - Every scenario-zero gNB is CONNECTED with a distinct ID, and each one's indications are seen.
  - 15-min run with no crash.
  - After `kubectl delete pod` of e2term, all gNBs reconnect with no manual IP change.
- **M8 RC**: an rc xApp control causes a handover visible in the ns-3 trace, for at least 2 gNBs.
- **M9 Reproducibility**: revert to `fresh-install` → one script → M6 green, unattended.

## 5. Trade-offs
There are two choices. **(a) RIC target:** L via the `commit_hashes_l_release.json` drop-in, or the default N. **(b) Reuse prior forks or re-port from scratch:** already decided by the user, re-port from scratch.

**Approach A: L drop-in + out-of-process E2 agent.** ns-3's oran-interface sends KPM data and receives RC controls over a simple local IPC (TCP/UDS, per gNB). One agent process per gNB, built from the NIST-pinned e2-interface via NIST's own build, does all the ASN.1/E2AP/SCTP work. It runs in-cluster or the way NIST's oransim container does.
- Prior mistakes it avoids: process isolation removes the shared-global bugs (1); ns-3 never links asn1c (2); the agent connects to the e2term Service, not a pod IP (4); the same pattern as NIST's own E2 node keeps the setup scriptable (6).
- Depends most on: the IPC schema carrying everything KPM and RC need, and wall-clock RC control being acceptable to ns-3's event loop.
- Fails first if: RC needs synchronous, sim-time-coupled replies.
- Worst case: the agent re-implements per-UE state and becomes a second simulator.

**Approach B: L drop-in + in-process thin binding to the unmodified pinned e2-interface.** Any required e2sim change ships as a small reviewed `.patch` in NIST-style `install_patch_files`, and multi-gNB tests run from day one.
- Prior mistakes it avoids: no wholesale fork rebase (1); patch files instead of drift (5).
- Depends most on: e2sim's global state (hardcoded 36422 source port, a single `client_fd`) being fixable with small patches.
- Fails first: at M7, because those globals need invasive changes.
- Worst case: it slides back into the prior dead end.

**Approach C: default N RIC + Approach A's agent.** NIST's tested path.
- Depends most on: the user accepting N.
- Fails on: the stated requirement.
- Worst case: delivering something the user didn't ask for.

## 6. Better approaches
None replaces the literal L ask. One evidence-based adjustment: because the E2-node pins are the same in L and N, a short N install from `fresh-install` is a cheap **diagnostic control** if L's ric-dep patches fail. It does not replace L.
- What it gives: a known-good RIC to diff against.
- Cost: about one install cycle and no rework, since everything from M4 onward carries over.
- It needs user approval at the L-failure stop point.

## 7. Recommended direction: Approach A, with an L-failure stop point
- **P0 Preflight** (can run before disk is reclaimed): host-side reads only — pick the libvirt pool and VM spec, plan the virtiofs tag, run the k8s 1.33 / Ubuntu 20.04 check from docs. Then do VM checks once the VM exists. Exit: M0 met, snapshot `l0-preflight`.
- **P1 RIC L**: on fork branch `dev/l-release-nist180`, copy the L pins to `Near-Real-Time-RIC/commit_hashes.json` and run `full_install.sh`. If `apply_patches` fails, port each hunk into a new `.patch` (time-boxed, kongming consulted). Exit: M1, snapshot `l1-ric-up`. Over budget: stop and ask the user (offer the N control).
- **P2 Reference + golden**: M2 and M3, snapshot `l2-refnode`. The pcap captured here is the only wire truth used later.
- **P3 Agent design** (kongming checkpoint): IPC schema, agent placement (pod vs host container), RC timing semantics. Journal it, and get user sign-off if it is a consequential fork.
- **P4 ns-3 side**: fresh branches; replace in-process e2sim calls with the IPC emitter; scripted build. Exit: M4.
- **P5 Agent + KPM**: M5 and M6; every claim is checked by tshark plus kpimon-decoder harness output. Snapshot.
- **P6 Multi-gNB + durability**: M7.
- **P7 RC**: M8, plus a real TS/QP loop if the user confirms scope.
- **P8 Reproducibility**: M9 from `fresh-install`; update the README/docs.

Rollback at any phase: revert to the previous gate snapshot. Code rollback is branch reset on the fork, done by the orchestrator only.

## 8. Risks and questions
**Risks:**
- The L ric-dep patch mismatch could be large.
- k8s 1.33 on Ubuntu 20.04 with cgroup v1 may not work.
- Wall-clock vs sim-time semantics for RC in Approach A.
- Building on virtiofs may be slow or hit permission issues.
- Approach A's agent may need a decoder harness to prove v2/v3 header compatibility. Mismatch with kpimon-go's v2 decoder may force a kpimon patch (on a fork).

**Questions for the user:**
1. If L ric-dep can't be patched within a bounded budget, may we run N as a diagnostic control? Is N ever acceptable as the deliverable?
2. Is RC/handover control (M8) in scope, and is a real TS+QP closed loop required, or just xApp-driven control?
3. VM identity once disk is reclaimed: domain name, disk size (≥120 GB OK?), RAM (8 vs 16 GiB), virtiofs tag/path for this worktree, and whether the agent may run `virsh snapshot-create/revert` without host sudo.
4. Is changing ns-O-RAN's E2 integration to an IPC agent acceptable, or must ns-3 speak SCTP/E2 directly?


---

## Errata from the verifier (read these alongside the contract; they win on any conflict)

1. **M6 and the Outcome contradict each other.** The Outcome requires "E2SM-KPM v3 on the wire", and M6 requires that "kpimon decodes the header with RC_OK". Both cannot hold with stock kpimon-go 8bbbbbb as NIST patches it, because its `kpm2_0.asn` keeps `TimeStamp SIZE(4)` (see `install_patch_files/xApps/kpimon-go/e2sm/asn1/kpm2_0.asn.patch`). NIST's own `kpm_e2sm` example also sends an 8-byte TimeStamp (`encode_kpm.cpp:223-227`). Before writing any agent code, decide the header contract (user question Q1). At M3, also grep kpimon's logs for `header RC_WMORE` while it is fed by NIST's bundled sim. That shows whether NIST's reference capture is itself clean.
2. **Patch applicability is no longer a real risk.** All 7 files that NIST patches have identical git blob SHAs in ric-dep L (ee47a34) and in the default m-release (d9298b0). The L recipe differs only in image tags: e2mgr/e2term 6.0.6, appmgr 0.5.8, rtmgr 0.9.6, submgr 0.10.2. The time-boxed patch porting in P1 is therefore mostly moot. Keep `git apply --check` in P0 as a quick confirmation. The remaining L risk is how these older images behave at runtime.
3. **Each agent needs its own network namespace**, meaning one container or pod per gNB agent. The unmodified e2sim keeps a single global `client_fd` (`e2sim/src/base/e2sim.cpp:36`) and binds a fixed source port, 36422 (`e2sim_defs.h:32`, `e2sim_sctp.cpp:177-181`). Several agent processes sharing one namespace would collide.
4. **"ns-3 never links asn1c" requires an explicit refactor.** At 8c42089 the lte and mmwave modules link oran-interface (`src/lte/CMakeLists.txt:373`, `src/mmwave/CMakeLists.txt:153`), and oran-interface requires the e2sim library. The plan must cut that dependency or isolate the Bronze e2sim build. The verifier's inference is that otherwise it will clash with NIST's `/usr/local/include/e2sim`.
5. **Run the NIST installer from a VM-local clone of the fork branch, never from the virtiofs mount.** `apply_patches.sh` writes back into its own tree (lines 47, 71, 77, 82, …), and the installer also runs `sudo find/sed` over it. Running it on the mount would leave root-owned changes in the host repo.
6. **Extend the M9 repro run.** It currently stops at M6. If RC is in scope, it must also re-reach M8.
7. **Correction to the evidence packet.** `git_clone.sh:115-119` reads `Near-Real-Time-RIC/commit_hashes.json` first and falls back to the *repo root* (`git_clone.sh:45`). It does not fall back to `$HOME`. Dropping the L file into `Near-Real-Time-RIC/commit_hashes.json` is therefore the correct selection mechanism.
8. **Pacing is a design input for P3.** None of the scratch scenarios at 8c42089 uses `RealtimeSimulatorImpl`. ns-3 already has metric and control semaphores (`LteEnbNetDevice::UseSemaphores`) that could provide lock-step pacing. P3 must choose between real-time and lock-step explicitly.

## Advice checkpoint (kongming)

- **/ak-goal-warmup: GO**, with the errata above attached.
- **/goal: NO-GO** until the user answers Q1, Q2 and Q4.
- **P0 (host-only, read-only work) can start now.**

Top risks:

1. The KPM header contract.
2. Agent design: pacing, IPC, and one network namespace per agent.
3. The environment: the VM is not yet identified, Ubuntu 20.04 is past end of life so apt sources may drift, k8s 1.33 on cgroup v1 (probably fine, since kubelet refuses cgroup v1 by default only from 1.35), virtiofs write behaviour, and the older L images (rc pod churn).

## Ranking appendix

| Rank | Candidate | Score (of 100) | Recommended design | Verifier's note |
|---|---|---|---|---|
| 1 | **E (this contract)** | 85 | Out-of-process E2 agent per gNB, connecting to the e2term Service | Most faithful to the directive; precise L drop-in; strong M7 pod-delete reconnect test; weakness: the M6 v3/RC_OK conflict |
| 2 | C | 83 | In-process, contract-first | Best evidence and acceptance criteria, but the in-process design fails with more than one gNB, as the e2sim source shows |
| 3 | D | 80 | Out-of-process bridge using ns-3's file mode | Conflict in G5; repro is only partial |
| 4 | A | 77 | In-process first | Wrong `$HOME` fallback claim |
| 5 | B | 76 | File-mode bridge | Turned an already-corrected misdiagnosis (TS letter case) into a user question |

Hard constraints: all five passed. Verifier confidence: high on the facts, moderate on the ranking. If evidence and acceptance criteria were weighted above faithfulness to the directive, C would have won.

ultra: picked=2/5 margin=low unanimous=no rejected_all=no

## Unresolved questions (answer these before `/goal`)

1. **KPM header contract (required).**
   - (a) Encode the header the way kpimon decodes it, with the v2 4-byte TimeStamp. This is the verifier's recommendation.
   - (b) Accept RC_WMORE, provided it matches NIST's own reference capture.
   - (c) Fork kpimon.
2. **E2 outside ns-3.** Is an out-of-process IPC agent acceptable? Must the RIC's subscription parameters (report period, metric set) drive ns-3's reporting?
3. **Closed-loop scope.** Is rc-xApp-driven control enough, or must a real TS+QP loop drive it?
4. **VM details.**
   - What are the domain name, IP, virtiofs tag and fresh snapshot name?
   - Is a disk of at least 120 GB acceptable?
   - Can I run `virsh` snapshot and revert without sudo?
   - May the VM be created now on the `VMs-HDD` pool, which has 1.17 TiB free, instead of waiting for disk space to be reclaimed?
5. **Fallback to N (low priority).** Is N acceptable only if L fails at runtime?

---

## User answers (2026-10-21) — these win over the contract and errata on any conflict

**Environment (replaces the Platform, virtiofs and Snapshots constraints, and M0)**
- **VM.**
  - `ssh oran-kvm-2404` reaches user `uc` at 192.168.122.137. The libvirt domain is `ubuntu24.04` (qemu:///system).
  - 8 vCPU, 16 GiB RAM, 100 GB disk.
  - The disk file stays at `/home/andang/VMs` on the host SSD, kept there for iteration speed. The rule to stop when the host has under 20 GB free still applies.
- **OS.** Ubuntu **24.04.5**, which is intended. The 20.04-only rule is dropped; NIST v1.8.0 supports 24.04. This removes the k8s 1.33 / cgroup v1 risk because 24.04 uses cgroup v2. The new risk is building ns-3-mmwave-oran with GCC 13.
- **Snapshots.** The base snapshot is `fresh-install`, an external snapshot taken while the VM was shut off. It already includes passwordless sudo for `uc`, checked with `sudo -n true`. M9 reverts to it. Never delete it.
- **virsh.** The host user is in the `libvirt` group, and polkit grants it management rights, so snapshot create and revert need no sudo. libvirt is 12.8. M0 must run one probe snapshot create and revert before any gate depends on it.
- **No shared folder or virtiofs.** Drop the virtiofs checks from M0 and erratum 5's mount concern.
  - Agents push WIP commits to the fork branches on GitHub as they go.
  - Day-to-day VM builds pull those commits.
  - Gate runs and M9 clone from GitHub at a pinned SHA.
  - The NIST installer always runs from a clone on the VM's own disk.

**Q1 KPM header: option (c).** Patch kpimon-go's `kpm2_0.asn` TimeStamp to `SIZE(8)`.
- Regenerate its decoder and ship the change as a `.patch` on a fork.
- At M6, header and message must both decode with `RC_OK` through kpimon's own decoder.
- First record a baseline with stock kpimon at M3, `header RC_WMORE` count included.
- Evidence: kpimon's schema is v2.0 (`version2(2)`, `SIZE(4)`). Our v3.00 schema and NIST's pinned e2sim (`da6f82f`, `TimeStamp.c`) both use `SIZE(8)`, and NIST's own `kpm_sim` already sends 8 bytes.

**Q2 E2 outside ns-3: accepted (Approach A).** Subscription handling is staged:
- **Now (A):** the agent accepts the subscription and forwards every ns-3 sample. ns-3 keeps its own `indicationPeriodicity` (default 0.1 s of simulated time) and its fixed metric set. Today ns-3 ignores the trigger definition (`oran-interface.cc`), and kpimon asks for `granulPeriod = 10000`.
- **Later (B):** the agent filters and aggregates per subscription. ns-3 does not change.
- **IPC rule:** every sample carries the full metric set and its simulation timestamp, so moving to B changes only the agent.
- ns-3 never applies the subscription itself.

**Q3 Closed loop: a ladder.** Each step is a gate with its own snapshot:
- R0 = M8: an rc xApp control triggers a handover in the ns-3 trace.
- R1: the same, scripted, on 2 or more gNBs.
- R2: the real TS xApp with a stub QoE predictor.
- R3: the real TS xApp plus the real QoE predictor, with KPM data from ns-3 flowing through InfluxDB.

M9 must reach the highest rung that has passed.

**Q5 / N: L only.** If L fails, stop, find the cause, look for a workaround and report to the user. N is not planned and is not used as a diagnostic control without asking. After the L migration is complete and verified, the user decides whether to do N.

**Still open, to settle in P3:** pacing, meaning the real-time scheduler or lock-step semaphores.

## User answers (2026-10-21, continued) — pacing

**Preference:** repeatable lock-step, meaning results that repeat run to run. The real-time scheduler is kept only as a possible demo mode. The staged P3 recommendation is accepted:
- M5–M7 run free, KPM only.
- Pacing is measured during M4.
- Lock-step with a per-step timeout T is the planned design from M8 onward. It is **not final until the gate below passes**.

**M4 addition: ns-3 timing measurement.** Record how fast simulated time runs compared with real time, in real seconds per simulated second.
- Configurations: scenario-zero with 1 gNB and with N gNBs.
- Conditions: at least at the default `indicationPeriodicity` 0.1 s and the default UE/traffic load.
- Method: real time measured on the VM with a monotonic clock, at least 3 repeats.
- Output: the measured numbers and the commit SHA, saved to the report.

**Hard stop before M8: pacing planning gate.** Do not start M8 work until all of these are done:
1. The M4 timing results are on hand. If they are missing or noisy, run more measurements first.
2. **Several independent kongming counsels.** Opus 5.5 at xhigh effort, each run blind to the others, each given the measurements and this contract. Questions:
   - lock-step versus real-time versus a hybrid;
   - how to choose T and what happens when it runs out;
   - how controls get safely from the IPC thread into the ns-3 thread;
   - how lock-step interacts with SCTP/E2 keep-alive timers and with subscription option B.
3. **Best-practice research:** how other projects pace ns-3 against outside controllers. Examples are ns-O-RAN with OpenRAN Gym semaphores, ns3-gym, Colosseum, and digital-twin and co-simulation work. Sources must be cited.
4. One synthesized pacing plan, written as a journal checkpoint. It covers the recommendation, how T is set, the rollback, and the M8 acceptance-criteria changes.
5. **User approval** of that plan before M8 starts.

## Current goal scope (2026-10-21)

The next `/goal` covers **M0–M7 only**. M8 (RC), the closed-loop ladder R0–R3, the pacing design and M9 are deferred. We will brainstorm and revise them later, starting at the pre-M8 planning gate. Every gate must still be scripted, so that M9 remains possible.

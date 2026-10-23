# kongming: P5 gate i2 run 3, the A1 threshold never reaches the TS xApp (a1mediator's stale RMR connection)

2026-10-24 08:40 KST. Model: Opus 5.5 (the caller's routing). This is advice only and never user approval. The VM was inspected read-only (`kubectl get/logs/exec cat`, `/proc`, `ip route get`). Nothing was changed and no pod was restarted.

## TL;DR
- **The diagnosis is right, with one refinement.** kube-proxy runs in **IPVS mode**, not iptables mode. The black hole needs two conditions together:
  1. a1mediator's RMR connection to the TS xApp was idle for 5.5 h, more than IPVS's 900 s idle expiry. So the old pod's FIN was never reverse-NATed, and a1mediator's socket stayed ESTABLISHED.
  2. `_dms_reinstall` deleted the Service, so the old ClusterIP left `kube-ipvs0`. Writes to it are now routed off the VM and never answered.
- **a1mediator does recover, but too late.** RMR 4.9.1 SI95 has no keepalive and no user timeout, and it keeps the endpoint open across route tables. The kernel aborts the socket only after `tcp_retries2=15`, about 15.4 min. Only then does RMR reconnect, and every 20010 sent in that window is lost.
- **Remedy (L-only, no code change, no test change):** restart the a1mediator pod after every TS xApp pod or Service replacement and before the rtmgr restart. Make it unconditional in gate i2 (every `--part`) and in r2's `ts_stub_pods_reset`. Prove it with new checks: a new a1mediator pod, type 20008 still present, and, after the threshold line, an ESTABLISHED connection to the *current* TS ClusterIP with an empty send queue.
- **Classification:** the same defect class as ruling 6, so report it and do not pause. Record it as **L finding 4** (L7 observed) on the Stop B list, as an extension of ruling 6. This re-run is the Failure Protocol's one kongming-guided fix. If the re-run is red → `PAUSE T6`. Name T5 in the journal if the threshold still fails to arrive after the restart.

## 1. Diagnosis: verified and refined
**Verified facts**
- **a1mediator links RMR SI95 4.9.1.** The image `ric-plt-a1:3.2.2` contains `librmr_si.so.4.9.1`, and the log line reads "ric message routing library on SI95 … (a68562a 4.9.1 …)".
- **Row 6 of the evidence `a1mediator-proc-net-tcp.txt`** is `10.244.0.21:46600 → 10.102.153.116:4560`:
  - st `01`, tx_queue `0x55B`, `tr=01` (retransmit timer), `retrnsmt=8`, rto 5145 clock_t (51.45 s ≈ 0.2 s × 2⁸).
  - At my read at 23:44:04 UTC: `retrnsmt=0x0C`, rto 12000 (120 s, TCP_RTO_MAX), same inode 4106293.
  - So segments are being sent and never ACKed. This is a black hole, not a buffered write.
- **The bytes match the sends.** tx_queue 1371 = 3 × 457 bytes, which is the three run-3 messages. RMR's cumulative counter now reads `target=service-ricxapp-trafficxapp-rmr.ricxapp:4560 open=1 succ=6 fail=0`: 3 sends in run 2 (delivered, three TS callbacks) plus 3 in run 3 (stuck).
  - Run 2 opened this connection. Before run 2 there was no 20010 route, so there was no connection.
- **kube-proxy and IPVS on the VM:**
  - kube-proxy `mode: ipvs` with `ipvs.tcpTimeout: 0s`, which keeps the kernel default.
  - Live `/proc/net/ip_vs_conn` entries show `ESTABLISHED Expires 899`, so the idle expiry is 900 s.
  - `vs.expire_nodest_conn=1`, `vs.sloppy_tcp=0`, `vs.conntrack=1`.
- **The deleted ClusterIP is routed off the VM.** `10.102.153.116` is absent from `kube-ipvs0`, and `ip route get 10.102.153.116` gives `via 192.168.122.1 dev enp1s0`.
- **Primary source for the IPVS behaviour.** Julian Anastasov (IPVS maintainer) says an IPVS connection is freed 15 min after its last packet, with no abort sent, and "following packets may get RST due to the missing IPVS connection" (lvs-users, 2020-05).
- **Corroboration.** a1mediator's connection to the rtmgr ClusterIP:4560 survived i2's rtmgr pod replacement cleanly: the IPVS entry now points at the new rtmgr pod `10.244.0.75`. That connection carries regular traffic. The one connection that broke was the idle one.

**RMR 4.9.1 source** (tag `4.9.1`, `src/rmr/`):
- `common/src/rt_generic_static.c:1373, :1491`: "all route tables share a common endpoint hash". The open fd survives every new rtmgr table, so an rtmgr restart cannot help.
- `si/src/si95/siwait.c:115-128`: a disconnect is noticed only when a readable fd's `recv()` returns ≤ 0. That happens on FIN, RST or a kernel error.
- `si/src/mt_call_si_static.c:298-334`: `mt_disc_cb` sets `ep->open = FALSE`.
- `si/src/rtable_si_static.c:257-264, :372-379, :439-445`: RMR reconnects (and re-resolves DNS) only when `!ep->open`.
- Socket options set: only `TCP_NODELAY` and `TCP_QUICKACK` (`si95/sinewses.c:83,90`; `si95/siestablish.c:208,215`), `SO_REUSEPORT` (`siestablish.c:102`) and `SO_LINGER` (`siclose.c:71`, `siterm.c:56`). There is no `SO_KEEPALIVE` and no `TCP_USER_TIMEOUT`.

**Inferred chain (high confidence; each step matches an observation)**
1. Run 2 (about 18:05 UTC): a1mediator connects to the TS ClusterIP `10.102.153.116`, delivers 3 messages, then goes idle.
2. About 15 min later, the IPVS connection entry expires. The TCP sockets at both ends stay ESTABLISHED.
3. Run 3, `ts_install` → `_dms_reinstall` (`scripts/gates/ts-lib.sh:62-71`, called at `:125`) runs `dms_cli uninstall`. The Service and its ClusterIP are deleted, and the old pod dies.
   - The old pod's FIN has no IPVS entry to reverse-NAT it, so it arrives from the pod IP, matches no a1mediator socket, and is dropped. The socket stays ESTABLISHED: state `01`, never `08` CLOSE_WAIT.
4. The new Service gets `10.98.118.139`. RMR never re-resolves, because `ep->open` is still TRUE.
5. Each 20010 is accepted into the socket buffer: RMR logs "message sent", `succ++`. The kernel retransmits into the off-VM route.

**Recovery without intervention (observed, §7).** The kernel aborts the socket with ETIMEDOUT at about T0 + 924.6 s (`tcp_retries2=15`, read inside the a1mediator netns). `select()` then flags the fd, `mt_disc_cb` runs, and the next send reconnects to the new ClusterIP. a1mediator never replays lost instances, so the TS xApp keeps threshold 0.
- **Observed:** row gone at 23:51:22 UTC; RMR `open=0` at 23:55:52 (section 7).

**Consequence for the next re-run.** Once the socket has aborted, a plain re-run of i2 would probably pass **without** any remedy, because a1mediator would then connect fresh. That green would prove nothing. Run 3's evidence plus the mechanism is the recorded root cause; the remedy must be unconditional and checked by its own steps.

## 2. What this means for r2 (the Services stay)
`ts_stub_pods_reset` (`ts-lib.sh:251-274`) deletes the pods and keeps the Services, so the ClusterIP stays on `kube-ipvs0`. There is no black hole, but the outcome depends on the idle time:
- **(a) a1mediator's last 20010 was less than 900 s before the pod deletion.** The IPVS entry is alive and the old pod's FIN is reverse-NATed. a1mediator sees EOF and reconnects cleanly on its next send.
  - This is the case between consecutive live runs: an R1 live run took about 2.7 min including its reset (`evidence/r1/20261023T084654Z/gate.log`).
- **(b) The idle time exceeds 900 s.** This covers the first run of any gate invocation: after i2, after `--mode calibrate`, between `--dev` and C1, and M9's `r2 --mode single` after i2 and C8.
  - The FIN is lost. a1mediator's next segment reaches the local ClusterIP with no IPVS entry; IPVS does not schedule a non-SYN packet when `sloppy_tcp=0`, so the local stack answers with a RST.
  - That 20010 is silently lost. `ts_policy_set` attempt 2 reconnects and succeeds.
  - This is inferred from kernel behaviour and the maintainer's note, not observed.
- **The same rule applies to `i2 --part stub`**, which follows the p5 probe. It reuses the TS pod from `--part ts`, and the connection will probably have been idle more than 900 s, so case (b) applies.
- **Other connections are not exposed:**
  - The injector starts in a fresh container each run (`ts-lib.sh:351-363`).
  - The TS→stub, stub→TS and TS→rc connections all come from fresh pods each run.
  - Trigger gaps inside a run are far below 900 s.
  - The e2term→TS connection (stray acks) has the same exposure. It stays recorded only, as in kongming-0245 A6. Restarting e2term would drop the agents' SCTP associations, so do not do it.

**Net effect.** Without the remedy, r2 would usually pass but would burn retry attempts nondeterministically. That conflicts with "RIC state is a measured precondition" (plan.md:124). With the remedy, every run sends its first 20010 on a fresh connection.

## 3. Remedy
**Placement.** Every pod replacement and registration comes before the a1mediator restart, which comes before the last rtmgr restart.
- **New helper `a1mediator_restart <label>` in `ts-lib.sh`:**
  - Mirror `rc_restart_rtmgr` (`rc-lib.sh:105-117`): `kc -n ricplt delete pod <a1mediator> --wait=true`, then wait for a new pod that is `1/1 Running` and named differently.
  - Write `$e/<label>-a1mediator-before.json` and `-after.json` (name, uid, podIP, restartCount, startTime).
  - Use pod deletion, not `rollout restart`. `rollout restart` writes a permanent annotation into the Deployment. Under its RollingUpdate maxSurge of 25% (that is, 1 pod) it would also briefly run two a1mediators against SDL and rtmgr.
- **Gate i2:** insert `check i2_a1mediator_restarted_after_ts_ready a1mediator_restart i2` between `i2_appmgr_xapp_list_saved` and `i2_rtmgr_restarted_after_registration` (`gate-i2-ts-xapp-install.sh:60-61`). Run it for **every** `--part`.
- **r2's `ts_stub_pods_reset`:** call it after `xapp_list_save` and before `rc_restart_rtmgr` (`ts-lib.sh:263-265`).
- **Do not touch `rc_ric_reset`** (`rc-lib.sh:180-209`). It is shared with the green R0/R1 path, which uses no A1.
- **What already covers the side effects:**
  - rtmgr's connection to the old a1mediator goes stale. The following rtmgr restart cures it, and `RTMGR_PEERS` already demands a session to a1mediator (`ts-lib.sh:44-45`).
  - Policy types and instances live in SDL, so they survive the restart. Check that, as listed in section 5.
- **P8 inherits this.** The r3 reset also replaces the TS pod. Reuse the same helper there, and in i3 if it replaces the TS pod.

**Alternatives rejected**
| Alternative | Why not |
|---|---|
| Rely on `ts_policy_set` retries | It does not fix i2 (a black hole for about 15 min, longer than 3 × 20 s), and in r2 it makes the attempt count nondeterministic. |
| Wait out `tcp_retries2` (about 15.4 min), then re-send | Slow and nondeterministic, and it hides the defect. |
| `ss -K` or `nsenter` to kill the socket | Root-level surgery inside a platform pod's netns. It is more fragile and more exotic than a restart, and it would need host-style privileges. |
| Tune kube-proxy `ipvs.tcpTimeout` or a1mediator `tcp_retries2` | A cluster or chart configuration change. It does not cure the deleted-ClusterIP case, and M9 would have to reproduce it from fresh-install. |
| Keep the TS Service in `ts_install` (`helm upgrade` instead of reinstall) | It departs from NIST's installer, still leaves the pod-replacement case, and does nothing for `--part stub`. |

## 4. Classification under the locked contract
**Report it and do not pause.** Record it as an extension of ruling 6 and as **L finding 4** for Stop B. The reasons:
- **Same class as ruling 6.** Ruling 6 covers the T5 reading "rtmgr never reconnects to a replaced xApp pod", remedied by a pod restart (`decisions-261024-0204…:12`). This is the same RMR SI95 endpoint-cache defect, through IPVS ClusterIPs, in another L component.
  - The harness already documents the class for rtmgr: `rc-lib.sh:18-23`.
  - kongming-0245 §4 L7 pre-declared exactly this remedy and this reporting path.
- **It keeps the contract:**
  - No TS xApp change beyond substitution 3, and no change to the a1mediator image, configuration or chart.
  - No test is weakened; checks are added.
  - A1 stays end to end, so in-scope item 6 ("then the A1 threshold is set") is met as written.
  - In-scope item 7's reset list gains a component and loses nothing.
  - "Any rtmgr or e2term change" is out of scope (goal-packet.md:16), but a pod restart is not a change by the ruling-6 precedent, and a1mediator is not on that list anyway.
- **Honest caveat:**
  - plan.md:85 ("Report, do not pause") does not list L-only remedies, and T5 reads "an L-release failure" (plan.md:80).
  - The run's established reading, which the user ratified with ruling 6 and implicitly accepted by putting L finding 3 "next to L finding 2", is: an L failure with a contract-preserving L-only remedy is reported and ratified at Stop B.
  - A strict reader could still want a pause. Record that trade-off in the journal and the implementation notes now, not only at Stop B.
- **When it flips to a PAUSE:**
  - **T6:** the re-run of i2 is red for any reason. This is the one kongming-guided fix for this failure.
  - **T5** (named alongside T6 in the journal): the threshold still does not arrive after the a1mediator restart, the stale-connection check is clean, and the route and sessions are present.
  - **T3:** the remedy would need an a1mediator, rtmgr or e2term configuration or code change, a kube-proxy change, or a relaxed threshold check.
  - **T8:** the classifier refuses the ricplt pod delete. Never work around it.

## 5. Checks to add, and RestartCount semantics
**Gate i2 and the r2 per-run reset (same helpers)**
1. `…_a1mediator_restarted_after_ts_ready` (the remedy). The new pod's uid differs from the old one, it is Ready, and its restartCount is 0. Write the before/after JSON. In r2, extend `check-ts-stub-reset.py`, which reads only ricxapp, or add a small ricplt sibling, so that freshness covers a1mediator.
2. Keep the existing rtmgr-session check after the rtmgr restart. It already includes a1mediator.
3. `…_a1_policy_type_20008_survives_a1mediator_restart`: a GET-only check that returns 200 with the expected schema and never re-creates the type. A missing type would be a new SDL finding, so fail loudly.
4. Keep `ts_policy_set` unchanged (3 attempts × 20 s). Add a fact `a1ThresholdAttempt` (1, 2 or 3) per run. The expected value with the remedy is 1. Do not make "attempt 1" a pass condition; the contract allows bounded, logged retries for bring-up preconditions.
5. `…_a1mediator_connection_to_current_ts_xapp`, after the threshold line:
   - Save a1mediator's `/proc/net/tcp` **every time**, not only on failure.
   - Assert at least one state-`01` row to `<current TS ClusterIP>:11D0` with tx_queue 0.
   - Assert no state-`01` row to any `:11D0` remote that has a non-zero tx_queue.
6. Optional: a bounded wait (≤ 40 s) after the rtmgr restart for a1mediator's RMR stats line naming `target=service-ricxapp-trafficxapp-rmr.ricxapp:4560`. That line proves a1mediator holds a table with the TS xApp in it, so attempt 1 is not spent on a table that has not arrived yet.
7. Verdict facts:
   - `a1mediatorRestart` per run (old and new name, uid, IP);
   - `a1mediatorRestartCountAtEnd` (recorded, expected 0);
   - `substitution3Applied` (already present).

**RestartCount semantics**
- `rc_restarts_zero` reads `<label>-pods.tsv` from `rc_pod_snapshot` (`rc-lib.sh:137-159`). It covers every ricxapp pod (rc, kpimon, hw-go, the TS xApp, the stub, later QP) plus the agent containers. It does not cover ricplt (a1mediator, rtmgr, e2term and the rest). This is stricter than the contract's list (goal-packet.md:14).
- RestartCount counts in-place container restarts of one pod. a1mediator's current 10 come from VM reboots. A deliberate pod deletion yields a new pod with 0.
- This is the ruling-5 reading ("only the pod is recreated … keeps RestartCount = 0 meaningful").
- Keep a1mediator's count recorded, not judged. It is not in the contract's list, and A1 delivery is proven by the threshold line plus the connection check.

## 6. Re-run and must-dos
**Before the re-run**
1. Record the root cause in `implementation-notes.html` and the journal as L finding 4 (L7 observed, IPVS refinement). Add a standards-ledger row in phase-05: "a1mediator pod restart after a TS xApp pod or Service replacement: no spec decision; O-RAN SC RMR 4.9.1 SI95 transport behaviour behind kube-proxy IPVS ClusterIPs, not A1AP or E2AP."
2. Commit the harness change: the helper, both call sites and checks 1, 3, 4, 5 and 7. Push.
3. Update the resume card: i2 re-run in flight.

**Verification: a fresh `gate-i2-ts-xapp-install.sh --part ts`, same command as run 3**
Green requires every existing check plus:
- `i2_a1mediator_restarted_after_ts_ready` PASS;
- the rtmgr session to a1mediator PASS;
- the type 20008 GET PASS;
- `Setting Threshold for A1-P value: 10%` in the TS log, with `a1ThresholdAttempt` = 1 expected;
- a1mediator's table showing ESTABLISHED to `<new TS ClusterIP>:11D0` with tx_queue 0;
- `substitution3Applied: true`.

If it is red → `PAUSE T6` (the journal names T5 if the cause is still on the L side).

**Then the planned sequence**
1. Gate p5 probe (no A1, no change needed).
2. `i2 --part stub`: the a1mediator restart runs here too and covers case (b).
3. r2 `--mode calibrate`.
4. `--dev` with at least 2 resets: in every run, a fresh a1mediator, `a1ThresholdAttempt` = 1 and the connection check green.
5. C1.

**For P8 (R3) and M9:** the r3 reset reuses `a1mediator_restart`. M9's i2 from fresh-install has no prior connection, but its r2 and r3 resets still need the remedy (case (b) after i2 and C8).

## What to avoid
- **Re-running i2 unchanged.** After about 23:51 UTC the stale socket has aborted, so a green run would be accidental and the defect would come back in r2 and M9.
- **Adding a1mediator to `rc_ric_reset`.** That changes the green R0/R1 code path.
- **Raising `ts_policy_set` attempts or timeouts to "absorb" the defect.** That masks it, and it is still about 15 min too short for i2.
- **`kubectl rollout restart` on the a1mediator Deployment.** It mutates the Deployment object and can briefly run two pods.
- **Making a1mediator's RestartCount a pass condition, or treating the deliberate restart as a contract RestartCount violation.**

## Assumptions
| # | Assumption | Confidence | What would change the answer |
|---|---|---|---|
| A1 | IPVS's 900 s expiry explains the missed FIN in run 3. The idle time was 5.5 h, and a regularly used a1mediator connection survived the rtmgr replacement. | High | A FIN observed at a1mediator after a replacement within 900 s, with the socket still stale, would point to the old TS process not closing. The remedy would not change. |
| A2 | In r2, case (b) gives a local RST rather than a black hole, because the ClusterIP stays on `kube-ipvs0`. | Medium (inferred from kernel code and the maintainer's note, not observed) | If it black-holes instead, r2 without the remedy would fail like i2. The remedy covers both cases. |
| A3 | Policy types and instances survive an a1mediator pod restart, because they live in SDL (dbaas). | High (kongming-0245 L7; a1mediator 3.x stores them in SDL) | Check 3 fails, which gives a new L finding and T6/T5. |
| A4 | Deleting the a1mediator pod has no side effect on the agents, kpimon or rc. a1mediator talks only to SDL, rtmgr and the xApps that receive 20010. | High | Any agent or kpimon disturbance in the `--dev` runs. |
| A5 | The user accepts this as a ruling-6 extension at Stop B. | Medium-high (precedent: ruling 6, L finding 2) | If the user rejects it, the alternatives in section 3 all cost more. Option 2 of the 0320 note (forged A1) remains a T3 path. |

## 7. Observed self-heal (read-only watch, 2026-10-23 UTC)
- **23:49:02–23:51:02:** row 6 stays ESTABLISHED with tx_queue `0x55B`. `retrnsmt` rises to `0x0F` (15) at 23:49:22, and the timer is due at about 23:51:06.
- **23:51:22:** the row is gone. This is the kernel abort at the 16th timer fire, matching `tcp_retries2=15`, about 15.5 min after run 3's first 20010.
- **23:54:41:** the a1 process (PID 7) no longer holds `socket:[4106293]`. A kernel abort alone leaves the fd open, so RMR SI95 ran its disconnect path (`siwait.c:121-127` → `mt_disc_cb`) and closed it.
- **RMR stats lines:** at 23:50:51 (before the abort), `open=1 succ=6`; at **23:55:52, `open=0 succ=6 fail=0`**.
  - RMR marked the endpoint closed, so the next 20010 would reconnect.
  - RMR still counts the three lost messages as successes, so "message sent" and `succ` are no evidence of delivery.
- **This confirms the whole chain by observation:** a silent black hole, recovery only through the kernel's `tcp_retries2`, and no RMR-level detection before then.
- **No instance was replayed.** The TS xApp still has threshold 0, and a1mediator now has **no** connection to the TS xApp: there is no IPVS entry to `10.98.118.139:4560`.

## Unresolved questions
- The user's Stop B ratification of L finding 4 as a ruling-6 extension.
- Whether case (b) in r2 gives a RST or a black hole. This becomes moot with the remedy, but the `--dev` runs record `a1ThresholdAttempt` either way.

Sources: [lvs-users, Julian Anastasov, 2020-05 (IPVS idle expiry, no abort, later RST)](https://archive.linuxvirtualserver.org/html/lvs-users/2020-05/msg00003.html); [kube-proxy IPVS timeout fields (AKS docs)](https://learn.microsoft.com/en-us/azure/aks/configure-kube-proxy).

Status: DONE. Diagnosis confirmed and refined: an IPVS idle expiry plus the deleted ClusterIP leave a1mediator's RMR 4.9.1 connection writing into a black hole for about 15 min. Remedy: an unconditional a1mediator pod restart before the rtmgr restart in i2 and in the r2 reset, with new checks. Report it as L finding 4 (a ruling-6 extension) and re-run i2 `--part ts` fresh; a red re-run means PAUSE T6.

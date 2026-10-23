# Milestone: M8–M9 segment 1 (P0–P4) complete, Stop A

Date: 2026-10-23 18:10 KST. Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`. Contract: `goal-packet.md` (locked). Journal: `docs/journals/2026-10-23-m8-m9-stop-a.md`.

## Outcome
R0 (= M8) and R1 both pass their full scripted repeat gate C1 on the VM `ubuntu24.04`, at unchanged fork pins. Three live runs per rung are byte-equal on every component, the RIC-free replay equals them, and `--RngRun=2` changes the digest. Segment 2 (P5–P9) can start after the user rules on the items below.

| Gate | Evidence (under the plan's `evidence/`) | Harness | Checks | Duration |
|---|---|---|---|---|
| R0 calibration | `r0/20261023T065002Z` | `02846b7` | 32/32 | 5 min |
| R0 = M8, C1 | `r0/20261023T073520Z` | `cfc6ef4` | 109/109, V1–V9 | 19 min |
| i0 (rc install; first run ever) | `i0/20261023T082556Z` | `cc017a1` | 8/8 | 3 min |
| R1 rehearsal (`dev: true`) | `r1/20261023T082845Z` | `57be9f0` | 123/123 | 17 min |
| R1, C1 | `r1/20261023T084654Z` | `1b6e4ea` | 123/123, V1–V6 | 17 min |

Fork pins (`scripts/pins.conf`, branch `dev/l-release-nist180`, unchanged since P2): ns-3 `962fabc7`, oran-interface `63155c49`, Testbed `4c8397d0`. rc `a2282ee`.

**R0** applies three controls, one through each D7 path (eNB, serving gNB, target gNB), to 3 IMSIs and targets {2, 3}. It also produces one already-on-target refusal and one forced-late control. Every ACK's outcome decodes to E2SM-RC Control Outcome Format 1 with the P0 decoder. `kpmUeListMoved` is {1, 3, 6} on the decoded KPM UE lists, C5 holds, and every per-run reset is proven fresh.

**R1** covers the four required cases:
- (a) a same-step pair through two agents: both applied.
- (b) one IMSI, the same agent, targets 3 and 2: target 2 applied, target 3 refused `inHandover`. Target 3 was sent first, so the cause proves the C4 sort rather than arrival order.
- (c) one IMSI through agents 3 and 2: the lower nodeId (2) applied, the other refused `inHandover`.
- (d) an unknown IMSI: refused `unknownImsi`.

D7 is 1/2/1 and `kpmUeListMoved` is {1, 2, 3, 6}. C2 holds as 7 = 7 + 0, with static rejects 0 and post-bye failures counted separately. Fault run (ii): a control sent after the final barrier through the eNB agent gets exactly one RICcontrolFailure `control-failed-to-execute` and no ledger line. Agent 1 counts it as failed on bye (`failedOnBye` 1, `rejIpcDown` 0). The Influx dump of live1 has 39,257 rows and 0 hits for the token or its shape.

## Report only (no pause)
- **Substitution 1 applied.** The R0-config null-control run at −5 dB has 5 LTE outage switches (Q2 = 5 in every R0 run), so the gated runs use `--outageThreshold=-1000`. This is recorded in `rung-config.json`.
- **T_ctl re-set: 30 s.** It is calibrated from L_max 12.9 ms over 10 complete trigger steps: max(30 s, ceil(20 × L_max)). W is still at its start value of 1 s and is re-set at R2/R3.
- **N5 match.** G4 decodes the e2mgr nodeb keys `0000000202` and `0000000303`, and the eNB keeps `reqpart`. The offline replay of the TS xApp's `cell_map` gives the same keys.
- **L-release finding (T5 reading).** rtmgr never reconnects to a replaced xApp pod. The per-run reset therefore restarts rtmgr and waits for rc's own RMR-ready line; this remedy uses only L components.

## User rulings needed (each with a recommended default)
1. **T8 reading of the P0 refused probe** (an unplanned delete command that the classifier refused, 01:38 KST). Default: not T8, since it was not a scripted command. From then on any refusal counts as T8.
2. **K5 is shown by integration cases** (S1 fb1 and R1 (b)), not by an ns-3 unit test. Default: accept.
3. **"late" also covers a control that misses its barrier mid-run** (K9 in R0, S1 `midlate`). Default: yes.
4. **RAN function 3 is not announced in E2 Setup.** The agents announce only KPM (function 2) but accept RC controls; E2AP v03.00 §8.2.4.3 says an unannounced function gets a FAILURE. You approved this with the issue known. Should it be listed as a recorded deviation? Default: list it.
5. **kpimon and hw-go are recreated each run,** against the contract's "hw-go (stays deployed)". Default: the deployment stays and only the pod is recreated, which is what keeps RestartCount = 0 literal.
6. **The rtmgr restart in the reset, and the T5 reading above.** The −1 route owner moves within a run; both rtmgr's and e2term's views are recorded, and owner identity is not a pass condition. Default: accept.
7. **ns-3 trace text files are gitignored,** with sha256 manifests. Default: accept.
8. **Fault run (ii) goes through the eNB agent.** Post-stop controls through nodes 2 and 3 get a `late` ledger line by design. The two P2-deferred fork items are dropped: the stop-loop drain would break V4, and the departure fix is not needed. Default: accept, and optionally bundle the departure fix into P6's fork change.
9. **C9 file naming.** The contract names `UeHandover*`; the checker reads `EnbHandover*`, and both agree in the evidence. Default: accept.

## Disk ledger and M9 projection
| Point | Host `/home` free |
|---|---|
| P0 baseline | 76 G |
| P3 exit | 57 G |
| Stop A (now) | 55 G |

- **Image chain:** base 3.3 G, `f7-rerun-green` overlay 37 G, the P1–P3 overlay frozen under `r0-green` 14 G, and the active overlay 2.1 G. The plan's local evidence is 2.3 G, mostly gitignored pcaps and traces. Rootless podman lives on `/mnt/data`.
- **Segment-1 growth:** 21 G.
- **M9 projection:** 55 − about 10 remaining dev (P5–P8: R2, the N4 ns-3 rebuild, QP image builds, R3) − about 48 M9 − 20 floor = **about −23 GB**. It was −19 GB at P2 and P3 because those projections assumed about 8 G of remaining dev growth.
- **Options for Stop B,** where you free the measured shortfall:
  - free space outside the VM images: `/home` holds other data, and the 2.3 G of local evidence pcaps could move to `/mnt/data` after their manifests are committed;
  - fewer dev snapshots: `r2-green` is optional to keep;
  - a user-approved deletion after `r3-green` and the reference exist, measured first, since deleting a non-leaf snapshot frees almost nothing.

## Carry-forward
- **P5/P8:** replacing the TS xApp or QP pods will hit the same rtmgr defect. Check `RMR_SEED_RT`, restart rtmgr, and check KPM continuity.
- **Before Stop B:** fix M3's kpimon log reader (`gate-m3-xapps.sh:162`) and re-run M3.
- Record kube-controller-manager and kube-scheduler restart counts per run.
- M7's 150 unseen indications are still unexplained (informational).
- **P0 partials:**
  - K13: `run-to-m9.sh` does not read `rung-config.json`;
  - K16: VM-side traces are not deleted;
  - `--harness-sha HEAD` is not resolved to a full SHA;
  - `--min-gb` cannot be passed through the runner;
  - watchdog files are not archived per run;
  - shellcheck skips `tools/`.
- Samples 0 and 1 share a Collection Start Time (an observation).
- Gate i0 first ran on 2026-10-23 at 17:26 KST.
- A kongming consult is due before P6's UL counter lands.

## Unresolved questions
- Rulings 1–9 above.
- The M9 disk shortfall of about 23 GB, settled at Stop B.

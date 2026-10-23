# Milestone: M8–M9 segment 1 (P0–P4) complete, Stop A

Date: 2026-10-23 18:10 KST. Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`. Contract: `goal-packet.md` (locked). Journal: `docs/journals/2026-10-23-m8-m9-stop-a.md`. Segment review and P5 go/no-go (kongming): `plans/reports/kongming-261023-1815-GH-1-stop-a-segment-1-review-and-p5-go-no-go.md` (segment 1 conforms to the locked contract; no narrowing, no weakened test; P5 GO after the rulings below).

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
- **Per-control latency in R1.** A first control in a step took 7–12 ms; a second control in the same step through another agent took about 0.04 s, and through the same agent about 0.20 s, in all three live runs (0.200, 0.206, 0.203 s). T_ctl = 30 s covers this by far, but it feeds W at R2/R3 (cause unverified; SCTP delayed acknowledgements are a guess).
- **L-release finding (T5 reading).** rtmgr never reconnects to a replaced xApp pod. The per-run reset therefore restarts rtmgr and waits for rc's own RMR-ready line; this remedy uses only L components.

## User rulings needed (each with a recommended default)
1. **T8 reading of the P0 refused probe** (an unplanned delete command that the classifier refused, 01:38 KST). Default: not T8, since it was not a scripted command. From then on any refusal counts as T8.
2. **K5 is shown by integration cases** (S1 fb1 and R1 (b)), not by an ns-3 unit test. Default: accept.
3. **"late" also covers a control that misses its barrier mid-run** (K9 in R0, S1 `midlate`). Default: yes.
4. **RAN function 3 is not announced in E2 Setup.** The agents announce only KPM (function 2) but accept RC controls; E2AP v03.00 §8.2.4.3 says an unannounced function gets a FAILURE. You approved this with the issue known. Should it be listed as a recorded deviation? Default: list it.
5. **kpimon and hw-go are recreated each run,** against the contract's "hw-go (stays deployed)". Default: the deployment stays and only the pod is recreated, which is what keeps RestartCount = 0 literal.
6. **The rtmgr restart in the reset, and the T5 reading above.** The −1 route owner moves within a run; both rtmgr's and e2term's views are recorded, and owner identity is not a pass condition. Default: accept.
7. **ns-3 trace text files are gitignored,** with sha256 manifests. Default: accept.
8. **Fault run (ii) goes through the eNB agent.** The contract's "exactly one FAILURE" holds through every node; only V4's "0 ledger lines" is specific to node 1, the only node whose post-stop control takes the bye path. That nodes 2 and 3 give a `late` ledger line instead was read from the code at the pins; it was never run and no gate covers it. The two P2-deferred fork items are dropped: the stop-loop drain would break V4, and the departure fix is not needed. Default: accept, and optionally bundle the departure fix into P6's fork change.
9. **C9 file naming.** The contract names `UeHandover*`; the checker reads `EnbHandover*`, and both agree in the evidence. Default: accept.

## Disk ledger and M9 projection
| Point | Host `/home` free |
|---|---|
| P0 baseline | 76 G |
| P3 exit | 57 G |
| Stop A (18:05 KST) | 55 G |
| 19:32 KST | 54 G |

- **Image chain:** base 3.3 G, `f7-rerun-green` overlay 37 G, the P1–P3 overlay frozen under `r0-green` 14 G, and the active overlay 2.1 G. The plan's local evidence is 2.3 G, mostly gitignored pcaps and traces. Rootless podman lives on `/mnt/data`.
- **Segment-1 growth:** 21 G.
- **M9 projection:** 54 − about 10 to 12 remaining dev − about 48 M9 − 20 floor = **about −24 to −26 GB**.
  - Remaining dev, by phase: P5 about 2 G (TS xApp and stub images, R2 runs), P6 about 5 G (the N4 ns-3 rebuild), P7 about 2 G (QP image builds), P8 about 2–3 G (R3 runs).
  - M9 overlay: `f7-rerun-green`'s measured 37 G for M0–M7 plus about 11 G for i0, R0–R3 and the TS xApp and QP installs.
  - The earlier figures were −19 GB at P2 (60 − 11 − 48 − 20) and at P3 (57 − about 8 − 48 − 20); the change is the measured segment-1 growth and the per-phase basis above.
  - K16 (VM-side traces are never deleted) inflates the M9 overlay; fixing it by P9 reduces the shortfall.
- **Options for Stop B,** where you free the measured shortfall:
  - free space outside the VM images: `/home` holds other data, and the 2.3 G of local evidence pcaps could move to `/mnt/data` after their manifests are committed;
  - fewer dev snapshots: not recommended. `r2-green` is P5's exit snapshot (Verify V6) and the rollback point for P6–P8, so skipping it needs your ruling and saves little;
  - note that `/mnt/data` (rootless podman) has only 21 G free (91 % used), so moving data there is limited;
  - a user-approved deletion after `r3-green` and the reference exist, measured first, since deleting a non-leaf snapshot frees almost nothing.

## Carry-forward
- **P5/P8:** replacing the TS xApp or QP pods will hit the same rtmgr defect. Check `RMR_SEED_RT`, restart rtmgr, and check KPM continuity.
- **Before Stop B:** fix M3's kpimon log reader (`gate-m3-xapps.sh:162`) and re-run M3.
- Record kube-controller-manager and kube-scheduler restart counts per run.
- M7's 150 unseen indications are still unexplained (informational).
- **P0 partials, due by P9:**
  - K13: `run-to-m9.sh` does not read `rung-config.json`;
  - K16: VM-side traces are not deleted;
  - `--harness-sha HEAD` is not resolved to a full SHA;
  - `--min-gb` cannot be passed through the runner;
  - watchdog files are not archived per run;
  - shellcheck skips `tools/`.
- Samples 0 and 1 share a Collection Start Time (an observation).
- Gate i0 first ran on 2026-10-23 at 17:26 KST.
- A kongming consult is due before P6's UL counter lands.
- The P5 must-do list and the TS xApp landmines (REST-mode descriptor default, `RMR_SEED_RT`, A1 threshold delivery, prediction format, substitution 2 registration) are in §3.3 and §2 of the kongming segment review.
- Live runs have no explicit `late` field: late = 0 is enforced only through the exact expected outcomes. Gate r2 adds an explicit per-run field.
- The 4.8 MB Influx dump of R1 live1 is committed, although `evidence/.gitignore` says raw dumps stay out of git. Default: gitignore it with a sha256 manifest. Your call.

## Unresolved questions
- Rulings 1–9 above.
- Whether the committed Influx dump stays in git or moves behind a sha256 manifest.
- The M9 disk shortfall of about 24–26 GB, settled at Stop B.

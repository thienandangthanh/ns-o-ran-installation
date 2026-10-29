# M9 run report: M8–M9 paced closed loop on the L-release RIC (amendment A1)

**Result: M9 PASS.** One unattended invocation from `fresh-install` exited 0. All 14 pre-registered steps passed. R3′ is the highest green rung: its full C1 passed and it equals the committed reference. Host free never fell below 59 GiB, and the watchdog stayed alive throughout.

Verdict: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T165825Z/verdict.json` (`pass: true`, `problems: []`). Every value below is taken from that verdict, its `steps.tsv` and `runner.log`, the per-step gate verdicts, and the unit journal. Contract: `goal-packet.md` (A1).

## Run

| Item | Value |
|---|---|
| Runner command | `scripts/run-to-m9.sh --harness-sha 39b3ba21d46d9e347d14d2841a8abe1ace1ccb05 --run-prefix q --no-snapshots`, run as the transient user unit `m9-q` (`systemd-run --user --wait`, KillMode=mixed; phase-10 Launch-route amendment), after `scripts/vm/vm-snapshot.sh revert fresh-install` |
| Exit code (V1) | client `rc=0`, `Finished with result: success`, `status=0/SUCCESS` (`evidence/m9/20261028T165825Z/client-exit.txt`, copied from the launch client's output); the unit journal (`unit-journal.txt`) has no `Main process exited` or `Failed with result` line, unlike attempt 3's (`evidence/m9/20261028T134954Z/unit-journal.txt`) |
| Start / end (UTC) / wall | 2026-10-28 16:58:25 / 20:29:08 / 12,643 s of the budgeted 20,199 s |
| Harness SHA (frozen) | F″ = `39b3ba2`: F′ `fb3554a` (the P9 freeze F `e0a6ac5` plus the atomic heartbeat write) plus the bring-up fix in `scripts/gates/bringup.sh`, `agents.sh` and `rc-lib.sh` (`m9-budget.md` F″ addendum) |
| Pins (verdict `pins`) | Testbed `c6d1434a`, ns-3 `ba954440`, oran-interface `96efc40e`, e2sim `2209995a` (`scripts/pins.conf`, re-checked with `git ls-remote` at pre-flight) |
| Step set (V2) | `m0 m1 m2 m3 m4 m5 m6 m7 i0 r0 r1 i2 r2 r3p` = verdict `expectedSteps`; `exactStepSet: true`, `notM9: false`, every step `pass: true` |
| Top rung | R3′ (`highestGreenRung: r3p`; no substitution 4 record) |
| Top rung C1 (V3) | `evidence/r3p/20261028T200710Z`, mode `c1`: `liveRunsEqual`, `replayEqual` and `rngRun2Differs` all true; `predictorDrivenApplied` 1/1/1; 168 PASS lines in `gate.log` (167 checks plus the verdict line), 0 FAIL |
| equalsReference (V3) | `true` against `reference/r3p/` (made from `evidence/r3p/20261028T044557Z` live1; not regenerated) |
| minHostFreeGb / watchdog (V4) | 59 GiB (floor 25; trip 29). Watchdog alive throughout: 420 checks every 30 s, `maxAgeS` 30, last check 29 s before the end. None of `watchdog-tripped.json`, `watchdog-lost.json`, `wall-deadline.json` or `monitor-lost.json` exists. In `free-series.tsv` (421 samples, 101 → 59 GiB) the peak drop was 0.067 GiB/s, a single 2 GiB step within one 30 s sample at 1 GiB rounding. That exceeds the budget's 0.0093, but the run never came near the trip. |
| substitution3Applied (verdict map) | r0 `false`, r1 `false`, r2 `true`, r3p `true` |
| Attempts before this one | 1: `evidence/m9/20261028T092148Z`, prefix n at F, m0–m1 green, cancelled in m2 by a torn heartbeat read → guided fix F′. 2: `evidence/m9/20261028T112207Z`, prefix o at F′, m0–m2 green, reaped in m3 by Claude Code's low-memory reaper (environmental, PAUSE T8; host reboot and launch route ruled by the user). 3: `evidence/m9/20261028T134954Z`, prefix p at F′, m0–m5 green, m6 red: after a cold boot the RMR route-table readers in e2mgr and submgr stopped reading rtmgr's pushes, so the E2 Setup Response had no route → guided fix F″, validated on the wedged VM (`plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/m6/20261028T164804Z`) |

## Per step

Duration is measured from the gate start to the green boundary, including the boundary reboot.

| Step | Status | Duration (s) | Timeout (s) | Evidence |
|---|---|---|---|---|
| m0 | pass | 111 | 716 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m0/20261028T170012Z` |
| m1 | pass | 1561 | 2754 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m1/20261028T170205Z` |
| m2 | pass | 900 | 1869 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m2/20261028T172808Z` |
| m3 | pass | 2485 | 4338 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m3/20261028T174310Z` |
| m4 | pass | 1321 | 2636 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m4/20261028T182437Z` |
| m5 | pass | 371 | 1238 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m5/20261028T184640Z` |
| m6 | pass | 381 | 1088 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m6/20261028T185253Z` |
| m7 | pass | 1856 | 3147 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m7/20261028T185916Z` |
| i0 | pass | 293 | 4260 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/i0/20261028T193015Z` |
| r0 | pass | 553 | 1379 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r0/20261028T193510Z` |
| r1 | pass | 463 | 1269 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r1/20261028T194425Z` |
| i2 | pass | 278 | 5580 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/i2/20261028T195210Z` |
| r2 | pass | 618 | 1518 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r2/20261028T195650Z` |
| r3p | pass | 1318 | 2529 | `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r3p/20261028T200710Z` |

R0, R1 and R2 each passed one live run (mode `single`, `failed: []`; C2–C9 within each gate's checks). Every rung's RestartCount is 0 for each pod in its path (`restartCountsAllZero: true`): rc, kpimon, hw-go and every agent in all rungs, plus the TS xApp and the stub QP in r2 and r3p. T_ctl is 30 s for every rung (R0 calibration `evidence/r0/20261023T065002Z`); R3′'s W stays 1.0 s (`r3pConfig.W_s`).

## Bring-up remedies (disclosed; F″)

| Gate | What fired | Evidence |
|---|---|---|
| m1 | `rt_reader_ok` found e2mgr's RMR route reader STUCK right after the RIC install. One `ric refresh (ric)` (17:15:10–17:17:01Z) replaced e2mgr and submgr and restarted rtmgr; both readers then OK (rx_queue 0). | `evidence/m1/20261028T170205Z/watchdog.log`, `rt-readers-ric-171502.txt`, `rt-readers-refresh-ric-171510.txt` |
| every other gate | readers OK on the read-only check; no refresh; no `agents-ready-remedy.txt` anywhere | `rt-readers-*.txt` in each gate's evidence |

The refresh is a bounded, logged bring-up remedy that runs before any judged evidence. It changes no judged check, and the top rung used none.

## Recorded deviations (out of scope, not fixed; the post-M9 realism pass) (V5)

| Id | What this port does | Standard | Status in M9 |
|---|---|---|---|
| P1 | The TS xApp sends the handover control to the target cell's E2 node | 3GPP TS 38.300 §9.2.3; 3GPP TS 37.340 §10.5.1 | present |
| P2 | The agent sends 5 raw bytes (gNB id, cell id) in `e2nodeComponentRequestPart`, not an EN-DC X2 SETUP REQUEST | E2AP v03.00 §9.2.27; 3GPP TS 36.423 §9.1.2.31 | present |
| P3 | d = 0: controls apply at the next step, no whole-loop delay | decision D5 | present |
| P4 | UE ID `gNB-UEID` with the IMSI in AMF-UE-NGAP-ID, not `en-gNB-UEID` / `eNB-UEID` | E2SM common v07.00 §6.2.2.6 | present |
| P5 | Every agent registers as `gNB` with a Global gNB ID | E2AP v03.00 §9.2.6 | present |
| P6 | MAC-sourced DL volume row sent as `QosFlow.PdcpPduVolumeDL`, REAL bytes per period | E2SM-KPM v03.00 §7.9.1; 3GPP TS 28.552 §5.1.3.6.1.1 | present |
| P7 | ns-3 puts an E-UTRA PDCP header on the EN-DC bearer | 3GPP TS 37.340 §4.2.2 | present; changes none of the N4 numbers |
| P8 | RAN function 3 (RC) is not announced in E2 Setup; the agents accept RC controls anyway (Stop A ruling 4) | E2AP v03.00 §8.2.4.3 | present |
| P9 | MN-hosted PDCP SDU volume credited to the en-gNB cell (`DRB.PdcpSduVolumeDL/UL`) | 3GPP TS 28.552 §5.1.2.1.1.1 (NRCellCU) | present; R3′'s predictor reads this counter |
| P10 | The agents send every E2AP message with SCTP PPID 0, not 70: e2sim (`2209995`) sends with a plain `send()` (`e2sim/src/SCTP/e2sim_sctp.cpp:222`). e2term sends PPID 70. Wireshark falls back to port 36422 (X2AP) and shows the agent's frames as X2AP; `-d sctp.port==36422,e2ap` decodes them as E2AP. | O-RAN.WG3.TS.E2GAP-R004-v08.00 §6.1 | present: in M9's r3p `live1.pcap`–`live3.pcap`, all 1142 agent → e2term DATA chunks per run carry PPID 0 and all 9 e2term → agent chunks carry 70; e2term accepts it, and no gate judges the PPID. Found in the post-M9 review on 2026-10-29. Fix acceptance (user ruling, 2026-10-29): a gate check that every agent's agent → e2term DATA chunks in every live capture carry PPID 70, judged per agent. |
| P11 | The handover target (E2SM-RC CONTROL style 3, action 1, RAN parameter 4 "NR CGI") is 9 raw octets, `00` \| PLMN (3) \| the N5 cell key (gNB ID 4 octets big-endian, cell ID 1 octet), e.g. `00 00F110 00000002 02`, not an NR CGI of PLMN Identity + 36-bit NR Cell Identity holding a 22–32-bit gNB ID. rc builds it from the TS xApp's key; the agent accepts only this form (`ns3_e2_agent/src/rc-control.cpp:25-33`) and answers `control-message-invalid` to anything else. The 40-bit gNB ID + cell ID pair does not fit the 36-bit NCI one to one, so a fix must choose a gNB ID length. | E2SM-RC v03.00 §8.4.4.1 (RAN parameter 4 = NR CGI, E2SM common §6.2.3.7); O-RAN.WG3.TS.E2SM-R004-v07.00 §6.2.3.7 (NR CGI; NR Cell Identity BIT STRING (SIZE(36)), from 3GPP TS 38.413 §9.3.1.7; GNB-ID BIT STRING (SIZE(22..32))); 3GPP TS 38.300 v19.4.0 §8.2 (the gNB ID is contained within the NCI) | present: every M9 control (r0–r3p). Simulated results are unaffected: ns-3 receives only (gNB ID, cell ID), so the handover, traces and KPM values would be the same under a spec-format NR CGI. E2 interoperability is affected: a standard RC xApp's control would be refused, and our rc/TS xApp pair would mis-target a real E2 node. Coupled to P2, P5 and N5 (the key comes from the E2 Setup request part). Found in the post-M9 review on 2026-10-29. Fix acceptance (user ruling, 2026-10-29): a gate sends a spec-format NR CGI target built by an encoder independent of our rc and expects `applied` in the ledger and in ns-3's handover traces. |
| N5 | gNB agents send `%08X%02X` (5 bytes) as the TS xApp's cell key; key-length limit for other experiments | — | present |


Q2: the R0-config null-control run at the default −5 dB counted **5** LTE outage switches (`q2OutageSwitches: 5`, `evidence/r0/20261023T073520Z`), so substitution 1 applies.

## Descoping (user rulings, 2026-10-27)

- **S1:** R3 with real QP and the QP fork are deferred to a later goal; R3′ (harness predictor reading per-cell DL from Influx by sim time) is the top rung, with stop-at-R2 (substitution 4) pre-authorized.
- **S2:** the N4 counters and the UL flag stay as an opt-in feature; the QP-only checks (K18 dump, V5 window predicate, V6) are dropped.
- **S3:** a complex-scenario or portability smoke (scenario-one) and a scenario-agnostic harness move to the next goal.

## Substitutions (only these are allowed)

| # | Substitution | Applied in M9 | Evidence |
|---|---|---|---|
| 1 | `--outageThreshold=-1000` after the R0-config null-control run counted LTE outage switches | **applied** (`substitution1Applied: true`, `outageThresholdDb: -1000` on r0; carried by r1, r2, r3p) | `evidence/r0/20261028T193510Z/verdict.json` |
| 2 | Do-nothing default RMR handler in the TS xApp (Testbed fork) | **applied** (`substitution2Applied: true` on r2 and r3p) | `evidence/r2/20261028T195650Z`, `evidence/r3p/20261028T200710Z` |
| 3 | The TS xApp parses an A1 policy body sent as a JSON string under `payload` (Testbed fork) | **applied** on r2 and r3p; `false` on r0 and r1 (the TS xApp is not in their control path) | verdict `substitution3Applied` |
| 4 | Stop at R2 when the R3′ dry run forms no schedule | **not applied**: the R3′ dry run formed a schedule (`scripts/gates/r3p-schedule.json`) | `evidence/r3p/20261028T041902Z` |

## Interpretations made under A1

Listed for ratification at Stop B (`docs/journals/2026-10-28-m8-m9-stop-b.md` §4, labels (a)–(k) as there). The user re-issued the goal after Stop B, but no explicit ruling on these items is recorded.

- (a) F09: an absent Influx token file passes the scrub only while provably no secret exists (no kubectl, or no Influx pod).
- (b) The R3′ persistence formula sends UEs toward the more loaded cell under CBR (anti-load-balancing); prediction quality is out of scope.
- (c) "Every seq 1..N" (P6 A1 V3) reads as N consecutive seqs 0..N−1.
- (d) R3′'s W was calibrated through R2's fixed-answer block on the R3′ prepare path.
- (e) The R3′ dry run ran in two stages (A: class; B: schedule).
- (f) Route owners of 12041/12042 differ between runs; they are recorded facts, not judged.
- (g) The parent repo's stale submodule gitlinks are disclosed; `pins.conf` governs.
- (h) "25 GB" is enforced as 25 GiB (`df -BG`), which is stricter; the effective floor is the 29 GiB trip point.
- (i) `substitution3Applied` is carried by every rung verdict (r0, r1, r2, r3p), by i2 and by the M9 verdict's map; the m0–m7 and i0 verdicts do not carry it.
- (j) Known record slips: the R3′ C1 count was first written as 168 checks (it is 167) and the verdict self-test count as 19 (it is 18); both are corrected, and there are no other slips.
- (k) P10's Verify wording (`watchdog.json`, `r3-green`, ≥ 20 GB) is mapped to the A1 runner's verdict fields (phase-10 "Stop B mapping"); the signals are the same.

## Records

- R3′ C1 in M9: 167 checks, none failed (the 168th PASS line in its `gate.log` is the verdict line); the same count as the P8′ C1 and the P9 rehearsal.
- Stale submodule gitlinks in the parent repo vs `pins.conf`: disclosed, not updated during M9; `pins.conf` governs every gate. Updated after M9 (2026-10-29): the gitlinks now equal the pins and `.gitmodules` points at the forks; no verdict changes.
- tshark in `tools/tshark-kpm` (unpinned `debian:trixie-slim`): Debian 4.4.19-0+deb13u1 at pre-flight (unchanged since P9); `equalsReference: true` shows no decoder drift.
- The M9 run created the allowed M0 probe snapshot `m0-probe-q10281658`. The probes from the earlier attempts (`m0-probe-n10280921`, `m0-probe-o10281122`, `m0-probe-p10281349`) are kept. `fresh-install`, `f7-rerun-green` and `r3p-green` are untouched.
- Leaked overlays deleted under the 2026-10-28 20:14 ruling: `ubuntu24.1793186558` (33.96 GiB, `evidence/p10-disk/20261028T134728Z`) and `ubuntu24.1793195425` (38.70 GiB, `evidence/p10-disk/20261028T165516Z`).
- Codex: plan gate 2 runs, pre-ship 1 run, and the spare 1 run (used by accident on a `--help` review that was cancelled; disclosed in the PAUSE T1 journal) make 4 runs, so the cap is reached. F″ was reviewed by kongming instead (`Codex skipped: run cap reached`).

## Unresolved questions

1. The A1 interpretations above have no explicit user ratification on record. Should they be ratified, or is the post-Stop-B goal re-issue taken as acceptance?
2. Why do e2mgr's and submgr's RMR route readers stop reading after a cold boot or a fresh RIC install? The remedy works, but the trigger inside the L-release images is unknown.

# M8–M9 paused in P3 at the CPU hold (PAUSE T3), 2026-10-23 ~12:50 KST

Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md` (resume card and notes inside). Status: **paused by the user's answer**, not by a failure. Everything in P3 that does not need a timing measurement is done and green; what is left needs the T_ctl calibration and the real R0 gate, which the user's CPU hold forbids.

## 1. Why this is a pause

At 02:30 KST the user wrote: "there's another claude session using CPU intensively. If timing measurements are required, pause them. resume after that session done." P3 sets `T_ctl = max(30 s, 20 × L_max)` from a measured latency L (trigger injected to `control` read by ns-3), so the calibration is a timing measurement, and the real R0 gate runs with that value. I cannot tell from the host whether the other session is still running (load average was 0.9–4 over the day, with a second login seen at times), and a lower load is not a release. I asked the user at about 09:50 KST with three options (release the hold; run the gate at the 30 s start value first; keep the hold); the answer came at about 12:40 KST: **"Keep the hold: pause"**. Not a failure and not a plan stop: user-directed. The T3 reading is the acceptance signal V7 (a calibrated `tCtlSeconds`), which cannot be produced without breaking the user's instruction.

## 2. State at the pause

| Item | State |
|---|---|
| Harness | branch `migrate-l-release-NIST-1-8-0` at the commit that carries this journal (pushed); the dev rehearsals ran at `4919b30` and `e67641a` |
| Fork pins (`scripts/pins.conf`) | ns-3 `962fabc7`, oran-interface `63155c49`, Testbed `4c8397d0` (all on `dev/l-release-nist180`) |
| Phases | P0, P1, P2 done; P3 in progress (everything except the calibration, the real gate, the `r0-green` snapshot and the exit) |
| VM `ubuntu24.04` | running (boot time `2026-10-22 16:40:08 UTC`, a revert detector); snapshot-current `f7-rerun-green` but **modified since**: rc installed at its pin, rtmgr, rc, kpimon and hw-go pods recreated, Influx bucket re-created; **no snapshot taken**; snapshots `fresh-install`, `f7-rerun-green` |
| Host `/home` | about 58 G free (floor 20 GB); the M9 projection stays negative, raised at Stop A, the user frees it at Stop B; rootless podman is on `/mnt/data` |
| Background jobs | none |

## 3. What P3 produced (all evidence under `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/`)

- **Pacer and extractor.** The pacer sends `go` before a trigger when a control must miss its barrier, queues `ready` lines it sees while waiting, and reports slack only for complete steps. `tools/e2-evidence/wire-c1-extract.py` reads RC requests, their answers and KPM headers from a capture and joins each request to the ledger one to one; tested on the old real RC capture (30 controls) and on S1.
- **R0 tooling.** `rung-config.py` (values with provenance, epoch pinned), `replay-ts-cell-map.py` (keys `0000000202`, `0000000303`, none for the eNB), `check-c9-handover-trace.py`, `r0-checks.py` and `r0-scenario.json` (three D7 paths and the already-on-target refusal), `rc-lib.sh`, `paced-lib.sh`, gates `i0` (rc install), `q8` (labelled smoke) and `r0`.
- **Smoke q8** (`evidence/q8/`): real rc controls reach the agents; one ACK with ControlOutcome Format 1 and one `control-failed-to-execute` FAILURE on the wire, joined to the ledger. Three runs with the final reset: two green (`20261022T234952Z`, `20261023T000106Z`); `20261022T235400Z` was red only on a SIGPIPE in the readiness read (`kubectl logs | grep -q` under `pipefail`), a harness defect fixed afterwards.
- **L-release finding (T5 reading recorded).** rtmgr opens one route-push connection per xApp the first time it sees the endpoint and never reconnects to a replaced pod; rc has no seed route table, so a recreated rc never gets RMR ready and its first gRPC control panics it (nil `gControlData`, `rcControl.go:149`). Confirmed by experiment E1 (restarting rtmgr alone made the stuck rc ready within 3 s). Remedy built only from L components, so reported, not paused: the per-run reset recreates rc, kpimon and hw-go, restarts rtmgr, and requires rc's own `RMR is ready after` log line. Details: `plans/reports/kongming-261023-0830-GH-1-p3-rc-rmr-never-ready-after-pod-recreate.md`.
- **R0 dev rehearsals** (`evidence/r0/20261023T000514Z`: 102/103, red only on a digest-scope harness defect; `evidence/r0/20261023T002614Z`: 103/103, `dev: true`). Q2 = 5 outage switches (substitution 1, `--outageThreshold=-1000`), C8 equal, D7 1/1/1 with 3 IMSIs and targets {2, 3}, refusal and forced-late cases, restart counts 0, replay equal, RngRun 2 differs. Costs: reset about 43 s, a live run about 170 s, 21 min for the whole gate.

## 4. What the user must decide, and the options

1. **Release the hold** (or say the other session is done). Then: i0, calibration, real gate, snapshot, exit (section 5).
2. **Or allow the real gate at the 30 s start value first.** Digests do not depend on T_ctl, so a pass at 30 s is a pass at any larger value. The gate must then be run with `--tctl 30 --tctl-provenance "user ruling <date>: gate at the contract start value, calibration pending"`; without them it is red at its first check by design. From the dev data (L 8-15 ms, recorded under load, unused) the calibrated value is expected to stay 30 s unless L_max exceeds 1.5 s, but that expectation is not a measurement.
3. **Host-only preparation while the hold stays** (done during the pause, no timing involved): `--mode calibrate` of gate `r0` (ten scripted controls through the same per-run path), `r0-checks.py tctl` (T_ctl = max(30 s, ceil(20 x L_max))), the provenance read from `rung-config.json` (a hard-coded "not calibrated" string would have made M9's `r0` step red by construction). Not yet run on the VM.

## 5. Resume steps (after the user releases the hold)

0. Compare `virsh -c qemu:///system domstate ubuntu24.04`, `snapshot-current --name` and `scripts/vm/vm-snapshot.sh list` with the resume card (running, `f7-rerun-green`, two snapshots); check the VM boot time (`ssh oran-kvm-2404 uptime -s` should still read `2026-10-22 16:40:08`) and that the rc pod is Ready with 0 restarts. A different boot time means a reboot or revert: run gate `i0` first (it installs rc if absent and ends with an rtmgr restart and rc RMR ready; it has never run yet). After a revert to `f7-rerun-green`, `~/m4-build` and the agent image rebuild inside the gates (up to 5400 s and 3600 s); a revert to `fresh-install` is M0-M7 again plus about 40 GB of overlay and would cross the 20 GB floor (T2): print PAUSE T3 and ask. Do not take a safety-net snapshot.
1. Check `uptime`/top and record the host load.
2. Calibration: `scripts/vm/vm-exec.sh gate-r0-rc-scripted.sh --timeout 10800 -- --mode calibrate` with `EVIDENCE_HOST_ROOT` set to the plan's `evidence/`. L is the pacer's wall time at the `controlRx` line minus the time just before it starts the trigger (an upper bound on trigger-to-read). Only complete trigger steps count; nothing recorded under the hold (q8, the rehearsals, S1), no slack, no barrier wait, no log time feeds T_ctl. Then `python3 scripts/gates/rung-config.py set deadlines.T_ctl_s <v> "evidence/r0/<ts> calibration, host load <x>"`, **commit and push `rung-config.json` before the gate** (the VM clones the pushed SHA).
3. Real gate: `scripts/vm/vm-exec.sh gate-r0-rc-scripted.sh --timeout 10800` (the provenance is read from `rung-config.json`; it must name `evidence/r0/` or a user ruling). A red C1 is re-run only after its root cause is recorded and a change committed, then as a full fresh set.
4. Free-space check (`df` at least 20 GB plus measured growth), then `scripts/vm/vm-snapshot.sh create r0-green --need-gb 11`.
5. P3 exit checklist (plan.md) and kongming go/no-go on P4. Record the date gate `i0` first ran.

## 6. Carry-forward (for Stop A and later phases)

- Stop A items: the rtmgr restart in the per-run reset and kpimon/hw-go recreated per run; what the recorded -1 owner means (it changes within a run; both views recorded); the reset cost in the M9 budget (about 43 s per run); the T5 reading; K5 closed by an integration case, not an ns-3 unit test; whether "late" covers a control that misses its barrier mid-run; RAN function 3 not announced; ns-3 trace text files gitignored with sha256 manifests; the T8 reading of the refused probe; the CPU-hold decision; calibration is a mode of gate `r0`, not a separate gate (phase-03's file list was folded into `gate-r0` and `rc-lib.sh`).
- P5 and P8 will meet the same rtmgr defect when the TS xApp or QP pods are replaced (check `RMR_SEED_RT`, restart rtmgr, check KPM continuity). Every snapshot create or revert reboots the VM, so P4's first R1 gate needs gate `i0` or a reset before its `rc_at_pin` precheck (unverified after a cold boot: rtmgr may start before rc listens).
- M3's `m3_patched_kpimon_log_zero_wmore` reads kpimon's log with plain `kubectl logs` and can falsely pass after a log rotation; fix with the pod-log reader and re-run M3 before Stop B.
- Record kube-controller-manager and kube-scheduler restart counts per run (19 and 20, unchanged since about 23:01 UTC on 2026-10-22 when both restarted during a smoke run).
- `rung-config.json` still has `substitutions.outage_threshold_minus_1000.applied: false`, `outageThreshold_dB: -5` and `schedules.r0.path: null`: set them from the gated run's evidence (Q2 = 5 switches in the rehearsals; the gate decides it itself).

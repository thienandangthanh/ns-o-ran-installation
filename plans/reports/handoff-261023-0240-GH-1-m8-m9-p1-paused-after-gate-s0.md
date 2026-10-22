# Handoff: M8–M9 `/goal`, paused in P1 after gate S0 (2026-10-23 02:40 KST)

**Why paused.** The user asked at 02:34 KST to pause at 02:40 and resume this session later. This is a user pause, not one of the plan's stops (A, B, T1–T8), so no PAUSE marker line was printed. Resume by re-issuing the same `/goal` opener (packet: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/goal-packet.md`).

## State
- **P0 done** (`e336af4`; V1–V8 pass). Kongming P0 exit: GO after four must-do items, all applied (`plans/reports/kongming-261023-0156-GH-1-p0-exit-go-no-go.md`; harness `5d3d072`, V1 rule `76e11d1`).
- **P1 in progress.** Pushed on `dev/l-release-nist180` and pinned in `scripts/pins.conf` (`715ace6`):
  - ns-3: `786527b3` (commit A: `LteEnbRrc::ApplyExternalHandover`, the D4 prechecks in K5 order, "already on target" excludes a UE on LTE fallback), `d3bc4d96` (master eNB registers the handler; `--e2LedgerPath`).
  - oran-interface `2817f7e4`: `E2ControlHub`, ledger, `controlAck`, inbound lines, IPC v1 minor 1.
  - Testbed: `9e7d85f` (agent RC path with rc's own E2SM-RC code in a hidden-symbol `librc_codec.so`, causes, Format 1 ACK, bye/EOF), `0fd195e` (N5 5-byte request part).
- **Gate S0 PASS** (`evidence/s0/20261022T171920Z/`, verdict `failed=[]`):
  - V1: ref2, commit A and the new pins each equal ref1 under the committed rule (`evidence/p1-free-run-reference/v1-rule.md`): all IPC samples and 29 ns-3 traces equal.
  - V3: one ledger line and one ack per scripted control, d = 0, C4 order.
  - V2: the agent unit test passes every cause path.
  - K23: the ACK outcome decodes as Format 1 with the independent decoder.
  - V4: gNB request parts are `0000000202` and `0000000303`; the eNB keeps `reqpart`.
  - V6: no stray processes.
- **Not done in P1:**
  - V5: gates M5, M6 and M7 at the new pins.
  - The phase-exit checklist (status row, disk and M9 projection, notes, kongming go/no-go on P2).

## Next steps on resume
1. Check the VM against the resume card: `virsh … domstate`, `snapshot-current` (`f7-rerun-green`), `scripts/vm/vm-snapshot.sh list`.
2. Run P1 V5 with `export EVIDENCE_HOST_ROOT=$PWD/plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence`: `scripts/vm/vm-exec.sh gate-m5-agent-setup.sh --timeout 5400`, then `gate-m6-kpm.sh` (3600), then `gate-m7-multignb.sh` (6000). `~/m4-build` on the VM is already at the P1 pins. The agent image is rebuilt automatically at the new Testbed tag.
3. P1 phase exit: mark P1 done in `plan.md`, record `df` and the M9 projection, then get kongming's (`model: opus`) go/no-go on P2.
4. P2: drafts already exist and were tested locally in a host container (Ubuntu 24.04 toolchain); they are not gate evidence.
   - Fork branches `wip/p2-pacing`: lock-step barrier and pacer link in oran-interface; `--e2Pacing`, `--simStartEpochMs`, `--e2StartTimeout`, `--e2GateTimeout` in scenario-zero; agent `step` lines and `E2_TEST_WITHHOLD_STEP`.
   - Harness (committed with this handoff, not yet used by any gate): `scripts/gates/pacer.py`, `check-ledger.py`, `digest-run.py`, and the null sink's `--lockstep` and `--withhold-step`.
   - Local results: null-control lock-step equals free-run (IPC samples and 29 traces); Fallback-1 ledger passes `check-ledger.py`; ledger replay is byte-equal (`digest-run.py` all equal); forced-late is answered `late` through the stop handshake.
   - Still to write for P2: `gate-s1-pacer-lockstep.sh` (null-control, Fallback-1 + replay, forced-late, fault run (i) with a real agent's `E2_TEST_WITHHOLD_STEP`, V6 against S0's `new` run, then M5–M7), and the agent unit-test case for a `late` refusal.

## Holds and open items
- **CPU hold (user, 02:30 KST).** Another Claude session was loading the host CPU. No timing measurement until it is done: P3's T_ctl calibration (L), the R2/R3 W calibrations, and any slack used as a gate value. Check `uptime` and `top` first.
- **Q2 preview (dev only, not evidence).** At RngRun 1 in the R0 config with −5 dB, 4 of 6 UEs fall back to LTE within 2 s and stay there under NoAuto. P3's null-control count will most likely trigger substitution 1 (`--outageThreshold=-1000`).
- **For the user at Stop A:**
  - Which T8 reading governs unplanned commands (plan vs contract; see the refused-probe note in `implementation-notes.html`).
  - Ns-3 trace text files stay gitignored, with only sha256 manifests committed.
  - The agents accept RAN function 3 without announcing it in E2 Setup (E2AP v03.00 §8.2.4.3).
- **Disk.** Host /home has 68 G free (76 G at P0). The M9 projection is still negative (−12 GB at P0) and is settled at Stop B.
- **Scratch clones.** The fork clones live in the session scratchpad (`…/scratchpad/forks/`). If that is gone, re-clone `dev/l-release-nist180` and `wip/p2-pacing` from GitHub.

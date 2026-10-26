# M8–M9 paused in P6: r0/r1 `--mode single` can never pass the aggregate restart check (PAUSE T6), 2026-10-27 ~02:45 KST

Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`. Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r0/20261026T171731Z/` (this red), `evidence/r0/20261026T165654Z/` (the first red) and `evidence/p6-pre/` (the recreation of the kept pods). Counsel (advice only, not user approval): `plans/reports/kongming-261027-0245-GH-1-p6-pause-t6-single-mode-aggregate-restart-check.md`, `kongming-261027-0235-…` (the one guided fix), `kongming-261027-0215-…` (N4 design) and `kongming-261027-0145-…` (P5 exit, GO for P6).

## 1. Where the run stands
- P5 is done: R2 C1 PASS (`evidence/r2/20261026T143406Z`), `r2-green` created 2026-10-27 01:26 KST. W = 1.0 s, A1 threshold 10, substitutions 2 and 3 recorded.
- P6, step 1 (the r0/r1 regression the user asked for before N4 code): gate r0 `--mode single` and gate r1 `--mode single` at harness `94657df` or later, no N4 code written yet.
- First red (`165654Z`): the kept TS xApp and stub pods carry restart count 1 from the `r2-green` create (the create shuts the VM down and starts it again). Fix (kongming 0235, option B, state not code): boot-guarded recreation of the two pods (`evidence/p6-pre/`, new pods `d5swj` and `km99t` at 0). It worked: the per-run restart check is green and all eight rows of the after-snapshot are 0.
- Second red (`171731Z`, exit 1, 43 of 44 checks pass): `r0_restart_counts_all_zero` only. This is a different cause from the first, which under the 0235 rule and the phase Failure Protocol is PAUSE T6.

## 2. The cause of the second red (verified by kongming 0245 and by me)
`gate-r0-rc-scripted.sh:357` is `cat live*-after-pods.tsv k9-after-pods.tsv 2>/dev/null | awk …` and `scripts/gates/lib.sh:14` sets `set -uo pipefail`. The k9 run (a forced-late control) exists only in `--mode c1`, so in `--mode single` the file is missing, `cat` exits 1, and pipefail turns a clean awk into a red. The fact `restartCountsAllZero` is false for the same reason. `gate-r1-rc-multi-control.sh:395` has the same construct with `f2-after-pods.tsv` (c1 only). `gate-r2-ts-stub-qp.sh:441` uses a glob and is not affected. Every earlier green r0/r1 verdict was `--mode c1` (R0 `073520Z`, R1 `084654Z`) or r0 calibrate, which exits before the check, so `165654Z` and `171731Z` are the first single runs ever. `run-to-m9.sh` runs r0 and r1 with `--mode single`, so as written the M9 chain can never pass these two checks, and P6 V4 cannot either.

It is not N4, not the pods, not the L release (so not T5) and not option B.

## 3. Proposed fix, not applied (kongming 0245 section 2)
- Add `rc_restarts_zero_all <run>...` to `scripts/gates/rc-lib.sh`: every named run's after-snapshot must exist, be non-empty and have restart count 0; an empty run list is red.
- r0 and r1 call it with the exact run list their mode makes (live1..N, plus k9 or f2 in c1). Same check names. The `restartCountsAllZero` fact line redirects the helper's output to `/dev/null`, otherwise `fact()` writes non-JSON and the gate fails without a verdict.
- `lint.sh` test: a single-mode list passes, a missing or empty snapshot, an empty run list and a restart count of 1 fail, and a static rule flags a silenced `cat` of a named evidence file into a pipe (it flags exactly r0:357 and r1:395 today).
- At least as strict in every mode: the per-row predicate is the same one that is already green; c1 now requires live1..3 and k9 or f2 each (a superset of the old requirement); single judges live1, where the old check was a constant red; an empty file now fails. Back-test on committed evidence reproduces every verdict: R0 `073520Z` 0, R1 `084654Z` 0, r0 `171731Z` [live1] 0, r0 `165654Z` [live1] 1 (the two kept pods).
- No other instance of the pattern in the harness (grep sweep over `scripts/` and `tools/`). r1 single has never run, so an unknown defect there is possible (medium confidence).

## 4. Facts from `171731Z` worth knowing
- Everything else is green: Q2 (5 LTE outage switches at −5 dB, so substitution 1 and −1000 dB), C8 (free = null, digest `22570657bd39…`, identical in R0 C1, R1 C1, R2 C1 and both single runs, the UL-off baseline for N4 V2), C9 on the windowed matcher, C2, C5, D7, the refusal checks, G4, KPM moves, slack and latencies (L 7.8–9.3 ms).
- The kept TS xApp and stub have no routes at all in the current state (0 route lines against 14 in r2 C1), probably because their appmgr registrations did not survive the `r2-green` boot (inference). They are inert in r0 and r1, closer to M9 order. r2's pre step re-registers them; do not register by hand before r0/r1.
- The 12041/12042 −1 owner was rc here (kpimon in `165654Z`); rtmgr's order is nondeterministic and it is recorded, not judged.

## 5. N4 design consult (kongming 0215), for the user before any N4 code is pushed
No N4 code exists yet. The consult found, from the sources at the pinned SHAs (ns-3 `962fabc7`, oran-interface `63155c49`):
- **There is no gNB PDCP for EN-DC UEs.** The PDCP is the LTE master node's `McEnbPdcp`; the gNB holds only RLC and forwards UL over X2. `DlE2PdcpStats.txt` has CellId 1 (the LTE cell) in all 588 rows checked. Both new counters would therefore report the MN's PDCP volume, credited to whichever gNB's UE map holds the UE (consistent with the user's decision-261022-2013 §4 "measured where the DL counter is taken", but it contradicts the phase file's Context and puts MN-hosted volume under the en-gNB cell, which 3GPP TS 28.552 calls NRCellCU). The user has not classified this: widen recorded deviation P7, or record a new one. The code is the same either way; kongming's rule is not to push or pin the counter before the user rules (T4 territory).
- SDU rule: Σ 8·(B − 2N) per gNB cell and period, header size 2 bytes (12-bit SN, always), rounded once per cell as (bits + 500)/1000.
- V3 as written cannot run (no gNB PDCP trace exists); replace with a flag-gated per-PDU audit printed to stdout (no new trace file, nothing changes with the flag off).
- V5 "≥ 2 distinct values per series" fails by construction with constant-rate DL; pre-register the K17 QP predicate (every complete 16-seq window per gNB cell: at least 10 distinct (UL, DL) rows, neither column all zero, both fields type long).
- V2 needs a strict drop option in `digest-run.py`, and the pin bump must come before the first gate that builds.
- The 3GPP TS 36.323 V19.0.0 (`DZFZCTGR`) and 3GPP TS 38.323 V19.1.0 (`MSNDDXJH`) items exist in Zotero (checked); the clause numbers kongming quoted from memory still need a read when the code lands.

## 6. Questions for the user (release, rulings)
1. **U1.** Approve editing the r0 and r1 judges as in section 3? It is the fourth change to code r0/r1 execute since their C1 (the 22:30 ruling approved only the own-pod edits). The alternative, running the regression as `--mode c1`, only postpones the edit to V4 and M9 and costs about four times the VM time.
2. **U2.** After the release, is the T6 budget fresh for the r0/r1 step (the literal reading of the 22:30 ruling, and kongming's default; practical because r1 single has never run) or already consumed?
3. **U3.** Fold the TS xApp and stub into the r0/r1 `restartCounts` fact now, or leave it for Stop B (kongming: leave it)?
4. **N4 classification.** How should the MN-hosted PDCP volume credited to the gNB cell be recorded: widen P7, or a new deviation? The plan text for P6 V3 and V5 also needs the corrections in section 5.
5. Carried over: T6 budget per Verify step or per release for P6's later steps; ratify the rule "RestartCount = 0 is judged literally; a gate reaches it by recreating pods, never by filtering; only a boot-explained restart may be cleared as a precondition"; option D (r0/r1 reset the TS xApp and stub per run); and the history of commit `f2138f0` (see the implementation notes: public repository, 239 ignored files, no secrets).

## 7. State at the pause
- **VM:** running, `snapshot-current` = `r2-green`, boot 2026-10-26 16:26:48 UTC (no boot since). Pods: rc `8wqx4`, kpimon `7n87d`, hw-go `7pn6k` (from the r0 pre-reset), TS xApp `d5swj`, stub `km99t` (recreated, restart count 0, unrouted). No agent containers, no ns-3, agent or capture process (checked after the gate).
- **Snapshots:** fresh-install, f7-rerun-green, r0-green, r2-green. Host `/home`: 45 G free, `r2-green` overlay 1.56 GB. Floor 20 GB. M9 projection unchanged (about −23 to −25 GB, re-measure at P8/P9).
- **Forks (`scripts/pins.conf`):** ns-3 `962fabc7`, oran-interface `63155c49`, Testbed `597bdde2`. Harness: see `git log` (code unchanged since `94657df`; the red is in its judges).
- **Background jobs:** none.
- **After release (kongming 0245 order):** check the VM against the card (re-apply the boot-guarded recreation only if it booted), apply the fix, lint, push, r0 single at the new SHA, read-only pre-r1 check, r1 single, then N4 per kongming 0215 with the pin bump before any gate.

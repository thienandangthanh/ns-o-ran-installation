# M8–M9 paused in P6/P7: the push of the QP fork branch was refused (PAUSE T8), 2026-10-27 ~13:00 KST

Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`. Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/n4/20261027T031109Z/` and `evidence/n4/20261027T031836Z/` (gate n4), the V4 chain dirs listed in section 3. Counsel (advice only, not user approval): the kongming pause note named in section 6, `kongming-261027-0215-…` (N4 design).

## 1. What happened
The user re-issued the goal at about 10:00 KST after ruling on the single-mode restart-judge pause (`plans/reports/decisions-261027-0955-…`). Work then ran from the first open step of P6. While the V4 regression chain ran on the VM, I started the host-side P7 work (allowed in segment 2, K21). P7 step 1, commit 1 of the QP fork, was built and verified locally. The `git push -u origin dev/l-release-nist180` to `github.com/thienandangthanh/ric-app-qp` was then refused by the Claude Code auto-mode permission classifier ("Data Exfiltration").

`plan.md` Cross-cutting rules, Permissions, says it directly: "A classifier refusal is T8". The push is also a scripted plan step: Code delivery, "Code delivery. Branch `dev/l-release-nist180` on ns-3, oran-interface, the Testbed and the QP fork; WIP pushes allowed". So the refusal is trigger T8. Per the goal, I did not retry it, did not push by any other route, and did not continue P7.

Pushes to the parent repo and to the ns-3, oran-interface and Testbed forks in the same session were all accepted. The refusal hit only the first push to the QP fork, a repository this session had not pushed to before.

## 2. P6 progress at the pause
- **Release regression green.** r0 single PASS (`evidence/r0/20261027T005939Z`, harness `089ea86`, 44/44, `r0_restart_counts_all_zero` "restart counts 0 in: live1"). The read-only pre-r1 check held. r1 single PASS (`evidence/r1/20261027T030251Z`, harness `1e5ed51`, 47 PASS). The first r1 launch passed a short harness SHA and failed at the VM bootstrap. No gate ran in that launch; it was my invocation error.
- **N4 code, pushed and pinned** (harness `55e7f57`): ns-3 `ba954440`, oran-interface `96efc40e`, Testbed `c6d1434a`. V1 lint: 0 findings.
  - The counter is Σ 8·(B − 2N) per gNB cell from the shared MN-PDCP calculator, rounded to kbit once.
  - `--enableUlTraffic` with a flag-gated per-PDU audit.
  - Metric-map rows 34 and 35.
- **Plan text.** The phase-06 "Release amendments" block carries kongming 0215's corrections (ruling 4's precondition), committed before the push.
- **Standards.** 3GPP TS 36.323 V19.0.0 §6.2.3 and 3GPP TS 38.323 V19.1.0 §6.2.2.2 were read through Zotero on 2026-10-27. Both give a 2-octet header for a 12-bit-SN DRB data PDU, so recorded deviation P7 changes none of the N4 numbers.
- **Gate n4, constant UL** (`031109Z`): PASS. V2 equals the K19 reference (r0 single's c8free at the pre-N4 pins) after the strict drop, with the same trace names and no audit lines. V3: A1–A5 all true, per-cell error ≤ 496 bits, period sum ≤ 0.888 kbit, 0 ties, 0 overlaps. Every IMSI's PDCP events are on node 5, the MN, which confirms F1 and P9. The UL flag moves no random draw.
- **V5 calibration with constant UL: red.** Rule n4-v5-r1 on the IPC samples fails for cell 3: 28 of 170 windows, where QP's `constant()` is true and some windows have an all-zero UL. As pre-registered, the fallback `steps` pattern was selected. This is not a tuning step.
- **Gate n4, steps UL** (`031836Z`): PASS, V3 green. V5 on the IPC samples: 170/170 windows. The selection and evidence are committed in `rung-config.json` `ul_rate` (`b60b51d`).
  - Diagnostic for P7: delivered UL per IMSI is 1917/433/1808/272/15/1749 PDUs against about 1980 offered. IMSI 5's UL is nearly starved in this config, while DL is 19 600 PDUs for every UE.
- **V4 chain at harness `9755007`:** see section 3.
- **Not done:** the K18 dump (gate n4 `--part dump`, written and committed, not run), V5 and V6 on the dump, the P6 phase exit and its kongming go/no-go.

## 3. V4 chain results (harness `9755007`, N4 pins)
| Gate | Evidence | Result |
|---|---|---|
| M5 | `evidence/m5/20261027T032251Z` | PASS (agent image rebuilt for the new metric map) |
| M6 | `evidence/m6/20261027T032457Z` | PASS (the map sha on the wire matches the 35-row gNB cell list) |
| M7 | `evidence/m7/20261027T032633Z` | PASS |
| r0 single | `evidence/r0/20261027T035415Z` | PASS |
| r1 single | `evidence/r1/20261027T040329Z` | PASS |
| r2 single | `evidence/r2/20261027T041111Z` | **FAIL, 1 check**: `r2_pre_ts_and_stub_pods_fresh_rtmgr_sessions`. The pods were recreated and both xApps registered (HTTP 201), and a1mediator was replaced fresh. Then "policy type 20008 after the restart: HTTP 404". The live run that followed passed all its checks (64 PASS). |

The r2 red is the first failed Verify after this release. Per kongming 1300 no fix was applied: the one-fix budget is unused and the PAUSE id stays T8. Inference, not verified: A1 policy types live in dbaas (SDL), and the M5–M7 gates that ran between r2 C1 and now may have reset that state, so the type no longer survives an a1mediator restart. This needs root-causing after the release under the phase-06 Failure Protocol, with kongming.

## 4. P7 state at the pause (local only)
- `ric-app-qp/` is a clone of the fork, excluded through `.git/info/exclude`. The branch `dev/l-release-nist180` holds commit `901f8c5`, which is `47a35ca` plus NIST's four patches applied as the installer does.
- V1 passes: the tree equals that of a scratch gerrit clone at `47a35ca` with `git apply` (both `aece41f6`).
- Token check before the push attempt: the patch's `token =` line is empty (length 0), and the deployed token (88 chars) differs by hash. No token is in the commit. The push was refused, so nothing reached the public fork.
- A background security review flagged Flux string interpolation in `src/database.py` (NIST's patch verbatim). Commit 1 must stay verbatim (V1). The P7 reader rewrite (K6/K7: typed int filters, ids validated as integers) removes the pattern. This is now a P7 requirement.

## 5. Points from kongming 1300 (advice, not approval; `plans/reports/kongming-261027-1300-GH-1-p6-pause-t8-qp-fork-push-refused.md`)
- **Pre-registration holds by commit times.** Amendments `533b404` (12:01), checkers `b153b45` (12:06), `ul_rate` plus the ns-3 pin carrying both patterns `55e7f57` (12:10:01), then the first UL-on run `031109Z` (12:11:09). The `registered` text in `rung-config.json` said 12:30; it is corrected in this commit.
- **Gate hardening before the dump** (stricter only; to do after the release):
  - D1: take the UL pattern from `rung-config.json` and check that CAL used `steps`;
  - D2: strict Influx-vs-IPC check of the dump (`tools/e2-evidence/influx-vs-trace.py`), with the G1 UE fields asserted;
  - D3: a raw annotated-CSV fixture in the V5 self-test;
  - D4: fix the stale header comment in `influx-dump.sh`;
  - D5: take the dump once.
- **Material for P7/P8: the gNB-cell DL is constant** (8371 / 4186 kbit in 97 of 100 samples, the UE count times the CBR DL).
  - Stock QP's `make_stationary` calls `adfuller` on DL, which raises on a constant series. Nothing catches it, so QP's process would exit at its first prediction request.
  - VAR also rejects a constant column, so K17's "model file per R3 cell" would fail.
  - Options for the user: **B** (default, in contract): R3's first trigger at seq ≤ 17, so the training window still holds the start-up DL rows. Fragile. **A** (needs a ruling): train on [seq 0, trigger] and keep the 16-step window for prediction. **C**: a guard with a persistence forecast; needs a waiver of K17. **D**: make the DL vary. Not recommended.
  - Kongming's default is B, with A pre-authorized as its fallback.
  - Either way the TS xApp will pull UEs into the cell with more UEs: a QP-driven handover, but load attraction, not balancing.
- **UL composition.** Cell 3 holds IMSIs {1, 2}, so its UL is in effect IMSI 1's step pattern. Cell 2 has a zero-UL stretch at seqs 92–97, which leaves its tail window at exactly 10 distinct rows, QP's threshold.
- **Flux finding.** Deferring it to the P7 reader rewrite is sound: never deploy commit 1; in commit 4 accept only strict-int ids in unquoted filters, check names against an allowlist regex, and add unit tests with injection-shaped ids.
- **Also recorded:** `ric-app-qp/` was added to `.git/info/exclude` before the refusal (local only, not a permission file).

## 6. Questions for the user (release)
1. **T8.** How should pushes to `github.com/thienandangthanh/ric-app-qp` (branch `dev/l-release-nist180`) be allowed? Without them, P7, R3 and M9 cannot proceed. Kongming lists three ways; the choice is yours, and I changed no setting:
   - (a) an auto-mode environment entry naming github.com/thienandangthanh as your own forks;
   - (b) a narrow allow rule for the push command;
   - (c) you push `901f8c5` yourself (later P7 pushes may hit T8 again).
2. **QP training under a constant DL:** B (default) with A pre-authorized as fallback, or C, or D?
3. **The r2 single red:** confirm that it gets the fresh one-fix budget after the release (standing ruling 2026-10-26 22:30).

## 7. State at the pause
- VM `ubuntu24.04` running, snapshot-current `r2-green`; no ns-3, agent or capture process after the chain (checked by every gate's no-stray check).
- Host `/home` free: 38 G (13:22 KST), above the 20 G floor; VM / 51 % used. No boot since 2026-10-26 16:26:48 UTC. Pods: rc `wbfw2`, kpimon `zqg56`, hw-go `sgz7b`, TS xApp `crdj5`, stub `g4zxt`, all at restart count 0. No ns-3, agent, pacer or capture process.
- Forks pushed: ns-3 `ba954440`, oran-interface `96efc40e`, Testbed `c6d1434a` (pins.conf). QP fork: local only.
- kongming pause note: `plans/reports/kongming-261027-1300-GH-1-p6-pause-t8-qp-fork-push-refused.md`.

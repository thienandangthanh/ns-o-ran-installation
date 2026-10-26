# kongming counsel: P5 exit, go/no-go for P6 (N4)

2026-10-27, about 01:55 KST. Phase-exit counsel. It is advice only and **not user approval**. Model: Opus 5.5 (the user's routing for kongming).

**Inputs**
- Plan files: `goal-packet.md`, `plan.md`, `phase-05`, `phase-06`, and `phase-07` and `phase-08` for V5's dependency.
- `plans/reports/kongming-261026-2250-…`.
- Evidence: `evidence/r2/20261026T143406Z` and its calibration and rehearsal runs.
- Git history f2138f0..3501c83, and the harness at 3501c83.
- Read-only VM checks (domstate, snapshot-current, boot time) and the host disk.

## TL;DR
**GO for P6. There is no scope-guard mismatch, so no T3.** Four conditions apply. None blocks, and all are cheap:
1. **Move the pin bump before the first VM gate.** The gates rebuild at the `pins.conf` SHAs, so with the bump last (step 8 as written), V2 would compare the old binary with itself and give a false green.
2. **Pre-register V5's window rule before the UL-on dump.** The rule: every complete 16-step window per gNB cell. K17's "R3 trigger windows" do not exist until P7 picks them from this same dump.
3. **Do not run gate i0.** The boot time matches the current resume card, and i0 reinstalls rc through `dms_cli uninstall`.
4. **Correct the records before the first P6 commit.** The slip note overstates the count (239 ignored files, not 675) and omits that the parent repo is **public**.

The f2138f0 blobs can stay until Stop B. T7 is not triggered; I re-checked this independently.

## Reframed problem
The question is whether P6 can start as written without breaking the locked contract. The answer depends on three things:
- whether P5 left anything the user must hear;
- whether P6's text can be executed literally;
- whether disk, the T6 budget and the history slip create a reason to pause now.

P6 delivers the ns-3 and agent half of In scope 4. Its acceptance is regression only: free-run UL off unchanged, M5–M7 green, R0–R2 single runs, and a UL-on dump that P7 consumes.

## Q1. GO, and the scope guard
**P5 compared with the contract (phase-exit item 1): no mismatch.**

| Contract item | Evidence (143406Z `verdict.json` unless noted) |
|---|---|
| In scope 6: G3 gRPC; TS xApp starts after every agent is CONNECTED, then A1; stray-ack probe, then substitution 2 | `r2_ts_xapp_at_pin_ready_in_grpc_mode`; nodeb list holds all 3 agents; threshold 10. p5/000354Z crashed, then p5/030729Z `crashed:false`, restarts 0→0 |
| In scope 7: per-run reset, RestartCount 0, route dumps, −1 owner | `resetEvidence`/`tsResetEvidence` fresh; `restartCounts` 24 × 0; `routeOwner12041/12042` start and end per run |
| R2: C1, negatives counted by ledger with late = 0, decimal IMSI, target-addressed (P1) | `c1` all true; `late` 0/0/0; `outcomes` applied 4 ×3; `d7` 4 via target gNBs 2 and 3; stub `ues` "1".."6" |
| K10 and K12 (≥ 1 positive per gNB key; one 30000 receiver) | `wireRequests.targetKeys` = `0000000202`, `0000000303`; route rows show only the stub on 30000 |

**P6 compared with the contract: no mismatch.**
- P6 delivers the ns-3 flag and counters and the agent mapping. QP mapping is P7; R3 with UL on is P8.
- This matches In scope 4 and the P6 traceability row.

**Two defects in the plan text.** Fix them during execution; they do not change the outcome.
- **D1, step order.** `agents_ns3_locate` rebuilds whenever `~/m4-build` is not at the `pins.conf` SHAs (`scripts/gates/agents-ns3-run.sh:38-51`). `build-ns3.sh` wipes and re-fetches the tree (`:57-62`).
  - If step 8 bumps the pins last, V2 and V4 run on the pre-P6 build and V2 is trivially equal.
  - Bump the pins in one harness commit right after the fork pushes.
  - V2 counts only if its `ns3-binary-provenance.txt` names the new ns-3 and oran-interface SHAs.
- **D2, V5 is circular.** K17 judges "every R3 trigger window", but P7 step 9 (K18) picks the R3 schedule from this dump.
  - Judge **every complete 16-step window per gNB cell**. That set contains every window any schedule can use, so the check is stricter, not narrower.
  - Put the rule into the gate before the dump run.
  - A failing start-up window is a failed Verify and goes to the Failure Protocol. Do not exclude it ad hoc.
  - Record in `rung-config.json` the R3-config fields the dump used: nodes, simTime, RngRun, outage threshold, epoch, and the UL rate or pattern. P7 and P8 must use the same values. Any later change means re-taking the dump and re-judging V5.

**Still required, and not covered here**
- The step 1 consult on the SDU header rule and the double-count design.
- The ledger row "PDCP header size" still says "check presence". K4 says 3GPP TS 36.323 V19.0.0 (`DZFZCTGR`) and 3GPP TS 38.323 V19.1.0 (`MSNDDXJH`) were added on 2026-10-23. Read both through zotero-mcp at step 2. A missing document is T4.

**Verified facts that lower P6 risk**
- **Metric map.** The gNB cell rows end at order 33 and measId 33, and every row carries a `kind`. Rows 34 and 35 with `kind: gnb, list: cell` therefore leave the eNB's advertisement unchanged (Testbed `schema/metric-map.v1.json` at 597bdde).
- **kpimon** (Testbed `install_patch_files/xApps/kpimon-go/control/control.go.patch`, `monitorE2Nodes`/`initializeNode`):
  - It polls every 5 s and re-reads the e2mgr RAN function on every reconnection it sees.
  - It drops any indication whose cell-value count differs from its name count (`control.go.previous:773-776`). A stale list therefore shows up as missing Influx rows, which M6's Influx-vs-trace check catches.
  - K13 is still binding: delete the kpimon pod after the new agent image exists and before M5. M6's wire-subscription check then gates the re-subscription.
- **IPC.** `minor` appears only in the hello line (oran-interface@63155c49 `model/e2-ipc-message-encoder.cc:153-164`); sample lines carry only `v` (`:201-209`). A minor bump does not affect V2's sample comparison.
- **V2 judge.** `scripts/gates/digest-run.py` cannot drop fields; it drops only `ipcDropped` (`:9`). V2 needs a new option that:
  - drops exactly the two keys;
  - requires both keys in every gNB cell sample;
  - asserts UL = 0 in every sample with UL off, and DL > 0 in at least one.

  The flag-off path must write no new trace file, or the trace digests will differ. Any per-RRC counting for V3 must sit behind the flag.

## Q2. Gate i0 and the run order
**Skip i0.**
- The VM boot time read at 16:50 UTC is 2026-10-26 16:26:48, which equals the card. The VM is running at `r2-green`.
- The rule is a revert detector (`docs/journals/2026-10-23-m8-m9-p3-pause-cpu-hold.md:36`: "a reboot or revert … it installs rc if absent").
- This reboot has a known cause (the `r2-green` create), and rc is installed at its pin inside `r2-green`.
- Every rung gate checks `rc_at_pin`, builds the decoder, fetches grpcurl and resets rc itself (`gate-r0-rc-scripted.sh:86-91`, `gate-r1-rc-multi-control.sh:85-90`).
- `rc_install` runs NIST's installer, which starts with `dms_cli uninstall` and deletes rc's Services (`rc-lib.sh:25-26, 39-56`). That is churn plus about 3 GB (`run-to-m9.sh` STEPS).
- i0's code path is unchanged since its P4 green; 611271d only added functions.
- **Rule from now on:** compare the boot time with the card's current value. If it differs, check `snapshot-current` first, and run i0 only when rc could be missing (a revert).

**Order**
| # | Step | Why here |
|---|---|---|
| 0 | Read-only resume checks; `df -h /home`; `du -B1 /home/andang/VMs/ubuntu24.04-r2-green.qcow2` | Baseline for growth |
| 1 | **Pre-N4:** `gate-r0 --mode single`, then `gate-r1 --mode single`, at the current pins | This is the r0/r1 regression the user asked for (ruling 2). Run before N4, a red cannot be confused with the N4 change. About 30 min and 1–2 GB. It adds runs and removes none. A red goes through the Failure Protocol |
| 2 | Step 1 kongming consult; Zotero reads | Required before code |
| 3 | Code; V1 lint; V2 drop option; `gate-n4`; push the forks; bump `pins.conf` | D1 |
| 4 | Build at the new pins (the first gate rebuilds, up to 5400 s); log growth | Largest disk step |
| 5 | **V2**: free run with UL off, in the c8free config, against `evidence/r2/20261026T143406Z/runs/c8free` | It needs no RIC and costs least. If the flag-off path moved, everything after it is moot. This is the last free run at the pre-P6 pins (unchanged since 0e821fb). Check its raw `ns3run` files against `ns3run-sha256.txt` first |
| 6 | V3: flag-on double-count run | Before any RIC gate |
| 7 | Delete the kpimon pod (K13); M5 → M6 → M7 | M6 is the most direct check of the new rows (single node, INTEGER exact); M7 adds the eNB and 4 gNBs |
| 8 | R0 → R1 → R2, `--mode single` (V4) | Order of the M9 chain |
| 9 | UL-on null-control dump in the pre-registered R3 config (K18); V5, V6 | D2 |
| 10 | Phase exit | — |

**One difference from M9.** The TS xApp and the stub stay deployed during r0 and r1 here; in M9, i2 runs after r1.
- This is harmless: r0 and r1 record the −1 owner without judging it, substitution 2 covers the TS xApp, and the stub has a safe handler.
- But do not treat P6's r0/r1 owner values as representative of M9.

## Q3. What to add for Stop B (no new contract deviation; T4 not triggered)
| # | Item | Class | Evidence |
|---|---|---|---|
| 1 | **Corrected slip facts.** The parent repo is **PUBLIC** (`gh repo view`). f2138f0 holds 675 files; only 239 match the ignore rules (about 150 MB of blobs: 3 live pcaps, `ns3run/*.txt`, `influx-*.csv`). 3e46506 untracked those 239 plus 5 strays: `.last-i2`, `.last-p5`, `.last-r2`, which are **not** ignored and whose 9 siblings are tracked, and 2 kongming memory files from a stray `.claude/` under `evidence/i2/20261023T233300Z`. The other 431 files are normal tracked evidence. `implementation-notes.html` currently says "675 files the .gitignore excludes" and "untracks all of them"; both are wrong | Tell the user (decision) | `git show --stat`, `git check-ignore --no-index`, `git ls-files` |
| 2 | **Substitution 2 does real work in gated runs, not only in the probe.** In every live run the stub received 12041 (`stubOtherTypes`). At the end of live2, e2term's view named the TS xApp as the −1 owner. The owner changes with every rtmgr restart. R3 and M9 depend on every −1 candidate surviving stray acks. Upstream QP's default handler frees the buffer (ric-app-qp@47a35ca `src/main.py:53-59`, static read); confirm the same in the fork at P7 | Tell the user (fact) | `routeOwner*`, `route-owners.tsv` |
| 3 | **The A1 threshold is PUT twice in every live run**, because the TS xApp does not flush stdout (`a1ThresholdAttempt` 2, `a1DeliveredAttempt` 1, ×3). It is a bounded precondition retry. The threshold's effect is proven on the ledger by negative n2 | Mention | `verdict.json`, implementation notes |
| 4 | **C9 as built.** End is bounded by the next applied line: the stricter variant, still not a weakening. The self-test covers only `c9-r2-calib`. It lacks the R1 PASS fixture (a refused sibling must not bound a window) and two FAIL cases: a duplicate Start in a window, and two applied lines at one apply time. Add them before P6's R1 run (a test strengthening). Report this together with the C9 change | Report with the C9 change | `check-c9-handover-trace.py:100-118` |
| 5 | **Provenance.** The R2 C1 verdict's `harness_sha` is 0a6864d, not 0cc532c; `git diff 0cc532c 0a6864d -- scripts tools` is empty. Fix the citations in the resume card and the notes | Records only | `verdict.json` |
| 6 | **M9 coverage.** i0 and `i2 --part all` have not run at the current harness. i0's code is unchanged since P4; i2's ts part is unchanged and its stub part was green at 00485d6. M5–M7 were last green at P2, and P6 covers them. This bears on Stop B's M9 go/no-go: consider an i0→r2 chain rehearsal in P9 if the budget allows | Stop B risk note | `git log` of the gate files |

No need to raise: W taken from L_max (≥ p99.9, conservative); platform pods' restart count of 1 after the reboot (not judged); the TS xApp's `jwrapper element [77]` warning.

## Q4. The f2138f0 blobs
**Leaving them until Stop B is acceptable. Do not pause.**
- **T7 is not triggered.** I re-scanned the f2138f0 tree (the R2 C1 dir and the stray `.claude`):
  - 0 files hold a base64 run of 80 or more characters ending in `==`.
  - `DOCKER_INFLUXDB_INIT_ADMIN_TOKEN` appears in pods JSON only as `valueFrom.secretKeyRef`.
  - The pcaps were captured with `ip proto 132`, so they hold SCTP/E2AP only.
  - The rest is simulation data, internal IPs, absolute host paths (with the username) and a kongming note. None of it is secret.
- **No stop or trigger fits.** Pausing on an id outside A, B and T1–T8 would break the goal's stop set.
- **Cost of waiting.**
  - If the user leaves history as is (the likely default), waiting costs nothing.
  - If the user wants a rewrite, the cost grows with time. Every SHA after f2138f0 changes, including the harness SHAs that the P5–P9 verdicts cite and M9's `--harness-sha`. Other clones diverge.
  - GitHub may keep unreferenced objects anyway, so a rewrite does not guarantee a purge.
- **What to do now**
  - Mention the slip in the journal of any pause before Stop B; that is the first time a human sees it.
  - At Stop B, offer three options: (a) leave it (recommended); (b) `git filter-repo` plus a force push; (c) clean history only on a future publication branch.
  - Never force-push without the user.
- **Stop it recurring.**
  - The UL-on dump's default name `influx-*.csv` is ignored. Decide in P6 step 7 where it is committed and under what name: a scrubbed fixture with a non-ignored name, a sha256, and the V6 token check. Then nobody reaches for `-f`.
  - Delete the stray `evidence/i2/20261023T233300Z/.claude/` (untracked). I copied its note into kongming memory.
  - Settle the pointer policy: either re-add the three `.last-*` files like the nine tracked ones, or ignore all twelve.

## Q5. Disk
**P6 alone is a low risk. P6 to P8 together is a real risk with a thin margin.**

**Measured**
- The `r0-green` overlay (P3 tail to P5, no ns-3 rebuild) holds 9.64 GB.
- The overlay before it holds 14.17 GB. By chain order I infer it covers P0–P3, with two rebuilds.
- The active `r2-green` overlay grew from 181 to 182 MB in the 24 min after boot, which suggests idle growth of about 0.1–0.45 GB/h.
- The disk has no `discard` (`evidence/r2/20261026T143406Z/disk-chain-after-r2-green.txt`), so deleting files in the guest frees nothing on the host.

**Estimate**
- P6: a full ns-3 rebuild, the agent image, M5–M7, 5 single rung runs, and the V2, V3 and dump runs. That is about 8–14 GB plus idle growth, leaving about 32–38 G free at P6 exit.
- P7 (QP image; i3 is estimated at 5 GB) and P8 (R3 calibration, dev and C1 runs, then `r3-green`) add about 5–10 GB.
- That leaves about 22–33 G entering P9. The `r3-green` create needs at least 20 GB plus the next growth (T2).
- Every GB of dev growth also deepens the M9 shortfall (−23 to −25 GB) one-for-one.

**Do**
- Before each VM step, require host free ≥ 20 GB plus that step's estimate (`run-to-m9.sh` STEPS: build 10, M5 3, M6 2, M7 2, rung 1).
- Log `du -B1` of the active overlay after each step.
- Measure idle growth over at least 1 h and add it to the M9 projection.
- If a pause will last more than a day, give the idle rate in the journal; the user can decide to shut the VM off.
- Skip optional runs (no pre-N4 M5–M7).

**Don't**
- Don't edit the domain XML (that is a host change).
- Don't count on cleanup inside the guest.
- Don't delete `r0-green` for space: it is not a leaf, so it frees almost nothing.

## What to avoid
- **A pin bump after the gates, or a manual dev build.** Either way the gates rebuild or locate the build at `pins.conf`, giving a void V2.
- **Narrowing V2 by hand,** for example by digesting a smaller file set, stripping text beyond the two keys, or adding new files on the flag-off path.
- **Choosing V5 windows after seeing the dump.**
- **Running gate i0 on a kept rc** just because the boot time changed.
- **Folding the step 1 SDU and double-count consult into this one.**
- **`git add -f`, a force push, or pausing on the slip without a trigger.**

## Alternatives and trade-offs
- **Follow P6 literally** (pins last, no pre-N4 runs). This is weaker: pins last cannot work (D1), and any V4 red would mix up the harness changes and N4.
- **Run i0 as the card's old wording says.** You get rc Service churn and about 3 GB of growth, with no benefit; the reboot's cause is known.
- **Also run M5–M7 before N4.** You gain more isolation, at the cost of about 1 h and 5–7 GB. R2 C1 already exercised the shared libraries green, and an M5–M7 red names its check. Skip it.

## Work checklist
1. Correct the slip note, the harness-SHA citations, the `r2-scenario.json:13` calibration `_comment`, the stray `.claude/` dir and the pointer policy. Push.
2. Run the read-only resume checks and record the disk baseline.
3. Run r0 single, then r1 single, at the current pins.
4. Hold the step 1 consult; do the Zotero reads.
5. Write the code, run V1, add the V2 drop option, add the C9 self-test cases, push the forks, then bump `pins.conf`.
6. Build, then run V2 (check provenance), then V3.
7. Delete the kpimon pod, then run M5, M6, M7.
8. Run r0, r1 and r2 single.
9. Pre-register V5, take the dump in the R3 config with UL on, then run V5 and V6.
10. Run the phase exit with the disk ledger and the M9 projection.

## Success metrics
- V1–V6 green on the first run; any red is attributable to one change.
- V2's provenance shows the new SHAs.
- Host free stays ≥ 30 G at P6 exit, with growth logged per step.
- The Stop B list includes items 1–4 above.
- No new `-f` add.

## Assumptions
- **High:** the r0/r1 regression the user asked for may run at the start of P6. The ruling says "P6 already schedules … unless the user wants it earlier."
- **High:** the c8free run of 143406Z is K19's "last free-run at the pre-P6 pins". The ns-3 and oran-interface pins are unchanged since 0e821fb.
- **Medium:** each failed Verify step gets one kongming-guided fix (the phase Failure Protocol), and the P5 C9 fix does not use up P6's budget. If the user's 22:30 ruling means one fix per release, then P6's first red is T6 directly.
- **Medium:** the idle growth rate comes from two samples taken soon after boot; re-measure it.
- **Low:** the 14.17 GB overlay maps to P0–P3; I inferred this from chain order only.

## Unresolved questions
1. Is the T6 budget per Verify step or per release? Check the journal; ask at Stop B if it is still open.
2. Where does the UL-on dump fixture live (QP fork tests or harness fixtures), and under what non-ignored name?
3. Is the R3 simTime final enough to take the dump in P6, or will P7 need to re-take it?
4. Does the user want f2138f0 rewritten? This is for Stop B.

Status: DONE_WITH_CONCERNS
Summary: GO for P6, no T3. Move the pin bump before the gates, pre-register V5's window rule, skip i0, and correct the slip facts (the repo is public; 239 ignored files, not 675) before the first P6 commit.
Concerns/Blockers: none blocking. The disk margin across P6–P8 is thin (about 22–33 G entering P9). The T6 budget reading is unresolved.

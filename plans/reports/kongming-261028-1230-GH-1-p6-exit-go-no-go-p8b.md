# kongming: P6-exit go/no-go and the P8′ start (2026-10-28 12:30 KST)

This is advice only. It is never user approval. Runtime: Claude Opus 5.5, through the caller's opus routing.

**Scope.** The review is read-only:
- No ssh or VM access.
- Harness range `47aee0b..b7128dd`, plus the working-tree edits in progress to `gate-r2-ts-stub-qp.sh`, `ts-rung-lib.sh` and `r3p-checks.py`.
- `bash scripts/gates/lint.sh` was run host-side at HEAD: exit 0, `lint: ok`, gate ids `m5 r0 s1 q7 r3p`.

## TL;DR

**(1) P6: GO, done under contract A1.**
- V1 and V2 stand.
- V3 is hardened (F04). The `031836Z` re-judge passes, and the old judge reproduces Codex's false PASSes.
- V4 is green with the fresh r2 single `030809Z` (65/65).
- F09 is committed.
- The only gaps are records (§4). There are no acceptance gaps.

**(2) F09 absent-token reading: acceptable within the contract.**
- It is not T3. T9 does not apply, because T9 is reserved for Codex findings.
- I verified that the literal reading would break M9 at m0. NIST also deletes and recreates the token file inside m3.
- The reading fails closed in every state where an Influx pod exists.
- Disclose it at Stop B. No pause.
- There is one real blind spot, the helm Influx **admin** token (§2.3). It should be fixed, but it does not block.

**(3) P8′ VM work: GO, conditional on 4 pre-stage-A items (§3.1).**
- Two of them are pre-registration defects that must be fixed **before stage A runs**, or they turn into a T3 after C1:
  - the n1 swap-eligibility check;
  - IPC completeness in `c_influx_ipc`.
- The step-1 amendment changes no acceptance signal and no user ruling: stage B, the W method and the persistence formula were each checked (§3.4).

**(4) Records:**
- The resume card has stale lines and lacks the commits since 6a1a4c1.
- The disk table has no P5 or P6 exit rows (checklist item 5).
- The phase-06 text needs errata.
- Stop B needs one "interpretations under A1" list (§4).

## 1. Is P6 done per contract A1? GO

| Exit item (phase-06 A1 block, plan checklist) | Evidence | Verdict |
|---|---|---|
| V1 lint, V2 UL-off digest | Green at `n4/20261027T031836Z`; A1 keeps both | ok |
| V3 hardened (F04) before further P6 VM work | `1bb00a9` (12:00 KST) predates r2 `030809Z` (03:08Z = 12:08 KST)<br>A0 = exact gNB set and seqs 0..N−1 once<br>Residual counted only after the final read instant<br>New fixtures: missing gNB cell, truncated tail, duplicate seq, unexpected node, UE leaving every map<br>Re-judge `v3-rejudge-hardened-f04.json`: pass, a0 true, nodes [2,3], 100 seqs, `unverifiedResidualBits` 0<br>The summary reproduces Codex: drop node 3 and truncate seq ≥ 50 both pass the old judge and fail A0 | ok |
| "every seq 1..N" vs 0..99 | The literal text is unmeetable as written: seq 100 would lie past simTime, and seq 0 would count as "extra"<br>The implementation enforces the intent strictly: exactly N = simTime/periodNs seqs, every one present, no extras | ok, needs an erratum (§4) |
| V4: m5–m7, r0/r1 single (9755007) + fresh r2 single after one guided fix (F06) | `r2/20261028T030809Z`: pass, 65 checks, 0 failed, harness 9bdad63 (gate code eb08897), `substitution3Applied` true, `a1PolicyTypeCreated` false | ok. Create path unproven until the next boot (§3.3 R2) |
| F09 before any further export | `1bb00a9`. First export through it: r2 `030809Z`, 0 redactions, 0 tokens in 16,436 archived text files | ok (§2) |
| Pins | `scripts/pins.conf` unchanged since `55e7f57` (N4 pins) | ok |
| Pushed | `@{u}...HEAD` = 0/0 at check time | ok |
| Checklist 5 (projection) and 7 (standards) | No P6-exit disk row. Standards: F04 and F09 add no spec decision | records gap only (§4) |

Changes after the V4 evidence:
- `1bb00a9` export, `b86deed` gate_id, `eb08897` ts-lib.
- They change naming and export for m5–r1, and add the a1mediator precondition, which i2 satisfies (ensure at `:46` before the restart at `:64`).
- Per kongming-1215, those V4 items stand. The later refactor `8a44734` is P8′ work and gets its own r2 regression (§3.1 C4).

## 2. The F09 absent-token reading

### 2.1 Verified token-file lifecycle in the M9 order

| Step | kubectl | Influx pod | Token file | Scrub path |
|---|---|---|---|---|
| m0 (fresh-install) | absent: every m1 `full_install.log` shows "Selecting previously unselected package kubectl", including the unattended `m1/20261021T213103Z` | no | absent | regex only, exit 0 |
| m1 (`full_install.sh`, hw-go only) | present (`~/.kube/config` copied by NIST) | no. full_install never installs Influx; only xApp installers do | absent | regex only, exit 0 |
| m2 | present | no | absent | regex only, exit 0 |
| m3 (kpimon) | present | yes. `install_xapp_kpi_monitor.sh:61-64` installs it | `revise_influxdb_values_yaml.sh:42` **deletes** it, then `install_xapp_kpi_monitor.sh:87-91` **creates** it | exact, exit 0 |
| i0 and later | present | yes | present | exact |

The literal reading ("absent = cannot be read = exit non-zero") would fail the m0 export of every M9. It would fail m1/m2 too once kubectl exists, while no secret exists anywhere. The contract clause names its own purpose: "fails closed when … the exact-secret scan cannot run". With no Influx there is no secret to scan for, and the regex scan still runs. The implementation admits absence only when absence is provable. **Verdict:** this is a faithful reading, and it is stricter than the old `except Exception: pass`. It is within the contract. T3 does not apply, because the signal can be met as intended. T9 does not apply.

Action:
- Turn the implementation-notes "question" into a "decision" that cites this report.
- List the reading in the Stop B journal so the user sees it once.

### 2.2 Hole check

| Case | Behaviour | Risk |
|---|---|---|
| kubectl present but no kubeconfig (m1 died mid-install) | `kubectl get pods` fails, exit 3, nothing copied, evidence stays on the VM (`vm-exec.sh` says where) | Liveness only. The gate is already red. Acceptable |
| The scrub's plain `kubectl` vs the gates' `kc()` (`bringup.sh:35-44`: `KUBECONFIG=$HOME/.kube/config`, else `sudo -n` admin.conf) | When `~/.kube/config` is unreadable, the scrub fails closed while the gates still work | Low. Optionally reuse `kc` semantics |
| `command -v kubectl` false negative while the RIC is up | kubectl is apt-installed in `/usr/bin`, so a non-interactive ssh PATH finds it | Low |
| Influx up, token file absent (e.g. deleted by a reinstall) | exit 3 | Correct |

### 2.3 Real blind spot (recommended, not blocking)

**The Influx admin token is not scanned for.**
- The influxdb2 pod takes `DOCKER_INFLUXDB_INIT_ADMIN_TOKEN` from a Secret (`valueFrom`, verified in `r2/030809Z/pre-a1mediator-restart-pods-before.json`).
- NIST never sets it, so it is the helm default, likely 32 alphanumerics. That is inference; check the length only, never print the value.
- The harness uses this token in-pod: `check-n6-influx-window.py:32`, `agents-ns3-run.sh:138`, `kpimon.sh:249`, `rc-lib.sh:204`.
- Two gaps follow:
  - The exact-secret set holds only the kpimon token file.
  - The `{80,}==` regex cannot match a 32-character token.
- P8′ multiplies these in-pod calls to about 70+ per dry run. The prepare tail (400 characters of stdout+stderr) lands in `pacer-summary.json`.

Fix:
- When an Influx pod exists, read the admin token into memory only (in-pod `printenv` or the Secret) and add it to `secrets`. Fail closed if that read fails. Apply the same in `r3p-checks.py secrets`.
- Cheap extras:
  - Scan files as bytes, so a non-UTF-8 file is not silently skipped. None exist today.
  - Fail closed on a non-pcap `.gz`.
  - Require `.token` itself to be a string of at least 80 characters. Today any 20-character string, such as an auth timestamp, satisfies "yields a secret": the r2 export counted "44 known secrets".

This is T7 prevention within F09, not a scope change.

## 3. P8′: go/no-go, build order, risks

### 3.1 Conditions before the first P8′ VM run (C1–C4 must; S1–S3 should)

**C1. n1 swap-eligibility (pre-registration defect).**
- `r3p-dry-run-classifier.py pick` selects n1 by "decision none and none-eligible" (20·other ≤ 21·serving).
- The pre-registered observation change says the swap makes n1 a handover. That needs 10·serving > 11·other, robustly 20·serving ≥ 23·other.
- An n1 on a cell with equal load passes the template but fails V6 at C1. Because `observationChange.cases` cannot change after a run, that would be a T3.
- With scenario-zero, n1 = IMSI 3 at a 0.5 ratio, so the swap gives 2.0 and it holds. The template still has to guarantee it.
- Fix:
  - Add swap-handover-eligibility to n1's pick.
  - Assert h1's swapped decision is none-eligible. It is implied by the margin with 2 cells: 1/1.15 → 17.4 ≤ 21.
  - Add a V9a fixture.
  - Add a sentence to `r3p-scenario.json` scheduleTemplate.
- Commit it **before stage A**. Editing pre-registration before its first run is allowed.

**C2. Full Influx = IPC must check IPC completeness.**
- `r3p-checks.py c_influx_ipc` walks only the seqs present in IPC. A truncated tail in both IPC and Influx passes. That is the exact F04 defect class.
- Fix:
  - Require `set(ipc[n]) == range(config.samples)` for every expected gNB cell.
  - Add a fixture: tail truncated in both IPC and Influx → fail.
  - Poll for the final seq (bounded, like N6) before the end-of-run query, so a kpimon flush lag does not make a false red.
- Contract: "full, duplicate-free, no missing seq".

**C3. A1 type ensure order in gate r3p.**
- `ts_policy_type_ensure` must precede the first `a1mediator_restart`. Today it sits in gate r2's pre block (`gate-r2-ts-stub-qp.sh:111`), not in `ts-rung-lib.sh`.
- Move the pre block (rc reset → rc at pin → ensure → `ts_stub_pods_reset pre`) into `ts-rung-lib.sh` so r2 and r3p cannot diverge.
- The `r3p-green` create reboots the VM, which wipes the dbaas SDL. So the P9 reference regeneration and M9's r3p both take the create path. The `eb08897` precondition makes an omission fail red, not silent, but it would still be a red precondition.

**C4. One r2 regression after the last r2-touching change.**
- `8a44734` and `cdc6b3f` are committed, and `gate-r2`/`ts-rung-lib.sh` are still being edited (probably `--reference`).
- Finish, commit and push all of it. Then make `gate-r2-ts-stub-qp.sh --mode single` the first VM action. It must be green before stage A.
- This fulfils the step-1 amendment's "one gate-r2 single after the hook lands" and covers the refactor.
- A red result gets the P8′ Failure Protocol.

**S1. The §2.3 admin-token scrub.** Before stage A (about 140 in-pod queries per dry run).

**S2. One `gate-r3p --mode single` after the schedule and W are committed, before `--mode c1`.** A gate bug found in single mode costs one run. Found in C1, it costs root cause, a commit and a full fresh set.

**S3. W provenance wording.** Write "p99.9 by nearest rank (⌈0.999·25⌉ = 25th) = L_max" next to `max(1 s, 3 × L_max)`, so the contract formula is literally visible.

### 3.2 Ordered build list (status at b7128dd)

**Host side:**
1. Pacer prepare hook (`87e9871`): done, self-test in r1/r2 pre-checks.
2. Pre-registration, predictor and N6 (`f8f49ad`): done, lint ok.
3. Dry-run classifier, prepare, schedules (`b7128dd`): done. Needs C1.
4. ts-rung-lib refactor (`8a44734`, `cdc6b3f`): done. Finish the in-progress r2 edits, then C3.
5. `r3p-checks.py` (in progress): C2. Also:
   - mirror decision == observed outcome for every trigger in every live run (ties the mirror to the real TS xApp);
   - predictor records byte-equal across the live runs.
6. `gate-r3p-ts-predictor.sh`:
   - modes `dryrun --stage a|b`, `calibrate`, `single`, `c1`, `--reference`;
   - pre block per C3;
   - own-pod restart rule;
   - route dumps and −1 owners;
   - `substitution3Applied`, `wSeconds`;
   - `secrets` over `RD/r3p` at the end of every run;
   - never `gate_init` inside prepare.
7. `gate-r2 --reference`, with judgement unchanged. It is needed for substitution 4 at P9.
8. `rung-config.json` `r3pConfig`: its own `W_s` with provenance naming `evidence/r3p/`. Leave R2's `W_s` and its provenance text ("re-set at R3 …") untouched, because `cfg_ok` (V9) depends on them.
9. Lint, push, resume card (VM work > 10 min).

**VM side:**
1. a: r2 single (C4).
2. b: stage A, classify, commit. Substitution 4 → `r3p-substitution4.json`, then go to P9. Invalid → Failure Protocol.
3. c: stage B → m1 → commit `r3p-schedule.json`.
4. d: calibrate → W → commit.
5. e: R3′ null-control (0 HandoverStart rows), unless C1's c8null already serves.
6. f: single (S2).
7. g: C1.
8. h: chain sizes and the measured M9 overlay → free-space check → `r3p-green` → exit checklist.

### 3.3 Risks (ranked)

**R1. Full Influx = IPC has never been shown at full scale.**
- M6 judges 3 picked samples (`influx-vs-trace.py:165-184`). M7 checks presence only.
- Stage A is the first real test. A systematic seq-0 or tail gap is "invalid" and goes to the Failure Protocol.
- If it cannot be fixed without redefining "full", that is T3. Never narrow the check.
- kpimon writes `time.Now()` points with no tags (`control.go.previous:955-984`). A same-nanosecond collision would overwrite a row. That is very unlikely, and N6 fails closed on it.

**R2. The A1 type create path.** It is unexercised since `eb08897` (`a1PolicyTypeCreated` false), and the next boot is `r3p-green`. See C3.

**R3. Pre-registration self-consistency (C1).** Once stage A has run, nothing in `r3p-scenario.json` may change. Review the whole file once more against the classifier before stage A.

**R4. Harness drift reaching M9 untested for r0/r1** (pacer hook, export, gate_id).
- The prepare branch is guarded by `if entry.get("prepare")` (`pacer.py:278`), and the self-test covers the paths with no prepare. So the risk is low.
- Still, at P9 run r0 and r1 single once at the frozen harness before Stop B. This is not a contract item, but an M9 failure at r0 costs hours.

**R5. The pacer loop blocks during prepare** (`subprocess.run`).
- This is fine while ns-3 is frozen.
- Keep `prepareTimeoutS` 30 above N6's deadline (20) plus the predictor and stub I/O.
- Never raise any of them blindly: that is T3 per phase-08b.

**R6. Kept-pod and rtmgr landmines.** Restart counts after a snapshot boot, the rtmgr stale wormhole after a pod replacement, and the stub `PUT` wiping its log. Reuse `ts-rung-lib` and `ts_stub_pods_reset` verbatim. The log is saved before each `PUT` (`r3p-prepare.py:43-46`).

**R7. `run-to-m9.sh` still lists i3 and r3 (`:65-66`).** This is P9 (F07/F08) work. Flag it so it is not forgotten.

### 3.4 Does the step-1 amendment touch an acceptance signal or a user ruling? No

**Stage B**
- The contract says only "the trigger schedule pre-registered from a dry run before C1". The two-stage dry run is still "the dry run", and stage A's classification is committed before stage B.
- Substitution 4 is decided by stage A alone, as before.
- "A handover exists but n1/h1/m1 cannot be formed → T3" was already in the A1 phase text approved under the Codex gate. The new margin-band → T3 rule only routes ambiguous cases to the user, so it is conservative.
- Stage B's injected h1 lands at the same barrier as the live h1 (the replay equivalence that C1 already proves).
- This is a plan edit. It is not T3.

**W method**
- Calibrating R2's fixed-answer block through the R3′ prepare path measures the same chain: injector 30003 → TS xApp → stub 30002 → rc → agent → ns-3. Prepare work is outside L by design.
- The contract's "from a calibration run" is met.
- p99.9 at n = 25 is the maximum by nearest rank, and R2 set the precedent (`W_s` provenance: `max(1 s, 3 × L_max)`, accepted at r2-green).
- The 1 s floor dominates anyway (3 × 8.2 ms ≈ 25 ms).
- This is not T3 (add S3).

**Persistence formula**
- The user chose B, "a stub that answers from Influx (persistence forecast)".
- B's own "depends most on" cell names the per-cell DL 8371 vs 4186 (`brainstorm-261027-2241` §5). Contract A1 says "from per-cell DL", and predictor quality is out of scope.
- `persistence-window-sum-v1` is a pre-registered instance of that choice. It is not a new policy.
- Its anti-load-balancing semantics (busy cells attract UEs) are honest and recorded. Disclose them at Stop B and in the docs' "run your own experiment". Do not pause.
- Switching to kongming-1220's option E is free only before stage A. After stage A it is T3.

**R3′-specific checks**
- Step-scoped negatives make "every trigger's outcome" precise.
- D7 target-only is the contract's own "R2/R3′ target-addressed (P1)".
- N6 value equality and the predictor sha256s are stricter.
- `--reference` judges the ledger and digests, which is the contract's "ledger and digests equal the committed dev reference". `recorded/` stays informational, which is fine.

## 4. Missing records

**Resume card (plan.md)**
- The `VM:` line is stale: boot 2026-10-26, pods of 2026-10-27 13:22. Replace it with the pods created by `030809Z`.
- `current phase` and `next action (A1)` still describe P6 as open.
- Add:
  - harness commits `87e9871 f8f49ad 8a44734 cdc6b3f b7128dd` plus the uncommitted r2/ts-rung-lib/r3p-checks edits;
  - this report's path;
  - the first VM action (r2 regression single);
  - "A1 type create path unproven until the next boot".

**Disk table (implementation-notes)**
- It ends at Stop A. P5-exit and P6-exit rows are missing (checklist item 5).
- P6 row: 62 G free; chain fresh-install > f7 > r0-green > r2-green plus the active overlay; projection about −4 to −6 GB against 25 GB before h. That is the A1 ruling's −3 to −5 at 63 G shifted by the −1 G since, re-measured at P8′.

**phase-06**
- Add an erratum line under the A1 block: "every seq" = seqs 0..N−1. Do not edit the binding text.
- Mark the original ledger row "PDCP header size … check presence in Zotero; missing → T4" as superseded by the 2026-10-27 rows (`DZFZCTGR`, `MSNDDXJH`).

**plan.md**
- Mark the original P6 Traceability row ("UL-on dump with both series varying") superseded by A1 S2.

**One "interpretations under A1" list for the Stop B journal and the F10 run report:**
- seq 0..N−1;
- F09 absent token (§2.1);
- W = 3 × L_max (nearest-rank p99.9);
- stage B as a plan edit;
- margin band → T3;
- persistence anti-load-balancing;
- `a1PolicyTypeCreated` false at r2 `030809Z`.

**Standards ledger:** nothing missing for P6. The P8′ rows (3GPP TS 28.552 §5.1.2.1.1.1 read 2026-10-28; "no definition exists" for the TS xApp field) are adequate.

## What to avoid
- Running stage A before C1 and C2 are committed: after that, either fix becomes a T3.
- Running the r2 regression before the r2 edits in progress are finished: it would need a second regression.
- Taking `observationChange` or `n6.deadlineS` values from stage-A data, or tuning W after a red run.
- Copying the kpimon tree, image or `control.go` into evidence (it holds the literal kpimon token).
- Treating `a1PolicyTypeCreated=false` as proof of the create path.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| The uncommitted `gate-r2`/`ts-rung-lib.sh` edits are the `--reference` mode or r3p hooks, with no change to r2 judgement | medium | If they change r2 checks, the r2 regression must be c1-equivalent, not only single |
| The helm admin token is about 32 alphanumerics and the regex cannot match it | medium | Verify the length only on the VM. If it is Influx-shaped (`{80,}==`), S1 drops to a nicety |
| kubectl is absent at fresh-install | high | A base image that ships kubectl would make m0's scrub hit the kubectl branch; with no cluster that is exit 3 |
| R2's `max(1 s, 3 × L_max)` W is accepted precedent | medium-high | A user preference for an interpolated p99.9 changes nothing numerically (the 1 s floor) |
| Scenario-zero UL-off DL in R3′ equals the c8null values (n1 = IMSI 3, h1 = IMSI 1, m1 none) | high | Stage A decides. C1 makes the template safe either way |

## Unresolved questions (for Stop B; none blocks)
- Does the user ratify the F09 absent-token reading? Default: yes.
- Does the user accept persistence's anti-load-balancing semantics for R3′? Default: P. Changing it is free only before stage A.

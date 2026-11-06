# N4 two-build determinism check: implementation report

Date: 2026-11-07 (KST). Spec: the row 148 amendment at the end of `plans/261103-0008-GH-1-post-m9-realism-m10/check-diff-ledger.md`, plus `plans/reports/kongming-261107-0705-GH-1-n4-two-build-determinism.md` (Q1, Q2, Q5). All work was host-only: no VM, no ssh, no vm-exec, no git clean, stash or checkout, no commit and no push.

## Outcome
The judge, its lint self-test and the gate's `--part determinism` are written. All host validation is green: self-test (23 fixtures), `lint.sh` (`lint: ok`), `bash -n`, and shellcheck at the lint's warning severity. A smoke test on real archived N4 runs also behaved as expected. The protected files are unchanged (`git diff --quiet` on pins.conf, build-ns3.sh, agents-ns3-run.sh, paced-lib.sh and p10-gate-chain.sh).

## Files
| File | Change |
|---|---|
| `scripts/gates/n4-run-byte-identity.py` | new, 308 lines (about 110 of them are the in-file self-test, which is the repo's convention for judges: check-pdcp-volume-totals.py has 278 lines, r0-checks.py 321) |
| `scripts/gates/gate-n4-ul-metric.sh` | +124/−3: `--part determinism`, argument handling, header doc |
| `scripts/gates/lint.sh` | +1 self-test line, next to the other N4 judges |

## Judge: `n4-run-byte-identity.py`
- **`manifest RUN`** writes `RUN/n4-run-bytes.manifest.json` and prints it.
  - The manifest holds `schema n4-run-bytes/v1`, `config`, and `items` (item name → sha256 of the normalised bytes).
  - It also holds per-item line counts, `info` (the audit header text, ulrx/dltx/end counts, emitter pins, simTime), `excluded` and `preconditions`.
  - It exits 2 when a precondition fails, and still writes the manifest as evidence.
- **Compared items (exactly the registered set):**
  - `ns3run/<name>` for every `*.txt` except stdout and stderr. The digest comes from `compare-free-run.py`'s `trace_digests`, imported through importlib, so the DlE2RlcStatsLte cols 5–6 exclusion has one source.
  - `trace/e2-ue-context-<n>.jsonl`, whole.
  - `trace/e2-ipc-trace-<n>.jsonl:samples`: the raw sample lines in file order (hello and bye excluded).
  - `ns3run/stdout.txt:body`: stdout without its first `N4AUDIT v1 hdr=` line.
  - `ns3run/stdout.txt:audit-header`: that line as its own item, so P7 can skip it.
  - `ns3-argv.txt`.
  - Emitter pins and config are recorded in the manifest but are not compared items, because the registered set does not list them. Pins are judged by `emitters_at_pins`.
- **`compare A B`** takes run dirs or manifest files.
  - It exits 0 when equal, 1 when they differ (it lists `differing`, `onlyInA`, `onlyInB`, plus `firstDifferingLines` for up to 12 items when both operands are run dirs) and 2 when a precondition fails.
  - The first-differing-line output is diagnostic only. The verdict is the digest.
- **Preconditions (exit 2):**
  - `ns3-exit`, when the file exists, is not 0.
  - `ns3-argv.txt` or its numeric `--simTime` is missing.
  - `stdout.txt` is missing.
  - Any `e2-control-ledger.jsonl` exists.
  - There is no ipc trace.
  - A trace's seqs are not exactly 0..N−1, with N = simTime / hello `periodNs`.
  - A sample lacks an integer `"ipcDropped":0`.
  - A trace line is neither hello, sample nor bye.
  - A ulon run (detected from `--enableUlTraffic=true` in its argv) does not have ulrx ≥ 1, dltx ≥ 1 and exactly one end line.
- **`--self-test` fixtures:**
  - Must fail (exit 1): changed ns3run trace byte, changed ipc sample byte, changed col 4, missing ns3run file, extra ns3run file, extra UE-context file, changed audit event, changed audit header, changed UE-context line, changed argv.
  - Must be inconclusive (exit 2): ipcDropped 1, ns-3 exit 1, ledger file, incomplete seq range, ulon without dltx, unknown line type, no argv.
  - Must pass (exit 0): identical, changed cols 5–6, changed hello (pid), hello moved after the first sample, changed bye, changed stderr.
  - The self-test also checks that a written manifest compares equal to its own run.
  - Every fixture edit asserts that its target text exists, so no fixture can silently be a no-op.

## Gate: `--part determinism`
- **Configuration.**
  - The UL pattern comes from `rung-config.py get ul_rate.value.pattern` (today `steps`) and the RngRun from `get scenario.RngRun` (1).
  - `--ul-pattern` together with this part exits 2.
  - The `PATTERN=constant` default and the v23 and dump flows are untouched; the only change there is the new `PATTERN_SET` flag.
- **Runs.** `det_run` captures paced_null_run's output to a file, so the run stays in the current shell, and moves that file to `runs/<label>/paced-run.log`.
  - It writes `ns3-argv.txt` from the `ns-3 started pid/pgid …: $NS3_BIN <args>` line, which is the real argv ns3_start received. The run dir is replaced by `<run>` and the binary path is stripped.
  - It then runs `manifest`.
  - I did this so the argument assembly in paced-lib.sh is not duplicated. That file was off-limits anyway.
- **Check order:**
  1. `n4_determinism_{uloff,ulon}_a1_free_run`, then `…_a2_free_run`.
  2. EXIT trap chained to `rm -rf $TWIN`, which covers an outer-timeout stop.
  3. `n4_determinism_twin_build_exit0`: `rm -rf`, then `timeout 1800 build-ns3.sh $HOME/n4-twin-build`, with output in `build-ns3-twin.{stdout,stderr}`.
  4. `n4_determinism_twin_tree_fresh_at_pins`: the realpaths differ from `$M4_WORKDIR`, the binary is under the twin's `build/scratch`, both git HEADs equal the pins, B's binary mtime ≥ T0 and A's < T0.
  5. `n4_determinism_twin_loads_only_its_own_libraries`:
     - It sets `NS3_BIN` (and `NS3_BIN_RE`) to B unconditionally, so b1 can never fall back to A.
     - It sets `LD_LIBRARY_PATH` to B's `build/lib` alone.
     - It writes ldd output to `ns3-binary-provenance-twin.txt`, and awk requires at least one `libns3*` with every one resolved under `$TWIN/`.
  6. `…_{uloff,ulon}_b1_free_run`.
  7. `n4_determinism_emitters_at_pins` over all 6 runs.
  8. The 4 equality checks.
  9. `n4_determinism_compare_discriminates`: uloff-a1 against ulon-a1 must exit exactly 1.
  10. Facts, then a copy of the a1 manifests to `$e/n4-run-bytes-{uloff,ulon}-a1.manifest.json`. This name already matches the `plans/.gitignore` allowlist (`*.manifest.json`).
  11. `n4_determinism_twin_tree_removed`, then `n4_no_stray_process`.
- **Facts** (all valid JSON): `rngRun`, `binarySha256A`, `binarySha256B`, `twinBinaryBitIdentical` (true, false or null), `twinBuildDurationS` (integer or null), `compare-<pair>` (the full compare JSON for each of the 5 pairs, or null) and `vmLoadEnd`. `ulPattern` is recorded by the existing fact and now holds the rung-config value.
- The part adds about 110 lines rather than about 50, because of the twin-library and freshness checks the amendment requires.

## Validation
- `python3 -I scripts/gates/n4-run-byte-identity.py --self-test` gives `ok (23 fixtures)`.
- `bash scripts/gates/lint.sh` gives `lint: ok`.
- `bash -n` passes. `shellcheck -x -e SC1090,SC1091,SC2046 -S warning` is clean. At info level there are only SC2329 (functions called through `check`) and SC2086 `return $rc`/`$bad`, the same patterns as the existing code.
- **Smoke test on real runs.** I used scratch copies of `plans/261023-0009-…/evidence/n4/2026102{7T031109Z,7T031836Z}/runs/{uloff,ulon}`. An offline harness sourced the gate's real `det_run`/`det_eq`, with paced_null_run stubbed to replay each archived run and to echo a start line of the real format. The format was checked against `checks/n4_ulon_free_run.out`.
  - The argv extraction gives the expected 9 lines, ending `--e2TraceDir=<run>/trace`.
  - Two uloff runs from two separate gate invocations with the same binary compare **equal** (exit 0). Their raw ipc traces differ (hello runIds `…-860217` and `…-853888`), so the hello exclusion was exercised on real data.
  - uloff against ulon exits 1, and ulon steps against ulon constant exits 1.
  - Limits of this smoke test: those runs predate `e2-ue-context-*.jsonl` (no UE-context items) and had no argv file (I reconstructed it from the real start line).

## Chain step 12 (I did not edit the driver)
In `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/p10-chain/p10-gate-chain.sh`, inside `steps=(`, directly after line 92 `  "s10|gate-s10-scale.sh|5400|"` and before the closing `)`, add:

```
  "n4|gate-n4-ul-metric.sh|3600|--part determinism"
```

The steps are 0-based (m2 = 0 … s10 = 11), so this line is index 12. I checked that `gate_id gate-n4-ul-metric.sh` returns `n4`. Run it as `p10-gate-chain.sh <H2> 12 12`.

## Concerns
- **Twin build timeout.** It is 1800 s, as kongming advised. M4's builds took 159–194 s plus the clone, so the margin is wide. The whole part should fit in the step's 3600 s: about 9 min of runs, about 3–5 min of build, and the hashing.
- **Hashing time.** Each manifest hashes about 30 MB of run output; offline this took under 1 s per run.
- **Precondition stricter than the amendment.** A trace line that is neither hello, sample nor bye (including an unparseable line) makes the run inconclusive (exit 2). The amendment does not name this case. The alternative would have been to drop such a line silently from the compared set. It follows digest-run.py's precedent of failing on a stray ueContext line.
- **ulon end line.** A ulon run needs exactly one `end` line, as in kongming's design. The amendment only says "no end line" is inconclusive.

Status: DONE_WITH_CONCERNS
Summary: n4-run-byte-identity.py (manifest/compare/self-test), its lint line and gate `--part determinism` are implemented with the registered check names; self-test, lint.sh, bash -n and shellcheck pass, and the smoke test on archived real N4 runs gave equal for the same-binary uloff pair and differ for the discriminating pairs.
Concerns/Blockers: not run on the VM (forbidden while the chain runs), so the twin build, the ldd check and the trap run untested until step 12. Two preconditions are slightly stricter than the amendment text (unknown ipc line type; exactly one ulon end line); the controller should confirm or I relax them.

## Codex findings fixed (2026-11-07)
The constraints were unchanged: host only, no commit, and the protected files untouched (`git diff --quiet` checked). The coordinator accepted the two stricter preconditions as they are.

### 1. HIGH: completeness was not enforced (`n4-run-byte-identity.py`)
Each run is now checked on its own before any hashing. Two runs that miss the same output exit 2 and can no longer compare equal. Name-set equality between the operands is unchanged. The new preconditions:
- **Node set.** `--nMmWaveEnbNodes=n` must be in the argv. The `e2-ipc-trace-<n>.jsonl` and `e2-ue-context-<n>.jsonl` node sets must each be exactly {1..n+1}.
  - Source: the emitter's nodeId is the cell id (`ns-3-mmwave-oran/src/lte/model/lte-enb-net-device.cc:941`, `src/mmwave/model/mmwave-enb-net-device.cc:499`). The LTE eNB is cell 1 and the gNBs are 2..n+1 (the `meid_of` comment in lib.sh, the dump's `NODES=enb:1,gnb:2,gnb:3`, M7 with n=4 having nodes 1..5).
- **No empty UE-context file.** Every emitter opens its file (`oran-interface/model/e2-ipc-emitter.cc:94`) and writes the seq-0 line with its first sample (`:123`). M7 node 1 has 5 lines.
- **A non-empty sample stream** in every IPC trace, in addition to the existing seq 0..N−1 check.
- **`REQUIRED_TRACES`:** 28 `ns3run` files must be present and non-empty. This is exactly the set common to both archived N4 runs (uloff, ulon) and M7 20261106T203538Z; M7 adds only handover files, which NoAuto does not produce.
- **`REQUIRED_ROWS`:** `ues.txt`, `enbs.txt`, `CellIdStats.txt`, `MmWaveSwitchStats.txt`, `X2Stats.txt` and `DlE2RlcStatsLte.txt` must each hold a line that is not a `%` header.
- **Emitter coverage.** The shared `emitter_at_pins` is unchanged, because it is also used by the v23 and dump parts. Node coverage is enforced as a manifest precondition, in `det_run` (every run check) and again in every `det_eq`. A comment at `all_emitters` says so.

New self-test fixtures, all exit 2:
- Both operands identically lack: an ns3run trace file, an IPC node, a UE-context node, `--nMmWaveEnbNodes`.
- Both operands identically have: an empty sample stream at one node, an empty UE-context file, a required trace holding only its header.
- One-sided: a missing IPC node.

Two one-sided fixtures changed their expected exit: a missing ns3run file and an extra UE-context node now give exit 2 (the inventory and node-set preconditions) instead of 1. Both still fail. 31 fixtures in total. I checked that each fixture fails for its own intended reason.

**Smoke test.** The archived M8 runs are now inconclusive (exit 2), and for one reason only: `e2-ue-context-<n>.jsonl node set [], want ['1','2','3']`, because those pins predate the files. They pass every other new precondition, which checks the 28-file inventory against real data. With one identical placeholder UE-context file per node added to each copy, the earlier results return: same-binary uloff equal (0), uloff against ulon 1, and steps against constant 1.

### 2. MEDIUM: twin removal before the alias check (`gate-n4-ul-metric.sh`)
- **New `twin_guard`.** It runs at the start of the part, before any `rm` and before the EXIT trap.
  - It resolves TWIN, `M4_WORKDIR` and `$HOME` with `realpath -m` and compares them as directory prefixes. A trailing `/` is normalised, so `/` stays `/`.
  - It refuses: an empty TWIN or A path; TWIN equal to A, inside A, or holding A; TWIN equal to `$HOME`, `/` or any ancestor of `$HOME`; and a TWIN path holding a quote (the trap string is single-quoted).
- **Use of the guard.** TWIN is replaced by its resolved path only if the guard passes (`TWIN_OK=1`).
  - `twin_build` and `twin_remove` refuse without calling `rm` when the guard failed, and the EXIT trap is installed only when it passed.
  - The guard's verdict is recorded first in `n4_determinism_twin_tree_fresh_at_pins`, replacing the old equality-only check, and is also logged.
- **Host test.** `/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/910ba118-28cd-4264-b831-5fa1b4929edd/scratchpad/twin-guard-test.sh` sources the real `twin_guard`/`twin_build`/`twin_remove` from the gate with `rm` and `timeout` stubbed, over 14 cases:
  - one ok case, where `rm` receives the resolved twin path exactly twice (build and removal);
  - the refused cases: equal, trailing slash, `..` alias, symlink alias, twin inside A, twin holding A, `$HOME`, an ancestor of `$HOME`, `/`, empty TWIN, empty A, A = `/`, and a quote;
  - for every refused case, `rm` is never called.
  - Its first run caught a real hole: `TWIN=/` gave `//` as its prefix and passed the ancestor test. The prefix normalisation fixed it.
  - The test is not committed: the repo has no pattern for function-level tests of a gate part.

### Validation
- Self-test `ok (31 fixtures)`, `lint.sh` `lint: ok`, `bash -n` ok, shellcheck `-S warning` clean.
- File sizes: judge 385 lines; gate +151/−3 overall.

Status: DONE
Summary: The judge now requires, per run, the full node set {1..n+1} for the IPC traces and the UE-context files, non-empty sample streams, the 28-file ns3run inventory and rows in the six named traces; fixtures where both operands lack the same output exit 2. The twin path is guarded (resolved, no overlap with build A, not /, $HOME or an ancestor of it) before any rm or trap, and a stubbed host test of 14 cases passes.
Concerns/Blockers: none new. The VM-side twin build, ldd check and trap still first run at step 12.

### 3. HIGH (Codex follow-up): a symlinked twin path was followed (`gate-n4-ul-metric.sh`)
Before this fix, the guard replaced TWIN with `realpath -m`. A symlink `$HOME/n4-twin-build -> $HOME/Documents` therefore passed, and every later `rm -rf` (build, removal check, trap) would have hit `Documents`.

**Fix:**
- **Guard: no symlink anywhere in the path.** Before any `rm` or trap, the guard now requires that the twin path is not a symlink and that `realpath -m` equals `realpath -ms` (physical path = lexical path). TWIN becomes the `realpath -ms` path. The overlap and `$HOME` checks are as before. The quote rule is gone, because the trap no longer embeds the path.
- **`twin_build` creates the twin itself.**
  - A leftover entry is removed only if it is not a symlink and its path still resolves to itself.
  - The twin is then created with `mkdir` (no `-p`, leaf only), and its device and inode number are recorded in `TWIN_ID`.
- **New `twin_rm` is the only place that removes the twin.** It removes it only while all of these still hold: `TWIN_ID` is set, the path is not a symlink and is a directory, it still resolves to itself (no component became a symlink), and its device:inode equals `TWIN_ID`.
- **Callers:** `twin_remove` (the `n4_determinism_twin_tree_removed` check) and the EXIT trap (`trap "twin_rm >/dev/null 2>&1; <previous trap>"`) both go through `twin_rm`. The trap is still installed only after the guard passed.
- **What `rm -rf` never follows:** it does not follow symlinks inside the tree. The gap between `twin_rm`'s checks and its `rm` is a race that only another process could exploit. Nothing else writes `$HOME` on the gate VM, so I left it at that.

**Host test.** Same scratch file: `/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/910ba118-28cd-4264-b831-5fa1b4929edd/scratchpad/twin-guard-test.sh`.
- It sources the real `twin_guard`, `twin_rm`, `twin_build`, `twin_remove` and the trap block from the gate. It uses the real `mkdir`, `stat` and `realpath`, with a recording `rm` stub that deletes only inside the scratch dir and must only ever see `-rf -- <twin path>`.
- 19 cases pass:
  - the 13 earlier guard cases;
  - twin is a symlink to an unrelated sibling directory: refused, no `rm`;
  - a parent component is a symlink: refused, no `rm`;
  - twin swapped for a symlink to `Documents` after creation: `twin_remove`, `twin_rm` and the real trap (subshell exit) all refuse; no `rm`; the `Documents` sentinel and the symlink itself are untouched;
  - inode swap (another real directory at the path): refused;
  - a parent component swapped to a symlink after creation: refused, and the entry in `Documents` is kept;
  - a leftover real tree is replaced by a fresh directory, and the real trap removes it on exit: exactly 2 `rm` calls, both on the twin path.
- **Non-vacuity:** I ran the test against two scratch copies of the gate with one protection removed each.
  - Without the symlink condition in the guard: 4 failures (the sibling-symlink and parent-symlink cases).
  - Without `twin_rm`'s re-check: 9 failures (all swap cases).

### Validation (after the follow-up fix)
- Guard test `ok` (19 cases).
- Self-test `ok (31 fixtures)`, `lint.sh` `lint: ok`, `bash -n` ok, shellcheck `-S warning` clean.
- Protected files unchanged.
- Gate total: +167/−3.

Status: DONE
Summary: The twin path must hold no symlink component (realpath -m = realpath -ms) before any rm or trap. Only twin_rm removes the twin, and only while it is still the directory this run created: not a symlink, no symlinked component, same device:inode. The 19-case host test passes, and it fails against both mutants.
Concerns/Blockers: none new. The check-to-rm race in twin_rm is left, as only another process could exploit it. The VM-side behaviour still first runs at step 12.

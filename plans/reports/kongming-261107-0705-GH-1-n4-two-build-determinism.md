# Kongming counsel: N4 two-build determinism for row 148 (b) at the SN-wrap commit

Date: 2026-11-07 (KST). Runtime: Claude Code, Opus 5.5 (the user's routing; not `fable`). Advisory only; no project file edited except this report.

## TL;DR
- Add an additive **row 148 amendment** (docs commit, before code) that defines (b)'s "byte for byte" as a named compared set and defines "two builds". Today the row names neither. Then add `--part determinism` to `gate-n4-ul-metric.sh`, judged by a new `scripts/gates/n4-run-byte-identity.py`.
- The part runs uloff and ulon three times each: twice on the M4 build A, and once on a fresh build B made at the same pins in a **different** workdir, with B's own `LD_LIBRARY_PATH`. It passes iff a1 = a2 = b1 on that set.
- Run it after the running 716b41b9 chain ends, as a one-step chain (step id **`n4`**). Expect about 20 min of wall time and about 3–4 GiB of /home.
- Bank the a1 manifests in `reference/n4-sn-wrap/` for P7.

## Reframed problem
- **What is being decided:** how to make row 148 (b)'s registered predicate operational before any run. The predicate is: "determinism verified once at the SN-wrap commit (two builds of the same source give byte-equal runs); if not, stop for a ruling before P7 code". The mechanism must also produce the baseline that P7's "byte identity with the SN-wrap commit" consumes.
- **Goals:**
  - A comparison that can be red only for a real simulation difference, never for fields that vary by design.
  - A twin build that stresses what P7 will perturb.
  - A baseline that survives a VM revert.
  - No change to N4's existing v23 or dump predicates.
- **Non-goals:** re-banking K19 (P11), row 161's `--part v3` (P9), any AM coverage (the Row 148 notes and the 0633 consensus), and fixing the `DlE2RlcStatsLte` defect.
- **Constraints:**
  - scope guard (additive only);
  - frozen-checkout rule;
  - disk floors;
  - questions go to brainstorm consensus. None is needed now: every choice below fits inside row 148's registered text. A ruling arises only on a red.

## Q1. What "two builds … byte-equal runs" means operationally

### Builds and runs: both "two builds" and "one build twice"
- **Build A:** the M4-gated build in `$HOME/m4-build` at the SN-wrap pins (ns-3 `4a0871d6`, oran-interface `53253fe`). It was built by the running chain's M4 (`gate-m4-ns3-build.sh:166-181`) and is located by `agents_ns3_locate` (`agents-ns3-run.sh:45-68`).
- **Build B:** `build-ns3.sh "$HOME/n4-twin-build"`.
  - It is a fresh clone (`clone_at` does `rm -rf`, `build-ns3.sh:71-73`), a fresh configure and a fresh cmake-cache, with ccache off (`:45`).
  - It uses the same pins, the same flags and a **different absolute path**.
- **Why a different path:** ns-3 stores `__FILE__` in every `LogComponent` (`src/core/model/log.h:202-203`). Changing the path therefore changes the sizes of static-init heap allocations, so B perturbs heap layout and stack contents without changing semantics. P7 will certainly cause such a perturbation, because a new `nr-pdcp-header.cc` adds its own `LogComponent` and `TypeId`. A same-path rebuild would be near-vacuous: GCC is deterministic for identical inputs. Only a different path tests what can make P7's (b) red for reasons unrelated to P7's wire bytes.
- **Runs:** uloff and ulon on A twice (a1, a2) and on B once (b1), six free runs.
  - a1 = a2 isolates run-to-run nondeterminism.
  - a1 = b1 isolates build or layout sensitivity.
  - If a red arrives, this split is the first fact the ruling needs.
- **Free path independence:** a1 and a2 run in different run directories, so their equality also shows that no compared output embeds a path. P7 also runs in its own evidence directory.

### What is compared: neither raw whole files nor the C1 digest
Raw whole files are guaranteed red:
- the `hello` line carries `runId = simStartEpochMs-pid` (`oran-interface/model/e2-ipc-emitter.cc:89`) and is written on each new connection (`:291-302`);
- the `bye` line carries delivery counters (`:237-238`);
- `DlE2RlcStatsLte.txt` cols 5–6 print an uninitialised `LteFlowId_t` (`src/lte/helper/mmwave-bearer-stats-calculator.cc:461-462`; empty constructor `src/lte/model/lte-common.cc:32-34`). They vary run to run with the same binary (counsel-261022-1045).

The C1 digest is also wrong for this purpose:
- `digest-run.py` digests neither `e2-ue-context-<n>.jsonl` nor stdout (`digest-run.py:125-147`; `compare-ns3-ipc-sample-digests.py:26` reads only `e2-ipc-trace-*`).
- It canonicalises the JSON (`:38`, `sort_keys`).
- Its `--compare` reports `ipcDroppedMaxAll` without failing on it (`digest-run.py:218-237`), so it silently drops C1's own "ipcDropped = 0" conjunct.

**Compared set of one N4 run, byte for byte (put this in the amendment):**
1. Every `ns3run/*.txt` except `stdout.txt` and `stderr.txt`, with the same name set. `DlE2RlcStatsLte.txt` is compared with its whitespace columns 5–6 removed. Reuse `compare-free-run.py`'s `trace_digests`/`COLUMN_EXCLUSIONS` (`:24,37-50`) so that the C1 exclusion has one source.
2. Every `trace/e2-ue-context-<n>.jsonl`, the whole file. These files are pure simulation output; M4 shows file = wire (`gate-m4-ns3-build.sh:142-149`).
3. Every `trace/e2-ipc-trace-<n>.jsonl`: the `sample` lines, **raw bytes, in file order**.
   - Precondition: every sample holds `"ipcDropped":0`. With 0 in both runs, raw equality needs no canonicalisation.
   - `hello` and `bye` lines are not compared.
   - Emitter SHAs are checked separately by `emitter_at_pins` (`gate-n4-ul-metric.sh:79-89`).
4. `ns3run/stdout.txt`: every line except the first `N4AUDIT v1 hdr=` line, raw. In uloff the file is empty; it was empty at the M8 pins, sha `e3b0c442…` in `evidence/n4/20261027T031836Z/ns3run-sha256.txt`.
   - The header line is kept as a separate field. It is compared at the determinism check, where the source is the same.
   - At P7 the header line is judged by row 150 instead, because row 148 (a) and row 150 require it to change: today it prints `LtePdcpHeader ().GetSerializedSize ()`, `scenario-zero.cc:727`.
   - Registering this before any run is the reading the row itself demands. It is not a narrowing.
5. The normalised ns-3 argv (the CLI, `--simStartEpochMs` and the part's extra arguments, with the run dir replaced by `<run>`). This catches config drift between the SN-wrap runs and P7.

**Preconditions** (exit 2, an inconclusive run rather than a determinism result):
- ns-3 exit 0;
- no `trace/e2-control-ledger.jsonl`;
- every node trace holds seq 0..N−1 with N = simTime/period (100);
- ulon has ≥ 1 `ulrx` line, ≥ 1 `dltx` line and one `end` line.

**Not compared:** `stderr.txt` (wall-clock connect text, trace paths: `e2-ipc-emitter.cc:104-106,244-248`), `sink/`, run-dir paths and binary bytes. Binary bytes are recorded as a fact; A and B will differ in debug info and `__FILE__` strings, and that difference proves they are distinct artifacts.

## Q2. Minimal implementation (file-level)

### Decision
A new `--part determinism` in `scripts/gates/gate-n4-ul-metric.sh`, not a new gate script and not driver logic.
- It reuses `paced_null_run` (`paced-lib.sh:20-44`), `CLI` (`:50`), `emitter_at_pins` and `no_stray`.
- The gate id stays `n4`, so evidence goes to `evidence/n4/<ts>/` and the driver's `.last-n4` cross-check works.
- It mirrors the existing `dump` branch (`:105-160`) and row 161's planned `--part v3`.

### `gate-n4-ul-metric.sh` (about +50 lines)
- **Argument handling.** Accept `determinism` in the case at `:41-42`. For this part, read the UL pattern from `rung-config.py get ul_rate.value.pattern` (today `steps`) and the RngRun from `get scenario.RngRun` (1). Refuse `--ul-pattern` with this part.
  - Reason: the gate's default `PATTERN=constant` (`:29`) is stale against the rung config selection (steps, b60b51d). P7 must use the same pattern, so the config is the single source.
- **Branch.** Place an `if [ "$PART" = determinism ]; then … gate_finish; exit $?; fi` block before the v23 code, after the shared `n4_build_tools_present` and `n4_ns3_binary_located_at_pins` checks (`:76-77`). Record `t0=$(date +%s)` and A's binary sha256.
- **Run wrapper.** `det_run <label> [extra args]` writes `runs/<label>/ns3-argv.txt` (normalised), calls `paced_null_run <label> free 0 --RngRun=$RNG <extra>`, then writes `runs/<label>/n4-run-bytes.manifest.json` through `n4-run-byte-identity.py manifest`. The `*.manifest.json` names are already in the `plans/.gitignore` allowlist.
- **Check order:**
  1. `n4_determinism_uloff_a1_free_run`, `…_ulon_a1_free_run`, `…_uloff_a2_free_run`, `…_ulon_a2_free_run`.
  2. `n4_determinism_twin_build_exit0`: `rm -rf "$TWIN"`, then `timeout --kill-after=60 1800 bash "$HARNESS_DIR/scripts/build-ns3.sh" "$TWIN"`, with stdout and stderr in `build-ns3-twin.*`. Do **not** use `agents_ns3_locate`'s implicit rebuild: it writes A's `build-ns3.stdout` file name and hides which build ran.
  3. `n4_determinism_twin_tree_fresh_at_pins`:
     - both trees' `git rev-parse` equal the pins;
     - `$TWIN` differs from `$M4_WORKDIR`;
     - B's binary mtime ≥ t0, and A's mtime < t0.
  4. `n4_determinism_twin_loads_only_its_own_libraries`:
     - set `NS3_BIN`, `NS3_BIN_RE` and `LD_LIBRARY_PATH="$TWIN/ns-3/build/lib"`, replacing the value rather than prepending to it;
     - then `ldd "$NS3_BIN"`, processed whole by awk (no `grep -q` under `pipefail`): every `libns3*` must resolve under `$TWIN`, with ≥ 1 found and 0 under `$M4_WORKDIR`;
     - write the output to `ns3-binary-provenance-twin.txt`.
     - Without this check the "twin" can load A's libraries, because `agents_ns3_locate` exported A's lib dir (`agents-ns3-run.sh:66`) and `LD_LIBRARY_PATH` precedes `DT_RUNPATH`.
  5. `n4_determinism_uloff_b1_free_run`, `…_ulon_b1_free_run`.
  6. `n4_determinism_emitters_at_pins`: the existing helper over all six runs.
  7. Equality checks: `n4_determinism_uloff_same_binary_twice_byte_equal` (a1 vs a2), `n4_determinism_uloff_two_builds_byte_equal` (a1 vs b1), and the same two for ulon.
  8. `n4_determinism_compare_discriminates`: uloff-a1 vs ulon-a1 must exit **1**; 0 or 2 fails.
  9. `n4_determinism_twin_tree_removed`: `rm -rf "$TWIN"`. Then the existing `n4_no_stray_process`.
- **Facts.** All must be valid JSON (use `json_str`, or `$(cat f || echo null)`; a raw or empty fact kills the verdict): `binarySha256A`, `binarySha256B`, `twinBinaryBitIdentical`, `twinBuildDurationS`, `ulPattern`, `rngRun`, and the comparison JSONs.

### `scripts/gates/n4-run-byte-identity.py` (new, about 150 lines)
- **`manifest RUN --config uloff|ulon --sim-time-s 10`** prints JSON with these fields:
  - `schema "n4-run-bytes/v1"`, `config`, `argv` (sha), `pins` (from hello `emitter`);
  - `traces` {name: sha} via `compare-free-run.trace_digests`;
  - `ueContext` {node: {sha, lines}};
  - `ipcSamples` {node: {sha, lines}};
  - `auditHeader` (string or null);
  - `auditEvents` {sha, lines, ulrx, dltx, end};
  - `excluded` {helloLines, byeLines, stderr, dlE2RlcStatsLteColumns [5,6]};
  - `preconditions`.
  It exits 2 on a failed precondition.
- **`compare A=RUN|MANIFEST B=… […]`:**
  - equality on traces, ueContext, ipcSamples, auditEvents, auditHeader, argv, pins and config;
  - exit 0 when equal, 1 on any difference, 2 on a precondition failure;
  - when both sides are run dirs, the first differing line per differing component, for the ruling.
  - P7 later adds a mode that skips `pins` and `auditHeader` (row 150 judges the header). Fix the manifest split now so P7 needs no format change.
- **`--self-test`**, wired into `scripts/gates/lint.sh` beside the other judges (`:46-70`).
  - Fixtures that must fail: one byte changed in a trace; a changed column 4 of `DlE2RlcStatsLte.txt`; a sample with `ipcDropped` 1 (exit 2); a missing trace file; an extra trace file; a changed `ulrx` line; a changed `e2-ue-context` line; a changed argv.
  - Fixtures that must pass: changed columns 5–6; a changed `hello` (pid) or `bye`; a `hello` at a different position; changed `stderr.txt`.

### Chain driver (after the running chain ends)
- Append step 12: `"n4|gate-n4-ul-metric.sh|3600|--part determinism"`.
- The id **must be `n4`**: `gate_id` maps `gate-n4-ul-metric.sh` to `n4` (`vm-common.sh:71`), and the driver reads `.last-$id` (`p10-gate-chain.sh`, cross-check). Any other id fails the step with 97 on a green gate.

## Q3. Ledger: an additive amendment of row 148, not a new row
- **Why an amendment:** row 148 already registers the predicate and its stop rule. A new row 163 would restate the predicate and risk two texts diverging.
- **Precedent:** "Row 160, amended before code" in the same ledger: added conjuncts, row text left unedited.
- **If the controller prefers one row per new gate route,** row 161 is the precedent for a row 163. The same text then applies with "implements row 148 (b)".
- Commit it in its own docs commit, pushed visibly before the code commit. The row 136 and row 146 notes record same-second commits as a weakness.

**Text to paste after "Row 148 notes":**

> **Row 148, amended before code (2026-11-07, kongming-261107-0705; additive; the row text above is left unedited): the mechanism of (b).**
> - **Why:** (b) says "byte for byte" and "two builds of the same source" without naming the compared bytes or the builds. Several outputs of an N4 run change from run to run by design, and P7 changes the audit header line on purpose (row 148 (a), row 150). The compared set is fixed here, before any run, so it cannot be narrowed after a result.
> - **Compared set of one N4 run (uloff or ulon), byte for byte:**
>   1. every `ns3run/*.txt` except `stdout.txt` and `stderr.txt`, same name set; `DlE2RlcStatsLte.txt` without its columns 5–6 (contract C1: an uninitialised `LteFlowId_t`, `src/lte/helper/mmwave-bearer-stats-calculator.cc:461-462`, `src/lte/model/lte-common.cc:32-34`);
>   2. every `trace/e2-ue-context-<n>.jsonl`, whole;
>   3. the `sample` lines of every `trace/e2-ipc-trace-<n>.jsonl`, raw, in file order, each with `"ipcDropped":0`; `hello` (pid run id, `e2-ipc-emitter.cc:89`) and `bye` (delivery counters, `:237`) are not compared;
>   4. `ns3run/stdout.txt` without its `N4AUDIT v1 hdr=` line, which is compared separately at this check and judged by row 150 at P7;
>   5. the ns-3 argv with the run directory normalised.
>   A run with ns-3 exit ≠ 0, a sample with `ipcDropped` ≠ 0, an incomplete seq range, a ledger file, or (ulon) no `ulrx`, `dltx` or `end` line is inconclusive: an ordinary red under the Failure Protocol, not a determinism result.
> - **Two builds:** build A is the M4 build in `$HOME/m4-build`; build B is `scripts/build-ns3.sh $HOME/n4-twin-build`, a fresh clone and configure at the same pins in a different directory, so it also perturbs the `__FILE__`-sized static allocations (`src/core/model/log.h:202-203`). B runs with `LD_LIBRARY_PATH` set to its own `build/lib` only, and fails unless `ldd` resolves every `libns3*` inside B's tree.
> - **Runs and checks** (new `--part determinism` in `gate-n4-ul-metric.sh`, judged by new `scripts/gates/n4-run-byte-identity.py`, self-test in `lint.sh`): uloff and ulon, free, null sink, UL pattern and RngRun from `rung-config.json`; A twice (a1, a2), B once (b1). `n4_determinism_<cfg>_same_binary_twice_byte_equal` (a1 = a2) and `n4_determinism_<cfg>_two_builds_byte_equal` (a1 = b1) for cfg ∈ {uloff, ulon}; `n4_determinism_twin_build_exit0`, `n4_determinism_twin_tree_fresh_at_pins`, `n4_determinism_twin_loads_only_its_own_libraries`, `n4_determinism_emitters_at_pins`, `n4_determinism_compare_discriminates` (uloff-a1 against ulon-a1 must differ). Self-test fixtures that must fail: a changed trace byte, a changed column 4 of `DlE2RlcStatsLte.txt`, `ipcDropped` 1, a missing or extra trace file, a changed audit event, a changed UE-context line, a changed argv; fixtures that must pass: changed columns 5–6, a changed or moved `hello`, a changed `bye`.
> - **Outcome (unchanged):** a red equality check stops P10 for a ruling before P7 code. A red a1 = a2 means run nondeterminism; a red a1 = b1 beside a green a1 = a2 means build or layout sensitivity.
> - **P7's (b):** P7 runs uloff and ulon once at its pins and compares each with the a1 manifests of this check, banked in `reference/n4-sn-wrap/` with `SHA256SUMS`, on the same compared set, except the pins and the audit header line (row 150). P7's gate part lands in P7's harness commit.
> - Not weaker: (b) had no mechanism; every condition is new. Contract change: No.

## Q4. Order of operations, disk and wall time

### Main worktree editing is safe now, verified
- The driver runs from the main worktree path, but its body is one `main` function followed by the single line `main "$@"; exit` (the file's last line). Bash has consumed both before it executes anything.
- `vm-exec.sh` runs from the frozen checkout (`ps`: `~/.cache/ns-o-ran-frozen-harness/716b41b9…/scripts/vm/vm-exec.sh … gate-m4-ns3-build.sh`).
- The VM runs `~/harness`, cloned from GitHub at 716b41b9.
- Commits and pushes do not move either the frozen checkout or the VM tree.

### Hard don'ts while the chain runs
- **No `vm-exec.sh` of anything.** It checks out the VM's shared `~/harness` (`vm-exec.sh:81-84`) under the running gate.
- No `git clean`, `git stash -u` or checkout over `plans/`: the chain writes `.last-*` and evidence dirs into the main worktree (`EVIDENCE_HOST_ROOT`).
- Use `git add` with explicit paths only.
- Do not edit `p10-gate-chain.sh`. It is safe by design, but the standing rule says no; add step 12 after the chain.

### Sequence
1. **Now, in parallel with the chain:**
   - commit and push the ledger amendment (docs);
   - write the code (part, comparator, lint line);
   - run `n4-run-byte-identity.py --self-test` and `bash -n`/shellcheck on the host;
   - commit and push as H2.
   - Confirm `git diff --quiet 716b41b9 H2 -- scripts/pins.conf scripts/build-ns3.sh scripts/gates/agents-ns3-run.sh scripts/gates/paced-lib.sh`, so that build A and the run helpers are what H2 assumes.
2. **Chain ends** (started about 07:03; at earlier chains M4 took about 25 min, M5 and M6 about 2 min each, M7 about 25 min, so it ends about 08:00 KST).
   - If red: the Failure Protocol first. The determinism check waits, because it needs a green M4 build at these pins.
3. **Commit and archive the chain's evidence.** Optionally remove the 716b41b9 frozen checkout (2.2 GiB, `git worktree unlock`/`chmod u+w`/`git worktree remove`), unless a diagnosis may need that SHA.
4. **Add step 12 and run the check:**
   - add step 12 to the driver;
   - `git worktree add --detach --lock ~/.cache/ns-o-ran-frozen-harness/<H2> <H2>`, then `chmod -R a-w scripts`;
   - `P10_CHAIN_LOG_DIR=$P/<h2>-n4det bash $P/p10-gate-chain.sh <H2> 12 12`.
5. **Green:**
   - copy `runs/uloff-a1/` and `runs/ulon-a1/n4-run-bytes.manifest.json` to `plans/261103-…/reference/n4-sn-wrap/{uloff,ulon}.manifest.json`, with `SHA256SUMS`;
   - commit the verdict layer and the reference; archive the raw runs to /mnt/data;
   - record the result in phase-10; remove the H2 frozen checkout.
   - The scrub cannot touch the manifests or the traces: its regex needs 80+ base64 characters then `==` (`scrub-evidence.sh`, `token_re`). Host re-verification of the copied raw runs is therefore valid.
6. **Red equality:** stop. Write a kongming note with the first differing lines and the a2/b1 split. The ruling follows the user's standing rule: brainstorm consensus; unanimous applies; a split goes to the user.

### Wall time
| Step | Estimate | Basis |
|---|---|---|
| Six runs | about 9 min | about 85–95 s each (`evidence/n4/20261027T031836Z/gate.log`) |
| Build B | about 3 min | M4's `build-ns3.sh` took 159–194 s (`m4/*/build-duration-s`) |
| Hashing and checks | < 1 min | |
| vm-exec start, scrub and copy | 3–5 min | |
| **Gate total** | **about 20 min** | |
| Code and self-test | 1–1.5 h | overlaps the chain |

SN-wrap could be DONE about 08:45–09:00 KST.

### Disk
| Item | Effect | Basis |
|---|---|---|
| /home now | 44 GiB free | `df`, 07:05 |
| Chain M4–M7 | about −2 GiB | `host-disk.tsv`: m4 48→46, m7 45→45 |
| Twin overlay growth | ≤ 2–3 GiB | likely less; the guest reuses blocks freed by M4's test tree |
| Raw evidence | about 0.3–0.6 GiB | |
| Frozen checkout swap | neutral | if 716b41b9's is removed |

- Expect about 39–41 GiB after. That is above the 22 GiB watchdog, and above the 33 GiB revert-point-2 threshold after P7's M4–M7 (about 2–3 GiB).
- The VM uses about 2–3 GiB of its about 45 GiB for the twin tree, removed at the end.
- The 34 GiB guard does not apply: there is no xApp or kpimon build.

## Q5. Legitimate nondeterminism and what controls it
| Source | Effect | Control |
|---|---|---|
| `hello` runId pid; `hello` written per connection (`e2-ipc-emitter.cc:89,291-302`) | Content and position vary | Excluded; pins checked by `emitter_at_pins` |
| `bye` counters (`:237-238`) | Wall-clock delivery | Excluded |
| `ipcDropped` in every sample | Delivery-dependent (agent down → 1) | Asserted 0; the null sink is READY before ns-3 (`paced-lib.sh:33-36`) |
| `DlE2RlcStatsLte` cols 5–6 | Uninitialised read, varies per run | Column-excluded (C1) |
| `stderr.txt` | Wall clock, paths | Excluded |
| RNG | Seed 1 by default (scenario-zero calls no `SetSeed`); run from `--RngRun` | `scenario.RngRun` = 1 (`rung-config.json`, C1). Auto stream numbers follow creation order, so any new `RandomVariableStream` at P7 shifts every later stream and (b) correctly goes red |
| Threads | ns-3 simulation is single-threaded; the IPC client thread only sends | Free mode with a null sink without `--controls` injects nothing; host load affects only `ipcDropped` |
| Pacer, agents | Wall-clock coupled in lock-step | Not used: N4's uloff and ulon are free runs (`gate-n4-ul-metric.sh:165,188`); the K18 dump is not part of (b) |
| Wall-clock epoch | Would leak into timestamps | `simStartEpochMs` fixed by the rung config; samples carry only `simTimeNs` |
| Heap layout (pointer-keyed maps `epc-x2.h:291`, `epc-s1ap.h:156`, `mmwave-beamforming-model.h:199-201,287`; uninitialised reads) | Could vary with the binary | I believe these maps are lookup-only (not verified). The different-path twin is the probe |
| Build | Compiler, cache | Fresh clone, ccache off, fixed flags (`build-ns3.sh:44-46`); recorded binary and library sha256 |

Prior evidence that run-to-run determinism holds:
- three M4 default runs gave 40 byte-identical trace files, with only cols 5–6 differing (counsel-261022-1045:23);
- every C1 repeat gate in M8, M9 and M10 has been green.

The new information is the two-build axis.

## What to avoid
- **Raw whole-file equality or the bare C1 digest as "byte for byte".** The first is guaranteed red. The second misses the UE-context files and the audit events, and does not fail on `ipcDropped`.
- **A twin that runs with A's libraries.** This happens if `LD_LIBRARY_PATH` keeps A's lib dir. Set it and verify it with `ldd`.
- **A same-path in-place rebuild as the only twin.** It is near-vacuous and blind to the perturbation P7 brings.
- **Driver step id other than `n4`.** It gives a false 97.
- **The gate's default `--ul-pattern constant`.** The rung config selected steps.
- **Banking P7's baseline as a VM path.** K19's reference was `/home/uc/evidence/r0/...`, which a revert loses.
- **Iterating on a red equality result** (tweaking exclusions, re-running until green). That narrows after a result; the row says stop. Only a precondition red (exit 2) gets the ordinary Failure Protocol.
- **Assuming a green twin guarantees P7's (b).** P7 also registers new TypeIds and LogComponents. If P7's (b) goes red, diagnose registration and RNG-stream effects before blaming the wire bytes (speculative residual).

## Alternatives and trade-offs
1. **Same-path rebuild** (`build-ns3.sh $HOME/m4-build` after a1 and a2).
   - For: zero extra disk, no library-path risk, mirrors P7's path.
   - Against: tests only compiler reproducibility.
   - Acceptable only as a diagnostic third build after a red b1.
2. **One build run twice.**
   - Against: does not meet "two builds". Reject as the predicate; keep it as a2.
3. **Extend `digest-run.py` and `reference-compare.py` with new components** instead of a new judge.
   - For: DRY banking with `SHA256SUMS`.
   - Against: both are shared judges used by many gates. `digest-run.py` is already 241 lines, and its `overall` digest is consumed elsewhere.
   - Reasonable if the controller wants fewer files; the compared set must still be the one above.
4. **Separate script, or a step inside the M4 gate.**
   - Against: a new gate id with duplicated helpers, or a longer M4 with an N4 concern in it. Reject.

## Work checklist
1. Paste the row 148 amendment. Docs commit, push.
2. Implement `--part determinism`, `n4-run-byte-identity.py` (manifest, compare, self-test) and the `lint.sh` line. Host self-test and shellcheck. Commit and push H2. Run the `git diff --quiet 716b41b9 H2 -- …` guard.
3. Wait for `chain green` in the chain output. On a red, the Failure Protocol.
4. Commit and archive the chain evidence. Decide whether to remove the 716b41b9 frozen checkout.
5. Add driver step 12 (`n4|gate-n4-ul-metric.sh|3600|--part determinism`). Create the H2 frozen checkout and run steps 12–12.
6. On green: bank the a1 manifests plus `SHA256SUMS` in `reference/n4-sn-wrap/`; commit the verdict layer and the reference; archive the raw runs; update phase-10 and the resume card; remove the H2 frozen checkout.
7. On a red equality check: stop; kongming note with the first differing lines and the a2/b1 split; ruling per the standing rule.

## Success metrics
- `gate n4 --part determinism` verdict PASS:
  - 4 equality checks green;
  - `compare_discriminates` green (exit 1 for uloff against ulon);
  - the twin library check green;
  - 6 emitters at pins;
  - the twin tree removed.
- The `lint.sh` self-test is green. Every must-fail fixture fails and every must-pass fixture passes.
- `reference/n4-sn-wrap/` verifies with `sha256sum -c`, so P7's comparison needs no VM-local file.
- `host-disk.tsv` shows /home ≥ 35 GiB at the gate's end. The gate takes ≤ 30 min of wall time.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| The running chain (M4–M7 at 716b41b9) goes green and leaves `$HOME/m4-build` at `4a0871d6`/`53253fe` | Medium | A red chain defers everything |
| H2 changes no pins, build script or run helper | High | Otherwise build A no longer represents H2 |
| uloff stdout stays empty and ulon stdout holds only audit lines at these pins | Medium; verified for the M8 pins only | A non-audit stdout line is still compared byte for byte; nothing breaks |
| P7 changes only the audit header line among the compared outputs, by design | High; row 148 (a) and row 150 | If P7's design changes another compared output, amend before P7 code |
| The pointer-keyed maps are lookup-only | Low; not verified | Only matters if b1 goes red; the twin is the empirical probe |
| The N4 run takes about 90 s at today's pins | Medium | P6 and the UB fix could change it slightly |
| Binary RUNPATH versus RPATH on the VM | Unknown | The `ldd` check settles it either way |
| The different-path twin is a controller-level choice inside row 148's text, not a user question | Medium | If the controller reads it as scope, route it to brainstorm consensus before code |

## Unresolved questions
- Amendment of row 148 or a new row 163? I recommend the amendment; row 161 is the precedent for a row. This is the controller's call.
- Should the full v23 mode's stale `--ul-pattern constant` default be fixed? It is out of scope here; it is re-banked at cp3 in P11. Flag it there.

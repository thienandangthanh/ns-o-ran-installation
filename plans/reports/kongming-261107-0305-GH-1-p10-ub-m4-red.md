# Kongming counsel: P10 UB-fix chain, step 2 (M4) red. Failure Protocol guide

Date: 2026-11-07 ~03:05 KST. Model: Opus 5.5 (kongming). Advisory only, no project file edited.
Red run: `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/m4/20261106T173845Z` (harness cf325954, ns-3 74c165f1).

## Verdict: GO-WITH-CHANGES (the proposed `cmake --build` fix is NO-GO)

Your diagnosis is right about the symptom but not the cause. The cause is one level up, in configure. With `--enable-modules=mmwave,oran-interface` and no `--disable-modules`, ns-3.38 drops its `src/test` module and never adds it back. Without that module, `utils/CMakeLists.txt` never defines `test-runner`. **There is no `test-runner` CMake target at all**, so `cmake --build cmake-cache --target test-runner` would fail with "No rule to make target 'test-runner'". That would be the second red, which means PAUSE T6.

The fix is a change to the configure flags of the `--tests` tree only. Add `test` to `--enable-modules`, add `--filter-module-examples-and-tests=mmwave`, and keep `./ns3 build -j$JOBS test-runner` as it is. I verified this with the VM's exact toolchain, as described below.

## Evidence (verified)

**Root cause in ns-3 74c165f1 (local checkout, HEAD = pin):**
- `build-support/macros-and-definitions.cmake:1907-1934`: when an enabled-modules list is given, `filter_modules` (:1915) cuts `libs_to_build` down to that list plus its dependencies. `test` is not a dependency of mmwave or oran-interface.
- `macros-and-definitions.cmake:1980-1982`: `list(APPEND libs_to_build test)` exists only inside the `if(${NS3_DISABLED_MODULES} OR …)` branch (:1936).
- `utils/CMakeLists.txt:1`: `if(${ENABLE_TESTS} AND (test IN_LIST libs_to_build))` guards `add_executable(test-runner …)` (:27) and `set_runtime_outputdirectory` (:41). That call (`macros-and-definitions.cmake:1509-1512`) is what puts the runner into `ns3-execs`. `ns3-lock.cmake:112-117` then writes that list to the lock's `ns3_runnable_programs`.
- The `ns3` wrapper (`main` :1568-1573) finds no `test-runner` in the lock. `build_step` (:1059-1063) calls `get_target_to_build("test-runner")`, its regex finds nothing, and :986 prints "Target to build does not exist".

**The VM test tree was left in place.** Section i deletes it only when `TESTS_SRC` is set, so it survived. I read it read-only at `~/m4-tests-build/ns-3`:
- `.lock-ns3_linux_build` has no `test-runner` entry. Its runnable programs are perf-io, print-introspected-doxygen, bench-packets, bench-scheduler and the scratch programs.
- `cmake-cache/Makefile` has 0 `test-runner:` rules and 0 `libtest:` rules. It does have `test-runner-examples-as-tests` and `all-test-targets`.
- `cmake-cache/utils/CMakeFiles` has no `test-runner.dir`, and there is no `cmake-cache/src/test`.
- The tree is 161 MB. The plain tree `~/m4-build` is 1.8 GB. `/home` on the VM has 47 GB free.

**Container check.** `localhost/ns3-env:noble` runs g++ 13.3.0-6ubuntu2~24.04.1 and cmake 3.28.3, the same versions as the VM. The tree was a `git archive` of the 74c165f1 checkout plus oran-interface 53253fe, built in a scratchpad (since removed):
1. **Configure.** `./ns3 configure --build-profile=default --disable-examples --enable-tests --disable-python --enable-modules=mmwave,oran-interface,test --filter-module-examples-and-tests=mmwave -G "Unix Makefiles" -- -DNS3_CCACHE=OFF -DNS3_FAST_LINKERS=OFF` returned rc 0 with 0 CMake Errors.
   - The lock now lists `…/build/utils/ns3.38.rc1-test-runner-default`.
   - The Makefile has `test-runner:`, `libtest:` and `libmmwave-test:`, and no other module test library.
   - For comparison, a host-cmake configure without the filter defines 15 module test libraries: lte, internet, core, network and the rest.
2. **Target route.** `./ns3 --dry-run build -j8 test-runner` returned rc 0 and resolves to `cmake --build . -j 8 --target test-runner`. The `scenario-zero` route is unchanged.
3. **Suite run.** I built `libcore` through CMake, then compiled the new suite, `mmwave-neighbour-selection.cc` and `utils/test-runner.cc` with the `libmmwave-test` flags. I linked the runner at the exact path `test.py` derives.
   - `./test.py -n -v -s mmwave-neighbour-list` returned rc 0 and printed `[1/1] ESC[32mPASS ESC[0m: TestSuite mmwave-neighbour-list`. All 17 cases passed.
   - The gate's own sed+grep (gate-m4-ns3-build.sh:373-375) finds the PASS line and no FAIL/CRASH/VALGR/SKIP line.
   - A prefix mutation (`mmwave-neighbour-lis`) is rejected.
4. **Syntax check.** `-fsyntax-only` with each target's own flags gave 0 errors on all 7 `libmmwave-test` sources and all 11 `libtest` sources.

**Not verified:**
- The full `test-runner` link against every module library.
- Static initialisation of the other 6 mmwave suites and the 10 `src/test` suites. `test.py` loads them when it runs `--print-test-name-list` to validate the suite name.
- Wall time on the VM.

The pre-flight probe below covers all three.

## Q1. Is the diagnosis right?
The symptom is right: the wrapper does resolve targets through the lock's runnable programs. The cause is not: `test-runner` would be in the lock if it were a target, because `set_runtime_outputdirectory` registers it. The real cause is the configure filtering described above.

On whether `test.py -n` finds a runner built by `cmake --build`: yes, if the runner existed. `test.py` reads `out_dir` from the lock (:609-618), uses `NS3_BUILDDIR` (:793), and builds the name `utils/ns3.38.rc1-test-runner-default` (:1084, :1471). It never asks how the runner was built.

## Q2. The right target route
| Route | Result |
|---|---|
| `cmake --build … --target test-runner` (your proposal) | **Red.** The target is undefined. |
| `./ns3 build` (no target) | **Red.** It builds every scratch program and util, but still no runner, so `test.py -n` fails on the missing binary. |
| `./ns3 build test` | **Red.** `test` is neither an enabled module nor a program, so the wrapper gives the same error. Even after the fix it maps to `libtest`, an object library, not the runner. |
| `--disable-modules=<unused>` to trigger the re-add branch | Works only by accident. Don't. |
| **Configure with `,test` plus `--filter-module-examples-and-tests=mmwave`, keep `./ns3 build test-runner`** | **Recommended.** Verified above. |
| Same, without the filter | Works, but compiles 14 test libraries the gate never judges (lte, internet, core, network, …). That adds time and disk, and a compile or link break in any fork-modified module's tests (lte is the likely one) would turn this check red for a reason unrelated to its predicate. |

**Cost.** With the filter, the test tree is about the plain tree (1.8 GB) plus `libmmwave-test` and `libtest`. Build time is about the plain build's 194 s plus roughly a minute (an estimate). The last M4 run took 1403 s against the 7200 s step timeout, so there is ample room.

**Isolation.** The `--tests` tree has its own workdir, clone, `cmake-cache` and `build/`. The change touches only the `TESTS` branch of `build-ns3.sh`, so the plain path the later gates use stays byte-identical in behaviour. `--tests` has no other caller (checked with grep).

Keeping `./ns3 build` also keeps `build-ns3.sh:91`'s recorded `build: ./ns3 build …` line true. A `cmake --build` route would make that line false.

## Concrete change (scripts/build-ns3.sh, TESTS branch only)
```bash
if [ "$TESTS" = 1 ]; then
    # ns-3.38 defines test-runner (utils/CMakeLists.txt) only when its src/test module is built, and an
    # --enable-modules list drops that module unless it is named; only mmwave's suites go into the runner.
    CONFIGURE_FLAGS=("${CONFIGURE_FLAGS[@]/--disable-tests/--enable-tests}")
    CONFIGURE_FLAGS=("${CONFIGURE_FLAGS[@]/--enable-modules=mmwave,oran-interface/--enable-modules=mmwave,oran-interface,test}")
    CONFIGURE_FLAGS=(--filter-module-examples-and-tests=mmwave "${CONFIGURE_FLAGS[@]}")
    TARGET=test-runner
fi
```
Notes on the snippet:
- The filter goes in front of the `--` separator, which is why the snippet prepends it.
- Do not put `&` in any `${var/pat/rep}` replacement. Bash 5.2.21 on the VM has `patsub_replacement` on, so `&` expands to the matched text.
- If the change is written as an array literal instead, add `# shellcheck disable=SC2054` above it. `lint.sh:21` shellchecks `scripts/*.sh` at warning level, and the existing disable at :38 covers only the next command.
- Update the header comment at :13-15 to match.
- If more module suites are ever wanted, the filter value must be `"mmwave;oran-interface"` (quoted). CMake does not convert commas for this variable; only the enabled and disabled lists get that conversion (:1902-1903).
- After the probe, check that the `configure:` line in `build-ns3-tests.stderr` shows `,test` and the filter.

**Commit.** Use something like `fix(harness): configure the ns-3 test tree with the test module so test-runner is a target`. Put no plan or phase IDs in the message or comments. Commit only `build-ns3.sh`.

Keep the uncommitted P6 work (`kpimon.sh`, `kpimon-guard-selftest.sh`, `lint.sh`) out of this commit. Otherwise M6 and later chain steps would run new kpimon code inside the guided-fix re-run, which confounds it. Push the commit afterwards: `vm-exec.sh:34-36` refuses SHAs that are not on origin.

No new ledger row is needed. Row 159 fixes the predicate, the pins and "a separate `build-ns3.sh --tests` tree", not the configure flags. Record the guided fix in the P10 phase record the way the earlier reds were recorded.

## Q3. The pre-flight probe and the Failure Protocol
The probe is compatible with the protocol. The protocol says "apply kongming's guidance, then re-run the Verify step", and this probe is part of the guidance. It is not a Verify re-run, so it does not consume the red budget. There is precedent: M8–M9 attempt 4 ran a validation gate before its re-run.

Pre-register the outcome rule now, so the probe cannot turn into a fix loop:
- **Probe-mechanics failure** (ssh drop, a wrong path in the probe command, the tool's own timeout): fix the mechanics and run the probe again.
- **Any failure inside the ns-3 tree** (configure, compile or link, `--print-test-name-list`, suite FAIL or CRASH, predicate miss): this guidance has failed. Print **PAUSE T6** with the probe evidence and do not attempt a second fix.
- **Green:** build rc 0, `test.py` rc 0, the gate's PASS-line grep matches and its FAIL-line grep does not. Proceed to the chain.

How to run it:
- Take the files from the **pushed fix SHA**, not the working tree. On the VM: `git -C ~/harness fetch -q origin`, then `git -C ~/harness archive <fix-sha> scripts/build-ns3.sh scripts/pins.conf | tar -x -C ~/ub-preflight/h`. `git archive` leaves the harness checkout untouched.
- Build into `~/ub-preflight/tree`, a different directory from `M4_TESTS_WORKDIR`.
- Run `cd <src> && ./test.py -n -v -s mmwave-neighbour-list` and apply the gate's lines 373-375 verbatim.
- Record `df -BG /home` before and after, and the tree's `git rev-parse HEAD`.
- Copy the outputs to `evidence/p10-chain/<fix-sha8>-ub/preflight/`, then `rm -rf ~/ub-preflight`.
- Expect about 5 minutes. Run it in the background or under nohup with polling, not in a foreground Bash call with its 10-minute cap.

## Q4. Other risks in section i
- `check()` (lib.sh:64-73) runs the function in the current shell, so `TESTS_SRC` does propagate to `ns3_suite_passes`, just as `BIN` does. `lib.sh:14` is `set -uo pipefail` without `-e`, so `[ -n "" ] && rm -rf …` is harmless.
- `ns3_suite_passes`: the coloured PASS line is verified against real `test.py` output with stdout redirected. Colour stays on when output goes to a file, `sed` strips it, and the anchors hold. `test.py` exits 2 on an unknown suite, and the PASS-line grep still guards the case where nothing runs.
- `rm -rf` only on success: if the build goes red, the tree stays behind (161 MB now). The next run's `clone_at` removes `$SRC`, so this never causes a red. Leave it; the leftover tree is what proved the cause here.
- `testpy-output/` is written inside `$TESTS_SRC` and removed with the tree. The evidence keeps `ns3-suite-*.txt` and `.plain`.
- The test tree's `ns3-configure-flags.txt` is deleted with it. The flags still survive in the `configure:` line of `build-ns3-tests.stderr`, which is enough.
- No other red trigger found in :349-381.

## Re-run checklist
1. Edit `build-ns3.sh` as above. Run `scripts/gates/lint.sh`, which shellchecks it. Commit only that file and push.
2. Run the pre-flight probe at the fix SHA. Apply the outcome rule. Keep the evidence.
3. Create the frozen checkout at the fix SHA (`~/.cache/ns-o-ran-frozen-harness/<sha>`). Host `/home` has 49 GB free and each checkout is about 2.2 GiB.
4. Run `P10_SKIP_STEPS=8 P10_CHAIN_LOG_DIR=…/evidence/p10-chain/<fix-sha8>-ub p10-gate-chain.sh <fix-sha> 2 11`, starting from step 2 with a fresh log directory.
5. M4 passes when all checks are green, including `m4_ns3_test_build_exit0` and `m4_ns3_neighbour_list_suite_passes`. `ns3-suite-mmwave-neighbour-list.txt` should show `[1/1] PASS: TestSuite mmwave-neighbour-list`, and `~/m4-tests-build` should be gone afterwards.

## What to avoid
- `cmake --build --target test-runner`, `./ns3 build` and `./ns3 build test`: all three go red, as shown in the Q2 table.
- Building the test runner in the plain tree (`~/m4-build`). Reconfiguring it would change the binary the later gates run.
- Probing with working-tree files, or editing `scripts/` while the chain runs.
- Iterating fixes after a red probe. That is PAUSE T6.

## Assumptions
- The local ns-3 checkout equals the VM clone. Confidence high: HEAD 74c165f1 matches the pin, and both locks report VERSION 3.38.rc1.
- The container toolchain matches the VM. Confidence high: both report g++ 13.3.0-6ubuntu2~24.04.1 and cmake 3.28.3.
- The full runner links, and the other suites initialise cleanly. Confidence medium; the probe decides.
- Configure flags are implementation detail, not part of the predicate, so no ledger row is needed. Confidence medium-high. The user may still want a one-line note.

## Unresolved questions
- None blocking.
- Should the oran-interface `e2-control-order` suite be added to the filter later? It is out of scope now.

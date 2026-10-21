# P4 — ns-3 decouple, IPC emitter, scripted build, timing (M4)

## Context
- `src/lte/CMakeLists.txt:373` and `src/mmwave/CMakeLists.txt:153` link `${liboran-interface}`.
- `oran-interface/CMakeLists.txt:17-29` calls `find_external_library(e2sim …)` against `/usr/local/include/e2sim` and links it at line 58. Line 22 has a broken `if(!${e2sim_FOUND})`.
- ASN.1 headers are included in `kpm-indication.{h,cc}`, `ric-control-message.h`, `asn1c-types.h` and `oran-interface.h:33` (`e2sim.hpp`).
- `E2Termination` starts an `std::thread` running the e2sim loop (`oran-interface.cc:112-137`).
- The metric-building helpers (`helper/*-indication-message-helper.cc`) and the file-logging path (`EnableE2FileLogging`, `mmwave-enb-net-device.cc:279-282, 512-1062`) are ASN.1-free.
- `e2term-ns3-build.sh` is stale (waf, old path). Reference only.

## Requirements (fresh branches `dev/l-release-nist180` on ns-3-mmwave-oran and oran-interface)
1. **Remove the e2sim/asn1c dependency from oran-interface and ns-3.**
   - Drop `find_external_library(e2sim)` and every asn1c include and type.
   - Delete or stub the ASN.1 encode paths. RC-related code that cannot compile without asn1c is removed now and re-introduced in M8 against IPC; it is out of scope here.
   - Keep the metric collection exactly as it is (no radio/scenario behaviour change).
2. **IPC emitter** (per the P3-approved schema). One client per E2 node:
   - Replaces `E2Termination` send and subscription.
   - Non-blocking: drop and count while the agent is unavailable.
   - Also writes each emitted sample to a local trace (CSV/JSONL). That trace is the "ns-3 trace" ground truth for M6.
   - Existing CLI args keep working, plus new ones for agent endpoints.
   - Unknown args still exit(1), so add args explicitly.
3. **`scripts/build-ns3.sh`.**
   - Clean clone at the pinned SHAs: ns-3, oran-interface (placed at `contrib/oran-interface`, as a copy or a symlink to the clone), then configure and build.
   - Fixed configure flags, recorded. No manual `ar`, no header copies, nothing in `/usr/local/include/e2sim`.
   - Fix GCC 13 issues as minimal source fixes, committed with one reason each.
4. **`scripts/measure-ns3-timing.sh`.** scenario-zero with 1 gNB and with the default N (4 mmWave + 1 LTE).
   - Default `indicationPeriodicity` 0.1 s and the default UE/traffic load.
   - IPC emitter active against a null sink agent, so the emit cost is included.
   - Fixed simTime (e.g. 10 s), at least 3 repeats each.
   - Wall time from a Python `time.monotonic()` wrapper.
   - Output: real seconds per simulated second (mean, min, max, stdev), commit SHAs, host and VM load notes.
   - Saved to `plans/reports/` and implementation-notes. If the spread is > 10 %, run more repeats.

## Gate M4 (`gate-m4-ns3-build.sh`)
- A clean clone builds by script, with exit 0.
- **No asn1c or e2sim linkage:**
  - `ldd` of the ns-3 libs and scenario binary shows no `e2sim` or `asn1c`
  - `nm -D` shows no `asn_DEF_*` symbols
  - `grep -r e2sim build/CMakeCache.txt` is empty
- scenario-zero runs `--simTime=2` to completion with the emitter enabled and the null sink.
- Timing report exists with SHA and repeats ≥ 3.

Pass → snapshot `l4-ns3-build`. Push the branches.

## Risks
- **The RC removal footprint may be wider than expected** (callbacks in the enb net devices). Keep code paths compiled-out rather than deleted where M8 will need them, but ensure no asn1c reference remains.
- **GCC 13 / CMake 3.28 on noble with ns-3.38.** If the fixes snowball, consult kongming after 2 failed attempts.

## Review amendments (contract-preserving review, 2026-10-21)
- **K5: the decoupling is wider than "drop find_external_library".** The helpers are ASN-coupled at compile level. Extra work items:
  - `helper/indication-message-helper.h:28` includes `kpm-indication.h`, which includes the E2SM ASN headers. Replace the asn1c-backed internals with plain value types.
  - Remove `E2AP_PDU_t` from the public net-device headers (`mmwave-enb-net-device.h:109`, `lte-enb-net-device.h:239`) and the e2sim include at `mmwave-enb-net-device.cc:34`.
  - Compile RC out (`asn1c-types.h:32-53`).
- **K7: emitter behaviour.** IPC writes use `MSG_NOSIGNAL`. Reconnect is non-blocking with backoff. Drops are counted and logged per node.
- **K14: timing runs.**
  - Run the compiled scenario binary directly in its own process group.
  - Assert before each repeat that no stray ns-3 process exists.
  - Time with `time.monotonic()` around the direct binary call (not `./ns3 run`, which adds a compile check).
- **K11 (D3): add `--nMmWaveEnbNodes` to `scratch/scenario-zero.cc`** (default 4; `nUeNodes = ues * nMmWaveEnbNodes` unchanged).
  - Timing runs use 1 and 4.
  - M4 also asserts that a default run (no arg) emits the same node and UE counts as before.

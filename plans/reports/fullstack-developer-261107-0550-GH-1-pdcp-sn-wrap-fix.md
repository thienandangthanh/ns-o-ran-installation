# PDCP SN-wrap fix + `pdcp-sn-wrap` gate check (check-diff ledger row 160): implementation report

Status: drafted, uncommitted. The suite is RED against the unfixed code and GREEN with the fix, both on a host build of the pinned ns-3 (74c165f1, whose src/lte matches m10-cp2's ea6e46f6).

## Files changed (all uncommitted)

ns-3 fork (`ns-3-mmwave-oran/`, branch dev/l-release-nist180):
- `src/lte/model/lte-pdcp-sn-wrap.h` (new, 69 lines): `PDCP_SN_SPACE = 4096`, `OrderPdcpSnsByCount`, `IsPdcpSnInForwardingLookback`.
- `src/lte/model/lte-pdcp-sn-wrap.cc` (new, 72 lines): pure helpers; NS_ASSERT on SN >= 4096 and on duplicate SNs.
- `src/lte/test/lte-test-pdcp-sn-wrap.cc` (new, 286 lines): suite `pdcp-sn-wrap`, UNIT, 13 QUICK cases.
- `src/lte/model/lte-rlc-am.{h,cc}`: `GetTransmittingRlcSduBuffer()` now returns `std::vector<std::pair<uint16_t, Ptr<Packet>>>` in COUNT order. The storage map stays keyed by SN (key type is now `uint16_t`), so an SDU reassembled again still replaces its earlier copy.
- `src/lte/model/lte-enb-rrc.cc`, `src/lte/model/lte-ue-rrc.cc`: iterate the vector, and replace the `uint16_t − 2` test with `IsPdcpSnInForwardingLookback`.
- `src/lte/CMakeLists.txt`: registers the helper source, header and test.

Harness:
- `scripts/build-ns3.sh`: in `--tests` mode only, `--filter-module-examples-and-tests=mmwave` becomes `"--filter-module-examples-and-tests=mmwave;lte"`, and the header comment is updated. The plain build flags are byte-unchanged.
- `scripts/gates/gate-m4-ns3-build.sh`: adds `check m4_ns3_pdcp_sn_wrap_suite_passes ns3_suite_passes pdcp-sn-wrap` after the neighbour-list check.

Evidence (small text):
- `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/p10-sn-wrap/red-at-cp2-code/` holds `tree.txt` (provenance, sha256 and the red-only helper), `test-py-pdcp-sn-wrap.txt`, `test-runner-pdcp-sn-wrap.txt` and `per-case.txt`.
- `.../p10-sn-wrap/green/` holds `tree.txt`, `test-py-pdcp-sn-wrap.txt` and `test-runner-pdcp-sn-wrap.txt`.

## Design and spec basis

- **COUNT ordering.** SDUs still awaiting delivery confirmation lie on an arc of the SN circle that is shorter than half the SN space, because a receiver can only recover COUNT from an SN within half the space:
  - TS 36.323 V16.5.0 §5.1.2.1.2, with Reordering_Window = 2048 for 12-bit SNs, "i.e. half of the PDCP SN space" (§7.3);
  - TS 38.323 V17.5.0 §5.2.2.1 (RCVD_HFN from RX_DELIV ± Window_Size), with Window_Size = 2^(SN size − 1) (§7.2).

  `OrderPdcpSnsByCount` therefore sorts the SNs and starts after the widest circular gap. The reference is derived from the set itself, not from the "first SDU". This keeps the order independent of the input order, and of the RLC raw-SN order that feeds `m_transmittingRlcSdus` (see consumer 4 below).

  The ascending-COUNT requirement comes from TS 36.323 §5.2.1.1 and TS 38.323 §5.1.2 (re-establishment: "in ascending order of the COUNT values"). COUNT is defined in TS 36.323 / 38.323 §6.3.5, and the 12-bit DRB PDU in TS 36.323 §6.2.3 and TS 38.323 §6.2.2.2. The clauses were checked in the ETSI PDF text.
- **No change without a wrap.** When the SN span is under 2048, the wrap-round gap (more than 2048) is strictly the widest, so the result is the ascending order that the old `std::map` produced. A tie goes to the wrap-round gap, which also gives ascending order. The no-wrap cases pass on both the red and the green code.
- **Lookback.** `IsPdcpSnInForwardingLookback(sn, sn1)` is `(sn1 − sn) mod 4096 ≤ 2`. It keeps the old window {SN_1−2, SN_1−1, SN_1}, which includes SN_1 itself, so selection without a wrap is unchanged. At SN_1 = 0 it now accepts {4094, 4095, 0}; the old code accepted {0}. At SN_1 = 1 it accepts {4095, 0, 1}; the old code accepted {0, 1}.
- **SN width.** LtePdcp, McEnbPdcp and McUePdcp all have `m_maxPdcpSn = 4095`, and LtePdcpHeader masks the SN with `0x0FFF`. The MC PDCP paths therefore feed the same 12-bit SNs into these functions.
- **One helper for eNB and UE.** Both RRCs call the same function (DRY), so the lookback cases are named "eNB and UE …". The suite calls the production helpers directly. The RLC case also runs the real `LteRlcAm::RlcPdusToRlcSdus` → `CreateRlcSduBuffer` → `GetTransmittingRlcSduBuffer` path, with no helper copy involved.

## Consumers / raw-SN orderings on the forwarding path

| # | Site | Verdict |
|---|---|---|
| 1 | `lte-rlc-am.cc` CreateRlcSduBuffer (map keyed by PDCP SN), `lte-rlc-am.h` m_transmittingRlcSduBuffer | Fixed: the getter returns COUNT order; the map is private and read only through the getter |
| 2 | `lte-enb-rrc.cc:1058-1071`, `lte-ue-rrc.cc:1725-1738` (the only getter callers; grep confirms none in src/, scratch/ or oran-interface) | Fixed: they iterate the COUNT-ordered vector, so `m_x2forwardingBuffer.at(0)` / `m_rlcBufferToBeForwarded.at(0)` is now the oldest SDU (4094, not 0) |
| 3 | `lte-enb-rrc.cc:1105`, `lte-ue-rrc.cc:1774` lookback | Fixed: modular helper |
| 4 | `MergeBuffers` (`lte-enb-rrc.cc:799`, `lte-ue-rrc.cc:1584`) compares RLC SNs with `SequenceNumber10::operator>`, which has modulus base 0 (a raw compare); `m_txedBuffer` / `m_retxBuffer` are `vector[1024]` indexed by raw RLC SN and iterated 0..1023 | **Not fixed.** This is the 10-bit RLC SN, outside row 160's PDCP scope. Complete SDUs are re-sorted by PDCP COUNT in #1, so the forwarded order is correct. An SDU segmented across the RLC 1023→0 boundary can still be mis-reassembled in `Reassemble`. Pre-existing; needs its own ruling/row |
| 5 | `m_txedRlcSduBuffer` iteration in the lookback loop | Fine: transmission order, insertion preserves it. The buffer is cleared at more than 1024 entries (< 2048), so the modular distance is unambiguous |
| 6 | Target side (X2 `SendUeData` / `ForwardRlcPdu` → target PDCP/RLC) | No SN ordering; the target assigns its own SNs |
| 7 | `src/mmwave/bindings/modulegen__gcc_*.py` still name the old map signature | Not touched: stale pybindgen files, not built by ns-3.38 (`--disable-python`) |

Pre-existing behaviours kept as they were, to preserve no-wrap behaviour (open questions below):
- The lookback window includes SN_1 itself, so the head SDU is likely forwarded twice.
- `m_transmittingRlcSdus` and the map are never cleared between forwardings; the existing `// TODO check if it must be emptied` is kept.

## Red run (the pinned ns-3 code plus the suite and a helper .cc reproducing the old behaviour; lte-rlc-am, eNB RRC and UE RRC untouched)

- `test.py -n -v -s pdcp-sn-wrap`: `[1/1] FAIL: TestSuite pdcp-sn-wrap`, rc 1. ns-3 stops a suite at its first failing case.
- Per-case run (probe: only the suite constructor was changed to register one case selected by an environment variable; reverted afterwards):

| Case | Result | Old-code output |
|---|---|---|
| COUNT order {4094,4095,0,1} | FAIL | got `0,1,4094,4095` |
| COUNT order {4095,0} | FAIL | got `0,4095` |
| **RLC AM SDU buffer {4094,4095,0,1}** (unmodified std::map code) | FAIL | got `0,1,4094,4095` |
| Lookback SN_1=0 | FAIL | got `0` (want `0,4094,4095`) |
| Lookback SN_1=1 | FAIL | got `0,1` (want `0,1,4095`) |
| 5 no-wrap ordering cases, no-wrap RLC buffer, lookback at 2 and 4095 | PASS | — |

## Green run

- `test.py`: `[1/1] PASS: TestSuite pdcp-sn-wrap`, rc 0, and all 13 cases PASS in the runner output.
- The gate's PASS-line regex matches, and there is no FAIL/CRASH/SKIP line.
- Regression check on the same tree: mmwave-neighbour-list, lte-rlc-am-transmitter, lte-rlc-am-e2e and lte-rlc-header all PASS.
- The fix compiles with no new warnings.

## Cost of adding the lte tests (host, -j8, gcc 16.2.1)

| Build | Wall time | CPU time | Peak RSS |
|---|---|---|---|
| Baseline test-runner, filter=mmwave (all libs from scratch) | 232 s | 1569 s | 1.4 GB |
| Incremental after `mmwave;lte`: 58 lte test sources + link | +32 s | +219 s (~+14 %) | 0.8 GB |

The lte test library is 67 MB on disk. The ns-3.38 syntax is a CMake list with `;`. `./ns3` passes it as a single argv element (`subprocess.run(list)`), and the recorded flags file shows it `%q`-escaped. The full ns-3.38 lte test set compiles in this fork.

## Host-build notes

- Ubuntu 24.04-like Python was needed: the host's Python 3.14 breaks ns-3.38's `./ns3` argparse, so a user-local Python 3.12.13 was fetched with `uv` (no system packages).
- ns-3's CMake treats any source path containing "scratch" as a scratch program dir. The tree therefore had to live at `/tmp/claude-1000/ns3-pdcp-sn-wrap-910ba118` rather than under the session scratchpad. It has been removed since (`git worktree remove`).
- The VM was not touched.

## Lint

- `bash scripts/gates/lint.sh`: `lint: ok`, rc 0.
- `shellcheck -x -S warning` on both edited scripts: clean.
- `bash -n` on both: ok.

## Unresolved questions

1. `plans/.gitignore` ignores `evidence/p10-sn-wrap/**` (pattern `/*/evidence/*/*/**`). Add `!/*/evidence/p10-sn-wrap/**` (like p03-unit) before committing, or the red proof stays out of git.
2. RLC 10-bit raw-SN ordering (`MergeBuffers`, txed/retx vectors iterated 0..1023): accept it as out of scope, or add a ledger row?
3. The lookback window includes SN_1 itself, which likely duplicates the head SDU on X2. It was kept for no-wrap identity. Does it need a separate ruling?
4. Row 160 wording: "CreateRlcSduBuffer … iterates in COUNT order" is met through the getter; CreateRlcSduBuffer still fills an SN-keyed map. Is the ledger wording fine as is?

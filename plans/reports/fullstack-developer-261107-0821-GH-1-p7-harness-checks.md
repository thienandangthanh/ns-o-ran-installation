# P7 harness checks (rows 148-150): implementation report

All six items are implemented and nothing is committed. Two results need a controller decision before P7 runs:
- **Row 149 is red at M7 at the current pins.** It is also red in all 15 archived M7 runs, so the row's claim that it "passes at m10-cp2" is wrong for M7. An amendment draft is in §3.
- **lint.sh is red on purpose** until pins.conf NS3_SHA moves to the P7 ns-3 commit (§5).

## Files changed (uncommitted)
| File | +/- |
|---|---|
| scripts/gates/gate-m4-ns3-build.sh | +3 |
| scripts/gates/gate-n4-ul-metric.sh | +82 / -19 |
| scripts/gates/n4-run-byte-identity.py | +27 / -4 |
| scripts/gates/check-pdcp-volume-totals.py | +18 / -9 |
| scripts/gates/rung-config.json | 1 line |
| scripts/gates/lint.sh | +49 / -1 |
| scripts/gates/gate-m6-kpm.sh, gate-m7-multignb.sh | +2 each |
| tools/e2-evidence/trace-facts.py | +55 / -1 |
| tools/e2-evidence/selftest.sh | +15 (the existing home of trace-facts.py's tests, run by lint.sh) |

I did not touch ns-3-mmwave-oran/, pins.conf, build-ns3.sh, agents-ns3-run.sh, paced-lib.sh, the ledger or p10-gate-chain.sh. The submodule shows `m` in git status because of the other developer's work, not mine.

## 1. Row 148, M4 check
- `check m4_ns3_pdcp_mc_nr_header_suites_pass ns3_suite_passes mc-pdcp-nr-header` is at gate-m4-ns3-build.sh:383, right after the pdcp-sn-wrap check.
- **Anchor moved:** the row's ":181" is now `m4_build_ns3_exit0`. The unit suites need the `--enable-tests` tree (section i, :349-385), so the check has to sit there. The plain tree has no test.py build.

## 2. Row 148 (b), N4 byte identity: `--part identity`
- **Judge flag:** `n4-run-byte-identity.py compare --except-audit-header A B` leaves out exactly one item, `ns3run/stdout.txt:audit-header`. The report lists `"skipped"`. `compare()` asserts that no other item can be skipped.
- **Self-test:** 6 new fixtures, 37 in total, all ok.
  - With the flag, a changed or removed header passes.
  - With the flag, a changed audit event, trace byte, IPC sample or argv still fails.
  - Without the flag, the existing "a changed audit header" fixture still fails.
- **Shared run helper:** `det_run` and `BYTES` moved out of the determinism block unchanged, so both parts run the same helper. The determinism code is otherwise untouched.
- **Same config:** the identity part reads the UL pattern and RngRun from rung-config.json, same as determinism (`--ul-pattern` is refused). It builds no twin tree and runs on the M4 build located by `agents_ns3_locate`.
- **Checks, in order:**
  - `n4_identity_reference_sha256_ok`: SHA256SUMS lists both a1 manifests, then `sha256sum -c`.
  - `n4_identity_uloff_free_run`, `n4_identity_ulon_free_run`.
  - `n4_identity_emitters_at_pins`: the pins are not a compared item; they must be the pins.conf pair.
  - `n4_identity_uloff_byte_equal_to_reference`, `n4_identity_ulon_byte_equal_to_reference`: compared with `--except-audit-header` against `reference/n4-sn-wrap/n4-run-bytes-<cfg>-a1.manifest.json`.
  - **New, not registered:** `n4_identity_ulon_pdcp_audit_judge_passes` runs check-pdcp-volume-totals.py on the ulon run. Draft amendment below.
  - `n4_no_stray_process`.
- **Reference path:** the default is `$HARNESS_DIR/plans/261103-0008-GH-1-post-m9-realism-m10/reference/n4-sn-wrap`, overridable with `N4_IDENTITY_REF`. This follows the existing `IDENTITY_MAP_CP1` pattern, and the reference files are git-tracked, so the VM harness clone has them.
- **Offline test on the archived SN-wrap determinism runs** (evidence/n4/20261106T230003Z/runs, copied to scratch):
  - Unmodified ulon-a2 and uloff-a2 against the reference with the flag: equal on 36 items, exit 0.
  - ulon-a2 with its header rewritten to `N4AUDIT v1 hdr=2 class=ns3::NrPdcpHeader`: exit 0 with the flag and exit 1 without it (only the audit-header item differs). check-pdcp-volume-totals passes on it (A1 true). Unmodified, it fails A1 because the line has no class.
  - With one dltx byte changed, the flag still fails (`ns3run/stdout.txt:body`).
  - uloff compared with the ulon reference differs on 22 items.

**Draft ledger amendment for the new check** (additive, after "Row 150"):
> **Row 150, amended before code (2026-11-07; additive): where the class conjunct is judged at P7.** Row 148 (b)'s compared set leaves out the audit header line. P7's `gate-n4-ul-metric.sh --part identity` judges that line with the whole audit: it runs `check-pdcp-volume-totals.py` (A0-A5, A1 with the class conjunct) on its ulon run, as `n4_identity_ulon_pdcp_audit_judge_passes`. Offline evidence: the SN-wrap determinism run ulon-a2 (evidence/n4/20261106T230003Z) passes the judge with its header line in the P7 form and fails A1 unmodified. Not weaker (new check). Contract change: No.

## 3. Row 149, `--pdcp-stats` at M6 and M7
**File and columns: verified as drafted.**
- `DlE2PdcpStats.txt` gets its name at `src/mmwave/helper/mmwave-helper.cc:3198` (at 4a0871d6).
- `MmWaveBearerStatsCalculator::WriteDlResults` writes it (`src/lte/helper/mmwave-bearer-stats-calculator.cc:438-480`, header `:363-366`): `% start end CellId IMSI RNTI LCID nTxPDUs TxBytes nRxPDUs RxBytes ...`.
- Rows are keyed by `m_dlTxPackets`, and `DlTxPdu` sets the flow id (`:216`), so LCID is valid wherever nTxPDUs > 0.
- The connector feeds it from `UeMap/<rnti>/DataRadioBearerMap/*/LtePdcp/TxPDU` (`src/mmwave/helper/mmwave-bearer-stats-connector.cc:1187-1199`).
- McEnbPdcp fires TxPDU after `AddHeader` (`mc-enb-pdcp.cc:221,238` after `:247-258`), so TxBytes counts PDU bytes.
- LCID 3 is the only LCID in every archived file. The SDU is 1308 bytes: `scenario-zero.cc:693` PacketSize 1280, plus 28.
- Real files: m6/20261106T223021Z has 294 rows, all equal to nTxPDUs × 1310. m7/20261106T223229Z has 5016 rows, of which 13 are not.

**Implementation.**
- `trace-facts.py --pdcp-stats FILE` finds columns by their header names.
- It fails on a data row before a header, a malformed row, no judged row, or a missing file.
- It is wired as `m6_pdcp_dl_pdu_bytes_eq_sdu_plus_nr_header` (after the agent counters check) and `m7_pdcp_dl_pdu_bytes_eq_sdu_plus_nr_header` (after the UE-context check), both on `$RUN/DlE2PdcpStats.txt`.
- selftest.sh adds 6 cases, all ok: an ok fixture passes; a 1308 + 3 row fails; a short row fails; no LCID-3 row fails; no header fails; a missing file fails.

**Finding: the registered predicate fails at M7 at the current pins and at m10-cp2.**

| Archive | Runs | Rows breaking the equality |
|---|---|---|
| M6 | 15/15 green | 0 per run (294 rows each) |
| M7 | 15/15 red | 13 or 14 per run (out of 5016-5376) |

- In every M7 run, all failing rows are LCID 3 with TxBytes **below** nTxPDUs × 1310 (deficits of 1, 7, 25 or 40 B).
- These are burst epochs with nTxPDUs in the hundreds to thousands.
- **Every** failing row's epoch [start, end) holds a SwitchToLte or SwitchToMmWave of that IMSI (MmWaveSwitchStats.txt / LteSwitchStats.txt). That is 13/13 or 14/14 in each of the 15 runs.
- Likely mechanism [I, static reading only, not proven at run time]: at an LTE↔mmWave switch, the UM branch of `UeManager::ForwardRlcBuffers` (`lte-enb-rrc.cc:1093-1157`, "Forward to mmWave cell in switch") puts each RLC UM tx-buffer entry back into McEnbPdcp after `RemoveHeader`. An entry whose head was already partly sent as a segment is short, so its re-sent PDU is smaller than SDU + 2. This is not a header-size effect.

As registered, P7's M7 will be red. I implemented the registered predicate unchanged. Draft amendment:
> **Row 149, amended before code (2026-11-07; additive; the row text above is left unedited).**
> - **File and columns:** verified as drafted.
>   - `DlE2PdcpStats.txt` (`mmwave-helper.cc:3198`), columns by header name `LCID`, `nTxPDUs`, `TxBytes` (`mmwave-bearer-stats-calculator.cc:363-366, 438-480`).
>   - TxBytes counts McEnbPdcp TxPDU sizes after the header is added (`mc-enb-pdcp.cc:221,238`).
>   - SDU 1308 = `scenario-zero.cc:693` 1280 + 28.
> - **Why the amendment:** the row's predicate does not hold at the current pins or at `m10-cp2` on M7.
>   - The 15 archived M7 runs have 13-14 LCID-3 rows each with TxBytes < nTxPDUs × 1310, all in an epoch holding an LTE↔mmWave switch of the row's IMSI.
>   - Likely cause [I]: the switch re-inserts partly sent RLC UM entries into the MC PDCP (`lte-enb-rrc.cc:1093-1157`).
>   - The 15 archived M6 runs hold no such row.
> - **Predicate:** over the LCID-3 rows with nTxPDUs > 0 of `DlE2PdcpStats.txt`:
>   - a row whose epoch [start, end) holds no SwitchToLte or SwitchToMmWave of its IMSI (`MmWaveSwitchStats.txt`, `LteSwitchStats.txt`, same run) has TxBytes = nTxPDUs × (1308 + 2);
>   - a row whose epoch holds one has TxBytes ≤ nTxPDUs × (1308 + 2);
>   - at least one row is of the first kind.
> - **Self-test fixtures:**
>   - 1308 + 3 on a row without a switch fails;
>   - 1308 + 3 on a switch row with no deficit fails;
>   - a short switch row passes;
>   - a short row without a switch fails;
>   - no row of the first kind fails.
> - **Archive check:** all 15 M7 runs pass. 920-988 rows per run are switch rows; all failing rows are among them and all of them satisfy ≤. All 15 M6 runs pass.
> - **Recorded openly:** switch rows are judged on an upper bound only. The defect in switch re-insertion is a follow-up outside M10. Not weaker than a predicate that was never green. Contract change: No.

The code change for this amendment is about 12 lines in `pdcp_dl_pdu_bytes` (read the two switch files from the stats file's directory) plus 3 fixtures. I can make it once the controller rules. The other options are dropping the M7 wiring (weaker) or accepting a red M7 (a stop).

## 4. Row 150, check-pdcp-volume-totals.py and rung-config.json
- `HDR` (:37) now cites 38.323 §6.2.2.2 for the MC DRB, and a new `HDR_CLASS = "ns3::NrPdcpHeader"` follows.
- `load_audit` reads `class=` from field 4 only when the line has exactly 4 fields. A1 (:103) adds `cls == HDR_CLASS`. The output gains `hdrClass`. The doc at :10-12 is rewritten; A5 is unchanged.
- Self-test: the good fixture's header line now carries the class. New cases "header class LtePdcpHeader", "header line without a class" and "class with a trailing field" all fail as required (18 cases ok).
- Every pre-P7 run now fails A1, as row 150 intends. The only consumers are the N4 v23 part and the new identity check.
- rung-config.json `pdcpHeaderSource` follows the file's convention, `ns-3-mmwave-oran@<sha> <file> <Class::Method>; 3GPP TS <spec> V<ver> <clause>`. The value is now `ns-3-mmwave-oran@NS3_P7_SHA src/lte/model/nr-pdcp-header.cc NrPdcpHeader::GetSerializedSize, the MC DRB header (audit line class=ns3::NrPdcpHeader); 3GPP TS 38.323 V19.1.0 6.2.2.2 (12-bit SN data PDU)`.
  - **The controller replaces the `NS3_P7_SHA` token with the 8-hex P7 commit at pin time,** and adds `:lines` if wanted (the file was not committed yet).
  - V19.1.0 is the version the plans cite for `MSNDDXJH`. No code reads this field.

## 5. Row 148 (a), source lint in lint.sh
- **Rule table:** `NS3_SOURCE_RULES` at the top of lint.sh (:20) holds triples of `<path under ns-3-mmwave-oran> <forbidden ERE> <required ERE or ''>`. To start with, `LtePdcpHeader` is forbidden in `src/lte/model/mc-{enb,ue}-pdcp.{h,cc}`.
- **Functions:**
  - `source_rule <label> <file> <forbid> <need>` prints one line per hit.
  - `ns3_source_lint` reads each file with `git -C ns-3-mmwave-oran show "$NS3_SHA:<path>"`, taking NS3_SHA from pins.conf in a subshell.
- **What I chose:** the lint reads the files committed at the pinned SHA from the submodule's object store, not its working tree. So the other developer's uncommitted edits never affect it, and it needs no HEAD==pin condition. A path that is not readable at the pin fails with "fetch the pinned commit".
- **Self-test on fixture text:**
  - an NR-only fixture passes;
  - a fixture naming LtePdcpHeader fails;
  - a missing required pattern fails;
  - the report is exactly one line per matching line, checked with an ERE alternation.
- **Interaction:** at the current pin (4a0871d6), lint.sh exits 1 with 6 hits (mc-enb-pdcp.cc:247,256,313 and mc-ue-pdcp.cc:197,206,258) plus "an ns-3 source rule fails at the pinned ns-3 commit". That is the **only** failure in the full lint run; every other self-test, the shellcheck pass and the bash -n pass are clean. Lint goes green once pins.conf NS3_SHA names the P7 commit and that commit exists in the local submodule.

## 6. Chain driver step for N4 identity (not edited)
Append this line to `steps=(...)` in p10-gate-chain.sh as index 13:
```
  "n4|gate-n4-ul-metric.sh|3600|--part identity"
```
Also add this header comment line: `#   step 13 (n4, --part identity) is P7's N4 byte identity with the banked SN-wrap reference`. For P7's chain, run with `P10_SKIP_STEPS` including 12 (determinism must not re-run at P7) plus whatever else the controller skips. Both n4 steps share the id `n4` / `.last-n4`, which is fine when they run one after the other.

## Tests run
- `python3 -I scripts/gates/n4-run-byte-identity.py --self-test`: ok, 37 fixtures.
- `python3 -I scripts/gates/check-pdcp-volume-totals.py --self-test`: 18/18 ok.
- `bash tools/e2-evidence/selftest.sh`: exit 0 (6 new pdcp-stats cases ok).
- bash -n and shellcheck (lint flags) on every edited .sh: clean. Shellcheck on selftest.sh: clean.
- `bash scripts/gates/lint.sh`: exit 1, only from the pin-dependent source rule (expected).
- Offline identity simulation on the archived determinism runs: as in §2.

## Unresolved questions
1. Row 149 at M7: amend as in §3, drop the M7 wiring, or keep it as registered (P7's M7 goes red)?
2. Accept the new `n4_identity_ulon_pdcp_audit_judge_passes`, with the row 150 amendment in §2, or drop it and leave row 150's class conjunct unjudged until P9's `--part v3`?
3. The lint table: the controller tightens it with the ns-3 developer's exact rule (for example the consumers in lte-{enb,ue}-rrc.cc and lte-rlc-am.cc, which hold both LTE and MC paths, so whole-file forbids do not fit).

Status: DONE_WITH_CONCERNS
Summary: Checks for rows 148-150 are implemented and self-tested: the M4 suite, N4 `--part identity` with `--except-audit-header`, `--pdcp-stats` at M6 and M7, the class conjunct in A1, and the pinned-source lint. lint.sh is red only on the expected pin-dependent rule.
Concerns: Row 149's registered predicate fails in all 15 archived M7 runs (13-14 switch-epoch rows each), so P7's M7 will be red without the drafted amendment. The new check `n4_identity_ulon_pdcp_audit_judge_passes` needs a ledger amendment. rung-config.json carries the `NS3_P7_SHA` placeholder.

---

## Follow-up (2026-11-07): source lint tightened to the ns-3 developer's rule
Accepted by the controller: `n4_identity_ulon_pdcp_audit_judge_passes`. Row 149 is in consensus, so `--pdcp-stats` is unchanged.

The source lint now matches the ns-3 developer's rule exactly (ns-3 report 261107-0820, "Source-lint rule"). It still reads the tree committed at pins.conf NS3_SHA, and lint.sh is red only on this rule at the current pin.

**Files.**
- New: `scripts/gates/ns3-source-lint.py` (about 260 lines; the rule table is at its top).
- Changed: `scripts/gates/lint.sh`. The bash table and functions of item 5 are replaced by two calls: the pinned lint and its self-test.

**The rule, as coded:**
- **Scope:** `*.h` and `*.cc` under `src/`, `scratch/` and `contrib/`, excluding `src/*/bindings/`.
- **Stripping first:** comments, string literals, raw strings and character literals are blanked, with line numbers kept. A digit separator (`1'000`) is not treated as a character literal.
- **Match:** `\bLtePdcpHeader\b`.
- **ALLOWED** (an allowlist, so a new file is caught):
  - `src/lte/model/lte-pdcp-header.{h,cc}`, any count;
  - `src/lte/model/lte-pdcp.cc`, exactly 4 matching code lines (a count, not line numbers);
  - `src/lte/test/lte-test-entities.cc` and `src/lte/test/lte-test-mc-pdcp-nr-header.cc`, any count.
- **lte-helper.cc needs no allowlist entry.** On the working tree its only raw hit, `:1462`, is inside a string literal and strips to 0 code lines.
- **MUST_BE_ZERO:** the 15 files the controller listed. A count of 0 already follows from the allowlist. Each file must also **exist**, so a rename cannot leave the list stale.
- **POSITIVE facts**, checked on stripped code, so a comment cannot satisfy them:
  - `using DataPduHeader = NrPdcpHeader;` in mc-enb-pdcp.h and in mc-ue-pdcp.h;
  - lte-rlc-am.cc has exactly one explicit instantiation (any `template` not followed by `<`), and it is `RlcPdusToRlcSdus<NrPdcpHeader>`;
  - mmwave-enb-net-device.cc contains `McEnbPdcp::DataPduHeader().GetSerializedSize()`.
  - I left out the optional "`RlcPdusToRlcSdus<` names `PdcpHeader`" conjunct for lte-{enb,ue}-rrc.cc; it was not in your list.

**Readers:**
- `--git REPO SHA` reads with `git ls-tree -r --name-only SHA -- src scratch contrib` and `git cat-file --batch` (2794 files in about 3 s). This is what lint.sh runs.
- `--dir DIR` is for fixtures and for looking at uncommitted work only. It is never a gate.
- An unreadable SHA exits 2.

**Results:**
- **At the current pin (4a0871d6), red with 13 problems:**
  - LtePdcpHeader in scenario-zero.cc, lte-enb-rrc.cc, lte-ue-rrc.cc, lte-rlc-am.cc, mc-enb-pdcp.cc, mc-ue-pdcp.cc, lte-test-pdcp-sn-wrap.cc and mmwave-enb-net-device.cc;
  - lte-pdcp.cc on 3 code lines instead of 4;
  - all 4 positive facts missing.
- **On the ns-3 developer's uncommitted P7 working tree (`--dir ns-3-mmwave-oran`), ok on 2797 files:**
  - lte-pdcp.cc has exactly the 4 code lines `:177, :197, :206, :239`;
  - the lte-pdcp.h hit `:127` is a comment;
  - lte-rlc-am.cc has the single instantiation `<NrPdcpHeader>`.

  So the lint should go green once that change is committed and pinned.

**Self-test (`--self-test`, 23 cases, ok):**
- These pass: the good tree; a hit in a line comment, in a block comment spanning lines, in a string with an escaped quote, or in a raw string; a longer identifier (`MyLtePdcpHeaderX`); a bindings file; the good tree read through `--dir`.
- These fail, as required:
  - a hit in a new file, in an MC file, in scratch/ or in contrib/;
  - a hit after a `'"'` character literal, or after a `1'000` digit separator;
  - lte-pdcp.cc with 5 code lines, with 3, or with 4 matches on 3 lines;
  - a listed consumer missing;
  - the alias missing, or present only in a comment;
  - a second explicit instantiation, none at all, or one for another header;
  - the NR header-size call missing.

**Checks run:**
- `python3 -I scripts/gates/ns3-source-lint.py --self-test`: ok.
- bash -n and shellcheck on lint.sh: clean.
- `bash scripts/gates/lint.sh`: exit 1, and the only failure is this rule at the pin (13 problem lines plus the summary). Everything else is clean.

Status: DONE
Summary: The source lint is now the allowlist rule with comments and literals stripped, the 4-line count on lte-pdcp.cc, the consumer-existence list and the three positive facts, read at pins.conf NS3_SHA from the submodule's objects. It passes on the ns-3 developer's uncommitted P7 tree and is red only at the current pin.
Concerns: none beyond the open row 149 consensus.

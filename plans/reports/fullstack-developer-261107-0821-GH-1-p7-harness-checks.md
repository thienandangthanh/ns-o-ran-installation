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

---

## Follow-up 2 (2026-11-07): row 149 implemented as amended (ledger 3dc3758d)
`trace-facts.py --pdcp-stats` and the M6/M7 checks now follow the block "Row 149, amended before code (2026-11-07, unanimous brainstorm consensus …)" exactly. The check names are unchanged.

**CLI.** The command is now `trace-facts.py --pdcp-stats <ns3run dir> [--out fact.json]`. It takes the directory, not the stats file. It reads `DlE2PdcpStats.txt`, `LteSwitchStats.txt` and `MmWaveSwitchStats.txt` from that one directory, so all three always come from the same run.

**Predicate, as coded:**
- Rows judged: LCID-3 rows with nTxPDUs > 0. Columns `start`, `end`, `IMSI`, `LCID`, `nTxPDUs` and `TxBytes` are found by header name.
- W = 1308 + 2. For each row, d = end − start.
- **Switch row:** any SwitchToLte or SwitchToMmWave of the row's IMSI with a time t where start − d ≤ t < end + d. The time is field 2 and the IMSI is field 3. A switch row must have TxBytes ≤ nTxPDUs × W.
- **Every other row:** TxBytes = nTxPDUs × W.
- At least one row must not be a switch row.
- A missing switch file means no events of that kind.
- **A malformed switch line fails.** A well-formed line has exactly the 5 fields McStatsCalculator writes, `<kind> <time> <imsi> <cellId> <rnti>` (`src/mmwave/helper/mc-stats-calculator.cc:144,165` at 4a0871d6). The kind must match the file: SwitchToLte in LteSwitchStats.txt, SwitchToMmWave in MmWaveSwitchStats.txt.
- **Fact:** printed as JSON and written to `--out`. It holds `switchRows`, `equalityRows`, `switchEvents`, `problems` and `perImsi` (switch-row and equality-row counts per IMSI).

**Gate wiring.**
- M6: `check m6_pdcp_dl_pdu_bytes_eq_sdu_plus_nr_header python3 -I "$E2EV/trace-facts.py" --pdcp-stats "$RUN" --out "$e/m6-pdcp-dl-pdu-bytes.json"`, followed by `fact pdcpDlPduBytes …`.
- M7: the same, with m7 names.
- `RUN="$EVIDENCE_DIR/ns3run"` in both gates. ns-3 writes its stats and both switch files there; all 30 archives have them in `ns3run/`.

**Self-test** (tools/e2-evidence/selftest.sh, 18 pdcp cases, all ok).
- Must fail, all as the block lists:
  - 1308 + 3 on a non-switch row;
  - 1308 + 3 on a switch row, nTxPDUs 253 > deficit 40;
  - a short non-switch row;
  - a short row whose only switch is two epochs away;
  - a short row whose switch belongs to another IMSI;
  - no non-switch row;
  - a malformed switch line.
- Must fail, extra cases: a switch line of the wrong kind for its file; no column header; a directory without DlE2PdcpStats.txt.
- Must pass:
  - a short row with its switch in the previous, same or next epoch;
  - absent switch files with every row equal;
  - a short row covered by a SwitchToLte in the previous epoch (shows LteSwitchStats.txt is read).
- One case also checks the fact's overall and per-IMSI counts.

**Archive replay (offline, all 30 runs): 30/30 pass. Counts match the amendment exactly.**

| Archive | Runs passing | Equality rows | Switch rows | Switch events |
|---|---|---|---|---|
| M6 | 15/15 | 201 | 93 | 78 |
| M7 | 15/15 | 3308–3557 | 1708–1819 | 9723–10928 |

The M7 runs fall into four trajectories by row count: 3308/1708, 3399/1737, 3467/1789 and 3557/1819.

**Checks run:**
- tools/e2-evidence/selftest.sh: exit 0.
- Python self-tests under `-I` (n4-run-byte-identity, check-pdcp-volume-totals, ns3-source-lint): all ok.
- bash -n and shellcheck on gate-m6-kpm.sh, gate-m7-multignb.sh and selftest.sh: clean.
- lint.sh: exit 1, and the only failure is the pin-dependent ns-3 source rule at 4a0871d6.

Status: DONE
Summary: Row 149 is implemented as amended. The check judges the stats file against both switch files of the same run, with a ±1-epoch window, ≤ on switch rows, equality elsewhere and at least one non-switch row, and it records per-IMSI counts in a fact. All 30 archived runs pass with the expected counts, and lint.sh is red only on the pinned source rule.
Concerns: none.

---

## Codex findings fixed (2026-11-07)
**1. HIGH: the identity part's reference check could pass falsely** (gate-n4-ul-metric.sh `ref_sums`).
- **Reproduced first.** A SHA256SUMS holding one valid entry (PROVENANCE.txt) plus two bare manifest-name lines makes `sha256sum -c` exit 0.
- **Fix:** a new subcommand, `n4-run-byte-identity.py verify-reference DIR NAME...`.
  - It parses SHA256SUMS strictly: every line must fully match `<64 lowercase hex>  <name>`.
  - It rejects any other line: a bare name, binary mode (`*`), uppercase hex, a blank line, or free text.
  - Each NAME must have exactly one entry, compared on the exact name, so a missing entry, a duplicate or a look-alike name fails.
  - It computes each NAME's sha256 and compares it with that entry.
  - It prints `{"dir", "verified": {name: sha256}, "problems"}` and exits 0 only when every name is verified.
- **Gate:** `ref_sums` now runs it on the two a1 manifests it compares, writes `identity-reference-digests.json`, and records the verified digests as `fact identityReferenceDigests`.
- **Host fixtures** (in the judge's `--self-test`, which lint.sh runs):
  - Pass: the good file.
  - Fail: a missing entry; a bare-name line instead of an entry or beside the entries; a malformed line; a binary-mode line; an uppercase digest; a wrong digest; a look-alike file name only (`m-uloffXjson`); a duplicate entry; a blank line.
- **Host run of `ref_sums`:** the real reference/n4-sn-wrap is verified (e5e2a10f…, 6e8f118b…). The reproduction case now fails with "0 entries for each manifest" plus a malformed-line problem.

**2. MEDIUM: the source lint could miss forbidden code after a prefixed character literal** (ns3-source-lint.py `strip_code`).
- The old guard treated any alphanumeric before `'` as a digit separator, so `L'"'` swallowed the code after it.
- **Fix:** the lexer now reads identifiers and pp-numbers whole.
  - An identifier that is exactly `L`, `u`, `U` or `u8`, directly followed by `'` or `"`, opens a prefixed literal.
  - `R`, `LR`, `uR`, `UR` or `u8R` directly followed by `"delim(` opens a raw string, which may span lines.
  - Any other identifier is ordinary code. A `'` after it starts a character literal, as in C++, for example `return'"'`.
  - A C++14 pp-number (a digit or `.digit`, then digits, identifier characters, `'` followed by a digit or nondigit, `e+ e- p+ p-`, dots) is consumed whole. So `'` is a digit separator only inside a number: `1'000`, `0x1'FF`, `0b1'01`, `1'0e+3`.
- **New self-test fixtures, 16 in all:**
  - Fail: forbidden code after `L'"'`, `u'"'`, `U'"'`, `u8'"'`, `u8"\""` or `return'"'`; after `0x1'FF`, `0b1'01` or `1'0e+3`; after a `uR"(x)"` raw string; behind `FOOR"(`, since an identifier ending in R is not a raw prefix.
  - Pass: a hit inside an `L"…"` string, a `u8"…"` string, a `u8R"d(…")d"` raw string, or an `LR"(…)"` raw string spanning lines.
  - Self-test total: 38 cases, all ok.

**Re-run:**
- Self-tests under `python3 -I`: n4-run-byte-identity (37 fixtures plus 11 SHA256SUMS fixtures), check-pdcp-volume-totals and ns3-source-lint all pass.
- tools/e2-evidence/selftest.sh: exit 0.
- bash -n and shellcheck on every script in scripts/gates and on selftest.sh: clean.
- ns3-source-lint `--dir ns-3-mmwave-oran` on the ns-3 developer's uncommitted working tree: ok, 2799 files.
- lint.sh: exit 1. The only failure is the pin-dependent ns-3 source rule at 4a0871d6 (13 problems); everything else is clean.

Status: DONE
Summary: Both Codex false passes are fixed and each has must-fail host fixtures. The reference check now parses SHA256SUMS strictly and requires exactly one verified entry per compared manifest, recording the digests as a fact. The source-lint lexer now handles literal prefixes, raw strings and C++14 digit separators.
Concerns: none.

---

## Codex follow-up (2026-11-07): line splices inside literals, fail-closed
Finding 1 (SHA256SUMS) is closed. The finding 2 follow-up is fixed fail-closed, as instructed, without phase-2 joining. **It trips three real ns-3 files.** They are reported below and not allowlisted.

**Rule.**
- `strip_code(text, splices)` records the line of every backslash-newline (`\n` or `\r\n`) met inside a non-raw string or character literal, with any prefix.
- `lint()` reports `line splice inside a literal at <file>:<line>` for each one, so the file fails.
- **One more case than the brief named.** Phase 2 splices every backslash-newline before escapes are read, so the lexer checks both the escaping backslash and an escaped backslash. This catches `"a\\` + newline + `b"; LtePdcpHeader h;`, where an escaped backslash sits at the end of the line. g++ splices it to `"a\b"`, and the old escape-pair skip blanked the forbidden code that follows.
- Raw strings are unaffected (no escapes). A backslash-newline in ordinary code, such as a macro continuation, is lexed as before; joining is not needed to see the same tokens.

**New self-test fixtures, 12** (the self-test then had 50 cases, all ok):
- Fail:
  - the Codex case (`"` + `\\` + backslash-newline + `n"; LtePdcpHeader h;`) with an ordinary, an L and a u8 string;
  - a splice behind an escaped backslash, with LF and with CRLF;
  - a CRLF splice;
  - a splice in a string with nothing forbidden nearby (fail-closed);
  - a splice in a char literal;
  - a multi-line `#define` with continuations whose second line names LtePdcpHeader.
- Pass:
  - the same `#define` without the name;
  - a backslash-newline inside a raw string;
  - an escaped backslash ending a line inside a closed literal.

**Real tree.** The rule fires on 3 files, with 24 splices, both at the pin (4a0871d6) and in the ns-3 developer's working tree:

| File | Splices |
|---|---|
| src/lr-wpan/examples/lr-wpan-error-model-plot.cc | 12 |
| src/lr-wpan/examples/lr-wpan-per-plot.cc | 8 |
| src/lr-wpan/examples/lr-wpan-error-distance-plot.cc | 4 |

- These are genuine multi-line gnuplot strings in `SetExtra("…\n\` (upstream ns-3.38 code, last touched in 11908797 "Update to ns-3.38") and contain no LtePdcpHeader.
- **They are never compiled here.** build-ns3.sh configures `--disable-examples` and `--enable-modules=mmwave,oran-interface`, and the tests tree filters examples to `mmwave;lte`.
- **Consequence:** the ns-3 source rule stays red even after the P7 pin, unless one of these is ruled:
  - **(a)** Exclude `src/*/examples/` from scope, on the same dead-code grounds as `src/*/bindings/`. This is a rule change and needs a ledger note.
  - **(b)** Narrow the scope to the compiled modules (lte, mmwave and their dependencies).
  - **(c)** Rewrite the three example strings in the ns-3 fork. That touches upstream files outside P7's scope.
- I did not change the scope.
- **Working tree with the splice problems set aside:** no other problems, so the MC rule itself is still satisfied by the P7 tree.

**Re-run:**
- Self-tests under `python3 -I` (n4-run-byte-identity, check-pdcp-volume-totals, ns3-source-lint): all ok.
- tools/e2-evidence/selftest.sh: exit 0.
- shellcheck on scripts/gates and bash -n: clean.
- lint.sh: exit 1, only from the ns-3 source rule at the pin. It reports 37 problems: the 13 MC problems plus the 24 lr-wpan splices.

Status: DONE_WITH_CONCERNS
Summary: Line splices inside non-raw literals now fail the file, including a splice behind an escaped backslash. Macro continuations still lex correctly, and every requested fixture is present.
Concerns: Three never-compiled upstream lr-wpan example files hold real in-literal splices, so the ns-3 source rule stays red after the P7 pin until the controller rules a scope change, (a) or (b), or an ns-3 edit, (c).

---

## Splice rule narrowed per the controller's ruling (2026-11-07)
The ruling chose none of (a), (b) or (c). The splice rule now applies only to files that hold the forbidden name.

**Rule, as coded** (`ns3-source-lint.py lint()`, documented as rule 4 in the module doc):
- `joined` is the file's text with every backslash-newline (`\\\r?\n`) removed, i.e. the text after translation phase 2.
- **Literal splices.** Each recorded splice inside a non-raw literal is reported as `line splice inside a literal at <file>:<line>`, but only when `joined` contains `LtePdcpHeader`. The name is now one constant, `FORBIDDEN_NAME`, and `FORBIDDEN` is built from it.
- **Why the joined text, not the raw text.** The joined text holds the name wherever the raw text does, since the name contains no backslash or newline. It also holds the name where a second splice spells it, for example `"\\` + splice, followed by `LtePdcp\` + newline + `Header h;`. So this is at least as strict as a raw-byte check, and still fail-closed.
- **Added conjunct (beyond the ruling's text, please confirm):** `<file>: LtePdcpHeader spelled across a line splice` fails when `joined` holds the name more times than the raw text. Without it, `LtePdcp\` + newline + `Header h;` in ordinary code was a false pass, with no literal involved.

**Fixtures** (the self-test now has 54 cases, all ok):
- Kept as must-fail: the ordinary, L and u8 Codex cases; a splice behind an escaped backslash; the macro continuation naming the name on line 2. All of them contain the name.
- Now must-pass: "a splice in a literal of a file without the name" (formerly "nothing forbidden nearby"), and a new CRLF splice in a char literal of a file without the name.
- Must-fail, given the name elsewhere so they keep their expectation: the CRLF splice, the char-literal splice, and the CRLF splice behind an escaped backslash.
- New must-fail:
  - the inverse case, "a splice, the name only in a comment elsewhere";
  - "the name spelled across a code splice";
  - "the name spelled across a splice in a literal" (fail-closed).

**Results:**
- `--dir ns-3-mmwave-oran` on the working tree: ok, 2799 files. The 3 lr-wpan files no longer trip, because they do not contain the name.
- lint.sh: exit 1, with exactly the 13 MC problems at the pin and 0 splice problems.
- Self-tests under `python3 -I` (n4-run-byte-identity, check-pdcp-volume-totals, ns3-source-lint): all ok.
- tools/e2-evidence/selftest.sh: exit 0.
- shellcheck and bash -n on scripts/gates: clean.

Status: DONE
Summary: The splice rule is narrowed to files whose phase-2 text holds LtePdcpHeader, which stays fail-closed with no scope change. The ns-3 working tree passes, and lint.sh is red only on the 13 MC problems at the pin.
Concerns: I added a conjunct the ruling did not name: the name spelled across a splice fails. Please confirm it.

---

## Source lint reads text as the compiler does (2026-11-07, second Codex follow-up)
The "spelled across a splice" check was confirmed, but it is now subsumed (see below). Codex found two more false passes, both compiler-confirmed:
- a `//` comment continued by a backslash-newline;
- CR-only line ends on the git read path.

Both are fixed by construction, not by special cases.

**(a) One normalize step.** `decode(bytes)` decodes as UTF-8 with replacement and then calls `normalize`, which turns CRLF and lone CR into LF. Both readers use `decode`: read_git (on the cat-file blob bytes) and read_dir (on `read_bytes()`). `lint()` calls `normalize` once more (it is idempotent) so that in-memory fixtures read exactly as the readers do.

**(b) Phase-2 splicing before lexing.**
- `phase2(text)` deletes every backslash-newline in a single pass over the original text. A backslash-newline that only appears after a deletion is kept, as the compiler keeps it.
- It returns the spliced text and a map from offset to original physical line, built from the kept segments plus a bisect over the original newlines.
- `strip_code` lexes the spliced text for comments, literals, prefixes, raw strings and pp-numbers.
- A count is the number of distinct original physical lines that hold a match start.
- **The one deliberate deviation is documented in `phase2`:** C++ reverts splices inside raw strings, and the lint does not. Lexing the spliced text can only end a raw string earlier, because a deleted backslash-newline cannot remove a `)delim"` terminator (it holds no backslash). So more text reaches the check: stricter, never a false pass. The fixture "code after a raw string ending behind a backslash-newline" fails as required.

**Checks dropped, and why.**
- **The literal-splice check:** with splicing done first, the lexer sees exactly the compiler's phase-2 text, so a splice can no longer move where a literal or comment ends unseen.
- **The "spelled across a line splice" check:** a name split by a splice is contiguous in the spliced text, so the `\bLtePdcpHeader\b` match itself finds it. Fixture "the name spelled across a code splice" still fails.
- Five fixtures were red only because of the dropped fail-closed rule. Spliced faithfully, nothing in them hides code, so they are now must-pass and renamed to say so ("… hides nothing", "the name only in a comment elsewhere", "the name spelled across a splice inside a literal is a string").
- Every fixture that does hide code is still must-fail: the ordinary, L and u8 Codex literal-splice cases, the splice behind an escaped backslash, and the macro continuation naming the name on line 2.

**Regression cases, each run in memory and through the git read path.** For the git path, the files are committed byte for byte (`core.autocrlf=false`, so CR is kept) and read back with read_git. Each case asserts the reported original line:

| Case | Want | Reported line |
|---|---|---|
| Codex continued-comment case: `// \` NL `/*` NL `LtePdcpHeader h;` NL `// */` | fail | [3] |
| CR-only comment end | fail | [2] |
| CR-only split identifier `LtePdcp\`CR`Header` | fail | [2] |
| CR-only literal splice | fail | [2] |
| A continued `//` comment without the name | pass | n/a |
| Macro continuation naming the name on line 2 | fail | [2] |
| Lines after two removed splices keep their number | fail | [5] |
| CR-only lines keep their number | fail | [4] |

The self-test now has 71 cases, all ok.

**Results:**
- `--dir ns-3-mmwave-oran` on the working tree: ok, 2799 files, in about 3.5 s.
- `--git` at the pin 4a0871d6: exactly the 13 MC problems. All 21 reported line numbers were checked against `git show <pin>:<path>`, and each physical line holds LtePdcpHeader (0 mismatches).
- lint.sh: exit 1, only from the ns-3 source rule at the pin (13 problems).
- Self-tests under `python3 -I` (n4-run-byte-identity, check-pdcp-volume-totals, ns3-source-lint): all ok.
- tools/e2-evidence/selftest.sh: exit 0.
- shellcheck and bash -n on scripts/gates: clean.

**Residual, recorded:** trigraphs (`??/` + newline as a splice) are not handled. ns-3.38 builds as C++17, where trigraphs are removed, and GCC ignores them by default in its gnu++ modes.

Status: DONE
Summary: Both readers now normalize line ends the same way, and the lint deletes backslash-newlines before lexing, mapping problems back to the original physical lines. Codex's continued-comment and CR-only cases are caught on both the in-memory and git paths. The two splice checks are dropped as redundant.
Concerns: none.

---

## Round: raw strings revert line splices (Codex HIGH at ns3-source-lint.py:95-100)

**Outcome:** the lint now follows the standard for raw strings. Phase 2 runs before raw-string recognition, so a raw opener can be formed across splices, but a splice inside a raw body is reverted. The old docstring paragraph claiming a "deliberate deviation, stricter, never a false pass" was false, and it is removed. Codex's repro now fails on the right line through both readers.

**Change (scripts/gates/ns3-source-lint.py, now 428 lines):**
- `phase2()` is now a small `Spliced` class:
  - `orig` holds the normalized original text and `text` the spliced text.
  - `to_orig(off)` maps a spliced offset to its original offset.
  - `to_spliced(o)` returns the first spliced offset whose original offset is ≥ o. If o falls inside a deleted backslash-newline, that is the start of the next segment.
  - `line_of(off)` returns the original physical line, as before.
  - The class docstring states the real rule.
- `strip_code(src)` still lexes `src.text`, so comments, ordinary literals and raw openers are all recognised after splicing. The raw-string branch works as follows:
  - It matches `R"delim(` on the spliced text.
  - The body starts at `to_orig(offset of "(") + 1`.
  - It finds the first `)delim"` in `src.orig` from there.
  - It maps the end of that terminator back with `to_spliced` and blanks the spliced span. If there is no terminator, it blanks to the end of the file, as before.
  - The output keeps the spliced length, so `line_of` still reports original physical lines.
- `lint()` uses `Spliced(normalize(t))`. Both readers share this path, as before.

**New regress fixtures.** Each runs in memory and through `read_git` on a temporary git repo, so 12 new self-test lines:

| case | expect |
|---|---|
| Codex repro `auto a = R"x()x\<NL>" R"y(<NL>)x";<NL>LtePdcpHeader h;<NL>auto b = R"y()y";` | fail, code lines [4] |
| raw body with a splice, then `)d"` on the next line, name after it | fail, code lines [2] |
| raw body with a splice, name only inside the body | pass |
| opener formed across a splice `R\<NL>"d(x)d";`, name on the next line | fail, code lines [3] |
| opener formed across a splice, name only inside the body | pass |
| delimiter formed across a splice `R"a\<NL>b(x)ab"; LtePdcpHeader h;` | fail, code lines [2] |

Both earlier raw fixtures still hold: "a splice in a raw string is no splice" passes, and "code after a raw string ending behind a backslash-newline" fails. To show the Codex fixture tells the two rules apart, I swapped in the old rule (search the spliced text) on the repro with its `class LtePdcpHeader {};` prefix. The old rule hits only line [1], which is the false pass. The new rule hits [1, 5].

**Verification (host only):**
- `ns3-source-lint.py --self-test`: ok, 83 cases (was 71).
- `n4-run-byte-identity.py --self-test` and `check-pdcp-volume-totals.py --self-test` (`-I`): rc 0.
- `tools/e2-evidence/selftest.sh`: rc 0.
- `shellcheck -x -e SC1090,SC1091,SC2046 -S warning` (lint.sh's flags) on the six touched shell files: rc 0. `bash -n` on the same files: clean.
- `scripts/gates/lint.sh`: rc 0, `lint: ok`. pins.conf NS3_SHA is 34b7f3cc, the ns-3 checkout HEAD is 34b7f3cc, and rung-config.json `pdcpHeaderSource` cites 34b7f3cc; none of these were touched.
- `--dir ns-3-mmwave-oran`: 2799 files, ok. `--git ns-3-mmwave-oran 34b7f3cc…`: 2799 files, ok.

Status: DONE
Summary: Raw-string bodies now revert line splices. The opener is recognised on the spliced text, the terminator is found in the original text, and its end is mapped back to the first spliced offset at or after it. Codex's repro and five related fixtures pass in memory and through git, and lint.sh is green at 34b7f3cc.
Concerns: none.

---

## Round: literal ud-suffixes (Codex MEDIUM at ns3-source-lint.py:165-171)

**Outcome:** a string or character literal closed by its quote now takes the identifier that immediately follows it as its ud-suffix. This applies to ordinary, prefixed and raw literals. Lexing resumes after the suffix, so a prefix-like suffix such as `R` or `u8` can no longer open a phantom literal. Codex's repro `auto a = R"(x)"R"("; LtePdcpHeader h; } //)"` now fails on line 1.

**Change (scripts/gates/ns3-source-lint.py, now 446 lines):**
- In `strip_code`, after any branch that blanks a literal, if the blanked span ends with a closing quote, `IDENT` (`[A-Za-z_][A-Za-z0-9_]*`) is matched right there and blanked with the literal. Comments are excluded: their spans start with `/`.
- An unclosed ordinary literal ends at its newline and an unclosed raw literal at end of file. Neither ends with a quote, so neither takes a suffix.
- The docstring now states the rule.

**Numeric ud-suffixes:** these were already covered. `PP_NUMBER` takes `[A-Za-z0-9_.]`, signed exponents and `'`-separators, so the whole token is one pp-number. `12_km`, `1.5e+3_x`, `0x1p-3_q`, `1uR` and `1'000_ms` each match in full. The `1uR` case is pinned by a fixture: a lexer that split the number would read `uR"(` as a raw opener.

**New regress fixtures.** Each runs in memory and through `read_git`, so 12 new self-test lines:

| case | expect |
|---|---|
| Codex repro `R"(x)"R"("; LtePdcpHeader h; } //)"` | fail, code lines [1] |
| ordinary `"x"R"(...` | fail, code lines [1] |
| char `'x'R"(...` | fail, code lines [1] |
| prefixed `u8"x"R"(...` | fail, code lines [1] |
| pp-number `1uR"(...` | fail, code lines [1] |
| `auto s = "abc"_sv; int y = 1;` | pass |

**Discrimination check:** I loaded a copy of the lint with the suffix step disabled and ran it on the four literal fixtures. It reports no hit on any of them (the false pass). The fixed lint hits line [1] on each.

**Verification (host only):**
- `ns3-source-lint.py --self-test`: ok, 95 cases (was 83).
- `n4-run-byte-identity.py --self-test` and `check-pdcp-volume-totals.py --self-test` (`-I`): rc 0.
- `tools/e2-evidence/selftest.sh`: rc 0.
- `shellcheck -x -e SC1090,SC1091,SC2046 -S warning` on the six touched shell files: rc 0. `bash -n` on the same files: clean.
- `lint.sh`: rc 0, `lint: ok`.
- `--dir ns-3-mmwave-oran` and `--git ns-3-mmwave-oran <pins NS3_SHA = 34b7f3cc>`: 2799 files each, ok.
- pins.conf, rung-config.json and p10-gate-chain.sh are untouched in this round.

Status: DONE
Summary: A closed string or character literal now takes its following identifier as its ud-suffix, so `"x"R"(` and its variants no longer open a phantom raw string. Numeric suffixes were already whole pp-numbers. The six new fixtures pass in memory and through git, and lint.sh is green.
Concerns: none.

---

## Round: whitespace before a line splice (Codex MEDIUM at ns3-source-lint.py:30)

**Outcome:** the lint now recognises a backslash, then horizontal whitespace, then a newline as a line splice, as GCC does. Codex's repro `// \ <NL>/*<NL>LtePdcpHeader h;<NL>// */` now fails on line 3. I checked GCC's side with a local g++: `-std=c++17 -fsyntax-only` accepts the same shape with `int h;` in place of the name, so the splice continued the comment and the declaration survives.

**Change (scripts/gates/ns3-source-lint.py, now 459 lines):**
- `SPLICE = re.compile(r"\\[ \t\f\v]*\n")`, with a comment citing GCC's behaviour and its "backslash and newline separated by space" warning.
- The module docstring and the `Spliced` docstring now describe a splice as a backslash, optional horizontal whitespace, then a newline.
- The raw-string terminator search still runs on the original text.

**Longer matches:** `Spliced` only uses `m.start()` and `m.end()`, so the segment maps take a match of any length. I checked them directly on `ab\    <NL>cd<NL>x`:
- The spliced text is `abcd<NL>x`.
- `to_orig` gives [0, 1, 8, 9, 10, 11].
- `to_spliced` maps every original offset inside the deleted 6-character splice to 2, the next kept character.
- `line_of` gives [1, 1, 2, 2, 2, 3].

**New regress fixtures.** Each runs in memory and through `read_git`, so 12 new self-test lines:

| case | expect |
|---|---|
| Codex repro, backslash-space-newline | fail, code lines [3] |
| same with a tab | fail, code lines [3] |
| same with four spaces | fail, code lines [3] |
| `LtePdcp\ <NL>Header h;` | fail, code lines [2] |
| `auto s = "a\ <NL>"; LtePdcpHeader h;` | fail, code lines [2] |
| backslash, spaces, then text (in a comment, and inside a literal holding the name) | pass |

**Discrimination check:** a copy of the lint with the old `\\\n` SPLICE finds no hit on any of the five must-fail fixtures. The new rule hits the expected line on each.

**ns-3 tree:** `git grep -P '\\[ \t\f\v]+$'` at 34b7f3cc over src/, scratch/ and contrib/ *.h/*.cc finds 0 lines, so no real file is affected.

**Verification (host only):**
- `ns3-source-lint.py --self-test`: ok, 107 cases (was 95).
- `n4-run-byte-identity.py --self-test` and `check-pdcp-volume-totals.py --self-test` (`-I`): rc 0.
- `selftest.sh`: rc 0.
- `shellcheck -S warning` (lint.sh's flags) on the six touched shell files: rc 0. `bash -n` on the same files: clean.
- `lint.sh`: rc 0, `lint: ok`.
- `--dir` and `--git` at the pinned 34b7f3cc: 2799 files each, ok.
- pins.conf, rung-config.json and the driver are untouched.

Status: DONE
Summary: SPLICE now also matches a backslash followed by horizontal whitespace before the newline, as GCC does. The offset maps handle the longer matches, and the six new fixtures pass in memory and through git. No file in ns-3 has such a splice, and lint.sh is green.
Concerns: none.

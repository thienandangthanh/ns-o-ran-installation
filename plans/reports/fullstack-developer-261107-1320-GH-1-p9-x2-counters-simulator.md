# P9 simulator side: en-gNB X2 PDCP SDU volume counters (host only)

Status: DONE_WITH_CONCERNS. Nothing is committed or pushed, and the VM was not touched. Everything is uncommitted in the three fork working trees, plus the evidence dir named below.

## Outcome

- ns-3 builds on the host. The new suite passes, and so do the three existing suites.
- The mutation turns case (b) red.
- scenario-zero ulon prints a well-formed audit v2.
- Per report window, the gNB IPC X2 values equal the audit's x2dl/x2ul lines exactly (100/100 windows, both cells, both directions).
- uloff prints no N4AUDIT line.
- Every ns3run trace is byte-equal to P7fix, in both configs (row 149 facts unchanged).
- KPM golden regenerated: header and UE pieces are identical, and each cell piece gains two appended items (decode-diffed with asn1-indep).
- **The metric-map lint is not at 0 findings, by design.**
  - The source refs carry the `@UNCOMMITTED` placeholder, which fails SOURCE_REF on purpose.
  - With a dummy sha, the one remaining finding is the X2DL value check: it holds false because of the open Q-2 gap.
  - See "Q-2 handling" below.

## Changed files

### ns-3-mmwave-oran (base 4318e43b, branch dev/l-release-nist180)

- `src/lte/model/epc-x2.h`: new typedef `McPdcpPduTracedCallback(localCellId, remoteCellId, gtpTeid, pduBytes)` and members `m_mcDlPdcpPduRx`, `m_mcUlPdcpPduTx`.
- `src/lte/model/epc-x2.cc`: new trace sources `McDlPdcpPduRx` and `McUlPdcpPduTx`.
  - DL fires in RecvFromX2uSocket after RemoveHeader(gtpu), for McForwardDownlinkData, before the forward-map test (:652-660).
  - UL fires in DoReceiveMcPdcpSdu before the GTP-U header is added (:1302-1307).
- `src/lte/model/mc-enb-pdcp.h/.cc`: new traces `TxPduLeg` (rnti, lcid, bytes, leg) and `RxPduLeg` (rnti, lcid, bytes, delayNs, leg), with a shared `ReceivePdu(p, legCellId)`.
  - TxPduLeg fires with leg 0 on the LTE leg, and with targetCellId on the X2 leg before SendMcPdcpPdu.
  - RxPduLeg uses leg 0 for the local RLC and sourceCellId for DoReceiveMcPdcpPdu.
  - The TxPDU and RxPDU signatures are unchanged.
- `src/mmwave/model/mmwave-enb-net-device.h/.cc`:
  - New `ConnectX2PdcpPduCounters()`, `CountX2DlPdcpPdu`/`CountX2UlPdcpPdu` (counted only when localCellId == m_cellId), and four uint64 counters.
  - X2 kbit = (8×(bytes−H×pdus)+500)/1000, with H = `McEnbPdcp::DataPduHeader().GetSerializedSize()`. The counters are reset at every CU-UP read, in every mode.
  - `FillCuUpValues(plmId, 0, 0, x2Ul, x2Dl)`. The MN-hosted UL/DL sums are removed.
  - The report aborts if an en-gNB UE context holds a DRB PDCP entity.
  - The per-UE loop, the stats calculators and the reset are untouched. No RandomVariable and no new event.
- `scratch/scenario-zero.cc`: audit v2.
  - Header `N4AUDIT v2 hdr=<H> class=<C>`; dltx/ulrx carry a trailing leg.
  - x2dl/x2ul lines come from `Config::ConnectFailSafe("/NodeList/*/$ns3::EpcX2/McDlPdcpPduRx"|"McUlPdcpPduTx")` and abort on false. The nodeId is parsed from the context, which aborts unless it starts with /NodeList.
  - ConnectUe connects RxPduLeg/TxPduLeg and aborts unless the entity is an McEnbPdcp.
  - Grammar doc block updated. ulon only, as today.
- `src/lte/test/lte-test-epc-x2-mc-pdcp-volume.cc` (new, 448 lines): suite `epc-x2-mc-pdcp-volume`, UNIT, 5 QUICK cases (a)–(e).
  - Three nodes on real EpcX2 over p2p, with user stubs for every receiving TEID. Any unexpected SAP primitive is recorded as a failure.
  - Each case checks the exact ordered list of trace events (node, dir, local, remote, teid, bytes) and the deliveries.
- `src/lte/CMakeLists.txt`: registers the suite.

### oran-interface (base 53253fe2)

- `helper/mmwave-indication-message-helper.h/.cc`: `FillCuUpValues(plmId, ul, dl, x2Ul, x2Dl)` adds `AddCellValue<long>("DRB.PdcpSduVolumeX2UL"/"X2DL")` (:59-60). No overload. The ns-3 caller is updated.

### O-RAN-Testbed-Automation (base 254027ca), ns3_e2_agent/

- `schema/metric-map.v1.json`:
  - Rows 34/35 are kept, with pendingFix dropped and an origin that names the constant 0 (37.340 §4.2.2, plus the abort line).
  - Appended order/measId 36 `DRB.PdcpSduVolumeX2UL` (§5.1.2.1.2.2) and 37 `DRB.PdcpSduVolumeX2DL` (§5.1.2.1.1.2): INTEGER, sample, Kbit, PDCP, legacyName null.
  - The pendingFix doc line is removed.
- `schema/kpm-measurement-clauses.v1.json`:
  - DRB.PdcpSduVolumeUL/DL checks: holds true, gaps [], maxValue 0, new reason, reAudit (SN-terminated bearer).
  - New entries X2UL and X2DL. Page numbers re-verified with pdftotext on Zotero RMU9VRW7: V20.2.0 pp.183-184 / 185-186, item a)/c)/e)/f). Annex A.25 is p.403. V17.17.0 (WJPE6SBD): `_Filter` form only, PLMN+QoS filter. The doc lines are updated.
- `tests/lint-metric-map.py`: removed PENDING_ALLOWED, VALUE, matched_check, `--require-no-pending`, the XFAIL print and `pendingExpectedFailures`. Rule (8) is now "a row that carries pendingFix is a finding". No caller used the removed flag (git grep over the superproject and Testbed).
- `tests/lint-metric-map-selftest.py`:
  - Pending fixtures replaced by "row carrying pendingFix fails", on the DL row, the passing control and an ns3 row.
  - The decoy fixtures now use a per-row `(PASS, tag)` want.
  - New X2UL/X2DL Mbit-unit fixtures; row-index texts updated (93→95, 118→120).
  - The shipped-map case requires 0 findings.
- `tests/fixtures/kpm-tt-golden-gnb2-seq26-35.txt`: the 10 cell pieces are regenerated, with 3 comment lines added. The hdr and ue pieces are unchanged.

### Superproject

- `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/p10-p9/suite-mutation/`, created per the brief: `mutation.diff`, `mutated-suite-verbose.txt`, `green-suite-verbose.txt`.
- This report.

## Test outputs

Build: an out-of-tree copy at `/home/andang/ns3-p9-910ba118/ns-3` (rsync of the working tree plus `contrib/oran-interface`). The configure line is P7's. `./ns3 build test-runner scenario-zero` rc=0, with no new warnings in the touched files; the two -Wunused warnings at device .cc:692/710 are pre-existing.

```
PASS epc-x2-mc-pdcp-volume 0.008 s
  PASS master eNB to en-gNB: one DL event at the en-gNB
  PASS master eNB to an en-gNB that forwards the TEID: one DL event at each en-gNB
  PASS en-gNB RLC buffer PDU to another en-gNB: one DL event at the target
  PASS en-gNB RLC to the master eNB PDCP: one UL event at the en-gNB
  PASS untyped UE data to an en-gNB: no event
test.py: epc-x2-mc-pdcp-volume, mc-pdcp-nr-header, pdcp-sn-wrap, mmwave-neighbour-list: each 1 of 1 passed
also: epc-gtpu, epc-s1u-downlink, epc-s1u-uplink, lte-epc-e2e-data, lte-x2-handover-measures, mmwave-attachment-test: PASS
lte-x2-handover: CRASH "UE manager for RNTI 1 not found" lte-enb-rrc.cc:3329. This is pre-existing, the same line as at base in the P7 report.
```

Mutation: the DL hook was moved inside the not-forwarded branch, in the build copy only, then reverted.

```
FAIL master eNB to an en-gNB that forwards the TEID: one DL event at each en-gNB
  actual="[node 2 dl local 3 remote 2 teid 7 bytes 1310]"
  limit="[node 1 dl local 2 remote 1 teid 7 bytes 1310][node 2 dl local 3 remote 2 teid 7 bytes 1310]"
exit=1    (the restored tree's epc-x2.cc is byte-equal to the working tree; green again, exit=0)
```

Row 148 source lint: `ns3-source-lint.py --dir ns-3-mmwave-oran` gives "2800 files, ok", and `--self-test` is ok. The `--dir` form is the one the tool documents for a look at uncommitted work, not a gate. The gate form, `--git REPO SHA`, needs the commit.

scenario-zero, host (P7's `n4-host-run.sh`, `--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1`):

- **uloff:** exit 0, manifest preconditions ok, 0 N4AUDIT lines.
  - gNB cells 2 and 3 carry all four keys in 100/100 samples. UL/DL are always 0, X2UL is 0, and X2DL sums are 410774 and 204413 kbit.
- **ulon:** exit 0, preconditions ok.
  - Header `N4AUDIT v2 hdr=2 class=ns3::NrPdcpHeader` (line 1) and `N4AUDIT end connected=6 present=6 missing=0`.
  - Line counts: dltx 117600 (leg 0: 58748, leg≠0: 58852), ulrx 6194 (all leg≠0), x2dl 58852, x2ul 6194. All 188842 lines match their form (0 malformed).
  - In every window and both cells, IPC X2DL/X2UL equals (8×(Σbytes−2×n)+500)/1000 over the audit's x2 lines of the window (100/100 each).
  - Cell 2: 39295 DL events and 3844 UL events. Cell 3: 19557 DL and 2350 UL.
- **Against P7fix** (`n4-run-byte-identity.py compare`, 37 items):
  - uloff differs only in `e2-ipc-trace-2/3.jsonl:samples`.
  - ulon differs in those two plus `stdout:audit-header` and `stdout:body`.
  - All ns3run/* traces are equal, including DlE2PdcpStats.
  - The ulon body with the x2 lines and leg tokens stripped is sha-equal to the P7fix v1 body (123795 lines).

Lint (`python3 -I tests/lint-metric-map.py schema/metric-map.v1.json --kpimon-enb ../install_patch_files/xApps/kpimon-go/control/enb-kpm-measurements.json`, then `--self-test`):

| tree | lint | self-test |
|---|---|---|
| working tree (`@UNCOMMITTED`) | 5 findings: 4 SOURCE_REF on entries 7-10, plus "registry has findings: clause checks skipped"; rc 1 | 67 ok / 71 FAIL; registry findings skip every clause fixture |
| copy, placeholder → dummy sha | 1 finding: `gnb/cell/37/DRB.PdcpSduVolumeX2DL: value check: value check fails: ...`; rc 1 | 136 ok / 2 FAIL (`shipped-map-and-registry: 1 findings`, `cli-shipped-map-with-kpimon-enb`) |
| copy, dummy sha + gap hypothetically resolved (holds true, gaps []) | 0 findings; rc 0 | 138 ok, self-test ok |
| copy, holds true but gap kept | the registry rejects it: "a value check with gaps ... cannot hold" | n/a |

KPM golden. The tool was the image `localhost/ns3-e2-agent:dev-style5` (`kpm-report-period-test <map> <fixtures> <out>`, `--entrypoint sh`).

- The image's `tests/kpm-report-period-test.cpp`, its fixtures and the old golden are byte-equal to the pin.
- Its `src/` differs from the pin only in `e2-node-identity.{cpp,hpp}` (X2 setup ARFCN constants, not on the KPM encode path).
- Old map: 82 PASS / 0 FAIL, `tt-byte-identical: 35/35`.
- New map against the old golden: `25/35`; all 10 hdr and 15 ue pieces are the same, and the 10 cell pieces grow by 15 octets each.
- New map against the new golden: 82 PASS, `tt-byte-identical: 35/35`.
- k20 worst-case cell: 1996 → 2011 octets, still ≤ 7000.
- Decode diff (`localhost/asn1-indep:09aeabb8b0f99b0c`, the tag of the current tools/asn1-indep sources) covers 25 pieces, 0 bad:
  - every header decodes equal;
  - every UE message decodes equal;
  - each cell message has items 35→37, the first 35 equal, and `id:36`, `id:37` appended with records `noValue, noValue` (the fixture samples carry no X2 keys).

Evidence outside the repo is in `/home/andang/ns3-p9-910ba118/evidence/`:

- the check outputs and cmp JSONs;
- golden/ (ind-lines old/new, decode-diff.py and its output, kpm test outputs);
- the self-test outputs;
- the one-off map/registry editor script.

The run dirs are in `/home/andang/ns3-p9-910ba118/runs/`. The tree is 1.8 GB; /home has 41 GB free. Remove it with `rm -rf /home/andang/ns3-p9-910ba118` once archived.

## Deviations from counsel, and why

1. **EpcX2 subscription point.**
   - Counsel: subscribe "where the CU-UP report is enabled", which means UpdateConfig/DoInitialize. That aborted at t=0 (`cell 2: the CU-UP report needs an EpcX2 on the node`), because MmWaveHelper calls `device->Initialize()` (mmwave-helper.cc:2227) before `AddEnb` aggregates EpcX2 (:2242, epc-helper :363-365).
   - Now: `ConnectX2PdcpPduCounters()` runs once, inside the first CU-UP report (800 µs, an existing event). It aborts if EpcX2 is absent, if a connection fails, or if the cell already holds a UE context. An X2-U MC PDU of a cell needs a UE context there, so no PDU can precede the connection.
   - No new event and no helper edit.
2. `NS_ABORT_MSG_IF` replaces counsel's NS_ASSERT for bytes < H×pdus, so the check also holds in optimized builds.
3. **Q-2 split by direction.** X2DL holds false with the UM-tail gap; X2UL holds true with gaps []. The tail exists only on the DL S-SN RLC-buffer forward. UL X2 PDUs are re-wrapped PDCP PDUs leaving through ReceiveMcPdcpSdu (lte-rlc-um.cc:1130, -um-lowlat.cc:1322, -am.cc:2816 @4318e43b).
4. **Source refs use the `ns-3-mmwave-oran@UNCOMMITTED` / `oran-interface@UNCOMMITTED` placeholder**, with working-tree line numbers (the commits do not exist). After committing both forks unchanged, run:
   `sed -i 's/ns-3-mmwave-oran@UNCOMMITTED/ns-3-mmwave-oran@<sha8>/g; s/oran-interface@UNCOMMITTED/oran-interface@<sha8>/g' schema/metric-map.v1.json schema/kpm-measurement-clauses.v1.json`
   Any further edit to the cited files invalidates the line numbers: re-run `/home/andang/ns3-p9-910ba118/evidence/update-map-registry.py` on a checkout of HEAD's two schema files.
5. **X2DL int32 bound.**
   - Counsel's basis is (X2 links into the cell) × 100 Gb/s × period / 1000. Applied honestly it is nMmWaveEnbNodes × 2e8 kbit, because scenario-zero links all pairs (mmwave-helper.cc:2922-2972).
   - That is ≤ 2e9 only for nMmWaveEnbNodes ≤ 10, while scenario-zero accepts up to 85 (scenario-zero.cc:357-360).
   - Recorded in maxValueBasis, with "nMmWaveEnbNodes > 10" added to reAudit. X2UL has one link, so 2e8.
6. scenario-zero.cc keeps its GNU style. clang-format was applied only to the added lines of the other ns-3 files. The pre-existing unsorted includes in mmwave-enb-net-device.cc were left as they are.
7. Self-test: the decoy cases assert per-row PASS instead of a whole-map pass, so they stay meaningful while the shipped map carries the X2DL finding.
8. The X2 entries set `legacyName {map: null, v17: null}`. V17 only has the `_Filter` form, which is a form rather than a legacy name.

## Q-2 registry handling (forwarded RLC UM tail)

- Recorded as one `gaps` item on the X2DL value check (`holds: false`). It cites the S-SN forward (lte-enb-rrc.cc:905,939), the UM-lowlat tail (:258-282) and the D/C test (lte-rlc-forwarding-buffer.cc:190-194), and states the error as 16 bits low per forwarded tail.
- No exception or waiver was invented.
- Effect:
  - The lint reports the X2DL row as a "value check fails" finding, exit 1.
  - The self-test fails its two shipped-map cases.
  - `scripts/gates/lint.sh:58`, `install_xapp_kpi_monitor.sh:193` and `install_ns3_e2_agent.sh:48` all run the lint, so all three stop until the user rules on a remedy and the gap is removed.
- Shown above: with the gap resolved the map is at 0 findings and the self-test passes 138/138.

## Unresolved questions

1. The Q-2 remedy (the user's call). Until it is ruled, the strict lint, lint.sh and both install scripts fail on X2DL.
2. Should the X2DL int32 bound for nMmWaveEnbNodes 11..85 get a tighter basis (for example the master eNB's S1-U input of 10 Gb/s plus forwarded buffers), or should the scenario cap the node count?
3. Is the lazy EpcX2 connection at the first CU-UP report acceptable, or is a helper-side connect after AddEnb preferred? The latter would touch mmwave-helper.cc and add a public device method.
4. The kpimon gNB-side handling of the new cell measIds 36/37 was not checked; it is outside this brief.
5. The golden was produced with the dev-style5 image binary, whose KPM sources equal the pin. Re-run `kpm-report-period-test` once the agent image is rebuilt from the P9 commit.

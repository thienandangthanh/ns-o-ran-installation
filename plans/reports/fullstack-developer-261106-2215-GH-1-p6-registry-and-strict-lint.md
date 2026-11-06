# P6 draft: 3GPP clause registry, strict metric-map lint, in-place renames

Date 2026-11-06. Draft only: nothing committed or pushed, no VM touched, no gate run except offline self-tests and `scripts/gates/lint.sh`. Testbed base `163ef25`; ns-3 sources cited at `ea6e46f6`, oran-interface at `53253fe`.

## Result

- The shipped map passes the strict lint with 0 findings. The two en-gNB P9 rows (cell :56-57 at HEAD) are reported as XFAIL. `--self-test` passes: the shipped pair plus 35 must-fail fixtures. `lint.sh` exits 0.
- After the independent read (kongming, see below), the en-gNB keeps **no** passing 3GPP-named row. The only 3GPP names left are the eNB `RRC.ConnMean` (passes) and the two pending P9 rows. Three outcomes differ from what the user was shown, and one new rule needs a user ruling (R1). See "Rulings needed".

## Files changed (all uncommitted)

Testbed `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/`:

| File | Change |
|---|---|
| `ns3_e2_agent/schema/kpm-measurement-clauses.v1.json` | new, 237 lines: the registry |
| `ns3_e2_agent/tests/kpm-clause-registry.py` | new, 155 lines: loader, registry validator, name grammar, vendor-name rule |
| `ns3_e2_agent/tests/lint-metric-map.py` | 161 → 293 lines: every old check kept verbatim, plus conjuncts (1)–(8), `--registry`, `--require-no-pending`, `--self-test` |
| `ns3_e2_agent/tests/lint-metric-map-selftest.py` | new, 149 lines: the fixtures |
| `ns3_e2_agent/schema/metric-map.v1.json` | 68 rows renamed or re-united in place; `clause` and `layer` on all 118 rows; `pendingFix: "P9"` on gnb cell 34/35; `doc` header updated |
| `install_patch_files/xApps/kpimon-go/control/enb-kpm-measurements.json` | regenerated from the map's eNB rows (9 renames) |

Superproject:

| File | Change |
|---|---|
| `scripts/gates/kpimon.sh:35-39` | `KPIMON_TESTBED_PATHS` gains the registry and `kpm-clause-registry.py` (the installer's lint reads both) |
| `scripts/gates/kpimon-guard-selftest.sh` | registry and module stubs in the scratch Testbed; new must-fail fixtures `clause-registry-edit` and `registry-module-edit`. This adds checks and removes none. |
| `scripts/gates/lint.sh:50` | runs `lint-metric-map.py --self-test` |

`lint.sh` also carries another session's uncommitted line for `check-ipc-neighbour-lists.py`, plus the `M` files `build-ns3.sh`, `gate-m4-ns3-build.sh` and `ts-rung-lib.sh` and the `ns-3-mmwave-oran` submodule. None of these is mine and I left all of them untouched.

## Pre-change measurement (new lint, HEAD map)

- `python3 -I tests/lint-metric-map.py <HEAD map>` exits 1 with 337 findings. **All 118 rows fail**, through conjunct (1): no row has `clause` or `layer`.
- **68 rows also fail at least one other conjunct.** The list below is from the final lint; with the first draft (case-sensitive name rule, gNB `RRC.ConnMean` not DC-excluded, TB checks holding) the count was 67.
- Lines are HEAD `metric-map.v1.json` lines.

| HEAD line | Row | Name | Conjuncts failed beyond (1) |
|---|---|---|---|
| 26 | gnb/cell/4 | TB.TotNbrDl.1 | (3) unit, (4) grammar (MU-MIMO label), value check |
| 27 | gnb/cell/5 | TB.TotNbrDlInitial | (3) unit, value check |
| 28-30 | gnb/cell/6-8 | TB.TotNbrDlInitial.Qpsk/16Qam/64Qam | (3) unit, value check |
| 31 | gnb/cell/9 | RRU.PrbUsedDl | (2) registry |
| 32 | gnb/cell/10 | TB.ErrTotalNbrDl.1 | (2) registry |
| 33 | gnb/cell/11 | QosFlow.PdcpPduVolumeDL | (3) layer, node (split-only, DC-excluded), type, unit; value check |
| 34-39 | gnb/cell/12-17 | CARR.PDSCHMCSDist.Bin1-6 | (2) registry |
| 40-46 | gnb/cell/18-24 | L1M.RS-SINR.Bin34…Bin127 | (2) registry |
| 47 | gnb/cell/25 | DRB.BufferSize.Qos | (2) registry |
| 48 | gnb/cell/26 | DRB.MeanActiveUeDl | (2) registry |
| 49-50 | gnb/cell/27-28 | RRU.PrbAvailDl/Ul | (2) registry |
| 51 | gnb/cell/29 | RRU.PrbTotDl | (2) registry (V17-only; successor RRU.PrbDl named) |
| 52 | gnb/cell/30 | RRU.PrbTotUl | (2) registry |
| 53 | gnb/cell/31 | ns3.du.qci | (6) vendor (placeholder QCI) |
| 55 | gnb/cell/33 | RRC.ConnMean | (3) node (DC-excluded), (3) unit, value check |
| 56-57 | gnb/cell/34-35 | DRB.PdcpSduVolumeUL/DL | (3) unit, value check |
| 62 | gnb/ue/5 | TB.TotNbrDl.1 | (3) per-UE, unit, (4) grammar, value check |
| 63-66 | gnb/ue/6-9 | TB.TotNbrDlInitial(.Qpsk/.16Qam/.64Qam) | (3) per-UE, unit, value check |
| 67 | gnb/ue/10 | TB.ErrTotalNbrDl.1 | (2) registry |
| 68 | gnb/ue/11 | ns3.du.QosFlow.PdcpPduVolumeDL | (6) vendor (family QosFlow) |
| 69 | gnb/ue/12 | RRU.PrbUsedDl | (2) registry |
| 70-82 | gnb/ue/13-25 | CARR / L1M bins | (2) registry |
| 83 | gnb/ue/26 | DRB.BufferSize.Qos | (2) registry |
| 84 | gnb/ue/27 | DRB.UEThpDl | (2) registry |
| 85 | gnb/ue/28 | QosFlow.PdcpPduVolumeDL | (3) node, type, unit; value check |
| 86 | gnb/ue/29 | DRB.PdcpPduNbrDl.Qos | (2) registry |
| 87 | gnb/ue/30 | DRB.EstabSucc.5QI | (4) grammar (5QI label), value check |
| 88 | gnb/ue/31 | DRB.RelActNbr.5QI | (2) registry |
| 119 | enb/cell/4 | DRB.PdcpSduDelayDl | (2) registry |
| 123 | enb/cell/8 | RRC.ConnMean | (3) unit ('UEs' != 'count') |
| 128-131 | enb/ue/5-8 | DRB.PdcpSduVolumeDl, Tot.PdcpSduNbrDl, DRB.PdcpSduBitRateDl, DRB.PdcpSduDelayDl | (2) registry |
| 134 | enb/ue/11 | QosFlow.PdcpPduVolumeDL | (2) registry, (3) node |
| 135-137 | enb/ue/12-14 | DRB.PdcpPduNbrDl.Qos, DRB.EstabSucc.5QI, DRB.RelActNbr.5QI | (2) registry |

The raw output is saved at `/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/910ba118-28cd-4264-b831-5fa1b4929edd/scratchpad/premap/lint-out-final.txt`.

## Renames

- Every rename keeps its order and measId. A script checked that no field other than kpm, unit, clause, layer and pendingFix changed.
- No row moves to a successor name; each failing row gets an `ns3.<section>.<name>` name instead.
- Each name is ns-3's own variable name where one exists. Each is checked case-insensitively against the 3GPP families and placeholders.
- The same name is used in the cell and UE lists. They land in different Influx measurements, so there is no clash.

| Rows (kind/list/order) | Old → new | Reason |
|---|---|---|
| gnb cell 4, ue 5 | TB.TotNbrDl.1 → ns3.du.macPdu | `.1` is a MU-MIMO layer label (L2). Cell: the value check fails on two SN-change paths that drop TBs (kongming items 1–2, rule R1). UE: KPM 7.9 has no per-UE TB type (L4). |
| gnb cell 5, ue 6 | TB.TotNbrDlInitial → ns3.du.macPduInitial | Same value-check failure; UE: L4 |
| gnb cell 6-8, ue 7-9 | TB.TotNbrDlInitial.Qpsk/16Qam/64Qam → ns3.du.macPduQpsk/16Qam/64Qam | They count every TB, not only initial ones (`mmwave-phy-trace.cc:264-278`); no value check exists |
| gnb cell 9, ue 12 | RRU.PrbUsedDl → ns3.du.macPrb (unit "PRB (139-PRB scale)") | Not a 28.552 V20.2.0 name |
| gnb cell 10, ue 10 | TB.ErrTotalNbrDl.1 → ns3.du.macPduRetx | Not a V20.2.0 name (the clause has TB.ErrTotNbrDl.X, NACK/DTX); the value is retransmissions |
| gnb cell 11 | QosFlow.PdcpPduVolumeDL → ns3.du.macVolume | Split-only, DC-excluded, MAC source under a PDCP clause, REAL |
| gnb ue 11 | ns3.du.QosFlow.PdcpPduVolumeDL → ns3.du.macVolume | (6) reuses the QosFlow family |
| gnb cell 12-17, ue 13-18 | CARR.PDSCHMCSDist.Bin1-6 → ns3.du.macPduMcs0to4 … Mcs25to29 | No registry entry; a Bin suffix is a KPM distribution label |
| gnb cell 18-24, ue 19-25 | L1M.RS-SINR.Bin34…127 → ns3.du.macPduSinrUpToMinus6dB, SinrMinus6To0dB, Sinr0To6dB, Sinr6To12dB, Sinr12To18dB, Sinr18To24dB, SinrAbove24dB | No registry entry; the bins are ns-3's dB thresholds (`mmwave-phy-trace.cc:305-333`) |
| gnb cell 25, ue 26 | DRB.BufferSize.Qos → ns3.du.rlcBufferOccup | No entry; QoS placeholder |
| gnb cell 26 | DRB.MeanActiveUeDl → ns3.du.numActiveUes | Value is a report-instant UE-map size, not a mean of active UEs (kongming agrees) |
| gnb cell 27/28 | RRU.PrbAvailDl/Ul → ns3.du.dlAvailablePrbs / ulAvailablePrbs (unit "PRB (constant 139)") | Not a V20.2.0 name |
| gnb cell 29 | RRU.PrbTotDl → ns3.du.dlPrbUsage | V17-only; its successor RRU.PrbDl's value check fails (PRB ruling, successor rule) |
| gnb cell 30 | RRU.PrbTotUl → ns3.du.ulPrbUsage (unit "% (constant 0)") | V17-only; the value is a constant 0 TODO (`mmwave-enb-net-device.cc:1376`) |
| gnb cell 31 | ns3.du.qci → ns3.du.prbReportClassId | Case-insensitive (6): `qci` is the QCI placeholder (kongming item 7) |
| gnb cell 33 | RRC.ConnMean → ns3.cuCp.meanRrcUes | 28.552 §1 p.28 excludes RRC-connection measurements from EN-DC (kongming item 3) |
| gnb cell 34/35 | kept; unit kbit/period → Kbit; `pendingFix: P9` | Expected failure until P9 |
| gnb ue 27 | DRB.UEThpDl → ns3.du.rlcPduSizeOverDelayDl | The value is mean RLC PDU size / mean RLC delay (`mmwave-enb-net-device.cc:795-805`), not ThpVolDl/ThpTimeDl. This conflicts with the L4 ruling text (see R2). |
| gnb ue 28 | QosFlow.PdcpPduVolumeDL → ns3.cuUp.txPdcpPduBytesNrRlc (unit → kbit/period) | Split-only, DC-excluded, REAL. The unit text was wrong: the value is kbit (`:710-725`). |
| gnb ue 29 | DRB.PdcpPduNbrDl.Qos → ns3.cuUp.txPdcpPduNrRlc | No entry; QoS placeholder |
| gnb ue 30 | DRB.EstabSucc.5QI → ns3.cuCp.numDrb | 5QI label (L2); the clause has no total; the value is a DRB count, not setups |
| gnb ue 31 | DRB.RelActNbr.5QI → ns3.cuCp.numDrbRelAct (unit "count (constant 0)") | No entry; constant 0 (`:1034-1036`) |
| enb cell 4 | DRB.PdcpSduDelayDl → ns3.cuUp.cellAverageLatency (unit ms → 0.1 ms) | No 32.425 V19.0.0 entry. The unit text was wrong: /1e5 gives 0.1 ms (`lte-enb-net-device.cc:1164,1215-1218`). |
| enb cell 8 | kept; unit UEs → count | Holds |
| enb ue 5 | DRB.PdcpSduVolumeDl → ns3.cuUp.pdcpTxVolumeDl (unit bytes/period → kbit/period) | No entry. The unit text was wrong: kbit (`:1110-1111`). |
| enb ue 6 | Tot.PdcpSduNbrDl → ns3.cuUp.txDlPackets | Not a 32.425 name |
| enb ue 7 | DRB.PdcpSduBitRateDl → ns3.cuUp.pdcpThroughput (kbit/s) | No entry (`:1167`) |
| enb ue 8 | DRB.PdcpSduDelayDl → ns3.cuUp.pdcpLatency (unit ms → 0.1 ms) | No entry; the unit text was wrong (`:1164`) |
| enb ue 11 | QosFlow.PdcpPduVolumeDL → ns3.cuUp.txPdcpPduBytesNrRlc (unit → kbit/period) | NR clause on an eNB; DC-excluded |
| enb ue 12 | DRB.PdcpPduNbrDl.Qos → ns3.cuUp.txPdcpPduNrRlc | No entry |
| enb ue 13 | DRB.EstabSucc.5QI → ns3.cuCp.numDrb | No 32.425 entry |
| enb ue 14 | DRB.RelActNbr.5QI → ns3.cuCp.numDrbRelAct (constant 0) | No entry |

Layers:
- `none`: the ns3 identity rows.
- PHY: the SINR bins.
- MAC: TB/PDU counts, PRB values, macVolume, prbReportClassId.
- RLC: rlcBufferOccup, rlcPduSizeOverDelayDl, the gNB `txPdcpPduBytesNrRlc` (NR RLC kbit), and the LteRlc rows.
- PDCP: the cuUp PDCP rows and the eNB `txPdcpPduBytesNrRlc`.
- RRC: cuCp, `l3.*` and `ns3.du.numActiveUes`.

`clause` is "vendor" on ns3 rows. On the 3GPP rows it is e.g. "3GPP TS 32.425 V19.0.0 §4.1.3.1".

## Registry entries (all from pages read; PDF pages)

| Entry | Document § and page | Kept in the map? | Value check |
|---|---|---|---|
| TB.TotNbrDl | 28.552 V20.2.0 §5.1.1.7.3 p.112 | no (fixture) | fails: two `gaps` |
| TB.TotNbrDlInitial | 28.552 V20.2.0 §5.1.1.7.1 pp.111-112 | no (fixture) | fails: the same gaps |
| RRC.ConnMean | 28.552 V20.2.0 §5.1.1.4.1 p.68; DC exclusion §1 p.28 | no (fixture) | fails; `dcExcluded: true` |
| RRC.ConnMean | 32.425 V19.0.0 §4.1.3.1 PDF p.19 | **yes**, enb cell 8 | holds; max 255; truncated mean recorded as an `interpretation` |
| DRB.PdcpSduVolumeDL | 28.552 V20.2.0 §5.1.2.1.1.1 p.183 (5.1.2 non-split heading p.183); Kbit from KPM 7.9.1 p.14 | yes, pending P9 | fails (MN-hosted PDCP) |
| DRB.PdcpSduVolumeUL | 28.552 V20.2.0 §5.1.2.1.2.1 p.185; Kbit from KPM p.14 | yes, pending P9 | fails |
| QosFlow.PdcpPduVolumeDL | 28.552 V20.2.0 §5.1.3.6.1.1 pp.196-197; split-only heading 5.1.3 p.188 | no (fixture) | fails; splitOnly and dcExcluded |
| RRU.PrbDl | 28.552 V20.2.0 §5.1.1.2.1 p.44; V17 name RRU.PrbTotDl (V17 pp.33-34) | no (successor fixture) | fails |
| DRB.EstabSucc | 28.552 V20.2.0 §5.1.1.10.2 pp.115-116 | no (fixture) | fails; no total form |

Every entry also carries:
- object class, RAT, layer, unit (+source), data type (+source), owningNode, counting event;
- splitOnly, dcExcluded, perUeAllowed (KPM 7.9 pp.13-14);
- nameForms;
- v17Identical against V17.17.0: true for the two TB clauses (V17 p.77, pp.77-78); false for the rest; null for 32.425;
- legacyName.

Top level:
- the documents with Zotero keys;
- the `_Filter` and noLabel interpretations;
- the families: 28.552 §3.3 pp.32-33, 32.425 §3.1 PDF pp.13-14, plus TB and QosFlow;
- the placeholders;
- the slot kinds, with KPM 8.3.11 labels from pp.30-31.

## Consumers of renamed names

- **Updated:** `install_patch_files/xApps/kpimon-go/control/enb-kpm-measurements.json` (9 eNB names). This is the only by-name reader that is kept in lock-step with the map.
- **Map-driven, so no edit was needed:**
  - `tools/.../influx-vs-trace.py`, `ranfunc-check.py`, `p12-records-check.py`;
  - the agent (`metric-map.cpp:39-45` ignores the extra fields);
  - codec-probe, ue-context-per-seq-test.
- **Reads unchanged names:** `check-n4-v5-windows.py:29`, `n4-drop-selftest.py:17`, `check-pdcp-volume-totals.py:38`, `digest-run.py:64`, `r3p-*` and `n6-fixtures.py:10` read DRB.PdcpSduVolumeUL/DL; `check-s10-neighbours.py` reads `ns3.l3.*`.
- **Uses a matching string that is not a map name; no edit:**
  - `n4-drop-selftest.py:27` (the IPC key `TB.TotNbrDl.1`, a src);
  - `ns3_e2_agent/tests/fixtures/ipc-samples-*.jsonl` (IPC keys);
  - `tools/asn1-indep/selftest_kpm_and_fixtures.py:35-47` and `tools/kpimon-decode-harness/selftest-encoder.c:49` (`DRB.UEThpDl` used as codec test data).
- **Affected but deliberately not edited**, because each is historical evidence or another RAN:
  - `scripts/probes/probe-e2-identity-setup.sh:161`: a historical probe; `--meas DRB.UEThpDl --meas RRU.PrbUsedDl` would now name absent measurements if re-run.
  - `tools/e2-evidence/fixtures/setup-identity/ac6a-setup-requests.txt:142-246,294+`: captured evidence.
  - `scripts/gates/fixtures/ts-influx-mixed/ue-metrics.lp:1-24` and its README: a live cut used by a name-agnostic test.
  - `ns3_e2_agent/tests/fixtures/kpimon-subscription-octets.txt`: a by-name capture; the test checks only G.
  - ad-cell `InfluxDBManager.py.patch:22,34,36,42-47` and `ad/src/ad_config.previous.ini:28,32`: generic 3GPP-name readers that no gate deploys. ad-cell will no longer find PRB or throughput fields on ns-O-RAN data.
  - The OCUDU/OAI READMEs, tutorials and dashboards: another RAN.
  - The TS xApp reads only the ueId tag and time.

## Wire impact

- Indications carry measIDs (`kpm-indication-message.cpp:144-145,194-195`), so the indication bytes and the KPM T/T golden do not change.
- The RAN function description carries names (`kpm-ran-function-description.cpp:31`), and the map's sha8 changes.
- The M6 sha check, the agent image, the kpimon reinstall (eNB list) and the Testbed pin all follow the commit.

## Test results

| Command | Result |
|---|---|
| `python3 -I .../tests/lint-metric-map.py .../schema/metric-map.v1.json --kpimon-enb .../enb-kpm-measurements.json` | exit 0; 0 findings, 2 XFAIL (gnb cell 34/35 pending P9) |
| `python3 -I .../tests/lint-metric-map.py --self-test` | exit 0; shipped pair ok and 35/35 fixtures ok, including all 11 named in row 147 |
| `python3 -I .../tests/lint-metric-map.py --require-no-pending` | exit 1, as intended until P9 |
| `bash scripts/gates/kpimon-guard-selftest.sh` | ok, 12 cases including the 2 new fixtures |
| `bash scripts/gates/lint.sh` | exit 0, "lint: ok", about 2 min. Two pre-existing SKIP lines are unrelated: kpimon codec selftests need KP_SO/KP_INC and KP_E2SM/TS_ORIG. |

The self-test fixtures cover:
- the row-147 list: MAC src under QosFlow; REAL DRB.PdcpSduVolumeDL; Mbit; split-only on gnb; DC-excluded on gnb and on enb; a 3GPP name with no entry; `.5QI` without a total form; TB.TotNbrDl on a UE row; `ns3.du.QosFlow…`; a 3GPP integer typed REAL; a V17-only name, and its move to a successor whose check fails;
- extras: the bare name with no total form; the MU-MIMO suffix; TB with gaps; gNB RRC.ConnMean in EN-DC; a gap inside a holding check; glued, lower-case and placeholder ns3 names; no value check; missing clause or layer; wrong clause; node ownership; the int32 bound; pendingFix on another row; a passing pendingFix row; `--require-no-pending`; an unpinned registry version; a source without a line; and a kept structural check (`_`).

## Independent read (kongming, Opus 5.5) and what I did with it

- **Adopted (spec-backed):**
  - gNB `RRC.ConnMean` fails. 28.552 §1 p.28, which I read, says the NG-RAN measurements apply to EN-DC "but not to the RRC connection related measurements which are handled by E-UTRAN for EN-DC". The registry gains `dcExcluded` on that entry. Lookup is now scoped to the row's own document, so the 28.552 exclusion cannot knock out the eNB row.
  - Case-insensitive vendor-name matching. It closes `ns3.du.qosFlow…` and `tb…`, and it forced `ns3.du.qci` and `drbRelAct` renames. It only adds failures.
  - The eNB floor is recorded as an `interpretation`, not a residual.
- **Adopted as the default, pending R1:** the TB rows fail. I verified both gaps:
  - `lte-enb-rrc.cc:5582-5612,5892-5900`: RemoveUe on X2 UE CONTEXT RELEASE without flushing the per-(RNTI, cell) counts;
  - `mmwave-spectrum-phy.cc:431-437`: the cellId check drops a TB before the trace.
  - The registry now has a `gaps` field. The validator forbids `holds: true` with gaps.
- **Agreed already:** eNB RRC.ConnMean holds; DRB.UEThpDl and DRB.MeanActiveUeDl fail.

## Ambiguities in row 147 and the interpretations chosen

1. **`_Filter`:** the bare name with noLabel is read as the unfiltered total. Recorded in the registry's `interpretations.filter`; it rests on KPM 8.3.9 p.30 and 28.552 §4.1/§4.3.
2. **"Unit (KPM §7.9.1 where it lists the name, else the clause)":**
   - Where the clause states no unit (counts), the registry uses `count`.
   - KPM 7.9.1 cites 28.552 clauses 5.1.2.1.2.1 and 5.1.2.1.2.2 for the DL/UL `_Filter` volumes. V20.2.0 numbers them 5.1.2.1.1.1 and 5.1.2.1.2.1, so KPM cites by older numbering. I matched by name and recorded the mismatch in `unitSource`.
3. **"A splitOnly or dcExcluded entry is forbidden on every node":**
   - Read as: the entries of the row's own document, or of any document when that document has none of the name.
   - Without this scoping, the 28.552 `RRC.ConnMean` exclusion would fail the 32.425 eNB row, which §1 p.28 itself sends to 32.425.
4. **Value-check strictness (gaps vs residuals):** row 147 has no rule for this. I chose the strict rule and need a ruling (R1).
5. **The ns3 name rule:** I chose case-insensitive token matching plus the "family followed by an upper-case letter or digit" glue rule. This is stricter than row 147 (6)'s wording and can produce false positives on two-letter families (CE, IP, SP, TI); none occur in the map.
6. **Layer of ns3 rows:** (6) asks for a layer but no src-section fit. The gNB `ns3.cuUp.txPdcpPduBytesNrRlc` is layer RLC under a cuUp src (NR RLC kbit), and `ns3.du.numActiveUes` is RRC under a du src. I did not add a fit check for ns3 rows.
7. **Same ns3 name, different layer:** `ns3.cuUp.txPdcpPduBytesNrRlc` is RLC on gnb and PDCP on enb, because ns-3 uses one variable name for two quantities. Both rows keep ns-3's name.
8. **The `pendingFix` value** is the string "P9". This puts a plan phase id inside a shipped artifact, which row 147 (8) itself mandates. It conflicts with the general rule against plan IDs in code, so it needs a ledger note.

## Rulings needed (possible ledger amendments)

- **R1. Residual versus gap.**
  - Proposed rule: a residual is allowed only for a point the clause leaves open, or for a boundary effect of at most one slot or sampling interval per event. Any path the runs reach that drops or adds counted events makes the check fail.
  - Under this rule, the cell TB.TotNbrDl and TB.TotNbrDlInitial rows fail; this draft ships that.
  - Under the alternative rule ("any disclosed residual is allowed"), those two rows keep their 3GPP names. That would mean flipping `holds` and the names back on gnb cell 4/5.
  - This needs a row-147 amendment either way.
- **R2. Outcomes that differ from what the user was shown:**
  - `DRB.UEThpDl` is renamed. The L4 ruling's line "DRB.UEThpDl keeps its name" was a forecast made before the value was checked; the value is RLC PDU size over delay.
  - gNB `RRC.ConnMean` is renamed (§1 p.28).
  - `DRB.MeanActiveUeDl` is renamed.
  - The cell TB rows depend on R1.
  - Net effect: the en-gNB reports no passing 3GPP-named measurement until P9 adds the X2 volumes.
  - Suggest an amendment line in the decisions log rather than editing the 21:37 text.
- **R3. TB counter fix** (count at the gNB MAC per cell, e.g. `m_macDlTxSizeRetx` at `mmwave-enb-mac.cc:943`): a follow-up outside M10 next to the PRB fix, or none.
- **R4. Unit-text corrections on renamed rows** (ms → 0.1 ms, bytes → kbit): these change informational text only, never a predicate. Confirm they are welcome.

## Unresolved questions

1. R1–R4 above.
2. ns-3 line numbers are cited at `ea6e46f6`. If P6 lands after the UB-fix commit moves the ns-3 pin, the registry `source` lines need re-checking. The validator checks their form, not their content.
3. Should the guard self-test addition (two fixtures in `kpimon-guard-selftest.sh`) be recorded as an added check in the phase record?
4. ad-cell and ad lose their 3GPP PRB and throughput fields on ns-O-RAN data. No gate deploys them; confirm this is acceptable.

Status: DONE_WITH_CONCERNS
Summary: The registry, strict lint, self-test and in-place renames are drafted and uncommitted. The shipped map passes with the two P9 rows as expected failures, the self-test passes 35/35, and lint.sh and the kpimon guard self-test pass.
Concerns/Blockers: the TB row verdicts depend on rule R1, which needs a user ruling. DRB.UEThpDl, gNB RRC.ConnMean and DRB.MeanActiveUeDl are renamed, which departs from what the user was shown (R2). pendingFix "P9" puts a plan id in a shipped artifact, as row 147 (8) requires.

# P6 metric-map lint: which 28.552 version, and sub-counters in names (kongming)

Date: 2026-11-06 KST. Advisory only. Kongming ran on Opus 5.5 at xhigh, per the user's CLAUDE.md override. No code, plan, ledger, evidence, page, VM, ssh, virsh or Codex was touched.
Pins read: Testbed `163ef25`, ns-3 `ea6e46f6`, oran-interface `53253fe`. V17.17.0 pages are the ETSI printed numbers; the others are PDF pages. Specs: 28.552 V20.2.0 (`5SZUBP6M`), 28.552 V17.17.0 (the ETSI PDF identical to `XU985K2J`), 32.425 V19.0.0 (`9XR9PVRW`), E2SM-KPM v03.00 (`F82PYZVK`).
Legend: [V] verified here (file:line, or clause and page); [I] inference; [B] belief.

## TL;DR

- **Q1. Judge against 28.552 V20.2.0 only, and adopt the successor rule.** KPM v03.00 cites 28.552 without a version, and its §2.1 says the latest version then applies. In P6, though, the successor rule renames no row. Every row whose name depends on the version fails its value check anyway:
  - RRU.PrbTotUl is a constant 0;
  - RRU.PrbTotDl's denominator includes the control symbols, so a full cell reads about 86 %;
  - TB.ErrTotalNbrDl.1 counts received HARQ retransmissions, not NACK/DTX receipts.

  All three become `ns3.*`.
- **Q2. Yes, the lint flags label-expressible sub-counters in 3GPP names.** A bare name with noLabel is allowed only when the clause defines a total and the value is that total. Otherwise the row becomes `ns3.*`. P6 encodes no labels. In practice this changes one row: the gNB cell `TB.TotNbrDl.1` becomes `TB.TotNbrDl`. Every other suffixed row is renamed by its value check.
- **New finding that widens P6.** Spot checks found six more value defects: the hard-coded 139-PRB scale, a constant UL PRB usage, modulation counts that include retransmissions, the eNB delay in 0.1 ms units, and the eNB "kbps" that is bytes/s. That makes about 30 of the 38 names renamed, not about 20. The VM budget and the commit order do not change. Registry work grows to about 2–3 h.

## 1. Question 1: which 28.552 version

### 1.1 Is RRU.PrbDl the same measurement as RRU.PrbTotDl? Yes [V]

| Item | V17.17.0 §5.1.1.2.1/.2 (printed p.32–33) | V20.2.0 §5.1.1.2.1/.2 (p.44–45) |
|---|---|---|
| Title | DL/UL Total PRB Usage | the same |
| Formula | M(T) = M1(T)/P(T) × 100, with P(T) = PRBs available for DL (UL) traffic in T | the same, with optional splits per PLMN, S-NSSAI and ResType |
| Type and unit | a single integer, 0–100 % | the same |
| Object | NRCellDU | NRCellDU |
| Name | `RRU.PrbTotDl` / `RRU.PrbTotUl` | `RRU.PrbDl` / `RRU.PrbUl` (all traffic), plus optional `.PLMN`, `.SNSSAI`, `.SNSSAI.ResType` and `_UEType` |

- The rename came with CR 0466, "Update DL/UL Total PRB Usage to support AI/ML enabled NG-RAN" (SP-231484, 2023-12, V18.5.0; change history in V20.2.0). V17.17.0 is the Rel-17 maintenance line, so it never received it [V row; I attribution].
- The TB name has the same clause in both versions, §5.1.1.7.4 "Total error number of DL TBs":
  - V17.17.0 `TB.ErrToltalNbrDl.X` (printed p.77);
  - V20.2.0 `TB.ErrTotNbrDl.X` (p.112–113);
  - CR 0396, "Modify the counter name for Total error number of DL/UL TBs" (SP-230209, 2023-03, V18.2.0, category F) [V].
- V20.2.0 itself still writes `RRU.PrbTotDlDist`, `RRU.PrbTotDlMimo` and, as a typo, `RRU.PrbTotUlSSB` (p.45–53). 3GPP's rename was not systematic. This does not matter for our rows [V].

### 1.2 Which map names depend on the version [V, script over both texts]

- **Only `RRU.PrbTotDl/Ul`** appear in V17.17.0 and not in V20.2.0. 32.425 still uses the name for E-UTRA, which does not apply to NR rows.
- **`TB.ErrTotalNbrDl.1`** matches neither spelling.
- **`DRB.MeanActiveUeDl`** has an explicit bare form in V20.2.0 (p.143). V17.17.0 has only `_Filter`.
- **The P9 X2 counters:** V20.2.0 defines the bare `DRB.PdcpSduVolumeX2DL/UL` explicitly (text lines 12588, 12713). V17.17.0 has only `_Filter` (lines 8291, 8406). V20.2.0 therefore fits P9's Option A directly.

### 1.3 What ns-3 computes [V code; I consequences]

- **RRU.PrbTotDl ← `dlPrbUsage`.**
  - Per UE: `macPrb = symbols / (slots × 14) × 139` (`mmwave-enb-net-device.cc:1191-1205`). It is summed into a `uint32_t`, so each UE's value is truncated (`:1148`, `:1207`). Then `dlPrbUsage = (long)(Σ/139 × 100)` (`:1374-1375`).
  - The 139 cancels, so the value is the share of symbols scheduled for DL TBs. That is the same quantity the clause defines in both versions.
  - The denominator has two biases. It counts all 14 symbols per slot, including 1 DL and 1 UL control symbol (`mmwave-phy-mac-common.cc:94-95`). Those symbols are never "available for DL traffic", so a full cell reads at most 12/14 ≈ 85.7 %. There is also the per-UE truncation.
- **RRU.PrbTotUl ← `ulPrbUsage = 0`**, marked "TODO for future implementation" (`:1376`). N4 added UL traffic, so the 0 is false. It matches neither version.
- **TB.ErrTotalNbrDl.1 ← TBs received by the UE with rv ≠ 0** (`mmwave-phy-trace.cc:249-258`, called from the UE Rx trace at `:422`). The clause counts "receipt by the gNB of a NACK or DTX" (V20.2.0 p.112).
  - Failures on the last HARQ attempt are missed.
  - Each count lands one HARQ round trip later.

  This is a different counting event.

### 1.4 Who consumes these names [V]

- **kpimon** writes each record into the Influx field named by the RAN function description's list at the same position (`control.go.patch:311-314`; the lists are built at `:597-598`). It has no per-name logic.
- **The TS xApp** reads only the UeMetrics `ueId` tag and time (`ts_xapp.cpp.style5_en_gnb_ueid.patch:18-30`).
- **The R3′ predictor** reads `DRB.PdcpSduVolumeDL` (`scripts/gates/r3p-scenario.json:8`; this is P9).
- **The gates** read IPC keys, which P6 does not change.
- **The NIST AD-cell xApp patch** lists `RRU.PrbTotDl/Ul`, `RRU.PrbUsedDl` and `RRU.PrbAvailDl/Ul` (`ad-cell/.../InfluxDBManager.py.patch:42-47`). No gate deploys it. It loses these fields under any strict outcome. Common RAN stacks and dashboards still emit `RRU.PrbTotDl` [B].

### 1.5 Ruling to put to the user

- **Recommended.** AC16's lint judges NR rows against 28.552 V20.2.0 (`5SZUBP6M`) only.
  - Reasons: KPM §2.1 (p.4) applies the latest version to a non-specific reference; the contract already pins V20.2.0; and accepting either version would be a compatibility mode.
  - Each registry row cites the V20.2.0 clause and page, and says whether V17.17.0's text is identical (the Zotero rule "check more than one version").
  - An old or misspelled name whose V20.2.0 successor has the same clause, type, unit, object and counting event is renamed to the successor, but only if the value passes. Otherwise the row becomes `ns3.*`.
  - At P6 this gives `RRU.PrbTotDl` → `ns3.du.dlPrbUsage` (the denominator bias; the user's Q1 ruling rejected "3GPP name with a recorded deviation"), `RRU.PrbTotUl` → `ns3.du.ulPrbUsage` (not modelled) and `TB.ErrTotalNbrDl.1` → `ns3.du.tbRetxNbrDl`.
- **Alternative.** Judge against V17.17.0, the release the names were copied from and the one deployed stacks follow.
  - It keeps `RRU.PrbTot*` as valid names, for AD-cell and dashboard interoperability.
  - It contradicts KPM §2.1 and the V20.2.0 pin, and P9's bare X2 names would then rest on a `_Filter` reading.
  - It changes no P6 outcome, because the values still fail.
- **Trade-off.** The question decides future names, for instance `RRU.PrbDl` if a later ns-3 fix corrects the denominator. It does not decide P6 rows.
- **Confidence.** High for V20.2.0 and for the clause equivalence. Medium-high that the strict rule should treat the 14/12 denominator as a failure: it is a definitional bias, not noise.
- **Effect on P6.** None on order or budget. It saves work: the lint's name table comes from one spec text.

## 2. Question 2: sub-counters in the name

### 2.1 What KPM v03.00 says [V]

- **§8.3.9 (p.30):** Measurement Name is `PrintableString(SIZE(1..150))`, "One of the measurement names specified in TS 28.552, TS 32.425, or Section 7.10. The subcounters are represented by the Measurement Labels defined in 8.3.11."
- **§8.3.11 (p.30–31)** has labels for:
  - noLabel ("without any subcounter");
  - PLMN, slice ID, 5QI, QFI, QCI;
  - QCImax/QCImin, ARPmax/ARPmin and Bitrate Range, all "used only when the name … ends with '_Filter'";
  - Layer at MU-MIMO;
  - Distribution Bin X/Y/Z;
  - Sum, which means cumulative since the measurement started, not the 3GPP `.sum` across sub-counters.

  There is **no modulation label.** For `TB.TotNbrDlInitial.Qpsk/16Qam/64Qam` the suffix stays in the name, as 28.552 lists those name forms (V20.2.0 p.112).
- **`_Filter` cannot be encoded.** KPM refers to `_Filter` names, yet PrintableString has no `_`. The map's existing reading (bare name with noLabel means the unfiltered total; lint `PRINTABLE`, `lint-metric-map.py:36`) is the only reading that can be encoded. Record it in the registry as an interpretation.
- **No vendor names.** §8.3.9 makes no provision for them. `ns3.*` is a class the project already accepted (Stop A′ ruling 4). The label rule therefore applies to 3GPP-named rows only.
- **Some clauses define no total form.** 28.552 defines `DRB.EstabSucc` only as `.5QI` or `.SNSSAI` (V20.2.0 §5.1.1.10.2; text line 7756). For such names, dropping the suffix invents a name.

### 2.2 Label support today [V]

- **Agent.**
  - Every row is sent with noLabel: `no_label()` (`kpm-indication-message.cpp:48-53`), the Format 1 `labelInfoList` (`:144-150`) and the Format 2 `matchingCond` (`:196-198`).
  - Subscription admission ignores the requested measurement and label lists; it checks only the action type, the definition and the granularity (`kpm-subscription-admission.cpp:115-132`).
  - The KPM RAN function description carries no labels by design.
- **kpimon.**
  - It subscribes Format 1 by name with one noLabel per item (`e2sm/wrapper.c.patch:707-718`) and Format 3 by measID (`control.go.patch:138-141`).
  - It maps records to Influx fields by position against the description's name list (`control.go.patch:311-314`) and never reads `labelInfoList` or `matchingCond`.
  - Two rows with the same name and different labels would collide in one field.

**What real labels would cost:**
- a `label` field in the map, with the measId per measurement type rather than per row, which breaks the lint's measId rule (`:83-87`) and the `enb-kpm-measurements.json` schema;
- about 50 lines in the agent encoder;
- a kpimon Go/C patch to read labels from each indication, build field keys from name and label, and subscribe per name-and-label item;
- a second rename of Influx fields;
- a regenerated KPM T/T golden.

It would be its own feature commit, so one more agent rebuild, kpimon reinstall and M5–M7 cycle (about 1 h and 3–5 GiB) [I]. No P6 survivor needs it.

### 2.3 Is "drop the suffix, report the total under the bare name" honest? Per row

| Rows (kind/list/order) | Suffix | Is the bare name with noLabel an honest total? | P6 outcome |
|---|---|---|---|
| gnb/cell/4 `TB.TotNbrDl.1` | `.1` = MU-MIMO layer | **Yes.** The value counts all TBs, initial and retransmitted (`mmwave-phy-trace.cc:248`), which is §5.1.1.7.3. The scenario is SISO (`scenario-zero.cc:525-527`), so the total equals the only layer | `TB.TotNbrDl` |
| gnb/ue/5 the same | `.1` | Yes on the sub-counter axis. But KPM §7.9 (p.13–14) lists no "TB related" type for per-UE conversion [I] | `ns3.*` if the per-UE rule is registered |
| gnb/cell/10 and ue/10 `TB.ErrTotalNbrDl.1` | `.1` | No. Dropping `.1` does not fix the counting event (§1.3) | `ns3.du.tbRetxNbrDl` |
| gnb/cell/6-8 and ue/7-9 `TB.TotNbrDlInitial.{Qpsk,16Qam,64Qam}` | modulation, which has no KPM label | The suffix must stay. But the value counts **all** TBs per modulation, retransmissions included (`mmwave-phy-trace.cc:262-278`, outside the `rv == 0` branch) | `ns3.*` |
| gnb/ue/30-31 and enb/ue/13-14 `DRB.EstabSucc.5QI`, `DRB.RelActNbr.5QI` | `.5QI` | No. 28.552 has no total form. The values are the current DRB count (`mmwave-enb-net-device.cc:947`) and a constant 0, "not modeled" (oran-interface `mmwave-indication-message-helper.cc:178`). On the eNB they are NR names | `ns3.*` |
| gnb/cell/25 and ue/26 `DRB.BufferSize.Qos`; gnb/ue/29 and enb/ue/12 `DRB.PdcpPduNbrDl.Qos` | `.Qos` | No. Both base names are invented | `ns3.*` |
| gnb `CARR.PDSCHMCSDist.Bin1-6`, `L1M.RS-SINR.Bin*` | bins | No. The bins are the measurement: CARR has the wrong form and semantics, and L1M is invented | `ns3.*` |
| enb/cell/4 and ue/8 `DRB.PdcpSduDelayDl` | `.QCI`, already dropped | Yes on the sub-counter axis: 32.425 §4.4.3.1 (p.52) defines a `.sum` total, and there is one QCI [I]. But see §3, item 5 (0.1 ms units) | `ns3.*` |
| enb/ue/7 `DRB.PdcpSduBitRateDl` | `.QCI`, dropped | Yes on the sub-counter axis. But see §3, item 6 (bytes/s), and the case differs from 32.425's `Bitrate` | `ns3.*` |
| `_Filter` rows (`DRB.PdcpSduVolumeDL/UL`, the X2 rows) | `_Filter`, dropped | Yes: the unfiltered total | per the P6 and P9 rulings |

### 2.4 Ruling to put to the user

- **Recommended.**
  - The lint parses each 3GPP name against its clause's name grammar and fails any suffix that encodes a sub-counter for which KPM §8.3.11 has a label: PLMN, S-NSSAI, 5QI, QFI, QCI, MU-MIMO layer or distribution bin.
  - The rename rule then sends the bare name with noLabel only if two conditions hold:
    - (a) the clause defines a total, meaning a bare form, `.sum`, an unfiltered `_Filter`, or a split that applies only in the MU-MIMO case;
    - (b) the value is that total.

    Otherwise the row becomes `ns3.*`.
  - Sub-counters that have no KPM label (modulation) stay in the name as the clause lists them.
  - `ns3.*` names are free-form, but they must not reuse a 3GPP family name or placeholder. Today's `ns3.du.QosFlow.PdcpPduVolumeDL` (gnb/ue/11) breaks that rule; P6's MAC rename fixes it.
  - P6 encodes no labels. noLabel stays everywhere, so indication bytes and the KPM T/T golden stay identical.
- **Alternative.** Add real label support (§2.2) and send, for example, `TB.TotNbrDl` with the label Layer at MU-MIMO = 1, or `DRB.EstabSucc` with 5QI = 9.
  - It is closer to KPM.
  - It costs a separate agent and kpimon cycle and a second Influx rename.
  - It serves no row that survives the value checks.
- **Trade-off.** The recommendation keeps P6 to a map, lint and kpimon-list change with no label machinery. Its only limit is that a future 3GPP name with no total form must stay `ns3.*` until labels exist.
- **Confidence.** High on the KPM reading. Medium-high on treating `noLabel` as the 3GPP total. Medium on the per-UE TB exclusion (§7.9 is a table of types, not an exhaustive rule).
- **Effect on P6.** It changes one name directly (gnb/cell/4). It adds a small suffix-grammar table to the lint. Order and budget do not change.

## 3. New value defects the strict lint must catch [V code; I consequences]

1. **The PRB scale is hard-coded at 139.** `dlAvailablePrbs = ulAvailablePrbs = 139` (`mmwave-enb-net-device.cc:1371-1372`), and `RRU.PrbUsedDl` is the symbol share × 139 (`:1203-1205`).
   - The simulated cell has `ceil(20 MHz / 720 kHz) = 28` RBs (`scenario-zero.cc:519`; `mmwave-phy-mac-common.cc:143-144`; numerology default 2 at `:48-52`).
   - The agent's X2 setup advertises nrb24 (`e2-node-identity.hpp:32-33`).

   `RRU.PrbAvailDl/Ul` and `RRU.PrbUsedDl` (cell and UE) therefore fail and become `ns3.*`.
2. **RRU.PrbTotUl** is a constant 0 (§1.3).
3. **RRU.PrbTotDl** has the 14/12 denominator bias (§1.3).
4. **TB.TotNbrDlInitial.{mod}** includes retransmissions (§2.3).
5. **The eNB `DRB.PdcpSduDelayDl` is in 0.1 ms, not ms.**
   - The PDCP Rx trace passes ns (`lte-pdcp.cc:219`), `GetDlDelay` returns the ns mean (`mmwave-bearer-stats-calculator.cc:746`), and the code divides by 1e5, commented "x 0.1 ms" (`lte-enb-net-device.cc:1162`).
   - The cell value is an unweighted mean of per-UE means (`:1215-1218`).
   - 32.425 wants an integer ms mean over SDUs.
6. **The eNB `DRB.PdcpSduBitRateDl` is PDU bytes per second.** It is computed as `txBytes / m_e2Periodicity` with the period in seconds (`lte-enb-net-device.cc:1167`, attribute `:567-571`) and commented "kbps". 32.425 wants SDU kbit/s, an integer, at cell level (§4.4.1.1, p.48).

Probable survivors under V20.2.0 with the rules above:
- gnb/cell `TB.TotNbrDl` and `TB.TotNbrDlInitial`;
- `RRC.ConnMean` (×2), `DRB.MeanActiveUeDl` and `DRB.UEThpDl`, whose values I did **not** check;
- `DRB.PdcpSduVolumeUL/DL`, pending P9;
- P9's X2 rows.

## 4. Effect on P6 scope, order and budget

- **Order:** unchanged (D-R3-1, UB, P6, SN-wrap, P7, P9, and so on).
- **VM budget:** unchanged. All the renames are one map change, so one agent rebuild, one kpimon reinstall (its eNB list per `lint-metric-map.py:121-133`) and M5–M7.
- **Agent time:** the registry needs a value check with file:line per row, so about 2–3 h instead of 1–2 h [I].
- **Bytes:** indication bytes are unchanged, because records go by measID with noLabel. The E2 Setup description, the Influx field names and `enb-kpm-measurements.json` change. The registry's `legacyName` gives the cp3 diff its old → new field map.
- **Optional follow-up, not in P6:** an ns-3 commit that sources the true PRB counts (`GetNumRb()`), a data-symbol denominator and UL usage. That would let the PRB family return to 3GPP names (`RRU.PrbDl/Ul`, `RRU.PrbUsedDl`, `RRU.PrbAvailDl/Ul`). It is a new T-C item, so it needs a registered scope addition and its own M4 and M5–M7 (about 1 h, 3–4 GiB). Defer it outside M10, like the eNB volume follow-up for row `:128`, unless the user wants PRB realism inside M10.

## Assumptions

- **noLabel denotes the 3GPP total across sub-counters** (medium-high). If the user reads noLabel as invalid for a clause that splits mandatorily, `TB.TotNbrDl` also becomes `ns3.*`.
- **One QCI or 5QI per UE in the scenario** (medium; `qci = 1` hard-coded at `mmwave-enb-net-device.cc:1373`, and the delay reads lcid 3 only).
- **The control-symbol denominator counts as a failure under the strict rule** (medium-high). If the user accepts it as a known approximation, it would reopen the "recorded deviation" class that Q1 rejected.
- **The registry includes a per-UE (§7.9) check** (medium). If it does not, the gnb/ue TB rows keep `TB.TotNbrDl` and `TB.TotNbrDlInitial` forms.
- The CR attribution for the PRB rename is inferred from the change-history title (medium-high).

## Unresolved questions

1. Q1 and Q2 rulings (§1.5, §2.4).
2. Does the user want the PRB-family source fix (§4) inside M10 as a new item, or recorded as a follow-up?
3. Is the per-UE §7.9 check part of the registered P6 rule?
4. The values of `RRC.ConnMean`, `DRB.MeanActiveUeDl` and `DRB.UEThpDl` against their clauses were not checked here. The registry must check them.
5. The type check: 32.425 and 28.552 give integers for several kept names, while the map uses REAL for some (for example `DRB.UEThpDl`). The lint needs a stated type rule (KPM keeps the 3GPP data type except where §7.9.1 changes it).

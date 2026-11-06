# Where the KPM measurement names in metric-map.v1.json came from

Date: 2026-11-06 (Asia/Seoul). Read-only research. Nothing in code, plans, ledger, evidence or pages was changed, and no VM, ssh or Codex was used.

## Plain answer

Most of the names were not chosen by this project. The ns-O-RAN authors (Michele Polese, Andrea Lacava and Tommaso Zugno at Northeastern University) wrote them in 2022, and this project inherited them as ns-3 strings [V]. They copied most of them from the 3GPP texts current at the time: TS 28.552 Rel-16/17 for the gNB side and TS 32.425 for the LTE eNB side. The evidence is in the spellings: they reproduce placeholders literally (`_Filter`, `.5QI`) and match each spec's own capitalisation (`DRB.PdcpSduVolumeDl` with 32.425's `Dl`, `QosFlow.PdcpPduVolumeDL` with 28.552's `DL`) [V spec text; I authorial intent]. Several names that fail today are real names from older or other specs. `RRU.PrbTotDl/Ul` is the 28.552 name up to at least V17.17.0 and is still the 32.425 name. `TB.ErrTotalNbrDl.X` is a corrected spelling of 28.552 Rel-16/17's typo `TB.ErrToltalNbrDl.X`, which V20.2.0 now spells `TB.ErrTotNbrDl.X`. `DRB.PdcpSduBitRateDl` is 32.425's `DRB.PdcpSduBitrateDl.QCI` with different capitalisation [V]. Four families have no definition in 28.552 (V16.6, V17.6, V17.17 or V20.2), 32.425 V19.0.0 or E2SM-KPM v03.00: `DRB.BufferSize.Qos`, `DRB.PdcpPduNbrDl.Qos`, `Tot.PdcpSduNbrDl` and `L1M.RS-SINR.Bin*`. They are ns-O-RAN inventions styled after 3GPP names [V search]. This project added only six of the 38 names, on 2026-10-21/22 and 2026-10-27: `RRU.PrbAvailDl/Ul`, `RRU.PrbTotDl/Ul` and `DRB.PdcpSduVolumeUL/DL` [V]. It also put the CSV-only `RRC.ConnMean` on the wire [V].

## Table

Map lines refer to `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/schema/metric-map.v1.json` at Testbed `163ef25`. These abbreviations are used:
- "NS3-1" means ns-3-mmwave-oran `fccf3903` (2022-04-15, Michele Polese, co-authors Andrea Lacava and Tommaso Zugno, "E2 interface integration (#1)").
- "OI-1" means oran-interface `8585bec` (2022-09-25, Andrea Lacava, "First release").
- "MAP-1" means Testbed `d487283` (2026-10-22, Thien An Dang Thanh, "add metric map v1 and its lint").
- 28.552 means V20.2.0 (Zotero `5SZUBP6M`) unless a version is given. 32.425 means V19.0.0 (Zotero `9XR9PVRW`). KPM means E2SM-KPM v03.00 (Zotero `F82PYZVK`). All pages are PDF pages.

| Name (map lines) | First appeared | Defining spec or nearest | Verdict |
|---|---|---|---|
| `TB.TotNbrDl.1`, `TB.TotNbrDlInitial`, `.Qpsk`, `.16Qam`, `.64Qam` (26-30, 62-66) | NS3-1 `mmwave-enb-net-device.cc:435,447` (CSV header); wire key OI-1 `helper/mmwave-indication-message-helper.cc:83-87,130-136` [V] | 28.552 §5.1.1.7.1 p.111-112 and §5.1.1.7.3 p.112 (`TB.TotNbrDl.X`, X = DL MU-MIMO max layer); the same in V16.6.0 p.46 [V] | Standard and correctly applied (NR, NRCellDU). The ns-3 modulation split by MCS range 0-9/10-16/17-28 (`mmwave-phy-trace.cc:264-278`) matches the subcounter idea [V code; I semantics] |
| `TB.ErrTotalNbrDl.1` (32, 67) | NS3-1 `:437,449`; OI-1 `:88,141` [V] | 28.552 V16.6.0 §5.1.1.7.4 p.47 and V17.6.0 p.77 spell it `TB.ErrToltalNbrDl.X` (a typo); V20.2.0 §5.1.1.7.4 p.113 spells it `TB.ErrTotNbrDl.X` [V] | Standard with a syntax variant. The authors corrected the old typo to "Total", and later 3GPP fixed it differently [I] |
| `CARR.PDSCHMCSDist.Bin1`…`Bin6` (34-39, 70-75) | NS3-1 `:441,455`; OI-1 `:91-96,143-148` [V] | 28.552 §5.1.1.12.1 p.121 (V16.6.0 p.53): `CARR.PDSCHMCSDist.BinX.BinY.BinZ`, X = rank (1-8), Y = MCS table (1-3), Z = MCS index (0-31). It counts PDSCH **RBs** per MCS [V] | Standard name, wrong form and wrong semantics. ns-3 counts TBs in six MCS ranges, 0-4 … 25-29 (`mmwave-phy-trace.cc:280-303`) [V] |
| `L1M.RS-SINR.Bin34/46/58/70/82/94/127` (40-46, 76-82) | NS3-1 `:441-444,455`; OI-1 `:97-103,149-155` [V] | No such name in any 28.552 version checked or in KPM. Nearest: 32.425 §6.6 p.95-96 `MR.RSSINR.BinX` (E-UTRA, eNB, -23 to 40 dB, 0.5 dB steps); 28.552 §5.1.1.32.1 p.166 `MR.NRScSSSINR.BinX` (NR; not in V16.6.0, present by V17.6.0 p.118); KPM §7.10.8 p.20 `L1M.DL-SS-SINR.SSB` (average, not distribution) [V] | Invented hybrid: 28.552's `L1M.` prefix (as in `L1M.SS-RSRP.BinX`, V16.6.0 p.69), E-UTRA's "RS-SINR" quantity, and bin labels that are 0-127 report indices. ns-3 thresholds −6/0/6/12/18/24 dB (`mmwave-phy-trace.cc:305-332`) map to index 2·(dB+23) = 34/46/58/70/82/94, with 127 as the top. The values are per-TB PHY SINR, not UE-reported [V code; I mapping] |
| `DRB.BufferSize.Qos` (47, 83) | NS3-1 `:444,1190`; OI-1 `:104,156` [V] | None in 28.552 (all four versions), 32.425 or KPM [V search]. No buffer-occupancy measurement exists in either PM spec [V search] | Invented, styled after 3GPP. `.Qos` imitates the `.QoS`/`.QOS` subcounter placeholder |
| `DRB.PdcpPduNbrDl.Qos` (86, 135) | NS3-1 `lte-enb-net-device.cc:637`; OI-1 `:46` [V] | None [V search]. Nearest: 28.552 §5.1.3.10.2 p.204 `DRB.TotalPdcpSDUPacketDl` (SDU packets, split CU-UP only; absent in V16.6.0 and V17.6.0) [V] | Invented |
| `Tot.PdcpSduNbrDl` (129) | NS3-1 `lte-enb-net-device.cc:635`; OI-1 `lte-indication-message-helper.cc` (`:49` today) [V] | None. No 3GPP family is called `Tot.`; 32.425 has no PDCP SDU count [V search]. Nearest: the same 28.552 §5.1.3.10.2 (NR, split only) | Invented |
| `QosFlow.PdcpPduVolumeDL` (33, 85, 134) | NS3-1 `lte-enb-net-device.cc:636`, `mmwave-enb-net-device.cc:450`; OI-1 `:43,89,142` [V] | 28.552 §5.1.3.6.1.1 p.196: split gNB only, DC excluded, `_Filter` form, Mbit (Kbit per KPM §7.9.1 p.14) [V]. The same in V16.6.0 p.88 | Standard but mis-applied: MAC TB bytes on the gNB cell, NR RLC kbit per UE, and an LTE eNB row |
| `DRB.EstabSucc.5QI`, `DRB.RelActNbr.5QI` (87-88, 136-137) | NS3-1 `mmwave-enb-net-device.cc:719-720` (`AddItem`), `lte-enb-net-device.cc:642` [V] | 28.552 §5.1.1.10.2 p.115 and §5.1.1.10.3 p.116 (5GS, mapped 5QI); V16.6.0 p.50-51. E-UTRA counterpart: 32.425 §4.2.2.6 p.30 `ERAB.RelActNbr.QCI` [V] | Standard but mis-applied. The NR 5GS names sit on the LTE eNB. `.5QI` is the placeholder, copied literally. The value is the current DRB count, with RelAct a constant 0 ("not modeled"), not a per-period count [V code] |
| `DRB.PdcpSduVolumeDl` (128) | NS3-1 `lte-enb-net-device.cc:634` (as `_Filter.UEID`); OI-1 `lte-indication-message-helper.cc` [V] | 32.425 §4.4.7.1 p.58 `DRB.PdcpSduVolumeDl_Filter` (E-UTRA, Mbit; Kbit per KPM §7.9.1 p.14) [V] | Standard 32.425 name (its exact `Dl` case) but mis-applied: the value is MN PDCP **PDU** volume, sent as REAL bytes |
| `DRB.PdcpSduDelayDl` (119, 131) | NS3-1 `lte-enb-net-device.cc:632,636`; OI-1 `lte-indication-message-helper.cc` [V] | 32.425 §4.4.3.1 p.52 `DRB.PdcpSduDelayDl.QCI` (E-UTRA, mean in ms). NR split-only twin: 28.552 §5.1.3.3.1 p.191 [V] | Standard 32.425 name with the `.QCI` subcounter dropped. It is plausibly correct for the eNB [I] |
| `DRB.PdcpSduBitRateDl` (130) | NS3-1 `lte-enb-net-device.cc:635`; OI-1 `lte-indication-message-helper.cc` [V] | 32.425 §4.4.1.1 p.48 `DRB.PdcpSduBitrateDl.QCI` (lower-case "r", kbit/s, cell level) [V] | Standard with a syntax variant (capitalisation, no `.QCI`). Applied per UE, while 32.425 defines it per cell |
| `RRU.PrbUsedDl` (31, 69) | NS3-1 `:437,450`; OI-1 `:90,137` [V] | 28.552 §5.1.1.2.5 p.46; V16.6.0 p.27 [V] | Standard |
| `DRB.UEThpDl` (84) | NS3-1 `:458`; OI-1 `:110` [V] | 28.552 §5.1.1.3.1 p.56-57; V16.6.0 p.29 [V] | Standard |
| `DRB.MeanActiveUeDl` (48) | NS3-1 `:444`; OI-1 `:159` [V] | 28.552 §5.1.1.23.1 p.142-143. The bare form is the V16.6.0 p.69 wording; V17.6.0 p.105 has only `_Filter` [V] | Standard |
| `RRC.ConnMean` (55, 123) | ns-3 `70f09016` (2022-12-23, Andrea Lacava, PR #107), CSV only. Put on the wire by MAP-1 [V] | 28.552 §5.1.1.4.1 p.68; 32.425 §4.1.3.1 p.19 [V] | Standard on both node kinds |
| `RRU.PrbAvailDl`, `RRU.PrbAvailUl` (49-50) | This project: kongming P3 counsel `plans/reports/kongming-261021-2005-GH-1-p3-e2-agent-design-counsel.md:341,358`, then MAP-1. The source fields `dlAvailablePrbs`/`ulAvailablePrbs` come from NS3-1 `:432` [V] | 28.552 §5.1.1.2.6 p.47 and §5.1.1.2.8 p.48; V16.6.0 p.27-28 [V] | Standard |
| `RRU.PrbTotDl`, `RRU.PrbTotUl` (51-52) | This project: the same counsel `:341,359`, then MAP-1. The source fields `dlPrbUsage`/`ulPrbUsage` (%) come from NS3-1 [V] | 28.552 §5.1.1.2.1/.2 used `RRU.PrbTotDl/Ul` in V16.6.0 p.25, V17.6.0 p.33-34 and V17.17.0 p.34. V20.2.0 p.44-45 renames them `RRU.PrbDl/Ul`. 32.425 §4.5.3/4.5.4 p.62 still uses `RRU.PrbTotDl/Ul` (E-UTRA) [V] | Standard in older 28.552 and in 32.425, but superseded in the pinned 28.552 V20.2.0 |
| `DRB.PdcpSduVolumeUL`, `DRB.PdcpSduVolumeDL` (56-57) | This project: oran-interface `96efc40` (2026-10-27, Thien An Dang Thanh) `helper/mmwave-indication-message-helper.cc:55-56`; Testbed `c6d1434` (2026-10-27); plan `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/phase-06-n4-ul-traffic-and-ul-pdcp-volume-counter.md:16,47-48` [V] | 28.552 §5.1.2.1.1.1 p.183 and §5.1.2.1.2.1 p.185 (non-split, `_Filter` form; Kbit per KPM §7.9.1 p.14) [V] | Standard and correctly formed. The value carries recorded deviation P9 (MN-hosted PDCP in EN-DC) |

Count: 13 names are standard as applied (the TB family of 5, `RRU.PrbUsedDl`, `RRU.PrbAvailDl/Ul`, `DRB.UEThpDl`, `DRB.MeanActiveUeDl`, `RRC.ConnMean` and `DRB.PdcpSduVolumeUL/DL`). Ten are standard with a syntax variant or an outdated form (`TB.ErrTotalNbrDl.1`, `RRU.PrbTotDl/Ul`, `DRB.PdcpSduBitRateDl` and the 6 `CARR` bins). Five are standard but mis-applied (`QosFlow.PdcpPduVolumeDL`, `DRB.EstabSucc.5QI`, `DRB.RelActNbr.5QI`, `DRB.PdcpSduVolumeDl` and `DRB.PdcpSduDelayDl`, the last only marginally). Ten are invented (7 `L1M.RS-SINR` bins, `DRB.BufferSize.Qos`, `DRB.PdcpPduNbrDl.Qos` and `Tot.PdcpSduNbrDl`). This sums to 38. I did not re-run the strict lint, so this grouping is mine and may not match its exact fail list of about 20.

## Evidence notes

1. **The chain of custody [V].**
   - ns-O-RAN's first public E2 commit is NS3-1. It carries every inherited name as CSV headers and comments: `src/mmwave/model/mmwave-enb-net-device.cc:432-458,1149-1190` and `src/lte/model/lte-enb-net-device.cc:632-642,845-848`.
   - At NS3-1, ns-3 already depends on a module called `oran-interface` (`src/mmwave/wscript:10`) and includes `mmwave-indication-message-helper.h` (`mmwave-enb-net-device.cc:60`). The wire strings (`AddItem("…UEID")`) therefore lived in that module. Its public history starts at OI-1, five months later, with the strings already in place.
   - `git log -S` in oran-interface returns OI-1 as the first commit for every inherited name. In ns-3-mmwave-oran it returns NS3-1, except `RRC.ConnMean` (`70f09016`).
   - The pre-2022-04 private history is not visible [I].
   - This project's map copies the names from the helpers (`origin` fields cite oran-interface `5f547ae`). The kongming P3 counsel set the naming rule (`kongming-261021-2005-…:339-341`): "Keep the ns-3/3GPP name; drop `.UEID` and `_Filter` … unless a TS 28.552 name fits exactly (`RRU.PrbAvailDl/Ul`, `RRU.PrbTotDl/Ul`, `RRC.ConnMean`)". That rule did not check the inherited names against any spec version, which is how the failures came through unchanged.

2. **Other sources ruled out [V].**
   - The OSC e2sim KPM example (`oran-e2sim/e2sim/e2sm_examples/kpm_e2sm/src/kpm/encode_kpm.cpp`) contains none of these names.
   - NIST's kpm_sim uses a disjoint set of 9 O-RAN §7.10 names (`lint-metric-map.py:31-35`).
   - colosseum-near-rt-ric and ric-app-qp contain none of them. ns-o-ran-gym only consumes them.
   - Neither ns-O-RAN paper in Zotero names or cites them:
     - The WNS3 2023 paper (`GE3QIWXF`, p.5) says the indications follow "the O-RAN KPM specification [15]", but its reference [15] is the O-RAN Use Cases Analysis Report.
     - The TMC paper (`79CU8L45`, p.8) describes the state vector (PRB, active UEs, TBs and QPSK/16QAM/64QAM shares) in prose and cites E2SM-KPM v02.00 (Jul 2021) as [17].
   - A web search for `DRB.BufferSize`, `DRB.PdcpPduNbrDl` and `Tot.PdcpSduNbrDl` found no defining document.

3. **The transport was also ns-O-RAN-specific [V].** The names travel in a custom ASN.1 module `E2SM-KPM-RC` (`oran-e2sim/e2sim/src/ASN1c/e2sm-kpm-rc.asn`, added in `77a7b72` on 2021-06-08 by Andrea Lacava and updated in `65889d8` on 2021-07-09 by Tommaso Zugno).
   - The module combines E2SM-KPM v1-style PF containers with a `list-of-PM-Information` that carries `pmType` as `measName` (`:138-156`), plus `valueRRC`/`L3-RRC-Measurements` (`:289-293`).
   - The unnamed ns-3 fields are the v1 container fields: `dl-TotalofAvailablePRBs` (`:174`), `dl-PRBUsage` (`:200`), `numberOfActive-UEs` (`:224`) and `pDCPBytesDL/UL` (`:268-269`). This is why `dlAvailablePrbs`, `dlPrbUsage`, `numActiveUes` and `pDCPBytesDL` had no 3GPP name until this project mapped some of them.

4. **Why the placeholder suffixes matter [V].**
   - The 3GPP texts write names with placeholders: `X_Filter`, `X.5QI` "where 5QI identifies mapped 5QI", and `X.QCI`.
   - ns-O-RAN copied the placeholders literally (`QosFlow.PdcpPduVolumeDL_Filter`, `DRB.PdcpSduVolumeDl_Filter`, `DRB.EstabSucc.5QI`) and added its own `.UEID` for per-UE variants.
   - KPM §8.3.9 (p.30) defines measName as "one of the measurement names specified in TS 28.552, TS 32.425, or Section 7.10. The subcounters are represented by the Measurement Labels defined in 8.3.11."
   - KPM §7.9 (p.13) derives per-UE variants by restricting the 3GPP formula to the UE, not by renaming.
   - The map already drops `.UEID` and `_Filter`. `.5QI`, `.Qos` and `.1` remain inside names [I: whether the strict lint treats them as label-expressible subcounters].

5. **Older 28.552 versions** were downloaded from ETSI (TS 128 552 V16.6.0 2020-08, V17.6.0 2022-05, V17.17.0 2025-04) into the session scratchpad. They were not added to Zotero.
   - V17.6.0 was current when NS3-1 landed. Its wording matches the inherited names better than V20.2.0 does: it has `RRU.PrbTotDl` and the `ErrToltal` typo.
   - The bare `DRB.MeanActiveUeDl` matches V16.x [V text; I that this is the version the authors read].

## Unresolved questions

1. Which 28.552 version should the strict lint judge against? Under V17.x, `RRU.PrbTotDl/Ul` are valid NR names. Under the pinned V20.2.0, they are not. Renaming them to `ns3.*` instead of `RRU.PrbDl/Ul` would discard a real, if renamed, 3GPP name. This is the user's call.
2. The exact 28.552 version and CR that renamed `RRU.PrbTotDl` to `RRU.PrbDl` and `TB.ErrToltalNbrDl` to `TB.ErrTotNbrDl` is not traced. It is somewhere after V17.17.0, probably Rel-18 [I].
3. I did not check whether 32.425 already had `MR.RSSINR.BinX` around 2021, so I cannot say whether it inspired `L1M.RS-SINR`.
4. The private pre-2022-09 oran-interface history is unavailable. Only the authors (Lacava and Polese) could confirm whether the invented names came from an internal document.
5. Should the strict lint flag subcounters embedded in names (`.5QI`, `.1`), given that KPM §8.3.9 puts subcounters in Measurement Labels? If it should, even the "standard" `TB.TotNbrDl.1` and `DRB.EstabSucc.5QI` change form.

Status: DONE
Summary: 32 of the 38 names come from ns-O-RAN (2022), mostly copied from 28.552 Rel-16/17 and 32.425. Ten are invented, ten are old-version or capitalisation variants, five are mis-applied, and this project added six correct ones.

# R-3 served-cell radio constants checked against the 3GPP specs in Zotero

Date: 2026-11-05 (Asia/Seoul). Read-only: no repo file edited apart from this report, Zotero not modified.
Constants under test: `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/e2-node-identity.hpp:30-39`. Usage: `src/e2-node-identity.cpp:59-62,74-76,98`. `kNrArfcn` feeds **two** fields: the X2 NR Freq Info `NRARFCN` and the MTC `carrierFreq` (see `x2ap_codec/x2ap-codec-measurement-timing.c:40`).

Page convention: "p. N" is the printed ETSI page number, and the PDF page is N+1. I checked this offset on every document cited here.

## Sources (Zotero)

| Spec | Version | Title | Zotero item key | PDF attachment |
|---|---|---|---|---|
| 3GPP TS 38.101-1 (ETSI TS 138 101-1) | V19.7.0 (2026-10), Rel-19 | 5G; NR; User Equipment (UE) radio transmission and reception; Part 1: Range 1 Standalone | **IH9HGZUU** | NHCW26VR |
| 3GPP TS 36.101 (ETSI TS 136 101) | V19.6.0 (2026-08), Rel-19 | LTE; E-UTRA; User Equipment (UE) radio transmission and reception | **5CR6ETYC** | T67CEUFN |
| 3GPP TS 36.104 (ETSI TS 136 104) | V19.2.0 (2026-02), Rel-19 | LTE; E-UTRA; Base Station (BS) radio transmission and reception | **ZE9UAT4R** | UCZUG7Z2 |
| 3GPP TS 36.423 (ETSI TS 136 423) | V19.1.0 (2026-02), Rel-19 | E-UTRAN; X2 Application Protocol (X2AP) | **3ML7Y29A** | LHV5ERKR |
| 3GPP TS 38.331 (ETSI TS 138 331), used for cross-checks only | V19.4.0 (2026-09), Rel-19 | 5G; NR; RRC; Protocol specification | **WF2FTADX** | Q47RLPUX |

TS 38.104 (the NR BS RF spec that 36.423 cites for the NR-ARFCN) is **not** in Zotero. A search for "38.104" found nothing. For the same quantities I used 38.101-1, which has the same F_REF equation and per-band tables.

## Verdict summary

| # | Constant | Verdict |
|---|---|---|
| 1 | NRNRB = 24 RBs for 20 MHz at 60 kHz | VERIFIED |
| 2 | n78 allows 60 kHz SCS with a 20 MHz channel | VERIFIED (no footnote on n78) |
| 3 | NR-ARFCN 633333 is in n78 and ≈3500 MHz | Band and frequency VERIFIED. **DISAGREES** on the raster step and on how the value is used (see §3) |
| 4 | SSB SCS for n78 = 30 kHz (`kSsbScsIndex` 1 = kHz30) | VERIFIED. 15 kHz is **not** allowed for the n78 SSB |
| 5 | n78 is TDD | VERIFIED |
| 6 | E-UTRA 20 MHz = 100 RBs | VERIFIED (36.101 and 36.104) |
| 7 | EARFCN DL 100 / UL 18100 are in band 1 at 2120 / 1930 MHz, and band 1 supports 20 MHz | VERIFIED (both values sit exactly on the lowest usable channel number for 20 MHz) |
| 8 | X2AP enums: NRSCS[2]=scs60, NRNRB[2]=nrb24, Transmission-Bandwidth[5]=bw100 | VERIFIED |

## Details

### 1. NR N_RB for 20 MHz at 60 kHz: VERIFIED
- 38.101-1 V19.7.0 (IH9HGZUU), §5.3.2, **Table 5.3.2-1 "Maximum transmission bandwidth configuration N_RB"**, p. 66 (PDF 67). Checked against the page image.
- Row SCS 60 kHz: `10 MHz 11 | 15 MHz 18 | 20 MHz 24 | 25 MHz 31 | …`. The 20 MHz column is **24**, which matches `kNrNrbIndex` = nrb24.
- Same page, Table 5.3.3-1: the minimum guardband at 60 kHz / 20 MHz is 1330 kHz, which is consistent.

### 2. n78 with 60 kHz SCS and a 20 MHz channel: VERIFIED
- 38.101-1, §5.3.5, **Table 5.3.5-1 "Channel bandwidths for each NR band"**. The title is on p. 69 (PDF 70) and the n78 rows are on p. 72 (PDF 73). Checked against the page image.
- n78 rows as read: SCS 15 → 10,15,20,25,30,40,50. SCS 30 → 10,15,20,25,30,40,50,60,70,80,90,100. **SCS 60 → 10,15,20,25,30,40,50,60,70,80,90,100**.
- No superscript note is attached to "n78" or to any n78 cell, so no footnote applies. In the same table, n79 has notes 10 and 4, and n78 has none.
- §5.3.5 text (p. 68): "The transmission bandwidth configuration in Table 5.3.2-1 shall be supported for each of the specified channel bandwidths."

### 3. NR-ARFCN 633333: band and frequency VERIFIED, raster step and field semantics DISAGREE
**Frequency (VERIFIED).** §5.4.2.1, **Table 5.4.2.1-1**, p. 84 (PDF 85):
- `F_REF = F_REF-Offs + ΔF_Global (N_REF – N_REF-Offs)`.
- Row "3000 – 24250 | ΔF_Global 15 kHz | F_REF-Offs 3000 MHz | N_REF-Offs 600000 | 600000 – 2016666".
- 633333 → 3000 + 0.015 × 33333 = **3499.995 MHz**, which is ≈3500 MHz.

**Band (VERIFIED).**
- Table 5.2-1, p. 38 (PDF 39): "n78 | 3300 MHz – 3800 MHz | 3300 MHz – 3800 MHz | TDD". 3499.995 MHz is inside this range.
- §5.4.2.3, **Table 5.4.2.3-1 "Applicable NR-ARFCN per operating band"**, p. 86 (PDF 87):
  - `n78 | 15 | 620000 – <1> – 653333 | 620000 – <1> – 653333`
  - `    | 30 | 620000 – <2> – 653332 | 620000 – <2> – 653332`
  - 633333 is inside 620000–653333.

**ΔF_Raster step: DISAGREES.**
- §5.4.2.3 text, p. 85 (PDF 86): "In frequency bands with two or more ΔF_Raster, the higher ΔF_Raster: For 15 kHz and 30 kHz channel raster applies to channels using only the SCS that is equal to or larger than the higher ΔF_Raster and SSB SCS is equal to the higher ΔF_Raster."
- Our NR carrier uses only 60 kHz SCS (≥ 30), and its SSB SCS is 30 kHz (= 30). So the **30 kHz raster with step <2> from 620000 applies**.
- (633333 − 620000) = 13333 is odd, so **633333 is not on the n78 30 kHz channel raster**. It is valid only on the 15 kHz raster, which applies to carriers that use 15 kHz SCS.
- Nearest valid 30 kHz-raster points: 633332 (3499.98 MHz) and 633334 (3500.01 MHz).

**What the signalled field actually means: DISAGREES with the constant's comment ("3.5 GHz, the ns-3 mmWave carrier (scenario-zero centerFrequency)").**
- 36.423 §9.2.106 NR Frequency Info, p. 277 (PDF 278), NRARFCN: "RF Reference Frequency as defined in TS 38.104 [37] section 5.4.2.1. The frequency provided in this IE identifies the absolute frequency position of the reference resource block (Common RB 0) of the carrier. Its lowest subcarrier is also known as Point A."
  - So X2 `NRARFCN` is **Point A**, not the carrier centre. Point A only has to lie on the global raster (ΔF_Global 15 kHz), and 633333 does. The channel-raster step rule therefore does not bind this field directly.
  - Signalling the carrier centre here is still a semantic error. A Point A of 3499.995 MHz puts a 24-RB / 60 kHz carrier (17.28 MHz) at about 3500.0–3517.3 MHz, centred near 3508.6 MHz, not at 3500 MHz.
- 38.331 V19.4.0 (WF2FTADX):
  - §11.2.2 MeasurementTimingConfiguration (ASN.1 p. 1775, field descriptions p. 1776) has `carrierFreq ARFCN-ValueNR` and the field description "physCellId: Physical Cell Identity of the SSB on the ARFCN indicated by carrierFreq". **The MTC carrierFreq is the SSB frequency.**
  - The code passes the same 633333 to the MTC (`e2-node-identity.cpp:98`). One ARFCN cannot be both Point A (NR Freq Info) and the SSB centre (MTC): the SSB is 20 RBs × 12 × 30 kHz = 7.2 MHz wide and must lie at or above Point A, so its centre is at least 3.6 MHz above Point A. **The two IEs are inconsistent with each other.**
- SSB sync raster:
  - 38.101-1 §5.4.3.1, Table 5.4.3.1-1, p. 89 (PDF 90): "3000 – 24250 MHz | 3000 MHz + N * 1.44 MHz | 7499 + N | 7499 – 22255".
  - 3499.995 MHz gives N = 347.22, which is not an integer, so **633333 is not a GSCN position**. The nearest are GSCN 7846 (3499.68 MHz, NR-ARFCN 633312) and GSCN 7847 (3501.12 MHz, NR-ARFCN 633408).
  - Mitigation: §5.4.3.1 says the sync raster gives SSB positions "used by the UE for system acquisition when explicit signalling of the synchronization block position is not present". An EN-DC-only NR cell gets its SSB frequency explicitly, so an off-raster SSB is not strictly forbidden there. It is a realism smell, not a hard violation.
- Spec-consistent options for the caller to decide. These are illustrations only: I did not check CRB/k_SSB alignment against TS 38.211/38.213.
  - (a) Keep NRARFCN = 633333 as Point A, and set the MTC carrierFreq to an SSB inside the carrier, e.g. 633600 (GSCN 7849, 3504.00 MHz; SSB 3500.4–3507.6 MHz, inside 3500.0–3517.3).
  - (b) Centre the carrier at 3500 MHz on the 30 kHz raster: F_REF = 633334. By Table 5.4.2.2-1 (N_RB even, so k=0 at n_PRB = 12), Point A ≈ 3500.01 − 12 × 0.72 = 3491.37 MHz, so NRARFCN = 632758. The MTC carrierFreq would be an in-carrier GSCN, e.g. 633312 (GSCN 7846, 3499.68 MHz).

### 4. n78 SSB SCS: VERIFIED (30 kHz only)
- 38.101-1 §5.4.3.3, **Table 5.4.3.3-1 "Applicable SS raster entries per operating band for above 3 MHz channel bandwidth"**, p. 91 (PDF 92). Checked against the page image.
  - Row: `n78 | 30 kHz | Case C | 7711 – <1> – 8051`. This is the only n78 row and it has no note.
- **15 kHz is not allowed** for the n78 SSB. Bands that allow both SCS values (e.g. n90, n101) list two rows.
- The index is also correct: 38.331 §6.3.2, `SubcarrierSpacing ::= ENUMERATED {kHz15, kHz30, kHz60, kHz120, kHz240, kHz480-v1700, kHz960-v1700, spare1}`, p. 1281 (PDF 1282). Index 1 = kHz30, which matches `kSsbScsIndex` = 1.

### 5. n78 duplex mode: VERIFIED
- 38.101-1 §5.2, Table 5.2-1 "NR operating bands in FR1" (title p. 37). The n78 row is on p. 38 (PDF 39), checked against the page image: "n78 | 3300 MHz – 3800 MHz | 3300 MHz – 3800 MHz | **TDD**", with no note.

### 6. E-UTRA 20 MHz = 100 RBs: VERIFIED
- 36.101 V19.6.0 (5CR6ETYC), §5.6, **Table 5.6-1 "Transmission bandwidth configuration N_RB in E-UTRA channel bandwidths"**, p. 66 (PDF 67):
  - "BW_Channel [MHz] 1.4 3 5 10 15 20 / N_RB 6 15 25 50 75 **100**"
- 36.104 V19.2.0 (ZE9UAT4R), §5.6, **Table 5.6-1** (same title), p. 26 (PDF 27): the same row, "6 15 25 50 75 **100**".

### 7. EARFCN DL 100 / UL 18100 in band 1: VERIFIED
**Band 1 range and duplex mode:**
- 36.101 Table 5.5-1, p. 43 (PDF 44): "1 | 1920 MHz – 1980 MHz | 2110 MHz – 2170 MHz | FDD".
- 36.104 Table 5.5-1, row on p. 24 (PDF 25): the same row.

**Mapping:**
- 36.101 §5.7.3, Table 5.7.3-1 "E-UTRA channel numbers", p. 206 (PDF 207): "F_DL = F_DL_low + 0.1(N_DL – N_Offs-DL)" and "F_UL = F_UL_low + 0.1(N_UL – N_Offs-UL)".
  - Row: "1 | 2110 | 0 | 0 – 599 | 1920 | 18000 | 18000 – 18599".
  - DL: 2110 + 0.1 × (100 − 0) = **2120 MHz**. UL: 1920 + 0.1 × (18100 − 18000) = **1930 MHz**.
- 36.104 §5.7.3 Table 5.7.3-1: the title is on p. 34 (PDF 35) and the band 1 row is on p. 35 (PDF 36). It is the same row, "1 | 2110 | 0 | 0 – 599 | 1920 | 18000 | 18000 – 18599".

**Band edge (passes, with no margin):**
- Table 5.7.3-1 NOTE 1 (36.101 p. 207; 36.104 p. 36): "the first 7, 15, 25, 50, 75 and 100 channel numbers at the lower operating band edge … shall not be used for channel bandwidths of 1.4, 3, 5, 10, 15 and 20 MHz respectively."
- For 20 MHz, DL 0–99 and UL 18000–18099 are excluded, so 100 and 18100 are the **lowest permitted** channels. The carriers occupy 2110–2130 MHz and 1920–1940 MHz, exactly flush with the band edge. This is valid.

**20 MHz support:**
- 36.101 §5.6.1, Table 5.6.1-1 "E-UTRA channel bandwidth", p. 67 (PDF 68): band 1 row "Yes" for 5, 10, 15 and 20 MHz, blank for 1.4 and 3 MHz, and no note on 20 MHz.

### 8. X2AP ASN.1 enumerations: VERIFIED
36.423 V19.1.0 (3ML7Y29A), §9.3.5 Information Element definitions:
- p. 470 (PDF 471):
  ```
  NR-TxBW ::= SEQUENCE { nRSCS NRSCS, nRNRB NRNRB, iE-Extensions … OPTIONAL, … }
  NRNRB ::= ENUMERATED { nrb11, nrb18, nrb24, nrb25, nrb31, nrb32, nrb38, nrb51, nrb52, nrb65, nrb66, nrb78, nrb79, nrb93, nrb106, nrb107, nrb121,
  nrb132, nrb133, nrb135, nrb160, nrb162, nrb189, nrb216, nrb217, nrb245, nrb264, nrb270, nrb273, ... , nrb44, nrb58, nrb92, nrb119, nrb188, nrb242}
  NRSCS ::= ENUMERATED { scs15, scs30, scs60, scs120, ...}
  ```
  Index 2 = **nrb24** and index 2 = **scs60**. Both are root values, so they are encoded without the extension bit.
- p. 494 (PDF 495):
  ```
  Transmission-Bandwidth ::= ENUMERATED { bw6, bw15, bw25, bw50, bw75, bw100, ..., bw1 }
  ```
  Index 5 = **bw100**, a root value.
- The tabular semantics agree:
  - §9.2.114 NR Transmission Bandwidth, p. 284: "The values nrb11, nrb18, etc. correspond to the number of resource blocks "NRB" 11, 18, etc."
  - §9.2.27 Transmission Bandwidth, p. 248: "bw6 … bw100 correspond to the number of resource blocks "NRB" 6, 15, 25, 50, 75, 100".

## Spec deviations (plain statement)
1. **`kNrArfcn` = 633333 is used as the carrier centre, but X2 `NRARFCN` means Point A** (36.423 §9.2.106). The signalled carrier therefore sits at about 3500–3517 MHz, not centred on 3500 MHz.
2. **The same 633333 is sent as the MTC SSB `carrierFreq`** (38.331 §11.2.2). Point A and the SSB centre cannot be the same frequency, so NR Freq Info and MTC contradict each other.
3. **As a carrier reference, 633333 is off the n78 30 kHz channel raster** (step <2> from 620000), which 38.101-1 §5.4.2.3 makes applicable to a 60 kHz-only carrier with a 30 kHz SSB.
4. **As an SSB frequency, 633333 is off the GSCN sync raster.** This is a soft issue for an EN-DC-only cell, which has explicit SSB signalling.

All other constants (1, 2, 4, 5, 6, 7, 8) match the specs exactly.

## Unresolved questions
- Which fix to take: option (a), keep Point A = 633333 and move the MTC SSB to e.g. 633600; option (b), centre at 3500 MHz with NRARFCN = 632758 and SSB 633312; or keep the current values and record a deviation. The choice depends on whether the ns-3 "centerFrequency 3.5 GHz" has to map to the X2 carrier centre.
- SSB placement relative to the CRB grid (offsetToPointA / k_SSB, TS 38.211 §7.4.3.1 / TS 38.213 §4.1) was not checked. Those specs were not consulted.
- TS 38.104 (the reference that 36.423 cites) is not in Zotero. 38.101-1 was used as an equivalent. Add 38.104 if a BS-side citation is required.

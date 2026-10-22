# M8–M9 contract: user decisions and standards check (2026-10-22 20:13 KST)

This record amends `brainstorm-261022-1739-GH-1-m8-m9-delivery-contract.md`. It covers the user's answers to Q1–Q6 and N1–N7, plus a new standing rule. All spec text was read from PDFs in the user's Zotero library and extracted with `pdftotext`.

**Naming.** In this record, "TS xApp" always means the OSC **Traffic Steering xApp** (`ric-app-ts`). A 3GPP Technical Specification is always written "3GPP TS" plus its number, for example 3GPP TS 38.300. A bare "TS" is never used.

## 1. Decisions recorded

| Item | Decision | Status |
|---|---|---|
| New contract rule | Check every technical decision against the standards and specifications. Use zotero-mcp to read them. If a document is missing from Zotero, ask the user to add it. Do not decide from memory. | **Adopted** (user) |
| Snapshots | Never delete a snapshot without asking the user. | Adopted (user, earlier) |
| TS xApp stray-ack guard | Probe first; patch only if TS xApp crashes. | Adopted (user, earlier) |
| Demo mode | Out of scope. | Adopted (user, earlier) |
| Late or refused control cause | `control-failed-to-execute`. | Adopted (user, earlier) |
| Q2 outage threshold | **Keep −5 dB and check first.** The first R0 run with no controls shows whether any outage fallback happens in the 2-gNB scenario. If one does, the gated runs switch to −1000 and the run report says so. | **Adopted** (user) |
| N1 | Leave rc's ack routing as it is; gate on the wire. | **Accepted** (user) |
| N2 | pandas 1.5.3 + numpy < 2, exact pins, base image pinned by digest. | **Accepted** (user) |
| N6 | The pacer checks Influx row counts before it triggers TS xApp. | **Accepted** (user) |
| N7 | The fork carries NIST's 4 QP patches as its first commit; the installer clones the fork; keep the Dockerfile and Influx-token edits at install time; the token never goes into the public fork. | **Accepted** (user) |
| Q1 / D7 | R0/R1 need at least one control each through the eNB (MN) agent, the serving gNB agent and the target agent; R2/R3 accept the TS xApp's target-addressed controls as a recorded deviation (§2). | **Adopted** (user, 20:30) |
| N3 | Restart the QP pod per run, force single-threaded BLAS in the pod, and have the repeat gate compare a hash of QP's forecasts across the 3 live runs (§3). | **Adopted** (user, 20:30) |
| N4 | Implement a real UL metric: opt-in UL traffic (default off), an ns-3 `DRB.PdcpSduVolumeUL_Filter` counter, and the agent and QP mapping. Required **by R3**; R0–R2 do not wait for it. `RRU.PrbUsedDl` is dropped as QP's second input (§4). | **Adopted** (user, 20:30) |
| N5 | Raw 5 bytes (`%08X%02X` gNB-id, cellId) now, recorded as a known deviation from E2AP §9.2.27; a real EN-DC X2 SETUP REQUEST goes in the post-M9 realism pass (§5). | **Adopted** (user, 20:30) |

## 2. Q1: where a handover command belongs (standards check)

The command belongs at the node that already holds the UE's context, which is the source/serving node. The target never initiates a handover. In EN-DC, either the master eNB or the source gNB can start a gNB change.

- **3GPP TS 38.300 §9.2.3.1** (Fig. 9.2.3.1-1), identical in V18.1.0, V18.11.0 and V19.4.0: "The source gNB initiates handover and issues a HANDOVER REQUEST over the Xn interface."
- **3GPP TS 38.300 §9.2.3.2.1**, step 2, identical in all three versions: "The source gNB decides to handover the UE, based on MeasurementReport and RRM information." Step 0: "The UE context within the source gNB contains information regarding roaming and access restrictions."
- **3GPP TS 37.340 §10.5.1 (EN-DC)**, identical in V18.7.0 and V19.3.0: "The Secondary Node Change procedure is initiated either by MN or SN." In the MN-initiated case, "the MN initiates the SN change by requesting the target SN to allocate resources". In the SN-initiated case, "the source SN initiates the SN change procedure by sending SgNB Change Required message which contains target SN ID information". In both cases the MN sends the RRC reconfiguration to the UE, because the procedure "always involves signalling over MCG SRB towards the UE".
- **3GPP TS 37.340 §3**: Master node = "the radio access node that provides the control plane connection to the core network … a Master eNB (in EN-DC)".
- **E2SM-RC v03.00 §7.6.4.2**: the RIC Control Header carries the UE ID, which is the context identifier at the E2 node that serves the UE.

**What this means for the testbed.** The OSC TS xApp sends the command to the target cell's E2 node (`ts_xapp.cpp:637-643`), which none of these flows describe. It works here only because every agent forwards to ns-3, and ns-3 routes the command by IMSI to the LTE master RRC. That makes the eNB path the most faithful one: the MN performs the change, as in the MN-initiated flow. The serving-gNB path is faithful as an entry point, matching the SN-initiated flow, but ns-3 does not model the SgNB Change Required message.

**D7 (adopted).** R0/R1 require at least one control through the eNB (MN) agent, at least one through the UE's serving gNB agent, and at least one through the target gNB agent (the TS xApp's path). R2/R3 accept the TS xApp's target-addressed controls, and the run report records this as a known TS xApp deviation from 3GPP TS 38.300 and 3GPP TS 37.340. Correcting it faithfully is **mandatory before publication** (§6).

**Q2 support.** 3GPP TS 37.340 §7.7 lists "SCG RLF" among the SCG failure cases. On SCG failure the UE "reports the SCGFailureInformation to the MN, instead of triggering re-establishment". ns-3's −5 dB outage fallback is the simulator's stand-in for this, which is why −1000 (no fallback ever) is less realistic.

## 3. N3: why a restarted QP pod repeats exactly

- **The model is not probabilistic.** QP fits a VAR (vector autoregression) with statsmodels (`qptrain.py:17,99-100,133-135`). The fit is ordinary least squares, a closed-form linear-algebra solve. The ADF stationarity test (`:45-53`) is deterministic too.
- **No random step exists.** The lag search splits the data in time order, the first 75 % for training and the rest for testing (`:96-97`), and tries lags 1–19 (`:107`). A grep of `src/` at 47a35ca and of NIST's QP patch files for `random|seed|shuffle|sample` finds nothing.
- **Three things can still change the output, and each is covered:**
  1. *The input rows.* Stock QP picks rows by wall-clock time. The fork reads a sim-time window. ns-3 is bit-identical across runs (pre-M8 probe), and `simStartEpochMs` is pinned (D10).
  2. *Hidden state.* QP trains once per cell, at the first request, writes `src/<cid>` into the container and never retrains (`main.py:123-125`, `qptrain.py:136-138`). A pod reused from an earlier run would answer with the old model. A restart before each run deletes that file, so the first training always sees the same window.
  3. *Floating-point order.* Multithreaded BLAS can change summation order in the last bits. Forecasts were bit-identical across 3 processes on the laptop (research Q9), but this has not been measured inside the image. Proposed: force single-threaded BLAS in the QP pod (`OMP_NUM_THREADS=1`, `OPENBLAS_NUM_THREADS=1`, `MKL_NUM_THREADS=1`), and have the repeat gate compare a hash of QP's forecasts across the 3 live runs. That way exact repetition is measured, not assumed.

## 4. N4: what QP needs, what exists, and the uplink check

- **QP's inputs.** Two time series per cell, UL volume then DL volume: `thptparam = [thptUL, thptDL]` with `thptUL = pdcpBytesUl`, `thptDL = pdcpBytesDl` (`database.py:123`, `qp_config.ini`). VAR needs at least two variables ("Only gave one variable to VAR", measured), and each must vary, otherwise `adfuller` raises.
- **TS xApp uses only DL.** "We are only considering download throughput" (`ts_xapp.cpp:688`). TS xApp takes the first number of each pair as DL (`:230-235`), but stock QP sends UL first, so stock OSC has the pair reversed. TS xApp parses only unsigned integers (`Uint` handler; `Double` is ignored, `:224-243`), so QP must send non-negative integers.
- **What we have.** The DL cell volume (`QosFlow.PdcpPduVolumeDL_Filter`, `DRB.PdcpSduVolumeDl_Filter`) and `RRU.PrbUsedDl` (`mmwave-enb-net-device.cc:549,562`).
- **What we lack.** Any uplink volume. ns-O-RAN hard-codes `m_pDCPBytesUL(0)` (`mmwave-enb-net-device.cc:502`; `lte-enb-net-device.cc:1231`: "pDCPBytesUL = 0 since it is not supported from the simulator"). scenario-zero also has **no uplink traffic**: each UE gets only a DL `UdpClient` (`scenario-zero.cc:534-545`). A UDP sink on the remote host at port 60000 exists (`:524-530`), but nothing sends to it.
- **The standards.**
  - 3GPP TS 28.552 V20.2.0 defines both PRB counters: §5.1.1.2.5 "Mean DL PRB used for data traffic" = `RRU.PrbUsedDl`, and **§5.1.1.2.7 "Mean UL PRB used for data traffic" = `RRU.PrbUsedUl`**. So `RRU.PrbUsedUl` is an official name.
  - The volume counterpart of QP's UL input is §5.1.2.1.2.1 "UL Cell PDCP SDU Data Volume" = `DRB.PdcpSduVolumeUL_Filter`; the DL one is §5.1.2.1.1.1, `DRB.PdcpSduVolumeDL_Filter`.
  - E2SM-KPM v2.0 §8.3.9 says the ASN.1 `MeasurementTypeName ::= PrintableString(SIZE(1..150,...))` must be "one of the measurement names specified in 3GPP TS 28.552 or 3GPP TS 32.425". KPM §7.9.1 lists `DRB.PdcpSduVolumeUL_Filter` and `QosFlow.PdcpPduVolumeUL_Filter` with unit kbit.
- **Is UL required?** QP's model requires a second varying series, and QP itself defines that series as UL volume. TS xApp's handover decision does not use it. So `RRU.PrbUsedDl` was a stand-in that keeps QP from crashing, not a faithful input.
- **Implementing it, under the user's rule, takes three parts:**
  1. Opt-in uplink traffic in scenario-zero, defaulting off so M5–M7 stay unchanged. UL data does go over mmWave while the UE is attached to a gNB: `McUePdcp` sends UL on the secondary stack unless `LteUplink` is true, and it defaults to false (`mc-ue-pdcp.cc:102-106,222-231`).
  2. A per-cell UL PDCP volume counter in ns-3, reported as `DRB.PdcpSduVolumeUL_Filter`.
  3. Mapping it through the agent and the QP fork reader.
- **Unverified risk.** In ns-3's EN-DC model the split bearer's PDCP lives at the LTE eNB and the gNB holds RLC. The per-cell UL counter must be measured where the DL counter is taken; that has to be checked during planning.

## 5. N5: the cell key TS xApp needs (restated, with a standards check)

- **The problem.** TS xApp builds its cell list (`cell_map`) once at start-up from e2mgr's record of each node's E2 Setup. It takes the node's `e2nodeComponentRequestPart`, finds the gNB id from the node name (`gnb_001_001_0000000N`) inside it, and keeps the 10 hex characters starting there as the cell key (`ts_xapp.cpp:333-373`). Our agents send the 7 ASCII bytes `reqpart`, so TS xApp finds nothing, `cell_map` is empty, and TS xApp skips every control (G4, confirmed).
- **The pick.** The agent writes 5 raw bytes: 4 bytes of gNB id, then 1 byte of cell id. For gNB 2 / cell 2 these are `00 00 00 02 02`. e2term passes them on as hex text, e2mgr stores that text base64-encoded, and TS xApp decodes it to `0000000202`. That is the key. QP emits the same key, and rc turns it back into the target cell. ASCII text would not work, because TS xApp searches the hex rendering of the bytes. In this scope (cell ids ≤ 9) the key is all digits, so letter case cannot break it.
- **Standards check (new).** E2AP v03.00 §9.2.27 says the request part is "a data structure defined by the appropriate 3GPP specification". For a gNB X2 component in EN-DC it should be the encoded **EN-DC X2 SETUP REQUEST, 3GPP TS 36.423 §9.1.2.31**; NG, Xn, E1 and F1 have their own setup requests. Our 5 bytes are **not** a standard encoding. They are the minimum that TS xApp's substring search accepts. A real X2 Setup Request carries the served NR CGIs, which contain the gNB id, but whether TS xApp's byte-level search finds it there depends on PER bit alignment, so this is unverified.
- **Options.** (a) Raw 5 bytes now, recorded as a known deviation from E2AP §9.2.27, with a real encoding in the post-M9 realism pass. (b) Encode a real EN-DC X2 SETUP REQUEST now. That needs X2AP ASN.1 (3GPP TS 36.423, now in Zotero, see §6) and a new asn1c build in the agent, and TS xApp may still fail to find the id. Recommendation: (a).

## 6. Post-M9 realism pass: items required before publication

These deviations are accepted for M8–M9 only. The user requires each to be corrected faithfully to the standards before results are published.

| # | Deviation in M8–M9 | Faithful target | Standard | Source in Zotero |
|---|---|---|---|---|
| P1 | The TS xApp sends the handover control to the **target** cell's E2 node (`ts_xapp.cpp:637-643`). | The control goes to the node that holds the UE context: the master eNB (MN-initiated SN change) or the source/serving gNB (SN-initiated, SgNB Change Required). Needs a TS xApp fork. | 3GPP TS 38.300 §9.2.3.1, §9.2.3.2.1; 3GPP TS 37.340 §10.5.1; E2SM-RC v03.00 §7.6.4.2 | 38.300 V18.1.0/V18.11.0/V19.4.0; 37.340 V18.7.0/V19.3.0; E2SM-RC v03.00 |
| P2 | The agent puts 5 raw bytes (gNB id, cell id) in `e2nodeComponentRequestPart`. | An encoded EN-DC X2 SETUP REQUEST, and TS xApp key extraction that still works with it. | E2AP v03.00 §9.2.27; **3GPP TS 36.423 §9.1.2.31** | **36.423 V18.4.0 (item `83VGITYK`) and V19.1.0 (item `M8YTSAQS`), added 2026-10-22; §9.1.2.31 confirmed present in both** |
| P3 | d = 0: controls apply at the next step, with no whole-loop delay. | A realistic whole-loop delay, together with `UseIdealRrc=false`. | Decided in D5 | — |

## Unresolved questions

None from the user. Items for planning:
1. Where in ns-3's EN-DC model to take the per-cell UL PDCP volume, so it mirrors the DL counter (§4 risk).
2. Whether QP's image uses OpenBLAS or MKL. Set the matching thread variable and confirm with the forecast hash.

## Erratum (2026-10-22 21:45 KST): agent-local reject causes

The "Late or refused control cause" row in §1 dropped part of an answer. At 18:49 KST the user replied "5. as you recommended". The recommendation had three parts:
- demo mode is out of scope;
- when ns-3 refuses a command, or one arrives late, the cause is `control-failed-to-execute`;
- **when the agent rejects a command itself, it uses the specific E2AP cause.**

The user's restatement repeated only the first two. This record now adds the third, and the user re-confirmed it at 21:40 KST.

The agent-local cause values come from E2AP v03.00 §9.2.1. The same enumerated values exist in v02.00, the version on the wire:
- `ricRequest: ran-function-id-invalid` when the RAN Function ID is not 3 ("Requested function Id invalid or not known by E2 Node");
- `ricRequest: action-not-supported` when the control style/action is not 3/1 ("Requested Action not supported by RAN function");
- `ricRequest: control-message-invalid` when the E2SM-RC header or message cannot be decoded ("RAN Function has detected invalid RIC CONTROL REQUEST message").

Gated runs require 0 agent-local rejects (contract C6), so this changes no gate.

## Amendment (2026-10-22 22:30 KST): spec versions for the standards checks

**E2SM-RC: use v03.00; do not look for v02.00.** E2SM-RC v09.00 (Zotero `59S65JXL`), Annex "Change history", p. 400, has the row "2022.11.21 02.00 November 2022 Publication Withdrawn". It then lists the minor CR "NOK.AO-2023.01.11-WG3-CR-0022-E2SM-RC-ASN1-correction-v03" under 02.00 (2023.01.18), and "2023.02.08 03.00 Final version for November 2022 Publication". So v03.00 is v02.00's content republished with that ASN.1 correction. The changes from v01.03 are the CRs listed under 01.03.01–01.03.03 on the same page (policy enhancements, mMIMO non-GoB, RIC Query, UE-group control, E1AP reference and others). Decision (user, 22:29 KST): every RC check cites **v03.00** (Zotero `XRWZU3SS`). Where v02.00 matters, use this change history.

**How rc's ASN.1 compares with v03.00** (checked 22:30 KST against the ASN.1 module extracted from the v03.00 PDF):
- The control-path types the agent uses have identical field lists in both:
  - `E2SM-RC-ControlHeader-Format1` = {ueID, ric-Style-Type, ric-ControlAction-ID, ric-ControlDecision};
  - `E2SM-RC-ControlMessage-Format1` = {ranP-List};
  - `E2SM-RC-ControlOutcome-Format1` = {ranP-List}.
- The file as a whole (`ric-app-rc@a2282ee e2sm/e2sm-rc-2.0.asn`) is **not** identical to v03.00. For example, it lacks the RIC Query definitions that v03.00 contains. Record this as a version gap whenever a check depends on types outside the control path.
- The UE ID types (`UEID`, `UEID-GNB`, `UEID-EN-GNB`, `UEID-ENB`) are **not** defined in E2SM-RC. They come from the common E2SM spec, which rc ships as `e2sm-common.asn`. Zotero holds only "O-RAN E2SM 8.0" (`AIBI24NH`).

**Evidence for the G6 question.** The common E2SM types define a separate `UEID-EN-GNB` (m-eNB-UE-X2AP-ID, globalENB-ID, gNB-CU-UE-F1AP-ID, ...) for a UE served by an en-gNB in EN-DC. rc and the TS xApp use `UEID-GNB` with an AMF-UE-NGAP-ID, the NR standalone form. That looks like a new deviation for our EN-DC scenario. The warmup scout must confirm it against the common E2SM spec, and the user then decides whether it is recorded as an accepted deviation.

**E2SM-KPM v03.00.** It was added to Zotero as item `F82PYZVK` ("O-RAN E2 Service Model (E2SM) KPM 3.0", March 2023). At 22:30 KST the item had **no PDF attachment**, so it cannot be read yet.

## Amendment (2026-10-22 22:50 KST): E2SM common and E2SM-KPM versions

**Withdrawals.**
- **E2SM common:** none. Its change history (v07.00, Zotero `QW6VJ83M`, "Annex (informative): Change History"; v08.00 `AIBI24NH` has the same annex) lists 01.00, 01.01, 02.00, 02.01, 03.00, 03.01, 04.00, 05.00, 06.00 and 07.00. None is marked withdrawn.
- **E2SM-KPM:** none. The v03.00 "Revision history" and "History" (Zotero `F82PYZVK`, PDF now attached) list 01.00, 02.00, 02.01, 02.02 and 02.03 as "Published as Final version". The KPM v07.00 text has no "withdrawn" entry either.

So the older versions were published and later superseded; they were not withdrawn. The user could not obtain them. Decision (user, 22:48 KST): the checks cite the oldest version held in Zotero and record the version gap.

**Which E2SM common version rc's `e2sm-common.asn` matches** (ric-app-rc@a2282ee):
- The file contains the O-RAN UEID choice. That arrived in 02.01 (2022.02.07, "Additional common IEs including O-RAN agreed UEID").
- It lacks the Beam ID (CR-0005, 03.01.01, 2023.05.15) and C-RNTI (CR-0002, 03.01.02, 2023.06.27) additions. Grep counts are 0 in rc's file against 4 each in v07.00.
- So rc's common ASN.1 is from **02.01–03.00** (inferred from the change history).

**`UEID-EN-GNB` and `UEID-GNB` match v07.00** in rc's file field for field, except for the later `cell-RNTI` extension. The check used the order of the field names; the PDF's comment words were ignored.
- `UEID-EN-GNB` = m-eNB-UE-X2AP-ID, m-eNB-UE-X2AP-ID-Extension, globalENB-ID, gNB-CU-UE-F1AP-ID, gNB-CU-CP-UE-E1AP-ID-List, ran-UEID.
- `UEID-GNB` = amf-UE-NGAP-ID, guami, gNB-CU-UE-F1AP-ID-List, gNB-CU-CP-UE-E1AP-ID-List, ran-UEID, m-NG-RAN-UE-XnAP-ID, globalGNB-ID, globalNG-RANNode-ID.

E2SM common **v07.00 is therefore a sound reference** for the UE identity question (G6). The only gap to record is `cell-RNTI`.

**Reference versions for M8–M9 standards checks:**

| Spec | Cite | Zotero item | Gap to record |
|---|---|---|---|
| E2SM-RC | v03.00 | `XRWZU3SS` | v02.00 withdrawn; rc's ASN lacks the RIC Query types |
| E2SM common (UEID, CGI and other common IEs) | v07.00 | `QW6VJ83M` | rc's file is 02.01–03.00; it lacks Beam ID, C-RNTI and `cell-RNTI` |
| E2SM-KPM | v03.00 (wire); v2.0 also held | `F82PYZVK`, `ZL929XRL` | none known |

## Amendment (2026-10-23 00:05 KST): deviations P4–P6, ruled inside the goal-warmup contract

The goal-warmup light scout (`scout-261022-2252-GH-1-m8-m9-warmup-standards-light-scout.md`) found one new deviation and two older ones. At contract approval the user ruled that all three are **recorded, not fixed, in M8–M9**. Each must be corrected faithfully in the post-M9 realism pass before publication, like P1–P3 (§6).

| # | Deviation in M8–M9 | Faithful target | Standard | Zotero |
|---|---|---|---|---|
| P4 | rc and the TS xApp send `gNB-UEID` (the 5GC form) with the IMSI in AMF-UE-NGAP-ID. The agent maps it back to the IMSI. | For a control to a gNB agent, `en-gNB-UEID` (MeNB UE X2AP ID + Global eNB ID); for one to the eNB agent, `eNB-UEID` (MME UE S1AP ID + GUMMEI). Needs an rc change plus ns-3 X2AP/S1AP UE IDs. | E2SM common v07.00 §6.2.2.6, §6.2.3.16/.23/.26; E2SM-RC v03.00 (UE ID → common §6.2.2.6); 3GPP TS 38.413 §9.3.3.1 | `QW6VJ83M`, `XRWZU3SS` |
| P5 | Every agent, the eNB included, registers with the `gNB` choice of Global E2 Node ID and only a Global gNB ID (since M5). | The `en-gNB` choice for the gNB agents and the `eNB` choice for the eNB agent. The TS xApp key path (N5) and e2mgr naming must still work. | E2AP v03.00 §9.2.6 | `WEE5IEXF` |
| P6 | The DL volume row is sent as `QosFlow.PdcpPduVolumeDL`, REAL, in bytes per period (since M6). | INTEGER in kbit. | E2SM-KPM v03.00 §7.9.1; 3GPP TS 28.552 §5.1.3.6.1.1 | `F82PYZVK`, `5SZUBP6M` |

**The UL metric (N4) is faithful, with no deviation:** the wire name is `DRB.PdcpSduVolumeUL` (the 3GPP TS 28.552 V20.2.0 §5.1.2.1.2.1 name with the `_Filter` placeholder left unfiltered, as E2SM-KPM v03.00 §8.3.9 PrintableString requires), legacyName `DRB.PdcpSduVolumeUL_Filter`, INTEGER, in kbit (E2SM-KPM v03.00 §7.9.1). The version gap to record: KPM v03.00 cites the older 3GPP TS 28.552 clause number 5.1.2.1.2.2.

## Amendment (2026-10-23 00:14 KST): QP's DL input, a contract edit during warmup planning

**Finding.** The gNB cell field `QosFlow.PdcpPduVolumeDL_Filter`, which M6 sends as `QosFlow.PdcpPduVolumeDL` (P6), is ns-O-RAN's sum of per-UE **MAC** volume (`mmwave-enb-net-device.cc:1087-1130, 1406-1421` @ace32168). It is not a PDCP count. The PDCP DL counter (`cellDlTxVolume`, `:648-670`) is written only to the CSV. P6 is widened to record this MAC source.

**Decision (user, 00:13 KST): contract edit, In scope 4.** The agent also sends a faithful DL row, `DRB.PdcpSduVolumeDL` (3GPP TS 28.552 V20.2.0 §5.1.2.1.1.1; INTEGER, kbit, E2SM-KPM v03.00 §7.9.1). It is computed in the same ns-3 loop as the UL row, at the PDCP SDU level. QP's two inputs are `DRB.PdcpSduVolumeDL` and `DRB.PdcpSduVolumeUL`, with one definition and one unit. The existing MAC-sourced row is unchanged. Both new rows are appended to the metric map.

## Amendment (2026-10-23 01:03 KST): rulings on the goal-warmup plan review

These rulings follow the collect-only review `kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`.

- **K1, snapshot deletion rule relaxed (user, 00:52 and 01:03 KST).** This follows M0–M7 warmup decision D2 (`plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/plan.md`, Decisions §2).
  - The run may delete **its own intermediate snapshots**: `m0-probe-*`, `m0-branch-*` (including the create-and-delete inside `gate-m0-host.sh:40-49`), `r0-green`, `r2-green`, and any snapshot the M9 run itself creates. It may do so only after that snapshot's evidence is archived on the host, and only when the disk budget requires it (the M0 probe pair is always allowed).
  - **`fresh-install` and `f7-rerun-green` are never deleted.** `r3-green` is kept until M9 is green.
  - If libvirt refuses a delete, stop and ask. Every deletion is logged in `implementation-notes.html` with the space it freed.
  - This replaces "never delete a snapshot without asking" (§1) for M8–M9.
- **K2, disk (user, 00:46 KST).** Before `/goal`, the user frees ≥ 40 GB on `/home` outside the VM images. P0 recomputes the M9 projection from the new number.
- **K4, PDCP specs and deviation P7 (user, 00:46 KST).** The user adds 3GPP TS 38.323 and 3GPP TS 36.323 to Zotero before `/goal`. New recorded deviation **P7**: ns-3 puts an E-UTRA (LTE) PDCP header on its EN-DC bearer, whereas 3GPP TS 37.340 V18.7.0 §4.2.2 (Zotero `E6VYJPXJ`) says NR PDCP is always used for EN-DC bearers other than MN-terminated MCG bearers. P6 strips the header ns-3 actually adds (3GPP TS 36.323 format) and records that. P7 is to be fixed faithfully post-M9, before publication.
- **K11, C1 replay reading (user, 01:03 KST).** The 3 live runs are byte-equal on all components: ledger, IPC samples, traces, the per-step RC multiset, KPM headers and colletStartTime. The RIC-free replay is compared with the live runs on the first three only: ledger, IPC samples and traces.

## Amendment (2026-10-23 01:30 KST): disk timing, permission mode, PDCP specs

- **Disk (user, 01:30; replaces K2's "free ≥ 40 GB before /goal").** The run starts at the current 76 G free. P0 measures the image chain, and every phase exit updates the M9 projection. A negative projection is reported, not a pause. T2 fires only when actual free space would cross the 20 GB floor plus the next growth. At Stop B, the report states the exact number of GB the user must free before M9, and the user frees it then.
- **Permissions (user, 01:25–01:30).** The worktree rules file `.claude/settings.local.json` was removed by the user. The run uses auto mode with no allow or deny rules, as M0–M7 did (`handoff-261022-0416…`; kongming-2105 §1). A classifier refusal of a scripted command is still T8 (pause, never work around it). Snapshot protection is now enforced by the plan's snapshot rule plus the P0 `vm-snapshot.sh` protected list (`fresh-install`, `f7-rerun-green`, `r3-green`), not by a deny rule.
- **PDCP specs (user, 01:23).** 3GPP TS 36.323 V19.0.0 (Zotero `DZFZCTGR`) and 3GPP TS 38.323 V19.1.0 (`MSNDDXJH`) are in Zotero, with PDFs. They are P6's references for SDU-header accounting and deviation P7.

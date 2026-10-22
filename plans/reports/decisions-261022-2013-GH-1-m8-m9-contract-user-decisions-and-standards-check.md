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

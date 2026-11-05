# P10 pre-registration verification (kongming)

Date: 2026-11-06 KST. Reviewer: kongming, advisory only. It ran on Opus 5.5 at xhigh, per the user's CLAUDE.md override of the `fable` routing.
Under review: `plans/reports/researcher-261106-0500-GH-1-p10-pre-registration-draft.md`, with draft rows 147–158 and its open questions.
Pins read: harness `ae16722d`, ns-3 `ea6e46f6`, oran-interface `53253fe`, Testbed `163ef25`. No VM, ssh, virsh, Codex, code, plan, ledger or evidence change was made.
Legend: [V] verified here (file:line, or clause plus PDF page); [I] inference; [B] belief, not verified.

## Verdict: GO-WITH-CHANGES

The draft's spec reading holds on every load-bearing point except one. P7's "only 18 bits makes the NR header distinguishable" is wrong against 3GPP TS 36.323: the E-UTRA 18-bit header has the same bytes as the NR one. The draft's recommendations survive, with the rationale changed for P7 and Option A preferred more firmly for P9.

The draft under-scopes four things:
1. **The AC16 lint.** About 20 of the map's 38 non-vendor names will fail it, not 4.
2. **The V3 route.** No gate can run row 151's V3 judge at the P9 pins as the N4 gate stands.
3. **Option A's cost.** It is a second metric-map change, so it costs a second agent rebuild and kpimon reinstall.
4. **Adoption gates for UseIdealRrc.** The draft's set does not cover r0, r1, r2 or s10 under real RRC.

Together these make three revert cycles likely, not two. Only the neighbour-loop UB fix needs a contract amendment (Amendment 4).

## 1. Spec claims, verified

| # | Draft claim | Verdict | Source |
|---|---|---|---|
| 1 | QosFlow.PdcpPduVolumeDL counts PDCP PDU bits CU→DU, excludes DC volume, is an integer in Mbit, has object GNBCUUPFunction/NRCellCU, and its NRCellCU form is "2-split only" | **True** [V] | 28.552 V20.2.0 §5.1.3.6.1.1, PDF pp.196–197; §5.1.3 is "valid for split gNB deployment" (p.188) |
| 2 | 28.552 has no MAC-layer data-volume measurement | **True** [V]. "MAC SDU" appears only in a delay formula (p.43) and "MAC PDU" only in an annex (p.402); TB.* are counts (p.112) | full-text search of `5SZUBP6M` |
| 3 | KPM v03.00 §7.9.1 replaces Mbit with kbit, INTEGER, for DRB.PdcpSduVolumeDL/UL, QosFlow.PdcpPduVolumeDL/UL, the X2 and Xn variants and 32.425 DRB.PdcpSduVolumeDl/Ul | **True** [V]. KPM's clause numbers are stale or duplicated (the DL cell row is cited as 5.1.2.1.2.1, and two rows are cited as 5.1.2.1.2.2), but the names are unambiguous | KPM `F82PYZVK` p.14 |
| 4 | Vendor rename is the spec-honest P6 fix | **True** [V/I]. No clause gives a home for a MAC volume on a non-split, all-DC en-gNB. KPM §7.10.1 DRB.RlcSduTransmittedVolumeDL is RLC-acked and kpm_sim-owned (`lint-metric-map.py:31-35`), so it is a new counter, not a rename | KPM p.15 |
| 5 | NR PDCP is mandatory on the MN-terminated split bearer | **True** [V]: "NR PDCP is always used for all other bearers" | 37.340 `PZYCKMNI` §4.2.2 |
| 6 | SN length is 12 or 18 for AM DRBs, chosen by RRC; Window_Size = 2^(SN−1) | **True** [V]. No clause forces either width for this bearer | 38.323 V19.1.0 Table 6.3.2-1 p.45, §7.2 p.49; 38.331 V19.4.0 PDCP-Config p.1044, field descriptions p.1048 |
| 7 | The NR 12-bit DL header is byte-identical to the E-UTRA 12-bit DL header | **True** [V]: D/C,R,R,R,SN(4) then SN(8). The UL differs only by AILC | 38.323 Fig 6.2.2.2-1 (PDF p.40); 36.323 V19.0.0 Fig 6.2.3.1/6.2.3.2 (PDF p.40) |
| 8 | "Only 18 bits makes the NR header distinguishable on the bytes" | **False** [V]. The E-UTRA 18-bit header is D/C,P,R,R,R,R,SN(2) then 2 SN octets, which equals NR's D/C,R×5,SN(2) whenever P = 0 (no LWA). No SN width distinguishes NR from E-UTRA on the bytes; 18 bits only distinguishes P7's header from cp2's 12-bit one | 36.323 §6.2.11, Fig 6.2.11.1 (PDF p.45); 38.323 Fig 6.2.2.3-1 (PDF p.40) |
| 9 | The SN-wrap bugs are real | **True** [V]. `std::map<uint32_t,…>` keyed by raw SN (`lte-rlc-am.h:208`, filled at `lte-rlc-am.cc:1808`) iterates 0, 1 before 4094, 4095. `SN >= SN_1 - 2` (`lte-enb-rrc.cc:1105`, `lte-ue-rrc.cc:1774`) promotes to int, so at SN_1 ∈ {0, 1} the wrapped predecessors are silently left out. It is an under-inclusion, not a crash | code |
| 10 | DRB.PdcpSduVolumeDL counts "bits entering the NG-RAN PDCP layers" (NRCellCU, non-split); its X2 variant counts SDU bits "transferred … through X2 interface" "in DC-scenarios" | **True** [V]. Annex A.25 (p.403) gives the purpose: "for split bearers, PDCP data is transferred between the MN and the SN … the data volume transferred between MN and SN should be counted." That supports Option A's reading. The split-only per-interface DRB.X2uPdcpSduVolumeDl (§5.1.3.6.2.3, p.198) is counted in the CU-UP, which is the SN-terminated view, so it does not apply here | 28.552 pp.183–186, 198–199, 403 |
| 11 | P15: Table 7.8-1 maps Style 1 → Action 1/Header 1/Message 1 and Style 3 → 3/1/2; the CGI "shall be included" for single-cell measurement types | **True** [V]. The agent already advertises both styles with these formats (`kpm-ran-function-description.cpp:60-62`) | KPM p.13, p.9 |
| 12 | Row 100's 8 sites | **True** [V]: `gate-m6-kpm.sh:100`, `gate-m7-multignb.sh:204`, `gate-r0-rc-scripted.sh:206`, `gate-r1-rc-multi-control.sh:174`, `gate-p12-kpm-period.sh:138` and `:212`, `gate-e2i-interop.sh:278`, `ts-rung-lib.sh:85` | code |
| 13 | c = 3 × X2LinkDelay, with no Uu message on the path | **True** [V] (the draft had it as [I]). The path is three X2 one-way legs at 1 ms (`mmwave-point-to-point-epc-helper.cc:224`; not overridden in scenario-zero), with no scheduling in between: (1) `ApplyExternalHandover` → `SendMcHandoverRequest`, MN → S-SN (`lte-enb-rrc.cc:4570-4619`); (2) `DoRecvMcHandoverRequest` → `SendHandoverRequest` → `PrepareHandover` → X2 HandoverRequest, S-SN → T-SN (`:5150`, `:5290`, `:774`); (3) the Ack, T-SN → S-SN, then `RecvHandoverRequestAck`, which fires the trace at `:909` | code |

## 2. P6 counsel

- **The rename is honest, and it fits the contract.** P6 is defined as "MAC-sourced DL volume row sent as QosFlow.PdcpPduVolumeDL, REAL bytes per period" (`run-report-261029-0535…:65`). Once no node sends a MAC value under that name, the deviation is gone, so P6 ends "fixed". AC16's lint already contemplates an `ns3.*` class (Stop A′ ruling 4). **No contract amendment is needed.**
- **It does depart from phase-10 Design's first option.** Design says "report the PDCP PDU volume … as QosFlow.PdcpPduVolumeDL". Record a user ruling (Q1).
- **Indication bytes do not change.** The agent encodes indications by measID (`kpm-indication-message.cpp:144-145`, `:194-195`), so in-place renames keep the order and measId, and the KPM T/T golden stays byte-identical. What changes is the RAN function description names (the E2 Setup bytes), the Influx field names, and kpimon's `enb-kpm-measurements.json`. The IPC keys stay, so the cp3 ipc component is untouched by P6.
- **Under-scoped: the lint covers every name (AC16), not four.** Spot checks against 28.552 [V] show these will fail:
  - CARR.PDSCHMCSDist.Bin1–6: 28.552's form is `.BinX.BinY.BinZ` (p.121);
  - L1M.RS-SINR.Bin*: no hit;
  - DRB.BufferSize.Qos, DRB.PdcpPduNbrDl.Qos and TB.ErrTotalNbrDl: no hit;
  - DRB.EstabSucc.5QI and DRB.RelActNbr.5QI on the **eNB**: these are NRCellCU/5QI names (p.115–116) on an E-UTRA node;
  - Tot.PdcpSduNbrDl and DRB.PdcpSduBitRateDl: probably non-standard [I];
  - RRU.PrbTot*: a percentage (0–100) in 28.552 (p.45, p.49), so the unit must be checked against what ns-3 sends.

  Expect roughly 20 of 38 names, and about 30 map rows, to be renamed. Pre-register the rule so that P6 needs no per-name ruling: **a 3GPP-style name with no readable clause, or whose object, RAT, layer, unit or type disagrees, is renamed in place to `ns3.<section>.<name>`, keeping its order and measId.** Budget about 1–2 h of agent time to build the registry with clause and page for each name before the P6 code.
- **Registry fields the draft's row 147 lacks:**
  - a per-UE justification taken from the KPM §7.9 conversion table (pp.13–14: data volume, throughput, delay, radio resource and MCS are "measured per UE"), so that a UE-list row may use a cell measurement only when §7.9 allows it;
  - a rule for `dcExcluded`: such an entry is forbidden on every node, because every bearer here is DC;
  - the `_Filter` name form (filters as KPM labels; the bare name is the total).
- **Staleness:** add the registry file to `KPIMON_TESTBED_PATHS` (`scripts/gates/kpimon.sh:36-37`), because the lint that the kpimon installer runs will read it.
- **Hazard confirmed [V]:**
  - the agent image copies the map (`ns3_e2_agent/Dockerfile:92`);
  - the kpimon installer runs the lint (`install_xapp_kpi_monitor.sh:193`);
  - kpimon's stale key includes the map and the lint (`kpimon.sh:36-37`).

  So P6 costs an agent rebuild, a kpimon reinstall, and M5, M6 and M7. It needs no M4, because ns-3 is unchanged.
- **Row `:128` (eNB, DRB.PdcpSduVolumeDl):** rename it in P6. Fixing its value to true MN SDU bits is a realism gain, since the eNB is the real PDCP host. But it needs ns-3 or oran-interface code and a read of 32.425, so record it as a follow-up outside M10.

## 3. P7 counsel

- **SN width.** The spec allows both widths, and the scenario's rate makes 12 bits adequate: about 2,000 PDU/s per UE gives a 2,048-PDU window of about 1 s, far beyond the 1 ms X2 delay plus RLC AM recovery. So the width is a configuration choice, not a mandate.
- **18 bits is still the better pre-registration**, for these reasons, in order:
  1. it is the usual configuration for NR AM eMBB DRBs in EN-DC [B, medium-high];
  2. it makes P7 visible in the cp3 diff (1,311-byte PDUs);
  3. live runs never wrap (131 s), so the wrap fix is trace-neutral, and the rollover is exercised only by (c).
- **Rewrite the rationale and row 149's "why".** Bytes cannot prove NR against E-UTRA at any width (claim 8). Row 149 proves only that P7's header replaced cp2's. The NR-ness is carried by check (a) on the `NrPdcpHeader` class and its 38.323 layout.
- **AC16's "traces show an NR PDCP header" is satisfied** as "the traces show the 38.323 §6.2.2.3 format at the registered width". Record that interpretation; no amendment is needed.
- **Non-vacuity of (c).** Show it by running a 12-bit analogue of (c)'s map-ordering and predecessor cases at `m10-cp2`, and keep the red output. Code reading alone is not enough.
- **A consumer the draft missed:** `scripts/gates/rung-config.json:80-81` (N4 `pdcpHeaderBytes: 2` and its 36.323 source). Nothing reads it [V grep], but it is stale metadata, so update it in P7's harness commit, alongside row 150.

## 4. P9 counsel

**Strictly, the en-gNB's DRB.PdcpSduVolumeDL is 0 [V/I].**
- The clause counts bits entering the PDCP layer of the NRCellCU (p.183).
- The ns-3 en-gNB hosts no PDCP for any bearer: `McEnbPdcp` is the MN's (`mc-enb-pdcp.cc:243-293`).
- A.25 says split-bearer MN↔SN transfer is exactly what the X2 counters are for.

**Option A, recommended.** DRB.PdcpSduVolumeDL/UL = 0 at every en-gNB, and DRB.PdcpSduVolumeX2DL/UL carries the via-SN SDU bits. The predictor reads X2DL with the same formula.
- It ends P9 "fixed" and keeps open point 2's formula.
- It is also the better TS input: it is the volume the NR cell actually carries, with no LTE-leg credit and no double credit for UEs listed by two gNBs during an SN change.
- Expected effect [I]: per-cell values about halve (`perPckToLTE` 0.5, not overridden; `mc-enb-pdcp.cc:109-113`, `:277`), with about 1–2 % binomial noise. R3′'s cell ratios (about 2:1, or about 1:1) stay outside the 1.05–1.15 margin band, so the decision and the IMSI selection very probably hold.
- It needs a T3 ruling on `r3p-scenario.json`: `counter` (`:8-10`), `formula.dl` (`:13`), `observationChange.transform` (`:29`), and the `_comment`'s clause citation (`:2`, §5.1.2.1.1.1 → §5.1.2.1.1.2).
- Record "the corrected counter" (contract open point 2, `:190`) as meaning the measurement that carries the en-gNB's routed volume. No amendment is needed unless the user reads open point 2 as naming DRB.PdcpSduVolumeDL itself.

**Option B is weaker than the draft says.** Keeping the name with the via-SN bits still credits MN-hosted PDCP SDUs to the en-gNB's DRB.PdcpSduVolumeDL, which is P9's own definition. Under the clause reading, P9 would end narrowed but not fixed, and the contract allows "listed" only under an approved substitution (§7). So B is a contract Decision, not a "recorded interpretation, no T3".

**Variant A′.** Rename rows `:56-57` in place to the X2 names and report no DRB.PdcpSduVolumeDL/UL on the en-gNB at all.
- It is leaner: no always-0 fields, and no appended rows.
- It loses A7's explicit "own-PDCP volume is 0" evidence, and drops two measurements that a real en-gNB would advertise (it may host SN-terminated bearers).
- I prefer A. A′ is acceptable if the user prefers KISS.

**Counting point.** Counting at the MN at first send, with the SN cell ID (the draft), aligns exactly with the audit truth. Disclose that S-SN→T-SN forwarding during an SN change (`lte-enb-rrc.cc:1160-1209`) is not re-counted. Counting on X2-U receipt at the SN would be more literal, but needs a 1 ms-shifted truth and double-counts forwarded PDUs. Keep MN-side counting.

**What the draft missed for P9:**
1. **No route runs V3 at the P9 pins [V].**
   - `check-pdcp-volume-totals.py` runs only inside `gate-n4-ul-metric.sh:191`.
   - That gate's uloff half requires equality with the pre-N4 reference (K19; header `:3-6`). After P7 changes every PDU size, that equality cannot hold.
   - Register a route before P9 code: either a `--part v3` that runs ulon, V3 and the no-RV check against a uloff run at the same pins, or a re-pointed reference. Either way it gets its own row.
2. **N4's V5 rule encodes QP's G1 inputs** (`check-n4-v5-windows.py:29-30`, "neither column all zero"). Under A it fails by construction on the en-gNB DL/UL. Row 152 re-points it to the X2 names. Record that this changes the future real-QP input mapping (out of M10 scope).
3. **A appends map rows,** so P9 repeats P6's agent rebuild, kpimon reinstall and M5–M7 (section 7).
4. **The KPM T/T golden.** Appended cell rows break `kpm-report-period-test`'s byte-identity against `fixtures/kpm-tt-golden-gnb2-seq26-35.txt`. It is built (`CMakeLists.txt:82`) but run by no gate and not at image build (`Dockerfile:94-97`). Regenerate it, or record it as stale.

## 5. P15 counsel

The spec basis and the sites are verified. Three additions:
- **Row 153's C.** C comes from "that node's E2 Setup X2 request part in the same capture". Confirm, for every site, that the capture starts before the agents' E2 Setup. Where it does not, the check must fail closed with a clear reason, not pass on C = 0.
- **The agent side.** Add a unit case in which a Format 1 action naming a foreign CGI is answered not admitted. Row 153's foreign-CGI fixture judges only kpimon's request.
- **p12 (b)** stays a SUBSCRIPTION FAILURE case. It is not a row-100 site, so row 153's admission conjunct applies at p12 a and c only, as drafted.

## 6. UseIdealRrc and c

**The rule "any offset ≠ 3.0 ms is a Stop" is right.**
- c sits in plan R-1 and I-2, so changing it after its phase starts is PAUSE T3 (`plan.md:156`).
- AC17 still makes `false` mandatory once the probe passes. The Stop is only about how I-2 is re-registered.
- Two additions:
  1. An applied line with **no** HandoverStart is also a Stop.
  2. Real RRC raises the chance that `PrepareHandover` meets a state it does not handle. It is fatal outside CONNECTED_NORMALLY, CONNECTION_RECONFIGURATION and HANDOVER_JOINING (`lte-enb-rrc.cc:789-790`). A crash is a failed probe (S-R), not a c question.

**Probe route (missing from the draft).**
- `scenario-zero.cc:492` hard-sets `true` after `cmd.Parse`, so a command-line flag cannot reach it. `MmWaveHelper`'s own default is `false` (`mmwave-helper.cc:218-221`).
- Run the probe on the candidate UseIdealRrc commit itself: the `:492` line deleted, on a branch, built in the VM. Echo the effective value. If it passes, pin that same commit. No switch then ever lands (R8).

**Gates after adoption (missing).** Add r0, r1 and r2 singles and one s10 `--dev` run to the draft's M4, M5–M7, R3′ single and wall-rate measurement.
- Real RRC changes attach timing for 30 UEs.
- It may also change outcomes that r0, r1 and r2 pre-register.
- It is untested against the frozen cp1 identity map (row 107's cross-check).

  A red found here costs one run. A red found in P11's cp3 chain costs a chain. [I]

## 7. Budget and revert plan (corrects P09 review §7.1)

Every metric-map or lint change forces an agent rebuild, a kpimon reinstall and M5–M7 (section 2). That makes 5 kpimon installs in P10 under Option A: P6, P9-A, P15, D-06b-1 and the node tag.

Projection from about 79 GiB free after a revert [I; agent image cost unmeasured, assumed 1–2 GiB]:

| Cycle | Contents | Projected spend | Projected end |
|---|---|---|---|
| 1 | prefix 24 + D-R3-1 1–3 + UB fix 3–4 (if ruled) + P6 5–7 + P7 4–5 + P9-A 6–9 (including the V3 run and R3′ single) | about 43–52 GiB | about 27–36 free |

- P15's kpimon build and its p12 then start near or below the 34 GiB guard. **Revert between P9 and P15.**
- **Cycle 2:** prefix + P15 + D-06b-1 + kpimon tag. The node-tag build starts at about 38. The TS xApp build then falls below 34. **Revert before the TS serving cell.**
- **Cycle 3:** prefix + TS + the UseIdealRrc probe + adoption gates (section 6). It ends at about 40 free.

Wall time is about 14–17 h, against 11–13 h before. Pre-register the three cycle points before P6. The 34 GiB start guard remains the binding rule. Re-read free /home when the running D-R3-1 chain ends.

## 8. Rulings to put to the user

Rule Q1–Q4 and the UB as one batch, before the next commit after D-R3-1. Q5–Q8 are controller rulings: record them with their rationale and show them at the next Stop.

1. **UB: the neighbour-loop UB (contract Amendment 4). User. Before the next ns-3 or agent commit (the slot before P6); hard deadline before P11 banks references.**
   - Recommended: fix it, as its own ns-3 commit right after D-R3-1, with a ledger row: in r2 and r3p, every UE tick whose node map holds 2 cells reports exactly 1 neighbour, and a 0-neighbour fixture fails. Gates: M4 and M5–M7 (about 1 h, 3–4 GiB).
   - Alternative: disclose only. This is the default if the user does not answer.
   - Trade-off: a small cost removes a cellId-order artefact from the ipc component and the KPM of every 2-gNB reference. Deferring to Stop B means "never in M10", because tags never move.
2. **Q1: P6. User. Before P6's rows (147) and code.**
   - Recommended: no QosFlow.PdcpPduVolumeDL on any node. The MAC value is renamed in place to `ns3.du.macVolumeDl`. Under the pre-registered rename rule in section 2, every name that fails the lint becomes `ns3.*`.
   - Alternative: keep Design's wording and source a PDCP PDU volume. Rejected: the clause is split-only and excludes DC (claim 1).
   - Trade-off: about 30 rows of name churn in Influx and E2 Setup, against a lint that is honest by construction. No amendment is needed.
3. **Q2: P9. User, with T3. Rule it with this batch, because it fixes the revert plan and the registry entries; hard deadline before P9 code.**
   - Recommended: Option A, with the T3 change of `r3p-scenario.json` and the recorded reading of open point 2.
   - Alternatives: A′ (section 4), or B. B leaves P9 not fixed under the clause reading, so it would need a contract Decision.
   - Trade-off: A costs a second agent and kpimon cycle and moves the cp3 r3p reference onto a new key. B is cheaper, but keeps an MN-credited 3GPP counter.
4. **Q3: AC16 for eNB rows. User. Before P6.**
   - Recommended: record that "28.552 clause" in AC16 means the node's RAT clause: 28.552 for NR, 32.425 for E-UTRAN (KPM §7.4.2.2, p.9 names both). Ask the user to add 3GPP TS 32.425 to Zotero, as with Stop A′ ruling 6.
   - Fallback if 32.425 is not added: eNB names whose type and unit KPM §7.9.1 lists keep their name, with the clause marked "unverified against Zotero" (AC20). Every other eNB 3GPP-style name is renamed to `ns3.*`.
   - Trade-off: a few minutes of the user's time, against weaker eNB rows.
5. **Q4: P7 SN width. User. Before P7's rows (148–150) and code.**
   - Recommended: 18 bits, DL and UL, on every MC DRB, with the rationale in section 3.
   - Alternative: 12 bits. P7 then changes no trace bytes and SN types stay `uint16_t`, but the cp3 diff cannot show P7, and the wrap paths stay live (a wrap every 2 s).
   - Trade-off: wider types and every PDU size moving, against an invisible fix.
6. **Q5: P7 check (b) baseline. Controller. Before P7 code.**
   - Recommended:
     - run (b) at `m10-cp2` first;
     - where cp2 loses no SDU in b1 or b2, P7 must lose none there;
     - where cp2 loses SDUs, judge byte equality, no duplicates and in-order delivery of the delivered SDUs, and record both loss counts.
   - Alternative: judge byte equality only.
   - Trade-off: a strict non-regression rule only where it is sound. Loss counts are not comparable across a PDU-size change.
7. **Q6: placing the SN-wrap fix. Controller. Before P7 code.**
   - Recommended: inside P7's commit, disclosed. Design already scopes "SN width … with its rollover", and at 18 bits the fix is trace-neutral in live runs.
   - Alternative, required if Q4 picks 12 bits: its own commit just before P7, with a bisection slot.
8. **Q7: judging c under UseIdealRrc (row 156). Controller registers it before the probe; the user is informed.**
   - Recommended: the draft's rule plus section 6's two additions, the probe on the candidate commit, and the extra adoption gates.
   - Alternative: pre-register a widened c now. Rejected: it would weaken I-2 without evidence.
9. **Q8: row 158, the hex-letter amendment to row 139. Controller (additive, not #9). Before the TS serving-cell commit.**
   - Recommended: as drafted. Copy only `ranName` and the request part into the public Testbed fixture, labelled cp2-era, with the D-R3-1 twin.
   - Also confirm that P09 review hand-off 7.3 item 6 was done: the replay for gNB IDs 2–11 at the D-R3-1 constants.

Also register before code, without a user question:
- the V3 route (section 4, item 1), before P9;
- the three revert points (section 7), before P6;
- one line in P11's diff rule, now. AC16 says components not explained by a T-C fix stay equal. The rule should name D-R3-1, D-06b-1 and R-4 as fixes that Stop A′ ruled into P10 (T-A residuals, so no amendment), and the UB fix only under Amendment 4. Otherwise P11's review will flag them.

## 9. Row edits to the draft

- **147:** add the rename rule, the per-UE (§7.9), `dcExcluded` and name-form fields, eNB entries per Q3, and the kpimon stale-path change. Replace "Today's map fails at 4 rows" with the measured count.
- **148:** prove (c)'s non-vacuity by running it at cp2; apply (b) per Q5.
- **149:** reword "why" (section 3). Verify the stats file and columns (`DlE2PdcpStats.txt`) before registering, because the draft has them as [I].
- **150:** also cover `rung-config.json:80-81`.
- **151:** add the run route, and the counting-point disclosure (section 4).
- **152:** add `_comment:2`, `formula.dl:13` and the G1 note for N4 V5. It is T3.
- **153:** C needs the setup inside the capture, or fails closed; add the agent's foreign-CGI unit case.
- **156:** a missing HandoverStart is also a Stop.
- **157:** probe on the candidate commit; then the extra adoption gates of section 6.
- **158:** keep the fixture minimal; confirm the replay for IDs 2–11.
- **New row, if the UB is ruled:** the check in section 8, item 1.

## Assumptions
- **About 20 of 38 names fail a strict lint** (medium). This comes from spot checks of 12 names; the exact count needs the registry.
- **18 bits is the common EN-DC eMBB setting** (medium-high, belief). If the user wants spec-only grounds, both widths are equally valid.
- **R3′'s decision survives P9-A** (medium). This is ratio arithmetic, not a run. The P9 R3′ single decides; a run without a handover is red, and a scenario change is T3.
- **Agent image disk cost of 1–2 GiB and kpimon reinstall of about 3 GiB** (medium). The cycle split depends on them; the 34 GiB guard is authoritative.
- **Real RRC does not change RNTI order** (medium). RNTIs are allocated at RACH, which is independent of the RRC protocol. Row 107's cross-check in the adoption gates verifies this.

## Unresolved questions
1. The user's rulings on the UB, Q1, Q2, Q3 and Q4 (section 8).
2. Will the user add 3GPP TS 32.425 to Zotero before P6?
3. Does the user read contract open point 2's "the corrected counter" as allowing DRB.PdcpSduVolumeX2DL (Option A), or as naming DRB.PdcpSduVolumeDL (which would need an amendment)?
4. Which route does the controller register for running V3 (row 151) at the P9 pins?
5. What is the measured disk cost of an agent image rebuild? It decides whether cycle 1 can still reach P15.

## Cross-check of Codex (2026-11-06)

Input: Codex's read-only answer to the five P10 user questions (controller scratchpad `codex-p10-questions.txt`, 75 lines). Every new Codex code claim was re-read at the same pins. Kongming ran on Opus 5.5 at xhigh. No code, plan, ledger, evidence, VM or Codex was touched.

### C.1 Codex's new claims, verified

| # | Codex claim | Verdict | Evidence |
|---|---|---|---|
| 1 | UB: with exactly 8 map entries `nNeighbours` stays 8 although 7 are neighbours, and CSV padding uses that count | **True** [V], narrow impact | `mmwave-enb-net-device.cc:993-997`, padding `:1025-1028`. The serving cell is always in the map, because `:958` inserts it through `operator[]`. The padding feeds only the offline CSV (`m_forceE2FileLogging`, `:1050`); `enableE2FileLogging` defaults false (`scenario-zero.cc:274-275`, `:483-486`) and no gate sets it [V grep]. The E2 list length is the emitted count. Maps of 8 or more entries are live in s10 (`--nMmWaveEnbNodes=10`), where the `--begin()` UB in a larger tree may drop more than one neighbour [I] |
| 2 | r2 live1 tally: node 2 one neighbour in 416 records, node 3 zero in 82 of 178 | Not re-tallied [B] | Consistent with the P09 review's mechanism (dropped when the serving cell has the higher cellId and the strongest SINR) |
| 3 | The MAC value includes HARQ retransmissions | **True** [V] | `mmwave-phy-trace.cc:262` adds `m_tbSize` for every TB, any RV (Codex cites `:250`, the function head); emitted at `mmwave-indication-message-helper.cc:132` (cell) and `:88` (UE) |
| 4 | `/cuUp` credits MN-hosted PDCP volume to the SN, so a source-section rule cannot certify ownership | **True** [V] | `mmwave-enb-net-device.cc:672-693`; the comment at `:672-674` says so. My §2 rule names "object", but I did not apply it to rows `:56-57` at P6 |
| 5 | Both legs fire the same MN PDCP trace | **True** [V] | `mc-enb-pdcp.cc:221` (LTE leg) and `:238` (X2 leg), same `(rnti, lcid, size)`. The calculator cannot split legs, so P9 needs a leg-specific count keyed by `m_ueDataParams.targetCellId` |
| 6 | V3 pools overlapping cells and judges their sum | **True** [V] | `check-pdcp-volume-totals.py:160-192` unions samples sharing a UE at one read and allows `500 * len(g)`; the truth goes to `owners[0]` (`:152-153`), an arbitrary cell. Volume moved between overlapping cells passes |
| 7 | Forwarding can strip a PDU and re-enter MN PDCP | **True** [V] | `lte-enb-rrc.cc:1227-1239` (LTE→NR switch: header removed, `TransmitPdcpSdu`, new SN, a second `m_txPdu` for the same SDU). My §4 covered only S-SN→T-SN (`:1219`) |
| 8 | The draft's packet-tag discriminator is stripped | **True** [V] | `lte-enb-rrc.cc:1190` `RemoveAllPacketTags()` runs before `ForwardRlcPdu` (`:1219`), which carries the header-bearing PDU. At the T-SN, a later SN change re-reads it at `:1184` and `lte-rlc-am.cc:1806` [I], so the draft's "tag, else `NS_FATAL_ERROR`" (draft line 86) would abort on a repeated SN change (r1, r2) |
| 9 | 12 bits minimises SN and status changes | **True** [V] | SN fields are `uint16_t` (`mc-enb-pdcp.h:226-227`, `:235`; `mc-ue-pdcp.h:195-196`, `:201`). The shared `LtePdcp::Status` is `uint16_t` (`lte-pdcp.h:103-104`). The X2 SN Status Transfer writes 16-bit SNs with a 4,096-bit bitmap (`epc-x2-header.cc:1810-1823`, `epc-x2-sap.h:104`). 18 bits must widen these or fail closed. The transfer walks only PDCP-hosting DRBs (`lte-enb-rrc.cc:919-932`), so it is latent with one eNB, but it cannot be left truncating |
| 10 | DL every 500 µs | **True** [V] | `scenario-zero.cc:691`: 2,000 PDU/s per UE, so a 12-bit SN wraps every ~2.05 s |
| 11 | The eNB's DRB.PdcpSduVolumeDl comes from PDU bytes | **True** [V] | `lte-enb-net-device.cc:1110-1111` has no header subtraction, unlike the gNB at `:677` |

Codex's citation drift is minor: `:250` should be `:262`, `:1108` should be `:1110-1111`, and `:1231` should be `:1227-1239`.

### C.2 Where my report was wrong
1. **Q3 fallback.** It was too permissive and broke my own §2 rule ("no readable clause → rename"). Row `:128` disproves it: KPM §7.9.1 lists the name as kbit INTEGER, yet the value is PDU bytes (claim 11).
2. **P6 registry.** It had no owning-node or counting-event field. At P6, rows `:56-57` would therefore be either certified falsely or renamed, and then renamed back at P9.
3. **P7 discriminator.** I did not test the draft's tag mechanism, and it fails (claim 8).
4. **Q4.** I under-weighted the 18-bit widening surface (claim 9). I also over-weighted cp3 visibility, which by my own claim 8 proves only "changed", not "NR". Reason 3 was backwards: at 18 bits the rollover fix is dead code in live runs; at 12 bits it is exercised every ~2 s.
5. **P9 counting point.** I missed the switch re-entry path (claim 7).
6. **UB regression.** My "2-cell map → exactly 1 neighbour" check is too narrow.

### C.3 Where Codex is wrong or incomplete
1. **UB.** The 8-entry miscount touches only the ungated CSV. The live E2 harm at 8 or more entries is the same `--begin()` UB. Fix both anyway.
2. **Q4.** At 12 bits the header switch is byte-neutral, so a separate rollover commit is worth it mainly because it enables a **byte-identity check** (C.4, Q4). Bisection alone is not the reason. Codex also does not say that, at 12 bits, AC16's trace clause passes at cp2 too, or how "verified MC consumer paths" is checked when a missed consumer is silent.
3. **Q2 "first send".** It has a natural definition (C.4, Q2) and need not stay open.
4. **The P6/P9 dependency.** "Resolve before code" needs a mechanism. A pending marker suffices; no reorder is needed.

### C.4 Final recommendation per question

**UB: fix it, as its own ns-3 commit before P6 (Amendment 4).**
- Iterate with a `reverse_iterator`. Count the eligible entries as those whose cellId is not the serving cell, cap them at 8, and pad from the emitted count.
- Regression:
  - a unit case over map sizes 1, 2, 8, 9 and 10, with equal-SINR ties;
  - in r2 and r3p, every UE tick reports exactly min(8, eligible) neighbours, and a 0-neighbour fixture fails;
  - one s10 run with no drops.

**Q1: rename.**
- The MAC value gets an honest name, such as `ns3.du.macTbVolumeDl` (TB bits, HARQ retransmissions included).
- The registry adds `owningNode` and `countingEvent`.
- Rows `:56-57` (en-gNB DRB.PdcpSduVolumeDL/UL) carry a `pendingFix: P9` marker. P6's lint reports them as named expected failures, neither passes nor renames. P9's row and P11 require the marker list to be empty.

**Q2: Option A, with the T3 change of `r3p-scenario.json`.**
- **Counting definition.** X2DL(c) counts 8 × (PDU bytes − header) for every PDCP PDU that the MN submits on the X2 leg to cell c (`DoTransmitPdcpSduMmWave`, `targetCellId`). SDUs re-entered after an LTE→NR switch count, because each crosses X2 once. S-SN→T-SN RLC forwarding is SN↔SN, so it is excluded and disclosed.
- **Audit.** It emits the same event with the target cell.
- **V3.** It judges per cell, with no overlap pooling, plus a swapped-attribution negative fixture that keeps the sum. It also requires DRB.PdcpSduVolumeDL = 0 at every en-gNB, and keeps the period-sum check.

**Q3: the 32.425 reading, and ask the user to add 3GPP TS 32.425 to Zotero.**
- Fallback: every eNB 3GPP-style name without a readable clause is renamed to `ns3.*`, unless the user grants a named exception. KPM §7.9.1 type and unit alone never suffice.

**Q4: 12 bits.** This reverses my 18-bit recommendation. The SN-rollover fix becomes its own commit right before P7 (my Q6 alternative). P7's rows at 12 bits:
- **(a) Type level.**
  - MC entities and every listed consumer take the header class from bearer context, never from a packet tag.
  - A source lint fails if an MC path names `LtePdcpHeader`.
  - The audit header line prints the class and size from the entity's header object.
- **(b) Byte identity.** P7's deterministic N4 runs (uloff and ulon) equal the rollover commit's byte for byte. This proves that P7 changed no wire byte and broke no consumer, including the forwarding paths.
- **(c) Rollover.**
  - It is red at cp2 (a 12-bit analogue) and green at the rollover commit.
  - Live runs exercise it, because the SN wraps every ~2 s.
  - The window is 2,048, about 1 s at 2,000 PDU/s, far above the 1 ms X2 delay plus RLC recovery.
- **Recorded openly.** AC16's trace clause also passes at cp2, because the 12-bit E-UTRA and NR headers are byte-identical. It is therefore a conformance check, not a discriminator; (a) and (c) discriminate.
- **Rows 148–150.** Row 150's `hdr == 3` change is void: HDR stays 2, cited to 38.323 §6.2.2.2, and `rung-config.json:80-81` gets the same citation.
- **Strongest counter-argument.** At 12 bits P7 leaves the wire unchanged. A reader of cp3 cannot see it, so its NR-ness rests on code-level evidence, the kind this project otherwise distrusts. 18 bits would put P7 on the wire, make an unconverted consumer fail loudly, and match the common eMBB configuration [B].
- **Rebuttal.** 18 bits still cannot prove NR (claim 8). Its loud failures guard against a hazard that 18 bits itself creates. Its realism gain is nil at this load. It widens shared LTE structures with latent truncation (claim 9).
- **What would flip it:**
  - the user reads AC16 as requiring a cp2-versus-cp3 wire difference;
  - the scenario moves to rates or durations where 2,048 PDUs in flight is tight;
  - the user values wire visibility over the smaller change.

### C.5 Effect on order, budget and the rule-now set
- **Order.** Insert "SN rollover" between P6 and P7 in the commit lists (`plan.md:100`, `:133`). If the UB is ruled fixed, the order becomes D-R3-1, UB, P6, rollover, P7, P9, P15, D-06b-1, kpimon node tag, TS serving cell, UseIdealRrc. Nothing else moves. The pending marker bridges P6 to P9.
- **Budget.**
  - The rollover commit adds about 1 h and 3–4 GiB (an ns-3 build, M4, M5–M7).
  - At 12 bits P7 avoids the widening and the trace-wide resize, and it no longer breaks N4's uloff equality. The UB fix and P9 still break it, so the V3 route row stays.
  - Cycle 1 becomes about 45–55 GiB and ends at about 24–34 GiB free, near the 22 GiB watchdog at the high end. Register a conditional fourth revert point before P9: revert if free /home after P7's gates is below 33 GiB.
  - Wall time is about 15–18 h.
- **Rule now.** The set does not change: the UB and Q1–Q4 as one batch, before the next commit after D-R3-1. Q4's recommendation changed, so show the user both sides.
- **Controller registrations.** These need no user question; register them before P6:
  - the pending marker;
  - the per-cell V3 judge and the counting definition;
  - the consumer lint and the bearer-context discriminator;
  - the conditional revert point.

### C.6 Unresolved
1. The user's batch ruling, especially Q4, which has now changed.
2. The disk cost of an agent image rebuild is still unmeasured. It decides whether the conditional fourth revert point fires.
3. Whether N4's uloff and ulon runs are byte-deterministic across two builds of the same source. The byte-identity check for (b) assumes so; verify it once at the rollover commit before relying on it.

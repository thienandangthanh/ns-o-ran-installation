# P6 draft rulings R1–R4: ultra + debate result (2026-11-06 23:59 KST)

Input: `decisions-261106-2246-GH-1-p6-draft-rulings-pending.md`. Read-only advisory run; no file in the Testbed, ns-3 or ledger changed. Nothing here is a user ruling; every answer below still needs the user.

Method:
- Five independent candidates got one identical evidence packet: four kongming runs (Opus 5.5) and one Codex run.
- A kongming verifier scored them blind (A–E) and spot-checked six contested claims in the source.
- Codex then challenged the verifier's final answers.
- A closing kongming read checked each challenge against the source and ruled on it.

Explainer page: `plans/261103-0008-GH-1-post-m9-realism-m10/visuals/explain-p6-draft-rulings.html`.

## Contract

- **Outcome:** the user can answer R1–R4, and one new question, before the P6 commit, with a recommended answer and evidence for each.
- **Constraints:** Prior user rulings stand: 20:46 (V20.2.0 only, successor rule, PRB fix outside M10), 21:37 (L2/L4/L5) and Q2 at 19:52. The scope guard holds: no check is weakened. Fix to spec, with no legacy modes.
- **Non-goals:** implementing the TB, PRB or throughput fixes; committing P6.
- **Acceptance:** every answer cites source or a spec page. Unverified claims are labelled as such. New decisions carry a deadline.

## Final recommended answers (after the debate)

| Q | Recommendation | Confidence |
|---|---|---|
| R1 | **Strict.** A row keeps its 3GPP name only if ns-3 counts the clause's events exactly once on every path the runs reach. Only timing may differ: up to 1 slot for counts, or 1 of the clause's own sampling steps for sampled values. The E2 report period never counts as a sampling step. This allowance is the project's tolerance, not a 3GPP number. Effect: the gNB TB pair becomes `ns3.*`, and so does the eNB `RRC.ConnMean` until a run proves its attach bound. | high |
| R2 | **Accept all three renames.** Record explicitly that this replaces the 21:37 L4 line "DRB.UEThpDl keeps its name", which was a ruling, not a forecast. The L4 per-UE rule stands. Append the amendment to the 0525 log and leave the 21:37 text unedited. Until P9, no row in the map passes under a 3GPP name. | high |
| R3 | **Follow-up outside M10**, next to the PRB fix. The follow-up chooses the counting site and must meet R1. The two candidate sites are the gNB PHY `mmwave-enb-phy.cc:948` (DATA, rv only) and the MAC `mmwave-enb-mac.cc:943` (has cellId and tbSize, but counts 2 slots early). | high |
| R4 | **Accept**, and extend the correction to three eNB rows that say "bytes" but carry kbit: enb cell 5 (always 0), enb cell 6 and enb ue 10 (`lte-enb-net-device.cc:1096,1112,1134,1233-1234`). The unit changes on kept 3GPP rows (gnb cell 34/35 to Kbit, enb cell 8 to count) are filed under row 147 (3). | high |
| New Q5 | **X2 forwarding (Q2/row 151):** count the data the source SN forwards to the target SN over X2 at the receiving cell. This revises Q2. Alternatives: (b) an explicit user-owned exception to R1, or (c) a known gap, under which P9's X2 rows can never pass. Annex A is informative (p.397), and A.25 p.403 exempts nothing, so calling the exclusion an "interpretation" would be a lenient pass with a new label. Deadline: before P9 code; ask it now. | medium |

## New facts this run established

- **Gap 1 measured.** One candidate counted 6,238 of 842,007 DL TBs lost (0.74%) in M7 run `20261103T201804Z` (pin `48d41a50`). The verifier judged the method sound and saw a consistent row total, but did not verify the numbers.
- **The eNB `RRC.ConnMean` pass is unproven.** LTE control errors are on by default (`lte-spectrum-phy.cc:222-225`), so a random-access failure that ends in the 15 ms timeout (`lte-enb-rrc.cc:3177-3184`) is a live path. scenario-zero traces no RRC state, so no existing run can prove the bound.
- **The draft's "No 32.425 entry" reasons are false.** 32.425 V19.0.0 has the measurements (§4.4.1.1 p.48, §4.4.3.1 p.52, §4.4.7.1 p.58). The renames still stand on other grounds: INTEGER vs REAL, ms vs 0.1 ms, PDU vs SDU bits, and a QCI label.
- **`pendingFix: "P9"` is a contract deviation id, not a plan phase id** (contract `:36`, `:115-118`). The 2246 note is wrong on this.
- **The draft already ships bare-name permission for `TB.TotNbrDl`** (registry `:55`, `kpm-clause-registry.py:117-119`), but item e) on p.112 lists only `TB.TotNbrDl.X`.

## Cleanup items (no ruling needed, before the P6 commit)

1. Set registry `:55` to `total: false`, and move the "TB drops at SN change" self-test fixture to `TB.TotNbrDlInitial`.
2. Reword the TB reason to "count per cell on transmission; the follow-up chooses the site".
3. Set the eNB `RRC.ConnMean` check to `holds: false` (attach bound unproven) and rename that row in place. *(Follows from R1.)*
4. In registry doc line 10, label the 1-slot / 1-sampling-step allowance as the project's tolerance, and add the count-once boundary rule.
5. Correct the false 32.425 reasons.
6. Correct the 2246 note: P9 is a deviation id, and the 21:37 line is a ruling.
7. Replace "ledger row 147 (n)" and "user ruling Q2" labels in code and registry text with the rule each one states.
8. Change gnb ue 29's layer to RLC.
9. Disclose in the P6 amendment that ad-cell loses `RRC.ConnMean`, PRB and throughput fields, and that the vendor-name rule is stricter than row 147 (6).
10. Record P9's rounding to Kbit as an interpretation.
11. Re-cite the ns-3 lines at the UB-fix pin. This is certain, not conditional, because the UB fix lands before P6.

## Ranking appendix

| Candidate | R-faith | R-ground | R-sharp | R-honest | R-miss | Total |
|---|---|---|---|---|---|---|
| **A (winner, kongming)** | 18 | 18 | 17 | 18 | 19 | 90 |
| C (kongming) | 18 | 17 | 18 | 18 | 18 | 89 |
| E (kongming) | 15 | 16 | 17 | 16 | 13 | 77 |
| D (kongming) | 14 | 14 | 16 | 15 | 17 | 76 |
| B (Codex) | 17 | 15 | 10 | 17 | 10 | 69 |

- No candidate failed a hard constraint.
- A won because it alone grounded the row-151 point in a verified spec passage and caught the false 32.425 reasons.
- The debate then overturned A's row-151 default (interpretation via A.25). It also overturned the verifier's eNB `RRC.ConnMean` pass and its deferral of the bare-name question.

Debate rulings on the Codex challenges:
- **C1, the residual cap: partly accepted.** The cap stays and is labelled the project's tolerance, with a boundary rule added.
- **C2: accepted.** L4 was a ruling, and the `holds:false` entries are optional.
- **C3: accepted.** The counting site is left to the follow-up. The control emission at `:889` filters out by its CTRL tag.
- **C4: accepted.** Row 151 goes to the user.
- **C5: accepted.** The bare-name permission is removed now.
- **C6: accepted.** The eNB `RRC.ConnMean` must not pass today.

ultra: picked=1/5 margin=low unanimous=no rejected_all=no

## Unresolved questions

1. R1–R4 and Q5: these are the user's decisions.
2. Whether counting forwarded data disturbs the R3′ predictor. Only a P9 run can show this; if it does, option (b) of Q5 is the fallback.
3. Whether real EN-DC forwards between SNs for MN-terminated bearers. 37.340 was not read.
4. The eNB attach-timing bound needs an instrumented run, with an RRC-state trace, before `RRC.ConnMean` can get its name back.
5. Pages not read this run: 28.552 p.68; KPM §8.3.x; the V17.17.0 pages.

## Appendix: winning candidate A (unchanged)

Read-only. Re-ran the lint and its self-test with bytecode writing off: 0 findings, 2 XFAIL, self-test ok, Testbed git status unchanged.

Spec pages read: 28.552 V20.2.0 (`5SZUBP6M`) pp.28, 56–57, 111–112, 142–143, 183–185, 403; 32.425 V19.0.0 (`9XR9PVRW`) PDF pp.19, 48, 51–52, 57–58; KPM v03.00 (`F82PYZVK`) pp.13–14. ns-3 read with `git show ea6e46f6:`, oran-interface at `53253fe`.

#### R1

- **Answer:** Strict. A gap fails. Only allowed: a residual that shifts when an event is counted without losing or adding it, within a stated bound; and an interpretation of a point the clause leaves open, with a cited basis. Write this into row 147 before the P6 commit, and classify P9's SN↔SN exclusion in the same amendment (missed issue 1).
- **Why:**
  - Row 147 (3) (`check-diff-ledger.md:153`) requires "the value check holds" and defines no tolerance. A disclosed-gap pass is a weaker predicate, which scope guard 3 forbids (`goal-packet.md:47`, AC18); inventing a tolerance is a spec choice that scope guard 4 sends to a human (`:48`).
  - 28.552 §5.1.1.7.1/§5.1.1.7.3 (pp.111–112) count "on transmission by the gNB of TB to UE". ns-3 counts when the UE PHY finishes receiving the TB (`mmwave-spectrum-phy.cc:707-732` → `mmwave-phy-trace.cc:242-260`). Neither gap is a point the clause leaves open.
  - Gap 1 verified: `DoRecvUeContextRelease` → `RemoveUe` (`lte-enb-rrc.cc:5582-5612, 5892-5900`); DU report sums and resets only UEs still in the UE map (`mmwave-enb-net-device.cc:1152-1165, 1339`).
  - Gap 2 verified: `mmwave-spectrum-phy.cc:431-437`.
  - Both gaps reached on every SN change; every RC Style 5 control causes one (contract `:97`).
  - Rename loses nothing: order, measId, indication bytes unchanged.
  - Wording fix: not "≤1 slot"; the MAC site proposed for R3 counts 2 slots early. Define a residual as an event counted exactly once, possibly in the adjacent period, because its counting instant is off by a stated fixed bound.
- **Strongest alternative:** Lenient with disclosure, citing the user's own acceptance of a disclosed exclusion for the X2 counters (0525 `:32`; ledger row 151 `check-diff-ledger.md:157`). Loses: that exclusion can be read as an interpretation backed by 28.552 Annex A.25 p.403; the TB clauses leave nothing open. A numeric tolerance (e.g. ≤1% lost) also loses: static lint cannot measure it, loss grows with handover rate × period, threshold is an invented spec choice.
- **Would change my mind:** evidence that no judged run reaches an SN change on a cell whose TB rows are judged, or 3GPP text allowing implementation-dependent omissions in TB counts.
- **Confidence:** high on strict; medium on exact residual wording.

#### R2

- **Answer:** Accept all three. Append one amendment line to the 0525 log: L4's per-UE rule stands; only its parenthetical forecast "DRB.UEThpDl keeps its name" (`:47`) is superseded by row 147 (3)'s value check.
- **Why:**
  - DRB.UEThpDl: value = mean RLC PDU size ÷ mean RLC delay (`mmwave-enb-net-device.cc:795-805`), sent as `DRB.UEThpDl.UEID` (oran-interface helper `:108`). Clause = ΣThpVolDl ÷ ΣThpTimeDl per burst, RLC SDU level, excluding last slot (28.552 §5.1.1.3.1 pp.56–57). L4 judged only per-UE eligibility (KPM §7.9 p.13), which stands.
  - gNB RRC.ConnMean: §1 p.28 EN-DC exclusion; eNB row holds (32.425 §4.1.3.1 PDF p.19; `lte-enb-net-device.cc:1283-1306`).
  - DRB.MeanActiveUeDl: value `ueMap.size()` at report instant (`mmwave-enb-net-device.cc:1402`); clause is mean number of UEs with DL data per 38.314 (pp.142–143).
  - Appending keeps the 21:37 record; the change comes from a conjunct registered before code, not a silent reversal.
  - Nothing needs en-gNB 3GPP names: TS xApp reads only ueId tag and time; r3p reads DRB.PdcpSduVolumeDL (kept); agent, kpimon, M6/M7 checks are map-driven.
- **Strongest alternative:** keep DRB.UEThpDl because the user was told it stays (needs value check waived, AC18); fix ns-3 to compute ThpVolDl/ThpTimeDl now (scope growth, belongs to R3 follow-up).
- **Would change my mind:** an ns-3 path already computing per-burst ThpVolDl/ThpTimeDl (none found; commented-out PDCP variant at helper `:106` is not one).
- **Confidence:** high.

#### R3

- **Answer:** Follow-up outside M10, next to the PRB fix. Count at the gNB PHY transmission (`mmwave-enb-phy.cc:948`), not at MAC `:943`.
- **Why:**
  - No M10 criterion needs a 3GPP TB count; AC16 satisfied by the rename (contract `:116`). Only reader of TB keys: IPC key in `n4-drop-selftest.py:27`.
  - Same kind as PRB ruling (0525 `:41`). Inside M10 would need a contract amendment, another ns-3 commit, checkpoint-3 attribution, on a chain the D-R3-1 M7 red still blocks.
  - Site: `m_macDlTxSizeRetx` at `mmwave-enb-mac.cc:943` fires in `DoSchedConfigIndication` for a slot scheduled L1L2Latency = 2 slots ahead (`mmwave-phy-mac-common.cc:97,153`; `mmwave-enb-mac.cc:556-561`). `TraceDlPhyTransmission(…, DATA)` at `mmwave-enb-phy.cc:948` (carries rv; `:1238-1251`) fires at the DL transmission, the clause's counting instant. A per-cell counter there removes both gaps.
  - Follow-up design: add a new `TB.TotNbrDl` row with a new measId rather than renaming `ns3.du.macPdu` back (measIds stable, append-only). Must settle the bare name (item e) p.112 lists only `TB.TotNbrDl.X`).
  - One follow-up record listing every fixable value-check failure: PRB family, TB pair, DRB.UEThpDl, DRB.MeanActiveUeDl.
- **Strongest alternative:** "Never" (no consumer); loses narrowly — fix-to-spec preference, record is free. Inside M10 loses on contract scope and schedule.
- **Would change my mind:** any M10 check, R3′, TS or QP reading TB counts, or user wanting checkpoint-3 references to carry 3GPP TB values.
- **Confidence:** high on follow-up; medium on the PHY-site detail.

#### R4

- **Answer:** Accept, and apply the same correction to three ns3 eNB rows the draft left wrong.
- **Why:**
  - Only the lint reads `unit`, and only on 3GPP rows (`lint-metric-map.py:174`).
  - Verified: 0.1 ms from delay in ns (`lte-pdcp.cc:219`) / 1e5 (`lte-enb-net-device.cc:1164`; cell `:1215-1218`); kbit from `:1110-1111`, gNB `:725`.
  - Missed: eNB cell 5/6 `ns3.cuUp.pDCPBytesUL/DL` say "bytes" but carry kbit (`:1096`, `:1112`, `:1234`), UL is constant 0 (`:1233`). eNB ue 10 `ns3.cuUp.txPdcpPduBytesLteRlc` says "bytes/period" but carries kbit (`:1134`).
  - Unit changes on 3GPP rows (gnb cell 34/35 → Kbit, enb cell 8 → count) are required by conjunct (3), not R4.
- **Strongest alternative:** leave text alone; keeps 125× and 10× errors.
- **Would change my mind:** a consumer that parses `unit` (none found).
- **Confidence:** high.

#### Points to note needing a ruling

None as written; the one needing a ruling is missed issue 1 (inside R1). Corrections:
- `pendingFix: "P9"` is not a plan-phase id: P9 is the contract's deviation id (contract `:36`, `:115-118`); HEAD map `origin` already says "recorded deviation P9". No ruling needed.
- Non-mandated references: "ledger row 147 (n)" at `lint-metric-map.py:77,148`, `kpm-clause-registry.py:115,132`, registry `:20,:213`, self-test `:1`; "user ruling Q2, 2026-11-06 19:52" at registry `:147,:167`, printed by every XFAIL line. Rewrite as invariants; no ruling.
- ns-3 line re-check will be needed (UB fix before P6, 0525 `:34`): pending UB edit removes `mmwave-enb-net-device.cc:882-897`, file loses 27 lines net; ranges from 898 on move. Citations are SHA-qualified, so true for `ea6e46f6`; re-check at new pin.
- Interpretation to add: `nameForms.total = true` for TB.TotNbrDl goes beyond item e) p.112 (only `TB.TotNbrDl.X`); matters for R3 follow-up.
- ad-cell/ad: disclosure enough.

#### Missed issues

1. **Strict R1 blocks P9 unless the SN↔SN exclusion is classified.** Q2 ruling (0525 `:32`) and ledger row 151 (`check-diff-ledger.md:157`) exclude S-SN→T-SN RLC forwarding during an SN change (`lte-enb-rrc.cc:1160-1219`) from X2DL/UL. §5.1.2.1.1.2 item c) p.184 counts "bits transferred in the downlink through X2 interface", no endpoints named. ns-3 forwards RLC buffers over X2 (`lte-enb-rrc.cc:959, 977, 1209, 1219`). Under the drafted rule this is a path dropping counted bits; validator forbids `holds: true` with gaps (`kpm-clause-registry.py:73-74`), so P9's X2 rows can never pass and the empty pending list required at P9/P11 is unreachable. Recommended: record it as an interpretation citing Annex A.25 p.403. Alternative: P9 counts on X2-U receive at the en-gNB. Needs a user ruling (touches Q2).
2. "≤1 slot" bound fails the R3 fix site (2 slots). Use count-conserving wording.
3. R4 incomplete: the three eNB rows above.
4. eNB rename reasons inaccurate: 32.425 V19.0.0 defines DRB.PdcpSduVolumeDl_Filter (§4.4.7.1 p.58), DRB.PdcpSduBitrateDl.QCI (§4.4.1.1 p.48), DRB.PdcpSduDelayDl.QCI (§4.4.3.1 p.52). Renames still right (INTEGER vs REAL, ms vs 0.1 ms, PDU bytes incl. header, `.QCI` sub-counter with KPM label); record should say so; `holds: false` registry entries would make reasons durable and testable.
5. Verdict depends on run configuration: AC17 flips `UseIdealRrc` (true at `scenario-zero.cc:492`) before checkpoint 3; eNB RRC.ConnMean attach residual (registry `:127`) judged under ideal RRC. Add a re-audit trigger to the R1 amendment.
6. Validator gap: `CHECK_FIELDS` (`kpm-clause-registry.py:17`) does not require `gaps` or `residuals`; the only `holds: true` check (eNB RRC.ConnMean, registry `:122-128`) has no `gaps` key. Require explicit `gaps: []`.

#### Unknowns

- Not read: 28.552 §5.1.1.4.1 p.68, KPM §8.3.9/§8.3.11 pp.30–31, V17.17.0 pages, 37.340 on SN-change forwarding.
- Not measured: TBs lost per SN change; attach duration under real RRC.
- Post-UB ns-3 SHA not yet available.
- Stale memory: a kongming memory note says eNB DRB.PdcpSduBitRateDl is bytes/s; at `ea6e46f6:1110-1111,1167` it is kbit/s.

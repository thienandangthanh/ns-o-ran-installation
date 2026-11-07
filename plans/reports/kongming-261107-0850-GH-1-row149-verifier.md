# Blind verifier: row 149 M7 judgement (best-of-5)

Date: 2026-11-07 (Asia/Seoul). Model: Opus 5.5 (kongming; caller routed `opus`, not `fable`). Read-only except this file.
Inputs: packet `row149-brainstorm-packet.md`, candidates `row149-blind/{A..E}.md` (scratchpad). ns-3 read at committed `4a0871d6` via `git show` (working tree has uncommitted P7 edits).

## TL;DR

Winner **A**. Q1: amend row 149 with a ±1-epoch switch window (equality off-window, upper bound in-window, ≥ 1 off-window row). Q2: record the defect as a follow-up outside M10; it does not block P7. A, C, D and E reach the same answer and nearly the same predicate. A wins because it is the only one whose ledger text admits that the change is weaker than the registered row ("Weaker than the registered text, which never held at M7"). C, D and E write "not weaker than a predicate never green", which is false: an upper bound accepts more than equality. A has three wrong line cites (corrected below). They do not change the decision. B ("diagnose first, keep the registered predicate") is not better supported: the predicate holds on code and archive facts alone, and B's route would guarantee a red that the Failure Protocol cannot clear within scope.

## Scores (1–20 per criterion)

| Cand | (1) Faithful | (2) Evidence | (3) Sharp predicate | (4) Honest unknowns | (5) Trade-offs | Total |
|---|---|---|---|---|---|---|
| A | 18 | 16 | 17 | 17 | 17 | **85** |
| D | 15 | 18 | 16 | 16 | 17 | 82 |
| E | 15 | 17 | 17 | 15 | 17 | 81 |
| C | 15 | 17 | 16 | 13 | 16 | 77 |
| B | 9 | 11 | 6 | 14 | 10 | 50 |

Ranking: A > D > E > C > B. No candidate hard-fails. C, D and E each give an additive amendment with a stated reason, but they misdescribe it as "not weaker". B weakens nothing. Its "better approach" (a per-PDU input/output audit) would need new ns-3 output, which is a scope expansion, but B does not make that its recommendation.

Per-candidate notes:
- **A**: Its counts are exact (205 short = 90/55/30/30; 3308–3557 equality rows and 1708–1819 window rows per M7 run; M6 201/93; 66% vs 82%). The margin claim is right: the closest switch to an epoch boundary is 2.5 ms, across all 15 runs. Its fixture set is the most complete: other-IMSI, two epochs away, missing file, no off-window row. It considers and rejects a "mean size band" alternative. It states the weakening honestly. Faults: wrong RLC class and wrong ForwardRlcBuffers branch cites, plus one approximate line (all listed below).
- **D**: Every cite is correct, including the RLC mapping, the LowLat file, and the gNB KPM-loop reset (`mmwave-enb-net-device.cc:816`, calc `:586`). It is the only candidate to find the reset. It is the only one to argue head-on that the predicate does not need the root cause. It admits the predicate was written after reading the archives. Faults: "not weaker"; "closest observed margin 4.7 ms" is only the minimum for the 13-row runs, since a 2.5 ms case exists.
- **E**: It verifies the single header-add function (`mc-enb-pdcp.cc:243-259`). It is the only candidate whose missing-file rule is grounded in fact: the switch files are created on the first event, so absence means zero events, which makes the predicate stricter. Its same-epoch and ±1 counts are exact for all 30 runs. Faults: "not weaker"; RLC cite to the wrong class (`lte-rlc-um.cc`); no other-IMSI fixture.
- **C**: All mechanism cites are correct (LowLat `:274-282`, `:1059`, `:1102`, `:1148-1157`, the zero payload from `udp-client.cc`, `nr-pdcp-header.cc:104-105`). It makes the sharp point that M6 has 78 switches, so (b) is not safe. Its 4.7 ms margin is correctly scoped to one run. Faults: "not weaker"; the reset cite `:484-501` is `ResetResults`, which E2 does not use; it leans on row 148(b), an N4 check, for M7 reproduction; it gives no single-sample caveat.
- **B**: Its counter and RX-side PduSize cites are right, and its line 165 arithmetic is right. It is right that "not weaker" is a logical error. But it gives no predicate. It wrongly claims (a) can mask a malformed header: header addition is uniform, so the off-window rows catch it. It cites the wrong RLC class and branch (`lte-rlc-um.cc:218-247`, `:1051`). It plans a known red and gives no investigation method or cost.

## On B's "diagnose first, keep the registered predicate"

Not better supported. On these facts, amending now is right.

- **The predicate is sound without a runtime diagnosis.** Its header verdict rests on three facts:
  1. **Code.** McEnbPdcp adds the header in one function for every TX PDU (`mc-enb-pdcp.cc:243-259`), and the TxPDU trace fires after that (`:221`, `:238`). Any change in header size therefore shifts every PDU. The off-window rows (about 66% of M7 rows, 68% of M6 rows) then fail equality.
  2. **Counters.** `nTxPDUs` and `TxBytes` are incremented in one call (calc `:217-218`) and erased in one call (`:542`, `:557`). A short row is therefore at least one short PDU, not an epoch artefact.
  3. **Archives.** All 205 of 205 short rows have a same-IMSI switch inside their own epoch, and no row in any of the 30 archives is long.
- **The runtime cause only matters for Q2.** It decides how severe the data-integrity problem is, not whether the header check is sound.
- **The residual gap is covered elsewhere.** A P7 regression confined to the forwarding path (for example, the strip length in ForwardRlcBuffers) would be caught by row 148(b). N4 runs the UM forwarding loops (ledger `:311`) and must stay byte-identical, and row 148(a)'s unit suite covers the codec.
- **A diagnosis could not flip Q1.** A header-related cause is excluded by the single fixed header class. It is also excluded by the deficits that persist across consecutive switches (IMSI 3 shows deficit 1 in four epochs in a row; IMSI 10 shows deficit 40 at 21.5 and 21.6 s).
- **A diagnosis could not flip Q2's P7 disposition either.** A fix stays outside M10 under the scope guard and needs a ruling. It would break P7's one-commit rule and row 148(b). The defect is pre-existing: 6 of the M7 archives were run at ns-3 `ea6e46f6`, which is `m10-cp2`'s pin in `pins.conf`.
- **B's route has a real cost.**
  - P7's M7 is guaranteed red.
  - The Failure Protocol allows one kongming-guided fix; a second red is PAUSE T6 (`plan.md:347`). With the user away, P10 would stall.
  - A diagnosis needs VM runs plus either an NS_LOG-enabled build or new trace output. New output inside P7's commit would change the N4 compared set; outside it, it means a separate diagnostic branch and more VM budget.
- **B's one valid point** is the "not weaker" fallacy. A already handles it correctly.

## Final answers (from winner A, unchanged)

**Q1: (a′). Confidence high on direction (amend, not b/c/d); medium on window width.**

Paste-ready amendment (A's text, verbatim):
> Row 149, amended before code (2026-11-07, <consensus ref>; additive). File/columns verified as drafted: DlE2PdcpStats.txt (mmwave-helper.cc:3198), columns by header name LCID, nTxPDUs, TxBytes (calculator :363-366, 438-480); both counters updated in one DlTxPdu call (:217-218) at McEnbPdcp TxPDU after header add (mc-enb-pdcp.cc:221,238), reset together (:542,557). SDU 1308 = 1280 (scenario-zero.cc:693) + 28.
> Why: the registered predicate never held at M7. All 15 archived runs (current pins and m10-cp2) hold 13–14 LCID-3 rows with TxBytes < nTxPDUs × 1310, deficits 1, 7, 25 or 40 B, each in an epoch holding an LTE↔mmWave switch of its IMSI. Cause [I]: a switch resubmits the RLC UM unsent tail of a segmented SDU to McEnbPdcp (lte-rlc-um.cc:239-247, lte-enb-rrc.cc:1101-1102,1146-1156); independent of the header. 15 M6 runs hold no such row.
> Predicate: over LCID-3 rows with nTxPDUs > 0, d = end − start; switch row = a SwitchToLte or SwitchToMmWave of its IMSI (LteSwitchStats.txt, MmWaveSwitchStats.txt, IMSI column 3, same run dir) in [start − d, end + d); switch row TxBytes ≤ nTxPDUs × 1310; every other row TxBytes = nTxPDUs × 1310; ≥ 1 non-switch row; missing switch file fails.
> Why ±1 epoch: switch files UE-side (lte-ue-rrc.cc:1563,1570); resubmission at the eNB at the same instant for SwitchToMmWave under ideal RRC, two X2 hops (2 ms) after a SwitchToLte; the UseIdealRrc commit (rows 156–157) adds RRC delay; same-epoch window would turn a boundary straddle into a false red.
> Fixtures fail: 1308+3 on non-switch row; 1308+3 on switch row; short non-switch row; short row whose only switch is two epochs away or another IMSI; no non-switch row; missing switch file. Pass: short row with its switch in previous, same or next epoch.
> Archive replay: M7 15/15 pass (3308–3557 equality rows, 1708–1819 switch rows per run); M6 15/15 (201 and 93).
> Recorded openly: switch rows judged on upper bound only; header conformance judged on equality rows because McEnbPdcp puts one header class on every PDU. Weaker than the registered text, which never held at M7. Contract change: No.

**Q2: follow-up outside M10; not a P7 blocker. Confidence high.** Pre-existing at m10-cp2 in all archives; P7 cannot change it (D/C bit same place in octet 1; row 148 (b) byte identity); fixing in P7 breaks one ns-3 commit, changes M7 traces, expands locked scope; predicate depends only on short PDUs near switches (205/205).

Follow-up text (A's, verbatim):
> RLC UM tail resubmission at LTE↔mmWave switches. Observation only. Pre-existing at m10-cp2; scenario-zero's UM DRB hits it at every switch. (1) ForwardRlcBuffers copies the UM tx buffer (lte-enb-rrc.cc:1048-1052) whose head can be an unsent SDU tail (lte-rlc-um.cc:239-247); D/C test (:1101-1102) reads its first byte; top bit 0 → silently dropped as "control PDU"; 1 → two payload bytes stripped as "header", rest resent as a new SDU with a new SN (row 149's short rows). M6 has 78 switches and no short row, so silent dropping dominates [I]. (2) Every resubmitted SDU fires McEnbPdcp TxPDU again (mc-enb-pdcp.cc:221,238); DL PDCP counters feeding KPM (mmwave-enb-net-device.cc:696-706, lte-enb-net-device.cc:1109-1111) count forwarded SDUs again in the switch epoch (IMSI 1: 1663 PDUs vs steady 198 in [0.7, 0.8) s, m7/20261106T223229Z). (3) gNB→gNB path (:905 → ForwardRlcPdu) forwards the same tails without PDCP [I]. (4) RX PduSize reaches 1904 B in switch epochs — possible UE reassembly anomaly [unverified]. Trigger: any realism claim on switch-epoch DL volume or SDU integrity.

### Factual corrections to apply when pasting A's text

1. **Wrong RLC class.** scenario-zero maps DRBs to `RLC_UM_LOWLAT_ALWAYS` (`mmwave-helper.cc:2091-2092` gNB, `:2392` eNB; `LteEnbRrc::GetRlcType` `lte-enb-rrc.cc:5860-5861`). `LteRlcUmLowLat` derives from `LteRlc`, not `LteRlcUm` (`lte-rlc-um-lowlat.h:45`, `.cc:79`). The head re-insertion is therefore at `lte-rlc-um-lowlat.cc:274-282`, not `lte-rlc-um.cc:239-247` (same code pattern). Fix this in the amendment's "Cause [I]" and in follow-up (1).
2. **Wrong ForwardRlcBuffers branch.** The live UM copy is the `LteRlcUmLowLat` branch at `lte-enb-rrc.cc:1055-1061`, not `:1048-1052`, which is the `LteRlcUm` branch and is dead for scenario-zero. Fix this in follow-up (1) and A's Q1 mechanism line.
3. **Approximate line.** The SwitchToLte X2 switch message is `lte-enb-rrc.cc:2190` (`SendSwitchConnectionToMmWave`, block `:2181-2191`), not "~2176". This is in A's Q1 reasoning only, not the amendment.
4. **Imprecise assumption wording.** A's "only non-S1 caller into McEnbPdcp" is not exact. There are two non-S1 routes, both driven by switches: ForwardRlcBuffers direct (`:1156`, SwitchToMmWave) and X2 `DoRecvUeData` → `SendData` (`:5627` → `:1217`, the SwitchToLte return). The assumption still holds.
5. **Design note, not a fact error: "missing switch file fails".** Both switch files are opened on their first event (`mc-stats-calculator.cc:139-142`, `:160-163`), so a run with zero events of one kind has no file. Reading absence as "no events of that kind" (E's wording) can only make the predicate stricter; "fails" risks a false red. This does not affect the current gates, since both kinds occur in all 30 archives (M6 38/40; M7 ≥ 590/9133). Optional.
6. **Supporting fact to add (from D).** E2 PDCP counters are reset by the gNB report loop (`mmwave-enb-net-device.cc:816`; `EndEpoch` skips the reset for "E2" at calc `:586-590`), not at the epoch end. Steady rows show 198 PDUs, not 200, because the reset lands about 1 ms after the epoch start. "Reset together (:542,557)" stays correct.
7. **Fixture caveat.** "1308+3 on switch row fails" holds only when nTxPDUs > deficit. The smallest short-row n in the archives is 253 (deficit 40), so build the fixture with n > deficit.

## Spot checks (ns-3 at `4a0871d6` unless marked)

| Claim | Result | Evidence |
|---|---|---|
| nTxPDUs and TxBytes are counted in the same call | ✓ | `mmwave-bearer-stats-calculator.cc:201-221` (`m_dlTxPackets[p]++` `:217`, `m_dlTxData[p] += packetSize` `:218`) |
| Both are reset together | ✓ | `ResetResultsForImsiLcid` `:539-543`, `:554-558`; E2 reset caller `mmwave-enb-net-device.cc:816`; `EndEpoch` skips it for E2 `:586-590` |
| PduSize columns are RX-side | ✓ | `DlRxPdu` `:285-313` (`m_dlPduSize` `:313`) |
| Column header | ✓ | `:363-366`; written by `WriteDlResults` `:438-480` |
| TxPDU fires after the header is added; one header path | ✓ | `mc-enb-pdcp.cc:243-259` (fixed `LtePdcpHeader`), trace `:221` (LTE leg), `:238` (mmWave leg) |
| ForwardRlcBuffers D/C path | ✓ | UM copy `lte-enb-rrc.cc:1048-1054` (UmLowLat branch `1055-1061`, the live one); size ≥ 3 `:1099`; D/C peek `:1101-1102`; McEnbPdcp re-insert `:1148-1156`; SwitchToLte X2 `:2181-2191` → gNB `:2218` → `DoRecvUeData` `:5627` → `SendData` `:1185-1217` |
| RLC UM head re-insertion | ✓ (LowLat) | `lte-rlc-um-lowlat.cc:274-282` (live); `lte-rlc-um.cc:238-247` is the same pattern but not the class in use |
| Switch traces are UE-side; files created on first event | ✓ | `lte-ue-rrc.cc:1563`, `:1570`; `mc-stats-calculator.cc:139-145`, `:160-166` (IMSI is field 3) |
| RRC/X2 delays | ✓ | `lte-rrc-protocol-ideal.cc:50` (0 ms); `mmwave-rrc-protocol-ideal.cc:60` (500 µs); X2 1 ms `mmwave-point-to-point-epc-helper.cc:222-224`; `UseIdealRrc` true at `scenario-zero.cc:492`; no `X2LinkDelay` override |
| Payload layout | ✓ | port 1234 `scenario-zero.cc:690`; 1280 B `:693`; UdpClient zero payload of size−12 plus SeqTs; NR decode `nr-pdcp-header.cc:100-105` (working tree, uncommitted) |
| Deficit set {1,7,25,40} identical across 15 M7 runs | ✓ | every run: 1×6, 7×3 (13-row runs) or ×4 (14-row runs), 25×2, 40×2; totals 90/55/30/30 = 205; 0 long rows |
| Every short row has a same-IMSI switch in its own epoch | ✓ | 205/205 |
| Same-epoch window passes all 30 | ✓ | M7 window/equality 920–988 / 4096–4388; M6 50/244 |
| ±1-epoch window passes all 30 | ✓ | M7 1708–1819 / 3308–3557; M6 93/201; ≥ 1 equality row everywhere |
| Smallest margin | 2.5 ms (A correct) | `m7/20261103T060451Z` row 43.6, IMSI 3, SwitchToLte 43.6975 s; 4.7 ms (C/D) is the minimum in the 13-row runs (`223229Z` row 36.2, IMSI 6) |
| M6 switch counts | ✓ | 38 SwitchToLte + 40 SwitchToMmWave in every M6 run |
| All rows CellId 1; 4 run lengths | ✓ | 5016/5136/5256/5376 rows |
| Bursts | ✓ | `223229Z`: IMSI 1 row 0.7 = 1663 PDUs; IMSI 10 row 21.6 = 6460; B's line 165 = 1006 PDUs / 1317853 B (deficit 7); PduSize max≠1310 in 120 rows, min≠1310 in 137 (of 5016) |
| Pre-existing at m10-cp2 | ✓ | M7 archive pins span 48d41a50, ace32168, e5b02094, ea6e46f6 (×6; `m10-cp2:scripts/pins.conf`), 74c165f1 and 4a0871d6, all with identical deficits |

## Confidence

- **High** on the decision: amend now with a ±1 window, and record Q2 as a follow-up. Four of five candidates agree, and every archive fact they rely on reproduces exactly.
- **Low** on the margin between A and D (85 vs 82). It turns on A's honest weakening wording against D's cleaner cites.
- **Not verified (shared by all candidates):**
  - The runtime cause. It is static reading plus archive pattern; there is no packet-level trace.
  - Skew under real RRC after the UseIdealRrc commit. A window that is too narrow fails red, never false green.
  - Whether P7's M7 reproduces the same 13–14 rows. This is expected, because P7 changes no wire byte.
- **Weak spot in the evidence.** All 15 M7 archives are one deterministic trajectory, so the window rule is fitted to one scenario sample.
- **Optional hardening that no candidate proposed.** Record per-IMSI equality-row counts in the fact, and treat a run whose equality rows collapse as worth a look. "≥ 1 non-switch row" is a weak floor.

## Unresolved questions

- Should the winner's missing-file rule follow E (absence = no events)? Recommend yes when pasting. It is not a factual error, so it is left to the controller.

ultra: picked=A/5 margin=low unanimous=no rejected_all=no

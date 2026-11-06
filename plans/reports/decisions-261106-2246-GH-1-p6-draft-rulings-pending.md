# P6 draft: rulings needed before the P6 commit (pending, 2026-11-06 22:46 KST)

Source: the uncommitted P6 draft (registry, strict lint, in-place renames) in `fullstack-developer-261106-2215-GH-1-p6-registry-and-strict-lint.md`, after kongming's independent read. The shipped map passes the new lint. The only expected failures are the two en-gNB rows marked `pendingFix: P9`, and the self-test passes 35 of 35 must-fail fixtures.

**Due:** before the P6 commit. That commit comes after the D-R3-1 chain (attempt 2 running) and the neighbour-loop fix, so none of this blocks current work. Ask all of them together when the user is back; do not commit P6 before they are answered.

## Questions

**R1. May a value check that misses some events still pass?**
- Row 147 needs every 3GPP-named row's value to equal what the clause counts, but it does not say what to do with known gaps.
- The draft ships the strict rule. A small boundary effect of at most one slot or sample per event is allowed. Any code path the runs reach that drops or adds counted events fails the check.
- Two verified gaps make the gNB cell rows `TB.TotNbrDl` and `TB.TotNbrDlInitial` fail:
  - At an SN change, the UE's per-cell count is dropped without being reported (`lte-enb-rrc.cc:5582-5612,5892-5900`).
  - A TB is dropped before the trace by a cell check (`mmwave-spectrum-phy.cc:431-437`).
- Under the strict rule they become `ns3.du.macPdu*`. Under a lenient rule ("a disclosed gap is allowed") they keep their 3GPP names.
- Either way row 147 needs an amendment that states the rule.
- **Recommendation: strict.** A count that drops events at every handover is not the clause's count, and the scope guard forbids loosening a check. The rename loses no data: the order, measId and wire bytes are unchanged.

**R2. Accept three renames that differ from the forecast shown at 21:37?**
- `DRB.UEThpDl` becomes `ns3.du.rlcPduSizeOverDelayDl`. The value is mean RLC PDU size divided by mean RLC delay, which is not the clause's throughput. The L4 line "DRB.UEThpDl keeps its name" was a forecast made before the value was checked.
- The gNB `RRC.ConnMean` is renamed. 28.552 §1 p.28 says EN-DC RRC connection measurements are handled by E-UTRAN under 32.425. The eNB row keeps the name and passes.
- `DRB.MeanActiveUeDl` is renamed.
- **Net effect:** until P9 adds the X2 volumes, the en-gNB reports no passing 3GPP-named measurement.
- **Recommendation:** accept, and record an amendment line in the 0525 decisions log rather than editing the 21:37 text.

**R3. Fix the TB counters (count per cell at the gNB MAC, e.g. `mmwave-enb-mac.cc:943`)?**
- **Recommendation:** a follow-up outside M10, next to the PRB-source fix. This follows the same pattern as the PRB ruling. Doing it inside M10 would be scope expansion.

**R4. Accept the unit-text corrections on renamed rows (ms → 0.1 ms, bytes → kbit)?**
- These change only the informational `unit` text, never a predicate or a wire byte.
- **Recommendation:** accept.

## Points to note, no ruling needed unless the user objects
- **ad-cell and ad configs.** They will no longer find their 3GPP PRB and throughput fields on ns-O-RAN data. No M10 gate deploys them. This will be disclosed in the P6 record.
- **`pendingFix: "P9"`.** This puts a plan phase id in a shipped artifact. Row 147 (8) mandates it, so it will be recorded as a stated exception to the rule against plan ids in code. P9's commit removes it.
- **Interpretations recorded in the registry.** Row 147 does not settle these, so the draft chose:
  - `_Filter`: the bare name read as the unfiltered total.
  - KPM §7.9.1 cites older 28.552 clause numbers, so entries are matched by name.
  - The splitOnly/dcExcluded rule applies to entries of the row's own document.
  - Vendor names are matched case-insensitively.

  Each will be stated in the P6 ledger amendment.
- **ns-3 line numbers.** The registry cites them at ns-3 `ea6e46f6`. They are re-checked if the UB-fix commit moves the ns-3 pin before P6.

## Unresolved questions
- R1–R4 above.

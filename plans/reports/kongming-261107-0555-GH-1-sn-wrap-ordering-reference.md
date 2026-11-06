# Kongming: ordering reference for the SN-wrap fix (ledger row 160)

Date: 2026-11-07. Advisory only; no code was edited. This ran on Opus 5.5 because the user's CLAUDE.md routes kongming there, not to `fable`.
Paths are relative to `ns-3-mmwave-oran/` unless they start with `plans/` or `scripts/`. Line numbers are from the working tree with the draft applied.

## TL;DR

- **Order by RLC transmission order, not by the PDCP SNs alone.** Walk the AM transmitting window from VT(A) to VT(S), using VT(A) as the modulus base (TS 36.322 §7.1). Take each SN's PDU from the transmitted buffer or the retransmission buffer, and delete both `MergeBuffers`. The getter returns each PDCP SN once, in the order its SDU was first reassembled. Keep the draft's modular lookback, and drop `OrderPdcpSnsByCount`.
- **Why this reference.** It is the only one of the four candidates that the spec bounds, that the model enforces, and that every call site can read, including the `pdcp = 0` paths. It does not depend on how far apart the retained PDCP SNs are, so it closes Codex's {10, 3010} case. The widest-gap draft cannot even detect that case.
- **It goes beyond row 160.** The same change also fixes the 10-bit RLC wrap: an SDU segmented across RLC SN 1023 → 0 is no longer lost. That needs an additive amendment to row 160, routed through brainstorm consensus. The wording is in §Q2.
- **Biggest finding: none of this code runs in scenario-zero.** Its DRBs use RLC UM low-latency, so M5–M7 and N4 never execute the AM forwarding path. P7's byte identity is not at risk. But row 148 (b) proves nothing about the AM-only header consumers, and the Q3/Q4 decision record says "the wrap fix runs live", which is not accurate for these paths.

## Reframed problem

The question is not "which reference" in the abstract. The model never stores COUNT, so any ordering has to rest on an invariant. The real decision is which invariant to rest it on:

- **(i) the PDCP half-window.** Retained SNs span less than 2048. The spec requires this for receiver HFN sync, but neither `McEnbPdcp` nor `McUePdcp` enforces it.
- **(ii) RLC entry order is COUNT order, read modulo 1024 from VT(A).** The spec bounds this, the model enforces the window, and it holds except for one model artifact.

Requirements:

- COUNT order across the 12-bit wrap.
- Unchanged output without any wrap.
- Works at every call site.
- No legacy or dual modes.
- Stays inside row 160, or gets an additive ruling.
- No risk to P7's byte identity or to N4 determinism.

Non-goals: the pre-existing LL-HO defects listed under "What to avoid".

## Verified evidence (load-bearing)

| Claim | Evidence |
|---|---|
| Codex is right: the draft reverses {10, 3010} | `lte-pdcp-sn-wrap.cc` `OrderPdcpSnsByCount`: interior gap 3000 > closing gap 1096 → start at 3010. The old map gave 10, 3010 |
| The sparse state is reachable | `mc-enb-pdcp.cc:248-254` assigns the SN, then `:274-288` picks a leg at random (`perPckToLTE`, default 0.5, `:109-113`). E2 can set the split per UE (`lte-enb-net-device.cc:352-372`). `mc-ue-pdcp.cc:266-269` keeps no RX window, so nothing in the model bounds the span. With 1500 B SDUs, one AM window of 512 PDUs can also hold more than 2048 SDUs when PDUs concatenate |
| Widest-gap cannot detect the out-of-spec case | For any set, the chosen arc span is 4096 − (widest gap) ≤ 2048 by construction. {10, 3010} reads as a valid 1096-wide wrapped arc |
| The RLC TX window is enforced | Window stall `lte-rlc-am.cc:733-738`; asserts `:1041-1042`; `IsInsideTransmittingWindow` `:1252-1260`; ACK handling with VT(A) as modulus base `:2233-2327` |
| The PDU walk ignores the wrap today | `m_txedBuffer` / `m_retxBuffer` are `vector[1024]` indexed by raw RLC SN (`:55-57`, `:1140`). `GetTxedBuffer` returns it raw (`:1188-1194`). `MergeBuffers` compares `GetSequenceNumber()` from a deserialized header (modulus base 0) at `lte-enb-rrc.cc:832` and `lte-ue-rrc.cc:1617` |
| The same file already handles the RLC wrap elsewhere | `lte-rlc-am.cc:2966-3005` ("If overflow happened, … from acked sequence to 1023, then from 0 to sent"); retx loop `:438-441` |
| Reassembly itself is wrap-safe if PDUs come in VT(A) order | `Reassemble` tests `currSeqNumber != m_reassembleExpectedSeqNumber` and adds `+1` with `SequenceNumber10` (mod 1024) at `:1317-1330`. The first PDU is forced into "with loss" mode at `:1846-1851` |
| With the raw walk at an RLC wrap, the straddling SDU is lost | The walk visits 0, 1, …, 1022, 1023. PDU 0's leading fragment is dropped in loss mode, and PDU 1023's head is never completed. The PDCP-SN map then only re-sorts the survivors, so the map was a patch over the raw walk |
| The PDCP reference is unavailable | `ForwardRlcBuffers(…, 0, …)` passes no PDCP at `lte-enb-rrc.cc:978` (the SN-change path this project uses, `ea6e46f6`) and at `:2305`. `GetStatus` is non-virtual (`lte-pdcp.h:111`) and is redeclared, together with `m_txSequenceNumber`, in `mc-enb-pdcp.h:139,226` and `mc-ue-pdcp.h:124,195`. Through `Ptr<LtePdcp>` you read LtePdcp's counter, which an MC entity never advances |
| A packet-tag arrival index cannot work | `Packet::AddAtEnd` merges byte tags only (`src/network/model/packet.cc:354-363`). An SDU's packet tags do not survive concatenation into a PDU |
| SRB and UM are unaffected | Forwarding iterates only `m_drbMap` / `m_rlcMap` (`lte-enb-rrc.cc:956-979`; UE callers `lte-ue-rrc.cc:1409,1487,2103,2470`). The UM branches copy the txon buffer FIFO (`lte-enb-rrc.cc:1135-1148`, `lte-ue-rrc.cc:1808-1815`) |
| The UE side never needs a PDCP SN reference | `CopyRlcBuffers` puts every SDU back into its PDCP (`lte-ue-rrc.cc:1846-1862`), which assigns new SNs in forwarding order |
| **scenario-zero DRBs are RLC UM** | `MmWaveHelper::RlcAmEnabled` defaults to false (`src/mmwave/helper/mmwave-helper.cc:93,164-167`). It maps to `RLC_UM_LOWLAT_ALWAYS` for both the gNB and the eNB (`:2085-2093`, `:2386-2392`; `GetRlcType` `lte-enb-rrc.cc:5920-5955`). `scratch/scenario-zero.cc` never sets it (only scenarios one, two, three and five do), and no harness script passes an `ns3::` override |

## Q1: Which reference

**Recommended: RLC transmission order, read modulo 1024 from VT(A).**

### Why each candidate stands or falls

| Candidate | Exact when | Available at :978, :2305 and the UE? | Verdict |
|---|---|---|---|
| Widest gap (the draft) | Retained span < 2048 (spec invariant, not enforced) | yes | Silently wrong on reachable states, worse than the old code there |
| PDCP next TX SN | Span < 4096 | **no** (`pdcp = 0`; hidden `GetStatus`) | Would need X2 plumbing: scope blow-up |
| Per-SDU arrival index (tag) | Always | yes, but packet tags die at concatenation; a byte tag leaks through forwarding (`lte-enb-rrc.cc:1194` strips packet tags only) | Reject. The RLC SN already *is* the arrival index |
| **RLC transmission order** | Each RLC receives its SDUs in COUNT order (PDCP submits in COUNT order; the RLC numbers PDUs in arrival order). The window of 512 < 1024/2 is enforced | yes, using RLC state only | **Choose** |

### Code points

1. **`lte-rlc-am.h:83-87` / `lte-rlc-am.cc:1188-1214`.** Add `std::vector<RetxPdu> GetUnackedPdusInTransmissionOrder() const`:
   - Copy `sn = m_vtA`, then `sn.SetModulusBase(m_vtA)`.
   - Copy `end = m_vtS`, then `end.SetModulusBase(m_vtA)`.
   - Loop `for (; sn < end; sn++)`, pushing `m_txedBuffer[v]` if it is non-null, else `m_retxBuffer[v]` if non-null.
   - Set the bases on **both** copies. `SequenceNumber10::operator>` asserts equal bases (`lte-rlc-sequence-number.h:158-163`), and the members' bases can differ.
   - txed and retx are disjoint (assert `lte-rlc-am.cc:2291`; the moves at `:2258-2270` and `:551-561`), so "txed, else retx" matches `MergeBuffers`' equal-SN branch.
   - Remove `GetTxedBuffer` and `GetRetxBuffer`: they are dead after the change, and keeping them invites another raw walk. Keep `GetTxedBufferSize` and `GetRetxBufferSize`.
2. **`lte-enb-rrc.cc:1003-1029` and `lte-ue-rrc.cc:1669-1695`.**
   - Keep the guard `retxBufferSize + txedBufferSize > 0`, then call `rlcAm->RlcPdusToRlcSdus(rlcAm->GetUnackedPdusInTransmissionOrder())`.
   - Delete `UeManager::MergeBuffers` (`lte-enb-rrc.cc:796-867`, declaration `lte-enb-rrc.h:474-475`).
   - Delete `LteUeRrc::MergeBuffers` (`lte-ue-rrc.cc:~1581-1652`, declaration `lte-ue-rrc.h:756-757`).
3. **`lte-rlc-am.cc:1811-1823` (`CreateRlcSduBuffer`).**
   - Add `std::vector<uint16_t> m_transmittingRlcSduOrder` next to the map (`lte-rlc-am.h:214-217`).
   - Append an SN only when `find(sn) == end()`, then assign as today (the latest copy wins, as now).
   - Clear it in `DoDispose` (`:227-228`).
   - This reuses the existing PDCP-header parse, so P7 gets no new consumer.
4. **Getter (`lte-rlc-am.cc:1216-1233`).** Walk `m_transmittingRlcSduOrder` and emit `(sn, map.at(sn))`. Keep the draft's `vector<pair<uint16_t, Ptr<Packet>>>` signature. Doc comment: transmission order, which is COUNT order.
5. **Lookback.** Keep the draft's `IsPdcpSnInForwardingLookback` and `PDCP_SN_SPACE`, and the edits at `lte-enb-rrc.cc:1107-1111` and `lte-ue-rrc.cc:1776-1779`. Delete `OrderPdcpSnsByCount` and its cases.

Cross-checks:

- **SRB:** never reaches these functions, and the new method is header-agnostic anyway.
- **UM:** untouched.
- **UE / `McUePdcp`:** identical, since the method uses RLC state only.
- **`:978` / `:2305`:** need no PDCP.

## Q2: Scope

**Inside row 160:**

- the ordering reference itself (the row says "COUNT order", not how to get it);
- the getter;
- the lookback.

**Beyond row 160:**

- the RLC 10-bit walk (both `MergeBuffers` deleted, VT(A)-relative walk);
- its behavioural side effect at RLC wraps: the straddling SDU is now recovered.

This is a second defect fixed, so it needs a ruling. It is cheap:

- it is additive;
- nothing in M5–M7 or N4 executes it (RLC UM);
- it follows 36.322 §7.1.

Route it through brainstorm consensus; if unanimous, apply. Default: **one commit** with the amendment, because the walk is what makes the transmission-order getter correct. If consensus enforces strict one-defect-per-commit, split into a walk commit (new row 162, judged by (d)–(f) below) followed by the getter commit (row 160). Both must land before P7, and P7's identity baseline is the last of them.

Proposed ledger text:

> Row 160, amended before code (2026-11-07, kongming-261107-0555 on the Codex pre-ship finding; it adds conditions and weakens none): COUNT order is taken from the RLC AM transmission order, not from the PDCP SNs alone. `UeManager::ForwardRlcBuffers` and `LteUeRrc::CopyRlcBuffers` read the unacknowledged PDUs through `LteRlcAm::GetUnackedPdusInTransmissionOrder`, which walks VT(A) ≤ SN < VT(S) with VT(A) as the modulus base (TS 36.322 §7.1) and takes each SN's PDU from the transmitted or the retransmission buffer. Both `MergeBuffers` (raw SN compare, modulus base 0) are removed. `GetTransmittingRlcSduBuffer` returns each PDCP SN once, in the order its SDU was first reassembled. The original pass rule is judged through that getter. Added conjuncts, all in suite `pdcp-sn-wrap` (check `m4_ns3_pdcp_sn_wrap_suite_passes`, unchanged):
> (c) PDUs carrying PDCP SNs {10, 3010} in that order come back as 10, 3010; {3010, 10} come back as 3010, 10.
> (d) On an `LteRlcAm` driven only through `DoTransmitPdcpPdu`, `DoNotifyTxOpportunity` and STATUS PDUs on `DoReceivePdu` to VT(A) = 1022, holding PDUs with RLC SNs 1022, 1023, 0, 1 that carry PDCP SNs 4094, 4095 (segmented across RLC SNs 1023 and 0), 0, 1: the walk returns RLC SNs 1022, 1023, 0, 1, and the getter returns 4094, 4095, 0, 1 with SDU 4095 whole.
> (e) The same after a STATUS PDU with ACK_SN 0 and NACK_SN {1022, 1023}, which leaves 1022 and 1023 in the retransmission buffer and 0 and 1 in the transmitted buffer.
> (f) No-wrap identity: VT(A) = 5, RLC SNs 5–8 carrying PDCP SNs 100–103 with SDU 101 segmented across RLC SNs 6 and 7, both before and after a NACK of {5, 6}: walk 5, 6, 7, 8 and getter 100–103.
> Non-vacuity: at `m10-cp2`, with the old RRC selection and `MergeBuffers` copied verbatim into a red-only shim (its sha256 recorded), (c, second half), (d) and (e) are red. (c, first half) and (f) are green by design. (c, first half) is red at the widest-gap draft. Recorded openly: this also fixes the RLC 10-bit wrap of the same path, a pre-existing defect beyond the row's PDCP scope. scenario-zero runs RLC UM low-latency (`MmWaveHelper::RlcAmEnabled` false, never set), so no M5–M7 or N4 run executes these paths. Contract change: No.

## Q3: Behaviour without any wrap

The new output is identical to the old when four conditions all hold:

1. There is no RLC wrap in [VT(A), VT(S)). Then the VT(A) walk equals the raw ascending walk, because no entries exist outside the window (cleared at `:2278-2311`, moved only within it). So the same PDUs go to the same reassembly and produce the same `m_transmittingRlcSdus`.
2. There is no PDCP wrap or 4096-alias among the retained SDUs.
3. Each RLC received its SDUs in COUNT order.
4. Under 1–3, first-insertion order equals ascending SN, which is what the map gave.

Sparse {10, 3010} sent in that order gives 10, 3010, the same as the old code. The lookback is identical for SN_1 ≥ 2.

Repeated `ForwardRlcBuffers` on one RLC (for example `:1756`, then `:2176`) keeps the map's semantics: dedup by SN and latest copy, with positions unchanged under 1–3.

**One honest exception (condition 3 fails).** The X2 double-hop race at an SN-change target:

- Packets in flight to the source are re-forwarded (`epc-x2.cc:642-674`) and can arrive after fresh, newer SNs.
- If the same UE then changes cell again while those SDUs are still unacknowledged, the new code forwards them a position or two late. The old ascending sort, and the draft, were right there.
- It needs two cell changes within the RLC retention time. It is a model artifact: per spec, the target sends forwarded data before fresh data.
- Record it as a residual; do not engineer a heuristic for it.

**In project runs, nothing changes at all** (RLC UM).

## Q4: Tests (suite `pdcp-sn-wrap`)

| Case | Path | cp2 (shim) | Draft A | New |
|---|---|---|---|---|
| L0/L1 lookback at SN_1 = 0, 1 (keep) | helper | red | green | green |
| L2/L4095 lookback (keep) | helper | green | green | green |
| B0 direct `RlcPdusToRlcSdus` {4094, 4095, 0, 1} (keep) | getter | red | green | green |
| B1 {10, 3010} in transmission order | getter | green | **red** | green |
| B2 {3010, 10} (10 after the wrap) | getter | red | green | green |
| B3 two `RlcPdusToRlcSdus` calls with overlap plus newer SNs: each SN once, first-insertion order, latest copy | getter | green | green | green |
| W1 = (d), SAP-driven, RLC 1022..1 with a straddling SDU | walk + getter | red (0, 1, 4094; SDU 4095 missing) | red | green |
| W2 = (e), STATUS ACK_SN 0 with NACK {1022, 1023} | walk + getter | red (merge gives 0, 1, 1022, 1023) | red | green |
| N1 = (f), no-wrap identity, txed-only and NACK {5, 6} | walk + getter | green | green | green |

Building W1/W2:

- Use `LteTestMac` from `src/lte/test/lte-test-entities.h:237-330` as the MAC SAP provider, and call `DoTransmitPdcpPdu` and `DoNotifyTxOpportunity` directly (both public in this fork).
- Advance VT(A) in chunks below 512: about 500 PDUs, then a STATUS `SetAckSn`, repeated up to 1022.
- Size the TX opportunities so PDU 1023 = [head of 4095] and PDU 0 = [tail of 4095 + SDU 0].
- **Assert the setup:** the FI flags of the captured PDUs 1023 and 0 must be FIRST|NO_LAST and NO_FIRST|LAST, so a mis-sized fixture cannot pass vacuously.
- `m_txCompletedCallback` is a `TracedCallback` (`lte-rlc.h:258-259`), so it is safe with nothing connected. `DoReceivePdu` tolerates the missing `RlcTag` (`lte-rlc-am.cc:1891-1897`).
- Keep `Simulator::Destroy` in teardown, as the draft does.

## Q5: P7 byte identity and N4 determinism

- **No runtime risk from this design.** No scenario-zero run executes the AM branches (RLC UM). The change adds no RNG and no pointer-keyed or unordered containers, and changes no plain-build flags. The `--tests` filter change only affects the test tree.
- **Row 148 (b) is partly vacuous.** N4 byte identity covers the PDCP entities and the UM send loops (`lte-enb-rrc.cc:1186-1210`, `lte-ue-rrc.cc:1846-1862`). It covers nothing on these AM-only consumers:
  - `CreateRlcSduBuffer`;
  - the AM-branch header peeks at `lte-enb-rrc.cc:1043,1081,1095,1103` and their UE equivalents.

  Those are covered only by row 148 (a)'s unit suite, row 160's suite and phase-10 step 2(c). Record this as an open note on row 148. It is not a predicate change.
- **The decision record overstates.** `decisions-261106-0525…:15` gives "the wrap fix runs live" as a reason. The SNs do wrap live, but the defective AM code does not run. The 12-bit ruling's other reasons stand. Record the correction; do not reopen the ruling.
- **Line drift.** Phase-10 Design `:19-27` lists consumers by line (`lte-rlc-am.cc:1801`, `lte-enb-rrc.cc:1034,1091,1176`, `lte-ue-rrc.cc:1700,1759,1829`). These have already drifted, and deleting `MergeBuffers` shifts them by about 70 lines. P7 must re-enumerate by symbol (`LtePdcpHeader` on MC-reachable paths), and its lint should key on symbols.
- **Width coupling.** Under this design, only the lookback (`PDCP_SN_SPACE = 4096`) depends on SN width. That is fine at 12 bits (Q4 ruling). P7 should take the modulus from the bearer's header class, or `static_assert` its 12-bit width.
- **Red evidence.** The draft's red run in `evidence/p10-sn-wrap/red-at-cp2-code/` covers the old case set. Regenerate it for the new suite.

## What to avoid

- **Keeping widest-gap as a fallback or second ordering.** That is two mechanisms and a legacy mode.
- **Reading PDCP state through `Ptr<LtePdcp>`.** The same hiding bug already makes the SN Status Transfer at `lte-enb-rrc.cc:927` report LtePdcp's dead counter for MC bearers. It is pre-existing and AM-only; it is a follow-up, not this commit.
- **Comparing `SequenceNumber10` values whose modulus bases differ.** This trips the debug assert.
- **Fixing the neighbouring pre-existing defects here.** Each changes no-wrap behaviour and needs its own row:
  - `m_transmittingRlcSdus` is never cleared (the `TODO`);
  - the lookback includes SN_1 itself, so the head SDU is duplicated;
  - `m_segmented_rlcsdu` is never reset;
  - SNs 4096 apart collapse into one map key;
  - `m_txedRlcSduBuffer` misses the first SDU of each PDU (`:797-814` versus `:1000`), so the lookback is sparse.
- **Claiming M5–M7 or N4 "exercise the fix".**

## Alternatives and trade-offs

- **Keep the draft (A).** No ruling, smallest diff, exact for every spec-conformant state. It is silently wrong, and worse than the old code, on states the model does produce (E2 split skew, dense AM retention). Accept it only if consensus rejects any RLC-walk change. In that case, record row 160 as "exact while the retained span is < 2048; the model does not enforce the PDCP half-window".
- **Split into two commits** (walk → row 162, getter → row 160). Same code, cleaner bisection, more ceremony, and no run impact either way.
- **COUNT byte tag set at the PDCP.** The most faithful option, but it touches all three PDCP classes (P7's files), byte tags leak across forwarding, and it interacts with `PdcpTag`. Not for this commit.

## Work checklist

1. Brainstorm consensus on the row 160 amendment (and single versus split commit). Commit the ledger amendment before the code.
2. Implement code points 1–5. Delete `MergeBuffers` ×2, `OrderPdcpSnsByCount`, `GetTxedBuffer` and `GetRetxBuffer`.
3. Rewrite the suite per Q4. Re-run red at `m10-cp2` with a verbatim-shim, and record its sha256 and a per-case table. Run B1 against the draft tree and keep that red result.
4. Green at the fix. Also run `lte-rlc-am-transmitter`, `lte-rlc-am-e2e`, `lte-rlc-header` and `mmwave-neighbour-list`.
5. Run the Codex follow-up review of this fix (never skip it); then M4, M5–M7; then the row 148 (b) determinism check (two builds) at this commit.
6. Add the record notes: row 148 (b) coverage scope, the decision-record correction, and follow-up candidates for the pre-existing defects.
7. Optional, to confirm the UM claim at runtime: run a short scenario-zero in a debug build with `NS_LOG=LteRlcAm=level_function` and expect no `DoTransmitPdcpPdu` lines with lcid ≥ 3.

## Success metrics

- Every red case in Q4 is red at cp2 and green at the fix. B1 is red at the draft.
- `grep -rn MergeBuffers\|OrderPdcpSnsByCount src/` returns nothing.
- The Codex follow-up review raises no ordering finding.
- M4 and M5–M7 are green, and the two-build N4 runs are byte-equal.

## Assumptions

| Assumption | Confidence | What would change the answer |
|---|---|---|
| scenario-zero DRBs run RLC UM low-latency, so AM forwarding is dead in project runs | high (three static citations) | A runtime override of `RlcAmEnabled`; the step 7 probe settles it |
| Within one RLC, entry order is COUNT order except for the X2 double-hop race | medium-high | Another reordering path into an RLC; then B3-style local reorders would need a ruling |
| The 36.322 clause numbers (§7.1 modulus base with VT(A); §7.2 AM_Window_Size = 512) | medium (from memory) | Verify in Zotero before citing them in code or the ledger |
| Consensus accepts the mechanism and its side effect in one commit | medium | A strict one-defect rule: split into rows 162 and 160 |
| `LteTestMac` can drive `LteRlcAm` in this fork without the simulator running | high | If a TX path needs scheduled events, run `Simulator::Run` with a stop time |

## Unresolved questions

1. Single commit with the amended row 160, or split into row 162 (walk) and row 160 (getter)?
2. Where to record the "wrap fix runs live" correction: the decisions file or row 148's note?
3. Should the pre-existing AM LL-HO defects get follow-up rows now, or stay logged? They are low priority while project runs use RLC UM.

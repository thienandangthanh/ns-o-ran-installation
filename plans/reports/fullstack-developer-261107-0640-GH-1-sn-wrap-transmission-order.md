# SN-wrap fix reworked to RLC transmission order: implementation report

Status: done, uncommitted. The widest-gap draft has been reworked in place in the `ns-3-mmwave-oran/` working tree. Per-case results:
- At the cp2 shim, the suite is red on exactly the cases the amended row 160 expects.
- At the saved widest-gap draft, (c) {10,3010} and (g) are red.
- At the fix, all 13 cases are green, and the four neighbouring suites pass.

## Files changed

ns-3 fork (`ns-3-mmwave-oran/`, uncommitted; 7 tracked files, +102/−223, and 3 new files):
- **`src/lte/model/lte-rlc-am.h/.cc`**
  - New `std::vector<RetxPdu> GetUnackedPdusInTransmissionOrder() const`. It walks VT(A) <= SN < VT(S) on copies of `m_vtA`/`m_vtS`, with both modulus bases set to VT(A). At each SN it takes the transmitted-buffer PDU, else the retransmission-buffer PDU.
  - The comment cites ETSI TS 136 322 V16.0.0 §5.1.3.1.1, §7.1 and §7.2. I checked the clause text in the ETSI PDF: VT(A) is the modulus base at the transmitting side; the window is VT(A) <= SN < VT(MS); AM_Window_Size is 512.
  - `GetTxedBuffer` and `GetRetxBuffer` are removed; `GetTxedBufferSize` and `GetRetxBufferSize` are kept.
  - `CreateRlcSduBuffer` keeps the SN-keyed map (the latest copy replaces the earlier one). It appends an SN to the new `m_transmittingRlcSduOrder` only when the SN is new. `DoDispose` clears both, and a comment says the order vector has the map's lifetime.
  - `GetTransmittingRlcSduBuffer` returns `(sn, sdu)` pairs in first-insertion order. The pre-existing TODO is kept.
- **`src/lte/model/lte-enb-rrc.cc/.h`, `src/lte/model/lte-ue-rrc.cc/.h`**
  - The txed/retx selection and `MergeBuffers` are replaced by `rlcAm->RlcPdusToRlcSdus(rlcAm->GetUnackedPdusInTransmissionOrder())` under the kept `retx + txed > 0` guard.
  - Both `MergeBuffers` definitions and declarations are deleted.
  - The modular lookback call is kept, and the forwarding comment now says "transmission order (COUNT order)".
- **`src/lte/model/lte-pdcp-sn-wrap.h/.cc`**: only `PDCP_SN_SPACE` and `IsPdcpSnInForwardingLookback` remain. `OrderPdcpSnsByCount`, `<vector>` and `<algorithm>` are dropped.
- **`src/lte/test/lte-test-pdcp-sn-wrap.cc`**: suite `pdcp-sn-wrap` rewritten, 13 cases (see the tables below).
- `src/lte/CMakeLists.txt` is unchanged from the draft (helper and test registered).

Harness:
- `scripts/build-ns3.sh` is unchanged from the previous draft (filter `mmwave;lte`; its wording is still correct).
- `scripts/gates/gate-m4-ns3-build.sh`: only the comment above the unchanged check line changed. It now reads "...across the 12-bit PDCP and 10-bit RLC AM SN wraps (src/lte/test)".

## Suite design

| Idx | Case | Path |
|---|---|---|
| 0–3 | L0, L1, L2, L4095: lookback over all 4096 SNs | helper |
| 4 | Direct `RlcPdusToRlcSdus` over hand-built PDUs with PDCP SNs {4094,4095,0,1} | getter |
| 5 | Direct, no wrap {10..13} (extra control) | getter |
| 6, 7 | (c) {10,3010} and {3010,10} in transmission order, VT(A)=0 | SAP |
| 8 | (d) VT(A)=1022, RLC SNs 1022, 1023, 0, 1 carrying PDCP 4094, [head 4095], [tail 4095 + 0], 1 | SAP |
| 9 | (e) as (d), then a STATUS PDU with ACK_SN 0 and NACK {1022, 1023} | SAP |
| 10, 11 | (f) VT(A)=5, PDCP 100..103 with SDU 101 straddling RLC SNs 6 and 7; txed only, and after a NACK of {5, 6} | SAP |
| 12 | (g) VT(A)=1022, PDCP 100..103 with SDU 101 straddling RLC SNs 1023 and 0; then forwarded a second time | SAP |

How the SAP cases (6–12) work:
- **Real SAPs only.** The RLC is driven through `GetLteRlcSapProvider()->TransmitPdcpPdu`, `GetLteMacSapUser()->NotifyTxOpportunity` and `ReceivePdu` (STATUS PDUs). I used a small in-file capturing `LteMacSapProvider` rather than `LteTestMac`, because `LteTestMac` strips the headers off the packets it receives, and the FI precondition needs the PDUs with headers intact.
- **Getting to VT(A).** Filler SDUs are sent and acknowledged in batches of 256, below the 512 window.
- **Preconditions** (each case stops if one fails):
  - txed + retx = 0 after the fillers;
  - every built PDU has the intended RLC SN and FI (the boundary PDUs are FIRST|NO_LAST and NO_FIRST|LAST);
  - after a NACK, retx > 0 and txed > 0.
- **Checks.**
  - The SN order is checked.
  - Every SDU must carry its own PDCP SN and be whole: its size is the PDCP header plus that SDU's distinct payload size.
  - For (g)'s second forwarding: the sorted SN set equals the expected set with each SN once, and every SDU is a new, whole copy. Cross-call position is not asserted.

## Red at the cp2 shim (`evidence/p10-sn-wrap/red-at-cp2-shim/`)

The tree is the pinned ns-3 (its src/lte equals cp2's) plus four additions:
- the suite;
- the fix's helper header;
- a red-only lookback `.cc` with cp2's `sn >= (SN_1 - 2) && sn <= SN_1`;
- a red-only `GetUnackedPdusInTransmissionOrder` shim in `lte-rlc-am.{h,cc}`.

The map, `CreateRlcSduBuffer`, `Reassemble` and the getter are cp2's code, unchanged.

**Shim.** `make-cp2-shim.py` generated it from cp2's `lte-enb-rrc.cc` text. `shim-vs-cp2.diff` shows the only differences from the cp2 text:
- `UeManager::MergeBuffers(` became a file-local `MergeBuffers(`;
- the selection block was wrapped in a method that binds `LteRlcAm* rlcAm = this`;
- `sortedTxedRetxBuffer` is declared outside the `if` so it can be returned;
- `rlcAm->RlcPdusToRlcSdus(sortedTxedRetxBuffer);` became a `return`.

All other lines are verbatim. `cp2-ue-vs-enb.diff` shows cp2's UE copy is identical except for its `"UE RRC: "` log prefixes, and the MergeBuffers bodies are identical. The sha256 values are in `shim-sha256.txt`; `red-tree-shim.diff`, the generator and the red lookback are kept alongside.

| Idx | Case | cp2 shim | Old output |
|---|---|---|---|
| 0 | L0 | **FAIL** | `0` |
| 1 | L1 | **FAIL** | `0,1` |
| 2 | L2 | PASS | |
| 3 | L4095 | PASS | |
| 4 | direct {4094,4095,0,1} | **FAIL** | `0,1,4094,4095` |
| 5 | direct no wrap | PASS | |
| 6 | (c) 10, 3010 | PASS (by design) | |
| 7 | (c) 3010, 10 | **FAIL** | `10,3010` |
| 8 | (d) | **FAIL** | `0,1,4094`: SDU 4095 lost |
| 9 | (e) | **FAIL** | `0,1,4094` |
| 10 | (f) txed | PASS (by design) | |
| 11 | (f) NACK | PASS (by design) | |
| 12 | (g) | **FAIL** | `100,102,103`: SDU 101 lost |

Every red result comes from the order/content check, not from a precondition.

## Red at the widest-gap draft (`evidence/p10-sn-wrap/red-at-widest-gap-draft/`)

The tree is the pinned ns-3 plus the saved `ns3-draft.diff` (its sha256 checked OK), the same shim (byte-identical, because the draft kept cp2's MergeBuffers selection), and the new suite.

| Idx | Case | Draft | Output |
|---|---|---|---|
| 0–5 | | PASS | |
| 6 | (c) 10, 3010 | **FAIL** | `3010,10` |
| 7 | (c) 3010, 10 | PASS | |
| 8, 9 | (d), (e) | **FAIL** | `4094,0,1`: SDU 4095 lost |
| 10, 11 | (f) | PASS | |
| 12 | (g) | **FAIL** | `100,102,103` |

## Green at the fix (`evidence/p10-sn-wrap/green-transmission-order/`)

- The tree is the working-tree fix; its tracked diff and new files are byte-identical to the working tree.
- `test.py`: `[1/1] PASS: TestSuite pdcp-sn-wrap`, and the gate PASS-line regex matches.
- The per-case table shows all 13 cases PASS.
- lte-rlc-am-transmitter, lte-rlc-am-e2e, lte-rlc-header and mmwave-neighbour-list all PASS (`neighbouring-suites.txt`).
- The only compiler warnings on the touched files are pre-existing `!= NULL` deprecations.

The older `red-at-cp2-code/` and `green/` directories are left as history.

## Other checks

- The grep of `src/` (excluding `bindings/`) for `MergeBuffers`, `OrderPdcpSnsByCount`, `GetTxedBuffer(` and `GetRetxBuffer(` returns 0 matches. Only the stale pybindgen files in `src/mmwave/bindings/` still name them; ns-3.38 does not build those files.
- There are no plan IDs, rows, phases or audit labels in the code, comments or test names.
- `bash scripts/gates/lint.sh` reports `lint: ok` (rc 0). shellcheck is clean on both scripts.
- The host build used the same flags as `build-ns3.sh --tests`, with Python 3.12 from uv. The tree was at `/tmp/claude-1000/ns3-sn-wrap-txorder-910ba118`, a path without "scratch"; it has been removed. The VM was not touched; nothing was committed or stashed.

## What I could not do or did differently

- **Per-case runs need a probe.** ns-3 stops a suite at its first failing case. Each per-case table therefore comes from a probe build whose only change is the suite constructor registering the case selected by `PDCP_SN_WRAP_CASE`. The probe was reverted and rebuilt, and the suite file was `cmp`-checked afterwards.
- **(c) comes from a fresh RLC at VT(A)=0.** The brief only says "in transmission order", and the row says "every RLC case through SAP".
- **The repeated-forwarding check is only in (g).**

## Unresolved questions

1. `plans/.gitignore` still ignores `evidence/p10-sn-wrap/**`. It needs `!/*/evidence/p10-sn-wrap/**` before the commit.
2. The evidence `test-py-*.txt` files contain test.py's environment dump (host PATH). It is harmless but noisy; trim it if you prefer.

Status: DONE
Summary: Transmission-order fix implemented in place. The suite is red at the cp2 shim on L0, L1, B0, (c) {3010,10}, (d), (e) and (g); green there on (c) {10,3010} and (f); red at the widest-gap draft on (c) {10,3010} and (g) (plus (d) and (e)); and fully green at the fix, with the neighbouring suites, lint and shellcheck clean.
Concerns: The gitignore negation for the evidence dir is still needed before the commit.

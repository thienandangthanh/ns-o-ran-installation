# P7: NR PDCP data-PDU header on the EN-DC (MC) bearer — implementation report

Status: done, uncommitted, in the `ns-3-mmwave-oran/` working tree on top of 4a0871d6. Results:
- The new suite `mc-pdcp-nr-header` has 37 cases. All pass at the change.
- At 4a0871d6, behind a shim, exactly the header-class checks fail (21 cases). Every byte, SN, order and payload check passes there, as expected, because the E-UTRA and NR 12-bit headers are byte-identical.
- The host N4 runs are byte-identical to 4a0871d6 on the whole compared set except the audit header line.

Design counsel (kongming, Opus): `plans/reports/kongming-261107-0830-GH-1-p7-nr-pdcp-header-design.md`. I adopted it as given, including its change to the LtePdcp assertion.

## Spec read (Zotero `MSNDDXJH`, 3GPP TS 38.323 V19.1.0, ETSI 2026-02)
- §6.2.2.2, Figure 6.2.2.2-1: octet 1 = D/C, R, R, R, PDCP SN[11:8]; octet 2 = SN[7:0]; then data. MAC-I is optional.
- §6.3.2: the SN is 12 or 18 bits.
- §6.3.4: on a DRB, MAC-I is present only with integrity protection, which the model never configures.
- §6.3.6: R bits are set to 0 and "shall be ignored by the receiver".
- §6.3.7: D/C 1 = Data PDU, 0 = Control PDU.
- 37.340 §4.2.2 (via kongming): an MN-terminated split bearer uses NR PDCP.

These clauses are cited in the code comments.

## Files (ns-3 fork, 17 tracked files, +216/−67, plus 3 new)
- **New `src/lte/model/nr-pdcp-header.{h,cc}`**: `NrPdcpHeader`, TypeId `ns3::NrPdcpHeader`, 2 octets, `SN_SPACE = 4096`.
  - Serialize writes R = 0.
  - Deserialize decodes D/C and the SN and ignores the R bits, per §6.3.6. It does not reject them: the clause says the receiver ignores them.
  - `SetSequenceNumber` aborts at SN ≥ 4096, and `SetDcBit` aborts above 1.
- **`mc-enb-pdcp.{h,cc}`, `mc-ue-pdcp.{h,cc}`**:
  - New public `using DataPduHeader = NrPdcpHeader;` and `CreateDataPduHeader() override`.
  - TX and RX use `DataPduHeader`.
  - RX aborts on D/C = 0 (the model sends Data PDUs only).
  - `DoTransmitPdcpSdu` and `DoReceivePdu` are now `override`, so a signature drift is a compile error.
  - The state-variable comments now cite 38.323.
- **`lte-pdcp.{h,cc}`**:
  - New `virtual std::unique_ptr<Header> CreateDataPduHeader() const` (the base returns an `LtePdcpHeader`).
  - New tripwire `AssertEUtraEntity()`, called first in `DoTransmitPdcpSdu` and `DoReceivePdu`: `NS_ABORT_MSG_IF(GetInstanceTypeId() != LtePdcp::GetTypeId(), …)`.
  - The E-UTRA codec itself is unchanged.
- **`lte-rlc-am.{h,cc}`**:
  - `RlcPdusToRlcSdus` and `CreateRlcSduBuffer` are now member templates over `PdcpDataPduHeader`.
  - There is one explicit instantiation, for `NrPdcpHeader`. A call with any other class fails at link time.
  - `lte-rlc-am.h` no longer includes `lte-pdcp-header.h`.
- **`lte-ue-rrc.{h,cc}`**:
  - `CopyRlcBuffers(Ptr<LteRlc>, Ptr<McUePdcp>, lcid)` aborts on a null PDCP and uses `McUePdcp::DataPduHeader` throughout.
  - Two callers now pass the already-cast `pdcp`, which is the same object.
- **`lte-enb-rrc.{h,cc}`**:
  - `ForwardRlcBuffers(…, Ptr<McEnbPdcp> pdcp, …)` uses `McEnbPdcp::DataPduHeader`.
  - The declaration documents why a 0 `pdcp` still means an MC bearer: an `m_rlcMap` SN-side RLC, or an RLC-SM DRB with no buffers.
  - The handover caller `DynamicCast`s and aborts if a DRB's non-null PDCP is not an `McEnbPdcp`.
  - The switch caller passes the cast `pdcp`.
- **`mmwave-enb-net-device.cc`**: `pdcpHeaderBytes = McEnbPdcp::DataPduHeader().GetSerializedSize()`. P9's counting logic is unchanged; only the size source and its comment changed.
- **`lte-pdcp-sn-wrap.h`**: comment only. It no longer names `LtePdcpHeader`.
- **`scratch/scenario-zero.cc`**: the audit header line (see below), the `:49` comment block, and `<lte-pdcp.h>` replacing `<lte-pdcp-header.h>`.
- **`src/lte/CMakeLists.txt`**: the new header source and the new test registered.
- **`src/lte/test/lte-test-pdcp-sn-wrap.cc`**: its PDUs and calls now use `NrPdcpHeader` / `RlcPdusToRlcSdus<NrPdcpHeader>`. The forwarded buffers are MC bearers', so row 160's suite re-checks this wiring.
- **New `src/lte/test/lte-test-mc-pdcp-nr-header.cc`**: the suite (below).

## Audit header line: how it is printed
- **What changed.** The line is no longer printed at `:727`, before `Simulator::Run`, when no PDCP entity exists.
  - It is now printed in `N4AuditConnectUe`, at the first DRB PDCP entity connected.
  - It is built from that entity's own header object (`pdcp->CreateDataPduHeader()`): `N4AUDIT v1 hdr=<GetSerializedSize> class=<GetInstanceTypeId().GetName()>`.
  - Every later connected entity must give the same pair, or the run aborts.
- **Why at run time.** A static print would still say NrPdcpHeader if DRB setup regressed to `LtePdcp`; the runtime print would not.
- **Position.** In the host ulon run the line is still stdout line 1. The judge strips the first `hdr=` line wherever it is.
- **uloff.** uloff still has 0 `N4AUDIT` lines.
- **Field layout.** `class=` is field 4.

## Suite `mc-pdcp-nr-header` (37 QUICK cases)
Every case first calls `Packet::EnablePrinting()`, so each packet records the class of each header added to it. The suite therefore needs its own process; `test.py -s` gives it one. `OuterHeaderClass(p)` reads that record. It is the only runtime check that can tell the two byte-identical headers apart.

| Idx | Case | 4a0871d6 shim | Change |
|---|---|---|---|
| 0–4 | `NrPdcpHeader` codec at SN {0, 1, 2047, 2048, 4095}: octets per the clause, R bits ignored on decode, D/C 0 decoded as control | PASS (new class, not a discriminator) | PASS |
| 5 | Header class: `McEnbPdcp/McUePdcp::DataPduHeader` is `NrPdcpHeader`; the header objects through the base class are NrPdcpHeader/2 (MC) and LtePdcpHeader/2 (LtePdcp) | **FAIL** | PASS |
| 6, 11, 16, 21, 26 | DL `McEnbPdcp` TX at each SN: PDU = SDU + 2, octet layout, payload byte-equal, TX SN + 1 mod 4096, writer class NrPdcpHeader | **FAIL** (only the class checks) | PASS |
| 7, 12, 17, 22, 27 | UL `McUePdcp` TX, the same checks | **FAIL** (only the class checks) | PASS |
| 8, 13, 18, 23, 28 | DL `McUePdcp` RX of a hand-built PDU (raw bytes): SDU delivered byte-equal, RX SN = SN + 1 mod 4096 | PASS | PASS |
| 9, 14, 19, 24, 29 | UL `McEnbPdcp` RX of a hand-built PDU, the same checks | PASS | PASS |
| 10, 15, 20, 25, 30 | SRB1 `LtePdcp` unchanged: LtePdcpHeader/2, same octets, writer class LtePdcpHeader, RX delivers | PASS | PASS |
| 31–33 | eNB X2 forwarding, case (b)+(c) | **FAIL** (only the class checks) | PASS |
| 34–36 | UE RLC switch, case (b)+(c) | **FAIL** (only the class checks) | PASS |

The eNB X2 forwarding cases (31–33):
- The real `McEnbPdcp` sends PDCP SNs 4094, 4095, 0, 1 into a real `LteRlcAm`, driven through its SAPs with a capturing MAC. VT(A) is 1022 (both wraps), 1022 with NACK {1022, 1023}, or 5 (PDCP wrap only).
- The PDCP SDU with SN 4095 straddles RLC PDUs. The RLC SN and framing-info preconditions are checked.
- `RlcPdusToRlcSdus<McEnbPdcp::DataPduHeader>` must recover SNs 4094, 4095, 0, 1 in that order. Each recovered SDU must carry its own SN, be whole and keep its writer class.
- Each SDU is then stripped of its header and tags and sent into a target `McEnbPdcp` at TX SN 4095. The new SNs are 4095, 0, 1, 2: the SN change, wrapping again.
- The UE `McUePdcp` must deliver all 4 original SDUs byte-equal and in order, with RX SN 3.

The UE RLC switch cases (34–36):
- These are the mirror of 31–33: `McUePdcp` sends into `LteRlcAm`, the recovery uses `McUePdcp::DataPduHeader`, and each SDU is sent again into the same `McUePdcp` on a new RLC.
- The new SNs are 2, 3, 4, 5. `McEnbPdcp` must deliver the originals.

**What the red run shows, honestly.**
- Red tree: 4a0871d6 plus the new header class, the suite, and a red-only shim. The shim diff and its sha256 are saved as evidence.
  - The shim exposes the old header class through the new API names: `CreateDataPduHeader` returns LtePdcpHeader, and `DataPduHeader = LtePdcpHeader`.
  - Its `RlcPdusToRlcSdus<H>` ignores `H`.
  - A per-case `MC_CASE` probe selects cases.
- Every red failure is a class check:
  - `EntityHeader` / `is_same`;
  - the writer class from the packet metadata of the TX PDUs, the recovered SDUs and the PDUs sent again.
- No byte, SN, order, size or payload check is red at 4a0871d6. Ledger row 148 records why: at 12 bits the two headers are byte-identical.
- The forwarding cases go red through the PDCP entities' header class. The class that `LteRlcAm` decodes with cannot be observed at run time: the bytes are identical, and the decode is a `PeekHeader`, which the metadata does not check. That class is enforced by the type: the explicit instantiation, the callers naming `Mc*::DataPduHeader`, and the lint below.

None of the six pre-existing `LteRlcAm` defects tripped. The suite uses a fresh entity, one forwarding, and only `GetTransmittingRlcSduBuffer`.

## Other suites, at 4a0871d6 and at the change (host, same configuration)
- **Same result at both: PASS.**
  - The RLC suites: `pdcp-sn-wrap`, `lte-rlc-am-transmitter`, `lte-rlc-am-e2e`, `lte-rlc-um-transmitter`, `lte-rlc-um-e2e`, `lte-rlc-header`.
  - The handover and bearer suites: `lte-epc-e2e-data`, `lte-x2-handover-measures`, `lte-handover-delay`, `lte-handover-target`, `lte-rrc`, `lte-test-deactivate-bearer`, `lte-ipv6-routing-test`.
  - The EPC and mmWave suites: `epc-s1u-downlink`, `epc-s1u-uplink`, `mmwave-neighbour-list`, `mmwave-attachment-test`.
- **Same result at both: CRASH.** `lte-x2-handover` hits the same pre-existing `NS_ASSERT "UE manager for RNTI 1 not found"` in `lte-enb-rrc.cc` (line 3515 → 3518, shifted only by the added lines). This is not PDCP-related.
- **`lte-pdcp` does not exist** as a suite in this tree; no source in src/lte/test registers it.

## Byte identity (row 148 (b)), on the host
- **Runs.** Both builds used the same tree and configuration. 4a0871d6 was run twice (a1, a2); the change was run once. Each run was N4 free with the null sink, the same CLI as `gate-n4-ul-metric.sh --part identity` and paced-lib (2 gNBs, NoAuto, simTime 10, outage threshold −1000, simStartEpochMs from the rung config, RngRun 1, ulon `steps`). The script is saved as `n4-host-run.sh`.
- **a1 = a2 at 4a0871d6.** Both uloff and ulon compare equal (exit 0, 37 items): the host runs are deterministic.
- **uloff, 4a0871d6 vs change:** equal on all 37 items.
- **ulon, 4a0871d6 vs change:**
  - The only differing item is `ns3run/stdout.txt:audit-header`: `hdr=2` becomes `hdr=2 class=ns3::NrPdcpHeader`.
  - `compare --except-audit-header` is equal on 36 items.
  - Stdout has the same 123,796 lines.
- **`check-pdcp-volume-totals.py`.** The working-tree version, from the parallel harness work, gives `pass: true`, `hdr: 2`, `hdrClass: ns3::NrPdcpHeader` and a0–a5 all true on the change's ulon run.
- **Scope.** This proves host-to-host identity at 4a0871d6. The VM gate, measured against the banked `reference/n4-sn-wrap/` manifests, is still the judge of record. The host compiler differs from the VM's.

## Source-lint rule for "an MC path never names LtePdcpHeader"
Strip C/C++ comments and string literals first, then match `\bLtePdcpHeader\b` over `src/`, `scratch/` and `contrib/` (`*.h`, `*.cc`), excluding `src/*/bindings/` (dead pybindgen; the build uses `--disable-python`).

**Allowlist.** A match is allowed only in these files; anything else fails. Use an allowlist, not a deny-list, so that a new MC consumer in a new file is caught.
- `src/lte/model/lte-pdcp-header.{h,cc}` (the class).
- `src/lte/model/lte-pdcp.cc`, exactly 4 code lines:
  - `LtePdcp::CreateDataPduHeader` (`std::make_unique<LtePdcpHeader>()`);
  - `LtePdcp::DoTransmitPdcpSdu` (`LtePdcpHeader pdcpHeader;` and `LtePdcpHeader::DATA_PDU`);
  - `LtePdcp::DoReceivePdu` (`LtePdcpHeader pdcpHeader;`).

  These are the E-UTRA entity's own codec, behind `AssertEUtraEntity()`.
- `src/lte/test/lte-test-entities.cc` (`:584`, the RLC-test entity, an E-UTRA context).
- `src/lte/test/lte-test-mc-pdcp-nr-header.cc` (the SRB checks).
- `src/lte/helper/lte-helper.cc` `:1462` is only the string literal `"LtePdcpHeader"` in `LogComponentEnable`. It disappears once string literals are stripped; otherwise allowlist it.

**Count 0 required** in these files, which hold the MC paths and every consumer the Design names:
- `src/lte/model/mc-enb-pdcp.{h,cc}` and `mc-ue-pdcp.{h,cc}`;
- `lte-enb-rrc.{h,cc}` and `lte-ue-rrc.{h,cc}`;
- `lte-rlc-am.{h,cc}`;
- `lte-pdcp-sn-wrap.{h,cc}`;
- `src/mmwave/model/mmwave-enb-net-device.cc`;
- `scratch/scenario-zero.cc`;
- `src/lte/test/lte-test-pdcp-sn-wrap.cc`.

**Positive conjuncts (optional):**
- `using DataPduHeader = NrPdcpHeader;` is present in both `mc-enb-pdcp.h` and `mc-ue-pdcp.h`.
- `lte-rlc-am.cc` holds exactly one explicit instantiation, `template void LteRlcAm::RlcPdusToRlcSdus<NrPdcpHeader>`.
- Every `RlcPdusToRlcSdus<` call in `lte-enb-rrc.cc` and `lte-ue-rrc.cc` names `PdcpHeader`, which is aliased to `McEnbPdcp::DataPduHeader` / `McUePdcp::DataPduHeader` in that function.
- `mmwave-enb-net-device.cc` contains `McEnbPdcp::DataPduHeader().GetSerializedSize()`.

## Evidence (`plans/261103-0008-GH-1-post-m9-realism-m10/evidence/p10-p7/`, 140 KiB of text)
- `red-at-4a0871d6-shim/`: `red-tree-shim.diff`, `shim-sha256.txt`, `per-case.txt`, `failing-checks-sample.txt`.
- `green/`:
  - `mc-pdcp-nr-header-verbose.txt` (37 PASS);
  - `suites-at-base.txt`, `suites-at-green.txt`;
  - `tree-at-green.txt`: the base SHA, the tracked-diff sha256 `58ba5c44…` and the sha256 of each new file.
- `n4-host/`: six manifests (base a1, base a2, P7 × uloff/ulon), the `cmp-*.json` results, `audit-header-lines.txt`, `check-pdcp-volume-totals-p7-ulon.json`, the argv files and `n4-host-run.sh`.

## Build and housekeeping
- The tree was `/tmp/claude-1000/ns3-p7-910ba118` (tmpfs; no "scratch" in the path). It used `build-ns3.sh --tests` flags plus the scenario-zero target and uv Python 3.12. It has been removed.
- /home has 45 GiB free.
- No stray process.
- No commit, stash, push or VM access. `.claude/` in the fork is untouched.
- clang-format is clean on the new files.
- The only compiler warnings on the touched files are pre-existing (`Ptr` operator Tester*, unused variables).

## Deviations and notes
- **Every DRB in this fork is a DC entity.** `SetupDataRadioBearer` always creates `McEnbPdcp`, and the UE always creates `McUePdcp`. Plain `LtePdcp` exists only on SRB1 and in `LteSimpleHelper` tests.
  - So "LTE-only DRBs keep the E-UTRA header" has no DRB to apply to. A pure `LteHelper` DRB now carries the NR header class too.
  - No wire byte changes, and no gate runs a non-EN-DC UE.
  - Kongming: this is consistent with 37.340 §4.2.2 for EN-DC. It needs a "Row 148 notes" ledger note, not a ruling, unless non-EN-DC UEs come into scope.
- **The LtePdcp assertion is a tripwire, not a discriminator.**
  - Through virtual dispatch the base codec never runs on an MC object, so a header-class check there could never fire.
  - The `override` keywords turn a signature drift into a compile error.
  - The instance-TypeId abort catches an explicit `LtePdcp::Do*` call from a subclass.
  - The run-time discriminator is the suite's metadata check.
- **Unchanged on purpose:** `GetStatus` is still non-virtual (pre-existing defect 6), and the hard-coded `>3`, `>=3` and `20+8+12` size literals are untouched. They encode a size, which is unchanged, not a class.

## Unresolved questions
1. `plans/.gitignore:6` ignores `evidence/p10-p7/**`. It needs a `!/*/evidence/p10-p7/**` negation before the evidence is committed, as for p10-sn-wrap.
2. The "Row 148 notes" ledger line about every DRB being a DC entity is still to be written by the controller.
3. The harness lint and the `class=` parse belong to the parallel developer. The rule above is what they should encode.

Status: DONE
Summary: The EN-DC bearer now writes and reads `NrPdcpHeader` (38.323 V19.1.0 §6.2.2.2, 12-bit) at every consumer. The header class comes from the bearer's entity type, enforced at compile time, and the audit line is printed from the entity's own header object. The 37-case suite is green at the change; at 4a0871d6 only its class checks are red. The host N4 runs are byte-identical to 4a0871d6 except the audit header line.
Concerns: The byte identity was checked host-to-host; the VM identity gate is the judge of record. The class the RLC AM decodes with is enforced by type and lint only (no run-time discriminator), as row 148 anticipated.

## Codex finding fixed (pre-ship MEDIUM: the forwarding cases bypassed the production consumers)
The old cases 31–36 recovered SDUs from `LteRlcAm`, then stripped headers and re-injected them inside the test loop. They never ran `UeManager::ForwardRlcBuffers` or `LteUeRrc::CopyRlcBuffers`. The fix is the narrow refactor Codex suggested, plus new cases that call the production code. No kongming consult was needed: the route was given, and the one open question (defect 3, below) is a ruling, not a design fork.

### Refactor (behaviour unchanged)
- New `src/lte/model/lte-rlc-forwarding-buffer.{h,cc}` holds the per-bearer work both RRC methods duplicated:
  - `CollectRlcForwardingBuffer<H>(rlc, buffer, size)`, for RLC AM: unacked PDUs to SDUs in transmission order, then the transmitting SDUs, the RLC's last-started-SDU copy, the txon buffer and the lookback. For RLC UM and UM low-latency it copies txon.
  - `DeliverRlcForwardingBuffer<H>(buffer, size, removePdcpHeader, deliver)`: drops packets under 3 bytes and Control PDUs, removes packet tags, optionally strips the PDCP header, and hands each packet to `deliver` in order.
- The code moved over unchanged. The only differences:
  - The UE path now peeks the header before stripping it (the eNB path already did). For Data PDUs the result is the same.
  - The byte counters are only used in logs.
  - Two `NS_LOG_UNCOND` lines lost their "UE RRC: " prefix. Neither line appears in either N4 stdout, and the stdout bodies are byte-identical.
- `ForwardRlcBuffers` and `CopyRlcBuffers` now each run Collect and then Deliver with their bearer's `Mc*::DataPduHeader`. Each passes a lambda that keeps its own dispatch:
  - eNB: X2 `SendUeData` (strip), `ForwardRlcPdu` (keep the header, secondary-cell handover), or `mcPdcp` re-injection with `Bid2Lcid(bid)` (strip).
  - UE: re-injection into the bearer's `McUePdcp` with `lcid` (strip).
- Each RRC method drops about 200 duplicated lines. The unused `lte-pdcp-sn-wrap.h` include is gone from both.

### The header class is now a compile-time guard (this corrects my earlier report)
- Before, I reported that the RLC AM's header class was "enforced by the type: the explicit instantiation". That was wrong. With shared libraries, a call naming `LtePdcpHeader` compiled, linked, and stayed green. The first mutation round showed this (m7 green).
- New `IfNrPdcpHeader<H>` in `nr-pdcp-header.h` uses `enable_if` on `is_same<H, NrPdcpHeader>`. It is the return type of `LteRlcAm::RlcPdusToRlcSdus<H>`, `CollectRlcForwardingBuffer<H>` and `DeliverRlcForwardingBuffer<H>`.
- Mutations m7 (`CopyRlcBuffers` names `LtePdcpHeader`) and m9 (`RlcPdusToRlcSdus<LtePdcpHeader>` inside Collect) now fail to compile.

### Suite: 41 cases (was 37)
Cases 31–40 replace the old 31–36. Each one drives a real `McEnbPdcp` or `McUePdcp` over a real `LteRlcAm` through their SAPs, as before, and then calls the production `CollectRlcForwardingBuffer` and `DeliverRlcForwardingBuffer`. The `deliver` lambda mirrors the production one: `TransmitPdcpSdu` with the RNTI and LCID.

| Idx | Case | 4a0871d6 shim | Change |
|---|---|---|---|
| 31–33 | eNB X2 forwarding of SDUs: SNs 4094..1 sent, VT(A) 1022 / 1022 with NACK 1022, 1023 / 5; strip, then into a target McEnbPdcp at TX SN 4095 | FAIL (class checks only) | PASS |
| 34 | the same, SDUs still queued in the RLC (Collect's txon-only branch) | FAIL (class only) | PASS |
| 35, 36 | eNB RLC PDU forwarding (secondary-cell handover, header kept, original SN), sent / queued | FAIL (class only) | PASS |
| 37–39 | UE RLC switch, sent, the three VT(A) variants; strip, then back into the same McUePdcp at TX SN 2 | FAIL (class only) | PASS |
| 40 | UE RLC switch, queued | FAIL (class only) | PASS |

Each case checks:
- the forwarded buffer: count, order, octets (SN plus SDU), NR writer class, and that the RLC tags are still on as a precondition;
- each delivered packet: no PDCP header (metadata `<no header>`, or the NR header kept for 35–36), bytes, and no packet tags;
- the PDUs sent again: the new SNs (4095, 0, 1, 2, 3 on the eNB, wrapping again; 2..6 on the UE) and the NR class;
- the peer entity: it delivers the SDUs byte-equal in forwarded order, and its RX SN is the last SN + 1.

The 4a0871d6 red run:
- The shim adds a red-only `lte-rlc-forwarding-buffer.h`: the 4a0871d6 bodies of the two RRC methods, moved verbatim, with `LtePdcpHeader` hard-coded and `H` ignored.
- 21 of 41 cases are red, and every red check is a header-class check (`OuterHeaderClass` on the forwarded buffer, the PDUs sent again, or the delivered PDUs). Counts, order, bytes and SNs, including the repeated SDU described next, are green at 4a0871d6. So the red reason is the real E-UTRA class, not the shim.

### Pre-existing defect 3 shows up and is pinned (ruling needed)
- When the SDUs have been sent, the production Collect appends the RLC AM's `m_segmented_rlcsdu`. That is its copy of the last SDU it started, and it is never reset (defect 3 in phase-10 "Follow-up candidates outside M10"). So SDU 3 (SN 1) is forwarded a second time: 5 packets for 4 SDUs.
- The 4a0871d6 run shows the same 5 packets, so this is old behaviour.
- The sent cases assert it as today's behaviour, and the class comment says why. Mutation m6 (no copy appended, the fixed behaviour) turns them red. A later fix of defect 3 must therefore update the expectation.
- I did not fix the defect. Per the brief, a defect that blocks a required test becomes a ruling. Pinning it keeps step 2(b) provable on the production path now. The ruling options are in question 4 below.
- The queued cases (34, 36, 40) take the branch without this copy and deliver exactly the 4 SDUs.

### Mutation check
Each mutation was made on the host green tree, to one production file in the build tree only. Cases 31–40 ran one per process, and the file was then restored. Evidence is in `evidence/p10-p7/mutations/`.
- m1, skip `RemoveHeader`: red on 31–34 and 37–40.
- m2, strip with `LtePdcpHeader`: red on the same cases (the NR header item stays in the metadata).
- m3, keep packet tags: red on 31–40.
- m4, always strip: 35–36 abort (the peer reads payload as a Control PDU).
- m5, reverse the SDU order: red on every sent case.
- m6, drop the last-started-SDU copy: red on every sent case.
- m7 and m9, name `LtePdcpHeader`: compile error.
- m8, the eNB dispatch flag inverted in `ForwardRlcBuffers`: GREEN. That is the uncovered part, listed next.

### Still uncovered
- The per-method dispatch in the two RRC methods: the lambda bodies (X2 `SendUeData` / `ForwardRlcPdu` parameters, `mcPdcp` re-injection with `Bid2Lcid(bid)`), the keep-header flag, and the `DynamicCast<McEnbPdcp>` abort at the handover caller.
- There is no cheap production-method test. Both methods are private and need a `UeManager` or `LteUeRrc` with full bearer, X2 and RRC state. The public paths into them (handover, MC reconfiguration, RRC connection switch) need the whole stack.
- Also uncovered: Collect's RLC UM and UM low-latency branches (a txon copy). N4 runs RLC UM but never forwards.

### Test robustness
ns-3's default runner continues after a failed `NS_TEST_ASSERT`. The size asserts in the suite now return explicitly (8 sites). Before, a count mismatch indexed past the end, which m6 showed as a segfault.

### Re-verified on the host
The fresh tree was `/tmp/claude-1000/ns3-p7-fix-910ba118` (tmpfs). It has been removed; /home has 45 GiB free and no stray process is left.
- `mc-pdcp-nr-header` passes 41/41.
- The 17 neighbouring suites plus `pdcp-sn-wrap` give the same table as before. All pass except `lte-x2-handover`, which crashes as it does at the base ("UE manager for RNTI 1 not found", `lte-enb-rrc.cc:3329`).
- N4 against the base manifests:
  - uloff: equal on 37 items.
  - ulon: differs only in `ns3run/stdout.txt:audit-header`, and is equal on 36 items with `--except-audit-header`.
  - Against the earlier P7 manifests, both are equal on 37 items, so the refactor changed no N4 byte.
- `check-pdcp-volume-totals` gives the same JSON as before (pass, `hdrClass ns3::NrPdcpHeader`).
- clang-format is clean on the new and changed blocks. The only diffs it still reports in `lte-enb-rrc.cc` and `lte-rlc-am.cc` are pre-existing ones outside them.

### Files changed for the fix
- new: `src/lte/model/lte-rlc-forwarding-buffer.h` (86 lines) and `.cc` (224);
- `lte-enb-rrc.cc` and `lte-ue-rrc.cc` (the bodies moved out);
- `lte-rlc-am.h` and `.cc` (the `IfNrPdcpHeader` return type, and the `nr-pdcp-header.h` include in the header);
- `nr-pdcp-header.h` (`IfNrPdcpHeader`);
- `src/lte/CMakeLists.txt` (2 entries);
- `lte-test-mc-pdcp-nr-header.cc`.
- The tracked diff against 4a0871d6 is now 17 files, +272/−495, sha256 `ef94e1e3…` (`green/tree-at-green.txt`).
- The source-lint rule is unchanged: none of the new files name `LtePdcpHeader`.

### Evidence updated (`evidence/p10-p7/`)
- `red-at-4a0871d6-shim/`: `red-tree-shim.diff` (now with the forwarding shim, sha256 `897f2928…`), `shim-sha256.txt`, `per-case.txt` (41 cases), `failing-checks-sample.txt`, `per-case-mc.sh`.
- `green/`: `mc-pdcp-nr-header-verbose.txt` (41 PASS), `suites-at-green.txt`, `tree-at-green.txt`.
- `n4-host/`: `runs-p7fix-{uloff,ulon}.manifest.json`, `cmp-base-vs-p7fix-*.json`, `cmp-p7-vs-p7fix-*.json`, `check-pdcp-volume-totals-p7fix-ulon.json`.
- `mutations/`: m1–m9, `README.txt`, `mutate.sh`.

### Unresolved questions (in addition to 1–3 above)
4. Defect 3 ruling. Options:
   - (a) keep the pin, which is today's state;
   - (b) assert only the first four forwarded SDUs and leave the repeat unasserted;
   - (c) fix defect 3, which is outside M10 by the 2026-11-07 consensus.
5. Is the uncovered RRC dispatch (the lambda bodies, the keep-header flag, the handover caller's cast and abort) acceptable as uncovered? Covering it would need a `UeManager` / `LteUeRrc` test fixture or a friend test hook in production headers.

Status: DONE_WITH_CONCERNS
Summary: The forwarding cases now run the production per-bearer code that both `ForwardRlcBuffers` and `CopyRlcBuffers` call. Mutating that code turns them red (strip, class, tags, order, keep-header flag), and the header class is now a compile-time guard. N4 bytes are unchanged against both 4a0871d6 and the earlier P7 build.
Concerns: Defect 3 (the never-reset `m_segmented_rlcsdu`) shows up on the production path and is pinned pending a ruling. The RRC-method dispatch lambdas and the handover caller's cast remain uncovered (m8 green).

## Controller rulings (2026-11-07 09:35 KST)
- **Q1–Q3:** closed in 3dc3758d (the `plans/.gitignore` p10-p7 negation, the "Row 148 notes" continuation) and by the harness developer's lint and `class=` parse.
- **Q4: (a), keep the pin.** Defect 3 (`m_segmented_rlcsdu` never reset) is already a follow-up outside M10 (phase-10 "Follow-up candidates outside M10", item 3). The sent cases are characterization tests, and their comment names the defect. A later fix must change the expectation deliberately. Leaving the repeat unasserted (b) would let the defect's behaviour change unnoticed. A fix (c) would expand M10 scope.
- **Q5: accepted as uncovered at unit level.** The private RRC dispatch (lambda bodies, the keep-header flag, the handover caller's cast) runs in every N4 and M7 run. N4 byte identity against `reference/n4-sn-wrap/` (row 148 (b)) catches any dispatch change that alters bytes. A friend test hook in production headers is not justified for P7.

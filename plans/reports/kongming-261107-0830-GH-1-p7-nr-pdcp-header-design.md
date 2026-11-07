# Kongming counsel — P7 NR PDCP header design (2026-11-07 08:30)

Runtime: Opus 5.5 (per user CLAUDE.md), advisory only. ns-3 at 4a0871d6 (read-only); the in-flight P7 working tree (nr-pdcp-header.*, mc-*-pdcp.cc) was read but not judged.

## TL;DR / decisions

Your design is sound. Keep items 1, 2, 4, 5 and 6 as written. Item 7 should be the runtime version, using **one** virtual that returns `std::unique_ptr<Header>`. Item 3 needs to change: as written it can never fire. Make it `override` on the `Mc*` `Do*` methods plus a cheap tripwire, and put the real discrimination in the unit suite with `Packet::EnableChecking()`. On (e), add a ledger note; it does not need a ruling.

## (a) Template RlcPdusToRlcSdus: yes, it is the right shape

- It passes the header class from the caller's bearer context at compile time. With an explicit instantiation for `NrPdcpHeader` only, any call with `LtePdcpHeader` fails at link time, so the error shows up at build.
- An SN-decoder functor works too, but it is a runtime value that can be null and needs its own check, and it buys nothing over the template.
- Having the RLC learn the header at setup is the weakest option. RLCs are created in at least six places: eNB DRB, the gNB `m_rlcMap`, UE DRB, UE `m_rlcMap`, and the RLCs re-created at switches and handovers. If one of them forgets to set the header, the failure only appears during AM forwarding, and no gate runs that path.
- Keep the SN keying. Row 160's dedupe and ordering depend on it.

## (b) Audit: print at runtime from the entity, from one virtual

- The static form at `:727` only knows the type, not the wiring. If `SetupDataRadioBearer` regressed to `LtePdcp`, the line would still say `NrPdcpHeader`, so it does not meet row 148 (a).
- Use `virtual std::unique_ptr<Header> CreateDataPduHeader() const`. The base returns `LtePdcpHeader` and the `Mc*` classes return `DataPduHeader`. Class and size then come from one object that the entity built, so they cannot disagree. With separate TypeId and size virtuals, they could. It runs a handful of times per run.
- Byte identity is safe. The judge strips the first header line wherever it appears (`n4-run-byte-identity.py:103-108`). `check-pdcp-volume-totals.py` `load_audit` (`:47-56`) and `gate-n4-ul-metric.sh:129` don't depend on position either. The print stays inside the `enableUlTraffic` connect, so uloff still has zero lines (`:408`). It draws no RNG and schedules no event.
- Keep the `NS_ABORT` that fires if a later entity reports a different class or size.

## (c) The base assertion is a tautology

- The base `Do*` methods only run when the object's actual type has no override. Both `Mc*` classes override both methods. Every SAP path reaches the `Mc*` methods through virtual dispatch: the base ones (`lte-pdcp.cc:66`, `lte-pdcp-sap.h:126`) and the `Mc*` classes' own hidden ones. I checked all of these.
- So the assert can only fire if an override stops matching the base signature, or if an override explicitly calls `LtePdcp::Do*`.
- The guard that catches that is `override` on `McEnbPdcp`/`McUePdcp` `DoTransmitPdcpSdu`/`DoReceivePdu`. In C++17, signature drift then becomes a compile error.
- If the phase wording needs something "asserted", keep a tripwire. Use `NS_ABORT_MSG_UNLESS(GetInstanceTypeId() == LtePdcp::GetTypeId(), …)`, which avoids a heap allocation per PDU. Record it as a regression tripwire, not as a discriminator.
- The real discriminator is `Packet::EnableChecking()`, called first in `mc-pdcp-nr-header` before any packet is created. With it on, `RemoveHeader` with a different header TypeId is fatal (`src/network/model/packet-metadata.cc:694-698`). It is the only runtime check that tells the two byte-identical headers apart. It does not cover `PeekHeader`; for those, rely on the types and the lint.

## (d) Consumer list: what is missing

- **`ForwardRlcBuffers` parses the RLC buffer even when `pdcp` is null.** This happens for the `m_rlcMap` SN-side RLC at `:905` and `:2218`. The header class there comes from the call context ("only MC bearers' RLCs are forwarded"), not from the parameter. Use `McEnbPdcp::DataPduHeader` unconditionally and write in a comment that null means the MC RLC or RLC SM, never an unknown header.
- **Checked, no PDCP parse:** UM and UmLowLat RLC, `epc-x2.cc`, and `mc-ue-net-device.cc` (IP only). The UM branches of the two forwarding functions feed the same loop and the same local header variable. N4 exercises the eNB UM loop.
- **Leave unchanged:**
  - `lte-test-entities.cc:584`, the RLC-test `LteTestMac`, which runs in an E-UTRA context;
  - the log string at `lte-helper.cc:1462`;
  - the dead pybindgen files `src/mmwave/bindings/modulegen__*.py` (the build uses `--disable-python`);
  - the hard-coded sizes `>3`, `>=3` and `20+8+12`. They encode a size, not a class, and the size is still 2 octets.
- **Lint:**
  - Use an allowlist: `LtePdcpHeader` may appear only in `lte-pdcp-header.*`, `lte-pdcp.cc`, `lte-helper.cc`, `lte-test-entities.cc`, the new suite and `CMakeLists.txt`. That catches a new MC consumer in a new file, which a denylist would miss.
  - Strip comments before matching. The comment at `lte-pdcp-sn-wrap.h:28` names `LtePdcpHeader` and would trip a naive grep.
- **Name hiding:**
  - Changing the parameters to `Ptr<Mc*>` makes `pdcp->GetLtePdcpSapProvider()` bind to the `Mc*` SAP instead of the base one. Both reach the same `Do*`, so behaviour does not change.
  - Do **not** make `GetStatus` virtual in P7. `lte-enb-rrc.cc:854` reads the base SNs through `Ptr<LtePdcp>` and gets stale values. That is a pre-existing bug and needs its own row.
- **Unit-suite traps:**
  - `McUePdcp` RX drops a PDU of 3 bytes or less and an SDU of 40 bytes or less. Use SDUs larger than 40 bytes and a `PdcpSapUser` stub.
  - `McEnbPdcp` TX draws from `m_uniformRNG` on every PDU and needs an `m_rlcSapProvider` stub.
  - The in-flight `NrPdcpHeader::SetSequenceNumber` aborts at 4096 or above, where `LtePdcpHeader` masked the value. That is fine, because the `Mc*` counters wrap at 4095.

## (e) Add a ledger note; no ruling needed

- 37.340 §4.2.2 (Rel-19): "the network can configure either E-UTRA PDCP or NR PDCP for MN terminated MCG bearers … NR PDCP is always used for all other bearers."
- `McEnbPdcp` is MN-terminated and becomes a split bearer once switched, so NR PDCP is allowed, and required once split. scenario-zero installs only MC UEs (`:641`).
- "LTE-only bearers keep the E-UTRA header" could only apply to non-EN-DC UEs: pure `LteHelper` runs and the src/lte tests. Strictly, 36.323 applies to them. Leaving it means no wire change at 12 bits and no gate exposure.
- Add this as a note under "Row 148 notes": the clause has no bearer to apply to in this fork, and plain `LtePdcp` exists only on SRB1 and in `LteSimpleHelper`. Raise a ruling only if non-EN-DC UEs come into scope.

## Assumptions

- The gate builds use the `default` profile with asserts on (`build-ns3.sh:39-43`). High confidence.
- No non-MC UE runs in any gate. High confidence: scenario-zero only.

Sources: [37.340 §4.2.2 (iTecSpec)](https://itecspec.com/3gpp/37.340/s/4.2.2), [37.340 V15.7.0](https://www.3gpp.org/ftp/tsg_ran/wg2_rl2/Specifications/201909_final_specs_after_RAN_85/37340-f70.docx).

Unresolved questions: none blocking. Wording of the base tripwire in the ledger is the caller's call.

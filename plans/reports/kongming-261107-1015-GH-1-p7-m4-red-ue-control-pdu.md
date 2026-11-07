# Kongming counsel: P7 M4 red, "McUePdcp received a PDCP Control PDU" (2026-11-07 10:15 KST)

Runtime: Opus 5.5 (user CLAUDE.md routing), advisory only. Host experiments ran in tmpfs scratch clones under `/tmp/claude-1000/kongming-p7-red/` (built with `build-ns3.sh`'s flags, uv Python 3.12, host g++ 16.2.1). The VM, the main worktree and the ns-3 submodule were not touched. Nothing was committed, pushed or stashed.

## TL;DR

- **P7 changed no byte on this path.** The D/C=0 PDUs come from switch-epoch forwarding defects that predate P7. 4a0871d6 receives exactly the same PDUs: the probe lines are byte-identical in all three M4 configs (341, 342 and 17 lines). At 4a0871d6 they were parsed as data and then silently dropped at `McUeNetDevice` ("Unknown IP type"). P7's new abort is wrong for this model. It only made the PDUs visible.
- **Fix: one ns-3 commit.** Replace both new D/C aborts (`McUePdcp`, `McEnbPdcp`) with the TS 38.323 §5.10 discard: no RX state change, nothing delivered, the RxPDU trace left where it is. Drop the two `abort.h` includes that only those aborts used. Add 6 unit cases.
- **Proved on the host.**
  - P7 + fix is trace-identical to 4a0871d6 in M4 default 2 s, default 10 s and single-gNB 10 s (44, 48 and 31 files, stdout equal). The one exception is `DlE2RlcStatsLte.txt` columns 5–6, the uninitialised-value columns the N4 judge already excludes under contract C1.
  - N4 uloff and ulon equal the banked `reference/n4-sn-wrap/` manifests on all 36 items except the audit header.
- **Other P7 aborts.** Every other abort P7 added was checked and cannot fire in M4–M7 or N4. Only the two D/C aborts change.

## Q1. Root cause

### What reaches `McUePdcp` at +0.238999999 s (4-gNB default, node 10 = IMSI 3)

- **Reproduced.** The host build at 34b7f3cc aborts at the same time on the same node (`--simTime=2`).
- **Delivery path (gdb backtrace).** The PDU arrives on the UE's **LTE** leg: `LteUePhy::PhyPduReceived` → `LteUeMac::DoReceivePhyPdu` → `LteRlcUm::DoReceivePdu` (`lte-rlc-um.cc:574`) → `ReassembleSnInterval` (`:1181`) → `ReassembleAndDeliver` (`:860`) → `McUePdcp::DoReceivePdu` (`mc-ue-pdcp.cc:267`). RNTI 5, LCID 3.
- **What the PDUs are.** A non-aborting stderr probe in `DoReceivePdu` (size, first 6 octets, PdcpTag delay) found, in the 2 s run, **341 D/C=0 PDUs**. All are IMSI 3, all are 1322 B, all begin `3b 03 05 22 00 00`, and they arrive between 0.239 and 1.397 s in 12 ms bursts. Decoded:
  - `0x3b` is the first octet `GtpuHeader::Serialize` writes (version 1, PT 1, spare 1, S 1, PN 1).
  - `0x03` is `EpcX2Header::McForwardDownlinkData` (`epc-x2-header.h:111`).
  - `0x0522` = 1314 = 1310 + 12 − 8, the length `EpcX2::DoSendMcPdcpPdu` writes.
  - So each PDU is a **12-octet X2-U GTP-U header + a 2-octet PDCP header + the 1308-octet SDU**. The receiver reads the GTP-U octet as D/C, which gives 0.
- **Object-level trace of the first one.** I added packet-uid probes at 4a0871d6; uids survive `Copy()`.
  1. PDCP PDU uid 1778 goes to the LTE RLC at 0.147003345 s on `McEnbPdcp`'s LTE leg.
  2. At 0.227767868 s, IMSI 3's MC setup (the `MC_CONNECTION_RECONFIGURATION` branch, `lte-enb-rrc.cc:1464-1495`) calls `ForwardRlcBuffers(…, lte2mmw=1)`. That branch **does not reset the LTE RLC**.
  3. `LteRlcUmLowLat::GetTxBuffer` returns the vector of `Ptr<Packet>` by value and never clears `m_txBuffer` (`lte-rlc-um-lowlat.cc:479-482`). The forwarding never copies (`lte-rlc-forwarding-buffer.cc:167,194,198`). So the forwarded object is still queued in the LTE RLC.
  4. The object re-enters `McEnbPdcp`. The 50 % split (`m_perPckToLTE` default 0.5, `mc-enb-pdcp.cc:79`) sends it to X2. There `EpcX2::DoSendMcPdcpPdu` prepends the GTP-U header **in place** (`epc-x2.cc:1254-1255`).
  5. The LTE RLC then transmits the mutated object. The UE receives it at 0.238999999 s.
- **The other PDUs.**
  - 83 D/C=0 PDUs carry an eNB LTE-leg PdcpTag (stamps 0.147–0.2275 s, receipt 0.239–0.503 s). Each maps to an LTE-leg object that was later sent over X2. The only forwarding of IMSI 3's LTE RLC before their receipt is the 0.2278 s one. It forwarded 162 objects, all of them the LTE-leg objects themselves, and the split sent exactly 83 of them to X2.
  - The other 258 carry a gNB-2 X2-reception PdcpTag (`epc-x2.cc:648`) and the same GTP-U `0x03` signature. Their chain through the gNB was not traced [unverified; same class: a shared packet mutated by an X2 send while still queued in an RLC].
- **Default 10 s run.** It has 341 such PDUs at IMSI 2 and 3, plus one 2382 B PDU with D/C=1.

### What reaches it at +2.834 s (single gNB, 10 s, node 7 = IMSI 3)

- **8 D/C=0 PDUs** at IMSI 2 and 3, each 1071 B and all-zero at the start (ns-3's UDP payload is zero-filled). They arrive on the LTE leg after mmWave→LTE switches: SwitchToLte at 2.8239 s, receipt at 2.834 s.
- **9 PDUs of 1556–2512 B** with D/C=1, from the same anomaly.
- This is the recorded follow-up, not a new defect: phase-10 "Follow-up candidate outside M10", items 1 and 4 (UM tail re-submission, UE reassembly anomaly).
- "`--nMmWaveEnbNodes=1` passes" only because the M4 single run lasts 2 s. The 10 s single timing run is red too.

### Pre-existing: proof

- **Same PDUs.** The same probe at 4a0871d6 (same host, same flags) gives **byte-identical PROBE lines** to the probe at 34b7f3cc with the abort removed, in all three configs: 341, 342 and 17 lines.
- **What 4a0871d6 did with them.**
  - It stripped 2 octets as a "header".
  - It overwrote RX SN. That state is dead: nothing reads `Mc*Pdcp::m_rxSequenceNumber`, and `lte-enb-rrc.cc:853` reads the base `LtePdcp` through the non-virtual `GetStatus`.
  - It handed the rest (> 40 B) to `McUeNetDevice::Receive`. That rejects it as neither IPv4 nor IPv6 (version nibble 0 in `05 22…` and `00…`) and logs "Unknown IP type, packet dropped" (`mc-ue-net-device.cc:391-410`).
- **Conclusion.** The PDUs were lost silently before P7 and are lost the same way with the fix.
- **The P7 bytes.** The refactor (`lte-rlc-forwarding-buffer.cc`) keeps the old order of peek, tag strip, header strip and target per path. That matches the identical probe output.
- **The upstream authors already knew.** `LtePdcpHeader::Deserialize` carries the receive assert P7 re-introduced, commented out: "HACKED. ENABLE THIS TO DISTINGUISH DATA_PDU and CONTROL_PDU in lte-enb-rrc.cc, lossless HO" (`lte-pdcp-header.cc:121-123`). The forwarding code in this model has long let D/C=0 bytes reach a PDCP decoder.

### Why the host N4 runs missed it

- N4 runs 2 gNBs with `--handoverMode=NoAuto` and `--outageThreshold=-1000` (rung-config substitution 1). There is no switch and no handover.
- Both classes need a forwarding event with a non-empty RLC buffer. The implementer's P7 N4 runs, with the abort still in, finished, so none occurs there. The likely reason is that each UE's MC setup happens before any DL backlog builds up on the LTE leg [inferred].
- The implementer ran only N4 and the unit suites on the host. The configs that exercise forwarding are M4 default/timing, M6 (single gNB, −5 dB, 10 s) and M7 (default config). **M6 and M7 would have been red too.**

## Q2. The fix (one ns-3 commit on 34b7f3cc)

### Code

`src/lte/model/mc-ue-pdcp.cc`, in `DoReceivePdu`, replace lines 267–268:

```cpp
        if (pdcpHeader.GetDcBit() != DataPduHeader::DATA_PDU)
        {
            // A PDCP Control PDU (D/C 0, 3GPP TS 38.323 clause 6.3.7). The model configures none
            // of the functions that use one (clause 6.2.3: status report, ROHC, EHC or UDC
            // feedback, SN gap report), so for this entity it carries reserved or invalid values
            // and is discarded (clause 5.10): RX state unchanged, nothing delivered.
            NS_LOG_WARN("McUePdcp rnti " << m_rnti << " lcid " << +m_lcid
                                         << " discards a PDCP Control PDU of "
                                         << p->GetSize() + pdcpHeader.GetSerializedSize()
                                         << " bytes");
            return;
        }
```

- `src/lte/model/mc-enb-pdcp.cc` `DoReceivePdu`, lines 322–323: the same block, at one indent level less, with "McEnbPdcp".
- Remove `#include "ns3/abort.h"` from both files. P7 added it only for these two aborts, and no other `NS_ABORT` is left in them.
- The exact diff, with both includes removed, compiled, and the unit suite green, is `fix-final.diff` in the evidence bundle (path below). Run clang-format on it: its `<<` continuation alignment is hand-written.
- The integration runs below used an earlier scratch variant. It differs only in its comment text ("UM DRB") and still had the include, so its behaviour is identical.
- Commit message: something like `fix(lte): discard a received PDCP Control PDU on EN-DC bearers instead of aborting`. No plan IDs in the code or the message.

### Spec basis (Zotero: 38.323 V19.1.0 `YX67SVUE`, 36.323 V19.0.0 `A8LZE4CW`, read with pdftotext)

- **§6.3.7.** D/C 0 means Control PDU.
- **§6.3.8.** PDU types: 000 status report, 001 interspersed ROHC feedback, 010 EHC feedback, 011 UDC feedback, 100 PDCP SN gap report, 101–111 reserved.
- **None applies to these entities.**
  - §5.4.2 defines the receive action for a status report on AM DRBs only, and §5.4.1 sends one only when `statusReportRequired` is configured. The model never configures it, and scenario-zero's DRBs are UM.
  - §5.7.6.2 passes ROHC feedback to "the associated ROHC protocol", and none is configured. The same holds for EHC, UDC and SN gap reports.
- **§5.10.** "When a PDCP PDU that contains reserved or invalid values is received, the receiving PDCP entity shall: discard the received PDU." 36.323 §5.8 says the same. 37.340 §4.2.2 makes NR PDCP the governing spec for these bearers.
- **No clause lets a receiver treat a Control PDU as data.** So 4a0871d6's parse-as-data was also non-conformant. The discard fixes P7's own D/C decode; it does not fix a recorded defect.

### Counters, traces, bytes

- **RxPDU is unchanged.** It fires at `mc-ue-pdcp.cc:257` and `mc-enb-pdcp.cc:314`, before the D/C check. The PDU stays counted as received from the RLC, as at 4a0871d6.
- **No trace sees any change.** The discarded PDUs never got past `McUeNetDevice` at 4a0871d6. `NS_LOG_WARN` is silent unless `NS_LOG` is set, so stdout is untouched.
- **N4 is untouched.** N4 never builds a D/C=0 PDU, so the new branch never runs there.

### Host verification of the candidate (scratch tree = 34b7f3cc + the diff)

| Run | Result |
|---|---|
| M4 default `--simTime=2` | exit 0; vs 4a0871d6, 44/44 trace files identical except `DlE2RlcStatsLte.txt` cols 5–6; stdout identical |
| default `--simTime=10 --indicationPeriodicity=0.1` | exit 0; 48/48 identical, same exception; stdout identical |
| single `--simTime=10 --indicationPeriodicity=0.1 --nMmWaveEnbNodes=1 --e2lteEnabled=false` | exit 0; 31/31 identical; stdout identical |
| N4 uloff and ulon (`n4-host-run.sh`, then `n4-run-byte-identity.py compare --except-audit-header` against `reference/n4-sn-wrap/*-a1.manifest.json`) | equal, 36 items each; audit line `hdr=2 class=ns3::NrPdcpHeader`; `check-pdcp-volume-totals.py` exit 0 |
| default `--simTime=30 --indicationPeriodicity=0.1` (a longer M7-like horizon) | exit 0 over about 4.8k SwitchToMmWave, 391 SwitchToLte and 250 handover trace rows. No other abort fired |
| `mc-pdcp-nr-header` with the 6 new cases (test build, `build-ns3.sh --tests` flags) | at 34b7f3cc without the fix: aborts at the first new case (red). With the fix: `PASS mc-pdcp-nr-header`, all 47 cases (41 existing + 6 new), 0 FAIL. `pdcp-sn-wrap` and `mmwave-neighbour-list` still PASS |

- The `DlE2RlcStatsLte` columns 5–6 differ even between 4a0871d6 and P7 without the fix (RNTI/LCID garbage for a UE with no data rows). The N4 judge already excludes them (contract C1).
- The host base N4 manifests (`evidence/p10-p7/n4-host/runs-base-*.manifest.json`) also equal the banked VM reference, so host-versus-VM compiler differences do not show up here.

## Q3. Tests, gates, records

- **Unit.** Add `McPdcpControlPduRxTestCase<Pdcp>` to `lte-test-mc-pdcp-nr-header.cc`, before `SrbLtePdcpUnchangedTestCase`, and register it before the forwarding cases. The full text is `addtest.py` in the evidence bundle. Six cases: `McUePdcp` (DL) and `McEnbPdcp` (UL), each × PDU type {0, 1, 5}. Each case:
  1. receives a Data PDU at SN 2047;
  2. receives a 101-octet Control PDU (octet 1 = `type << 4`);
  3. expects RxPDU fired 2×, exactly 1 SDU delivered, and RX SN = 2048.
  - It is red at 34b7f3cc (abort).
  - It is red at 4a0871d6 by construction: 99 octets > 40, so a second SDU is delivered and RX SN is overwritten.
  - Run it at the shim if the record needs the red.
- **M4 gate: no script change.** `m4_ns3_pdcp_mc_nr_header_suites_pass` already runs the suite. The smoke, regress and timing runs are the integration guard that caught this.
- **Chain.** Re-pin the harness (pins.conf + submodule) and run M4, M5–M7 and the N4 identity on the fix commit.
  - Watch the new M6/M7 row-149 PDCP size check. It never executed at P7 because the runs aborted.
  - Row 149 judges the TX side (`McEnbPdcp` TxPDU = 1310 B), which this fix does not touch, so I expect it to behave as designed.
- **Ledger: record only, within the existing rows.**
  - Add a "Row 148 notes, continued" entry: P7 red #1 under the Failure Protocol; the M4 evidence `20261107T010358Z`; the root cause (pre-existing, identical at 4a0871d6); the 38.323 §5.10 receive rule; the 6 new cases, which extend row 148 (a)'s suite with its predicate unchanged.
  - In that note, supersede the line "RX aborts on D/C = 0 (the model sends Data PDUs only)" in `fullstack-developer-261107-0820-GH-1-p7-nr-pdcp-header.md`. Reports are stateful records, so do not edit the report itself.
- **Phase-10 follow-up: add one observation outside M10** (no row, no fix), next to the UM tail item:
  - At forwarding, RLC TX-buffer packets are shared, not copied. The UM low-latency buffer is not cleared, and the MC-setup branch does not reset the LTE RLC.
  - `EpcX2::DoSendMcPdcpPdu` adds its GTP-U header in place, so the LTE leg transmits X2-framed 1322 B PDUs: 341 per UE switch epoch in M4 default. These inflate LTE RLC TX and UE PDCP RX volumes.
  - The 79 objects re-split to LTE are queued twice.
  - Trigger: any realism claim on LTE-leg DL volume, RLC counters or switch-epoch throughput.

## Q4. Every new P7 abort or tripwire, with a verdict

| Site (34b7f3cc) | Can M4–M7 or N4 reach it? | Verdict |
|---|---|---|
| `mc-ue-pdcp.cc:267` D/C abort | **Yes**: M4 default/timing (class A), single 10 s and M6 (class B), M7 (default config) | Replace with the discard |
| `mc-enb-pdcp.cc:322` D/C abort | Not seen (no UL data in M4 configs). The same garbage classes are reachable on UL when UL traffic meets a switch or SN change (later R-rungs) | Replace with the discard (same clause, one commit) |
| `lte-pdcp.cc:183` `AssertEUtraEntity` (called at `:195`, `:228`) | No: the `Mc*` `override`s are always dispatched, and SRB1 is a plain `LtePdcp` | Keep |
| `lte-enb-rrc.cc:888` DRB PDCP not `McEnbPdcp` | No: every DRB PDCP is `McEnbPdcp` (`:499-500`), and an RLC SM DRB has a null PDCP, which the condition excludes. The default 10 s runs had secondary HOs and passed | Keep |
| `lte-enb-rrc.cc:930/932` asserts in `ForwardRlcBuffers` | No: both callers pass a non-null `McEnbPdcp` after `DynamicCast` checks (`:1473-1475`, `:1891-1893`) | Keep |
| `lte-ue-rrc.cc:1588` null `McUePdcp` | No: all three callers are inside `if (pdcp)` (`:1389-1390`, `:1754-1755`, `:2116-2117`) | Keep |
| `scenario-zero.cc:69`, `:79` audit header | UL on only. It inspects only `DataRadioBearerMap/*/LtePdcp`, which are all `McEnbPdcp`, so always `NrPdcpHeader`/2. N4 ulon passed | Keep |
| `nr-pdcp-header.cc:38`, `:45` (`SetDcBit` > 1, SN ≥ 4096) | No: callers pass `DATA_PDU`, and the TX SNs wrap at 4095. `SetStatus` has no production caller (`lte-enb-rrc.cc:1156` is commented out) | Keep |

## Work checklist

1. Make the ns-3 commit on 34b7f3cc (branch `dev/l-release-nist180` of the fork): `fix-final.diff` + `addtest.py`'s case, run through clang-format.
2. On the host: run `mc-pdcp-nr-header`, `pdcp-sn-wrap` and `mmwave-neighbour-list` (expect 47 cases, PASS). Run M4 default `--simTime=2` and the single and default `--simTime=10` runs (expect exit 0). Run N4 uloff and ulon against `reference/n4-sn-wrap/` (expect equal on 36 items).
3. In the harness, as one commit: the pins.conf and submodule bump, the ledger note (Row 148 notes, continued), and the phase-10 follow-up observation (class A).
4. Run the VM chain: M4, M5–M7, then the N4 identity.
5. If anything goes red, pause: that is the second red.

## Success metrics

- M4 is green, including smoke, agent-down, regress, timing (both configs) and `m4_ns3_pdcp_mc_nr_header_suites_pass` with 47 cases.
- M6 and M7 finish with ns-3 exit 0, and the row-149 PDCP size check passes.
- N4 identity is equal against the banked reference except the audit header, and the audit line reads `hdr=2 class=ns3::NrPdcpHeader`.

## What to avoid

- **Do not fix the forwarding aliasing** (copy on forward, clear the UM buffer, reset the LTE RLC in the MC-setup branch) or the UM tail defect in this commit. That is outside P7, it changes switch-epoch traces, and it needs its own row and ruling.
- **No stdout or stderr output in the discard branch** (`std::cout`, `NS_LOG_UNCOND`). N4 compares the stdout body, and gates parse stdout.
- **Do not move the RxPDU trace or add a counter or trace source.** The point is "no observable change versus 4a0871d6".
- **No flag, no "strict mode" and no kept abort** behind an option ("no legacy/compat modes").
- **Do not let N4 stand as P7's integration proof.** It has no switches. Keep M4 default/timing, M6 and M7 as the forwarding coverage.
- **Do not read "1 gNB passes" as "4-gNB-specific".** The single-gNB 10 s run aborts too.

## Alternatives considered

- **Remove the abort and parse as data** (exact 4a0871d6 behaviour). It treats a Control PDU as data and overwrites RX state, and it gains nothing observable. It is weaker than the discard on "fix to spec".
- **Keep the abort and fix the upstream defects first.** That is the right long-term order for realism, but it is out of P7 scope, would take two or more commits, and changes M6/M7 numbers. It would turn one guided fix into a scope change that needs a user ruling.

## Assumptions

- **No production path configures a PDCP Control PDU** (no status report, ROHC, EHC, UDC or SN gap report). High confidence: grep finds no `statusReportRequired`/ROHC machinery in the `Mc*` entities.
- **The 258 gNB-stamped class-A PDUs share the traced mechanism.** Medium confidence: the signature is identical, but the chain was not traced. It does not affect the fix: they are identical at 4a0871d6 and discarded the same way.
- **The VM matches these host runs.** Medium-high confidence: the host reproduces the VM abort time and node exactly, and the host base N4 manifests equal the VM reference.
- **M6/M7 row-149 checks pass on the fix commit.** Medium confidence: they judge TX sizes, which are unchanged, but they have never run green at P7.

## Evidence bundle (session scratchpad, ephemeral; copy it into `evidence/p10-p7/` if the record should keep it)

`/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/910ba118-28cd-4264-b831-5fa1b4929edd/scratchpad/kongming-p7-red-evidence/` holds:

- `fix-final.diff`;
- `addtest.py` (the test case);
- `probe.py`, `uidprobe*.py` (the probes);
- `gdb-backtrace-p7-regress2.txt`;
- `probes/` (P7 and 4a0871d6 PROBE lines per config, plus the uid trace for IMSI 3);
- `n4/` (the fix manifests and the comparisons against the reference);
- `tests/` (suite output with and without the fix).

The scratch build trees were removed.

## Unresolved questions

- Should class A (X2-framed PDUs on the LTE leg) be only a phase-10 follow-up observation (my default) or a ledger row now? This is the user's call at the next checkpoint. Nothing in P7 depends on it.

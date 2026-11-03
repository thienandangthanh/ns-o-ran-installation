# P10 (ME, T-C): P6, P7, P9 fixes and the UseIdealRrc probe

**Start state:** checkpoint-2 pins; `f7-rerun-green`. **Snapshot at exit:** none. The PDCP unit tests live under `ns-3-mmwave-oran/src/lte/test/` (new test file, registered in `src/lte/CMakeLists.txt`). **Precondition:** tag `m10-cp2` exists (no T-C code before it).

## Context
- **P6:** the gNB cell report sends a MAC-sourced DL volume as `QosFlow.PdcpPduVolumeDL_Filter` [V `oran-interface/helper/mmwave-indication-message-helper.cc:132`], mapped to `QosFlow.PdcpPduVolumeDL`, REAL, bytes/period [V `ns3_e2_agent/schema/metric-map.v1.json:33`]. UE-level rows `:68`, `:85` and the eNB row `:134` are related [V].
- **P7:** the EN-DC bearer's PDCP (`McEnbPdcp`, created at `ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:499-500`) writes an E-UTRA PDCP header [V `mc-enb-pdcp.cc:247-256`, `:313`; UE side `mc-ue-pdcp.cc:197-206`, `:258`].
- **P9:** `DRB.PdcpSduVolumeUL/DL` on a gNB cell counts the MN-hosted PDCP of the cell's UEs, with a single E-UTRA header size [V `src/mmwave/model/mmwave-enb-net-device.cc:653-689`; map rows `metric-map.v1.json:56-57`]. R3′'s predictor reads this counter.
- `UseIdealRrc` is hard-set true [V `scratch/scenario-zero.cc:483`].
- The metric-map lint exists [V `ns3_e2_agent/tests/lint-metric-map.py`].
- R8: each fix becomes the only behaviour at its own commit; no switch.

## Requirements (contract)
- **AC16 (fixes):** each of P6, P7, P9 lands at its own commit. The lint matches each measName's source, unit and type to its 3GPP TS 28.552 clause. The traces show an NR PDCP header on the EN-DC bearer (3GPP TS 37.340 §4.2.2). P9: R3′'s predictor reads the corrected counter; any predicate change is registered per AC18.
- **AC17:** a `UseIdealRrc=false` probe run comes first. If it completes with ≥ 1 applied PSCell change, `false` becomes the only setting before checkpoint 3. Otherwise S-R applies: `UseIdealRrc` stays `true`, and the "ideal RRC" row is listed with the probe evidence.

## Design
- **P6:** report the PDCP PDU volume at the PDCP layer, from the PDCP stats calculator (DL PDU bytes per cell), as `QosFlow.PdcpPduVolumeDL` with the 28.552 unit and type (Mbit, INTEGER or REAL per the clause [to cite]). The MAC volume either stops being sent or moves to a correctly named MAC measurement if 28.552 defines one [I]. The lint gets a `clause` column per row and checks source layer, unit and type.
- **P7:** an NR PDCP header per 3GPP TS 38.323 (`MSNDDXJH`). The SN width (12 or 18 bits) is pre-registered from the clause before code, with its rollover (window = 2^(SN−1)). A new `NrPdcpHeader` class is used on the EN-DC (MC) bearers; LTE-only bearers keep the E-UTRA header. **Every PDCP-header consumer is enumerated and moved to the bearer's header type** (Codex 1) [V]:
  - writers and parsers in `mc-enb-pdcp.cc:247,256,313` and `mc-ue-pdcp.cc:197,206,258`;
  - the UE-side forwarding paths that strip the header, `lte-ue-rrc.cc:1700,1759,1829`;
  - the eNB-side forwarding and handover buffers, `lte-enb-rrc.cc:1034,1091,1176`;
  - RLC AM recovery, which indexes by the decoded SN, `lte-rlc-am.cc:1801`;
  - the LTE PDCP, `lte-pdcp.cc:180,221`, unchanged for non-MC bearers but asserted to never see an MC PDU;
  - the P9 header-size subtraction, `mmwave-enb-net-device.cc:658`.

  A consumer that cannot tell the bearer type fails loudly; it never guesses.
- **P9:** credit `DRB.PdcpSduVolume*` (NRCellCU) only with PDCP SDU volume that the en-gNB's own CU handles. In EN-DC with an MN-terminated split bearer, the honest value for the en-gNB cell is the SDU volume routed via the SN [I: exact definition per 28.552 §5.1.2.1.1.1, read at the phase]. The header size comes from the NR header (P7). The predictor keeps its formula and reads the corrected counter (approved open point 2). Any predictor predicate change gets an AC18 row.
- **P15 (contract Amendment 3, Stop A ruling S3, `plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`):** the agent answers a KPM action with the format that action asked for. Today it sends cell Format 1 and UE Format 2 under the one admitted action, whatever the action definition says; kpimon asks Format 3 by ID, and E2SM-KPM v03.00 answers a Format 3 action with indication Format 2 only (Zotero `F82PYZVK`; cite the clause at the phase). The fix [I, sized by the P05 scoping read]: kpimon subscribes a Format 1 action per ns-3 cell next to the Format 3 action; the agent routes each report to its own action (Format 1 → Format 1, Format 3 → Format 2); p12's judge and its references are re-baselined, with an AC18 row. If the P05 read found the F7 limit, this item is record-only instead and this bullet is replaced by the record.
- **UseIdealRrc probe:** one R3′-config run with `false` (scenario-zero global, default unchanged until the probe passes).

## Files
- ns-3: `ns-3-mmwave-oran/src/lte/model/mc-enb-pdcp.cc`, `mc-enb-pdcp.h`, `mc-ue-pdcp.cc`, `mc-ue-pdcp.h`, `lte-ue-rrc.cc`, `lte-enb-rrc.cc`, `lte-rlc-am.cc`, `lte-pdcp.cc` (assertion only), new `src/lte/model/nr-pdcp-header.cc/.h`, `ns-3-mmwave-oran/src/lte/CMakeLists.txt`, `src/mmwave/model/mmwave-enb-net-device.cc`, `scratch/scenario-zero.cc` (`:483`).
- oran-interface: `oran-interface/helper/mmwave-indication-message-helper.cc` (`:43-56`, `:88`, `:132`).
- Agent: `ns3_e2_agent/schema/metric-map.v1.json`, `ns3_e2_agent/tests/lint-metric-map.py`; P15: the agent's subscription/action handling and `sample-forwarder.cpp` report routing [I: exact files from the P05 scoping read].
- kpimon (P15): `install_patch_files/xApps/kpimon-go/*` (a per-cell Format 1 action next to the Format 3 action).
- Harness (P15): `scripts/gates/p12-records-check.py`, `gate-p12-kpm-period.sh` (re-baselined, AC18 row).
- Harness: `scripts/gates/check-pdcp-volume-totals.py`, `scripts/gates/r3p-predictor.py` (only if the counter key changes), `tools/e2-evidence/trace-facts.py` (PDCP header check).

## Steps
1. P6 commit, lint, M6 Influx = IPC.
2. P7 commit. Checks:
   - (a) the decoded header bytes on MC-bearer PDUs equal the NR header (D/C bit, SN width) in a packet-level unit test;
   - (b) payload preservation: the SDU bytes delivered at the UE PDCP equal the SDU bytes sent, through X2 forwarding and through an SN change (UE and eNB forwarding paths);
   - (c) an SN rollover test: SN at its maximum, then wrap, with RLC AM recovery still indexing correctly;
   - (d) M6/M7.
3. P9 commit; the counter totals check (`check-pdcp-volume-totals.py`) is updated with an AC18 row; R3′ single run.
3b. P15 commit(s) (agent per-action routing, kpimon per-cell Format 1 action) on the fork branches; p12 judge change with its ledger row in the same commit; M6, p12, R3′ single run.
4. UseIdealRrc probe: one run at `false`. Pass → commit `false` as the only setting. Fail → S-R, with evidence recorded.
5. Phase exit (checkpoint 3 is P11).

## Validation
- `python3 ns3_e2_agent/tests/lint-metric-map.py` passes with a 28.552 clause per row.
- The PDCP checks (a)–(c) pass: header bytes on every MC PDU = NR header; payload byte-equal through forwarding and handover; rollover recovery correct.
- P9: `check-pdcp-volume-totals.py` green under the registered predicate.
- P15: every RIC INDICATION's format equals its action's requested format in the decoded capture (Format 1 action → Format 1, Format 3 action → Format 2); p12 green under the re-baselined judge; or the record-only entry with the P05 evidence.
- Probe verdict: `useIdealRrc: false`, `appliedPscellChanges ≥ 1`, run completed, or the S-R record.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| PDCP PDU / SDU volume definitions, units, NRCellCU scope | 3GPP TS 28.552 §5.1.2.1.1.1, §5.1.3.6.1.1 | `5SZUBP6M` [C] | to cite |
| KPM measurement naming and types | KPM v03.00 §7.9.1 | `F82PYZVK` | to cite |
| NR PDCP on the EN-DC bearer; header format, SN length | 3GPP TS 37.340 §4.2.2; 3GPP TS 38.323 §6.2.2 (data PDU formats), §7.1 (state variables, SN) | `E6VYJPXJ`, `MSNDDXJH` | to cite |
| Ideal vs real RRC signalling (model choice) | ns-3 model documentation (not a spec) | — | — |

## Risks
- The P6/P9 definitions may not map one to one onto ns-3's counters (Medium/Medium). Mitigation: read the clause first, then write the ledger row before code.
- `UseIdealRrc=false` may break EN-DC setup in ns-3-mmwave (Medium/Medium). S-R is the approved fallback.
- The NR header changes every PDCP size downstream, and the traces (Medium/Certain) are accounted in P11's diff report.

## Rollback
Re-pin the `m10-cp2` SHAs.

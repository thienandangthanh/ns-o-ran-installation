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
- **R-4 serving cell (Stop A′ ruling 1, 2026-11-05; `plans/reports/decisions-261105-2349-GH-1-m10-stop-a-prime-rulings.md`; plan R-4; ledger rows 137–142, registered before code):**
  - **kpimon node tag.** A new layered patch, `install_patch_files/xApps/kpimon-go/control/control.go.e2-node-tag.patch`, is listed after `control.go.ue-id-tag.patch` in `patches.manifest`.
    - It adds the tag `e2NodeId` = `params.Meid.RanName` to every UeMetrics point, for the eNB too.
    - The image's `patchset.sha256` label follows from the manifest.
    - Row 137 judges it.
  - **The TS xApp serving cell from Influx.** It is a change to `ts_xapp.cpp.style5_en_gnb_ueid.patch`, or a new patch after it in the TS `patches.manifest`, plus the unit test of row 139.
    - The order stays: prediction, then Influx, then the decision.
    - It sends one Flux query: the UE's UeMetrics points with exactly that `ueId` tag in the last 60 s, keeping `_time` and `e2NodeId` only.
    - The serving cell is the latest point's node, mapped to its single NR cell key in `cell_map`.
    - No control is sent, and the reason is logged, when: there is no point (row 125); the latest `_time` holds two or more nodes; the node has no NR cell key, or more than one; or the prediction lacks the serving cell.
    - The decision formula is unchanged, and the QP answer's order no longer matters.
    - It writes one log line per decision with the serving key and its `e2NodeId`, for diagnosis only. Row 142 judges on the wire.
    - No `ns3.*` field is part of the decision. Rows 128 and 138 judge this.
  - **Harness.**
    - `influx-vs-trace.py` (row 137), `ts-patches-selftest.sh` (row 138), `ts-influx-query-selftest.sh` and its fixture (row 140).
    - `r2-scenario.json` (row 141): steps 30 and 40 list the serving cell second.
    - The new check `<rung>_<label>_wire_control_node_holds_the_ue_in_ns3_context` in `ts-rung-lib.sh` (row 142).
  - **Docs.** Update the kpimon section of `docs/system-architecture-l-release.md` (fixed in P09) with the node tag, in the kpimon commit's docs follow-up.

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
3c. D-06b-1 (Stop A′ ruling 5): first row 81's amendment, then its own commit. It is not squashed into P15.
3d. R-4 serving cell (Stop A′ ruling 1), in two commits:
   - (i) the kpimon `e2NodeId` patch (Testbed), separate from the D-06b-1 commit, then a kpimon rebuild with M6, M7 and p12 (row 137);
   - (ii) the TS xApp change (Testbed): its unit test (row 139), lint (rows 138, 140), and the R2 single and R3′ single runs, with `r2-scenario.json`'s row 141 change and row 142's check landing in the same harness commit, before the Testbed pin moves.
   - After (i), update the kpimon section of `docs/system-architecture-l-release.md`, as its own docs commit.
4. UseIdealRrc probe: one run at `false`. Pass → commit `false` as the only setting. Fail → S-R, with evidence recorded.
5. Phase exit (checkpoint 3 is P11).

## Validation
- `python3 ns3_e2_agent/tests/lint-metric-map.py` passes with a 28.552 clause per row.
- The PDCP checks (a)–(c) pass: header bytes on every MC PDU = NR header; payload byte-equal through forwarding and handover; rollover recovery correct.
- P9: `check-pdcp-volume-totals.py` green under the registered predicate.
- P15: every RIC INDICATION's format equals its action's requested format in the decoded capture (Format 1 action → Format 1, Format 3 action → Format 2); p12 green under the re-baselined judge; or the record-only entry with the P05 evidence.
- Probe verdict: `useIdealRrc: false`, `appliedPscellChanges ≥ 1`, run completed, or the S-R record.
- R-4 serving cell: rows 137–142 green. Every UeMetrics point carries its reporting node's `e2NodeId`. The TS unit test passes. R2 is green with steps 30 and 40 reordered. Every R2 and R3′ RICcontrolRequest goes to the en-gNB that holds its UE in the ns-3 context (row 142).

## Stop A′ rulings that bind this phase (2026-11-05)
- **Before P10 starts:**
  - Re-read `df -BG /mnt/data` (ruling 8; 18 GiB at 23:52 KST on 2026-11-05).
  - Any VM image prune follows plan "Constraints" ruling 3: dangling only, above 75 % guest root, logged before and after, never during a gate.
- **Codex triage:** kongming-261105-1050's rule (ruling 7). No harness commit lands while a chain runs.
- **`ns3.imsi`** stays a vendor measurement (ruling 4). The AC16 lint classifies it under `ns3.*`.
- **Commit order for P11's bisection:** P6, P7, P9, P15, D-06b-1, the kpimon node tag, the TS serving cell, then UseIdealRrc. One fix per commit; no two of them share a commit.
- **Budget:** the TS xApp and kpimon rebuilds with their M6, M7, p12, R2 and R3′ regressions add about 1.5–2 h [I] to the 6.5–8 h above.

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

## Hand-offs from the P06b exit review (kongming-261104-1958)
- **D-06b-1, the MeNB UE X2AP ID before DC.** It is scheduled here, bundled with P15, which rebuilds the agent and kpimon anyway.
  - Today the eNB agent always includes the MeNB UE X2AP ID in eNB-UEID. E2SM v07.00 §6.2.2.6 makes it conditional on DC being established.
  - M7 shows the window: IMSIs 2 and 3 are on the eNB from seq 1, but enter an en-gNB context only at seq 6 and seq 3.
  - **Row first.** Row 81's eNB conjunct becomes "the MeNB UE X2AP ID is present iff the UE is in some en-gNB's ctx(g, s)". It is derived from the en-gNB context files, not from the eNB's own flag, with one negative each way.
  - **Code.**
    - ns-3 adds a DC flag to the eNB `ueContext`.
    - The agent omits the member when DC is not set up.
    - kpimon's tag formatter handles the absent member: `enbUeId:<s1ap>` without `@<x2ap>`.
    - The n6 and Influx form checks follow.
  - Stop A′ reports P4-KPM as fixed with this one scheduled residual. The user may move the fix before cp2, into P07.
- **AC16 lint.** Classify the `ns3.*` vendor measNames, for example `ns3.imsi`, which is kept under the interpretation of R-4 recorded in phase 06b.

## Hand-offs from the P08 exit review (kongming-261105-1606)
- **One fix per commit:** P6, P7, P9, P15, D-06b-1 and UseIdealRrc. P11's bisection depends on it. D-06b-1 gets row 81's amendment first and its own commit; it is not squashed into P15.
- **Expected movements:**
  - P9 is the fix most likely to move R3′'s predictor answers, and possibly its decision. A run without a predictor-driven handover is red, and a scenario change is PAUSE T3.
  - P15's per-cell Format 1 actions will probably change kpm-headers and collet-start-time. Expect both in the cp3 diff.
  - The UseIdealRrc=false probe may fail. S-R is pre-approved for that case.
- **Before P10 starts:** the Stop A′ rulings on the VM prune rule and on /mnt/data headroom. P10 rebuilds ns-3, the agent and kpimon, and row 131's 85 % guest-root guard could stop a build mid-phase.
- **Budget (unit costs from the cp2 chain):** about 6.5–8 h of wall time and about 46 GiB of /home from one revert. That is the prefix (8,602 s, 22 GiB), an M4 rebuild per fix (1,281 s, 3 GiB) with the M6 and M7 regression, and for P15 with D-06b-1 an M5, M3 (2,181 s, 12 GiB), M6, M7, p12 and R3′ single.

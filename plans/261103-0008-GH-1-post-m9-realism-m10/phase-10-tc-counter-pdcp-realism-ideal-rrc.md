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
    - The serving cell is the latest point's node, mapped to the one key of that node in `cell_map` that the prediction also names (the node's `…00` Global-ID key is never named).
    - No control is sent, and the reason is logged, when: there is no point (row 125); the latest `_time` holds two or more nodes; no key of that node in `cell_map` is named by the prediction, or more than one is.
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
0. D-R3-1 (Stop A′ follow-up ruling, 2026-11-06; `plans/reports/kongming-261106-0008-GH-1-nr-arfcn-deviation-d-r3-1.md`; ledger rows 143–144), before P6:
   - **Testbed commit.**
     - In `ns3_e2_agent/src/e2-node-identity.hpp`, constexpr `kNrFref = 633334`, `kNrPointA = 632758` and `kNrSsbArfcn = 633312`, with `static_assert`s: the reference is on the raster (even offset from 620000, ≤ 653332); the SSB lies inside the carrier (SSB − 240 ≥ Point A, SSB + 238 ≤ Point A + 287·4); 7711 ≤ GSCN ≤ 8051. The wrong `:30` comment is rewritten.
     - In `e2-node-identity.cpp`, `:59` uses Point A and `:98` uses the SSB ARFCN.
     - The `codec-probe-e2ap.cpp:59-68` fixtures and the `SOURCES.txt:25` prose are regenerated in the asn1-indep image.
   - **Harness commit (the pin bump moves with it).**
     - The e2i predicate and self-test (row 143).
     - The AC6a probe sends the agent's cell, with scs60/nrb24, 632758 and 633312.
     - The `replay-ts-cell-map.py` `FIXTURE_HEX` (row 144).
   - **Gates at the commit:** the agent image build (codec byte equality), `lint.sh` with `e2i-wire-checks.py --self-test`, and a live `gate-e2i-interop.sh`. M5–M7, r0 and s10 are covered by P11's cp3 chain and its rehearsals.
   - **Then** mark the phase-06 D-R3-1 row as fixed at both SHAs.
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
- **Commit order for P11's bisection:** D-R3-1 first (one Testbed commit and one harness commit, which move together; rows 143–144; follow-up ruling 2026-11-06), then P6, P7, P9, P15, D-06b-1, the kpimon node tag, the TS serving cell, then UseIdealRrc. One fix per commit; no two of them share a commit.
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
- **One fix per commit:** D-R3-1 (first; added at the Stop A′ follow-up, 2026-11-06), P6, P7, P9, P15, D-06b-1, the kpimon node tag, the TS serving cell and UseIdealRrc. P11's bisection depends on it. D-06b-1 gets row 81's amendment first and its own commit; it is not squashed into P15.
- **Expected movements:**
  - P9 is the fix most likely to move R3′'s predictor answers, and possibly its decision. A run without a predictor-driven handover is red, and a scenario change is PAUSE T3.
  - P15's per-cell Format 1 actions will probably change kpm-headers and collet-start-time. Expect both in the cp3 diff.
  - The UseIdealRrc=false probe may fail. S-R is pre-approved for that case.
- **Before P10 starts:** the Stop A′ rulings on the VM prune rule and on /mnt/data headroom. P10 rebuilds ns-3, the agent and kpimon, and row 131's 85 % guest-root guard could stop a build mid-phase.
- **Budget (unit costs from the cp2 chain):** about 6.5–8 h of wall time and about 46 GiB of /home from one revert. That is the prefix (8,602 s, 22 GiB), an M4 rebuild per fix (1,281 s, 3 GiB) with the M6 and M7 regression, and for P15 with D-06b-1 an M5, M3 (2,181 s, 12 GiB), M6, M7, p12 and R3′ single.

## Hand-offs from the P09 exit review (kongming-261106-0414 §7)
- **Disk:** two revert cycles to `f7-rerun-green`, the first before D-R3-1 and the second between P15 and D-06b-1. Never start a p12 run or an xApp or kpimon build below 34 GiB of free /home; revert first. Remove each frozen checkout once its step's evidence is committed. The wall estimate is about 11–13 h. /mnt/data has 18 GiB free, floor 5.
- **Gates per commit:** report §7.2. At D-R3-1, also run M5–M7: the plan's invariant requires them after every agent change (`plan.md:71`), and it overrides step 0's "covered by cp3".
- **Ordering hazards:**
  - Each pin bump lands in the same harness commit as the predicate change it needs; rows 143 and 141 fail at the old pins.
  - The kpimon patch stack: P15, D-06b-1 and the node tag all touch `control.go`. The node-tag patch comes last in `patches.manifest`, and later patches are regenerated whenever an earlier one changes.
  - P15 replaces row 100's "one action, ID 1, Format 3" predicate at 8 sites: m6, m7, r0, r1, p12 a and c, e2i, and `ts-rung-lib.sh:85`, which covers r2, r3p and s10.
  - UseIdealRrc=false may move I-2's c. Register how c is judged at cp3 before that commit, and measure the 10-gNB wall rate after it, so that any simTime T3 is ruled before P11.
  - D-R3-1's new X2 bytes: run the cell-map replay for gNB IDs 2–11 at the new constants.
- **Register before code:**
  - the revert plan;
  - the P15 rows, in a docs commit ahead of the code (not in the same commit as the p12 row);
  - the P6, P7 and P9 rows, plus P7's SN width;
  - how c is judged under UseIdealRrc;
  - the M5–M7 run at D-R3-1;
  - an additive amendment to row 139: a hex-letter node case built from s10's `e2mgr-node-10.json`, so the TS cell-map path is tested on a key ≥ 10.
- **User question due before P6:** fix the ns-3 neighbour-loop UB (phase-09, finding) under contract Amendment 4, or disclose it only? The default is disclose-only.

## On resuming the goal: first housekeeping step (user, 2026-11-06 20:05 KST)
- Two locked frozen-checkout worktrees are left from the chains, 2.2 GiB each in /home:
  - `~/.cache/ns-o-ran-frozen-harness/510ae30811f842a7fec1a32cf7d8b09c531331a0` (P09 s10 gate of record);
  - `~/.cache/ns-o-ran-frozen-harness/a7943bfb66b54bc58beb12f24d4f189de59c87a2` (the D-R3-1 chain, red at M7).
- At resume, check whether each is still needed. A checkout is needed only while its chain's evidence is not yet committed and archived (tsv, step logs, as-run driver, `evidence-sha256.txt`, raw archive on /mnt/data), or while a diagnosis must re-run something at exactly that SHA. The M7 diagnosis may need a7943bf; the same SHA can be re-created with `git worktree add --detach --lock` from git, so the checkout itself is never the only copy.
- If one is not needed, remove it with `git worktree unlock <path>` then `git worktree remove <path>` (the frozen tree is `chmod -R a-w`, so restore write permission on that one path first), never `rm -rf`. Log the freed space in this phase.

## D-R3-1 chain attempt 1: red at M7, and the guided step (2026-11-06)
Counsel: `plans/reports/kongming-261106-2200-GH-1-p10-d-r3-1-chain-m7-red-counsel.md`. Evidence: `evidence/m7/20261105T211444Z/` with `m7-diagnosis/` (kubelet logs of rtmgr, e2mgr and the new e2term pod, 21:25–21:46Z) and `m7-diagnosis/recapture-20261106/` (read-only re-capture at 13:02Z: e2term `/opt/e2/`, seed table, RMR env and sockets; the e2mgr stash as the control; rtmgr sockets and logs; Services, endpoints, kube-proxy mode and IPVS). Driver record: `evidence/p10-chain/a7943bf/`.
- **Red checks.** At harness a7943bf (Testbed 163ef25), M2–M6 passed and M7 failed its 4 post-delete recovery checks; the e2term pod was deleted at 21:30:52Z.
- **Root cause [V].**
  - The replacement e2term (`…-cz7j8`) never received a route table. It has no `router.txt.stash`, only the empty `.stash.inc` written at RMR start-up. e2mgr's stash is rewritten on every rtmgr push, so the stash is valid receiver-side evidence.
  - It ran on the seed `router.txt` alone. The seed routes 1080 and 1100 (so E2_TERM_INIT and lost-connection reached e2mgr) but neither 12001 nor 1102. Every E2 Setup Request therefore failed with `RMR_ERR_NOENDPT` and the keep-alive response could not be sent. e2mgr removed the E2T instance at 21:40:44 (E2TKeepAliveExpired).
  - The e2term has no session on :4561, and IPVS shows 0 active connections to 10.244.0.161:4561. rtmgr has push sessions to every other endpoint but none to the e2term Service, and every push to it fails with EPIPE (`tp=32`). rtmgr never reopens it (`bringup.sh:207-208`).
  - This is a variant of the FU4 hazard class: no session at all, rather than a stuck reader.
- **D-R3-1 excluded [V].** The M7 code path is byte-identical from 673fe7b to a7943bf, the Testbed change touches only the agent's identity constants, codec probe, `SOURCES.txt` and `x2ap-codec.h`, and the failure is in e2term's message-type routing before e2mgr parses any payload. The pre-delete setups at the same SHA succeeded on all 5 nodes.
- **Classification.** L-release route distribution to a replaced pod. It is payload-independent and outside M10's scope (contract §3). It happened in 1 of 20 M7 runs on record. In green runs rtmgr reaches the new pod 20–100 s after the first setup; why it does then is out of scope.
- **Guided step (the one guided step of this goal's budget).** Revert `f7-rerun-green`, then re-run the full chain M2→e2i (steps 0–8) at the unchanged frozen a7943bf, with a fresh log directory (the driver now requires `P10_CHAIN_LOG_DIR`). M7 needs the state built by M2–M6 and no snapshot exists at M6, so the full chain is the minimum. No harness or check change; no ledger row (no predicate changed; M7 is unchanged).
- **Outcome rules, set before the run.** Any red step gets a kongming note, then PAUSE T6: the budget is spent. A green chain marks D-R3-1 fixed at both SHAs and continues with resume step 3.
- **T5 considered.** T5 ("an L-release failure") was not invoked. The precedent is M9 attempt 3, a known L-release route hazard handled by the Failure Protocol first (F″), with T5 only if the remedy failed. The user may read T5 differently; this is recorded for the next human checkpoint.
- **Budget.** About 2.5 h and 24–26 GiB of /home. This is an extra revert cycle on top of the four revert points below. The 510ae30 frozen checkout was removed at 22:10 KST under the 20:05 ruling (/home 52 → 54 GiB). The leaked overlay of attempt 1 is deleted after the revert under the 2026-10-28 ruling, with its five checks logged.
- **Not chased (record only).** Five sessions into rtmgr :4560 each hold 111,136 B unread by their peers. There is no green-run baseline.
- **For the user (non-blocking).** How to treat future M7 reds with this signature: (i) status quo, each a normal Failure Protocol red (the default); (ii) an additive receiver-side record in M7 (e2term stash, e2term :4561 sessions, rtmgr sessions to the e2term Service, NOENDPT 12001 lines) and one re-run outside the budget for a matching red, two in a row = PAUSE (kongming's recommendation; its own ledger row, after this chain); (iii) a remedy inside M7 (weakens the check; advised against); (iv) fix rtmgr reconnect (scope change). The same question goes on the Stop B list for M10.

## D-R3-1 chain attempt 2: red at e2i, PAUSE T6 (2026-11-07)
- **Run.** Revert `f7-rerun-green` at 13:09Z (libvirt's revert unlinked attempt 1's overlay itself; /home 54 → 76 GiB), then `p10-gate-chain.sh a7943bf… 0 8` from the frozen checkout, 13:09–15:15Z. Driver record: `evidence/p10-chain/a7943bf/attempt-2/` (tsv, step logs, as-run driver). Raw archive `…-m10-p10b-20261107.tar.zst` on /mnt/data (1,462 files, SHA256SUMS verified).
- **Green steps:** M2 `m2/20261106T130927Z`, M3 `m3/20261106T133007Z`, M4 `m4/20261106T140610Z`, M5 `m5/20261106T142843Z`, M6 `m6/20261106T143252Z`, **M7 `m7/20261106T143502Z` (green this time)**, I0 `i0/20261106T150015Z`, I2 `i2/20261106T150454Z`.
- **Red step:** e2i `e2i/20261106T150933Z`, exit 1. The first failing check, `e2i_asn1_indep_image_checksum_verified_and_loaded`, fails with `cd: /home/uc/asn1-indep: No such file or directory`. Every later e2i check fails on inputs that this missing image would have produced. `gate-e2i-interop.sh:3` says the host copies the tarball in. The P08 procedure re-copied it after every revert (kongming-261105-1050 step 6; phase-08 records the copy). That step was missing from attempt 2's checklist and launch. The host tarball `tools/asn1-indep/dist/asn1-indep-09aeabb8b0f99b0c.tar` is present.
- **Rule applied.** The outcome rule was set before the run: any red step gets a kongming note, then PAUSE T6. The red is not reclassified, even though its cause is a launch omission and not D-R3-1. Kongming note: `plans/reports/kongming-261107-0020-GH-1-p10-d-r3-1-chain-attempt-2-e2i-red.md`.
- **D-R3-1 is unverified, not failed.** Row 143's predicate (`x2apRequestPartDecodes`) never ran. Two facts point the right way but are not the gate's judgement:
  - At a7943bf, the e2mgr X2 request parts carry 632758 at bit 418 (the NRARFCN position) and 633312 at bit 509 (inside the MTC), and 633333 is absent. P08's dd27868 records, the control, carry 633333 at both positions.
  - M5's agent build logs "X2 components … byte-equal to pycrate" (`install-agent-image.log:3704,3715`).

  The phase-06 D-R3-1 row stays open.
- **The M7 hazard did not recur.** The replacement e2term pod was Ready after 151.8 s, at the top of the range seen in 12 runs (127–152 s). Setup request to response took 84 s for the eNB and 21–22 s for the gNBs, inside the ranges of the green runs. The no-route-table signature now stands at 1 in 21 runs. e2i's own RIC checks also passed: RIC reset, injector route table, the CONNECTED set, e2mgr records, and setup requests and responses 3/3 on the wire.
- **Where the omission came from.**
  - P08 re-copied the tarball after every revert (`kongming-261105-1050:154`, `phase-08:116`).
  - P09's chain had no e2i step (`p09-gate-chain.sh:56-70`).
  - The copy was never written into the driver or the resume card. The 2200 counsel's checklist dropped it, and the attempt-1 record inherited that.
  - It was latent in attempt 1 too, which stopped at M7 before e2i.
- **Cost:** 2 h 06 min of wall time; /home 76 → 51 GiB, of which M3 took 18 GiB.
- **Recorded, no change now.** `e2i_schedule_written` and `e2i_lockstep_run_with_five_injected_controls` passed with zero controls. The setup judge needs `injected.jsonl`, so a failed control encoding hides every setup check. This is no path to a false green: the encoding check itself is red.
- **State at the PAUSE.** The VM is running and not reverted, on overlay `ubuntu24.1793970545`; e2i finished its own teardown. The frozen checkout a7943bf stays locked.
- **User options (kongming's table):**
  - (a), recommended: copy and verify the tarball, then run only step 8 (`p10-gate-chain.sh a7943bf… 8 8`, the unchanged driver, a fresh log dir) on the current VM. About 15 min and 0–0.5 GiB; no M7 exposure. The current state is a valid start for e2i, because e2i resets what it relies on (precedent: P06 e2i runs 3→4).
  - (b): revert, copy, then the full chain 0–8. About 2 h 15 min, a 25 GiB peak, and M7's hazard.
  - (c): defer e2i to P11's cp3 chain (advised against).
- **Outcome rule if (a) is ruled.** Read-only pre-checks first: overlay, no gate unit, no agent or ns-3, no injector, TS 1/1 Ready, RIC pods Running. Then the copy, with `sha256sum -c` on the host and on the VM.
  - **Green:** exit 0, the run-dir cross-check passes, and the image Id equals P08's. D-R3-1 is then fixed at both SHAs, citing `e2i-setup.json`.
  - **Any red:** a kongming note and PAUSE again.
- **Prevention, after (a) and before the next e2i or AC6a chain.** A driver pre-flight copies and checks `asn1-indep-$TAG.tar` (host and VM `sha256sum -c`) before the first step whenever the range holds an `--image-tag` step, and fails with exit 2 before M2. It adds no check and changes no verdict, so it needs no ledger row. Shellcheck it, test two offline failure cases and dry-run the pre-flight alone. P12's M10 runner needs the same step (`phase-13:24`).

## D-R3-1 verified: user-authorized e2i resume (2026-11-07)
- **Ruling.** At PAUSE T6 the user chose option (a): `plans/reports/decisions-261107-0045-GH-1-p10-pause-t6-rulings.md`. The same file records three more rulings: M7 policy (ii), the Failure Protocol reading for known L-release hazards, and the P6 recommended set.
- **Pre-checks (read-only, 17:1xZ), all passing:**
  - the VM is on overlay `ubuntu24.1793970545`;
  - no gate unit, agent container or ns-3 process is running;
  - no injector pod is running, and TS and the other xApps are Running;
  - every RIC platform pod is Running, and the E2T list is not empty.
- **Copy.** `sha256sum -c` passed on the host, then the tarball was copied by scp, then `sha256sum -c` passed in the VM (`evidence/p10-chain/a7943bf/e2i-resume/preflight-asn1-indep.txt`).
- **Run.** `p10-gate-chain.sh a7943bf… 8 8` used the as-run driver of attempt 2 (sha256 `dc1712c8…`, identical) with a fresh log dir, 17:19–17:25Z.
- **Result:** e2i `evidence/e2i/20261106T171917Z`, verdict PASS with no failed check.
  - The image Id is `sha256:d6bd0587…`, equal to P08's.
  - Row 143's `x2apRequestPartDecodes` passes on every node, and so do `globalIds` and `ranFunctions`.
  - `e2i-setup.json` decodes 632758 and 633312, and 633333 is absent.
  - Raw archive `…-m10-p10c-20261107.tar.zst`.
- **D-R3-1 is FIXED** at Testbed 163ef252 / harness a7943bf (phase-06 row updated). Step 0's "Then" is done.
- **Next:**
  1. the driver pre-flight for the asn1-indep copy (no ledger row);
  2. the M7 signature record under ruling (ii), with its own additive ledger row, before the UB fix so the UB fix's M7 run carries it;
  3. the docs commit for the P6 rulings (row 147 amendment, the 0525 amendment line, row 151 revised for Q5);
  4. then the code commits in order, UB fix first.
- **Done (1): the driver pre-flight** (`evidence/p10-chain/p10-gate-chain.sh`). Before the first step, when the range holds an `--image-tag` step, it checks the host tarball and its SHA256SUMS entry, copies the tarball into the VM when the VM copy is missing or fails its check, and checks it in the VM. On failure it exits 2 before any step and before any tsv line, and it writes `preflight-asn1-indep.txt`. `P10_PREFLIGHT_ONLY=1` runs the pre-flight alone, and `ASN1_INDEP_DIR` overrides the source dir for tests. It adds no check and changes no verdict, so it has no ledger row.
  - Tests on 2026-11-07, all as expected:
    - shellcheck is clean apart from SC2034 on unused variables;
    - a wrong tag exits 2;
    - a missing tarball exits 2;
    - a range without e2i skips the pre-flight;
    - a dry run against the VM finds the copy present and checked;
    - with the VM's `~/asn1-indep` removed, the copy path copies it and the check passes.
  - The a7943bf frozen checkout was removed after D-R3-1's evidence was committed and archived (/home 51 → 53 GiB).

## Neighbour-loop UB fix: one red, one guided fix, chain green (2026-11-07)
- **Commits.**
  - ns-3 74c165f1 on the fork branch `dev/l-release-nist180`: `SelectNeighbourCells` is used by `mmwave-enb-net-device.cc`, and `mmwave-neighbour-list` has 17 QUICK cases.
  - Codex found that a NaN SINR broke the sort's strict weak ordering. The fix makes only readings `>= 0` eligible, and the follow-up review approved it.
  - Harness cf325954: the pin bump, M4's suite check (ANSI-safe `[n/m] PASS:` match), the r2/r3p tick check (row 159), and driver steps 9–11 with `P10_SKIP_STEPS`.
- **Red at cf325954, step 2 M4** (`evidence/m4/20261106T173845Z`): "Target to build does not exist: test-runner". Every M4 check that existed before passed.
  - Cause (kongming-261107-0305): ns-3.38 drops `src/test` when only `mmwave,oran-interface` are enabled, so the test tree had no test-runner. My first `cmake --build` idea was wrong and was never committed.
- **Guided fix 302d310c** (the one fix the Failure Protocol allows). `build-ns3.sh --tests` adds the `test` module and `--filter-module-examples-and-tests=mmwave`. The plain build's flags are unchanged.
- **VM probe before the re-run**, with its rule fixed in advance: a mechanics failure means re-probe, and any failure in the ns-3 tree means PAUSE T6.
  - The probe was green: the test tree took 200 s at 74c165f1, with `[1/1] PASS: TestSuite mmwave-neighbour-list` (`evidence/p10-chain/302d310c-ub/preflight/`).
- **Re-run:** `P10_SKIP_STEPS=8 p10-gate-chain.sh 302d310c… 2 11` from a frozen checkout, 18:26–20:21Z, on overlay `ubuntu24.1793970545` with no revert. Chain green; every step exited 0 with no failed check.

  | Gate | Run dir | Duration | Notes |
  |---|---|---|---|
  | M4 | `m4/20261106T182625Z` | 1514 s | `m4_ns3_neighbour_list_suite_passes` (row 159) |
  | M5 | `m5/20261106T185200Z` | 68 s | |
  | M6 | `m6/20261106T185336Z` | 96 s | |
  | M7 | `m7/20261106T185544Z` | 1411 s | route record (row 162): stash present, `e2term4561Est` 2, `rtmgrToE2termSvc` 2, `noEndpt12001` 10, matches false |
  | I0 | `i0/20261106T192026Z` | | |
  | I2 | `i2/20261106T192233Z` | | |
  | r2 single | `r2/20261106T192742Z` | 633 s | `r2_every_ue_tick_reports_min8_eligible_neighbours`, no problems |
  | r3p single | `r3p/20261106T193828Z` | 627 s | `r3p_every_ue_tick_reports_min8_eligible_neighbours`, no problems |
  | s10 | `s10/20261106T194917Z` | 1860 s | `s10_kpm_neighbour_list_exactly_8_when_more_than_8_cells_measured` |

- **M7's NOENDPT lines** (10 for 12001) are the early setups before the route table arrived. The stash and the two :4561 sessions show the table was received, and M7 is green.
- **Records.**
  - Each run dir has `evidence-sha256.txt`, including the red M4.
  - Raw archive `…-m10-p10d-20261107.tar.zst` (2,634 files: the ten run dirs and both chain dirs; SHA256SUMS verified).
  - Chain records are in `evidence/p10-chain/{cf325954-ub,302d310c-ub}/`.
  - `plans/.gitignore` now keeps `evidence/p10-chain/**`, like `cp2-chain`, except the probe's raw build stderr.
- **UB fix DONE.** Next in the commit order is P6.

## P6: KPM names checked against their 3GPP clauses, chain green (2026-11-07)
- **Commits.**
  - Testbed 254027ca on the fork `dev/l-release-nist180`, pushed. It holds the clause registry `kpm-measurement-clauses.v1.json` and its module, the strict lint with a self-test of 136 fixtures plus CLI cases, the metric map with every row failing row 147 renamed in place to `ns3.*` (48 rows; order and measId unchanged; R4 unit texts), and the kpimon eNB config regenerated from the map.
  - Harness 66cb0896: the pin, the registry and module added to `KPIMON_TESTBED_PATHS` (two new guard fixtures), and `lint.sh` running the lint's self-test.
- **Reviews.** Codex had 10 rounds. Rounds 1–4 were fixed by the subagent and rounds 5–9 by the controller; round 10 approved with no findings (`fullstack-developer-261107-0300-…`). The debate had already confirmed that no consumer needs an en-gNB 3GPP name (`brainstorm-261106-2359` §113).
- **Host checks at the commit:**
  - the shipped lint has 0 findings;
  - the two expected failures are gnb cell 34 and 35, which have pendingFix P9;
  - `--require-no-pending` exits 1 on those two only;
  - `lint.sh` and the kpimon guard self-test pass.
- **Gates:** `p10-gate-chain.sh 66cb0896… 3 5` from a frozen checkout, 20:29–21:02Z, on the same overlay. Chain green.

  | Gate | Run dir | Duration | Notes |
  |---|---|---|---|
  | M5 | `m5/20261106T202921Z` | 242 s | the agent image rebuilt as `ns3-e2-agent:254027ca7875` (new pin tag); tree at 254027ca |
  | M6 | `m6/20261106T203330Z` | 99 s | kpimon reinstalled; 42 checks pass |
  | M7 | `m7/20261106T203538Z` | 1580 s | route record: matches false (stash present, 2 sessions on :4561) |

- **Records.** Each run dir has `evidence-sha256.txt`. The raw archive is `…-m10-p10e-20261107.tar.zst` (485 files; SHA256SUMS verified). The chain record is `evidence/p10-chain/66cb0896-p6/`.
- **P6 DONE.** Next in the commit order is the SN-wrap fix (row 160).

## Follow-up candidates outside M10: LteRlcAm lossless-handover defects (consensus 2026-11-07, `decisions-261107-0633` Q3)
These are observations only, with no ledger rows and no fixes in M10. They sit next to the PRB and TB follow-ups. Each one is AM-only, is dead in scenario-zero (RLC UM), and would change behaviour without any wrap. Sources: kongming-261107-0555 "What to avoid"; Codex verified items 1, 2, 3 and 6 in source, and the rest are carried from that advice.
1. `LteRlcAm::m_transmittingRlcSdus` is never cleared; the map is cleared only in `DoDispose`. Later forwardings re-send old SDUs.
2. The forwarding lookback includes the head SN, so the head SDU is forwarded twice.
3. `m_segmented_rlcsdu` is never reset.
4. PDCP SNs 4096 apart collapse into one map key.
5. `m_txedRlcSduBuffer` misses the first SDU of each PDU.
6. The X2 SN Status Transfer reads the non-virtual `LtePdcp::GetStatus`, which `McEnbPdcp` hides (`lte-enb-rrc.cc:925-927`).

- **Trigger:** any gate or scenario that enables AM DRBs. Scenarios one, two, three and five set `RlcAmEnabled` from a global; the harness runs only scenario-zero.
- **P7 hazard:** if P7's step 2(b)/(c) unit tests trip on one of these, it becomes a P7 blocker with its own row and a ruling.

## Follow-up candidate outside M10: RLC UM tail re-submission at LTE↔mmWave switches (consensus 2026-11-07, `decisions-261107-0901` Q2)
This is an observation only, with no ledger row and no fix in M10. It is pre-existing at `m10-cp2` (6 archived M7 runs at ns-3 `ea6e46f6`), and scenario-zero's UM DRB hits it at every switch. The runtime cause has not been traced.
1. `ForwardRlcBuffers` copies the `LteRlcUmLowLat` TX buffer (`lte-enb-rrc.cc:1055-1061` @4a0871d6), whose head can be an unsent SDU tail (`lte-rlc-um-lowlat.cc:274-282`). The D/C test (`:1101-1102`) reads the tail's first byte:
   - **Top bit 0:** the tail is silently dropped as a "control PDU".
   - **Top bit 1:** two payload bytes are stripped as a "header", and the rest is re-sent as a new SDU with a new SN. These are row 149's short rows.
   - M6 has 78 switches and no short row, so silent dropping probably dominates [I].
2. Every re-submitted SDU fires McEnbPdcp TxPDU again (`mc-enb-pdcp.cc:221,238`). The DL PDCP counters that feed KPM (`mmwave-enb-net-device.cc:696-706`, `lte-enb-net-device.cc:1109-1111`) therefore count forwarded SDUs again in the switch epoch.
   - Example: IMSI 1 has 1663 PDUs against a steady 198 in [0.7, 0.8) s (`m7/20261106T223229Z`).
   - This matters for P6's PDCP-sourced volume and P9's counters.
3. The SwitchToLte return goes over two X2 legs (`:2190` → `:2218` → `:5627` → `:1217`), and the gNB→gNB path (`:905` → `ForwardRlcPdu`) forwards the same tails without passing through PDCP [I].
4. The UE RX PduSize reaches 1904 B (> 1310) in 120 of 5016 rows of switch epochs. This may be a UE reassembly anomaly [unverified].

- **Spec target [to verify in Zotero before citing]:** RLC UM and PDCP re-establishment for UM bearers (38.322 / 38.323).
- **Trigger:** any realism claim on switch-epoch DL volume or SDU integrity.

## Follow-up candidate outside M10: forwarded Packets aliased with the LTE RLC queue at MC setup (P7 red #1, kongming-261107-1015)
This is an observation only, with no ledger row and no fix in M10. It is pre-existing: the same PDUs appear at 4a0871d6. It is traced for 83 of the 341 GTP-U-framed PDUs in a 2 s 4-gNB run; the other 258 carry the same signature [I].
1. At an IMSI's MC setup (`lte-enb-rrc.cc:1464-1495` @4a0871d6), `ForwardRlcBuffers` takes the LTE RLC's buffer without resetting that RLC. `LteRlcUmLowLat::GetTxBuffer` (`:479-482`) never clears it, so the same Packet objects stay queued.
2. Forwarded objects re-enter `McEnbPdcp`. Its split sends some to X2, and `EpcX2::DoSendMcPdcpPdu` adds the GTP-U header in place on the shared object (`epc-x2.cc:1254-1255`).
3. The LTE RLC then transmits the modified object. The UE receives a 1322 B PDU starting `3b 03 05 22` (a 12-octet GTP-U header, then the PDCP header and the SDU).
   - Before P7 it was parsed as data and dropped by `McUeNetDevice` as "Unknown IP type".
   - Since P7's fix it is discarded at PDCP per 38.323 §5.10.
4. **Effect:** duplicated or lost DL SDUs around MC setup, and the PDCP RX counters count these PDUs.

- **Trigger:** any realism claim on DL SDU integrity or delivery around MC setup or switches.

## Pre-registration (2026-11-06; one docs commit before any P10 code after D-R3-1)
Sources: the user rulings in `plans/reports/decisions-261106-0525-GH-1-p10-pre-registration-questions.md`; kongming `kongming-261106-0500-…` (§7, §9, C.4, C.5) and `kongming-261106-1952-…`; ledger rows 147–161 (`check-diff-ledger.md`); contract Amendment 4.
- **Commit order (one fix per commit, for P11's bisection):** D-R3-1 (Testbed + harness pair), the neighbour-loop UB fix (Amendment 4, row 159), P6 (row 147), the SN-wrap fix (row 160), P7 (rows 148–150), P9 (rows 151, 152, 161), P15 (rows 153–155), D-06b-1 (row 81 amendment first), the kpimon node tag (row 137), the TS serving cell (rows 138–142, 158), UseIdealRrc (rows 156–157).
- **Design changes ruled against the text above:**
  - P6: no QosFlow.PdcpPduVolumeDL on any node. The MAC value and every name that fails row 147 are renamed in place to `ns3.*` (same order and measId). The PRB-family source fix is a follow-up outside M10; until then the PRB rows stay `ns3.*`. The eNB DRB.PdcpSduVolumeDl value fix (row `:128`) is a follow-up outside M10; P6 renames it.
  - P7: 12-bit SN in both directions (38.323 §6.2.2.2), so `NrPdcpHeader` is 2 octets and no SN type is widened. The header class comes from the bearer context, never from a packet tag. The SN-wrap fix is its own commit right before P7.
  - P9: Option A. DRB.PdcpSduVolumeDL/UL report 0 at every en-gNB; new map rows DRB.PdcpSduVolumeX2DL/UL carry the volume the MN submits over X2 to that cell (row 151's counting definition). The predictor reads X2DL with its formula, window, thresholds and decision unchanged (row 152, T3 ruled).
  - UseIdealRrc: the probe runs on the candidate commit with `scenario-zero.cc:492` deleted (row 157); c is judged by row 156.
  - P6 amended by the 2026-11-07 rulings (`decisions-261107-0045` item 4; row 147 amendment):
    - R1 strict value checks (exactly once on every reached path, timing only; `gaps` cannot hold).
    - R2: `DRB.UEThpDl`, the gNB `RRC.ConnMean` and `DRB.MeanActiveUeDl` are renamed; the 0525 log carries the amendment line.
    - The eNB `RRC.ConnMean` stays `ns3.*` until a run proves its attach bound. This changes the P6 draft, which kept it under its 3GPP name.
    - R3: the TB counter fix is a follow-up outside M10, next to the PRB fix.
    - R4: unit-text corrections, extended to enb cell 5, enb cell 6 and enb ue 10.
  - P9 amended by Q5 (row 151): S-SN→T-SN forwarding over X2 is counted at the receiving cell, revising Q2.
- **Gates per commit (P09 review §7.2, kongming-261106-0500 §2 and §7):**
  - UB fix: M4 (row 159's suite), M5–M7, one r2 and one r3p single (row 159's tick check), one s10 run.
  - P6: agent rebuild, kpimon reinstall (the map and the registry are kpimon stale-path inputs), lint with row 147's self-test, M5–M7. No M4 (ns-3 unchanged).
  - SN-wrap fix: row 160 red at `m10-cp2` (kept), green at the commit; M4, M5–M7; N4 determinism check for row 148 (b).
    - 2026-11-07 consensus (`decisions-261107-0633`): one ns-3 commit using RLC transmission order, judged by row 160 as amended (c)–(g). scenario-zero runs RLC UM, so M5–M7 and N4 at this commit and at P7 are no-regression guards and P7's byte-identity baseline, not coverage of the AM paths. P7's step 2(b)/(c) proof for the AM consumers must be unit tests on an `LteRlcAm` (ledger "Row 148 notes").
    - **DONE 2026-11-07 08:12 KST.** ns-3 4a0871d6, harness 716b41b9.
      - Row 160 suite (13 cases): red at the cp2 shim and at the widest-gap draft exactly as the amendment expects; green at the commit (`evidence/p10-sn-wrap/`).
      - Codex follow-up review: approve, no findings.
      - Chain M4–M7 green at 716b41b9 (`evidence/p10-chain/716b41b9-snwrap`); M4 log has `PASS: TestSuite pdcp-sn-wrap`. Raw archive p10f.
      - Row 148 (b) determinism, mechanism per the row 148 amendment (harness 3ab4c030, after three Codex findings fixed and a final approve): step 12 at 5ae73d27 green (`evidence/n4/20261106T230003Z`, raw archive p10g). uloff and ulon: a1 = a2 (same binary) and a1 = b1 (fresh second tree, own libraries only) on 37 manifest items each; uloff vs ulon differ on 23 items (discrimination); twin tree removed.
      - P7's reference: the a1 manifests are banked in `reference/n4-sn-wrap/` with `SHA256SUMS`.
  - P7: M4 (row 148), M5–M7 with row 149, N4 uloff/ulon byte identity with the SN-wrap commit.
    - **DONE 2026-11-07 12:10 KST.** ns-3 34b7f3cc (`NrPdcpHeader`) + 4318e43b (Control PDU discard), harness 3dac03b8 + 83b01bc6 (pin).
      - Red #1 (the one Failure Protocol fix): chain at 3dac03b8 red at M4 (`evidence/m4/20261107T010358Z`, chain log `p10-chain/3dac03b8-p7`); cause pre-existing (kongming-261107-1015, ledger "Row 148 notes, continued"); fix 4318e43b, Codex approve.
      - Chain at 83b01bc6 green (`evidence/p10-chain/83b01bc6-p7-fix`, steps 2–5 and 13): M4 `evidence/m4/20261107T020916Z` (22/22; `PASS: TestSuite mc-pdcp-nr-header`, `pdcp-sn-wrap`, `mmwave-neighbour-list`), M5 `m5/20261107T023424Z` (24/24), M6 `m6/20261107T023600Z` (43/43), M7 `m7/20261107T023808Z` (61/61), N4 identity `n4/20261107T030354Z` (11/11).
      - Row 149 at P7: M6 201 equality rows, 93 switch rows, 78 switch events; M7 3557 equality rows, 1819 switch rows, 10928 switch events; 0 problems. These equal the archive replay at the amendment (M6 201/93, M7 up to 3557/1819), so P7 reproduces the pre-P7 rows exactly.
      - Row 150: uloff and ulon byte-equal to `reference/n4-sn-wrap/` on 36 items each, only `ns3run/stdout.txt:audit-header` skipped; reference SHA256SUMS ok; audit judge `hdr=2 class=ns3::NrPdcpHeader`, a0–a5 true; emitters at ns-3 4318e43b, oran-interface 53253fe2.
      - Raw archive p10h (`plans-evidence-raw-m10-p10h-20261107.tar.zst`, 1588 files, red M4 included); per-run `evidence-sha256.txt` committed. /home 41 GiB free after the gates, so revert point 2 is not taken.
  - P9: M4, agent rebuild, kpimon reinstall, M5–M7, the V3 run by row 161's `--part v3`, R3′ single (a run without a predictor-driven handover is red; a scenario change is PAUSE T3).
    - 2026-11-07 design and consensus (`kongming-261107-1215`, `decisions-261107-1244`): counting at the en-gNB's X2-U boundary (row 151 amendment), audit v2, A8 inclusion, the M4 suite of row 163, the golden of row 164, row 152 (a)–(d). M4 also runs `m4_ns3_epc_x2_mc_pdcp_volume_suite_passes`. Chain: steps 2–7 (M4–M7, i0, i2), then step 14 (`n4 --part v3`), then step 10 (r3p single). N4 identity (step 13) is not a P9 gate (row 150 note).
    - Open user decision before P9 code lands: the remedy for the forwarded RLC UM tail gap (consensus Q-2).
  - P15: agent rebuild, kpimon reinstall, M5–M7, p12 with the re-baselined judge, R3′ single.
  - D-06b-1 and the kpimon node tag: as in steps 3c and 3d. The TS serving cell: step 3d (ii) plus row 158.
  - UseIdealRrc: the probe, then row 157's adoption gates.
- **Revert points to `f7-rerun-green` (kongming-261106-0500 §7 and C.5; the 34 GiB start guard stays binding):**
  1. before D-R3-1 (done: the D-R3-1 chain started from `f7-rerun-green`);
  2. conditional, before P9: revert if free /home after P7's gates is below 33 GiB;
  3. between P9 and P15;
  4. before the TS serving cell.

  Never start a p12 run or an xApp or kpimon build below 34 GiB free; revert first. Each revert re-runs the prefix at the then-current pins. Projected wall time is about 15–18 h; cycle 1 about 45–55 GiB.
- **The KPM T/T golden.** P9's appended cell rows break `kpm-report-period-test`'s byte identity against `fixtures/kpm-tt-golden-gnb2-seq26-35.txt`. The golden is regenerated in the P9 commit, with the reason in its commit message.

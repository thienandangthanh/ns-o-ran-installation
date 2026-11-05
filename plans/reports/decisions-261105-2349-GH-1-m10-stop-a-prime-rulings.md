# User rulings at M10 Stop A′, 2026-11-05 23:38 KST

Source: the user's written rulings in the session (2026-11-05 23:38 KST). Agenda: `docs/journals/2026-11-05-m10-stop-a-prime.md` § "Decisions required". Counsel: `plans/reports/kongming-261105-1606-GH-1-p08-exit-review-and-stop-a-prime-note.md` (GO-WITH-CHANGES; its notes were applied in 76acd2d before PAUSE A′). Plan: `plans/261103-0008-GH-1-post-m9-realism-m10/plan.md` (rev 3). Two rulings depart from the default: 1 (R-4 as written) and 6 (verify against Zotero now).

| # | Question | Ruling | Where it lands |
|---|---|---|---|
| 1 | The serving cell under R-4 and the AC14b reading | **Not the default: R-4 as written.** In P10, kpimon tags each UeMetrics point with the E2 node that reported it. This is a new layered patch file in `patches.manifest`, at its own commit. The TS xApp takes the serving cell and the UE IDs from the UE's latest Influx row and no longer uses the first cell of the QP answer. No `ns3.*` field may be part of the decision, and row 128 must still pass. The kpimon node-tag commit stays separate from the D-06b-1 commit, so P11 can bisect them. | plan R-4 (`plan.md:204-205`), phase-07 controller note (superseded), phase-10 scope; ledger rows 137–142 (registered now, before any code) |
| 2 | #9 rows 106, 120 and 121 | **Confirmed as registered.** | ledger (Stop A′ paragraph) |
| 3 | The VM prune rule | **Default.** Only `docker image prune -f` on dangling images. Never `-a`, never a tagged image, and never during a gate. Only when the guest root is above 75 %. `docker system df` and the removed image IDs are logged before and after. This also covers P06b's prune. | plan "Disk" constraints; phases 09–13 |
| 4 | `ns3.imsi` | **Default: keep it** as a vendor measurement through M10. | P10 AC16 lint classifies it |
| 5 | D-06b-1 | **Default.** Fixed in P10 at its own commit, with row 81's amendment first and not squashed into P15. | phase-10 |
| 6 | Zotero for the R-3 bandwidth rows | **Not the default.** The user has added 3GPP TS 38.101-1, 36.101 and 36.104 to Zotero. Verify the R-3 bandwidth rows against them now with the Zotero tools, cite the clauses, and drop the "unverified against Zotero" disclosure for each verified row. Report any row that disagrees with the spec as a P1–P3-style deviation. | phase-06 standards ledger; report `researcher-261105-2349-GH-1-r3-bandwidth-zotero-verification.md` |
| 7 | Codex triage | **Adopt kongming-261105-1050's rule.** A finding blocks the next chain only if, on a realistic path, it can turn a clean run red, turn a red run green, or lose a red run's evidence. Other findings get a ledger note now and a fix after the chain in the same phase, each with its own follow-up Codex review (the 2026-11-05 10:38 ruling stands). No harness commit lands while a chain runs. | plan constraints |
| 8 | /mnt/data headroom | **Met.** The user removed unused host podman images; /mnt/data has about 18 GiB free (user's df; re-read by the controller 2026-11-05 23:52 KST: 18 GiB available). Keep archiving raw evidence to the existing location (`/mnt/data/andang-data/ns-o-ran-installation-evidence/`). Recheck the free space before P10 and before P11. | plan budget; phases 10, 11 |
| P09+ | Extra item: the stale kpimon description in `docs/system-architecture-l-release.md` | Line 7 ("patched only for an 8-byte TimeStamp") and §6 ("Nothing else in kpimon changes") are out of date. Describe all our layered changes: the 8-byte TimeStamp (47920a4); the configurable reporting and granularity periods with subscription by measurement ID (4b4a61a, 809fb2d); the eNB measurement lists from `enb-kpm-measurements.json` (75e80ba); and the `ueId` tag on UeMetrics (89d45af). Point to `install_xapp_kpi_monitor.sh:38-59` and `patches.manifest` as the authority instead of copying their detail. Its own docs commit in P09. When P10 lands the node-tag patch, update the same section. | phase-09 step, phase-10 step |

## Contract
No amendment is needed.
- Ruling 1 restores R-4 as pre-registered. AC14b already reads "kpimon stores the decoded UE ID in Influx, and the TS xApp reads it from there to build the AC14 control" (contract §4, T-A). §2 already lists the kpimon and TS xApp fork patches.
- Rulings 2–8 sit inside the existing constraints (§5) and the allowed substitutions (§7).
- The scope guard holds: no deliverable is narrowed. Ruling 1 adds work to P10 (a kpimon patch, a TS xApp change and their checks). It does not add a contract item.

## Ruling 1: what the controller pre-registers (before code)
These are the forms that rows 137–142 bind. They are the controller's reading of "R-4 as written". None is a product choice beyond the ruling.
- **The node tag.** kpimon adds the tag `e2NodeId` to every UeMetrics point. Its value is the RAN name of the E2 node whose RIC INDICATION carried the point (`params.Meid.RanName`, for example `en_gnb_001_001_00000002`). It is a new patch file, `control/control.go.e2-node-tag.patch`, listed after `control.go.ue-id-tag.patch` in `patches.manifest`.
- **The TS xApp order stays the same.** It gets the prediction (30002) first, then reads Influx, then decides. Plan R-4 and the P07 inventory ruling 4 both have this order. Then:
  - **One query.** The TS xApp sends one Flux query: the UE's UeMetrics points with exactly that `ueId` tag in the last 60 s, keeping `_time` and `e2NodeId` only. The query names no field, so no `ns3.*` name is ever read.
  - **The serving cell** is the `e2NodeId` of the latest point by `_time`. The TS xApp maps it to the one key in `cell_map` that belongs to that RAN name and that the prediction also names. `cell_map` holds two keys per en-gNB: `…10`, the NR CGI, and `…00`, a by-product of the Global en-gNB ID (`replay-ts-cell-map.py`). The QP answer names only cell keys.
  - **No control, with a logged reason, when:** no point exists (row 125); the latest `_time` carries more than one `e2NodeId`; no key of that node in `cell_map` is named by the prediction, or more than one is.
  - **The decision** is unchanged: hand over iff the best other cell's dl > (1 + threshold/100) × the serving cell's dl. Only the source of "serving" changes. The answer's order no longer matters.
  - **The UE IDs** come from the same `ueId` tag, parsed as today.
  - **One log line per decision,** naming the serving cell key and its `e2NodeId`. It is for diagnosis only. The checks judge on the wire and the ns-3 context files (row 142), never on xApp logs.
- **eNB rows** carry `enbUeId:…` tags, so an en-gNB-UEID key never matches them. The eNB cannot become the serving cell.
- **Commits (P10, one each, in this order within the T-C sequence):** the kpimon node tag (Testbed), then the TS xApp change (Testbed). Each comes with its ledger rows, which are already registered here. The kpimon commit is separate from D-06b-1's.

## Rule-#9 rows (ruling 1 asks to flag them)
**None of the new rows 137–142 is a #9 rewrite.** None of them changes a predicate that encodes P1, P5 or N5.
- **Closest is row 141.** It reorders the `predictions` of two R2 cases in `r2-scenario.json`, the file that #9 row 19 governs. It does not touch any `via`, `key` or `targetCell` value, and every expected outcome stays as it is.
- **The P1 addressing checks are unchanged:** D7, wire and expect (rows 10–16). They now also confirm that the Influx-derived serving cell is the true source en-gNB.

## Unresolved questions
- None from these rulings. The T′ base is still ruled at Stop B (S5).

## Follow-up rulings (2026-11-06 ~00:27 KST), from ruling 6's Zotero check
The Zotero check of the R-3 rows (`researcher-261105-2349-GH-1-r3-bandwidth-zotero-verification.md`) found one deviation, D-R3-1: the agent sends NR-ARFCN 633333 as the X2 `NRARFCN`, which is Point A, and also as the SSB frequency. As a carrier reference it is off n78's 30 kHz raster. On the user's request, counsel came from kongming (`kongming-261106-0008-GH-1-nr-arfcn-deviation-d-r3-1.md`) and from Codex (read-only), which agree. The user then added 3GPP TS 38.104, 38.211 and 38.213 to Zotero, and the controller re-checked the key clauses there.

| # | Question | Ruling | Where it lands |
|---|---|---|---|
| 6a | D-R3-1 fix | **Fix (b), as P10's first commit pair.** X2 `NRARFCN` (Point A) = 632758, carrier reference 633334 (3500.010 MHz, implied), MTC SSB 633312 (GSCN 7846); band, scs60, nrb24 and SMTC unchanged. The AC6a probe is fixed in the same harness commit. | ledger rows 143–144; plan R-3; phase-10 step 0 and commit order; phase-11 bisection list; phase-06 standards ledger |
| 6b | ns-3 28 RBs against the wire's 24 | **Disclose only.** It is an ns-3 model simplification; the wire keeps nrb24. | phase-06 standards ledger; P13 records |

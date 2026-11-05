# M10 Stop A′: checkpoint 2 tagged, live runs equal T(M9) at δ 0, 150 and 500 (2026-11-05)

Plan `plans/261103-0008-GH-1-post-m9-realism-m10/plan.md` (rev 3), locked contract
`plans/reports/contract-261103-0001-GH-1-post-m9-realism-outcome-contract.md` (Amendments 1–3). Phases P00–P08 are
done. This is the planned Stop A′, and the run waits for the rulings at the end. No T-C code has been written.

## Outcome
- **Checkpoint 2:** `m10-cp2` is annotated at harness `dd27868` and pushed in all five repos. The forks are tagged at
  their pins: Testbed `554d6d6`, ns-3 `ea6e46f`, oran-interface `53253fe` and e2sim `e270581`. Because the tag is
  annotated, `git rev-parse m10-cp2^{commit}` is the command that gives dd27868.
- **The chain:** it ran from `f7-rerun-green` at one harness SHA with one pin set, 20/20 green, 02:21–07:06 UTC. The
  order was M2, M3, M4, M5, M6, M7, I0, Q8, R0 single, R1 single, I2, R2 C1, R3′ calibrate, R3′ dryrun stage b, R3′ C1
  at δ 0, 150 and 500 with `--reference-transform`, e2i, the δ seam smoke and R1 C1. It replaces P07's mixed pass set
  with one uniform set. The step log is `evidence/cp2-chain/dd27868/p08-gate-chain.tsv`.
- **AC8b:** met at all three δ (table below). The self-test `reference-transform-compare.py --selftest` passes:
  - fixtures a–c and e–l fail, each naming its file and field, and fixture d passes;
  - an identity map that does not match its SHA256SUMS is refused;
  - a T that rewrites a field outside R-2 is caught.
- **Evidence:** every run dir has its verdict layer and an `evidence-sha256.txt` in git (23cdb3e). The raw files are
  in `plans-evidence-raw-m10-p08b-20261105.tar.zst` (138 MB, 5,682 files) on
  `/mnt/data/andang-data/ns-o-ran-installation-evidence/`, and `SHA256SUMS` was verified.
- **Exit review:** kongming-261105-1606 returned GO-WITH-CHANGES. All its required changes are record notes, and all
  are made (`phase-08-…md`, "Exit").

| δ (ms) | run dir (`evidence/r3p/`) | pass | liveRunsEqual / replayEqual / rngRun2Differs | transformEqualsM9 | transformedFields | fieldsWithoutOccurrence | literal |
|---|---|---|---|---|---|---|---|
| 0 | `20261105T052524Z` | true | true / true / true | true (M9 raw + M9 digests) | 17 | meid | ipc, traces, kpm-headers, collet-start-time |
| 150 | `20261105T054823Z` | true | true / true / true | true (cp1 `reference/r3p-d150`) | 17 | meid | same |
| 500 | `20261105T061121Z` | true | true / true / true | true (cp1 `reference/r3p-d500`) | 17 | meid | same |

The compare requires `transformedFields` together with `fieldsWithoutOccurrence` to equal R-2's list exactly, and any
other differing byte fails with its field named. G2 (Stop A) is met: the δ rungs now have their checkpoint-2 baseline
for AC16. I-2 holds as well: HandoverStart − apply = 3.0 ms in all nine live runs, with one applied line each
(`checks/r3p_live*_actuation_delay_…_handover_start_at_apply_plus_c.out`).

**P4-KPM status at cp2:** fixed, with one scheduled residual, D-06b-1 (P10). The alternative recorded in P06b, "fix it
before cp2", lapsed when cp2 was tagged.

## I-1: the X2 message mapping (F2)
The left column is the SN-initiated SN change in 3GPP TS 37.340 v18.7.0 §10.5.1, Figure 10.5.1-2, pp. 61–63 (Zotero
`E6VYJPXJ`; steps 1–6 read 2026-11-04, steps 6–17 re-read 2026-11-05). The right column is what ns-3 (`ea6e46f6`)
does when the TS xApp's Style 5 action 3 control reaches the source en-gNB.

| §10.5.1 step (EN-DC, SN-initiated) | ns-3 in M10 |
|---|---|
| 1. S-SN → MN: SgNB Change Required (target SN ID) | The source en-gNB calls the MN in process, with zero latency (`mmwave-enb-net-device.cc:1541-1554`, `ApplyExternalHandover`). No X2 message goes on the wire. |
| (no step) | The MN's local checks: the UE is known, the target is known, the UE is not in handover, not already on the target, and not on LTE (`lte-enb-rrc.cc:4570-4619`). |
| 2/3. MN ↔ T-SN: SgNB Addition Request / Acknowledge | The S-SN → T-SN X2 HandoverRequest / HandoverRequestAck (`lte-enb-rrc.cc:5150-5157`, `:774`). The function is the same, but the endpoints differ: SN ↔ SN, triggered by the MN's request. |
| 4/5. MN ↔ UE: RRCConnectionReconfiguration / Complete | ns-3's RRC model. With `UseIdealRrc=true` (`scenario-zero.cc:492`), RRC delivery is ideal until the AC17 probe. |
| 6. MN → S-SN: SgNB Change Confirm | The MN → S-SN X2 `McHandoverRequest` (`epc-x2.cc:1345`). Same direction, but it comes earlier in the order, before the target's admission. |
| 7. SgNB Reconfiguration Complete; 8. UE synchronises to T-SN; 9. SN Status Transfer; 10. data forwarding; 11. Secondary RAT Data Usage Report; 12–16. path update; 17. UE Context Release | ns-3's own handover model, or not modelled. It is not §10.5.1 message by message. |

- **The source row was wrong.** P07's standards row (`phase-07-…md:141`) had put steps 2/3 at "the MN's admission and
  X2 `McHandoverRequest`". The P08 exit review found this was wrong, and the code confirms it. A dated note under the
  table corrects it. Plan I-1 (`plan.md:253`) already mapped `McHandoverRequest` to step 6 only.
- **Why the control goes to the source en-gNB:**
  - E2SM-RC v03.00 §8.4.6.3 says the E2 node invokes "SNChange (only SN-initiated)".
  - 3GPP TS 37.340 §7.2 allows an MN-initiated SN change only for inter-frequency changes.
  - The scenario is single-carrier.
- **What can be observed is unchanged:** `X2Stats.txt` and `EnbHandoverStartStats.txt` are in the traces digest and
  literal-equal to M9 at δ 0.

## Budget re-projection (scale and T-C cost)
**Host growth per step in this chain** (allocated overlay GiB / /home GiB, from each run dir's `host-disk.tsv`):

| Steps | Growth |
|---|---|
| M2 | 3 / 3 |
| M3 | 12 / 12 |
| M4 | 3 / 3 |
| M7 | 0 / 1 |
| I0 | 3 / 2 |
| Q8 | 0 / 1 |
| R3′ dryrun | 1 / 0 |
| All others | 0 / 0 |
| **Total** | **22 / 24** (overlay 1 → 23, /home 79 → 55) |

**Disk on /home.** There is 56.9 GiB free now and about 80 GiB after the next revert, which unlinks the 23 GiB
overlay.
- N_new is now measured, not inferred. e2i, the three R3′ C1 runs and the seam smoke grew about 0 GiB. s10 adds about
  0.7 GiB per run (AC6b). p12 and the single-run δ identities add about 0–1 GiB [I]. So N_new ≈ 1–3 GiB.
- T′_method = 37 + 43 + 12 + N_new ≈ 93–95 GiB.
- T′_measured′ is between 78 and 88 GiB [I, until the P11 per-step measurement].
  - The low end, 37 + M9's m0 + m1 (3 + 13) + this chain's 24 + N_new, is a warm lower bound: the chain started from
    `f7-rerun-green`, whose base already holds the RIC, the images and the build caches.
  - The high end takes the larger of M9's and this chain's growth for each step, giving 37 + 48 + N_new.
  - The swing term is cold M3: 20 GiB in M9 against 12 GiB here.
- **Reachable /home at Stop B is about 71–73 GiB, not 80.**
  - Raw evidence stays in the worktree on /home. This plan's `evidence/` is 9.6 GB today, and each full chain adds
    about 1.8 GB.
  - The shortfall is then about 20–24 GiB under the method base, and about 5–17 GiB under measured′.
  - **Expect to free 10–25 GiB at Stop B.** The base is still ruled at Stop B (S5).
- **Revert arithmetic.** From a revert, 80 − 24 − 24 = 32 GiB, which clears the 22 GiB watchdog trip. Two full chains
  fit per revert, and a third does not.

**Remaining VM time before Stop B** [I]. The unit costs come from this chain. The prefix, M2 through I2 from a revert,
takes 8,602 s (2.4 h) and 22 GiB.

| Phase | Wall time | Disk | What it contains |
|---|---|---|---|
| P09 (scale) | about 4–5 h | about 24 GiB | The prefix, the p12 baseline at the cp2 pins, and 2–3 s10 runs (about 2,100 s and 0.7 GiB each, AC6b). |
| P10 (T-C) | about 6.5–8 h | about 46 GiB from one revert | The prefix, an M4 rebuild (1,281 s, 3 GiB) per fix with the M6 and M7 regression, and P15 with D-06b-1 (M5, then M3 at 2,181 s and 12 GiB, M6, M7, p12 and R3′ single). |
| P11 (cp3) | about 11–14 h | at least 2 reverts | The prefix; about 4 bisection points of a rebuild plus a C1 (1,370–1,400 s each); the final C1 and four δ C1s; the rehearsals; cold I0, I2 and M3 from `fresh-install` (about 35–40 GiB). This replaces the phase file's "6–8 h". |
| **Total** | **about 22–27 h** | | Without reds. |

**Wall time W′.** The chain's longest steps were M3 2,181 s, M7 1,463 s, R3′ C1 1,372–1,403 s, R2 C1 1,402 s and M4
1,281 s. These sit inside Stop A's W′ ≈ 29–33 ks inputs. As ruled at Stop A, `m9-budget.py` is extended in P11.

**Disk on /mnt/data: 6.24 GiB free, against the 5 GiB floor.**
- This chain's archive was 1.8 GB raw and 138 MB compressed (13:1).
- The remaining archives come to about 1.0 GB: P09 about 0.06, P10 about 0.15, P11 0.3–0.4, and the end run about
  0.45. That leaves about 5.2 GiB, before any growth in podman storage on the same disk.
- **PAUSE T2 is likely during P11 or the end run** (question 8).
- Podman storage there shows 86 GB of images and 211 GB of volumes as reclaimable. These are not this plan's builds,
  and nothing was touched.

## Disclosures (no ruling needed)
**P08 red #1 and its fix.**
- **What happened:** step 15 of the first cp2 chain (harness 668d1ef) went red at the host runner, while the gate
  itself passed. I rewrote `scripts/vm/vm-exec.sh` while that runner was executing it, and bash resumed at a stale byte
  offset.
- **Classification:** kongming-261105-1050 counted it as red #1. The controller classifies reds with kongming under the
  Failure Protocol. You may rule it a non-red; nothing changes either way.
- **The guided fix** was a procedure change (the chain note in the ledger, 813e9c9): every step runs from a frozen,
  locked checkout, and each green step's run dir is cross-checked.
- **The superseded dirs:** the 668d1ef run dirs are kept as evidence and archived (`…-m10-p08a-20261105`).

**Codex runs 1–7 in P08.** All were read-only.
- Runs 1–6 found real defects in the watchdog lifecycle, `nist_run` and the transform. Each was accepted and fixed
  after its ledger amendment: 4111713, 1a4e528, dc0cf0b, ea8b681, 791e405, 749fbd0, 668d1ef, 33b4992, 293957f and
  0d32a88.
- Run 7 approved.
- Under your ruling (2026-11-05 10:38 KST, "don't skip a fourth Codex review"), every Codex-driven fix gets its own
  follow-up review.

**Chain operation.**
- **Launch.** The chain ran as `systemd-run --user --wait` (KillMode=mixed, TimeoutStopSec=180), the route that P10 and
  the end run use.
- **A 1 GiB deviation, accepted.** kongming-261105-1050 set the launch condition "/home ≥ 80 GiB after the revert",
  and the chain launched at 79 GiB. I accepted that 1 GiB deviation: the old overlay had been confirmed unlinked, and
  the watchdog trips at 22 GiB. The minimum during the chain was 55 GiB, with no trip.
- **Not logged.** The driver's sha256 was not logged in the tsv. The committed driver
  `evidence/cp2-chain/p08-gate-chain.sh` is the file the unit ran (`9642fbdc5f349183…`).
- **Runner smoke.** Before the chain, an M6 run from the frozen checkout was green, its records were complete, and no
  process was left. The log is `evidence/cp2-chain/dd27868/runner-smoke-m6.log`.
- **Allowlist.** `host-disk-watchdog.json` and `evidence/cp2-chain/` are now on the verdict-layer allowlist (813e9c9).
- **A tool-shell slip.** During a mutation test, I stopped a deliberately leaked watchdog with a `pgrep -f` pattern
  that also matched my own tool shell. Only that shell ended.
- **The chain at 749fbd0 was stopped** about 3 minutes into M2, to take Codex run 3's fix.
- **The VM was reverted to `f7-rerun-green` several times** in P08. `--pending` was checked each time, and no overlay
  was orphaned.
- **Frozen checkout for the runners.** `run-to-m9.sh` and the M10 runner should get the same frozen-checkout hand-off
  as the P08 driver. This goes to P12 as its own ledger row (kongming-261105-1050).

**The compare.**
- **meid** is in `fieldsWithoutOccurrence`. No compared M9 file carries a meid, so T has nothing to rewrite there. Any
  meid path can only fail: a rewritten meid falls outside R-2's classes, and one left unrewritten fails explicitly. The
  ledger has notes on row 136.
- **Fixtures j–l** were added after Codex runs 1 and 2: a malformed N5 `targetKey`, and a partially converted schedule
  and stage-A classification.

**p12** has not run since the P06b pins (`p12/20261104T104145Z`). P07 changed the per-seq context that p12 uses, so P09
runs p12 at the cp2 pins first.

**Carried from P07** (kongming-261105-0536):
- The pass-set spread and the agent-image rebuild, now superseded by this uniform chain.
- The /home floor breach (minimum 17 GiB), with the red M5 evidence lost.
- The Failure Protocol skip for P07's three reds, endorsed after the fact.
- The e2i cause mapping, and the stop-time `late` lines with `imsi` 0.
- The 60 s Influx window, and the token install pattern.
- The T_ctl/W provenance strings still cite M9-era calibrations. P07 re-measured L_max at 15.3 ms, with
  `tCtlCoversTwentyLMax: true`.
- The TS xApp keeps upstream's REST control default, which the harness switches to gRPC at install.

**Carried from P06 and P06b:**
- The R-3 X2AP refinements: `nR-TxBW` {`scs60`, `nrb24`}, and the 2-octet Configured TAC with no 5GS-TAC.
- The MME UE S1AP ID equals the IMSI, by ns-3's construction.
- The GUMMEI constants.
- The controller rulings on rows 79–100 (`check-diff-ledger.md:195`).
- The e2i association-based frame-to-node mapping, resolved as harness work in P07.
- P06b's two step deviations: step 2's local proof ran after M4–M7 on the VM, and step 5 used the full r3p single
  gate.

**No VM `docker image prune`** has run since P06b. It waits for question 3.

## Decisions required (Stop A′ agenda; each has a default, and kongming's recommendation matches it)
1. **The serving cell under R-4, and the AC14b reading.**
   - Default: accept. The TS xApp takes the serving cell from the QP answer, confirms that the `ueId` tag exists in
     Influx within 60 s, and parses the UE ID from that tag (`plan.md:204`). Row 125's negative makes the dependency
     visible on the wire in every R2 and R3′ run.
   - Alternative: R-4 as written. kpimon would tag the reporting node, and the TS xApp would read the serving cell and
     IDs from the latest row. That means a kpimon and TS xApp rewrite, bundled into P10.
2. **Confirm the #9 rows 106, 120 and 121.** Default: confirm as registered. They were registered before their code and
   passed again in the uniform chain.
   - **Row 106 (G1, the δ seam smoke):** every control moves to the migrated IPC schema, `{nodeId, ctlId, ueId:
     {mEnbUeX2apId, mnCellId}, targetCellId, afterSeq}`, with no `imsi`. Each control is sent through the UE's source
     en-gNB, with the UE IDs taken from the frozen cp1 map and verified per run by row 107.
     - Why it is not weaker: every asserted predicate keeps its code (the line count, the δ arithmetic, ack pairing,
       cancel at stop, tie order, pins and emitter SHAs), and the case mix keeps every outcome.
     - The count rises by one, for an added non-source control. It passed 32/32.
   - **Row 120 (e2i):** the independent codec encodes Style 5 action 3 with IMSI 6's en-gNB-UEID through its source
     en-gNB, and expects an ack.
     - The N5-form negative is now the same control with only the target changed, so it still tests the target.
     - Three cases are added: the old Style 3/1 encoding (expects `action-not-supported`), a non-source en-gNB, and the
       eNB.
     - Why it is not weaker: the applied positive and the N5 refusal keep their judge, nodes, steps and expected
       answers.
   - **Row 121 (e2i ledger):** the ledger has exactly two lines.
     - (2, 6, 3, applied) at rxSeq 20 is unchanged.
     - (3, 0, 3, refused `unknownUe`) is added at rxSeq 60. Its pacing-log record names IMSI 3.
     - The handover starts stay [(6, 3)], and there is no ledger line for the agent-local refusals.
     - Why it is not weaker: the applied line and the single handover start are unchanged, and the added line proves
       that the non-source control reached ns-3 and was refused for its addressee.
3. **The VM prune rule.** Default: ratify it narrowly. This interprets §5, "Nothing is deleted autonomously", and
   covers P06b's prune.
   - Allowed: `docker image prune -f` on dangling (untagged) images only. Never `-a`, never a tagged image, and never
     during a gate.
   - Only when the guest root passes 75 %.
   - `docker system df` and the removed image IDs are logged before and after.
   - P10 rebuilds ns-3, the agent and kpimon. Without this rule, the 85 % guest guard could stop a build in the middle
     of the phase.
4. **`ns3.imsi`.**
   - Default: keep the vendor measurement through M10. The contract forbids only an IMSI carried as a gNB-UEID, and
     P10's lint classifies `ns3.*` as vendor measurements.
   - Alternative: remove it by amendment. That changes the KPM content and needs attribution at cp3.
5. **D-06b-1** (the MeNB UE X2AP ID sent without DC).
   - Default: fix it in P10 at its own commit, with row 81's amendment first and not squashed into P15, so P11's
     bisection can attribute it.
   - Alternative: fix it before P09.
6. **Zotero.**
   - Default: accept "unverified against Zotero" now for the R-3 bandwidth rows, under AC20, and add 3GPP TS
     38.101-1, 36.101 and 36.104 before the P13 records.
   - Alternative: add them now.
7. **Codex triage rule.** Default: adopt kongming-261105-1050's rule.
   - A finding blocks the next chain only if, on a realistic path, it can turn a clean run red, turn a red run green,
     or lose a red run's evidence.
   - Other findings get a ledger note now, and a fix after the chain in the same phase, each with its follow-up Codex
     review. Your 10:38 ruling stands.
   - No harness commit lands while a chain runs.
8. **/mnt/data headroom.** Default: you free at least 5 GiB on /mnt/data before P10, or name another target for the
   raw archives. Only you know which podman images and volumes there are safe to remove. Without this, expect PAUSE T2
   around P11 or the end run.

## Unresolved questions
- Rulings 1–8 above.
- Whether M2's and M4's growth here (3 GiB each, against 0 and 1 in M9) is a real cold cost or comes from the warm base.
  P11's cold rehearsals answer this.

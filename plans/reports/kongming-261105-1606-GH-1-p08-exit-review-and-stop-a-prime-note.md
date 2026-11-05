# P08 exit review and Stop A′ note (checkpoint 2, transform-compare)

Date: 2026-11-05 16:06 KST (Asia/Seoul). Reviewer: kongming, advisory only. Runtime: Claude Code subagent on Opus 5.5 (`model: opus`, per the user's CLAUDE.md override of the `fable` routing).

**Scope.** Harness HEAD `23cdb3e` (last script change `0d32a88`; `m10-cp2` → `dd27868`). Pins: Testbed `554d6d6`, ns-3 `ea6e46f6`, oran-interface `53253fe`, e2sim `e2705816`.

**Method.** I did no VM operation and called no Codex. On the host I did the following:
- re-read the three R3′ C1 verdicts, their `checks.jsonl` and `.out` files;
- recomputed per-step disk use from all 20 `host-disk.tsv` and `host-disk-watchdog.json` files;
- ran `python3 -I scripts/gates/reference-transform-compare.py --selftest` (ok);
- read the tags with `git cat-file` and `git ls-remote` in all five repos;
- ran `sha256sum` on the p08b archive and counted its `.list0`;
- ran `df` on the host;
- read the ns-3 SN-change code path for I-1.

## TL;DR

- **(A) P08 exit: GO-WITH-CHANGES.** I checked AC8b, G2 and every Validation bullet against the committed evidence myself (table A1).
  - No check was weakened or narrowed, no scope-guard rule slipped, and all ten checkpoint tags are correct (cp1 and cp2 in five repos).
  - The required changes are record-only:
    - the resume card and the phase table;
    - two Validation-wording notes;
    - a row 136 note that the meid path can only fail;
    - the phase exit entry;
    - the complete Codex fix list.
  - None of them touches the tag.
- **(B) Stop A′ packet: complete in shape, but not yet correct.** Fix three things before it goes to the user:
  1. **The I-1 table puts steps 2/3 at the wrong endpoints.** In ns-3, the target SN admits the UE through an SN↔SN X2 HandoverRequest from the source SN. The source SN sends it after the MN's McHandoverRequest reaches it. There is no MN↔T-SN exchange. Plan I-1 was closer to this than ledger row 141 is.
  2. **The budget is optimistic.**
     - /mnt/data has 6.24 GiB, not 7, and the remaining archives take it to the 5 GiB floor by the end run.
     - T′_measured′ 78–80 GiB is a warm-start lower bound, with an upper bound near 86–88 GiB.
     - "P11 about 6–8 h, as written" is not a re-projection. With this chain's unit costs it is about 11–14 h.
  3. **The questions need tidying.**
     - Q2, Q7 and Q8a have no default.
     - Q6 and Q8b are disclosures, not questions.
     - A /mnt/data question is missing.
- **First thing in P09: run p12 at the cp2 pins.**
  - AC10's gate last passed at the P06b pins (`p12/20261104T104145Z`, harness 28d4508).
  - P07 then changed the agent's per-seq context path, which p12's multi-record indications exercise.
  - P11 also needs a cp2 p12 baseline to attribute P15's change.

## A. P08 exit review

### A1. Validation bullets, AC8b and G2, checked against the verdicts

| Item | What I checked | Status |
|---|---|---|
| Self-test: a, b, c, e–i fail, d passes (`phase-08:49`) | I ran it at HEAD (`scripts/` is identical to dd27868). Fixtures a–c and e–l fail, each naming its file and field; j–l name field `T` (T refused the M9 file). d passes. The identity map off its SHA256SUMS is refused, and a T that rewrites ledger `targetCell` is caught. Exit 0. The gate check `r3p_transform_compare_self_test` passes in all three runs. | met |
| `liveRunsEqual`, `replayEqual`, `rngRun2Differs` | The `c1` block of `r3p/20261105T052524Z`, `054823Z` and `061121Z` is all true. Each run has 194 checks, none failed, `pass: true`, `harness_sha` dd27868…, and pins as tagged. | met |
| `transformEqualsM9: true` | Each run's `checks/r3p_c1_live1_transform_equals_m9.out` has `problems: []`. The δ 0 and δ 500 outputs are identical. | met |
| `transformedFields` equals the R-2 list exactly (`:53`) | The 17 fields plus `fieldsWithoutOccurrence: ["meid"]` together equal `FIELDS` (`m9-transform.py:24-33`, 18 entries). The literal bullet is not met; the bullet as amended in row 136 (07b82bd) is. | met under the amended reading; note required |
| `literalComponents ⊇ {ipc, traces}` | ipc, traces, kpm-headers, collet-start-time | met |
| G2: d150 and d500 against the cp1 δ references | `transformReference` is `reference/r3p-d150/{raw,equal}` and `…/r3p-d500/…`. These are byte copies of P04's C1 at 876c8d6 (`SOURCES.txt`), tracked since 23f85dc and 58629fc, before P05. The predicates are the same as at δ 0. The cp1 δ digests hold only ledger, ipc and traces, so kpm-headers and collet-start-time were compared byte for byte against the promoted raw `extra/` files. That is stronger than cp1's own δ check. | met |
| `git rev-parse m10-cp2` equals the verdict SHA (`:56`) | The literal command gives `d873afd`, the annotated tag object. `m10-cp2^{commit}` gives dd27868, which equals all three verdicts' `harness_sha`. Local and origin agree. | met under `^{commit}`; note required |
| AC8b: ipc and traces literal at δ 0 | Compared against M9's `reference/r3p/equal/digests.json`: 3 ipc nodes and 33 traces, including `X2Stats.txt` and `EnbHandoverStartStats.txt`. There are 0 `ueContext` lines in the ipc trace. | met |
| AC8b: predictor records, scenario, schedule = T(M9) | The compare covers these and the stage-A classification. The run side is live1; live2 and live3 equal it through C1. | met |
| AC8b: ledger and `extra` differ only on enumerated fields | Ledger: `viaNodeId` only. rc-multiset: `viaNode`, `style`, `action`, `targetKey`, and `imsi` → `ueId` {mEnbUeX2apId 3, 00F110/00001}, taken from `identity-map-cp1.json`. That map's sha256 `aa5a98c7…` equals `reference/SHA256SUMS`. kpm-headers and collet-start-time are literal. | met |
| AC8b: a mutated M9 file fails | j, k and l mutate M9 raw files and re-write their checksums, so only the compare can catch them. | met |
| AC8b: the passing commit is tagged | `m10-cp2` is annotated at dd27868, and its message lists the 20 run dirs and the pins. On GitHub, each fork's annotated `m10-cp2` peels to its pin, and each fork's `dev/l-release-nist180` head equals that pin. | met |
| Chain integrity | 20 tsv lines, every rc 0, frozen HEAD dd27868 on every line. Every run dir has `exit_code` 0, `host-disk.tsv`, a watchdog record with `tripped: false` (minimum 55 GiB) and a passing verdict. No `gate-*` or `p08-*` unit, watchdog process or frozen worktree is left. | met |
| I-2 | `applyToHandoverStartMs: [3.0]` on the single applied line of each of the 9 live runs, at δ 0, 150 and 500. | met |
| Raw archive | The p08b sha256 matches `SHA256SUMS`, and the `.list0` has 5,682 entries. | met |

### A2. Record accuracy and AC18

**No check was weakened or narrowed.**
- `git diff 3dfe627 dd27868 -- scripts tools` removes no `check` line. The removed lines are:
  - the old `fact()` body;
  - the old `kubectl exec` token read in the scrub;
  - `nist_run`'s old stdin producer;
  - the old `vm_state` and wait loop;
  - the old Testbed pin.
- Each successor adds a failure condition or keeps the fail-closed rule.
- `--reference-transform` is added beside `--reference`, and C1 is unchanged.
- `fact()` now re-serialises valid JSON onto one line. Facts never gate.

**Commit order holds.**
- Rows 130–136 (65542db, 06:06) precede all P08 code (94d0225, 06:17).
- Each amendment precedes its fix:
  - 4d3aef5 before 4111713, 1a4e528 and dc0cf0b;
  - 2df76db before ea8b681, 791e405 and 749fbd0;
  - 66d1d29 before 668d1ef;
  - 1bd18bd before 33b4992;
  - 87c3757 and b4109d2 before 293957f;
  - 20c653d before 0d32a88.
- The chain procedure note (813e9c9) precedes the driver commit (dd27868).
- **Process note:** the meid amendment 07b82bd and its code abc2a74 carry the same second (06:28:21). History shows their order, but not that the row was decided before the code was written. This is the same situation as row 129's note, and it is tolerable for a new check whose original form could never pass.

**Record findings.** None of these affects a verdict.
1. **The meid path can only fail (row 136, work record `:97`, journal `:99-100`).**
   - `classify()` (`reference-transform-compare.py:97-127`) has no meid class. A meid that T rewrites therefore fails as "T changed a field outside R-2's list".
   - A meid that T does not rewrite fails at `:201-202`.
   - `meid()` (`m9-transform.py:139-143`) maps only `gnb_001_001_%08x`. R-2's eNB → `enB_macro_001_001_000001` rewrite appears in the docstring (`:17`) but not in the code.
   - So "A meid that occurs and is not rewritten fails" is true but incomplete: any meid occurrence fails. The path fails closed, and T is not reused after cp2, because cp3 makes new references.
   - Add a dated note on row 136 and in the work record. No code change is needed.
2. **Validation wording.**
   - `phase-08:53` and `:56` are met only under row 136's amendment and under `^{commit}`. Add dated notes to both.
   - `phase-11:52` uses the same `git rev-parse m10-cp3` wording. Fix it before P11, because that tag will also be annotated.
3. **The plan card and phase table are stale.**
   - `plan.md:38` still says "P07 DONE; next P08".
   - `:48`, the VM line, is from P06b.
   - `:49` lists fork SHAs 89d45afb, e5b02094 and e5ad09d4, which are the P06b pins and have been stale since P07.
   - `:50` says "m10-cp2 (none)".
   - The phase table row `:78` says P08 is "pending".
4. **The journal's Codex fix list misses two commits.** Run 1's watchdog latch fix (4111713) and its `nist_run` fix (1a4e528) are missing from "The fixes are dc0cf0b, ea8b681, …" (journal `:85-86`).
5. **The runner smoke has no retained evidence.**
   - The pre-chain M6 smoke ran at 02:17Z on the pre-revert overlay (`ubuntu24.1793829629`). Its run dir was `~/.cache/ns-o-ran-runner-smoke/`, which has since been removed.
   - Its only record is `runner-smoke-m6.log` in the volatile session scratchpad.
   - Copy that log into `evidence/cp2-chain/dd27868/` and cite it.
6. **Two counsel conditions were relaxed.**
   - kongming-261105-1050 made "/home ≥ 80 GiB" a launch condition (its Q5 step 6), and the chain launched at 79. Record this as a 1 GiB deviation that the controller accepted (projected minimum about 55 GiB against the 22 GiB trip). Do not call it a "rule of thumb", as the journal does at `:90`.
   - The same counsel asked for the driver's sha256 in the tsv, and it was not logged. Provenance holds anyway: the committed driver at dd27868 is unchanged at HEAD, and its body is parsed whole. Disclose it.
7. **The phase exit entry is missing.** Add the disk figures (/home 56.9 GiB, /mnt/data 6.24 GiB) and the projection against T′.

### A3. Scope guard

- **Ledger row before a changed predicate:** held (A2).
- **No T-C code before `m10-cp2`:** held.
  - `scripts/` is unchanged from 0d32a88 to 23cdb3e, and no P6, P7, P9, P15 or UseIdealRrc file changed in the harness.
  - On GitHub, every fork's branch head equals its cp2 pin, so nothing beyond the pins is pushed.
- **Tags never moved:** held.
  - `m10-cp1` → 83443e1, locally and on origin.
  - The fork `m10-cp1` tags peel to the cp1 pins in `83443e1:scripts/pins.conf`: 809fb2d, 48d41a5, b2342c6 and 2209995a.
- **No secrets in the tree:** held.
  - P08's diff of `plans/` and `scripts/` contains no token-shaped string (40+ mixed characters) and no kubeadm-token pattern.
  - Every step's scrub ran: 17 steps redacted nothing, and M5, R0 and e2i redacted 1, 6 and 3 files.
  - No `agent-image.env` is in P08's committed layer.
- **No VM prune; D-06b-1 stays in P10:** held.
- **Failure Protocol:** red #1 had its consult (kongming-261105-1050) before its fix, and no second red occurred.

### A4. Verdict: GO-WITH-CHANGES

Required, host-only, before the `PAUSE A′` line:
1. Update the `plan.md` resume card, the phase table row P08 ("done 2026-11-05, m10-cp2 = dd27868"), and the pins, tags, VM and disk lines.
2. In `phase-08`:
   - add dated notes on Validation `:53` and `:56`;
   - write the exit entry: disk, projection, the runner-smoke log location, the 79 GiB launch deviation, and the driver sha256 that was not logged.
   Change `phase-11:52` to `^{commit}`.
3. Add a dated note to row 136: the meid path can only fail, the eNB form is not implemented, and T is not reused.
4. Apply the journal fixes in section B. Then commit and push the journal with this report.

## B. Stop A′ note

### B1. Is the packet complete and correctly classed?

#### I-1 mapping, cross-checked against `phase-07:139-141` and `plan.md:253`

The journal follows row 141: "the MN's admission and X2 `McHandoverRequest` to the source SN ≈ steps 2/3 and 6". Plan I-1 maps `McHandoverRequest` only to step 6, and calls ns-3's SN↔SN leg not message by message. The two disagree. The ns-3 code at the pin supports plan I-1, with one refinement:
1. **Step 1.** `mmwave-enb-net-device.cc:1541-1554`: the source en-gNB calls `master->ApplyExternalHandover` in process. This ≈ step 1, and the journal is right here.
2. **The MN's checks and the request to the source SN.** `lte-enb-rrc.cc:4570-4619`:
   - The MN runs local checks: the UE is known, the target is known, the UE is not in a handover, not already on the target, and not on LTE. No §10.5.1 message corresponds to these checks.
   - It then calls `SendMcHandoverRequest` with `oldCellId = sourceCellId`.
   - `epc-x2.cc:1345-1360` sends that message on the source cell's X2 socket. Its direction, MN → S-SN, matches SgNB Change Confirm (step 6). But it comes before the target's admission, not after the RRC reconfiguration.
3. **The target's admission is SN↔SN.** `lte-enb-rrc.cc:5150-5157` with `:774`: the source SN answers with `SendHandoverRequest`, which sends `UeManager::PrepareHandover`'s X2 HandoverRequest to the target SN. So the admission that steps 2/3 perform between MN and T-SN happens between the two SNs in ns-3.

The journal row "2/3 … The MN runs its existing admission: bookkeeping and the X2 McHandoverRequest leg" therefore names the wrong endpoints. Rewrite the table as follows:

| §10.5.1 step | ns-3 in M10 |
|---|---|
| 1. S-SN → MN: SgNB Change Required | The in-process call (unchanged). |
| (no step) | The MN's local checks: UE known, target known, not in handover, not already on target, not on LTE. |
| 2/3. SgNB Addition Request / Acknowledge (MN ↔ T-SN) | The S-SN → T-SN X2 HandoverRequest / HandoverRequestAck. The function is the same, the endpoints differ (SN↔SN, triggered by the MN). |
| 4/5. RRCConnectionReconfiguration / Complete | ns-3's RRC model. With `UseIdealRrc=true` (`scratch/scenario-zero.cc:492`), RRC delivery is ideal until AC17. |
| 6. SgNB Change Confirm (MN → S-SN) | The MN → S-SN `McHandoverRequest`. Same direction, earlier in the order. |
| Later steps [I]: SgNB Reconfiguration Complete, random access, SN Status Transfer, data forwarding, path update, UE Context Release | ns-3's model, or not modelled. Confirm their numbering against the PDF (`E6VYJPXJ`, pp. 61–62). I could not read the 37.340 text. |

Also:
- Add a dated note to row 141; do not rewrite the row.
- The journal's statement on the observable traces is correct: X2Stats and EnbHandoverStartStats are in the digest and literal-equal at δ 0.
- The class is correct: this is a disclosure.

#### Budget, checked against the run dirs' `host-disk.tsv`

Per-step growth, as allocated overlay GiB / /home GiB:

| Steps | Growth |
|---|---|
| M2 | 3/3 |
| M3 | 12/12 |
| M4 | 3/3 |
| M5, M6 | 0/0 |
| M7 | 0/1 |
| I0 | 3/2 |
| Q8 | 0/1 |
| R3′ dryrun | 1/0 |
| All others (R0, R1, I2, R2 C1, R3′ calibrate, the three R3′ C1s, e2i, seam smoke, R1 C1) | 0/0 |

- **Totals:** overlay 1 → 23 GiB, /home 79 → 55 GiB. The journal's list and its 22 and 24 GiB totals are right. "M7 0–1" mixes the two columns.
- **Wall time:** 16,929 s is the sum of each step's start to its gate exit. End to end, the chain took 17,080 s (02:21:57–07:06:37). The difference is immaterial.
- **Arithmetic:** correct.
  - T′_method = 92 + N_new = 93–95 GiB.
  - T′_measured′ = 37 + 16 + 24 + N_new = 78–80 GiB.
  - Reachable /home after a revert = 57 + 23 = 80 GiB.

Four statements are optimistic:

1. **T′_measured′ is a warm lower bound.**
   - The 24 GiB was measured from `f7-rerun-green`, whose base already holds the RIC, the images and the build caches. The end run starts from `fresh-install`.
   - M9's cold m3 grew 20 GiB; this chain's M3 grew 12.
   - Take the larger of M9 and this chain for each step: m0 3, m1 13, m2 3, m3 20, m4 3, m7 1, i0 3, r1 1, r3p 1, which sums to 48. That gives T′_measured′ ≈ 37 + 48 + N_new ≈ 86–88 GiB.
   - Present measured′ as 78–88 GiB, with cold m3 as the swing term. P11's cold m3 rehearsal settles it (S5).
   - "About 0 shortfall under the measured base" should read "0 to about 8 GiB".
2. **Reachable /home shrinks before Stop B.**
   - Raw evidence stays in the worktree on /home. This plan's `evidence/` is 9.6 GB today, and each full chain adds about 1.8 GB of raw files.
   - P09–P11 should add about 7–9 GB [I]. Reachable /home at Stop B is then about 71–73 GiB, unless the user rules that archived raw evidence may leave /home.
   - The shortfall then becomes about 20–24 GiB under the method base and about 5–17 GiB under measured′.
   - Tell the user now to expect to free 10–25 GiB at Stop B.
3. **/mnt/data has 6.24 GiB, not 7.**
   - `df -BG` rounds up. The resume card said 6.5 GiB at P07's exit, and the p08a and p08b archives have since taken about 240 MB (103 + 138 MB).
   - M10's phase archives have been 31–179 MB each. Projected: P09 about 0.06 GB, P10 0.15, P11 0.3–0.4, and the end run 0.45, about 1.0 GB in total.
   - That leaves about 5.2 GiB at the end run, before any growth of podman storage, which is on the same disk. That is at the 5 GiB floor, so PAUSE T2 is likely during P11 or the end run.
   - Only the user can free storage that this plan did not create, so this needs a question (B2).
4. **The T-C cost is not re-projected.** The journal copies "6–8 h" from `phase-11:61`. With this chain's unit costs [I]:
   - **The prefix** through I2 from `f7-rerun-green` is 8,602 s (2.4 h) and 22 GiB.
   - **P10** ≈ 6.5–8 h and ≈ 46 GiB from one revert (80 → 34 GiB, above the 22 GiB trip). It consists of:
     - the prefix;
     - P6, P7, P9 and UseIdealRrc, each an M4 rebuild (1,281 s, 3 GiB) plus the required M6 and M7 regression;
     - P15 with D-06b-1: M5 (245 s), M3 (2,181 s, 12 GiB), M6, M7, p12 and an R3′ single run.
   - **P11** ≈ 11–14 h, with at least two reverts. It consists of:
     - the prefix;
     - about 4 bisection points, each a rebuild plus a C1 of about 1,370–1,400 s (0.75–1.05 h each);
     - the final C1 and the four δ C1s (1.9 h);
     - the rehearsals (about 1.7 h);
     - cold i0, i2 and m3 from `fresh-install` (2–2.5 h, about 35–40 GiB, on their own revert).
   - **P09** ≈ 4–5 h and about 24 GiB: the prefix, the p12 baseline and 2–3 s10 runs.
   - **In total,** about 22–27 h of VM wall time remain before Stop B, without reds.
   - **The revert arithmetic.** "57 − 24 − 24 = 9" starts from today's unreverted 57 GiB. From a revert, 80 − 24 − 24 = 32 ≥ 22, so two full chains fit per revert and a third does not. Plan P11's revert points on that basis.

#### Questions and their defaults

Q1, Q3, Q4, Q5, Q6 and Q8b state a default. Q2, Q7 and Q8a do not.

### B2. Class errors and missing items

**Reclassify:**
- **Q6 (ratify P08 red #1) becomes a disclosure.** P08 closed green, and the classification changes nothing either way. Reds are classified by the controller with kongming under the plan's Failure Protocol. Keep the sentence "you may rule it a non-red; nothing changes".
- **Q8b (frozen checkout for `run-to-m9.sh` and the M10 runner) becomes a disclosure and a P12 hand-off.** It is additive ops hardening within the existing scope, and it gets its own ledger row (kongming-261105-1050 already recommended it).
- **The unresolved "T′ base" line becomes a disclosure.** Stop A ruling S5 already decided it: the base is ruled at Stop B from P11's measurements. Add that the 24 GiB is a warm lower bound.

**Keep these as questions, and add defaults:**
- **Q2: default "confirm rows 106, 120 and 121 as registered".** Give one line per row in the journal (old → new, and why it is not weaker). The user cannot confirm a row's content from a line reference.
- **Q7: default "accept 'unverified against Zotero' now".** AC20 allows it. Add 3GPP TS 38.101-1, 36.101 and 36.104 before the P13 records.
- **Q8a: default as in kongming-261105-1050.**
  - A finding blocks the next chain only if, on a realistic path, it can turn a clean run red, turn a red run green, or lose a red run's evidence.
  - Other findings get a ledger note and a fix after the chain, in the same phase, each with its follow-up Codex review, so the 10:38 ruling stands.
  - No harness commit lands while a chain is running.

**Add:**
- **Q9 (new): /mnt/data headroom.**
  - Default: the user frees at least 5 GiB on /mnt/data before P10, or names another target for the archives.
  - Only the user knows which podman images and volumes there are safe to remove (86 GB and 211 GB are shown as reclaimable).
  - Without this, expect PAUSE T2 around P11 or the end run.

**Missing disclosures:**
- **P06b's two step deviations** (`phase-06b:159-160`):
  - step 2's local proof ran after M4–M7, on the VM;
  - step 5 used the full r3p single gate.
- **The e2i association mapping, now resolved in P07** (`phase-06b:167`). Both P06b items were promised for Stop A′ at `phase-06b:171`.
- **p12 has not run since the P06b pins** (B3).
- **The meid fail-closed path** (A2, finding 1).
- **The runner smoke log's location, and the driver sha256 that was not logged** (A2, findings 5 and 6).
- **P4-KPM's status.** `phase-06b:85` promised to report P4-KPM at Stop A′ as fixed, with D-06b-1 as its one scheduled residual. The journal does not say this. Its alternative, "require it before cp2", lapsed when cp2 was tagged. Optionally, add a P1–P13/N5 status table at cp2.

Apart from these items, every question and disclosure on kongming-261105-0536's lists is present.

### B3. Recommendations

**On each question:**
1. **R-4: accept.**
   - AC14 and AC14b concern where the UE ID comes from. The ID bytes equal the Influx tag through an exact-tag filter.
   - Row 125's negative makes that dependency falsifiable on the wire in every R2 and R3′ run.
   - R-4 as written would need a kpimon node tag and a TS xApp rewrite, for no contract gain.
   - State in the AC20 run report how AC14b holds: the ID is confirmed in Influx and parsed from the tag, and the serving cell comes from the QP answer.
2. **Rows 106, 120 and 121: confirm.** They implement G1, R6/R7 and the approved N5 key. They were registered before their code and passed again in the uniform chain (seam smoke 32/32, e2i).
3. **Prune: ratify, narrowly.**
   - Allow only `docker image prune -f`: dangling images only, never `-a`, never a tagged image, and never during a gate.
   - Log `docker system df` before and after, with the removed image IDs.
   - Prune only when the guest root passes 75 %.
   - P10 rebuilds ns-3, the agent and kpimon. Without a ruling, row 131's 85 % guard could stop a build in the middle of the phase.
4. **`ns3.imsi`: keep it through M10.**
   - Removing it changes the KPM content, needs an amendment, and needs a cp3 attribution.
   - P10's lint classifies the `ns3.*` measurements as vendor measurements.
   - Disclose it in the run report.
5. **D-06b-1: fix it in P10, at its own commit, with row 81's amendment first.**
   - Do not squash it into P15. That way P11's bisection can attribute it as a T-A residual.
   - Nothing in P09 depends on it.
6. **Red #1:** this is now a disclosure. If the user wants a ruling, ratify the classification.
7. **Zotero:** accept "unverified" now, and add the three documents before P13.
8. **Codex and the runner.**
   - **8a:** adopt the triage rule from kongming-261105-1050.
   - **8b:** yes, as a P12 ledger row.
9. **/mnt/data:** free at least 5 GiB before P10.

**Before P09 (scale):**
- **Run p12 at the cp2 pins** right after the prefix.
  - p12 last passed at P06b's pins: `p12/20261104T104145Z`, harness 28d4508, Testbed 89d45af, ns-3 e5b02094.
  - P07 changed the per-seq context that p12's 10-record indications use. This run re-proves AC10 before any T-C code.
  - It also gives P11 the baseline it needs to attribute P15's change.
- **Use the same safeguards as P08:** reuse the frozen-checkout driver and the 22 GiB watchdog, and start from a revert (80 GiB).
- **Cells 10 and 11 bring the first live hex letters in the IDs** (`en_gnb_001_001_0000000a`, key `0000000A10`).
  - The replay models the TS xApp as upper-casing the meid suffix (`replay-ts-cell-map.py:11,61`), but no live run has exercised it.
  - Dry-run the replay on a synthetic 10-gNB e2mgr record first.
- **Record that the 60 s Influx window holds** at s10's report rate (kongming-261105-0536).
- **Steer one UE to a cell ≥ 10.** AC15 needs an applied PSCell change to such a cell, so the scenario must include one.

**Before P10 (T-C):**
- **Land one fix per commit:** P6, P7, P9, P15, D-06b-1 and UseIdealRrc. P11's bisection depends on it.
- **P9 is the fix most likely to move R3′'s predictor answers,** and possibly its decision (open point 2). A run without a predictor-driven handover is a red, and a scenario change is PAUSE T3.
- **P15's per-cell Format 1 actions will probably change kpm-headers and collet-start-time.** Expect both in the cp3 diff.
- **The UseIdealRrc=false probe may fail.** S-R is pre-approved for that case.
- **Have the Q3 and Q9 rulings in hand before P10 starts.**
- **P11's cp2 baseline can be rebuilt from git.** The compare proved that cp2 equals T(M9 reference) at δ 0, and T(cp1 δ reference) at 150 and 500. P11's diff can therefore use T(reference) as cp2 without the raw archive.

## What to avoid

- Re-running any VM step to "complete" P08. The evidence is sufficient.
- Rewriting rows 136 or 141, or touching the tag. Append dated notes only.
- Telling the user "about 0 shortfall under the measured base", or "7 GiB" on /mnt/data.
- Starting P10 before the Q3 and Q9 rulings.
- Freeing anything on /mnt/data or /home autonomously.
- Squashing T-C fixes into fewer commits.

## Assumptions

| Assumption | Confidence | What would change the answer |
|---|---|---|
| The worktree's raw files are the ones archived and hashed (the p08b archive is verified, with 5,682 entries) | High | A mismatch would make my offline reads non-authoritative. |
| M9's per-step growth from `fresh-install` (m3 20 GiB) is the right cold proxy for M10's m3 | Medium | P11's cold m3 rehearsal replaces it. |
| Steps 7 onwards of Figure 10.5.1-2 are as I listed them | Medium-low (I could not read the PDF; the vault search found no 37.340 cache) | The PDF read at `E6VYJPXJ` pp. 61–62. |
| The phase costs (P09 4–5 h, P10 6.5–8 h, P11 11–14 h) and raw-evidence growth (7–9 GB) | Medium [I] | Actual runs. Reds add a prefix (2.4 h) each. |
| /mnt/data archive growth of about 1.0 GB to the end run | Medium | Larger P11 rehearsal sets or podman pulls make it worse. |
| P07's per-seq context change touches p12's multi-record encoding | Medium-high (phase-06b finding 3 names that path) | A green p12 at the cp2 pins makes it moot. |

## Unresolved questions

1. **User, at Stop A′:**
   - Q1 R-4 (accept);
   - Q2 rows 106, 120 and 121 (confirm);
   - Q3 the prune rule (ratify, narrowly);
   - Q4 `ns3.imsi` (keep);
   - Q5 D-06b-1 (P10, at its own commit);
   - Q7 Zotero (unverified now, add the documents before P13);
   - Q8a Codex triage (the kongming-261105-1050 rule);
   - new Q9: /mnt/data headroom (free at least 5 GiB before P10).
2. **Controller:** confirm the steps after step 6 of Figure 10.5.1-2 from the PDF before the I-1 table goes to the user.
3. **Controller:** are M10's m2 and m4 growth (3 GiB each here, against 0 and 1 in M9) real cold costs, or artefacts of the warm base? P11's cold rehearsals answer this.

Status: DONE_WITH_CONCERNS
Summary: P08 is GO-WITH-CHANGES. AC8b, G2 and every Validation bullet hold on the committed evidence, no check was weakened, and the tags are correct; the required changes are record-only. The Stop A′ packet needs three fixes before it goes to the user:
- the I-1 steps 2/3 mapping;
- an honest budget: /mnt/data 6.24 GiB reaching the floor, T′_measured′ 78–88 GiB, P11 about 11–14 h;
- question hygiene: three missing defaults, two reclassifications and a new /mnt/data question.
P09 should run p12 at the cp2 pins first.

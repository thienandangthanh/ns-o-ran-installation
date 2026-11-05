# P09 exit review (scale gate, AC15)

Date: 2026-11-06 ~04:40 KST (Asia/Seoul). Reviewer: kongming, advisory only. Runtime: Claude Code subagent on Opus 5.5 (`model: opus`, per the user's CLAUDE.md override of the `fable` routing).

**Scope.** Harness HEAD `3558b86` (last script change `510ae30`). Pins (cp2): Testbed `554d6d6`, ns-3 `ea6e46f6`, oran-interface `53253fe`, e2sim `e2705816`.

**Method.** No VM, virsh or Codex call. On the host I:
- re-read both s10 verdicts, `checks.jsonl`, `checks/*.out` and the judge outputs under `runs/live1/s10/` (neighbours, influx-vs-trace per node, cellmap-replay, influx-window, e2mgr records);
- re-read the p12 verdict at 673fe7b and the three chain tsv files and driver copies;
- diffed `6e157ffa..19f6ec9e` and `19f6ec9e..510ae308`, read `write-verdict.py`, `check-s10-neighbours.py`, `s10-scenario.json` and the TS patch `ts_xapp.cpp.style5_en_gnb_ueid.patch`;
- read the ns-3 loop at the pinned `ea6e46f6`, derived the libstdc++ behaviour, and tested the prediction on r2 live1's IPC trace;
- recomputed per-step disk from every `host-disk.tsv` and p12's watchdog `free-series.tsv`; ran `df` and `du` on the host.

## Verdict: GO-WITH-CHANGES

- AC15 is met on the gate of record `s10/20261105T184211Z`, and every extra P09 exit item is met. I checked non-vacuity in the judge outputs, not in the summary (table 1).
- No check was weakened, and no predicate changed without a prior ledger row. The required changes are record-only (section 6). No step needs a re-run at 510ae30.
- Two findings need the user before P11, not at Stop B. The first is the ns-3 neighbour-loop bug (section 5). The second is optional: AC15's "TS xApp's cell map" conjunct rests on a replay model, not on live TS behaviour (section 2).
- **P10 does not fit one revert.** The P08 estimate of 46 GiB predates ruling 1 and D-R3-1, and p12 measured 8 GiB per run. Plan two revert cycles before the first P10 chain (section 7.1).

## 1. Exit gate (Q1)

| Item | What I checked | Status |
|---|---|---|
| `agentsConnected == 11` | `runs/live1/s10/agents.json`: the e2mgr CONNECTED set equals the 11 expected meids, including `…_0000000a` and `…_0000000b`. Every agent is READY with one setup. | met |
| `influxEqualsIpc` (every node, every seq) | `influx-vs-trace-{1..11}.json`: 80/80 samples complete on each node, 0 fields differ (e.g. node 1: 40,930 fields compared; node 11: 18,228), 0 duplicate keys, 0 `ueId` mismatches. Node 10 has 207 UE rows and node 11 has 266, which shows the two handed-over UEs arriving. | met |
| > 8 measured, exactly 8 decoded | `neighbours.json`: `measuredHistogram {9: 2338}`, `decodedHistogram {8: 2370}`, 0 short, 0 over the cap, 0 malformed. The decoded side is kpimon's library run on the capture (wire), and the measured side is ns-3's `MmWaveSinrTime.txt` (1.5 M rows). The 32 unjudged ticks are 30 first ticks plus 2 handover ticks, which the membership rule excludes by design. | met, non-vacuous |
| `cellIdsGe10InKpm ⊇ {10, 11}` | From three decoded sources: Format 1 `nodeId`, `servCellId` and the neighbour cellIds. | met |
| `tsCellMapKeysGe10 ⊇ {10, 11}` | `replay-ts-cell-map.py` run on the e2mgr records saved after the TS restart gives `0000000A10` and `0000000B10`, with no wrong-node key. This is a model of the TS parser, not live TS behaviour (section 2). | met as pre-registered |
| `appliedPscellChangesToGe10 ≥ 1` | 2 changes, checked on the ledger, the wire and the ns-3 trace: 2 applied lines via 2, 2 acked Style 5 action 3 requests with targets `0000000A10`/`0000000B10`, the c9 handover rows, and KPM UE lists that move. | met |
| `stepWallS ≤ 2700` | 1,869 s in the gate; 1,921 s on the host from the unit start to the end of the copy. | met |
| `s10_e2ap_ppid70_every_node` | `--node-ips` with 11 distinct IPs; every association carries only PPID 70 (246–1,262 chunks per node). | met |
| p12 at the cp2 pins | `p12/20261105T172146Z` (673fe7b) PASS, 57/57 checks: 20 indications × 10 records, 14,694 fields equal to IPC, a decoded `ricRequest:eventTriggerNotSupported` failure for P = 150, and 100/100 restored on the wire. | met, non-vacuous |
| 60 s Influx window | `influx-window.json`: the latest row was 0.15–0.17 s old at each trigger. | recorded |
| Step-2 budget | 177.2 wall s per sim s (AC6b: 171). VM root +0.23 GiB, evidence 189 MB, watchdog minimum 42 GiB. The dev and gate runs are deterministic: `MmWaveSinrTime.txt` is byte-equal and all AC15 facts are equal. | recorded |

## 2. Scope guard and AC18 (Q2)

- **Contract.** There is no divergence from AC15, plan R-1 or the scope guard. Rows 145 (e0e5e40, 00:49) and 146 (8ddfb92, 02:56) were committed before their code (19f6ec9, 3cad432).
- **Nothing weakened.**
  - `write-verdict.py` is stricter on the normal path (`pass is True`) and identical for boolean records.
  - The `ts-rung-lib.sh` defaults keep n = 3 and 180 s.
  - s10 adds its own port check instead of widening the shared predicates.
  - The lint change (389732b, 60 → 180 s) is a bound in an offline tool that no gate runs, so it needs no row.
- **Record drifts (fixed in section 6):**
  - Row 146 still describes `systemctl is-active`. In 510ae30 the stop must instead succeed and `ActiveState` must be inactive or failed, which is stricter. The amendment and the code (3746e9a, 7456d71) share one commit second.
  - The phase Design (`phase-09:16`) names "the R3′ predictor". s10 instead uses the TS xApp with the stub QP and authored answers. That choice was pre-registered in `s10-scenario.json` before the first run, and AC15 does not require the predictor.
  - The P09 standards ledger (`phase-09:37-41`) is still "to cite".
- **Evidence class of the TS cell-map conjunct.**
  - The cp2 TS xApp looks up only the **serving** key in `cell_map` (`O-RAN-Testbed-Automation/…/xApps/ts/src/ts_xapp/ts_xapp.cpp.style5_en_gnb_ueid.patch:129`). It passes the target key through unchecked.
  - `excludeServing [10, 11]` (`s10-scenario.json:16`) keeps every live lookup on cells below 10.
  - So no live TS xApp has yet resolved a hex-letter key, which was P08 hand-off item 3. The conjunct rests on the replay of the e2mgr records, which matches what was pre-registered and judges on e2mgr records, not xApp logs. It is acceptable, but it should be disclosed.
  - A cheap strengthening without a T3 is in section 7.4 (row 139).

## 3. Harness spread (Q3)

The spread is acceptable, and nothing needs a re-run at 510ae30 before P10.
- Between 673fe7b and 510ae30, the code that the prefix and p12 executed differs only in four places:
  1. the verdict writer, moved and shown byte-equal on the p12, r0, m7 and i2 run dirs;
  2. vm-exec's timeout branch, which never fired;
  3. the `ts-rung-lib.sh` defaults, which are identical;
  4. lint, which does not run on the VM.
- The gate of record is at the latest SHA, and the forks are at the cp2 pins in every verdict.
- AC19 requires a single SHA only for the M10 run, and P11 re-runs the whole set at cp3.
- No harness commit landed while a step was running. b3bf4b1 (03:42:22) is plans-only and landed 11 s into the gate of record, under a frozen checkout.

## 4. Codex triage, runs 2–6 (Q4)

Nothing was triaged in a way that caused harm.
- **Run 2** was treated as blocking. By ruling 7 it was not: a run longer than 3,600 s already fails `stepWallS ≤ 2700`, so only `verdict.json` was at stake, the same class as run 3. Over-triage is harmless.
- **Runs 3–5** were triaged correctly. Exit code 124 and the driver's rc 97 keep a stopped run red, so none of them could turn a run green.
- **Residual introduced by 7456d71/510ae30.** When the stop cannot be confirmed after 5 tries, vm-exec now dies **without copying** the evidence (`scripts/vm/vm-exec.sh`, the `else die` branch). Before these commits it always copied.
  - In dev chains the evidence stays on the VM until the next revert. In the M10 runner, a later revert would lose it.
  - The path is rare and the run stays red. Handed to P12 in section 8.
- **Open.** 510ae30 was committed at 03:40:27, and the gate of record started at 03:42:11. Confirm that run 6 reviewed exactly those bytes (Unresolved 3).

## 5. The ns-3 neighbour-loop UB (Q5)

**Verified, with a narrower condition than the phase file states.**
- In libstdc++, `--begin()` returns `begin()` only when the tree's root is its leftmost node. That requires 2 or fewer entries; otherwise `--begin()` returns `end()` and the loop is correct.
- `flip_map` (`mmwave-enb-net-device.cc:891-895`) inserts in ascending cellId. So in a 2-entry map the lower cellId is the root, and it is leftmost exactly when the higher cellId has the higher SINR. The loop at `:1001-1003` then visits only the strongest entry.
- **The neighbour is dropped iff the serving cell is the higher cellId of the two and the strongest.** In r2 live1 (`evidence/r2/20261105T044701Z`, IPC `cuCp.l3.neigh`):
  - node 2 reports its neighbour in all 416 UE ticks, including the 273 where node 2 is the stronger cell;
  - node 3 drops it in 82 of its 178 UE ticks.
  - So `phase-09:92` ("serving cell is the strongest → drops"; "predicts all 594 blocks that decode 0") is wrong. The rule matches 594 of 594 blocks, of which 82 decode 0.
- **Where it shows.**
  - The lists are in the IPC sample lines, so they are in the literal **ipc** component of every 2-gNB reference (M9, cp1, cp2, the δ references), and in KPM and Influx.
  - No gate predicate reads them except s10's, which is safe because every s10 map has ≥ 3 entries.
  - The R3′ predictor reads `DRB.PdcpSduVolumeDL`, not the neighbour lists.
- **Timing of the decision: Stop B is too late.**
  - Stop B comes after cp3 is tagged. A fix then would need new references and a new tag, and tags never move, so deferring to Stop B quietly decides "not in M10".
  - The cheap window is P10: one ns-3 commit plus an attribution line in P11's diff. AC16 requires every changed component to be explained by a T-C fix, so a fix needs contract Amendment 4 first.
  - Ask the user now, as a non-blocking question. D-R3-1 does not depend on it. The answer is needed before P10's first ns-3 commit (P6), and at the latest before P11 banks references.
  - My recommendation is to fix it. The marginal cost is small, and it removes an artefact in the KPM of every 2-gNB rung that depends on cellId order.
  - If the user does not answer, the default is disclose-only, because the scope guard forbids self-expansion.

## 6. Required changes (record-only; no re-run)

1. **`phase-09-scale-gate-ten-gnbs.md:92`.** Restate the UB condition as in section 5 (higher cellId and strongest; 82 of 594 r2 live1 blocks; node 2 unaffected; the ipc component is affected). Replace "listed for the user at Stop B" with a user question to be decided before P6 (P10) or, at the latest, before P11.
2. **`check-diff-ledger.md:152` (row 146).** Add a note that 510ae30 replaced the `systemctl is-active` test with "the stop succeeds and `ActiveState` ∈ {inactive, failed}", which is stricter. Note also that the amendment followed the code, that 3746e9a and 7456d71 share one commit second, and that the unconfirmed-stop path leaves the evidence on the VM.
3. **`phase-09…:16` and the gate-of-record entry.** Record that the trigger path is the TS xApp with the stub QP and authored answers, pre-registered in `s10-scenario.json` (19f6ec9) before the first run. Record that `tsCellMapKeysGe10` is replay evidence and that no live hex-letter lookup occurred (section 2).
4. **`phase-09…:37-41` standards ledger.** Fill both rows. The neighbour cap is an ns-3 model limit (`mmwave-enb-net-device.h:71`) on vendor `ns3.l3.nbr*` names, not a KPM v03.00 clause. Say so, or mark the row "unverified against Zotero". Take the E2SM-RC §8.4.6.3 citation from P07's ledger.
5. **`phase-09…:91` (lint).** Correct "passes alone": per 389732b the self-test takes about 62 s on an idle host. Record a `lint.sh` run at 510ae30 with its result. The phase promised one, and none is recorded.
6. **Plan budget line and resume card.** Record the measured unit costs:
   - prefix M2–I2 24 GiB (78 → 54), of which M3 is 15;
   - p12 8 GiB per run, from three kpimon installs, with a maximum 370 s burst of 3 GiB (below h = 12);
   - s10 0.25 GiB;
   - 2.2 GiB per frozen checkout.
   These feed T′_measured′ at Stop B. Mark P09 done in the phase table.

## 7. Hand-offs for P10 (Q6)

### 7.1 Disk and wall projection
- **Starting point.**
  - Now: /home has 42 GiB free, the active overlay `ubuntu24.1793890803` holds 31 GiB, and the three locked frozen checkouts hold 6.6 GiB. /mnt/data has 18 GiB free (floor 5), which meets ruling 8; re-read it at the P10 start.
  - After `git worktree unlock` + `remove` of the three checkouts and a revert to `f7-rerun-green`, expect about 77–80 GiB. Run `vm-orphan-overlays.sh` after the revert.
  - About 57 GiB is then usable before the 22 GiB watchdog.
- **Demand [I, from the P08 and P09 unit costs]:**
  - prefix 24;
  - D-R3-1 about 1;
  - P6, P7, P9 together 4–10;
  - P15 about 12 (p12 8 + kpimon 3 + R3′ 1);
  - D-06b-1 4–6;
  - kpimon node tag about 11 (kpimon + p12);
  - TS serving cell 3–4;
  - UseIdealRrc about 4;
  - 2.2 per gated SHA if checkouts are kept.

  That totals about 67–80 GiB, which does not fit.
- **Recommendation: two cycles, with the revert between P15 and D-06b-1.**
  - Cycle 1 is the prefix + D-R3-1 + P6 + P7 + P9 + P15, ending at about 33–39 GiB.
  - Cycle 2 is a prefix at the P15 pins + D-06b-1 + kpimon tag + TS + UseIdealRrc + a 10-gNB rate check, ending at about 30–34 GiB.
  - Rule: never start a p12 or an xApp or kpimon build below 34 GiB free (22 + h); revert first.
  - Remove each frozen checkout once its step's evidence is committed.
- **Wall.** P08's 6.5–8 h, plus 1.5–2 h for ruling 1, plus one more prefix (about 2.4 h), plus D-R3-1's e2i and M5–M7 (about 40 min): about 11–13 h.

### 7.2 Gates per commit (phase-10 plus this review)
| Commit | Gates |
|---|---|
| D-R3-1 pair | agent build (codec bytes), lint (e2i self-test, replay self-test on the regenerated `FIXTURE_HEX`), live e2i. **Add M5–M7.** The plan invariant "M5–M7 re-pass after every agent change" (`plan.md:71,343`) conflicts with `phase-10:76`'s "covered by P11"; run them or record the deviation. |
| P6 | metric-map lint (clause column), M4, M6, M7 |
| P7 | unit tests (a)–(c), M4, M6, M7, trace header check |
| P9 | M4, `check-pdcp-volume-totals.py`, R3′ single (a predictor-driven handover is required; a scenario change is T3) |
| P15 | M5, kpimon rebuild, M6, M7, re-baselined p12, R3′ single |
| D-06b-1 | row 81 amended first; M4, M5, kpimon, M6, M7 |
| kpimon node tag | kpimon rebuild, M6, M7, p12 (row 137) |
| TS serving cell | unit test (row 139), lint (rows 138, 140), R2 single (row 141), R3′ single (row 142) |
| UseIdealRrc | probe run; if adopted: M4, M5–M7, R3′ single, and the 10-gNB wall rate (7.3 item 5) |

### 7.3 Ordering hazards
1. **Pin bumps and predicate changes are atomic.**
   - Row 143 fails on the old Testbed pin, and row 141 fails with the old TS xApp.
   - Each harness commit carries its pin bump, so no chain ever runs at a mixed state.
2. **The kpimon patch stack.**
   - P15, D-06b-1 (the tag formatter in `control.go.ue-id-tag.patch`) and the node tag all touch kpimon's `control.go`.
   - Generate each patch against the exact preceding manifest state, and place the node-tag patch last. Read "after `ue-id-tag`" as "anywhere after", not "immediately after".
   - After any edit of an earlier patch, regenerate the later ones. The `patchset.sha256` guard catches a stale image but not a fuzzy apply.
3. **P15 replaces row 100's predicate at 8 sites:**
   - `m6`, `m7`, `r0`, `r1`, `p12` a and c, `e2i`;
   - `ts-rung-lib.sh:85`, which covers r2, r3p and **s10**.
   - Register those rows before P15 code, in a docs commit and not in the same commit (`phase-10:66` puts the p12 row "in the same commit"; history must show the row first).
4. **UseIdealRrc may move I-2's c.** R-1 asserts HandoverStart − apply = c (`plan.md:160,280`). [Speculative: real RRC may change c or make it vary.]
   - Register before that commit how c is judged at cp3.
   - Make the probe record HandoverStart − apply for every applied line.
5. **The s10 wall at cp3.**
   - P7 and UseIdealRrc may slow ns-3. 1,869 s against 2,700 s leaves 30 % headroom.
   - Measure the 10-gNB rate after the UseIdealRrc commit (s10 `--dev` or the AC6b probe), so that any simTime change (T3) is ruled before P11 and not inside the cp3 chain.
6. **D-R3-1's new X2 bytes.** The TS cell map is a substring search for the gNB-ID hex in the X2 hex. Row 144 proves "no spurious key" only for gNBs 2 and 3. Run the replay offline with synthetic records for IDs 2–11 at the new constants before any cp3 s10.
7. **The UB fix, if the user rules it.** It needs Amendment 4, its own commit (best right after D-R3-1, before P6, so P6's M6 and M7 cover it), a slot in P11's bisection list, and a ledger row with a non-vacuous check.
   - The check: in r2 and r3p, every UE tick whose node's map holds 2 cells reports exactly 1 neighbour.
   - A fixture that decodes 0 neighbours must fail.

### 7.4 Register before code (controller)
- The revert plan from 7.1, in phase-10.
- The P15 rows from 7.3 item 3.
- The rows for P6, P7 and P9, and P7's SN width from 3GPP TS 38.323.
- The judgement of c (7.3 item 4).
- The M5–M7 disposition at D-R3-1.
- Optional, and additive: amend row 139 with a hex-letter node (`en_gnb_001_001_0000000a` → `0000000A10`/`0000000A00`), ideally built from s10's saved `e2mgr-node-10.json`. The TS C++ path then gets a hex-letter test without a T3 change to s10.

## 8. Hand-offs for P11, P12 and Stop B
- **P12.** The M10 runner must not revert or destroy the VM after a step that died with "evidence NOT copied". It should first try a best-effort copy marked "unconfirmed". Judge AC15's 45 min on the host-side step wall: 1,921 s here, against the gate's own 1,869 s.
- **P11.** Re-run s10 at cp3 with the rate re-measured. Attribute P15's kpm-headers and collet changes, and the UB fix if it is ruled.
- **Stop B.** p12 measured 8 GiB and s10 0.25 GiB toward N_new.

## Assumptions
- The revert to `f7-rerun-green` frees the 31 GiB overlay with no revertDisks leak, since no m0 branch runs in dev chains (medium). A leak would leave about 46 GiB and force three cycles.
- The kpimon reinstall costs about 3 GiB, inferred from p12's three installs at about 8 GiB in total (medium). The P10 cycle split depends on it.
- The libstdc++ derivation holds for the VM's GCC. It matches r2's 594 blocks exactly (high).

## Unresolved questions
1. The neighbour-loop UB: should it be fixed in M10 under Amendment 4, or disclosed only? The default is disclose-only. A decision is needed before P10's P6 commit, and at the latest before P11.
2. AC15's TS cell-map conjunct: accept the replay, or add a trigger served by cell 10 or 11 at cp3? The second is a T3 scenario change. The default is to accept the replay and add the row-139 hex-letter test.
3. Did Codex run 6 review exactly the 510ae30 bytes? It was committed 1 min 44 s before the gate of record started.
4. Where should P10's revert go? The default is between P15 and D-06b-1.

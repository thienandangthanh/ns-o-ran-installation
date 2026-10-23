# kongming: P3 (R0) first failed Verify, V7 and V9 verdict fields

Date 2026-10-23 ~16:30 KST. Model: Opus 5.5 (as routed by the caller). Advisory only; never user approval.
Inputs: gate run at harness `aa9317b` (HEAD now `222ad1d`), evidence `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r0/20261023T065551Z/` (pcaps present on the host), `scripts/gates/gate-r0-rc-scripted.sh`, `scripts/gates/rc-lib.sh`, `tools/e2-evidence/wire-c1-extract.py`, `tools/rc-decode/rc-decode.c`, `tools/kpimon-decode-harness/`, `scripts/gates/gate-s1-pacer-lockstep.sh`, `scripts/gates/check-c9-handover-trace.py`, `scripts/gates/digest-run.py`, `scripts/run-to-m9.sh`, and the agent source (local Testbed clone at 725b167, older than pin 4c8397d0; the wire from the pinned agent is the authority).

## TL;DR
- This is a real failed Verify. Fix gate r0 so that every V7/V9 item is a **check** plus a verdict fact, valid in `--mode single` as well. Then run **one full fresh `--mode c1` R0 gate** at the new harness SHA and redo V1 to V9 on its `verdict.json`.
- A post-hoc checker on 065551Z is useful only as a fixture test of the new checks. It cannot serve as the acceptance, for three reasons:
  - V7 and V9 name fields of the gate's own `verdict.json`.
  - Part of the reset evidence was never captured, so it cannot be recomputed.
  - M9 reads only a gate's `pass` and `failed`.
- `kpmUeListMoved` can be decoded, and it is **true** on 065551Z. I checked it post-hoc on all three live runs with host tshark 4.7.4: E2SM-KPM Indication Format 2, `matchingUEidList`, gNB-UEID with `amf-UE-NGAP-ID` = IMSI.
- Two V2/C5 checks are also not what the Verify names:
  - the ACK outcome is compared as the literal `0000`; it is never decoded by the P0 decoder;
  - nothing checks that the answer comes back from the node the request was sent to.
- No T-trigger fires now. T6 fires if the fresh run fails any V.

## Reframed problem
The question is not "which fields are missing". It is "what counts as acceptance evidence for R0". The locked contract judges R0 by the gate's own verdict, produced by the harness SHA it records. M9 later runs the same gate in single mode and trusts only that gate's pass/fail. So the gaps have to be closed in the gate, and the gate has to be shown green once as amended. Requirements:
- no weakening;
- no change to C1's component set;
- no re-use of 065551Z's live runs as the acceptance;
- the per-run reset evidence must work with one live run.

## 1. Q1: post-hoc vs a fresh gate run (verified)
**What 065551Z has and lacks**
- Present: `tCtlSeconds` = 30, with provenance; `q2OutageSwitches` = 5; `c1` all true; `d7`; `ipcDropped` = 0; `minSlack`; exit_code 0.
- `restartCounts`: only the boolean `restartCountsAllZero` exists (gate-r0:315-317). The per-pod data sits in `live*/k9-after-pods.tsv`.
- Route owners:
  - They are suffixed per run, and they come from the **end** dump only. `ROUTE_OWNER_*` is set by the last `rc_route_dump` call (rc-lib.sh:125-129), and the facts are written after the end dump (gate-r0:179-183).
  - The start dumps disagree. At live1's start, rtmgr's last `-1` line pointed to kpimon while e2term's stash pointed to rc; at the end both pointed to rc. That start state is in the check detail only, not in the facts.
- **Not recoverable post-hoc:**
  - The per-run Influx bucket id. `rc_influx_bucket_reset` overwrites one `influx-bucket-id.txt` (rc-lib.sh:165), and `check()` keeps only the last 3 output lines (lib.sh:58). Only k9's id (`25a68c9bf1a5f65e`) survives.
  - Pod and agent start times. `rc_pod_snapshot` never records them (rc-lib.sh:135-146).
- `droppedNoSub` is absent from the verdict. It can be recovered: every `e2-pacing-log.jsonl` step line has `droppedNoSub` 0, in all 7 paced runs (c8null, live1-3, k9, replay, rng2).

**Why a post-hoc checker is not acceptance**
1. V7/V9 say "`verdict.json` has …". Editing 065551Z's verdict breaks its provenance: harness `aa9317b` never wrote those fields. A "supplement" file is not `verdict.json`.
2. Reset evidence (bucket ids, start times) is missing from 065551Z.
3. M9 runs `gate-r0 … --mode single` (run-to-m9.sh:61). `write_verdict` reads only `pass`, `failed` and `pins` (run-to-m9.sh:78-104). Any V9 item that is only a fact, or that lives in a post-hoc script, is invisible to M9, and the new in-gate code would run live for the first time inside the unattended M9.
4. "Never re-run a red C1 to get green" does not apply, because C1 is green. Its discipline still applies: record the cause, commit the change, then run a full fresh set. If that set shows a red C1, it is a red C1. The green 065551Z never overrides it.

**Cost:** about 18 to 21 min of VM time (`duration_s` 1084). It needs no re-calibration: the harness change does not touch timing, and `rung-config.json` already carries the T_ctl provenance that `tctl_ok` accepts.

## 2. Q2: `kpmUeListMoved` (verified on the wire)
**What the wire carries**
- Each sample produces, per node, one Format 1 cell indication plus n Format 2 UE indications. The eNB sends 6 UEs as chunks of 4 + 2: `indTxUe` is 198 for the eNB and 99 for each gNB.
- Format 2 `measCondUEidList[*].matchingUEidList` holds UEID `gNB-UEID` with `amf-UE-NGAP-ID` = decimal IMSI (recorded deviation P4). See the agent at kpm-indication-message.cpp:154-156 and sample-forwarder.cpp:101 (local 725b167). The pinned agent's wire confirms it.
- Header `colletStartTime` = epoch + max(0, simMs − 100) (sample-forwarder.cpp:65). So the report of sample k carries epoch + (k−1)·100 ms. **Samples 0 and 1 share epoch + 0**: live1 has 99 distinct timestamps per node for 100 samples.

**Decoding**
- Host tshark 4.7.4 with `-d sctp.port==36422,e2ap` dissects KPM v3 into the **`e2ap.` namespace**, using the fields `e2ap.colletStartTime`, `e2ap.indicationMessage_formats` (1 = Format 2) and `e2ap.amf_UE_NGAP_ID`. The `kpm-v2.*` fields stay empty.
- live1: 696 indications = 300 Format 1 + 396 Format 2, with no SCTP bundling (no frame holds more than one indication).

**Post-hoc result on 065551Z** (scratchpad script; not committed)

| Run | Line | Report of k (src, tgt) | Report of k+1 (src, tgt) | Moved |
|---|---|---|---|---|
| live1–3 | applied IMSI 6, k 20, 2→3 | (in, out) | (out, in) | true |
| live1–3 | applied IMSI 3, k 30, 2→3 | (in, out) | (out, in) | true |
| live1–3 | applied IMSI 1, k 40, 3→2 | (in, out) | (out, in) | true |
| live1–3 | refused alreadyOnTarget IMSI 6, k 50 | unchanged | unchanged | n/a (correct) |
| k9 | refused late IMSI 4, k 61 (ledger sourceCell 0) | on gNB 2 | on gNB 2 | n/a (correct) |

For live1, the wire UE sets equal the IPC `ues` sets for all 297 (node, colletStartTime) keys.

**Definition to implement** (one checker, run per live run and on k9; gNB node n serves cell n, as in r0-checks.py:71)
- U(n, ts) is the union of `amf-UE-NGAP-ID`s over **all** Format 2 indications from node n with that `colletStartTime`, across all `measCondUEid` items, not just item 0.
- An applied line (i, s, t, k) is moved when both hold:
  - in the report of k (epoch + (k−1)·100 ms), i ∈ U(s) and i ∉ U(t);
  - in the report of k+1 (epoch + k·100 ms), i ∉ U(s) and i ∈ U(t).
- Problems (exit 1):
  - a missing report at k or k+1 for s or t;
  - k ≤ 1, where timestamps collide (refuse to judge);
  - a frame holding indications with different `colletStartTime` values;
  - a Format 2 indication without `matchingUEidList`;
  - a UE ID that is not gNB-UEID.
- Recommended negative, since it is the wire twin of V4/K9's "no handover row": for each refused or late line, i's gNB membership is identical in the reports of k and k+1. Use i's membership, not the ledger's sourceCell, which is 0 for `late`.
- Supporting only, never the judge: wire sets equal the IPC `ues` sets.
- Facts:
  - `kpmUeListMoved: {"1": true, "3": true, "6": true}`, the AND over the live runs;
  - per-run detail in `runs/<label>/kpm-ue-moves.json`.
  - Do **not** add it to `EXTRA_EXPECTED`. digest-run.py:41,67 digests only the three named files; adding it would change C1's locked component set.

**Decoder choice**
- Use tshark. It is independent of the agent codec and of kpimon, it reads every item, and it needs no `.so` extraction.
- Verify the field names on the VM's `tshark-kpm:trixie` 4.4.19 before the gate run.
- Fallback: `kpimon-decode-harness --records`, the M0–M7 harness. It prints only item 0's IDs (kpimon-decode-harness-records.c:44-66). It also needs `kpimon_extract_so`, which gate r0 does not run today.

**Honest reading if the VM tshark cannot decode the fields:** the acceptance signal cannot be met as written. That is T3. Never substitute IPC `ues` lists (agent input, not the wire) or Influx/kpimon rows.

**Standards row before the code lands:** add one ledger row. It covers E2SM-KPM v03.00, Indication Message Format 2 (`measCondUEidList`/`matchingUEidList`) and Header Format 1 `colletStartTime` (`F82PYZVK`), and E2SM common v07.00 UEID `gNB-UEID` (`QW6VJ83M`; P4 is already recorded). Read them through zotero-mcp. I did not read them, so confirm the exact section numbers.

## 3. Q3: other gaps in V1–V8

| # | Verify | Gap (code) | 065551Z evidence | Fix |
|---|---|---|---|---|
| 1 | V2 | The ACK outcome is compared as the literal `0000` (wire-c1-extract.py:245-247). The P0 decoder supports `outcome` (rc-decode.c:68-72), but the extractor sends it only header and message items (:213-216). | `0000`. That is the APER of Format 1 with an empty `ranP-List` (my derivation; it matches the selftest's purpose), so the evidence is very likely sound. The check is still not the named one. | Decode every ACK outcome in the same decoder call. Require `ok` and `<controlOutcome-Format1>` in the XER; keep the octets as a record. |
| 2 | V2, C2, C6 | A request with no ledger line skips the answer check (`continue`, :261-266). `none` answers are flagged only through the ledger join. Nothing asserts #requests = scenario count, or that agent-local rejects = 0 (C6). | 4 requests and 4 answers per live run, 1/1 in k9; agent `rc.rej*` = 0. | Every request gets exactly one answer, unconditionally. `rcRequests == N_CTL` (k9: 1). `agentLocalFailures == 0`. Emit the C2 equation: answers = ledger + agent-local. |
| 3 | V9 c5 | `answerViaNodeId` is never checked. Answers carry `viaNode` from `ip.src` (:141), but it is never compared with the request's destination. | Holds in live1–3 and k9 (checked post-hoc). | Flag a problem when they differ. Emit `c5.pairsByReqId` and `c5.answerViaNodeId` per run, ANDed in the verdict. |
| 4 | V7 | Route owners: end only, suffixed. | live1's start owner differs from its end owner. | Record a structured `routeOwner12041`/`routeOwner12042`: per run, start and end, rtmgr and e2term. Presence only; owner identity is not a pass condition (N1; making rc receive its acks is out of scope). |
| 5 | V7 | `restartCounts` map absent. | All 0 in the TSVs. | Build `restartCounts` from `*-after-pods.tsv` (rc, kpimon, hw-go, agent-N); keep the all-zero check. |
| 6 | V9 reset | Bucket id overwritten; no start times. | Lost. | Make it per run and mode-independent (it must work with one live run). Record bucket id before and after; pod name, uid, `status.startTime` and `containerStatuses[].state.running.startedAt` before and after the reset; agents' `.State.StartedAt`. **Check** that the new ≠ the old and that start ≥ the reset start. |
| 7 | V9 rng2 | Only C2 is checked (gate-r0:264-265). `facts_final` takes slack from `live*`/`k9` only (:285, :292). | rng2: 4 lines, 0 late (2 applied, 2 alreadyOnTarget), `droppedNoSub` 0. | Add an `r0_rng2_c7_holds` check (clean exit, late = 0, `droppedNoSub` = 0, slack recorded) and a `rng2` fact. |
| 8 | V9 | `droppedNoSub` absent. | 0 everywhere. | Port gate-s1:480-510 (pacing-log step lines) over all paced runs, as a check plus a fact. |
| 9 | V6 (low) | Contract C9 names `UeHandoverStartStats`/`UeHandoverEndStats`; the checker reads `EnbHandover*` (check-c9:34-35). | The Ue rows agree (0.5 ms later). | V6 is met as written. Optionally check both files. |
| 10 | cosmetic | `lLabelledUnusedUnderHold` is stale now that the hold is released. | n/a | Rename it, for example `lControlLatencyS`. |
| 11 | note | The colletStartTime collision of samples 0 and 1 (point 2 above). | Deterministic, so C1 is unaffected. | Record it as an observation. The new checker must not assume unique timestamps. |

Checked and fine as written: V1, V3, V4, V5, V6, and C1's `extra` comparison (the three named files only). "Never judge on rc's log" holds: rc's log is used only as the bring-up readiness precondition (`rc_rmr_ready`), not for any judgement.

## 4. Q4: triggers
- **None now.** This is the phase's first failed Verify. The fix adds checks the contract already requires (contract item 7, K10, C2, C5, C6, C7). It narrows nothing and does not change the outcome, so it is not T6. It restores scope rather than reducing it, so it is not T3.
- **T6** fires if the fresh run fails any of V1 to V7 or V9. That includes `kpmUeListMoved` false and a red C1. Pause, and do not run again.
- **T3** fires if the VM's tshark (and the fallback harness) cannot decode the Format 2 UE IDs.
- **T4** fires only if a needed KPM document is missing from Zotero.
- Record the gap honestly in `implementation-notes.html`. Dev rehearsal 2's "103/103" counted checks, not Verify fields, so this gap was carried, not new.

## 5. What to do (ordered checklist)
1. **Record the cause** in implementation-notes and the resume card. 065551Z: C1 green, 103/103 checks; V7/V9 failed (and V2's decoder clause); carried since rehearsal 2. Keep 065551Z committed as evidence. Do not edit its `verdict.json`.
2. **Standards row** for the KPM UE-list interpretation, read through zotero-mcp before the code lands.
3. **Code** (harness; conventional commits; no plan, phase or finding IDs in comments, test names or commit messages):
   - In `wire-c1-extract.py`, gaps #1–#3: decode outcomes; answers checked unconditionally; request count; agent-local = 0; answer node; c5 summary fields.
   - Add a KPM UE-list checker per §2, for example `tools/e2-evidence/kpm-ue-list-moves.py`: pcap + node-ips + ledger, with an optional IPC cross-check.
   - In `rc-lib.sh`: a per-run bucket id file and before/after ids; start times in `rc_pod_snapshot`.
   - In `gate-r0-rc-scripted.sh`: in `r0_live` (all modes), add the KPM check per run and on k9. After the loop, add the `c5`, `kpmUeListMoved`, `restartCounts`, `routeOwner12041`/`12042`, `reset`, `droppedNoSub` and `rng2` facts. Make each V-item a **check**. Confirm statically that no new check needs k9, replay, rng2 or ≥ 2 live runs in `--mode single`.
4. **Fixture-validate on 065551Z (host).** Expected values: c5 true/true; 4 outcomes decode as Format 1 (k9: 0 ACKs); `kpmUeListMoved` {1, 3, 6} true in live1–3; refused/late unchanged; `droppedNoSub` 0; rng2 C7 holds. Run `scripts/gates/lint.sh` and the e2-evidence selftest. Label this as checker validation, not acceptance.
5. **VM tshark check.** Run the §2 field extraction on one pcap with the VM's tshark 4.4.19. Expect 396 Format 2 rows carrying UE IDs in live1.
6. Commit and push the harness; record the SHA. Update the resume card (the VM operation exceeds 10 min).
7. **VM pre-checks:**
   - boot time is still 2026-10-22 16:40:08 UTC (else run gate i0 first);
   - the rc pod is up;
   - no stray ns-3, pacer or agent process.
8. **Run** `scripts/vm/vm-exec.sh gate-r0-rc-scripted.sh --timeout 10800` (mode c1, no `--tctl`).
9. **Re-run Verify V1–V7 and V9** on the new verdict.
   - Any failure is **PAUSE T6**: journal, kongming note, card, push.
   - A red C1 also needs its root cause recorded. Never fall back to 065551Z.
10. V8: free-space check, then `vm-snapshot.sh create r0-green --need-gb 11`.
11. Optional, to de-risk M9, before the snapshot (the snapshot reboots the VM): one `--mode single` run. It is not a Verify condition.
12. Phase-exit checklist, then a kongming go/no-go on P4.

## What to avoid
- Editing 065551Z's `verdict.json`, or calling V7/V9 passed from a post-hoc "supplement".
- Computing `kpmUeListMoved` from IPC `ues`, Influx or kpimon's log. Those are inputs or downstream, not the decoded wire.
- Reading only item 0, or only the first chunk. The eNB splits its UEs 4 + 2.
- Mapping seq by "the n-th indication". Use `colletStartTime`, and guard k ≤ 1.
- Adding the KPM UE-list file to `EXTRA_EXPECTED` (C1's component set is locked).
- Making facts without checks. M9 sees only `pass`/`failed`.
- Making rtmgr/e2term owner agreement a pass condition.
- Designing reset freshness as a cross-run comparison only; it would break `--mode single`.
- Re-running after a red result from the fresh gate.

## Alternatives and trade-offs
- **Post-hoc checker only (rejected).** It saves about 20 VM minutes. It cannot produce bucket ids or start times, it leaves V7/V9 literally unmet, and it ships untested in-gate code to M9.
- **Fresh `--mode single` instead of `c1` (rejected).** V1's C1 fields and V7/V9 must sit in one verdict at one harness SHA, and single mode has no C1.
- **kpimon harness as the primary decoder (acceptable fallback).** It is closer to "the KPM decoder harness" wording in plan.md. It needs `.so` extraction, prints only item 0, and is less independent of kpimon.

## Success metrics
- The new verdict at the new SHA has every V7/V9 field. All V-checks are green:
  - `kpmUeListMoved` {1, 3, 6} true;
  - c5 true/true;
  - `droppedNoSub` 0;
  - `restartCounts` all 0;
  - reset ids differ before and after in every run;
  - `r0_rng2_c7_holds` passes;
  - C1 is still all true.
- The fixture run on 065551Z matches the expected values in step 4 before the VM run.

## Assumptions
- Host and VM tshark expose the same `e2ap.*` KPM field names. Medium confidence; step 5 settles it, and the harness is the fallback.
- The pinned agent (4c8397d0) encodes Format 2 as the local 725b167 does. High confidence; the 065551Z wire was produced at the pin and shows it.
- "Per applied IMSI" means per applied ledger line, ANDed over the live runs. High confidence.
- `0000` is the APER of an empty Format 1. High confidence on encoding rules; the decoder call removes the doubt.
- The user accepts the refused/late "unchanged" negative as part of the same check. Medium confidence. If not, keep it as a fact only.

## Unresolved questions
- The exact E2SM-KPM v03.00 section numbers for Format 2 and `colletStartTime` (to be read in Zotero).

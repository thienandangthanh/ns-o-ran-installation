# kongming: M10 P06 phase-exit review (identity cluster P11/N5/P2/P5/P8, N1, RIC control injector)

- **Date:** 2026-11-04, about 13:40 KST (Asia/Seoul).
- **Runtime:** Claude Code on Opus 5.5, as the caller routed it (not `fable`).
- **Mode:** advisory only. I wrote this note and one kongming memory file. I ran nothing on the VM and changed no code. Every claim below comes from a code read, the committed or worktree evidence, or a host-side tshark read of the committed AC6a captures.

**What I reviewed**
- Plan and contract: `plan.md`, `goal-packet.md`, `phase-06-…md` (work record up to 8ab6cf3, and the standards rows filled in 368b740), the contract (AC12, AC13, AC18, Amendments 1–3), and ledger rows 1–77.
- My earlier notes: `kongming-261104-0600` and `kongming-261104-0410`.
- Code: `git diff 5db0346..HEAD`, read in full for `gate-e2i-interop.sh`, `e2i-wire-checks.py`, `rc-injector-lib.sh`, `replay-ts-cell-map.py`, the `agents.sh` e2mgr checks, `e2-facts-query.py`, `wire-c1-extract.py`, and the M1/M2/M3/M5/Q8/R0 gate diffs.
- Evidence: the verdict.json, checks.jsonl and `checks/*.out` of every listed run, plus `e2i/20261104T025747Z/{e2i-setup.json, e2i-controls.json, facts.jsonl, after-pods.tsv, e2i-e2ap-setup-subscription-decoded.txt, ts-patches-applied.diff, e2mgr-node-*.json}` and the M6 kpimon log.

## TL;DR
**GO-WITH-CHANGES.** AC12 and AC13 are met on the wire, in e2mgr's records, in the ledger and in the traces. No VM re-run is needed. All changes are host-only, and the must-fix items should land before P06b's first VM operation.

1. **One Validation item is false as recorded.**
   - The PASS verdict (`e2i/20261104T025747Z/verdict.json`) has `tsXappDownDuringInjector: false`.
   - Cause: cdd66b1 renamed the check to `e2i_ts_xapp_scaled_to_zero_and_deregistered`, but the fact still asks `passed e2i_ts_xapp_scaled_to_zero` (`gate-e2i-interop.sh:168`). The fact has been false in every run since that commit.
   - The three underlying checks all passed, so the TS xApp really was down. The verdict, however, does not show it, and a fact never gates.
   - The work record's "PASS on every Validation item" is therefore not true of the verdict as written.
   - Fix: correct the name, turn the fact into a check, recompute the value offline from `checks.jsonl`, and correct the work record.
2. **Ledger.**
   - Row 77 is spec-correct and stricter.
   - b583d51 does not change row 55's registered predicate; give it a dated implementation note.
   - Row 39's "frames 6, 21" refers to the original AC6a capture; the committed fixture comes from the re-probe, where the frames are 6 and 17 (exact correction text in Q4).
   - No check was deleted or narrowed: I diffed the check names of every P06 run against its P05 or M9 predecessor.
3. **Scope guard: no PAUSE T3 trigger.** Four facts must be disclosed in the exit record:
   - the VM was not reverted after the AC6a re-probe, which R-3 says it is;
   - the eNB agent still serves RC controls on RAN function 3, which it no longer announces (P07 removes this);
   - the R-3 X2AP refinements (`scs60`/`nrb24`, the 2-octet Configured TAC) are listed for Stop A′;
   - the P06 gate evidence lives under the M0–M7 plan's evidence root.
4. **P05 hand-offs: four of six are closed.**
   - The P15 interim assertion ("kpimon stays Format-3-only") was never made a check. The evidence shows that it holds.
   - The "decoded hex next to the e2mgr JSON" part of the scrubber item was not done for e2i: all six e2i e2mgr records hold `REDACTED-TOKEN`.

## Reframed problem
- **The decision:** can P06 close, and P06b (KPM UE IDs, the X2AP context export) start, on the current evidence and records without breaking AC18 or the scope guard?
- **Close means:**
  - each AC12/AC13 clause and each phase Validation item is backed by a judged artefact;
  - every predicate change has its row;
  - every deviation from a pre-registration is written down;
  - nothing P06b or P07 builds on is silently wrong.
- **Non-goals:** filling the standards rows marked "to cite" (another agent did this in 368b740), and P07 design.

## Q1. GO / GO-WITH-CHANGES / NO-GO against AC12, AC13 and the Validation list
**Verdict: GO-WITH-CHANGES.**

All paths are under `plans/`.
- `E2I` = `261103-0008-GH-1-post-m9-realism-m10/evidence/e2i/20261104T025747Z`.
- `OLD` = `261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence`.

| Clause | Evidence (verified) | Status |
|---|---|---|
| AC12: the gNB ID is 32 bits and equals the cellId | `E2I/e2i-setup.json`: en-gNB 2 and 3 decode as `['en-gNB','00f110',n,32]`, and tshark agrees. Check `m5_tshark_setup_request_func2_oid_shortname_en_gnb2_32bit_not_kpm_sim` (`OLD/m5/20261104T013651Z`) | met |
| AC12: NCI = gNB ID ‖ 1 | X2 served NR cell `nRcellIdentifier` 33 (2<<4\|1) and 49 (3<<4\|1), 36 bits, PCI = n | met |
| AC12: meid right-aligned; e2mgr `nbId` is 32 characters | `e2i_e2mgr_en_gnb_2_record`: `nbId=000…010` (32 digits), GNB/EN_GNB, ranFunctions [2, 3]. The bring-up CONNECTED set is `en_gnb_001_001_0000000{2,3}` and `enB_macro_001_001_000001` | met |
| AC12: rc, the TS key and the agent use the spec NR CGI | rc: i0 PASS (`OLD/i0/20261103T235248Z`) and `rc_at_pin` in every later gate. On the R0/R1 wire, every rc control passes `wire-c1-extract.py`'s `0000F110([0-9A-F]{8})10` filter. TS key: `r2_live1_wire_requests_equal_positives_via_target_with_stub_key` (`OLD/r2/20261104T032002Z`) shows the deployed TS xApp's real cell map, the strongest evidence. Agent: the unit cases | met |
| AC12: an independently encoded target is applied | `injected.jsonl` (pycrate target `0000F1100000000310`). The wire carries it once (frame 330, node 2) and acks it. Ledger `(2, 6, src 2, tgt 3, applied)` and `EnbHandoverStartStats` `(6, 3)` | met |
| AC12: the old N5 form is refused | frame 638 to node 3 is answered by a failure with `control-message-invalid`, and the ledger has no line for it | met |
| AC12 (A2/P14): asn1c/pycrate cross-check | `PASS agent-codec-reencode-equals-x691`, `fixture-decodes 2/2`, `m8-capture-refused 30/30` (`E2I/rc-control-test.out`) | met |
| AC13: Global ENB ID and Global en-gNB IDs | eNB `['eNB','00f110',1,20]` with tshark agreement (`e2i_globalIds`) | met |
| AC13: request parts | eNB init-eNB with one E-UTRA cell (ECI 257/28), two X2 components naming en-gNBs 2 and 3. Each en-gNB is init-en-gNB with one NR cell, n78 / 633333, and an MTC that decodes, and names the eNB | met |
| AC13: RAN function 3 with Style 5 action 3 (gNBs only) | `style5Action3Announced`: OID `1.3.6.1.4.1.53148.1.1.2.3`, Style 5 action 3 with params 1–4 (Style 3/1 is also listed, which is expected until P07). The eNB announces [2] only | met |
| AC13: every node CONNECTED, kpimon subscribes to all | the bring-up set; `kpimonSubscribedAll` (1 request and 1 response per node); `e2i_every_agent_ready_and_subscribed_by_kpimon` | met |
| AC13: N1, a non-empty TS cell map | e2i replay: keys `0000000210` and `0000000310` (plus the row-33 artifacts `…200`, `…300`), none for the eNB; `ts_nodeb_list_check`; and the R2 wire (row above) | met |
| Validation `ppidPerNode70` | `checks/e2i_ppid_per_node_70.out`: node 1 300, node 2 403, node 3 383 chunks; 712 frames by PPID = 712 forced (checks.jsonl keeps only the tail, which hides node 1) | met |
| Validation `tsXappDownDuringInjector: true` | the fact reads **false** (the rename bug above). The checks behind it passed: `e2i_ts_xapp_scaled_to_zero_and_deregistered`, then `ts_absent` before and after the run | **met in substance, false as recorded** |
| Validation: guard self-tests | the work record says `lint.sh` PASS. I did not re-run them, because no local clone holds Testbed `3163900` | accepted on the record |
| Validation: M5–M7, R0, R1, R2 green | all PASS. Check counts: M5 22→23, M2 +1, M3 +1, R0/R1/R2 +3 each versus M9. No names were lost; the M5 renames are covered by rows 35 and 39 | met |

## Q2. Scope guard and AC18
**No PAUSE T3 trigger. No check was weakened without a row.** Details:

- **Fact 3, row 77 (one X2 component per neighbour): correct and not weaker.**
  - E2AP's `E2nodeComponentID-InterfaceX2` names the peer, so an eNB with two en-gNB peers has two X2 components (E2AP v03.00 §9.2.32; recorded in my AC6a memory).
  - For an en-gNB, the new predicate keeps the old count of one and adds the peer's identity and "no other component".
  - For the eNB, the old predicate rejected a conforming node. The new one fixes which peers, with the expected set derived from the run's node set (`x2_peers`) and not from what the agent sent, so it is not circular. The e2mgr side requires `got == want` on (PLMN, 32-bit gNB ID).
  - Belief, not verified: ns-3 may also wire en-gNB↔en-gNB X2. E2AP does not require a node to list every interface, so announcing only the eNB↔en-gNB EN-DC pairs is allowed.
- **Fact 4, b583d51 (`^PASS <name>(:|$)`): not a predicate change against row 55.**
  - Row 55 says "exits 0 and prints every PASS name". The old `grep -qx` rejected a conforming output (run 3, `…/20261104T025051Z`). The new match still requires the whole name, and it still requires exit 0 and `rc-control-test: ok`.
  - The ledger's own rule since row 59 is "a predicate change and its row land in one commit", and the scope guard says "every changed predicate goes into the ledger". So append a dated implementation note to row 55.
  - Note the same for 6975269: the X2, RC and identity facts now come from the independent decode, with tshark agreement as an added conjunct. That is stronger, and it landed before e2i's first green.
- **Fact 5 (frame→node by container IP): sound, and it fails closed.**
  - The "after" snapshot (`rc_pod_snapshot after`, `gate-e2i-interop.sh:167`) includes agent RestartCount (`after-pods.tsv`: agents 1–3 at 0), and `e2i_restart_counts_zero` judges it.
  - A restart after line 167 (the TS scale-up part) is not counted, but a swapped IP would then put a foreign Global ID on a node and fail `globalIds`.
  - Optional: take the snapshot at gate end instead.
- **Facts 1 and 2: sound as recorded.**
  - Side effect of fact 1: tshark marks every gNB E2 Setup Request malformed. Today only M6 counts malformed frames, and only on indications. Any future check that counts malformed E2AP frames globally will go red.
- **Pre-registration deviations to disclose. None is a T3.**
  1. **R-3 says "the VM is reverted after the probe".** It was not. The e2i TS nodeb list holds `en_gnb_001_001_7f000001` and `enB_macro_001_001_0ffffe` (DISCONNECTED), and the M6 kpimon log lists both among its "connected" gNB and eNB lists. The judges read only nodes 1–3 and the IDs cannot collide (R-3's reason), so no verdict is affected. The end run never runs the probe.
  2. **The R-3 X2AP values were refined in place:** `nR-TxBW` {`scs60`, `nrb24`} instead of 30 kHz, and a 2-octet Configured TAC `0001` with no 5GS-TAC. R-3 marks these values "[I] until cited in P06's ledger", so refining them is inside the pre-registration, not a change to it. Show them at Stop A′, because 3GPP TS 38.101-1 is not in Zotero.
  3. **The eNB agent still applies RC controls (R0 D7 `viaEnb: 1` applied) while it announces only RAN function 2.** This is transitional, so that the R0/R1 P1 predicates stay valid until P07 (phase-07:46, rows 12, 51, 52). It is still an E2AP inconsistency at this pin, so state it in the exit record.
  4. **N1 keeps `gnb_` meids.** This is not a legacy mode: `gnb_` is e2term's rendering of a real gNB, and the agents can no longer register that way (row 37 refuses the old names).

## Q3. P05-exit hand-offs to P06
| Hand-off | Status | Evidence / gap |
|---|---|---|
| M2 before M3 from `f7-rerun-green` | closed late | The first chain skipped it and M3 `000505Z` went red (36 min). M2 `004154Z` then M3 `005519Z` PASS, with no predicate changed |
| Dev route for the patched e2mgr | closed | Rows 68–69, `m2_e2mgr_image_patched_from_pin --deploy`. AC6a re-probe PASS (`e2-identity-setup/20261103T221838Z`). The e2term-after-swap finding is handled by 01a1827 |
| Patch provenance from the pin | closed | Rows 72–74 and 76. `testbed_paths_at_pin` is called at `ts-lib.sh:112,138`, `rc-lib.sh:54,144`, `kpimon.sh:90,204`, `agents.sh:49,228` and `bringup.sh:476`; host self-tests are in `lint.sh` |
| Scrubber-proof request-part evidence | **partly open** | AC6a: judged on the VM before the scrub. e2i: the X2 judge reads the pcap and the replay runs on the VM, so the verdicts are valid. But `E2I/e2mgr-node-*.json` (all six) hold `REDACTED-TOKEN`, and no hex sidecar was written. The same applies to R0 G4's `e2mgr-node-*.json`. The stored copies cannot be re-judged on the host, and P10 needs them |
| P15 interim and stored copy | **partly open** | The stored-copy decode is closed (AC6a `e2id_*_stored_x2_request_part_decodes_and_equals_sent`). "Assert Format-3-only" has no check. The evidence agrees: in `E2I/e2i-e2ap-setup-subscription-decoded.txt` each of the 3 KPM subscriptions has exactly one action, ActionID 1, Format 3, and the M6 kpimon log has no sidecar error |
| PPID expected-node sets | closed | Row 75 (reviewed; `--nodes 2` stays) |
| (P05 Q1) PPID lines in phase-09 and phase-11 | closed | One line each in the diff |
| (S2) fail-fast headers | closed | 2d46e52. Line 4 of each of the three scripts exits 3 with "frozen at m10-cp1" before doing anything |

## Q4. Open items before P06b may start
**Must (host-only, before P06b's first VM operation)**
1. **The `tsXappDownDuringInjector` fact.**
   - Change `gate-e2i-interop.sh:168` to the renamed check.
   - Better: make it a check (`e2i_ts_xapp_down_during_injector`, conjunction of the three) so that a false value fails the gate. Add a ledger row (new check; stronger).
   - Recompute the value offline from `E2I/checks.jsonl`, save the output beside the run, and correct the work record's "PASS on every Validation item".
   - P07's e2i re-run is the live proof.
2. **Finish the work record and the exit section:**
   - Step 6 (R0 `030306Z`, R1 `031150Z`, R2 `032002Z`, all PASS);
   - the Validation list closed with paths;
   - the four disclosures from Q2;
   - the wording fix: the replayed map has every `%08X10` key **plus** the row-33 `<gNB ID>00` artifacts. It is not "`%08X10` keys only".
3. **Commit the verdict layers and archive the raw evidence.**
   - Commit: every P06 run directory listed above, plus `e2i/*` and the `.p06-ac6a-reprobe*.log` files, which are untracked in the worktree.
   - Archive to /mnt/data: the raw evidence, including `e2i.pcap`.
   - Update the resume card (it still reads "P05 DONE, 06:40") and the phase table (P06 "pending").
4. **Row 39 correction (citation only; the predicate is unchanged).** Verified with host tshark:
   - The original AC6a capture `e2-identity-setup/20261102T192656Z/e2id.pcap` has its E2 Setup Requests at frames 6 (172.17.0.2) and 21 (172.17.0.3). The planner checked the labels there with tshark 4.7.4.
   - The re-probe capture `…/20261103T221838Z/e2id.pcap` has them at frames 6 and 17, plus frame 66, the en-gNB's re-setup after the graceful close.
   - The committed fixture's arrival time (22:29:21Z) and the selftest comment (`selftest.sh:201`) show that the fixture comes from the re-probe.
   - Row 39's last clause should read: "fixture `tools/e2-evidence/fixtures/setup-identity/ac6a-setup-requests.txt` = VM tshark 4.4.19 `-V` of frames 6 (en-gNB 0x7F000001) and 17 (eNB 0xFFFFE) of the AC6a re-probe capture `evidence/e2-identity-setup/20261103T221838Z/e2id.pcap`".
   - Add a dated note: "corrected 2026-11-04: frames 6 and 21 are the setup requests of the original AC6a capture `…/20261102T192656Z`, where the labels were first verified with tshark 4.7.4; frame 66 of the re-probe is not in the fixture".
   - Append the note rather than rewriting the original cell, as rows 45 and 72 do.

**Should (before the named consumer)**
5. **The P15 interim assertion, before P06b's kpimon fork changes run on the VM** (P06b changes kpimon).
   - Record today's observation (3 subscriptions × 1 action, ID 1, Format 3).
   - Add a check with its row: every KPM subscription has exactly one action, Format 3, until P10.
6. **Row 55 implementation note** for b583d51 (and 6975269), per Q2.
7. **Hex sidecars:** write the request-part hex text next to each `e2mgr-node-*.json` on the VM, before the scrub, in e2i and R0 G4. Hex has no `==`, so the scrubber regex leaves it alone. Do this before P07's e2i re-run, and at the latest before P10.
8. **Evidence root:** export `EVIDENCE_HOST_ROOT` to the M10 plan for P06b onwards (the default is `scripts/vm/vm-common.sh:20`), or state the split in the exit record.
9. **Standards ledger: decisions that have no row yet.** This does not duplicate the to-cite rows filled in 368b740.
   - `RANfunction-Item` criticality `ignore` (`tools/asn1-indep/asn/e2ap-pdu-v03.01.asn:1257-1258`);
   - the NR PCI range 0..1007 (the codec-probe refuses 1008);
   - ECI = macro eNB ID ‖ 8-bit cell part;
   - N1's NR-only key rule (3GPP TS 37.340 §10.5.1);
   - the Style 5/3 parameter IDs announced in the definition (I-4, E2SM-RC §8.4.6.3).

**Optional:** a read-only Codex adversarial review over `5db0346..HEAD`. It is the largest T-A change set, and P07 builds directly on these judges. The goal packet allows it, with disclosure.

## Q5. Risks for P06b/P07 created by P06 choices
1. **The RAN function 3 definition and the eNB RC handler (P07).**
   - P07 must remove Style 3/1 from the definition and the eNB's RC handler (phase-07:46).
   - `rcdef_problems` checks only that the parameters include {1, 2, 3, 4}. If P07's controls carry any RAN parameter beyond 1–4 (I-4 lists 7 and 15–17), the definition must list it, or the node announces less than it serves.
   - Pre-register "action-3 parameter set in the definition == the set the rc fork sends" and "no Style 3 in the definition" as P07 e2i conjuncts.
2. **The N5-form negative in P07.** Once Style 3/1 is answered `action-not-supported`, the N5-form fixture must be re-encoded as Style 5/3 with the N5 target. Otherwise the refusal comes from the style, not the target decode, and AC12's negative becomes vacuous.
3. **The heuristic N1 parser.**
   - It takes 10 hex digits at every occurrence of the suffix in e2mgr's hex text, which yields the `<gNB ID>00` artifacts.
   - At P09 scale, more nibble-offset matches are possible. `--no-wrong-node` would catch a cross-node key, but only as an s10 red that needs an N1 patch revision.
   - Cheap pre-check: run `replay-ts-cell-map.py` on synthetic X2 parts for gNB IDs 2..12 before the s10 VM run.
4. **IP-based attribution in e2i at the end run.**
   - P13 runs e2i after r3p in one long chain, so one agent restart turns that step red: fail-closed, but costly in an unattended run.
   - For P12, consider association-based attribution keyed on a non-circular source, such as the agent's own log of its SCTP local port with the container's nodeId label.
5. **e2i's end state.**
   - e2i leaves the TS xApp re-registered on a new pod. rtmgr is restarted but a1mediator is not, and a1mediator holds a stale RMR connection to a replaced pod under IPVS (my memory note).
   - In R-1 the step after e2i is d150; in dev the steps after e2i were r0/r1/r2. Each rung run restarts a1mediator (`OLD/r2/…/live1-a1mediator-restart.json`), so the risk is low.
   - Still, exercise the e2i→d150 order in the P11 rehearsal.
6. **P06b and kpimon.** P06b changes kpimon (UE IDs) and the agent's KPM:
   - the kpimon patch-set digest changes, so plan the M3 cold rebuild (about 36 min);
   - the eNB's config-list Format 3 path (`enb-kpm-measurements.json`, `tools/kpimon-enb-probe`) must carry the eNB-UEID too;
   - the Format-3-only assertion (item 5) is the guard that kpimon's action list did not move by accident.
7. **The redacted stored copies.** P10's kpimon X2AP decoder reads e2mgr's stored request part (base64 → hex text → APER). Every judge of it must run before the scrub (item 7).
8. **Stale e2mgr records in dev chains.** Probe nodes, the M7 nodes 4–5 and kpm_sim stay in e2mgr. kpimon lists them as "connected", and the TS xApp builds keys from them. The end run is unaffected (fresh-install, no probe). In dev, any new judge must filter to the run's nodes, as G4 and the e2i replay do.
9. **The tshark malformed flag on gNB setups** (Q2): avoid global malformed-frame predicates in P07–P13.

## What to avoid
- Re-running e2i on the VM only to flip the fact. The underlying checks are recorded passes; recompute the fact offline and let P07's e2i give the live proof.
- Rewriting row 39's original text. Append a dated citation correction instead.
- Loosening `scrub-evidence.sh` to keep the e2mgr request parts. Write hex sidecars instead.
- Reading "replay passes" as proof of the deployed TS map. Cite R2's wire check for that, and keep the replay as the structural judge.
- Treating the eNB's transitional RC acceptance as acceptable after P07.

## Work checklist
1. Fix the fact name. Promote it to a check and add its ledger row. Recompute the fact offline from `E2I/checks.jsonl`.
2. Append notes to row 39 (citation) and row 55 (b583d51, 6975269).
3. Work record:
   - Step 6, the Validation closure and the four disclosures;
   - fix the "`%08X10` keys only" wording;
   - the P15 interim observation with its evidence lines;
   - the hand-off table status.
4. Commit the verdict layers, archive the raw evidence, and update the resume card and the phase table. Push.
5. Before P06b's kpimon VM run: add the Format-3-only check and its row. Before P07's e2i run: add the hex sidecars.
6. Set `EVIDENCE_HOST_ROOT` to the M10 plan for P06b.
7. Add the missing standards rows (item 9).
8. Optional: Codex review over `5db0346..HEAD`.

## Success metrics
- The recomputed `tsXappDownDuringInjector` is `true` for `025747Z`. The next e2i verdict carries a passing `e2i_ts_xapp_down_during_injector` check.
- `git ls-files` lists the verdict layer of every P06 run cited in the exit record.
- Row 39 cites frames 6/17 of `20261103T221838Z` and keeps the 6/21 history in its note.
- P06b's first kpimon run shows one Format 3 action per subscription through a gate check, not by hand.
- No `REDACTED-TOKEN` sits in a field that a judge reads without a hex sidecar next to it.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| The host self-tests (`ts-patches`, `rc-at-pin`, `kpimon-guard`) pass as the work record says | Medium-high (not re-run: no local clone holds Testbed `3163900`) | A failing self-test would reopen the guard item of the Validation list. |
| ns-3 may also wire en-gNB↔en-gNB X2, and E2AP does not require a node to announce every interface | Medium (belief, not re-read for this note) | If E2AP required every interface, row 77's expected set would need the en-gNB peers too. |
| asn1-indep's E2SM-RC module text is rc's `e2sm-rc-2.0.asn` with the v03.00 bound edit (`tools/asn1-indep/asn/SOURCES.txt`), and this was accepted in P01 as "the spec ASN.1" | Medium | If the contract wording is read strictly, the independence of AC12's encoder rests on pycrate (an independent compiler) and on the hand-checked X.691 NR-CGI fixture, not on an independent module text. Record that in the standards ledger. |
| The probe records left in e2mgr affect no P06 verdict | High (every judge filters to nodes 1–3 or to the CONNECTED set) | A judge that reads the whole nodeb list would need a filter. |
| The Format-3-only state holds in R0/R1/R2 as in e2i | Medium-high (the same kpimon image; e2i decoded) | A different action list would be a P15 or AC8b question for P08. |

## Unresolved questions
1. 3GPP TS 38.101-1 (for `nR-TxBW` {`scs60`, `nrb24`}), and 36.101/36.104 for the eNB's `bw100`, are not in Zotero. Should the user add them, or accept "unverified against Zotero" under AC20? This is a user decision, best shown at Stop A′ together with the R-3 refinements.
2. Should e2i's frame-to-node attribution move to association-based attribution keyed on a non-circular source before the P12 runner freeze? I recommend yes. It is P12 work, not a P06b blocker.

Status: DONE
Summary: P06 is GO-WITH-CHANGES. AC12 and AC13 are met. The recorded `tsXappDownDuringInjector` fact is false because of a check rename and needs a host-side fix and recompute. Rows 39 and 55 need notes, the records and verdict layers must be committed, and two P05 hand-offs (the Format-3-only check, the hex sidecars) are still partly open.

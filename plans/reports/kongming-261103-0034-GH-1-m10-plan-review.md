# Kongming counsel: M10 implementation plan review (warmup `--advice`, collect-only)

Date: 2026-11-03 00:34 KST. Subject: `plans/261103-0008-GH-1-post-m9-realism-m10/` (plan.md and phases P00–P13), checked against the locked contract `contract-261103-0001-…` and rulings R1–R12. Runtime: kongming on Opus 5.5 (the user's CLAUDE.md routes kongming to `opus` and overrides `fable`). The review was read-only: no ssh, no virsh, no git writes, no Codex. Network reads were limited to the public e2mgr 6.0.6 and nodeb-rnib sources and the E2SM-RC PDFs in `zotero-vault`. This is advice, not user approval.

Notation: [V] verified at file:line; [I] inferred; [M] taken from my memory notes and re-checked where cited.

## Verdict

**GO-WITH-CHANGES. Not Ready yet.**

- Two findings are outcome-change requests (F1, F5). Both need a user ruling in this warmup, before P00 and not at Stop A, because they change pre-registrations R-2 and R-4 and the file sets of P01, P04 and P06.
- One planner design is wrong at the deployed e2mgr (F7: kpimon cannot get eNB RAN functions).
- The plan has four high and eight medium gaps (§3).
- Nothing found is a blocker.

## 1. F1–F12, verified and classified

| F | Class | Evidence | What to do |
|---|---|---|---|
| F1 | **Outcome-change request (OCR)** | The planner's finding is correct but too narrow. The three files carry N5 keys, and also P1 and a derived hash: `r3p-scenario.json:5` (cells `0000000202`), `:17` (`"ueId": "decimal IMSI string"`), `:27` ("via the target gNB (deviation P1)"); `r3p-schedule.json:2` (`scenarioSha256` of the scenario), `:48` (key), `:52` (`"via": 2`, the target). M9 `reference/r3p/equal/files.json` pins all three [V]. | Options in §2. Recommend (a). |
| F2 | Mitigation within contract, plus disclosure | `X2Stats.txt` (73,329 rows) and `EnbHandoverStartStats.txt` are in the traces digest [V M9 digests.json; live1 ns3run]. A modelled "SgNB Change Required" X2 hop would change both. AC8b (literal traces) and AC14 (SN-initiated) are both locked, and only the in-process, zero-latency call satisfies both. | Keep P07's design. Write the message mapping into the standards ledger (in-process call ≈ SgNB Change Required; MN→S-SN `McHandoverRequest` ≈ SgNB Change Confirm; ns-3's SN↔SN X2 leg is not 3GPP TS 37.340 §10.5.1 message by message). Show it at Stop A′. |
| F3 | Within contract (interpretation) | Ledger `applySimTimeNs` 3000800000 vs `EnbHandoverStartStats.txt` 3.0038 → +3.0 ms [V M9 live1]. | Replace "the δ = 0 offset of the same control" with a registered constant: on every applied line at every δ, HandoverStart − applySimTimeNs = c, with c = 3.0 ms from the M9 reference, at the trace's 0.1 ms resolution. Controls at different δ do not pair reliably. |
| F4 | Within contract (reading) | `rxSimTimeNs` at `oran-interface/model/e2-control-hub.cc:285-286`; `applySimTimeNs = rxNs` at `:287-288` [V]. | Keep R-5. Record it as an interpretation of AC9's wording. |
| F5 | **OCR** | The `sample` lines in IPC carry only `imsi` per UE, with no RNTI [V M9 live1 `e2-ipc-trace-2.jsonl`]. ns-3 holds the X2AP-type ID: `lte-enb-rrc.cc:570` (`req.lteRnti = m_rnti`), `:726` (`oldEnbUeX2apId = m_rnti`), `:730` (`mmeUeS1apId = m_imsi`), `:1479`, `:1482` [V]. KPM Format 2 is also gNB-UEID with the IMSI (`sample-forwarder.cpp` `encode_format2`). The TS xApp calls `stoi(ue_id)` three times (`ts_xapp.cpp:622-624`) [V]. `kpm-ue-list-moves.py:55` judges `e2ap.amf_UE_NGAP_ID` [V]. | Options in §2. Recommend A. The ruling must come **before P06**, not just before P07. |
| F6 | Within contract; **resolved** | Both PDFs are in the vault: `PSHY8566` (v01.03) and `JRDTL7XS` (v03.00).<br>The §8.4.6.3 tables are identical in both [V, PDF p.180 and p.183]: 1 Target PSCell ID, 2 CHOICE Target Cell, 3 NR Cell, 4 NR CGI, 7 Secondary Node ID, … 15–17 en-gNB. These are the same IDs 1–4 that Style 3/1 uses.<br>rc's `e2sm-rc-2.0.asn` has ControlHeader-Format3 (as in v03.00, not in v01.03) and no QUERY service (which v03.00 has), so it sits between the two versions.<br>§7.6.6.5 uses Control Outcome Format 1 with one optional parameter (ReceivedTimestamp), so the empty outcome (`"outcome": "0000"` in rc-multiset) stays valid.<br>The `.zotero-ft-cache` texts are cut at about 270 KB (they end in §8.1.x). | Not a T4. The ledger row cites both bracketing versions. Read §8 from the PDF (`pdftotext -layout`), not from the cache. |
| F7 | **Preflight required + plan change** | The deployed e2mgr is 6.0.6 [V `reference/r3p/recorded/deployed-image-ids.json:43`]. In `e2_setup_request_notification_handler.go` at tag 6.0.6, the ENB branch returns at `:251-257` and `:383-389` before RAN functions are stored (`:271`, `:412`, Gnb only), and nodeb-rnib's `Enb` has no `ran_functions` [V upstream]. kpimon reads only `Gnb` (`types.go:50-59`), which is a value struct, so an eNB gets "does not advertise RAN function 2" and is never subscribed. | The planned patch ("read Gnb or Enb by nodeType") finds nothing. Take the eNB's KPM measurement list from kpimon config (the metric-map `enb` rows) and disclose it as an L-release e2mgr limit. Extend AC6a: record the eNB nodeb JSON without `ranFunctions`, and send one KPM subscription to the eNB probe node. |
| F8 | Within contract | The eNB keeps the generator's `reqpart` (`e2ap-builders.cpp:61-63`) [V]. This is as non-compliant as the gNB's 5 bytes, and P2 must end fixed. | Send an init-eNB `ENDCX2SetupRequest` (served E-UTRA cells). Add an eNB row to the e2i verdict. |
| F9 | Within contract | R5 leaves the 4-bit value open. | 1 is a good choice: a decode test can then tell the cell bits from padding. Record why. |
| F10 | Preflight required (already planned) | kpimon config is global (M3 uses kpm_sim). | Keep P03 step 2 before AC8 run 2. |
| F11 | Preflight required | The RC PDFs are present. The other documents (E2AP v03, E2SM common v07, KPM v03, 3GPP TS 36.423, 37.340, 38.323, 28.552) are not yet checked. | Check all of them once in P01, so that a T4 surfaces at the start and not in the middle of T-C. |
| F12 | Within contract; add items | `rcService.go:35` dereferences `UEID.GnbUEID.Guami.*`, and `GnbUEID` is a pointer (`rc.pb.go:151`). An EnGnbUEID request therefore panics rc, which fails AC19's RestartCount 0.<br>`rc_at_pin` checks only the source SHA (`rc-lib.sh:47,126`), while the TS xApp has an image-freshness guard (`ts-lib.sh:116-140`).<br>`rc.pb.h:11` requires protoc 3.6.1. | Add `rcService.go` to P07's rc patch. Add an image guard for rc and kpimon that ties the image to the patch-set digest. Regenerate the protobuf code in containers pinned to the image versions. As a first step, regenerate the unchanged `rc.proto` and require byte-equality with the committed `rc.pb.*`; that proves the toolchain. |

## 2. Options for the two OCRs

### F1: literal predictor records, scenario and schedule (contract AC8b)

- **(a) Recommended. Contract change to AC8b.** The three files must equal T(M9) exactly. T is a pre-registered pure transform with these parts:
  - N5 key → NCI key (`%08X%02X` → `%08X` + `1` + `0`), on key-valued fields only;
  - schedule `via`: target → the source cell, taken from the M9 ledger line's `sourceCell`;
  - `scenarioSha256` recomputed from T(scenario);
  - the two strings that name deviation P1, replaced by registered text;
  - under F5 = A, also `formula.ueId`.

  Everything else stays literal: IMSIs, steps, decisions, windows and every predictor number. A negative fixture mutates one numeric answer. This keeps the strongest continuity evidence (the predictor numbers) and keeps no legacy key in the code.
- (b) Keep N5 keys inside the harness and translate them at the TS boundary. This preserves the AC8b text, but it is a legacy shim (R1/R8), and the records would then disagree with the wire. Reject.
- (c) Re-bank the three files at checkpoint 2 without an M9 comparison. That is weaker and loses the numeric continuity. Reject.

### F5: P4 scope and the RIC-side source of en-gNB-UEID

- **A. Recommended. P4 covers RC and KPM, and the RIC learns the ID from E2.**
  - ns-3 publishes each UE's X2AP context on a new IPC line type, not inside `sample` lines. `digest-run.py` hashes only sample lines, so the ipc component stays literal.
  - Agents report KPM UE IDs as en-gNB-UEID (en-gNBs) and as eNB-UEID {MME-UE-S1AP-ID, GUMMEI, m-eNB-UE-X2AP-ID} (eNB). Both are allowed by `e2sm-common.asn:235-256` [V]. kpimon's headers already include `UEID-EN-GNB.h` and `UEID-ENB.h`.
  - kpimon writes the decoded UE ID into Influx UeMetrics.
  - The AD stand-in names the UE by the en-gNB-UEID it read from Influx. This is the real OSC AD data path.
  - The TS patch parses that ID instead of calling `stoi`.
  - The predictor maps the UE ID back to the IMSI, so its records stay literal.
  - Costs: about one extra phase of work; new ordinary AC18 rows (`kpm-ue-list-moves.py:55`, the r3p stub check "decimal IMSI", `kpimon-decode-harness-records.c:51`); F1 gains the `ueId` field. With A, P4 ends honestly "fixed".
- **B. RC only.** The trigger carries en-gNB-UEID values resolved from ns-3, which makes it an oracle. KPM stays gNB-UEID with the IMSI, so P4 cannot end "fixed". That needs a contract change (split P4 and list the KPM half). It is cheaper, but the RIC would use IDs it never received.
- **C. A without the kpimon patch.** The AD stand-in decodes the KPM UE IDs from the live capture in the pacer's pre-t0 prepare hook. This saves the kpimon work but adds tshark latency to the prepare path.

## 3. What the planner missed

**High**
1. **No injector for independent-encoder controls.** The AC12 and AC14 checks in e2i need a sender of RIC_CONTROL_REQ other than rc: the independent target, the 9-octet refusal, and Style 3/1 → `action-not-supported`.
   - After P06, rc can no longer emit those forms.
   - R0's path is rc gRPC (`rc-send.sh`).
   - rmr-peer has routes only for TS messages (`tools/rmr-peer/xapp-descriptor/config-file.json:26-27,43-44`).

   The design needs an injector descriptor (tx RIC_CONTROL_REQ, rx ACK/FAILURE), its appmgr registration and an rtmgr route. Judge the answers on the decoded wire, and keep the TS xApp down during e2i: a stray ACK reaching the TS xApp's xfcpp 2.3.6 double-frees [M].
2. F7 (kpimon for the eNB), above.
3. F1's scope (P1 `via` and the derived hash), above.
4. F12's `rcService.go` panic, above.

**Medium**
5. **Stale rc and kpimon images in dev.** A warm install can skip the rebuild (the "stale build" landmine class [M]). Add a patch-digest guard like the TS xApp's.
6. **X2AP constants.** `ServedNRCell-Information.measurementTimingConfiguration` is mandatory [V legacy `oran-e2sim/e2sim/previous/ASN1c/ServedNRCell-Information.h`], and so is `nrModeInfo`. Pre-register both as valid 3GPP TS 38.331 encodings and TDD n78 values, so that tshark decodes cleanly. Also confirm from E2AP §9.2.27 whether the request part is the whole X2AP-PDU or only the message.
7. **AC11 vs kpm_sim.** The M2/M3 captures contain kpm_sim (e2sim), which sends PPID 0 via `e2sim_sctp.cpp:222`, and the P10 row itself cites that line. "Every live capture" is then either red or ambiguous. Fix e2sim's send too (pin bump; recommended), or scope "agent" to `ns3_e2_agent` in the plan before P05.
8. **Ordering around checkpoint 3.**
   - s10 is validated at cp2 pins but runs at cp3 pins (with `UseIdealRrc=false`, the NR PDCP header and the P9 counter).
   - The e2i, p12, d100/d200/d500 and s10 rehearsals and the Codex pre-ship audit come after the cp3 tag (P12), so any fix they force needs new references and a new tag.

   Move the rehearsals and the code audit into P11, before the tag, and keep P12 runner-only. Also run one `UseIdealRrc=false` smoke in P01 (informational), so that s10's simTime and the budget reflect the final RRC model.
9. **AC16 "every C1 rung".** The four δ references from P04 are stale after T-A and T-C. Re-bank all four at cp3 (about 1 h). This holds under either reading and keeps AC9's references meaningful.
10. **p12 changes kpimon's global period in the middle of the run.** Later steps reset kpimon and inherit its config. Either p12 restores 100/100 and every later step asserts that the decoded subscription period is 100 ms, or p12 runs last. For P03(b): the reporting period sits in the event trigger, which applies to the whole subscription. Expect a RIC SUBSCRIPTION FAILURE, and pre-register its cause from the E2AP v03 text.
11. **Hub and SN resolution.**
    - The batch sort key `(imsi, viaNodeId, targetCellId, ctlId)` (`e2-control-hub.cc:247-250`) needs the resolved IMSI before sorting.
    - The S-SN must confirm it is the UE's *current* SN, because an old SN may keep a stale `RlcBearerInfo`.
    - The ledger `imsi` for `unknownUe` lines must be defined.
    - For δ a multiple of 100 ms, t_k + δ lands exactly on barrier k+n. Define and test the order of those same-timestamp events.
12. **AC18 seed misses:**
    - `r3p-checks-fixtures.py:16,59,91`;
    - `r3p-dry-run-fixtures.py:34`;
    - `tools/rmr-peer/rmr-peer-selftest.py:76-142` (N5 keys);
    - `rc-lib.sh:238` (the key argument);
    - P4 sites `kpimon-decode-harness-records.c:51` and `kpm-ue-list-moves.py:55`.

    Also note for s10: the TS xApp builds its cell map only at start (`ts_xapp.cpp:890`), so s10 must recreate it after all 11 agents connect (the r2 pattern).

**Low**
13. The independent encoder must work offline in the end run (no PyPI fetch inside the VM). Ship the image tarball with its sha256, or pre-encode on the host.
14. Make AC12's NR-CGI check strict: decode, re-encode and compare bytes, and require 8 octets. A lenient APER decode of the old 9-octet form silently drops the N5 nibble [M].
15. AC6a probe IDs must not collide with ns-3 cellIds. e2mgr keeps DISCONNECTED nodebs and the TS xApp lists them [M]. Revert after the probe.

## 4. Budget

- **/home.** 54 GiB free now [V `df -BG /home`]. The active overlay `ubuntu24.1793206761` (about 42 GiB) leaks at the first revert (FU2), so about 96 GiB is reachable.
- **T′.** The plan's T′ of 100–107 GiB uses the M9 method terms (43 + 12). Those overestimated M9: the green run went from 101 to 59 GiB free, i.e. **42 GiB consumed** [V `evidence/m9/20261028T165825Z/free-series.tsv`]. An empirical T′ = 37 + 42 + N_new (8–15) + margin is about 90–97 GiB.
  - Contract §5 does not define T′, so the plan may adopt the measured base, with the method value shown as the upper bound.
  - Raise this at Stop A, not at Stop B.
- **/mnt/data.** Only 20 GiB free (91 % used) [V]. It holds rootless podman storage (new containers: asn1-indep, protoc) and the raw-evidence archive (M9's evidence was 5.8 GB). Add a budget line and a pruning rule.
- **Wall.** The green M9 run took 12,584 s, so W′ ≈ 27–31 ks is fine. Re-measure cold i0, i2 and m3 with the patched builds: M9's warm-only timeouts nearly failed i2 [M]. A full `--dev` rehearsal from fresh-install would be best if disk allows.

## 5. Before Ready

1. User rulings on F1 (recommend (a), a contract change to AC8b) and F5 (recommend A).
2. Plan edits:
   - R-2 (F1), R-4 and R-1 (F5);
   - F7's kpimon design and the AC6a additions;
   - the injector design in P06 (#1);
   - #4–#6 in the P06/P07 file lists;
   - the AC11 scope (#7);
   - move the rehearsals and the audit before the cp3 tag (#8);
   - #9–#12;
   - budget lines (T′ base, /mnt/data, cold re-measures).
3. Write the F2, F3, F4, F6, F8 and F9 readings into an "Interpretations" section of the plan and list them in the Stop A journal. No user ruling is needed for these.
4. Then run the Codex plan gate.

## Assumptions

- The e2mgr image 6.0.6 matches the source at tag 6.0.6 (high confidence). If it does not, AC6a decides.
- submgr forwards a subscription to an ENB node without consulting RAN functions (medium). AC6a's eNB subscription probe settles it.
- Wireshark's SCTP dissector picks the dissector by PPI 70 before port 36422 (medium). P05's count comparison settles it.
- The X2 path delay is constant at 3.0 ms (high; the C9 evidence [M]).

## Unresolved questions

1. F1 ruling: (a), (b) or (c)?
2. F5 ruling: A, B or C?
3. Fix e2sim's send (pin bump), or scope AC11 to the ns-3 agents? (A plan decision; I recommend the fix.)
4. T′ base: measured M9 consumption or the method sum? (The user decides at Stop B; flag it at Stop A.)
5. AC16: do the δ sweep references count as "every C1 rung"? (I recommend re-banking them at cp3.)

Status: DONE

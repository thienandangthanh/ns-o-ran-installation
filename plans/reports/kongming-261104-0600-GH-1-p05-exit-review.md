# kongming: M10 P05 phase-exit review (SCTP PPID 70 on every E2 node, P15 scoping read)

- **Date:** 2026-11-04 (Asia/Seoul).
- **Runtime:** Claude Code on Opus 5.5, as the caller routed (not `fable`).
- **Mode:** advisory only. Besides this note I wrote only a kongming memory file. I re-ran nothing on the VM. Every claim below comes from a code read, the committed evidence, or a host-side computation.

**Reviewed**
- The plan: the phase-05 exit record (uncommitted working copy), `plan.md`, `goal-packet.md`.
- The rulings: contract AC11 and Amendments 1–3; Stop A rulings S3, S5 and G2; ledger rows 61–65; my earlier note `kongming-261104-0410`.
- The evidence: m2/192101Z, m3/193519Z, m5/201049Z, m6/201325Z, m7/201804Z, r3p/204341Z (with `reference-compare-cp1.json`), p05-ppid-offline/180737Z, and `.p05-chain.log`.
- The code:
  - harness 58629fc..5db0346;
  - Testbed d48c792 and d84068c;
  - e2sim fork e270581;
  - upstream kpimon-go 8bbbbbb (the session's scratchpad clone, including `f1ap.tar.gz`);
  - e2mgr 6.0.6 (the local OSC clone, `git show 6.0.6:`).

## TL;DR
**GO-WITH-CHANGES.** None of the changes needs a VM re-run.

1. **AC11 (dev form): met.**
   - For the agents it is met exactly as the contract words it.
   - For kpm_sim it is met in substance only. The M2/M3 predicate never ties the PPID-70 chunks to kpm_sim. It passes on "at least one association", and e2term's own association satisfies that.
   - The fix is `--source-ip` plus ledger row 66, and it can be proven offline on the committed fact sheets. The alternative is to reword the claim.
2. **The S3 conclusion is right: P15 stays a fix.**
   - Two facts in the record are wrong. The sidecar decodes only an F1AP gNB-DU CONFIGURATION UPDATE (not an F1 SETUP REQUEST), and e2mgr stores the request part as XER hex text.
   - The record also leaves out four things P10 needs: the eNB, kpimon's RAN-function gate, the X2AP decoder kpimon will have to carry, and the action-ID shift.
3. **The three deviations are sound.** Record a fourth one (the agent's fallback error path) and close the two phase risks in writing.
4. **The partial-tree risk is not triggered on the known snapshots.** P06's planned image guards must still take their patch digests from the pin's git objects: `ts_patches_check` reads the working tree today. Do this in P06's harness, before its first VM chain.
5. **New P06 blockers** (beyond your four):
   - There is no dev route to deploy the patched e2mgr on `f7-rerun-green`, and the AC6a re-probe depends on it.
   - The evidence scrubber turns long base64 request parts into `REDACTED-TOKEN` before the evidence leaves the VM.

## Reframed problem
- **The decision:** can P05 be closed and P06 started on the current evidence and records?
- **Close means:**
  - AC11's dev form is proven against the contract's wording, not only the phase's;
  - the S3 answer is a correct and complete enough input for P10 that P10 cannot narrow P15 by accident;
  - no latent harness hole is carried into P06, the first pin bump that touches the rc, TS xApp, kpimon and e2mgr patches.
- **Non-goals:** re-judging the δ work, and redesigning P15 here.

## Q1. Is AC11 (dev form) met, and as the contract states it?
**Verified**
- **Both fixes are in the code paths that the contract names.**
  - Agent: `finish_connect` sets `SCTP_DEFAULT_SNDINFO`, with a per-message `SCTP_SNDINFO` fallback (`ns3_e2_agent/src/sctp-association.cpp:110-118, 164-187` at d84068c).
  - kpm_sim: `sctp_send_data` is the only live send site in the patch file. `sctp_send_data_X2AP` is commented out (`install_patch_files/e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp:236-275`).
- **Every chain-2 capture passes**, judged per association:

| Run | PPID-70 chunks | E2AP frames, decoded by PPID = forced |
|---|---|---|
| M2 golden | kpm_sim 510 | 127 = 127 |
| M3 stock | 510 | 126 = 126 |
| M3 patched | 510 | 126 = 126 |
| M5 | node 2: 4 | 4 = 4 |
| M6 | node 2: 302 | 203 = 203 |
| M7 | every node, across 5 associations including the restarts | — |
| r3p live1 | node 2: 540, node 3: 302 | 779 = 779 |

- **The check is not vacuous on the VM.** The attempt-1 M5 red is a live negative control. The VM's tshark did not decode the PPID-0 E2SetupRequest as E2AP, so no Wireshark profile there forces a decode-as. Offline, the result agrees: 7 frames vs 778.
- **No check was removed.** Comparing check names with the cp1-era runs:
  - M2 goes 32 → 34, M3 50 → 53, M5 21 → 22, M6 37 → 38, M7 52 → 53. Every difference is a new PPID or image check.
  - The r3p single run has the live1 set plus the PPID check. The live2/live3/c1 checks are absent only because single mode does not run them.
- **The risk "tshark selects X2AP by port before PPID" is refuted.** By-PPID equals forced on all seven captures. Close the risk in the exit record.
- **Live agents used the default path.** No agent log in m7, m5 or r3p has the "PPID 70 set per message" warning. The fallback is proven only by the host loopback (`agent-loopback.txt`), which is fine.

**Gap against the contract's words ("judged per node") for kpm_sim**
- M2 and M3 call `e2ap_ppid_check "$GP" golden` with no options (`gate-m2-refnode.sh:135`, `gate-m3-xapps.sh:173`).
- `q_ppid` (`tools/e2-evidence/e2-facts-query.py:377-410`) then requires only two things: every chunk to port 36422 carries 70, and the association map is not empty.
- kpm_sim binds local port 36422. So e2term's association (`10.97.131.139:36422`, 2 chunks in the M2 golden capture) sits in the same map, and "at least one association" can be met by e2term alone.
- The practical exposure is low. A PPID-0 kpm_sim chunk still fails the first conjunct, and a silent kpm_sim fails the setup checks. But the per-node predicate is missing, and the phase Design said "kpm_sim by its pod IP". Row 62 describes the code accurately, so this is a design-to-code drift that was never recorded.
- **Fix (host-provable):**
  - Pass `--source-ip <kpm_sim container IP>`, read with `dk inspect` as `gate-m2-refnode.sh:221-222` already does for the probe.
  - Add row 66 (stricter).
  - Replay it on the committed `m2/…/golden-ppid-facts.json` (172.17.0.2) and `m3/…/m3-{stock,patched}-ppid-facts.json` (172.17.0.3).
  - The self-test already has an "absent source" case. Live proof comes in P06's own M2/M3.

**Coverage for P13 (informational, cheap to fix now)**
- PPID checks exist in m2, m3, m5, m6, m7, p12, r0, r1 and `ts-rung-lib.sh` (r2, r3p, d150).
- `phase-13:32` expects them in e2i, s10 and "every rung" as well. P06 lists `ppidPerNode70`; `phase-09` (s10, whose probe has no PPID check) and `phase-11` (`gate-d-delta-identity.sh`) do not. Add one line to each.
- The p12, r0 and r1 PPID wiring has not yet run live. A red there in P06/P07 is a wiring fault, not a P05 regression.

## Q2. Is the S3 answer sound and specific enough for P10?
**The conclusion is sound.** The F7 limit (e2mgr storing no `ranFunctions` for ENB) is not what P15 needs. Cell data lives in `nodeConfigs` for both node kinds. Verified:
- **kpimon:** the patched `initializeNode` first requires `resp.Gnb.RanFunctions` to hold the KPM function (`control.go.patch:412-453`; it returns false otherwise). Only then does it read the sidecar (`:581-599`); on error it logs and keeps an empty list.
- **Sidecar** (`f1apHelper/f1apServer.go:90-106`): it takes the `"f1"` entry, or entry 0 when there is none. There is no bounds check: an empty `nodeConfigs` panics the handler, net/http recovers, and kpimon logs "Unable to read F1 cell metadata".
- **e2mgr 6.0.6:**
  - The ranName prefix `en_gnb` maps to `Node_GNB` with `GnbType_EN_GNB` (handler `:52-54`, `:436-440`), so `nodeConfigs` (`:392-395`) and `ranFunctions` (`:409-412`) are stored under `gnb`.
  - ENB stores `nodeConfigs` (`:383-387`); the AC6a probe JSON confirms an `x2` entry.

**Corrections to the record** (factual, cheap)
1. `decodeF1apGetCellIds` (wrapper.c in kpimon-go 8bbbbbb `f1ap.tar.gz`, `:40-100`) hex-decodes its input and APER-decodes an F1AP-PDU. It takes cells **only** from a gNB-DU CONFIGURATION UPDATE (`initiatingMessage value.present == 3`, Served Cells To Add List), not from an F1 SETUP REQUEST.
2. e2mgr's field is `E2NodeRequestPart []byte xml:"e2nodeComponentRequestPart"` (`models/e2_setup_request_message.go:200` at 6.0.6). It stores e2term's **XER hex text**. So `MDAwMDAwMDIwMg==` is the text "0000000202", that is, the wire octets `00 00 00 02 02` ("5 raw octets", phase-06:8). It is not an ASCII payload. P10's decoder must therefore do base64 → hex → APER.

**Missing items that P10 needs** (add them to the S3 entry, one line each)
3. **The eNB.**
   - After P06, kpimon subscribes the eNB from its config list (phase-06:46, :76).
   - E2SM-KPM requires the Cell Global ID for cell-confined measurement types (v07 cache `SDJ6XPRF`, around line 203: "the Cell Global ID IE shall be included…"; the clause was added in v02.01, so v03.00 is expected to match; cite it in P10). An eNB cell-level Format 1 action therefore needs the eNB's E-UTRA CGI.
   - The source exists: `enb.nodeConfigs` x2, the init-eNB served E-UTRA cells. That is not F7. But kpimon's `E2mgrResponse` has no `Enb.NodeConfigs` (P06 adds `Enb` "for identity only"), and `encode_action_format1` would need an eUTRA-CGI branch.
   - State whether the eNB is in or out of P15's Format 1 set, and why. Without that line, P10 can narrow P15 silently, which is a scope-guard breach.
4. **The decoder's weight.** kpimon will need an X2AP APER decoder in its image; upstream vendors F1AP the same way, as `f1ap.tar.gz` (2.6 MB). "Medium" holds only if P10 reuses P06's agent-side X2AP asn1c codec and its e2i fixtures (`x2apRequestPartDecodes`). Share them with the TS xApp's N1 parser too, so that two forks never decode the same bytes differently. Add the kpimon cold-build time to the P11 rehearsal (M3 already takes about 36 min).
5. **Behaviour between P06 and P10.**
   - Once the en-gNB registers only an `x2` component, the sidecar falls back to entry 0 and feeds X2AP bytes to the F1AP decoder.
   - Expected result: 0 cells, because the X2AP procedureCode 36 never opens the gNB-DU CONFIGURATION UPDATE branch. kpimon then stays Format-3-only, the same as at cp1, and AC8b is unaffected.
   - Assert this in P06 (kpimon's action count and IDs unchanged) rather than assume it.
6. **The action IDs shift.** With N cells, kpimon's loop gives the Format 1 actions IDs 1..N and moves the Format 3 action to N + 1; today Format 3 is ActionID 1. The p12 judge (rows 59–60) must key on action and format. `kpm-ue-list-moves.py` keys on format and stays robust. Anything that holds `ricActionID` or the action list changes at cp3.
7. **Runtime confirmation at the AC6a re-probe.**
   - Confirm that the en-gNB nodeb has a `gnb.nodeConfigs[*]` entry with interface type `x2`, and that **e2mgr's stored copy**, not only the wire, decodes to the R-3 served NR CGIs.
   - If it does not, the cause is not F7, so it is a new Decision required. It is not a licence to take the record-only exit.
8. **The rejected alternative, for the record:** a node-level Format 1 (no Cell Global ID) would avoid the cell source, but it breaks KPM's "shall be included" rule.

## Q3. Do the deviations need anything further?
- **Start state `r3p-green`: sound; nothing more needed.**
  - The tree was clean (M2 shows `clean tree: detached checkout`).
  - c6d1434..d84068c touches no rc or TS xApp file, so the snapshot's rc and TS installs are the pinned ones.
  - Skipping M4 is covered by `r3p_live1_ns3_emitters_at_pins`.
  - **Consequence for P06:** P06 starts from `f7-rerun-green`, where the kpm_sim image has no label, and only M2 rebuilds it (`--rebuild`). Any P06 chain must therefore run M2 before M3.
- **`sendmsg` + `SCTP_SNDINFO` instead of `sctp_sendmsg`: sound, and arguably better.**
  - RFC 6458 §5.3.4 defines this as the current per-message interface. My belief, not re-verified: lksctp-tools' `sctp_sendmsg` wraps the older `SCTP_SNDRCV` message.
  - The wire evidence covers it.
  - Nit: e2sim's `cbuf` has no `alignas`, unlike the agent's. It is harmless on x86-64; fix it if the file is touched again.
- **The forced decode kept at three sites: sound.**
  - A grep confirms there are exactly three: `e2ap-pcap-facts.py:87`, `probe-rc-control-latency.sh:122` and `probe-ns3-pause-ric-reaction.sh:172`.
  - The pause probe needs no fail-fast header. S2 did not freeze it, it is not an M10 step, and a forced decode cannot give a false PPID verdict (it simply judges none).
- **A fourth deviation to record.**
  - The Design said "if neither works, association start fails loudly".
  - The code picks the fallback at connect without testing it, and a failing send becomes `Lost` (`sctp-association.cpp:115-118, :191-196`).
  - The effect is equivalent, because the first send is the E2 SETUP REQUEST and a lost setup is loud. Still, write it down.
  - Also record whether the wineslab fork e270581 was built. Nothing in M10 consumes it: `E2SIM_SHA` is only fetched by `gate-m0-preflight.sh:193`.

## Q4. Partial-tree risk before P06
**Status: latent, and not triggered on the known snapshots.**
- In this plan, only attempt 1 took the partial path (`m3/182717Z`, `m5/190346Z`), and 9a95504 removed that cause.
- From a clean snapshot, the first gate does a full checkout.

**Still real for P06, which bumps the rc, TS xApp, kpimon and e2mgr patches.** Four mechanisms combine:
- `ts_patches_check` applies the patches from `$TS_PATCH_DIR` in the working tree (`ts-lib.sh:57-58, 104-105`).
- `rc_at_pin` checks only the rc clone's HEAD (`rc-lib.sh:130-131`).
- The `already-at-sha` branch of `nist_tree_at_testbed_sha` never checks for tracked edits (`kpimon.sh:78-80`).
- P06's planned `patchset.sha256` labels do not say where the expected digest comes from (phase-06:44, :109).

On a partial or edited tree, all four pass with old patches. Only a wire check would then catch it, as a confusing red that counts against the Failure Protocol.

**Must, in P06's harness before P06's first VM chain, with ledger rows** (not before committing P05):
1. Compute every expected patch-set digest (rc, TS xApp, kpimon, e2mgr) from `git -C "$RIC_DIR" show "$TESTBED_SHA":<path>` (or `ls-tree`), as row 63 does for kpm_sim.
2. Turn the amendment-B precondition into one helper, `testbed_paths_at_pin <paths…>`: the tracked diff against the pin is quiet, and there are no untracked files that are not ignored.
3. Call that helper before any build or reuse of those images, and from `ts_patches_check`.

Optional: make `already-at-sha` also require `git diff --quiet HEAD`, and change the dirty-tree evidence to `git diff --stat HEAD` (`kpimon.sh:71`).

## Q5. Must-fix items

**Before committing the exit record** (host-only, no VM)
1. **S3 entry:** apply corrections 1–2 and add items 3–8 (short).
2. **AC11 for kpm_sim:** add `--source-ip`, ledger row 66 and the offline replay (recommended). Otherwise, reword "judged per node" for kpm_sim and schedule the fix as P06's first harness commit.
3. **Exit-record text:**
   - record the fourth deviation;
   - close both Risks (X2AP-by-port: refuted; cached kpm_sim image: rows 63/65 plus the M2 label rebuild);
   - S5's Validation line cites the chain log, but `evidence/.p05-chain.log` is untracked. Allowlist it or archive it, and cite it.
4. **Resume card and phase table:** both still read 03:20 KST, "chain-1 running".

**Before P06's VM work** (add to P06's preconditions, beside the e2mgr patch, the AC6a re-probe, the S2 headers and the AC18 rows)

5. **A dev route for the patched e2mgr.**
   - phase-06:109 describes only the M1 recipe override, which a chain from `f7-rerun-green` never runs. So the AC6a re-probe cannot run as planned.
   - Pick one:
     - a gate step: build, `ctr import`, `kubectl set image` or `helm upgrade` of e2mgr, then the replaced-pod RMR remedy (submgr too, rtmgr last, `rt_reader_ok`), recording the running pod's imageID and labels in the re-probe evidence;
     - or start P06 from `fresh-install` and accept the budget cost.
   - Either way, the stronger M1 e2mgr predicate is first exercised cold in P11.
6. **The Q4 provenance items.**
7. **The scrubber vs request parts.**
   - `scrub-evidence.sh:67` (`[A-Za-z0-9_\-]{80,}==`) runs on the VM before the copy (`vm-exec.sh:90`), so every copy, the raw archive included, loses the value.
   - Base64 of hex text is pure alphanumeric (computed). So a request part of 31 or more octets with an octet count ≡ 2 (mod 3), about one length in three, becomes `REDACTED-TOKEN`.
   - It has already happened: `e2-identity-setup/20261102T192656Z/e2mgr-nodeb-enB_macro_001_001_0ffffe.json`.
   - P06's X2 request parts are tens of octets or more, so they are exposed. Judge `x2apRequestPartDecodes` and the re-probe on the VM before the scrub, or from the pcap, and write decoded hex or fields next to the JSON.
   - Do not loosen the scrubber.
8. **The PPID expected-node sets** once the eNB becomes an E2 node.
   - The `--node-ips` gates pick it up automatically.
   - Review the `--nodes 2` sites: `gate-m5-agent-setup.sh:95` and `gate-p12-kpm-period.sh:136`.
   - Write a row for any expected set that changes.

## What to avoid
- Taking P15's record-only exit for any finding other than the F7 limit. A missing or undecodable X2 component in e2mgr is a new Decision required.
- Dodging the cell source with a node-level Format 1 (it breaks the KPM rule).
- Loosening `scrub-evidence.sh` to save request parts. The exact-secret scan is the primary control, but the regex is the only guard for tokens the scan does not know.
- Re-running the VM chain for the text fixes. The `--source-ip` change is provable offline.
- Folding P06's provenance helper into P05's exit commit. It belongs to P06's harness work, with its ledger rows.

## Alternatives and trade-offs
- **Record the kpm_sim attribution gap instead of fixing it now.**
  - Benefit: a clean P05 commit.
  - Cost: "judged per node" stays untrue for kpm_sim until P06, and the item must not be lost before P12 freezes the runner.
  - Acceptable only if the exit record says so in plain words.
- **Run P06 from `fresh-install`, not from `f7-rerun-green`.**
  - Benefits: e2mgr deploys through the real recipe path, and every image is built cold.
  - Costs: about the M1–M7 chain time and roughly 40 GiB of overlay (M9 measured 42 GiB in total), against /home at 68 GiB free.
  - I would build the dev swap route instead and leave the cold path to P11.

## Work checklist
1. `gate-m2-refnode.sh` and `gate-m3-xapps.sh`: read the kpm_sim container IP and pass `--source-ip`. Add row 66 (stricter). Replay offline on the three committed fact sheets and save the output under `evidence/p05-ppid-offline/`.
2. Edit the exit record:
   - the S3 corrections and additions;
   - the fourth deviation and the e270581 build status;
   - the two risks closed;
   - the chain-log citation.
3. Update the resume card and the phase table. Commit, and push the harness.
4. Add the PPID lines to phase-09 (s10) and phase-11 (`gate-d-delta-identity.sh`).
5. Add these to phase-06's preconditions and Risks:
   - the dev route for the patched e2mgr;
   - provenance from the pin's objects (helper plus ledger rows);
   - the scrubber-safe request-part evidence;
   - M2 before M3 from `f7-rerun-green`;
   - an assertion that kpimon keeps one Format 3 action until P10;
   - the review of the eNB expected-node sets.

## Success metrics
- Offline replay:
  - `e2-facts-query.py …golden-ppid-facts.json ppid --source-ip 172.17.0.2` passes;
  - with an unused source IP, it fails with "sent no PPID-70 DATA chunk".
- P06's M2/M3 detail shows `source 172.17.0.x: n PPID-70 chunk(s)`.
- The AC6a re-probe evidence shows all of the following:
  - the running e2mgr pod's imageID, with a label digest equal to the pin's patch digest;
  - the en-gNB nodeb's `x2` entry, decoded on the VM to the R-3 served NR CGIs;
  - no `REDACTED-TOKEN` in any field that a judge reads.
- P06's image guards fail on a fixture whose working-tree patch differs from the pin.
- P06's kpimon log shows one action (ActionID 1, Format 3) per en-gNB, and 0 sidecar cells.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| E2SM-KPM v03.00 has the same Cell Global ID "shall be included" rule as v07 (clause added in v02.01, per the v07 change log) | Medium-high | If v03.00 lacks it, a node-level Format 1 becomes a legal and simpler P15 fallback. |
| An X2AP request part fed to the F1AP decoder yields 0 cells and does not crash the sidecar | Medium-high | A sidecar crash still gives 0 cells (a kpimon error log). Garbage cells would perturb AC8b, which is why P06 should assert. |
| e2term renders request parts as canonical XER hex (no spaces) | High (the stored ns-3 value has none) | Spaced hex changes only P10's hex-decode step. Base64 of it is still alphanumeric, so the scrubber exposure is the same. |
| `f7-rerun-green`'s `~/nist` tree has clean tracked files | High (earlier M3 runs took a full checkout) | A dirty tree would take the partial path, so the Q4 helper becomes urgent. |
| The VM has no Wireshark decode-as profile | High (the attempt-1 red) | A profile would not hide a PPID fault: the per-chunk PPID histogram is independent of decoding. |
| lksctp's `sctp_sendmsg` uses `SCTP_SNDRCV` | Medium, not re-verified | Not load-bearing. |
| The wineslab fork e270581 was never compiled | Unknown (the record is silent) | If it was built, record that. Nothing in M10 consumes it either way. |

## Verdict
**GO-WITH-CHANGES.**
- Make Q5 items 1–4 before committing the exit record. All are host-only, and item 2 is a small harness change proven offline.
- Make items 5–8 P06 preconditions, before P06's first VM chain.

## Unresolved questions
- The eNB in P15's Format 1 set: in or out? I recommend in, with the E-UTRA CGI from `enb.nodeConfigs`. This is a scope statement for the user only if the caller wants it out.

Status: DONE
Summary: AC11's dev form is met for the agents. kpm_sim lacks a per-node predicate; the cheap `--source-ip` fix plus row 66 closes that. P15 stays a fix, but the S3 record needs two factual corrections and the eNB, decoder, action-ID and P06-interim items. P06 also needs a dev route for the patched e2mgr, digests taken from the pin's objects, and request-part evidence the scrubber cannot redact.

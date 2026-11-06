# kongming: P10 D-R3-1 chain attempt 2, red at e2i (Failure Protocol note)

Date: 2026-11-07 ~00:20 KST. Caller: the P10 controller. Model: Opus 5.5 (kongming). Advisory only. I edited no repo files except this report, and the VM was not touched (the only host check was a read-only `virsh domstate`/`domblklist`).
Scope: the attempt-2 driver record (`evidence/p10-chain/a7943bf/attempt-2/`, the same as the scratchpad copy), `evidence/e2i/20261106T150933Z`, the M7 run `m7/20261106T143502Z`, `gate-e2i-interop.sh`, ledger row 143, and the P06/P08/P09 precedents.

## TL;DR
- **Confirmed: a launch-procedure omission.** The host never copied `~/asn1-indep/` into the VM after the revert. It is not a D-R3-1 defect and not the M7 hazard. Every one of the 12 red checks follows from the missing image. **No e2i check judged D-R3-1's payload either way.** Row 143's predicate (`e2i_x2apRequestPartDecodes`) never ran, so D-R3-1 is *unverified*, not failed.
- **PAUSE T6 is correct under the rule set before the run.** The record needs a few additions (see Q2), the most important being "D-R3-1 unverified, not failed". Do not mark the phase-06 D-R3-1 row fixed.
- **Recommended resume (the user's ruling): (a).** Stage and verify the tarball, then run step 8 alone (`8 8`) with the byte-identical driver on the current VM. It takes about 15 min and about 0–0.5 GiB of /home, and carries no M7 risk. The VM state is a valid e2i precondition (P06 precedent: e2i run 3 → run 4).
- **Prevention:** a pre-flight in the driver that stages the asn1-indep tarball and runs `sha256sum -c` on the VM before the first step, whenever the step range contains e2i. It fails fast with exit 2 before M2. **No ledger row is needed**, because no check changes.
- I own part of this. My 2200 checklist (steps 5–6) dropped P08's "re-copy asn1-indep" step, and the resume card (`plan.md:40`) inherited that gap.

## Q1. Was it the omission? Is any e2i check evidence on D-R3-1?
**Confirmed [V]:**
- The first failing check, `e2i_asn1_indep_image_checksum_verified_and_loaded`, failed with `cd: /home/uc/asn1-indep: No such file or directory`. `image_loaded` is at `gate-e2i-interop.sh:65-69`, and `:3` says "copied by the host". No host script copies it: grepping `scripts/` finds only the e2i gate and the AC6a probe, both of which read the directory.
- Every other red check is downstream of that one:
  - `independent_decoder_self_test` and `controls_encoded_by_the_independent_codec`: "Unable to find image" (exit 125/1).
  - `encode_controls` (`:133-157`) never wrote `injected.jsonl`.
  - `setup_wire` (`:261-265`) crashes at `e2i-wire-checks.py:336` opening `injected.jsonl` **before it decodes anything**.
  - `globalIds`, `ranFunctions`, `x2apRequestPartDecodes`, `style5Action3Announced`, `kpimonSubscribedAll` and `x2-parts` all fail with "no `e2i-setup.json`".
  - `controls` fails on the missing `injected.jsonl`, and the ledger check fails because no control was applied, so there is no `e2-control-ledger.jsonl`.
- **The M7 hazard is excluded:**
  - M7 was green in this attempt.
  - e2i's own RIC checks passed: the RIC reset, the injector route table, `rtmgr_restarted` ×2, and the CONNECTED set equal to the meids.
  - The e2mgr records for all 3 nodes passed, and the setups were answered on the wire: `setup_req=3 setup_resp=3 sub_resp=3`, PPID 70 everywhere.

**D-R3-1's payload:**
- **No gate check judged it.** Row 143's conjuncts (nRARFCN 632758, band [78], nR-TxBW {scs60, nrb24}, exactly one MeasTiming with carrierFreq 633312 and SSB kHz30) live in `x2apRequestPartDecodes`, which never evaluated.
- Supportive evidence outside the gate [V] (label it "informational, not row 143"):
  - **The e2mgr records at a7943bf** (`e2mgr-node-{2,3}.json`, request parts decoded from base64 to hex):
    - The 22-bit value 632758 sits at bit 418, the APER NRARFCN position, and 633312 sits at bit 509, inside the MTC octet string. 633333 appears nowhere.
    - **The control is P08's e2i at dd27868** (`e2i/20261105T063451Z`): it has 633333 at both bit 418 and bit 509.
    - So the agent sent the D-R3-1 values on the wire and the L-release e2mgr accepted them (CONNECTED).
  - **M5's agent-image build ran the codec probe:** "X2 components … byte-equal to pycrate", ok for gNB 2 and eNB 1 (`m5/20261106T142843Z/install-agent-image.log:3704,3715`), using the fixtures regenerated for D-R3-1.
  - Neither of these is the independent decoder's judgment of nR-TxBW, the MeasTiming count or the SSB SCS. They lower the prior that (a) will be red on row 143, but they do not replace it.

## Q2. PAUSE T6 and the record
**Confirmed.** `phase-10…md:177` set "Any red step gets a kongming note, then PAUSE T6" before the run. A red e2i is a red step, and its cause does not matter to the rule. The controller's draft block ("D-R3-1 chain attempt 2", uncommitted) is accurate as written.

**Add or change before the PAUSE commit:**
1. **D-R3-1 status: "unverified (row 143 never evaluated), not failed"**, with the two informational [V] items from Q1. Say explicitly that the phase-06 D-R3-1 row stays open.
2. **Where the omission came from.**
   - P08 re-copied the tarball after every revert (`kongming-261105-1050:154`, `phase-08:116`).
   - P09's chain had no e2i step (`p09-gate-chain.sh:56-70`), so it set no precedent either way.
   - The copy was never written into a driver, a script or the resume card. `gate-e2i-interop.sh:3` is the only place that states it.
   - kongming-261106-2200's checklist dropped it, and `plan.md:40` inherited the gap.
   - [I] It was also latent in attempt 1, which stopped at M7 before e2i.
3. **Actual cost of attempt 2:** 13:09–15:15Z (2 h 06 min); /home 76 → 51 GiB (25 GiB, of which M3 took 18 GiB, 73 → 55); e2i took 309 s and 0 GiB.
4. **The state at PAUSE [V, read-only virsh]:**
   - The VM is **running on overlay `ubuntu24.1793970545` (24.6 GB), not reverted**, and e2i completed its teardown: agents stopped, injector deregistered, TS recreated and registered, rtmgr restarted, capture stopped.
   - Frozen checkout `~/.cache/ns-o-ran-frozen-harness/a7943bf…` is still present and locked. **Keep it.** The 2200 "remove after green" condition has not been met, and option (a) needs it.
   - The tarball is not staged in the VM.
5. **Resume card** (`plan.md:40` and `:58`): change "in flight" to "PAUSE T6". List the options and the recommendation below, and the ruling the user must make.
6. Add the journal in `docs/journals/` and the terminal `PAUSE T6 evidence=… journal=…` line (`plan.md:125`).
7. **Record only, no change now:**
   - `e2i_schedule_written` (`"steps": {}`) and `e2i_lockstep_run_with_five_injected_controls` passed with **zero** controls, so they passed vacuously.
   - The setup judge depends on `injected.jsonl`, so a control-encoding failure masks every setup check.
   - There is no false-green path, because `controls_encoded…` and the downstream checks are red. Any hardening later is a check change and needs its own row.
8. **Cleanup:** `tools/asn1-indep/.claude/agent-memory/` is an empty directory created by this agent's spawn CWD. I wrote nothing there. It is outside `build.sh`'s tag inputs (`build.sh:4-7`) but inside the podman build context, so remove it.

## Q3. Options to resume (the user decides at PAUSE)
| | What | Wall time | /home | /mnt/data | Risk |
|---|---|---|---|---|---|
| **(a) recommended** | Stage and verify the tarball, then `p10-gate-chain.sh a7943bf… 8 8` on the current VM, with the same driver (sha256 `dc1712c8…` = attempt 2's as-run) and a fresh `P10_CHAIN_LOG_DIR` | ~15 min (pre-checks 3, stage 1, e2i ~6, export 1), plus the records | ≈ 0–0.5 GiB (tarball ~0.15 GB [I] plus `docker load` in the overlay; P08's e2i step showed 0 GiB) | ~0.03 GiB (the e2i run dir is 25 MB) | First live run of row 143. No M7 exposure |
| (b) | Shut down, revert `f7-rerun-green`, stage, run the full chain 0–8 | ~2 h 15 min | 51 → ~76 after the revert → ~51 at the end (peak demand 25 GiB) | ~0.1–0.3 GiB | M7 no-route-table hazard: 1 in 21 on record, planning band 5–20 %. A red means PAUSE again |
| (c) | Defer e2i's D-R3-1 verification to P11's cp3 chain and continue with the UB fix | 0 now | 0 | 0 | Stacks ~10 ordered commits on an unverified first commit. Breaks the "Then mark fixed" step and P11's per-commit bisection premise. **Advise against** |

**Is the current state a valid precondition for e2i? Yes [V]:**
- e2i resets everything it relies on at its start:
  - `rc_ric_reset`: fresh rc, kpimon, hw-go and bucket;
  - `ts_scale_down` plus deregistration;
  - a fresh injector, a rtmgr restart, and route-reader checks;
  - its own agents, capture and ns-3 run.
- The failed run's teardown completed (see Q2.4).
- **Precedent:** P06 e2i run 3 (`20261104T025051Z`, red on a late check, full teardown) was followed by run 4 (`…025747Z`), **PASS**, about 7 min later on the same VM with no revert (`phase-06:170-171`). P08's e2i was also green at step 17, after six r2/r3p steps (`cp2-chain/p08-gate-chain.sh:64-70`). So e2i does not need a pristine post-I2 state.
- **Residual differences:**
  - DISCONNECTED e2mgr records. These were already present before attempt 2's e2i, from M5–M7, and the checks compare only CONNECTED or named nodes.
  - A stubqp image that is already imported. Its tag is content-addressed, so the re-import is idempotent.
  - Two more rtmgr pod generations. FU4 is guarded inside e2i.
  - None of these touches a judged input.
- **What re-running M2–I2 under (b) would add:** nothing about D-R3-1. Those steps are already green at the same SHA from a clean revert.

**Outcome rule for (a), written before launch:**
- **Pre-launch (read-only; do not launch if any check fails):**
  - `virsh domstate` is running on `ubuntu24.1793970545`.
  - No active `gate-*` unit, and no host `vm-exec` or watchdog process.
  - In the VM: no `ns3-e2-agent` container and no ns-3 process.
  - No injector deployment; appmgr does not list `ric-control-injector`.
  - The TS xApp is 1/1 Ready and registered.
  - e2term, e2mgr, rtmgr and submgr are Running, and the e2mgr E2T list is not empty.
  - The frozen checkout's `scripts/` is still read-only.
- **Stage:**
  - Host: `cd tools/asn1-indep/dist && sha256sum -c SHA256SUMS`, and confirm the tar name carries the tag `09aeabb8b0f99b0c`.
  - `ssh oran-kvm-2404 mkdir -p asn1-indep`, then `scp` the tar and `SHA256SUMS` into it.
  - VM: `cd ~/asn1-indep && sha256sum -c SHA256SUMS` returns OK.
  - Save all three outputs into the new log directory.
- **Green:**
  - Exit 0, the driver's run-dir cross-check, `verdict.pass`, and `e2i_asn1_indep_image_checksum_verified_and_loaded` showing image Id `sha256:d6bd0587…`, the same as P08's (`e2i/20261105T063451Z`).
  - Then mark D-R3-1 fixed at both SHAs. Record it as "attempt 2, steps 0–7, plus a step-8 re-run after the host-staged input was restored; user-authorized resume from PAUSE T6".
  - Cite the decoded nRARFCN, nR-TxBW and MTC values from `e2i-setup.json`. The verdict detail only says "every node as expected".
  - Continue with resume step 3.
- **Any red, including the image check again:** a kongming note, then PAUSE. No further re-run without the user.
- **Not a reclassification.** It is the user's ruling at the PAUSE, which is what T6 exists for. Do not create a general "operator-error re-run" exemption. Remove the cause instead (Q4).

## Q4. Prevention
- **Driver pre-flight (recommended).** Add this in `p10-gate-chain.sh`, after the frozen-checkout checks and before step `first`, only when the selected range contains a step with `--image-tag`:
  1. Read TAG from that step's arguments, so there is one source of truth.
  2. Host: `tools/asn1-indep/dist/asn1-indep-$TAG.tar` exists and the host `sha256sum -c` passes.
  3. If the VM's `cd ~/asn1-indep && sha256sum -c SHA256SUMS` fails, or `SHA256SUMS` does not name `asn1-indep-$TAG.tar`: copy the tar and `SHA256SUMS` with `scp`, then verify again.
  4. Write the outputs to `$here/preflight-asn1-indep.txt`.
  5. On failure, `return 2` before any step and write no tsv line.
  - Use `VM_SSH`/`SSH_OPTS` from `vm-common.sh` so the route is the same one vm-exec uses.
  - The P12 M10 runner needs the same staging; it is already listed in `phase-13:24`. Share one helper (`scripts/vm/…`) when it lands with the next harness commit. The plan-local driver can inline about 12 lines until then.
- **Its gate:**
  - shellcheck (`lint.sh`);
  - two offline negatives: the tarball missing, and the tag not matching. Each must exit 2 before step 0 with no tsv line;
  - one positive pre-flight-only dry run.
  - It does not move the harness SHA: the driver is a plan artefact, and the host steps still run from the frozen checkout.
- **Also update the launch checklist** in the resume card: "after every revert: the driver stages asn1-indep; confirm `preflight-asn1-indep.txt`".
- **No ledger row (AC18).** The ledger is "one row per changed check" (`check-diff-ledger.md:3`). The pre-flight adds no check and changes no predicate or verdict. The e2i check `image_loaded` stays the authority. A one-line note in phase-10 is enough.
  - If someone instead changes the *gate* (for example, aborting e2i early when the image check fails), that is a check change and needs a row. Not now.
- **Timing.** Land it after (a) and before the next chain that contains e2i or the AC6a probe (P11's cp3 chain and the rehearsals). Under (a), the as-run driver stays byte-identical to attempt 2's, which keeps provenance clean. Under (b), land it first and let it do the staging.

## Q5. Other things in attempt 2 worth recording
- **M7 recovery [V] was typical.**
  - The replacement e2term pod was Ready 151.8 s after the delete. That is the highest of the 12 runs in this plan dir, whose range is 127.4–152.0 s.
  - The lag from setup request to response was 84 s for the eNB and 21–22 s for the en-gNBs. In the 11 green runs the ranges are 65–103 s for the eNB and 21–65 s for the en-gNBs. The eNB needed 8 new SCTP associations (retries).
  - This adds nothing on the cause. The no-route-table signature now stands at 1 in 21 M7 runs on record.
- **Disk:** the prefix consumed 25 GiB, which matches the P09 figure of 24 GiB plus e2i. /home is at 51 GiB now.
- **Informational D-R3-1 wire evidence:** see Q1. Record it with the dd27868 control so P11 can reuse it.
- **Vacuous passes and the setup-judge coupling:** Q2.7.

## What to avoid
- Running (a) without the pre-launch checks, or after any manual RIC repair. Either becomes an improvised environment.
- Judging attempt 2's pcap offline with the host image as a stand-in for e2i. It has no controls and would be a partial, improvised gate.
- Removing the a7943bf frozen checkout or reverting the VM before the user rules. Reverting would remove (a).
- Using `sha256sum -c --ignore-missing` anywhere. It can pass with nothing verified.

## Work checklist (controller)
1. Add the Q2 items 1–8 to the phase-10 block, update the resume card, write the journal, commit and push (docs only), and print the PAUSE line.
2. Put the user's choice on the table: (a) [recommended], (b) or (c), with the Q3 costs and the outcome rule for (a).
3. Once the user has ruled: run the (a) pre-checks, stage, run `8 8`, then archive, commit the verdict layer, and remove the a7943bf checkout only after a green run.
4. Land the driver pre-flight and its negatives before the next chain with e2i.

## Assumptions
- The VM has not been touched since 15:15Z beyond the evidence export. High confidence: the overlay is the attempt-2 one, /home is 51, and the controller says it did not revert. Any manual change would void (a)'s precondition; fall back to (b).
- The host tarball is the one P08 loaded (tag 09aeabb8b0f99b0c; D-R3-1 changed only harness files mounted into it). High confidence. The image-Id comparison in (a) verifies it.
- The tarball is about 0.15 GB. Medium confidence: a hook blocked `dist/`, and the estimate comes from `tools/asn1-indep` at 160 MB.
- The M7 hazard rate is 5–20 %. Low confidence (n = 21).

## Unresolved questions
1. The user: (a), (b) or (c) for the resume. Recommendation: (a).
2. The user, carried over from the 2200 counsel: the M7-signature re-run policy, (i) or (ii). Still open, and it also applies to (b).

Status: DONE_WITH_CONCERNS
Summary: The e2i red is a verified launch omission: the asn1-indep tarball was never staged after the revert. D-R3-1's payload went unjudged, so it is unverified, not failed. PAUSE T6 stands. I recommend the user authorize an e2i-only re-run on the current VM after staging (about 15 min, about 0 GiB, no M7 risk), plus a driver pre-flight that stages and verifies the tarball before M2 (no ledger row).
Concerns: The omission traces to my own 2200 checklist. e2i's control-encoding failure masks every setup check, and two of its checks passed vacuously (record only). Keep the a7943bf frozen checkout and the VM state until the user rules.

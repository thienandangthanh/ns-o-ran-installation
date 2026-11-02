# Kongming counsel: AC6a en-gNB refusal (PAUSE T3), decision options

Date: 2026-11-03 04:40 KST. Mode: `--advice`, read-only, Opus 5.5 (the user's CLAUDE.md routing, not `fable`). This is counsel, not user approval; the user decides.

## TL;DR

Recommend **option A**: patch the deployed e2mgr 6.0.6. The patch is one XML tag on one line plus its test fixture. Deliver it the way the Testbed already delivers xApp images: build from the gerrit source at the 6.0.6 SHA with the patch applied, run `ctr import`, and override the e2mgr image in the recipe. Both A and B need a contract amendment. A's amendment is small: add e2mgr to the fork-patch list and let AC6a accept the pinned patched e2mgr. With A, every other AC holds and P5 still ends "fixed". B (register the gNB agents with the gNB choice) leaves P5 not fixed, needs a new substitution, and spreads into N1, AC14 and AC14b.

On T-B: **NO-GO to continue on your own authority, GO as soon as the user says so.** The contract says "the goal stops", so continuing needs the user's word. Ask for it in the same message as the AC6a ruling, because P02–P04 come out the same under A and under B.

## Reframed problem

The real question is not whether to patch e2mgr. It is this: **the stock L-release e2mgr cannot store any E2 node that registers with the E2AP en-gNB choice. Does the goal keep "P5 fixed to spec" by owning a one-line platform fix, or does it give up spec identity for the gNB agents to keep the platform image stock?**

- **Requirements in force:**
  - R1 and R8 say fix to spec, with no compat modes.
  - AC13 needs Global en-gNB IDs for the gNB agents.
  - AC15 needs all 11 agents CONNECTED.
  - AC14 and AC14b need the en-gNB as addressee and en-gNB-UEID.
  - §7 says "No other item may end as listed with evidence".
- **Non-goals:** upstream PRs, the N release, host changes.

## Verified evidence (new or corrected)

**e2mgr root cause [V]**
- The defect is at `E2Manager/models/e2_setup_request_message.go:54` at tag 6.0.6 (SHA `09036c6ff70f15aa3e8655612c6d9681346a1943`). `EnGnb.GlobalGNBID` is tagged `xml:"global-gNB-ID"`, so `GetPlmnId()` (`:596-610`) and `GetNbId()` (`:667-686`) read empty strings for an en-gNB.
- `SaveNodeb` then fails in `ValidateAndBuildNodeBIdKey` ("an empty plmnId received", nodeb-rnib `common/utils.go:66-67`).
- The struct is identical in 6.0.8 and in master `353939c` (2026-09-30).
- The bug is an incomplete E2AP v2 migration:
  - e2mgr already uses `global-en-gNB-ID` for the X2 component ID (`models/e2_setup_request_message.go:281`, and `models/e2_node_configuration_update.go:174`, commit `d2f1a29`, 2023-03-05).
  - Upstream tests never caught it because their fixture uses the v01 name: `tests/resources/setupRequest/setupRequest_en-gNB.xml:27,32`, asserted by `models/e2_setup_request_message_test.go:103-108,131-136`.
- **On the wire, the refusal is silence, not E2 SETUP FAILURE.** When `handleNewRan` fails with any error other than an unknown RAN name, the handler returns without sending anything (`handlers/rmrmsghandlers/e2_setup_request_notification_handler.go:138-146`). That matches the probe's "no rx within 30 s".

**e2term side [V], with one correction**
- The deployed e2term (`ric-plt-e2:6.0.6`) is correct.
- `BuildRunName.h` at 6.0.6 builds `en_gnb_` from `global_en_gNB_ID`.
- Its asn1c member name is `"global-en-gNB-ID"` (`3rdparty/oranE2/GlobalE2node-en-gNB-ID.c:18`).
- The XER it sent in run 20261102T191332Z reads `<en-gNB><global-en-gNB-ID><pLMN-Identity>00F110…`.
- **Correction:** e2term's asn1c is **E2AP v02.00** ("e2ap-v2.asn", squash `2175dd3`, 2022-05-17), not v03-era. The field name is the same in v02 and v03, so the diagnosis stands.
- The repo's `asnTextFiles/e2ap-v01.00.00.asn:1018-1021` is stale text, not the generated code.

**Spec semantics [V, E2AP v08 text, vault cache `M6MJY9U9`; v03.00 `WEE5IEXF` to cite in the ledger]**
- §9.2.6: the en-gNB choice is "To be used when E2 Node supports en-gNB mode only".
- §9.2.6: the gNB choice is for "gNB mode or both gNB and en-gNB modes".
- The scenario-zero gNBs are EN-DC SNs only, so en-gNB is the spec choice.

**e2mgr after the fix [V by reading the code]**
- **Node type.** A RAN name starting `en_gnb` maps to `Node_GNB` / `GnbType_EN_GNB` (`handler:54`, `:436-444`).
- **RAN functions.** They are stored in the gNB branch (`:409-414`), so kpimon's `resp.Gnb.RanFunctions` works. Unlike the eNB, this needs no F7 workaround.
- **Node key.** The key is `GNB:<plmn>:<nbId>`.
- **E2T association.** It is done by RAN name.
- **Setup response.** The builder handles an X2 component carrying `global-eNB-ID` (`models/e2_setup_response_message.go:397-414`).
- **Existing-RAN path.** `handleExistingRan` (`:230-272`) is node-type generic.
- I found no second en-gNB-specific defect. The re-probe must still prove this.

**Delivery path [V]**
- e2mgr comes from the recipe: `ric-dep` l-release `ee47a34`, `RECIPE_EXAMPLE/example_recipe_latest_stable.yaml:97-101` (registry, name, tag 6.0.6).
- The chart default is `imagePullPolicy: IfNotPresent` (`helm/e2mgr/values.yaml:24`).
- The registry can be overridden through `common.dockerregistry.url`.
- The Testbed already edits the recipe with yq (`install_scripts/revise_example_recipe_yaml.sh`, called at `full_install.sh:315`).
- Docker is ready by `full_install.sh:221-251`, before the helm install at `:334`.
- The xApps already use the same pattern, docker build then `ctr -n=k8s.io image import` (`additional_scripts/install_xapp_ric_control.sh:112-118`).
- kpimon and the TS xApp already build on the same `bldr-ubuntu20-c-go:1.0.0` builder that e2mgr's Dockerfile uses, with the same packagecloud RMR fetch. Both answered on 2026-11-03 (HTTP 200/302).

**Harness impact [V]**
- `scripts/gates/gate-m1-ric-up.sh:103` (`EXPECT_E2MGR=6.0.6`) and `:127-136` (`image_tags_match_l_recipe`) will fail under A by design. This needs a check-diff row.

## Options

### A. Patch e2mgr 6.0.6 and deliver it as a Testbed-built image (recommended)

**The patch** (fork patch under `install_patch_files/ric-plt/e2mgr/` with an ordered manifest):
- `models/e2_setup_request_message.go:54`: change `xml:"global-gNB-ID"` to `xml:"global-en-gNB-ID"`. Accept only that name. Do not accept both; that would be a compat mode, and e2term 6.0.6 never emits the v01 name.
- Update the fixture `setupRequest_en-gNB.xml:27,32` to `global-en-gNB-ID`, so the existing plmnId and nbId tests guard the fix.
- Add one negative unit test: a v01-named `<en-gNB><global-gNB-ID>` yields an empty plmnId.

**Delivery:**
- A new Testbed script, run between `full_install.sh:315` and `:334`, does the following:
  - clones gerrit `ric-plt/e2mgr` at `09036c6` (pinned in the Testbed's `commit_hashes*.json`, like kpimon and rc);
  - applies the manifest;
  - runs `docker build` with labels `patchset.sha256` and the source SHA;
  - runs `ctr -n=k8s.io image import`.
- The recipe override sets `.e2mgr.image.registry/name/tag` to a distinct tag such as `6.0.6-nist180-<digest12>`.
- The image is guarded like F12: the pod's imageID equals the built image, and its label equals the manifest digest.

**Contract amendment (A2):**
- §2: add "e2mgr (en-gNB XER field fix)" to the fork-patch list.
- AC6a: "accept … on e2mgr 6.0.6 plus the pinned patch set; the stock refusal (run 20261102T191332Z) is recorded as an L-release defect".
- Nothing else changes. AC12–AC15, N1, R-2 and R-3 hold as written.

**Effort [I]:**
- About 1 h for the patch and tests.
- 3–5 h for the install script, recipe override, guard and check-diff row.
- 1–3 h for the first cold build on the VM. Upstream `build-e2mgr-ubuntu.sh` runs `go get github.com/ory/go-acc` and the full test suite under `GODEBUG=…gcstoptheworld=2`, which may need a plumbing fix or may be slow.
- About 30 min for the re-probe.
- Overall about one working day plus 2–3 VM cycles.

**Risk to other ACs:**
- AC8 (cp1): none, if the patch is pinned only after `m10-cp1` (T-A invariant). Its behaviour for the M9 node types `gnb_` and `enB_` is unchanged anyway.
- AC19 end run:
  - m1 gains a build, unmeasured, and roughly 1–2 GiB on the VM [I].
  - No new class of network dependency, because gerrit, nexus3 and packagecloud are already used.
- AC18: one new row for `gate-m1` (see the checklist).
- The new predicate is stronger than the old one: the tag, the source SHA and the patch-set digest must all match.

### B. Keep 32-bit IDs and register the gNB agents with the gNB choice (Global gNB ID)

**Contract amendment (larger):**
- AC13 bullet 1;
- N1 becomes vacuous: the stock 3-underscore parser handles `gnb_`;
- a new §7 substitution so that P5 ends "listed with evidence" for the gNB agents;
- R-2 and R-3 meid layout;
- AC14 "source en-gNB" wording.

**Spec cost:**
- The node claims gNB (SA) mode, which it does not have. A Global gNB ID (3GPP TS 38.423 §9.2.2.1) is an NG-RAN identity, and these nodes have no NG or Xn.
- It also makes AC14 and AC14b incoherent. en-gNB-UEID (E2SM common §6.2.2.6) addressed to an E2 node of type gNB contradicts the R6 ruling and Open point 1. The user would need to re-rule P4's UE ID too.

**Effort:** small in code. P06 just picks a different CHOICE. The contract rework is large.

**Risk:** P5 stays unfixed, which goes against the §1 outcome "each item ends fixed".

**Variant B′:** the gNB choice with the optional Global en-gNB ID filled (§9.2.6 "both gNB and en-gNB modes"). It is the least-wrong form of B: the en-gNB ID is on the wire, and en-gNB-UEID and the X2 component stay coherent. It still overclaims SA mode, and e2mgr's `Gnb` struct (`:31-43`) does not store the en-gNB ID. If the user rejects A, choose B′ over B.

### C. Other options, all rejected

- **C1, patch e2term to emit the v01 name.**
  - e2term is the correct component.
  - This is a compensating shim, against the spirit of R1 and R8.
  - It needs a heavier C++ rebuild.
- **C2, use a newer e2mgr (6.0.8, master or N release).**
  - Verified: the defect is still there in all of them.
  - The N release is out of scope (§3).
- **C3, pre-provision the nodeb in rnib so that `handleExistingRan` runs.**
  - This is data surgery that bypasses validation.
  - dbaas has no persistence, so it is wiped at every boot.
- **C4, descope the T-A identity cluster.**
  - This is the largest contract change of all, and it is not justified by a one-line upstream bug.

### Comparison

| | A (e2mgr patch) | B / B′ (gNB choice) |
|---|---|---|
| P5 end state | fixed | listed (new substitution) |
| Contract amendment | §2 list plus AC6a wording | AC13, N1, AC14, AC14b, §7, R-2, R-3 |
| Spec compliance | E2AP §9.2.6 en-gNB | deviation (claims SA mode) |
| Engineering effort | ~1 day + 2–3 VM cycles | hours of code; heavy contract rework |
| New ownership | one platform image | none |
| Ripple to P4/AC14 | none | en-gNB-UEID coherence re-ruling |

## What to do (recommended path)

1. Put this decision to the user as Amendment 2, option A. In the same message, ask the user to:
   - confirm P14's scope;
   - rule on T4 (see below);
   - say "continue T-B" if they want it.
2. On approval, build and probe a non-pinned patched e2mgr on the VM first (feasibility). Then pin it through the Testbed only after `m10-cp1`, in P05/P06, so the T-A invariant holds.
3. Fix the P06 design wording "Interface type x2, with the node's own global ID". E2AP §9.2.32 defines the X2 component ID as the **neighbour** eNB or en-gNB. The probe already did this correctly (the en-gNB carried the MN's `global-eNB-ID`; the eNB carried the en-gNB's ID).

## AC6a evidence that closes it under A

All of the following come from the same probe script and IDs, on a RIC whose e2mgr came from the Testbed path. The VM is reverted afterwards.

1. **Image provenance.** The e2mgr pod image is the local patched tag, and its imageID equals the built image. Its labels carry source SHA `09036c6` and the manifest digest.
2. **Unit tests.** The build log shows the patched unit tests (the en-gNB plmnId and nbId tests plus the new negative test) passing.
3. **Setup response.** The en-gNB gets an `E2setupResponse` decoded by `tools/asn1-indep`, with PPID 70 on every chunk.
4. **Node record.**
   - The meid is exactly `en_gnb_001_001_7f000001`.
   - The e2mgr nodeb JSON shows CONNECTED, `nodeType` GNB, `gnb.gnbType` EN_GNB, `globalNbId.plmnId` `00F110`, and `nbId` `01111111000000000000000000000001` (32 characters).
   - `gnb.ranFunctions` contains id 2.
   - The e2mgr log has no "empty plmnId".
5. **KPM subscription.** One subscription through submgr REST to the en-gNB probe node is admitted, then deleted. This exercises the gNB-branch consumer path.
6. **Re-setup.** After a graceful close and a wait of more than 10 s, a second E2 Setup from the same en-gNB is accepted. This exercises `handleExistingRan`, which M5–M7 agent restarts hit.
7. **eNB regression.** The eNB rows are unchanged from run 20261102T191332Z.
8. **Before evidence.** The stock-image refusal run stays archived as the "before" record.

## What to avoid

- **Do not** make the e2mgr fix accept both `global-gNB-ID` and `global-en-gNB-ID`. That is a legacy mode, and nothing emits the old name.
- **Do not** tag the patched image `6.0.6` just to keep `image_tags_match_l_recipe` green. That silently weakens a check. Use a distinct tag and register the stronger predicate.
- **Do not** use `kubectl set image` on a running pod as the delivery path. It bypasses the install path and invites stale images. It is acceptable only for the unpinned feasibility probe.
- **Do not** widen the e2mgr patch to F7 (eNB RAN functions). nodeb-rnib's `Enb` entity has no `ran_functions` field, so that fix is a proto change across kpimon, the TS xApp and submgr. Keep the planned kpimon config workaround.
- **Do not** pin the e2mgr patch before `m10-cp1`.

## Other P01 results and the Stop A agenda

**P14 (RANParameter-ID unconstrained)**
- The substance is unchanged. AC12's independent-encoder target cannot be applied without this fix, so P14 is effectively required by AC12 and R1. It is not optional.
- Fold its scope confirmation into Amendment 2 now.
- **Verified:** it does not touch AC8b's enumerated list.
  - M9 rc-multiset outcome octets are `0000` (Format 1, no items), and the records hold decoded fields only.
  - Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/r0/20261026T171731Z/runs/live1/extra/rc-multiset.json`.
- Note for P06/P07: rebuild `tools/rc-decode` from the corrected ASN.1, or it cannot decode the new wire.

**T4 (3GPP TS 38.331 missing)**
- This decision does not change it. Both A and B need the X2 request part of AC13.
- Encoding is not blocked, because pycrate bundles the Rel-18 38.331 ASN.1. Only the clause citation for the standards ledger is missing.
- Ask now, while the user is already being asked. That clears a Stop A item.

**AC6b simTime of 8 s**
- This decision does not change it either. Keep it marked provisional at Stop A.
- AC15 non-vacuity has not been tested at 8 s, because the probe ran with an empty pacer schedule. Non-vacuity means more than 8 measured neighbours, and an applied PSCell change to a cell with ID ≥ 10.
- If P09 shows that 8 s is vacuous, raising simTime collides with the 45 min cap. That is a Decision required.
- UseIdealRrc=false may also change the 171 s/sim-s rate.

## GO/NO-GO for T-B (P02–P04) while the user decides

**NO-GO as an autonomous action; GO the moment the user says so. I recommend the user say so.**

Reasons:
1. AC6a's contract text says "the goal stops with Decision required". That is a contract-level stop, approved by the user. P01 already logged one deviation of this kind (deferring T4). A second deviation, this time against a contract-level stop, wears down the stop discipline the user designed.
2. The stop was placed in the prelude precisely so the user could re-scope before investing in T-B.
3. Once the user says go, T-B is safe:
   - P02 and P03 touch the hub, the pacer and kpimon's period, and cp1 compares against M9 references.
   - Neither A nor B changes those artifacts or e2mgr's behaviour for the M9 node types.

Caveats even with the user's GO:
- Hold P04's AC18 #9 **P5 rows**. The meid literals differ: `en_gnb_…` under A, `gnb_…` under B.
- Start P02's δ > 0 code only after the AC6 runtime fixtures are green. Fixtures A and B were False in runs 1–4. Run 5 is in progress, or the user must accept the contract's file:line-only reading.

**Allowed during the pause, as decision support:** the unpinned feasibility build and re-probe from "What to do" step 2. It moves no pins and lands no T-A code, and it turns A from verified-by-reading into verified-live. Put its evidence under a separate `e2-identity-setup/<ts>-patched-e2mgr-feasibility/` directory.

## Work checklist

1. Write the PAUSE T3 journal, kongming note and resume card. The decision packet covers:
   - A vs B′;
   - Amendment 2 text;
   - the P14 scope;
   - the T4 request;
   - whether to continue T-B.
2. Optionally run the feasibility probe:
   - build e2mgr 6.0.6 with the patch on the VM in a scratch directory;
   - deploy it with the recipe override or `set image`, unpinned;
   - re-run `probe-e2-identity-setup.sh`;
   - revert to `fresh-install`;
   - run `vm-orphan-overlays.sh` and `--pending`.
3. After approval and after cp1, deliver through the Testbed:
   - `install_patch_files/ric-plt/e2mgr/` with its manifest;
   - the new install script;
   - the yq override;
   - the image guard;
   - the commit_hashes pin;
   - a `TESTBED_SHA` bump.
4. Add a check-diff row for `gate-m1-ric-up.sh:103,127-136`. The new predicate: e2mgr equals the local patched tag, source label `09036c6`, and the patch-set digest. The other four tags are unchanged. The row needs no P1/P5/N5 contract flag, because Amendment 2 covers it.
5. Re-pass M0–M7 on the new pin, and record m1's build wall time and disk for the budget (N_new).
6. Rework P06's text: fix the X2 component ID wording, and record "e2mgr 6.0.6 patched" in the standards ledger and the run report.

## Success metrics

- AC6a re-probe green on every item listed above.
- M0–M7 green on the new `TESTBED_SHA`.
- The e2i step later shows all en-gNBs CONNECTED, with `nbIdBits` 32 and kpimon subscribed.
- AC15 shows 11/11 CONNECTED.
- No check weakened (ledger row present).

## Assumptions

- **High confidence.** No other e2mgr code path rejects EN_GNB once plmnId and nbId are read. This is based on reading the handler, the response builder and rnib key validation.
  - Would change it: the re-probe failing at association or response.
- **High confidence.** The probe XER is representative: the agents will use the same e2term and the same CHOICE.
- **Medium confidence.** The upstream e2mgr Docker build still works with at most a plumbing fix (the go-acc install or packagecloud).
  - Would change it: dead build dependencies. Then use a minimal two-stage Dockerfile that still runs the unit tests. Choose B′ only if that also fails.
- **Medium confidence.** The user values "P5 fixed to spec" over a stock platform image, inferred from R1, R8 and §1.
  - Would change it: a publication requirement that every RIC image stay stock. Then B′.
- **Low–medium confidence.** e2mgr's build adds ≤ 10 min and ≤ 2 GiB to m1. This is unmeasured.
- **Runtime.** Claude Code on Opus 5.5 (`model: opus`), per the user's CLAUDE.md override of the `fable` routing.

## Unresolved questions

1. Which does the user choose: A (Amendment 2: e2mgr fork patch) or B′ (gNB choice with the optional en-gNB ID, plus a new P5 substitution)?
2. May T-B (P02–P04) continue while the decision is pending, with P04's P5 rows held?
3. Does the user confirm P14 as in scope now, under AC12 and R1?
4. Will the user add 3GPP TS 38.331 to Zotero before P06, or accept the pinned pycrate ASN.1 module as the citation source?
5. Is the unpinned feasibility probe of the patched e2mgr acceptable during the pause?

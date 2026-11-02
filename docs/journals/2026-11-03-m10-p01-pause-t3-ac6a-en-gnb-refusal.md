# M10, P01: PAUSE T3, the deployed e2mgr refuses an en-gNB E2 Setup (2026-11-03 04:45 KST)

## What happened

The M10 goal started at 02:37 KST. P00 (ops prelude) is done and reviewed: kongming's verdict was GO-WITH-CHANGES, and the changes are applied (`fe25712`). In P01 everything except AC6a is green:

- **AC6 (rc claims): confirmed in source at `a2282ee` and at runtime.** An outcome-less RIC CONTROL ACKNOWLEDGE delivered 0.06 s after a control panics rc (`index out of range [0] with length 0`, RestartCount 1 → 2). The same ACK 3.10 s later is dropped, because the 2 s timer has removed the entry, and rc keeps running. In this deployment rtmgr routes 12041 to another xApp, so rc never sees an E2 node's ACK at all; the fixtures used the RMR injector.
- **AC6b (10-gNB scale probe): PASS.** The steady rate is 171 wall s per simulated second, about 0.7 GiB of host growth per run, and the proposed s10 simTime is 8 s (≈ 35 min per step).
- **Toolchain:** `tools/asn1-indep` (pycrate, offline image) passes 45/45 and decodes the committed asn1c captures.
- **Standards preflight:** 12 of 13 documents are present. 3GPP TS 38.331 is missing (T4, deferred to Stop A; notified at 03:10).
- **F10:** static. kpm_sim ignores the event trigger.
- All of it is in `plans/reports/probe-261103-0315-GH-1-m10-prelude-probes.md`.

## Why it pauses

**AC6a: the en-gNB E2 Setup is refused.** Contract text: "If either is refused, the goal stops with Decision required."

- The eNB (Global ENB ID, macro 0xFFFFE) works end to end:
  - E2 Setup Response;
  - meid `enB_macro_001_001_0ffffe`, CONNECTED, nodeType ENB, 20-bit nbId, no `ranFunctions` (F7 confirmed);
  - a KPM subscription through submgr reached it, was admitted and was deleted;
  - PPID 70 on every chunk.
- The en-gNB (Global en-gNB ID, 32-bit gNB ID 0x7F000001) gets no answer.
  - e2term builds `en_gnb_001_001_7f000001` and forwards the setup.
  - e2mgr logs `failed saving nodebInfo. Error: #utils.ValidateAndBuildNodeBIdKey - an empty plmnId received` and sends nothing.
- **Root cause (source):** the deployed e2mgr 6.0.6 reads the en-gNB identity from the XML tag `global-gNB-ID` (`E2Manager/models/e2_setup_request_message.go:54`). That is the E2AP v01 field name. e2term renders E2AP v02, where the field is `global-en-gNB-ID`.
  - The handler returns silently on the save error (`handlers/rmrmsghandlers/e2_setup_request_notification_handler.go:138-146`).
  - The same struct is in e2mgr 6.0.8 and on current master, so no OSC release fixes it.
- Evidence: `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/e2-identity-setup/20261102T192656Z` (conclusive run), with `…191332Z` as the first "before" record.

kongming's counsel (`plans/reports/kongming-261103-0440-GH-1-m10-ac6a-en-gnb-refusal-decision.md`) recommends **option A**:
- an e2mgr fork patch: one XML tag plus its upstream test fixture;
- delivered through the Testbed as a locally built image (build from gerrit 6.0.6 with the patch, `ctr import`, override the recipe's e2mgr image);
- pinned only after `m10-cp1`;
- with a small Amendment 2: add e2mgr to §2's fork-patch list, and let AC6a accept "6.0.6 plus the pinned patch".

P5 then still ends fixed. Option B′ (register the gNB agents with the Global gNB ID choice plus the optional en-gNB ID) would claim an SA mode the nodes do not have. It would leave P5 listed under a new substitution and ripple into N1, AC14 and AC14b.

## Other items for the user (also on the Stop A agenda)

1. **P14, new deviation.** rc's RANParameter-ID is encoded unconstrained, because rc's ASN.1 writes `(1..2^32, ...)`. E2SM-RC v03.00 defines `(1..4294967295, ...)` (Zotero `JRDTL7XS`, p. 287). AC12, the independent-encoder target, cannot pass without fixing rc's and the agent's codec, so it is effectively in scope. It does not touch AC8b's transform list.
2. **T4.** 3GPP TS 38.331 is missing from Zotero. pycrate bundles its ASN.1 (Rel-18, ≥ v18.6.0), so encoding is not blocked; only the citation is.
3. **AC6b simTime 8 s is provisional.** AC15's non-vacuity at 8 s is untested.
4. **P06 text correction.** The X2 component ID names the neighbour node (E2AP §9.2.32), not the node itself; the probe already does it this way.

## State at the pause

- **VM:** reverted to `fresh-install` and running. Zero untracked overlays, and the active overlay is recorded for unlink.
- **Host:** /home 96 GiB, /mnt/data 20 GiB. The 42.4 GiB post-M9 leak was deleted under the 2026-10-28 ruling.
- **Snapshots:**
  - fresh-install, f7-rerun-green, r0-green, r2-green, r3p-green;
  - `m0-probe-{d11021754,n,o,p,q}` (about 30 MB each; kept).
- **Harness:** the branch is pushed; P01's probes are committed.
- **Pins:** unchanged (the M9 values).
- **Uncommitted P02 work in progress:** the δ seam (`ActuationDelay`) is written in `oran-interface/model/e2-control-hub.{h,cc}` and `e2-ipc-emitter.cc`, and `actuationDelayMs` in `ns-3-mmwave-oran/scratch/scenario-zero.cc`. It is not compiled, not committed and not pinned. It is T-B code and is independent of this decision.
- **Codex runs this goal:** none.

## Asks for the user

1. **AC6a:** option A (an e2mgr fork patch, with Amendment 2), option B′, or another path?
2. May T-B (P02–P04) continue while you decide? P04's P5 rows of the AC18 #9 registration would be held, since the meid literals depend on 1.
3. Is P14 confirmed in scope (rc and agent RANParameter-ID constraint fixed to E2SM-RC v03.00)?
4. Will you add 3GPP TS 38.331 to Zotero, or accept the pinned pycrate ASN.1 as the citation source?
5. Under A, is an unpinned feasibility build and probe of the patched e2mgr acceptable before `m10-cp1`, as decision support?

## Open questions
- Should the AC6b simTime (8 s) be confirmed now, or re-checked against AC15's non-vacuity in P09 as planned?

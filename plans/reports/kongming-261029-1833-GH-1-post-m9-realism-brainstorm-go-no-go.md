# Kongming counsel: go/no-go on the post-M9 realism brainstorm winner

Date: 2026-10-29 18:33 KST. `--advice` checkpoint after the best-of-9 decision round. Runtime: kongming on Opus 5.5 at xhigh, read-only. Advice only; not user approval. Subject: `brainstorm-261029-1824-GH-1-post-m9-realism-goal-contract.md`.

**TL;DR.** Hand D to `ak:goal-warmup`. There is no need to redo the brainstorm or switch to A. D and A differ only in how they read δ = 0, and D converts to A by editing AC8, AC12 and AC19. Before approval, fix six defects in the contract text and add one new defect I found: P5 renames the meids, which breaks the TS xApp's cell map. Plan three Stops, not one uninterrupted goal. (I ran on Opus 5.5, read-only. No files, memory, git, ssh or Codex were touched.)

**Q1. Go / no-go**
Go with D. None of the 11 defects is structural. A's useful pieces can be grafted onto D: substitution 6 (the P12 fallback), plus F's Stop A, its rule for registering deviation-encoding checks, its δ tie rule and its scale probe.

**Q2. Unresolved items 1–5**

1. **δ = 0 reading: take SUB-1, with three hardening rules.**
   - Evidence: P1, P4, P5 and P11 change pinned components, the ledger and the `extra` digests. They also change predicates that encode the deviations:
     - `r3p-checks.py:203-207` (d7 "via the target gNB (recorded deviation P1)"), used by r0, r1, r2 and r3p;
     - `gate-r0-rc-scripted.sh:150-152` (cell-map expectations);
     - `gate-m5-agent-setup.sh:25` (meid).
   - A compat profile would keep non-spec wire paths alive in the agent, rc, the TS xApp and the harness, and it contradicts AC12.
   - Hardening rules:
     - (a) Tag the AC8 commit, so the M9 references reproduce from a named commit.
     - (b) After T-A, with δ = 0 and T-C off, ipc, traces, predictor-records, scenario and schedule must still be literally equal.
     - (c) Transforms cover only enumerated fields (viaNodeId, the UE ID, target and viaNode in rc-multiset, meid), and a negative fixture proves a mutated M9 file fails.
   - Cost if wrong: if the user wants literal equality forever, compat has to be retrofitted after T-A, which is expensive. Get the ruling in warmup.

2. **Measurement-time stamping: keep it out.**
   - Influx is queried by a wall-time range (`agents-ns3-run.sh:161`), and the epoch is pinned to 2026-01-01. Stamped points would fall outside every judge's query range.
   - Points are untagged, so they would also collide across nodes. Nothing in scope consumes them.
   - Cost if wrong: low. It can be added later with the QP goal.

3. **h: use 12, defined by AC4's method rather than as a number.**
   - I computed the largest 370 s drop in each M9 attempt: 8, 9, 11 and 12 GiB, rising across attempts. h ≈ 9 was already exceeded twice.
   - Extend the method to dev rehearsals of the new steps; 10-gNB captures may make larger bursts.
   - Cost: +3 GiB. If h is set too low, a burst during the stop path can breach the 25 GiB floor.

4. **P11: 32 bits.**
   - e2term writes the gNB ID right-aligned as whole-octet hex (`ric-plt-e2 BuildRunName.h:76-93`). The TS xApp finds that suffix in the request part and takes 10 hex digits (`ts_xapp.cpp:338-366`).
   - Those 10 digits line up with the NCI octets only for a 32-bit ID: 8 hex of gNB ID, 1 hex of cell part, 1 hex of padding. With 28 + 8 the match is shifted by a nibble and only works by PLMN coincidence.
   - ns-3 has one cell per gNB, so gNB ID = ns-3 cellId and the cell part is a constant. The agent then maps the gNB ID to the cell; today it passes `o[8]` (`rc-control.cpp:31`).
   - Cost if wrong: the agent, rc, TS xApp and predictor must be re-keyed. That is low if decided before the identity cluster.

5. **P1 to the MN eNB, and P4 per addressee.**
   - ns-3 runs every handover through the master node's handler (`e2-control-hub.cc:265`). It already models MN-driven SN change, and the eNB already has an agent.
   - A later move to Style 5 action 4 also addresses the MN, so nothing would need re-addressing.
   - Record "Style 3 action 1 at the MN" under P13.
   - P4:
     - RC controls use eNB-UEID {MME-UE-S1AP-ID set to ns-3's own value; that equals the IMSI by ns-3's construction (`epc-mme-application.cc:112`), and this is disclosed; GUMMEI constant}.
     - en-gNB KPM reports use en-gNB-UEID {the m-eNB-UE-X2AP-ID ns-3 really holds, cited with file:line in the plan; globalENBID}.
   - Alternative: addressing the source en-gNB (SN-initiated, 3GPP TS 37.340 §10.5.1) needs a smaller TS xApp patch.
   - Cost if wrong: the d7 predicates and the rc-multiset transform are redone. Moderate.

**Q3. Defects**

Fix in the contract text before approval:
- #1: SUB-1 with the hardening above.
- #4: AC19 names `reference/r3p` at the tagged checkpoint plus each new reference, `minHostFreeGb ≥ 25`, rc RestartCount 0, and the rule for the step list. Put one full C1 at δ = 150 ms in M10 and short δ-identity runs for the other values.
- #5: an item may end "listed with evidence" only under an approved substitution.
- #6: write the gNB ID length decision into AC12.
- #7: add P12 fallback A-sub-6 / F-(d) as a proposed substitution.
- #9, widened: rewriting any predicate that encodes P1, P5 or N5 is a registered contract change. That covers d7 in r0 to r3p, `:234`, the cell-map and meid literals in m5, r0, `rc-send.sh`, `replay-ts-cell-map.py` and the probes.
- **New N1:** e2term names en-gNBs `en_gnb_…` and eNBs `enB_macro_…` (`BuildRunName.h:150-200`). The TS xApp takes the suffix after the 3rd `_`, so its stock cell map is empty for en-gNBs. AC13 should name the patch.

Leave for the plan:
- #8: run AC8 after the δ seam and again after P12. Keep apply synchronous at δ = 0, because a zero-delay event can reorder ties.
- #10: preflight probes.
- #11: fix the text while editing.
- P2 needs an X2AP codec. Legacy asn1c `ENDCX2SetupRequest` code exists in `oran-e2sim/e2sim/previous/ASN1c/`.

**Q4. Size**

One `/goal` is realistic only with Stops:
- **Stop A** after MB: literal checkpoint and δ references banked, budget re-projected.
- **Stop A′** after the T-A identity cluster, the largest unknown.
- **Stop B** before M10, for disk.

Move two cheap probes into the prelude: whether the live e2mgr/e2term accept en-gNB and eNB setups (and the meids they produce), and a 10-gNB wall and disk probe.

Disk: T′ ≈ 37 + 43 + 12 + (8–15) = 100–107 GiB, against about 101 GiB reachable (58 free now plus the ~42 GiB leak). Plan on a shortfall that the user frees at Stop B. Do not delete anything autonomously beyond the 2026-10-28 ruling.

Wall: 27–31 ks in one `systemd-run` invocation is fine.

**Next risk to watch:** the T-A identity cluster. That means the meid rename through e2term, the TS xApp, kpimon and the harness, plus whether e2mgr accepts en-gNB and eNB setups. e2mgr master parses EnGNB/ENB; the deployed L-release image is unverified.

**Assumptions**
- The deployed e2term names nodes like ric-plt-e2 master `5aa396f` (medium confidence). If it does not, the N1 specifics change.
- The deployed TS xApp's cell-map code is the upstream code, since its patches are small (high confidence).
- ns-3's en-gNB holds an X2AP-type UE ID (low confidence). If it does not, P4's KPM side needs a fallback ID.

Sources: [e2mgr e2_setup_request_message.go](https://raw.githubusercontent.com/o-ran-sc/ric-plt-e2mgr/master/E2Manager/models/e2_setup_request_message.go), [RIC-211](https://jira.o-ran-sc.org/browse/RIC-211).

Verdict: GO-WITH-CHANGES

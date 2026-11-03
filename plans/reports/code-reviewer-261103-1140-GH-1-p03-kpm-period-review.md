# Code review: P03 KPM reporting period / granularity (uncommitted, O-RAN-Testbed-Automation)

Date: 2026-11-03 (Asia/Seoul). Read-only review. Nothing built or run except `git apply --check` of the patches in a scratch dir.

## Scope
- Agent: `ns3_e2_agent/src/` (18 modified, +2 new: `kpm-subscription-admission.{hpp,cpp}`), `CMakeLists.txt`, `Dockerfile`, `asn1c_patches/NativeEnumerated_aper.c.patch`, tests and fixtures.
- kpimon: `control.go.patch`, `wrapper.c.patch`, `wrapper.h.patch` (new). Reviewed the code they produce: applied both the HEAD and the working-tree patch sets to the `*.previous` sources and diffed the results.
- Installer: `additional_scripts/install_xapp_kpi_monitor.sh`.
- About 850 lines changed in tracked files, plus about 1.3k lines in new files (mostly the test).
- Evidence checked: M7 capture `plans/261103-0008-.../evidence/m7/20261103T022052Z/m7-e2ap-setup-subscription-decoded.txt`; M9/M10 IPC traces scanned for duplicate IMSIs; pristine NIST asn1c at da6f82f2 (`OSC-repos/sim-e2-interface/e2sim/asn1c`); kpimon 8bbbbbb descriptor/schema; E2AP v03.01 ASN.1 and KPM v03.00 ASN.1 in `tools/asn1-indep/asn/`.

## Overall
The P = T path is sound. A single-sample report goes through the same header, cell and UE-chunk code with the same inputs, and the step-line `forwarded` value stays the same at P = T. The asn1c builders have no ownership bugs. The E2AP IE sets and criticalities match v03.01. One blocking design gap: there is no upper bound on K = P/T. Large but legal reporting periods are admitted and then never delivered, and the buffer can grow without limit.

## Critical
None found.

## High

**H1. No bound on K. Admitted periods produce reports that can never be encoded or sent, and the buffer is unbounded.**
- Where: `kpm-subscription-admission.cpp:95-102` (only checks P mod T), `subscription-table.cpp:41` (window grows to K), `sample-forwarder.cpp:108` (cell Format 1 not chunked), `e2ap-builders.cpp:331` (hard limit of 8192 octets).
- Sizes from the golden fixture: cell message = 340 octets at K = 1, about 160 more per extra measData item. So any P above about 5 s (K ≈ 50) gives a cell message over 8192 octets. `build_indication` then fails on every period: the whole report fails (cell first, UEs never tried), all K samples go to `samplesReportFailed`, and the subscriber gets nothing.
- UE side: one UE costs about 870 octets of measCond plus about 175 per item. Above P ≈ 3.5 s even chunk = 1 exceeds `E2_MAX_E2SM_BYTES=7000`, so every UE is dropped as oversize every period.
- Concrete failure: `KPIMON_REPORTING_PERIOD_MS=10000` (NIST's old default; the installer accepts it, `install_xapp_kpi_monitor.sh:53`). P = 10000 is a multiple of 100, so it is admitted in a RIC SUBSCRIPTION RESPONSE. Then zero indications are ever sent, while kpimon believes it is subscribed.
- At P = 4294967200 ms, K ≈ 43M SampleRecords (about 7.8 KB each with 5 UEs) are buffered before the first attempt: OOM.
- K > 65535 also breaks KPM v03.00 `MeasurementData SIZE(1..maxnoofMeasurementRecord=65535)`.
- This breaks the "exactly one indication per reporting period" requirement for admitted subscriptions.
- Fix:
  - Add a K bound at admission, e.g. `E2_MAX_SAMPLES_PER_REPORT`, or derive it from a worst-case size of the cell message.
  - Refuse above it with RIC SUBSCRIPTION FAILURE, ricRequest / `function-resource-limit` (E2AP 9.2.1) or `eventTriggerNotSupported`. Pick one and record it.
  - Cap `KPIMON_REPORTING_PERIOD_MS` in the installer to match.
  - Choice 7 ("cell Format 1 not chunked") is only acceptable together with this bound.

## Medium

**M1. Admission is per action, but what is sent is not.**
- Where: `e2-session.cpp:179`; `forward` / `send_report`.
- The agent still sends every report (cell Format 1 and UE Format 2) under the lowest admitted action ID, whatever format that action asked for.
- Failure case: a request with a Format 1 cell action (G = T) and a Format 3 UE action that is not admitted (bad G, or a definition truncated by SubMgr, which is exactly the by-name case). The response lists the UE action as not admitted, yet UE Format 2 indications keep arriving on the cell action. The reverse also happens.
- E2SM-KPM ties indication Format 2 to action Format 3 and indication Format 1 to action Format 1.
- In the testbed this cannot happen today: the M7 capture shows 20 subscriptions, each with exactly one action (ID 1, Format 3). kpimon's per-cell Format 1 loop yields no actions for ns-3 nodes. So this is a latent spec deviation that the new not-admitted list makes visible.
- Fix: record the admitted format(s) on the Subscription. Send cell messages only when a Format 1 action is admitted and UE messages only when a Format 3 (or 2/4/5) action is admitted, each under its own action ID. Alternatively, record it as a deviation.

**M2. The hello-period check (choice 5) has no wiring.**
- Where: `sample-forwarder.cpp:51`; `run_ns3_e2_agents.sh:83` passes no `E2_INDICATION_PERIOD_MS`.
- Every current gate and probe uses `--indicationPeriodicity=0.1`, so gates do not regress. But upstream `run-scenario-three.sh` / `run-scenario-five.sh` / `run-simulations.sh` use 0.02 s.
- With those scripts, the hello is rejected and IPC is closed. In lockstep, ns-3 then waits at its barrier until timeout. This is a silent operational break for anyone who forgets `--env E2_INDICATION_PERIOD_MS=20`.
- The choice itself is right: T must be fixed before the subscription arrives. Fix: have the run script take the period (or derive it from the scenario args) and document it in the deployment guide.

## Low

**L1. Latent P = T divergence: duplicate IMSIs.**
- Where: `sample-forwarder.cpp:80-85`.
- Before, a sample with a repeated IMSI encoded that UE twice. Now the duplicate is dropped and counted as `uesDroppedBadImsi`. That counter now mixes bad IMSIs with duplicates.
- Octets would differ at P = T if ns-3 ever emitted a duplicate. I scanned 27 IPC traces (M9 m6/m7, M10 m6/m7): 0 samples with duplicates, so no observed effect.
- The change is not stated anywhere. Either document it or keep both entries for K = 1.
- Related: `ConvCounters` are now counted once per sample at build time (`:66,:85`), including UEs later dropped as oversize, whereas before they were counted per kept chunk. Stats change only.

**L2. Samples without `seq` are now dropped.**
- Where: `sample-forwarder.cpp:62`. Such a sample is now counted as `droppedEncode`; before, it was encoded. IPC v1 always carries `seq`, so no practical effect.

**L3. The stats identity (choice 6) cannot be computed from the stats line.**
- `droppedEncode` counts in mixed units: per sample for a build failure (`main.cpp:80`), per report for an encode failure (`e2-session.cpp:241`), and per indication when `build_indication` fails (`e2-session.cpp:215`). The last two are also counted in `samplesReportFailed`, so they are double-counted against the identity's "pre-table drops".
- `PeriodTally` takes the max over subscriptions (`subscription-table.cpp:37,42`) and clamps forwarded at 0 (`:48`). That stops the pending-delta from telescoping when subscriptions differ in P or alignment.
- Exact for the testbed's single subscription. Fix: add a separate `droppedBuild` counter so the identity can be closed.

**L4. A seq gap right after a completed period is not counted.**
- Where: `subscription-table.cpp:33`. When the window is empty, a gap is not detected and `reportGaps` stays 0. The next period just re-aligns, which is acceptable. Only the counter is under-reported.

**L5. The installer decides between restart and reinstall only on the deployed periods.**
- Where: `install_xapp_kpi_monitor.sh:67-70`.
- A kpimon image built from an earlier version of these patches, with the same 100/100, is restarted, not rebuilt, so the new Format 2 loop or encoder would not be picked up.
- Pre-existing restart semantics, but now more likely while the patch is iterating. Fix: also compare a digest of the patch set (e.g. a deployment annotation).

**L6. Pre-existing issues, outside scope.**
- kpimon panics on division by zero when `ranUeKpi` is empty (the Format 2 loop keeps `/ int32(len(tmpUeKpi))`).
- The NIST generator sets admitted-item criticality to reject, while v03.01 says ignore.
- A subscription for another RAN function gets no answer (`e2-session.cpp:153-158`), where E2AP expects FAILURE `ran-function-id-invalid`.
- When a subscription is refused, the lockstep READY is never sent, so ns-3 waits until the gate's timeout. That is correct behaviour, but worth recording for the P = 150 gate.

## Per-area verdicts (requested focus)

**(a) P = T octets and ordering.**
- No change found in practice.
- Header: same timestamp formula, using the first sample, which is the only sample at K = 1.
- Cell: one item, same builder.
- UE: the union of one sample is that sample's UEs, sorted ascending as before, same chunk halving.
- Indications still go cell first, then UE chunks. SN handling and the lowest-action-ID rule are unchanged.
- Step line `forwarded`: `before + 1 - failed - after` = 1 on success and 0 on failure, same as before.
- Subscription response at 100/100 with kpimon's single F3 action: the same admitted list and no NotAdmitted IE, so the same octets. The trigger and action-definition octets in the *request* do change (08270f → 0063; by-name → by-ID). The agent ignored them before, so the agent's indication octets are unaffected.
- The asn1c patch only touches the extension-index branch (the root path returns at pristine line 139). Every cause the agent emits outside admission (`rc-control.cpp`) is a root value.
- Only latent difference: L1 (duplicate IMSIs).

**(b) Period buffering.**
- No off-by-one: the report fires at `window.size() == K`.
- Alignment = the first sample seen, re-aligned after a gap. A replace, delete, hello, bye or disconnect clears the window.
- Multiple subscriptions: each has its own window, encodes its own report, and is served even if another fails (better than before).
- Issues: H1 (no bound), L3, L4.

**(c) asn1c memory and ownership.**
- None found.
- NotAdmitted IE and items are calloc'd and handed to the PDU, which `ASN_STRUCT_FREE` releases through `finish()`. The IE is appended after the generator's three IEs, which matches the v03.01 order.
- FAILURE builder: the `unsuccessfulOutcome` pointer is owned by the PDU.
- The admission decoders free on both paths; `ASN_STRUCT_FREE` of NULL is safe.
- OCTET_STRING copies in `e2ap-inbound.cpp` are by value.
- The generator's empty-reject path (`reject_size 0`) adds no NotAdmitted IE, so there is no duplicate IE (checked in NIST `encode_e2apv1.cpp:709`).

**(d) Go patch.**
- Config: strict `*uint32` parse, so nil, 0, negative, float and overflow values are fatal at start. `log.Fatalf` before xapp init is acceptable fail-fast.
- The descriptor path `/opt/ric/config/config-file.json` matches the standard dms_cli appconfig mount. kpimon's schema has `additionalProperties: true`, so `controls` is accepted.
- Trigger: a 16-octet buffer is enough (6 needed). Fixture `08270f` equals the old literal and `0063` is the correct APER for 100. Constraint check is done before encoding.
- Format 2 loop: the per-item index `n + i*no_of_ue` is correct for the agent's metric-major layout. Skipping a row only when every record is noValue drops exactly the absent-UE fill, since `ns3.seq` and `ns3.imsi` are records too.
- The Format 1 handler already loops over measData items (K rows).
- Influx rows carry no tags and use `time.Now()`. Blocking writes make same-nanosecond collisions practically impossible. Rows are identified by the `ns3.seq` and `ns3.imsi` fields, as before.
- No new issues beyond L6.

**(e) Installer.**
- Validation: the regex plus `-gt` is correct (bash 64-bit). `jq --argjson` gets validated integers. The ConfigMap probe tolerates a missing map (gives "null null", so it reinstalls).
- Patch order: wrapper.c, then wrapper.h, then the KPM bindings, then control.go, all before the build. The order is fine: control.go needs the new 3-argument `encode_action_Definition` and the new trigger symbol, and both are in place by build time.
- `wrapper.h` backup is not copied back to `install_patch_files` the way `wrapper.c` is (the repo's `wrapper.previous.h` was placed by hand). Cosmetic.
- Issue: L5.

**(f) Spec conformance.**
- RICsubscriptionFailure: RICrequestID, RANfunctionID, Cause, all reject, CriticalityDiagnostics omitted. Matches `e2ap-pdu-v03.01.asn:281-287`.
- Response NotAdmitted: list reject, item ignore. Matches `:240,:261`.
- Causes: `eventTriggerNotSupported` = 17 (extension index 3) for P mod T ≠ 0 or an undecodable trigger; `action-not-supported` = 1 for G ≠ T, non-REPORT actions, missing or undecodable definitions, and when no action is left. Consistent with the requirement.
- Admitted list SIZE(1..), so an empty admitted list correctly becomes a FAILURE.
- KPM: one measData item per granularity period, oldest first. A UE absent from a period is filled with noValue; KPM v03.00 also offers `matchingUEidPerGP` for this, but noValue is accepted. Open deviation: M1.

## The implementer's choices
1. **By-ID Format 3 (determine 3): accept.** The fixture shows the wire definition corrupted after 1024 octets. The M7 capture shows kpimon sends only this action. Cell by-name Format 1 would be about 870 of 1024 octets if it were ever used, which leaves little margin.
2. **Format 2 loop and all-noValue skip: accept** (see d). A UE with only some values missing is still stored, which is correct.
3. **NativeEnumerated APER patch: accept.**
   - Correct per X.691 §11.6/§14.3: "0" plus 6 bits when ≤ 63; otherwise "1", align, a length octet, then the value. It mirrors `aper_get_nsnnwn(pd, 65537)`.
   - `git apply --check` succeeds on the pristine da6f82f2 file.
   - It only touches extension indices.
   - Before the patch, `eventTriggerNotSupported` was written as a 4-bit root-width index that no X.691 decoder reads back.
   - Interop with SubMgr's decoder is an open question (below).
4. **Non-REPORT not admitted: accept.** KPM defines REPORT only.
5. **Reject a hello whose period differs: accept with M2.**
6. **Accounting: partially acceptable.** Exact for one subscription, but cannot be closed from the stats line (L3).
7. **Cell Format 1 not chunked: reject as-is.** Needs the H1 bound.

## Recommended actions
1. H1: bound K at admission (refuse) and cap it in the installer. Add a test: P = 10000 must be refused, not admitted and silently dropped.
2. M1: send cell and UE messages according to the admitted action formats and their own action IDs, or record the deviation.
3. M2: wire `E2_INDICATION_PERIOD_MS` through the run script and docs.
4. L3: split out `droppedBuild` so the identity can be closed.
5. L1: document or restore duplicate-IMSI behaviour for K = 1.

## Metrics
- Type coverage: n/a (C++/Go). Lint not run. Tests not run (no heavy builds). The test file covers tt golden, p1000, p150, g200 and period cases. It does not cover kpimon's per-cell Format 1 definitions (not used in the testbed), large P, or multiple subscriptions with different P.

## Unresolved questions
1. Does the M9 reference digest include agent stats lines or subscription request/response PDUs? The stats line gains keys and kpimon's request octets change at 100/100.
2. Does the L-release SubMgr's E2AP decoder read `eventTriggerNotSupported` (extension index 3) correctly, or map it to the first enum value? Has gate p12 shown the decoded cause on the SubMgr side?
3. What is the intended maximum P for M10, and which refusal cause should apply above it (`function-resource-limit` or `eventTriggerNotSupported`)?
4. Was `kpm-report-period-test` run inside the rebuilt image with the patched asn1c, and with what result?

Status: DONE_WITH_CONCERNS
Summary: P = T octets and asn1c ownership hold up, and the E2AP IE sets match v03.01. But K = P/T has no upper bound: legal periods above about 3.5–5 s are admitted and then dropped (UEs) or never delivered (whole report), and memory is unbounded.

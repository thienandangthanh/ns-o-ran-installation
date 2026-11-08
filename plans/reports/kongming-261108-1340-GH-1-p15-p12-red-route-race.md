# Kongming counsel: the P15 chain is red at p12 because of an rtmgr route race (2026-11-08 13:40 KST)

Runtime: Claude Opus 5.5, as the user's CLAUDE.md requires; no Fable model was used. This counsel is advisory only. Sources were cloned into the scratchpad at the deployed pins: rtmgr `0.9.6` (`go.mod` pins xapp-frame `v0.9.16`) and RMR `4.9.4`.

## TL;DR

- **The cause is a platform race in OSC rtmgr. P15 did not cause it.**
  - At kpimon's registration (147.257), before subscription 23 existed, rtmgr generated a full route table.
  - That stale table was retried to e2term at about 152.06. This was after the subscription's partial update (about 150.06) had installed `mse|12050|23|kpimon` there.
  - RMR replaces every message-type route when a full table arrives. e2term therefore had no 12050 route from about 152.06 to 152.86, and the first indication pair (152.162) fell into that gap.
- **Two triggers lined up.**
  - p12 reinstalls kpimon without restarting rtmgr. From then on, rtmgr got no acknowledgement for any push within its 200 ms wait. Each success or failure verdict was read from freed memory, so retries fired at random.
  - appmgr rejected kpimon's registration with HTTP 400 three times. The registration push therefore landed only 1 s before the subscription push.
- **Recommended guided fix (the one the Failure Protocol allows).** p12 should rebuild RIC route state after each kpimon reinstall, the way every R-gate already does:
  1. Wait until the new kpimon pod logs its own registration.
  2. Restart rtmgr.
  3. Require the route readers to be OK.
  4. Add an informational record of e2term's route at the moment ns-3 starts.

  These are new checks, so ledger row 166 lands first. No existing predicate changes.
- **The re-run needs a VM revert.** /home is 31 GiB, below the 34 GiB guard, so the revert means re-running the full chain at the fix SHA. Any red means a kongming note, then PAUSE T6.
- **Other sites.**
  - r2, r3p and s10 are protected by a structural rtmgr restart after subscription.
  - r0, r1 and e2i start from a fresh rtmgr.
  - M6 and M7 have the same precondition gap, inherited from M3. This is a Stop B item.

## Q1. Root cause, confirmed with corrections

### What the gate waits for
- Between the subscription response and ns-3, p12 waits only for `wait_wire` (`scripts/gates/gate-p12-kpm-period.sh:92-103`). It polls the pcap every 3 s for one RIC subscription request and one successful outcome; it says nothing about routes. ns-3 starts right after that (`:121-125`; gate.log: wire PASS 04:12:30, ns-3 04:12:32).
- `kpimon_at` (`:78-89`) uninstalls and reinstalls kpimon with dms_cli, which recreates its Services. It then waits only for pod Ready and checks the config. It does not restart rtmgr and does not wait for registration.

### Verified source facts at the deployed pins
- **rtmgr 0.9.6 `pkg/sbi/nngpush.go`**
  - `DistributeAll` (`:120-137`) pushes one call_id to every endpoint, one goroutine each.
  - `send_sync` (`:159-176`) retries up to 3 times with 1 s sleeps. Each retry resends the same `policies` pointer, which is the table captured when the distribution started.
  - The retry counter `count` is a package global (`:52`), so the bound is racy.
  - `send_data` sets `Timeout = 200` (`:201`). Its success test is `state != RMR_OK && status != "OK"` (`:204`).
- **xapp-frame v0.9.16 `pkg/xapp/rmr.go`**
  - `SendCallMsg` holds `contextMux` across the whole `rmr_wh_call`, both the send and the 200 ms wait (`:520-522`). Every push in rtmgr is therefore serialized.
  - On a timeout it returns `LogMBufError("SendBuf failed", txBuffer)` (`:524-526`, `:616-622`).
- **RMR 4.9.4**
  - A successful no-alloc send frees the tx buffer (`src/rmr/si/src/sr_si_static.c:641-647`; `rmr_si.c:1109`). `mt_call` returns NULL on a timeout (`rmr_si.c:1166`).
  - So the timeout verdict reads freed memory. An "[tp=0] 0 - state is good" line becomes rtmgr's "successful"; any other garbage becomes "failed".
  - **Consequence:** only `Route Update Status: OK(` is an ack. A `successful` or `failed` line with an empty status means the table was written but not acknowledged within 200 ms.
  - On the receiver, `newrt|start` clones only the meid space (`src/rmr/common/src/rt_generic_static.c:1049`, `:1476-1487`). `updatert|start` clones everything first (`:1141`).

### The timeline (rtmgr log = `evidence/p12/20261108T040312Z/ric-route-logs-after/rtmgr-041130Z.log`)

Before the race:
- rtmgr was last restarted at about 04:00, during r3p. p12 then uninstalled kpimon at 04:03 and reinstalled it at 04:10:50; at 04:11:23 rtmgr was 11 min old and kpimon 32 s old (`bringup-pods-wide-041123.txt`).
- Real acks ran until 140.092 (`:98` is an example). The first unacked verdict came at 141.293 (`:240`).
- From 147.458 (`:345`) to 658.607 (`:2679`), every verdict has an empty status.
- The e2mgr and submgr readers were OK (`rt-readers-ric-041143.txt`), so this is not the stuck-reader hazard.

kpimon:
- appmgr answered its register call with 400 at 92.2, 117.2 and 142.3 (`p12-a-kpimon.log:2,12,21`).
- The 201 and xapp-frame's "Registration done" came at 147.255 (`:28-29`).
- kpimon subscribed at 148.216 and 148.219 (`:35,:43`).
- In the green run of 2026-11-05, registration came 51 s before subscription.

The two tables:
- Call 26 is a full table generated at 147.257 (`:320`). It has 85 entries and no 12050 row; the trigger was the registration (`:247`).
- Call 27 is the partial table generated at 148.219 (`:353`, `:372`). It holds `mse|12050|23|service-ricxapp-kpimon-go-rmr.ricxapp:4560`.
- e2term had already sent the request at 148.220 and returned "Successful Outcome 8" at 148.221. The subscription therefore completed before any route reached e2term.

Both e2term endpoints, `service-ricplt-e2term-rmr-alpha` and `10.101.123.229` (the E2T address, `bringup-e2t-list.json`), are the same single e2term pod. Every push in this span timed out after holding the mutex, and the verdict lines arrive back to back, 200 ms apart, from 147.458 to 153.861. So each table was written at about its verdict time minus 0.2 s.

| ≈ written (s) | e2term endpoint | Table | rtmgr line |
|---|---|---|---|
| 148.659 | svc | full 26, no 12050 row | `:403` |
| 149.059 | IP | full 26 | `:408` |
| 150.059 | svc | partial 27, adds 12050\|23 | `:423` |
| 150.660 | IP | partial 27 | `:429` |
| **152.060** | svc | **retry of full 26** (queued at 149.859, `:416`) **drops 12050\|23** | `:451` |
| 152.162 | none | e2term logs two `RMR_ERR_NOENDPT … 12050` (`e2term-041130Z.log:9-10`); frames 21 and 24 are lost (`p12-a-ind-actions.jsonl:1-2`) | none |
| 152.861 | IP | retry of partial 27 (queued at 151.860, `:444`) restores the row | `:463` |
| 154.149 | none | the next pair is delivered (`p12-a-ind-actions.jsonl:3`) | none |

### Corrections to the brief
- "Call 26 to e2term FAILED at 148.859, and its retry succeeded at 152.260" is not about delivery. Both lines have an empty status, so both are unacknowledged writes. The retry at 152.26 means the stale table was written to e2term a second time, after the partial.
- "The table goes 85 → 84 on the subscription delete" is wrong. No full table ever carried subscription 23's routes; they exist only in partial 27. The drop from 85 to 84 is in the meid map: the second `mme_ar` row for en_gnb_…02 was removed. The payloads differ by 52 bytes (5028 vs 4976, `:646`).
- This was not a table swapped mid-load. RMR rolls tables atomically (`rt_generic_static.c:458`). The active table simply lacked the row.

### Is P15 the cause? No.
- The P15 kpimon patch (`control.go.format1-per-cell.patch` at Testbed `cb69741`) touches only the encoders, `sendSubscription` (it now handles the error from `encode_actionsToBeSetup`) and `initializeNode`. The registration gate and the 5 s `monitorE2Nodes` ticker are older (`control.go.patch`, last changed in `4b4a61a`).
- Both actions sit in one subscription with one instance (23). That gives the same 7 route rows as before P15 (`:372`).
- The appmgr 400×3 pattern predates P15. Run `evidence/p12/20261103T090413Z` had it too, subscribed 4 s after registration, and stayed green.
- What actually differed:
  - the overlap of the registration push with the subscription push (1 s here, 51 s on 2026-11-05);
  - an rtmgr that no longer received acks after the gate's own kpimon replacement;
  - timing luck: the gap ran from 3.84 to 4.64 s after the response, and the first indication came at 3.94 s. A 5.5 s gap would have missed it.
- The question of a 5.5 s versus 3.9 s gap is a red herring. It moves with `wait_wire`'s 3 s poll phase.

### Not established
- I could not tell from the logs why rtmgr stopped receiving acks at 141.293. The onset follows the dms_cli replacement of kpimon without an rtmgr restart, which matches the documented hazard that rtmgr keeps stale endpoints. A fresh rtmgr does get real acks: the six `rtmgr_push_acked` lines in this chain's i2, e2i and r3p evidence all read `Route Update Status: OK(`.

### A second hazard in the same run
- After p12-c's kpimon uninstall began (about 04:20:58, about 658 s), one push to the removed kpimon held `contextMux` until 1141.945, when it ended with `tp=110` ETIMEDOUT (`:2679` → `:3808`, `:3811`). That blocked all route distribution for 483 s.
- p12-c's registration (1055.171, `:3280`), its subscription (1110.174, `:3571`) and its delete (1112.268, `:3614`) all happened inside that freeze.
- p12-c passed only because it judges no indications.

## Q2. The guided remedy

**Do (c): the precondition fix. Do not do (a).** Option (b), a wait for e2term's route, goes in only as an informational record.

- **(a) Re-run alone: reject.**
  - It is not allowed on this VM: /home has 31 GiB free, below the 34 GiB start guard for p12 (phase-10 `:142`, `:379`), and p12 itself consumed 9 GiB (`host-disk.tsv`).
  - It would spend a full chain on luck and leave the race in the M10 end run.
  - Ruling item 2 (an out-of-budget re-run) applies to M7 only (`decisions-261107-0045` item 2).
- **(b) A judged wait for the subscription's route in e2term before ns-3: insufficient alone and riskier.**
  - e2term's `/opt/e2/router.txt.stash` holds only the last table received, and partial updates overwrite it.
  - On an rtmgr that gets no acks, a stale retry can still land after the check passes. In this red the stash showed the row from about 150.06 to 152.06.
  - Proving that rtmgr is quiescent would mean parsing verdict lines that are themselves garbage.
  - It is not a weakening, but it adds an unvalidated judged check at a moment when a second red means PAUSE.
- **(c) Recommended: re-establish route state after each reinstall, using proven helpers only.**
  - It removes both triggers: the rtmgr that gets no acks or is frozen, and the overlap between registration and subscription.
  - It is the precondition `rc_ric_reset` already gives every R-gate (`scripts/gates/rc-lib.sh:244-283`), and the standing P3 rule: an xApp replacement is followed by an rtmgr restart.
  - It hides no defect in the system under test. P15's checks all passed: per-cell Format 1 plus Format 3, and format equal to action format, 10/10 per action. Influx differs in 0 fields on the 90 rows present.
  - The platform defect stays visible through the Stop B record.
  - Patching rtmgr, submgr or xapp-frame is out of scope (goal-packet: upstream work and RMR root causes are out of scope).

### Exact steps
1. **Docs commit first: ledger row 166 and a phase-10 section "P15 chain red #1: p12, and the guided fix".** The section carries the cause (this note), the commits under test, the red evidence and the outcome rule below.
   - Draft row 166:
     - **Site:** gate p12 `kpimon_at` (`gate-p12-kpm-period.sh:78-89`), sites a, b and c.
     - **Old:** none. After a reinstall, only pod Ready and the config periods were judged.
     - **New:** `p12_<tag>_kpimon_pod_logged_its_registration`, `p12_<tag>_rtmgr_restarted_after_kpimon_registration`, `p12_<tag>_route_readers_ok_after_rtmgr_restart`, plus the informational `p12_a_ric_route_record_informational`.
     - **Why not weaker:** every old predicate is unchanged byte for byte, the new checks add conjuncts only, and the precondition is the one `rc_ric_reset` gives every R-gate.
     - **Contract change:** No.
2. **One harness commit, touching `gate-p12-kpm-period.sh` only, so the other chain steps' code stays byte-identical.** In `kpimon_at`, after the config check:
   - Poll `kc -n ricxapp logs "$KPIMON_POD"` until xapp-frame's `Registration done, proceeding with startup` appears, bounded at 300 s. The observed wait was about 65 s after Ready.
     - Do **not** use appmgr's `/ric/v1/xapps` (`_xapp_listed_ok`, `ts-lib.sh:290`). dms_cli uninstall never removes the entry and kpimon never deregisters, so a stale entry with the same name, IP and port satisfies it before the new pod registers.
   - Run `ric_restart_rtmgr` (`bringup.sh:209-221`).
   - Run `rt_reader_ok` for kpimon in ricxapp, then for e2mgr and submgr (`bringup.sh:231-271`).
   - Write the comments as invariants with no plan IDs. For example: "a dms_cli reinstall replaces kpimon's Services; rtmgr's pushes then go unacknowledged, and a retried table generated before kpimon's subscription can reach e2term after the subscription's route update and drop it (seen 2026-11-08); restart rtmgr once the new pod has registered, as rc_ric_reset does".
3. **The informational record, never judged (`record`, as row 162 does for M7).**
   - Just before `ns3_start` in a: e2term's stash (read as `rc-lib.sh:179-180` does) holds `mse|12050|<instance>|service-ricxapp-kpimon-go-rmr`.
   - After the drain in a: rtmgr, e2term and submgr logs since `CAP_T0` saved to the evidence, plus counts of `Status: OK(` lines against empty-status lines.
   - Guard each collection with `|| true`.
4. **Static checks and review.** Run `bash -n`, shellcheck and `scripts/gates/lint.sh`. Then a Codex read-only review of the diff (disclosed), and a follow-up review of any change Codex drives.
5. **New frozen checkout at the fix SHA** (locked worktree, `chmod a-w scripts`). Remove the 1084f0f2 checkout (2.2 GiB) once its evidence is archived.
6. **Entry, as in the P9 guided fix.**
   - Host IO pressure: full avg60 ≤ 5 and avg300 ≤ 10, read twice 5 min apart.
   - Memory pressure and MemAvailable as in the P9 guided fix; no cargo or rustc processes.
   - Revert to `f7-rerun-green`, then the orphan-overlay check and the VM etcd quiet window.
   - Re-copy and verify the asn1-indep tarball.
7. **Chain at the fix SHA:** M2, M3, M4, M5, M6, M7, I0, I2, e2i, r3p single, then p12 after a /home ≥ 34 GiB check. Each step gets a fresh log directory.
8. **Outcome rule, written down before the run.**
   - **Green:** every step exits 0 with no failed check. That includes p12 a's unchanged predicates (kpimon indications equal wire indications, 20/20; Influx equals the trace at every seq) and the new checks.
   - **Any red step:** a kongming note, then **PAUSE T6**. That includes a new-check red: no registration line within 300 s, rtmgr not coming back, or a stuck reader. P15's budget is then spent.
   - The M7 route-record re-run (ruling ii) still applies to M7 only.
   - T5 applies only if this remedy fails (ruling item 3).

### What to record
- Cite this note's timeline table and source lines.
- Note that `ric-route-logs-after/` was collected by hand after the gate, at 13:31 KST with `--since` 04:11:30Z. It is raw, ignored by git and contains no tokens.
- Ledger row 166 and the fix SHA.
- The re-run evidence.
- In the green record, e2term's 12050 row and the ack counts from the informational record.

## Q3. The other sites

| Site | rtmgr state at subscription | Exposure |
|---|---|---|
| p12 a/b/c | Not restarted after the gate's own dms_cli reinstall (this red); c ran entirely inside the 483 s freeze | Fixed by the remedy |
| r2, r3p, s10 (`ts-rung-lib.sh`) | `rc_ric_reset` before bring-up, plus an rtmgr restart **after** every agent is subscribed (`ts-rung-lib.sh:41` → `ts-lib.sh:371-372`). A fresh rtmgr re-pushes every subscription route. | Structurally protected, even for s10's `--every-seq` |
| r0, r1, e2i | `rc_ric_reset` (pod delete; Services kept) and a fresh rtmgr before bring-up (`gate-r0:167`, `gate-r1:136`, `gate-e2i-interop.sh:83`) | Low; only an rtmgr that degrades mid-run would expose them |
| M6, M7 (and M3) | The same rtmgr ran from M3 to M7, 81 and 83 min old at M6 and M7, with kpimon created in M3 (`m6/…/bringup-pods-wide-030729.txt`, `m7/…-030938.txt`). M3's dms_cli reinstall has no rtmgr restart (`gate-m3-xapps.sh:137-159`). | Same precondition gap. The trigger would be the E2 Setup full table against the subscription 0–5 s later. Their judges mostly tolerate a lost first period (three picks with fallback; M3 has only `first_indication_logged`). Green in this chain. |
| P11 / M10 end run | Inherits the per-gate behaviour | p12 is covered by the fix; the M3→M6/M7 gap remains |

### For Stop B (record, not blocking)
1. **L-release finding.** rtmgr 0.9.6 with xapp-frame v0.9.16 has these route-distribution defects:
   - pushes are serialized, with 200 ms waits;
   - timeout verdicts are read from freed memory;
   - retries resend stale tables and can undo a newer partial update;
   - the retry bound is racy;
   - one send to a removed xApp can freeze all distribution (483 s, ETIMEDOUT);
   - the subscription completes before e2term holds its route.

   All of this is out of scope to fix.
2. **The M3→M6/M7 precondition gap.** Choose between adding the same precondition after M3's kpimon reinstall (its own ledger row, before the M10 end run) and accepting it with a record.
3. **`rtmgr_push_acked`** (`rc-lib.sh:122-135`) accepts empty-status timeouts. Tighten it to `Route Update Status: OK` (stricter, needs a ledger row). It is supporting evidence only today.
4. **p12-c.** Its subscription routes reached e2term only after the delete. It is safe now only because c judges no indications; the fix supplies the precondition.
5. **appmgr 400×3 after a dms_cli reinstall.** Seen on 2026-11-03 and 2026-11-08; the cause is not verified.
6. **The extra revert cycle.** It costs about 3 h and a fresh overlay, on top of the planned P15→D-06b-1 revert.

## What to avoid
- Do not add a `sleep` before ns-3, and do not make kpimon delay its subscription. Both are timing patches, and the gap can open anywhere.
- Do not treat a `successful` rtmgr line as a delivery, and do not use appmgr's list as proof of a new registration.
- Do not extend M7's re-run policy (ii) to p12 without a user ruling.
- Do not touch M3, M6 or M7 inside this fix; that is scope creep with PAUSE risk. Record them for Stop B.
- Do not edit scripts under a running chain, and do not run p12 or build kpimon below 34 GiB free.

## Assumptions
- **The deployed versions are rtmgr 0.9.6, xapp-frame v0.9.16 and RMR 4.9.4.** Confidence high: the earlier VM check in memory, plus the exact 200 ms cadence and the "[tp=0] <garbage>" verdicts. A different rtmgr image would change the source citations, not the log-derived timeline.
- **Both e2term endpoints reach the one e2term pod.** Confidence high: there is one e2term pod and the E2T address is 10.101.123.229.
- **Write time ≈ verdict time − 200 ms.** Confidence medium-high: the mutex is held through send and wait, and the verdicts are contiguous. A direct receiver-side record would settle it; step 3 adds one.
- **A fresh rtmgr after registration restores real acks and ends the overlap.** Confidence medium-high: six real-ack lines appeared after rtmgr restarts in this chain. If the re-run's informational record shows empty-status verdicts after the restart, the precondition is not enough; that is a PAUSE and the controller should treat it as T5.
- **The cause of the ack outage and of the appmgr 400s is unknown.** Confidence low. Neither changes the remedy.

Status: DONE
Summary: The cause is confirmed with corrections. A stale full-table retry from rtmgr 0.9.6 (generated at kpimon's late registration) reached e2term after the subscription's partial update and dropped the 12050 route for 0.8 s. This is a platform race, not P15. The one guided fix is p12-only: after each kpimon reinstall, wait for the pod's registration, restart rtmgr and require the readers OK (ledger row 166 first), plus an informational e2term route record. Then revert and re-run the full chain; any red is PAUSE T6.
Concerns: The re-run costs a full chain (about 3 h) because /home is at 31 GiB. Why rtmgr's acks stopped is unexplained. M6 and M7 carry the same precondition gap into the M10 end run (Stop B).

# Research: NIST AD patch wall-clock behaviour (Q6) and E2AP control ACK/FAILURE semantics (Q7)

Date: 2026-10-22. Answers open questions 6 and 7 of `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md` §9. Read-only work: no VM, no commits. This file is the only one written.

## Bottom line

- **Q6. NIST's AD patch does not change AD's window or its schedule.** It ports AD from InfluxDB v1 to v2. The predict window stays 1600 ms of wall clock, the job still runs every 0.5 s, and the training windows are unchanged. AD reads `UEReports`, which kpimon never writes. NIST feeds that measurement from a replay loader that stamps rows with `now()`.
- **Q6, new finding (static reading, not run live).** The patch leaves `ad_model.py` untouched. Its InfluxQL query in `CAUSE.cause` now goes through the patched Flux `query()`, which always returns a DataFrame. The next line, `if normal:`, then raises `ValueError` on the first predicted anomaly. Nothing catches it, so the process exits before `msg_to_ts` runs. As deployed, NIST's AD probably never sends RMR 30003. This makes G5 stronger: real AD cannot drive any rung, not just a repeatable one.
- **Q7. The v02/v03 prose was not reachable.** I read two texts:
  - **v08.00**: O-RAN.WG3.TS.E2AP-R004-v08.00, a local converted copy.
  - **v04.00**: O-RAN.WG3.E2AP-R003-v04.00, published as ETSI TS 104 039 V4.0.0 (2024-10), downloaded from etsi.org.

  §8.2.4 (the RIC Control procedure) is word-for-word identical in the two (difflib ratio 0.9985; the only difference is a PlantUML `skin rose` artifact). The change history, which appears in both documents, lists no RIC Control change after v02.02. So the v03.01 prose is almost certainly the same as v04.00. That is an inference from the history, not a reading of v03.01. rc's ASN dates from about v02.01, which is before the v02.02 "Clarification to … RIC Control", so its prose may differ.
- **Q7, a correction to the plan's wording.** The spec does not say "accepted and executed or scheduled". It says the node acknowledges once it "has successfully processed the requested RIC Control procedure action". FAILURE means the request "has failed to be executed". The plan's ACK at the barrier, after validation and commit with d = 0, is a defensible reading of "processed", but "scheduled" is our gloss.
- **Q7, a problem with the cause value in the D2 options.** `control-timer-expired` is defined as a request "received by E2 Node after the associated RIC Time to Wait timer had expired". That timer belongs to a RIC Call Process ID from an INSERT action, and rc never sends one. For a late control, `control-failed-to-execute` (or `system-not-ready`) matches the spec text. `control-timer-expired` does not.

---

## Q6: the AD xApp under the NIST patch

### Provenance

- The installer is `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/additional_scripts/install_xapp_anomaly_detection.sh`. It clones AD at `:65`, applies 4 patches at `:87,95,103,111`, injects the token at `:116`, and starts the loader at `:228`.
- AD is pinned to `l-release` @ `f9f97b8` (`commit_hashes_l_release.json:14`). This equals `~/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-ad` HEAD, so the upstream line numbers below are the deployed base.
- The patches are in `…/install_patch_files/xApps/ad/`: `setup.py.patch`, `src/ad_config.ini.patch`, `src/database.py.patch` and `src/insert.py.patch`. **`src/main.py` and `src/ad_model.py` are not patched.**

### What the patch changes and what it keeps

| Aspect | Upstream (`ric-app-ad` @f9f97b8) | After the NIST patch | Changed? |
|---|---|---|---|
| Client | influxdb v1 `DataFrameClient`, InfluxQL | `influxdb_client` v2, Flux (`database.py.patch:10-11,77-80`) | yes |
| Endpoint and auth | `ricplt-influxdb.ricplt:8086`, user/password | `r4-influxdb-influxdb2.ricplt:80`, token, org `influxdata`, **bucket `kpimon`** (`ad_config.ini.patch:13-17`) | yes |
| Measurement read | `UEReports` (`ad_config.ini:24`) | `UEReports` (kept; context line `ad_config.ini.patch:20`) | no |
| **Predict window** | `where time>now()-1600ms` (`database.py:88`) | `range(start: -1600ms)` + `filter(_measurement == UEReports)` + pivot (`database.py.patch:133,137`) | **no** (same 1.6 s wall window) |
| Training window | `time<now()-5m and time>now()-75m` (`database.py:90`) | `range(start: -75m, stop: -5m)` (`database.py.patch:126`) | no |
| Validation window | `time>now()-5m` (`database.py:92`) | `range(start: -5m)` (`database.py.patch:131`) | no |
| **Schedule** | `schedule.every(0.5).seconds.do(predict, self)` (`main.py:44`) | unchanged (main.py not patched) | **no** |
| Row index | v1 frame keyed by time | `_time` set as the index (`database.py.patch:194-195`) | equivalent |
| `query()` on error | returns `False` | returns an **empty `pd.DataFrame()`** (`database.py.patch:196-198`) | yes (see the defect below) |
| `schedule` dependency | `schedule>=0.0.0` | same, unpinned (`setup.py.patch:18`), so the latest version is used at build time | no |

### What AD reads, compared with what kpimon writes

- AD reads bucket `kpimon`, measurement `UEReports`. The features it needs are `DRB.UEThpDl`, `RF.serving.RSRP`, `RF.serving.RSRQ`, `RF.serving.RSSINR`, `RRU.PrbUsedDl` and `ue-id`, plus the label `Viavi.UE.anomalies` (`ad_config.ini:27-35`).
- kpimon writes org `influxdata`, bucket `kpimon` (NIST `kpimon-go/control/control.go.patch:162,171`), measurements **`UeMetrics`** and **`cellMetrics`** with `SetTime(time.Now())` (`ric-app-kpimon-go` @8bbbbbb `control/control.go:955,959,976,980`).
- So the bucket and org match, but the measurement does not. **AD never sees kpimon's data.** This is the same kind of mismatch as G1 for QP. The field-level match was not checked.
- What AD reads in the NIST deployment is the replay loader `insert.py`, which the installer starts inside the pod (`install_xapp_anomaly_detection.sh:228`). The loader:
  - writes `src/ue.csv` to `UEReports`;
  - stamps each `measTimeStampRf` group with `datetime.now()` at 1 ms spacing, then sleeps 0.7 s (`insert.py.patch:67-76`; upstream `insert.py:66-72`).
- The UE ids are the 10 synthetic VIAVI names (`Car-1`…`Train passenger 3`). They are not ns-3 IMSIs.
- `ue.csv` has 10 000 rows in 3 187 groups, so one replay pass takes about 37 min. A 1.6 s window holds about 2 groups, roughly 6 rows.

### What AD sends to TS on RMR 30003

- **When it sends.** `predict_anomaly` builds the payload only for rows that the model flags and that `CAUSE` keeps as anomalous (`main.py:102-110`). `msg_to_ts` sends it with `rmr_send(val, 30003)` (`main.py:82-83,120`).
- **Payload.** The payload is a JSON array of `{"ue-id": <string>, "time": <Influx _time as epoch ms>, "Degradation": "<Throughput|RSRP|RSRQ …>"}` (`main.py:106-110`; `to_json(orient='records')` writes epoch milliseconds by default).
- **Route.** Static seed `rte|30003|service-ricxapp-trafficxapp-rmr.ricxapp:4560` (`local.rt:2`, `Dockerfile:33-34`). The descriptor declares tx `TS_ANOMALY_UPDATE` and rx `TS_ANOMALY_ACK` (`xapp-descriptor/config.json:26-27,43-44`).
- **TS side** (`ric-app-ts` @19e169b):
  - `ad_callback` keeps only `"ue-id"` strings (`ts_xapp.cpp:264-284`);
  - it acks with 30004 (`:797`);
  - then it sends `{"UEPredictionSet": [...]}` to QP on 30000 (`:799`, `:775`);
  - the callback is registered at `:903`.

  NIST rewrites TS's route back to AD to the FQDN form (`install_xapp_traffic_steering.sh:70-83`).
- **Draining.** AD reads 30004 and A1 20010 only by draining its RMR queue once after each send (`main.py:125-130`).

### Defect: NIST-patched AD most likely crashes before it ever sends 30003

1. `predict_anomaly` calls `cp.cause(df, db, threshold)` as soon as the model flags any row (`main.py:102-103`).
2. `CAUSE.cause` builds an **InfluxQL** string, `select * from UEReports where "ue-id" = '…' and time<now() and time>now()-20s` (`ad_model.py:102`). It passes the string to `db.query`. The patch does not touch this file.
3. The patched `query()` sends that string to the Flux query API. The query either fails or returns a frame. Either way the result is a `pd.DataFrame`: the error path returns an empty one (`database.py.patch:174-198`).
4. `if normal:` (`ad_model.py:104`) then evaluates the truth value of a DataFrame. pandas always raises on that: `ValueError: The truth value of a DataFrame is ambiguous`, whether the frame is empty or not. I checked this on pandas 3.0.6; the behaviour is long-standing.
5. Nothing catches the error. `schedule.run_pending()` lets job exceptions propagate (`main.py:45-46`), and ricxappframe 3.2.2 `Xapp.run()` calls the entrypoint inline (`xapp_frame.py:1024-1028`, read from the PyPI wheel). The process exits, and `msg_to_ts` (`main.py:82-83`) is never reached.
6. Kubernetes then restarts the container. That kills the loader, which was started with `kubectl exec`, and drops the trained model, because the image has no `src/model` (`main.py:59-62`). After the restart AD either waits for training data or logs "No data in last 1 second" forever.

Confidence: high for steps 1 to 5, which follow from the code and from pandas semantics. Step 6 is inference. Neither has been run live. The model flags anomalies readily: the contamination search covers 0.01 to 0.49 (`ad_train.py:83`), and 2 568 of the 10 000 `ue.csv` rows carry an anomaly label.

### Every wall-clock dependency in AD (NIST build)

| # | Dependency | Value | Source |
|---|---|---|---|
| 1 | Predict schedule | every 0.5 s. The `schedule` library sets `next_run = now() + 0.5 s` after the job finishes (checked in `schedule` 1.2.2 `_schedule_next_run`), so the real period is 0.5 s plus the job's run time | `main.py:44` |
| 2 | Scheduler loop | `while True: schedule.run_pending()`, a busy spin with no sleep | `main.py:45-46` |
| 3 | Predict window | Influx `_time` ≥ now − 1600 ms (wall) | `database.py.patch:133` |
| 4 | No-data back-off | `time.sleep(1)`, so the period becomes about 1.5 s plus the query | `main.py:80-81` |
| 5 | Training data | [now − 75 min, now − 5 min], ≥ 1000 rows, retry every 120 s. Runs at every container start, because no model is shipped. At the loader's rate (about 3.1 rows per 0.7 s), the first training is possible about 8.7 min after the loader starts, rounded up to the 120 s retry grid | `database.py.patch:126`, `ad_train.py:53-58`, `main.py:59-62` |
| 6 | Validation data | [now − 5 min, now], ≥ 300 rows, retry every 60 s | `database.py.patch:131`, `ad_train.py:62-68` |
| 7 | Cause window | InfluxQL `now()-20s` per anomalous UE (broken under the patch, see above) | `ad_model.py:102` |
| 8 | Input timestamps | loader stamps rows with `datetime.now()` and paces at 0.7 s per group | `insert.py.patch:67-76` |
| 9 | Connect probe and retry | `range(start: -1m)`; on failure `sleep(120)` | `database.py.patch:85-98` |
| 10 | AD output rows | written to measurement `AD`, indexed from the row's wall `_time` | `main.py:111-113` |
| 11 | Non-determinism unrelated to wall clock | `RandomizedSearchCV(n_iter=50)` has no `random_state`; only the IsolationForest is seeded (`random_state=4`) | `ad_train.py:87-88` |

Side note: `change_threshold` assigns to a local variable, so an A1 threshold update never takes effect (`main.py:166-170`).

**Implication for the plan.** G5 stands, and it is stronger than stated. Stock NIST AD is wall-clock driven (items 1 to 8). It reads synthetic data, not ns-3's. As a static reading, it never emits 30003. A harness-driven 30003 stub remains the only usable trigger for R2/R3. If real AD is ever wanted, it needs three things:
- a fork that fixes `ad_model.py`;
- a mapping from `UeMetrics` to `UEReports`;
- a decision on the 1.6 s window, the same decision G2 needs for QP.

---

## Q7: E2AP RIC Control ACK/FAILURE semantics across versions

### Which E2AP our stack carries

- **Every v02.00+ module uses OID `version2`.** The OID is `… e2(1) version2(2) e2ap(1) …` in v04.00 (ETSI text) and v08.00 (local copy). v01.00 uses `version1` (`ric-plt-e2/RIC-E2-TERMINATION/3rdparty/asnTextFiles/e2ap-v01.00.00.asn:9`). The change history logs "Change to ASN.1 version" at v02.00. So `version2` in an ASN file only proves "E2AP v02.00 or later".
- **rc** (`ric-app-rc` @a2282ee `e2ap/e2ap.asn:10`, `version2`) contains TransactionID, RICsubscriptionDeleteRequired and E2RemovalRequest. E2 removal is a v02.01 feature. It has no RICsubscriptionModification or RICQuery (v03.00 features). It also lacks `CriticalityDiagnostics` in `RICcontrolFailure-IEs` (`:975-982`) and the cause `ric-subscription-end-time-expired` (`:271-287`). **This places it in v02.01–v02.03, most likely v02.01.** That is before the v02.02 RIC Control clarification. The exact version is not proven.
- **NIST e2-interface** (`sim/e2-interface` @da6f82f, `e2sim/asn1c/asn/v03/e2ap-*-v03.01.asn`, generated code says `found in "e2ap-ied-v03.01.asn"`) is v03.01. Its `RICcontrolFailure-IEs` carries `CriticalityDiagnostics` as an extension (`e2ap-pdu-v03.01.asn:776-784`). The ack enum is `{noAck, ack, ...}` (`e2ap-ied-v03.01.asn:395-399`). Per `docs/deployment-guide-l-release.md:186`, our agent is built in this tree.
- **e2term** is generated from `e2ap-v2.asn`; its enum is `{noAck, ack}` (`ric-plt-e2/…/3rdparty/oranE2/RICcontrolAckRequest.h:4,22-24`).
- **Wire compatibility.** The ACK and FAILURE IE sets match across rc, v03.01, v04.00 and v08.00. FAILURE adds an optional CriticalityDiagnostics after the extension marker, so the encodings interoperate.
- **v01 differs.** v01.00 had `{noAck, ack, nAck, ...}` (`e2ap-v01.00.00.asn:1137-1142`); v02.00 removed `nAck`. The journal's "the ASN enumeration is identical" holds for v02 to v08, not v01. Jira RIC-722 confirms the removal.
- Aside: the worktree's legacy `oran-e2sim` submodule still contains v01.00 code (`oran-e2sim/e2sim/src/ASN1c/RICcontrolAckRequest.h`: `nAck = 2`). It is not the agent built for this port.

### The text I read

**Primary texts.**
- (1) O-RAN.WG3.TS.E2AP-R004-v08.00, local converted markdown at `~/Documents/UCLAB/papers-main/journal/3-oran-survey/converted/O-RAN Working Group 3 - 2025 - O-RAN E2 Application Protocol (E2AP) 8.0/…md` (§8.2.4 at lines 834-920).
- (2) ETSI TS 104 039 V4.0.0 (2024-10), "(O-RAN.WG3.E2AP-R003-v04.00)", from https://www.etsi.org/deliver/etsi_ts/104000_104099/104039/04.00.00_60/ts_104039v040000p.pdf (sha256 `03a20214…ba2a55`, 109 pages).

§8.2.4 matches word for word between (1) and (2).

**§8.2.4.2 Successful operation**, quoted from v04.00; v08.00 is identical:
> "When the Near-RT RIC sends the RIC CONTROL REQUEST message and the optional RIC Control Ack Request IE has been set to "Ack", or is not present, the Near-RT RIC, it shall start the timer TRICcontrol."
>
> "If the RIC CONTROL REQUEST message contains the optional RIC Control Ack Request IE set to "Ack", or if the optional RIC Control Ack Request IE is not present, and the E2 Node has successfully processed the requested RIC Control procedure action, then the E2 Node shall respond with the RIC CONTROL ACKNOWLEDGE message."
>
> "If … set to "NoAck" and the E2 Node has successfully processed the requested RIC Control procedure action, then the E2 Node shall not send the RIC CONTROL ACKNOWLEDGE message."
>
> "Upon reception of the RIC CONTROL ACKNOWLEDGE message, the Near-RT RIC shall stop timer TRICcontrol and terminate the RIC Control procedure. The Near-RT RIC may use the information contained in the optional RIC Control Outcome IE to determine subsequent actions."

**§8.2.4.3 Unsuccessful operation.** FAILURE "with an appropriate cause value" is required in six cases:
- an invalid RIC Call Process ID;
- a Call Process ID whose RIC Time to Wait timer had expired;
- "If the E2 Node fails to execute the requested RIC Control procedure E2SM specific action";
- an E2SM encoding or functional error;
- an unknown RAN Function ID;
- an unsupported control action.

In each case the RIC "shall stop timer TRICcontrol, if running, and terminate the RIC Control procedure" and "may use … Cause IE and optional RIC Control Outcome IE".

**§8.2.4.4 Abnormal conditions.**
> "If timer TRICcontrol was set … and there was no response from the E2 node before the timer expiry, the Near-RT RIC shall send an ERROR INDICATION with the appropriate value for the Cause IE."

**§9.1.1.9 ACKNOWLEDGE and §9.1.1.10 FAILURE.**
- ACKNOWLEDGE: "sent by the E2 Node to inform the Near-RT RIC that the RIC CONTROL REQUEST message was received and to provide information on the outcome of the request". RIC Control Outcome is **O**.
- FAILURE: "…has failed to be executed". Cause is **M**; RIC Control Outcome and Criticality Diagnostics are **O**.

**§9.2.21.** RIC Control Ack Request is "ENUMERATED (NoAck, Ack, …)"; it "defines whether and when the RIC CONTROL ACKNOWLEDGE message shall be sent by the E2 Node".

**§9.2.1 cause values.**
- `Control timer expired`: "RIC Control Request received by E2 Node after the associated RIC Time to Wait timer had expired".
- `Control failed to execute`: "Requested control procedure initiated by RIC Control Request failed to be executed in the E2 Node".
- `System not ready`: "RAN Function is not ready to receive RIC Subscription or RIC Control message".

**Secondary corroboration for v2.0.**
- O-RAN SC Jira RIC-722, read through the REST API (`lf-o-ran-sc.atlassian.net/rest/api/2/issue/RIC-722`). It is the e2mgr "base support for E2APv2.0" ticket, status Done. It says: "RIC Control request has one less value in its IE "RIC Control Ack Request" (ENUMERATED (NoAck, Ack, -NAck-…))". It also says E2APv2.0 "Clarified role of (optionally requested) RIC CONTROL ACKNOWLEDGE and (mandatory) RIC CONTROL FAILURE messages … FAILURE to be sent if control timer on E2 expired, or if E2 node fails to execute RIC CONTROL request."
- Slide 7 of Czichy and Hiltunen, ONE Summit NA 2021, `static.sched.com/…/ONeS_NA_2021_…lessons_learned_near_rt_RIC_and_xApps.pdf`, carries the same text and marks RIC Control "Updated#" in v2.0.

These are maintainer-level sources (the OSC RIC PTL), but they are not the spec.

### Change history: did the RIC Control text change between v02 and v04/v08?

The annex appears in both v08.00 (lines 8046-8200, at CR granularity) and v04.00 (Annex A, at version granularity). The two agree. Only two entries touch RIC Control:
- **v02.00.04 (2021-06-09):** "NOK.AO-2021.05.26-WG3-CR-0003-E2AP-RIC control", which went into **v02.00** (v08 line 8063).
- **v02.02.02 (2022-03-25):** "NEC-2022.02.28-WG3-CR-0002-E2AP- RIC CONTROL FAILURE -v03", which went into **v02.02**. That release is summarised as "Clarification to RIC Service Update, RIC Control" (lines 8080, 8087).

From v02.03 to v08.00, no CR or summary names RIC Control:
- v03.00 added Subscription Modification and Query;
- v03.01 was a drafting-rules alignment;
- v04.00 clarified E2 node components;
- v05 to v08 added Audit, State Control, Assistance and resource status.

What this means for each version:
- **v03.01** (NIST e2-interface, our agent): its §8.2.4 text is, by this history, the v04.00 text quoted above. High confidence, but not read directly.
- **v02.01-era rc ASN**: it predates CR-0002 and the v02.02 clarification. Its §8.2.4 prose could be worded differently, possibly only on FAILURE. I could not read it.

### Not reachable, and why

- **Local search.** Under `~/Documents`, `~/Downloads`, `prior-works`, `discussions` and `OSC-repos` (with `fd`; no system-wide find), the only E2AP spec is the v08.00 conversion. There is no v02.xx, v03.xx or v04.xx PDF or DOCX.
- **The O-RAN portal.** `specifications.o-ran.org` is a Blazor app; a download requires registering and accepting a licence. I did not submit personal data.
- **Web search.** No public mirror of v02.xx or v03.xx turned up. ETSI TS 104 039 V4.0.0 is the earliest freely published E2AP text.

### What the ASN alone proves (rc v02.0x, v03.01, e2term `e2ap-v2`)

- RIC Control Ack Request is optional in the request and is `{noAck, ack, …}`. rc **omits** it: `e2ap/wrapper.c:67,84,98,120` encodes only RequestID, RANfunctionID, Header and Message.
- ACK = RequestID (M), RANfunctionID (M), CallProcessID (O), **ControlOutcome (O)**.
- FAILURE = the same, plus **Cause (M)**. v03.01 also has CriticalityDiagnostics (O, extension).
- The cause enumeration (`CauseRICrequest`) contains `control-message-invalid`, `ric-call-process-id-invalid`, `control-timer-expired`, `control-failed-to-execute`, `system-not-ready` and `unspecified` in both rc and v03.01.
- The ASN proves nothing about *when* an ACK may be sent, or about what "processed" means. That is prose only.

### Consequences for the plan (from the v04.00/v08.00 text)

1. **Ack Request absent means ACK on success, so every successful control gets an ACK.** rc never sets the IE.
   - rc's TRICcontrol is `controlAckTimer = 2` s of wall time (`xapp-descriptor/config.json:72`, `control/rcControl.go:156-196`). On expiry rc only logs; the ERROR INDICATION that §8.2.4.4 requires is a comment (`rcControl.go:179`).
   - Under pacing, the ACK leaves within milliseconds of the barrier read, so the timer does not matter. In free-run, a control that waits for ns-3's step can exceed 2 s (3.2 s at the default config). rc then logs a spurious "timer expired", which is harmless.
   - rc keys the timer by `aRequestSN` (`:310`) but the response by `InstanceId` (`:334,376`). This may be the double increment in G9. It was not checked further.
2. **The ACK wording.** "Successfully processed" is undefined beyond that phrase. ACK at the barrier, after validation and commit with apply at the same sim instant (D5 d = 0), fits it. With d = 1 the fit is weaker: the action has not started, and §8.2.4.2 ends the procedure on ACK. **There is no FAILURE after an ACK for the same RIC Request ID.** This bears on the D5 skeptic's assumption A4 (`counsel-261022-1544-GH-1-d5-delay-skeptic.md:235`); the text confirms it.
3. **The D2 cause value.** Options (a) and (b) in journal §6 (lines 164-165) answer late controls with `control-timer-expired`. Per §9.2.1 and §8.2.4.3 that cause belongs to the RIC Time to Wait timer of a Call Process ID, and rc sends none. `control-failed-to-execute` matches "fails to execute the requested … action". The repeat gate is unaffected either way; this only matters for spec alignment of the decoded wire.
4. **ControlOutcome stays optional in E2AP** in every version read. G8 (rc panics without it) is an rc defect that we must accommodate; the spec does not require the outcome.
5. **A silent drop.** The node "shall respond" with ACK or FAILURE (or must not ACK under NoAck). The RIC-side remedy for silence is ERROR INDICATION on TRICcontrol expiry, which rc does not implement. So the journal's "drop silently violates E2AP" stands.

## Sources (credibility)

- Primary specs (normative):
  - O-RAN.WG3.TS.E2AP-R004-v08.00 (local converted copy);
  - [ETSI TS 104 039 V4.0.0 = O-RAN.WG3.E2AP-R003-v04.00](https://www.etsi.org/deliver/etsi_ts/104000_104099/104039/04.00.00_60/ts_104039v040000p.pdf).
- Primary code: `ric-app-ad` @f9f97b8, NIST patches @725b167, `ric-app-ts` @19e169b, `ric-app-kpimon-go` @8bbbbbb, `ric-app-rc` @a2282ee, `sim/e2-interface` @da6f82f, `ric-plt-e2` @5aa396f, and ricxappframe 3.2.2 (PyPI wheel).
- Maintainer secondary:
  - [O-RAN SC Jira RIC-722](https://lf-o-ran-sc.atlassian.net/jira/browse/RIC-722), plus RIC-783 and RIC-784;
  - [Czichy and Hiltunen, ONE Summit NA 2021 slides](https://static.sched.com/hosted_files/onesummit2021/62/ONeS_NA_2021_Thoralf_Czichy_Matti_Hiltunen_lessons_learned_near_rt_RIC_and_xApps.pdf).
- Low-weight secondary, noted only: [hackmd E2GAP v02.01 notes](https://hackmd.io/@Min-xiang/rk_gODRVq) (paraphrase, no E2AP version given).

## Limitations

- The AD crash is a static reading. It has not been reproduced on a pod, because there was no VM access in this task.
- AD's feature columns were not mapped against kpimon's `UeMetrics` fields.
- The exact E2AP version of rc's ASN is bracketed, not pinned.
- The E2SM-RC prose on control outcomes was not read; it is out of scope.

## Unresolved questions

1. What exactly do the v02.01 and v02.02 RIC Control texts say? In particular, did NEC CR-0002 change the FAILURE conditions or only add CriticalityDiagnostics? Answering this needs a user-side download from specifications.o-ran.org (registration plus licence).
2. Should the agent's late-control FAILURE use `control-failed-to-execute` instead of `control-timer-expired`? This is a user call on D2 wording.
3. Does the AD crash reproduce live? It is worth a 10-minute check only if real AD is ever brought into scope.
4. Does rc's timer key (`aRequestSN`) equal the `ricInstanceID` it puts on the wire? This ties into G9.

Status: DONE
Summary: The NIST AD patch keeps AD's 1.6 s wall window, its 0.5 s schedule and the `UEReports` input, which kpimon does not write, and a static reading shows the patched AD crashes before it can send 30003. The E2AP §8.2.4 ACK/FAILURE text is identical in v04.00 (ETSI) and v08.00, and the change history shows no RIC Control change after v02.02, so v03.01 almost certainly matches; v02.0x prose remains unread.

## Addendum (2026-10-22 16:40 KST): Q7 checked against v02.00, v03.00, v03.01, v08.00 and v09.00

The user's Zotero library holds the five E2AP texts: `O-RAN.WG3.E2AP-v02.00` (Oct 2021), `R003-v03.00`, `R003-v03.01`, `TS.E2AP-R004-v08.00` and `TS.E2AP-R005-v09.00`. §8.2.4 of each was extracted with `pdftotext -layout` and word-diffed after removing page furniture and PlantUML figure source.

**The ACK rule is identical in all five versions.** v02.00 §8.2.4.2: "If the RIC CONTROL REQUEST message contains the optional RIC Control Ack Request IE set to "Ack", or if the optional RIC Control Ack Request IE is not present, and the E2 Node has successfully processed the requested RIC Control procedure action, then the E2 Node shall respond with the RIC CONTROL ACKNOWLEDGE message and continue call processing." From v03.01 on, the closing words "and continue call processing" are dropped, and the NoAck case says "shall not send the RIC CONTROL ACKNOWLEDGE message".

**The FAILURE triggers are the same in every version:**
- an invalid RIC Call Process ID;
- a Call Process ID whose RIC Time to Wait timer has expired;
- a failure to execute the E2SM-specific action;
- an encoding or functional error in the E2SM IEs;
- an unknown or unannounced RAN Function ID, or an unsupported control action.

v03.01 only rewords the RAN-function case; it no longer mentions E2 Setup or Service Update.

**Diff results:**
- v02.00 → v03.00: no change in the rules (the word-diff ratio of 0.958 is figure markup).
- v03.00 → v03.01: editorial rewording only; the Call Process clause drops "clear the timer".
- v03.01 → v08.00: case changes only. One sentence first looked deleted; that was a page-break artifact, and the sentence is present in all five versions.
- v08.00 → v09.00: identical (ratio 1.000).

**The cause semantics are the same in all five versions:**
- `control-timer-expired`: "RIC Control Request received by E2 Node after the associated RIC Time to Wait timer had expired". This is a Call Process timer. rc never sends a Call Process ID.
- `control-failed-to-execute`: "Requested control procedure initiated by RIC Control Request failed to be executed in the E2 Node". This is the correct cause for a late control that is refused under D2(a) or D2(b), and for a precheck refusal.

**Message IEs:**
- **ACK** (§9.1.1.9) in all versions: Message Type, RIC Request ID and RAN Function ID are mandatory; RIC Control Outcome is optional. v02.00 has no RIC Control Status IE.
- **FAILURE** (§9.1.1.10): Cause is mandatory and RIC Control Outcome optional. Criticality Diagnostics is absent in v02.00 and present from v03.01. That is consistent with rc's ASN dating from v02.0x.

**Conclusion.** The plan's ACK and FAILURE semantics hold for every E2AP version our stack touches: rc's v02.x, our agent's v03.01 and the L-release era. v02.01 and v02.02 were not read, but v02.00 and v03.00 bracket them and are identical in rules. The ACK means "successfully processed". With d = 0, processing at the barrier is the apply, so ACK at apply time is exactly compliant. With any δ > 0, the ACK must wait for the apply time, because no later FAILURE can retract it. Every control that is refused or arrives late uses `control-failed-to-execute`.

# Verifier verdict: M8–M9 delivery contract, best-of-5 (brainstorm --ultra)

Date 2026-10-22 KST. Verifier: kongming (Opus 5.5). Advisory only; candidates untouched.
Inputs: packet `plans/reports/brief-261022-1713-GH-1-m8-m9-contract-evidence-packet.md`, journal §5–§8, cited reports, local clones (rc @a2282ee, TS @19e169b, QP @47a35ca, kpimon @8bbbbbb, ric-plt-e2 @5aa396f), ns-3 @ace32168, Testbed @725b167, M0–M7 evidence.

## 0. Decisive finding (N5, the user's named spot-check)

The request-part octets must be **raw bytes**, not ASCII text. Chain, all verified:
- e2term sends E2Setup to e2mgr as BASIC-XER (`ric-plt-e2 RIC-E2-TERMINATION/sctpThread.cpp:2193`). XER renders an OCTET STRING as hex: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/dev-p5/r1/e2ap-setup-request.xer:213` = `72 65 71 70 61 72 74` ("reqpart").
- e2mgr stores that hex text. The nodeb JSON field is `NzI2NTcxNzA2MTcyNzQ=`, which is base64 of `72657170617274` (`.../dev-p5/smoke/20261021T164639Z/e2mgr-nodeb.json`).
- TS base64-decodes that field and string-matches the uppercased ranName suffix (`ts_xapp.cpp:333, 353, 363-366`). e2term renders the suffix as lowercase hex (`BuildRunName.h:89,92`, `%1x`), giving `gnb_001_001_00000002`. TS uppercases it, so case is not the failure mode.
- The TS key therefore has to equal the hex rendering of the octets. With 5 raw octets `00 00 00 02 xx`, the rendering is `00000002xx`, which matches. With 10 ASCII characters `"0000000200"`, the rendering is `3030303030303032…`, which never matches. `cell_map` stays empty and G4 is not fixed.
- rc hex-decodes `"00"+PLMN+key` (`rcE2SmRc.go:101-102`) and copies those octets raw into the OCTET STRING `valueOctS` (`e2sm/wrapper.c:275`; the BIT STRING encoder at `:358ff` sits inside a comment). So the agent reads the target from the last 5 bytes. `%08X`+`00` and `%08X%02X` both work there.
- Precedent: M-RC4 on the old stack used requestPart bytes `[gnbId 4B ++ cellByte]`, which rendered as `16B8CE0N0N` (user memory `phase6b-cellmap-gap-and-option4.md`).

How each candidate does:
- **D** is the only one that gets the encoding right ("5 raw bytes").
- **A, B and C** explicitly specify ASCII, which is wrong.
- **E** does not say which. Read naturally ("write the string") it is wrong, but its R0 check ("nodeb JSON shows its base64") would catch the mistake at R0.

## 1. Scores (1–20 per criterion)

| Criterion | A | B | C | D | E |
|---|---|---|---|---|---|
| R1 Faithfulness | 17 | 16 | 16 | 15 | 17 |
| R2 Evidence grounding | 11 | 13 | 11 | **18** | 15 |
| R3 Criteria sharpness | 15 | **18** | 17 | 15 | 17 |
| R4 Honesty about unknowns | 14 | 16 | 14 | **17** | **17** |
| R5 Conditional fields | **17** | 16 | 15 | **17** | **17** |
| R6 N1–N7 + sequencing | 13 | 14 | 13 | **18** | 15 |
| **Total (/120)** | 87 | 93 | 86 | **100** | 98 |
| Hard constraints H1–H5 | PASS | PASS | PASS | PASS | PASS |

Hard-constraint check:
- H1: none reopens D1–D10, the D2 cause, or d = 0. Agent-local reject causes (C, E) and the LTE-fallback precheck (D) fall inside D2/D4, so they do not reopen anything.
- H2: every candidate applies the full C1 gate to R3.
- H3: every candidate covers R0–R3, M9 and N1–N7.
- H4: no TS, kpimon or rc fork; `fresh-install` is preserved by all.
- H5: every candidate lists the realism pass as its first non-goal.

## 2. Per-candidate rationale

**A (87)**
- ✔ rc's timeout only logs, and the ErrorIndication is a comment (`rcControl.go:179`). The E2 send is async (`:141`), and gRPC succeeds at enqueue (`rcService.go:39,50`).
- ✔ TS sets `ranname` to the target's node (`ts_xapp.cpp:639-643`). ✔ kpimon discards unknown mtypes (`control.go:651-652`).
- ✘ N5: "10 ASCII characters; the request part is exactly this key" is wrong (§0). A's own R2-2 ("JSON base64-decodes to the key") contradicts its design and would only catch the error at R2.
- ✘ "parses the CGI's trailing 10 bytes": the key decodes to 5 bytes.
- Strengths: R0-3 (refusals for both serving-cell and unknown IMSI), R0-4 (measured apply→end), M9-3 (global wall deadline).
- Gaps: no forced freeze-then-fail run and no bye/EOF run. The C3 count identity omits post-bye requests. The health check omits hw-go.

**B (93)**
- ✔ `scenario-zero.cc:173-176` says "use -1000.0 with NoAuto". This is a unique, strong find for the outage fallback.
- ✔ rc's instance counter is hard-coded (`rcControl.go:146-153`). ✔ `metric-map.v1.json:31,48`. ✔ Installer lines `install_xapp_qoe_predictor.sh:65,81-111`. ✔ `lte-enb-rrc.cc:4478-4532` is `PerformHandoverToTargetCell`.
- ✘ N5: "10 ASCII bytes" is wrong. Mitigation: B lists "e2mgr's encoding of the request part: nodeb JSON after E0" as discoverable, and its offline replay of TS's algorithm on the nodeb JSON would catch the error.
- ◐ Better approach #1 (QP fork in a fixed-prediction mode as R2's stub):
  - the premise is ✔ (`research §2.4`: the serving cell is the first key with a `Uint`);
  - "needs QP's reader anyway" is overstated, because the harness knows the serving cell;
  - "no extra code" is false;
  - it couples R2 to the QP fork and the N7 pickup.
- ◐ "IMSI appears in the target's KPM list at rxSeq+1" is plausible (skeptic E5 derives about 4.7 ms apply→end) but is not marked as derived.
- Sharpest criteria overall:
  - C8, a fault run aborted within T_gate + 5 s;
  - R1(e), the post-bye case;
  - C10, the image digest and `pip freeze`;
  - M9 requires `fresh-install` unchanged and ≥ 20 GB free.

**C (86)**
- ✔ The ack handlers mark the map and decode the outcome (`rcControl.go:325-390`). ✔ The A1 default is 0 (`ts_xapp.cpp:96`). ✔ `git_clone.sh:134-163`.
- ≈ `main.py:107`: `train_model` is actually at `:104`. The write-back at `:116` comes before the send at `:71`, so C's §7 premise holds.
- ✘ N5: "carried as ASCII" is wrong. ✘ The N5 trade-off names "lowercase hex" as the failure mode, but TS uppercases the suffix (`:353`). The real risk, how octets are rendered, is missed.
- Strengths:
  - explicit agent-reject causes;
  - "no ACK before controlAck";
  - zero HO rows in the null-control run;
  - a stalled-`go` fault;
  - R1 post-bye.
- Weaknesses: M9 never requires R3. The N1(a) trade-off ignores the xApp-set variant.

**D (100)**
- ✔ F1: `rcService.go:39,50`, `rcControl.go:176-181`. ✔ F3: `ts_xapp.cpp:643`. ✔ F4: `rcE2SmRc.go:101-102`.
- ✔ F5: the outage switch (`lte-enb-rrc.cc:4755-4780`, `SendRrcConnectionSwitch` at `:4768`) writes no handover-start row; that trace fires only at `:909`. `PerformHandoverToTargetCell` (`:4479-4531`) never checks `m_imsiUsingLte`, so the LTE-fallback refusal fills a real precheck gap.
- ✔ N5 uses raw octets `[gNB-ID 4B][cell 1B]`. It is the only candidate consistent with the XER/e2mgr rendering, it cites the M-RC4 precedent, and it honestly flags "unverified on this e2mgr until R0".
- ✔ Sequencing: S0 lands G4/N5 first, and S1 builds the pacer without the RIC.
- Gaps (see §5): no forced fault runs, KPM headers left out of C1, N6 checks only seq T, no recalibration of T_ctl/W, kpimon and hw-go missing from the health check, snapshot deletions planned automatically.

**E (98)**
- ✔ "46 distinct `RRU.PrbUsedDl` in 100 M6 rows" reproduces in all four `m6-influx-cell.csv` files. All rows are from nodeId 2; E itself flags that variance at the 2-gNB config is still open.
- ✔ `e2ap-builders.cpp:53-65` zeroes the request-part context and leaves the octets untouched. ✔ `ts_xapp.cpp:879-888`, `:645-647`. ✔ `rcService.go:39,50`.
- ◐ N5 leaves the octet encoding unstated (see §0). Its R0 JSON check would catch an ASCII implementation early.
- ◐ It cites `lte-enb-rrc.cc:4765` (the line is actually `:4768`) and marks the no-start-row point as unverified; D verified it.
- Strengths:
  - one refusal per class, naming both asserts;
  - a fault run that includes bye/EOF;
  - a QP unit-test list and an in-image SHA check;
  - an R3 calibration run for W;
  - the N7 "empty tree diff" check.

## 3. Ranking and winner

**D > E > B > A > C. Winner: candidate D, unchanged.** Confidence: **medium**.

Why D wins:
- Of the seven open decisions, N5 is the only one with no design yet.
- It is the only decision on which a wrong call silently re-creates G4.
- D is the only candidate that gets it right on primary evidence.
- D is also the only one to verify the outage-fallback behaviour.
- D's gaps are missing tests, which can be added without rework. E's N5 gap is a design ambiguity on the exact point the user asked about.

## 4. Margin

- **Low.**
- Deciding criteria are R2 and R6. D leads E by 3 points on each. That is below 4.75, which is 25 % of the 19-point range, so the lead does not count as high.
- On totals, D leads by 2 of 114, or 1.8 %.
- **Unanimous: no.** D does not top R1 (A and E do) or R3 (B does).

## 5. Defects in the winner (surface to the user)

1. **D2 freeze-then-fail is never exercised.** D has no forced fault run, so a deadline run-out is only "stated". Add one, like B C8 (an agent withholds `step{k}`; the run aborts within T_gate + 5 s naming k; no ledger line after k), or C C6, or E's R0 fault run.
2. **The bye/EOF FAILURE-all-pending rule passes vacuously.** D's C6 has no scenario that forces it. Add B R1(e) (a control after the final barrier) or E's buffered-control fault run.
3. **C1 does not compare KPM headers or `colletStartTime`**, even though D10 pins `simStartEpochMs`. A, B, C and E all include them.
4. **The N6 predicate checks only `ns3.simTimeMs == T`.** kpimon writes out of order (K2, `kp:666`), and the pacer releases non-trigger steps within milliseconds, so earlier rows in the window can still be in flight. Check every seq in QP's 1600 sim-ms window (C, E).
5. **No recalibration of T_ctl or W.** D never re-sets T_ctl from R0's measured L, as journal §6 asks. It also never sizes W for R3, where QP's first request trains inline (`main.py:104`). Consider E's calibration run or C's write-back anchor.
6. **The health check omits kpimon and hw-go RestartCount.** kpimon receives the acks for rc instance IDs 2 and 4 by exact key, and hw-go can own the −1 fallback (probe §Answer 2–3).
7. **Snapshot deletions are planned automatically:** `f7-rerun-green` after `r0-green`, and `r0-green` after `r1-green`. Previous deletions were approved by the user. Gate these on user approval (D's own Q4).
8. **N7 misses installer steps** (true of every candidate). The installer still edits the Dockerfile with sed (`install_xapp_qoe_predictor.sh:112-118`) and injects the Influx token with sed (`:121-124`). Both must survive "skip `git apply`", and the token must never be committed to the **public** fork. Also, `git_clone.sh` names the directory after the URL basename, which would be `ric-app-qp`, but the installer runs `cd qp` (`:62-70`). Pass `qp` as NAME.
9. **The eNB request part.** D says "every agent decodes to its N5 key", which puts LTE cell 1 into TS's `cell_map`. Either keep the eNB's request part non-matching (B, C), or state that D4 refuses non-mmWave targets.
10. **Demo mode is not addressed.** D never says whether D2's continue-and-flag is built in this scope (compare A Q1, C Q5, E's non-goal).
11. **The N5 caveat can be narrowed now.** The dev-p5 JSON already shows that this e2mgr renders the field as hex of the octets. What remains to verify at R0 is that the hex is uppercase and that the match succeeds; B's offline replay of TS's algorithm checks both cheaply.
12. **Minor: the key format.** `%08X%02X` puts the cellId into NCI's 4 pad bits (TS's comment at `ts_xapp.cpp:366` says "last 4 bit unused"). It works because rc carries raw octets. `%08X`+`00` is semantically cleaner. Either way the octets must be raw. This is a user pick.

## 6. Good ideas found only in non-winners (optional additions)

- **B:**
  - `--outageThreshold=-1000` in paced rungs, per `scenario-zero.cc:173-176`. This removes the LTE-fallback class instead of refusing it. It is a user call, because the journal says NoAuto "keeps the outage fallback".
  - An offline replay of TS's `cell_map` algorithm on the nodeb JSON as a gate check, run at R0.
  - C10: record the QP image digest and `pip freeze`.
  - "QP model files are created only after this run's restart".
  - R1(d): a same-IMSI pair through two agents, where the lower nodeId wins.
  - Build pacer injection before the agent control path.
- **E:**
  - The measured PrbUsedDl variance as N4 evidence.
  - A calibration run that measures L including the first QP training, then sets W = max(1 s, 3 × p99.9).
  - A unit-test list for the QP fork, plus a forecast SHA check inside the image.
  - Verify N7's commit 1 as an empty tree diff against gerrit with `git apply`.
  - M9: one live run for each lower rung and the full C1 for the highest.
  - Ledger detail causes (`alreadyOnTarget`, `inHandover`, `unknownImsi`, `unknownTarget`).
  - Handover-row count == applied count.
- **C:**
  - Anchor W after QP's write-back becomes visible.
  - An explicit mapping of agent-reject causes (`control-message-invalid`, `ran-function-id-invalid`, `action-not-supported`).
  - Zero HO rows in the null-control run.
  - `OPENBLAS_NUM_THREADS=1` as a fallback.
  - No snapshot for R1, since it is harness-only.
- **A:**
  - R0 measures apply → HandoverEnd (skeptic Q1).
  - R0 refuses a handover to the serving cell.
  - A global M9 wall deadline.
  - "A control at a non-trigger step is late".

## Unresolved questions

1. N5 key shape: `%08X%02X`(D, the M-RC4 layout) or `%08X`+`00` (the others, NCI-clean)? Both need raw octets.
2. Outage fallback in paced rungs: refuse LTE-fallback UEs in D4 (D), or pass `--outageThreshold=-1000` (B)?
3. Is the hex case of the XER rendering on e2term 6.0.6 uppercase? The old stack showed uppercase. Confirm at R0 with a gNB-ID ≥ 10, or accept that IDs 1–3 are all digits.

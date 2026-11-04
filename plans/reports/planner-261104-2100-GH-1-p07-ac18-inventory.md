# P07 AC18 inventory (Style 5 action 3 to the source en-gNB)

Date: 2026-11-04 (Asia/Seoul). This is the check-diff inventory that P07 needs before any code: step 0 (G1) and P07's "Hand-offs from the P06b exit review" item 2, together with the P06 hand-offs. I appended rows 106–127 to `plans/261103-0008-GH-1-post-m9-realism-m10/check-diff-ledger.md`. No code or other plan file changed, and nothing was committed.

Of the 22 new rows, three are marked as contract changes. Row 106 (the seam smoke, required by ruling G1) and rows 120 and 121 (the e2i cases) encode P1 or N5 and were not registered at Stop A. The other 19 are ordinary rows or new checks.

## Basis

- I re-read every site at HEAD 2e7abf4. Line numbers in the new rows are current.
- Most new rows share one identity rule: I(id) is the IMSI whose (lteRnti, mnCellId) in the run's `e2-ue-context-*.jsonl` equals the en-gNB-UEID's (mEnbUeX2apId, macroEnbId).
  - Row 79 (c) makes this a bijection, and row 79 (d) anchors it on ns-3's MN PDCP trace.
  - I is MN-scoped, not resolved against the via node. A non-source control can therefore still be attributed to the UE it was sent for, while ns-3 refuses it `unknownUe` with ledger imsi 0. This is the same rule row 16 uses.
  - Row 113 defines I. Rows 107, 117, 121, 123 and 124 reuse it.
- Every refusal of an unresolved or non-source control is attributed through the hub's `e2-pacing-log.jsonl` record of (viaNodeId, ctlId), which carries the IPC `ueId`. The pacer replay uses the same record (row 111).
- Three negatives need a UE ID that no UE holds: the seam smoke, R1 (d) and R2 n3. They use X2AP ID 4095 on MN cell 1, and each judge asserts that no IMSI holds it.

## Rows by owner

**δ seam smoke (G1), `scripts/probes/probe-delta-seam-smoke.sh`:**
- Row 106 (#9 P1/P4):
  - The six schedules move to the en-gNB-UEID IPC control, addressed through the source.
  - The eNB pair at fb1 step 20 becomes a same-node, same-target `inHandover` pair, because the hub sorts on the target before the ctlId.
  - IMSI 99 becomes an unheld X2AP ID.
  - One non-source `unknownUe` control is added, so check-ledger expects 9 lines instead of 8.
  - The tie, cancel-at-stop, ack-pairing and pins/emitter-SHA predicates keep their code.
- Row 107 (new check): after each run, the frozen-map IDs written into the schedules must name the intended IMSIs in that run's own context.

**R3′ preparation:**
- `r3p-prepare.py`: row 108 (`stub_load` and the `trigger` branch) and row 109 (the `fixed` calibration branch).
  - The key U comes from ctx(n, T).
  - U must equal the `ueId` of the Influx row that N6 certified. For this, N6 gains `ueIdAtT` in OUT_VERDICT only; OUT_WINDOW stays as row 86 says.
  - The stub must answer `{"ues": [U], "entries": 1}`.
  - Prepare writes `trigger-ue-T.txt` and `trigger-ue-T.json`.
- `r3p-schedules.py` `trigger_entry` and the new `send-rmr.sh anomaly-from` op: row 110.

**Pacer:** row 111 (`pacer.py --replay` takes the UE-identity tuple from live1's pacing log, with four pairing conjuncts) and row 112 (`pacer-selftest.py` case 10 plus four negatives). Row 57's scheduling rule is unchanged.

**Wire extractor and wire judges:**
- Row 113 is the ordinary row that row 13 promised. It covers:
  - `wire-c1-extract.py`: the UE ID decode and filter, the ledger join (I(ueId) = ledger imsi, or imsi 0 with `unknownUe`), the equality between the pacing log and the wire, and the multiset `ueId` with its sort key;
  - the (imsi, step) attribution in `r2-checks.py cmd_wire` and `r3p-checks.py c_wire`;
  - R1 f2's `m["imsi"] == 4` at `gate-r1:292`.
- Row 114: a shared IP in the extractor's IP map now fails closed (today the last listed node wins silently).

**Agent counters:** row 115 adds new checks that share one helper:
- every rung (beside `agent_c2`), R1, R0 (which first gains the stats-after-bye wait) and M7;
- `samplesNoUeContext` and `ipc.ueContextRejected` must be 0 as a maximum over every stats line across restarts, and `ipc.ueContext` must reach at least 1;
- the helper is replayed offline on the archived M7, R0, R1 and r3p runs before it lands.

**KPM UE-list judge:** row 116 (the rungs' `kpm_moves` gain `--facts "$e/$label-sub-facts.json"`) and row 117 (an imsi-0 line is attributed through its pacing record to I(ueId) and judged as that UE's refusal; an unheld ID carries no UE).

**e2i:**
- Row 118: association-based attribution through `assoc_node_of` in `setup` and `controls`, with the circularity disclosure.
- Row 119: the RAN function 3 definition judge. It keeps {1,2,3,4}, adds the I-4 IDs and the RAN parameter IDs seen on the wire (collected recursively), and requires that the announced (style, action) set is exactly {(5,3)}.
- Row 120 (#9 P1, N5): five injected cases. They are the Style 5 positive, the N5-form negative re-encoded as Style 5/3 and sent via IMSI 6's source at step 40, Style 3/1 → `action-not-supported`, non-source → `unknownUe`, and eNB → `ran-function-id-invalid`.
- Row 121 (#9 P1): `ledger_and_handover` now expects two lines.
- Row 122 (new check): hex sidecars beside the e2mgr record files. They must equal the record (judged before the scrub) and the request part on the wire.

**Scripted R1/R0 residue:**
- Row 123: R1 (d) `unknownImsi` → an unheld en-gNB-UEID refused `unknownUe`. rc-send gets an explicit-ID form for this one negative.
- Row 124: the ledger `imsi` of `late` lines (R0 k9). I propose that ns-3 resolves read-only at rx, so the k9 match is unchanged; the alternative is listed.

**TS xApp:** row 125 adds R2 negative n3. It is a well-formed `ueId` with no Influx row and handover-worthy predictions, and it must produce zero RIC CONTROL requests on the wire, no controlRx and no ledger line.

**rc and agent:**
- Row 126 (new check): a Q8 gRPC request with neither UeId alternative must get InvalidArgument, send no RIC message and leave rc RestartCount at 0.
- Row 127 (new test): the agent's per-seq UE context unit test in the image build. The "K = 1 wherever handovers happen" constraint is withdrawn.

## Existing rows that cover P07 sites (not duplicated)

| Site in the task | Covered by | Line drift at HEAD 2e7abf4 |
|---|---|---|
| r3p D7 | row 10 | `r3p-checks.py:203-207` → `:205-209` (`gate-r3p:246` unchanged) |
| r2 D7 | row 11 | none |
| r0/r1 D7, the `enb`/`nonSourceGnb` negatives in D7 | row 12 | `gate-r0:238-240` → `:246-248`; `gate-r1:269-271` → `:275-277` |
| r2 wire via/key (the UE-ID part is now row 113) | row 13 | none |
| r3p wire | row 14 | `r3p-checks.py:85-97`, `:90` → `:87-99`, `:92` |
| r3p expect, dry-ledger | row 15 | `:69-82`, `:73` → `:71-84`, `:75`; `:263-275`, `:270` → `:265-277`, `:272` |
| r0/r1/r2 expect and the `unknownUe` attribution of non-source negatives | row 16 | `gate-r0:236` → `:244`; `gate-r1:249` → `:255`; f2 `:277` → `:283-284` |
| R0 scenario, both negatives, N_REQ/N_LED/N_LOCAL | row 17 | none |
| R1 (a), (b), (c), (e), f2 scenario | row 18 | none |
| r2 scenario via, r2/r3p calibration triggers, schedule/stage-A T, classifier, stage-B inject | rows 19, 20, 22, 23, 24, 25 | none |
| r3p and r3p-dry-run fixtures | rows 28, 29 | none |
| R1 C4 (b)/(c) and the arrival-order fixture plus the order test suite | row 30 | `gate-r1:252-267` → `:258-273` (`:258` → `:263`, `:260-261` → `:266-267`, `:262` → `:268`) |
| R1 f2 via agent 2 (S1 option A) | row 31 | `:276-295` → `:281-302` (`:285` → `:291`, `:287` → `:293`, `:290` → `:296`); `:109` unchanged |
| wire-c1-extract target and style/action filter | row 40 | none |
| rc-send / rc_send_control (Style 5, source, Influx UE ID) | row 41 | `rc-lib.sh:243-248` → `:280-286` |
| Q8 EnGnbUEID-only request | row 42 | none |
| agent unit test `style3-action1-refused` and e2i PASS list | rows 45, 55 | none |
| rc-decode Style 5/3 fixture | row 46 | none |
| R0 V4 refusal count | row 50 | `gate-r0:241-253` → `:249-261` |
| R1 agent C2 split | row 51 | `gate-r1:223-243` → `:229-249`; calls `:248`, `:275` → `:254`, `:281` |
| r0/r1 schedule absence for `agent:` controls | row 52 | none |
| wire-c1-extract `viaMeid` | row 53 | (row 53 cites no harness lines) |
| pacer replay scheduling | row 57 | none |
| stub, fixtures, scenario `:17`, predictor, r2 stub/schedule/table, `send-rmr anomaly`, rmr-peer self-test (verdicts at P07) | rows 88–95 | none |
| agent_counters_assert (M6, P12) | row 98 | `agents-ns3-run.sh:243-262` → `:278-303` |

The phase file's Context and plan.md R-7 have the same drift: `ts-rung-lib.sh:169` (the C1 replay) is now `:182-183`, and `gate-r1:252-267` / `:276-295` are now `:258-273` / `:281-302`. I did not edit either file, because that is outside my scope.

## Checked and found unchanged

- `check-ledger.py`: its order key (rxSeq, imsi, viaNodeId, targetCell, ctlId) reads the resolved ledger imsi, so the code does not change. It will verify that ns-3 sorts unresolved controls (imsi 0) the way the hub's key says.
- `check-c9-handover-trace.py`, `check-actuation-delay.py` and the r3p expect/driven/membership/observation judges read applied ledger lines, whose imsi stays literal (R-2).
- `digest-run.py` digests the ledger and the sample lines, and the pacing log is not digested.
- `ipc-null-sink.py` never receives controls (the pacer injects them).
- The S0/S1 sites (`check-free-control-ledger.py`, `gate-s1-pacer-lockstep.sh:233`) are frozen under ruling S2.
- `ts_patches_check` and `rc_at_pin` (rows 72 and 73) keep their predicates while their manifests grow.

## Observations

- **Row 53 implementation.** Row 53 needs the association of each RIC control request. The extractor has no fact sheet today. Building it on `e2-facts-query.py build_assocs`, as rows 101 and 118 do, keeps one attribution rule (DRY), but `wire-c1-extract.py` then needs a `--facts` argument that row 53's text does not mention.
- **Duplicated helper.** `agent_logs_after_bye` is defined twice (`gate-r1:122`, `ts-rung-lib.sh:21`), and R0 needs it for row 115. Moving it to a shared library avoids a third copy.
- **Seam smoke outcomes.** The resolution rule (the current SN, `m_lastMmWaveCell`) may turn the seam smoke's step-20 IMSI 1 control from `lteFallback` into `unknownUe` if a UE in LTE fallback has no current SN. That outcome is informational in the smoke, but it would matter for any gate that asserts `lteFallback`. None does today.
- **Finding 6 ordering.** Rows 108–113 and 125 land with the TS xApp patch at one harness pin, together with rows 10, 14, 15, 25 and 88–95. No r3p run should happen on a partial migration.

## Unresolved questions

1. Rows 106, 120 and 121 encode P1 (and N5 for 120) and were not confirmed at Stop A. Ruling G1 requires row 106 before code, but not the user's confirmation of its content. Do these three rows need the user's confirmation before the first P07 code commit, or is Stop A′ enough?
2. Row 124: does ns-3 resolve the UE of a `late` control read-only at rx, so that the ledger imsi stays meaningful, or do late lines carry imsi 0? R-4 and the Design do not say. The choice affects R0 k9, the KPM judge and the seam smoke.
3. Rows 106, 107 and 120 write UE IDs into schedules before the run, taken from the frozen cp1 map, and verify them afterwards. The alternative is to encode at injection time from the live context files. Is the frozen map acceptable for the seam smoke, whose radio configuration lacks `--outageThreshold=-1000`, and for e2i?
4. Row 125 assumes the TS xApp reads Influx when it builds the control, after the QP prediction, so n3 still produces one 30000. If the patch reads Influx first, that conjunct becomes "zero 30000 naming the key". Which order does the TS patch take?
5. The phase text says the window files "record both the IMSI and the key". Row 86 keeps OUT_WINDOW unchanged, so row 108 records the pair in `trigger-ue-T.json` and N6's verdict instead. Is that acceptable?
6. Should r2's triggers (row 93) use the same `anomaly-from` route, with a prepare that resolves the key through the context files and confirms it in Influx (kongming Q4 item 4), instead of reading Influx inside the trigger?
7. Row 118: for e2i's setup frames, should the node come from row 101's association rule (circular for the node number, with the IP cross-check and a disclosure), or from an agent-side, non-circular source (the agent's log of its SCTP local port plus the container's nodeId label)? The agent's port log is [UNVERIFIED].
8. Row 119 keeps {1, 2, 3, 4} as a conjunct. If the I-4 reading of §8.4.6.3 shows that action 3 does not carry all four IDs, the row must be amended with that evidence before code. This needs the PDF read from step 1.
9. Is X2AP ID 4095 (on MN cell 1) an acceptable "no UE holds it" value for rows 106, 123 and 125?
10. Row 115 covers M7, R0, R1 and the rungs, as the hand-off asks. Should e2i and Q8, which also save agent logs, get the same counter check?
11. Should "the TS xApp never uses an `ns3.*` field for the UE identity" become a static check on the TS patch (a new row), or stay a review item?
12. rc-send (row 41) has to find each R0/R1 UE's ID in Influx. Should it look the UE up by the `ns3.imsi` field, or resolve IMSI → ueId through the context files and then confirm the tag in Influx (the route of row 108)?
13. Is the protoc byte-equality proof (F12) a one-time recorded proof, or will it run as a lint/gate check? If it is a check, it needs its own "new check" row.

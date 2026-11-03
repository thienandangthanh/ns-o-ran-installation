# AC18 #9 design-gap resolutions (M10 plan, check-diff ledger rows 9–48)

Date 2026-11-03 KST. Inputs: draft `scratchpad/ac18-9-rows-draft.md`, `plans/261103-0008-GH-1-post-m9-realism-m10/{plan.md, phase-06*, phase-07, phase-08, check-diff-ledger.md}`, contract (items 12–14b, 18, §3, §7, A1, A2), rulings D1–D4. Code re-read at HEAD 5093c15 (harness), Testbed c6d1434, deployed OSC clones (`~/Documents/UCLAB/projects/O-RAN-DW/OSC-repos`, rc a2282ee, ric-plt-e2 5aa396f). No repo file edited.

## 0. Outcome (read first)

18 of 20 gaps close inside the contract with pinned predicates. Two need a user ruling: **gap 5** (R1 f2, see below) and **gap 15** (S0/S1/probe outside R-1). Three findings correct the draft or the plan:

1. **APER NR-CGI is 9 octets, not 8.** pycrate (image `localhost/asn1-indep`) encodes {00F110, NCI = gNB 2 ‖ cell part 1} as `0000f1100000000210`. That is 1 preamble octet (extension bit + 7 pad bits) + 3 PLMN + 5 (36-bit NCI + 4 zero pad bits). The same tool decodes the N5 form `0000f1100000000202` leniently as gNB 2 / cell part 0 and re-encodes it as `…0200`, so byte equality is what refuses it (I-6 works). Two texts need correcting: P06's "requires byte equality and 8 octets", and the draft's "16 hex" rule for row 39. The TS key `%08X10` is still the last 10 hex digits. Side effect: rc's current `"00"+PLMN+key` concatenation (`rcE2SmRc.go:101`) already produces valid APER bytes for a valid key. One case is inherently ambiguous: cell 0x10 (16), where the N5 and NCI bytes are identical. It does not occur, because s10 uses cells ≤ 11.
2. **f2 through "the source en-gNB agent" is infeasible as P07 pins it.** ns-3 disposes emitters in node order 1, 2, 3. `E2IpcEmitter::Stop()` calls `DeliverInbound()` before `OnEmitterStopping()` (`oran-interface/model/e2-ipc-emitter.cc:181-188`). Only the first emitter (node 1, the eNB) stops before the stop handshake. When emitter 2 stops after the handshake, it reads agent 2's forwarded control, and the hub answers it `late` (`e2-control-hub.cc:196-200`). That produces a ledger line and failedOnBye 0, so P07's predicate cannot pass. Under P07 the eNB agent refuses RC controls itself (ran-function-id-invalid), so agent 1 can no longer carry the control either. Ruling needed (gap 5).
3. **The eNB meid literal `enB_macro_001_001_000001` is verified, not merely derived.** e2term renders each octet as 2 hex digits after shifting out `bits_unused`, so a 20-bit ID takes 6 right-aligned hex digits [V `ric-plt-e2/RIC-E2-TERMINATION/BuildRunName.h:56-118`]. The prefix comes from `:190-192` and the PLMN `001_001` from `:47-50`. AC6a matches: 0xFFFFE → `enB_macro_001_001_0ffffe`, with nbId 20 chars [V `evidence/e2-identity-setup/20261102T192656Z/e2mgr-nodeb-enB_macro_001_001_0ffffe.json`]. AC6a also shows e2mgr storing an en-gNB as `node_type:GNB gnb:{ran_functions…}` [V `…/20261102T192656Z/e2mgr-setup-log.txt` line 3], so the `gnb` body key stays correct for en-gNBs.

Per D2, the P5 meid rows (31, 33–37, the meid part of 40) are pinned here but registered only after the patched-e2mgr AC6a re-probe (P06, before code). The rest go to Stop A.

## 1. Gap resolutions

Format: **R** = resolution (predicate/literal/rule · owner · Files additions); **NW** = why not weaker; **U** = user ruling.

**Gap 1 — R0 rewrite (rows 11, 16).**
- R (P07):
  - `r0-scenario.json` `controls`:
    - step 20: via 1→2;
    - step 30: via 2 (unchanged);
    - step 40: via 2→3;
    - these three get `path: "viaSourceGnb"`, `expect: "applied"`;
    - step 50: via 3, `alreadyOnTarget` (unchanged).
  - Add two negatives:
    - step 60 `{"via":3,"imsi":5,"key":"0000000310","targetCell":3,"path":"nonSourceGnb","expect":"unknownUe"}` (IMSI 5 is on cell 2);
    - step 70 `{"via":1,"imsi":2,"key":"0000000210","targetCell":2,"path":"enb","expect":"agent:ran-function-id-invalid"}`.
  - `calibration`: 20 via 1→2, 40 via 2→3, 60 via 1→3, 78 via 1→2; the rest unchanged (all already source). Count stays 10. `forcedLate` unchanged (via 2 = source).
  - `r0-checks.py`:
    - `schedule`: an `agent:` control becomes `{"trigger":{"cmd":…},"expect":0,"absence":true}` (pacer W, default 1.0 s; alone in its step).
    - `expect`: the gap-3 matcher.
    - `d7 SCENARIO LEDGER RC_MULTISET`: the new predicate (row 11).
  - `gate-r0`:
    - `r0_live` takes nreq/nled/nlocal = 6/5/1;
    - `extract --expect-requests 6 --expect-agent-local 1`;
    - `c2 --expect 5`;
    - d7 gets `$SCEN` and live1 `extra/rc-multiset.json`;
    - V4 refusal: `len(ref)==1` AND #wire failures with `control-failed-to-execute` == #ledger lines with outcome refused (2) AND one of them has `(step, viaNode) == (ref.rxSeq, ref.viaNodeId)`.
- NW: per-conjunct mapping in row 11. Every addressing path stays exercised in R0 itself, now with its spec outcome.
- U: no. AC14's negatives are placed where D7 needs them. Shown at Stop A in rows 11/16.

**Gap 2 — R1 (a) and the eNB negative (row 17).**
- R (P07):
  - `r1-scenario.json:4` via 1→2. (a) is still "two IMSIs through different agents" (2 and 3).
  - (c)'s via-3 entry gets `path:"nonSourceGnb"`, `expect:"unknownUe"`.
  - Add case (e) `{"step":60,"case":"e","via":1,"imsi":5,"key":"0000000310","targetCell":3,"path":"enb","expect":"agent:ran-function-id-invalid"}` (IMSI 5 is unused in R1).
  - `gate-r1`:
    - `r1_live` takes `nreq nled nstatic nbye` (the extractor gets nstatic+nbye): live 8/7/1/0, f2 2/1/0/1;
    - `agent_c2` passes iff `perAgent["1"].rejFunc == nstatic`, every other static counter is 0, `post_bye == nbye` and `pending == 0`.
  - Comments `r1-scenario.json:2,13` and `gate-r1:10-19` restated (texts in §3).
- NW: (a) keeps both-applied/two-agents; (e) is added.
- U: no.

**Gap 3 — expect matcher for `unknownUe` (row 15).**
- R (P07, `r0-checks.py cmd_expect`):
  - for `expect == "unknownUe"`, match `viaNodeId==via ∧ imsi==0 ∧ targetCell==targetCell ∧ afterSeq==step`, exactly one line, refused `unknownUe`;
  - its `(viaNodeId, ctlId)` names exactly one inbound record in the run's `e2-pacing-log.jsonl` with `ueId.mnCellId == 1` and `ueId.mEnbUeX2apId` == c.imsi's `lteRnti` in the run's `e2-ue-context-1.jsonl` (latest record with seq ≤ step);
  - `agent:` controls: zero lines with `(viaNodeId, afterSeq) == (via, step)`;
  - `len(lines) == #controls without "agent:"`;
  - both files are read from the ledger's directory [I: P06b/P07 write them there].
- Dependencies (P4 ordinary rows, P07): `kpm-ue-list-moves.py` skips imsi-0 lines; the `wire-c1-extract.py` ledger join compares an imsi-0 line's UE through the pacing log.
- NW: the old match proved "this line is that UE's" through the IMSI. The unresolved line cannot carry it (R-4), so the same one-line-per-control attribution runs through the X2AP ID the control was sent with.
- U: no.

**Gap 4 — C4 (c) and the viaNodeId term (row 29).**
- R (P07):
  - `c4_used`:
    - ok_b: in (b), the refused `inHandover` line has ctlId < the applied line's, and both have `viaNodeId == 3`;
    - ok_c: `order40 == [3,2]` AND exactly one step-40 line via 3 refused `unknownUe` imsi 0 AND exactly one via 2 applied imsi 3.
  - The comparator becomes a named function in `e2-control-hub.h`, used by `Apply`.
  - New `oran-interface/test/e2-control-order-test-suite.cc` (ns-3 TestSuite `e2-control-order`; `TEST_SOURCES` in `oran-interface/CMakeLists.txt`; run on the host build with tests enabled at P07 step 6). It asserts:
    - (i) the (b) pair sorts target 2 first, and arrival order gives target 3 first (they differ);
    - (ii) a pair differing only in viaNodeId puts the lower one first;
    - (iii) a pair differing only in ctlId puts the lower one first.
  - Fixture `fixtures/r1-c4-arrival-order/` as P07 pins.
- NW: the viaNodeId term can no longer decide any live outcome. Two controls for one UE through two nodes cannot both resolve, because only the current SN resolves (R-4). No observable is lost; the term itself is pinned by (ii), and wrong-node rejection is added.
- U: no.

**Gap 5 — f2 agent and the `gate-r1:109` confirm (row 30).** As pinned (agent 2, failedOnBye 1), f2 deterministically fails (§0 item 2). Options:
- **F-A (recommended):**
  - `E2IpcEmitter::Stop()` calls `DeliverInbound()` only while `!E2ControlHub::Get()->IsStopping()` (new accessor in `e2-control-hub.h`). Every node then behaves as node 1 always did: a control forwarded after the stop handshake is never read, and the agent fails it on bye. The `:196` late path stays reachable through `DrainAll()`.
  - f2:
    - faultStop control step 20 via 2, IMSI 6 → 3, applied;
    - stopTrigger via 2, IMSI 4 → 3;
    - `gate-r1:109` becomes `agent-forward-wait.sh 2 2 5`.
  - `f2_check`:
    - `a = perAgent["2"]`;
    - `all(viaNode == 2)`;
    - `forwarded == 2 ∧ failedOnBye == 1 ∧ rejIpcDown == 0 ∧ pending == 0`;
    - agents 1 and 3 have all rc counters 0.
  - Files (P07): `oran-interface/model/e2-ipc-emitter.cc`, `e2-control-hub.h`.
  - Byte risk: none for the references. The M9 r3p ledger has 0 `late` lines [V `reference/m9-r3p-raw/trace/e2-control-ledger.jsonl`], green R2/R3′ assert late = 0, and the P07 step-3 byte-compare gates it.
- **F-B:** ns-3 unchanged. f2 via agent 2 judges the late-at-stop path: one RICcontrolFailure `control-failed-to-execute`, one ledger line refused `late`, failedOnBye 0. The failedOnBye path moves to the agent unit test `bye-fails-all-pending`. This is **weaker** (the live failedOnBye path is lost).
- NW: F-A has the same four counters on one agent, the same "no ledger line", and the same stop-trigger confirm.
- **U: yes.** F-A changes ns-3 shutdown behaviour, which is not a contract item. F-B weakens a check.

**Gap 6 — `r2-scenario.json` via (row 18).**
- R (P07): add `scripts/gates/r2-scenario.json` to P07 Files.
  - via by the scenario's own layout: step 20 IMSI 1 → 3; step 30 IMSI 3 → 2; step 60 IMSI 2 → 3; step 70 IMSI 6 → 2.
  - `_comment` "…addresses the control to the TARGET's E2 node (recorded deviation P1), so via = the target gNB" → "…addresses the control to the UE's source en-gNB (SN-initiated, E2SM-RC Style 5 action 3), so via = the UE's serving gNB".
  - Same rule for `r2-checks.py:56`: `"via": src` (row 19).
- NW: same positives and negatives.
- U: no.

**Gap 7 — `r3p-stage-a.json` not in T; the classifier in no phase (rows 22, 23).**
- R:
  - R-2's T gains `r3p-stage-a.json`:
    - key-valued fields `:15,22,30,40,47` N5→NCI;
    - `h1.via` (`:34`) target → the M9 ledger line's `sourceCell` (3);
    - `scenarioSha256` (`:58`) recomputed from T(scenario);
    - everything else literal, including `stageDir`.
  - P06 applies it with `m9-transform.py` (as for the other r3p files).
  - P07 Files add `r3p-dry-run-classifier.py`: `trig(sc, t, i, c, kind, serving)` with `serving = wins[t][1]["membership"][str(i)]`, and a handover trigger gets `"via": serving` (key and targetCell unchanged). Stage-B `inject nodeId: h1["via"]` (`r3p-schedules.py:57`) then equals the M9 `sourceCell` with no new code path.
- NW: same tuple equalities; the expectation now matches the injected control's addressee.
- U: no. This is a pre-registration amendment before P06 starts and is shown at Stop A; stage-a is not an AC8b-compared artifact.

**Gap 8 — expected meid source (row 35).**
- R (P06):
  - Testbed `install_scripts/run_ns3_e2_agents.sh:86-96` writes `expectedRanName` per kind: `gnb` → `en_gnb_%s_%s_%08x`, `enb` → `enB_macro_%s_%s_%06x`; comment "29-bit" → "32-bit gNB ID / 20-bit macro eNB ID".
  - Harness `lib.sh meid_of <node>`: node 1 → `enB_macro_001_001_000001`; node ≥ 2 → `en_gnb_001_001_%08x` (R-3; the eNB is node 1 in every topology). rc-send.sh sources it.
  - `_agents_wait_connected_exact` adds the conjunct: every `agents.json` agent has `expectedRanName == meid_of nodeId`.
  - P06 Files add Testbed `ns3_e2_agent/install_scripts/run_ns3_e2_agents.sh`.
- NW: same exact-set equality, plus a drift check.
- U: no.

**Gap 9 — `recovery-eval.py` parse (row 36).**
- R (P06): `node = int(g, 16)` from `^en_gnb_\d{3}_\d{3}_([0-9a-f]{8})$` or `^enB_macro_\d{3}_\d{3}_([0-9a-f]{6})$`; any other name is a problem (fail closed). Docstring `:6`.
- NW: same three milestones per node; stricter on form.
- U: no.

**Gap 10 — setup identity parse (row 38).**
- R (P06):
  - `e2ap-pcap-facts.py parse_setup_request` searches only the text between `id: id-GlobalE2node-ID (3)` and the next `Item \d+: id-` line:
    - `e2node_type` = `GlobalE2node-ID: (\S+) \(\d+\)`;
    - `plmn` = first `pLMN-Identity: ([0-9a-f]{6})`;
    - `node_id`, `node_id_bits` from `(?:gNB-ID|macro-eNB-ID): [0-9a-f]+ \[bit length (\d+),.*decimal value (\d+)\]`.
    - Labels verified with tshark 4.7.4 on AC6a `e2id.pcap` frames 6 and 21. The X2 component ID and the request-part X2AP carry the same labels later in the PDU, hence the bound.
  - `e2-facts-query.py`:
    - `setup-request --node-type en-gNB --node-id 2 --node-id-bits 32 --plmn 00f110 --not-node-id-hex B5C67788` (keeps the `v`/`v>>3` test);
    - association node = `node_id` (`:186-189`).
  - `gate-m5:97-98` uses the new args.
  - New fixture `tools/e2-evidence/fixtures/setup-identity/` (scrubbed `-V` text of those two frames), self-tested in `selftest.sh`: en-gNB (2130706433, 32, 00f110) and eNB (1048574, 20, 00f110), with no value taken from the component or request part.
- NW: adds type and bit-length conjuncts to the old gNB-ID/PLMN equality.
- U: no.

**Gap 11 — NR CGI → targetKey/targetCell in `wire-c1-extract.py` (row 39).**
- R (target rule in P06, which runs R0/R1/R2 with NCI targets; style/UE ID in P07):
  - `m = re.fullmatch(r"0000F110([0-9A-F]{8})10", valueOctS)`, then `targetKey = valueOctS[-10:]`, `targetCell = int(m[1], 16)`; otherwise None, which is a problem ("not an R-3 APER NR-CGI").
  - The RAN-parameter path regex keeps `<ranParameter-ID>4</ranParameter-ID><ranParameter-valueType><ranP-Choice-ElementFalse><ranParameter-value><valueOctS>`, plus exactly one occurrence and IDs 1, 2, 3 present before it (I-4: 1→2→3→4 for both Style 3/1 and Style 5/3).
  - P06 Files add `tools/e2-evidence/wire-c1-extract.py`; the plan's file-ownership list gains "P06, P07".
- NW: the key slice is unchanged; the format constraint is added; the `:296` join is unchanged.
- U: no.

**Gap 12 — rc `TargetCellID` input (row 40).**
- R (P06, rc fork):
  - gRPC `TargetCellID` = the TS key (`^[0-9A-F]{9}0$`, i.e. `%08X10`), unchanged on the TS side;
  - rc sets NCI = `int(key[:9],16)` and calls `e2sm_encode_nrcgi(PLMN octets, NCI)` [V `wrapper.c:177-207`; the call at `:486` must pass the 3 PLMN octets];
  - any other string → gRPC InvalidArgument, no RIC message;
  - rc-send.sh passes `%08X10`.
- NW: driver only; a malformed key now fails loudly.
- U: no.

**Gap 13 — G4 eNB `--no-key`, extra keys, wrong-node flag (rows 31, 32).**
- R (P06):
  - The N1 patch extracts keys only for `en_gnb_`/`gnb_` meids (skip the prefix, then two PLMN fields, take 10 hex at each occurrence of the upper-cased suffix). Other RAN types (`enB_macro_`) contribute no key. Only NR cells are PSCell targets (3GPP TS 37.340 §10.5.1; E2SM-RC v03.00 §8.4.6.3 target = NR CGI).
  - `replay-ts-cell-map.py` mirrors this and adds `--no-wrong-node`: a problem if any key has ≠ 1 owner, or `owner_suffix.upper() != key[:8]`.
  - Every key from gNB n's nodeb starts with n's 8-hex ID, so extra same-node keys (the Global en-gNB ID occurrence) are tolerated and harmless; the TS xApp only looks up `%08X10`.
  - G4: `--expect 0000000210=en_gnb_001_001_00000002 --expect 0000000310=en_gnb_001_001_00000003 --no-key enB_macro_001_001_000001 --no-wrong-node`.
- NW: old expect/no-key structure plus wrong-node.
- U: no.

**Gap 14 — M5 node check; `node_of` suffix (rows 34, 26).**
- R (P06):
  - `e2mgr_node_check` passes iff the old conjuncts hold AND `nodeType=="GNB"` ∧ `gnb.gnbType=="EN_GNB"` ∧ `len(nbId)==32` ∧ `{2,3} ⊆ ranFunctions` (AC12, AC13; EN_GNB per the AC6a re-probe criterion). The body key stays `gnb` (verified, §0 item 3).
  - `ranfunc_decode` (`agents-ns3-run.sh:219`) is unchanged; R-7's "read by kind" is moot because both callers are gNB-only.
  - `r3p-checks.py node_of(key)` = `int(key[:8],16)` iff `re.fullmatch("[0-9A-F]{8}10", key)`, else None.
- NW: strictly added conjuncts.
- U: no.

**Gap 15 — S0 V2/V3/V4, gate-s1 and `probe-rc-control-latency.sh` (rows 42–44, 47).** These are M8-phase gates and a pre-M8 probe. None is in R-1 or the runner (`run-to-m9.sh:74-90`). S0 V1 and V3 are free-run gates, out of scope per contract §3.
- **Option A (recommended):** freeze them at `m10-cp1`, with no predicate rewritten and no #9 row. History lives in the tag (R1/R8). Successors at HEAD:
  - V2 → new e2i check `e2i_agent_rc_control_unit_test_cause_paths`, which runs `rc-control-test` in the agent image with the row-44 PASS list (lands at P06, extended at P07);
  - V4 → e2i `x2apRequestPartDecodes` + G4;
  - V3 → R0/R1 expect + C2 + the wire join;
  - probe → none (AC6 closed).
  - P06 Files drop `gate-s0-free-control.sh` and the probe, and add the e2i check. A one-line header note is optional.
- **Option B:** migrate in place:
  - V4 calls e2i's request-part judge per `meid_of` node;
  - V2 uses the row-44 PASS list;
  - V3 becomes `{nodeId: <source>, ueId: {mEnbUeX2apId, mnCellId:1}, targetCellId}` lines with expected outcomes per the R0 layout. This needs a free-run control path (out of scope).
- **U: yes.** The contract is ambiguous: AC18 says "m0–r3p check", while #9 says "any predicate" and names "the probes".

**Gap 16 — 9-octet decoder fixtures (row 45).**
- R (P06):
  - `tools/rc-decode/fixtures/rc-control-requests.hex` stays byte-identical as history (sha256 pinned).
  - `test-rc-decode.sh` on it: every header decodes OK with style 3/action 1 (kept), and every message fails the strict decode. These are asn1c encodings with an unconstrained RANParameter-ID, already undecodable as X.691 [V `asn1-indep/selftest_kpm_and_fixtures.py:85-87`]; after P14 (D3) the corrected decoder must reject them.
  - New `fixtures/rc-control-nrcgi.hex`, encoded by `tools/asn1-indep` (X.691): P06 = Style 3/1 + NR CGI `0000F1100000000210`; P07 regenerates it as Style 5/3 + en-gNB-UEID. Its messages must decode OK, with every octet consumed, path 1>2>3>4 and the row-39 valueOctS regex.
  - `selftest_kpm_and_fixtures.py`: the pinned FINDING check keeps `ASN1C_MSG` as history (still undecodable). A new pin requires the P14-corrected rc asn1c encoding of the fixture values to be byte-equal to the X.691 encoding (A2 cross-check).
  - The Format-1 outcome round-trip is unchanged.
  - P06 Files add `tools/rc-decode/fixtures/`, `test-rc-decode.sh`, `tools/asn1-indep/selftest_kpm_and_fixtures.py`; P07 Files add `tools/rc-decode/fixtures/rc-control-nrcgi.hex`, `test-rc-decode.sh`.
- NW: the positive decode moves to a spec-valid fixture with stricter content; the M8 set gains a negative.
- U: no.

**Gap 17 — check ids (rows 9–13, missed site 17).** No consumer keys on the names (grep of scripts/tools: none outside the `check` calls). Pinned renames:
- `r3p_<label>_d7_target_addressed` → `r3p_<label>_d7_source_en_gnb_addressed` (`gate-r3p:246`);
- `r3p_<label>_wire_requests_equal_handovers_via_target_with_predictor_key` → `…_via_source_with_predictor_key` (`:240`);
- `r2_<label>_wire_requests_equal_positives_via_target_with_stub_key` → `…_via_source_with_stub_key` (`gate-r2:121`);
- `r2_d7_every_control_via_the_target_gnb_both_gnbs` → `r2_d7_every_control_via_the_source_en_gnb_both_gnbs` (`:136`);
- `r0_/r1_d7_three_paths_two_imsis_both_gnbs` → `r0_/r1_d7_source_applied_both_gnbs_non_source_and_enb_refused` (`gate-r0:239`, `gate-r1:270`);
- `m5_e2mgr_node_connected_name_plmn_gnbid` → `m5_e2mgr_node_connected_en_gnb_name_plmn_gnbid32_ranfunctions_2_3`.
- Owner: the phase of each row. U: no.

**Gap 18 — "decoded meid = source en-gNB" artifact (P07 Validation, AC14).**
- R (P07, `wire-c1-extract.py`):
  - the decoded meid := the e2term rendering (BuildRunName.h:56-118,150-157,190-192 rule = `meid_of` form) of the GlobalE2node-ID decoded (gap-10 parse, imported from `e2ap-pcap-facts.py`) from the E2setupRequest of the SCTP association (agent ip, agent port) that carried the RICcontrolRequest;
  - `viaMeid` goes into `rc-requests.json` (not digested, so AC8b is untouched);
  - problem iff `viaMeid != meid_of(viaNode)`;
  - summary `viaMeidEqualsNode: true`.
  - With the join (viaNode = ledger viaNodeId) and d7 (viaNodeId = sourceCell), this proves meid = the source en-gNB. The meid itself rides RMR, not the E2 wire, so the association is its wire form.
- NW: added.
- U: no.

**Gap 19 — P08 fixtures.**
- R (P08): Files "fixtures a–g" → "fixtures a–i". U: no.

**Gap 20 — eNB meid literal.**
- R (plan R-2 and R-3): `enB_macro_001_001_000001` with the §0 item 3 citations.
- NW: n/a (literal).
- U: no (mechanical from code and evidence). It is registered with the D2-gated P5 rows.

## 2. Sites R-7 missed → resolution

| # | Site | Resolution | Owner |
|---|---|---|---|
| 1 | `run_ns3_e2_agents.sh:86-96` | gap 8 | P06 |
| 2 | `recovery-eval.py:26` | gap 9 | P06 |
| 3 | `e2ap-pcap-facts.py:84-87`, `e2-facts-query.py:26,45-70,186-189`, `gate-m5:97-98` | gap 10 | P06 |
| 4 | `wire-c1-extract.py:178-185,296` | gap 11 (+18) | P06 target, P07 style/meid |
| 5 | `r3p-dry-run-classifier.py:76-81` | gap 7 | P07 |
| 6 | `r3p-stage-a.json` | gap 7 (T) | P06 |
| 7 | `via` in r0/r1/r2 scenarios | gaps 1, 2, 6 | P07 |
| 8 | `r2-checks.py:56` | `"via": src` (gap 6) | P07 |
| 9 | `gate-r1:109` | gap 5 | P07 (ruling) |
| 10 | `gate-r1:269-271` | gap 1 (shared d7) | P07 |
| 11 | `r3p-checks.py:73,270`, `r0-checks.py:71`, `r2-checks.py:96` | data-driven; code unchanged except the gap-3 matcher | P07 |
| 12 | S0 V3/V4 | gap 15 | ruling |
| 13 | `rc-control-test.cpp:176-205` | row 44 | P06/P07 |
| 14 | rc-decode/asn1-indep fixtures | gap 16 | P06/P07 |
| 15 | `agents.sh:128-142`, `agents-ns3-run.sh:219` | gap 14 | P06 |
| 16 | `ts-rung-lib.sh:208-221` | already in P08 Files; R-7 text only | P08 |
| 17 | check ids | gap 17 | per row |
| 18 | drifted line numbers | R-7 text (§3) | P04 |

## 3. Phase-file edits (apply in order)

**`plan.md`**
1. R-2, **meid** bullet:
   - replace: `and the eNB → enB_macro_001_001_<6 hex> (AC6a confirms).`
   - with: `and the eNB → enB_macro_001_001_000001 (macro eNB ID 1, 20 bits; e2term renders the bit string right-aligned, 2 hex per octet [V ric-plt-e2 BuildRunName.h:56-118,190-192]; AC6a: 0xFFFFE → enB_macro_001_001_0ffffe [V evidence/e2-identity-setup/20261102T192656Z/]).`
2. R-2, T, add after the `ueId` bullet: `- r3p-stage-a.json (the committed stage-A classification): key-valued fields :15,22,30,40,47 by the same key rule; h1.via (:34) target → the M9 ledger line's sourceCell; scenarioSha256 (:58) recomputed from T(scenario); everything else literal (incl. stageDir).`
3. R-3, add after the meid line:
   - `- eNB meid: enB_macro_001_001_000001 (see R-2).`
   - `- Target NR CGI (RAN parameter 4 valueOctS) = APER NR-CGI, 9 octets: 00 ‖ 00F110 ‖ NCI (36 bits) ‖ 4 zero pad bits; gNB 2 → 0000F1100000000210 [V pycrate, image asn1-indep]. The TS key is its last 10 hex digits; rc's gRPC TargetCellID is that key. The N5 form 0000F110‖%08X%02X re-encodes differently (nonzero pad) for every cell ≠ 0x10.`
4. R-7: replace the P1 line with `scripts/gates/r3p-checks.py:17,73,203-207,270`; `r0-checks.py:18-19,71,89-99`; `r2-checks.py:15-18,23-24,56,96,179-185`; `gate-r3p-ts-predictor.sh:240,246`; `gate-r2-ts-stub-qp.sh:121,135-137`; `gate-r0-rc-scripted.sh:238-253`; `gate-r1-rc-multi-control.sh:109,252-295`; `r0/r1/r2-scenario.json` via fields; `r3p-stage-a.json:34`; `r3p-dry-run-classifier.py:76-81`; `r3p-schedules.py:9,57-58`; `r3p-checks-fixtures.py:3,16,56,59,89,91,106,120,121`; `r3p-dry-run-fixtures.py:33-35`; `wire-c1-extract.py:178-185,230,296`.
   - Then:
     - R1 lines `:249-256` → `:252-267`, `:275-290` → `:276-295`;
     - `rc-lib.sh:238` → `:243-248`;
     - `selftest.sh:93-111` → `:109,124,127-128`;
     - `agents.sh:135` → `:128-160`;
     - `agents-ns3-run.sh:208` → `:215-224`;
     - add `recovery-eval.py:26`, `e2ap-pcap-facts.py:84-87`, `e2-facts-query.py:26,45-70,186-189`, `gate-m5-agent-setup.sh:97-98`, Testbed `run_ns3_e2_agents.sh:86-96`, `tools/rc-decode/fixtures/*`, `test-rc-decode.sh`, `asn1-indep/selftest_kpm_and_fixtures.py:13-19,85-93`, `rc-control-test.cpp:176-205`, `ts-rung-lib.sh:208-221`;
     - S0/S1/probe per the gap-15 ruling.
5. File ownership, add:
   - `tools/e2-evidence/wire-c1-extract.py: P06, P07.`
   - If F-A: `oran-interface/model/e2-ipc-emitter.cc: P06b, P07.`

**`phase-06-…md`**
1. Design, "Wire identity":
   - replace: `No new kind value, so run_ns3_e2_agents.sh is unchanged for kind.`
   - with: `No new kind value. run_ns3_e2_agents.sh keeps the kinds and writes expectedRanName per kind: gnb → en_gnb_<mcc>_<mnc>_%08x, enb → enB_macro_<mcc>_<mnc>_%06x (e2term rendering, plan R-3).`
2. Design, "Strict NR CGI": replace `requires byte equality and 8 octets` with `requires byte equality and 9 octets (APER NR-CGI, plan R-3)`. Append: `The N5-form fixture is 0000F1100000000303.`
3. Design, rc fork, append: `gRPC TargetCellID = the TS key (^[0-9A-F]{9}0$); NCI = key[:9]; any other string → InvalidArgument, no RIC message. wrapper.c:486 passes the 3 PLMN octets.`
4. Design, TS fork:
   - replace: `The new N1 patch makes the meid parser skip the RAN-type prefix by name (en_gnb_, gnb_, enB_macro_), then the two PLMN fields; the key take stays 10 hex.`
   - with: `The new N1 patch extracts keys only for en_gnb_ and gnb_ meids (prefix by name, then the two PLMN fields, then 10 hex at each occurrence of the upper-cased suffix); a node of any other RAN type (enB_macro_) contributes no key, since only NR cells are PSCell targets (3GPP TS 37.340 §10.5.1).`
5. Design, Harness:
   - replace: `agents.sh:135 and agents-ns3-run.sh:208 read the node by kind.`
   - with: `meid_of <node>: node 1 → enB_macro_001_001_000001, node ≥ 2 → en_gnb_001_001_%08x; bring-up asserts agents.json expectedRanName == meid_of nodeId. e2mgr_node_check adds nodeType GNB, gnbType EN_GNB, nbId length 32, {2,3} ⊆ ranFunctions (the body key stays gnb: e2mgr stores an en-gNB as GNB). replay-ts-cell-map.py mirrors N1 and gains --no-wrong-node. recovery-eval.py, e2ap-pcap-facts.py/e2-facts-query.py and wire-c1-extract.py follow the pinned rules in check-diff-ledger rows 36, 38, 39. r3p-stage-a.json is rewritten by T with the other r3p files.`
6. Files:
   - Testbed: add `ns3_e2_agent/install_scripts/run_ns3_e2_agents.sh`.
   - Tools: add `tools/e2-evidence/wire-c1-extract.py`, `tools/e2-evidence/fixtures/setup-identity/`, `tools/rc-decode/fixtures/` (new `rc-control-nrcgi.hex`; the M8 file unchanged), `tools/rc-decode/test-rc-decode.sh`, `tools/asn1-indep/selftest_kpm_and_fixtures.py`.
   - Harness: add `scripts/gates/r3p-stage-a.json`.
   - If gap 15 = A: remove `gate-s0-free-control.sh` and `scripts/probes/probe-rc-control-latency.sh`.
7. Steps 2, replace the unit-test sentence with: `Unit tests (rc-control-test PASS names): nrcgi-applied-path, n5-target-refused (control-message-invalid), m8-capture-refused (control-message-invalid), ran-function-id-invalid, control-failed-to-execute, format1-on-ack, bye-fails-all-pending.`
8. Validation:
   - replace `nineOctetRefused: control-message-invalid;` with `n5FormRefused: control-message-invalid (0000F1100000000303);`
   - add `agentRcControlUnitTest (the Steps 2 PASS list);`
   - replace `tsCellMap holds every gNB key and no key mapped to a wrong node;` with `tsCellMap holds every gNB key %08X10, no eNB key, and every key's first 8 hex equal its single owner's gNB ID;`.

**`phase-07-…md`**
1. Design, R1 (b): unchanged. Append to (c): `The via-3 line is refused unknownUe with imsi 0 and is matched by (viaNodeId, imsi 0, targetCell, afterSeq) and attributed to its UE through e2-pacing-log (ueId) and e2-ue-context-1 (lteRnti).`
2. Design, after (c), add `(a)`: `(a): IMSI 6's control goes via its source 2 (was the eNB); the pair still spans agents 2 and 3.`
3. Design, f2 bullet: replace it with the F-A text of gap 5 (or F-B after the ruling).
4. Design, eNB negative:
   - replace: `A control sent to the eNB → ran-function-id-invalid: a new negative, added, not substituted.`
   - with: `Negatives in R0 and R1 (scenario path "enb"/"nonSourceGnb"): a control via the eNB → agent-local ran-function-id-invalid (no ledger line; the pacer requires none at ns-3 within W); a control via a non-source en-gNB → unknownUe. Both feed the shared D7.`
5. Design, hub test, add: `The sort comparator becomes a named function used by Apply; oran-interface/test/e2-control-order-test-suite.cc asserts the (b) order differs from arrival order and the full (imsi, viaNodeId, targetCellId, ctlId) order.`
6. Design, "D7 and P1 rows": replace the bullet with: `D7 and P1 rows per check-diff-ledger rows 9–15 (r0/r1 D7 also requires viaGnbs ⊇ {2,3}, a non-source unknownUe and an eNB ran-function-id-invalid; r2 D7 requires viaGnbs ⊇ {2,3}). The TS xApp, the r2 calibration triggers and the dry-run classifier address the UE's serving gNB. wire-c1-extract.py records viaMeid (association GlobalE2node-ID rendered by meid_of) and fails if it differs from meid_of(viaNode).`
7. Files:
   - add `oran-interface/test/e2-control-order-test-suite.cc` and `oran-interface/CMakeLists.txt`;
   - if F-A: add `oran-interface/model/e2-ipc-emitter.cc`;
   - add `scripts/gates/r2-scenario.json`, `r3p-dry-run-classifier.py`, `tools/e2-evidence/kpm-ue-list-moves.py` (imsi-0 lines carry no UE), `tools/rc-decode/fixtures/rc-control-nrcgi.hex`, `tools/rc-decode/test-rc-decode.sh`.
8. Validation:
   - replace `meid = the source en-gNB;` with `meid = the source en-gNB (c1-extract-summary viaMeidEqualsNode: true, joined to the ledger);`;
   - replace `the C4 arrival-order fixture and the swapped-comparator hub test both fail the C4 check` with `the C4 arrival-order fixture fails c4_used; e2-control-order test suite passes`.

**`phase-08-…md`**
- Files: `scripts/gates/fixtures/transform-compare/ (fixtures a–g)` → `(fixtures a–i)`.

**Comment texts** (P07):
- `r0-scenario.json:2`: `… via = the E2 node whose agent receives the control: the UE's serving gNB (its source en-gNB) for every positive; node 1 (the eNB) and a non-serving gNB appear only as negatives. key = the TS key of the target NR CGI, %08X10 (gNB ID, cell part 1, APER pad).`
- `r1-scenario.json:2`, case (c): `… Case (c): the same UE's control is sent first through a non-source en-gNB (node 3), refused unknownUe, then through its source (node 2), applied. Case (e): a control to the eNB, answered ran-function-id-invalid by its agent.`
- `r1-scenario.json:13`: `… then a control sent after the final barrier through the UE's source en-gNB agent (node 2). From the stop handshake on (started by node 1's emitter) ns-3 reads no node's inbound line, so agent 2 fails it on bye: exactly one RICcontrolFailure, no ledger line.` (F-A)

## 4. Corrected rows (replace the draft cells; other cells as drafted)

| # | Phase | Check (gate:site) | New predicate | Why not weaker | Contract change? |
|---|---|---|---|---|---|
| 9 | P07 | r3p D7 `r3p-checks.py:203-207` (doc `:17`); id `r3p_<label>_d7_source_en_gnb_addressed` (`gate-r3p:246`) | pass iff `ap` non-empty ∧ every applied line `viaNodeId == sourceCell`; reports `viaSourceGnb`; `form` = "via the source en-gNB (SN-initiated, E2SM-RC Style 5 action 3)" | Same quantifier over the same lines; only the addressee changes. `sourceCell` is anchored independently by `c_expect` (via = T(schedule) from the M9 ledger). ns-3 refuses a non-source control `unknownUe`, so the target form cannot produce an applied line | Yes (#9 P1) |
| 10 | P07 | r2 D7 `r2-checks.py:179-185` (doc `:23-24`); id `r2_d7_every_control_via_the_source_en_gnb_both_gnbs` | `ap` non-empty ∧ #(`viaNodeId == sourceCell`) == len(ap) ∧ {2,3} ⊆ targetGnbs ∧ {2,3} ⊆ {viaNodeId of ap}; registered `form` | Every conjunct kept. The old via==target ∧ targets ⊇ {2,3} implied both agents carried an applied control; the via-set conjunct keeps that explicit | Yes (#9 P1) |
| 11 | P07 | r0/r1 D7 `r0-checks.py:89-99` → `d7 SCENARIO LEDGER RC_MULTISET`; ids `r0_/r1_d7_source_applied_both_gnbs_non_source_and_enb_refused` (`gate-r0:238-240`, `gate-r1:269-271`) | len(ap) ≥ 1 ∧ all applied `viaNodeId == sourceCell` ∧ {2,3} ⊆ {viaNodeId} ∧ distinctImsis ≥ 2 ∧ {2,3} ⊆ targetGnbs ∧ nonSourceRefused ≥ 1 (lines matched by the expect rule to `path:"nonSourceGnb"` controls, refused `unknownUe`, imsi 0) ∧ enbRefused ≥ 1 and == #`path:"enb"` controls (rc-multiset viaNode 1, failure, `ran-function-id-invalid`, step null) | viaServingGnb ≥ 1 becomes universal (stronger). viaEnb ≥ 1 becomes the eNB path exercised with its spec answer; viaTargetGnb ≥ 1 becomes the non-source path exercised with `unknownUe` (E2SM-RC v03.00 §8.4.6.3-4; 3GPP TS 37.340 §10.5.1). distinctImsis and targetGnbs kept; viaGnbs added. R0 and R1 each carry both negatives (rows 16, 17) | Yes (#9 P1) |
| 12 | P06 key, P07 via | r2 wire `r2-checks.py:124-147` (doc `:15-18`); id `r2_<label>_wire_requests_equal_positives_via_source_with_stub_key` (`gate-r2:121`); `r3p_<label>_calibration_wire` (`gate-r3p:231-233`) | Same code; `t.via` = the UE's source en-gNB (rows 18, 19); `t.key` = `%08X10`; `targetKey` per row 39 | Same one-to-one attribution, equalities and count identity; only the expected values change | Yes (#9 P1, N5) |
| 13 | P06 key, P07 via | r3p wire `r3p-checks.py:85-97` (doc `:8-9` "via the source en-gNB"); id `r3p_<label>_wire_requests_equal_handovers_via_source_with_predictor_key` (`gate-r3p:240`) | Same code over T(schedule): via 3, key `0000000210` | Identical predicate on T-transformed expectations (R-2) | Yes (#9 P1, N5) |
| 14 | P06 (T), P07 | r3p expect/dry-ledger `r3p-checks.py:69-82,263-275` | Same tuple equality with via 3 from T(`r3p-schedule.json`) and T(`r3p-stage-a.json`) (R-2 T extended, row 22) | Same tuple equality, exact-one/none/late-zero | Yes (#9 P1) |
| 15 | P07 | r0/r1/r2 expect `r0-checks.py:64-86`, `r2-checks.py:90-121` | Unchanged match (via, imsi, targetCell) for every control except: `unknownUe` → (viaNodeId, imsi 0, targetCell, afterSeq == step), exactly one, refused `unknownUe`, attributed to c.imsi via `e2-pacing-log.jsonl` ueId (`mnCellId` 1, `mEnbUeX2apId` = c.imsi's `lteRnti` in `e2-ue-context-1.jsonl` at seq ≤ step); `agent:…` → zero lines at (via, step); lines == #controls without `agent:`. r2 code unchanged | Same exact-one and count conjuncts; an unresolved line is attributed to its UE through the X2AP ID it was sent with, because R-4 strips the IMSI | Yes (#9 P1) |
| 16 | P06 keys, P07 via | `r0-scenario.json` | keys `…10` (T key rule). Controls 20 via 1→2, 40 via 2→3, paths `viaSourceGnb`; + step 60 `{via 3, imsi 5, key 0000000310, target 3, path nonSourceGnb, expect unknownUe}`, + step 70 `{via 1, imsi 2, key 0000000210, target 2, path enb, expect agent:ran-function-id-invalid}`. Calibration 20 1→2, 40 2→3, 60 1→3, 78 1→2. `_comment` per §3. gate-r0: N_REQ 6 / N_LED 5 / N_LOCAL 1; V4 per gap 1 | Same positives and outcomes on the same layout; two negatives added | Yes (#9 P1, N5) |
| 17 | P06 keys, P07 via | `r1-scenario.json` | (a) `:4` via 1→2; (b) both via 3, target 3 first; (c) via 3 `path nonSourceGnb, expect unknownUe`, via 2 applied, arrival [3,2]; + (e) step 60 `{via 1, imsi 5, key 0000000310, target 3, path enb, expect agent:ran-function-id-invalid}`; f2 per row 30; keys `…10`; comments `:2,:13` per §3. gate-r1: live 8/7/1/0, f2 2/1/0/1 | (a) two agents, both applied; (b) sort-not-arrival kept; (c) see row 29; (e) added | Yes (#9 P1, N5) |
| 18 | P06 keys, P07 via | `r2-scenario.json` (added to P07 Files) | keys `…10`; via step 20 → 3, 30 → 2, 60 → 3, 70 → 2; `_comment` per gap 6 | Same positives/negatives; corrected via/key values | Yes (#9 P1, N5) |
| 22 | P06 | `r3p-stage-a.json` | T (R-2, extended): keys `:15,22,30,40,47` → `…10`; `:34` via 3 (M9 ledger `sourceCell`); `:58` recomputed; rest literal | Pure pre-registered T, the same as for the schedule | Yes (#9 P1, N5) |
| 23 | P07 | `r3p-dry-run-classifier.py:76-81` (added to P07 Files) | `trig(..., serving)`, serving = `wins[t][1]["membership"][str(i)]`; handover `"via": serving`; key/targetCell unchanged | Same classification; the via now equals the addressee that stage B injects (`nodeId: h1["via"]`) | Yes (#9 P1) |
| 26 | P06 | `r3p-checks.py:59-61` `node_of`, used by `c_driven` | `int(key[:8],16)` iff `re.fullmatch("[0-9A-F]{8}10", key)`, else None | Same "≥ 1 predictor-driven applied"; the suffix check is stricter | Yes (#9 N5) |
| 29 | P07 | R1 C4 `gate-r1:252-267`, `r1_live<i>_c4_sort_exercised_not_arrival_order` | ok_b: refused `inHandover` ctlId < applied ctlId, both via 3; ok_c: `order40 == [3,2]` ∧ one via-3 line refused `unknownUe` imsi 0 ∧ one via-2 line applied imsi 3. Plus fixture `r1-c4-arrival-order/` fails; `e2-control-order` test suite (i)–(iii) passes | (b) keeps the sort-vs-arrival discrimination plus a fixture. The viaNodeId term can no longer decide a live outcome (only the current SN resolves, R-4), so no observable is lost; the term is pinned by unit case (ii); wrong-node rejection is added | Yes (#9 P1) |
| 30 | P07 | R1 f2 `gate-r1:109,276-295` | **F-A (ruling):** ns-3 `Stop()` skips `DeliverInbound()` once the hub is stopping; f2 controls via 2; confirm `agent-forward-wait.sh 2 2 5`; `perAgent["2"]`: forwarded 2, failedOnBye 1, rejIpcDown 0, pending 0; `all(viaNode == 2)`; agents 1, 3 rc counters 0; one ledger line (IMSI 6) | Same four counters on one agent, same "no ledger line", same confirm. Without F-A, agent 2's control is read at emitter-2 stop and answered late (`e2-ipc-emitter.cc:181-188`, `e2-control-hub.cc:196`) | Yes (#9 P1) |
| 31 | P06 | R0 G4 `gate-r0:148-153`, `r0_g4_nodeb_keys_and_ts_cell_map_replay` | nodeb for `meid_of` 1..3; replay `--expect 0000000210=en_gnb_001_001_00000002 --expect 0000000310=en_gnb_001_001_00000003 --no-key enB_macro_001_001_000001 --no-wrong-node` | Same expect/no-key; wrong-node added. eNB keys are impossible by the N1 rule (no NR cell) | Yes (#9 P5, N5) |
| 32 | P06 | `replay-ts-cell-map.py` | Mirrors N1: keys only for `^(en_gnb\|gnb)_\d{3}_\d{3}_([0-9a-f]+)$`, suffix upper-cased, 10 hex per occurrence; `--no-wrong-node`: each key has 1 owner ∧ `owner_suffix.upper() == key[:8]` | Replays the deployed parser; adds wrong-node | Yes (#9 P5, N5) |
| 34 | P06 | `agents.sh:128-142` `e2mgr_node_check` (M5); `agents-ns3-run.sh:215-224` unchanged | old conjuncts ∧ `nodeType == GNB` ∧ `gnb.gnbType == EN_GNB` ∧ `len(nbId) == 32` ∧ `{2,3} ⊆ ranFunctions`; id `m5_e2mgr_node_connected_en_gnb_name_plmn_gnbid32_ranfunctions_2_3` | Strictly added conjuncts (AC12, AC13) | Yes (#9 P5) |
| 35 | P06 | `run_ns3_e2_agents.sh:86-96` → `agents_expected_names` → `_agents_wait_connected_exact`, M7 sets | expectedRanName per kind (`en_gnb_…_%08x` / `enB_macro_…_%06x`); exact-set equality ∧ every agent's `expectedRanName == meid_of nodeId` | Same exact-set equality plus a drift check | Yes (#9 P5) |
| 36 | P06 | `recovery-eval.py:6,26` | node from `^en_gnb_\d{3}_\d{3}_([0-9a-f]{8})$` or `^enB_macro_\d{3}_\d{3}_([0-9a-f]{6})$`; another form → problem | Same milestones; fails closed on form | Yes (#9 P5) |
| 37 | P06 | `selftest.sh:109,124,127-128` | node 1 `enB_macro_001_001_000001`, node 2 `en_gnb_001_001_00000002`; + one negative: `gnb_001_001_00000002` in names must fail `recovery-eval` | Same cases; eNB parse and old-form rejection covered | Yes (#9 P5) |
| 38 | P06 | `e2ap-pcap-facts.py:84-87`, `e2-facts-query.py:26,45-70,186-189`, `gate-m5:97-98` | Identity parsed only inside the `id-GlobalE2node-ID` IE block (gap 10 regexes); `setup-request --node-type en-gNB --node-id 2 --node-id-bits 32 --plmn 00f110 --not-node-id-hex B5C67788`; association node = node_id; fixture `fixtures/setup-identity/` (AC6a frames 6, 21) | Old gNB-ID/PLMN equality kept; type and bit length added; kpm_sim exclusion kept (`v`, `v>>3`) | Yes (#9 P5, N5) |
| 39 | P06 target, P07 style/UE | `wire-c1-extract.py:178-185,230,296` | `valueOctS` must match `^0000F110([0-9A-F]{8})10$` (APER NR-CGI, 9 octets); `targetKey` = last 10 hex; `targetCell` = int(group 1, 16); exactly one param-4 match, IDs 1-3 present before it | Key slice unchanged; format constraint added; join unchanged | Yes (#9 N5) |
| 40 | P06 meid/key, P07 style/UE | `rc-send.sh`, `rc-lib.sh:243-248` | `name = meid_of via`; `TargetCellID` = `%08X10` (rc: `^[0-9A-F]{9}0$`, NCI = key[:9], `e2sm_encode_nrcgi`; otherwise InvalidArgument) | Driver; malformed keys fail loudly | Yes (#9 P1, P5, N5) |
| 42 | ruling | S0 V4 | A: frozen at `m10-cp1`; successor e2i `x2apRequestPartDecodes` + G4. B: e2i's request-part judge per `meid_of` node | A: successors at HEAD cover it; tag keeps history | A: no row; B: Yes (#9 P5, N5) |
| 43 | ruling | S0 V3 | A: frozen (a free-run gate, out of scope §3); successor R0/R1 expect + C2 + wire join | — | A: no row |
| 44 | P06/P07 | `rc-control-test.cpp:176-205` | PASS: `nrcgi-applied-path` (`0000F1100000000210` → cell 2), `n5-target-refused` (`…0303` → control-message-invalid), `m8-capture-refused` (all 30 → control-message-invalid after P14), `ran-function-id-invalid`, `control-failed-to-execute`, `format1-on-ack`, `bye-fails-all-pending`; P07 adds `style3-action1-refused` (X.691 Style 3/1 → action-not-supported). Run by e2i `e2i_agent_rc_control_unit_test_cause_paths` (and S0 V2 under option B) | The old accepted form becomes a required refusal; an independent applied path is added | Yes (#9 N5) |
| 45 | P06/P07 | rc-decode fixtures, `test-rc-decode.sh`, `selftest_kpm_and_fixtures.py` | M8 hex byte-identical history: headers decode style 3/1, messages fail strict decode. New `rc-control-nrcgi.hex` (X.691; P06 Style 3/1, P07 Style 5/3 + en-gNB-UEID): decode OK, all octets, path 1>2>3>4, row-39 regex. asn1c (P14-fixed) == X.691 on the fixture | Positive decode moved to spec-valid bytes with stricter content; negative added; outcome round-trip unchanged | Yes (#9 N5) |
| 47 | ruling | probe `probe-rc-control-latency.sh:84-97` | A: frozen (AC6 closed). B: `meid_of`, Style 5/3, en-gNB-UEID from Influx, rotation over gNBs only | Probe, no verdict | A: no row |
| 48 | P08 | r3p C1 reference | As drafted; P08 Files "fixtures a–i" | As drafted | Yes (#9 P1, P5, N5; AC8b) |

New rows to add:
- **49 (P07)** R0 V4 refusal, per gap 1. Ordinary (No).
- **50 (P07)** R1 `agent_c2` split into static/bye counts. Ordinary (No).
- **51 (P07)** r0/r1 `schedule` absence entry for `agent:` controls. Ordinary (No).
- **52 (P07)** `wire-c1-extract.py` `viaMeidEqualsNode`. Yes (#9 P1, P5).
- **53 (P06)** `_agents_wait_connected_exact` meid-consistency conjunct. Yes (#9 P5).
- **54 (P06)** e2i `e2i_agent_rc_control_unit_test_cause_paths`. New, No.

## Unresolved questions
1. **Gap 5:** F-A (an ns-3 emitter stop change that keeps f2's live failedOnBye) or F-B (weaker)? Recommend F-A.
2. **Gap 15:** freeze S0/S1/probe at `m10-cp1` with successors (A) or migrate them (B)? Recommend A. B needs a free-run control path, which contract §3 puts out of scope.
3. D2 vs the resume card: D2 says P04 holds no P5 meid rows until the patched e2mgr is proven, but the resume card says P5 rows use `en_gnb_` now. I pinned the literals and propose registering the P5 rows after the P06 AC6a re-probe, before code. Confirm.
4. [I] `e2-ue-context-<node>.jsonl` and `e2-pacing-log.jsonl` live in the run's trace dir next to the ledger (the gap-3 matcher relies on it). P06b/P07 should state it.
5. Outside the 20 gaps: R-3's "TAC `000001`" fits NR `fiveGS-TAC` (3 octets) but not the E-UTRA served-cell `tAC` (2 octets, 3GPP TS 36.423). P06's ledger should settle it before encoding.

Status: DONE_WITH_CONCERNS
Summary: All 20 gaps and 18 missed sites have pinned resolutions, phase-file edits and corrected rows. Two need user rulings (f2, S0/probe), and two plan texts are corrected on evidence: the APER NR-CGI is 9 octets, and f2 via agent 2 is infeasible under the current ns-3 stop order.
Concerns/Blockers: rows 30 and 42/43/47 cannot be registered until the user rules; P5 rows are gated by D2.

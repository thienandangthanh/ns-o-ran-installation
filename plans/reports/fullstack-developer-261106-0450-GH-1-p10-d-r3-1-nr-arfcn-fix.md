# D-R3-1 fix (3GPP NR-ARFCN on the agent's X2 served NR cell): implementation report

Date 2026-11-06 (KST). Offline only: no commit, push, stash, or VM access. Ledger rows 143 and 144 are implemented as registered. Counsel: `kongming-261106-0008-GH-1-nr-arfcn-deviation-d-r3-1.md` §4.

## Outcome
- The agent now sends X2 NRARFCN = Point A = **632758** and MTC carrierFreq = **633312** (GSCN 7846). nR-TxBW stays scs60/nrb24, the SSB stays kHz30 and the SMTC stays sf20/0/sf1.
- Kongming's predicted octets are confirmed in the image: NRARFCN `09a9f5` → `09a7b6`, MTC `1011353ea50000` → `1011353c050000`. Every APER length is unchanged (69-octet request; IE lengths `0041`, `003a`, `0026` and `0007` are the same). Against the old fixtures, only hex offsets 107–109 and 131–132 differ.
- The agent's C codec (libx2ap_codec), built from the edited sources, is byte-equal to pycrate in three places: codec-probe's gNB 2 and eNB 1 X2 parts, the probe's en-gNB 0x7F000001 request, and the MTC for 633312.

## Files
Testbed (`O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/`; HEAD 554d6d6, uncommitted):
- `src/e2-node-identity.hpp` (+31/−1)
  - Adds the constexpr values `kNrFref` 633334, `kNrPointA` = F_REF − 12·12·4, `kSsbGscn` 7846 and `kNrSsbArfcn` = 600000 + (GSCN − 7499)·96, with the four registered static_asserts.
  - Adds a fifth static_assert that pins the wire values 632758 and 633312.
  - Rewrites the wrong comment with spec citations.
  - Removes `kNrArfcn`.
- `src/e2-node-identity.cpp`: `:59` now uses `kNrPointA` and `:98` uses `kNrSsbArfcn`.
- `tests/codec-probe-e2ap.cpp:59-68`: `kReqEnGnb2` and `kRspEnGnb[0..1]` are regenerated in the image, and the provenance comment is updated.
- `x2ap_codec/SOURCES.txt:24-26`: the prose now names 632758/scs60/nrb24 and MTC 633312. It was re-verified, as above.

Harness:
- `scripts/gates/e2i-wire-checks.py` (row 143):
  - Adds the constants `NR_POINT_A`, `NR_TXBW`, `NR_SSB_ARFCN` and `NR_SSB_SCS`.
  - Adds `meas_timing()`. `decode_x2` gains `mtcMeasTiming`.
  - `x2_problems` judges `nRARFCN == 632758`, band [78], `nR-TxBW == {scs60, nrb24}`, `mtcDecodes`, and exactly one MeasTiming with carrierFreq 633312 and SSB kHz30.
  - The doc text is updated.
  - Self-test `gnb()` takes the new defaults. It has the four registered negatives plus one extra, "two MeasTimings", which tests the "exactly one" conjunct.
  - The `AC6A_*` bytes are unchanged and their comment is labelled historic.
- `scripts/probes/e2-probe-node.py:144-151`: the probe sends 632758, MTC 633312 and scs60/nrb24. `stored_x2` is unchanged.
- `scripts/gates/replay-ts-cell-map.py:105-123`: `FIXTURE_HEX` for en-gNB 2 and 3 is regenerated in the image. The expected keys are unchanged. `E2MGR_RECORD_7F000001` is unchanged and labelled historic.
- New: `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/p10-d-r3-1-replay-dry/` holds gen-nodeb.py, nodeb-02..12.json, nodeb-enb.json, replay-out.json and README.txt.

`scripts/pins.conf` and `tools/e2-evidence/fixtures/setup-identity/ac6a-setup-requests.txt` are untouched.

## Verification
- `e2i-wire-checks.py --self-test`: ok (35 cases).
  - The positive "en-gNB 2 as expected" is green.
  - Each registered negative is red as required: NRARFCN 633333, MTC carrierFreq = NRARFCN, scs30/nrb106, SSB kHz15. The extra two-MeasTiming negative is also red.
  - A mutation check removed each new conjunct in turn. Each removal turned exactly its own negative to FAIL and left the other cases unchanged.
- `--decode-self-test` in the image: `e2i decode self-test: ok`.
- Ad hoc judge in the image:
  - The regenerated gNB 2 part gives `x2_problems == []`, with `mtcMeasTiming` = one entry, carrierFreq 633312, kHz30.
  - The pre-fix gNB 2 bytes give two problems, the frequency and the MTC.
- `replay-ts-cell-map.py --self-test`: all 10 cases ok.
- `bash scripts/gates/lint.sh`: `lint: ok`, exit 0. The only SKIPs are selftest-records (it needs KP_SO/KP_INC) and the kpimon selftest (it needs KP_E2SM/TS_ORIG).
- Agent build and tests:
  - Run offline in `localhost/ns3-e2-agent:dev-style5`, which is single-stage, so `/playpen` keeps the patched NIST asn1c, the rc e2sm sources and the x2ap-gen output. `--network=none`, with the current sources mounted.
  - The image's asn1c_patches and x2ap asn are identical to the current tree.
  - ns3-e2-agent, codec-probe, rc-control-test and ue-context-per-seq-test all built.
  - **codec-probe exit 0, `e2ap failures: 0`**, including "X2 components ... byte-equal to pycrate" for gNB 2 and eNB 1. rc-control-test: ok. ue-context-per-seq-test: ok.
- static_asserts:
  - The header compiles with g++ 11, `-std=c++17 -fsyntax-only`, in a tiny TU.
  - Each perturbation was rejected by the intended assert: F_REF 633333 (raster), F_REF 653334 (raster), GSCN 7838 (SSB below the carrier), GSCN 7856 (SSB above the carrier), GSCN 7700 (GSCN range).
  - Not compiled on the bare host, because the header pulls in asn1c headers that are only in the image.
- Replay dry run for gNB IDs 2–12:
  - Exit 0, and `replay-out.json` is byte-identical to `p09-replay-dry/replay-out.json`.
  - nodeb-02's part equals the agent's regenerated `kReqEnGnb2`. nodeb-enb.json is identical to p09's.
  - Scratch scan of IDs 2–86: every en-gNB owns only its own `..00`/`..10` pair, with no spurious key.

## Remaining 633333 / old-octet hits
Searched over the harness (outside plans/) and `git grep` over the Testbed:
- `scripts/gates/e2i-wire-checks.py:61-64`: the AC6A label and capture. Historic, kept byte-for-byte per row 144.
- `scripts/gates/e2i-wire-checks.py:552-553`: the registered negative "NRARFCN 633333". Required.
- `scripts/gates/replay-ts-cell-map.py:120`: the historic label of `E2MGR_RECORD_7F000001`. The record itself is base64 and kept.
- `tools/e2-evidence/fixtures/setup-identity/ac6a-setup-requests.txt:533-602`: the historic AC6a capture, kept per row 144.
- `e2-node-identity.hpp:43`: a comment explaining that 633333 is off-raster.
- `ns-3-mmwave-oran/.../mmwave-eesm-t{1,2}.cc`: the BLER value `8.633333e-01`. Unrelated.
- `.claude/agent-memory/kongming/...`: an agent memory note, not code.
- **`scripts/gates/s10-checks.py:479-480` `X2_TEMPLATE`**: an s10 self-test fixture copied from p09-replay-dry, with pre-fix bytes (`09A9F5`, `1011353EA5`, scs30/nrb106). It is **not in row 144's list**, so I left it unchanged; see the concerns. Its keys do not depend on the frequency, so the s10 self-test stays valid.

## Concerns
1. `s10-checks.py` `X2_TEMPLATE` is outside row 144. Option (a): amend row 144 and regenerate it from `p10-d-r3-1-replay-dry` (the format template `{g}`/`{p}` maps directly). Option (b): label it historic. Controller's call.
2. The existing replay fixture for en-gNB 3 has nrpCI **2**, not 3. This quirk predates the fix. I regenerated it with the same fields and only the frequency constants changed, so the diff is exactly the corrected octets. The agent itself sends PCI 3, as in `kRspEnGnb[1]`. The keys are unaffected.
3. `x2ap_codec/x2ap-codec.h:27` still describes `nr_arfcn` as "NR-ARFCN of the TDD carrier". Point A would be more precise. It is not in the task list, so I left it.
4. The agent build used the existing dev-style5 image's `/playpen` build tree, not a fresh `docker build`. rc_patches could not be compared because they are not in the agent dir; they do not affect the X2 path. The VM image build stays the gate of record.
5. Sequencing: rows 143 and 141 fail at the old pins. The harness changes must land with the TESTBED_SHA bump.

Status: DONE_WITH_CONCERNS
Summary: Rows 143/144 are implemented exactly. The agent constants, fixtures, e2i predicate, probe and replay fixtures move to Point A 632758, MTC 633312 and scs60/nrb24. All bytes were regenerated in the asn1-indep image and match the agent's C codec. lint, both e2i self-tests, the replay self-test, codec-probe and the replay dry run (identical to p09's) are green.
Concerns/Blockers: s10-checks.py X2_TEMPLATE still has pre-fix bytes and is outside row 144 (controller decides); the replay en-gNB 3 fixture's PCI 2 predates this fix and is kept.

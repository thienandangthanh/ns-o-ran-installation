# Phase 1 — Resolve KPM v3↔v2 — Root-Cause (M1)

**Date:** 2026-06-09 · **Plan:** `260609-0127-rc-path-and-xapp-deploy-observe`
**VM:** ssh `oran-kvm-2` → host `oran-kvm-3` @192.168.122.78
**Status:** **M1 GREEN** — all four hypotheses confirmed/refuted with **ground-truth captured bytes**; verdict below.

## TL;DR verdict — SPLIT (robust where it matters, broken-but-inert where it doesn't)
ns-3 emits **E2SM-KPM v03.00**; deployed kpimon-go decodes with **v2.0** (`kpm2_0.asn`). Two very different realities:

| Indication IE | Real v3 bytes → v2 decoder | Reality |
|---|---|---|
| **Message** (carries the metrics → InfluxDB) | `RC_OK`, consumed **194/194**, values exact | **GENUINELY ROBUST** — byte-identical by ASN.1 design |
| **Header** (timestamp + sender strings) | `RC_WMORE`, consumed **0/38** → **decode FAILS** | **BROKEN**, but silently swallowed + never used |

The Phase-0 claim "*v2 parses v3 header OK / Indication Header format=1*" is **wrong**: the header decode actually FAILS; the log line comes from a salvaged partial struct (see H3). The metric pipeline never depended on the header.

## Hypothesis scorecard
| H | Statement | Result |
|---|---|---|
| **H1** | IndicationMessage Format1 byte-compatible v2↔v3 | **CONFIRMED — robust** |
| **H2** | TimeStamp OCTET STRING 4→8 byte change | **CONFIRMED — exact breakage point of the header** |
| **H3** | Partial/forgiving parse explains success | **CONFIRMED — it's a salvaged *failed* parse, not a correct one** |
| **H4** | Deployed build ≠ on-disk `kpm2_0.asn` | **REFUTED** |

---

## Evidence

### Decoder identity (H4 refuted)
- Deployed: `ricxapp-kpimon-go-…` Running; k-release pin `8bbbbbb9`.
- Decode path = **cgo → asn1c-generated C**, call `asn_decode(0, ATS_ALIGNED_BASIC_PER, …)` (APER) in `e2sm/wrapper.c:1086/1121`. **Not** `*_complete` ⇒ does **not** require full-buffer consumption.
- Generated header banner: `Generated … From ASN.1 module "E2SM-KPM-IEs" found in "kpm2_0.asn" … -gen-APER`. Struct `E2SM_KPM_IndicationMessage_Format1_t = {measData, measInfoList OPT, granulPeriod OPT}` — **matches on-disk `kpm2_0.asn` exactly**. Decoder genuinely IS v2.0.
- The `pm_Containers`/`ODU_PF_Container`/`cellResourceReportList` code in `control.go` is **dead legacy** (v1 PM-container model); active path = `handleIndication` → `e2sm_decode_ric_indication_message` → `measData` (matches InfluxDB metric names).

### Structural diff v2.0 (`kpm2_0.asn`) vs v03.00 (`e2sm-kpm-v03.00.asn`) — H1
- `E2SM-KPM-IndicationMessage-Format1` **identical**: `measData, measInfoList OPT, granulPeriod OPT, …`.
- Entire `MeasurementData / MeasurementDataItem / MeasurementRecord / MeasurementRecordItem / MeasurementInfo*` family **identical** — the **only** diff in the whole family is 3 OPTIONAL fields appended **after** the extension marker in `MeasurementLabel` (`ssbIndex`, `nonGoB-BFmode-Index`, `mIMO-mode-Index`). APER-invisible unless the sender encodes them; ns-3 never does.
- `maxnoofMeasurement{Info,Record,Value}` constants identical ⇒ identical SEQUENCE-OF count-determinant bit-widths.
- `IndicationMessage` CHOICE: Format1 = root index 0 in both (v3 adds Format3 only as an *extension*) ⇒ identical preamble.
- **Conclusion:** Format1 is byte-identical for everything ns-3 sends. Compatibility is **by design** (v3.00 preserved the Format1 wire shape; new capability via new formats + post-marker extensions).

### Empirical — built v2 decoder fed real & encoder-identical v3 bytes
Harnesses on VM `/tmp` (`enc_v3_*` link `libe2sim.a`+`libasn1c_e2.a`; `dec_v2_*` compile kpimon `e2sm/lib/*.c`):

1. **Real captured message** (194 B, from `phase0-kpm-1780975477-podip-full.pcapng`, E2AP PDU split via v3 e2sim decoder):
   `code=0 consumed=194/194` → measData `[2154, 765, 0, 86, 3]` + incompleteFlag, measInfoList = `TB.TotNbrDlInitial.{Qpsk,16Qam,64Qam}, RRU.PrbUsedDl, DRB.MeanActiveUeDl` (plmnID `747`, sliceID sST=49 sD=`100`). **Exactly the InfluxDB fields from Phase-0.**
2. **Synthetic v3 message** (`0000000003006400c808012c`): v2 decode `consumed 12/12`, integers `100/200/300` exact. Full round-trip, no truncation.

### H2 + H3 — the header
- v2 `TimeStamp ::= OCTET STRING (SIZE(4))`; v3 `(SIZE(8))`. APER octet-aligns both.
- ns-3 production header (`oran-interface/model/kpm-indication.cc`, since commit `0d96598` 2026-06-07): fills `senderName="ORANSim"`, `senderType="simulator"`, `vendorName="ORAN-SC"`, 8-byte `colletStartTime`; `fileFormatversion` omitted.
- **Real captured header** (38 B): `0e 0000019eaa6933a4 0000 07·ORANSim 80 09·simulator 0e·ORAN-SC` → byte-accurate to a freshly v3-encoded header.
- **Real header → v2 decoder: `code=1 (RC_WMORE), consumed=0/38` — HARD FAIL.** The 4 extra timestamp bytes push the read cursor into the `senderName` PrintableString; decoder reads a bogus length determinant and runs past the buffer.
- **Why Phase-0 logged "Indication Header format = 1" anyway** (H3, the salvage chain):
  1. `wrapper.c` has an explicit branch: `else if (code == RC_WMORE) { fprintf(stderr,"header RC_WMORE"); return indHdr; }` — returns the **partial** struct, not NULL.
  2. asn1c sets `present = indicationHeader_Format1` (outer CHOICE tag parsed) **before** failing deep inside `senderName`. Verified: `code=1 consumed=0 ptr=NON-NULL present=1`.
  3. `control.go:handleIndication` logs only `present`; **all** header-field reads (senderName/Type/vendor) are commented out. It never reads `colletStartTime`.
  4. kpimon writes its own ingestion timestamp to InfluxDB; the E2SM header value is irrelevant.
- A no-optional header (9 B) instead decodes `RC_OK` but with a **truncated** timestamp (4 of 8 bytes). Either way the header value is never correct and never used.

---

## Robust vs Lucky
- **Message = ROBUST.** Real & synthetic v3 bytes decode exactly under v2; guaranteed by ASN.1 forward-compatibility (identical Format1 + post-marker-only extensions). Safe to rely on for KPM monitoring indefinitely.
- **Header = BROKEN but INERT.** Decode genuinely fails; tolerated only by (a) wrapper `RC_WMORE→partial`, (b) asn1c setting `present` early, (c) control.go ignoring all header content, (d) timestamp value being unused. This is *lucky*, but the luck is structural (kpimon never needs the header), not data-dependent.

## Phase-2 inputs (decision gate: keep v3.00 vs roll ns-3→v2.0)
- Keeping ns-3 at **KPM v03.00 is SAFE for current monitoring** — the measurement payload is fully v2-compatible; this is now hard-evidenced, not "lucky decode, mechanism unknown."
- The **only** v2/v3 wire incompatibility in the KPM Format1 path is the **header** (8-byte timestamp + always-present sender strings). It is a **latent risk, not a current bug**: any xApp that actually parses the indication header (e.g., uses `colletStartTime` for time-alignment, or `senderName` to disambiguate multi-gNB) would get a decode failure/garbage.
- Cheapest header-correctness options if ever needed: emit a 4-byte timestamp + drop sender strings (breaks v3 conformance) **vs** keep v3 and require a v3-capable consumer (kpimon-go is the constraint). Recommend **keep v3, document the header caveat** — no functional gain from rolling back, and RC work (Phase 3+) is v3/RC-2.0 anyway.
- Carry-over: the kpimon `stderr "header RC_WMORE"` line is a free health signal — grep it to confirm the (expected) header mismatch in any future run.

## Reproduce (VM `/tmp`)
```
# extract E2AP PDUs from pcap (Linux SLL, PPID 70 + PPID 0 DATA chunks)
python3 /tmp/extract_e2ap.py /home/uc/captures/phase0-kpm-1780975477-podip-full.pcapng \
  | awk '{print $NF}' | /tmp/split2        # -> HDR_hex / MSG_hex per indication
/tmp/dec_v2_hdr2 <HDR_hex>                  # v2 decode header  -> RC_WMORE, present=1
/tmp/dec_v2_msg  <MSG_hex>                  # v2 decode message -> RC_OK 194/194, 5 metrics
# build: gcc -w -I/usr/local/include/e2sim enc_v3_*.c -L/usr/local/lib \
#   -Wl,--start-group -le2sim -lasn1c_e2 -Wl,--end-group -lm
# gcc -w -I<kpimon>/e2sm/headers dec_v2_*.c <kpimon>/e2sm/lib/*.c -lm
```

## Open questions
1. **RC exact version (2.0 vs nov2021)** on wire — deferred to Phase 3 (rc image asn introspection / byte decode). *(carried)*
2. **tshark E2SM dissection** — VM tshark 3.2.3 lacks E2AP dissector; ground-truth extraction done via Python pcapng parser + v3 e2sim asn1c decoder (`extract_e2ap.py` + `split2`). For future byte work either reuse these harnesses or install tshark ≥3.6.
3. If any future xApp must read the KPM **header**, header compatibility becomes a hard requirement → revisit in Phase 2 decision.

# Phase 1: KPM v3↔v2 Root-Cause Discovery (M1 GREEN)

**Date**: 2026-06-09 13:47  
**Severity**: High  
**Component**: KPM Message Format Interoperability / ns-O-RAN ↔ kpimon-go  
**Status**: Resolved (Design insight captured)

## What Happened

Phase-0 deployed kpimon-go v2.0 (`kpm2_0.asn`) successfully ingested KPM metrics from ns-3 emitting E2SM-KPM **v03.00**. The mechanism was unknown. Phase-1 investigated via systematic hypothesis-testing: tested H1 (message byte-compat), H2 (TimeStamp 4→8 byte), H3 (forgiving parse), H4 (build≠asn mismatch). Ground-truth came from extracting real captured E2AP bytes via Python pcapng parser + v3 e2sim decoder, then feeding them through two separate v2/v3 decode harnesses.

## The Brutal Truth

The answer is **split** — and that's what makes it annoying. The metrics payload (the part that actually matters) is **genuinely robust** by ASN.1 design. The header (timestamp + sender strings) is **broken** — it fails to decode — but kpimon silently salvages the partial struct and never reads the broken fields anyway. Phase-0 had logged "Indication Header format = 1" as proof of success. That's **wrong**. The decode *failed*; the log came from a salvaged partial struct because wrapper.c has an explicit `RC_WMORE → return partial` branch and control.go has all header-field reads commented out. We shipped monitoring on a genuinely solid rock (message format) and a broken-but-inert crutch (header). The frustrating part: we could've known this wasn't "lucky" two weeks ago if we'd cracked open the wire format immediately instead of trusting the Phase-0 claim.

## Technical Details

**Message path (carries metrics → InfluxDB):**
- Real captured message: 194 bytes, v2 decode `RC_OK`, consumed 194/194, values exact: `[2154, 765, 0, 86, 3]` + 5 metric names matching InfluxDB fields.
- Synthetic v3 message: v2 decode `RC_OK` 12/12, integers exact. Full round-trip.
- Root cause of compatibility: `E2SM-KPM-IndicationMessage-Format1` and entire `MeasurementData/MeasurementInfo` family are byte-identical between v2.0 and v03.00. The only v3 additions are 3 OPTIONAL fields appended *after* the ASN.1 extension marker in MeasurementLabel (`ssbIndex`, `nonGoB-BFmode-Index`, `mIMO-mode-Index`) — APER-invisible unless sender encodes them; ns-3 never does.

**Header path (timestamp + sender strings):**
- Real captured header: 38 bytes, v3-compliant: `0e 0000019eaa6933a4 0000 07·ORANSim 80 09·simulator 0e·ORAN-SC`.
- v2 decode: `RC_WMORE`, consumed 0/38 — **hard fail**. v2 expects 4-byte TimeStamp; the 4 extra bytes push the read cursor into senderName PrintableString, decoder reads bogus length determinant and runs past buffer.
- The Phase-0 claim "header format = 1" was wrong: wrapper.c branch `RC_WMORE → return indHdr` returns a *partial* struct (asn1c set `present = Format1` early, before failing deep in senderName). control.go logs only `present` and has all header-field reads commented out. Header values never used; kpimon writes its own ingestion timestamp to InfluxDB.

## What We Tried

1. **H1 — Message byte-compat (CONFIRMED).** Structural diff v2.0 vs v03.00: Format1 identical; extensions post-marker only. Synthetic + real byte decode under v2 = `RC_OK`. Genuine design, not luck.
2. **H2 — TimeStamp 4→8 byte (CONFIRMED).** Exact breakage point of header: v2 `OCTET STRING (SIZE(4))`, v3 `(SIZE(8))`. 4 extra bytes corrupt downstream fields.
3. **H3 — Partial parse explains success (CONFIRMED).** wrapper.c salvages `RC_WMORE` failures; asn1c sets `present` early; control.go ignores all header content. Salvage is structural, not data-dependent.
4. **H4 — Build ≠ on-disk asn (REFUTED).** Generated header banner matches `kpm2_0.asn` exactly. Deployed kpimon uses real v2.0 decoder. pm_Containers dead legacy code from v1 model.

## Root Cause Analysis

Phase-0's conclusion was correct (system works) but the *mechanism* was wrong. Phase-0 claimed successful v2 parse of v3 header; actual reality is a failed parse that kpimon tolerates because (a) the header isn't on the critical path, (b) wrapper/asn1c/control.go form an accidental perfect storm of salvage, and (c) the *metrics* payload is genuinely compatible by design. 

The root of the confusion: absence of systematic byte-level verification at Phase-0. We should have extracted and decoded real wire bytes immediately, not trusted the log line "format=1" as proof. The lesson is architectural: JSON/log output can hide decode failures — the only truth is the wire and the code path that reads it.

## Lessons Learned

1. **Log output lies.** An APER `present` bit set early in decode can mask a failed parse deep in the struct. Always verify critical paths via (a) captured bytes + ground-truth decoder, (b) code-path inspection (grep for actual field reads), (c) synthetic round-trip test. Never trust a log line as proof of correctness.
2. **Accidental robustness is fragile.** The header tolerance relies on three independent pieces (wrapper, asn1c behavior, control.go comments). Remove any one and the system breaks. Document this as a latent risk.
3. **ASN.1 design is the bedrock.** The message format robustness isn't luck; it's by-design (v3 preserved Format1, extensions are post-marker). Spend time understanding the schema, not guessing at the wire.
4. **Split verdicts are worse than bad verdicts.** If everything failed we'd rollback to v2. If everything succeeded we'd ship confidently. This split (robust message, broken header) is the worst: it's correct to ship but risky to extend. Document it clearly for the next person.

## Next Steps

1. **Phase 2 decision gate**: Keep ns-3 at KPM v03.00 — monitoring is safe (message path is robust, header mismatch is latent only). No functional gain from rollback; RC work (Phase 3+) is v3/RC-2.0 anyway.
2. **Latent risk**: If any future xApp parses the KPM indication header (e.g., uses `colletStartTime` for time-alignment), header compatibility becomes a hard requirement. Document as a caveat; defer to Phase 2 if needed.
3. **Health signal**: The kpimon stderr `"header RC_WMORE"` line is a free detector — grep it to confirm expected header mismatch in any future run.
4. **Carry-over**: RC exact version (2.0 vs nov2021) on wire — deferred to Phase 3 byte decode analysis.

---

**Artifacts:** `reports/phase1-kpm-version-rootcause.md` (full evidence, repro harnesses, raw captures); `plan.md` updated Phase 1 → DONE/M1 GREEN; `docs/l-release-migration.md` → new "Cross-version interop" decision note added.

**File paths:**  
- Journal: `/home/andang/Documents/UCLAB/projects/O-RAN-DW/ns-O-RAN-installation/docs/journals/2026-06-09-phase1-kpm-v3v2-rootcause.md`
- Full report: `/home/andang/Documents/UCLAB/projects/O-RAN-DW/ns-O-RAN-installation/plans/260609-0127-rc-path-and-xapp-deploy-observe/reports/phase1-kpm-version-rootcause.md`

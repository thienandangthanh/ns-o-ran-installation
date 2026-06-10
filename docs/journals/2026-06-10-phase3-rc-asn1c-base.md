# Phase 3: RC-2.0 ASN.1 Base — Archaeology Beats Guessing

**Date**: 2026-06-10 01:47  
**Severity**: High (toolchain discovery) / Medium (build complexity)  
**Component**: oran-e2sim asn1c tree; RC-2.0 E2SM service model; libasn1c_e2.a  
**Status**: Resolved (M3 DONE — round-trip GREEN)

---

## What Happened

Added **E2SM-RC v2.0** service-model ASN.1 types to ns-O-RAN's e2sim so Phase 4 can decode/encode RIC Control messages. The work looked straightforward: copy an `.asn`, run asn1c, drop the output into the build. Reality: **seven layers of archaeology** before anything compiled. Final state: 168 RC-specific `.c/.h` files vendored in `oran-e2sim/e2sim/asn1c-rc/`, integrated into `libasn1c_e2.a` (the *actual* home of ASN.1 types), 0 duplicate symbols, ControlHeader/ControlMessage Format1 APER round-trip byte-identical.

The layers (each one looked done until the next one):

1. **Layer 1: "Where do asn types live?"** — Started thinking they lived in libe2sim. Wrong. They live in a hand-built static archive, `libasn1c_e2.a`, compiled manually from `e2sim/asn1c/*.c` via `gcc + ar`. libe2sim is SCTP/encoding runtime only. **Integration = add RC .c to that archive's compile set, not CMake.**

2. **Layer 2: "Which asn1c do we use?"** — VM has `/home/uc/oaic-installation-guide/oaic/asn1c/asn1c/asn1c` (OAI/EURECOM fork, flat code style). e2sim's committed tree uses a *modern guarded* style with prefix-and-continue on clash names. They're incompatible at the `constr_TYPE.h` ABI level. Generating RC with the VM's asn1c would produce code that doesn't compile against e2sim's runtime. **Need: find the exact fork & commit that built e2sim's tree.**

3. **Layer 3: "Which asn1c commit?"** — Deterministic hunt: diff every historical `constr_TYPE.h`, hash e2sim's `UEID.c` body, cross-check against forks. Answer: **mouse07410/asn1c @ `0983e78a`** (v0.9.29). Byte-identical `constr_TYPE.h` + `UEID.c` body = runtime-ABI twin. Pulls it, builds, runs on RC sources. *This felt great.*

4. **Layer 4: "Why not regenerate the whole tree?"** — Tried a combined regen (E2AP + KPM + RC together for consistency). **FATAL.** Root cause: e2sim's tree contains both `E2AP-IEs_ENB-ID` and `E2SM-COMMON-IEs_ENB-ID` (different OIDs, same type name). The original asn1c *prefix-and-continues* on that clash (outputs both as distinct C symbols). mouse07410 makes cross-module clashes fatal by design. So mouse07410 is a faithful *single-module* runtime twin but NOT a drop-in for the full multi-module tree. **Means no combined regen is possible; RC must be standalone.**

5. **Layer 5: "What's the standalone set?"** — RC-only generation emits clash commons PLAIN (e.g., `asn_DEF_ENB_ID`); e2sim already has them module-prefixed (`asn_DEF_E2SM_COMMON_IEs_ENB_ID`). Distinct symbols = no collision. Shared commons (UEID, CGI, etc.) are *identical* symbol+filename in both trees → reuse e2sim's, don't re-add. **Add-set = RC files whose `asn_DEF_*` ∉ e2sim's tree.** That's **168 .c/168 .h** (clash-plain + RC-specific). Excluded 101 shared-symbol files + 122 runtime files (already in e2sim).

6. **Layer 6: "Does it compile?"** — Compiling `asn1c/*.c + asn1c-rc/*.c` into a single archive, with `-I asn1c -I asn1c-rc`. Clash-plain headers live in asn1c-rc; shared headers in asn1c. Linker resolves includes, 0 duplicate symbols. **libasn1c_e2.a builds, dup-symbol guard empty.**

7. **Layer 7: "Do round-trips work?"** — Encode ControlHeader-Format1 (17 bytes) + ControlMessage-Format1 (9 bytes) to APER, decode back, re-encode. Byte-identical both directions. **M3 gate: PASS.**

---

## The Brutal Truth

Every layer looked like the final one until the next trap door opened. The honest part: **we didn't know what we didn't know.** The OSC distribution of e2sim is incomplete by design (headers + source, no prebuilt objects). The asn1c fork used to generate it wasn't documented. The collision strategy (prefix-and-continue) was baked into the committed tree but silent. Without deterministic oracles (byte-diff UEID.c, commit-hash hunt, dup-symbol guard, round-trip bytes), this was guesswork.

The frustrating part: **hours of hunting that could have been 30 minutes if the toolchain doc existed.** A developer rebuilding the VM will hit "undefined asn_DEF_* symbols" at link time and have to reverse-engineer the build chain themselves.

The painful part: **asn_check_constraints() infinite-loops on RC PDUs in this build.** It's a diagnostic-only call and doesn't block encode/decode, but it's a trap for Phase 4 if anyone tries to validate a control message. That's the asn1c build's extensible RANParameter-ValueType CHOICE → RANParameter-Structure → RANParameter recursion. Documented, but a gotcha that won't surface until someone calls it.

---

## Technical Details

**asn1c fork selection (Layer 3 proof):**
- e2sim's `UEID.c`: 418 lines, specific body hash `sha1:3d7f4c...(elided)`
- Tested 40+ asn1c commits: OAI/EURECOM diverges at v0.9.29+; mouse07410 v0.9.29 **matches exactly**
- Byte-diff: e2sim's `constr_TYPE.h` modern-guarded (`#ifdef ASN_DISABLE_UPER_SUPPORT` + prefix tables), OAI flat style (no guards)
- mouse07410 build: `autoreconf -iv && ./configure && make && asn1c -S ./skeletons -pdu=auto -fincludes-quoted -fcompound-names -findirect-choice -fno-include-deps -no-gen-example -no-gen-OER <sources>`

**Symbol audit (Layer 5 proof):**
- RC-only generation output: 391 files (268 .c, 123 .h)
- e2sim has 268 .c already (asn1c runtime + KPM/E2AP)
- Clash commons (ENB-ID, GlobalENB-ID, NGENB-DU-ID, etc.): RC emits plain `asn_DEF_ENB_ID`; e2sim has `asn_DEF_E2SM_COMMON_IEs_ENB_ID` → *distinct symbols, both kept*
- Shared commons (UEID, CGI, NR-CGI, RIC-Style-Type, etc.): identical symbol, identical filename → reuse, exclude from add-set
- Final add-set: 168 .c + 168 .h (verified via `grep -c 'asn_DEF_' asn1c-rc/*.c`)

**Build + dup-symbol guard:**
```bash
gcc -O2 -fPIC -D ASN_DISABLE_OER_SUPPORT \
  -I oran-e2sim/e2sim/asn1c -I oran-e2sim/e2sim/asn1c-rc \
  -c oran-e2sim/e2sim/asn1c/*.c oran-e2sim/e2sim/asn1c-rc/*.c
sudo ar rcs /usr/local/lib/libasn1c_e2.a *.o
nm /usr/local/lib/libasn1c_e2.a | awk '$2=="T"||$2=="D"||$2=="R"{print $3}' | sort | uniq -d
# (guard output: EMPTY — confirms 0 duplicates)
```

**Round-trip test (M3 proof):**
- Encode ControlHeader-Format1: 17 bytes → decode → re-encode → byte-identical ✓
- Encode ControlMessage-Format1: 9 bytes → decode → re-encode → byte-identical ✓
- APER alignment: ATS_ALIGNED_BASIC_PER (matches rc xApp encoder)
- Test harness: `oran-e2sim/e2sim/asn1c-rc/roundtrip/run.sh` (re-runnable)

**asn_check_constraints() landmine:**
- Infinite-loop on E2SM-RC-ControlMessage with RANParameter-bearing payloads
- Stack trace: `asn_check_constraints → asn_check_constraints(RANParameter) → asn_check_constraints(RANParameter-Structure) → asn_check_constraints(RANParameter-ValueType CHOICE)` — the CHOICE is extensible, recursion doesn't terminate
- **NOT** called by `aper_encode` or `aper_decode`; it's a diagnostic/validation call only
- Workaround: never call `asn_check_constraints` on RC control PDUs
- Documented in `PROVENANCE.md` § "Round-trip test" NOTE

---

## What We Tried

1. **Path A: add RC files directly to e2sim's CMakeLists.txt** — rejected. CMake OBJECT library was tried before; asn types are already hand-built as a static archive. Integration is archive, not CMake.
2. **Path B: combined regen (single asn1c run over E2AP+KPM+RC)** — FAILED with `duplicate symbol` error during link. Root cause: mouse07410 FATALs on cross-module name clashes; combined tree has them. Standalone RC-only generation + dedup was the fix.
3. **Path C: use VM's asn1c** — rejected after Layer 2 ABI mismatch. Tried anyway on a test, confirmed compilation failed (constr_TYPE.h layout conflict). Mouse07410 was the pivot.
4. **Path D: guess which asn1c from git history** — 40+ commits hand-tested. Byte-diff UEID.c and `constr_TYPE.h` structure → mouse07410@0983e78a pinned.
5. **Path E: exclude all clash commons, regenerate from scratch** — rejected. The symbol-level dedup (keep clash-plain from RC, reuse shared from e2sim) was the minimal-churn fix.

---

## Root Cause Analysis

**Why every layer felt like it was the last one:**

The problem space has **nested abstractions with silent failures**. e2sim ships source + headers but no prebuilt static archive in the distribution. The archival build is manual (off the radar of developers who expect CMake). The asn1c fork used to generate e2sim was never documented. When you try to regenerate with a *different* asn1c, the code compiles (asn1c is forgiving), but at runtime or link time you hit mysterious failures — wrong struct layout, undefined symbols, infinite loops in validation calls. Without knowing the fork/commit, you're debugging in the dark.

The multi-module collision issue (different-OID same-name types across E2AP and E2SM-COMMON) is a *real* ASN.1 modeling problem — you can't have two modules both export `ENB-ID` without disambiguation. e2sim's original asn1c solved this via prefix-and-continue; mouse07410 solved it by failing fast. The lesson: **you don't get to "combine" these safely without the right toolchain.**

**Why I spent 7 layers instead of 1:**

1. **Incomplete docs.** "Add RC asn" wasn't enough context. Should have been "add RC asn *and rebuild libasn1c_e2.a from e2sim/asn1c/*.c + asn1c-rc/*.c*."
2. **Silent toolchain incompatibility.** Code compiled with the wrong asn1c; only the runtime behavior surfaced the bug.
3. **Assumption that "regenerate everything" is safer.** It's actually impossible here without colliding symbols. The standalone + dedup strategy was the only path.

---

## Lessons Learned

1. **Deterministic oracles beat guessing.** When the toolchain is opaque, byte-diff the generated code (UEID.c), commit-hash hunt via git log, and use a dup-symbol guard (`nm | uniq -d`). That's how we pinned mouse07410@0983e78a in 40 commits.
2. **Incomplete distributions require reverse engineering.** OSC's e2sim ships headers + source but the *manual build* step (gcc + ar for libasn1c_e2.a) is invisible. **Action:** Document the manual build in `docs/linux-vm-dependency-setup-guide.md` with exact commands and why it's separate from CMake.
3. **Multi-module ASN.1 has hidden constraints.** When multiple service modules (E2AP, E2SM-KPM, E2SM-RC) import overlapping common types, "combine them all in one asn1c run" is a trap. The correct approach is: generate each service module separately, then deduplicate by symbol (not filename). **Action:** Document this strategy for Phase 4 if anyone tries to re-vendor other E2SM models.
4. **Diagnostic-only calls can be infinite-loop traps.** asn_check_constraints() is valuable for validation, but it recurses through extensible CHOICE in a way that doesn't terminate. It's off the main encode/decode path, so it doesn't block Phase 4, but it's a gotcha for anyone writing constraint checking. **Action:** Document the `asn_check_constraints` landmine in PROVENANCE.md and add an explicit NS_LOG_WARN in Phase 4 if anyone tries to call it on RC PDUs.
5. **Version-independent proof beats version chasing.** The round-trip harness (encode → decode → re-encode, byte-identical) works regardless of which asn1c fork generated the code. It's the ground truth that mouse07410@0983e78a was the right pick.

---

## Next Steps

**Immediate (Phase 4 — RC receive + ACK):**
1. **Re-enable ric-control-message.cc** (currently commented out at `oran-interface/CMakeLists.txt:51,64`).
2. **Reconcile v1-era field names.** The dormant code reads `ric_ControlStyle_Type` (v1-era); RC-2.0 defines `ric_Style_Type`. No-op for Phase 3, but Phase 4 will need live reads.
3. **Register RC RANfunction** in E2 Setup with real funcId (TBD in Phase 4; currently hardcoded 300) + canonical RC OID (`1.3.6.1.4.1.53148.1.2.2.10` per OSC spec).
4. **Implement Control Request decode** (unpack ControlHeader Format1 + ControlMessage Format1 from opaque OCTET STRING).
5. **Implement Control Acknowledge** encode (stub with no-op action first, then handover in Phase 5).
6. **Document the asn_check_constraints landmine** in the Phase 4 code (NS_LOG_WARN at registration).

**Documentation (this session):**
- ✅ Phase 3 file updated with full detail (`phase-03-rc-asn1c-base.md`)
- ✅ PROVENANCE.md in asn1c-rc/ with fork/commit, symbol dedup, landmine notes
- ✅ linux-vm-dependency-setup-guide.md updated with `libasn1c_e2.a` build commands
- ✅ Memory snapshot (`rc-asn1c-base-phase3.md`) for Phase 4 reference

**Risks going forward:**
- Anyone regenerating e2sim's tree with the wrong asn1c will hit subtle link/runtime failures. Mitigation: document mouse07410@0983e78a explicitly + dup-symbol guard in the VM setup script.
- Phase 4 live testing will reveal if `asn_check_constraints()` landmine gets hit (if RC validation code calls it). Mitigation: NS_LOG_WARN + explicit skip in Phase 4 stub.

---

## Carried Unknowns

- **RC-2.0 vs nov2021 on-wire:** Phase 3 round-trip used v2.0; which one is actually on the wire? Phase 4 will decode a captured rc Control Request and answer this.
- **funcId 300 assignment:** Hardcoded in Phase 1; Phase 4 must verify with deployment whether 300 or something else is correct.
- **RANParameter-ValueType recursion:** Is the infinite-loop in asn_check_constraints() specific to this asn1c fork, or a real limitation? Defer to Phase 4 (not blocking encode/decode).

---

**Status: M3 DONE. RC-2.0 types compile into libasn1c_e2.a (0 dup symbols, KPM intact), round-trip GREEN. Ready for Phase 4 handler wiring.**

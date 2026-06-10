# Phase 3 — RC-2.0 ASN.1 base (M3)

**Plan:** `260609-0127-rc-path-and-xapp-deploy-observe` · **Exit M3:** RC-2.0 E2SM types compile into libe2sim + round-trip GREEN.
**Status:** ✅ **M3 DONE (2026-06-10)** — RC-2.0 types compile into libasn1c_e2.a (0 dup symbols, KPM intact); ControlHeader-Format1 + ControlMessage-Format1 APER round-trip byte-identical.

## Goal
Add **E2SM-RC v2.0** service-model ASN.1 types to the ns-O-RAN e2sim so ns-3 can later decode/encode
RIC Control payloads (Phase 4/5). Phase 3 = ASN.1 base only: generate via asn1c, build into libe2sim,
prove encode→decode round-trip of a sample `E2SM-RC-ControlHeader/ControlMessage Format1`. **No handler
wiring, no oran-interface changes** (that's Phase 4).

## Evidence baseline (verified 2026-06-10, read-only)
- e2sim asn1c tree (`oran-e2sim/e2sim/asn1c/`) = E2AP v03.01 + KPM v03.00 only. **Outer** E2AP `RICcontrol*`
  types present; **inner** `E2SM_RC_*` types ABSENT. VM `libe2sim.a` has no `asn_DEF_E2SM_RC_ControlHeader`.
- `oran-interface/model/ric-control-message.cc` references `E2SM_RC_ControlHeader_t`,
  `asn_DEF_E2SM_RC_ControlMessage`, `controlHeader_Format1` — but is **commented out** in
  `oran-interface/CMakeLists.txt:51,64` (v1-era leftover from pre-L-release merged `e2sm-kpm-rc.asn`).
  → compiles today only because excluded. Re-enable = Phase 4.
- RC-2.0 source (VM): `O-RAN-Testbed-Automation/.../xApps/rc/e2sm/{e2sm-rc-2.0.asn,e2sm-common.asn}`
  (+ `e2sm-rc-nov2021.asn`). rc xApp already ships full asn1c output (`e2sm/lib` 298 .c, `headers` 293)
  → reference for exact generated set.
- RC-2.0: `DEFINITIONS AUTOMATIC TAGS`, `IMPORTS ... FROM E2SM-COMMON-IEs`.
  `E2SM-RC-ControlHeader-Format1 ::= { ueID UEID, ric-Style-Type, ric-ControlAction-ID, ric-ControlDecision? }`.
- asn1c on VM: `/home/uc/oaic-installation-guide/oaic/asn1c/asn1c/asn1c` (not on PATH).
- Local + VM `oran-e2sim` = same fork `origin thienandangthanh/o-ran-e2sim`, both `dev/l-release@0b9e972`, clean.

## Toolchain + integration findings (2026-06-10, validated)
- **libasn1c_e2.a is the asn-type home**, NOT libe2sim. Built manually: `cd e2sim/asn1c && gcc -O2 -fPIC -I. -c *.c && ar rcs /usr/local/lib/libasn1c_e2.a *.o` (types + asn1c runtime, self-contained). `libe2sim_shared.so` = SCTP/encoding only. ns-3 `oran-interface` links `libe2sim_shared.so` + `libasn1c_e2.a` (asn AFTER shared). Doc: `docs/linux-vm-dependency-setup-guide.md` §"asn1c type archive". ⇒ RC integration = add RC `.c` to the libasn1c_e2.a compile set + install headers. **No CMake object-lib wiring.**
- **asn1c version:** e2sim's committed tree uses the modern guarded style (`ASN_DISABLE_OER/UPER/APER_SUPPORT`) AND **prefix-and-continues** on different-OID cross-module name clashes (tree contains BOTH `E2AP-IEs_ENB-ID` and `E2SM-COMMON-IEs_ENB-ID`). VM's OAI asn1c = flat style (incompatible). **mouse07410/asn1c @ `0983e78a`** (v0.9.29) is runtime-ABI-identical (`constr_TYPE.h` + `UEID.c` body byte-identical; RC types compile clean vs e2sim runtime) — used for RC-only generation. But mouse07410 makes different-OID clashes FATAL ⇒ **cannot reproduce e2sim's full tree / no combined regen**. Build: `autoreconf -iv && ./configure && make`; run `-S <tree>/skeletons` + e2sim flags `-pdu=auto -fincludes-quoted -fcompound-names -findirect-choice -fno-include-deps -no-gen-example -no-gen-OER`.
- **Symbol-level dedup (corrected integration):** RC-only emits clash commons PLAIN (`asn_DEF_ENB_ID`); e2sim has them module-prefixed (`asn_DEF_E2SM_COMMON_IEs_ENB_ID`) — *distinct symbols*, NO duplication. Non-clashing commons (UEID, CGI, NR-CGI…) share the SAME symbol+filename ⇒ reuse e2sim's, don't re-add. **Add-set = RC-gen files whose `asn_DEF_*` ∉ e2sim's `asn1c/`.** Compiling `asn1c/*.c + asn1c-rc/*.c` with `-I asn1c -I asn1c-rc` resolves all includes (clash-plain headers live in asn1c-rc; shared in asn1c) with zero duplicate symbols.

## Collision analysis (why standalone, not combined regen)
RC-2.0 imports `E2SM-COMMON-IEs` (UEID, RAN parameter primitives). KPM's `e2sm-v03.01.asn` defines an
overlapping common set. A **single combined asn1c invocation** over E2AP+KPM+RC would **double-define**
shared types (UEID, etc.) → asn1c clobber / duplicate-symbol link errors. RC inner types only decode the
opaque OCTET STRING payload of the E2AP `RICcontrolHeader/Message` → **fully independent of E2AP types**.
⇒ Recommended: **standalone RC-2.0 asn1c module** (own subtree + object lib), reusing e2sim's existing
asn1c runtime (aper_*/ber_*/asn_*) to avoid duplicate-runtime-symbol collisions. Mirrors precedent:
`e2sm_examples/kpm_e2sm/asn1c` is already a separate subdir; the rc xApp's `e2sm/` is self-contained.

## Implementation steps (on VM, then sync to fork)
1. **Stage asn sources.** New dir `oran-e2sim/e2sim/asn1c/asn/rc/` ← copy `e2sm-rc-2.0.asn` + `e2sm-common.asn`
   from the rc xApp clone. Record provenance (commit/sha) in a README.
2. **Generate.** Run VM asn1c over `e2sm-common.asn + e2sm-rc-2.0.asn` ONLY, into a scratch dir
   (`-fcompound-names -gen-PER -no-gen-OER -no-gen-example -D <out>`). Confirm `E2SM-RC-ControlHeader.{c,h}`,
   `E2SM-RC-ControlMessage.{c,h}`, `UEID.*`, etc. produced.
3. **Isolate RC-type files.** Keep only RC/common **type** .c/.h; **drop** regenerated asn1c runtime +
   converter skeletons (aper_*, ber_*, xer_*, per_*, constr_*, asn_*, OCTET_STRING*, INTEGER*, etc. — already
   in e2sim's flat `asn1c/`). Diff against the rc xApp's `lib/` to confirm the RC-specific set.
4. **Wire build.** Place RC type files in a dedicated dir compiled as an OBJECT lib (glob *.c, like top
   `asn1c/CMakeLists.txt`), `target_link`/object-include into libe2sim. Preserve strict build order
   (libe2sim → libasn1c_e2 → header copy). Add RC headers to the `install(FILES …)` set →
   `/usr/local/include/e2sim/`.
5. **Build + install.** `cd oran-e2sim/e2sim && (cmake _bld && make -C _bld -jN)`; `sudo make install`
   (libe2sim.a/.so + headers). Verify `nm -C libe2sim.a | grep asn_DEF_E2SM_RC_ControlHeader` non-empty.
6. **Round-trip test (M3 gate).** Small standalone C/C++ prog linked against libe2sim:
   build an `E2SM-RC-ControlHeader-Format1` (+ `ControlMessage Format1`), `aper_encode` → buffer →
   `asn_decode(ATS_ALIGNED_BASIC_PER)` → assert struct equality / `xer_fprint` match. Use a real captured
   87 B Phase-0 RC payload as a second decode-only vector if shapes line up.
7. **Sync + commit.** Commit on VM `dev/l-release` (`feat(e2sim): add E2SM-RC v2.0 service-model asn.1`),
   push to `origin`, `git pull` locally. Round-trip test committed under e2sim (re-runnable harness).

## Success criteria (M3)
- [x] `e2sm-rc-2.0.asn` + `e2sm-common.asn` vendored (`asn1c-rc/asn/`); provenance in `asn1c-rc/PROVENANCE.md`.
- [x] RC types regenerated via asn1c (mouse07410@0983e78a) — no hand-edits to generated C.
- [x] libasn1c_e2.a builds clean with RC (661 .o); `asn_DEF_E2SM_RC_ControlHeader` present; KPM intact; **0 dup symbols**.
- [x] RC headers installed to `/usr/local/include/e2sim/` (570 .h).
- [x] Round-trip ControlHeader-Format1 (17B) + ControlMessage-Format1 (9B) byte-identical GREEN; re-runnable `asn1c-rc/roundtrip/run.sh`.
- [ ] Committed to fork `dev/l-release` (oran-e2sim submodule) + superproject — pending user OK.

## M3 result (2026-06-10)
- **Toolchain archaeology**: e2sim tree built by an asn1c that is modern-guarded AND prefix-and-continues on different-OID clashes. Closest runtime-ABI match = **mouse07410/asn1c@0983e78a** (constr_TYPE.h + UEID.c body byte-identical; RC compiles clean vs e2sim runtime). mouse07410 FATALs on cross-module clashes ⇒ no combined regen; used RC-only generation + symbol-level dedup instead.
- **Add-set = 168 .c/168 .h** (RC-specific + plain clash-commons). Excluded 101 shared-symbol commons (reuse e2sim's) + 122 runtime files. Build `gcc asn1c/*.c asn1c-rc/*.c` → libasn1c_e2.a, dup-symbol guard EMPTY.
- **Open landmine (Phase 4/5)**: `asn_check_constraints()` infinite-loops on RANParameter-bearing RC PDUs in this asn1c build (extensible RANParameter-ValueType CHOICE recursion). Diagnostic-only, NOT on encode/decode path. Do not call it on RC control messages. Documented in PROVENANCE.md.
- **RC version note**: on-wire 2.0-vs-nov2021 (open Q4) still not byte-confirmed; round-trip used 2.0. Settle when Phase 4 decodes a captured rc Control Request.

## Out of scope (later phases)
- Re-enabling `ric-control-message.cc` / funcId-300 dispatch / ACK → **Phase 4**.
- Forced-handover action mapping → **Phase 5**.
- RC field-name reconciliation (v1-era `ric_ControlStyle_Type` vs RC-2.0 `ric_Style_Type`) → Phase 4 (dormant reads).

## Risks
- asn1c version on VM differs from whatever generated the committed KPM tree → style churn (mitigate: RC in
  its own dir, don't regen E2AP/KPM). · Duplicate runtime symbols if runtime files not excluded (step 3). ·
  e2sm-common UEID overlap if ever combined with KPM (avoided by standalone). · Round-trip APER alignment
  (ATS_ALIGNED_BASIC_PER) must match rc xApp's encoder choice (confirm vs Phase-0 bytes).

## Open questions
- RC-2.0 vs nov2021 on-wire disambiguation still pending (Phase-0 open Q2) — Phase 3 round-trip uses 2.0; if
  captured 87 B fails to decode as 2.0, test nov2021 to settle the version (feeds plan §"RC version").

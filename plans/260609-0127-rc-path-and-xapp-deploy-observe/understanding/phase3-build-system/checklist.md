# Understanding Checklist — Phase 3 Build System: asn1c clone location & CMake automation

**Legend:** ⬜ not started · 🔄 in progress · ✅ mastered  ·  **STATUS: all items ✅ mastered (2026-06-12)**

**Builds on:** `../phase3-asn1c-version/checklist.md` (version-pinning — all ✅). That answered
*which* asn1c (mouse07410@0983e78a) and *why* (ABI twin, minimal-churn). This doc answers the
two *mechanical* follow-ups:

> **Q1: Where did we place/clone the asn1c repo from mouse07410?**
> **Q2: Can we make the asn1 compilation automated with CMake?**

Both questions reduce to one root topic: **the e2sim build topology** — where ASN.1 types
actually live, how `libasn1c_e2.a` is really produced, and what's reproducible vs ephemeral.

---

## Stage 1 — The Problem: e2sim's split build topology

- ✅ **1.1 Two separate build systems coexist in e2sim.** (a) CMake builds `libe2sim_shared.so`
  (SCTP, message routing, encoding *runtime*). (b) A MANUAL `gcc + ar` step builds
  `libasn1c_e2.a` (the ASN.1 *type descriptors*). They are NOT the same artifact and NOT built
  by the same tool. ASN.1 types do not live in libe2sim.
- ✅ **1.2 The orphaned CMake target.** `oran-e2sim/e2sim/asn1c/CMakeLists.txt:24` DOES
  `add_library(asn1_objects OBJECT *.c)` — but `asn1_objects` is referenced by NOTHING.
  `e2sim_shared` (top CMakeLists:102-104) links def/sctp/messagerouting/encoding/base only.
  So CMake compiles the asn1c `.o` files into the build tree, then never archives or installs
  them. Dead build output. The real archive comes from the manual step.
- ✅ **1.3 Why the split exists at all.** OSC ships e2sim as source+headers, no prebuilt
  ASN.1 archive. The asn1c types are generated C; the project never wired their archive into
  CMake's install. So integrators must run the `gcc + ar` step by hand. This is the "invisible
  manual build" the journal calls out.
- ✅ **1.4 What "compile" means here vs "generate".** TWO distinct asn1c-touching steps, easy to
  conflate: (a) **generate** — run the `asn1c` *binary* on `.asn` → emits `.c/.h` (needs the
  mouse07410 clone; done ONCE, output vendored). (b) **compile** — run `gcc` on those `.c` →
  `.o` → `ar` archive (needs only gcc; done every build). Q1 is about (a)'s tooling; Q2 is about
  automating (b).

## Stage 2 — Q1: Where the mouse07410 asn1c clone is (and the gap)

- ✅ **2.1 What IS recorded.** PROVENANCE.md:26 — generated OUTPUT went to `/tmp/rc-gen-m07` on
  the VM (391 .c). The invocation flags are recorded (PROVENANCE.md:22-25). The fork+commit is
  recorded (mouse07410@0983e78a).
- ✅ **2.2 What is NOT recorded (the gap).** WHERE the mouse07410 repo was cloned, built, and
  where its `asn1c` binary lives — undocumented in PROVENANCE, journal, and setup guide. Only the
  *wrong* asn1c's path is recorded (`/home/uc/.../oaic/asn1c/asn1c/asn1c`, the OAI flat-style fork
  to AVOID).
- ✅ **2.3 Why the gap (mostly) doesn't hurt — and when it does.** The generated `.c/.h` are
  VENDORED into `asn1c-rc/` (committed). So day-to-day builds (the *compile* step) never need the
  asn1c binary again. The clone only matters if we must RE-GENERATE (new RC format, fix a codegen
  bug, add another E2SM model). Then a missing/ephemeral `/tmp` clone = redo the 40-commit hunt.
- ✅ **2.4 The fix.** Document the clone+build recipe (git URL, commit, autoreconf/configure/make,
  resulting binary path) in the setup guide so re-generation is a 5-min recipe, not archaeology.

## Stage 2 — Q2: Can CMake automate the asn1 compilation?

- ✅ **2.5 Direct answer: YES, the COMPILE step (Stage 1.4b) — trivially.** The scaffolding
  already exists (`asn1_objects` OBJECT lib). Automating = (i) also glob `asn1c-rc/*.c`, (ii) add a
  STATIC target that archives the objects into `libasn1c_e2.a`, (iii) install it. No collision risk:
  compiling the already-deduped `asn1c/*.c + asn1c-rc/*.c` yields 0 duplicate symbols (proven M3).
- ✅ **2.6 What CMake CANNOT sanely automate: the GENERATE step.** Running the asn1c binary inside
  CMake would require the pinned mouse07410 toolchain present on every build host + the
  combined-regen collision trap. We deliberately do generation ONCE and vendor the output. So
  "automate asn1 compilation" = automate compile+archive, NOT regeneration.
- ✅ **2.7 Why it was done manually instead (the real reason).** NOT because CMake can't —
  minimal-churn + reversibility. Touching upstream e2sim CMake = merge friction with OSC; a
  hand-built archive keeps the RC graft isolated and trivially revertible. Trade-off: every VM
  rebuild must re-run the manual step (a documented gotcha, but a footgun).
- ✅ **2.8 The concrete CMake change (if we choose to automate).** Wire `asn1_objects` (+ a new
  `asn1c-rc` glob) into a `add_library(asn1c_e2 STATIC $<TARGET_OBJECTS:asn1_objects>)` +
  `install(TARGETS asn1c_e2 ...)`. ~10 lines. Result: `make install` produces libasn1c_e2.a, no
  manual gcc/ar.

## Stage 2.6 — Why not dedup the SOURCE (.asn) instead of the output? (user question, 2026-06-12)

- ✅ **2.9 asn1c emits the transitive closure; no external-type linking.** Feeding a `.asn` makes
  asn1c generate a `.c/.h` for EVERY type reachable from the PDUs. It has no concept of "this type
  is defined in another precompiled `.a`, just reference it." Proof in our own data: RC-only gen =
  391 files, of which 101 were shared commons (UEID, CGI…) we then *excluded* — you can only exclude
  what was generated. Deleting a shared type from the `.asn` leaves a dangling `IMPORTS` (resolves
  only within one run) → asn1c errors. **No source edit makes asn1c skip a reachable type.** Symbol-
  level OUTPUT dedup is the only seam where "already exists elsewhere" is visible.
- ✅ **2.10 Two granularities of source-trimming.** (a) COARSE = module selection (which `.asn`
  modules you feed) — ALREADY used; feeding RC-only (no E2AP module) is exactly what dodged the
  fatal ENB-ID cross-module clash (Path B needs both modules present). (b) FINE = per-type deletion
  — impossible (2.9).
- ✅ **2.11 The real lever to AVOID dedup entirely = generator clash-strategy, not the source.**
  e2sim's original asn1c PREFIX-AND-CONTINUES (ENB-ID → `E2AP_IEs_ENB_ID` / `E2SM_COMMON_IEs_ENB_ID`,
  globally unique by construction). Feed ALL modules to THAT generator in one run → no clash, no
  dups, nothing to dedup = the OSC "whole-tree regen" path. Cost = regenerate everything as a unit
  (ABI all-or-nothing). mouse07410 FATALs on the clash instead of prefixing, so it can't do the
  combined run. **Dedup-after = price of freezing e2sim's tree; whole-tree-regen-with-prefixing =
  price of avoiding dedup.** Same trade-off, opposite end.

## Stage 2.7 — Why not MERGE the .asn files into one, then generate? (user question, 2026-06-12)

- ✅ **2.12 "Merge files" ≠ "merge modules".** asn1c module boundaries = `DEFINITIONS ::= BEGIN…END`,
  NOT files (verified: every .asn is its own `DEFINITIONS AUTOMATIC TAGS ::=`). Concatenating files
  leaves both `ENB-ID`-defining modules present → mouse07410 still fatals → NO-OP. To actually remove
  the clash you must merge into ONE namespace = two `ENB-ID ::= CHOICE` in one module = ILLEGAL ASN.1
  (duplicate type), rejected before codegen. You'd hand-resolve each collision.
- ✅ **2.13 The clash is a DELIBERATE namespace collision, not accidental duplication.** ASN.1 modules
  exist so two specs can each own `ENB-ID` without agreeing on its definition. Disambiguation is the
  GENERATOR's job: e2sim's asn1c = prefix-and-continue (`E2AP_IEs_ENB_ID` / `E2SM_COMMON_IEs_ENB_ID`,
  both kept); mouse07410 = fatal. Merging the source = doing the generator's disambiguation BY HAND.
- ✅ **2.14 Evidence + the trap.** Verified E2AP's ENB-ID (`e2ap-ied-v03.01.asn:197`) and E2SM's
  (`e2sm-v03.01.asn:271`) are IDENTICAL (same CHOICE alts, SIZE constraints, ext-marker; only
  whitespace/comments differ). So merge "works" for ENB-ID — but identity is INCIDENTAL per-type.
  Across all clash types (GlobalENB-ID, NgENB-ID, GNB-DU-ID, NGENB-DU-ID…) you'd have to manually
  prove identity for each; one wrong "looks same" = silent wire corruption (collapsing two types the
  standard keeps distinct). AND merged output emits PLAIN symbols ≠ e2sim's PREFIXED tree → whole-tree
  regen anyway. Net: merge = whole-tree-regen + manual collision-resolution + silent-corruption risk =
  strictly worse than both real options (output dedup, or prefixing-generator whole-tree regen).

## Stage 3 — Broader Context

- ✅ **3.1 What automation buys.** Reproducible builds (no "forgot the manual step" → undefined
  `asn_DEF_*` at link), CI-friendliness, one-command VM rebuild. What it costs: upstream-CMake
  divergence from OSC.
- ✅ **3.2 The reproducibility ladder.** compile step (vendored .c) = fully reproducible today.
  generate step = NOT reproducible without documenting the clone (Q1 gap). Closing 2.4 makes the
  WHOLE pipeline reproducible.
- ✅ **3.3 Decision framing.** Two independent improvements: (A) document the asn1c clone recipe
  [closes Q1 gap, low effort, high value]; (B) CMake-ify the archive [closes Q2, ~10 lines, but
  upstream churn]. They're orthogonal — can do A without B.

---

## Misconceptions resolved
- ✅ "asn1 compilation = running asn1c" — FALSE. "Compile" = gcc on already-generated .c (stage 2);
  "generate" = running the asn1c binary (stage 1). Q2 automates stage 2, which never touches asn1c.
- ✅ "A pinned asn1c submodule makes regeneration reproducible" — NECESSARY, NOT SUFFICIENT. It
  pins generator+skeletons but NOT the 168-of-391 symbol-dedup, which is a hand-step needing a script.
- ✅ "CMake can't build the archive (Path A rejected = impossible)" — FALSE. CMake can; `asn1_objects`
  scaffolding already exists unwired. Rejection was Phase-3 speed, not capability.
- ✅ "Modifying e2sim CMake = upstream churn" — WEAK. oran-e2sim is our fork; editing its CMake is
  normal version-controlled work, not OSC divergence.
- ✅ "The vendored .c is the reproducible artifact, so nothing else matters" — TRUE for BUILDS, FALSE
  for REGENERATION. Build repro ✓ today; regen repro needs the Q1 fix.
- ✅ "Missing headers cause link errors" — FALSE. Headers are a COMPILE input (downstream oran-interface);
  symbols are the LINK input. Forgetting header-install breaks compile, not link.

## Actionable outcomes (orthogonal; do either independently)
- **A (reproducibility):** add `mouse07410/asn1c @0983e78a` as a submodule + commit a generate+dedup
  script (asn1c run → `nm`-diff vs ../asn1c → copy complement). Closes Q1 gap. Most directly serves the goal.
- **B (ergonomics):** wire `asn1_objects` + new `asn1_rc_objects` into `add_library(asn1c_e2 STATIC ...)`
  + `install(TARGETS)` + `install(DIRECTORY asn1c-rc/ ... *.h)`. ~12 lines. Removes the manual gcc/ar footgun.

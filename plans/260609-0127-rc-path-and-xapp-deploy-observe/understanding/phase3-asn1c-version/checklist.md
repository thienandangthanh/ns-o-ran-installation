# Understanding Checklist — asn1c Version Pinning (mouse07410 @ 0983e78a vs latest)

**Legend:** ⬜ not started · 🔄 in progress · ✅ mastered  ·  **STATUS: all items ✅ mastered (2026-06-10)**

**Core question being learned:** We pinned asn1c to `0983e78a` (2022). Latest on `vlm_master`
is `79dec883` (2026), 1108 commits newer. The OSC wiki says "update toward mouse07410/asn1c"
but pins no commit. *Are there behavior changes between the commits, and does "0983 is too old"
mean we picked wrong?*

---

## Stage 1 — The Problem (what's actually being decided, and why it existed)

- ✅ **1.1 Two rival definitions of "the right asn1c."** "Latest of the recommended fork" (OSC
  guidance) vs "the ABI-twin of e2sim's *already-committed* generated tree" (our pin). The
  framing "0983 is too old vs latest" silently assumes newer = better. For a code generator
  whose output must link against pre-existing generated code, that assumption can invert.
- ✅ **1.2 What "runtime-ABI twin" means.** asn1c output is C that references a shared runtime
  (`constr_TYPE.h`, `asn_TYPE_operation_s`, aper_*). e2sim ships that runtime *already generated*
  by some unknown asn1c. Our RC files get compiled into the SAME archive (`libasn1c_e2.a`). If
  our generator's struct layout ≠ e2sim's, the archive is internally inconsistent.
- ✅ **1.3 Why OSC pins no commit — and why that isn't a contradiction.** "Move toward
  mouse07410" is a *direction* (fork choice), not a *version*. It answers "which fork's codegen
  semantics" not "which commit must I match for THIS pre-built tree."

## Stage 2 — The Solution & how we verify the answer

- ✅ **2.1 The literal facts.** `0983e78a` = "whitespace consistency", 2022-05-02, reports as
  asn1c-0.9.29. `79dec883` = 2026-06-08. `0983e78a` IS a linear ancestor of HEAD; 1108 commits
  between. So they are on one history, not divergent forks.
- ✅ **2.2 The behavior changes ARE real and ARE ABI-level.** `git diff 0983e78a..HEAD --
  skeletons/constr_TYPE.h`: `asn_TYPE_operation_s` gained `kind` (at front), `copy_struct`,
  `jer_decoder`, `cbor_decoder`, `cbor_encoder`; `asn_encoding_constraints_s` gained
  `jer_constraints`. New fields = new struct size & offsets = ABI break.
- ✅ **2.3 Why that ABI break is fatal for a MIXED archive.** e2sim's committed runtime defines
  the *old* struct; HEAD-generated RC code would emit initializers for the *new* struct. Linked
  into one `libasn1c_e2.a`, callers index function pointers at wrong offsets → wrong codec
  called / corruption. This is the exact "compiles fine, fails at runtime" trap from Layer 2.
- ✅ **2.4 The three deterministic oracles that answer "did behavior change?"** (a) byte-diff
  `constr_TYPE.h` + `UEID.c` body = compile-time ABI match; (b) `nm | uniq -d` dup-symbol guard
  = link-time; (c) APER encode→decode→re-encode byte-identical = runtime ground truth,
  *version-independent*. The pin to 0983e78a was *derived* from oracle (a), not chosen by date.
- ✅ **2.5 Direct answer to your question.** Yes — there are behavior/ABI changes between the
  commits. That is precisely WHY we do NOT take latest: we deliberately matched the (old) asn1c
  whose output ABI equals e2sim's committed tree. "Too old" is the goal, not a defect — *for the
  minimal-churn, don't-regenerate-e2sim strategy*.

## Stage 2.5 — The CVE thread (your live concern: CVE-2025-55398 / GHSA-6v99-57j9-cq4w)

- ✅ **2.5a What the CVE actually is.** `skeletons/INTEGER_uper.c`: the **UPER** decoder fails to
  enforce an INTEGER's *upper* bound when the positive range exceeds 32 bits. Effect = an
  out-of-range value decodes "successfully" instead of being rejected. It is a *constraint
  non-enforcement* bug, NOT a buffer overflow / RCE. Affects asn1c ≤ 0.9.29.
- ✅ **2.5b Is `0983e78a` affected? YES — in that file.** Verified: its unsigned branch does
  `uvalue += lower_bound` then stores, with no `> upper_bound` rejection.
- ✅ **2.5c Why it (likely) does NOT touch us: UPER ≠ APER.** Our app decodes with
  `ATS_ALIGNED_BASIC_PER` → `INTEGER_aper.c`, a *different* skeleton. At `0983e78a` that file
  *does* enforce upper bounds (lines 190–191, 206–207). The buggy `INTEGER_decode_uper` is
  linked in (only OER is `-D`-disabled) but never *invoked* on our encode/decode path → dead
  code for us.
- ✅ **2.5d The catch-22.** "Just upgrade asn1c to get the fix" reintroduces the exact ABI break
  from 2.2/2.3. Correct minimal fix if ever needed: cherry-pick ONLY the `INTEGER_uper.c`
  skeleton fix (runtime file, ABI-neutral), not bump the whole generator. Cheapest of all:
  confirm no code path calls UPER decode + document.
- ✅ **2.5e Threat-model honesty.** Even unpatched, exploitation needs (i) a >32-bit positive
  INTEGER constraint in our RC types AND (ii) decoding *untrusted* input via UPER. Lab testbed
  RIC↔ns-3 over APER = neither holds. Residual risk ≈ 0 for current usage; non-zero only if a
  future path enables UPER on attacker-controlled data.

## Stage 3 — Broader Context (what it unblocks, what it constrains)

- ✅ **3.1 What the pin unblocks vs constrains.** Unblocks: Phase 4 RC decode/ACK against the
  existing tree with zero churn. Constrains: you cannot bump asn1c in isolation — a newer
  generator forces regenerating the WHOLE e2sim tree (E2AP+KPM+RC) consistently.
- ✅ **3.2 The OSC "right answer" vs our "minimal-churn answer."** OSC's intent = everyone
  standardizes on mouse07410 AND regenerates their whole tree with one current version. Our
  pin = keep e2sim's tree frozen, graft RC on with the matching old generator. Both valid;
  different blast radius.
- ✅ **3.3 When the pin must change.** If we ever regenerate e2sim's full tree, or adopt a model
  needing CBOR/JER/copy_struct, we move forward as a unit — and re-run all three oracles.

---

## Misconceptions resolved
- ✅ "Newer asn1c is safer" — FALSE here. Only true if you regenerate the *entire* dependent
  tree as a unit. For a graft onto e2sim's frozen tree, newer = ABI break.
- ✅ "OSC recommends a version" — it recommends a *fork/direction* (mouse07410), not a commit.
- ✅ "Matching kpimon/rc requires matching their asn1c version" — FALSE. Wire compat = `.asn` +
  PER rules (standard, version-independent). Version-match is a *link/ABI* concern, purely local.
- ✅ "The CVE file isn't in our build" — FALSE precision: it IS linked into `libasn1c_e2.a`
  (only OER `-D`-disabled), just never *called*. Dead code ≠ excluded code.
- ✅ "Can't know CVE impact without fuzzing" — FALSE. Codec dispatch + bound-checks are
  statically determinable; we read the actual branches in `INTEGER_{uper,aper}.c`.

## Residual action items (optional, not blocking)
- [ ] Add a one-line note to `asn1c-rc/PROVENANCE.md`: CVE-2025-55398 present in linked-but-
  uncalled `INTEGER_uper.c`; we decode via APER; revisit if UPER ever enabled.
- [ ] If defense-in-depth wanted later: cherry-pick the upstream `INTEGER_uper.c` bound-check
  fix only (ABI-neutral skeleton), NOT a generator bump.
- [ ] (Phase 4) When decoding the captured 87 B RC payload: confirm it decodes as APER, not UPER.

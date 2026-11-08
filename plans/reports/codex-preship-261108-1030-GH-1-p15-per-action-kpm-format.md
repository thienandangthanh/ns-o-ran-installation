# P15 per-action KPM format: Codex pre-ship audit (2026-11-08)

Codex (read-only `adversarial-review`) was run five times. Every Codex-driven fix had a follow-up review, and the final review approves.

## Round 1: Testbed, `--base 03180a5` (07f295f, 27fe123, cb69741)
- **Verdict: needs-attention, 1 finding.** Rejected for P15 and recorded as a follow-up.
- **Finding (high):** `install_xapp_kpi_monitor.sh:98-110`. With `CLEAN_INSTALL=false` and matching periods, NIST's installer restarts the existing kpimon deployment and exits. It does this before the codec lock check and before the image-label comparison, so a manual warm upgrade can keep an old image.
- **Triage: rejected for P15, as pre-existing and outside the gates' reach.**
  - The restart shortcut predates P15 and applies to every earlier kpimon patch change.
  - The harness always installs with `CLEAN_INSTALL=true` (`scripts/gates/kpimon.sh:205`).
  - `kpimon_image_labelled` (row 74) checks after every install that the running image's label equals the pinned patch-set digest, so a stale image fails the gate.
- **Follow-up:** have the shortcut restart only when the deployed image's label matches the expected patch set. This needs its own commit and its own ledger row if it is ever done.

## Round 2: harness, `--base 11c81c9c` (77dd6a16, feebff52, e1cda9b7)
**Verdict: needs-attention, 4 findings, all accepted.** Each fix has a fixture shown to fail before it.
1. **(high) Decoded sidecar reused without provenance.** Fixed in 5048d674: provenance holds the capture sha256, the decoder sha256, and the image tag and ID. The image must be ready and self-tested on every call, and a new `asn1-indep-lib-selftest.sh` runs in lint.
2. **(medium) A silent re-subscription reused earlier coverage.** Fixed in 361578f5: coverage is counted per subscription generation.
3. **(medium) The association join was not the 4-tuple.** Fixed in ace8d47f: the full SCTP 4-tuple plus birth time across `build_assocs`, `assoc_at`, both judges and p12. `pcap-to-lines.py --actions` adds `ip.dst` and `sctp.dstport`, and its default output is unchanged.
4. **(medium) A later retry masked a rejected request.** Fixed in 873af7a7: answers are matched to each request attempt.

Ledger locations: fd3dd5c2.

## Round 3: follow-up, `--base e1cda9b7`
**Verdict: needs-attention, 3 findings on the fixes, all accepted.**
1. **(high) Requests with equal timestamps shared one response.** Fixed in f3a87f85: ordering is by (time, frame, PDU index) on both bounds.
2. **(medium) A retransmitted response created a phantom generation.** Fixed in 4f606adb: a generation is the request attempt that its response answers, and a duplicate response answers none.
3. **(medium) A failed digest was swallowed.** Fixed in 00680e96: each digest is a checked assignment matching `^[0-9a-f]{64}$`, with fail closed before any cache lookup.

Ledger locations: 1084f0f2.

## Round 4: second follow-up, `--base fd3dd5c2`
**Verdict: approve.**
- The three gaps are closed.
- Codex probed these cases directly and they passed:
  - bundled requests;
  - failure then success;
  - pending retries;
  - missing requests;
  - p12 caching isolated per association;
  - both digest failures.

## Final state
Testbed `cb69741` is pushed (`dev/l-release-nist180`), and harness `1084f0f2` is pushed. The chain runs from the frozen checkout `1084f0f2`.

## Unresolved questions
- The installer's warm-restart shortcut (round 1). Fixing it later would need a new row.

# M10 P10: user ruling on the P9 forwarded RLC UM tail (PAUSE T3 resolved)

- **Date:** 2026-11-07 21:38 KST
- **Ruled by:** the user ("use the recommended decision" on `plans/261103-0008-GH-1-post-m9-realism-m10/visuals/explain-p9-um-tail-remedy.html`)
- **Pause resolved:** PAUSE T3 of 13:55 KST (journal `docs/journals/2026-11-07-m10-p10-pause-t3-p9-um-tail-remedy.md`)

## Ruling: option (a-narrow)

Fix the tail framing on the S-SN secondary-cell forward only (`forwardPdcpPdus`), in its own ns-3 commit placed right before the P9 commits.

- Forward only whole PDCP PDUs, recognised by the FULL_SDU status tag; test the tag before the D/C test, so an unsent segmented-SDU tail can no longer pass the D/C test and lose 16 bits of payload from the X2 counter.
- Register a new ledger row (next free number, 165 at this writing) and a unit case before code; run a brainstorm-checked design, then implement, review and commit.
- Row 149's P7 counts (M6 201/93, M7 3557/1819) stay unchanged.
- The X2 rows keep their 3GPP names (Option A / Q2 stands); no user-owned exception is recorded.

## Not chosen

- (a-wide): every `DeliverRlcForwardingBuffer` caller. The truncated-tail behaviour at LTE↔mmWave switch forwards stays a recorded follow-up ("RLC UM tail re-submission"), outside M10.
- (b): user-owned exception of ≤ 16 bits per forwarded tail.
- (c): `ns3.*` names.

## Also accepted

The non-blocking consensus rulings listed for review on the explainer page (counting point Q-1 at the en-gNB X2-U boundary, redirected packets counted at both cells, M4 suite row 163, judge additions Q-4 incl. A8, lint/schedule-hash/N4/golden items in `decisions-261107-1244`) stand as applied. The user did not object to them in this ruling.

## Resume order

1. Register the tail-fix ledger row and unit case; brainstorm-checked design; implement the ns-3 fix in its own commit; review (Codex + follow-up review of any Codex-driven fix).
2. Lint must report 0 findings. Commit forks: ns-3 (tail fix, then P9), oran-interface, replace the `@UNCOMMITTED` refs with SHAs, Testbed, then the harness pin.
3. Check `df` (≥ 34 GiB on /home for the kpimon rebuild), then run the P10 chain from a frozen checkout: steps 2–7, then 14, then 10.
4. Record, archive the raw evidence to /mnt/data, remove the host build tree `/home/andang/ns3-p9-910ba118`, then continue with P15.

## Design check (2026-11-07 21:55 KST, brainstormer on Opus, read-only)

- **Rule as implemented:** on the whole-PDU forward only (`removePdcpHeader == false`, which only the S-SN forward passes), a packet whose `LteRlcSduStatusTag` is present and not FULL_SDU is dropped before the D/C test; a packet with no status tag keeps the D/C test.
- **Why this is the ruling, not a change to it:** on every path our scenarios reach (RLC UM low latency; `RlcAmEnabled` is false), every buffered packet carries a status tag, so this rule and the literal "forward only FULL_SDU" behave identically. They differ only for RLC AM SDUs reassembled from unacknowledged PDUs, which carry no status tag (`Packet::AddAtEnd` keeps no packet tags) and are whole PDUs; dropping them would contradict the ruling's goal and turn the AM whole-PDU suite cases red. Verdict: implementation detail, no new user ruling.
- **Scope switch:** tied to the existing `removePdcpHeader` flag, with no new parameter, because a tail forwarded as a PDCP PDU is never valid; the SDU-path follow-up needs a different remedy (re-submission, not a drop).
- **Tests tightened per the check:** tail ≥ 3 octets, the one MAC PDU carries A's head, byte count 0 after the whole-PDU delivery. Suite green, and removing the tag test turns case (i) red (2 packets delivered instead of 1): `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/p10-um-tail/`.
- **ns-3 commit:** `1f1fa3d3` on `dev/l-release-nist180`, directly on `4318e43b`, before the P9 commits.

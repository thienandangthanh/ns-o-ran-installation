# M10, P10: PAUSE T6, the D-R3-1 chain's re-run is red at e2i (2026-11-07 00:30 KST)

## What happened

P10 opens with the D-R3-1 chain: M2–M7, I0, I2 and e2i, run at harness a7943bf (Testbed 163ef25) from a frozen checkout.

- **Attempt 1 (2026-11-05) was red at M7.** The replacement e2term never received a route table after M7 deleted its pod. Evidence:
  - no `router.txt.stash` in the pod;
  - no session on :4561 (IPVS: 0 active connections);
  - rtmgr pushing on a dead session (EPIPE).

  So every E2 Setup Request had no route. This is the L-release route-distribution hazard (the FU4 class, a new variant). It does not depend on the payload, and D-R3-1 is excluded. The one guided step was a revert plus a full re-run of the chain with no code change (kongming-261106-2200; record in phase-10, commit b3a2502).
- **Attempt 2 (2026-11-06 13:09–15:15Z):** M2, M3, M4, M5, M6, M7, I0 and I2 are green. M7 recovered normally this time.
- **e2i is red at its first check.** The asn1-indep image tarball was never copied into the VM after the revert (`cd: /home/uc/asn1-indep: No such file or directory`), and every later e2i check fails on the missing inputs.
  - The P08 procedure re-copied the tarball after every revert. P09's chain had no e2i step. The copy was never written into the driver.
  - The 2200 counsel's checklist and my launch both missed it.
  - The tarball is on the host.

## Why it pauses

The outcome rule was set before attempt 2 ran: any red step gets a kongming note, then PAUSE T6, because the Failure Protocol's one guided fix is spent. The cause is a launch omission, not D-R3-1. Following the P08 precedent ("do not reclassify"), it is still a PAUSE.

D-R3-1 is **unverified, not failed**. Row 143's predicate never ran. Two facts point the right way:
- the e2mgr X2 request parts carry 632758 (the NRARFCN) and 633312 (in the MTC), and 633333 is absent;
- M5's codec probe is byte-equal to pycrate.

Kongming note: `plans/reports/kongming-261107-0020-GH-1-p10-d-r3-1-chain-attempt-2-e2i-red.md`.

## Decisions needed from the user

1. **How to resume D-R3-1's verification.**
   - (a), recommended: copy and verify the tarball, then run e2i alone (step 8) on the current VM. About 15 min and 0–0.5 GiB, with no M7 exposure. The current state is a valid start for e2i.
   - (b): revert, copy, then the full chain 0–8. About 2 h 15 min, 25 GiB peak, plus M7's 1-in-21 route-table hazard.
   - (c): defer to P11's cp3 chain (advised against).

   The outcome rule for (a) is in phase-10, "D-R3-1 chain attempt 2". A driver pre-flight that copies and checks the tarball lands after it; it adds no check, so it needs no ledger row.
2. **Future M7 reds with the no-route-table signature** (kongming-261106-2200 Q4):
   - (i) the status quo, where each is a normal Failure Protocol red;
   - (ii) an additive receiver-side record in M7 plus one re-run outside the budget, with two in a row meaning PAUSE (kongming's recommendation).

   The same question applies to M10 at Stop B.
3. **T5.** I handled the M7 red under the Failure Protocol, not T5, by the M9 attempt-3 precedent. Say if you read T5 differently.
4. **The P6 draft's rulings R1–R4** (`plans/reports/decisions-261106-2246-GH-1-p6-draft-rulings-pending.md`), due before the P6 commit:
   - R1: a value check that misses events fails (strict; recommended);
   - R2: three renames that differ from the forecast shown at 21:37;
   - R3: a TB counter fix as a follow-up outside M10;
   - R4: unit-text corrections.

   A separate read-only advisory run, an ultra debate at 23:59 that is not mine, refined these and added a fifth question. See `plans/reports/brainstorm-261106-2359-GH-1-p6-rulings-ultra-debate.md` and `visuals/explain-p6-draft-rulings.html`.
   - Under its tighter R1, the eNB `RRC.ConnMean` also becomes `ns3.*` until a run proves its attach bound.
   - R4 is extended to three eNB "bytes" rows that carry kbit.
   - Q5 is new: how the X2 forwarding counters of P9 (row 151) meet R1. It is due before P9 code.

## State left behind

- **VM:** running and not reverted, on overlay `ubuntu24.1793970545`. e2i finished its own teardown.
- **Disk:** /home 51 GiB, /mnt/data 18 GiB.
- **Frozen checkout** `~/.cache/ns-o-ran-frozen-harness/a7943bf…`: kept, still locked. 510ae30 was removed (/home 52 → 54 GiB).
- **Evidence:**
  - attempt 2's verdict layer, plus its driver record in `evidence/p10-chain/a7943bf/attempt-2/`;
  - raw archives `…-m10-p10a-20261106` (attempt 1 plus the M7 diagnosis) and `…-m10-p10b-20261107` (attempt 2) on /mnt/data, SHA256SUMS verified.
- **Uncommitted drafts** (no gate has run on them):
  - **The neighbour-loop UB fix (Amendment 4, row 159).**
    - In the ns-3 submodule: `mmwave-neighbour-selection.{h,cc}`, the `mmwave-enb-net-device.cc` loop, and the `mmwave-neighbour-list` suite (14 cases, checked standalone).
    - In the harness: `build-ns3.sh --tests`, the M4 suite check, and `check-ipc-neighbour-lists.py` wired into `ts-rung-lib.sh` and `lint.sh`.
  - **The P6 registry, strict lint and in-place renames** (Testbed submodule, `kpimon.sh`, `kpimon-guard-selftest.sh` and `lint.sh`).

  Both wait for D-R3-1 to be verified, in the commit order.

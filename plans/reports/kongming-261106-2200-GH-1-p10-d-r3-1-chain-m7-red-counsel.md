# kongming: P10 step 0 (D-R3-1) chain red at M7, Failure Protocol counsel

Date: 2026-11-06 ~22:00 KST. Caller: the P10 controller. Model: Opus 5.5 (kongming). Advisory only. No repo edits except this report.
Scope: M7 at harness a7943bf, TESTBED 163ef25, evidence `evidence/m7/20261105T211444Z`, chain tsv `evidence/p10-chain/a7943bf/`.

## TL;DR
- The red comes from the RIC platform, not from D-R3-1. The replacement e2term pod has **never received a single route table**, in more than 15 h. It runs on its seed `router.txt`, which routes 1080 and 1100 but not 12001 or 1102. rtmgr's push session to the e2term Service died with the old pod and was never reopened. This is the documented "rtmgr never reconnects to a replaced pod" behaviour (`scripts/gates/bringup.sh:207-208`), which is out of scope by contract §3.
- Next step: **(a), as the one guided step.** Record the root cause, pull and archive the live evidence, revert `f7-rerun-green`, then re-run the **full** D-R3-1 chain (steps 0–8, M2→e2i) at the unchanged frozen a7943bf. Any red in that run means PAUSE T6.
- Do not put any remedy into M7. Do not run M7 alone on the current VM.
- One user question is worth raising now. It does not block the re-run: a pre-registered re-run rule for this exact signature. About 10 more M7 runs lie ahead, and the hazard is likely to come back.

## Evidence I pulled (read-only, VM, 2026-11-06 12:50–12:55Z; no state changed)
All [V]. Re-capture it formally into `m7-diagnosis/` (commands in the checklist): this report is not the evidence record.

1. **e2term `deployment-ricplt-e2term-alpha-88fd95787-cz7j8`:**
   - `/opt/e2/` holds `router.txt` (the configmap seed, 21:30:52) and `router.txt.stash.inc` (0 B, 21:30:52.847, created at RMR init). There is **no `router.txt.stash`**.
   - The env has `RMR_SEED_RT=router.txt` and `RMR_RTG_SVC=4561`.
2. **Control: RMR writes the stash on every table it receives.**
   - e2mgr's `router.txt.stash` mtime is 2026-11-06 12:53:19, two seconds after rtmgr's push cycle.
   - rtmgr logged that very push to e2mgr as "Updating Routes … e2mgr … **failed**, call_id: 197".
   - So the e2term never received a table at all.
3. **The seed `router.txt` matches the routed set exactly:**
   - 1080 and 1100 go to e2mgr: E2_TERM_INIT ×3 and the lost-connection messages were delivered.
   - The seed has no 12001 and no 1102. That gives `RMR_ERR_NOENDPT` for every E2 Setup Request and "Failed to send E2_TERM_KEEP_ALIVE_RESP" at 21:34:44.
   - Your inference that e2term runs on the seed table only is now verified.
4. **e2term `/proc/net/tcp{,6}`:**
   - :4561 is LISTEN with **no ESTABLISHED session**. This is not FU4's stuck reader (a session with rx_queue stuck); there is no session at all.
   - :38000 has one session, from e2mgr 10.244.0.155.
5. **rtmgr `/proc/net/tcp{,6}`:**
   - It has outgoing :4561 sessions to hw-go (10.111.79.228), kpimon (10.104.47.161), e2mgr (10.102.21.132), submgr (10.244.0.156) and a1mediator (10.106.37.221).
   - It has **none to the e2term Service 10.101.123.229**.
6. **rtmgr now:**
   - Every push to `service-ricplt-e2term-rmr-alpha.ricplt:38000` fails with `tp=32` (EPIPE).
   - The "Route Update Status" echoes the table back (`newrt|st…`): the send itself failed on a dead session. It is retried 3× per cycle and never reopened.
   - Other endpoints log "failed" with an **empty** status. That means no ack, not no delivery (point 2). Your point 5 is mostly noise; the e2term lines are a different signature.
7. **rtmgr window log (21:30–21:42Z):**
   - The last "successful" push to `10.101.123.229:38000` was at 21:31:21.6. The old pod's delete returned at 21:31:23.
   - The first `tp=110` (ETIMEDOUT) came at 21:32:26, then `tp=32` from 21:32:28.
   - The "successful" lines to the service endpoint at 21:32:27–21:36:47 cannot have reached the new pod (it has no stash). FU4's "successful is not proof" holds again.
8. **Other platform facts:** kube-proxy runs in **ipvs** mode. The e2term Service endpoints are now 10.244.0.161 (cz7j8). e2mgr 0.2.2 handled E2_TERM_INIT as the same ACTIVE instance (21:30:53: 5 RANs dissociated; 21:32:33 and 21:34:13: 0 RANs, POST /handles/e2t). rtmgr therefore kept its existing endpoint object and never opened a fresh session.
9. **Unexplained, record only:** five sessions into rtmgr :4560 (from e2mgr, submgr, kpimon and two more pods) each hold tx_queue 0x1B220 (111,136 B) that the peers do not read. There is no green-run baseline, and the cause is out of scope.

## Q1. Is the diagnosis sound, and is it D-R3-1?
**Sound, with three sharpenings.**
1. "e2term's table lacks 12001": no rtmgr table was ever applied (points 1–3).
2. "Every rtmgr table contains 12001": true, but none was delivered.
3. This is not the FU4 stuck-reader variant. There is no session at all to the replaced endpoint.

**D-R3-1 is excluded (high confidence):**
- The M7 code path is byte-identical from 673fe7b to a7943bf: `gate-m7-multignb.sh`, `bringup.sh`, `rc-lib.sh` and `tools/` show no diff. `lib.sh` only moved the verdict writer into `write-verdict.py` [V].
- Testbed 554d6d61→163ef25 touches only `ns3_e2_agent` identity constants, the codec probe, `SOURCES.txt` and `x2ap-codec.h` [V].
- The failure happens at RMR message-type routing inside e2term, before e2mgr parses anything. A route table either reaches e2term or it does not, whatever the E2 payload says.
- Pre-delete setups at the same SHA succeeded on all 5 nodes [V].

**Frequency.** This is 1 of 20 M7 runs on record, and 1 of 5 since M2's e2mgr-image refresh became routine on 2026-11-04 (the other two red M7 runs on record had answered setups). In every green run the first post-delete setup also went unanswered, with a response 20–100 s later. So the replacement e2term always starts on the seed table, and rtmgr usually reaches it within one or two push cycles (~62 s period) [I]. Why the reopen happens in green runs is unknown. One speculative hypothesis is how the old session dies under IPVS: a FIN seen by RMR versus a silent drop followed by ETIMEDOUT/EPIPE on send. Do not chase it (contract §3).

**Extra evidence to pull before the revert:** the items in the checklist below. It does **not** change the next step. It strengthens "environmental, payload-independent", and it rules out an M7-only re-run on this VM: e2term has no routes, rtmgr's session is dead, and the E2T instance was deleted at 21:40:44.

## Q2. Next step under the Failure Protocol
**Recommend (a): one guided re-run with a clean environment and unchanged code.** It is not a blind retry:
- the root cause is recorded with receiver-side evidence;
- the change under test is excluded;
- the guidance is explicit;
- the outcome rule is set before the run.

**Scope.** Revert `f7-rerun-green`, then `p10-gate-chain.sh a7943bfb… 0 8` (M2, M3, M4, M5, M6, M7, I0, I2, e2i). M7 needs the state built by M2–M6, and no snapshot exists at M6, so the minimum is the full chain.

**Outcome rules (write them down before launch):**
- Any red step (M7 or another) → a kongming note → PAUSE T6. The budget is spent.
- A green chain → mark D-R3-1 fixed at both SHAs (step 0 "Then"), archive, and continue to the docs commit (resume step 3).

**Cost:**
- About 2.5 h of wall time: M2–M7 took 110 min in attempt 1, and I0 + I2 + e2i take about 15–25 min.
- About 24–26 GiB of /home growth, the P09 prefix figure plus e2i.
- Budget: /home is 52 GiB now. Removing the 510ae30 checkout gives back ~3 GiB. Deleting the leaked overlay `ubuntu24.1793907376` (23 GiB) after the revert, under the 2026-10-28 ruling, gives ~75–78 GiB before the run and ~50–52 GiB after it. That is above the 34 GiB build line for the rest of P10.
- /mnt/data: 18 GiB free; the raw archive is about 0.1–0.2 GiB.

**Why not (b):**
- Any remedy inside M7 changes what M7 proves, from unassisted recovery to assisted recovery. Examples are `ric_restart_rtmgr` or `ric_refresh_routes` after the delete, or extending `rt_reader_ok` to the replacement e2term with a refresh. That needs an AC18 row and a user ruling.
- A diagnostic-only addition is legitimate, but a harness commit now moves the chain SHA and needs lint and review. It also buys little, because the chain stops at the first red and leaves the VM up for post-hoc pulls (as today).
- Schedule the diagnostic as an additive informational record after the chain (Q4).

**Why not (c):** nothing here needs a user decision before the re-run. The guidance does not change the locked outcome. T5 ("an L-release failure") was considered. The precedent is M9 attempt 3, a known L-release route hazard that went through the Failure Protocol (F″) first, with T5 only if the remedy failed. Say so in the record; the user may read T5 differently.

**Record before the re-run** (one docs commit, pushed; no code):
1. `m7-diagnosis/`: the re-captured pulls plus a short provenance note (commands, UTC times, read-only).
2. `phase-10-…md`: a "D-R3-1 chain attempt 1" block with:
   - the red checks;
   - the [V]/[I] root cause;
   - the classification (L-release route distribution to a replaced pod, payload-independent, out of scope);
   - the guided step;
   - budget spent, second red = T6;
   - T5 considered and why not invoked;
   - the extra revert cycle (it updates the revert plan in the pending docs commit).
3. FU4 findings: a dated addendum covering the variant "no route-table session to a replaced endpoint", the stash test as receiver-side evidence, the two push-log signatures (empty status means no ack; echoed table with `tp=32` means a dead session), and the 1/20 rate.
4. The check-diff ledger: **no row**. No predicate changes, and AC18 needs a row only for a change. You may add one line noting M7 is unchanged.
5. The resume card (VM op > 10 min), `implementation-notes.html`, the attempt-1 verdict layer per the `plans/.gitignore` allowlist, and the raw archive (e.g. `…-m10-p10a-20261106.tar.zst` + `.list0`) on /mnt/data.
6. The chain driver: `here=` hard-codes the previous session's scratchpad (`p10-gate-chain.sh:19`), so the tsv appends (`>>`) and the step logs overwrite. Point it at a fresh directory before launch, commit that, and save the outputs to `evidence/p10-chain/a7943bf/attempt-2/`.

## Q3. The frozen checkouts
- **Keep a7943bf** for the re-run: same SHA, already frozen. The driver checks that HEAD equals the SHA and the tree is clean before every step. Also confirm `scripts/` is still read-only. Remove it once attempt 2's evidence is committed and archived.
- **Remove 510ae30 now.** P09 is done, its gate of record is committed, and archives p09a/p09b are on /mnt/data. Use `git worktree unlock` then `git worktree remove` (after restoring write permission on that path), never `rm -rf`, and log the ~3 GiB freed (du shows 3G each).

## Q4. Decisions for the user
- **Nothing blocks the re-run.**
- **Raise now (non-blocking; T3-class process ruling): how to handle future M7 reds with this exact signature.** About 8–11 M7 runs remain: P7, P9, P15, D-06b-1, the kpimon tag and UseIdealRrc regressions, the cp3 chain, rehearsals and M10. At a 5–20 % rate, P(≥ 1 more) is about 40–90 %. Once the budget is spent, each occurrence means T6 and a user round trip. Options:
  - (i) **Status quo** (the default if no answer): each occurrence is a normal Failure Protocol red.
  - (ii) **Pre-registered signature re-run.** M7 gains an additive, informational, receiver-side record taken after recovery: e2term `router.txt.stash` present and its mtime, e2term :4561 sessions, rtmgr sessions to the e2term Service, and NOENDPT 12001 lines. An M7 red whose record matches the signature gets one re-run from the step's start state, outside the guided-fix budget; two in a row means PAUSE. This needs its own ledger row (additive) and lands after this chain. **My recommendation.**
  - (iii) **A remedy inside M7.** Weakens M7 and hides a defect a production RIC would also hit. Advise against.
  - (iv) **Fix rtmgr/RMR reconnect.** A scope change (contract §3).
- **For M10 (AC19, one unattended run, exit 0)** the same hazard is an end-run risk. Put it on the Stop B list as a decision on the rerun policy or (ii)'s record.

## What to avoid
- A rtmgr restart or route refresh in M7 after the delete. A wider recovery window: the e2term went 15 h without a table, so it would not help, and it weakens the check.
- An M7-only run on the current VM, or after a manual RIC repair. That is an improvised environment change and breaks provenance.
- Reading rtmgr's "successful" or "failed" lines as evidence of delivery in either direction. Use the receiver's stash and sessions.
- Reverting before the live evidence is pulled and archived. Editing the driver or harness while the chain runs.
- Leaving the empty `evidence/m7/.claude/agent-memory/` directory: it was created by this agent's spawn CWD. Remove it before archiving or committing. I wrote nothing there.

## Work checklist
1. Re-capture read-only into `evidence/m7/20261105T211444Z/m7-diagnosis/`:
   - e2term: `ls -la --time-style=full-iso /opt/e2/`, `cat /opt/e2/router.txt`, `env | grep ^RMR_`, `cat /proc/net/tcp /proc/net/tcp6`;
   - e2mgr: `ls -la --time-style=full-iso` of its `router.txt*` (the control);
   - rtmgr: `/proc/net/tcp{,6}` and `kubectl logs --since=10m`;
   - `kubectl -n ricplt get svc,endpoints -o wide` and the kube-proxy mode;
   - optional: `sudo ipvsadm -Ln -t 10.101.123.229:4561`, and the kubelet journal for the kill time of pod `…-kvfhz`.
2. Write the records in Q2 (1–6), commit and push (docs only).
3. Archive the attempt-1 raw evidence to /mnt/data and verify the sha256 list.
4. Remove the 510ae30 checkout and log the space freed.
5. Shut down the VM, revert `f7-rerun-green`, then delete the leaked overlay with the 5 checks; log `df -BG /home /mnt/data`.
6. Update the resume card, then launch `p10-gate-chain.sh a7943bf… 0 8` with the new `here`.
7. Green: D-R3-1 is fixed at both SHAs; archive; remove the a7943bf checkout; ask the Q4 question if it is not yet ruled. Red: kongming note → PAUSE T6.

## Success metrics
- Attempt 2: all 9 steps exit 0 and pass the run-dir cross-check.
- M7 post-delete: every node has a setup response, a subscription and a first indication within the window.
- /home ≥ 34 GiB after the chain.
- The record shows [V] versus [I] and the T5/T6 reasoning.

## Assumptions
- The e2term seed configmap is identical across runs, so every green recovery needed an rtmgr push. High confidence; it would change only if the configmap varied between snapshots.
- The re-issued goal reset the one-fix budget (ruling 2026-10-26), and this is the first failed Verify since then. High confidence; if the budget were already spent, this is PAUSE T6 now.
- The leaked-overlay deletion after the revert falls under the 2026-10-28 ruling. High confidence.
- The hazard rate is 5–20 % per M7 run. Low confidence (n = 20 and n = 5).
- "M5–M7 after every agent change" makes M7 part of D-R3-1's Verify (P09 hand-off overrides step 0's "covered by cp3"). High confidence.

## Unresolved questions
1. The user: (i) or (ii) for future same-signature M7 reds, and the same question for M10 at Stop B.
2. The user: whether T5 should have been invoked instead of the Failure Protocol for a known L-release hazard. The precedent says no.
3. Why green runs do get a reopened rtmgr session. Out of scope; (ii)'s record would answer it as a side effect.

Status: DONE_WITH_CONCERNS
Summary: The M7 red is a verified RIC route-distribution failure: the replacement e2term got no route table and rtmgr's push session is dead. It is independent of D-R3-1. One guided full-chain re-run at a7943bf from `f7-rerun-green` is the right step, and a second red means PAUSE T6.
Concerns: The hazard will probably recur in about 10 future M7 runs, M10 included, so raise the user ruling (ii) early. Clean up the stray empty `evidence/m7/.claude/` directory before archiving.

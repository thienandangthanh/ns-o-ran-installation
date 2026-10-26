# kongming: P5 gate i2 --part stub red on rc's rotated start-up line (2026-10-26)

This is advice only and is not user approval. Model: Opus 5.5, per the user's CLAUDE.md. The VM was used read-only: `kubectl get` and `kubectl logs`, `sudo` reads under `/var/log/pods`, and a read of the kubelet config. Nothing was changed.

## TL;DR
- **Diagnosis:** confirmed. kubelet rotated the kept rc pod's log on 2026-10-26 at 07:22:01 UTC, and `kubectl logs` reads only `0.log`. rc writes one INFO line for every kubelet probe (about 149 KB/h), so its start-up line disappears about 70 h after any rc pod starts. This is not an L-release failure.
- **The 8c88b7a fix worked.** `ts_ready` passed, and so did `i2_a1_threshold_reaches_ts_xapp` (attempts 2 and 1, stale line ignored).
- **Q1: print `PAUSE T6` now and do not patch in this session.** The plan text, read the way the 2026-10-24 journal already read it, says so. My earlier no-go trigger says the same, and the user released with that trigger written in the journal.
- **Q2: the fix for the user's release is option (a).** Each gate on the goal path starts from a pod it created itself (`rc_ric_reset` before the first rc check). Strengthen the "after rtmgr restart" check with rtmgr's per-endpoint push acknowledgement. Reject (b) and (c). No option changes the locked outcome.
- **Q3:** in the r2 path, apply the same rule to the TS xApp at r2's top. Every other pod is already safe or is never read.
- **Q4:** NO-GO in this session. GO on the user's release: fix, then lint, then i2 `--part stub` fresh, then r2 `--mode calibrate`.

## 1. Verified facts

### VM, 2026-10-26 13:06–13:13 UTC
1. **VM state.** Boot time is 2026-10-23 07:57 UTC (`uptime`: 3 d 5:09). `virsh` shows running, snapshot-current `r0-green`, and host `/home` has 49 G free. All three match the resume card.
2. **The rc log files.** rc pod `jbcb4` was created on 2026-10-23 at 08:58:59. Its directory holds two files:
   - `0.log.20261026-072201`: 10,485,893 B, from 2026-10-23 08:58:59 to 2026-10-26 07:22:01 (70 h 23 min, about 149 KB/h);
   - `0.log`: 856,984 B over 5.74 h, the same rate.
3. **The start-up line is only in the rotated file.** `RMR is ready` appears in the rotated file at lines 36 and 43 (08:59:30–32). `0.log` does not have it.
4. **kubelet runs with the defaults.** `/var/lib/kubelet/config.yaml` has no `containerLog*` keys, so the limits are 10 MiB and 5 files, and older files are gzipped. kpimon's directory already shows `.gz` files.
5. **What rc logs.** In the rotated file:
   - 33,784 of its 40,617 lines are `restapi: method=GET url=/ric/v1/health/ready|alive`;
   - the rest is mostly RMR `sends:` statistics, 8 lines every 301 s.
   - During the i2 window (12:57–13:03 UTC), rc logged nothing except those statistics. So on a kept pod, rc's own log cannot show anything about an rtmgr restart.
6. **What rtmgr logs** (fresh pod, started 13:00:05 UTC):
   - `Update Routes to Endpoint: service-ricxapp-rc-rmr.ricxapp:4560 successful, call_id: …` first appears at 13:00:16.863;
   - it then recurs 18 times in 12 min.
   - In rtmgr's `sendDynamicRoutes` (`pkg/sbi/nngpush.go`, GitHub master), that line is written unless `SendCallMsg` failed and the reply does not start with `OK`. So the line means rc's RMR answered the route-table call from this rtmgr.
   - rtmgr also logged `Updating Routes … failed, call_id: 1` once each for hw-go and a1mediator; later pushes succeeded.
7. **Log growth of the other pods:**

   | Pod | Rate | Rotation |
   |---|---|---|
   | TS xApp `2hx5c` | 1,561,089 B in about 58 h, about 27 KB/h | none yet |
   | kpimon | about 570 KB/h idle | 4 in 3 days |
   | hw-go | about 12 MB in 3 days | 1 |
   | rtmgr | about 4 MB/h (DEBUG) | about every 2.6 h |
   | stub | 17 KB | none |

### Code
1. `rc_at_pin` (`rc-lib.sh:101-103`) calls `rc_ready` (`:73-83`), which calls `rc_rmr_ready` (`:87-99`). That reads the current container's `kubectl logs` only.
2. `rc_at_pin` is the first rc check at these sites, always on the pod the previous gate left: `gate-i2-ts-xapp-install.sh:40`, `gate-r0-rc-scripted.sh:87`, `gate-r1-rc-multi-control.sh:86`, `gate-r2-ts-stub-qp.sh:104`, and `gate-q8-rc-smoke.sh:43` (q8 is not on the M9 chain, `run-to-m9.sh:52-66`).
3. **The "after rtmgr restart" checks never proved what their name says.**
   - `i2:67`: on a kept pod it re-finds a 3-day-old line.
   - `r2:183`: it re-finds the line written after the first per-run rtmgr restart (`rc_ric_reset`, `rc-lib.sh:203-204`), not after the second one (`ts_stub_pods_reset`, `ts-lib.sh:281`).
   - The real post-restart evidence today is the rtmgr→rc session check: `RTMGR_PEERS` (`ts-lib.sh:66`) and i2's `SVCS` (`i2:41`) both include `service-ricxapp-rc-rmr`. In r2 there is also rc's RICcontrolRequest on the wire.
4. `ts_at_pin` at r2's top (`r2:105-107`) runs `ts_ready` (`ts-lib.sh:152`), which reads the one-time line `listening on port 4560` from the kept TS xApp pod. That is the same class of hazard.
5. `pod-log-window.py` already reads across rotation for kpimon (`agents-ns3-run.sh:171-181`). But its fail-closed rule (`pod-log-window.py:105-108`) needs a record older than `--since`, so it cannot read "from container start" without a new mode.
6. A per-run `rc_ric_reset` took about 44 s (R1 `live1`: 08:50:52 → PASS 08:51:36).

## 2. Q1: pause or fix?
**Print `PAUSE T6 evidence=plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/i2/20261026T125704Z journal=docs/journals/2026-10-26-m8-m9-p5-pause-t6-rc-log-rotation.md`** after the usual pause steps.

The plan text governs. My trigger is only counsel, but here the two agree:
1. **The literal Failure Protocol.** The phase-05 Failure Protocol says: "Apply kongming's guidance, then re-run the Verify step. If it fails again … PAUSE T6."
   - 8c88b7a *is* kongming's guidance (kongming-261024-1255 §3), and run 125704Z is its re-run, which failed.
   - The 2026-10-24 journal (line 13) already applied this reading ("I print T6 rather than fix again because the protocol says so literally"). That included the point that a different root cause does not reset the count.
2. **A release is not a new budget.** Neither plan.md nor the phase file says that a release resets the budget.
   - The resume card's own next action defined the run after the release as the re-run of the fix: "apply journal section 3 fix …; i2 --part stub fresh".
   - Your reading ("first failed Verify after the release") is defensible, but the records do not support it.
3. **The user released knowing the trigger.** Journal line 37 carries my trigger: "a third harness red in this segment that is not an L-release cause means stop and re-scope, not another patch." This red is the third one (after 84c2a33 and fa1bf1e), and it is not an L-release cause.

**The id is T6.** It is not T3, because the acceptance signal is still reachable as written. It is not T5, because kubelet rotation of a chatty xApp's log is k8s behaviour that meets a harness assumption, not an L-release defect. It is not T4: no standard is involved.

**What "re-scope" means here** (so the user can rule on it at release):
- Adopt one harness rule: *a gate reads a pod's one-time start-up line only from a pod that the gate itself created; for a kept pod, liveness is proven by fresh evidence (an rtmgr acknowledgement, a session, or wire bytes)*.
- Section 4 is the class audit behind the rule. Section 3 implements the rule at every gate on the goal path.
- Ask the user for a standing ruling on whether a release resets the one-fix budget, so this is not argued again at the next pause.

**Do not apply code before the pause.** The precedent of 2026-10-24 was to put the fix in the journal and apply it after the release.

## 3. Q2: the fix, for the user's release

### Recommended: (a) start from a pod the gate created
1. **i2.** Before `i2:40`, add `check i2_pre_ric_reset_fresh_rc_kpimon_hw_go_and_bucket rc_ric_reset pre`.
   - `rc_ric_reset` is the tested function: about 44 s, used 8+ times in R0/R1.
   - Its `check-ric-reset.py` proves that rc, kpimon and hw-go are new and the bucket is new.
   - `rc_at_pin` at `:40` then runs on a pod from this gate.
   - The label `pre` writes `pre-reset*`, which does not collide with `i2-a1mediator-restart*`.
2. **r0 and r1.** Add the same line before `r0:87` and `r1:86`. These lines first run in P6 (one live run each) and in M9.
3. **r2.** Before `r2:104`, add `rc_ric_reset pre`, then `ts_stub_pods_reset pre` (section 4). Both are the same functions the per-run loop calls seconds later, so they add no new failure mode.
4. **Strengthen the post-restart check, keeping its name.**
   - At `i2:67` and `r2:183`, run `rc_rmr_ready && rtmgr_push_acked service-ricxapp-rc-rmr`.
   - `rtmgr_push_acked` is a new helper in `rc-lib.sh`. It takes the running rtmgr pod and polls for at most 90 s with `grep -F -m 1 "Update Routes to Endpoint: $1.ricxapp:4560 successful" < <(kc -n ricplt logs "$pod")`.
   - Use process substitution: the lint rule forbids `logs | grep -m`.
   - The rtmgr pod was created by this gate, so any such line comes after the restart by construction. The line recurs, so rtmgr's 2.6 h rotation does not matter.
   - This step is separable. If the user wants the smallest diff, drop it and record in `implementation-notes.html` that the check proves "this gate's rc container is RMR-ready", while the session check carries the post-restart claim.
5. **`rc-lib.sh` header (`:20-21`).** State the rule and the reason: rc logs every probe, its log rotates in about 70 h, and `kubectl logs` reads only the newest file.
6. **Commit.** Example: `fix(gates): start each rc gate from a pod it created so rc's start-up line is never rotated away`. Keep plan ids, phase numbers and kongming out of the message and the comments.

**Is the outcome changed?** No.
- Contract In scope 7 already requires a per-run reset of rc. One more reset before the first check is a precondition.
- Every existing check stays with its name; the only additions are new pre-reset checks and the rtmgr acknowledgement.
- C1 compares ledgers, IPC, traces, RC multisets and KPM headers, none of which change.
- M9 costs about 1–3 min more per gate, inside `run-to-m9.sh:60-66` (i2 3600 s, r0/r1/r2 5400 s).

**Is it a weakening?** No.
- A pass now means "rc at the pin reached RMR-ready under this gate's rtmgr", and the rtmgr acknowledgement adds evidence that can actually fail.
- It removes a false red and adds no false green.
- It does mask a broken *kept* rc pod, but the contract never tests kept-pod longevity: RestartCount = 0 is per run, on fresh pods.

### Rejected options
- **(b) Read the start-up line from rotated files under `/var/log/pods`.**
  - It keeps a stale check alive: a 3-day-old line says nothing about now.
  - It needs a new "from container start" mode in `pod-log-window.py`, because the current rule exits 3 for that kind of read.
  - It has to handle `.gz` files.
  - It goes red anyway once kubelet deletes the oldest file, after about 5 rotations (about 15 days for rc).
  - In short, it is more code for weaker evidence.
- **(c) `kubectl logs --previous`.** It does not apply: rc has not restarted.

## 4. Q3: other kept-pod aging hazards (class audit)

| Pod | Kept into a gate? | What the gate reads | Horizon | Action |
|---|---|---|---|---|
| rc | yes: the top of i2, r0, r1, r2 (and q8) | one-time `RMR is ready after` | about 70 h | **fix now** (section 3) |
| TS xApp | yes: i2 `--part stub` (`ts_ready`) and r2's top (`ts_at_pin` → `ts_ready`); fresh per run inside r2 | one-time `listening on port 4560`; `ts_policy_set` uses this call's own marker, so it is safe | pod `2hx5c` about 2026-11-09 at 27 KB/h (about 11-15 idle); every r2 run renews the pod | **r2 top: fix now** with `ts_stub_pods_reset pre`. **i2 `--part stub`: leave it**, because it keeps the TS xApp by design and M9 runs `--part all` with a fresh install. Write the horizon on the resume card: a resume with a kept TS xApp pod older than about 10 days runs i2 `--part all` first. |
| stub QP | no: reinstalled by i2 and fresh per run | its own fresh log 8 s after Ready; table and log over HTTP | none | none |
| kpimon | no: fresh per run | window since `cap_t0` through `pod-log-window.py` (rotation-aware, fail closed) | about 2 MB per R1 run against 10 MiB | none. Watch R3 (UL on, longer runs): a rotation shows up as exit 3, never as a false green. |
| hw-go | no: fresh per run | nothing (RestartCount only) | — | none |
| rtmgr, a1mediator | restarted per gate and per run | `/proc/net/tcp`; the rtmgr acknowledgement if adopted, read within 90 s | rtmgr about 2.6 h | never read rtmgr's log long after its restart |
| e2term, e2mgr | kept | the stash file through `exec`; the REST API | — | none |

Note for P8: gate r3 must follow the same rule at its top.

## 5. Q4: go/no-go
- **Now:** NO-GO. Write the journal (facts in section 1, the T6 reasoning, section 3 as "Proposed fix, for the user's release", the section 4 table, and the questions below). Update the resume card and `implementation-notes.html`, push, and print the PAUSE line.
- **On the user's release:** GO, under these conditions:
  1. The resume checks still match. The boot time stays 2026-10-23 07:57 UTC; a different one means gate i0 first.
  2. `lint.sh` is ok, and `bash -n` passes on the touched scripts.
  3. i2 `--part stub` runs fresh at the fix commit and every check is green. In particular:
     - `pre-reset.json` shows `fresh: true`;
     - the rc pod is not `jbcb4`;
     - the RMR-ready line is visible;
     - the rtmgr acknowledgement is found for rc;
     - `a1ThresholdAttempt=2` and `a1DeliveredAttempt=1` again;
     - restart counts are 0.
  4. Then r2 `--mode calibrate`. It is r2's first run, so its own Failure Protocol budget applies.
- **No-go triggers after the release:**
  - any red in i2 → T6, with no further patching;
  - a red in a new pre-reset check → T6, because the remedy itself is wrong.

## What to avoid
- **Deleting the rc pod by hand and re-running i2 unchanged.** That makes the gate green on hand-made state, the next aged gate fails again, and it is an unscripted VM change.
- **Raising `containerLogMaxSize` on the VM.** It hides the hazard on the dev VM, M9's `fresh-install` would differ, and it changes k8s configuration outside scope.
- **Dropping `rc_rmr_ready` from `rc_at_pin`, deleting the post-restart check, or renaming checks.** The first two narrow a test. Renaming churns the verdict for no gain; only the gate scripts reference these names.
- **`kubectl logs --since-time` for the start-up line.** It still reads only `0.log`.
- **Classifying this as T5 or as an L finding.**

## Assumptions
- **The rc log rate is stable at about 149 KB/h, driven by the probe period** (high). Two independent windows give the same rate.
- **rtmgr 0.9.6's `successful` means the xApp's RMR answered** (medium-high). This is read from GitHub master; the deployed strings match. If the user doubts it, keep only the session check and document it.
- **The TS xApp grows at 27 KB/h** (medium). It depends on traffic, so the horizon may move by days.
- **A release does not reset the one-fix budget** (medium; this is a reading, not plan text). If the user rules that it does, apply section 3 directly, and the next i2 red is T6.

## Unresolved questions (for the user, in the journal)
1. Does a release reset the Failure Protocol's one-fix budget? A standing ruling is requested.
2. Do you approve the rule "a start-up line only from a pod the gate created", including edits to the scripts of the green rungs r0 and r1? Their first run would be in P6.
3. Should the rtmgr push acknowledgement be added to the `*_rc_rmr_ready_after_rtmgr_restart` checks, or should the smaller diff be taken?

Status: DONE
Summary: Cause confirmed: kubelet rotated the kept rc pod's log about 70 h after start because rc logs every probe; this is not an L-release cause, and the T6 fix itself worked. Print PAUSE T6 now; on the user's release, start each gate on the goal path from pods it created (`rc_ric_reset pre`, plus `ts_stub_pods_reset pre` at r2's top), add rtmgr's push acknowledgement as the post-restart evidence, then run i2 `--part stub` fresh and r2 calibrate.

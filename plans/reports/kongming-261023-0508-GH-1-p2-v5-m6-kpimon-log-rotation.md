# kongming: P2 (S1), first failed V5. M6 kpimon log count lost lines to a kubelet log rotation

Date: 2026-10-23, about 06:50 KST. Model: Opus 5.5, as routed by the caller. This is advice only and does not count as user approval.

Inputs:
- harness ca65920; tree at 9724889
- evidence: `evidence/m6/20261022T193317Z` (failed), `evidence/m6/20261022T174436Z` (P1), `evidence/m7/20261022T193453Z` and `20261022T174612Z`, `evidence/m5/20261022T193213Z`
- scripts: `scripts/gates/{agents-ns3-run.sh,gate-m6-kpm.sh,gate-m7-multignb.sh,gate-m3-xapps.sh,kpimon.sh,lint.sh}`, `scripts/probes/*.sh`
- `plan.md`, phase-02, and my report from 04:10
- read-only VM look at 21:48 UTC: kubectl, the kubelet config and `/var/log/pods` under `sudo -n`

## TL;DR

**The diagnosis is right, and I proved it by recounting.** The rotated file `6.log.20261022-193410.gz` holds the missing 95 indications from the M6 window. The captured file holds 104. 95 + 104 = 199, which is the wire count. RC_WMORE is 0/0 in both files. This is a harness measurement defect, not a product defect.

**The fix is a root-run reader of the pod's `/var/log/pods` files.** It reads every rotated and live file, decompresses `.gz`, parses the CRI format, filters to records at or after capture start, and fails closed when it cannot prove the window start is still on disk. The pass condition stays exactly the same.

**Re-run V5 fresh (M5, M6, M7) at the fix's SHA.** S1 needs no re-run.

**This is not T6.** It is V5's first failure. My 04:10 wording over-reached, and the phase-02 text governs.

## 1. Diagnosis (Q1): right and sufficient (verified)

**Rotation mechanics (verified on the VM):**
- Kubernetes is v1.33.13. `/var/lib/kubelet/config.yaml` has no `containerLog*` key, so the kubelet defaults apply: `containerLogMaxSize` 10 MiB and `containerLogMaxFiles` 5.
- The pod log dir contains `5.log` (the previous container instance), `6.log.20261022-175906.gz`, `6.log.20261022-193410.gz`, `6.log.20261022-194910` and the live `6.log`.
- The suffix in a rotated file's name is the rotation time, which is the **end** of its content. `193410.gz` runs 17:59:09.71 → 19:34:10.05. `194910` runs 19:34:10.18 → 19:49:07.8.
- The newest rotated file stays uncompressed. Older ones are gzipped at the next rotation.
- The Kubernetes logging docs say that only the newest file is served by `kubectl logs` (source below). The captured log starts at 19:34:10.177, which is the first record of `194910`.

**Recount (read-only, CRI timestamp in [19:33:19, 19:34:28)):**

| File | Indications | hdr/msg RC_WMORE | Records |
|---|---|---|---|
| `6.log.20261022-193410.gz` | 95 | 0/0 | 1052 (1 partial `P`) |
| `6.log.20261022-194910` | 104 (= captured log) | 0/0 | 1102 |
| total | **199 = wire** | 0/0 | |

**Rates:**
- About 10.5 MB in 15 min under the 5-node M7 load, roughly 11.6 KB/s.
- About 1.2 KB/s idle (8.5 MB in 2 h).
- The live `6.log` was 8.5 MB at 21:48 UTC, so idle rotation was due around 22:10 UTC.
- Any 76 s M6 window can catch a rotation. Every M7 run (about 28 min) will rotate once or twice.

**This is a latent defect from M0–M7, not something P2 introduced:**
- P1's M7 (`174612Z`, capture at 17:46:14) has a log that starts at 17:59:09, after the 17:59:06 rotation. Its informational count was 2258 against a wire count of 4949.
- P2's M7 log starts at 19:49:11. Its count was 2058 against 5006.
- M7 only *records* the count, so it stayed green.
- A recount across files for P2's M7 window [19:34:55, 20:03) gives 4907 indications, with WMORE 0/0. My guess is that the 99 short of the wire are indications sent toward the deleted e2term that never reached kpimon. This is informational only.

## 2. Fix (Q2)

### Reader: new `scripts/gates/pod-log-window.py`

Run it as `sudo -n python3 -I <reader> <dir> --since <epoch> [--until <epoch>]`. Stdout carries the log text, and the shell redirects it so the file is owned by the user. The manifest goes as JSON on stderr to `<out>.manifest.json`.

1. **Locating the directory.**
   - Path: `/var/log/pods/<ns>_<pod>_<uid>/<container>/`, with the uid taken from `kc get pod -o jsonpath='{.metadata.uid}'`.
   - Read every container subdirectory, to keep the `--all-containers` semantics.
   - Assert that the pod's `spec.nodeName` equals `hostname`. The cluster is single-node, and a mismatch means the files are not local.
2. **Choosing files.**
   - Take names matching `^(\d+)\.log(\.\d{8}-\d{6})?(\.gz)?$` and ignore `*.tmp`.
   - If both `X` and `X.gz` exist, read only `X.gz`. The kubelet writes `X.gz.tmp`, renames it to `X.gz`, and only then removes `X`, so reading both would double-count.
   - Read order: restart number ascending, then rotated files by suffix ascending, then the live `N.log`.
3. **Parsing (same as kubelet).**
   - Each record is `<RFC3339Nano> <stdout|stderr> <P|F> <content>`.
   - Keep a record when its timestamp is at or after `since`. That is kubelet's `--since-time` rule.
   - Emit the content, and add a newline only after an `F` record. Partial `P` records do occur: 1 inside this M6 window and 10 in `193410.gz`. A marker split across a `P`/`F` pair must still be counted.
   - **Do not compare timestamps as strings.** containerd's RFC3339Nano trims trailing zeros (for example `…17:59:09.71339545Z`). Parse them instead: `datetime.fromisoformat` on the VM's Python 3.12.3 accepts 9 fractional digits (verified there). Otherwise compare only the first 19 characters against an integer-second boundary; `CAP_T0` is an integer.
4. **Consistency (bounded, logged).**
   - List the files, read them all, then list again.
   - If the name sets differ, a rotation happened during the read. Retry up to 3 times, then exit 2. This is a read-consistency loop, not a re-run of a gate.
5. **Coverage (fail closed; this is what keeps the check strong).**
   - For each container, the first record of the oldest file read must be earlier than `since`. kpimon logs DEBUG lines every second, so this always holds when the window start is still on disk.
   - Otherwise exit 3 with "window start not covered: rotated file deleted" and print the file set.
   - Exception: the container started after `since`. Record that case.
6. **Manifest.** List the files read, each with bytes, first and last timestamp, and the number of records in the window. Add `rotationsInWindow` (rotated files whose suffix is later than `since`), `coverage`, `retries`, and `kubectlParity` (next item).
7. **Parity with kubelet (recommended, cheap).** The gate calls `kc logs --since-time` first. The reader's output for the live file must then start byte-for-byte with that output. The live file only grows between the two calls. This proves the parser matches kubelet exactly.

### Gate wiring

- **`kpimon_logs_since`** (`agents-ns3-run.sh:167-171`): keep the signature `<epoch> <out>`. Make it call the reader and return the reader's rc. It writes `<out>` and `<out>.manifest.json`.
- **M6** (`gate-m6-kpm.sh:86`): today the return code is ignored. Wrap the call as a new check, `m6_kpimon_log_window_complete_across_rotations`. Adding a check is additive, not a weakening. `kpimon_eq` stays unchanged: indications equal wire, and WMORE is 0/0. Add the file count, the rotation count and the coverage result to its detail.
- **M7** (`:122`, `:185`): keep them informational. Put the manifest summary into `m7_kpimon_log_counts_informational`, and do not make a pass condition out of it. A coverage failure there is recorded, not gated.
- **`probe-ns3-pause-ric-reaction.sh:165`** benefits automatically.
- **Self-test:** add `pod-log-window.py --self-test`. It builds a temp dir with:
  - a rotated `.gz` holding records before and after `since`;
  - a marker split across `P` + `F`;
  - a stderr `"\nheader RC_WMORE "` fragment;
  - an `X`/`X.gz` twin;
  - a live file;
  - an older-instance `5.log`.

  It asserts the exact counts, that the twin is read once, and exit 3 when the oldest file starts after `since`. Generate the fixtures at run time and commit no binary files. Run it from `lint.sh` (host) and as an M6 prerequisite check (the VM's Python 3.12).

### Is reading `/var/log/pods` with sudo acceptable? Yes

- It is read-only and changes nothing on the host or VM.
- It uses the same `sudo -n` NOPASSWD route the gates already use: `capture.sh` (tcpdump, kill), `agents.sh:45-54,78,94` (modprobe, apt, install, the docker shim) and `kpimon.sh` (extract).
- The `fresh-install` snapshot has NOPASSWD, so M9 works too.
- `/var/log/pods` is `drwxr-x--- root`, so root is required.
- lint rule 3 forbids `sudo <shell function>`. The reader is a file, so `sudo -n python3 -I "$HARNESS_DIR/scripts/gates/pod-log-window.py"` passes.
- A refusal would be T8, so do not work around one.
- **Alternative without sudo (unverified here):** the kubelet's `/logs/` handler, via `kubectl get --raw /api/v1/nodes/<node>/proxy/logs/pods/<dir>/<ctr>/<file>`. It is more obscure, so I prefer sudo.

### Which gates share the defect (verified by grep)

| Where | Use | Effect today | Action now |
|---|---|---|---|
| `gate-m6-kpm.sh:86` | pass condition | false FAIL (this failure) | fix |
| `gate-m7-multignb.sh:122,185` | informational | numbers wrong in P1 and P2 | fix (shared function) |
| `probe-ns3-pause-ric-reaction.sh:165` | probe evidence | partial | fixed by the shared function |
| `gate-m3-xapps.sh:162` (`m3_patched_kpimon_log_zero_wmore`), `:106` | **pass condition**, plain `kc logs` | a rotation inside M3's window could hide WMORE lines, a possible **false PASS** | not in V5. Track it and fix before the P9 freeze with an M3 run (§5) |
| `probe-ns3-pause-ric-reaction.sh:163`, `probe-rc-control-latency.sh:116` (RIC and rc logs) | informational | partial | none. Rung gates judge on wire, ledger and digests, never on rc's log |
| future gates R0–R3 | any pod log used as evidence | — | use the reader, collect one window per run |

**What to avoid:**
- **Raising `containerLogMaxSize`.** It changes the VM config, diverges from `fresh-install` and M9, and only lowers the odds of the failure.
- **Counting from Influx instead.** That narrows the check: Influx does not see kpimon's in-process WMORE.
- **A tolerance.** That weakens the check.
- **A background `kubectl logs -f`.** You would have to manage the process lifecycle, and a dropped stream loses lines silently.
- **Re-running M6 unchanged and hoping no rotation hits it.** That is re-running until green.

## 3. Re-run scope (Q3)

- **V5 complete and fresh at the fix's harness SHA: M5, then M6, then M7.**
  - M6 and M7 both run the changed code.
  - M5 does not, but it takes about 46 s and gives one coherent V5 set at one SHA.
  - Total is about 31 min, so update the resume card first.
- **No S1 re-run.**
  - `gate-s1-pacer-lockstep.sh` never calls `kpimon_logs_since` (verified by grep).
  - It sources `agents-ns3-run.sh` only through `agents.sh`, for the ns-3 helpers.
  - Record `git diff --stat ca65920..<fix>` in implementation-notes as the argument. It should touch only the reader, `agents-ns3-run.sh`, gate-m6, gate-m7 and `lint.sh`. V1 evidence (s1/20261022T191853Z at ca65920) stands.
- **Pre-flight before V5 (read-only, not a Verify).**
  - Run the reader on the VM with `--since 2026-10-22T19:33:19Z --until 2026-10-22T19:34:28Z` and expect 199 indications and WMORE 0/0. This reproduces the failed window on the real rotated files.
  - Do it **before** the V5 re-run. `193410.gz` is deleted at about the third rotation from now (kubelet keeps 4 rotated files), and the re-run's M7 alone causes 1–2 rotations.
  - If the reader cannot reproduce 199, fix the reader before running V5. A V5 run with a broken reader is a wasted, T6-grade failure.
- **What happens after the re-run:**
  - Every M6 check green, including the new coverage check: V5 passes.
  - Any check red in the fresh M5, M6 or M7: PAUSE T6, with no second fix. This includes the new coverage or self-test checks.

## 4. T6? (Q4): No. The phase-02 text governs

- **The binding text.**
  - phase-02 Failure Protocol: "If any Verify step does not meet its stated pass condition … spawn kongming … apply … re-run the Verify step. If it fails again … PAUSE T6".
  - plan.md T6: "a Verify still fails after one kongming-guided fix".
  - Both work per Verify. V1 failed once, was fixed and passed. V5 is failing for the first time, and its root cause (kubelet rotation) has nothing to do with the V1 fix.
- **My 04:10 step 9** ("if any check in step 6 or 8 is red, PAUSE T6") was over-broad on step 8.
  - Its purpose was to forbid a second self-fix of the pacer-exit read. It should have applied to V1, which was step 6.
  - Counsel cannot add a trigger to the contract. kongming's counsel is not a contract amendment, and it is not user approval.
  - Record in implementation-notes that this report supersedes that sentence, and why.
- **This fix does not change the outcome.**
  - It changes no pass condition, pin or product code.
  - It changes the measurement from a partial view to the complete one.
  - It adds checks; it removes none.

## 5. Other things in the evidence (Q5)

1. **The M7 informational kpimon numbers in both `174612Z` and `193453Z` are partial (§1).** Note this in implementation-notes. Re-running P1's M7 is not needed, because the line never gated anything.
2. **M3 can give a false PASS (§2 table).** This is worse than M6's false FAIL. Add it to implementation-notes as an open item, and fix it before the P9 freeze or Stop B by switching M3 to the reader with `since=install_start`, then running M3 once. Do not slip it into this commit unverified, because M9 runs M3 unattended.
3. **Retention ceiling.** 5 × 10 MiB is about 50 MiB, roughly 55–60 min at the 5-node load. A rung gate that collects one kpimon window longer than that, for example one window across a whole C1 set, will trip the coverage check. That fails closed, which is correct. Collect one window per run.
4. **A stray `evidence/m6/.claude/agent-memory/kongming/` (empty).** The runtime created it because this consult started with its cwd in `evidence/m6`. Delete it before the next commit, and spawn kongming with the worktree root as cwd. I wrote no memory there.
5. **Non-issue: kpimon's "List for connected gNBs" includes e2mgr DISCONNECTED nodes.** There are 5 now against 3 in P1, because of nodes from earlier gates. This is kpimon's own listing. The wire shows exactly one subscription request and one response, and `connected_set_exact` passed. No action.
6. **M5 and M7 otherwise look clean.**
   - M7 checks: no new restarts, agent RSS flat at 1.5 MiB, max 1-min load 1.57 on 8 CPUs, 0 SCTP ABORTs.
   - The load is low, but timing calibration stays on hold anyway per the user's hold.

## Work checklist (numbered next steps)

1. Delete `plans/261023-0009-…/evidence/m6/.claude/`. Run everything from the worktree root.
2. Write `scripts/gates/pod-log-window.py` as specified in §2, covering: the file-set rules, the `P`/`F` reassembly, parsed timestamps, the consistency loop, fail-closed coverage, the manifest, `--until` and `--self-test`.
3. Rewire `kpimon_logs_since` to call the reader and add the kubectl parity check. In M6, wrap line 86 as `m6_kpimon_log_window_complete_across_rotations` and run `--self-test` as a prerequisite check. In M7, add the manifest summary to the informational record. Add `--self-test` to `lint.sh`.
4. Run `scripts/gates/lint.sh`, including the self-test.
5. Pre-flight (§3): reproduce 199 and WMORE 0/0 for [19:33:19, 19:34:28) from the real rotated files. Do it soon, before `193410.gz` is rotated out. Record the numbers and the manifest in implementation-notes.
6. Record the root cause in `implementation-notes.html` (P2):
   - kubelet defaults 10 MiB/5 files; `kubectl logs` reads only the newest file;
   - the 95 + 104 = 199 recount;
   - the latent M7 partial numbers in P1 and P2;
   - the M3 false-pass open item;
   - the retention ceiling;
   - that this report supersedes step 9 of the 04:10 report;
   - that no pass condition changed.
7. Commit and push with no plan IDs in the messages, e.g. `fix(gates): count kpimon log lines across kubelet log rotations`. The failed M6 evidence is already committed in 9724889, so keep it as the first-failure record.
8. Update the resume card, then run M5, M6 and M7 fresh at the fix's SHA.
9. Pass criteria: all three exit 0. In M6, the coverage check passes, its detail names the files read, and `kpimon_eq` shows indications = wire with WMORE 0/0. M7's manifest probably shows 1 or more rotations, which exercises the multi-file path live, and its in-window count is close to wire minus the losses around the delete.
10. If any check in step 8 is red: PAUSE T6 (journal, kongming note, resume card, push), with no second fix.
11. If green: run the P2 phase-exit checklist, then a kongming go/no-go for P3. The open items to carry forward are M3 (before P9) and the per-run log windows for the rung gates.

## Assumptions

- **The kubelet keeps 4 rotated files plus the live one (`MaxFiles` 5), so `193410.gz` survives about 2 more rotations.** Confidence: medium-high. Kubelet behaviour, not verified on this VM beyond the defaults being in effect. If it is already gone at step 5, skip the reproduction and rely on the self-test plus the recount in this report.
- **The kubelet compresses through `X.gz.tmp`, then renames, then removes `X`.** Confidence: medium (from the kubelet source as I remember it). The "read `X.gz` only when both exist" rule is safe either way.
- **The M7 shortfall of 99 indications is due to the e2term delete.** Confidence: low (my guess). It is informational, and nothing depends on it.
- **The VM's Python at M9 (`fresh-install`) is the same 3.12.** Confidence: high (same image).

## Status

DONE. The diagnosis is verified by a recount (95 + 104 = 199 = wire, WMORE 0/0). The fix is a fail-closed rotation-aware reader behind `kpimon_logs_since`. Re-run M5, M6 and M7 fresh at the fix's SHA; S1 does not need a re-run. This is not T6, and the next red V5 is.

## Unresolved questions

- None blocking. One for later: should the M3 fix be scheduled at P9 or folded into the next phase that re-runs M3? I recommend before Stop B.

## Sources

- [Kubernetes v1.33 docs, Logging architecture](https://v1-33.docs.kubernetes.io/docs/concepts/cluster-administration/logging/): `kubectl logs` shows only the latest log file; `containerLogMaxSize` 10Mi, `containerLogMaxFiles` 5.
- [k8s.io/kubernetes/pkg/kubelet/logs package](https://pkg.go.dev/k8s.io/kubernetes/pkg/kubelet/logs): the container log manager (rotation and compression); a TODO to support rotated logs in `kubectl logs` (issue #59902).

# Kongming counsel: P10 M9 attempt 1 red: heartbeat torn read (Failure Protocol)

Date 2026-10-28 ~19:15 KST. Model: Opus 5.5 (caller-routed `opus`). Advisory only. This is not user approval.
Phase/task: P10 (M9), first failed Verify after the 18:16 KST re-issue, so the one-fix budget is fresh.
Failed: V1 (exit 1), V2 (step set `m0,m1` only), V4 (`watchdog-lost.json` present). Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/20261028T092148Z/`.

## Verdict: GO, with conditions

- **GO** for one guided fix: an atomic heartbeat write plus a discriminating self-test case. Then freeze it as F′, get the spare Codex review, revert `fresh-install` again, and do a fresh M9 run with `--run-prefix o`.
- **NO-GO** for re-running at F. That would be a blind retry of a race that will recur: attempt 1 hit at check 75, and a full run makes about 460 checks.
- The locked outcome does not change, and no signal is weakened.

## TL;DR

- Your root cause is right, and the evidence now pins it to within about 3 ms.
- The fix is one line: `host-disk-watchdog.sh:60` writes to a temp file, then renames. Leave the monitor unchanged.
- Add fixture (8). It drives the **shipped** watchdog with a slowed `date` against the monitor. I ran it in a scratch copy: it fails 4/4 on the old code and passes 4/4 on the new.
- F′ touches no gate input, so `reference/r3p/` stays valid. No rehearsal and no regeneration are needed.
- Spend the spare Codex run (CX-3) on F..F′ plus a sweep for the same bug class.
- Revert, re-measure df (expect about 99–101 GiB), and run with prefix **o**.

## 1. Root cause: agreed, with no contradicting evidence

Verified facts:

| Evidence | What it shows |
|---|---|
| `scripts/vm/host-disk-watchdog.sh:60` `date +%s >"$out/heartbeat"` | The file is truncated at open in the forked child and stays empty until `date` has exec'd and written. The window is about 1–3 ms per poll under load. |
| `scripts/vm/m9-heartbeat-monitor.sh:49-50` | One `cat`, then a regex. An empty read means immediate `cancel "no watchdog heartbeat"`. |
| mtimes in `evidence/watchdog/`: `heartbeat` 18:59:23.448391; `watchdog-lost.json` and `free-series.tsv` both 18:59:23.451163 | The monitor read, logged and wrote its marker within about 3 ms of the watchdog's heartbeat write, in the same coarse-clock tick as the watchdog's next append. This is a direct timing hit on the truncate→write window. |
| `free-series.tsv`: 76 rows, 1793179308 → 1793181563 | The watchdog's period is 30.067 s (2255 s / 75). The monitor's 75th check landed at the same instant, so both periods are about 30.067 s. Their phase drifts slowly and can sit near alignment for many cycles. |
| `watchdog-alive.json` `maxAgeS 30`, `checks 74` | At least one earlier check read just *before* a write (age 30), and others read just after. The two loops were crossing each other's phase. |
| `heartbeat` content now `1793181563`; watchdog PID alive at 09:59:42; `min-host-free-gb.txt` mtime 18:38:53 and `watchdog-alive.json` intact | The watchdog did not die, and the directory was not wiped. The emptiness was transient. |
| Writers of `evidence/watchdog/`: only `run-to-m9.sh:133` (at start), the watchdog and the monitor (grep of `scripts`/`tools`) | No other process touches the directory. `vm-exec.sh` writes only `.last-<gate>` and `<gate>/<ts>/`, and m2 was mid-run, so no export or scrub ran. |
| Scratch experiment (copies of the three scripts, not the repo) | Real watchdog `--interval 0`, `date` slowed 0.3 s, real monitor at 1 s: **old code FAIL 4/4** at check 1 with "no watchdog heartbeat"; **new code ok 4/4**, 7 checks each. |

There is no contradicting evidence. Two side notes:
- "Terminated sleep 5" in the log is the `supervised` poll sleep receiving the monitor's child sweep. That is expected.
- Precedent: Round 2 of the pre-ship ledger, item R3, made the monitor's *own* record atomic for exactly this reason ("truncated by `>` can be read empty"). Nobody applied the symmetric fix to its *input*. The class was half-fixed.

## 2. The fix (Q2)

**Change 1: `scripts/vm/host-disk-watchdog.sh:60`, required**

```bash
    # written whole (temp file, then rename in the same dir), so the heartbeat monitor never reads it empty
    date +%s >"$out/heartbeat.tmp" && mv -f "$out/heartbeat.tmp" "$out/heartbeat"
```

- A rename in the same directory is atomic for readers: `cat` opens either the old complete inode or the new one.
- If the temp write fails (for example a full disk), `mv` is skipped. The heartbeat then goes stale and the monitor cancels after 2 periods, which is the correct fail-closed behaviour.
- Do not change the runner's `rm` list. A leftover `heartbeat.tmp` is overwritten on the first poll and nobody reads it.

**Do not make the monitor tolerant (no re-read).** Leave `m9-heartbeat-monitor.sh` byte-identical:
- After the rename write, an empty or partial read cannot happen. The only "missing" case left is "never written", which is a real failure.
- A retry would make fixture (8) unable to tell old from new (old code plus a retry usually passes), so it would mask a writer regression.
- It would change the F08 stop path that Codex and fixture (1) certified, for no remaining benefit.
- The defect is in the writer, so fix the writer.

**Change 2: `scripts/vm/m9-runner-selftest.sh`, new case (8); also list it in the header comment.** It must drive the shipped `host-disk-watchdog.sh`, as cases 5–7 drive the shipped runner text through `fn()`. A synthetic writer loop doing the old write proves nothing about the fix. Text as tested, with the VM-isolation env added so an accidental trip can never ssh to the real VM:

```bash
# (8) a live watchdog's heartbeat is never read torn: the shipped watchdog in a tight loop, its date slowed so a
# truncate-then-write heartbeat would sit empty for 0.3 s of every ~0.6 s loop, against the monitor at 1 s
d="$tmp/torn"; mkdir -p "$d/bin"
printf '#!/bin/sh\nsleep 0.3\nexec %s "$@"\n' "$(command -v date)" >"$d/bin/date"; chmod +x "$d/bin/date"
VM_SSH=selftest.invalid VM_DOMAIN=selftest-absent PATH="$d/bin:$PATH" \
    "$here/host-disk-watchdog.sh" --interval 0 --min-gb 0 --out "$d" >/dev/null 2>&1 & wdog=$!
sleep 300 & unit=$!
runner=$(dummy_runner)
"$here/m9-heartbeat-monitor.sh" --runner-pid "$runner" --dir "$d" --interval 1 --deadline-epoch $(($(date +%s) + 600)) \
    --stop-cmd "kill $unit" >/dev/null 2>&1 & mon=$!
sleep 8
if alive "$unit" && alive "$runner" && alive "$mon" && [ ! -e "$d/watchdog-lost.json" ] &&
    python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1])); sys.exit(0 if a["checks"] >= 5 and a["maxAgeS"] <= 2 * a["intervalS"] else 1)' "$d/watchdog-alive.json"; then
    echo "ok   a live watchdog's heartbeat is never read torn"
else echo "FAIL torn heartbeat read: $(cat "$d/watchdog-lost.json" 2>/dev/null)"; rc=1; fi
kill "$wdog" "$mon" "$unit" "$runner" 2>/dev/null
```

- The case adds about 8.5 s, well inside `lint.sh:55`'s `timeout 120`.
- `--min-gb 0` plus no `--runner-pid` means it never trips and never kills anything.
- On the new code the green is deterministic.

**Red-before-green proof (record it; it is the evidence the fix works):**
1. `git archive e0a6ac5 scripts | tar -x -C <scratchpad>/F`
2. Copy the new selftest into `<scratchpad>/F/scripts/vm/` and run it. Expect exactly one FAIL (case 8, "no watchdog heartbeat") and exit 1.
3. Run the selftest in the worktree 3 times. Expect every case ok and exit 0.
4. Save both outputs under `evidence/m9/20261028T092148Z/fix-proof/`.

**Out of scope for this fix (checked):** `min-host-free-gb.txt` (watchdog `:63`) is also written with `>`.
- Its only cross-process reader is `m9-verdict.py`, run in `finish` right after `kill "$wd_pid"` without a wait.
- A torn read needs TERM to land in the µs between a builtin `echo`'s open and write, on the rare poll that lowers the minimum. That is about 1e-7, and it fails closed.
- Leave it. If the Codex review flags it, accepting the same one-line rename is fine and stays inside this fix.

## 3. Freeze consequences (Q3)

- **F′ = the fix commit.**
  - Commit only the two files: `git add` those paths, never `-A`. The worktree has docs WIP and submodule pointer changes.
  - Use a conventional message with no plan IDs, for example `fix(vm): write the watchdog heartbeat by rename so the monitor never reads it empty`.
  - Push to origin. `vm-exec.sh:31-32` refuses a SHA that is not on an origin branch, and the VM clones it (`:40-51`).
- **K14 statement is sufficient; no rehearsal.**
  - Record that `git diff --name-only e0a6ac5 F′ -- scripts tools <reference>` lists only `scripts/vm/host-disk-watchdog.sh` and `scripts/vm/m9-runner-selftest.sh`.
  - Record that `git diff --quiet e0a6ac5 F′ -- scripts/gates tools scripts/pins.conf scripts/m9-budget.json scripts/run-to-m9.sh scripts/m9-verdict.py <reference>` exits 0.
  - The VM never executes either changed file. They are host-side only (grep), and every VM-side gate input (pacer, scenario, schedule, rung-config, pins) is byte-identical.
  - A rehearsal would run identical VM code for about an hour of VM churn and gain nothing.
  - The changed host path cannot be soaked meaningfully at 30 s periods: the race took 37 min to show. Fixture (8) is the proof, and the M9 run exercises it live.
- **`reference/r3p/` is still valid.** Verified: `equal/digests.json` holds `ledger`, `ipc` {1,2,3}, `traces` (33 files) and `extra` {collet-start-time, kpm-headers, rc-multiset}, and `equal/files.json` holds {predictor-records, scenario, schedule}. Nothing in the reference holds a harness SHA (grep for `e0a6ac5|harness` finds nothing). The F rehearsal `r3p/20261028T055917Z` remains the `--reference` evidence.
- **Re-run at F′:** `lint.sh`, `m9-runner-selftest.sh` (now 11 cases) and `m9-verdict.py --self-test`, and re-check `ls-remote` on the pins at pre-flight.
- **Codex: use the spare (CX-3).**
  - This is exactly "a new evidence-backed finding". The stakes are maximal, because a second red is T6.
  - The normal reviewer already caught half of this class (R3) and missed its mirror, so a reader of different provenance is the right instrument.
  - The controller runs it. Record `git rev-parse HEAD` before the fix commit as this fix's pre-build sha (`df3bb79` unless more plan commits land) and run `adversarial-review --base <that>`, background, `--json`, 15 min cap.
  - Focus:
    - the inventory is the 2 files, with the proof outputs attached;
    - read-only context: `run-to-m9.sh`, `m9-heartbeat-monitor.sh`, `m9-verdict.py`, `vm-common.sh` and the attempt-1 evidence;
    - (a) is the rename write correct and sufficient;
    - (b) does fixture (8) discriminate;
    - (c) is there any other file that one host M9 process writes while another may read it, or any other false-red or false-green in the stop paths;
    - mark each inventory item reviewed or not.
  - Triage into `reports/codex-pre-ship-audit.md` under a new "## F′ heartbeat fix" section. Mark both items reviewed and end `Status: complete` again.
  - Accept within-contract findings that are confined to the host supervision files (watchdog, monitor, selftest, the runner's supervision functions, `m9-verdict.py`): fix, then repeat the proof, lint and K14 steps.
  - Any finding needing a change to a gate input, an acceptance signal or a ruling → PAUSE T9, not a quiet second fix.
  - CX-1 failure → `Codex skipped: <reason>`, and a `code-reviewer` subagent reviews the same inventory and checklist.

## 4. Contract, prefix, snapshots, disk (Q4)

- **Within contract.**
  - The outcome, acceptance signals and judges are unchanged. The monitor is still strict on the first read, and `m9-verdict.py` is untouched.
  - The harness SHA is a P9 freeze artifact, not a locked-outcome term. `pins.conf` (the forks) is unchanged.
  - This is the one guided fix. After it, any red in the re-run's V1–V5 → `PAUSE T6`.
- **Prefix: use `o`, not `n`.**
  - Phase-10 Failure Protocol: "must use a prefix whose names do not exist". `m0-probe-n10280921` is a name from the n run (`gate-m0-host.sh:21-22` builds `m0-probe-<prefix><MMDDHHMM>`).
  - Pre-flight check 1 forbids `m0-*-n*`. Reusing n would need a reinterpretation, while `o` complies literally.
  - My Stop B line "a re-run may reuse n" assumed no probe leftover. It is superseded here.
  - **Never `m`.** `run-to-m9.sh:52`'s `^m[0-9]-` matches every `m0-probe-*` name, so the runner would refuse. f and l are reserved.
  - The verdict only records `run_prefix`; it does not judge it.
  - Update `m9-run-report-template.md:9` (it hard-codes F and n) to F′ and o. At P10 step 7 the docs (`README.md:44`, `deployment-guide-l-release.md:72`) must show what actually ran or present the prefix as a parameter.
- **Snapshot: keep `m0-probe-n10280921`; do not delete it.**
  - The packet allows deleting m0-probe snapshots only "when the disk budget requires it". It does not: the projection is about +15.
  - It pins only the small 18:21 boot overlay.
  - My Stop B phrase "may always be deleted" was too loose; the packet rule governs.
  - Record it in the resume card as the expected attempt-1 leftover, so the resume check is not a T3 mismatch.
- **Disk: re-check after the revert. That is the binding number.**
  - Pre-revert df is 85 ≥ 84 = T, so step 7 passes. It is below the optional 88 margin (`m9-budget.md:43`).
  - The revert should free the leaf overlay holding m0–m2 (about 16 GiB: 101 → 85). That is inferred, so measure it.
  - Expect about 99–101. Require ≥ 84, else PAUSE T2 without launching.
  - Commit a "P10 restart" projection row.
- **New fact to record, not to act on now.**
  - Attempt 1 measured a peak host-disk growth of **8 GiB in 363 s** (09:26:18–09:32:21Z, during m1), about 0.022 GiB/s against the budgeted 0.0093. That implies h ≈ 9 (trip ≈ 34) against the frozen h = 4 (trip 29); the budget's caveat expected "doubling → 8".
  - It is harmless at X″ ≈ 100: the expected minimum is ≈ X″ − 55 ≈ 45 GiB, about 16 above the trip.
  - Do not change `m9-budget.json` in this fix. It is a runner input and a different issue.
  - Put the measurement in `m9-budget.md` and in the run report, where the budget already promised that M9 would check h.

## 5. Ordered steps (Q5)

1. **Records.** Update the resume card with: root cause confirmed; counsel at this path; plan = fix → F′ → Codex spare → revert → `--run-prefix o`; `m0-probe-n10280921` expected and kept. Add a short `implementation-notes.html` entry. Commit and push the attempt-1 evidence dir (plans only).
2. Record the fix's pre-build sha: `git rev-parse HEAD`.
3. Apply change 1 and change 2 (section 2).
4. Run the red-before-green proof (F archive: 1 FAIL in case 8, exit 1; worktree ×3: all ok). Save it to `evidence/m9/20261028T092148Z/fix-proof/`.
5. Run `scripts/gates/lint.sh`, `bash scripts/vm/m9-runner-selftest.sh` and `python3 -I scripts/m9-verdict.py --self-test`. All must pass.
6. Commit F′ (the 2 files only). Record the F′ SHA.
7. Run Codex spare `adversarial-review --base <step-2 sha>` (section 3). Triage into the ledger and end `Status: complete`. Accepted host-side fixes go to F″ with steps 4–6 repeated. A T9 finding → PAUSE T9.
8. Push. Confirm with `git branch -r --contains <F′>`.
9. K14 record: the two `git diff` commands from section 3. Add an F′ addendum to `m9-budget.md` "Freeze" with the F′ SHA, the reason, "no gate input changed, reference/r3p valid", and the attempt-1 peak-growth fact. Update `m9-run-report-template.md:9`. Commit and push (plans only).
10. Pre-flight (Stop B mapping, adapted):
    - (1) Resume checks. The VM is **shut off** (not running/r3p-green). The tree is fresh-install > f7-rerun-green > r0-green > r2-green > r3p-green plus `m0-probe-n10280921`. There are no `o[0-9]-*` and no `m0-*-o*` names.
    - (2) Run `git diff --quiet <F′> -- scripts tools <reference>`. No untracked files there. F′ is on origin.
    - (3) Run `ls-remote` on the 4 forks and compare with `pins.conf`.
    - (4) Run lint and both self-tests.
    - (5) Record the tshark version.
    - (6) No host runner, watchdog, monitor or `vm-exec` process. The VM is off, so no gate unit can be active.
    - (7) `df -BG /home` ≥ 84 (85 now).
    - (8) Update the resume card ("P10 attempt 2 reverting"), commit and push.
11. Run `scripts/vm/vm-snapshot.sh revert fresh-install`. Re-measure df: ≥ 84, else PAUSE T2. Confirm `r3p-green` and `m0-probe-n10280921` are listed. Commit the "P10 restart" projection row X″ − 84.
12. In the background, run `scripts/run-to-m9.sh --harness-sha <F′> --run-prefix o --no-snapshots`. Record the start epoch and the deadline (+20199 s). Update the resume card at each `<step> green` line.
13. On exit, apply V1–V5 per the Stop B mapping. Any red → `PAUSE T6 evidence=<run dir> journal=<path>`, with the journal and the kongming note per plan.md.

## What to avoid

- Re-running at F, or launching before the revert. The runner never reverts, and `gate-m0-host.sh` would pin the current overlay, with about 16 GiB of m1–m2 data, as the probe's backing.
- Adding a monitor retry, changing its interval, or offsetting the loops. Each hides the writer defect and changes the certified stop path. Desynchronizing only lowers the odds, because drift still crosses the phases.
- A fixture that re-implements the old write instead of running the shipped watchdog.
- `git add -A`, a bare `git stash`, or plan IDs in the commit or code comments.
- Prefix `m`; deleting `m0-probe-n10280921`; changing the trip point or the budget JSON in this fix.

## Alternatives and trade-offs

- **Reuse prefix n**, excepting the attempt-1 probe in check 1. It works mechanically (the runner checks `^n[0-9]-`, and probe names are minute-stamped) but needs a reinterpretation of binding text. `o` costs only a records note.
- **`code-reviewer` instead of the Codex spare.** It is cheaper and has precedent (Round 2). But R3 shows it caught only half of this class, and the spare exists for this situation. Use it as the CX-1 fallback.
- **Also harden `min-host-free-gb.txt` now.** It is zero-cost and correct, but the risk is about 1e-7, fails closed and is untestable without contrivance. Leave it unless a reviewer raises it.

## Success metrics

- The proof is recorded: F's watchdog plus case 8 → FAIL; F′ → ok ×3.
- The ledger re-ends `Status: complete`, with both F′ items reviewed.
- The M9 re-run passes all of these:
  - exit 0;
  - `exactStepSet: true`, `notM9: false`, `highestGreenRung: r3p`;
  - top-rung C1 all true and `equalsReference: true`;
  - `minHostFreeGb` ≥ 25 (expect about 45);
  - `watchdogAlive.maxAgeS` ≤ 60, `checks` ≈ run seconds / 30, last check within 60 s of the end;
  - no lost, tripped, deadline or monitor-lost markers.

## Assumptions

- **High:** the revert deletes the leaf overlay holding m0–m2. It did so for the 18:21 revert (+3 GiB), and the m0-branch was deleted, so nothing references that overlay. **Measure it.** If df stays below 84 → PAUSE T2.
- **High:** no VM-side state from the cancelled m2 is needed. The failure is host-side, and the m0/m1 evidence is already on the host.
- **Medium:** the controller session can run Codex now (CX-4); if not → CX-1 fallback.
- **Medium:** the coarse-clock mtime reading (about 3 ms) is my inference about kernel timestamp granularity. The experiment and the code path carry the conclusion without it.
- **Runtime note:** this ran on Opus 5.5 per the caller's routing, not `fable`.

## Unresolved questions

- None blocking.
- For the user later: should the h ≈ 9 (trip 34) measured in attempt 1 replace h = 4 in a future budget? It is not needed for this run at X″ ≈ 100.

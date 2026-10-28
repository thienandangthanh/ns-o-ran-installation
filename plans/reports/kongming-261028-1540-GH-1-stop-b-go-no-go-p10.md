# kongming 2026-10-28 15:40 KST: Stop B (P9 exit), go/no-go on P10

This is advisory only (Opus 5.5, xhigh, as the user's CLAUDE.md routes it). It is never user approval. All evidence was checked on the host and is read-only. I did not use the VM, SSH, virsh or the runner.

## Verdict

**GO for P10, on two conditions:**
1. The user frees disk so that `df -BG /home` ≥ 84 GiB. I recommend 88.
2. The must-dos below are done before PAUSE B.

Every must-do is a records change in `plans/` or `docs/`. None touches `scripts/`, `tools/` or `reference/`. F, K14, the Codex ledger and the runner's refusal check therefore stay valid, and nothing re-enters the freeze or audit rules. I found no code defect that requires a re-freeze.

## Q1. V1–V5 and the A1 P9 requirements (verified 15:40–15:55 KST)

| Item | Result | Evidence |
|---|---|---|
| V1 pins = fork heads; F on origin | **met** | I re-ran `git ls-remote` at ~15:45: Testbed `c6d1434a`, ns-3 `ba954440`, oran-interface `96efc40e` and e2sim `2209995a` all equal `pins.conf`. `pins.conf` is unchanged since F. `origin/migrate-l-release-NIST-1-8-0` contains `e0a6ac5`. |
| F → HEAD touches only plans/docs | **met** | `git diff --name-only e0a6ac5 HEAD` lists 809 files, none outside `plans/` or `docs/`. `git diff --quiet e0a6ac5 -- scripts tools <plan>/reference` exits 0, and nothing is untracked there, so the runner's refusal check (`run-to-m9.sh:56-59`) passes. |
| V2 reference | **met** | `sha256sum -c reference/r3p/SHA256SUMS` is OK on 5 files, and there is no unlisted file (the compare trap). `equal/` holds ledger, ipc 1–3, 38 traces and extra (`rc-multiset`, `kpm-headers`, `collet-start-time`) plus `files.json`. `recorded/` is reported but never judged (`ts-rung-lib.sh:207-221`). |
| V3 projection row | **met** | `m9-budget.md`: X 58 − T 84 = **−26**. My `df -BG /home` also reads 58G. |
| V4 self-tests | **met** | `lint.sh` ok. `m9-runner-selftest.sh` ok: 9 printed cases plus the substitution-4 validator self-test, which is silent. `m9-verdict.py --self-test` ok with **18** cases, which cover no heartbeat, stale heartbeat, early-dead monitor, missing or 24 minimum free, subset, missing and extra step, not equal, single and sub4. |
| V5 Codex ledger | **met** | `Status: complete`. All 38 inventory items were reviewed by Codex, and the post-fix diff by `code-reviewer`. The R1/R2 fix commit `2d1314e` had no independent review. I read the final `run-to-m9.sh`, `vm-common.sh`, `host-disk-watchdog.sh`, `m9-heartbeat-monitor.sh` and `m9-verdict.py` at F and found no defect, so this report closes that gap. |
| Runner fail-closed (F07/F08) | **met** | The step set is exact (`m9-verdict.py:53-55`); a subset is marked notM9; the top-rung check covers c1, gatePass and equalsReference; min free must be ≥ 25; the heartbeat checks maxAge and lastCheckEpoch; both monitors are supervised. A stale `.last-<step>` cannot certify a pass, because `vm-exec.sh:92` writes `.last` on every path that exits 0. |
| `--reference` | **met live** | Rehearsal `r3p/20261028T055917Z` at F: pass, mode c1, equalsReference true, a1PolicyTypeCreated true, 168 checks, 1284 s against a 2529 s timeout. |
| F10 records | **mostly met** | `substitution3Applied` is false on r0 and r1 at F (43 and 46 checks), true on r2 (`034353Z`) and r3p, and emitted by i2. M9 carries a per-rung map. **Gap:** the run-report template lacks **S3**, which P10 A1 V5 requires (must-do 4). |
| Budget vs 25 | **met** | `m9-budget.json`: trip 29 (h 4), wall 20199 s, cold floors for i0/i2. |

## Must-do before PAUSE B (records only; no re-freeze)

1. **Push.** Origin is at `a3f02b9`. `8d51d68` and the Stop B commits are unpushed, and Stop B requires a push.
2. **Fix the journal** (`docs/journals/2026-10-28-m8-m9-stop-b.md`):
   - (a) Use this report's name.
   - (b) Item 3 is wrong as framed. P10 step 5 already says `--no-snapshots`, and A1 did not override it, so the plan's default is *no* snapshots. Reframe it as: "P10 runs `--no-snapshots` (recommended); rule otherwise only if you want per-step snapshots." The reasons are in Q4 D.
   - (c) Item 5 must name the revert and the full command (Q2).
   - (d) V4: add the verdict self-test (18 cases). The ledger's "19 cases" is an erratum.
   - (e) Add the interpretations and the risk section listed in Q3.
3. **Map P10's stale Verify wording to the A1 runner.** Write this in the resume card's next action or as a short note in phase-10. It is a mapping of the same signals, not a weakening, so it is not a scope change.
   - **V4**: no `watchdog.json` exists. Read V4 as `evidence/m9/<ts>/verdict.json`: `minHostFreeGb ≥ 25`, `watchdogAlive.maxAgeS ≤ 2 × intervalS`, and none of `watchdog-tripped.json`, `watchdog-lost.json`, `wall-deadline.json` or `monitor-lost.json` in that dir. Without this mapping, P10 could hit a V4 that cannot be met as written (T3) at the end of a 4-hour run.
   - **Step 2**: read "r3-green" as `r3p-green`, and "host free ≥ 20" as `df -BG /home` ≥ T (84, or 88).
   - **Step 6**: read "reference/r3/" as the r3p gate's own `equalsReference` against `reference/r3p/equal/`.
   - **V2**: "no notM9 flag" means `notM9: false`.
4. **Fix the run-report template.** Add **S3** (portability smoke deferred to the next goal) to Descoping. Change the runner command to `--run-prefix n --no-snapshots`. Add interpretations (h)–(j) from Q3.
5. **Update the resume card and plan.md.** Set P9 to done. Set next to P10 with the pre-flight list in Q2. Note that this report serves as P10 step 1 while F and the pins stay unchanged.
6. **Correct `m9-budget.md`.** Its line "M9 repeats those snapshots" is false under `--no-snapshots`; say the M0–M7 term is conservative there. State that the 88 option is headroom only and the trip stays 29. State that P10 re-measures after the revert (Q2 step 6).

## Q2. P10 against the A1 runner

**Is a revert needed? Yes, run it before the runner.** The runner never reverts.

`gate-m0-host.sh` does revert to `fresh-install`, but only after it creates `m0-probe-n<MMDDHHMM>` from the current state, and it keeps that probe. The M0–M7 evidence `m0/20261021T212837Z-host` shows the effect: the pre-probe active overlay (`ubuntu24.1792618108`) survives as the probe's backing file.

Without the P10 revert, the probe would pin the active overlay above `r3p-green`. That is `/home/andang/VMs/ubuntu24.04-r3p-green.qcow2`, 2.8 GB apparent, holding the rehearsal plus the r0 and r1 runs. The revert first does three things:
- it makes "revert fresh-install, then one invocation" literal;
- it frees that overlay (a revert deletes the active overlay, per the same evidence and the P5 lesson; inferred, so measure it);
- it starts from a known state.

**Consistency with the runner:**
- `--run-prefix n` is valid: one letter, not f or l. The runner's collision check is `^n[0-9]-` (`run-to-m9.sh:52`). m0-host names carry a minute timestamp, so they cannot collide.
- With `--no-snapshots`, no `n[0-9]-` names are ever created, so a re-run after a fresh revert may reuse n.
- The m0-probe-n snapshot remains after M9. It is tiny, and the M0 probe pair may always be deleted.
- The runner does **not** check that the top rung's snapshot exists. Pre-flight must.
- The verdict is at `evidence/m9/<run_ts>/verdict.json`, and the runner prints `M9 verdict: PASS|FAIL … -> <path>`.
- The wall is 20199 s from the runner's start. The expected run is about 13.5–14.5 ks (≈3.8 h).
- K15 (trip at 25) is superseded by the A1 trip at 29.

**P10 pre-flight, in order:**
1. Run the resume checks. Expect domstate running, current `r3p-green`, and `vm-snapshot.sh list` showing fresh-install > f7-rerun-green > r0-green > r2-green > r3p-green, with no `n[0-9]-*` and no `m0-*-n*`.
2. Confirm F: `git diff --quiet e0a6ac5 -- scripts tools plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference`; no untracked files there; `git branch -r --contains e0a6ac5` shows origin.
3. Re-check V1 with `git ls-remote` on the four forks.
4. Run `lint.sh`, the runner self-test and the verdict self-test.
5. Record the Debian trixie tshark version. It is `4.4.19-0+deb13u1` on packages.debian.org as of 15:4x today. If it changed, record that and proceed (default; Q4 C) unless the user ruled otherwise at Stop B.
6. Check that no host runner, watchdog, monitor or `vm-exec` process is running, and that no `gate-*` unit is active on the VM.
7. Record `df -BG /home`. It must be ≥ 84 (or 88). If it is short, do not revert; print PAUSE T2.
8. Update the resume card ("P10 running, reverting"), commit and push. This touches plans only.
9. Run `scripts/vm/vm-snapshot.sh revert fresh-install`. Then:
   - record `df -BG /home` again (expect about +2.6 GiB);
   - confirm `r3p-green` is still listed;
   - add a "P10 start" projection row (X′ − 84 ≥ 0) to `m9-budget.md` and commit it (plans only).
10. In the background, run `scripts/run-to-m9.sh --harness-sha e0a6ac5ee0b4824038c22e39d467fc1f714d0d13 --run-prefix n --no-snapshots`. Record its start epoch and its deadline (start + 20199 s). Update the resume card at each `<step> green` log line.
11. After it exits, apply V1–V5 with the mapping in must-do 3.

## Q3. Is the journal complete and accurate?

**Accurate:** the numbers I checked:
- 167 and 168 checks;
- 43 and 46 checks;
- 1053 and 881 s;
- 20199 s, h 4 and trip 29;
- X 58, T 84 and −26;
- the X1–X3 and R1–R2 findings;
- F, the pins and the rehearsal facts.

**Inaccurate:**
- item 3, the snapshot default (must-do 2b);
- item 5, the incomplete command;
- V4, which omits the verdict self-test.

**Missing items:**
- The P10 Verify mapping (must-do 3) and the template's S3 gap.
- More interpretations to ratify:
  - (h) "25 GB" is enforced as 25 **GiB** (`df -BG`), which is stricter. M9's effective floor is the 29 GiB trip, since any trip fails M9.
  - (i) F10's "every verdict carries `substitution3Applied`" is met by the rung verdicts (r0/r1 false), by i2 and by M9's per-rung map. The m0–m7 and i0 verdicts do not carry it, which matches phase-09 A1 ("every rung and M9 verdict").
  - (j) Known record slips: list them or write "none". The earlier counsel listed "evidence-commit slips"; the journal dropped them.
- The r2 single was **not re-run at F**. The only r2 gate change since its last green (`640c7f9`, `034353Z`) is `pipefail` on three tee'd judges. Re-running those judges on the host against `034353Z` at F exits 0 (expect, wire, stub).
- The residual-risk section from Q4, in short.
- Runtime expectations: about 3.8 h, wall 5.6 h. Keep the host awake (no suspend) and the Claude session open, and do not write heavily to `/home` during the run.
- **Never delete or move files in `/home/andang/VMs/`.** The qcow2 files form one backing chain: `ubuntu24.04` ← `ubuntu24.1792618143` ← `ubuntu24.1792653312` ← `…-r0-green` ← `…-r2-green` ← `…-r3p-green`. Deleting, say, `…-r0-green.qcow2` destroys `r2-green` and `r3p-green`. The current text, "deleting r0-green frees almost nothing", covers virsh deletions, not file deletions.
- The push state (must-do 1).

## Q4. Residual risk to the M9 verdict (disclose; no fix before Stop B)

**A. First cold execution of the exact R-section order.** This is the main risk; my rough guess is a 15–25 % chance of a red M9.
- i0 has never been green cold. Its only green, `082556Z`, was warm, and `rc-lib.sh` has changed since. Its cold parts did run in other gates: the decoder build in s0/q8 and the cold rc install in q8.
- i2's only cold run, `171928Z`, was red on rtmgr sessions, later fixed. i2 has not run since `fa7d64e5`, but the change since then (ensure-before-restart) is ordered correctly in i2: ensure at line 46, restart at line 64.
- m0–m4 have not run since `8ed1d9f`. Shared libraries changed (`lib.sh`, `agents.sh`, `bringup.sh`, the F09 scrub), and later gates exercised them.
- The scrub's pre-Influx path at m1/m2: in the M0–M7 m1 install log, influxdb is "NOT being deployed", so that path is regex-only, and a lint fixture covers it.
- The dev VM also carried state from s0, s1, q7, q8, p5 and n4, which are not in M9's step set.
- A red costs up to about 4 h. With `--no-snapshots` it costs no pinned disk, because the next revert frees the failed overlay.

**B. Network dependence for about 4 h:** GitHub, OSC nexus, Docker Hub, the Ubuntu and Debian archives, and pip (hash-pinned). The timeouts are at least 1.5× the measured time + 600 s, so only an outage, not slowness, should break a step.

**C. Decoder drift.** `equal/` includes `kpm-headers`, `collet-start-time` and `rc-multiset`, all decoded by unpinned images: `tshark-kpm` (trixie-slim) and `rc-decode` (ubuntu:24.04). A tshark or asn1 change could flip `equalsReference` with no fault in the system. The probability for a security point release is low. Pinning the image now would change F (K14, Codex spare, rehearsal), which is not worth it. Re-check at pre-flight 5.

**D. Disk and the watchdog.**
- T = 84 by construction ends at the trip (29) if growth equals the estimate.
- Slack beyond that is inferred, not measured:
  - `--no-snapshots` avoids the duplicate blocks behind the 43 GiB M0–M7 term (the merged overlay is 36.96 GiB, so ~5 GiB);
  - the revert frees ~2.6 GiB.
- The expected end free is then ≈ 36 ± 3 GiB with 84, which is a low trip risk. With per-step snapshots, the slack falls to ~2.6, against the ±3 uncertainty of the R estimate. So: `--no-snapshots` with 84 is acceptable, and **88 is cheap insurance** against losing a 4-hour run.
- A trip stops the run cleanly (bounded stop path, verdict fail, T2).

**E. Revert semantics.** These are covered above. The P10 revert deletes only the active overlay above `r3p-green`. `r3p-green`'s own state (the chain through `…-r2-green.qcow2`) is untouched, so diagnosis can still roll back to `r3p-green`.

**F. A1 type path.** In M9, i2 creates type 20008, and r2/r3p take the "found" path with no reboot in between. Both paths have been proven: found in C1 `044557Z`, create in rehearsal `055917Z`.

**G. Any harness fix after Stop B changes F.** The runner then refuses to start until it is re-frozen. That re-enters K14, the reference rule for r3p inputs, and the Codex spare (1 left), so the P10 one-fix budget is expensive. Prefer fixes outside `scripts/`/`tools/` where the cause allows it.

**H. Host lifetime.** The runner is a child of the Claude session. A TERM writes a fail verdict and stops the VM gate units. A SIGHUP or SIGKILL leaves no verdict, and host suspend breaks the wall-clock timeouts.

## Alternatives considered

- **A pre-M9 "cold R-section" rehearsal from `f7-rerun-green`** (`--from i0`). Rejected. f7 holds ns-3 and the agents at old pins, so it is not M9's post-m7 state. A faithful rehearsal needs M0–M7 anyway, which is M9 itself.
- **Per-step snapshots in M9.** These give mid-chain diagnosis points. They cost ~5 GiB of slack and make a red M9 pin tens of GiB that a non-leaf delete cannot free. Not recommended.

## Assumptions

- A libvirt external revert deletes the active overlay when no snapshot uses it as a backing file. *High*: the M0–M7 m0-host disk chains and the P5 lesson agree. Pre-flight 9 measures it.
- The `--no-snapshots` saving is ~5 GiB. *Medium*: it is inferred from the merged overlay against the host-free drop; host evidence and metadata are not separated.
- No dev-only VM state is needed by i0–r3p. *Medium*: I checked statically only (gate order, scrub path, ensure-before-restart). M9 is the first real test.
- The tshark security release keeps its version until P10. *Medium*: re-check at pre-flight 5.

Status: DONE_WITH_CONCERNS (GO for P10 once the user frees disk and must-dos 1–6 are done; no code change needed)

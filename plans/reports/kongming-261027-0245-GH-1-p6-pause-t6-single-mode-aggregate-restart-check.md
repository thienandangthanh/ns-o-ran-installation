# kongming counsel: PAUSE T6, single-mode aggregate restart check in gates r0 and r1

2026-10-27, about 02:45 KST. PAUSE T6 note for P6, step "regression: r0 single, then r1 single". Advice only; **not user approval**. Model: Opus 5.5 (user routing for kongming). VM not touched.

**Read for this counsel:** `gate-r0-rc-scripted.sh`, `gate-r1-rc-multi-control.sh`, `gate-r2-ts-stub-qp.sh`, `lib.sh`, `lint.sh`, `rc-lib.sh`, `r0-run-facts.py`, `run-to-m9.sh`, `vm-exec.sh`, `plan.md` (resume card, T6), `phase-06` (V4, Failure Protocol), `decisions-261026-2230`, my `kongming-261027-0235`. Evidence: `r0/20261026T171731Z` (all files), with `r0/20261023T073520Z`, `r0/20261026T165654Z`, `r1/20261023T084654Z` and `r2/20261026T143406Z` for comparison.

## Verdict
1. **The diagnosis is correct.** This is a latent harness defect. In `--mode single`, r0 and r1 could never pass their aggregate restart check, for any data. It is not N4, not the pods, not the L release, and not option B.
2. **PAUSE T6 is the right call.** It is a red on the regression step after the one guided fix (0235 rule).
3. **Fix:** add one shared judge, `rc_restarts_zero_all <run>...`, to `rc-lib.sh`. Each gate calls it with the exact run list its mode makes: live1..N, plus k9 or f2 in c1. The fix is at least as strict in every mode, it keeps the check names, and it leaves r2 untouched.
4. **The user must approve it at release.** It edits the judges of green rungs, and the 22:30 approval covered only the own-pod edits.
5. **The fix is not optional.** Without it, P6 V4 (R0/R1 single) and M9 (`run-to-m9.sh:61-62`, chain stops at first red) both stay red forever.

## 1. Diagnosis (verified)
| Claim | Evidence |
|---|---|
| k9 is skipped in single mode | `gate-r0-rc-scripted.sh:252` `if [ "$MODE" = c1 ]` wraps `r0_live k9` (:254) through C1 to `fi` (:307). Only `live1-after-pods.tsv` exists in 171731Z |
| f2 is skipped in single mode in r1 | `gate-r1-rc-multi-control.sh:270` `if [ "$MODE" = c1 ]` wraps `r1_live f2` (:272) to `fi` (:333). Same construct at :395 |
| The pipeline goes red although awk is clean | `lib.sh:14` `set -uo pipefail`; `r0:357` `cat live* k9 2>/dev/null \| awk`. Reproduced: missing file into awk returns 1. The check detail is empty (`exit 1: `), so awk printed nothing |
| The fact is false too | `r0:359` reuses the function, so `restartCountsAllZero: false` in facts.jsonl, although `restartCounts` is all 0 |
| calibrate mode is not affected | `r0:227-228` exits before :357 |
| r2 is not affected | `r2:441` uses a glob. There is no `nullglob`/`failglob` anywhere in `scripts/` (grep), so an unmatched glob stays literal, `cat` fails, and an empty set is red |
| It never showed before | Every earlier r0/r1 verdict was c1 (k9/f2 present) or r0 calibrate. 171731Z and 165654Z are the first single runs ever. **165654Z was red on this check for two causes**; the TS xApp and stub restarts masked this one |
| Back-test of the proposed judge on committed TSVs | r0 073520Z [live1-3,k9] → 0; r1 084654Z [live1-3,f2] → 0; r0 171731Z [live1] → 0; r0 165654Z [live1] → 1 (stubqp `rrkd6`, trafficxapp `f57mf` at 1); r0 171731Z [live1,k9] → 1 ("k9: no after-snapshot"). Old green verdicts are kept, the known-bad run is still red |

**Sweep for the same class** ("pipeline whose first stage reads a mode-optional file, under pipefail, as a judge"). I grepped `\bcat\b…2>/dev/null *\|[^|]` and every `2>/dev/null |` over `scripts/gates`, `scripts/vm`, `scripts/*.sh` and `tools/*/*.sh`.
- There are exactly three `cat` hits: r0:357 and r1:395 (defective) and r2:441 (glob, safe).
- The other `2>/dev/null |` pipelines are safe because their exit status is unused or intended:
  - `rc-lib.sh:151-155`: route-owner assignments, defaulted to `unknown`;
  - `kpimon.sh:232-236`: `grep -o | wc -l` inside `echo`;
  - `agents.sh:211`: "no stats yet" is meant to return 1;
  - `ts-lib.sh:110`: committed patch files, inside `echo`;
  - M-gate lines that are not on this path.
- The `$(cat f 2>/dev/null || echo null)` facts are not pipelines.
- **r1 single:** I read the whole script. Every other f2 reference outside the c1 block is a Python glob (`:360` facts_final, `:347` agent_c2_fact). `r0-run-facts.py` picks runs by directory and passed with `runs: ["live1"]` in r0. r1:395 is the only single-mode defect I can find; r1 single has never run (medium confidence).
- **r2 single** (later V4) has no such defect: glob at :441, and the mode-dependent blocks at :296-311 and :357 are guarded.

## 2. Minimal fix (state it in the journal; apply only after the user approves)
**rc-lib.sh**, after `rc_restarts_zero` (:179-182). Also add one line to the header index (:12-13).
```bash
# rc_restarts_zero_all <run>...: each named run's after-snapshot exists, is non-empty and shows restart count 0
rc_restarts_zero_all() {
    local l bad=0
    [ $# -ge 1 ] || { echo "no run named"; return 1; }
    for l in "$@"; do
        if [ ! -s "$EVIDENCE_DIR/$l-after-pods.tsv" ]; then
            echo "$l: no after-snapshot"; bad=1
        elif ! rc_restarts_zero "$l-after"; then
            echo "$l: restart count not 0"; bad=1
        fi
    done
    [ "$bad" = 0 ] && echo "restart counts 0 in: $*"
    return "$bad"
}
```
**r0, replacing :357-359.** For r1 :395-397, use the same text with `f2` and `r1_`.
```bash
JUDGED_RUNS=(); for i in $(seq "$NLIVE"); do JUDGED_RUNS+=("live$i"); done
if [ "$MODE" = c1 ]; then JUDGED_RUNS+=(k9); fi   # the forced-late run exists only in c1 mode
check r0_restart_counts_all_zero rc_restarts_zero_all "${JUDGED_RUNS[@]}"
fact restartCountsAllZero "$(rc_restarts_zero_all "${JUDGED_RUNS[@]}" >/dev/null 2>&1 && echo true || echo false)"
```
**The `>/dev/null 2>&1` in the fact line is load-bearing.** The new judge prints messages. Without the redirect, `fact()` (`lib.sh:68-72`) writes the non-JSON value raw, possibly over two lines. `gate_finish` then fails in `json.loads`, so no verdict.json is written and the gate exits 2. Also keep both functions multi-line, ending in `}` at column 0, so lint can extract them with `sed`. Do not use a variable named `rc` inside them (lint's accumulator).

**Why this is not a weakening:**
- **Same per-row predicate.** `rc_restarts_zero`'s awk `$4 != 0` is the per-run judge that is already green. It covers every ricxapp pod row and every agent row, with no filter. Contract item 7 ("RestartCount = 0") is unchanged literally, so the locked outcome is unchanged.
- **c1:** the old check required k9 or f2 plus at least one `live*` file. The new one requires live1, live2, live3 and k9 or f2 **each**, which is a superset of the requirements.
- **single:** the old check was a constant red, carrying no information. The new one judges live1, the only run the mode makes.
- **Empty inputs:** an empty run list and an empty (0-byte) snapshot are now red. The old check passed an empty file.
- **Missing snapshot:** it is now red with the run named. The old check was red silently.
- **Unchanged:** the check name, verdict keys and r2. The back-test (section 1) reproduces every committed verdict.

**Your glob idea** (judge all existing `*-after-pods.tsv`, fail if no live file) is acceptable, but it is **weaker in c1**: it drops the explicit k9/f2 requirement and never required live2 and live3. The per-run checks still catch those cases, but you would have to argue that point to the user. The mode-derived list removes the need for that argument. A glob union adds nothing: the evidence dir is fresh per run (`lib.sh:22-26`), and `rc_pod_snapshot "$label-after"` inside r0_live/r1_live (`r0:182`, `r1:170`) is the only writer of `-after-pods.tsv`.

**lint.sh test**, inserted before `[ "$rc" = 0 ] && echo "lint: ok"` (:52). I ran it in a scratch copy: rc=0 on the fixed function. The static rule flags exactly r0:357 and r1:395 today and does not flag r2:441.
```bash
# rc_restarts_zero_all: every run a mode makes needs a non-empty after-snapshot with all restart counts 0; a list
# without the c1-only runs passes, an empty list or file does not, and the fact form is exactly one word
source <(sed -n '/^rc_restarts_zero()/,/^}/p; /^rc_restarts_zero_all()/,/^}/p' scripts/gates/rc-lib.sh)
EVIDENCE_DIR=$(mktemp -d)
ok=$'pod\tricxapp-rc-a\tu\t0\t-\t-\nagent\t1\tc\t0\t-\t-'
printf '%s\n' "$ok" >"$EVIDENCE_DIR/live1-after-pods.tsv"
rc_restarts_zero_all live1 >/dev/null || { echo "restart judge: a single-mode run list was red"; rc=1; }
rc_restarts_zero_all live1 k9 >/dev/null && { echo "restart judge: a missing k9 snapshot passed"; rc=1; }
rc_restarts_zero_all >/dev/null && { echo "restart judge: an empty run list passed"; rc=1; }
: >"$EVIDENCE_DIR/k9-after-pods.tsv"
rc_restarts_zero_all live1 k9 >/dev/null && { echo "restart judge: an empty snapshot passed"; rc=1; }
printf '%s\n' "$ok" $'pod\tricxapp-trafficxapp-b\tu\t1\t-\t-' >"$EVIDENCE_DIR/k9-after-pods.tsv"
rc_restarts_zero_all live1 k9 >/dev/null && { echo "restart judge: a restart count of 1 passed"; rc=1; }
printf '%s\n' "$ok" >"$EVIDENCE_DIR/k9-after-pods.tsv"
rc_restarts_zero_all live1 k9 >/dev/null || { echo "restart judge: a complete c1 run list was red"; rc=1; }
[ "$(rc_restarts_zero_all live1 live2 >/dev/null 2>&1 && echo true || echo false)" = false ] ||
    { echo "restart fact form is not exactly false"; rc=1; }
rm -rf "$EVIDENCE_DIR"
# a silenced cat of a named evidence file into a pipe: a mode that skips that run makes cat fail, pipefail red
if grep -nE 'cat [^|#]*"\$e"/[A-Za-z0-9_]+-[A-Za-z0-9_.-]+ [^|#]*2>/dev/null *\|[^|]' scripts/gates/*.sh; then
    echo "a silenced cat of a named evidence file into a pipe (see above)"; rc=1
fi
```
Record the back-test output (section 1) in the cause record as supporting evidence. It is not a substitute for the fresh runs.

**Commit message:** no plan IDs (rule). For example: `fix(gates): judge the restart counts of exactly the runs each mode makes, so single mode can pass`. vm-exec refuses an unpushed SHA (`vm-exec.sh:30-32`), so push before the run. The repo is public.

## 3. What the user must rule on at release
| # | Ruling | kongming default | What would flip it |
|---|---|---|---|
| U1 | **Approve editing the r0 and r1 judges.** That means the additive `rc-lib.sh` helper, the two call sites and the lint test. By commit count, this is the fourth change to code r0/r1 execute since their C1: `1bc626b` (pre-Stop A), `611271d` (approved 22:30), `c3817e3` (shared C9 judge, P5 fix), now this. The 22:30 ruling approved only the own-pod edits, and kongming cannot approve | Approve, note it like 22:30, and let r0/r1 single at the new SHA be its regression | User prefers U1-alt |
| U1-alt | Run the regression as `--mode c1` (k9/f2 present, no edit now) | Not recommended. It only postpones the edit to V4 and M9, which use single, and costs about 4x the VM time | – |
| U2 | **T6 budget after release.** Literal ruling 1: release resets the budget. The user-approved fix is part of the release, not the guided fix, so the first failed Verify after release (r0 single, r1 single, ...) gets one guided fix | Literal reading. Practical, because r1 single has never run | User wants this step "fix consumed": any red on r0/r1 single = T6 directly |
| U3 | Optional rider: add the TS xApp and stub to the r0/r1 `restartCounts` fact map (`r0:360-377` lists only rc, kpimon, hw-go and agents; the judge already covers them) | No, keep the edit minimal. Stop B note | User wants the verdicts self-describing now |
| U4 | Carried over from 0235: per-step or per-release budget for V1–V6; Stop B invariant ("recreate, never filter"); option D | Unchanged | – |

**Order after release**
0. Resume-card checks: domstate, snapshot-current = r2-green, boot time still 16:26:48 UTC.
   - If the VM booted during the pause, re-apply the boot-guarded TS xApp/stub recreation first. That is the standing procedure from 0235 Q3, not a new fix.
   - Clear the stale "in-flight: r0 single" line.
1. Apply the fix, exactly as in section 2.
2. `scripts/gates/lint.sh`: ok.
3. Commit, push, and record the harness SHA on the card.
4. `vm-exec.sh gate-r0-rc-scripted.sh --harness-sha <new> --timeout 5400 -- --mode single`: exit 0, every check PASS, including `r0_restart_counts_all_zero` with detail "restart counts 0 in: live1". The last run took about 8 min of gate time.
5. Read-only pre-r1 check (0235 step 7). The TS xApp/stub names in the new `live1-after-pods.tsv` must equal the running pods (`d5swj`, `km99t` unless step 0 recreated them), counts must be 0, and the boot time unchanged. Do not recreate.
6. r1 single, same form: exit 0, every check PASS, with `r1_restart_counts_all_zero` detail "restart counts 0 in: live1".
7. N4 per `kongming-261027-0215`. It is now in `plans/reports/` (`kongming-261027-0215-GH-1-p6-n4-sdu-header-rule-and-double-count-design.md`); I have not read it.

## 4. Everything else in 171731Z
All 43 checks pass except `r0_restart_counts_all_zero`.
| Item | Value | Reading |
|---|---|---|
| Q2 | 5 `SwitchToLte` at −5 dB, so substitution 1 applies, −1000 dB | Same as every r0 run since 000514Z. Deterministic |
| C8 | c8free = c8null = `22570657bd39…` | **Identical digest in R0 C1, R1 C1, R2 C1, 165654Z and 171731Z.** Good UL-off baseline for N4 V2 |
| C9, C2, C5, D7, V4 refusal, G4, KPM moves | all pass; KPM headers by node 298/199/199, the same as R0 C1 live1; kpimon 696 indications, WMORE 0 | Normal |
| Restart map and TSVs | 8 rows at 0 (before and after are identical). TS xApp/stub created 17:16:52 (p6-pre), the gate started 17:17:31 | B worked. The `restartCounts` fact omits the TS xApp and stub (U3). The `restartCountsAllZero: false` fact is the defect |
| Route owners | 12041/12042 −1 owner = rc at start and end, with rtmgr and e2term in agreement. It was kpimon in 165654Z and mixed in R0 C1 | rtmgr ordering is nondeterministic. It is a fact, not a judge |
| **Surprising: the TS xApp and stub are unrouted** | 0 route lines naming trafficxapp or stubqp at ready-probe, live1 start and live1 end, against 14 in r2 C1 live3-end | Inference (medium-high, not checked on the VM): appmgr's registrations did not survive the r2-green boot. `ts-lib.sh:292` says they survive a pod replacement but not an appmgr restart. As a result the pods are inert in r0/r1, which is closer to M9, where r0/r1 run before i2. r2 re-registers in its pre step (`r2:107` → `ts-lib.sh:293`), so the later r2 single is fine. Do not register them by hand before r0/r1 |
| Slack, L | T_start 119.9996 s, T_gate 9.992 s, T_ctl 29.991 s; L 7.8–9.3 ms (calibration L_max 12.9 ms) | Normal, in line with R0 C1 |
| VM | up 50 min at start (boot about 16:27 UTC = card), / 49 % used, no stray process | No boot between B and the run |

## What to avoid
- Do not re-judge 171731Z offline and call r0 "green". Re-run at the fixed SHA: it costs about 8 min and gives a verdict from the code M9 will use.
- Do not use `--mode c1` to dodge the edit (U1-alt).
- Do not edit r2:441 now. It is correct; moving r2 onto the shared helper is a Stop B option.
- Do not apply or commit the harness change before the user releases the pause.
- Do not drop the fact-line redirect.
- P7 i3 and P8 r3 (not written yet) must call `rc_restarts_zero_all` with their mode's run list, not a `cat | awk` pipeline. Add this to their design requirements.

## Corrections of my own counsel (0235)
- Q2 step 6 predicted "exit 0, every check PASS" after B. I missed this defect, which was already the second cause of the 165654Z red on `r0_restart_counts_all_zero`.
- Q1 and Q2 called the kept TS xApp/stub live −1 route candidates in P6. The route tables show they have no routes at all in the current state. B's strictness argument stands (the judge still covers them), but the "real RIC-health signal" point is weaker for r0/r1 than I said.

## Assumptions
- **High:** the diagnosis (code, reproduction, back-test).
- **High:** no other instance of the class in the bash harness (grep sweep).
- **Medium-high:** the TS xApp/stub are unrouted because the registrations were lost at boot (inference from route tables plus `ts-lib.sh:292`).
- **Medium:** r1 single has no other single-mode defect. I read the whole script, but it has never run.
- **Medium:** U2 literal reading. The user may tighten it.

## Unresolved questions
1. U1: approve the edit to the r0/r1 judges (fourth change to green-rung code)?
2. U2: after release, is the budget fresh for the r0/r1 step, or already consumed?
3. U3: fold the TS xApp/stub into the `restartCounts` fact now, or leave it for Stop B?

Status: DONE
Summary: Diagnosis confirmed. r0:357 and r1:395 `cat` the c1-only k9/f2 snapshot under pipefail, so single mode can never pass, which blocks P6 V4 and M9. No other instance in the harness. Fix: one shared `rc_restarts_zero_all` judge called with the mode's exact run list (at least as strict, back-tested on committed evidence), plus a lint test; it needs the user's approval at release.
Concerns/Blockers: user rulings U1 (edit to the green-rung judges) and U2 (T6 budget reading); r1 single has never run.

# kongming counsel: PAUSE T8 in P6/P7 (QP fork push refused), 2026-10-27 ~13:05 KST

This is advice only. It is **not user approval**. Model: Opus 5.5, per the user's routing for kongming. I did not touch the VM, and I pushed nothing.

**Where this file is.** It was written in kongming's isolated worktree, because the harness blocked writes to the shared checkout. Copy it to `plans/reports/` in the work context, with the same name.

**Inputs**
- Plan files: `goal-packet.md`, `plan.md`, `phase-06` (with its Release amendments), `phase-07`.
- Records: the draft journal `docs/journals/2026-10-27-m8-m9-p6-pause-t8-qp-fork-push-refused.md`, `decisions-261027-0955`, `kongming-261027-0215`.
- Evidence: `evidence/n4/20261027T031109Z` and `evidence/n4/20261027T031836Z` (verdicts, V2, V3, host V5, the IPC traces), and `evidence/m7/20261027T032633Z`.
- Harness: `gate-n4-ul-metric.sh`, `check-pdcp-volume-totals.py`, `check-n4-v5-windows.py`, `influx-dump.sh`, `rung-config.json`, and the git history of the branch.
- Code: `ns-3-mmwave-oran/scratch/scenario-zero.cc`, and `ric-app-qp/src/{qptrain,prediction,main,database}.py` at `901f8c5`.
- Primary sources:
  - statsmodels `stattools.py` (v0.14.4 and v0.14.6);
  - ricxappframe `xapp_frame.py` (tag 3.2.2);
  - the Flux spec, string literals;
  - the Claude Code auto mode configuration docs.

## TL;DR
1. **T8 is the right classification.** `plan.md:130` says it outright: "A classifier refusal is T8."
   - Letting the V4 chain that is already running finish is correct. Before the PAUSE line, do only the pause procedure: no new VM job, no fix, no other push route, and no edits to settings.
2. **P6 followed its contract.** The commit times prove the pre-registration came first, and the selection of the fallback was mechanical.
   - One record is wrong: `rung-config.json` says "registered 12:30 KST". The real time is 12:10 KST (`55e7f57`). Correct it.
   - The V2 reference is right.
   - Before the dump, add three checks that only make the gate stricter:
     - the dump takes its UL pattern from `rung-config.json`;
     - the Influx rows are compared with the IPC samples, for completeness and equal values;
     - a self-test fixture covers the checker's Influx parser.
3. **The finding the user must hear is not the UL starvation. It is the DL.**
   - The gNB-cell DL is constant: 8371 and 4186 kbit in 97 of 100 samples.
   - Stock QP training calls `adfuller`, which raises on a constant series, and nothing catches the error. ricxappframe's loop catches only `queue.Empty`, so QP's process exits at the first prediction request.
   - That holds unless the 16-step training window still contains seq 2, which happens only when the first trigger is at seq ≤ 17.
   - K17's "model file per R3 cell" depends on this. Put the choice of option in front of the user at this release.
4. **Deferring the Flux finding to the P7 reader rewrite is sound.** Add two things: a guard for Flux `${` interpolation (or no string literals at all), and unit tests with injection-shaped ids. Never deploy commit 1.
5. **How the user can release T8.** The documented fix for a "Data Exfiltration" block on the user's own repositories is an `autoMode.environment` entry in `~/.claude/settings.json`.
   - Other routes: a narrow `permissions.allow` rule, or the user pushes by hand.
   - An `autoMode.allow` entry or "explicit intent" in a message does not clear the built-in data-exfiltration rule.

## Q1. T8, the running chain, and what not to do before the PAUSE line
**Classification.** T8 is correct, for these reasons:
- The cross-cutting rule is explicit: "Permissions. Auto mode with no rules file … A classifier refusal is T8" (`plan.md:130`). Cite that line in the journal (§1); it is stronger than the argument that the push is a scripted step.
- It is not T7: the patched `token =` line is empty and the push never landed.
- It is not T3: no part of the contract became unmeetable because of it.

**Letting the V4 chain finish is correct.**
- The chain started (12:22 KST) before the trigger, as one detached job with a hard timeout. The resume card listed it beforehand, and it does not touch the QP fork.
- T8's "never work around it" forbids getting the refused effect by another route. It does not require killing unrelated work that is already running.
- Stopping mid-gate would leave ns-3, agent and capture state that needs more VM work to clean up. It would also throw away regression evidence the release needs.
- "Terminal" governs what happens *after* the PAUSE line. The pause procedure itself (journal, kongming, resume card, notes, push) is made of tool calls.
- Verified at 12:57 KST: m7 `20261027T032633Z` exit 0 at `9755007` (m5 `032251Z` and m6 `032457Z` passed before it).

**Conditions while you wait**
- Launch no new VM job: no K18 dump and no re-run.
- If r0, r1 or r2 single goes red, apply no fix. Record it as the first failed Verify after the release with the fix budget unused, and list it in the journal's questions. The PAUSE id stays T8.
- If the chain hangs past its hard timeout, stop it with the documented PGID kill and record that.
- After it ends:
  - confirm no stray ns-3, agent or capture process (`pgrep -f <full path>`, empty `ss -Sanp`);
  - record domstate, snapshot-current and the current pod names in the resume card;
  - set "in-flight background jobs: none".

**Do not, before the PAUSE line:**
- Retry the push in any form: no `gh api` upload, no other remote or URL, no SSH variant.
- Move the QP tree anywhere else:
  - into the parent repo;
  - into the Testbed fork, as files or patches (that would also break N7);
  - into a gist;
  - as a new submodule.
- Change `.git/info/exclude`, any `settings*.json`, `CLAUDE.md` or hooks, or run `/auto-mode-setup`. Changing the permission regime is the user's call. Auto-mode bypass is also a built-in soft-deny rule.
- Amend, rebase or delete `dev/l-release-nist180` at `901f8c5`. The user may push exactly that commit.
- Start P7 commit 2 or anything later.
- Print any form of the token.
- Call any tool after the PAUSE line.

**Evidence path.** Give the PAUSE line a real evidence directory, for example `evidence/p7/<UTC-ts>/`, containing:
- the V1 tree equality (both `aece41f6`, and how the scratch clone was made);
- `push-refusal.txt`:
  - the command, the KST time and the classifier label `[Data Exfiltration]`;
  - the remote URL, the branch and the SHA;
  - "not retried";
- the token pre-check as counts only.

**`push=refused`.** Append it only if the pause-time push of the records is refused. T8 already encodes the refused push of the QP fork.

## Q2. P6 contract fidelity and test strictness
**Pre-registration: verified, with no tuning after data.**

| Time | Commit or run | What it is |
|---|---|---|
| 12:01:39 | `533b404` | Release amendments: the primary, the fallback formula, V3 and V5 |
| 12:06:40 | `b153b45` | `check-n4-v5-windows.py` and `check-pdcp-volume-totals.py` |
| 12:10:01 | `55e7f57` | `rung-config.json` `ul_rate`, with the primary "constant" and the fallback "steps" spelled out; the ns-3 pin `ba954440`, which already contains `--ulTrafficPattern=steps` |
| 12:11:09 | `031109Z` | First UL-on run |

- The constant primary failed the registered predicate clearly: cell 3 had 28 of 170 windows red, with clause (b), and (c) in 7 of them.
- The steps code matches the registration exactly (`scenario-zero.cc:690-716`):
  - Interval 5000 µs;
  - PacketSize 200 for period 0, then `200 + 50·(k mod 16)` scheduled at 100 + 100·k ms;
  - the smallest SDU is 228 B, above the 40 B constraint.
- The steps run was mandated by the rule, so it holds no option value. The commit at 12:22 only records that selection.
- **Fix the record:** `ul_rate.value.v5Rule.registered` reads "2026-10-27 12:30 KST, before any UL-on run". That contradicts the runs at 12:11 and 12:18, and an auditor would read it as post-hoc. Change it to "12:10:01 KST, commit `55e7f57`, before the first UL-on run `031109Z` (12:11:09 KST)". This corrects a record; the rule does not change.
- **Disclose if needed:** if any UL-on dev or smoke run happened on the VM before `031109Z`, say so in the journal. I could not check the VM.

**V2 reference: right.**
- K19 asks for the last free-run at the pre-P6 pins. The reference's emitter is `962fabc7`, and the gate asserted that it is not the gated pins.
- Its overall digest, `22570657bd39…`, is the exact C8 digest the amendment names, so it is tied to the committed R0, R1 and R2 evidence.
- Whether the reference is r0's `c8free` or a later pre-N4 free-run makes no difference, by determinism.
- Optional strengthening for later: assert the reference emitter **equals** the pre-N4 pins, rather than only "is not the new pins".

**V3: sound for its purpose.**
- The audit is an independent connection to the same MN PDCP trace sources. It verifies:
  - the wiring;
  - the read and reset windows;
  - the header strip;
  - attribution through the UE map;
  - rounding once per cell.
- `perCellMaxErrBits` 496 is the rounding bound (≤ 500 by construction), not drift.
- A1–A5 fail closed on ties, non-int counters and missing PDCPs.
- It is not vacuous: a gNB-side PDCP or a double connection would show in A1–A3.
- No change is needed before the dump.

**V5 judge: correct, with one gap and one untested path.**
- **Gap.** The rule n4-v5-r1 counts only windows of 16 seqs that are all present. So missing rows (kpimon loss, a late subscription, a short drain) shrink the window set silently instead of failing. Keep the registered rule unchanged and add a separate completeness check (D2 below).
- **Untested path.** The self-test exercises only `judge()`, not the Influx annotated-CSV parser. The one-shot dump would be its first real use.
- **My smoke test.** I ran the checker on R2 live1's raw dump (`evidence/r2/20261026T143406Z/runs/live1/influx-kpimon.csv`, pre-N4 pins).
  - It found 100 rows per gNB node and 85 windows each, all failing clause (a) because the fields are absent at those pins.
  - So the parser keys rows correctly on a 3-node lock-step dump with no `_time` collisions.
  - What this did not test: the `long` detection of the two new fields.

**Fix before running `--part dump`.** These only make the gate stricter; commit them before the dump.

| Id | Severity | Change |
|---|---|---|
| D1 | Medium | **UL pattern from `rung-config.json`.** `PATTERN` defaults to `constant` (`gate-n4-ul-metric.sh:30`). Read `ul_rate.value.pattern` (now `steps`) and fail on a CLI mismatch. Make `cal_ok` also check that CAL's recorded ns-3 command line carries `--ulTrafficPattern=steps`. The IPC equality would catch a mistake, but only by turning the one-shot dump red. |
| D2 | Medium-high | **Influx equals IPC.** Reuse `tools/e2-evidence/influx-vs-trace.py`, as M6 and M7 do, for nodes 1, 2 and 3 on the dump run, with pivoted cell and UE exports as M7 makes. Judge its `all` numbers strictly: `influx_cell_rows == trace_samples`, `influx_ue_rows == trace_ue_rows`, `all_fields_differ == 0`, `duplicate_keys == 0`. Also assert that the G1 UE fields K7 needs are present: `ns3.imsi`, `ns3.l3.servCellId`, `ns3.l3.nbr*.cellId`. This makes the dump a faithful QP fixture and catches a short `sleep 5` drain. M6 at the new pins (`032457Z`) already shows 151 fields, 0 differences and 100 of 100 samples for one gNB, so this is feasible. |
| D3 | Low-medium | **Parser fixture.** Add a small raw annotated-CSV fixture to the V5 self-test: `long` fields pass; a `double` field fails clause (a). |
| D4 | Records | Change `influx-dump.sh`'s header ("Evidence only: never a QP input (UL-off rows)"); it is false for K18. Fix the `registered` time (above). |
| D5 | Process | Take the dump once. A red host V5 is a failed Verify (Failure Protocol), never a re-dump. Fill `dumpEvidence`. Commit `n4-ul-on-dump.csv` under its name (not matched by `influx-*.csv`, so no `git add -f`), scrubbed, with its size recorded. R2's raw dump was 4.75 MB, which is fine. Optionally record the kpimon image digest and the Influx version as fixture provenance. |

## Q3. The UL diagnostic, and the DL finding behind it
**Facts** (from the IPC of `031836Z`):
- **UE maps.** Cell 2 holds IMSIs {3, 4, 5, 6} and cell 3 holds {1, 2}, in 99 of 100 samples.
- **Delivered UL per IMSI.** IMSIs 3 and 6 are healthy, 4 and 5 are starved, and 2 is partial.
  - Cell 3's UL is in effect IMSI 1 alone: its clean step pattern of 36, 44, 52, 60 … kbit is visible at seqs 83–89.
  - Cell 2's UL is mostly IMSIs 3 and 6.
- **A tail stall.** Cell 2 has six zero-UL periods in a row (seqs 92–97). Its tail window therefore lands on exactly 10 distinct rows, which is QP's threshold.
- **DL per cell.** The sequence is 0, 0, then 7534 (cell 2) or 3767 (cell 3) at seq 2, then **constant at 8371 or 4186 through seq 99**. This is the CBR offered load, which is correct for the PDCP SDU DL measurement (F6 in 0215).

**What the UL composition means.** On its own, it is a minor matter. The TS xApp reads only DL, the first number of each pair. UL affects decisions only through the VAR's cross terms, and it serves mainly to make QP's `constant()` False.
- After a QP-driven handover of IMSI 1 out of cell 3, cell 3's UL collapses to IMSI 2's sporadic bursts.
- Later cell-3 windows can then fail `constant()` (K17 "every R3 trigger window"), so the P7 dry run must check every trigger window after a handover.
- The starvation is plausibly an effect of substitution 1: at −1000 dB, UEs stay on poor mmWave uplinks. This is an inference. Confirm it in P7 from the UL SINR per IMSI in the ns-3 traces, as a diagnostic, not a gate. Record it in the run report; it is not a deviation.

**The DL finding, which the user should hear now** (verified against the sources):

| Step | What happens | Source |
|---|---|---|
| 1 | `train_cid` reads the cell, `constant()` is False because UL varies, then `md.process()` → `make_stationary()` → `adfuller(column)` for UL **and** DL | `ric-app-qp@901f8c5 src/qptrain.py` |
| 2 | `adfuller` raises `ValueError("Invalid input, x is constant")` | statsmodels `stattools.py:274-275` (v0.14.4; the same check is present at v0.14.6, the N2 pin) |
| 3 | The `try` in `train_cid` covers only `model.fit`, so the error propagates through `train_model` → `predict` → `qp_predict_handler` | `qptrain.py`, `main.py` |
| 4 | ricxappframe 3.2.2's `loop()` catches only `queue.Empty`, and QP's `start()` runs with `thread=False` | `xapp_frame.py:950-962` |
| 5 | So the QP process exits: no 30002 reply, a pod restart, and R3 red on RestartCount | consequence of 1–4 |
| 6 | Even with ADF skipped, VAR rejects a constant column (`get_var_endog(..., has_constant="raise")`); that error is caught, so no model file is written. That contradicts phase-07 K17 ("a model file for each R3 cell") | statsmodels `var_model.py` |

- **Consequence.** QP's `constant()`, the registered V5 predicate, is necessary but not sufficient for QP to train.
- With the NIST-faithful 16-step training read (phase-07 step 4), only windows that contain seq 2, that is, a first trigger at seq ≤ 17, have DL variation.
- This is not a P6 defect: V5 is exactly as registered. It is a feasibility issue for P7/P8 that P7 step 6 will hit.

**Options for the user** (my default first):

| Option | What it is | Ruling needed | Cost or weakness |
|---|---|---|---|
| **B (default)** | R3's first trigger at seq ≤ 17, so both gNB cells train on a window that contains seq 2 | No (P7 step 9 picks the schedule) | Fragile: one deviant DL row. I traced the lag search: only VAR lag 1 survives. |
| **A (robust fallback)** | Training reads [seq 0, trigger] (stock QP's `limit=4800` history, bounded in sim time); prediction keeps the 16-step window | Yes: it reinterprets "QP's 1600 sim-ms window" in N6 and step 4 | Ask the user to pre-authorize A now as B's fallback, to avoid a second pause |
| **C** | A guard: catch ADF/VAR errors, write no model, use the persistence forecast | Yes: it needs a waiver of K17's model-file assertion | — |
| **D** | Make the DL vary | Yes: it changes the pre-registered `r3Config.dl` and forces a new calibration | Not recommended |

- Add C's guard in any case, as crash-proofing, with a unit test that it never fires for an R3 cell. The pod then stays alive, and K17 still fails visibly.
- **Expected behaviour either way.** The DL forecasts track UE count × ~2093 kbit. The TS xApp will therefore move UEs from cell 3 (2 UEs) to cell 2 (4 UEs). That is a feasible QP-driven handover, but it is load attraction, not balancing (0215 Q7.9). QP prediction quality is out of scope; record this in the run report.

## Q4. The Flux-injection finding
**Verified.** NIST's `database.py` builds Flux with f-strings:
- `_escape_flux_string` escapes `\` and `"` only.
- The Flux spec makes `${…}` inside a string literal an evaluated interpolation, and the literal form must be escaped as `\${`.
- `r["{param}"]` takes the field name from config, unescaped.
- The inputs are `ueid` from the TS xApp's RMR payload, `cid` from UE rows that kpimon wrote, and config values.

**Threat model.** It is a single-VM testbed with RMR and Influx inside the cluster. Anyone who can forge an RMR 30000 message or write Influx rows already has more direct power. The expression runs inside a string literal with no imports possible. Severity is low, and the pattern is inherited and already public upstream.

**Deferral is sound** because V1 requires commit 1 verbatim and K6/K7 already require typed int filters. Add these:
1. Never deploy commit 1: `QP_SHA` in `pins.conf` must be the head after the reader rewrite, which is natural.
2. In commit 4:
   - Validate every id as a strict int, rejecting bool, float and non-digit strings, within `0..2^32−1`. Format it with `%d` into an unquoted comparison (`r["ns3.nodeId"] == 2`).
   - Validate the measurement, bucket and field names at config load against `^[A-Za-z0-9_.]+$`.
   - If any string literal remains, also escape `${`.
3. Unit tests in the image:
   - injection-shaped ids (`2") |> yield()`, `${now()}`, `2.0`, `True`, `-1`, `2**32`) are rejected before any query text is built;
   - a valid id yields the exact expected query.
4. Record it in the implementation notes and the P7 ledger: "inherited from NIST; closed by commit 4". It does not trigger T4 or T7, and it needs no pause.

## Q5. Ordered next steps
**Now, before the PAUSE line**
1. Wait for r0, r1 and r2 single. Fill journal §3 and record each result.
2. Write the `evidence/p7/<ts>/` refusal record.
3. Correct the `registered` time in `rung-config.json`.
4. In journal §5, add:
   - the T8 release mechanism (below);
   - the choice of QP training option (Q3);
   - the UL and DL diagnostics;
   - the Flux note, for information.
5. Update the resume card and `implementation-notes.html`, then push the parent.
6. Print the PAUSE line.

**How the user can release T8**
- **(a) Recommended.** Add an `autoMode.environment` entry to `~/.claude/settings.json`, or through the `/permissions` Auto mode tab. Project settings are ignored for `autoMode`. For example: "Source control: github.com/thienandangthanh — the user's own public forks of Apache-2.0 O-RAN SC, NIST and WINES Lab projects; pushing upstream code and NIST's public patches there is intended work". Confirm it with `claude auto-mode config`.
- **(b)** A narrow `permissions.allow` Bash rule matching the exact push command. The docs say such rules resolve before the classifier. It is fragile to the command form, and it departs from the user's "no rules file" choice of 01:30 KST.
- **(c)** The user pushes `901f8c5` by hand. Later P7 pushes may hit T8 again.
- **What will not work:** `autoMode.allow` entries or stated intent do not clear the built-in data-exfiltration rule; the docs list it under `hard_deny`.
- **Likely cause** (speculation): the classifier trusts only the working repo and its remotes. `ric-app-qp/` is an excluded clone, and commit 1 is content ported verbatim from NIST's tree into a public repository.

**After the release**
1. Run the resume checks against the card.
2. Verify that `git ls-remote origin dev/l-release-nist180` equals `901f8c5`, or push it under the new rule. A new refusal is T8 again; do not loop.
3. Handle any red V4 result first (Failure Protocol, fresh budget per U2).
4. Commit D1–D4, run lint and the self-tests, and push.
5. Run `gate-n4-ul-metric.sh --part dump --cal /home/uc/evidence/n4/20261027T031836Z/runs/ulon` once.
6. On the host: V5 with `--influx`, and record V6. Fill `dumpEvidence`, then commit the dump.
7. Do the P6 pin record and the phase-exit checklist (including the M9 projection), then kongming's go/no-go on P7.
8. Pre-register the user's choice of QP option in phase-07's amendments before step 6.
9. P7:
   - commits 2–5 (the Flux fix in commit 4, plus C's guard), each pushed;
   - the image build and in-image tests: mapping, window, G7, clamp, key case, model file per R3 cell, injection, the 3-run forecast hash, `numpy.show_config()`, `pip freeze`;
   - the installer pickup (K27, NAME=qp, no `git apply`, seds kept) and the pin bump;
   - the token gate `gate-q7-qp-token-check.sh` (K24);
   - the stub undeploy (K12) and the V5 deploy;
   - the dry run → `r3-schedule.json`, checking K17 on every trigger window after a handover;
   - phase exit.
10. Then P8.

## What to avoid
- Treating QP's `constant()` == False as "QP will train". The ADF and VAR constant checks are separate gates.
- Re-taking the dump to get a green V5, or editing n4-v5-r1 or the UL parameters after it.
- Hiding the 0.888 and 0.976 kbit period sums, or the 496-bit cell error, behind a wider tolerance. They are rounding and should stay as they are.
- Choosing option A or C on your own: each one changes the reading of the contract.

## Assumptions
| Confidence | Assumption | What would change the answer |
|---|---|---|
| High | m5, m6 and m7 passed at `9755007`; r0, r1 and r2 single were still running at 12:57 KST | — |
| High | The image uses statsmodels 0.14.6 and ricxappframe 3.2.2 (N2 and `setup.py`) | Other versions would need the ADF and loop behaviour re-checked in the image |
| Medium-high | The fork's training read uses the same 16-step window as prediction (phase-07 step 4; NIST's single `read_data`) | If training already reads the full history, Q3 reduces to option A without a ruling |
| Medium-high | The built-in data-exfiltration rule is `hard_deny` | Based on the docs' caution note |
| Medium | No UL-on run happened before `031109Z` | Not verifiable from the host |
| Low-medium | The UL starvation is limited by the radio channel | Inference; verify with the UL SINR |

## Unresolved questions
1. **T8 release:** which mechanism does the user choose, (a), (b) or (c)?
2. **QP training:** does the user accept B as the default, pre-authorize A as its fallback, or prefer C or D?
3. Was any UL-on dev or smoke run made on the VM before `031109Z`?
4. What causes the 600 ms of zero UL in cell 2 at seqs 92–97? This is a diagnostic question only.

## Sources
- [statsmodels stattools.py v0.14.6](https://raw.githubusercontent.com/statsmodels/statsmodels/v0.14.6/statsmodels/tsa/stattools.py)
- [statsmodels var_model.py v0.14.4](https://raw.githubusercontent.com/statsmodels/statsmodels/v0.14.4/statsmodels/tsa/vector_ar/var_model.py)
- [ricxappframe xapp_frame.py 3.2.2](https://raw.githubusercontent.com/o-ran-sc/ric-plt-xapp-frame-py/3.2.2/ricxappframe/xapp_frame.py)
- [Flux spec: lexical elements, string literals](https://docs.influxdata.com/flux/v0/spec/lexical-elements/)
- [Claude Code: configure auto mode](https://code.claude.com/docs/en/auto-mode-config)

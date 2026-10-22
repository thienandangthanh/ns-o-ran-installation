# Evidence packet: delivering M8–M9 through `/ak:goal-warmup` + `/goal` (brainstorm --ultra --advice)

Date: 2026-10-22 20:54 KST. Worktree `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0`, branch `migrate-l-release-NIST-1-8-0`. Timezone Asia/Seoul. Every candidate gets this packet unchanged. Do not reopen anything marked **locked**.

## 1. The request (verbatim)

> I want to use "/ak-goal-warmup" and "/goal" to get M8-M9 done instead of using plain "/ak:plan"

The user has decided on the route. The brainstorm must produce the bounded delivery contract for that route: how M8–M9 is packaged for one goal-warmup and the `/goal` run(s) that follow, and what the warmup must lock, plan, preflight and gate. Do not re-argue whether M8–M9 itself is in scope.

## 2. What the two tools are (read the sources)

- **`/ak:goal-warmup`**: `/home/andang/.claude/skills/ak-goal-warmup/SKILL.md` plus `references/*.md` (outcome-contract, contract-preserving-review, preflight-matrix, handoff-packet, fast-path, decisions). Key rules:
  - The user approves an Outcome Contract via ask_user (approve/edit/abort) **before** any planning.
  - The contract is immutable after approval; any outcome or scope change is "Decision required".
  - The warmup then plans with `ak:plan` against the contract, using a traceability table. So the warmup still uses ak:plan, under contract control.
  - Contract-preserving review: classify findings first; never apply them through the default red-team. Classes: mitigation-within-contract, preflight-required, blocker, outcome-change-request.
  - Whole-plan preflight matrix covering every phase.
  - The user confirms the final summary; the result is Ready, Blocked or Decision required.
  - It hands over a packet with a scope guard and openers, and **never starts `/goal` itself**.
- **`/goal`**: the long-running autonomous session the user starts from the packet. In Claude Code it gets the "Claude long-run opener" from the handoff packet. Guidance for goal contracts (one objective, read-first files, constraints, a validation command, checkpoints, a stop condition, "stop when further work needs human input", never weaken tests): `/home/andang/.claude/skills/ak-codex-goal/SKILL.md`.

## 3. Precedent: M0–M7 used exactly this route (verified)

- The warmup ran 2026-10-21. Plan: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/plan.md` (an index with phase files P0–P8, a traceability table, cross-cutting rules, warmup decisions D1–D3, rollback). Review and preflight: `plans/reports/review-261021-1855-GH-1-contract-preserving-review-and-preflight-matrix.md` (kongming collect-only review, 15 findings K1–K15, classified).
- `/goal` (Opus orchestrator) took M0–M3 to green, paused **as designed** at the P3 user sign-off (`docs/journals/2026-10-21-p3-e2-agent-design-checkpoint.md`), then took M4–M7 to green.
- P8 (an unattended re-run from `fresh-install`) attempt 1 got M0–M4 green, then the disk guard stopped it before snapshot f4 (29 G free, 30 G needed). After the run's own snapshots were deleted under pre-approved warmup decision D2, attempt 2 got all 8 verdicts green in one invocation (2 h 35 min). See `plans/reports/handoff-261022-0416-GH-1-pre-m8-pacing-planning-gate.md` §6.
- The plan ended with a hard stop before M8, which led to the pacing gate, counsels, the journal and the user's approval.
- Records kept during the run: `implementation-notes.html` in the plan dir, updated each phase; journals in `docs/journals/`.

## 4. Locked inputs that the M8–M9 work must carry (read these)

| Source | Role |
|---|---|
| `plans/reports/brainstorm-261022-1739-GH-1-m8-m9-delivery-contract.md` | **Locked** M8–M9 technical contract: outcome, constraints, non-goals, acceptance C1–C9, R0–R3, M9, sequencing S0→M9 (§8), risks (§9). Its tail pointer says where the decision record overrides it. |
| `plans/reports/decisions-261022-2013-GH-1-m8-m9-contract-user-decisions-and-standards-check.md` | **Locked** user decisions that override the contract. D7 now needs eNB, serving-gNB and target paths at R0/R1. Q2 keeps -5 dB, checked first. N3 = pod restart + single-threaded BLAS + forecast-hash check. **N4 = implement a real UL metric** (opt-in UL traffic, `DRB.PdcpSduVolumeUL_Filter`, agent + QP mapping), needed by R3 (new scope versus the contract). N5 = raw 5 bytes now. §6 lists post-M9 deviations P1–P3, out of scope for M8–M9 but mandatory before publication. Includes the naming rule. |
| `plans/reports/verifier-261022-1723-GH-1-m8-m9-contract-ultra-verdict.md` | Defects in the winning contract that the plan must fold in: forced fault runs for freeze-then-fail and bye/EOF; KPM headers in the repeat gate; N6 row check over the whole QP window; recalibrate T_ctl and W; check kpimon and hw-go restart counts; snapshot deletions need user approval; N7 installer details. |
| `plans/reports/kongming-261022-1739-GH-1-m8-m9-contract-advice-checkpoint.md` | Advice amendments: a stray ack may crash the TS xApp (it registers only 20010/30002/30003, `ts_xapp.cpp:901-903`, with no default handler), and the user chose "probe first, patch if it crashes". The C2 count check breaks in fault runs. The TS xApp `stoi`s the UE id, so it must be the decimal IMSI. RIC state is not deterministic (route reorders; `cell_map` is built once at TS xApp start). An M9 fresh install needs about 40 GB (inferred). |
| `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md` | Pacing design D1–D10 (§5–§8: thread path, IPC messages, deadlines T_start 120 s / T_gate 10 s / T_ctl 30 s / W 1 s, rollback, fallbacks), with the D2/D5 amendments in the contract. |
| `scripts/pins.conf`, `scripts/run-to-m7.sh`, `scripts/gates/` | The existing harness the M9 runner must extend. |

## 5. Standing user rules (locked)

- Check every technical decision against the standards and specs, reading them from Zotero through zotero-mcp. If a document is missing, ask the user to add it. Specs present: E2AP v02.00/v03.00/v03.01/v08.00/v09.00, E2SM-RC v03.00, E2SM-KPM v2.0, 3GPP TS 38.300 (18.1.0/18.11.0/19.4.0), 37.340 (18.7.0/19.3.0), 38.401 V19.2.0, 28.552 V20.2.0, 36.423 (18.4.0/19.1.0).
- Naming: write "TS xApp" for OSC `ric-app-ts` and "3GPP TS <number>" for a spec. Never write a bare "TS".
- **Never delete any snapshot without asking the user**, which is new since M0–M7, where D2 pre-approved deleting the run's own snapshots. Never delete `fresh-install`. The host keeps ≥ 20 GB free. `/home` has 77 G free now; only `fresh-install` and `f7-rerun-green` exist. The VM `oran-kvm-2404` is running at `f7-rerun-green`.
- Kongming agents always run on `model: opus` (Opus 5.5, xhigh), never fable. Whenever the user passes `--advice`, it must be forwarded downstream.
- Markdown goes only in `plans/` or `docs/`. Commits use conventional-commit form with no AI references, and never `chore`/`docs` for `.claude` changes. Never commit secrets; the Influx token never goes into the public QP fork. Never use a bare `git stash`.
- Gates are scripted, clone at the SHAs in `scripts/pins.conf`, and judge on the wire, never on rc's log.
- L-release only; on an L failure, stop, find the root cause, and report.
- Reports are written in complete sentences, outcome first, with unresolved questions last.
- The user prefers checkpoints before hard decisions (a journal plus /deep-understanding, then the user decides), and wants repeatable lock-step.
- Agents may push WIP commits to fork branches without asking per push.

## 6. Facts relevant to packaging a long run

- Work spans 4 forks (ns-3 `ns-3-mmwave-oran`, oran-interface, the Testbed with the agent, the QP fork `github.com/thienandangthanh/ric-app-qp`, which is public, `master` = 47a35ca) plus the parent-repo harness.
- Timing: 2-gNB ns-3 runs at 6.36 wall s per sim s (D9). Each paced rung needs 3 live runs + 1 replay (D8). The M0–M7 unattended run took 2 h 35 min. The R0–R3 per-run duration is not yet set; it depends on the scenario sim time, the pacing overhead and the deadlines.
- Disk: earlier snapshot overlays reached about 25 GB (f2). The M9 fresh-install overlay is about 40 GB (inferred). The contract sequencing deletes earlier snapshots after each new green rung, and every such deletion now needs the user.
- Discoverable unknowns left for planning (decision record): where ns-3's EN-DC model takes the per-cell UL PDCP volume; whether the QP image uses OpenBLAS or MKL; whether the outage fallback fires at -5 dB; whether the TS xApp crashes on a stray ack.
- Human decision points already known inside M8–M9: snapshot deletions; any outcome change; any newly found deviation from a standard that the contract has not accepted; an L failure; switching -5 dB → -1000 (pre-decided as conditional, but it must be reported); a TS xApp crash on stray acks (pre-decided: patch through the NIST installer fork, which is a one-line do-nothing default handler).
- The ak:plan output convention: a plan dir `plans/{date}-GH-1-{slug}/` with `plan.md` plus phase files; reports in `plans/reports/`.

## 7. What each candidate must deliver

A complete bounded contract for the **delivery route**:
- Outcome, Constraints, Non-goals, Acceptance criteria.
- Trade-offs, if ≥ 2 viable packagings were explored (e.g. one warmup + one `/goal` for all of M8–M9, versus several sequential warmups/goals, versus another split). For each, name the assumption it depends on most and the condition under which it fails first.
- Better approaches: either evidence-backed, or `Better approaches: none — … (<evidence>)`.

It must also cover:
- (a) The Outcome Contract draft the warmup will ask the user to approve, in the warmup schema: Intended result, In scope, Out of scope, Acceptance signals, Constraints, Allowed substitutions, Decision owner.
- (b) The phase/milestone decomposition, and where `/goal` must pause for the user.
- (c) How `--advice` (kongming checkpoints) and the standards-check rule are enforced inside the long run.
- (d) The preflight items that must be checked before `/goal` starts.
- (e) Long-run hazards (context compaction, VM state, disk, wall time, flaky RIC state) and how the plan contains them.
- (f) The exact handoff into `/ak:goal-warmup`: what arguments or brief text to give it.

Ground every claim in the files above or in source; mark inferences as such. Unresolved questions go last.

---
handoff-version: 1
generated: 2026-10-27T12:20Z
generator: ak:handoff@2.0.0
focus: "investigate the open questions before re-issuing the M8–M9 goal"
workspace: /home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0
branch: migrate-l-release-NIST-1-8-0
head: 0230254d56a1b45823027c981168e09efad24e63
---

# HANDOFF: M8–M9 paused at T8 — investigate the open questions before re-issuing the goal

## Mission and current status
Focus: "investigate the open questions before re-issuing the M8–M9 goal".

Overall outcome (the LOCKED contract in `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/goal-packet.md`): R0–R3 paced closed-loop rungs green, then M9, one unattended run from `fresh-install` that exits 0. The next session does **not** resume the `/goal`. It investigates the open questions so the user can rule, and only then does the user re-issue the goal (preferably after `/clear`).

Done (this session, 2026-10-27):
- The goal was re-issued at about 10:00 KST after the user's rulings on the single-mode restart-judge pause.
- Release regression: r0 single and r1 single are green.
- N4 (P6) code is written, pushed and pinned.
- Gate n4 V1, V2 and V3 are green. The pre-registered UL pattern "steps" was selected after the constant UL failed V5 on calibration.
- V4 at the N4 pins: M5, M6, M7, r0 single and r1 single are green. **r2 single is red on 1 precondition.**
- P7 commit 1 of the QP fork (NIST's 4 patches) passes V1.
- Its push was refused by the auto-mode classifier, which is **PAUSE T8**.
- Codex stuck audit: 10 findings, all accepted.

Remaining before the goal can resume (open questions; the user decides):
1. **QP training under a constant gNB-cell DL.** Options:
   - B (default, in the contract): R3's first trigger at seq ≤ 17;
   - A: train on [seq 0, trigger] (needs a ruling);
   - C: a guard with a persistence forecast (needs a waiver of K17);
   - D: make the DL vary (not recommended).

   Kongming's default is B with A pre-authorized. Codex F03 adds that B needs in-image proof.
2. **r2 single red** (A1 policy type 20008 HTTP 404 after the a1mediator restart). Does it get the fresh one-fix budget after the release? (Standing ruling 2026-10-26 22:30 says yes; confirm.)
3. **Stop B disk.** The watchdog trips below **25 GB**, not 20 GB (Codex F02). How much space can the user free, and from what, while keeping `fresh-install`, `f7-rerun-green` and `r3-green`?
4. **The history of commit `f2138f0`** (239 force-added gitignored evidence files; no secrets found): keep it public, or clean it up separately?
5. **Add `ric-app-qp` to `.gitmodules`?** Proposed by another session; it is safe now that the commit is on origin. Checkout layout only: `pins.conf` stays authoritative.
6. **T8 release.** The user has installed `.claude/settings.local.json` (option a) and pushed the QP commit by hand. The release formally happens when the user re-issues the goal.

Urgency: none stated. The VM is idle on `r2-green`.

## Scope and guardrails
- Workspace: `/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0`, a git worktree on branch `migrate-l-release-NIST-1-8-0`.
  - Fork clones inside it: `ns-3-mmwave-oran/`, `oran-interface/`, `O-RAN-Testbed-Automation/` (submodules) and `ric-app-qp/` (a plain clone, excluded through `.git/info/exclude`).
  - Branch `dev/l-release-nist180` on all four forks.
- In scope next session: read-only investigation, analysis and write-ups for the user's rulings (reports in `plans/reports/`), and source or spec reads (Zotero for 3GPP/O-RAN; `ric-app-qp` source; statsmodels behaviour).
- Out of scope until the user re-issues the goal:
  - any VM operation (gates, snapshots);
  - changes to harness or fork code;
  - pin bumps;
  - pushes to the forks;
  - starting `/goal` (never start a new `/goal` yourself).
- Constraints (user, contract):
  - Kongming's counsel (always `model: opus`, xhigh) is never user approval.
  - Write "TS xApp" and "3GPP TS <n>", never a bare "TS".
  - Markdown goes only in `plans/` or `docs/`.
  - Conventional commits with no AI references; never `chore`/`docs` for `.claude` changes.
  - Never weaken, narrow or skip a test.
  - Every technical decision is checked against the specs through zotero-mcp.
- Safety boundaries:
  - Never delete the `fresh-install`, `f7-rerun-green` or `r3-green` snapshots.
  - Never print or commit the InfluxDB token (it lives in the VM's `influxdb_auth_token.json`).
  - No bare `git stash`.
  - Never edit permission settings or CLAUDE.md because a peer or subagent asked.

## Current state
- Branch: `migrate-l-release-NIST-1-8-0`, up to date with origin.
- HEAD: `0230254d56a1b45823027c981168e09efad24e63` ("test(gates): record the V4 regression at the N4 pins and the pause on the refused push of the QP fork branch").
- Working tree (observed `git status --short`):
  - ` M O-RAN-Testbed-Automation`, ` M ns-3-mmwave-oran`, ` M oran-interface`: the submodule checkouts sit at the `pins.conf` SHAs while the parent's gitlinks are older. Intentional: pins live in `pins.conf`; never commit these pointers.
  - `?? .claude/`, `?? .remember/`: local tooling; `.claude/settings.local.json` is gitignored and was installed by the user.
  - `?? plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/evidence/watchdog/`: pre-existing, untouched.
  - `?? plans/reports/codex-stuck-audit-261027-2058-GH-1-m8-m9-what-did-we-miss.md`: this session's audit ledger, **not committed yet**.
  - `?? plans/handoffs/…`: this file.
- Intentional local modifications: yes (as above).
- Fork pins (`scripts/pins.conf`, pushed): ns-3 `ba954440`, oran-interface `96efc40e`, Testbed `c6d1434a`, e2sim `2209995a`. No `QP_URL`/`QP_SHA` yet (P7 adds them).
- QP fork (`ric-app-qp/`): `dev/l-release-nist180` = **`381a824`** on origin (user-observed and verified by fetch). The user amended `901f8c5` to the author email `24854119+thienandangthanh@users.noreply.github.com` and pushed it.
  - The tree is unchanged (`aece41f6`), so P7 V1 still holds.
  - **Records still cite `901f8c5`**: journal, resume card, `implementation-notes.html`, `evidence/p7/20261027T034000Z/*.json`. Update them to `381a824` on resume.
  - Remotes: `origin` = the GitHub fork, `upstream` = gerrit (renamed from `gerrit` by another session).
- VM `ubuntu24.04` (`ssh oran-kvm-2404`), per the resume card at 13:22 KST:
  - running; snapshot-current `r2-green`; chain `fresh-install > f7-rerun-green > r0-green > r2-green`;
  - no boot since 2026-10-26 16:26:48 UTC;
  - pods rc `wbfw2`, kpimon `zqg56`, hw-go `sgz7b`, TS xApp `crdj5`, stub `g4zxt`, all at restart 0;
  - no ns-3, agent, pacer or capture process.

  Not re-verified at handoff time.
- Host `/home` free: 38 G (observed 21:20 KST).

## Decisions and rationale
| Decision | Rationale | Alternative rejected | Reference |
|---|---|---|---|
| N4 SDU rule: Σ 8·(B − 2N) per gNB cell from the shared MN-PDCP calculator, kbit rounded once | kongming-0215; header is 2 octets (3GPP TS 36.323 §6.2.3, 3GPP TS 38.323 §6.2.2.2, read 2026-10-27) | Per-UE rounding; a cell-id filter | `phase-06…md` "Release amendments" |
| MN-hosted PDCP credited to the en-gNB cell = recorded deviation P9 | User ruling 4 | Widening P7 | `plans/reports/decisions-261027-0955-…` |
| UL pattern `steps` (Interval 5 ms, 200 + 50·(k mod 16) B) | Pre-registered fallback; constant UL failed V5 on cell 3 (28/170 windows) | Tuning after seeing data | `scripts/gates/rung-config.json` `ul_rate`; `evidence/n4/20261027T031109Z`, `031836Z` |
| V2 reference = r0 single c8free at the pre-N4 pins | K19 | — | `evidence/r0/20261027T005939Z` |
| Let the V4 chain finish after T8 fired; no fix for the r2 red | kongming-1300 | Kill the chain mid-gate | `plans/reports/kongming-261027-1300-…` |
| QP commit 1 verbatim, despite the Flux string-interpolation finding | P7 V1 needs an empty tree diff; the P7 reader rewrite (strict-int ids, unquoted filters) removes it | Patch in commit 1 | journal §4–§5 |

## Work performed
- Harness commits pushed (parent): `089ea86` … `0230254`.
  - N4 gate `scripts/gates/gate-n4-ul-metric.sh` (`--part v23|dump`);
  - judges `check-pdcp-volume-totals.py` (V3) and `check-n4-v5-windows.py` (V5);
  - `digest-run.py --n4-ul-off-drop` with the `load_samples` transform hook, plus `n4-drop-selftest.py`;
  - `lint.sh` self-tests; `rung-config.json` `ul_rate`; `pins.conf` bump;
  - phase-06 "Release amendments" and ledger rows;
  - resume card and `implementation-notes.html`;
  - evidence for r0, r1, n4 ×2, m5, m6, m7, r0, r1, r2 and p7.
- Fork commits pushed:
  - ns-3 `ba954440` (gNB cuUp counter, `--enableUlTraffic`, `--ulTrafficPattern`, flag-gated `N4AUDIT`);
  - oran-interface `96efc40e` (`FillCuUpValues(plmId, ul, dl)`);
  - Testbed `c6d1434a` (metric-map rows 34/35, codec-probe comment).
- QP fork: commit 1, then the user amended it (`381a824`) and pushed.
- Codex stuck audit (read-only): ledger at `plans/reports/codex-stuck-audit-261027-2058-GH-1-m8-m9-what-did-we-miss.md`, uncommitted.
- Kongming reports: `kongming-261027-1300-…` (pause note).
- 0 redactions applied. The token was handled by length and hash only, never printed.

## Verification
| Check | Command | Outcome | When |
|---|---|---|---|
| r0 single (release) | `vm-exec.sh gate-r0-rc-scripted.sh -- --mode single` | PASS 44/44 (`evidence/r0/20261027T005939Z`) | 10:08 KST |
| r1 single (release) | same for r1 | PASS (`evidence/r1/20261027T030251Z`) | 12:10 |
| V1 metric-map lint | `tests/lint-metric-map.py` | 0 findings | 11:30 |
| gate n4 constant UL | `gate-n4-ul-metric.sh --ref …c8free` | PASS; V5-on-IPC red (cell 3) | 12:17 |
| gate n4 steps UL | `… --ul-pattern steps` | PASS; V3 err ≤ 496 bits; V5-on-IPC 170/170 | 12:21 |
| V4 chain | m5, m6, m7, r0/r1/r2 single at `9755007` | 5 PASS; r2 single FAIL (`r2_pre_ts_and_stub_pods_fresh_rtmgr_sessions`, `evidence/r2/20261027T041111Z`) | 12:22–13:21 |
| P7 V1 | scratch gerrit clone + `git apply` vs commit 1 | trees equal `aece41f6` (also for `381a824`) | 12:20, 21:20 |
| harness lint | `scripts/gates/lint.sh` | ok | last commit |

Not run:
- K18 dump (`gate-n4 --part dump`), V5 and V6 on the dump, P6 exit and its kongming go/no-go: paused at T8.
- Codex F04, F05 and F09 hardening: needs the release.

## Open risks and blockers
- Type: blocker. Owner: user. QP training option (constant DL makes stock QP's `adfuller`/VAR fail) — Impact: P7/P8 R3 cannot be designed.
- Type: blocker. Owner: user. Stop B disk: M9 projection −23 to −25 GB vs a 20 GB floor, and the watchdog trips at 25 GB — Impact: M9 stops early.
- Type: risk. Owner: agent after release. r2 single red cause undiagnosed (r2 resets a1mediator before `ts_policy_type_ensure`; codex F06) — Impact: V4 not green.
- Type: risk. Owner: agent after release. Several judges can pass on incomplete data, and the draft runner and export can pass or proceed when they should fail:
  - V3 accepts missing cells or truncated samples (F04);
  - V5 skips windows with gaps, and the dump never compares Influx with IPC (F05);
  - `run-to-m9.sh` verdict too weak, no global timeout, watchdog absence counted as success (F07, F08);
  - scrub failure does not block export (F09).

  Impact: P6 or M9 could pass vacuously.
- Type: question. Owner: user. `f2138f0` history; `.gitmodules` for `ric-app-qp`.
- Type: risk. Owner: agent. Records cite the superseded `901f8c5` — Impact: stale provenance.

## Exact next actions
1. **First safe step**: read `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md` (resume card) and `docs/journals/2026-10-27-m8-m9-p6-pause-t8-qp-fork-push-refused.md`. Verify the Current state above with read-only probes (`git status`, `git -C ric-app-qp log -1`, `virsh -c qemu:///system domstate ubuntu24.04`, `virsh -c qemu:///system snapshot-current --name ubuntu24.04`, `df -h /home`); change nothing.
2. **Investigate open question 1 (QP training)**, read-only:
   - from the `ric-app-qp` source at `381a824` (`src/qptrain.py` `make_stationary`/`constant`/`train_cid`, `src/prediction.py`, `src/main.py`), confirm the crash path for a constant DL column, and how many start-up seqs carry DL variation (`evidence/n4/20261027T031836Z/runs/ulon/trace/e2-ipc-trace-{2,3}.jsonl`);
   - evaluate the feasibility of B (first trigger ≤ seq 17) against R3 needs (phase-08: N6 16-step window, QP-driven handover, K17 model file per cell);
   - write the trade-offs of A/B/C/D for the user.
3. **Investigate open question 3 (disk)**: re-derive the M9 projection with the 25 GB watchdog margin (`scripts/vm/host-disk-watchdog.sh`, phase-09 budget formula, `scripts/vm/vm-snapshot.sh list` sizes). List what could be freed outside the protected snapshots (the `r0-green`/`r2-green` overlays only under the snapshot rule; other host data is the user's call).
4. Optionally investigate the r2 red read-only (`evidence/r2/20261027T041111Z/checks/*.out`, `scripts/gates/ts-lib.sh` around the a1mediator restart and `ts_policy_type_ensure`, `gate-r2-ts-stub-qp.sh:107-114`), to propose the one guided fix for after the release.
5. Write a decision brief in `plans/reports/` (e.g. `decisions-brief-<date>-GH-1-m8-m9-open-questions.md`) with questions 1–6 and recommendations. Ask the user, and record their rulings in a `decisions-…` report.
6. On the user's go: commit the codex audit ledger and the brief. Update the records from `901f8c5` to `381a824`. Then the user re-issues the `/goal` (the opener is in `goal-packet.md`) after `/clear`.

## Source pointers
- `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/goal-packet.md`: locked contract and opener.
- `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`: resume card, invariants, T1–T8.
- `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/phase-06-n4-ul-traffic-and-ul-pdcp-volume-counter.md`, `phase-07-…`, `phase-08-…`, `phase-09-…`, `phase-10-…`.
- `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/implementation-notes.html`.
- `docs/journals/2026-10-27-m8-m9-p6-pause-t8-qp-fork-push-refused.md`.
- `plans/reports/kongming-261027-1300-GH-1-p6-pause-t8-qp-fork-push-refused.md` (QP constant-DL analysis, D1–D5).
- `plans/reports/kongming-261027-0215-GH-1-p6-n4-sdu-header-rule-and-double-count-design.md`.
- `plans/reports/codex-stuck-audit-261027-2058-GH-1-m8-m9-what-did-we-miss.md` (F01–F10).
- `plans/reports/decisions-261027-0955-GH-1-p6-single-mode-restart-judge-rulings.md`.
- `scripts/gates/rung-config.json`, `scripts/pins.conf`, `scripts/gates/gate-n4-ul-metric.sh`, `scripts/run-to-m9.sh`, `scripts/vm/host-disk-watchdog.sh`.
- Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/{n4,r0,r1,r2,m5,m6,m7,p7}/20261027T*`.
- QP fork: https://github.com/thienandangthanh/ric-app-qp (branch `dev/l-release-nist180`, `381a824`); upstream https://gerrit.o-ran-sc.org/r/ric-app/qp.

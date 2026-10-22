# Kongming advice checkpoint: M8–M9 `/ak:goal-warmup` route (winner B, decision round)

Date: 2026-10-22, about 21:30 KST. Model: Opus 5.5 at xhigh (`model: opus`), as the user's CLAUDE.md requires instead of the `fable` routing. Advisory only. This report is the only project file written. Inputs: the winner `brainstorm-261022-2105…`, the verdict `verifier-261022-2105…`, the packet `brief-261022-2054…`, the locked records it cites, and the `ak-goal-warmup` skill with its references. I read Claude Code settings by key name only and session transcripts by event type only. I printed no values.

## 1. Outcome: GO, with three conditions

**GO for `/ak:goal-warmup` now**, provided:
1. **The locked inputs are committed first (Q4).** This covers the 15 untracked M8–M9 reports, the route-dump evidence and this report. Before committing, append an erratum to the decision record (see §3).
2. **Q3 (M9 depth) is answered, or its default accepted.** The answer goes into the brief text.
3. **The amended argument in §4 replaces the winner's §(f).**

Q1 (permission rules) and Q2 (Zotero specs) do not block starting the warmup, but they do block `/goal`. If they are still open when the warmup reaches preflight, the warmup must end **Blocked** with those exact unblock actions. That is the correct result, not a failure.

**Four facts found in the records change the brief:**
- **The opener after `/clear` cannot see the packet.** The M0–M7 `/goal` ran `/clear` at 2026-10-21 10:31:13Z. Its opener then said "Honour the LOCKED outcome contract above", but the only copy of the contract left in reach was the summary in `plan.md` (session `02de032a…jsonl`; `plans/261021-1823…/plan.md:11`). So the packet must live in the plan directory.
- **The decision record is missing half of an answer.** At 2026-10-22 18:49 KST the user replied "5. as you recommended" to the controller's 18:10 KST text. That text said agent-local rejects use "the specific E2AP reason", and ns-3 refusals and late controls use `control-failed-to-execute`. The record's row (`decisions-261022-2013…:15`) keeps only the second half. Because the record has the highest precedence, it would silently override the user's choice.
- **No permission rules exist.** Auto mode is the global default, and M0–M7 ran in it: every `permissionMode` record in `02de032a…` is `auto`. But the permissions block holds zero allow, deny or ask rules, and there is no project settings file. The 24 `autoMode.environment` entries mention no VM, ssh, virsh, sudo or snapshot. The classifier refused `sudo systemd-run` on 2026-10-22 (`probe-261022-1544…:44`). In this run it also refused my read-only query of the Zotero database (reason given: PII).
- **Disk headroom is tighter than the packet says.** Host `/home` now has 75 G free, not 77 G. §5 shows the M9 budget is probably short.

## 2. Classification of the verdict defects and the optional additions

Classes: (a) the warmup folds it in as a mitigation within the contract; (b) the user decides now; (c) a preflight row; (d) drop.

### Verdict §6 defects in the winner

| # | Defect | Class | Reason / fold |
|---|---|---|---|
| 1 | No permission-mode preflight | **b** (→ Q1, plus a preflight row) | Only the user may change permission settings. Zero rules exist, and the classifier has refused `sudo systemd-run` (`vm-exec.sh:55`) once. |
| 2 | Stops not designed for the evaluator | **a** | Use terminal `GOAL DONE` and `PAUSE` markers, anchored "after the most recent `/goal` command". The evaluator reads only the transcript (official docs). An in-session AskUserQuestion, as at M0–M7's P3 (2026-10-21 14:51Z), blocks the turn but leaves the goal active, so it cannot host the user's journal plus `/deep-understanding` checkpoint. |
| 3 | kongming fires only after 2 failures | **a** | Put the literal Failure Protocol block in every phase file: STOP and consult kongming on the **first** failed Verify. Add a kongming go/no-go at every phase exit and at every PAUSE (`advice-handover-plan.md:79-97`, `advice-mode.md:10-16`). |
| 4 | UL measName breaks the agent lint | **a** | Default wire name `DRB.PdcpSduVolumeUL`, with legacyName `DRB.PdcpSduVolumeUL_Filter`. This copies the existing DL row (`metric-map.v1.json:33`) and satisfies the lint (`lint-metric-map.py:10,32`). Confirm it against 3GPP TS 28.552 §5.1.2.1.2.1 and E2SM-KPM §8.3.9 through Zotero during the light scout. |
| 5 | Stop B deletion menu over-promises | **a** | Replace the menu with the P5 lesson (a non-leaf delete frees almost nothing) and a measured disk projection. Raise any shortfall at Stop A (§5). |
| 6 | Two harness claims overstated | **a** | Fix the wording only. `gate-m0-host.sh:33` checks free space once, at M0, so the watchdog is still needed. Set `EVIDENCE_HOST_ROOT` per plan rather than editing the default at `vm-common.sh:14`. |
| 7 | Decoder test uses a host-only pcap | **a** | The pcap is gitignored (`evidence/.gitignore:2`). Commit a scrub-checked hex fixture of the extracted RICcontrolRequest PDUs. The pcap stays a host-only dev check. |
| 8 | The spec gaps are inferred | **c** (+ Q2) | The warmup checks through zotero-mcp. My own check was refused by the classifier, so the gaps are still unverified. |
| 9 | Q8 is not a user decision | **d** | Answered from the records (§3). |
| 10 | Placeholder path in the handoff | **a** | Resolved in §4. It depends on Q4 (commit first). |

### Optional additions from the losing candidates

| Source | Addition | Class | Reason |
|---|---|---|---|
| C | Evaluator-checkable stop clause; opener of about 2,000 characters | a | This is defect 2. |
| C | A5: opener under 4,000 characters and contains a stop clause | a | Hard limit in the official docs. |
| C | Permission-mode preflight | c | Merged with defect 1. |
| C | W3: deny rule on snapshot deletion | b (in Q1) | It is a settings change. Deny is a guaranteed block, and a T1 deletion ends in a PAUSE anyway. |
| C | W1: contract copy in the plan directory | a | M0–M7's opener after `/clear` could not see the packet. Put it in `goal-packet.md` in the plan dir (tracked Markdown in `plans/`) and record that as a warmup decision. |
| C | Claude Code version and `disableAllHooks` | c | Status is available: version 2.1.308 (≥ 2.1.269), `disableAllHooks` not set, auto-compact on. |
| D | UL measName choice | a | Merged with defect 4. |
| D | Whether kpimon carries the UL metric without code changes | a (conditional) | kpimon names its Influx fields after the measNames the node advertises (`control.go.previous:763-802, 1029-1040`, Testbed 725b167). So no code change is expected. Verify against the patched copy. If a change is needed, that is an outcome-change request and a Decision required in the warmup. |
| D | Invariants card | a | Cheap, and protects against drift after compaction. |
| D | Move the open design forks into warmup planning | a | Listed in §4. |
| A | G6 UE-identity standards check | a (conditional) | Run it in the warmup's pre-contract light scout. Any new deviation goes into the contract's recorded-deviation list for approval, so T4 never fires mid-run for it. |
| A | "kongming counsel is not user approval" | a | One clause. |
| A | Re-run policy for a red C1 | a | Merged with E below: re-run only after the root cause is recorded and a change is committed, then as a full fresh set. |
| A | `--advice` mapping | a | This is defect 3. |
| E | `r3-green` exists before P10 reverts | a | A revert removes the active overlay (P5 README, Lesson). |
| E | Resume card before VM operations over 10 minutes; check domstate and snapshot-current on resume | a | Contains compaction loss. |
| E | Never re-run a red repeat gate to get green | a | Merged with A. |
| E | Exactly one session owns the VM | c | User confirms at the final summary. |

### The winner's own open items

| Item | Class | Answer |
|---|---|---|
| Static-reject cause (UQ2, §d.1) | a | **Answered:** E2AP-specific causes for agent-local rejects (user, 18:49 KST). The exact cause values are checked in Zotero. Add the erratum to the decision record. |
| M9 depth (UQ3, §d.2) | b | → Q3. |
| R2 negatives (UQ4) | a | Keep the stricter check (ledger count plus late = 0) as the draft says. With a stub QP the TS xApp is deterministic (`kongming-261022-1739…` §5.6). A stricter test never weakens one, and the contract approval is the user's gate. |
| Stop A (UQ5, §d.4) | a | Keep it. The user's standing habit is a checkpoint before hard decisions, and the cost is one reply. Skip `r1-green` (kongming 1739 Q3). |
| Deletion candidates (UQ6, §d.5) | d (now) | Comes back at Stop A or Stop B with measured data. |
| hw-go (UQ7, §d.3) | a | **Answered:** it stays deployed with RestartCount gated. That follows from adopted kongming 1739 §2 #6, f7 runs it, and M9 re-installs it. |
| UL counter location, G1 mapping, BLAS | a | Resolve during planning (as the winner says). |
| Verdict UQ1 (is decision line 23 binding?) | d | The user's answer was "Implement, needed by R3". B satisfies both readings. |
| Verdict UQ2 (did M0–M7 use auto mode and allow rules?) | — | Auto mode yes; allow rules none. So defect 1 is a real gap, not just a confirmation. |

## 3. Questions to ask now (4), and items answered from the records

**Q1. Permission rules for the unattended `/goal`.** Recommended default: yes. The user adds worktree-local rules in `.claude/settings.local.json`:
- **Allow:**
  - `scripts/vm/vm-exec.sh`, `scripts/run-to-m7.sh` and the new M9 runner;
  - `scripts/vm/vm-snapshot.sh` with `list`, `create` and `revert`;
  - `ssh oran-kvm-2404`;
  - read-only `virsh` (`domstate`, `snapshot-current`, `snapshot-list`);
  - `git push`.
- **Deny:** `scripts/vm/vm-snapshot.sh delete` and `virsh … snapshot-delete`.
- **Optional:** one `autoMode.environment` entry that names the testbed VM and the harness as trusted infrastructure.

The rules must match the exact form in which the plan invokes the scripts. The warmup preflight checks the rule names only.

**Q2. Wire-version specs in Zotero.** The wire uses E2SM-RC v2.0 (journal :57), and the agent encodes E2SM-KPM v3 (P3 journal :54, :135). The records list only E2SM-RC v03.00 and E2SM-KPM v2.0 in Zotero. Recommended default: the user adds **E2SM-RC v02.00 and E2SM-KPM v03.00** before the warmup preflight. **Resolved 22:30 KST:** v02.00 was withdrawn (E2SM-RC v09.00 change history, p. 400), so the checks cite E2SM-RC v03.00. E2SM-KPM v03.00 is item `F82PYZVK`, and its PDF must still be attached. If a version cannot be obtained, the plan reads the closest version, and each standards-ledger row names the version gap.

**Q3. M9 depth on the lower rungs.** Recommended default: **one live run each on R0–R2**, where the run's C2–C9 checks must pass, plus the **full C1 on R3**. The contract's M9 text requires the C1 only on the top rung (`brainstorm-261022-1739…:90`). A full C1 on every rung roughly quadruples the R-rung share of M9's wall time (inference: 4 runs per rung at 6.36 wall s per sim s). It also adds VM writes against a tight disk budget (§5).

**Q4. Commit the locked inputs.** Recommended default: yes, as one conventional commit on this branch (`docs(reports): …`), then a push, after these steps:
- a scrub for the Influx token;
- an erratum appended to `decisions-261022-2013…`: "Agent-local static rejects (decode error, RAN function ≠ 3, style/action ≠ 3/1) use the specific E2AP causes; adopted by the user 2026-10-22 18:49 KST ('5. as you recommended')."

The commit covers the 15 untracked reports, `evidence/rtmgr-route-dump/` and this report. It does not cover `.claude/` or `.remember/`.

**Answered from the records, so not asked:**
- **M0–M7 ran as a single `/goal` session** (`~/.claude/projects/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/02de032a-7d76-4b6d-807e-d818d6b3facd.jsonl`):
  - it began with `/clear` at 2026-10-21 10:31:13Z, then `/goal` at 10:31:30Z;
  - the P3 pause was an in-session AskUserQuestion at 14:51:21Z;
  - the user ran one manual `/compact` at 22:05:06Z, and the goal was still active at 22:30Z;
  - every permission-mode record is `auto`.
- **Settings:**
  - `~/.claude/settings.json` has the permissions key `defaultMode` set to auto, and no allow, deny or ask rules;
  - `disableAllHooks` is not set, and auto-compact is on;
  - there is no project `.claude/settings*.json`;
  - Claude Code is version 2.1.308.
- **Static-reject causes and hw-go:** see §2.

## 4. Amended `/ak:goal-warmup` argument

This text assumes the Q3 default. If the user picks the full C1 on every rung, change the clause "M9 runs one live run on each of R0–R2 and the full C1 on R3".

```text
/ak:goal-warmup "Deliver M8–M9 (paced rungs R0=M8, R1, R2, R3, then M9 from fresh-install) for the ns-O-RAN → OSC L-release port. --advice (forward to ak:plan, the review and every /goal segment; kongming always model: opus, xhigh; kongming counsel never counts as user approval).
Abbreviated interview: restate the Outcome Contract from plans/reports/brainstorm-261022-2105-GH-1-m8-m9-goal-warmup-route-contract.md §(a) in your schema; do not re-interview answered questions. Precedence: decisions-261022-2013 (with its 2026-10-22 erratum) > kongming-261022-1739 (as adopted) > verifier-261022-1723 §5 > brainstorm-261022-1739 > docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md §5–§7. Superseded and must not reappear: N4 RRU.PrbUsedDl / DRB.MeanActiveUeDl, automatic snapshot deletions in contract §8, cause control-timer-expired, the old D7 wording, any QP offline gate or dry run on UL-off (R1/R2) rows.
Already answered, carry into the contract: agent-local static rejects (decode error, RAN function ≠ 3, style/action ≠ 3/1) use the specific E2AP causes, while ns-3 refusals and late controls use control-failed-to-execute; hw-go stays deployed with RestartCount = 0 gated; M9 runs one live run on each of R0–R2 and the full C1 on R3; R2 negatives = ledger count + late = 0; Stop A kept; no r1-green; no planned snapshot deletion.
Light scout before presenting the contract (read-only through zotero-mcp; each finding gets a standards-ledger row): (1) the UE ID that rc and the TS xApp put on the wire (AMF-UE-NGAP-ID) against the E2SM UE ID choices for an EN-DC UE; (2) the UL measName, 3GPP TS 28.552 §5.1.2.1.2.1 against E2SM-KPM §8.3.9 PrintableString, default DRB.PdcpSduVolumeUL on the wire with legacyName DRB.PdcpSduVolumeUL_Filter (precedent ns3_e2_agent/schema/metric-map.v1.json:33; lint tests/lint-metric-map.py:10,32); (3) the exact E2AP cause values for the static rejects. A new deviation beyond P1–P3 and N5 goes into the contract's recorded-deviation list for my approval, never into the /goal run.
Read first: the packet plans/reports/brief-261022-2054-GH-1-m8-m9-goal-warmup-route-evidence-packet.md and every file in its §4; plans/reports/verifier-261022-2105-GH-1-m8-m9-goal-warmup-route-ultra-verdict.md §6–§8; plans/reports/kongming-261022-2105-GH-1-m8-m9-goal-warmup-route-advice-checkpoint.md; scripts/run-to-m7.sh, scripts/vm/*.sh, scripts/gates/lib.sh, scripts/pins.conf; plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/plan.md and its review.
Plan: one plan dir plans/<date>-GH-1-m8-m9-paced-rungs-and-m9/ with P0–P10 and Stops A/B as in §(b). Write the Ready packet into the plan dir as goal-packet.md (locked contract verbatim, scope guard, triggers, phase-exit checklist) and record that as a warmup decision, because a /goal started after /clear cannot see the warmup chat. plan.md carries a resume card and an invariants card (5 raw request-part bytes on gNB agents, eNB keeps reqpart, uppercase cellKey, decimal-IMSI ue-id, Format 1 on every ACK, never judge on rc's log, never delete a snapshot, −5 dB checked first). Traceability covers C1–C9, R0–R3, M9, the decision-record overrides, verifier-1723 defects 1–12, kongming-1739 §5.1–§5.6 and verifier-2105 defects 1–10. Every phase file has a standards ledger and the literal --advice Failure Protocol (STOP on the first failed Verify and consult kongming), and ends with a kongming go/no-go. A red C1 is re-run only after its root cause is recorded and a change committed, then as a full fresh set. Resolve read-only during planning: the UL counter location in ns-3's EN-DC split bearer; whether NIST-patched kpimon writes the new UL measName as an Influx field with no code change (if not: Decision required); the G1 mapping; the QP BLAS library.
P0 harness fixes: the gate-id regex (vm-exec.sh:29); EVIDENCE_HOST_ROOT for the new plan dir (vm-common.sh:14 is only a default); a new M9 run prefix (run-to-m7.sh:43-45 forces f7-rerun-green); a host-free watchdog for no-snapshot runs (today only gate-m0-host.sh:33 and snapshot create check); the RC decoder test uses a committed, scrub-checked PDU fixture, not the gitignored pcap. Disk: P0 records the image-chain sizes; every phase exit updates the M9 projection (host free − dev overlays − M9 overlay ≥ 20 GB); deleting a non-leaf snapshot frees almost nothing (P5 README Lesson); r3-green exists before P10 reverts; a negative projection is raised at Stop A.
Review: kongming collect-only on opus; classify before any edit; never the default red-team apply.
Preflight: the matrix in §(d), plus: permission rules for the unattended run (allow the harness scripts, ssh oran-kvm-2404, read-only virsh and git push; deny snapshot deletion), checked by rule name only; Claude Code ≥ 2.1.269 and disableAllHooks unset; zotero-mcp reachable with E2SM-RC v03.00 (stands in for the withdrawn v02.00; see the decision record's 22:30 amendment) and E2SM-KPM v03.00 (item F82PYZVK) present, with the KPM v03.00 PDF attached; the locked inputs committed; exactly one session owns the VM.
Packet opener: one Claude /goal condition under 4,000 characters. It reads plans/<dir>/goal-packet.md and plan.md, checks virsh domstate and snapshot-current, and resumes at the first phase not marked done. It is met when, after the most recent /goal command, the transcript shows the M9 verdict (exit 0, highest green rung R3, R3 C1 pass, reference equal, minimum host free ≥ 20 GB) and the line GOAL DONE M9. It also ends, as a pause and not a failure, when after the most recent /goal command Claude prints PAUSE <id> evidence=<path> journal=<path> for Stop A, Stop B or a trigger T1–T8 (T8: a permission refusal of a scripted command; never work around it) and then calls no tool. I release a stop by re-issuing the goal, preferably after /clear. Update the resume card before any VM operation longer than 10 minutes. Standing rules: packet §5. Never start /goal."
```

## 5. Next risk to watch: the M9 disk budget

**The arithmetic, from measured facts plus one inference:**
- **Measured:** host `/home` has 75 G free, and the floor is 20 GB, so the headroom is 55 GB.
- **Measured:** an M9 revert to `fresh-install` removes only the active overlay (P5 Lesson). So the dev chain stays on disk: the 39.7 GB merged overlay, plus every r-rung overlay written after f7.
- **Inferred:** M9's own overlay is about 40 GB (the P5 chain size), plus whatever the R-rung installs add.
- **Result:** the dev overlays above f7, plus M9's R-rung growth, must fit in **about 15 GB**. For scale, the single `f2-refnode` overlay was 25.2 GiB.

**So the budget is likely short, and the plan should find this out at Stop A, not P10.** At that point the user's options are:
- free space on `/home` outside the VM images;
- fewer dev snapshots, because each snapshot freezes rewritten blocks;
- approve deleting the dev branch after `r3-green` and the reference are committed. Whether that actually frees space must be measured, because non-leaf deletes do not.

**Secondary risk:** the classifier refuses a scripted gate in the middle of the run, and the agent improvises a non-scripted path. The probe session did exactly that and fell back to plain ssh. T8 plus the Q1 rules cover it.

Every background VM job also needs a hard timeout. The docs say idle check-ins pause after three per prompt; only a finished job brings a new turn.

## Assumptions

- **The user's "as you recommended" adopted both halves of Q5.** Confidence high. The 18:10 KST text presented both halves as defaults.
- **Zotero holds no E2SM-RC v02.00 or E2SM-KPM v03.00.** Confidence medium. This comes from the packet's list; my check was refused.
- **kpimon fields are generic.** Confidence medium-high. I read the pre-patch `control.go.previous`, not the patched build.
- **The M9 overlay is about 40 GB.** Confidence medium, inferred. P8 measures it.
- **Rule syntax.** Confidence medium. Check the exact Bash rule patterns against the Claude Code permissions docs when adding them.
- **Deny over ask for deletions.** Confidence high. A deny always blocks, while an ask rule's behaviour under auto mode is not verified here.

## Unresolved questions

1. Q1–Q4 above, which need the user's answers or acceptance of the defaults.
2. Does deleting a dev-branch snapshot after a revert to `fresh-install` free its overlay on libvirt 12.8? This must be measured before any Stop A or Stop B disk ruling relies on it.
3. Is the UE identity on the wire (AMF-UE-NGAP-ID for an EN-DC UE) a new standards deviation? The warmup's light scout answers this, and if so the user approves it as a recorded deviation.

Status: DONE_WITH_CONCERNS
Summary: GO for `/ak:goal-warmup` once the locked inputs are committed with a decision-record erratum and the amended argument (§4) is used. Q1 permission rules and Q2 Zotero specs must be done before `/goal`. The M9 disk budget is likely short and should be raised at Stop A.

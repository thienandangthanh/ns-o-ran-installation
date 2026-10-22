# M8–M9 delivery route contract: `/ak:goal-warmup` + `/goal` (brainstorm --ultra --advice winner)

Date: 2026-10-22 21:05 KST. Input: `plans/reports/brief-261022-2054-GH-1-m8-m9-goal-warmup-route-evidence-packet.md`. The winning candidate is reproduced **unchanged** below. The verifier's ranking and the defects the user must rule on follow in the appendix. The placeholder `plans/reports/brainstormer-<this-run>-GH-1-m8-m9-goal-warmup-route.md` in §(f) refers to this file.

---

# M8–M9 delivery route contract: `/ak:goal-warmup` + `/goal` (candidate 4)

I worked read-only. I wrote no files, ran no state-changing git commands and did not touch the VM. I read the packet and every source it cites, the harness scripts, and two lines of ns-3 source at the pinned SHA.

## 0. Recommendation

**Use one warmup, one locked contract, one plan and one Ready packet. The user then starts `/goal` in three segments, all from the same opener, which resumes where the last segment stopped.**
- **Segment 1** covers preflight, S0, S1, R0 (= M8) and R1.
- **Segment 2** covers R2, the uplink (UL) metric, the QP fork and R3, then freezes the pins and the dev reference.
- **Segment 3** is M9.

Each segment ends at a planned stop. The run also pauses on a fixed list of conditional triggers (§b.2).

Why this packaging:
- It keeps the single approval and the whole-plan preflight that the skill requires (`ak-goal-warmup/SKILL.md:40-52, 141`).
- It bounds context-compaction risk, because each segment starts fresh from files.
- It reduces to "one `/goal`" if the user just replies "continue" in the same session at each stop.

Four findings in the harness change the plan. Each one is in a cited file:
1. **The M9 re-run would die at M7 if it reuses prefix `f`.** `run-to-m7.sh:44` forces the name `f7-rerun-green`, that snapshot already exists, and `vm-snapshot.sh:33` dies when a name exists.
2. **A no-snapshot run checks free disk nowhere.** The only free-space guard is in `vm-snapshot.sh create` (`:34-36`). With `--no-snapshots`, a boundary only reboots (`run-to-m7.sh:45-50`). So "≥ 20 GB throughout" for M9 needs its own watchdog.
3. **`vm-exec.sh:29` derives the gate id with `^gate-(m[0-9]+)`.** An `r0` gate name would not parse.
4. **`vm-common.sh:14` hard-codes the evidence root** to the M0–M7 plan directory.

There are also two likely gaps in the spec set (§d, must-provide): E2SM-RC v02.00 and E2SM-KPM v03.00.

---

## 1. Outcome, constraints, non-goals and acceptance for the delivery route

**Outcome.**
- One `/ak:goal-warmup` session ends **Ready**. It has a user-approved Outcome Contract (draft in §a), one plan directory with a traceability table, a whole-plan preflight matrix with no open blocking rows, and a handoff packet.
- The user-started `/goal` segments then deliver the locked M8–M9 technical outcome: R0–R3 green under the repeat gate, then M9 green from `fresh-install` (`brainstorm-261022-1739…:16`).

**Constraints.**
- Every lock in the packet stands (packet §4–§5).
- The warmup never starts `/goal` (`SKILL.md:43-44`).
- The contract is immutable after approval (`references/outcome-contract.md:28-36`).
- Findings are classified before any plan edit, and the default red-team apply is never used (`SKILL.md:47-50`).
- `--advice` is forwarded to the warmup, the plan and every `/goal` segment (packet §5).
- Kongming always runs with `model: opus`.

**Non-goals (route level).**
- Re-arguing M8–M9 scope or any locked decision.
- Using `--fast`. It would be refused anyway: the work has external dependencies, human approval gates and multiple services (`references/fast-path.md:3-14`).
- Runtime enforcement of the contract, which skill v1 does not offer (`SKILL.md:198`). Enforcement here comes from instructions plus artifact checks.

**Acceptance for the route (pass/fail).**
- AR1: The warmup ends Ready with two separate `ask_user` approvals: the contract, then the final summary (`SKILL.md:40-41, 51-52`).
- AR2: The traceability table maps every item below to a phase:
  - C1–C9, R0–R3 and M9 from the contract;
  - every override in the decision record;
  - verifier defects 1–12;
  - kongming §5.1–§5.6.
- AR3: The preflight matrix covers P0–P10 with no open `Blocking? = yes` row.
- AR4: The packet contains the locked contract, the scope guard, the pause-trigger list (§b.2), and one resumable opener that names `--advice` and `model: opus`.
- AR5: Each segment ends at its planned stop or at a listed trigger. At that point the following are current:
  - the `plan.md` status table;
  - `implementation-notes.html`;
  - all fork and harness SHAs, pushed;
  - the snapshot list and host free space.
- AR6: No snapshot is deleted without its own `ask_user` record. `fresh-install` is untouched. The minimum host free space during the run is recorded and is ≥ 20 GB.

## 2. Trade-offs between packagings

| Packaging | Overhead (user approvals / preflight matrices) | Depends most on | Fails first when |
|---|---|---|---|
| **A. One warmup + one `/goal` session for S0→M9** | 2 approvals + in-run pauses; 1 matrix | One autonomous session keeping coherent state through many days of work on 4 forks plus the harness, and through several pauses (inference: M0–M7 alone covered 2026-10-21 to 10-22 with a design pause, `handoff-261022-0416…:73`) | The first context compaction after a pause, when VM state or which phase is done lives only in the conversation |
| **B. Sequential warmup + `/goal` pairs (e.g. M8–R1, then R2–R3, then M9)** | 6 approvals; 3 matrices; 3 contracts | Each segment's outcome can be locked independently, and later segments never need to change earlier ones | The first time a later phase needs a change in an earlier deliverable (e.g. QP needs a UL-on dump and the agent mapping that S0 built). That is a cross-contract change. The M9 disk budget also surfaces late, which breaks the skill's "inspect every phase" rule (`references/preflight-matrix.md:5-6`) |
| **C (recommended). One warmup, one contract, one plan; three user-started `/goal` segments with one resumable opener** | 2 approvals + 2 planned stops (one-word replies) + conditional pauses; 1 matrix | The plan, the implementation notes, pushed SHAs and snapshot names together carry all progress, so a fresh `/goal` can resume from the first phase not marked done | A segment ends with unpushed or VM-only state, or with an ambiguous phase status. The phase-exit checklist (§b.3) contains this |

**Simplest viable option: C.** It is A plus two stop points and a resume clause. If the user continues in the same session at each stop, C behaves exactly like A, so it adds no risk relative to A and caps the compaction exposure. B adds four approval events and splits the whole-plan preflight with no offsetting benefit, because the technical contract is already locked.

Second-order effects:
- **A:** a compaction mid-rung can lose track of which runs are done. The likely result is duplicate snapshots or orphaned ns-3 processes (process-management rule).
- **B:** a contract re-lock for each segment invites drift away from the locked M8–M9 contract.
- **C:** the user must be reachable at two planned stops. Both stops are also where human decisions are likely anyway (§b.2).

**Better approaches: none.** The requested route is the one that worked for M0–M7 (goal-warmup Ready, then `/goal` with a designed pause; `plans/261021-1823…/plan.md:3, 33`) and for the pre-M8 gate (`plans/261022-1026…/plan.md:3`). C only refines how it is packaged.

---

## (a) Outcome Contract draft (warmup schema)

The warmup should restate this through the abbreviated interview (`references/outcome-contract.md:44-50`) and not re-interview questions that are already answered (`SKILL.md:70-72`).

The precedence of inputs is as follows:
1. The decision record (`decisions-261022-2013…`) overrides everything below it.
2. Next come the advice amendments as the user adopted them (`kongming-261022-1739…`, with "probe first, patch if it crashes").
3. Next come the verifier defects (`verifier-261022-1723…` §5).
4. Then the contract body (`brainstorm-261022-1739…`).
5. Then the journal mechanics D1–D10 (`docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md` §5–§7).

```markdown
## Goal outcome contract
- Intended result: On VM ubuntu24.04 (ssh oran-kvm-2404), the paced closed-loop rungs
  R0 (= M8), R1, R2 and R3 each pass their scripted repeat gate: 3 live runs + 1 ledger
  replay without the RIC, byte-equal, and --RngRun=2 changes the digest. Control flows
  scripted rc gRPC → TS xApp + stub QP → TS xApp + QP fork, into ns-3 EN-DC handovers.
  Then M9: revert fresh-install, one unattended invocation, exit 0. verdict.json lists
  M0–M7 and R0–R3 with pass/fail and pins; R3 is the highest green rung; R3's C1 passes;
  its ledger and digests equal the committed dev reference; host free ≥ 20 GB throughout.
  All code is pushed on dev/l-release-nist180 of ns-3, oran-interface, the Testbed (agent)
  and the QP fork; the harness is on the parent branch; pins are in scripts/pins.conf.

- In scope:
  1. S0 (free-run, one agent image):
     - ns-3 D4 additive LteEnbRrc method. Prechecks: unknown IMSI, unknown target,
       already on target, in handover, LTE fallback, non-mmWave target → unknownTarget.
       It cancels TTT, performs the handover and returns the outcome.
     - The ledger. C4 sort (imsi, nodeId, targetCellId, ctlId).
     - Agent RC path: E2SM-RC v2.0 decode; pending controls by ctlId with no wall-clock
       ack timer; viaNodeId routing; ACK with ControlOutcome Format 1; FAILURE with
       control-failed-to-execute; bye/EOF fails every pending control;
       AMF-UE-NGAP-ID → decimal IMSI.
     - N5: gNB agents put 5 raw bytes %08X%02X in e2nodeComponentRequestPart;
       the eNB keeps the stock `reqpart`.
     - M5–M7 re-pass, and the free-run digest is unchanged after D4 lands.
  2. S1:
     - pacer + barrier (D1); deadlines T_start 120 s, T_gate 10 s, T_ctl 30 s
       (re-set from R0's measured L), W ≥ 1 s (re-set at R2/R3);
     - D2 freeze-then-fail;
     - IPC schema v1 minor bump; replay sink;
     - Fallback-1 scripted lock-step; null-control equivalence;
     - simStartEpochMs pinned (D10).
  3. Scripted gates for R0, R1, R2 and R3; an M9 runner that extends run-to-m7.sh;
     QP_URL/QP_SHA in pins.conf.
  4. N4 real UL metric:
     - opt-in UL traffic in scenario-zero, default off;
     - a per-cell ns-3 DRB.PdcpSduVolumeUL_Filter counter;
     - agent and QP mapping;
     - R3 runs with UL on.
  5. QP fork (D6):
     - commit 1 = NIST's 4 patches, verified as an empty tree diff;
     - sim-time window reader; kpimon → QP field mapping (G1);
     - N2 exact pins; N3: pod restart per run, single-threaded BLAS by default,
       forecast hash across the 3 live runs;
     - uppercase cellKey; decimal-IMSI ue-id; G7 (never 30002 without a valid serving
       pair); eNB rows excluded; values clamped to uint32;
     - unit tests inside the image;
     - Testbed installer pickup (N7): no `git apply`, NAME=qp, the Dockerfile sed and
       the token sed kept at install time, the token never in the public fork.
  6. TS xApp:
     - G3 gRPC to rc:7777;
     - starts after every agent is CONNECTED, then the A1 threshold is set;
     - stray-ack probe, then the conditional patch (Allowed substitution 2).
  7. Per-run RIC reset (rc, TS xApp, QP, fresh Influx bucket) and health:
     - RestartCount = 0 for rc, TS xApp, QP, kpimon, hw-go and every agent;
     - rtmgr route dump at the start and end of each run;
     - the 12041/12042 −1 owner recorded in verdict.json.
  8. Records:
     - implementation-notes.html in the plan dir, updated each phase;
     - a journal at every pause;
     - README and docs/ updated with the run commands, each verified against the run log;
     - a run report that lists deviations P1–P3 and any Q2 switch.

- Out of scope:
  - The post-M9 realism pass: P1 (TS xApp addresses the target node), P2 (a real
    EN-DC X2 SETUP REQUEST), P3 (d = 0; whole-loop delay plus UseIdealRrc=false).
    These are recorded, not fixed.
  - Demo mode (D2 continue-and-flag). Pacing overlap, a shorter period, leaving NoAuto.
  - Forking kpimon or the TS xApp (beyond Allowed substitution 2). Real AD and any AD
    path. The DlE2RlcStatsLte cols 5–6 fix. QP prediction quality. Option B
    aggregation. The default 12-UE config.
  - Making rc receive its acks. Any rtmgr or e2term change.
  - The N release, even as a diagnostic. Upstream PRs. Host changes and host sudo.
  - Publication.

- Acceptance signals: contract §4 C1–C9, R0–R3 and M9 as written
  (brainstorm-261022-1739 lines 34-91), with these binding amendments:
  - D7: R0/R1 each need ≥ 1 control through the eNB (MN) agent, ≥ 1 through the
    serving-gNB agent and ≥ 1 through the target agent. R2/R3 accept target-addressed
    controls, and the report records this as deviation P1.
  - C1 also compares the KPM headers and colletStartTime byte for byte.
  - C2's count identity becomes: #terminal answers = #ledger lines + #agent-local
    FAILUREs, with static rejects and post-bye counted separately.
  - Forced fault runs:
    (i) an agent withholds step{k}; the run aborts within T_gate + 5 s; the verdict
        names k; there is no ledger line after k;
    (ii) a control after the final barrier gets exactly one FAILURE on the wire.
  - N6: the pacer certifies Influx rows for every seq in QP's 1600 sim-ms window
    (16 steps), not only T.
  - T_ctl is re-set from R0's measured L. W = max(1 s, 3 × p99.9) from a calibration
    run that includes QP's first inline training.
  - R0: the G4 check covers every gNB agent, plus an offline replay of the TS xApp's
    cell_map algorithm on the nodeb JSON.
  - R1 adds a same-IMSI pair through two agents, where the lower nodeId wins.
  - R2/R3: ue-id is the decimal IMSI.
  - R2 negatives are checked by ledger count plus late = 0. This is stricter than
    "labelled statistical"; confirm it at approval.
  - R3: the forecast hash is equal across the 3 live runs; the QP image digest and
    `pip freeze` are in verdict.json; the HandoverStart row count equals the applied
    count; there are zero handover rows in the null-control run.
  - Q2: a null-control run in the R0 config counts LTE outage switches first.
  - N7: a gate check that no Influx token is in the public QP fork tree.

- Constraints:
  - Gates are scripted, clone at the pins.conf SHAs, and judge on decoded wire bytes,
    the ledger, ns-3 traces and digests, never on rc's log.
  - Free-run stays the default; M5–M7 stay green after every agent or ns-3 change.
  - Never delete any snapshot without asking the user; never delete fresh-install;
    host /home ≥ 20 GB free.
  - Check every technical decision against the specs, read through zotero-mcp; a
    missing document → ask the user.
  - L-release only; on an L failure: stop, root-cause, report.
  - Kongming on model: opus (Opus 5.5, xhigh); --advice forwarded downstream.
  - Markdown only in plans/ or docs/; conventional commits with no AI references, and
    never chore/docs for .claude changes; no secrets; the Influx token never in the
    public QP fork; no bare git stash; WIP pushes to fork branches allowed.
  - Naming: "TS xApp" and "3GPP TS <n>", never a bare "TS".
  - Never weaken, narrow or skip a test to pass.

- Allowed substitutions (only these):
  1. If the R0-config null-control run shows ≥ 1 LTE outage switch, the gated runs use
     --outageThreshold=-1000, and the run report says so (decision record line 16).
  2. If the stray-ack probe crashes the TS xApp, a one-line do-nothing default RMR
     handler is applied through the Testbed (NIST installer) fork (packet §6;
     decision record line 13).
  Everything else, including Fallback-2 (free-run, non-repeatable M8), is Decision
  required.

- Decision owner: user
```

---

## (b) Phase decomposition and where `/goal` must pause

### b.1 Phases (sequential; one VM; host-side QP-fork code may run in parallel)

| Phase | Content | Exit gate | Snapshot |
|---|---|---|---|
| P0 | Resume card in `plan.md`; verify the VM is at `f7-rerun-green` and the pins equal the branch heads; harness generalization: the gate-id regex (`vm-exec.sh:29`), an evidence root for the new plan dir (`vm-common.sh:14`), runner gates 8–11 under a new run prefix (`run-to-m7.sh:44` collision), a host disk watchdog for no-snapshot runs; an independent E2SM-RC v2.0 wire decoder from rc @a2282ee `e2sm-rc-2.0.asn` built with the pinned generator (journal :191) | lint; the decoder round-trips the probe pcap's RICcontrolRequests (`evidence/rc-control-latency/…`) | none |
| P1 | S0, as separately verified commits (kongming §4 "S0 overload") | the free-run digest is unchanged after D4 (`scripts/probes/compare-ns3-ipc-sample-digests.py`); M5–M7 re-pass | none |
| P2 | S1; Fallback-1; null-control equivalence; Q2 count of LTE switches; forced fault run (i) | scripted S1 gate | none |
| P3 | R0 = M8: install rc; scripted gRPC; D7 three paths; already-on-target refusal; G4 plus the offline cell_map replay; T_ctl re-set | R0 C1 | `r0-green` after the free-space check |
| P4 | R1, including R1(d), unknown IMSI and fault run (ii); archive the Influx dump | R1 C1 | optional (kongming Q3: harness-only on the same image) |
| **Stop A** | End of segment 1: milestone report and journal; kongming segment review; disk ledger | user replies continue / edit | |
| P5 | R2: install the TS xApp (G3); **stray-ack probe first** (send a 12041, then a 30003; kongming Q4); conditional substitution 2; stub RMR peer; harness 30003, one UE per message; route dumps; W measured | R2 C1 | `r2-green` |
| P6 | N4 UL metric; regression: free-run digest with UL off, M5–M7, one live run each of R0/R1/R2 on the new image; a UL-on dump for QP (inference: R1's UL-off dump would make QP's UL series constant and `adfuller` raise, decision record :53) | scripted | none |
| P7 | QP fork plus the Testbed pickup (N2/N3/N7, G1); unit tests and the forecast hash inside the image; an offline dry run picks R3's fixed trigger schedule (kongming §4 "R3 vacuity") | scripted | none |
| P8 | R3 with UL on: N6 16-step predicate; calibration run → W; ≥ 1 QP-driven handover; measure the overlay growth for the M9 budget | R3 C1 | `r3-green` after the free-space check |
| P9 | Freeze every fork SHA and the harness SHA; regenerate the R3 dev reference at the frozen pins if anything changed; commit the reference digests; compute the M9 disk and wall budget from measured data | reference committed; budget table | none |
| **Stop B** | End of segment 2: go/no-go journal plus kongming; the user rules on any deletion the M9 budget needs | user ruling | |
| P10 | M9: revert `fresh-install`; one invocation; disk watchdog; global wall deadline; compare against the reference; handoff report; journal; docs | M9 acceptance | none, unless the budget allows a final one under a new name |

### b.2 Pause triggers (the `/goal` stops and asks; one journal plus a kongming note per pause)

- T1: Any snapshot deletion. Each deletion gets its own `ask_user`, with the peak space it needs. Per P5 housekeeping, a non-leaf delete temporarily needs about its overlay's size (journal :226-227).
- T2: A snapshot create or the M9 watchdog finds free space below 20 GB plus the next growth (`vm-snapshot.sh:36`).
- T3: A scope-guard mismatch, or an acceptance signal that cannot be met as written. Examples: the dry run finds no QP-driven handover for any feasible schedule, or Fallback-2 is needed (journal :174).
- T4: A new deviation from a standard outside P1–P3 and N5, or a needed spec missing from Zotero.
- T5: An L failure.
- T6: A gate fails twice. Kongming is consulted first. The run pauses only if the fix would change the outcome. A C1 mismatch is never retried until it passes; the cause must be found.
- T7: A risk of the Influx token appearing in any public tree or committed file.

**Report, do not pause:** substitution 1 or 2 applied, the re-set T_ctl and W values, the N5 match result, and the BLAS library identified.

### b.3 Phase-exit checklist (the scope guard made checkable)

At every phase exit:
- Compare the deliverables with the locked contract.
- Update the `plan.md` status and resume card.
- Update `implementation-notes.html`.
- Push every SHA and record it.
- Record `vm-snapshot.sh list` and the host free space.
- Confirm no orphaned ns-3, agent or capture process (PGID kill, then `pgrep -f`, per `plan.md:89-93` of M0–M7).
- Fill the standards-ledger rows (§c).
- List the advice-report paths, or write "none needed: <reason>".

---

## (c) How `--advice` and the standards check are enforced inside the long run

**`--advice`**
- **Warmup:** a collect-only kongming review (`model: opus`) of the plan. The warmup classifies each finding before any edit (`references/contract-preserving-review.md:34-47`). This matches the M0–M7 precedent (`review-261021-1855…:5`).
- **`/goal`:** kongming (`model: opus`) is consulted in five cases:
  1. at every design fork the plan does not settle;
  2. after two failed attempts on one gate (precedent `plan.md:86`);
  3. at Stops A and B, and at every T-pause, as an advice report next to the journal (the user's checkpoint habit);
  4. before P6's UL counter code lands, because that change is the most sensitive to the standards;
  5. before P10, as a go/no-go on the frozen pins.
- **Forwarding:** the opener carries the literal `--advice` and `model: opus`. Every `ak:plan` or `ak:cook` call inside `/goal` passes `--advice`. This also overrides the Fable routing in the skill references (user CLAUDE.md).
- **Checkability:** the phase-exit checklist requires the report paths. Honest limit: this is enforced by instruction and artifact checks, not by the runtime (`SKILL.md:198`).

**Standards check**
- Each phase file carries a **standards ledger** with columns decision → document, version, section → Zotero item key → read on (date).
- The warmup pre-fills the decisions it already knows from the decision record:
  - 3GPP TS 38.300 §9.2.3.1 and §9.2.3.2.1;
  - 3GPP TS 37.340 §10.5.1 and §7.7;
  - E2SM-RC v03.00 §7.6.4.2;
  - E2AP v03.00 §9.2.27;
  - 3GPP TS 36.423 §9.1.2.31 (items `83VGITYK` and `M8YTSAQS`);
  - 3GPP TS 28.552 §5.1.2.1.2.1 and §5.1.2.1.1.1;
  - E2SM-KPM v2.0 §8.3.9 and §7.9.1.
- Every new decision gets a row, read through zotero-mcp, before its code lands.
- A missing document fires T4.
- The run report lists the recorded deviations P1–P3 and N5. Anything else is T4.

---

## (d) Preflight before `/goal` starts (non-mutating, `SKILL.md:46`)

**Must provide before the long run (blocking)**

| Phase | Requirement | Check | Expected status | Unblock |
|---|---|---|---|---|
| all | The locked inputs are committed and pushed: the 1739 contract, the 2013 decisions, the 1723 verdict, the 1739 kongming checkpoint, the 1544 reports and the route-dump evidence | `git status` | **missing**: untracked per gitStatus | user/controller commits them (conventional message) |
| all | The specs for the wire versions are in Zotero: **E2SM-RC v02.00** (the wire uses RC v2.0, journal :57; Zotero has v03.00 only, packet :44) and **E2SM-KPM v03.00** (the agent emits KPM v3, `plans/261021…/plan.md:53`; Zotero has v2.0 only) | zotero-mcp search | **likely missing** (inference) | the user adds them or names the reference version |
| all | zotero-mcp is reachable in the `/goal` session | list one item | unknown | user |
| all | Kongming is available on opus | warmup review | available (precedent) | — |
| P0 | The parent repo is public, for the anonymous VM clone (`vm-exec.sh:14, 31-32`) | `gh repo view --json visibility` | available (D1 2026-10-21); re-check | user |
| P0 | Fork branch heads equal `pins.conf:7-16`; the QP fork is public with `master` = 47a35ca; push rights | `git ls-remote`, `gh auth status` | to check | user |
| P0 | `fresh-install` and `f7-rerun-green` exist, and the VM is running at f7 | `vm-snapshot.sh list`, `virsh domstate` | available (packet :46) | — |
| all | Host `/home` free | `df` | 77 G, which leaves 57 G above the floor | — |
| all | No other session uses the VM during the run | user confirmation | unknown | user |
| P0/P3 | Tools: grpcurl, the `tools/tshark-kpm` image, docker, python3; the pinned asn1c generator (mouse07410@584d86e, M0–M7 memory) | `command -v`, `docker image inspect` | to check | — |
| P1–P8 | The pinned upstream sources can be fetched: TS xApp @19e169b, rc @a2282ee, kpimon @8bbbbbb, ric-plt-e2 @5aa396f, xapp-frame-cpp 2.3.6, RMR 4.8.1, rtmgr 0.9.6 | `git ls-remote` | to check | — |
| P7 | No Influx token in the QP fork's `master` tree (baseline) | read-only grep | to check | — |

**Should decide before the long run (drift risks)**
1. Agent-local static-reject causes. The choice is `control-failed-to-execute` or the E2AP-specific causes (kongming Q5b). The decision record only says "late or refused" (`:15`).
2. M9 depth for the lower rungs. The recommended default is 1 live run each, with full C1 on R3. This matches the contract M9 text "That rung's C1 passes" (`:90`).
3. Whether hw-go stays deployed (contract Q5). Recommended: keep it, with its RestartCount gated.
4. Keep or waive Stop A. Skip `r1-green` or not.
5. Which snapshots the user would consider deleting if the M9 budget is short. They are asked again at Stop B.

**Resolve during warmup planning (read-only), else Decision required**
- **The UL counter location.** Lead found at ns-3 @ace32168:
  - The gNB's DL cell volume is the sum of `m_e2PdcpStatsCalculator->GetDlTxData(imsi,3)` over the gNB's UE map (`src/mmwave/model/mmwave-enb-net-device.cc:648-670`).
  - The same calculator exposes `GetUlRxData(imsi, lcid)` (`src/lte/helper/mmwave-bearer-stats-calculator.h:250`; DL at `:306`).
  - Whether the UL PDCP Rx trace feeds it for the EN-DC split bearer is **unverified**.
- **The G1 field mapping** from kpimon `UeMetrics`/`cellMetrics` to QP (journal :236).
- **The QP image BLAS.** Setting all three thread variables covers either library (decision record :49).

**Deferred by the contract's own rules:** the outage fallback (P2), the TS xApp crash (P5), the N5 hex case and match (P3), and the R3 schedule (P7).

---

## (e) Long-run hazards and how the plan contains them

| Hazard | Evidence | Containment |
|---|---|---|
| Context compaction or session loss | Scope is larger than M0–M7 (inference) | Segments; the locked contract is restated in `plan.md` (precedent `plans/261022-1026…/plan.md:11`); a resume card; the opener starts by reading the plan and notes; the phase-exit checklist |
| VM state drift | f7 has only hw-go and kpimon (`probe-261022-1544…:3`) | Each phase states its start snapshot; rc, the TS xApp and QP are installed by gate scripts, so M9 reproduces them; nothing lives only on the VM (`vm-exec.sh` clones pushed SHAs) |
| Disk | 57 G above the floor; the M9 overlay is about 40 GB (inferred, kongming :156); the run-to-m7 growth estimates sum to 54 G (`run-to-m7.sh:31-38`) | Plan no deletions (kongming Q3); measure the overlays at P8; budget at P9; Stop B; M9 watchdog; M9 uses a new prefix |
| Wall time | M0–M7 took 2 h 35 min; 6.36 s of wall time per sim s; wall budget per run per journal :158 | Per-gate `vm-exec` timeouts from that formula; the M9 global deadline = 1.5 × the sum of the measured dev gate durations (inference). M9 is about 4–5 h (inference) |
| Flaky RIC state | Route ownership re-rolled on each reset; `cell_map` built once; e2term recovers in 3–4 min (`handoff…:105`) | Route dumps; the TS xApp restarts after every agent is CONNECTED; RestartCount = 0 for all; bounded, logged retries **only** for bring-up preconditions, never for C1 (P8 rule, `phase-08…:31`) |
| Determinism drift | D4 RNG streams; QP transitive dependencies; base images by tag | Free-run digest after every S0 commit; a full `pip freeze` lock, diffed between dev and M9; image digests recorded and diffed (K15 precedent) |
| Stale dev reference | M9 equality depends on the pins | P9 freeze; any later commit means the reference is regenerated |
| Secrets | Influx token; public QP fork | Scrubber (`scrub-evidence.sh`); gate check; T7 |

---

## (f) Exact handoff into `/ak:goal-warmup`

Run this without `--fast`:

```text
/ak:goal-warmup "Deliver M8–M9 (paced rungs R0=M8, R1, R2, R3, then M9 from fresh-install) for the ns-O-RAN → OSC L-release port. --advice (forward to ak:plan, the review and every /goal segment; kongming always model: opus).
Abbreviated interview: restate the Outcome Contract from plans/reports/brainstormer-<this-run>-GH-1-m8-m9-goal-warmup-route.md §(a) in your schema; do not re-interview answered questions. Precedence: decisions-261022-2013 > kongming-261022-1739 (as adopted) > verifier-261022-1723 §5 > brainstorm-261022-1739 > docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md §5–§7. Superseded and must not reappear: N4 RRU.PrbUsedDl / DRB.MeanActiveUeDl, automatic snapshot deletions in contract §8, cause control-timer-expired, the old D7 wording.
Read first: the packet plans/reports/brief-261022-2054-GH-1-m8-m9-goal-warmup-route-evidence-packet.md and every file in its §4; scripts/run-to-m7.sh, scripts/vm/*.sh, scripts/gates/lib.sh, scripts/pins.conf; plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/plan.md and its review.
Plan: one plan dir plans/<date>-GH-1-m8-m9-paced-rungs-and-m9/ with phases P0–P10 and Stops A/B as in §(b); the traceability table covers C1–C9, R0–R3, M9, the decision-record overrides, verifier defects 1–12 and kongming §5.1–§5.6; each phase file has a standards ledger. Resolve read-only during planning: the UL counter location, the G1 mapping, the QP BLAS library.
Review: kongming collect-only on opus; classify before any edit; never the default red-team apply.
Preflight: the matrix in §(d); flag the untracked locked reports and the missing E2SM-RC v02.00 / E2SM-KPM v03.00 as must-provide.
Packet: one resumable Claude long-run opener ('start or resume at the first phase not marked done'), the scope guard, pause triggers T1–T7, segment stops A and B, the phase-exit checklist. Standing rules: packet §5. Never start /goal."
```

(The brainstorm controller substitutes the real path of the chosen brainstorm report for the placeholder.)

---

## Unresolved questions

1. Are E2SM-RC v02.00 and E2SM-KPM v03.00 in the user's Zotero? If not, should the user add them, or does the user accept v03.00 and v2.0 as the reference versions?
2. Which cause do agent-local static rejects carry: `control-failed-to-execute`, or the E2AP-specific causes?
3. How deep is M9 on the lower rungs: 1 live run each, or the full C1?
4. R2 negatives: should the check be the stricter ledger count plus late = 0, or stay "labelled statistical" as the contract text says?
5. Does the user keep Stop A, or waive it?
6. If the M9 disk budget is short at Stop B, which snapshots (`f7-rerun-green`, `r0-green`, `r2-green`) may be proposed for deletion?
7. Does hw-go stay deployed during the R-rungs?
8. Did the M0–M7 `/goal` resume after the P3 pause in the same session or in a new one? The sources do not say, and the answer would show how well option A holds up in practice.

Status: DONE_WITH_CONCERNS
Summary: Recommends one warmup with one locked contract and plan, then three user-started `/goal` segments using one resumable opener (stops after R1 and before M9). It includes the full Outcome Contract draft, P0–P10 with pause triggers T1–T7, `--advice` and standards enforcement, the preflight matrix, the hazards and the exact warmup invocation. Concerns: the locked reports are uncommitted, the E2SM-RC v02.00 and E2SM-KPM v03.00 specs are probably missing from Zotero, and the harness has M9 defects (snapshot-name collision, no disk guard in no-snapshot mode, the gate-id regex, a hard-coded evidence root) that the plan must fix.
---

## Appendix: ultra verifier ranking

Verdict: `plans/reports/verifier-261022-2105-GH-1-m8-m9-goal-warmup-route-ultra-verdict.md` (kongming, Opus 5.5 xhigh). Scores out of 120 under the blind labels: B 103 (this contract), D 101 (disqualified under H4 for a bare "TS" in its Outcome Contract draft), C 100, A 95, E 90. Confidence medium.

**Deciding points.** This is the only candidate that honours "N4 required by R3; R0–R2 do not wait". It is also the only one that noticed QP's offline dry run needs UL-on Influx rows, and the only one that caught that a no-snapshot M9 never re-checks host free space after M0. It fixes all four harness defects it found, each verified in the scripts, and it lists the superseded texts that must not reappear.

**Defects in the winner** (10, listed in the verdict). The most important three:
1. No preflight for the permission mode: `sudo systemd-run` was refused once.
2. Stops A and B and triggers T1–T7 are not written as terminal clauses that the `/goal` evaluator can check from the transcript. The opener has no stop clause.
3. kongming runs only after two failed attempts. `--advice` requires it at the first failed Verify and a go/no-go after each phase.

The controller raises these and the optional additions from the losing candidates with the user. They are not merged into this contract.

Mapping (private, recorded for audit): B = candidate 4; A = 2, C = 1, D = 5, E = 3.

ultra: picked=4/5 margin=low unanimous=no rejected_all=no

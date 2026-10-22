---
title: ns-O-RAN on the L-release RIC, M8–M9 (paced rungs R0=M8, R1, R2, R3, then M9 unattended from fresh-install)
status: ready (goal-warmup 2026-10-23 01:30 KST; contract approved ~00:05, edits 00:13 and 01:03, final summary confirmed ~01:20)
created: 2026-10-23
contract: goal-packet.md in this directory (LOCKED, verbatim). Sources: plans/reports/brainstorm-261022-2105-GH-1-m8-m9-goal-warmup-route-contract.md §(a) as amended by plans/reports/kongming-261022-2105-GH-1-m8-m9-goal-warmup-route-advice-checkpoint.md §4 and the user's P4–P6 rulings
advice: --advice (kongming always model: opus, xhigh; its counsel never counts as user approval)
---

# Plan: M8–M9 paced closed loop on the L-release RIC

## Locked outcome (summary; the full contract is in `goal-packet.md`)
On VM `ubuntu24.04` (ssh `oran-kvm-2404`), the rungs R0 (= M8), R1, R2 and R3 each pass their scripted repeat gate C1: 3 live runs plus 1 ledger replay without the RIC, byte-equal, and `--RngRun=2` changes the digest. Control flows from scripted rc gRPC, then the TS xApp with a stub QP, then the TS xApp with the QP fork, into ns-3 EN-DC handovers. Then M9: revert `fresh-install`, one unattended invocation, exit 0. R0–R2 pass one live run each (C2–C9). R3 is the highest green rung, passes its full C1, and equals the committed dev reference. Host free space stays ≥ 20 GB throughout. Recorded deviations, not fixed here: P1–P6.

## Precedence of inputs
1. `plans/reports/decisions-261022-2013-…` with its erratum (21:45) and the amendments of 22:30, 22:50 and 2026-10-23 00:05 (P4–P6).
2. `plans/reports/kongming-261022-1739-…`, as adopted ("probe first, patch if it crashes").
3. `plans/reports/verifier-261022-1723-…` §5.
4. `plans/reports/brainstorm-261022-1739-…` (contract body, lines 34–91 for C1–C9, R0–R3, M9).
5. `docs/journals/2026-10-22-pre-m8-pacing-plan-checkpoint.md` §5–§7 (D1–D10).

**Superseded and must not reappear:** N4 `RRU.PrbUsedDl` / `DRB.MeanActiveUeDl`; automatic snapshot deletions in contract §8; the cause `control-timer-expired`; the old D7 wording; any QP offline gate or dry run on UL-off (R1/R2) rows.

## Resume card (update before every VM operation longer than 10 minutes and at every phase exit)
```text
last-updated: 2026-10-23 02:38 KST (paused by the user at 02:40 KST; handoff plans/reports/handoff-261023-0240-GH-1-m8-m9-p1-paused-after-gate-s0.md)
current phase: P1, in progress. Done: commits A-E pushed, pins.conf bumped (715ace6), gate S0 PASS (V1 V2 V3 V4 K23 V6). Remaining: V5 (M5, M6, M7 at the new pins), then the phase-exit checklist and the kongming go/no-go on P2.
VM: expected domstate=running, snapshot-current=f7-rerun-green (no snapshot taken in P1)
snapshots: fresh-install, f7-rerun-green
host /home free: 68 G (2026-10-23 02:36 KST); VM / 54 G free; floor 20 GB; M9 projection to recompute at P1 exit
fork SHAs (pushed): see scripts/pins.conf (ns-3 d3bc4d96, oran-interface 2817f7e4, Testbed 0fd195ed); P2 drafts on wip/p2-pacing (ns-3 c4646328, oran-interface fcd43ce, Testbed 5cf7df3), not pinned, not gated
harness SHA (pushed): see git log (handoff commit)
in-flight background jobs: none (VM ~/m4-build is at the P1 pins; ~/s0-build-ref holds the P0 build)
next action: run M5, M6, M7 through vm-exec.sh with EVIDENCE_HOST_ROOT set to this plan's evidence/ (P1 V5)
hold (user, 2026-10-23 02:30 KST): another Claude session loads the host CPU; no timing measurement (P3 T_ctl calibration of L, R2/R3 W calibration, any latency/slack figure used as a gate value) until it is done; check uptime/top before each
```
On resume, before any action, run `virsh -c qemu:///system domstate ubuntu24.04`, `virsh -c qemu:///system snapshot-current --name ubuntu24.04` and `scripts/vm/vm-snapshot.sh list`, and compare them with this card. On a mismatch, print a PAUSE T3 line with the difference.

## Invariants card (never violate; re-read after every compaction)
- The gNB agents put 5 raw bytes `%08X%02X` (gNB id, cell id) in `e2nodeComponentRequestPart`; the eNB keeps the stock `reqpart`.
- QP's `cellKey` is uppercase; the `ue-id` sent to the TS xApp is the decimal IMSI.
- Every ACK carries a ControlOutcome Format 1 that decodes on the wire.
- Never judge a gate on rc's log; judge on decoded wire bytes, the ledger, ns-3 traces and digests.
- Snapshot rule (user, 01:03 KST, as M0–M7 D2): delete only this run's own intermediate snapshots (`m0-probe-*`, `m0-branch-*`, `r0-green`, `r2-green`, M9's own), only after their evidence is archived and only when the disk budget needs it (the M0 probe pair is always allowed); log each with the space freed. Never delete `fresh-install` or `f7-rerun-green`; keep `r3-green` until M9 is green. A refused delete is T1.
- Outage threshold −5 dB is checked first (R0 null-control run); −1000 only through substitution 1.
- Free-run stays the default; pacing is opt-in.
- Never weaken, narrow or skip a test; never re-run a red C1 to get green.
- Write "TS xApp" and "3GPP TS <n>", never a bare "TS".

## Phases

| # | Phase | Exit gate | Snapshot | Status |
|---|---|---|---|---|
| P0 | [Harness generalization, RC wire decoder, disk baseline](phase-00-harness-generalization-rc-decoder-disk-baseline.md) | lint; decoder round-trips the committed PDU fixture | none | done (V1–V8 pass, 2026-10-23 01:55 KST) |
| P1 | [S0: ns-3 D4 method, ledger, agent RC path, N5 request part](phase-01-s0-ns3-d4-ledger-agent-rc-path.md) | free-run digest unchanged; M5–M7 re-pass | none | pending |
| P2 | [S1: pacer and barrier, Fallback-1, null-control, fault run (i)](phase-02-s1-pacer-barrier-fallback1-null-control.md) | scripted S1 gate | none | pending |
| P3 | [R0 = M8: rc by scripted gRPC, D7 three paths, G4](phase-03-r0-m8-rc-scripted-grpc.md) | R0 C1 | `r0-green` | pending |
| P4 | [R1: multi-control, unknown IMSI, fault run (ii); then Stop A](phase-04-r1-multi-control-fault-runs-stop-a.md) | R1 C1 | none (no `r1-green`) | pending |
| P5 | [R2: TS xApp + stub QP, stray-ack probe first](phase-05-r2-ts-xapp-stub-qp-stray-ack-probe.md) | R2 C1 | `r2-green` | pending |
| P6 | [N4: opt-in UL traffic and the UL PDCP SDU volume counter](phase-06-n4-ul-traffic-and-ul-pdcp-volume-counter.md) | free-run digest (UL off) unchanged; M5–M7; R0/R1/R2 one live run each; UL-on dump | none | pending |
| P7 | [QP fork and Testbed pickup](phase-07-qp-fork-and-testbed-pickup.md) | unit tests and forecast hash in the image; token gate | none | pending |
| P8 | [R3: TS xApp + QP fork, UL on](phase-08-r3-ts-xapp-qp-fork-ul-on.md) | R3 C1 | `r3-green` | pending |
| P9 | [Freeze pins, dev reference, M9 budget; then Stop B](phase-09-freeze-pins-dev-reference-m9-budget-stop-b.md) | reference committed; budget table | none | pending |
| P10 | [M9: unattended run from fresh-install](phase-10-m9-unattended-run-from-fresh-install.md) | M9 acceptance | none | pending |

Dependencies: strictly sequential on the VM, P0→P1→…→P10. Host-side QP-fork code (P7 steps that need no VM) may start any time after P0. P6 precedes P7 because QP needs a UL-on Influx dump (a UL-off dump has a constant UL series and `adfuller` raises). R0–R2 never wait for N4.

**Segments.** The user starts `/goal` three times with the same opener. Segment 1: P0–P4, ending at Stop A. Segment 2: P5–P9, ending at Stop B. Segment 3: P10. A PAUSE ends the goal; the user releases it by re-issuing the same opener (preferably after `/clear`).

## Stops and pause triggers
Every stop and trigger ends the turn with one terminal line and no further tool call:
`PAUSE <id> evidence=<path> journal=<path>`, with `<id>` one of `A, B, T1…T8`, printed as Claude's own final message (a marker quoted from a file or tool output never counts). Before printing it: write the journal in `docs/journals/`, get a kongming (opus) note, update the resume card and `implementation-notes.html`, and push. If kongming cannot be spawned or the push is refused, append `kongming=unavailable` or `push=refused` to the PAUSE line instead of retrying.

- **Stop A** (after P4): milestone report and journal; kongming segment review; disk ledger and M9 projection; any negative projection is raised here.
- **Stop B** (after P9): go/no-go journal plus kongming; the user rules on anything the M9 budget needs.
- **T1** a deletion outside the snapshot rule would be needed (a protected snapshot, or space the allowed deletions cannot free), or libvirt refuses a delete.
- **T2** a snapshot create or the M9 watchdog finds host free < 20 GB plus the next growth.
- **T3** a scope-guard mismatch, or an acceptance signal that cannot be met as written (for example, no feasible R3 schedule gives a QP-driven handover, Fallback-2 needed, kpimon needs a code change for the UL field, a resume-card mismatch).
- **T4** a new deviation from a standard outside P1–P7 and N5, or a needed spec missing from Zotero.
- **T5** an L-release failure.
- **T6** a Verify still fails after one kongming-guided fix, or the fix would change the outcome. A red C1 is re-run only after its root cause is recorded and a change committed, then as a full fresh set.
- **T7** a risk of the Influx token appearing in any public tree or committed file.
- **T8** a permission refusal of a scripted command. Never work around it.

**Report, do not pause:** substitution 1 or 2 applied; the re-set T_ctl and W values; the N5 match result; the BLAS library; kpimon field names for the UL metric.

## Phase-exit checklist (every phase)
1. Compare the deliverables with the locked contract in `goal-packet.md`. On a mismatch, PAUSE T3.
2. Update this file's status table and the resume card.
3. Update `implementation-notes.html` (decisions, deviations, trade-offs, open questions).
4. Push every fork SHA and the harness SHA; record them.
5. Record `scripts/vm/vm-snapshot.sh list`, `df -h /home`, and the M9 disk projection (host free − dev overlays − M9 overlay ≥ 20 GB).
6. Confirm no orphaned ns-3, agent or capture process (PGID kill, then `pgrep -f <full path>` and `ss -Sanp` empty).
7. Fill the phase's standards-ledger rows.
8. Spawn kongming (`model: opus`) for a go/no-go on the next phase; record the report path, or "none needed: <reason>" only where this plan says so.

## Traceability

| Phase | Contract items | Acceptance signals | Facts (F) / assumptions (A) / prereqs (X) / user decisions (U) |
|---|---|---|---|
| P0 | In scope 3 (harness, M9 runner groundwork); constraints (disk, scripted gates) | lint clean; decoder fixture round-trip; disk baseline recorded | F: `vm-exec.sh:29` regex, `vm-common.sh:14` default root, `run-to-m7.sh:44-45` f7 collision, host checks only at `vm-snapshot.sh:34-36` and `gate-m0-host.sh:33` (verifier-2105 §7). F: probe pcap is gitignored (`evidence/.gitignore:2`). U: no planned deletions. Covers verifier-2105 defects 5, 6, 7. |
| P1 | In scope 1 (S0), N5 | C3, C4, C6 static-reject causes; free-run digest unchanged after D4; M5–M7 re-pass | F: in-handover refusal is synchronous (`lte-enb-rrc.cc:4519, 4493`). F: outage fallback writes no handover row (contract F5). U: causes per erratum; P4 recorded (agent maps AMF-UE-NGAP-ID → IMSI). Covers verifier-1723 #9, #12; kongming-1739 §5.2 (C2 identity), §5.3 (copy body key `0000000N0C`). |
| P2 | In scope 2 (S1) | C2, C7, C8 null-control; fault run (i); D2 freeze-then-fail | F: paused ns-3 for 900 s causes no E2 teardown (journal §6). Covers verifier-1723 #1, #10 (demo mode out of scope). |
| P3 | In scope 3, 7; R0 | R0 C1; D7 three paths; already-on-target refusal; G4 on every gNB agent + offline cell_map replay; Q2 null-control count first; T_ctl re-set | U: Q1/D7, Q2. F: e2term XER is uppercase hex (kongming-1739 §2 #11). Covers verifier-1723 #3, #5 (T_ctl), #6, #11; kongming-1739 §4 (route dumps, RestartCount). |
| P4 | R1 | R1 C1: same-step pair, same-IMSI pair via one agent (lower targetCellId), R1(d) two agents (lower nodeId), unknown IMSI, fault run (ii) | Covers verifier-1723 #2; kongming-1739 §2 (R1(d)). U: no `r1-green`; Stop A kept. |
| P5 | In scope 6, 7; R2 | R2 C1 positives; negatives by ledger count + late = 0; W measured; stray-ack probe result | F: TS xApp registers only 20010/30002/30003 and may double-free on a stray ack (kongming-1739 §5.1). F: `stoi(ue_id)` unguarded (§5.4). U: probe first, substitution 2 only on crash; R2 negatives stricter. Covers kongming-1739 §5.1, §5.4, §5.6. |
| P6 | In scope 4 (N4, amended 00:14) | free-run with UL off unchanged (traces equal; IPC equal minus the two new fields); M5–M7; one live run each of R0/R1/R2; UL-on dump with both series varying | U: N4 by R3; `DRB.PdcpSduVolumeUL` and `DRB.PdcpSduVolumeDL`, INTEGER, kbit, PDCP SDU level (decision record 00:05 and 00:14 amendments). F: UL Rx at `McEnbPdcp::DoReceivePdu`; DL counter PDU-level and CSV-only; kpimon needs no code change. A: no double count through X2 (V3 measures it). Covers verifier-2105 defect 4. |
| P7 | In scope 5 (QP fork, N2, N3, N7, G1, G7) | unit tests + forecast hash in the image; empty tree diff for commit 1; no-token gate | U: N2, N3, N7. F: installer `cd qp` needs NAME=qp; Dockerfile and token sed stay at install time (verifier-1723 #8). Covers verifier-1723 #8; kongming-1739 §5.5 (uppercase cellKey). |
| P8 | R3 | R3 C1; ≥ 1 QP-driven handover; forecast hash equal; QP digest + `pip freeze` in verdict; HandoverStart = applied; 0 rows in null-control; N6 16-step predicate; W from calibration | Covers verifier-1723 #4, #5 (W); kongming-1739 §4 (R3 vacuity, schedule from the UL-on dry run). |
| P9 | M9 groundwork; constraints (disk) | reference committed at frozen pins; M9 budget table | F: deleting a non-leaf snapshot frees almost nothing (P5 housekeeping README, Lesson). A: M9 overlay ≈ 40 GB (measured at P8). Covers verifier-1723 #7 (no automatic deletions); verifier-2105 defect 5. |
| P10 | M9 | exit 0; verdict lists M0–M7, R0–R3; R0–R2 one live run each; R3 full C1 equal to the reference; min host free ≥ 20 GB | U: M9 depth (Q3 default). F: `r3-green` exists before the revert. |
| all | constraints; records | standards ledger per phase; journals; README/docs | U: standards rule (decision record §1); P1–P6 recorded. Covers verifier-2105 defects 1 (permissions, preflight), 2 (terminal PAUSE lines), 3 (Failure Protocol + go/no-go), 8 (spec reads), 10 (packet in plan dir). |

| P1–P4 | C5 (pairing by requestorId/instanceId; acks via viaNodeId) | `c5.pairsByReqId`, `c5.answerViaNodeId` in every rung verdict | Review K10. |
| — | verifier-2105 defect 9 | none (dropped) | Answered from the records (kongming-2105 §2, class d). |
| all | review K1–K27 | per phase "Review amendments" blocks | Classified in `plans/reports/review-261023-0009-…`. |

### Decision-record overrides → phase
Q1/D7 → P3, P4 (P8 records P1). Q2 → P3. N1 (gate on the wire) → all. N2, N3, N7 → P7. N4 → P6, P8. N5 → P1, P3. N6 → P8. Erratum (agent-local causes) → P1. P4–P7 → run report in P10. Snapshot rule (01:03) → P0, P9, P10. C1 reading (01:03) → P2, P3, P4, P5, P8. DL PDCP row (00:14) → P6, P7. Standards rule → every phase's ledger.

## Cross-cutting rules (every phase)
- **Evidence.** A gate is green only on decoded wire bytes (tshark with `-d sctp.port==36422,e2ap`, the KPM decoder harness, the P0 RC decoder), the ledger, ns-3 traces and digests. Logs are supporting evidence only. Evidence goes to `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/<gate>/<UTC-ts>/` through `EVIDENCE_HOST_ROOT`, scrubbed by `scripts/gates/scrub-evidence.sh`. Pcaps stay out of git, with a sha256 manifest.
- **Capture, NIST calls, bring-up, process hygiene:** unchanged from the M0–M7 plan (K3, K6, K10, K14 in `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/plan.md`).
- **RIC state is a measured precondition.** Each run: reset rc, the TS xApp, QP and a fresh Influx bucket; restart the TS xApp only after every agent is CONNECTED, then set the A1 threshold; dump rtmgr routes at start and end; record the 12041/12042 −1 owner in `verdict.json`; RestartCount = 0 for rc, TS xApp, QP, kpimon, hw-go and every agent. Bounded, logged retries only for bring-up preconditions, never for C1.
- **Snapshots.** `scripts/vm/vm-snapshot.sh create <name> --need-gb <n>` only after the free-space check. Deletions only under the snapshot rule in the invariants card. `r3-green` must exist before P10 reverts.
- **Disk.** Host free ≥ 20 GB at all times. Every phase exit updates the M9 projection. A negative projection is reported at Stop A and settled at Stop B, where the user frees the measured shortfall (user, 01:30 KST). T2 fires only when actual free space would cross the floor.
- **Permissions.** Auto mode with no rules file, as in M0–M7 (user, 01:30 KST). A classifier refusal is T8.
- **Background VM jobs** run through `vm-exec.sh` (detached unit, polled), each with a hard timeout.
- **Standards.** Every new technical decision gets a ledger row (decision → document, version, section → Zotero key → read date), read through zotero-mcp, before its code lands. References: E2SM-RC v03.00 `XRWZU3SS`, E2SM common v07.00 `QW6VJ83M`, E2SM-KPM v03.00 `F82PYZVK`, E2AP v03.00 `WEE5IEXF`, 3GPP TS 28.552 V20.2.0 `5SZUBP6M`, 3GPP TS 36.423 `83VGITYK`/`M8YTSAQS`. A missing document is T4.
- **Code delivery.** Branch `dev/l-release-nist180` on ns-3, oran-interface, the Testbed (agent, installer) and the QP fork; WIP pushes allowed. Gate runs clone at the `scripts/pins.conf` SHAs. Conventional commits, no AI references, never `chore`/`docs` for `.claude` changes, no bare `git stash`.
- **Advisors (`--advice`).** kongming (`model: opus`, xhigh) on the first failed Verify (Failure Protocol in every phase file), at every design fork the plan does not settle, at every phase exit (go/no-go), at Stops A and B and every PAUSE, before P6's UL counter lands, and before P10. Every `ak:plan`, `ak:cook` or `ak:fix` call inside `/goal` passes `--advice`. kongming's counsel never counts as user approval.
- **L only.** On an L failure: stop, find the root cause, report (T5).

## Warmup decisions
1. **W1, contract copy in the plan dir.** The locked contract is written verbatim into `goal-packet.md` here, a departure from the skill's session-only default, because a `/goal` started after `/clear` cannot see the warmup chat (M0–M7 precedent, kongming-2105 §1).
2. **W2, terminal PAUSE lines.** Stops and triggers are terminal transcript lines so the `/goal` evaluator, which reads only the transcript, can see them.
3. **W3, M9 depth.** One live run on each of R0–R2 (C2–C9) and the full C1 on R3 (kongming-2105 Q3 default, accepted in the brief).

## Contract-preserving review
Collect-only kongming review (opus), classified before any edit: `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.

## Rollback
Environment: revert to the phase's start snapshot (`f7-rerun-green`, `r0-green`, `r2-green` or `r3-green`), always with the VM shut off first. Code: revert commits on the fork branch (no history rewrite of pushed branches without the user). Pacing and UL traffic are opt-in, so the free-run default is the rollback for the ns-3 and agent changes. Nothing on the host changes.

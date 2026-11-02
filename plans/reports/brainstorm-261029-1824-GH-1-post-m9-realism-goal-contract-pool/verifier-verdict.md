# Verifier verdict: post-M9 realism contract (9 candidates)

**Winner: D**, with a **low** margin. A is the runner-up and is the more faithful candidate on the δ = 0 ruling. **Unanimous: no.** **Confidence: medium.** The top tier (D, A, F, C) is clearly separated from the bottom tier (B, E, H, I). The order inside the top tier is sensitive to how heavily criterion 1 weighs the δ = 0 ruling.

No files were written, no git, ssh or virsh was used, and no de-anonymizing files were opened. The memory write was skipped because the brief required read-only.

## Spot-checks on the claims that split the candidates

**(a) Can "δ = 0 byte-equal" survive the T-A fixes?**
- The committed reference pins more than the simulator output:
  - `reference/r3p/equal/digests.json` pins `ledger`, `ipc{1,2,3}`, 36 trace files, and `extra{collet-start-time, kpm-headers, rc-multiset}`.
  - `files.json` pins `predictor-records`, `scenario` and `schedule`.
  - `ts-rung-lib.sh:207-221` runs `reference-compare.py` over all of these.
  - `rc-multiset` holds viaNode, imsi and target (`wire-c1-extract.py:9-13`). The ledger holds `viaNodeId` (`e2-control-hub.cc:289-290`).
- So unconditional P1, P4 and P11 fixes must break literal equality. Literal equality survives in only three ways:
  - compat switches or a profile (A, B, E, F, H);
  - a second compat build (I);
  - a checkpoint before T-A lands (C, D).
- G has no literal check at all: it compares through a projection and may exempt r3p.

**(b) P10 send path.**
- The agents send through their own `SctpAssociation::send` → `::send` (`ns3_e2_agent/src/sctp-association.cpp:147`, called from `e2-session.cpp:81,179,200`).
- `main.cpp:4-6` states that libe2sim's send path is never used. `e2sim_sctp.cpp:224-228` is not on the agents' path.
- The packet's and the run report's P10 location is therefore wrong. A, C, D, F and G corrected it. H repeats the error, marking `e2sim_sctp.cpp:228` [V] as "the current sender".
- A's byte-order point is correct: `e2sim_defs.h:29` defines `X2AP_PPID` as `htonl(27)`.

**(c) Scale-gate N needed to exceed `maxNeigh`.**
- `m_l3sinrMap[imsi]` includes the serving cell (`mmwave-enb-net-device.cc:939, 971-977`), and the cap is `E2SM_REPORT_MAX_NEIGH = 8` (`.h:71`).
- N = 9 gives exactly 8 non-serving cells, which reaches the cap but does not exceed it. **N ≥ 10 is required.**
- C's [I] is also correct: at map size 8 the padding loop writes one triple too few.
- A, C, D, F and G test the cap (a report carries 8 while 9 or more cells are heard). That matches the ruling's "the neighbour cap stay untested" (`run-report:74`).
- B, E, H and I require 9 or more neighbours in a KPM report "without truncation". That needs a cap change they neither plan nor check against the spec.

**(d) Does measurement-time stamping have an in-scope consumer?** None.
- R3′ keys on `ns3.nodeId` / `ns3.seq` (`r3p-scenario.json:9-10`).
- Joins never use `_time` (`gate-m6-kpm.sh:12`).
- `check-n6-influx-window.py:100` keys on seq.

It also carries two hazards:
- kpimon points carry no tags (no `AddTag`; `SetTime(time.Now())` at `control.go.previous:959,980`). The colletStartTime is the same across nodes, and the epoch is pinned to 2026-01-01 (`rung-config.json:49`). Stamping by measurement time would therefore overwrite rows across nodes.
- Those rows would also fall outside the harness's wall-time range queries (`agents-ns3-run.sh:161`).

**A's AC10 has the collision argument backwards.**

**(e) The M9 burst used for h.**
- In `free-series.tsv`, free space fell from 84 to 72 GiB between 17:50:07Z and 17:55:37Z. That is 12 GiB inside the 370 s stop-path window, and 11 GiB inside any 300 s window.
- The largest single 30 s step is 2 GiB. That is the "0.067 GiB/s rounding artefact".
- How each candidate handles it:
  - D's h = 12 is exactly right.
  - A, C and G use a windowed method that would yield 11–12 GiB, but they budget for or expect 9.
  - F hard-codes 9. Its citation is correct: `m9-budget.json:105-106` currently holds 4 / 29.
  - E and I propose 25 by extrapolating the 2 GiB rounding step, which is over-conservative.

## Per-candidate scores

Criteria: C1 faithfulness, C2 evidence, C3 acceptance-criteria sharpness, C4 feasibility and budget, C5 standards, C6 unknowns, C7 conditional fields.

| Cand | Hard constraints | C1 | C2 | C3 | C4 | C5 | C6 | C7 | Total |
|---|---|---|---|---|---|---|---|---|---|
| **D** | pass (H3 conditional) | 16 | 18 | 16 | 17 | 18 | 17 | 19 | **121** |
| A | pass | 18 | 18 | 17 | 15 | 16 | 17 | 17 | 118 |
| F | pass | 14 | 18 | 18 | 15 | 17 | 16 | 18 | 116 |
| C | pass (H3 conditional) | 14 | 17 | 18 | 14 | 16 | 17 | 17 | 113 |
| G | **FAIL H3** | 11 | 16 | 15 | 15 | 16 | 15 | 16 | 104 |
| E | pass (scale caveat) | 15 | 13 | 11 | 10 | 13 | 14 | 13 | 89 |
| B | pass (scale caveat) | 15 | 12 | 11 | 11 | 12 | 14 | 13 | 88 |
| I | **FAIL H4** | 14 | 13 | 11 | 10 | 13 | 14 | 13 | 88 |
| H | pass (scale caveat) | 15 | 10 | 11 | 11 | 11 | 14 | 13 | 85 |

### D
- **Verified [V] citations:** `run-to-m9.sh:122`, `gate-m0-host.sh:46-52`, `agents-ns3-run.sh:161`, `e2ap-builders.cpp:110` (29-bit ID today), upstream `ts_xapp.cpp:366`, `sctp-association.cpp:147`, and the computed 84→72 GiB burst. One slip: L_max is cited at `rung-config.json:15,19`; the lines are :14 and :18.
- **Routed challenges:** each is backed by evidence and routed to the user (Q1–Q3):
  - B1/SUB-1: δ = 0 equality checked through field transforms after T-A, with the literal-forever option (legacy wire switches) named;
  - B2: h = 12;
  - B3: measurement-time stamping out.
- **Budget:** the most accurate. It counts the last leak of the post-M9 overlay and its deletion under the ruling, and it sets a start condition of X′ − T′ ≥ 0.
- **Trade-offs:** both tables are complete, including worst cases.
- **Extras:** the E2SM-RC Style 5 point for P1 is recorded as a candidate only (the vault key `JRDTL7XS` exists; the clause text was not re-verified). The check-diff ledger (AC18) guards against weakened tests.

### A
- **Verified [V] citations:** more than 12 checked, all accurate (`e2-control-hub.cc:287-290, 356, 228-229`, `wire-c1-extract.py:9-13`, `rc-lib.sh:35, 111-123`, `epc-mme-application.cc:112`, `e2sim_defs.h:29`, and others). One near-miss: `control.go.previous:957` is the commented copy; the live line is 959.
- **Faithfulness:** the most faithful candidate. A compat profile keeps the end-run regression `equalsReference: true` against the unchanged `reference/r3p/`, and A includes both optional items.
- **Defects:**
  - AC10 makes measurement-time stamping mandatory for the P12 gate on the inverted collision argument (see (d)).
  - The budget uses h = 9, although A's own window method gives 11–12.
  - The dual compat modes in the agent, rc and the TS xApp are a heavy implementation cost.

### F
- **Verified [V] citations:** all checked are accurate. They include `m9-budget.json:105-106`, `check-n6:100, 37-38`, and `gate-r3p-ts-predictor.sh:234`. That last one is a unique catch: the check `..._via_target_...` encodes P1, so fixing P1 means rewriting it.
- **Strengths:**
  - the strongest H3 design: a runtime baseline profile, with r0, r1 and r2 equal as well;
  - correct reasoning on measurement-time stamping;
  - the tie rule for δ values that are multiples of T.
- **Defects:**
  - measurement-time stamping is moved to Non-goals and never asked as a user question, so it is an unrouted cut;
  - AC4 hard-codes h = 9, below M9's measured 12 GiB burst;
  - it assumes a "leak-free revert" [C].

### C
- **Verified [V] citations:** `digests.json` / `files.json`, `ts-rung-lib.sh:207-208`, `r3p-scenario.json:9-10`, `control.go:548-553`, `goal-packet.md:26`, and the architecture doc `:200`.
- **Strengths:** the N = 10 analysis and the padding finding are right, and the end-run step list is the most concrete of any candidate.
- **Defects:**
  - Its "E0 + v2" reading of δ = 0 is routed (Q2), but its evidence leaves out the compat-switch option ("equality can hold only before those fixes land" is overstated).
  - Measurement-time stamping is made conditional without asking the user.
  - It claims fixing follow-up 2 frees the post-M9 overlay, which is wrong: that overlay is already untracked.

### G
- **Fails H3.** AC20 never asserts literal equality with M9: ledger and extra are compared after a projection, and r3p may be exempted. This contradicts G's own constraint that every default reproduces M9.
- Measurement-time stamping is cut without routing.
- On the plus side, its [V] citations are good (`replay-ts-cell-map.py:4-13`, `main.cpp:4-6`, `e2-ipc-message-encoder.cc:236`), and its P7 note (a 2-octet header gives the same bytes) is useful.

### E
- Its compat fixture passes H3.
- Its [V] citation `free-series.tsv:143-144` is accurate, but h = 25 extrapolates the rounding artefact. That drives its disk estimate to 105 GiB or more, and it has no plan to reclaim space.
- The acceptance criteria are bundled and vague. T-A runs before the compat proof. The scale criterion needs a cap change.

### B
- Its compat profile passes H3, and its few [V] citations are accurate.
- The acceptance criteria are vague ("correct EN-DC mobility owner").
- The scale criterion requires 9 or more neighbours with no truncation allowed.
- Disk: it needs 89 GiB or more against 59 GiB with no bridging plan. It also requires 3 live runs per δ value.

### I
- **Fails H4.** AC4 limits PPID 70 to "every realism live capture", which narrows the ruling of "every live capture" and exempts its compat build.
- Running two installations in the end run is costly. The scale criterion has the cap conflict. The acceptance criteria are vague.

### H
- Its [V] claim about the P10 sender (`e2sim_sctp.cpp:228`) is factually wrong for the agents.
- The scale criterion has the cap conflict, and it assumes no space can be recovered from the leaked overlay.
- Otherwise it is faithful (compat profile, measurement-time stamping in).

## Ranking
D (121) > A (118) > F (116) > C (113) > G (104, ineligible: H3) > E (89) > B (88) ≈ I (88, ineligible: H4) > H (85).

- **Winner:** D.
- **Runner-up:** A.
- **Margin:** low.
  - D leads A by 3 points in total.
  - On the deciding criteria C1, C4, C5 and C7, D leads by 70 to 66, which is not more than 5.
- **Unanimous:** no.
  - A tops C1.
  - C and F top C3.
  - A and F tie D on C2.

## Winner (D) defects the controller must surface to the user

1. **δ = 0 ruling narrowed.**
   - Literal equality with the committed `reference/r3p` is proven only once, at the AC8 dev checkpoint before T-A. After that, SUB-1 replaces it with equality after field transforms.
   - The user must choose between SUB-1 and legacy wire switches (literal equality forever, which is A's and F's compat-profile route).
   - If the user chooses literal equality, then:
     - AC12, which answers the 9-octet form with `control-message-invalid`, conflicts with a compat mode and must change;
     - the end-run step set must add a compat regression with `--reference reference/r3p`.
2. **Measurement-time stamping excluded** (B3, routed as Q3), although the user offered it inside T-B. The evidence holds (see (d)). If the user keeps it, it needs kpimon tags and a change to the harness range queries.
3. **h = 12 (SUB-H) challenges the ruled h ≈ 9.** The evidence is verified, and the change adds about 3 GiB to the disk requirement T′.
4. **AC19 (end run) is under-specified.**
   - "Top rung equals its committed reference" does not say which reference.
   - It omits `minHostFreeGb ≥ 25` and `RestartCount = 0`.
   - The exact end-run step list and the number of δ-sweep steps in the end run are not listed, and the wall budget depends on them.
5. **The Outcome text lets a P item end "listed with evidence"**, which is a loophole against the ruling to fix the T-A and T-C items. Only an approved substitution should allow that.
6. **P11 gNB ID length of 32 bits** (4-bit cell part, aligned to the TS xApp's key [I]). Most other candidates recommend 28 + 8. D defers the choice to warmup approval, but it is not in the unresolved questions. It needs an explicit user decision.
7. **The P12 gate (RP 1 s, GP = T, 10 records) depends on kpimon decoding multi-record Format 1.** Stock kpimon treats measData items as "cells" (`control.go.previous:752-766`). D has no fallback; A's substitution 6 and F's substitution (d) do.
8. **AC8 assumes P12 at T/T is byte-neutral [I].** If it is not, the literal checkpoint fails.
9. **The P1 fix requires rewriting `gate-r3p-ts-predictor.sh:234`** (the `via_target` check). D's AC18 check-diff ledger covers this only in general terms; it should be named as a contract change registered before code lands (as F does).
10. **Unverified items still open:**
    - whether e2mgr accepts the en-gNB and eNB node types (a refusal could block P5);
    - rc's panic on an ACK without an outcome, and its 2 s timer at `a2282ee` (AC6 checks these before δ > 0);
    - the 10-gNB cost;
    - the KPM v03.00 and RC Style 5 clause text;
    - Codex accounting: the A1 precedent says runs made before the contract were not counted (`goal-packet.md:26`, verified).
11. **Small citation slip:** `rung-config.json:15,19` should be :14 and :18.

## Unresolved questions
- Should the δ = 0 ruling be read as literal equality in the end run (pushing toward A or F) or as "literal equality before T-A" (C, D)? With low margin, this one user preference can flip D and A.
- Should the scale ruling be read as "exercise the cap" (A, C, D, F, G) or "a report with more than 8 neighbours" (B, E, H, I)? I scored the first as the faithful reading.

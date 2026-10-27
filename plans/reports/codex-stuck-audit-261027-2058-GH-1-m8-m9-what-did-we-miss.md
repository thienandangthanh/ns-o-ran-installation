# Codex stuck audit: what did we miss? (M8–M9, at PAUSE T8), 2026-10-27 20:58 KST

Requested by the user ("what did we miss? codex audit"). Codex ran read-only (`task --fresh --effort high`, codex-cli 0.163.0) against parent `0230254`. It made no edits, used no SSH and read no secret values. Its live libvirt reads were denied, so VM, pod and snapshot state is taken from the records. Brief: session scratchpad `codex-stuck-audit-brief.md`. I verified every cited line below before triage. Nothing was changed in code; this ledger is the only output.

## Verdict (Codex)
M9 is conditionally reachable, but it is not ready to run as contracted. P6 is still open, P7 has only local commit 1, and R3 feasibility is unproved. The top risks:
- QP's green window rule does not prove that its model can train.
- The N4 judges, and the draft M9 runner, can accept incomplete evidence.
- QP delivery is blocked by T8, and the disk budget is negative.

## Triage
| Id | Sev | Finding | Verified at | Decision | Resolution |
|---|---|---|---|---|---|
| F01 | blocker | The QP fork commit `901f8c5` is unpushed (T8), and `QP_URL`/`QP_SHA` are not yet in `pins.conf` | `evidence/p7/20261027T034000Z/t8-refusal.json`; `scripts/pins.conf` | Escalate (already the open T8 question) | The user picks the release mechanism; then retrieve every QP pin anonymously and verify it |
| F02 | blocker | The host disk watchdog trips below **25 GB** (`host-disk-watchdog.sh:16` `min_gb=25`), but P9 budgets only to the 20 GB floor. A budget P9 accepts can still stop M9 early | `scripts/vm/host-disk-watchdog.sh:16`; phase-09 | Accept | At Stop B, budget for 25 GB plus measured growth, re-measured after P8. The user frees the space. Amend P9 text on resume |
| F03 | high | V5 green does not prove QP trains: `constant()` drops constant columns only in its temporary frame, while training runs ADF on the original columns, and statsmodels 0.14.6 rejects constant input. Also, the null-control dump cannot show windows after handovers change UE membership | `ric-app-qp/src/qptrain.py:55,81,130`; kongming-1300 §3 | Accept; escalate the option | Before R3: show model creation, deterministic forecasts and one applied QP-driven handover with the exact image and schedule, and check every actual trigger window. Option B needs this evidence; A, C and D need a user ruling |
| F04 | high | The V3 judge (`check-pdcp-volume-totals.py`) passes when a whole gNB cell's samples are missing, or the tail is truncated. Residual bits are ungated, and A4 needs only that some samples exist. Codex reproduced this in memory on `031836Z`: dropping node 3 → PASS (422 Mbit residual); dropping the last half → PASS | `check-pdcp-volume-totals.py:124,141` | Accept (my judge is too weak; no waiver needed) | Require the expected gNB nodes and every seq 1..N per node. Allow residuals only after each UE's verified final read. Add missing-cell and truncated-tail fail fixtures. Re-judge `031836Z` with the hardened judge |
| F05 | high | The V5 judge skips windows that contain a missing seq (deleting seq 50 left 138 windows, still PASS; keeping only the last 16 seqs also passed), and overwrites duplicate keys. The dump part compares IPC with IPC, never Influx with IPC, after a fixed 5 s drain. `influx-vs-trace.py`'s exit judges only 3 samples | `check-n4-v5-windows.py:105,118`; `gate-n4-ul-metric.sh:144`; `tools/e2-evidence/influx-vs-trace.py:184` | Accept (extends kongming D1–D3) | Before the one-shot dump: fail on any missing seq in the expected range and on duplicate (node, seq); require a full, duplicate-free Influx = IPC equality including the G1 UE fields; bound the drain by an observed row count, not a sleep; take the UL pattern from `rung-config.json` and assert CAL used `steps`; add raw annotated-CSV type fixtures |
| F06 | high | The cause of the r2 single red is undiagnosed. Sequence: HTTP 404 in the a1mediator-restart helper, then `ts_policy_type_ensure` creates 20008 (HTTP 201), then live checks pass. r2 resets a1mediator before ensuring the type (`gate-r2:107,114`); the helper assumes the type persists (`ts-lib.sh:347`). Fresh M9's i2 ensures the type before restarting, so recurrence in M9 is not established | evidence `r2/20261027T041111Z` | Accept | On release, under the phase-06 Failure Protocol with kongming: find when the type disappears, fix the order or the cause, then get a fresh green r2 single (the standing ruling gives the fix budget) |
| F07 | high | The draft `run-to-m9.sh` verdict passes on any non-empty all-pass step list with no watchdog trip. It does not require the full M0–M7/R0–R3 set, the R3 C1 fields, reference equality, or a valid min-free value; a `--from/--to` subset gets "PASS". There is no global deadline (P9 requires one) | `scripts/run-to-m9.sh:94-119`; phase-09:13 | Accept | Make the contract's M9 acceptance executable in the runner: exact step set, R3 C1 pass, R3 = reference, min free ≥ 20 GB present. Mark partial runs as not-M9. Add measured per-gate and global timeouts. Do this before the P9 freeze |
| F08 | high | Watchdog absence counts as success: there is no readiness or liveness check, `minHostFreeGb` may be null without failing, and 60 s polling needs a growth bound to support "throughout" | `run-to-m9.sh:95,119`; `host-disk-watchdog.sh:57` | Accept | Fail closed on a missing or stale watchdog; require the min-free record; justify the polling margin from measured growth and shutdown delay |
| F09 | high | Evidence export fails open: the scrubber silently tolerates an unreadable token file (`except Exception: pass`), and `vm-exec.sh` ignores scrub failure (`…; true`) before copying evidence to the public repo | `scripts/gates/scrub-evidence.sh:24-27`; `scripts/vm/vm-exec.sh:81-83` | Accept (T7-adjacent hardening) | Block export when the exact-secret scan cannot run or the scrub fails. History of `f2138f0` stays a separate user decision |
| F10 | medium | The records lag the rulings: P10's run report lists only "P1–P7 and N5" and omits approved deviations P8 and P9; the packet requires `substitution3Applied` in every verdict, but only i2 and r2 emit it | phase-10:60; `grep substitution3Applied scripts/gates/*.sh` → 2 files | Accept | Reconcile before the P9 freeze: P10 lists P1–P9 and N5; every rung and M9 verdict carries `substitution3Applied` |

Rejected: none. Every finding was verified at the cited lines; no finding reverses a user decision.

## Checked and fine (Codex, with citations in its output)
- Every contract scope area has an owning phase and check.
- V2 strips exactly the two keys and reproduces `22570657bd39…`.
- The fallback selection was pre-registered: `533b404`, `b153b45` and `55e7f57` all precede `031109Z`.
- V3's arithmetic and tie rejection are sound on complete inputs.
- The regression records match the resume card.
- The submodule pointers in the parent are older by design, because the pins live in `pins.conf`.
- No unauthorized decision was found in the N4 choices; P9 and the V3/V5 amendments were approved.
- No extra C1 re-pass is owed after the approved judge edit.
- The protected-snapshot guards are present.

## What changes for the plan (on release; not applied now, goal paused at T8)
1. Harness hardening before any more P6 VM work: F04, F05 (with kongming D1–D4) and F09. Then re-judge the archived n4 runs; that is a judge change, so the evidence is re-read, not re-run.
2. The r2 single red: Failure Protocol with kongming (F06).
3. P7/P8: the in-image QP training proof (F03) after the user picks a training option.
4. P9: runner acceptance and timeouts (F07); watchdog fail-closed (F08); budget at 25 GB plus growth (F02); record reconciliation (F10).

## Unresolved questions for the user
1. Which mechanism releases the refused QP push (T8)?
2. QP training under the constant gNB-cell DL: option B only, or B with A pre-authorized as fallback (or C/D)?
3. At Stop B: how much space can be freed while keeping the protected snapshots and the 25 GB watchdog margin?
4. Should the historical artifacts in commit `f2138f0` stay public, or get a separately authorized history cleanup?
